class_name WorldView
extends Node2D
## 64x64 Dimetric Isometric World View for KINGDOMS UNBOUND.
## Renders 2:1 isometric diamond terrain, starter buildings, props, citizens, and cursor highlight.
## Supports interactive building placement, citizen inspection, and job execution.

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
var workplace_mgr: WorkplaceManager
var automation_mgr: AutomationManager
var research_mgr: ResearchManager
var fog_of_war: FogOfWar
var poi_mgr: POIManager
var event_system: WorldEventSystem
var poi_nodes_by_id: Dictionary = {}
var faction_mgr: FactionManager
var active_caravan: RefCounted = null
var immigration_mgr: ImmigrationManager
var victory_mgr: VictoryManager
var autosave_enabled: bool = true
var autosave_interval_days: int = 1

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
		hud.world_view_ref = self
		hud.return_to_menu_requested.connect(_on_return_to_menu)
		hud.build_requested.connect(_on_build_requested)
		hud.citizen_role_changed.connect(_on_citizen_role_changed)
		
	# Connect to TimeManager simulation clock
	if Engine.has_singleton("TimeManager") or get_node_or_null("/root/TimeManager"):
		var tm = get_node("/root/TimeManager")
		tm.hour_passed.connect(_on_simulation_hour_passed)
		tm.day_passed.connect(_on_simulation_day_passed)
		
	# Focus camera on settlement plaza
	if camera:
		camera.focus_on_cell(Vector2i(32, 32))
		
	var am = get_node_or_null("/root/AudioManager")
	if am:
		am.start_ambient_music()
		
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
	building_textures["watchtower"] = load("res://assets/buildings/bld_watchtower.png")
	if ResourceLoader.exists("res://assets/buildings/bld_quarry.png"):
		building_textures["quarry"] = load("res://assets/buildings/bld_quarry.png")
	else:
		building_textures["quarry"] = building_textures.get("storehouse", null)
	if ResourceLoader.exists("res://assets/buildings/bld_mine.png"):
		building_textures["mine"] = load("res://assets/buildings/bld_mine.png")
	else:
		building_textures["mine"] = building_textures.get("storehouse", null)
	if ResourceLoader.exists("res://assets/buildings/bld_workshop.png"):
		building_textures["workshop"] = load("res://assets/buildings/bld_workshop.png")
	else:
		building_textures["workshop"] = building_textures.get("storehouse", null)
	if ResourceLoader.exists("res://assets/buildings/bld_research_hall.png"):
		building_textures["research_hall"] = load("res://assets/buildings/bld_research_hall.png")
	else:
		building_textures["research_hall"] = building_textures.get("townhall", null)
	if ResourceLoader.exists("res://assets/buildings/bld_barracks.png"):
		building_textures["barracks"] = load("res://assets/buildings/bld_barracks.png")
	else:
		building_textures["barracks"] = building_textures.get("townhall", null)
	
	prop_textures["tree"] = load("res://assets/props/prop_tree.png")
	prop_textures["rock"] = load("res://assets/props/prop_rock.png")
	prop_textures["poi_ruins"] = load("res://assets/props/prop_poi_ruins.png")
	
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
	workplace_mgr = WorkplaceManager.new()
	automation_mgr = AutomationManager.new()
	
	research_mgr = ResearchManager.new()
	research_mgr.set_hall_checker(func(): return BuildingSystem.is_research_hall_active(world_data))
	fog_of_war = FogOfWar.new(IsoMath.MAP_SIZE)
	fog_of_war.reveal_circle(Vector2i(32, 32), 10)
	
	poi_mgr = POIManager.new()
	var walkable: Array[Vector2i] = []
	for x in range(IsoMath.MAP_SIZE):
		for y in range(IsoMath.MAP_SIZE):
			var cell := Vector2i(x, y)
			if nav.is_walkable(cell):
				walkable.append(cell)
	poi_mgr.generate_pois(world_seed, walkable, 4)
	poi_mgr.poi_revealed.connect(_on_poi_revealed)
	
	event_system = WorldEventSystem.new(world_seed)
	faction_mgr = FactionManager.new()
	immigration_mgr = ImmigrationManager.new(world_seed + 777)
	victory_mgr = VictoryManager.new()
	
	job_mgr.set_barracks_checker(func(b_id: String = ""): return BuildingSystem.is_barracks_active(world_data, b_id))
	job_mgr.set_construction_checker(func(b_id: String = ""): return BuildingSystem.is_building_under_construction(world_data, b_id))
	if hud:
		hud.set_research_manager(research_mgr)
		hud.set_faction_manager(faction_mgr, self)
		hud.set_barracks_checker(func(b_id: String = ""): return BuildingSystem.is_barracks_active(world_data, b_id))
		victory_mgr.victory_achieved.connect(func(report: Dictionary): hud.show_victory_panel(report))
		victory_mgr.collapse_triggered.connect(func(report: Dictionary): hud.show_collapse_panel(report))
		victory_mgr.crisis_warning_issued.connect(func(warning: Dictionary): hud.show_crisis_warning(warning))
	
	_setup_workplaces()
	_create_workplace_jobs()
	_render_terrain()
	_spawn_starter_buildings()
	_spawn_props()
	_spawn_pois()
	_spawn_starter_citizens()

