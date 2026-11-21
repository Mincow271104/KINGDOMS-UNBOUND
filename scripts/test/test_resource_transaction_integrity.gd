extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — RISK-001: ResourceManager Transaction Integrity
## Verifies atomic reservation, safe commit, idempotent rollback, and caller integration.

const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const ResourceManagerScript = preload("res://scripts/economy/resource_manager.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")
const WorkplaceManagerScript = preload("res://scripts/economy/workplace_manager.gd")
const PlayerArmyManagerScript = preload("res://scripts/military/player_army_manager.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")

var failures: int = 0
var passed_count: int = 0

func _assert(condition: bool, test_name: String, details: String = "") -> void:
	if condition:
		passed_count += 1
		print("  [PASS] %s" % test_name)
	else:
		failures += 1
		printerr("  [FAIL] %s - %s" % [test_name, details])

func _create_test_world_data() -> WorldGenerator.WorldData:
	var wd = WorldGeneratorScript.generate(42)
	return wd

func _init() -> void:
	print("\n========================================================")
	print("  STARTING RISK-001 RESOURCE TRANSACTION INTEGRITY SUITE")
	print("========================================================\n")

	_run_scenario_1_valid_reserve_commit()
	_run_scenario_2_commit_without_reservation_fails_closed()
	_run_scenario_3_double_commit_fails_closed()
	_run_scenario_4_concurrent_reservations_with_limited_stock()
	_run_scenario_5_partial_reservation_all_or_nothing()
	_run_scenario_6_rollback_restores_available_stock()
	_run_scenario_7_double_rollback_fails_closed_no_stealing()
	_run_scenario_8_failed_transaction_invariance()
	_run_scenario_9_building_system_integration()
	_run_scenario_10_player_army_manager_integration()
	_run_scenario_11_workplace_manager_integration()

	print("\n--------------------------------------------------------")
	if failures == 0:
		print("  RISK-001 SUITE: ALL %d SCENARIO CHECKS PASSED! (0 Failures)" % passed_count)
		print("========================================================\n")
		quit(0)
	else:
		printerr("  RISK-001 SUITE: FAILED WITH %d FAILURES (Passed: %d)" % [failures, passed_count])
		print("========================================================\n")
		quit(1)

## Scenario 1: Valid reserve + commit
func _run_scenario_1_valid_reserve_commit() -> void:
	print("--- Scenario 1: Valid Reserve + Commit (Direct & Ticketed) ---")
	var rm = ResourceManagerScript.new()
	root.add_child(rm)
	rm.reset_economy()

	var init_wood: int = rm.get_available_stock("wood")
	var init_stone: int = rm.get_available_stock("stone")
	var cost := {"wood": 30, "stone": 20}

	var reserved: bool = rm.reserve_cost(cost)
	_assert(reserved == true, "S1.1: Direct reserve_cost succeeds")
	_assert(rm.get_reserved_stock("wood") == 30, "S1.2: Reserved wood matches cost")
	_assert(rm.get_reserved_stock("stone") == 20, "S1.3: Reserved stone matches cost")
	_assert(rm.get_available_stock("wood") == init_wood - 30, "S1.4: Available wood reduced by reservation")
	_assert(rm.get_total_stock("wood") == init_wood, "S1.5: Total stock wood intact during reservation")

	var committed: bool = rm.commit_cost(cost)
	_assert(committed == true, "S1.6: Direct commit_cost succeeds")
	_assert(rm.get_reserved_stock("wood") == 0, "S1.7: Reserved wood cleared after commit")
	_assert(rm.get_reserved_stock("stone") == 0, "S1.8: Reserved stone cleared after commit")
	_assert(rm.get_total_stock("wood") == init_wood - 30, "S1.9: Total wood deducted after commit")

	# Test Ticket-based API
	var tx_cost := {"wood": 20, "stone": 10}
	var pre_tx_wood: int = rm.get_available_stock("wood")
	var tx_id: String = rm.begin_transaction(tx_cost)
	_assert(tx_id != "", "S1.10: begin_transaction returns non-empty ticket ID")
	_assert(rm.has_active_transaction(tx_id) == true, "S1.11: has_active_transaction confirms ticket")
	_assert(rm.get_available_stock("wood") == pre_tx_wood - 20, "S1.12: Available wood reduced by ticket reservation")

	var tx_committed: bool = rm.commit_transaction(tx_id)
	_assert(tx_committed == true, "S1.13: commit_transaction succeeds")
	_assert(rm.has_active_transaction(tx_id) == false, "S1.14: Ticket removed after commit")
	_assert(rm.get_total_stock("wood") == pre_tx_wood - 20, "S1.15: Total wood deducted after ticket commit")

	rm.queue_free()

