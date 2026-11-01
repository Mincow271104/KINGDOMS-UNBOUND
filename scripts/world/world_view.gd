class_name WorldView
extends Node2D
## 64x64 Dimetric Isometric World View for KINGDOMS UNBOUND.
## Renders 2:1 isometric diamond terrain, starter buildings, props, citizens, and cursor highlight.
## Supports interactive building placement, citizen inspection, and job execution.

const CitizenControllerScript = preload("res://scripts/entities/citizen_controller.gd")
const BattleCampaignManagerScript = preload("res://scripts/combat/battle_campaign_manager.gd")
const PlayerArmyManagerScript = preload("res://scripts/military/player_army_manager.gd")
const TacticalMilitaryManagerScript = preload("res://scripts/military/tactical_military_manager.gd")
const ArmyMarkerScript = preload("res://scripts/military/army_marker.gd")
const CaravanMarkerScript = preload("res://scripts/trade/caravan_marker.gd")
const EnemyMilitaryManagerScript = preload("res://scripts/military/enemy_military_manager.gd")
const FieldSiegeManagerScript = preload("res://scripts/combat/field_siege_manager.gd")
const LegacyProfileManagerScript = preload("res://scripts/legacy/legacy_profile_manager.gd")

@export var world_seed: int = 12345
@export var world_id: String = ""
var is_world_id_persisted: bool = false
static var _world_id_counter: int = 0

static func generate_unique_world_id(seed_val: int = 0) -> String:
	_world_id_counter += 1
	var unix_t: int = int(Time.get_unix_time_from_system()) if Time else 0
	var ticks_usec: int = Time.get_ticks_usec() if Time else 0
	var rand_val: int = randi() & 0xFFFFFFFF
	return "world_%d_%d_%d_%d_%x" % [seed_val, unix_t, ticks_usec, _world_id_counter, rand_val]

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
var battle_campaign_mgr: RefCounted = null
var player_army_mgr: RefCounted = null
var tactical_military_mgr: RefCounted = null
var enemy_military_mgr: RefCounted = null
var field_siege_mgr: RefCounted = null
var army_marker: Node2D = null
var caravan_marker: Node2D = null
var autosave_enabled: bool = true
var autosave_interval_days: int = 1

# Tactical Box Selection State (Package 1W)
var _selection_box_layer: CanvasLayer = null
var _selection_box_control: Control = null
var _is_left_mouse_down: bool = false
var _is_drag_box_active: bool = false
var _drag_start_screen: Vector2 = Vector2.ZERO
var _drag_current_screen: Vector2 = Vector2.ZERO

# Building Inspection & Selection State (Package 2F)
const BuildingSelectionHighlightScript = preload("res://scripts/world/building_selection_highlight.gd")
var selected_building_id: String = ""
var building_highlight: Node2D = null

var buildings_by_cell: Dictionary = {} # cell (Vector2i) -> building_type (String)
var citizens_by_id: Dictionary = {}
var deceased_citizen_ids: Dictionary = {}
var citizen_list: Array = []
var terrain_textures: Dictionary = {}
var building_textures: Dictionary = {}
var prop_textures: Dictionary = {}

var placing_building_type: String = ""
var ghost_building_node: Node2D
var ghost_building_sprite: Sprite2D

