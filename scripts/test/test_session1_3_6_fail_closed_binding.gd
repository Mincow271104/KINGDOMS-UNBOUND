extends SceneTree

const WorldViewScene = preload("res://scenes/world/world_view.tscn")
const PlayerArmyManagerScript = preload("res://scripts/military/player_army_manager.gd")
const TacticalMilitaryManagerScript = preload("res://scripts/military/tactical_military_manager.gd")
const TacticalUnitScript = preload("res://scripts/military/tactical_unit.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")

var passed_count: int = 0
var failed_count: int = 0

var world_instance: Node = null
var pam: Object = null
var tmm: Object = null

# Mock manager classes for error injection
class MockUnexpectedTypeManager extends RefCounted:
	var player_army_mgr: Object = null
	var return_value: Variant = 42
	func set_player_army_manager(mgr: Object) -> Variant:
		player_army_mgr = mgr
		return null
	func sync_with_player_army() -> Variant:
		return return_value
	func clear_all_units() -> void:
		pass

class MockFailedRegistrationManager extends RefCounted:
	var player_army_mgr: Object = null
	func set_player_army_manager(_mgr: Object) -> Dictionary:
		return {"success": false, "reason": "Registration intentionally rejected"}
	func sync_with_player_army() -> Dictionary:
		return {"success": true, "reason": "Mock sync"}
	func clear_all_units() -> void:
		pass

class MockMissingSyncManager extends RefCounted:
	var player_army_mgr: Object = null
	func set_player_army_manager(mgr: Object) -> Variant:
		player_army_mgr = mgr
		return null
	func clear_all_units() -> void:
		pass

func _init() -> void:
	print("\n========================================================")
	print("  STARTING SESSION 1.3.6 FAIL-CLOSED BINDING SUITE")
	print("========================================================\n")
	call_deferred("_run_all_tests")

func _assert(condition: bool, message: String) -> void:
	if condition:
		passed_count += 1
		print("  [PASS] %s" % message)
	else:
		failed_count += 1
		printerr("  [FAIL] %s" % message)

func _setup_world() -> void:
	var root := get_root()
	if is_instance_valid(world_instance):
		world_instance.queue_free()
		world_instance = null

	world_instance = WorldViewScene.instantiate()
	root.add_child(world_instance)

	pam = world_instance.get("player_army_mgr")
	tmm = world_instance.get("tactical_military_mgr")

	pam.soldier_count = 0
	pam.equipment_tier = 1
	pam.garrisons = {}
	pam.active_reinforcements.clear()
	tmm.clear_all_units()

func _run_all_tests() -> void:
	_test_c1_same_manager_sync_failure()
	_test_c2_unexpected_sync_return_type()
	_test_c3_failed_manager_registration()
	_test_c4_failed_replacement_manager()
	_test_c5_successful_manager_replacement()
	_test_c6_partial_spawn_rollback_completeness()
	_test_c7_no_manager_detach_lifecycle()
	_test_c8_starting_perk_regression()

	print("\n========================================================")
	print("  SESSION 1.3.6 TEST RESULTS SUMMARY")
	print("  Passed Assertions : %d" % passed_count)
	print("  Failed Assertions : %d" % failed_count)
	if failed_count == 0:
		print("  ALL SESSION 1.3.6 ASSERTIONS PASSED! (Exit Code 0)")
		print("========================================================\n")
		quit(0)
	else:
		printerr("  SOME ASSERTIONS FAILED! (Exit Code 1)")
		print("========================================================\n")
		quit(1)

