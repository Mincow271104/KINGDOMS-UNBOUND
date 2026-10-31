extends SceneTree
## Headless Test Suite for Phase 8: Robust Save/Load & Persistence Hardening.
## Validates TC-8.1 (Save -> Load -> Save Equivalence) and TC-8.2 (Corruption Handling & Backup Recovery).

const SaveManager = preload("res://scripts/persistence/save_manager.gd")
const ImmigrationManagerScript = preload("res://scripts/economy/immigration_manager.gd")
const WorldEventSystemScript = preload("res://scripts/core/world_event_system.gd")

const SAVE_PATH_1: String = "user://saves/test_roundtrip_1.json"
const SAVE_PATH_2: String = "user://saves/test_roundtrip_2.json"
const TEST_CORRUPT_PATH: String = "user://saves/test_corrupt_save.json"
const TEST_BAK_PATH: String = "user://saves/test_backup_restore.json"
const TEST_DEFAULT_SAVE_OVERRIDE: String = "user://saves/test_isolated_default_world_save.json"

var frame_count: int = 0
var world_instance: Node = null
var _assertions_passed: int = 0
var _assertions_failed: int = 0

func _cleanup_test_save_files() -> void:
	SaveManager.set_test_default_save_path("")
	var dir := DirAccess.open("user://")
	if dir != null:
		for base_p in [SAVE_PATH_1, SAVE_PATH_2, TEST_CORRUPT_PATH, TEST_BAK_PATH, TEST_DEFAULT_SAVE_OVERRIDE]:
			for suffix in ["", ".bak", ".tmp", ".bak.tmp", ".bak.old"]:
				var p: String = base_p + suffix
				if FileAccess.file_exists(p):
					dir.remove(p)

func _assert_true(cond: bool, label: String, desc: String = "") -> bool:
	if cond:
		_assertions_passed += 1
		print("  [PASS] [%s]%s" % [label, (" - " + desc) if not desc.is_empty() else ""])
		return true
	else:
		_assertions_failed += 1
		printerr("  [FAIL] [%s]%s" % [label, (" - " + desc) if not desc.is_empty() else ""])
		return false

func _assert_eq(actual: Variant, expected: Variant, label: String, desc: String = "") -> bool:
	if actual == expected:
		_assertions_passed += 1
		print("  [PASS] [%s]: %s == %s%s" % [label, str(actual), str(expected), (" - " + desc) if not desc.is_empty() else ""])
		return true
	else:
		_assertions_failed += 1
		printerr("  [FAIL] [%s]: expected %s, got %s%s" % [label, str(expected), str(actual), (" - " + desc) if not desc.is_empty() else ""])
		return false

func _init() -> void:
	print("\n========================================================")
	print("  TEST SUITE: Phase 8 — Robust Save/Load & Persistence")
	print("========================================================\n")
	
	SaveManager.ensure_save_directory()
	SaveManager.set_test_default_save_path(TEST_DEFAULT_SAVE_OVERRIDE)
	
	# Instantiate live WorldView scene into root
	var world_scene: PackedScene = load("res://scenes/world/world_view.tscn")
	world_instance = world_scene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	
	# Allow world_instance._ready() to initialize
	if frame_count == 3:
		var pass_tc1: bool = _test_tc8_1_save_load_equivalence()
		var pass_tc2: bool = _test_tc8_2_corruption_and_backup_recovery()
		var pass_tc3: bool = _test_tc8_3_ui_save_load_workflow()
		var pass_tc4: bool = _test_tc8_4_clock_and_legacy_season_fallback()
		var pass_tc5: bool = _test_tc8_5_starvation_reset_and_load_integrity()
		var pass_tc6: bool = _test_tc8_6_battle_campaign_sequence_compatibility()
		var pass_tc7: bool = _test_tc8_7_immigration_persistence_and_collision_proof_ids()
		var pass_tc8: bool = _test_tc8_8_world_event_persistence_and_legacy_fallback()
		var pass_tc9: bool = _test_tc8_9_package_1x_schema_validation()
		var pass_tc10: bool = _test_tc8_10_package_1x_worldview_and_double_load()
		var pass_tc11: bool = _test_tc8_11_hardening_gates_combat_transactional_and_caravan()

		_cleanup_test_save_files()
		
		print("\n--------------------------------------------------------")
		print("  Assertions Passed: %d | Failed: %d" % [_assertions_passed, _assertions_failed])
		if pass_tc1 and pass_tc2 and pass_tc3 and pass_tc4 and pass_tc5 and pass_tc6 and pass_tc7 and pass_tc8 and pass_tc9 and pass_tc10 and pass_tc11 and _assertions_failed == 0:
			print("  ALL PHASE 8 PERSISTENCE TESTS PASSED! (Exit Code 0)")
			print("--------------------------------------------------------\n")
			quit(0)
			return true
		else:
			print("  PHASE 8 TESTS FAILED!")
			print("--------------------------------------------------------\n")
			quit(1)
			return true
			
	return false

func _test_tc8_1_save_load_equivalence() -> bool:
	print("--- Running TC-8.1: Save -> Load -> Save Canonical Equivalence ---")

	# Verify initial populated world
	var initial_cits: Array = world_instance.get("citizen_list")
	var world_data = world_instance.get("world_data")
	if world_data == null or initial_cits == null:
		print("  [FAIL] WorldData or citizen list not initialized!")
		return false
		
	var initial_blds: Array = world_data.buildings
	if initial_cits.size() != 24:
		print("  [FAIL] Expected 24 initial citizens, got %d" % initial_cits.size())
		return false
	if initial_blds.size() != 8:
		print("  [FAIL] Expected 8 initial buildings, got %d" % initial_blds.size())
		return false
	print("  [PASS] Initial WorldView verified (24 citizens, 8 buildings).")

	# 1. First Save: World State -> SAVE_PATH_1
	var save_res1 := SaveManager.save_to_file(world_instance, SAVE_PATH_1)
	if not save_res1["success"]:
		print("  [FAIL] First save failed: %s" % save_res1["error"])
		return false
	print("  [PASS] First save completed successfully (%d bytes written)." % save_res1["bytes"])

	# 2. Load from SAVE_PATH_1
	var load_res := SaveManager.load_from_file(SAVE_PATH_1)
	if not load_res["success"]:
		print("  [FAIL] Load from save failed: %s" % load_res["error"])
		return false
	var loaded_data: Dictionary = load_res["data"]
	print("  [PASS] Save file parsed and validated cleanly.")

	# 3. Apply Loaded State back to WorldView (Testing reconstruction and duplicate prevention)
	var apply_res := SaveManager.apply_loaded_state_to_world(world_instance, loaded_data)
	if not apply_res["success"]:
		print("  [FAIL] Apply state to world failed: %s" % apply_res["error"])
		return false

	# Verify no node duplication occurred during reconstruction
	var reconstructed_cits: Array = world_instance.get("citizen_list")
	var reconstructed_blds: Array = world_instance.get("world_data").buildings
	if reconstructed_cits.size() != 24:
		print("  [FAIL] Citizen count after reconstruction was duplicated or lost! (got %d, expected 24)" % reconstructed_cits.size())
		return false
	if reconstructed_blds.size() != 8:
		print("  [FAIL] Building count after reconstruction was duplicated or lost! (got %d, expected 8)" % reconstructed_blds.size())
		return false
	print("  [PASS] Reconstructed state verified: zero entity or building duplication.")

	# 4. Second Save: Reconstructed World State -> SAVE_PATH_2
	var save_res2 := SaveManager.save_to_file(world_instance, SAVE_PATH_2)
	if not save_res2["success"]:
		print("  [FAIL] Second save failed: %s" % save_res2["error"])
		return false

	var load_res2 := SaveManager.load_from_file(SAVE_PATH_2)
	if not load_res2["success"]:
		print("  [FAIL] Second load failed: %s" % load_res2["error"])
		return false
	var state_1: Dictionary = load_res["data"]
	var state_2: Dictionary = load_res2["data"]

	# 5. Deep Equivalence Assertions across all subsystems
	print("  state_1 resources: ", state_1.get("resources"))
	print("  state_2 resources: ", state_2.get("resources"))
	if state_1["metadata"]["world_seed"] != state_2["metadata"]["world_seed"]:
		print("  [FAIL] Seed mismatch between saves!")
		return false
	if state_1["resources"].get("stock") != state_2["resources"].get("stock"):
		print("  [FAIL] Resource stocks mismatch between saves!")
		return false
	if state_1["resources"]["capacities"] != state_2["resources"]["capacities"]:
		print("  [FAIL] Resource capacities mismatch between saves!")
		return false
	if state_1["citizens"].size() != state_2["citizens"].size():
		print("  [FAIL] Citizen array size mismatch!")
		return false
	for i in range(state_1["citizens"].size()):
		var c1: Dictionary = state_1["citizens"][i]
		var c2: Dictionary = state_2["citizens"][i]
		if c1["id"] != c2["id"] or c1["name"] != c2["name"] or c1["role"] != c2["role"] or c1["cell_x"] != c2["cell_x"] or c1["cell_y"] != c2["cell_y"]:
			print("  [FAIL] Citizen %s data diverged across save-load roundtrip!" % c1["id"])
			return false
	if state_1["buildings"].size() != state_2["buildings"].size():
		print("  [FAIL] Buildings array size mismatch!")
		return false
	for i in range(state_1["buildings"].size()):
		var b1: Dictionary = state_1["buildings"][i]
		var b2: Dictionary = state_2["buildings"][i]
		if b1["id"] != b2["id"] or b1["type"] != b2["type"] or b1["cell_x"] != b2["cell_x"] or b1["cell_y"] != b2["cell_y"]:
			print("  [FAIL] Building %s data diverged across save-load roundtrip!" % b1["id"])
			return false
	if state_1["research"] != state_2["research"]:
		print("  [FAIL] Research state diverged across save-load roundtrip!")
		return false
	if state_1["victory"] != state_2["victory"]:
		print("  [FAIL] Victory state diverged across save-load roundtrip!")
		return false
	if state_1.has("fog_of_war") and state_2.has("fog_of_war"):
		if state_1["fog_of_war"] != state_2["fog_of_war"]:
			print("  [FAIL] Fog of war diverged across save-load roundtrip!")
			return false

	print("  [PASS] Save -> Load -> Save roundtrip preserved 100% canonical state equivalence.")
	print("  [PASS] TC-8.1 PASSED.\n")
	return true

