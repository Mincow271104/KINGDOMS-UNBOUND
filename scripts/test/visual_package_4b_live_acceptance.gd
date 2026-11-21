extends SceneTree
## =============================================================================
## KINGDOMS UNBOUND — Package 4B Final Gate Visual Acceptance Harness
## Legacy Reward Lifecycle & Cross-Campaign Progression
## Engine: Godot 4.7-stable (Hardware GUI Execution: D3D12 Forward+ on Windows)
## Captures high-fidelity PNG screenshots in docs/visual_validation/package_4b_live/
## =============================================================================

const MainMenuScene = preload("res://scenes/ui/main_menu.tscn")
const WorldViewScene = preload("res://scenes/world/world_view.tscn")
const LegacyProfileManagerScript = preload("res://scripts/legacy/legacy_profile_manager.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const VictoryManagerScript = preload("res://scripts/core/victory_manager.gd")

const SCREENSHOT_DIR: String = "docs/visual_validation/package_4b_live/"

var frame_count: int = 0
var main_menu: Control = null
var world_inst: Node = null
var hud: CanvasLayer = null
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
	print("  STARTING PACKAGE 4B FINAL GATE GUI ACCEPTANCE")
	print("  DisplayServer: ", DisplayServer.get_name())
	print("  Expected Target: 1280x720, D3D12 Forward+")
	print("========================================================\n")

	var target_res := Vector2i(1280, 720)
	DisplayServer.window_set_size(target_res)
	root.size = target_res

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + SCREENSHOT_DIR))

	# Clean profile starting at 0 balance
	prof = LegacyProfileManagerScript.new("user://temp_visual_profile_4b.json")
	prof.reset_profile()
	LegacyProfileManagerScript.set_instance(prof)

	# Instantiate Campaign 1 in WorldView
	world_inst = WorldViewScene.instantiate()
	world_inst.world_seed = 9001
	root.add_child(world_inst)

func _process(_delta: float) -> bool:
	frame_count += 1

	if frame_count == 10:
		# Frame 10: Configure Campaign 1 for Prosperity Victory
		hud = world_inst.get_node_or_null("HUD")
		var rm: Node = root.get_node_or_null("ResourceManager")
		if rm != null:
			rm.call("reset_economy")
			rm.call("add_resource", "gold", 3300) # 3500 total gold (2500 surplus -> +25 LP)
			rm.call("add_resource", "food", 350) # 500 total food
		
		# Persist to establish valid world_id
		SaveManagerScript.save_to_file(world_inst)

		var vic_mgr = world_inst.get("victory_mgr")
		if vic_mgr != null:
			vic_mgr.set("is_victory_achieved", true)
			vic_mgr.set("legacy_points_earned", 100)
			var report: Dictionary = vic_mgr.generate_summary_report("VICTORY", 30, 500, 3500, 85.0, 80.0, 3, 10)
			if hud != null and hud.has_method("show_victory_panel"):
				hud.show_victory_panel(report)

	elif frame_count == 25:
		# Screenshot 1: Victory completion and reward breakdown
		print("[GUI Live Acceptance 4B] Capturing 01_victory_completion_and_reward.png...")
		_save_screenshot("01_victory_completion_and_reward.png")

	elif frame_count == 35:
		# Frame 35: Hide victory panel and trigger Collapse Panel demonstration
		if hud != null:
			var vic_panel = hud.get_node_or_null("VictoryPanel")
			if vic_panel: vic_panel.visible = false
			var col_report: Dictionary = {
				"outcome": "COLLAPSE",
				"days_survived": 12,
				"hours_survived": 8,
				"peak_population": 32,
				"primary_cause": "Tuyệt chủng: Toàn bộ cư dân đã qua đời vì nạn đói hoặc kiệt sức.",
				"buildings_count": 14,
				"technologies_unlocked": 4,
				"legacy_points": 0,
				"legacy_claimed": false
			}
			if hud.has_method("show_collapse_panel"):
				hud.show_collapse_panel(col_report)

	elif frame_count == 50:
		# Screenshot 2: Collapse completion and reward policy
		print("[GUI Live Acceptance 4B] Capturing 02_collapse_completion_and_reward.png...")
		_save_screenshot("02_collapse_completion_and_reward.png")

	elif frame_count == 60:
		# Frame 60: Settle Victory Reward (+125 LP) and re-open settled Victory Panel
		if hud != null:
			var col_panel = hud.get_node_or_null("CollapsePanel")
			if col_panel: col_panel.visible = false
			if hud.has_method("_on_claim_victory_btn_pressed"):
				hud._on_claim_victory_btn_pressed()
			var vic_panel = hud.get_node_or_null("VictoryPanel")
			if vic_panel: vic_panel.visible = true

	elif frame_count == 75:
		# Screenshot 3: Reopened completed campaign showing reward already processed
		print("[GUI Live Acceptance 4B] Capturing 03_reopened_completed_campaign_reward_settled.png...")
		_save_screenshot("03_reopened_completed_campaign_reward_settled.png")

	elif frame_count == 85:
		# Frame 85: Transition to Main Menu with persistent updated Legacy balance
		root.remove_child(world_inst)
		world_inst.queue_free()
		world_inst = null

		main_menu = MainMenuScene.instantiate()
		root.add_child(main_menu)
		if main_menu.has_method("_on_open_new_world"):
			main_menu._on_open_new_world()

	elif frame_count == 100:
		# Screenshot 4: Main Menu showing persistent updated balance (125 LP) & New World Panel
		print("[GUI Live Acceptance 4B] Capturing 04_main_menu_persistent_updated_balance.png...")
		_save_screenshot("04_main_menu_persistent_updated_balance.png")

	elif frame_count == 110:
		# Frame 110: Unlock starter_grain (50 LP) in UI and start Campaign 2
		if main_menu != null:
			if main_menu.has_method("_on_unlock_perk_pressed"):
				main_menu._on_unlock_perk_pressed("starter_grain")
			if main_menu.has_method("set_perk_selected"):
				main_menu.set_perk_selected("starter_grain", true)

			var selected_perks: Array = main_menu.get_selected_perks() if main_menu.has_method("get_selected_perks") else []
			var selected_mods: Array = main_menu.get_selected_modifiers() if main_menu.has_method("get_selected_modifiers") else []

			root.remove_child(main_menu)
			main_menu.queue_free()
			main_menu = null

			world_inst = WorldViewScene.instantiate()
			world_inst.world_seed = 9002
			world_inst.active_perks = selected_perks
			world_inst.world_modifiers = selected_mods
			root.add_child(world_inst)

	elif frame_count == 130:
		# Screenshot 5: In-world HUD with starter_grain applied (Food: 200)
		print("[GUI Live Acceptance 4B] Capturing 05_new_campaign_using_unlocked_perks.png...")
		var cam: Camera2D = world_inst.get_node_or_null("Camera2D")
		if cam != null:
			cam.position = Vector2(1024, 600)
			cam.zoom = Vector2(1.0, 1.0)
		_save_screenshot("05_new_campaign_using_unlocked_perks.png")

	elif frame_count == 145:
		print("\n========================================================")
		print("  PACKAGE 4B FINAL GATE GUI ACCEPTANCE COMPLETED")
		print("========================================================\n")
		if prof != null:
			LegacyProfileManagerScript.reset_instance()
			var da := DirAccess.open("user://")
			if da:
				da.remove("temp_visual_profile_4b.json")
				da.remove("temp_visual_profile_4b.json.bak")
		quit(0)

	return false