# -----------------------------------------------------------------------------
# C1. Same-manager synchronization failure
# -----------------------------------------------------------------------------
func _test_c1_same_manager_sync_failure() -> void:
	print("--- Running TC-C1: Same-Manager Synchronization Failure ---")
	_setup_world()

	pam.soldier_count = 3
	var sync_ok: Dictionary = pam.set_tactical_military_manager(tmm)
	_assert(sync_ok.get("success", false) == true, "TC-C1.1: Initial binding succeeded with 3 units")
	_assert(tmm.units.size() == 3, "TC-C1.2: Tactical roster has exactly 3 units")
	_assert(pam.movement_state == 0, "TC-C1.3: Army movement_state is GARRISONED (0)")

	# Simulate failure on re-synchronization by setting spawn instantiation failure flag
	tmm._test_simulate_spawn_instantiation_failure = true
	# Also request 1 more soldier so sync_with_player_army must attempt a spawn
	pam.soldier_count = 4

	var sync_fail: Dictionary = pam.set_tactical_military_manager(tmm)
	_assert(sync_fail.get("success", true) == false, "TC-C1.4: Re-binding failed closed when sync failed")
	_assert(pam.soldier_count == 4, "TC-C1.5: Strategic soldier count preserved at 4 (never reduced)")
	_assert(pam.movement_state == 0, "TC-C1.6: Army movement_state preserved as GARRISONED without corruption")
	_assert(tmm.units.size() == 3, "TC-C1.7: Pre-existing 3 tactical units untouched")

	tmm._test_simulate_spawn_instantiation_failure = false

	# Same non-null manager without sync_with_player_army()
	var mock_nosync := MockMissingSyncManager.new()
	var pam_standalone := PlayerArmyManagerScript.new()
	pam_standalone.tactical_military_mgr = mock_nosync
	var res_same_nosync: Dictionary = pam_standalone.set_tactical_military_manager(mock_nosync)
	_assert(res_same_nosync.get("success", true) == false, "TC-C1.8: Same non-null manager without sync_with_player_army rejected fail-closed")
	_assert(res_same_nosync.get("reason", "").contains("missing"), "TC-C1.9: Reason identifies missing sync method")

	# Same non-null manager with unexpected sync return type
	var mock_bad_ret := MockUnexpectedTypeManager.new()
	mock_bad_ret.return_value = 12345
	pam_standalone.tactical_military_mgr = mock_bad_ret
	var res_same_bad: Dictionary = pam_standalone.set_tactical_military_manager(mock_bad_ret)
	_assert(res_same_bad.get("success", true) == false, "TC-C1.10: Same manager with integer return type rejected fail-closed")

# -----------------------------------------------------------------------------
# C2. Unexpected synchronization return type
# -----------------------------------------------------------------------------
func _test_c2_unexpected_sync_return_type() -> void:
	print("\n--- Running TC-C2: Unexpected Synchronization Return Type ---")
	_setup_world()

	var mock := MockUnexpectedTypeManager.new()

	# C2.a: integer return
	mock.return_value = 42
	var res_int: Dictionary = pam.set_tactical_military_manager(mock)
	_assert(res_int.get("success", true) == false, "TC-C2.1: Integer sync return value rejected fail-closed")
	_assert(res_int.get("reason", "").contains("expected Dictionary"), "TC-C2.2: Reason notes unexpected type")

	# C2.b: boolean false return
	mock.return_value = false
	var res_bool: Dictionary = pam.set_tactical_military_manager(mock)
	_assert(res_bool.get("success", true) == false, "TC-C2.3: Boolean false sync return value rejected fail-closed")

	# C2.c: null return
	mock.return_value = null
	var res_null: Dictionary = pam.set_tactical_military_manager(mock)
	_assert(res_null.get("success", true) == false, "TC-C2.4: Null sync return value rejected fail-closed")

	# C2.d: Dictionary missing 'success' key
	mock.return_value = {"units_spawned": 5}
	var res_dict_nosuccess: Dictionary = pam.set_tactical_military_manager(mock)
	_assert(res_dict_nosuccess.get("success", true) == false, "TC-C2.5: Dictionary missing boolean 'success' key rejected fail-closed")

	# C2.e: Dictionary with non-boolean 'success'
	mock.return_value = {"success": "yes"}
	var res_dict_nonbool: Dictionary = pam.set_tactical_military_manager(mock)
	_assert(not (res_dict_nonbool.get("success") is bool and res_dict_nonbool.get("success") == true), "TC-C2.6: Dictionary with string 'success' rejected fail-closed")

	# C2.f: Missing sync method on non-null manager
	var mock_nosync := MockMissingSyncManager.new()
	var res_nosync: Dictionary = pam.set_tactical_military_manager(mock_nosync)
	_assert(res_nosync.get("success", true) == false, "TC-C2.7: Non-null manager missing sync_with_player_army rejected fail-closed")

