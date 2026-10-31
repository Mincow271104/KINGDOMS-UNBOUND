extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — Package 2B: Citizen Skill Progression & Vocational Specialization
## Strictly covers TC-SKL-01 through TC-SKL-22 with fail-closed assertions.

const CitizenControllerScript = preload("res://scripts/entities/citizen_controller.gd")
const CitizenSkillDataScript = preload("res://scripts/entities/citizen_skill_data.gd")
const JobManagerScript = preload("res://scripts/jobs/job_manager.gd")
const WorkplaceManagerScript = preload("res://scripts/economy/workplace_manager.gd")
const GridNavigationScript = preload("res://scripts/navigation/grid_navigation.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")

const TEST_SAVE_PATH: String = "user://test_package_2b_citizen_skills.json"

class MockTestResourceManager extends Node:
	var stock: Dictionary = {}
	var capacities: Dictionary = {}

	func _init(initial: Dictionary = {}) -> void:
		for r in EconomyConfig.ALL_RESOURCES:
			stock[r] = initial.get(r, 0)
			capacities[r] = 500
		capacities[EconomyConfig.RES_GOLD] = 999999

	func get_available_stock(res_id: String) -> int:
		return stock.get(res_id, 0)

	func get_total_stock(res_id: String) -> int:
		return stock.get(res_id, 0)

	func get_storage_capacity(res_id: String) -> int:
		return capacities.get(res_id, 500)

	func can_afford(cost: Dictionary) -> bool:
		for r in cost:
			if get_available_stock(r) < cost[r]:
				return false
		return true

	func reserve_cost(cost: Dictionary) -> bool:
		return can_afford(cost)

	func commit_cost(cost: Dictionary) -> void:
		for r in cost:
			stock[r] = get_available_stock(r) - cost[r]

	func add_resource(res_id: String, amount: int) -> int:
		var cur = get_available_stock(res_id)
		var max_cap = capacities.get(res_id, 500)
		var added = mini(amount, max_cap - cur)
		stock[res_id] = cur + added
		return added

	func has_resource(res_id: String, amount: int) -> bool:
		return get_available_stock(res_id) >= amount

var frame_count: int = 0
var all_passed: bool = true
var test_results: Array[Dictionary] = []

func _init() -> void:
	print("\n========================================================")
	print("  STARTING PACKAGE 2B CITIZEN SKILL PROGRESSION TESTS")
	print("========================================================\n")
	SaveManagerScript.set_test_default_save_path(TEST_SAVE_PATH)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count == 2:
		_run_all_tests()
	return false

func _record(test_id: String, passed: bool, message: String) -> void:
	test_results.append({"id": test_id, "passed": passed, "message": message})
	if passed:
		print("  [PASS] %s: %s" % [test_id, message])
	else:
		printerr("  [FAIL] %s: %s" % [test_id, message])
		all_passed = false

func _run_all_tests() -> void:
	# Part 1: Data Model
	_test_tc_skl_01_initialization()
	_test_tc_skl_02_thresholds_and_levels()
	_test_tc_skl_03_efficiency_multipliers()
	_test_tc_skl_04_xp_clamping()
	_test_tc_skl_05_malformed_data_handling()

	# Part 2: XP Attribution
	_test_tc_skl_06_production_xp_attribution()
	_test_tc_skl_07_failed_production_no_xp()
	_test_tc_skl_08_construction_labor_xp()
	_test_tc_skl_09_multiple_builders_independent_credit()
	_test_tc_skl_10_hauling_delivery_xp()
	_test_tc_skl_11_failed_hauling_no_xp()
	_test_tc_skl_12_non_work_states_zero_xp()
	_test_tc_skl_13_repeated_callbacks_idempotency()

	# Part 3: Gameplay Effects
	_test_tc_skl_14_worker_specific_production_efficiency()
	_test_tc_skl_15_builder_construction_contribution()
	_test_tc_skl_16_hauler_logistics_speed()
	_test_tc_skl_17_seasons_and_workplace_modifiers()

	# Part 4: Persistence and Cross-Training
	_test_tc_skl_18_role_switching_xp_retention()
	_test_tc_skl_19_save_load_roundtrip()
	_test_tc_skl_20_legacy_save_fallback()
	_test_tc_skl_21_malformed_saved_xp_recovery()
	_test_tc_skl_22_citizen_inspector_ui_reflection()

	# Part 5: Critical Invariants and Edge-Case Hardening
	_test_tc_skl_23_partial_production_zero_xp()
	_test_tc_skl_24_builder_completion_overrun_bounded_xp()
	_test_tc_skl_25_hauler_partial_deposit_cargo_preservation()
	_test_tc_skl_26_multiple_builders_skill_pro_rated_completion()
	_test_tc_skl_27_completed_or_cancelled_building_zero_xp()

	_print_summary()
	_cleanup()
	quit(0 if all_passed else 1)

# -----------------------------------------------------------------------------
# Part 1: Data Model
# -----------------------------------------------------------------------------

func _test_tc_skl_01_initialization() -> void:
	var cit := CitizenControllerScript.new()
	var s_data: CitizenSkillData = cit.get_skill_data()
	var ok := (s_data != null)
	for voc in CitizenSkillDataScript.VOCATIONS:
		if s_data.get_xp(voc) != 0.0 or s_data.get_level(voc) != 1 or s_data.get_efficiency(voc) != 1.00:
			ok = false
			break
	_record("TC-SKL-01", ok, "New citizen initializes all 6 skills at 0 XP, Level 1, 1.00x efficiency")