func _setup_workplaces() -> void:
	# Farm at (36, 35)
	workplace_mgr.register_workplace("farm_starter", "farm", Vector2i(36, 35), Vector2i(2, 2), Vector2i(35, 35), EconomyConfig.RES_FOOD, 50, 5.0, 5)
	# Woodcutter Camp at (26, 30)
	workplace_mgr.register_workplace("woodcutter_starter", "woodcutter", Vector2i(26, 30), Vector2i(2, 2), Vector2i(28, 30), EconomyConfig.RES_WOOD, 40, 4.0, 4)
	# Dropoffs: Storehouse (32, 27) and Town Hall (31, 31)
	workplace_mgr.register_dropoff("storehouse_starter", "storehouse", Vector2i(32, 29))
	workplace_mgr.register_dropoff("townhall_starter", "townhall", Vector2i(31, 34))

func _create_workplace_jobs() -> void:
	# Farm at (36, 35) generates 5 recurring farming jobs
	for i in range(5):
		var target := Vector2i(35 + (i % 2), 35 + int(float(i) / 2.0))
		job_mgr.create_job("farmer", target, "Chăm sóc và thu hoạch nông sản", "farm_starter", 3.0, 1, true)
		
	# Woodcutter Camp at (26, 30) generates 4 recurring woodcutter jobs
	for i in range(4):
		var target := Vector2i(25 + (i % 2), 29 + int(float(i) / 2.0))
		job_mgr.create_job("woodcutter", target, "Khai thác và chế biến gỗ", "woodcutter_starter", 3.0, 1, true)

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
		_instantiate_building_node(bld["type"], bld["cell"], bld["size"], bld.get("state", "active"))

func _instantiate_building_node(type: String, origin: Vector2i, size: Vector2i, state: String = "active") -> Node2D:
	var tex: Texture2D = building_textures.get(type)
	if not tex:
		return null
		
	var b_node := Node2D.new()
	b_node.name = "Building_%s_%d_%d" % [type, origin.x, origin.y]
	b_node.y_sort_enabled = true
	
	# Bottom center of footprint diamond for exact Y-sorting
	var base_vertex := origin + Vector2i(size.x - 1, size.y - 1)
	b_node.position = IsoMath.map_to_local(base_vertex)
	
	var spr := Sprite2D.new()
	spr.name = "Sprite2D"
	spr.texture = tex
	spr.centered = false
	spr.offset = _get_building_sprite_offset(type)
	if state == "under_construction":
		spr.modulate = Color(0.8, 0.7, 0.5, 0.7)
	else:
		spr.modulate = Color(1.0, 1.0, 1.0, 1.0)
			
	b_node.add_child(spr)
	buildings_container.add_child(b_node)
	
	# Register building footprint for tile inspection
	for ox in range(size.x):
		for oy in range(size.y):
			buildings_by_cell[origin + Vector2i(ox, oy)] = type

	return b_node

func _get_building_sprite_offset(type: String) -> Vector2:
	match type:
		"townhall": return Vector2(-48.0, -56.0)
		"research_hall": return Vector2(-48.0, -56.0)
		"barracks": return Vector2(-48.0, -56.0)
		"house": return Vector2(-32.0, -40.0)
		"storehouse": return Vector2(-32.0, -40.0)
		"farm": return Vector2(-32.0, -28.0)
		"woodcutter": return Vector2(-32.0, -36.0)
		"watchtower": return Vector2(-16.0, -40.0)
		"quarry": return Vector2(-32.0, -36.0)
		"mine": return Vector2(-32.0, -36.0)
		"workshop": return Vector2(-32.0, -36.0)
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

func _spawn_single_poi_node(poi: POIManager.POIData) -> Node2D:
	if poi == null:
		return null
	var p_node := Node2D.new()
	p_node.name = "POI_%s" % poi.id
	p_node.position = IsoMath.map_to_local(poi.cell)
	p_node.y_sort_enabled = true

	var spr := Sprite2D.new()
	spr.name = "Sprite2D"
	spr.texture = prop_textures.get("poi_ruins")
	spr.centered = false
	spr.offset = Vector2(-16.0, -24.0)
	p_node.add_child(spr)

	p_node.visible = (poi.state != POIManager.POIState.UNDISCOVERED)

	props_container.add_child(p_node)
	poi_nodes_by_id[poi.id] = p_node
	return p_node

func _spawn_pois() -> void:
	if poi_mgr == null:
		return
	for poi in poi_mgr.get_all_pois():
		_spawn_single_poi_node(poi)

