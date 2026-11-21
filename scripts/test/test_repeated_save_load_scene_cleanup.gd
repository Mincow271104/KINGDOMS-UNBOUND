extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — RISK-005: Save/Load Scene-Tree Cleanup
## Verifies clean reconstruction of citizens and buildings during repeated world loads.

const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const CitizenControllerScript = preload("res://scripts/entities/citizen_controller.gd")

const TEST_MANUAL_PATH: String = "user://test_cleanup_manual.json"
const TEST_AUTOSAVE_PATH: String = "user://test_cleanup_autosave.json"

var frame_count: int = 0
var world_instance: Node = null
var failures: int = 0
var passed_count: int = 0

func _assert(condition: bool, test_name: String, details: String = "") -> void:
	if condition:
		passed_count += 1
		print("  [PASS] %s" % test_name)
	else:
		failures += 1
		printerr("  [FAIL] %s - %s" % [test_name, details])

func _init() -> void:
	print("\n========================================================")
	print("  STARTING RISK-005 SAVE/LOAD SCENE CLEANUP SUITE")
	print("========================================================\n")
	SaveManagerScript.set_test_default_save_path(TEST_MANUAL_PATH)
	SaveManagerScript.set_test_autosave_path(TEST_AUTOSAVE_PATH)
	_cleanup_test_files()
	world_instance = WorldViewScene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count == 3:
		_run_all_tests()
	return false

func _cleanup_test_files() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		var targets := [
			TEST_MANUAL_PATH,
			TEST_MANUAL_PATH + ".bak",
			TEST_MANUAL_PATH + ".tmp",
			TEST_AUTOSAVE_PATH,
			TEST_AUTOSAVE_PATH + ".bak",
			TEST_AUTOSAVE_PATH + ".tmp"
		]
		for t in targets:
			if FileAccess.file_exists(t):
				dir.remove(t)

