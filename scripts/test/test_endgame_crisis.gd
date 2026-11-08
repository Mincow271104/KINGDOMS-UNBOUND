class_name TestEndgameCrisis
extends SceneTree
## Comprehensive automated test suite for Package 4A: Endgame Crisis Scenarios & Settlement Resilience.
## Tests CrisisManager lifecycle, Drought, Blizzard, Bandit Horde, VictoryManager integration, and Save/Load persistence.

const CrisisManagerScript = preload("res://scripts/core/crisis_manager.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")

var _total_assertions: int = 0
var _passed_assertions: int = 0
var _failed_assertions: int = 0

func _init() -> void:
	print("\n=== STARTING PACKAGE 4A: ENDGAME CRISIS TEST SUITE ===")
	run_all_tests()
	print("\n=== TEST RESULTS ===")
	print("Total Assertions: %d" % _total_assertions)
	print("Passed: %d" % _passed_assertions)
	print("Failed: %d" % _failed_assertions)
	if _failed_assertions == 0:
		print("STATUS: ALL TESTS PASSED SUCCESSFULLY!")
		quit(0)
	else:
		print("STATUS: TEST FAILURES DETECTED!")
		quit(1)

func assert_true(condition: bool, message: String) -> void:
	_total_assertions += 1
	if condition:
		_passed_assertions += 1
	else:
		_failed_assertions += 1
		printerr("  [FAIL] %s" % message)

func assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	_total_assertions += 1
	if actual == expected:
		_passed_assertions += 1
	else:
		_failed_assertions += 1
		printerr("  [FAIL] %s: Expected '%s', got '%s'" % [message, str(expected), str(actual)])

func assert_almost_eq(actual: float, expected: float, tolerance: float, message: String) -> void:
	_total_assertions += 1
	if absf(actual - expected) <= tolerance:
		_passed_assertions += 1
	else:
		_failed_assertions += 1
		printerr("  [FAIL] %s: Expected ~%f (+/-%f), got %f" % [message, expected, tolerance, actual])

# Mock Resource Manager for standalone testing
class MockResourceManager:
	var stock: Dictionary = {"food": 200, "wood": 100, "gold": 500}
	func get_available_stock(res_id: String) -> int:
		return stock.get(res_id, 0)
	func consume_resource(res_id: String, amount: int) -> bool:
		if get_available_stock(res_id) < amount:
			return false
		stock[res_id] -= amount
		return true

# Mock Citizen for testing
class MockCitizen:
	var citizen_id: String = "cit_1"
	var health: float = 100.0
	var morale: float = 75.0
	var fatigue: float = 10.0
	var hunger: float = 20.0
	var current_state: int = 1 # State.WORKING
	var death_reason: String = ""
	var death_cause: String = ""
	func is_alive() -> bool:
		return health > 0.0
	func die(reason: String, cause: String = "") -> void:
		health = 0.0
		death_reason = reason
		death_cause = cause

# Mock Player Army Manager for testing garrison and army interactions
class MockPlayerArmyManager:
	var soldier_count: int = 4
	var garrisons: Dictionary = {}
	func get_garrison_count(outpost_id: String) -> int:
		if not garrisons.has(outpost_id):
			return 0
		return garrisons[outpost_id].get("soldiers", []).size()
	func apply_outpost_casualties(outpost_id: String, count: int) -> int:
		if not garrisons.has(outpost_id):
			return 0
		var s_list: Array = garrisons[outpost_id].get("soldiers", [])
		var removed: int = mini(count, s_list.size())
		for i in range(removed):
			s_list.pop_back()
		return removed
	func remove_casualties(count: int, _from_field: bool = false) -> int:
		var removed: int = mini(count, soldier_count)
		soldier_count -= removed
		return removed

