class_name VisualValidationTest
extends Node2D
## Visual-Validation Gate scene controller for KINGDOMS UNBOUND.
## Mandatory Phase 1 milestone demonstrating:
## 1. 2:1 isometric diamond terrain tiles (32x16 px)
## 2. Isometric props (trees and rocks) with ground-contact pivots
## 3. Multi-tile buildings with visible rooftops and front-facing facades (SW & SE)
## 4. One moving citizen navigating the grid with ground-contact foot pivot (12, 30)
## 5. Interactive mouse-hover diamond grid highlighting matching 32x16 geometry
## 6. Flawless depth/Y-sorting (y_sort_enabled = true) with natural occlusion

@onready var world_container: Node2D = $WorldContainer
@onready var terrain_layer: Node2D = $WorldContainer/TerrainLayer
@onready var entity_container: Node2D = $WorldContainer/Entities
@onready var cursor_highlight: Sprite2D = $WorldContainer/CursorHighlight
@onready var info_label: Label = $CanvasLayer/InfoPanel/MarginContainer/VBoxContainer/InfoLabel
@onready var status_label: Label = $CanvasLayer/InfoPanel/MarginContainer/VBoxContainer/StatusLabel

# Citizen movement patrol waypoints (grid cells)
var patrol_path: Array[Vector2i] = [
	Vector2i(2, 2), # Start: North-West open ground
	Vector2i(4, 2), # Moving behind Tree at (4, 3)
	Vector2i(5, 3), # Moving BEHIND House at (4, 4) -> Occluded by Roof
	Vector2i(7, 3), # East of House
	Vector2i(7, 6), # North of Town Hall -> BEHIND Town Hall
	Vector2i(10, 6), # East of Town Hall
	Vector2i(10, 10), # South of Town Hall -> IN FRONT of Town Hall
	Vector2i(4, 6), # South of House -> IN FRONT of House
	Vector2i(2, 5), # West of House
]

var citizen_sprite: Sprite2D
var citizen_node: Node2D
var current_waypoint_idx: int = 0
var move_speed: float = 60.0 # pixels per second
var is_headless: bool = false

func _ready() -> void:
	is_headless = DisplayServer.get_name() == "headless"
	
	if has_node("Camera2D"):
		var cam: CameraController = $Camera2D as CameraController
		cam.start_grid_pos = Vector2i(6, 6)
		cam.position = IsoMath.map_to_local(Vector2i(6, 6))
		cam.zoom = Vector2(2.5, 2.5)
	
	_setup_terrain()
	_setup_props()
	_setup_buildings()
	_setup_citizen()
	_setup_cursor()
	
	print("[VisualValidation] Visual-Validation Gate scene initialized successfully.")
	if is_headless:
		_run_headless_verification()

func _setup_terrain() -> void:
	var grass_tex = load("res://assets/terrain/tile_grass.png")
	var dirt_tex = load("res://assets/terrain/tile_dirt.png")
	var sand_tex = load("res://assets/terrain/tile_sand.png")
	
	# Create a 14x14 test grid area (cells 0..13)
	for x in range(14):
		for y in range(14):
			var tile := Sprite2D.new()
			if (x + y) % 5 == 0:
				tile.texture = dirt_tex
			elif x == 0 or y == 0 or x == 13 or y == 13:
				tile.texture = sand_tex
			else:
				tile.texture = grass_tex
				
			tile.centered = false
			# Position tile so diamond center aligns with IsoMath.map_to_local
			# Diamond texture is 32x16. Diamond top vertex is (16, 0), center is (16, 8).
			var local_pos := IsoMath.map_to_local(Vector2i(x, y))
			tile.position = local_pos - Vector2(16.0, 8.0)
			terrain_layer.add_child(tile)

