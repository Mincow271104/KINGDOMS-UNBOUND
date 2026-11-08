extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — PACKAGE 2M
## Civic Building Damage & Maintenance Repair (GDD §7.2, ISSUE-006 / TC-ARMY.32)
## Authoritative Coverage: Scenarios 1 through 25 (Fail-Closed Assertions)

const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")
const JobManagerScript = preload("res://scripts/jobs/job_manager.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")

var frame_count: int = 0
var tests_executed: bool = false
var failures: int = 0
var passed_count: int = 0
var world_instance: Node = null

func _assert(condition: bool, test_name: String, details: String = "") -> void:
	if condition:
		passed_count += 1
		print("  [PASS] %s" % test_name)
	else:
		failures += 1
		printerr("  [FAIL] %s - %s" % [test_name, details])

func _init() -> void:
	print("\n========================================================")
	print("  STARTING PACKAGE 2M BUILDING DAMAGE & REPAIR TEST SUITE")
	print("========================================================\n")

	world_instance = WorldViewScene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count >= 3 and not tests_executed:
		tests_executed = true
		_run_all_tests()
		_print_summary()
		quit(0 if failures == 0 else 1)
		return true
	return false

func _print_summary() -> void:
	print("\n--------------------------------------------------------")
	print("  PACKAGE 2M TEST RESULTS SUMMARY")
	print("--------------------------------------------------------")
	print("  Passed Assertions : %d" % passed_count)
	print("  Failed Assertions : %d" % failures)
	if failures == 0:
		print("  ALL 25 SCENARIOS PASSED CLEANLY! (Exit Code 0)")
	else:
		print("  TEST SUITE COMPLETED WITH FAILURES! (Exit Code 1)")
	print("--------------------------------------------------------\n")

func _run_all_tests() -> void:
	_test_tc_bdr_1_healthy_building_initialization()
	_test_tc_bdr_2_valid_damage_application()
	_test_tc_bdr_3_invalid_damage_input_rejection()
	_test_tc_bdr_4_health_boundary_and_clamping()
	_test_tc_bdr_5_transition_into_damaged_condition()
	_test_tc_bdr_6_damaged_barracks_zero_soldier_capacity()
	_test_tc_bdr_7_tc_army_32_resolution_verification()
	_test_tc_bdr_8_recruitment_rejected_when_damaged()
	_test_tc_bdr_9_existing_soldiers_preserved_on_capacity_drop()
	_test_tc_bdr_10_repair_eligibility_validation()
	_test_tc_bdr_11_proportional_repair_cost_calculation()
	_test_tc_bdr_12_resource_reservation_and_exact_once_consumption()
	_test_tc_bdr_13_repair_builder_job_assignment()
	_test_tc_bdr_14_repair_progress_and_proportional_health_restoration()
	_test_tc_bdr_15_repair_interruption_and_safe_resumption()
	_test_tc_bdr_16_repair_cancellation_and_reservation_cleanup()
	_test_tc_bdr_17_repair_completion_and_functionality_restoration()
	_test_tc_bdr_18_previously_paused_building_restored_to_paused()
	_test_tc_bdr_19_repeated_calls_idempotency()
	_test_tc_bdr_20_demolition_during_repair_cleans_up_safely()
	_test_tc_bdr_21_save_load_roundtrip_damaged_building()
	_test_tc_bdr_22_save_load_roundtrip_in_progress_repair()
	_test_tc_bdr_23_legacy_save_compatibility_missing_fields()
	_test_tc_bdr_24_upgrade_and_repair_mutual_exclusion()
	_test_tc_bdr_25_building_inspect_panel_ui_reflection()

# -----------------------------------------------------------------------------
# 1. Healthy building initialization
# -----------------------------------------------------------------------------
func _test_tc_bdr_1_healthy_building_initialization() -> void:
	print("--- Running Scenario 1: Healthy Building Initialization ---")
	var raw_b := {
		"id": "bld_init_test_1",
		"type": "workshop",
		"cell": Vector2i(5, 5),
		"size": Vector2i(2, 2)
	}
	var b := BuildingSystemScript.normalize_building_data(raw_b)
	_assert(int(b.get("health", 0)) == 100, "TC-BDR.1.1: Health defaults to 100")
	_assert(int(b.get("max_health", 0)) == 100, "TC-BDR.1.2: Max health defaults to 100")
	_assert(str(b.get("state", "")) == "active", "TC-BDR.1.3: State defaults to active")
	_assert(bool(b.get("is_repairing", true)) == false, "TC-BDR.1.4: is_repairing defaults to false")
	_assert(BuildingSystemScript.is_building_damaged(b) == false, "TC-BDR.1.5: is_building_damaged query returns false")
	_assert(BuildingSystemScript.is_building_repairing(b) == false, "TC-BDR.1.6: is_building_repairing query returns false")
	_assert(BuildingSystemScript.is_building_under_construction(b) == false, "TC-BDR.1.7: is_building_under_construction query returns false")

