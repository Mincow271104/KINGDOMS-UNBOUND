extends SceneTree

const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const GridNavigationScript = preload("res://scripts/navigation/grid_navigation.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")
const BattleResolverScript = preload("res://scripts/combat/battle_resolver.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const CitizenControllerScript = preload("res://scripts/entities/citizen_controller.gd")

const TEST_SEEDS: Array[int] = [0, 1, 42, 12345, 99999, 202611]

var _assertions: int = 0
var _failures: int = 0

func _assert_true(cond: bool, msg: String) -> void:
	_assertions += 1
	if not cond:
		_failures += 1
		printerr("[FAIL] %s" % msg)

func _assert_eq(a, b, msg: String) -> void:
	_assertions += 1
	if a != b:
		_failures += 1
		printerr("[FAIL] %s (got=%s expected=%s)" % [msg, str(a), str(b)])

func _fingerprint_world(wd: WorldGenerator.WorldData) -> String:
	var parts: PackedStringArray = []
	parts.append("v=%d;s=%d;cs=%d,%d" % [wd.generator_version, wd.seed_value, wd.center_spawn.x, wd.center_spawn.y])
	for x in range(WorldGeneratorScript.MAP_SIZE):
		var row := PackedStringArray()
		for y in range(WorldGeneratorScript.MAP_SIZE):
			row.append("%d:%d" % [int(wd.terrain[x][y]), 1 if wd.occupancy[x][y] else 0])
		parts.append(",".join(row))
	for p in wd.props:
		var c: Vector2i = p["cell"]
		parts.append("p:%s@%d,%d" % [p["type"], c.x, c.y])
	for b in wd.buildings:
		var bc: Vector2i = b["cell"]
		var bs: Vector2i = b["size"]
		parts.append("b:%s@%d,%d(%dx%d)" % [b["type"], bc.x, bc.y, bs.x, bs.y])
	return "|".join(parts).sha256_text()

func _init() -> void:
	print("--- Running Batch 03C World Generator Versioning & Terrain Corrective Suite ---")
	call_deferred("_run_all")

func _run_all() -> void:
	await process_frame
	_test_version_dispatch_and_reproducibility()
	_test_v3_neutral_settlement_six_seeds()
	_test_mountain_navigation_and_building_rules()
	_test_combat_terrain_rules()
	await _test_save_load_version_lifecycle()

	print("=== Batch 03C Suite Summary: %d assertions, %d failures ===" % [_assertions, _failures])
	quit(0 if _failures == 0 else 1)

func _test_version_dispatch_and_reproducibility() -> void:
	print("[Test 1] Version dispatch, V1/V2/V3/Latest reproducibility & unsupported version safety...")
	var latest_ver: int = WorldGeneratorScript.LATEST_GENERATOR_VERSION
	_assert_true(latest_ver >= 7, "Latest generator version is at least V7 (got=%d)" % latest_ver)
	for v in range(1, latest_ver + 1):
		_assert_true(WorldGeneratorScript.is_supported_generator_version(v), "V%d supported" % v)
	_assert_true(not WorldGeneratorScript.is_supported_generator_version(0), "V0 unsupported")
	_assert_true(not WorldGeneratorScript.is_supported_generator_version(latest_ver + 1), "V%d unsupported" % (latest_ver + 1))

	# Missing metadata returns AMBIGUOUS_MISSING; explicit returns EXPLICIT_SUPPORTED
	var res_missing: Dictionary = SaveManagerScript.resolve_save_generator_version({})
	_assert_eq(int(res_missing.get("status", -1)), SaveManagerScript.GeneratorVersionStatus.AMBIGUOUS_MISSING, "Missing world_generator_version returns AMBIGUOUS_MISSING")
	_assert_eq(int(SaveManagerScript.resolve_save_generator_version({"world_generator_version": 1}).get("version", -1)), 1, "Explicit V1 resolves to 1")
	_assert_eq(int(SaveManagerScript.resolve_save_generator_version({"world_generator_version": 2}).get("version", -1)), 2, "Explicit V2 resolves to 2")
	_assert_eq(int(SaveManagerScript.resolve_save_generator_version({"world_generator_version": 3}).get("version", -1)), 3, "Explicit V3 resolves to 3")

	for s in TEST_SEEDS:
		var v1_a := WorldGeneratorScript.generate(s, 1)
		var v1_b := WorldGeneratorScript.generate(s, 1)
		_assert_eq(v1_a.generator_version, 1, "V1 sets generator_version=1 for seed %d" % s)
		_assert_eq(_fingerprint_world(v1_a), _fingerprint_world(v1_b), "V1 deterministic for seed %d" % s)

		# V1 must contain only TerrainType 0..3 (no HILLS=4 or MOUNTAINS=5)
		var v1_has_elev := false
		for x in range(WorldGeneratorScript.MAP_SIZE):
			for y in range(WorldGeneratorScript.MAP_SIZE):
				if int(v1_a.terrain[x][y]) >= 4:
					v1_has_elev = true
		_assert_true(not v1_has_elev, "V1 contains zero Hills/Mountains for seed %d" % s)

		var v2_a := WorldGeneratorScript.generate(s, 2)
		var v2_b := WorldGeneratorScript.generate(s, 2)
		_assert_eq(v2_a.generator_version, 2, "V2 sets generator_version=2 for seed %d" % s)
		_assert_eq(_fingerprint_world(v2_a), _fingerprint_world(v2_b), "V2 deterministic for seed %d" % s)

		# V2 Mountains must preserve occupancy=true
		var v2_mtn_occ_ok := true
		for x in range(WorldGeneratorScript.MAP_SIZE):
			for y in range(WorldGeneratorScript.MAP_SIZE):
				if v2_a.terrain[x][y] == WorldGeneratorScript.TerrainType.MOUNTAINS and not v2_a.occupancy[x][y]:
					v2_mtn_occ_ok = false
		_assert_true(v2_mtn_occ_ok, "V2 Mountains keep occupancy=true for seed %d" % s)

		var v3_a := WorldGeneratorScript.generate(s, 3)
		var v3_b := WorldGeneratorScript.generate(s, 3)
		var latest_a := WorldGeneratorScript.generate(s, latest_ver)
		var latest_def := WorldGeneratorScript.generate(s)
		_assert_eq(v3_a.generator_version, 3, "V3 sets generator_version=3 for seed %d" % s)
		_assert_eq(_fingerprint_world(v3_a), _fingerprint_world(v3_b), "V3 deterministic for seed %d" % s)
		_assert_eq(latest_def.generator_version, latest_ver, "Default generate(seed) sets generator_version=%d for seed %d" % [latest_ver, s])
		_assert_eq(_fingerprint_world(latest_a), _fingerprint_world(latest_def), "Default generate(seed) dispatches to latest V%d for seed %d" % [latest_ver, s])

func _test_v3_neutral_settlement_six_seeds() -> void:
	print("[Test 2] V3 Neutral Settlement (16,48) land, prop, overlap & BFS connectivity...")
	for s in TEST_SEEDS:
		var wd := WorldGeneratorScript.generate(s, 3)
		var nav := GridNavigationScript.new(wd)
		var bad_cells: int = 0
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				var cx: int = 16 + dx
				var cy: int = 48 + dy
				var t: int = int(wd.terrain[cx][cy])
				if t == WorldGeneratorScript.TerrainType.WATER or t == WorldGeneratorScript.TerrainType.MOUNTAINS:
					bad_cells += 1
				if wd.occupancy[cx][cy]:
					bad_cells += 1
		_assert_eq(bad_cells, 0, "V3 Neutral region (16,48)+/-2 has zero Water/Mountains/blocking props for seed %d" % s)

		var path := nav.find_path(wd.center_spawn, Vector2i(16, 48))
		_assert_true(path.size() > 0, "V3 Neutral anchor (16,48) reachable from center_spawn for seed %d" % s)

		# Verify no overlap with starter buildings
		var overlaps_starter := false
		for b in wd.buildings:
			var o: Vector2i = b["cell"]
			var sz: Vector2i = b["size"]
			for ox in range(sz.x):
				for oy in range(sz.y):
					var c := o + Vector2i(ox, oy)
					if abs(c.x - 16) <= 2 and abs(c.y - 48) <= 2:
						overlaps_starter = true
		_assert_true(not overlaps_starter, "V3 Neutral region does not overlap starter buildings for seed %d" % s)

func _test_mountain_navigation_and_building_rules() -> void:
	print("[Test 3] Mountain traversal, cost=3, speed parity, and Town Hall-only Mountain ban...")
	var wd := WorldGeneratorScript.generate(12345, 3)
	for x in range(8, 22):
		for y in range(8, 22):
			wd.terrain[x][y] = WorldGeneratorScript.TerrainType.GRASS
			wd.occupancy[x][y] = false

	# Create a corridor test: row y=10 is GRASS (cost 1), row y=11 is HILLS (cost 2), row y=12 is MOUNTAINS (cost 3)
	for x in range(10, 16):
		wd.terrain[x][11] = WorldGeneratorScript.TerrainType.HILLS
		wd.terrain[x][12] = WorldGeneratorScript.TerrainType.MOUNTAINS
	wd.terrain[14][14] = WorldGeneratorScript.TerrainType.WATER
	wd.occupancy[14][14] = true

	var nav := GridNavigationScript.new(wd)
	_assert_eq(nav.get_movement_cost(Vector2i(12, 10)), 1, "GRASS cost == 1")
	_assert_eq(nav.get_movement_cost(Vector2i(12, 11)), 2, "HILLS cost == 2")
	_assert_eq(nav.get_movement_cost(Vector2i(12, 12)), 3, "MOUNTAINS cost == 3")
	_assert_true(nav.is_cell_walkable(Vector2i(12, 12)), "V3 MOUNTAINS is walkable")
	_assert_true(not nav.is_cell_walkable(Vector2i(14, 14)), "WATER remains unwalkable")

	# Path across pure Mountain is valid when forced
	for x in range(10, 16):
		wd.occupancy[x][10] = true
		wd.occupancy[x][11] = true
		wd.occupancy[x][9] = true
		wd.occupancy[x][13] = true
	wd.occupancy[10][12] = false
	wd.occupancy[15][12] = false
	var mtn_path := nav.find_path(Vector2i(10, 12), Vector2i(15, 12))
	_assert_true(mtn_path.size() >= 6, "Pathfinder traverses Mountain corridor when other routes blocked")

	# Citizen physical speed: Hills=0.75x, Mountains=1.0x (no double penalty)
	var cit := CitizenControllerScript.new()
	cit.world_data = wd
	cit.move_speed_px = 100.0
	cit.current_cell = Vector2i(12, 10)
	_assert_eq(cit.get_effective_move_speed(), 100.0, "Citizen speed on GRASS == 100.0")
	cit.current_cell = Vector2i(12, 11)
	_assert_eq(cit.get_effective_move_speed(), 75.0, "Citizen speed on HILLS == 75.0 (0.75x)")
	cit.current_cell = Vector2i(12, 12)
	_assert_eq(cit.get_effective_move_speed(), 100.0, "Citizen speed on MOUNTAINS == 100.0 (no extra speed penalty)")
	cit.free()

	# Building rules: Town Hall rejected on Mountains; non-Town Hall allowed on Mountains
	var rm = root.get_node_or_null("ResourceManager")
	if rm != null:
		rm.add_resource("wood", 1000)
		rm.add_resource("stone", 1000)
		for x in range(16, 21):
			for y in range(16, 21):
				wd.terrain[x][y] = WorldGeneratorScript.TerrainType.MOUNTAINS
				wd.occupancy[x][y] = false
		var th_res := BuildingSystemScript.can_place_building("townhall", Vector2i(17, 17), wd, rm)
		_assert_true(not bool(th_res.get("valid", true)), "Town Hall rejected on MOUNTAINS (GDD §3.3)")
		var wt_res := BuildingSystemScript.can_place_building("watchtower", Vector2i(17, 17), wd, rm)
		_assert_true(bool(wt_res.get("valid", false)), "Watchtower allowed on unoccupied MOUNTAINS")
		var acc := BuildingSystemScript.find_access_cell(Vector2i(17, 17), Vector2i(1, 1), wd)
		_assert_true(acc != Vector2i(-1, -1), "find_access_cell succeeds on adjacent MOUNTAINS")

func _test_combat_terrain_rules() -> void:
	print("[Test 4] Combat terrain rules (no Hills 1.15x, Water 1.15x preserved)...")
	var wd := WorldGeneratorScript.generate(12345, 3)
	_assert_eq(BattleResolverScript.calculate_settlement_terrain_multiplier(wd), 1.0, "Flat starter settlement == 1.0")
	wd.terrain[30][30] = WorldGeneratorScript.TerrainType.HILLS
	_assert_eq(BattleResolverScript.calculate_settlement_terrain_multiplier(wd), 1.0, "HILLS adjacent to Town Hall == 1.0 (removed)")
	wd.terrain[30][30] = WorldGeneratorScript.TerrainType.WATER
	_assert_eq(BattleResolverScript.calculate_settlement_terrain_multiplier(wd), 1.15, "WATER adjacent to Town Hall == 1.15")

func _test_save_load_version_lifecycle() -> void:
	print("[Test 5] Isolated save/load version lifecycle & unsupported version safety...")
	var wv_scene := load("res://scenes/world/world_view.tscn")
	var wv: Node = wv_scene.instantiate()
	wv.set("world_seed", 42)
	root.add_child(wv)
	await process_frame
	await process_frame

	# New world must match LATEST_GENERATOR_VERSION
	var latest_ver: int = WorldGeneratorScript.LATEST_GENERATOR_VERSION
	_assert_eq(int(wv.world_data.generator_version), latest_ver, "New WorldView defaults to V%d" % latest_ver)
	var latest_save: Dictionary = SaveManagerScript.serialize_world_state(wv)
	_assert_eq(int(latest_save["metadata"].get("world_generator_version", -1)), latest_ver, "Serialized save contains world_generator_version=%d" % latest_ver)
	_assert_true(bool(SaveManagerScript.validate_save_data(latest_save).get("valid", false)), "Latest save validates cleanly")

	# Unversioned legacy fixture (no world_generator_version key) -> must reconstruct V1 and retain V1 on resave
	var unversioned_v1 := latest_save.duplicate(true)
	unversioned_v1["metadata"].erase("world_generator_version")
	unversioned_v1["metadata"]["world_seed"] = 99999
	unversioned_v1["resources"]["stock"]["wood"] = 777
	_assert_true(bool(SaveManagerScript.validate_save_data(unversioned_v1).get("valid", false)), "Unversioned legacy save validates cleanly")

	var apply_unres := SaveManagerScript.apply_loaded_state_to_world(wv, unversioned_v1)
	_assert_true(not bool(apply_unres.get("success", true)) and bool(apply_unres.get("requires_generator_resolution", false)), "Unversioned legacy save requires explicit V1/V2 resolution before load")

	var apply_v1 := SaveManagerScript.apply_loaded_state_to_world(wv, unversioned_v1, false, 1)
	_assert_true(bool(apply_v1.get("success", false)), "Unversioned legacy save loads cleanly after explicit V1 selection")
	_assert_eq(int(wv.world_data.generator_version), 1, "Unversioned legacy save reconstructs V1")
	_assert_eq(int(wv.world_data.seed_value), 99999, "Loaded seed restored")
	var expected_v1_fp := _fingerprint_world(WorldGeneratorScript.generate(99999, 1))
	# Note: buildings in wv.world_data may carry runtime IDs/state after apply_loaded_state, so verify terrain & props match V1
	var v1_ref := WorldGeneratorScript.generate(99999, 1)
	var v1_terrain_diffs: int = 0
	for x in range(WorldGeneratorScript.MAP_SIZE):
		for y in range(WorldGeneratorScript.MAP_SIZE):
			if wv.world_data.terrain[x][y] != v1_ref.terrain[x][y]:
				v1_terrain_diffs += 1
	_assert_eq(v1_terrain_diffs, 0, "Loaded unversioned save terrain matches exact V1 terrain for seed 99999")
	_assert_eq(wv.world_data.props.size(), v1_ref.props.size(), "Loaded unversioned save props match V1 prop count")
	var rm = root.get_node_or_null("ResourceManager")
	if rm != null:
		_assert_eq(int(rm.get_resource("wood")), 777, "Loaded resource stock (777 wood) preserved, not reset")

	var resaved_v1: Dictionary = SaveManagerScript.serialize_world_state(wv)
	_assert_eq(int(resaved_v1["metadata"].get("world_generator_version", -1)), 1, "Resaved V1 world retains world_generator_version=1")

	# Explicit V2 fixture -> reconstructs V2 and retains V2 on resave
	var v2_fixture := latest_save.duplicate(true)
	v2_fixture["metadata"]["world_generator_version"] = 2
	v2_fixture["metadata"]["world_seed"] = 12345
	var apply_v2 := SaveManagerScript.apply_loaded_state_to_world(wv, v2_fixture)
	_assert_true(bool(apply_v2.get("success", false)), "Explicit V2 save loads cleanly")
	_assert_eq(int(wv.world_data.generator_version), 2, "Explicit V2 save reconstructs V2")
	var resaved_v2: Dictionary = SaveManagerScript.serialize_world_state(wv)
	_assert_eq(int(resaved_v2["metadata"].get("world_generator_version", -1)), 2, "Resaved V2 world retains world_generator_version=2")

	# Explicit V3 fixture -> reconstructs V3 and retains V3 on resave
	var v3_fixture := latest_save.duplicate(true)
	v3_fixture["metadata"]["world_generator_version"] = 3
	v3_fixture["metadata"]["world_seed"] = 42
	var apply_v3 := SaveManagerScript.apply_loaded_state_to_world(wv, v3_fixture)
	_assert_true(bool(apply_v3.get("success", false)), "Explicit V3 save loads cleanly")
	_assert_eq(int(wv.world_data.generator_version), 3, "Explicit V3 save reconstructs V3")
	var resaved_v3: Dictionary = SaveManagerScript.serialize_world_state(wv)
	_assert_eq(int(resaved_v3["metadata"].get("world_generator_version", -1)), 3, "Resaved V3 world retains world_generator_version=3")

	# Reload latest save -> reconstructs latest_ver
	var apply_latest := SaveManagerScript.apply_loaded_state_to_world(wv, latest_save)
	_assert_true(bool(apply_latest.get("success", false)), "Latest save reloads cleanly")
	_assert_eq(int(wv.world_data.generator_version), latest_ver, "Latest save reconstructs V%d" % latest_ver)

	# Unsupported future version -> fails safely without mutating live world
	var future_save := latest_save.duplicate(true)
	future_save["metadata"]["world_generator_version"] = 99
	var future_val := SaveManagerScript.validate_save_data(future_save)
	_assert_true(not bool(future_val.get("valid", true)), "Unsupported future version (99) rejected by validate_save_data")
	var future_apply := SaveManagerScript.apply_loaded_state_to_world(wv, future_save)
	_assert_true(not bool(future_apply.get("success", true)), "Unsupported future version (99) rejected by apply_loaded_state_to_world")
	_assert_eq(int(wv.world_data.generator_version), latest_ver, "Live WorldView remains V%d after rejected future save" % latest_ver)
	_assert_eq(int(wv.world_data.seed_value), 42, "Live WorldView seed remains 42 after rejected future save")

	wv.queue_free()
	await process_frame
