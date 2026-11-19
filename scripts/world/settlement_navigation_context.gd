class_name SettlementNavigationContext
extends RefCounted
## Phase 6 Settlement-Local Navigation & Transient Locomotion Context.
## Pure RefCounted, owned by RivalPresentationController (never by SettlementVillagerContext).
##
## Ownership Rules:
## - `SettlementVillagerData.cell` is the SINGLE authoritative coarse logical position.
## - `LocomotionState` holds ONLY transient movement/interpolation state (never a duplicate `current_cell`).
## - Only this context writes `villager.cell` during physical movement.

const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementBuildingCapabilityAdapterScript = preload("res://scripts/world/settlement_building_capability_adapter.gd")
const ContinuousPathFollowerScript = preload("res://scripts/navigation/continuous_path_follower.gd")
const GridNavigationScript = preload("res://scripts/navigation/grid_navigation.gd")

const MOVE_SPEED_PX: float = 48.0 # Matches CitizenController reference speed (px/sec at 1x)
const FAR_CELLS_PER_HOUR: int = 12 # Bounded coarse travel distance per in-game hour when settlement is FAR LOD
const MAX_PATH_CACHE_ENTRIES: int = 64
const DEFAULT_ACTIVITY_MARGIN_CELLS: int = 12

enum MoveStatus {
	IDLE = 0,
	WAITING_PATH = 1,
	MOVING = 2,
	ARRIVED = 3,
	BLOCKED = 4
}

class LocomotionState extends RefCounted:
	var from_cell: Vector2i = Vector2i.ZERO
	var to_cell: Vector2i = Vector2i.ZERO
	var destination_cell: Vector2i = Vector2i(-1, -1)
	var focus_cell: Vector2i = Vector2i(-1, -1)
	var has_valid_focus: bool = false
	var path: Array[Vector2i] = []
	var path_index: int = 0
	var segment_progress: float = 0.0
	var visual_pos: Vector2 = Vector2.ZERO
	var facing_dir: int = ContinuousPathFollowerScript.ScreenDir.E
	var flip_h: bool = false
	var is_moving: bool = false
	var intent_key: String = ""
	var nav_revision: int = 0
	var status: int = MoveStatus.IDLE
	var retry_cooldown_left: float = 0.0
	var follower: ContinuousPathFollower = null
	var has_cached_intent: bool = false
	var cached_life_state: String = ""
	var cached_task_state: String = ""
	var cached_rest_phase: String = ""
	var cached_role: String = ""
	var cached_job_id: String = ""
	var cached_work_target_id: String = ""
	var cached_home_building_id: String = ""
	var cached_carrying_amount: int = 0
	var cached_carrying_resource: String = ""
	var cached_source_cell: Vector2i = Vector2i(-1, -1)
	var cached_nav_revision: int = 0
	var cached_dynamic_target_token: String = ""

var settlement_id: String = ""
var anchor_cell: Vector2i = Vector2i.ZERO
var nav_revision: int = 1
var world_data: RefCounted = null
var grid_nav: GridNavigation = null

var _locomotion_by_vid: Dictionary = {} # villager_id (String) -> LocomotionState
var _foreign_building_cells: Dictionary = {} # Vector2i -> true (buildings of OTHER settlements / player)
var _own_building_cells: Dictionary = {} # Vector2i -> true
var _path_cache: Dictionary = {} # cache_key (String) -> Array[Vector2i]
var _path_cache_order: Array[String] = []
var _base_bounds: Rect2i = Rect2i()
var _activity_bounds: Rect2i = Rect2i()
var _activity_bounds_dirty: bool = true

# M0.3 Opt-In Benchmark Counters (disabled by default; zero gameplay impact)
var benchmark_telemetry_enabled: bool = false
var bench_sync_intent_calls: int = 0
var bench_resolve_intent_calls: int = 0
var bench_find_adjacent_calls: int = 0
var bench_intent_cache_hits: int = 0
var bench_intent_invalidations: int = 0

func _init(
	p_settlement_id: String = "",
	p_world_data: RefCounted = null,
	p_grid_nav: GridNavigation = null,
	p_settlement_data: RefCounted = null
) -> void:
	settlement_id = p_settlement_id
	world_data = p_world_data
	grid_nav = p_grid_nav if p_grid_nav != null else GridNavigationScript.new(p_world_data)
	configure_settlement_geometry(p_settlement_data)

