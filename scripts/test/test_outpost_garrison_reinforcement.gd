extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — PACKAGE 3A
## Territorial Outpost Garrisoning & Reinforcement (GDD §6.3, §10.5, Milestone 3)
## Authoritative Coverage: TC-OGR.01 through TC-OGR.26

const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")
const PlayerArmyManagerScript = preload("res://scripts/military/player_army_manager.gd")
const FieldSiegeManagerScript = preload("res://scripts/combat/field_siege_manager.gd")
const BattleCampaignManagerScript = preload("res://scripts/combat/battle_campaign_manager.gd")
const SiegeObjectiveActorScript = preload("res://scripts/combat/siege_objective_actor.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")

class MockUpkeepRM extends RefCounted:
	var stock := {"food": 10}
	func reserve_cost(_cost: Dictionary) -> bool: return true
	func commit_cost(cost: Dictionary) -> bool:
		stock["food"] -= int(cost.get("food", 0))
		return true

class MockFailingRM extends RefCounted:
	func reserve_cost(_cost: Dictionary) -> bool: return false
	func commit_cost(_cost: Dictionary) -> bool: return false

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
	print("  STARTING PACKAGE 3A OUTPOST GARRISONING TEST SUITE")
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
	print("  PACKAGE 3A TEST RESULTS SUMMARY")
	print("--------------------------------------------------------")
	print("  Passed Assertions : %d" % passed_count)
	print("  Failed Assertions : %d" % failures)
	if failures == 0:
		print("  ALL PACKAGE 3A ASSERTIONS PASSED! (Exit Code 0)")
	else:
		printerr("  PACKAGE 3A FAILED WITH %d FAILURES! (Exit Code 1)" % failures)
	print("--------------------------------------------------------\n")

func _run_all_tests() -> void:
	_test_tc_ogr_01_initialization()
	_test_tc_ogr_02_legal_stationing_at_captured_outpost()
	_test_tc_ogr_03_capacity_limit_enforcement()
	_test_tc_ogr_04_rejection_when_central_reserve_insufficient()
	_test_tc_ogr_05_legal_stationing_at_watchtower()
	_test_tc_ogr_06_legal_stationing_at_palisade()
	_test_tc_ogr_07_rejection_at_damaged_or_paused_building()
	_test_tc_ogr_08_rejection_at_hostile_or_unowned_outpost()
	_test_tc_ogr_09_soldier_recall_to_central_reserve()
	_test_tc_ogr_10_rejection_of_empty_or_excessive_recall()
	_test_tc_ogr_11_strict_global_soldier_conservation()
	_test_tc_ogr_12_equipment_tier_and_attribute_preservation()
	_test_tc_ogr_13_reinforcement_dispatch_and_in_transit()
	_test_tc_ogr_14_in_transit_capacity_bounding()
	_test_tc_ogr_15_reinforcement_arrival_synchronization()
	_test_tc_ogr_16_daily_food_upkeep_across_all_troops()
	_test_tc_ogr_17_upkeep_failure_morale_penalty_without_troop_loss()
	_test_tc_ogr_18_outpost_defense_power_calculation()
	_test_tc_ogr_19_casualty_deduction_from_garrison_records()
	_test_tc_ogr_20_outpost_conquest_eviction_without_leaks()
	_test_tc_ogr_21_multiple_simultaneous_garrisons()
	_test_tc_ogr_22_outpost_lost_in_transit_retreats_safely()
	_test_tc_ogr_23_hud_inspection_wiring()
	_test_tc_ogr_24_save_manager_persistence_roundtrip()
	_test_tc_ogr_25_save_manager_legacy_backward_compatibility()
	_test_tc_ogr_26_idempotency_and_invalid_inputs()
	# Package 3A Follow-Up: Outpost Capacity Correctness (TC-CAP.01 to TC-CAP.08)
	_test_tc_cap_01_legacy_save_missing_capacity()
	_test_tc_cap_02_invalid_zero_capacity()
	_test_tc_cap_03_negative_capacity()
	_test_tc_cap_04_explicit_capacity_preservation()
	_test_tc_cap_05_new_objective_default()
	_test_tc_cap_06_legacy_pre_package_1x_default_objectives()
	_test_tc_cap_07_save_load_persistence()
	_test_tc_cap_08_soldier_conservation()

# -----------------------------------------------------------------------------
# 1. TC-OGR.01: Initialization & Defaults
# -----------------------------------------------------------------------------
func _test_tc_ogr_01_initialization() -> void:
	print("\n--- TC-OGR.01: Outpost Garrison Initialization & Defaults ---")
	var pam = PlayerArmyManagerScript.new()
	_assert(pam.garrisons.is_empty(), "TC-OGR.01.1: Initial garrisons dictionary is empty")
	_assert(pam.active_reinforcements.is_empty(), "TC-OGR.01.2: Initial active reinforcements list is empty")
	_assert(pam.get_total_soldier_count() == 0, "TC-OGR.01.3: Total soldier count starts at 0")
	_assert(pam.get_all_garrisoned_count() == 0, "TC-OGR.01.4: All garrisoned count starts at 0")
	_assert(pam.get_in_transit_count() == 0, "TC-OGR.01.5: In transit count starts at 0")
	_assert(pam.get_garrison_count("any_outpost") == 0, "TC-OGR.01.6: Unknown outpost returns 0 garrison")

# -----------------------------------------------------------------------------
# 2. TC-OGR.02: Legal Stationing at Captured Outpost
# -----------------------------------------------------------------------------
func _test_tc_ogr_02_legal_stationing_at_captured_outpost() -> void:
	print("\n--- TC-OGR.02: Legal Soldier Stationing at Captured Territorial Outpost ---")
	var pam = PlayerArmyManagerScript.new()
	pam.soldier_count = 5
	pam.register_outpost_for_testing("outpost_player_alpha", 4, Vector2i(10, 10), "player")

	var res: Dictionary = pam.station_soldier("outpost_player_alpha", 2)
	_assert(res.get("success", false) == true, "TC-OGR.02.1: Station soldier returns success")
	_assert(res.get("stationed", 0) == 2, "TC-OGR.02.2: Stationed count is 2")
	_assert(pam.soldier_count == 3, "TC-OGR.02.3: Central reserve decreased by 2 (3 remaining)")
	_assert(pam.get_garrison_count("outpost_player_alpha") == 2, "TC-OGR.02.4: Outpost garrison count is 2")
	_assert(pam.get_total_soldier_count() == 5, "TC-OGR.02.5: Total soldier count conserved at 5")