func _test_tc_skl_02_thresholds_and_levels() -> void:
	var s_data := CitizenSkillDataScript.new()
	var ok := true
	# Level 1: 0 - 99
	ok = ok and (s_data.get_level_for_xp(0.0) == 1)
	ok = ok and (s_data.get_level_for_xp(99.9) == 1)
	# Level 2: 100 - 299
	ok = ok and (s_data.get_level_for_xp(100.0) == 2)
	ok = ok and (s_data.get_level_for_xp(299.9) == 2)
	# Level 3: 300 - 599
	ok = ok and (s_data.get_level_for_xp(300.0) == 3)
	ok = ok and (s_data.get_level_for_xp(599.9) == 3)
	# Level 4: 600 - 999
	ok = ok and (s_data.get_level_for_xp(600.0) == 4)
	ok = ok and (s_data.get_level_for_xp(999.9) == 4)
	# Level 5: 1000
	ok = ok and (s_data.get_level_for_xp(1000.0) == 5)
	_record("TC-SKL-02", ok, "Cumulative XP thresholds map deterministically to Levels 1..5")

func _test_tc_skl_03_efficiency_multipliers() -> void:
	var ok := true
	ok = ok and is_equal_approx(CitizenSkillDataScript.get_efficiency_for_level(1), 1.00)
	ok = ok and is_equal_approx(CitizenSkillDataScript.get_efficiency_for_level(2), 1.08)
	ok = ok and is_equal_approx(CitizenSkillDataScript.get_efficiency_for_level(3), 1.16)
	ok = ok and is_equal_approx(CitizenSkillDataScript.get_efficiency_for_level(4), 1.25)
	ok = ok and is_equal_approx(CitizenSkillDataScript.get_efficiency_for_level(5), 1.35)
	_record("TC-SKL-03", ok, "Level multipliers match approved schedule: 1.00x, 1.08x, 1.16x, 1.25x, 1.35x max")

func _test_tc_skl_04_xp_clamping() -> void:
	var s_data := CitizenSkillDataScript.new()
	s_data.add_xp("farming", -50.0) # Negative rejected
	var ok: bool = (s_data.get_xp("farming") == 0.0)
	s_data.add_xp("farming", 500.0)
	ok = ok and (s_data.get_xp("farming") == 500.0)
	s_data.add_xp("farming", 900.0) # Exceeds max 1000.0
	ok = ok and (s_data.get_xp("farming") == 1000.0)
	ok = ok and (s_data.get_level("farming") == 5)
	ok = ok and is_equal_approx(s_data.get_efficiency("farming"), 1.35)
	_record("TC-SKL-04", ok, "XP is strictly clamped to [0.0, 1000.0]")

func _test_tc_skl_05_malformed_data_handling() -> void:
	var s_data := CitizenSkillDataScript.new()
	# Unknown vocation returns false
	var res_bad := s_data.add_xp("alchemy", 100.0)
	var ok: bool = (not res_bad)
	ok = ok and (s_data.get_xp("alchemy") == 0.0)
	ok = ok and (s_data.get_level("alchemy") == 1)
	ok = ok and (s_data.get_efficiency("alchemy") == 1.00)

	# Deserializing malformed data
	s_data.deserialize({
		"farming": "not_a_number",
		"woodcutting": NAN,
		"mining": INF,
		"smithing": -999.0,
		"building": 999999.0,
		"invalid_voc": 500.0
	})
	ok = ok and (s_data.get_xp("farming") == 0.0)
	ok = ok and (s_data.get_xp("woodcutting") == 0.0)
	ok = ok and (s_data.get_xp("mining") == 0.0)
	ok = ok and (s_data.get_xp("smithing") == 0.0)
	ok = ok and (s_data.get_xp("building") == 1000.0) # Clamped to 1000.0
	_record("TC-SKL-05", ok, "Malformed, unknown, NaN, Inf, and negative skill values recover fail-closed")

# -----------------------------------------------------------------------------
# Part 2: XP Attribution
# -----------------------------------------------------------------------------

func _test_tc_skl_06_production_xp_attribution() -> void:
	var jm := JobManagerScript.new()
	var wm := WorkplaceManagerScript.new()
	var rm := MockTestResourceManager.new()
	wm.register_workplace("wp_farm_01", "farm", Vector2i(10, 10), Vector2i(2, 2), Vector2i(10, 10), EconomyConfigScript.RES_FOOD, 50, 5.0, 5)

	var cit := CitizenControllerScript.new()
	cit.init_citizen("cit_farm_01", "Farmer One", "farmer", Vector2i(10, 10), null, jm, wm)

	var job := jm.create_job("farmer", Vector2i(10, 10), "Harvest", "wp_farm_01", 1.0, 1, true)
	job.state = JobManagerScript.JobState.IN_PROGRESS
	job.worker_id = cit.citizen_id
	cit.active_job = job
	cit.current_state = CitizenControllerScript.State.WORKING

	# Advance 1.0 hour to complete the job
	cit._process_working(1.0)

	var xp := cit.get_skill_data().get_xp("farming")
	var other_xp := cit.get_skill_data().get_xp("woodcutting")
	var ok := (xp == 10.0 and other_xp == 0.0 and wm.get_buffer_amount("wp_farm_01") == 5)
	_record("TC-SKL-06", ok, "Successful production cycle awards exactly +10 XP to matching worker and vocation")

