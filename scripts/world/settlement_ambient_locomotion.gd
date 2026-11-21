class_name SettlementAmbientLocomotion
extends RefCounted
## M1 Canonical Road-Graph Idle Wandering Stepper.
## Owned by SettlementSimulationManager (simulation side).
## Advances SettlementVillagerData.cell along validated settlement road graphs
## strictly on canonical simulation time, completely independent of Camera2D,
## zoom, Near/Mid/Far LOD, Actor pooling, or render FPS.
## Emits ZERO A* PathRequestScheduler requests.

const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const ContinuousPathFollowerScript = preload("res://scripts/navigation/continuous_path_follower.gd")

const DIRS_4: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
	Vector2i(0, -1),
]

const MAX_EVENTS_PER_TICK: int = 32
const MAX_CANDIDATES_PER_TICK: int = 64
const FIXED_STEP_SIM_SEC: float = 0.1
const STEP_DURATION_SIM_SEC: float = 0.9
const DWELL_MIN_SIM_SEC: float = 1.8
const DWELL_MAX_SIM_SEC: float = 4.8
const BURST_MIN_STEPS: int = 2
const BURST_MAX_STEPS: int = 5
const RECENT_HISTORY_LEN: int = 4
const DWELL_TURN_PROB: float = 0.45

class RoadGraph extends RefCounted:
	var settlement_id: String = ""
	var valid: bool = false
	var invalid_reason: String = ""
	var road_cells: Array[Vector2i] = []
	var road_set: Dictionary = {} # Vector2i -> true
	var neighbors: Dictionary = {} # Vector2i -> Array[Vector2i]

class AmbientState extends RefCounted:
	var committed_cell: Vector2i = Vector2i(-1, -1)
	var step_from: Vector2i = Vector2i(-1, -1)
	var step_to: Vector2i = Vector2i(-1, -1)
	var step_start_time: float = 0.0
	var step_end_time: float = 0.0
	var dwell_end_time: float = 0.0
	var dwell_turn_time: float = -1.0
	var dwell_turned: bool = false
	var prev_cell: Vector2i = Vector2i(-1, -1)
	var recent_cells: Array[Vector2i] = []
	var burst_total_steps: int = 0
	var burst_step_index: int = 0
	var burst_steps_remaining: int = 0
	var facing_dir: int = ContinuousPathFollowerScript.ScreenDir.E
	var flip_h: bool = false
	var rng_step_seq: int = 0
	var is_stepping: bool = false
	var initialized: bool = false

var world_seed: int = 12345
var sim_clock_sec: float = 0.0
var _sim_accum_sec: float = 0.0
var _fixed_tick_seq: int = 0
var _fixed_clock_sec: float = 0.0

var _graphs_by_sid: Dictionary = {} # settlement_id -> RoadGraph
var _states_by_key: Dictionary = {} # "<sid>:<vid>" -> AmbientState
var _reserved_by_sid: Dictionary = {} # sid -> Dictionary (Vector2i -> int count)
var _rr_sid_cursor: int = 0
var _rr_vid_cursor_by_sid: Dictionary = {} # sid -> int

# M1 Opt-In Telemetry Counters
var benchmark_telemetry_enabled: bool = false
var _bench_events_processed: int = 0
var _bench_events_overdue: int = 0
var _bench_candidate_checks: int = 0
var _bench_neighbor_evals: int = 0
var _bench_cell_commits: int = 0
var _bench_service_counts_by_sid: Dictionary = {}

func reset_all() -> void:
	sim_clock_sec = 0.0
	_sim_accum_sec = 0.0
	_fixed_tick_seq = 0
	_fixed_clock_sec = 0.0
	_graphs_by_sid.clear()
	_states_by_key.clear()
	_reserved_by_sid.clear()
	_rr_sid_cursor = 0
	_rr_vid_cursor_by_sid.clear()
	reset_benchmark_metrics()

func reset_benchmark_metrics() -> void:
	_bench_events_processed = 0
	_bench_events_overdue = 0
	_bench_candidate_checks = 0
	_bench_neighbor_evals = 0
	_bench_cell_commits = 0
	_bench_service_counts_by_sid.clear()