# -----------------------------------------------------------------------------
# C3. Failed manager registration
# -----------------------------------------------------------------------------
func _test_c3_failed_manager_registration() -> void:
	print("\n--- Running TC-C3: Failed Manager Registration ---")
	_setup_world()

	var mock_reg_fail := MockFailedRegistrationManager.new()
	var res: Dictionary = pam.set_tactical_military_manager(mock_reg_fail)
	_assert(res.get("success", true) == false, "TC-C3.1: Manager registration failure rejected fail-closed")
	_assert(pam.tactical_military_mgr != mock_reg_fail, "TC-C3.2: Failed manager was NOT retained as tactical_military_mgr")
	_assert(res.get("reason", "").contains("rejected"), "TC-C3.3: Rejection reason propagated")

# -----------------------------------------------------------------------------
# C4. Failed replacement manager (preserves old manager state)
# -----------------------------------------------------------------------------
func _test_c4_failed_replacement_manager() -> void:
	print("\n--- Running TC-C4: Failed Replacement Manager Transaction ---")
	_setup_world()

	# Start with healthy tmm with 3 units
	pam.soldier_count = 3
	var bind_ok: Dictionary = pam.set_tactical_military_manager(tmm)
	_assert(bind_ok.get("success", false) == true, "TC-C4.1: Initial manager bound successfully")
	_assert(tmm.units.size() == 3, "TC-C4.2: Initial manager has 3 units")

	var orig_uids: Array = tmm.units.keys()
	orig_uids.sort()
	var orig_instances: Array = []
	for uid in orig_uids:
		orig_instances.append(tmm.units[uid])

	# Create replacement manager that fails sync
	var bad_tmm := TacticalMilitaryManagerScript.new(world_instance)
	bad_tmm.set_tactical_units_container(world_instance.citizens_container)
	bad_tmm._test_simulate_spawn_instantiation_failure = true

	var repl_res: Dictionary = pam.set_tactical_military_manager(bad_tmm)
	_assert(repl_res.get("success", true) == false, "TC-C4.3: Replacement with failing manager returned failure")
	_assert(pam.tactical_military_mgr == tmm, "TC-C4.4: Active manager rolled back to original healthy manager")
	_assert(tmm.units.size() == 3, "TC-C4.5: Original manager's 3 units were NOT destroyed")

	var curr_uids: Array = tmm.units.keys()
	curr_uids.sort()
	_assert(curr_uids == orig_uids, "TC-C4.6: Original unit IDs perfectly preserved")

	var all_instances_match: bool = true
	for i in range(orig_instances.size()):
		if tmm.units[orig_uids[i]] != orig_instances[i]:
			all_instances_match = false
	_assert(all_instances_match, "TC-C4.7: Original unit Node2D instances strictly preserved without reconstruction")
	_assert(pam.soldier_count == 3, "TC-C4.8: Strategic soldier_count conserved at 3")

	# Verify SaveManager can save cleanly post-rollback
	var save_path := "user://test_c4_rollback_save.json"
	var save_dict := SaveManagerScript.serialize_world_state(world_instance)
	var val_res := SaveManagerScript.validate_save_data(save_dict)
	_assert(val_res.get("valid", false), "TC-C4.9: SaveManager validation passed without schema error")
	var save_ok: bool = SaveManagerScript.save_dict_to_file(save_dict, save_path)
	_assert(save_ok, "TC-C4.10: SaveManager saved world cleanly post-rollback without schema/count mismatch")
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)

# -----------------------------------------------------------------------------
# C5. Successful manager replacement
# -----------------------------------------------------------------------------
func _test_c5_successful_manager_replacement() -> void:
	print("\n--- Running TC-C5: Successful Manager Replacement ---")
	_setup_world()

	pam.soldier_count = 3
	pam.set_tactical_military_manager(tmm)
	_assert(tmm.units.size() == 3, "TC-C5.1: Manager 1 has 3 units")

	# Create healthy second manager
	var tmm2 := TacticalMilitaryManagerScript.new(world_instance)
	tmm2.set_tactical_units_container(world_instance.citizens_container)

	var repl_res: Dictionary = pam.set_tactical_military_manager(tmm2)
	_assert(repl_res.get("success", false) == true, "TC-C5.2: Replacement with healthy manager succeeded")
	_assert(pam.tactical_military_mgr == tmm2, "TC-C5.3: Active manager is now tmm2")
	_assert(tmm2.units.size() == 3, "TC-C5.4: Replacement manager has exactly 3 units")
	_assert(tmm.units.size() == 0, "TC-C5.5: Old manager units safely cleared on successful replacement")
	_assert(pam.soldier_count == 3, "TC-C5.6: Strategic soldier_count unchanged at 3")
	_assert(pam.movement_state == 0, "TC-C5.7: Movement state is GARRISONED (0)")

	# Check uniqueness of IDs in tmm2
	var unique_ids: Dictionary = {}
	for uid in tmm2.units.keys():
		unique_ids[uid] = true
	_assert(unique_ids.size() == 3, "TC-C5.8: All 3 unit IDs in new manager are strictly unique")

