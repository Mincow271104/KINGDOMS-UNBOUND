class_name RivalPresentationController
extends Node
## Phase 6 Presentation & Hybrid LOD Coordinator for Rival Settlement Villagers.
## Owned by WorldView; coordinates SettlementNavigationContext, PathRequestScheduler,
## RivalVillagerActorPool, Camera/FogOfWar gating, and Near/Mid/Far LOD transitions.
## Never owns canonical NPC state, economy, production, or immigration.

const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementNavigationContextScript = preload("res://scripts/world/settlement_navigation_context.gd")
const PathRequestSchedulerScript = preload("res://scripts/world/path_request_scheduler.gd")
const RivalVillagerActorPoolScript = preload("res://scripts/world/rival_villager_actor_pool.gd")
const GridNavigationScript = preload("res://scripts/navigation/grid_navigation.gd")
const WorkerPresentationResolverScript = preload("res://scripts/world/worker_presentation_resolver.gd")

enum LODTier {
	FAR = 0,
	MID = 1,
	NEAR = 2
}

# Provisional Phase 6 Presentation & LOD Tuning Constants
const MAX_HYDRATIONS_PER_FRAME: int = 8
const MID_STEP_INTERVAL_SEC: float = 0.25
const NEAR_ENTER_WORLD_PX: float = 64.0
const NEAR_EXIT_WORLD_PX: float = 128.0
const MID_ENTER_WORLD_PX: float = 320.0
const MID_EXIT_WORLD_PX: float = 448.0

var sim_manager: Node = null
var world_data: RefCounted = null
var grid_nav: GridNavigation = null
var camera: Camera2D = null
var fog_of_war: RefCounted = null
var debug_fog_disabled: bool = false

var _pool_container: Node2D = null
var _worker_pres_resolver: WorkerPresentationResolverScript = WorkerPresentationResolverScript.new()
var _worker_pres_result: WorkerPresentationResolverScript.PresentationResult = WorkerPresentationResolverScript.PresentationResult.new()
var _settlement_groups_provider: Callable = Callable() # func(sid: String) -> Node2D

var _nav_contexts_by_sid: Dictionary = {} # settlement_id -> SettlementNavigationContext
var _path_scheduler: RefCounted = null
var _actor_pool: RefCounted = null
var _villager_lod_by_key: Dictionary = {} # "<sid>:<vid>" -> LODTier
var _settlement_lod_by_sid: Dictionary = {} # sid -> LODTier

var _mid_accum_sec: float = 0.0
var _last_frame_hydrations: int = 0
var _last_far_settlements_skipped: int = 0
var _last_far_villagers_scanned: int = 0

# M0 Opt-In Benchmark Telemetry (disabled by default; zero gameplay impact)
const BENCH_SAMPLE_CAP: int = 256
var benchmark_telemetry_enabled: bool = false:
	set(value):
		benchmark_telemetry_enabled = value
		if _path_scheduler != null:
			_path_scheduler.benchmark_telemetry_enabled = value
		for nctx in _nav_contexts_by_sid.values():
			if nctx != null:
				nctx.benchmark_telemetry_enabled = value
var _bench_pres_samples_ms: PackedFloat64Array = PackedFloat64Array()
var _bench_pres_cursor: int = 0
var _bench_pres_frames: int = 0
var _bench_pres_total_ms: float = 0.0
var _bench_last_near: int = 0
var _bench_last_mid: int = 0
var _bench_last_far: int = 0
var _bench_last_releases: int = 0
var _bench_total_hydrations: int = 0
var _bench_total_releases: int = 0

func _init() -> void:
	_path_scheduler = PathRequestSchedulerScript.new()
	_actor_pool = RivalVillagerActorPoolScript.new(null, RivalVillagerActorPoolScript.MAX_ACTIVE_ACTORS)

func setup(
	p_sim_manager: Node,
	p_world_data: RefCounted,
	p_grid_nav: GridNavigation,
	p_camera: Camera2D,
	p_fog_of_war: RefCounted,
	p_pool_container: Node2D,
	p_settlement_groups_provider: Callable = Callable()
) -> void:
	sim_manager = p_sim_manager
	world_data = p_world_data
	grid_nav = p_grid_nav if p_grid_nav != null else GridNavigationScript.new(p_world_data)
	camera = p_camera
	fog_of_war = p_fog_of_war
	_pool_container = p_pool_container
	_settlement_groups_provider = p_settlement_groups_provider
	if _actor_pool != null and _pool_container != null:
		_actor_pool.set_pool_container(_pool_container)
	reconcile_settlements()

