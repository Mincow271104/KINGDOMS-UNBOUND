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
const TradeRouteCalculatorScript = preload("res://scripts/trade/trade_route_calculator.gd")
const EnemyMilitaryManagerScript = preload("res://scripts/military/enemy_military_manager.gd")
const FieldSiegeManagerScript = preload("res://scripts/combat/field_siege_manager.gd")
const LegacyProfileManagerScript = preload("res://scripts/legacy/legacy_profile_manager.gd")
const CrisisManagerScript = preload("res://scripts/core/crisis_manager.gd")
const LandClearingManagerScript = preload("res://scripts/economy/land_clearing_manager.gd")
const TerritoryManagerScript = preload("res://scripts/world/territory_manager.gd")

@export var world_seed: int = 12345
@export var world_generator_version: int = WorldGenerator.LATEST_GENERATOR_VERSION
@export var world_id: String = ""
@export var active_perks: Array = []
@export var world_modifiers: Array = []
@export var difficulty: String = "normal"
var is_perks_and_modifiers_applied: bool = false
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
const TerrainPreviewFieldScript = preload("res://scripts/world/terrain_preview_field.gd")
const TerrainPreviewRendererScript = preload("res://scripts/world/terrain_preview_renderer.gd")
var fog_tile_layer: TileMapLayer = null
var cloud_sea_base: Polygon2D = null
var fog_cloud_layer: FogCloudLayer = null
var cloud_sea_composite: Polygon2D = null
var use_cloud_sea_composite: bool = true
const TOWN_HALL_PREVIEW_RADIUS_PX: float = 350.0
const TOWN_HALL_CORE_RADIUS_PX: float = 200.0
var _gameplay_preview_ids: Dictionary = {}
var _tracked_hunter_states: Dictionary = {}
var _fog_state_bytes: PackedByteArray = PackedByteArray()
var _fog_state_img: Image = null
var _fog_state_tex: ImageTexture = null
var _fog_state_upload_count: int = 0
var _fog_state_last_stats: Dictionary = {}
var _fog_transition_viewport: SubViewport = null
var _fog_transition_rect: ColorRect = null
var _fog_transition_update_count: int = 0
var terrain_preview_field: TerrainPreviewFieldScript = null
var terrain_preview_renderer: TerrainPreviewRendererScript = null
static var _cloud_sea_shader: Shader = null
const CLOUD_SEA_BASE_TEX_PATH: String = "res://assets/fog/cloud_sea_base_v4_512.png"
const CLOUD_SEA_WISP_TEX_PATH: String = "res://assets/fog/cloud_sea_base_v5_wisps_512.png"
const CLOUD_SEA_COMPOSITE_SHADER_PATH: String = "res://shaders/fog/cloud_sea_composite.gdshader"
const FOG_TRANSITION_COVERAGE_SHADER_PATH: String = "res://shaders/fog/fog_transition_coverage.gdshader"
const CLOUD_SEA_COMPOSITE_SEA_TEX_PATH: String = "res://assets/fog/cloud_wisps_sea_1024.png"
const CLOUD_SEA_COMPOSITE_BANK_TEX_PATH: String = "res://assets/fog/cloud_banks_macro_1024.png"
var prop_nodes_by_cell: Dictionary = {}
const WildlifeManagerScript = preload("res://scripts/world/wildlife_manager.gd")
const MonsterManagerScript = preload("res://scripts/world/monster_manager.gd")
var cookhouse_mgr: CookhouseManager = null
var natural_resource_mgr: NaturalResourceManager = null
var wildlife_mgr: RefCounted = null
var wildlife_container: Node2D = null
var monster_mgr: RefCounted = null
var monsters_container: Node2D = null
var debug_fog_disabled: bool = false
var _last_cam_pos_for_minimap: Vector2 = Vector2.INF
var faction_mgr: FactionManager
var active_caravan: RefCounted = null
var immigration_mgr: ImmigrationManager
var victory_mgr: VictoryManager
var crisis_mgr: RefCounted = null
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
var settlement_simulation_manager: Node = null
var is_loading_save: bool = false
var rival_presentation_controller: Node = null
var _rival_inspection_query: RefCounted = null
var _rival_villager_pool_container: Node2D = null
var _rival_settlement_groups: Dictionary = {} # settlement_id -> Node2D (stl_group)
var _debug_inspect_providers: Array[Callable] = []

var buildings_by_cell: Dictionary = {} # cell (Vector2i) -> building_type (String)
var rival_buildings_by_cell: Dictionary = {} # cell (Vector2i) -> {type, faction_id, origin_faction_id, settlement_id}
var rival_settlements_container: Node2D = null
var _rival_settlement_visuals: Array[Dictionary] = [] # [{node: Node2D, vis_cell: Vector2i}]
var citizens_by_id: Dictionary = {}
var deceased_citizen_ids: Dictionary = {}
var citizen_list: Array = []
var house_indoor_occupants: Dictionary = {} # house_id (String) -> Array[String] of citizen_ids
var terrain_textures: Dictionary = {}
var building_textures: Dictionary = {}
var prop_textures: Dictionary = {}

var placing_building_type: String = ""
var ghost_building_node: Node2D
var ghost_building_sprite: Sprite2D
var bridge_start_bank: Vector2i = Vector2i(-1, -1)
var bridge_width: int = 1
var bridge_width_offset: int = 0
var _bridge_preview_overlay: Node2D = null
var _bridge_preview_cells: Array[Vector2i] = []
var _bridge_preview_valid: bool = false
var _bridge_preview_hover_cell: Vector2i = Vector2i(-1, -1)
var _last_input_mouse_screen: Vector2 = Vector2.INF
var _last_bridge_preview: Dictionary = {}

var land_clearing_mgr: LandClearingManagerScript = null
var is_clear_land_mode: bool = false
var _clear_land_overlay: Node2D = null
var _clear_land_dispatch_timer: float = 0.0

var territory_mgr: TerritoryManagerScript = null
var _territory_overlay: Node2D = null

# ResourceManager dependency injection for testing & decoupling
var resource_mgr: Object = null
var _resource_mgr_injected: bool = false

func set_resource_mgr_for_testing(rm: Object) -> void:
	resource_mgr = rm
	_resource_mgr_injected = true

func clear_resource_mgr_for_testing() -> void:
	resource_mgr = null
	_resource_mgr_injected = false

func _get_resource_mgr() -> Object:
	if _resource_mgr_injected:
		return resource_mgr
	if is_inside_tree() and has_node("/root/ResourceManager"):
		return get_node_or_null("/root/ResourceManager")
	return null

var pending_death_cargo: Dictionary = {}

func add_pending_death_cargo(res_type: String, amount: int) -> void:
	if amount <= 0 or res_type.is_empty():
		return
	pending_death_cargo[res_type] = int(pending_death_cargo.get(res_type, 0)) + amount

func get_pending_death_cargo(res_type: String = "") -> Variant:
	if res_type.is_empty():
		return pending_death_cargo.duplicate()
	return int(pending_death_cargo.get(res_type, 0))

func flush_pending_death_cargo() -> Dictionary:
	var rm: Object = _get_resource_mgr()
	if rm == null or not rm.has_method("add_resource"):
		return {"recovered": {}, "remaining": pending_death_cargo.duplicate()}
	var recovered: Dictionary = {}
	var to_erase: Array[String] = []
	for res_type in pending_death_cargo:
		var amt: int = int(pending_death_cargo[res_type])
		if amt <= 0:
			to_erase.append(res_type)
			continue
		var added: int = int(rm.call("add_resource", res_type, amt))
		if added > 0:
			recovered[res_type] = added
			pending_death_cargo[res_type] = amt - added
			if int(pending_death_cargo[res_type]) <= 0:
				to_erase.append(res_type)
	for r in to_erase:
		pending_death_cargo.erase(r)
	return {"recovered": recovered, "remaining": pending_death_cargo.duplicate()}

func _ready() -> void:
	DisplayServer.window_set_min_size(Vector2i(1024, 576))
	_load_assets()
	_generate_and_build_world()
	_setup_ghost_preview()
	
	# Connect HUD signals
	if hud:
		hud.world_view_ref = self
		if hud.has_method("initialize_minimap"):
			hud.initialize_minimap(self)
		if hud.has_method("set_minimap_debug_fog_disabled"):
			hud.call("set_minimap_debug_fog_disabled", debug_fog_disabled)
		var housing_cap: int = BuildingSystem.get_total_housing_capacity(world_data)
		hud.update_population_display(citizen_list.size(), housing_cap)
		hud.return_to_menu_requested.connect(_on_return_to_menu)
		hud.build_requested.connect(_on_build_requested)
		hud.citizen_role_changed.connect(_on_citizen_role_changed)
		
	# Connect to TimeManager simulation clock
	if Engine.has_singleton("TimeManager") or get_node_or_null("/root/TimeManager"):
		var tm = get_node("/root/TimeManager")
		tm.hour_passed.connect(_on_simulation_hour_passed)
		tm.day_passed.connect(_on_simulation_day_passed)
		if tm.has_signal("day_phase_changed"):
			tm.day_phase_changed.connect(_on_day_phase_changed)
	_ensure_settlement_simulation_manager()
	if not is_loading_save and settlement_simulation_manager != null and settlement_simulation_manager.has_method("seed_initial_populations"):
		settlement_simulation_manager.seed_initial_populations()
	if terrain_layer != null:
		terrain_layer.z_index = -3000
	sync_day_night_visuals()
		
	# Focus camera on settlement plaza
	if camera:
		var start_focus: Vector2i = world_data.center_spawn if world_data != null else Vector2i(32, 32)
		camera.focus_on_cell(start_focus)
		
	var am = get_node_or_null("/root/AudioManager")
	if am:
		am.start_ambient_music()
		
	if world_data != null:
		print("[WorldView] %dx%d Isometric World generated from seed: %d" % [world_data.map_width, world_data.map_height, world_seed])

func _load_assets() -> void:
	terrain_textures[WorldGenerator.TerrainType.GRASS] = load("res://assets/terrain/tile_grass.png")
	terrain_textures[WorldGenerator.TerrainType.DIRT] = load("res://assets/terrain/tile_dirt.png")
	terrain_textures[WorldGenerator.TerrainType.WATER] = load("res://assets/terrain/tile_water.png")
	terrain_textures[WorldGenerator.TerrainType.SAND] = load("res://assets/terrain/tile_sand.png")
	terrain_textures[WorldGenerator.TerrainType.HILLS] = terrain_textures[WorldGenerator.TerrainType.DIRT]
	terrain_textures[WorldGenerator.TerrainType.MOUNTAINS] = terrain_textures[WorldGenerator.TerrainType.DIRT]
	
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
	if ResourceLoader.exists("res://assets/buildings/bld_cookhouse.png"):
		building_textures["cookhouse"] = load("res://assets/buildings/bld_cookhouse.png")
	else:
		building_textures["cookhouse"] = building_textures.get("house", building_textures.get("workshop", null))
	
	prop_textures["tree"] = load("res://assets/props/prop_tree.png")
	prop_textures["rock"] = load("res://assets/props/prop_rock.png")
	prop_textures["poi_ruins"] = EntityVisualRegistry.get_poi_texture("ruins", false)
	prop_textures["poi_ancient_ruins"] = EntityVisualRegistry.get_poi_texture("ancient_ruins", false)
	prop_textures["poi_abandoned_camp"] = EntityVisualRegistry.get_poi_texture("abandoned_camp", false)
	prop_textures["poi_forgotten_cache"] = EntityVisualRegistry.get_poi_texture("forgotten_cache", false)
	prop_textures["ore_deposit"] = _make_resource_prop_texture("ore_deposit")
	prop_textures["crystal_vein"] = _make_resource_prop_texture("crystal_vein")
	prop_textures["herb_patch"] = _make_resource_prop_texture("herb_patch")
	prop_textures["berry_bush"] = _make_resource_prop_texture("berry_bush")

	cursor_highlight.texture = load("res://assets/ui/cursor_diamond.png")
	cursor_highlight.offset = Vector2(-16.0, -8.0)
	cursor_highlight.centered = false

func _make_resource_prop_texture(res_type: String) -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	match res_type:
		"ore_deposit":
			# Dark iron/copper rock mound with metallic ore glints
			for y in range(12, 27):
				for x in range(7, 25):
					var dx := (x - 16) / 9.0
					var dy := (y - 20) / 7.0
					if dx * dx + dy * dy <= 1.0:
						var col := Color8(78, 82, 92) if (x + y) % 3 != 0 else Color8(184, 118, 56)
						if y < 17:
							col = col.lightened(0.18)
						img.set_pixel(x, y, col)
			for p in [Vector2i(13, 17), Vector2i(18, 16), Vector2i(16, 20), Vector2i(20, 21)]:
				img.set_pixel(p.x, p.y, Color8(230, 160, 75))
				img.set_pixel(p.x + 1, p.y, Color8(250, 205, 115))
		"crystal_vein":
			# Glowing cyan/violet crystal shards emerging from stone base
			for y in range(18, 27):
				for x in range(8, 24):
					if absi(x - 16) + absi(y - 22) <= 7:
						img.set_pixel(x, y, Color8(64, 68, 84))
			for x in range(13, 19):
				for y in range(7, 21):
					if absi(x - 16) <= (y - 6) / 3:
						img.set_pixel(x, y, Color8(80, 225, 255) if x < 16 else Color8(145, 245, 255))
			for x in range(9, 13):
				for y in range(12, 22):
					img.set_pixel(x, y, Color8(130, 110, 245))
			for x in range(19, 23):
				for y in range(11, 22):
					img.set_pixel(x, y, Color8(70, 200, 240))
		"herb_patch":
			# Lush emerald/mint leafy herb cluster with tiny blossoms
			for y in range(13, 27):
				for x in range(7, 25):
					var dx := (x - 16) / 9.0
					var dy := (y - 20) / 7.0
					if dx * dx + dy * dy <= 1.0 and ((x * 3 + y * 5) % 4 != 0):
						img.set_pixel(x, y, Color8(46, 148, 72) if y > 19 else Color8(78, 192, 98))
			for p in [Vector2i(11, 16), Vector2i(16, 14), Vector2i(20, 17), Vector2i(14, 21)]:
				img.set_pixel(p.x, p.y, Color8(235, 245, 160))
				img.set_pixel(p.x, p.y + 1, Color8(180, 235, 120))
		"berry_bush":
			# Rounded green bush dotted with bright red berries
			for y in range(11, 27):
				for x in range(6, 26):
					var dx := (x - 16) / 9.5
					var dy := (y - 19) / 7.5
					if dx * dx + dy * dy <= 1.0:
						img.set_pixel(x, y, Color8(38, 118, 46) if y > 19 else Color8(56, 152, 62))
			for p in [Vector2i(11, 15), Vector2i(15, 13), Vector2i(19, 16), Vector2i(13, 20), Vector2i(18, 21), Vector2i(21, 19)]:
				img.set_pixel(p.x, p.y, Color8(220, 42, 54))
				img.set_pixel(p.x + 1, p.y, Color8(255, 110, 115))
	return ImageTexture.create_from_image(img)

func _setup_ghost_preview() -> void:
	ghost_building_node = Node2D.new()
	ghost_building_node.name = "GhostBuildingPreview"
	ghost_building_node.visible = false
	ghost_building_node.z_index = 20
	
	ghost_building_sprite = Sprite2D.new()
	ghost_building_sprite.centered = false
	ghost_building_node.add_child(ghost_building_sprite)
	$World.add_child(ghost_building_node)

	_bridge_preview_overlay = Node2D.new()
	_bridge_preview_overlay.name = "BridgePreviewOverlay"
	_bridge_preview_overlay.visible = false
	_bridge_preview_overlay.z_index = 20
	_bridge_preview_overlay.draw.connect(_on_bridge_preview_draw)
	$World.add_child(_bridge_preview_overlay)

func _generate_and_build_world() -> void:
	var rm_init = _get_resource_mgr()
	if rm_init != null and rm_init.has_method("reset_economy"):
		rm_init.reset_economy()
	world_data = WorldGenerator.generate(world_seed, world_generator_version)
	if world_data == null:
		push_error("[WorldView] Failed to generate world for unsupported version %d; cannot construct world." % world_generator_version)
		return
	IsoMath.set_active_map_dimensions(world_data.map_width, world_data.map_height)
	if camera != null and camera.has_method("set_map_dimensions"):
		camera.set_map_dimensions(world_data.map_width, world_data.map_height)
	nav = GridNavigation.new(world_data)
	territory_mgr = TerritoryManagerScript.new()
	territory_mgr.initialize(world_data)
	if not territory_mgr.territory_changed.is_connected(_on_territory_changed):
		territory_mgr.territory_changed.connect(_on_territory_changed)
	job_mgr = JobManager.new()
	workplace_mgr = WorkplaceManager.new()
	cookhouse_mgr = CookhouseManager.new()
	cookhouse_mgr.sync_from_world_data(world_data)
	automation_mgr = AutomationManager.new()
	
	research_mgr = ResearchManager.new()
	research_mgr.set_hall_checker(func(): return BuildingSystem.is_research_hall_active(world_data))
	fog_of_war = FogOfWar.new(world_data.map_width, world_data.map_height)
	fog_of_war.reveal_circle(world_data.center_spawn, 10)
	
	poi_mgr = POIManager.new()
	poi_mgr.poi_revealed.connect(_on_poi_revealed)
	poi_mgr.poi_state_changed.connect(_on_poi_state_changed)
	poi_mgr.poi_reward_claimed.connect(_on_poi_reward_claimed)
	
	event_system = WorldEventSystem.new(world_seed)
	event_system.set_world_modifiers(world_modifiers)
	crisis_mgr = CrisisManagerScript.new(world_seed)
	crisis_mgr.set_world_modifiers(world_modifiers)
	if crisis_mgr.has_method("set_damage_handler"):
		crisis_mgr.set_damage_handler(Callable(self, "damage_building"))
	event_system.set_crisis_manager(crisis_mgr)
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
	victory_mgr.set("world_view", self)
	battle_campaign_mgr = BattleCampaignManagerScript.new(self, faction_mgr, world_seed)
	player_army_mgr = PlayerArmyManagerScript.new(self)
	tactical_military_mgr = TacticalMilitaryManagerScript.new(self, player_army_mgr)
	player_army_mgr.set_tactical_military_manager(tactical_military_mgr)
	enemy_military_mgr = EnemyMilitaryManagerScript.new(self, faction_mgr)
	field_siege_mgr = FieldSiegeManagerScript.new(self, faction_mgr, player_army_mgr, enemy_military_mgr)
	if entity_container != null:
		var siege_cont := entity_container.get_node_or_null("SiegeObjectives")
		if siege_cont == null:
			siege_cont = Node2D.new()
			siege_cont.name = "SiegeObjectives"
			siege_cont.y_sort_enabled = true
			entity_container.add_child(siege_cont)
		field_siege_mgr.set_objectives_container(siege_cont)
	enemy_military_mgr.set_field_siege_manager(field_siege_mgr)
	enemy_military_mgr.set_tactical_military_manager(tactical_military_mgr)
	var rm_node = get_node_or_null("/root/ResourceManager")
	if rm_node != null:
		field_siege_mgr.set_resource_manager(rm_node)
	land_clearing_mgr = LandClearingManagerScript.new()
	land_clearing_mgr.prop_cleared.connect(_on_land_clearing_prop_cleared)
	land_clearing_mgr.clearing_orders_changed.connect(_on_land_clearing_orders_changed)
	natural_resource_mgr = NaturalResourceManager.new()
	natural_resource_mgr.node_depleted.connect(func(_nid: String, _ptype: String, cell: Vector2i):
		remove_prop_visual_at_cell(cell)
	)
	natural_resource_mgr.sync_from_world_data(world_data)
	var walkable: Array[Vector2i] = []
	var poi_excl: Dictionary = {}
	for rc in natural_resource_mgr.nodes_by_cell.keys():
		poi_excl[rc] = true
	if world_data.get("props") != null:
		for pr in world_data.props:
			if pr is Dictionary and pr.has("cell"):
				poi_excl[pr["cell"]] = true
	if world_data.get("bridges") != null:
		for br in world_data.bridges:
			for bc in br.get("cells", []):
				poi_excl[bc] = true
	for x in range(world_data.map_width):
		for y in range(world_data.map_height):
			var w_cell := Vector2i(x, y)
			if nav.is_walkable(w_cell):
				walkable.append(w_cell)
				if territory_mgr != null and territory_mgr.is_cell_owned(w_cell):
					poi_excl[w_cell] = true
	poi_mgr.generate_pois(world_seed, walkable, -1, true, poi_excl, world_data.center_spawn)
	wildlife_mgr = WildlifeManagerScript.new()
	var wl_parent: Node = props_container.get_parent() if props_container != null else self
	if wl_parent != null:
		wildlife_container = Node2D.new()
		wildlife_container.name = "WildlifeContainer"
		wildlife_container.y_sort_enabled = true
		wl_parent.add_child(wildlife_container)
		wildlife_mgr.set_container(wildlife_container)
	wildlife_mgr.generate_initial_population(world_data, nav)
	wildlife_mgr.refresh_visibility(fog_of_war, debug_fog_disabled)
	register_debug_inspect_provider(func(c: Vector2i) -> Dictionary:
		if wildlife_mgr != null:
			return wildlife_mgr.inspect_cell(c, world_data, fog_of_war, debug_fog_disabled)
		return {}
	)
	monster_mgr = MonsterManagerScript.new()
	if wl_parent != null:
		monsters_container = Node2D.new()
		monsters_container.name = "MonstersContainer"
		monsters_container.y_sort_enabled = true
		wl_parent.add_child(monsters_container)
		monster_mgr.set_container(monsters_container)
	monster_mgr.generate_initial_world(world_data, nav, territory_mgr, poi_mgr, natural_resource_mgr)
	monster_mgr.refresh_visibility(fog_of_war, debug_fog_disabled)
	register_debug_inspect_provider(func(c: Vector2i) -> Dictionary:
		if monster_mgr != null:
			return monster_mgr.inspect_cell(c, world_data, fog_of_war, debug_fog_disabled)
		return {}
	)
	if rm_node != null and rm_node.has_signal("resource_changed"):
		rm_node.resource_changed.connect(func(_res_id: String, _amt: int, _cap: int):
			if land_clearing_mgr != null:
				land_clearing_mgr.try_finalize_waiting_orders(world_data, rm_node, self, citizen_list)
		)
	_setup_clear_land_overlay()
	_setup_territory_overlay()
	field_siege_mgr.field_siege_resolved.connect(func(_sid: String, outcome: String, _details: Dictionary):
		if hud != null:
			if outcome == "DEFEAT":
				hud.show_event_banner("Thất Bại Công Thành!", "Toàn bộ lực lượng công thành đã bị đẩy lui.", false, 5.0)
			elif outcome == "WITHDRAWAL":
				hud.show_event_banner("Rút Quân Công Thành", "Lực lượng công thành đã rút lui khỏi chiến địa.", false, 4.0)
	)
	field_siege_mgr.outpost_ownership_changed.connect(func(_obj_id: String, prev_owner: String, new_owner: String, _tx_id: String):
		refresh_world_vision()
		if prev_owner == "player" and player_army_mgr != null and player_army_mgr.has_method("cancel_outpost_reinforcements"):
			player_army_mgr.call("cancel_outpost_reinforcements", _obj_id, true)
		if hud != null:
			var prev_name := _get_faction_display_name(prev_owner)
			if new_owner == "player":
				var title := "ĐÃ CHIẾM TIỀN ĐỒN!"
				var desc := "Quân đội hoàng gia đã chiếm tiền đồn của %s. Quyền kiểm soát hiện thuộc về Vương quốc của bạn." % prev_name
				hud.show_event_banner(title, desc, true, 5.0)
			else:
				var new_name := _get_faction_display_name(new_owner)
				var title := "BIẾN ĐỘNG LÃNH THỔ!"
				var desc := "%s đã chiếm tiền đồn từ %s." % [new_name, prev_name]
				hud.show_event_banner(title, desc, true, 5.0)
	)
	if field_siege_mgr.has_signal("objective_registered"):
		field_siege_mgr.objective_registered.connect(func(_oid: String, _cell: Vector2i, _fid: String): refresh_world_vision())
	if field_siege_mgr.has_signal("objective_destroyed"):
		field_siege_mgr.objective_destroyed.connect(func(_oid: String, _killer: String):
			refresh_world_vision()
			if player_army_mgr != null and player_army_mgr.has_method("evict_and_cancel_outpost"):
				player_army_mgr.call("evict_and_cancel_outpost", _oid, true, true)
		)
	if field_siege_mgr.has_signal("objective_unregistered"):
		field_siege_mgr.objective_unregistered.connect(func(_oid: String): refresh_world_vision())

	# Package 3B: Connect military movement & unit lifecycle to fog of war reconnaissance
	if tactical_military_mgr != null:
		if tactical_military_mgr.has_signal("unit_moved"):
			tactical_military_mgr.unit_moved.connect(_on_tactical_unit_moved)
		if tactical_military_mgr.has_signal("unit_spawned"):
			tactical_military_mgr.unit_spawned.connect(_on_tactical_unit_spawned)
		if tactical_military_mgr.has_signal("unit_despawned"):
			tactical_military_mgr.unit_despawned.connect(_on_tactical_unit_despawned)
	if player_army_mgr != null and player_army_mgr.has_signal("army_moved"):
		player_army_mgr.army_moved.connect(_on_player_army_moved)
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
		if crisis_mgr != null:
			crisis_mgr.crisis_warning_issued.connect(func(w: Dictionary): hud.show_crisis_warning(w))
			crisis_mgr.crisis_started.connect(func(w: Dictionary): hud.show_crisis_active(w))
			crisis_mgr.crisis_resolved.connect(func(w: Dictionary): hud.show_crisis_resolved(w))
	
	_setup_workplaces()
	_create_workplace_jobs()
	_render_terrain()
	_setup_fog_layer()
	_spawn_starter_buildings()
	_spawn_props()
	_spawn_pois()
	_spawn_starter_citizens()
	_setup_army_marker()
	refresh_caravan_marker()
	sync_rival_settlements_visuals()
	_setup_default_siege_objectives()
	refresh_world_vision()
	_apply_starting_perks_and_modifiers()

	if faction_mgr != null:
		if faction_mgr.has_signal("war_declared") and not faction_mgr.war_declared.is_connected(_on_faction_war_declared):
			faction_mgr.war_declared.connect(_on_faction_war_declared)
		if faction_mgr.has_signal("peace_signed") and not faction_mgr.peace_signed.is_connected(_on_faction_peace_signed):
			faction_mgr.peace_signed.connect(_on_faction_peace_signed)

func _apply_starting_perks_and_modifiers() -> void:
	if is_perks_and_modifiers_applied:
		return
	is_perks_and_modifiers_applied = true

	var rm: Object = _get_resource_mgr()

	# 1. Apply Active Starting Perks (One-time at campaign genesis)
	for perk in active_perks:
		var p_id := str(perk).strip_edges()
		match p_id:
			"starter_grain":
				if rm != null and rm.has_method("add_resource"):
					rm.add_resource("food", 50)
			"master_carpenter":
				if rm != null and rm.has_method("add_resource"):
					rm.add_resource("wood", 40)
					rm.add_resource("tools", 10)
			"hardened_outposts":
				if rm != null and rm.has_method("add_resource"):
					rm.add_resource("metal", 20)
				if player_army_mgr != null:
					var cur_s: int = int(player_army_mgr.get("soldier_count")) if player_army_mgr.get("soldier_count") != null else 0
					player_army_mgr.set("soldier_count", cur_s + 2)
					if tactical_military_mgr != null and tactical_military_mgr.has_method("sync_with_player_army"):
						var s_res = tactical_military_mgr.sync_with_player_army()
						if s_res is Dictionary and not bool(s_res.get("success", true)):
							player_army_mgr.set("soldier_count", cur_s)
							push_error("WorldView: hardened_outposts perk failed to spawn tactical units, rolling back starting soldiers.")
			"pioneer_spirit":
				for cit in citizen_list:
					if cit != null and is_instance_valid(cit):
						var cur_m: float = float(cit.get("morale")) if cit.get("morale") != null else 70.0
						cit.set("morale", clampf(cur_m + 10.0, 0.0, 100.0))

	# 2. Apply Immediate Starting World Modifiers
	for mod in world_modifiers:
		var m_id := str(mod).strip_edges()
		match m_id:
			"arid_realm":
				if rm != null and rm.has_method("consume_resource"):
					rm.consume_resource("wood", 20)

func _setup_workplaces() -> void:
	_register_starter_workplace("farm_starter")
	_register_starter_workplace("woodcutter_starter")
	_register_starter_dropoff("storehouse_starter")
	_register_starter_dropoff("townhall_starter")

func _get_starter_center() -> Vector2i:
	if world_data != null:
		return Vector2i(world_data.map_width / 2, world_data.map_height / 2)
	return Vector2i(32, 32)

func _register_starter_workplace(starter_id: String) -> void:
	if workplace_mgr == null:
		return
	var center := _get_starter_center()
	if starter_id == "farm_starter":
		workplace_mgr.register_workplace("farm_starter", "farm", center + Vector2i(4, 3), Vector2i(2, 2), center + Vector2i(3, 3), EconomyConfig.RES_FOOD, 50, 5.0, 5)
	elif starter_id == "woodcutter_starter":
		workplace_mgr.register_workplace("woodcutter_starter", "woodcutter", center + Vector2i(-6, -2), Vector2i(2, 2), center + Vector2i(-4, -2), EconomyConfig.RES_WOOD, 40, 4.0, 4)

