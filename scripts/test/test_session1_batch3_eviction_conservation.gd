extends SceneTree
## Test Suite: Batch 3 Outpost Demolition & Destruction Eviction & Conservation
## Validates MBL-MIL-01:
## - Garrison and in-transit reinforcement conservation on demolition and destruction
## - Damaged building preservation of garrison
## - Same-tick / simulation advance race conditions
## - Idempotent eviction and transit cancellation
## - Branch 3 guard in get_outpost_info for demolished buildings

const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")
const PlayerArmyManagerScript = preload("res://scripts/military/player_army_manager.gd")

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
	print("  STARTING BATCH 3 EVICTION & CONSERVATION TEST SUITE")
	print("========================================================\n")
	world_instance = WorldViewScene.instantiate()
	world_instance.world_seed = 4242
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count >= 3 and not tests_executed:
		tests_executed = true
		_run_all_tests()
	return false

func _create_active_watchtower(b_id: String, cell: Vector2i) -> Dictionary:
	var wd = world_instance.world_data
	var b_data := {
		"id": b_id,
		"type": "watchtower",
		"cell": cell,
		"size": Vector2i(1, 1),
		"state": "active",
		"health": 100,
		"max_health": 100
	}
	wd.buildings.append(b_data)
	world_instance.buildings_by_cell[cell] = b_data
	world_instance._instantiate_building_node("watchtower", cell, Vector2i(1, 1), "active")
	return b_data

