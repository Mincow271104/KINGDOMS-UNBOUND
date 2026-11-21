extends SceneTree
## Test Suite: Session 1.3 Final Military Transaction Closure & Invariant Enforcement
## Validates Authoritative Architectural Policies:
## Policy A: Voluntary Demolition (Strict all-or-nothing fail-closed)
## Policy B: Forced Destruction & Hostile Capture (Evacuate up to spawn capacity, rest casualties, zero ghost records)
## Policy C: Invalid Reinforcement Arrival (Evacuate up to spawn capacity, rest casualties, zero blind increments)
## Policy D: Ownership Transfer Unified Military Transaction
## Group E: Save/Load and ID Monotonicity across all lifecycles

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
	print("  STARTING SESSION 1.3 TRANSACTION CLOSURE TEST SUITE")
	print("========================================================\n")
	world_instance = WorldViewScene.instantiate()
	world_instance.world_seed = 6060
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

	print("\n--- TEST GROUP A: OWNERSHIP TRANSFER ATOMICITY (POLICY B & D) ---")
	# A1: Full spawn capacity (G=3, T=2, capacity >= 5)
	pam.soldier_count = 10
	tmm.sync_with_player_army()
	pam.garrisons.clear()
	pam.active_reinforcements.clear()

	var obj_a1 := "test_obj_transfer_full"
	fsm.register_objective(obj_a1, Vector2i(20, 20), "player", 100.0, 5)
	pam.station_soldier(obj_a1, 3)
	pam.dispatch_reinforcements(obj_a1, 2, 4.0)

	var inv_a1_pre: Dictionary = _calc_invariants(pam, tmm)
	_assert(inv_a1_pre.reserve == 5, "TC-A1.1: Pre-transfer reserve is 5")
	_assert(inv_a1_pre.garrisoned == 3, "TC-A1.2: Pre-transfer garrison is 3")
	_assert(inv_a1_pre.in_transit == 2, "TC-A1.3: Pre-transfer transit is 2")
	_assert(inv_a1_pre.total_headcount == 10, "TC-A1.4: Pre-transfer total is 10")
	_assert(inv_a1_pre.invariant_b_holds, "TC-A1.5: Pre-transfer tactical equality holds (5 == 5)")

	var res_a1: Dictionary = fsm.transfer_outpost_ownership(obj_a1, "rival_military", "tx_transfer_a1")
	_assert(res_a1.get("success", false) == true, "TC-A1.6: transfer_outpost_ownership succeeded")
	_assert(pam.get_garrison_count(obj_a1) == 0, "TC-A1.7: Garrison cleanly cleared")
	_assert(pam.get_in_transit_count(obj_a1) == 0, "TC-A1.8: In-transit reinforcements cleanly cleared")
	_assert(pam.soldier_count == 10, "TC-A1.9: All 5 soldiers safely returned to central reserve (10)")

	var inv_a1_post: Dictionary = _calc_invariants(pam, tmm)
	_assert(inv_a1_post.total_headcount == 10, "TC-A1.10: Invariant A holds at 10")
	_assert(inv_a1_post.tactical_units == 10, "TC-A1.11: Tactical units synced to 10")
	_assert(inv_a1_post.invariant_b_holds, "TC-A1.12: Invariant B holds at 10 == 10")

	# A2: Partial spawn capacity (G=3, T=2, only 3 spawns available -> 3 return, 2 casualties)
	pam.soldier_count = 10
	tmm.sync_with_player_army()
	var obj_a2 := "test_obj_transfer_partial"
	fsm.register_objective(obj_a2, Vector2i(22, 22), "player", 100.0, 5)
	pam.station_soldier(obj_a2, 3)
	pam.dispatch_reinforcements(obj_a2, 2, 4.0)

	tmm._test_spawn_capacity_override = 3

	var res_a2: Dictionary = fsm.transfer_outpost_ownership(obj_a2, "rival_military", "tx_transfer_a2")
	tmm._test_spawn_capacity_override = -1
	_assert(res_a2.get("success", false) == true, "TC-A2.1: Transfer succeeds under forced capture policy")
	_assert(pam.get_garrison_count(obj_a2) == 0, "TC-A2.2: Garrison record cleared")
	_assert(pam.get_in_transit_count(obj_a2) == 0, "TC-A2.3: In-transit record cleared (0 ghost records)")
	_assert(pam.soldier_count == 8, "TC-A2.4: Exactly 3 soldiers returned to reserve (5 + 3 = 8)")
	_assert(pam.get_total_soldier_count() == 8, "TC-A2.5: Total headcount is 8 (2 accounted as casualties)")

	var inv_a2_post: Dictionary = _calc_invariants(pam, tmm)
	_assert(inv_a2_post.invariant_a_holds, "TC-A2.6: Invariant A strictly holds at 8")
	_assert(inv_a2_post.invariant_b_holds, "TC-A2.7: Invariant B strictly holds (8 units == 8 reserve)")

	# A3: Zero spawn capacity (G=2, T=1, 0 spawns available -> all 3 become casualties)
	pam.soldier_count = 8
	tmm.sync_with_player_army()
	var obj_a3 := "test_obj_transfer_zero"
	fsm.register_objective(obj_a3, Vector2i(24, 24), "player", 100.0, 5)
	pam.station_soldier(obj_a3, 2)
	pam.dispatch_reinforcements(obj_a3, 1, 4.0)

	tmm._test_spawn_capacity_override = 0

	var res_a3: Dictionary = fsm.transfer_outpost_ownership(obj_a3, "rival_military", "tx_transfer_a3")
	tmm._test_spawn_capacity_override = -1
	_assert(res_a3.get("success", false) == true, "TC-A3.1: Transfer succeeds under zero spawn capacity")
	_assert(pam.get_garrison_count(obj_a3) == 0, "TC-A3.2: Garrison record cleared")
	_assert(pam.get_in_transit_count(obj_a3) == 0, "TC-A3.3: In-transit record cleared")
	_assert(pam.soldier_count == 5, "TC-A3.4: Central reserve unchanged at 5 (all 3 became casualties)")
	_assert(pam.get_total_soldier_count() == 5, "TC-A3.5: Total headcount updated to 5")

	var inv_a3_post: Dictionary = _calc_invariants(pam, tmm)
	_assert(inv_a3_post.invariant_a_holds, "TC-A3.6: Invariant A holds at 5")
	_assert(inv_a3_post.invariant_b_holds, "TC-A3.7: Invariant B holds at 5 == 5")

	# A4: Duplicate transaction ID
	var dup_res: Dictionary = fsm.transfer_outpost_ownership(obj_a1, "rival_military", "tx_transfer_a1")
	_assert(dup_res.get("already_applied", false) == true, "TC-A4.1: Duplicate tx_id flagged already_applied")
	_assert(pam.soldier_count == 5, "TC-A4.2: Duplicate tx_id does not mutate reserve")
	_assert(pam.get_total_soldier_count() == 5, "TC-A4.3: Duplicate tx_id does not mutate total headcount")

	# A5: Invalid objective or ownership transfer failure
	var fail_invalid: Dictionary = fsm.transfer_outpost_ownership("non_existent_obj_999", "rival_military", "tx_invalid")
	_assert(fail_invalid.get("success", true) == false, "TC-A5.1: Invalid objective rejected")
	_assert(pam.soldier_count == 5, "TC-A5.2: Invalid transfer does not mutate reserve")

	print("\n--- TEST GROUP B: FORCED DESTRUCTION (POLICY B) ---")
	# B1: Destroy building with sufficient spawn capacity
	pam.soldier_count = 10
	tmm.sync_with_player_army()
	var obj_b1 := "test_obj_destruct_full"
	fsm.register_objective(obj_b1, Vector2i(26, 26), "player", 100.0, 4)
	pam.station_soldier(obj_b1, 2)
	pam.dispatch_reinforcements(obj_b1, 1, 3.0)

	var actor_b1 = fsm.get_objective(obj_b1)
	actor_b1.is_under_active_siege = true
	actor_b1.take_damage(100.0, "attacker_enemy")

	_assert(pam.get_garrison_count(obj_b1) == 0, "TC-B1.1: Garrison evicted on destruction")
	_assert(pam.get_in_transit_count(obj_b1) == 0, "TC-B1.2: Transit cancelled on destruction")
	_assert(pam.soldier_count == 10, "TC-B1.3: All 3 soldiers refunded to central reserve (10)")
	var inv_b1 := _calc_invariants(pam, tmm)
	_assert(inv_b1.invariant_a_holds, "TC-B1.4: Invariant A holds (10)")
	_assert(inv_b1.invariant_b_holds, "TC-B1.5: Invariant B holds (10 == 10)")

	# B2: Destroy building with partial spawn capacity (G=2, T=1, only 1 spawn available -> 1 evacuated, 2 casualties)
	var obj_b2 := "test_obj_destruct_partial"
	fsm.register_objective(obj_b2, Vector2i(28, 28), "player", 100.0, 4)
	pam.station_soldier(obj_b2, 2)
	pam.dispatch_reinforcements(obj_b2, 1, 3.0)

	tmm._test_spawn_capacity_override = 1

	var actor_b2 = fsm.get_objective(obj_b2)
	actor_b2.is_under_active_siege = true
	actor_b2.take_damage(100.0, "attacker_enemy")
	tmm._test_spawn_capacity_override = -1

	_assert(pam.get_garrison_count(obj_b2) == 0, "TC-B2.1: Garrison record cleared on partial destruction")
	_assert(pam.get_in_transit_count(obj_b2) == 0, "TC-B2.2: Transit record cleared (0 ghost records)")
	_assert(pam.soldier_count == 8, "TC-B2.3: 1 evacuated (7 + 1 = 8)")
	_assert(pam.get_total_soldier_count() == 8, "TC-B2.4: 2 became casualties (total 8)")
	var inv_b2 := _calc_invariants(pam, tmm)
	_assert(inv_b2.invariant_a_holds, "TC-B2.5: Invariant A holds at 8")
	_assert(inv_b2.invariant_b_holds, "TC-B2.6: Invariant B holds at 8 == 8")

	# B3: Destroy building with zero spawn capacity (G=2, 0 spawns available -> all 2 casualties)
	pam.soldier_count = 8
	tmm.sync_with_player_army()
	var obj_b3 := "test_obj_destruct_zero"
	fsm.register_objective(obj_b3, Vector2i(30, 30), "player", 100.0, 4)
	pam.station_soldier(obj_b3, 2)

	tmm._test_spawn_capacity_override = 0

	var actor_b3 = fsm.get_objective(obj_b3)
	actor_b3.is_under_active_siege = true
	actor_b3.take_damage(100.0, "attacker_enemy")
	tmm._test_spawn_capacity_override = -1

	_assert(pam.get_garrison_count(obj_b3) == 0, "TC-B3.1: Garrison record cleared on zero spawn destruction")
	_assert(pam.soldier_count == 6, "TC-B3.2: Reserve unchanged at 6 (both became casualties)")
	_assert(pam.get_total_soldier_count() == 6, "TC-B3.3: Total headcount updated to 6")
	var inv_b3 := _calc_invariants(pam, tmm)
	_assert(inv_b3.invariant_a_holds, "TC-B3.4: Invariant A holds at 6")
	_assert(inv_b3.invariant_b_holds, "TC-B3.5: Invariant B holds at 6 == 6")

	# B4 & B5: Repeated destruction signal emission idempotency
	fsm.objective_destroyed.emit(obj_b1, "repeated_attacker")
	_assert(pam.soldier_count == 6, "TC-B5.1: Repeated destruction signal does not double refund")
	_assert(pam.get_total_soldier_count() == 6, "TC-B5.2: Repeated destruction signal does not double deduct")
	var inv_b5 := _calc_invariants(pam, tmm)
	_assert(inv_b5.invariant_a_holds, "TC-B5.3: Invariant A holds on repeat")
	_assert(inv_b5.invariant_b_holds, "TC-B5.4: Invariant B holds on repeat")

	print("\n--- TEST GROUP C: VOLUNTARY DEMOLITION (POLICY A) ---")
	pam.soldier_count = 10
	tmm.sync_with_player_army()
	pam.garrisons.clear()
	pam.active_reinforcements.clear()

	# C1: Enough spawn cells -> demolition succeeds and all soldiers returned
	var bld_c1 := "bld_watchtower_c1"
	_create_active_watchtower(bld_c1, Vector2i(14, 14))
	pam.station_soldier(bld_c1, 1)
	pam.dispatch_reinforcements(bld_c1, 1, 3.0)
	_assert(pam.soldier_count == 8, "TC-C1.1: Pre-demolish reserve is 8")
	_assert(pam.get_total_soldier_count() == 10, "TC-C1.2: Pre-demolish total is 10")

	var demo_res: Dictionary = world_instance.demolish_building_project(bld_c1)
	_assert(demo_res.get("success", false) == true, "TC-C1.3: Demolition succeeded when cells available")
	_assert(pam.get_garrison_count(bld_c1) == 0, "TC-C1.4: Garrison cleared")
	_assert(pam.get_in_transit_count(bld_c1) == 0, "TC-C1.5: Transit cleared")
	_assert(pam.soldier_count == 10, "TC-C1.6: All 2 soldiers refunded to central reserve (10)")
	var inv_c1 := _calc_invariants(pam, tmm)
	_assert(inv_c1.invariant_a_holds, "TC-C1.7: Invariant A holds at 10")
	_assert(inv_c1.invariant_b_holds, "TC-C1.8: Invariant B holds at 10 == 10")

	# C2 & C3: Insufficient spawn cells -> demolition fails closed
	var bld_c2 := "bld_watchtower_c2"
	_create_active_watchtower(bld_c2, Vector2i(15, 15))
	pam.station_soldier(bld_c2, 2)
	_assert(pam.soldier_count == 8, "TC-C2.1: Pre-demolish reserve is 8")

	tmm._test_spawn_capacity_override = 1 # Only 1 spawn allowed, 2 needed

	var demo_fail: Dictionary = world_instance.demolish_building_project(bld_c2)
	_assert(demo_fail.get("success", true) == false, "TC-C2.2: Demolition fails closed when spawn cells insufficient")
	_assert(pam.get_garrison_count(bld_c2) == 2, "TC-C2.3: Garrison preserved in building")
	_assert(pam.soldier_count == 8, "TC-C2.4: Central reserve untouched at 8")
	_assert(pam.get_total_soldier_count() == 10, "TC-C2.5: Total headcount untouched at 10")
	var inv_c2 := _calc_invariants(pam, tmm)
	_assert(inv_c2.invariant_a_holds, "TC-C2.6: Invariant A holds")
	_assert(inv_c2.invariant_b_holds, "TC-C2.7: Invariant B holds")

	# C4: Clean up bld_c2 with full capacity
	tmm._test_spawn_capacity_override = -1
	var demo_c2_ok: Dictionary = world_instance.demolish_building_project(bld_c2)
	_assert(demo_c2_ok.get("success", false) == true, "TC-C4.1: Demolition succeeds once cells freed")
	_assert(pam.soldier_count == 10, "TC-C4.2: Reserve restored to 10")

	print("\n--- TEST GROUP D: INVALID REINFORCEMENT ARRIVAL (POLICY C) ---")
	pam.soldier_count = 10
	tmm.sync_with_player_army()
	pam.garrisons.clear()
	pam.active_reinforcements.clear()

	# D1 & D3: Reinforcement arrives at destroyed objective with sufficient spawn capacity
	var obj_d1 := "test_obj_arrival_destruct"
	fsm.register_objective(obj_d1, Vector2i(32, 32), "player", 100.0, 4)
	pam.dispatch_reinforcements(obj_d1, 2, 2.0)
	_assert(pam.soldier_count == 8, "TC-D1.1: Reserve is 8 after dispatch")

	# Destroy objective before reinforcement arrives
	pam._test_registered_outposts[obj_d1] = {"owner": "rival_military", "is_alive": false}
	pam.advance_reinforcements(3.0)
	_assert(pam.get_in_transit_count(obj_d1) == 0, "TC-D1.2: Transit record cleared on dead outpost arrival")
	_assert(pam.soldier_count == 10, "TC-D1.3: 2 soldiers safely retreated to central reserve (8 + 2 = 10)")
	var inv_d1 := _calc_invariants(pam, tmm)
	_assert(inv_d1.invariant_a_holds, "TC-D1.4: Invariant A holds")
	_assert(inv_d1.invariant_b_holds, "TC-D1.5: Invariant B holds")

	# D2: Reinforcement arrives at captured objective with sufficient spawn capacity
	var obj_d2 := "test_obj_arrival_captured"
	pam.register_outpost_for_testing(obj_d2, 4, Vector2i(35, 35), "player")
	pam.dispatch_reinforcements(obj_d2, 2, 2.0)
	_assert(pam.soldier_count == 8, "TC-D2.1: Reserve is 8 during transit")

	# Hostile capture while in transit
	pam._test_registered_outposts[obj_d2]["owner"] = "rival_military"

	# Arrival with sufficient capacity
	pam.advance_reinforcements(3.0)
	_assert(pam.get_garrison_count(obj_d2) == 0, "TC-D2.2: No troops stationed at hostile outpost")
	_assert(pam.get_in_transit_count(obj_d2) == 0, "TC-D2.3: Transit record cleared")
	_assert(pam.soldier_count == 10, "TC-D2.4: 2 soldiers safely retreated to central reserve (8 + 2 = 10)")
	var inv_d2 := _calc_invariants(pam, tmm)
	_assert(inv_d2.invariant_a_holds, "TC-D2.5: Invariant A holds")
	_assert(inv_d2.invariant_b_holds, "TC-D2.6: Invariant B holds")

	# D4: Arrival at captured objective with INSUFFICIENT spawn capacity (Policy C: casualties)
	var obj_d3 := "test_obj_arrival_congested"
	pam.register_outpost_for_testing(obj_d3, 4, Vector2i(38, 38), "player")
	pam.dispatch_reinforcements(obj_d3, 3, 2.0)
	_assert(pam.soldier_count == 7, "TC-D4.1: Reserve is 7 during transit (10 - 3 = 7)")
	pam._test_registered_outposts[obj_d3]["owner"] = "rival_military"

	# Mock only 1 spawn available for 3 arriving soldiers -> 1 returns, 2 casualties
	tmm._test_spawn_capacity_override = 1

	pam.advance_reinforcements(3.0)
	tmm._test_spawn_capacity_override = -1
	_assert(pam.get_garrison_count(obj_d3) == 0, "TC-D4.2: No soldiers stationed in hostile outpost")
	_assert(pam.get_in_transit_count(obj_d3) == 0, "TC-D4.3: Transit cleared cleanly")
	_assert(pam.soldier_count == 8, "TC-D4.4: Exactly 1 soldier returned to reserve (7 + 1 = 8)")
	_assert(pam.get_total_soldier_count() == 8, "TC-D4.5: 2 soldiers became casualties (total 8)")
	var inv_d4 := _calc_invariants(pam, tmm)
	_assert(inv_d4.invariant_a_holds, "TC-D4.6: Invariant A holds at 8")
	_assert(inv_d4.invariant_b_holds, "TC-D4.7: Invariant B holds at 8 == 8")

	print("\n--- TEST GROUP E: SAVE/LOAD & ID MONOTONICITY ---")
	pam.set_tactical_military_manager(tmm)
	# E1 & E2: Save/load after capture and destruction with casualties
	var test_slot := "user://test_session1_3_persistence.json"
	var save_res: Dictionary = SaveManagerScript.save_to_file(world_instance, test_slot)
	_assert(save_res.get("success", false) == true, "TC-E1.1: Save succeeded post-casualties")

	var load_res: Dictionary = SaveManagerScript.load_from_file(test_slot)
	_assert(load_res.get("success", false) == true, "TC-E1.2: Load succeeded")
	var apply_res: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, load_res.get("data", {}))
	_assert(apply_res.get("success", false) == true, "TC-E1.3: Applied loaded state")

	_assert(pam.soldier_count == 8, "TC-E1.4: Restored soldier count is 8")
	_assert(pam.get_all_garrisoned_count() == 0, "TC-E1.5: 0 ghost garrisons after load")
	_assert(pam.get_in_transit_count() == 0, "TC-E1.6: 0 ghost reinforcements after load")
	_assert(pam.get_total_soldier_count() == 8, "TC-E1.7: Total headcount restored to 8")
	var inv_e1 := _calc_invariants(pam, tmm)
	_assert(inv_e1.invariant_a_holds, "TC-E1.8: Invariant A holds across save/load")
	_assert(inv_e1.invariant_b_holds, "TC-E1.9: Invariant B holds across save/load")

	# E4 & E5: Legacy save without ID counters, followed by station and dispatch
	pam.register_outpost_for_testing("outpost_leg_e", 10, Vector2i(40, 40), "player")
	pam.next_soldier_id = 1
	pam.next_reinforce_id = 1
	var legacy_dict: Dictionary = {
		"soldier_count": 8,
		"equipment_tier": 1,
		"garrisons": {
			"outpost_leg_e": {
				"capacity": 10,
				"soldiers": [
					{"soldier_id": "soldier_gar_200", "equipment_tier": 1, "health": 100.0},
					{"soldier_id": "soldier_gar_250", "equipment_tier": 1, "health": 100.0}
				]
			}
		},
		"reinforcements": [
			{
				"dispatch_id": "reinf_90",
				"outpost_id": "outpost_leg_e",
				"soldier_count": 1,
				"soldiers": [{"soldier_id": "soldier_reinf_275", "equipment_tier": 1, "health": 100.0}]
			}
		]
	}

	pam.deserialize_garrisons(legacy_dict)
	_assert(pam.next_soldier_id == 276, "TC-E4.1: next_soldier_id recomputed past max(275) -> 276")
	_assert(pam.next_reinforce_id == 91, "TC-E4.2: next_reinforce_id recomputed past max(90) -> 91")

	var stat_res: Dictionary = pam.station_soldier("outpost_leg_e", 1)
	_assert(stat_res.get("success", false) == true, "TC-E5.1: Station soldier post-legacy-load succeeded")
	var new_soldier: Dictionary = pam.garrisons["outpost_leg_e"]["soldiers"][-1]
	_assert(str(new_soldier.get("soldier_id", "")) == "soldier_gar_276", "TC-E5.2: New soldier ID is soldier_gar_276")
	_assert(pam.next_soldier_id == 277, "TC-E5.3: Counter monotonically advanced to 277")

	var disp_res: Dictionary = pam.dispatch_reinforcements("outpost_leg_e", 1, 3.0)
	_assert(disp_res.get("success", false) == true, "TC-E5.4: Dispatch post-legacy-load succeeded")
	var new_reinf: Dictionary = pam.active_reinforcements[-1]
	_assert(str(new_reinf.get("dispatch_id", "")) == "reinf_91", "TC-E5.5: New dispatch ID is reinf_91")
	_assert(pam.next_reinforce_id == 92, "TC-E5.6: Counter monotonically advanced to 92")

	print("\n========================================================")
	print("  SESSION 1.3 TEST RESULTS")
	print("  TOTAL ASSERTIONS: %d" % (passed_count + failures))
	print("  PASSED:           %d" % passed_count)
	print("  FAILED:           %d" % failures)
	print("========================================================\n")

	if failures == 0:
		print("ALL SESSION 1.3 TESTS PASSED!")
		quit(0)
	else:
		printerr("TESTS FAILED WITH %d ERRORS!" % failures)
		quit(1)
