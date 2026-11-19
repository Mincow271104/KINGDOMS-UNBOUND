extends SceneTree
## Phase 6 Automated Test Suite: Rival Villager Actors, Movement, Pathfinding & Hybrid LOD
## Covers Categories A–I + Performance Ladder (36/72/144/300/600 NPCs) using actual production systems.

const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const SettlementDataScript = preload("res://scripts/world/settlement_data.gd")
const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementVillagerContextScript = preload("res://scripts/world/settlement_villager_context.gd")
const SettlementSimulationManagerScript = preload("res://scripts/world/settlement_simulation_manager.gd")
const SettlementNavigationContextScript = preload("res://scripts/world/settlement_navigation_context.gd")
const PathRequestSchedulerScript = preload("res://scripts/world/path_request_scheduler.gd")
const RivalVillagerActorScript = preload("res://scripts/world/rival_villager_actor.gd")
const RivalVillagerActorPoolScript = preload("res://scripts/world/rival_villager_actor_pool.gd")
const RivalPresentationControllerScript = preload("res://scripts/world/rival_presentation_controller.gd")
const GridNavigationScript = preload("res://scripts/navigation/grid_navigation.gd")
const FogOfWarScript = preload("res://scripts/world/fog_of_war.gd")
const WorldViewScene = preload("res://scenes/world/world_view.tscn")

var _passed: int = 0
var _failed: int = 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] %s" % msg)
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)

func _make_flat_world(w: int = 64, h: int = 64) -> WorldGeneratorScript.WorldData:
	IsoMath.set_active_map_dimensions(w, h)
	var wd := WorldGeneratorScript.WorldData.new()
	wd.map_width = w
	wd.map_height = h
	wd.terrain = []
	wd.occupancy = []
	wd.owned_cells = []
	for x in range(w):
		var t_col: Array[int] = []
		var o_col: Array[bool] = []
		var own_col: Array[bool] = []
		for y in range(h):
			t_col.append(WorldGeneratorScript.TerrainType.GRASS)
			o_col.append(false)
			own_col.append(false)
		wd.terrain.append(t_col)
		wd.occupancy.append(o_col)
		wd.owned_cells.append(own_col)
	return wd

func _make_settlement(sid: String, fid: String, anchor: Vector2i, extra_buildings: Array = []) -> RefCounted:
	var stl := SettlementDataScript.new(sid, fid, fid, SettlementDataScript.ROLE_VILLAGE, anchor)
	var blds: Array[Dictionary] = [
		{"id": "%s_th" % sid, "type": "townhall", "cell": anchor, "size": Vector2i(2, 2), "role": "hq", "blocking": true},
		{"id": "%s_h1" % sid, "type": "house", "cell": anchor + Vector2i(3, 0), "size": Vector2i(2, 2), "role": "residential", "blocking": true}
	]
	for eb in extra_buildings:
		blds.append(eb)
	stl.buildings = blds
	return stl

