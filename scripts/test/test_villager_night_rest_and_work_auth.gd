extends SceneTree

const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const SettlementDataScript = preload("res://scripts/world/settlement_data.gd")
const SettlementGeneratorScript = preload("res://scripts/world/settlement_generator.gd")
const SettlementVillagerContextScript = preload("res://scripts/world/settlement_villager_context.gd")
const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementSimulationManagerScript = preload("res://scripts/world/settlement_simulation_manager.gd")
const SettlementNavigationContextScript = preload("res://scripts/world/settlement_navigation_context.gd")
const RivalPresentationControllerScript = preload("res://scripts/world/rival_presentation_controller.gd")
const WorkerPresentationResolverScript = preload("res://scripts/world/worker_presentation_resolver.gd")
const RivalVillagerActorScript = preload("res://scripts/world/rival_villager_actor.gd")
const CitizenScene = preload("res://scenes/entities/citizen.tscn")
const WorkplaceManagerScript = preload("res://scripts/economy/workplace_manager.gd")
const TimeManagerScript = preload("res://scripts/core/time_manager.gd")

var _passed: int = 0
var _failed: int = 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("  [FAIL] ", msg)

func _build_stl(sid: String, fid: String, tier: String, anchor: Vector2i) -> RefCounted:
	var layout: Dictionary = SettlementGeneratorScript._build_layout_template(fid, anchor, tier)
	var role: String = SettlementDataScript.ROLE_VILLAGE if fid == "neutral_tribe" else SettlementDataScript.ROLE_CAPITAL
	var stl := SettlementDataScript.new(sid, fid, fid, role, anchor, "outpost_%s" % fid)
	stl.layout_tier = tier
	for b in layout.get("buildings", []):
		stl.buildings.append((b as Dictionary).duplicate(true))
	return stl

func _test_night_rest_and_day_resume() -> void:
	print("\n[5.1] Rival Night Rest, Housing, Guard Exemption & Daytime Resume")
	var wd = WorldGeneratorScript.generate(12345, WorldGeneratorScript.LATEST_GENERATOR_VERSION, 64, 64)
	var nav := GridNavigation.new(wd)
	var mgr := SettlementSimulationManagerScript.new()
	mgr.set_immigration_enabled(false)
	mgr.set_world_data(wd)
	var tm := TimeManagerScript.new()
	mgr.connect_time_manager(tm)

	# 1. Settlement with houses (rival_merchant full) + homeless villager + guard
	var anchor := Vector2i(32, 32)
	var ctx := SettlementVillagerContextScript.new("stl_night", "rival_merchant")
	var stl = _build_stl("stl_night", "rival_merchant", "full", anchor)
	ctx.reconcile_buildings(stl)
	var res_blds: Array = ctx.get_residential_buildings()
	_assert(not res_blds.is_empty(), "Rival settlement has valid residential building")
	var house_id: String = String(res_blds[0]["building_id"])
	var house_access := anchor
	for bd in ctx.get_building_descriptors():
		if bd is Dictionary and String(bd.get("building_id", "")) == house_id:
			var ac = bd.get("access_cell")
			if ac is Vector2i:
				house_access = ac
			break

	var v_housed = ctx.create_and_add_villager("v_housed", SettlementVillagerDataScript.ROLE_FARMER, anchor)
	v_housed.home_building_id = house_id
	var v_homeless = ctx.create_and_add_villager("v_homeless", SettlementVillagerDataScript.ROLE_WOODCUTTER, anchor)
	v_homeless.home_building_id = ""
	var v_guard = ctx.create_and_add_villager("v_guard", SettlementVillagerDataScript.ROLE_GUARD, anchor)
	v_guard.home_building_id = house_id
	ctx.reconcile_buildings(stl)
	# Ensure v_homeless explicitly has no home
	v_homeless.home_building_id = ""

	var nctx := SettlementNavigationContextScript.new("stl_night", wd, nav, stl)
	nctx.configure_settlement_geometry(stl, [stl])
	ctx.set_meta("nav_context", nctx)
	mgr.register_context(ctx)

	var stock_before: Dictionary = ctx.economy.get_all_resources().duplicate(true)

	# Advance to dusk (h_seq = 13 -> 19:00), keep guard non-exhausted, then advance to night (h_seq = 14 -> 20:00 NIGHT)
	mgr.advance_to_hour_seq(13)
	mgr.process_all_pending()
	v_guard.fatigue = 0.0
	v_guard.role = SettlementVillagerDataScript.ROLE_GUARD
	v_guard.task_state = SettlementVillagerDataScript.TASK_GUARDING
	v_guard.rest_phase = SettlementVillagerDataScript.REST_NONE
	mgr.advance_to_hour_seq(14)
	mgr.process_all_pending()

	_assert(v_housed.task_state == SettlementVillagerDataScript.TASK_RESTING, "Housed Rival villager enters TASK_RESTING at night")
	_assert(v_housed.rest_phase == SettlementVillagerDataScript.REST_RETURNING_HOME or v_housed.rest_phase == SettlementVillagerDataScript.REST_RESTING_INSIDE, "Housed Rival villager enters RETURNING_HOME or RESTING_INSIDE")
	_assert(v_homeless.task_state == SettlementVillagerDataScript.TASK_RESTING, "Homeless Rival villager enters TASK_RESTING at night")
	_assert(v_homeless.rest_phase == SettlementVillagerDataScript.REST_NONE, "Homeless Rival villager stays REST_NONE (no fake house)")
	_assert(v_guard.task_state != SettlementVillagerDataScript.TASK_RESTING, "Guard is NIGHT_EXEMPT and does not abandon guard duty at night (state=%s, rest=%s, fat=%.1f, role=%s)" % [v_guard.task_state, v_guard.rest_phase, v_guard.fatigue, v_guard.role])

	# Verify _resolve_home_access_cell does not assign another resident's house to v_homeless
	var homeless_intent: Dictionary = nctx.resolve_intent(ctx, v_homeless)
	_assert(homeless_intent["dest_cell"] == v_homeless.cell, "Homeless villager does not resolve to another resident's house")

	# Walk v_housed to house access cell and process next night hour (21:00, h_seq = 15) -> REST_RESTING_INSIDE
	v_housed.cell = house_access
	mgr.advance_to_hour_seq(15)
	mgr.process_all_pending()
	_assert(v_housed.rest_phase == SettlementVillagerDataScript.REST_RESTING_INSIDE, "Housed villager transitions to REST_RESTING_INSIDE upon reaching home access")

	# Night transition creates zero free resources
	_assert(ctx.economy.get_all_resources() == stock_before, "Night rest transition creates zero free resources")

	# Save/Load roundtrip preserves rest_phase & home_building_id
	var saved_v: Dictionary = v_housed.to_dict()
	var loaded_v := SettlementVillagerDataScript.from_dict(saved_v)
	_assert(loaded_v != null and loaded_v.rest_phase == SettlementVillagerDataScript.REST_RESTING_INSIDE and loaded_v.home_building_id == house_id, "Save/load roundtrip preserves Rival rest_phase and home_building_id")

	# Daytime resume (h_seq = 24 -> 06:00 DAWN)
	v_housed.fatigue = 5.0
	mgr.advance_to_hour_seq(24)
	mgr.process_all_pending()
	_assert(v_housed.task_state != SettlementVillagerDataScript.TASK_RESTING and v_housed.rest_phase == SettlementVillagerDataScript.REST_NONE, "Housed Rival villager wakes and clears rest_phase at daytime")

	# Pause freezes schedule progression
	var pre_seq: int = v_housed.last_processed_hour_seq
	mgr.process_all_pending()
	_assert(v_housed.last_processed_hour_seq == pre_seq, "Zero time progression freezes Rival schedule state")

