extends SceneTree

var frame_count: int = 0
var world_instance: Node = null
var main_menu_instance: Node = null

func _init() -> void:
	var world_scene: PackedScene = load("res://scenes/world/world_view.tscn")
	world_instance = world_scene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	
	if frame_count == 25:
		var hud = world_instance.get_node_or_null("HUD")
		if hud:
			hud.call("_toggle_pause_menu")
			hud.call("_on_save_game_pressed")
			
	elif frame_count == 35:
		_save_shot("screenshot_phase8_pause_menu.png")
		
		# Remove World and load Main Menu
		world_instance.queue_free()
		world_instance = null
		
		var mm_scene: PackedScene = load("res://scenes/ui/main_menu.tscn")
		main_menu_instance = mm_scene.instantiate()
		root.add_child(main_menu_instance)
		
	elif frame_count == 45:
		_save_shot("screenshot_phase8_main_menu.png")
		quit(0)
		return true
		
	return false

func _save_shot(filename: String) -> void:
	var vp: Viewport = root
	var img: Image = vp.get_texture().get_image()
	if img:
		var dir := DirAccess.open("res://")
		if not dir.dir_exists("addons/godot_mcp/cache/screenshots"):
			dir.make_dir_recursive("addons/godot_mcp/cache/screenshots")
		var path := "addons/godot_mcp/cache/screenshots/" + filename
		var err := img.save_png(path)
		print("[Capture] Saved screenshot to %s (error code: %d)" % [path, err])