func _ready() -> void:
	DisplayServer.window_set_min_size(Vector2i(1024, 576))
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
	if ResourceLoader.exists("res://assets/buildings/bld_palisade.png"):
		building_textures["palisade"] = load("res://assets/buildings/bld_palisade.png")
	else:
		building_textures["palisade"] = building_textures.get("woodcutter", null)
	if ResourceLoader.exists("res://assets/buildings/bld_market.png"):
		building_textures["market"] = load("res://assets/buildings/bld_market.png")
	else:
		building_textures["market"] = building_textures.get("townhall", null)
	
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
	var rm_init = get_node_or_null("/root/ResourceManager")
	if rm_init != null and rm_init.has_method("reset_economy"):
		rm_init.reset_economy()
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
	if world_id.strip_edges().is_empty():
		world_id = generate_unique_world_id(world_seed)
		is_world_id_persisted = false
	victory_mgr = VictoryManager.new()
	victory_mgr.profile_mgr = LegacyProfileManagerScript.get_instance()
	victory_mgr.world_id = world_id
	victory_mgr.is_world_id_persisted = is_world_id_persisted
	victory_mgr.resource_mgr = get_node_or_null("/root/ResourceManager")
	battle_campaign_mgr = BattleCampaignManagerScript.new(self, faction_mgr, world_seed)
	player_army_mgr = PlayerArmyManagerScript.new(self)
	tactical_military_mgr = TacticalMilitaryManagerScript.new(self, player_army_mgr)
	player_army_mgr.set_tactical_military_manager(tactical_military_mgr)
	enemy_military_mgr = EnemyMilitaryManagerScript.new(self, faction_mgr)
	field_siege_mgr = FieldSiegeManagerScript.new(self, faction_mgr, player_army_mgr, enemy_military_mgr)
	enemy_military_mgr.set_field_siege_manager(field_siege_mgr)
	enemy_military_mgr.set_tactical_military_manager(tactical_military_mgr)
	var rm_node = get_node_or_null("/root/ResourceManager")
	if rm_node != null:
		field_siege_mgr.set_resource_manager(rm_node)
	field_siege_mgr.field_siege_resolved.connect(func(_sid: String, outcome: String, _details: Dictionary):
		if hud != null:
			if outcome == "VICTORY":
				hud.show_event_banner("Chiến Thắng Công Thành!", "Đã chiếm thành công tiền đồn địch! Thu được chiến lợi phẩm phong phú.", true, 5.0)
			elif outcome == "DEFEAT":
				hud.show_event_banner("Thất Bại Công Thành!", "Toàn bộ lực lượng công thành đã bị đẩy lui.", false, 5.0)
	)
	_setup_selection_box_overlay()

	# Building Selection Footprint Highlight (Package 2F)
	building_highlight = BuildingSelectionHighlightScript.new()
	building_highlight.name = "BuildingSelectionHighlight"
	building_highlight.z_index = 5
	$World.add_child(building_highlight)

	job_mgr.set_barracks_checker(func(b_id: String = ""): return BuildingSystem.is_barracks_active(world_data, b_id))
	job_mgr.set_construction_checker(func(b_id: String = ""): return BuildingSystem.is_building_under_construction(world_data, b_id))
	job_mgr.set_building_checker(Callable(self, "_is_building_active_for_jobs"))
	if hud:
		hud.set_research_manager(research_mgr)
		hud.set_faction_manager(faction_mgr, self)
		hud.set_battle_campaign_manager(battle_campaign_mgr)
		hud.set_player_army_manager(player_army_mgr)
		if hud.has_method("set_tactical_military_manager"):
			hud.set_tactical_military_manager(tactical_military_mgr)
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
	_setup_army_marker()
	refresh_caravan_marker()
	_setup_default_siege_objectives()

	if faction_mgr != null:
		if faction_mgr.has_signal("war_declared") and not faction_mgr.war_declared.is_connected(_on_faction_war_declared):
			faction_mgr.war_declared.connect(_on_faction_war_declared)
		if faction_mgr.has_signal("peace_signed") and not faction_mgr.peace_signed.is_connected(_on_faction_peace_signed):
			faction_mgr.peace_signed.connect(_on_faction_peace_signed)

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
		if not bld.has("id") or bld["id"] == "":
			var b_type: String = bld.get("type", "")
			var b_cell: Vector2i = bld.get("cell", Vector2i.ZERO)
			if b_type == "farm" and b_cell == Vector2i(36, 35):
				bld["id"] = "farm_starter"
			elif b_type == "woodcutter" and b_cell == Vector2i(26, 30):
				bld["id"] = "woodcutter_starter"
			elif b_type == "townhall":
				bld["id"] = "townhall_starter"
			elif b_type == "storehouse":
				bld["id"] = "storehouse_starter"
			else:
				bld["id"] = "bld_%s_%d_%d" % [b_type, b_cell.x, b_cell.y]
		if not bld.has("state"):
			bld["state"] = "active"
		if not bld.has("health"):
			bld["health"] = 100
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
	elif state == "paused":
		spr.modulate = Color(0.7, 0.7, 0.7, 0.85)
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
		"market": return Vector2(-48.0, -56.0)
		"house": return Vector2(-32.0, -40.0)
		"storehouse": return Vector2(-32.0, -40.0)
		"farm": return Vector2(-32.0, -28.0)
		"woodcutter": return Vector2(-32.0, -36.0)
		"watchtower": return Vector2(-16.0, -40.0)
		"quarry": return Vector2(-32.0, -36.0)
		"mine": return Vector2(-32.0, -36.0)
		"workshop": return Vector2(-32.0, -36.0)
		"palisade": return Vector2(-16.0, -28.0)
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
	deceased_citizen_ids.clear()
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
	if died_id == "" or deceased_citizen_ids.has(died_id):
		return # Idempotent: already processed death for this citizen ID

	var cit = citizens_by_id.get(died_id)
	if cit == null:
		return # Missing or already removed citizen ID; do not fabricate events

	deceased_citizen_ids[died_id] = true

	var rm = get_node_or_null("/root/ResourceManager")
	var em = get_node_or_null("/root/EventManager")
	var is_combat_death: bool = false
	var explicit_cause: String = String(cit.get("death_cause")) if cit.get("death_cause") != null else ""
	if explicit_cause == "combat":
		is_combat_death = true
	elif explicit_cause.is_empty():
		var status_reason: String = String(cit.get("status_reason"))
		if status_reason.contains("Tử trận"):
			is_combat_death = true

	citizen_list.erase(cit)
	citizens_by_id.erase(died_id)
	if is_instance_valid(cit):
		cit.queue_free()

	if rm:
		rm.active_population = citizen_list.size()
	if em:
		if is_combat_death:
			em.trigger_event("citizen_died", "Chiến Binh Tử Trận", "Một vệ binh đã anh dũng hy sinh khi bảo vệ định cư trong trận chiến.", false, {"citizen_id": died_id, "cause": "combat"})
		else:
			em.trigger_event("citizen_died", "Tang Lễ Vương Quốc", "Một cư dân đã qua đời do nạn đói hoặc kiệt sức.", false, {"citizen_id": died_id, "cause": "starvation_or_exhaustion"})
	var housing_cap: int = BuildingSystem.get_total_housing_capacity(world_data)
	if hud:
		hud.update_population_display(citizen_list.size(), housing_cap)

func _setup_army_marker() -> void:
	if citizens_container == null:
		return
	if army_marker != null and is_instance_valid(army_marker):
		if not army_marker.is_inside_tree() and army_marker.get_parent() == null:
			citizens_container.add_child(army_marker)
		army_marker.set_player_army_manager(player_army_mgr)
		army_marker.update_display()
		return

	var existing = citizens_container.get_node_or_null("ArmyMarker")
	if existing != null:
		army_marker = existing
		army_marker.set_player_army_manager(player_army_mgr)
		army_marker.update_display()
		return

	army_marker = ArmyMarkerScript.new()
	army_marker.name = "ArmyMarker"
	citizens_container.add_child(army_marker)
	army_marker.set_player_army_manager(player_army_mgr)

func get_army_marker() -> Node2D:
	return army_marker

func _setup_caravan_marker() -> void:
	if citizens_container == null:
		return
	if active_caravan == null or not bool(active_caravan.get("is_active")):
		if caravan_marker != null and is_instance_valid(caravan_marker):
			caravan_marker.visible = false
		return

	if caravan_marker != null and is_instance_valid(caravan_marker):
		if not caravan_marker.is_inside_tree() and caravan_marker.get_parent() == null:
			citizens_container.add_child(caravan_marker)
		_update_caravan_marker_docking()
		return

	var existing = citizens_container.get_node_or_null("CaravanMarker")
	if existing != null:
		caravan_marker = existing
		_update_caravan_marker_docking()
		return

	caravan_marker = CaravanMarkerScript.new()
	caravan_marker.name = "CaravanMarker"
	citizens_container.add_child(caravan_marker)
	_update_caravan_marker_docking()

func _update_caravan_marker_docking() -> void:
	if caravan_marker == null or not is_instance_valid(caravan_marker):
		return
	if active_caravan == null or not bool(active_caravan.get("is_active")):
		caravan_marker.visible = false
		return

	var dock_info: Dictionary = BuildingSystem.find_caravan_docking_cell(world_data)
	var cell: Vector2i = dock_info.get("cell", Vector2i(-1, -1))
	var at_market: bool = bool(dock_info.get("is_market", false))
	caravan_marker.call("update_docking", cell, at_market, active_caravan)

func refresh_caravan_marker() -> void:
	if active_caravan == null or not bool(active_caravan.get("is_active")):
		if caravan_marker != null and is_instance_valid(caravan_marker):
			caravan_marker.visible = false
			caravan_marker.queue_free()
			caravan_marker = null
		if citizens_container != null:
			var existing = citizens_container.get_node_or_null("CaravanMarker")
			if existing != null and is_instance_valid(existing):
				existing.queue_free()
		return
	_setup_caravan_marker()

func get_caravan_marker() -> Node2D:
	return caravan_marker