func _test_tc_skl_07_failed_production_no_xp() -> void:
	var jm := JobManagerScript.new()
	var wm := WorkplaceManagerScript.new()
	wm.register_workplace("wp_farm_full", "farm", Vector2i(10, 10), Vector2i(2, 2), Vector2i(10, 10), EconomyConfigScript.RES_FOOD, 50, 5.0, 5)
	# Fill buffer to capacity so production cannot commit
	wm.get_workplace("wp_farm_full").buffer_amount = 50

	var cit := CitizenControllerScript.new()
	cit.init_citizen("cit_farm_02", "Farmer Two", "farmer", Vector2i(10, 10), null, jm, wm)

	var job := jm.create_job("farmer", Vector2i(10, 10), "Harvest", "wp_farm_full", 1.0, 1, true)
	job.state = JobManagerScript.JobState.IN_PROGRESS
	job.worker_id = cit.citizen_id
	cit.active_job = job
	cit.current_state = CitizenControllerScript.State.WORKING

	# Advance 1.0 hour to trigger completion attempt with full buffer
	cit._process_working(1.0)

	var xp := cit.get_skill_data().get_xp("farming")
	var ok := (xp == 0.0) # Zero XP because output could not be committed
	_record("TC-SKL-07", ok, "Failed/blocked production cycle awards zero XP")

func _test_tc_skl_08_construction_labor_xp() -> void:
	var jm := JobManagerScript.new()
	var cit := CitizenControllerScript.new()
	cit.init_citizen("cit_builder_01", "Builder One", "builder", Vector2i(20, 20), null, jm, null)

	var job := jm.create_job("builder", Vector2i(20, 20), "Build house", "bld_house_test", 12.0, 1, false)
	job.state = JobManagerScript.JobState.IN_PROGRESS
	job.worker_id = cit.citizen_id
	cit.active_job = job
	cit.current_state = CitizenControllerScript.State.WORKING

	# Mock construction handler advancing progress
	var current_prog: float = 0.0
	cit.set_construction_handler(func(b_id: String, delta_hrs: float):
		current_prog += delta_hrs
		return {"success": true, "completed": false, "progress": current_prog, "hours": 12.0}
	)

	# Work 2.5 game hours -> should earn 2.5 * 5.0 = 12.5 XP
	cit._process_building_work(2.5)

	var xp := cit.get_skill_data().get_xp("building")
	var ok := is_equal_approx(xp, 12.5)
	_record("TC-SKL-08", ok, "Active construction labor awards exactly 5.0 XP per game-hour of labor contributed")

func _test_tc_skl_09_multiple_builders_independent_credit() -> void:
	var jm := JobManagerScript.new()
	var cit_a := CitizenControllerScript.new()
	var cit_b := CitizenControllerScript.new()
	cit_a.init_citizen("builder_a", "Builder A", "builder", Vector2i(20, 20), null, jm, null)
	cit_b.init_citizen("builder_b", "Builder B", "builder", Vector2i(21, 20), null, jm, null)

	var site_tracker := [0.0]
	var handler := func(b_id: String, delta_hrs: float):
		site_tracker[0] += delta_hrs
		return {"success": true, "completed": false, "progress": site_tracker[0], "hours": 20.0}

	cit_a.set_construction_handler(handler)
	cit_b.set_construction_handler(handler)

	var job_a := jm.create_job("builder", Vector2i(20, 20), "Build", "site_multi", 20.0, 1, false)
	var job_b := jm.create_job("builder", Vector2i(21, 20), "Build", "site_multi", 20.0, 1, false)
	job_a.state = JobManagerScript.JobState.IN_PROGRESS
	job_b.state = JobManagerScript.JobState.IN_PROGRESS
	cit_a.active_job = job_a
	cit_b.active_job = job_b

	# Builder A works 1.0 hour -> +5.0 XP
	cit_a._process_building_work(1.0)
	# Builder B works 3.0 hours -> +15.0 XP
	cit_b._process_building_work(3.0)

	var xp_a := cit_a.get_skill_data().get_xp("building")
	var xp_b := cit_b.get_skill_data().get_xp("building")
	var ok := is_equal_approx(xp_a, 5.0) and is_equal_approx(xp_b, 15.0) and is_equal_approx(site_tracker[0], 4.0)
	_record("TC-SKL-09", ok, "Multiple builders receive only their own contribution credit (5.0 vs 15.0 XP)")

func _test_tc_skl_10_hauling_delivery_xp() -> void:
	var jm := JobManagerScript.new()
	var cit := CitizenControllerScript.new()
	cit.init_citizen("cit_hauler_01", "Hauler One", "hauler", Vector2i(15, 15), null, jm, null)

	cit.carrying_resource = EconomyConfigScript.RES_WOOD
	cit.carrying_amount = 10

	var job := jm.create_job("hauler", Vector2i(15, 15), "Haul", "town_hall", 1.0, 1, false)
	cit.active_job = job
	cit.current_state = CitizenControllerScript.State.HAULING

	# Deposit cargo
	cit._deposit_hauler_cargo()

	var xp := cit.get_skill_data().get_xp("hauling")
	var ok := (xp == 10.0 and cit.carrying_amount == 0)
	_record("TC-SKL-10", ok, "Successful cargo delivery awards exactly +10 XP to the delivering hauler")

func _test_tc_skl_11_failed_hauling_no_xp() -> void:
	var jm := JobManagerScript.new()
	var cit := CitizenControllerScript.new()
	cit.init_citizen("cit_hauler_02", "Hauler Empty", "hauler", Vector2i(15, 15), null, jm, null)

	cit.carrying_resource = ""
	cit.carrying_amount = 0 # Empty cargo

	var job := jm.create_job("hauler", Vector2i(15, 15), "Haul", "town_hall", 1.0, 1, false)
	cit.active_job = job
	cit.current_state = CitizenControllerScript.State.HAULING

	# Attempt deposit with 0 cargo
	cit._deposit_hauler_cargo()

	var xp := cit.get_skill_data().get_xp("hauling")
	var ok := (xp == 0.0)
	_record("TC-SKL-11", ok, "Deposit attempt with zero cargo awards zero hauling XP")

