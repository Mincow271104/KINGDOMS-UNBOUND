extends SceneTree

const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const SettlementGeneratorScript = preload("res://scripts/world/settlement_generator.gd")
const SettlementDataScript = preload("res://scripts/world/settlement_data.gd")
const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementSimulationManagerScript = preload("res://scripts/world/settlement_simulation_manager.gd")
const SettlementAmbientLocomotionScript = preload("res://scripts/world/settlement_ambient_locomotion.gd")
const RivalPresentationControllerScript = preload("res://scripts/world/rival_presentation_controller.gd")
const GridNavigationScript = preload("res://scripts/navigation/grid_navigation.gd")
const FogOfWarScript = preload("res://scripts/world/fog_of_war.gd")

var _passed: int = 0
var _failed: int = 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] %s" % msg)
	else:
		_failed += 1
		printerr("  [FAIL] %s" % msg)

func _make_env(cam_pos: Vector2, zoom_val: float) -> Dictionary:
	var wd = WorldGeneratorScript.generate(12345, WorldGeneratorScript.LATEST_GENERATOR_VERSION, 128, 128)
	var mgr := SettlementSimulationManagerScript.new()
	mgr.benchmark_telemetry_enabled = true
	mgr.register_settlements_from_world_data(wd)
	mgr.seed_initial_populations()
	var gnav := GridNavigationScript.new(wd)
	var cam := Camera2D.new()
	cam.global_position = cam_pos
	cam.zoom = Vector2(zoom_val, zoom_val)
	var fog := FogOfWarScript.new(128, 128)
	var pool_cont := Node2D.new()
	var pres := RivalPresentationControllerScript.new()
	pres.benchmark_telemetry_enabled = true
	pres.debug_fog_disabled = true
	pres.setup(mgr, wd, gnav, cam, fog, pool_cont)
	return {"wd": wd, "mgr": mgr, "cam": cam, "fog": fog, "pool": pool_cont, "pres": pres}

func _free_env(env: Dictionary) -> void:
	env["pool"].free()
	env["cam"].free()
	env["pres"].free()
	env["mgr"].free()

func _collect_idle_cells(mgr: Node) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for sid in mgr.get_registered_settlement_ids():
		var ctx = mgr.get_context(sid)
		for v in ctx.get_all_villagers():
			if v.role == SettlementVillagerDataScript.ROLE_IDLE:
				out.append(Vector2i(v.cell.x, v.cell.y))
	return out

