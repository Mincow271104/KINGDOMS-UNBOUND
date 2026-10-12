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
	
	event_system = WorldEventSystem.new(world_seed)
	faction_mgr = FactionManager.new()
	immigration_mgr = ImmigrationManager.new(world_seed + 777)
	victory_mgr = VictoryManager.new()
	
	if hud:
		hud.set_research_manager(research_mgr)
		hud.set_faction_manager(faction_mgr, self)
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

func _spawn_pois() -> void:
	if poi_mgr == null:
		return
	for poi in poi_mgr.get_all_pois():
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
		
		props_container.add_child(p_node)
		poi_nodes_by_id[poi.id] = p_node

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
		var housing_cap: int = BuildingSystem.get_total_housing_capacity(world_data)
		if hud:
			hud.update_population_display(citizen_list.size(), housing_cap)
		var am = get_node_or_null("/root/AudioManager")
		if am:
			am.play_build()
		_cancel_placement()
	else:
		print("[WorldView] Cannot place building: %s" % res["reason"])
		var am = get_node_or_null("/root/AudioManager")
		if am:
			am.play_error()

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