func configure_settlement_geometry(settlement_data: RefCounted, all_settlements: Array = []) -> void:
	_own_building_cells.clear()
	_foreign_building_cells.clear()
	if settlement_data != null:
		var raw_anchor: Variant = settlement_data.get("anchor_cell")
		if raw_anchor is Vector2i and raw_anchor.x >= 0 and raw_anchor.y >= 0:
			anchor_cell = raw_anchor
		if settlement_data.has_method("get_building_cells"):
			for c in settlement_data.get_building_cells():
				_own_building_cells[c] = true
		if settlement_data.has_method("get_bounds"):
			_base_bounds = settlement_data.get_bounds()
	if _base_bounds.size == Vector2i.ZERO:
		_base_bounds = Rect2i(anchor_cell, Vector2i.ONE)

	for stl in all_settlements:
		if stl == null or String(stl.get("settlement_id")) == settlement_id:
			continue
		if stl.has_method("get_building_cells"):
			for fc in stl.get_building_cells():
				_foreign_building_cells[fc] = true

	if world_data != null and world_data.get("buildings") is Array:
		for pb in world_data.buildings:
			if pb is Dictionary:
				var p_origin: Vector2i = pb.get("cell", Vector2i.ZERO)
				var p_size: Vector2i = pb.get("size", Vector2i.ONE)
				for ox in range(p_size.x):
					for oy in range(p_size.y):
						_foreign_building_cells[p_origin + Vector2i(ox, oy)] = true

	bump_nav_revision()
	invalidate_activity_bounds()

func set_foreign_building_cells(cells: Dictionary) -> void:
	_foreign_building_cells = cells.duplicate()
	bump_nav_revision()

func bump_nav_revision() -> void:
	nav_revision += 1
	_path_cache.clear()
	_path_cache_order.clear()
	_activity_bounds_dirty = true

func invalidate_activity_bounds() -> void:
	_activity_bounds_dirty = true

## Reconstructs or retrieves transient LocomotionState from canonical SettlementVillagerData.cell.
func get_or_create_locomotion(villager: RefCounted) -> LocomotionState:
	if villager == null:
		return null
	var vid: String = String(villager.villager_id)
	if _locomotion_by_vid.has(vid):
		return _locomotion_by_vid[vid]
	var loc := LocomotionState.new()
	var c: Vector2i = villager.cell
	loc.from_cell = c
	loc.to_cell = c
	loc.destination_cell = c
	loc.visual_pos = IsoMath.map_to_local(c)
	loc.segment_progress = 0.0
	loc.nav_revision = nav_revision
	loc.follower = ContinuousPathFollowerScript.new()
	_locomotion_by_vid[vid] = loc
	return loc

func has_locomotion(villager_id: String) -> bool:
	return _locomotion_by_vid.has(villager_id)

func remove_villager_locomotion(villager_id: String) -> void:
	_locomotion_by_vid.erase(villager_id)
	_activity_bounds_dirty = true

func clear_all() -> void:
	_locomotion_by_vid.clear()
	_path_cache.clear()
	_path_cache_order.clear()
	_activity_bounds_dirty = true

## Settlement-local walkability predicate: enforces world bounds, terrain/bridges,
## WorldData.occupancy, and rejects foreign settlement / player building footprints.
func is_cell_walkable(cell: Vector2i) -> bool:
	if not is_cell_allowed_for_settlement(cell):
		return false
	if grid_nav != null:
		return grid_nav.is_cell_walkable(cell)
	return true

func is_cell_allowed_for_settlement(cell: Vector2i) -> bool:
	if world_data != null:
		if not IsoMath.is_in_bounds(cell, world_data.map_width, world_data.map_height):
			return false
	elif not IsoMath.is_in_bounds(cell):
		return false
	if _foreign_building_cells.has(cell):
		return false
	return true

func get_walkability_predicate() -> Callable:
	return Callable(self, "is_cell_allowed_for_settlement")

func find_closest_walkable_adjacent(target: Vector2i, from_cell: Vector2i) -> Vector2i:
	if benchmark_telemetry_enabled:
		bench_find_adjacent_calls += 1
	if is_cell_walkable(target):
		return target
	var best_cell := Vector2i(-1, -1)
	var best_dist: int = 999999
	for n in IsoMath.get_cardinal_neighbors(target):
		if is_cell_walkable(n):
			var d: int = IsoMath.grid_distance(from_cell, n)
			if d < best_dist:
				best_dist = d
				best_cell = n
	if best_cell != Vector2i(-1, -1):
		return best_cell
	# Fallback: check radius-1 diagonals and radius-2 neighbors (matching <= 2 home/work arrival radius)
	for r in [1, 2]:
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cand := target + Vector2i(dx, dy)
				if is_cell_walkable(cand):
					var d2: int = IsoMath.grid_distance(from_cell, cand)
					if d2 < best_dist:
						best_dist = d2
						best_cell = cand
		if best_cell != Vector2i(-1, -1):
			return best_cell
	return best_cell

