class_name WorldGenerator
extends RefCounted
## Procedural World Generator for KINGDOMS UNBOUND.
## Generates a 64x64 discrete simulation grid map deterministically from a numeric seed.

const WildlifeConfigScript = preload("res://scripts/world/wildlife_config.gd")
const GridNavigationScript = preload("res://scripts/navigation/grid_navigation.gd")

const MAP_SIZE: int = 64 # Legacy 64x64 constant; use WorldData.map_width / map_height at runtime
const LEGACY_MAP_SIZE: int = 64
const DEFAULT_NEW_MAP_SIZE: int = 128
const LEGACY_GENERATOR_VERSION: int = 1
const BATCH03_GENERATOR_VERSION: int = 2
const V3_GENERATOR_VERSION: int = 3
const EXPANDED_GENERATOR_VERSION: int = 4
const BIOME_RIVER_GENERATOR_VERSION: int = 5
const RIVER_FIX_GENERATOR_VERSION: int = 6
const NATURAL_RESOURCES_GENERATOR_VERSION: int = 7
const RIVAL_SETTLEMENTS_GENERATOR_VERSION: int = 8
const LATEST_GENERATOR_VERSION: int = 8
const MIN_SUPPORTED_GENERATOR_VERSION: int = 1
const MAX_SUPPORTED_GENERATOR_VERSION: int = 8

enum TerrainType {
	WATER = 0,
	SAND = 1,
	GRASS = 2,
	DIRT = 3,
	HILLS = 4,
	MOUNTAINS = 5
}

enum BiomeType {
	GRASSLAND = 0,
	TEMPERATE_FOREST = 1,
	PINE_FOREST = 2,
	HIGHLANDS = 3,
	WETLANDS = 4
}

class WorldData:
	var seed_value: int
	var generator_version: int = LATEST_GENERATOR_VERSION
	var map_width: int = MAP_SIZE
	var map_height: int = MAP_SIZE
	var terrain: Array # Array of Array of int (map_width x map_height)
	var occupancy: Array # Array of Array of bool (map_width x map_height)
	var biome_grid: Array = [] # Array of Array of int (BiomeType), populated for V5+
	var elevation_grid: Array = [] # Array of Array of float, populated for V5+
	var river_cells: Array[Vector2i] = []
	var lake_cells: Array[Vector2i] = []
	var buildings: Array[Dictionary] = [] # [{type: String, cell: Vector2i, size: Vector2i}]
	var props: Array[Dictionary] = [] # [{type: String, cell: Vector2i}]
	var owned_cells: Array = [] # map_width x map_height bool grid maintained by TerritoryManager
	var bridge_walkable_cells: Dictionary = {} # Vector2i -> String (active bridge_id)
	var player_center: Vector2i = Vector2i(-999, -999) # Authoritative player generation & protection center
	var center_spawn: Vector2i = Vector2i(32, 32)
	var townhall_anchor: Vector2i = Vector2i(-1, -1)
	var settlements: Array = [] # Array of SettlementData (C1.10, V8+)
	var settlement_reserved_cells: Dictionary = {} # Vector2i -> true (walkable roads/plazas/margins)
	var settlement_skip_reasons: Dictionary = {} # faction_id -> String ("map_constraints")
	var wildlife: Array[Dictionary] = [] # Authoritative canonical wildlife records (P4-20)
	var wildlife_by_id: Dictionary = {} # a_id -> Dictionary

	func get_animal_by_id(a_id: String) -> Dictionary:
		return wildlife_by_id.get(a_id, {})

	func get_all_animals() -> Array[Dictionary]:
		return wildlife

	func is_bridge_walkable(cell: Vector2i) -> bool:
		return bridge_walkable_cells.has(cell)

	func get_map_size() -> int:
		return maxi(map_width, map_height)

	func is_in_bounds(cell: Vector2i) -> bool:
		return cell.x >= 0 and cell.x < map_width and cell.y >= 0 and cell.y < map_height

	func get_biome(cell: Vector2i) -> int:
		if biome_grid.is_empty() or not is_in_bounds(cell):
			return BiomeType.GRASSLAND
		return int(biome_grid[cell.x][cell.y])

static func is_supported_generator_version(ver: int) -> bool:
	return ver >= MIN_SUPPORTED_GENERATOR_VERSION and ver <= MAX_SUPPORTED_GENERATOR_VERSION

static func generate(seed_val: int, generator_version: int = LATEST_GENERATOR_VERSION, width: int = -1, height: int = -1, stage_e_snapshot_settlements: Variant = null) -> WorldData:
	if not is_supported_generator_version(generator_version):
		push_error("[WorldGenerator] Unsupported world_generator_version: %d" % generator_version)
		return null
	match generator_version:
		LEGACY_GENERATOR_VERSION:
			return _generate_world_v1(seed_val)
		BATCH03_GENERATOR_VERSION:
			return _generate_world_v2(seed_val)
		V3_GENERATOR_VERSION:
			return _generate_world_v3(seed_val)
		EXPANDED_GENERATOR_VERSION:
			var w: int = DEFAULT_NEW_MAP_SIZE if width <= 0 else width
			var h: int = DEFAULT_NEW_MAP_SIZE if height <= 0 else height
			return _generate_world_v4(seed_val, w, h)
		BIOME_RIVER_GENERATOR_VERSION:
			var w5: int = DEFAULT_NEW_MAP_SIZE if width <= 0 else width
			var h5: int = DEFAULT_NEW_MAP_SIZE if height <= 0 else height
			return _generate_world_v5(seed_val, w5, h5)
		RIVER_FIX_GENERATOR_VERSION:
			var w6: int = DEFAULT_NEW_MAP_SIZE if width <= 0 else width
			var h6: int = DEFAULT_NEW_MAP_SIZE if height <= 0 else height
			return _generate_world_v6(seed_val, w6, h6)
		NATURAL_RESOURCES_GENERATOR_VERSION:
			var w7: int = DEFAULT_NEW_MAP_SIZE if width <= 0 else width
			var h7: int = DEFAULT_NEW_MAP_SIZE if height <= 0 else height
			return _generate_world_v7(seed_val, w7, h7)
		RIVAL_SETTLEMENTS_GENERATOR_VERSION:
			var w8: int = DEFAULT_NEW_MAP_SIZE if width <= 0 else width
			var h8: int = DEFAULT_NEW_MAP_SIZE if height <= 0 else height
			return _generate_world_v8(seed_val, w8, h8, stage_e_snapshot_settlements)
	return null

static func _create_empty_world_data(seed_val: int, gen_ver: int, width: int = MAP_SIZE, height: int = MAP_SIZE) -> WorldData:
	var data := WorldData.new()
	data.seed_value = seed_val
	data.generator_version = gen_ver
	data.map_width = maxi(1, width)
	data.map_height = maxi(1, height)
	data.terrain = []
	data.occupancy = []
	for x in range(data.map_width):
		var col_terrain: Array[int] = []
		var col_occ: Array[bool] = []
		for y in range(data.map_height):
			col_terrain.append(TerrainType.GRASS)
			col_occ.append(false)
		data.terrain.append(col_terrain)
		data.occupancy.append(col_occ)
	return data

static func _place_starter_settlement(data: WorldData, center: Vector2i = Vector2i(32, 32)) -> void:
	# Place Starter Settlement Buildings around center
	# 1. Town Hall (3x3)
	_place_building(data, "townhall", center + Vector2i(-1, -2), Vector2i(3, 3))
	data.townhall_anchor = center + Vector2i(-1, -2)
	# 2. Storehouse (2x2)
	_place_building(data, "storehouse", center + Vector2i(4, -2), Vector2i(2, 2))
	# 3. Woodcutter Camp (2x2)
	_place_building(data, "woodcutter", center + Vector2i(-6, -2), Vector2i(2, 2))
	# 4. Farm (2x2)
	_place_building(data, "farm", center + Vector2i(4, 3), Vector2i(2, 2))
	# 5. 4 Houses (2x2 each)
	_place_building(data, "house", center + Vector2i(-6, 3), Vector2i(2, 2)) # House 1
	_place_building(data, "house", center + Vector2i(-1, 3), Vector2i(2, 2)) # House 2
	_place_building(data, "house", center + Vector2i(-6, -7), Vector2i(2, 2)) # House 3
	_place_building(data, "house", center + Vector2i(4, -7), Vector2i(2, 2)) # House 4
	data.player_center = center
	data.center_spawn = center + Vector2i(0, 1) # Plaza in front of Town Hall