func _register_starter_dropoff(dropoff_id: String) -> void:
	if workplace_mgr == null:
		return
	var center := _get_starter_center()
	if dropoff_id == "storehouse_starter":
		workplace_mgr.register_dropoff("storehouse_starter", "storehouse", center + Vector2i(0, -3))
	elif dropoff_id == "townhall_starter":
		workplace_mgr.register_dropoff("townhall_starter", "townhall", center + Vector2i(-1, 2))

func _create_workplace_jobs() -> void:
	_create_starter_jobs("farm_starter")
	_create_starter_jobs("woodcutter_starter")

func _create_starter_jobs(starter_id: String) -> void:
	if job_mgr == null:
		return
	var center := _get_starter_center()
	if starter_id == "farm_starter":
		for i in range(5):
			var target := Vector2i(center.x + 3 + (i % 2), center.y + 3 + int(float(i) / 2.0))
			job_mgr.create_job("farmer", target, "Chăm sóc và thu hoạch nông sản", "farm_starter", 3.0, 1, true)
	elif starter_id == "woodcutter_starter":
		for i in range(4):
			var target := Vector2i(center.x - 7 + (i % 2), center.y - 3 + int(float(i) / 2.0))
			job_mgr.create_job("woodcutter", target, "Khai thác và chế biến gỗ", "woodcutter_starter", 3.0, 1, true)

func rebuild_world_terrain_for_load(p_seed: int, p_gen_ver: int, p_width: int = -1, p_height: int = -1, stage_e_snapshot_settlements: Variant = null) -> bool:
	if not WorldGenerator.is_supported_generator_version(p_gen_ver):
		push_error("[WorldView] Unsupported world_generator_version %d during load." % p_gen_ver)
		return false
	var new_data := WorldGenerator.generate(p_seed, p_gen_ver, p_width, p_height, stage_e_snapshot_settlements)
	if new_data == null:
		return false
	world_seed = p_seed
	world_generator_version = p_gen_ver
	world_data = new_data
	IsoMath.set_active_map_dimensions(world_data.map_width, world_data.map_height)
	if camera != null and camera.has_method("set_map_dimensions"):
		camera.set_map_dimensions(world_data.map_width, world_data.map_height)
	nav = GridNavigation.new(world_data)
	if territory_mgr == null:
		territory_mgr = TerritoryManagerScript.new()
	territory_mgr.initialize(world_data)
	if not territory_mgr.territory_changed.is_connected(_on_territory_changed):
		territory_mgr.territory_changed.connect(_on_territory_changed)
	if terrain_layer != null:
		for child in terrain_layer.get_children():
			child.queue_free()
		_render_terrain()
	_setup_fog_layer()
	if props_container != null:
		prop_nodes_by_cell.clear()
		for child in props_container.get_children():
			if not child.name.begins_with("POI_"):
				child.queue_free()
		_spawn_props()
	sync_rival_settlements_visuals()
	return true

func _get_biome_terrain_modulate(t_type: int, biome_id: int) -> Color:
	var base := Color(1.0, 1.0, 1.0, 1.0)
	if t_type == WorldGenerator.TerrainType.HILLS:
		base = Color(0.92, 0.88, 0.76, 1.0)
	elif t_type == WorldGenerator.TerrainType.MOUNTAINS:
		base = Color(0.55, 0.54, 0.62, 1.0)

	match biome_id:
		WorldGenerator.BiomeType.TEMPERATE_FOREST:
			if t_type == WorldGenerator.TerrainType.GRASS:
				return Color(0.78, 0.92, 0.72, 1.0)
			if t_type == WorldGenerator.TerrainType.DIRT:
				return Color(0.84, 0.78, 0.68, 1.0)
		WorldGenerator.BiomeType.PINE_FOREST:
			if t_type == WorldGenerator.TerrainType.GRASS:
				return Color(0.66, 0.84, 0.82, 1.0)
			if t_type == WorldGenerator.TerrainType.DIRT:
				return Color(0.76, 0.78, 0.82, 1.0)
			if t_type == WorldGenerator.TerrainType.HILLS:
				return Color(0.78, 0.84, 0.84, 1.0)
		WorldGenerator.BiomeType.HIGHLANDS:
			if t_type == WorldGenerator.TerrainType.GRASS:
				return Color(0.88, 0.84, 0.64, 1.0)
			if t_type == WorldGenerator.TerrainType.DIRT:
				return Color(0.86, 0.82, 0.76, 1.0)
			if t_type == WorldGenerator.TerrainType.HILLS:
				return Color(0.90, 0.86, 0.74, 1.0)
			if t_type == WorldGenerator.TerrainType.MOUNTAINS:
				return Color(0.54, 0.53, 0.63, 1.0)
		WorldGenerator.BiomeType.WETLANDS:
			if t_type == WorldGenerator.TerrainType.GRASS:
				return Color(0.64, 0.78, 0.60, 1.0)
			if t_type == WorldGenerator.TerrainType.DIRT:
				return Color(0.60, 0.56, 0.46, 1.0)
			if t_type == WorldGenerator.TerrainType.WATER:
				return Color(0.74, 0.88, 0.82, 1.0)
	return base

func _build_terrain_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = Vector2i(int(IsoMath.TILE_WIDTH), int(IsoMath.TILE_HEIGHT))
	var fallback_tex: Texture2D = terrain_textures.get(WorldGenerator.TerrainType.GRASS)
	var terrain_types: Array[int] = [
		WorldGenerator.TerrainType.WATER,
		WorldGenerator.TerrainType.SAND,
		WorldGenerator.TerrainType.GRASS,
		WorldGenerator.TerrainType.DIRT,
		WorldGenerator.TerrainType.HILLS,
		WorldGenerator.TerrainType.MOUNTAINS,
	]
	var biome_ids: Array[int] = [
		WorldGenerator.BiomeType.GRASSLAND,
		WorldGenerator.BiomeType.TEMPERATE_FOREST,
		WorldGenerator.BiomeType.PINE_FOREST,
		WorldGenerator.BiomeType.HIGHLANDS,
		WorldGenerator.BiomeType.WETLANDS,
	]
	for t_type in terrain_types:
		var tex: Texture2D = terrain_textures.get(t_type, fallback_tex)
		if tex == null:
			continue
		var source := TileSetAtlasSource.new()
		source.texture = tex
		var tex_sz := tex.get_size()
		source.texture_region_size = Vector2i(maxi(1, int(tex_sz.x)), maxi(1, int(tex_sz.y)))
		source.create_tile(Vector2i(0, 0))
		for b_id in biome_ids:
			if b_id != 0:
				source.create_alternative_tile(Vector2i(0, 0), b_id)
			var tile_data := source.get_tile_data(Vector2i(0, 0), b_id)
			if tile_data != null:
				tile_data.modulate = _get_biome_terrain_modulate(t_type, b_id)
				if t_type == WorldGenerator.TerrainType.HILLS:
					tile_data.texture_origin = Vector2i(0, 2)
				elif t_type == WorldGenerator.TerrainType.MOUNTAINS:
					tile_data.texture_origin = Vector2i(0, 6)
		ts.add_source(source, t_type)
	return ts

func _render_terrain() -> void:
	if terrain_layer == null or world_data == null:
		return
	var tml := TileMapLayer.new()
	tml.name = "TerrainTileMapLayer"
	tml.tile_set = _build_terrain_tileset()
	# TileMapLayer DIAMOND_DOWN map_to_local(0,0) is (16, 8), whereas IsoMath.map_to_local(0,0) is (0, 0).
	tml.position = Vector2(-IsoMath.HALF_WIDTH, -IsoMath.HALF_HEIGHT)
	for x in range(world_data.map_width):
		for y in range(world_data.map_height):
			var t_type: int = world_data.terrain[x][y]
			if not tml.tile_set.has_source(t_type):
				t_type = WorldGenerator.TerrainType.GRASS
			var b_id: int = world_data.get_biome(Vector2i(x, y))
			tml.set_cell(Vector2i(x, y), t_type, Vector2i(0, 0), b_id)
	terrain_layer.add_child(tml)

func _spawn_starter_buildings() -> void:
	var center := _get_starter_center()
	for bld in world_data.buildings:
		if not bld.has("id") or bld["id"] == "":
			var b_type: String = bld.get("type", "")
			var b_cell: Vector2i = bld.get("cell", Vector2i.ZERO)
			if b_type == "farm" and b_cell == center + Vector2i(4, 3):
				bld["id"] = "farm_starter"
			elif b_type == "woodcutter" and b_cell == center + Vector2i(-6, -2):
				bld["id"] = "woodcutter_starter"
			elif b_type == "townhall":
				bld["id"] = "townhall_starter"
				bld["storage_applied"] = true
				if world_data != null and world_data.townhall_anchor.x < 0:
					world_data.townhall_anchor = b_cell
			elif b_type == "storehouse":
				bld["id"] = "storehouse_starter"
				bld["storage_applied"] = true
			else:
				bld["id"] = "bld_%s_%d_%d" % [b_type, b_cell.x, b_cell.y]
		if not bld.has("state"):
			bld["state"] = "active"
		if not bld.has("health"):
			bld["health"] = 100
		_instantiate_building_node(bld["type"], bld["cell"], bld["size"], bld.get("state", "active"))

func _create_building_sprite_node(type: String, origin: Vector2i, size: Vector2i, node_name: String, state: String = "active") -> Node2D:
	var tex: Texture2D = building_textures.get(type)
	if not tex:
		return null

	var b_node := Node2D.new()
	b_node.name = node_name
	b_node.y_sort_enabled = true

	# Bottom center of footprint diamond for exact Y-sorting
	var base_vertex := origin + Vector2i(size.x - 1, size.y - 1)
	b_node.position = IsoMath.map_to_local(base_vertex)
	b_node.z_index = IsoMath.world_y_to_z_index(b_node.position.y)

	var spr := Sprite2D.new()
	spr.name = "Sprite2D"
	spr.texture = tex
	spr.centered = false
	spr.offset = _get_building_sprite_offset(type)
	if state == "under_construction":
		spr.modulate = Color(0.8, 0.7, 0.5, 0.7)
	elif state == "paused":
		spr.modulate = Color(0.7, 0.7, 0.7, 0.85)
	elif state == "damaged":
		spr.modulate = Color(0.85, 0.45, 0.45, 0.9)
	elif state == "destroyed":
		spr.modulate = Color(0.35, 0.25, 0.25, 0.7)
	else:
		spr.modulate = Color(1.0, 1.0, 1.0, 1.0)

	b_node.add_child(spr)
	return b_node

func _instantiate_building_node(type: String, origin: Vector2i, size: Vector2i, state: String = "active") -> Node2D:
	var b_node := _create_building_sprite_node(type, origin, size, "Building_%s_%d_%d" % [type, origin.x, origin.y], state)
	if b_node == null:
		return null

	buildings_container.add_child(b_node)
	
	# Register building footprint for tile inspection
	for ox in range(size.x):
		for oy in range(size.y):
			buildings_by_cell[origin + Vector2i(ox, oy)] = type

	_refresh_objective_building_overlaps()
	return b_node

class _RivalDecorationNode extends Node2D:
	var dec_type: String = ""
	var faction_id: String = ""

	func _draw() -> void:
		if dec_type == "faction_banner":
			var banner_color: Color
			match faction_id:
				"rival_military":
					banner_color = Color(0.85, 0.2, 0.2, 0.95) # Crimson Red
				"rival_merchant":
					banner_color = Color(0.92, 0.72, 0.15, 0.95) # Amber Gold
				"neutral_tribe":
					banner_color = Color(0.2, 0.75, 0.35, 0.95) # Forest Green
				_:
					banner_color = Color(0.65, 0.65, 0.65, 0.95)
			draw_line(Vector2(0, 0), Vector2(0, -22), Color(0.22, 0.16, 0.12, 1.0), 1.5)
			var pts := PackedVector2Array([
				Vector2(0, -21),
				Vector2(10, -17),
				Vector2(0, -13)
			])
			draw_colored_polygon(pts, banner_color)
			draw_polyline(pts, Color(0.15, 0.1, 0.08, 0.9), 1.0, true)
		elif dec_type == "campfire":
			draw_circle(Vector2(0, 0), 5.0, Color(0.32, 0.28, 0.25, 0.9))
			draw_circle(Vector2(0, -1), 3.0, Color(0.95, 0.55, 0.15, 0.95))
			draw_circle(Vector2(0, -2), 1.6, Color(1.0, 0.85, 0.35, 0.95))

func _is_cell_explored_or_debug(cell: Vector2i) -> bool:
	return debug_fog_disabled or (fog_of_war != null and fog_of_war.is_explored(cell))

func sync_rival_settlements_visuals() -> void:
	rival_buildings_by_cell.clear()
	_rival_settlement_visuals.clear()

	if entity_container == null:
		return

	if rival_settlements_container == null or not is_instance_valid(rival_settlements_container):
		var existing := entity_container.get_node_or_null("RivalSettlements")
		if existing is Node2D:
			rival_settlements_container = existing
		else:
			rival_settlements_container = Node2D.new()
			rival_settlements_container.name = "RivalSettlements"
			rival_settlements_container.y_sort_enabled = true
			entity_container.add_child(rival_settlements_container)

	if rival_presentation_controller != null and is_instance_valid(rival_presentation_controller):
		rival_presentation_controller.on_before_rival_settlements_rebuild()
	_rival_settlement_groups.clear()

	for child in rival_settlements_container.get_children():
		rival_settlements_container.remove_child(child)
		child.queue_free()

	if world_data == null or world_data.get("settlements") == null:
		return

	for stl in world_data.settlements:
		if stl == null:
			continue
		var sid: String = str(stl.get("settlement_id"))
		var owner_fid: String = str(stl.get("owner_faction_id"))
		var origin_fid: String = str(stl.get("origin_faction_id"))

		var stl_group := Node2D.new()
		stl_group.name = sid if not sid.is_empty() else "Settlement_%s" % origin_fid
		stl_group.y_sort_enabled = true
		rival_settlements_container.add_child(stl_group)
		if not sid.is_empty():
			_rival_settlement_groups[sid] = stl_group

		var b_list: Array = stl.get("buildings") if stl.get("buildings") is Array else []
		for b in b_list:
			if not (b is Dictionary):
				continue
			var b_type: String = str(b.get("type", ""))
			var b_id: String = str(b.get("id", ""))
			var b_origin: Vector2i = b.get("cell", Vector2i.ZERO)
			var b_size: Vector2i = b.get("size", Vector2i.ONE)
			var b_node := _create_building_sprite_node(b_type, b_origin, b_size, "RivalBld_%s_%s" % [sid, b_id], "active")
			if b_node != null:
				b_node.set_meta("settlement_id", sid)
				b_node.set_meta("faction_id", owner_fid)
				b_node.set_meta("building_role", str(b.get("role", "")))
				var vis_cell: Vector2i = b_origin + Vector2i(b_size.x / 2, b_size.y / 2)
				b_node.visible = _is_cell_explored_or_debug(vis_cell)
				stl_group.add_child(b_node)
				_rival_settlement_visuals.append({"node": b_node, "vis_cell": vis_cell})

			for ox in range(b_size.x):
				for oy in range(b_size.y):
					var f_cell := b_origin + Vector2i(ox, oy)
					rival_buildings_by_cell[f_cell] = {
						"type": b_type,
						"faction_id": owner_fid,
						"origin_faction_id": origin_fid,
						"settlement_id": sid
					}

		var d_list: Array = stl.get("decorations") if stl.get("decorations") is Array else []
		for idx in range(d_list.size()):
			var dec = d_list[idx]
			if not (dec is Dictionary):
				continue
			var d_type: String = str(dec.get("type", ""))
			if d_type != "faction_banner" and d_type != "campfire":
				continue
			var d_cell: Vector2i = dec.get("cell", Vector2i.ZERO)
			var d_node := _RivalDecorationNode.new()
			d_node.name = "RivalDec_%s_%d" % [sid, idx]
			d_node.y_sort_enabled = true
			d_node.dec_type = d_type
			d_node.faction_id = owner_fid if not owner_fid.is_empty() else str(dec.get("faction_id", origin_fid))
			d_node.position = IsoMath.map_to_local(d_cell)
			d_node.z_index = IsoMath.world_y_to_z_index(d_node.position.y)
			d_node.visible = _is_cell_explored_or_debug(d_cell)
			stl_group.add_child(d_node)
			_rival_settlement_visuals.append({"node": d_node, "vis_cell": d_cell})

func _refresh_objective_building_overlaps() -> void:
	if field_siege_mgr == null or not field_siege_mgr.has_method("get_all_objectives"):
		return
	for obj in field_siege_mgr.call("get_all_objectives"):
		if obj == null or not is_instance_valid(obj):
			continue
		var linked_sid: String = str(obj.get("linked_settlement_id")) if obj.get("linked_settlement_id") != null else ""
		var should_overlap := false
		if linked_sid.is_empty() and not buildings_by_cell.is_empty():
			var origin: Vector2i = obj.current_cell
			var size: Vector2i = obj.get("size") if (obj.get("size") is Vector2i) else Vector2i(2, 2)
			for ox in range(size.x):
				for oy in range(size.y):
					if buildings_by_cell.has(origin + Vector2i(ox, oy)):
						should_overlap = true
						break
				if should_overlap:
					break
		var prev_overlap := bool(obj.get("is_player_building_overlapping"))
		if prev_overlap != should_overlap:
			obj.set("is_player_building_overlapping", should_overlap)
			obj.queue_redraw()

func apply_settlement_overlays_from_world_data(excluded_cells: Dictionary = {}) -> void:
	if world_data == null:
		return
	world_data.settlement_reserved_cells.clear()
	var stl_list: Array = world_data.settlements if world_data.get("settlements") is Array else []
	if stl_list.is_empty():
		sync_rival_settlements_visuals()
		return

	# 1. Reapply solid settlement occupancy and reserved cells (excluding player-occupied cells)
	if ResourceLoader.exists("res://scripts/world/settlement_generator.gd"):
		var SettlementGeneratorScript = load("res://scripts/world/settlement_generator.gd")
		SettlementGeneratorScript.apply_settlement_reservations_and_occupancy(world_data, stl_list, true, true, excluded_cells)

	# 2. Reapply road TERRAIN_DIRT and update TerrainTileMapLayer cells
	var tml: TileMapLayer = terrain_layer.get_node_or_null("TerrainTileMapLayer") as TileMapLayer if terrain_layer != null else null
	for stl in stl_list:
		if stl == null:
			continue
		var r_list: Array = stl.get("roads") if stl.get("roads") is Array else []
		for r in r_list:
			if not (r is Vector2i) or not world_data.is_in_bounds(r):
				continue
			if excluded_cells.has(r) or world_data.occupancy[r.x][r.y]:
				continue
			var t_cur: int = int(world_data.terrain[r.x][r.y])
			if t_cur == WorldGenerator.TerrainType.WATER or t_cur == WorldGenerator.TerrainType.MOUNTAINS:
				continue
			if t_cur != WorldGenerator.TerrainType.DIRT:
				world_data.terrain[r.x][r.y] = WorldGenerator.TerrainType.DIRT
				if tml != null and tml.tile_set != null and tml.tile_set.has_source(WorldGenerator.TerrainType.DIRT):
					tml.set_cell(r, WorldGenerator.TerrainType.DIRT, Vector2i(0, 0), world_data.get_biome(r))

	sync_rival_settlements_visuals()
	_ensure_settlement_simulation_manager()

func _ensure_settlement_simulation_manager() -> void:
	return

func _get_rival_settlement_group(sid: String) -> Node2D:
	return _rival_settlement_groups.get(sid, null)

func _ensure_rival_presentation_controller() -> void:
	return

func _refresh_rival_settlement_visibility() -> void:
	for entry in _rival_settlement_visuals:
		var n = entry.get("node")
		if n != null and is_instance_valid(n):
			var vc: Vector2i = entry.get("vis_cell", Vector2i(-1, -1))
			n.visible = _is_cell_explored_or_debug(vc)

func get_rival_hover_label(cell: Vector2i) -> String:
	if fog_of_war == null or fog_of_war.is_unexplored(cell):
		return ""
	if not rival_buildings_by_cell.has(cell):
		return ""
	var rb: Dictionary = rival_buildings_by_cell[cell]
	var rb_name := _get_building_display_name(str(rb.get("type", "")))
	if rb_name.is_empty():
		return ""
	var fac_name := _get_faction_display_name(str(rb.get("faction_id", "")))
	return "%s (%s)" % [rb_name, fac_name]

func _instantiate_bridge_node(b_data: Dictionary) -> Node2D:
	if b_data.is_empty() or buildings_container == null:
		return null
	var origin: Vector2i = b_data.get("cell", Vector2i.ZERO)
	var size: Vector2i = b_data.get("size", Vector2i.ONE)
	var node_name := "Building_bridge_%d_%d" % [origin.x, origin.y]
	var existing := buildings_container.get_node_or_null(node_name)
	if existing != null:
		existing.queue_free()
	var b_node := BridgeVisualNode.new()
	b_node.setup(b_data)
	buildings_container.add_child(b_node)
	for ox in range(size.x):
		for oy in range(size.y):
			buildings_by_cell[origin + Vector2i(ox, oy)] = "bridge"
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
		"cookhouse": return Vector2(-32.0, -40.0)
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
		p_node.set_meta("cell", cell)
		p_node.set_meta("prop_type", type)
		
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.centered = false
		spr.offset = Vector2(-16.0, -40.0) if type == "tree" else Vector2(-16.0, -18.0)
		if type == "tree" and world_data != null:
			var b_id: int = world_data.get_biome(cell)
			if b_id == WorldGenerator.BiomeType.PINE_FOREST:
				spr.modulate = Color(0.70, 0.88, 0.84, 1.0)
			elif b_id == WorldGenerator.BiomeType.WETLANDS:
				spr.modulate = Color(0.80, 0.88, 0.72, 1.0)
			elif b_id == WorldGenerator.BiomeType.TEMPERATE_FOREST:
				spr.modulate = Color(0.92, 1.0, 0.90, 1.0)
			
		p_node.visible = debug_fog_disabled or (fog_of_war != null and fog_of_war.is_explored(cell))
		p_node.z_index = IsoMath.world_y_to_z_index(p_node.position.y)
		p_node.add_child(spr)
		props_container.add_child(p_node)
		prop_nodes_by_cell[cell] = p_node

func remove_prop_visual_at_cell(cell: Vector2i) -> void:
	prop_nodes_by_cell.erase(cell)
	if props_container == null:
		return
	for child in props_container.get_children():
		if child.name.begins_with("POI_"):
			continue
		if child.has_meta("cell") and child.get_meta("cell") == cell:
			props_container.remove_child(child)
			child.queue_free()

func sync_props_from_world_data() -> void:
	if props_container == null or world_data == null:
		return
	prop_nodes_by_cell.clear()
	for child in props_container.get_children():
		if not child.name.begins_with("POI_"):
			props_container.remove_child(child)
			child.queue_free()
	_spawn_props()
	if _clear_land_overlay != null and is_instance_valid(_clear_land_overlay):
		_clear_land_overlay.queue_redraw()

func _update_poi_node_visual(poi: POIManager.POIData) -> void:
	if poi == null:
		return
	var p_node: Node2D = poi_nodes_by_id.get(poi.id) as Node2D
	if not is_instance_valid(p_node):
		return
	var spr: Sprite2D = p_node.get_node_or_null("Sprite2D") as Sprite2D
	if spr == null:
		return
	var is_claimed: bool = (poi.state == POIManager.POIState.CLAIMED)
	var tex: Texture2D = EntityVisualRegistry.get_poi_texture(str(poi.type), is_claimed)
	if tex != null:
		spr.texture = tex
		spr.offset = EntityVisualRegistry.get_poi_sprite_offset(tex)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p_node.z_index = IsoMath.world_y_to_z_index(p_node.position.y)
	p_node.visible = should_debug_reveal_category("poi") or (poi.state != POIManager.POIState.UNDISCOVERED)

func _spawn_single_poi_node(poi: POIManager.POIData) -> Node2D:
	if poi == null:
		return null
	var p_node := Node2D.new()
	p_node.name = "POI_%s" % poi.id
	p_node.position = IsoMath.map_to_local(poi.cell)
	p_node.y_sort_enabled = true
	p_node.z_index = IsoMath.world_y_to_z_index(p_node.position.y)

	var spr := Sprite2D.new()
	spr.name = "Sprite2D"
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p_node.add_child(spr)

	props_container.add_child(p_node)
	poi_nodes_by_id[poi.id] = p_node
	_update_poi_node_visual(poi)
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
		_spawn_single_poi_node(poi)
	else:
		_update_poi_node_visual(poi)

func _on_poi_state_changed(poi: POIManager.POIData) -> void:
	if poi == null:
		return
	var p_node: CanvasItem = poi_nodes_by_id.get(poi.id)
	if p_node == null:
		_spawn_single_poi_node(poi)
	else:
		_update_poi_node_visual(poi)

func _on_poi_reward_claimed(poi: POIManager.POIData, _rewards: Dictionary) -> void:
	if poi == null:
		return
	var p_node: CanvasItem = poi_nodes_by_id.get(poi.id)
	if p_node == null:
		_spawn_single_poi_node(poi)
	else:
		_update_poi_node_visual(poi)

func refresh_poi_visibility() -> void:
	if poi_mgr == null:
		return
	for poi in poi_mgr.get_all_pois():
		var p_node: CanvasItem = poi_nodes_by_id.get(poi.id)
		if p_node == null:
			_spawn_single_poi_node(poi)
		else:
			_update_poi_node_visual(poi)

func _spawn_starter_citizens() -> void:
	deceased_citizen_ids.clear()
	var citizen_tex = load("res://assets/entities/citizen.png")
	var starter_roles: Array[String] = []
	for i in range(5): starter_roles.append("farmer")
	for i in range(4): starter_roles.append("woodcutter")
	for i in range(2): starter_roles.append("miner")
	for i in range(3): starter_roles.append("builder")
	for i in range(3): starter_roles.append("hauler")
	for i in range(2): starter_roles.append("researcher")
	for i in range(2): starter_roles.append("guard")
	for i in range(3): starter_roles.append("idle")
	
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
		cit.land_clearing_mgr = land_clearing_mgr
		cit.natural_resource_mgr = natural_resource_mgr
		cit.set_barracks_checker(func(b_id: String = ""): return BuildingSystem.is_barracks_active(world_data, b_id))
		cit.set_construction_checker(func(b_id: String = ""): return BuildingSystem.is_building_under_construction(world_data, b_id))
		cit.set_world_view(self)
		citizens_container.add_child(cit)
		
		citizens_by_id[cid] = cit
		citizen_list.append(cit)
		cit.citizen_died.connect(func(died_id: String): _on_citizen_died(died_id))
	sync_gameplay_terrain_preview_sources()
	var rm = _get_resource_mgr()
	if rm:
		rm.active_population = citizen_list.size()

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
		cit.land_clearing_mgr = land_clearing_mgr
		cit.natural_resource_mgr = natural_resource_mgr
		cit.set_barracks_checker(func(b_id: String = ""): return BuildingSystem.is_barracks_active(world_data, b_id))
		cit.set_construction_checker(func(b_id: String = ""): return BuildingSystem.is_building_under_construction(world_data, b_id))
		cit.set_world_view(self)
		citizens_container.add_child(cit)
		
		citizens_by_id[cid] = cit
		citizen_list.append(cit)
		cit.citizen_died.connect(func(died_id: String): _on_citizen_died(died_id))
	sync_gameplay_terrain_preview_sources()
		
	if rm:
		rm.active_population = citizen_list.size()
	if em:
		em.trigger_event("immigration_arrived", "Đoàn Người Di Cư Đã Đến!", "Có %d người di cư mới gia nhập vương quốc!" % immigrants.size(), true, {})
	var housing_cap: int = BuildingSystem.get_total_housing_capacity(world_data)
	if hud:
		hud.update_population_display(citizen_list.size(), housing_cap)
	sync_gameplay_terrain_preview_sources()

func is_house_active_and_owned(house_id: String) -> bool:
	if house_id == "" or world_data == null:
		return false
	var b_data: Dictionary = BuildingSystem.get_building_by_id(house_id, world_data)
	if b_data.is_empty():
		return false
	if str(b_data.get("type", "")) != "house":
		return false
	if str(b_data.get("state", "active")) != "active":
		return false
	if territory_mgr != null:
		if territory_mgr.get_owned_count() <= 0:
			return false
		var origin: Vector2i = b_data.get("cell", Vector2i(-1, -1))
		var b_size: Vector2i = b_data.get("size", Vector2i(2, 2))
		var is_owned: bool = territory_mgr.is_footprint_owned(origin, b_size) if territory_mgr.has_method("is_footprint_owned") else territory_mgr.is_cell_owned(origin)
		if not is_owned:
			return false
	return true

func register_house_occupant(house_id: String, cit_id: String) -> bool:
	if house_id == "" or cit_id == "":
		return false
	if not is_house_active_and_owned(house_id):
		return false
	var cit = citizens_by_id.get(cit_id)
	if cit == null or not is_instance_valid(cit):
		return false
	if str(cit.get("home_building_id")) != house_id:
		return false
	var existing_occ: Array = house_indoor_occupants.get(house_id, [])
	if cit_id in existing_occ:
		return true
	var b_data: Dictionary = BuildingSystem.get_building_by_id(house_id, world_data)
	var cap: int = EconomyConfig.get_house_capacity(int(b_data.get("level", 1)))
	if existing_occ.size() >= cap:
		return false
	# Ensure a citizen is never registered inside two houses simultaneously
	for existing_hid in house_indoor_occupants.keys().duplicate():
		if existing_hid != house_id:
			var arr: Array = house_indoor_occupants[existing_hid]
			if cit_id in arr:
				arr.erase(cit_id)
				if arr.is_empty():
					house_indoor_occupants.erase(existing_hid)
	if not house_indoor_occupants.has(house_id):
		house_indoor_occupants[house_id] = []
	var occ: Array = house_indoor_occupants[house_id]
	if not (cit_id in occ):
		occ.append(cit_id)
	return true