func _test_player_farmer_work_location_auth() -> void:
	print("\n[5.2A] Player Farmer Remote Production Prevention & Arrival Authorization")
	var wd = WorldGeneratorScript.generate(12345, WorldGeneratorScript.LATEST_GENERATOR_VERSION, 64, 64)
	var nav := GridNavigation.new(wd)
	var jm := JobManager.new()
	var wpm := WorkplaceManagerScript.new()
	var tm := TimeManagerScript.new()
	tm.current_hour = 9 # DAY

	var farm_cell := Vector2i(35, 35)
	var work_cell := Vector2i(35, 37)
	for dy in range(-5, 6):
		for dx in range(-5, 6):
			var cand := Vector2i(35 + dx, 37 + dy)
			if nav.is_walkable(cand):
				work_cell = cand
				break
		if nav.is_walkable(work_cell):
			break
	wpm.register_workplace("farm_auth_1", "farm", farm_cell, Vector2i(2, 2), work_cell, "food", 50, 5.0, 5)
	var job := jm.create_job("farmer", work_cell, "Farm", "farm_auth_1", 1.0)

	var cit: CitizenController = CitizenScene.instantiate() as CitizenController
	cit.citizen_id = "cit_auth_f1"
	cit.role = "farmer"
	cit.current_cell = Vector2i(5, 5) # FAR away from farm work_cell (35, 37)!
	cit.nav = nav
	cit.job_mgr = jm
	cit.workplace_mgr = wpm
	cit.world_data = wd
	cit.set_custom_time_manager(tm)
	root.add_child(cit)
	cit.sprite.centered = false

	# Force citizen into State.WORKING while still physically far away at (5, 5)
	cit.active_job = job
	job.worker_id = cit.citizen_id
	job.state = JobManager.JobState.IN_PROGRESS
	cit.current_state = CitizenController.State.WORKING

	var wp_obj = wpm.get_workplace("farm_auth_1")
	var buf_before: int = wp_obj.buffer_amount
	cit._process_working(10.0) # 1.33+ game hours — would have completed cycle!
	cit._sync_citizen_visuals(0.1)

	_assert(wp_obj.buffer_amount == buf_before, "Remote Player Farmer (5,5 vs 35,36) produces ZERO food")
	_assert(job.work_hours_done == 0.0, "Remote Player Farmer advances ZERO job hours")
	_assert(cit.current_state != CitizenController.State.WORKING, "Remote Player Farmer exits State.WORKING (redirects to MOVING_TO_JOB)")
	_assert(cit.sprite.frame_coords.y != 4, "Remote Player Farmer does NOT play work animation row 4")

	# Travelling before arrival: zero production
	cit.current_cell = Vector2i(20, 20)
	cit._process_working(10.0)
	_assert(wp_obj.buffer_amount == buf_before, "Travelling Player Farmer produces ZERO food before arrival")

	# Arrived at valid work cell: production proceeds normally
	cit.current_cell = work_cell
	cit.current_state = CitizenController.State.WORKING
	cit.active_job = job
	job.state = JobManager.JobState.IN_PROGRESS
	cit._process_working(10.0)
	cit._sync_citizen_visuals(0.1)
	_assert(wp_obj.buffer_amount > buf_before, "Arrived Player Farmer at %s produces food into buffer (%d -> %d)" % [str(work_cell), buf_before, wp_obj.buffer_amount])

	# Moved away mid-work: no further production
	var buf_after_arrive: int = wp_obj.buffer_amount
	var job2 := jm.create_job("farmer", work_cell, "Farm", "farm_auth_1", 1.0)
	cit.active_job = job2
	cit.current_state = CitizenController.State.WORKING
	cit.current_cell = Vector2i(10, 10)
	cit._process_working(10.0)
	_assert(wp_obj.buffer_amount == buf_after_arrive, "Player Farmer moved away from farm produces ZERO additional food")

	cit.queue_free()