func _run_category_a_ownership() -> void:
	print("\n[Category A] Canonical Movement Ownership")
	var wd := _make_flat_world(64, 64)
	var stl := _make_settlement("stl_a", "neutral_tribe", Vector2i(10, 10))
	var ctx := SettlementVillagerContextScript.new("stl_a", "neutral_tribe")
	ctx.reconcile_buildings(stl)
	var v = ctx.create_and_add_villager("V1", SettlementVillagerDataScript.ROLE_IDLE, Vector2i(12, 12))

	var gnav := GridNavigationScript.new(wd)
	var nctx := SettlementNavigationContextScript.new("stl_a", wd, gnav, stl)
	var loc := nctx.get_or_create_locomotion(v)

	_assert(v.cell == Vector2i(12, 12), "A1: SettlementVillagerData.cell is canonical initial position")
	_assert(loc.get("current_cell") == null, "A2: LocomotionState does not store a duplicate current_cell")
	_assert(loc.from_cell == Vector2i(12, 12) and loc.to_cell == Vector2i(12, 12) and loc.visual_pos == IsoMath.map_to_local(Vector2i(12, 12)), "A3: LocomotionState reconstructed from canonical v.cell")

	# Actor never mutates v.cell
	var actor := RivalVillagerActorScript.new()
	actor.bind_villager("stl_a", v.villager_id, "neutral_tribe", v.role)
	actor.sync_presentation(Vector2(500, 500), false, 0, true, true, 0.1)
	_assert(v.cell == Vector2i(12, 12), "A4: Actor sync never mutates canonical v.cell")

	# Dehydration preserves LocomotionState and v.cell
	var pool := RivalVillagerActorPoolScript.new(null, 4)
	var p_act: Node2D = pool.acquire("stl_a", v.villager_id, "neutral_tribe", v.role)
	p_act.sync_presentation(loc.visual_pos, false, 0, false, true, 0.0)
	pool.release("stl_a", v.villager_id)
	_assert(v.cell == Vector2i(12, 12) and nctx.has_locomotion(v.villager_id), "A5: Dehydration preserves v.cell and LocomotionState")

	# Pool rebinding never mixes previous villager
	var v2 = ctx.create_and_add_villager("V2", SettlementVillagerDataScript.ROLE_FARMER, Vector2i(14, 14))
	var p_act2: Node2D = pool.acquire("stl_a", v2.villager_id, "rival_military", v2.role)
	_assert(p_act2 == p_act and p_act2.bound_villager_id == v2.villager_id and p_act2.bound_faction_id == "rival_military", "A6: Rebound pooled actor carries only new villager identity")
	pool.dispose_all()
	actor.free()

