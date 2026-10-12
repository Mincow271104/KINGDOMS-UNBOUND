class_name WorldView
extends Node2D
## 64x64 Dimetric Isometric World View for KINGDOMS UNBOUND.
## Renders 2:1 isometric diamond terrain, starter buildings, props, citizens, and cursor highlight.

@export var world_seed: int = 12345

@onready var terrain_layer: Node2D = $World/TerrainLayer
@onready var entity_container: Node2D = $World/Entities
@onready var buildings_container: Node2D = $World/Entities/Buildings
@onready var props_container: Node2D = $World/Entities/Props
@onready var citizens_container: Node2D = $World/Entities/Citizens
@onready var cursor_highlight: Sprite2D = $World/CursorHighlight
@onready var camera: CameraController = $Camera2D
@onready var hud: InGameHUD = $HUD

var world_data: WorldGenerator.WorldData
var buildings_by_cell: Dictionary = {} # cell (Vector2i) -> building_type (String)
var terrain_textures: Dictionary = {}
var building_textures: Dictionary = {}
var prop_textures: Dictionary = {}

func _ready() -> void:
	_load_assets()
	_generate_and_build_world()
	
	# Connect HUD signals
	if hud:
		hud.return_to_menu_requested.connect(_on_return_to_menu)
		
	# Focus camera on settlement plaza
	if camera:
		camera.focus_on_cell(Vector2i(32, 32))
		
	print("[WorldView] 64x64 Isometric World generated from seed: %d" % world_seed)

func _load_assets() -> void:
	terrain_textures[WorldGenerator.TerrainType.GRASS] = load("res://assets/terrain/tile_grass.png")
	terrain_textures[WorldGenerator.TerrainType.DIRT] = load("res://assets/terrain/tile_dirt.png")
	terrain_textures[WorldGenerator.TerrainType.WATER] = load("res://assets/terrain/tile_water.png")
	terrain_textures[WorldGenerator.TerrainType.SAND] = load("res://assets/terrain/tile_sand.png")
	
	building_textures["townhall"] = load("res://assets/buildings/bld_townhall.png")
	building_textures["house"] = load("res://assets/buildings/bld_house.png")
	building_textures["farm"] = load("res://assets/buildings/bld_farm.png")
	building_textures["storehouse"] = load("res://assets/buildings/bld_storehouse.png")
	building_textures["woodcutter"] = load("res://assets/buildings/bld_woodcutter.png")
	
	prop_textures["tree"] = load("res://assets/props/prop_tree.png")
	prop_textures["rock"] = load("res://assets/props/prop_rock.png")
	
	cursor_highlight.texture = load("res://assets/ui/cursor_diamond.png")
	cursor_highlight.offset = Vector2(-16.0, -8.0)
	cursor_highlight.centered = false

func _generate_and_build_world() -> void:
	world_data = WorldGenerator.generate(world_seed)
	
	_render_terrain()
	_spawn_starter_buildings()
	_spawn_props()
	_spawn_starter_citizens()

func _render_terrain() -> void:
	for x in range(IsoMath.MAP_SIZE):
		for y in range(IsoMath.MAP_SIZE):
			var t_type: int = world_data.terrain[x][y]
			var tex: Texture2D = terrain_textures.get(t_type, terrain_textures[WorldGenerator.TerrainType.GRASS])
			
			var tile := Sprite2D.new()
			tile.texture = tex
			tile.centered = false
			var local_pos := IsoMath.map_to_local(Vector2i(x, y))
			tile.position = local_pos - Vector2(16.0, 8.0)
			terrain_layer.add_child(tile)

