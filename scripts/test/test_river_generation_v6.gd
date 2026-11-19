extends SceneTree

const WorldGenerator = preload("res://scripts/world/world_generator.gd")
const WorldViewScene = preload("res://scenes/world/world_view.tscn")

var _passed: int = 0
var _failed: int = 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] ", msg)
	else:
		_failed += 1
		printerr("  [FAIL] ", msg)

func _fingerprint_world(wd: WorldGenerator.WorldData) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("%dx%d:v%d:spawn=%d,%d" % [wd.map_width, wd.map_height, wd.generator_version, wd.center_spawn.x, wd.center_spawn.y]).to_utf8_buffer())
	var t_ctx := HashingContext.new()
	t_ctx.start(HashingContext.HASH_SHA256)
	var b_ctx := HashingContext.new()
	b_ctx.start(HashingContext.HASH_SHA256)
	var e_ctx := HashingContext.new()
	e_ctx.start(HashingContext.HASH_SHA256)
	for x in range(wd.map_width):
		var t_row := PackedByteArray()
		var b_row := PackedByteArray()
		var e_parts: PackedStringArray = []
		for y in range(wd.map_height):
			t_row.append(int(wd.terrain[x][y]))
			b_row.append(wd.get_biome(Vector2i(x, y)))
			var ev: float = float(wd.elevation_grid[x][y]) if x < wd.elevation_grid.size() and y < wd.elevation_grid[x].size() else 0.0
			e_parts.append("%.6f" % ev)
		t_ctx.update(t_row)
		b_ctx.update(b_row)
		e_ctx.update((",".join(e_parts) + ";").to_utf8_buffer())
	var r_ctx := HashingContext.new()
	r_ctx.start(HashingContext.HASH_SHA256)
	var r_sorted: Array[Vector2i] = wd.river_cells.duplicate()
	r_sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	for c in r_sorted:
		r_ctx.update(("%d,%d;" % [c.x, c.y]).to_utf8_buffer())
	var l_ctx := HashingContext.new()
	l_ctx.start(HashingContext.HASH_SHA256)
	var l_sorted: Array[Vector2i] = wd.lake_cells.duplicate()
	l_sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	for c in l_sorted:
		l_ctx.update(("%d,%d;" % [c.x, c.y]).to_utf8_buffer())
	var p_ctx := HashingContext.new()
	p_ctx.start(HashingContext.HASH_SHA256)
	var p_strs: Array[String] = []
	for p in wd.props:
		var pc: Vector2i = p.get("cell", Vector2i(-1, -1))
		p_strs.append("%s@%d,%d" % [str(p.get("type", "")), pc.x, pc.y])
	p_strs.sort()
	p_ctx.update((";".join(p_strs)).to_utf8_buffer())
	ctx.update((
		t_ctx.finish().hex_encode().substr(0, 16) +
		b_ctx.finish().hex_encode().substr(0, 16) +
		e_ctx.finish().hex_encode().substr(0, 16) +
		r_ctx.finish().hex_encode().substr(0, 16) +
		l_ctx.finish().hex_encode().substr(0, 16) +
		p_ctx.finish().hex_encode().substr(0, 16)
	).to_utf8_buffer())
	return ctx.finish().hex_encode().substr(0, 16)

func _connected_components(cells: Array[Vector2i], dirs4: Array[Vector2i]) -> Array:
	var cell_set := {}
	for c in cells:
		cell_set[c] = true
	var seen := {}
	var comps := []
	for c in cells:
		if seen.has(c):
			continue
		var comp: Array[Vector2i] = []
		var q: Array[Vector2i] = [c]
		seen[c] = true
		while not q.is_empty():
			var cur: Vector2i = q.pop_front()
			comp.append(cur)
			for d in dirs4:
				var nb := cur + d
				if cell_set.has(nb) and not seen.has(nb):
					seen[nb] = true
					q.append(nb)
		comps.append(comp)
	return comps