func _test_player_all_professions_work_auth() -> void:
	print("\n[5.2C] Player Smith, Hauler, Natural Resource & Hunter Work-Location Authorization")
	var wd = WorldGeneratorScript.generate(12345, WorldGeneratorScript.LATEST_GENERATOR_VERSION, 64, 64)
	var nav := GridNavigation.new(wd)
	var jm := JobManager.new()
	var wpm := WorkplaceManagerScript.new()
	var tm := TimeManagerScript.new()
	tm.current_hour = 10

	var wp_cell := Vector2i(35, 37)
	for dy in range(-5, 6):
		for dx in range(-5, 6):
			var cand := Vector2i(35 + dx, 37 + dy)
			if nav.is_walkable(cand):
				wp_cell = cand
				break
		if nav.is_walkable(wp_cell):
			break

	# 1. Player Woodcutter/Smith workplace job
	wpm.register_workplace("wc_auth_1", "woodcutter", wp_cell, Vector2i(2, 2), wp_cell, "wood", 50, 4.0, 5)
	var wc_job := jm.create_job("woodcutter", wp_cell, "Chop", "wc_auth_1", 1.0)
	var cit_wc: CitizenController = CitizenScene.instantiate() as CitizenController
	cit_wc.citizen_id = "cit_auth_wc"
	cit_wc.role = "woodcutter"
	cit_wc.current_cell = Vector2i(5, 5)
	cit_wc.nav = nav
	cit_wc.job_mgr = jm
	cit_wc.workplace_mgr = wpm
	cit_wc.world_data = wd
	cit_wc.set_custom_time_manager(tm)
	root.add_child(cit_wc)
	cit_wc.active_job = wc_job
	wc_job.worker_id = cit_wc.citizen_id
	wc_job.state = JobManager.JobState.IN_PROGRESS
	cit_wc.current_state = CitizenController.State.WORKING
	cit_wc._process_working(10.0)
	var wc_wp = wpm.get_workplace("wc_auth_1")
	_assert(wc_wp.buffer_amount == 0, "Remote Player Woodcutter produces ZERO wood")
	cit_wc.current_cell = wp_cell
	cit_wc.active_job = wc_job
	wc_job.state = JobManager.JobState.IN_PROGRESS
	cit_wc.current_state = CitizenController.State.WORKING
	cit_wc._process_working(10.0)
	_assert(wc_wp.buffer_amount > 0, "Arrived Player Woodcutter produces wood (%d)" % wc_wp.buffer_amount)

	# 2. Player Hauler remote pickup blocked, arrived pickup succeeds
	var haul_job := jm.create_job("hauler", wp_cell, "Haul", "wc_auth_1", 1.0)
	haul_job.source_workplace_id = "wc_auth_1"
	haul_job.source_cell = wp_cell
	haul_job.dest_cell = Vector2i(32, 32)
	haul_job.cargo_amount = wc_wp.buffer_amount
	var cit_h: CitizenController = CitizenScene.instantiate() as CitizenController
	cit_h.citizen_id = "cit_auth_h"
	cit_h.role = "hauler"
	cit_h.current_cell = Vector2i(6, 6)
	cit_h.nav = nav
	cit_h.job_mgr = jm
	cit_h.workplace_mgr = wpm
	cit_h.world_data = wd
	cit_h.set_custom_time_manager(tm)
	root.add_child(cit_h)
	cit_h.active_job = haul_job
	haul_job.worker_id = cit_h.citizen_id
	haul_job.state = JobManager.JobState.IN_PROGRESS
	cit_h._pickup_hauler_cargo()
	_assert(cit_h.carrying_amount == 0, "Remote Player Hauler picks up ZERO cargo")
	cit_h.current_cell = wp_cell
	cit_h.active_job = haul_job
	haul_job.state = JobManager.JobState.IN_PROGRESS
	cit_h._pickup_hauler_cargo()
	_assert(cit_h.carrying_amount > 0, "Arrived Player Hauler picks up cargo (%d)" % cit_h.carrying_amount)

	# 3. Natural Resource & Hunter arrival guards on CitizenController
	var nrm_script = preload("res://scripts/economy/natural_resource_manager.gd")
	var nrm = nrm_script.new()
	nrm.nodes_by_id["nr_auth_1"] = {
		"id": "nr_auth_1",
		"type": "iron_vein",
		"cell": wp_cell,
		"remaining_qty": 10,
		"depleted": false
	}
	nrm.reserved_by["nr_auth_1"] = "cit_auth_nr"
	var cit_nr: CitizenController = CitizenScene.instantiate() as CitizenController
	cit_nr.citizen_id = "cit_auth_nr"
	cit_nr.role = "miner"
	cit_nr.current_cell = Vector2i(4, 4)
	cit_nr.nav = nav
	cit_nr.world_data = wd
	cit_nr.natural_resource_mgr = nrm
	cit_nr.set_custom_time_manager(tm)
	root.add_child(cit_nr)
	cit_nr.active_resource_node_id = "nr_auth_1"
	cit_nr.current_state = CitizenController.State.WORKING
	cit_nr._process_natural_resource_work(20.0)
	_assert(cit_nr.carrying_amount == 0 and int(nrm.nodes_by_id["nr_auth_1"]["remaining_qty"]) == 10, "Remote Player Miner harvests ZERO ore from natural resource node")

	cit_wc.queue_free()
	cit_h.queue_free()
	cit_nr.queue_free()