## Resolves the canonical movement destination & intent key for a villager from Phase 3/4 data.
func resolve_intent(ctx: RefCounted, villager: RefCounted) -> Dictionary:
	if benchmark_telemetry_enabled:
		bench_resolve_intent_calls += 1
	if ctx == null or villager == null:
		return {"dest_cell": Vector2i(-1, -1), "focus_cell": Vector2i(-1, -1), "has_valid_focus": false, "intent_key": "invalid", "indoor": false}

	var life: String = String(villager.life_state)
	if life != SettlementVillagerDataScript.LIFE_ALIVE:
		return {"dest_cell": villager.cell, "focus_cell": Vector2i(-1, -1), "has_valid_focus": false, "intent_key": "dead|%s" % life, "indoor": true}

	var t_state: String = String(villager.task_state)
	var r_phase: String = String(villager.rest_phase)
	var j_id: String = String(villager.active_job_id)
	var wt_id: String = String(villager.work_target_id)

	# 1. Indoor / Returning Home
	if r_phase == SettlementVillagerDataScript.REST_RESTING_INSIDE:
		var home_cell: Vector2i = _resolve_home_access_cell(ctx, villager)
		return {
			"dest_cell": home_cell,
			"focus_cell": home_cell,
			"has_valid_focus": home_cell.x >= 0 and home_cell.y >= 0,
			"intent_key": "rest_in|%s|%s" % [villager.home_building_id, str(home_cell)],
			"indoor": true
		}
	if t_state == SettlementVillagerDataScript.TASK_RESTING or r_phase == SettlementVillagerDataScript.REST_RETURNING_HOME:
		var home_cell: Vector2i = _resolve_home_access_cell(ctx, villager)
		return {
			"dest_cell": home_cell,
			"focus_cell": home_cell,
			"has_valid_focus": home_cell.x >= 0 and home_cell.y >= 0,
			"intent_key": "rest_ret|%s|%s" % [villager.home_building_id, str(home_cell)],
			"indoor": false
		}

	# 2. Job-backed tasks
	var job = ctx.job_board.get_job(j_id) if (ctx.job_board != null and not j_id.is_empty()) else null
	if job != null:
		if t_state == SettlementVillagerDataScript.TASK_GUARDING:
			var patrol_cell: Vector2i = _resolve_guard_target_cell(ctx, villager, job)
			var guard_focus: Vector2i = _resolve_guard_focus_cell(ctx, villager, job)
			return {
				"dest_cell": patrol_cell,
				"focus_cell": guard_focus,
				"has_valid_focus": guard_focus.x >= 0 and guard_focus.y >= 0,
				"intent_key": "guard|%s|%s|%s" % [j_id, wt_id, str(patrol_cell)],
				"indoor": false
			}
		if t_state == SettlementVillagerDataScript.TASK_HAULING:
			var haul_cell: Vector2i = _resolve_hauler_target_cell(villager, job)
			var haul_focus: Vector2i = _resolve_hauler_focus_cell(villager, job)
			return {
				"dest_cell": haul_cell,
				"focus_cell": haul_focus,
				"has_valid_focus": haul_focus.x >= 0 and haul_focus.y >= 0,
				"intent_key": "haul|%s|%d|%s" % [j_id, villager.get_carrying_amount(), str(haul_cell)],
				"indoor": false
			}
		if t_state == SettlementVillagerDataScript.TASK_WORKING or t_state == SettlementVillagerDataScript.TASK_MOVING_TO_JOB:
			var work_cell: Vector2i = _resolve_work_target_cell(ctx, villager, job)
			var work_focus: Vector2i = _resolve_work_focus_cell(ctx, villager, job)
			return {
				"dest_cell": work_cell,
				"focus_cell": work_focus,
				"has_valid_focus": work_focus.x >= 0 and work_focus.y >= 0,
				"intent_key": "work|%s|%s|%s|%s" % [t_state, j_id, wt_id, str(work_cell)],
				"indoor": false
			}

	# 3. Idle / unassigned: stay near anchor_cell (no unbounded roaming)
	var idle_dest: Vector2i = find_closest_walkable_adjacent(anchor_cell, villager.cell)
	if idle_dest == Vector2i(-1, -1):
		idle_dest = villager.cell
	return {
		"dest_cell": idle_dest,
		"focus_cell": Vector2i(-1, -1),
		"has_valid_focus": false,
		"intent_key": "idle|%s|%s" % [t_state, str(idle_dest)],
		"indoor": false
	}