func _test_tc_skl_12_non_work_states_zero_xp() -> void:
	var cit := CitizenControllerScript.new()
	cit.init_citizen("cit_idle", "Idle Citizen", "idle", Vector2i(10, 10), null, null, null)

	# Simulate idle ticks, hunger tick, eating, resting
	cit.hunger = 80.0
	cit.fatigue = 90.0
	cit._process_idle()
	cit._on_hour_passed(12, 1)

	var ok := true
	for voc in CitizenSkillDataScript.VOCATIONS:
		if cit.get_skill_data().get_xp(voc) != 0.0:
			ok = false
			break
	_record("TC-SKL-12", ok, "Idle, eating, resting and wandering states award exactly zero XP")

func _test_tc_skl_13_repeated_callbacks_idempotency() -> void:
	var jm := JobManagerScript.new()
	var cit := CitizenControllerScript.new()
	cit.init_citizen("cit_idempotent", "Idempotent Hauler", "hauler", Vector2i(10, 10), null, jm, null)

	cit.carrying_resource = EconomyConfigScript.RES_WOOD
	cit.carrying_amount = 10
	var job := jm.create_job("hauler", Vector2i(10, 10), "Haul", "town_hall", 1.0, 1, false)
	cit.active_job = job

	# First deposit
	cit._deposit_hauler_cargo()
	var xp_first := cit.get_skill_data().get_xp("hauling")

	# Second spurious deposit callback
	cit._deposit_hauler_cargo()
	var xp_second := cit.get_skill_data().get_xp("hauling")

	var ok := (xp_first == 10.0 and xp_second == 10.0)
	_record("TC-SKL-13", ok, "Repeated completion callbacks cannot award duplicate XP (strictly 10.0 XP)")

# -----------------------------------------------------------------------------
# Part 3: Gameplay Effects
# -----------------------------------------------------------------------------

func _test_tc_skl_14_worker_specific_production_efficiency() -> void:
	var jm := JobManagerScript.new()
	var wm := WorkplaceManagerScript.new()
	wm.register_workplace("wp_farm_bench", "farm", Vector2i(10, 10), Vector2i(2, 2), Vector2i(10, 10), EconomyConfigScript.RES_FOOD, 50, 5.0, 5)

	# Novice Farmer (1.00x)
	var cit_novice := CitizenControllerScript.new()
	cit_novice.init_citizen("cit_novice", "Novice Farmer", "farmer", Vector2i(10, 10), null, jm, wm)

	# Master Farmer (1.35x)
	var cit_master := CitizenControllerScript.new()
	cit_master.init_citizen("cit_master", "Master Farmer", "farmer", Vector2i(10, 10), null, jm, wm)
	cit_master.get_skill_data().add_xp("farming", 1000.0) # Level 5 Master

	# Two identical 3.0-hour recurring farming jobs
	var job_n := jm.create_job("farmer", Vector2i(10, 10), "Farm N", "wp_farm_bench", 3.0, 1, true)
	var job_m := jm.create_job("farmer", Vector2i(10, 10), "Farm M", "wp_farm_bench", 3.0, 1, true)
	job_n.state = JobManagerScript.JobState.IN_PROGRESS
	job_m.state = JobManagerScript.JobState.IN_PROGRESS
	cit_novice.active_job = job_n
	cit_master.active_job = job_m

	# Both work for 2.3 game hours
	cit_novice._process_working(2.3)
	cit_master._process_working(2.3)

	# Novice progress: 2.3 * 1.0 = 2.3 / 3.0 (Not completed, buffer still 0)
	# Master progress: 2.3 * 1.35 = 3.105 / 3.0 (Completed! Buffer has 5 food)
	var ok: bool = (wm.get_buffer_amount("wp_farm_bench") == 5)
	ok = ok and (job_n.work_hours_done < 3.0) # Novice not done
	ok = ok and (cit_master.active_job == null) # Master finished cycle
	_record("TC-SKL-14", ok, "Higher vocational skill improves only matching worker's production rate (Master finished, Novice incomplete)")

func _test_tc_skl_15_builder_construction_contribution() -> void:
	var jm := JobManagerScript.new()

	var cit_novice := CitizenControllerScript.new()
	cit_novice.init_citizen("b_novice", "Novice Builder", "builder", Vector2i(20, 20), null, jm, null)

	var cit_master := CitizenControllerScript.new()
	cit_master.init_citizen("b_master", "Master Builder", "builder", Vector2i(20, 20), null, jm, null)
	cit_master.get_skill_data().add_xp("building", 1000.0) # Level 5 Master (1.35x)

	var prog_n := [0.0]
	cit_novice.set_construction_handler(func(b_id: String, delta_hrs: float):
		prog_n[0] += delta_hrs
		return {"success": true, "completed": false, "progress": prog_n[0], "hours": 20.0}
	)

	var prog_m := [0.0]
	cit_master.set_construction_handler(func(b_id: String, delta_hrs: float):
		prog_m[0] += delta_hrs
		return {"success": true, "completed": false, "progress": prog_m[0], "hours": 20.0}
	)

	var j_n := jm.create_job("builder", Vector2i(20, 20), "B", "site_n", 20.0, 1, false)
	var j_m := jm.create_job("builder", Vector2i(20, 20), "B", "site_m", 20.0, 1, false)
	j_n.state = JobManagerScript.JobState.IN_PROGRESS
	j_m.state = JobManagerScript.JobState.IN_PROGRESS
	cit_novice.active_job = j_n
	cit_master.active_job = j_m

	# Both work 1.0 game hour
	cit_novice._process_building_work(1.0)
	cit_master._process_building_work(1.0)

	# Novice should contribute 1.0 hr, Master contributes 1.35 hrs
	var ok := is_equal_approx(prog_n[0], 1.0) and is_equal_approx(prog_m[0], 1.35)
	_record("TC-SKL-15", ok, "Skilled builder contributes 1.35x construction progress independently without compounding")