func run_all_tests() -> void:
	test_initial_state()
	test_warning_and_lifecycle_transitions()
	test_cooldown_and_no_overlapping()
	test_drought_scenario_consequences_and_recovery()
	test_blizzard_scenario_wood_and_hypothermia()
	test_blizzard_seasonal_eligibility()
	test_bandit_horde_outpost_garrison_interception()
	test_bandit_horde_breach_consequences()
	test_victory_manager_crisis_invalidation()
	test_save_load_serialization_roundtrip()
	test_legacy_save_compatibility()
	test_deterministic_seeded_outcomes()
	test_bounded_plunder_and_resource_safety()
	test_multi_outpost_casualty_distribution()

func test_initial_state() -> void:
	print("Running test_initial_state...")
	var cm = CrisisManagerScript.new(12345)
	assert_eq(cm.current_crisis_type, CrisisManagerScript.CRISIS_NONE, "Initial crisis type should be NONE")
	assert_eq(cm.current_stage, CrisisManagerScript.STAGE_INACTIVE, "Initial stage should be INACTIVE")
	assert_false(cm.is_crisis_active(), "Crisis should not be active initially")
	assert_false(cm.is_in_warning(), "Should not be in warning initially")
	assert_false(cm.is_in_recovery(), "Should not be in recovery initially")
	assert_eq(cm.get_farm_production_multiplier(), 1.0, "Farm multiplier should be 1.0 initially")
	assert_eq(cm.get_citizen_fatigue_multiplier(), 1.0, "Fatigue multiplier should be 1.0 initially")
	assert_false(cm.is_hypothermia_active(), "Hypothermia should not be active initially")

func test_warning_and_lifecycle_transitions() -> void:
	print("Running test_warning_and_lifecycle_transitions...")
	var cm = CrisisManagerScript.new(55555)
	var trig_res := cm.trigger_crisis(CrisisManagerScript.CRISIS_DROUGHT, false, 72.0)
	assert_true(trig_res.get("success", false), "Crisis trigger should succeed")
	assert_eq(cm.current_stage, CrisisManagerScript.STAGE_WARNING, "Stage should be WARNING")
	assert_true(cm.is_in_warning(), "is_in_warning should return true")
	assert_false(cm.is_crisis_active(), "is_crisis_active should be false during warning")
	assert_eq(cm.warning_hours_remaining, 24.0, "Warning duration should start at 24 hours")

	# Warning data complies with GDD §12.2
	var wdata := cm.get_warning_data_for(CrisisManagerScript.CRISIS_DROUGHT)
	assert_true(wdata.has("title"), "Warning data must contain title")
	assert_true(wdata.has("cause"), "Warning data must contain cause")
	assert_true(wdata.has("severity"), "Warning data must contain severity")
	assert_true(wdata.has("projected_consequences"), "Warning data must contain projected consequences")
	assert_true(wdata.has("recommended_action"), "Warning data must contain recommended actions")

	# Tick 23 hours: still in warning
	for h in range(23):
		cm.tick_hourly(h, 1, "summer")
	assert_eq(cm.current_stage, CrisisManagerScript.STAGE_WARNING, "Should remain in WARNING after 23 hours")
	assert_almost_eq(cm.warning_hours_remaining, 1.0, 0.01, "Warning should have 1 hour remaining")

	# Tick 24th hour: transitions to ACTIVE
	cm.tick_hourly(23, 1, "summer")
	assert_eq(cm.current_stage, CrisisManagerScript.STAGE_ACTIVE, "Should transition to ACTIVE at hour 24")
	assert_true(cm.is_crisis_active(), "is_crisis_active should be true")
	assert_false(cm.is_in_warning(), "is_in_warning should be false")
	assert_almost_eq(cm.active_hours_remaining, 72.0, 0.01, "Active hours should be 72.0")

	# Tick 72 hours: transitions to RECOVERY
	for h in range(72):
		cm.tick_hourly(h % 24, 2 + (h / 24), "summer")
	assert_eq(cm.current_stage, CrisisManagerScript.STAGE_RECOVERY, "Should transition to RECOVERY after active duration")
	assert_true(cm.is_in_recovery(), "is_in_recovery should be true")
	assert_false(cm.is_crisis_active(), "is_crisis_active should be false during recovery")
	assert_eq(cm.total_crises_survived, 1, "Crises survived count should increment")

	# Tick 24 recovery hours: transitions to INACTIVE with cooldown
	for h in range(24):
		cm.tick_hourly(h % 24, 5 + (h / 24), "summer")
	assert_eq(cm.current_stage, CrisisManagerScript.STAGE_INACTIVE, "Should return to INACTIVE after recovery")
	assert_eq(cm.current_crisis_type, CrisisManagerScript.CRISIS_NONE, "Crisis type should reset to NONE")
	assert_almost_eq(cm.cooldown_hours_remaining, CrisisManagerScript.DEFAULT_COOLDOWN_HOURS, 0.01, "Cooldown should be set")

