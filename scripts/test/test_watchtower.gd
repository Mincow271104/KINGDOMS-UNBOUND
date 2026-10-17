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
var old_tower_ref_for_next_frame: WeakRef = null

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

	# In frame 4, verify that queued-for-deletion nodes have been completely freed by engine
	if frame_count == 4:
		print("\n--- Verifying Deferred Node Deletion Lifecycle (Frame 4) ---")
		if old_tower_ref_for_next_frame != null:
			if old_tower_ref_for_next_frame.get_ref() != null:
				printerr("  [FAIL] Old watchtower node was NOT freed by engine after frame step!")
				failures += 1
			else:
				print("  [PASS] Old watchtower node completely freed from memory by engine on next frame.")

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
	# TC-W.5: HUD Integration & Signal Verification
	# -------------------------------------------------------------------------
	print("\n--- Running TC-W.5: HUD Integration & Signal Verification ---")
	var wt_btn = world_instance.get_node_or_null("HUD/BuildMenuPanel/MarginContainer/VBoxContainer/GridContainer/WatchtowerBtn")
	if wt_btn == null:
		printerr("  [FAIL] WatchtowerBtn not found in HUD BuildMenuPanel!")
		failures += 1
	else:
		print("  [PASS] WatchtowerBtn found in HUD tree.")
		var live_rm = world_instance.get_node_or_null("/root/ResourceManager")
		if live_rm:
			live_rm.reset_economy()
			live_rm.add_resource("wood", 100)
			live_rm.add_resource("stone", 100)
		var wood_prior: int = live_rm.get_available_stock("wood") if live_rm else 0
		var stone_prior: int = live_rm.get_available_stock("stone") if live_rm else 0

		# Emit button pressed signal
		wt_btn.pressed.emit()

		# Verify world placing_building_type set
		var placing_type: String = world_instance.get("placing_building_type")
		if placing_type != "watchtower":
			printerr("  [FAIL] After WatchtowerBtn pressed, placing_building_type is '%s', expected 'watchtower'" % placing_type)
			failures += 1
		else:
			print("  [PASS] WatchtowerBtn pressed correctly set placing_building_type to 'watchtower'.")

		# Verify ghost preview
		var ghost_node: Node2D = world_instance.get("ghost_building_node")
		var ghost_sprite: Sprite2D = world_instance.get("ghost_building_sprite")
		if ghost_node == null or ghost_sprite == null:
			printerr("  [FAIL] Ghost preview node or sprite missing!")
			failures += 1
		else:
			if not ghost_node.visible:
				printerr("  [FAIL] Ghost preview node is not visible!")
				failures += 1
			else:
				print("  [PASS] Ghost preview node is visible.")
			if ghost_sprite.texture == null:
				printerr("  [FAIL] Ghost preview sprite texture is null!")
				failures += 1
			else:
				print("  [PASS] Ghost preview sprite texture loaded.")
			if ghost_sprite.offset != Vector2(-16.0, -40.0):
				printerr("  [FAIL] Ghost preview sprite offset is %s, expected (-16, -40)" % ghost_sprite.offset)
				failures += 1
			else:
				print("  [PASS] Ghost preview sprite offset verified (-16, -40).")

		# Cancel placement and verify no deduction
		world_instance.call("_cancel_placement")
		if world_instance.get("placing_building_type") != "":
			printerr("  [FAIL] placing_building_type should be empty after _cancel_placement()!")
			failures += 1
		else:
			print("  [PASS] Placement canceled cleanly.")
		if ghost_node != null and ghost_node.visible:
			printerr("  [FAIL] Ghost preview should be hidden after cancel!")
			failures += 1
		else:
			print("  [PASS] Ghost preview hidden after cancel.")

		var wood_post: int = live_rm.get_available_stock("wood") if live_rm else 0
		var stone_post: int = live_rm.get_available_stock("stone") if live_rm else 0
		if wood_post != wood_prior or stone_post != stone_prior:
			printerr("  [FAIL] Resources changed on canceled placement! Prior: (%d, %d), Post: (%d, %d)" % [wood_prior, stone_prior, wood_post, stone_post])
			failures += 1
		else:
			print("  [PASS] Resources unaffected by canceling placement.")

	# -------------------------------------------------------------------------
	# TC-W.6: Exact Manhattan Boundary Verification (Dist 15 vs Dist 16)
	# -------------------------------------------------------------------------
	print("\n--- Running TC-W.6: Exact Manhattan Boundary Verification (Dist 15 vs Dist 16) ---")
	var fow: FogOfWar = world_instance.get("fog_of_war")
	var poi_mgr: POIManager = world_instance.get("poi_mgr")
	var w_data = world_instance.get("world_data")

	var tower_cell := Vector2i(10, 10)
	w_data.terrain[tower_cell.x][tower_cell.y] = WorldGeneratorScript.TerrainType.GRASS
	w_data.occupancy[tower_cell.x][tower_cell.y] = false

	# Exact Manhattan distance 15: dx=10, dy=5 -> 10 + 5 = 15
	var pt_dist_15 := Vector2i(20, 15)
	# Exact Manhattan distance 16: dx=10, dy=6 -> 10 + 6 = 16
	var pt_dist_16 := Vector2i(20, 16)

	fow._grid[pt_dist_15.x][pt_dist_15.y] = FogOfWarScript.State.UNEXPLORED
	fow._grid[pt_dist_16.x][pt_dist_16.y] = FogOfWarScript.State.UNEXPLORED

	if fow.get_state(pt_dist_15) != FogOfWarScript.State.UNEXPLORED or fow.get_state(pt_dist_16) != FogOfWarScript.State.UNEXPLORED:
		printerr("  [FAIL] Test cells were not reset to UNEXPLORED!")
		failures += 1

	# Setup two POIs: one inside vision (dist 10 <= 15), one outside vision (dist 30 > 15)
	var poi_inside := POIManagerScript.POIData.new()
	poi_inside.id = "poi_watchtower_test"
	poi_inside.name = "Phế tích Đài Quan Sát"
	poi_inside.cell = Vector2i(15, 15) # dist = 5 + 5 = 10 <= 15
	poi_inside.state = POIManagerScript.POIState.UNDISCOVERED
	poi_inside.rewards = {EconomyConfigScript.RES_GOLD: 50}
	poi_mgr._pois[poi_inside.id] = poi_inside

	var poi_outside := POIManagerScript.POIData.new()
	poi_outside.id = "poi_distant_grove"
	poi_outside.name = "Rừng Rậm Xa Xôi"
	poi_outside.cell = Vector2i(25, 25) # dist = 15 + 15 = 30 > 15
	poi_outside.state = POIManagerScript.POIState.UNDISCOVERED
	poi_outside.rewards = {EconomyConfigScript.RES_HERBS: 20}
	poi_mgr._pois[poi_outside.id] = poi_outside

	# Spawn visual nodes for POIs
	var node_inside = world_instance.call("_spawn_single_poi_node", poi_inside)
	var node_outside = world_instance.call("_spawn_single_poi_node", poi_outside)

	# Verify POI nodes are hidden while UNDISCOVERED
	if node_inside.visible:
		printerr("  [FAIL] Undiscovered POI node_inside should be invisible!")
		failures += 1
	else:
		print("  [PASS] Undiscovered POI node_inside is correctly hidden.")

	if node_outside.visible:
		printerr("  [FAIL] Undiscovered POI node_outside should be invisible!")
		failures += 1
	else:
		print("  [PASS] Undiscovered POI node_outside is correctly hidden.")

	# Execute placement via WorldView
	world_instance.set("placing_building_type", "watchtower")
	var live_rm2 = world_instance.get_node_or_null("/root/ResourceManager")
	if live_rm2:
		live_rm2.reset_economy()
		live_rm2.add_resource("wood", 100)
		live_rm2.add_resource("stone", 100)
	world_instance.call("_execute_placement", tower_cell)

	# Boundary check: dist 15 must be VISIBLE
	if not fow.is_visible(pt_dist_15):
		printerr("  [FAIL] Exact Manhattan boundary (dist=15) at (20, 15) should be VISIBLE! State=%d" % fow.get_state(pt_dist_15))
		failures += 1
	else:
		print("  [PASS] Exact Manhattan boundary (dist=15) at (20, 15) verified VISIBLE.")

	# Boundary check: dist 16 must remain UNEXPLORED
	if fow.is_explored(pt_dist_16):
		printerr("  [FAIL] Exact Manhattan boundary (dist=16) at (20, 16) should remain UNEXPLORED! State=%d" % fow.get_state(pt_dist_16))
		failures += 1
	else:
		print("  [PASS] Exact Manhattan boundary (dist=16) at (20, 16) strictly remained UNEXPLORED.")

	# -------------------------------------------------------------------------
	# TC-W.7: POI Discovery Visual Feedback
	# -------------------------------------------------------------------------
	print("\n--- Running TC-W.7: POI Discovery Visual Feedback ---")
	if poi_inside.state != POIManagerScript.POIState.DISCOVERED:
		printerr("  [FAIL] POI inside vision should be DISCOVERED! State=%d" % poi_inside.state)
		failures += 1
	else:
		print("  [PASS] POI inside vision transitioned to DISCOVERED.")

	if not node_inside.visible:
		printerr("  [FAIL] POI visual node was not made visible upon discovery!")
		failures += 1
	else:
		print("  [PASS] POI visual node became visible via poi_revealed signal.")

	if poi_outside.state != POIManagerScript.POIState.UNDISCOVERED:
		printerr("  [FAIL] POI outside vision should remain UNDISCOVERED! State=%d" % poi_outside.state)
		failures += 1
	else:
		print("  [PASS] POI outside vision remained UNDISCOVERED.")

	if node_outside.visible:
		printerr("  [FAIL] POI outside vision became visible erroneously!")
		failures += 1
	else:
		print("  [PASS] POI outside vision remained invisible.")

	# Continuous vision test: simulate hour passed
	world_instance.call("_on_simulation_hour_passed", 7, 1)
	if not fow.is_visible(pt_dist_15):
		printerr("  [FAIL] Continuous simulation hour failed to maintain watchtower vision at dist 15!")
		failures += 1
	else:
		print("  [PASS] Watchtower continuous hourly simulation vision maintained cleanly.")
	if not node_inside.visible or node_outside.visible:
		printerr("  [FAIL] Continuous simulation corrupted POI node visibilities!")
		failures += 1
	else:
		print("  [PASS] Continuous simulation maintained correct POI visibility states.")

	# -------------------------------------------------------------------------
	# TC-W.8: Save/Load Fog, Watchtower & POI Persistence
	# -------------------------------------------------------------------------
	print("\n--- Running TC-W.8: Save/Load Fog, Watchtower & POI Persistence ---")
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

		# Check fog coordinates in save data
		var saved_fow_list: Array = loaded_data.get("fog_of_war", [])
		var has_pt_15 := false
		var has_pt_16 := false
		for coord in saved_fow_list:
			if coord is Array and coord.size() >= 2:
				if coord[0] == pt_dist_15.x and coord[1] == pt_dist_15.y:
					has_pt_15 = true
				if coord[0] == pt_dist_16.x and coord[1] == pt_dist_16.y:
					has_pt_16 = true
		if not has_pt_15:
			printerr("  [FAIL] Saved fog_of_war missing dist 15 coordinate (20, 15)!")
			failures += 1
		else:
			print("  [PASS] Saved fog_of_war contains explored dist 15 coordinate.")
		if has_pt_16:
			printerr("  [FAIL] Saved fog_of_war erroneously contains dist 16 coordinate (20, 16)!")
			failures += 1
		else:
			print("  [PASS] Saved fog_of_war strictly excludes unexplored dist 16 coordinate.")

		# Check POI states in save data
		var saved_pois_list: Array = loaded_data.get("pois", [])
		var saved_poi_inside_state := -1
		var saved_poi_outside_state := -1
		for sp in saved_pois_list:
			if sp.get("id") == poi_inside.id:
				saved_poi_inside_state = int(sp.get("state", -1))
			elif sp.get("id") == poi_outside.id:
				saved_poi_outside_state = int(sp.get("state", -1))
		if saved_poi_inside_state != POIManagerScript.POIState.DISCOVERED:
			printerr("  [FAIL] Saved poi_inside state is %d, expected DISCOVERED (1)" % saved_poi_inside_state)
			failures += 1
		else:
			print("  [PASS] Saved poi_inside correctly serialized as DISCOVERED.")
		if saved_poi_outside_state != POIManagerScript.POIState.UNDISCOVERED:
			printerr("  [FAIL] Saved poi_outside state is %d, expected UNDISCOVERED (0)" % saved_poi_outside_state)
			failures += 1
		else:
			print("  [PASS] Saved poi_outside correctly serialized as UNDISCOVERED.")

		# Capture pre-existing watchtower node before reloading
		var b_container: Node2D = world_instance.get("buildings_container")
		var old_tower_node: Node = b_container.get_node_or_null("Building_watchtower_%d_%d" % [tower_cell.x, tower_cell.y])
		if old_tower_node == null:
			printerr("  [FAIL] Pre-existing watchtower node missing before save load test!")
			failures += 1
		else:
			print("  [PASS] Pre-existing watchtower node tracked before reload: %s" % old_tower_node.name)
			old_tower_ref_for_next_frame = weakref(old_tower_node)

		# ---------------------------------------------------------------------
		# Intentional pre-load dirty state injection:
		# Actively corrupt the live world state before applying loaded data
		# to ensure apply_loaded_state_to_world actually resets dirty state and restores canonical state.
		# ---------------------------------------------------------------------
		fow._grid[pt_dist_15.x][pt_dist_15.y] = FogOfWarScript.State.UNEXPLORED
		fow._grid[pt_dist_16.x][pt_dist_16.y] = FogOfWarScript.State.VISIBLE

		if fow.get_state(pt_dist_15) != FogOfWarScript.State.UNEXPLORED or fow.get_state(pt_dist_16) != FogOfWarScript.State.VISIBLE:
			printerr("  [FAIL] Failed to inject pre-load dirty fog state!")
			failures += 1
		else:
			print("  [PASS] Pre-load dirty fog state injected: (20, 15) -> UNEXPLORED, (20, 16) -> VISIBLE.")

		# Also corrupt POI live state before loading
		poi_inside.state = POIManagerScript.POIState.UNDISCOVERED
		poi_outside.state = POIManagerScript.POIState.DISCOVERED
		world_instance.call("refresh_poi_visibility")
		var pre_inside = world_instance.poi_nodes_by_id.get(poi_inside.id)
		var pre_outside = world_instance.poi_nodes_by_id.get(poi_outside.id)
		if pre_inside != null and pre_inside.visible:
			printerr("  [FAIL] Pre-load corrupted poi_inside should be invisible!")
			failures += 1
		if pre_outside != null and not pre_outside.visible:
			printerr("  [FAIL] Pre-load corrupted poi_outside should be visible!")
			failures += 1

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

			# 1. Old building node is no longer under buildings_container
			if old_tower_node != null:
				if old_tower_node.get_parent() == b_container:
					printerr("  [FAIL] Old watchtower node is still a child of buildings_container!")
					failures += 1
				else:
					print("  [PASS] Old watchtower node successfully detached from buildings_container.")
				if not old_tower_node.is_queued_for_deletion():
					printerr("  [FAIL] Old watchtower node was not queued for deletion!")
					failures += 1
				else:
					print("  [PASS] Old watchtower node is queued for deletion.")

			# 2 & 3 & 4. Reconstructed node verification
			var new_tower_node: Node = b_container.get_node_or_null("Building_watchtower_%d_%d" % [tower_cell.x, tower_cell.y])
			if new_tower_node == null:
				printerr("  [FAIL] Reconstructed watchtower node not found in buildings_container!")
				failures += 1
			else:
				if new_tower_node == old_tower_node:
					printerr("  [FAIL] Reconstructed watchtower node is identical to the old node instance!")
					failures += 1
				else:
					print("  [PASS] Reconstructed watchtower is a distinct new node instance.")

				if new_tower_node.name != ("Building_watchtower_%d_%d" % [tower_cell.x, tower_cell.y]):
					printerr("  [FAIL] Reconstructed watchtower node name is '%s', expected canonical name" % new_tower_node.name)
					failures += 1
				else:
					print("  [PASS] Reconstructed watchtower node has exact canonical name 'Building_watchtower_%d_%d'." % [tower_cell.x, tower_cell.y])

				if new_tower_node.is_queued_for_deletion():
					printerr("  [FAIL] Reconstructed watchtower node is unexpectedly queued for deletion!")
					failures += 1
				else:
					print("  [PASS] Reconstructed watchtower node is active (not queued for deletion).")

				if new_tower_node.get_parent() != b_container:
					printerr("  [FAIL] Reconstructed watchtower node parent is not buildings_container!")
					failures += 1
				else:
					print("  [PASS] Reconstructed watchtower node parent is strictly buildings_container.")

				var sprite_found := false
				for ch in new_tower_node.get_children():
					if ch is Sprite2D and ch.texture != null and ch.texture == wt_tex:
						sprite_found = true
						break
				if not sprite_found:
					printerr("  [FAIL] Reconstructed watchtower node missing valid Sprite2D with watchtower texture!")
					failures += 1
				else:
					print("  [PASS] Reconstructed watchtower node contains valid Sprite2D texture.")

			# 5. Ensure NO duplicate active or lingering watchtower nodes at this cell
			var active_tower_count := 0
			var all_tower_nodes: Array = []
			for child in b_container.get_children():
				if ("watchtower_%d_%d" % [tower_cell.x, tower_cell.y]) in child.name:
					all_tower_nodes.append(child)
					if not child.is_queued_for_deletion():
						active_tower_count += 1
			if active_tower_count != 1:
				printerr("  [FAIL] Expected exactly 1 active watchtower node at (%d, %d), found %d!" % [tower_cell.x, tower_cell.y, active_tower_count])
				failures += 1
			else:
				print("  [PASS] Exactly 1 active watchtower node present under buildings_container (zero duplicates).")
			if all_tower_nodes.size() != 1:
				printerr("  [FAIL] buildings_container contains lingering duplicate tower nodes: %s" % str(all_tower_nodes))
				failures += 1
			else:
				print("  [PASS] buildings_container child list strictly contains only the new watchtower node.")

			# Check fog restoration from dirty pre-load state
			if not fow.is_visible(pt_dist_15):
				printerr("  [FAIL] Restored fog dist 15 (20, 15) is not visible! State=%d" % fow.get_state(pt_dist_15))
				failures += 1
			else:
				print("  [PASS] Restored fog dist 15 (20, 15) recovered from UNEXPLORED to VISIBLE.")

			if not fow.is_unexplored(pt_dist_16):
				printerr("  [FAIL] Restored fog dist 16 (20, 16) was NOT reset to UNEXPLORED! State=%d" % fow.get_state(pt_dist_16))
				failures += 1
			else:
				print("  [PASS] Restored fog dist 16 (20, 16) successfully wiped from dirty VISIBLE back to UNEXPLORED.")

			# Check POI node visibility restoration
			var restored_inside_node = world_instance.poi_nodes_by_id.get(poi_inside.id)
			var restored_outside_node = world_instance.poi_nodes_by_id.get(poi_outside.id)
			if restored_inside_node == null or not restored_inside_node.visible:
				printerr("  [FAIL] Restored discovered POI node is not visible!")
				failures += 1
			else:
				print("  [PASS] Restored discovered POI node recovered to visible.")
			if restored_outside_node == null or restored_outside_node.visible:
				printerr("  [FAIL] Restored undiscovered POI node should not be visible!")
				failures += 1
			else:
				print("  [PASS] Restored undiscovered POI node recovered to hidden.")

		# ---------------------------------------------------------------------
		# Secondary Roundtrip: Apply save data onto a freshly initialized WorldView
		# ---------------------------------------------------------------------
		print("\n--- Running TC-W.8b: Fresh WorldView Instance Save Restoration ---")
		var fresh_world = WorldViewScene.instantiate()
		root.add_child(fresh_world)

		var fresh_fow: FogOfWar = fresh_world.get("fog_of_war")
		var fresh_wdata = fresh_world.get("world_data")

		# Confirm fresh world does not have watchtower yet
		var fresh_has_tower := false
		for b in fresh_wdata.buildings:
			if b.get("type") == "watchtower":
				fresh_has_tower = true
				break
		if fresh_has_tower:
			printerr("  [FAIL] Fresh world already has watchtower before load!")
			failures += 1
		else:
			print("  [PASS] Fresh world confirmed without watchtower prior to load.")

		# Confirm fresh world has (20, 15) unexplored initially
		if not fresh_fow.is_unexplored(pt_dist_15):
			printerr("  [FAIL] Fresh world cell (20, 15) should be UNEXPLORED initially!")
			failures += 1
		else:
			print("  [PASS] Fresh world cell (20, 15) initially UNEXPLORED.")

		# Apply save to fresh_world
		var fresh_apply: Dictionary = SaveManagerScript.apply_loaded_state_to_world(fresh_world, loaded_data)
		if not fresh_apply.get("success", false):
			printerr("  [FAIL] Failed to apply loaded state to fresh WorldView: %s" % fresh_apply.get("error"))
			failures += 1
		else:
			# Verify watchtower in fresh world
			var fresh_tower_found := false
			for b in fresh_wdata.buildings:
				if b.get("type") == "watchtower" and b.get("cell") == tower_cell:
					fresh_tower_found = true
					break
			if not fresh_tower_found:
				printerr("  [FAIL] Watchtower not reconstructed in fresh WorldView!")
				failures += 1
			else:
				print("  [PASS] Watchtower successfully restored in fresh WorldView at %s." % tower_cell)

			var fresh_b_node = fresh_world.get("buildings_container").get_node_or_null("Building_watchtower_%d_%d" % [tower_cell.x, tower_cell.y])
			if fresh_b_node == null:
				printerr("  [FAIL] Visual watchtower node missing in fresh WorldView!")
				failures += 1
			else:
				print("  [PASS] Visual watchtower node instantiated in fresh WorldView.")

			# Verify Fog of War in fresh world
			if not fresh_fow.is_visible(pt_dist_15):
				printerr("  [FAIL] Cell (20, 15) is not visible in restored fresh WorldView!")
				failures += 1
			else:
				print("  [PASS] Cell (20, 15) properly restored to VISIBLE in fresh WorldView.")

			if not fresh_fow.is_unexplored(pt_dist_16):
				printerr("  [FAIL] Cell (20, 16) is not unexplored in restored fresh WorldView!")
				failures += 1
			else:
				print("  [PASS] Cell (20, 16) strictly UNEXPLORED in fresh WorldView.")

			# Verify POI visibility in fresh world
			var fresh_inside_node = fresh_world.poi_nodes_by_id.get(poi_inside.id)
			var fresh_outside_node = fresh_world.poi_nodes_by_id.get(poi_outside.id)
			if fresh_inside_node == null or not fresh_inside_node.visible:
				printerr("  [FAIL] Discovered POI node not visible in fresh WorldView!")
				failures += 1
			else:
				print("  [PASS] Discovered POI node visible in fresh WorldView.")

			if fresh_outside_node == null or fresh_outside_node.visible:
				printerr("  [FAIL] Undiscovered POI node should not be visible in fresh WorldView!")
				failures += 1
			else:
				print("  [PASS] Undiscovered POI node hidden in fresh WorldView.")

		fresh_world.queue_free()

	# Clean up test save file
	var dir := DirAccess.open("user://saves")
	if dir:
		dir.remove("test_watchtower_save.json")
		dir.remove("test_watchtower_save.json.bak")
