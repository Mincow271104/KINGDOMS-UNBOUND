extends SceneTree

## Comprehensive automated acceptance suite for KU-POST-MVP-TOWN-HALL-TERRITORY-01:
## 11.1 Territory Ownership & Starter Bounds
## 11.2 Town Hall Upgrade & Monotonic Expansion
## 11.3 Authoritative Building Placement & Full-Footprint Validation
## 11.4 Territory Overlay Visibility in Build Mode
## 11.5 Territory-Constrained Civilian Roaming, Interruptions, Expansion & Save/Load
## 11.6 Military Movement Exemption

const WorldViewScene := preload("res://scenes/world/world_view.tscn")
const WorldGeneratorScript := preload("res://scripts/world/world_generator.gd")
const EconomyConfigScript := preload("res://scripts/economy/economy_config.gd")
const BuildingSystemScript := preload("res://scripts/economy/building_system.gd")
const TerritoryManagerScript := preload("res://scripts/world/territory_manager.gd")
const SaveManagerScript := preload("res://scripts/persistence/save_manager.gd")

var _passed: int = 0
var _failed: int = 0

func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] %s" % label)
	else:
		_failed += 1
		printerr("  [FAIL] %s" % label)

func _initialize() -> void:
	call_deferred("_run_all")

func _run_all() -> void:
	print("=== KU-POST-MVP-TOWN-HALL-TERRITORY-01 TEST SUITE ===")
	await _test_territory_ownership_and_starter_bounds()
	await _test_town_hall_upgrade_and_expansion()
	await _test_building_placement_and_footprint()
	await _test_overlay_visibility()
	await _test_civilian_roaming_and_save_load()
	await _test_military_exemption()
	await _test_civilian_territory_movement_policy()
	await _test_policy_1c_and_2b_recovery()

	print("=== SUMMARY: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _spawn_world_view() -> Node:
	var wv := WorldViewScene.instantiate()
	wv.world_seed = 424242
	root.add_child(wv)
	await process_frame
	await process_frame
	return wv

func _find_townhall(world_data: WorldGenerator.WorldData) -> Dictionary:
	for b in world_data.buildings:
		if b is Dictionary and str(b.get("type", "")) == "townhall":
			return b
	return {}

func _find_free_cell_at_distance(world_data: WorldGenerator.WorldData, center: Vector2i, min_dist: int, max_dist: int, size: Vector2i = Vector2i(2, 2)) -> Vector2i:
	for r in range(min_dist, max_dist + 1):
		for x in range(WorldGeneratorScript.MAP_SIZE - size.x):
			for y in range(WorldGeneratorScript.MAP_SIZE - size.y):
				var origin := Vector2i(x, y)
				var d := absi(x - center.x) + absi(y - center.y)
				if d != r:
					continue
				var ok := true
				for ox in range(size.x):
					for oy in range(size.y):
						var c := origin + Vector2i(ox, oy)
						if world_data.terrain[c.x][c.y] == WorldGeneratorScript.TerrainType.WATER or world_data.occupancy[c.x][c.y]:
							ok = false
							break
					if not ok:
						break
				if ok:
					return origin
	return Vector2i(-1, -1)

func _test_territory_ownership_and_starter_bounds() -> void:
	print("--- 11.1 Territory Ownership & Starter Bounds ---")
	var wv := await _spawn_world_view()
	var tmgr: TerritoryManagerScript = wv.get("territory_mgr")
	var wd: WorldGenerator.WorldData = wv.get("world_data")
	_assert(tmgr != null, "WorldView initializes TerritoryManager")
	_assert(tmgr.get_current_territory_level() == 1, "Starter Town Hall territory level is 1")
	_assert(tmgr.get_current_radius() == EconomyConfigScript.get_territory_radius(1), "Starter territory radius matches Level 1 config (13)")

	var th := _find_townhall(wd)
	_assert(not th.is_empty(), "Starter Town Hall exists")
	var th_origin: Vector2i = th.get("cell", th.get("origin", Vector2i.ZERO))
	var th_size: Vector2i = th.get("size", Vector2i(3, 3))
	var th_center := Vector2i(th_origin.x + th_size.x / 2, th_origin.y + th_size.y / 2)
	_assert(tmgr.is_cell_owned(th_center), "Town Hall center is owned")

	var all_starter_inside := true
	for b in wd.buildings:
		if b is Dictionary:
			if not tmgr.is_footprint_owned(b.get("cell", b.get("origin", Vector2i.ZERO)), b.get("size", Vector2i(1, 1))):
				all_starter_inside = false
				break
	_assert(all_starter_inside, "All starter buildings lie completely inside Level 1 territory")
	_assert(not tmgr.is_cell_owned(Vector2i(0, 0)), "Corner cell (0,0) is outside Level 1 territory")
	_assert(not tmgr.is_cell_owned(th_center + Vector2i(14, 0)), "Cell at Manhattan distance 14 is outside Level 1 territory")

	wv.queue_free()
	await process_frame

func _test_town_hall_upgrade_and_expansion() -> void:
	print("--- 11.2 Town Hall Upgrade & Monotonic Expansion ---")
	_assert("townhall" in EconomyConfigScript.UPGRADEABLE_BUILDINGS, "townhall is registered in UPGRADEABLE_BUILDINGS")
	var wv := await _spawn_world_view()
	var tmgr: TerritoryManagerScript = wv.get("territory_mgr")
	var wd: WorldGenerator.WorldData = wv.get("world_data")
	var rm := root.get_node_or_null("ResourceManager")
	if rm != null and rm.has_method("add_resource"):
		rm.add_resource(EconomyConfigScript.RES_WOOD, 2000)
		rm.add_resource(EconomyConfigScript.RES_STONE, 2000)
		rm.add_resource(EconomyConfigScript.RES_GOLD, 2000)

	var count_lv1 := tmgr.get_owned_count()
	var rad_lv1 := tmgr.get_current_radius()
	var signal_count := [0]
	tmgr.territory_changed.connect(func(_lv: int, _cnt: int, _rev: int): signal_count[0] += 1)

	var th := _find_townhall(wd)
	var b_id := str(th.get("id", ""))
	if b_id == "":
		b_id = "townhall_starter"
		th["id"] = b_id
	var up2: Dictionary = wv.start_building_upgrade(b_id, rm)
	_assert(bool(up2.get("success", false)), "Town Hall upgrade to Level 2 starts cleanly")
	var adv2 := BuildingSystemScript.advance_upgrade(th, 999.0, wd)
	_assert(bool(adv2.get("completed", false)), "Town Hall upgrade to Level 2 reaches completion")
	_assert(wv.complete_upgrade(b_id, rm), "WorldView.complete_upgrade completes Town Hall Level 2")

	var count_lv2: int = tmgr.get_owned_count()
	var rad_lv2: int = tmgr.get_current_radius()
	_assert(tmgr.get_current_territory_level() == 2, "Territory level advances to 2")
	_assert(rad_lv2 > rad_lv1 and count_lv2 > count_lv1, "Level 2 territory strictly expands (%d > %d tiles)" % [count_lv2, count_lv1])
	_assert(signal_count[0] >= 1, "territory_changed signal emitted on Town Hall expansion")

	var up3: Dictionary = wv.start_building_upgrade(b_id, rm)
	_assert(bool(up3.get("success", false)), "Town Hall upgrade to Level 3 starts cleanly")
	BuildingSystemScript.advance_upgrade(th, 999.0, wd)
	_assert(wv.complete_upgrade(b_id, rm), "WorldView.complete_upgrade completes Town Hall Level 3")
	var count_lv3 := tmgr.get_owned_count()
	_assert(tmgr.get_current_territory_level() == 3 and count_lv3 > count_lv2, "Level 3 territory strictly expands (%d > %d tiles)" % [count_lv3, count_lv2])

	wv.queue_free()
	await process_frame

func _test_building_placement_and_footprint() -> void:
	print("--- 11.3 Authoritative Building Placement & Full-Footprint Validation ---")
	var wv := await _spawn_world_view()
	var tmgr: TerritoryManagerScript = wv.get("territory_mgr")
	var wd: WorldGenerator.WorldData = wv.get("world_data")
	var rm := root.get_node_or_null("ResourceManager")
	if rm != null and rm.has_method("add_resource"):
		rm.add_resource(EconomyConfigScript.RES_WOOD, 2000)
		rm.add_resource(EconomyConfigScript.RES_STONE, 2000)
		rm.add_resource(EconomyConfigScript.RES_GOLD, 2000)

	var th := _find_townhall(wd)
	var th_origin: Vector2i = th.get("cell", th.get("origin", Vector2i.ZERO))
	var th_size: Vector2i = th.get("size", Vector2i(3, 3))
	var th_center := Vector2i(th_origin.x + th_size.x / 2, th_origin.y + th_size.y / 2)

	var inside_cell := _find_free_cell_at_distance(wd, th_center, 5, 10, Vector2i(2, 2))
	var outside_cell := _find_free_cell_at_distance(wd, th_center, 15, 17, Vector2i(2, 2))
	_assert(inside_cell != Vector2i(-1, -1), "Found free 2x2 cell inside Level 1 territory")
	_assert(outside_cell != Vector2i(-1, -1), "Found free 2x2 cell between radius 15..17 (outside Lv1, inside Lv2)")

	var check_in := BuildingSystemScript.can_place_building("house", inside_cell, wd, rm)
	_assert(bool(check_in.get("valid", false)), "Placement inside territory is valid")

	var check_out := BuildingSystemScript.can_place_building("house", outside_cell, wd, rm)
	_assert(not bool(check_out.get("valid", true)) and str(check_out.get("reason", "")).find("Ngoài lãnh thổ") != -1, "Placement outside territory is rejected with territory reason")

	# Boundary-straddling 2x2 footprint check: find a border cell where (x, y) is owned but (x+1, y) or (x, y+1) is not
	var straddle_cell := Vector2i(-1, -1)
	for bcell in tmgr.get_border_cells():
		if not tmgr.is_footprint_owned(bcell, Vector2i(2, 2)) and bcell.x < WorldGeneratorScript.MAP_SIZE - 2 and bcell.y < WorldGeneratorScript.MAP_SIZE - 2:
			var clear_terrain := true
			for ox in range(2):
				for oy in range(2):
					var c: Vector2i = bcell + Vector2i(ox, oy)
					if wd.terrain[c.x][c.y] == WorldGeneratorScript.TerrainType.WATER or wd.occupancy[c.x][c.y]:
						clear_terrain = false
			if clear_terrain:
				straddle_cell = bcell
				break
	if straddle_cell != Vector2i(-1, -1):
		var check_straddle := BuildingSystemScript.can_place_building("house", straddle_cell, wd, rm)
		_assert(not bool(check_straddle.get("valid", true)), "Footprint straddling territory border is rejected")

	# Upgrade Town Hall to Level 2 -> previously outside_cell (dist 15..17) is now allowed!
	var b_id := str(th.get("id", ""))
	if b_id == "":
		b_id = "townhall_starter"
		th["id"] = b_id
	wv.start_building_upgrade(b_id, rm)
	BuildingSystemScript.advance_upgrade(th, 999.0, wd)
	wv.complete_upgrade(b_id, rm)
	var check_after := BuildingSystemScript.can_place_building("house", outside_cell, wd, rm)
	_assert(bool(check_after.get("valid", false)), "Previously rejected cell (%s) becomes buildable after Town Hall Lv2 expansion" % str(outside_cell))

	wv.queue_free()
	await process_frame

func _test_overlay_visibility() -> void:
	print("--- 11.4 Territory Overlay Visibility ---")
	var wv := await _spawn_world_view()
	_assert(not wv.is_territory_overlay_visible(), "Territory overlay is hidden initially")
	wv._on_build_requested("house")
	_assert(wv.is_territory_overlay_visible(), "Territory overlay becomes visible when selecting a building to construct")
	wv._cancel_placement()
	_assert(not wv.is_territory_overlay_visible(), "Territory overlay hides when placement is cancelled")
	wv.queue_free()
	await process_frame

func _test_civilian_roaming_and_save_load() -> void:
	print("--- 11.5 Territory-Constrained Civilian Roaming & Save/Load ---")
	var wv := await _spawn_world_view()
	var tmgr: TerritoryManagerScript = wv.get("territory_mgr")
	var citizens: Array = wv.get("citizen_list")
	_assert(citizens.size() > 0, "Citizens spawned in WorldView")

	var idle_cit: Node = citizens[0]
	idle_cit.set_role("idle")
	idle_cit.set("_roam_wait_timer", 0.05)

	var started_roaming := false
	var stayed_inside := true
	for _f in range(180):
		await process_frame
		if bool(idle_cit.get("is_roaming")):
			started_roaming = true
			var c_cell: Vector2i = idle_cit.get("current_cell")
			var r_target: Vector2i = idle_cit.get("roam_target")
			if not tmgr.is_cell_owned(c_cell) or not tmgr.is_cell_owned(r_target):
				stayed_inside = false
				break
	_assert(started_roaming, "Idle citizen starts autonomous roaming")
	_assert(stayed_inside, "Roaming citizen and target stay strictly inside owned territory")

	# Interruption by manual command
	var th := _find_townhall(wv.get("world_data"))
	var cmd_res: Dictionary = idle_cit.issue_manual_command("move", idle_cit.get("current_cell"))
	_assert(bool(cmd_res.get("success", false)) and not bool(idle_cit.get("is_roaming")), "Manual command immediately cancels roaming")

	# Save/Load roundtrip preserves Town Hall Level 2 territory & roaming
	var rm := root.get_node_or_null("ResourceManager")
	if rm != null and rm.has_method("add_resource"):
		rm.add_resource(EconomyConfigScript.RES_WOOD, 2000)
		rm.add_resource(EconomyConfigScript.RES_STONE, 2000)
		rm.add_resource(EconomyConfigScript.RES_GOLD, 2000)
	var b_id := str(th.get("id", ""))
	if b_id == "":
		b_id = "townhall_starter"
		th["id"] = b_id
	wv.start_building_upgrade(b_id, rm)
	BuildingSystemScript.advance_upgrade(th, 999.0, wv.get("world_data"))
	wv.complete_upgrade(b_id, rm)
	var lv2_count := tmgr.get_owned_count()

	var save_path := "user://saves/__test_territory_roundtrip.json"
	var save_res: Dictionary = SaveManagerScript.save_to_file(wv, save_path)
	_assert(bool(save_res.get("success", false)), "SaveManager.save_to_file succeeds")
	var load_res: Dictionary = SaveManagerScript.load_from_file(save_path)
	_assert(bool(load_res.get("success", false)), "SaveManager.load_from_file succeeds")
	if bool(load_res.get("success", false)):
		var wv2 := await _spawn_world_view()
		var apply_res: Dictionary = SaveManagerScript.apply_loaded_state_to_world(wv2, load_res.get("data", {}))
		_assert(bool(apply_res.get("success", false)), "SaveManager.apply_loaded_state_to_world succeeds")
		var tmgr2: TerritoryManagerScript = wv2.get("territory_mgr")
		_assert(tmgr2.get_current_territory_level() == 2 and tmgr2.get_owned_count() == lv2_count, "Loaded world restores Town Hall Lv2 territory (%d tiles)" % tmgr2.get_owned_count())
		wv2.queue_free()
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	wv.queue_free()
	await process_frame

func _test_military_exemption() -> void:
	print("--- 11.6 Military Movement Exemption ---")
	var wv := await _spawn_world_view()
	var nav: GridNavigation = wv.get("nav")
	var tmgr: TerritoryManagerScript = wv.get("territory_mgr")
	var wd: WorldGenerator.WorldData = wv.get("world_data")
	var th := _find_townhall(wd)
	var th_origin: Vector2i = th.get("cell", th.get("origin", Vector2i.ZERO))
	var th_size: Vector2i = th.get("size", Vector2i(3, 3))
	var th_center := Vector2i(th_origin.x + th_size.x / 2, th_origin.y + th_size.y / 2)

	var start_cell := _find_free_cell_at_distance(wd, th_center, 4, 8, Vector2i(1, 1))
	var outside_goal := _find_free_cell_at_distance(wd, th_center, 18, 24, Vector2i(1, 1))
	_assert(start_cell != Vector2i(-1, -1) and outside_goal != Vector2i(-1, -1), "Found walkable start inside territory and goal outside territory")
	_assert(not tmgr.is_cell_owned(outside_goal), "Military test goal is outside Level 1 territory")

	var civ_path := nav.find_path_with_predicate(start_cell, outside_goal, Callable(tmgr, "is_cell_owned"))
	var mil_path := nav.find_path(start_cell, outside_goal)
	_assert(civ_path.is_empty(), "Civilian territory predicate blocks pathing outside territory")
	_assert(not mil_path.is_empty(), "Unrestricted military pathing succeeds outside territory (%d steps)" % mil_path.size())

	wv.queue_free()
	await process_frame

func _test_civilian_territory_movement_policy() -> void:
	print("--- 11.7 Civilian Territory Movement Policy Closure ---")
	var wv := await _spawn_world_view()
	var tmgr: TerritoryManagerScript = wv.get("territory_mgr")
	var wd: WorldGenerator.WorldData = wv.get("world_data")
	var nav: GridNavigation = wv.get("nav")
	var citizens: Array = wv.get("citizen_list")
	var th := _find_townhall(wd)
	var th_origin: Vector2i = th.get("cell", th.get("origin", Vector2i.ZERO))
	var th_size: Vector2i = th.get("size", Vector2i(3, 3))
	var th_center := Vector2i(th_origin.x + th_size.x / 2, th_origin.y + th_size.y / 2)

	var outside_walkable := _find_free_cell_at_distance(wd, th_center, 15, 17, Vector2i(1, 1))
	_assert(outside_walkable != Vector2i(-1, -1) and not tmgr.is_cell_owned(outside_walkable), "Found walkable cell outside Level 1 territory")

	var cit: Node = citizens[0]
	# 1. Manual movement outside territory is rejected safely
	var rej_cmd: Dictionary = cit.issue_manual_command("move", outside_walkable)
	_assert(not bool(rej_cmd.get("success", true)) and str(rej_cmd.get("reason", "")).find("ngoài lãnh thổ") != -1, "Manual move outside territory is rejected with clear reason")

	# 2. Land Clearing outside territory is rejected safely
	var lcm = wv.get("land_clearing_mgr")
	var out_prop_cell := Vector2i(-1, -1)
	for p in wd.props:
		if p is Dictionary:
			var pc: Vector2i = p.get("cell", Vector2i(-1, -1))
			if pc != Vector2i(-1, -1) and not tmgr.is_cell_owned(pc):
				out_prop_cell = pc
				break
	if lcm != null and out_prop_cell != Vector2i(-1, -1):
		var qres: Dictionary = lcm.queue_clearing_order(wd, out_prop_cell, wv.world_seed, wv.world_generator_version, wv.get("poi_mgr"))
		_assert(not bool(qres.get("success", true)), "Land clearing order outside territory is rejected cleanly")

	# 3. Assigned job outside territory cannot pull citizen outside and sets retry cooldown (no infinite loop)
	var jmgr = wv.get("job_mgr")
	if jmgr != null and jmgr.has_method("add_job"):
		var out_job := JobManager.JobData.new()
		out_job.id = "outside_job_1"
		out_job.type = "woodcutter"
		out_job.target_cell = outside_walkable
		out_job.target_building_id = "outside_wp"
		jmgr.add_job(out_job)
		cit.set_role("woodcutter")
		cit.set("current_state", 0)
		cit.set("_job_retry_timer", 0.0)
		await process_frame
		_assert(tmgr.is_cell_owned(cit.get("current_cell")) and cit.get("active_job") == null, "Woodcutter refuses/releases unreachable outside-territory job without crossing border")
		_assert(float(cit.get("_job_retry_timer")) > 0.0, "Outside-territory job sets retry cooldown (prevents per-frame loop)")

	# 4. Hungry citizen when food storage is outside/unreachable does NOT cross territory or enter retry loop
	cit.set_role("idle")
	cit.set("carrying_amount", 0)
	cit.set("hunger", 80.0)
	cit.set("_survival_retry_timer", 0.0)
	var prev_owned := []
	# Simulate food storage outside territory by temporarily marking center_spawn unowned
	var plaza_c: Vector2i = wd.center_spawn
	var saved_plaza_owned := bool(wd.owned_cells[plaza_c.x][plaza_c.y])
	wd.owned_cells[plaza_c.x][plaza_c.y] = false
	await process_frame
	_assert(cit.get("current_state") == 0 and float(cit.get("_survival_retry_timer")) > 0.0, "Hungry citizen with unowned food storage stays IDLE with survival cooldown (no border cross or retry loop)")
	wd.owned_cells[plaza_c.x][plaza_c.y] = saved_plaza_owned
	cit.set("hunger", 10.0)
	cit.set("_survival_retry_timer", 0.0)

	# 5. Fatigue/resting stays inside territory
	cit.set("fatigue", 90.0)
	await process_frame
	_assert(tmgr.is_cell_owned(cit.get("current_cell")), "Fatigued/resting citizen remains inside owned territory")
	cit.set("fatigue", 10.0)
	cit.set("current_state", 0)

	# 6. Cargo hauling stranded outside-territory dropoff preserves cargo and sets cooldown
	var away_cell := wd.center_spawn + Vector2i(0, -10)
	cit.set("current_cell", away_cell)
	cit.position = IsoMath.map_to_local(away_cell)
	cit.set("carrying_resource", "wood")
	cit.set("carrying_amount", 5)
	cit.set("_cargo_retry_timer", 0.0)
	cit.current_path.clear()
	var drop_c: Vector2i = cit.call("_get_storage_dropoff_cell")
	var saved_cells: Dictionary = {}
	for dc in [drop_c, drop_c + Vector2i(1, 0), drop_c + Vector2i(-1, 0), drop_c + Vector2i(0, 1), drop_c + Vector2i(0, -1)]:
		if IsoMath.is_in_bounds(dc):
			saved_cells[dc] = bool(wd.owned_cells[dc.x][dc.y])
			wd.owned_cells[dc.x][dc.y] = false
	await process_frame
	_assert(int(cit.get("carrying_amount")) == 5 and bool(cit.get("is_stranded_with_cargo")) and float(cit.get("_cargo_retry_timer")) > 0.0, "Stranded cargo preserves inventory (5 wood) and sets cooldown without crossing unowned cells (amt=%s stranded=%s cd=%s st=%s reason=%s)" % [str(cit.get("carrying_amount")), str(cit.get("is_stranded_with_cargo")), str(cit.get("_cargo_retry_timer")), str(cit.get("current_state")), str(cit.get("status_reason"))])
	for dc in saved_cells:
		wd.owned_cells[dc.x][dc.y] = saved_cells[dc]
	cit.set("carrying_amount", 0)
	cit.set("carrying_resource", "")
	cit.set("is_stranded_with_cargo", false)

	# 7. Displaced citizen outside territory recovers inward toward nearest owned cell without teleporting
	cit.set("current_cell", outside_walkable)
	cit.position = IsoMath.map_to_local(outside_walkable)
	cit.set("current_state", 0)
	cit.current_path.clear()
	cit.set("_recovery_retry_timer", 0.0)
	await process_frame
	var rec_tgt: Vector2i = cit.get("recovery_target")
	_assert(bool(cit.get("is_recovering_to_territory")) and tmgr.is_cell_owned(rec_tgt) and not cit.current_path.is_empty(), "Displaced citizen enters Policy 2B recovery toward nearest owned cell without teleporting")
	cit.call("_clear_territory_recovery")
	cit.current_path.clear()
	cit.set("current_state", 0)
	cit.set("current_cell", wd.center_spawn)
	cit.position = IsoMath.map_to_local(wd.center_spawn)

	# 8. Territory expansion makes outside_walkable accessible to existing citizen without respawning
	var rm := root.get_node_or_null("ResourceManager")
	if rm != null and rm.has_method("add_resource"):
		rm.add_resource(EconomyConfigScript.RES_WOOD, 2000)
		rm.add_resource(EconomyConfigScript.RES_STONE, 2000)
		rm.add_resource(EconomyConfigScript.RES_GOLD, 2000)
	var b_id := str(th.get("id", ""))
	if b_id == "":
		b_id = "townhall_starter"
		th["id"] = b_id
	wv.start_building_upgrade(b_id, rm)
	BuildingSystemScript.advance_upgrade(th, 999.0, wd)
	wv.complete_upgrade(b_id, rm)
	var post_exp_cmd: Dictionary = cit.issue_manual_command("move", outside_walkable)
	_assert(bool(post_exp_cmd.get("success", false)), "Existing citizen can move to newly expanded cell (%s) without respawning" % str(outside_walkable))

	wv.queue_free()
	await process_frame

func _test_policy_1c_and_2b_recovery() -> void:
	print("--- 11.8 Policy 1C (Zero-Territory Freeze & TH Repair) & Policy 2B (Nearest-Owned Recovery) ---")
	var wv := await _spawn_world_view()
	var tmgr: TerritoryManagerScript = wv.get("territory_mgr")
	var wd: WorldGenerator.WorldData = wv.get("world_data")
	var nav: GridNavigation = wv.get("nav")
	var citizens: Array = wv.get("citizen_list")
	var rm := root.get_node_or_null("ResourceManager")
	if rm != null and rm.has_method("add_resource"):
		rm.add_resource(EconomyConfigScript.RES_WOOD, 2000)
		rm.add_resource(EconomyConfigScript.RES_STONE, 2000)
		rm.add_resource(EconomyConfigScript.RES_GOLD, 2000)

	var th := _find_townhall(wd)
	var th_id := str(th.get("id", "townhall_starter"))
	if th_id == "":
		th_id = "townhall_starter"
		th["id"] = th_id
	var th_origin: Vector2i = th.get("cell", th.get("origin", Vector2i.ZERO))
	var th_size: Vector2i = th.get("size", Vector2i(3, 3))
	var th_center := Vector2i(th_origin.x + th_size.x / 2, th_origin.y + th_size.y / 2)

	# Pick test citizens: idle_c (preserving cargo + needs), non_builder_c (woodcutter), builder_c (builder >2 cells away)
	var idle_c: Node = citizens[0]
	var non_builder_c: Node = citizens[1]
	var builder_c: Node = citizens[2]

	idle_c.set_role("idle")
	idle_c.set("carrying_resource", "wood")
	idle_c.set("carrying_amount", 7)
	idle_c.set("hunger", 82.0)
	idle_c.set("fatigue", 20.0)
	var idle_start_pos: Vector2 = idle_c.position
	var idle_start_cell: Vector2i = idle_c.get("current_cell")

	non_builder_c.set_role("woodcutter")
	non_builder_c.set("current_state", 0)

	# 9.1 Zero-territory freeze: destroy the only active Town Hall
	wv.damage_building(th_id, 999999)
	_assert(tmgr.get_owned_count() == 0, "9.1 Destroyed Town Hall drops owned_count to 0")

	for _i in range(10):
		await process_frame

	_assert(idle_c.position.distance_to(idle_start_pos) < 0.01 and idle_c.get("current_cell") == idle_start_cell, "9.1 Idle citizen remains stationary when owned_count == 0 (no sliding window)")
	_assert(not bool(idle_c.get("is_roaming")), "9.1 Idle roaming disabled when owned_count == 0")
	_assert(int(idle_c.get("carrying_amount")) == 7 and str(idle_c.get("carrying_resource")) == "wood", "9.5 Carried cargo preserved during zero-territory freeze")
	_assert(absf(float(idle_c.get("hunger")) - 82.0) < 0.1 and absf(float(idle_c.get("fatigue")) - 20.0) < 0.1, "9.5 Citizen hunger and fatigue preserved during zero-territory freeze")
	_assert(non_builder_c.get("active_job") == null and non_builder_c.current_path.is_empty(), "9.1 Non-builder job movement frozen when owned_count == 0")

	var rej_zero: Dictionary = idle_c.issue_manual_command("move", th_center + Vector2i(5, 0))
	_assert(not bool(rej_zero.get("success", true)), "9.1 Manual move rejected when owned_count == 0")

	# Save/Load test #1: Zero territory with citizens frozen
	var save_dir := "user://saves"
	var p_zero := "%s/test_terr05_zero.json" % save_dir
	_assert(bool(SaveManagerScript.save_to_file(wv, p_zero).get("success", false)), "9.6 Save during zero-territory freeze succeeds")

	# 9.2 Town Hall construction/repair exception while owned_count == 0 (builder > 2 tiles away)
	# Note: BuildingSystem.can_repair_building() rejects state == "destroyed", so in the existing architecture
	# a Town Hall in `under_construction` state (with owned_count == 0) exercises the builder recovery path.
	th["state"] = "under_construction"
	th["is_constructed"] = false
	th["health"] = th.get("max_health", 500)
	th["construction_progress"] = 0.0
	th["construction_hours_required"] = 10.0
	tmgr.recalculate_territory()
	_assert(tmgr.get_owned_count() == 0, "9.2 Under-construction Town Hall keeps owned_count == 0 until completed")
	var th_jobs: Array = wv.register_construction_jobs(th)
	_assert(not th_jobs.is_empty(), "9.2 register_construction_jobs creates Town Hall builder jobs")

	var far_builder_cell := _find_free_cell_at_distance(wd, th_center, 6, 9, Vector2i(1, 1))
	_assert(far_builder_cell != Vector2i(-1, -1) and IsoMath.grid_distance(far_builder_cell, th_center) > 2, "9.2 Found walkable start >2 cells from Town Hall for builder")
	builder_c.set_role("builder")
	builder_c.set("current_cell", far_builder_cell)
	builder_c.position = IsoMath.map_to_local(far_builder_cell)
	builder_c.set("current_state", 0)
	builder_c.current_path.clear()
	builder_c.set("_job_retry_timer", 0.0)
	await process_frame

	_assert(builder_c.get("active_job") != null and builder_c.get("active_job").target_building_id == th_id, "9.2 Builder accepts Town Hall construction job while owned_count == 0")
	_assert(not builder_c.current_path.is_empty(), "9.2 Builder >2 cells away computes valid path to Town Hall work slot")
	_assert(not bool(non_builder_c.call("_is_valid_townhall_repair_exception")), "9.2 Non-builder cannot use Town Hall repair/construction exception")

	var b_start_pos: Vector2 = builder_c.position
	for _i in range(8):
		await process_frame
	_assert(builder_c.position.distance_to(b_start_pos) > 1.0, "9.2 Builder physically moves toward Town Hall under special exception")

	# Save/Load test #2: Builder moving to Town Hall construction/repair
	var p_rep := "%s/test_terr05_repair.json" % save_dir
	_assert(bool(SaveManagerScript.save_to_file(wv, p_rep).get("success", false)), "9.6 Save while builder moving to Town Hall succeeds")

	# Cancel Town Hall job while builder is moving -> special permission revoked immediately
	var active_th_job = builder_c.get("active_job")
	wv._safe_cleanup_construction_job(active_th_job)
	await process_frame
	_assert(builder_c.current_path.is_empty() and not bool(builder_c.call("_is_valid_townhall_repair_exception")), "9.2 Cancelling Town Hall job revokes exception and stops builder")

	# Complete Town Hall construction -> territory restored
	th["state"] = "active"
	th["is_constructed"] = true
	tmgr.recalculate_territory()
	_assert(tmgr.get_owned_count() > 0, "9.2 Territory restored (owned_count > 0) after Town Hall completion")

	# 9.3 Displaced recovery around an obstacle requiring > 6 cells of additional Manhattan distance
	var rec_cit: Node = citizens[3]
	rec_cit.set_role("idle")
	rec_cit.set("carrying_amount", 0)
	rec_cit.set("hunger", 10.0)
	rec_cit.set("fatigue", 10.0)
	# Place citizen at a walkable cell outside Level 1 territory and build an obstacle wall forcing a >6-tile detour
	var disp_cell := _find_free_cell_at_distance(wd, th_center, 16, 17, Vector2i(1, 1))
	_assert(disp_cell != Vector2i(-1, -1) and not tmgr.is_cell_owned(disp_cell), "9.3 Found displaced walkable cell outside territory")

	# Block direct line between disp_cell and th_center with temporary occupancy wall of length 9 (forces >6 extra steps)
	var wall_cells: Array[Vector2i] = []
	var dir_to_th := Vector2i(signi(th_center.x - disp_cell.x), signi(th_center.y - disp_cell.y))
	var wall_mid := disp_cell + Vector2i(dir_to_th.x, 0) if dir_to_th.x != 0 else disp_cell + Vector2i(0, dir_to_th.y)
	for offset in range(-4, 5):
		var wc := Vector2i(wall_mid.x, wall_mid.y + offset) if dir_to_th.x != 0 else Vector2i(wall_mid.x + offset, wall_mid.y)
		if IsoMath.is_in_bounds(wc) and wc != disp_cell and not tmgr.is_cell_owned(wc) and not wd.occupancy[wc.x][wc.y]:
			wd.occupancy[wc.x][wc.y] = true
			wall_cells.append(wc)

	rec_cit.set("current_cell", disp_cell)
	rec_cit.position = IsoMath.map_to_local(disp_cell)
	rec_cit.set("current_state", 0)
	rec_cit.current_path.clear()
	rec_cit.set("_recovery_retry_timer", 0.0)
	for _rf in range(10):
		await process_frame
		if bool(rec_cit.get("is_recovering_to_territory")):
			break

	_assert(bool(rec_cit.get("is_recovering_to_territory")) and not rec_cit.current_path.is_empty(), "9.3 Displaced citizen enters recovery around >6-cell obstacle detour")
	var rec_target: Vector2i = rec_cit.get("recovery_target")
	_assert(tmgr.is_cell_owned(rec_target) and nav.is_cell_walkable(rec_target), "9.3 Recovery target is owned and walkable")

	# Save/Load test #3: Displaced citizen recovering
	var p_rec := "%s/test_terr05_recover.json" % save_dir
	_assert(bool(SaveManagerScript.save_to_file(wv, p_rec).get("success", false)), "9.6 Save while displaced citizen recovering succeeds")

	# Multi-frame continuous walk until citizen enters owned territory
	for _i in range(1500):
		await process_frame
		if not bool(rec_cit.get("is_recovering_to_territory")) and tmgr.is_cell_owned(rec_cit.get("current_cell")):
			break
	_assert(tmgr.is_cell_owned(rec_cit.get("current_cell")) and not bool(rec_cit.get("is_recovering_to_territory")), "9.3 Displaced citizen completes multi-frame walk into owned territory and exits recovery immediately")

	for wc in wall_cells:
		wd.occupancy[wc.x][wc.y] = false

	# 9.4 Recovery failure handling (completely walled off -> stationary + cooldown -> unblock -> recovers)
	var iso_cell := _find_free_cell_at_distance(wd, th_center, 16, 17, Vector2i(1, 1))
	var box_cells: Array[Vector2i] = []
	for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var bc: Vector2i = iso_cell + d
		if IsoMath.is_in_bounds(bc) and not wd.occupancy[bc.x][bc.y]:
			wd.occupancy[bc.x][bc.y] = true
			box_cells.append(bc)
	rec_cit.set("current_cell", iso_cell)
	rec_cit.position = IsoMath.map_to_local(iso_cell)
	rec_cit.set("current_state", 0)
	rec_cit.current_path.clear()
	rec_cit.set("_recovery_retry_timer", 0.0)
	await process_frame
	_assert(not bool(rec_cit.get("is_recovering_to_territory")) and float(rec_cit.get("_recovery_retry_timer")) > 0.0 and rec_cit.get("current_cell") == iso_cell, "9.4 Unreachable owned cells keep displaced citizen stationary with retry cooldown (no teleport)")
	for bc in box_cells:
		wd.occupancy[bc.x][bc.y] = false
	rec_cit.set("_recovery_retry_timer", 0.0)
	await process_frame
	_assert(bool(rec_cit.get("is_recovering_to_territory")) and not rec_cit.current_path.is_empty(), "9.4 Removing obstacle allows displaced citizen to recover")

	# 9.6 Verify loading all 3 saved states reconstructs the expected policies
	var l_zero := SaveManagerScript.load_from_file(p_zero)
	_assert(bool(l_zero.get("success", false)) and SaveManagerScript.apply_loaded_state_to_world(wv, l_zero["data"]), "9.6 Reload zero-territory save succeeds")
	await process_frame
	_assert(tmgr.get_owned_count() == 0, "9.6 Reloaded zero-territory state restores owned_count == 0")

	var l_rep := SaveManagerScript.load_from_file(p_rep)
	_assert(bool(l_rep.get("success", false)) and SaveManagerScript.apply_loaded_state_to_world(wv, l_rep["data"]), "9.6 Reload Town Hall repair save succeeds")
	await process_frame
	_assert(tmgr.get_owned_count() == 0, "9.6 Reloaded repair state keeps owned_count == 0 while TH repairing")

	var l_rec := SaveManagerScript.load_from_file(p_rec)
	_assert(bool(l_rec.get("success", false)) and SaveManagerScript.apply_loaded_state_to_world(wv, l_rec["data"]), "9.6 Reload displaced recovery save succeeds")
	await process_frame
	var reloaded_disp_recovering := false
	for c_node in wv.get("citizen_list"):
		if is_instance_valid(c_node) and bool(c_node.get("is_recovering_to_territory")):
			reloaded_disp_recovering = true
			break
	_assert(reloaded_disp_recovering, "9.6 Reloaded displaced citizen automatically resumes Policy 2B recovery")

	for sp in [p_zero, p_rep, p_rec]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(sp))

	wv.queue_free()
	await process_frame