func _run_all_tests() -> void:
	var pam = world_instance.player_army_mgr
	var tmm = world_instance.tactical_military_mgr
	var wd = world_instance.world_data

	_assert(pam != null and tmm != null and wd != null, "Core managers initialized")

	# Setup initial army state: 10 soldiers
	pam.soldier_count = 10
	tmm.sync_with_player_army()
	_assert(pam.soldier_count == 10, "Initial army soldier_count is 10")
	_assert(tmm.units.size() == 10, "Initial tactical units size is 10")
	var initial_total: int = pam.get_total_soldier_count()
	_assert(initial_total == 10, "Initial total soldier count is 10")

	# =========================================================================
	# Test 1 (TC-B3.01): Demolish Watchtower with Stationed Garrison
	# =========================================================================
	print("\n--- TC-B3.01: Demolish Watchtower with Stationed Garrison ---")
	var wt1: Dictionary = _create_active_watchtower("bld_watchtower_10_10", Vector2i(10, 10))
	var stat_res1: Dictionary = pam.station_soldier("bld_watchtower_10_10", 2)
	_assert(stat_res1.get("success", false) == true, "TC-B3.01.1: Stationed 2 soldiers in watchtower 1")
	_assert(pam.soldier_count == 8, "TC-B3.01.2: Central soldier count reduced to 8")
	_assert(pam.get_garrison_count("bld_watchtower_10_10") == 2, "TC-B3.01.3: Garrison count is 2")
	_assert(pam.get_total_soldier_count() == 10, "TC-B3.01.4: Total soldier count remains 10")

	var demo_res1: Dictionary = world_instance.demolish_building_project("bld_watchtower_10_10")
	_assert(demo_res1.get("success", false) == true, "TC-B3.01.5: demolish_building_project succeeded")
	_assert(not pam.garrisons.has("bld_watchtower_10_10"), "TC-B3.01.6: Garrison record evicted from PlayerArmyManager")
	_assert(pam.soldier_count == 10, "TC-B3.01.7: 2 soldiers refunded to central army (soldier_count == 10)")
	_assert(tmm.units.size() == 10, "TC-B3.01.8: Tactical units synced to 10")
	_assert(pam.get_total_soldier_count() == 10, "TC-B3.01.9: Total soldier count conserved at 10")
	var info_post_demo1: Dictionary = pam.get_outpost_info("bld_watchtower_10_10")
	_assert(info_post_demo1.get("valid", false) == false, "TC-B3.01.10: Demolished outpost returns valid: false")

	# =========================================================================
	# Test 2 (TC-B3.02): Destroy Watchtower via set_building_state("destroyed")
	# =========================================================================
	print("\n--- TC-B3.02: Destroy Watchtower via set_building_state('destroyed') ---")
	var wt2: Dictionary = _create_active_watchtower("bld_watchtower_12_12", Vector2i(12, 12))
	var stat_res2: Dictionary = pam.station_soldier("bld_watchtower_12_12", 2)
	_assert(stat_res2.get("success", false) == true, "TC-B3.02.1: Stationed 2 soldiers in watchtower 2")
	_assert(pam.soldier_count == 8, "TC-B3.02.2: Central soldier count reduced to 8")
	_assert(pam.get_garrison_count("bld_watchtower_12_12") == 2, "TC-B3.02.3: Garrison count is 2")

	var dest_res2: bool = world_instance.set_building_state("bld_watchtower_12_12", "destroyed")
	_assert(dest_res2 == true, "TC-B3.02.4: set_building_state('destroyed') succeeded")
	_assert(not pam.garrisons.has("bld_watchtower_12_12"), "TC-B3.02.5: Garrison record evicted on destruction")
	_assert(pam.soldier_count == 10, "TC-B3.02.6: 2 soldiers refunded to central army (soldier_count == 10)")
	_assert(tmm.units.size() == 10, "TC-B3.02.7: Tactical units synced to 10")
	_assert(pam.get_total_soldier_count() == 10, "TC-B3.02.8: Total soldier count conserved at 10")
	var info_post_dest2: Dictionary = pam.get_outpost_info("bld_watchtower_12_12")
	_assert(info_post_dest2.get("valid", false) == false, "TC-B3.02.9: Destroyed outpost returns valid: false")

	# =========================================================================
	# Test 3 (TC-B3.03): Damaged Watchtower Preserves Garrison
	# =========================================================================
	print("\n--- TC-B3.03: Damaged Watchtower Preserves Garrison ---")
	var wt3: Dictionary = _create_active_watchtower("bld_watchtower_14_14", Vector2i(14, 14))
	var stat_res3: Dictionary = pam.station_soldier("bld_watchtower_14_14", 2)
	_assert(stat_res3.get("success", false) == true, "TC-B3.03.1: Stationed 2 soldiers in watchtower 3")
	_assert(pam.soldier_count == 8, "TC-B3.03.2: Central soldier count is 8")

	var dmg_res3: bool = world_instance.set_building_state("bld_watchtower_14_14", "damaged")
	_assert(dmg_res3 == true, "TC-B3.03.3: set_building_state('damaged') succeeded")
	_assert(pam.garrisons.has("bld_watchtower_14_14"), "TC-B3.03.4: Garrison preserved in damaged building")
	_assert(pam.get_garrison_count("bld_watchtower_14_14") == 2, "TC-B3.03.5: Garrison count remains 2")
	_assert(pam.soldier_count == 8, "TC-B3.03.6: Central reserve unchanged at 8")
	_assert(pam.get_total_soldier_count() == 10, "TC-B3.03.7: Total soldier count conserved at 10")

	# Clean up wt3 for subsequent tests
	pam.evict_outpost_garrison("bld_watchtower_14_14", true)
	_assert(pam.soldier_count == 10, "TC-B3.03.8: Restored central army to 10")

	# =========================================================================
	# Test 4 (TC-B3.04): Demolish Watchtower with In-Transit Reinforcements
	# =========================================================================
	print("\n--- TC-B3.04: Demolish Watchtower with In-Transit Reinforcements ---")
	var wt4: Dictionary = _create_active_watchtower("bld_watchtower_16_16", Vector2i(16, 16))
	var reinf_res4: Dictionary = pam.dispatch_reinforcements("bld_watchtower_16_16", 2, 5.0)
	_assert(reinf_res4.get("success", false) == true, "TC-B3.04.1: Dispatched 2 reinforcements")
	_assert(pam.soldier_count == 8, "TC-B3.04.2: Central soldier count reduced to 8")
	_assert(pam.get_in_transit_count("bld_watchtower_16_16") == 2, "TC-B3.04.3: In-transit count is 2")
	_assert(pam.get_total_soldier_count() == 10, "TC-B3.04.4: Total soldier count conserved at 10")

	var demo_res4: Dictionary = world_instance.demolish_building_project("bld_watchtower_16_16")
	_assert(demo_res4.get("success", false) == true, "TC-B3.04.5: Demolish succeeded")
	_assert(pam.get_in_transit_count("bld_watchtower_16_16") == 0, "TC-B3.04.6: In-transit record cancelled")
	_assert(pam.soldier_count == 10, "TC-B3.04.7: In-transit soldiers refunded to central army (soldier_count == 10)")
	_assert(tmm.units.size() == 10, "TC-B3.04.8: Tactical units synced to 10")
	_assert(pam.get_total_soldier_count() == 10, "TC-B3.04.9: Total soldier count conserved at 10")

	# =========================================================================
	# Test 5 (TC-B3.05): Destroy Watchtower with BOTH Garrison and In-Transit Reinforcements
	# =========================================================================
	print("\n--- TC-B3.05: Destroy Watchtower with BOTH Garrison and In-Transit Reinforcements ---")
	var wt5: Dictionary = _create_active_watchtower("bld_watchtower_18_18", Vector2i(18, 18))
	var stat_res5: Dictionary = pam.station_soldier("bld_watchtower_18_18", 1)
	_assert(stat_res5.get("success", false) == true, "TC-B3.05.1: Stationed 1 soldier")
	var reinf_res5: Dictionary = pam.dispatch_reinforcements("bld_watchtower_18_18", 1, 4.0)
	_assert(reinf_res5.get("success", false) == true, "TC-B3.05.2: Dispatched 1 reinforcement")
	_assert(pam.soldier_count == 8, "TC-B3.05.3: Central soldier count is 8")
	_assert(pam.get_garrison_count("bld_watchtower_18_18") == 1, "TC-B3.05.4: Garrison count is 1")
	_assert(pam.get_in_transit_count("bld_watchtower_18_18") == 1, "TC-B3.05.5: In-transit count is 1")
	_assert(pam.get_total_soldier_count() == 10, "TC-B3.05.6: Total soldiers is 10")

	var dest_res5: bool = world_instance.set_building_state("bld_watchtower_18_18", "destroyed")
	_assert(dest_res5 == true, "TC-B3.05.7: Destroy succeeded")
	_assert(not pam.garrisons.has("bld_watchtower_18_18"), "TC-B3.05.8: Garrison evicted")
	_assert(pam.get_in_transit_count("bld_watchtower_18_18") == 0, "TC-B3.05.9: In-transit cancelled")
	_assert(pam.soldier_count == 10, "TC-B3.05.10: Exactly 2 soldiers refunded (soldier_count == 10)")
	_assert(tmm.units.size() == 10, "TC-B3.05.11: Tactical units synced to 10")
	_assert(pam.get_total_soldier_count() == 10, "TC-B3.05.12: Total soldier count conserved at 10")

	# =========================================================================
	# Test 6 (TC-B3.06): Simulation Advance Race Conditions (Order A & Order B)
	# =========================================================================
	print("\n--- TC-B3.06: Simulation Advance Race Conditions ---")
	# Order A: Demolition before advance
	var wt6a: Dictionary = _create_active_watchtower("bld_watchtower_20_20", Vector2i(20, 20))
	pam.dispatch_reinforcements("bld_watchtower_20_20", 2, 2.0)
	_assert(pam.soldier_count == 8, "TC-B3.06.1: Dispatched 2 soldiers, central count is 8")
	world_instance.demolish_building_project("bld_watchtower_20_20")
	_assert(pam.soldier_count == 10, "TC-B3.06.2: Demolition refunded 2 soldiers to 10")
	# Now advance simulation past travel time: should have 0 active records, no double refund
	var arrivals_a: Array = pam.advance_reinforcements(5.0)
	_assert(arrivals_a.is_empty(), "TC-B3.06.3: No arrivals completed after proactive cancellation")
	_assert(pam.soldier_count == 10, "TC-B3.06.4: Zero double refund after advance (soldier_count == 10)")
	_assert(pam.get_total_soldier_count() == 10, "TC-B3.06.5: Conservation holds under Order A")

	# Order B: Advance before demolition
	var wt6b: Dictionary = _create_active_watchtower("bld_watchtower_22_22", Vector2i(22, 22))
	pam.dispatch_reinforcements("bld_watchtower_22_22", 2, 1.0)
	_assert(pam.soldier_count == 8, "TC-B3.06.6: Dispatched 2 soldiers, central count is 8")
	var arrivals_b: Array = pam.advance_reinforcements(2.0)
	_assert(arrivals_b.size() == 1, "TC-B3.06.7: Reinforcements arrived at valid outpost before demolition")
	_assert(pam.get_garrison_count("bld_watchtower_22_22") == 2, "TC-B3.06.8: Soldiers now stationed in garrison")
	_assert(pam.soldier_count == 8, "TC-B3.06.9: Central soldier count still 8")
	# Now demolish:
	world_instance.demolish_building_project("bld_watchtower_22_22")
	_assert(pam.soldier_count == 10, "TC-B3.06.10: Demolition evicted the newly arrived garrison (soldier_count == 10)")
	_assert(pam.get_total_soldier_count() == 10, "TC-B3.06.11: Conservation holds under Order B")

	# =========================================================================
	# Test 7 (TC-B3.07): Eviction & Transit Cancellation Idempotency
	# =========================================================================
	print("\n--- TC-B3.07: Eviction & Transit Cancellation Idempotency ---")
	var idem_res1: Dictionary = pam.evict_and_cancel_outpost("non_existent_outpost", true)
	_assert(idem_res1.get("total_refunded", -1) == 0, "TC-B3.07.1: Non-existent outpost returns 0 refund")
	_assert(pam.soldier_count == 10, "TC-B3.07.2: Central soldier count unchanged")

	var wt7: Dictionary = _create_active_watchtower("bld_watchtower_24_24", Vector2i(24, 24))
	pam.station_soldier("bld_watchtower_24_24", 2)
	_assert(pam.soldier_count == 8, "TC-B3.07.3: Stationed 2 soldiers")

	var first_call: Dictionary = pam.evict_and_cancel_outpost("bld_watchtower_24_24", true)
	_assert(first_call.get("total_refunded") == 2, "TC-B3.07.4: First call refunds 2 soldiers")
	_assert(pam.soldier_count == 10, "TC-B3.07.5: Central soldier count restored to 10")

	var second_call: Dictionary = pam.evict_and_cancel_outpost("bld_watchtower_24_24", true)
	_assert(second_call.get("total_refunded") == 0, "TC-B3.07.6: Second call is idempotent (0 refund)")
	_assert(pam.soldier_count == 10, "TC-B3.07.7: Central soldier count strictly unchanged at 10")

	var cancel_repeat: int = pam.cancel_outpost_reinforcements("bld_watchtower_24_24", true)
	_assert(cancel_repeat == 0, "TC-B3.07.8: cancel_outpost_reinforcements returns 0 when no transit records exist")
	_assert(pam.soldier_count == 10, "TC-B3.07.9: Central count unchanged at 10")

	# =========================================================================
	# Test 8 (TC-B3.08): Branch 3 Guard in get_outpost_info()
	# =========================================================================
	print("\n--- TC-B3.08: Branch 3 Guard in get_outpost_info() ---")
	# Force an artificial residual entry in garrisons for a demolished building ID
	pam.garrisons["bld_watchtower_ghost_99_99"] = {
		"outpost_id": "bld_watchtower_ghost_99_99",
		"capacity": 2,
		"soldiers": []
	}
	var ghost_info: Dictionary = pam.get_outpost_info("bld_watchtower_ghost_99_99")
	_assert(ghost_info.get("valid", true) == false, "TC-B3.08.1: Ghost demolished building returns valid: false")
	_assert(ghost_info.get("reason", "").contains("dỡ bỏ hoặc không tồn tại"), "TC-B3.08.2: Reason notes demolition or non-existence")
	pam.garrisons.erase("bld_watchtower_ghost_99_99")
	_assert(ghost_info.get("valid", true) == false, "TC-B3.08.1: Ghost demolished building returns valid: false")
	_assert(ghost_info.get("reason", "").contains("dỡ bỏ hoặc không tồn tại"), "TC-B3.08.2: Reason notes demolition or non-existence")
	pam.garrisons.erase("bld_watchtower_ghost_99_99")

	print("\n--------------------------------------------------------")
	print("  BATCH 3 RESULTS: %d Passed, %d Failed" % [passed_count, failures])
	print("--------------------------------------------------------\n")
	quit(0 if failures == 0 else 1)