func _test_tc_skl_16_hauler_logistics_speed() -> void:
	var cit := CitizenControllerScript.new()
	cit.init_citizen("hauler_speed", "Speed Hauler", "hauler", Vector2i(10, 10), null, null, null)

	var base_speed := cit.get_effective_move_speed()
	var ok: bool = is_equal_approx(base_speed, 48.0) # Baseline Level 1

	cit.get_skill_data().add_xp("hauling", 300.0) # Level 3 (1.16x)
	var lvl3_speed := cit.get_effective_move_speed()
	ok = ok and is_equal_approx(lvl3_speed, 48.0 * 1.16)

	cit.get_skill_data().add_xp("hauling", 700.0) # Level 5 Master (1.35x)
	var max_speed := cit.get_effective_move_speed()
	ok = ok and is_equal_approx(max_speed, 48.0 * 1.35)
	_record("TC-SKL-16", ok, "Hauler skill improves worker-specific movement speed (48.0 -> 55.68 -> 64.8 px/s)")

func _test_tc_skl_17_seasons_and_workplace_modifiers() -> void:
	var jm := JobManagerScript.new()
	var wm := WorkplaceManagerScript.new()
	wm.register_workplace("wp_farm_seasonal", "farm", Vector2i(10, 10), Vector2i(2, 2), Vector2i(10, 10), EconomyConfigScript.RES_FOOD, 50, 5.0, 5)

	var cit := CitizenControllerScript.new()
	cit.init_citizen("cit_season", "Seasonal Farmer", "farmer", Vector2i(10, 10), null, jm, wm)
	cit.get_skill_data().add_xp("farming", 300.0) # Level 3 Journeyman (1.16x)

	# Verify standard seasonal farm output modifier (Winter 0.5x, Summer 1.2x) is preserved in produce_to_buffer
	var summer_prod: int = wm.produce_to_buffer("wp_farm_seasonal", 1.2)
	var winter_prod: int = wm.produce_to_buffer("wp_farm_seasonal", 0.5)

	# Summer: round(5.0 * 1.2) = 6
	# Winter: round(5.0 * 0.5) = 2 or 3
	var ok := (summer_prod == 6 and winter_prod == 3)
	_record("TC-SKL-17", ok, "Existing seasonal workplace modifiers remain conserved alongside citizen skill progression")

# -----------------------------------------------------------------------------
# Part 4: Persistence and Cross-Training
# -----------------------------------------------------------------------------

func _test_tc_skl_18_role_switching_xp_retention() -> void:
	var cit := CitizenControllerScript.new()
	cit.init_citizen("cit_cross", "Cross Trainer", "farmer", Vector2i(10, 10), null, null, null)

	# Earn 450 XP in farming (Level 3 Journeyman)
	cit.award_work_xp("farming", 450.0)
	var ok: bool = (cit.get_skill_data().get_level("farming") == 3)

	# Reassign to builder
	cit.set_role("builder")
	ok = ok and (cit.role == "builder")
	ok = ok and (cit.get_skill_data().get_xp("farming") == 450.0) # Farming XP retained
	ok = ok and (cit.get_skill_data().get_xp("building") == 0.0)  # Building starts fresh

	# Earn 150 XP in building (Level 2 Apprentice)
	cit.award_work_xp("building", 150.0)
	ok = ok and (cit.get_skill_data().get_level("building") == 2)
	ok = ok and (cit.get_skill_data().get_xp("farming") == 450.0) # Farming XP still intact!

	# Reassign back to farmer
	cit.set_role("farmer")
	ok = ok and (cit.get_skill_data().get_level("farming") == 3)
	ok = ok and (cit.get_skill_data().get_level("building") == 2)
	_record("TC-SKL-18", ok, "Role switching preserves all accumulated vocational XP across multiple careers")

func _test_tc_skl_19_save_load_roundtrip() -> void:
	var cit := CitizenControllerScript.new()
	cit.init_citizen("cit_save_test", "Saved Master", "miner", Vector2i(12, 14), null, null, null)
	cit.award_work_xp("mining", 750.0)  # Level 4 Expert
	cit.award_work_xp("smithing", 200.0) # Level 2 Apprentice

	var serialized: Dictionary = cit.serialize_skills()
	var ok: bool = (serialized.has("mining") and serialized["mining"] == 750.0)
	ok = ok and (serialized.has("smithing") and serialized["smithing"] == 200.0)

	# Restore into fresh citizen
	var restored_cit := CitizenControllerScript.new()
	restored_cit.init_citizen("cit_save_test", "Saved Master", "miner", Vector2i(12, 14), null, null, null)
	restored_cit.deserialize_skills(serialized)

	var r_data: CitizenSkillData = restored_cit.get_skill_data()
	ok = ok and (r_data.get_xp("mining") == 750.0 and r_data.get_level("mining") == 4)
	ok = ok and is_equal_approx(r_data.get_efficiency("mining"), 1.25)
	ok = ok and (r_data.get_xp("smithing") == 200.0 and r_data.get_level("smithing") == 2)
	ok = ok and is_equal_approx(r_data.get_efficiency("smithing"), 1.08)
	_record("TC-SKL-19", ok, "Save/Load serialization and deserialization roundtrip preserves exact skill XP and levels")

