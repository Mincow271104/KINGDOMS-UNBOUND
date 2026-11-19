class_name TerritoryManager
extends RefCounted

## Authoritative Town Hall-based Kingdom Territory & Expansion System.
## Owns and maintains `world_data.owned_cells` (64x64 bool grid) and caches
## border cells and walkable owned cells per revision.

signal territory_changed(new_level: int, owned_count: int, revision: int)

var _world_data: WorldGenerator.WorldData = null
var _revision: int = 0
var _current_level: int = 0
var _current_radius: int = 0
var _owned_count: int = 0
const RECOVERY_EXPANSIONS_PER_FRAME: int = 160
const RECOVERY_SLICE_PER_CITIZEN: int = 64

var _cached_owned_cells: Array[Vector2i] = []
var _cached_border_cells: Array[Vector2i] = []
var _cached_walkable_cells: Array[Vector2i] = []
var _cached_walkable_revision: int = -1
var _cached_walkable_nav_ref: GridNavigation = null

# Incremental recovery search scheduler (shared per-frame work budget)
var _nav_revision: int = 0
var _recovery_requests: Dictionary = {}
var _recovery_queue: Array[String] = []
var _recovery_frame_id: int = -1
var _recovery_budget_remaining: int = RECOVERY_EXPANSIONS_PER_FRAME
var _recovery_manual_frame: int = 0


func initialize(p_world_data: WorldGenerator.WorldData) -> void:
	_world_data = p_world_data
	_cached_walkable_revision = -1
	_cached_walkable_nav_ref = null
	recalculate_territory()


func recalculate_territory() -> Dictionary:
	if _world_data == null:
		return {"level": 0, "radius": 0, "owned_count": 0, "revision": _revision}
	_nav_revision += 1
	_invalidate_stale_recoveries()

	var map_w: int = _world_data.map_width
	var map_h: int = _world_data.map_height
	if _world_data.owned_cells.size() != map_w or (map_w > 0 and _world_data.owned_cells[0].size() != map_h):
		_world_data.owned_cells.clear()
		for x in range(map_w):
			var col: Array[bool] = []
			col.resize(map_h)
			col.fill(false)
			_world_data.owned_cells.append(col)
	else:
		for x in range(map_w):
			for y in range(map_h):
				_world_data.owned_cells[x][y] = false

	var max_th_level: int = 0
	var anchors: Array[Dictionary] = []
	for b in _world_data.buildings:
		if not (b is Dictionary):
			continue
		if str(b.get("type", "")) != "townhall":
			continue
		# Only active/damaged completed Town Halls project territory; destroyed or under-construction do not.
		var b_state: String = str(b.get("state", "active"))
		if b_state == "destroyed" or b_state == "under_construction" or not bool(b.get("is_constructed", true)):
			continue
		var lv: int = clampi(int(b.get("upgrade_level", 1)), 1, EconomyConfig.MAX_BUILDING_LEVEL)
		var rad: int = EconomyConfig.get_territory_radius(lv)
		var origin: Vector2i = b.get("cell", b.get("origin", Vector2i.ZERO))
		var size: Vector2i = b.get("size", Vector2i(3, 3))
		var center := Vector2i(origin.x + size.x / 2, origin.y + size.y / 2)
		anchors.append({"center": center, "radius": rad, "level": lv})
		if lv > max_th_level:
			max_th_level = lv

	var new_owned: Array[Vector2i] = []
	for anchor in anchors:
		var center: Vector2i = anchor["center"]
		var rad: int = int(anchor["radius"])
		var min_x := maxi(0, center.x - rad)
		var max_x := mini(map_w - 1, center.x + rad)
		var min_y := maxi(0, center.y - rad)
		var max_y := mini(map_h - 1, center.y + rad)
		for x in range(min_x, max_x + 1):
			for y in range(min_y, max_y + 1):
				var dist: int = absi(x - center.x) + absi(y - center.y)
				if dist <= rad and not bool(_world_data.owned_cells[x][y]):
					_world_data.owned_cells[x][y] = true
					new_owned.append(Vector2i(x, y))

	_cached_owned_cells = new_owned
	_owned_count = new_owned.size()
	_current_level = max_th_level
	_current_radius = EconomyConfig.get_territory_radius(max_th_level) if max_th_level > 0 else 0

	var borders: Array[Vector2i] = []
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for cell in new_owned:
		var is_border := false
		for d in dirs:
			var n := cell + d
			if n.x < 0 or n.y < 0 or n.x >= map_w or n.y >= map_h:
				is_border = true
				break
			if not bool(_world_data.owned_cells[n.x][n.y]):
				is_border = true
				break
		if is_border:
			borders.append(cell)
	_cached_border_cells = borders

	_revision += 1
	_cached_walkable_revision = -1
	territory_changed.emit(_current_level, _owned_count, _revision)

	return {
		"level": _current_level,
		"radius": _current_radius,
		"owned_count": _owned_count,
		"revision": _revision,
	}


func is_cell_owned(cell: Vector2i) -> bool:
	if _world_data == null:
		return false
	if not _world_data.is_in_bounds(cell):
		return false
	if _world_data.owned_cells.size() != _world_data.map_width:
		return false
	return bool(_world_data.owned_cells[cell.x][cell.y])


func is_footprint_owned(origin: Vector2i, size: Vector2i) -> bool:
	if size.x <= 0 or size.y <= 0:
		return false
	for ox in range(size.x):
		for oy in range(size.y):
			if not is_cell_owned(origin + Vector2i(ox, oy)):
				return false
	return true


func get_owned_cells() -> Array[Vector2i]:
	return _cached_owned_cells


func get_border_cells() -> Array[Vector2i]:
	return _cached_border_cells


