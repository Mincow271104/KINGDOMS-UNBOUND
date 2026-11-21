extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — BUG-003: Save Slot Isolation (Autosave vs Manual Save)
## Authoritative Coverage: TC-SAVE-ISO.1 through TC-SAVE-ISO.10 with Fail-Closed Assertions

const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")

const TEST_MANUAL_PATH: String = "user://test_isolation_manual.json"
const TEST_AUTOSAVE_PATH: String = "user://test_isolation_autosave.json"

var frame_count: int = 0
var world_instance: Node = null
var all_passed: bool = true
var test_results: Array[Dictionary] = []

func _init() -> void:
	print("\n========================================================")
	print("  STARTING BUG-003 SAVE SLOT ISOLATION TEST SUITE")
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

func _record(test_id: String, passed: bool, message: String) -> void:
	test_results.append({"id": test_id, "passed": passed, "message": message})
	if passed:
		print("  [PASS] %s: %s" % [test_id, message])
	else:
		printerr("  [FAIL] %s: %s" % [test_id, message])
		all_passed = false

func _cleanup_test_files() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		var targets := [
			TEST_MANUAL_PATH,
			TEST_MANUAL_PATH + ".bak",
			TEST_MANUAL_PATH + ".tmp",
			TEST_MANUAL_PATH + ".bak.tmp",
			TEST_MANUAL_PATH + ".bak.old",
			TEST_AUTOSAVE_PATH,
			TEST_AUTOSAVE_PATH + ".bak",
			TEST_AUTOSAVE_PATH + ".tmp",
			TEST_AUTOSAVE_PATH + ".bak.tmp",
			TEST_AUTOSAVE_PATH + ".bak.old"
		]
		for t in targets:
			if FileAccess.file_exists(t):
				dir.remove(t)

func _run_all_tests() -> void:
	_test_tc_save_iso_1_manual_writes_to_manual_slot()
	_test_tc_save_iso_2_autosave_writes_to_autosave_slot()
	_test_tc_save_iso_3_autosave_does_not_modify_manual_save()
	_test_tc_save_iso_4_independent_backup_rotation()
	_test_tc_save_iso_5_manual_load_loads_manual_slot()
	_test_tc_save_iso_6_autosave_loaded_explicitly()
	_test_tc_save_iso_7_missing_autosave_does_not_break_manual_load()
	_test_tc_save_iso_8_corrupt_autosave_does_not_corrupt_manual_save()
	_test_tc_save_iso_9_multiple_daily_autosaves_update_only_autosave_slot()
	_test_tc_save_iso_10_backward_compatibility()

	_cleanup_test_files()
	SaveManagerScript.set_test_default_save_path("")
	SaveManagerScript.set_test_autosave_path("")

	print("\n--------------------------------------------------------")
	var passed_count: int = 0
	for res in test_results:
		if res.get("passed", false):
			passed_count += 1
	print("  BUG-003 RESULTS: %d / %d Tests Passed" % [passed_count, test_results.size()])
	if all_passed and passed_count == test_results.size():
		print("  ALL %d BUG-003 SAVE SLOT ISOLATION TESTS PASSED! (Exit Code 0)" % test_results.size())
		print("--------------------------------------------------------\n")
		quit(0)
	else:
		print("  BUG-003 TESTS FAILED! (Exit Code 1)")
		print("--------------------------------------------------------\n")
		quit(1)

# -----------------------------------------------------------------------------
# TC-SAVE-ISO.1: Manual save writes strictly to manual save path
# -----------------------------------------------------------------------------
func _test_tc_save_iso_1_manual_writes_to_manual_slot() -> void:
	var res: Dictionary = SaveManagerScript.save_to_file(world_instance, TEST_MANUAL_PATH)
	var ok: bool = (
		res.get("success", false) == true
		and FileAccess.file_exists(TEST_MANUAL_PATH)
		and not FileAccess.file_exists(TEST_AUTOSAVE_PATH)
	)
	_record("TC-SAVE-ISO.1", ok, "Manual save writes to manual slot without touching autosave slot")

# -----------------------------------------------------------------------------
# TC-SAVE-ISO.2: Autosave writes strictly to autosave path
# -----------------------------------------------------------------------------
func _test_tc_save_iso_2_autosave_writes_to_autosave_slot() -> void:
	var res: Dictionary = SaveManagerScript.save_autosave(world_instance)
	var ok: bool = (
		res.get("success", false) == true
		and FileAccess.file_exists(TEST_AUTOSAVE_PATH)
	)
	_record("TC-SAVE-ISO.2", ok, "Autosave writes strictly to autosave path (%s)" % TEST_AUTOSAVE_PATH)

# -----------------------------------------------------------------------------
# TC-SAVE-ISO.3: Autosave does not modify manual save bytes or content
# -----------------------------------------------------------------------------
func _test_tc_save_iso_3_autosave_does_not_modify_manual_save() -> void:
	var manual_content_before: String = FileAccess.get_file_as_string(TEST_MANUAL_PATH)
	var manual_modified_time_before: int = FileAccess.get_modified_time(TEST_MANUAL_PATH)

	# Trigger autosave again
	SaveManagerScript.save_autosave(world_instance)

	var manual_content_after: String = FileAccess.get_file_as_string(TEST_MANUAL_PATH)
	var manual_modified_time_after: int = FileAccess.get_modified_time(TEST_MANUAL_PATH)

	var ok: bool = (
		manual_content_before == manual_content_after
		and manual_modified_time_before == manual_modified_time_after
	)
	_record("TC-SAVE-ISO.3", ok, "Autosave execution leaves manual save content and timestamp 100% untouched")