func _init() -> void:
	print("=== TEST SUITE: V6 River Generation & V5 Compatibility ===")
	_assert(WorldGenerator.RIVER_FIX_GENERATOR_VERSION == 6, "RIVER_FIX_GENERATOR_VERSION == 6")
	_assert(WorldGenerator.LATEST_GENERATOR_VERSION >= 6, "LATEST_GENERATOR_VERSION >= 6")
	_assert(WorldGenerator.MAX_SUPPORTED_GENERATOR_VERSION >= 6, "MAX_SUPPORTED_GENERATOR_VERSION >= 6")

	# 1. Exact V1-V5 fingerprint preservation
	var expected_v1_4 := {1: "cb759a18da8e740d", 2: "863eac7dc81fada4", 3: "a85cfbceaf2b903c", 4: "1c672c4b563c4f50"}
	for v in expected_v1_4.keys():
		_assert(_fingerprint_world(WorldGenerator.generate(12345, v)) == expected_v1_4[v], "V%d seed 12345 fingerprint preserved" % v)

	var expected_v5 := {
		12345: "d691db1688e8139c",
		42: "d568823f6302b0c0",
		777: "e8cda27c25db8611",
		9999: "c460bc33d3545d6f",
		314159: "87acddb89f46fc3a",
	}
	for s in expected_v5.keys():
		_assert(_fingerprint_world(WorldGenerator.generate(s, 5)) == expected_v5[s], "V5 seed %d fingerprint preserved identically" % s)

	# 2. V6 determinism & valid endpoint / geometry / starter protection across 5 seeds
	var dirs4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var max_river_cells_overall := 0
	for s in [12345, 42, 777, 9999, 314159]:
		var wd1 := WorldGenerator.generate(s, 6)
		var wd2 := WorldGenerator.generate(s, 6)
		_assert(_fingerprint_world(wd1) == _fingerprint_world(wd2), "V6 seed %d is deterministic" % s)
		_assert(wd1.river_cells.size() >= 60, "V6 seed %d has substantial river network (%d cells)" % [s, wd1.river_cells.size()])

		var lake_set := {}
		for lc in wd1.lake_cells:
			lake_set[lc] = true
		var river_set := {}
		var water_occ_ok := true
		for rc in wd1.river_cells:
			river_set[rc] = true
			if not wd1.is_in_bounds(rc) or wd1.terrain[rc.x][rc.y] != WorldGenerator.TerrainType.WATER or not wd1.occupancy[rc.x][rc.y]:
				water_occ_ok = false
		_assert(water_occ_ok, "V6 seed %d river cells are in-bounds WATER with occupancy=true" % s)

		var comps := _connected_components(wd1.river_cells, dirs4)
		_assert(comps.size() >= 2, "V6 seed %d generates multiple distinct river systems (%d)" % [s, comps.size()])
		var all_valid_term := true
		for comp in comps:
			if comp.size() > max_river_cells_overall:
				max_river_cells_overall = comp.size()
			var touches_ext := false
			for p in comp:
				if p.x <= 1 or p.y <= 1 or p.x >= wd1.map_width - 2 or p.y >= wd1.map_height - 2:
					touches_ext = true
					break
				for d in dirs4:
					var nb: Vector2i = p + d
					if wd1.is_in_bounds(nb) and wd1.terrain[nb.x][nb.y] == WorldGenerator.TerrainType.WATER and not river_set.has(nb):
						touches_ext = true
						break
				if touches_ext:
					break
			if not touches_ext:
				all_valid_term = false
		_assert(all_valid_term, "V6 seed %d all river components terminate at lake, ocean/coast, or map edge" % s)

		# Starter 13x13 Grassland & dry buildings
		var grass_13 := 0
		for dx in range(-6, 7):
			for dy in range(-6, 7):
				var p := wd1.center_spawn + Vector2i(dx, dy)
				if wd1.is_in_bounds(p) and wd1.get_biome(p) == WorldGenerator.BiomeType.GRASSLAND:
					grass_13 += 1
		var flooded_bld := 0
		for bld in wd1.buildings:
			var bp: Vector2i = bld["cell"]
			var bs: Vector2i = bld.get("size", Vector2i.ONE)
			for dx in range(bs.x):
				for dy in range(bs.y):
					if wd1.terrain[bp.x + dx][bp.y + dy] == WorldGenerator.TerrainType.WATER:
						flooded_bld += 1
		_assert(grass_13 == 169 and flooded_bld == 0, "V6 seed %d starter 13x13 Grassland (169/169) and 0 flooded buildings" % s)
	_assert(max_river_cells_overall >= 60, "V6 produces long river systems across test set (max=%d cells)" % max_river_cells_overall)

	# 3. Save/Load preservation for V5 and V6
	_run_save_load_tests()

func _run_save_load_tests() -> void:
	var wv: Node = WorldViewScene.instantiate()
	wv.world_seed = 12345
	wv.world_generator_version = 6
	root.add_child(wv)
	await process_frame
	await process_frame
	_assert(wv.world_data.generator_version == 6, "Explicit V6 WorldView creates V6")
	var v6_fp := _fingerprint_world(wv.world_data)
	var save_v6 := SaveManager.save_to_file(wv, "user://test_v6_preserve.json")
	_assert(bool(save_v6.get("success", false)), "Save V6 succeeds")

	# Load V5 explicitly and verify it stays V5 (not promoted to V6)
	var wv5: Node = WorldViewScene.instantiate()
	wv5.world_seed = 12345
	wv5.world_generator_version = 5
	root.add_child(wv5)
	await process_frame
	var v5_fp := _fingerprint_world(wv5.world_data)
	var save_v5 := SaveManager.save_to_file(wv5, "user://test_v5_preserve.json")
	_assert(bool(save_v5.get("success", false)), "Save V5 succeeds")
	wv5.queue_free()
	await process_frame

	var loaded_v5 := SaveManager.load_from_file("user://test_v5_preserve.json")
	var res5 := SaveManager.apply_loaded_state_to_world(wv, loaded_v5.get("data", {}))
	_assert(bool(res5.get("success", false)) and wv.world_data.generator_version == 5, "Reloading V5 save keeps generator_version == 5")
	_assert(_fingerprint_world(wv.world_data) == v5_fp, "Reloaded V5 world matches exact frozen V5 fingerprint")

	var loaded_v6 := SaveManager.load_from_file("user://test_v6_preserve.json")
	var res6 := SaveManager.apply_loaded_state_to_world(wv, loaded_v6.get("data", {}))
	_assert(bool(res6.get("success", false)) and wv.world_data.generator_version == 6, "Reloading V6 save keeps generator_version == 6")
	_assert(_fingerprint_world(wv.world_data) == v6_fp, "Reloaded V6 world matches exact V6 fingerprint")

	wv.queue_free()
	await process_frame
	print("========================================================")
	print("V6 RIVER GENERATION RESULTS: %d passed, %d failed" % [_passed, _failed])
	print("========================================================")
	quit(0 if _failed == 0 else 1)
