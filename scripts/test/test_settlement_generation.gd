extends SceneTree

const SettlementDataScript = preload("res://scripts/world/settlement_data.gd")
const SettlementGeneratorScript = preload("res://scripts/world/settlement_generator.gd")

var _passed: int = 0
var _failed: int = 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] %s" % msg)
	else:
		_failed += 1
		push_error("  [FAIL] %s" % msg)

func _init() -> void:
	print("\n========================================================")
	print("  TEST SUITE: C1.10 M1 Settlement Data & Generation")
	print("========================================================")

	_test_settlement_data_model()
	_test_v8_determinism_and_composition()
	_test_placement_safety_and_isolation()
	_test_navigation_and_bfs_connectivity()
	_test_fallback_and_clean_skip()
	_test_v7_compatibility()

	print("--------------------------------------------------------")
	print("  Results: %d passed, %d failed" % [_passed, _failed])
	print("========================================================")
	quit(1 if _failed > 0 else 0)

func _test_settlement_data_model() -> void:
	print("\n[1] SettlementDataScript Model & Serialization")
	var empty_stl := SettlementDataScript.new()
	_assert(empty_stl.status == SettlementDataScript.STATUS_ACTIVE, "Default status is active")
	_assert(empty_stl.layout_version == SettlementDataScript.LAYOUT_VERSION, "Default layout_version is 1")
	_assert(SettlementDataScript.deserialize({}) == null, "Empty dict deserialize returns null")

	var stl := SettlementDataScript.new("stl_test_1", "rival_military", "rival_military", SettlementDataScript.ROLE_CAPITAL, Vector2i(20, 20), "outpost_rival_military")
	stl.buildings.append({"id": "b1", "type": "barracks", "cell": Vector2i(19, 16), "size": Vector2i(3, 3), "role": "hq", "blocking": true})
	stl.roads.append(Vector2i(20, 20))
	stl.decorations.append({"type": "faction_banner", "cell": Vector2i(20, 19), "variant": "military", "faction_id": "rival_military"})

	var payload: Dictionary = stl.serialize()
	var restored := SettlementDataScript.deserialize(payload)
	_assert(restored != null, "Serialized SettlementDataScript deserializes")
	_assert(restored.settlement_id == "stl_test_1", "settlement_id roundtrips")
	_assert(restored.origin_faction_id == "rival_military", "origin_faction_id roundtrips")
	_assert(restored.owner_faction_id == "rival_military", "owner_faction_id roundtrips")
	_assert(restored.anchor_cell == Vector2i(20, 20), "anchor_cell roundtrips")
	_assert(restored.linked_objective_id == "outpost_rival_military", "linked_objective_id roundtrips")
	_assert(restored.buildings.size() == 1 and restored.buildings[0]["cell"] == Vector2i(19, 16), "buildings roundtrip")
	_assert(restored.roads.size() == 1 and restored.roads[0] == Vector2i(20, 20), "roads roundtrip")
	_assert(restored.decorations.size() == 1 and restored.decorations[0]["cell"] == Vector2i(20, 19), "decorations roundtrip")
	_assert(restored.get_bounds().has_point(Vector2i(20, 20)), "get_bounds() includes anchor/roads")

