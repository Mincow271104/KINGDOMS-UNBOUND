extends SceneTree
## =============================================================================
## KINGDOMS UNBOUND — Package 2F Live Visual Validation
## Building Inspection, Workplace Management & Demolition System
## Captures high-fidelity PNG screenshots at 1280x720 and 1024x576
## =============================================================================

const WorldViewScene = preload("res://scenes/world/world_view.tscn")

var frame_count: int = 0
var world_inst: Node = null
var hud: Node = null

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
	print("  STARTING PACKAGE 2F LIVE VISUAL VALIDATION")
	print("  DisplayServer: ", DisplayServer.get_name())
	print("========================================================\n")

	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)

	world_inst = WorldViewScene.instantiate()
	root.add_child(world_inst)

func _process(_delta: float) -> bool:
	frame_count += 1

	if frame_count == 5:
		hud = world_inst.get_node_or_null("HUD")
		# Give some buffer stock and assign worker skills to show rich info
		var wp_mgr = world_inst.get("workplace_mgr")
		if wp_mgr != null:
			var farm_wp = wp_mgr.get_workplace("farm_starter")
			if farm_wp:
				farm_wp.buffer_amount = 35 # 35/50 (70% full)

		# Set up a citizen with skill
		var citizens = world_inst.get("citizens")
		if citizens and citizens.size() > 0:
			var c0 = citizens[0]
			if c0.has_method("get_skill_data"):
				var sd = c0.get_skill_data()
				if sd:
					sd.set_xp("farming", 350.0)

		# Select farm starter
		var farm_bld = BuildingSystem.get_building_by_id("farm_starter", world_inst.world_data)
		if not farm_bld.is_empty():
			world_inst.select_building(farm_bld)

	elif frame_count == 10:
		_save_screenshot("p2f_01_workplace_inspect_buffer_1280x720.png")

		# Click demolish to show DemolishConfirmOverlay
		if hud != null:
			hud._on_demolish_building_pressed()

	elif frame_count == 15:
		_save_screenshot("p2f_02_demolish_confirm_overlay_1280x720.png")

		# Close demolish modal, select Town Hall, and trigger demolish modal on Town Hall
		if hud != null:
			hud._on_cancel_demolish_pressed()
			var th_bld = BuildingSystem.get_building_by_id("townhall_starter", world_inst.world_data)
			if not th_bld.is_empty():
				world_inst.select_building(th_bld)
				hud._on_demolish_building_pressed()

	elif frame_count == 20:
		_save_screenshot("p2f_03_townhall_demolish_emergency_warning_1280x720.png")

		# Close modal, re-select farm starter, resize window to 1024x576 for responsive check
		if hud != null:
			hud._on_cancel_demolish_pressed()
			var farm_bld = BuildingSystem.get_building_by_id("farm_starter", world_inst.world_data)
			if not farm_bld.is_empty():
				world_inst.select_building(farm_bld)

		DisplayServer.window_set_size(Vector2i(1024, 576))
		root.size = Vector2i(1024, 576)

	elif frame_count == 25:
		_save_screenshot("p2f_04_workplace_inspect_responsive_1024x576.png")
		print("\n[Visual Validation] All Package 2F visual validation captures completed successfully!\n")
		quit(0)
		return true

	return false