func _test_tc8_2_corruption_and_backup_recovery() -> bool:
	print("--- Running TC-8.2: Corruption Handling & Backup Recovery ---")

	# Test 1: Incompatible schema version
	var bad_ver_dict := {"schema_version": 999, "metadata": {}, "resources": {}, "buildings": [], "citizens": []}
	var val_res1: Dictionary = SaveManager.validate_save_data(bad_ver_dict)
	if val_res1["valid"]:
		print("  [FAIL] Incompatible schema version was erroneously accepted!")
		return false
	print("  [PASS] Incompatible schema version correctly rejected: %s" % val_res1["error"])

	# Test 2: Missing essential section (e.g. missing 'citizens')
	var missing_sec_dict := {"schema_version": 1, "metadata": {}, "resources": {}, "buildings": []}
	var val_res2: Dictionary = SaveManager.validate_save_data(missing_sec_dict)
	if val_res2["valid"]:
		print("  [FAIL] Missing essential section was erroneously accepted!")
		return false
	print("  [PASS] Missing section correctly rejected: %s" % val_res2["error"])

	# Test 3: Malformed / Corrupted JSON text on disk
	var corrupt_file := FileAccess.open(TEST_CORRUPT_PATH, FileAccess.WRITE)
	if corrupt_file:
		corrupt_file.store_string('{"schema_version": 1, "metadata": { "unclosed": true ')
		corrupt_file.close()

	var corrupt_load: Dictionary = SaveManager.load_from_file(TEST_CORRUPT_PATH)
	if corrupt_load["success"]:
		print("  [FAIL] Malformed JSON was accepted as successful load!")
		return false
	if not corrupt_load["error"].contains("Lỗi phân tích cú pháp"):
		print("  [FAIL] Malformed JSON error did not mention parser error: %s" % corrupt_load["error"])
		return false
	print("  [PASS] Malformed JSON file rejected gracefully: %s" % corrupt_load["error"])

	# Test 4: Automatic Backup (.bak) Recovery when main save is missing
	var good_bak_dict: Dictionary = {
		"schema_version": 1,
		"metadata": {"world_seed": 77777, "difficulty": "normal"},
		"resources": {"stock": {"food": 100}, "capacities": {}, "active_population": 24},
		"buildings": [],
		"citizens": []
	}
	var bak_json := JSON.stringify(good_bak_dict, "\t")
	var bak_file := FileAccess.open(TEST_BAK_PATH + ".bak", FileAccess.WRITE)
	if bak_file:
		bak_file.store_string(bak_json)
		bak_file.close()

	# Remove main save file if exists to trigger fallback
	var dir := DirAccess.open("user://")
	if dir != null and FileAccess.file_exists(TEST_BAK_PATH):
		dir.remove(TEST_BAK_PATH)

	var bak_load: Dictionary = SaveManager.load_from_file(TEST_BAK_PATH)
	if not bak_load["success"]:
		print("  [FAIL] Fallback to .bak failed: %s" % bak_load["error"])
		return false
	if bak_load["data"]["metadata"]["world_seed"] != 77777:
		print("  [FAIL] Fallback .bak data content mismatch!")
		return false
	print("  [PASS] Automatic fallback to backup (.bak) succeeded.")

	print("  [PASS] TC-8.2 PASSED.\n")
	return true

func _test_tc8_3_ui_save_load_workflow() -> bool:
	print("--- Running TC-8.3: UI Save/Load & Menu Integration ---")
	var hud = world_instance.get("hud")
	if hud == null:
		print("  [FAIL] HUD not found on world instance!")
		return false

	# 1. Open Pause Menu
	hud.call("_toggle_pause_menu")
	var pause_dialog: Control = hud.get_node_or_null("PauseMenuOverlay")
	if pause_dialog == null or not pause_dialog.visible:
		print("  [FAIL] Pause menu dialog did not open!")
		return false
	print("  [PASS] Pause menu opened successfully.")

	# 2. Trigger Save Game from HUD UI
	hud.call("_on_save_game_pressed")
	var status_lbl: Label = hud.get_node_or_null("PauseMenuOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SaveStatusLabel")
	if status_lbl == null or not status_lbl.text.contains("thành công"):
		print("  [FAIL] HUD save button did not indicate success! Label text: %s" % (status_lbl.text if status_lbl else "null"))
		return false
	print("  [PASS] HUD save triggered and displayed success feedback: '%s'" % status_lbl.text)

	# Verify save file exists on disk (at isolated test path)
	var expected_save_path := SaveManager._resolve_filepath(SaveManager.DEFAULT_SAVE_PATH)
	if not FileAccess.file_exists(expected_save_path):
		print("  [FAIL] Default save file does not exist on disk!")
		return false
	print("  [PASS] Save file confirmed on disk at %s" % expected_save_path)

	# 3. Modify live world state (e.g. consume gold)
	var rm = root.get_node_or_null("ResourceManager")
	var original_gold: int = rm.get_available_stock("gold") if rm else 0
	if rm:
		rm.consume_resource("gold", 50)
		print("  Modified live gold stock: %d -> %d" % [original_gold, rm.get_available_stock("gold")])

	# 4. Trigger Load Game from HUD UI
	hud.call("_on_load_game_pressed")
	if rm and rm.get_available_stock("gold") != original_gold:
		print("  [FAIL] Live gold stock was not restored by HUD load! (got %d, expected %d)" % [rm.get_available_stock("gold"), original_gold])
		return false
	print("  [PASS] HUD load restored original live world state.")

	# 5. Verify MainMenu recognizes save file
	var main_menu_scene: PackedScene = load("res://scenes/ui/main_menu.tscn")
	var main_menu = main_menu_scene.instantiate()
	root.add_child(main_menu)
	var load_btn: Button = main_menu.get_node_or_null("CenterContainer/MainPanel/MarginContainer/VBoxContainer/ActionButtons/LoadWorldBtn")
	if load_btn == null or load_btn.disabled:
		print("  [FAIL] MainMenu LoadWorldBtn is disabled despite valid save file!")
		main_menu.queue_free()
		return false
	print("  [PASS] MainMenu LoadWorldBtn is enabled with tooltip: '%s'" % load_btn.tooltip_text)
	main_menu.queue_free()

	print("  [PASS] TC-8.3 PASSED.\n")
	return true

func _test_tc8_4_clock_and_legacy_season_fallback() -> bool:
	print("--- Running TC-8.4: BUG-01 TimeManager Non-Spring Roundtrip, Legacy Season Fallback & Validation ---")
	var tm: Node = root.get_node_or_null("TimeManager")
	if not _assert_true(tm != null, "TC-8.4-TM-EXISTS", "TimeManager autoload exists"):
		return false

	# 1. Configure live TimeManager to a non-Spring season: Day 25 (Autumn, season_index = 2), Hour 14, Year 1, Speed 2
	tm.reset_time(14, 25, 1)
	tm.set_speed(2)
	_assert_eq(tm.get("season_index"), 2, "TC-8.4-PRE-SEASON-IDX", "Day 25 is Autumn (season_index = 2)")
	_assert_eq(tm.call("get_current_season_key"), "autumn", "TC-8.4-PRE-SEASON-KEY", "Season key is autumn")

	var saved_autumn: Dictionary = SaveManager.serialize_world_state(world_instance)
	var clock_sec: Dictionary = saved_autumn.get("game_clock", {})
	_assert_eq(clock_sec.get("current_day"), 25, "TC-8.4-SER-DAY", "Serialized current_day == 25")
	_assert_eq(clock_sec.get("current_hour"), 14, "TC-8.4-SER-HOUR", "Serialized current_hour == 14")
	_assert_eq(clock_sec.get("season_index"), 2, "TC-8.4-SER-SEASON", "Serialized season_index == 2")
	_assert_eq(clock_sec.get("current_year"), 1, "TC-8.4-SER-YEAR", "Serialized current_year == 1")
	_assert_eq(clock_sec.get("current_speed"), 2, "TC-8.4-SER-SPEED", "Serialized current_speed == 2")
	_assert_true(not clock_sec.has("current_season"), "TC-8.4-NO-GHOST-SEASON", "Ghost field current_season not serialized")
	_assert_true(not clock_sec.has("total_elapsed_seconds"), "TC-8.4-NO-GHOST-ELAPSED", "Ghost field total_elapsed_seconds not serialized")

	# Perturb live TimeManager back to Day 1 Spring
	tm.reset_time(6, 1, 1)
	_assert_eq(tm.get("season_index"), 0, "TC-8.4-PERTURB-SPRING", "Reset to Spring before load")

	# Apply saved state and verify live TimeManager restoration
	var apply_autumn: Dictionary = SaveManager.apply_loaded_state_to_world(world_instance, saved_autumn)
	_assert_true(apply_autumn.get("success", false), "TC-8.4-APPLY-AUTUMN", "Autumn save applied cleanly")
	_assert_eq(tm.get("current_day"), 25, "TC-8.4-RESTORED-DAY", "Restored live current_day == 25")
	_assert_eq(tm.get("current_hour"), 14, "TC-8.4-RESTORED-HOUR", "Restored live current_hour == 14")
	_assert_eq(tm.get("season_index"), 2, "TC-8.4-RESTORED-SEASON-IDX", "Restored live season_index == 2")
	_assert_eq(tm.call("get_current_season_key"), "autumn", "TC-8.4-RESTORED-SEASON-KEY", "Restored live season key == autumn")
	_assert_eq(tm.get("current_year"), 1, "TC-8.4-RESTORED-YEAR", "Restored live current_year == 1")
	_assert_eq(tm.get("current_speed"), 2, "TC-8.4-RESTORED-SPEED", "Restored live current_speed == 2")

	# 2. Legacy save missing season_index and current_year: Day 55 -> Year 2, Day 15 of Year 2 -> Summer (season_index = 1)
	var legacy_clock_save: Dictionary = saved_autumn.duplicate(true)
	legacy_clock_save["game_clock"] = {
		"current_day": 55,
		"current_hour": 19
	}
	tm.reset_time(6, 1, 1)
	var apply_legacy_clock: Dictionary = SaveManager.apply_loaded_state_to_world(world_instance, legacy_clock_save)
	_assert_true(apply_legacy_clock.get("success", false), "TC-8.4-LEGACY-APPLY", "Legacy clock save applied cleanly")
	_assert_eq(tm.get("current_day"), 55, "TC-8.4-LEGACY-DAY", "Restored legacy current_day == 55")
	_assert_eq(tm.get("current_hour"), 19, "TC-8.4-LEGACY-HOUR", "Restored legacy current_hour == 19")
	_assert_eq(tm.get("season_index"), 1, "TC-8.4-LEGACY-DERIVED-SEASON", "Derived Summer (season_index = 1) from Day 55")
	_assert_eq(tm.call("get_current_season_key"), "summer", "TC-8.4-LEGACY-SEASON-KEY", "Derived season key is summer")
	_assert_eq(tm.get("current_year"), 2, "TC-8.4-LEGACY-DERIVED-YEAR", "Derived Year 2 from Day 55")

	# 3. Validation of out-of-range / invalid game_clock fields
	var bad_hour_save: Dictionary = saved_autumn.duplicate(true)
	bad_hour_save["game_clock"]["current_hour"] = 24
	_assert_eq(SaveManager.validate_save_data(bad_hour_save).get("valid", true), false, "TC-8.4-VAL-BAD-HOUR", "current_hour = 24 rejected")

	var bad_season_save: Dictionary = saved_autumn.duplicate(true)
	bad_season_save["game_clock"]["season_index"] = 4
	_assert_eq(SaveManager.validate_save_data(bad_season_save).get("valid", true), false, "TC-8.4-VAL-BAD-SEASON", "season_index = 4 rejected")

	var bad_year_save: Dictionary = saved_autumn.duplicate(true)
	bad_year_save["game_clock"]["current_year"] = 0
	_assert_eq(SaveManager.validate_save_data(bad_year_save).get("valid", true), false, "TC-8.4-VAL-BAD-YEAR", "current_year = 0 rejected")

	# Restore clean time state
	tm.reset_time(6, 1, 1)
	print("  [PASS] TC-8.4 PASSED.\n")
	return _assertions_failed == 0

