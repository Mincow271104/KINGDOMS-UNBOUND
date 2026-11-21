extends SceneTree

const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const SettlementDataScript = preload("res://scripts/world/settlement_data.gd")
const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementVillagerContextScript = preload("res://scripts/world/settlement_villager_context.gd")
const SettlementSimulationManagerScript = preload("res://scripts/world/settlement_simulation_manager.gd")
const RivalPresentationControllerScript = preload("res://scripts/world/rival_presentation_controller.gd")
const GridNavigationScript = preload("res://scripts/navigation/grid_navigation.gd")
const FogOfWarScript = preload("res://scripts/world/fog_of_war.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")

const WARMUP_FRAMES: int = 15
const SAMPLE_FRAMES: int = 60
const SIM_DT: float = 0.016

var _passed: int = 0
var _failed: int = 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] %s" % msg)
	else:
		_failed += 1
		printerr("  [FAIL] %s" % msg)

func _capture_snapshot(mgr: Node) -> Dictionary:
	var out := {}
	for sid in mgr.get_registered_settlement_ids():
		var ctx = mgr.get_context(sid)
		var v_list: Array = []
		for v in ctx.get_all_villagers():
			v_list.append({
				"id": String(v.villager_id),
				"cell": Vector2i(v.cell.x, v.cell.y),
				"role": String(v.role),
				"task_state": String(v.task_state),
				"workplace_id": String(v.workplace_id),
				"active_job_id": String(v.active_job_id),
			})
		out[sid] = {
			"settled_hour_seq": int(ctx.sim_state.settled_hour_seq),
			"gold": int(ctx.economy.get_gold()),
			"resources": ctx.economy.get_all_resources().duplicate(true),
			"villagers": v_list,
		}
	return out

func _run_parity_test() -> void:
	print("\n[M0 Integrity] Telemetry Disabled vs Enabled Snapshot Parity")
	var snaps: Array[Dictionary] = []
	for telemetry_on in [false, true]:
		var wd = WorldGeneratorScript.generate(12345, WorldGeneratorScript.LATEST_GENERATOR_VERSION, 128, 128)
		var mgr := SettlementSimulationManagerScript.new()
		mgr.benchmark_telemetry_enabled = telemetry_on
		mgr.register_settlements_from_world_data(wd)
		mgr.seed_initial_populations()
		var gnav := GridNavigationScript.new(wd)
		var cam := Camera2D.new()
		var fog := FogOfWarScript.new(128, 128)
		var pool_cont := Node2D.new()
		var pres := RivalPresentationControllerScript.new()
		pres.benchmark_telemetry_enabled = telemetry_on
		pres.debug_fog_disabled = true
		pres.setup(mgr, wd, gnav, cam, fog, pool_cont)
		cam.global_position = IsoMath.map_to_local(wd.settlements[0].anchor_cell)

		for h in range(1, 5):
			mgr.advance_to_hour_seq(h)
			mgr.process_all_pending()
		for _f in range(10):
			pres.update_presentation(SIM_DT, 1.0)

		snaps.append(_capture_snapshot(mgr))
		pool_cont.free()
		cam.free()
		pres.free()
		mgr.free()

	_assert(snaps[0] == snaps[1], "M0-1: Canonical state snapshots (villagers, cells, roles, jobs, economy, sim_state) are 100% identical with telemetry OFF vs ON")

