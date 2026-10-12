class_name WorldGenerator
extends RefCounted
## Procedural World Generator for KINGDOMS UNBOUND.
## Generates a 64x64 discrete simulation grid map deterministically from a numeric seed.

const MAP_SIZE: int = 64

enum TerrainType {
	WATER = 0,
	SAND = 1,
	GRASS = 2,
	DIRT = 3
}

class WorldData:
	var seed_value: int
	var terrain: Array # Array of Array of int (64x64)
	var occupancy: Array # Array of Array of bool (64x64)
	var buildings: Array[Dictionary] = [] # [{type: String, cell: Vector2i, size: Vector2i}]
	var props: Array[Dictionary] = [] # [{type: String, cell: Vector2i}]
	var center_spawn: Vector2i = Vector2i(32, 32)

static func generate(seed_val: int) -> WorldData:
	var data := WorldData.new()
	data.seed_value = seed_val
	
	# Initialize grid arrays
	data.terrain = []
	data.occupancy = []
	for x in range(MAP_SIZE):
		var col_terrain: Array[int] = []
		var col_occ: Array[bool] = []
		for y in range(MAP_SIZE):
			col_terrain.append(TerrainType.GRASS)
			col_occ.append(false)
		data.terrain.append(col_terrain)
		data.occupancy.append(col_occ)
		
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
	
	# Generate terrain heights
	for x in range(MAP_SIZE):
		for y in range(MAP_SIZE):
			# Distance to center to create a natural island / settlement valley
			var dx: float = float(x - 32) / 32.0
			var dy: float = float(y - 32) / 32.0
			var center_dist: float = sqrt(dx * dx + dy * dy)
			
			var n_val: float = noise.get_noise_2d(float(x), float(y)) - (center_dist * 0.35)
			
			# Guaranteed dry land around settlement center (22..42)
			if x >= 22 and x <= 42 and y >= 22 and y <= 42:
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

	# Place Starter Settlement Buildings around center (32, 32)
	# 1. Town Hall (3x3) at (31, 30)
	_place_building(data, "townhall", Vector2i(31, 30), Vector2i(3, 3))
	
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
			if data.terrain[x][y] == TerrainType.WATER:
				continue
				
			# Keep center settlement area (25..39) clear of heavy clutter
			var in_settlement: bool = (x >= 25 and x <= 39 and y >= 24 and y <= 38)
			var tree_thresh: float = 0.35 if not in_settlement else 0.85
			var rock_thresh: float = 0.55 if not in_settlement else 0.92
			
			var fn: float = flora_noise.get_noise_2d(float(x), float(y))
			var roll: float = rng.randf()
			
			if fn > tree_thresh and roll < 0.45:
				data.props.append({"type": "tree", "cell": Vector2i(x, y)})
				data.occupancy[x][y] = true
			elif fn < -0.30 and roll < 0.15:
				data.props.append({"type": "rock", "cell": Vector2i(x, y)})
				data.occupancy[x][y] = true

	return data

static func _place_building(data: WorldData, type: String, origin: Vector2i, size: Vector2i) -> void:
	data.buildings.append({
		"type": type,
		"cell": origin,
		"size": size
	})
	for ox in range(size.x):
		for oy in range(size.y):
			var cx: int = origin.x + ox
			var cy: int = origin.y + oy
			if cx >= 0 and cx < MAP_SIZE and cy >= 0 and cy < MAP_SIZE:
				data.occupancy[cx][cy] = true
				# Ensure ground underneath building is solid grass/dirt
				data.terrain[cx][cy] = TerrainType.GRASS