func _test_tc8_5_starvation_reset_and_load_integrity() -> bool:
	print("--- Running TC-8.5: BUG-02 Starvation Reset, Save/Load Restoration & Legacy Derivation ---")
	var rm: Node = root.get_node_or_null("ResourceManager")
	if not _assert_true(rm != null, "TC-8.5-RM-EXISTS", "ResourceManager autoload exists"):
		return false

	# 1. Trigger starvation and verify reset_economy() clears _is_starving
	rm.reset_economy()
	_assert_eq(rm.is_starving(), false, "TC-8.5-INIT-NOT-STARVING", "Not starving after fresh reset_economy")
	rm.consume_resource("food", rm.get_available_stock("food"))
	rm._execute_daily_accounting_tick()
	_assert_eq(rm.is_starving(), true, "TC-8.5-STARVING-TRIGGERED", "Starvation triggered when food depleted on daily tick")
	rm.reset_economy()
	_assert_eq(rm.is_starving(), false, "TC-8.5-RESET-CLEARS-STARVING", "reset_economy() clears _is_starving immediately")

	# 2. Save while starving -> reset -> load -> verify is_starving() is true immediately after load
	rm.consume_resource("food", rm.get_available_stock("food"))
	rm._execute_daily_accounting_tick()
	_assert_eq(rm.is_starving(), true, "TC-8.5-PRE-SAVE-STARVING", "Colony is starving before save")
	var starving_save: Dictionary = SaveManager.serialize_world_state(world_instance)
	_assert_eq(starving_save["resources"].get("is_starving"), true, "TC-8.5-SER-STARVING", "Serialized resources.is_starving == true")

	rm.reset_economy()
	_assert_eq(rm.is_starving(), false, "TC-8.5-PRE-LOAD-CLEARED", "Live starvation cleared before load")
	var apply_starving: Dictionary = SaveManager.apply_loaded_state_to_world(world_instance, starving_save)
	_assert_true(apply_starving.get("success", false), "TC-8.5-APPLY-STARVING", "Starving save applied cleanly")
	_assert_eq(rm.is_starving(), true, "TC-8.5-RESTORED-STARVING", "is_starving() == true immediately after load without waiting for next day tick")
	_assert_eq(rm.get_available_stock("food"), 0, "TC-8.5-RESTORED-FOOD-ZERO", "Restored food stock is 0")

	# 3. Legacy save lacking is_starving field: derive deterministically from food <= 0 and active_population > 0
	var legacy_starving_save: Dictionary = starving_save.duplicate(true)
	legacy_starving_save["resources"].erase("is_starving")
	rm.reset_economy()
	var apply_legacy_starving: Dictionary = SaveManager.apply_loaded_state_to_world(world_instance, legacy_starving_save)
	_assert_true(apply_legacy_starving.get("success", false), "TC-8.5-LEGACY-STARVING-APPLY", "Legacy starving save applied")
	_assert_eq(rm.is_starving(), true, "TC-8.5-LEGACY-STARVING-DERIVED", "Legacy save with 0 food deterministically derives is_starving() == true")

	var legacy_fed_save: Dictionary = legacy_starving_save.duplicate(true)
	legacy_fed_save["resources"]["stock"]["food"] = 120
	var apply_legacy_fed: Dictionary = SaveManager.apply_loaded_state_to_world(world_instance, legacy_fed_save)
	_assert_true(apply_legacy_fed.get("success", false), "TC-8.5-LEGACY-FED-APPLY", "Legacy fed save applied")
	_assert_eq(rm.is_starving(), false, "TC-8.5-LEGACY-FED-DERIVED", "Legacy save with 120 food derives is_starving() == false")

	# 4. Validation rejects non-boolean is_starving
	var bad_starving_save: Dictionary = starving_save.duplicate(true)
	bad_starving_save["resources"]["is_starving"] = "invalid_bool"
	_assert_eq(SaveManager.validate_save_data(bad_starving_save).get("valid", true), false, "TC-8.5-VAL-BAD-STARVING", "Non-boolean is_starving rejected")

	rm.reset_economy()
	print("  [PASS] TC-8.5 PASSED.\n")
	return _assertions_failed == 0

func _test_tc8_6_battle_campaign_sequence_compatibility() -> bool:
	print("--- Running TC-8.6: BUG-05 Battle Campaign Sequence Validation & Legacy Alias Compatibility ---")
	var bcm = world_instance.get("battle_campaign_mgr")
	var tm: Node = root.get_node_or_null("TimeManager")
	if not _assert_true(bcm != null and tm != null, "TC-8.6-DEPS-EXIST", "BattleCampaignManager and TimeManager exist"):
		return false

	var base_save: Dictionary = SaveManager.serialize_world_state(world_instance)

	# 1. Valid offensive_sequence
	var valid_off_save: Dictionary = base_save.duplicate(true)
	valid_off_save["battle_campaign"] = {"offensive_sequence": 5, "pending_raids": {}, "processed_raids": {}}
	_assert_eq(SaveManager.validate_save_data(valid_off_save).get("valid", false), true, "TC-8.6-VAL-OFF-OK", "Valid offensive_sequence = 5 accepted")
	var apply_off: Dictionary = SaveManager.apply_loaded_state_to_world(world_instance, valid_off_save)
	_assert_true(apply_off.get("success", false), "TC-8.6-APPLY-OFF-OK", "Applied offensive_sequence = 5")
	_assert_eq(bcm.get_offensive_campaign_sequence(), 5, "TC-8.6-RESTORED-OFF-SEQ", "Restored offensive_sequence == 5")

	# 2. Legacy campaign_sequence accepted & restored when valid
	var valid_leg_save: Dictionary = base_save.duplicate(true)
	valid_leg_save["battle_campaign"] = {"campaign_sequence": 8, "pending_raids": {}, "processed_raids": {}}
	_assert_eq(SaveManager.validate_save_data(valid_leg_save).get("valid", false), true, "TC-8.6-VAL-LEG-OK", "Valid legacy campaign_sequence = 8 accepted")
	var apply_leg: Dictionary = SaveManager.apply_loaded_state_to_world(world_instance, valid_leg_save)
	_assert_true(apply_leg.get("success", false), "TC-8.6-APPLY-LEG-OK", "Applied legacy campaign_sequence = 8")
	_assert_eq(bcm.get_offensive_campaign_sequence(), 8, "TC-8.6-RESTORED-LEG-SEQ", "Legacy campaign_sequence = 8 restored into manager")

	# 3. Invalid offensive_sequence (negative or wrong type) rejected
	var neg_off_save: Dictionary = base_save.duplicate(true)
	neg_off_save["battle_campaign"] = {"offensive_sequence": -3, "pending_raids": {}, "processed_raids": {}}
	_assert_eq(SaveManager.validate_save_data(neg_off_save).get("valid", true), false, "TC-8.6-VAL-OFF-NEG", "Negative offensive_sequence = -3 rejected")

	var str_off_save: Dictionary = base_save.duplicate(true)
	str_off_save["battle_campaign"] = {"offensive_sequence": "bad", "pending_raids": {}, "processed_raids": {}}
	_assert_eq(SaveManager.validate_save_data(str_off_save).get("valid", true), false, "TC-8.6-VAL-OFF-STR", "String offensive_sequence rejected")

	# 4. Invalid legacy campaign_sequence rejected BEFORE mutating live world state (even when offensive_sequence is valid)
	tm.reset_time(9, 12, 1)
	bcm.set_offensive_campaign_sequence(8)
	var bad_leg_save: Dictionary = base_save.duplicate(true)
	bad_leg_save["game_clock"]["current_day"] = 99
	bad_leg_save["battle_campaign"] = {"campaign_sequence": -1, "offensive_sequence": 4, "pending_raids": {}, "processed_raids": {}}
	_assert_eq(SaveManager.validate_save_data(bad_leg_save).get("valid", true), false, "TC-8.6-VAL-LEG-NEG", "Negative legacy campaign_sequence = -1 rejected")

	var apply_bad_leg: Dictionary = SaveManager.apply_loaded_state_to_world(world_instance, bad_leg_save)
	_assert_eq(apply_bad_leg.get("success", true), false, "TC-8.6-APPLY-LEG-NEG-REJECTED", "apply_loaded_state_to_world rejected invalid campaign_sequence")
	_assert_eq(tm.get("current_day"), 12, "TC-8.6-NO-MUTATION-DAY", "Live TimeManager.current_day remained 12 (unmutated)")
	_assert_eq(bcm.get_offensive_campaign_sequence(), 8, "TC-8.6-NO-MUTATION-SEQ", "Live campaign sequence remained 8 (unmutated)")

	tm.reset_time(6, 1, 1)
	bcm.set_offensive_campaign_sequence(0)
	print("  [PASS] TC-8.6 PASSED.\n")
	return _assertions_failed == 0