func _run_m03_cache_and_intent_tests() -> void:
	print("\n[M0.3 Integrity] Villager List Cache & Intent Cache Invalidation Tests")
	var ctx := SettlementVillagerContextScript.new("stl_m03", "neutral_tribe", "neutral_tribe")
	var v1 = ctx.create_and_add_villager("v1", SettlementVillagerDataScript.ROLE_IDLE, Vector2i(10, 10))
	var v2 = ctx.create_and_add_villager("v2", SettlementVillagerDataScript.ROLE_IDLE, Vector2i(11, 10))
	ctx.reset_villager_cache_telemetry()

	var list1 := ctx.get_all_villagers()
	var list2 := ctx.get_all_villagers()
	var tel1 := ctx.get_villager_cache_telemetry()
	_assert(list1.size() == 2 and list1[0].villager_id == v1.villager_id and list1[1].villager_id == v2.villager_id, "M0.3-A1: Deterministic villager ordering preserved")
	_assert(int(tel1["rebuilds"]) == 1 and int(tel1["hits"]) == 1 and int(tel1["id_parses"]) == 2, "M0.3-A2: Repeated read hits cache without rebuild or re-parse")

	# Mutating returned defensive Array must NOT corrupt internal cache
	list1.clear()
	_assert(ctx.get_all_villagers().size() == 2, "M0.3-A3: Mutating returned get_all_villagers() snapshot cannot corrupt internal cache")

	# Non-membership mutations (cell, task_state, hunger) do NOT invalidate cache
	v1.cell = Vector2i(12, 12)
	v1.task_state = SettlementVillagerDataScript.TASK_WORKING
	v1.hunger = 55.0
	var tel_before_add: int = int(ctx.get_villager_cache_telemetry()["rebuilds"])
	var _view := ctx.get_all_villagers_cached_view()
	_assert(int(ctx.get_villager_cache_telemetry()["rebuilds"]) == tel_before_add, "M0.3-A4: Cell/task/needs changes do not invalidate membership cache")

	# Failed add/remove does not invalidate cache; successful add/remove DOES
	var bad_add := ctx.add_villager(null)
	var bad_rem := ctx.remove_villager("nonexistent_id")
	_assert(not bad_add and not bad_rem and not bool(ctx.get_villager_cache_telemetry()["dirty"]), "M0.3-A5: Failed add/remove does not corrupt cache")
	var v3 = ctx.create_and_add_villager("v3", SettlementVillagerDataScript.ROLE_IDLE, Vector2i(12, 10))
	_assert(ctx.get_all_villagers().size() == 3 and v3 != null, "M0.3-A6: Successful add invalidates cache and includes new villager")
	ctx.remove_villager(v2.villager_id)
	_assert(ctx.get_all_villagers().size() == 2, "M0.3-A7: Successful remove invalidates cache")

	# Intent cache hit & invalidation tests
	var wd = WorldGeneratorScript.generate(12345, WorldGeneratorScript.LATEST_GENERATOR_VERSION, 128, 128)
	var mgr := SettlementSimulationManagerScript.new()
	mgr.register_settlements_from_world_data(wd)
	mgr.seed_initial_populations()
	var stl = wd.settlements[2] # neutral_tribe/full
	var sctx = mgr.get_context(stl.settlement_id)
	var gnav := GridNavigationScript.new(wd)
	var nctx: RefCounted = SettlementPresentationAnchorHelper_new_nav(stl, wd, gnav)
	nctx.benchmark_telemetry_enabled = true
	var sv = sctx.get_all_villagers()[0]
	nctx.sync_intent(sctx, sv)
	nctx.sync_intent(sctx, sv)
	nctx.sync_intent(sctx, sv)
	_assert(nctx.bench_resolve_intent_calls == 1 and nctx.bench_intent_cache_hits == 2, "M0.3-B1: Unchanged villager hits intent cache without re-calling resolve_intent()")

	sv.cell = sv.cell + Vector2i(1, 0)
	nctx.sync_intent(sctx, sv)
	_assert(nctx.bench_resolve_intent_calls == 2 and nctx.bench_intent_invalidations >= 1, "M0.3-B2: Cell change invalidates intent cache")
	mgr.free()

func SettlementPresentationAnchorHelper_new_nav(stl, wd, gnav):
	var NavScript = preload("res://scripts/world/settlement_navigation_context.gd")
	return NavScript.new(stl.settlement_id, wd, gnav, stl)

