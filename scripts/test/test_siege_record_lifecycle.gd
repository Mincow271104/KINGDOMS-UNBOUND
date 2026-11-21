extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — RISK-002: Field Siege Lifecycle & Bounded Records
## Verifies separation of active vs resolved sieges, history bounding, idempotency, and migration.

const SiegeObjectiveActorScript = preload("res://scripts/combat/siege_objective_actor.gd")
const FieldSiegeManagerScript = preload("res://scripts/combat/field_siege_manager.gd")
const PlayerArmyManagerScript = preload("res://scripts/military/player_army_manager.gd")
const EnemyMilitaryManagerScript = preload("res://scripts/military/enemy_military_manager.gd")
const TacticalMilitaryManagerScript = preload("res://scripts/military/tactical_military_manager.gd")

var failures: int = 0
var passed_count: int = 0

class MockResourceManager:
	var resources: Dictionary = {"gold": 100, "food": 100, "wood": 100, "metal": 100}
	func add_resource(res_type: String, amount: int) -> int:
		resources[res_type] = resources.get(res_type, 0) + amount
		return amount
	func get_resource(res_type: String) -> int:
		return resources.get(res_type, 0)

class MockFactionData:
	var id: String = "enemy_faction"
	var name: String = "Enemy"
	var existence_status: String = "active"
	var is_at_war: bool = true
	var military_power: float = 60.0

class MockFactionManager:
	var _factions: Dictionary = {}
	func add_faction(fac: MockFactionData) -> void:
		_factions[fac.id] = fac
	func get_faction(f_id: String) -> MockFactionData:
		return _factions.get(f_id, null)
	func are_factions_at_war(f_id: String, _other: String) -> bool:
		var f = _factions.get(f_id, null)
		return f.is_at_war if f != null else false

func _assert(condition: bool, test_name: String, details: String = "") -> void:
	if condition:
		passed_count += 1
		print("  [PASS] %s" % test_name)
	else:
		failures += 1
		printerr("  [FAIL] %s - %s" % [test_name, details])

func _init() -> void:
	print("\n========================================================")
	print("  STARTING RISK-002 SIEGE RECORD LIFECYCLE TEST SUITE")
	print("========================================================\n")

	_run_all_scenarios()

	print("\n--------------------------------------------------------")
	if failures == 0:
		print("  RISK-002 SUITE: ALL %d SCENARIO CHECKS PASSED! (0 Failures)" % passed_count)
		print("========================================================\n")
		quit(0)
	else:
		printerr("  RISK-002 SUITE: FAILED WITH %d FAILURES (Passed: %d)" % [failures, passed_count])
		print("========================================================\n")
		quit(1)

func _setup_siege_environment():
	var fm = MockFactionManager.new()
	var fac = MockFactionData.new()
	fm.add_faction(fac)
	var rm = MockResourceManager.new()
	var army_mgr = PlayerArmyManagerScript.new()
	var tac_mgr = TacticalMilitaryManagerScript.new(null, army_mgr)
	army_mgr.set_tactical_military_manager(tac_mgr)
	army_mgr.soldier_count = 5
	tac_mgr.sync_with_player_army()
	for u in tac_mgr.get_all_units():
		u.current_cell = Vector2i(10, 10)
	army_mgr.current_cell = Vector2i(10, 10)
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD

	var enemy_mgr = EnemyMilitaryManagerScript.new()
	var siege_mgr = FieldSiegeManagerScript.new(null, fm, army_mgr, enemy_mgr)
	siege_mgr.set_resource_manager(rm)
	return {
		"fm": fm,
		"rm": rm,
		"army_mgr": army_mgr,
		"enemy_mgr": enemy_mgr,
		"siege_mgr": siege_mgr
	}

