class_name WorldView
extends Node2D
## 64x64 Dimetric Isometric World View for KINGDOMS UNBOUND.
## Renders 2:1 isometric diamond terrain, starter buildings, props, citizens, and cursor highlight.
## Supports interactive building placement, citizen inspection, and job execution.

const IsoMath = preload("res://scripts/utils/iso_math.gd")
const WorldGenerator = preload("res://scripts/world/world_generator.gd")
const EconomyConfig = preload("res://scripts/economy/economy_config.gd")
const BuildingSystem = preload("res://scripts/economy/building_system.gd")
const GridNavigation = preload("res://scripts/navigation/grid_navigation.gd")
const JobManager = preload("res://scripts/jobs/job_manager.gd")
const CitizenControllerScript = preload("res://scripts/entities/citizen_controller.gd")

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
var nav: GridNavigation
var job_mgr: JobManager

var buildings_by_cell: Dictionary = {} # cell (Vector2i) -> building_type (String)
var citizens_by_id: Dictionary = {}
var citizen_list: Array = []
var terrain_textures: Dictionary = {}
var building_textures: Dictionary = {}
var prop_textures: Dictionary = {}

var placing_building_type: String = ""
var ghost_building_node: Node2D
var ghost_building_sprite: Sprite2D

func _ready() -> void:
	_load_assets()
	_generate_and_build_world()
	_setup_ghost_preview()
	
	# Connect HUD signals
	if hud:
		hud.return_to_menu_requested.connect(_on_return_to_menu)
		hud.build_requested.connect(_on_build_requested)
		hud.citizen_role_changed.connect(_on_citizen_role_changed)
		
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

func _setup_ghost_preview() -> void:
	ghost_building_node = Node2D.new()
	ghost_building_node.name = "GhostBuildingPreview"
	ghost_building_node.visible = false
	ghost_building_node.z_index = 20
	
	ghost_building_sprite = Sprite2D.new()
	ghost_building_sprite.centered = false
	ghost_building_node.add_child(ghost_building_sprite)
	$World.add_child(ghost_building_node)

func _generate_and_build_world() -> void:
	world_data = WorldGenerator.generate(world_seed)
	nav = GridNavigation.new(world_data)
	job_mgr = JobManager.new()
	
	_create_workplace_jobs()
	_render_terrain()
	_spawn_starter_buildings()
	_spawn_props()
	_spawn_starter_citizens()

func _create_workplace_jobs() -> void:
	# Farm at (36, 35) generates 5 farming jobs around perimeter
	for i in range(5):
		var target := Vector2i(35 + (i % 2), 35 + (i / 2))
		job_mgr.create_job("farmer", target, "Chăm sóc và thu hoạch nông sản", "farm_starter", 3.0)
		
	# Woodcutter Camp at (26, 30) generates 4 woodcutter jobs
	for i in range(4):
		var target := Vector2i(25 + (i % 2), 29 + (i / 2))
		job_mgr.create_job("woodcutter", target, "Khai thác và chế biến gỗ", "woodcutter_starter", 3.0)

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
		_instantiate_building_node(bld["type"], bld["cell"], bld["size"])

func _instantiate_building_node(type: String, origin: Vector2i, size: Vector2i) -> void:
	var tex: Texture2D = building_textures.get(type)
	if not tex:
		return
		
	var b_node := Node2D.new()
	b_node.name = "Building_%s_%d_%d" % [type, origin.x, origin.y]
	b_node.y_sort_enabled = true
	
	# Bottom center of footprint diamond for exact Y-sorting
	var base_vertex := origin + Vector2i(size.x - 1, size.y - 1)
	b_node.position = IsoMath.map_to_local(base_vertex)
	
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = false
	spr.offset = _get_building_sprite_offset(type)
			
	b_node.add_child(spr)
	buildings_container.add_child(b_node)
	
	# Register building footprint for tile inspection
	for ox in range(size.x):
		for oy in range(size.y):
			buildings_by_cell[origin + Vector2i(ox, oy)] = type

func _get_building_sprite_offset(type: String) -> Vector2:
	match type:
		"townhall": return Vector2(-48.0, -56.0)
		"house": return Vector2(-32.0, -40.0)
		"storehouse": return Vector2(-32.0, -40.0)
		"farm": return Vector2(-32.0, -28.0)
		"woodcutter": return Vector2(-32.0, -36.0)
		_: return Vector2(-32.0, -32.0)

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
		spr.offset = Vector2(-16.0, -40.0) if type == "tree" else Vector2(-16.0, -18.0)
			
		p_node.add_child(spr)
		props_container.add_child(p_node)