func _run_category_b_and_c_navigation_and_bounds() -> void:
	print("\n[Category B & C] Navigation, Isolation, External Targets & Activity Bounds")
	var wd := _make_flat_world(80, 80)
	# Water river at x=20, with bridge at (20, 15)
	for y in range(80):
		wd.terrain[20][y] = WorldGeneratorScript.TerrainType.WATER
	wd.bridge_walkable_cells[Vector2i(20, 15)] = "bridge_1"

	var stl_a := _make_settlement("stl_nav_a", "neutral_tribe", Vector2i(10, 10), [
		{"id": "a_farm", "type": "farm", "cell": Vector2i(10, 14), "size": Vector2i(2, 2), "role": "production", "blocking": true},
		{"id": "a_wood", "type": "woodcutter", "cell": Vector2i(14, 10), "size": Vector2i(2, 2), "role": "production", "blocking": true}
	])
	var stl_b := _make_settlement("stl_nav_b", "rival_military", Vector2i(30, 10))
	for c in stl_a.get_building_cells() + stl_b.get_building_cells():
		wd.occupancy[c.x][c.y] = true

	var gnav := GridNavigationScript.new(wd)
	var nctx_a := SettlementNavigationContextScript.new("stl_nav_a", wd, gnav, stl_a)
	nctx_a.configure_settlement_geometry(stl_a, [stl_a, stl_b])
	var nctx_b := SettlementNavigationContextScript.new("stl_nav_b", wd, gnav, stl_b)
	nctx_b.configure_settlement_geometry(stl_b, [stl_a, stl_b])

	_assert(nctx_a.is_cell_walkable(Vector2i(12, 12)), "B1: In-bounds grass cell is walkable")
	_assert(not nctx_a.is_cell_walkable(Vector2i(20, 10)), "B2: Water cell is blocked")
	_assert(nctx_a.is_cell_walkable(Vector2i(20, 15)), "B3: Bridge cell over water is walkable")
	_assert(not nctx_a.is_cell_walkable(Vector2i(30, 10)), "B4: Other settlement building cell is rejected")
	_assert(not nctx_a.is_cell_walkable(Vector2i(10, 10)), "B5: Own blocking building footprint is not walkable")

	# External Hunter prey at (45, 10) (~35 cells from Town Hall) & Woodcutter tree at (22, 10)
	wd.occupancy[22][10] = true # Tree occupies cell
	wd.wildlife.append({"id": "deer_1", "species_id": "deer", "cell": Vector2i(45, 10)})
	wd.wildlife_by_id["deer_1"] = wd.wildlife[0]

	var ctx_a := SettlementVillagerContextScript.new("stl_nav_a", "neutral_tribe")
	ctx_a.reconcile_buildings(stl_a)
	var vh = ctx_a.create_and_add_villager("Hunter", SettlementVillagerDataScript.ROLE_HUNTER, Vector2i(12, 10))
	vh.task_state = SettlementVillagerDataScript.TASK_WORKING
	vh.active_job_id = "job__stl_nav_a__stl_nav_a_th__hunter__1"
	ctx_a.sim_state.production_sources["stl_nav_a_th__hunter"] = {"type": "hunter_source", "current_prey_id": "deer_1"}
	# Create matching job record for test
	var jh := SettlementJobBoard.NpcJobRecord.new()
	jh.job_id = vh.active_job_id
	jh.settlement_id = "stl_nav_a"
	jh.job_type = SettlementVillagerDataScript.ROLE_HUNTER
	jh.workplace_id = "stl_nav_a_th__hunter"
	jh.target_cell = Vector2i(11, 12)
	ctx_a.job_board.register_job(jh)

	var h_intent: Dictionary = nctx_a.resolve_intent(ctx_a, vh)
	_assert(h_intent["dest_cell"] == Vector2i(45, 10), "B6/C1: External Hunter prey destination (35 cells away) resolved")

	var vw = ctx_a.create_and_add_villager("Woodcutter", SettlementVillagerDataScript.ROLE_WOODCUTTER, Vector2i(14, 12))
	vw.task_state = SettlementVillagerDataScript.TASK_WORKING
	vw.active_job_id = "job__stl_nav_a__a_wood__woodcutter__1"
	ctx_a.sim_state.production_sources["a_wood"] = {"resource": "wood", "trees": [{"cell": Vector2i(22, 10), "remaining_milli": 5000}]}
	var jw := SettlementJobBoard.NpcJobRecord.new()
	jw.job_id = vw.active_job_id
	jw.settlement_id = "stl_nav_a"
	jw.job_type = SettlementVillagerDataScript.ROLE_WOODCUTTER
	jw.workplace_id = "a_wood"
	jw.target_cell = Vector2i(14, 12)
	ctx_a.job_board.register_job(jw)

	var w_intent: Dictionary = nctx_a.resolve_intent(ctx_a, vw)
	var w_dest: Vector2i = w_intent["dest_cell"]
	_assert(w_dest != Vector2i(22, 10) and IsoMath.grid_distance(w_dest, Vector2i(22, 10)) == 1 and nctx_a.is_cell_walkable(w_dest), "B7/C2: Occupied tree resolves to adjacent walkable cell")

	nctx_a.invalidate_activity_bounds()
	var act_bounds: Rect2i = nctx_a.get_activity_bounds(ctx_a)
	_assert(act_bounds.has_point(Vector2i(45, 10)) and act_bounds.has_point(Vector2i(22, 10)), "C3: Activity bounds include external Hunter prey and Woodcutter tree")

	# Navigation revision invalidates path cache
	nctx_a.store_cached_path(Vector2i(12, 10), Vector2i(15, 10), [Vector2i(12, 10), Vector2i(15, 10)])
	nctx_a.bump_nav_revision()
	_assert(nctx_a.get_cached_path(Vector2i(12, 10), Vector2i(15, 10)).is_empty(), "B8: bump_nav_revision clears stale cached paths")