func _resolve_home_access_cell(ctx: RefCounted, villager: RefCounted) -> Vector2i:
	var hb_id: String = String(villager.home_building_id)
	if hb_id.is_empty():
		return villager.cell
	if ctx.has_method("get_building_descriptors"):
		for bd in ctx.get_building_descriptors():
			if bd is Dictionary and String(bd.get("building_id", "")) == hb_id:
				var ac: Variant = bd.get("access_cell")
				if ac is Vector2i:
					var adj := find_closest_walkable_adjacent(ac, villager.cell)
					if adj != Vector2i(-1, -1):
						return adj
	return villager.cell

func _resolve_guard_target_cell(ctx: RefCounted, villager: RefCounted, job: RefCounted) -> Vector2i:
	var wt_id: String = String(villager.work_target_id)
	if ctx.has_method("get_patrol_targets"):
		for pt in ctx.get_patrol_targets():
			if pt is Dictionary and String(pt.get("building_id", "")) == wt_id:
				var ac: Variant = pt.get("access_cell")
				if ac is Vector2i:
					var adj := find_closest_walkable_adjacent(ac, villager.cell)
					if adj != Vector2i(-1, -1):
						return adj
	var j_adj := find_closest_walkable_adjacent(job.target_cell, villager.cell)
	return j_adj if j_adj != Vector2i(-1, -1) else villager.cell

func _resolve_guard_focus_cell(ctx: RefCounted, villager: RefCounted, job: RefCounted) -> Vector2i:
	var wt_id: String = String(villager.work_target_id)
	if ctx.has_method("get_patrol_targets"):
		for pt in ctx.get_patrol_targets():
			if pt is Dictionary and String(pt.get("building_id", "")) == wt_id:
				var ac: Variant = pt.get("access_cell")
				if ac is Vector2i and ac.x >= 0 and ac.y >= 0:
					return ac
	if job != null and job.target_cell.x >= 0 and job.target_cell.y >= 0:
		return job.target_cell
	return Vector2i(-1, -1)

func _resolve_hauler_focus_cell(villager: RefCounted, job: RefCounted) -> Vector2i:
	var raw_cell: Vector2i = job.dest_cell if villager.get_carrying_amount() > 0 else job.source_cell
	if raw_cell.x < 0 or raw_cell.y < 0:
		raw_cell = job.target_cell
	return raw_cell if (raw_cell.x >= 0 and raw_cell.y >= 0) else Vector2i(-1, -1)

func _resolve_work_focus_cell(ctx: RefCounted, villager: RefCounted, job: RefCounted) -> Vector2i:
	var wpid: String = String(job.workplace_id)
	var st: RefCounted = ctx.sim_state
	if villager.role == SettlementVillagerDataScript.ROLE_HUNTER:
		if st != null and st.production_sources.has(wpid):
			var src: Variant = st.production_sources[wpid]
			if src is Dictionary:
				var prey_id: String = String(src.get("current_prey_id", ""))
				if not prey_id.is_empty() and world_data != null and world_data.has_method("get_animal_by_id"):
					var animal: Dictionary = world_data.get_animal_by_id(prey_id)
					var is_avail: bool = bool(animal.get("is_available", true))
					var res_by: String = String(animal.get("reserved_by", ""))
					var res_type: String = String(animal.get("reservation_type", ""))
					var rec_left: float = float(animal.get("recovery_hours_left", 0.0))
					var owner_ok: bool = (res_by == villager.villager_id and (res_type == "rival" or res_type.is_empty())) or (is_avail and res_by.is_empty() and res_type.is_empty() and rec_left <= 0.0)
					if not animal.is_empty() and animal.get("cell") is Vector2i and owner_ok:
						return animal["cell"]
		return Vector2i(-1, -1)
	if villager.role == SettlementVillagerDataScript.ROLE_WOODCUTTER:
		if st != null and st.production_sources.has(wpid):
			var src_w: Variant = st.production_sources[wpid]
			if src_w is Dictionary and src_w.get("trees") is Array:
				for t in src_w["trees"]:
					if t is Dictionary and int(t.get("remaining_milli", 0)) > 0 and t.get("cell") is Vector2i:
						return t["cell"]
		return Vector2i(-1, -1)
	return job.target_cell if (job != null and job.target_cell.x >= 0 and job.target_cell.y >= 0) else Vector2i(-1, -1)

func _resolve_hauler_target_cell(villager: RefCounted, job: RefCounted) -> Vector2i:
	var raw_cell: Vector2i = job.dest_cell if villager.get_carrying_amount() > 0 else job.source_cell
	if raw_cell.x < 0 or raw_cell.y < 0:
		raw_cell = job.target_cell
	var adj := find_closest_walkable_adjacent(raw_cell, villager.cell)
	return adj if adj != Vector2i(-1, -1) else villager.cell