func get_path_scheduler() -> RefCounted:
	return _path_scheduler

func get_actor_pool() -> RefCounted:
	return _actor_pool

func get_navigation_context(settlement_id: String) -> RefCounted:
	return _nav_contexts_by_sid.get(settlement_id, null)

func get_villager_lod(settlement_id: String, villager_id: String) -> int:
	return int(_villager_lod_by_key.get("%s:%s" % [settlement_id, villager_id], LODTier.FAR))

func get_last_frame_hydrations() -> int:
	return _last_frame_hydrations

func get_last_far_metrics() -> Dictionary:
	return {
		"far_settlements_skipped": _last_far_settlements_skipped,
		"far_villagers_scanned": _last_far_villagers_scanned
	}

## Synchronizes navigation contexts with currently registered settlements in SimulationManager.
func reconcile_settlements() -> void:
	if sim_manager == null:
		return
	var active_sids: Array[String] = sim_manager.get_registered_settlement_ids()
	var active_set: Dictionary = {}
	for sid in active_sids:
		active_set[sid] = true

	# Clean up removed settlements without touching canonical villagers
	for old_sid in _nav_contexts_by_sid.keys():
		if not active_set.has(old_sid):
			remove_settlement(String(old_sid))

	var all_settlements: Array = world_data.settlements if (world_data != null and world_data.get("settlements") is Array) else []
	var stl_by_sid: Dictionary = {}
	for stl in all_settlements:
		if stl != null:
			stl_by_sid[String(stl.get("settlement_id"))] = stl

	for sid in active_sids:
		var stl_data: RefCounted = stl_by_sid.get(sid, null)
		if not _nav_contexts_by_sid.has(sid):
			var nctx := SettlementNavigationContextScript.new(sid, world_data, grid_nav, stl_data)
			nctx.benchmark_telemetry_enabled = benchmark_telemetry_enabled
			nctx.configure_settlement_geometry(stl_data, all_settlements)
			_nav_contexts_by_sid[sid] = nctx
			var ctx_ref: RefCounted = sim_manager.get_context(sid)
			if ctx_ref != null:
				ctx_ref.set_meta("nav_context", nctx)
		else:
			var existing: RefCounted = _nav_contexts_by_sid[sid]
			existing.world_data = world_data
			existing.grid_nav = grid_nav
			var ctx_ref2: RefCounted = sim_manager.get_context(sid)
			if ctx_ref2 != null:
				ctx_ref2.set_meta("nav_context", existing)

func remove_settlement(settlement_id: String) -> void:
	if sim_manager != null:
		var ctx_rem: RefCounted = sim_manager.get_context(settlement_id)
		if ctx_rem != null:
			if ctx_rem.has_meta("nav_context"):
				ctx_rem.remove_meta("nav_context")
			if ctx_rem.has_meta("lod_is_far"):
				ctx_rem.remove_meta("lod_is_far")
	if _actor_pool != null:
		_actor_pool.release_settlement(settlement_id)
	if _path_scheduler != null:
		_path_scheduler.cancel_settlement(settlement_id)
	if _nav_contexts_by_sid.has(settlement_id):
		_nav_contexts_by_sid[settlement_id].clear_all()
		_nav_contexts_by_sid.erase(settlement_id)
	_settlement_lod_by_sid.erase(settlement_id)
	for k in _villager_lod_by_key.keys():
		if String(k).begins_with("%s:" % settlement_id):
			_villager_lod_by_key.erase(k)

## Must be called before WorldView rebuilds/frees RivalSettlements stl_group nodes.
func on_before_rival_settlements_rebuild() -> void:
	if _actor_pool != null:
		_actor_pool.release_all()

func dispose_all() -> void:
	if _path_scheduler != null:
		_path_scheduler.clear_all()
	if _actor_pool != null:
		_actor_pool.dispose_all()
	for sid in _nav_contexts_by_sid.keys():
		_nav_contexts_by_sid[sid].clear_all()
	_nav_contexts_by_sid.clear()
	_villager_lod_by_key.clear()
	_settlement_lod_by_sid.clear()