func test_cooldown_and_no_overlapping() -> void:
	print("Running test_cooldown_and_no_overlapping...")
	var cm = CrisisManagerScript.new(12345)
	cm.trigger_crisis(CrisisManagerScript.CRISIS_DROUGHT, true, 48.0)
	assert_true(cm.is_crisis_active(), "Drought should be active")

	# Cannot start overlapping crisis
	var second_trig := cm.trigger_crisis(CrisisManagerScript.CRISIS_BLIZZARD)
	assert_false(second_trig.get("success", false), "Cannot trigger second crisis while one is active")

	# Fast forward through active + recovery
	for h in range(72):
		cm.tick_hourly(h % 24, 1 + (h / 24), "summer")
	assert_eq(cm.current_stage, CrisisManagerScript.STAGE_INACTIVE, "Should be INACTIVE now")
	assert_true(cm.cooldown_hours_remaining > 0.0, "Cooldown should be active")

	# Daily process should not trigger during cooldown
	var day_eval := cm.process_day(10, "summer", 1, null, null, 20, 500)
	assert_eq(day_eval.get("action"), "in_cooldown", "Should refuse trigger during cooldown")

func test_drought_scenario_consequences_and_recovery() -> void:
	print("Running test_drought_scenario_consequences_and_recovery...")
	var cm = CrisisManagerScript.new(777)
	cm.trigger_crisis(CrisisManagerScript.CRISIS_DROUGHT, true, 72.0)

	# Production modifier during drought: 0.40
	assert_almost_eq(cm.get_farm_production_multiplier(), 0.40, 0.001, "Drought farm multiplier should be 0.40 (60% penalty)")

	# Thirst / fatigue stress on working citizens
	var cit := MockCitizen.new()
	cit.fatigue = 20.0
	cit.current_state = 1 # WORKING
	var citizen_list: Array = [cit]

	cm.tick_hourly(10, 1, "summer", null, null, citizen_list)
	assert_almost_eq(cit.fatigue, 20.5, 0.01, "Working citizen should suffer thirst fatigue in drought")

	# Fast forward 71 hours -> transitions to RECOVERY
	for h in range(71):
		cm.tick_hourly(h % 24, 1 + (h / 24), "summer")
	assert_eq(cm.current_stage, CrisisManagerScript.STAGE_RECOVERY, "Should enter recovery")

	# During drought recovery: soil revitalized (+10% / 1.10)
	assert_almost_eq(cm.get_farm_production_multiplier(), 1.10, 0.001, "Recovery farm multiplier should be 1.10")

	# Complete recovery
	for h in range(24):
		cm.tick_hourly(h % 24, 4 + (h / 24), "summer")
	assert_almost_eq(cm.get_farm_production_multiplier(), 1.0, 0.001, "Farm multiplier should return to 1.0 after recovery")

