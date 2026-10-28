class_name TacticalMilitaryManager
extends RefCounted
## Tactical Military Manager (Package 1W)
## Authoritative coordinator for tactical military unit rosters, selections,
## formations (Line, Column, Scatter), control groups (1, 2, 3), and pathfinding command dispatch.
## Maintains strict 1:1 synchronization with PlayerArmyManager.soldier_count.

const TacticalUnitScene: PackedScene = preload("res://scenes/world/tactical_unit.tscn")
const TacticalUnitScript = preload("res://scripts/military/tactical_unit.gd")

const FORMATION_LINE := "Line"
const FORMATION_COLUMN := "Column"
const FORMATION_SCATTER := "Scatter"

const VALID_FORMATIONS := [FORMATION_LINE, FORMATION_COLUMN, FORMATION_SCATTER]
const RALLY_PERIMETER_DISTANCE: int = 5

signal selection_changed(selected_ids: Array[String])
signal formation_changed(formation_name: String)
signal control_groups_changed(groups: Dictionary)
signal unit_spawned(unit_id: String, cell: Vector2i)
signal unit_despawned(unit_id: String)
signal order_issued(order_type: String, count: int, target_cell: Vector2i)
signal tactical_state_updated()

var world_view: Node = null
var player_army_mgr: PlayerArmyManager = null
var tactical_units_container: Node = null

var units: Dictionary = {} # unit_id: String -> TacticalUnit
var selected_unit_ids: Array[String] = []
var control_groups: Dictionary = {1: [], 2: [], 3: []}
var current_formation: String = FORMATION_LINE
var next_unit_index: int = 1

# Dependency injection for headless unit testing
var _custom_nav: GridNavigation = null
var _custom_time_mgr: Object = null

func _init(wv: Node = null, army_mgr: PlayerArmyManager = null) -> void:
	world_view = wv
	units = {}
	selected_unit_ids = []
	control_groups = {1: [], 2: [], 3: []}
	current_formation = FORMATION_LINE
	next_unit_index = 1
	if army_mgr != null:
		set_player_army_manager(army_mgr)

func set_world_view(wv: Node) -> void:
	world_view = wv

func set_tactical_units_container(container: Node) -> void:
	tactical_units_container = container

func set_player_army_manager(mgr: PlayerArmyManager) -> void:
	if player_army_mgr == mgr:
		return

	var old_army: PlayerArmyManager = player_army_mgr
	player_army_mgr = null

	if old_army != null and is_instance_valid(old_army):
		_unbind_army_manager(old_army)
		if old_army.get("tactical_military_mgr") == self:
			if old_army.has_method("set_tactical_military_manager"):
				old_army.call("set_tactical_military_manager", null)
			else:
				old_army.set("tactical_military_mgr", null)

	clear_all_units()

	player_army_mgr = mgr
	if player_army_mgr != null and is_instance_valid(player_army_mgr):
		_bind_army_manager(player_army_mgr)
		if player_army_mgr.get("tactical_military_mgr") != self:
			if player_army_mgr.has_method("set_tactical_military_manager"):
				player_army_mgr.call("set_tactical_military_manager", self)
			else:
				player_army_mgr.set("tactical_military_mgr", self)
		sync_with_player_army()

func _bind_army_manager(mgr: PlayerArmyManager) -> void:
	if mgr == null or not is_instance_valid(mgr):
		return
	if mgr.has_signal("army_changed") and not mgr.army_changed.is_connected(_on_army_changed):
		mgr.army_changed.connect(_on_army_changed)
	if mgr.has_method("sync_state_from_tactical") and not tactical_state_updated.is_connected(mgr.sync_state_from_tactical):
		tactical_state_updated.connect(mgr.sync_state_from_tactical)

func _unbind_army_manager(mgr: PlayerArmyManager) -> void:
	if mgr == null or not is_instance_valid(mgr):
		return
	if mgr.has_signal("army_changed") and mgr.army_changed.is_connected(_on_army_changed):
		mgr.army_changed.disconnect(_on_army_changed)
	if mgr.has_method("sync_state_from_tactical") and tactical_state_updated.is_connected(mgr.sync_state_from_tactical):
		tactical_state_updated.disconnect(mgr.sync_state_from_tactical)

func _on_army_changed(_count: int, _cap: int) -> void:
	if player_army_mgr == null or not is_instance_valid(player_army_mgr):
		return
	if player_army_mgr.get("tactical_military_mgr") != self:
		return
	if player_army_mgr.get("is_deserializing") == true:
		return
	sync_with_player_army()

func set_custom_nav(p_nav: GridNavigation) -> void:
	_custom_nav = p_nav

func set_custom_time_manager(tm: Object) -> void:
	_custom_time_mgr = tm

func get_nav() -> GridNavigation:
	if _custom_nav != null:
		return _custom_nav
	if player_army_mgr != null and player_army_mgr.has_method("get_nav"):
		return player_army_mgr.call("get_nav")
	if is_instance_valid(world_view) and world_view.get("nav") != null:
		return world_view.get("nav")
	return null

func get_time_manager() -> Object:
	if _custom_time_mgr != null:
		return _custom_time_mgr
	if player_army_mgr != null and player_army_mgr.has_method("get_time_manager"):
		return player_army_mgr.call("get_time_manager")
	if is_instance_valid(world_view) and world_view.is_inside_tree() and world_view.has_node("/root/TimeManager"):
		return world_view.get_node("/root/TimeManager")
	if Engine.has_singleton("TimeManager"):
		return Engine.get_singleton("TimeManager")
	return null

