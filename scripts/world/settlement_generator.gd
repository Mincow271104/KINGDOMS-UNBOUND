class_name SettlementGenerator
extends RefCounted
## Deterministic Procedural Settlement Generator for KINGDOMS UNBOUND (C1.10).
## Generates one physical settlement per NPC faction (rival_military, rival_merchant, neutral_tribe)
## using an independent RNG stream (seed + 65432), atomic scratch validation, and bounded fallback.

const SettlementDataScript = preload("res://scripts/world/settlement_data.gd")

const TERRAIN_WATER: int = 0
const TERRAIN_SAND: int = 1
const TERRAIN_GRASS: int = 2
const TERRAIN_DIRT: int = 3
const TERRAIN_HILLS: int = 4
const TERRAIN_MOUNTAINS: int = 5

const BIOME_GRASSLAND: int = 0
const BIOME_TEMPERATE_FOREST: int = 1
const BIOME_PINE_FOREST: int = 2
const BIOME_HIGHLANDS: int = 3
const BIOME_WETLANDS: int = 4

const SETTLEMENT_RNG_OFFSET: int = 65432
const MAX_CANDIDATES_TO_TRY: int = 28

const FACTION_SPECS: Array[Dictionary] = [
	{
		"faction_id": "rival_military",
		"role": SettlementDataScript.ROLE_CAPITAL,
		"objective_id": "outpost_rival_military"
	},
	{
		"faction_id": "rival_merchant",
		"role": SettlementDataScript.ROLE_CAPITAL,
		"objective_id": "outpost_rival_merchant"
	},
	{
		"faction_id": "neutral_tribe",
		"role": SettlementDataScript.ROLE_VILLAGE,
		"objective_id": "outpost_neutral_tribe"
	}
]

static func generate_settlements(data: RefCounted, seed_val: int, player_center: Vector2i) -> Array:
	var placed: Array = []
	if data == null:
		return placed

	if data.get("settlement_skip_reasons") is Dictionary:
		data.settlement_skip_reasons.clear()

	var stl_rng := RandomNumberGenerator.new()
	stl_rng.seed = seed_val + SETTLEMENT_RNG_OFFSET

	var is_compact_map: bool = (data.map_width < 96 or data.map_height < 96)
	var margin: int = 4 if is_compact_map else 6
	var min_player_dist: int = 14 if is_compact_map else 24
	var min_settlement_dist: int = 16 if is_compact_map else 28
	var sample_step: int = 3 if is_compact_map else 4

	# Precompute reachable cells from player_center over dry, unoccupied land
	var reachable: Dictionary = _compute_reachable_cells(data, player_center)

	# Build player protected cells lookup (starter buildings + tight starter valley)
	var player_protected: Dictionary = _build_player_protected_cells(data, player_center)

	for spec in FACTION_SPECS:
		var fid: String = str(spec["faction_id"])
		var role: String = str(spec["role"])
		var obj_id: String = str(spec["objective_id"])

		var candidates: Array[Dictionary] = _collect_scored_candidates(
			data, fid, player_center, placed, reachable,
			margin, min_player_dist, min_settlement_dist, sample_step, stl_rng
		)

		var committed: Variant = null
		var tiers: Array[String] = ["compact"]
		if not is_compact_map:
			tiers = ["full", "compact"]

		for tier in tiers:
			var tried: int = 0
			for cand in candidates:
				if tried >= MAX_CANDIDATES_TO_TRY:
					break
				tried += 1
				var anchor: Vector2i = cand["cell"]
				var layout: Dictionary = _build_layout_template(fid, anchor, tier)
				if _validate_layout_atomic(data, anchor, layout, player_protected, reachable):
					committed = _commit_layout(data, fid, role, obj_id, anchor, tier, layout)
					break
			if committed != null:
				break

		if committed != null:
			placed.append(committed)
			data.settlements.append(committed)
		elif data.is_in_bounds(player_center) and not reachable.is_empty():
			if data.get("settlement_skip_reasons") is Dictionary:
				data.settlement_skip_reasons[fid] = "map_constraints"

	return placed

static func is_valid_player_center(data: RefCounted, center: Vector2i) -> bool:
	if center == Vector2i(-999, -999) or center.x < 0 or center.y < 0:
		return false
	if data != null and data.has_method("is_in_bounds") and not data.is_in_bounds(center):
		return false
	return true