func test_blizzard_scenario_wood_and_hypothermia() -> void:
	print("Running test_blizzard_scenario_wood_and_hypothermia...")
	var cm = CrisisManagerScript.new(888)
	cm.trigger_crisis(CrisisManagerScript.CRISIS_BLIZZARD, true, 48.0)

	# Frozen farm output & fatigue multiplier
	assert_almost_eq(cm.get_farm_production_multiplier(), 0.0, 0.001, "Blizzard farm multiplier must be 0.0 (frozen agriculture)")
	assert_almost_eq(cm.get_citizen_fatigue_multiplier(), 1.50, 0.001, "Blizzard fatigue multiplier must be 1.50 (+50% cold fatigue)")

	var rm := MockResourceManager.new()
	rm.stock["wood"] = 4 # Enough for 2 hours of heating (2 wood/hr)
	var cit := MockCitizen.new()
	cit.health = 100.0
	var citizen_list: Array = [cit]

	# Hour 1: Wood consumed, no hypothermia
	cm.tick_hourly(1, 31, "winter", null, rm, citizen_list)
	assert_eq(rm.stock["wood"], 2, "2 wood should be consumed for heating")
	assert_false(cm.is_hypothermia_active(), "Hypothermia should not trigger while wood is available")
	assert_eq(cit.health, 100.0, "Citizen health should remain full with heating")

	# Hour 2: Remaining 2 wood consumed
	cm.tick_hourly(2, 31, "winter", null, rm, citizen_list)
	assert_eq(rm.stock["wood"], 0, "Wood should reach 0")
	assert_false(cm.is_hypothermia_active(), "Hypothermia not active during hour 2")

	# Hour 3: Wood exhausted! Hypothermia triggers
	cm.tick_hourly(3, 31, "winter", null, rm, citizen_list)
	assert_true(cm.is_hypothermia_active(), "Hypothermia should activate when wood is exhausted")
	assert_almost_eq(cit.health, 99.0, 0.01, "Citizen health should decrease by 1.0 from freezing cold")

	# Reduce citizen health to 1.0 and tick -> causes hypothermia death
	cit.health = 1.0
	cm.tick_hourly(4, 31, "winter", null, rm, citizen_list)
	assert_eq(cit.health, 0.0, "Citizen health should reach 0")
	assert_eq(cit.death_cause, "hypothermia_or_cold", "Citizen death cause should be hypothermia_or_cold")

func test_blizzard_seasonal_eligibility() -> void:
	print("Running test_blizzard_seasonal_eligibility...")
	var cm = CrisisManagerScript.new(999)
	# Spring (index 0) or Summer (index 1) cannot trigger Blizzard naturally
	var res_summer := cm.process_day(5, "summer", 1, null, null, 20, 500)
	if res_summer.get("success"):
		assert_eq(cm.current_crisis_type, CrisisManagerScript.CRISIS_DROUGHT, "Summer should trigger Drought, not Blizzard")
		cm.trigger_crisis(CrisisManagerScript.CRISIS_DROUGHT, true, 1.0) # Reset

func test_bandit_horde_outpost_garrison_interception() -> void:
	print("Running test_bandit_horde_outpost_garrison_interception...")
	var cm = CrisisManagerScript.new(12345)
	var rm := MockResourceManager.new()
	rm.stock["food"] = 300
	rm.stock["gold"] = 500

	var army_mgr := MockPlayerArmyManager.new()
	# Station 6 soldiers across 2 outposts (each soldier stops up to 2 bandits = 12 bandits max)
	army_mgr.garrisons["outpost_north"] = {"soldiers": [{}, {}, {}]}
	army_mgr.garrisons["outpost_south"] = {"soldiers": [{}, {}, {}]}

	var cit := MockCitizen.new()
	cit.morale = 80.0
	var citizen_list: Array = [cit]

	var raid_summary := cm.resolve_bandit_raid(null, rm, citizen_list, army_mgr, null)
	assert_true(raid_summary.get("intercepted_completely", false), "Sufficient garrisons should completely intercept bandit horde")
	assert_eq(raid_summary.get("breached_bandits", -1), 0, "No bandits should breach settlement defenses")
	assert_eq(raid_summary.get("plundered_food", -1), 0, "Zero food should be plundered")
	assert_eq(raid_summary.get("plundered_gold", -1), 0, "Zero gold should be plundered")
	assert_eq(cit.morale, 80.0, "Citizen morale should not drop when raid is intercepted at borders")
	assert_true(raid_summary.get("garrison_intercepted", 0) > 0, "Outposts should intercept bandits")