func _build_synthetic_fixture(total_pop: int, idle_only: bool, stl_count: int) -> Dictionary:
	var wd = WorldGeneratorScript.generate(12345, WorldGeneratorScript.LATEST_GENERATOR_VERSION, 128, 128)
	# Expand synthetic settlements deterministically if stl_count > generated count
	while wd.settlements.size() < stl_count:
		var idx: int = wd.settlements.size()
		var ax: int = 20 + ((idx * 18) % 88)
		var ay: int = 20 + ((idx / 5) * 18) % 88
		var stl := SettlementDataScript.new(
			"stl_bench_%d" % idx,
			"neutral_tribe",
			"neutral_tribe",
			SettlementDataScript.ROLE_VILLAGE,
			Vector2i(ax, ay)
		)
		stl.buildings.append({
			"id": "bench_hq_%d" % idx,
			"type": "townhall",
			"cell": Vector2i(ax, ay),
			"size": Vector2i(2, 2),
			"role": "hq",
			"blocking": true,
		})
		for rx in range(-2, 4):
			stl.roads.append(Vector2i(ax + rx, ay + 2))
		wd.settlements.append(stl)

	var mgr := SettlementSimulationManagerScript.new()
	mgr.benchmark_telemetry_enabled = true
	mgr.register_settlements_from_world_data(wd)

	var roles: Array = [SettlementVillagerDataScript.ROLE_IDLE] if idle_only else [
		SettlementVillagerDataScript.ROLE_FARMER,
		SettlementVillagerDataScript.ROLE_WOODCUTTER,
		SettlementVillagerDataScript.ROLE_HAULER,
		SettlementVillagerDataScript.ROLE_GUARD,
		SettlementVillagerDataScript.ROLE_IDLE,
	]
	var sids: Array[String] = mgr.get_registered_settlement_ids()
	for i in range(total_pop):
		var sid: String = sids[i % mini(stl_count, sids.size())]
		var ctx = mgr.get_context(sid)
		var r: String = roles[i % roles.size()]
		var spawn_c: Vector2i = wd.settlements[i % mini(stl_count, wd.settlements.size())].anchor_cell + Vector2i(0, 2)
		var v = ctx.create_and_add_villager("bench_%d" % i, r, spawn_c)
		if not idle_only and r != SettlementVillagerDataScript.ROLE_IDLE:
			v.task_state = SettlementVillagerDataScript.TASK_WORKING

	var gnav := GridNavigationScript.new(wd)
	var cam := Camera2D.new()
	var fog := FogOfWarScript.new(128, 128)
	var pool_cont := Node2D.new()
	root.add_child(pool_cont)
	var pres := RivalPresentationControllerScript.new()
	pres.benchmark_telemetry_enabled = true
	pres.debug_fog_disabled = true
	pres.setup(mgr, wd, gnav, cam, fog, pool_cont)
	return {"wd": wd, "mgr": mgr, "cam": cam, "pool": pool_cont, "pres": pres}

func _run_bench_case(label: String, total_pop: int, idle_only: bool, stl_count: int, cam_zoom: float, macro_far: bool) -> void:
	var fx := _build_synthetic_fixture(total_pop, idle_only, stl_count)
	var wd = fx["wd"]
	var mgr: Node = fx["mgr"]
	var cam: Camera2D = fx["cam"]
	var pres: Node = fx["pres"]
	var pool_cont: Node2D = fx["pool"]

	cam.zoom = Vector2(cam_zoom, cam_zoom)
	if macro_far:
		cam.global_position = Vector2(-5000.0, -5000.0)
	else:
		cam.global_position = IsoMath.map_to_local(wd.settlements[0].anchor_cell)

	# Warmup
	for _w in range(WARMUP_FRAMES):
		pres.update_presentation(SIM_DT, 1.0)
	mgr.reset_benchmark_metrics()
	pres.reset_benchmark_metrics()

	var frame_times_ms: Array[float] = []
	frame_times_ms.resize(SAMPLE_FRAMES)
	for f in range(SAMPLE_FRAMES):
		var t0: int = Time.get_ticks_usec()
		if f % 15 == 0:
			mgr.advance_to_hour_seq((f / 15) + 1)
			mgr.process_batch()
		pres.update_presentation(SIM_DT, 1.0)
		frame_times_ms[f] = float(Time.get_ticks_usec() - t0) / 1000.0

	var sum_f: float = 0.0
	for ft in frame_times_ms:
		sum_f += ft
	frame_times_ms.sort()
	var avg_f: float = sum_f / float(SAMPLE_FRAMES)
	var p95_f: float = frame_times_ms[clampi(int(ceil(0.95 * float(SAMPLE_FRAMES))) - 1, 0, SAMPLE_FRAMES - 1)]
	var sim_m: Dictionary = mgr.get_benchmark_metrics()
	var pres_m: Dictionary = pres.get_benchmark_metrics()
	var ps_m: Dictionary = pres_m.get("path_scheduler", {})
	var mem_mb: float = float(Performance.get_monitor(Performance.MEMORY_STATIC)) / (1024.0 * 1024.0)
	var node_cnt: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))

	print("  [%s | pop=%d | stls=%d | zoom=%.1fx] frame=%.3fms (P95=%.3fms) | sim=%.3fms (maint=%.3fms) | pres=%.3fms (N=%d M=%d F=%d noAct=%d) | sync=%d res=%d adj=%d hits=%d | cReb=%d cHits=%d | maxQ=%d exp=%d | actors=%d" % [
		label, total_pop, stl_count, cam_zoom,
		avg_f, p95_f,
		float(sim_m.get("avg_sim_ms", 0.0)),
		float(sim_m.get("update_settled_ms", 0.0)),
		float(pres_m.get("avg_pres_ms", 0.0)),
		int(pres_m.get("near_count", 0)),
		int(pres_m.get("mid_count", 0)),
		int(pres_m.get("far_count", 0)),
		int(pres_m.get("near_without_actor", 0)),
		int(pres_m.get("sync_intent_calls", 0)),
		int(pres_m.get("resolve_intent_calls", 0)),
		int(pres_m.get("find_adjacent_calls", 0)),
		int(pres_m.get("intent_cache_hits", 0)),
		int(sim_m.get("cache_rebuilds", 0)),
		int(sim_m.get("cache_hits", 0)),
		int(ps_m.get("max_queue_depth", 0)),
		int(ps_m.get("total_expansions", 0)),
		int(pres_m.get("active_actors", 0)),
	])

	root.remove_child(pool_cont)
	pool_cont.free()
	cam.free()
	pres.free()
	mgr.free()