# -----------------------------------------------------------------------------
# Authoritative Roster Synchronization
# -----------------------------------------------------------------------------

func get_unit_count() -> int:
	return units.size()

func get_unit(unit_id: String) -> Node2D:
	return units.get(unit_id, null)

func get_all_units() -> Array:
	return units.values()

func get_occupied_cells(exclude_unit_ids: Array = []) -> Array[Vector2i]:
	var occ: Array[Vector2i] = []
	for uid in units.keys():
		if exclude_unit_ids.has(uid):
			continue
		var u = units[uid]
		if is_instance_valid(u):
			if not occ.has(u.current_cell):
				occ.append(u.current_cell)
			if u.target_cell != u.current_cell and not occ.has(u.target_cell):
				occ.append(u.target_cell)
	return occ

func can_allocate_spawns(count: int, rally_cell: Vector2i = Vector2i(-1, -1), nav: GridNavigation = null) -> bool:
	if count <= 0:
		return true
	if rally_cell == Vector2i(-1, -1):
		rally_cell = player_army_mgr.get_rally_cell() if player_army_mgr else Vector2i(32, 33)
	if nav == null:
		nav = get_nav()
	var occupied := get_occupied_cells()
	var slots := _find_distinct_walkable_cells(rally_cell, count, nav, occupied)
	return slots.size() >= count

func sync_with_player_army(prefer_field_casualties: bool = false, location_restricted: bool = false) -> void:
	if player_army_mgr == null or not is_instance_valid(player_army_mgr):
		return
	if player_army_mgr.get("tactical_military_mgr") != self:
		return

	var target_count: int = player_army_mgr.get_army_count()
	var current_count: int = units.size()

	if current_count == target_count:
		return

	if target_count == 0:
		clear_all_units()
		tactical_state_updated.emit()
		return

	if current_count < target_count:
		# Recruit additions: spawn missing units at base rally cell
		var needed := target_count - current_count
		var base_spawn := player_army_mgr.get_rally_cell()
		var nav := get_nav()
		var occupied := get_occupied_cells()
		var spawn_slots := _find_distinct_walkable_cells(base_spawn, needed, nav, occupied)
		var actual_spawn_count := mini(needed, spawn_slots.size())

		if actual_spawn_count < needed:
			printerr("[TacticalMilitaryManager] Warning: Only found %d unoccupied walkable cells for %d new units near %s" % [actual_spawn_count, needed, base_spawn])

		for i in range(actual_spawn_count):
			var slot: Vector2i = spawn_slots[i]
			var u_id := "tac_unit_%d" % next_unit_index
			next_unit_index += 1
			while units.has(u_id):
				u_id = "tac_unit_%d" % next_unit_index
				next_unit_index += 1

			var unit: Node2D = _create_unit_instance(u_id, slot)
			units[u_id] = unit
			unit_spawned.emit(u_id, slot)

	elif current_count > target_count:
		# Casualty / reduction: deterministically remove units
		var to_remove := current_count - target_count
		var r_cell: Vector2i = player_army_mgr.get_rally_cell() if player_army_mgr else Vector2i(32, 33)
		var remove_candidates: Array[String] = []
		var all_ids: Array = units.keys()
		all_ids.sort()

		var is_preferred_loc = func(u: Node2D) -> bool:
			if u.order_state == TacticalUnitScript.OrderState.MOVING:
				return false
			var dist: int = IsoMath.grid_distance(u.current_cell, r_cell)
			if prefer_field_casualties:
				return dist > RALLY_PERIMETER_DISTANCE
			else:
				return dist <= RALLY_PERIMETER_DISTANCE

		# Pass 1: Unselected idle units in preferred battle location (descending ID)
		for i in range(all_ids.size() - 1, -1, -1):
			var uid: String = all_ids[i]
			var u = units[uid]
			if not selected_unit_ids.has(uid) and u.order_state == TacticalUnitScript.OrderState.IDLE and is_preferred_loc.call(u):
				remove_candidates.append(uid)
				if remove_candidates.size() >= to_remove:
					break

		# Pass 2: Any unselected units in preferred battle location
		if remove_candidates.size() < to_remove:
			for i in range(all_ids.size() - 1, -1, -1):
				var uid: String = all_ids[i]
				var u = units[uid]
				if not selected_unit_ids.has(uid) and not remove_candidates.has(uid) and is_preferred_loc.call(u):
					remove_candidates.append(uid)
					if remove_candidates.size() >= to_remove:
						break

		# Pass 2b: Any units in preferred battle location (even if selected)
		if remove_candidates.size() < to_remove:
			for i in range(all_ids.size() - 1, -1, -1):
				var uid: String = all_ids[i]
				var u = units[uid]
				if not remove_candidates.has(uid) and is_preferred_loc.call(u):
					remove_candidates.append(uid)
					if remove_candidates.size() >= to_remove:
						break

		if not location_restricted:
			# Pass 3: Any unselected idle units anywhere
			if remove_candidates.size() < to_remove:
				for i in range(all_ids.size() - 1, -1, -1):
					var uid: String = all_ids[i]
					var u = units[uid]
					if not selected_unit_ids.has(uid) and not remove_candidates.has(uid) and u.order_state == TacticalUnitScript.OrderState.IDLE:
						remove_candidates.append(uid)
						if remove_candidates.size() >= to_remove:
							break

			# Pass 4: Any unselected units anywhere
			if remove_candidates.size() < to_remove:
				for i in range(all_ids.size() - 1, -1, -1):
					var uid: String = all_ids[i]
					if not selected_unit_ids.has(uid) and not remove_candidates.has(uid):
						remove_candidates.append(uid)
						if remove_candidates.size() >= to_remove:
							break

			# Pass 5: Remaining units in descending ID
			if remove_candidates.size() < to_remove:
				for i in range(all_ids.size() - 1, -1, -1):
					var uid: String = all_ids[i]
					if not remove_candidates.has(uid):
						remove_candidates.append(uid)
						if remove_candidates.size() >= to_remove:
							break

		for uid in remove_candidates:
			_remove_unit(uid)

	prune_invalid_units()
	tactical_state_updated.emit()