func _on_poi_revealed(poi: POIManager.POIData) -> void:
	if poi == null:
		return
	var p_node: CanvasItem = poi_nodes_by_id.get(poi.id)
	if p_node == null:
		p_node = _spawn_single_poi_node(poi)
	if is_instance_valid(p_node):
		p_node.visible = true

func refresh_poi_visibility() -> void:
	if poi_mgr == null:
		return
	for poi in poi_mgr.get_all_pois():
		var p_node: CanvasItem = poi_nodes_by_id.get(poi.id)
		if p_node == null:
			p_node = _spawn_single_poi_node(poi)
		if is_instance_valid(p_node):
			p_node.visible = (poi.state != POIManager.POIState.UNDISCOVERED)

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
		
		cit.init_citizen(cid, cname, crole, cell, nav, job_mgr, workplace_mgr)
		cit.set_barracks_checker(func(b_id: String = ""): return BuildingSystem.is_barracks_active(world_data, b_id))
		cit.set_construction_checker(func(b_id: String = ""): return BuildingSystem.is_building_under_construction(world_data, b_id))
		cit.set_world_view(self)
		citizens_container.add_child(cit)
		
		citizens_by_id[cid] = cit
		citizen_list.append(cit)
		cit.citizen_died.connect(func(died_id: String): _on_citizen_died(died_id))

func _spawn_immigrant_wave(immigrants: Array) -> void:
	var citizen_tex = load("res://assets/entities/citizen.png")
	var rm = get_node_or_null("/root/ResourceManager")
	var em = get_node_or_null("/root/EventManager")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	
	for imm in immigrants:
		var cid: String = imm["id"]
		var cname: String = imm["name"]
		var crole: String = imm.get("role", "idle")
		
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
		
		cit.init_citizen(cid, cname, crole, cell, nav, job_mgr, workplace_mgr)
		cit.set_barracks_checker(func(b_id: String = ""): return BuildingSystem.is_barracks_active(world_data, b_id))
		cit.set_construction_checker(func(b_id: String = ""): return BuildingSystem.is_building_under_construction(world_data, b_id))
		cit.set_world_view(self)
		citizens_container.add_child(cit)
		
		citizens_by_id[cid] = cit
		citizen_list.append(cit)
		cit.citizen_died.connect(func(died_id: String): _on_citizen_died(died_id))
		
	if rm:
		rm.active_population = citizen_list.size()
	if em:
		em.trigger_event("immigration_arrived", "Đoàn Người Di Cư Đã Đến!", "Có %d người di cư mới gia nhập vương quốc!" % immigrants.size(), true, {})
	var housing_cap: int = BuildingSystem.get_total_housing_capacity(world_data)
	if hud:
		hud.update_population_display(citizen_list.size(), housing_cap)

func _on_citizen_died(died_id: String) -> void:
	var rm = get_node_or_null("/root/ResourceManager")
	var em = get_node_or_null("/root/EventManager")
	var cit = citizens_by_id.get(died_id)
	if cit:
		citizen_list.erase(cit)
		citizens_by_id.erase(died_id)
		if is_instance_valid(cit):
			cit.queue_free()
	if rm:
		rm.active_population = citizen_list.size()
	if em:
		em.trigger_event("citizen_died", "Tang Lễ Vương Quốc", "Một cư dân đã qua đời do nạn đói hoặc kiệt sức.", false, {})
	var housing_cap: int = BuildingSystem.get_total_housing_capacity(world_data)
	if hud:
		hud.update_population_display(citizen_list.size(), housing_cap)

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
			var bld := _get_building_at_cell(cell)
			if not bld.is_empty() and bld.get("state", "") == "under_construction":
				var prog: float = float(bld.get("construction_progress", 0.0))
				var total: float = float(bld.get("construction_hours", 12.0))
				var pct: int = int((prog / total) * 100.0) if total > 0.0 else 0
				b_name += " [Đang xây: %d%%]" % pct
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
		if new_role == "guard" and not BuildingSystem.is_barracks_active(world_data):
			print("[WorldView] Cannot assign %s to guard: no active barracks" % cid)
			return
		cit.call("set_role", new_role)
		print("[WorldView] Reassigned %s to role: %s" % [cid, new_role])

func _on_build_requested(type: String) -> void:
	placing_building_type = type
	var tex: Texture2D = building_textures.get(type)
	if tex:
		ghost_building_sprite.texture = tex
		ghost_building_sprite.offset = _get_building_sprite_offset(type)
		ghost_building_node.visible = true