func _run_category_d_incremental_astar_and_scheduler() -> void:
	print("\n[Category D] Incremental A* & PathRequestScheduler")
	var wd := _make_flat_world(64, 64)
	var gnav := GridNavigationScript.new(wd)

	# D1-D4: Incremental A* start, pause at budget, resume, complete
	var s := gnav.create_incremental_astar_search(Vector2i(2, 2), Vector2i(40, 40), Callable(), 2048, 1)
	_assert(s.status == GridNavigationScript.NearestSearchStatus.IN_PROGRESS, "D1: Incremental A* starts IN_PROGRESS")
	var step1 := gnav.step_incremental_astar_search(s, 10)
	_assert(int(step1["status"]) == GridNavigationScript.NearestSearchStatus.IN_PROGRESS and int(step1["step_expansions"]) == 10, "D2: Search pauses at exact step_budget (10 expansions)")
	var safety: int = 0
	while s.status == GridNavigationScript.NearestSearchStatus.IN_PROGRESS and safety < 500:
		safety += 1
		gnav.step_incremental_astar_search(s, 50)
	_assert(s.status == GridNavigationScript.NearestSearchStatus.FOUND and not s.path.is_empty(), "D3: Resumed incremental A* finds valid path")

	# D5: Unreachable target fails safely
	for y in range(64):
		wd.occupancy[10][y] = true
	var s_fail := gnav.create_incremental_astar_search(Vector2i(2, 2), Vector2i(20, 2), Callable(), 2048, 1)
	for _i in range(30):
		if s_fail.status != GridNavigationScript.NearestSearchStatus.IN_PROGRESS:
			break
		gnav.step_incremental_astar_search(s_fail, 50)
	_assert(s_fail.status == GridNavigationScript.NearestSearchStatus.UNREACHABLE, "D4: Unreachable target fails cleanly with UNREACHABLE")

	# D6-D13: Scheduler budgets, round-robin fairness, deduplication, cancellation, overflow
	var wd2 := _make_flat_world(64, 64)
	var gnav2 := GridNavigationScript.new(wd2)
	var sched := PathRequestSchedulerScript.new()
	sched.max_expansions_per_frame = 64
	sched.max_admissions_per_frame = 2
	sched.max_queue_size = 5

	var nctx_1 := SettlementNavigationContextScript.new("s1", wd2, gnav2)
	var nctx_2 := SettlementNavigationContextScript.new("s2", wd2, gnav2)
	var v1 := SettlementVillagerDataScript.new("npc_s1_1", "s1", "neutral_tribe", "V1", "idle", Vector2i(2, 2))
	var v2 := SettlementVillagerDataScript.new("npc_s2_1", "s2", "rival_military", "V2", "idle", Vector2i(2, 4))
	var loc1 := nctx_1.get_or_create_locomotion(v1)
	loc1.intent_key = "go_30_30"
	loc1.destination_cell = Vector2i(30, 30)
	var loc2 := nctx_2.get_or_create_locomotion(v2)
	loc2.intent_key = "go_35_35"
	loc2.destination_cell = Vector2i(35, 35)

	sched.enqueue("s1", v1.villager_id, v1.cell, Vector2i(30, 30), "go_30_30", nctx_1.nav_revision, PathRequestSchedulerScript.PRIO_VISIBLE_NEAR, nctx_1, v1)
	# Deduplicate identical key
	sched.enqueue("s1", v1.villager_id, v1.cell, Vector2i(30, 30), "go_30_30", nctx_1.nav_revision, PathRequestSchedulerScript.PRIO_VISIBLE_NEAR, nctx_1, v1)
	_assert(sched.get_queue_size() == 1, "D5: Deduplication prevents duplicate pending requests for same villager")

	sched.enqueue("s2", v2.villager_id, v2.cell, Vector2i(35, 35), "go_35_35", nctx_2.nav_revision, PathRequestSchedulerScript.PRIO_VISIBLE_NEAR, nctx_2, v2)
	sched.step_frame()
	_assert(sched.last_frame_expansions <= 64 and sched.last_frame_admitted == 2, "D6: Scheduler enforces global expansion budget (<=64) and admission cap (2)")

	# Overflow cap test
	for i in range(10):
		var vx := SettlementVillagerDataScript.new("npc_s1_%d" % (i + 10), "s1", "neutral_tribe", "VX", "idle", Vector2i(2, 2))
		var lx := nctx_1.get_or_create_locomotion(vx)
		lx.intent_key = "k%d" % i
		sched.enqueue("s1", vx.villager_id, vx.cell, Vector2i(25, 25), lx.intent_key, nctx_1.nav_revision, PathRequestSchedulerScript.PRIO_MID, nctx_1, vx)
	_assert(sched.get_queue_size() <= 5, "D7: Queue size never exceeds max_queue_size (5)")

	# Stale cancellation on nav_revision bump
	nctx_1.bump_nav_revision()
	sched.step_frame()
	_assert(sched.total_cancelled > 0, "D8: Stale requests cancelled on nav_revision change")