## Version 1 — Legacy Pre-Batch 03 WorldGenerator (TerrainType 0..3 only).
static func _generate_world_v1(seed_val: int) -> WorldData:
	var data := _create_empty_world_data(seed_val, LEGACY_GENERATOR_VERSION)

	var noise := FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = 0.04
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = 3

	var flora_noise := FastNoiseLite.new()
	flora_noise.seed = seed_val + 9999
	flora_noise.frequency = 0.08

	for x in range(MAP_SIZE):
		for y in range(MAP_SIZE):
			var dx: float = float(x - 32) / 32.0
			var dy: float = float(y - 32) / 32.0
			var center_dist: float = sqrt(dx * dx + dy * dy)

			var n_val: float = noise.get_noise_2d(float(x), float(y)) - (center_dist * 0.35)

			if x >= 22 and x <= 42 and y >= 22 and y <= 42:
				n_val = maxf(n_val, 0.05)

			if n_val < -0.22:
				data.terrain[x][y] = TerrainType.WATER
				data.occupancy[x][y] = true
			elif n_val < -0.10:
				data.terrain[x][y] = TerrainType.SAND
			elif n_val < 0.20:
				data.terrain[x][y] = TerrainType.GRASS
			else:
				data.terrain[x][y] = TerrainType.DIRT

	_place_starter_settlement(data)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 54321

	for x in range(MAP_SIZE):
		for y in range(MAP_SIZE):
			if data.occupancy[x][y]:
				continue
			if data.terrain[x][y] == TerrainType.WATER:
				continue

			var in_settlement: bool = (x >= 25 and x <= 39 and y >= 24 and y <= 38)
			var tree_thresh: float = 0.35 if not in_settlement else 0.85
			var _rock_thresh: float = 0.55 if not in_settlement else 0.92

			var fn: float = flora_noise.get_noise_2d(float(x), float(y))
			var roll: float = rng.randf()

			if fn > tree_thresh and roll < 0.45:
				data.props.append({"type": "tree", "cell": Vector2i(x, y)})
				data.occupancy[x][y] = true
			elif fn < -0.30 and roll < 0.15:
				data.props.append({"type": "rock", "cell": Vector2i(x, y)})
				data.occupancy[x][y] = true

	return data

## Version 2 — Existing Batch 03 WorldGenerator (preserved for V2 save compatibility).
static func _generate_world_v2(seed_val: int) -> WorldData:
	var data := _create_empty_world_data(seed_val, BATCH03_GENERATOR_VERSION)
		
	# Deterministic Noise for terrain
	var noise := FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = 0.04
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = 3
	
	# Moisture / Flora Noise
	var flora_noise := FastNoiseLite.new()
	flora_noise.seed = seed_val + 9999
	flora_noise.frequency = 0.08

	# Elevation Noise for Hills & Mountains (GDD §3.2)
	var elev_noise := FastNoiseLite.new()
	elev_noise.seed = seed_val + 7777
	elev_noise.frequency = 0.055
	elev_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	elev_noise.fractal_octaves = 3
	
	# Generate terrain heights
	var hills_count: int = 0
	var mountains_count: int = 0
	for x in range(MAP_SIZE):
		for y in range(MAP_SIZE):
			# Distance to center to create a natural island / settlement valley
			var dx: float = float(x - 32) / 32.0
			var dy: float = float(y - 32) / 32.0
			var center_dist: float = sqrt(dx * dx + dy * dy)
			
			var n_val: float = noise.get_noise_2d(float(x), float(y)) - (center_dist * 0.35)
			
			# Guaranteed dry land around settlement center (22..42)
			var in_starter_valley: bool = (x >= 22 and x <= 42 and y >= 22 and y <= 42)
			if in_starter_valley:
				n_val = maxf(n_val, 0.05)
				
			if n_val < -0.22:
				data.terrain[x][y] = TerrainType.WATER
				data.occupancy[x][y] = true # Water is impassable / unwalkable
			elif n_val < -0.10:
				data.terrain[x][y] = TerrainType.SAND
			elif n_val < 0.20:
				data.terrain[x][y] = TerrainType.GRASS
			else:
				data.terrain[x][y] = TerrainType.DIRT

			# Apply Hills & Mountains on dry land outside starter valley & neutral tribe anchor (16, 48)
			var near_neutral: bool = (abs(x - 16) <= 2 and abs(y - 48) <= 2)
			if not in_starter_valley and not near_neutral and data.terrain[x][y] != TerrainType.WATER:
				var e_val: float = elev_noise.get_noise_2d(float(x), float(y))
				if e_val > 0.32 and center_dist > 0.38:
					data.terrain[x][y] = TerrainType.MOUNTAINS
					data.occupancy[x][y] = true # Mountains are impassable & unbuildable
					mountains_count += 1
				elif e_val > 0.16:
					data.terrain[x][y] = TerrainType.HILLS
					hills_count += 1

	# Deterministic fallback if an extreme seed produced zero Hills or Mountains
	if hills_count == 0:
		for hx in range(10, 14):
			for hy in range(10, 14):
				if data.terrain[hx][hy] != TerrainType.WATER and not data.occupancy[hx][hy]:
					data.terrain[hx][hy] = TerrainType.HILLS
	if mountains_count == 0:
		for mx in range(52, 55):
			for my in range(52, 55):
				if not data.occupancy[mx][my]:
					data.terrain[mx][my] = TerrainType.MOUNTAINS
					data.occupancy[mx][my] = true

	# Place Starter Settlement Buildings around center (32, 32)
	# 1. Town Hall (3x3) at (31, 30)
	_place_building(data, "townhall", Vector2i(31, 30), Vector2i(3, 3))
	data.townhall_anchor = Vector2i(31, 30)
	
	# 2. Storehouse (2x2) at (36, 30)
	_place_building(data, "storehouse", Vector2i(36, 30), Vector2i(2, 2))
	
	# 3. Woodcutter Camp (2x2) at (26, 30)
	_place_building(data, "woodcutter", Vector2i(26, 30), Vector2i(2, 2))
	
	# 4. Farm (2x2) at (36, 35)
	_place_building(data, "farm", Vector2i(36, 35), Vector2i(2, 2))
	
	# 5. 4 Houses (2x2 each)
	_place_building(data, "house", Vector2i(26, 35), Vector2i(2, 2)) # House 1
	_place_building(data, "house", Vector2i(31, 35), Vector2i(2, 2)) # House 2
	_place_building(data, "house", Vector2i(26, 25), Vector2i(2, 2)) # House 3
	_place_building(data, "house", Vector2i(36, 25), Vector2i(2, 2)) # House 4
	
	data.center_spawn = Vector2i(32, 33) # Plaza in front of Town Hall

	# Place Props (Trees & Rocks) on unoccupied dry tiles
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 54321
	
	for x in range(MAP_SIZE):
		for y in range(MAP_SIZE):
			if data.occupancy[x][y]:
				continue
			if data.terrain[x][y] == TerrainType.WATER or data.terrain[x][y] == TerrainType.MOUNTAINS:
				continue
				
			# Keep center settlement area (25..39) clear of heavy clutter
			var in_settlement: bool = (x >= 25 and x <= 39 and y >= 24 and y <= 38)
			var tree_thresh: float = 0.35 if not in_settlement else 0.85
			var _rock_thresh: float = 0.55 if not in_settlement else 0.92
			
			var fn: float = flora_noise.get_noise_2d(float(x), float(y))
			var roll: float = rng.randf()
			
			if data.terrain[x][y] == TerrainType.HILLS and not in_settlement:
				# Hills contain richer stone & ore deposits (GDD §3.2)
				if roll < 0.22:
					data.props.append({"type": "rock", "cell": Vector2i(x, y)})
					data.occupancy[x][y] = true
			elif fn > tree_thresh and roll < 0.45:
				data.props.append({"type": "tree", "cell": Vector2i(x, y)})
				data.occupancy[x][y] = true
			elif fn < -0.30 and roll < 0.15:
				data.props.append({"type": "rock", "cell": Vector2i(x, y)})
				data.occupancy[x][y] = true

	return data

