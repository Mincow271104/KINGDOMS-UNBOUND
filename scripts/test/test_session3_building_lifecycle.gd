extends SceneTree

## =============================================================================
## KINGDOMS UNBOUND — CONTROLLED DEFECT REPAIR PROGRAM
## SESSION 3 TEST SUITE: BUILDING LIFECYCLE & DAMAGE INTEGRITY
## Focus: MBL-BLD-01 (Town Hall Raid Targeting & Fallback Exclusion)
##        MBL-BLD-02 (Unified Crisis Damage Lifecycle & Side Effects)
##        MBL-BLD-03 (Repair Reservation Ticket Leak Rollback)
##        MBL-BLD-04 (Mid-Repair Damage & Progress Retention)
##        MBL-BLD-05 (Construction Damage & Ruin Clearance/Occupancy)
## =============================================================================

const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")
const CrisisManagerScript = preload("res://scripts/core/crisis_manager.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const CitizenControllerScript = preload("res://scripts/entities/citizen_controller.gd")
const JobManagerScript = preload("res://scripts/jobs/job_manager.gd")

var frame_count: int = 0
var world_instance: Node = null
var failures: int = 0
var checks_passed: int = 0

func _assert(condition: bool, message: String, detail: String = "") -> void:
	if condition:
		checks_passed += 1
		print("  [PASS] %s" % message)
	else:
		failures += 1
		var err_msg := "  [FAIL] %s" % message
		if not detail.is_empty():
			err_msg += " (%s)" % detail
		printerr(err_msg)

func _init() -> void:
	print("\n========================================================")
	print("  STARTING SESSION 3 BUILDING LIFECYCLE TEST SUITE")
	print("========================================================\n")
	world_instance = WorldViewScene.instantiate()
	world_instance.world_seed = 12345
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count < 3:
		return false

	_run_all_tests()

	print("\n========================================================")
	print("  SESSION 3 TEST RESULTS SUMMARY")
	print("  Passed Assertions : %d" % checks_passed)
	print("  Failed Assertions : %d" % failures)
	if failures == 0:
		print("  ALL SESSION 3 ASSERTIONS PASSED! (Exit Code 0)")
		print("========================================================\n")
		if is_instance_valid(world_instance):
			world_instance.queue_free()
		quit(0)
	else:
		printerr("  SOME SESSION 3 ASSERTIONS FAILED! (Exit Code 1)")
		print("========================================================\n")
		if is_instance_valid(world_instance):
			world_instance.queue_free()
		quit(1)
	return true

func _run_all_tests() -> void:
	print("--- Running Task A: MBL-BLD-01 Bandit Raid Town Hall Targeting ---")
	_test_mbl_bld_01_bandit_raid_targeting()

	print("\n--- Running Task B: MBL-BLD-02 Unified Crisis Damage Lifecycle ---")
	_test_mbl_bld_02_unified_damage_lifecycle()

	print("\n--- Running Task C: MBL-BLD-03 Repair Reservation Ticket Leak ---")
	_test_mbl_bld_03_repair_ticket_leak()

	print("\n--- Running Task D: MBL-BLD-04 Mid-Repair Damage Progression ---")
	_test_mbl_bld_04_mid_repair_damage()

	print("\n--- Running Task E1: MBL-BLD-05 Construction Damage State ---")
	_test_mbl_bld_05_e1_construction_damage()

	print("\n--- Running Task E2: MBL-BLD-05 Destroyed Ruin Clearance & Occupancy ---")
	_test_mbl_bld_05_e2_ruin_clearance_and_occupancy()

## -----------------------------------------------------------------------------
## TASK A: MBL-BLD-01 Bandit Raid Canonical Town Hall Targeting & Fallback
## -----------------------------------------------------------------------------
func _test_mbl_bld_01_bandit_raid_targeting() -> void:
	var cm := CrisisManagerScript.new(12345)
	var rm = world_instance.call("_get_resource_mgr")

	# Subtest 1: Primary lookup selects canonical Town Hall; ordinary buildings untouched
	var mock_wd = {
		"buildings": [
			{"id": "townhall_main", "type": "townhall", "cell": Vector2i(32, 32), "size": Vector2i(3, 3), "state": "active", "health": 100, "max_health": 100},
			{"id": "workshop_1", "type": "workshop", "cell": Vector2i(20, 20), "size": Vector2i(2, 2), "state": "active", "health": 100, "max_health": 100},
			{"id": "house_1", "type": "house", "cell": Vector2i(25, 25), "size": Vector2i(2, 2), "state": "active", "health": 100, "max_health": 100}
		]
	}

	# Force breach by passing null army
	var raid_res: Dictionary = cm.resolve_bandit_raid(mock_wd, rm, [], null, null)
	_assert(raid_res.get("breached_bandits", 0) > 0, "A1.1: Bandits breached settlement defenses")

	var th_entry: Dictionary = mock_wd["buildings"][0]
	_assert(int(th_entry.get("health", 0)) == 75, "A1.2: Primary lookup selected canonical Town Hall and applied 25 damage (health: 75)", "Got: %d" % int(th_entry.get("health", 0)))
	_assert(str(th_entry.get("state", "")) == "active", "A1.3: Town Hall remains active after non-lethal raid damage")

	var damaged_list: Array = raid_res.get("damaged_buildings", [])
	_assert(damaged_list.has("townhall_main"), "A1.4: Damaged buildings list correctly contains targeted Town Hall")
	_assert(not damaged_list.has("workshop_1") and not damaged_list.has("house_1"), "A1.5: Ordinary buildings strictly excluded from damage list")
	_assert(int(mock_wd["buildings"][1].get("health", 0)) == 100, "A1.6: Workshop received zero damage (health strictly 100)")
	_assert(int(mock_wd["buildings"][2].get("health", 0)) == 100, "A1.7: House received zero damage (health strictly 100)")

	# Subtest 2: Fallback selects valid Town Hall when primary is unavailable; ordinary buildings never selected
	var mock_wd_fallback = {
		"buildings": [
			{"id": "ruined_farm", "type": "farm", "cell": Vector2i(10, 10), "size": Vector2i(2, 2), "state": "destroyed", "health": 0, "max_health": 100},
			{"id": "valid_quarry", "type": "quarry", "cell": Vector2i(15, 15), "size": Vector2i(2, 2), "state": "active", "health": 100, "max_health": 100},
			{"id": "townhall_sec", "type": "townhall", "cell": Vector2i(40, 40), "size": Vector2i(3, 3), "state": "active", "health": 100, "max_health": 100}
		]
	}
	var raid_res_2: Dictionary = cm.resolve_bandit_raid(mock_wd_fallback, rm, [], null, null)
	var damaged_2: Array = raid_res_2.get("damaged_buildings", [])
	_assert(damaged_2.has("townhall_sec"), "A2.1: Fallback selected valid Town Hall candidate")
	_assert(not damaged_2.has("valid_quarry"), "A2.2: Ordinary building (quarry) never selected as fallback")
	_assert(not damaged_2.has("ruined_farm"), "A2.3: Destroyed building excluded from fallback")
	_assert(int(mock_wd_fallback["buildings"][1].get("health", 0)) == 100, "A2.4: Quarry remains undamaged at 100 health")
	_assert(int(mock_wd_fallback["buildings"][2].get("health", 0)) == 75, "A2.5: Targeted fallback Town Hall took 25 damage")

	# Subtest 3: Legacy alias "town_hall" compatibility is exercised
	var mock_wd_legacy = {
		"buildings": [
			{"id": "house_legacy_test", "type": "house", "cell": Vector2i(22, 22), "size": Vector2i(2, 2), "state": "active", "health": 100, "max_health": 100},
			{"id": "th_legacy", "type": "town_hall", "cell": Vector2i(32, 32), "size": Vector2i(3, 3), "state": "active", "health": 100, "max_health": 100}
		]
	}
	var raid_res_3: Dictionary = cm.resolve_bandit_raid(mock_wd_legacy, rm, [], null, null)
	var damaged_3: Array = raid_res_3.get("damaged_buildings", [])
	_assert(damaged_3.has("th_legacy"), "A3.1: Supported legacy alias 'town_hall' correctly recognized and targeted")
	_assert(not damaged_3.has("house_legacy_test"), "A3.2: House untouched when legacy Town Hall is present")
	_assert(int(mock_wd_legacy["buildings"][1].get("health", 0)) == 75, "A3.3: Legacy Town Hall took 25 damage")

	# Subtest 4: Disallowed candidates rejected (destroyed, under_construction, hostile faction, empty id)
	var mock_wd_disallowed = {
		"buildings": [
			{"id": "th_destroyed", "type": "townhall", "cell": Vector2i(32, 32), "size": Vector2i(3, 3), "state": "destroyed", "health": 0, "max_health": 100},
			{"id": "th_construction", "type": "townhall", "cell": Vector2i(35, 35), "size": Vector2i(3, 3), "state": "under_construction", "health": 50, "max_health": 100},
			{"id": "th_enemy", "type": "townhall", "cell": Vector2i(38, 38), "size": Vector2i(3, 3), "state": "active", "health": 100, "max_health": 100, "faction": "enemy"},
			{"id": "", "type": "townhall", "cell": Vector2i(42, 42), "size": Vector2i(3, 3), "state": "active", "health": 100, "max_health": 100},
			{"id": "workshop_safe", "type": "workshop", "cell": Vector2i(20, 20), "size": Vector2i(2, 2), "state": "active", "health": 100, "max_health": 100}
		]
	}
	var raid_res_4: Dictionary = cm.resolve_bandit_raid(mock_wd_disallowed, rm, [], null, null)
	var damaged_4: Array = raid_res_4.get("damaged_buildings", [])
	_assert(damaged_4.is_empty(), "A4.1: Disallowed Town Hall candidates rejected; zero buildings damaged")
	_assert(int(mock_wd_disallowed["buildings"][4].get("health", 0)) == 100, "A4.2: Ordinary workshop never targeted as fallback")

	# Subtest 5: Active-raid retarget is deterministic after target destruction
	var mock_wd_retarget = {
		"buildings": [
			{"id": "th_alpha", "type": "townhall", "cell": Vector2i(30, 30), "size": Vector2i(3, 3), "state": "active", "health": 20, "max_health": 100},
			{"id": "th_beta", "type": "townhall", "cell": Vector2i(40, 40), "size": Vector2i(3, 3), "state": "active", "health": 100, "max_health": 100},
			{"id": "farm_bystander", "type": "farm", "cell": Vector2i(10, 10), "size": Vector2i(2, 2), "state": "active", "health": 100, "max_health": 100}
		]
	}
	var raid_res_5: Dictionary = cm.resolve_bandit_raid(mock_wd_retarget, rm, [], null, null)
	var damaged_5: Array = raid_res_5.get("damaged_buildings", [])
	_assert(damaged_5.has("th_alpha"), "A5.1: Strike 1 targeted vulnerable Town Hall alpha")
	_assert(int(mock_wd_retarget["buildings"][0].get("health", 0)) == 0, "A5.2: Town Hall alpha suffered lethal damage and was destroyed")
	_assert(str(mock_wd_retarget["buildings"][0].get("state", "")) == "destroyed", "A5.3: Town Hall alpha state transitioned to destroyed")
	_assert(damaged_5.has("th_beta"), "A5.4: Strike 2 deterministically retargeted valid surviving Town Hall beta")
	_assert(not damaged_5.has("farm_bystander"), "A5.5: Bystander farm was never targeted during retargeting")

	# Subtest 6: Documented safe terminal/idle behavior when no valid Town Hall exists
	var mock_wd_no_th = {
		"buildings": [
			{"id": "farm_only_1", "type": "farm", "cell": Vector2i(10, 10), "size": Vector2i(2, 2), "state": "active", "health": 100, "max_health": 100},
			{"id": "house_only_1", "type": "house", "cell": Vector2i(20, 20), "size": Vector2i(2, 2), "state": "active", "health": 100, "max_health": 100}
		]
	}
	var raid_res_6: Dictionary = cm.resolve_bandit_raid(mock_wd_no_th, rm, [], null, null)
	var damaged_6: Array = raid_res_6.get("damaged_buildings", [])
	_assert(damaged_6.is_empty(), "A6.1: Zero structural damage when no valid Town Hall exists (safe idle)")
	_assert(raid_res_6.get("breached_bandits", 0) > 0, "A6.2: Bandits still breach defenses")
	_assert(int(mock_wd_no_th["buildings"][0].get("health", 0)) == 100, "A6.3: Farm undamaged")
	_assert(int(mock_wd_no_th["buildings"][1].get("health", 0)) == 100, "A6.4: House undamaged")

## -----------------------------------------------------------------------------
## TASK B: MBL-BLD-02 Unified Crisis Damage Lifecycle & Side Effects
## -----------------------------------------------------------------------------
func _test_mbl_bld_02_unified_damage_lifecycle() -> void:
	# Subtest 1: Verify CrisisManager damage handler wiring
	var cm = world_instance.get("crisis_mgr")
	_assert(cm != null, "B1.1: WorldView crisis_mgr exists")
	_assert(cm.get("building_damage_handler") != null, "B1.2: CrisisManager building_damage_handler property is configured")

	# Subtest 2: Blizzard damage routes through WorldView and pauses workplace
	var wd = world_instance.get("world_data")
	var rm = world_instance.call("_get_resource_mgr")
	var wm = world_instance.get("workplace_mgr")

	var farm_b = {
		"id": "bld_farm_test_b",
		"type": "farm",
		"cell": Vector2i(18, 18),
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 51,
		"max_health": 100
	}
	wd.buildings.append(farm_b)
	wm.register_workplace("bld_farm_test_b", "farm", Vector2i(18, 18), Vector2i(2, 2), Vector2i(18, 20), "food")
	_assert(not wm.is_workplace_paused("bld_farm_test_b"), "B2.1: Farm workplace is initially active and unpaused")

	# Apply 2 damage (simulating Blizzard snow load wear) via WorldView.damage_building
	# Health drops from 51 to 49 (crosses <= 50 threshold)
	var dmg_ok: bool = world_instance.damage_building("bld_farm_test_b", 2)
	_assert(dmg_ok, "B2.2: WorldView.damage_building executed successfully")
	_assert(int(farm_b.get("health", 0)) == 49, "B2.3: Farm health dropped to 49")
	_assert(str(farm_b.get("state", "")) == "damaged", "B2.4: Farm state transitioned to 'damaged'")
	_assert(wm.is_workplace_paused("bld_farm_test_b"), "B2.5: Farm workplace was paused automatically by damage lifecycle")

	# Subtest 3: Non-state-transition damage (49 -> 45) does not re-trigger spurious lifecycle
	var dmg_again: bool = world_instance.damage_building("bld_farm_test_b", 4)
	_assert(dmg_again, "B3.1: Consecutive damage on already damaged building succeeds")
	_assert(int(farm_b.get("health", 0)) == 45, "B3.2: Health reduced to 45")
	_assert(str(farm_b.get("state", "")) == "damaged", "B3.3: State remains 'damaged'")

	# Subtest 4: Lethal damage invokes destruction lifecycle and evicts military garrison
	var pam = world_instance.get("player_army_mgr")
	if pam != null and pam.has_method("station_soldier"):
		pam.station_soldier("op_bld_test_b", 1)
	var lethal_res: bool = world_instance.damage_building("bld_farm_test_b", 100)
	_assert(lethal_res, "B4.1: Lethal damage applied successfully")
	_assert(int(farm_b.get("health", 0)) == 0, "B4.2: Health reduced to 0")
	_assert(str(farm_b.get("state", "")) == "destroyed", "B4.3: Building transitioned to 'destroyed'")

	# Cleanup test building
	wd.buildings.erase(farm_b)

## -----------------------------------------------------------------------------
## TASK C: MBL-BLD-03 Repair Reservation Ticket Leak Rollback
## -----------------------------------------------------------------------------
func _test_mbl_bld_03_repair_ticket_leak() -> void:
	var wd = world_instance.get("world_data")
	var rm = world_instance.call("_get_resource_mgr")

	# Setup resources: Ensure enough wood, stone, tools for repair
	rm.reset_economy()
	rm.add_resource("wood", 100)
	rm.add_resource("stone", 100)
	rm.add_resource("tools", 100)
	var initial_wood: int = rm.get_available_stock("wood")

	var workshop_b = {
		"id": "bld_repair_leak_test",
		"type": "workshop",
		"cell": Vector2i(22, 22),
		"size": Vector2i(2, 2),
		"state": "damaged",
		"health": 40,
		"max_health": 100,
		"is_repairing": false
	}
	wd.buildings.append(workshop_b)

	# 1. Start repair: registers transaction ticket "repair_bld_repair_leak_test"
	var start_res: Dictionary = world_instance.start_repair_building("bld_repair_leak_test", rm)
	_assert(start_res.get("success", false), "C1.1: start_repair_building succeeded")
	var tid: String = "repair_bld_repair_leak_test"
	_assert(rm.has_active_transaction(tid), "C1.2: ResourceManager has active transaction ticket '%s'" % tid)

	var cost: Dictionary = start_res.get("cost", {})
	var wood_cost: int = int(cost.get("wood", 0))
	var avail_wood_during_repair: int = rm.get_available_stock("wood")
	_assert(avail_wood_during_repair == (initial_wood - wood_cost), "C1.3: Available wood stock reflects reservation deduction (%d - %d = %d)" % [initial_wood, wood_cost, avail_wood_during_repair])

	# 2. Apply lethal damage while repairing
	var lethal_res: bool = world_instance.damage_building("bld_repair_leak_test", 100)
	_assert(lethal_res, "C2.1: Lethal damage applied to actively repairing building")
	_assert(str(workshop_b.get("state", "")) == "destroyed", "C2.2: Building state transitioned to destroyed")
	_assert(not bool(workshop_b.get("is_repairing", false)), "C2.3: is_repairing reset to false")

	# 3. Verify transaction rollback and stock restoration
	_assert(not rm.has_active_transaction(tid), "C3.1: Active repair transaction ticket was erased on lethal damage")
	var avail_wood_post_lethal: int = rm.get_available_stock("wood")
	_assert(avail_wood_post_lethal == initial_wood, "C3.2: Reserved wood returned to available stock (expected %d, observed: %d)" % [initial_wood, avail_wood_post_lethal])

	# 4. Idempotency under repeated damage/destruction calls
	var re_damage: bool = world_instance.damage_building("bld_repair_leak_test", 50)
	_assert(not re_damage, "C4.1: Repeated damage on destroyed building rejected fail-closed")
	_assert(rm.get_available_stock("wood") == initial_wood, "C4.2: Stock unmodified on re-damage")

	# Cleanup test building
	wd.buildings.erase(workshop_b)

## -----------------------------------------------------------------------------
## TASK D: MBL-BLD-04 Mid-Repair Damage Progression & Baseline Retention
## -----------------------------------------------------------------------------
func _test_mbl_bld_04_mid_repair_damage() -> void:
	var wd = world_instance.get("world_data")
	var rm = world_instance.call("_get_resource_mgr")

	rm.reset_economy()
	rm.add_resource("wood", 100)
	rm.add_resource("stone", 100)
	rm.add_resource("tools", 100)

	var b = {
		"id": "bld_mid_repair_test",
		"type": "workshop",
		"cell": Vector2i(24, 24),
		"size": Vector2i(2, 2),
		"state": "damaged",
		"health": 50,
		"max_health": 100
	}
	wd.buildings.append(b)

	# Step 1: Start repair at 50 HP (requires 2.0h or calculated hours)
	var start_res: Dictionary = world_instance.start_repair_building("bld_mid_repair_test", rm)
	_assert(start_res.get("success", false), "D1.1: Repair started at 50 HP")
	var req_hours: float = float(b.get("repair_hours_required", 2.0))

	# Step 2: Advance repair to 50% progress
	var half_time: float = req_hours * 0.5
	var adv_res: Dictionary = BuildingSystemScript.advance_repair(b, half_time, wd)
	_assert(adv_res.get("success", false), "D2.1: advance_repair by 50% succeeded")
	var hp_at_50: int = int(b.get("health", 0))
	_assert(hp_at_50 == 75, "D2.2: Health at 50% repair reached 75 HP (observed: " + str(hp_at_50) + ")")

	# Step 3: Apply 20 non-lethal damage mid-repair; health falls to 55 HP
	var dmg_res := BuildingSystemScript.apply_damage(b, 20, wd, rm)
	_assert(dmg_res.get("success", false), "D3.1: Mid-repair damage applied successfully")
	_assert(int(b.get("health", 0)) == 55, "D3.2: Health fell to exactly 55 HP (observed: %d)" % int(b.get("health", 0)))
	_assert(int(b.get("damage_initial_health", 0)) == 55, "D3.3: damage_initial_health updated to new baseline 55")
	_assert(float(b.get("repair_progress", -1.0)) == 0.0, "D3.4: repair_progress reset to 0.0 from new baseline")

	# Step 4: Advance repair by 0.1 hours — verify health does NOT jump back to 75 or higher
	var adv_tick: Dictionary = BuildingSystemScript.advance_repair(b, 0.1, wd)
	_assert(adv_tick.get("success", false), "D4.1: advance_repair by 0.1h succeeded")
	var hp_after_tick: int = int(b.get("health", 0))
	_assert(hp_after_tick >= 55 and hp_after_tick <= 60, "D4.2: Health progresses smoothly from 55 without erasing damage (observed: %d, expected ~56-57, strictly < 75)" % hp_after_tick)

	# Step 5: Advance repair to full completion and verify reaches max HP 100
	var new_req: float = float(b.get("repair_hours_required", 2.0))
	BuildingSystemScript.advance_repair(b, new_req, wd)
	var comp_res := BuildingSystemScript.complete_repair(b, wd, rm)
	_assert(comp_res.get("success", false), "D5.1: complete_repair succeeded")
	_assert(int(b.get("health", 0)) == 100, "D5.2: Final health reached exactly max_health 100")
	_assert(str(b.get("state", "")) == "active", "D5.3: Building restored to active state")
	_assert(not rm.has_active_transaction("repair_bld_mid_repair_test"), "D5.4: Transaction committed cleanly")

	# Cleanup test building
	wd.buildings.erase(b)

## -----------------------------------------------------------------------------
## TASK E1: MBL-BLD-05 Under-Construction Damage State Distinction
## -----------------------------------------------------------------------------
func _test_mbl_bld_05_e1_construction_damage() -> void:
	var wd = world_instance.get("world_data")
	var rm = world_instance.call("_get_resource_mgr")

	var uc_b = {
		"id": "bld_uc_damage_test",
		"type": "workshop",
		"cell": Vector2i(26, 26),
		"size": Vector2i(2, 2),
		"state": "under_construction",
		"construction_progress": 2.0,
		"construction_hours": 12.0,
		"health": 100,
		"max_health": 100
	}
	wd.buildings.append(uc_b)

	# 1. Apply 60 non-lethal damage to under-construction building
	var dmg_res := BuildingSystemScript.apply_damage(uc_b, 60, wd, rm)
	_assert(dmg_res.get("success", false), "E1.1: Damage applied to under-construction building")
	_assert(int(uc_b.get("health", 0)) == 40, "E1.2: Health dropped to 40 (<= 50)")
	_assert(str(uc_b.get("state", "")) == "under_construction", "E1.3: State strictly remains 'under_construction' (NOT 'damaged')")

	# 2. Verify can_repair_building rejects under-construction building
	var rep_check := BuildingSystemScript.can_repair_building(uc_b, wd, rm)
	_assert(not rep_check.get("can_repair", false), "E1.4: can_repair_building rejects unfinished building")

	# 3. Verify complete_repair does not mark unfinished building active
	var comp_rep := BuildingSystemScript.complete_repair(uc_b, wd, rm)
	_assert(not comp_rep.get("success", true), "E1.5: complete_repair rejected for unfinished building")
	_assert(str(uc_b.get("state", "")) == "under_construction", "E1.6: State remains 'under_construction' after rejected repair")

	# 4. Verify construction can advance and cancel normally
	var adv_con := BuildingSystemScript.advance_construction(uc_b, 1.0, wd)
	_assert(adv_con.get("success", false), "E1.7: advance_construction succeeds on damaged under-construction building")
	_assert(float(uc_b.get("construction_progress", 0.0)) == 3.0, "E1.8: Construction progress advanced to 3.0h")

	var can_cancel := BuildingSystemScript.can_cancel_construction(uc_b, wd, rm)
	_assert(can_cancel.get("can_cancel", false), "E1.9: can_cancel_construction remains valid on damaged under-construction building")

	# Cleanup test building
	wd.buildings.erase(uc_b)

## -----------------------------------------------------------------------------
## TASK E2: MBL-BLD-05 Destroyed Ruin Clearance & Occupancy
## -----------------------------------------------------------------------------
func _test_mbl_bld_05_e2_ruin_clearance_and_occupancy() -> void:
	var wd = world_instance.get("world_data")
	var rm = world_instance.call("_get_resource_mgr")

	var origin := Vector2i(28, 28)
	var size := Vector2i(2, 2)

	# Mark occupancy grid
	for ox in range(size.x):
		for oy in range(size.y):
			wd.occupancy[origin.x + ox][origin.y + oy] = true

	var storehouse_ruin = {
		"id": "bld_storehouse_ruin_test",
		"type": "storehouse",
		"cell": origin,
		"size": size,
		"state": "active",
		"upgrade_level": 1,
		"health": 100,
		"max_health": 100,
		"storage_applied": true
	}
	wd.buildings.append(storehouse_ruin)
	world_instance.buildings_by_cell[origin] = storehouse_ruin

	# Baseline capacity is 500 each; add storehouse storage capacity bonus (500 each for wood/stone)
	rm.reset_economy()
	var base_wood_cap: int = int(rm.get_storage_capacity("wood"))
	rm.add_storage_capacity("wood", 500)
	rm.add_storage_capacity("stone", 500)

	# 1. Destroy building to zero HP
	var lethal_res: bool = world_instance.damage_building("bld_storehouse_ruin_test", 100)
	_assert(lethal_res, "E2.1: Lethal damage destroyed storehouse")
	_assert(str(storehouse_ruin.get("state", "")) == "destroyed", "E2.2: Building state is 'destroyed'")

	# 2. Verify can_repair_building rejects destroyed ruin
	var can_rep := BuildingSystemScript.can_repair_building(storehouse_ruin, wd, rm)
	_assert(not can_rep.get("can_repair", false), "E2.3: Destroyed ruin cannot be repaired")

	# 3. Verify can_demolish_building permits clearing the destroyed ruin with 0 refund
	var can_demo := BuildingSystemScript.can_demolish_building(storehouse_ruin, wd, rm)
	_assert(can_demo.get("can_demolish", false), "E2.4: can_demolish_building permits clearing destroyed ruin")
	_assert(can_demo.get("refund", {}).is_empty(), "E2.5: Ruin clearance provides 0 refund (empty dictionary)")

	# 4. Clear/demolish the destroyed ruin via demolish_building_project
	var demo_res: Dictionary = world_instance.call("demolish_building_project", "bld_storehouse_ruin_test")
	_assert(demo_res.get("success", false), "E2.6: demolish_building_project succeeded on destroyed ruin")

	# 5. Verify building record and occupancy grid were cleared
	var found_b = BuildingSystemScript.get_building_by_id("bld_storehouse_ruin_test", wd)
	_assert(found_b.is_empty(), "E2.7: Building record erased from world_data.buildings")
	_assert(not world_instance.buildings_by_cell.has(origin), "E2.8: Building erased from buildings_by_cell")

	var occupancy_cleared := true
	for ox in range(size.x):
		for oy in range(size.y):
			if wd.occupancy[origin.x + ox][origin.y + oy] == true:
				occupancy_cleared = false
	_assert(occupancy_cleared, "E2.9: All 4 footprint cells released in occupancy grid")

	# 6. Verify storage capacity was decremented exactly once (from base + 500 back to base)
	_assert(rm.get_storage_capacity("wood") == base_wood_cap, "E2.10: Storage capacity decremented exactly once (observed: %d, expected %d)" % [rm.get_storage_capacity("wood"), base_wood_cap])

	# 7. Verify new building can occupy the released grid cells
	var can_place := BuildingSystemScript.can_place_building("workshop", origin, wd, rm)
	_assert(can_place.get("valid", false), "E2.11: New building can be placed on the released footprint cells")

	# 8. Idempotency: repeated demolition call on cleared ruin safely rejected
	var repeat_demo: Dictionary = world_instance.call("demolish_building_project", "bld_storehouse_ruin_test")
	_assert(not repeat_demo.get("success", true), "E2.12: Repeated clearance call safely rejected")
	_assert(rm.get_storage_capacity("wood") == base_wood_cap, "E2.13: Storage capacity not double-decremented on repeated clearance")