func _run_category_e_f_g_h_movement_lod_pool_camera_fog() -> void:
	print("\n[Category E, F, G, H] Movement, LOD, Hysteresis, Pool, Camera & Fog")
	var wd := _make_flat_world(80, 80)
	var gnav := GridNavigationScript.new(wd)
	var stl := _make_settlement("stl_lod", "neutral_tribe", Vector2i(20, 20), [
		{"id": "farm_a", "type": "farm", "cell": Vector2i(24, 20), "size": Vector2i(2, 2), "role": "production", "blocking": true},
		{"id": "farm_b", "type": "farm", "cell": Vector2i(28, 20), "size": Vector2i(2, 2), "role": "production", "blocking": true}
	])
	for c in stl.get_building_cells():
		wd.occupancy[c.x][c.y] = true

	var mgr := SettlementSimulationManagerScript.new()
	mgr.set_world_data(wd)
	var ctx := SettlementVillagerContextScript.new("stl_lod", "neutral_tribe")
	ctx.reconcile_buildings(stl)
	var v = ctx.create_and_add_villager("Mover", SettlementVillagerDataScript.ROLE_FARMER, Vector2i(20, 23))
	mgr.register_context(ctx)

	var cam := Camera2D.new()
	cam.zoom = Vector2(1.5, 1.5)
	cam.position = IsoMath.map_to_local(Vector2i(20, 23))
	var fog := FogOfWarScript.new(80, 80)
	fog.reveal_circle(Vector2i(20, 23), 10)
	var pool_node := Node2D.new()

	var ctrl := RivalPresentationControllerScript.new()
	ctrl.setup(mgr, wd, gnav, cam, fog, pool_node)

	# Camera world rect across zooms
	for z_val in [0.5, 1.0, 1.5, 3.0]:
		cam.zoom = Vector2(z_val, z_val)
		var r := RivalPresentationControllerScript.compute_camera_world_rect(cam, Vector2(1280, 720))
		_assert(is_equal_approx(r.size.x, 1280.0 / z_val) and is_equal_approx(r.size.y, 720.0 / z_val), "H1: Camera world rect scales accurately at zoom %.1f" % z_val)
	cam.zoom = Vector2(1.5, 1.5)

	# Hydrate Near visible villager
	ctrl.update_presentation(0.016, 1.0)
	_assert(ctrl.get_villager_lod("stl_lod", v.villager_id) == RivalPresentationControllerScript.LODTier.NEAR, "F1: Visible villager near camera enters NEAR LOD")
	_assert(ctrl.get_actor_pool().get_active_count() == 1, "G1: Near visible villager acquires 1 pooled actor")

	# Fog of War: EXPLORED (non-VISIBLE) immediately hides/releases actor
	fog.update_observers([], 0) # Degrades VISIBLE -> EXPLORED
	ctrl.update_presentation(0.016, 1.0)
	_assert(ctrl.get_actor_pool().get_active_count() == 0, "H2: Losing Fog VISIBLE immediately releases actor")

	# Debug fog override restores hydration
	ctrl.debug_fog_disabled = true
	ctrl.update_presentation(0.016, 1.0)
	_assert(ctrl.get_actor_pool().get_active_count() == 1, "H3: debug_fog_disabled permits hydration")

	# Movement & speed policy (Pause freezes, 3x advances)
	var nctx: RefCounted = ctrl.get_navigation_context("stl_lod")
	nctx.apply_computed_path(v, ([Vector2i(20, 23), Vector2i(21, 23), Vector2i(22, 23), Vector2i(23, 23)] as Array[Vector2i]), nctx.get_or_create_locomotion(v).intent_key, nctx.nav_revision)
	var loc: RefCounted = nctx.get_or_create_locomotion(v)
	var pos_before_pause: Vector2 = loc.visual_pos
	ctrl.update_presentation(0.1, 0.0) # Paused
	_assert(loc.visual_pos == pos_before_pause, "E1: Pause (speed_mult=0) freezes visual locomotion")

	ctrl.update_presentation(0.1, 3.0) # 3x speed
	_assert(loc.visual_pos.distance_to(pos_before_pause) > 10.0, "E2: 3x speed advances locomotion proportionally")
	_assert(v.work_hours_done == 0.0, "E3: Visual movement never modifies work_hours_done")

	# Hysteresis & Far Farm A -> Farm B test
	var near_edge_pos := IsoMath.map_to_local(Vector2i(20, 23)) + Vector2(700.0, 0.0)
	cam.position = near_edge_pos # Move camera ~700px away (inside MID_EXIT, outside NEAR_EXIT)
	ctrl.update_presentation(0.016, 1.0)
	_assert(ctrl.get_villager_lod("stl_lod", v.villager_id) != RivalPresentationControllerScript.LODTier.NEAR, "F2: Moving camera past NEAR_EXIT dehydrates villager")
	_assert(ctrl.get_actor_pool().get_active_count() == 0, "F3: Dehydrated villager releases actor back to pool")

	# Move camera far away -> FAR LOD
	cam.position = Vector2(10000, 10000)
	ctrl.update_presentation(0.016, 1.0)
	_assert(ctrl.get_villager_lod("stl_lod", v.villager_id) == RivalPresentationControllerScript.LODTier.FAR, "F4: Distant camera places villager in FAR LOD")

	var cell_while_far: Vector2i = v.cell
	# Change task from Farm A to Farm B while Far
	v.task_state = SettlementVillagerDataScript.TASK_WORKING
	v.active_job_id = "job_farm_b"
	v.work_target_id = "farm_b"
	ctrl.update_presentation(0.016, 1.0)
	_assert(v.cell == cell_while_far, "F5: Far villager is NEVER teleported on task change")
	_assert(loc.path.is_empty(), "F6: Obsolete Far route is cleared on intent change")

	# Return camera -> fresh path from canonical cell
	cam.position = IsoMath.map_to_local(v.cell)
	ctrl.update_presentation(0.016, 1.0)
	_assert(ctrl.get_villager_lod("stl_lod", v.villager_id) == RivalPresentationControllerScript.LODTier.NEAR and ctrl.get_actor_pool().get_active_count() == 1, "F7: Returning camera rehydrates villager at canonical cell without teleporting")

	# Indoor hiding
	v.rest_phase = SettlementVillagerDataScript.REST_RESTING_INSIDE
	ctrl.update_presentation(0.016, 1.0)
	_assert(ctrl.get_actor_pool().get_active_count() == 0, "G2: REST_RESTING_INSIDE hides/releases outdoor actor")

	ctrl.dispose_all()
	ctrl.free()
	pool_node.free()
	cam.free()
	mgr.free()

