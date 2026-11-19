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
	print("  TEST SUITE: World Size Compatibility & TileMapLayer")
	print("========================================================")

	_test_world_generator_dimensions()
	_test_iso_math_and_camera_bounds()
	_test_fog_territory_and_poi_128()
	await _test_world_view_and_save_load_compatibility()

	print("--------------------------------------------------------")
	print("  Results: %d passed, %d failed" % [_passed, _failed])
	print("========================================================")
	quit(1 if _failed > 0 else 0)

func _test_world_generator_dimensions() -> void:
	print("\n[1] WorldGenerator 128x128 & Legacy 64x64")
	var wd128 := WorldGenerator.generate(12345)
	_assert(wd128 != null, "Default WorldGenerator.generate() succeeds")
	_assert(wd128.map_width == 128 and wd128.map_height == 128, "Default new world is 128x128 (got %dx%d)" % [wd128.map_width, wd128.map_height])
	_assert(wd128.generator_version == WorldGenerator.LATEST_GENERATOR_VERSION, "Default generator_version is LATEST (%d)" % WorldGenerator.LATEST_GENERATOR_VERSION)
	_assert(wd128.terrain.size() == 128 and wd128.terrain[0].size() == 128, "Terrain grid is 128x128")
	_assert(wd128.occupancy.size() == 128 and wd128.occupancy[0].size() == 128, "Occupancy grid is 128x128")
	_assert(wd128.center_spawn == Vector2i(64, 65), "128x128 center_spawn is (64, 65)")
	_assert(wd128.townhall_anchor == Vector2i(63, 62), "128x128 townhall_anchor is (63, 62)")

	for ver in [1, 2, 3]:
		var wd64 := WorldGenerator.generate(12345, ver)
		_assert(wd64 != null and wd64.map_width == 64 and wd64.map_height == 64, "Legacy v%d generates 64x64" % ver)
		_assert(wd64.center_spawn == Vector2i(32, 33), "Legacy v%d center_spawn is (32, 33)" % ver)
		_assert(wd64.townhall_anchor == Vector2i(31, 30), "Legacy v%d townhall_anchor is (31, 30)" % ver)

func _test_iso_math_and_camera_bounds() -> void:
	print("\n[2] IsoMath & CameraController Dynamic Bounds")
	IsoMath.set_active_map_dimensions(128, 128)
	_assert(IsoMath.is_in_bounds(Vector2i(0, 0)), "(0,0) in 128x128 bounds")
	_assert(IsoMath.is_in_bounds(Vector2i(127, 127)), "(127,127) in 128x128 bounds")
	_assert(not IsoMath.is_in_bounds(Vector2i(128, 127)), "(128,127) out of 128x128 bounds")
	_assert(IsoMath.clamp_grid(Vector2i(200, -5)) == Vector2i(127, 0), "clamp_grid clamps to (127, 0) on 128x128")

	IsoMath.set_active_map_dimensions(64, 64)
	_assert(IsoMath.is_in_bounds(Vector2i(63, 63)), "(63,63) in 64x64 bounds")
	_assert(not IsoMath.is_in_bounds(Vector2i(64, 64)), "(64,64) out of 64x64 bounds")

	var cam := CameraController.new()
	cam.auto_center_on_start = false
	cam.set_map_dimensions(128, 128)
	cam.focus_on_cell(Vector2i(127, 0))
	var right_128 := IsoMath.map_to_local(Vector2i(127, 0))
	_assert(cam.position.is_equal_approx(right_128), "Camera reaches (127, 0) on 128x128 without clamping back to 64x64")
	cam.set_map_dimensions(64, 64)
	var right_64 := IsoMath.map_to_local(Vector2i(63, 0))
	_assert(cam.position.x <= right_64.x + 192.1, "Camera clamps back into 64x64 extents when resized to 64x64")
	cam.free()

func _test_fog_territory_and_poi_128() -> void:
	print("\n[3] FogOfWar, TerritoryManager, BuildingSystem, POIManager on 128x128")
	var wd := WorldGenerator.generate(12345)
	IsoMath.set_active_map_dimensions(128, 128)
	var fow := FogOfWar.new(128, 128)
	fow.reveal_circle(Vector2i(125, 125), 2)
	_assert(fow.is_visible(Vector2i(125, 125)), "FogOfWar reveals outer 128x128 corner cell (125,125)")
	_assert(not fow.is_visible(Vector2i(128, 128)), "FogOfWar rejects out-of-bounds (128,128)")

	var tm_script := load("res://scripts/world/territory_manager.gd")
	var tm = tm_script.new()
	tm.initialize(wd)
	var t_info: Dictionary = tm.recalculate_territory()
	_assert(int(t_info.get("owned_count", 0)) > 0, "TerritoryManager computes owned_count > 0 on 128x128")
	_assert(wd.owned_cells.size() == 128 and wd.owned_cells[0].size() == 128, "owned_cells grid is 128x128")
	_assert(tm.is_cell_owned(wd.townhall_anchor), "128x128 Town Hall anchor is owned")

	wd.buildings.append({"id": "m1", "type": "market", "cell": Vector2i(70, 70), "state": "active"})
	wd.buildings.append({"id": "m2", "type": "market", "cell": Vector2i(60, 65), "state": "active"})
	var markets := BuildingSystem.get_all_active_markets(wd)
	_assert(markets.size() == 2 and str(markets[0].get("id")) == "m2", "get_all_active_markets sorts with dynamic map_width")

	var nav := GridNavigation.new(wd)
	var walkable: Array[Vector2i] = []
	for x in range(128):
		for y in range(128):
			var c := Vector2i(x, y)
			if nav.is_walkable(c):
				walkable.append(c)
	var poi_mgr := POIManager.new()
	poi_mgr.generate_pois(12345, walkable, 4)
	_assert(poi_mgr._pois.size() == 4, "POIManager generates 4 POIs on 128x128")