func unregister_house_occupant(cit_id: String, house_id: String = "") -> void:
	if cit_id == "":
		return
	if house_id != "":
		if house_indoor_occupants.has(house_id):
			var arr: Array = house_indoor_occupants[house_id]
			arr.erase(cit_id)
			if arr.is_empty():
				house_indoor_occupants.erase(house_id)
		return
	for hid in house_indoor_occupants.keys():
		var arr: Array = house_indoor_occupants[hid]
		arr.erase(cit_id)
		if arr.is_empty():
			house_indoor_occupants.erase(hid)

func get_house_indoor_occupants(house_id: String) -> Array:
	if house_id == "" or not house_indoor_occupants.has(house_id):
		return []
	return house_indoor_occupants[house_id].duplicate()

func _evict_house_occupants(house_id: String, reason_text: String = "Nhà ở đã bị phá hủy") -> void:
	if house_id == "":
		return
	for cit in citizen_list:
		if is_instance_valid(cit):
			var r_hid: String = str(cit.get("rest_house_id")) if cit.get("rest_house_id") != null else ""
			var h_bid: String = str(cit.get("home_building_id")) if cit.get("home_building_id") != null else ""
			if r_hid == house_id or h_bid == house_id:
				if cit.has_method("evict_from_house"):
					cit.call("evict_from_house", house_id, reason_text)
				elif h_bid == house_id:
					cit.set("home_building_id", "")
	house_indoor_occupants.erase(house_id)

func resolve_home_for_citizen(cit: Node) -> Dictionary:
	if cit == null or not is_instance_valid(cit) or world_data == null or nav == null:
		return {}
	if territory_mgr != null and territory_mgr.get_owned_count() <= 0:
		return {}

	var cit_cell: Vector2i = cit.get("current_cell")
	var cit_id: String = str(cit.get("citizen_id")) if cit.get("citizen_id") != null else ""
	var pref_id: String = str(cit.get("home_building_id")) if cit.get("home_building_id") != null else ""

	# Count current home assignments & indoor occupants per active house (excluding this citizen)
	var assigned_counts: Dictionary = {}
	for c_other in citizen_list:
		if is_instance_valid(c_other) and c_other != cit:
			var ohid: String = str(c_other.get("home_building_id")) if c_other.get("home_building_id") != null else ""
			if ohid != "":
				assigned_counts[ohid] = int(assigned_counts.get(ohid, 0)) + 1
	var indoor_counts: Dictionary = {}
	for hid_key in house_indoor_occupants.keys():
		var occ_arr: Array = house_indoor_occupants[hid_key]
		var cnt: int = 0
		for oid in occ_arr:
			if str(oid) != cit_id:
				cnt += 1
		if cnt > 0:
			indoor_counts[hid_key] = cnt

	# 1. Try existing preferred home if active, owned, and reachable
	if pref_id != "" and is_house_active_and_owned(pref_id):
		var pref_b: Dictionary = BuildingSystem.get_building_by_id(pref_id, world_data)
		var pref_cap: int = EconomyConfig.get_house_capacity(int(pref_b.get("level", 1)))
		var already_inside_pref: bool = (cit_id != "" and cit_id in house_indoor_occupants.get(pref_id, []))
		var pref_has_space: bool = already_inside_pref or (int(assigned_counts.get(pref_id, 0)) < pref_cap and int(indoor_counts.get(pref_id, 0)) < pref_cap)
		if pref_has_space:
			var pref_acc: Vector2i = cit.call("_find_house_perimeter_access", pref_id)
			if pref_acc != Vector2i(-1, -1):
				var pref_path: Array[Vector2i] = cit.call("_find_civilian_path", cit_cell, pref_acc)
				if not pref_path.is_empty() or cit_cell == pref_acc:
					return {"house_id": pref_id, "access_cell": pref_acc, "path": pref_path}

	var best_id: String = ""
	var best_acc := Vector2i(-1, -1)
	var best_path: Array[Vector2i] = []
	var best_score: float = 1e12

	for b in world_data.buildings:
		if str(b.get("type", "")) != "house" or str(b.get("state", "active")) != "active":
			continue
		var bid: String = str(b.get("id", ""))
		if bid == "" or not is_house_active_and_owned(bid):
			continue
		var cap: int = EconomyConfig.get_house_capacity(int(b.get("level", 1)))
		var cur_assigned: int = int(assigned_counts.get(bid, 0))
		var cur_indoor: int = int(indoor_counts.get(bid, 0))
		if cur_assigned >= cap or cur_indoor >= cap:
			continue
		var acc: Vector2i = cit.call("_find_house_perimeter_access", bid)
		if acc == Vector2i(-1, -1):
			continue
		var p: Array[Vector2i] = cit.call("_find_civilian_path", cit_cell, acc)
		if p.is_empty() and cit_cell != acc:
			continue
		var dist: int = IsoMath.grid_distance(cit_cell, acc)
		# Balance occupancy across houses while favoring proximity
		var score: float = float(cur_assigned) * 8.0 + float(dist)
		if score < best_score:
			best_score = score
			best_id = bid
			best_acc = acc
			best_path = p

	if best_id != "":
		cit.set("home_building_id", best_id)
		return {"house_id": best_id, "access_cell": best_acc, "path": best_path}
	return {}

func _on_citizen_died(died_id: String) -> void:
	if died_id == "" or deceased_citizen_ids.has(died_id):
		return # Idempotent: already processed death for this citizen ID

	var cit = citizens_by_id.get(died_id)
	if cit == null:
		return # Missing or already removed citizen ID; do not fabricate events

	deceased_citizen_ids[died_id] = true

	var rm = _get_resource_mgr()
	var em = get_node_or_null("/root/EventManager")
	var is_combat_death: bool = false
	var explicit_cause: String = String(cit.get("death_cause")) if cit.get("death_cause") != null else ""
	if explicit_cause == "combat":
		is_combat_death = true
	elif explicit_cause.is_empty():
		var status_reason: String = String(cit.get("status_reason"))
		if status_reason.contains("Tử trận"):
			is_combat_death = true

	# Conserve carried goods on citizen death (BUG-001): deposit into central storage before node is freed
	if is_instance_valid(cit):
		if cit.has_method("recover_cargo"):
			cit.call("recover_cargo", rm)
		else:
			var carry_amt: int = int(cit.get("carrying_amount")) if cit.get("carrying_amount") != null else 0
			var carry_res: String = String(cit.get("carrying_resource")) if cit.get("carrying_resource") != null else ""
			if carry_amt > 0 and not carry_res.is_empty() and rm != null and rm.has_method("add_resource"):
				var added: int = int(rm.call("add_resource", carry_res, carry_amt))
				var rem: int = carry_amt - added
				cit.set("carrying_amount", rem)
				if rem <= 0:
					cit.set("carrying_resource", "")
					cit.set("carrying_source_workplace_id", "")

		# Check if central storage was at capacity and unrecovered cargo needs durable retention in pending_death_cargo
		var unrec_amt: int = int(cit.get("carrying_amount")) if cit.get("carrying_amount") != null else 0
		var unrec_res: String = String(cit.get("carrying_resource")) if cit.get("carrying_resource") != null else ""
		if unrec_amt > 0 and not unrec_res.is_empty():
			add_pending_death_cargo(unrec_res, unrec_amt)
			cit.set("carrying_amount", 0)
			cit.set("carrying_resource", "")
			cit.set("carrying_source_workplace_id", "")
			push_warning("[WorldView] Central storage at capacity on citizen %s death: stored %d %s in pending_death_cargo" % [died_id, unrec_amt, unrec_res])

	unregister_house_occupant(died_id)
	citizen_list.erase(cit)
	citizens_by_id.erase(died_id)
	if is_instance_valid(cit):
		cit.queue_free()
	sync_gameplay_terrain_preview_sources()

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
	sync_gameplay_terrain_preview_sources()

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
		citizens_container = get_node_or_null("World/Entities/Citizens")
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
	refresh_caravan_route_risk()

func refresh_caravan_route_risk() -> void:
	if active_caravan == null or not bool(active_caravan.get("is_active")):
		return
	var origin_faction: String = String(active_caravan.get("origin_faction_id")) if active_caravan.get("origin_faction_id") != null else "rival_merchant"
	if origin_faction.is_empty():
		origin_faction = "rival_merchant"
	var origin_cell: Vector2i = TradeRouteCalculatorScript.get_caravan_origin_cell(origin_faction, field_siege_mgr, world_seed)
	var dock_info: Dictionary = BuildingSystem.find_caravan_docking_cell(world_data)
	var dest_cell: Vector2i = dock_info.get("cell", Vector2i(31, 34))
	if dest_cell == Vector2i(-1, -1):
		dest_cell = world_data.center_spawn if world_data != null else Vector2i(32, 32)
	var is_war: bool = bool(active_caravan.get("is_origin_at_war")) if active_caravan.get("is_origin_at_war") != null else false
	# MBL-LEG-01: Pass authoritative world_modifiers as 7th parameter to evaluate_route_risk_between
	var eval: Dictionary = TradeRouteCalculatorScript.evaluate_route_risk_between(
		origin_cell,
		dest_cell,
		fog_of_war,
		field_siege_mgr,
		world_data,
		is_war,
		world_modifiers
	)
	var net_risk: float = float(eval.get("net_risk", 0.0))
	active_caravan.call("set_route_risk", net_risk, eval)
	if hud != null and hud.has_method("refresh_caravan_trade_section"):
		hud.call("refresh_caravan_trade_section")

## Calculates the authoritative live kingdom stability at the current simulation moment.
func get_live_stability() -> float:
	if victory_mgr == null:
		return -1.0
	var rm = _get_resource_mgr()
	var food_stock: int = rm.get_available_stock("food") if rm != null and rm.has_method("get_available_stock") else 0
	var gold_stock: int = rm.get_available_stock("gold") if rm != null and rm.has_method("get_available_stock") else 0
	var housing_cap: int = BuildingSystem.get_total_housing_capacity(world_data) if world_data != null else 0
	var town_hall_alive: bool = BuildingSystem.is_town_hall_active(world_data) if world_data != null else false
	var current_pop: int = citizen_list.size()
	var avg_morale: float = 70.0
	if not citizen_list.is_empty():
		var total_m: float = 0.0
		for cit in citizen_list:
			total_m += float(cit.get("morale")) if cit != null and cit.get("morale") != null else 70.0
		avg_morale = total_m / float(citizen_list.size())
	return victory_mgr.calculate_stability(food_stock, gold_stock, current_pop, housing_cap, avg_morale, town_hall_alive)

## Returns the active world modifiers array.
func get_world_modifiers() -> Array:
	return world_modifiers

## Replaces the active world modifiers collection and synchronizes across all systems.
func set_world_modifiers(p_modifiers: Array) -> void:
	world_modifiers.clear()
	for m in p_modifiers:
		world_modifiers.append(str(m))
	if event_system != null and event_system.has_method("set_world_modifiers"):
		event_system.set_world_modifiers(world_modifiers)
	if crisis_mgr != null and crisis_mgr.has_method("set_world_modifiers"):
		crisis_mgr.set_world_modifiers(world_modifiers)
	if active_caravan != null and bool(active_caravan.get("is_active")):
		refresh_caravan_route_risk()

## Adds a world modifier and refreshes dependent systems.
func add_world_modifier(mod_id: String) -> void:
	var mid := str(mod_id).strip_edges()
	if not mid.is_empty() and not world_modifiers.has(mid):
		world_modifiers.append(mid)
		if event_system != null and event_system.has_method("set_world_modifiers"):
			event_system.set_world_modifiers(world_modifiers)
		if crisis_mgr != null and crisis_mgr.has_method("set_world_modifiers"):
			crisis_mgr.set_world_modifiers(world_modifiers)
		if active_caravan != null and bool(active_caravan.get("is_active")):
			refresh_caravan_route_risk()

## Removes a world modifier and refreshes dependent systems.
func remove_world_modifier(mod_id: String) -> void:
	var mid := str(mod_id).strip_edges()
	if world_modifiers.has(mid):
		world_modifiers.erase(mid)
		if event_system != null and event_system.has_method("set_world_modifiers"):
			event_system.set_world_modifiers(world_modifiers)
		if crisis_mgr != null and crisis_mgr.has_method("set_world_modifiers"):
			crisis_mgr.set_world_modifiers(world_modifiers)
		if active_caravan != null and bool(active_caravan.get("is_active")):
			refresh_caravan_route_risk()

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
	refresh_caravan_route_risk()

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

func _get_faction_display_name(fac_id: String) -> String:
	if fac_id == "player":
		return "Vương quốc của bạn"
	if faction_mgr != null and faction_mgr.has_method("get_faction"):
		var f = faction_mgr.get_faction(fac_id)
		if f != null and f.get("name") != null:
			return str(f.get("name"))
	return fac_id.capitalize()

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

func _validate_settlement_for_objective(stl: Object, expected_fid: String, expected_oid: String) -> bool:
	if stl == null or world_data == null:
		return false
	var sid: String = str(stl.get("settlement_id"))
	var o_fid: String = str(stl.get("origin_faction_id"))
	var linked_oid: String = str(stl.get("linked_objective_id"))
	if sid.is_empty() or o_fid != expected_fid:
		push_error("[WorldView] Invalid settlement identity/faction (sid='%s', fid='%s', expected='%s')." % [sid, o_fid, expected_fid])
		return false
	if linked_oid != expected_oid:
		push_error("[WorldView] Mismatched canonical linked_objective_id '%s' on settlement '%s' (expected '%s')." % [linked_oid, sid, expected_oid])
		return false

	# Validate HQ descriptor
	var has_valid_hq := false
	var b_list = stl.get("buildings")
	if b_list is Array:
		for b in b_list:
			if b is Dictionary and str(b.get("role", "")) == "hq":
				var b_type: String = str(b.get("type", ""))
				if not b_type.is_empty() and (building_textures.has(b_type) or EconomyConfig.BLUEPRINTS.has(b_type)):
					has_valid_hq = true
					break
	if not has_valid_hq:
		push_error("[WorldView] Settlement '%s' lacks a valid HQ descriptor; omitting linked objective '%s'." % [sid, expected_oid])
		return false

	# Validate walkable, in-bounds anchor_cell
	var anchor = stl.get("anchor_cell")
	if not (anchor is Vector2i) or not world_data.is_in_bounds(anchor):
		push_error("[WorldView] Settlement '%s' has out-of-bounds anchor_cell; omitting linked objective '%s'." % [sid, expected_oid])
		return false
	var t_type: int = int(world_data.terrain[anchor.x][anchor.y])
	if t_type == WorldGenerator.TerrainType.WATER or t_type == WorldGenerator.TerrainType.MOUNTAINS:
		push_error("[WorldView] Settlement '%s' anchor_cell %s is WATER/MOUNTAINS; omitting linked objective '%s'." % [sid, str(anchor), expected_oid])
		return false
	if world_data.occupancy[anchor.x][anchor.y]:
		push_error("[WorldView] Settlement '%s' anchor_cell %s is occupied; omitting linked objective '%s'." % [sid, str(anchor), expected_oid])
		return false

	return true

func _setup_default_siege_objectives() -> void:
	if field_siege_mgr == null:
		return

	var outpost_configs := [
		{"fid": "rival_military", "id": "outpost_rival_military", "anchor": Vector2i(14, 14), "hp": 300.0, "gar": 4},
		{"fid": "rival_merchant", "id": "outpost_rival_merchant", "anchor": Vector2i(50, 16), "hp": 250.0, "gar": 3},
		{"fid": "neutral_tribe", "id": "outpost_neutral_tribe", "anchor": Vector2i(16, 48), "hp": 200.0, "gar": 2}
	]

	var gen_ver: int = int(world_data.generator_version) if world_data != null else WorldGenerator.LEGACY_GENERATOR_VERSION
	if gen_ver < WorldGenerator.RIVAL_SETTLEMENTS_GENERATOR_VERSION:
		for cfg in outpost_configs:
			var fid: String = cfg["fid"]
			var oid: String = cfg["id"]
			var cell: Vector2i = _find_valid_outpost_cell(cfg["anchor"], 15)
			field_siege_mgr.register_objective(oid, cell, fid, cfg["hp"], cfg["gar"])
		return

	# V8+: Build validated 1:1 settlement lookup without silent repair
	var settlements_by_faction: Dictionary = {}
	var seen_sids: Dictionary = {}
	var seen_oids: Dictionary = {}
	var invalid_factions: Dictionary = {}
	if world_data != null and world_data.get("settlements") != null:
		for stl in world_data.settlements:
			if stl == null:
				continue
			var sid: String = str(stl.get("settlement_id"))
			var o_fid: String = str(stl.get("origin_faction_id"))
			var l_oid: String = str(stl.get("linked_objective_id"))
			if seen_sids.has(sid):
				push_error("[WorldView] Duplicate settlement_id '%s' detected; skipping duplicate." % sid)
				invalid_factions[o_fid] = true
				continue
			if not l_oid.is_empty() and seen_oids.has(l_oid):
				push_error("[WorldView] Duplicate canonical linked_objective_id '%s' on settlement '%s'; skipping." % [l_oid, sid])
				invalid_factions[o_fid] = true
				continue
			if settlements_by_faction.has(o_fid):
				push_error("[WorldView] Multiple settlements for faction '%s' detected; skipping duplicate '%s'." % [o_fid, sid])
				invalid_factions[o_fid] = true
				continue
			seen_sids[sid] = true
			if not l_oid.is_empty():
				seen_oids[l_oid] = true
			settlements_by_faction[o_fid] = stl

	var skip_reasons: Dictionary = world_data.settlement_skip_reasons if (world_data != null and world_data.get("settlement_skip_reasons") is Dictionary) else {}
	for cfg in outpost_configs:
		var fid: String = cfg["fid"]
		var oid: String = cfg["id"]
		if invalid_factions.has(fid):
			continue
		var stl = settlements_by_faction.get(fid, null)
		if stl == null:
			if str(skip_reasons.get(fid, "")) == "map_constraints":
				continue # Intentional skip on constrained map; no phantom objective
			push_error("[WorldView] Unexpected missing settlement for faction '%s' in V%d; omitting objective '%s'." % [fid, gen_ver, oid])
			continue
		if not _validate_settlement_for_objective(stl, fid, oid):
			continue
		field_siege_mgr.register_objective(oid, stl.anchor_cell, fid, cfg["hp"], cfg["gar"], str(stl.settlement_id))

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

func _setup_clear_land_overlay() -> void:
	if _clear_land_overlay != null:
		return
	_clear_land_overlay = Node2D.new()
	_clear_land_overlay.name = "ClearLandOverlay"
	_clear_land_overlay.z_index = 45
	_clear_land_overlay.draw.connect(_on_clear_land_overlay_draw)
	var world_node := get_node_or_null("World")
	if world_node != null:
		world_node.add_child(_clear_land_overlay)
	else:
		add_child(_clear_land_overlay)

func _setup_territory_overlay() -> void:
	if _territory_overlay != null:
		return
	_territory_overlay = Node2D.new()
	_territory_overlay.name = "TerritoryOverlay"
	_territory_overlay.z_index = 15
	_territory_overlay.visible = false
	_territory_overlay.draw.connect(_on_territory_overlay_draw)
	var world_node := get_node_or_null("World")
	if world_node != null:
		world_node.add_child(_territory_overlay)
	else:
		add_child(_territory_overlay)

func is_territory_overlay_visible() -> bool:
	return _territory_overlay != null and is_instance_valid(_territory_overlay) and _territory_overlay.visible

func _refresh_territory_overlay() -> void:
	if _territory_overlay == null or not is_instance_valid(_territory_overlay):
		return
	var should_show := placing_building_type != ""
	_territory_overlay.visible = should_show
	if should_show:
		_territory_overlay.queue_redraw()

func _on_territory_overlay_draw() -> void:
	if _territory_overlay == null or territory_mgr == null or world_data == null:
		return
	if placing_building_type == "":
		return
	var fill_color := Color(0.2, 0.72, 0.95, 0.14)
	var border_color := Color(0.35, 0.85, 1.0, 0.85)
	var hw: float = IsoMath.TILE_WIDTH * 0.5
	var hh: float = IsoMath.TILE_HEIGHT * 0.5

	# Subtle translucent fill per owned cell (no interior per-cell grid outlines)
	for cell in territory_mgr.get_owned_cells():
		var c: Vector2 = IsoMath.map_to_local(cell)
		var pts := PackedVector2Array([
			c + Vector2(0.0, -hh),
			c + Vector2(hw, 0.0),
			c + Vector2(0.0, hh),
			c + Vector2(-hw, 0.0),
		])
		_territory_overlay.draw_colored_polygon(pts, fill_color)

	# Exposed outer perimeter contour only (handles convex, concave, holes, and islands)
	for bcell in territory_mgr.get_border_cells():
		var c: Vector2 = IsoMath.map_to_local(bcell)
		var p0 := c + Vector2(0.0, -hh)
		var p1 := c + Vector2(hw, 0.0)
		var p2 := c + Vector2(0.0, hh)
		var p3 := c + Vector2(-hw, 0.0)
		if not territory_mgr.is_cell_owned(bcell + Vector2i(0, -1)):
			_territory_overlay.draw_line(p0, p1, border_color, 2.5, true)
		if not territory_mgr.is_cell_owned(bcell + Vector2i(1, 0)):
			_territory_overlay.draw_line(p1, p2, border_color, 2.5, true)
		if not territory_mgr.is_cell_owned(bcell + Vector2i(0, 1)):
			_territory_overlay.draw_line(p2, p3, border_color, 2.5, true)
		if not territory_mgr.is_cell_owned(bcell + Vector2i(-1, 0)):
			_territory_overlay.draw_line(p3, p0, border_color, 2.5, true)

func set_clear_land_mode(enabled: bool) -> void:
	if enabled:
		if placing_building_type != "":
			_cancel_placement()
		if hud != null and hud.has_method("is_army_move_targeting") and hud.call("is_army_move_targeting"):
			hud.call("cancel_army_move_targeting")
	is_clear_land_mode = enabled
	if _clear_land_overlay != null and is_instance_valid(_clear_land_overlay):
		_clear_land_overlay.queue_redraw()
	if hud != null and hud.has_method("set_clear_land_mode_active"):
		hud.call("set_clear_land_mode_active", enabled)
	_notify_hud_clear_land_summary()

func toggle_clear_land_mode() -> void:
	set_clear_land_mode(not is_clear_land_mode)

func queue_clear_land_cell(cell: Vector2i) -> Dictionary:
	if land_clearing_mgr == null:
		return {"success": false, "reason": "Hệ thống dọn mặt bằng chưa sẵn sàng"}
	var res: Dictionary = land_clearing_mgr.queue_clearing_order(world_data, cell, world_seed, world_generator_version, poi_mgr)
	if res.get("success", false):
		land_clearing_mgr.dispatch_orders(world_data, citizen_list, nav)
	if _clear_land_overlay != null and is_instance_valid(_clear_land_overlay):
		_clear_land_overlay.queue_redraw()
	_notify_hud_clear_land_summary()
	return res

func cancel_clear_land_cell(cell: Vector2i) -> Dictionary:
	if land_clearing_mgr == null:
		return {"success": false, "reason": "Hệ thống dọn mặt bằng chưa sẵn sàng"}
	var res: Dictionary = land_clearing_mgr.cancel_clearing_at_cell(cell, citizen_list)
	if _clear_land_overlay != null and is_instance_valid(_clear_land_overlay):
		_clear_land_overlay.queue_redraw()
	_notify_hud_clear_land_summary()
	return res

func queue_clear_land_in_screen_rect(rect: Rect2) -> Dictionary:
	if land_clearing_mgr == null or world_data == null or camera == null:
		return {"queued": 0, "skipped": 0}
	var queued_count: int = 0
	var skipped_count: int = 0
	var canvas_xform: Transform2D = camera.get_canvas_transform()
	for p in world_data.props:
		var cell: Vector2i = p.get("cell", Vector2i(-1, -1))
		var local_pos: Vector2 = IsoMath.map_to_local(cell)
		var global_pos: Vector2 = terrain_layer.to_global(local_pos) if terrain_layer != null else to_global(local_pos)
		var screen_pos: Vector2 = canvas_xform * global_pos
		if rect.has_point(screen_pos):
			var res: Dictionary = land_clearing_mgr.queue_clearing_order(world_data, cell, world_seed, world_generator_version, poi_mgr)
			if res.get("success", false):
				queued_count += 1
			else:
				skipped_count += 1
	if queued_count > 0:
		land_clearing_mgr.dispatch_orders(world_data, citizen_list, nav)
	if _clear_land_overlay != null and is_instance_valid(_clear_land_overlay):
		_clear_land_overlay.queue_redraw()
	_notify_hud_clear_land_summary()
	return {"queued": queued_count, "skipped": skipped_count}

func _notify_hud_clear_land_summary() -> void:
	if hud != null and hud.has_method("update_clear_land_summary") and land_clearing_mgr != null:
		hud.call("update_clear_land_summary", land_clearing_mgr.get_active_orders().size(), is_clear_land_mode)

func _on_land_clearing_prop_cleared(_prop_id: String, _prop_type: String, cell: Vector2i, _reward_res: String, _reward_amt: int) -> void:
	remove_prop_visual_at_cell(cell)
	if _clear_land_overlay != null and is_instance_valid(_clear_land_overlay):
		_clear_land_overlay.queue_redraw()
	_notify_hud_clear_land_summary()

func _on_land_clearing_orders_changed() -> void:
	if _clear_land_overlay != null and is_instance_valid(_clear_land_overlay):
		_clear_land_overlay.queue_redraw()
	_notify_hud_clear_land_summary()

func _draw_iso_diamond(canvas: CanvasItem, cell: Vector2i, fill_color: Color, border_color: Color, border_width: float = 2.0) -> void:
	var c: Vector2 = IsoMath.map_to_local(cell)
	var hw: float = IsoMath.TILE_WIDTH * 0.5
	var hh: float = IsoMath.TILE_HEIGHT * 0.5
	var pts := PackedVector2Array([
		c + Vector2(0.0, -hh),
		c + Vector2(hw, 0.0),
		c + Vector2(0.0, hh),
		c + Vector2(-hw, 0.0),
	])
	canvas.draw_colored_polygon(pts, fill_color)
	var loop_pts := PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]])
	canvas.draw_polyline(loop_pts, border_color, border_width)

func _on_clear_land_overlay_draw() -> void:
	if _clear_land_overlay == null or land_clearing_mgr == null:
		return
	var active_orders: Array = land_clearing_mgr.get_active_orders()
	for order in active_orders:
		var cell: Vector2i = order.get("cell", Vector2i(-1, -1))
		if cell.x < 0:
			continue
		var st: int = int(order.get("state", LandClearingManagerScript.OrderState.QUEUED))
		var fill := Color(1.0, 0.65, 0.15, 0.28)
		var border := Color(1.0, 0.78, 0.25, 0.95)
		match st:
			LandClearingManagerScript.OrderState.WORKING:
				fill = Color(0.25, 0.9, 0.35, 0.32)
				border = Color(0.45, 1.0, 0.5, 0.95)
			LandClearingManagerScript.OrderState.PAUSED_FOR_REST:
				fill = Color(0.4, 0.7, 1.0, 0.28)
				border = Color(0.55, 0.85, 1.0, 0.95)
			LandClearingManagerScript.OrderState.WAITING_FOR_STORAGE:
				fill = Color(1.0, 0.85, 0.1, 0.34)
				border = Color(1.0, 0.95, 0.3, 1.0)
			LandClearingManagerScript.OrderState.BLOCKED:
				fill = Color(0.95, 0.22, 0.22, 0.32)
				border = Color(1.0, 0.35, 0.35, 0.95)
		_draw_iso_diamond(_clear_land_overlay, cell, fill, border, 2.0)

		var req: float = float(order.get("work_hours_required", 1.0))
		var prog: float = float(order.get("work_hours_done", 0.0))
		if req > 0.0 and (prog > 0.0 or st == LandClearingManagerScript.OrderState.WORKING):
			var ratio: float = clampf(prog / req, 0.0, 1.0)
			var c: Vector2 = IsoMath.map_to_local(cell) + Vector2(-18.0, -34.0)
			var bar_w: float = 36.0
			var bar_h: float = 5.0
			_clear_land_overlay.draw_rect(Rect2(c, Vector2(bar_w, bar_h)), Color(0.08, 0.08, 0.1, 0.85), true)
			_clear_land_overlay.draw_rect(Rect2(c + Vector2(1.0, 1.0), Vector2((bar_w - 2.0) * ratio, bar_h - 2.0)), border, true)

	if is_clear_land_mode and terrain_layer != null and world_data != null:
		var hover_cell: Vector2i = IsoMath.local_to_map(terrain_layer.get_local_mouse_position())
		if IsoMath.is_in_bounds(hover_cell):
			var existing := land_clearing_mgr.get_order_at_cell(hover_cell)
			if existing.is_empty():
				var prop := land_clearing_mgr.find_prop_at_cell(world_data, hover_cell)
				if not prop.is_empty():
					_draw_iso_diamond(_clear_land_overlay, hover_cell, Color(1.0, 0.8, 0.2, 0.22), Color(1.0, 0.9, 0.4, 0.9), 1.5)

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
	if best_unit != null and best_dist > 0:
		var b_at_cell: Dictionary = _get_building_at_cell(cell)
		if not b_at_cell.is_empty():
			return null
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