func get_benchmark_metrics() -> Dictionary:
	return {
		"sim_clock_sec": sim_clock_sec,
		"events_processed": _bench_events_processed,
		"events_overdue": _bench_events_overdue,
		"candidate_checks": _bench_candidate_checks,
		"neighbor_evals": _bench_neighbor_evals,
		"cell_commits": _bench_cell_commits,
		"ambient_astar_requests": 0,
		"service_counts_by_sid": _bench_service_counts_by_sid.duplicate(),
	}

func configure_from_world_data(world_data: RefCounted) -> void:
	_graphs_by_sid.clear()
	_reserved_by_sid.clear()
	if world_data == null or world_data.get("settlements") == null:
		return
	var s_val: Variant = world_data.get("seed_value")
	if s_val != null:
		world_seed = int(s_val)
	for stl in world_data.settlements:
		if stl != null:
			register_settlement_road_graph(stl, world_data)

func register_settlement_road_graph(stl: RefCounted, world_data: RefCounted) -> RoadGraph:
	var rg := RoadGraph.new()
	if stl == null:
		rg.invalid_reason = "null_settlement"
		return rg
	var sid: String = String(stl.settlement_id)
	rg.settlement_id = sid
	if sid.is_empty():
		rg.invalid_reason = "empty_settlement_id"
		return rg

	var map_w: int = int(world_data.map_width) if (world_data != null and world_data.get("map_width") != null) else 64
	var map_h: int = int(world_data.map_height) if (world_data != null and world_data.get("map_height") != null) else 64

	var b_set := {}
	if stl.has_method("get_building_cells"):
		for bc in stl.get_building_cells():
			b_set[bc] = true

	var raw_roads: Array = stl.roads if stl.get("roads") is Array else []
	for rc in raw_roads:
		if not (rc is Vector2i):
			continue
		var c: Vector2i = rc
		if c.x < 0 or c.x >= map_w or c.y < 0 or c.y >= map_h:
			rg.valid = false
			rg.invalid_reason = "road_out_of_bounds"
			_graphs_by_sid[sid] = rg
			return rg
		if b_set.has(c):
			rg.valid = false
			rg.invalid_reason = "road_overlaps_building"
			_graphs_by_sid[sid] = rg
			return rg
		if world_data != null and world_data.get("terrain") != null:
			var t_type: int = int(world_data.terrain[c.x][c.y])
			var is_water: bool = (t_type == 0) # WorldGenerator.TerrainType.WATER == 0
			var has_bridge: bool = (world_data.get("bridge_walkable_cells") is Dictionary and world_data.bridge_walkable_cells.has(c))
			if is_water and not has_bridge:
				rg.valid = false
				rg.invalid_reason = "road_on_water"
				_graphs_by_sid[sid] = rg
				return rg
			if world_data.get("occupancy") != null and bool(world_data.occupancy[c.x][c.y]):
				rg.valid = false
				rg.invalid_reason = "road_occupied"
				_graphs_by_sid[sid] = rg
				return rg
		if not rg.road_set.has(c):
			rg.road_set[c] = true
			rg.road_cells.append(c)

	if rg.road_cells.is_empty():
		rg.valid = false
		rg.invalid_reason = "empty_roads"
		_graphs_by_sid[sid] = rg
		return rg

	# Build deterministic 4-neighbor adjacency
	for c in rg.road_cells:
		var nbrs: Array[Vector2i] = []
		for d in DIRS_4:
			var nc: Vector2i = c + d
			if rg.road_set.has(nc):
				nbrs.append(nc)
		rg.neighbors[c] = nbrs

	# Validate single 4-connected component
	var visited := {}
	var q: Array[Vector2i] = [rg.road_cells[0]]
	visited[rg.road_cells[0]] = true
	while not q.is_empty():
		var cur: Vector2i = q.pop_front()
		for nb in rg.neighbors.get(cur, []):
			if not visited.has(nb):
				visited[nb] = true
				q.append(nb)

	if visited.size() != rg.road_cells.size():
		rg.valid = false
		rg.invalid_reason = "disconnected_road_graph"
		_graphs_by_sid[sid] = rg
		return rg

	rg.valid = true
	rg.invalid_reason = ""
	_graphs_by_sid[sid] = rg
	if not _reserved_by_sid.has(sid):
		_reserved_by_sid[sid] = {}
	return rg