func get_caravan_docking_cell() -> Vector2i:
	if caravan_marker != null and is_instance_valid(caravan_marker) and caravan_marker.has_method("get_docking_cell"):
		var c = caravan_marker.call("get_docking_cell")
		if c is Vector2i:
			return c
	var dock_info: Dictionary = BuildingSystem.find_caravan_docking_cell(world_data)
	return dock_info.get("cell", Vector2i(-1, -1))

func is_caravan_docked_at_market() -> bool:
	if caravan_marker != null and is_instance_valid(caravan_marker) and caravan_marker.has_method("is_docked_at_market"):
		return bool(caravan_marker.call("is_docked_at_market"))
	var dock_info: Dictionary = BuildingSystem.find_caravan_docking_cell(world_data)
	return bool(dock_info.get("is_market", false))

func get_caravan_docking_location_name() -> String:
	return "Chợ" if is_caravan_docked_at_market() else "Tòa thị chính"

func get_tactical_military_manager() -> RefCounted:
	return tactical_military_mgr

func get_enemy_military_manager() -> RefCounted:
	return enemy_military_mgr

func get_field_siege_manager() -> RefCounted:
	return field_siege_mgr

func _find_valid_outpost_cell(preferred_center: Vector2i, min_dist_from_rally: int = 15) -> Vector2i:
	var rally := Vector2i(30, 30)
	if player_army_mgr != null and player_army_mgr.has_method("get_rally_cell"):
		rally = player_army_mgr.get_rally_cell()

	var is_cell_valid := func(c: Vector2i) -> bool:
		if not IsoMath.is_in_bounds(c):
			return false
		if IsoMath.grid_distance(c, rally) < min_dist_from_rally:
			return false
		if nav != null and not nav.is_cell_walkable(c):
			return false
		if world_data != null and world_data.occupancy != null:
			if world_data.occupancy[c.x][c.y]:
				return false
		if field_siege_mgr != null and field_siege_mgr.has_method("get_all_objectives"):
			for o in field_siege_mgr.get_all_objectives():
				if is_instance_valid(o) and o.current_cell == c:
					return false
		for cit in citizen_list:
			if is_instance_valid(cit) and cit.get("current_cell") == c:
				return false
		if tactical_military_mgr != null and tactical_military_mgr.has_method("get_all_units"):
			for u in tactical_military_mgr.get_all_units():
				if is_instance_valid(u) and u.current_cell == c:
					return false
		return true

	if is_cell_valid.call(preferred_center):
		return preferred_center

	var max_radius := 20
	for r in range(1, max_radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cand := preferred_center + Vector2i(dx, dy)
				if is_cell_valid.call(cand):
					return cand

	return preferred_center

func _setup_default_siege_objectives() -> void:
	if field_siege_mgr == null:
		return

	var outpost_configs := [
		{"fid": "rival_military", "id": "outpost_rival_military", "anchor": Vector2i(14, 14), "hp": 300.0, "gar": 4},
		{"fid": "rival_merchant", "id": "outpost_rival_merchant", "anchor": Vector2i(50, 16), "hp": 250.0, "gar": 3},
		{"fid": "neutral_tribe", "id": "outpost_neutral_tribe", "anchor": Vector2i(16, 48), "hp": 200.0, "gar": 2}
	]

	for cfg in outpost_configs:
		var fid: String = cfg["fid"]
		var oid: String = cfg["id"]
		if field_siege_mgr.get_objective(oid) != null:
			continue
		var cell: Vector2i = _find_valid_outpost_cell(cfg["anchor"], 15)
		field_siege_mgr.register_objective(oid, cell, fid, cfg["hp"], cfg["gar"])

func _on_faction_war_declared(faction_id: String) -> void:
	if faction_mgr == null or enemy_military_mgr == null or field_siege_mgr == null:
		return

	var fac = null
	if faction_mgr.has_method("get_faction"):
		fac = faction_mgr.get_faction(faction_id)
	if fac == null:
		return
	if fac.get("existence_status") != null and fac.get("existence_status") != "active":
		return

	# Idempotency check: if forces already spawned for this faction, do not duplicate
	var existing = enemy_military_mgr.get_enemies_by_faction(faction_id)
	if existing.size() > 0:
		return

	var obj_id := "outpost_%s" % faction_id
	var obj = field_siege_mgr.get_objective(obj_id)
	if obj == null:
		for o in field_siege_mgr.get_all_objectives():
			if is_instance_valid(o) and o.owning_faction_id == faction_id:
				obj = o
				break

	var spawn_center: Vector2i = Vector2i(14, 14)
	if obj != null:
		spawn_center = obj.current_cell
	else:
		spawn_center = _find_valid_outpost_cell(Vector2i(20, 20), 15)
		obj = field_siege_mgr.register_objective(obj_id, spawn_center, faction_id)

	var force_count: int = obj.garrison_count if obj != null else 3
	var spawned_units = enemy_military_mgr.spawn_enemy_force(faction_id, spawn_center, force_count, nav, true, true, obj.objective_id if obj != null else "")
	for u in spawned_units:
		if u != null:
			u.patrol_origin = spawn_center
			u.patrol_radius = 5
			if u.has_method("set_ai_state"):
				u.set_ai_state(1) # 1 = PATROL

	if obj != null:
		var ids: Array[String] = []
		for u in spawned_units:
			if u != null:
				ids.append(u.unit_id)
		obj.defending_unit_ids = ids

	if hud != null:
		var fac_name: String = str(fac.name) if fac.get("name") != null else faction_id
		hud.show_event_banner("Chiến Sự Bùng Nổ!", "Thế lực %s đã điều động quân đội đối đầu với chúng ta!" % fac_name, false, 5.0)

func _on_faction_peace_signed(faction_id: String) -> void:
	if enemy_military_mgr != null and enemy_military_mgr.has_method("on_peace_signed"):
		enemy_military_mgr.on_peace_signed(faction_id)
	if tactical_military_mgr != null and tactical_military_mgr.has_method("disengage_targets_of_faction"):
		tactical_military_mgr.disengage_targets_of_faction(faction_id)
	if field_siege_mgr != null and field_siege_mgr.has_method("cancel_active_sieges_for_faction"):
		field_siege_mgr.cancel_active_sieges_for_faction(faction_id, "WITHDRAWAL")

func _setup_selection_box_overlay() -> void:
	if _selection_box_layer == null:
		_selection_box_layer = CanvasLayer.new()
		_selection_box_layer.name = "SelectionBoxLayer"
		_selection_box_layer.layer = 10
		_selection_box_control = Control.new()
		_selection_box_control.name = "SelectionBoxControl"
		_selection_box_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_selection_box_control.set_anchors_preset(Control.PRESET_FULL_RECT)
		_selection_box_control.draw.connect(_on_selection_box_draw)
		_selection_box_layer.add_child(_selection_box_control)
		add_child(_selection_box_layer)

func _on_selection_box_draw() -> void:
	if _is_drag_box_active and _selection_box_control != null:
		var r := Rect2(_drag_start_screen, _drag_current_screen - _drag_start_screen).abs()
		if r.size.x > 2.0 and r.size.y > 2.0:
			_selection_box_control.draw_rect(r, Color(0.2, 0.75, 1.0, 0.2), true)
			_selection_box_control.draw_rect(r, Color(0.4, 0.9, 1.0, 0.95), false, 1.5)

func _update_selection_box_display() -> void:
	if _selection_box_control != null and is_instance_valid(_selection_box_control):
		_selection_box_control.queue_redraw()

func _clear_selection_box_display() -> void:
	if _selection_box_control != null and is_instance_valid(_selection_box_control):
		_selection_box_control.queue_redraw()

func _find_tactical_unit_at_cell(cell: Vector2i) -> Node2D:
	if tactical_military_mgr == null:
		return null
	var best_unit: Node2D = null
	var best_dist := 2 # Current cell or adjacent 1 tile
	for u in tactical_military_mgr.call("get_all_units"):
		var d := IsoMath.grid_distance(cell, u.current_cell)
		if d < best_dist:
			best_dist = d
			best_unit = u
	return best_unit

func _find_enemy_unit_at_cell(cell: Vector2i) -> Node2D:
	if enemy_military_mgr == null:
		return null
	var best_unit: Node2D = null
	var best_dist := 2 # Current cell or adjacent 1 tile
	for e in enemy_military_mgr.call("get_all_enemies"):
		if e == null or not is_instance_valid(e) or not e.is_alive:
			continue
		var d: int = IsoMath.grid_distance(cell, e.current_cell)
		if d < best_dist:
			best_dist = d
			best_unit = e
			if d == 0:
				break
	return best_unit

func _find_siege_objective_at_cell(cell: Vector2i) -> Node2D:
	if field_siege_mgr == null:
		return null
	var best_obj: Node2D = null
	var best_dist := 2 # Current cell or adjacent 1 tile
	for o in field_siege_mgr.call("get_all_objectives"):
		if o == null or not is_instance_valid(o) or not o.is_alive:
			continue
		var d: int = IsoMath.grid_distance(cell, o.current_cell)
		if d < best_dist:
			best_dist = d
			best_obj = o
			if d == 0:
				break
	return best_obj

func _process(delta: float) -> void:
	_update_tile_hover()
	var speed_mult: float = 1.0
	var tm = get_node_or_null("/root/TimeManager")
	if tm != null:
		if tm.has_method("is_paused") and tm.is_paused():
			speed_mult = 0.0
		elif tm.get("current_speed") != null:
			speed_mult = float(tm.get("current_speed"))

	if player_army_mgr != null and player_army_mgr.has_method("advance_movement"):
		player_army_mgr.advance_movement(delta, speed_mult)
	elif tactical_military_mgr != null and tactical_military_mgr.has_method("advance_movement"):
		tactical_military_mgr.advance_movement(delta, speed_mult, nav)

	if enemy_military_mgr != null and enemy_military_mgr.has_method("advance_simulation"):
		var p_units: Array = tactical_military_mgr.call("get_all_units") if (tactical_military_mgr != null and tactical_military_mgr.has_method("get_all_units")) else []
		enemy_military_mgr.call("advance_simulation", delta, speed_mult, nav, p_units)

	if field_siege_mgr != null and field_siege_mgr.get("active_sieges") != null:
		var s_ids = field_siege_mgr.active_sieges.keys()
		for s_id in s_ids:
			field_siege_mgr.evaluate_siege_status(s_id)

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
			if hud.has_method("is_army_move_targeting") and hud.call("is_army_move_targeting"):
				b_name += " [Nhấp để điều động]"
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
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event as InputEventKey
		if k.keycode == KEY_ESCAPE:
			if placing_building_type != "":
				_cancel_placement()
			elif tactical_military_mgr != null and tactical_military_mgr.call("get_selected_count") > 0:
				tactical_military_mgr.call("clear_selection")
				get_viewport().set_input_as_handled()
			elif selected_building_id != "":
				clear_building_selection()
				get_viewport().set_input_as_handled()
		elif k.keycode in [KEY_1, KEY_2, KEY_3]:
			var grp: int = k.keycode - KEY_1 + 1
			if k.ctrl_pressed:
				if tactical_military_mgr != null:
					tactical_military_mgr.call("assign_control_group", grp)
					get_viewport().set_input_as_handled()
			elif k.shift_pressed:
				if tactical_military_mgr != null:
					tactical_military_mgr.call("recall_control_group", grp)
					get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion:
		if _is_left_mouse_down:
			var mm: InputEventMouseMotion = event as InputEventMouseMotion
			if not _is_drag_box_active and (mm.position - _drag_start_screen).length() > 6.0:
				_is_drag_box_active = true
			if _is_drag_box_active:
				_drag_current_screen = mm.position
				_update_selection_box_display()

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		var mouse_local := terrain_layer.get_local_mouse_position()
		var cell := IsoMath.local_to_map(mouse_local)
		
		if placing_building_type != "":
			if mb.pressed:
				if mb.button_index == MOUSE_BUTTON_LEFT:
					_execute_placement(cell)
				elif mb.button_index == MOUSE_BUTTON_RIGHT:
					_cancel_placement()
		elif hud != null and hud.has_method("is_army_move_targeting") and hud.call("is_army_move_targeting"):
			if mb.pressed:
				if mb.button_index == MOUSE_BUTTON_LEFT:
					hud.call("execute_army_move_target", cell)
				elif mb.button_index == MOUSE_BUTTON_RIGHT:
					hud.call("cancel_army_move_targeting")
		else:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_is_left_mouse_down = true
					_drag_start_screen = mb.position
					_drag_current_screen = mb.position
					_is_drag_box_active = false
				else:
					# Left mouse button released
					_is_left_mouse_down = false
					if _is_drag_box_active:
						_is_drag_box_active = false
						_clear_selection_box_display()
						var rect := Rect2(_drag_start_screen, _drag_current_screen - _drag_start_screen).abs()
						if tactical_military_mgr != null:
							tactical_military_mgr.call("select_in_screen_rect", rect, camera, mb.shift_pressed)
					else:
						# Simple left click
						_clear_selection_box_display()
						var clicked_unit = _find_tactical_unit_at_cell(cell)
						if clicked_unit != null:
							if tactical_military_mgr != null:
								tactical_military_mgr.call("select_unit", clicked_unit.unit_id, mb.shift_pressed)
						else:
							if not mb.shift_pressed and tactical_military_mgr != null:
								tactical_military_mgr.call("clear_selection")
							_handle_left_click(cell)
			elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
				if tactical_military_mgr != null and tactical_military_mgr.call("get_selected_count") > 0:
					var obj_target = _find_siege_objective_at_cell(cell)
					var enemy_target = _find_enemy_unit_at_cell(cell)

					# If right-clicking directly on an outpost objective cell, prioritize the objective!
					var target_is_obj: bool = false
					if obj_target != null and obj_target.current_cell == cell:
						target_is_obj = true
					elif enemy_target != null:
						target_is_obj = false
					elif obj_target != null:
						target_is_obj = true

					if target_is_obj and obj_target != null:
						var is_active := false
						if field_siege_mgr != null and field_siege_mgr.has_method("is_siege_active_for_objective"):
							is_active = field_siege_mgr.is_siege_active_for_objective(obj_target.objective_id)

						if is_active:
							var res: Dictionary = tactical_military_mgr.call("issue_attack_order", obj_target, nav)
							if not res.get("success", false) and hud != null:
								hud.show_event_banner("Lệnh Tấn Công Thất Bại", res.get("reason", "Không thể tấn công"), false, 3.0)
						else:
							if field_siege_mgr != null:
								var check: Dictionary = field_siege_mgr.can_launch_field_siege(obj_target.owning_faction_id, obj_target.objective_id)
								if bool(check.get("can_launch", false)):
									var launch_res: Dictionary = field_siege_mgr.launch_field_siege(obj_target.owning_faction_id, obj_target.objective_id)
									if bool(launch_res.get("success", false)):
										var atk_res: Dictionary = tactical_military_mgr.call("issue_attack_order", obj_target, nav)
										if hud != null:
											hud.show_event_banner("Phát Động Công Thành!", "Đã phát động chiến dịch công thành đối với %s!" % obj_target.objective_name, true, 4.0)
									else:
										if hud != null:
											hud.show_event_banner("Không Thể Công Thành", launch_res.get("reason", "Phát động thất bại"), false, 3.5)
								else:
									if hud != null:
										hud.show_event_banner("Không Thể Công Thành", check.get("reason", "Không đủ điều kiện công thành"), false, 3.5)
					elif enemy_target != null:
						var res: Dictionary = tactical_military_mgr.call("issue_attack_order", enemy_target, nav)
						if not res.get("success", false) and hud != null:
							hud.show_event_banner("Lệnh Tấn Công Thất Bại", res.get("reason", "Không thể tấn công"), false, 3.0)
					else:
						var res: Dictionary = tactical_military_mgr.call("issue_move_order", cell, nav)
						if not res.get("success", false) and hud != null:
							hud.show_event_banner("Lệnh Thất Bại", res.get("reason", "Vị trí không thể đi tới"), false, 3.0)

func _handle_left_click(cell: Vector2i) -> void:
	# Priority 2: Exact-cell citizen
	for cit in citizen_list:
		if is_instance_valid(cit) and cit.get("current_cell") == cell:
			clear_building_selection()
			if hud != null and hud.has_method("show_citizen_inspector"):
				hud.show_citizen_inspector(cit)
			return

	# Priority 3: Building footprint at clicked cell (1x1, 2x2, 3x3)
	var b_data := _get_building_at_cell(cell)
	if not b_data.is_empty():
		if hud != null and hud.has_method("close_citizen_inspector"):
			hud.close_citizen_inspector()
		select_building(b_data)
		return

	# Priority 4: Fuzzy adjacent citizen (within Manhattan distance 1, only if no building was clicked)
	var best_cit: Node = null
	var best_dist: int = 2 # distance <= 1
	for cit in citizen_list:
		if is_instance_valid(cit):
			var c_cell: Vector2i = cit.get("current_cell")
			var d: int = IsoMath.grid_distance(cell, c_cell)
			if d < best_dist:
				best_dist = d
				best_cit = cit

	if best_cit != null:
		clear_building_selection()
		if hud != null and hud.has_method("show_citizen_inspector"):
			hud.show_citizen_inspector(best_cit)
		return

	# Priority 5: Empty ground - clear building selection and close inspectors
	clear_building_selection()
	if hud != null and hud.has_method("close_citizen_inspector"):
		hud.close_citizen_inspector()

func select_building(b_data: Dictionary) -> void:
	if b_data.is_empty():
		clear_building_selection()
		return
	selected_building_id = b_data.get("id", "")
	var origin: Vector2i = b_data.get("cell", Vector2i(-1, -1))
	var size: Vector2i = b_data.get("size", Vector2i(1, 1))
	if building_highlight != null:
		building_highlight.set_footprint(origin, size)
	if hud != null and hud.has_method("show_building_inspector"):
		hud.show_building_inspector(b_data)

func clear_building_selection() -> void:
	selected_building_id = ""
	if building_highlight != null:
		building_highlight.clear_highlight()
	if hud != null and hud.has_method("close_building_inspector"):
		hud.close_building_inspector()

func focus_camera_on_building(b_id: String) -> void:
	if world_data == null or b_id == "":
		return
	var b_data := BuildingSystem.get_building_by_id(b_id, world_data)
	if b_data.is_empty():
		return
	var origin: Vector2i = b_data.get("cell", Vector2i(-1, -1))
	if origin.x >= 0 and origin.y >= 0 and camera != null:
		var size: Vector2i = b_data.get("size", Vector2i(1, 1))
		var center_local := IsoMath.map_to_local(origin) + Vector2(float(size.x - 1) * 16.0, float(size.y - 1) * 8.0)
		camera.position = center_local

func _is_building_active_for_jobs(b_id: String) -> bool:
	if world_data == null or b_id == "":
		return false
	return BuildingSystem.is_building_active_by_id(b_id, world_data)

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
	if hud != null and hud.has_method("is_army_move_targeting") and hud.call("is_army_move_targeting"):
		hud.call("cancel_army_move_targeting")
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

func _safe_cleanup_construction_job(j: JobManager.JobData) -> void:
	if j == null or job_mgr == null:
		return

	# 1. Inspect CitizenController lifecycle to avoid leaving orphaned task references
	var all_citizens: Array = []
	all_citizens.append_array(citizen_list)
	if citizens_container != null:
		for child in citizens_container.get_children():
			if child is CitizenController and not all_citizens.has(child):
				all_citizens.append(child)

	for cit in all_citizens:
		if cit == null:
			continue
		var cit_job = cit.get("active_job")
		if cit_job != null:
			# Only clear active_job and interrupt when it actually matches the job being removed
			if cit_job == j or cit_job.id == j.id:
				cit.active_job = null
				cit.set("current_state", CitizenController.State.IDLE)
				cit.set("current_path", [])
				if cit.has_method("_update_reason"):
					cit.call("_update_reason")
			# If the citizen has a different valid active_job, preserve that job and assignment untouched
		else:
			# If j.worker_id matches a citizen whose active_job is null and that citizen is visibly stranded in a job-related state, release safely
			if j.worker_id != "" and cit.get("citizen_id") == j.worker_id:
				var cstate = cit.get("current_state")
				if cstate == CitizenController.State.MOVING_TO_JOB or cstate == CitizenController.State.WORKING or cstate == CitizenController.State.HAULING or cstate == CitizenController.State.GUARDING:
					cit.set("current_state", CitizenController.State.IDLE)
					cit.set("current_path", [])
					if cit.has_method("_update_reason"):
						cit.call("_update_reason")

	# 2. Cancel the job through JobManager if it was reserved or in progress
	if j.state == JobManager.JobState.RESERVED or j.state == JobManager.JobState.IN_PROGRESS:
		job_mgr.cancel_job(j, "Cleaned up invalid or duplicate construction job")

	# 3. Remove the job from JobManager
	job_mgr.remove_job(j.id)

func register_construction_jobs(b_data: Dictionary) -> Array[JobManager.JobData]:
	var result: Array[JobManager.JobData] = []
	if job_mgr == null or world_data == null or b_data.is_empty():
		return result

	var b_id: String = b_data.get("id", "")
	if b_id == "":
		return result

	var b_state: String = b_data.get("state", "")
	if b_state != "under_construction":
		return result

	var b_type: String = b_data.get("type", "")
	var origin: Vector2i = b_data.get("cell", Vector2i.ZERO)
	var size: Vector2i = b_data.get("size", Vector2i(1, 1))

	var capacity: int = BuildingSystem.get_construction_worker_capacity(b_type)
	var max_candidate_count: int = 2 * (size.x + size.y) + 16
	var perimeter: Array[Vector2i] = BuildingSystem.find_perimeter_cells(origin, size, world_data, max_candidate_count)
	var max_jobs: int = mini(capacity, perimeter.size())

	if nav != null and world_data != null and nav.world_data != world_data:
		nav.world_data = world_data

	# 1. Collect all builder jobs specifically matching this exact building project
	var all_matching_jobs := job_mgr.get_jobs_for_building(b_id)
	var existing_builder_jobs: Array[JobManager.JobData] = []
	for j in all_matching_jobs:
		# Require exact project ownership: do not adopt builder jobs belonging to other projects
		# even if they share a separator-aware prefix (e.g. bld_house_15_15_annex vs bld_house_15_15)
		if j.type == "builder" and j.target_building_id == b_id:
			existing_builder_jobs.append(j)

	var valid_candidates: Array[JobManager.JobData] = []
	var stale_jobs: Array[JobManager.JobData] = []

	for j in existing_builder_jobs:
		var is_valid_state: bool = (j.state == JobManager.JobState.AVAILABLE or j.state == JobManager.JobState.RESERVED or j.state == JobManager.JobState.IN_PROGRESS)
		var is_in_bounds: bool = IsoMath.is_in_bounds(j.target_cell)
		var is_valid_cell: bool = is_in_bounds and \
			(nav == null or nav.is_walkable(j.target_cell)) and \
			world_data.terrain[j.target_cell.x][j.target_cell.y] != WorldGenerator.TerrainType.WATER and \
			not world_data.occupancy[j.target_cell.x][j.target_cell.y]
		var is_in_perimeter: bool = perimeter.has(j.target_cell)

		if is_valid_state and is_valid_cell and is_in_perimeter:
			valid_candidates.append(j)
		else:
			stale_jobs.append(j)

	# 2. Group valid candidates by target_cell to eliminate duplicate-position jobs
	var jobs_by_cell: Dictionary = {}
	for j in valid_candidates:
		if not jobs_by_cell.has(j.target_cell):
			jobs_by_cell[j.target_cell] = []
		jobs_by_cell[j.target_cell].append(j)

	var unique_cell_jobs: Array[JobManager.JobData] = []
	var duplicate_jobs_to_remove: Array[JobManager.JobData] = []

	for cell in jobs_by_cell:
		var list_at_cell: Array = jobs_by_cell[cell]
		# Preserve a valid active assignment where possible: prefer IN_PROGRESS, then RESERVED, then AVAILABLE
		var best_job: JobManager.JobData = list_at_cell[0]
		for k in range(1, list_at_cell.size()):
			var cand: JobManager.JobData = list_at_cell[k]
			var prio_cand := 2 if cand.state == JobManager.JobState.IN_PROGRESS else (1 if cand.state == JobManager.JobState.RESERVED else 0)
			var prio_best := 2 if best_job.state == JobManager.JobState.IN_PROGRESS else (1 if best_job.state == JobManager.JobState.RESERVED else 0)
			if prio_cand > prio_best:
				best_job = cand

		unique_cell_jobs.append(best_job)
		for j in list_at_cell:
			if j != best_job:
				duplicate_jobs_to_remove.append(j)

	# 3. Enforce worker capacity and valid perimeter limits
	var retained_jobs: Array[JobManager.JobData] = []
	var excess_jobs_to_remove: Array[JobManager.JobData] = []

	if unique_cell_jobs.size() > max_jobs:
		# Prioritize preserving active assignments
		unique_cell_jobs.sort_custom(func(a: JobManager.JobData, b: JobManager.JobData) -> bool:
			var prio_a := 2 if a.state == JobManager.JobState.IN_PROGRESS else (1 if a.state == JobManager.JobState.RESERVED else 0)
			var prio_b := 2 if b.state == JobManager.JobState.IN_PROGRESS else (1 if b.state == JobManager.JobState.RESERVED else 0)
			if prio_a != prio_b:
				return prio_a > prio_b
			return a.id < b.id
		)
		for i in range(unique_cell_jobs.size()):
			if i < max_jobs:
				retained_jobs.append(unique_cell_jobs[i])
			else:
				excess_jobs_to_remove.append(unique_cell_jobs[i])
	else:
		retained_jobs = unique_cell_jobs

	# 4. Safely clean up stale, duplicate, and excess jobs
	var all_removals: Array[JobManager.JobData] = []
	all_removals.append_array(stale_jobs)
	all_removals.append_array(duplicate_jobs_to_remove)
	all_removals.append_array(excess_jobs_to_remove)

	var seen_remove_ids: Dictionary = {}
	for rem_j in all_removals:
		if not seen_remove_ids.has(rem_j.id):
			seen_remove_ids[rem_j.id] = true
			_safe_cleanup_construction_job(rem_j)

	# 5. Spawn new jobs if retained count is below max_jobs
	var used_cells: Array[Vector2i] = []
	for rj in retained_jobs:
		used_cells.append(rj.target_cell)

	for cell in perimeter:
		if retained_jobs.size() >= max_jobs:
			break
		if cell in used_cells:
			continue
		var job = job_mgr.create_job(
			"builder",
			cell,
			"Thi công xây dựng %s" % _get_building_display_name(b_type),
			b_id,
			float(b_data.get("construction_hours", 12.0)),
			2,
			false
		)
		retained_jobs.append(job)
		used_cells.append(cell)

	result = retained_jobs
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

	var total_hours: float = float(b_data.get("construction_hours", 0.0))
	if is_nan(total_hours) or is_inf(total_hours) or total_hours <= 0.0:
		return false

	var cur_prog: float = float(b_data.get("construction_progress", 0.0))
	if is_nan(cur_prog) or is_inf(cur_prog):
		return false

	const PROGRESS_TOLERANCE: float = 0.001
	if cur_prog < (total_hours - PROGRESS_TOLERANCE):
		return false # Refuse premature completion before required construction work is achieved

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
		if cit.get("active_job") != null and JobManager.job_matches_building(cit.active_job, b_id):
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

	# If barracks, register guard jobs and refresh hud role options & army panel
	if b_data["type"] == "barracks":
		register_barracks_jobs(b_data)
		if hud != null and hud.has_method("_refresh_role_options"):
			hud.call("_refresh_role_options")
		if player_army_mgr != null and player_army_mgr.has_method("notify_capacity_changed"):
			player_army_mgr.call("notify_capacity_changed")
		elif hud != null and hud.has_method("_refresh_army_panel"):
			hud.call("_refresh_army_panel")

	# If market, refresh active trade caravan docking location
	if b_data["type"] == "market":
		refresh_caravan_marker()

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
	if rm == null:
		return {"success": false, "reason": "Thiếu ResourceManager để hoàn trả tài nguyên"}

	var res := BuildingSystem.cancel_construction(b_data, world_data, rm, job_mgr)
	if not res.get("success", false):
		return res

	# Clear selection if canceled building was currently selected
	if selected_building_id == b_id:
		clear_building_selection()

	# Free visual node only if cancellation succeeded!
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
		if cit.get("active_job") != null and JobManager.job_matches_building(cit.active_job, b_id):
			cit.active_job = null
			cit.set("current_state", CitizenController.State.IDLE)
			if cit.has_method("_update_reason"):
				cit.call("_update_reason")

	if type == "barracks":
		if hud != null and hud.has_method("_refresh_role_options"):
			hud.call("_refresh_role_options")
		if player_army_mgr != null and player_army_mgr.has_method("notify_capacity_changed"):
			player_army_mgr.call("notify_capacity_changed")
		elif hud != null and hud.has_method("_refresh_army_panel"):
			hud.call("_refresh_army_panel")

	# If market, refresh active trade caravan docking location
	if b_data.get("type", "") == "market":
		refresh_caravan_marker()

	return res

func set_building_state(b_id: String, new_state: String) -> bool:
	if world_data == null or b_id == "":
		return false
	var b_data: Dictionary = BuildingSystem.get_building_by_id(b_id, world_data)
	if b_data.is_empty():
		return false
	var old_state: String = b_data.get("state", "")
	if old_state == new_state:
		return true
	b_data["state"] = new_state

	var origin: Vector2i = b_data.get("cell", Vector2i.ZERO)
	var type: String = b_data.get("type", "")
	var node_name := "Building_%s_%d_%d" % [type, origin.x, origin.y]
	var b_node = buildings_container.get_node_or_null(node_name) if buildings_container != null else null
	var spr: Sprite2D = null
	if b_node != null:
		spr = b_node.get_node_or_null("Sprite2D")
		if spr == null:
			for ch in b_node.get_children():
				if ch is Sprite2D:
					spr = ch
					break

	if new_state == "paused":
		if workplace_mgr != null:
			workplace_mgr.set_workplace_paused(b_id, true)
		if spr != null:
			spr.modulate = Color(0.7, 0.7, 0.7, 0.85)
		# Release active workers targeting this building
		for cit in citizen_list:
			if cit.get("active_job") != null and JobManager.job_matches_building(cit.active_job, b_id):
				if job_mgr != null:
					job_mgr.release_job(cit.active_job)
				cit.active_job = null
				cit.set("current_state", CitizenController.State.IDLE)
				cit.set("status_reason", "Công trình tạm dừng hoạt động")
	elif new_state == "active":
		if workplace_mgr != null:
			workplace_mgr.set_workplace_paused(b_id, false)
		if spr != null:
			spr.modulate = Color(1.0, 1.0, 1.0, 1.0)

	if b_data.get("type", "") == "barracks":
		if hud != null and hud.has_method("_refresh_role_options"):
			hud.call("_refresh_role_options")
		if player_army_mgr != null and player_army_mgr.has_method("notify_capacity_changed"):
			player_army_mgr.call("notify_capacity_changed")
		elif hud != null and hud.has_method("_refresh_army_panel"):
			hud.call("_refresh_army_panel")

	# If market, refresh active trade caravan docking location
	if b_data.get("type", "") == "market":
		refresh_caravan_marker()

	# If currently inspected, refresh HUD inspector
	if hud != null and hud.has_method("refresh_building_inspector") and selected_building_id == b_id:
		hud.refresh_building_inspector()

	return true

func demolish_building_project(b_id: String) -> Dictionary:
	if world_data == null or b_id == "":
		return {"success": false, "reason": "Dữ liệu thế giới rỗng"}
	var b_data: Dictionary = BuildingSystem.get_building_by_id(b_id, world_data)
	if b_data.is_empty():
		return {"success": false, "reason": "Công trình không tồn tại"}

	var rm := get_node_or_null("/root/ResourceManager")
	var res := BuildingSystem.demolish_building(b_data, world_data, rm, job_mgr)
	if not res.get("success", false):
		return res

	# Clear building selection if demolished building was currently selected
	if selected_building_id == b_id:
		clear_building_selection()

	var origin: Vector2i = b_data.get("cell", Vector2i.ZERO)
	var size: Vector2i = b_data.get("size", Vector2i(1, 1))
	var type: String = b_data.get("type", "")
	var node_name := "Building_%s_%d_%d" % [type, origin.x, origin.y]
	var b_node = buildings_container.get_node_or_null(node_name) if buildings_container != null else null
	if b_node:
		b_node.queue_free()
	for ox in range(size.x):
		for oy in range(size.y):
			buildings_by_cell.erase(origin + Vector2i(ox, oy))

	# Release any citizens assigned to this building to IDLE
	for cit in citizen_list:
		if cit.get("active_job") != null and JobManager.job_matches_building(cit.active_job, b_id):
			cit.active_job = null
			cit.set("current_state", CitizenController.State.IDLE)
			cit.set("status_reason", "Công trình đã bị dỡ bỏ")
			if cit.has_method("_update_reason"):
				cit.call("_update_reason")
		if cit.get("workplace_id") == b_id:
			cit.set("workplace_id", "")

	# Unregister workplace and channels if dynamic workplace
	if workplace_mgr != null:
		if workplace_mgr.has_method("unregister_workplace"):
			workplace_mgr.unregister_workplace(b_id)
		if workplace_mgr.has_method("unregister_dropoff"):
			workplace_mgr.unregister_dropoff(b_id)

	if type == "barracks":
		if hud != null and hud.has_method("_refresh_role_options"):
			hud.call("_refresh_role_options")
		if player_army_mgr != null and player_army_mgr.has_method("notify_capacity_changed"):
			player_army_mgr.call("notify_capacity_changed")
		elif hud != null and hud.has_method("_refresh_army_panel"):
			hud.call("_refresh_army_panel")

	# If market, refresh active trade caravan docking location
	if type == "market":
		refresh_caravan_marker()

	# If watchtower, refresh vision
	if type == "watchtower":
		refresh_world_vision()

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

		# Sync paused state to workplace manager and visual node
		if b_state == "paused":
			if workplace_mgr != null:
				workplace_mgr.set_workplace_paused(b.get("id", ""), true)
			var node_name := "Building_%s_%d_%d" % [b_type, b.get("cell", Vector2i.ZERO).x, b.get("cell", Vector2i.ZERO).y]
			var b_node = buildings_container.get_node_or_null(node_name) if buildings_container != null else null
			if b_node != null:
				for ch in b_node.get_children():
					if ch is Sprite2D:
						ch.modulate = Color(0.7, 0.7, 0.7, 0.85)
						break

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
		"palisade": return "Tường Rào Phòng Ngự (1x1)"
		"market": return "Chợ (3x3)"
		_: return ""

func _on_return_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func refresh_world_vision() -> void:
	if fog_of_war == null:
		return

	# Degrade all currently VISIBLE cells to EXPLORED before recomputing active sightlines
	for x in range(fog_of_war.map_size):
		for y in range(fog_of_war.map_size):
			if fog_of_war._grid[x][y] == FogOfWar.State.VISIBLE:
				fog_of_war._grid[x][y] = FogOfWar.State.EXPLORED

	# 1. Core settlement vision around Town Hall / starting center
	if world_data == null or world_data.get("buildings") == null or world_data.buildings.is_empty() or BuildingSystem.is_town_hall_active(world_data):
		fog_of_war.reveal_circle(Vector2i(32, 32), 10)

	# 2. Living citizens vision
	for cit in citizen_list:
		if cit != null and is_instance_valid(cit):
			var c_cell = cit.get("current_cell")
			if c_cell is Vector2i:
				fog_of_war.reveal_circle(c_cell, 4)

	# 3. Active watchtowers vision
	if world_data != null and world_data.get("buildings") != null:
		for b in world_data.buildings:
			if b.get("type") == "watchtower" and b.get("state", "active") == "active":
				var b_cell: Vector2i = b.get("cell", Vector2i.ZERO)
				var bp: Dictionary = EconomyConfig.BLUEPRINTS.get("watchtower", {})
				var v_rad: int = bp.get("vision_radius", 15)
				fog_of_war.reveal_circle(b_cell, v_rad)

	# 4. Living player tactical units vision
	if tactical_military_mgr != null and tactical_military_mgr.has_method("get_all_units"):
		for u in tactical_military_mgr.get_all_units():
			if u != null and is_instance_valid(u) and bool(u.get("is_alive")):
				var u_cell = u.get("current_cell")
				if u_cell is Vector2i:
					fog_of_war.reveal_circle(u_cell, 4)

func _on_simulation_hour_passed(hour: int, day: int) -> void:
	var rm = get_node_or_null("/root/ResourceManager")
	
	# Progress active research project
	if research_mgr != null:
		research_mgr.progress_research(1.0, rm)
		
	# Update citizen/building/unit vision and fog of war
	refresh_world_vision()

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
			var paused: bool = (tm != null and tm.has_method("is_paused") and tm.is_paused())
			var cur_d: int = tm.current_day if tm else 1
			var cur_h: int = tm.current_hour if tm else 0
			automation_mgr.evaluate_rules(rm, job_mgr, workplace_mgr, season, citizen_list, world_data, paused, cur_d, cur_h)

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
		event_system.update_daily_modifiers(day)
		var ev_result: Dictionary = event_system.check_and_trigger_event(day, rm, em, citizen_list)
		# BUG-04 fix: apply world-event citizen effects via WorldEventSystem idempotent helper
		# (validates citizen is alive, not dead/queued_for_deletion, clamps [0, 100], prevents double application).
		if not ev_result.is_empty():
			event_system.apply_citizen_effects(ev_result, citizen_list)
		
	# Update daily faction simulation
	if faction_mgr != null:
		faction_mgr.update_daily_simulation(day)

	# Process player army daily food upkeep
	if player_army_mgr != null:
		player_army_mgr.process_daily_upkeep(day)

	# Process settlement defense battle campaign raids
	if battle_campaign_mgr != null:
		battle_campaign_mgr.process_daily_raids(day)
		
	# Scheduled visiting trade caravan arrivals (Every 5 days, starting Day 3)
	if (day % 5 == 3) and (active_caravan == null or not active_caravan.get("is_active")):
		var is_merchant_at_war: bool = false
		if faction_mgr != null:
			var fac = faction_mgr.get_faction("rival_merchant")
			if fac != null and fac.is_at_war:
				is_merchant_at_war = true
			elif faction_mgr.are_factions_at_war("rival_merchant", "rival_military") or faction_mgr.are_factions_at_war("rival_merchant", "neutral_tribe"):
				is_merchant_at_war = true
		active_caravan = TradeCaravan.generate_caravan(world_seed, day, "rival_merchant", is_merchant_at_war)
		refresh_caravan_marker()
		if em != null:
			var loc_name: String = get_caravan_docking_location_name()
			em.trigger_event("caravan_arrived", "Thương Đoàn Ghé Thăm!", "%s đã cập bến %s của định cư!" % [active_caravan.get("name"), loc_name], true, {})
			
	# Check caravan departure
	if active_caravan != null and day >= active_caravan.get("departure_day"):
		active_caravan.set("is_active", false)
		active_caravan = null
		refresh_caravan_marker()

	# Daily Autosave
	if autosave_enabled and (day % autosave_interval_days == 0):
		var asave_res := SaveManager.save_to_file(self, SaveManager.DEFAULT_SAVE_PATH)
		if asave_res.get("success", false) and em != null:
			em.trigger_event("autosave", "Tự Động Lưu", "Đã tự động lưu thế giới an toàn (Ngày %d)." % day, true, {})