func _resolve_work_target_cell(ctx: RefCounted, villager: RefCounted, job: RefCounted) -> Vector2i:
	var wpid: String = String(job.workplace_id)
	var st: RefCounted = ctx.sim_state
	if st != null and st.production_sources.has(wpid):
		var src: Variant = st.production_sources[wpid]
		if src is Dictionary:
			# H1 Hunter: active prey cell in WorldData.wildlife (up to 40 cells)
			if villager.role == SettlementVillagerDataScript.ROLE_HUNTER:
				var prey_id: String = String(src.get("current_prey_id", ""))
				if not prey_id.is_empty() and world_data != null and world_data.has_method("get_animal_by_id"):
					var animal: Dictionary = world_data.get_animal_by_id(prey_id)
					if not animal.is_empty() and animal.get("cell") is Vector2i:
						var p_adj := find_closest_walkable_adjacent(animal["cell"], villager.cell)
						if p_adj != Vector2i(-1, -1):
							return p_adj
			# W1 Woodcutter: allocated physical tree cell (up to 12 cells)
			elif villager.role == SettlementVillagerDataScript.ROLE_WOODCUTTER and src.get("trees") is Array:
				for t in src["trees"]:
					if t is Dictionary and int(t.get("remaining_milli", 0)) > 0 and t.get("cell") is Vector2i:
						var t_adj := find_closest_walkable_adjacent(t["cell"], villager.cell)
						if t_adj != Vector2i(-1, -1):
							return t_adj

	var j_adj := find_closest_walkable_adjacent(job.target_cell, villager.cell)
	return j_adj if j_adj != Vector2i(-1, -1) else villager.cell

## Path Cache (bounded FIFO)
func _make_cache_key(start: Vector2i, goal: Vector2i) -> String:
	return "%d,%d->%d,%d@%d" % [start.x, start.y, goal.x, goal.y, nav_revision]

func get_cached_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var key := _make_cache_key(start, goal)
	if _path_cache.has(key):
		return (_path_cache[key] as Array[Vector2i]).duplicate()
	return []

func store_cached_path(start: Vector2i, goal: Vector2i, path: Array[Vector2i]) -> void:
	if path.is_empty():
		return
	var key := _make_cache_key(start, goal)
	if not _path_cache.has(key):
		_path_cache_order.append(key)
		while _path_cache_order.size() > MAX_PATH_CACHE_ENTRIES:
			var old_key: String = _path_cache_order.pop_front()
			_path_cache.erase(old_key)
	_path_cache[key] = path.duplicate()

## Applies a completed path from PathRequestScheduler to a villager's LocomotionState.
func apply_computed_path(villager: RefCounted, path: Array[Vector2i], expected_intent_key: String, expected_nav_rev: int) -> bool:
	if villager == null or expected_nav_rev != nav_revision:
		return false
	var loc := get_or_create_locomotion(villager)
	if loc.intent_key != expected_intent_key:
		return false
	if path.is_empty():
		loc.path.clear()
		loc.path_index = 0
		loc.is_moving = false
		loc.status = MoveStatus.BLOCKED
		loc.retry_cooldown_left = 2.0
		return false

	loc.path = path.duplicate()
	loc.path_index = 0
	loc.nav_revision = nav_revision
	loc.from_cell = villager.cell
	loc.to_cell = path[1] if path.size() >= 2 else path[0]
	loc.segment_progress = 0.0
	loc.is_moving = (path.size() >= 2 and villager.cell != loc.destination_cell)
	loc.status = MoveStatus.MOVING if loc.is_moving else MoveStatus.ARRIVED
	loc.retry_cooldown_left = 0.0
	if loc.follower != null:
		loc.follower.set_path(path, grid_nav, loc.visual_pos, get_walkability_predicate())
	return true

func _compute_dynamic_target_token(ctx: RefCounted, villager: RefCounted) -> String:
	var j_id: String = String(villager.active_job_id)
	if ctx == null or j_id.is_empty() or ctx.job_board == null:
		return ""
	var job = ctx.job_board.get_job(j_id)
	if job == null:
		return "nojob"
	var r: String = String(villager.role)
	if r == SettlementVillagerDataScript.ROLE_HUNTER or r == SettlementVillagerDataScript.ROLE_WOODCUTTER:
		var wpid: String = String(job.workplace_id)
		var st: RefCounted = ctx.sim_state
		if st != null and st.production_sources.has(wpid):
			var src: Variant = st.production_sources[wpid]
			if src is Dictionary:
				if r == SettlementVillagerDataScript.ROLE_HUNTER:
					var prey_id: String = String(src.get("current_prey_id", ""))
					if not prey_id.is_empty() and world_data != null and world_data.has_method("get_animal_by_id"):
						var animal: Dictionary = world_data.get_animal_by_id(prey_id)
						return "h:%s:%s" % [prey_id, str(animal.get("cell", Vector2i(-1, -1)))]
					return "h:%s" % prey_id
				elif r == SettlementVillagerDataScript.ROLE_WOODCUTTER and src.get("trees") is Array:
					for t in src["trees"]:
						if t is Dictionary and int(t.get("remaining_milli", 0)) > 0 and t.get("cell") is Vector2i:
							return "w:%s" % str(t["cell"])
					return "w:none"
	elif r == SettlementVillagerDataScript.ROLE_HAULER:
		return "haul:%s:%s" % [str(job.source_cell), str(job.dest_cell)]
	elif r == SettlementVillagerDataScript.ROLE_GUARD:
		return "g:%s" % str(job.target_cell)
	return "j:%s" % str(job.target_cell)