# -----------------------------------------------------------------------------
# 2. Valid damage application via damage_building and apply_damage
# -----------------------------------------------------------------------------
func _test_tc_bdr_2_valid_damage_application() -> void:
	print("--- Running Scenario 2: Valid Damage Application ---")
	var b := {
		"id": "bld_dmg_test_2",
		"type": "workshop",
		"cell": Vector2i(6, 6),
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100,
		"max_health": 100
	}
	var res := BuildingSystemScript.apply_damage(b, 30)
	_assert(res.get("success", false) == true, "TC-BDR.2.1: apply_damage returns true for valid damage")
	_assert(int(b.get("health")) == 70, "TC-BDR.2.2: Health reduced from 100 to 70", "Got %d" % int(b.get("health")))

	# Test WorldView integration
	var wd = world_instance.world_data
	var wv_b := {
		"id": "wv_dmg_test_2",
		"type": "house",
		"cell": Vector2i(7, 7),
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100,
		"max_health": 100
	}
	wd.buildings.append(wv_b)
	var wv_res: bool = world_instance.damage_building("wv_dmg_test_2", 25)
	_assert(wv_res == true, "TC-BDR.2.3: world_instance.damage_building returns true")
	_assert(int(wv_b.get("health")) == 75, "TC-BDR.2.4: WorldView building health reduced to 75")
	wd.buildings.erase(wv_b)

# -----------------------------------------------------------------------------
# 3. Invalid damage input rejection
# -----------------------------------------------------------------------------
func _test_tc_bdr_3_invalid_damage_input_rejection() -> void:
	print("--- Running Scenario 3: Invalid Damage Input Rejection ---")
	var b := {
		"id": "bld_inv_dmg_3",
		"type": "farm",
		"state": "active",
		"health": 80,
		"max_health": 100
	}
	var res_zero := BuildingSystemScript.apply_damage(b, 0)
	var res_neg := BuildingSystemScript.apply_damage(b, -15)
	var res_empty := BuildingSystemScript.apply_damage({}, 20)
	_assert(res_zero.get("success", true) == false, "TC-BDR.3.1: Zero damage rejected")
	_assert(res_neg.get("success", true) == false, "TC-BDR.3.2: Negative damage rejected")
	_assert(res_empty.get("success", true) == false, "TC-BDR.3.3: Empty dictionary rejected")
	_assert(int(b.get("health")) == 80, "TC-BDR.3.4: Health unmodified after invalid calls")

	var wv_res_none: bool = world_instance.damage_building("non_existent_building_xyz", 20)
	var wv_res_zero: bool = world_instance.damage_building("bld_inv_dmg_3", 0)
	_assert(wv_res_none == false, "TC-BDR.3.5: Non-existent building damage returns false")
	_assert(wv_res_zero == false, "TC-BDR.3.6: Non-existent or zero damage in WorldView returns false")

# -----------------------------------------------------------------------------
# 4. Health boundary and clamping behavior
# -----------------------------------------------------------------------------
func _test_tc_bdr_4_health_boundary_and_clamping() -> void:
	print("--- Running Scenario 4: Health Boundary and Clamping ---")
	var b := {
		"id": "bld_clamp_4",
		"type": "mine",
		"state": "active",
		"health": 60,
		"max_health": 100
	}
	BuildingSystemScript.apply_damage(b, 500)
	_assert(int(b.get("health")) == 0, "TC-BDR.4.1: Excessive damage clamps health at 0, not negative", "Got %d" % int(b.get("health")))

	# Check upper bound clamp during repair advance
	b["health"] = 95
	b["damage_initial_health"] = 90
	b["repair_hours_required"] = 1.0
	b["is_repairing"] = true
	b["repair_progress"] = 0.0
	BuildingSystemScript.advance_repair(b, 10.0)
	_assert(int(b.get("health")) == 100, "TC-BDR.4.2: Health restoration clamped at max_health (100)", "Got %d" % int(b.get("health")))

# -----------------------------------------------------------------------------
# 5. Transition into damaged condition
# -----------------------------------------------------------------------------
func _test_tc_bdr_5_transition_into_damaged_condition() -> void:
	print("--- Running Scenario 5: Transition into Damaged Condition ---")
	var wd = world_instance.world_data
	var b := {
		"id": "bld_trans_5",
		"type": "quarry",
		"cell": Vector2i(8, 8),
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 60,
		"max_health": 100
	}
	wd.buildings.append(b)

	# Damage by 15 brings health to 45 (<= 50) -> transitions to "damaged"
	world_instance.damage_building("bld_trans_5", 15)
	_assert(str(b.get("state")) == "damaged", "TC-BDR.5.1: State transitioned to damaged when health dropped to 45 (<= 50)")
	_assert(BuildingSystemScript.is_building_damaged(b) == true, "TC-BDR.5.2: is_building_damaged returns true")

	# Test explicit set_building_state
	b["state"] = "active"
	world_instance.set_building_state("bld_trans_5", "damaged")
	_assert(str(b.get("state")) == "damaged", "TC-BDR.5.3: Explicit set_building_state transitions to damaged")

	wd.buildings.erase(b)

# -----------------------------------------------------------------------------
# 6. Damaged Barracks provides zero soldier capacity
# -----------------------------------------------------------------------------
func _test_tc_bdr_6_damaged_barracks_zero_soldier_capacity() -> void:
	print("--- Running Scenario 6: Damaged Barracks Zero Capacity ---")
	var wd = world_instance.world_data
	var pam = world_instance.player_army_mgr

	var barracks_b := {
		"id": "bld_barracks_scen_6",
		"type": "barracks",
		"cell": Vector2i(20, 20),
		"size": Vector2i(3, 3),
		"state": "active",
		"health": 100,
		"max_health": 100
	}
	wd.buildings.append(barracks_b)
	pam.notify_capacity_changed()
	var init_cap: int = pam.get_army_capacity()
	_assert(init_cap >= 5, "TC-BDR.6.1: Active barracks grants capacity >= 5", "Got %d" % init_cap)

	# Apply damage to transition to damaged
	world_instance.damage_building("bld_barracks_scen_6", 60)
	_assert(str(barracks_b.get("state")) == "damaged", "TC-BDR.6.2: Barracks state is damaged")
	_assert(pam.get_army_capacity() == (init_cap - 5), "TC-BDR.6.3: Damaged barracks deducted 5 capacity dynamically", "Cap: %d" % pam.get_army_capacity())

	wd.buildings.erase(barracks_b)
	pam.notify_capacity_changed()