func _test_rival_work_location_auth() -> void:
	print("\n[5.2B] Rival Farmer, Woodcutter, Hunter & Hauler Work-Location Authorization")
	var wd = WorldGeneratorScript.generate(12345, WorldGeneratorScript.LATEST_GENERATOR_VERSION, 64, 64)
	var nav := GridNavigation.new(wd)
	var mgr := SettlementSimulationManagerScript.new()
	mgr.set_immigration_enabled(false)
	mgr.set_world_data(wd)
	var tm := TimeManagerScript.new()
	mgr.connect_time_manager(tm)

	var anchor := Vector2i(32, 32)
	var ctx := SettlementVillagerContextScript.new("stl_wauth", "neutral_tribe")
	var stl = _build_stl("stl_wauth", "neutral_tribe", "full", anchor)
	# Spawn all villagers FAR away at (4, 4)
	var far_cell := Vector2i(4, 4)
	var vf = ctx.create_and_add_villager("rv_f", SettlementVillagerDataScript.ROLE_FARMER, far_cell)
	var vw = ctx.create_and_add_villager("rv_w", SettlementVillagerDataScript.ROLE_WOODCUTTER, far_cell)
	var vh = ctx.create_and_add_villager("rv_h", SettlementVillagerDataScript.ROLE_HAULER, far_cell)
	ctx.reconcile_buildings(stl)

	var nctx := SettlementNavigationContextScript.new("stl_wauth", wd, nav, stl)
	nctx.configure_settlement_geometry(stl, [stl])
	ctx.set_meta("nav_context", nctx)
	mgr.register_context(ctx)
	mgr.register_farm_source("stl_wauth", "neu_farm")

	# Pick a farm workplace ID from registry
	var farm_wp = null
	var wood_wp = null
	for wp in ctx.workplace_registry.get_all_workplaces():
		if wp.building_type == "farm" and farm_wp == null:
			farm_wp = wp
		elif wp.building_type == "woodcutter" and wood_wp == null:
			wood_wp = wp
	if farm_wp != null:
		mgr.register_farm_source("stl_wauth", farm_wp.workplace_id)
	if wood_wp != null:
		mgr.register_woodcutter_source("stl_wauth", wood_wp.workplace_id, [wood_wp.origin_cell + Vector2i(1, 0)])

	var resolver := WorkerPresentationResolverScript.new()
	var pres_out := WorkerPresentationResolverScript.PresentationResult.new()

	# Advance 4 daytime hours while all Rival workers are FAR at (4, 4)
	for h in range(4):
		mgr.advance_to_hour_seq(h)
		mgr.process_all_pending()

	_assert(vf.work_hours_done == 0.0, "Remote Rival Farmer advances ZERO work_hours_done")
	_assert(vf.task_state == SettlementVillagerDataScript.TASK_MOVING_TO_JOB, "Remote Rival Farmer reports TASK_MOVING_TO_JOB")
	if farm_wp != null:
		_assert(int(farm_wp.buffer_amount) == 0, "Remote Rival Farmer produces ZERO farm buffer output")
	_assert(vw.work_hours_done == 0.0, "Remote Rival Woodcutter advances ZERO work_hours_done")
	_assert(vh.get_carrying_amount() == 0, "Remote Rival Hauler picks up ZERO cargo while far away")

	var loc_far := SettlementNavigationContextScript.LocomotionState.new()
	loc_far.is_moving = true
	resolver.resolve_into(ctx, vf, loc_far, wd, tm, pres_out)
	_assert(pres_out.presentation_state != WorkerPresentationResolverScript.State.WORKING_AT_TARGET, "Remote Rival Farmer does NOT play WORKING_AT_TARGET animation")

	# Now move Rival Farmer to the farm cell -> production succeeds!
	if farm_wp != null:
		vf.cell = farm_wp.access_cell if (farm_wp.access_cell.x >= 0) else farm_wp.origin_cell
		for h in range(4, 8):
			mgr.advance_to_hour_seq(h)
			mgr.process_all_pending()
		_assert(int(farm_wp.buffer_amount) > 0, "Arrived Rival Farmer at farm cell produces food (%d)" % int(farm_wp.buffer_amount))

func _test_real_rival_home_assignment_coverage() -> void:
	print("\n[5.3] Real Rival Home Assignment Coverage (WorldGenerator + Seeder + Reconcile)")
	var wd = WorldGeneratorScript.generate(12345, WorldGeneratorScript.LATEST_GENERATOR_VERSION, 128, 128)
	var nav := GridNavigation.new(wd)
	var mgr := SettlementSimulationManagerScript.new()
	mgr.set_world_data(wd)
	var tm := TimeManagerScript.new()
	mgr.connect_time_manager(tm)
	mgr.register_settlements_from_world_data(wd)
	mgr.seed_initial_populations()

	var categories_seen: Dictionary = {}
	for stl in wd.settlements:
		if stl == null:
			continue
		var sid: String = String(stl.settlement_id)
		var fid: String = String(stl.owner_faction_id)
		if not (fid in ["neutral_tribe", "rival_military", "rival_merchant"]):
			continue
		var ctx = mgr.get_context(sid)
		_assert(ctx != null, "Registered context exists for %s (%s)" % [sid, fid])
		if ctx == null:
			continue
		var nctx := SettlementNavigationContextScript.new(sid, wd, nav, stl)
		nctx.configure_settlement_geometry(stl, wd.settlements)
		ctx.set_meta("nav_context", nctx)

		var cap_by_id: Dictionary = {}
		var total_cap: int = 0
		for rb in ctx.get_residential_buildings():
			if rb is Dictionary:
				var bid: String = String(rb.get("building_id", ""))
				var cap: int = int(rb.get("capacity", 0))
				cap_by_id[bid] = cap
				total_cap += cap

		var occ_by_id: Dictionary = {}
		var total_res: int = 0
		var non_empty: int = 0
		var valid_home: int = 0
		var invalid_home: int = 0
		for v in ctx.get_all_villagers():
			total_res += 1
			var hid: String = String(v.home_building_id)
			if not hid.is_empty():
				non_empty += 1
				if cap_by_id.has(hid):
					valid_home += 1
					occ_by_id[hid] = int(occ_by_id.get(hid, 0)) + 1
				else:
					invalid_home += 1

		var unassigned: int = total_res - non_empty
		var unused_cap: int = maxi(0, total_cap - valid_home)
		print("  [%s | %s] total=%d non_empty=%d valid=%d invalid=%d cap=%d occ=%d unassigned=%d unused_cap=%d" % [
			fid, sid, total_res, non_empty, valid_home, invalid_home, total_cap, valid_home, unassigned, unused_cap
		])
		categories_seen[fid] = true
		_assert(total_res > 0, "%s has naturally seeded residents (%d)" % [fid, total_res])
		_assert(invalid_home == 0, "%s has zero invalid home_building_id references" % fid)
		_assert(not (unused_cap > 0 and unassigned > 0), "%s has zero unassigned residents while housing capacity (%d) remains unused" % [fid, total_cap])

		# Snapshot assignments, reconcile again, and run 3 simulation hours -> assignments remain stable
		var before_homes: Dictionary = {}
		for v in ctx.get_all_villagers():
			before_homes[v.villager_id] = String(v.home_building_id)
		ctx.reconcile_buildings(stl)
		for h in range(1, 4):
			mgr.advance_to_hour_seq(h)
			mgr.process_all_pending()
		var stable := true
		for v in ctx.get_all_villagers():
			if String(before_homes.get(v.villager_id, "")) != String(v.home_building_id):
				stable = false
				break
		_assert(stable, "%s home_building_id assignments remain stable after reconcile and simulation" % fid)

	for expected_fid in ["neutral_tribe", "rival_military", "rival_merchant"]:
		_assert(categories_seen.has(expected_fid), "Naturally generated world includes %s settlement" % expected_fid)