static func resolve_player_center(data: RefCounted, explicit_center: Vector2i = Vector2i(-999, -999)) -> Vector2i:
	if explicit_center != Vector2i(-999, -999):
		if is_valid_player_center(data, explicit_center):
			return explicit_center
		return Vector2i(-999, -999)
	if data != null:
		if data.get("player_center") is Vector2i:
			var pc: Vector2i = data.player_center
			if is_valid_player_center(data, pc):
				return pc
		if data.get("townhall_anchor") is Vector2i:
			var th: Vector2i = data.townhall_anchor
			if th != Vector2i(-1, -1) and th != Vector2i(-999, -999) and th.x >= 0 and th.y >= 0:
				var derived := th + Vector2i(1, 2)
				if is_valid_player_center(data, derived):
					return derived
	return Vector2i(-999, -999)

static func build_player_protected_cells(data: RefCounted, player_center: Vector2i = Vector2i(-999, -999)) -> Dictionary:
	var protected: Dictionary = {}
	if data == null:
		return protected

	var pc: Vector2i = resolve_player_center(data, player_center)

	# 1. Starter & placed buildings footprints with 1-tile clearance margin
	if data.get("buildings") is Array:
		for b in data.buildings:
			var origin: Vector2i = b.get("cell", Vector2i.ZERO)
			var b_size: Vector2i = b.get("size", Vector2i.ONE)
			for ox in range(-1, b_size.x + 1):
				for oy in range(-1, b_size.y + 1):
					var c := origin + Vector2i(ox, oy)
					if not data.has_method("is_in_bounds") or data.is_in_bounds(c):
						protected[c] = true

	# 2. Chebyshev radius-8 region around player_center
	if pc != Vector2i(-999, -999):
		for dx in range(-8, 9):
			for dy in range(-8, 9):
				var vc := pc + Vector2i(dx, dy)
				if not data.has_method("is_in_bounds") or data.is_in_bounds(vc):
					protected[vc] = true

	# 3. Player-owned territory
	if data.get("owned_cells") is Array:
		var mw_val: Variant = data.get("map_width")
		var mw_int: int = int(mw_val) if mw_val != null else -1
		if mw_int > 0 and data.owned_cells.size() == mw_int:
			for x in range(mw_int):
				var col: Variant = data.owned_cells[x]
				if col is Array:
					for y in range(col.size()):
						if bool(col[y]):
							protected[Vector2i(x, y)] = true

	return protected

static func _build_player_protected_cells(data: RefCounted, player_center: Vector2i) -> Dictionary:
	return build_player_protected_cells(data, player_center)

static func _compute_reachable_cells(data: RefCounted, start: Vector2i) -> Dictionary:
	var visited: Dictionary = {}
	if not data.is_in_bounds(start):
		return visited
	var queue: Array[Vector2i] = [start]
	visited[start] = true
	var head: int = 0
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		for d in dirs:
			var nxt := cur + d
			if not data.is_in_bounds(nxt) or visited.has(nxt):
				continue
			if not _is_cell_traversable_for_gen(data, nxt):
				continue
			visited[nxt] = true
			queue.append(nxt)
	return visited

static func _is_cell_traversable_for_gen(data: RefCounted, cell: Vector2i) -> bool:
	if not data.is_in_bounds(cell):
		return false
	var t: int = int(data.terrain[cell.x][cell.y])
	if t == TERRAIN_WATER:
		return false
	if t == TERRAIN_MOUNTAINS:
		return false
	if data.occupancy[cell.x][cell.y]:
		return false
	return true

static func _collect_scored_candidates(
	data: RefCounted,
	faction_id: String,
	player_center: Vector2i,
	placed: Array,
	reachable: Dictionary,
	margin: int,
	min_player_dist: int,
	min_settlement_dist: int,
	step: int,
	stl_rng: RandomNumberGenerator
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for x in range(margin, data.map_width - margin, step):
		for y in range(margin, data.map_height - margin, step):
			var c := Vector2i(x, y)
			if not reachable.has(c):
				continue
			var p_dist: int = absi(x - player_center.x) + absi(y - player_center.y)
			if p_dist < min_player_dist:
				continue
			var too_close: bool = false
			for prev in placed:
				var s_dist: int = absi(x - prev.anchor_cell.x) + absi(y - prev.anchor_cell.y)
				if s_dist < min_settlement_dist:
					too_close = true
					break
			if too_close:
				continue

			var score: float = _score_candidate(data, faction_id, c, p_dist, stl_rng)
			out.append({
				"cell": c,
				"score": score,
				"dist": p_dist
			})

	# Deterministic sort: highest score, then closest to ideal distance, then y, then x
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["score"]), float(b["score"])):
			return float(a["score"]) > float(b["score"])
		if int(a["dist"]) != int(b["dist"]):
			return int(a["dist"]) < int(b["dist"])
		var ca: Vector2i = a["cell"]
		var cb: Vector2i = b["cell"]
		if ca.y != cb.y:
			return ca.y < cb.y
		return ca.x < cb.x
	)
	return out