# -----------------------------------------------------------------------------
# 3. TC-OGR.03: Capacity Limit Enforcement
# -----------------------------------------------------------------------------
func _test_tc_ogr_03_capacity_limit_enforcement() -> void:
	print("\n--- TC-OGR.03: Capacity Limit Enforcement on Outpost Garrison ---")
	var pam = PlayerArmyManagerScript.new()
	pam.soldier_count = 10
	pam.register_outpost_for_testing("outpost_cap_test", 3, Vector2i(12, 12), "player")

	pam.station_soldier("outpost_cap_test", 2)
	_assert(pam.get_garrison_count("outpost_cap_test") == 2, "TC-OGR.03.1: 2 soldiers stationed")

	# Attempt to station 2 more when capacity is 3 (2 + 2 = 4 > 3)
	var res_overflow: Dictionary = pam.station_soldier("outpost_cap_test", 2)
	_assert(res_overflow.get("success", true) == false, "TC-OGR.03.2: Over-capacity stationing rejected fail-closed")
	_assert(pam.get_garrison_count("outpost_cap_test") == 2, "TC-OGR.03.3: Garrison count unchanged at 2")
	_assert(pam.soldier_count == 8, "TC-OGR.03.4: Central reserve unchanged at 8")

# -----------------------------------------------------------------------------
# 4. TC-OGR.04: Rejection When Central Reserve Insufficient
# -----------------------------------------------------------------------------
func _test_tc_ogr_04_rejection_when_central_reserve_insufficient() -> void:
	print("\n--- TC-OGR.04: Rejection When Central Reserve is Insufficient ---")
	var pam = PlayerArmyManagerScript.new()
	pam.soldier_count = 1
	pam.register_outpost_for_testing("outpost_res_test", 4, Vector2i(15, 15), "player")

	var res: Dictionary = pam.station_soldier("outpost_res_test", 2)
	_assert(res.get("success", true) == false, "TC-OGR.04.1: Stationing rejected when central reserve insufficient")
	_assert(pam.get_garrison_count("outpost_res_test") == 0, "TC-OGR.04.2: Garrison remains 0")
	_assert(pam.soldier_count == 1, "TC-OGR.04.3: Central reserve preserved at 1")

# -----------------------------------------------------------------------------
# 5. TC-OGR.05: Legal Stationing at Watchtower (Capacity 2)
# -----------------------------------------------------------------------------
func _test_tc_ogr_05_legal_stationing_at_watchtower() -> void:
	print("\n--- TC-OGR.05: Legal Soldier Stationing at Watchtower ---")
	var pam = PlayerArmyManagerScript.new(world_instance)
	pam.soldier_count = 4

	# Insert an active watchtower building in world_data
	var wt := {
		"id": "test_wt_civic_1",
		"type": "watchtower",
		"state": "active",
		"cell": Vector2i(20, 20),
		"size": Vector2i(1, 1),
		"health": 100,
		"max_health": 100
	}
	world_instance.world_data.buildings.append(wt)

	var res: Dictionary = pam.station_soldier("test_wt_civic_1", 2)
	_assert(res.get("success", false) == true, "TC-OGR.05.1: Stationing at watchtower successful")
	_assert(pam.get_garrison_count("test_wt_civic_1") == 2, "TC-OGR.05.2: Watchtower garrison count is 2")
	_assert(pam.get_garrison_capacity("test_wt_civic_1") == 2, "TC-OGR.05.3: Watchtower capacity is 2")

	# Station 1 more should fail (capacity 2 full)
	var res_full: Dictionary = pam.station_soldier("test_wt_civic_1", 1)
	_assert(res_full.get("success", true) == false, "TC-OGR.05.4: Watchtower rejects stationing beyond capacity 2")

	world_instance.world_data.buildings.erase(wt)

# -----------------------------------------------------------------------------
# 6. TC-OGR.06: Legal Stationing at Palisade (Capacity 2)
# -----------------------------------------------------------------------------
func _test_tc_ogr_06_legal_stationing_at_palisade() -> void:
	print("\n--- TC-OGR.06: Legal Soldier Stationing at Palisade ---")
	var pam = PlayerArmyManagerScript.new(world_instance)
	pam.soldier_count = 3

	var pal := {
		"id": "test_pal_civic_1",
		"type": "palisade",
		"state": "active",
		"cell": Vector2i(22, 22),
		"size": Vector2i(1, 1),
		"health": 100,
		"max_health": 100
	}
	world_instance.world_data.buildings.append(pal)

	var res: Dictionary = pam.station_soldier("test_pal_civic_1", 1)
	_assert(res.get("success", false) == true, "TC-OGR.06.1: Stationing at palisade successful")
	_assert(pam.get_garrison_count("test_pal_civic_1") == 1, "TC-OGR.06.2: Palisade garrison count is 1")
	_assert(pam.get_garrison_capacity("test_pal_civic_1") == 2, "TC-OGR.06.3: Palisade capacity is 2")

	world_instance.world_data.buildings.erase(pal)

# -----------------------------------------------------------------------------
# 7. TC-OGR.07: Rejection at Damaged, Paused, or Unconstructed Building
# -----------------------------------------------------------------------------
func _test_tc_ogr_07_rejection_at_damaged_or_paused_building() -> void:
	print("\n--- TC-OGR.07: Rejection at Damaged, Paused, or Unbuilt Building ---")
	var pam = PlayerArmyManagerScript.new(world_instance)
	pam.soldier_count = 5

	var dmg_wt := {
		"id": "test_wt_damaged",
		"type": "watchtower",
		"state": "damaged",
		"cell": Vector2i(24, 24),
		"size": Vector2i(1, 1),
		"health": 40,
		"max_health": 100
	}
	var unbuilt_wt := {
		"id": "test_wt_unbuilt",
		"type": "watchtower",
		"state": "under_construction",
		"cell": Vector2i(25, 25),
		"size": Vector2i(1, 1),
		"health": 100,
		"max_health": 100
	}
	world_instance.world_data.buildings.append(dmg_wt)
	world_instance.world_data.buildings.append(unbuilt_wt)

	var res_dmg: Dictionary = pam.station_soldier("test_wt_damaged", 1)
	_assert(res_dmg.get("success", true) == false, "TC-OGR.07.1: Stationing rejected at damaged watchtower")

	var res_unbuilt: Dictionary = pam.station_soldier("test_wt_unbuilt", 1)
	_assert(res_unbuilt.get("success", true) == false, "TC-OGR.07.2: Stationing rejected at unbuilt watchtower")

	world_instance.world_data.buildings.erase(dmg_wt)
	world_instance.world_data.buildings.erase(unbuilt_wt)

# -----------------------------------------------------------------------------
# 8. TC-OGR.08: Rejection at Hostile or Unowned Outpost
# -----------------------------------------------------------------------------
func _test_tc_ogr_08_rejection_at_hostile_or_unowned_outpost() -> void:
	print("\n--- TC-OGR.08: Rejection at Hostile or Unowned Outpost ---")
	var pam = PlayerArmyManagerScript.new()
	pam.soldier_count = 5
	pam.register_outpost_for_testing("outpost_enemy_base", 4, Vector2i(10, 10), "rival_military")

	var res: Dictionary = pam.station_soldier("outpost_enemy_base", 1)
	_assert(res.get("success", true) == false, "TC-OGR.08.1: Stationing rejected at rival outpost")
	_assert(pam.get_garrison_count("outpost_enemy_base") == 0, "TC-OGR.08.2: Rival outpost garrison remains 0")
	_assert(pam.soldier_count == 5, "TC-OGR.08.3: Central reserve unchanged at 5")