func _run_category_i_worldview_scene_and_ysort() -> void:
	print("\n[Category I] WorldView Scene Integration & Y-Sort Interleaving")
	var wv := WorldViewScene.instantiate()
	get_root().add_child(wv)

	var sim_mgr = wv.get("settlement_simulation_manager")
	var pres_ctrl = wv.get("rival_presentation_controller")
	_assert(sim_mgr != null and pres_ctrl != null, "I1: WorldView initializes both SettlementSimulationManager and RivalPresentationController")

	var sids: Array[String] = sim_mgr.get_registered_settlement_ids()
	_assert(not sids.is_empty(), "I2: WorldView registers canonical rival settlements")
	var sid0 := sids[0]
	var ctx0 = sim_mgr.get_context(sid0)
	var stl_group: Node2D = wv.call("_get_rival_settlement_group", sid0)
	_assert(stl_group != null and stl_group.y_sort_enabled, "I3: Settlement stl_group exists with y_sort_enabled=true")

	# Add a villager to ctx0, enable debug fog, center camera on settlement, and verify Y-sort placement
	var v = ctx0.create_and_add_villager("SceneTester", SettlementVillagerDataScript.ROLE_IDLE, wv.world_data.settlements[0].anchor_cell + Vector2i(0, 2))
	wv.set("debug_fog_disabled", true)
	wv.camera.focus_on_cell(v.cell)
	wv.camera.force_update_scroll()
	await process_frame
	pres_ctrl.debug_fog_disabled = true
	pres_ctrl.update_presentation(0.016, 1.0)

	var actor: Node2D = pres_ctrl.get_actor_pool().get_active_actor(sid0, v.villager_id)
	var pool_cont: Node2D = wv.get("_rival_villager_pool_container")
	_assert(actor != null and actor.get_parent() == pool_cont, "I4: Hydrated actor is parented in RivalVillagerPool without polluting stl_group child count")

	# Global depth-sorting verification across sibling containers:
	var th_node: Node2D = null
	for c in stl_group.get_children():
		if c.name.begins_with("RivalBld_"):
			th_node = c
			break
	var player_bld: Node2D = wv.buildings_container.get_child(0)
	var player_cit: Node2D = wv.citizens_container.get_child(0)
	var other_sid: String = sids[1]
	var other_stl_group: Node2D = wv.call("_get_rival_settlement_group", other_sid)
	var other_bld: Node2D = null
	for c in other_stl_group.get_children():
		if c.name.begins_with("RivalBld_"):
			other_bld = c
			break

	# A & B: Behind vs In Front of own Rival building
	actor.sync_presentation(th_node.position + Vector2(0, -32.0), false, 0, false, true, 0.0)
	_assert(actor.z_index < th_node.z_index, "I4a: NPC behind own Rival building has smaller z_index (%d < %d)" % [actor.z_index, th_node.z_index])
	actor.sync_presentation(th_node.position + Vector2(0, 32.0), false, 0, false, true, 0.0)
	_assert(actor.z_index > th_node.z_index, "I4b: NPC in front of own Rival building has larger z_index (%d > %d)" % [actor.z_index, th_node.z_index])

	# C & D: Hunter behind vs in front of Player building
	actor.sync_presentation(player_bld.position + Vector2(0, -32.0), false, 0, false, true, 0.0)
	_assert(actor.z_index < player_bld.z_index, "I4c: Hunter behind Player building has smaller z_index (%d < %d)" % [actor.z_index, player_bld.z_index])
	actor.sync_presentation(player_bld.position + Vector2(0, 32.0), false, 0, false, true, 0.0)
	_assert(actor.z_index > player_bld.z_index, "I4d: Hunter in front of Player building has larger z_index (%d > %d)" % [actor.z_index, player_bld.z_index])

	# E: Interleaving with another Rival Settlement building
	actor.sync_presentation(other_bld.position + Vector2(0, -32.0), false, 0, false, true, 0.0)
	_assert(actor.z_index < other_bld.z_index, "I4e1: NPC behind other Rival building (%d < %d)" % [actor.z_index, other_bld.z_index])
	actor.sync_presentation(other_bld.position + Vector2(0, 32.0), false, 0, false, true, 0.0)
	_assert(actor.z_index > other_bld.z_index, "I4e2: NPC in front of other Rival building (%d > %d)" % [actor.z_index, other_bld.z_index])

	# F: Interleaving with Player CitizenController & Terrain/Fog layer bounds
	actor.sync_presentation(player_cit.position + Vector2(0, -24.0), false, 0, false, true, 0.0)
	_assert(actor.z_index < player_cit.z_index, "I4f1: NPC behind Player citizen (%d < %d)" % [actor.z_index, player_cit.z_index])
	actor.sync_presentation(player_cit.position + Vector2(0, 24.0), false, 0, false, true, 0.0)
	_assert(actor.z_index > player_cit.z_index, "I4f2: NPC in front of Player citizen (%d > %d)" % [actor.z_index, player_cit.z_index])
	_assert(actor.z_index > wv.terrain_layer.z_index and actor.z_index < 5, "I4f3: Sortable entity z_index (%d) sits strictly between TerrainLayer (%d) and Fog/HUD (>=5)" % [actor.z_index, wv.terrain_layer.z_index])

	# G: Release resets z_index, rehydration restores it
	pres_ctrl.get_actor_pool().release(sid0, v.villager_id)
	_assert(actor.z_index == 0, "I4g: Released pooled actor resets z_index to 0")

	# Verify repeated apply_settlement_overlays_from_world_data() preserves pool without leaking/duplicating actors
	# (P5-07 seeds initial residents on WorldView._ready(), so flush per-frame hydration budget before comparing.)
	for _i in range(8):
		pres_ctrl.update_presentation(0.016, 1.0)
	var count_before: int = pres_ctrl.get_actor_pool().get_active_count()
	wv.apply_settlement_overlays_from_world_data()
	for _i in range(8):
		pres_ctrl.update_presentation(0.016, 1.0)
	var count_after: int = pres_ctrl.get_actor_pool().get_active_count()
	_assert(count_after == count_before, "I5: Repeated overlay sync creates zero duplicate actors (%d == %d)" % [count_after, count_before])

	wv.queue_free()