func _create_unit_instance(u_id: String, spawn_cell: Vector2i) -> Node2D:
	var unit: Node2D = null
	if TacticalUnitScene != null:
		unit = TacticalUnitScene.instantiate() as Node2D
	if unit == null:
		unit = TacticalUnitScript.new() as Node2D

	unit.unit_id = u_id
	unit.unit_name = "Binh Sĩ #%s" % u_id.replace("tac_unit_", "")
	unit.unit_type = "swordsman"
	unit.current_cell = spawn_cell
	unit.target_cell = spawn_cell
	unit.formation = current_formation
	unit.set_world_view(world_view)
	if _custom_time_mgr != null:
		unit.set_custom_time_manager(_custom_time_mgr)

	if unit.has_signal("unit_reached_destination") and not unit.unit_reached_destination.is_connected(_on_unit_reached_destination):
		unit.unit_reached_destination.connect(_on_unit_reached_destination)
	if unit.has_signal("unit_defeated") and not unit.unit_defeated.is_connected(_on_unit_defeated):
		unit.unit_defeated.connect(_on_unit_defeated)

	var container = _get_units_container()
	if container != null and is_instance_valid(container):
		container.add_child(unit)

	return unit

func _on_unit_reached_destination(_id: String, _cell: Vector2i) -> void:
	tactical_state_updated.emit()

func _on_unit_defeated(u_id: String, _killer_id: String) -> void:
	_remove_unit(u_id)
	if player_army_mgr != null and is_instance_valid(player_army_mgr):
		if player_army_mgr.has_method("on_tactical_unit_killed"):
			player_army_mgr.call("on_tactical_unit_killed", u_id)
		else:
			player_army_mgr.soldier_count = maxi(0, player_army_mgr.soldier_count - 1)
			player_army_mgr.army_changed.emit(player_army_mgr.soldier_count, player_army_mgr.get_army_capacity())
	tactical_state_updated.emit()

func _remove_unit(uid: String) -> void:
	if not units.has(uid):
		return
	var u = units[uid]
	if selected_unit_ids.has(uid):
		selected_unit_ids.erase(uid)
		selection_changed.emit(selected_unit_ids)
	for g in [1, 2, 3]:
		if control_groups[g].has(uid):
			control_groups[g].erase(uid)
	units.erase(uid)
	unit_despawned.emit(uid)
	if is_instance_valid(u) and u is Node:
		u.queue_free()

func clear_all_units() -> void:
	for uid in units.keys():
		var u = units[uid]
		if is_instance_valid(u) and u is Node:
			u.queue_free()
		unit_despawned.emit(uid)
	units.clear()
	selected_unit_ids.clear()
	control_groups = {1: [], 2: [], 3: []}
	selection_changed.emit(selected_unit_ids)
	control_groups_changed.emit(control_groups)
	tactical_state_updated.emit()

func _get_units_container() -> Node:
	if tactical_units_container != null and is_instance_valid(tactical_units_container):
		return tactical_units_container
	if is_instance_valid(world_view) and world_view.get("citizens_container") != null:
		return world_view.get("citizens_container")
	return null

# -----------------------------------------------------------------------------
# Selection API
# -----------------------------------------------------------------------------

func select_unit(unit_id: String, additive: bool = false) -> void:
	if not units.has(unit_id):
		return

	if not additive:
		for uid in selected_unit_ids:
			if units.has(uid):
				units[uid].set_selected(false)
		selected_unit_ids.clear()

	if selected_unit_ids.has(unit_id):
		if additive:
			selected_unit_ids.erase(unit_id)
			units[unit_id].set_selected(false)
	else:
		selected_unit_ids.append(unit_id)
		units[unit_id].set_selected(true)

	selection_changed.emit(selected_unit_ids)

func deselect_unit(unit_id: String) -> void:
	if selected_unit_ids.has(unit_id):
		selected_unit_ids.erase(unit_id)
		if units.has(unit_id):
			units[unit_id].set_selected(false)
		selection_changed.emit(selected_unit_ids)

func select_all() -> void:
	selected_unit_ids.clear()
	for uid in units.keys():
		selected_unit_ids.append(uid)
		units[uid].set_selected(true)
	selection_changed.emit(selected_unit_ids)

func clear_selection() -> void:
	if selected_unit_ids.is_empty():
		return
	for uid in selected_unit_ids:
		if units.has(uid):
			units[uid].set_selected(false)
	selected_unit_ids.clear()
	selection_changed.emit(selected_unit_ids)

func get_selected_count() -> int:
	return selected_unit_ids.size()

func get_selected_unit_ids() -> Array[String]:
	return selected_unit_ids.duplicate()

