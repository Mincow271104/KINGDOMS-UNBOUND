extends SceneTree

const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const SettlementDataScript = preload("res://scripts/world/settlement_data.gd")
const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementJobBoardScript = preload("res://scripts/world/settlement_job_board.gd")
const SettlementWorkplaceRegistryScript = preload("res://scripts/world/settlement_workplace_registry.gd")
const SettlementSimulationManagerScript = preload("res://scripts/world/settlement_simulation_manager.gd")
const SettlementNavigationContextScript = preload("res://scripts/world/settlement_navigation_context.gd")
const WorkerPresentationResolverScript = preload("res://scripts/world/worker_presentation_resolver.gd")
const RivalPresentationControllerScript = preload("res://scripts/world/rival_presentation_controller.gd")
const GridNavigationScript = preload("res://scripts/navigation/grid_navigation.gd")
const FogOfWarScript = preload("res://scripts/world/fog_of_war.gd")

var _passed: int = 0
var _failed: int = 0

func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] %s" % label)
	else:
		_failed += 1
		printerr("  [FAIL] %s" % label)

func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		_passed += 1
		print("  [PASS] %s" % label)
	else:
		_failed += 1
		printerr("  [FAIL] %s (got=%s exp=%s)" % [label, str(actual), str(expected)])

func _init() -> void:
	call_deferred("_run")

func _make_world_and_sim() -> Dictionary:
	var wd = WorldGeneratorScript.WorldData.new()
	wd.map_width = 32
	wd.map_height = 32
	wd.seed_value = 3030
	wd.terrain = []
	wd.occupancy = []
	wd.wildlife.clear()
	for x in range(32):
		var tc: Array = []
		var oc: Array = []
		tc.resize(32)
		oc.resize(32)
		tc.fill(1)
		oc.fill(false)
		wd.terrain.append(tc)
		wd.occupancy.append(oc)

	# Block workplace target cells so navigation picks an adjacent walkable cell != focus_cell
	wd.occupancy[10][10] = true # farm
	wd.occupancy[14][10] = true # tree 1
	wd.occupancy[16][10] = true # tree 2
	wd.occupancy[18][10] = true # prey 1
	wd.occupancy[20][12] = true # hauler source
	wd.occupancy[22][12] = true # hauler dest
	wd.occupancy[12][16] = true # guard watchtower

	var stl = SettlementDataScript.new()
	stl.settlement_id = "stl_m3"
	stl.origin_faction_id = "neutral_tribe"
	stl.owner_faction_id = "neutral_tribe"
	stl.anchor_cell = Vector2i(8, 8)
	wd.settlements.append(stl)

	var mgr = SettlementSimulationManagerScript.new()
	mgr.register_settlements_from_world_data(wd)
	var ctx = mgr.get_context("stl_m3")
	var gnav = GridNavigationScript.new(wd)
	var nctx = SettlementNavigationContextScript.new("stl_m3", wd, gnav, stl)
	var resolver = WorkerPresentationResolverScript.new()

	# Register workplaces
	ctx.workplace_registry.register_workplace("wp_farm", "farm", Vector2i(10, 10), Vector2i.ONE, Vector2i(10, 10), "food", 10, 2)
	ctx.workplace_registry.register_workplace("wp_wood", "woodcutter", Vector2i(14, 10), Vector2i.ONE, Vector2i(14, 10), "wood", 10, 2)
	ctx.workplace_registry.register_workplace("wp_hunt", "townhall", Vector2i(8, 8), Vector2i.ONE, Vector2i(8, 8), "raw_meat", 10, 2)
	ctx.workplace_registry.register_workplace("wp_haul", "granary", Vector2i(22, 12), Vector2i.ONE, Vector2i(22, 12), "food", 20, 2, true)
	ctx.workplace_registry.register_workplace("wp_barr", "barracks", Vector2i(12, 16), Vector2i.ONE, Vector2i(12, 16), "", 0, 2)

	# Production sources
	ctx.sim_state.production_sources["wp_wood"] = {
		"type": "woodcutter",
		"resource": "wood",
		"trees": [
			{"cell": Vector2i(14, 10), "remaining_milli": 1000},
			{"cell": Vector2i(16, 10), "remaining_milli": 1000},
		]
	}
	wd.wildlife.append({
		"animal_id": "deer_1",
		"species_id": "deer",
		"cell": Vector2i(18, 10),
		"is_available": true,
		"reserved_by": "",
		"recovery_hours_left": 0.0,
	})
	wd.wildlife_by_id["deer_1"] = wd.wildlife[0]
	ctx.sim_state.production_sources["wp_hunt"] = {
		"type": "hunter_source",
		"current_prey_id": "deer_1",
		"allocated_animals": ["deer_1"],
	}

	return {"wd": wd, "mgr": mgr, "ctx": ctx, "nctx": nctx, "gnav": gnav, "resolver": resolver}