static func _score_candidate(
	data: RefCounted,
	faction_id: String,
	cell: Vector2i,
	player_dist: int,
	stl_rng: RandomNumberGenerator
) -> float:
	var score: float = 0.0
	var b_id: int = data.get_biome(cell)

	match faction_id:
		"rival_military":
			if b_id == BIOME_HIGHLANDS:
				score += 2.5
			elif b_id == BIOME_PINE_FOREST:
				score += 1.5
		"rival_merchant":
			if b_id == BIOME_GRASSLAND:
				score += 2.0
			elif b_id == BIOME_TEMPERATE_FOREST:
				score += 1.0
			# Prefer being moderately near water (trade river) without touching it
			if _has_water_within_ring(data, cell, 4, 10):
				score += 1.5
		"neutral_tribe":
			if b_id == BIOME_TEMPERATE_FOREST:
				score += 2.5
			elif b_id == BIOME_WETLANDS:
				score += 1.5

	# Flat dry land ratio in 7x7 neighborhood
	var flat_count: int = 0
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var nc := cell + Vector2i(dx, dy)
			if not data.is_in_bounds(nc):
				continue
			var t: int = int(data.terrain[nc.x][nc.y])
			if t == TERRAIN_GRASS or t == TERRAIN_DIRT:
				flat_count += 1
	score += float(flat_count) * 0.06

	# Prefer mid-range distance from player (not hugging map corners)
	var ideal_dist: float = float(maxi(data.map_width, data.map_height)) * 0.38
	score -= absf(float(player_dist) - ideal_dist) * 0.04

	# Tiny deterministic tie-break perturbation
	score += stl_rng.randf_range(0.0, 0.05)
	return score

static func _has_water_within_ring(data: RefCounted, center: Vector2i, r_min: int, r_max: int) -> bool:
	for dx in range(-r_max, r_max + 1):
		for dy in range(-r_max, r_max + 1):
			var d: int = absi(dx) + absi(dy)
			if d < r_min or d > r_max:
				continue
			var c := center + Vector2i(dx, dy)
			if data.is_in_bounds(c) and int(data.terrain[c.x][c.y]) == TERRAIN_WATER:
				return true
	return false

static func _get_footprint(b_type: String) -> Vector2i:
	var bp: Dictionary = EconomyConfig.BLUEPRINTS.get(b_type, {})
	if not bp.is_empty() and bp.has("footprint"):
		return bp["footprint"]
	match b_type:
		"townhall", "barracks", "market", "research_hall":
			return Vector2i(3, 3)
		"watchtower", "palisade":
			return Vector2i(1, 1)
		_:
			return Vector2i(2, 2)