## Version 3 — Corrected Current Generator:
## - Guaranteed dry, prop-free, reachable Neutral Settlement region around (16, 48).
## - Mountains are traversable (occupancy=false) with higher movement cost in GridNavigation.
static func _generate_world_v3(seed_val: int) -> WorldData:
	var data := _create_empty_world_data(seed_val, V3_GENERATOR_VERSION)

	var noise := FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = 0.04
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = 3

	var flora_noise := FastNoiseLite.new()
	flora_noise.seed = seed_val + 9999
	flora_noise.frequency = 0.08

	var elev_noise := FastNoiseLite.new()
	elev_noise.seed = seed_val + 7777
	elev_noise.frequency = 0.055
	elev_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	elev_noise.fractal_octaves = 3

	var hills_count: int = 0
	var mountains_count: int = 0
	for x in range(MAP_SIZE):
		for y in range(MAP_SIZE):
			var dx: float = float(x - 32) / 32.0
			var dy: float = float(y - 32) / 32.0
			var center_dist: float = sqrt(dx * dx + dy * dy)

			var n_val: float = noise.get_noise_2d(float(x), float(y)) - (center_dist * 0.35)

			var in_starter_valley: bool = (x >= 22 and x <= 42 and y >= 22 and y <= 42)
			var near_neutral: bool = (abs(x - 16) <= 2 and abs(y - 48) <= 2)
			if in_starter_valley or near_neutral:
				n_val = maxf(n_val, 0.05)

			if n_val < -0.22:
				data.terrain[x][y] = TerrainType.WATER
				data.occupancy[x][y] = true
			elif n_val < -0.10:
				data.terrain[x][y] = TerrainType.SAND
			elif n_val < 0.20:
				data.terrain[x][y] = TerrainType.GRASS
			else:
				data.terrain[x][y] = TerrainType.DIRT

			if not in_starter_valley and not near_neutral and data.terrain[x][y] != TerrainType.WATER:
				var e_val: float = elev_noise.get_noise_2d(float(x), float(y))
				if e_val > 0.32 and center_dist > 0.38:
					data.terrain[x][y] = TerrainType.MOUNTAINS
					mountains_count += 1
				elif e_val > 0.16:
					data.terrain[x][y] = TerrainType.HILLS
					hills_count += 1

	if hills_count == 0:
		for hx in range(10, 14):
			for hy in range(10, 14):
				if data.terrain[hx][hy] != TerrainType.WATER and not data.occupancy[hx][hy]:
					data.terrain[hx][hy] = TerrainType.HILLS
	if mountains_count == 0:
		for mx in range(52, 55):
			for my in range(52, 55):
				if not data.occupancy[mx][my]:
					data.terrain[mx][my] = TerrainType.MOUNTAINS

	_place_starter_settlement(data)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 54321

	for x in range(MAP_SIZE):
		for y in range(MAP_SIZE):
			if data.occupancy[x][y]:
				continue
			if data.terrain[x][y] == TerrainType.WATER or data.terrain[x][y] == TerrainType.MOUNTAINS:
				continue
			if abs(x - 16) <= 2 and abs(y - 48) <= 2:
				continue

			var in_settlement: bool = (x >= 25 and x <= 39 and y >= 24 and y <= 38)
			var tree_thresh: float = 0.35 if not in_settlement else 0.85

			var fn: float = flora_noise.get_noise_2d(float(x), float(y))
			var roll: float = rng.randf()

			if data.terrain[x][y] == TerrainType.HILLS and not in_settlement:
				if roll < 0.22:
					data.props.append({"type": "rock", "cell": Vector2i(x, y)})
					data.occupancy[x][y] = true
			elif fn > tree_thresh and roll < 0.45:
				data.props.append({"type": "tree", "cell": Vector2i(x, y)})
				data.occupancy[x][y] = true
			elif fn < -0.30 and roll < 0.15:
				data.props.append({"type": "rock", "cell": Vector2i(x, y)})
				data.occupancy[x][y] = true

	_ensure_neutral_settlement_connectivity(data, Vector2i(16, 48))
	return data

## Version 4 — Dynamic Finite Map Generator (Default 128x128).
## Scales starter valley, starter settlement, and neutral anchor around map center.
static func _generate_world_v4(seed_val: int, width: int = DEFAULT_NEW_MAP_SIZE, height: int = DEFAULT_NEW_MAP_SIZE) -> WorldData:
	var data := _create_empty_world_data(seed_val, EXPANDED_GENERATOR_VERSION, width, height)
	var center := Vector2i(width / 2, height / 2)
	var half_w: float = maxf(1.0, float(width) * 0.5)
	var half_h: float = maxf(1.0, float(height) * 0.5)
	var neutral_anchor := Vector2i(
		clampi(width / 4, 4, maxi(4, width - 5)),
		clampi((height * 3) / 4, 4, maxi(4, height - 5))
	)

	var noise := FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = 0.032
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = 3

	var flora_noise := FastNoiseLite.new()
	flora_noise.seed = seed_val + 9999
	flora_noise.frequency = 0.08

	var elev_noise := FastNoiseLite.new()
	elev_noise.seed = seed_val + 7777
	elev_noise.frequency = 0.045
	elev_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	elev_noise.fractal_octaves = 3

	var hills_count: int = 0
	var mountains_count: int = 0
	for x in range(width):
		for y in range(height):
			var dx: float = float(x - center.x) / half_w
			var dy: float = float(y - center.y) / half_h
			var center_dist: float = sqrt(dx * dx + dy * dy)

			var n_val: float = noise.get_noise_2d(float(x), float(y)) - (center_dist * 0.35)

			var in_starter_valley: bool = (absi(x - center.x) <= 10 and absi(y - center.y) <= 10)
			var near_neutral: bool = (absi(x - neutral_anchor.x) <= 2 and absi(y - neutral_anchor.y) <= 2)
			if in_starter_valley or near_neutral:
				n_val = maxf(n_val, 0.05)

			if n_val < -0.22:
				data.terrain[x][y] = TerrainType.WATER
				data.occupancy[x][y] = true
			elif n_val < -0.10:
				data.terrain[x][y] = TerrainType.SAND
			elif n_val < 0.20:
				data.terrain[x][y] = TerrainType.GRASS
			else:
				data.terrain[x][y] = TerrainType.DIRT

			if not in_starter_valley and not near_neutral and data.terrain[x][y] != TerrainType.WATER:
				var e_val: float = elev_noise.get_noise_2d(float(x), float(y))
				if e_val > 0.32 and center_dist > 0.38:
					data.terrain[x][y] = TerrainType.MOUNTAINS
					mountains_count += 1
				elif e_val > 0.16:
					data.terrain[x][y] = TerrainType.HILLS
					hills_count += 1

	if hills_count == 0:
		var h_start_x := clampi(width / 6, 2, maxi(2, width - 6))
		var h_start_y := clampi(height / 6, 2, maxi(2, height - 6))
		for hx in range(h_start_x, mini(width, h_start_x + 4)):
			for hy in range(h_start_y, mini(height, h_start_y + 4)):
				if data.terrain[hx][hy] != TerrainType.WATER and not data.occupancy[hx][hy]:
					data.terrain[hx][hy] = TerrainType.HILLS
	if mountains_count == 0:
		var m_start_x := clampi(width - 12, 2, maxi(2, width - 4))
		var m_start_y := clampi(height - 12, 2, maxi(2, height - 4))
		for mx in range(m_start_x, mini(width, m_start_x + 3)):
			for my in range(m_start_y, mini(height, m_start_y + 3)):
				if not data.occupancy[mx][my]:
					data.terrain[mx][my] = TerrainType.MOUNTAINS

	_place_starter_settlement(data, center)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 54321

	for x in range(width):
		for y in range(height):
			if data.occupancy[x][y]:
				continue
			if data.terrain[x][y] == TerrainType.WATER or data.terrain[x][y] == TerrainType.MOUNTAINS:
				continue
			if absi(x - neutral_anchor.x) <= 2 and absi(y - neutral_anchor.y) <= 2:
				continue

			var in_settlement: bool = (absi(x - center.x) <= 7 and absi(y - center.y) <= 7)
			var tree_thresh: float = 0.35 if not in_settlement else 0.85

			var fn: float = flora_noise.get_noise_2d(float(x), float(y))
			var roll: float = rng.randf()

			if data.terrain[x][y] == TerrainType.HILLS and not in_settlement:
				if roll < 0.22:
					data.props.append({"type": "rock", "cell": Vector2i(x, y)})
					data.occupancy[x][y] = true
			elif fn > tree_thresh and roll < 0.45:
				data.props.append({"type": "tree", "cell": Vector2i(x, y)})
				data.occupancy[x][y] = true
			elif fn < -0.30 and roll < 0.15:
				data.props.append({"type": "rock", "cell": Vector2i(x, y)})
				data.occupancy[x][y] = true

	_ensure_neutral_settlement_connectivity(data, neutral_anchor)
	return data

static func _ensure_neutral_settlement_connectivity(data: WorldData, neutral_anchor: Vector2i) -> void:
	var start: Vector2i = data.center_spawn
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [start]
	visited[start] = true
	var head: int = 0
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		if cur == neutral_anchor:
			return
		for d in dirs:
			var nxt: Vector2i = cur + d
			if not data.is_in_bounds(nxt):
				continue
			if visited.has(nxt):
				continue
			if data.terrain[nxt.x][nxt.y] == TerrainType.WATER or data.occupancy[nxt.x][nxt.y]:
				continue
			visited[nxt] = true
			queue.append(nxt)

	# Carve a deterministic dry land bridge from neutral_anchor toward center_spawn until reaching visited network
	var cur_p: Vector2i = neutral_anchor
	var prop_cells_to_remove: Dictionary = {}
	while not visited.has(cur_p) and cur_p != start:
		if data.terrain[cur_p.x][cur_p.y] == TerrainType.WATER:
			data.terrain[cur_p.x][cur_p.y] = TerrainType.GRASS
		if data.occupancy[cur_p.x][cur_p.y]:
			data.occupancy[cur_p.x][cur_p.y] = false
			prop_cells_to_remove[cur_p] = true
		if cur_p.x != start.x:
			cur_p.x += 1 if start.x > cur_p.x else -1
		elif cur_p.y != start.y:
			cur_p.y += 1 if start.y > cur_p.y else -1
	if not prop_cells_to_remove.is_empty():
		var filtered_props: Array[Dictionary] = []
		for p in data.props:
			if not prop_cells_to_remove.has(p.get("cell", Vector2i(-1, -1))):
				filtered_props.append(p)
		data.props = filtered_props

