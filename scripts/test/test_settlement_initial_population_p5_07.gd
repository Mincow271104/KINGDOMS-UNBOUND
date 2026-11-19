extends SceneTree
## P5-07 Automated Test Suite: Initial Settlement Population Seeding
## Covers Categories A–J (Counts, Role Composition, Housing, Jobs, Spawn Cells,
## Economy, Determinism, Idempotency, Simulation Timing, and Phase 6 Discovery).

const SettlementDataScript = preload("res://scripts/world/settlement_data.gd")
const SettlementGeneratorScript = preload("res://scripts/world/settlement_generator.gd")
const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementVillagerContextScript = preload("res://scripts/world/settlement_villager_context.gd")
const SettlementSimulationStateScript = preload("res://scripts/world/settlement_simulation_state.gd")
const SettlementSimulationManagerScript = preload("res://scripts/world/settlement_simulation_manager.gd")
const SettlementPopulationSeederScript = preload("res://scripts/world/settlement_population_seeder.gd")
const SettlementImmigrationPolicyScript = preload("res://scripts/world/settlement_immigration_policy.gd")
const SettlementResourceSourceAdapterScript = preload("res://scripts/world/settlement_resource_source_adapter.gd")
const RivalPresentationControllerScript = preload("res://scripts/world/rival_presentation_controller.gd")
const GridNavigationScript = preload("res://scripts/navigation/grid_navigation.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const TimeManagerScript = preload("res://scripts/core/time_manager.gd")
const WorldViewScene = preload("res://scenes/world/world_view.tscn")

var _passed: int = 0
var _failed: int = 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] %s" % msg)
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)

func _make_flat_world(w: int = 96, h: int = 96) -> WorldGeneratorScript.WorldData:
	IsoMath.set_active_map_dimensions(w, h)
	var wd := WorldGeneratorScript.WorldData.new()
	wd.map_width = w
	wd.map_height = h
	wd.seed_value = 12345
	wd.terrain = []
	wd.occupancy = []
	wd.owned_cells = []
	for x in range(w):
		var tc: Array[int] = []
		var oc: Array[bool] = []
		var ownc: Array[bool] = []
		for y in range(h):
			tc.append(WorldGeneratorScript.TerrainType.GRASS)
			oc.append(false)
			ownc.append(false)
		wd.terrain.append(tc)
		wd.occupancy.append(oc)
		wd.owned_cells.append(ownc)
	return wd

func _build_profile_fixture(faction_id: String, tier: String, anchor: Vector2i, wd: WorldGeneratorScript.WorldData) -> Dictionary:
	var sid := "stl_%s_%s" % [faction_id, tier]
	var layout: Dictionary = SettlementGeneratorScript._build_layout_template(faction_id, anchor, tier)
	var stl := SettlementDataScript.new(sid, faction_id, faction_id, SettlementDataScript.ROLE_VILLAGE, anchor)
	stl.layout_tier = tier
	for b in layout.get("buildings", []):
		stl.buildings.append((b as Dictionary).duplicate(true))
	for r in layout.get("roads", []):
		stl.roads.append(r)
	if wd != null:
		wd.settlements.append(stl)
		SettlementGeneratorScript.apply_settlement_reservations_and_occupancy(wd, [stl], true, true)
	var ctx := SettlementVillagerContextScript.new(sid, faction_id, faction_id, 1, true)
	ctx.set_meta("enable_hunter", true)
	ctx.reconcile_buildings(stl)
	SettlementResourceSourceAdapterScript.register_all_hunter_sources([ctx], wd)
	return {"stl": stl, "ctx": ctx}

func _count_roles(ctx: RefCounted) -> Dictionary:
	var counts: Dictionary = {}
	for v in ctx.get_all_villagers():
		var r := String(v.role)
		counts[r] = int(counts.get(r, 0)) + 1
	return counts