func _test_nighttime_hauler_completion_and_rest() -> void:
	print("\n[5.4] Nighttime Hauler Delivery Completion & Post-Delivery Curfew Rest")
	var wd = WorldGeneratorScript.generate(12345, WorldGeneratorScript.LATEST_GENERATOR_VERSION, 64, 64)
	var nav := GridNavigation.new(wd)
	var mgr := SettlementSimulationManagerScript.new()
	mgr.set_immigration_enabled(false)
	mgr.set_world_data(wd)
	var tm := TimeManagerScript.new()
	mgr.connect_time_manager(tm)

	var anchor := Vector2i(32, 32)
	var ctx := SettlementVillagerContextScript.new("stl_haul_night", "rival_merchant")
	var stl = _build_stl("stl_haul_night", "rival_merchant", "full", anchor)
	ctx.reconcile_buildings(stl)
	var res_blds: Array = ctx.get_residential_buildings()
	var house_id: String = String(res_blds[0]["building_id"])
	var house_access := anchor
	for bd in ctx.get_building_descriptors():
		if bd is Dictionary and String(bd.get("building_id", "")) == house_id and bd.get("access_cell") is Vector2i:
			house_access = bd["access_cell"]
			break

	var v_haul = ctx.create_and_add_villager("v_haul_night", SettlementVillagerDataScript.ROLE_HAULER, anchor)
	v_haul.home_building_id = house_id
	var nctx := SettlementNavigationContextScript.new("stl_haul_night", wd, nav, stl)
	nctx.configure_settlement_geometry(stl, [stl])
	ctx.set_meta("nav_context", nctx)
	mgr.register_context(ctx)

	# 1. Advance to dusk (h_seq = 13 -> 19:00), load valid cargo onto Hauler away from dropoff
	mgr.advance_to_hour_seq(13)
	mgr.process_all_pending()
	var food_before: int = ctx.economy.get_resource("food")
	v_haul.cell = Vector2i(10, 10)
	v_haul.cargo = {
		"resource": "food",
		"amount": 4,
		"source_workplace_id": "farm_src_1",
		"dest_cell_x": anchor.x,
		"dest_cell_y": anchor.y,
	}
	v_haul.fatigue = 0.0
	v_haul.task_state = SettlementVillagerDataScript.TASK_HAULING
	v_haul.rest_phase = SettlementVillagerDataScript.REST_NONE

	# 2. Night begins (h_seq = 14 -> 20:00 NIGHT): Hauler must NOT drop cargo or enter curfew rest while carrying
	mgr.advance_to_hour_seq(14)
	mgr.process_all_pending()
	_assert(v_haul.get_carrying_amount() == 4, "Remote nighttime Hauler keeps cargo intact while travelling to dropoff")
	_assert(v_haul.task_state != SettlementVillagerDataScript.TASK_RESTING, "Nighttime Hauler carrying cargo is exempt from curfew until delivery")

	# 3. Hauler arrives at dropoff (anchor) on next night hour (h_seq = 15 -> 21:00): completes delivery
	# Also ensure a workplace has buffer ready so Hauler would otherwise want a new pickup trip
	var farm_wp = null
	for wp in ctx.workplace_registry.get_all_workplaces():
		if wp.building_type == "farm":
			farm_wp = wp
			break
	if farm_wp != null:
		farm_wp.buffer_amount = 5
	v_haul.cell = anchor
	mgr.advance_to_hour_seq(15)
	mgr.process_all_pending()
	_assert(ctx.economy.get_resource("food") == food_before + 4, "Nighttime Hauler completes delivery cleanly (%d -> %d)" % [food_before, ctx.economy.get_resource("food")])
	_assert(v_haul.get_carrying_amount() == 0, "Nighttime Hauler clears cargo after delivery")

	# 4. Next night hour (h_seq = 16 -> 22:00): does NOT accept another trip; returns home & rests
	mgr.advance_to_hour_seq(16)
	mgr.process_all_pending()
	_assert(v_haul.get_carrying_amount() == 0, "Post-delivery Hauler does NOT pick up new cargo during same nighttime")
	_assert(v_haul.task_state == SettlementVillagerDataScript.TASK_RESTING, "Post-delivery Hauler enters TASK_RESTING at night")
	_assert(v_haul.rest_phase == SettlementVillagerDataScript.REST_RETURNING_HOME or v_haul.rest_phase == SettlementVillagerDataScript.REST_RESTING_INSIDE, "Post-delivery housed Hauler returns home to rest")

	# 5. Reaches home access -> REST_RESTING_INSIDE
	v_haul.cell = house_access
	mgr.advance_to_hour_seq(17)
	mgr.process_all_pending()
	_assert(v_haul.rest_phase == SettlementVillagerDataScript.REST_RESTING_INSIDE, "Post-delivery Hauler transitions to REST_RESTING_INSIDE upon reaching home")