# -----------------------------------------------------------------------------
# 9. TC-OGR.09: Soldier Recall to Central Reserve
# -----------------------------------------------------------------------------
func _test_tc_ogr_09_soldier_recall_to_central_reserve() -> void:
	print("\n--- TC-OGR.09: Soldier Recall from Outpost Back to Central Reserve ---")
	var pam = PlayerArmyManagerScript.new()
	pam.soldier_count = 5
	pam.register_outpost_for_testing("outpost_recall_test", 4, Vector2i(10, 10), "player")

	pam.station_soldier("outpost_recall_test", 3)
	_assert(pam.soldier_count == 2, "TC-OGR.09.1: Central reserve is 2 after stationing 3")
	_assert(pam.get_garrison_count("outpost_recall_test") == 3, "TC-OGR.09.2: Garrison is 3")

	var recall_res: Dictionary = pam.recall_soldier("outpost_recall_test", 2)
	_assert(recall_res.get("success", false) == true, "TC-OGR.09.3: Recall returns success")
	_assert(recall_res.get("recalled", 0) == 2, "TC-OGR.09.4: Recalled count is 2")
	_assert(pam.soldier_count == 4, "TC-OGR.09.5: Central reserve increased back to 4")
	_assert(pam.get_garrison_count("outpost_recall_test") == 1, "TC-OGR.09.6: Garrison decreased to 1")
	_assert(pam.get_total_soldier_count() == 5, "TC-OGR.09.7: Total soldiers conserved at 5")

# -----------------------------------------------------------------------------
# 10. TC-OGR.10: Rejection of Empty or Excessive Recall
# -----------------------------------------------------------------------------
func _test_tc_ogr_10_rejection_of_empty_or_excessive_recall() -> void:
	print("\n--- TC-OGR.10: Rejection of Empty or Excessive Recall ---")
	var pam = PlayerArmyManagerScript.new()
	pam.soldier_count = 5
	pam.register_outpost_for_testing("outpost_recall_bounds", 4, Vector2i(10, 10), "player")

	# Recall from empty outpost
	var res_empty: Dictionary = pam.recall_soldier("outpost_recall_bounds", 1)
	_assert(res_empty.get("success", true) == false, "TC-OGR.10.1: Empty recall rejected fail-closed")

	pam.station_soldier("outpost_recall_bounds", 1)
	# Recall 2 from outpost with only 1
	var res_excess: Dictionary = pam.recall_soldier("outpost_recall_bounds", 2)
	_assert(res_excess.get("success", true) == false, "TC-OGR.10.2: Excessive recall rejected fail-closed")
	_assert(pam.get_garrison_count("outpost_recall_bounds") == 1, "TC-OGR.10.3: Garrison preserved at 1")

# -----------------------------------------------------------------------------
# 11. TC-OGR.11: Strict Global Soldier Conservation
# -----------------------------------------------------------------------------
func _test_tc_ogr_11_strict_global_soldier_conservation() -> void:
	print("\n--- TC-OGR.11: Strict Global Soldier Conservation Across Operations ---")
	var pam = PlayerArmyManagerScript.new()
	pam.soldier_count = 12
	var initial_total: int = pam.get_total_soldier_count()
	pam.register_outpost_for_testing("outpost_cons_1", 4, Vector2i(5, 5), "player")
	pam.register_outpost_for_testing("outpost_cons_2", 4, Vector2i(15, 15), "player")

	var operations := [
		["station", "outpost_cons_1", 3],
		["station", "outpost_cons_2", 2],
		["recall", "outpost_cons_1", 1],
		["station", "outpost_cons_2", 1],
		["recall", "outpost_cons_2", 2],
		["station", "outpost_cons_1", 2]
	]

	var all_conserved := true
	for op in operations:
		var act: String = op[0]
		var target: String = op[1]
		var amt: int = op[2]
		if act == "station":
			pam.station_soldier(target, amt)
		elif act == "recall":
			pam.recall_soldier(target, amt)

		var cur_total := pam.get_total_soldier_count()
		if cur_total != initial_total:
			all_conserved = false
			break

	_assert(all_conserved == true, "TC-OGR.11.1: Soldier count strictly conserved across all operations")
	_assert(pam.get_total_soldier_count() == 12, "TC-OGR.11.2: Total soldier count remains exactly 12")

# -----------------------------------------------------------------------------
# 12. TC-OGR.12: Equipment Tier and Health Attribute Preservation
# -----------------------------------------------------------------------------
func _test_tc_ogr_12_equipment_tier_and_attribute_preservation() -> void:
	print("\n--- TC-OGR.12: Equipment Tier and Health Attribute Preservation ---")
	var pam = PlayerArmyManagerScript.new()
	pam.soldier_count = 3
	pam.equipment_tier = 3
	pam.register_outpost_for_testing("outpost_tier_test", 4, Vector2i(10, 10), "player")

	pam.station_soldier("outpost_tier_test", 1)
	var gar: Dictionary = pam.get_garrison("outpost_tier_test")
	var s_list: Array = gar.get("soldiers", [])
	_assert(s_list.size() == 1, "TC-OGR.12.1: Garrison has 1 soldier")
	var s: Dictionary = s_list[0]
	_assert(int(s.get("equipment_tier", 0)) == 3, "TC-OGR.12.2: Soldier preserves Tier 3 equipment")
	_assert(float(s.get("health", 0.0)) == 100.0, "TC-OGR.12.3: Soldier health initialized at 100 HP")

# -----------------------------------------------------------------------------
# 13. TC-OGR.13: Reinforcement Dispatch & In-Transit Tracking
# -----------------------------------------------------------------------------
func _test_tc_ogr_13_reinforcement_dispatch_and_in_transit() -> void:
	print("\n--- TC-OGR.13: Reinforcement Dispatch and In-Transit Tracking ---")
	var pam = PlayerArmyManagerScript.new()
	pam.soldier_count = 6
	pam.register_outpost_for_testing("outpost_transit_test", 4, Vector2i(20, 20), "player")

	var res: Dictionary = pam.dispatch_reinforcements("outpost_transit_test", 2, 2.0)
	_assert(res.get("success", false) == true, "TC-OGR.13.1: Dispatch reinforcements returns success")
	_assert(pam.soldier_count == 4, "TC-OGR.13.2: Central reserve decremented to 4 immediately")
	_assert(pam.get_in_transit_count("outpost_transit_test") == 2, "TC-OGR.13.3: In-transit count for outpost is 2")
	_assert(pam.get_garrison_count("outpost_transit_test") == 0, "TC-OGR.13.4: Stationed count is still 0 before arrival")
	_assert(pam.get_total_soldier_count() == 6, "TC-OGR.13.5: Total soldiers conserved during transit (4 reserve + 2 transit)")