func _execute_placement(cell: Vector2i) -> Dictionary:
	var rm := get_node_or_null("/root/ResourceManager")
	var res: Dictionary = BuildingSystem.place_building(placing_building_type, cell, world_data, rm, "under_construction")
	
	if res["success"]:
		var b_data: Dictionary = res["building"]
		_instantiate_building_node(b_data["type"], b_data["cell"], b_data["size"], "under_construction")
		print("[WorldView] Successfully placed construction site for %s at %s" % [b_data["type"], cell])

		# Register builder jobs for the construction site
		register_construction_jobs(b_data)

		var am = get_node_or_null("/root/AudioManager")
		if am:
			am.play_build()
		_cancel_placement()
	else:
		print("[WorldView] Cannot place building: %s" % res["reason"])
		var am = get_node_or_null("/root/AudioManager")
		if am:
			am.play_error()

	return res

func register_construction_jobs(b_data: Dictionary) -> Array[JobManager.JobData]:
	var result: Array[JobManager.JobData] = []
	if job_mgr == null or world_data == null or b_data.is_empty():
		return result

	var b_id: String = b_data.get("id", "")
	var b_type: String = b_data.get("type", "")
	var origin: Vector2i = b_data.get("cell", Vector2i.ZERO)
	var size: Vector2i = b_data.get("size", Vector2i(1, 1))

	var capacity: int = BuildingSystem.get_construction_worker_capacity(b_type)
	var perimeter: Array[Vector2i] = BuildingSystem.find_perimeter_cells(origin, size, world_data, capacity)
	var job_count: int = mini(capacity, perimeter.size())

	for i in range(job_count):
		var target_cell: Vector2i = perimeter[i]
		var job = job_mgr.create_job(
			"builder",
			target_cell,
			"Thi công xây dựng %s" % _get_building_display_name(b_type),
			b_id,
			float(b_data.get("construction_hours", 12.0)),
			2,
			false
		)
		result.append(job)

	return result

func advance_construction_work(b_id: String, delta_hours: float) -> Dictionary:
	if world_data == null:
		return {"success": false, "completed": false, "progress": 0.0, "hours": 0.0}

	var res := BuildingSystem.advance_construction(b_id, delta_hours, world_data)
	if not res.get("success", false):
		return res

	if res.get("completed", false):
		complete_construction(b_id)

	return res

func complete_construction(b_id: String) -> bool:
	if world_data == null or b_id == "":
		return false

	var b_data: Dictionary = BuildingSystem.get_building_by_id(b_id, world_data)
	if b_data.is_empty():
		return false

	if b_data.get("state", "") != "under_construction":
		return false # Idempotent: cannot complete if already active or other state

	var rm := get_node_or_null("/root/ResourceManager")
	var success := BuildingSystem.complete_building(b_data, world_data, rm)
	if not success:
		return false

	# 1. Update visual: clear scaffolding / amber modulate back to normal Color(1, 1, 1, 1)
	var origin: Vector2i = b_data.get("cell", Vector2i.ZERO)
	var b_type: String = b_data.get("type", "")
	var node_name := "Building_%s_%d_%d" % [b_type, origin.x, origin.y]
	var b_node = buildings_container.get_node_or_null(node_name)
	if b_node:
		var spr: Sprite2D = b_node.get_node_or_null("Sprite2D")
		if spr == null:
			for child in b_node.get_children():
				if child is Sprite2D:
					spr = child
					break
		if spr:
			spr.modulate = Color(1.0, 1.0, 1.0, 1.0)

	# 2. Release & complete builder jobs and workers for this building
	if job_mgr:
		var b_jobs := job_mgr.get_jobs_for_building(b_id)
		for j in b_jobs:
			if j.type == "builder":
				job_mgr.complete_job(j)
		job_mgr.remove_jobs_for_building(b_id)

	for cit in citizen_list:
		if cit.get("active_job") != null and cit.active_job.target_building_id == b_id:
			cit.active_job = null
			cit.set("current_state", CitizenController.State.IDLE)
			if cit.has_method("_update_reason"):
				cit.call("_update_reason")

	# 3. Operational integrations (activated exactly once)
	var housing_cap: int = BuildingSystem.get_total_housing_capacity(world_data)
	if hud:
		hud.update_population_display(citizen_list.size(), housing_cap)

	# If farm, woodcutter, quarry, mine, or workshop, register dynamic workplace
	if b_data["type"] in ["farm", "woodcutter", "quarry", "mine", "workshop"]:
		register_dynamic_workplace(b_data)

	# If watchtower, reveal vision and update POI discovery
	if b_data["type"] == "watchtower" and fog_of_war != null:
		var bp: Dictionary = EconomyConfig.BLUEPRINTS.get("watchtower", {})
		var v_rad: int = bp.get("vision_radius", 15)
		fog_of_war.reveal_circle(b_data["cell"], v_rad)
		if poi_mgr != null:
			poi_mgr.update_discovery(fog_of_war)

	# If research_hall, refresh research UI in hud
	if b_data["type"] == "research_hall" and hud != null:
		hud.call("_refresh_research_ui")

	# If barracks, register guard jobs and refresh hud role options
	if b_data["type"] == "barracks":
		register_barracks_jobs(b_data)
		if hud != null and hud.has_method("_refresh_role_options"):
			hud.call("_refresh_role_options")

	var am = get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_build"):
		am.play_build()

	print("[WorldView] Construction completed for %s (%s)" % [b_id, b_data.get("type", "")])
	return true