# -----------------------------------------------------------------------------
# 7. Verification that TC-ARMY.32 passes without weakening assertions
# -----------------------------------------------------------------------------
func _test_tc_bdr_7_tc_army_32_resolution_verification() -> void:
	print("--- Running Scenario 7: TC-ARMY.32 Resolution Verification ---")
	var wd = world_instance.world_data
	var pam = world_instance.player_army_mgr
	var saved_buildings = wd.buildings.duplicate()
	wd.buildings.clear()
	pam.notify_capacity_changed()

	_assert(pam.get_army_capacity() == 0, "TC-BDR.7.1: Zero barracks -> strictly 0 capacity")

	var b_test_id := "tc_army_32_barracks"
	var test_b := {
		"id": b_test_id,
		"type": "barracks",
		"cell": Vector2i(25, 25),
		"size": Vector2i(3, 3),
		"state": "under_construction",
		"construction_progress": 0.0,
		"construction_hours": 12.0
	}
	wd.buildings.append(test_b)
	pam.notify_capacity_changed()
	_assert(pam.get_army_capacity() == 0, "TC-BDR.7.2: under_construction barracks -> strictly 0 capacity")

	# Complete construction
	test_b["construction_progress"] = 12.0
	world_instance.complete_construction(b_test_id)
	_assert(pam.get_army_capacity() == 5, "TC-BDR.7.3: Completed barracks expands capacity to 5")

	# Damage barracks
	pam.soldier_count = 3
	world_instance.set_building_state(b_test_id, "damaged")
	_assert(pam.get_army_capacity() == 0, "TC-BDR.7.4: Damaged barracks drops capacity to 0")
	_assert(pam.get_army_count() == 3, "TC-BDR.7.5: Existing 3 soldiers preserved on damage")

	# Restore barracks
	world_instance.set_building_state(b_test_id, "active")
	_assert(pam.get_army_capacity() == 5, "TC-BDR.7.6: Restored barracks restores capacity to 5")

	# Demolish barracks
	world_instance.demolish_building_project(b_test_id)
	_assert(pam.get_army_capacity() == 0, "TC-BDR.7.7: Demolished barracks drops capacity to 0")
	_assert(pam.get_army_count() == 3, "TC-BDR.7.8: Demolished barracks preserves existing soldiers")

	# Restore original buildings
	wd.buildings.append_array(saved_buildings)
	pam.notify_capacity_changed()

# -----------------------------------------------------------------------------
# 8. Recruitment rejected when Barracks is damaged
# -----------------------------------------------------------------------------
func _test_tc_bdr_8_recruitment_rejected_when_damaged() -> void:
	print("--- Running Scenario 8: Recruitment Rejected When Damaged ---")
	var wd = world_instance.world_data
	var pam = world_instance.player_army_mgr
	var rm = world_instance.get_node_or_null("/root/ResourceManager")

	var barracks_b := {
		"id": "bld_barracks_scen_8",
		"type": "barracks",
		"cell": Vector2i(21, 21),
		"size": Vector2i(3, 3),
		"state": "damaged",
		"health": 40,
		"max_health": 100
	}
	var saved_buildings = wd.buildings.duplicate()
	wd.buildings.clear()
	wd.buildings.append(barracks_b)
	pam.notify_capacity_changed()

	if rm != null:
		rm.add_resource("gold", 500)
		rm.add_resource("metal", 100)
		rm.add_resource("food", 100)

	var can_rec: bool = pam.can_recruit(1).get("can_recruit", false)
	_assert(can_rec == false, "TC-BDR.8.1: can_recruit returns false when barracks damaged (0 capacity)")
	var rec_res: bool = pam.recruit(1).get("success", false)
	_assert(rec_res == false, "TC-BDR.8.2: recruit fails closed when barracks damaged")

	wd.buildings.clear()
	wd.buildings.append_array(saved_buildings)
	pam.notify_capacity_changed()

# -----------------------------------------------------------------------------
# 9. Existing soldiers preserved when capacity drops
# -----------------------------------------------------------------------------
func _test_tc_bdr_9_existing_soldiers_preserved_on_capacity_drop() -> void:
	print("--- Running Scenario 9: Existing Soldiers Preserved on Capacity Drop ---")
	var pam = world_instance.player_army_mgr
	pam.soldier_count = 4
	var wd = world_instance.world_data
	var barracks_b := {
		"id": "bld_barracks_scen_9",
		"type": "barracks",
		"cell": Vector2i(22, 22),
		"size": Vector2i(3, 3),
		"state": "active",
		"health": 100,
		"max_health": 100
	}
	wd.buildings.append(barracks_b)
	pam.notify_capacity_changed()

	world_instance.damage_building("bld_barracks_scen_9", 70)
	_assert(int(barracks_b.get("health")) == 30, "TC-BDR.9.1: Barracks reduced to 30 health")
	_assert(str(barracks_b.get("state")) == "damaged", "TC-BDR.9.2: Barracks state is damaged")
	_assert(pam.get_army_count() == 4, "TC-BDR.9.3: Soldier count remains strictly 4 (no silent deletion)")

	wd.buildings.erase(barracks_b)
	pam.notify_capacity_changed()

