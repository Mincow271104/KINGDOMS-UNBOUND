extends SceneTree
## Test Suite: Session 1.2 Final Military Transaction Audit & Ledger Restoration
## Validates:
## A. Ownership transfer atomicity (combined count preflight vs partial congestion)
## B. Objective destruction call ordering, single refund, no ghost records
## C. Destroyed building blocked eviction, absent production retry, and ghost record lifecycle
## D. Legacy and current save schema compatibility with monotonic ID generators

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
	print("  STARTING SESSION 1.2 FINAL MILITARY AUDIT TEST SUITE")
	print("========================================================\n")
	world_instance = WorldViewScene.instantiate()
	world_instance.world_seed = 5050
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count >= 3 and not tests_executed:
		tests_executed = true
		_run_all_tests()
	return false

class MockCapacityTMM extends RefCounted:
	var units: Dictionary = {}
	var max_allowed_spawns: int = 999
	var real_tmm: Object = null

	func _init(p_real_tmm: Object, p_max: int = 999) -> void:
		real_tmm = p_real_tmm
		max_allowed_spawns = p_max
		if real_tmm != null and "units" in real_tmm:
			units = real_tmm.units

	func can_allocate_spawns(count: int, rally_cell: Vector2i = Vector2i(-1, -1)) -> bool:
		if count > max_allowed_spawns:
			return false
		if real_tmm != null and real_tmm.has_method("can_allocate_spawns"):
			return bool(real_tmm.call("can_allocate_spawns", count, rally_cell))
		return true

	func sync_with_player_army() -> void:
		if real_tmm != null and real_tmm.has_method("sync_with_player_army"):
			real_tmm.sync_with_player_army()

	func get_all_units() -> Array:
		if real_tmm != null and real_tmm.has_method("get_all_units"):
			return real_tmm.call("get_all_units")
		return []

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

	print("\n--- GROUP A: OWNERSHIP TRANSFER ATOMICITY ---")
	# Clean slate
	pam.soldier_count = 10
	tmm.sync_with_player_army()
	pam.garrisons.clear()
	pam.active_reinforcements.clear()

	var test_outpost_a: String = "test_outpost_transfer_a"
	pam.register_outpost_for_testing(test_outpost_a, 6, Vector2i(20, 20), "player")
	pam.station_soldier(test_outpost_a, 3)
	pam.dispatch_reinforcements(test_outpost_a, 2, 5.0)

	var inv_a_pre: Dictionary = _calc_invariants(pam, tmm)
	_assert(inv_a_pre.reserve == 5, "TC-1.2.01a: Reserve is 5 (10 - 3 - 2)")
	_assert(inv_a_pre.garrisoned == 3, "TC-1.2.01b: Stationed garrison is 3")
	_assert(inv_a_pre.in_transit == 2, "TC-1.2.01c: In-transit is 2")
	_assert(inv_a_pre.total_headcount == 10, "TC-1.2.01d: Invariant A holds (10 total)")
	_assert(inv_a_pre.invariant_b_holds, "TC-1.2.01e: Invariant B holds (5 tactical units == 5 reserve)")

	# Case 1: Partial congestion (can allocate 3 garrison, but NOT 5 combined)
	var mock_partial := MockCapacityTMM.new(tmm, 3)
	pam.set_tactical_military_manager(mock_partial)

	var fail_res: Dictionary = pam.evict_and_cancel_outpost(test_outpost_a, true)
	_assert(fail_res.get("success", true) == false, "TC-1.2.02a: evict_and_cancel_outpost fails closed on partial congestion")
	_assert(pam.get_garrison_count(test_outpost_a) == 3, "TC-1.2.02b: Garrison is UNTOUCHED (3 retained)")
	_assert(pam.get_in_transit_count(test_outpost_a) == 2, "TC-1.2.02c: Transit is UNTOUCHED (2 retained)")
	_assert(pam.soldier_count == 5, "TC-1.2.02d: Central reserve UNTOUCHED (5)")
	_assert(pam.get_total_soldier_count() == 10, "TC-1.2.02e: Total headcount UNTOUCHED (10)")

	# Case 2: Full capacity available (can allocate all 5)
	pam.set_tactical_military_manager(tmm)
	var ok_res: Dictionary = pam.evict_and_cancel_outpost(test_outpost_a, true)
	_assert(ok_res.get("success", false) == true, "TC-1.2.03a: evict_and_cancel_outpost succeeds when cells available")
	_assert(ok_res.get("evicted_count", 0) == 3, "TC-1.2.03b: Exactly 3 garrison soldiers evicted")
	_assert(ok_res.get("cancelled_count", 0) == 2, "TC-1.2.03c: Exactly 2 transit soldiers cancelled")
	_assert(ok_res.get("total_refunded", 0) == 5, "TC-1.2.03d: Exactly 5 total refunded")
	_assert(pam.soldier_count == 10, "TC-1.2.03e: Central reserve restored to 10")
	_assert(pam.get_garrison_count(test_outpost_a) == 0, "TC-1.2.03f: Garrison cleanly zeroed")
	_assert(pam.get_in_transit_count(test_outpost_a) == 0, "TC-1.2.03g: Transit cleanly zeroed")

	var inv_a_post: Dictionary = _calc_invariants(pam, tmm)
	_assert(inv_a_post.total_headcount == 10, "TC-1.2.03h: Total headcount preserved at 10")
	_assert(inv_a_post.tactical_units == 10, "TC-1.2.03i: Tactical units synced to 10")
	_assert(inv_a_post.invariant_b_holds, "TC-1.2.03j: Invariant B holds at 10 == 10")

	print("\n--- GROUP B: OBJECTIVE DESTRUCTION CALL PATH & IDEMPOTENCY ---")
	var test_obj_id: String = "siege_destruct_audit_01"
	var reg_obj = fsm.register_objective(test_obj_id, Vector2i(25, 25), "player", 100.0, 3)
	_assert(reg_obj != null, "TC-1.2.04a: Objective registered successfully")

	pam.soldier_count = 10
	tmm.sync_with_player_army()
	pam.station_soldier(test_obj_id, 2)
	pam.dispatch_reinforcements(test_obj_id, 1, 4.0)

	var obj_actor = fsm.get_objective(test_obj_id)
	_assert(obj_actor != null, "TC-1.2.04b: Objective actor exists")

	# Destroy objective via simulated combat damage while active
	obj_actor.is_under_active_siege = true
	obj_actor.take_damage(100.0, "attacker_rival")
	_assert(not obj_actor.is_alive, "TC-1.2.04c: Objective is marked dead")

	# Verify signal propagated to WorldView and called evict_and_cancel_outpost
	_assert(pam.get_garrison_count(test_obj_id) == 0, "TC-1.2.04d: Garrison evicted on destruction")
	_assert(pam.get_in_transit_count(test_obj_id) == 0, "TC-1.2.04e: Transit cancelled on destruction")
	_assert(pam.soldier_count == 10, "TC-1.2.04f: Central reserve refunded exactly once to 10")

	var inv_b: Dictionary = _calc_invariants(pam, tmm)
	_assert(inv_b.total_headcount == 10, "TC-1.2.04g: Total headcount is 10")
	_assert(inv_b.invariant_b_holds, "TC-1.2.04h: Invariant B holds (10 == 10)")

	print("\n--- GROUP C: DESTROYED BUILDING RETRY & BLOCKED LIFECYCLE AUDIT (POLICY B) ---")
	# Force preflight failure on destruction (0 spawn capacity)
	var blocked_obj_id: String = "siege_destruct_blocked_02"
	fsm.register_objective(blocked_obj_id, Vector2i(28, 28), "player", 100.0, 4)
	pam.station_soldier(blocked_obj_id, 3)

	var mock_block := MockCapacityTMM.new(tmm, 0) # 0 spawns available
	pam.set_tactical_military_manager(mock_block)

	var blocked_actor = fsm.get_objective(blocked_obj_id)
	blocked_actor.is_under_active_siege = true
	blocked_actor.take_damage(100.0, "attacker_rival")

	# Under Policy B (Session 1.3+): On destruction with 0 spawn capacity,
	# soldiers cannot remain trapped in deleted building. All 3 become casualties, garrison cleared.
	_assert(pam.get_garrison_count(blocked_obj_id) == 0, "TC-1.2.05a: Garrison cleanly cleared (0 trapped in destroyed building)")
	_assert(pam.soldier_count == 7, "TC-1.2.05b: Reserve remains 7 (0 refunded due to 0 spawn capacity)")
	_assert(pam.get_total_soldier_count() == 7, "TC-1.2.05c: Living headcount is 7 (3 casualties cleanly accounted)")

	# Restore valid cells
	pam.set_tactical_military_manager(tmm)

	# Verify zero ghost records or phantom resurrection
	_assert(pam.get_garrison_count(blocked_obj_id) == 0, "TC-1.2.05d: Without retry trigger, garrison remains 0 (zero ghost records)")

	# Save/load during the post-destruction state
	var test_slot: String = "user://test_blocked_destruction_audit.json"
	var save_res: Dictionary = SaveManagerScript.save_to_file(world_instance, test_slot)
	_assert(save_res.get("success", false) == true, "TC-1.2.06a: Save succeeds with clean post-destruction state")

	var load_res: Dictionary = SaveManagerScript.load_from_file(test_slot)
	_assert(load_res.get("success", false) == true, "TC-1.2.06b: Load succeeds with clean post-destruction state")
	var apply_res: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, load_res.get("data", {}))
	_assert(apply_res.get("success", false) == true, "TC-1.2.06c: Apply loaded state succeeds")

	_assert(pam.get_garrison_count(blocked_obj_id) == 0, "TC-1.2.06d: Restored garrison is 0 (zero ghost records restored)")
	_assert(pam.soldier_count == 7, "TC-1.2.06e: Restored reserve is 7")
	_assert(pam.get_total_soldier_count() == 7, "TC-1.2.06f: Restored living headcount is 7")

	# Idempotent cleanup call returns success cleanly with 0 evacuated
	var manual_rec: Dictionary = pam.evict_and_cancel_outpost(blocked_obj_id, true)
	_assert(manual_rec.get("success", false) == true, "TC-1.2.06g: Idempotent eviction succeeds cleanly")
	_assert(pam.soldier_count == 7, "TC-1.2.06h: Reserve remains stable at 7 (no phantom increment)")

	print("\n--- GROUP D: SAVE/LOAD COMPATIBILITY & ID MONOTONICITY ---")
	pam.register_outpost_for_testing("outpost_leg_1", 10, Vector2i(15, 15), "player")
	pam.next_soldier_id = 1
	pam.next_reinforce_id = 1

	# 1. Legacy save without ID counters
	var legacy_dict: Dictionary = {
		"soldier_count": 5,
		"equipment_tier": 1,
		"garrisons": {
			"outpost_leg_1": {
				"capacity": 10,
				"soldiers": [
					{"soldier_id": "soldier_gar_105", "equipment_tier": 1, "health": 100.0},
					{"soldier_id": "soldier_gar_110", "equipment_tier": 1, "health": 100.0}
				]
			}
		},
		"reinforcements": [
			{
				"dispatch_id": "reinf_45",
				"outpost_id": "outpost_leg_1",
				"soldier_count": 1,
				"soldiers": [{"soldier_id": "soldier_reinf_115", "equipment_tier": 1, "health": 100.0}]
			}
		]
		# Notice: NO next_soldier_id or next_reinforce_id
	}

	pam.deserialize_garrisons(legacy_dict)
	_assert(pam.next_soldier_id == 116, "TC-1.2.07a: next_soldier_id derived from max(115) + 1 = 116")
	_assert(pam.next_reinforce_id == 46, "TC-1.2.07b: next_reinforce_id derived from max(45) + 1 = 46")

	# Station new soldier after legacy load
	var st_res: Dictionary = pam.station_soldier("outpost_leg_1", 1)
	_assert(st_res.get("success", false) == true, "TC-1.2.07c: Station soldier succeeds after legacy load")
	var new_s: Dictionary = pam.garrisons["outpost_leg_1"]["soldiers"][-1]
	_assert(str(new_s.get("soldier_id", "")) == "soldier_gar_116", "TC-1.2.07d: Newly stationed soldier gets non-colliding ID soldier_gar_116")
	_assert(pam.next_soldier_id == 117, "TC-1.2.07e: next_soldier_id monotonically advanced to 117")

	# Dispatch new reinforcement after legacy load
	var disp_res: Dictionary = pam.dispatch_reinforcements("outpost_leg_1", 1, 3.0)
	_assert(disp_res.get("success", false) == true, "TC-1.2.07f: Dispatch succeeds after legacy load")
	var new_r: Dictionary = pam.active_reinforcements[-1]
	_assert(str(new_r.get("dispatch_id", "")) == "reinf_46", "TC-1.2.07g: Newly dispatched reinforcement gets ID reinf_46")
	_assert(pam.next_reinforce_id == 47, "TC-1.2.07h: next_reinforce_id monotonically advanced to 47")

	# 2. Modern save roundtrip with explicit counters
	var modern_saved: Dictionary = pam.serialize_garrisons()
	_assert(modern_saved.get("next_soldier_id") == 118, "TC-1.2.08a: Serialized next_soldier_id is 118")
	_assert(modern_saved.get("next_reinforce_id") == 47, "TC-1.2.08b: Serialized next_reinforce_id is 47")

	pam.next_soldier_id = 1
	pam.next_reinforce_id = 1
	pam.deserialize_garrisons(modern_saved)
	_assert(pam.next_soldier_id == 118, "TC-1.2.08c: Restored next_soldier_id preserves exact counter 118")
	_assert(pam.next_reinforce_id == 47, "TC-1.2.08d: Restored next_reinforce_id preserves exact counter 47")

	print("\n========================================================")
	print("  SESSION 1.2 TEST RESULTS")
	print("  TOTAL ASSERTIONS: %d" % (passed_count + failures))
	print("  PASSED:           %d" % passed_count)
	print("  FAILED:           %d" % failures)
	print("========================================================\n")

	if failures == 0:
		print("ALL SESSION 1.2 TESTS PASSED!")
		quit(0)
	else:
		printerr("TESTS FAILED WITH %d ERRORS!" % failures)
		quit(1)
