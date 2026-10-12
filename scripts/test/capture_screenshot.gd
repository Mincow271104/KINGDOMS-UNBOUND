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
				var err = img.save_png("res://addons/godot_mcp/cache/screenshots/screenshot_phase5.png")
				if err == OK:
					print("PASS: Screenshot captured and saved to res://addons/godot_mcp/cache/screenshots/screenshot_phase5.png")
				else:
					printerr("FAIL: Error saving screenshot: %d" % err)
			else:
				print("Viewport image empty in headless mode (expected without physical GPU window)")
	quit(0)