## Computes the camera's visible world-space Rect2 accurately across zoom levels.
static func compute_camera_world_rect(cam: Camera2D, fallback_vp_size: Vector2 = Vector2(1280.0, 720.0)) -> Rect2:
	if cam == null:
		return Rect2(-fallback_vp_size * 0.5, fallback_vp_size)
	var vp: Viewport = cam.get_viewport()
	if vp != null:
		var vp_rect: Rect2 = vp.get_visible_rect()
		var inv_xf: Transform2D = cam.get_canvas_transform().affine_inverse()
		var p0: Vector2 = inv_xf * vp_rect.position
		var p1: Vector2 = inv_xf * Vector2(vp_rect.end.x, vp_rect.position.y)
		var p2: Vector2 = inv_xf * vp_rect.end
		var p3: Vector2 = inv_xf * Vector2(vp_rect.position.x, vp_rect.end.y)
		var min_x: float = minf(minf(p0.x, p1.x), minf(p2.x, p3.x))
		var max_x: float = maxf(maxf(p0.x, p1.x), maxf(p2.x, p3.x))
		var min_y: float = minf(minf(p0.y, p1.y), minf(p2.y, p3.y))
		var max_y: float = maxf(maxf(p0.y, p1.y), maxf(p2.y, p3.y))
		return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))

	# Headless fallback (no SceneTree Viewport attached)
	var z: Vector2 = cam.zoom
	var zx: float = maxf(0.01, z.x)
	var zy: float = maxf(0.01, z.y)
	var half_ext := Vector2(fallback_vp_size.x * 0.5 / zx, fallback_vp_size.y * 0.5 / zy)
	return Rect2(cam.global_position - half_ext, half_ext * 2.0)

static func grid_rect_to_world_rect(grid_rect: Rect2i) -> Rect2:
	if grid_rect.size.x <= 0 or grid_rect.size.y <= 0:
		return Rect2()
	var c0 := IsoMath.map_to_local(grid_rect.position)
	var c1 := IsoMath.map_to_local(Vector2i(grid_rect.end.x, grid_rect.position.y))
	var c2 := IsoMath.map_to_local(grid_rect.end)
	var c3 := IsoMath.map_to_local(Vector2i(grid_rect.position.x, grid_rect.end.y))
	var min_x: float = minf(minf(c0.x, c1.x), minf(c2.x, c3.x)) - IsoMath.TILE_WIDTH
	var max_x: float = maxf(maxf(c0.x, c1.x), maxf(c2.x, c3.x)) + IsoMath.TILE_WIDTH
	var min_y: float = minf(minf(c0.y, c1.y), minf(c2.y, c3.y)) - IsoMath.TILE_HEIGHT
	var max_y: float = maxf(maxf(c0.y, c1.y), maxf(c2.y, c3.y)) + IsoMath.TILE_HEIGHT
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))

func is_cell_fog_visible(cell: Vector2i) -> bool:
	if debug_fog_disabled or fog_of_war == null:
		return true
	return fog_of_war.is_visible(cell)

func _classify_point_lod(world_pos: Vector2, prev_lod: int, near_enter: Rect2, near_exit: Rect2, mid_enter: Rect2, mid_exit: Rect2) -> int:
	if prev_lod == LODTier.NEAR:
		if near_exit.has_point(world_pos):
			return LODTier.NEAR
		return LODTier.MID if mid_exit.has_point(world_pos) else LODTier.FAR
	if prev_lod == LODTier.MID:
		if near_enter.has_point(world_pos):
			return LODTier.NEAR
		return LODTier.MID if mid_exit.has_point(world_pos) else LODTier.FAR
	# Previously FAR
	if near_enter.has_point(world_pos):
		return LODTier.NEAR
	if mid_enter.has_point(world_pos):
		return LODTier.MID
	return LODTier.FAR