func _test_tc8_7_immigration_persistence_and_collision_proof_ids() -> bool:
	print("--- Running TC-8.7: DEBT-03 Immigration Persistence, RNG Continuation & Collision-Proof IDs ---")
	var imm_mgr = world_instance.get("immigration_mgr")
	var tm: Node = root.get_node_or_null("TimeManager")
	if not _assert_true(imm_mgr != null and tm != null, "TC-8.7-DEPS-EXIST", "ImmigrationManager and TimeManager exist"):
		return false

	# 1. Validation tests for malformed immigration section before world mutation
	var base_save: Dictionary = SaveManager.serialize_world_state(world_instance)
	base_save["game_clock"]["current_day"] = 10

	var bad_imm_type: Dictionary = base_save.duplicate(true)
	bad_imm_type["immigration"] = "not_a_dict"
	_assert_eq(SaveManager.validate_save_data(bad_imm_type).get("valid", true), false, "TC-8.7-VAL-IMM-NOT-DICT", "Non-Dictionary immigration rejected")

	var bad_imm_future_day: Dictionary = base_save.duplicate(true)
	bad_imm_future_day["immigration"] = {"last_immigration_day": 15, "total_immigrants_admitted": 2, "next_citizen_index": 27}
	_assert_eq(SaveManager.validate_save_data(bad_imm_future_day).get("valid", true), false, "TC-8.7-VAL-IMM-FUTURE-DAY", "last_immigration_day (15) > current_day (10) rejected")

	var bad_imm_idx: Dictionary = base_save.duplicate(true)
	bad_imm_idx["immigration"] = {"last_immigration_day": 3, "total_immigrants_admitted": 2, "next_citizen_index": 0}
	_assert_eq(SaveManager.validate_save_data(bad_imm_idx).get("valid", true), false, "TC-8.7-VAL-IMM-ZERO-IDX", "next_citizen_index = 0 rejected")

	var bad_imm_rng: Dictionary = base_save.duplicate(true)
	bad_imm_rng["immigration"] = {"last_immigration_day": 3, "total_immigrants_admitted": 2, "next_citizen_index": 27, "rng_state": "invalid_rng"}
	_assert_eq(SaveManager.validate_save_data(bad_imm_rng).get("valid", true), false, "TC-8.7-VAL-IMM-BAD-RNG", "Non-numeric rng_state rejected")

	# Verify invalid immigration save is rejected before mutating live world
	tm.reset_time(6, 5, 1)
	var apply_bad_imm: Dictionary = SaveManager.apply_loaded_state_to_world(world_instance, bad_imm_future_day)
	_assert_eq(apply_bad_imm.get("success", true), false, "TC-8.7-APPLY-BAD-IMM-REJECTED", "Invalid immigration save rejected before world mutation")
	_assert_eq(tm.get("current_day"), 5, "TC-8.7-NO-MUTATION-ON-BAD-IMM", "Live TimeManager.current_day remained 5")

	# 2. Immigration round-trip persistence & deterministic RNG continuation
	tm.reset_time(6, 3, 1)
	imm_mgr._init(54321)
	var wave1: Dictionary = imm_mgr.evaluate_immigration(30, 24, 150, 85.0, 80.0, 3)
	_assert_true(wave1.get("allowed", false), "TC-8.7-WAVE1-ALLOWED", "Wave 1 on Day 3 admitted")
	var saved_after_wave1: Dictionary = SaveManager.serialize_world_state(world_instance)

	# Compute reference Wave 2 on Day 6 from an uninterrupted clone
	var ref_imm := ImmigrationManagerScript.new(54321)
	ref_imm.evaluate_immigration(30, 24, 150, 85.0, 80.0, 3)
	var ref_wave2: Dictionary = ref_imm.evaluate_immigration(34, 28, 150, 85.0, 80.0, 6)

	# Perturb live immigration_mgr completely
	imm_mgr._init(11111)
	imm_mgr.last_immigration_day = 0
	imm_mgr.total_immigrants_admitted = 0
	imm_mgr.next_citizen_index = 25

	# Restore from save and verify counters, schedule, and RNG stream continuation
	var apply_wave1: Dictionary = SaveManager.apply_loaded_state_to_world(world_instance, saved_after_wave1)
	_assert_true(apply_wave1.get("success", false), "TC-8.7-APPLY-WAVE1", "Saved state after Wave 1 restored")
	_assert_eq(imm_mgr.last_immigration_day, 3, "TC-8.7-RESTORED-LAST-DAY", "Restored last_immigration_day == 3")
	_assert_eq(imm_mgr.total_immigrants_admitted, wave1["count"], "TC-8.7-RESTORED-TOTAL", "Restored total_immigrants_admitted == 4")
	_assert_eq(imm_mgr.next_citizen_index, 25 + int(wave1["count"]), "TC-8.7-RESTORED-NEXT-IDX", "Restored next_citizen_index == 29")
	_assert_eq(imm_mgr.can_evaluate_today(3, 6), false, "TC-8.7-SCHEDULE-GUARD-DAY3", "Duplicate evaluation on Day 3 blocked after load")
	_assert_eq(imm_mgr.can_evaluate_today(6, 6), true, "TC-8.7-SCHEDULE-ALLOW-DAY6", "Evaluation on Day 6 allowed")

	var restored_wave2: Dictionary = imm_mgr.evaluate_immigration(34, 28, 150, 85.0, 80.0, 6)
	_assert_eq(restored_wave2["immigrants"], ref_wave2["immigrants"], "TC-8.7-RNG-STREAM-MATCH", "Restored RNG state produces identical Wave 2 names and IDs")

	# 3. High Citizen ID Collision-Proof Integration Test
	var high_id_save: Dictionary = base_save.duplicate(true)
	high_id_save["game_clock"]["current_day"] = 6
	# Inject a citizen with a high ID ("citizen_42") while saved next_citizen_index is stale (25)
	var high_cit: Dictionary = high_id_save["citizens"][0].duplicate(true)
	high_cit["id"] = "citizen_42"
	high_cit["name"] = "Nguyễn Văn Cao"
	high_id_save["citizens"].append(high_cit)
	high_id_save["immigration"] = {
		"last_immigration_day": 3,
		"total_immigrants_admitted": 1,
		"next_citizen_index": 25
	}

	var apply_high_id: Dictionary = SaveManager.apply_loaded_state_to_world(world_instance, high_id_save)
	_assert_true(apply_high_id.get("success", false), "TC-8.7-APPLY-HIGH-ID", "High citizen ID save applied")
	_assert_eq(imm_mgr.next_citizen_index, 43, "TC-8.7-BUMPED-NEXT-IDX", "next_citizen_index bumped to 43 (> citizen_42)")

	# Trigger and spawn an immigration wave on Day 9
	var wave_after_high: Dictionary = imm_mgr.evaluate_immigration(40, 25, 150, 85.0, 80.0, 9)
	_assert_true(wave_after_high.get("allowed", false), "TC-8.7-HIGH-WAVE-ALLOWED", "Wave after high-ID load allowed")
	_assert_eq(wave_after_high["immigrants"][0]["id"], "citizen_43", "TC-8.7-FIRST-NEW-ID-43", "First new immigrant after citizen_42 is citizen_43")
	world_instance.call("_spawn_immigrant_wave", wave_after_high["immigrants"])

	var seen_ids: Dictionary = {}
	var has_duplicate_id: bool = false
	for cit in world_instance.get("citizen_list"):
		var cid: String = String(cit.get("citizen_id"))
		if seen_ids.has(cid):
			has_duplicate_id = true
		seen_ids[cid] = true
	_assert_eq(has_duplicate_id, false, "TC-8.7-ZERO-ID-COLLISIONS", "All live citizen IDs in citizen_list are 100% unique")
	_assert_eq(imm_mgr.next_citizen_index, 43 + int(wave_after_high["count"]), "TC-8.7-NEXT-IDX-ADVANCED", "next_citizen_index advanced to 43 + wave_size")

	# Restore clean baseline state after TC-8.7
	SaveManager.apply_loaded_state_to_world(world_instance, base_save)

	print("  [PASS] TC-8.7 PASSED.\n")
	return _assertions_failed == 0

