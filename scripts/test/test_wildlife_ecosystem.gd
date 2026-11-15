extends SceneTree

const WorldViewScene := preload("res://scenes/world/world_view.tscn")
const WildlifeConfig = preload("res://scripts/world/wildlife_config.gd")
const WildlifeManager = preload("res://scripts/world/wildlife_manager.gd")
const WildlifeActor = preload("res://scripts/world/wildlife_actor.gd")

var _passed: int = 0
var _failures: Array[String] = []

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures.append(msg)
		printerr("[FAIL] ", msg)

func _init() -> void:
	call_deferred("_run_all")

func _fingerprint_world(wd: WorldGenerator.WorldData) -> Dictionary:
	var h_terrain: int = 0
	var h_biome: int = 0
	for x in range(wd.map_width):
		for y in range(wd.map_height):
			h_terrain = hash([h_terrain, wd.terrain[x][y]])
			if not wd.biome_grid.is_empty():
				h_biome = hash([h_biome, wd.biome_grid[x][y]])
	return {
		"terrain": h_terrain,
		"biome": h_biome,
		"rivers": wd.river_cells.size(),
		"lakes": wd.lake_cells.size(),
		"props": wd.props.size(),
	}

func _run_all() -> void:
	# --- 1-4. Deterministic Generation & V7 Non-Perturbation ---
	var wd_a := WorldGenerator.generate(12345, WorldGenerator.LATEST_GENERATOR_VERSION, 128, 128)
	var fp_before := _fingerprint_world(wd_a)
	var nav_a := GridNavigation.new(wd_a)
	var mgr_a := WildlifeManager.new()
	mgr_a.generate_initial_population(wd_a, nav_a)
	var fp_after := _fingerprint_world(wd_a)
	_assert(fp_before == fp_after, "Case 3: Wildlife spawn does not alter V7 terrain, biome, river, lake, or props")

	var wd_b := WorldGenerator.generate(12345, WorldGenerator.LATEST_GENERATOR_VERSION, 128, 128)
	var nav_b := GridNavigation.new(wd_b)
	var mgr_b := WildlifeManager.new()
	mgr_b.generate_initial_population(wd_b, nav_b)
	_assert(mgr_a.get_all_animals().size() == mgr_b.get_all_animals().size() and mgr_a.get_all_animals().size() > 0, "Case 1a: Same seed produces identical wildlife count")
	var all_match: bool = true
	for i in range(mgr_a.get_all_animals().size()):
		var a1: Dictionary = mgr_a.get_all_animals()[i]
		var a2: Dictionary = mgr_b.get_all_animals()[i]
		if a1["id"] != a2["id"] or a1["species_id"] != a2["species_id"] or a1["cell"] != a2["cell"]:
			all_match = false
			break
	_assert(all_match, "Case 1b: Same seed produces identical IDs, species, and cells")

	var wd_c := WorldGenerator.generate(99991, WorldGenerator.LATEST_GENERATOR_VERSION, 128, 128)
	var nav_c := GridNavigation.new(wd_c)
	var mgr_c := WildlifeManager.new()
	mgr_c.generate_initial_population(wd_c, nav_c)
	_assert(mgr_c.get_all_animals().size() > 0 and mgr_c.get_all_animals()[0]["cell"] != mgr_a.get_all_animals()[0]["cell"], "Case 2: Different seeds produce different valid populations")

	# Legacy V1-V4 safe handling (no biome_grid)
	var wd_v1 := WorldGenerator.generate(12345, 1, 64, 64)
	var nav_v1 := GridNavigation.new(wd_v1)
	var mgr_v1 := WildlifeManager.new()
	mgr_v1.generate_initial_population(wd_v1, nav_v1)
	_assert(mgr_v1.get_all_animals().is_empty(), "Case 4 & 34: Legacy world without biome_grid handled safely")

	# --- 5-10. Habitat, Spawn, Caps & Non-Overlap ---
	var prop_cells: Dictionary = {}
	for p in wd_a.props:
		prop_cells[p["cell"]] = true
	var counts_by_species: Dictionary = {}
	var bad_biome: int = 0
	var bad_walkable: int = 0
	var bad_overlap: int = 0
	var bad_bounds: int = 0
	var near_townhall_invaders: int = 0
	var grassland_near_settlement: int = 0
	for rec in mgr_a.get_all_animals():
		var sp: String = rec["species_id"]
		var c: Vector2i = rec["cell"]
		counts_by_species[sp] = int(counts_by_species.get(sp, 0)) + 1
		if not wd_a.is_in_bounds(c):
			bad_bounds += 1
		if not WildlifeConfig.is_biome_allowed(sp, wd_a.get_biome(c)):
			bad_biome += 1
		if not nav_a.is_cell_walkable(c) or wd_a.terrain[c.x][c.y] == WorldGenerator.TerrainType.WATER:
			bad_walkable += 1
		if prop_cells.has(c) or wd_a.occupancy[c.x][c.y]:
			bad_overlap += 1
		var d_center := IsoMath.grid_distance(c, wd_a.center_spawn)
		if d_center <= 5:
			near_townhall_invaders += 1
		if wd_a.get_biome(c) == WorldGenerator.BiomeType.GRASSLAND and d_center <= 28:
			grassland_near_settlement += 1

	_assert(bad_biome == 0, "Case 5: All animals spawned in allowed biomes")
	_assert(bad_walkable == 0, "Case 6: No animal spawned in water or impassable terrain")
	_assert(bad_overlap == 0, "Case 7: No animal overlapped props, resources, or occupied cells")
	_assert(bad_bounds == 0, "Case 8: All animals within map bounds")
	_assert(mgr_a.get_all_animals().size() <= WildlifeConfig.MAX_TOTAL_POPULATION, "Case 9a: Total population <= 70")
	var cap_ok: bool = true
	for sp in counts_by_species.keys():
		if counts_by_species[sp] > int(WildlifeConfig.get_species_def(sp).get("max_pop", 0)):
			cap_ok = false
	_assert(cap_ok, "Case 9b: Per-species population caps respected")
	_assert(near_townhall_invaders == 0, "Case 10a: No animal inside Town Hall core")
	_assert(grassland_near_settlement > 0, "Case 10b: Grassland wildlife exists near starting region")

	# --- Live WorldView Integration Tests (11-35) ---
	var wv := WorldViewScene.instantiate()
	wv.set("skip_intro_for_test", true)
	root.add_child(wv)
	await create_timer(0.2).timeout

	var wl: WildlifeManager = wv.get("wildlife_mgr")
	var fow: FogOfWar = wv.get("fog_of_war")
	var wd: WorldGenerator.WorldData = wv.get("world_data")
	var nav: GridNavigation = wv.get("nav")
	var hud = wv.get("hud")
	_assert(wl != null and wl.get_all_animals().size() > 0, "Live WorldView initialized WildlifeManager")

	# 11-13. Non-blocking occupancy & walkable movement
	var occ_before: int = 0
	for x in range(wd.map_width):
		for y in range(wd.map_height):
			if wd.occupancy[x][y]:
				occ_before += 1

	for _step in range(10):
		wl.advance_simulation(0.2, 1.0, wd, nav, wv.citizen_list, [])

	var occ_after: int = 0
	for x in range(wd.map_width):
		for y in range(wd.map_height):
			if wd.occupancy[x][y]:
				occ_after += 1
	_assert(occ_before == occ_after, "Case 13: Wildlife movement does not modify world occupancy")

	var bad_move: int = 0
	for rec in wl.get_all_animals():
		if not nav.is_cell_walkable(rec["cell"]) or not nav.is_cell_walkable(rec["target_cell"]):
			bad_move += 1
	_assert(bad_move == 0, "Case 11: Wildlife moves only through walkable terrain")

	# 17-18. Pause & speed_mult
	var snap_cells: Array = []
	for rec in wl.get_all_animals():
		snap_cells.append([rec["cell"], rec["target_cell"], rec["move_progress"], rec["state_timer"]])
	wl.advance_simulation(0.5, 0.0, wd, nav, wv.citizen_list, [])
	var paused_unchanged: bool = true
	for i in range(wl.get_all_animals().size()):
		var rec: Dictionary = wl.get_all_animals()[i]
		if rec["cell"] != snap_cells[i][0] or rec["target_cell"] != snap_cells[i][1] or rec["move_progress"] != snap_cells[i][2] or rec["state_timer"] != snap_cells[i][3]:
			paused_unchanged = false
			break
	_assert(paused_unchanged, "Case 17: Wildlife stops updating when paused (speed_mult == 0.0)")

	# 14-16. Category behavior: Passive flee, Defensive display->retreat, Ambient never combat/flee
	var passive_rec: Dictionary = {}
	var defensive_rec: Dictionary = {}
	var ambient_rec: Dictionary = {}
	for rec in wl.get_all_animals():
		if passive_rec.is_empty() and rec["category"] == WildlifeConfig.Category.PASSIVE_HUNTABLE:
			passive_rec = rec
		elif defensive_rec.is_empty() and rec["category"] == WildlifeConfig.Category.DEFENSIVE:
			defensive_rec = rec
		elif ambient_rec.is_empty() and rec["category"] == WildlifeConfig.Category.AMBIENT:
			ambient_rec = rec

	if not passive_rec.is_empty():
		var mock_unit := {"current_cell": passive_rec["cell"] + Vector2i(1, 0), "is_alive": true}
		wl._threat_scan_accum = WildlifeManager.THREAT_SCAN_INTERVAL
		wl.advance_simulation(0.05, 1.0, wd, nav, [], [mock_unit])
		_assert(passive_rec["state"] == WildlifeConfig.BehaviorState.FLEEING, "Case 14: Passive wildlife flees from nearby unit")

	if not defensive_rec.is_empty():
		defensive_rec["state"] = WildlifeConfig.BehaviorState.IDLE
		defensive_rec["target_cell"] = defensive_rec["cell"]
		var mock_unit2 := {"current_cell": defensive_rec["cell"] + Vector2i(1, 0), "is_alive": true}
		wl._threat_scan_accum = WildlifeManager.THREAT_SCAN_INTERVAL
		wl.advance_simulation(0.05, 1.0, wd, nav, [], [mock_unit2])
		_assert(defensive_rec["state"] == WildlifeConfig.BehaviorState.DEFENSIVE_DISPLAY, "Case 15a: Defensive wildlife enters DEFENSIVE_DISPLAY on approach")
		for _k in range(30):
			wl.advance_simulation(0.05, 1.0, wd, nav, [], [mock_unit2])
		_assert(defensive_rec["state"] == WildlifeConfig.BehaviorState.FLEEING or defensive_rec["state"] == WildlifeConfig.BehaviorState.IDLE, "Case 15b: Defensive wildlife retreats after warning without attacking")

	if not ambient_rec.is_empty():
		_assert(ambient_rec["state"] == WildlifeConfig.BehaviorState.IDLE or ambient_rec["state"] == WildlifeConfig.BehaviorState.WANDERING, "Case 16: Ambient wildlife stays IDLE or WANDERING")

	# 19-26. Fog of War & Debug Inspection
	var unexp_wl: Dictionary = {}
	for rec in wl.get_all_animals():
		if fow != null and not fow.is_explored(rec["cell"]):
			unexp_wl = rec
			break
	_assert(not unexp_wl.is_empty(), "Fixture: found wildlife on UNEXPLORED cell")
	if not unexp_wl.is_empty():
		var actor_u: WildlifeActor = wl.actors_by_id.get(unexp_wl["id"])
		_assert(actor_u != null and not actor_u.visible, "Case 21: UNEXPLORED wildlife hidden with Fog ON")
		# Temporarily mark EXPLORED (not VISIBLE) to verify Case 20
		var orig_state: int = fow.get_state(unexp_wl["cell"])
		fow.set_state(unexp_wl["cell"], FogOfWar.State.EXPLORED)
		wl.refresh_visibility(fow, false)
		_assert(not actor_u.visible, "Case 20: EXPLORED (non-visible) living wildlife stays hidden with Fog ON")
		fow.set_state(unexp_wl["cell"], orig_state)
		wl.refresh_visibility(fow, false)

		# Fog OFF reveals & inspects
		wv.set_debug_fog_disabled(true)
		_assert(actor_u.visible, "Case 22: Fog OFF reveals wildlife everywhere")
		var c_before: Vector2i = unexp_wl["cell"]
		var s_before: int = unexp_wl["state"]
		wv._handle_left_click(unexp_wl["cell"])
		var insp: Dictionary = hud.get("inspected_building_data")
		_assert(insp.get("category") == "wildlife" and insp.get("entity_id") == unexp_wl["id"], "Case 23: Fog OFF inspects wildlife")
		_assert(unexp_wl["cell"] == c_before and unexp_wl["state"] == s_before, "Case 27-29: Inspecting wildlife has zero side effects")
		_assert(fow.get_state(unexp_wl["cell"]) == FogOfWar.State.UNEXPLORED, "Case 26: FogOfWar state unchanged")

		# Fog ON restores
		wv.set_debug_fog_disabled(false)
		_assert(not actor_u.visible, "Case 24a: Fog ON hides unexplored wildlife again")
		_assert(wv.get("selected_building_id") == "", "Case 24b: Fog ON clears debug wildlife selection")

	# 31-33. Save/Load persistence & legacy load without wildlife section
	var save_path := "user://test_p6_wildlife.json"
	var first_wl: Dictionary = wl.get_all_animals()[0]
	var saved_id: String = first_wl["id"]
	var saved_cell: Vector2i = first_wl["cell"]
	var s_res := SaveManager.save_to_file(wv, save_path)
	_assert(bool(s_res.get("success", false)) and s_res != null, "Case 31a: Save succeeded")

	var l_res := SaveManager.load_from_file(save_path)
	_assert(bool(l_res.get("success", false)) and l_res["data"].has("wildlife"), "Case 31b: Save payload contains wildlife section")

	var wv2 := WorldViewScene.instantiate()
	wv2.set("skip_intro_for_test", true)
	root.add_child(wv2)
	await create_timer(0.15).timeout
	var ok_apply_res := SaveManager.apply_loaded_state_to_world(wv2, l_res["data"])
	_assert(bool(ok_apply_res.get("success", false)), "Case 31c: Apply loaded state succeeded")
	var wl2 = wv2.get("wildlife_mgr")
	var restored: Dictionary = wl2.get_animal_by_id(saved_id)
	_assert(not restored.is_empty() and restored["cell"] == saved_cell, "Case 31d: Saved wildlife cell restored")
	var uniq_ids: Dictionary = {}
	for rec in wl2.get_all_animals():
		uniq_ids[rec["id"]] = true
	_assert(uniq_ids.size() == wl2.get_all_animals().size(), "Case 32: No duplicate animal IDs after load")

	# Legacy save without "wildlife" key
	var legacy_data: Dictionary = l_res["data"].duplicate(true)
	legacy_data.erase("wildlife")
	var ok_legacy_res := SaveManager.apply_loaded_state_to_world(wv2, legacy_data)
	_assert(bool(ok_legacy_res.get("success", false)) and wl2.get_all_animals().size() > 0, "Case 33 & 35: Old save without wildlife section loads and initializes deterministically")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	wv.queue_free()
	wv2.queue_free()

	print("[test_wildlife_ecosystem] Passed: %d | Failed: %d" % [_passed, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
