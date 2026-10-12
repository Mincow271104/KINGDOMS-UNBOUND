extends SceneTree

var frame_count: int = 0
var world_instance: Node = null

func _init() -> void:
	var world_scene: PackedScene = load("res://scenes/world/world_view.tscn")
	world_instance = world_scene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	
	if frame_count == 25:
		_save_shot("screenshot_phase7.png")
		# Open Victory Dialog
		var hud = world_instance.get_node_or_null("HUD")
		if hud:
			hud.show_victory_panel({
				"days_survived": 12,
				"peak_population": 32,
				"food_reserve": 650,
				"treasury": 1450,
				"technologies_unlocked": 4,
				"legacy_points": 100
			})
			
	elif frame_count == 40:
		_save_shot("screenshot_phase7_victory.png")
		# Close Victory Dialog and Open Collapse Dialog
		var hud = world_instance.get_node_or_null("HUD")
		if hud:
			var vic_panel = hud.get_node_or_null("VictoryPanel")
			if vic_panel: vic_panel.visible = false
			hud.show_collapse_panel({
				"days_survived": 8,
				"hours_survived": 14,
				"peak_population": 28,
				"primary_cause": "Nạn đói toàn diện: Kho lương thực đã cạn kiệt kéo dài dẫn đến suy kiệt dân số",
				"buildings_count": 9,
				"technologies_unlocked": 2
			})
			
	elif frame_count == 55:
		_save_shot("screenshot_phase7_collapse.png")
		quit(0)
		return true
		
	return false

func _save_shot(filename: String) -> void:
	var vp: Viewport = root
	var img: Image = vp.get_texture().get_image()
	if img:
		var path := "addons/godot_mcp/cache/screenshots/" + filename
		var err := img.save_png(path)
		print("[Capture] Saved screenshot to %s (error code: %d)" % [path, err])