func _is_cell_in_siege_objective(obj: Node2D, cell: Vector2i) -> bool:
	if obj == null or not is_instance_valid(obj):
		return false
	var origin: Vector2i = obj.current_cell
	var size: Vector2i = obj.get("size") if (obj.get("size") is Vector2i) else Vector2i(2, 2)
	return cell.x >= origin.x and cell.x < origin.x + size.x and cell.y >= origin.y and cell.y < origin.y + size.y

func _find_siege_objective_at_cell(cell: Vector2i) -> Node2D:
	if field_siege_mgr == null:
		return null
	for o in field_siege_mgr.call("get_all_objectives"):
		if o == null or not is_instance_valid(o) or not o.is_alive:
			continue
		if _is_cell_in_siege_objective(o, cell):
			return o
	return null

func _process(delta: float) -> void:
	_update_tile_hover()
	sync_day_night_visuals()
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
		if speed_mult > 0.0:
			_refresh_dynamic_actor_visibility()

	if wildlife_mgr != null:
		var p_units_wl: Array = tactical_military_mgr.call("get_all_units") if (tactical_military_mgr != null and tactical_military_mgr.has_method("get_all_units")) else []
		wildlife_mgr.advance_simulation(delta, speed_mult, world_data, nav, citizen_list, p_units_wl)
		if speed_mult > 0.0:
			wildlife_mgr.refresh_visibility(fog_of_war, debug_fog_disabled)

	if monster_mgr != null:
		monster_mgr.update_simulation(delta, speed_mult, world_data, nav, tactical_military_mgr, territory_mgr, fog_of_war, debug_fog_disabled)
		if poi_mgr != null and speed_mult > 0.0:
			poi_mgr.refresh_guard_states(monster_mgr, nav)
	_sync_hunter_preview_sources_if_moved()

	if settlement_simulation_manager != null and is_instance_valid(settlement_simulation_manager) and speed_mult > 0.0:
		settlement_simulation_manager.step_ambient_locomotion(delta * speed_mult)

	if rival_presentation_controller != null and is_instance_valid(rival_presentation_controller):
		rival_presentation_controller.debug_fog_disabled = debug_fog_disabled
		rival_presentation_controller.fog_of_war = fog_of_war
		rival_presentation_controller.update_presentation(delta, speed_mult)

	if cookhouse_mgr != null and speed_mult > 0.0:
		var rm_cook := get_node_or_null("/root/ResourceManager")
		var dh_cook: float = (delta * speed_mult) / 7.5
		cookhouse_mgr.advance_production(dh_cook, rm_cook)

	if camera != null and is_instance_valid(camera) and camera.position.distance_squared_to(_last_cam_pos_for_minimap) > 4.0:
		_last_cam_pos_for_minimap = camera.position
		if hud != null and hud.has_method("refresh_minimap_markers"):
			hud.refresh_minimap_markers()

	if field_siege_mgr != null and field_siege_mgr.get("active_sieges") != null:
		var s_ids = field_siege_mgr.active_sieges.keys()
		for s_id in s_ids:
			field_siege_mgr.evaluate_siege_status(s_id)

	if land_clearing_mgr != null:
		_clear_land_dispatch_timer += delta
		if _clear_land_dispatch_timer >= 0.35:
			_clear_land_dispatch_timer = 0.0
			if speed_mult > 0.0:
				land_clearing_mgr.dispatch_orders(world_data, citizen_list, nav)
			if _clear_land_overlay != null and is_instance_valid(_clear_land_overlay):
				if is_clear_land_mode or not land_clearing_mgr.get_active_orders().is_empty():
					_clear_land_overlay.queue_redraw()

func _update_tile_hover() -> void:
	var screen_m := get_viewport().get_mouse_position() if is_inside_tree() else Vector2.ZERO
	var use_input_screen := (absf(screen_m.x) > 100000.0 or absf(screen_m.y) > 100000.0) and _last_input_mouse_screen != Vector2.INF
	if use_input_screen:
		screen_m = _last_input_mouse_screen
	var mouse_local: Vector2
	if use_input_screen and camera != null and is_inside_tree():
		mouse_local = terrain_layer.to_local(camera.get_canvas_transform().affine_inverse() * screen_m)
	else:
		mouse_local = terrain_layer.get_local_mouse_position()
	var cell := IsoMath.local_to_map(mouse_local)
	
	if IsoMath.is_in_bounds(cell):
		cursor_highlight.visible = true
		cursor_highlight.position = IsoMath.map_to_local(cell)
		
		if hud:
			if fog_of_war != null and fog_of_war.is_unexplored(cell) and not debug_fog_disabled:
				hud.set_tile_info(cell, "Chưa khám phá", "")
				if hud.has_method("hide_entity_hover_tooltip"):
					hud.call("hide_entity_hover_tooltip")
				if placing_building_type != "" and ghost_building_node != null:
					ghost_building_node.visible = false
				return
			var t_name := _get_terrain_name(world_data.terrain[cell.x][cell.y])
			var b_name := _get_building_display_name(buildings_by_cell.get(cell, ""))
			if b_name.is_empty():
				b_name = get_rival_hover_label(cell)
			var bld := _get_building_at_cell(cell)
			if not bld.is_empty() and bld.get("state", "") == "under_construction":
				var prog: float = float(bld.get("construction_progress", 0.0))
				var total: float = float(bld.get("construction_hours", 12.0))
				var pct: int = int((prog / total) * 100.0) if total > 0.0 else 0
				b_name += " [Đang xây: %d%%]" % pct
			if hud.has_method("is_army_move_targeting") and hud.call("is_army_move_targeting"):
				b_name += " [Nhấp để điều động]"
			elif is_clear_land_mode:
				b_name += " [Dọn Mặt Bằng]"
			if land_clearing_mgr != null:
				var cl_order := land_clearing_mgr.get_order_at_cell(cell)
				if not cl_order.is_empty():
					var req_h: float = float(cl_order.get("work_hours_required", 1.0))
					var prog_h: float = float(cl_order.get("work_hours_done", 0.0))
					var cl_pct: int = int((prog_h / req_h) * 100.0) if req_h > 0.0 else 0
					b_name += " [Dọn: %s %d%%]" % [LandClearingManagerScript.state_to_string(int(cl_order.get("state", 0))), cl_pct]
			var hover_entity_title := ""
			if hud.has_method("update_world_hover"):
				var hover_blocked := (placing_building_type != "" or is_clear_land_mode)
				hover_entity_title = str(hud.call("update_world_hover", cell, screen_m, hover_blocked))
			hud.set_tile_info(cell, t_name, b_name, hover_entity_title if b_name.is_empty() else "")
			if is_clear_land_mode and _clear_land_overlay != null and is_instance_valid(_clear_land_overlay):
				_clear_land_overlay.queue_redraw()
			
		# Handle ghost building placement preview
		if placing_building_type == "bridge":
			if ghost_building_node:
				ghost_building_node.visible = false
			_update_bridge_preview(cell)
		elif placing_building_type != "":
			if _bridge_preview_overlay:
				_bridge_preview_overlay.visible = false
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
		if hud != null and hud.has_method("hide_entity_hover_tooltip"):
			hud.call("hide_entity_hover_tooltip")
		if _bridge_preview_overlay and placing_building_type != "bridge":
			_bridge_preview_overlay.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event as InputEventKey
		if k.keycode == KEY_X:
			var focus := get_viewport().gui_get_focus_owner()
			if not (focus is LineEdit or focus is TextEdit):
				toggle_clear_land_mode()
				get_viewport().set_input_as_handled()
				return
		if k.keycode == KEY_ESCAPE:
			if is_clear_land_mode:
				set_clear_land_mode(false)
				get_viewport().set_input_as_handled()
			elif placing_building_type != "":
				_cancel_placement()
			elif tactical_military_mgr != null and tactical_military_mgr.call("get_selected_count") > 0:
				tactical_military_mgr.call("clear_selection")
				get_viewport().set_input_as_handled()
			elif selected_building_id != "":
				clear_building_selection()
				get_viewport().set_input_as_handled()
		elif k.keycode in [KEY_1, KEY_2, KEY_3]:
			var grp: int = k.keycode - KEY_1 + 1
			if placing_building_type == "bridge" and not k.ctrl_pressed and not k.shift_pressed:
				set_bridge_width(grp)
				get_viewport().set_input_as_handled()
			elif k.ctrl_pressed:
				if tactical_military_mgr != null:
					tactical_military_mgr.call("assign_control_group", grp)
					get_viewport().set_input_as_handled()
			elif k.shift_pressed:
				if tactical_military_mgr != null:
					tactical_military_mgr.call("recall_control_group", grp)
					get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion:
		var mm_track: InputEventMouseMotion = event as InputEventMouseMotion
		_last_input_mouse_screen = mm_track.position
		if _is_left_mouse_down:
			var mm: InputEventMouseMotion = event as InputEventMouseMotion
			if not _is_drag_box_active and (mm.position - _drag_start_screen).length() > 6.0:
				_is_drag_box_active = true
			if _is_drag_box_active:
				_drag_current_screen = mm.position
				_update_selection_box_display()

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		var mouse_local: Vector2
		if event.has_meta("target_cell"):
			mouse_local = IsoMath.map_to_local(event.get_meta("target_cell"))
		elif mb.position != Vector2.ZERO and camera != null and is_inside_tree():
			var canvas_xform: Transform2D = camera.get_canvas_transform()
			var global_pos: Vector2 = canvas_xform.affine_inverse() * mb.position
			mouse_local = terrain_layer.to_local(global_pos)
		else:
			mouse_local = terrain_layer.get_local_mouse_position()
		var cell := IsoMath.local_to_map(mouse_local)
		
		if is_clear_land_mode:
			if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
				set_clear_land_mode(false)
				_is_left_mouse_down = false
				_is_drag_box_active = false
				_clear_selection_box_display()
				get_viewport().set_input_as_handled()
				return
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_is_left_mouse_down = true
					_drag_start_screen = mb.position
					_drag_current_screen = mb.position
					_is_drag_box_active = false
				else:
					_is_left_mouse_down = false
					if _is_drag_box_active:
						_is_drag_box_active = false
						_clear_selection_box_display()
						var rect := Rect2(_drag_start_screen, _drag_current_screen - _drag_start_screen).abs()
						queue_clear_land_in_screen_rect(rect)
					else:
						_clear_selection_box_display()
						if land_clearing_mgr != null and not land_clearing_mgr.get_order_at_cell(cell).is_empty():
							cancel_clear_land_cell(cell)
						else:
							var res := queue_clear_land_cell(cell)
							if not res.get("success", false) and hud != null:
								hud.show_event_banner("Không Thể Dọn", str(res.get("reason", "Vị trí không hợp lệ")), false, 2.5)
				get_viewport().set_input_as_handled()
				return
		elif placing_building_type == "bridge":
			if mb.pressed:
				if mb.button_index == MOUSE_BUTTON_LEFT:
					_handle_bridge_click(cell)
				elif mb.button_index == MOUSE_BUTTON_RIGHT:
					if bridge_start_bank != Vector2i(-1, -1):
						bridge_start_bank = Vector2i(-1, -1)
						_update_bridge_preview(cell)
					else:
						_cancel_placement()
		elif placing_building_type != "":
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
							if hud != null and hud.has_method("close_entity_inspector") and int(tactical_military_mgr.call("get_selected_count")) != 1:
								hud.call("close_entity_inspector")
					else:
						# Simple left click
						_clear_selection_box_display()
						var clicked_unit: Node2D = null
						if tactical_military_mgr != null:
							clicked_unit = _find_tactical_unit_at_cell(cell)

						if clicked_unit != null and tactical_military_mgr != null:
							clear_building_selection()
							if hud != null and hud.has_method("close_citizen_inspector"):
								hud.close_citizen_inspector()
							tactical_military_mgr.call("select_unit", clicked_unit.unit_id, mb.shift_pressed)
							if hud != null and hud.has_method("show_entity_inspector") and int(tactical_military_mgr.call("get_selected_count")) == 1:
								var sel_ids: Array = tactical_military_mgr.call("get_selected_unit_ids")
								if not sel_ids.is_empty():
									hud.call("show_entity_inspector", "military_unit", "player:%s" % str(sel_ids[0]))
							elif hud != null and hud.has_method("close_entity_inspector"):
								hud.call("close_entity_inspector")
						else:
							if not mb.shift_pressed and tactical_military_mgr != null:
								tactical_military_mgr.call("clear_selection")
							var click_pos_opt: Vector2 = Vector2.INF if event.has_meta("target_cell") else mouse_local
							_handle_left_click(cell, click_pos_opt)
			elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
				if tactical_military_mgr != null and tactical_military_mgr.call("get_selected_count") > 0:
					# AUD-3B-01: Hostile target resolution (siege objectives and enemy units)
					# requires the target cell to be currently VISIBLE in Fog of War.
					# Fail closed: if fog_of_war is null or cell is not visible (unexplored or explored-only),
					# do not perform lookups or dispatch attacks against hidden entities; fall through to move order.
					var is_cell_visible: bool = (fog_of_war != null and fog_of_war.is_visible(cell))
					var obj_target: Node2D = null
					var enemy_target: Node2D = null
					if is_cell_visible:
						obj_target = _find_siege_objective_at_cell(cell)
						enemy_target = _find_enemy_unit_at_cell(cell)

					# If right-clicking directly on an outpost objective cell, prioritize the objective!
					var target_is_obj: bool = false
					if obj_target != null and _is_cell_in_siege_objective(obj_target, cell):
						target_is_obj = true
					elif enemy_target != null:
						target_is_obj = false
					elif obj_target != null:
						target_is_obj = true

					if target_is_obj and obj_target != null:
						if str(obj_target.owning_faction_id) == "player":
							_handle_tactical_right_click_friendly_outpost(
								str(obj_target.objective_id),
								str(obj_target.objective_name),
								obj_target.current_cell,
								bool(obj_target.is_alive)
							)
						else:
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
											if not atk_res.get("success", false) and hud != null:
												hud.show_event_banner("Lệnh Tấn Công Thất Bại", atk_res.get("reason", "Không thể tấn công mục tiêu công thành"), false, 3.0)
											elif hud != null:
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
						var monster_target: Node2D = null
						if monster_mgr != null:
							monster_target = monster_mgr.get_monster_actor_at(cell)
							if monster_target == null:
								monster_target = monster_mgr.get_nest_actor_at(cell)
						if monster_target != null and is_instance_valid(monster_target) and bool(monster_target.get("is_alive")):
							var m_res: Dictionary = tactical_military_mgr.call("issue_attack_order", monster_target, nav)
							if not m_res.get("success", false) and hud != null:
								hud.show_event_banner("Lệnh Tấn Công Thất Bại", m_res.get("reason", "Không thể tấn công"), false, 3.0)
						else:
							var b_data := _get_building_at_cell(cell)
							if not b_data.is_empty() and BuildingSystem.is_outpost_building(b_data):
								var b_id := str(b_data.get("id", ""))
								var b_type := str(b_data.get("type", ""))
								var b_name := _get_building_display_name(b_type)
								var b_cell: Vector2i = b_data.get("cell", cell)
								var b_active := (str(b_data.get("state", "")) == "active")
								_handle_tactical_right_click_friendly_outpost(b_id, b_name, b_cell, b_active)
							else:
								var res: Dictionary = tactical_military_mgr.call("issue_move_order", cell, nav)
								if not res.get("success", false) and hud != null:
									hud.show_event_banner("Lệnh Thất Bại", res.get("reason", "Vị trí không thể đi tới"), false, 3.0)
				elif hud != null and hud.has_method("get_inspected_citizen") and hud.get_inspected_citizen() != null:
					_handle_citizen_right_click(cell, hud.get_inspected_citizen())

func _handle_citizen_right_click(cell: Vector2i, citizen: Node) -> void:
	if citizen == null or not is_instance_valid(citizen) or not citizen.call("is_alive"):
		return

	if not IsoMath.is_in_bounds(cell):
		if hud != null:
			hud.show_event_banner("Lệnh Thất Bại", "Tọa độ nằm ngoài bản đồ", false, 3.0)
		var am = get_node_or_null("/root/AudioManager") if is_inside_tree() else null
		if am and am.has_method("play_error"):
			am.play_error()
		return

	var cmd_type: String = ""
	var target_id: String = ""

	# Check 1: Building at target cell
	var b_data := _get_building_at_cell(cell)
	if not b_data.is_empty():
		var b_id: String = b_data.get("id", "")
		var is_uc: bool = BuildingSystem.is_building_under_construction(world_data, b_id)
		var is_upg: bool = bool(b_data.get("is_upgrading", false))
		if is_uc or is_upg:
			cmd_type = "build"
			target_id = b_id
		else:
			# Check if building has buffer cargo to haul
			if workplace_mgr != null and workplace_mgr.has_method("get_workplace"):
				var wp = workplace_mgr.get_workplace(b_id)
				if wp != null and wp.buffer_amount > 0:
					cmd_type = "haul"
					target_id = b_id

	# Check 2: POI at target cell (if no building action)
	if cmd_type == "" and poi_mgr != null:
		for poi in poi_mgr.get_all_pois():
			if poi.cell == cell:
				if poi.state != POIManager.POIState.CLAIMED:
					cmd_type = "explore"
					target_id = poi.id
				else:
					if hud != null:
						hud.show_event_banner("Lệnh Thất Bại", "Điểm khám phá này đã được khai phá từ trước", false, 3.0)
					var am = get_node_or_null("/root/AudioManager") if is_inside_tree() else null
					if am and am.has_method("play_error"):
						am.play_error()
					return
				break

	# Check 3: Terrain / Props at target cell (if no building/POI action)
	if cmd_type == "":
		var is_tree: bool = false
		var is_rock: bool = false
		if world_data != null and world_data.get("props") != null:
			for p in world_data.props:
				if p.get("cell") == cell:
					if p.get("type") in ["tree", "forest"]:
						is_tree = true
					elif p.get("type") in ["rock", "mountain", "stone"]:
						is_rock = true
					break

		if is_tree:
			cmd_type = "chop"
		elif is_rock:
			cmd_type = "mine"
		else:
			var t_type: int = -1
			if world_data != null and world_data.get("terrain") != null:
				t_type = world_data.terrain[cell.x][cell.y]
			if t_type == WorldGenerator.TerrainType.WATER:
				if hud != null:
					hud.show_event_banner("Lệnh Thất Bại", "Vị trí là mặt nước sâu, không thể tiếp cận", false, 3.0)
				var am = get_node_or_null("/root/AudioManager") if is_inside_tree() else null
				if am and am.has_method("play_error"):
					am.play_error()
				return
			else:
				if not b_data.is_empty():
					if hud != null:
						hud.show_event_banner("Lệnh Thất Bại", "Công trình đã hoàn thành và không có hàng đệm cần vận chuyển", false, 3.0)
					var am = get_node_or_null("/root/AudioManager") if is_inside_tree() else null
					if am and am.has_method("play_error"):
						am.play_error()
					return
				cmd_type = "move"

	var res: Dictionary = citizen.call("issue_manual_command", cmd_type, cell, target_id)
	if not res.get("success", false):
		if hud != null:
			hud.show_event_banner("Lệnh Thất Bại", res.get("reason", "Không thể thực hiện lệnh"), false, 3.0)
		var am = get_node_or_null("/root/AudioManager") if is_inside_tree() else null
		if am and am.has_method("play_error"):
			am.play_error()
	else:
		var am = get_node_or_null("/root/AudioManager") if is_inside_tree() else null
		if am and am.has_method("play_click"):
			am.play_click()
		if hud != null and hud.has_method("_refresh_inspected_citizen"):
			hud._refresh_inspected_citizen()

func get_rival_inspection_query() -> RefCounted:
	return _rival_inspection_query

func clear_rival_selection_highlight() -> void:
	if building_highlight != null and selected_building_id.is_empty():
		building_highlight.clear_highlight()

func _try_select_rival_target(cell: Vector2i, click_world_pos: Vector2 = Vector2.INF) -> bool:
	var query := get_rival_inspection_query()
	if query == null:
		return false
	var rival_hit: Dictionary = query.find_rival_target_at_cell(cell, click_world_pos)
	if rival_hit.is_empty():
		return false
	var kind: String = String(rival_hit.get("kind", ""))
	if kind == "villager":
		clear_building_selection()
		if hud != null and hud.has_method("close_citizen_inspector"):
			hud.close_citizen_inspector()
		if hud != null and hud.has_method("show_rival_villager_inspector"):
			hud.show_rival_villager_inspector(String(rival_hit.get("settlement_id", "")), String(rival_hit.get("villager_id", "")), false)
		return true
	if kind == "settlement":
		clear_building_selection()
		if hud != null and hud.has_method("close_citizen_inspector"):
			hud.close_citizen_inspector()
		if building_highlight != null:
			building_highlight.set_footprint(
				rival_hit.get("building_cell", cell),
				rival_hit.get("building_size", Vector2i.ONE)
			)
		if hud != null and hud.has_method("show_rival_settlement_inspector"):
			hud.show_rival_settlement_inspector(String(rival_hit.get("settlement_id", "")))
		return true
	return false

func _handle_left_click(cell: Vector2i, click_world_pos: Vector2 = Vector2.INF) -> void:
	# AUD-3B-01: Fail closed if FogOfWar is missing or if clicked cell is in UNEXPLORED fog.
	# A cell in UNEXPLORED fog must not reveal hidden buildings, outposts, siege objectives,
	# or any other map entities.
	# Exception: Debug reveal & inspection mode (debug builds only) allows inspecting revealed
	# world objects/resources/POIs without granting gameplay permissions or altering FogOfWar.
	if fog_of_war == null or not fog_of_war.is_explored(cell):
		if debug_fog_disabled and OS.is_debug_build():
			if _try_select_rival_target(cell, click_world_pos):
				return
			var debug_info: Dictionary = inspect_cell_in_debug_mode(cell)
			if not debug_info.is_empty():
				if hud != null and hud.has_method("close_citizen_inspector"):
					hud.close_citizen_inspector()
				select_building(debug_info)
				return
		clear_building_selection()
		if hud != null and hud.has_method("close_citizen_inspector"):
			hud.close_citizen_inspector()
		if hud != null and hud.has_method("close_rival_inspectors"):
			hud.close_rival_inspectors()
		if hud != null and hud.has_method("close_entity_inspector"):
			hud.close_entity_inspector()
		return

	# Priority 2: Exact-cell citizen (ignore hidden/indoor-resting citizens)
	for cit in citizen_list:
		if is_instance_valid(cit) and cit.visible and int(cit.get("rest_phase")) != CitizenControllerScript.RestPhase.RESTING_INSIDE and cit.get("current_cell") == cell:
			clear_building_selection()
			if hud != null and hud.has_method("show_citizen_inspector"):
				hud.show_citizen_inspector(cit)
			return

	# Priority 2.5: Siege Objective Outpost at clicked cell (player buildings take precedence on occupied cells)
	if not buildings_by_cell.has(cell):
		var obj_at_cell = _find_siege_objective_at_cell(cell)
		if obj_at_cell != null and _is_cell_in_siege_objective(obj_at_cell, cell):
			if hud != null and hud.has_method("close_citizen_inspector"):
				hud.close_citizen_inspector()
			var obj_size: Vector2i = obj_at_cell.get("size") if (obj_at_cell.get("size") is Vector2i) else Vector2i(2, 2)
			var outpost_data := {
				"id": obj_at_cell.objective_id,
				"type": "outpost",
				"name": obj_at_cell.objective_name,
				"cell": obj_at_cell.current_cell,
				"size": obj_size,
				"state": "active" if obj_at_cell.is_alive else "destroyed",
				"health": int(obj_at_cell.health),
				"max_health": int(obj_at_cell.max_health),
				"owner": obj_at_cell.owning_faction_id,
				"is_outpost": true,
				"is_under_siege": bool(obj_at_cell.get("is_under_active_siege"))
			}
			select_building(outpost_data)
			return

	# Priority 3: Building footprint at clicked cell (1x1, 2x2, 3x3)
	var b_data := _get_building_at_cell(cell)
	if not b_data.is_empty():
		if hud != null and hud.has_method("close_citizen_inspector"):
			hud.close_citizen_inspector()
		select_building(b_data)
		return

	# Priority 4: Fuzzy adjacent citizen (within Manhattan distance 1, only if no building was clicked; ignore hidden/indoor-resting citizens)
	var best_cit: Node = null
	var best_dist: int = 2 # distance <= 1
	for cit in citizen_list:
		if is_instance_valid(cit) and cit.visible and int(cit.get("rest_phase")) != CitizenControllerScript.RestPhase.RESTING_INSIDE:
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

	# Priority 4.15: Visible Enemy Military Unit (exact cell first)
	if fog_of_war != null and fog_of_war.is_visible(cell) and enemy_military_mgr != null:
		var exact_enemy: Node2D = _find_enemy_unit_at_cell(cell)
		if exact_enemy != null and exact_enemy.current_cell == cell:
			clear_building_selection()
			if hud != null and hud.has_method("show_entity_inspector"):
				hud.call("show_entity_inspector", "military_unit", "enemy:%s" % str(exact_enemy.unit_id))
				return

	# Priority 4.2: Monster & Cave / Nest inspection under normal gameplay (M6-1 EntityInspectPanel)
	if monster_mgr != null:
		var m_info: Dictionary = monster_mgr.inspect_cell(cell, world_data, fog_of_war, debug_fog_disabled)
		if not m_info.is_empty():
			clear_building_selection()
			if hud != null and hud.has_method("show_entity_inspector"):
				hud.call("show_entity_inspector", str(m_info.get("category", "monster")), str(m_info.get("id", "")))
				return

	# Priority 4.22: Discovered POI inspection under normal gameplay (M6-1 EntityInspectPanel)
	if poi_mgr != null and fog_of_war != null and fog_of_war.is_explored(cell):
		var poi_obj = poi_mgr.get_poi_at(cell)
		if poi_obj != null and poi_obj.state != POIManager.POIState.UNDISCOVERED:
			clear_building_selection()
			if hud != null and hud.has_method("show_entity_inspector"):
				hud.call("show_entity_inspector", "poi", str(poi_obj.id))
				return

	# Priority 4.25: Visible wildlife inspection under normal gameplay (M6-1 EntityInspectPanel)
	if wildlife_mgr != null and (debug_fog_disabled or (fog_of_war != null and fog_of_war.is_visible(cell))):
		var wl_info: Dictionary = wildlife_mgr.inspect_cell(cell, world_data, fog_of_war, debug_fog_disabled)
		if not wl_info.is_empty():
			clear_building_selection()
			if hud != null and hud.has_method("show_entity_inspector"):
				hud.call("show_entity_inspector", "wildlife", str(wl_info.get("entity_id", "")))
				return

	# Priority 4.28: Fuzzy adjacent Enemy Military Unit (if no entity was directly on cell)
	if fog_of_war != null and fog_of_war.is_visible(cell) and enemy_military_mgr != null:
		var near_enemy: Node2D = _find_enemy_unit_at_cell(cell)
		if near_enemy != null:
			clear_building_selection()
			if hud != null and hud.has_method("show_entity_inspector"):
				hud.call("show_entity_inspector", "military_unit", "enemy:%s" % str(near_enemy.unit_id))
				return

	# Priority 4.3: Read-only Rival Villager / Rival Settlement inspection (Phase 7)
	if _try_select_rival_target(cell, click_world_pos):
		return

	# Priority 4.35: Natural Resource Node inspection in normal gameplay (Fog ON)
	if natural_resource_mgr != null and (debug_fog_disabled or (fog_of_war != null and fog_of_war.is_explored(cell))):
		var res_node: Dictionary = natural_resource_mgr.get_node_at_cell(cell)
		if not res_node.is_empty():
			clear_building_selection()
			if hud != null and hud.has_method("show_entity_inspector"):
				hud.call("show_entity_inspector", "natural_resource", str(res_node.get("id", "")))
				return

	# Priority 4.5: Debug object inspection on explored/visible cells when Fog is OFF
	if debug_fog_disabled and OS.is_debug_build():
		var debug_info: Dictionary = inspect_cell_in_debug_mode(cell)
		if not debug_info.is_empty():
			if hud != null and hud.has_method("close_citizen_inspector"):
				hud.close_citizen_inspector()
			select_building(debug_info)
			return

	# Priority 5: Empty ground - clear building selection and close inspectors
	clear_building_selection()
	if hud != null and hud.has_method("close_citizen_inspector"):
		hud.close_citizen_inspector()
	if hud != null and hud.has_method("close_rival_inspectors"):
		hud.close_rival_inspectors()
	if hud != null and hud.has_method("close_entity_inspector"):
		hud.close_entity_inspector()

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
		var role_ok: bool = bool(cit.call("set_role", new_role))
		if role_ok:
			print("[WorldView] Reassigned %s to role: %s" % [cid, new_role])
			sync_gameplay_terrain_preview_sources()
		else:
			push_warning("[WorldView] Role change rejected for %s -> %s" % [cid, new_role])