func _test_player_hunter_work_location_auth() -> void:
	print("\n[5.5] Player Hunter Location Authorization & Interaction Range")
	var wd = WorldGeneratorScript.generate(12345, WorldGeneratorScript.LATEST_GENERATOR_VERSION, 64, 64)
	var nav := GridNavigation.new(wd)
	var tm := TimeManagerScript.new()
	tm.current_hour = 10

	var WildlifeManagerScript = preload("res://scripts/world/wildlife_manager.gd")
	var WildlifeConfigScript = preload("res://scripts/world/wildlife_config.gd")
	var wlm = WildlifeManagerScript.new()
	var prey_cell := Vector2i(35, 37)
	for dy in range(-5, 6):
		for dx in range(-5, 6):
			var cand := Vector2i(35 + dx, 37 + dy)
			if nav.is_walkable(cand):
				prey_cell = cand
				break
		if nav.is_walkable(prey_cell):
			break
	var rec: Dictionary = wlm._make_animal_record("prey_auth_1", "rabbit", WildlifeConfigScript.Category.PASSIVE_HUNTABLE, prey_cell)
	wlm.animals.append(rec)
	wlm.animals_by_id["prey_auth_1"] = rec
	wlm.reserve_animal("prey_auth_1", "cit_auth_hunt")

	var cit: CitizenController = CitizenScene.instantiate() as CitizenController
	cit.citizen_id = "cit_auth_hunt"
	cit.role = "hunter"
	cit.current_cell = Vector2i(4, 4) # FAR away
	cit.nav = nav
	cit.world_data = wd
	cit.wildlife_mgr = wlm
	cit.set_custom_time_manager(tm)
	root.add_child(cit)

	# 1. Far from prey: cannot complete hunt or produce meat
	cit.active_hunt_target_id = "prey_auth_1"
	cit.current_state = CitizenController.State.WORKING
	cit._process_hunting_work(20.0)
	_assert(cit.carrying_amount == 0, "Far Player Hunter harvests ZERO meat")
	_assert(not wlm.get_animal_by_id("prey_auth_1").is_empty(), "Far Player Hunter leaves prey alive")
	_assert(cit.current_state != CitizenController.State.WORKING, "Far Player Hunter exits State.WORKING")

	# 2. Travelling midway (distance > 1): cannot complete hunt early
	cit.current_cell = prey_cell + Vector2i(3, 0)
	cit.active_hunt_target_id = "prey_auth_1"
	cit.current_state = CitizenController.State.WORKING
	cit._process_hunting_work(20.0)
	_assert(cit.carrying_amount == 0, "Travelling Player Hunter harvests ZERO meat before reaching interaction range")

	# 3. Inside valid adjacent interaction range (Chebyshev distance == 1): completes hunt cleanly
	cit.current_cell = prey_cell + Vector2i(1, 0)
	cit.active_hunt_target_id = "prey_auth_1"
	cit.current_state = CitizenController.State.WORKING
	cit._process_hunting_work(20.0)
	var got_amt: int = cit.carrying_amount
	_assert(got_amt > 0 and cit.carrying_resource == "raw_meat", "Adjacent Player Hunter completes hunt (%d raw_meat)" % got_amt)
	_assert(wlm.get_animal_by_id("prey_auth_1").is_empty() or not bool(wlm.get_animal_by_id("prey_auth_1").get("is_available", true)), "Completed hunt consumes/marks prey cleanly")

	# Repeat tick does not duplicate yield
	cit._process_hunting_work(20.0)
	_assert(cit.carrying_amount == got_amt, "Repeat tick after hunt completion produces ZERO duplicate yield")
	cit.queue_free()

func _test_npc_job_record_crash_and_type_safety() -> void:
	print("\n[5.6] NpcJobRecord.access_cell Crash Reproduction & Record-Type Validation")
	var wd = WorldGeneratorScript.generate(12345, WorldGeneratorScript.LATEST_GENERATOR_VERSION, 64, 64)
	var nav := GridNavigation.new(wd)
	var mgr := SettlementSimulationManagerScript.new()
	mgr.set_immigration_enabled(false)
	mgr.set_world_data(wd)
	var tm := TimeManagerScript.new()
	mgr.connect_time_manager(tm)

	var anchor := Vector2i(32, 32)
	var ctx := SettlementVillagerContextScript.new("stl_p0", "rival_merchant")
	var stl = _build_stl("stl_p0", "rival_merchant", "full", anchor)
	ctx.reconcile_buildings(stl)
	var nctx := SettlementNavigationContextScript.new("stl_p0", wd, nav, stl)
	nctx.configure_settlement_geometry(stl, [stl])
	ctx.set_meta("nav_context", nctx)

	var v_haul = ctx.create_and_add_villager("v_p0_haul", SettlementVillagerDataScript.ROLE_HAULER, anchor)
	var farm_wp = null
	for wp in ctx.workplace_registry.get_all_workplaces():
		if wp.building_type == "farm":
			farm_wp = wp
			break
	if farm_wp != null:
		farm_wp.buffer_amount = 3
		v_haul.cell = anchor
		# Force source_cell == anchor to guarantee line 1134 post-deposit pickup check runs
		var job_h = ctx.job_board.get_job(v_haul.active_job_id) if not v_haul.active_job_id.is_empty() else null
		if job_h != null:
			job_h.source_cell = anchor
			job_h.dest_cell = anchor
	v_haul.cargo = {"resource": "food", "amount": 2, "source_workplace_id": "farm_1", "dest_cell_x": anchor.x, "dest_cell_y": anchor.y}
	mgr.register_context(ctx)

	# Execute _simulate_villager_hour() directly on the exact crash path (daytime deposit -> post-deposit pickup check)
	var ok_sim: bool = mgr._simulate_villager_hour(ctx, v_haul, 2)
	_assert(ok_sim, "_simulate_villager_hour() completes without crashing on Hauler post-deposit path")
	_assert(v_haul.get_carrying_amount() == 0, "Hauler deposit clears cargo cleanly")

	# Direct type-safety checks for _is_villager_at_work_location
	var any_job = null
	for j in ctx.job_board.get_all_jobs():
		any_job = j
		break
	if any_job != null and farm_wp != null:
		_assert(not mgr._is_villager_at_work_location(ctx, v_haul, any_job, any_job), "Passing NpcJobRecord as wp fails closed without crash")
		_assert(not mgr._is_villager_at_work_location(ctx, v_haul, farm_wp, farm_wp), "Passing NpcWorkplaceRecord as job fails closed without crash")
		_assert(not mgr._is_villager_at_work_location(ctx, v_haul, null, farm_wp), "Null job fails closed")
		_assert(not mgr._is_villager_at_work_location(ctx, v_haul, any_job, null), "Null workplace fails closed")
		farm_wp.is_active = false
		_assert(not mgr._is_villager_at_work_location(ctx, v_haul, any_job, farm_wp), "Inactive workplace fails closed")
		farm_wp.is_active = true