func cancel_construction_project(b_id: String) -> Dictionary:
	if world_data == null:
		return {"success": false, "reason": "Dữ liệu thế giới rỗng"}

	var b_data: Dictionary = BuildingSystem.get_building_by_id(b_id, world_data)
	if b_data.is_empty():
		return {"success": false, "reason": "Công trình không tồn tại"}

	var rm := get_node_or_null("/root/ResourceManager")
	var res := BuildingSystem.cancel_construction(b_data, world_data, rm, job_mgr)
	if not res.get("success", false):
		return res

	# Free visual node
	var origin: Vector2i = b_data.get("cell", Vector2i.ZERO)
	var size: Vector2i = b_data.get("size", Vector2i(1, 1))
	var type: String = b_data.get("type", "")
	var node_name := "Building_%s_%d_%d" % [type, origin.x, origin.y]
	var b_node = buildings_container.get_node_or_null(node_name)
	if b_node:
		b_node.queue_free()

	for ox in range(size.x):
		for oy in range(size.y):
			buildings_by_cell.erase(origin + Vector2i(ox, oy))

	# Release any citizens assigned to this building
	for cit in citizen_list:
		if cit.get("active_job") != null and cit.active_job.target_building_id == b_id:
			cit.active_job = null
			cit.set("current_state", CitizenController.State.IDLE)
			if cit.has_method("_update_reason"):
				cit.call("_update_reason")

	return res

func _get_building_at_cell(cell: Vector2i) -> Dictionary:
	if world_data == null:
		return {}
	for b in world_data.buildings:
		var origin: Vector2i = b.get("cell", Vector2i(-1, -1))
		var size: Vector2i = b.get("size", Vector2i(1, 1))
		if cell.x >= origin.x and cell.x < origin.x + size.x and cell.y >= origin.y and cell.y < origin.y + size.y:
			return b
	return {}

func register_dynamic_workplace(b_data: Dictionary) -> WorkplaceManager.WorkplaceData:
	if workplace_mgr == null or job_mgr == null or world_data == null:
		return null

	var b_type: String = b_data.get("type", "")
	if not b_type in ["farm", "woodcutter", "quarry", "mine", "workshop"]:
		return null

	var origin: Vector2i = b_data.get("cell", Vector2i.ZERO)
	var size: Vector2i = b_data.get("size", Vector2i(2, 2))
	var b_id: String = b_data.get("id", "")
	if b_id == "":
		b_id = "bld_%s_%d_%d" % [b_type, origin.x, origin.y]
		b_data["id"] = b_id

	# Prevent duplicate workplace registration
	var existing: WorkplaceManager.WorkplaceData = workplace_mgr.get_workplace(b_id)
	if existing != null:
		return existing

	var access_cell: Vector2i = BuildingSystem.find_access_cell(origin, size, world_data)
	if access_cell == Vector2i(-1, -1):
		printerr("[WorldView] Cannot register workplace for %s: no valid access cell" % b_id)
		return null

	if b_type == "workshop":
		var bp: Dictionary = EconomyConfig.BLUEPRINTS.get("workshop", {})
		var recipes: Dictionary = bp.get("recipes", {})
		var job_type: String = bp.get("job_type", "smith")

		var primary_wp: WorkplaceManager.WorkplaceData = null

		# Register independent recipe channels directly from EconomyConfig recipe definitions
		for r_key in recipes:
			var r_data: Dictionary = recipes[r_key]
			var r_id: String = r_data.get("id", r_key)
			var r_inputs: Dictionary = r_data.get("inputs", {})
			var r_output: String = r_data.get("output", "")
			var r_output_amount: int = int(r_data.get("output_amount", 1))
			var r_capacity: int = int(r_data.get("buffer_capacity", 40))
			var r_quota: int = int(r_data.get("worker_quota", 2))

			# Preserve stable channel IDs ending in _smelt and _craft
			var ch_suffix := "_smelt" if r_id == "smelt_metal" else ("_craft" if r_id == "craft_tools" else "_" + r_id)
			var ch_id := b_id + ch_suffix

			var wp_ch: WorkplaceManager.WorkplaceData = workplace_mgr.register_workplace(
				ch_id,
				b_type,
				origin,
				size,
				access_cell,
				r_output,
				r_capacity,
				1.0, # base prod
				r_quota,
				b_id, # parent_id
				r_id,
				r_inputs,
				r_output_amount
			)
			if primary_wp == null:
				primary_wp = wp_ch

		# Create recurring smith jobs from configured recipes if not already present
		var existing_jobs := job_mgr.get_jobs_for_building(b_id)
		if existing_jobs.is_empty():
			for r_key in recipes:
				var r_data: Dictionary = recipes[r_key]
				var r_id: String = r_data.get("id", r_key)
				var r_name: String = r_data.get("name_vi", "")
				var r_duration: float = float(r_data.get("duration_hours", 3.0))
				var r_quota: int = int(r_data.get("worker_quota", 2))
				var ch_suffix := "_smelt" if r_id == "smelt_metal" else ("_craft" if r_id == "craft_tools" else "_" + r_id)
				var ch_id := b_id + ch_suffix
				var desc: String = "Luyện kim loại từ quặng thô" if r_id == "smelt_metal" else ("Rèn công cụ từ kim loại và gỗ" if r_id == "craft_tools" else ("Chế tác: " + r_name))
				for i in range(r_quota):
					job_mgr.create_job(job_type, access_cell, desc, b_id, r_duration, 1, true, r_id, ch_id)

		print("[WorldView] Registered dynamic workshop '%s' with %d recipe channels at %s" % [b_id, recipes.size(), access_cell])
		return primary_wp

	var bp: Dictionary = EconomyConfig.BLUEPRINTS.get(b_type, {})
	var max_workers: int = bp.get("max_workers", 1)
	var job_type: String = bp.get("job_type", "")
	var out_res: String = bp.get("output_resource", "")
	var capacity: int = 50 if b_type == "farm" else 40
	var base_prod: float = 5.0 if b_type == "farm" else 4.0

	var wp: WorkplaceManager.WorkplaceData = workplace_mgr.register_workplace(
		b_id, b_type, origin, size, access_cell, out_res, capacity, base_prod, max_workers
	)

	# Create recurring jobs if not already present
	var existing_jobs := job_mgr.get_jobs_for_building(b_id)
	if existing_jobs.is_empty():
		var desc: String = "Chăm sóc và thu hoạch nông sản" if b_type == "farm" else ("Khai thác và chế biến gỗ" if b_type == "woodcutter" else ("Khai thác đá tảng tại mỏ đá" if b_type == "quarry" else "Khai thác quặng thô tại mỏ quặng"))
		for i in range(max_workers):
			job_mgr.create_job(job_type, access_cell, desc, b_id, 3.0, 1, true)

	print("[WorldView] Registered dynamic workplace '%s' (%s) with %d jobs at %s" % [b_id, b_type, max_workers, access_cell])
	return wp