func _run_performance_ladder() -> void:
	print("\n[Category J] Performance Safety Ladder (36 / 72 / 144 / 300 / 600 NPCs)")
	var wd := _make_flat_world(128, 128)
	var gnav := GridNavigationScript.new(wd)
	for pop_total in [36, 72, 144, 300, 600]:
		var mgr := SettlementSimulationManagerScript.new()
		wd.settlements.clear()
		var per_stl: int = int(pop_total / 3)
		var anchors := [Vector2i(15, 15), Vector2i(105, 15), Vector2i(105, 105)]
		for i in range(3):
			var sid := "stl_perf_%d" % i
			var stl := _make_settlement(sid, "neutral_tribe", anchors[i])
			wd.settlements.append(stl)
			var ctx := SettlementVillagerContextScript.new(sid, "neutral_tribe")
			ctx.reconcile_buildings(stl)
			for j in range(per_stl):
				ctx.create_and_add_villager("P_%d_%d" % [i, j], SettlementVillagerDataScript.ROLE_IDLE, anchors[i] + Vector2i(j % 16, 2 + int(j / 16)))
			mgr.register_context(ctx)
		mgr.set_world_data(wd)

		var cam := Camera2D.new()
		cam.zoom = Vector2(1.5, 1.5)
		cam.position = IsoMath.map_to_local(anchors[0]) # Camera on settlement 0; 1 & 2 are Far
		var pool_node := Node2D.new()
		var ctrl := RivalPresentationControllerScript.new()
		ctrl.debug_fog_disabled = true
		ctrl.setup(mgr, wd, gnav, cam, null, pool_node)
		ctrl.update_presentation(0.016, 1.0)

		var active_c: int = ctrl.get_actor_pool().get_active_count()
		var hyd_c: int = ctrl.get_last_frame_hydrations()
		var exp_c: int = ctrl.get_path_scheduler().last_frame_expansions
		var adm_c: int = ctrl.get_path_scheduler().last_frame_admitted
		var q_c: int = ctrl.get_path_scheduler().get_queue_size()
		var far_m: Dictionary = ctrl.get_last_far_metrics()

		_assert(
			active_c <= RivalVillagerActorPoolScript.MAX_ACTIVE_ACTORS and hyd_c <= RivalPresentationControllerScript.MAX_HYDRATIONS_PER_FRAME and exp_c <= PathRequestSchedulerScript.MAX_ASTAR_EXPANSIONS_PER_FRAME and adm_c <= PathRequestSchedulerScript.MAX_PATH_REQUESTS_PER_FRAME and q_c <= PathRequestSchedulerScript.MAX_QUEUE_SIZE and int(far_m["far_settlements_skipped"]) == 2,
			"J(%d NPCs): active=%d<=48, hyd=%d<=8, exp=%d<=256, adm=%d<=4, queue=%d<=128, far_skipped=%d" % [pop_total, active_c, hyd_c, exp_c, adm_c, q_c, int(far_m["far_settlements_skipped"])]
		)
		ctrl.dispose_all()
		ctrl.free()
		pool_node.free()
		cam.free()
		mgr.free()

func _init() -> void:
	print("====================================================================")
	print("  TEST SUITE: Phase 6 Rival Villager Actors, Movement & Hybrid LOD")
	print("====================================================================")
	call_deferred("_run_all")

func _run_all() -> void:
	_run_category_a_ownership()
	_run_category_b_and_c_navigation_and_bounds()
	_run_category_d_incremental_astar_and_scheduler()
	_run_category_e_f_g_h_movement_lod_pool_camera_fog()
	await _run_category_i_worldview_scene_and_ysort()
	_run_performance_ladder()

	print("\n--------------------------------------------------------------------")
	print("  Results: %d passed, %d failed" % [_passed, _failed])
	print("====================================================================")
	if _failed == 0:
		print("ALL %d ASSERTIONS PASSED! (Exit Code 0)" % _passed)
		quit(0)
	else:
		print("FAILED WITH %d FAILURES! (Exit Code 1)" % _failed)
		quit(1)
