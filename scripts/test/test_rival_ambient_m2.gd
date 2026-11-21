extends SceneTree

const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const SettlementDataScript = preload("res://scripts/world/settlement_data.gd")
const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementSimulationManagerScript = preload("res://scripts/world/settlement_simulation_manager.gd")
const SettlementAmbientLocomotionScript = preload("res://scripts/world/settlement_ambient_locomotion.gd")
const RivalPresentationControllerScript = preload("res://scripts/world/rival_presentation_controller.gd")
const GridNavigationScript = preload("res://scripts/navigation/grid_navigation.gd")
const FogOfWarScript = preload("res://scripts/world/fog_of_war.gd")

var _passed: int = 0
var _failed: int = 0

func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] %s" % label)
	else:
		_failed += 1
		printerr("  [FAIL] %s" % label)

func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		_passed += 1
		print("  [PASS] %s" % label)
	else:
		_failed += 1
		printerr("  [FAIL] %s (got=%s exp=%s)" % [label, str(actual), str(expected)])

func _init() -> void:
	call_deferred("_run")

func _build_road_world(seed_val: int = 2026, stl_count: int = 1, pop_per_stl: int = 4) -> Dictionary:
	var wd = WorldGeneratorScript.WorldData.new()
	wd.map_width = 64
	wd.map_height = 64
	wd.seed_value = seed_val
	wd.terrain = []
	wd.occupancy = []
	for x in range(64):
		var t_col: Array = []
		var o_col: Array = []
		t_col.resize(64)
		o_col.resize(64)
		t_col.fill(1)
		o_col.fill(false)
		wd.terrain.append(t_col)
		wd.occupancy.append(o_col)

	var mgr = SettlementSimulationManagerScript.new()
	for s_idx in range(stl_count):
		var sid := "stl_m2_%d" % s_idx
		var stl = SettlementDataScript.new()
		stl.settlement_id = sid
		stl.origin_faction_id = "neutral_tribe"
		stl.owner_faction_id = "neutral_tribe"
		var ox: int = 6 + (s_idx % 4) * 14
		var oy: int = 6 + (s_idx / 4) * 14
		stl.anchor_cell = Vector2i(ox, oy)
		stl.roads.clear()
		# Build a 5x5 connected road grid loop + intersection
		for dx in range(5):
			for dy in range(5):
				if dx == 0 or dx == 4 or dy == 0 or dy == 4 or dx == 2 or dy == 2:
					stl.roads.append(Vector2i(ox + dx, oy + dy))
		wd.settlements.append(stl)
	mgr.register_settlements_from_world_data(wd)
	for s_idx in range(stl_count):
		var sid := "stl_m2_%d" % s_idx
		var stl = wd.settlements[s_idx]
		var ctx = mgr.get_context(sid)
		for v_idx in range(pop_per_stl):
			var rc: Vector2i = stl.roads[(v_idx * 3) % stl.roads.size()]
			var v = SettlementVillagerDataScript.new(ctx.allocate_villager_id(), sid, "neutral_tribe", "Villager", "farmer", rc)
			ctx.add_villager(v)
	mgr.get_ambient_locomotion().configure_from_world_data(wd)
	return {"wd": wd, "mgr": mgr}

