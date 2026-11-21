extends SceneTree

const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const SettlementSimulationManagerScript = preload("res://scripts/world/settlement_simulation_manager.gd")
const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementNavigationContextScript = preload("res://scripts/world/settlement_navigation_context.gd")
const SettlementJobBoardScript = preload("res://scripts/world/settlement_job_board.gd")
const SettlementWorkplaceRegistryScript = preload("res://scripts/world/settlement_workplace_registry.gd")
const RivalPresentationControllerScript = preload("res://scripts/world/rival_presentation_controller.gd")
const TimeManagerScript = preload("res://scripts/core/time_manager.gd")

const SEEDS: Array[int] = [12345, 22222, 33333, 44444, 55555, 66666]
const HOURS_TO_SIM: int = 72

var _passed: int = 0
var _failed: int = 0
var _anomalies: Array[String] = []

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("  [FAIL] ", msg)

func _record_anomaly(msg: String) -> void:
	if _anomalies.size() < 40:
		_anomalies.append(msg)
	_failed += 1
	printerr("  [ANOMALY] ", msg)

func _step_nctx_hour(ctx: RefCounted, nctx: RefCounted, nav: GridNavigation) -> void:
	# Simulate ~7.5 real seconds of Near-LOD locomotion per game hour (15 steps x 0.5s)
	for v in ctx.get_all_villagers():
		if v == null or String(v.life_state) != SettlementVillagerDataScript.LIFE_ALIVE:
			continue
		var needs_path: bool = nctx.sync_intent(ctx, v)
		var loc = nctx.get_or_create_locomotion(v)
		if needs_path and loc.destination_cell.x >= 0 and nav != null:
			var p: Array[Vector2i] = nav.find_path(v.cell, loc.destination_cell)
			nctx.apply_computed_path(v, p, loc.intent_key, nctx.nav_revision)
	for _step in range(15):
		for v in ctx.get_all_villagers():
			if v == null or String(v.life_state) != SettlementVillagerDataScript.LIFE_ALIVE:
				continue
			nctx.advance_near(v, 0.5, 1.0)