# -----------------------------------------------------------------------------
# 14. TC-OGR.14: In-Transit Capacity Bounding
# -----------------------------------------------------------------------------
func _test_tc_ogr_14_in_transit_capacity_bounding() -> void:
	print("\n--- TC-OGR.14: In-Transit Reinforcement Capacity Bounding ---")
	var pam = PlayerArmyManagerScript.new()
	pam.soldier_count = 8
	pam.register_outpost_for_testing("outpost_cap_bound", 3, Vector2i(10, 10), "player")

	# Dispatch 2 into outpost with cap 3
	pam.dispatch_reinforcements("outpost_cap_bound", 2, 3.0)
	# Attempt to dispatch 2 more (2 in transit + 2 new = 4 > 3 cap)
	var res_over: Dictionary = pam.dispatch_reinforcements("outpost_cap_bound", 2, 3.0)
	_assert(res_over.get("success", true) == false, "TC-OGR.14.1: Over-dispatch beyond capacity rejected fail-closed")
	_assert(pam.get_in_transit_count("outpost_cap_bound") == 2, "TC-OGR.14.2: In-transit count remains 2")
	_assert(pam.soldier_count == 6, "TC-OGR.14.3: Central reserve preserved at 6")

# -----------------------------------------------------------------------------
# 15. TC-OGR.15: Reinforcement Arrival Synchronization
# -----------------------------------------------------------------------------
func _test_tc_ogr_15_reinforcement_arrival_synchronization() -> void:
	print("\n--- TC-OGR.15: Reinforcement Arrival Synchronization ---")
	var pam = PlayerArmyManagerScript.new()
	pam.soldier_count = 5
	pam.register_outpost_for_testing("outpost_arrival_test", 4, Vector2i(15, 15), "player")

	pam.dispatch_reinforcements("outpost_arrival_test", 2, 3.0)

	# Partial transit (elapsed 1.5 < 3.0)
	var mid_arr: Array = pam.advance_reinforcements(1.5)
	_assert(mid_arr.is_empty(), "TC-OGR.15.1: No arrivals at half travel duration")
	_assert(pam.get_garrison_count("outpost_arrival_test") == 0, "TC-OGR.15.2: Garrison still 0")
	_assert(pam.get_in_transit_count("outpost_arrival_test") == 2, "TC-OGR.15.3: In-transit still 2")

	# Arrival (elapsed 1.5 + 1.5 = 3.0 >= 3.0)
	var final_arr: Array = pam.advance_reinforcements(1.5)
	_assert(final_arr.size() == 1, "TC-OGR.15.4: Arrival completed at full duration")
	_assert(pam.get_garrison_count("outpost_arrival_test") == 2, "TC-OGR.15.5: Soldiers stationed at outpost upon arrival")
	_assert(pam.get_in_transit_count("outpost_arrival_test") == 0, "TC-OGR.15.6: In-transit cleared upon arrival")
	_assert(pam.get_total_soldier_count() == 5, "TC-OGR.15.7: Total soldiers conserved at 5")

# -----------------------------------------------------------------------------
# 16. TC-OGR.16: Daily Food Upkeep Consumption
# -----------------------------------------------------------------------------
func _test_tc_ogr_16_daily_food_upkeep_across_all_troops() -> void:
	print("\n--- TC-OGR.16: Daily Food Upkeep Across Central + Garrison Troops ---")
	var pam = PlayerArmyManagerScript.new()
	pam.soldier_count = 5
	pam.register_outpost_for_testing("outpost_upkeep_1", 4, Vector2i(5, 5), "player")
	pam.register_outpost_for_testing("outpost_upkeep_2", 4, Vector2i(15, 15), "player")

	# 2 in outpost_1 + 1 in outpost_2 = 3 stationed, 2 in reserve = 5 total soldiers
	pam.station_soldier("outpost_upkeep_1", 2)
	pam.station_soldier("outpost_upkeep_2", 1)
	_assert(pam.get_total_soldier_count() == 5, "TC-OGR.16.1: 5 total soldiers distributed across realm")

	# Provide mock ResourceManager with 10 food
	var mock_rm = MockUpkeepRM.new()
	pam.set_custom_resource_manager(mock_rm)

	var upkeep_res: Dictionary = pam.process_daily_upkeep(1)
	_assert(upkeep_res.get("success", false) == true, "TC-OGR.16.2: Daily upkeep succeeds")
	_assert(pam.is_supplied == true, "TC-OGR.16.3: Army is supplied")
	_assert(mock_rm.stock["food"] == 5, "TC-OGR.16.4: Exactly 5 food consumed for 5 soldiers (1 food/soldier/day)")

# -----------------------------------------------------------------------------
# 17. TC-OGR.17: Upkeep Failure Morale Penalty Without Troop Loss
# -----------------------------------------------------------------------------
func _test_tc_ogr_17_upkeep_failure_morale_penalty_without_troop_loss() -> void:
	print("\n--- TC-OGR.17: Upkeep Failure Morale Penalty Without Troop Loss ---")
	var pam = PlayerArmyManagerScript.new()
	pam.soldier_count = 4
	pam.register_outpost_for_testing("outpost_starve_test", 4, Vector2i(10, 10), "player")
	pam.station_soldier("outpost_starve_test", 2)

	# Mock RM failing reservation (0 food available)
	var mock_rm = MockFailingRM.new()
	pam.set_custom_resource_manager(mock_rm)

	var upkeep_res: Dictionary = pam.process_daily_upkeep(2)
	_assert(upkeep_res.get("success", true) == false, "TC-OGR.17.1: Upkeep fails gracefully when food insufficient")
	_assert(pam.is_supplied == false, "TC-OGR.17.2: Army marked unsupplied")
	_assert(pam.get_combat_morale() == EconomyConfigScript.ARMY_MORALE_UNSUPPLIED, "TC-OGR.17.3: Morale penalty applied")
	_assert(pam.get_total_soldier_count() == 4, "TC-OGR.17.4: Zero soldiers deleted on starvation (conservation invariant)")

# -----------------------------------------------------------------------------
# 18. TC-OGR.18: Outpost Defense Power Calculation
# -----------------------------------------------------------------------------
func _test_tc_ogr_18_outpost_defense_power_calculation() -> void:
	print("\n--- TC-OGR.18: Outpost Defense Power Calculation ---")
	var pam = PlayerArmyManagerScript.new()
	pam.soldier_count = 4
	pam.equipment_tier = 2
	pam.register_outpost_for_testing("outpost_bcm_test", 4, Vector2i(10, 10), "player")
	pam.station_soldier("outpost_bcm_test", 3)

	var bcm = BattleCampaignManagerScript.new(world_instance)
	bcm.set_player_army_manager(pam)
	var def_force: Dictionary = bcm.construct_outpost_defending_force("outpost_bcm_test")
	_assert(def_force.get("troops", 0) == 3, "TC-OGR.18.1: Defending force troops equals garrison count (3)")
	_assert(def_force.get("equipment_tier", 0) == 2, "TC-OGR.18.2: Defending force equipment tier matches Tier 2")