func test_bandit_horde_breach_consequences() -> void:
	print("Running test_bandit_horde_breach_consequences...")
	var cm = CrisisManagerScript.new(12345)
	var rm := MockResourceManager.new()
	rm.stock["food"] = 200
	rm.stock["gold"] = 400

	var army_mgr := MockPlayerArmyManager.new()
	army_mgr.soldier_count = 0 # No army
	army_mgr.garrisons = {}    # No outposts

	var cit := MockCitizen.new()
	cit.morale = 70.0
	var citizen_list: Array = [cit]

	var world_data = WorldGenerator.WorldData.new()
	var test_b: Dictionary = {
		"id": "farm_1",
		"type": "farm",
		"health": 100,
		"max_health": 100,
		"state": "active",
		"level": 1
	}
	world_data.buildings.clear()
	world_data.buildings.append(test_b)

	var raid_summary := cm.resolve_bandit_raid(world_data, rm, citizen_list, army_mgr, null)
	assert_false(raid_summary.get("intercepted_completely", true), "Undefended settlement should suffer breach")
	assert_true(raid_summary.get("breached_bandits", 0) > 0, "Bandits should breach settlement")
	assert_true(raid_summary.get("plundered_food", 0) > 0, "Food should be plundered")
	assert_true(raid_summary.get("plundered_gold", 0) > 0, "Gold should be plundered")
	assert_almost_eq(cit.morale, 60.0, 0.01, "Citizen morale should drop by 10 from raid")
	assert_true(BuildingSystemScript.is_building_damaged(test_b), "Building should be recognized as damaged by BuildingSystem")
	assert_almost_eq(float(test_b.get("health")), 75.0, 0.01, "Building should take 25 structural damage")

func test_victory_manager_crisis_invalidation() -> void:
	print("Running test_victory_manager_crisis_invalidation...")
	var vm := VictoryManager.new()
	# Setup valid prosperity conditions (pop 30, food 500, gold 1000, stability 80, morale 75, techs 3)
	var check_peace := vm.evaluate_prosperity_conditions(30, 500, 1000, 85.0, 80.0, 3, false, "")
	assert_true(check_peace.get("all_met", false), "Prosperity conditions should be met in peacetime")

	# With active crisis: prosperity conditions MUST fail per GDD §12.3
	var check_crisis := vm.evaluate_prosperity_conditions(30, 500, 1000, 85.0, 80.0, 3, true, "Hạn Hán Khắc Nghiệt")
	assert_false(check_crisis.get("all_met", true), "Active crisis must invalidate prosperity victory hold")
	var failed: Array = check_crisis.get("failed", [])
	assert_true(failed.has("Không có khủng hoảng nghiêm trọng"), "Failure reason must cite active crisis")

	# Continuous hold reset check in tick_hourly
	vm.hold_hours_elapsed = 48.0
	var res := vm.tick_hourly(30, 500, 1000, 85.0, 80.0, 3, true, 10, true, "Bão Tuyết Băng Giá")
	assert_almost_eq(vm.hold_hours_elapsed, 0.0, 0.01, "Hold hours must reset to 0 upon crisis onset")

func test_save_load_serialization_roundtrip() -> void:
	print("Running test_save_load_serialization_roundtrip...")
	var cm := CrisisManagerScript.new(4444)
	cm.trigger_crisis(CrisisManagerScript.CRISIS_BLIZZARD, false, 48.0)
	cm.warning_hours_remaining = 14.5
	cm.total_crises_faced = 3
	cm.total_crises_survived = 2
	cm.cold_hypothermia_active = true

	var saved_dict := cm.serialize()
	assert_true(saved_dict.has("version"), "Serialized data must contain version")
	assert_eq(saved_dict.get("current_crisis_type"), CrisisManagerScript.CRISIS_BLIZZARD, "Saved crisis type mismatch")
	assert_eq(saved_dict.get("current_stage"), CrisisManagerScript.STAGE_WARNING, "Saved stage mismatch")

	var restored_cm := CrisisManagerScript.new(1111)
	restored_cm.deserialize(saved_dict)

	assert_eq(restored_cm.current_crisis_type, CrisisManagerScript.CRISIS_BLIZZARD, "Restored crisis type mismatch")
	assert_eq(restored_cm.current_stage, CrisisManagerScript.STAGE_WARNING, "Restored stage mismatch")
	assert_almost_eq(restored_cm.warning_hours_remaining, 14.5, 0.01, "Restored warning hours mismatch")
	assert_eq(restored_cm.total_crises_faced, 3, "Restored crises faced mismatch")
	assert_eq(restored_cm.total_crises_survived, 2, "Restored crises survived mismatch")
	assert_true(restored_cm.cold_hypothermia_active, "Restored hypothermia state mismatch")

