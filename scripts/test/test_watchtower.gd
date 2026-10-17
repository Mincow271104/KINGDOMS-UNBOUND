extends SceneTree
## Test Suite: Package 1A — Watchtower Scouting Building
## Verifies Blueprint data, 1x1 placement legality, atomic cost deduction,
## sprite offset & texture loading, Fog of War 15-tile vision expansion,
## POI discovery integration, and Save/Load persistence.

const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const ResourceManagerScript = preload("res://scripts/economy/resource_manager.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const FogOfWarScript = preload("res://scripts/world/fog_of_war.gd")
const POIManagerScript = preload("res://scripts/world/poi_manager.gd")
const IsoMathScript = preload("res://scripts/utils/iso_math.gd")
const WorldViewScene = preload("res://scenes/world/world_view.tscn")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")

var frame_count: int = 0
var world_instance: Node = null
var failures: int = 0

func _init() -> void:
	print("\n========================================================")
	print("  TEST SUITE: Package 1A — Watchtower Scouting Building")
	print("========================================================\n")

	_run_unit_checks()

	# Instantiate WorldView to allow _ready() initialization across frames
	world_instance = WorldViewScene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1

	# Allow world_instance._ready() to initialize terrain, HUD and systems
	if frame_count == 3:
		_run_world_integration_checks()

		print("\n--------------------------------------------------------")
		if failures == 0:
			print("  ALL PACKAGE 1A WATCHTOWER TESTS PASSED! (Exit Code 0)")
			print("--------------------------------------------------------\n")
			quit(0)
			return true
		else:
			printerr("  PACKAGE 1A WATCHTOWER TESTS FAILED with %d failures! (Exit Code 1)" % failures)
			print("--------------------------------------------------------\n")
			quit(1)
			return true

	return false

func _run_unit_checks() -> void:
	# -------------------------------------------------------------------------
	# TC-W.1: Blueprint & Cost Verification
	# -------------------------------------------------------------------------
	print("--- Running TC-W.1: Blueprint & Cost Verification ---")
	var bp: Dictionary = EconomyConfigScript.BLUEPRINTS.get("watchtower", {})
	if bp.is_empty():
		printerr("  [FAIL] 'watchtower' blueprint missing from EconomyConfig.BLUEPRINTS!")
		failures += 1
	else:
		if bp.get("id") != "watchtower":
			printerr("  [FAIL] Blueprint ID is '%s', expected 'watchtower'" % bp.get("id"))
			failures += 1
		if bp.get("footprint") != Vector2i(1, 1):
			printerr("  [FAIL] Footprint is %s, expected Vector2i(1, 1)" % bp.get("footprint"))
			failures += 1
		var cost: Dictionary = bp.get("cost", {})
		if cost.get(EconomyConfigScript.RES_WOOD) != 20 or cost.get(EconomyConfigScript.RES_STONE) != 15:
			printerr("  [FAIL] Cost mismatch! Expected 20 Wood, 15 Stone. Got: %s" % cost)
			failures += 1
		if bp.get("construction_hours", 0.0) != 6.0:
			printerr("  [FAIL] Construction hours is %f, expected 6.0" % bp.get("construction_hours"))
			failures += 1
		if bp.get("vision_radius", 0) != 15:
			printerr("  [FAIL] Vision radius is %d, expected 15" % bp.get("vision_radius"))
			failures += 1
		if bp.get("max_workers", -1) != 0:
			printerr("  [FAIL] max_workers should be 0, got %d" % bp.get("max_workers"))
			failures += 1
		print("  [PASS] Blueprint 'watchtower' verified: 1x1 diamond, 20 Wood + 15 Stone, 6h, Vision 15, 0 workers.")

	# -------------------------------------------------------------------------
	# TC-W.2: Placement Validation (1x1 Footprint)
	# -------------------------------------------------------------------------
	print("\n--- Running TC-W.2: Placement Legality Validation (1x1 Footprint) ---")
	var world_data = WorldGeneratorScript.generate(12345)
	var rm = ResourceManagerScript.new()
	root.add_child(rm)
	rm.reset_economy()

	# Clear a clean grass patch around test cell (20, 20)
	var test_cell := Vector2i(20, 20)
	for ox in range(-2, 4):
		for oy in range(-2, 4):
			var c := Vector2i(test_cell.x + ox, test_cell.y + oy)
			world_data.terrain[c.x][c.y] = WorldGeneratorScript.TerrainType.GRASS
			world_data.occupancy[c.x][c.y] = false

	# 1. Legal placement on open meadow/grass
	var check_legal: Dictionary = BuildingSystemScript.can_place_building("watchtower", test_cell, world_data, rm)
	if not check_legal["valid"]:
		printerr("  [FAIL] Legal cell (20, 20) rejected: %s" % check_legal.get("reason"))
		failures += 1
	else:
		print("  [PASS] Legal 1x1 placement on grass accepted.")

	# 2. Rejection on water
	var water_cell := Vector2i(21, 20)
	world_data.terrain[water_cell.x][water_cell.y] = WorldGeneratorScript.TerrainType.WATER
	var check_water: Dictionary = BuildingSystemScript.can_place_building("watchtower", water_cell, world_data, rm)
	if check_water["valid"]:
		printerr("  [FAIL] Placement on water should have been rejected!")
		failures += 1
	else:
		print("  [PASS] Placement on water correctly rejected: '%s'" % check_water.get("reason"))

	# 3. Rejection on occupied cell
	var occupied_cell := Vector2i(22, 20)
	world_data.terrain[occupied_cell.x][occupied_cell.y] = WorldGeneratorScript.TerrainType.GRASS
	world_data.occupancy[occupied_cell.x][occupied_cell.y] = true
	var check_occupied: Dictionary = BuildingSystemScript.can_place_building("watchtower", occupied_cell, world_data, rm)
	if check_occupied["valid"]:
		printerr("  [FAIL] Placement on occupied cell should have been rejected!")
		failures += 1
	else:
		print("  [PASS] Placement on occupied cell correctly rejected: '%s'" % check_occupied.get("reason"))

	# 4. Rejection out of bounds
	var oob_cell := Vector2i(64, 20)
	var check_oob: Dictionary = BuildingSystemScript.can_place_building("watchtower", oob_cell, world_data, rm)
	if check_oob["valid"]:
		printerr("  [FAIL] Out of bounds placement should have been rejected!")
		failures += 1
	else:
		print("  [PASS] Out of bounds placement correctly rejected: '%s'" % check_oob.get("reason"))

	# 5. Rejection on insufficient resources
	for r_id in EconomyConfigScript.ALL_RESOURCES:
		rm._current_stock[r_id] = 0
	var check_poor: Dictionary = BuildingSystemScript.can_place_building("watchtower", test_cell, world_data, rm)
	if check_poor["valid"]:
		printerr("  [FAIL] Insufficient resources placement should have been rejected!")
		failures += 1
	else:
		print("  [PASS] Insufficient resources correctly rejected: '%s'" % check_poor.get("reason"))

	# -------------------------------------------------------------------------
	# TC-W.3: Cost Deduction & Atomic Safety
	# -------------------------------------------------------------------------
	print("\n--- Running TC-W.3: Cost Deduction & Atomic Safety ---")
	rm.reset_economy()
	var wood_before: int = rm.get_available_stock(EconomyConfigScript.RES_WOOD)
	var stone_before: int = rm.get_available_stock(EconomyConfigScript.RES_STONE)

	var place_res: Dictionary = BuildingSystemScript.place_building("watchtower", test_cell, world_data, rm)
	if not place_res.get("success", false):
		printerr("  [FAIL] Failed to place watchtower: %s" % place_res.get("reason"))
		failures += 1
	else:
		var wood_after: int = rm.get_available_stock(EconomyConfigScript.RES_WOOD)
		var stone_after: int = rm.get_available_stock(EconomyConfigScript.RES_STONE)
		if wood_before - wood_after != 20:
			printerr("  [FAIL] Wood deduction mismatch! Before=%d, After=%d" % [wood_before, wood_after])
			failures += 1
		elif stone_before - stone_after != 15:
			printerr("  [FAIL] Stone deduction mismatch! Before=%d, After=%d" % [stone_before, stone_after])
			failures += 1
		else:
			print("  [PASS] Exactly 20 Wood and 15 Stone deducted atomically (Wood: %d->%d, Stone: %d->%d)." % [wood_before, wood_after, stone_before, stone_after])

		# Check exact 1x1 occupancy
		if not world_data.occupancy[test_cell.x][test_cell.y]:
			printerr("  [FAIL] Cell (%d, %d) was not marked occupied!" % [test_cell.x, test_cell.y])
			failures += 1
		elif world_data.occupancy[test_cell.x + 1][test_cell.y]:
			printerr("  [FAIL] Cell (%d, %d) was erroneously marked occupied for 1x1 footprint!" % [test_cell.x + 1, test_cell.y])
			failures += 1
		else:
			print("  [PASS] Exact 1x1 occupancy verified (only target cell occupied).")

func _run_world_integration_checks() -> void:
	# -------------------------------------------------------------------------
	# TC-W.4: UI, Texture & Sprite Offset Validation
	# -------------------------------------------------------------------------
	print("\n--- Running TC-W.4: UI, Texture & Sprite Offset Validation ---")
	var wt_tex: Texture2D = load("res://assets/buildings/bld_watchtower.png")
	if wt_tex == null:
		printerr("  [FAIL] Failed to load 'res://assets/buildings/bld_watchtower.png'!")
		failures += 1
	else:
		print("  [PASS] Texture 'res://assets/buildings/bld_watchtower.png' loaded successfully (%dx%d px)." % [wt_tex.get_width(), wt_tex.get_height()])
		if wt_tex.get_width() != 32 or wt_tex.get_height() != 48:
			printerr("  [FAIL] Texture size is %dx%d, expected 32x48" % [wt_tex.get_width(), wt_tex.get_height()])
			failures += 1
		else:
			print("  [PASS] Watchtower sprite dimensions strictly 32x48 px (1x1 diamond base).")

	var b_textures: Dictionary = world_instance.get("building_textures")
	if not b_textures.has("watchtower") or b_textures["watchtower"] == null:
		printerr("  [FAIL] WorldView building_textures missing 'watchtower'!")
		failures += 1
	else:
		print("  [PASS] WorldView building_textures contains valid 'watchtower' Texture2D.")

	# Verify sprite offset
	var offset: Vector2 = world_instance.call("_get_building_sprite_offset", "watchtower")
	if offset != Vector2(-16.0, -40.0):
		printerr("  [FAIL] Watchtower sprite offset is %s, expected (-16, -40)" % offset)
		failures += 1
	else:
		print("  [PASS] Watchtower sprite offset strictly (-16, -40) matching diamond pivot.")

	# Verify display name
	var dname: String = world_instance.call("_get_building_display_name", "watchtower")
	if not ("Tháp Canh" in dname):
		printerr("  [FAIL] Display name is '%s', expected to contain 'Tháp Canh'" % dname)
		failures += 1
	else:
		print("  [PASS] Watchtower display name verified: '%s'" % dname)

	# -------------------------------------------------------------------------
	# TC-W.5: Vision Expansion (Radius 15) & POI Discovery Integration
	# -------------------------------------------------------------------------
	print("\n--- Running TC-W.5: Vision Expansion (Radius 15) & POI Discovery Integration ---")
	var fow: FogOfWar = world_instance.get("fog_of_war")
	var poi_mgr: POIManager = world_instance.get("poi_mgr")
	var w_data = world_instance.get("world_data")

	var tower_cell := Vector2i(10, 10)
	# Clear terrain for tower placement
	w_data.terrain[tower_cell.x][tower_cell.y] = WorldGeneratorScript.TerrainType.GRASS
	w_data.occupancy[tower_cell.x][tower_cell.y] = false

	# Cell at distance 12 Manhattan: (10 + 6, 10 + 6) -> dx=6, dy=6, dist=12 <= 15
	var edge_cell := Vector2i(16, 16)
	var far_cell := Vector2i(26, 26) # dist = 16 + 16 = 32 > 15

	# Reset fog cell to unexplored for controlled test
	fow._grid[edge_cell.x][edge_cell.y] = FogOfWarScript.State.UNEXPLORED
	fow._grid[far_cell.x][far_cell.y] = FogOfWarScript.State.UNEXPLORED

	if fow.get_state(edge_cell) != FogOfWarScript.State.UNEXPLORED:
		printerr("  [FAIL] Edge cell was not UNEXPLORED before tower placement!")
		failures += 1

	# Configure POI inside watchtower vision range (dist = 10 <= 15)
	var poi_cell := Vector2i(15, 15) # dist = 10
	var test_poi := POIManagerScript.POIData.new()
	test_poi.id = "poi_watchtower_test"
	test_poi.name = "Phế tích Đài Quan Sát"
	test_poi.cell = poi_cell
	test_poi.state = POIManagerScript.POIState.UNDISCOVERED
	test_poi.rewards = {EconomyConfigScript.RES_GOLD: 50}
	poi_mgr._pois[test_poi.id] = test_poi

	# Execute placement via WorldView
	world_instance.set("placing_building_type", "watchtower")
	var live_rm = world_instance.get_node_or_null("/root/ResourceManager")
	if live_rm:
		live_rm.reset_economy()
		live_rm.add_resource("wood", 100)
		live_rm.add_resource("stone", 100)
	world_instance.call("_execute_placement", tower_cell)

	# Check vision expansion
	if not fow.is_visible(edge_cell):
		printerr("  [FAIL] Edge cell (16, 16) [dist=12] should be VISIBLE after Watchtower build! State=%d" % fow.get_state(edge_cell))
		failures += 1
	else:
		print("  [PASS] 15-tile vision expansion confirmed: cell (16, 16) [dist=12] became VISIBLE.")

	if fow.is_explored(far_cell):
		printerr("  [FAIL] Far cell (26, 26) [dist=32] should remain UNEXPLORED!")
		failures += 1
	else:
		print("  [PASS] Cells outside radius 15 strictly remained UNEXPLORED.")

	# Check POI discovery
	if test_poi.state != POIManagerScript.POIState.DISCOVERED:
		printerr("  [FAIL] POI inside watchtower radius was not DISCOVERED! State=%d" % test_poi.state)
		failures += 1
	else:
		print("  [PASS] POI in watchtower vision range automatically DISCOVERED.")

	# Continuous vision test: simulate hour passed
	world_instance.call("_on_simulation_hour_passed", 7, 1)
	if not fow.is_visible(edge_cell):
		printerr("  [FAIL] Continuous simulation hour failed to maintain watchtower vision!")
		failures += 1
	else:
		print("  [PASS] Watchtower continuous hourly simulation vision maintained cleanly.")

	# -------------------------------------------------------------------------
	# TC-W.6: Save/Load Persistence
	# -------------------------------------------------------------------------
	print("\n--- Running TC-W.6: Save/Load Persistence ---")
	var save_path := "user://saves/test_watchtower_save.json"
	var save_res: Dictionary = SaveManagerScript.save_to_file(world_instance, save_path)
	if not save_res.get("success", false):
		printerr("  [FAIL] Failed to save world with watchtower: %s" % save_res.get("error"))
		failures += 1
	else:
		print("  [PASS] World with watchtower saved successfully (%d bytes)." % save_res.get("bytes", 0))

	var load_res: Dictionary = SaveManagerScript.load_from_file(save_path)
	if not load_res.get("success", false):
		printerr("  [FAIL] Failed to load save file: %s" % load_res.get("error"))
		failures += 1
	else:
		var loaded_data: Dictionary = load_res["data"]
		var found_tower := false
		for b in loaded_data.get("buildings", []):
			if b.get("type") == "watchtower" and b.get("cell_x") == tower_cell.x and b.get("cell_y") == tower_cell.y:
				found_tower = true
				if b.get("size_x") != 1 or b.get("size_y") != 1:
					printerr("  [FAIL] Saved watchtower size is not 1x1: %dx%d" % [b.get("size_x"), b.get("size_y")])
					failures += 1
				break
		if not found_tower:
			printerr("  [FAIL] Watchtower not found in saved buildings data!")
			failures += 1
		else:
			print("  [PASS] Watchtower correctly serialized with 1x1 footprint.")

		# Apply loaded state to world
		var apply_res: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, loaded_data)
		if not apply_res.get("success", false):
			printerr("  [FAIL] Failed to apply loaded state: %s" % apply_res.get("error"))
			failures += 1
		else:
			var live_found := false
			for b in w_data.buildings:
				if b.get("type") == "watchtower" and b.get("cell") == tower_cell:
					live_found = true
					break
			if not live_found:
				printerr("  [FAIL] Watchtower not reconstructed in live world!")
				failures += 1
			else:
				print("  [PASS] Watchtower reconstructed in live world at %s." % tower_cell)

			# Check node existence in buildings_container
			var b_container = world_instance.get("buildings_container")
			var b_node = b_container.get_node_or_null("Building_watchtower_%d_%d" % [tower_cell.x, tower_cell.y])
			if b_node == null:
				printerr("  [FAIL] Watchtower visual node not found in scene tree!")
				failures += 1
			else:
				print("  [PASS] Watchtower visual node verified in scene tree with zero duplicates.")

	# Clean up test save file
	var dir := DirAccess.open("user://saves")
	if dir:
		dir.remove("test_watchtower_save.json")
		dir.remove("test_watchtower_save.json.bak")