func _run_categories_a_to_e() -> void:
	print("\n[Categories A-E] Population Counts, Roles, Housing, Jobs & Spawn Cells")
	var seeder := SettlementPopulationSeederScript.new()
	var wd := _make_flat_world(96, 96)

	var expected := [
		{"fid": "neutral_tribe", "tier": "full", "anchor": Vector2i(15, 15), "pop": 7, "roles": {"hunter": 1, "farmer": 2, "woodcutter": 2, "hauler": 1, "idle": 1}},
		{"fid": "neutral_tribe", "tier": "compact", "anchor": Vector2i(35, 15), "pop": 3, "roles": {"hunter": 1, "woodcutter": 1, "hauler": 1}},
		{"fid": "rival_military", "tier": "full", "anchor": Vector2i(55, 15), "pop": 8, "roles": {"guard": 2, "hauler": 2, "idle": 4}},
		{"fid": "rival_military", "tier": "compact", "anchor": Vector2i(75, 15), "pop": 4, "roles": {"guard": 2, "idle": 2}},
		{"fid": "rival_merchant", "tier": "full", "anchor": Vector2i(15, 45), "pop": 7, "roles": {"hauler": 4, "idle": 3}},
		{"fid": "rival_merchant", "tier": "compact", "anchor": Vector2i(35, 45), "pop": 3, "roles": {"hauler": 2, "idle": 1}}
	]

	for case in expected:
		var fix := _build_profile_fixture(case["fid"], case["tier"], case["anchor"], wd)
		var ctx: RefCounted = fix["ctx"]
		var stl: RefCounted = fix["stl"]
		var res: Dictionary = seeder.seed_settlement(ctx, 12345, stl, wd)
		var label := "%s/%s" % [case["fid"], case["tier"]]

		_assert(bool(res["ok"]) and int(res["seeded"]) == int(case["pop"]) and ctx.get_villager_count() == int(case["pop"]), "A(%s): Seeded exact target %d (got %d)" % [label, int(case["pop"]), ctx.get_villager_count()])
		_assert(ctx.get_villager_count() <= ctx.get_housing_capacity(), "C(%s): Population (%d) <= housing_capacity (%d)" % [label, ctx.get_villager_count(), ctx.get_housing_capacity()])

		var rc := _count_roles(ctx)
		var role_match: bool = true
		for rk in case["roles"].keys():
			if int(rc.get(rk, 0)) != int(case["roles"][rk]):
				role_match = false
		_assert(role_match, "B(%s): Exact role composition %s (got %s)" % [label, str(case["roles"]), str(rc)])

		var integ: Dictionary = ctx.verify_assignment_integrity()
		_assert(bool(integ.get("ok", false)), "D(%s): Phase 3 job assignment integrity valid" % label)

		# Verify housing assignments & distinct walkable spawn cells
		var home_counts: Dictionary = {}
		var spawn_set: Dictionary = {}
		var bld_cells: Dictionary = {}
		for bc in stl.get_building_cells():
			bld_cells[bc] = true
		var all_valid_spawns: bool = true
		for v in ctx.get_all_villagers():
			if not v.home_building_id.is_empty():
				home_counts[v.home_building_id] = int(home_counts.get(v.home_building_id, 0)) + 1
			if bld_cells.has(v.cell) or wd.occupancy[v.cell.x][v.cell.y]:
				all_valid_spawns = false
			spawn_set[v.cell] = true
		var house_ok: bool = true
		for h_id in home_counts.keys():
			if int(home_counts[h_id]) > 6:
				house_ok = false
		_assert(house_ok, "C2(%s): No house exceeds capacity 6 (%s)" % [label, str(home_counts)])
		_assert(all_valid_spawns and spawn_set.size() == ctx.get_villager_count(), "E(%s): All %d spawn cells valid, walkable, non-building, and distinct" % [label, ctx.get_villager_count()])

