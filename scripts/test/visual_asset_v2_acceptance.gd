class_name VisualAssetV2Acceptance
extends SceneTree

const IsoMathScript = preload("res://scripts/utils/iso_math.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")

var world_scene: PackedScene
var world_inst: Node2D
var cam: Camera2D
var hud: CanvasLayer
var current_step: int = 0
var phase: int = 0 # 0: action, 1: wait frames, 2: capture
var wait_frames: int = 0

const SCREENSHOT_DIR: String = "docs/visual_validation/"

func _init() -> void:
	print("========================================================")
	print("  STARTING ASSET PACK V2 VISUAL ACCEPTANCE HARNESS")
	print("  DisplayServer: ", DisplayServer.get_name())
	print("========================================================\n")

	world_scene = load("res://scenes/world/world_view.tscn")
	world_inst = world_scene.instantiate()
	root.add_child(world_inst)
	cam = world_inst.get_node_or_null("Camera2D")
	hud = world_inst.get_node_or_null("HUD")

func _capture_screenshot(filename: String) -> void:
	var vp = root.get_viewport()
	if vp:
		var tex = vp.get_texture()
		if tex:
			var img = tex.get_image()
			if img:
				var path = SCREENSHOT_DIR + filename
				var err = img.save_png(path)
				if err == OK:
					print("  [SCREENSHOT CAPTURED] -> %s (%dx%d)" % [path, img.get_width(), img.get_height()])
				else:
					printerr("  [SCREENSHOT FAILED] -> %s (err %d)" % [path, err])

func _process(_delta: float) -> bool:
	if phase == 1:
		wait_frames += 1
		if wait_frames >= 8: # Wait 8 frames for full render and texture updates
			phase = 2
		return false

	if phase == 2:
		_capture_for_step(current_step)
		phase = 0
		wait_frames = 0
		return false

	current_step += 1
	match current_step:
		1:
			_step_1_starter_settlement()
			phase = 1
		2:
			_step_2_placement_preview()
			phase = 1
		3:
			_step_3_citizen_ysort_closeup()
			phase = 1
		4:
			_step_4_all_buildings_showcase()
			phase = 1
		5:
			_step_5_main_menu()
			phase = 1
		6:
			_step_6_finish()
			return true
	return false

func _step_1_starter_settlement() -> void:
	print("--- Step 1: Starter Settlement & Main Gameplay View ---")
	if cam:
		cam.position = IsoMathScript.map_to_local(Vector2i(32, 32))
		cam.zoom = Vector2(2.0, 2.0)

func _step_2_placement_preview() -> void:
	print("--- Step 2: Building Placement Preview (Ghost Building & Diamond Cursor) ---")
	if world_inst:
		# Trigger placement preview mode for 'house'
		world_inst._on_build_requested("house")
		var preview_cell := Vector2i(35, 29)
		world_inst.ghost_building_node.visible = true
		world_inst.ghost_building_node.position = IsoMathScript.map_to_local(preview_cell + Vector2i(1, 1))
		world_inst.ghost_building_sprite.modulate = Color(0.4, 1.3, 0.4, 0.8) # Green: legal
		world_inst.cursor_highlight.visible = true
		world_inst.cursor_highlight.position = IsoMathScript.map_to_local(preview_cell)
		if cam:
			cam.position = IsoMathScript.map_to_local(preview_cell)
			cam.zoom = Vector2(2.4, 2.4)

func _step_3_citizen_ysort_closeup() -> void:
	print("--- Step 3: Citizen Near Building & Y-Sorting Close-up ---")
	if world_inst:
		world_inst._cancel_placement()
		var front_cell := Vector2i(34, 34) # South of townhall -> In front
		var behind_cell := Vector2i(32, 30) # North of townhall -> Behind
		
		if world_inst.citizen_list.size() >= 2:
			var c1 = world_inst.citizen_list[0]
			var c2 = world_inst.citizen_list[1]
			c1.position = IsoMathScript.map_to_local(front_cell)
			c2.position = IsoMathScript.map_to_local(behind_cell)
			c1.current_cell = front_cell
			c2.current_cell = behind_cell

		if cam:
			cam.position = IsoMathScript.map_to_local(Vector2i(33, 33))
			cam.zoom = Vector2(3.2, 3.2)

func _step_4_all_buildings_showcase() -> void:
	print("--- Step 4: All 13 Building Assets Showcase ---")
	if world_inst:
		# Place all 13 building types in an exhibition strip
		var bld_types := [
			"townhall", "barracks", "market", "research_hall",
			"house", "storehouse", "farm", "woodcutter",
			"quarry", "mine", "workshop", "watchtower", "palisade"
		]
		
		var start_origin := Vector2i(8, 8)
		var col := 0
		var row := 0
		for b_type in bld_types:
			var bp: Dictionary = EconomyConfigScript.BLUEPRINTS.get(b_type, {})
			var b_size: Vector2i = bp.get("footprint", Vector2i(2, 2))
			var cell := start_origin + Vector2i(col * 5, row * 5)
			world_inst._instantiate_building_node(b_type, cell, b_size, "active")
			col += 1
			if col >= 4:
				col = 0
				row += 1
				
		# Also place prop_poi_ruins, prop_tree, prop_rock nearby
		var poi_cell := Vector2i( start_origin.x + 1 * 5, start_origin.y + 3 * 5 )
		var p_poi := Node2D.new()
		p_poi.position = IsoMathScript.map_to_local(poi_cell)
		p_poi.y_sort_enabled = true
		var spr_poi := Sprite2D.new()
		spr_poi.texture = world_inst.prop_textures.get("poi_ruins")
		spr_poi.centered = false
		spr_poi.offset = Vector2(-16.0, -24.0)
		p_poi.add_child(spr_poi)
		world_inst.props_container.add_child(p_poi)

		if cam:
			cam.position = IsoMathScript.map_to_local(Vector2i(16, 16))
			cam.zoom = Vector2(1.5, 1.5)

func _step_5_main_menu() -> void:
	print("--- Step 5: Main Menu Scene Inspection ---")
	# Free world_inst and instantiate MainMenu
	if world_inst:
		world_inst.queue_free()
		world_inst = null
	var menu_scene = load("res://scenes/ui/main_menu.tscn")
	if menu_scene:
		var menu_inst = menu_scene.instantiate()
		root.add_child(menu_inst)

func _step_6_finish() -> void:
	print("--- Step 6: Verification Complete ---")
	print("=== ASSET PACK V2 VISUAL ACCEPTANCE FINISHED SUCCESSFULLY ===")
	quit(0)

func _capture_for_step(step: int) -> void:
	match step:
		1:
			_capture_screenshot("v2_01_starter_settlement.png")
		2:
			_capture_screenshot("v2_02_placement_preview.png")
		3:
			_capture_screenshot("v2_03_citizen_near_building_ysort.png")
		4:
			_capture_screenshot("v2_04_all_buildings_showcase.png")
		5:
			_capture_screenshot("v2_05_main_menu.png")