static func _build_layout_template(faction_id: String, anchor: Vector2i, tier: String) -> Dictionary:
	var buildings: Array[Dictionary] = []
	var roads: Array[Vector2i] = []
	var decorations: Array[Dictionary] = []

	if tier == "compact":
		# Compact 7x7-compatible village layout
		var hq_type: String = "townhall"
		var sec_type: String = "house"
		if faction_id == "rival_military":
			hq_type = "barracks"
			sec_type = "watchtower"
		elif faction_id == "rival_merchant":
			hq_type = "market"
			sec_type = "storehouse"
		else:
			hq_type = "townhall"
			sec_type = "woodcutter"

		buildings.append({
			"id": "%s_hq" % faction_id,
			"type": hq_type,
			"cell": anchor + Vector2i(-1, -3),
			"size": _get_footprint(hq_type),
			"role": "hq",
			"blocking": true
		})
		var sec_size := _get_footprint(sec_type)
		buildings.append({
			"id": "%s_sec_1" % faction_id,
			"type": sec_type,
			"cell": anchor + Vector2i(-1, 1),
			"size": sec_size,
			"role": "support",
			"blocking": true
		})
		if faction_id == "rival_military":
			buildings.append({
				"id": "%s_house_1" % faction_id,
				"type": "house",
				"cell": anchor + Vector2i(1, 1),
				"size": Vector2i(2, 2),
				"role": "residential",
				"blocking": true
			})

		for rx in range(-2, 3):
			roads.append(anchor + Vector2i(rx, 0))
		if sec_size == Vector2i(1, 1):
			roads.append(anchor + Vector2i(0, 1))
		decorations.append({
			"type": "faction_banner",
			"cell": anchor + Vector2i(-2, 0),
			"variant": faction_id,
			"faction_id": faction_id
		})
		return {"buildings": buildings, "roads": roads, "decorations": decorations}

	# Full Layout (fits inside [-5, +4] around anchor)
	match faction_id:
		"rival_military":
			buildings.append({"id": "mil_hq", "type": "barracks", "cell": anchor + Vector2i(-1, -4), "size": Vector2i(3, 3), "role": "hq", "blocking": true})
			buildings.append({"id": "mil_store", "type": "storehouse", "cell": anchor + Vector2i(2, -2), "size": Vector2i(2, 2), "role": "storage", "blocking": true})
			buildings.append({"id": "mil_house_1", "type": "house", "cell": anchor + Vector2i(-4, -2), "size": Vector2i(2, 2), "role": "residential", "blocking": true})
			buildings.append({"id": "mil_house_2", "type": "house", "cell": anchor + Vector2i(-4, 2), "size": Vector2i(2, 2), "role": "residential", "blocking": true})
			buildings.append({"id": "mil_tower_nw", "type": "watchtower", "cell": anchor + Vector2i(-4, -4), "size": Vector2i(1, 1), "role": "defense", "blocking": true})
			buildings.append({"id": "mil_tower_ne", "type": "watchtower", "cell": anchor + Vector2i(3, -4), "size": Vector2i(1, 1), "role": "defense", "blocking": true})
			buildings.append({"id": "mil_tower_se", "type": "watchtower", "cell": anchor + Vector2i(3, 3), "size": Vector2i(1, 1), "role": "defense", "blocking": true})
			buildings.append({"id": "mil_tower_sw", "type": "watchtower", "cell": anchor + Vector2i(-4, 3), "size": Vector2i(1, 1), "role": "defense", "blocking": true})

			# Partial palisade perimeter with wide 2-tile gates on all 4 cardinal sides (never sealed)
			var pal_offsets: Array[Vector2i] = [
				Vector2i(-3, -5), Vector2i(-2, -5), Vector2i(2, -5), Vector2i(3, -5),
				Vector2i(-3, 4), Vector2i(-2, 4), Vector2i(2, 4), Vector2i(3, 4),
				Vector2i(-5, -3), Vector2i(-5, -2), Vector2i(-5, 2), Vector2i(-5, 3),
				Vector2i(4, -3), Vector2i(4, -2), Vector2i(4, 2), Vector2i(4, 3)
			]
			for idx in range(pal_offsets.size()):
				buildings.append({
					"id": "mil_pal_%d" % idx,
					"type": "palisade",
					"cell": anchor + pal_offsets[idx],
					"size": Vector2i(1, 1),
					"role": "wall",
					"blocking": true
				})

			# Plaza + cardinal road spines through the gates
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					roads.append(anchor + Vector2i(dx, dy))
			for rx in range(-5, 5):
				var rc := anchor + Vector2i(rx, 0)
				if not roads.has(rc):
					roads.append(rc)
			for ry in range(1, 5):
				var rc2 := anchor + Vector2i(0, ry)
				if not roads.has(rc2):
					roads.append(rc2)
			decorations.append({"type": "faction_banner", "cell": anchor + Vector2i(0, -1), "variant": "military", "faction_id": faction_id})

		"rival_merchant":
			buildings.append({"id": "mer_hq", "type": "market", "cell": anchor + Vector2i(-1, -4), "size": Vector2i(3, 3), "role": "hq", "blocking": true})
			buildings.append({"id": "mer_store_1", "type": "storehouse", "cell": anchor + Vector2i(2, -2), "size": Vector2i(2, 2), "role": "storage", "blocking": true})
			buildings.append({"id": "mer_store_2", "type": "storehouse", "cell": anchor + Vector2i(-4, -2), "size": Vector2i(2, 2), "role": "storage", "blocking": true})
			buildings.append({"id": "mer_workshop", "type": "workshop", "cell": anchor + Vector2i(2, 2), "size": Vector2i(2, 2), "role": "production", "blocking": true})
			buildings.append({"id": "mer_house_1", "type": "house", "cell": anchor + Vector2i(-4, 2), "size": Vector2i(2, 2), "role": "residential", "blocking": true})
			buildings.append({"id": "mer_house_2", "type": "house", "cell": anchor + Vector2i(-1, 2), "size": Vector2i(2, 2), "role": "residential", "blocking": true})

			for dx in range(-1, 2):
				for dy in range(-1, 2):
					roads.append(anchor + Vector2i(dx, dy))
			for rx in range(-5, 5):
				var rc := anchor + Vector2i(rx, 0)
				if not roads.has(rc):
					roads.append(rc)
			for ry in range(1, 5):
				var rc2 := anchor + Vector2i(1, ry)
				if not roads.has(rc2):
					roads.append(rc2)
			decorations.append({"type": "faction_banner", "cell": anchor + Vector2i(0, -1), "variant": "merchant", "faction_id": faction_id})

		"neutral_tribe", _:
			buildings.append({"id": "neu_hq", "type": "townhall", "cell": anchor + Vector2i(-1, -4), "size": Vector2i(3, 3), "role": "hq", "blocking": true})
			buildings.append({"id": "neu_wood", "type": "woodcutter", "cell": anchor + Vector2i(-4, -2), "size": Vector2i(2, 2), "role": "production", "blocking": true})
			buildings.append({"id": "neu_farm", "type": "farm", "cell": anchor + Vector2i(2, -2), "size": Vector2i(2, 2), "role": "production", "blocking": true})
			buildings.append({"id": "neu_house_1", "type": "house", "cell": anchor + Vector2i(-4, 2), "size": Vector2i(2, 2), "role": "residential", "blocking": true})
			buildings.append({"id": "neu_house_2", "type": "house", "cell": anchor + Vector2i(2, 2), "size": Vector2i(2, 2), "role": "residential", "blocking": true})

			for dx in range(-1, 2):
				for dy in range(-1, 2):
					roads.append(anchor + Vector2i(dx, dy))
			for ry in range(1, 4):
				var rc := anchor + Vector2i(0, ry)
				if not roads.has(rc):
					roads.append(rc)
			for rx in range(-3, 4):
				var rc2 := anchor + Vector2i(rx, 1)
				if not roads.has(rc2):
					roads.append(rc2)
			decorations.append({"type": "faction_banner", "cell": anchor + Vector2i(0, -1), "variant": "neutral", "faction_id": faction_id})
			decorations.append({"type": "campfire", "cell": anchor + Vector2i(0, 1), "variant": "neutral", "faction_id": faction_id})

	return {"buildings": buildings, "roads": roads, "decorations": decorations}