func _test_tc8_8_world_event_persistence_and_legacy_fallback() -> bool:
	print("--- Running TC-8.8: BUG-04 World Event Timed Modifiers, RNG, Cooldown & Legacy Save Persistence ---")
	var es = world_instance.get("event_system")
	var tm: Node = root.get_node_or_null("TimeManager")
	var rm: Node = root.get_node_or_null("ResourceManager")
	var wp_mgr = world_instance.get("workplace_mgr")
	var job_mgr = world_instance.get("job_mgr")
	var imm_mgr = world_instance.get("immigration_mgr")
	if not _assert_true(es != null and tm != null and rm != null and wp_mgr != null and job_mgr != null and imm_mgr != null, "TC-8.8-DEPS-EXIST", "WorldEventSystem, TimeManager, ResourceManager, WorkplaceManager, JobManager, ImmigrationManager exist"):
		return false

	# Reset immigration_mgr from TC-8.7's Day 9 test so last_immigration_day <= Day 5/6
	imm_mgr._init(12345)

	# 1. Validation tests for malformed world_events section BEFORE mutating live world
	var base_save: Dictionary = SaveManager.serialize_world_state(world_instance)
	base_save["game_clock"]["current_day"] = 10

	var bad_ev_type: Dictionary = base_save.duplicate(true)
	bad_ev_type["world_events"] = "not_a_dict"
	_assert_eq(SaveManager.validate_save_data(bad_ev_type).get("valid", true), false, "TC-8.8-VAL-EV-NOT-DICT", "Non-Dictionary world_events rejected")

	var bad_ev_future_day: Dictionary = base_save.duplicate(true)
	bad_ev_future_day["world_events"] = {"last_event_day": 14, "min_days_between_events": 4}
	_assert_eq(SaveManager.validate_save_data(bad_ev_future_day).get("valid", true), false, "TC-8.8-VAL-EV-FUTURE-DAY", "last_event_day (14) > current_day (10) rejected")

	var bad_ev_neg_farm: Dictionary = base_save.duplicate(true)
	bad_ev_neg_farm["world_events"] = {"last_event_day": 5, "active_farm_modifier_bonus": -0.5, "farm_bonus_expires_day": 7}
	_assert_eq(SaveManager.validate_save_data(bad_ev_neg_farm).get("valid", true), false, "TC-8.8-VAL-EV-NEG-FARM", "Negative active_farm_modifier_bonus rejected")

	var bad_ev_zero_fatigue: Dictionary = base_save.duplicate(true)
	bad_ev_zero_fatigue["world_events"] = {"last_event_day": 5, "active_fatigue_multiplier": 0.0, "fatigue_mult_expires_day": 7}
	_assert_eq(SaveManager.validate_save_data(bad_ev_zero_fatigue).get("valid", true), false, "TC-8.8-VAL-EV-ZERO-FATIGUE", "Non-positive active_fatigue_multiplier = 0.0 rejected")

	var bad_ev_rng: Dictionary = base_save.duplicate(true)
	bad_ev_rng["world_events"] = {"last_event_day": 5, "rng_state": "corrupt_rng"}
	_assert_eq(SaveManager.validate_save_data(bad_ev_rng).get("valid", true), false, "TC-8.8-VAL-EV-BAD-RNG", "Non-numeric world_events.rng_state rejected")

	tm.reset_time(6, 7, 1)
	var apply_bad_ev: Dictionary = SaveManager.apply_loaded_state_to_world(world_instance, bad_ev_future_day)
	_assert_eq(apply_bad_ev.get("success", true), false, "TC-8.8-APPLY-BAD-EV-REJECTED", "Invalid world_events save rejected before world mutation")
	_assert_eq(tm.get("current_day"), 7, "TC-8.8-NO-MUTATION-ON-BAD-EV", "Live TimeManager.current_day remained 7")

	# 2. Save while bountiful_harvest is active on Day 5 (expires Day 7) -> Load on Day 6 -> Verify:
	#    (a) bonus_food (+30) is NOT granted a second time on load,
	#    (b) farm modifier bonus (+0.5 -> 8 food/cycle) is still active on Day 6,
	#    (c) farm modifier bonus expires cleanly on Day 7 (back to 5 food/cycle).
	rm.reset_economy()
	tm.reset_time(8, 5, 1) # Day 5, Spring (season_mod = 1.0)
	es._init(12345)
	var food_before_bh: int = rm.get_available_stock("food")
	es.trigger_event_by_id("bountiful_harvest", 5, rm, null, world_instance.get("citizen_list"))
	var food_after_bh: int = rm.get_available_stock("food")
	_assert_eq(food_after_bh, food_before_bh + 30, "TC-8.8-BH-INITIAL-BONUS-FOOD", "bountiful_harvest granted +30 food once on Day 5")

	# Advance clock to Day 6 (day 2 of 2 of bountiful_harvest) and save
	tm.reset_time(9, 6, 1)
	es.update_daily_modifiers(6)
	var save_bh_day6: Dictionary = SaveManager.serialize_world_state(world_instance)

	# Compute reference next event on Day 9 (5 + 4 cooldown = Day 9) from an uninterrupted clone
	var ref_es := WorldEventSystemScript.new(12345)
	ref_es.deserialize(save_bh_day6["world_events"], 6)
	var ref_day9_ev: Dictionary = ref_es.check_and_trigger_event(9, null, null, [])

	# Perturb live world state (reset event_system and change food stock)
	es.reset_state()
	rm.add_resource("food", 100)
	_assert_eq(es.is_farm_bonus_active(6), false, "TC-8.8-BH-PERTURBED", "Live farm bonus cleared before load")

	# Load the Day 6 save
	var apply_bh_day6: Dictionary = SaveManager.apply_loaded_state_to_world(world_instance, save_bh_day6)
	_assert_true(apply_bh_day6.get("success", false), "TC-8.8-BH-LOAD-SUCCESS", "Day 6 save with active bountiful_harvest loaded")
	_assert_eq(rm.get_available_stock("food"), food_after_bh, "TC-8.8-NO-DOUBLE-BONUS-ON-LOAD", "Loading save did NOT grant +30 bonus_food a second time")
	_assert_eq(es.is_farm_bonus_active(6), true, "TC-8.8-BH-ACTIVE-AFTER-LOAD", "Farm bonus (+0.5) is active on Day 6 after load")
	_assert_eq(es._farm_bonus_expires_day, 7, "TC-8.8-BH-EXPIRES-DAY-7", "Restored farm_bonus_expires_day == 7")

	# Verify actual farmer citizen production on Day 6 after load yields 8 food (5.0 * 1.5 = 7.5 -> 8)
	var farmer_cit = null
	for cit in world_instance.get("citizen_list"):
		if cit.get("role") == "farmer":
			farmer_cit = cit
			break
	_assert_true(farmer_cit != null, "TC-8.8-FARMER-FOUND", "Found restored farmer citizen in WorldView")
	var farm_wp = wp_mgr.get_workplace("farm_starter")
	farm_wp.buffer_amount = 0
	var test_farm_job = job_mgr.create_job("farmer", Vector2i(35, 35), "Test Harvest", "farm_starter", 1.0, 1, true)
	test_farm_job.state = 2 # JobState.IN_PROGRESS
	test_farm_job.work_hours_done = 0.0
	farmer_cit.active_job = test_farm_job
	farmer_cit.current_state = 2 # State.WORKING
	farmer_cit._process_working(1.0)
	_assert_eq(farm_wp.buffer_amount, 8, "TC-8.8-FARM-PROD-DAY6-AFTER-LOAD", "Restored farmer produces 8 food on Day 6 while bountiful_harvest active")

	# Advance to Day 7 (expiration boundary): verify cooldown blocks new event AND farm bonus expires to 0.0 (5 food/cycle)
	tm.reset_time(9, 7, 1)
	var day7_ev: Dictionary = es.check_and_trigger_event(7, null, null, [])
	_assert_eq(day7_ev.is_empty(), true, "TC-8.8-COOLDOWN-BLOCKS-DAY7", "Cooldown (last_event_day=5, min=4) blocks event trigger on Day 7 after load")
	_assert_eq(es.is_farm_bonus_active(7), false, "TC-8.8-BH-EXPIRED-DAY7", "Farm bonus expired on Day 7 after load")
	farm_wp.buffer_amount = 0
	test_farm_job.state = 2
	test_farm_job.work_hours_done = 0.0
	farmer_cit.active_job = test_farm_job
	farmer_cit.current_state = 2
	farmer_cit._process_working(1.0)
	_assert_eq(farm_wp.buffer_amount, 5, "TC-8.8-FARM-PROD-DAY7-EXPIRED", "Restored farmer returns to baseline 5 food on Day 7 after expiration")

	# Verify RNG continuation on Day 9 (when cooldown expires) matches uninterrupted reference
	var restored_day9_ev: Dictionary = es.check_and_trigger_event(9, null, null, [])
	_assert_eq(restored_day9_ev.get("id", ""), ref_day9_ev.get("id", ""), "TC-8.8-RNG-MATCH-DAY9", "Restored RNG stream produces identical event on Day 9")

	# 3. Save while heatwave is active on Day 12 (expires Day 14) -> Load on Day 13 -> Verify fatigue 1.25x & expiration on Day 14
	tm.reset_time(8, 12, 1)
	es.trigger_event_by_id("heatwave", 12, rm, null, [])
	tm.reset_time(10, 13, 1)
	es.update_daily_modifiers(13)
	var save_hw_day13: Dictionary = SaveManager.serialize_world_state(world_instance)

	es.reset_state()
	_assert_eq(es.is_heatwave_active(13), false, "TC-8.8-HW-PERTURBED", "Live heatwave cleared before load")

	var apply_hw_day13: Dictionary = SaveManager.apply_loaded_state_to_world(world_instance, save_hw_day13)
	_assert_true(apply_hw_day13.get("success", false), "TC-8.8-HW-LOAD-SUCCESS", "Day 13 save with active heatwave loaded")
	_assert_eq(es.is_heatwave_active(13), true, "TC-8.8-HW-ACTIVE-AFTER-LOAD", "Heatwave (1.25x) is active on Day 13 after load")

	farmer_cit = world_instance.get("citizen_list")[0]
	farmer_cit.hunger = 10.0
	farmer_cit.fatigue = 10.0
	farmer_cit.current_state = 2 # State.WORKING
	farmer_cit._on_hour_passed(11, 13)
	_assert_true(is_equal_approx(farmer_cit.fatigue, 15.0), "TC-8.8-HW-FATIGUE-DAY13", "Citizen working fatigue increases by +5.0 (4.0 * 1.25) on Day 13 after load")

	# Advance to Day 14 (expiration boundary): heatwave expires, working fatigue gain reverts to +4.0
	farmer_cit.fatigue = 10.0
	farmer_cit._on_hour_passed(8, 14)
	_assert_eq(es.is_heatwave_active(14), false, "TC-8.8-HW-EXPIRED-DAY14", "Heatwave expired on Day 14 after load")
	_assert_true(is_equal_approx(farmer_cit.fatigue, 14.0), "TC-8.8-HW-FATIGUE-DAY14-EXPIRED", "Citizen working fatigue reverts to +4.0 on Day 14 after expiration")

	# 4. Legacy save lacking "world_events" section resets WorldEventSystem cleanly to baseline
	es.trigger_event_by_id("heatwave", 15, rm, null, [])
	_assert_eq(es.is_heatwave_active(15), true, "TC-8.8-PRE-LEGACY-HW-ACTIVE", "Heatwave active in memory before legacy load")
	var legacy_no_ev_save: Dictionary = base_save.duplicate(true)
	legacy_no_ev_save.erase("world_events")
	var apply_legacy_no_ev: Dictionary = SaveManager.apply_loaded_state_to_world(world_instance, legacy_no_ev_save)
	_assert_true(apply_legacy_no_ev.get("success", false), "TC-8.8-LEGACY-NO-EV-APPLY", "Legacy save without world_events loaded cleanly")
	_assert_eq(es.last_event_day, -99, "TC-8.8-LEGACY-RESET-LAST-DAY", "Legacy load reset last_event_day to -99")
	_assert_eq(es.is_farm_bonus_active(10), false, "TC-8.8-LEGACY-RESET-FARM", "Legacy load cleared stale farm bonus")
	_assert_eq(es.is_heatwave_active(15), false, "TC-8.8-LEGACY-RESET-HW", "Legacy load cleared stale heatwave multiplier")

	print("  [PASS] TC-8.8 PASSED.\n")
	return _assertions_failed == 0