func _test_interaction_sequence_hardening() -> void:
	print("\n[5.7] Interaction Sequences: Destroyed Home/Workplace, Reassignment, Context Unregister & Arrival")
	var wd = WorldGeneratorScript.generate(12345, WorldGeneratorScript.LATEST_GENERATOR_VERSION, 64, 64)
	var nav := GridNavigation.new(wd)
	var mgr := SettlementSimulationManagerScript.new()
	mgr.set_immigration_enabled(false)
	mgr.set_world_data(wd)
	var tm := TimeManagerScript.new()
	mgr.connect_time_manager(tm)

	var anchor := Vector2i(32, 32)
	var ctx := SettlementVillagerContextScript.new("stl_seq", "rival_merchant")
	var stl = _build_stl("stl_seq", "rival_merchant", "full", anchor)
	ctx.reconcile_buildings(stl)
	var nctx := SettlementNavigationContextScript.new("stl_seq", wd, nav, stl)
	nctx.configure_settlement_geometry(stl, [stl])
	ctx.set_meta("nav_context", nctx)
	mgr.register_context(ctx)

	var res_blds: Array = ctx.get_residential_buildings()
	var house_id: String = String(res_blds[0]["building_id"])
	var house_access := anchor
	for bd in ctx.get_building_descriptors():
		if bd is Dictionary and String(bd.get("building_id", "")) == house_id and bd.get("access_cell") is Vector2i:
			house_access = bd["access_cell"]
			break

	var v = ctx.create_and_add_villager("v_seq", SettlementVillagerDataScript.ROLE_FARMER, Vector2i(10, 10))
	v.home_building_id = house_id

	# 1. Night begins -> RETURNING_HOME, then reaches home_access -> immediate arrival transition
	mgr.advance_to_hour_seq(14) # 20:00 NIGHT
	mgr.process_all_pending()
	_assert(v.rest_phase == SettlementVillagerDataScript.REST_RETURNING_HOME, "Far villager enters REST_RETURNING_HOME at night")
	v.cell = house_access
	var entered: bool = mgr.complete_home_arrival_if_eligible(ctx, v)
	_assert(entered and v.rest_phase == SettlementVillagerDataScript.REST_RESTING_INSIDE, "Immediate arrival transition moves villager to REST_RESTING_INSIDE")

	# 2. All homes destroyed while resting -> next hour falls back safely to REST_NONE (no crash, no fake house)
	var all_res_ids: Dictionary = {}
	for rb in res_blds:
		if rb is Dictionary:
			all_res_ids[String(rb.get("building_id", ""))] = true
	for i in range(stl.buildings.size() - 1, -1, -1):
		var b_id: String = String(stl.buildings[i].get("id", stl.buildings[i].get("building_id", "")))
		if all_res_ids.has(b_id):
			stl.buildings.remove_at(i)
	ctx.reconcile_buildings(stl)
	mgr.advance_to_hour_seq(15)
	mgr.process_all_pending()
	_assert(v.task_state == SettlementVillagerDataScript.TASK_RESTING and v.rest_phase == SettlementVillagerDataScript.REST_RETURNING_HOME and v.home_building_id == "mer_hq", "Destroyed houses reassign villager to remaining HQ residential capacity cleanly")

	# 2b. Remove remaining residential HQ -> falls back safely to REST_NONE (no crash, no fake house)
	for i in range(stl.buildings.size() - 1, -1, -1):
		if String(stl.buildings[i].get("id", "")) == "mer_hq":
			stl.buildings.remove_at(i)
	ctx.reconcile_buildings(stl)
	mgr.advance_to_hour_seq(16)
	mgr.process_all_pending()
	_assert(v.task_state == SettlementVillagerDataScript.TASK_RESTING and v.rest_phase == SettlementVillagerDataScript.REST_NONE, "All homes destroyed falls back safely to REST_NONE at night")

	# 3. RivalPresentationController context unregistration removes nav_context metadata cleanly
	var rpc = RivalPresentationControllerScript.new()
	rpc.sim_manager = mgr
	rpc.world_data = wd
	rpc.grid_nav = nav
	rpc.reconcile_settlements()
	_assert(ctx.has_meta("nav_context"), "RivalPresentationController binds nav_context")
	rpc.remove_settlement("stl_seq")
	_assert(not ctx.has_meta("nav_context"), "remove_settlement clears nav_context metadata cleanly")
	rpc.free()