# -----------------------------------------------------------------------------
# C6. Partial spawn rollback completeness
# -----------------------------------------------------------------------------
func _test_c6_partial_spawn_rollback_completeness() -> void:
	print("\n--- Running TC-C6: Partial Spawn Rollback Completeness ---")
	_setup_world()

	# Start with 2 pre-existing units
	pam.soldier_count = 2
	pam.set_tactical_military_manager(tmm)
	_assert(tmm.units.size() == 2, "TC-C6.1: Initial roster has 2 units")

	var u1_id: String = tmm.units.keys()[0]
	var u2_id: String = tmm.units.keys()[1]
	var u1_instance: Node2D = tmm.units[u1_id]
	var u2_instance: Node2D = tmm.units[u2_id]
	var container: Node = world_instance.citizens_container
	var initial_child_count: int = container.get_child_count()

	# Now set soldier_count to 5 (needed = 3)
	pam.soldier_count = 5
	# Force partial spawn: allow only 1 unit to spawn before failing
	tmm._test_max_successful_spawns = 1

	var sync_res: Dictionary = tmm.sync_with_player_army()
	_assert(sync_res.get("success", true) == false, "TC-C6.2: sync_with_player_army reported failure on partial spawn")
	_assert(sync_res.get("spawned", -1) == 0, "TC-C6.3: Reported spawned count is 0 after rollback")
	_assert(tmm.units.size() == 2, "TC-C6.4: Roster returned to exactly 2 pre-existing units")
	_assert(tmm.units.has(u1_id) and tmm.units[u1_id] == u1_instance, "TC-C6.5: Original unit 1 instance strictly preserved")
	_assert(tmm.units.has(u2_id) and tmm.units[u2_id] == u2_instance, "TC-C6.6: Original unit 2 instance strictly preserved")

	# Scene tree child verification: the 3rd unit must be unparented and not present in container!
	_assert(container.get_child_count() == initial_child_count, "TC-C6.7: Scene container child count restored exactly to pre-attempt count (no orphan nodes)")
	_assert(pam.soldier_count == 5, "TC-C6.8: Strategic soldier_count preserved at 5")

	# Retry after capacity restored
	tmm._test_max_successful_spawns = -1
	var retry_res: Dictionary = tmm.sync_with_player_army()
	_assert(retry_res.get("success", false) == true, "TC-C6.9: Retry after restoring capacity succeeded")
	_assert(tmm.units.size() == 5, "TC-C6.10: Final roster contains exactly 5 units")

	var final_ids: Dictionary = {}
	for uid in tmm.units.keys():
		final_ids[uid] = true
	_assert(final_ids.size() == 5, "TC-C6.11: All 5 final unit IDs are strictly unique")

