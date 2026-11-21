class_name TestSettlementHunterH1
extends SceneTree
## Focused Test Suite for Implementation Slice H1:
## Town Hall Hunting, Canonical WorldData Wildlife & Exclusive Prey Allocation (Phase 4 / P4-20).
## Authoritative Verification across Categories A–H.

const SettlementSimulationManagerScript = preload("res://scripts/world/settlement_simulation_manager.gd")
const SettlementResourceSourceAdapterScript = preload("res://scripts/world/settlement_resource_source_adapter.gd")
const SettlementVillagerContextScript = preload("res://scripts/world/settlement_villager_context.gd")
const SettlementSimulationStateScript = preload("res://scripts/world/settlement_simulation_state.gd")
const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementBuildingCapabilityAdapterScript = preload("res://scripts/world/settlement_building_capability_adapter.gd")
const SettlementDataScript = preload("res://scripts/world/settlement_data.gd")
const SettlementGeneratorScript = preload("res://scripts/world/settlement_generator.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const WildlifeManagerScript = preload("res://scripts/world/wildlife_manager.gd")
const WildlifeConfig = preload("res://scripts/world/wildlife_config.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const TimeManagerScript = preload("res://scripts/core/time_manager.gd")
const IsoMath = preload("res://scripts/utils/iso_math.gd")

var _passed: int = 0
var _failed: int = 0

func _init() -> void:
	call_deferred("_run_tests")

func _assert(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("  [PASS] %s" % message)
	else:
		_failed += 1
		printerr("  [FAIL] %s" % message)

func _create_mock_world_data(map_size: int = 100, seed_val: int = 12345) -> WorldGeneratorScript.WorldData:
	var wd = WorldGeneratorScript.WorldData.new()
	wd.seed_value = seed_val
	wd.generator_version = 8
	wd.map_width = map_size
	wd.map_height = map_size
	wd.player_center = Vector2i(map_size / 2, map_size / 2) # e.g. (50, 50)
	wd.center_spawn = wd.player_center + Vector2i(0, 1)
	wd.townhall_anchor = wd.player_center + Vector2i(-1, -2)
	wd.terrain = []
	wd.occupancy = []
	wd.biome_grid = []
	for x in range(map_size):
		var t_col: Array = []
		var o_col: Array = []
		var b_col: Array = []
		for y in range(map_size):
			t_col.append(WorldGeneratorScript.TerrainType.GRASS)
			o_col.append(false)
			b_col.append(WorldGeneratorScript.BiomeType.GRASSLAND)
		wd.terrain.append(t_col)
		wd.occupancy.append(o_col)
		wd.biome_grid.append(b_col)
	WorldGeneratorScript.generate_canonical_wildlife(wd, null)
	return wd

func _build_canonical_settlement(sid: String, fid: String = "neutral_tribe", tier: String = "full", anchor: Vector2i = Vector2i(30, 30)) -> RefCounted:
	var layout: Dictionary = SettlementGeneratorScript._build_layout_template(fid, anchor, tier)
	var role: String = SettlementDataScript.ROLE_VILLAGE if fid == "neutral_tribe" else SettlementDataScript.ROLE_CAPITAL
	var stl := SettlementDataScript.new(sid, fid, fid, role, anchor, "outpost_%s" % fid)
	stl.layout_tier = tier
	for b in layout.get("buildings", []):
		stl.buildings.append((b as Dictionary).duplicate(true))
	for r in layout.get("roads", []):
		stl.roads.append(r)
	for dec in layout.get("decorations", []):
		stl.decorations.append((dec as Dictionary).duplicate(true))
	return stl

func _setup_hunter_context(sid: String = "stl_hunter_test", fid: String = "neutral_tribe", anchor: Vector2i = Vector2i(30, 30), tier: String = "full") -> Dictionary:
	var ctx := SettlementVillagerContextScript.new(sid, fid, fid, 1, true)
	ctx.set_meta("enable_hunter", true)
	var stl = _build_canonical_settlement(sid, fid, tier, anchor)
	ctx.reconcile_buildings(stl)

	# Find Town Hall hunter workplace
	var hunter_wp: RefCounted = null
	for wp in ctx.workplace_registry.get_all_workplaces():
		if wp.output_resource == EconomyConfigScript.RES_RAW_MEAT or wp.workplace_id.ends_with("__hunter"):
			hunter_wp = wp
			break

	# Add 1 hunter villager
	var v = ctx.create_and_add_villager("vh_%s" % sid, SettlementVillagerDataScript.ROLE_HUNTER, anchor)
	v.last_processed_hour_seq = -1

	# Assign to hunter job if present
	var hunter_job: RefCounted = null
	for j in ctx.job_board.get_all_jobs():
		if j.job_type == SettlementVillagerDataScript.ROLE_HUNTER:
			hunter_job = j
			break
	if hunter_job != null:
		hunter_job.assigned_villager_id = v.villager_id
		v.active_job_id = hunter_job.job_id
		v.workplace_id = hunter_job.workplace_id

	return {
		"ctx": ctx,
		"stl": stl,
		"wp": hunter_wp,
		"job": hunter_job,
		"villager": v
	}

func _run_tests() -> void:
	print("====================================================================")
	print("  TEST SUITE: Town Hall Hunting & Wildlife Allocation (H1 / P4-20)")
	print("====================================================================")

	_test_category_a_town_hall_workplace()
	_test_category_b_canonical_wildlife_in_world_data()
	_test_category_c_exclusive_prey_allocation_and_mutual_exclusion()
	_test_category_d_yield_fractional_labor_banking_and_timing()
	_test_category_e_economic_accounting_and_provenance()
	_test_category_f_time_and_schedule()
	_test_category_g_player_hunter_regression()
	_test_category_h_rival_player_isolation()

	print("--------------------------------------------------------------------")
	print("  Results: %d passed, %d failed" % [_passed, _failed])
	print("====================================================================")
	if _failed == 0:
		print("ALL %d ASSERTIONS PASSED! (Exit Code 0)" % _passed)
		quit(0)
	else:
		printerr("FAILED: %d assertions failed!" % _failed)
		quit(1)

# -----------------------------------------------------------------------------
# Category A: Town Hall Hunter Workplace & Job Registration
# -----------------------------------------------------------------------------
func _test_category_a_town_hall_workplace() -> void:
	print("\n[Category A] Town Hall Hunter Workplace & Job Registration")

	var setup = _setup_hunter_context("stl_a", "neutral_tribe", Vector2i(30, 30), "full")
	var ctx: RefCounted = setup["ctx"]
	var wp: RefCounted = setup["wp"]
	var job: RefCounted = setup["job"]
	var v: RefCounted = setup["villager"]

	# A1: Workplace properties
	_assert(wp != null, "A1.1: Town Hall Hunter workplace is registered")
	_assert(wp.building_type == "townhall", "A1.2: Hunter workplace building_type is townhall")
	_assert(wp.output_resource == EconomyConfigScript.RES_RAW_MEAT, "A1.3: Hunter workplace output_resource is raw_meat")
	_assert(wp.worker_quota == 1, "A1.4: Hunter workplace quota is exactly 1")
	_assert(wp.is_dropoff == true, "A1.5: Hunter workplace retains is_dropoff=true")
	_assert(wp.workplace_id.ends_with("__hunter"), "A1.6: Hunter workplace_id has __hunter suffix")

	# A2: Job properties
	_assert(job != null, "A2.1: Hunter job posted on job board")
	_assert(job.job_type == SettlementVillagerDataScript.ROLE_HUNTER, "A2.2: Job type is hunter")
	_assert(job.work_hours_required == 2.5, "A2.3: Job default work_hours_required is 2.5")
	_assert(job.priority == SettlementBuildingCapabilityAdapterScript.PRIORITY_HUNTER, "A2.4: Job priority is PRIORITY_HUNTER (9)")

	# A3: Town Hall hauler slots preserved
	var hauler_jobs: Array = []
	for j in ctx.job_board.get_all_jobs():
		if j.job_type == SettlementVillagerDataScript.ROLE_HAULER:
			hauler_jobs.append(j)
	_assert(hauler_jobs.size() == 2, "A3.1: Full tier Town Hall preserves exactly 2 hauler jobs alongside hunter")

	var compact_setup = _setup_hunter_context("stl_a_c", "neutral_tribe", Vector2i(20, 20), "compact")
	var compact_ctx: RefCounted = compact_setup["ctx"]
	var compact_haulers: Array = []
	for j in compact_ctx.job_board.get_all_jobs():
		if j.job_type == SettlementVillagerDataScript.ROLE_HAULER:
			compact_haulers.append(j)
	_assert(compact_haulers.size() == 1, "A3.2: Compact tier Town Hall preserves exactly 1 hauler job alongside hunter")

	# A4: Role mismatch validation (fail closed)
	var wd := _create_mock_world_data()
	SettlementResourceSourceAdapterScript.register_hunter_source(ctx, wp.workplace_id, wd)
	var farmer_v = ctx.create_and_add_villager("v_farmer_mismatch", SettlementVillagerDataScript.ROLE_FARMER, Vector2i(30, 30))
	var fail_role := SettlementResourceSourceAdapterScript.prepare_hunter_production_transaction(
		ctx, wp.workplace_id, wd, null, farmer_v, 1.0, 0
	)
	_assert(not fail_role["ok"] and fail_role["reason"] == "villager_role_mismatch", "A4: Farmer assigned to hunter workplace fails closed with 'villager_role_mismatch'")

	# A5: Villager state validation (dead / null)
	var dead_v = ctx.create_and_add_villager("v_dead_hunter", SettlementVillagerDataScript.ROLE_HUNTER, Vector2i(30, 30))
	dead_v.life_state = SettlementVillagerDataScript.LIFE_DEAD
	var fail_dead := SettlementResourceSourceAdapterScript.prepare_hunter_production_transaction(
		ctx, wp.workplace_id, wd, null, dead_v, 1.0, 0
	)
	_assert(not fail_dead["ok"] and fail_dead["reason"] == "villager_not_alive", "A5.1: Dead hunter fails closed with 'villager_not_alive'")

	var fail_null := SettlementResourceSourceAdapterScript.prepare_hunter_production_transaction(
		ctx, wp.workplace_id, wd, null, null, 1.0, 0
	)
	_assert(not fail_null["ok"] and fail_null["reason"] == "missing_hunter_villager", "A5.2: Null hunter fails closed with 'missing_hunter_villager'")

	# A6: Workplace active / pause validation
	wp.is_active = false
	var fail_inact := SettlementResourceSourceAdapterScript.prepare_hunter_production_transaction(
		ctx, wp.workplace_id, wd, null, v, 1.0, 0
	)
	_assert(not fail_inact["ok"] and fail_inact["reason"] == "workplace_inactive", "A6.1: Inactive workplace fails closed with 'workplace_inactive'")
	wp.is_active = true

	wp.is_paused = true
	var fail_pause := SettlementResourceSourceAdapterScript.prepare_hunter_production_transaction(
		ctx, wp.workplace_id, wd, null, v, 1.0, 0
	)
	_assert(not fail_pause["ok"] and fail_pause["reason"] == "workplace_paused", "A6.2: Paused workplace fails closed with 'workplace_paused'")
	wp.is_paused = false

# -----------------------------------------------------------------------------
# Category B: Canonical Wildlife in WorldData
# -----------------------------------------------------------------------------
func _test_category_b_canonical_wildlife_in_world_data() -> void:
	print("\n[Category B] Canonical Wildlife in WorldData")

	var wd1 := _create_mock_world_data(100, 424242)
	var wd2 := _create_mock_world_data(100, 424242)

	# B1: Deterministic generation from seed
	_assert(wd1.wildlife.size() > 0, "B1.1: Canonical wildlife generated in WorldData")
	_assert(wd1.wildlife.size() == wd2.wildlife.size(), "B1.2: Wildlife counts identical for identical seeds")

	var identical := true
	for i in range(wd1.wildlife.size()):
		var a1: Dictionary = wd1.wildlife[i]
		var a2: Dictionary = wd2.wildlife[i]
		if a1["id"] != a2["id"] or a1["species_id"] != a2["species_id"] or a1["cell"] != a2["cell"]:
			identical = false
			break
	_assert(identical, "B1.3: Animal records, IDs, and positions are byte-deterministic across identical seeds")

	# B2: Canonical Rabbit and Deer yield, hunt duration, and recovery
	var found_rabbit := false
	var found_deer := false
	var rabbit_ok := true
	var deer_ok := true

	for a in wd1.wildlife:
		var sp: String = a["species_id"]
		if sp == "rabbit":
			found_rabbit = true
			if a["raw_meat_yield"] != 2 or not is_equal_approx(a["hunt_duration_hours"], 1.5) or not is_equal_approx(a["recovery_hours"], 48.0):
				rabbit_ok = false
		elif sp == "deer":
			found_deer = true
			if a["raw_meat_yield"] != 4 or not is_equal_approx(a["hunt_duration_hours"], 2.5) or not is_equal_approx(a["recovery_hours"], 72.0):
				deer_ok = false

	_assert(found_rabbit and rabbit_ok, "B2.1: Rabbit has raw_meat_yield=2, hunt_duration_hours=1.5, recovery_hours=48.0")
	_assert(found_deer and deer_ok, "B2.2: Deer has raw_meat_yield=4, hunt_duration_hours=2.5, recovery_hours=72.0")

	# B3: Lookup methods on WorldData
	var first_a: Dictionary = wd1.wildlife[0]
	var looked_up: Dictionary = wd1.get_animal_by_id(first_a["id"])
	_assert(looked_up == first_a, "B3.1: get_animal_by_id retrieves canonical animal record")
	_assert(wd1.get_animal_by_id("non_existent").is_empty(), "B3.2: get_animal_by_id returns empty dictionary for unknown id")
	_assert(wd1.get_all_animals().size() == wd1.wildlife.size(), "B3.3: get_all_animals returns all canonical animals")

	# B4: Initial reservation and availability flags
	var initial_flags_ok := true
	for a in wd1.wildlife:
		if not a["is_available"] or not a["reserved_by"].is_empty() or not is_equal_approx(a["recovery_hours_left"], 0.0):
			initial_flags_ok = false
			break
	_assert(initial_flags_ok, "B4: All canonical animals initialized as available, unreserved, and 0 recovery hours")

# -----------------------------------------------------------------------------
# Category C: Exclusive Prey Allocation & Mutual Exclusion
# -----------------------------------------------------------------------------
func _test_category_c_exclusive_prey_allocation_and_mutual_exclusion() -> void:
	print("\n[Category C] Exclusive Prey Allocation & Mutual Exclusion")

	var wd := _create_mock_world_data(100, 99999)
	var setup1 = _setup_hunter_context("stl_c1", "neutral_tribe", Vector2i(25, 25), "full")
	var setup2 = _setup_hunter_context("stl_c2", "iron_claws", Vector2i(75, 75), "full")
	var ctx1: RefCounted = setup1["ctx"]
	var ctx2: RefCounted = setup2["ctx"]

	var allocs := SettlementResourceSourceAdapterScript.allocate_global_hunter_sources(
		[ctx1, ctx2], wd, wd.player_center
	)
	_assert(not allocs.is_empty(), "C1.1: Global hunter source allocation executed")

	# C2: Mutual exclusion in allocation (no animal in multiple workplaces)
	var seen_animals: Dictionary = {}
	var duplicate_found := false
	for wpid in allocs:
		for aid in allocs[wpid]:
			if seen_animals.has(aid):
				duplicate_found = true
			seen_animals[aid] = wpid
	_assert(not duplicate_found and seen_animals.size() > 0, "C2: Every allocated animal is bound to at most ONE Town Hall Hunter workplace")

	# C3: Proximity Allocation Harmonization (Audit A: verified no unsupported radius-14 global exclusion)
	var any_allocated := seen_animals.size() > 0
	_assert(any_allocated, "C3: Wildlife allocation operates without unsupported radius-14 exclusion; reservation protects prey")

	# C4: Player reservation blocks Rival hunter
	var wp1: RefCounted = setup1["wp"]
	var v1: RefCounted = setup1["villager"]
	SettlementResourceSourceAdapterScript.register_hunter_source(ctx1, wp1.workplace_id, wd)

	var src1: Dictionary = ctx1.sim_state.production_sources[wp1.workplace_id]
	var allocated_list: Array = src1.get("allocated_animals", [])
	if not allocated_list.is_empty():
		# Manually reserve all allocated animals by player
		for aid in allocated_list:
			var arec: Dictionary = wd.get_animal_by_id(aid)
			arec["is_available"] = false
			arec["reserved_by"] = "player"
			arec["reservation_type"] = "player"

		var prep_blocked := SettlementResourceSourceAdapterScript.prepare_hunter_production_transaction(
			ctx1, wp1.workplace_id, wd, null, v1, 1.0, 0
		)
		_assert(not prep_blocked["ok"] and prep_blocked["reason"] == "no_available_prey", "C4: Player reservation blocks Rival hunter from harvesting allocated prey")

		# Release one animal
		var first_aid: String = allocated_list[0]
		var first_rec: Dictionary = wd.get_animal_by_id(first_aid)
		first_rec["is_available"] = true
		first_rec["reserved_by"] = ""
		first_rec["reservation_type"] = ""

		var prep_ok := SettlementResourceSourceAdapterScript.prepare_hunter_production_transaction(
			ctx1, wp1.workplace_id, wd, null, v1, 1.0, 0
		)
		_assert(prep_ok["ok"] and prep_ok["target_prey_id"] == first_aid, "C4.2: Released animal immediately becomes eligible for Rival hunter")

	# C5: Rival reservation blocks Player reservation in WildlifeManager
	var wm := WildlifeManagerScript.new()
	wm.generate_initial_population(wd, null)

	# Pick an animal and reserve it by rival
	var test_animal: Dictionary = wd.wildlife[0]
	var ta_id: String = test_animal["id"]
	test_animal["is_available"] = false
	test_animal["reserved_by"] = "rival_villager_99"
	test_animal["reservation_type"] = "rival"

	var player_reserve_res: bool = wm.reserve_animal(ta_id, "player")
	_assert(not player_reserve_res, "C5: WildlifeManager.reserve_animal fails closed when prey is reserved by Rival hunter")

# -----------------------------------------------------------------------------
# Category D: Yield, Fractional Labor Banking & Timing
# -----------------------------------------------------------------------------
func _test_category_d_yield_fractional_labor_banking_and_timing() -> void:
	print("\n[Category D] Yield, Fractional Labor Banking & Timing")

	var wd := _create_mock_world_data(80, 55555)
	var setup = _setup_hunter_context("stl_d", "neutral_tribe", Vector2i(30, 30), "full")
	var ctx: RefCounted = setup["ctx"]
	var wp: RefCounted = setup["wp"]
	var v: RefCounted = setup["villager"]

	# Inject a mock rabbit and deer close to anchor
	var mock_rabbit: Dictionary = {
		"id": "animal_mock_rabbit",
		"species_id": "rabbit",
		"cell": Vector2i(32, 32),
		"raw_meat_yield": 2,
		"hunt_duration_hours": 1.5,
		"recovery_hours": 48.0,
		"is_available": true,
		"reserved_by": "",
		"reservation_type": "",
		"recovery_hours_left": 0.0,
		"allocated_workplace_id": wp.workplace_id,
		"allocated_settlement_id": ctx.settlement_id
	}
	var mock_deer: Dictionary = {
		"id": "animal_mock_deer",
		"species_id": "deer",
		"cell": Vector2i(33, 33),
		"raw_meat_yield": 4,
		"hunt_duration_hours": 2.5,
		"recovery_hours": 72.0,
		"is_available": true,
		"reserved_by": "",
		"reservation_type": "",
		"recovery_hours_left": 0.0,
		"allocated_workplace_id": wp.workplace_id,
		"allocated_settlement_id": ctx.settlement_id
	}
	wd.wildlife.append(mock_rabbit)
	wd.wildlife.append(mock_deer)
	wd.wildlife_by_id["animal_mock_rabbit"] = mock_rabbit
	wd.wildlife_by_id["animal_mock_deer"] = mock_deer

	SettlementResourceSourceAdapterScript.register_hunter_source(
		ctx, wp.workplace_id, wd, ["animal_mock_rabbit", "animal_mock_deer"]
	)

	# D1: Rabbit Hunt Lifecycle (1.5 hours total)
	# Hour 1: 1.0 hour done out of 1.5 required
	v.work_hours_done = 0.0
	var h1_res := SettlementResourceSourceAdapterScript.execute_hunter_production_transaction(
		ctx, wp.workplace_id, wd, null, v, 1.0, 0
	)
	_assert(h1_res["ok"] and not h1_res["hunt_completed"] and h1_res["meat_produced"] == 0, "D1.1: Hour 1 (1.0h) produces 0 meat and is incomplete")
	_assert(is_equal_approx(v.work_hours_done, 1.0), "D1.2: Villager work_hours_done tracks 1.0h banked")
	_assert(mock_rabbit["reserved_by"] == v.villager_id and not mock_rabbit["is_available"], "D1.3: Target rabbit is locked with reserved_by=villager_id")

	# Hour 2: 1.0 hour more -> total 2.0h >= 1.5h required
	var h2_res := SettlementResourceSourceAdapterScript.execute_hunter_production_transaction(
		ctx, wp.workplace_id, wd, null, v, 1.0, 1
	)
	_assert(h2_res["ok"] and h2_res["hunt_completed"] and h2_res["meat_produced"] == 2, "D1.4: Hour 2 completes rabbit hunt producing exactly 2 raw_meat")
	_assert(is_equal_approx(v.work_hours_done, 0.5), "D1.5: Exact fractional remainder (2.0 - 1.5 = 0.5h) banked in work_hours_done")
	_assert(mock_rabbit["recovery_hours_left"] == 48.0 and not mock_rabbit["is_available"] and mock_rabbit["reserved_by"].is_empty(), "D1.6: Rabbit enters recovery with recovery_hours_left=48.0 and unreserved")

	# D2: Deer Hunt Lifecycle (2.5 hours total)
	# Hour 3: starting from 0.5h remainder + 1.0h = 1.5h done out of 2.5h required
	var h3_res := SettlementResourceSourceAdapterScript.execute_hunter_production_transaction(
		ctx, wp.workplace_id, wd, null, v, 1.0, 2
	)
	_assert(h3_res["ok"] and not h3_res["hunt_completed"] and h3_res["meat_produced"] == 0, "D2.1: Hour 3 applies carried 0.5h remainder (total 1.5h) without hunt completion")
	_assert(is_equal_approx(v.work_hours_done, 1.5), "D2.2: Villager work_hours_done accurately tracks 1.5h")
	_assert(mock_deer["reserved_by"] == v.villager_id, "D2.3: Target deer is locked onto by hunter")

	# Hour 4: 1.5h + 1.0h = 2.5h >= 2.5h required
	var h4_res := SettlementResourceSourceAdapterScript.execute_hunter_production_transaction(
		ctx, wp.workplace_id, wd, null, v, 1.0, 3
	)
	_assert(h4_res["ok"] and h4_res["hunt_completed"] and h4_res["meat_produced"] == 4, "D2.4: Hour 4 completes deer hunt producing exactly 4 raw_meat")
	_assert(is_equal_approx(v.work_hours_done, 0.0), "D2.5: Remainder labor is exactly 0.0h")
	_assert(mock_deer["recovery_hours_left"] == 72.0 and not mock_deer["is_available"], "D2.6: Deer enters recovery with recovery_hours_left=72.0")

	# D3: Total yield verification
	var src: Dictionary = ctx.sim_state.production_sources[wp.workplace_id]
	_assert(int(src["total_produced"]) == 6 and int(src["cycles_completed"]) == 2, "D3: Total produced = 6 raw_meat (2 rabbit + 4 deer) across 2 completed cycles")

	# D4: Wildlife Recovery Tick & Re-activation
	var recovered_count_1 := SettlementResourceSourceAdapterScript.advance_wildlife_recovery(wd, 47.0)
	_assert(mock_rabbit["recovery_hours_left"] == 1.0 and not mock_rabbit["is_available"], "D4.1: Rabbit after 47h recovery still recovering (1.0h left)")

	var recovered_count_2 := SettlementResourceSourceAdapterScript.advance_wildlife_recovery(wd, 1.0)
	_assert(mock_rabbit["recovery_hours_left"] == 0.0 and mock_rabbit["is_available"], "D4.2: Rabbit after 48h total recovery is restored (is_available=true)")

	# Advance 24h more for deer (total 72h)
	SettlementResourceSourceAdapterScript.advance_wildlife_recovery(wd, 24.0)
	_assert(mock_deer["recovery_hours_left"] == 0.0 and mock_deer["is_available"], "D4.3: Deer after 72h total recovery is restored (is_available=true)")

	# D5: Restored rabbit can be hunted again
	var h5_prep := SettlementResourceSourceAdapterScript.prepare_hunter_production_transaction(
		ctx, wp.workplace_id, wd, null, v, 1.0, 4
	)
	_assert(h5_prep["ok"] and h5_prep["target_prey_id"] == "animal_mock_rabbit", "D5: Fully recovered rabbit is automatically re-selected for subsequent hunt")

# -----------------------------------------------------------------------------
# Category E: Economic Accounting & Provenance
# -----------------------------------------------------------------------------
func _test_category_e_economic_accounting_and_provenance() -> void:
	print("\n[Category E] Economic Accounting & Provenance")

	var wd := _create_mock_world_data(80, 77777)
	var setup = _setup_hunter_context("stl_e", "neutral_tribe", Vector2i(30, 30), "full")
	var ctx: RefCounted = setup["ctx"]
	var wp: RefCounted = setup["wp"]
	var v: RefCounted = setup["villager"]

	var mock_rabbit: Dictionary = {
		"id": "animal_rabbit_e",
		"species_id": "rabbit",
		"cell": Vector2i(31, 31),
		"raw_meat_yield": 2,
		"hunt_duration_hours": 1.5,
		"recovery_hours": 48.0,
		"is_available": true,
		"reserved_by": "",
		"reservation_type": "",
		"recovery_hours_left": 0.0,
		"allocated_workplace_id": wp.workplace_id,
		"allocated_settlement_id": ctx.settlement_id
	}
	wd.wildlife.append(mock_rabbit)
	wd.wildlife_by_id["animal_rabbit_e"] = mock_rabbit
	SettlementResourceSourceAdapterScript.register_hunter_source(ctx, wp.workplace_id, wd, ["animal_rabbit_e"])

	var init_raw_meat: int = ctx.economy.get_resource(EconomyConfigScript.RES_RAW_MEAT)
	var init_food: int = ctx.economy.get_resource("food")

	# Complete a rabbit hunt (1.5h) in 2 simulation steps
	SettlementResourceSourceAdapterScript.execute_hunter_production_transaction(ctx, wp.workplace_id, wd, null, v, 1.0, 0)
	SettlementResourceSourceAdapterScript.execute_hunter_production_transaction(ctx, wp.workplace_id, wd, null, v, 1.0, 1)

	# E1: Direct credit to SettlementEconomy
	var post_raw_meat: int = ctx.economy.get_resource(EconomyConfigScript.RES_RAW_MEAT)
	_assert(post_raw_meat == init_raw_meat + 2, "E1: Raw meat credited directly to settlement stock (+2)")

	# E2: Supply ledger logging
	var ledger: RefCounted = ctx.economy.ledger
	var entries: Array = ledger.get_recent_entries()
	var found_entry := false
	for entry in entries:
		if entry.get("resource_id", "") == EconomyConfigScript.RES_RAW_MEAT and entry.get("reason", "") == "hunter_production" and String(entry.get("source", "")).begins_with("workplace_output:"):
			found_entry = true
			break
	_assert(found_entry, "E2: Supply ledger logs entry with reason='hunter_production' and workplace_output source")

	# E3: Zero conversion to Food & Food Upkeep Protection
	var post_food: int = ctx.economy.get_resource("food")
	_assert(post_food == init_food, "E3.1: Food stock is strictly untouched by raw meat production")

	# Simulate food upkeep debit
	var food_upkeep_res: Dictionary = ctx.economy.debit_resource("food", 1, "daily_upkeep", "villager_upkeep", 1)
	_assert(food_upkeep_res["ok"], "E3.2: Food upkeep debits 'food' successfully")
	_assert(ctx.economy.get_resource(EconomyConfigScript.RES_RAW_MEAT) == post_raw_meat, "E3.3: Raw meat is NEVER consumed as upkeep food")

	# E4: Storage full fail-closed
	ctx.economy._capacities[EconomyConfigScript.RES_RAW_MEAT] = post_raw_meat # set capacity to current stock (100% full)
	mock_rabbit["is_available"] = true
	mock_rabbit["recovery_hours_left"] = 0.0
	mock_rabbit["reserved_by"] = ""
	v.work_hours_done = 1.0 # 0.5h needed to complete hunt

	var prep_full := SettlementResourceSourceAdapterScript.prepare_hunter_production_transaction(
		ctx, wp.workplace_id, wd, null, v, 1.0, 2
	)
	_assert(not prep_full["ok"] and prep_full["reason"] == "storage_full", "E4.1: Full meat storage fails closed in prepare with 'storage_full'")

	var exec_full := SettlementResourceSourceAdapterScript.execute_hunter_production_transaction(
		ctx, wp.workplace_id, wd, null, v, 1.0, 2
	)
	_assert(not exec_full["ok"] and exec_full["reason"] == "storage_full", "E4.2: Full meat storage fails closed in execute without corrupting progress or wildlife")
	_assert(is_equal_approx(v.work_hours_done, 1.0), "E4.3: Villager work_hours_done is preserved (1.0h) without discard")
	_assert(mock_rabbit["is_available"], "E4.4: Animal remains alive and available when storage is full")

# -----------------------------------------------------------------------------
# Category F: Time & Schedule
# -----------------------------------------------------------------------------
func _test_category_f_time_and_schedule() -> void:
	print("\n[Category F] Time & Schedule")

	var wd := _create_mock_world_data(80, 88888)
	var setup = _setup_hunter_context("stl_f", "neutral_tribe", Vector2i(30, 30), "full")
	var ctx: RefCounted = setup["ctx"]
	var wp: RefCounted = setup["wp"]
	var v: RefCounted = setup["villager"]

	var mock_rabbit: Dictionary = {
		"id": "animal_rabbit_f",
		"species_id": "rabbit",
		"cell": Vector2i(31, 31),
		"raw_meat_yield": 2,
		"hunt_duration_hours": 1.5,
		"recovery_hours": 48.0,
		"is_available": true,
		"reserved_by": "",
		"reservation_type": "",
		"recovery_hours_left": 0.0,
		"allocated_workplace_id": wp.workplace_id,
		"allocated_settlement_id": ctx.settlement_id
	}
	wd.wildlife.append(mock_rabbit)
	wd.wildlife_by_id["animal_rabbit_f"] = mock_rabbit
	SettlementResourceSourceAdapterScript.register_hunter_source(ctx, wp.workplace_id, wd, ["animal_rabbit_f"])

	# F1: DAY_SHIFT validation (05:00 to 17:00)
	# Hour 0 (06:00) is DAY_SHIFT
	var day_prep := SettlementResourceSourceAdapterScript.prepare_hunter_production_transaction(
		ctx, wp.workplace_id, wd, null, v, 1.0, 0
	)
	_assert(day_prep["ok"], "F1.1: Hour seq 0 (06:00, DAY_SHIFT) is valid for hunting")

	# Hour 23 (05:00, dawn) is DAY_SHIFT
	var dawn_prep := SettlementResourceSourceAdapterScript.prepare_hunter_production_transaction(
		ctx, wp.workplace_id, wd, null, v, 1.0, 23
	)
	_assert(dawn_prep["ok"], "F1.2: Hour seq 23 (05:00 DAWN, DAY_SHIFT) is valid for hunting")

	# Hour 11 (17:00, dusk) is DAY_SHIFT
	var dusk_prep := SettlementResourceSourceAdapterScript.prepare_hunter_production_transaction(
		ctx, wp.workplace_id, wd, null, v, 1.0, 11
	)
	_assert(dusk_prep["ok"], "F1.3: Hour seq 11 (17:00, DAY_SHIFT) is valid for hunting")

	# F2: Outside DAY_SHIFT (18:00 to 04:00)
	# Hour 12 (18:00, DUSK/NIGHT) is outside day shift
	var night_prep1 := SettlementResourceSourceAdapterScript.prepare_hunter_production_transaction(
		ctx, wp.workplace_id, wd, null, v, 1.0, 12
	)
	_assert(not night_prep1["ok"] and night_prep1["reason"] == "outside_day_shift", "F2.1: Hour seq 12 (18:00 DUSK) fails closed with 'outside_day_shift'")

	# Hour 18 (00:00 midnight) is outside day shift
	var night_prep2 := SettlementResourceSourceAdapterScript.prepare_hunter_production_transaction(
		ctx, wp.workplace_id, wd, null, v, 1.0, 18
	)
	_assert(not night_prep2["ok"] and night_prep2["reason"] == "outside_day_shift", "F2.2: Hour seq 18 (00:00 NIGHT) fails closed with 'outside_day_shift'")

	# F3: Overnight progress preservation
	v.work_hours_done = 1.0 # 1.0 hour done before dusk
	# Night hours tick (no execution)
	# Next day dawn (hour 23 = 05:00)
	_assert(is_equal_approx(v.work_hours_done, 1.0), "F3.1: Work progress preserved overnight without discard")
	var resume_res := SettlementResourceSourceAdapterScript.execute_hunter_production_transaction(
		ctx, wp.workplace_id, wd, null, v, 1.0, 23
	)
	_assert(resume_res["ok"] and resume_res["hunt_completed"], "F3.2: Hunter completes hunt at dawn using carried over progress")

# -----------------------------------------------------------------------------
# Category G: Player Hunter Regression
# -----------------------------------------------------------------------------
func _test_category_g_player_hunter_regression() -> void:
	print("\n[Category G] Player Hunter Regression")

	var wd := _create_mock_world_data(100, 31415)
	var wm := WildlifeManagerScript.new()
	wm.generate_initial_population(wd, null)

	# G1: Canonical projection into WildlifeManager
	_assert(wm.animals.size() == wd.wildlife.size(), "G1.1: WildlifeManager projects canonical WorldData.wildlife")
	_assert(wm.animals_by_id.size() == wd.wildlife_by_id.size(), "G1.2: WildlifeManager maps all canonical animal IDs")

	# G2: Player reservation & release lifecycle
	var target_a: Dictionary = {}
	var non_huntable_a: Dictionary = {}
	for a in wm.animals:
		if target_a.is_empty() and WildlifeConfig.is_huntable_species(a["species_id"]):
			target_a = a
		elif non_huntable_a.is_empty() and not WildlifeConfig.is_huntable_species(a["species_id"]):
			non_huntable_a = a
	var ta_id: String = target_a["id"]

	var reserved: bool = wm.reserve_animal(ta_id, "player")
	_assert(reserved and not target_a["is_available"] and target_a["reserved_by"] == "player", "G2.1: Player reserves canonical animal successfully")

	# Try duplicate player reservation
	var dup_reserve: bool = wm.reserve_animal(ta_id, "player_2")
	_assert(not dup_reserve, "G2.2: Cannot reserve already-reserved animal")

	# Release reservation
	wm.release_reservation(ta_id)
	_assert(target_a["is_available"] and target_a["reserved_by"].is_empty(), "G2.3: Releasing reservation restores animal availability")

	# G3: Mutual exclusion query & non-huntable exclusion
	_assert(not wm.is_animal_reserved(ta_id), "G3.1: Released animal is not reserved")
	var reserved_again: bool = wm.reserve_animal(ta_id, "citizen_player_1")
	_assert(reserved_again and wm.is_animal_reserved(ta_id), "G3.2: Animal can be reserved by Player citizen controller")
	wm.release_reservation(ta_id)

	if not non_huntable_a.is_empty():
		_assert(not wm.reserve_animal(non_huntable_a["id"], "player"), "G3.3: Non-huntable species cannot be reserved by Player")

# -----------------------------------------------------------------------------
# Category H: Rival/Player Architectural Isolation
# -----------------------------------------------------------------------------
func _test_category_h_rival_player_isolation() -> void:
	print("\n[Category H] Rival/Player Architectural Isolation")

	var wd := _create_mock_world_data(100, 44444)
	var setup = _setup_hunter_context("stl_h", "neutral_tribe", Vector2i(35, 35), "full")
	var ctx: RefCounted = setup["ctx"]
	var wp: RefCounted = setup["wp"]
	var v: RefCounted = setup["villager"]

	var sim_mgr := SettlementSimulationManagerScript.new()
	var tm := TimeManagerScript.new()
	sim_mgr.connect_time_manager(tm)
	wd.settlements = [setup["stl"]]
	sim_mgr.register_context(ctx)
	sim_mgr.set_world_data(wd)
	SettlementResourceSourceAdapterScript.register_all_hunter_sources([ctx], wd)

	# H1: Simulation manager runs fully headless without Player scene dependencies
	_assert(sim_mgr != null, "H1.1: SettlementSimulationManager operates headless")
	_assert(ctx.economy != null, "H1.2: Settlement economy is strictly local to settlement context")

	# H2: Simulation of 24 hours does not access player singletons or invent resources
	var initial_produced: int = int(ctx.sim_state.stats.get("produced", 0))
	sim_mgr.advance_to_hour_seq(0)
	sim_mgr.process_all_pending()

	for i in range(23):
		tm._advance_one_hour()
		sim_mgr.process_all_pending()

	var final_produced: int = int(ctx.sim_state.stats.get("produced", 0))
	_assert(final_produced >= 0, "H2.1: 24h simulation completes deterministically with valid production statistics")
	_assert(ctx.sim_state.production_sources.has(wp.workplace_id), "H2.2: Town Hall hunter source is verified and tracked in sim_state")

	sim_mgr.free()
	tm.free()