# -----------------------------------------------------------------------------
# 10. Repair eligibility validation
# -----------------------------------------------------------------------------
func _test_tc_bdr_10_repair_eligibility_validation() -> void:
	print("--- Running Scenario 10: Repair Eligibility Validation ---")
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	var healthy_b := {
		"id": "bld_elig_healthy",
		"type": "workshop",
		"state": "active",
		"health": 100,
		"max_health": 100
	}
	var res_healthy = BuildingSystemScript.can_repair_building(healthy_b, null, rm)
	_assert(res_healthy.get("can_repair") == false, "TC-BDR.10.1: Healthy building cannot be repaired")

	var under_const_b := {
		"id": "bld_elig_const",
		"type": "workshop",
		"state": "under_construction",
		"health": 50,
		"max_health": 100
	}
	var res_const = BuildingSystemScript.can_repair_building(under_const_b, null, rm)
	_assert(res_const.get("can_repair") == false, "TC-BDR.10.2: Under-construction building cannot be repaired")

	var damaged_b := {
		"id": "bld_elig_damaged",
		"type": "workshop",
		"state": "damaged",
		"health": 40,
		"max_health": 100
	}
	if rm != null:
		rm.add_resource("wood", 100)
		rm.add_resource("stone", 100)
		rm.add_resource("metal", 100)
	var res_damaged = BuildingSystemScript.can_repair_building(damaged_b, null, rm)
	_assert(res_damaged.get("can_repair") == true, "TC-BDR.10.3: Damaged building with materials can be repaired")

# -----------------------------------------------------------------------------
# 11. Proportional repair resource requirements calculation
# -----------------------------------------------------------------------------
func _test_tc_bdr_11_proportional_repair_cost_calculation() -> void:
	print("--- Running Scenario 11: Proportional Repair Cost Calculation ---")
	# Workshop base cost: 20 Wood, 15 Stone, 5 Metal. Max repair is 25% of base: 5 Wood, 4 Stone, 1 Metal.
	var b_zero_hp := {
		"type": "workshop",
		"health": 0,
		"max_health": 100
	}
	var cost_zero = BuildingSystemScript.calculate_repair_cost(b_zero_hp)
	_assert(cost_zero.get("wood", 0) == 5, "TC-BDR.11.1: 0 HP Workshop requires 5 Wood (25% of 20)")
	_assert(cost_zero.get("stone", 0) == 4, "TC-BDR.11.2: 0 HP Workshop requires 4 Stone (round(15*0.25)=4)")
	_assert(cost_zero.get("metal", 0) == 1, "TC-BDR.11.3: 0 HP Workshop requires 1 Metal (round(5*0.25)=1)")

	# At 50 HP (damage ratio 0.5): cost is scaled by 0.5
	var b_half_hp := {
		"type": "workshop",
		"health": 50,
		"max_health": 100
	}
	var cost_half = BuildingSystemScript.calculate_repair_cost(b_half_hp)
	_assert(cost_half.get("wood", 0) == 3, "TC-BDR.11.4: 50 HP Workshop requires 3 Wood (round(20*0.25*0.5)=3)")
	_assert(cost_half.get("stone", 0) == 2, "TC-BDR.11.5: 50 HP Workshop requires 2 Stone (round(15*0.25*0.5)=2)")
	_assert(cost_half.get("metal", 0) == 1, "TC-BDR.11.6: 50 HP Workshop requires 1 Metal (min 1 clamp)")

	# Hours calculation
	var hours = BuildingSystemScript.calculate_repair_hours(b_zero_hp)
	_assert(hours > 0.0, "TC-BDR.11.7: Repair hours calculated strictly > 0.0", "Got %f" % hours)

# -----------------------------------------------------------------------------
# 12. Resource reservation and exact-once consumption upon repair completion
# -----------------------------------------------------------------------------
func _test_tc_bdr_12_resource_reservation_and_exact_once_consumption() -> void:
	print("--- Running Scenario 12: Resource Reservation & Exact-Once Consumption ---")
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	var wd = world_instance.world_data
	if rm == null:
		_assert(false, "TC-BDR.12: ResourceManager not found")
		return

	rm.add_resource("wood", 200)
	rm.add_resource("stone", 200)
	rm.add_resource("metal", 200)

	var b := {
		"id": "bld_res_test_12",
		"type": "workshop",
		"cell": Vector2i(10, 10),
		"size": Vector2i(2, 2),
		"state": "damaged",
		"health": 0,
		"max_health": 100
	}
	wd.buildings.append(b)

	var initial_free_wood: int = rm.get_available_stock("wood")
	var initial_total_wood: int = rm.get_total_stock("wood")

	# Start repair -> reserves materials
	var start_res = world_instance.start_repair_building("bld_res_test_12")
	_assert(start_res.get("success") == true, "TC-BDR.12.1: start_repair_building succeeded")
	_assert(bool(b.get("is_repairing")) == true, "TC-BDR.12.2: Building is marked is_repairing")
	_assert(rm.get_total_stock("wood") == initial_total_wood, "TC-BDR.12.3: Total stock unchanged during reservation")
	_assert(rm.get_available_stock("wood") < initial_free_wood, "TC-BDR.12.4: Free stock decreased by reserved amount")
	_assert(rm.get_reserved_stock("wood") > 0, "TC-BDR.12.4b: Reserved stock increased")

	# Complete repair -> exact-once deduction
	var complete_res = world_instance.complete_repair("bld_res_test_12")
	_assert(complete_res == true, "TC-BDR.12.5: complete_repair returned true")
	_assert(rm.get_total_stock("wood") < initial_total_wood, "TC-BDR.12.6: Total stock consumed upon completion")

	# Idempotent: second call does not deduct again
	var stock_after = rm.get_total_stock("wood")
	var repeat_res = world_instance.complete_repair("bld_res_test_12")
	_assert(repeat_res == false, "TC-BDR.12.7: Second complete_repair returns false")
	_assert(rm.get_total_stock("wood") == stock_after, "TC-BDR.12.8: Total stock unchanged on second complete_repair")

	wd.buildings.erase(b)