func _on_build_requested(type: String) -> void:
	if is_clear_land_mode:
		set_clear_land_mode(false)
	if hud != null and hud.has_method("is_army_move_targeting") and hud.call("is_army_move_targeting"):
		hud.call("cancel_army_move_targeting")
	placing_building_type = type
	bridge_start_bank = Vector2i(-1, -1)
	_bridge_preview_cells.clear()
	_last_bridge_preview = {}
	if type == "bridge":
		if ghost_building_node:
			ghost_building_node.visible = false
		if _bridge_preview_overlay:
			_bridge_preview_overlay.visible = true
			_bridge_preview_overlay.queue_redraw()
		if hud != null and hud.has_method("show_bridge_placement_ui"):
			hud.call("show_bridge_placement_ui", true, bridge_width, {})
	else:
		if _bridge_preview_overlay:
			_bridge_preview_overlay.visible = false
		if hud != null and hud.has_method("show_bridge_placement_ui"):
			hud.call("show_bridge_placement_ui", false, bridge_width, {})
		var tex: Texture2D = building_textures.get(type)
		if tex:
			ghost_building_sprite.texture = tex
			ghost_building_sprite.offset = _get_building_sprite_offset(type)
			ghost_building_node.visible = true
	_refresh_territory_overlay()

func set_bridge_width(w: int) -> void:
	bridge_width = clampi(w, EconomyConfig.BRIDGE_MIN_WIDTH, EconomyConfig.BRIDGE_MAX_WIDTH)
	if placing_building_type == "bridge":
		if IsoMath.is_in_bounds(_bridge_preview_hover_cell, world_data.map_width if world_data else 128, world_data.map_height if world_data else 128):
			_update_bridge_preview(_bridge_preview_hover_cell)
		elif hud != null and hud.has_method("show_bridge_placement_ui"):
			hud.call("show_bridge_placement_ui", true, bridge_width, _last_bridge_preview)

func _update_bridge_preview(hover_cell: Vector2i) -> void:
	_bridge_preview_hover_cell = hover_cell
	_bridge_preview_cells.clear()
	_bridge_preview_valid = false
	var preview_info: Dictionary = {}
	if bridge_start_bank == Vector2i(-1, -1):
		var start_ok: bool = BridgeSystem.is_cell_owned(hover_cell, world_data) and BridgeSystem.is_dry_walkable_land(hover_cell, world_data)
		_bridge_preview_valid = start_ok
		_bridge_preview_cells.append(hover_cell)
		preview_info = {
			"step": "select_start",
			"valid": start_ok,
			"width": bridge_width,
			"reason": "" if start_ok else "Chọn bờ đất trống thuộc lãnh thổ để bắt đầu bắc cầu"
		}
	else:
		var rm := _get_resource_mgr()
		var check := BridgeSystem.validate_bridge_placement(bridge_start_bank, hover_cell, bridge_width, world_data, fog_of_war, rm, bridge_width_offset)
		_bridge_preview_valid = bool(check.get("valid", false))
		var dc: Array = check.get("deck_cells", [])
		for c in dc:
			_bridge_preview_cells.append(c)
		if _bridge_preview_cells.is_empty():
			_bridge_preview_cells.append(bridge_start_bank)
			if hover_cell != bridge_start_bank:
				_bridge_preview_cells.append(hover_cell)
		preview_info = check
		preview_info["step"] = "select_end"
	_last_bridge_preview = preview_info
	if _bridge_preview_overlay != null:
		_bridge_preview_overlay.visible = true
		_bridge_preview_overlay.queue_redraw()
	if hud != null and hud.has_method("update_bridge_preview_ui"):
		hud.call("update_bridge_preview_ui", preview_info)

func _on_bridge_preview_draw() -> void:
	if _bridge_preview_overlay == null or placing_building_type != "bridge":
		return
	var fill_col := Color(0.25, 0.85, 0.35, 0.45) if _bridge_preview_valid else Color(0.9, 0.22, 0.22, 0.45)
	var border_col := Color(0.4, 1.0, 0.5, 0.9) if _bridge_preview_valid else Color(1.0, 0.35, 0.35, 0.9)
	for cell in _bridge_preview_cells:
		var c := IsoMath.map_to_local(cell)
		var poly := PackedVector2Array([
			c + Vector2(0, -IsoMath.HALF_HEIGHT),
			c + Vector2(IsoMath.HALF_WIDTH, 0),
			c + Vector2(0, IsoMath.HALF_HEIGHT),
			c + Vector2(-IsoMath.HALF_WIDTH, 0)
		])
		_bridge_preview_overlay.draw_colored_polygon(poly, fill_col)
		var closed := PackedVector2Array([poly[0], poly[1], poly[2], poly[3], poly[0]])
		_bridge_preview_overlay.draw_polyline(closed, border_col, 1.5)
	if bridge_start_bank != Vector2i(-1, -1):
		var sc := IsoMath.map_to_local(bridge_start_bank)
		var spoly := PackedVector2Array([
			sc + Vector2(0, -IsoMath.HALF_HEIGHT),
			sc + Vector2(IsoMath.HALF_WIDTH, 0),
			sc + Vector2(0, IsoMath.HALF_HEIGHT),
			sc + Vector2(-IsoMath.HALF_WIDTH, 0),
			sc + Vector2(0, -IsoMath.HALF_HEIGHT)
		])
		_bridge_preview_overlay.draw_polyline(spoly, Color(1.0, 0.9, 0.3, 1.0), 2.0)

func _handle_bridge_click(cell: Vector2i) -> void:
	if bridge_start_bank == Vector2i(-1, -1):
		if BridgeSystem.is_cell_owned(cell, world_data) and BridgeSystem.is_dry_walkable_land(cell, world_data):
			bridge_start_bank = cell
			_update_bridge_preview(cell)
		else:
			if hud != null and hud.has_method("show_event_banner"):
				hud.show_event_banner("Vị Trí Không Hợp Lệ", "Bờ xuất phát phải là đất trống thuộc lãnh thổ vương quốc.", false, 2.5)
			var am = get_node_or_null("/root/AudioManager")
			if am:
				am.play_error()
	else:
		execute_bridge_placement(bridge_start_bank, cell, bridge_width, bridge_width_offset)

func execute_bridge_placement(start_bank: Vector2i, end_bank: Vector2i, width: int = 1, width_offset: int = 0) -> Dictionary:
	var rm := _get_resource_mgr()
	var res := BridgeSystem.place_bridge(start_bank, end_bank, width, world_data, fog_of_war, rm, "under_construction", width_offset)
	if bool(res.get("success", false)):
		var b_data: Dictionary = res["building"]
		_instantiate_bridge_node(b_data)
		register_construction_jobs(b_data)
		var am = get_node_or_null("/root/AudioManager")
		if am:
			am.play_build()
		_cancel_placement()
	else:
		if hud != null and hud.has_method("show_event_banner"):
			hud.show_event_banner("Không Thể Xây Cầu", str(res.get("reason", "Vị trí đặt cầu không hợp lệ")), false, 3.0)
		var am = get_node_or_null("/root/AudioManager")
		if am:
			am.play_error()
	return res

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
		if hud != null and str(res.get("reason", "")).find("Ngoài lãnh thổ") != -1 and hud.has_method("show_event_banner"):
			hud.show_event_banner("Ngoài Lãnh Thổ Vương Quốc", "Nâng cấp Tòa Thị Chính để mở rộng lãnh thổ xây dựng.", false, 3.0)
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
	var is_repairing: bool = bool(b_data.get("is_repairing", false))
	var is_upgrading: bool = bool(b_data.get("is_upgrading", false))
	if b_state != "under_construction" and not is_repairing and not is_upgrading:
		return result

	var b_type: String = b_data.get("type", "")
	var origin: Vector2i = b_data.get("cell", Vector2i.ZERO)
	var size: Vector2i = b_data.get("size", Vector2i(1, 1))

	var capacity: int = BuildingSystem.get_construction_worker_capacity(b_type)
	var max_candidate_count: int = 2 * (size.x + size.y) + 16
	var perimeter: Array[Vector2i] = BridgeSystem.get_owned_access_cells(b_data, world_data) if b_type == "bridge" else BuildingSystem.find_perimeter_cells(origin, size, world_data, max_candidate_count)
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
		var desc: String = "Thi công xây dựng %s" % _get_building_display_name(b_type)
		var j_hours: float = float(b_data.get("construction_hours", 12.0))
		if is_repairing:
			desc = "Sửa chữa %s" % _get_building_display_name(b_type)
			j_hours = float(b_data.get("repair_hours_required", 2.0))
		elif is_upgrading:
			desc = "Nâng cấp %s" % _get_building_display_name(b_type)
			j_hours = float(b_data.get("upgrade_required_hours", 2.0))
		var job = job_mgr.create_job(
			"builder",
			cell,
			desc,
			b_id,
			j_hours,
			2,
			false
		)
		retained_jobs.append(job)
		used_cells.append(cell)

	result = retained_jobs
	return result

func advance_construction_work(b_id: String, delta_hours: float, p_resource_mgr: Object = null) -> Dictionary:
	if world_data == null:
		return {"success": false, "completed": false, "progress": 0.0, "hours": 0.0}

	var b_data: Dictionary = BuildingSystem.get_building_by_id(b_id, world_data)
	if b_data.is_empty():
		return {"success": false, "completed": false, "progress": 0.0, "hours": 0.0}

	var rm: Object = p_resource_mgr if p_resource_mgr != null else _get_resource_mgr()

	if bool(b_data.get("is_repairing", false)):
		var repair_result := BuildingSystem.advance_repair(b_data, delta_hours, world_data)
		if not repair_result.get("success", false):
			return repair_result
		if repair_result.get("completed", false):
			var completed_ok: bool = complete_repair(b_id, rm)
			if not completed_ok:
				repair_result["completed"] = false
				repair_result["completion_blocked"] = true
				repair_result["reason"] = "Sửa chữa hoàn thành thời gian thi công nhưng chưa thể hoàn tất (chờ ResourceManager sẵn sàng)"
		return repair_result

	if bool(b_data.get("is_upgrading", false)):
		var upgrade_result := BuildingSystem.advance_upgrade(b_data, delta_hours, world_data)
		if not upgrade_result.get("success", false):
			return upgrade_result
		if upgrade_result.get("completed", false):
			var completed_ok: bool = complete_upgrade(b_id, rm)
			if not completed_ok:
				upgrade_result["completed"] = false
				upgrade_result["completion_blocked"] = true
				upgrade_result["reason"] = "Nâng cấp hoàn thành thời gian thi công nhưng chưa thể hoàn tất (chờ ResourceManager sẵn sàng)"
		return upgrade_result

	var res := BuildingSystem.advance_construction(b_id, delta_hours, world_data)
	if not res.get("success", false):
		return res

	if res.get("completed", false):
		var completed_ok: bool = complete_construction(b_id, rm)
		if not completed_ok:
			res["completed"] = false
			res["completion_blocked"] = true
			res["reason"] = "Thi công xây dựng đã hoàn thành thời gian nhưng chưa thể hoàn tất"

	return res

func complete_construction(b_id: String, p_resource_mgr: Object = null) -> bool:
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

	var rm: Object = p_resource_mgr if p_resource_mgr != null else _get_resource_mgr()
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
	sync_gameplay_terrain_preview_sources()

	# If farm, woodcutter, quarry, mine, or workshop, register dynamic workplace
	if b_data["type"] in ["farm", "woodcutter", "quarry", "mine", "workshop"]:
		register_dynamic_workplace(b_data)
	elif b_data["type"] == "cookhouse" and cookhouse_mgr != null:
		cookhouse_mgr.register_cookhouse(b_id)

	# If watchtower, refresh world vision (updates FogTileMapLayer, Minimap, and POI discovery)
	if b_data["type"] == "watchtower" and fog_of_war != null:
		refresh_world_vision()

	# If research_hall, refresh research UI in hud
	if b_data["type"] == "research_hall" and hud != null:
		hud.call("_refresh_research_ui")

	if territory_mgr != null:
		if b_data["type"] == "townhall":
			if workplace_mgr != null:
				var drop_cell := origin + Vector2i(0, 4)
				if not IsoMath.is_in_bounds(drop_cell):
					drop_cell = origin + Vector2i(0, 3)
				workplace_mgr.register_dropoff(b_id, "townhall", drop_cell)
			territory_mgr.recalculate_territory()
			_refresh_territory_overlay()
		else:
			territory_mgr.invalidate_walkable_cache()

	if b_data["type"] == "townhall" and hud != null and hud.has_method("_refresh_emergency_townhall_button"):
		hud.call("_refresh_emergency_townhall_button")

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

func start_building_upgrade(b_id: String, p_resource_mgr: Object = null) -> Dictionary:
	if world_data == null or b_id == "":
		return {"success": false, "reason": "Dữ liệu thế giới không hợp lệ"}

	var b_data := BuildingSystem.get_building_by_id(b_id, world_data)
	if b_data.is_empty():
		return {"success": false, "reason": "Công trình không tồn tại"}

	var rm: Object = p_resource_mgr if p_resource_mgr != null else _get_resource_mgr()
	var res := BuildingSystem.start_upgrade(b_data, world_data, rm)
	if not res.get("success", false):
		return res

	register_upgrade_jobs(b_data)

	if hud != null and hud.has_method("refresh_building_inspector"):
		hud.refresh_building_inspector()

	return res

func cancel_building_upgrade(b_id: String, p_resource_mgr: Object = null) -> Dictionary:
	if world_data == null or b_id == "":
		return {"success": false, "reason": "Dữ liệu thế giới không hợp lệ"}

	var b_data := BuildingSystem.get_building_by_id(b_id, world_data)
	if b_data.is_empty():
		return {"success": false, "reason": "Công trình không tồn tại"}

	var rm: Object = p_resource_mgr if p_resource_mgr != null else _get_resource_mgr()
	var res := BuildingSystem.cancel_upgrade(b_data, world_data, rm, job_mgr)
	if not res.get("success", false):
		return res

	if citizen_list != null:
		for cit in citizen_list:
			if is_instance_valid(cit) and cit.get("active_job") != null and JobManager.job_matches_building(cit.active_job, b_id):
				cit.active_job = null
				cit.set("current_state", CitizenController.State.IDLE)
				if cit.has_method("_update_reason"):
					cit.call("_update_reason")

	if hud != null and hud.has_method("refresh_building_inspector"):
		hud.refresh_building_inspector()

	return res

func complete_upgrade(b_id: String, p_resource_mgr: Object = null) -> bool:
	if world_data == null or b_id == "":
		return false

	var b_data := BuildingSystem.get_building_by_id(b_id, world_data)
	if b_data.is_empty() or not bool(b_data.get("is_upgrading", false)):
		return false

	var rm: Object = p_resource_mgr if p_resource_mgr != null else _get_resource_mgr()
	var res := BuildingSystem.complete_building_upgrade(b_data, world_data, rm)
	if not res.get("success", false):
		return false

	var new_lvl: int = int(res.get("new_level", 1))
	var b_type: String = b_data.get("type", "")

	# Clean up upgrade builder jobs and release workers
	if job_mgr:
		var b_jobs := job_mgr.get_jobs_for_building(b_id)
		for j in b_jobs:
			if j.type == "builder":
				job_mgr.complete_job(j)
		job_mgr.remove_jobs_for_building(b_id)

	if citizen_list != null:
		for cit in citizen_list:
			if is_instance_valid(cit) and cit.get("active_job") != null and JobManager.job_matches_building(cit.active_job, b_id):
				cit.active_job = null
				cit.set("current_state", CitizenController.State.IDLE)
				if cit.has_method("_update_reason"):
					cit.call("_update_reason")

	# Update runtime subsystems for new level
	if b_type == "farm" and workplace_mgr != null:
		var wp = workplace_mgr.get_workplace(b_id)
		if wp == null and (b_data.get("cell", Vector2i.ZERO) == Vector2i(36, 35) or b_id == "farm_starter"):
			wp = workplace_mgr.get_workplace("farm_starter")
		if wp != null:
			wp.level_multiplier = EconomyConfig.get_farm_multiplier(new_lvl)
	elif b_type == "house":
		var housing_cap: int = BuildingSystem.get_total_housing_capacity(world_data)
		if hud != null and hud.has_method("update_population_display"):
			hud.update_population_display(citizen_list.size() if citizen_list != null else 0, housing_cap)
	elif b_type == "townhall":
		if territory_mgr != null:
			var tinfo: Dictionary = territory_mgr.recalculate_territory()
			_refresh_territory_overlay()
			sync_gameplay_terrain_preview_sources()
			if hud != null and hud.has_method("show_event_banner"):
				hud.show_event_banner("Mở Rộng Lãnh Thổ!", "Tòa Thị Chính cấp %d — Bán kính lãnh thổ: %d ô." % [int(tinfo.get("level", new_lvl)), int(tinfo.get("radius", 0))], true, 4.0)

	if hud != null and hud.has_method("refresh_building_inspector"):
		hud.refresh_building_inspector()

	var am = get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_build"):
		am.play_build()

	_refresh_objective_building_overlaps()
	print("[WorldView] Upgrade completed for %s (%s) -> Level %d" % [b_id, b_type, new_lvl])
	return true

func register_upgrade_jobs(b_data: Dictionary) -> Array[JobManager.JobData]:
	var result: Array[JobManager.JobData] = []
	if job_mgr == null or world_data == null or b_data.is_empty():
		return result

	var b_id: String = b_data.get("id", "")
	if b_id == "" or not bool(b_data.get("is_upgrading", false)):
		return result

	var b_type: String = b_data.get("type", "")
	var origin: Vector2i = b_data.get("cell", Vector2i.ZERO)
	var size: Vector2i = b_data.get("size", Vector2i(1, 1))
	var target_lvl: int = int(b_data.get("upgrade_target_level", 2))
	var duration: float = float(b_data.get("upgrade_required_hours", 2.0))

	var capacity: int = BuildingSystem.get_construction_worker_capacity(b_type)
	var max_candidate_count: int = 2 * (size.x + size.y) + 16
	var perimeter: Array[Vector2i] = BridgeSystem.get_owned_access_cells(b_data, world_data) if b_type == "bridge" else BuildingSystem.find_perimeter_cells(origin, size, world_data, max_candidate_count)
	var max_jobs: int = mini(capacity, perimeter.size())

	if nav != null and world_data != null and nav.world_data != world_data:
		nav.world_data = world_data

	var all_matching_jobs := job_mgr.get_jobs_for_building(b_id)
	var existing_builder_jobs: Array[JobManager.JobData] = []
	for j in all_matching_jobs:
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

	var jobs_by_cell: Dictionary = {}
	for j in valid_candidates:
		if not jobs_by_cell.has(j.target_cell):
			jobs_by_cell[j.target_cell] = []
		jobs_by_cell[j.target_cell].append(j)

	var unique_cell_jobs: Array[JobManager.JobData] = []
	var duplicate_jobs_to_remove: Array[JobManager.JobData] = []

	for cell in jobs_by_cell:
		var list_at_cell: Array = jobs_by_cell[cell]
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

	var retained_jobs: Array[JobManager.JobData] = []
	var excess_jobs_to_remove: Array[JobManager.JobData] = []

	if unique_cell_jobs.size() > max_jobs:
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

	var all_removals: Array[JobManager.JobData] = []
	all_removals.append_array(stale_jobs)
	all_removals.append_array(duplicate_jobs_to_remove)
	all_removals.append_array(excess_jobs_to_remove)

	var seen_remove_ids: Dictionary = {}
	for rem_j in all_removals:
		if not seen_remove_ids.has(rem_j.id):
			seen_remove_ids[rem_j.id] = true
			_safe_cleanup_construction_job(rem_j)

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
			"Nâng cấp %s lên Cấp %d" % [_get_building_display_name(b_type), target_lvl],
			b_id,
			duration,
			2,
			false
		)
		retained_jobs.append(job)
		used_cells.append(cell)

	result = retained_jobs
	return result


func cancel_construction_project(b_id: String) -> Dictionary:
	if world_data == null:
		return {"success": false, "reason": "Dữ liệu thế giới rỗng"}

	var b_data: Dictionary = BuildingSystem.get_building_by_id(b_id, world_data)
	if b_data.is_empty():
		return {"success": false, "reason": "Công trình không tồn tại"}

	if str(b_data.get("type", "")) == "bridge" and BridgeSystem.has_living_units_on_bridge(b_data, citizen_list, tactical_military_mgr, enemy_military_mgr):
		return {"success": false, "reason": "Không thể dỡ cầu khi vẫn còn đơn vị đang đứng trên mặt cầu"}

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
	if type == "house":
		_evict_house_occupants(b_id, "Nhà ở đã bị dỡ bỏ")
	if territory_mgr != null:
		if type == "townhall":
			territory_mgr.recalculate_territory()
			_refresh_territory_overlay()
		else:
			territory_mgr.invalidate_walkable_cache()
	if type == "townhall" and hud != null and hud.has_method("_refresh_emergency_townhall_button"):
		hud.call("_refresh_emergency_townhall_button")
	var node_name := "Building_%s_%d_%d" % [type, origin.x, origin.y]
	var b_node = buildings_container.get_node_or_null(node_name)
	if b_node:
		b_node.queue_free()

	for ox in range(size.x):
		for oy in range(size.y):
			buildings_by_cell.erase(origin + Vector2i(ox, oy))
	_refresh_objective_building_overlaps()

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

func set_building_state(b_id: String, new_state: String, from_state: String = "") -> bool:
	if world_data == null or b_id == "":
		return false
	var b_data: Dictionary = BuildingSystem.get_building_by_id(b_id, world_data)
	if b_data.is_empty():
		return false
	var old_state: String = from_state if from_state != "" else b_data.get("state", "")
	if old_state == new_state:
		return true

	var type: String = b_data.get("type", "")
	if territory_mgr != null:
		if type == "townhall":
			territory_mgr.recalculate_territory()
			_refresh_territory_overlay()
		else:
			territory_mgr.invalidate_walkable_cache()
	if type == "townhall" and hud != null and hud.has_method("_refresh_emergency_townhall_button"):
		hud.call("_refresh_emergency_townhall_button")
	# Validate state transitions fail-closed:
	if new_state == "paused":
		# Only supported pausable workplace types can be paused
		if not BuildingSystem.is_building_pausable(type):
			return false
		# Only active buildings can be paused (or preserve pause preference when damaged)
		if old_state != "active" and old_state != "damaged":
			return false
		if old_state == "damaged":
			b_data["pre_damage_state"] = "paused"
			if workplace_mgr != null:
				workplace_mgr.set_workplace_pause_reason(b_id, WorkplaceManager.PAUSE_REASON_PLAYER, true)
			return true
	elif new_state == "active":
		# Can only resume if currently paused, completing construction, or recovering from damaged/repairing
		if old_state != "paused" and old_state != "under_construction" and old_state != "damaged" and old_state != "repairing":
			return false
		if old_state == "paused" and not BuildingSystem.is_building_pausable(type):
			return false
	elif new_state == "damaged":
		if old_state == "destroyed":
			return false
	elif new_state == "destroyed":
		pass
	else:
		return false

	b_data["state"] = new_state
	if type == "bridge" and world_data != null:
		BridgeSystem.rebuild_bridge_walkability(world_data)
		if territory_mgr != null:
			territory_mgr.invalidate_walkable_cache()

	var origin: Vector2i = b_data.get("cell", Vector2i.ZERO)
	var node_name := "Building_%s_%d_%d" % [type, origin.x, origin.y]
	var b_node = buildings_container.get_node_or_null(node_name) if buildings_container != null else null
	if b_node != null and b_node.has_method("set_bridge_state"):
		b_node.call("set_bridge_state", new_state)
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
			workplace_mgr.set_workplace_pause_reason(b_id, WorkplaceManager.PAUSE_REASON_PLAYER, true)
		if spr != null:
			spr.modulate = Color(0.7, 0.7, 0.7, 0.85)
		# Release active workers targeting this building
		for cit in citizen_list:
			if is_instance_valid(cit) and cit.get("active_job") != null and JobManager.job_matches_building(cit.active_job, b_id):
				if cit.has_method("interrupt_current_job"):
					cit.call("interrupt_current_job", "Công trình tạm dừng hoạt động", false)
				else:
					if job_mgr != null:
						job_mgr.release_job(cit.active_job)
					cit.active_job = null
					cit.set("current_state", CitizenController.State.IDLE)
					cit.set("status_reason", "Công trình tạm dừng hoạt động")
	elif new_state == "damaged":
		if old_state == "active" or old_state == "paused":
			b_data["pre_damage_state"] = old_state
		if int(b_data.get("health", 100)) >= 100:
			b_data["health"] = 50
		if workplace_mgr != null:
			workplace_mgr.set_workplace_pause_reason(b_id, WorkplaceManager.PAUSE_REASON_DAMAGED, true)
		if spr != null:
			spr.modulate = Color(0.85, 0.45, 0.45, 0.9)
		# Release active workers targeting this building
		for cit in citizen_list:
			if is_instance_valid(cit) and cit.get("active_job") != null and JobManager.job_matches_building(cit.active_job, b_id):
				if cit.has_method("interrupt_current_job"):
					cit.call("interrupt_current_job", "Công trình bị hư hại", false)
				else:
					if job_mgr != null:
						job_mgr.release_job(cit.active_job)
					cit.active_job = null
					cit.set("current_state", CitizenController.State.IDLE)
					cit.set("status_reason", "Công trình bị hư hại")
	elif new_state == "active":
		if old_state == "damaged" or old_state == "repairing":
			b_data["health"] = int(b_data.get("max_health", 100))
			b_data["is_repairing"] = false
			b_data["repair_progress"] = 0.0
			b_data["repair_cost"] = {}
			b_data["repair_reserved"] = false
			if workplace_mgr != null:
				workplace_mgr.set_workplace_pause_reason(b_id, WorkplaceManager.PAUSE_REASON_DAMAGED, false)
		elif old_state == "paused":
			if workplace_mgr != null:
				workplace_mgr.set_workplace_pause_reason(b_id, WorkplaceManager.PAUSE_REASON_PLAYER, false)
		if spr != null:
			spr.modulate = Color(1.0, 1.0, 1.0, 1.0)
	elif new_state == "destroyed":
		if spr != null:
			spr.modulate = Color(0.35, 0.25, 0.25, 0.7)
		if workplace_mgr != null:
			if workplace_mgr.has_method("unregister_workplace"):
				workplace_mgr.unregister_workplace(b_id)
			elif workplace_mgr.has_method("set_workplace_pause_reason"):
				workplace_mgr.set_workplace_pause_reason(b_id, "destroyed", true)
			if workplace_mgr.has_method("unregister_dropoff"):
				workplace_mgr.unregister_dropoff(b_id)
		for cit in citizen_list:
			if is_instance_valid(cit) and cit.get("active_job") != null and JobManager.job_matches_building(cit.active_job, b_id):
				if cit.has_method("interrupt_current_job"):
					cit.call("interrupt_current_job", "Công trình đã bị phá hủy", false)
				else:
					if job_mgr != null:
						job_mgr.release_job(cit.active_job)
					cit.active_job = null
					cit.set("current_state", CitizenController.State.IDLE)
					cit.set("status_reason", "Công trình đã bị phá hủy")
		if player_army_mgr != null:
			if player_army_mgr.has_method("evict_and_cancel_outpost"):
				player_army_mgr.call("evict_and_cancel_outpost", b_id, true, true)
			elif player_army_mgr.has_method("evict_outpost_garrison"):
				player_army_mgr.call("evict_outpost_garrison", b_id, true)
				if player_army_mgr.has_method("cancel_outpost_reinforcements"):
					player_army_mgr.call("cancel_outpost_reinforcements", b_id, true)
		elif b_data.get("type", "") == "outpost":
			push_error("Invariant violation: player_army_mgr is null while destroying outpost %s; garrison records cannot be resolved" % b_id)
		if b_data.get("type", "") == "house":
			_evict_house_occupants(b_id, "Nhà ở đã bị phá hủy")

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

func damage_building(b_id: String, amount: int) -> bool:
	if world_data == null or b_id == "" or amount <= 0:
		return false
	var b_data: Dictionary = BuildingSystem.get_building_by_id(b_id, world_data)
	if b_data.is_empty():
		return false
	var prev_state: String = str(b_data.get("state", "active"))
	if prev_state == "destroyed":
		return false

	var rm: Object = _get_resource_mgr()
	var res := BuildingSystem.apply_damage(b_data, amount, world_data, rm)
	if not res.get("success", false):
		return false

	var new_state: String = str(b_data.get("state", prev_state))
	if prev_state != new_state:
		set_building_state(b_id, new_state, prev_state)

	if prev_state != new_state and str(b_data.get("type", "")) == "townhall" and (new_state == "destroyed" or prev_state == "destroyed"):
		if territory_mgr != null:
			territory_mgr.recalculate_territory()
			_refresh_territory_overlay()
		sync_gameplay_terrain_preview_sources()

	if hud != null and hud.has_method("refresh_building_inspector") and selected_building_id == b_id:
		hud.refresh_building_inspector()

	return true

func start_repair_building(b_id: String, p_resource_mgr: Object = null) -> Dictionary:
	if world_data == null or b_id == "":
		return {"success": false, "reason": "Dữ liệu thế giới rỗng"}

	var b_data: Dictionary = BuildingSystem.get_building_by_id(b_id, world_data)
	if b_data.is_empty():
		return {"success": false, "reason": "Công trình không tồn tại"}

	var rm: Object = p_resource_mgr if p_resource_mgr != null else _get_resource_mgr()
	var res := BuildingSystem.start_repair(b_data, world_data, rm)
	if not res.get("success", false):
		return res

	# Create builder jobs for repair
	register_construction_jobs(b_data)

	if hud != null and hud.has_method("refresh_building_inspector") and selected_building_id == b_id:
		hud.refresh_building_inspector()

	return res