# -----------------------------------------------------------------------------
# 19. TC-OGR.19: Casualty Deduction from Garrison Records
# -----------------------------------------------------------------------------
func _test_tc_ogr_19_casualty_deduction_from_garrison_records() -> void:
	print("\n--- TC-OGR.19: Casualty Deduction from Garrison Records ---")
	var pam = PlayerArmyManagerScript.new()
	pam.soldier_count = 5
	pam.register_outpost_for_testing("outpost_cas_test", 4, Vector2i(10, 10), "player")
	pam.station_soldier("outpost_cas_test", 3)

	var dead_count: int = pam.apply_outpost_casualties("outpost_cas_test", 2)
	_assert(dead_count == 2, "TC-OGR.19.1: Exactly 2 casualties applied")
	_assert(pam.get_garrison_count("outpost_cas_test") == 1, "TC-OGR.19.2: Garrison reduced to 1")
	_assert(pam.soldier_count == 2, "TC-OGR.19.3: Central reserve untouched at 2")
	_assert(pam.get_total_soldier_count() == 3, "TC-OGR.19.4: Total soldiers updated correctly to 3")

# -----------------------------------------------------------------------------
# 20. TC-OGR.20: Outpost Conquest Eviction Without Leaks
# -----------------------------------------------------------------------------
func _test_tc_ogr_20_outpost_conquest_eviction_without_leaks() -> void:
	print("\n--- TC-OGR.20: Outpost Conquest Eviction Without Leaks ---")
	var pam = PlayerArmyManagerScript.new(world_instance)
	pam.soldier_count = 4
	pam.register_outpost_for_testing("outpost_conquest_test", 4, Vector2i(10, 10), "player")
	pam.station_soldier("outpost_conquest_test", 2)
	_assert(pam.soldier_count == 2, "TC-OGR.20.0: Reserve is 2 while 2 stationed")

	# Evict garrison on outpost conquest with retreat_to_central = true
	var evicted: Array = pam.evict_outpost_garrison("outpost_conquest_test", true)
	_assert(evicted.size() == 2, "TC-OGR.20.1: 2 soldiers evicted from lost outpost")
	_assert(pam.get_garrison_count("outpost_conquest_test") == 0, "TC-OGR.20.2: Garrison reset to 0")
	_assert(not pam.garrisons.has("outpost_conquest_test"), "TC-OGR.20.3: Outpost key cleanly removed from garrisons")
	_assert(pam.soldier_count == 4, "TC-OGR.20.4: Surviving evicted soldiers safely returned to central reserve")
	_assert(pam.get_total_soldier_count() == 4, "TC-OGR.20.5: Total living soldier conservation strictly preserved")

# -----------------------------------------------------------------------------
# 21. TC-OGR.21: Multiple Simultaneous Garrisons
# -----------------------------------------------------------------------------
func _test_tc_ogr_21_multiple_simultaneous_garrisons() -> void:
	print("\n--- TC-OGR.21: Multiple Simultaneous Garrisons Across Realm ---")
	var pam = PlayerArmyManagerScript.new()
	pam.soldier_count = 10
	pam.register_outpost_for_testing("outpost_multi_1", 3, Vector2i(5, 5), "player")
	pam.register_outpost_for_testing("outpost_multi_2", 3, Vector2i(15, 15), "player")
	pam.register_outpost_for_testing("outpost_multi_3", 3, Vector2i(25, 25), "player")

	pam.station_soldier("outpost_multi_1", 2)
	pam.station_soldier("outpost_multi_2", 3)
	pam.station_soldier("outpost_multi_3", 1)

	_assert(pam.get_garrison_count("outpost_multi_1") == 2, "TC-OGR.21.1: Outpost 1 has 2 soldiers")
	_assert(pam.get_garrison_count("outpost_multi_2") == 3, "TC-OGR.21.2: Outpost 2 has 3 soldiers")
	_assert(pam.get_garrison_count("outpost_multi_3") == 1, "TC-OGR.21.3: Outpost 3 has 1 soldier")
	_assert(pam.get_all_garrisoned_count() == 6, "TC-OGR.21.4: Total garrisoned across realm is 6")
	_assert(pam.soldier_count == 4, "TC-OGR.21.5: Central reserve is 4")
	_assert(pam.get_total_soldier_count() == 10, "TC-OGR.21.6: Global total is 10")

# -----------------------------------------------------------------------------
# 22. TC-OGR.22: Outpost Lost in Transit Retreats Safely
# -----------------------------------------------------------------------------
func _test_tc_ogr_22_outpost_lost_in_transit_retreats_safely() -> void:
	print("\n--- TC-OGR.22: Outpost Lost in Transit Retreats Safely to Central Reserve ---")
	var pam = PlayerArmyManagerScript.new()
	pam.soldier_count = 5
	pam.register_outpost_for_testing("outpost_lost_transit", 4, Vector2i(10, 10), "player")

	pam.dispatch_reinforcements("outpost_lost_transit", 2, 2.0)
	_assert(pam.soldier_count == 3, "TC-OGR.22.1: Central reserve is 3 during transit")

	# Mark outpost lost before arrival
	pam._test_registered_outposts["outpost_lost_transit"]["owner"] = "rival_military"

	# Complete transit
	pam.advance_reinforcements(3.0)
	_assert(pam.get_garrison_count("outpost_lost_transit") == 0, "TC-OGR.22.2: No troops stationed at hostile outpost")
	_assert(pam.soldier_count == 5, "TC-OGR.22.3: Soldiers retreated safely to central reserve (5 total)")
	_assert(pam.get_total_soldier_count() == 5, "TC-OGR.22.4: Conservation invariant preserved")

# -----------------------------------------------------------------------------
# 23. TC-OGR.23: HUD Inspection Wiring
# -----------------------------------------------------------------------------
func _test_tc_ogr_23_hud_inspection_wiring() -> void:
	print("\n--- TC-OGR.23: HUD Outpost & Building Inspection UI Wiring ---")
	var hud = world_instance.get_node_or_null("HUD")
	_assert(hud != null, "TC-OGR.23.1: HUD node exists in WorldView")

	var pam = world_instance.get("player_army_mgr")
	if pam != null:
		pam.soldier_count = 5
		pam.register_outpost_for_testing("outpost_hud_test", 4, Vector2i(10, 10), "player")
		pam.station_soldier("outpost_hud_test", 2)

	# Show building inspector with outpost data
	var outpost_ui_data := {
		"id": "outpost_hud_test",
		"type": "outpost",
		"name": "Tiền Đồn Thử Nghiệm",
		"cell": Vector2i(10, 10),
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 250,
		"max_health": 250,
		"owner": "player",
		"is_outpost": true,
		"is_under_siege": false
	}
	hud.show_building_inspector(outpost_ui_data)

	var gar_sec = hud.get_node_or_null("BuildingInspectPanel/MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/GarrisonSection")
	_assert(gar_sec != null and gar_sec.visible == true, "TC-OGR.23.2: GarrisonSection visible in BuildingInspectPanel")

	var count_lbl: Label = hud.get_node_or_null("BuildingInspectPanel/MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/GarrisonSection/GarrisonCountLabel")
	_assert(count_lbl != null and "2 / 4" in count_lbl.text, "TC-OGR.23.3: GarrisonCountLabel displays '2 / 4'")

	hud.close_building_inspector()