static func _place_building(data: WorldData, type: String, origin: Vector2i, size: Vector2i) -> void:
	data.buildings.append({
		"type": type,
		"cell": origin,
		"size": size,
		"upgrade_level": 1
	})
	for ox in range(size.x):
		for oy in range(size.y):
			var cx: int = origin.x + ox
			var cy: int = origin.y + oy
			if data.is_in_bounds(Vector2i(cx, cy)):
				data.occupancy[cx][cy] = true
				# Ensure ground underneath building is solid grass/dirt
				data.terrain[cx][cy] = TerrainType.GRASS

## Version 5 — Procedural Biomes, Varied Elevation, Rivers & Lakes (Frozen Phase 2 baseline).
static func _generate_world_v5(seed_val: int, width: int = DEFAULT_NEW_MAP_SIZE, height: int = DEFAULT_NEW_MAP_SIZE) -> WorldData:
	return _generate_world_v5_or_v6(seed_val, width, height, BIOME_RIVER_GENERATOR_VERSION)

## Version 6 — Procedural Biomes, Varied Elevation, Lakes & Corrected Continuous Rivers (Default 128x128).
static func _generate_world_v6(seed_val: int, width: int = DEFAULT_NEW_MAP_SIZE, height: int = DEFAULT_NEW_MAP_SIZE) -> WorldData:
	return _generate_world_v5_or_v6(seed_val, width, height, RIVER_FIX_GENERATOR_VERSION)

static func _generate_world_v7(seed_val: int, width: int = DEFAULT_NEW_MAP_SIZE, height: int = DEFAULT_NEW_MAP_SIZE) -> WorldData:
	return _generate_world_v5_or_v6(seed_val, width, height, NATURAL_RESOURCES_GENERATOR_VERSION)

static func _generate_world_v8(seed_val: int, width: int = DEFAULT_NEW_MAP_SIZE, height: int = DEFAULT_NEW_MAP_SIZE, stage_e_snapshot_settlements: Variant = null) -> WorldData:
	return _generate_world_v5_or_v6(seed_val, width, height, RIVAL_SETTLEMENTS_GENERATOR_VERSION, stage_e_snapshot_settlements)

static func _generate_world_v5_or_v6(seed_val: int, width: int, height: int, gen_ver: int, stage_e_snapshot_settlements: Variant = null) -> WorldData:
	var data := _create_empty_world_data(seed_val, gen_ver, width, height)
	var center := Vector2i(width / 2, height / 2)
	var neutral_anchor := Vector2i(-999, -999)
	if gen_ver < RIVAL_SETTLEMENTS_GENERATOR_VERSION:
		neutral_anchor = Vector2i(
			clampi(width / 4, 4, maxi(4, width - 5)),
			clampi((height * 3) / 4, 4, maxi(4, height - 5))
		)

	# Initialize biome_grid and elevation_grid
	data.biome_grid = []
	data.elevation_grid = []
	for x in range(width):
		var col_b: Array[int] = []
		col_b.resize(height)
		col_b.fill(BiomeType.GRASSLAND)
		data.biome_grid.append(col_b)
		var col_e: Array[float] = []
		col_e.resize(height)
		col_e.fill(0.15)
		data.elevation_grid.append(col_e)

	# Separate deterministic noise streams
	var elev_noise := FastNoiseLite.new()
	elev_noise.seed = seed_val + 1111
	elev_noise.frequency = 0.022
	elev_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	elev_noise.fractal_octaves = 4

	var moist_noise := FastNoiseLite.new()
	moist_noise.seed = seed_val + 2222
	moist_noise.frequency = 0.020
	moist_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	moist_noise.fractal_octaves = 3

	var temp_noise := FastNoiseLite.new()
	temp_noise.seed = seed_val + 3333
	temp_noise.frequency = 0.018
	temp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	temp_noise.fractal_octaves = 2

	var detail_noise := FastNoiseLite.new()
	detail_noise.seed = seed_val + 4444
	detail_noise.frequency = 0.075
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail_noise.fractal_octaves = 2

	var moist_grid: Array = []
	var temp_grid: Array = []
	var half_w: float = maxf(1.0, float(width) * 0.5)
	var half_h: float = maxf(1.0, float(height) * 0.5)

	# Stage A: Elevation, Moisture, Temperature fields
	for x in range(width):
		var m_col: Array[float] = []
		var t_col: Array[float] = []
		m_col.resize(height)
		t_col.resize(height)
		for y in range(height):
			var dx: float = float(x - center.x) / half_w
			var dy: float = float(y - center.y) / half_h
			var center_dist: float = sqrt(dx * dx + dy * dy)
			var edge_falloff: float = maxf(0.0, (center_dist - 0.72) * 1.15)
			var raw_e: float = elev_noise.get_noise_2d(float(x), float(y)) * 0.85 + 0.16 - edge_falloff
			var raw_m: float = moist_noise.get_noise_2d(float(x), float(y))
			var raw_t: float = temp_noise.get_noise_2d(float(x), float(y)) - maxf(0.0, raw_e) * 0.22

			var grid_dist: float = Vector2(x - center.x, y - center.y).length()
			var valley_edge: float = 12.5 + detail_noise.get_noise_2d(float(x), float(y)) * 3.0
			if grid_dist <= valley_edge:
				var blend: float = clampf((valley_edge - grid_dist) / 4.0, 0.0, 1.0)
				raw_e = lerpf(raw_e, 0.16, blend)
				raw_m = lerpf(raw_m, 0.0, blend * 0.7)
			if absi(x - neutral_anchor.x) <= 3 and absi(y - neutral_anchor.y) <= 3:
				raw_e = maxf(raw_e, 0.12)

			data.elevation_grid[x][y] = raw_e
			m_col[y] = raw_m
			t_col[y] = raw_t
		moist_grid.append(m_col)
		temp_grid.append(t_col)

	# Stage B: Biome Classification (5 approved biomes)
	for x in range(width):
		for y in range(height):
			var grid_dist: float = Vector2(x - center.x, y - center.y).length()
			var valley_edge: float = 11.5 + detail_noise.get_noise_2d(float(x), float(y)) * 2.5
			if grid_dist <= valley_edge:
				data.biome_grid[x][y] = BiomeType.GRASSLAND
				continue
			var e: float = float(data.elevation_grid[x][y])
			var m: float = float(moist_grid[x][y])
			var t: float = float(temp_grid[x][y])
			if e >= 0.36:
				data.biome_grid[x][y] = BiomeType.HIGHLANDS
			elif e < 0.22 and m > 0.12:
				data.biome_grid[x][y] = BiomeType.WETLANDS
			elif m > -0.04 and t < -0.03:
				data.biome_grid[x][y] = BiomeType.PINE_FOREST
			elif m > 0.02:
				data.biome_grid[x][y] = BiomeType.TEMPERATE_FOREST
			else:
				data.biome_grid[x][y] = BiomeType.GRASSLAND

	# 1-pass majority smoothing for spatial coherence (preserves starter valley)
	_smooth_v5_biomes(data, center)

	# Stage C: Base Terrain & Elevation Mapping
	for x in range(width):
		for y in range(height):
			var e: float = float(data.elevation_grid[x][y])
			var d_n: float = detail_noise.get_noise_2d(float(x), float(y))
			var b: int = int(data.biome_grid[x][y])
			var in_valley: bool = (absi(x - center.x) <= 13 and absi(y - center.y) <= 13)
			var near_neutral: bool = (absi(x - neutral_anchor.x) <= 3 and absi(y - neutral_anchor.y) <= 3)

			if not in_valley and not near_neutral and e < -0.18:
				data.terrain[x][y] = TerrainType.WATER
				data.occupancy[x][y] = true
			elif not in_valley and not near_neutral and e < -0.09:
				data.terrain[x][y] = TerrainType.SAND
			else:
				match b:
					BiomeType.HIGHLANDS:
						if e > 0.54:
							data.terrain[x][y] = TerrainType.MOUNTAINS
						elif e > 0.38:
							data.terrain[x][y] = TerrainType.HILLS
						elif d_n > 0.05:
							data.terrain[x][y] = TerrainType.DIRT
						else:
							data.terrain[x][y] = TerrainType.GRASS
					BiomeType.WETLANDS:
						if not in_valley and not near_neutral and d_n < -0.26 and e < 0.14:
							data.terrain[x][y] = TerrainType.WATER
							data.occupancy[x][y] = true
						elif d_n < 0.12:
							data.terrain[x][y] = TerrainType.DIRT
						else:
							data.terrain[x][y] = TerrainType.GRASS
					BiomeType.TEMPERATE_FOREST:
						if e > 0.34:
							data.terrain[x][y] = TerrainType.HILLS
						elif d_n < -0.14:
							data.terrain[x][y] = TerrainType.DIRT
						else:
							data.terrain[x][y] = TerrainType.GRASS
					BiomeType.PINE_FOREST:
						if e > 0.35:
							data.terrain[x][y] = TerrainType.HILLS
						elif d_n < -0.10:
							data.terrain[x][y] = TerrainType.DIRT
						else:
							data.terrain[x][y] = TerrainType.GRASS
					_:
						if d_n < -0.22 and not in_valley:
							data.terrain[x][y] = TerrainType.DIRT
						else:
							data.terrain[x][y] = TerrainType.GRASS

	# Stage D: Procedural Lakes and Rivers
	if data.generator_version >= RIVER_FIX_GENERATOR_VERSION:
		_generate_v6_hydrology(data, seed_val, center, neutral_anchor)
	else:
		_generate_v5_hydrology(data, seed_val, center, neutral_anchor)

	# Stage E: Starter Settlement, Procedural Rival Settlements (V8+) & Biome-Aware Props
	_place_starter_settlement(data, center)
	if data.generator_version >= RIVAL_SETTLEMENTS_GENERATOR_VERSION and ResourceLoader.exists("res://scripts/world/settlement_generator.gd"):
		var SettlementGeneratorScript = load("res://scripts/world/settlement_generator.gd")
		if stage_e_snapshot_settlements is Array:
			# Option B: supply snapshot reservations & solid occupancy for props/resources without committing settlement overlays
			SettlementGeneratorScript.apply_settlement_reservations_and_occupancy(data, stage_e_snapshot_settlements, true, true)
		else:
			SettlementGeneratorScript.generate_settlements(data, seed_val, center)
	if data.generator_version >= NATURAL_RESOURCES_GENERATOR_VERSION:
		_place_v7_props_and_resources(data, seed_val, center, neutral_anchor)
	else:
		_place_v5_props(data, seed_val, center, neutral_anchor)
	if data.generator_version < RIVAL_SETTLEMENTS_GENERATOR_VERSION:
		_ensure_neutral_settlement_connectivity(data, neutral_anchor)
	if data.generator_version >= RIVAL_SETTLEMENTS_GENERATOR_VERSION:
		generate_canonical_wildlife(data)
	return data