## Main per-frame update called from WorldView._process(delta).
## When `speed_mult <= 0.0` (Paused), camera/fog visibility & actor release still run,
## while locomotion and walk animation remain frozen.
func update_presentation(delta: float, speed_mult: float) -> void:
	var pres_start_usec: int = Time.get_ticks_usec() if benchmark_telemetry_enabled else 0
	var b_near: int = 0
	var b_mid: int = 0
	var b_far: int = 0
	var b_releases: int = 0
	_last_frame_hydrations = 0
	_last_far_settlements_skipped = 0
	_last_far_villagers_scanned = 0

	if sim_manager == null:
		return
	reconcile_settlements()

	var cam_rect: Rect2 = compute_camera_world_rect(camera)
	var cam_center: Vector2 = cam_rect.get_center()
	var near_enter: Rect2 = cam_rect.grow(NEAR_ENTER_WORLD_PX)
	var near_exit: Rect2 = cam_rect.grow(NEAR_EXIT_WORLD_PX)
	var mid_enter: Rect2 = cam_rect.grow(MID_ENTER_WORLD_PX)
	var mid_exit: Rect2 = cam_rect.grow(MID_EXIT_WORLD_PX)

	var do_mid_step: bool = false
	var mid_dt: float = 0.0
	if speed_mult > 0.0 and delta > 0.0:
		_mid_accum_sec += delta
		if _mid_accum_sec >= MID_STEP_INTERVAL_SEC:
			do_mid_step = true
			mid_dt = _mid_accum_sec
			_mid_accum_sec = 0.0

	var near_hydration_candidates: Array[Dictionary] = []
	var seen_active_keys: Dictionary = {}
	var amb_loc: RefCounted = sim_manager.get_ambient_locomotion() if (sim_manager != null and sim_manager.has_method("get_ambient_locomotion")) else null

	for sid in sim_manager.get_registered_settlement_ids():
		var ctx: RefCounted = sim_manager.get_context(sid)
		var nctx: RefCounted = _nav_contexts_by_sid.get(sid, null)
		if ctx == null or nctx == null:
			continue

		var act_world_rect: Rect2 = grid_rect_to_world_rect(nctx.get_activity_bounds(ctx))
		var prev_stl_lod: int = int(_settlement_lod_by_sid.get(sid, LODTier.FAR))
		var stl_check_rect: Rect2 = mid_exit if prev_stl_lod != LODTier.FAR else mid_enter

		# Far-settlement activity-bounds culling: skip iterating residents of Far settlements
		if not stl_check_rect.intersects(act_world_rect):
			if prev_stl_lod != LODTier.FAR:
				_actor_pool.release_settlement(sid)
				_path_scheduler.cancel_settlement(sid)
				for v_far in ctx.get_all_villagers_cached_view():
					if v_far != null:
						var fk := "%s:%s" % [sid, String(v_far.villager_id)]
						_villager_lod_by_key[fk] = LODTier.FAR
						nctx.invalidate_stale_far_intent(ctx, v_far)
			_settlement_lod_by_sid[sid] = LODTier.FAR
			ctx.set_meta("lod_is_far", true)
			_last_far_settlements_skipped += 1
			if benchmark_telemetry_enabled:
				b_far += ctx.get_villager_count()
			continue

		_settlement_lod_by_sid[sid] = LODTier.MID # Active evaluation band
		ctx.set_meta("lod_is_far", false)
		var faction_id: String = String(ctx.owner_faction_id)
		var stl_parent: Node2D = _resolve_settlement_parent(sid)

		for v in ctx.get_all_villagers_cached_view():
			if v == null:
				continue
			var vid: String = String(v.villager_id)
			var key := "%s:%s" % [sid, vid]
			seen_active_keys[key] = true

			var is_alive: bool = (String(v.life_state) == SettlementVillagerDataScript.LIFE_ALIVE)
			if not is_alive:
				_villager_lod_by_key[key] = LODTier.FAR
				_actor_pool.release(sid, vid)
				_path_scheduler.cancel_villager(sid, vid)
				nctx.remove_villager_locomotion(vid)
				continue

			var is_amb_idle: bool = (amb_loc != null and amb_loc.is_villager_eligible(sid, v))
			var loc: RefCounted = null if is_amb_idle else nctx.get_or_create_locomotion(v)
			var lod_pos: Vector2 = IsoMath.map_to_local(v.cell) if is_amb_idle else loc.visual_pos
			var prev_lod: int = int(_villager_lod_by_key.get(key, LODTier.FAR))
			var new_lod: int = _classify_point_lod(lod_pos, prev_lod, near_enter, near_exit, mid_enter, mid_exit)
			_villager_lod_by_key[key] = new_lod

			if new_lod == LODTier.FAR:
				if benchmark_telemetry_enabled:
					b_far += 1
				if prev_lod != LODTier.FAR:
					if _actor_pool.release(sid, vid):
						b_releases += 1
					_path_scheduler.cancel_villager(sid, vid)
				if not is_amb_idle:
					nctx.invalidate_stale_far_intent(ctx, v)
				continue
			elif benchmark_telemetry_enabled:
				if new_lod == LODTier.NEAR:
					b_near += 1
				else:
					b_mid += 1

			var fog_vis: bool = is_cell_fog_visible(v.cell)
			if is_amb_idle:
				if _path_scheduler.has_request(sid, vid):
					_path_scheduler.cancel_villager(sid, vid)
				if new_lod != LODTier.NEAR or not fog_vis:
					if _actor_pool.release(sid, vid):
						b_releases += 1
					continue
				var amb_interp: Dictionary = amb_loc.get_visual_interpolation(sid, vid, v.cell)
				var step_to_c: Vector2i = amb_interp.get("step_to", Vector2i(-1, -1))
				if bool(amb_interp.get("is_moving", false)) and step_to_c.x >= 0 and not is_cell_fog_visible(step_to_c):
					if _actor_pool.release(sid, vid):
						b_releases += 1
					continue
				var amb_pos: Vector2 = amb_interp.get("visual_pos", lod_pos)
				var amb_actor: Node2D = _actor_pool.get_active_actor(sid, vid)
				if amb_actor != null:
					if amb_actor.get_parent() != stl_parent and stl_parent != null:
						amb_actor.get_parent().remove_child(amb_actor)
						stl_parent.add_child(amb_actor)
					var amb_anim_dt: float = (delta * speed_mult) if speed_mult > 0.0 else 0.0
					amb_actor.sync_presentation(
						amb_pos,
						bool(amb_interp.get("flip_h", false)),
						int(amb_interp.get("facing_dir", 0)),
						bool(amb_interp.get("is_moving", false)),
						true,
						amb_anim_dt,
						19.9
					)
				else:
					_insert_top_k_candidate(near_hydration_candidates, {
						"sid": sid,
						"vid": vid,
						"faction_id": faction_id,
						"role": String(v.role),
						"parent": stl_parent,
						"visual_pos": amb_pos,
						"flip_h": bool(amb_interp.get("flip_h", false)),
						"facing_dir": int(amb_interp.get("facing_dir", 0)),
						"is_moving": bool(amb_interp.get("is_moving", false)),
						"dist_sq": amb_pos.distance_squared_to(cam_center),
					}, MAX_HYDRATIONS_PER_FRAME)
				continue

			# Mid or Near (job/rest villagers): sync intent and enqueue path if needed
			var needs_path: bool = nctx.sync_intent(ctx, v)
			if needs_path and loc.destination_cell.x >= 0:
				var prio: int = PathRequestSchedulerScript.PRIO_MID
				if new_lod == LODTier.NEAR:
					prio = PathRequestSchedulerScript.PRIO_VISIBLE_NEAR if fog_vis else PathRequestSchedulerScript.PRIO_NEAR
				_path_scheduler.enqueue(
					sid, vid, v.cell, loc.destination_cell, loc.intent_key, nctx.nav_revision, prio, nctx, v
				)

			# Locomotion (frozen when paused)
			if speed_mult > 0.0 and delta > 0.0:
				if new_lod == LODTier.NEAR:
					nctx.advance_near(v, delta, speed_mult)
				elif do_mid_step:
					nctx.advance_mid(v, mid_dt, speed_mult)

			if (
				String(v.task_state) == SettlementVillagerDataScript.TASK_RESTING
				and String(v.rest_phase) == SettlementVillagerDataScript.REST_RETURNING_HOME
				and loc.status == SettlementNavigationContextScript.MoveStatus.ARRIVED
				and sim_manager.has_method("complete_home_arrival_if_eligible")
			):
				sim_manager.complete_home_arrival_if_eligible(ctx, v)

			# Indoor / Fog-of-War / Actor Hydration
			var is_indoor: bool = (String(v.rest_phase) == SettlementVillagerDataScript.REST_RESTING_INSIDE)
			var can_show: bool = (new_lod == LODTier.NEAR and not is_indoor and fog_vis)

			if not can_show:
				if _actor_pool.release(sid, vid):
					b_releases += 1
				continue

			var actor: Node2D = _actor_pool.get_active_actor(sid, vid)
			if actor != null:
				if actor.get_parent() != stl_parent and stl_parent != null:
					actor.get_parent().remove_child(actor)
					stl_parent.add_child(actor)
				var anim_dt: float = (delta * speed_mult) if speed_mult > 0.0 else 0.0
				_sync_worker_actor_presentation(actor, ctx, v, loc, anim_dt)
			else:
				_insert_top_k_candidate(near_hydration_candidates, {
					"sid": sid,
					"vid": vid,
					"faction_id": faction_id,
					"role": String(v.role),
					"parent": stl_parent,
					"ctx": ctx,
					"v": v,
					"loc": loc,
					"dist_sq": loc.visual_pos.distance_squared_to(cam_center)
				}, MAX_HYDRATIONS_PER_FRAME)

	# Release any orphaned actors (e.g. removed villagers)
	for active_key in _actor_pool.get_all_active_keys():
		if not seen_active_keys.has(active_key):
			var parts: PackedStringArray = active_key.split(":", false, 1)
			if parts.size() == 2:
				_actor_pool.release(parts[0], parts[1])

	# Step bounded incremental A* scheduler
	if speed_mult > 0.0:
		_path_scheduler.step_frame(sim_manager)

	# Bounded per-frame Actor hydration prioritized by proximity to camera center (already top-K sorted)
	if not near_hydration_candidates.is_empty():
		var hydrated_now: int = 0
		for cand in near_hydration_candidates:
			if hydrated_now >= MAX_HYDRATIONS_PER_FRAME:
				break
			var new_actor: Node2D = _actor_pool.acquire(
				String(cand["sid"]),
				String(cand["vid"]),
				String(cand["faction_id"]),
				String(cand["role"]),
				cand["parent"]
			)
			if new_actor == null:
				break # Pool cap reached (excess villagers continue at Mid/Near logic)
			if cand.has("loc"):
				var loc: RefCounted = cand["loc"]
				_sync_worker_actor_presentation(new_actor, cand.get("ctx", null), cand.get("v", null), loc, 0.0)
			else:
				new_actor.sync_presentation(
					cand.get("visual_pos", Vector2.ZERO),
					bool(cand.get("flip_h", false)),
					int(cand.get("facing_dir", 0)),
					bool(cand.get("is_moving", false)),
					true,
					0.0,
					19.9
				)
			hydrated_now += 1
		_last_frame_hydrations = hydrated_now
	if benchmark_telemetry_enabled:
		var pres_ms: float = float(Time.get_ticks_usec() - pres_start_usec) / 1000.0
		_bench_pres_frames += 1
		_bench_pres_total_ms += pres_ms
		_bench_last_near = b_near
		_bench_last_mid = b_mid
		_bench_last_far = b_far
		_bench_last_releases = b_releases
		_bench_total_hydrations += _last_frame_hydrations
		_bench_total_releases += b_releases
		if _bench_pres_samples_ms.size() < BENCH_SAMPLE_CAP:
			_bench_pres_samples_ms.append(pres_ms)
		else:
			_bench_pres_samples_ms[_bench_pres_cursor] = pres_ms
			_bench_pres_cursor = (_bench_pres_cursor + 1) % BENCH_SAMPLE_CAP