func _test_tc8_9_package_1x_schema_validation() -> bool:
	print("--- Running TC-8.9: Package 1X Enemy Military & Field Siege Schema Validation ---")
	var base_save: Dictionary = SaveManager.serialize_world_state(world_instance)

	# 1. Invalid enemy_military type (not a dict)
	var bad1 = base_save.duplicate(true)
	bad1["enemy_military"] = "invalid_string"
	var res1 = SaveManager.validate_save_data(bad1)
	_assert_eq(res1["valid"], false, "TC-8.9-ENEMY-NON-DICT", "Rejected non-dict enemy_military")

	# 2. Invalid enemy coordinate
	var bad2 = base_save.duplicate(true)
	bad2["enemy_military"] = {
		"enemies": [
			{"unit_id": "e_bad_coord", "owning_faction_id": "rival_military", "current_cell": [-9, 99]}
		]
	}
	var res2 = SaveManager.validate_save_data(bad2)
	_assert_eq(res2["valid"], false, "TC-8.9-ENEMY-BAD-COORD", "Rejected out-of-bounds enemy coordinates")

	# 3. Duplicate enemy unit IDs
	var bad3 = base_save.duplicate(true)
	bad3["enemy_military"] = {
		"enemies": [
			{"unit_id": "dup_e", "owning_faction_id": "rival_military", "current_cell": [10, 10]},
			{"unit_id": "dup_e", "owning_faction_id": "rival_merchant", "current_cell": [11, 11]}
		]
	}
	var res3 = SaveManager.validate_save_data(bad3)
	_assert_eq(res3["valid"], false, "TC-8.9-ENEMY-DUP-ID", "Rejected duplicate enemy unit IDs")

	# 4. Enemy health > max_health
	var bad4 = base_save.duplicate(true)
	bad4["enemy_military"] = {
		"enemies": [
			{"unit_id": "e_overhp", "owning_faction_id": "rival_military", "current_cell": [10, 10], "health": 150.0, "max_health": 100.0}
		]
	}
	var res4 = SaveManager.validate_save_data(bad4)
	_assert_eq(res4["valid"], false, "TC-8.9-ENEMY-OVERHP", "Rejected enemy health exceeding max_health")

	# 5. Invalid field_siege type
	var bad5 = base_save.duplicate(true)
	bad5["field_siege"] = 12345
	var res5 = SaveManager.validate_save_data(bad5)
	_assert_eq(res5["valid"], false, "TC-8.9-SIEGE-NON-DICT", "Rejected non-dict field_siege")

	# 6. Duplicate objective IDs
	var bad6 = base_save.duplicate(true)
	bad6["field_siege"] = {
		"objectives": [
			{"objective_id": "dup_obj", "owning_faction_id": "fac_a", "current_cell": [10, 10]},
			{"objective_id": "dup_obj", "owning_faction_id": "fac_b", "current_cell": [12, 12]}
		]
	}
	var res6 = SaveManager.validate_save_data(bad6)
	_assert_eq(res6["valid"], false, "TC-8.9-OBJ-DUP-ID", "Rejected duplicate objective IDs")

	# 7. active_sieges referencing missing objective
	var bad7 = base_save.duplicate(true)
	bad7["field_siege"] = {
		"objectives": [
			{"objective_id": "obj_alpha", "owning_faction_id": "fac_a", "current_cell": [10, 10]}
		],
		"active_sieges": {
			"siege_1": {
				"siege_id": "siege_1",
				"faction_id": "fac_a",
				"objective_id": "missing_obj",
				"status": "active"
			}
		}
	}
	var res7 = SaveManager.validate_save_data(bad7)
	_assert_eq(res7["valid"], false, "TC-8.9-SIEGE-MISSING-OBJ", "Rejected active_siege referencing missing objective")

	# 8. active_sieges invalid status
	var bad8 = base_save.duplicate(true)
	bad8["field_siege"] = {
		"objectives": [
			{"objective_id": "obj_alpha", "owning_faction_id": "fac_a", "current_cell": [10, 10]}
		],
		"active_sieges": {
			"siege_1": {
				"siege_id": "siege_1",
				"faction_id": "fac_a",
				"objective_id": "obj_alpha",
				"status": "invalid_status_xyz"
			}
		}
	}
	var res8 = SaveManager.validate_save_data(bad8)
	_assert_eq(res8["valid"], false, "TC-8.9-SIEGE-INVALID-STATUS", "Rejected active_siege with invalid status")

	print("  [PASS] TC-8.9 PASSED.\n")
	return _assertions_failed == 0

func _test_tc8_10_package_1x_worldview_and_double_load() -> bool:
	print("--- Running TC-8.10: Package 1X WorldView End-to-End Persistence & Double Load ---")
	var base_save: Dictionary = SaveManager.serialize_world_state(world_instance)

	# 1. Verify default outposts exist in WorldView after startup
	var sm = world_instance.get("field_siege_mgr")
	_assert_true(sm != null, "TC-8.10-SM-EXISTS", "FieldSiegeManager exists on WorldView")
	var objs: Array = sm.get_all_objectives()
	_assert_true(objs.size() >= 3, "TC-8.10-DEFAULT-OBJECTIVES", "WorldView startup registered at least 3 default outposts")

	# 2. Trigger war declaration and verify force spawn
	var fm = world_instance.get("faction_mgr")
	_assert_true(fm != null, "TC-8.10-FM-EXISTS", "FactionManager exists on WorldView")
	fm.war_declared.emit("rival_military")

	var em = world_instance.get("enemy_military_mgr")
	_assert_true(em != null, "TC-8.10-EM-EXISTS", "EnemyMilitaryManager exists on WorldView")
	var enemies_before: int = em.get_enemies_by_faction("rival_military").size()
	_assert_true(enemies_before > 0, "TC-8.10-WAR-SPAWN", "War declaration spawned hostile forces for rival_military")

	# Idempotency check: emit war_declared again -> count must NOT increase
	fm.war_declared.emit("rival_military")
	var enemies_after_war2: int = em.get_enemies_by_faction("rival_military").size()
	_assert_eq(enemies_after_war2, enemies_before, "TC-8.10-WAR-IDEMPOTENT", "Repeated war declaration did NOT duplicate enemy forces")

	# 3. Serialize full state with enemies and objectives
	var save_with_war: Dictionary = SaveManager.serialize_world_state(world_instance)
	_assert_true(save_with_war.has("enemy_military"), "TC-8.10-SAVE-HAS-ENEMY", "Saved state contains enemy_military")
	_assert_true(save_with_war.has("field_siege"), "TC-8.10-SAVE-HAS-SIEGE", "Saved state contains field_siege")

	# 4. Load save once
	var load_res1 = SaveManager.apply_loaded_state_to_world(world_instance, save_with_war)
	if not load_res1.get("success", false):
		print("DEBUG LOAD ERROR: ", load_res1.get("error"))
	_assert_true(load_res1.get("success", false), "TC-8.10-LOAD-1-SUCCESS", "First restoration succeeded")
	var count_load1: int = em.get_enemies_by_faction("rival_military").size()
	_assert_eq(count_load1, enemies_before, "TC-8.10-LOAD-1-ENEMY-COUNT", "First restoration restored exact enemy count")

	# 5. Load save a second time (double load idempotency)
	var load_res2 = SaveManager.apply_loaded_state_to_world(world_instance, save_with_war)
	_assert_true(load_res2.get("success", false), "TC-8.10-LOAD-2-SUCCESS", "Second restoration succeeded (double-load)")
	var count_load2: int = em.get_enemies_by_faction("rival_military").size()
	_assert_eq(count_load2, enemies_before, "TC-8.10-LOAD-2-NO-DUPLICATES", "Double load did NOT duplicate enemy units")
	var obj_count_load2: int = sm.get_all_objectives().size()
	_assert_eq(obj_count_load2, objs.size(), "TC-8.10-LOAD-2-NO-DUP-OBJS", "Double load did NOT duplicate siege objectives")

	# 6. Legacy save without Package 1X sections loads safely and recreates default siege objectives without duplication (DEF-3)
	var legacy_save: Dictionary = base_save.duplicate(true)
	legacy_save.erase("enemy_military")
	legacy_save.erase("field_siege")
	var leg_res = SaveManager.apply_loaded_state_to_world(world_instance, legacy_save)
	_assert_true(leg_res.get("success", false), "TC-8.10-LEGACY-SUCCESS", "Legacy save without enemy_military/field_siege loads cleanly")
	var leg_objs: Array = sm.get_all_objectives()
	_assert_eq(leg_objs.size(), 3, "TC-8.10-LEGACY-DEFAULT-OBJS", "Legacy save without field_siege recreated 3 default outpost objectives")
	_assert_true(sm.get_objective("outpost_rival_military") != null and sm.get_objective("outpost_rival_merchant") != null and sm.get_objective("outpost_neutral_tribe") != null, "TC-8.10-LEGACY-OBJ-IDS", "All 3 default faction outposts exist after legacy load")
	var siege_container = world_instance.get_node_or_null("SiegeObjectivesContainer")
	if siege_container != null:
		_assert_eq(siege_container.get_child_count(), 3, "TC-8.10-LEGACY-NO-ACTOR-DUP", "SiegeObjectivesContainer has 3 child actors without duplication")
	var leg_res2 = SaveManager.apply_loaded_state_to_world(world_instance, legacy_save)
	_assert_true(leg_res2.get("success", false), "TC-8.10-LEGACY-RELOAD-SUCCESS", "Second legacy load succeeded")
	_assert_eq(sm.get_all_objectives().size(), 3, "TC-8.10-LEGACY-RELOAD-NO-DUP", "Repeated legacy load did not duplicate siege objectives")
	if siege_container != null:
		_assert_eq(siege_container.get_child_count(), 3, "TC-8.10-LEGACY-RELOAD-ACTORS", "Repeated legacy load did not duplicate objective actors")

	print("  [PASS] TC-8.10 PASSED.\n")
	return _assertions_failed == 0