static func _smooth_v5_biomes(data: WorldData, center: Vector2i) -> void:
	var w: int = data.map_width
	var h: int = data.map_height
	var copy_b: Array = []
	for x in range(w):
		copy_b.append(data.biome_grid[x].duplicate())
	for x in range(1, w - 1):
		for y in range(1, h - 1):
			if absi(x - center.x) <= 10 and absi(y - center.y) <= 10:
				continue
			var counts: Dictionary = {}
			var best_b: int = int(copy_b[x][y])
			var best_c: int = 0
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					var nb: int = int(copy_b[x + dx][y + dy])
					var nc: int = int(counts.get(nb, 0)) + 1
					counts[nb] = nc
					if nc > best_c:
						best_c = nc
						best_b = nb
			if best_c >= 5:
				data.biome_grid[x][y] = best_b

static func _is_protected_for_water(cell: Vector2i, center: Vector2i, neutral_anchor: Vector2i) -> bool:
	if absi(cell.x - center.x) <= 14 and absi(cell.y - center.y) <= 14:
		return true
	if absi(cell.x - neutral_anchor.x) <= 3 and absi(cell.y - neutral_anchor.y) <= 3:
		return true
	return false

static func _generate_v5_hydrology(data: WorldData, seed_val: int, center: Vector2i, neutral_anchor: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 8888
	var w: int = data.map_width
	var h: int = data.map_height

	# 1. Carve 3 coherent lakes in low-elevation non-protected basins
	var lake_candidates: Array[Vector2i] = []
	for x in range(12, w - 12, 6):
		for y in range(12, h - 12, 6):
			var c := Vector2i(x, y)
			if _is_protected_for_water(c, center, neutral_anchor):
				continue
			var e: float = float(data.elevation_grid[x][y])
			if e < 0.22 and data.terrain[x][y] != TerrainType.WATER:
				lake_candidates.append(c)
	# Sort by lowest elevation, then pick spaced centers
	lake_candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return float(data.elevation_grid[a.x][a.y]) < float(data.elevation_grid[b.x][b.y])
	)
	var lake_centers: Array[Vector2i] = []
	for lc in lake_candidates:
		var ok := true
		for prev in lake_centers:
			if lc.distance_to(prev) < 26.0:
				ok = false
				break
		if ok:
			lake_centers.append(lc)
			if lake_centers.size() >= 3:
				break
	for lc in lake_centers:
		var rad: int = rng.randi_range(3, 5)
		for dx in range(-rad - 1, rad + 2):
			for dy in range(-rad - 1, rad + 2):
				var p := lc + Vector2i(dx, dy)
				if not data.is_in_bounds(p) or _is_protected_for_water(p, center, neutral_anchor):
					continue
				var d: float = Vector2(dx, dy).length() + rng.randf_range(-0.6, 0.6)
				if d <= float(rad):
					data.terrain[p.x][p.y] = TerrainType.WATER
					data.occupancy[p.x][p.y] = true
					data.lake_cells.append(p)
				elif d <= float(rad) + 1.2 and data.terrain[p.x][p.y] != TerrainType.WATER:
					data.terrain[p.x][p.y] = TerrainType.SAND

	# 2. Carve 3 continuous downhill meandering rivers
	var source_candidates: Array[Vector2i] = []
	for x in range(10, w - 10, 5):
		for y in range(10, h - 10, 5):
			var c := Vector2i(x, y)
			if _is_protected_for_water(c, center, neutral_anchor):
				continue
			if c.distance_to(center) < 20.0:
				continue
			var e: float = float(data.elevation_grid[x][y])
			if e > 0.24 and data.terrain[x][y] != TerrainType.WATER:
				source_candidates.append(c)
	source_candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return float(data.elevation_grid[a.x][a.y]) > float(data.elevation_grid[b.x][b.y])
	)
	var river_sources: Array[Vector2i] = []
	for sc in source_candidates:
		var ok := true
		for prev in river_sources:
			if sc.distance_to(prev) < 28.0:
				ok = false
				break
		if ok:
			river_sources.append(sc)
			if river_sources.size() >= 3:
				break

	var dirs4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for r_idx in range(river_sources.size()):
		var cur: Vector2i = river_sources[r_idx]
		var visited: Dictionary = {}
		var prev_dir := Vector2i(1, 0)
		# Pick a general outward/lakeward drainage target so rivers wind naturally without self-trapping
		var drain_target: Vector2i = lake_centers[r_idx % lake_centers.size()] if not lake_centers.is_empty() else Vector2i(w - 2 if cur.x >= center.x else 1, h - 2 if cur.y >= center.y else 1)
		if cur.distance_to(drain_target) < 18.0:
			drain_target = Vector2i(w - 2 if cur.x >= center.x else 1, h - 2 if cur.y >= center.y else 1)
		for step in range(180):
			if not data.is_in_bounds(cur):
				break
			if _is_protected_for_water(cur, center, neutral_anchor):
				break
			# Carve river cell + optional 1-cell widening for main stem
			var width_cells: Array[Vector2i] = [cur]
			if step > 10 and step % 3 != 0:
				var perp := Vector2i(-prev_dir.y, prev_dir.x)
				width_cells.append(cur + perp)
			for rc in width_cells:
				if data.is_in_bounds(rc) and not _is_protected_for_water(rc, center, neutral_anchor):
					data.terrain[rc.x][rc.y] = TerrainType.WATER
					data.occupancy[rc.x][rc.y] = true
					if not data.river_cells.has(rc):
						data.river_cells.append(rc)
					# Bank transition
					for d in dirs4:
						var bk: Vector2i = rc + d
						if data.is_in_bounds(bk) and data.terrain[bk.x][bk.y] != TerrainType.WATER and not _is_protected_for_water(bk, center, neutral_anchor):
							if data.terrain[bk.x][bk.y] == TerrainType.MOUNTAINS:
								data.terrain[bk.x][bk.y] = TerrainType.HILLS
							elif rng.randf() < 0.45:
								data.terrain[bk.x][bk.y] = TerrainType.SAND
			visited[cur] = true

			# Reached map edge
			if cur.x <= 1 or cur.y <= 1 or cur.x >= w - 2 or cur.y >= h - 2:
				break

			# Pick best downhill + drainage-guided neighbor (4-connected to keep river continuous)
			var best_next := Vector2i(-1, -1)
			var best_score: float = 999999.0
			var cur_dist: float = cur.distance_to(drain_target)
			for d in dirs4:
				var nxt := cur + d
				if not data.is_in_bounds(nxt) or visited.has(nxt):
					continue
				if _is_protected_for_water(nxt, center, neutral_anchor):
					continue
				var dist_delta: float = (nxt.distance_to(drain_target) - cur_dist) * 0.08
				var score: float = float(data.elevation_grid[nxt.x][nxt.y]) + dist_delta + rng.randf_range(-0.05, 0.05)
				if d == prev_dir:
					score -= 0.03 # Slight momentum for natural bends
				if data.terrain[nxt.x][nxt.y] == TerrainType.WATER and step > 14:
					score -= 0.40 # Flow into lakes/ocean after winding
				if score < best_score:
					best_score = score
					best_next = nxt
			if best_next == Vector2i(-1, -1):
				break
			prev_dir = best_next - cur
			var hit_existing_water: bool = (data.terrain[best_next.x][best_next.y] == TerrainType.WATER and step > 14)
			cur = best_next
			if hit_existing_water:
				break