func _spawn_starter_buildings() -> void:
	for bld in world_data.buildings:
		var type: String = bld["type"]
		var origin: Vector2i = bld["cell"]
		var size: Vector2i = bld["size"]
		var tex: Texture2D = building_textures.get(type)
		if not tex:
			continue
			
		var b_node := Node2D.new()
		b_node.name = "Building_%s_%d_%d" % [type, origin.x, origin.y]
		b_node.y_sort_enabled = true
		
		# Set node position to the bottom center of the footprint diamond for exact Y-sorting
		var base_vertex := origin + Vector2i(size.x - 1, size.y - 1)
		b_node.position = IsoMath.map_to_local(base_vertex)
		
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.centered = false
		
		# Adjust offset so footprint base diamond center aligns with node origin
		match type:
			"townhall": # 96x80, base 96x48
				spr.offset = Vector2(-48.0, -56.0)
			"house": # 64x56, base 64x32
				spr.offset = Vector2(-32.0, -40.0)
			"storehouse": # 64x56, base 64x32
				spr.offset = Vector2(-32.0, -40.0)
			"farm": # 64x40, base 64x32
				spr.offset = Vector2(-32.0, -28.0)
			"woodcutter": # 64x48, base 64x32
				spr.offset = Vector2(-32.0, -36.0)
				
		b_node.add_child(spr)
		buildings_container.add_child(b_node)
		
		# Register building footprint for tile inspection
		for ox in range(size.x):
			for oy in range(size.y):
				buildings_by_cell[origin + Vector2i(ox, oy)] = type

func _spawn_props() -> void:
	for p in world_data.props:
		var type: String = p["type"]
		var cell: Vector2i = p["cell"]
		var tex: Texture2D = prop_textures.get(type)
		if not tex:
			continue
			
		var p_node := Node2D.new()
		p_node.position = IsoMath.map_to_local(cell)
		p_node.y_sort_enabled = true
		
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.centered = false
		
		if type == "tree":
			spr.offset = Vector2(-16.0, -40.0)
		else:
			spr.offset = Vector2(-16.0, -18.0)
			
		p_node.add_child(spr)
		props_container.add_child(p_node)

func _spawn_starter_citizens() -> void:
	var citizen_tex = load("res://assets/entities/citizen.png")
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 1111
	
	# Spawn 24 citizens around plaza (30..34, 31..35)
	for i in range(24):
		var rx := rng.randi_range(-2, 2)
		var ry := rng.randi_range(-2, 2)
		var cell := world_data.center_spawn + Vector2i(rx, ry)
		cell = IsoMath.clamp_grid(cell)
		
		var c_node := Node2D.new()
		c_node.name = "Citizen_%d" % (i + 1)
		c_node.position = IsoMath.map_to_local(cell)
		c_node.y_sort_enabled = true
		
		var spr := Sprite2D.new()
		spr.texture = citizen_tex
		spr.centered = false
		spr.offset = Vector2(-12.0, -30.0)
		
		c_node.add_child(spr)
		citizens_container.add_child(c_node)

func _process(_delta: float) -> void:
	_update_tile_hover()

func _update_tile_hover() -> void:
	var mouse_local := terrain_layer.get_local_mouse_position()
	var cell := IsoMath.local_to_map(mouse_local)
	
	if IsoMath.is_in_bounds(cell):
		cursor_highlight.visible = true
		cursor_highlight.position = IsoMath.map_to_local(cell)
		
		if hud:
			var t_name := _get_terrain_name(world_data.terrain[cell.x][cell.y])
			var b_name := _get_building_display_name(buildings_by_cell.get(cell, ""))
			hud.set_tile_info(cell, t_name, b_name)
	else:
		cursor_highlight.visible = false

func _get_terrain_name(type: int) -> String:
	match type:
		WorldGenerator.TerrainType.WATER:
			return "Mặt Nước (Không thể đi)"
		WorldGenerator.TerrainType.SAND:
			return "Bãi Cát"
		WorldGenerator.TerrainType.GRASS:
			return "Đồng Cỏ"
		WorldGenerator.TerrainType.DIRT:
			return "Đất Thổ"
		_:
			return "Không xác định"

func _get_building_display_name(key: String) -> String:
	match key:
		"townhall":
			return "Tòa Thị Chính (3x3)"
		"house":
			return "Nhà Ở (2x2)"
		"farm":
			return "Nông Trại (2x2)"
		"storehouse":
			return "Kho Lương (2x2)"
		"woodcutter":
			return "Trại Tiều Phu (2x2)"
		_:
			return ""

func _on_return_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