## Updates LocomotionState when a villager's intent/destination changes or nav_revision mismatches.
## Returns true if a new path request is needed.
func sync_intent(ctx: RefCounted, villager: RefCounted) -> bool:
	if benchmark_telemetry_enabled:
		bench_sync_intent_calls += 1
	var loc := get_or_create_locomotion(villager)
	var v_life: String = String(villager.life_state)
	var v_task: String = String(villager.task_state)
	var v_rest: String = String(villager.rest_phase)
	var v_role: String = String(villager.role)
	var v_job: String = String(villager.active_job_id)
	var v_wt: String = String(villager.work_target_id)
	var v_hb: String = String(villager.home_building_id)
	var v_cargo: int = villager.get_carrying_amount()
	var v_cargo_res: String = villager.get_carrying_resource() if v_cargo > 0 else ""
	var dyn_tok: String = _compute_dynamic_target_token(ctx, villager)
	var cell_matches: bool = (loc.status == MoveStatus.MOVING) or (loc.cached_source_cell == villager.cell)

	if (
		loc.has_cached_intent
		and cell_matches
		and loc.cached_nav_revision == nav_revision
		and loc.cached_life_state == v_life
		and loc.cached_task_state == v_task
		and loc.cached_rest_phase == v_rest
		and loc.cached_role == v_role
		and loc.cached_job_id == v_job
		and loc.cached_work_target_id == v_wt
		and loc.cached_home_building_id == v_hb
		and loc.cached_carrying_amount == v_cargo
		and loc.cached_carrying_resource == v_cargo_res
		and loc.cached_dynamic_target_token == dyn_tok
	):
		if benchmark_telemetry_enabled:
			bench_intent_cache_hits += 1
		if loc.status == MoveStatus.WAITING_PATH:
			return true
		if loc.status == MoveStatus.BLOCKED and loc.retry_cooldown_left <= 0.0 and villager.cell != loc.destination_cell:
			loc.status = MoveStatus.WAITING_PATH
			return true
		return false

	if benchmark_telemetry_enabled and loc.has_cached_intent:
		bench_intent_invalidations += 1

	var intent := resolve_intent(ctx, villager)
	var dest: Vector2i = intent["dest_cell"]
	var i_key: String = String(intent["intent_key"])
	loc.focus_cell = intent.get("focus_cell", Vector2i(-1, -1))
	loc.has_valid_focus = bool(intent.get("has_valid_focus", false))

	loc.has_cached_intent = true
	loc.cached_life_state = v_life
	loc.cached_task_state = v_task
	loc.cached_rest_phase = v_rest
	loc.cached_role = v_role
	loc.cached_job_id = v_job
	loc.cached_work_target_id = v_wt
	loc.cached_home_building_id = v_hb
	loc.cached_carrying_amount = v_cargo
	loc.cached_carrying_resource = v_cargo_res
	loc.cached_source_cell = villager.cell
	loc.cached_nav_revision = nav_revision
	loc.cached_dynamic_target_token = dyn_tok

	if loc.intent_key != i_key or loc.destination_cell != dest or loc.nav_revision != nav_revision:
		loc.intent_key = i_key
		loc.destination_cell = dest
		loc.nav_revision = nav_revision
		loc.path.clear()
		loc.path_index = 0
		loc.segment_progress = 0.0
		loc.from_cell = villager.cell
		loc.to_cell = villager.cell
		loc.retry_cooldown_left = 0.0
		if loc.follower != null:
			loc.follower.clear()
		if villager.cell == dest or dest.x < 0 or dest.y < 0:
			loc.is_moving = false
			loc.status = MoveStatus.ARRIVED
			return false
		# Check local path cache before queueing scheduler work
		var cached := get_cached_path(villager.cell, dest)
		if not cached.is_empty():
			apply_computed_path(villager, cached, i_key, nav_revision)
			return false
		loc.is_moving = false
		loc.status = MoveStatus.WAITING_PATH
		return true

	if loc.status == MoveStatus.WAITING_PATH:
		return true
	if loc.status == MoveStatus.BLOCKED and loc.retry_cooldown_left <= 0.0 and villager.cell != dest:
		loc.status = MoveStatus.WAITING_PATH
		return true
	return false

