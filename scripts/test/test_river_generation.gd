extends SceneTree

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
	print("  TEST SUITE: Phase 2 — River & Lake Generation + V1..V5 Saves")
	print("========================================================")

	_test_rivers_and_lakes_determinism_and_rules()
	_test_starter_reachability_and_resources()
	await _test_v1_to_v5_save_load_compatibility()

	print("--------------------------------------------------------")
	print("  Results: %d passed, %d failed" % [_passed, _failed])
	print("========================================================")
	quit(1 if _failed > 0 else 0)

func _test_rivers_and_lakes_determinism_and_rules() -> void:
	print("\n[1] River & Lake Determinism, Bounds, Continuity & Occupancy")
	var wd1 := WorldGenerator.generate(12345, 5)
	var wd2 := WorldGenerator.generate(12345, 5)
	IsoMath.set_active_map_dimensions(wd1.map_width, wd1.map_height)

	_assert(wd1.river_cells.size() > 30, "V5 generates substantial river network (%d river cells)" % wd1.river_cells.size())
	_assert(wd1.lake_cells.size() > 20, "V5 generates coherent lake basins (%d lake cells)" % wd1.lake_cells.size())
	_assert(wd1.river_cells == wd2.river_cells and wd1.lake_cells == wd2.lake_cells, "Rivers and lakes reproduce identically for same seed")

	var nav := GridNavigation.new(wd1)
	var bad_water := 0
	var bad_continuity := 0
	for rc in wd1.river_cells:
		if not wd1.is_in_bounds(rc) or wd1.terrain[rc.x][rc.y] != WorldGenerator.TerrainType.WATER or not wd1.occupancy[rc.x][rc.y] or nav.is_cell_walkable(rc):
			bad_water += 1
		var has_nb := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = rc + d
			if wd1.is_in_bounds(nb) and wd1.terrain[nb.x][nb.y] == WorldGenerator.TerrainType.WATER:
				has_nb = true
				break
		if not has_nb:
			bad_continuity += 1

	_assert(bad_water == 0, "All river cells are in-bounds, TerrainType.WATER, occupied, and impassable")
	_assert(bad_continuity == 0, "All river cells are 4-connected to adjacent water (no isolated single-cell scratches)")

	var overlap_bld := 0
	for bld in wd1.buildings:
		var org: Vector2i = bld["cell"]
		var sz: Vector2i = bld["size"]
		for ox in range(sz.x):
			for oy in range(sz.y):
				var bc := org + Vector2i(ox, oy)
				if wd1.terrain[bc.x][bc.y] == WorldGenerator.TerrainType.WATER:
					overlap_bld += 1
	_assert(overlap_bld == 0, "No river or lake overwrites starter building footprints")

func _test_starter_reachability_and_resources() -> void:
	print("\n[2] Starter Territory Connectivity & Reachable Starter Props")
	var wd := WorldGenerator.generate(12345, 5)
	IsoMath.set_active_map_dimensions(wd.map_width, wd.map_height)
	var nav := GridNavigation.new(wd)
	var tm = load("res://scripts/world/territory_manager.gd").new()
	tm.initialize(wd)
	var t_info: Dictionary = tm.recalculate_territory()
	_assert(int(t_info.get("owned_count", 0)) == 365, "V5 starter Town Hall projects 365 owned cells")

	# BFS reachable dry land from center_spawn
	var visited: Dictionary = {}
	var q: Array[Vector2i] = [wd.center_spawn]
	visited[wd.center_spawn] = true
	var head := 0
	while head < q.size():
		var cur: Vector2i = q[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nxt: Vector2i = cur + d
			if wd.is_in_bounds(nxt) and not visited.has(nxt) and wd.terrain[nxt.x][nxt.y] != WorldGenerator.TerrainType.WATER:
				visited[nxt] = true
				q.append(nxt)
	_assert(visited.size() > 3000, "Large contiguous dry mainland reachable from center_spawn (%d cells)" % visited.size())

	var reachable_trees := 0
	var reachable_rocks := 0
	for p in wd.props:
		var pc: Vector2i = p["cell"]
		if wd.center_spawn.distance_to(pc) <= 18.0:
			if str(p.get("type")) == "tree":
				reachable_trees += 1
			elif str(p.get("type")) == "rock":
				reachable_rocks += 1
	_assert(reachable_trees >= 4 and reachable_rocks >= 2, "Starter region has reachable trees (%d) and rocks (%d)" % [reachable_trees, reachable_rocks])

func _test_v1_to_v5_save_load_compatibility() -> void:
	print("\n[3] V1-V5 Save/Load Compatibility & Non-Upgrade Verification")
	var wv_scene := load("res://scenes/world/world_view.tscn") as PackedScene
	var wv := wv_scene.instantiate()
	root.add_child(wv)
	await process_frame

	_assert(wv.world_data.generator_version == WorldGenerator.LATEST_GENERATOR_VERSION and wv.world_data.map_width == 128, "New WorldView defaults to V%d 128x128" % WorldGenerator.LATEST_GENERATOR_VERSION)
	var v5_save: Dictionary = SaveManager.serialize_world_state(wv)
	var orig_river_count: int = wv.world_data.river_cells.size()
	var orig_biome_sample: int = wv.world_data.get_biome(Vector2i(15, 15))

	# Load V4 save -> must stay V4 without V5 biomes/rivers
	var wv4 := wv_scene.instantiate()
	wv4.world_generator_version = 4
	root.add_child(wv4)
	await process_frame
	var v4_save: Dictionary = SaveManager.serialize_world_state(wv4)
	wv4.queue_free()
	await process_frame

	var res4: Dictionary = SaveManager.apply_loaded_state_to_world(wv, v4_save)
	await process_frame
	_assert(bool(res4.get("success", false)) and wv.world_data.generator_version == 4 and wv.world_data.biome_grid.is_empty(), "Loading V4 save keeps V4 128x128 without V5 biomes/rivers")

	# Load V3 legacy save -> must shrink to 64x64
	var wv3 := wv_scene.instantiate()
	wv3.world_generator_version = 3
	root.add_child(wv3)
	await process_frame
	var v3_save: Dictionary = SaveManager.serialize_world_state(wv3)
	wv3.queue_free()
	await process_frame

	var res3: Dictionary = SaveManager.apply_loaded_state_to_world(wv, v3_save)
	await process_frame
	_assert(bool(res3.get("success", false)) and wv.world_data.generator_version == 3 and wv.world_data.map_width == 64, "Loading V3 save shrinks to 64x64 cleanly")

	# Reload V5 save -> restores V5 128x128 exact biomes and rivers
	var res5: Dictionary = SaveManager.apply_loaded_state_to_world(wv, v5_save)
	await process_frame
	_assert(bool(res5.get("success", false)) and wv.world_data.generator_version == WorldGenerator.LATEST_GENERATOR_VERSION and wv.world_data.map_width == 128, "Reloading latest save restores V%d 128x128" % WorldGenerator.LATEST_GENERATOR_VERSION)
	_assert(wv.world_data.river_cells.size() == orig_river_count and wv.world_data.get_biome(Vector2i(15, 15)) == orig_biome_sample, "Reloading V5 save restores exact rivers and biome grid")

	wv.queue_free()
	await process_frame