func _run_categories_f_to_i() -> void:
	print("\n[Categories F-I] Economy, Determinism, Idempotency & Simulation Timing")
	var seeder := SettlementPopulationSeederScript.new()
	var wd1 := _make_flat_world(96, 96)
	var wd2 := _make_flat_world(96, 96)
	var f1 := _build_profile_fixture("neutral_tribe", "full", Vector2i(20, 20), wd1)
	var f2 := _build_profile_fixture("neutral_tribe", "full", Vector2i(20, 20), wd2)
	var ctx1: RefCounted = f1["ctx"]
	var ctx2: RefCounted = f2["ctx"]

	# F: Economy untouched & raw_meat cannot satisfy food reserve
	var food_before: int = int(ctx1.economy.get_resource(EconomyConfigScript.RES_FOOD))
	seeder.seed_settlement(ctx1, 77777, f1["stl"], wd1)
	_assert(int(ctx1.economy.get_resource(EconomyConfigScript.RES_FOOD)) == food_before, "F1: Seeding creates/deletes 0 food (60 preserved)")

	var f_low := _build_profile_fixture("neutral_tribe", "full", Vector2i(50, 50), wd1)
	var ctx_low: RefCounted = f_low["ctx"]
	ctx_low.economy.debit_resource(EconomyConfigScript.RES_FOOD, 55, "test_drain", "test_setup", 0) # leaves 5 food (<10)
	ctx_low.economy.credit_resource(EconomyConfigScript.RES_RAW_MEAT, 200, "test_meat", "test_setup", 0)
	var res_low: Dictionary = seeder.seed_settlement(ctx_low, 77777, f_low["stl"], wd1)
	_assert(int(res_low["seeded"]) == 0 and String(res_low["reason"]) == "insufficient_food_reserve", "F2: Low food (5) with 200 raw_meat fails safely without seeding")

	# G: Determinism
	randomize()
	for _i in range(15):
		var _d := randi()
	seeder.seed_settlement(ctx2, 77777, f2["stl"], wd2)
	var same_det: bool = (ctx1.get_villager_count() == ctx2.get_villager_count())
	if same_det:
		var v1_arr: Array = ctx1.get_all_villagers()
		var v2_arr: Array = ctx2.get_all_villagers()
		for i in range(v1_arr.size()):
			if v1_arr[i].villager_id != v2_arr[i].villager_id or v1_arr[i].role != v2_arr[i].role or v1_arr[i].cell != v2_arr[i].cell or v1_arr[i].home_building_id != v2_arr[i].home_building_id:
				same_det = false
	_assert(same_det, "G1: Identical seed & settlement produce identical IDs, roles, homes & spawn cells despite global RNG")

	# H: Idempotency & serialization round-trip
	var res_rep: Dictionary = seeder.seed_settlement(ctx1, 77777, f1["stl"], wd1)
	_assert(bool(res_rep["ok"]) and int(res_rep["seeded"]) == 0 and ctx1.get_villager_count() == 7, "H1: Repeat seeding does not duplicate residents")

	var st_dict: Dictionary = ctx1.sim_state.to_dict()
	var st_restored = SettlementSimulationStateScript.from_dict(st_dict)
	_assert(st_restored != null and st_restored.initial_population_seeded and st_restored.initial_seed_hour_seq == 0, "H2: SimulationState round-trip preserves initial_population_seeded & initial_seed_hour_seq")

	var legacy_dict: Dictionary = st_dict.duplicate(true)
	legacy_dict.erase("initial_population_seeded")
	legacy_dict.erase("initial_seed_hour_seq")
	var st_legacy = SettlementSimulationStateScript.from_dict(legacy_dict)
	_assert(st_legacy != null and not st_legacy.initial_population_seeded and st_legacy.initial_seed_hour_seq == -1, "H3: Legacy sim_state dict loads cleanly")

	# I: Simulation timing & Phase 5 daily immigration compatibility
	var mgr := SettlementSimulationManagerScript.new()
	var pol := SettlementImmigrationPolicyScript.new()
	pol.daily_admission_probability = 1.0
	mgr.set_immigration_policy(pol)
	var tm := TimeManagerScript.new()
	mgr.connect_time_manager(tm)
	mgr.register_context(ctx1)
	# Process 18 hours -> Day 1 midnight day_passed triggers Phase 5 immigration (7 -> 8)
	for _h in range(18):
		tm._advance_one_hour()
		mgr.process_all_pending()
	_assert(ctx1.get_villager_count() == 8, "I1: Phase 5 daily immigration still admits 1 newcomer (7 -> 8) after initial seeding")
	var all_v: Array = ctx1.get_all_villagers()
	_assert(all_v[0].admission_hour_seq == -1 and all_v[7].admission_hour_seq == 18, "I2: Founding residents have admission_hour_seq=-1; Day 1 immigrant has 18")
	mgr.disconnect_time_manager()
	mgr.free()
	tm.free()