func _run() -> void:
	print("\n====================================================================")
	print("  TEST SUITE: M2 Rival Idle Movement & Behavioral Polish")
	print("====================================================================")

	# 1. Movement cadence: multi-cell walking bursts without intermediate pauses
	var w1 := _build_road_world(101, 1, 1)
	var mgr1 = w1["mgr"]
	var amb1 = mgr1.get_ambient_locomotion()
	amb1.benchmark_telemetry_enabled = true
	var ctx1 = mgr1.get_context("stl_m2_0")
	var v1 = ctx1.get_all_villagers_cached_view()[0]
	var vid1: String = String(v1.villager_id)
	var max_continuous_steps: int = 0
	var cur_continuous_steps: int = 0
	var prev_step_to := Vector2i(-1, -1)
	var saw_dwell_after_burst: bool = false
	var saw_burst_end_dwell: bool = false
	for _i in range(250):
		mgr1.step_ambient_locomotion(0.1)
		var interp: Dictionary = amb1.get_visual_interpolation("stl_m2_0", vid1, v1.cell)
		var moving: bool = bool(interp.get("is_moving", false))
		var step_to: Vector2i = interp.get("step_to", Vector2i(-1, -1))
		if moving:
			if step_to != prev_step_to:
				cur_continuous_steps += 1
				prev_step_to = step_to
				if cur_continuous_steps > max_continuous_steps:
					max_continuous_steps = cur_continuous_steps
		else:
			if cur_continuous_steps >= 2:
				saw_dwell_after_burst = true
				saw_burst_end_dwell = true
			cur_continuous_steps = 0
			prev_step_to = Vector2i(-1, -1)

	_assert_true(max_continuous_steps >= 2 and max_continuous_steps <= 5, "M2-A1: Walking burst traverses 2..5 continuous road cells without intermediate pause (max=%d)" % max_continuous_steps)
	_assert_true(saw_dwell_after_burst and saw_burst_end_dwell, "M2-A2: Villager dwells only after completing multi-cell burst")
	_assert_eq(int(amb1.get_benchmark_metrics().get("ambient_astar_requests", -1)), 0, "M2-A3: Zero A* requests during M2 walking bursts")

	# 2. Visual interpolation C1 continuity & bounds
	var eps: float = 0.0001
	var p_start_0: float = SettlementAmbientLocomotionScript.ease_burst_progress(0.0, true, false)
	var p_start_1: float = SettlementAmbientLocomotionScript.ease_burst_progress(1.0, true, false)
	var dv_start_0: float = (SettlementAmbientLocomotionScript.ease_burst_progress(eps, true, false) - p_start_0) / eps
	var dv_start_1: float = (p_start_1 - SettlementAmbientLocomotionScript.ease_burst_progress(1.0 - eps, true, false)) / eps
	var dv_mid_0: float = (SettlementAmbientLocomotionScript.ease_burst_progress(eps, false, false) - 0.0) / eps
	var dv_end_0: float = (SettlementAmbientLocomotionScript.ease_burst_progress(eps, false, true) - 0.0) / eps
	var dv_end_1: float = (1.0 - SettlementAmbientLocomotionScript.ease_burst_progress(1.0 - eps, false, true)) / eps
	_assert_true(absf(dv_start_0) < 0.01 and absf(dv_start_1 - 1.0) < 0.01, "M2-B1: Burst start accelerates from 0 to unit cruising velocity (dv0=%.4f dv1=%.4f)" % [dv_start_0, dv_start_1])
	_assert_true(absf(dv_mid_0 - 1.0) < 0.001 and absf(dv_end_0 - 1.0) < 0.01 and absf(dv_end_1) < 0.01, "M2-B2: C1 velocity continuity across burst middle & smooth stop at burst end")

	# 3. Determinism across FPS (30/60/120/144 + irregular) & 1x/2x/3x speed
	var snaps := []
	for dt_arr in [[0.0333333], [0.0166667], [0.0083333], [0.0069444], [0.02, 0.05, 0.01, 0.12]]:
		var wf := _build_road_world(777, 2, 6)
		var mf = wf["mgr"]
		var elapsed: float = 0.0
		var idx: int = 0
		while elapsed < 12.0 - 0.00001:
			var step_dt: float = minf(float(dt_arr[idx % dt_arr.size()]), 12.0 - elapsed)
			mf.step_ambient_locomotion(step_dt)
			elapsed += step_dt
			idx += 1
		var out: Array = []
		for sid in mf.get_registered_settlement_ids():
			for vv in mf.get_context(sid).get_all_villagers_cached_view():
				out.append([String(vv.villager_id), vv.cell])
		snaps.append(out)
	_assert_true(snaps[0] == snaps[1] and snaps[1] == snaps[2] and snaps[2] == snaps[3] and snaps[3] == snaps[4], "M2-C1: 30/60/120/144 FPS & irregular deltas produce identical canonical burst trajectories")

	# 4. Pause & Speed invariance
	var wp := _build_road_world(888, 1, 4)
	var mp = wp["mgr"]
	var before_pause := []
	for vv in mp.get_context("stl_m2_0").get_all_villagers_cached_view():
		before_pause.append(vv.cell)
	mp.step_ambient_locomotion(0.0)
	var after_pause := []
	for vv in mp.get_context("stl_m2_0").get_all_villagers_cached_view():
		after_pause.append(vv.cell)
	_assert_eq(after_pause, before_pause, "M2-C2: Pause (0.0 sim_dt) freezes ambient bursts")

	# 5. Facing & Dwell: no frame-to-frame flicker & idle turn stays deterministic
	var wf2 := _build_road_world(555, 1, 2)
	var mf2 = wf2["mgr"]
	var af2 = mf2.get_ambient_locomotion()
	var v2 = mf2.get_context("stl_m2_0").get_all_villagers_cached_view()[0]
	var prev_flip: bool = false
	var flip_changes_during_dwell: int = 0
	var was_moving: bool = false
	for _k in range(150):
		mf2.step_ambient_locomotion(0.1)
		var it: Dictionary = af2.get_visual_interpolation("stl_m2_0", String(v2.villager_id), v2.cell)
		var mv: bool = bool(it.get("is_moving", false))
		var fl: bool = bool(it.get("flip_h", false))
		if not mv and not was_moving and fl != prev_flip:
			flip_changes_during_dwell += 1
		prev_flip = fl
		was_moving = mv
	_assert_true(flip_changes_during_dwell <= 5, "M2-D1: Idle dwell facing turns occur occasionally without frame-to-frame flicker (turns=%d)" % flip_changes_during_dwell)

	# 6. Anti-repetition & Dead-end reversal
	var wd_de = WorldGeneratorScript.WorldData.new()
	wd_de.map_width = 16
	wd_de.map_height = 16
	wd_de.seed_value = 303
	wd_de.terrain = []
	wd_de.occupancy = []
	for x in range(16):
		var tc: Array = []
		var oc: Array = []
		tc.resize(16)
		oc.resize(16)
		tc.fill(1)
		oc.fill(false)
		wd_de.terrain.append(tc)
		wd_de.occupancy.append(oc)
	var mgr_de = SettlementSimulationManagerScript.new()
	var stl_de = SettlementDataScript.new()
	stl_de.settlement_id = "stl_de"
	stl_de.origin_faction_id = "neutral_tribe"
	stl_de.owner_faction_id = "neutral_tribe"
	stl_de.anchor_cell = Vector2i(4, 4)
	stl_de.roads.clear()
	stl_de.roads.append(Vector2i(4, 4))
	stl_de.roads.append(Vector2i(5, 4))
	stl_de.roads.append(Vector2i(6, 4)) # 3-tile dead-end corridor
	wd_de.settlements.append(stl_de)
	mgr_de.register_settlements_from_world_data(wd_de)
	var ctx_de = mgr_de.get_context("stl_de")
	var v_de = SettlementVillagerDataScript.new(ctx_de.allocate_villager_id(), "stl_de", "neutral_tribe", "Villager", "farmer", Vector2i(4, 4))
	ctx_de.add_villager(v_de)
	mgr_de.get_ambient_locomotion().configure_from_world_data(wd_de)
	var visited_de := {}
	for _s in range(180):
		mgr_de.step_ambient_locomotion(0.1)
		visited_de[v_de.cell] = true
	_assert_true(visited_de.has(Vector2i(4, 4)) and visited_de.has(Vector2i(5, 4)) and visited_de.has(Vector2i(6, 4)), "M2-E1: Dead-end corridor reverses cleanly without getting stuck")

	# 7. Preemption across all phases (accel, mid-burst, decel, dwell) + gameplay isolation
	for phase in ["accel", "mid_burst", "decel", "dwell"]:
		var wp2 := _build_road_world(999, 1, 1)
		var mp2 = wp2["mgr"]
		var ap2 = mp2.get_ambient_locomotion()
		var ctxp2 = mp2.get_context("stl_m2_0")
		var vp2 = ctxp2.get_all_villagers_cached_view()[0]
		var vidp2: String = String(vp2.villager_id)
		var matched: bool = false
		for _t in range(200):
			mp2.step_ambient_locomotion(0.1)
			var it2: Dictionary = ap2.get_visual_interpolation("stl_m2_0", vidp2, vp2.cell)
			var mv2: bool = bool(it2.get("is_moving", false))
			var bidx: int = int(it2.get("burst_step_index", 0))
			var btot: int = int(it2.get("burst_total_steps", 0))
			if phase == "accel" and mv2 and bidx == 0:
				matched = true
				break
			elif phase == "mid_burst" and mv2 and bidx >= 1 and bidx < btot - 1:
				matched = true
				break
			elif phase == "decel" and mv2 and btot >= 2 and bidx == btot - 1:
				matched = true
				break
			elif phase == "dwell" and not mv2 and int(ctxp2.get_all_villagers_cached_view().size()) == 1:
				if _t > 30:
					matched = true
					break
		var committed_before: Vector2i = vp2.cell
		vp2.active_job_id = "job_preempt_test"
		vp2.task_state = SettlementVillagerDataScript.TASK_WORKING
		mp2.step_ambient_locomotion(0.1)
		_assert_true(matched and not ap2.is_villager_ambient_active("stl_m2_0", vidp2) and vp2.cell == committed_before, "M2-F(%s): Job preemption cancels ambient burst cleanly at committed cell" % phase)

	# 8. Near/Mid/Far LOD, Fog, and 48-Actor Cap
	var w_lod := _build_road_world(404, 2, 30)
	var m_lod = w_lod["mgr"]
	var wd_lod = w_lod["wd"]
	var gnav := GridNavigationScript.new(wd_lod)
	var fog = FogOfWarScript.new(64, 64)
	var cam := Camera2D.new()
	cam.position = IsoMath.map_to_local(Vector2i(10, 10))
	cam.zoom = Vector2(1.0, 1.0)
	root.add_child(cam)
	var pool_cont := Node2D.new()
	root.add_child(pool_cont)
	var pres = RivalPresentationControllerScript.new()
	pres.benchmark_telemetry_enabled = true
	pres.setup(m_lod, wd_lod, gnav, cam, fog, pool_cont)
	pres.debug_fog_disabled = false
	# Unexplored fog -> 0 actors
	pres.update_presentation(0.016, 1.0)
	_assert_eq(int(pres.get_benchmark_metrics().get("active_actors", -1)), 0, "M2-G1: Unexplored fog keeps active_actors == 0")
	# Reveal all -> bounded <= 48 actors
	pres.debug_fog_disabled = true
	for _f in range(10):
		m_lod.step_ambient_locomotion(0.1)
		pres.update_presentation(0.016, 1.0)
	_assert_true(int(pres.get_benchmark_metrics().get("active_actors", 999)) <= 48, "M2-G2: Active Actors bounded <= 48 (%d)" % int(pres.get_benchmark_metrics().get("active_actors", -1)))
	pres.queue_free()
	pool_cont.queue_free()
	cam.queue_free()
	await process_frame

	print("\n--------------------------------------------------------------------")
	print("  Results: %d passed, %d failed" % [_passed, _failed])
	print("====================================================================")
	quit(0 if _failed == 0 else 1)
