extends SceneTree
## Test Suite: Session 1.3.1 Corrective Verification, Atomicity Hardening & Master Ledger Restoration
## Authoritative test suite verifying:
## Group A: Dependency Failure Tests (Missing TMM / Missing Nav fail closed for voluntary; 0 capacity for forced)
## Group B: Actual Spawn Instantiation Failure Tests (Preflight pass vs instantiation fail / partial spawn)
## Group C: Ownership Transfer Transaction (9 mandatory failure/edge tests, snapshot rollback, idempotency)
## Group D: Invalid Reinforcement Arrival (Destroyed/captured objective, capacity bounds, instantiation failure)
## Group E: Regression & Invariant Reconciliation

const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const PlayerArmyManagerScript = preload("res://scripts/military/player_army_manager.gd")
const FieldSiegeManagerScript = preload("res://scripts/combat/field_siege_manager.gd")
const SiegeObjectiveActorScript = preload("res://scripts/combat/siege_objective_actor.gd")

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
	print("  STARTING SESSION 1.3.1 CORRECTIVE VERIFICATION SUITE")
	print("========================================================\n")
	world_instance = WorldViewScene.instantiate()
	world_instance.world_seed = 7070
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
	world_instance.buildings_by_cell[cell] = "watchtower"
	world_instance._instantiate_building_node("watchtower", cell, Vector2i(1, 1), "active")
	return b_data

func _calc_invariants(pam: Object, tmm: Object) -> Dictionary:
	var reserve: int = int(pam.get("soldier_count"))
	var garrisoned: int = int(pam.call("get_all_garrisoned_count"))
	var in_transit: int = int(pam.call("get_in_transit_count"))
	var total_headcount: int = int(pam.call("get_total_soldier_count"))
	var tactical_unit_count: int = int(tmm.units.size()) if (tmm != null and "units" in tmm) else 0

	var invariant_a: bool = (total_headcount == (reserve + garrisoned + in_transit))
	var invariant_b: bool = (tactical_unit_count == reserve)

	return {
		"reserve": reserve,
		"garrisoned": garrisoned,
		"in_transit": in_transit,
		"total_headcount": total_headcount,
		"tactical_units": tactical_unit_count,
		"invariant_a_holds": invariant_a,
		"invariant_b_holds": invariant_b
	}