func register_barracks_jobs(b_data: Dictionary, p_world_data: WorldGenerator.WorldData = null) -> Array[JobManager.JobData]:
	var w_data: WorldGenerator.WorldData = p_world_data if p_world_data != null else world_data
	var result: Array[JobManager.JobData] = []
	if job_mgr == null or w_data == null:
		return result

	# Inactive barracks do not receive executable guard jobs
	if b_data.get("state", "active") != "active":
		return result

	var b_id: String = b_data.get("id", "")
	var origin: Vector2i = b_data.get("cell", Vector2i.ZERO)
	var size: Vector2i = b_data.get("size", Vector2i(3, 3))
	if b_id == "":
		b_id = "bld_barracks_%d_%d" % [origin.x, origin.y]
		b_data["id"] = b_id

	# Avoid duplicate jobs if already created
	var existing_jobs := job_mgr.get_jobs_for_building(b_id)
	if not existing_jobs.is_empty():
		return existing_jobs

	# Collect guard posts already in use by other buildings to avoid conflicting positions
	var occupied_guard_posts: Array = []
	for j in job_mgr.get_all_jobs():
		if j.type == "guard" and j.target_building_id != b_id:
			occupied_guard_posts.append(j.target_cell)

	var bp: Dictionary = EconomyConfig.BLUEPRINTS.get("barracks", {})
	var guard_capacity: int = bp.get("guard_capacity", 2)
	var perimeter_cells := BuildingSystem.find_perimeter_cells(origin, size, w_data, guard_capacity, occupied_guard_posts)

	# Strictly create at most mini(guard_capacity, perimeter_cells.size()) jobs
	# Do NOT duplicate cells or fall back to duplicate posts
	var num_jobs: int = mini(guard_capacity, perimeter_cells.size())
	for i in range(num_jobs):
		var target_cell: Vector2i = perimeter_cells[i]
		var desc := "Tuần tra và canh gác tại Doanh Trại (Vị trí %d)" % (i + 1)
		var job := job_mgr.create_job("guard", target_cell, desc, b_id, 4.0, 2, true)
		result.append(job)

	print("[WorldView] Registered %d guard jobs for barracks '%s'" % [result.size(), b_id])
	return result