## Scenario 2: Commit without reservation fails closed
func _run_scenario_2_commit_without_reservation_fails_closed() -> void:
	print("--- Scenario 2: Commit Without Reservation Fails Closed ---")
	var rm = ResourceManagerScript.new()
	root.add_child(rm)
	rm.reset_economy()

	var init_wood: int = rm.get_available_stock("wood")
	var unreserved_cost := {"wood": 40}

	var committed: bool = rm.commit_cost(unreserved_cost)
	_assert(committed == false, "S2.1: commit_cost without reservation returns false")
	_assert(rm.get_total_stock("wood") == init_wood, "S2.2: Total wood stock strictly unchanged")
	_assert(rm.get_available_stock("wood") == init_wood, "S2.3: Available wood stock strictly unchanged")
	_assert(rm.get_reserved_stock("wood") == 0, "S2.4: Reserved wood stock remains 0")

	# Ticket equivalent: invalid ticket ID
	var tx_res: bool = rm.commit_transaction("tx_nonexistent_999")
	_assert(tx_res == false, "S2.5: commit_transaction on nonexistent ticket fails closed")

	rm.queue_free()

## Scenario 3: Double commit fails closed
func _run_scenario_3_double_commit_fails_closed() -> void:
	print("--- Scenario 3: Double Commit Fails Closed ---")
	var rm = ResourceManagerScript.new()
	root.add_child(rm)
	rm.reset_economy()

	var init_wood: int = rm.get_available_stock("wood")
	var cost := {"wood": 40}

	var reserved: bool = rm.reserve_cost(cost)
	_assert(reserved == true, "S3.1: Initial reservation succeeds")

	var commit_1: bool = rm.commit_cost(cost)
	_assert(commit_1 == true, "S3.2: First commit succeeds")
	_assert(rm.get_total_stock("wood") == init_wood - 40, "S3.3: Total wood deducted once")

	# Duplicate commit attempt
	var commit_2: bool = rm.commit_cost(cost)
	_assert(commit_2 == false, "S3.4: Second commit fails closed")
	_assert(rm.get_total_stock("wood") == init_wood - 40, "S3.5: Total wood stock not deducted twice")
	_assert(rm.get_reserved_stock("wood") == 0, "S3.6: Reserved wood remains 0")

	# Ticket equivalent: double commit_transaction
	var tx_cost := {"wood": 20}
	var tx_id: String = rm.begin_transaction(tx_cost)
	var tx_c1: bool = rm.commit_transaction(tx_id)
	_assert(tx_c1 == true, "S3.7: First ticket commit succeeds")
	var tx_c2: bool = rm.commit_transaction(tx_id)
	_assert(tx_c2 == false, "S3.8: Second ticket commit fails closed")

	rm.queue_free()

## Scenario 4: Concurrent reservations with limited stock
func _run_scenario_4_concurrent_reservations_with_limited_stock() -> void:
	print("--- Scenario 4: Concurrent Reservations With Limited Stock ---")
	var rm = ResourceManagerScript.new()
	root.add_child(rm)
	rm.reset_economy()

	# Set available wood to exactly 50
	var cur_wood: int = rm.get_available_stock("wood")
	rm.deduct_resource("wood", cur_wood - 50, false)
	_assert(rm.get_available_stock("wood") == 50, "S4.1: Available wood calibrated to 50")

	var order_a := {"wood": 30}
	var order_b := {"wood": 30}

	var res_a: bool = rm.reserve_cost(order_a)
	_assert(res_a == true, "S4.2: Order A reservation succeeds (30 of 50)")
	_assert(rm.get_available_stock("wood") == 20, "S4.3: Available wood is now 20")

	# Order B needs 30, but only 20 available
	var res_b: bool = rm.reserve_cost(order_b)
	_assert(res_b == false, "S4.4: Order B reservation rejected (needs 30, only 20 avail)")
	_assert(rm.get_reserved_stock("wood") == 30, "S4.5: Reserved wood remains strictly 30 for Order A")

	# Commit Order A
	var comm_a: bool = rm.commit_cost(order_a)
	_assert(comm_a == true, "S4.6: Order A commit succeeds")
	_assert(rm.get_total_stock("wood") == 20, "S4.7: Remaining total wood is 20")

	rm.queue_free()