# -----------------------------------------------------------------------------
# 24. TC-OGR.24: SaveManager Persistence Roundtrip
# -----------------------------------------------------------------------------
func _test_tc_ogr_24_save_manager_persistence_roundtrip() -> void:
	print("\n--- TC-OGR.24: SaveManager Persistence Disk Roundtrip ---")
	var pam = world_instance.get("player_army_mgr")
	_assert(pam != null, "TC-OGR.24.1: PlayerArmyManager available in WorldView")

	pam.garrisons.clear()
	pam.active_reinforcements.clear()
	pam.soldier_count = 6
	pam.equipment_tier = 2
	pam.register_outpost_for_testing("outpost_save_test", 4, Vector2i(12, 12), "player")
	pam.station_soldier("outpost_save_test", 2)
	pam.dispatch_reinforcements("outpost_save_test", 1, 3.0)

	var test_slot_path := "user://test_package_3a_roundtrip.json"
	var save_res: Dictionary = SaveManagerScript.save_to_file(world_instance, test_slot_path)
	_assert(save_res.get("success", false) == true, "TC-OGR.24.2: SaveManager successfully wrote state to disk")

	# Reset state before loading
	pam.garrisons.clear()
	pam.active_reinforcements.clear()
	pam.soldier_count = 0

	var load_res: Dictionary = SaveManagerScript.load_from_file(test_slot_path)
	_assert(load_res.get("success", false) == true, "TC-OGR.24.3: SaveManager load returns success")

	var loaded_data: Dictionary = load_res.get("data", {})
	var apply_res: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, loaded_data)
	_assert(apply_res.get("success", false) == true, "TC-OGR.24.4: apply_loaded_state_to_world returns true")

	_assert(pam.soldier_count == 3, "TC-OGR.24.5: Restored central reserve is 3")
	_assert(pam.get_garrison_count("outpost_save_test") == 2, "TC-OGR.24.6: Restored outpost garrison is 2")
	_assert(pam.get_in_transit_count("outpost_save_test") == 1, "TC-OGR.24.7: Restored in-transit reinforcement is 1")
	_assert(pam.get_total_soldier_count() == 6, "TC-OGR.24.8: Conservation invariant holds across disk roundtrip")

	# Outpost ownership loss eviction followed by second disk save/load roundtrip
	pam.evict_outpost_garrison("outpost_save_test", true)
	_assert(pam.soldier_count == 5, "TC-OGR.24.9: Central reserve restored to 5 on outpost eviction")
	_assert(pam.get_garrison_count("outpost_save_test") == 0, "TC-OGR.24.10: Outpost garrison cleared to 0")
	_assert(pam.get_total_soldier_count() == 6, "TC-OGR.24.11: Conservation invariant holds (5 reserve + 1 transit)")

	var save_res_2 = SaveManagerScript.save_to_file(world_instance, test_slot_path)
	_assert(save_res_2.get("success", false) == true, "TC-OGR.24.12: Second save succeeded")
	pam.soldier_count = 0
	var load_res_2 = SaveManagerScript.load_from_file(test_slot_path)
	SaveManagerScript.apply_loaded_state_to_world(world_instance, load_res_2.get("data", {}))
	_assert(pam.soldier_count == 5, "TC-OGR.24.13: Post-eviction reserve reloaded as 5")
	_assert(pam.get_garrison_count("outpost_save_test") == 0, "TC-OGR.24.14: Post-eviction garrison reloaded as 0")
	_assert(pam.get_total_soldier_count() == 6, "TC-OGR.24.15: Conservation invariant preserved after eviction reload")

	# Clean up disk file
	if FileAccess.file_exists(test_slot_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_slot_path))

# -----------------------------------------------------------------------------
# 25. TC-OGR.25: SaveManager Legacy Backward Compatibility
# -----------------------------------------------------------------------------
func _test_tc_ogr_25_save_manager_legacy_backward_compatibility() -> void:
	print("\n--- TC-OGR.25: SaveManager Legacy Backward Compatibility ---")
	var pam = PlayerArmyManagerScript.new()
	var legacy_dict := {
		"soldier_count": 5,
		"equipment_tier": 1,
		"is_supplied": true,
		"last_upkeep_day": 2,
		"current_cell": [32, 33],
		"rally_cell": [32, 33],
		"destination_cell": [32, 33],
		"movement_state": "garrisoned",
		"current_path": []
	}

	pam.deserialize(legacy_dict)
	_assert(pam.soldier_count == 5, "TC-OGR.25.1: Legacy soldier_count loaded correctly")
	_assert(pam.garrisons.is_empty(), "TC-OGR.25.2: Legacy save cleanly defaults garrisons to empty")
	_assert(pam.active_reinforcements.is_empty(), "TC-OGR.25.3: Legacy save cleanly defaults reinforcements to empty")
	_assert(pam.get_total_soldier_count() == 5, "TC-OGR.25.4: Total soldier count matches legacy soldier_count")

# -----------------------------------------------------------------------------
# 26. TC-OGR.26: Idempotency & Invalid Inputs
# -----------------------------------------------------------------------------
func _test_tc_ogr_26_idempotency_and_invalid_inputs() -> void:
	print("\n--- TC-OGR.26: Idempotency and Fail-Closed Negative Input Handling ---")
	var pam = PlayerArmyManagerScript.new()
	pam.soldier_count = 5

	var res_neg_stat: Dictionary = pam.station_soldier("any_id", -2)
	_assert(res_neg_stat.get("success", true) == false, "TC-OGR.26.1: Negative station count rejected fail-closed")

	var res_zero_stat: Dictionary = pam.station_soldier("any_id", 0)
	_assert(res_zero_stat.get("success", true) == false, "TC-OGR.26.2: Zero station count rejected fail-closed")

	var res_neg_rec: Dictionary = pam.recall_soldier("any_id", -1)
	_assert(res_neg_rec.get("success", true) == false, "TC-OGR.26.3: Negative recall count rejected fail-closed")

	var res_neg_disp: Dictionary = pam.dispatch_reinforcements("any_id", -3)
	_assert(res_neg_disp.get("success", true) == false, "TC-OGR.26.4: Negative dispatch count rejected fail-closed")

	_assert(pam.soldier_count == 5, "TC-OGR.26.5: Soldier count completely unaffected by invalid operations")

# =============================================================================
# PACKAGE 3A FOLLOW-UP: OUTPOST CAPACITY CORRECTNESS (TC-CAP.01 to TC-CAP.08)
# =============================================================================

# -----------------------------------------------------------------------------
# 27. TC-CAP.01: Legacy Field Siege Save Missing Capacity
# -----------------------------------------------------------------------------
func _test_tc_cap_01_legacy_save_missing_capacity() -> void:
	print("\n--- TC-CAP.01: Legacy Field Siege Save Missing Capacity ---")
	var legacy_dict := {
		"objective_id": "outpost_legacy_missing",
		"objective_name": "Tiền Đồn Cũ",
		"owning_faction_id": "player",
		"current_cell": [10, 10],
		"health": 250.0,
		"max_health": 250.0,
		"is_alive": true
	}
	var actor := SiegeObjectiveActorScript.new()
	var deser_ok: bool = actor.deserialize(legacy_dict)
	_assert(deser_ok, "TC-CAP.01.1: Actor deserialized legacy dictionary successfully")
	_assert(actor.garrison_count == 3, "TC-CAP.01.2: Actor garrison_count defaulted to 3")
	actor.free()

	var fsm := FieldSiegeManagerScript.new()
	fsm.deserialize({"objectives": [legacy_dict]})
	_assert(fsm.get_objective("outpost_legacy_missing") != null, "TC-CAP.01.3: Objective registered in FSM")

	var pam := PlayerArmyManagerScript.new()
	pam._custom_field_siege_mgr = fsm
	var info := pam.get_outpost_info("outpost_legacy_missing")
	_assert(int(info.get("capacity", -1)) == 3, "TC-CAP.01.4: PlayerArmyManager get_outpost_info returns capacity = 3")
	_assert(pam.get_garrison_capacity("outpost_legacy_missing") == 3, "TC-CAP.01.5: get_garrison_capacity returns 3")