func _run() -> void:
	print("\n====================================================================")
	print("  TEST SUITE: M3-0 Shared Worker Presentation State & Focus-Cell")
	print("====================================================================")

	var env := _make_world_and_sim()
	var wd = env["wd"]
	var mgr = env["mgr"]
	var ctx = env["ctx"]
	var nctx = env["nctx"]
	var resolver = env["resolver"]

	# 1. Farmer: approaching vs arrived WORKING_AT_TARGET vs paused WAITING vs invalid workplace
	var v_farm = SettlementVillagerDataScript.new(ctx.allocate_villager_id(), "stl_m3", "neutral_tribe", "Farmer", SettlementVillagerDataScript.ROLE_FARMER, Vector2i(9, 10))
	ctx.add_villager(v_farm)
	var j_farm = ctx.job_board.create_job_record(SettlementVillagerDataScript.ROLE_FARMER, "wp_farm", Vector2i(10, 10))
	j_farm.assigned_villager_id = v_farm.villager_id
	v_farm.active_job_id = j_farm.job_id
	v_farm.task_state = SettlementVillagerDataScript.TASK_WORKING

	nctx.sync_intent(ctx, v_farm)
	var loc_farm = nctx.get_or_create_locomotion(v_farm)
	_assert_eq(loc_farm.destination_cell, Vector2i(9, 10), "M3-0 Farmer: navigation dest is adjacent cell (9,10)")
	_assert_eq(loc_farm.focus_cell, Vector2i(10, 10), "M3-0 Farmer: focus_cell is farm target (10,10) != dest_cell")
	var res_farm = resolver.resolve(ctx, v_farm, loc_farm, wd, null)
	_assert_eq(res_farm.presentation_state, WorkerPresentationResolverScript.State.WORKING_AT_TARGET, "M3-0 Farmer: arrived active farm -> WORKING_AT_TARGET")

	ctx.workplace_registry.get_workplace("wp_farm").is_paused = true
	res_farm = resolver.resolve(ctx, v_farm, loc_farm, wd, null)
	_assert_eq(res_farm.presentation_state, WorkerPresentationResolverScript.State.WAITING, "M3-0 Farmer: paused farm -> WAITING")
	ctx.workplace_registry.get_workplace("wp_farm").is_paused = false

	# 2. Woodcutter: active tree focus & depleted tree invalidation
	var v_wood = SettlementVillagerDataScript.new(ctx.allocate_villager_id(), "stl_m3", "neutral_tribe", "Woodcutter", SettlementVillagerDataScript.ROLE_WOODCUTTER, Vector2i(13, 10))
	ctx.add_villager(v_wood)
	var j_wood = ctx.job_board.create_job_record(SettlementVillagerDataScript.ROLE_WOODCUTTER, "wp_wood", Vector2i(14, 10))
	j_wood.assigned_villager_id = v_wood.villager_id
	v_wood.active_job_id = j_wood.job_id
	v_wood.task_state = SettlementVillagerDataScript.TASK_WORKING

	nctx.sync_intent(ctx, v_wood)
	var loc_wood = nctx.get_or_create_locomotion(v_wood)
	_assert_eq(loc_wood.focus_cell, Vector2i(14, 10), "M3-0 Woodcutter: focus_cell tracks first non-depleted tree (14,10)")
	ctx.sim_state.production_sources["wp_wood"]["trees"][0]["remaining_milli"] = 0
	nctx.sync_intent(ctx, v_wood)
	_assert_eq(loc_wood.focus_cell, Vector2i(16, 10), "M3-0 Woodcutter: depleting tree 1 shifts focus_cell to tree 2 (16,10)")
	ctx.sim_state.production_sources["wp_wood"]["trees"][1]["remaining_milli"] = 0
	nctx.sync_intent(ctx, v_wood)
	var res_wood = resolver.resolve(ctx, v_wood, loc_wood, wd, null)
	_assert_true(not loc_wood.has_valid_focus and res_wood.presentation_state == WorkerPresentationResolverScript.State.INVALID_TARGET, "M3-0 Woodcutter: all trees depleted -> INVALID_TARGET & focus cleared")

	# 3. Hunter: prey focus, prey movement, missing prey
	var v_hunt = SettlementVillagerDataScript.new(ctx.allocate_villager_id(), "stl_m3", "neutral_tribe", "Hunter", SettlementVillagerDataScript.ROLE_HUNTER, Vector2i(17, 10))
	ctx.add_villager(v_hunt)
	var j_hunt = ctx.job_board.create_job_record(SettlementVillagerDataScript.ROLE_HUNTER, "wp_hunt", Vector2i(8, 8))
	j_hunt.assigned_villager_id = v_hunt.villager_id
	v_hunt.active_job_id = j_hunt.job_id
	v_hunt.task_state = SettlementVillagerDataScript.TASK_WORKING

	nctx.sync_intent(ctx, v_hunt)
	var loc_hunt = nctx.get_or_create_locomotion(v_hunt)
	_assert_eq(loc_hunt.focus_cell, Vector2i(18, 10), "M3-0 Hunter: focus_cell matches prey cell (18,10)")
	wd.wildlife[0]["cell"] = Vector2i(19, 10)
	nctx.sync_intent(ctx, v_hunt)
	_assert_eq(loc_hunt.focus_cell, Vector2i(19, 10), "M3-0 Hunter: prey movement updates focus_cell to (19,10)")
	wd.wildlife[0]["is_available"] = false
	nctx.sync_intent(ctx, v_hunt)
	var res_hunt = resolver.resolve(ctx, v_hunt, loc_hunt, wd, null)
	_assert_eq(res_hunt.presentation_state, WorkerPresentationResolverScript.State.INVALID_TARGET, "M3-0 Hunter: unavailable prey -> INVALID_TARGET")

	# 4. Hauler: empty vs loaded from actual cargo
	var v_haul = SettlementVillagerDataScript.new(ctx.allocate_villager_id(), "stl_m3", "neutral_tribe", "Hauler", SettlementVillagerDataScript.ROLE_HAULER, Vector2i(19, 12))
	ctx.add_villager(v_haul)
	var j_haul = ctx.job_board.create_job_record(SettlementVillagerDataScript.ROLE_HAULER, "wp_haul", Vector2i(20, 12))
	j_haul.source_cell = Vector2i(20, 12)
	j_haul.dest_cell = Vector2i(22, 12)
	j_haul.assigned_villager_id = v_haul.villager_id
	v_haul.active_job_id = j_haul.job_id
	v_haul.task_state = SettlementVillagerDataScript.TASK_HAULING

	nctx.sync_intent(ctx, v_haul)
	var loc_haul = nctx.get_or_create_locomotion(v_haul)
	var res_haul_empty = resolver.resolve(ctx, v_haul, loc_haul, wd, null)
	_assert_true(res_haul_empty.presentation_state == WorkerPresentationResolverScript.State.TRANSPORT_EMPTY and not res_haul_empty.transport_loaded and res_haul_empty.focus_cell == Vector2i(20, 12), "M3-0 Hauler: empty cargo -> TRANSPORT_EMPTY & source_cell focus")

	v_haul.set_cargo("wood", 4, "wp_wood", Vector2i(22, 12))
	nctx.sync_intent(ctx, v_haul)
	var res_haul_full = resolver.resolve(ctx, v_haul, loc_haul, wd, null)
	_assert_true(res_haul_full.presentation_state == WorkerPresentationResolverScript.State.TRANSPORT_LOADED and res_haul_full.transport_loaded and res_haul_full.cargo_resource == "wood" and res_haul_full.focus_cell == Vector2i(22, 12), "M3-0 Hauler: positive cargo -> TRANSPORT_LOADED, cargo_resource='wood', dest_cell focus")

	# 5. Guard: patrol target vs Barracks fallback + facing preservation when at access cell
	var v_guard = SettlementVillagerDataScript.new(ctx.allocate_villager_id(), "stl_m3", "neutral_tribe", "Guard", SettlementVillagerDataScript.ROLE_GUARD, Vector2i(11, 16))
	ctx.add_villager(v_guard)
	var j_guard = ctx.job_board.create_job_record(SettlementVillagerDataScript.ROLE_GUARD, "wp_barr", Vector2i(12, 16))
	j_guard.assigned_villager_id = v_guard.villager_id
	v_guard.active_job_id = j_guard.job_id
	v_guard.task_state = SettlementVillagerDataScript.TASK_GUARDING

	nctx.sync_intent(ctx, v_guard)
	var loc_guard = nctx.get_or_create_locomotion(v_guard)
	var res_guard = resolver.resolve(ctx, v_guard, loc_guard, wd, null)
	_assert_true(res_guard.presentation_state == WorkerPresentationResolverScript.State.GUARDING and res_guard.focus_cell == Vector2i(12, 16), "M3-0 Guard: Barracks fallback -> GUARDING & focus (12,16)")

	# 6. Returning home & Resting inside
	v_farm.task_state = SettlementVillagerDataScript.TASK_RESTING
	v_farm.rest_phase = SettlementVillagerDataScript.REST_RETURNING_HOME
	var res_ret = resolver.resolve(ctx, v_farm, loc_farm, wd, null)
	_assert_eq(res_ret.presentation_state, WorkerPresentationResolverScript.State.RETURNING_HOME, "M3-0 Returning home -> RETURNING_HOME")
	v_farm.rest_phase = SettlementVillagerDataScript.REST_RESTING_INSIDE
	var res_rest = resolver.resolve(ctx, v_farm, loc_farm, wd, null)
	_assert_eq(res_rest.presentation_state, WorkerPresentationResolverScript.State.RESTING, "M3-0 Resting inside -> RESTING")

	# 7. Read-only integrity check: snapshot before & after 20 resolver calls
	v_farm.task_state = SettlementVillagerDataScript.TASK_WORKING
	v_farm.rest_phase = SettlementVillagerDataScript.REST_NONE
	var snap_before := v_farm.to_dict()
	var haul_before := v_haul.to_dict()
	for _i in range(20):
		resolver.resolve(ctx, v_farm, loc_farm, wd, null)
		resolver.resolve(ctx, v_haul, loc_haul, wd, null)
	_assert_eq(v_farm.to_dict(), snap_before, "M3-0 Read-only: Farmer canonical dict 100% unchanged")
	_assert_eq(v_haul.to_dict(), haul_before, "M3-0 Read-only: Hauler canonical dict 100% unchanged")

	# 8. Active-actor integration & fog safety (no hidden actor hydration, <= 48 actors)
	var cam := Camera2D.new()
	cam.position = IsoMath.map_to_local(Vector2i(12, 12))
	cam.zoom = Vector2(1.0, 1.0)
	root.add_child(cam)
	var pool_cont := Node2D.new()
	root.add_child(pool_cont)
	var fog := FogOfWarScript.new(32, 32)
	var pres := RivalPresentationControllerScript.new()
	pres.setup(mgr, wd, env["gnav"], cam, fog, pool_cont)
	pres.debug_fog_disabled = false
	pres.update_presentation(0.016, 1.0)
	_assert_eq(pres.get_actor_pool().get_active_count(), 0, "M3-0 Fog: Unexplored cells keep active_actors == 0")
	pres.debug_fog_disabled = true
	pres.update_presentation(0.016, 1.0)
	pres.update_presentation(0.016, 1.0)
	var act_farm = pres.get_actor_pool().get_active_actor("stl_m3", v_farm.villager_id)
	_assert_true(act_farm != null and act_farm.worker_presentation_state == WorkerPresentationResolverScript.State.WORKING_AT_TARGET and act_farm.worker_focus_cell == Vector2i(10, 10), "M3-0 Active Actor: RivalVillagerActor receives derived WORKING_AT_TARGET & focus_cell")
	_assert_true(pres.get_actor_pool().get_active_count() <= 48, "M3-0 Actor cap <= 48 (%d)" % pres.get_actor_pool().get_active_count())

	# 9. M3-0 Follow-up: Guard active patrol target & rotation (read-only)
	ctx._set_derived_building_state(
		0, [], [], [], [], [], [],
		["wt_1", "wt_2"],
		[
			{"building_id": "wt_1", "building_type": "watchtower", "access_cell": Vector2i(6, 16)},
			{"building_id": "wt_2", "building_type": "watchtower", "access_cell": Vector2i(14, 16)},
		],
		[
			{
				"barracks_workplace_id": "wp_barr",
				"barracks_building_id": "wp_barr",
				"barracks_access_cell": Vector2i(12, 16),
				"patrol_targets": [
					{"building_id": "wt_1", "building_type": "watchtower", "access_cell": Vector2i(6, 16)},
					{"building_id": "wt_2", "building_type": "watchtower", "access_cell": Vector2i(14, 16)},
				],
			}
		]
	)
	wd.occupancy[6][16] = true
	v_guard.cell = Vector2i(7, 16)
	v_guard.work_target_id = "wt_1"
	nctx.sync_intent(ctx, v_guard)
	var guard_snap := v_guard.to_dict()
	var res_wt1 = resolver.resolve(ctx, v_guard, loc_guard, wd, null)
	_assert_true(res_wt1.presentation_state == WorkerPresentationResolverScript.State.GUARDING and res_wt1.focus_cell == Vector2i(6, 16), "M3-0 Follow-up Guard: active patrol wt_1 -> focus (6,16)")
	v_guard.work_target_id = "wt_2"
	nctx.sync_intent(ctx, v_guard)
	var res_wt2 = resolver.resolve(ctx, v_guard, loc_guard, wd, null)
	_assert_eq(res_wt2.focus_cell, Vector2i(14, 16), "M3-0 Follow-up Guard: patrol rotation wt_2 -> focus (14,16)")
	v_guard.work_target_id = "wt_1"
	_assert_eq(v_guard.to_dict(), guard_snap, "M3-0 Follow-up Guard: resolver is strictly read-only")

	# 10. M3-1 Farmer & Woodcutter target-facing, work/wait cadence, depletion, and reacquire
	# Farmer approaching vs arrived vs waiting
	v_farm.cell = Vector2i(7, 10)
	nctx.sync_intent(ctx, v_farm)
	loc_farm.is_moving = true
	loc_farm.status = SettlementNavigationContextScript.MoveStatus.MOVING
	var res_farm_app = resolver.resolve(ctx, v_farm, loc_farm, wd, null)
	_assert_eq(res_farm_app.presentation_state, WorkerPresentationResolverScript.State.APPROACHING, "M3-1 Farmer: moving toward farm -> APPROACHING")

	# Place farmer to the East of farm (11,10) so facing farm (10,10) requires flip_h = true (West/NW)
	v_farm.cell = Vector2i(11, 10)
	loc_farm.is_moving = false
	loc_farm.status = SettlementNavigationContextScript.MoveStatus.ARRIVED
	loc_farm.flip_h = false
	nctx.sync_intent(ctx, v_farm)
	# Ensure actor is hydrated and synced with anim_delta > 0
	for _f in range(3):
		pres.update_presentation(0.05, 1.0)
	act_farm = pres.get_actor_pool().get_active_actor("stl_m3", v_farm.villager_id)
	_assert_true(act_farm != null and act_farm.sprite.flip_h == true and act_farm.work_anim_time > 0.0, "M3-1 Farmer: arrived East of farm faces West toward (10,10) & advances work cadence")

	# Paused / buffer-full farm stops work cadence
	var wp_farm_ref = ctx.workplace_registry.get_workplace("wp_farm")
	wp_farm_ref.is_paused = true
	wp_farm_ref.pause_reason = "buffer_full"
	pres.update_presentation(0.05, 1.0)
	_assert_true(act_farm.worker_presentation_state == WorkerPresentationResolverScript.State.WAITING and act_farm.work_anim_time == 0.0, "M3-1 Farmer: buffer_full/paused farm -> WAITING & work_anim_time == 0.0")
	wp_farm_ref.is_paused = false
	wp_farm_ref.pause_reason = ""

	# Woodcutter faces active tree, switches facing on depletion, and stops when all trees depleted
	ctx.sim_state.production_sources["wp_wood"]["trees"][0]["remaining_milli"] = 1000
	ctx.sim_state.production_sources["wp_wood"]["trees"][1]["remaining_milli"] = 1000
	v_wood.cell = Vector2i(15, 10) # Between tree 1 (14,10) to West and tree 2 (16,10) to East!
	loc_wood.is_moving = false
	loc_wood.status = SettlementNavigationContextScript.MoveStatus.ARRIVED
	pres.update_presentation(0.05, 1.0)
	pres.update_presentation(0.05, 1.0)
	var act_wood = pres.get_actor_pool().get_active_actor("stl_m3", v_wood.villager_id)
	_assert_true(act_wood != null and act_wood.sprite.flip_h == true and act_wood.worker_focus_cell == Vector2i(14, 10), "M3-1 Woodcutter: at (15,10) faces West tree 1 (14,10)")

	# Deplete tree 1 -> shifts focus to East tree 2 (16,10) and flips to East (flip_h == false)
	ctx.sim_state.production_sources["wp_wood"]["trees"][0]["remaining_milli"] = 0
	pres.update_presentation(0.05, 1.0)
	_assert_true(act_wood.worker_focus_cell == Vector2i(16, 10) and act_wood.sprite.flip_h == false and act_wood.work_anim_time > 0.0, "M3-1 Woodcutter: tree 1 depleted -> faces East tree 2 (16,10)")

	# Deplete tree 2 -> INVALID_TARGET & work cadence stopped
	ctx.sim_state.production_sources["wp_wood"]["trees"][1]["remaining_milli"] = 0
	pres.update_presentation(0.05, 1.0)
	_assert_true(act_wood.worker_presentation_state == WorkerPresentationResolverScript.State.INVALID_TARGET and act_wood.work_anim_time == 0.0, "M3-1 Woodcutter: all trees depleted -> INVALID_TARGET & work_anim_time == 0.0")

	# Actor release/reacquire restores target-facing on first frame
	pres.get_actor_pool().release("stl_m3", v_farm.villager_id)
	pres.update_presentation(0.05, 1.0)
	var act_farm_re = pres.get_actor_pool().get_active_actor("stl_m3", v_farm.villager_id)
	_assert_true(act_farm_re != null and act_farm_re.sprite.flip_h == true and act_farm_re.worker_focus_cell == Vector2i(10, 10), "M3-1 Actor reacquire: Farmer restores target-facing toward (10,10) on hydration")

	# Zero F1/W1 canonical mutation from presentation updates
	var f_hours_before: float = v_farm.work_hours_done
	var w_hours_before: float = v_wood.work_hours_done
	var f_buf_before: int = wp_farm_ref.buffer_amount
	var w_buf_before: int = ctx.workplace_registry.get_workplace("wp_wood").buffer_amount
	for _p in range(10):
		pres.update_presentation(0.05, 1.0)
	_assert_true(v_farm.work_hours_done == f_hours_before and v_wood.work_hours_done == w_hours_before and wp_farm_ref.buffer_amount == f_buf_before and ctx.workplace_registry.get_workplace("wp_wood").buffer_amount == w_buf_before, "M3-1 Isolation: presentation updates produce zero F1/W1 canonical mutations")

	# 11. M3-1 Audit: Woodcutter WAITING states (paused, buffer_full/headroom, production_blocked) & resume
	ctx.sim_state.production_sources["wp_wood"]["trees"][0]["remaining_milli"] = 1000
	var wp_wood_ref = ctx.workplace_registry.get_workplace("wp_wood")
	wp_wood_ref.is_paused = false
	wp_wood_ref.buffer_amount = 0
	ctx.sim_state.production_blocked.erase("wp_wood")
	pres.update_presentation(0.05, 1.0)
	_assert_true(act_wood.worker_presentation_state == WorkerPresentationResolverScript.State.WORKING_AT_TARGET and act_wood.work_anim_time > 0.0, "M3-1 Audit Woodcutter: valid tree + active wp + available buffer + arrived -> WORKING_AT_TARGET")

	# Paused workplace -> WAITING & work_anim_time == 0.0
	wp_wood_ref.is_paused = true
	pres.update_presentation(0.05, 1.0)
	_assert_true(act_wood.worker_presentation_state == WorkerPresentationResolverScript.State.WAITING and act_wood.work_anim_time == 0.0, "M3-1 Audit Woodcutter: paused workplace -> WAITING & work_anim_time == 0.0")
	wp_wood_ref.is_paused = false

	# Full buffer (headroom < TREE_WOOD_UNITS) even before wp.is_paused is set -> WAITING & work_anim_time == 0.0
	wp_wood_ref.buffer_amount = wp_wood_ref.buffer_capacity
	pres.update_presentation(0.05, 1.0)
	_assert_true(act_wood.worker_presentation_state == WorkerPresentationResolverScript.State.WAITING and act_wood.work_anim_time == 0.0, "M3-1 Audit Woodcutter: full buffer -> WAITING & work_anim_time == 0.0")

	# Resume after buffer availability -> returns to WORKING_AT_TARGET
	wp_wood_ref.buffer_amount = 0
	pres.update_presentation(0.05, 1.0)
	_assert_true(act_wood.worker_presentation_state == WorkerPresentationResolverScript.State.WORKING_AT_TARGET and act_wood.work_anim_time > 0.0, "M3-1 Audit Woodcutter: buffer headroom restored -> WORKING_AT_TARGET")

	# Production blocked -> WAITING & work_anim_time == 0.0
	ctx.sim_state.production_blocked["wp_wood"] = "source_depleted"
	pres.update_presentation(0.05, 1.0)
	_assert_true(act_wood.worker_presentation_state == WorkerPresentationResolverScript.State.WAITING and act_wood.work_anim_time == 0.0, "M3-1 Audit Woodcutter: production_blocked -> WAITING & work_anim_time == 0.0")
	ctx.sim_state.production_blocked.erase("wp_wood")

	# Snapshot read-only integrity across Woodcutter presentation updates
	var w_villager_snap := v_wood.to_dict()
	var w_tree_milli_before: int = int(ctx.sim_state.production_sources["wp_wood"]["trees"][0]["remaining_milli"])
	var w_job_snap: Dictionary = j_wood.to_dict()
	for _a in range(10):
		pres.update_presentation(0.05, 1.0)
	_assert_true(v_wood.to_dict() == w_villager_snap and int(ctx.sim_state.production_sources["wp_wood"]["trees"][0]["remaining_milli"]) == w_tree_milli_before and j_wood.to_dict() == w_job_snap, "M3-1 Audit Read-only: Woodcutter villager, tree remaining_milli, and job record 100% unchanged")

	# 12. M3-1 Edge-Case Closure: eff_cap == 0 blocks both Woodcutter and Farmer -> WAITING & work_anim_time == 0.0
	var prev_wood_cap: int = wp_wood_ref.buffer_capacity
	wp_wood_ref.buffer_capacity = 0
	wp_wood_ref.buffer_amount = 0
	wp_wood_ref.is_paused = false
	pres.update_presentation(0.05, 1.0)
	_assert_true(act_wood.worker_presentation_state == WorkerPresentationResolverScript.State.WAITING and act_wood.work_anim_time == 0.0, "M3-1 Edge-Case Woodcutter: eff_cap == 0 -> WAITING & work_anim_time == 0.0")
	wp_wood_ref.buffer_capacity = prev_wood_cap
	pres.update_presentation(0.05, 1.0)
	_assert_true(act_wood.worker_presentation_state == WorkerPresentationResolverScript.State.WORKING_AT_TARGET and act_wood.work_anim_time > 0.0, "M3-1 Edge-Case Woodcutter: positive eff_cap restored -> WORKING_AT_TARGET")

	var prev_farm_cap: int = wp_farm_ref.buffer_capacity
	wp_farm_ref.buffer_capacity = 0
	wp_farm_ref.buffer_amount = 0
	wp_farm_ref.is_paused = false
	pres.update_presentation(0.05, 1.0)
	var act_farm_ec = pres.get_actor_pool().get_active_actor("stl_m3", v_farm.villager_id)
	_assert_true(act_farm_ec != null and act_farm_ec.worker_presentation_state == WorkerPresentationResolverScript.State.WAITING and act_farm_ec.work_anim_time == 0.0, "M3-1 Edge-Case Farmer: eff_cap == 0 -> WAITING & work_anim_time == 0.0")
	wp_farm_ref.buffer_capacity = prev_farm_cap
	pres.update_presentation(0.05, 1.0)
	_assert_true(act_farm_ec.worker_presentation_state == WorkerPresentationResolverScript.State.WORKING_AT_TARGET and act_farm_ec.work_anim_time > 0.0, "M3-1 Edge-Case Farmer: positive eff_cap restored -> WORKING_AT_TARGET")

	# 13. M3-2 Hunter Presentation (approaching, arrived facing, dynamic prey move, unavailable/blocked, read-only)
	wd.wildlife[0]["is_available"] = true
	wd.wildlife[0]["reserved_by"] = ""
	wd.wildlife[0]["cell"] = Vector2i(18, 10)
	v_hunt.cell = Vector2i(19, 10)
	v_hunt.active_job_id = j_hunt.job_id
	v_hunt.task_state = SettlementVillagerDataScript.TASK_WORKING
	var pres_nctx = pres.get_navigation_context("stl_m3")
	pres_nctx.sync_intent(ctx, v_hunt)
	var p_loc_hunt = pres_nctx.get_or_create_locomotion(v_hunt)
	p_loc_hunt.is_moving = true
	p_loc_hunt.status = SettlementNavigationContextScript.MoveStatus.MOVING
	p_loc_hunt.flip_h = false
	var res_h_app = resolver.resolve(ctx, v_hunt, p_loc_hunt, wd, null)
	_assert_true(res_h_app.presentation_state == WorkerPresentationResolverScript.State.APPROACHING and res_h_app.flip_h == false, "M3-2 Hunter: approaching prey -> APPROACHING & preserves path facing")

	# Arrived at (19,10) with prey West at (18,10) -> WORKING_AT_TARGET & faces West (flip_h == true)
	p_loc_hunt.is_moving = false
	p_loc_hunt.status = SettlementNavigationContextScript.MoveStatus.ARRIVED
	p_loc_hunt.flip_h = false
	pres.update_presentation(0.05, 1.0)
	var act_hunt = pres.get_actor_pool().get_active_actor("stl_m3", v_hunt.villager_id)
	_assert_true(act_hunt != null and act_hunt.worker_presentation_state == WorkerPresentationResolverScript.State.WORKING_AT_TARGET and act_hunt.worker_focus_cell == Vector2i(18, 10) and act_hunt.sprite.flip_h == true, "M3-2 Hunter: arrived East of prey -> WORKING_AT_TARGET & faces West prey (18,10)")

	# Prey moves East to (20,10) -> focus & facing update to East (flip_h == false)
	wd.occupancy[20][10] = true
	wd.wildlife[0]["cell"] = Vector2i(20, 10)
	pres.update_presentation(0.05, 1.0)
	_assert_true(act_hunt.worker_focus_cell == Vector2i(20, 10) and act_hunt.sprite.flip_h == false, "M3-2 Hunter: prey moves East -> focus & facing update to (20,10)")

	# Production blocked (e.g. storage_full) -> WAITING
	ctx.sim_state.production_blocked["wp_hunt"] = "storage_full"
	pres.update_presentation(0.05, 1.0)
	_assert_eq(act_hunt.worker_presentation_state, WorkerPresentationResolverScript.State.WAITING, "M3-2 Hunter: production_blocked -> WAITING")
	ctx.sim_state.production_blocked.erase("wp_hunt")

	# Prey unavailable -> INVALID_TARGET & no stale focus
	wd.wildlife[0]["is_available"] = false
	pres.update_presentation(0.05, 1.0)
	_assert_true(act_hunt.worker_presentation_state == WorkerPresentationResolverScript.State.INVALID_TARGET and not act_hunt.worker_has_valid_focus, "M3-2 Hunter: unavailable prey -> INVALID_TARGET & focus cleared")

	# Read-only integrity across 10 presentation updates
	wd.wildlife[0]["is_available"] = true
	pres.update_presentation(0.05, 1.0)
	var h_vill_snap: Dictionary = v_hunt.to_dict()
	var h_prey_snap: Dictionary = wd.wildlife[0].duplicate(true)
	var h_meat_before: int = ctx.economy.get_resource("raw_meat")
	var h_job_snap: Dictionary = j_hunt.to_dict()
	for _hp in range(10):
		pres.update_presentation(0.05, 1.0)
	_assert_eq(v_hunt.to_dict(), h_vill_snap, "M3-2 Hunter Read-only: villager 100% unchanged")
	_assert_eq(wd.wildlife[0], h_prey_snap, "M3-2 Hunter Read-only: prey 100% unchanged")
	_assert_eq(ctx.economy.get_resource("raw_meat"), h_meat_before, "M3-2 Hunter Read-only: raw_meat 100% unchanged")
	_assert_eq(j_hunt.to_dict(), h_job_snap, "M3-2 Hunter Read-only: job 100% unchanged")

	# 14. M3-2 Hauler Cargo Presentation (real canonical pickup/deposit, empty/loaded transitions, facing, invalid targets)
	v_haul.clear_cargo()
	v_haul.cell = Vector2i(21, 12) # Between source (20,12) West and dest (22,12) East
	v_haul.active_job_id = j_haul.job_id
	v_haul.task_state = SettlementVillagerDataScript.TASK_HAULING
	pres_nctx.sync_intent(ctx, v_haul)
	var p_loc_haul = pres_nctx.get_or_create_locomotion(v_haul)
	p_loc_haul.is_moving = false
	p_loc_haul.status = SettlementNavigationContextScript.MoveStatus.ARRIVED
	pres.update_presentation(0.05, 1.0)
	var act_haul = pres.get_actor_pool().get_active_actor("stl_m3", v_haul.villager_id)
	_assert_true(act_haul != null and act_haul.worker_presentation_state == WorkerPresentationResolverScript.State.TRANSPORT_EMPTY and not act_haul.worker_transport_loaded and act_haul.worker_focus_cell == Vector2i(20, 12) and act_haul.sprite.flip_h == true, "M3-2 Hauler: empty arrived at (21,12) -> TRANSPORT_EMPTY & faces West source (20,12)")

	# Real canonical pickup via SettlementSimulationManager._attempt_hauler_pickup
	ctx._set_derived_building_state(
		0, [], [], [], [],
		[{"source_workplace_id": "wp_wood", "dest_workplace_id": "wp_haul", "cargo_resource": "wood"}],
		[], [], [], []
	)
	wp_wood_ref.buffer_amount = 4
	mgr._attempt_hauler_pickup(ctx, v_haul, j_haul, 10)
	pres.update_presentation(0.05, 1.0)
	_assert_true(v_haul.get_carrying_amount() == 4 and act_haul.worker_presentation_state == WorkerPresentationResolverScript.State.TRANSPORT_LOADED and act_haul.worker_transport_loaded and act_haul.worker_cargo_resource == "wood" and act_haul.worker_focus_cell == Vector2i(22, 12) and act_haul.sprite.flip_h == false, "M3-2 Hauler: real pickup -> TRANSPORT_LOADED, 'wood', faces East dest (22,12)")

	# Failed/blocked delivery (wood headroom == 0) preserves loaded cargo
	var wood_cap: int = ctx.economy.get_capacity("wood")
	ctx.economy.credit_resource("wood", wood_cap - ctx.economy.get_resource("wood"), "test_fill", "test", 11)
	mgr._attempt_hauler_deposit(ctx, v_haul, 12)
	pres.update_presentation(0.05, 1.0)
	_assert_true(v_haul.get_carrying_amount() == 4 and act_haul.worker_presentation_state == WorkerPresentationResolverScript.State.TRANSPORT_LOADED and act_haul.worker_transport_loaded, "M3-2 Hauler: blocked delivery -> cargo preserved & remains TRANSPORT_LOADED")

	# Successful delivery after headroom restored -> clears cargo & returns to TRANSPORT_EMPTY
	ctx.economy.debit_resource("wood", 4, "test_drain", "test", 13)
	mgr._attempt_hauler_deposit(ctx, v_haul, 14)
	pres.update_presentation(0.05, 1.0)
	_assert_true(v_haul.get_carrying_amount() == 0 and act_haul.worker_presentation_state == WorkerPresentationResolverScript.State.TRANSPORT_EMPTY and not act_haul.worker_transport_loaded and act_haul.worker_cargo_resource == "", "M3-2 Hauler: successful delivery -> TRANSPORT_EMPTY & cargo cleared")

	# Read-only integrity across 10 presentation updates
	var hl_vill_snap: Dictionary = v_haul.to_dict()
	var hl_src_buf: int = wp_wood_ref.buffer_amount
	var hl_econ_wood: int = ctx.economy.get_resource("wood")
	var hl_job_snap: Dictionary = j_haul.to_dict()
	for _hlp in range(10):
		pres.update_presentation(0.05, 1.0)
	_assert_true(v_haul.to_dict() == hl_vill_snap and wp_wood_ref.buffer_amount == hl_src_buf and ctx.economy.get_resource("wood") == hl_econ_wood and j_haul.to_dict() == hl_job_snap, "M3-2 Hauler Read-only: villager, buffers, economy, and job 100% unchanged")

	# Invalid source/dest -> INVALID_TARGET & no stale focus
	j_haul.source_cell = Vector2i(-1, -1)
	j_haul.target_cell = Vector2i(-1, -1)
	pres_nctx.sync_intent(ctx, v_haul)
	var res_hl_inv = resolver.resolve(ctx, v_haul, p_loc_haul, wd, null)
	_assert_true(res_hl_inv.presentation_state == WorkerPresentationResolverScript.State.INVALID_TARGET and not res_hl_inv.has_valid_focus, "M3-2 Hauler: invalid source/target -> INVALID_TARGET & focus cleared")

	# 15. M3-2 Acceptance Audit: Prey reservation ownership, loaded+invalid dest, and cargo resource change
	# 15a. Prey reserved by THIS Hunter (is_available=false, reserved_by=v_hunt.villager_id) -> valid WORKING_AT_TARGET
	wd.wildlife[0]["is_available"] = false
	wd.wildlife[0]["reserved_by"] = v_hunt.villager_id
	wd.wildlife[0]["recovery_hours_left"] = 0.0
	v_hunt.cell = Vector2i(19, 10)
	pres_nctx.sync_intent(ctx, v_hunt)
	p_loc_hunt.is_moving = false
	p_loc_hunt.status = SettlementNavigationContextScript.MoveStatus.ARRIVED
	var res_h_own = resolver.resolve(ctx, v_hunt, p_loc_hunt, wd, null)
	_assert_true(res_h_own.presentation_state == WorkerPresentationResolverScript.State.WORKING_AT_TARGET and res_h_own.focus_cell == Vector2i(20, 10), "M3-2 Audit Hunter: prey reserved by self -> WORKING_AT_TARGET & focus (20,10)")

	# 15b. Prey reserved by ANOTHER Hunter (even if is_available=true) -> INVALID_TARGET & focus cleared
	wd.wildlife[0]["is_available"] = true
	wd.wildlife[0]["reserved_by"] = "npc_stl_m3_other_hunter"
	pres_nctx.sync_intent(ctx, v_hunt)
	var res_h_other = resolver.resolve(ctx, v_hunt, p_loc_hunt, wd, null)
	_assert_true(res_h_other.presentation_state == WorkerPresentationResolverScript.State.INVALID_TARGET and not res_h_other.has_valid_focus, "M3-2 Audit Hunter: prey reserved by other hunter -> INVALID_TARGET & no stale focus")

	# 15b2. Prey reserved with reservation_type="player" -> INVALID_TARGET & focus cleared
	wd.wildlife[0]["is_available"] = false
	wd.wildlife[0]["reserved_by"] = v_hunt.villager_id
	wd.wildlife[0]["reservation_type"] = "player"
	pres_nctx.sync_intent(ctx, v_hunt)
	var res_h_player = resolver.resolve(ctx, v_hunt, p_loc_hunt, wd, null)
	_assert_true(res_h_player.presentation_state == WorkerPresentationResolverScript.State.INVALID_TARGET and not res_h_player.has_valid_focus, "M3 Final Audit Hunter: reservation_type='player' -> INVALID_TARGET & focus cleared")
	wd.wildlife[0]["reservation_type"] = ""

	# 15c. Prey in recovery (recovery_hours_left > 0) -> INVALID_TARGET
	wd.wildlife[0]["reserved_by"] = ""
	wd.wildlife[0]["recovery_hours_left"] = 24.0
	pres_nctx.sync_intent(ctx, v_hunt)
	var res_h_rec = resolver.resolve(ctx, v_hunt, p_loc_hunt, wd, null)
	_assert_true(res_h_rec.presentation_state == WorkerPresentationResolverScript.State.INVALID_TARGET and not res_h_rec.has_valid_focus, "M3-2 Audit Hunter: recovering prey -> INVALID_TARGET & no stale focus")
	wd.wildlife[0]["recovery_hours_left"] = 0.0

	# 15d. Hauler loaded + invalid destination -> INVALID_TARGET, focus cleared, transport_loaded=true, cargo_resource='wood', canonical cargo untouched
	v_haul.set_cargo("wood", 4, "wp_wood", Vector2i(-1, -1))
	j_haul.dest_cell = Vector2i(-1, -1)
	j_haul.target_cell = Vector2i(-1, -1)
	pres_nctx.sync_intent(ctx, v_haul)
	var res_hl_loaded_inv = resolver.resolve(ctx, v_haul, p_loc_haul, wd, null)
	_assert_true(res_hl_loaded_inv.presentation_state == WorkerPresentationResolverScript.State.INVALID_TARGET and not res_hl_loaded_inv.has_valid_focus and res_hl_loaded_inv.transport_loaded and res_hl_loaded_inv.cargo_resource == "wood" and v_haul.get_carrying_amount() == 4, "M3-2 Audit Hauler: loaded + invalid dest -> INVALID_TARGET, transport_loaded=true, cargo preserved")

	# 15e. Restore valid destination -> TRANSPORT_LOADED & dest_cell focus
	j_haul.dest_cell = Vector2i(22, 12)
	pres_nctx.sync_intent(ctx, v_haul)
	var res_hl_loaded_ok = resolver.resolve(ctx, v_haul, p_loc_haul, wd, null)
	_assert_true(res_hl_loaded_ok.presentation_state == WorkerPresentationResolverScript.State.TRANSPORT_LOADED and res_hl_loaded_ok.focus_cell == Vector2i(22, 12) and res_hl_loaded_ok.cargo_resource == "wood", "M3-2 Audit Hauler: valid dest restored -> TRANSPORT_LOADED & focus (22,12)")

	# 15f. Cargo resource change with unchanged amount (4 'wood' -> 4 'food') invalidates cache & updates cargo_resource
	v_haul.set_cargo("food", 4, "wp_farm", Vector2i(22, 12))
	pres_nctx.sync_intent(ctx, v_haul)
	var res_hl_res_chg = resolver.resolve(ctx, v_haul, p_loc_haul, wd, null)
	_assert_true(p_loc_haul.cached_carrying_resource == "food" and res_hl_res_chg.cargo_resource == "food" and res_hl_res_chg.transport_loaded, "M3-2 Audit Hauler: resource change with same amount updates cached_carrying_resource & cargo_resource='food'")

	# 16. M3-3 Guard Presentation & Patrol Behavior
	wd.occupancy[6][16] = true # Watchtower A
	wd.occupancy[14][16] = true # Watchtower B
	wd.occupancy[12][18] = true # Watchtower C
	ctx._set_derived_building_state(
		0, [], [], [], [], [], [],
		["wt_1", "wt_2", "wt_3"],
		[
			{"building_id": "wt_1", "building_type": "watchtower", "access_cell": Vector2i(6, 16)},
			{"building_id": "wt_2", "building_type": "watchtower", "access_cell": Vector2i(14, 16)},
			{"building_id": "wt_3", "building_type": "watchtower", "access_cell": Vector2i(12, 18)},
		],
		[
			{
				"barracks_workplace_id": "wp_barr",
				"barracks_building_id": "wp_barr",
				"barracks_access_cell": Vector2i(12, 16),
				"patrol_targets": [
					{"building_id": "wt_1", "building_type": "watchtower", "access_cell": Vector2i(6, 16)},
					{"building_id": "wt_2", "building_type": "watchtower", "access_cell": Vector2i(14, 16)},
					{"building_id": "wt_3", "building_type": "watchtower", "access_cell": Vector2i(12, 18)},
				],
			}
		]
	)
	v_guard.active_job_id = j_guard.job_id
	v_guard.task_state = SettlementVillagerDataScript.TASK_GUARDING
	v_guard.work_target_id = "wt_1"
	v_guard.cell = Vector2i(7, 16) # East of wt_1 (6,16)
	pres_nctx.sync_intent(ctx, v_guard)
	var p_loc_guard = pres_nctx.get_or_create_locomotion(v_guard)
	p_loc_guard.is_moving = true
	p_loc_guard.status = SettlementNavigationContextScript.MoveStatus.MOVING
	p_loc_guard.flip_h = false
	var res_g_app = resolver.resolve(ctx, v_guard, p_loc_guard, wd, null)
	_assert_true(res_g_app.presentation_state == WorkerPresentationResolverScript.State.APPROACHING and res_g_app.flip_h == false, "M3-3 Guard: moving toward wt_1 -> APPROACHING & preserves path facing")

	# Arrived at wt_1 (7,16) facing West (6,16) -> GUARDING & flip_h == true
	p_loc_guard.is_moving = false
	p_loc_guard.status = SettlementNavigationContextScript.MoveStatus.ARRIVED
	pres.update_presentation(0.05, 1.0)
	var act_guard = pres.get_actor_pool().get_active_actor("stl_m3", v_guard.villager_id)
	_assert_true(act_guard != null and act_guard.worker_presentation_state == WorkerPresentationResolverScript.State.GUARDING and act_guard.worker_focus_cell == Vector2i(6, 16) and act_guard.sprite.flip_h == true, "M3-3 Guard: arrived East of wt_1 -> GUARDING & faces West wt_1 (6,16)")

	# Rotate wt_1 -> wt_2 (14,16) with Guard at (13,16) -> faces East (flip_h == false)
	v_guard.work_target_id = "wt_2"
	v_guard.cell = Vector2i(13, 16)
	pres.update_presentation(0.05, 1.0)
	_assert_true(act_guard.worker_focus_cell == Vector2i(14, 16) and act_guard.sprite.flip_h == false, "M3-3 Guard: rotated wt_2 -> focus (14,16) & faces East")

	# Rotate wt_2 -> wt_3 (12,18) -> focus updates to (12,18)
	v_guard.work_target_id = "wt_3"
	v_guard.cell = Vector2i(12, 17)
	pres.update_presentation(0.05, 1.0)
	_assert_eq(act_guard.worker_focus_cell, Vector2i(12, 18), "M3-3 Guard: rotated wt_3 -> focus (12,18)")

	# Read-only isolation across 10 presentation updates
	var g_vill_snap: Dictionary = v_guard.to_dict()
	var g_job_snap: Dictionary = j_guard.to_dict()
	var g_patrol_before: Array = ctx.get_patrol_targets()
	for _gp in range(10):
		pres.update_presentation(0.05, 1.0)
	_assert_true(v_guard.to_dict() == g_vill_snap and j_guard.to_dict() == g_job_snap and ctx.get_patrol_targets() == g_patrol_before, "M3-3 Guard Read-only: villager, job, work_target_id, and patrol_targets 100% unchanged")

	# Paused Barracks -> WAITING
	var wp_barr_ref = ctx.workplace_registry.get_workplace("wp_barr")
	wp_barr_ref.is_paused = true
	pres.update_presentation(0.05, 1.0)
	_assert_eq(act_guard.worker_presentation_state, WorkerPresentationResolverScript.State.WAITING, "M3-3 Guard: paused Barracks -> WAITING")
	wp_barr_ref.is_paused = false

	# No Watchtowers -> Barracks fallback (12,16) -> GUARDING
	ctx._set_derived_building_state(0, [], [], [], [], [], [], [], [], [])
	v_guard.work_target_id = "wp_barr"
	v_guard.cell = Vector2i(11, 16)
	pres.update_presentation(0.05, 1.0)
	_assert_true(act_guard.worker_presentation_state == WorkerPresentationResolverScript.State.GUARDING and act_guard.worker_focus_cell == Vector2i(12, 16), "M3-3 Guard: Barracks fallback -> GUARDING & focus (12,16)")

	# Barracks invalid -> INVALID_TARGET & focus cleared
	j_guard.target_cell = Vector2i(-1, -1)
	pres.update_presentation(0.05, 1.0)
	_assert_true(act_guard.worker_presentation_state == WorkerPresentationResolverScript.State.INVALID_TARGET and not act_guard.worker_has_valid_focus, "M3-3 Guard: invalid Barracks -> INVALID_TARGET & focus cleared")

	# Invalid job/task -> NONE
	v_guard.active_job_id = ""
	v_guard.task_state = SettlementVillagerDataScript.TASK_IDLE
	pres_nctx.sync_intent(ctx, v_guard)
	var res_g_none = resolver.resolve(ctx, v_guard, p_loc_guard, wd, null)
	_assert_eq(res_g_none.presentation_state, WorkerPresentationResolverScript.State.NONE, "M3-3 Guard: cleared job/task -> NONE")

	# 17. M3-3 Closure: loc == null, non-ARRIVED, ARRIVED, target-change while unresolved, and inactive workplace
	v_guard.active_job_id = j_guard.job_id
	v_guard.task_state = SettlementVillagerDataScript.TASK_GUARDING
	j_guard.target_cell = Vector2i(12, 16)
	v_guard.work_target_id = "wp_barr"
	var res_g_null_loc = resolver.resolve(ctx, v_guard, null, wd, null)
	_assert_true(res_g_null_loc.presentation_state == WorkerPresentationResolverScript.State.WAITING and res_g_null_loc.focus_cell == Vector2i(12, 16), "M3-3 Closure Guard: loc == null -> WAITING (never GUARDING)")

	p_loc_guard.is_moving = false
	p_loc_guard.status = SettlementNavigationContextScript.MoveStatus.WAITING_PATH
	var res_g_wait_path = resolver.resolve(ctx, v_guard, p_loc_guard, wd, null)
	_assert_eq(res_g_wait_path.presentation_state, WorkerPresentationResolverScript.State.WAITING, "M3-3 Closure Guard: WAITING_PATH -> WAITING")

	p_loc_guard.status = SettlementNavigationContextScript.MoveStatus.ARRIVED
	var res_g_arrived = resolver.resolve(ctx, v_guard, p_loc_guard, wd, null)
	_assert_eq(res_g_arrived.presentation_state, WorkerPresentationResolverScript.State.GUARDING, "M3-3 Closure Guard: ARRIVED -> GUARDING")

	# Target changes while loc == null (unresolved) -> stays WAITING with updated focus
	v_guard.work_target_id = "wt_2"
	ctx._set_derived_building_state(0, [], [], [], [], [], [], ["wt_2"], [{"building_id": "wt_2", "building_type": "watchtower", "access_cell": Vector2i(14, 16)}], [])
	var res_g_chg_null = resolver.resolve(ctx, v_guard, null, wd, null)
	_assert_true(res_g_chg_null.presentation_state == WorkerPresentationResolverScript.State.WAITING and res_g_chg_null.focus_cell == Vector2i(14, 16), "M3-3 Closure Guard: target change while loc == null -> WAITING & updated focus (14,16)")

	# Inactive workplace -> INVALID_TARGET
	wp_barr_ref.is_active = false
	var res_g_inact = resolver.resolve(ctx, v_guard, p_loc_guard, wd, null)
	_assert_eq(res_g_inact.presentation_state, WorkerPresentationResolverScript.State.INVALID_TARGET, "M3-3 Closure Guard: inactive Barracks -> INVALID_TARGET")
	wp_barr_ref.is_active = true

	# 18. M3 Final Audit Closure: Canonical H1 Wildlife Reservation Ownership (SettlementResourceSourceAdapter)
	var AdapterScript = preload("res://scripts/world/settlement_resource_source_adapter.gd")
	ctx.economy.set_resource_capacity("raw_meat", 100)
	wd.wildlife[0]["is_available"] = false
	wd.wildlife[0]["reserved_by"] = v_hunt.villager_id
	wd.wildlife[0]["reservation_type"] = "player"
	wd.wildlife[0]["recovery_hours_left"] = 0.0
	ctx.sim_state.production_sources["wp_hunt"]["current_prey_id"] = "deer_1"
	var h_player_res := AdapterScript.execute_hunter_production_transaction(ctx, "wp_hunt", wd, null, v_hunt, 1.0, 1)
	_assert_true(not bool(h_player_res.get("ok", false)) and wd.wildlife[0]["reservation_type"] == "player" and wd.wildlife[0]["reserved_by"] == v_hunt.villager_id and not bool(wd.wildlife[0]["is_available"]), "M3 Closure H1: Player-reserved prey cannot be claimed by Rival H1 & remains untouched")

	# Rival-owned prey can be continued and completed by its owning Rival Hunter
	wd.wildlife[0]["reservation_type"] = "rival"
	v_hunt.work_hours_done = 0.0
	var h_own_cont := AdapterScript.execute_hunter_production_transaction(ctx, "wp_hunt", wd, null, v_hunt, 1.0, 2)
	_assert_true(bool(h_own_cont.get("ok", false)) and not bool(h_own_cont.get("hunt_completed", true)) and wd.wildlife[0]["reserved_by"] == v_hunt.villager_id and wd.wildlife[0]["reservation_type"] == "rival", "M3 Closure H1: Rival-owned prey continued by owning Rival Hunter (reason=%s)" % str(h_own_cont.get("reason", "")))

	# Another Rival Hunter cannot claim prey reserved by v_hunt
	var v_hunt_other = SettlementVillagerDataScript.new(ctx.allocate_villager_id(), "stl_m3", "neutral_tribe", "Hunter2", SettlementVillagerDataScript.ROLE_HUNTER, Vector2i(19, 10))
	ctx.add_villager(v_hunt_other)
	var h_other_res := AdapterScript.execute_hunter_production_transaction(ctx, "wp_hunt", wd, null, v_hunt_other, 1.0, 3)
	_assert_true(not bool(h_other_res.get("ok", false)) and wd.wildlife[0]["reserved_by"] == v_hunt.villager_id, "M3 Closure H1: Another Rival Hunter cannot claim v_hunt's reserved prey")

	# Completing hunt releases only v_hunt's own reservation
	var h_complete := AdapterScript.execute_hunter_production_transaction(ctx, "wp_hunt", wd, null, v_hunt, 2.0, 4)
	_assert_true(bool(h_complete.get("ok", false)) and bool(h_complete.get("hunt_completed", false)) and String(wd.wildlife[0]["reserved_by"]).is_empty() and String(wd.wildlife[0]["reservation_type"]).is_empty(), "M3 Closure H1: Completed Rival hunt releases only its own reservation")

	# Unreserved available prey remains eligible
	wd.wildlife[0]["is_available"] = true
	wd.wildlife[0]["recovery_hours_left"] = 0.0
	ctx.sim_state.production_sources["wp_hunt"]["current_prey_id"] = ""
	var h_free := AdapterScript.execute_hunter_production_transaction(ctx, "wp_hunt", wd, null, v_hunt, 1.0, 5)
	_assert_true(bool(h_free.get("ok", false)) and wd.wildlife[0]["reserved_by"] == v_hunt.villager_id and wd.wildlife[0]["reservation_type"] == "rival", "M3 Closure H1: Unreserved available prey remains eligible")

	pres.queue_free()
	pool_cont.queue_free()
	cam.queue_free()
	await process_frame

	print("\n--------------------------------------------------------------------")
	print("  Results: %d passed, %d failed" % [_passed, _failed])
	print("====================================================================")
	quit(0 if _failed == 0 else 1)