func _test_tc8_11_hardening_gates_combat_transactional_and_caravan() -> bool:
	print("--- Running TC-8.11: Pre-Package-2A Hardening Gates (Gate A, Gate B, Gate E, Gate F) ---")
	var TacticalUnitScript = preload("res://scripts/military/tactical_unit.gd")
	var EnemyTacticalUnitScript = preload("res://scripts/military/enemy_tactical_unit.gd")

	# -------------------------------------------------------------------------
	# GATE A: Active Combat Save/Load, Target Resolution Order, & Transactional Load (CANON-001 / WEAK-TEST-01)
	# -------------------------------------------------------------------------
	var army_mgr = world_instance.get("player_army_mgr")
	var tac_mgr = world_instance.get("tactical_military_mgr")
	var em_mgr = world_instance.get("enemy_military_mgr")
	var siege_mgr = world_instance.get("field_siege_mgr")
	var fm = world_instance.get("faction_mgr")
	var nav = world_instance.get("nav")

	# Spawn 2 player units and enemy units, and configure active combat against both an enemy unit and a siege objective
	army_mgr.soldier_count = 2
	tac_mgr.sync_with_player_army()
	var p_units: Array = tac_mgr.get_all_units()
	_assert_eq(p_units.size(), 2, "GATE-A.1", "2 player tactical units spawned")

	var mil_fac = fm.get_faction("rival_military")
	if mil_fac:
		mil_fac.is_at_war = true
	fm.war_declared.emit("rival_military")
	var e_units: Array = em_mgr.get_enemies_by_faction("rival_military")
	_assert_true(e_units.size() > 0, "GATE-A.2", "Hostile enemy units spawned for rival_military")

	var target_enemy = e_units[0]
	var target_obj = siege_mgr.get_objective("outpost_rival_military")
	_assert_true(target_obj != null, "GATE-A.3", "Siege objective outpost_rival_military exists")

	# Player unit 0 engages enemy unit in melee range (empty pursuit path)
	p_units[0].current_cell = Vector2i(20, 20)
	p_units[0].target_cell = Vector2i(20, 20)
	target_enemy.current_cell = Vector2i(20, 21)
	target_enemy.target_cell = Vector2i(20, 21)
	p_units[0].order_attack(target_enemy)
	p_units[0].current_path.clear()

	# Player unit 1 pursues siege objective with a valid path ending at target_cell
	p_units[1].current_cell = target_obj.current_cell + Vector2i(2, 0)
	p_units[1].order_attack(target_obj)
	var p1_path: Array[Vector2i] = [target_obj.current_cell + Vector2i(1, 0), target_obj.current_cell]
	p_units[1].current_path = p1_path
	p_units[1].target_cell = target_obj.current_cell

	# Enemy unit attacks player unit 0
	target_enemy.order_attack(p_units[0])
	target_enemy.current_path.clear()
	target_enemy.target_cell = target_enemy.current_cell
	target_enemy.ai_state = EnemyTacticalUnitScript.AIState.ATTACK

	army_mgr.sync_state_from_tactical()

	var combat_save: Dictionary = SaveManager.serialize_world_state(world_instance)
	var val_combat = SaveManager.validate_save_data(combat_save)
	if not val_combat.get("valid", false):
		print("DEBUG GATE-A VALIDATION ERROR: ", val_combat.get("error"))
	_assert_true(val_combat.get("valid", false), "GATE-A.4", "Active combat save passes validate_save_data")

	var apply_combat = SaveManager.apply_loaded_state_to_world(world_instance, combat_save)
	if not apply_combat.get("success", false):
		print("DEBUG GATE-A APPLY ERROR: ", apply_combat.get("error"))
	_assert_true(apply_combat.get("success", false), "GATE-A.5", "Active combat save restored cleanly via apply_loaded_state_to_world")

	var restored_u0 = tac_mgr.get_unit(p_units[0].unit_id)
	var restored_u1 = tac_mgr.get_unit(p_units[1].unit_id)
	var restored_enemy = em_mgr.get_enemy(target_enemy.unit_id)
	_assert_true(restored_u0 != null and restored_u0.order_state == TacticalUnitScript.OrderState.ATTACKING, "GATE-A.6", "Player unit 0 restored in ATTACKING state")
	_assert_true(restored_u0 != null and restored_u0.target_actor != null and restored_u0.target_actor.unit_id == target_enemy.unit_id, "GATE-A.7", "Player unit 0 target_actor resolved to restored enemy unit")
	_assert_true(restored_u1 != null and restored_u1.order_state == TacticalUnitScript.OrderState.ATTACKING, "GATE-A.8", "Player unit 1 restored in ATTACKING state")
	_assert_true(restored_u1 != null and restored_u1.target_actor != null and restored_u1.target_actor.objective_id == "outpost_rival_military", "GATE-A.9", "Player unit 1 target_actor resolved to restored SiegeObjective")
	_assert_true(restored_enemy != null and restored_enemy.order_state == TacticalUnitScript.OrderState.ATTACKING and restored_enemy.target_actor != null, "GATE-A.10", "Enemy unit target_actor resolved to restored player unit")

	# Missing target on load -> graceful fallback to IDLE with empty path
	var missing_tgt_save: Dictionary = combat_save.duplicate(true)
	missing_tgt_save["tactical_military"]["units"][1]["target_actor_id"] = "deleted_target_999"
	var apply_missing = SaveManager.apply_loaded_state_to_world(world_instance, missing_tgt_save)
	_assert_true(apply_missing.get("success", false), "GATE-A.11", "Save with missing combat target loads cleanly without error")
	var fallback_u1 = tac_mgr.get_unit(p_units[1].unit_id)
	_assert_true(fallback_u1 != null and fallback_u1.order_state == TacticalUnitScript.OrderState.IDLE, "GATE-A.12", "Unit with missing target transitioned gracefully to IDLE")
	_assert_true(fallback_u1 != null and fallback_u1.target_actor == null and fallback_u1.target_actor_id == "" and fallback_u1.current_path.is_empty(), "GATE-A.13", "Unit with missing target cleared pursuit path and target_actor_id")

	# Enemy path validation rules in validate_save_data()
	var bad_enemy_moving: Dictionary = combat_save.duplicate(true)
	bad_enemy_moving["enemy_military"]["enemies"][0]["order_state"] = "moving"
	bad_enemy_moving["enemy_military"]["enemies"][0]["current_path"] = []
	_assert_eq(SaveManager.validate_save_data(bad_enemy_moving).get("valid", true), false, "GATE-A.14", "Rejected enemy unit with order_state=moving and empty current_path")

	var bad_enemy_idle_path: Dictionary = combat_save.duplicate(true)
	bad_enemy_idle_path["enemy_military"]["enemies"][0]["order_state"] = "idle"
	bad_enemy_idle_path["enemy_military"]["enemies"][0]["current_path"] = [[20, 22]]
	_assert_eq(SaveManager.validate_save_data(bad_enemy_idle_path).get("valid", true), false, "GATE-A.15", "Rejected enemy unit with order_state=idle and non-empty current_path")

	# Transactional / preflight safety in apply_loaded_state_to_world() (DEF-2)
	var tm: Node = root.get_node_or_null("TimeManager")
	var rm: Node = root.get_node_or_null("ResourceManager")
	tm.reset_time(10, 7, 1)
	rm.reset_economy()
	var pre_wid: String = String(world_instance.get("world_id"))
	var pre_day: int = int(tm.get("current_day"))
	var pre_hour: int = int(tm.get("current_hour"))
	var pre_gold: int = int(rm.call("get_available_stock", "gold"))
	var pre_food: int = int(rm.call("get_available_stock", "food"))
	var pre_cit_count: int = (world_instance.get("citizen_list") as Array).size()
	var pre_soldiers: int = army_mgr.get_army_count()
	var pre_tac_count: int = tac_mgr.get_unit_count()
	var pre_enemy_count: int = em_mgr.get_enemy_count()

	var bad_late_payload: Dictionary = combat_save.duplicate(true)
	bad_late_payload["metadata"]["world_id"] = "world_corrupt_late_999_999_999"
	bad_late_payload["game_clock"]["current_day"] = 99
	bad_late_payload["game_clock"]["current_hour"] = 22
	bad_late_payload["resources"]["stock"]["gold"] = 9999
	bad_late_payload["resources"]["stock"]["food"] = 8888
	bad_late_payload["enemy_military"]["enemies"][0]["order_state"] = "idle"
	bad_late_payload["enemy_military"]["enemies"][0]["current_path"] = null

	var schema_pass_res: Dictionary = SaveManager.validate_save_data(bad_late_payload)
	_assert_eq(schema_pass_res.get("valid", false), true, "GATE-A.16a", "Payload passes SaveManager.validate_save_data() schema check (Step 0a)")
	var bad_apply_res: Dictionary = SaveManager.apply_loaded_state_to_world(world_instance, bad_late_payload)
	_assert_eq(bad_apply_res.get("success", true), false, "GATE-A.16", "apply_loaded_state_to_world rejected payload during isolated preflight subsystem deserialize() probe (Step 0b)")
	_assert_eq(String(world_instance.get("world_id")), pre_wid, "GATE-A.17", "Live world_id untouched on failed load")
	_assert_eq(int(tm.get("current_day")), pre_day, "GATE-A.18", "Live TimeManager.current_day untouched on failed load")
	_assert_eq(int(tm.get("current_hour")), pre_hour, "GATE-A.18b", "Live TimeManager.current_hour untouched on failed load")
	_assert_eq(int(rm.call("get_available_stock", "gold")), pre_gold, "GATE-A.19", "Live ResourceManager gold untouched on failed load")
	_assert_eq(int(rm.call("get_available_stock", "food")), pre_food, "GATE-A.19b", "Live ResourceManager food untouched on failed load")
	_assert_eq((world_instance.get("citizen_list") as Array).size(), pre_cit_count, "GATE-A.20", "Live citizen count untouched on failed load")
	_assert_eq(army_mgr.get_army_count(), pre_soldiers, "GATE-A.20b", "Live PlayerArmyManager soldier_count untouched on failed load")
	_assert_eq(tac_mgr.get_unit_count(), pre_tac_count, "GATE-A.20c", "Live TacticalMilitaryManager unit count untouched on failed load")
	_assert_eq(em_mgr.get_enemy_count(), pre_enemy_count, "GATE-A.20d", "Live EnemyMilitaryManager unit count untouched on failed load")

	# -------------------------------------------------------------------------
	# GATE B: Victory/Collapse State, Active Caravan, Fog of War, Midnight Order, & New-World Economy Reset
	# -------------------------------------------------------------------------
	# 1. Victory & Collapse state persistence (CANON-006)
	var vic_mgr = world_instance.get("victory_mgr")
	vic_mgr.townhall_ruin_hours = 36.5
	vic_mgr.anarchy_hours = 18.0
	vic_mgr.primary_collapse_reason = "Tòa Thị Chính bị phá hủy"
	vic_mgr.has_continued_after_victory = true
	var custom_events: Array[String] = ["Ngày 4: Đại Thắng Mùa Xuân"]
	vic_mgr.major_events = custom_events

	# 2. Active Trade Caravan persistence & faction opinion pricing (CANON-007 & CANON-010)
	var caravan = TradeCaravan.generate_caravan(12345, 3, "rival_merchant")
	world_instance.set("active_caravan", caravan)
	var merch_fac_b = fm.get_faction("rival_merchant")
	if merch_fac_b:
		merch_fac_b.opinion = 100.0
	var hud = world_instance.get("hud")
	if hud and hud.has_method("_get_caravan_faction_opinion"):
		var op_val: float = float(hud.call("_get_caravan_faction_opinion", caravan))
		_assert_eq(op_val, 100.0, "GATE-B.1", "HUD queries actual rival_merchant faction opinion (100.0) for caravan pricing")
	var initial_caravan_food: int = int(caravan.inventory.get("food", 0))
	rm.add_resource("gold", 500)
	var buy_res: Dictionary = caravan.buy_from_caravan("food", 5, rm, 100.0)
	_assert_true(buy_res.get("success", false), "GATE-B.2", "Purchased 5 food from active caravan with opinion discount")
	var post_buy_food: int = int(caravan.inventory.get("food", 0))
	var post_buy_gold: int = int(caravan.gold)
	_assert_eq(post_buy_food, initial_caravan_food - 5, "GATE-B.3", "Caravan inventory decremented by 5")

	# 3. Fog of War active vision vs explored degradation (CANON-011)
	var fow = world_instance.get("fog_of_war")
	fow.reveal_circle(Vector2i(60, 60), 2)
	_assert_eq(fow.get_state(Vector2i(60, 60)), FogOfWar.State.VISIBLE, "GATE-B.4", "Far corner (60,60) initially marked VISIBLE")
	world_instance.call("refresh_world_vision")
	_assert_eq(fow.get_state(Vector2i(60, 60)), FogOfWar.State.EXPLORED, "GATE-B.5", "Unobserved cell (60,60) degraded from VISIBLE to EXPLORED on vision refresh")
	_assert_eq(fow.get_state(Vector2i(32, 32)), FogOfWar.State.VISIBLE, "GATE-B.6", "Settlement center (32,32) remains VISIBLE")

	# Save and reload -> verify Victory fields, Active Caravan, and Fog of War states
	var gate_b_save: Dictionary = SaveManager.serialize_world_state(world_instance)
	vic_mgr.townhall_ruin_hours = 0.0
	vic_mgr.anarchy_hours = 0.0
	vic_mgr.primary_collapse_reason = ""
	vic_mgr.has_continued_after_victory = false
	var empty_events: Array[String] = []
	vic_mgr.major_events = empty_events
	world_instance.set("active_caravan", null)

	var apply_b = SaveManager.apply_loaded_state_to_world(world_instance, gate_b_save)
	_assert_true(apply_b.get("success", false), "GATE-B.7", "Gate B save restored cleanly")
	_assert_eq(vic_mgr.townhall_ruin_hours, 36.5, "GATE-B.8", "Restored townhall_ruin_hours == 36.5")
	_assert_eq(vic_mgr.anarchy_hours, 18.0, "GATE-B.9", "Restored anarchy_hours == 18.0")
	_assert_eq(vic_mgr.primary_collapse_reason, "Tòa Thị Chính bị phá hủy", "GATE-B.10", "Restored primary_collapse_reason")
	_assert_eq(vic_mgr.has_continued_after_victory, true, "GATE-B.11", "Restored has_continued_after_victory == true")
	_assert_eq(vic_mgr.major_events.size(), 1, "GATE-B.12", "Restored major_events array")

	var restored_caravan = world_instance.get("active_caravan")
	_assert_true(restored_caravan != null and bool(restored_caravan.get("is_active")), "GATE-B.13", "Active caravan restored across save/load")
	if restored_caravan != null:
		_assert_eq(int(restored_caravan.inventory.get("food", -1)), post_buy_food, "GATE-B.14", "Restored caravan preserved modified food inventory")
		_assert_eq(int(restored_caravan.gold), post_buy_gold, "GATE-B.15", "Restored caravan preserved modified gold balance")
	_assert_eq(fow.get_state(Vector2i(60, 60)), FogOfWar.State.EXPLORED, "GATE-B.16", "Saved explored cell (60,60) restored as EXPLORED (not VISIBLE)")

	# 4. Midnight hour-0 signal ordering before daily autosave (CANON-008)
	var signal_order: Array[String] = []
	var on_hr = func(h: int, d: int):
		signal_order.append("hour:%d:%d" % [h, d])
	var on_day = func(d: int, _s: String, _y: int):
		signal_order.append("day:%d" % d)
	tm.hour_passed.connect(on_hr)
	tm.day_passed.connect(on_day)
	tm.reset_time(23, 2, 1)
	tm.call("_advance_one_hour")
	tm.hour_passed.disconnect(on_hr)
	tm.day_passed.disconnect(on_day)
	_assert_true(signal_order.size() >= 2 and signal_order[0] == "hour:0:3" and signal_order[1] == "day:3", "GATE-B.17", "Midnight rollover emits hour_passed(0, 3) BEFORE day_passed(3): %s" % str(signal_order))

	# 5. New-World Economy Reset in WorldView._generate_and_build_world() (CANON-005)
	rm.consume_resource("gold", rm.get_available_stock("gold"))
	rm.reserve_cost({"wood": 25})
	rm.set("_is_starving", true)
	_assert_eq(rm.get_available_stock("gold"), 0, "GATE-B.18", "Mutated gold to 0 before new world generation")
	world_instance.call("_generate_and_build_world")
	_assert_eq(rm.get_available_stock("gold"), EconomyConfig.STARTING_RESOURCES[EconomyConfig.RES_GOLD], "GATE-B.19", "New world generation reset gold to starting value (200)")
	_assert_eq(rm.get_reserved_stock("wood"), 0, "GATE-B.20", "New world generation cleared resource reservations")
	_assert_eq(rm.is_starving(), false, "GATE-B.21", "New world generation cleared starvation flag")

	print("  [PASS] TC-8.11 PASSED.\n")
	return _assertions_failed == 0