## Far-LOD event/checkpoint invalidation: never teleports `villager.cell`, only clears stale routes.
func invalidate_stale_far_intent(ctx: RefCounted, villager: RefCounted) -> void:
	if villager == null:
		return
	var vid: String = String(villager.villager_id)
	if not _locomotion_by_vid.has(vid):
		return
	var loc: LocomotionState = _locomotion_by_vid[vid]
	loc.has_cached_intent = false
	loc.path.clear()
	loc.path_index = 0
	loc.segment_progress = 0.0
	loc.from_cell = villager.cell
	loc.to_cell = villager.cell
	loc.visual_pos = IsoMath.map_to_local(villager.cell)
	loc.is_moving = false
	loc.status = MoveStatus.IDLE
	if loc.follower != null:
		loc.follower.clear()
	var intent := resolve_intent(ctx, villager)
	loc.intent_key = String(intent["intent_key"])
	loc.destination_cell = intent["dest_cell"]
	loc.focus_cell = intent.get("focus_cell", Vector2i(-1, -1))
	loc.has_valid_focus = bool(intent.get("has_valid_focus", false))
	loc.nav_revision = nav_revision

## Advances a FAR-LOD villager along a valid cached/computed route at hourly simulation cadence.
## Preserves canonical cell progression without spawning Actors or per-frame loops.
func advance_far_hour(ctx: RefCounted, villager: RefCounted) -> bool:
	if ctx == null or villager == null:
		return false
	if String(villager.life_state) != SettlementVillagerDataScript.LIFE_ALIVE:
		return false
	var intent := resolve_intent(ctx, villager)
	if bool(intent.get("indoor", false)):
		return false
	var dest: Vector2i = intent.get("dest_cell", Vector2i(-1, -1))
	if dest.x < 0 or dest.y < 0 or villager.cell == dest:
		return false
	var path := get_cached_path(villager.cell, dest)
	if path.is_empty() and grid_nav != null:
		path = grid_nav.find_path(villager.cell, dest)
		if not path.is_empty():
			store_cached_path(villager.cell, dest, path)
	if path.is_empty():
		return false
	var start_idx: int = 1 if (path.size() > 1 and path[0] == villager.cell) else 0
	var target_idx: int = mini(path.size() - 1, start_idx + FAR_CELLS_PER_HOUR - 1)
	var moved := false
	var final_cell: Vector2i = villager.cell
	for i in range(start_idx, target_idx + 1):
		var c: Vector2i = path[i]
		if is_cell_walkable(c):
			final_cell = c
			moved = true
		else:
			break
	if not moved or final_cell == villager.cell:
		return false
	villager.cell = final_cell
	_expand_activity_bounds_for_cell(final_cell)
	var vid: String = String(villager.villager_id)
	if _locomotion_by_vid.has(vid):
		var loc: LocomotionState = _locomotion_by_vid[vid]
		loc.from_cell = final_cell
		loc.to_cell = final_cell
		loc.visual_pos = IsoMath.map_to_local(final_cell)
		loc.is_moving = false
		loc.has_cached_intent = false
		loc.path.clear()
		loc.path_index = 0
		loc.segment_progress = 0.0
		loc.status = MoveStatus.ARRIVED if final_cell == dest else MoveStatus.IDLE
		if loc.follower != null:
			loc.follower.clear()
	return true

## Advances continuous Near-LOD locomotion. Writes `villager.cell` ONLY at legitimate cell crossings.
func advance_near(villager: RefCounted, delta: float, speed_mult: float) -> void:
	if villager == null or speed_mult <= 0.0 or delta <= 0.0:
		return
	var loc := get_or_create_locomotion(villager)
	if loc.retry_cooldown_left > 0.0:
		loc.retry_cooldown_left = maxf(0.0, loc.retry_cooldown_left - delta * speed_mult)
	if not loc.is_moving or loc.follower == null or loc.follower.is_finished():
		return

	var step_dist: float = MOVE_SPEED_PX * delta * speed_mult
	var res: Dictionary = loc.follower.advance(loc.visual_pos, step_dist)
	loc.visual_pos = res["position"]
	var new_cell: Vector2i = res["cell"]
	if new_cell != villager.cell and is_cell_walkable(new_cell):
		loc.from_cell = villager.cell
		villager.cell = new_cell
		loc.to_cell = new_cell
		_expand_activity_bounds_for_cell(new_cell)

	var vel: Vector2 = res["velocity"]
	if vel.length_squared() >= ContinuousPathFollowerScript.VEL_DEADZONE_SQ:
		loc.facing_dir = loc.follower.update_facing_from_velocity(vel)
		loc.flip_h = loc.follower.last_flip_h

	if bool(res["arrived"]):
		loc.is_moving = false
		loc.status = MoveStatus.ARRIVED
		loc.segment_progress = 1.0
		if loc.destination_cell.x >= 0 and is_cell_walkable(loc.destination_cell):
			villager.cell = loc.destination_cell
			loc.visual_pos = IsoMath.map_to_local(villager.cell)
			_expand_activity_bounds_for_cell(villager.cell)