static func _validate_layout_atomic(
	data: RefCounted,
	anchor: Vector2i,
	layout: Dictionary,
	player_protected: Dictionary,
	reachable: Dictionary
) -> bool:
	var buildings: Array = layout.get("buildings", [])
	var roads: Array = layout.get("roads", [])
	if buildings.is_empty():
		return false

	var scratch_solid: Dictionary = {}
	for b in buildings:
		var origin: Vector2i = b.get("cell", Vector2i.ZERO)
		var b_size: Vector2i = b.get("size", Vector2i.ONE)
		for ox in range(b_size.x):
			for oy in range(b_size.y):
				var c := origin + Vector2i(ox, oy)
				if not data.is_in_bounds(c):
					return false
				if player_protected.has(c):
					return false
				if data.settlement_reserved_cells.has(c):
					return false
				if not _is_cell_traversable_for_gen(data, c):
					return false
				if scratch_solid.has(c):
					return false
				scratch_solid[c] = true

	var scratch_roads: Dictionary = {}
	for r in roads:
		if not data.is_in_bounds(r):
			return false
		if player_protected.has(r):
			return false
		if scratch_solid.has(r):
			return false
		if not _is_cell_traversable_for_gen(data, r):
			return false
		scratch_roads[r] = true

	if scratch_solid.has(anchor) or not _is_cell_traversable_for_gen(data, anchor):
		return false
	if not reachable.has(anchor):
		return false

	# Verify local connectivity from plaza (anchor) to at least 2 distinct outside-perimeter cells (or >= 1 for compact)
	var min_x: int = anchor.x
	var max_x: int = anchor.x
	var min_y: int = anchor.y
	var max_y: int = anchor.y
	for sc in scratch_solid.keys():
		min_x = mini(min_x, sc.x)
		max_x = maxi(max_x, sc.x)
		min_y = mini(min_y, sc.y)
		max_y = maxi(max_y, sc.y)

	var exit_count: int = 0
	var local_visited: Dictionary = {anchor: true}
	var q: Array[Vector2i] = [anchor]
	var head: int = 0
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while head < q.size():
		var cur: Vector2i = q[head]
		head += 1
		if cur.x < min_x or cur.x > max_x or cur.y < min_y or cur.y > max_y:
			exit_count += 1
			if exit_count >= 2:
				return true
			continue
		for d in dirs:
			var nxt := cur + d
			if local_visited.has(nxt):
				continue
			if scratch_solid.has(nxt):
				continue
			if not _is_cell_traversable_for_gen(data, nxt):
				continue
			local_visited[nxt] = true
			q.append(nxt)

	return exit_count >= 1

