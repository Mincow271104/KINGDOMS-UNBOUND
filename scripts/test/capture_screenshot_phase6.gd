extends SceneTree

func _init() -> void:
	var world_scene = load("res://scenes/world/world_view.tscn").instantiate()
	root.add_child(world_scene)
	
	for i in range(5):
		await process_frame
		
	var vp: Viewport = root.get_viewport()
	if vp != null:
		var tex = vp.get_texture()
		if tex != null:
			var img: Image = tex.get_image()
			if img != null and not img.is_empty():
				img.save_png("res://addons/godot_mcp/cache/screenshots/screenshot_phase6.png")
				print("PASS: Phase 6 world screenshot saved.")
				
	# Now toggle diplomacy menu
	var hud: InGameHUD = world_scene.get_node("HUD") as InGameHUD
	if hud != null:
		hud._toggle_diplomacy_menu()
		
	for i in range(5):
		await process_frame
		
	if vp != null:
		var tex2 = vp.get_texture()
		if tex2 != null:
			var img2: Image = tex2.get_image()
			if img2 != null and not img2.is_empty():
				img2.save_png("res://addons/godot_mcp/cache/screenshots/screenshot_phase6_diplomacy.png")
				print("PASS: Phase 6 diplomacy menu screenshot saved.")
				
	quit(0)