## Version 6 Hydrology — Fixes premature river self-termination by distinguishing own widened river cells
## from external water (lakes, ocean/coast, map edge, or prior committed rivers for confluences).
static func _generate_v6_hydrology(data: WorldData, seed_val: int, center: Vector2i, neutral_anchor: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 8888
	var w: int = data.map_width
	var h: int = data.map_height

	# 1. Carve 3 coherent lakes in low-elevation non-protected basins (same lake model as V5)
	var lake_candidates: Array[Vector2i] = []
	for x in range(12, w - 12, 6):
		for y in range(12, h - 12, 6):
			var c := Vector2i(x, y)
			if _is_protected_for_water(c, center, neutral_anchor):
				continue
			var e: float = float(data.elevation_grid[x][y])
			if e < 0.22 and data.terrain[x][y] != TerrainType.WATER:
				lake_candidates.append(c)
	lake_candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return float(data.elevation_grid[a.x][a.y]) < float(data.elevation_grid[b.x][b.y])
	)
	var lake_centers: Array[Vector2i] = []
	for lc in lake_candidates:
		var ok := true
		for prev in lake_centers:
			if lc.distance_to(prev) < 26.0:
				ok = false
				break
		if ok:
			lake_centers.append(lc)
			if lake_centers.size() >= 3:
				break
	for lc in lake_centers:
		var rad: int = rng.randi_range(3, 5)
		for dx in range(-rad - 1, rad + 2):
			for dy in range(-rad - 1, rad + 2):
				var p := lc + Vector2i(dx, dy)
				if not data.is_in_bounds(p) or _is_protected_for_water(p, center, neutral_anchor):
					continue
				var d: float = Vector2(dx, dy).length() + rng.randf_range(-0.6, 0.6)
				if d <= float(rad):
					data.terrain[p.x][p.y] = TerrainType.WATER
					data.occupancy[p.x][p.y] = true
					data.lake_cells.append(p)
				elif d <= float(rad) + 1.2 and data.terrain[p.x][p.y] != TerrainType.WATER:
					data.terrain[p.x][p.y] = TerrainType.SAND

	# 2. Carve up to 3 continuous downhill meandering rivers with strict own-cell tracking & valid sink termination
	var source_candidates: Array[Vector2i] = []
	for x in range(10, w - 10, 5):
		for y in range(10, h - 10, 5):
			var c := Vector2i(x, y)
			if _is_protected_for_water(c, center, neutral_anchor):
				continue
			if c.distance_to(center) < 20.0:
				continue
			var e: float = float(data.elevation_grid[x][y])
			if e > 0.24 and data.terrain[x][y] != TerrainType.WATER:
				source_candidates.append(c)
	source_candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return float(data.elevation_grid[a.x][a.y]) > float(data.elevation_grid[b.x][b.y])
	)

	var spaced_sources: Array[Vector2i] = []
	for sc in source_candidates:
		var ok := true
		for prev in spaced_sources:
			if sc.distance_to(prev) < 24.0:
				ok = false
				break
		if ok:
			spaced_sources.append(sc)
			if spaced_sources.size() >= 12:
				break

	var dirs4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var step_budget: int = (w + h) * 2
	var committed_rivers: int = 0
	var committed_river_set: Dictionary = {}

	for r_idx in range(spaced_sources.size()):
		if committed_rivers >= 3:
			break
		var cur: Vector2i = spaced_sources[r_idx]
		if committed_river_set.has(cur) or data.terrain[cur.x][cur.y] == TerrainType.WATER:
			continue
		var visited: Dictionary = {}
		var own_river_cells: Dictionary = {}
		var pending_carves: Array[Vector2i] = []
		var prev_dir := Vector2i(1, 0)

		var drain_target: Vector2i = Vector2i(w - 2 if cur.x >= center.x else 1, h - 2 if cur.y >= center.y else 1)
		if not lake_centers.is_empty():
			var best_lc: Vector2i = lake_centers[r_idx % lake_centers.size()]
			if cur.distance_to(best_lc) >= 18.0:
				drain_target = best_lc

		var terminated_valid: bool = false
		for step in range(step_budget):
			if not data.is_in_bounds(cur) or _is_protected_for_water(cur, center, neutral_anchor):
				break

			# Record current river stem cell + optional 1-cell widening (never overwriting existing external water)
			var width_cells: Array[Vector2i] = [cur]
			if step > 8 and step % 4 != 0:
				var perp := Vector2i(-prev_dir.y, prev_dir.x)
				var wide_c := cur + perp
				if data.is_in_bounds(wide_c) and not _is_protected_for_water(wide_c, center, neutral_anchor) and data.terrain[wide_c.x][wide_c.y] != TerrainType.WATER:
					width_cells.append(wide_c)
			for rc in width_cells:
				if not own_river_cells.has(rc):
					own_river_cells[rc] = true
					visited[rc] = true
					pending_carves.append(rc)

			# Reached valid map-edge outlet
			if cur.x <= 1 or cur.y <= 1 or cur.x >= w - 2 or cur.y >= h - 2:
				terminated_valid = true
				break

			# Pick best downhill + drainage-guided 4-neighbor, strictly ignoring own_river_cells
			var best_next := Vector2i(-1, -1)
			var best_score: float = 999999.0
			var cur_dist: float = cur.distance_to(drain_target)
			for d in dirs4:
				var nxt := cur + d
				if not data.is_in_bounds(nxt):
					continue
				if own_river_cells.has(nxt) or visited.has(nxt):
					continue
				if _is_protected_for_water(nxt, center, neutral_anchor):
					continue
				var is_ext_water: bool = (data.terrain[nxt.x][nxt.y] == TerrainType.WATER)
				if is_ext_water and step < 8:
					continue
				var dist_delta: float = (nxt.distance_to(drain_target) - cur_dist) * 0.09
				var score: float = float(data.elevation_grid[nxt.x][nxt.y]) + dist_delta + rng.randf_range(-0.04, 0.04)
				if d == prev_dir:
					score -= 0.03
				if is_ext_water:
					score -= 0.65 # Snap cleanly into lake, ocean/coast, or prior river confluence
				if score < best_score:
					best_score = score
					best_next = nxt

			if best_next == Vector2i(-1, -1):
				break

			if data.terrain[best_next.x][best_next.y] == TerrainType.WATER:
				# cur is 4-adjacent to external water (lake, ocean/coast, or committed river) -> valid termination
				terminated_valid = true
				break

			prev_dir = best_next - cur
			cur = best_next

		if terminated_valid and pending_carves.size() >= 10:
			for rc in pending_carves:
				data.terrain[rc.x][rc.y] = TerrainType.WATER
				data.occupancy[rc.x][rc.y] = true
				if not data.river_cells.has(rc):
					data.river_cells.append(rc)
				committed_river_set[rc] = true
				for d in dirs4:
					var bk: Vector2i = rc + d
					if data.is_in_bounds(bk) and data.terrain[bk.x][bk.y] != TerrainType.WATER and not _is_protected_for_water(bk, center, neutral_anchor):
						if data.terrain[bk.x][bk.y] == TerrainType.MOUNTAINS:
							data.terrain[bk.x][bk.y] = TerrainType.HILLS
						elif rng.randf() < 0.45:
							data.terrain[bk.x][bk.y] = TerrainType.SAND
			committed_rivers += 1