func get_road_graph(settlement_id: String) -> RoadGraph:
	return _graphs_by_sid.get(settlement_id, null)

func has_valid_road_graph(settlement_id: String) -> bool:
	var rg: RoadGraph = _graphs_by_sid.get(settlement_id, null)
	return rg != null and rg.valid

func is_villager_eligible(settlement_id: String, v: RefCounted) -> bool:
	if v == null:
		return false
	if not has_valid_road_graph(settlement_id):
		return false
	if String(v.life_state) != SettlementVillagerDataScript.LIFE_ALIVE:
		return false
	if String(v.task_state) != SettlementVillagerDataScript.TASK_IDLE:
		return false
	if String(v.rest_phase) != SettlementVillagerDataScript.REST_NONE:
		return false
	if not String(v.active_job_id).is_empty():
		return false
	if not String(v.work_target_id).is_empty():
		return false
	if v.get_carrying_amount() > 0:
		return false
	var rg: RoadGraph = _graphs_by_sid[settlement_id]
	if rg.road_set.has(v.cell):
		return true
	for d in DIRS_4:
		if rg.road_set.has(v.cell + d):
			return true
	return false

func is_villager_ambient_active(settlement_id: String, villager_id: String) -> bool:
	var key := "%s:%s" % [settlement_id, villager_id]
	var st: AmbientState = _states_by_key.get(key, null)
	return st != null and st.initialized

func cancel_villager(settlement_id: String, villager_id: String) -> void:
	var key := "%s:%s" % [settlement_id, villager_id]
	var st: AmbientState = _states_by_key.get(key, null)
	if st == null:
		return
	if st.is_stepping and st.step_to.x >= 0:
		_unreserve_cell(settlement_id, st.step_to)
	_states_by_key.erase(key)

func _reserve_cell(sid: String, cell: Vector2i) -> void:
	if not _reserved_by_sid.has(sid):
		_reserved_by_sid[sid] = {}
	var d: Dictionary = _reserved_by_sid[sid]
	d[cell] = int(d.get(cell, 0)) + 1

func _unreserve_cell(sid: String, cell: Vector2i) -> void:
	if not _reserved_by_sid.has(sid):
		return
	var d: Dictionary = _reserved_by_sid[sid]
	var cnt: int = int(d.get(cell, 0)) - 1
	if cnt <= 0:
		d.erase(cell)
	else:
		d[cell] = cnt