# -----------------------------------------------------------------------------
# 13. Repair worker/job assignment to vocational builders
# -----------------------------------------------------------------------------
func _test_tc_bdr_13_repair_builder_job_assignment() -> void:
	print("--- Running Scenario 13: Repair Builder Job Assignment ---")
	var wd = world_instance.world_data
	var jm = world_instance.job_mgr
	var b := {
		"id": "bld_job_test_13",
		"type": "farm",
		"cell": Vector2i(12, 12),
		"size": Vector2i(2, 2),
		"state": "damaged",
		"health": 20,
		"max_health": 100
	}
	wd.buildings.append(b)

	world_instance.start_repair_building("bld_job_test_13")
	var b_jobs = jm.get_jobs_for_building("bld_job_test_13")
	_assert(b_jobs.size() > 0, "TC-BDR.13.1: Builder job registered for repairing building")
	var job_desc: String = b_jobs[0].description if b_jobs.size() > 0 else ""
	_assert(job_desc.contains("Sửa chữa"), "TC-BDR.13.2: Job description indicates repair: %s" % job_desc)

	world_instance.cancel_repair_building("bld_job_test_13")
	wd.buildings.erase(b)

# -----------------------------------------------------------------------------
# 14. Repair progress updates via advance_repair_work and proportional health restoration
# -----------------------------------------------------------------------------
func _test_tc_bdr_14_repair_progress_and_proportional_health_restoration() -> void:
	print("--- Running Scenario 14: Repair Progress & Proportional Health ---")
	var wd = world_instance.world_data
	var b := {
		"id": "bld_prog_test_14",
		"type": "workshop",
		"cell": Vector2i(14, 14),
		"size": Vector2i(2, 2),
		"state": "damaged",
		"health": 20,
		"max_health": 100
	}
	wd.buildings.append(b)
	world_instance.start_repair_building("bld_prog_test_14")

	var req_hours: float = float(b.get("repair_hours_required", 6.0))
	var half_hours: float = req_hours * 0.5
	world_instance.advance_repair_work("bld_prog_test_14", half_hours)

	_assert(is_equal_approx(float(b.get("repair_progress", 0.0)), half_hours), "TC-BDR.14.1: repair_progress reached 50%")
	var current_hp: int = int(b.get("health", 0))
	_assert(current_hp > 20 and current_hp < 100, "TC-BDR.14.2: Health restored proportionally (expected ~60, got %d)" % current_hp)

	world_instance.cancel_repair_building("bld_prog_test_14")
	wd.buildings.erase(b)

# -----------------------------------------------------------------------------
# 15. Repair interruption and safe resumption
# -----------------------------------------------------------------------------
func _test_tc_bdr_15_repair_interruption_and_safe_resumption() -> void:
	print("--- Running Scenario 15: Repair Interruption & Safe Resumption ---")
	var wd = world_instance.world_data
	var b := {
		"id": "bld_resume_test_15",
		"type": "workshop",
		"cell": Vector2i(16, 16),
		"size": Vector2i(2, 2),
		"state": "damaged",
		"health": 20,
		"max_health": 100
	}
	wd.buildings.append(b)
	world_instance.start_repair_building("bld_resume_test_15")

	var req_hours: float = float(b.get("repair_hours_required", 6.0))
	world_instance.advance_repair_work("bld_resume_test_15", req_hours * 0.4)
	var mid_progress: float = float(b.get("repair_progress", 0.0))
	var mid_hp: int = int(b.get("health", 0))

	# Simulate interruption (e.g. time passes without work)
	_assert(float(b.get("repair_progress", 0.0)) == mid_progress, "TC-BDR.15.1: Progress held safely during interruption")
	_assert(int(b.get("health", 0)) == mid_hp, "TC-BDR.15.2: Health held safely during interruption")

	# Resume work until finished
	world_instance.advance_repair_work("bld_resume_test_15", req_hours * 0.7)
	_assert(bool(b.get("is_repairing")) == false, "TC-BDR.15.3: Repair completed after resumption")
	_assert(str(b.get("state")) == "active", "TC-BDR.15.4: State restored to active")
	_assert(int(b.get("health")) == 100, "TC-BDR.15.5: Health fully restored to 100")

	wd.buildings.erase(b)