func _test_v8_determinism_and_composition() -> void:
	print("\n[2] V8 Determinism & Faction Composition")
	var wd_a := WorldGenerator.generate(12345, WorldGenerator.RIVAL_SETTLEMENTS_GENERATOR_VERSION)
	var wd_b := WorldGenerator.generate(12345, WorldGenerator.RIVAL_SETTLEMENTS_GENERATOR_VERSION)
	var wd_other := WorldGenerator.generate(54321, WorldGenerator.RIVAL_SETTLEMENTS_GENERATOR_VERSION)

	_assert(wd_a != null and wd_b != null, "V8 generation succeeds for seed 12345")
	_assert(wd_a.settlements.size() == 3, "128x128 V8 generates 3 NPC settlements (got %d)" % wd_a.settlements.size())
	_assert(wd_a.settlements.size() == wd_b.settlements.size(), "Same seed produces same settlement count")

	var expected_factions := ["rival_military", "rival_merchant", "neutral_tribe"]
	var expected_hqs := {"rival_military": "barracks", "rival_merchant": "market", "neutral_tribe": "townhall"}
	for i in range(wd_a.settlements.size()):
		var sa = wd_a.settlements[i]
		var sb = wd_b.settlements[i]
		_assert(sa.origin_faction_id == expected_factions[i], "Settlement %d faction is %s" % [i, expected_factions[i]])
		_assert(sa.anchor_cell == sb.anchor_cell, "Deterministic anchor for %s" % sa.origin_faction_id)
		_assert(sa.serialize() == sb.serialize(), "Deterministic full serialized layout for %s" % sa.origin_faction_id)
		var has_hq := false
		for b in sa.buildings:
			if b.get("role", "") == "hq" and b.get("type", "") == expected_hqs[sa.origin_faction_id]:
				has_hq = true
		_assert(has_hq, "%s has expected HQ (%s)" % [sa.origin_faction_id, expected_hqs[sa.origin_faction_id]])

	if wd_other.settlements.size() == 3:
		var diff_count := 0
		for i in range(3):
			if wd_a.settlements[i].anchor_cell != wd_other.settlements[i].anchor_cell:
				diff_count += 1
		_assert(diff_count > 0, "Different seed produces distinct settlement anchors")

func _test_placement_safety_and_isolation() -> void:
	print("\n[3] Placement Safety & Player Isolation")
	var wd := WorldGenerator.generate(12345, WorldGenerator.RIVAL_SETTLEMENTS_GENERATOR_VERSION)
	_assert(wd.buildings.size() == 8, "world_data.buildings remains strictly 8 starter player buildings (got %d)" % wd.buildings.size())

	var player_cells: Dictionary = {}
	for pb in wd.buildings:
		var o: Vector2i = pb["cell"]
		var s: Vector2i = pb["size"]
		for ox in range(s.x):
			for oy in range(s.y):
				player_cells[o + Vector2i(ox, oy)] = true

	var all_stl_building_cells: Dictionary = {}
	for stl in wd.settlements:
		for b in stl.buildings:
			var o: Vector2i = b["cell"]
			var s: Vector2i = b["size"]
			for ox in range(s.x):
				for oy in range(s.y):
					var c := o + Vector2i(ox, oy)
					_assert(wd.is_in_bounds(c), "Settlement building cell %s in bounds" % str(c))
					_assert(not player_cells.has(c), "Settlement building does not overlap player building at %s" % str(c))
					_assert(not all_stl_building_cells.has(c), "Settlement building does not overlap another settlement at %s" % str(c))
					var t: int = int(wd.terrain[c.x][c.y])
					_assert(t != WorldGenerator.TerrainType.WATER and t != WorldGenerator.TerrainType.MOUNTAINS, "Settlement building not on WATER/MOUNTAINS at %s" % str(c))
					all_stl_building_cells[c] = true
		for r in stl.roads:
			_assert(not all_stl_building_cells.has(r), "Road cell %s does not overlap solid building" % str(r))
			_assert(not player_cells.has(r), "Road cell %s does not overlap player building" % str(r))
			_assert(int(wd.terrain[r.x][r.y]) == WorldGenerator.TerrainType.DIRT, "Road cell %s uses TerrainType.DIRT" % str(r))

	for p in wd.props:
		var pc: Vector2i = p["cell"]
		_assert(not all_stl_building_cells.has(pc), "Prop %s does not overlap settlement building" % str(pc))
		_assert(not wd.settlement_reserved_cells.has(pc), "Prop %s respects settlement_reserved_cells" % str(pc))

