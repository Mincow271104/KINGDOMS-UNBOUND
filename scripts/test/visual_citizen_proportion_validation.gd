class_name VisualCitizenProportionValidation
extends SceneTree

const IsoMathScript = preload("res://scripts/utils/iso_math.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")

var world_scene: PackedScene
var world_inst: Node2D
var cam: Camera2D
var hud: CanvasLayer
var current_step: int = 0
var phase: int = 0
var wait_frames: int = 0
var file_prefix: String = "before_"

const SCREENSHOT_DIR: String = "docs/visual_validation/citizen_tuning/"

func _init() -> void:
	print("========================================================")
	print("  STARTING CITIZEN PROPORTION VISUAL VALIDATION HARNESS")
	print("  DisplayServer: ", DisplayServer.get_name())

	for arg in OS.get_cmdline_args():
		if arg.begins_with("--prefix="):
			file_prefix = arg.substr(9)
	print("  File Prefix: ", file_prefix)
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
				var path = SCREENSHOT_DIR + file_prefix + filename
				var err = img.save_png(path)
				if err == OK:
					print("  [SCREENSHOT CAPTURED] -> %s (%dx%d)" % [path, img.get_width(), img.get_height()])
				else:
					printerr("  [SCREENSHOT FAILED] -> %s (err %d)" % [path, err])

func _process(_delta: float) -> bool:
	if phase == 1:
		wait_frames += 1
		if wait_frames >= 10:
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
			_step_1_citizen_beside_house()
			phase = 1
		2:
			_step_2_citizen_near_townhall()
			phase = 1
		3:
			_step_3_citizens_gathering()
			phase = 1
		4:
			_step_4_citizen_ysort()
			phase = 1
		5:
			_step_5_citizen_inspection()
			phase = 1
		6:
			_step_6_settlement_overview()
			phase = 1
		7:
			_step_7_finish()
			return true
	return false

func _step_1_citizen_beside_house() -> void:
	print("--- Step 1: Citizen beside House ---")
	if world_inst:
		# Place a house at (30, 34)
		world_inst._instantiate_building_node("house", Vector2i(30, 34), Vector2i(2, 2), "active")
		if world_inst.citizen_list.size() >= 2:
			var c1 = world_inst.citizen_list[0]
			var c2 = world_inst.citizen_list[1]
			c1.position = IsoMathScript.map_to_local(Vector2i(32, 34))
			c1.current_cell = Vector2i(32, 34)
			c2.position = IsoMathScript.map_to_local(Vector2i(30, 36))
			c2.current_cell = Vector2i(30, 36)
		if cam:
			cam.position = IsoMathScript.map_to_local(Vector2i(31, 35))
			cam.zoom = Vector2(3.0, 3.0)

func _step_2_citizen_near_townhall() -> void:
	print("--- Step 2: Citizen near Town Hall ---")
	if world_inst:
		if world_inst.citizen_list.size() >= 1:
			var c1 = world_inst.citizen_list[0]
			c1.position = IsoMathScript.map_to_local(Vector2i(34, 34))
			c1.current_cell = Vector2i(34, 34)
		if cam:
			cam.position = IsoMathScript.map_to_local(Vector2i(33, 33))
			cam.zoom = Vector2(2.8, 2.8)

func _step_3_citizens_gathering() -> void:
	print("--- Step 3: Citizens Gathering in Plaza ---")
	if world_inst:
		var gather_cells := [
			Vector2i(33, 34), Vector2i(34, 33), Vector2i(34, 34),
			Vector2i(33, 35), Vector2i(35, 34), Vector2i(32, 35)
		]
		for i in range(mini(gather_cells.size(), world_inst.citizen_list.size())):
			var c = world_inst.citizen_list[i]
			c.position = IsoMathScript.map_to_local(gather_cells[i])
			c.current_cell = gather_cells[i]
		if cam:
			cam.position = IsoMathScript.map_to_local(Vector2i(33, 34))
			cam.zoom = Vector2(2.2, 2.2)

func _step_4_citizen_ysort() -> void:
	print("--- Step 4: Citizen Y-Sorting (Front and Behind) ---")
	if world_inst:
		if world_inst.citizen_list.size() >= 4:
			# Townhall at 31..33
			var c_th_behind = world_inst.citizen_list[0]
			var c_th_front = world_inst.citizen_list[1]
			c_th_behind.position = IsoMathScript.map_to_local(Vector2i(32, 30))
			c_th_behind.current_cell = Vector2i(32, 30)
			c_th_front.position = IsoMathScript.map_to_local(Vector2i(33, 34))
			c_th_front.current_cell = Vector2i(33, 34)

			# House at 30..31, 34..35
			var c_h_behind = world_inst.citizen_list[2]
			var c_h_front = world_inst.citizen_list[3]
			c_h_behind.position = IsoMathScript.map_to_local(Vector2i(30, 33))
			c_h_behind.current_cell = Vector2i(30, 33)
			c_h_front.position = IsoMathScript.map_to_local(Vector2i(31, 36))
			c_h_front.current_cell = Vector2i(31, 36)

		if cam:
			cam.position = IsoMathScript.map_to_local(Vector2i(32, 33))
			cam.zoom = Vector2(2.8, 2.8)

func _step_5_citizen_inspection() -> void:
	print("--- Step 5: Citizen Selection & Inspector UI ---")
	if world_inst and hud:
		if world_inst.citizen_list.size() >= 1:
			var target_cit = world_inst.citizen_list[0]
			target_cit.position = IsoMathScript.map_to_local(Vector2i(33, 34))
			target_cit.current_cell = Vector2i(33, 34)
			hud.show_citizen_inspector(target_cit)
		if cam:
			cam.position = IsoMathScript.map_to_local(Vector2i(33, 34))
			cam.zoom = Vector2(2.5, 2.5)

func _step_6_settlement_overview() -> void:
	print("--- Step 6: Full Settlement Overview (Normal Gameplay Zoom) ---")
	if world_inst:
		# Close inspector
		if hud and hud.citizen_panel:
			hud.citizen_panel.visible = false
		if cam:
			cam.position = IsoMathScript.map_to_local(Vector2i(32, 32))
			cam.zoom = Vector2(1.8, 1.8)

func _step_7_finish() -> void:
	print("--- Step 7: Validation Harness Complete ---")
	print("=== CITIZEN PROPORTION HARNESS FINISHED SUCCESSFULLY ===")
	quit(0)

func _capture_for_step(step: int) -> void:
	match step:
		1:
			_capture_screenshot("01_citizen_beside_house.png")
		2:
			_capture_screenshot("02_citizen_near_townhall.png")
		3:
			_capture_screenshot("03_citizens_gathering.png")
		4:
			_capture_screenshot("04_citizen_ysort_front_behind.png")
		5:
			_capture_screenshot("05_citizen_selection_inspection.png")
		6:
			_capture_screenshot("06_settlement_overview.png")