static func _commit_layout(
	data: RefCounted,
	faction_id: String,
	role: String,
	objective_id: String,
	anchor: Vector2i,
	tier: String,
	layout: Dictionary
) -> RefCounted:
	var stl := SettlementDataScript.new(
		"stl_%s_1" % faction_id,
		faction_id,
		faction_id,
		role,
		anchor,
		objective_id
	)
	stl.layout_tier = tier

	for b in layout.get("buildings", []):
		var b_copy: Dictionary = b.duplicate(true)
		stl.buildings.append(b_copy)

	for r in layout.get("roads", []):
		stl.roads.append(r)
		if data.is_in_bounds(r) and not data.occupancy[r.x][r.y]:
			if int(data.terrain[r.x][r.y]) != TERRAIN_WATER:
				data.terrain[r.x][r.y] = TERRAIN_DIRT

	for dec in layout.get("decorations", []):
		var d_copy: Dictionary = dec.duplicate(true)
		stl.decorations.append(d_copy)

	apply_settlement_reservations_and_occupancy(data, [stl], true, true)
	return stl

static func build_reserved_cells_for_settlement(stl: RefCounted, map_w: int, map_h: int) -> Dictionary:
	var reserved: Dictionary = {}
	if stl == null:
		return reserved
	var b_list: Array = stl.get("buildings") if stl.get("buildings") is Array else []
	for b in b_list:
		if not (b is Dictionary):
			continue
		var origin: Vector2i = b.get("cell", Vector2i.ZERO)
		var b_size: Vector2i = b.get("size", Vector2i.ONE)
		for ox in range(-1, b_size.x + 1):
			for oy in range(-1, b_size.y + 1):
				var bc := origin + Vector2i(ox, oy)
				if bc.x >= 0 and bc.x < map_w and bc.y >= 0 and bc.y < map_h:
					reserved[bc] = true
	var r_list: Array = stl.get("roads") if stl.get("roads") is Array else []
	for r in r_list:
		if r is Vector2i and r.x >= 0 and r.x < map_w and r.y >= 0 and r.y < map_h:
			reserved[r] = true
	var d_list: Array = stl.get("decorations") if stl.get("decorations") is Array else []
	for dec in d_list:
		if not (dec is Dictionary):
			continue
		var dc: Vector2i = dec.get("cell", Vector2i.ZERO)
		if dc.x >= 0 and dc.x < map_w and dc.y >= 0 and dc.y < map_h:
			reserved[dc] = true
	return reserved

static func apply_settlement_reservations_and_occupancy(
	data: RefCounted,
	settlements_list: Array,
	apply_occupancy: bool = true,
	apply_reservations: bool = true,
	excluded_reserved_cells: Dictionary = {}
) -> void:
	if data == null:
		return
	for stl in settlements_list:
		if stl == null:
			continue
		if apply_occupancy:
			var b_list: Array = stl.get("buildings") if stl.get("buildings") is Array else []
			for b in b_list:
				if not (b is Dictionary):
					continue
				if not bool(b.get("blocking", true)):
					continue
				var origin: Vector2i = b.get("cell", Vector2i.ZERO)
				var b_size: Vector2i = b.get("size", Vector2i.ONE)
				for ox in range(b_size.x):
					for oy in range(b_size.y):
						var c := origin + Vector2i(ox, oy)
						if data.is_in_bounds(c):
							data.occupancy[c.x][c.y] = true
		if apply_reservations:
			var reserved := build_reserved_cells_for_settlement(stl, data.map_width, data.map_height)
			for rc in reserved.keys():
				if not excluded_reserved_cells.has(rc):
					data.settlement_reserved_cells[rc] = true