func get_walkable_owned_cells(nav: GridNavigation) -> Array[Vector2i]:
	if nav == null:
		return []
	if _cached_walkable_revision == _revision and _cached_walkable_nav_ref == nav:
		return _cached_walkable_cells
	var walkable: Array[Vector2i] = []
	for cell in _cached_owned_cells:
		if nav.is_cell_walkable(cell):
			walkable.append(cell)
	_cached_walkable_cells = walkable
	_cached_walkable_revision = _revision
	_cached_walkable_nav_ref = nav
	return _cached_walkable_cells


func invalidate_walkable_cache() -> void:
	_cached_walkable_revision = -1
	_nav_revision += 1
	_invalidate_stale_recoveries()

func advance_recovery_frame() -> void:
	_recovery_manual_frame += 1
	_recovery_budget_remaining = RECOVERY_EXPANSIONS_PER_FRAME

func _sync_recovery_frame_budget() -> void:
	var frame_key: int = int(Engine.get_process_frames()) + _recovery_manual_frame
	if frame_key != _recovery_frame_id:
		_recovery_frame_id = frame_key
		_recovery_budget_remaining = RECOVERY_EXPANSIONS_PER_FRAME

func _invalidate_stale_recoveries() -> void:
	for cid in _recovery_requests.keys():
		var req: Dictionary = _recovery_requests[cid]
		if req.get("result", {}).is_empty():
			req["result"] = {"status": GridNavigation.NearestSearchStatus.INVALIDATED, "path": ([] as Array[Vector2i]), "iterations": 0}
	_recovery_queue.clear()

func cancel_recovery(citizen_id: String) -> void:
	if citizen_id == "":
		return
	_recovery_requests.erase(citizen_id)
	_recovery_queue.erase(citizen_id)

func get_recovery_queue_size() -> int:
	return _recovery_queue.size()

func get_active_recovery_count() -> int:
	return _recovery_requests.size()

func get_recovery_budget_remaining() -> int:
	_sync_recovery_frame_budget()
	return _recovery_budget_remaining

func request_recovery(citizen_id: String, start: Vector2i, nav: GridNavigation) -> Dictionary:
	var empty_path: Array[Vector2i] = []
	_sync_recovery_frame_budget()
	if citizen_id == "" or nav == null or _world_data == null:
		return {"status": GridNavigation.NearestSearchStatus.INVALID_INPUT, "path": empty_path, "iterations": 0}

	if _recovery_requests.has(citizen_id):
		var existing: Dictionary = _recovery_requests[citizen_id]
		var existing_res: Dictionary = existing.get("result", {})
		if not existing_res.is_empty():
			_recovery_requests.erase(citizen_id)
			_recovery_queue.erase(citizen_id)
			if int(existing_res.get("status", GridNavigation.NearestSearchStatus.INVALIDATED)) != GridNavigation.NearestSearchStatus.INVALIDATED:
				return existing_res
		elif existing.get("start", Vector2i(-1, -1)) != start or int(existing.get("territory_rev", -1)) != _revision or int(existing.get("nav_rev", -1)) != _nav_revision:
			cancel_recovery(citizen_id)

	if not _recovery_requests.has(citizen_id):
		var st := nav.create_incremental_nearest_search(start, Callable(self, "is_cell_owned"), -1, _nav_revision)
		if st.status != GridNavigation.NearestSearchStatus.IN_PROGRESS:
			return {"status": st.status, "path": st.path, "iterations": st.iterations}
		_recovery_requests[citizen_id] = {
			"state": st,
			"nav": nav,
			"start": start,
			"territory_rev": _revision,
			"nav_rev": _nav_revision,
			"result": {}
		}
		_recovery_queue.append(citizen_id)

	_step_recovery_queue()

	if _recovery_requests.has(citizen_id):
		var cur_req: Dictionary = _recovery_requests[citizen_id]
		var cur_res: Dictionary = cur_req.get("result", {})
		if not cur_res.is_empty():
			_recovery_requests.erase(citizen_id)
			_recovery_queue.erase(citizen_id)
			return cur_res
		return {"status": GridNavigation.NearestSearchStatus.IN_PROGRESS, "path": empty_path, "iterations": int(cur_req["state"].iterations)}

	return {"status": GridNavigation.NearestSearchStatus.INVALIDATED, "path": empty_path, "iterations": 0}

func _step_recovery_queue() -> void:
	while _recovery_budget_remaining > 0 and not _recovery_queue.is_empty():
		var cid: String = _recovery_queue.pop_front()
		if not _recovery_requests.has(cid):
			continue
		var req: Dictionary = _recovery_requests[cid]
		if not req.get("result", {}).is_empty():
			continue
		if int(req.get("territory_rev", -1)) != _revision or int(req.get("nav_rev", -1)) != _nav_revision:
			req["result"] = {"status": GridNavigation.NearestSearchStatus.INVALIDATED, "path": ([] as Array[Vector2i]), "iterations": 0}
			continue
		var slice_budget: int = mini(_recovery_budget_remaining, RECOVERY_SLICE_PER_CITIZEN)
		var step_res: Dictionary = req["nav"].step_incremental_nearest_search(req["state"], slice_budget)
		_recovery_budget_remaining = maxi(0, _recovery_budget_remaining - int(step_res.get("step_expansions", 0)))
		var st_code: int = int(step_res.get("status", GridNavigation.NearestSearchStatus.UNREACHABLE))
		if st_code == GridNavigation.NearestSearchStatus.IN_PROGRESS:
			_recovery_queue.append(cid)
		else:
			req["result"] = step_res


func get_current_territory_level() -> int:
	return _current_level


func get_current_radius() -> int:
	return _current_radius


func get_owned_count() -> int:
	return _owned_count


func get_revision() -> int:
	return _revision