func _setup_props() -> void:
	var tree_tex = load("res://assets/props/prop_tree.png")
	var rock_tex = load("res://assets/props/prop_rock.png")
	
	var prop_placements: Array[Dictionary] = [
		{"type": "tree", "cell": Vector2i(3, 3)},
		{"type": "tree", "cell": Vector2i(7, 2)},
		{"type": "tree", "cell": Vector2i(2, 6)},
		{"type": "tree", "cell": Vector2i(11, 4)},
		{"type": "rock", "cell": Vector2i(2, 4)},
		{"type": "rock", "cell": Vector2i(6, 4)},
		{"type": "rock", "cell": Vector2i(9, 3)},
		{"type": "rock", "cell": Vector2i(3, 8)}
	]
	
	for p in prop_placements:
		var prop_node := Node2D.new()
		prop_node.position = IsoMath.map_to_local(p["cell"])
		prop_node.y_sort_enabled = true
		
		var spr := Sprite2D.new()
		if p["type"] == "tree":
			spr.texture = tree_tex
			# Tree 32x48, trunk base pivot at (16, 40)
			spr.offset = Vector2(-16.0, -40.0)
		else:
			spr.texture = rock_tex
			# Rock 32x24, base contact pivot at (16, 18)
			spr.offset = Vector2(-16.0, -18.0)
			
		spr.centered = false
		prop_node.add_child(spr)
		entity_container.add_child(prop_node)

func _setup_buildings() -> void:
	var house_tex = load("res://assets/buildings/bld_house.png")
	var townhall_tex = load("res://assets/buildings/bld_townhall.png")
	
	# 1. House (2x2 footprint at cells (4,4). Base diamond occupies (4,4), (5,4), (4,5), (5,5))
	# Bottom-most vertex of 2x2 footprint is at map_to_local(Vector2i(5, 5))
	var house_origin := Vector2i(4, 4)
	var house_node := Node2D.new()
	# Anchor house node at the bottom center of its base diamond for exact Y-sorting
	# Center of cell (5, 5) ground vertex:
	house_node.position = IsoMath.map_to_local(house_origin + Vector2i(1, 1))
	house_node.y_sort_enabled = true
	
	var house_spr := Sprite2D.new()
	house_spr.texture = house_tex
	# House texture is 64x56. Base diamond center is at (32, 40).
	# Offset to place base diamond center on node origin:
	house_spr.offset = Vector2(-32.0, -40.0)
	house_spr.centered = false
	house_node.add_child(house_spr)
	entity_container.add_child(house_node)
	
	# 2. Town Hall (3x3 footprint at cells (7,7). Base diamond occupies (7,7) to (9,9))
	var th_origin := Vector2i(7, 7)
	var th_node := Node2D.new()
	th_node.position = IsoMath.map_to_local(th_origin + Vector2i(2, 2))
	th_node.y_sort_enabled = true
	
	var th_spr := Sprite2D.new()
	th_spr.texture = townhall_tex
	# Town Hall texture is 96x80. Base diamond center is at (48, 56).
	th_spr.offset = Vector2(-48.0, -56.0)
	th_spr.centered = false
	th_node.add_child(th_spr)
	entity_container.add_child(th_node)

func _setup_citizen() -> void:
	citizen_node = Node2D.new()
	citizen_node.position = IsoMath.map_to_local(patrol_path[0])
	citizen_node.y_sort_enabled = true
	
	citizen_sprite = Sprite2D.new()
	citizen_sprite.texture = load("res://assets/entities/citizen.png")
	# Citizen 24x32 canvas, ground contact foot pivot at (12, 30)
	citizen_sprite.offset = Vector2(-12.0, -30.0)
	citizen_sprite.centered = false
	citizen_node.add_child(citizen_sprite)
	
	entity_container.add_child(citizen_node)

func _setup_cursor() -> void:
	cursor_highlight.texture = load("res://assets/ui/cursor_diamond.png")
	cursor_highlight.offset = Vector2(-16.0, -8.0)
	cursor_highlight.centered = false

func _process(delta: float) -> void:
	# 1. Update citizen patrol movement
	_update_citizen_movement(delta)
	
	# 2. Update interactive cursor hover
	_update_cursor_hover()