func _run_all_tests() -> void:
	# Save current baseline world
	var save_res = SaveManagerScript.save_to_file(world_instance, TEST_MANUAL_PATH)
	_assert(save_res.get("success", false) == true, "Setup: Initial world saved successfully")

	var entities_container = world_instance.get("citizens_container")
	_assert(entities_container != null, "Setup: citizens_container found")

	# Scenario 1: Initial world citizen names match their citizen_id exactly
	print("--- Scenario 1: Initial Citizen Node Names ---")
	var initial_cit_nodes = []
	for child in entities_container.get_children():
		if child is CitizenControllerScript:
			initial_cit_nodes.append(child)
			_assert(child.name == child.citizen_id, "S1: Initial citizen node name matches citizen_id (%s)" % child.name)

	# Scenario 2: Immediate repeated world load without frame delay
	print("--- Scenario 2: Immediate Repeated World Load ---")
	var load_dict = SaveManagerScript.load_from_file(TEST_MANUAL_PATH)
	_assert(load_dict.get("success", false) == true, "S2.0: load_from_file succeeded")
	var load_res = SaveManagerScript.apply_loaded_state_to_world(world_instance, load_dict["data"])
	if not load_res.get("success", false):
		print("    load_res failure reason: %s" % str(load_res))
	_assert(load_res.get("success", false) == true, "S2.1: Immediate load succeeded")

	var reloaded_cits = []
	var name_collisions = 0
	for child in entities_container.get_children():
		if child is CitizenControllerScript:
			reloaded_cits.append(child)
			if child.name != child.citizen_id:
				name_collisions += 1
				print("    Detected node name collision: name='%s', expected citizen_id='%s'" % [child.name, child.citizen_id])

	_assert(name_collisions == 0, "S2.2: Zero node name collisions after immediate reload", "Collisions found: %d" % name_collisions)

	# Scenario 3: Verify node count in YSortEntities matches active citizens
	print("--- Scenario 3: YSortEntities Node Count Integrity ---")
	var active_cits_count = world_instance.citizens_by_id.size()
	# Account for ArmyMarker if present
	var non_army_children = 0
	for child in entities_container.get_children():
		if child.name != "ArmyMarker":
			non_army_children += 1
	_assert(non_army_children == active_cits_count, "S3.1: Child count in YSortEntities (%d) equals active citizens (%d)" % [non_army_children, active_cits_count])

	# Scenario 4: Verify no stale signal connections on citizens
	print("--- Scenario 4: Citizen Signal Cleanliness ---")
	var signal_leak: bool = false
	for child in entities_container.get_children():
		if child is CitizenControllerScript:
			var conns = child.citizen_died.get_connections()
			if conns.size() != 1:
				signal_leak = true
				break
	_assert(signal_leak == false, "S4.1: Citizen signals correctly and uniquely wired (exactly 1 connection per citizen)")

	# Scenario 5: get_node(cid) on entities_container resolves to active citizen
	print("--- Scenario 5: Direct Node Lookup Consistency ---")
	var lookup_ok: bool = true
	for cid in world_instance.citizens_by_id:
		var found_node = entities_container.get_node_or_null(cid)
		if found_node == null or found_node != world_instance.citizens_by_id[cid]:
			lookup_ok = false
			break
	_assert(lookup_ok == true, "S5.1: entities_container.get_node(cid) strictly returns active citizen instance")

	# Scenario 6: Consecutive rapid reloads (5 in a row)
	print("--- Scenario 6: 5 Consecutive Rapid Reloads ---")
	var multi_reload_ok: bool = true
	for i in range(5):
		var d = SaveManagerScript.load_from_file(TEST_MANUAL_PATH)
		var res = SaveManagerScript.apply_loaded_state_to_world(world_instance, d["data"])
		if not res.get("success", false):
			multi_reload_ok = false
			break
		# Check name collisions on each iteration
		for child in entities_container.get_children():
			if child is CitizenControllerScript and child.name != child.citizen_id:
				multi_reload_ok = false
				break
	_assert(multi_reload_ok == true, "S6.1: 5 consecutive reloads succeed with 0 name collisions or stale nodes")

	# Scenario 7: Manual save load into existing world
	print("--- Scenario 7: Manual Save Load Into Existing World ---")
	var m_dict = SaveManagerScript.load_from_file(TEST_MANUAL_PATH)
	var manual_load_res = SaveManagerScript.apply_loaded_state_to_world(world_instance, m_dict["data"])
	_assert(manual_load_res.get("success", false) == true, "S7.1: Manual save load succeeds")

	# Scenario 8: Autosave load into existing world
	print("--- Scenario 8: Autosave Load Into Existing World ---")
	var auto_save_res = SaveManagerScript.save_autosave(world_instance)
	_assert(auto_save_res.get("success", false) == true, "S8.1: Autosave created")
	var a_dict = SaveManagerScript.load_autosave()
	var auto_load_res = SaveManagerScript.apply_loaded_state_to_world(world_instance, a_dict["data"])
	_assert(auto_load_res.get("success", false) == true, "S8.2: Autosave loaded into existing world")

	# Scenario 9: Manager references on newly created citizens are valid
	print("--- Scenario 9: Citizen Manager References ---")
	var refs_valid: bool = true
	for cid in world_instance.citizens_by_id:
		var cit = world_instance.citizens_by_id[cid]
		if cit.job_mgr == null or cit.workplace_mgr == null or cit.nav == null:
			refs_valid = false
			break
	_assert(refs_valid == true, "S9.1: All citizens possess valid job_mgr, workplace_mgr, and nav references")

	# Scenario 10: Legacy save compatibility without leaks
	print("--- Scenario 10: Legacy Save Compatibility ---")
	var legacy_file_dict = SaveManagerScript.load_from_file(TEST_MANUAL_PATH)
	var legacy_save_dict: Dictionary = legacy_file_dict["data"]
	# Remove modern optional sections to simulate legacy save
	if legacy_save_dict.has("field_siege"):
		legacy_save_dict.erase("field_siege")
	if legacy_save_dict.has("battle_campaign"):
		legacy_save_dict.erase("battle_campaign")
	var leg_apply_res = SaveManagerScript.apply_loaded_state_to_world(world_instance, legacy_save_dict)
	_assert(leg_apply_res.get("success", false) == true, "S10.1: Legacy state applied cleanly to world")

	print("\n--------------------------------------------------------")
	if failures == 0:
		print("  RISK-005 SUITE: ALL %d SCENARIO CHECKS PASSED! (0 Failures)" % passed_count)
		print("========================================================\n")
		quit(0)
	else:
		printerr("  RISK-005 SUITE: FAILED WITH %d FAILURES (Passed: %d)" % [failures, passed_count])
		print("========================================================\n")
		quit(1)