func get_selected_units() -> Array:
	var res: Array = []
	for uid in selected_unit_ids:
		if units.has(uid):
			res.append(units[uid])
	return res

func is_unit_selected(unit_id: String) -> bool:
	return selected_unit_ids.has(unit_id)

func select_in_screen_rect(screen_rect: Rect2, camera: Camera2D = null, additive: bool = false) -> void:
	var norm_rect: Rect2 = screen_rect.abs()
	if not additive:
		clear_selection()

	var canvas_xform: Transform2D = Transform2D.IDENTITY
	if camera != null and camera.is_inside_tree() and camera.get_viewport() != null:
		canvas_xform = camera.get_viewport().get_canvas_transform()

	for uid in units.keys():
		var u = units[uid]
		var world_pos: Vector2 = u.global_position if (u is Node2D and u.is_inside_tree()) else IsoMath.map_to_local(u.current_cell)
		var screen_pos: Vector2 = canvas_xform * world_pos if camera != null else world_pos

		if norm_rect.has_point(screen_pos):
			if not selected_unit_ids.has(uid):
				selected_unit_ids.append(uid)
				u.set_selected(true)

	selection_changed.emit(selected_unit_ids)

# -----------------------------------------------------------------------------
# Formations & Slot Calculation
# -----------------------------------------------------------------------------

func set_formation(formation_name: String) -> bool:
	if not VALID_FORMATIONS.has(formation_name):
		return false
	current_formation = formation_name
	for uid in selected_unit_ids:
		if units.has(uid):
			units[uid].formation = current_formation
	formation_changed.emit(current_formation)
	return true

func get_formation() -> String:
	return current_formation

func compute_formation_slots(target_cell: Vector2i, count: int, formation_name: String = "", nav: GridNavigation = null, excluded_cells: Array[Vector2i] = []) -> Array[Vector2i]:
	if count <= 0:
		return []

	var f_name: String = formation_name if formation_name != "" else current_formation
	if not VALID_FORMATIONS.has(f_name):
		f_name = FORMATION_LINE

	if nav == null:
		nav = get_nav()

	var assigned_slots: Array[Vector2i] = []

	# Deterministic base offsets per formation
	var raw_offsets: Array[Vector2i] = []
	match f_name:
		FORMATION_LINE:
			# Lateral line across X axis
			for i in range(count):
				var ox: int = i - int(count / 2)
				raw_offsets.append(Vector2i(ox, 0))
		FORMATION_COLUMN:
			# Longitudinal column along Y axis
			for i in range(count):
				var oy: int = i - int(count / 2)
				raw_offsets.append(Vector2i(0, oy))
		FORMATION_SCATTER, _:
			# Concentric diamond rings / spiral
			raw_offsets.append(Vector2i(0, 0))
			var ring: int = 1
			while raw_offsets.size() < count:
				for dy in range(-ring, ring + 1):
					for dx in range(-ring, ring + 1):
						if abs(dx) + abs(dy) == ring:
							raw_offsets.append(Vector2i(dx, dy))
							if raw_offsets.size() >= count:
								break
					if raw_offsets.size() >= count:
						break
				ring += 1

	# Assign valid, in-bounds, walkable, non-overlapping destination cells
	for i in range(count):
		var base_cand: Vector2i = target_cell + raw_offsets[i]
		if IsoMath.is_in_bounds(base_cand) and (nav == null or nav.is_cell_walkable(base_cand)) and not assigned_slots.has(base_cand) and not excluded_cells.has(base_cand):
			assigned_slots.append(base_cand)
		else:
			# Search locally for nearest walkable, in-bounds, unassigned cell
			var alt_slot := _find_nearest_unassigned_cell(base_cand, target_cell, assigned_slots, nav, excluded_cells)
			if alt_slot != Vector2i(-1, -1):
				assigned_slots.append(alt_slot)
			else:
				# Cannot satisfy distinct slots for entire group
				return []

	return assigned_slots