func _run_tests() -> void:
	print("\n[Categories A-E] LOD, Zoom, Actor Pool, FPS, Pause & Speed Invariance")
	var base_wd = WorldGeneratorScript.generate(12345, WorldGeneratorScript.LATEST_GENERATOR_VERSION, 128, 128)
	var near_cam_pos: Vector2 = IsoMath.map_to_local(base_wd.settlements[2].anchor_cell)
	var far_cam_pos := Vector2(-5000.0, -5000.0)

	# A & B: Near (1x) vs Zoom (3x) vs Far
	var e_near := _make_env(near_cam_pos, 1.0)
	var e_zoom := _make_env(near_cam_pos, 3.0)
	var e_far := _make_env(far_cam_pos, 1.0)
	var initial_cells := _collect_idle_cells(e_near["mgr"])

	for _step in range(200):
		for e in [e_near, e_zoom, e_far]:
			e["mgr"].step_ambient_locomotion(0.05)
			e["pres"].update_presentation(0.05, 1.0)

	var c_near := _collect_idle_cells(e_near["mgr"])
	var c_zoom := _collect_idle_cells(e_zoom["mgr"])
	var c_far := _collect_idle_cells(e_far["mgr"])
	_assert(c_near != initial_cells, "A0: Idle villagers actually wandered to new road cells over 10s sim time")
	_assert(c_near == c_far, "A: Near and Far LOD produce identical canonical villager.cell sequence")
	_assert(c_near == c_zoom, "B: 1x and 3x camera zoom produce identical canonical villager.cell sequence")

	# C: Actor pool release/reacquire invariance
	var e_pool := _make_env(near_cam_pos, 1.0)
	for s in range(200):
		e_pool["mgr"].step_ambient_locomotion(0.05)
		e_pool["pres"].update_presentation(0.05, 1.0)
		if s % 10 == 0:
			e_pool["pres"].get_actor_pool().release_all()
	_assert(_collect_idle_cells(e_pool["mgr"]) == c_near, "C: Actor pool release/reacquire does not alter canonical position")

	# D: Frame rate invariance (0.05s x 200 == 0.1s x 100)
	var e_fps := _make_env(far_cam_pos, 1.0)
	for _s in range(100):
		e_fps["mgr"].step_ambient_locomotion(0.1)
	_assert(_collect_idle_cells(e_fps["mgr"]) == c_near, "D: Different delta step sizes (0.05s vs 0.1s) with equal sim time produce identical canonical positions")

	# M: Zero A* requests for ambient movement
	var ps_m: Dictionary = e_near["pres"].get_benchmark_metrics().get("path_scheduler", {})
	var amb_m: Dictionary = e_near["mgr"].get_benchmark_metrics().get("ambient_locomotion", {})
	_assert(int(amb_m.get("ambient_astar_requests", -1)) == 0 and int(ps_m.get("total_expansions", 0)) == 0, "M: Ordinary Idle road wandering emits zero A* requests (exp=%d)" % int(ps_m.get("total_expansions", 0)))

	# E: Pause & Speed
	var before_pause := _collect_idle_cells(e_near["mgr"])
	e_near["mgr"].step_ambient_locomotion(0.0)
	_assert(_collect_idle_cells(e_near["mgr"]) == before_pause, "E1: Pause (0.0 sim_dt) freezes canonical ambient movement")

	_free_env(e_near)
	_free_env(e_zoom)
	_free_env(e_far)
	_free_env(e_pool)
	_free_env(e_fps)

	print("\n[Categories F-N] Road Safety, Eligibility, Preemption, Fog, Fairness & Save Semantics")
	# F: All 6 layouts have valid road graphs and zero building overlap
	var all_6_valid := true
	for p in ["neutral_tribe", "rival_military", "rival_merchant"]:
		for t in ["full", "compact"]:
			var tmpl: Dictionary = SettlementGeneratorScript._build_layout_template(p, Vector2i(20, 20), t)
			var stl_t := SettlementDataScript.new("stl_%s_%s" % [p, t], p, p, SettlementDataScript.ROLE_CAPITAL, Vector2i(20, 20))
			stl_t.layout_tier = t
			for b in tmpl.get("buildings", []):
				stl_t.buildings.append(b)
			for r in tmpl.get("roads", []):
				stl_t.roads.append(r)
			var amb_check := SettlementAmbientLocomotionScript.new()
			var rg = amb_check.register_settlement_road_graph(stl_t, null)
			if not rg.valid:
				all_6_valid = false
	_assert(all_6_valid, "F1: All 6 settlement layouts produce valid single-component road graphs")

	# F2: Disconnected road graph fails safely without wandering
	var bad_stl := SettlementDataScript.new("stl_bad", "neutral_tribe", "neutral_tribe", SettlementDataScript.ROLE_VILLAGE, Vector2i(10, 10))
	bad_stl.roads = [Vector2i(10, 10), Vector2i(15, 15)]
	var amb_bad := SettlementAmbientLocomotionScript.new()
	var bad_rg = amb_bad.register_settlement_road_graph(bad_stl, null)
	_assert(not bad_rg.valid and bad_rg.invalid_reason == "disconnected_road_graph", "F2: Disconnected road graph is rejected safely")

	# G & H & I & J: Isolated resident, eligibility, job preemption, and economy invariance
	var e2 := _make_env(near_cam_pos, 1.0)
	var mgr2: Node = e2["mgr"]
	var amb2: RefCounted = mgr2.get_ambient_locomotion()
	var s2_id := "stl_neutral_tribe_1"
	var ctx2 = mgr2.get_context(s2_id)
	var food_before: int = ctx2.economy.get_resource("food")
	var gold_before: int = ctx2.economy.get_gold()

	var iso_v = ctx2.create_and_add_villager("iso_idle", SettlementVillagerDataScript.ROLE_IDLE, Vector2i(2, 2))
	_assert(not amb2.is_villager_eligible(s2_id, iso_v), "G: Resident with no road/adjacent connector is ineligible and stays stationary")

	var idle_v = null
	for v in ctx2.get_all_villagers():
		if v.role == SettlementVillagerDataScript.ROLE_IDLE and v.villager_id != iso_v.villager_id:
			idle_v = v
			break
	for _k in range(80):
		mgr2.step_ambient_locomotion(0.05)
	_assert(amb2.is_villager_ambient_active(s2_id, idle_v.villager_id) and iso_v.cell == Vector2i(2, 2), "H: Eligible Idle villager activates ambient movement while isolated resident stays at (2,2)")

	# I: Job/Rest preemption cancels ambient state safely
	idle_v.task_state = SettlementVillagerDataScript.TASK_WORKING
	idle_v.active_job_id = "job_test_1"
	mgr2.step_ambient_locomotion(0.1)
	_assert(not amb2.is_villager_ambient_active(s2_id, idle_v.villager_id), "I: Assigning a job/working task cancels ambient movement immediately")
	_assert(ctx2.economy.get_resource("food") == food_before and ctx2.economy.get_gold() == gold_before, "J: Ambient wandering leaves SettlementEconomy unchanged")

	# K: Fog safety — Actor is not rendered when target cell is unexplored
	e2["pres"].debug_fog_disabled = false
	e2["fog"].reset_fog()
	e2["pres"].update_presentation(0.016, 1.0)
	_assert(e2["pres"].get_actor_pool().get_active_count() == 0, "K: Unexplored fog releases/hides all ambient Actors")

	# L: Scheduler fairness across multiple settlements
	var e_fair := _make_env(far_cam_pos, 1.0)
	for _f in range(120):
		e_fair["mgr"].step_ambient_locomotion(0.1)
	var sc_dict: Dictionary = e_fair["mgr"].get_benchmark_metrics().get("ambient_locomotion", {}).get("service_counts_by_sid", {})
	_assert(sc_dict.size() >= 2, "L: Multiple settlements receive ambient scheduler service (%d settlements serviced)" % sc_dict.size())

	# N: Transient reset semantics (reconstructing ambient locomotion starts cleanly at committed v.cell)
	var committed := Vector2i(idle_v.cell.x, idle_v.cell.y)
	var fresh_amb := SettlementAmbientLocomotionScript.new()
	fresh_amb.configure_from_world_data(e2["wd"])
	var interp: Dictionary = fresh_amb.get_visual_interpolation(s2_id, idle_v.villager_id, idle_v.cell)
	_assert(not bool(interp["active"]) and interp["step_from"] == committed, "N: Transient reset starts cleanly at committed villager.cell")

	_free_env(e2)
	_free_env(e_fair)

	# O: Preemption at Beginning, Midpoint, and Just Before Completion of an active step
	print("\n[Categories O-Q] Step-Phase Preemption, Synchronized Saturation FPS-Invariance & 1000-Resident Stress")
	for phase_name in ["beginning", "midpoint", "pre_completion"]:
		var ep := _make_env(near_cam_pos, 1.0)
		var mp: Node = ep["mgr"]
		var ap: RefCounted = mp.get_ambient_locomotion()
		var cp = mp.get_context("stl_neutral_tribe_1")
		var pv = null
		for vv in cp.get_all_villagers():
			if vv.role == SettlementVillagerDataScript.ROLE_IDLE:
				pv = vv
				break
		var safety: int = 0
		while safety < 100:
			mp.step_ambient_locomotion(0.1)
			var itp: Dictionary = ap.get_visual_interpolation("stl_neutral_tribe_1", pv.villager_id, pv.cell)
			if bool(itp["active"]) and bool(itp["is_moving"]):
				break
			safety += 1
		if phase_name == "midpoint":
			mp.step_ambient_locomotion(0.5)
		elif phase_name == "pre_completion":
			mp.step_ambient_locomotion(0.9)
		var cell_at_cancel := Vector2i(pv.cell.x, pv.cell.y)
		pv.task_state = SettlementVillagerDataScript.TASK_WORKING
		pv.active_job_id = "job_preempt"
		mp.step_ambient_locomotion(0.1)
		_assert(not ap.is_villager_ambient_active("stl_neutral_tribe_1", pv.villager_id) and pv.cell == cell_at_cancel, "O(%s): Preemption cancels step cleanly without corrupting committed cell" % phase_name)
		_free_env(ep)

	# P: FPS-Invariance under Synchronized Saturation (30, 60, 120, 144 FPS, irregular, catch-up) at 50..1000
	for pop_sz in [50, 200, 500, 1000]:
		var fps_patterns := {
			"30fps": _make_uniform_deltas(1.0 / 30.0, 10.0),
			"60fps": _make_uniform_deltas(1.0 / 60.0, 10.0),
			"120fps": _make_uniform_deltas(1.0 / 120.0, 10.0),
			"144fps": _make_uniform_deltas(1.0 / 144.0, 10.0),
			"irregular": _make_irregular_deltas(10.0),
			"catchup": [1.0, 2.0, 0.5, 1.5, 2.5, 2.5],
		}
		var ref_cells: Array[Vector2i] = []
		var all_fps_match := true
		var stats_line := ""
		for pat_name in fps_patterns.keys():
			var ef := _make_1000_road_fixture(pop_sz)
			var mf: Node = ef["mgr"]
			var af: RefCounted = mf.get_ambient_locomotion()
			mf.step_ambient_locomotion(0.1)
			for st_obj in af._states_by_key.values():
				st_obj.dwell_end_time = 0.5
			for dt in fps_patterns[pat_name]:
				mf.step_ambient_locomotion(dt)
			var cur_cells := _collect_idle_cells(mf)
			if ref_cells.is_empty():
				ref_cells = cur_cells
				var am: Dictionary = af.get_benchmark_metrics()
				stats_line = "events=%d commits=%d checks=%d astar=%d" % [
					int(am["events_processed"]), int(am["cell_commits"]), int(am["candidate_checks"]), int(am["ambient_astar_requests"])
				]
			elif cur_cells != ref_cells:
				all_fps_match = false
			_free_env(ef)
		_assert(all_fps_match, "P(pop=%d): 30/60/120/144 FPS, irregular & catch-up produce IDENTICAL cells under synchronized saturation (%s)" % [pop_sz, stats_line])