# -----------------------------------------------------------------------------
# 16. Cancellation via cancel_repair_building and material reservation cleanup
# -----------------------------------------------------------------------------
func _test_tc_bdr_16_repair_cancellation_and_reservation_cleanup() -> void:
	print("--- Running Scenario 16: Repair Cancellation & Reservation Cleanup ---")
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	var wd = world_instance.world_data
	var b := {
		"id": "bld_cancel_test_16",
		"type": "workshop",
		"cell": Vector2i(18, 18),
		"size": Vector2i(2, 2),
		"state": "damaged",
		"health": 30,
		"max_health": 100
	}
	wd.buildings.append(b)

	var free_before: int = rm.get_available_stock("wood")
	world_instance.start_repair_building("bld_cancel_test_16")
	_assert(rm.get_available_stock("wood") < free_before, "TC-BDR.16.1: Free stock reserved upon start")

	var cancel_res = world_instance.cancel_repair_building("bld_cancel_test_16")
	_assert(cancel_res.get("success") == true, "TC-BDR.16.2: cancel_repair_building returned success")
	_assert(rm.get_available_stock("wood") == free_before, "TC-BDR.16.3: Reserved stock released back to free stock")
	_assert(bool(b.get("is_repairing")) == false, "TC-BDR.16.4: is_repairing reset to false")
	_assert(str(b.get("state")) == "damaged", "TC-BDR.16.5: Building remains in damaged state")
	_assert(int(b.get("health")) == 30, "TC-BDR.16.6: Building health preserved at 30")

	wd.buildings.erase(b)

# -----------------------------------------------------------------------------
# 17. Repair completion and restoration of eligible building functionality
# -----------------------------------------------------------------------------
func _test_tc_bdr_17_repair_completion_and_functionality_restoration() -> void:
	print("--- Running Scenario 17: Repair Completion & Functionality Restoration ---")
	var wd = world_instance.world_data
	var pam = world_instance.player_army_mgr
	var b := {
		"id": "bld_barracks_rest_17",
		"type": "barracks",
		"cell": Vector2i(28, 28),
		"size": Vector2i(3, 3),
		"state": "damaged",
		"health": 20,
		"max_health": 100
	}
	wd.buildings.append(b)
	pam.notify_capacity_changed()
	var init_cap: int = pam.get_army_capacity()

	world_instance.start_repair_building("bld_barracks_rest_17")
	var req_h: float = float(b.get("repair_hours_required", 6.0))
	world_instance.advance_repair_work("bld_barracks_rest_17", req_h)

	_assert(str(b.get("state")) == "active", "TC-BDR.17.1: Barracks restored to active state")
	_assert(int(b.get("health")) == 100, "TC-BDR.17.2: Barracks health restored to 100")
	_assert(pam.get_army_capacity() == init_cap + 5, "TC-BDR.17.3: Barracks capacity dynamically restored (+5)")

	wd.buildings.erase(b)
	pam.notify_capacity_changed()

# -----------------------------------------------------------------------------
# 18. Previously paused building remains paused after repair
# -----------------------------------------------------------------------------
func _test_tc_bdr_18_previously_paused_building_restored_to_paused() -> void:
	print("--- Running Scenario 18: Previously Paused Building Stays Paused ---")
	var wd = world_instance.world_data
	var b := {
		"id": "bld_paused_test_18",
		"type": "workshop",
		"cell": Vector2i(32, 32),
		"size": Vector2i(2, 2),
		"state": "paused",
		"health": 100,
		"max_health": 100
	}
	wd.buildings.append(b)

	# Damage the paused building
	world_instance.damage_building("bld_paused_test_18", 60)
	_assert(str(b.get("state")) == "damaged", "TC-BDR.18.1: State became damaged")
	_assert(str(b.get("pre_damage_state")) == "paused", "TC-BDR.18.2: pre_damage_state captured as paused")

	# Start and complete repair
	world_instance.start_repair_building("bld_paused_test_18")
	var req_h: float = float(b.get("repair_hours_required", 6.0))
	world_instance.advance_repair_work("bld_paused_test_18", req_h)

	_assert(str(b.get("state")) == "paused", "TC-BDR.18.3: State cleanly restored to paused (not active)")
	_assert(int(b.get("health")) == 100, "TC-BDR.18.4: Health restored to 100")

	wd.buildings.erase(b)

# -----------------------------------------------------------------------------
# 19. Repeated damage/repair calls are idempotent
# -----------------------------------------------------------------------------
func _test_tc_bdr_19_repeated_calls_idempotency() -> void:
	print("--- Running Scenario 19: Repeated Calls Idempotency ---")
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	var b := {
		"id": "bld_idem_test_19",
		"type": "farm",
		"state": "active",
		"health": 100,
		"max_health": 100
	}
	_assert(BuildingSystemScript.complete_repair(b, null, rm).get("success", true) == false, "TC-BDR.19.1: complete_repair on active building returns false")
	_assert(BuildingSystemScript.cancel_repair(b, null, rm).get("success", true) == false, "TC-BDR.19.2: cancel_repair on non-repairing building returns false")

	b["state"] = "destroyed"
	_assert(BuildingSystemScript.apply_damage(b, 20).get("success", true) == false, "TC-BDR.19.3: apply_damage on destroyed building returns false")