func _test_navigation_and_bfs_connectivity() -> void:
	print("\n[4] Navigation & BFS Connectivity")
	var wd := WorldGenerator.generate(12345, WorldGenerator.RIVAL_SETTLEMENTS_GENERATOR_VERSION)
	IsoMath.set_active_map_dimensions(wd.map_width, wd.map_height)
	var nav := GridNavigation.new(wd)

	# Full-map BFS from center_spawn (independent of 2048-iteration A* cap)
	var visited: Dictionary = {wd.center_spawn: true}
	var q: Array[Vector2i] = [wd.center_spawn]
	var head: int = 0
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while head < q.size():
		var cur: Vector2i = q[head]
		head += 1
		for d in dirs:
			var nxt := cur + d
			if visited.has(nxt) or not nav.is_cell_walkable(nxt):
				continue
			visited[nxt] = true
			q.append(nxt)

	for stl in wd.settlements:
		_assert(nav.is_cell_walkable(stl.anchor_cell), "%s plaza anchor %s is walkable" % [stl.origin_faction_id, str(stl.anchor_cell)])
		_assert(visited.has(stl.anchor_cell), "%s plaza %s is BFS-reachable from center_spawn" % [stl.origin_faction_id, str(stl.anchor_cell)])
		for r in stl.roads:
			_assert(nav.is_cell_walkable(r), "%s road %s is walkable" % [stl.origin_faction_id, str(r)])
		for b in stl.buildings:
			var o: Vector2i = b["cell"]
			var s: Vector2i = b["size"]
			for ox in range(s.x):
				for oy in range(s.y):
					_assert(not nav.is_cell_walkable(o + Vector2i(ox, oy)), "%s solid %s cell blocked" % [stl.origin_faction_id, str(b["type"])])

	# Verify player starter plaza can still reach starter Farm/Storehouse adjacent cells
	var starter_farm_adj := wd.center_spawn + Vector2i(2, 2)
	_assert(visited.has(starter_farm_adj), "Player starter settlement remains walkable")

func _test_fallback_and_clean_skip() -> void:
	print("\n[5] Compact Fallback & Clean Skip")
	var wd64 := WorldGenerator.generate(12345, WorldGenerator.RIVAL_SETTLEMENTS_GENERATOR_VERSION, 64, 64)
	_assert(wd64 != null and wd64.map_width == 64, "64x64 V8 generation succeeds")
	_assert(wd64.settlements.size() >= 1, "64x64 V8 places >= 1 compact settlement (got %d)" % wd64.settlements.size())
	for stl in wd64.settlements:
		_assert(stl.layout_tier == "compact", "64x64 uses compact layout tier for %s" % stl.origin_faction_id)

	# Constrained impossible map: 16x16 all WATER except (8,8)
	var tiny := WorldGenerator._create_empty_world_data(999, WorldGenerator.RIVAL_SETTLEMENTS_GENERATOR_VERSION, 16, 16)
	for x in range(16):
		for y in range(16):
			tiny.terrain[x][y] = WorldGenerator.TerrainType.WATER
			tiny.occupancy[x][y] = true
	tiny.terrain[8][8] = WorldGenerator.TerrainType.GRASS
	tiny.occupancy[8][8] = false
	tiny.center_spawn = Vector2i(8, 8)
	var skipped := SettlementGeneratorScript.generate_settlements(tiny, 999, Vector2i(8, 8))
	_assert(skipped.is_empty(), "Impossible map cleanly skips all settlements")
	_assert(tiny.settlements.is_empty(), "Impossible map leaves 0 settlements")
	_assert(tiny.settlement_reserved_cells.is_empty(), "Impossible map leaves 0 residual reserved cells")
	_assert(not tiny.occupancy[8][8] and tiny.terrain[8][8] == WorldGenerator.TerrainType.GRASS, "Impossible map leaves center_spawn untouched")

func _test_v7_compatibility() -> void:
	print("\n[6] V7 Legacy Compatibility")
	var wd7 := WorldGenerator.generate(12345, WorldGenerator.NATURAL_RESOURCES_GENERATOR_VERSION)
	_assert(wd7 != null and wd7.generator_version == 7, "V7 still generates cleanly")
	_assert(wd7.settlements.is_empty(), "V7 generates 0 rival settlements")
	_assert(wd7.settlement_reserved_cells.is_empty(), "V7 leaves settlement_reserved_cells empty")