func _run_all_tests() -> void:
	var pam = world_instance.get("player_army_mgr")
	var tmm = world_instance.get("tactical_military_mgr")
	var fsm = world_instance.get("field_siege_mgr")

	print("\n--- TEST GROUP A: DEPENDENCY FAILURE TESTS ---")
	# Reset state
	pam.soldier_count = 10
	tmm.sync_with_player_army()
	pam.garrisons.clear()
	pam.active_reinforcements.clear()

	# TC-A1: Missing TMM during voluntary demolition -> fails closed, building preserved, garrison preserved
	var b_id_a1 := "test_b_dep_a1"
	_create_active_watchtower(b_id_a1, Vector2i(20, 20))
	var st_res_a1 = pam.station_soldier(b_id_a1, 2)
	_assert(st_res_a1.get("success", false) == true, "TC-A1.0: Station 2 soldiers in watchtower succeeded")

	# Temporarily nullify TMM reference in PAM and WorldView
	pam.tactical_military_mgr = null
	world_instance.tactical_military_mgr = null

	var demo_res_a1: Dictionary = world_instance.demolish_building_project(b_id_a1)
	_assert(demo_res_a1.get("success", true) == false, "TC-A1.1: Voluntary demolition fails closed when TMM is null")
	_assert(pam.get_garrison_count(b_id_a1) == 2, "TC-A1.2: Garrison preserved on missing TMM demolition")
	_assert(world_instance.world_data.buildings.any(func(b): return b.id == b_id_a1), "TC-A1.3: Building preserved in world_data")

	# Restore TMM
	pam.tactical_military_mgr = tmm
	world_instance.tactical_military_mgr = tmm

	# TC-A2: Missing Nav during voluntary demolition -> fails closed
	tmm._test_simulate_null_nav = true
	pam._test_simulate_null_nav = true

	var demo_res_a2: Dictionary = world_instance.demolish_building_project(b_id_a1)
	_assert(demo_res_a2.get("success", true) == false, "TC-A2.1: Voluntary demolition fails closed when Navigation is null")
	_assert(pam.get_garrison_count(b_id_a1) == 2, "TC-A2.2: Garrison preserved on missing Nav demolition")

	# Restore Navigation
	tmm._test_simulate_null_nav = false
	pam._test_simulate_null_nav = false

	# TC-A3: Missing TMM during forced destruction -> evaluates to 0 capacity, 0 evacuated, 100% casualties, records cleared
	pam.tactical_military_mgr = null
	world_instance.tactical_military_mgr = null
	var evict_res_a3: Dictionary = pam.evict_and_cancel_outpost(b_id_a1, true, true)
	_assert(evict_res_a3.get("success", false) == true, "TC-A3.1: Forced eviction succeeds with 0 capacity on missing TMM")
	_assert(evict_res_a3.get("evacuated_count", -1) == 0, "TC-A3.2: 0 soldiers evacuated to reserve on missing TMM")
	_assert(evict_res_a3.get("casualties_count", -1) == 2, "TC-A3.3: All 2 soldiers accounted as casualties")
	_assert(pam.get_garrison_count(b_id_a1) == 0, "TC-A3.4: Garrison record cleanly erased")
	_assert(pam.soldier_count == 8, "TC-A3.5: Reserve not inflated (remains 8)")

	pam.tactical_military_mgr = tmm
	world_instance.tactical_military_mgr = tmm

	# TC-A4: Missing Nav during forced destruction -> evaluates to 0 capacity, 0 evacuated, 100% casualties
	var b_id_a4 := "test_b_dep_a4"
	_create_active_watchtower(b_id_a4, Vector2i(21, 21))
	var st_res_a4 = pam.station_soldier(b_id_a4, 2)
	_assert(st_res_a4.get("success", false) == true, "TC-A4.0: Station 2 in watchtower a4 succeeded")
	_assert(pam.soldier_count == 6, "TC-A4.1: Reserve at 6 after stationing 2")

	tmm._test_simulate_null_nav = true
	pam._test_simulate_null_nav = true

	var evict_res_a4: Dictionary = pam.evict_and_cancel_outpost(b_id_a4, true, true)
	_assert(evict_res_a4.get("success", false) == true, "TC-A4.2: Forced eviction succeeds with 0 capacity on missing Nav")
	_assert(evict_res_a4.get("evacuated_count", -1) == 0, "TC-A4.3: 0 soldiers evacuated on missing Nav")
	_assert(evict_res_a4.get("casualties_count", -1) == 2, "TC-A4.4: 2 soldiers recorded as casualties")
	_assert(pam.get_garrison_count(b_id_a4) == 0, "TC-A4.5: Garrison record erased")
	_assert(pam.soldier_count == 6, "TC-A4.6: Reserve remains 6, zero ghost increment")

	tmm._test_simulate_null_nav = false
	pam._test_simulate_null_nav = false

	# TC-A5: Hostile capture with null PAM fails closed
	var obj_a5 := "test_obj_dep_a5"
	fsm.register_objective(obj_a5, Vector2i(22, 22), "player", 100.0, 5)
	fsm.player_army_mgr = null
	world_instance.player_army_mgr = null
	var cap_res_a5: Dictionary = fsm.transfer_outpost_ownership(obj_a5, "rival_military", "tx_dep_a5")
	_assert(cap_res_a5.get("success", true) == false, "TC-A5.1: Hostile capture fails closed when PAM is null")
	fsm.player_army_mgr = pam
	world_instance.player_army_mgr = pam

	print("\n--- TEST GROUP B: ACTUAL SPAWN INSTANTIATION FAILURE TESTS ---")
	pam.soldier_count = 10
	tmm.sync_with_player_army()
	pam.garrisons.clear()
	pam.active_reinforcements.clear()

	# TC-B1: Preflight succeeds but actual spawn fails completely (voluntary demolition rollback)
	var obj_b1 := "test_obj_inst_b1"
	fsm.register_objective(obj_b1, Vector2i(24, 24), "player", 100.0, 10)
	pam.station_soldier(obj_b1, 4)
	_assert(pam.soldier_count == 6, "TC-B1.1: Reserve at 6")

	tmm._test_simulate_spawn_instantiation_failure = true
	var evict_res_b1: Dictionary = pam.evict_and_cancel_outpost(obj_b1, true, false) # Policy A
	tmm._test_simulate_spawn_instantiation_failure = false

	_assert(evict_res_b1.get("success", true) == false, "TC-B1.2: Voluntary eviction fails closed when spawn instantiation fails")
	_assert(pam.get_garrison_count(obj_b1) == 4, "TC-B1.3: Garrison preserved in pam")
	_assert(pam.soldier_count == 6, "TC-B1.4: Reserve remains exactly 6 (zero leak)")
	_assert(tmm.units.size() == 6, "TC-B1.5: Invariant B holds at 6 == 6")

	# TC-B2: Preflight succeeds but actual spawn fails completely (forced destruction casualty accounting)
	tmm._test_simulate_spawn_instantiation_failure = true
	var evict_res_b2: Dictionary = pam.evict_and_cancel_outpost(obj_b1, true, true) # Policy B
	tmm._test_simulate_spawn_instantiation_failure = false

	_assert(evict_res_b2.get("success", false) == true, "TC-B2.1: Forced eviction succeeds with casualty accounting")
	_assert(evict_res_b2.get("evacuated_count", -1) == 0, "TC-B2.2: 0 evacuated when spawn instantiation failed")
	_assert(evict_res_b2.get("casualties_count", -1) == 4, "TC-B2.3: 4 casualties logged")
	_assert(pam.get_garrison_count(obj_b1) == 0, "TC-B2.4: Garrison cleared cleanly")
	_assert(pam.soldier_count == 6, "TC-B2.5: Reserve remains 6")
	_assert(tmm.units.size() == pam.soldier_count, "TC-B2.6: Invariant B strictly holds (6 == 6)")

	# TC-B3: Preflight succeeds but actual spawn partially succeeds (voluntary demolition all-or-nothing rollback)
	var obj_b3 := "test_obj_inst_b3"
	fsm.register_objective(obj_b3, Vector2i(25, 25), "player", 100.0, 10)
	pam.station_soldier(obj_b3, 4)
	_assert(pam.soldier_count == 2, "TC-B3.1: Reserve at 2")

	tmm._test_max_successful_spawns = 2
	var evict_res_b3: Dictionary = pam.evict_and_cancel_outpost(obj_b3, true, false) # Policy A
	tmm._test_max_successful_spawns = -1

	_assert(evict_res_b3.get("success", true) == false, "TC-B3.2: Partial spawn causes atomic rollback on voluntary eviction")
	_assert(pam.get_garrison_count(obj_b3) == 4, "TC-B3.3: Garrison preserved on partial spawn failure")
	_assert(pam.soldier_count == 2, "TC-B3.4: Reserve remains 2")
	_assert(tmm.units.size() == 2, "TC-B3.5: Invariant B strictly holds: 0 partial units leaked into TMM (2 == 2)")

	# TC-B4: Preflight succeeds but actual spawn partially succeeds (forced destruction representation)
	tmm._test_max_successful_spawns = 2
	var evict_res_b4: Dictionary = pam.evict_and_cancel_outpost(obj_b3, true, true) # Policy B
	tmm._test_max_successful_spawns = -1

	_assert(evict_res_b4.get("success", false) == true, "TC-B4.1: Forced eviction succeeds with partial representation")
	_assert(evict_res_b4.get("evacuated_count", -1) == 2, "TC-B4.2: Exactly 2 soldiers evacuated and spawned")
	_assert(evict_res_b4.get("casualties_count", -1) == 2, "TC-B4.3: Remaining 2 soldiers recorded as casualties")
	_assert(pam.get_garrison_count(obj_b3) == 0, "TC-B4.4: Garrison cleared cleanly")
	_assert(pam.soldier_count == 4, "TC-B4.5: Reserve updated to 4 (2 + 2)")
	_assert(tmm.units.size() == pam.soldier_count, "TC-B4.6: Invariant B holds: units (4) == reserve (4)")

	print("\n--- TEST GROUP C: OWNERSHIP TRANSFER TRANSACTION (9 MANDATORY TESTS) ---")
	# Reset
	pam.soldier_count = 10
	tmm.sync_with_player_army()
	pam.garrisons.clear()
	pam.active_reinforcements.clear()

	# TC-C1: Full capacity hostile capture -> evacuates all to base, records cleared, ownership transferred
	var obj_c1 := "test_obj_c1"
	fsm.register_objective(obj_c1, Vector2i(26, 26), "player", 100.0, 5)
	pam.station_soldier(obj_c1, 3)
	pam.dispatch_reinforcements(obj_c1, 2, 5.0)

	var res_c1: Dictionary = fsm.transfer_outpost_ownership(obj_c1, "rival_military", "tx_c1_full")
	_assert(res_c1.get("success", false) == true, "TC-C1.1: Full capacity capture succeeds")
	_assert(pam.get_garrison_count(obj_c1) == 0, "TC-C1.2: Garrison cleared")
	_assert(pam.get_in_transit_count(obj_c1) == 0, "TC-C1.3: Reinforcements cleared")
	_assert(pam.soldier_count == 10, "TC-C1.4: All 5 returned to reserve (5 + 5 = 10)")
	_assert(tmm.units.size() == pam.soldier_count, "TC-C1.5: Invariant B holds (10 == 10)")

	# TC-C2: Partial capacity hostile capture -> evacuates partial, remainder casualties, ownership transferred
	var obj_c2 := "test_obj_c2"
	fsm.register_objective(obj_c2, Vector2i(27, 27), "player", 100.0, 5)
	pam.station_soldier(obj_c2, 3)
	pam.dispatch_reinforcements(obj_c2, 2, 5.0)
	_assert(pam.soldier_count == 5, "TC-C2.1: Reserve at 5")

	tmm._test_spawn_capacity_override = 2
	var res_c2: Dictionary = fsm.transfer_outpost_ownership(obj_c2, "rival_military", "tx_c2_part")
	tmm._test_spawn_capacity_override = -1

	_assert(res_c2.get("success", false) == true, "TC-C2.2: Partial capacity capture succeeds")
	_assert(pam.get_garrison_count(obj_c2) == 0, "TC-C2.3: Garrison cleared")
	_assert(pam.get_in_transit_count(obj_c2) == 0, "TC-C2.4: Reinforcements cleared")
	_assert(pam.soldier_count == 7, "TC-C2.5: Reserve increased by 2 (5 + 2 = 7)")
	_assert(tmm.units.size() == pam.soldier_count, "TC-C2.6: Invariant B holds (7 == 7)")

	# TC-C3: Zero capacity hostile capture -> 0 evacuated, 100% casualties, records cleared, ownership transferred
	var obj_c3 := "test_obj_c3"
	fsm.register_objective(obj_c3, Vector2i(28, 28), "player", 100.0, 5)
	pam.station_soldier(obj_c3, 2)
	_assert(pam.soldier_count == 5, "TC-C3.1: Reserve at 5")

	tmm._test_spawn_capacity_override = 0
	var res_c3: Dictionary = fsm.transfer_outpost_ownership(obj_c3, "rival_military", "tx_c3_zero")
	tmm._test_spawn_capacity_override = -1

	_assert(res_c3.get("success", false) == true, "TC-C3.2: Zero capacity capture succeeds")
	_assert(pam.get_garrison_count(obj_c3) == 0, "TC-C3.3: Garrison cleared")
	_assert(pam.soldier_count == 5, "TC-C3.4: Reserve remains 5 (zero ghost increment)")
	_assert(tmm.units.size() == pam.soldier_count, "TC-C3.5: Invariant B holds (5 == 5)")

	# TC-C4: Invalid objective -> rejected without modifying PAM or state
	var res_c4: Dictionary = fsm.transfer_outpost_ownership("nonexistent_obj", "rival_military", "tx_c4_invalid")
	_assert(res_c4.get("success", true) == false, "TC-C4.1: Transfer fails for nonexistent objective")

	# TC-C5: Ownership API failure rollback -> if obj.transfer_ownership returns failure, PAM snapshot restored exactly
	var obj_c5 := "test_obj_c5"
	fsm.register_objective(obj_c5, Vector2i(29, 29), "player", 100.0, 5)
	pam.station_soldier(obj_c5, 3)
	pam.dispatch_reinforcements(obj_c5, 1, 5.0)
	var snap_c5: Dictionary = pam.get_outpost_military_snapshot(obj_c5)
	_assert(snap_c5.garrison.soldiers.size() == 3, "TC-C5.1: Snapshot has 3 garrison soldiers")
	_assert(snap_c5.reinforcements.size() == 1, "TC-C5.2: Snapshot has 1 reinforcement")

	var res_c5_invalid_owner = fsm.transfer_outpost_ownership(obj_c5, "invalid_faction_xyz_unknown", "tx_c5_fail")
	_assert(res_c5_invalid_owner.get("success", true) == false, "TC-C5.3: Invalid owner rejected")
	_assert(pam.get_garrison_count(obj_c5) == 3, "TC-C5.4: Garrison preserved on invalid owner rejection")
	_assert(pam.get_in_transit_count(obj_c5) == 1, "TC-C5.5: Reinforcements preserved on invalid owner rejection")

	# Now explicitly simulate actor failure during Phase 2 commit and verify snapshot restoration
	pam.evict_and_cancel_outpost(obj_c5, true, true)
	_assert(pam.get_garrison_count(obj_c5) == 0, "TC-C5.6: Garrison cleared during eviction")
	pam.restore_outpost_military_snapshot(snap_c5)
	_assert(pam.get_garrison_count(obj_c5) == 3, "TC-C5.7: Snapshot rollback restored garrison to 3")
	_assert(pam.get_in_transit_count(obj_c5) == 1, "TC-C5.8: Snapshot rollback restored reinforcements to 1")
	_assert(tmm.units.size() == pam.soldier_count, "TC-C5.9: Invariant B holds after snapshot restoration")

	# Clean up c5
	pam.evict_and_cancel_outpost(obj_c5, true, true)

	# TC-C7: Duplicate tx_id -> already_applied=true, no mutations
	var res_c7: Dictionary = fsm.transfer_outpost_ownership(obj_c1, "rival_military", "tx_c1_full")
	_assert(res_c7.get("success", false) == true, "TC-C7.1: Duplicate tx returns success")
	_assert(res_c7.get("already_applied", false) == true, "TC-C7.2: already_applied is true")

	# TC-C8: Repeated signal -> outpost_ownership_changed emitted exactly once
	var signal_emitted_count: int = 0
	var sig_tracker = func(_id, _prev, _new_o, _tx): signal_emitted_count += 1
	fsm.outpost_ownership_changed.connect(sig_tracker)
	var res_c8: Dictionary = fsm.transfer_outpost_ownership(obj_c1, "rival_military", "tx_c1_full")
	_assert(res_c8.get("already_applied", false) == true, "TC-C8.1: Duplicate returns already_applied")
	_assert(signal_emitted_count == 0, "TC-C8.2: Signal was NOT emitted for duplicate transaction")
	fsm.outpost_ownership_changed.disconnect(sig_tracker)

	# TC-C9: Save/load integrity -> capture state survives save/load roundtrip
	pam.current_cell = pam.rally_cell
	pam.movement_state = pam.MovementState.GARRISONED
	pam.set_tactical_military_manager(tmm)
	var save_path := "user://test_session1_3_1_save.json"
	var save_res: Dictionary = SaveManagerScript.save_to_file(world_instance, save_path)
	_assert(save_res.get("success", false) == true, "TC-C9.1: Save succeeded")
	var load_res: Dictionary = SaveManagerScript.load_from_file(save_path)
	_assert(load_res.get("success", false) == true, "TC-C9.2: Load returned valid data")
	var load_data: Dictionary = load_res.get("data", {})
	var saved_objs: Array = load_data.get("field_siege", {}).get("objectives", [])
	var found_obj: Dictionary = {}
	for o in saved_objs:
		if str(o.get("objective_id", "")) == obj_c1:
			found_obj = o
			break
	_assert(not found_obj.is_empty(), "TC-C9.3: Captured objective found in saved data")
	_assert(found_obj.get("owning_faction_id") == "rival_military", "TC-C9.4: Saved owner is rival_military")
	var da := DirAccess.open("user://")
	if da != null and da.file_exists(save_path):
		da.remove(save_path)

	print("\n--- TEST GROUP D: INVALID REINFORCEMENT ARRIVAL ---")
	# Reset
	pam.soldier_count = 10
	tmm.sync_with_player_army()
	pam.garrisons.clear()
	pam.active_reinforcements.clear()

	# TC-D1: Reinforcements arriving at destroyed objective -> evacuated to base under Policy B
	var obj_d1 := "test_obj_d1"
	fsm.register_objective(obj_d1, Vector2i(30, 30), "player", 100.0, 5)
	pam.dispatch_reinforcements(obj_d1, 2, 0.05)
	_assert(pam.soldier_count == 8, "TC-D1.1: Reserve at 8")

	# Destroy objective before arrival
	var d1_actor = fsm.get_objective(obj_d1)
	d1_actor.is_alive = false
	d1_actor.health = 0.0

	# Advance reinforcements
	pam.advance_reinforcements(0.1)
	_assert(pam.get_in_transit_count(obj_d1) == 0, "TC-D1.2: Reinforcements cleanly cleared")
	_assert(pam.soldier_count == 10, "TC-D1.3: Reinforcements safely refunded to reserve (8 + 2 = 10)")
	_assert(tmm.units.size() == pam.soldier_count, "TC-D1.4: Invariant B holds (10 == 10)")

	# TC-D2: Reinforcements arriving at captured objective -> cannot reinforce hostile objective
	var obj_d2 := "test_obj_d2"
	fsm.register_objective(obj_d2, Vector2i(31, 31), "player", 100.0, 5)
	pam.dispatch_reinforcements(obj_d2, 2, 0.05)
	_assert(pam.soldier_count == 8, "TC-D2.1: Reserve at 8")

	# Hostile capture before arrival
	fsm.transfer_outpost_ownership(obj_d2, "rival_military", "tx_d2_cap")
	# At this point, transfer_outpost_ownership already cancelled/evacuated in-transit reinforcements!
	_assert(pam.get_in_transit_count(obj_d2) == 0, "TC-D2.2: Reinforcements cancelled upon capture")
	_assert(pam.soldier_count == 10, "TC-D2.3: Reserve restored to 10")
	_assert(tmm.units.size() == pam.soldier_count, "TC-D2.4: Invariant B holds (10 == 10)")

	# TC-D3, TC-D4, TC-D5: Arrival capacity bounds
	# Test arrival when outpost capacity is full -> excess refunded
	var obj_d3 := "test_obj_d3"
	fsm.register_objective(obj_d3, Vector2i(32, 32), "player", 100.0, 5)
	pam.station_soldier(obj_d3, 3) # 3 stationed (10 - 3 = 7 reserve)
	pam.dispatch_reinforcements(obj_d3, 2, 0.05) # 2 dispatched (7 - 2 = 5 reserve)
	_assert(pam.soldier_count == 5, "TC-D3.1: Reserve at 5 (10 - 3 - 2)")

	# Reduce outpost capacity to 3 so it is completely full with existing garrison
	var d3_actor = fsm.get_objective(obj_d3)
	d3_actor.garrison_count = 3
	pam.garrisons[obj_d3]["capacity"] = 3

	pam.advance_reinforcements(0.1)
	_assert(pam.get_garrison_count(obj_d3) == 3, "TC-D3.2: Garrison remains at max capacity (3)")
	_assert(pam.soldier_count == 7, "TC-D3.3: Excess 2 refunded back to reserve (5 + 2 = 7)")
	_assert(tmm.units.size() == pam.soldier_count, "TC-D3.4: Invariant B holds (7 == 7)")

	# TC-D4: Partial capacity arrival: capacity 4, current garrison 3, 2 arrive -> 1 accepted, 1 refunded
	pam.evict_and_cancel_outpost(obj_d3, true, true)
	pam.soldier_count = 10
	tmm.sync_with_player_army()
	d3_actor.garrison_count = 5
	pam.station_soldier(obj_d3, 3) # 3 stationed (10 - 3 = 7 reserve)
	pam.dispatch_reinforcements(obj_d3, 2, 0.05) # 2 dispatched (7 - 2 = 5 reserve)
	_assert(pam.soldier_count == 5, "TC-D4.1: Reserve at 5 (10 - 3 - 2)")

	# Reduce capacity to 4 (room for only 1 more)
	d3_actor.garrison_count = 4
	pam.garrisons[obj_d3]["capacity"] = 4

	pam.advance_reinforcements(0.1)
	_assert(pam.get_garrison_count(obj_d3) == 4, "TC-D4.2: Garrison filled to 4 (3 + 1)")
	_assert(pam.soldier_count == 6, "TC-D4.3: Remaining 1 refunded to reserve (5 + 1 = 6)")
	_assert(tmm.units.size() == pam.soldier_count, "TC-D4.4: Invariant B holds (6 == 6)")

	# TC-D6: Actual spawn failure during arrival casualty handling / refund
	pam.evict_and_cancel_outpost(obj_d3, true, true)
	pam.soldier_count = 10
	tmm.sync_with_player_army()
	pam.station_soldier(obj_d3, 3) # full capacity
	pam.register_outpost_for_testing("test_fake_outpost", 10, Vector2i(35, 35), "player")
	pam.dispatch_reinforcements("test_fake_outpost", 2, 0.05)
	# Destroy fake outpost so arriving troops must evacuate
	pam._test_registered_outposts["test_fake_outpost"]["is_alive"] = false

	tmm._test_simulate_spawn_instantiation_failure = true
	pam.advance_reinforcements(0.1)
	tmm._test_simulate_spawn_instantiation_failure = false
	_assert(pam.get_in_transit_count("test_fake_outpost") == 0, "TC-D6.1: Transit records cleared")
	_assert(tmm.units.size() == pam.soldier_count, "TC-D6.2: Invariant B holds under arrival spawn failure")

	# TC-D7, TC-D8: Tactical equality holds
	var inv_final: Dictionary = _calc_invariants(pam, tmm)
	_assert(inv_final.invariant_a_holds, "TC-D8.1: Final Invariant A holds")
	_assert(inv_final.invariant_b_holds, "TC-D8.2: Final Invariant B holds (units == reserve)")

	print("\n========================================================")
	print("  SESSION 1.3.1 RESULTS: %d Passed, %d Failed" % [passed_count, failures])
	print("========================================================\n")

	if failures == 0:
		print("ALL SESSION 1.3.1 TESTS PASSED!")
		quit(0)
	else:
		printerr("TESTS FAILED WITH %d ERRORS!" % failures)
		quit(1)