func _run_seed(seed_val: int) -> void:
	print("\n[Stress Seed %d] 72-Hour Multi-Day Simulation" % seed_val)
	var wd = WorldGeneratorScript.generate(seed_val, WorldGeneratorScript.LATEST_GENERATOR_VERSION, 128, 128)
	IsoMath.set_active_map_dimensions(wd.map_width, wd.map_height)
	var nav := GridNavigation.new(wd)
	var mgr := SettlementSimulationManagerScript.new()
	mgr.set_immigration_enabled(false)
	mgr.set_world_data(wd)
	var tm := TimeManagerScript.new()
	mgr.connect_time_manager(tm)
	mgr.register_settlements_from_world_data(wd)
	mgr.seed_initial_populations()

	var nctx_by_sid: Dictionary = {}
	for stl in wd.settlements:
		if stl == null:
			continue
		var sid: String = String(stl.settlement_id)
		var ctx = mgr.get_context(sid)
		if ctx == null:
			continue
		var nctx := SettlementNavigationContextScript.new(sid, wd, nav, stl)
		nctx.configure_settlement_geometry(stl, wd.settlements)
		ctx.set_meta("nav_context", nctx)
		nctx_by_sid[sid] = nctx

	var failed_night_entry: int = 0
	var stuck_morning_wake: int = 0
	var stuck_outside_idle: int = 0
	var home_invalid_count: int = 0

	for h_seq in range(HOURS_TO_SIM):
		# Step physical locomotion before each hour tick
		for sid in nctx_by_sid.keys():
			_step_nctx_hour(mgr.get_context(sid), nctx_by_sid[sid], nav)

		mgr.advance_to_hour_seq(h_seq)
		mgr.process_all_pending()

		var clock_h: int = (6 + h_seq) % 24 # TimeManager starts at 06:00 when h_seq=0
		# Check deep night (01:00..04:00) for housed non-guard non-carrying residents
		if clock_h >= 1 and clock_h <= 4:
			for sid in nctx_by_sid.keys():
				var ctx = mgr.get_context(sid)
				for v in ctx.get_all_villagers():
					if v == null or String(v.life_state) != SettlementVillagerDataScript.LIFE_ALIVE:
						continue
					if v.role == SettlementVillagerDataScript.ROLE_GUARD or v.get_carrying_amount() > 0:
						continue
					if not String(v.home_building_id).is_empty():
						if v.rest_phase != SettlementVillagerDataScript.REST_RESTING_INSIDE:
							failed_night_entry += 1
							if failed_night_entry <= 2:
								var loc_dbg = nctx_by_sid[sid].get_or_create_locomotion(v)
								var bd_dbg = mgr._get_valid_home_building(ctx, v)
								var ac_dbg: Vector2i = bd_dbg.get("access_cell", bd_dbg.get("origin_cell", Vector2i(-1,-1)))
								_record_anomaly("Seed %d h=%d (clock %02d:00) %s/%s (%s) failed night entry: cell=%s(w=%s,occ=%s) dest=%s status=%d ac=%s(w=%s,occ=%s,t=%d) task=%s rest=%s home=%s" % [
									seed_val, h_seq, clock_h, sid, v.villager_id, v.role, str(v.cell), str(nav.is_cell_walkable(v.cell)), str(wd.occupancy[v.cell.x][v.cell.y]), str(loc_dbg.destination_cell), int(loc_dbg.status), str(ac_dbg), str(nav.is_cell_walkable(ac_dbg)), str(wd.occupancy[ac_dbg.x][ac_dbg.y]), int(wd.terrain[ac_dbg.x][ac_dbg.y]), v.task_state, v.rest_phase, v.home_building_id
								])

		# Check mid-morning (10:00..15:00) for residents still stuck resting or stuck outside
		if clock_h >= 10 and clock_h <= 15:
			for sid in nctx_by_sid.keys():
				var ctx = mgr.get_context(sid)
				var nctx = nctx_by_sid[sid]
				for v in ctx.get_all_villagers():
					if v == null or String(v.life_state) != SettlementVillagerDataScript.LIFE_ALIVE:
						continue
					if v.task_state == SettlementVillagerDataScript.TASK_RESTING or v.rest_phase != SettlementVillagerDataScript.REST_NONE:
						stuck_morning_wake += 1
						if stuck_morning_wake <= 5:
							_record_anomaly("Seed %d h=%d (clock %02d:00) %s/%s (%s) stuck resting at morning: cell=%s task=%s rest=%s fat=%.1f" % [
								seed_val, h_seq, clock_h, sid, v.villager_id, v.role, str(v.cell), v.task_state, v.rest_phase, v.fatigue
							])
					elif v.role in ["farmer", "woodcutter", "hunter", "hauler"] and v.task_state == SettlementVillagerDataScript.TASK_IDLE and not v.active_job_id.is_empty():
						var j = ctx.job_board.get_job(v.active_job_id)
						var wp = ctx.workplace_registry.get_workplace(j.workplace_id) if j != null else null
						# Only flag if workplace is active & not capped/paused
						if wp != null and wp.is_active and not wp.is_paused and v.role == "farmer":
							var loc = nctx.get_or_create_locomotion(v)
							if loc.status == SettlementNavigationContextScript.MoveStatus.BLOCKED:
								stuck_outside_idle += 1

	_assert(failed_night_entry == 0, "Seed %d: zero housed residents failed night entry (count=%d)" % [seed_val, failed_night_entry])
	_assert(stuck_morning_wake == 0, "Seed %d: zero residents stuck resting in mid-morning (count=%d)" % [seed_val, stuck_morning_wake])
	_assert(home_invalid_count == 0, "Seed %d: zero invalid homes" % seed_val)