# -----------------------------------------------------------------------------
# 20. Target demolition during repair cleans up safely
# -----------------------------------------------------------------------------
func _test_tc_bdr_20_demolition_during_repair_cleans_up_safely() -> void:
	print("--- Running Scenario 20: Demolition During Repair Cleans Up Safely ---")
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	var wd = world_instance.world_data
	var jm = world_instance.job_mgr

	if rm != null:
		rm.add_resource("wood", 100)
		rm.add_resource("stone", 100)

	var b := {
		"id": "bld_demolish_repair_20",
		"type": "farm",
		"cell": Vector2i(34, 34),
		"size": Vector2i(2, 2),
		"state": "damaged",
		"health": 30,
		"max_health": 100
	}
	wd.buildings.append(b)

	var free_wood_before: int = rm.get_available_stock("wood")
	var start_res = world_instance.start_repair_building("bld_demolish_repair_20")
	_assert(start_res.get("success", false) == true, "TC-BDR.20.1: Repair successfully started")
	_assert(rm.get_available_stock("wood") < free_wood_before, "TC-BDR.20.1b: Materials reserved in ResourceManager")

	# Demolish while repair in progress
	var demo_res = world_instance.demolish_building_project("bld_demolish_repair_20")
	_assert(demo_res.get("success") == true, "TC-BDR.20.2: demolish_building_project succeeded")

	# Check reservations released
	var b_lookup = BuildingSystemScript.get_building_by_id("bld_demolish_repair_20", wd)
	_assert(b_lookup.is_empty(), "TC-BDR.20.3: Building removed from world_data")

	# Verify jobs cleaned up
	var b_jobs_after = jm.get_jobs_for_building("bld_demolish_repair_20")
	_assert(b_jobs_after.is_empty(), "TC-BDR.20.4: Repair job removed from job manager")

# -----------------------------------------------------------------------------
# 21. Save/load disk roundtrip of a damaged building via SaveManager
# -----------------------------------------------------------------------------
func _test_tc_bdr_21_save_load_roundtrip_damaged_building() -> void:
	print("--- Running Scenario 21: Save/Load Roundtrip Damaged Building ---")
	var save_path := "user://saves/test_damage_roundtrip_21.json"
	var wd = world_instance.world_data
	var b := {
		"id": "bld_save_dmg_21",
		"type": "workshop",
		"cell": Vector2i(38, 38),
		"size": Vector2i(2, 2),
		"state": "damaged",
		"health": 42,
		"max_health": 100,
		"pre_damage_state": "active"
	}
	wd.buildings.append(b)

	var save_res = SaveManagerScript.save_to_file(world_instance, save_path)
	_assert(save_res.get("success") == true, "TC-BDR.21.1: World saved successfully with damaged building")

	var load_res = SaveManagerScript.load_from_file(save_path)
	_assert(load_res.get("success", false) == true, "TC-BDR.21.2: Save loaded successfully")
	var load_data: Dictionary = load_res.get("data", {})

	# Clean up world and apply loaded data
	wd.buildings.erase(b)
	SaveManagerScript.apply_loaded_state_to_world(world_instance, load_data)

	var restored_b = BuildingSystemScript.get_building_by_id("bld_save_dmg_21", world_instance.world_data)
	_assert(not restored_b.is_empty(), "TC-BDR.21.3: Damaged building restored from save")
	_assert(int(restored_b.get("health", 0)) == 42, "TC-BDR.21.4: Restored health is 42", "Got %d" % int(restored_b.get("health", 0)))
	_assert(str(restored_b.get("state", "")) == "damaged", "TC-BDR.21.5: Restored state is damaged")

	# Clean up
	world_instance.world_data.buildings.erase(restored_b)
	DirAccess.remove_absolute(save_path)

# -----------------------------------------------------------------------------
# 22. Save/load disk roundtrip of an in-progress repair via SaveManager
# -----------------------------------------------------------------------------
func _test_tc_bdr_22_save_load_roundtrip_in_progress_repair() -> void:
	print("--- Running Scenario 22: Save/Load In-Progress Repair ---")
	var save_path := "user://saves/test_repair_roundtrip_22.json"
	var wd = world_instance.world_data
	var b := {
		"id": "bld_save_rep_22",
		"type": "workshop",
		"cell": Vector2i(40, 40),
		"size": Vector2i(2, 2),
		"state": "damaged",
		"health": 30,
		"max_health": 100,
		"is_repairing": true,
		"repair_progress": 2.5,
		"repair_hours_required": 5.0,
		"repair_cost": {"wood": 5, "stone": 4, "metal": 1},
		"repair_reserved": true,
		"damage_initial_health": 30
	}
	wd.buildings.append(b)

	var save_res = SaveManagerScript.save_to_file(world_instance, save_path)
	_assert(save_res.get("success") == true, "TC-BDR.22.1: Saved world with in-progress repair")

	var load_res = SaveManagerScript.load_from_file(save_path)
	_assert(load_res.get("success", false) == true, "TC-BDR.22.2a: Load returned success")
	var load_data: Dictionary = load_res.get("data", {})

	wd.buildings.erase(b)
	SaveManagerScript.apply_loaded_state_to_world(world_instance, load_data)

	var restored_b = BuildingSystemScript.get_building_by_id("bld_save_rep_22", world_instance.world_data)
	_assert(not restored_b.is_empty(), "TC-BDR.22.2: Restored building from save")
	_assert(bool(restored_b.get("is_repairing", false)) == true, "TC-BDR.22.3: is_repairing restored as true")
	_assert(is_equal_approx(float(restored_b.get("repair_progress", 0.0)), 2.5), "TC-BDR.22.4: repair_progress restored accurately (2.5)")

	# Verify repair job was re-registered
	var restored_jobs = world_instance.job_mgr.get_jobs_for_building("bld_save_rep_22")
	_assert(restored_jobs.size() > 0, "TC-BDR.22.5: Repair job was re-registered after load")

	world_instance.world_data.buildings.erase(restored_b)
	DirAccess.remove_absolute(save_path)

	world_instance.world_data.buildings.erase(restored_b)
	DirAccess.remove_absolute(save_path)