func reset_benchmark_metrics() -> void:
	_bench_pres_samples_ms = PackedFloat64Array()
	_bench_pres_cursor = 0
	_bench_pres_frames = 0
	_bench_pres_total_ms = 0.0
	_bench_last_near = 0
	_bench_last_mid = 0
	_bench_last_far = 0
	_bench_last_releases = 0
	_bench_total_hydrations = 0
	_bench_total_releases = 0
	if _path_scheduler != null:
		_path_scheduler.reset_benchmark_metrics()
	for nctx in _nav_contexts_by_sid.values():
		if nctx != null and nctx.has_method("reset_benchmark_metrics"):
			nctx.reset_benchmark_metrics()

func get_benchmark_metrics() -> Dictionary:
	var n: int = _bench_pres_samples_ms.size()
	var avg_ms: float = (_bench_pres_total_ms / float(_bench_pres_frames)) if _bench_pres_frames > 0 else 0.0
	var p95_ms: float = 0.0
	if n > 0:
		var sorted: Array[float] = []
		sorted.resize(n)
		for i in range(n):
			sorted[i] = _bench_pres_samples_ms[i]
		sorted.sort()
		var idx: int = clampi(int(ceil(0.95 * float(n))) - 1, 0, n - 1)
		p95_ms = sorted[idx]
	var sync_calls: int = 0
	var res_calls: int = 0
	var adj_calls: int = 0
	var hit_calls: int = 0
	var inv_calls: int = 0
	for nctx in _nav_contexts_by_sid.values():
		if nctx != null and nctx.has_method("get_benchmark_metrics"):
			var nm: Dictionary = nctx.get_benchmark_metrics()
			sync_calls += int(nm.get("sync_intent_calls", 0))
			res_calls += int(nm.get("resolve_intent_calls", 0))
			adj_calls += int(nm.get("find_adjacent_calls", 0))
			hit_calls += int(nm.get("intent_cache_hits", 0))
			inv_calls += int(nm.get("intent_invalidations", 0))
	var act_cnt: int = _actor_pool.get_active_count() if _actor_pool != null else 0
	return {
		"enabled": benchmark_telemetry_enabled,
		"frames": _bench_pres_frames,
		"avg_pres_ms": avg_ms,
		"p95_pres_ms": p95_ms,
		"near_count": _bench_last_near,
		"mid_count": _bench_last_mid,
		"far_count": _bench_last_far,
		"active_actors": act_cnt,
		"near_without_actor": maxi(0, _bench_last_near - act_cnt),
		"last_frame_hydrations": _last_frame_hydrations,
		"last_frame_releases": _bench_last_releases,
		"total_hydrations": _bench_total_hydrations,
		"total_releases": _bench_total_releases,
		"sync_intent_calls": sync_calls,
		"resolve_intent_calls": res_calls,
		"find_adjacent_calls": adj_calls,
		"intent_cache_hits": hit_calls,
		"intent_invalidations": inv_calls,
		"path_scheduler": _path_scheduler.get_benchmark_metrics() if _path_scheduler != null else {},
	}