func _test_world_view_and_save_load_compatibility() -> void:
	print("\n[4] WorldView TileMapLayer + Legacy 64x64 & 128x128 Save/Load Round-Trip")
	var wv_scene := load("res://scenes/world/world_view.tscn") as PackedScene
	var wv := wv_scene.instantiate()
	root.add_child(wv)
	await process_frame

	_assert(wv.world_data != null and wv.world_data.map_width == 128 and wv.world_data.map_height == 128, "WorldView initializes 128x128 by default")
	var terrain_layer := wv.get_node_or_null("World/TerrainLayer")
	_assert(terrain_layer != null and terrain_layer.get_child_count() == 1, "TerrainLayer has exactly 1 child node (got %d)" % (terrain_layer.get_child_count() if terrain_layer != null else -1))
	_assert(terrain_layer != null and terrain_layer.get_child(0) is TileMapLayer, "TerrainLayer child is TileMapLayer")
	var tml := terrain_layer.get_child(0) as TileMapLayer
	_assert(tml.get_used_cells().size() == 128 * 128, "TileMapLayer renders all 16,384 cells on 128x128")

	# Save 128x128 state
	var save_128: Dictionary = SaveManager.serialize_world_state(wv)
	var meta_128: Dictionary = save_128.get("metadata", {})
	_assert(int(meta_128.get("map_width", -1)) == 128 and int(meta_128.get("map_height", -1)) == 128, "SaveManager serializes map_width=128, map_height=128")

	# Construct synthetic legacy 64x64 v3 save (without map_width/map_height metadata)
	var legacy_wv := wv_scene.instantiate()
	legacy_wv.world_generator_version = 3
	root.add_child(legacy_wv)
	await process_frame
	var save_64: Dictionary = SaveManager.serialize_world_state(legacy_wv)
	var meta_64: Dictionary = save_64.get("metadata", {})
	meta_64.erase("map_width")
	meta_64.erase("map_height")
	save_64["metadata"] = meta_64

	# Load legacy 64x64 save into the 128x128 WorldView
	var load_64_res: Dictionary = SaveManager.apply_loaded_state_to_world(wv, save_64)
	await process_frame
	_assert(bool(load_64_res.get("success", false)), "Loading legacy 64x64 save into 128x128 WorldView succeeds")
	_assert(wv.world_data.map_width == 64 and wv.world_data.map_height == 64, "WorldView shrinks back to 64x64 on legacy save load")
	_assert(wv.world_data.townhall_anchor == Vector2i(31, 30), "Legacy 64x64 Town Hall anchor preserved at (31, 30)")
	_assert(wv.fog_of_war.map_width == 64 and wv.fog_of_war.map_height == 64, "FogOfWar resizes to 64x64 on legacy save load")
	_assert(IsoMath.get_active_map_width() == 64, "IsoMath active dimensions updated to 64x64")
	var tml_64 := terrain_layer.get_child(terrain_layer.get_child_count() - 1) as TileMapLayer
	_assert(tml_64 != null and tml_64.get_used_cells().size() == 64 * 64, "TileMapLayer renders 4,096 cells after loading legacy 64x64 save")

	# Load 128x128 save back into WorldView
	var load_128_res: Dictionary = SaveManager.apply_loaded_state_to_world(wv, save_128)
	await process_frame
	_assert(bool(load_128_res.get("success", false)), "Reloading 128x128 save succeeds")
	_assert(wv.world_data.map_width == 128 and wv.world_data.map_height == 128, "WorldView restores 128x128 dimensions")
	_assert(wv.world_data.townhall_anchor == Vector2i(63, 62), "128x128 Town Hall anchor preserved at (63, 62)")
	_assert(wv.fog_of_war.map_width == 128 and wv.fog_of_war.map_height == 128, "FogOfWar restores 128x128 dimensions")

	legacy_wv.queue_free()
	wv.queue_free()
	await process_frame