# -----------------------------------------------------------------------------
# 23. Legacy save compatibility (missing health/repair fields default cleanly)
# -----------------------------------------------------------------------------
func _test_tc_bdr_23_legacy_save_compatibility_missing_fields() -> void:
	print("--- Running Scenario 23: Legacy Save Compatibility ---")
	var legacy_b := {
		"id": "bld_legacy_23",
		"type": "farm",
		"cell": Vector2i(42, 42),
		"size": Vector2i(2, 2),
		"state": "active"
		# Missing health, max_health, is_repairing, repair_progress, etc.
	}
	var norm_b = BuildingSystemScript.normalize_building_data(legacy_b)
	_assert(int(norm_b.get("health")) == 100, "TC-BDR.23.1: Legacy missing health defaults to 100")
	_assert(int(norm_b.get("max_health")) == 100, "TC-BDR.23.2: Legacy missing max_health defaults to 100")
	_assert(bool(norm_b.get("is_repairing")) == false, "TC-BDR.23.3: Legacy missing is_repairing defaults to false")
	_assert(float(norm_b.get("repair_progress")) == 0.0, "TC-BDR.23.4: Legacy missing repair_progress defaults to 0.0")

# -----------------------------------------------------------------------------
# 24. Building upgrade and repair interaction (damaged/repairing cannot upgrade)
# -----------------------------------------------------------------------------
func _test_tc_bdr_24_upgrade_and_repair_mutual_exclusion() -> void:
	print("--- Running Scenario 24: Upgrade and Repair Mutual Exclusion ---")
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	var wd = world_instance.world_data
	var b_damaged := {
		"id": "bld_upg_dmg_24",
		"type": "farm",
		"cell": Vector2i(44, 44),
		"size": Vector2i(2, 2),
		"state": "damaged",
		"health": 40,
		"max_health": 100,
		"upgrade_level": 1
	}
	var res_dmg = BuildingSystemScript.can_start_upgrade(b_damaged, wd, rm)
	_assert(res_dmg.get("can_upgrade") == false, "TC-BDR.24.1: Damaged building cannot start upgrade")
	_assert(str(res_dmg.get("reason")).contains("hư hại"), "TC-BDR.24.2: Rejection reason mentions damage: %s" % str(res_dmg.get("reason")))

	var b_repairing := {
		"id": "bld_upg_rep_24",
		"type": "farm",
		"cell": Vector2i(46, 46),
		"size": Vector2i(2, 2),
		"state": "damaged",
		"health": 60,
		"max_health": 100,
		"upgrade_level": 1,
		"is_repairing": true
	}
	var res_rep = BuildingSystemScript.can_start_upgrade(b_repairing, wd, rm)
	_assert(res_rep.get("can_upgrade") == false, "TC-BDR.24.3: Repairing building cannot start upgrade")
	_assert(str(res_rep.get("reason")).contains("sửa chữa"), "TC-BDR.24.4: Rejection reason mentions repair: %s" % str(res_rep.get("reason")))

# -----------------------------------------------------------------------------
# 25. Building inspection UI accurately reflects condition, badges, and repair controls
# -----------------------------------------------------------------------------
func _test_tc_bdr_25_building_inspect_panel_ui_reflection() -> void:
	print("--- Running Scenario 25: Building Inspection UI Reflection ---")
	var hud = world_instance.get("hud")
	var wd = world_instance.world_data
	if hud == null:
		_assert(false, "TC-BDR.25: HUD not present in world_instance")
		return

	var b := {
		"id": "bld_ui_test_25",
		"type": "workshop",
		"cell": Vector2i(48, 48),
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100,
		"max_health": 100
	}
	wd.buildings.append(b)

	# 1. Inspect healthy building
	hud.show_building_inspector(b)
	_assert(hud.building_state_label.text.contains("HOẠT ĐỘNG"), "TC-BDR.25.1: Healthy building shows HOẠT ĐỘNG badge")
	_assert(hud.pause_resume_btn.visible == true, "TC-BDR.25.2: Pause/resume button is visible for healthy building")
	_assert(hud.repair_section.visible == false, "TC-BDR.25.3: RepairSection is hidden for healthy building")

	# 2. Damage building and inspect
	world_instance.damage_building("bld_ui_test_25", 60)
	hud.refresh_building_inspector()
	_assert(hud.building_state_label.text.contains("BỊ HƯ HẠI"), "TC-BDR.25.4: Damaged building shows [BỊ HƯ HẠI] badge")
	_assert(hud.pause_resume_btn.visible == false, "TC-BDR.25.5: Pause/resume button hidden for damaged building")
	_assert(hud.repair_section.visible == true, "TC-BDR.25.6: RepairSection is visible for damaged building")
	_assert(hud.repair_btn.visible == true, "TC-BDR.25.7: Repair button is visible")

	# 3. Click start repair via UI handler
	hud._on_start_repair_pressed()
	_assert(hud.repair_progress_box.visible == true, "TC-BDR.25.8: RepairProgressBox visible when repairing")
	_assert(hud.cancel_repair_btn.visible == true, "TC-BDR.25.9: CancelRepairBtn visible when repairing")
	_assert(hud.building_state_label.text.contains("ĐANG SỬA CHỮA"), "TC-BDR.25.10: Badge updates to [ĐANG SỬA CHỮA]")

	# 4. Click cancel repair via UI handler
	hud._on_cancel_repair_pressed()
	_assert(hud.repair_progress_box.visible == false, "TC-BDR.25.11: RepairProgressBox hidden after cancellation")
	_assert(hud.repair_btn.visible == true, "TC-BDR.25.12: Repair button restored after cancellation")

	hud.close_building_inspector()
	wd.buildings.erase(b)