## Scenario 5: Partial reservation rejected (all-or-nothing)
func _run_scenario_5_partial_reservation_all_or_nothing() -> void:
	print("--- Scenario 5: Partial Reservation Rejected (All-or-Nothing) ---")
	var rm = ResourceManagerScript.new()
	root.add_child(rm)
	rm.reset_economy()

	var init_wood: int = rm.get_available_stock("wood")
	var init_stone: int = rm.get_available_stock("stone")

	# Request affordable wood (50 <= init_wood), but stone far exceeds available (99999)
	var mixed_cost := {"wood": 50, "stone": 99999}
	var res_res: bool = rm.reserve_cost(mixed_cost)
	_assert(res_res == false, "S5.1: Mixed cost reservation rejected due to stone deficit")
	_assert(rm.get_available_stock("wood") == init_wood, "S5.2: Wood available stock untouched")
	_assert(rm.get_reserved_stock("wood") == 0, "S5.3: Wood reserved stock untouched (no leak)")
	_assert(rm.get_reserved_stock("stone") == 0, "S5.4: Stone reserved stock untouched")

	# Ticket equivalent: begin_transaction all-or-nothing
	var tx_id: String = rm.begin_transaction(mixed_cost)
	_assert(tx_id == "", "S5.5: begin_transaction returns empty string on partial deficit")
	_assert(rm.get_reserved_stock("wood") == 0, "S5.6: No ticketed reservation leaked")

	rm.queue_free()

## Scenario 6: Rollback / release_cost restores available stock
func _run_scenario_6_rollback_restores_available_stock() -> void:
	print("--- Scenario 6: Rollback / release_cost Restores Available Stock ---")
	var rm = ResourceManagerScript.new()
	root.add_child(rm)
	rm.reset_economy()

	var init_wood: int = rm.get_available_stock("wood")
	var init_stone: int = rm.get_available_stock("stone")
	var cost := {"wood": 40, "stone": 25}

	var res_ok: bool = rm.reserve_cost(cost)
	_assert(res_ok == true, "S6.1: Cost successfully reserved")
	_assert(rm.get_available_stock("wood") == init_wood - 40, "S6.2: Wood locked")

	var rel_ok: bool = rm.release_cost(cost)
	_assert(rel_ok == true, "S6.3: release_cost returns true")
	_assert(rm.get_available_stock("wood") == init_wood, "S6.4: Wood available stock restored 100%")
	_assert(rm.get_available_stock("stone") == init_stone, "S6.5: Stone available stock restored 100%")
	_assert(rm.get_reserved_stock("wood") == 0, "S6.6: Reserved wood is 0")
	_assert(rm.get_reserved_stock("stone") == 0, "S6.7: Reserved stone is 0")

	# Case D: Commit attempted after release rejected
	var commit_after_rel: bool = rm.commit_cost(cost)
	_assert(commit_after_rel == false, "S6.8: commit_cost after release fails closed (Case D)")

	# Ticket rollback
	var tx_id: String = rm.begin_transaction(cost)
	_assert(tx_id != "", "S6.9: Ticket created")
	var roll_ok: bool = rm.rollback_transaction(tx_id)
	_assert(roll_ok == true, "S6.10: rollback_transaction succeeds")
	_assert(rm.has_active_transaction(tx_id) == false, "S6.11: Ticket cleaned up")
	_assert(rm.get_available_stock("wood") == init_wood, "S6.12: Stock restored after ticket rollback")

	# Case D Ticket: Commit attempted after rollback rejected
	var commit_after_tx_roll: bool = rm.commit_transaction(tx_id)
	_assert(commit_after_tx_roll == false, "S6.13: commit_transaction after rollback fails closed (Case D)")

	rm.queue_free()