func _sync_worker_actor_presentation(actor: Node2D, ctx: RefCounted, v: RefCounted, loc: RefCounted, anim_dt: float) -> void:
	var sim_tm: Node = sim_manager.get("_time_manager") if sim_manager != null else null
	_worker_pres_resolver.resolve_into(ctx, v, loc, world_data, sim_tm, _worker_pres_result)
	if actor.has_method("set_worker_presentation_metadata"):
		actor.set_worker_presentation_metadata(_worker_pres_result)
	var use_flip: bool = loc.flip_h
	var use_facing: int = loc.facing_dir
	var r_str: String = String(v.role) if v != null else ""
	if (
		r_str == SettlementVillagerDataScript.ROLE_FARMER
		or r_str == SettlementVillagerDataScript.ROLE_WOODCUTTER
		or r_str == SettlementVillagerDataScript.ROLE_HUNTER
		or r_str == SettlementVillagerDataScript.ROLE_HAULER
		or r_str == SettlementVillagerDataScript.ROLE_GUARD
	):
		use_flip = _worker_pres_result.flip_h
		use_facing = _worker_pres_result.facing_dir
	actor.sync_presentation(loc.visual_pos, use_flip, use_facing, loc.is_moving, true, anim_dt, SettlementNavigationContextScript.MOVE_SPEED_PX)