func start_townhall_restoration(b_id: String, p_resource_mgr: Object = null) -> Dictionary:
	if world_data == null or b_id == "":
		return {"success": false, "reason": "Dữ liệu thế giới không hợp lệ"}

	var b_data := BuildingSystem.get_building_by_id(b_id, world_data)
	if b_data.is_empty():
		return {"success": false, "reason": "Công trình không tồn tại"}

	var rm: Object = p_resource_mgr if p_resource_mgr != null else _get_resource_mgr()
	var res := BuildingSystem.start_townhall_restoration(b_data, world_data, rm)
	if not res.get("success", false):
		return res

	register_construction_jobs(b_data)

	if hud != null:
		if hud.has_method("refresh_building_inspector") and selected_building_id == b_id:
			hud.refresh_building_inspector()
		if hud.has_method("_refresh_emergency_townhall_button"):
			hud.call("_refresh_emergency_townhall_button")

	return res

func start_emergency_townhall_rebuild(p_resource_mgr: Object = null) -> Dictionary:
	if world_data == null:
		return {"success": false, "reason": "Dữ liệu thế giới không hợp lệ"}

	var rm: Object = p_resource_mgr if p_resource_mgr != null else _get_resource_mgr()
	var owned_cnt: int = int(territory_mgr.get_owned_count()) if territory_mgr != null else 0
	var res := BuildingSystem.place_emergency_townhall(world_data.townhall_anchor, world_data, rm, owned_cnt)
	if not res.get("success", false):
		return res

	var b_data: Dictionary = res.get("building", {})
	var origin: Vector2i = b_data.get("cell", Vector2i.ZERO)
	var size: Vector2i = b_data.get("size", Vector2i(3, 3))
	_instantiate_building_node("townhall", origin, size, "under_construction")
	for ox in range(size.x):
		for oy in range(size.y):
			buildings_by_cell[origin + Vector2i(ox, oy)] = b_data

	register_construction_jobs(b_data)

	if territory_mgr != null:
		territory_mgr.invalidate_walkable_cache()

	if hud != null and hud.has_method("_refresh_emergency_townhall_button"):
		hud.call("_refresh_emergency_townhall_button")

	return res

func advance_repair_work(b_id: String, delta_hours: float, p_resource_mgr: Object = null) -> Dictionary:
	return advance_construction_work(b_id, delta_hours, p_resource_mgr)

func complete_repair(b_id: String, p_resource_mgr: Object = null) -> bool:
	if world_data == null or b_id == "":
		return false

	var b_data: Dictionary = BuildingSystem.get_building_by_id(b_id, world_data)
	if b_data.is_empty() or not bool(b_data.get("is_repairing", false)):
		return false

	var rm: Object = p_resource_mgr if p_resource_mgr != null else _get_resource_mgr()
	var res := BuildingSystem.complete_repair(b_data, world_data, rm)
	if not res.get("success", false):
		return false

	# Clean up builder jobs for this building
	if job_mgr != null and job_mgr.has_method("get_jobs_for_building"):
		var jobs := job_mgr.get_jobs_for_building(b_id)
		for j in jobs:
			if j.type == "builder":
				_safe_cleanup_construction_job(j)

	var target_state: String = res.get("new_state", "active")
	var origin: Vector2i = b_data.get("cell", Vector2i.ZERO)
	var type: String = b_data.get("type", "")
	if territory_mgr != null:
		if type == "townhall":
			if workplace_mgr != null:
				var drop_cell := origin + Vector2i(0, 4)
				if not IsoMath.is_in_bounds(drop_cell):
					drop_cell = origin + Vector2i(0, 3)
				workplace_mgr.register_dropoff(b_id, "townhall", drop_cell)
			territory_mgr.recalculate_territory()
			_refresh_territory_overlay()
		else:
			territory_mgr.invalidate_walkable_cache()
	if type == "townhall" and hud != null and hud.has_method("_refresh_emergency_townhall_button"):
		hud.call("_refresh_emergency_townhall_button")
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

	if workplace_mgr != null:
		workplace_mgr.set_workplace_pause_reason(b_id, WorkplaceManager.PAUSE_REASON_DAMAGED, false)
	if target_state == "paused":
		if workplace_mgr != null:
			workplace_mgr.set_workplace_pause_reason(b_id, WorkplaceManager.PAUSE_REASON_PLAYER, true)
		if spr != null:
			spr.modulate = Color(0.7, 0.7, 0.7, 0.85)
	else:
		if spr != null:
			spr.modulate = Color(1.0, 1.0, 1.0, 1.0)

	if type == "barracks":
		if hud != null and hud.has_method("_refresh_role_options"):
			hud.call("_refresh_role_options")
		if player_army_mgr != null and player_army_mgr.has_method("notify_capacity_changed"):
			player_army_mgr.call("notify_capacity_changed")
		elif hud != null and hud.has_method("_refresh_army_panel"):
			hud.call("_refresh_army_panel")

	if type == "market":
		refresh_caravan_marker()

	if hud != null and hud.has_method("refresh_building_inspector") and selected_building_id == b_id:
		hud.refresh_building_inspector()

	return true

func cancel_repair_building(b_id: String, p_resource_mgr: Object = null) -> Dictionary:
	if world_data == null or b_id == "":
		return {"success": false, "reason": "Dữ liệu thế giới rỗng"}

	var b_data: Dictionary = BuildingSystem.get_building_by_id(b_id, world_data)
	if b_data.is_empty():
		return {"success": false, "reason": "Công trình không tồn tại"}

	var rm: Object = p_resource_mgr if p_resource_mgr != null else _get_resource_mgr()
	var res := BuildingSystem.cancel_repair(b_data, world_data, rm)
	if not res.get("success", false):
		return res

	# Clean up builder jobs
	if job_mgr != null and job_mgr.has_method("get_jobs_for_building"):
		var jobs := job_mgr.get_jobs_for_building(b_id)
		for j in jobs:
			if j.type == "builder":
				_safe_cleanup_construction_job(j)

	if hud != null and hud.has_method("refresh_building_inspector") and selected_building_id == b_id:
		hud.refresh_building_inspector()

	return res

func get_carried_cargo_for_building(b_id: String) -> Dictionary:
	var cargo: Dictionary = {}
	if citizen_list == null or b_id == "":
		return cargo
	for cit in citizen_list:
		if is_instance_valid(cit):
			var matches_job: bool = (cit.get("active_job") != null and JobManager.job_matches_building(cit.active_job, b_id))
			var wp_id: String = String(cit.get("workplace_id")) if cit.get("workplace_id") != null else ""
			var matches_wp: bool = (wp_id == b_id or wp_id.begins_with(b_id + "_"))
			var src_id: String = String(cit.get("carrying_source_workplace_id")) if cit.get("carrying_source_workplace_id") != null else ""
			var matches_src: bool = (src_id == b_id or src_id.begins_with(b_id + "_"))
			if matches_job or matches_wp or matches_src:
				var carry_amt: int = int(cit.get("carrying_amount")) if cit.get("carrying_amount") != null else 0
				var carry_res: String = cit.get("carrying_resource") if cit.get("carrying_resource") != null else ""
				if carry_amt > 0 and carry_res != "":
					cargo[carry_res] = cargo.get(carry_res, 0) + carry_amt
	return cargo

func demolish_building_project(b_id: String) -> Dictionary:
	if world_data == null or b_id == "":
		return {"success": false, "reason": "Dữ liệu thế giới rỗng"}
	var b_data: Dictionary = BuildingSystem.get_building_by_id(b_id, world_data)
	if b_data.is_empty():
		return {"success": false, "reason": "Công trình không tồn tại"}

	if str(b_data.get("type", "")) == "bridge" and BridgeSystem.has_living_units_on_bridge(b_data, citizen_list, tactical_military_mgr, enemy_military_mgr):
		return {"success": false, "reason": "Không thể dỡ cầu khi vẫn còn đơn vị đang đứng trên mặt cầu"}

	var rm := get_node_or_null("/root/ResourceManager")
	if bool(b_data.get("is_repairing", false)):
		cancel_repair_building(b_id, rm)
	# Preflight check: must conserve both refunds and any carried cargo without inventory loss
	var carried_cargo := get_carried_cargo_for_building(b_id)

	# Preflight check: prevent Cookhouse demolition while active batch or pending output exists
	if str(b_data.get("type", "")) == "cookhouse" and cookhouse_mgr != null:
		var ck_check := cookhouse_mgr.can_remove_cookhouse(b_id)
		if not bool(ck_check.get("can_remove", true)):
			return {"success": false, "reason": str(ck_check.get("reason", "Không thể dỡ bỏ Nhà Bếp lúc này"))}

	# Preflight check: verify BuildingSystem demolition eligibility BEFORE mutating military state
	var can_demo: Dictionary = BuildingSystem.can_demolish_building(b_data, world_data, rm, 0.5, carried_cargo)
	if not bool(can_demo.get("can_demolish", false)):
		return {"success": false, "reason": str(can_demo.get("reason", "Không thể dỡ bỏ công trình"))}

	# Preflight check: verify garrison/reinforcement evacuation if building contains military
	var total_military: int = 0
	if player_army_mgr != null:
		if player_army_mgr.has_method("get_garrison_count"):
			total_military += int(player_army_mgr.call("get_garrison_count", b_id))
		if player_army_mgr.has_method("get_in_transit_count"):
			total_military += int(player_army_mgr.call("get_in_transit_count", b_id))
	var tmm_check = player_army_mgr.get("tactical_military_mgr") if (player_army_mgr and player_army_mgr.get("tactical_military_mgr") != null) else tactical_military_mgr
	var military_snapshot: Dictionary = {}
	if total_military > 0:
		if tmm_check == null or not is_instance_valid(tmm_check):
			return {"success": false, "reason": "Hệ thống quân sự chiến thuật không khả dụng để tiếp nhận binh sĩ rút về"}
		var rally_c: Vector2i = player_army_mgr.call("get_rally_cell") if (player_army_mgr and player_army_mgr.has_method("get_rally_cell")) else Vector2i(32, 33)
		if not tmm_check.has_method("can_allocate_spawns") or not bool(tmm_check.call("can_allocate_spawns", total_military, rally_c)):
			return {"success": false, "reason": "Không đủ vị trí trống quanh căn cứ để tiếp nhận binh sĩ rút về"}

		# Capture military snapshot before voluntary eviction for atomic rollback safety
		if player_army_mgr.has_method("get_outpost_military_snapshot"):
			military_snapshot = player_army_mgr.call("get_outpost_military_snapshot", b_id)

		# Perform voluntary eviction BEFORE destructive demolition (Policy A)
		if player_army_mgr.has_method("evict_and_cancel_outpost"):
			var evict_res: Dictionary = player_army_mgr.call("evict_and_cancel_outpost", b_id, true, false)
			if not bool(evict_res.get("success", false)):
				return {"success": false, "reason": str(evict_res.get("reason", "Không thể di tản binh sĩ về căn cứ"))}
			military_snapshot["spawned_unit_ids"] = evict_res.get("spawned_unit_ids", [])

	var res := BuildingSystem.demolish_building(b_data, world_data, rm, job_mgr, 0.5, carried_cargo)
	if not res.get("success", false):
		# Atomic rollback: restore exact military snapshot if building demolition failed
		if total_military > 0 and not military_snapshot.is_empty() and player_army_mgr != null and player_army_mgr.has_method("restore_outpost_military_snapshot"):
			player_army_mgr.call("restore_outpost_military_snapshot", military_snapshot)
		return res

	if str(b_data.get("type", "")) == "cookhouse" and cookhouse_mgr != null:
		cookhouse_mgr.unregister_cookhouse(b_id)

	# Evict any stationed garrison and cancel in-transit reinforcements back to central reserve if not already done
	if total_military > 0 and (player_army_mgr == null or not player_army_mgr.has_method("evict_and_cancel_outpost")):
		if player_army_mgr != null and player_army_mgr.has_method("evict_outpost_garrison"):
			player_army_mgr.call("evict_outpost_garrison", b_id, true)
			if player_army_mgr.has_method("cancel_outpost_reinforcements"):
				player_army_mgr.call("cancel_outpost_reinforcements", b_id, true)

	# Clear building selection if demolished building was currently selected
	if selected_building_id == b_id:
		clear_building_selection()

	var origin: Vector2i = b_data.get("cell", Vector2i.ZERO)
	var size: Vector2i = b_data.get("size", Vector2i(1, 1))
	var type: String = b_data.get("type", "")
	if type == "house":
		_evict_house_occupants(b_id, "Nhà ở đã bị dỡ bỏ")
	if type == "townhall" and world_data != null and not IsoMath.is_in_bounds(world_data.townhall_anchor):
		world_data.townhall_anchor = origin
	if territory_mgr != null:
		if type == "townhall":
			territory_mgr.recalculate_territory()
			_refresh_territory_overlay()
		else:
			territory_mgr.invalidate_walkable_cache()
	if type == "townhall" and hud != null and hud.has_method("_refresh_emergency_townhall_button"):
		hud.call("_refresh_emergency_townhall_button")
	var node_name := "Building_%s_%d_%d" % [type, origin.x, origin.y]
	var b_node = buildings_container.get_node_or_null(node_name) if buildings_container != null else null
	if b_node:
		b_node.queue_free()
	for ox in range(size.x):
		for oy in range(size.y):
			buildings_by_cell.erase(origin + Vector2i(ox, oy))
	_refresh_objective_building_overlaps()

	# Release any citizens assigned to this building to IDLE and deposit cargo safely
	for cit in citizen_list:
		if is_instance_valid(cit):
			var matches_job: bool = (cit.get("active_job") != null and JobManager.job_matches_building(cit.active_job, b_id))
			var wp_id: String = String(cit.get("workplace_id")) if cit.get("workplace_id") != null else ""
			var matches_wp: bool = (wp_id == b_id or wp_id.begins_with(b_id + "_"))
			var src_id: String = String(cit.get("carrying_source_workplace_id")) if cit.get("carrying_source_workplace_id") != null else ""
			var matches_src: bool = (src_id == b_id or src_id.begins_with(b_id + "_"))
			if matches_job or matches_wp or matches_src:
				# Conserve carried goods: deposit directly into central storage so goods are never lost
				var carry_amt: int = int(cit.get("carrying_amount")) if cit.get("carrying_amount") != null else 0
				var carry_res: String = cit.get("carrying_resource") if cit.get("carrying_resource") != null else ""
				if carry_amt > 0 and carry_res != "" and rm != null:
					var added: int = rm.add_resource(carry_res, carry_amt)
					var rem: int = carry_amt - added
					cit.set("carrying_amount", rem)
					if rem <= 0:
						cit.set("carrying_resource", "")
						cit.set("carrying_source_workplace_id", "")
					else:
						# If central storage could not accept remaining cargo, preserve source ID and report
						print("[WorldView] Partial cargo deposit on demolition: %d %s retained on citizen %s (source: %s)" % [rem, carry_res, cit.get("citizen_id", ""), src_id])

				if matches_job:
					if job_mgr != null:
						job_mgr.release_job(cit.active_job)
					cit.active_job = null
					cit.set("current_state", CitizenController.State.IDLE)
					cit.set("status_reason", "Công trình đã bị dỡ bỏ")
					# Note: Do not call _update_reason() here as it overwrites custom status reason
				elif matches_src or matches_wp:
					if cit.get("current_state") == CitizenController.State.HAULING:
						cit.set("current_state", CitizenController.State.IDLE)
						cit.set("status_reason", "Công trình đã bị dỡ bỏ")

				if matches_wp:
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
		var workshop_blueprint: Dictionary = EconomyConfig.BLUEPRINTS.get("workshop", {})
		var recipes: Dictionary = workshop_blueprint.get("recipes", {})
		var workshop_job_type: String = workshop_blueprint.get("job_type", "smith")

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
		var existing_workshop_jobs := job_mgr.get_jobs_for_building(b_id)
		if existing_workshop_jobs.is_empty():
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
					var r_job = job_mgr.create_job(workshop_job_type, access_cell, desc, b_id, r_duration, 1, true, r_id, ch_id)
					if r_job != null:
						r_job.id = "%s_job_%d" % [ch_id, i]

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
	if b_type == "farm":
		wp.level_multiplier = EconomyConfig.get_farm_multiplier(int(b_data.get("upgrade_level", 1)))

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

func _match_starter_workplace_id(b: Dictionary) -> String:
	return BuildingSystem.match_starter_workplace_id(b)

func _match_starter_dropoff_id(b: Dictionary) -> String:
	return BuildingSystem.match_starter_dropoff_id(b)

func _resolve_building_canonical_id(b: Dictionary) -> String:
	return BuildingSystem.resolve_building_canonical_id(b)

func sync_workplaces_after_load(saved_workplaces_data: Dictionary = {}) -> void:
	if workplace_mgr == null or job_mgr == null or world_data == null:
		return

	# Ensure every restored building has a normalized canonical ID
	for b in world_data.buildings:
		if str(b.get("id", "")).is_empty():
			b["id"] = BuildingSystem.resolve_building_canonical_id(b)

	# Determine which starter workplaces and dropoffs actually exist (and are not destroyed ruins) in restored buildings.
	# Demolished starter buildings are absent from world_data.buildings and must NOT survive via unconditional starter IDs.
	var valid_starter_workplaces: Array[String] = []
	var valid_starter_dropoffs: Dictionary = {}
	for b in world_data.buildings:
		if str(b.get("state", "active")) == "destroyed":
			continue
		var starter_wp_id: String = _match_starter_workplace_id(b)
		if starter_wp_id != "" and not starter_wp_id in valid_starter_workplaces:
			valid_starter_workplaces.append(starter_wp_id)
		var starter_dropoff_id: String = _match_starter_dropoff_id(b)
		if starter_dropoff_id != "":
			valid_starter_dropoffs[starter_dropoff_id] = true

	# 1. Clear dynamic workplaces/jobs and any demolished or destroyed starter records not present in restored buildings
	workplace_mgr.clear_dynamic_workplaces(valid_starter_workplaces)
	job_mgr.clear_dynamic_jobs(valid_starter_workplaces)

	# Reconcile starter dropoffs against restored world_data.buildings
	for dropoff_id in ["storehouse_starter", "townhall_starter"]:
		if not valid_starter_dropoffs.has(dropoff_id):
			workplace_mgr.unregister_dropoff(dropoff_id)
		elif workplace_mgr.has_method("has_dropoff") and not workplace_mgr.has_dropoff(dropoff_id):
			_register_starter_dropoff(dropoff_id)

	# Reconcile valid starter workplaces/jobs idempotently (supports loading a valid save into a reused WorldView)
	for sid in valid_starter_workplaces:
		if not workplace_mgr.has_workplace(sid):
			_register_starter_workplace(sid)
		if job_mgr.get_jobs_for_building(sid).is_empty():
			_create_starter_jobs(sid)

	# Reset all existing workplace buffers to 0 first (ensures legacy saves default to 0)
	# Also clear reconstructed pause reasons so repeated load synchronization is idempotent
	for wp in workplace_mgr.get_all_workplaces():
		wp.buffer_amount = 0
		workplace_mgr.set_workplace_pause_reason(wp.id, WorkplaceManager.PAUSE_REASON_PLAYER, false)
		workplace_mgr.set_workplace_pause_reason(wp.id, WorkplaceManager.PAUSE_REASON_DAMAGED, false)

	# 2. Re-register dynamic workplaces, barracks jobs, or construction jobs from world_data.buildings
	for b in world_data.buildings:
		var b_type: String = b.get("type", "")
		var b_state: String = b.get("state", "active")
		if b_state == "under_construction":
			register_construction_jobs(b)
		elif b_state == "destroyed":
			# MBL-BLD-05 / MBL-ECO-01: Destroyed ruins have no active workplace, dropoff, or jobs.
			# Ensure any starter or stale workplace record is unregistered and its buffer forfeited under Policy A.
			var b_id: String = _resolve_building_canonical_id(b)
			if b_id != "":
				if workplace_mgr != null:
					workplace_mgr.unregister_workplace(b_id)
					workplace_mgr.unregister_dropoff(b_id)
				if job_mgr != null:
					job_mgr.remove_jobs_for_building(b_id)
		elif b_type in ["farm", "woodcutter", "quarry", "mine", "workshop"]:
			var starter_wp_id: String = _match_starter_workplace_id(b)
			if starter_wp_id != "" and starter_wp_id in valid_starter_workplaces:
				if b_type == "farm" and workplace_mgr != null:
					var starter_farm = workplace_mgr.get_workplace("farm_starter")
					if starter_farm != null:
						starter_farm.level_multiplier = EconomyConfig.get_farm_multiplier(int(b.get("upgrade_level", 1)))
			else:
				register_dynamic_workplace(b)
		elif b_type == "barracks":
			if b_state == "active":
				register_barracks_jobs(b)

		# Re-register upgrade builder jobs if an upgrade was in progress
		if bool(b.get("is_upgrading", false)):
			register_upgrade_jobs(b)

		# Sync paused / damaged pause reasons to workplace manager and visual node
		if b_state == "paused":
			var paused_id: String = _resolve_building_canonical_id(b)
			if workplace_mgr != null and paused_id != "":
				workplace_mgr.set_workplace_pause_reason(paused_id, WorkplaceManager.PAUSE_REASON_PLAYER, true)
			var node_name := "Building_%s_%d_%d" % [b_type, b.get("cell", Vector2i.ZERO).x, b.get("cell", Vector2i.ZERO).y]
			var b_node = buildings_container.get_node_or_null(node_name) if buildings_container != null else null
			if b_node != null:
				for ch in b_node.get_children():
					if ch is Sprite2D:
						ch.modulate = Color(0.7, 0.7, 0.7, 0.85)
						break
		elif b_state == "damaged" or b_state == "repairing":
			var damaged_id: String = _resolve_building_canonical_id(b)
			if workplace_mgr != null and damaged_id != "":
				workplace_mgr.set_workplace_pause_reason(damaged_id, WorkplaceManager.PAUSE_REASON_DAMAGED, true)
				if str(b.get("pre_damage_state", "")) == "paused":
					workplace_mgr.set_workplace_pause_reason(damaged_id, WorkplaceManager.PAUSE_REASON_PLAYER, true)

	# Clear any dangling live citizen references if sync_workplaces_after_load is called directly with active citizens
	for cit in citizen_list:
		if not is_instance_valid(cit):
			continue
		var removed_target := false
		for sid in ["farm_starter", "woodcutter_starter"]:
			if not sid in valid_starter_workplaces:
				if cit.get("active_job") != null and JobManager.job_matches_building(cit.active_job, sid):
					cit.active_job = null
					removed_target = true
				var wp_ref := str(cit.get("workplace_id")) if cit.get("workplace_id") != null else ""
				if wp_ref == sid or wp_ref.begins_with(sid + "_"):
					cit.set("workplace_id", "")
					removed_target = true
		if removed_target and cit.get("current_state") != CitizenController.State.HAULING:
			cit.set("current_state", CitizenController.State.IDLE)

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
	bridge_start_bank = Vector2i(-1, -1)
	_bridge_preview_cells.clear()
	_last_bridge_preview = {}
	if ghost_building_node:
		ghost_building_node.visible = false
	if _bridge_preview_overlay:
		_bridge_preview_overlay.visible = false
	if hud != null and hud.has_method("show_bridge_placement_ui"):
		hud.call("show_bridge_placement_ui", false, bridge_width, {})
	_refresh_territory_overlay()
	var am = get_node_or_null("/root/AudioManager")
	if am:
		am.play_click()

func _get_terrain_name(type: int) -> String:
	match type:
		WorldGenerator.TerrainType.WATER: return "Mặt Nước (Không thể đi)"
		WorldGenerator.TerrainType.SAND: return "Bãi Cát"
		WorldGenerator.TerrainType.GRASS: return "Đồng Cỏ"
		WorldGenerator.TerrainType.DIRT: return "Đất Thổ"
		WorldGenerator.TerrainType.HILLS: return "Đồi (Di chuyển chậm, giàu Đá/Quặng)"
		WorldGenerator.TerrainType.MOUNTAINS: return "Núi Cao (Địa hình hiểm trở)"
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
		"cookhouse": return "Nhà Bếp (2x2)"
		"bridge": return "Cầu Vượt Sông"
		_: return ""