## Scenario 7: Double rollback fails closed without stealing other reservations
func _run_scenario_7_double_rollback_fails_closed_no_stealing() -> void:
	print("--- Scenario 7: Double Rollback Fails Closed Without Stealing ---")
	var rm = ResourceManagerScript.new()
	root.add_child(rm)
	rm.reset_economy()

	var cost_a := {"wood": 30}
	var cost_b := {"wood": 40}

	var res_a: bool = rm.reserve_cost(cost_a)
	var res_b: bool = rm.reserve_cost(cost_b)
	_assert(res_a and res_b, "S7.1: Both Order A and Order B reserved")
	_assert(rm.get_reserved_stock("wood") == 70, "S7.2: Total reserved wood is 70")

	# Release Order A
	var rel_a1: bool = rm.release_cost(cost_a)
	_assert(rel_a1 == true, "S7.3: First release of Order A succeeds")
	_assert(rm.get_reserved_stock("wood") == 40, "S7.4: Reserved wood reduced to 40")

	# Attempt second release of Order A (should FAIL and NOT deduct from Order B)
	var rel_a2: bool = rm.release_cost(cost_a)
	_assert(rel_a2 == false, "S7.5: Second release of Order A fails closed")
	_assert(rm.get_reserved_stock("wood") == 40, "S7.6: Reserved wood strictly remains 40 (Order B not stolen)")

	# Unticketed caller cannot steal ticketed reservation
	var tx_cost := {"wood": 25}
	var tx_id: String = rm.begin_transaction(tx_cost)
	_assert(rm.get_reserved_stock("wood") == 65, "S7.7: Reserved wood is 40 + 25 = 65")
	var unticketed_steal_rel: bool = rm.release_cost({"wood": 25})
	_assert(unticketed_steal_rel == false, "S7.8: Direct release_cost cannot release ticketed reservation")
	_assert(rm.get_reserved_stock("wood") == 65, "S7.9: Reserved wood remains 65")

	rm.rollback_transaction(tx_id)
	rm.release_cost(cost_b)
	_assert(rm.get_reserved_stock("wood") == 0, "S7.10: All reservations safely cleaned up")

	rm.queue_free()

## Scenario 8: Failed transaction invariance (0 side effects)
func _run_scenario_8_failed_transaction_invariance() -> void:
	print("--- Scenario 8: Failed Transaction Invariance ---")
	var rm = ResourceManagerScript.new()
	root.add_child(rm)
	rm.reset_economy()

	# Take full ledger snapshot
	var snapshot_avail: Dictionary = {}
	var snapshot_total: Dictionary = {}
	var snapshot_reserved: Dictionary = {}
	for r_id in EconomyConfigScript.ALL_RESOURCES:
		snapshot_avail[r_id] = rm.get_available_stock(r_id)
		snapshot_total[r_id] = rm.get_total_stock(r_id)
		snapshot_reserved[r_id] = rm.get_reserved_stock(r_id)

	# Execute barrage of invalid transactions
	_assert(rm.reserve_cost({}) == false, "S8.1: Empty cost reservation rejected")
	_assert(rm.commit_cost({}) == false, "S8.2: Empty cost commit rejected")
	_assert(rm.release_cost({}) == false, "S8.3: Empty cost release rejected")
	_assert(rm.begin_transaction({}) == "", "S8.4: Empty cost ticket rejected")
	_assert(rm.reserve_cost({"wood": -10}) == false, "S8.5: Negative cost reservation rejected")
	_assert(rm.commit_cost({"wood": -10}) == false, "S8.6: Negative cost commit rejected")
	_assert(rm.reserve_cost({"wood": 0}) == false, "S8.7: Zero cost reservation rejected")
	_assert(rm.commit_cost({"wood": 99999}) == false, "S8.8: Massive unreserved commit rejected")

	# Verify 100% invariance
	var invariant: bool = true
	for r_id in EconomyConfigScript.ALL_RESOURCES:
		if rm.get_available_stock(r_id) != snapshot_avail[r_id]:
			invariant = false
		if rm.get_total_stock(r_id) != snapshot_total[r_id]:
			invariant = false
		if rm.get_reserved_stock(r_id) != snapshot_reserved[r_id]:
			invariant = false

	_assert(invariant == true, "S8.9: Full ledger snapshot strictly invariant across invalid calls")
	rm.queue_free()