func _test_tc_skl_20_legacy_save_fallback() -> void:
	var restored_cit := CitizenControllerScript.new()
	restored_cit.init_citizen("cit_legacy", "Old Save Citizen", "woodcutter", Vector2i(10, 10), null, null, null)

	# Simulate legacy save where "skills" dictionary is completely absent
	restored_cit.deserialize_skills({})

	var ok := true
	for voc in CitizenSkillDataScript.VOCATIONS:
		if restored_cit.get_skill_data().get_xp(voc) != 0.0 or restored_cit.get_skill_data().get_level(voc) != 1:
			ok = false
			break
	_record("TC-SKL-20", ok, "Legacy save without 'skills' field deserializes with Level 1, 0 XP defaults without errors")

func _test_tc_skl_21_malformed_saved_xp_recovery() -> void:
	var cit := CitizenControllerScript.new()
	cit.init_citizen("cit_corrupt", "Corrupt Citizen", "smith", Vector2i(10, 10), null, null, null)

	# Malformed serialized payload
	cit.deserialize_skills({
		"smithing": {"xp": -500.0},
		"mining": {"xp": 9999999.0},
		"building": "garbage_string"
	})

	var s_data: CitizenSkillData = cit.get_skill_data()
	var ok: bool = (s_data.get_xp("smithing") == 0.0 and s_data.get_efficiency("smithing") == 1.00)
	ok = ok and (s_data.get_xp("mining") == 1000.0 and s_data.get_efficiency("mining") == 1.35)
	ok = ok and (s_data.get_xp("building") == 0.0 and s_data.get_efficiency("building") == 1.00)
	_record("TC-SKL-21", ok, "Malformed or tampered saved XP cannot produce negative or overflowing multipliers")

func _test_tc_skl_22_citizen_inspector_ui_reflection() -> void:
	var hud_scene: PackedScene = load("res://scenes/ui/hud.tscn")
	var hud: CanvasLayer = hud_scene.instantiate()
	root.add_child(hud)

	var cit := CitizenControllerScript.new()
	cit.init_citizen("cit_ui_test", "UI Master", "farmer", Vector2i(32, 32), null, null, null)
	cit.award_work_xp("farming", 340.0) # Level 3 Journeyman, XP 340/600, +16%

	hud.show_citizen_inspector(cit)

	var name_lbl: Label = hud.get_node("CitizenInspectPanel/MarginContainer/VBoxContainer/SkillContainer/SkillNameLabel")
	var bonus_lbl: Label = hud.get_node("CitizenInspectPanel/MarginContainer/VBoxContainer/SkillContainer/SkillBonusLabel")
	var prog_bar: ProgressBar = hud.get_node("CitizenInspectPanel/MarginContainer/VBoxContainer/SkillContainer/SkillProgressBar")

	var ok := (name_lbl != null and bonus_lbl != null and prog_bar != null)
	if ok:
		ok = ok and name_lbl.text.contains("Nông nghiệp") and name_lbl.text.contains("Cấp 3")
		ok = ok and bonus_lbl.text.contains("340") and bonus_lbl.text.contains("600") and bonus_lbl.text.contains("+16%")
		ok = ok and (prog_bar.value == 340.0)

	# Test Level 5 Max state
	cit.award_work_xp("farming", 700.0) # Max 1000 XP (Level 5)
	hud._refresh_inspected_citizen()
	if ok:
		ok = ok and name_lbl.text.contains("Cấp 5") and name_lbl.text.contains("Tối đa")
		ok = ok and bonus_lbl.text.contains("+35%") and bonus_lbl.text.contains("1000")

	hud.queue_free()
	cit.queue_free()
	_record("TC-SKL-22", ok, "Citizen Inspector displays correct vocational name, level badge, XP progress and efficiency bonus")

# -----------------------------------------------------------------------------
# Part 5: Critical Invariants and Edge-Case Hardening
# -----------------------------------------------------------------------------

func _test_tc_skl_23_partial_production_zero_xp() -> void:
	var jm := JobManagerScript.new()
	var wm := WorkplaceManagerScript.new()
	# Farm with capacity 50, cycle output 5
	wm.register_workplace("wp_farm_partial", "farm", Vector2i(10, 10), Vector2i(2, 2), Vector2i(10, 10), EconomyConfigScript.RES_FOOD, 50, 5.0, 5)
	# Set buffer to 48 so only 2 units can be stored (less than full cycle of 5)
	wm.get_workplace("wp_farm_partial").buffer_amount = 48

	var cit := CitizenControllerScript.new()
	cit.init_citizen("cit_farm_part", "Farmer Partial", "farmer", Vector2i(10, 10), null, jm, wm)

	var job := jm.create_job("farmer", Vector2i(10, 10), "Harvest", "wp_farm_partial", 1.0, 1, true)
	job.state = JobManagerScript.JobState.IN_PROGRESS
	job.worker_id = cit.citizen_id
	cit.active_job = job
	cit.current_state = CitizenControllerScript.State.WORKING

	# Advance 1.0 hour to complete the job
	cit._process_working(1.0)

	var xp := cit.get_skill_data().get_xp("farming")
	var buf := wm.get_buffer_amount("wp_farm_partial")
	# Buffer received 2 (now 50/50), but worker must receive ZERO XP because cycle was partial
	var ok := (xp == 0.0 and buf == 50)

	# Now empty buffer and run a full cycle -> should earn full +10.0 XP
	wm.get_workplace("wp_farm_partial").buffer_amount = 0
	var job_full := jm.create_job("farmer", Vector2i(10, 10), "Harvest Full", "wp_farm_partial", 1.0, 1, true)
	job_full.state = JobManagerScript.JobState.IN_PROGRESS
	job_full.worker_id = cit.citizen_id
	cit.active_job = job_full
	cit.current_state = CitizenControllerScript.State.WORKING
	cit._process_working(1.0)

	var xp_after := cit.get_skill_data().get_xp("farming")
	ok = ok and (xp_after == 10.0 and wm.get_buffer_amount("wp_farm_partial") == 5)

	# Now buffer is full (fill to 50) -> next attempt earns zero XP
	wm.get_workplace("wp_farm_partial").buffer_amount = 50
	var job_blocked := jm.create_job("farmer", Vector2i(10, 10), "Harvest Blocked", "wp_farm_partial", 1.0, 1, true)
	job_blocked.state = JobManagerScript.JobState.IN_PROGRESS
	job_blocked.worker_id = cit.citizen_id
	cit.active_job = job_blocked
	cit.current_state = CitizenControllerScript.State.WORKING
	cit._process_working(1.0)

	var xp_blocked := cit.get_skill_data().get_xp("farming")
	ok = ok and (xp_blocked == 10.0)

	cit.queue_free()
	_record("TC-SKL-23", ok, "Partial production output grants zero XP; full cycle grants +10 XP; full buffer grants 0 XP")