static func _place_v5_props(data: WorldData, seed_val: int, center: Vector2i, neutral_anchor: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 54321
	var flora_noise := FastNoiseLite.new()
	flora_noise.seed = seed_val + 9999
	flora_noise.frequency = 0.09

	var starter_trees := 0
	var starter_rocks := 0
	for x in range(data.map_width):
		for y in range(data.map_height):
			if data.occupancy[x][y]:
				continue
			var t: int = data.terrain[x][y]
			if t == TerrainType.WATER or t == TerrainType.MOUNTAINS or t == TerrainType.SAND:
				continue
			if absi(x - neutral_anchor.x) <= 2 and absi(y - neutral_anchor.y) <= 2:
				continue
			var in_settlement_core: bool = (absi(x - center.x) <= 7 and absi(y - center.y) <= 7)
			if in_settlement_core:
				continue

			var b: int = data.get_biome(Vector2i(x, y))
			var fn: float = flora_noise.get_noise_2d(float(x), float(y))
			var roll: float = rng.randf()
			var tree_prob := 0.04
			var rock_prob := 0.01
			match b:
				BiomeType.TEMPERATE_FOREST:
					tree_prob = 0.28 if fn > -0.10 else 0.14
					rock_prob = 0.02
				BiomeType.PINE_FOREST:
					tree_prob = 0.24 if fn > -0.10 else 0.12
					rock_prob = 0.03
				BiomeType.HIGHLANDS:
					tree_prob = 0.04
					rock_prob = 0.16 if (t == TerrainType.HILLS or t == TerrainType.DIRT) else 0.07
				BiomeType.WETLANDS:
					tree_prob = 0.09
					rock_prob = 0.01
				_:
					tree_prob = 0.045
					rock_prob = 0.012

			var in_starter_ring: bool = (absi(x - center.x) <= 12 and absi(y - center.y) <= 12)
			if roll < tree_prob:
				data.props.append({"type": "tree", "cell": Vector2i(x, y)})
				data.occupancy[x][y] = true
				if in_starter_ring:
					starter_trees += 1
			elif roll < tree_prob + rock_prob:
				data.props.append({"type": "rock", "cell": Vector2i(x, y)})
				data.occupancy[x][y] = true
				if in_starter_ring:
					starter_rocks += 1

	# Guarantee minimal starter wood/stone accessibility inside starter ring
	if starter_trees < 4 or starter_rocks < 2:
		for x in range(maxi(0, center.x - 11), mini(data.map_width, center.x + 12)):
			for y in range(maxi(0, center.y - 11), mini(data.map_height, center.y + 12)):
				if absi(x - center.x) <= 7 and absi(y - center.y) <= 7:
					continue
				if data.occupancy[x][y] or data.terrain[x][y] == TerrainType.WATER:
					continue
				if starter_trees < 4:
					data.props.append({"type": "tree", "cell": Vector2i(x, y)})
					data.occupancy[x][y] = true
					starter_trees += 1
				elif starter_rocks < 2:
					data.props.append({"type": "rock", "cell": Vector2i(x, y)})
					data.occupancy[x][y] = true
					starter_rocks += 1
				if starter_trees >= 4 and starter_rocks >= 2:
					break
			if starter_trees >= 4 and starter_rocks >= 2:
				break

static func make_prop_id(world_seed: int, gen_ver: int, prop_type: String, cell: Vector2i) -> String:
	return "%d_v%d_%s_%d_%d" % [world_seed, gen_ver, prop_type, cell.x, cell.y]

static func make_resource_node_id(world_seed: int, gen_ver: int, res_type: String, cell: Vector2i) -> String:
	return "%d_v%d_%s_%d_%d" % [world_seed, gen_ver, res_type, cell.x, cell.y]

static func _is_valid_v7_prop_cell(data: WorldData, cell: Vector2i, center: Vector2i, neutral_anchor: Vector2i) -> bool:
	if not data.is_in_bounds(cell):
		return false
	if data.occupancy[cell.x][cell.y]:
		return false
	if not data.settlement_reserved_cells.is_empty() and data.settlement_reserved_cells.has(cell):
		return false
	var t: int = data.terrain[cell.x][cell.y]
	if t == TerrainType.WATER or t == TerrainType.MOUNTAINS or t == TerrainType.SAND:
		return false
	if neutral_anchor.x >= 0 and absi(cell.x - neutral_anchor.x) <= 2 and absi(cell.y - neutral_anchor.y) <= 2:
		return false
	if absi(cell.x - center.x) <= 7 and absi(cell.y - center.y) <= 7:
		return false
	return true

static func _has_walkable_approach_neighbor(data: WorldData, cell: Vector2i) -> bool:
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = cell + offset
		if data.is_in_bounds(n) and not data.occupancy[n.x][n.y]:
			var nt: int = data.terrain[n.x][n.y]
			if nt != TerrainType.WATER and nt != TerrainType.MOUNTAINS:
				return true
	return false

static func _place_v7_props_and_resources(data: WorldData, seed_val: int, center: Vector2i, neutral_anchor: Vector2i) -> void:
	# 1. Biome-tuned tree & rock placement (isolated RNG stream)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 54321
	var flora_noise := FastNoiseLite.new()
	flora_noise.seed = seed_val + 9999
	flora_noise.frequency = 0.09

	var starter_trees := 0
	var starter_rocks := 0
	for x in range(data.map_width):
		for y in range(data.map_height):
			var cell := Vector2i(x, y)
			if not _is_valid_v7_prop_cell(data, cell, center, neutral_anchor):
				continue
			var t: int = data.terrain[x][y]
			var b: int = data.get_biome(cell)
			var fn: float = flora_noise.get_noise_2d(float(x), float(y))
			var roll: float = rng.randf()
			var tree_prob := 0.04
			var rock_prob := 0.01
			match b:
				BiomeType.TEMPERATE_FOREST:
					tree_prob = 0.29 if fn > -0.10 else 0.15
					rock_prob = 0.015
				BiomeType.PINE_FOREST:
					tree_prob = 0.25 if fn > -0.05 else 0.13
					rock_prob = 0.025
				BiomeType.HIGHLANDS:
					tree_prob = 0.035
					rock_prob = 0.17 if (t == TerrainType.HILLS or t == TerrainType.DIRT) else 0.08
				BiomeType.WETLANDS:
					tree_prob = 0.10
					rock_prob = 0.006
				_:
					tree_prob = 0.042
					rock_prob = 0.010

			var in_starter_ring: bool = (absi(x - center.x) <= 12 and absi(y - center.y) <= 12)
			if roll < tree_prob:
				data.props.append({"type": "tree", "cell": cell})
				data.occupancy[x][y] = true
				if in_starter_ring:
					starter_trees += 1
			elif roll < tree_prob + rock_prob:
				data.props.append({"type": "rock", "cell": cell})
				data.occupancy[x][y] = true
				if in_starter_ring:
					starter_rocks += 1

	# Guarantee minimal starter wood/stone accessibility inside starter ring
	if starter_trees < 4 or starter_rocks < 2:
		for x in range(maxi(0, center.x - 11), mini(data.map_width, center.x + 12)):
			for y in range(maxi(0, center.y - 11), mini(data.map_height, center.y + 12)):
				if absi(x - center.x) <= 7 and absi(y - center.y) <= 7:
					continue
				if data.occupancy[x][y] or data.terrain[x][y] == TerrainType.WATER or data.terrain[x][y] == TerrainType.MOUNTAINS:
					continue
				if starter_trees < 4:
					data.props.append({"type": "tree", "cell": Vector2i(x, y)})
					data.occupancy[x][y] = true
					starter_trees += 1
				elif starter_rocks < 2:
					data.props.append({"type": "rock", "cell": Vector2i(x, y)})
					data.occupancy[x][y] = true
					starter_rocks += 1
				if starter_trees >= 4 and starter_rocks >= 2:
					break
			if starter_trees >= 4 and starter_rocks >= 2:
				break

	# 2. Natural Resource Clusters (separate deterministic RNG stream)
	var res_rng := RandomNumberGenerator.new()
	res_rng.seed = seed_val + 70001
	var cluster_centers: Array[Vector2i] = []

	var resource_specs := [
		{
			"type": "ore_deposit",
			"min_dist": 9,
			"max_clusters": 14,
			"cluster_min": 2,
			"cluster_max": 4,
			"min_spacing": 9,
			"weights": {
				BiomeType.HIGHLANDS: 0.032,
				BiomeType.PINE_FOREST: 0.016,
				BiomeType.TEMPERATE_FOREST: 0.004,
				BiomeType.GRASSLAND: 0.003,
				BiomeType.WETLANDS: 0.001
			}
		},
		{
			"type": "crystal_vein",
			"min_dist": 20,
			"max_clusters": 5,
			"cluster_min": 1,
			"cluster_max": 2,
			"min_spacing": 16,
			"weights": {
				BiomeType.HIGHLANDS: 0.012,
				BiomeType.PINE_FOREST: 0.002,
				BiomeType.TEMPERATE_FOREST: 0.001,
				BiomeType.GRASSLAND: 0.0,
				BiomeType.WETLANDS: 0.0
			}
		},
		{
			"type": "herb_patch",
			"min_dist": 8,
			"max_clusters": 14,
			"cluster_min": 2,
			"cluster_max": 4,
			"min_spacing": 8,
			"weights": {
				BiomeType.TEMPERATE_FOREST: 0.028,
				BiomeType.WETLANDS: 0.030,
				BiomeType.PINE_FOREST: 0.006,
				BiomeType.GRASSLAND: 0.004,
				BiomeType.HIGHLANDS: 0.002
			}
		},
		{
			"type": "berry_bush",
			"min_dist": 8,
			"max_clusters": 16,
			"cluster_min": 2,
			"cluster_max": 4,
			"min_spacing": 8,
			"weights": {
				BiomeType.GRASSLAND: 0.022,
				BiomeType.TEMPERATE_FOREST: 0.026,
				BiomeType.PINE_FOREST: 0.006,
				BiomeType.WETLANDS: 0.005,
				BiomeType.HIGHLANDS: 0.002
			}
		}
	]

	for cfg in resource_specs:
		var r_type: String = str(cfg["type"])
		var spec: Dictionary = EconomyConfig.get_natural_resource_spec(r_type)
		if spec.is_empty():
			continue
		var min_dist: int = int(cfg["min_dist"])
		var max_clusters: int = int(cfg["max_clusters"])
		var c_min: int = int(cfg["cluster_min"])
		var c_max: int = int(cfg["cluster_max"])
		var min_spacing: int = int(cfg["min_spacing"])
		var weights: Dictionary = cfg["weights"]

		var candidates: Array[Vector2i] = []
		for x in range(2, data.map_width - 2):
			for y in range(2, data.map_height - 2):
				var cell := Vector2i(x, y)
				var dist: int = absi(x - center.x) + absi(y - center.y)
				if dist < min_dist:
					continue
				if not _is_valid_v7_prop_cell(data, cell, center, neutral_anchor):
					continue
				var b_id: int = data.get_biome(cell)
				var w_prob: float = float(weights.get(b_id, 0.0))
				if w_prob <= 0.0:
					continue
				if res_rng.randf() < w_prob:
					candidates.append(cell)

		# Shuffle deterministically using res_rng
		for i in range(candidates.size() - 1, 0, -1):
			var j: int = res_rng.randi_range(0, i)
			var tmp := candidates[i]
			candidates[i] = candidates[j]
			candidates[j] = tmp

		var placed_clusters := 0
		for anchor in candidates:
			if placed_clusters >= max_clusters:
				break
			var too_close := false
			for prev in cluster_centers:
				if absi(anchor.x - prev.x) + absi(anchor.y - prev.y) < min_spacing:
					too_close = true
					break
			if too_close:
				continue
			if not _is_valid_v7_prop_cell(data, anchor, center, neutral_anchor) or not _has_walkable_approach_neighbor(data, anchor):
				continue

			var target_size: int = res_rng.randi_range(c_min, c_max)
			var cluster_cells: Array[Vector2i] = [anchor]
			var offsets := [
				Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
				Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)
			]
			for off in offsets:
				if cluster_cells.size() >= target_size:
					break
				var nc: Vector2i = anchor + off
				if not _is_valid_v7_prop_cell(data, nc, center, neutral_anchor):
					continue
				if not _has_walkable_approach_neighbor(data, nc):
					continue
				if res_rng.randf() < 0.72:
					cluster_cells.append(nc)

			for c in cluster_cells:
				# Re-check approach after prior cluster placements and ensure we don't seal an adjacent resource
				data.occupancy[c.x][c.y] = true
				var safe_place := _has_walkable_approach_neighbor(data, c)
				if safe_place:
					for n_off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var nn: Vector2i = c + n_off
						if data.is_in_bounds(nn) and data.occupancy[nn.x][nn.y]:
							if not _has_walkable_approach_neighbor(data, nn):
								safe_place = false
								break
				if not safe_place:
					data.occupancy[c.x][c.y] = false
					continue
				data.props.append({
					"id": make_resource_node_id(seed_val, NATURAL_RESOURCES_GENERATOR_VERSION, r_type, c),
					"type": r_type,
					"cell": c,
					"resource": str(spec["resource"]),
					"max_qty": int(spec["max_qty"]),
					"remaining_qty": int(spec["max_qty"]),
					"depleted": false
				})
			cluster_centers.append(anchor)
			placed_clusters += 1