# -----------------------------------------------------------------------------
# 28. TC-CAP.02: Invalid Zero Capacity
# -----------------------------------------------------------------------------
func _test_tc_cap_02_invalid_zero_capacity() -> void:
	print("\n--- TC-CAP.02: Invalid Zero Capacity ---")
	var zero_dict := {
		"objective_id": "outpost_zero_cap",
		"objective_name": "Tiền Đồn Không",
		"owning_faction_id": "player",
		"current_cell": [12, 12],
		"health": 250.0,
		"max_health": 250.0,
		"is_alive": true,
		"garrison_count": 0
	}
	var actor := SiegeObjectiveActorScript.new()
	actor.deserialize(zero_dict)
	_assert(actor.garrison_count == 3, "TC-CAP.02.1: Actor normalized zero garrison_count to 3")
	actor.free()

	var fsm := FieldSiegeManagerScript.new()
	fsm.deserialize({"objectives": [zero_dict]})
	var pam := PlayerArmyManagerScript.new()
	pam._custom_field_siege_mgr = fsm
	var info := pam.get_outpost_info("outpost_zero_cap")
	_assert(int(info.get("capacity", -1)) == 3, "TC-CAP.02.2: Final capacity for zero capacity save resolves to 3")
	_assert(pam.get_garrison_capacity("outpost_zero_cap") == 3, "TC-CAP.02.3: get_garrison_capacity resolves to 3")

# -----------------------------------------------------------------------------
# 29. TC-CAP.03: Negative Capacity
# -----------------------------------------------------------------------------
func _test_tc_cap_03_negative_capacity() -> void:
	print("\n--- TC-CAP.03: Negative Capacity ---")
	var neg_dict := {
		"objective_id": "outpost_neg_cap",
		"objective_name": "Tiền Đồn Âm",
		"owning_faction_id": "player",
		"current_cell": [14, 14],
		"health": 250.0,
		"max_health": 250.0,
		"is_alive": true,
		"garrison_count": -5
	}
	var actor := SiegeObjectiveActorScript.new()
	actor.deserialize(neg_dict)
	_assert(actor.garrison_count == 3, "TC-CAP.03.1: Actor normalized negative garrison_count to 3")
	actor.free()

	var fsm := FieldSiegeManagerScript.new()
	fsm.deserialize({"objectives": [neg_dict]})
	var pam := PlayerArmyManagerScript.new()
	pam._custom_field_siege_mgr = fsm
	var info := pam.get_outpost_info("outpost_neg_cap")
	_assert(int(info.get("capacity", -1)) == 3, "TC-CAP.03.2: Final capacity for negative capacity save resolves to 3")

	var neg_reg = fsm.register_objective("outpost_neg_reg", Vector2i(15, 15), "player", 250.0, -2)
	_assert(neg_reg.garrison_count == 3, "TC-CAP.03.3: register_objective normalized negative capacity to 3")
	var info_reg := pam.get_outpost_info("outpost_neg_reg")
	_assert(int(info_reg.get("capacity", -1)) == 3, "TC-CAP.03.4: get_outpost_info for registered negative capacity resolves to 3")

# -----------------------------------------------------------------------------
# 30. TC-CAP.04: Explicit Capacity Preservation
# -----------------------------------------------------------------------------
func _test_tc_cap_04_explicit_capacity_preservation() -> void:
	print("\n--- TC-CAP.04: Explicit Capacity Preservation ---")
	var caps := [2, 4, 5]
	for c in caps:
		var d := {
			"objective_id": "outpost_exp_%d" % c,
			"objective_name": "Tiền Đồn %d" % c,
			"owning_faction_id": "player",
			"current_cell": [16 + c, 16],
			"health": 250.0,
			"max_health": 250.0,
			"is_alive": true,
			"garrison_count": c
		}
		var actor := SiegeObjectiveActorScript.new()
		actor.deserialize(d)
		_assert(actor.garrison_count == c, "TC-CAP.04.1_%d: Actor preserved explicit capacity %d" % [c, c])
		actor.free()

		var fsm := FieldSiegeManagerScript.new()
		fsm.deserialize({"objectives": [d]})
		var pam := PlayerArmyManagerScript.new()
		pam._custom_field_siege_mgr = fsm
		var info := pam.get_outpost_info("outpost_exp_%d" % c)
		_assert(int(info.get("capacity", -1)) == c, "TC-CAP.04.2_%d: get_outpost_info preserved explicit capacity %d" % [c, c])
		_assert(pam.get_garrison_capacity("outpost_exp_%d" % c) == c, "TC-CAP.04.3_%d: get_garrison_capacity preserved explicit capacity %d" % [c, c])

# -----------------------------------------------------------------------------
# 31. TC-CAP.05: New Objective Default
# -----------------------------------------------------------------------------
func _test_tc_cap_05_new_objective_default() -> void:
	print("\n--- TC-CAP.05: New Objective Default ---")
	var fsm := FieldSiegeManagerScript.new()
	var obj = fsm.register_objective("outpost_new_default", Vector2i(22, 22), "player")
	_assert(obj.garrison_count == 3, "TC-CAP.05.1: register_objective default parameter is 3")

	var pam := PlayerArmyManagerScript.new()
	pam._custom_field_siege_mgr = fsm
	var info := pam.get_outpost_info("outpost_new_default")
	_assert(int(info.get("capacity", -1)) == 3, "TC-CAP.05.2: get_outpost_info returns 3 for new default objective")
	_assert(pam.get_garrison_capacity("outpost_new_default") == 3, "TC-CAP.05.3: get_garrison_capacity returns 3")

# -----------------------------------------------------------------------------
# 32. TC-CAP.06: Legacy Pre-Package-1X Default Objectives
# -----------------------------------------------------------------------------
func _test_tc_cap_06_legacy_pre_package_1x_default_objectives() -> void:
	print("\n--- TC-CAP.06: Legacy Pre-Package-1X Default Objectives ---")
	_assert(world_instance.has_method("_setup_default_siege_objectives"), "TC-CAP.06.1: WorldView has _setup_default_siege_objectives")
	var fsm_wv = world_instance.get("field_siege_mgr")
	if fsm_wv != null:
		var obj_mil = fsm_wv.get_objective("outpost_rival_military")
		if obj_mil != null:
			_assert(obj_mil.garrison_count == 4, "TC-CAP.06.2: Historical rival_military capacity 4 preserved")
		var obj_mer = fsm_wv.get_objective("outpost_rival_merchant")
		if obj_mer != null:
			_assert(obj_mer.garrison_count == 3, "TC-CAP.06.3: Historical rival_merchant capacity 3 preserved")
		var obj_tri = fsm_wv.get_objective("outpost_neutral_tribe")
		if obj_tri != null:
			_assert(obj_tri.garrison_count == 2, "TC-CAP.06.4: Historical neutral_tribe capacity 2 preserved")