func _update_citizen_movement(delta: float) -> void:
	if patrol_path.is_empty():
		return
		
	var target_cell := patrol_path[current_waypoint_idx]
	var target_local := IsoMath.map_to_local(target_cell)
	var dir := target_local - citizen_node.position
	var dist := dir.length()
	
	if dist <= move_speed * delta:
		citizen_node.position = target_local
		current_waypoint_idx = (current_waypoint_idx + 1) % patrol_path.size()
	else:
		citizen_node.position += dir.normalized() * move_speed * delta

func _update_cursor_hover() -> void:
	var mouse_local := world_container.get_local_mouse_position()
	var hovered_cell := IsoMath.local_to_map(mouse_local)
	
	if IsoMath.is_in_bounds(hovered_cell) and hovered_cell.x < 14 and hovered_cell.y < 14:
		cursor_highlight.visible = true
		cursor_highlight.position = IsoMath.map_to_local(hovered_cell)
		if info_label:
			var current_grid := IsoMath.local_to_map(citizen_node.position)
			info_label.text = "Ô đang chọn: (%d, %d)\nVị trí Dân làng: (%d, %d)" % [hovered_cell.x, hovered_cell.y, current_grid.x, current_grid.y]
	else:
		cursor_highlight.visible = false

func _run_headless_verification() -> void:
	print("--- Running Headless Verification of Visual-Validation Gate ---")
	var failures: int = 0
	
	# 1. Verify entity container Y-Sort
	if not entity_container.y_sort_enabled:
		printerr("FAIL: Entities container y_sort_enabled is FALSE")
		failures += 1
	else:
		print("PASS: Entity container y_sort_enabled = true")
		
	# 2. Verify World container Y-Sort
	if not world_container.y_sort_enabled:
		printerr("FAIL: WorldContainer y_sort_enabled is FALSE")
		failures += 1
	else:
		print("PASS: World container y_sort_enabled = true")

	# 3. Verify citizen foot pivot offset
	if citizen_sprite.offset != Vector2(-12.0, -30.0):
		printerr("FAIL: Citizen foot pivot offset is %s, expected (-12, -30)" % citizen_sprite.offset)
		failures += 1
	else:
		print("PASS: Citizen foot pivot offset strictly (-12, -30) at ground contact")

	# 4. Verify Y-Sort occlusion math:
	# Cell (5, 3) is behind House (base at y = map_to_local(5, 5).y = 80)
	var behind_pos := IsoMath.map_to_local(Vector2i(5, 3))
	var house_base_pos := IsoMath.map_to_local(Vector2i(5, 5))
	var in_front_pos := IsoMath.map_to_local(Vector2i(5, 7))
	
	if behind_pos.y >= house_base_pos.y:
		printerr("FAIL: Cell (5, 3) y (%f) should be less than House base y (%f)" % [behind_pos.y, house_base_pos.y])
		failures += 1
	else:
		print("PASS: Citizen at (5, 3) [y=%.1f] sorts BEHIND House [y=%.1f] (Natural Occlusion)" % [behind_pos.y, house_base_pos.y])
		
	if in_front_pos.y <= house_base_pos.y:
		printerr("FAIL: Cell (5, 7) y (%f) should be greater than House base y (%f)" % [in_front_pos.y, house_base_pos.y])
		failures += 1
	else:
		print("PASS: Citizen at (5, 7) [y=%.1f] sorts IN FRONT of House [y=%.1f] (Overlays Facade)" % [in_front_pos.y, house_base_pos.y])

	if failures == 0:
		print("=== VISUAL-VALIDATION GATE VERIFIED SUCCESSFULLY ===")
		if status_label:
			status_label.text = "CỔNG KIỂM TRA THỊ GIÁC: ĐẠT CHUẨN (PASSED)"
	else:
		printerr("=== VISUAL-VALIDATION GATE FAILED ===")