# -----------------------------------------------------------------------------
# TC-SAVE-ISO.4: Independent backup rotation for manual and autosave slots
# -----------------------------------------------------------------------------
func _test_tc_save_iso_4_independent_backup_rotation() -> void:
	# Saving manual again creates manual .bak
	SaveManagerScript.save_to_file(world_instance, TEST_MANUAL_PATH)
	var has_manual_bak: bool = FileAccess.file_exists(TEST_MANUAL_PATH + ".bak")

	# Saving autosave again creates autosave .bak
	SaveManagerScript.save_autosave(world_instance)
	var has_auto_bak: bool = FileAccess.file_exists(TEST_AUTOSAVE_PATH + ".bak")

	var ok: bool = has_manual_bak and has_auto_bak
	_record("TC-SAVE-ISO.4", ok, "Both manual and autosave maintain independent .bak backups")

# -----------------------------------------------------------------------------
# TC-SAVE-ISO.5: Manual load still loads legacy manual slot
# -----------------------------------------------------------------------------
func _test_tc_save_iso_5_manual_load_loads_manual_slot() -> void:
	var load_res: Dictionary = SaveManagerScript.load_from_file(TEST_MANUAL_PATH)
	var ok: bool = (
		load_res.get("success", false) == true
		and load_res.get("data") != null
		and load_res.get("source_path") == TEST_MANUAL_PATH
	)
	_record("TC-SAVE-ISO.5", ok, "Manual load correctly loads from manual save slot")

# -----------------------------------------------------------------------------
# TC-SAVE-ISO.6: Autosave can be loaded explicitly
# -----------------------------------------------------------------------------
func _test_tc_save_iso_6_autosave_loaded_explicitly() -> void:
	var load_res: Dictionary = SaveManagerScript.load_autosave()
	var ok: bool = (
		load_res.get("success", false) == true
		and load_res.get("data") != null
		and load_res.get("source_path") == TEST_AUTOSAVE_PATH
	)
	_record("TC-SAVE-ISO.6", ok, "Autosave can be loaded explicitly via load_autosave()")

# -----------------------------------------------------------------------------
# TC-SAVE-ISO.7: Missing autosave does not break manual load
# -----------------------------------------------------------------------------
func _test_tc_save_iso_7_missing_autosave_does_not_break_manual_load() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		if FileAccess.file_exists(TEST_AUTOSAVE_PATH): dir.remove(TEST_AUTOSAVE_PATH)
		if FileAccess.file_exists(TEST_AUTOSAVE_PATH + ".bak"): dir.remove(TEST_AUTOSAVE_PATH + ".bak")

	var manual_load: Dictionary = SaveManagerScript.load_from_file(TEST_MANUAL_PATH)
	var has_auto: bool = SaveManagerScript.has_autosave()

	var ok: bool = (
		manual_load.get("success", false) == true
		and not has_auto
	)
	_record("TC-SAVE-ISO.7", ok, "Absence of autosave has zero impact on manual load success")

# -----------------------------------------------------------------------------
# TC-SAVE-ISO.8: Corrupt autosave does not overwrite or corrupt manual save
# -----------------------------------------------------------------------------
func _test_tc_save_iso_8_corrupt_autosave_does_not_corrupt_manual_save() -> void:
	# Write corrupt garbage into autosave slot
	var f := FileAccess.open(TEST_AUTOSAVE_PATH, FileAccess.WRITE)
	f.store_string("CORRUPTED_JSON_DATA_GARBAGE_12345")
	f.close()

	var manual_load: Dictionary = SaveManagerScript.load_from_file(TEST_MANUAL_PATH)
	var auto_load: Dictionary = SaveManagerScript.load_autosave()

	var ok: bool = (
		manual_load.get("success", false) == true
		and auto_load.get("success", false) == false
	)
	_record("TC-SAVE-ISO.8", ok, "Corrupted autosave fails closed and never affects manual save integrity")

# -----------------------------------------------------------------------------
# TC-SAVE-ISO.9: Multiple daily autosaves update only the autosave slot
# -----------------------------------------------------------------------------
func _test_tc_save_iso_9_multiple_daily_autosaves_update_only_autosave_slot() -> void:
	var manual_bytes_before: int = FileAccess.get_file_as_string(TEST_MANUAL_PATH).length()

	# Simulate day 1, 2, 3 autosaves via WorldView simulation day passed with synchronized game clock
	var tm = world_instance.get_node_or_null("/root/TimeManager")
	for d in range(1, 4):
		if tm != null:
			tm.current_day = d
		world_instance.call("_on_simulation_day_passed", d, "Spring", 1)

	var manual_bytes_after: int = FileAccess.get_file_as_string(TEST_MANUAL_PATH).length()
	var auto_exists: bool = FileAccess.file_exists(TEST_AUTOSAVE_PATH)

	var ok: bool = (
		manual_bytes_before == manual_bytes_after
		and auto_exists
	)
	_record("TC-SAVE-ISO.9", ok, "Sequential daily autosaves cycle exclusively within autosave slot")

# -----------------------------------------------------------------------------
# TC-SAVE-ISO.10: Save/load state remains backward compatible
# -----------------------------------------------------------------------------
func _test_tc_save_iso_10_backward_compatibility() -> void:
	# Standard default save path constant check
	var def_path: String = SaveManagerScript.DEFAULT_SAVE_PATH
	var auto_path: String = SaveManagerScript.AUTOSAVE_PATH

	var ok: bool = (
		def_path == "user://saves/world_save.json"
		and auto_path == "user://saves/autosave.json"
		and def_path != auto_path
	)
	_record("TC-SAVE-ISO.10", ok, "Default paths preserve full backward compatibility with legacy saves")