# -----------------------------------------------------------------------------
# 33. TC-CAP.07: Save/Load Persistence
# -----------------------------------------------------------------------------
func _test_tc_cap_07_save_load_persistence() -> void:
	print("\n--- TC-CAP.07: Save/Load Persistence ---")
	var test_slot := "user://test_cap_persistence.json"
	var pam_live = world_instance.get("player_army_mgr")
	var fsm_live = world_instance.get("field_siege_mgr")
	_assert(pam_live != null and fsm_live != null, "TC-CAP.07.1: Live PAM and FSM available in WorldView")

	# Register an objective with explicit capacity 5
	var obj_persist = fsm_live.register_objective("outpost_persist_cap5", Vector2i(25, 25), "player", 250.0, 5)
	pam_live.soldier_count = 10
	pam_live.station_soldier("outpost_persist_cap5", 2)

	var save_res = SaveManagerScript.save_to_file(world_instance, test_slot)
	_assert(save_res.get("success", false) == true, "TC-CAP.07.2: SaveManager successfully saved state")

	var load_res = SaveManagerScript.load_from_file(test_slot)
	_assert(load_res.get("success", false) == true, "TC-CAP.07.3: SaveManager load returned success")
	var loaded_data: Dictionary = load_res.get("data", {})
	var apply_res = SaveManagerScript.apply_loaded_state_to_world(world_instance, loaded_data)
	_assert(apply_res.get("success", false) == true, "TC-CAP.07.4: apply_loaded_state_to_world returned success")

	_assert(pam_live.get_garrison_capacity("outpost_persist_cap5") == 5, "TC-CAP.07.5: Post-load garrison capacity remains 5")
	_assert(pam_live.get_garrison_count("outpost_persist_cap5") == 2, "TC-CAP.07.6: Post-load garrison count remains 2")

	# Legacy missing-field simulation through real SaveManager.apply_loaded_state_to_world
	var legacy_loaded_data = loaded_data.duplicate(true)
	if legacy_loaded_data.has("field_siege") and legacy_loaded_data["field_siege"].has("objectives"):
		var objs: Array = legacy_loaded_data["field_siege"]["objectives"]
		objs.append({
			"objective_id": "outpost_legacy_disk_sim",
			"objective_name": "Tiền Đồn Cũ Disk",
			"owning_faction_id": "player",
			"current_cell": [28, 28],
			"health": 250.0,
			"max_health": 250.0,
			"is_alive": true
			# Missing garrison_count
		})
		var apply_leg_res = SaveManagerScript.apply_loaded_state_to_world(world_instance, legacy_loaded_data)
		_assert(apply_leg_res.get("success", false) == true, "TC-CAP.07.7: Legacy missing-field state applied cleanly")
		_assert(pam_live.get_garrison_capacity("outpost_legacy_disk_sim") == 3, "TC-CAP.07.8: Legacy missing-field outpost resolved capacity to 3 via real SaveManager apply")

	if FileAccess.file_exists(test_slot):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_slot))

# -----------------------------------------------------------------------------
# 34. TC-CAP.08: Soldier Conservation
# -----------------------------------------------------------------------------
func _test_tc_cap_08_soldier_conservation() -> void:
	print("\n--- TC-CAP.08: Soldier Conservation ---")
	var pam_c = PlayerArmyManagerScript.new()
	var fsm_c = FieldSiegeManagerScript.new()
	pam_c._custom_field_siege_mgr = fsm_c
	var out_c = fsm_c.register_objective("outpost_cons_1", Vector2i(10, 10), "player")
	pam_c.soldier_count = 10

	# Station 2 soldiers (cap is 3)
	var stat_res = pam_c.station_soldier("outpost_cons_1", 2)
	_assert(stat_res.get("success", false) == true, "TC-CAP.08.1: Stationed 2 soldiers")
	_assert(pam_c.soldier_count == 8, "TC-CAP.08.2: Central reserve reduced by exactly 2")
	_assert(pam_c.get_total_soldier_count() == 10, "TC-CAP.08.3: Total soldier count conserved at 10")

	# Dispatch 1 reinforcement (cur 2 + 1 transit <= cap 3)
	var disp_res = pam_c.dispatch_reinforcements("outpost_cons_1", 1, 2.0)
	_assert(disp_res.get("success", false) == true, "TC-CAP.08.4: Dispatched 1 reinforcement")
	_assert(pam_c.soldier_count == 7, "TC-CAP.08.5: Central reserve reduced to 7")
	_assert(pam_c.get_in_transit_count("outpost_cons_1") == 1, "TC-CAP.08.6: In-transit count is 1")
	_assert(pam_c.get_total_soldier_count() == 10, "TC-CAP.08.7: Total soldier count conserved at 10 (7 + 2 + 1)")

	# Reject stationing beyond cap (cur 2 + transit 1 + attempt 1 > cap 3)
	var over_res = pam_c.station_soldier("outpost_cons_1", 1)
	_assert(over_res.get("success", true) == false, "TC-CAP.08.8: Over-capacity station rejected")
	_assert(pam_c.get_total_soldier_count() == 10, "TC-CAP.08.9: Total soldiers strictly conserved after rejection")

	# Advance arrival
	pam_c.advance_reinforcements(2.5)
	_assert(pam_c.get_in_transit_count("outpost_cons_1") == 0, "TC-CAP.08.10: Transit completed")
	_assert(pam_c.get_garrison_count("outpost_cons_1") == 3, "TC-CAP.08.11: Garrison count is 3")
	_assert(pam_c.get_total_soldier_count() == 10, "TC-CAP.08.12: Conservation holds after reinforcement arrival")

	# Apply casualties (1 casualty)
	var cas_removed = pam_c.apply_outpost_casualties("outpost_cons_1", 1)
	_assert(cas_removed == 1, "TC-CAP.08.13: Exactly 1 casualty removed")
	_assert(pam_c.get_garrison_count("outpost_cons_1") == 2, "TC-CAP.08.14: Garrison count now 2")
	_assert(pam_c.get_total_soldier_count() == 9, "TC-CAP.08.15: Total soldier count decremented exactly once to 9")

	# Evict outpost garrison on ownership loss (retreat to central)
	pam_c.evict_outpost_garrison("outpost_cons_1", true)
	_assert(pam_c.get_garrison_count("outpost_cons_1") == 0, "TC-CAP.08.16: Garrison evicted to 0")
	_assert(pam_c.soldier_count == 9, "TC-CAP.08.17: Central reserve restored to 9 (7 + 2)")
	_assert(pam_c.get_total_soldier_count() == 9, "TC-CAP.08.18: Final conservation holds at 9 with zero leaks")