func test_legacy_save_compatibility() -> void:
	print("Running test_legacy_save_compatibility...")
	var cm := CrisisManagerScript.new(12345)
	# Simulate loading empty legacy dictionary
	cm.deserialize({})
	assert_eq(cm.current_crisis_type, CrisisManagerScript.CRISIS_NONE, "Legacy save should load as CRISIS_NONE")
	assert_eq(cm.current_stage, CrisisManagerScript.STAGE_INACTIVE, "Legacy save should load as STAGE_INACTIVE")
	assert_false(cm.is_crisis_active(), "Legacy save should not be active")
	assert_false(cm.is_in_warning(), "Legacy save should not be in warning")
	assert_eq(cm.get_farm_production_multiplier(), 1.0, "Legacy save should have 1.0 farm multiplier")

func test_deterministic_seeded_outcomes() -> void:
	print("Running test_deterministic_seeded_outcomes...")
	var cm1 = CrisisManagerScript.new(98765)
	var cm2 = CrisisManagerScript.new(98765)
	
	# Evaluate identical day
	var res1 := cm1.process_day(15, "summer", 1, null, null, 20, 500)
	var res2 := cm2.process_day(15, "summer", 1, null, null, 20, 500)
	assert_eq(res1.get("action"), res2.get("action"), "Identical seeds must yield identical action")
	assert_eq(cm1.current_crisis_type, cm2.current_crisis_type, "Identical seeds must yield identical crisis type")
	assert_eq(cm1.current_stage, cm2.current_stage, "Identical seeds must yield identical stage")

func test_bounded_plunder_and_resource_safety() -> void:
	print("Running test_bounded_plunder_and_resource_safety...")
	var cm = CrisisManagerScript.new(12345)
	var rm = MockResourceManager.new()
	rm.stock["food"] = 5 # Very low stock
	rm.stock["gold"] = 10 # Very low stock

	var army_mgr := MockPlayerArmyManager.new()
	army_mgr.soldier_count = 0
	army_mgr.garrisons = {}

	var raid_summary := cm.resolve_bandit_raid(null, rm, [], army_mgr, null)
	assert_true(raid_summary.get("plundered_food", 0) <= 5, "Plundered food must not exceed current stock")
	assert_true(raid_summary.get("plundered_gold", 0) <= 10, "Plundered gold must not exceed current stock")
	assert_true(rm.stock["food"] >= 0, "Food stock must never become negative")
	assert_true(rm.stock["gold"] >= 0, "Gold stock must never become negative")

func test_multi_outpost_casualty_distribution() -> void:
	print("Running test_multi_outpost_casualty_distribution...")
	var cm = CrisisManagerScript.new(12345)
	var army_mgr := MockPlayerArmyManager.new()
	army_mgr.garrisons["outpost_1"] = {"soldiers": [{}, {}]}
	army_mgr.garrisons["outpost_2"] = {"soldiers": [{}, {}]}

	var total_initial: int = army_mgr.get_garrison_count("outpost_1") + army_mgr.get_garrison_count("outpost_2")
	var raid_summary := cm.resolve_bandit_raid(null, null, [], army_mgr, null)

	var total_remaining: int = army_mgr.get_garrison_count("outpost_1") + army_mgr.get_garrison_count("outpost_2")
	var recorded_cas: int = int(raid_summary.get("garrison_casualties", 0))
	assert_eq(total_remaining + recorded_cas, total_initial, "Total soldiers must be strictly conserved across outposts")

func assert_false(condition: bool, message: String) -> void:
	assert_true(not condition, message)