func sync_workplaces_after_load(saved_workplaces_data: Dictionary = {}) -> void:
	if workplace_mgr == null or job_mgr == null or world_data == null:
		return

	var starter_ids: Array[String] = ["farm_starter", "woodcutter_starter"]

	# 1. Clear dynamic workplaces and dynamic jobs
	workplace_mgr.clear_dynamic_workplaces(starter_ids)
	job_mgr.clear_dynamic_jobs(starter_ids)

	# Reset all existing workplace buffers to 0 first (ensures legacy saves default to 0)
	for wp in workplace_mgr.get_all_workplaces():
		wp.buffer_amount = 0

	# 2. Re-register dynamic workplaces, barracks jobs, or construction jobs from world_data.buildings
	for b in world_data.buildings:
		var b_type: String = b.get("type", "")
		var b_state: String = b.get("state", "active")
		if b_state == "under_construction":
			register_construction_jobs(b)
		elif b_type in ["farm", "woodcutter", "quarry", "mine", "workshop"]:
			var b_cell: Vector2i = b.get("cell", Vector2i.ZERO)
			# Skip starter workplaces
			if (b_type == "farm" and b_cell == Vector2i(36, 35)) or (b_type == "woodcutter" and b_cell == Vector2i(26, 30)) or b.get("id", "") in starter_ids:
				continue
			register_dynamic_workplace(b)
		elif b_type == "barracks":
			if b_state == "active":
				register_barracks_jobs(b)

	# 3. Restore buffer amounts
	if saved_workplaces_data is Dictionary and not saved_workplaces_data.is_empty():
		for wp_id in saved_workplaces_data:
			var entry = saved_workplaces_data[wp_id]

			# Format 3: Nested dictionary by parent building ID (e.g. {"metal": 14, "tools": 9})
			if entry is Dictionary and (entry.has("metal") or entry.has("tools")):
				var smelt_ch = workplace_mgr.get_workplace(wp_id + "_smelt")
				if smelt_ch == null:
					smelt_ch = workplace_mgr.get_workplace_channel(wp_id, "smelt_metal")
				if smelt_ch != null and entry.has("metal"):
					smelt_ch.buffer_amount = clampi(int(entry["metal"]), 0, smelt_ch.buffer_capacity)
					workplace_mgr.buffer_changed.emit(smelt_ch.id, smelt_ch.buffer_amount, smelt_ch.buffer_capacity)

				var craft_ch = workplace_mgr.get_workplace(wp_id + "_craft")
				if craft_ch == null:
					craft_ch = workplace_mgr.get_workplace_channel(wp_id, "craft_tools")
				if craft_ch != null and entry.has("tools"):
					craft_ch.buffer_amount = clampi(int(entry["tools"]), 0, craft_ch.buffer_capacity)
					workplace_mgr.buffer_changed.emit(craft_ch.id, craft_ch.buffer_amount, craft_ch.buffer_capacity)
				continue

			# Format 1: Exact channel ID or single-workplace building ID
			var wp = workplace_mgr.get_workplace(wp_id)
			if wp != null and wp.id == wp_id:
				var saved_buf: int = 0
				if entry is Dictionary:
					saved_buf = int(entry.get("buffer_amount", 0))
				elif entry is int or entry is float:
					saved_buf = int(entry)
				wp.buffer_amount = clampi(saved_buf, 0, wp.buffer_capacity)
				workplace_mgr.buffer_changed.emit(wp.id, wp.buffer_amount, wp.buffer_capacity)
			else:
				# Format 2: Backward compatibility for parent building ID with integer or single buffer_amount
				var smelt_ch = workplace_mgr.get_workplace(wp_id + "_smelt")
				if smelt_ch == null:
					smelt_ch = workplace_mgr.get_workplace_channel(wp_id, "smelt_metal")
				if smelt_ch != null:
					var saved_buf: int = 0
					if entry is Dictionary:
						saved_buf = int(entry.get("buffer_amount", 0))
					elif entry is int or entry is float:
						saved_buf = int(entry)
					smelt_ch.buffer_amount = clampi(saved_buf, 0, smelt_ch.buffer_capacity)
					workplace_mgr.buffer_changed.emit(smelt_ch.id, smelt_ch.buffer_amount, smelt_ch.buffer_capacity)

	if hud != null and hud.has_method("_refresh_role_options"):
		hud.call("_refresh_role_options")

func _cancel_placement() -> void:
	placing_building_type = ""
	if ghost_building_node:
		ghost_building_node.visible = false
	var am = get_node_or_null("/root/AudioManager")
	if am:
		am.play_click()

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
		"watchtower": return "Tháp Canh (1x1)"
		"quarry": return "Mỏ Khai Thác Đá (2x2)"
		"mine": return "Mỏ Khai Thác Quặng (2x2)"
		"workshop": return "Xưởng Chế Tác (2x2)"
		"research_hall": return "Viện Nghiên Cứu Hoàng Gia (3x3)"
		"barracks": return "Doanh Trại (3x3)"
		_: return ""