func _run_all_scenarios() -> void:
	var env = _setup_siege_environment()
	var sm = env["siege_mgr"]

	# -------------------------------------------------------------------------
	# Scenario 1: Active siege remains registered in active_sieges
	# -------------------------------------------------------------------------
	print("--- Scenario 1: Active Siege Registration ---")
	var obj1 = sm.register_objective("outpost_1", Vector2i(12, 12), "enemy_faction", 200.0, 2)
	var launch_res = sm.launch_field_siege("enemy_faction", "outpost_1")
	_assert(launch_res.get("success", false) == true, "S1.1: Siege launched successfully")
	var s_id: String = launch_res.get("siege_id", "")
	_assert(s_id != "", "S1.2: Valid siege_id generated")
	_assert(sm.active_sieges.has(s_id), "S1.3: Active siege is present in active_sieges")
	_assert(sm.active_sieges[s_id].get("status") == "active", "S1.4: Status is strictly 'active'")
	_assert(sm.get_active_siege_count() == 1, "S1.5: active_siege_count is 1")
	_assert(sm.get_resolved_siege_count() == 0, "S1.6: resolved_siege_count is 0")

	# -------------------------------------------------------------------------
	# Scenario 2: Successful resolution (VICTORY) removes from active_sieges
	# -------------------------------------------------------------------------
	print("--- Scenario 2: VICTORY Resolution & Active Cleanliness ---")
	var vic_res = sm._resolve_siege_outcome(s_id, "VICTORY")
	_assert(vic_res.get("status") == "resolved", "S2.1: Outcome resolved successfully")
	_assert(vic_res.get("outcome") == "VICTORY", "S2.2: Outcome is VICTORY")
	_assert(not sm.active_sieges.has(s_id), "S2.3: Resolved siege erased from active_sieges")
	_assert(sm.get_active_siege_count() == 0, "S2.4: active_siege_count dropped to 0")
	_assert(sm.get_resolved_siege_count() == 1, "S2.5: resolved_siege_count increased to 1")
	var hist_rec = sm.get_resolved_siege_record(s_id)
	_assert(hist_rec.get("status") == "resolved", "S2.6: History record status is resolved")
	_assert(hist_rec.get("outcome") == "VICTORY", "S2.7: History record outcome is VICTORY")

	# -------------------------------------------------------------------------
	# Scenario 3: Withdrawal resolution removes from active_sieges
	# -------------------------------------------------------------------------
	print("--- Scenario 3: WITHDRAWAL Resolution ---")
	var obj2 = sm.register_objective("outpost_2", Vector2i(15, 15), "enemy_faction", 200.0, 2)
	var launch_res2 = sm.launch_field_siege("enemy_faction", "outpost_2")
	var s_id2: String = launch_res2.get("siege_id", "")
	_assert(sm.get_active_siege_count() == 1, "S3.1: Second siege active")

	sm.cancel_active_sieges_for_faction("enemy_faction", "WITHDRAWAL")
	_assert(sm.get_active_siege_count() == 0, "S3.2: Cancelled siege erased from active_sieges")
	_assert(sm.get_resolved_siege_count() == 2, "S3.3: Total resolved count is 2")
	var hist_rec2 = sm.get_resolved_siege_record(s_id2)
	_assert(hist_rec2.get("outcome") == "WITHDRAWAL", "S3.4: Withdrawn siege recorded with WITHDRAWAL outcome")

	# -------------------------------------------------------------------------
	# Scenario 4: Resolution on already-resolved siege is idempotent
	# -------------------------------------------------------------------------
	print("--- Scenario 4: Idempotency of Resolved Records ---")
	var gold_before = env["rm"].get_resource("gold")
	var count_before = sm.get_resolved_siege_count()
	var idem_res = sm._resolve_siege_outcome(s_id, "VICTORY")
	_assert(idem_res.get("status") == "resolved", "S4.1: Idempotent call returns resolved status")
	_assert(idem_res.get("outcome") == "VICTORY", "S4.2: Idempotent call returns VICTORY outcome")
	_assert(sm.get_resolved_siege_count() == count_before, "S4.3: History size unchanged on duplicate resolve")
	_assert(env["rm"].get_resource("gold") == gold_before, "S4.4: Plunder resources not awarded twice")

	var eval_idem = sm.evaluate_siege_status(s_id)
	_assert(eval_idem.get("status") == "resolved", "S4.5: evaluate_siege_status on resolved siege returns resolved")
	_assert(eval_idem.get("outcome") == "VICTORY", "S4.6: evaluate_siege_status returns original outcome")

	# -------------------------------------------------------------------------
	# Scenario 5: Recent history retains resolved information
	# -------------------------------------------------------------------------
	print("--- Scenario 5: Recent History Integrity ---")
	var recent = sm.get_recent_resolved_sieges()
	_assert(recent.size() == 2, "S5.1: get_recent_resolved_sieges returns 2 records")
	_assert(recent[0].get("siege_id") == s_id, "S5.2: First resolved record matches s_id")
	_assert(recent[1].get("siege_id") == s_id2, "S5.3: Second resolved record matches s_id2")
	# Immutability of returned copy
	recent.clear()
	_assert(sm.get_resolved_siege_count() == 2, "S5.4: Modifying caller copy does not affect internal history")

	# -------------------------------------------------------------------------
	# Scenario 6: Strictly bounded at MAX_RESOLVED_HISTORY (50) under stress
	# -------------------------------------------------------------------------
	print("--- Scenario 6: Bounded History Under Stress ---")
	for i in range(100):
		var dummy_record = {
			"siege_id": "dummy_siege_%d" % i,
			"faction_id": "enemy_faction",
			"objective_id": "outpost_1",
			"status": "resolved",
			"outcome": "VICTORY",
			"details": {}
		}
		sm._push_resolved_history(dummy_record)

	_assert(sm.get_resolved_siege_count() == 50, "S6.1: History size capped strictly at 50")
	var capped_recent = sm.get_recent_resolved_sieges()
	_assert(capped_recent.size() == 50, "S6.2: get_recent_resolved_sieges size is 50")
	_assert(capped_recent[0].get("siege_id") == "dummy_siege_50", "S6.3: Oldest records pruned FIFO (starts at 50)")
	_assert(capped_recent[49].get("siege_id") == "dummy_siege_99", "S6.4: Latest record preserved at end (dummy_siege_99)")

	# -------------------------------------------------------------------------
	# Scenario 7: Save/load does not resurrect resolved sieges into active_sieges
	# -------------------------------------------------------------------------
	print("--- Scenario 7: Save/Load Roundtrip Without Resurrection ---")
	var serialized = sm.serialize()
	_assert(serialized.has("active_sieges"), "S7.1: Serialized data contains active_sieges")
	_assert(serialized.get("active_sieges").is_empty(), "S7.2: Serialized active_sieges is empty")
	_assert(serialized.has("resolved_sieges_history"), "S7.3: Serialized data contains resolved_sieges_history")
	_assert(serialized.get("resolved_sieges_history").size() == 50, "S7.4: Serialized history has 50 records")

	var sm_loaded = FieldSiegeManagerScript.new()
	var des_ok = sm_loaded.deserialize(serialized)
	_assert(des_ok == true, "S7.5: deserialize succeeded")
	_assert(sm_loaded.get_active_siege_count() == 0, "S7.6: active_sieges remains strictly empty after load")
	_assert(sm_loaded.get_resolved_siege_count() == 50, "S7.7: resolved_sieges_history faithfully restored (50)")

	# -------------------------------------------------------------------------
	# Scenario 8: Legacy save with resolved records in active_sieges normalizes
	# -------------------------------------------------------------------------
	print("--- Scenario 8: Legacy Save Migration & Normalization ---")
	var legacy_data = {
		"objectives": serialized.get("objectives", []),
		"active_sieges": {
			"legacy_resolved_1": {
				"siege_id": "legacy_resolved_1",
				"faction_id": "enemy_faction",
				"objective_id": "outpost_1",
				"status": "resolved",
				"outcome": "VICTORY"
			},
			"legacy_cancelled_2": {
				"siege_id": "legacy_cancelled_2",
				"faction_id": "enemy_faction",
				"objective_id": "outpost_1",
				"status": "cancelled",
				"outcome": "WITHDRAWAL"
			},
			"legacy_active_3": {
				"siege_id": "legacy_active_3",
				"faction_id": "enemy_faction",
				"objective_id": "outpost_1",
				"status": "active",
				"outcome": "NONE"
			}
		},
		"next_siege_index": 4
	}

	var sm_migrated = FieldSiegeManagerScript.new()
	var mig_ok = sm_migrated.deserialize(legacy_data)
	_assert(mig_ok == true, "S8.1: Legacy save deserialized successfully")
	_assert(sm_migrated.get_active_siege_count() == 1, "S8.2: Exactly 1 truly active siege retained in active_sieges")
	_assert(sm_migrated.active_sieges.has("legacy_active_3"), "S8.3: legacy_active_3 is the sole active siege")
	_assert(not sm_migrated.active_sieges.has("legacy_resolved_1"), "S8.4: legacy_resolved_1 migrated out of active_sieges")
	_assert(not sm_migrated.active_sieges.has("legacy_cancelled_2"), "S8.5: legacy_cancelled_2 migrated out of active_sieges")
	_assert(sm_migrated.get_resolved_siege_count() == 2, "S8.6: Both resolved/cancelled records migrated into history")

	# -------------------------------------------------------------------------
	# Scenario 9: Active siege survives save/load in active_sieges
	# -------------------------------------------------------------------------
	print("--- Scenario 9: Active Siege Persistence ---")
	var roundtrip_data = sm_migrated.serialize()
	var sm_reloaded = FieldSiegeManagerScript.new()
	var rt_ok = sm_reloaded.deserialize(roundtrip_data)
	_assert(rt_ok == true, "S9.1: Reload succeeded")
	_assert(sm_reloaded.get_active_siege_count() == 1, "S9.2: Active siege count preserved as 1")
	_assert(sm_reloaded.active_sieges.has("legacy_active_3"), "S9.3: Active siege ID preserved")
	_assert(sm_reloaded.active_sieges["legacy_active_3"].get("status") == "active", "S9.4: Status is active")

	# -------------------------------------------------------------------------
	# Scenario 10: WorldView processing efficiency
	# -------------------------------------------------------------------------
	print("--- Scenario 10: WorldView Processing Efficiency ---")
	sm_reloaded._resolve_siege_outcome("legacy_active_3", "VICTORY")
	_assert(sm_reloaded.get_active_siege_count() == 0, "S10.1: All sieges now resolved")

	# In WorldView._process:
	var keys = sm_reloaded.active_sieges.keys()
	_assert(keys.is_empty(), "S10.2: active_sieges.keys() is empty")
	var eval_iterations: int = 0
	for k in keys:
		eval_iterations += 1
		sm_reloaded.evaluate_siege_status(k)
	_assert(eval_iterations == 0, "S10.3: Zero evaluate_siege_status iterations performed in frame loop")

	sm.clear_all_objectives()
	sm_loaded.clear_all_objectives()
	sm_migrated.clear_all_objectives()
	sm_reloaded.clear_all_objectives()