## Generates canonical wildlife population into WorldData (P4-20 / H1 Hunter Production).
## Deterministic, pure data population sharing exact RNG and distribution rules with WildlifeManager.
static func generate_canonical_wildlife(world_data: WorldData, nav: RefCounted = null) -> void:
	if world_data == null or world_data.biome_grid.is_empty():
		return
	var active_nav = nav
	if active_nav == null:
		active_nav = GridNavigationScript.new(world_data)

	world_data.wildlife.clear()
	world_data.wildlife_by_id.clear()

	var rng := RandomNumberGenerator.new()
	rng.seed = int(world_data.seed_value) ^ WildlifeConfigScript.WILDLIFE_RNG_SALT
	var candidates_by_biome: Dictionary = {
		BiomeType.GRASSLAND: [],
		BiomeType.TEMPERATE_FOREST: [],
		BiomeType.PINE_FOREST: [],
		BiomeType.HIGHLANDS: [],
		BiomeType.WETLANDS: [],
	}

	var occupied_spawn_cells: Dictionary = {}
	var building_cells: Array[Vector2i] = []
	for b in world_data.buildings:
		var origin: Vector2i = b.get("cell", Vector2i.ZERO)
		var b_size: Vector2i = b.get("size", Vector2i.ONE)
		for ox in range(b_size.x):
			for oy in range(b_size.y):
				building_cells.append(origin + Vector2i(ox, oy))

	var cardinal_dirs: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
	]

	for x in range(world_data.map_width):
		for y in range(world_data.map_height):
			var c := Vector2i(x, y)
			if not active_nav.is_cell_walkable(c):
				continue
			if IsoMath.grid_distance(c, world_data.center_spawn) <= 5:
				continue
			var too_close_to_bld: bool = false
			for bc in building_cells:
				if IsoMath.grid_distance(c, bc) <= 2:
					too_close_to_bld = true
					break
			if too_close_to_bld:
				continue
			var walkable_neighbors: int = 0
			for d in cardinal_dirs:
				var nc := c + d
				if nc.x >= 0 and nc.x < world_data.map_width and nc.y >= 0 and nc.y < world_data.map_height:
					if active_nav.is_cell_walkable(nc):
						walkable_neighbors += 1
			if walkable_neighbors < 2:
				continue
			var b_id: int = world_data.get_biome(c)
			if candidates_by_biome.has(b_id):
				candidates_by_biome[b_id].append(c)

	var total_spawned: int = 0
	for species_id in WildlifeConfigScript.SPECIES_ORDER:
		if total_spawned >= WildlifeConfigScript.MAX_TOTAL_POPULATION:
			break
		var spec: Dictionary = WildlifeConfigScript.get_species_def(species_id)
		var pool: Array[Vector2i] = []
		for b_id in spec.get("biomes", []):
			if candidates_by_biome.has(b_id):
				for c in candidates_by_biome[b_id]:
					pool.append(c)
		if pool.is_empty():
			continue
		# Deterministic Fisher-Yates shuffle
		for i in range(pool.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var tmp := pool[i]
			pool[i] = pool[j]
			pool[j] = tmp

		var cells_per_spawn: int = maxi(1, int(spec.get("cells_per_spawn", 150)))
		var area_cap: int = maxi(1, pool.size() / cells_per_spawn)
		var species_cap: int = mini(int(spec.get("max_pop", 8)), area_cap)
		species_cap = mini(species_cap, WildlifeConfigScript.MAX_TOTAL_POPULATION - total_spawned)

		var spawned_for_species: int = 0
		for c in pool:
			if spawned_for_species >= species_cap:
				break
			if occupied_spawn_cells.has(c):
				continue
			occupied_spawn_cells[c] = true
			var a_id := "wl_%s_%02d" % [species_id, spawned_for_species + 1]
			var idle_t: float = rng.randf_range(0.25, float(spec.get("idle_max", 4.0)))
			var rec: Dictionary = {
				"id": a_id,
				"species_id": species_id,
				"category": int(spec.get("category", 0)),
				"cell": c,
				"prev_cell": c,
				"home_cell": c,
				"target_cell": c,
				"last_dir": Vector2i.ZERO,
				"burst_remaining": 0,
				"speed_jitter": rng.randf_range(0.88, 1.12),
				"anim_phase": rng.randf_range(0.0, TAU),
				"turn_blend": 1.0,
				"move_progress": 0.0,
				"state": 0, # WildlifeConfig.BehaviorState.IDLE
				"state_timer": idle_t,
				"threat_cell": Vector2i(-1, -1),
				"flip_h": false,
				"is_available": true,
				"reserved_by": "",
				"reservation_type": "",
				"recovery_hours_left": 0.0,
				"raw_meat_yield": 2 if species_id == "rabbit" else (4 if species_id == "deer" else 0),
				"hunt_duration_hours": 1.5 if species_id == "rabbit" else (2.5 if species_id == "deer" else 0.0),
				"recovery_hours": 48.0 if species_id == "rabbit" else (72.0 if species_id == "deer" else 0.0),
				"allocated_workplace_id": "",
				"allocated_settlement_id": "",
			}
			world_data.wildlife.append(rec)
			world_data.wildlife_by_id[a_id] = rec
			spawned_for_species += 1
			total_spawned += 1