## Computes dedicated deterministic return-home garrison slots strictly within RALLY_PERIMETER_DISTANCE.
## Fail-closed: returns an empty Array if fewer than count valid, walkable, unoccupied cells exist within perimeter.
func compute_garrison_return_slots(rally_cell: Vector2i, count: int, nav: GridNavigation = null, excluded_cells: Array[Vector2i] = []) -> Array[Vector2i]:
	if count <= 0:
		return []

	if nav == null:
		nav = get_nav()

	var slots: Array[Vector2i] = []

	# Radius 0: check rally_cell itself
	if IsoMath.is_in_bounds(rally_cell) and (nav == null or nav.is_cell_walkable(rally_cell)) and not excluded_cells.has(rally_cell):
		slots.append(rally_cell)
		if slots.size() >= count:
			return slots

	# Search strictly within RALLY_PERIMETER_DISTANCE (Manhattan distance 1..5)
	for r in range(1, RALLY_PERIMETER_DISTANCE + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if abs(dx) + abs(dy) == r:
					var cand := rally_cell + Vector2i(dx, dy)
					if IsoMath.is_in_bounds(cand) and (nav == null or nav.is_cell_walkable(cand)) and not slots.has(cand) and not excluded_cells.has(cand):
						slots.append(cand)
						if slots.size() >= count:
							return slots

	# Atomic all-or-nothing guarantee: return empty array if insufficient slots
	return []

func _find_nearest_unassigned_cell(near_cell: Vector2i, center: Vector2i, assigned: Array[Vector2i], nav: GridNavigation, excluded: Array[Vector2i] = []) -> Vector2i:
	for r in range(1, 15):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if abs(dx) + abs(dy) == r:
					var cand := near_cell + Vector2i(dx, dy)
					if IsoMath.is_in_bounds(cand) and (nav == null or nav.is_cell_walkable(cand)) and not assigned.has(cand) and not excluded.has(cand):
						return cand

	# Secondary fallback around center
	for r in range(1, 15):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if abs(dx) + abs(dy) == r:
					var cand := center + Vector2i(dx, dy)
					if IsoMath.is_in_bounds(cand) and (nav == null or nav.is_cell_walkable(cand)) and not assigned.has(cand) and not excluded.has(cand):
						return cand

	return Vector2i(-1, -1)

func _find_distinct_walkable_cells(center: Vector2i, count: int, nav: GridNavigation = null, occupied_cells: Array[Vector2i] = []) -> Array[Vector2i]:
	var res: Array[Vector2i] = []
	if IsoMath.is_in_bounds(center) and (nav == null or nav.is_cell_walkable(center)) and not occupied_cells.has(center):
		res.append(center)
	if res.size() >= count:
		return res

	var max_radius: int = IsoMath.MAP_SIZE
	for r in range(1, max_radius):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if abs(dx) + abs(dy) == r:
					var cand := center + Vector2i(dx, dy)
					if IsoMath.is_in_bounds(cand) and (nav == null or nav.is_cell_walkable(cand)) and not res.has(cand) and not occupied_cells.has(cand):
						res.append(cand)
						if res.size() >= count:
							return res
	return res

# -----------------------------------------------------------------------------
# Movement Command Dispatch
# -----------------------------------------------------------------------------

func issue_move_order(target_cell: Vector2i, nav: GridNavigation = null) -> Dictionary:
	if selected_unit_ids.is_empty():
		return {"success": false, "reason": "Không có đơn vị nào được chọn để điều động"}

	if not IsoMath.is_in_bounds(target_cell):
		return {"success": false, "reason": "Vị trí chỉ định nằm ngoài bản đồ"}

	if nav == null:
		nav = get_nav()

	if nav == null:
		return {"success": false, "reason": "Hệ thống dẫn đường không khả dụng"}

	if not nav.is_cell_walkable(target_cell):
		return {"success": false, "reason": "Vị trí chỉ định bị cản trở hoặc không thể đi tới"}

	var unit_count: int = selected_unit_ids.size()
	var excluded_cells: Array[Vector2i] = get_occupied_cells(selected_unit_ids)
	var slots := compute_formation_slots(target_cell, unit_count, current_formation, nav, excluded_cells)
	if slots.size() < unit_count:
		return {"success": false, "reason": "Không đủ vị trí trống hợp lệ cho toàn bộ đội hình tại điểm đến"}

	# Pre-validate paths for all units (fail-safe all-or-nothing dispatch)
	var planned_paths: Dictionary = {}
	for idx in range(unit_count):
		var uid := selected_unit_ids[idx]
		var u = units.get(uid)
		if u == null:
			continue
		var slot: Vector2i = slots[idx]
		if u.current_cell == slot:
			var empty_p: Array[Vector2i] = []
			planned_paths[uid] = empty_p
		else:
			var path: Array[Vector2i] = nav.find_path(u.current_cell, slot)
			if path.is_empty():
				return {"success": false, "reason": "Không tìm thấy đường đi tới đích cho một hoặc nhiều đơn vị"}
			if path.size() > 0 and path[0] == u.current_cell:
				path.remove_at(0)
			planned_paths[uid] = path

	# Dispatch paths
	for idx in range(unit_count):
		var uid := selected_unit_ids[idx]
		var u = units.get(uid)
		if u == null:
			continue
		var slot: Vector2i = slots[idx]
		var path_arr: Array = planned_paths.get(uid, [])
		var path: Array[Vector2i] = []
		for p in path_arr:
			path.append(Vector2i(p))
		u.order_move(path, slot)

	order_issued.emit("Move", unit_count, target_cell)
	tactical_state_updated.emit()
	return {
		"success": true,
		"reason": "Đã nhận lệnh di chuyển đội hình %s" % current_formation,
		"count": unit_count,
		"target_cell": target_cell,
		"formation": current_formation
	}

func issue_attack_order(target: Node, nav: GridNavigation = null) -> Dictionary:
	if selected_unit_ids.is_empty():
		return {"success": false, "reason": "Không có đơn vị nào được chọn để tấn công"}

	if target == null or not is_instance_valid(target):
		return {"success": false, "reason": "Mục tiêu không hợp lệ"}

	var alive_val = target.get("is_alive")
	if alive_val != null and not bool(alive_val):
		return {"success": false, "reason": "Mục tiêu đã bị tiêu diệt"}

	var hp_val = target.get("health")
	if hp_val != null and float(hp_val) <= 0.0:
		return {"success": false, "reason": "Mục tiêu đã bị tiêu diệt"}

	# Faction hostility check
	var tgt_fac = target.get("faction_id")
	if tgt_fac == null:
		tgt_fac = target.get("owning_faction_id")
	var tgt_faction_str := str(tgt_fac) if tgt_fac != null else ""
	if tgt_faction_str == "player":
		return {"success": false, "reason": "Không thể tấn công đơn vị phe mình"}

	# Siege objective active check (Package 1X)
	var is_siege_obj: bool = target.get("objective_id") != null and target.get("garrison_count") != null
	if is_siege_obj:
		var under_siege = target.get("is_under_active_siege")
		if under_siege == null or not bool(under_siege):
			return {"success": false, "reason": "Chưa phát động chiến dịch công thành đối với mục tiêu này"}
		var is_cap = target.get("is_captured")
		if is_cap != null and bool(is_cap):
			return {"success": false, "reason": "Mục tiêu công thành đã bị chiếm đóng"}

	var fm = null
	if is_instance_valid(world_view) and world_view.get("faction_manager") != null:
		fm = world_view.get("faction_manager")
	if fm != null and not tgt_faction_str.is_empty():
		var at_war: bool = false
		if fm.has_method("get_faction"):
			var f = fm.get_faction(tgt_faction_str)
			if f != null:
				at_war = bool(f.is_at_war)
		elif fm.has_method("are_factions_at_war"):
			at_war = fm.are_factions_at_war(tgt_faction_str, "player")
		if not at_war:
			return {"success": false, "reason": "Chưa ở trạng thái chiến tranh với thế lực này, không thể tấn công"}

	if nav == null:
		nav = get_nav()

	var count: int = 0
	for uid in selected_unit_ids:
		var u = units.get(uid, null)
		if u != null and is_instance_valid(u) and u.is_alive:
			u.order_attack(target)
			count += 1

	if count == 0:
		return {"success": false, "reason": "Không có đơn vị sẵn sàng tấn công"}

	var raw_tgt_c = target.get("current_cell")
	var tgt_cell: Vector2i = raw_tgt_c if (raw_tgt_c is Vector2i) else Vector2i(-1, -1)
	order_issued.emit("Attack", count, tgt_cell)
	tactical_state_updated.emit()
	return {"success": true, "reason": "Đã ra lệnh tấn công mục tiêu", "count": count}

func halt_selected_units() -> void:
	for uid in selected_unit_ids:
		if units.has(uid):
			units[uid].order_hold()
	tactical_state_updated.emit()

func disengage_targets_of_faction(faction_id: String) -> void:
	for u in units.values():
		if u != null and is_instance_valid(u) and u.order_state == TacticalUnit.OrderState.ATTACKING:
			var tgt = u.target_actor
			if tgt != null and is_instance_valid(tgt):
				var tf = tgt.get("faction_id")
				if tf == null:
					tf = tgt.get("owning_faction_id")
				if str(tf) == faction_id:
					u.order_hold()
	tactical_state_updated.emit()

# -----------------------------------------------------------------------------
# Garrison & Field Spatial Queries (Contract C)
# -----------------------------------------------------------------------------

func get_garrisoned_units(p_rally: Vector2i = Vector2i(-1, -1)) -> Array:
	var r_cell: Vector2i = p_rally
	if r_cell == Vector2i(-1, -1):
		r_cell = player_army_mgr.get_rally_cell() if player_army_mgr else Vector2i(32, 33)
	var res: Array = []
	for uid in units.keys():
		var u = units[uid]
		if is_instance_valid(u):
			var dist: int = IsoMath.grid_distance(u.current_cell, r_cell)
			if dist <= RALLY_PERIMETER_DISTANCE and u.order_state != TacticalUnitScript.OrderState.MOVING:
				res.append(u)
	return res

func get_garrisoned_unit_count(p_rally: Vector2i = Vector2i(-1, -1)) -> int:
	return get_garrisoned_units(p_rally).size()

## Returns all ready/eligible field units. A tactical unit is an eligible field troop if and only if
## it is physically outside the garrison perimeter (dist > RALLY_PERIMETER_DISTANCE) AND stationary (order_state != MOVING).
func get_field_units(p_rally: Vector2i = Vector2i(-1, -1)) -> Array:
	var r_cell: Vector2i = p_rally
	if r_cell == Vector2i(-1, -1):
		r_cell = player_army_mgr.get_rally_cell() if player_army_mgr else Vector2i(32, 33)
	var res: Array = []
	for uid in units.keys():
		var u = units[uid]
		if is_instance_valid(u):
			var dist: int = IsoMath.grid_distance(u.current_cell, r_cell)
			if dist > RALLY_PERIMETER_DISTANCE and u.order_state != TacticalUnitScript.OrderState.MOVING:
				res.append(u)
	return res

func get_field_unit_count(p_rally: Vector2i = Vector2i(-1, -1)) -> int:
	return get_field_units(p_rally).size()

## Returns all units physically located outside RALLY_PERIMETER_DISTANCE regardless of movement state.
func get_all_field_units(p_rally: Vector2i = Vector2i(-1, -1)) -> Array:
	var r_cell: Vector2i = p_rally
	if r_cell == Vector2i(-1, -1):
		r_cell = player_army_mgr.get_rally_cell() if player_army_mgr else Vector2i(32, 33)
	var res: Array = []
	for uid in units.keys():
		var u = units[uid]
		if is_instance_valid(u):
			var dist: int = IsoMath.grid_distance(u.current_cell, r_cell)
			if dist > RALLY_PERIMETER_DISTANCE:
				res.append(u)
	return res

func order_move_all(target_cell: Vector2i, nav: GridNavigation = null) -> Dictionary:
	if player_army_mgr != null and units.size() != player_army_mgr.get_army_count():
		sync_with_player_army()
	select_all()
	return issue_move_order(target_cell, nav)

## Issues deterministic return-to-rally orders for all units strictly using garrison perimeter allocation.
## Fails closed atomically if insufficient slots or valid paths cannot be found.
func order_return_all_to_rally(p_rally: Vector2i = Vector2i(-1, -1), nav: GridNavigation = null) -> Dictionary:
	if player_army_mgr != null and units.size() != player_army_mgr.get_army_count():
		sync_with_player_army()
	var r_cell: Vector2i = p_rally
	if r_cell == Vector2i(-1, -1):
		r_cell = player_army_mgr.get_rally_cell() if player_army_mgr else Vector2i(32, 33)

	var unit_count: int = units.size()
	if unit_count <= 0:
		return {"success": false, "reason": "Không có binh sĩ để điều động"}

	if nav == null:
		nav = get_nav()
	if nav == null:
		return {"success": false, "reason": "Hệ thống dẫn đường không khả dụng"}

	# Validate slots without prematurely modifying selection or issuing partial orders
	var all_unit_ids: Array = units.keys()
	var excluded_cells: Array[Vector2i] = get_occupied_cells(all_unit_ids)
	var slots := compute_garrison_return_slots(r_cell, unit_count, nav, excluded_cells)
	if slots.size() < unit_count:
		return {"success": false, "reason": "Không đủ vị trí trống trong khu vực căn cứ để đóng quân"}

	# Pre-validate paths for all units to assigned slots (fail-safe all-or-nothing dispatch)
	var sorted_uids: Array = units.keys()
	sorted_uids.sort()
	var planned_paths: Dictionary = {}

	for idx in range(unit_count):
		var uid: String = sorted_uids[idx]
		var u = units.get(uid)
		if u == null:
			continue
		var slot: Vector2i = slots[idx]
		if u.current_cell == slot:
			var empty_p: Array[Vector2i] = []
			planned_paths[uid] = empty_p
		else:
			var path: Array[Vector2i] = nav.find_path(u.current_cell, slot)
			if path.is_empty():
				return {"success": false, "reason": "Không tìm thấy đường đi tới căn cứ cho một hoặc nhiều đơn vị"}
			if path.size() > 0 and path[0] == u.current_cell:
				path.remove_at(0)
			planned_paths[uid] = path

	# Validation completely succeeded; now update selection and dispatch orders atomically
	select_all()

	# Dispatch orders
	for idx in range(unit_count):
		var uid: String = sorted_uids[idx]
		var u = units.get(uid)
		if u == null:
			continue
		var slot: Vector2i = slots[idx]
		var path_arr: Array = planned_paths.get(uid, [])
		var path: Array[Vector2i] = []
		for p in path_arr:
			path.append(Vector2i(p))
		u.order_move(path, slot)

	order_issued.emit("ReturnHome", unit_count, r_cell)
	tactical_state_updated.emit()
	return {
		"success": true,
		"reason": "Đã nhận lệnh trở về căn cứ",
		"count": unit_count,
		"target_cell": r_cell
	}

func arrive_all_at_destination() -> void:
	# Snapping/teleportation removed: units advance physically via advance_movement().
	tactical_state_updated.emit()

# -----------------------------------------------------------------------------
# Control Groups (1, 2, 3)
# -----------------------------------------------------------------------------

func assign_control_group(group_id: int) -> bool:
	if group_id < 1 or group_id > 3:
		return false
	prune_invalid_units()
	control_groups[group_id] = selected_unit_ids.duplicate()
	for uid in units.keys():
		if selected_unit_ids.has(uid):
			units[uid].control_group_id = group_id
		elif units[uid].control_group_id == group_id:
			units[uid].control_group_id = 0
	control_groups_changed.emit(control_groups)
	return true

func recall_control_group(group_id: int) -> bool:
	if group_id < 1 or group_id > 3:
		return false
	prune_invalid_units()
	var group: Array = control_groups.get(group_id, [])
	clear_selection()
	for uid in group:
		if units.has(uid):
			selected_unit_ids.append(uid)
			units[uid].set_selected(true)
	selection_changed.emit(selected_unit_ids)
	return true

func get_control_group(group_id: int) -> Array[String]:
	prune_invalid_units()
	var res: Array[String] = []
	for uid in control_groups.get(group_id, []):
		res.append(String(uid))
	return res

func prune_invalid_units() -> void:
	for g in [1, 2, 3]:
		var valid_list: Array = []
		for uid in control_groups.get(g, []):
			if units.has(uid):
				valid_list.append(uid)
		control_groups[g] = valid_list

	var valid_sel: Array[String] = []
	for uid in selected_unit_ids:
		if units.has(uid):
			valid_sel.append(uid)
	selected_unit_ids = valid_sel

# -----------------------------------------------------------------------------
# Simulation Advance
# -----------------------------------------------------------------------------

func advance_movement(delta: float, speed_mult: float = 1.0, nav: GridNavigation = null) -> void:
	if nav == null:
		nav = get_nav()
	for uid in units.keys():
		var u = units[uid]
		if is_instance_valid(u):
			u.advance_movement(delta, speed_mult, nav)
			u.advance_combat(delta, speed_mult, nav)

func advance_combat(delta: float, speed_mult: float = 1.0, nav: GridNavigation = null) -> void:
	if nav == null:
		nav = get_nav()
	for uid in units.keys():
		var u = units[uid]
		if is_instance_valid(u):
			u.advance_combat(delta, speed_mult, nav)

func advance_simulation(delta: float, speed_mult: float = 1.0, nav: GridNavigation = null) -> void:
	advance_movement(delta, speed_mult, nav)

# -----------------------------------------------------------------------------
# Serialization & Persistence
# -----------------------------------------------------------------------------

func serialize() -> Dictionary:
	prune_invalid_units()
	var units_arr: Array = []
	var sorted_ids := units.keys()
	sorted_ids.sort()

	for uid in sorted_ids:
		var u = units[uid]
		units_arr.append(u.serialize())

	var cg_dict: Dictionary = {}
	for g in [1, 2, 3]:
		cg_dict[str(g)] = control_groups[g].duplicate()

	return {
		"units": units_arr,
		"current_formation": current_formation,
		"control_groups": cg_dict,
		"next_unit_index": next_unit_index
	}

func deserialize(data: Dictionary) -> bool:
	if data.is_empty():
		clear_all_units()
		return true

	if not data.has("units") or not (data.get("units") is Array):
		return false

	var raw_units: Array = data.get("units")
	var seen_ids: Dictionary = {}
	for u_data in raw_units:
		if not (u_data is Dictionary):
			return false
		var uid: String = String(u_data.get("unit_id", "")).strip_edges()
		if uid.is_empty() or seen_ids.has(uid):
			return false
		seen_ids[uid] = true

		var raw_cell = u_data.get("current_cell")
		var cell := Vector2i(-1, -1)
		if raw_cell is Array and raw_cell.size() >= 2:
			cell = Vector2i(int(raw_cell[0]), int(raw_cell[1]))
		elif raw_cell is Vector2i:
			cell = raw_cell
		if not IsoMath.is_in_bounds(cell):
			return false

		var o_state_str: String = String(u_data.get("order_state", "idle")).to_lower()
		if not (o_state_str in ["idle", "moving", "holding"]):
			return false

		var tgt_c := cell
		if u_data.has("target_cell"):
			var raw_tgt = u_data.get("target_cell")
			if raw_tgt is Array and raw_tgt.size() >= 2:
				tgt_c = Vector2i(int(raw_tgt[0]), int(raw_tgt[1]))
			elif raw_tgt is Vector2i:
				tgt_c = raw_tgt
			else:
				return false
			if not IsoMath.is_in_bounds(tgt_c):
				return false
		elif o_state_str == "moving":
			return false

		var u_path = u_data.get("current_path")
		if o_state_str == "moving":
			if not (u_path is Array) or u_path.is_empty():
				return false
			for step in u_path:
				var s_pt := Vector2i(-1, -1)
				if step is Array and step.size() >= 2:
					s_pt = Vector2i(int(step[0]), int(step[1]))
				elif step is Vector2i:
					s_pt = step
				if not IsoMath.is_in_bounds(s_pt):
					return false
			var last_pt_raw = u_path[-1]
			var last_pt := Vector2i(-1, -1)
			if last_pt_raw is Array and last_pt_raw.size() >= 2:
				last_pt = Vector2i(int(last_pt_raw[0]), int(last_pt_raw[1]))
			elif last_pt_raw is Vector2i:
				last_pt = last_pt_raw
			if last_pt != tgt_c:
				return false
		elif o_state_str in ["idle", "holding"]:
			if u_path != null and (not (u_path is Array) or not u_path.is_empty()):
				return false

	var raw_cg = data.get("control_groups")
	if raw_cg != null and not (raw_cg is Dictionary):
		return false

	# All validation passed! Safe to mutate state
	clear_all_units()

	current_formation = String(data.get("current_formation", FORMATION_LINE))
	if not VALID_FORMATIONS.has(current_formation):
		current_formation = FORMATION_LINE

	next_unit_index = maxi(1, int(data.get("next_unit_index", 1)))

	for u_data in raw_units:
		var uid: String = String(u_data.get("unit_id", "")).strip_edges()
		var raw_cell = u_data.get("current_cell")
		var cell: Vector2i = Vector2i(int(raw_cell[0]), int(raw_cell[1])) if raw_cell is Array else raw_cell
		var unit: Node2D = _create_unit_instance(uid, cell)
		unit.deserialize(u_data)
		units[uid] = unit
		unit_spawned.emit(uid, cell)

	if raw_cg is Dictionary:
		for g in [1, 2, 3]:
			var key := str(g)
			if raw_cg.has(key) and raw_cg[key] is Array:
				control_groups[g] = raw_cg[key].duplicate()
			elif raw_cg.has(g) and raw_cg[g] is Array:
				control_groups[g] = raw_cg[g].duplicate()

	prune_invalid_units()
	formation_changed.emit(current_formation)
	control_groups_changed.emit(control_groups)
	tactical_state_updated.emit()
	return true

func deserialize_legacy(soldier_count: int, rally_cell: Vector2i, nav: GridNavigation = null) -> bool:
	clear_all_units()
	if soldier_count <= 0:
		return true

	if nav == null:
		nav = get_nav()

	var slots := _find_distinct_walkable_cells(rally_cell, soldier_count, nav, [])
	var actual_count := mini(soldier_count, slots.size())
	for i in range(actual_count):
		var slot: Vector2i = slots[i]
		var u_id := "tac_unit_%d" % (i + 1)
		var unit: Node2D = _create_unit_instance(u_id, slot)
		units[u_id] = unit
		unit_spawned.emit(u_id, slot)

	next_unit_index = soldier_count + 1
	current_formation = FORMATION_LINE
	control_groups = {1: [], 2: [], 3: []}
	formation_changed.emit(current_formation)
	control_groups_changed.emit(control_groups)
	tactical_state_updated.emit()
	return true