func _on_return_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _setup_fog_layer() -> void:
	var world_root := get_node_or_null("World")
	if world_root == null or world_data == null:
		return
	if fog_tile_layer != null and is_instance_valid(fog_tile_layer):
		if fog_tile_layer.get_parent() == world_root:
			world_root.remove_child(fog_tile_layer)
		fog_tile_layer.queue_free()
		fog_tile_layer = null
	if cloud_sea_base != null and is_instance_valid(cloud_sea_base):
		if cloud_sea_base.get_parent() == world_root:
			world_root.remove_child(cloud_sea_base)
		cloud_sea_base.queue_free()
		cloud_sea_base = null
	if fog_cloud_layer != null and is_instance_valid(fog_cloud_layer):
		if fog_cloud_layer.get_parent() == world_root:
			world_root.remove_child(fog_cloud_layer)
		fog_cloud_layer.queue_free()
		fog_cloud_layer = null

	var w: int = int(IsoMath.TILE_WIDTH)
	var h: int = int(IsoMath.TILE_HEIGHT)
	var half_w: float = float(w) * 0.5
	var half_h: float = float(h) * 0.5
	var img := Image.create(w * 16, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Build 16-tile cardinal-neighbor bitmask atlas (A2 Organic Pixel-Mist Fringe)
	# Bit 0 (1): TR (0,-1), Bit 1 (2): BR (1,0), Bit 2 (4): BL (0,1), Bit 3 (8): TL (-1,0)
	for mask in range(16):
		var x_off: int = mask * w
		for py in range(h):
			for px in range(w):
				var u: float = ((float(px) + 0.5) - half_w) / half_w
				var v: float = ((float(py) + 0.5) - half_h) / half_h
				var nx: float = absf(u)
				var ny: float = absf(v)
				if nx + ny > 1.08:
					continue
				if mask == 0:
					img.set_pixel(x_off + px, py, Color(1, 1, 1, 1))
					continue
				var min_d: float = 99.0
				if (mask & 1) != 0:
					min_d = minf(min_d, 1.0 - (u - v))
				if (mask & 2) != 0:
					min_d = minf(min_d, 1.0 - (u + v))
				if (mask & 4) != 0:
					min_d = minf(min_d, 1.0 - (-u + v))
				if (mask & 8) != 0:
					min_d = minf(min_d, 1.0 - (-u - v))
				var h_val: float = float(((px * 73856093) ^ (py * 19349663)) & 255) / 255.0
				var alpha: float = 1.0
				if min_d < 0.08:
					alpha = 0.0
				elif min_d < 0.24:
					alpha = 0.42 if h_val < 0.55 else 0.0
				elif min_d < 0.44:
					alpha = 0.78 if h_val < 0.80 else 0.45
				if alpha > 0.0:
					img.set_pixel(x_off + px, py, Color(1, 1, 1, alpha))
	var fog_tex := ImageTexture.create_from_image(img)

	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = Vector2i(w, h)
	var src := TileSetAtlasSource.new()
	src.texture = fog_tex
	src.texture_region_size = Vector2i(w, h)
	for mask in range(16):
		var coords := Vector2i(mask, 0)
		src.create_tile(coords)
		var td_unexplored := src.get_tile_data(coords, 0)
		if td_unexplored != null:
			td_unexplored.modulate = Color(0.04, 0.05, 0.08, 1.0)
	src.create_alternative_tile(Vector2i(0, 0), 1)
	var td_explored := src.get_tile_data(Vector2i(0, 0), 1)
	if td_explored != null:
		td_explored.modulate = Color(0.05, 0.07, 0.11, 0.56)
	ts.add_source(src, 0)

	fog_tile_layer = TileMapLayer.new()
	fog_tile_layer.name = "FogTileMapLayer"
	fog_tile_layer.z_index = 5
	fog_tile_layer.tile_set = ts
	fog_tile_layer.position = Vector2(-IsoMath.HALF_WIDTH, -IsoMath.HALF_HEIGHT)
	fog_tile_layer.visible = not debug_fog_disabled
	world_root.add_child(fog_tile_layer)

	fog_cloud_layer = FogCloudLayer.new()
	fog_cloud_layer.visible = true
	world_root.add_child(fog_cloud_layer)
	var cloud_seed: int = int(world_data.get("seed")) if world_data != null and world_data.get("seed") != null else world_seed
	fog_cloud_layer.configure(fog_of_war, cloud_seed, FogCloudLayer.DensityPreset.BALANCED)

	var mw_fog: int = fog_of_war.map_width if fog_of_war != null else IsoMath.get_active_map_width()
	var mh_fog: int = fog_of_war.map_height if fog_of_war != null else IsoMath.get_active_map_height()
	cloud_sea_base = _create_cloud_sea_base(mw_fog, mh_fog, fog_cloud_layer.get_fog_mask_texture())
	cloud_sea_base.visible = not use_cloud_sea_composite and fog_cloud_layer.is_cloud_enabled()
	world_root.add_child(cloud_sea_base)

	_setup_terrain_preview_renderer()
	_setup_cloud_sea_composite()
	_sync_full_fog_layer()
	_apply_fog_presentation_visibility()

func _exit_tree() -> void:
	if rival_presentation_controller != null and is_instance_valid(rival_presentation_controller) and rival_presentation_controller.has_method("dispose_all"):
		rival_presentation_controller.dispose_all()
	if settlement_simulation_manager != null and is_instance_valid(settlement_simulation_manager) and settlement_simulation_manager.has_method("disconnect_time_manager"):
		settlement_simulation_manager.disconnect_time_manager()
	cleanup_cloud_sea_composite()
	cleanup_terrain_preview_renderer()

func _setup_terrain_preview_renderer() -> void:
	var mw: int = fog_of_war.map_width if fog_of_war != null else IsoMath.get_active_map_width()
	var mh: int = fog_of_war.map_height if fog_of_war != null else IsoMath.get_active_map_height()
	var p_seed: int = int(world_data.get("seed")) if world_data != null and world_data.get("seed") != null else world_seed

	if terrain_preview_field == null:
		terrain_preview_field = TerrainPreviewFieldScript.new()
	terrain_preview_field.clear_sources()
	terrain_preview_field.configure(mw, mh, p_seed, 1, fog_of_war)

	if terrain_preview_renderer == null or not is_instance_valid(terrain_preview_renderer):
		terrain_preview_renderer = TerrainPreviewRendererScript.new()
		terrain_preview_renderer.name = "TerrainPreviewRenderer"
		add_child(terrain_preview_renderer)
	terrain_preview_renderer.configure(terrain_preview_field, 1)

func rebind_terrain_preview_fog(new_fog: FogOfWar = null) -> void:
	var target_fog: FogOfWar = new_fog if new_fog != null else fog_of_war
	if new_fog != null:
		fog_of_war = new_fog
	if terrain_preview_field != null:
		terrain_preview_field.set_fog_of_war(target_fog)
	if terrain_preview_renderer != null and is_instance_valid(terrain_preview_renderer):
		terrain_preview_renderer.sync_if_needed()
	sync_fog_state_texture_full(false)
	_refresh_cloud_sea_composite_bindings()

func cleanup_terrain_preview_renderer() -> void:
	if terrain_preview_renderer != null and is_instance_valid(terrain_preview_renderer):
		terrain_preview_renderer.cleanup()
		if terrain_preview_renderer.get_parent() == self:
			remove_child(terrain_preview_renderer)
		terrain_preview_renderer.queue_free()
	terrain_preview_renderer = null
	terrain_preview_field = null
	_gameplay_preview_ids.clear()
	_tracked_hunter_states.clear()

func _apply_fog_presentation_visibility() -> void:
	var show_composite: bool = use_cloud_sea_composite and not debug_fog_disabled
	var show_legacy: bool = not use_cloud_sea_composite and not debug_fog_disabled
	if cloud_sea_composite != null and is_instance_valid(cloud_sea_composite):
		cloud_sea_composite.visible = show_composite
	if fog_tile_layer != null and is_instance_valid(fog_tile_layer):
		fog_tile_layer.visible = show_legacy
	if fog_cloud_layer != null and is_instance_valid(fog_cloud_layer):
		fog_cloud_layer.visible = show_legacy and fog_cloud_layer.is_cloud_enabled()
	if cloud_sea_base != null and is_instance_valid(cloud_sea_base) and fog_cloud_layer != null and is_instance_valid(fog_cloud_layer):
		cloud_sea_base.visible = show_legacy and fog_cloud_layer.is_cloud_enabled()

func _refresh_cloud_sea_composite_bindings() -> void:
	if cloud_sea_composite == null or not is_instance_valid(cloud_sea_composite):
		return
	var mw: int = fog_of_war.map_width if fog_of_war != null else (int(world_data.map_width) if world_data != null else 128)
	var mh: int = fog_of_war.map_height if fog_of_war != null else (int(world_data.map_height) if world_data != null else 128)
	var p_seed: int = int(world_data.get("seed")) if world_data != null and world_data.get("seed") != null else world_seed
	_ensure_fog_transition_viewport(mw, mh)
	var c_mat := cloud_sea_composite.material as ShaderMaterial
	if c_mat != null:
		var env_tex: Texture2D = terrain_preview_renderer.get_envelope_texture() if (terrain_preview_renderer != null and is_instance_valid(terrain_preview_renderer)) else null
		c_mat.set_shader_parameter("envelope_tex", env_tex)
		c_mat.set_shader_parameter("fog_state_tex", _fog_state_tex)
		c_mat.set_shader_parameter("transition_tex", _fog_transition_viewport.get_texture() if (_fog_transition_viewport != null and is_instance_valid(_fog_transition_viewport)) else null)
		c_mat.set_shader_parameter("map_size", Vector2(float(mw), float(mh)))
		c_mat.set_shader_parameter("world_seed_f", float(p_seed))
	_apply_fog_presentation_visibility()

static func _screen_dir_to_vector(f_dir: int) -> Vector2:
	var angle: float = float(f_dir) * (PI * 0.25)
	return Vector2(cos(angle), sin(angle))

func _resolve_active_townhall_info() -> Dictionary:
	if world_data != null and world_data.get("buildings") != null and not world_data.buildings.is_empty():
		for b in world_data.buildings:
			if str(b.get("type", "")) == "townhall" and str(b.get("state", "active")) != "destroyed":
				var b_cell = b.get("cell")
				var th_cell: Vector2i = b_cell if b_cell is Vector2i else world_data.center_spawn
				var th_lvl: int = clampi(int(b.get("upgrade_level", 1)), 1, EconomyConfig.MAX_BUILDING_LEVEL)
				var th_rad: int = EconomyConfig.get_territory_radius(th_lvl)
				return {"cell": th_cell, "level": th_lvl, "radius": th_rad}
		return {}
	if world_data != null:
		return {
			"cell": world_data.center_spawn,
			"level": 1,
			"radius": EconomyConfig.get_territory_radius(1)
		}
	return {}

func _resolve_active_townhall_cell() -> Variant:
	var info := _resolve_active_townhall_info()
	if info.is_empty():
		return null
	return info.get("cell")

func sync_gameplay_terrain_preview_sources() -> void:
	return

func _sync_hunter_preview_sources_if_moved() -> void:
	if terrain_preview_field == null:
		return
	var hunter_changed := false
	var seen_hunters: Dictionary = {}
	for cit in citizen_list:
		if cit == null or not is_instance_valid(cit) or bool(cit.get("_death_processed")):
			continue
		if cit.get("health") != null and float(cit.get("health")) <= 0.0:
			continue
		if cit.get("can_scout_beyond_territory") != true:
			continue
		var cid: String = str(cit.get("citizen_id")) if cit.get("citizen_id") != null else str(cit.name)
		if cid.is_empty() or deceased_citizen_ids.has(cid):
			continue
		var c_cell = cit.get("current_cell")
		if not (c_cell is Vector2i):
			continue
		var f_dir: int = int(cit.get("facing_dir")) if cit.get("facing_dir") != null else 0
		seen_hunters[cid] = true
		var prev = _tracked_hunter_states.get(cid)
		if prev == null or prev["cell"] != c_cell or int(prev["dir"]) != f_dir:
			hunter_changed = true
			break
	if not hunter_changed and seen_hunters.size() != _tracked_hunter_states.size():
		hunter_changed = true
	if hunter_changed:
		sync_gameplay_terrain_preview_sources()

static func _load_composite_cloud_texture(res_path: String) -> Texture2D:
	if ResourceLoader.exists(res_path):
		var loaded := load(res_path) as Texture2D
		if loaded != null:
			return loaded
	var abs_path := ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(abs_path):
		var img := Image.load_from_file(abs_path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null

func _setup_cloud_sea_composite() -> void:
	var world_root := get_node_or_null("World")
	if world_root == null:
		return
	var mw: int = fog_of_war.map_width if fog_of_war != null else (int(world_data.map_width) if world_data != null else 128)
	var mh: int = fog_of_war.map_height if fog_of_war != null else (int(world_data.map_height) if world_data != null else 128)
	var p_seed: int = int(world_data.get("seed")) if world_data != null and world_data.get("seed") != null else world_seed

	if cloud_sea_composite == null or not is_instance_valid(cloud_sea_composite):
		var mat := ShaderMaterial.new()
		mat.shader = load(CLOUD_SEA_COMPOSITE_SHADER_PATH) as Shader
		cloud_sea_composite = Polygon2D.new()
		cloud_sea_composite.name = "CloudSeaComposite"
		cloud_sea_composite.z_index = 7
		cloud_sea_composite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		cloud_sea_composite.material = mat
		world_root.add_child(cloud_sea_composite)
	elif cloud_sea_composite.get_parent() != world_root:
		if cloud_sea_composite.get_parent() != null:
			cloud_sea_composite.get_parent().remove_child(cloud_sea_composite)
		world_root.add_child(cloud_sea_composite)

	var p0 := Vector2((-0.5 - (-0.5)) * IsoMath.HALF_WIDTH, (-0.5 + (-0.5)) * IsoMath.HALF_HEIGHT)
	var p1 := Vector2(((float(mw) - 0.5) - (-0.5)) * IsoMath.HALF_WIDTH, ((float(mw) - 0.5) + (-0.5)) * IsoMath.HALF_HEIGHT)
	var p2 := Vector2(((float(mw) - 0.5) - (float(mh) - 0.5)) * IsoMath.HALF_WIDTH, ((float(mw) - 0.5) + (float(mh) - 0.5)) * IsoMath.HALF_HEIGHT)
	var p3 := Vector2((-0.5 - (float(mh) - 0.5)) * IsoMath.HALF_WIDTH, (-0.5 + (float(mh) - 0.5)) * IsoMath.HALF_HEIGHT)
	cloud_sea_composite.polygon = PackedVector2Array([p0, p1, p2, p3])
	cloud_sea_composite.modulate = Color.WHITE
	cloud_sea_composite.visible = use_cloud_sea_composite and not debug_fog_disabled

	var c_mat := cloud_sea_composite.material as ShaderMaterial
	if c_mat != null:
		c_mat.set_shader_parameter("sea_tex", _load_composite_cloud_texture(CLOUD_SEA_COMPOSITE_SEA_TEX_PATH))
		c_mat.set_shader_parameter("bank_tex", _load_composite_cloud_texture(CLOUD_SEA_COMPOSITE_BANK_TEX_PATH))
		var env_tex: Texture2D = terrain_preview_renderer.get_envelope_texture() if (terrain_preview_renderer != null and is_instance_valid(terrain_preview_renderer)) else null
		c_mat.set_shader_parameter("envelope_tex", env_tex)
		_ensure_fog_transition_viewport(mw, mh)
		sync_fog_state_texture_full(false)
		c_mat.set_shader_parameter("fog_state_tex", _fog_state_tex)
		c_mat.set_shader_parameter("transition_tex", _fog_transition_viewport.get_texture() if (_fog_transition_viewport != null and is_instance_valid(_fog_transition_viewport)) else null)
		c_mat.set_shader_parameter("map_size", Vector2(float(mw), float(mh)))
		c_mat.set_shader_parameter("world_seed_f", float(p_seed))
		c_mat.set_shader_parameter("debug_mode", 0)

func _ensure_fog_transition_viewport(mw: int, mh: int) -> void:
	if _fog_transition_viewport == null or not is_instance_valid(_fog_transition_viewport):
		_fog_transition_viewport = SubViewport.new()
		_fog_transition_viewport.name = "FogTransitionViewport"
		_fog_transition_viewport.size = Vector2i(maxi(128, mw * 2), maxi(128, mh * 2))
		_fog_transition_viewport.transparent_bg = false
		_fog_transition_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_fog_transition_viewport.disable_3d = true
		_fog_transition_rect = ColorRect.new()
		_fog_transition_rect.size = Vector2(_fog_transition_viewport.size)
		var t_mat := ShaderMaterial.new()
		t_mat.shader = load(FOG_TRANSITION_COVERAGE_SHADER_PATH) as Shader
		_fog_transition_rect.material = t_mat
		_fog_transition_viewport.add_child(_fog_transition_rect)
		add_child(_fog_transition_viewport)
	else:
		var target_sz := Vector2i(maxi(128, mw * 2), maxi(128, mh * 2))
		if _fog_transition_viewport.size != target_sz:
			_fog_transition_viewport.size = target_sz
			if _fog_transition_rect != null and is_instance_valid(_fog_transition_rect):
				_fog_transition_rect.size = Vector2(target_sz)

func _schedule_fog_transition_update(mw: int, mh: int) -> void:
	if _fog_transition_viewport == null or not is_instance_valid(_fog_transition_viewport):
		return
	if _fog_transition_rect != null and is_instance_valid(_fog_transition_rect):
		var t_mat := _fog_transition_rect.material as ShaderMaterial
		if t_mat != null:
			t_mat.set_shader_parameter("fog_state_tex", _fog_state_tex)
			t_mat.set_shader_parameter("map_size", Vector2(float(mw), float(mh)))
	_fog_transition_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_fog_transition_update_count += 1

func get_fog_transition_texture() -> Texture2D:
	if _fog_transition_viewport != null and is_instance_valid(_fog_transition_viewport):
		return _fog_transition_viewport.get_texture()
	return null

func get_fog_transition_update_count() -> int:
	return _fog_transition_update_count

static func _encode_fog_state_byte(state: int) -> int:
	if state == FogOfWar.State.VISIBLE:
		return 255
	elif state == FogOfWar.State.EXPLORED:
		return 128
	return 0

func get_fog_state_texture() -> ImageTexture:
	return _fog_state_tex

func get_fog_state_upload_count() -> int:
	return _fog_state_upload_count

func get_fog_state_last_stats() -> Dictionary:
	return _fog_state_last_stats.duplicate()

func sync_fog_state_texture_full(force: bool = false) -> bool:
	if fog_of_war == null:
		return false
	var t0 := Time.get_ticks_usec()
	var mw: int = fog_of_war.map_width
	var mh: int = fog_of_war.map_height
	var total: int = mw * mh
	var new_bytes := PackedByteArray()
	new_bytes.resize(total)
	var grid: Array = fog_of_war._grid
	for x in range(mw):
		var col: Array = grid[x]
		for y in range(mh):
			new_bytes[y * mw + x] = _encode_fog_state_byte(int(col[y]))
	var gen_ms := float(Time.get_ticks_usec() - t0) / 1000.0

	var size_changed := (_fog_state_img == null or _fog_state_img.get_width() != mw or _fog_state_img.get_height() != mh)
	if not force and not size_changed and _fog_state_tex != null and _fog_state_bytes == new_bytes:
		return false

	_fog_state_bytes = new_bytes
	var t_up0 := Time.get_ticks_usec()
	if size_changed:
		_fog_state_img = Image.create_from_data(mw, mh, false, Image.FORMAT_R8, _fog_state_bytes)
		_fog_state_tex = ImageTexture.create_from_image(_fog_state_img)
	else:
		_fog_state_img.set_data(mw, mh, false, Image.FORMAT_R8, _fog_state_bytes)
		if _fog_state_tex == null:
			_fog_state_tex = ImageTexture.create_from_image(_fog_state_img)
		else:
			_fog_state_tex.update(_fog_state_img)
	var upload_ms := float(Time.get_ticks_usec() - t_up0) / 1000.0
	_fog_state_upload_count += 1
	_schedule_fog_transition_update(mw, mh)
	_schedule_fog_transition_update(mw, mh)

	if cloud_sea_composite != null and is_instance_valid(cloud_sea_composite):
		var c_mat := cloud_sea_composite.material as ShaderMaterial
		if c_mat != null:
			c_mat.set_shader_parameter("fog_state_tex", _fog_state_tex)
			if _fog_transition_viewport != null and is_instance_valid(_fog_transition_viewport):
				c_mat.set_shader_parameter("transition_tex", _fog_transition_viewport.get_texture())

	_fog_state_last_stats = {
		"mode": "full",
		"gen_ms": gen_ms,
		"upload_ms": upload_ms,
		"mem_bytes": total * 2,
		"upload_count": _fog_state_upload_count,
	}
	return true

func update_fog_state_texture_dirty_cells(dirty_cells: Array[Vector2i]) -> bool:
	if fog_of_war == null or dirty_cells.is_empty():
		return false
	var mw: int = fog_of_war.map_width
	var mh: int = fog_of_war.map_height
	if _fog_state_tex == null or _fog_state_img == null or _fog_state_img.get_width() != mw or _fog_state_img.get_height() != mh or _fog_state_bytes.size() != mw * mh:
		return sync_fog_state_texture_full(true)

	var t0 := Time.get_ticks_usec()
	var changed := false
	for cell in dirty_cells:
		if cell.x >= 0 and cell.y >= 0 and cell.x < mw and cell.y < mh:
			var idx := cell.y * mw + cell.x
			var encoded := _encode_fog_state_byte(fog_of_war.get_state(cell))
			if _fog_state_bytes[idx] != encoded:
				_fog_state_bytes[idx] = encoded
				changed = true
	var inc_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	if not changed:
		return false

	var t_up0 := Time.get_ticks_usec()
	_fog_state_img.set_data(mw, mh, false, Image.FORMAT_R8, _fog_state_bytes)
	_fog_state_tex.update(_fog_state_img)
	var upload_ms := float(Time.get_ticks_usec() - t_up0) / 1000.0
	_fog_state_upload_count += 1
	_schedule_fog_transition_update(mw, mh)

	_fog_state_last_stats = {
		"mode": "incremental",
		"inc_ms": inc_ms,
		"upload_ms": upload_ms,
		"dirty_count": dirty_cells.size(),
		"mem_bytes": mw * mh * 2,
		"upload_count": _fog_state_upload_count,
	}
	return true

func set_cloud_sea_composite_isolated_mode(enabled: bool) -> void:
	use_cloud_sea_composite = enabled
	if cloud_sea_composite != null and is_instance_valid(cloud_sea_composite):
		cloud_sea_composite.visible = enabled and not debug_fog_disabled
	if fog_tile_layer != null and is_instance_valid(fog_tile_layer):
		fog_tile_layer.visible = (not enabled) and (not debug_fog_disabled)
	if fog_cloud_layer != null and is_instance_valid(fog_cloud_layer):
		fog_cloud_layer.visible = (not enabled) and (not debug_fog_disabled) and fog_cloud_layer.is_cloud_enabled()
	if cloud_sea_base != null and is_instance_valid(cloud_sea_base) and fog_cloud_layer != null and is_instance_valid(fog_cloud_layer):
		cloud_sea_base.visible = (not enabled) and (not debug_fog_disabled) and fog_cloud_layer.is_cloud_enabled()

func cleanup_cloud_sea_composite() -> void:
	if cloud_sea_composite != null and is_instance_valid(cloud_sea_composite):
		if cloud_sea_composite.get_parent() != null:
			cloud_sea_composite.get_parent().remove_child(cloud_sea_composite)
		cloud_sea_composite.queue_free()
	cloud_sea_composite = null
	if _fog_transition_viewport != null and is_instance_valid(_fog_transition_viewport):
		if _fog_transition_viewport.get_parent() != null:
			_fog_transition_viewport.get_parent().remove_child(_fog_transition_viewport)
		_fog_transition_viewport.queue_free()
	_fog_transition_viewport = null
	_fog_transition_rect = null
	_fog_state_tex = null
	_fog_state_img = null
	_fog_state_bytes.clear()

static func _get_cloud_sea_shader() -> Shader:
	if _cloud_sea_shader != null:
		return _cloud_sea_shader
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;

uniform sampler2D base_tex : repeat_enable, filter_nearest;
uniform sampler2D wisp_tex : repeat_enable, filter_nearest;
uniform sampler2D fog_mask : repeat_disable, filter_linear;
uniform vec2 map_size = vec2(128.0, 128.0);
uniform float tex_scale = 512.0;
uniform float wisp_scale = 640.0;
uniform float use_wisp = 1.0;
uniform float base_alpha = 0.96;

varying vec2 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float bayer4(vec2 p) {
	int x = int(mod(floor(p.x), 4.0));
	int y = int(mod(floor(p.y), 4.0));
	int idx = x + y * 4;
	float m[16] = float[16](
		0.0/16.0, 8.0/16.0, 2.0/16.0, 10.0/16.0,
		12.0/16.0, 4.0/16.0, 14.0/16.0, 6.0/16.0,
		3.0/16.0, 11.0/16.0, 1.0/16.0, 9.0/16.0,
		15.0/16.0, 7.0/16.0, 13.0/16.0, 5.0/16.0
	);
	return m[idx];
}

void fragment() {
	float u_grid = (v_world_pos.x / 32.0) + (v_world_pos.y / 16.0);
	float v_grid = (v_world_pos.y / 16.0) - (v_world_pos.x / 32.0);
	vec2 mask_uv = (vec2(u_grid, v_grid) + 0.5) / map_size;
	if (mask_uv.x < 0.0 || mask_uv.x > 1.0 || mask_uv.y < 0.0 || mask_uv.y > 1.0) {
		discard;
	}
	float mask_val = texture(fog_mask, mask_uv).r;
	if (mask_val <= 0.02) {
		discard;
	}
	float dither = bayer4(floor(v_world_pos * 0.5));
	if (mask_val < 0.98 && mask_val <= dither) {
		discard;
	}
	vec4 col = texture(base_tex, v_world_pos / tex_scale);
	if (use_wisp > 0.5) {
		vec4 wcol = texture(wisp_tex, (v_world_pos / wisp_scale) + vec2(0.37, 0.19));
		col.rgb = mix(col.rgb, wcol.rgb, wcol.a * 0.85);
	}
	COLOR = vec4(col.rgb, col.a * base_alpha);
}
"""
	_cloud_sea_shader = sh
	return _cloud_sea_shader

func _create_cloud_sea_base(mw: int, mh: int, mask_tex: Texture2D) -> Polygon2D:
	var mat := ShaderMaterial.new()
	mat.shader = _get_cloud_sea_shader()
	mat.set_shader_parameter("base_tex", load(CLOUD_SEA_BASE_TEX_PATH) as Texture2D)
	mat.set_shader_parameter("wisp_tex", load(CLOUD_SEA_WISP_TEX_PATH) as Texture2D)
	mat.set_shader_parameter("fog_mask", mask_tex)
	mat.set_shader_parameter("map_size", Vector2(float(mw), float(mh)))
	mat.set_shader_parameter("tex_scale", 512.0)
	mat.set_shader_parameter("wisp_scale", 640.0)
	mat.set_shader_parameter("use_wisp", 1.0)
	mat.set_shader_parameter("base_alpha", 0.96)

	var poly := Polygon2D.new()
	poly.name = "CloudSeaBase"
	poly.z_index = 6
	poly.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	poly.material = mat
	var p0 := Vector2((-0.5 - (-0.5)) * IsoMath.HALF_WIDTH, (-0.5 + (-0.5)) * IsoMath.HALF_HEIGHT)
	var p1 := Vector2(((float(mw) - 0.5) - (-0.5)) * IsoMath.HALF_WIDTH, ((float(mw) - 0.5) + (-0.5)) * IsoMath.HALF_HEIGHT)
	var p2 := Vector2(((float(mw) - 0.5) - (float(mh) - 0.5)) * IsoMath.HALF_WIDTH, ((float(mw) - 0.5) + (float(mh) - 0.5)) * IsoMath.HALF_HEIGHT)
	var p3 := Vector2((-0.5 - (float(mh) - 0.5)) * IsoMath.HALF_WIDTH, (-0.5 + (float(mh) - 0.5)) * IsoMath.HALF_HEIGHT)
	poly.polygon = PackedVector2Array([p0, p1, p2, p3])
	return poly

func _compute_unexplored_fog_mask(cell: Vector2i) -> int:
	if fog_of_war == null:
		return 0
	var mask: int = 0
	if fog_of_war.is_explored(cell + Vector2i(0, -1)):
		mask |= 1
	if fog_of_war.is_explored(cell + Vector2i(1, 0)):
		mask |= 2
	if fog_of_war.is_explored(cell + Vector2i(0, 1)):
		mask |= 4
	if fog_of_war.is_explored(cell + Vector2i(-1, 0)):
		mask |= 8
	return mask

func _sync_fog_cell(cell: Vector2i) -> void:
	if fog_tile_layer == null or not is_instance_valid(fog_tile_layer) or fog_of_war == null:
		return
	var st: int = fog_of_war.get_state(cell)
	if st == FogOfWar.State.VISIBLE:
		fog_tile_layer.erase_cell(cell)
	elif st == FogOfWar.State.EXPLORED:
		fog_tile_layer.set_cell(cell, 0, Vector2i(0, 0), 1)
	else:
		var mask: int = _compute_unexplored_fog_mask(cell)
		fog_tile_layer.set_cell(cell, 0, Vector2i(mask, 0), 0)

func _sync_full_fog_layer() -> void:
	if fog_tile_layer == null or not is_instance_valid(fog_tile_layer) or fog_of_war == null:
		return
	fog_tile_layer.clear()
	for x in range(fog_of_war.map_width):
		for y in range(fog_of_war.map_height):
			_sync_fog_cell(Vector2i(x, y))
	if fog_cloud_layer != null and is_instance_valid(fog_cloud_layer):
		fog_cloud_layer.sync_full()
		if cloud_sea_base != null and is_instance_valid(cloud_sea_base):
			var mat := cloud_sea_base.material as ShaderMaterial
			if mat != null:
				mat.set_shader_parameter("fog_mask", fog_cloud_layer.get_fog_mask_texture())
	sync_fog_state_texture_full(false)

func _sync_full_fog_and_minimap() -> void:
	if fog_of_war != null:
		fog_of_war.rebuild_visible_cache()
	_sync_full_fog_layer()
	rebind_terrain_preview_fog(fog_of_war)
	sync_gameplay_terrain_preview_sources()
	_apply_fog_presentation_visibility()
	for cell in prop_nodes_by_cell.keys():
		var p_node: Node = prop_nodes_by_cell[cell]
		if is_instance_valid(p_node):
			p_node.visible = debug_fog_disabled or (fog_of_war != null and fog_of_war.is_explored(cell))
	refresh_poi_visibility()
	_refresh_rival_settlement_visibility()
	_refresh_dynamic_actor_visibility()
	if hud != null and hud.has_method("initialize_minimap"):
		hud.initialize_minimap(self)
	if hud != null:
		if hud.has_method("close_entity_inspector"):
			hud.call("close_entity_inspector")
		if hud.has_method("hide_entity_hover_tooltip"):
			hud.call("hide_entity_hover_tooltip")
	if hud != null and hud.has_method("set_minimap_debug_fog_disabled"):
		hud.call("set_minimap_debug_fog_disabled", debug_fog_disabled)

func register_debug_inspect_provider(provider: Callable) -> void:
	if provider.is_valid() and not _debug_inspect_providers.has(provider):
		_debug_inspect_providers.append(provider)

func should_debug_reveal_category(category: String) -> bool:
	# Enemy military units remain strictly governed by real FogOfWar visibility.
	if category == "enemy_military":
		return false
	return debug_fog_disabled and OS.is_debug_build()

func inspect_cell_in_debug_mode(cell: Vector2i) -> Dictionary:
	if not debug_fog_disabled or not OS.is_debug_build():
		return {}
	# 1. Extensible category providers (e.g., future wildlife / monsters)
	for provider in _debug_inspect_providers:
		if provider.is_valid():
			var provided = provider.call(cell)
			if provided is Dictionary and not provided.is_empty():
				if str(provided.get("category", "")) != "enemy_military":
					provided["is_debug_inspect"] = true
					return provided
	# 2. Natural Resource Nodes
	if natural_resource_mgr != null:
		var res_node: Dictionary = natural_resource_mgr.get_node_at_cell(cell)
		if not res_node.is_empty():
			var r_type: String = str(res_node.get("type", ""))
			var r_id: String = str(res_node.get("id", ""))
			var r_cell: Vector2i = res_node.get("cell", cell)
			var r_res: String = str(res_node.get("resource", ""))
			var r_rem: int = int(res_node.get("remaining_qty", 0))
			var r_max: int = int(res_node.get("max_qty", 0))
			var spec: Dictionary = EconomyConfig.get_natural_resource_spec(r_type)
			var label: String = str(spec.get("name_vi", r_type.capitalize()))
			var is_dep: bool = bool(res_node.get("depleted", false)) or r_rem <= 0
			return {
				"is_debug_inspect": true,
				"category": "natural_resource",
				"id": "debug_res_%s" % r_id,
				"node_id": r_id,
				"type": r_type,
				"label": label,
				"cell": r_cell,
				"size": Vector2i(1, 1),
				"resource": r_res,
				"remaining_qty": r_rem,
				"max_qty": r_max,
				"depleted": is_dep,
				"title": "%s [Debug]" % label,
				"coords_text": "Tọa độ: (%d, %d) | Loại: %s | Yield: %s" % [r_cell.x, r_cell.y, r_type, r_res],
				"state_text": "[CẠN KIỆT - DEBUG]" if is_dep else "[TÀI NGUYÊN - DEBUG]",
				"state_color": Color(0.85, 0.35, 0.35, 1) if is_dep else Color(0.35, 0.85, 0.95, 1),
				"detail_text": "Sản lượng còn lại: %d / %d %s" % [r_rem, r_max, r_res],
				"show_bar": true,
				"bar_max": maxi(1, r_max),
				"bar_value": r_rem,
			}
	# 3. Static POIs (informational only; never discovers or claims)
	if poi_mgr != null and poi_mgr.has_method("get_all_pois"):
		for poi in poi_mgr.get_all_pois():
			if poi != null and poi.cell == cell:
				var poi_label: String = str(poi.get("name") if poi.get("name") != null else poi.get("type")).capitalize()
				return {
					"is_debug_inspect": true,
					"category": "poi",
					"id": "debug_poi_%s" % str(poi.id),
					"poi_id": str(poi.id),
					"type": str(poi.type),
					"label": poi_label,
					"cell": cell,
					"size": Vector2i(1, 1),
					"title": "POI: %s [Debug]" % poi_label,
					"coords_text": "Tọa độ: (%d, %d) | Loại: %s" % [cell.x, cell.y, str(poi.type)],
					"state_text": "[ĐIỂM ĐỊA DANH - DEBUG]",
					"state_color": Color(0.95, 0.72, 0.22, 1),
					"detail_text": "Thông tin địa danh (chỉ xem, không kích hoạt khám phá).",
					"show_bar": false,
				}
	# 4. Static Props (tree / rock)
	var prop_type: String = ""
	var prop_node: Node = prop_nodes_by_cell.get(cell)
	if prop_node != null and is_instance_valid(prop_node):
		prop_type = str(prop_node.get_meta("prop_type", ""))
	elif world_data != null:
		for p in world_data.props:
			if p.get("cell") == cell:
				prop_type = str(p.get("type", ""))
				break
	if prop_type != "":
		var label: String = "Cây (Tree)" if prop_type == "tree" else ("Đá (Rock)" if prop_type == "rock" else prop_type.capitalize())
		return {
			"is_debug_inspect": true,
			"category": "prop",
			"id": "debug_prop_%d_%d" % [cell.x, cell.y],
			"type": prop_type,
			"label": label,
			"cell": cell,
			"size": Vector2i(1, 1),
			"title": "%s [Debug]" % label,
			"coords_text": "Tọa độ: (%d, %d) | Loại: %s" % [cell.x, cell.y, prop_type],
			"state_text": "[VẬT THỂ TỰ NHIÊN - DEBUG]",
			"state_color": Color(0.65, 0.85, 0.55, 1),
			"detail_text": "Chỉ xem thông tin (Debug Mode — không tạo job/khai thác).",
			"show_bar": false,
		}
	return {}

func set_debug_fog_disabled(disabled: bool) -> void:
	if not OS.is_debug_build():
		disabled = false
	debug_fog_disabled = disabled
	_apply_fog_presentation_visibility()
	for cell in prop_nodes_by_cell.keys():
		var p_node: Node = prop_nodes_by_cell[cell]
		if is_instance_valid(p_node):
			p_node.visible = debug_fog_disabled or (fog_of_war != null and fog_of_war.is_explored(cell))
	refresh_poi_visibility()
	_refresh_rival_settlement_visibility()
	_refresh_dynamic_actor_visibility()
	if not debug_fog_disabled and selected_building_id.begins_with("debug_"):
		clear_building_selection()
	if hud != null:
		if hud.has_method("refresh_entity_inspector"):
			hud.call("refresh_entity_inspector")
		if hud.has_method("hide_entity_hover_tooltip"):
			hud.call("hide_entity_hover_tooltip")
	if hud != null and hud.has_method("set_minimap_debug_fog_disabled"):
		hud.call("set_minimap_debug_fog_disabled", debug_fog_disabled)

func is_debug_fog_disabled() -> bool:
	return debug_fog_disabled

func _update_fog_visuals(dirty_cells: Array[Vector2i]) -> void:
	if not use_cloud_sea_composite:
		if fog_tile_layer != null and is_instance_valid(fog_tile_layer) and fog_of_war != null and not dirty_cells.is_empty():
			var cells_to_refresh: Dictionary = {}
			var dirs: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
			var mw: int = fog_of_war.map_width
			var mh: int = fog_of_war.map_height
			for cell in dirty_cells:
				if cell.x >= 0 and cell.y >= 0 and cell.x < mw and cell.y < mh:
					cells_to_refresh[cell] = true
				for d in dirs:
					var nb := cell + d
					if nb.x >= 0 and nb.y >= 0 and nb.x < mw and nb.y < mh:
						cells_to_refresh[nb] = true
			for refresh_cell in cells_to_refresh.keys():
				_sync_fog_cell(refresh_cell)
		if fog_cloud_layer != null and is_instance_valid(fog_cloud_layer) and not dirty_cells.is_empty():
			fog_cloud_layer.update_dirty_cells(dirty_cells)
	if not dirty_cells.is_empty():
		update_fog_state_texture_dirty_cells(dirty_cells)
	for cell in dirty_cells:
		var p_node = prop_nodes_by_cell.get(cell)
		if p_node != null and is_instance_valid(p_node):
			p_node.visible = debug_fog_disabled or (fog_of_war != null and fog_of_war.is_explored(cell))
	if not dirty_cells.is_empty() and wildlife_mgr != null:
		wildlife_mgr.invalidate_hunter_range_cache()
	_refresh_rival_settlement_visibility()
	_refresh_dynamic_actor_visibility()
	if hud != null:
		if not dirty_cells.is_empty() and hud.has_method("update_minimap_cells"):
			hud.update_minimap_cells(dirty_cells)
		elif hud.has_method("refresh_minimap_markers"):
			hud.refresh_minimap_markers()

func _refresh_dynamic_actor_visibility() -> void:
	if fog_of_war == null:
		return
	if enemy_military_mgr != null and enemy_military_mgr.has_method("get_all_enemies"):
		for e in enemy_military_mgr.get_all_enemies():
			if e != null and is_instance_valid(e):
				var ec = e.get("current_cell")
				if ec is Vector2i:
					e.visible = fog_of_war.is_visible(ec)
	if field_siege_mgr != null and field_siege_mgr.has_method("get_all_objectives"):
		for obj in field_siege_mgr.get_all_objectives():
			if obj != null and is_instance_valid(obj):
				var oc = obj.get("current_cell")
				if oc is Vector2i:
					obj.visible = debug_fog_disabled or fog_of_war.is_explored(oc)
	if wildlife_mgr != null:
		wildlife_mgr.refresh_visibility(fog_of_war, debug_fog_disabled)
	if monster_mgr != null:
		monster_mgr.refresh_visibility(fog_of_war, debug_fog_disabled)
	if rival_presentation_controller != null and is_instance_valid(rival_presentation_controller):
		rival_presentation_controller.debug_fog_disabled = debug_fog_disabled
		rival_presentation_controller.fog_of_war = fog_of_war
		rival_presentation_controller.update_presentation(0.0, 0.0)

func refresh_world_vision() -> void:
	if fog_of_war == null:
		return

	# 1. Town Hall owned territory (authoritative permanent current visibility)
	var owned_cells: Array[Vector2i] = []
	if territory_mgr != null and territory_mgr.has_method("get_owned_cells"):
		for oc in territory_mgr.get_owned_cells():
			owned_cells.append(oc)

	var observer_specs: Array = []

	# 2. Core Town Hall local vision (when Town Hall is active or buildings empty in unit fixtures)
	if world_data == null or world_data.get("buildings") == null or world_data.buildings.is_empty() or BuildingSystem.is_town_hall_active(world_data):
		var vision_center: Vector2i = world_data.center_spawn if world_data != null else Vector2i(32, 32)
		observer_specs.append({"cell": vision_center, "radius": FogOfWar.TOWN_HALL_VISION_RADIUS})

	# 3. Specialized scouting citizens ONLY (ordinary citizens do not scout beyond owned territory)
	for cit in citizen_list:
		if cit != null and is_instance_valid(cit) and cit.get("can_scout_beyond_territory") == true:
			var c_cell = cit.get("current_cell")
			if c_cell is Vector2i:
				var c_rad: int = int(cit.get("vision_radius")) if cit.get("vision_radius") != null else FogOfWar.CITIZEN_VISION_RADIUS
				observer_specs.append({"cell": c_cell, "radius": c_rad})

	# 4. Active watchtowers vision
	if world_data != null and world_data.get("buildings") != null:
		for b in world_data.buildings:
			if b.get("type") == "watchtower" and b.get("state", "active") == "active":
				var b_cell: Vector2i = b.get("cell", Vector2i.ZERO)
				var bp: Dictionary = EconomyConfig.BLUEPRINTS.get("watchtower", {})
				var v_rad: int = bp.get("vision_radius", FogOfWar.WATCHTOWER_VISION_RADIUS)
				observer_specs.append({"cell": b_cell, "radius": v_rad})

	# 5. Living player tactical units / strategic army vision
	var tactical_units_observed := false
	if tactical_military_mgr != null and tactical_military_mgr.has_method("get_all_units"):
		var t_units = tactical_military_mgr.get_all_units()
		if not t_units.is_empty():
			tactical_units_observed = true
			for u in t_units:
				if u != null and is_instance_valid(u) and bool(u.get("is_alive")):
					var u_cell = u.get("current_cell")
					if u_cell is Vector2i:
						observer_specs.append({"cell": u_cell, "radius": FogOfWar.ARMY_UNIT_VISION_RADIUS})
	if not tactical_units_observed and player_army_mgr != null:
		var s_count: int = int(player_army_mgr.get("soldier_count")) if player_army_mgr.get("soldier_count") != null else 0
		if s_count > 0:
			var a_cell = player_army_mgr.get("current_cell")
			if a_cell is Vector2i:
				observer_specs.append({"cell": a_cell, "radius": FogOfWar.ARMY_UNIT_VISION_RADIUS})

	# 6. Active player-owned territorial outposts vision (Package 3B: Manhattan radius 6)
	if field_siege_mgr != null and field_siege_mgr.has_method("get_all_objectives"):
		for obj in field_siege_mgr.get_all_objectives():
			if obj != null and is_instance_valid(obj):
				var is_player: bool = (str(obj.get("owning_faction_id")) == "player")
				var is_alive: bool = bool(obj.get("is_alive")) if obj.get("is_alive") != null else true
				var hp: float = float(obj.get("health")) if obj.get("health") != null else 0.0
				if is_player and is_alive and hp > 0.0:
					var o_cell = obj.get("current_cell")
					if o_cell is Vector2i:
						var r: int = int(obj.get("vision_radius")) if obj.get("vision_radius") != null else FogOfWar.OUTPOST_VISION_RADIUS
						observer_specs.append({"cell": o_cell, "radius": r})

	var dirty_cells: Array[Vector2i] = fog_of_war.recompute_vision(owned_cells, observer_specs)
	_update_fog_visuals(dirty_cells)

	# Discover any newly visible POIs
	if poi_mgr != null and fog_of_war != null:
		poi_mgr.update_discovery(fog_of_war, monster_mgr, nav)
	if monster_mgr != null:
		monster_mgr.refresh_visibility(fog_of_war, debug_fog_disabled)
	if rival_presentation_controller != null and is_instance_valid(rival_presentation_controller):
		rival_presentation_controller.debug_fog_disabled = debug_fog_disabled
		rival_presentation_controller.fog_of_war = fog_of_war
		rival_presentation_controller.update_presentation(0.0, 0.0)

	# Package 3C: Refresh dynamic route risk for active trade caravan
	if active_caravan != null and bool(active_caravan.get("is_active")):
		refresh_caravan_route_risk()

func _on_territory_changed(_new_level: int, _owned_count: int, _revision: int) -> void:
	refresh_world_vision()
	var houses_to_check: Dictionary = {}
	for hid in house_indoor_occupants.keys():
		if str(hid) != "":
			houses_to_check[str(hid)] = true
	for cit in citizen_list:
		if is_instance_valid(cit):
			var h_bid: String = str(cit.get("home_building_id")) if cit.get("home_building_id") != null else ""
			var r_hid: String = str(cit.get("rest_house_id")) if cit.get("rest_house_id") != null else ""
			if h_bid != "":
				houses_to_check[h_bid] = true
			if r_hid != "":
				houses_to_check[r_hid] = true
	if world_data != null:
		for b in world_data.buildings:
			if str(b.get("type", "")) == "house":
				var bid: String = str(b.get("id", ""))
				if bid != "":
					houses_to_check[bid] = true
	for hid in houses_to_check.keys():
		if not is_house_active_and_owned(hid):
			_evict_house_occupants(hid, "Nhà ở nằm ngoài lãnh thổ")

func _on_tactical_unit_moved(_unit_id: String, _new_cell: Vector2i) -> void:
	refresh_world_vision()
	sync_gameplay_terrain_preview_sources()

func _on_tactical_unit_spawned(_unit_id: String, _cell: Vector2i) -> void:
	refresh_world_vision()
	sync_gameplay_terrain_preview_sources()

func _on_tactical_unit_despawned(_unit_id: String) -> void:
	refresh_world_vision()
	sync_gameplay_terrain_preview_sources()

func _on_player_army_moved(_new_cell: Vector2i) -> void:
	refresh_world_vision()

const DAY_NIGHT_KEYFRAMES: Array = [
	[0.0, Color(0.52, 0.60, 0.84, 1.0)],
	[4.5, Color(0.52, 0.60, 0.84, 1.0)],
	[5.0, Color(0.84, 0.68, 0.64, 1.0)],
	[5.5, Color(0.95, 0.76, 0.62, 1.0)],
	[6.5, Color(0.99, 0.91, 0.82, 1.0)],
	[7.0, Color(1.0, 0.99, 0.97, 1.0)],
	[12.0, Color(1.0, 1.0, 1.0, 1.0)],
	[17.5, Color(1.0, 0.98, 0.94, 1.0)],
	[18.0, Color(0.98, 0.80, 0.64, 1.0)],
	[18.5, Color(0.95, 0.66, 0.48, 1.0)],
	[19.3, Color(0.76, 0.60, 0.66, 1.0)],
	[20.0, Color(0.52, 0.60, 0.84, 1.0)],
	[24.0, Color(0.52, 0.60, 0.84, 1.0)]
]

func get_ambient_color_for_time(continuous_hour: float) -> Color:
	var h: float = fposmod(continuous_hour, 24.0)
	for i in range(DAY_NIGHT_KEYFRAMES.size() - 1):
		var h0: float = float(DAY_NIGHT_KEYFRAMES[i][0])
		var h1: float = float(DAY_NIGHT_KEYFRAMES[i + 1][0])
		if h >= h0 and h <= h1:
			var span: float = maxf(0.0001, h1 - h0)
			var t: float = clampf((h - h0) / span, 0.0, 1.0)
			var c0: Color = DAY_NIGHT_KEYFRAMES[i][1]
			var c1: Color = DAY_NIGHT_KEYFRAMES[i + 1][1]
			return c0.lerp(c1, t)
	return Color(1.0, 1.0, 1.0, 1.0)

func sync_day_night_visuals() -> void:
	var mod: CanvasModulate = get_node_or_null("World/DayNightModulate") as CanvasModulate
	if mod == null:
		return
	var tm = get_node_or_null("/root/TimeManager")
	if tm == null:
		return
	var cont_h: float = float(tm.call("get_continuous_hour")) if tm.has_method("get_continuous_hour") else float(tm.get("current_hour"))
	mod.color = get_ambient_color_for_time(cont_h)
	if fog_cloud_layer != null and is_instance_valid(fog_cloud_layer):
		fog_cloud_layer.apply_day_night_tint(cont_h)

func set_cloud_overlay_enabled(enabled: bool) -> void:
	if fog_cloud_layer != null and is_instance_valid(fog_cloud_layer):
		fog_cloud_layer.set_cloud_enabled(enabled)
		fog_cloud_layer.visible = enabled and not debug_fog_disabled
	if cloud_sea_base != null and is_instance_valid(cloud_sea_base):
		cloud_sea_base.visible = enabled and not debug_fog_disabled

func set_cloud_density_preset(preset: int) -> void:
	if fog_cloud_layer != null and is_instance_valid(fog_cloud_layer):
		fog_cloud_layer.set_density_preset(preset)

func _on_day_phase_changed(_new_phase: int, _old_phase: int) -> void:
	sync_day_night_visuals()

func _on_simulation_hour_passed(hour: int, day: int) -> void:
	var rm = _get_resource_mgr()

	# Attempt recovery of any pending death cargo if central storage has available space
	if not pending_death_cargo.is_empty():
		flush_pending_death_cargo()

	# Progress active research project
	if research_mgr != null:
		research_mgr.progress_research(1.0, rm)

	# Package 3A: Progress outpost reinforcements
	if player_army_mgr != null and player_army_mgr.has_method("advance_reinforcements"):
		player_army_mgr.call("advance_reinforcements", 1.0)
		
	# Update citizen/building/unit vision and fog of war
	refresh_world_vision()

	# Update POI discovery & guard status (NO automatic citizen claiming in Phase 9)
	if poi_mgr != null and fog_of_war != null:
		poi_mgr.update_discovery(fog_of_war, monster_mgr, nav)
		poi_mgr.refresh_guard_states(monster_mgr, nav)
						
	if workplace_mgr != null and job_mgr != null:
		workplace_mgr.update_hauling_jobs(job_mgr)
		if automation_mgr != null:
			var tm = get_node_or_null("/root/TimeManager")
			var season: String = tm.get_season_name() if tm else "spring"
			var paused: bool = (tm != null and tm.has_method("is_paused") and tm.is_paused())
			var cur_d: int = tm.current_day if tm else 1
			var cur_h: int = tm.current_hour if tm else 0
			automation_mgr.evaluate_rules(rm, job_mgr, workplace_mgr, season, citizen_list, world_data, paused, cur_d, cur_h)

	# Pre-crisis snapshot for HUD & hourly immigration evaluation
	var pre_crisis_snapshot: Dictionary = _collect_kingdom_snapshot()

	if hud:
		hud.update_population_display(pre_crisis_snapshot["pop"], pre_crisis_snapshot["housing_cap"])

	if immigration_mgr != null and immigration_mgr.can_evaluate_today(day, hour):
		var stability_est := 75.0
		if victory_mgr != null:
			stability_est = victory_mgr.calculate_stability(
				pre_crisis_snapshot["food"],
				pre_crisis_snapshot["gold"],
				pre_crisis_snapshot["pop"],
				pre_crisis_snapshot["housing_cap"],
				pre_crisis_snapshot["avg_morale"],
				pre_crisis_snapshot["town_hall_alive"]
			)
		var imm_res: Dictionary = immigration_mgr.evaluate_immigration(
			pre_crisis_snapshot["housing_cap"],
			pre_crisis_snapshot["pop"],
			pre_crisis_snapshot["food"],
			stability_est,
			pre_crisis_snapshot["avg_morale"],
			day
		)
		if imm_res["allowed"] and not imm_res["immigrants"].is_empty():
			_spawn_immigrant_wave(imm_res["immigrants"])

	# MBL-CRS-03: Process hourly crisis update FIRST, then recompute post-crisis state for VictoryManager
	if crisis_mgr != null:
		var tm_node = get_node_or_null("/root/TimeManager")
		var season_name: String = tm_node.get_season_name() if tm_node else "spring"
		crisis_mgr.tick_hourly(hour, day, season_name, world_data, rm, citizen_list, player_army_mgr, field_siege_mgr, hud)

	if victory_mgr != null:
		var post_crisis_snapshot: Dictionary = _collect_kingdom_snapshot()
		var stability: float = victory_mgr.calculate_stability(
			post_crisis_snapshot["food"],
			post_crisis_snapshot["gold"],
			post_crisis_snapshot["pop"],
			post_crisis_snapshot["housing_cap"],
			post_crisis_snapshot["avg_morale"],
			post_crisis_snapshot["town_hall_alive"]
		)
		var is_cr_active: bool = (crisis_mgr != null and crisis_mgr.is_crisis_active())
		var cr_name: String = crisis_mgr.get_crisis_display_name() if crisis_mgr else ""
		victory_mgr.tick_hourly(
			post_crisis_snapshot["pop"],
			post_crisis_snapshot["food"],
			post_crisis_snapshot["gold"],
			stability,
			post_crisis_snapshot["avg_morale"],
			post_crisis_snapshot["techs_count"],
			post_crisis_snapshot["town_hall_alive"],
			post_crisis_snapshot["buildings_count"],
			is_cr_active,
			cr_name
		)

func _collect_kingdom_snapshot() -> Dictionary:
	var rm = _get_resource_mgr()
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

	return {
		"housing_cap": housing_cap,
		"town_hall_alive": town_hall_alive,
		"pop": current_pop,
		"food": food_stock,
		"gold": gold_stock,
		"techs_count": techs_count,
		"buildings_count": buildings_count,
		"avg_morale": avg_morale
	}

func _on_simulation_day_passed(day: int, _season: String, _year: int) -> void:
	var rm = _get_resource_mgr()
	var em = get_node_or_null("/root/EventManager")
	var tm = get_node_or_null("/root/TimeManager")

	if not pending_death_cargo.is_empty():
		flush_pending_death_cargo()

	if crisis_mgr != null:
		var s_idx: int = tm.season_index if tm else 0
		var s_name: String = tm.get_season_name() if tm else "spring"
		var cur_gold: int = rm.get_available_stock("gold") if rm else 0
		crisis_mgr.process_day(day, s_name, s_idx, world_data, rm, citizen_list.size(), cur_gold)

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

	# Daily Autosave (BUG-003: Isolated to AUTOSAVE_PATH)
	if autosave_enabled and (day % autosave_interval_days == 0):
		var asave_res := SaveManager.save_to_file(self, SaveManager.get_autosave_path())
		if asave_res.get("success", false) and em != null:
			em.trigger_event("autosave", "Tự Động Lưu", "Đã tự động lưu thế giới an toàn (Ngày %d)." % day, true, {})

# -----------------------------------------------------------------------------
# Package 3A: Outpost Garrisoning API
# -----------------------------------------------------------------------------

func station_outpost_garrison(outpost_id: String, count: int = 1) -> Dictionary:
	if player_army_mgr != null and player_army_mgr.has_method("station_soldier"):
		return player_army_mgr.call("station_soldier", outpost_id, count)
	return {"success": false, "reason": "PlayerArmyManager không khả dụng"}

func recall_outpost_garrison(outpost_id: String, count: int = 1) -> Dictionary:
	if player_army_mgr != null and player_army_mgr.has_method("recall_soldier"):
		return player_army_mgr.call("recall_soldier", outpost_id, count)
	return {"success": false, "reason": "PlayerArmyManager không khả dụng"}

func dispatch_reinforcements_to_outpost(outpost_id: String, count: int = 1, travel_hours: float = -1.0) -> Dictionary:
	if player_army_mgr != null and player_army_mgr.has_method("dispatch_reinforcements"):
		return player_army_mgr.call("dispatch_reinforcements", outpost_id, count, travel_hours)
	return {"success": false, "reason": "PlayerArmyManager không khả dụng"}

func get_outpost_garrison_data(outpost_id: String) -> Dictionary:
	if player_army_mgr != null and player_army_mgr.has_method("get_garrison"):
		return player_army_mgr.call("get_garrison", outpost_id)
	return {}

# -----------------------------------------------------------------------------
# Phase 9: POI Inspector & Military Claim API
# -----------------------------------------------------------------------------

func _build_poi_inspector_data(poi: POIManager.POIData) -> Dictionary:
	var guarded: bool = poi_mgr.is_poi_guarded(poi, monster_mgr, nav)
	var nearby_mil: bool = poi_mgr.has_nearby_military_unit(poi, tactical_military_mgr, nav)
	var can_claim: bool = (poi.state == POIManager.POIState.CLEARED or (poi.state == POIManager.POIState.DISCOVERED and not guarded)) and not guarded and nearby_mil and poi.state != POIManager.POIState.CLAIMED
	var reward_parts: Array[String] = []
	for r_id in poi.rewards.keys():
		reward_parts.append("%s +%d" % [EconomyConfig.RESOURCE_NAMES_VI.get(str(r_id), str(r_id)), int(poi.rewards[r_id])])
	var pending_parts: Array[String] = []
	for r_id in poi.pending_rewards.keys():
		pending_parts.append("%s +%d" % [EconomyConfig.RESOURCE_NAMES_VI.get(str(r_id), str(r_id)), int(poi.pending_rewards[r_id])])
	var detail := "Phần thưởng: %s" % (", ".join(reward_parts) if not reward_parts.is_empty() else "Không có")
	if not pending_parts.is_empty():
		detail += "\nĐang chờ kho trống: %s" % ", ".join(pending_parts)
	if poi.state == POIManager.POIState.CLAIMED:
		detail += "\nĐã thu thập hoàn tất."
	elif guarded:
		detail += "\nCần tiêu diệt quái vật canh giữ (<= 5 ô)."
	elif not nearby_mil:
		detail += "\nCần đưa quân đội đứng cạnh (<= 1 ô) để thu thập."
	return {
		"is_debug_inspect": false,
		"category": "poi",
		"id": poi.id,
		"poi_id": poi.id,
		"type": poi.type,
		"cell": poi.cell,
		"size": Vector2i(1, 1),
		"title": poi.name,
		"coords_text": "Tọa độ: (%d, %d) | Loại: %s" % [poi.cell.x, poi.cell.y, poi.type],
		"state_text": "Trạng thái: %s" % poi_mgr.get_state_label(poi.state),
		"state_color": Color(0.95, 0.72, 0.22, 1.0) if poi.state != POIManager.POIState.CLAIMED else Color(0.65, 0.65, 0.65, 1.0),
		"detail_text": detail,
		"show_bar": false,
		"can_claim": can_claim,
	}

func claim_poi_with_military(poi_id: String) -> Dictionary:
	if poi_mgr == null:
		return {"success": false, "reason": "POIManager không khả dụng"}
	var rm = _get_resource_mgr()
	var res: Dictionary = poi_mgr.claim_poi_reward(poi_id, rm, tactical_military_mgr, monster_mgr, nav, true)
	var poi = poi_mgr.get_poi(poi_id)
	if poi != null:
		_update_poi_node_visual(poi)
		if hud != null and hud.has_method("show_entity_inspector"):
			hud.call("show_entity_inspector", "poi", str(poi.id))
	return res

func _handle_tactical_right_click_friendly_outpost(outpost_id: String, outpost_name: String, outpost_cell: Vector2i, is_operational: bool) -> void:
	if player_army_mgr == null or tactical_military_mgr == null:
		return
	if not is_operational:
		if hud != null:
			hud.show_event_banner("Không Thể Đồn Trú", "%s chưa ở trạng thái hoạt động để đồn trú." % outpost_name, false, 3.0)
		return

	var info: Dictionary = player_army_mgr.call("get_outpost_info", outpost_id)
	if not bool(info.get("valid", false)):
		if hud != null:
			hud.show_event_banner("Không Thể Đồn Trú", str(info.get("reason", "Tiền đồn không hợp lệ.")), false, 3.0)
		return

	var cap: int = int(player_army_mgr.call("get_garrison_capacity", outpost_id))
	var cur: int = int(player_army_mgr.call("get_garrison_count", outpost_id))
	var in_transit: int = int(player_army_mgr.call("get_in_transit_count", outpost_id))
	var vacant: int = maxi(0, cap - cur - in_transit)
	if vacant <= 0:
		if hud != null:
			hud.show_event_banner("Không Thể Đồn Trú", "%s đã đạt sức chứa tối đa (%d/%d)." % [outpost_name, cur, cap], false, 3.0)
		return

	var near_ids: Array[String] = []
	var far_ids: Array[String] = []
	var sel_ids: Array = tactical_military_mgr.get("selected_unit_ids") if tactical_military_mgr.get("selected_unit_ids") != null else []
	for uid in sel_ids:
		var u = tactical_military_mgr.call("get_unit", str(uid))
		if u == null or not is_instance_valid(u) or not bool(u.get("is_alive")):
			continue
		var u_cell: Vector2i = u.get("current_cell")
		if IsoMath.grid_distance(u_cell, outpost_cell) <= 4:
			near_ids.append(str(uid))
		else:
			far_ids.append(str(uid))

	var reserve_count: int = int(player_army_mgr.get("soldier_count")) if player_army_mgr.get("soldier_count") != null else 0
	var max_stationable: int = mini(vacant, reserve_count)
	if max_stationable <= 0 or (near_ids.is_empty() and far_ids.is_empty()):
		if hud != null:
			hud.show_event_banner("Không Thể Đồn Trú", "Không đủ binh sĩ dự bị hợp lệ để điều động.", false, 3.0)
		return

	if not near_ids.is_empty():
		var to_station: int = mini(near_ids.size(), max_stationable)
		var chosen_ids: Array[String] = near_ids.slice(0, to_station)
		if tactical_military_mgr.has_method("despawn_units"):
			tactical_military_mgr.call("despawn_units", chosen_ids, true)
		var res: Dictionary = station_outpost_garrison(outpost_id, to_station)
		if not bool(res.get("success", false)):
			if tactical_military_mgr.has_method("sync_with_player_army"):
				tactical_military_mgr.call("sync_with_player_army")
			if hud != null:
				hud.show_event_banner("Không Thể Đồn Trú", str(res.get("reason", "Điều binh thất bại")), false, 3.0)
			return
		if hud != null:
			hud.show_event_banner("Đồn Trú Thành Công", "Đã đồn trú %d quân vào %s (%d/%d)." % [to_station, outpost_name, int(res.get("outpost_count", cur + to_station)), cap], true, 2.5)
			if hud.has_method("refresh_building_inspector"):
				hud.call("refresh_building_inspector")
	else:
		var to_dispatch: int = mini(far_ids.size(), max_stationable)
		var chosen_ids: Array[String] = far_ids.slice(0, to_dispatch)
		if tactical_military_mgr.has_method("despawn_units"):
			tactical_military_mgr.call("despawn_units", chosen_ids, true)
		var res: Dictionary = dispatch_reinforcements_to_outpost(outpost_id, to_dispatch)
		if not bool(res.get("success", false)):
			if tactical_military_mgr.has_method("sync_with_player_army"):
				tactical_military_mgr.call("sync_with_player_army")
			if hud != null:
				hud.show_event_banner("Điều Binh Thất Bại", str(res.get("reason", "Không thể điều binh")), false, 3.0)
			return
		var travel_h: float = float(res.get("travel_hours", 1.0))
		if hud != null:
			hud.show_event_banner("Điều Binh Tiếp Viện", "Đã điều %d quân tiếp viện đến %s (Dự kiến đến sau %.1f giờ)." % [to_dispatch, outpost_name, travel_h], true, 2.5)
			if hud.has_method("refresh_building_inspector"):
				hud.call("refresh_building_inspector")