func _run_category_j_worldview_and_phase6() -> void:
	print("\n[Category J] Fresh WorldView Integration, Save/Load Overlay Guard & Phase 6 Discovery")
	var wv := WorldViewScene.instantiate()
	get_root().add_child(wv)
	await process_frame

	var sim_mgr = wv.get("settlement_simulation_manager")
	var pres_ctrl = wv.get("rival_presentation_controller")
	var total_pop: int = 0
	var expected_total: int = 0
	for stl in wv.world_data.settlements:
		var sid: String = String(stl.settlement_id)
		var ctx = sim_mgr.get_context(sid)
		var spec := SettlementPopulationSeederScript.resolve_profile_spec(String(ctx.economy.economy_profile_id), String(stl.layout_tier))
		var exp_c: int = int(spec["target"])
		expected_total += exp_c
		total_pop += ctx.get_villager_count()
		_assert(ctx.sim_state.initial_population_seeded and ctx.get_villager_count() == exp_c, "J1(%s/%s): Fresh WorldView seeded %d/%d residents" % [sid, stl.layout_tier, ctx.get_villager_count(), exp_c])
	_assert(total_pop == expected_total, "J2: Fresh 128x128 WorldView seeds exact tier-matched total %d Rival residents (got %d)" % [expected_total, total_pop])
	var tribe_ctx = sim_mgr.get_context("stl_neutral_tribe_1")
	if tribe_ctx != null:
		var t_roles := _count_roles(tribe_ctx)
		_assert(int(t_roles.get("hunter", 0)) == 1 and int(t_roles.get("farmer", 0)) == 2 and int(t_roles.get("woodcutter", 0)) == 2 and int(t_roles.get("hauler", 0)) == 1 and int(t_roles.get("idle", 0)) == 1, "J2b: Live WorldView Neutral Tribe has exact approved roles %s" % str(t_roles))

	# Repeated apply_settlement_overlays_from_world_data (Save/Load path) never duplicates residents
	wv.apply_settlement_overlays_from_world_data()
	var after_overlay_pop: int = int(sim_mgr.get_telemetry()["registered_villagers"])
	_assert(after_overlay_pop == total_pop, "J3: apply_settlement_overlays_from_world_data() does not duplicate seeded residents")

	# Phase 6 presentation discovers and hydrates seeded residents cleanly
	var sid0: String = sim_mgr.get_registered_settlement_ids()[0]
	var ctx0 = sim_mgr.get_context(sid0)
	var first_v = ctx0.get_all_villagers()[0]
	wv.set("debug_fog_disabled", true)
	wv.camera.focus_on_cell(first_v.cell)
	wv.camera.force_update_scroll()
	await process_frame
	pres_ctrl.debug_fog_disabled = true
	pres_ctrl.update_presentation(0.016, 1.0)
	_assert(pres_ctrl.get_actor_pool().get_active_count() > 0 and pres_ctrl.get_actor_pool().get_active_count() <= 48, "J4: Phase 6 discovers and hydrates seeded residents within pool cap")

	wv.queue_free()
	await process_frame

	# J5: Save/Load staged WorldView (is_loading_save = true, matching MainMenu load path) must NOT seed
	var wv_load: Node = WorldViewScene.instantiate()
	wv_load.set("is_loading_save", true)
	wv_load.set("world_seed", 12345)
	root.add_child(wv_load)
	await process_frame
	wv_load.apply_settlement_overlays_from_world_data()
	var load_mgr: Node = wv_load.get("settlement_simulation_manager")
	var load_pop: int = int(load_mgr.get_telemetry()["registered_villagers"]) if load_mgr != null else -1
	var any_seeded_on_load: bool = false
	if load_mgr != null:
		for l_sid in load_mgr.get_registered_settlement_ids():
			var l_ctx = load_mgr.get_context(l_sid)
			if l_ctx != null and l_ctx.sim_state != null and l_ctx.sim_state.initial_population_seeded:
				any_seeded_on_load = true
	_assert(load_pop == 0 and not any_seeded_on_load, "J5: WorldView with is_loading_save=true skips initial seeding (0 residents, initial_population_seeded=false)")
	wv_load.queue_free()
	await process_frame

func _init() -> void:
	print("====================================================================")
	print("  TEST SUITE: P5-07 Initial Settlement Population Seeding")
	print("====================================================================")
	call_deferred("_run_all")

func _run_all() -> void:
	_run_categories_a_to_e()
	_run_categories_f_to_i()
	await _run_category_j_worldview_and_phase6()

	print("\n--------------------------------------------------------------------")
	print("  Results: %d passed, %d failed" % [_passed, _failed])
	print("====================================================================")
	if _failed == 0:
		print("ALL %d ASSERTIONS PASSED! (Exit Code 0)" % _passed)
		quit(0)
	else:
		print("FAILED WITH %d FAILURES! (Exit Code 1)" % _failed)
		quit(1)