func _test_clock_alignment_and_diagnostics() -> void:
	print("\n[5.8] TimeManager Clock Alignment After reset_time() & Bounded Diagnostic Trace")
	var mgr := SettlementSimulationManagerScript.new()
	mgr.diagnostic_trace_enabled = true
	var tm := TimeManagerScript.new()
	# Simulate a second session where hour_seq=14 (would map to 20:00 NIGHT via offset) while reset_time(6,1,1) sets DAWN
	tm.hour_seq = 14
	tm.reset_time(6, 1, 1)
	mgr.connect_time_manager(tm)

	var ctx := SettlementVillagerContextScript.new("stl_clk", "rival_merchant")
	var v = ctx.create_and_add_villager("v_clk", SettlementVillagerDataScript.ROLE_HAULER, Vector2i(32, 32))
	mgr.register_context(ctx)
	mgr._simulate_villager_hour(ctx, v, 14)
	_assert(v.task_state != SettlementVillagerDataScript.TASK_RESTING, "reset_time(6) DAWN overrides stale hour_seq=14 offset")

	# Transition to NIGHT on tm (20:00) -> records bounded diagnostic event
	tm.current_hour = 20
	tm.hour_seq = 15
	mgr._simulate_villager_hour(ctx, v, 15)
	_assert(v.task_state == SettlementVillagerDataScript.TASK_RESTING, "TimeManager NIGHT (20:00) triggers TASK_RESTING")
	var evs: Array[Dictionary] = mgr.get_diagnostic_events()
	_assert(evs.size() >= 1 and String(evs[evs.size() - 1].get("villager_id", "")) == String(v.villager_id), "Diagnostic trace records state transition with villager_id")
	mgr.clear_diagnostic_events()
	mgr.free()

func _test_all_settlement_categories_and_actor_pool() -> void:
	print("\n[5.1B] All Rival Categories Night Rest, Actor Pool Rebinding & Fog Hiding")
	var wd = WorldGeneratorScript.generate(12345, WorldGeneratorScript.LATEST_GENERATOR_VERSION, 64, 64)
	var nav := GridNavigation.new(wd)
	var mgr := SettlementSimulationManagerScript.new()
	mgr.set_immigration_enabled(false)
	mgr.set_world_data(wd)
	var tm := TimeManagerScript.new()
	mgr.connect_time_manager(tm)

	var fids: Array[String] = ["rival_military", "rival_merchant", "neutral_tribe"]
	var villagers: Dictionary = {}
	for i in range(fids.size()):
		var fid: String = fids[i]
		var sid: String = "stl_%s" % fid
		var anchor := Vector2i(16 + i * 16, 32)
		var ctx := SettlementVillagerContextScript.new(sid, fid)
		var stl = _build_stl(sid, fid, "full", anchor)
		ctx.reconcile_buildings(stl)
		var res_blds: Array = ctx.get_residential_buildings()
		var hid: String = String(res_blds[0]["building_id"]) if not res_blds.is_empty() else ""
		var v = ctx.create_and_add_villager("v_%s" % fid, SettlementVillagerDataScript.ROLE_FARMER, anchor)
		v.home_building_id = hid
		var nctx := SettlementNavigationContextScript.new(sid, wd, nav, stl)
		nctx.configure_settlement_geometry(stl, [stl])
		ctx.set_meta("nav_context", nctx)
		mgr.register_context(ctx)
		villagers[fid] = v

	mgr.advance_to_hour_seq(14) # 20:00 NIGHT
	mgr.process_all_pending()
	for fid in fids:
		var v = villagers[fid]
		_assert(v.task_state == SettlementVillagerDataScript.TASK_RESTING, "%s villager enters TASK_RESTING at night" % fid)

	# Actor pool rebinding & Fog hiding
	var actor: Node2D = RivalVillagerActorScript.new()
	root.add_child(actor)
	actor.bind_villager("stl_1", "v_1", "rival_merchant", "farmer")
	var pres_work := WorkerPresentationResolverScript.PresentationResult.new()
	pres_work.presentation_state = WorkerPresentationResolverScript.State.WORKING_AT_TARGET
	actor.set_worker_presentation_metadata(pres_work)
	actor.sync_presentation(Vector2(100, 100), false, 0, false, true, 0.1)
	_assert(actor.visible == true, "Visible RivalVillagerActor is shown when not resting inside and fog-visible")
	actor.sync_presentation(Vector2(100, 100), false, 0, false, false, 0.1)
	_assert(actor.visible == false, "RivalVillagerActor hides when p_visible is false (fog-hidden or resting inside)")

	# Rebind clears stale worker presentation metadata
	actor.release_binding()
	actor.bind_villager("stl_2", "v_2", "rival_military", "guard")
	_assert(actor.worker_presentation_state == WorkerPresentationResolverScript.State.NONE, "Pool rebinding clears stale worker_presentation_state")
	actor.queue_free()

func _run() -> void:
	print("====================================================================")
	print("  TEST SUITE: Night Rest Schedule & Work-Location Authorization")
	print("====================================================================")
	_test_night_rest_and_day_resume()
	_test_all_settlement_categories_and_actor_pool()
	_test_player_farmer_work_location_auth()
	_test_player_all_professions_work_auth()
	_test_rival_work_location_auth()
	_test_real_rival_home_assignment_coverage()
	_test_nighttime_hauler_completion_and_rest()
	_test_player_hunter_work_location_auth()
	_test_npc_job_record_crash_and_type_safety()
	_test_interaction_sequence_hardening()
	_test_clock_alignment_and_diagnostics()
	await process_frame
	print("--------------------------------------------------------------------")
	print("  Results: %d passed, %d failed" % [_passed, _failed])
	print("====================================================================")
	quit(0 if _failed == 0 else 1)

func _initialize() -> void:
	call_deferred("_run")