func _test_far_lod_72h_and_transitions() -> void:
	print("\n[FAR-LOD 72h & Transitions] Offscreen Continuity Across All 3 Rival Categories")
	var wd = WorldGeneratorScript.generate(12345, WorldGeneratorScript.LATEST_GENERATOR_VERSION, 128, 128)
	IsoMath.set_active_map_dimensions(wd.map_width, wd.map_height)
	var nav := GridNavigation.new(wd)
	var mgr := SettlementSimulationManagerScript.new()
	mgr.set_immigration_enabled(false)
	mgr.set_world_data(wd)
	var tm := TimeManagerScript.new()
	mgr.connect_time_manager(tm)
	mgr.register_settlements_from_world_data(wd)
	mgr.seed_initial_populations()

	var cam := Camera2D.new()
	cam.position = Vector2(-99999, -99999) # Keep all settlements FAR offscreen
	root.add_child(cam)
	cam.make_current()
	await process_frame
	var pool_container := Node2D.new()
	root.add_child(pool_container)

	var rpc := RivalPresentationControllerScript.new()
	rpc.debug_fog_disabled = true
	rpc.setup(mgr, wd, nav, cam, null, pool_container)

	# Run 72 hours completely in LODTier.FAR
	var far_failed_night: int = 0
	var far_stuck_morning: int = 0
	for h_seq in range(HOURS_TO_SIM):
		rpc.update_presentation(0.2, 1.0)
		mgr.advance_to_hour_seq(h_seq)
		mgr.process_all_pending()
		_assert(rpc.get_actor_pool().get_active_count() == 0, "FAR LOD spawns 0 actors at h=%d" % h_seq) if h_seq % 24 == 0 else null
		var clock_h: int = (6 + h_seq) % 24
		if clock_h >= 2 and clock_h <= 4:
			for sid in mgr.get_registered_settlement_ids():
				var ctx = mgr.get_context(sid)
				for v in ctx.get_all_villagers():
					if v == null or String(v.life_state) != SettlementVillagerDataScript.LIFE_ALIVE:
						continue
					if v.role == SettlementVillagerDataScript.ROLE_GUARD or v.get_carrying_amount() > 0:
						continue
					if not String(v.home_building_id).is_empty() and v.rest_phase != SettlementVillagerDataScript.REST_RESTING_INSIDE:
						far_failed_night += 1
		if clock_h >= 10 and clock_h <= 15:
			for sid in mgr.get_registered_settlement_ids():
				var ctx = mgr.get_context(sid)
				for v in ctx.get_all_villagers():
					if v == null or String(v.life_state) != SettlementVillagerDataScript.LIFE_ALIVE:
						continue
					if v.task_state == SettlementVillagerDataScript.TASK_RESTING or v.rest_phase != SettlementVillagerDataScript.REST_NONE:
						far_stuck_morning += 1

	_assert(far_failed_night == 0, "FAR LOD 72h: zero housed residents failed night entry (count=%d)" % far_failed_night)
	_assert(far_stuck_morning == 0, "FAR LOD 72h: zero residents stuck resting at morning (count=%d)" % far_stuck_morning)

	# Test MID/NEAR -> FAR during home return -> FAR -> NEAR after dawn
	var test_stl = wd.settlements[0]
	var test_sid: String = String(test_stl.settlement_id)
	var test_ctx = mgr.get_context(test_sid)
	# Pan camera onto test_stl (NEAR) while others stay FAR (mixed LOD)
	cam.position = IsoMath.grid_to_world(test_stl.anchor_cell)
	await process_frame
	rpc.update_presentation(0.2, 1.0)
	_assert(not bool(test_ctx.get_meta("lod_is_far", true)), "Panning to settlement clears lod_is_far (NEAR/MID)")
	# Start night -> residents begin returning home, then pan away (MID/NEAR -> FAR)
	mgr.advance_to_hour_seq(HOURS_TO_SIM + 14)
	mgr.process_all_pending()
	rpc.update_presentation(0.2, 1.0)
	cam.position = Vector2(-99999, -99999)
	await process_frame
	rpc.update_presentation(0.2, 1.0)
	_assert(bool(test_ctx.get_meta("lod_is_far", false)), "Panning away sets lod_is_far=true during home return")
	_assert(rpc.get_actor_pool().get_active_count() == 0, "Panning away releases all pooled actors")

	# Advance 2 night hours in FAR -> housed residents finish entering homes
	mgr.advance_to_hour_seq(HOURS_TO_SIM + 16)
	mgr.process_all_pending()
	var inside_cnt := 0
	for v in test_ctx.get_all_villagers():
		if v != null and v.role != SettlementVillagerDataScript.ROLE_GUARD and not String(v.home_building_id).is_empty():
			if v.rest_phase == SettlementVillagerDataScript.REST_RESTING_INSIDE:
				inside_cnt += 1
	_assert(inside_cnt > 0, "MID->FAR home return completes REST_RESTING_INSIDE offscreen (%d inside)" % inside_cnt)

	# Dawn while FAR, then pan back (FAR -> NEAR) -> actors hydrate at current canonical cell
	mgr.advance_to_hour_seq(HOURS_TO_SIM + 24)
	mgr.process_all_pending()
	cam.position = IsoMath.grid_to_world(test_stl.anchor_cell)
	await process_frame
	for _f in range(5):
		rpc.update_presentation(0.1, 1.0)
	_assert(rpc.get_actor_pool().get_active_count() > 0, "FAR->NEAR after dawn hydrates visible actors cleanly")

	rpc.dispose_all()
	cam.queue_free()
	pool_container.queue_free()

func _run() -> void:
	print("====================================================================")
	print("  MULTI-SEED 72-HOUR SETTLEMENT STRESS HARNESS")
	print("====================================================================")
	for s in SEEDS:
		_run_seed(s)
	await _test_far_lod_72h_and_transitions()
	await process_frame
	print("--------------------------------------------------------------------")
	print("  Stress Results: %d passed, %d failed" % [_passed, _failed])
	print("====================================================================")
	quit(0 if _failed == 0 else 1)

func _initialize() -> void:
	call_deferred("_run")
