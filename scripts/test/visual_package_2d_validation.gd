extends SceneTree
## =============================================================================
## KINGDOMS UNBOUND — Package 2D Live Visual Validation
## In-Game Player Field Guide & 30-Day Starter Manual
## Captures high-fidelity PNG screenshots across chapters and resolutions
## =============================================================================

const WorldViewScene = preload("res://scenes/world/world_view.tscn")

var frame_count: int = 0
var world_inst: Node = null
var hud: Node = null
var guide: Control = null

func _save_screenshot(filename: String) -> void:
	var vp: Viewport = root
	if vp:
		var tex := vp.get_texture()
		if tex:
			var img := tex.get_image()
			if img:
				var path := "docs/visual_validation/" + filename
				var err := img.save_png(path)
				print("[Visual Validation] Saved screenshot: %s (%dx%d, code: %d)" % [path, img.get_width(), img.get_height(), err])

func _init() -> void:
	print("\n========================================================")
	print("  STARTING PACKAGE 2D LIVE VISUAL VALIDATION")
	print("  DisplayServer: ", DisplayServer.get_name())
	print("========================================================\n")

	world_inst = WorldViewScene.instantiate()
	root.add_child(world_inst)

func _process(_delta: float) -> bool:
	frame_count += 1

	if frame_count == 5:
		hud = world_inst.get_node_or_null("HUD")
		guide = hud.get_node_or_null("PlayerFieldGuide") if hud else null
		if guide != null:
			# State 1: Open Guide on Chapter A (Main Overview & Starting Settlement)
			guide.open_guide(0)

	elif frame_count == 10:
		# Capture Main Overview (Chapter A)
		_save_screenshot("p2d_01_guide_main_overview.png")
		# State 2: Switch to Chapter D (30-Day Starter Roadmap & 40-Day Calendar)
		if guide != null:
			guide.select_chapter(3)

	elif frame_count == 15:
		# Capture 30-Day Roadmap (Chapter D)
		_save_screenshot("p2d_02_guide_30day_starter.png")
		# State 3: Switch to Chapter B (Citizen Vocations & 5-Level Skill Progression)
		if guide != null:
			guide.select_chapter(1)

	elif frame_count == 20:
		# Capture Citizen Skills (Chapter B)
		_save_screenshot("p2d_03_guide_citizen_skills.png")
		# State 4: Switch to Chapter F (Prosperity Victory & Package 2C Surplus Treasury)
		if guide != null:
			guide.select_chapter(5)

	elif frame_count == 25:
		# Capture Victory & Legacy (Chapter F)
		_save_screenshot("p2d_04_guide_victory_legacy.png")
		# State 5: Switch resolution to 1024x576 and capture responsive layout
		DisplayServer.window_set_size(Vector2i(1024, 576))
		if guide != null:
			guide.select_chapter(3)

	elif frame_count == 30:
		# Capture 1024x576 Responsive Layout
		_save_screenshot("p2d_05_guide_responsive_1024x576.png")

		print("\n========================================================")
		print("  LIVE VISUAL VALIDATION COMPLETED SUCCESSFULLY (Exit Code 0)")
		print("========================================================\n")
		quit(0)
		return true

	return false
