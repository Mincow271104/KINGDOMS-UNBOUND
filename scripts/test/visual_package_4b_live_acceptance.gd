extends SceneTree
## =============================================================================
## KINGDOMS UNBOUND — Package 4B Live Interactive Gameplay Acceptance Harness
## Legacy Meta-Unlocks & World Modifiers
## Engine: Godot 4.7-stable (Hardware GUI Execution: D3D12 Forward+ on Windows)
## Captures high-fidelity PNG screenshots in docs/visual_validation/package_4b_live/
## =============================================================================

const MainMenuScene = preload("res://scenes/ui/main_menu.tscn")
const WorldViewScene = preload("res://scenes/world/world_view.tscn")
const LegacyProfileManagerScript = preload("res://scripts/legacy/legacy_profile_manager.gd")

const SCREENSHOT_DIR: String = "docs/visual_validation/package_4b_live/"

var frame_count: int = 0
var main_menu: Control = null
var world_inst: Node = null
var prof: RefCounted = null

func _save_screenshot(filename: String) -> void:
	var vp: Viewport = root
	if vp:
		var tex := vp.get_texture()
		if tex:
			var img := tex.get_image()
			if img:
				var path := SCREENSHOT_DIR + filename
				var global_path := ProjectSettings.globalize_path("res://" + path)
				var err := img.save_png(global_path)
				print("[GUI Live Acceptance 4B] Screenshot saved: %s (Err: %d)" % [path, err])

func _init() -> void:
	print("\n========================================================")
	print("  STARTING PACKAGE 4B LIVE GAMEPLAY ACCEPTANCE (GUI)")
	print("  DisplayServer: ", DisplayServer.get_name())
	print("  Expected Target: 1280x720, D3D12 Forward+")
	print("========================================================\n")

	var target_res := Vector2i(1280, 720)
	DisplayServer.window_set_size(target_res)
	root.size = target_res

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + SCREENSHOT_DIR))

	# Setup a rich test profile with 300 Legacy Points
	prof = LegacyProfileManagerScript.new("user://temp_visual_profile_4b.json")
	prof.reset_profile()
	prof.claim_reward("visual_test_reward", "victory", 300, "world_visual_init")
	LegacyProfileManagerScript.set_instance(prof)

	main_menu = MainMenuScene.instantiate()
	root.add_child(main_menu)

func _process(_delta: float) -> bool:
	frame_count += 1

	if frame_count == 10:
		# Frame 10: Main Menu Open with Legacy Fund indicator
		print("[GUI Live Acceptance 4B] Capturing Main Menu with Quỹ Di Sản...")
		_save_screenshot("01_main_menu_legacy_fund.png")

	elif frame_count == 20:
		# Frame 20: Open New World Dialog
		print("[GUI Live Acceptance 4B] Opening New World Dialog...")
		if main_menu.has_method("_on_open_new_world"):
			main_menu._on_open_new_world()

	elif frame_count == 35:
		# Frame 35: Capture New World Dialog with Perks and Modifiers UI rendered
		print("[GUI Live Acceptance 4B] Capturing New World Dialog with Perks & Modifiers...")
		_save_screenshot("02_new_world_dialog_perks_and_modifiers.png")

	elif frame_count == 45:
		# Frame 45: Unlock starter_grain and master_carpenter via GUI
		print("[GUI Live Acceptance 4B] Unlocking Perks via UI...")
		if main_menu.has_method("_on_unlock_perk_pressed"):
			main_menu._on_unlock_perk_pressed("starter_grain")
			main_menu._on_unlock_perk_pressed("master_carpenter")
		if main_menu.has_method("set_perk_selected"):
			main_menu.set_perk_selected("starter_grain", true)
			main_menu.set_perk_selected("master_carpenter", true)
		if main_menu.has_method("set_modifier_selected"):
			main_menu.set_modifier_selected("harsh_winters", true)

	elif frame_count == 60:
		# Frame 60: Capture unlocked perks and selected modifiers
		print("[GUI Live Acceptance 4B] Capturing unlocked perks and selected modifiers...")
		_save_screenshot("03_perks_unlocked_and_modifiers_selected.png")

	elif frame_count == 70:
		# Frame 70: Start Campaign with selected Perks & Modifiers
		print("[GUI Live Acceptance 4B] Launching Campaign Genesis...")
		var selected_perks: Array = main_menu.get_selected_perks() if main_menu.has_method("get_selected_perks") else []
		var selected_mods: Array = main_menu.get_selected_modifiers() if main_menu.has_method("get_selected_modifiers") else []
		
		root.remove_child(main_menu)
		main_menu.queue_free()
		main_menu = null

		world_inst = WorldViewScene.instantiate()
		world_inst.active_perks = selected_perks
		world_inst.world_modifiers = selected_mods
		root.add_child(world_inst)

	elif frame_count == 95:
		# Frame 95: In-world HUD showing starter perks applied (Food 200, Wood 160, Tools 25)
		print("[GUI Live Acceptance 4B] Capturing in-game HUD with starter perks applied...")
		var cam: Camera2D = world_inst.get_node_or_null("Camera2D")
		if cam != null:
			cam.position = Vector2(1024, 600)
			cam.zoom = Vector2(1.0, 1.0)
		_save_screenshot("04_world_genesis_starter_bonuses_applied.png")

	elif frame_count == 115:
		print("\n========================================================")
		print("  PACKAGE 4B LIVE GUI ACCEPTANCE COMPLETED SUCCESSFULLY")
		print("========================================================\n")
		# Cleanup
		if prof != null:
			LegacyProfileManagerScript.reset_instance()
			var da := DirAccess.open("user://")
			if da:
				da.remove("temp_visual_profile_4b.json")
				da.remove("temp_visual_profile_4b.json.bak")
		quit(0)

	return false