## Advances throttled Mid-LOD coarse movement without an active Actor.
func advance_mid(villager: RefCounted, step_seconds: float, speed_mult: float) -> void:
	if villager == null or speed_mult <= 0.0 or step_seconds <= 0.0:
		return
	var loc := get_or_create_locomotion(villager)
	if loc.retry_cooldown_left > 0.0:
		loc.retry_cooldown_left = maxf(0.0, loc.retry_cooldown_left - step_seconds * speed_mult)
	if not loc.is_moving or loc.path.is_empty():
		return

	# Advance discrete cells proportional to MOVE_SPEED_PX (~17.89 px/cell)
	var cells_to_step: int = maxi(1, int(floor((MOVE_SPEED_PX * step_seconds * speed_mult) / 18.0)))
	var cur_idx: int = maxi(0, loc.path_index)
	var next_idx: int = mini(loc.path.size() - 1, cur_idx + cells_to_step)
	if next_idx > cur_idx:
		loc.from_cell = villager.cell
		var target_c: Vector2i = loc.path[next_idx]
		if is_cell_walkable(target_c):
			villager.cell = target_c
			loc.to_cell = target_c
			loc.visual_pos = IsoMath.map_to_local(target_c)
			_expand_activity_bounds_for_cell(target_c)
		loc.path_index = next_idx
	if loc.path_index >= loc.path.size() - 1:
		loc.is_moving = false
		loc.status = MoveStatus.ARRIVED

## Conservative per-settlement world-grid activity bounds (accounts for external Woodcutters/Hunters).
func get_activity_bounds(ctx: RefCounted = null) -> Rect2i:
	if _activity_bounds_dirty:
		_rebuild_activity_bounds(ctx)
	return _activity_bounds

func reset_benchmark_metrics() -> void:
	bench_sync_intent_calls = 0
	bench_resolve_intent_calls = 0
	bench_find_adjacent_calls = 0
	bench_intent_cache_hits = 0
	bench_intent_invalidations = 0

func get_benchmark_metrics() -> Dictionary:
	return {
		"sync_intent_calls": bench_sync_intent_calls,
		"resolve_intent_calls": bench_resolve_intent_calls,
		"find_adjacent_calls": bench_find_adjacent_calls,
		"intent_cache_hits": bench_intent_cache_hits,
		"intent_invalidations": bench_intent_invalidations,
	}

func _expand_activity_bounds_for_cell(c: Vector2i) -> void:
	if _activity_bounds_dirty:
		return
	if not _activity_bounds.has_point(c):
		_activity_bounds = _activity_bounds.merge(Rect2i(c, Vector2i.ONE))

func _rebuild_activity_bounds(ctx: RefCounted) -> void:
	var b: Rect2i = _base_bounds.grow(DEFAULT_ACTIVITY_MARGIN_CELLS)
	if ctx != null:
		for v in ctx.get_all_villagers():
			if v != null:
				b = b.merge(Rect2i(v.cell, Vector2i.ONE))
		if ctx.sim_state != null:
			for wpid in ctx.sim_state.production_sources.keys():
				var src: Variant = ctx.sim_state.production_sources[wpid]
				if not (src is Dictionary):
					continue
				if src.get("trees") is Array:
					for t in src["trees"]:
						if t is Dictionary and int(t.get("remaining_milli", 0)) > 0 and t.get("cell") is Vector2i:
							b = b.merge(Rect2i(t["cell"], Vector2i.ONE))
				var prey_id: String = String(src.get("current_prey_id", ""))
				if not prey_id.is_empty() and world_data != null and world_data.has_method("get_animal_by_id"):
					var anim: Dictionary = world_data.get_animal_by_id(prey_id)
					if not anim.is_empty() and anim.get("cell") is Vector2i:
						b = b.merge(Rect2i(anim["cell"], Vector2i.ONE))
	_activity_bounds = b
	_activity_bounds_dirty = false