func _on_return_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _on_simulation_hour_passed(hour: int, day: int) -> void:
	var rm = get_node_or_null("/root/ResourceManager")
	
	# Progress active research project
	if research_mgr != null:
		research_mgr.progress_research(1.0, rm)
		
	# Update citizen vision and fog of war
	if fog_of_war != null:
		for cit in citizen_list:
			var c_cell: Vector2i = cit.get("current_cell")
			fog_of_war.reveal_circle(c_cell, 4)
			
		# Maintain active watchtowers vision
		if world_data != null and world_data.get("buildings") != null:
			for b in world_data.buildings:
				if b.get("type") == "watchtower" and b.get("state", "active") != "destroyed":
					var b_cell: Vector2i = b.get("cell", Vector2i.ZERO)
					var bp: Dictionary = EconomyConfig.BLUEPRINTS.get("watchtower", {})
					var v_rad: int = bp.get("vision_radius", 15)
					fog_of_war.reveal_circle(b_cell, v_rad)

	# Update POI discovery
	if poi_mgr != null and fog_of_war != null:
		poi_mgr.update_discovery(fog_of_war)
		# Proximity check for claiming rewards
		for poi in poi_mgr.get_all_pois():
			if poi.state != POIManager.POIState.CLAIMED:
				for cit in citizen_list:
					var c_cell: Vector2i = cit.get("current_cell")
					if IsoMath.grid_distance(c_cell, poi.cell) <= 2:
						poi_mgr.claim_poi_reward(poi.id, rm)
						break
						
	if workplace_mgr != null and job_mgr != null:
		workplace_mgr.update_hauling_jobs(job_mgr)
		if automation_mgr != null:
			var tm = get_node_or_null("/root/TimeManager")
			var season: String = tm.get_season_name() if tm else "spring"
			automation_mgr.evaluate_rules(rm, job_mgr, workplace_mgr, season)

	# Hourly Immigration & Victory/Crisis Evaluation
	var housing_cap: int = BuildingSystem.get_total_housing_capacity(world_data)
	var town_hall_alive: bool = BuildingSystem.is_town_hall_active(world_data)
	var current_pop: int = citizen_list.size()
	var food_stock: int = rm.get_available_stock("food") if rm else 0
	var gold_stock: int = rm.get_available_stock("gold") if rm else 0
	var techs_count: int = research_mgr.get_unlocked_count() if research_mgr else 0
	var buildings_count: int = world_data.buildings.size() if world_data else 0

	var avg_morale: float = 70.0
	if not citizen_list.is_empty():
		var total_m: float = 0.0
		for cit in citizen_list:
			total_m += cit.get("morale") if cit.get("morale") != null else 70.0
		avg_morale = total_m / float(citizen_list.size())

	if hud:
		hud.update_population_display(current_pop, housing_cap)

	if immigration_mgr != null and immigration_mgr.can_evaluate_today(day, hour):
		var stability_est := 75.0
		if victory_mgr != null:
			stability_est = victory_mgr.calculate_stability(food_stock, gold_stock, current_pop, housing_cap, avg_morale, town_hall_alive)
		var imm_res: Dictionary = immigration_mgr.evaluate_immigration(housing_cap, current_pop, food_stock, stability_est, avg_morale, day)
		if imm_res["allowed"] and not imm_res["immigrants"].is_empty():
			_spawn_immigrant_wave(imm_res["immigrants"])

	if victory_mgr != null:
		var stability: float = victory_mgr.calculate_stability(food_stock, gold_stock, current_pop, housing_cap, avg_morale, town_hall_alive)
		victory_mgr.tick_hourly(current_pop, food_stock, gold_stock, stability, avg_morale, techs_count, town_hall_alive, buildings_count)

func _on_simulation_day_passed(day: int, _season: String, _year: int) -> void:
	var rm = get_node_or_null("/root/ResourceManager")
	var em = get_node_or_null("/root/EventManager")
	
	if event_system != null:
		event_system.check_and_trigger_event(day, rm, em)
		
	# Update daily faction simulation
	if faction_mgr != null:
		faction_mgr.update_daily_simulation(day)
		
	# Scheduled visiting trade caravan arrivals (Every 5 days, starting Day 3)
	if (day % 5 == 3) and (active_caravan == null or not active_caravan.get("is_active")):
		active_caravan = TradeCaravan.generate_caravan(world_seed, day, "rival_merchant")
		if em != null:
			em.trigger_event("caravan_arrived", "Thương Đoàn Ghé Thăm!", "%s đã cập bến quảng trường định cư!" % active_caravan.get("name"), true, {})
			
	# Check caravan departure
	if active_caravan != null and day >= active_caravan.get("departure_day"):
		active_caravan.set("is_active", false)
		active_caravan = null

	# Daily Autosave
	if autosave_enabled and (day % autosave_interval_days == 0):
		var asave_res := SaveManager.save_to_file(self, SaveManager.DEFAULT_SAVE_PATH)
		if asave_res.get("success", false) and em != null:
			em.trigger_event("autosave", "Tự Động Lưu", "Đã tự động lưu thế giới an toàn (Ngày %d)." % day, true, {})