# -----------------------------------------------------------------------------
# C7. No-manager detach lifecycle
# -----------------------------------------------------------------------------
func _test_c7_no_manager_detach_lifecycle() -> void:
	print("\n--- Running TC-C7: No-Manager Detach Lifecycle ---")
	_setup_world()

	pam.soldier_count = 2
	pam.set_tactical_military_manager(tmm)
	_assert(tmm.units.size() == 2, "TC-C7.1: Pre-detach roster has 2 units")
	_assert(pam.movement_state == 0, "TC-C7.2: Pre-detach movement_state is GARRISONED")

	# Detach manager intentionally
	var detach_res: Dictionary = pam.set_tactical_military_manager(null)
	_assert(detach_res.get("success", false) == true, "TC-C7.3: Intentional detach returned success")
	_assert(pam.tactical_military_mgr == null, "TC-C7.4: tactical_military_mgr is strictly null")
	_assert(tmm.units.size() == 0, "TC-C7.5: Detached manager units safely cleared")
	_assert(pam.soldier_count == 2, "TC-C7.6: Strategic soldier_count conserved at 2 on detach")
	_assert(pam.movement_state == PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD, "TC-C7.7: Non-empty detached army transitioned to IDLE_AT_FIELD (2)")

	# Re-attaching manager restores tactical units and GARRISONED state
	var reattach_res: Dictionary = pam.set_tactical_military_manager(tmm)
	_assert(reattach_res.get("success", false) == true, "TC-C7.8: Re-attaching manager succeeded")
	_assert(tmm.units.size() == 2, "TC-C7.9: Re-attached manager spawned 2 tactical units")
	_assert(pam.movement_state == 0, "TC-C7.10: Re-attached army restored to GARRISONED")

	# Both current and requested managers are null: intentional no-op
	pam.set_tactical_military_manager(null)
	_assert(pam.tactical_military_mgr == null, "TC-C7.11: Pre-condition: manager is currently null")
	var initial_movement_state = pam.movement_state
	var both_null_res: Dictionary = pam.set_tactical_military_manager(null)
	_assert(both_null_res.get("success", false) == true, "TC-C7.12: Both current and requested managers null returns success")
	_assert(both_null_res.get("reason", "") == "No tactical manager attached", "TC-C7.13: Correct intentional no-manager reason")
	_assert(pam.tactical_military_mgr == null, "TC-C7.14: Manager remains null without crash")
	_assert(pam.movement_state == initial_movement_state, "TC-C7.15: Movement state strictly untouched by both-null no-op")

# -----------------------------------------------------------------------------
# C8. Starting perk regression (hardened_outposts)
# -----------------------------------------------------------------------------
func _test_c8_starting_perk_regression() -> void:
	print("\n--- Running TC-C8: Starting Perk Regression (hardened_outposts) ---")
	var root := get_root()
	if is_instance_valid(world_instance):
		world_instance.queue_free()
		world_instance = null

	var wv: Node = WorldViewScene.instantiate()
	wv.active_perks = ["hardened_outposts"]
	wv.world_seed = 8888
	root.add_child(wv)

	var wv_pam = wv.get("player_army_mgr")
	var wv_tmm = wv.get("tactical_military_mgr")

	_assert(wv_pam.soldier_count == 2, "TC-C8.1: hardened_outposts genesis soldier_count is strictly 2")
	_assert(wv_tmm.units.size() == 2, "TC-C8.2: hardened_outposts tactical roster is strictly 2")
	_assert(wv_pam.movement_state == 0, "TC-C8.3: hardened_outposts army is GARRISONED (0)")

	var uids: Array = wv_tmm.units.keys()
	_assert(uids.size() == 2 and uids[0] != uids[1], "TC-C8.4: Both tactical unit IDs are strictly unique")

	# Save/load roundtrip
	var save_path := "user://test_c8_genesis_roundtrip.json"
	var save_dict := SaveManagerScript.serialize_world_state(wv)
	var val_res := SaveManagerScript.validate_save_data(save_dict)
	_assert(val_res.get("valid", false), "TC-C8.5: SaveManager validated hardened_outposts save without schema error")

	var save_ok: bool = SaveManagerScript.save_dict_to_file(save_dict, save_path)
	_assert(save_ok, "TC-C8.6: SaveManager saved hardened_outposts genesis world successfully")

	var load_res: Dictionary = SaveManagerScript.load_from_file(save_path)
	_assert(load_res.get("success", false) == true, "TC-C8.7: Save file loaded successfully")

	var apply_res: Dictionary = SaveManagerScript.apply_loaded_state_to_world(wv, load_res.get("data", {}))
	_assert(apply_res.get("success", false) == true, "TC-C8.8: apply_loaded_state_to_world succeeded")
	_assert(wv_pam.soldier_count == 2, "TC-C8.9: Post-load soldier_count conserved at 2")
	_assert(wv_tmm.units.size() == 2, "TC-C8.10: Post-load tactical units conserved at 2")
	_assert(wv_pam.movement_state == 0, "TC-C8.11: Post-load movement_state remains GARRISONED (0)")

	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	wv.queue_free()