func _deterministic_rng(sid: String, vid: String, seq: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	var h: int = hash(world_seed) ^ hash(sid) ^ hash(vid) ^ hash(seq)
	rng.seed = h
	return rng

func _update_facing_for_step(st: AmbientState, from_c: Vector2i, to_c: Vector2i) -> void:
	var delta_px: Vector2 = IsoMath.map_to_local(to_c) - IsoMath.map_to_local(from_c)
	if delta_px.length_squared() >= 0.001:
		var dir_enum: int = ContinuousPathFollowerScript.classify_screen_direction(delta_px, st.facing_dir)
		st.facing_dir = dir_enum
		st.flip_h = ContinuousPathFollowerScript.should_flip_h(dir_enum, st.flip_h)

func _push_recent_cell(st: AmbientState, cell: Vector2i) -> void:
	if cell.x < 0:
		return
	st.recent_cells.append(cell)
	while st.recent_cells.size() > RECENT_HISTORY_LEN:
		st.recent_cells.pop_front()

func _schedule_dwell(st: AmbientState, sid: String, vid: String, base_time: float) -> void:
	var d_rng := _deterministic_rng(sid, vid, st.rng_step_seq)
	st.rng_step_seq += 1
	var dwell_dur: float = d_rng.randf_range(DWELL_MIN_SIM_SEC, DWELL_MAX_SIM_SEC)
	st.dwell_end_time = base_time + dwell_dur
	st.dwell_turned = false
	if d_rng.randf() < DWELL_TURN_PROB:
		st.dwell_turn_time = base_time + dwell_dur * d_rng.randf_range(0.35, 0.72)
	else:
		st.dwell_turn_time = -1.0

func _apply_idle_dwell_turn(rg: RoadGraph, sid: String, vid: String, st: AmbientState, cur_cell: Vector2i) -> void:
	st.dwell_turned = true
	var nbrs: Array = rg.neighbors.get(cur_cell, [])
	if not nbrs.is_empty():
		var t_rng := _deterministic_rng(sid, vid, st.rng_step_seq)
		st.rng_step_seq += 1
		var target_c: Vector2i = nbrs[t_rng.randi_range(0, nbrs.size() - 1)]
		_update_facing_for_step(st, cur_cell, target_c)
	else:
		st.flip_h = not st.flip_h
		st.facing_dir = ContinuousPathFollowerScript.ScreenDir.W if st.flip_h else ContinuousPathFollowerScript.ScreenDir.E

func _pick_next_road_cell(rg: RoadGraph, sid: String, vid: String, st: AmbientState, cur_cell: Vector2i) -> Vector2i:
	var candidates: Array[Vector2i] = []
	if rg.road_set.has(cur_cell):
		for nb in rg.neighbors.get(cur_cell, []):
			candidates.append(nb)
	else:
		# One-step connector from adjacent spawn/idle cell onto road graph
		for d in DIRS_4:
			var nc: Vector2i = cur_cell + d
			if rg.road_set.has(nc):
				candidates.append(nc)

	if candidates.is_empty():
		return Vector2i(-1, -1)

	var res_dict: Dictionary = _reserved_by_sid.get(sid, {})
	var last_delta: Vector2i = (cur_cell - st.prev_cell) if st.prev_cell.x >= 0 else Vector2i.ZERO
	var best_score: int = 999999
	var best_cands: Array[Vector2i] = []
	for cand in candidates:
		if benchmark_telemetry_enabled:
			_bench_neighbor_evals += 1
		var occ: int = int(res_dict.get(cand, 0))
		var anti_osc: int = 100 if (cand == st.prev_cell and candidates.size() > 1) else 0
		var recent_hits: int = 0
		if candidates.size() > 1:
			for rc in st.recent_cells:
				if rc == cand:
					recent_hits += 1
		var straight_bonus: int = -3 if (last_delta != Vector2i.ZERO and (cand - cur_cell) == last_delta) else 0
		var score: int = occ * 25 + anti_osc + recent_hits * 15 + straight_bonus
		if score < best_score:
			best_score = score
			best_cands = [cand]
		elif score == best_score:
			best_cands.append(cand)

	if best_cands.size() == 1:
		return best_cands[0]
	var rng := _deterministic_rng(sid, vid, st.rng_step_seq)
	st.rng_step_seq += 1
	return best_cands[rng.randi_range(0, best_cands.size() - 1)]

func step_simulation_time(sim_dt: float, sim_manager: Object) -> void:
	if sim_dt <= 0.0 or sim_manager == null:
		return
	sim_clock_sec += sim_dt
	_sim_accum_sec += sim_dt
	while _sim_accum_sec + 0.000001 >= FIXED_STEP_SIM_SEC:
		_sim_accum_sec = maxf(0.0, _sim_accum_sec - FIXED_STEP_SIM_SEC)
		_fixed_tick_seq += 1
		_fixed_clock_sec = float(_fixed_tick_seq) * FIXED_STEP_SIM_SEC
		_step_fixed_tick(sim_manager)

func _step_fixed_tick(sim_manager: Object) -> void:
	var sids: Array[String] = sim_manager.get_registered_settlement_ids()
	if sids.is_empty():
		return
	var s_count: int = sids.size()

	var events_left: int = MAX_EVENTS_PER_TICK
	var checks_left: int = MAX_CANDIDATES_PER_TICK
	var sid_passes: int = 0
	while events_left > 0 and checks_left > 0 and sid_passes < s_count:
		var sid: String = sids[_rr_sid_cursor % s_count]
		_rr_sid_cursor = (_rr_sid_cursor + 1) % s_count
		sid_passes += 1

		var ctx = sim_manager.get_context(sid)
		if ctx == null:
			continue
		var villagers: Array = ctx.get_all_villagers_cached_view()
		var v_count: int = villagers.size()
		if v_count == 0:
			continue

		var v_cursor: int = int(_rr_vid_cursor_by_sid.get(sid, 0)) % v_count
		var per_stl_cap: int = mini(v_count, maxi(1, ceili(float(MAX_CANDIDATES_PER_TICK) / float(s_count))))
		var scanned: int = 0
		while scanned < per_stl_cap and checks_left > 0 and events_left > 0:
			var v = villagers[v_cursor]
			v_cursor = (v_cursor + 1) % v_count
			scanned += 1
			checks_left -= 1
			if benchmark_telemetry_enabled:
				_bench_candidate_checks += 1
			if v == null:
				continue
			var vid: String = String(v.villager_id)
			var key := "%s:%s" % [sid, vid]

			if not is_villager_eligible(sid, v):
				cancel_villager(sid, vid)
				continue

			var rg: RoadGraph = _graphs_by_sid[sid]
			var st: AmbientState = _states_by_key.get(key, null)
			if st == null:
				st = AmbientState.new()
				st.initialized = true
				st.committed_cell = v.cell
				st.step_from = v.cell
				st.step_to = Vector2i(-1, -1)
				st.is_stepping = false
				st.rng_step_seq = 0
				_schedule_dwell(st, sid, vid, _fixed_clock_sec)
				_states_by_key[key] = st
				continue

			# Advance due step-completion, dwell-turn, and burst-start events deterministically by fixed timestamp
			while events_left > 0:
				if st.is_stepping:
					if _fixed_clock_sec + 0.000001 < st.step_end_time:
						break
					var event_t: float = st.step_end_time
					_unreserve_cell(sid, st.step_to)
					st.prev_cell = st.committed_cell
					_push_recent_cell(st, st.committed_cell)
					v.cell = st.step_to
					st.committed_cell = st.step_to
					st.burst_steps_remaining -= 1
					if benchmark_telemetry_enabled:
						_bench_cell_commits += 1

					if st.burst_steps_remaining > 0:
						var next_c: Vector2i = _pick_next_road_cell(rg, sid, vid, st, v.cell)
						var is_dead_end_reversal: bool = (next_c == st.prev_cell and rg.neighbors.get(v.cell, []).size() <= 1)
						if next_c.x >= 0 and not is_dead_end_reversal:
							st.burst_step_index += 1
							st.step_from = v.cell
							st.step_to = next_c
							st.step_start_time = event_t
							st.step_end_time = event_t + STEP_DURATION_SIM_SEC
							st.is_stepping = true
							_reserve_cell(sid, next_c)
							_update_facing_for_step(st, st.step_from, st.step_to)
							events_left -= 1
							if benchmark_telemetry_enabled:
								_bench_events_processed += 1
								_bench_service_counts_by_sid[sid] = int(_bench_service_counts_by_sid.get(sid, 0)) + 1
							continue

					st.burst_steps_remaining = 0
					st.step_from = st.committed_cell
					st.step_to = Vector2i(-1, -1)
					st.is_stepping = false
					_schedule_dwell(st, sid, vid, event_t)
					events_left -= 1
					if benchmark_telemetry_enabled:
						_bench_events_processed += 1
						_bench_service_counts_by_sid[sid] = int(_bench_service_counts_by_sid.get(sid, 0)) + 1
				else:
					if st.dwell_turn_time > 0.0 and not st.dwell_turned and _fixed_clock_sec + 0.000001 >= st.dwell_turn_time:
						_apply_idle_dwell_turn(rg, sid, vid, st, v.cell)
					if _fixed_clock_sec + 0.000001 < st.dwell_end_time:
						break
					var dwell_t: float = st.dwell_end_time
					var next_c: Vector2i = _pick_next_road_cell(rg, sid, vid, st, v.cell)
					if next_c.x < 0:
						_schedule_dwell(st, sid, vid, dwell_t)
						events_left -= 1
						if benchmark_telemetry_enabled:
							_bench_events_processed += 1
						break
					var b_rng := _deterministic_rng(sid, vid, st.rng_step_seq)
					st.rng_step_seq += 1
					st.burst_total_steps = b_rng.randi_range(BURST_MIN_STEPS, BURST_MAX_STEPS)
					st.burst_step_index = 0
					st.burst_steps_remaining = st.burst_total_steps
					st.committed_cell = v.cell
					st.step_from = v.cell
					st.step_to = next_c
					st.step_start_time = dwell_t
					st.step_end_time = dwell_t + STEP_DURATION_SIM_SEC
					st.is_stepping = true
					_reserve_cell(sid, next_c)
					_update_facing_for_step(st, st.step_from, st.step_to)
					events_left -= 1
					if benchmark_telemetry_enabled:
						_bench_events_processed += 1
						_bench_service_counts_by_sid[sid] = int(_bench_service_counts_by_sid.get(sid, 0)) + 1
		_rr_vid_cursor_by_sid[sid] = v_cursor

	if benchmark_telemetry_enabled and events_left == 0:
		for sid_o in sids:
			var ctx_o = sim_manager.get_context(sid_o)
			if ctx_o == null:
				continue
			for vo in ctx_o.get_all_villagers_cached_view():
				if vo == null:
					continue
				var sto: AmbientState = _states_by_key.get("%s:%s" % [sid_o, String(vo.villager_id)], null)
				if sto == null:
					continue
				if (sto.is_stepping and _fixed_clock_sec + 0.000001 >= sto.step_end_time) or (not sto.is_stepping and _fixed_clock_sec + 0.000001 >= sto.dwell_end_time):
					_bench_events_overdue += 1

static func ease_burst_progress(u: float, is_first: bool, is_last: bool) -> float:
	var uc: float = clampf(u, 0.0, 1.0)
	if is_first and is_last:
		return uc * uc * (3.0 - 2.0 * uc)
	if is_first:
		return 2.0 * uc * uc - uc * uc * uc
	if is_last:
		var inv: float = 1.0 - uc
		return 1.0 - (2.0 * inv * inv - inv * inv * inv)
	return uc

func get_visual_interpolation(settlement_id: String, villager_id: String, fallback_cell: Vector2i) -> Dictionary:
	var key := "%s:%s" % [settlement_id, villager_id]
	var st: AmbientState = _states_by_key.get(key, null)
	if st == null or not st.initialized:
		return {
			"active": false,
			"visual_pos": IsoMath.map_to_local(fallback_cell),
			"facing_dir": ContinuousPathFollowerScript.ScreenDir.E,
			"flip_h": false,
			"is_moving": false,
			"step_from": fallback_cell,
			"step_to": Vector2i(-1, -1),
			"burst_step_index": 0,
			"burst_total_steps": 0,
		}
	if not st.is_stepping or st.step_to.x < 0:
		return {
			"active": true,
			"visual_pos": IsoMath.map_to_local(st.committed_cell),
			"facing_dir": st.facing_dir,
			"flip_h": st.flip_h,
			"is_moving": false,
			"step_from": st.committed_cell,
			"step_to": Vector2i(-1, -1),
			"burst_step_index": 0,
			"burst_total_steps": 0,
		}
	var dur: float = maxf(0.001, st.step_end_time - st.step_start_time)
	var u: float = clampf((sim_clock_sec - st.step_start_time) / dur, 0.0, 1.0)
	var is_first: bool = (st.burst_step_index == 0)
	var is_last: bool = (st.burst_steps_remaining <= 1)
	var eased_t: float = ease_burst_progress(u, is_first, is_last)
	var p0: Vector2 = IsoMath.map_to_local(st.step_from)
	var p1: Vector2 = IsoMath.map_to_local(st.step_to)
	return {
		"active": true,
		"visual_pos": p0.lerp(p1, eased_t),
		"facing_dir": st.facing_dir,
		"flip_h": st.flip_h,
		"is_moving": true,
		"step_from": st.step_from,
		"step_to": st.step_to,
		"burst_step_index": st.burst_step_index,
		"burst_total_steps": st.burst_total_steps,
	}