func _test_tc_skl_24_builder_completion_overrun_bounded_xp() -> void:
	var jm := JobManagerScript.new()
	var cit := CitizenControllerScript.new()
	cit.init_citizen("cit_expert_builder", "Expert Builder", "builder", Vector2i(20, 20), null, jm, null)
	# Set to Level 4 Expert (600 XP, 1.25x efficiency multiplier)
	cit.get_skill_data().set_xp("building", 600.0)
	var mult: float = cit.get_skill_efficiency("building") # 1.25

	var job := jm.create_job("builder", Vector2i(20, 20), "Finish site", "bld_finishing", 12.0, 1, false)
	job.state = JobManagerScript.JobState.IN_PROGRESS
	job.worker_id = cit.citizen_id
	cit.active_job = job
	cit.current_state = CitizenControllerScript.State.WORKING

	# Site has 11.9 out of 12.0 progress (only 0.1 remaining)
	var current_prog: float = 11.9
	cit.set_construction_handler(func(b_id: String, delta_hrs: float):
		var p_add: float = minf(delta_hrs, 12.0 - current_prog)
		current_prog += p_add
		return {
			"success": true,
			"completed": current_prog >= (12.0 - 0.001),
			"progress": current_prog,
			"hours": 12.0,
			"progress_delta": p_add
		}
	)

	# Simulation tick passes delta_hours = 1.0 (with 1.25x mult, effective delta = 1.25)
	# But site only accepts 0.1 progress!
	# Actual labor hours contributed = 0.1 / 1.25 = 0.08 hours.
	# Expected XP = 0.08 * 5.0 = 0.40 XP, NOT 5.0 XP!
	cit._process_building_work(1.0)

	var xp_earned: float = cit.get_skill_data().get_xp("building") - 600.0
	var expected_labor_hours: float = 0.1 / mult
	var expected_xp: float = expected_labor_hours * 5.0

	var ok := is_equal_approx(xp_earned, expected_xp) and not is_equal_approx(xp_earned, 5.0)
	cit.queue_free()
	_record("TC-SKL-24", ok, "Construction completion overrun bounds builder XP to actual labor accepted (%.3f XP, not 5.0 XP)" % xp_earned)

func _test_tc_skl_25_hauler_partial_deposit_cargo_preservation() -> void:
	var jm := JobManagerScript.new()
	var cit := CitizenControllerScript.new()
	cit.init_citizen("cit_hauler_part", "Hauler Partial", "hauler", Vector2i(15, 15), null, jm, null)
	cit.carrying_resource = EconomyConfigScript.RES_WOOD
	cit.carrying_amount = 10

	var job := jm.create_job("hauler", Vector2i(15, 15), "Haul", "town_hall", 1.0, 1, false)
	cit.active_job = job
	cit.current_state = CitizenControllerScript.State.HAULING

	# Mock ResourceManager with capacity capped so only 4 items can fit
	var rm := MockTestResourceManager.new()
	rm.capacities[EconomyConfigScript.RES_WOOD] = 500
	rm.stock[EconomyConfigScript.RES_WOOD] = 496 # Space available = 4

	# Add Mock ResourceManager to root and set as custom rm so cit can find it
	rm.name = "ResourceManager"
	root.add_child(rm)
	cit.set_custom_resource_manager(rm)

	# First deposit attempt: 4 stored, 6 remaining in citizen backpack
	cit._deposit_hauler_cargo()

	var stock_after_1: int = rm.get_available_stock(EconomyConfigScript.RES_WOOD)
	var carrying_after_1: int = cit.carrying_amount
	var xp_after_1: float = cit.get_skill_data().get_xp("hauling")

	# Check: 4 stored, 6 preserved in citizen inventory, zero XP awarded
	var ok: bool = (stock_after_1 == 500 and carrying_after_1 == 6 and xp_after_1 == 0.0)

	# Second attempt with storage still full -> 0 stored, 6 preserved, 0 XP
	cit.active_job = job
	cit._deposit_hauler_cargo()
	ok = ok and (rm.get_available_stock(EconomyConfigScript.RES_WOOD) == 500 and cit.carrying_amount == 6 and cit.get_skill_data().get_xp("hauling") == 0.0)

	# Now storage capacity is increased (e.g. warehouse built)
	rm.capacities[EconomyConfigScript.RES_WOOD] = 600
	cit.active_job = job
	cit._deposit_hauler_cargo()

	var stock_after_final: int = rm.get_available_stock(EconomyConfigScript.RES_WOOD)
	var carrying_after_final: int = cit.carrying_amount
	var xp_after_final: float = cit.get_skill_data().get_xp("hauling")

	# Check: 500 + 6 = 506 stored (exactly 10 total deposited), citizen empty, +10 XP awarded
	ok = ok and (stock_after_final == 506 and carrying_after_final == 0 and xp_after_final == 10.0)

	root.remove_child(rm)
	rm.free()
	cit.queue_free()
	_record("TC-SKL-25", ok, "Partial cargo deposit preserves undelivered goods in inventory, prevents item loss/duplication, and awards XP only on full batch delivery")

