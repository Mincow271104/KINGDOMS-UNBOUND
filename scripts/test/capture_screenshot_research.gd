extends SceneTree

func _init() -> void:
	var world_scene = load("res://scenes/world/world_view.tscn").instantiate()
	root.add_child(world_scene)
	
	for i in range(5):
		await process_frame
		
	var hud: InGameHUD = world_scene.get_node("HUD") as InGameHUD
	if hud != null:
		hud._toggle_research_menu()
		
	for i in range(5):
		await process_frame
		
	var vp: Viewport = root.get_viewport()
	if vp != null:
		var tex = vp.get_texture()
		if tex != null:
			var img: Image = tex.get_image()
			if img != null and not img.is_empty():
				var err = img.save_png("res://addons/godot_mcp/cache/screenshots/screenshot_phase5_research_menu.png")
				if err == OK:
					print("PASS: Research menu screenshot captured and saved.")
	quit(0)
