extends SceneTree
## Headless Test Suite for Phase 8: Robust Save/Load & Persistence Hardening.
## Validates TC-8.1 (Save -> Load -> Save Equivalence) and TC-8.2 (Corruption Handling & Backup Recovery).

const SaveManager = preload("res://scripts/persistence/save_manager.gd")

const SAVE_PATH_1: String = "user://saves/test_roundtrip_1.json"
const SAVE_PATH_2: String = "user://saves/test_roundtrip_2.json"
const TEST_CORRUPT_PATH: String = "user://saves/test_corrupt_save.json"
const TEST_BAK_PATH: String = "user://saves/test_backup_restore.json"

var frame_count: int = 0
var world_instance: Node = null

func _init() -> void:
	print("\n========================================================")
	print("  TEST SUITE: Phase 8 — Robust Save/Load & Persistence")
	print("========================================================\n")
	
	SaveManager.ensure_save_directory()
	
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
		
		print("\n--------------------------------------------------------")
		if pass_tc1 and pass_tc2 and pass_tc3:
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

	# Verify save file exists on disk
	if not FileAccess.file_exists(SaveManager.DEFAULT_SAVE_PATH):
		print("  [FAIL] Default save file does not exist on disk!")
		return false
	print("  [PASS] Save file confirmed on disk at %s" % SaveManager.DEFAULT_SAVE_PATH)

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