func _init() -> void:
	print("====================================================================")
	print("  M0 BENCHMARK HARNESS: Rival Ambient Baseline (No Ambient Wandering)")
	print("  Godot=%s | Resolution=Headless | Warmup=%df | Sample=%df" % [
		Engine.get_version_info().get("string", "4.7"), WARMUP_FRAMES, SAMPLE_FRAMES
	])
	print("====================================================================")
	call_deferred("_run_all")

func _run_pure_pres_and_sim_windows() -> void:
	print("\n[M0.3 Separated Windows] Pure Presentation (300f, 0 sim) & Sim Batch (10 batches)")
	for pop in [100, 200, 300, 500, 1000]:
		var fx := _build_synthetic_fixture(pop, true, 3)
		var wd = fx["wd"]
		var mgr: Node = fx["mgr"]
		var cam: Camera2D = fx["cam"]
		var pres: Node = fx["pres"]
		var pool_cont: Node2D = fx["pool"]
		cam.global_position = IsoMath.map_to_local(wd.settlements[0].anchor_cell)
		for _w in range(15):
			pres.update_presentation(SIM_DT, 1.0)
		pres.reset_benchmark_metrics()
		var p_times: Array[float] = []
		p_times.resize(300)
		for f in range(300):
			var t0: int = Time.get_ticks_usec()
			pres.update_presentation(SIM_DT, 1.0)
			p_times[f] = float(Time.get_ticks_usec() - t0) / 1000.0
		p_times.sort()
		var pm: Dictionary = pres.get_benchmark_metrics()
		mgr.reset_benchmark_metrics()
		for b in range(10):
			mgr.advance_to_hour_seq(b + 1)
			mgr.process_batch()
		var sm: Dictionary = mgr.get_benchmark_metrics()
		print("  [pop=%d] PurePres(300f): avg=%.3fms p50=%.3fms p95=%.3fms p99=%.3fms max=%.3fms (sync=%d res=%d hits=%d) | Sim(10 calls): avg=%.3fms/call p95=%.3fms maint=%.3fms" % [
			pop,
			float(pm.get("avg_pres_ms", 0.0)),
			p_times[150],
			p_times[284],
			p_times[296],
			p_times[299],
			int(pm.get("sync_intent_calls", 0)),
			int(pm.get("resolve_intent_calls", 0)),
			int(pm.get("intent_cache_hits", 0)),
			float(sm.get("avg_sim_ms", 0.0)),
			float(sm.get("p95_sim_ms", 0.0)),
			float(sm.get("update_settled_ms", 0.0)),
		])
		root.remove_child(pool_cont)
		pool_cont.free()
		cam.free()
		pres.free()
		mgr.free()

func _run_all() -> void:
	_run_parity_test()
	_run_m03_cache_and_intent_tests()
	_run_pure_pres_and_sim_windows()

	print("\n[M0 Baseline Matrix] Synthetic Multi-Settlement Fixtures")
	for pop in [50, 100, 200, 300, 500, 1000]:
		_run_bench_case("Idle", pop, true, 3, 1.0, false)
	for pop in [50, 100, 200, 300, 500, 1000]:
		_run_bench_case("Mixed+Nav", pop, false, 6, 1.0, false)
	for z in [1.0, 2.0, 3.0]:
		_run_bench_case("Zoom", 200, false, 3, z, false)
	_run_bench_case("MacroFar", 1000, false, 10, 1.0, true)

	print("\n--------------------------------------------------------------------")
	print("  Parity Assertions: %d passed, %d failed" % [_passed, _failed])
	print("====================================================================")
	quit(0 if _failed == 0 else 1)