func _test_tc_skl_26_multiple_builders_skill_pro_rated_completion() -> void:
	var jm := JobManagerScript.new()
	var cit_a := CitizenControllerScript.new() # Level 1 (mult = 1.0)
	var cit_b := CitizenControllerScript.new() # Level 4 (mult = 1.25)
	cit_a.init_citizen("builder_a_comp", "Builder A", "builder", Vector2i(20, 20), null, jm, null)
	cit_b.init_citizen("builder_b_comp", "Builder B", "builder", Vector2i(21, 20), null, jm, null)
	cit_b.get_skill_data().set_xp("building", 600.0) # Level 4 Expert (1.25x mult)

	var site_tracker := [19.0] # 1.0 hour remaining to reach 20.0
	var handler := func(b_id: String, delta_hrs: float):
		var p_add: float = minf(delta_hrs, 20.0 - site_tracker[0])
		site_tracker[0] += p_add
		return {
			"success": true,
			"completed": site_tracker[0] >= (20.0 - 0.001),
			"progress": site_tracker[0],
			"hours": 20.0,
			"progress_delta": p_add
		}

	cit_a.set_construction_handler(handler)
	cit_b.set_construction_handler(handler)

	var job_a := jm.create_job("builder", Vector2i(20, 20), "Build", "site_shared", 20.0, 1, false)
	var job_b := jm.create_job("builder", Vector2i(21, 20), "Build", "site_shared", 20.0, 1, false)
	job_a.state = JobManagerScript.JobState.IN_PROGRESS
	job_b.state = JobManagerScript.JobState.IN_PROGRESS
	cit_a.active_job = job_a
	cit_b.active_job = job_b

	# Builder A works 0.5 hours (1.0 mult) -> 0.5 progress accepted, earns 0.5 * 5.0 = 2.5 XP
	cit_a._process_building_work(0.5)

	# Now 0.5 progress remaining to reach 20.0.
	# Builder B works 1.0 hours (1.25 mult).
	# Builder B only needs 0.5 / 1.25 = 0.40 hours to complete the site!
	# Builder B earns (0.5 / 1.25) * 5.0 = 2.0 XP, NOT 5.0 XP!
	cit_b._process_building_work(1.0)

	var xp_a: float = cit_a.get_skill_data().get_xp("building")
	var xp_b: float = cit_b.get_skill_data().get_xp("building") - 600.0
	var expected_b_xp: float = (0.5 / 1.25) * 5.0

	var ok := is_equal_approx(xp_a, 2.5) and is_equal_approx(xp_b, expected_b_xp) and is_equal_approx(site_tracker[0], 20.0)

	cit_a.queue_free()
	cit_b.queue_free()
	_record("TC-SKL-26", ok, "Multiple builders with different skill multipliers receive exact pro-rated XP on shared site completion")

func _test_tc_skl_27_completed_or_cancelled_building_zero_xp() -> void:
	var jm := JobManagerScript.new()
	var cit := CitizenControllerScript.new()
	cit.init_citizen("cit_idle_builder", "Idle Builder", "builder", Vector2i(20, 20), null, jm, null)

	var job := jm.create_job("builder", Vector2i(20, 20), "Build", "site_done", 20.0, 1, false)
	job.state = JobManagerScript.JobState.IN_PROGRESS
	cit.active_job = job

	# Building already completed or cancelled: handler returns success: false
	cit.set_construction_handler(func(b_id: String, delta_hrs: float):
		return {"success": false, "completed": false, "progress": 0.0, "hours": 0.0, "progress_delta": 0.0}
	)

	cit._process_building_work(1.0)

	var xp: float = cit.get_skill_data().get_xp("building")
	var ok := (xp == 0.0)

	cit.queue_free()
	_record("TC-SKL-27", ok, "Completed, cancelled or failed construction work awards strictly zero XP")

# -----------------------------------------------------------------------------
# Summary and Cleanup
# -----------------------------------------------------------------------------

func _print_summary() -> void:
	print("\n========================================================")
	print("  PACKAGE 2B TEST RESULTS SUMMARY")
	print("========================================================")
	var passed_count := 0
	for r in test_results:
		if r["passed"]:
			passed_count += 1
	print("  Total tests executed: %d" % test_results.size())
	print("  Tests passed:         %d" % passed_count)
	print("  Tests failed:         %d" % (test_results.size() - passed_count))
	if all_passed:
		print("  STATUS: ALL PACKAGE 2B TESTS PASSED (100% PASS RATE)")
	else:
		printerr("  STATUS: ONE OR MORE TESTS FAILED")
	print("========================================================\n")

func _cleanup() -> void:
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(TEST_SAVE_PATH)
	if FileAccess.file_exists(TEST_SAVE_PATH + ".bak"):
		DirAccess.remove_absolute(TEST_SAVE_PATH + ".bak")
	if FileAccess.file_exists(TEST_SAVE_PATH + ".tmp"):
		DirAccess.remove_absolute(TEST_SAVE_PATH + ".tmp")