func _spawn_starter_citizens() -> void:
	var citizen_tex = load("res://assets/entities/citizen.png")
	var starter_roles: Array[String] = []
	for i in range(5): starter_roles.append("farmer")
	for i in range(4): starter_roles.append("woodcutter")
	for i in range(3): starter_roles.append("builder")
	for i in range(3): starter_roles.append("hauler")
	for i in range(9): starter_roles.append("idle")
	
	var citizen_names: Array[String] = [
		"Nguyễn Văn An", "Trần Minh Bình", "Lê Văn Cường", "Phạm Quốc Dũng", "Hoàng Gia Em",
		"Vũ Thành Phúc", "Đặng Quang Giáp", "Bùi Huy Hùng", "Đỗ Đức Khang", "Hồ Nhật Long",
		"Ngô Hữu Minh", "Dương Tấn Nam", "Lý Hải Oanh", "Phan Trọng Phát", "Trịnh Đình Quân",
		"Lâm Vĩnh Sơn", "Cao Hoài Thắng", "Mai Hữu Uy", "Đinh Tuấn Vũ", "Hà Hải Xuân",
		"Đoàn Thế Yên", "Lương Chí Bảo", "Tạ Đình Chiến", "Trương Bá Đạt"
	]
	
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 1111
	
	for i in range(24):
		var cid := "citizen_%d" % (i + 1)
		var cname: String = citizen_names[i]
		var crole: String = starter_roles[i]
		
		var rx := rng.randi_range(-2, 2)
		var ry := rng.randi_range(-2, 2)
		var cell := world_data.center_spawn + Vector2i(rx, ry)
		cell = IsoMath.clamp_grid(cell)
		
		var cit = CitizenControllerScript.new()
		cit.name = cid
		
		var spr := Sprite2D.new()
		spr.name = "Sprite2D"
		spr.texture = citizen_tex
		spr.centered = false
		spr.offset = Vector2(-12.0, -30.0)
		cit.add_child(spr)
		
		cit.init_citizen(cid, cname, crole, cell, nav, job_mgr)
		citizens_container.add_child(cit)
		
		citizens_by_id[cid] = cit
		citizen_list.append(cit)

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
			
		# Handle ghost building placement preview
		if placing_building_type != "":
			ghost_building_node.visible = true
			var bp: Dictionary = EconomyConfig.BLUEPRINTS.get(placing_building_type, {})
			var size: Vector2i = bp.get("footprint", Vector2i(2, 2))
			var base_vertex := cell + Vector2i(size.x - 1, size.y - 1)
			ghost_building_node.position = IsoMath.map_to_local(base_vertex)
			
			var rm := get_node_or_null("/root/ResourceManager")
			var check: Dictionary = BuildingSystem.can_place_building(placing_building_type, cell, world_data, rm)
			if check["valid"]:
				ghost_building_sprite.modulate = Color(0.4, 1.3, 0.4, 0.8) # Green: Legal
			else:
				ghost_building_sprite.modulate = Color(1.5, 0.3, 0.3, 0.8) # Red: Blocked
	else:
		cursor_highlight.visible = false
		if ghost_building_node:
			ghost_building_node.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		var mouse_local := terrain_layer.get_local_mouse_position()
		var cell := IsoMath.local_to_map(mouse_local)
		
		if placing_building_type != "":
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_execute_placement(cell)
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_placement()
		else:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_check_citizen_click(cell)

func _check_citizen_click(cell: Vector2i) -> void:
	# Find closest citizen to the clicked cell
	var best_cit: Node = null
	var best_dist := 2 # Max distance 1 tile away
	
	for cit in citizen_list:
		var c_cell: Vector2i = cit.get("current_cell")
		var d := IsoMath.grid_distance(cell, c_cell)
		if d < best_dist:
			best_dist = d
			best_cit = cit
			
	if best_cit != null and hud != null:
		hud.show_citizen_inspector(best_cit)

func _on_citizen_role_changed(cid: String, new_role: String) -> void:
	var cit: Node = citizens_by_id.get(cid)
	if cit:
		cit.call("set_role", new_role)
		print("[WorldView] Reassigned %s to role: %s" % [cid, new_role])

func _on_build_requested(type: String) -> void:
	placing_building_type = type
	var tex: Texture2D = building_textures.get(type)
	if tex:
		ghost_building_sprite.texture = tex
		ghost_building_sprite.offset = _get_building_sprite_offset(type)
		ghost_building_node.visible = true

func _execute_placement(cell: Vector2i) -> void:
	var rm := get_node_or_null("/root/ResourceManager")
	var res: Dictionary = BuildingSystem.place_building(placing_building_type, cell, world_data, rm)
	
	if res["success"]:
		var b_data: Dictionary = res["building"]
		_instantiate_building_node(b_data["type"], b_data["cell"], b_data["size"])
		print("[WorldView] Successfully constructed %s at %s" % [b_data["type"], cell])
		_cancel_placement()
	else:
		print("[WorldView] Cannot place building: %s" % res["reason"])

func _cancel_placement() -> void:
	placing_building_type = ""
	if ghost_building_node:
		ghost_building_node.visible = false

func _get_terrain_name(type: int) -> String:
	match type:
		WorldGenerator.TerrainType.WATER: return "Mặt Nước (Không thể đi)"
		WorldGenerator.TerrainType.SAND: return "Bãi Cát"
		WorldGenerator.TerrainType.GRASS: return "Đồng Cỏ"
		WorldGenerator.TerrainType.DIRT: return "Đất Thổ"
		_: return "Không xác định"

func _get_building_display_name(key: String) -> String:
	match key:
		"townhall": return "Tòa Thị Chính (3x3)"
		"house": return "Nhà Ở (2x2)"
		"farm": return "Nông Trại (2x2)"
		"storehouse": return "Kho Lương (2x2)"
		"woodcutter": return "Trại Tiều Phu (2x2)"
		_: return ""

func _on_return_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