func _make_uniform_deltas(dt: float, total: float) -> Array[float]:
	var arr: Array[float] = []
	var steps: int = int(round(total / dt))
	for _i in range(steps):
		arr.append(dt)
	return arr

func _make_irregular_deltas(total: float) -> Array[float]:
	var pattern: Array[float] = [0.011, 0.047, 0.008, 0.093, 0.021, 0.12]
	var arr: Array[float] = []
	var acc: float = 0.0
	var idx: int = 0
	while acc < total:
		var d: float = minf(pattern[idx % pattern.size()], total - acc)
		arr.append(d)
		acc += d
		idx += 1
	return arr

func _make_1000_road_fixture(total_pop: int) -> Dictionary:
	var wd = WorldGeneratorScript.generate(12345, WorldGeneratorScript.LATEST_GENERATOR_VERSION, 128, 128)
	for k in range(10):
		var ax: int = 16 + (k % 5) * 20
		var ay: int = 16 + (k / 5) * 40
		for dx in range(-2, 6):
			for dy in range(-2, 4):
				wd.terrain[ax + dx][ay + dy] = 1
				wd.occupancy[ax + dx][ay + dy] = false
		var stl := SettlementDataScript.new("stl_stress_%d" % k, "neutral_tribe", "neutral_tribe", SettlementDataScript.ROLE_VILLAGE, Vector2i(ax, ay))
		for rx in range(0, 6):
			stl.roads.append(Vector2i(ax + rx, ay))
		wd.settlements.append(stl)
	var mgr := SettlementSimulationManagerScript.new()
	mgr.benchmark_telemetry_enabled = true
	mgr.register_settlements_from_world_data(wd)
	var stress_sids: Array[String] = []
	for k in range(10):
		stress_sids.append("stl_stress_%d" % k)
	for i in range(total_pop):
		var sid: String = stress_sids[i % 10]
		var ctx = mgr.get_context(sid)
		var k_idx: int = i % 10
		var ax: int = 16 + (k_idx % 5) * 20
		var ay: int = 16 + (k_idx / 5) * 40
		ctx.create_and_add_villager("s_%d" % i, SettlementVillagerDataScript.ROLE_IDLE, Vector2i(ax + (i % 6), ay))
	var gnav := GridNavigationScript.new(wd)
	var cam := Camera2D.new()
	cam.global_position = Vector2(-5000.0, -5000.0)
	var fog := FogOfWarScript.new(128, 128)
	var pool_cont := Node2D.new()
	var pres := RivalPresentationControllerScript.new()
	pres.benchmark_telemetry_enabled = true
	pres.debug_fog_disabled = true
	pres.setup(mgr, wd, gnav, cam, fog, pool_cont)
	return {"wd": wd, "mgr": mgr, "cam": cam, "fog": fog, "pool": pool_cont, "pres": pres}

func _init() -> void:
	print("====================================================================")
	print("  TEST SUITE: M1 Canonical Road-Graph Idle Wandering")
	print("====================================================================")
	_run_tests()
	print("\n--------------------------------------------------------------------")
	print("  Results: %d passed, %d failed" % [_passed, _failed])
	print("====================================================================")
	quit(0 if _failed == 0 else 1)