func _insert_top_k_candidate(arr: Array[Dictionary], cand: Dictionary, k: int) -> void:
	var d_sq: float = float(cand["dist_sq"])
	var c_sid: String = String(cand["sid"])
	var c_vid: String = String(cand["vid"])
	if arr.size() >= k:
		var last: Dictionary = arr[k - 1]
		var l_sq: float = float(last["dist_sq"])
		if d_sq > l_sq or (is_equal_approx(d_sq, l_sq) and (c_sid > String(last["sid"]) or (c_sid == String(last["sid"]) and c_vid >= String(last["vid"])))):
			return
	var ins_idx: int = arr.size()
	for i in range(arr.size()):
		var cur: Dictionary = arr[i]
		var cur_sq: float = float(cur["dist_sq"])
		if d_sq < cur_sq or (is_equal_approx(d_sq, cur_sq) and (c_sid < String(cur["sid"]) or (c_sid == String(cur["sid"]) and c_vid < String(cur["vid"])))):
			ins_idx = i
			break
	arr.insert(ins_idx, cand)
	if arr.size() > k:
		arr.resize(k)

func _resolve_settlement_parent(sid: String) -> Node2D:
	if _settlement_groups_provider.is_valid():
		var g = _settlement_groups_provider.call(sid)
		if g is Node2D and is_instance_valid(g):
			return g
	return _pool_container