## Scenario 9: BuildingSystem construction integration
func _run_scenario_9_building_system_integration() -> void:
	print("--- Scenario 9: BuildingSystem Integration ---")
	var rm = ResourceManagerScript.new()
	root.add_child(rm)
	rm.reset_economy()

	var wd := _create_test_world_data()
	# Ensure cells at Vector2i(20, 20) are clear grass terrain
	for ox in range(2):
		for oy in range(2):
			wd.terrain[20 + ox][20 + oy] = WorldGeneratorScript.TerrainType.GRASS
			wd.occupancy[20 + ox][20 + oy] = false

	var init_wood: int = rm.get_available_stock("wood")
	var init_stone: int = rm.get_available_stock("stone")

	# Place house: cost is 25 wood, 10 stone
	var place_res: Dictionary = BuildingSystemScript.place_building("house", Vector2i(20, 20), wd, rm, "under_construction")
	_assert(place_res.get("success", false) == true, "S9.1: BuildingSystem place_building succeeds")
	_assert(rm.get_total_stock("wood") == init_wood - 25, "S9.2: Wood deducted 25 for house")
	_assert(rm.get_total_stock("stone") == init_stone - 10, "S9.3: Stone deducted 10 for house")
	_assert(rm.get_reserved_stock("wood") == 0, "S9.4: Reserved wood cleared cleanly after placement")
	_assert(rm.get_reserved_stock("stone") == 0, "S9.5: Reserved stone cleared cleanly after placement")

	rm.queue_free()

## Scenario 10: PlayerArmyManager equipment upgrade integration
func _run_scenario_10_player_army_manager_integration() -> void:
	print("--- Scenario 10: PlayerArmyManager Upgrade Integration ---")
	var rm = ResourceManagerScript.new()
	root.add_child(rm)
	rm.reset_economy()

	var pam := PlayerArmyManagerScript.new()
	var wd := WorldGeneratorScript.generate(101)
	var b := {
		"id": "bld_barracks_test",
		"type": "barracks",
		"cell": Vector2i(20, 20),
		"state": "active",
		"health": 100,
		"max_health": 100
	}
	wd.buildings.append(b)
	pam.set_custom_resource_manager(rm)
	pam.set_custom_world_data(wd)
	pam.soldier_count = 2 # Setup soldiers

	# Tier 1 -> Tier 2 costs: 30 wood, 15 metal
	rm.add_resource("metal", 100) # Ensure sufficient metal
	var init_wood: int = rm.get_available_stock("wood")
	var init_metal: int = rm.get_available_stock("metal")

	var up_res: Dictionary = pam.upgrade_equipment(2)
	_assert(up_res.get("success", false) == true, "S10.1: upgrade_equipment to Tier 2 succeeds")
	_assert(pam.get_equipment_tier() == 2, "S10.2: Army tier is 2")
	_assert(rm.get_total_stock("wood") == init_wood - 30, "S10.3: Wood deducted 30 for equipment")
	_assert(rm.get_total_stock("metal") == init_metal - 15, "S10.4: Metal deducted 15 for equipment")
	_assert(rm.get_reserved_stock("wood") == 0, "S10.5: 0 reserved wood remaining")
	_assert(rm.get_reserved_stock("metal") == 0, "S10.6: 0 reserved metal remaining")

	rm.queue_free()

## Scenario 11: WorkplaceManager production integration
func _run_scenario_11_workplace_manager_integration() -> void:
	print("--- Scenario 11: WorkplaceManager Production Integration ---")
	var rm = ResourceManagerScript.new()
	root.add_child(rm)
	rm.reset_economy()

	var wpm := WorkplaceManagerScript.new()
	rm.add_resource("metal", 50)
	var init_wood: int = rm.get_available_stock("wood")
	var init_metal: int = rm.get_available_stock("metal")

	# Register workshop craft recipe: requires 2 metal + 1 wood -> produces 1 tools
	wpm.register_workplace("workshop_craft_test", "workshop", Vector2i(15, 15), Vector2i(2, 2), Vector2i(15, 16), EconomyConfigScript.RES_TOOLS, 20, 1.0, 5, "", "craft_tools", {"metal": 2, "wood": 1}, 1)

	var produced: int = wpm.produce_to_buffer("workshop_craft_test", 1.0, rm)
	_assert(produced == 1, "S11.1: produce_to_buffer produced 1 tool")
	_assert(wpm.get_buffer_amount("workshop_craft_test") == 1, "S11.2: Workplace buffer holds 1 tool")
	_assert(rm.get_total_stock("metal") == init_metal - 2, "S11.3: Metal deducted 2 for crafting")
	_assert(rm.get_total_stock("wood") == init_wood - 1, "S11.4: Wood deducted 1 for crafting")
	_assert(rm.get_reserved_stock("metal") == 0, "S11.5: Reserved metal is 0")
	_assert(rm.get_reserved_stock("wood") == 0, "S11.6: Reserved wood is 0")

	rm.queue_free()
