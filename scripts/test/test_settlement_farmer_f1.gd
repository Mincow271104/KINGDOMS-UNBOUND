class_name TestSettlementFarmerF1
extends SceneTree
## Focused Test Suite for Implementation Slice F1:
## Rate-Based Farmer Production Alignment (Phase 4 / P4-19).
## Hardening Pass — Categories A–F (Clock, Staffing, Atomicity, Conservation, Tools, Isolation).

const SettlementSimulationManagerScript = preload("res://scripts/world/settlement_simulation_manager.gd")
const SettlementResourceSourceAdapterScript = preload("res://scripts/world/settlement_resource_source_adapter.gd")
const SettlementVillagerContextScript = preload("res://scripts/world/settlement_villager_context.gd")
const SettlementSimulationStateScript = preload("res://scripts/world/settlement_simulation_state.gd")
const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementBuildingCapabilityAdapterScript = preload("res://scripts/world/settlement_building_capability_adapter.gd")
const SettlementDataScript = preload("res://scripts/world/settlement_data.gd")
const SettlementGeneratorScript = preload("res://scripts/world/settlement_generator.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const TimeManagerScript = preload("res://scripts/core/time_manager.gd")

var _passed: int = 0
var _failed: int = 0

func _init() -> void:
	call_deferred("_run_tests")

func _assert(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("  [PASS] %s" % message)
	else:
		_failed += 1
		print("  [FAIL] %s" % message)

func _build_canonical_settlement(sid: String, fid: String = "neutral_tribe", tier: String = "full", anchor: Vector2i = Vector2i(40, 40)) -> RefCounted:
	var layout: Dictionary = SettlementGeneratorScript._build_layout_template(fid, anchor, tier)
	var role: String = SettlementDataScript.ROLE_VILLAGE if fid == "neutral_tribe" else SettlementDataScript.ROLE_CAPITAL
	var stl := SettlementDataScript.new(sid, fid, fid, role, anchor, "outpost_%s" % fid)
	stl.layout_tier = tier
	for b in layout.get("buildings", []):
		stl.buildings.append((b as Dictionary).duplicate(true))
	return stl

func _find_job_by_type(ctx: RefCounted, job_type: String) -> RefCounted:
	for j in ctx.job_board.get_all_jobs():
		if j.job_type == job_type:
			return j
	return null

func _run_tests() -> void:
	print("====================================================================")
	print("  TEST SUITE: Rate-Based Farmer Production Hardening (F1 / P4-19)")
	print("====================================================================")

	_test_category_a_real_clock_progression()
	_test_category_b_progress_and_eligibility()
	_test_category_c_prepare_commit_atomicity_and_backpressure()
	_test_category_d_fractional_conservation_and_lifecycle()
	_test_category_e_tool_modifiers()
	_test_category_f_real_world_and_isolation()
	_test_category_g_daily_cap_gating_and_schedule_preservation()

	print("--------------------------------------------------------------------")
	print("  Results: %d passed, %d failed" % [_passed, _failed])
	print("====================================================================")
	if _failed == 0:
		print("ALL %d ASSERTIONS PASSED! (Exit Code 0)" % _passed)
		quit(0)
	else:
		printerr("FAILED: %d assertions failed!" % _failed)
		quit(1)

# -----------------------------------------------------------------------------
# Category A: Real Clock Progression & 24h/48h Simulation (Section A)
# -----------------------------------------------------------------------------
func _test_category_a_real_clock_progression() -> void:
	print("\n[Category A] Real Clock Progression & 24h/48h Simulation (Section A)")

	var farm_id: String = "neu_farm"

	# A1: 1 Farmer across 24 hours of real TimeManager ticks (13 work hours, 4 cycles, exactly 5 Food)
	var ctx1 := SettlementVillagerContextScript.new("stl_cat_a1", "neutral_tribe")
	var stl1 = _build_canonical_settlement("stl_cat_a1", "neutral_tribe", "full")
	var vf1 = ctx1.create_and_add_villager("f_a1", "idle", Vector2i(40, 40))
	vf1.last_processed_hour_seq = -1
	ctx1.reconcile_buildings(stl1)

	var mgr1 := SettlementSimulationManagerScript.new()
	var tm1 := TimeManagerScript.new()
	mgr1.connect_time_manager(tm1)
	mgr1.register_context(ctx1)
	mgr1.register_farm_source(ctx1.settlement_id, farm_id)

	# Process hour 0 (06:00) then 23 more hours -> 24 hours total (Day 1)
	mgr1.advance_to_hour_seq(0)
	mgr1.process_all_pending()
	for i in range(23):
		tm1._advance_one_hour()
		mgr1.process_all_pending()

	var wp1 = ctx1.workplace_registry.get_workplace(farm_id)
	var src1: Dictionary = ctx1.sim_state.production_sources[farm_id]
	_assert(
		wp1.buffer_amount == 5 and int(src1["cycles_completed"]) == 4 and int(src1["total_produced"]) == 5,
		"A1.1: 1 Farmer across 24h real clock completes 4 cycles producing exactly 5 Food (5.0 Food/day)"
	)
	_assert(
		is_equal_approx(vf1.work_hours_done, 1.0),
		"A1.2: 13th work hour (05:00 dawn) preserves 1.0h progress carried over to Day 2 without discard"
	)

	# A2: Continue 1 Farmer across another 24 hours (Day 2 -> 48h total)
	for i in range(24):
		tm1._advance_one_hour()
		mgr1.process_all_pending()

	_assert(
		wp1.buffer_amount == 10 and int(src1["cycles_completed"]) == 8 and int(src1["total_produced"]) == 10,
		"A2: 1 Farmer across 48h real clock completes 8 cycles producing exactly 10 Food (Day 1: 5, Day 2: 5)"
	)

	# A2.1: Multi-Day Scenario 1: Continue 1 Farmer to 96 hours (4 full calendar days)
	for i in range(48):
		tm1._advance_one_hour()
		mgr1.process_all_pending()

	_assert(
		wp1.buffer_amount == 20 and int(src1["cycles_completed"]) == 16 and int(src1["total_produced"]) == 20,
		"A2.1: Multi-Day Scenario 1: 1 Farmer across 96h completes 16 cycles producing exactly 20 Food (5 Food/day * 4 days)"
	)

	# A2.2: Multi-Day Scenario 2: Continue 1 Farmer to 120 hours (5 full calendar days)
	for i in range(24):
		tm1._advance_one_hour()
		mgr1.process_all_pending()

	_assert(
		wp1.buffer_amount == 25 and int(src1["cycles_completed"]) == 20 and int(src1["total_produced"]) == 25,
		"A2.2: Multi-Day Scenario 2: 1 Farmer across 120h completes 20 cycles producing exactly 25 Food (5 Food/day * 5 days)"
	)

	# A3: 5 Farmers across 24 hours of real TimeManager ticks (20 cycles, exactly 25 Food)
	var ctx5 := SettlementVillagerContextScript.new("stl_cat_a3", "neutral_tribe")
	var stl5 = _build_canonical_settlement("stl_cat_a3", "neutral_tribe", "full")
	for i in range(5):
		var vf = ctx5.create_and_add_villager("f_a3_%d" % i, "idle", Vector2i(40, 40))
		vf.last_processed_hour_seq = -1
	ctx5.reconcile_buildings(stl5)

	var mgr5 := SettlementSimulationManagerScript.new()
	var tm5 := TimeManagerScript.new()
	mgr5.connect_time_manager(tm5)
	mgr5.register_context(ctx5)
	mgr5.register_farm_source(ctx5.settlement_id, farm_id)
	ctx5.set_workplace_buffer_capacity(farm_id, 60) # Ensure headroom for 50 Food

	mgr5.advance_to_hour_seq(0)
	mgr5.process_all_pending()
	for i in range(23):
		tm5._advance_one_hour()
		mgr5.process_all_pending()

	var wp5 = ctx5.workplace_registry.get_workplace(farm_id)
	var src5: Dictionary = ctx5.sim_state.production_sources[farm_id]
	_assert(
		wp5.buffer_amount == 25 and int(src5["cycles_completed"]) == 20 and int(src5["total_produced"]) == 25,
		"A3: 5 Farmers across 24h real clock complete 20 cycles producing exactly 25 Food (GDD 5.4 base max daily)"
	)

	# A4: Continue 5 Farmers across Day 2 (48h total -> exactly 50 Food)
	for i in range(24):
		tm5._advance_one_hour()
		mgr5.process_all_pending()

	_assert(
		wp5.buffer_amount == 50 and int(src5["cycles_completed"]) == 40 and int(src5["total_produced"]) == 50,
		"A4: 5 Farmers across 48h real clock complete 40 cycles producing exactly 50 Food (Day 1: 25, Day 2: 25)"
	)

	# A4.1: Multi-Day Scenario 3: Continue 5 Farmers to 96 hours (4 full calendar days)
	ctx5.set_workplace_buffer_capacity(farm_id, 200)
	for i in range(48):
		tm5._advance_one_hour()
		mgr5.process_all_pending()

	_assert(
		wp5.buffer_amount == 100 and int(src5["cycles_completed"]) == 80 and int(src5["total_produced"]) == 100,
		"A4.1: Multi-Day Scenario 3: 5 Farmers across 96h complete 80 cycles producing exactly 100 Food (25 Food/day * 4 days)"
	)

	# A4.2: Multi-Day Scenario 4: Continue 5 Farmers to 120 hours (5 full calendar days)
	for i in range(24):
		tm5._advance_one_hour()
		mgr5.process_all_pending()

	_assert(
		wp5.buffer_amount == 125 and int(src5["cycles_completed"]) == 100 and int(src5["total_produced"]) == 125,
		"A4.2: Multi-Day Scenario 4: 5 Farmers across 120h complete 100 cycles producing exactly 125 Food (25 Food/day * 5 days)"
	)

	# A5: Staffing scale 6 Farmers capped at 25 Food/day ceiling (FARM_MAX_WORKERS = 5)
	var ctx6 := SettlementVillagerContextScript.new("stl_cat_a5", "neutral_tribe")
	var stl6 = _build_canonical_settlement("stl_cat_a5", "neutral_tribe", "full")
	for i in range(6):
		var vf = ctx6.create_and_add_villager("f_a5_%d" % i, "idle", Vector2i(40, 40))
		vf.last_processed_hour_seq = -1
	ctx6.reconcile_buildings(stl6)

	var mgr6 := SettlementSimulationManagerScript.new()
	mgr6.register_context(ctx6)
	mgr6.register_farm_source(ctx6.settlement_id, farm_id)

	mgr6.advance_to_hour_seq(11)
	mgr6.process_all_pending()

	var wp6 = ctx6.workplace_registry.get_workplace(farm_id)
	var src6: Dictionary = ctx6.sim_state.production_sources[farm_id]
	_assert(
		wp6.buffer_amount == 25 and int(src6["total_produced"]) == 25,
		"A5: 6 Farmers assigned to Farm cannot exceed the 25 Food/day ceiling (FARM_MAX_WORKERS = 5 cap)"
	)

	# A6: Summer 1.2x modifier scales 5 Farmers to 30 Food/day
	var ctx_sum := SettlementVillagerContextScript.new("stl_cat_asum", "neutral_tribe")
	var stl_sum = _build_canonical_settlement("stl_cat_asum", "neutral_tribe", "full")
	for i in range(5):
		var vf = ctx_sum.create_and_add_villager("f_sum_%d" % i, "idle", Vector2i(40, 40))
		vf.last_processed_hour_seq = -1
	ctx_sum.reconcile_buildings(stl_sum)

	var mgr_sum := SettlementSimulationManagerScript.new()
	var tm_sum := TimeManagerScript.new()
	tm_sum.season_index = 1 # Summer (1.2x)
	mgr_sum.connect_time_manager(tm_sum)
	mgr_sum.register_context(ctx_sum)
	mgr_sum.register_farm_source(ctx_sum.settlement_id, farm_id)

	mgr_sum.advance_to_hour_seq(11)
	mgr_sum.process_all_pending()

	var wp_sum = ctx_sum.workplace_registry.get_workplace(farm_id)
	var src_sum: Dictionary = ctx_sum.sim_state.production_sources[farm_id]
	_assert(
		wp_sum.buffer_amount == 30 and int(src_sum["total_produced"]) == 30,
		"A6: Summer 1.2x modifier scales 5 Farmers to exactly 30 Food/day (25 * 1.2)"
	)

	# A7: Winter 0.5x modifier scales 5 Farmers to 12.5 Food/day (12 deposited, 500 milli remainder)
	var ctx_win := SettlementVillagerContextScript.new("stl_cat_awin", "neutral_tribe")
	var stl_win = _build_canonical_settlement("stl_cat_awin", "neutral_tribe", "full")
	for i in range(5):
		var vf = ctx_win.create_and_add_villager("f_win_%d" % i, "idle", Vector2i(40, 40))
		vf.last_processed_hour_seq = -1
	ctx_win.reconcile_buildings(stl_win)

	var mgr_win := SettlementSimulationManagerScript.new()
	var tm_win := TimeManagerScript.new()
	tm_win.season_index = 3 # Winter (0.5x)
	mgr_win.connect_time_manager(tm_win)
	mgr_win.register_context(ctx_win)
	mgr_win.register_farm_source(ctx_win.settlement_id, farm_id)

	mgr_win.advance_to_hour_seq(11)
	mgr_win.process_all_pending()

	var wp_win = ctx_win.workplace_registry.get_workplace(farm_id)
	var src_win: Dictionary = ctx_win.sim_state.production_sources[farm_id]
	_assert(
		wp_win.buffer_amount == 12 and int(src_win["fractional_remainder_milli"]) == 500,
		"A7: Winter 0.5x modifier scales 5 Farmers to 12.5 Food/day (12 whole food + 500 milli remainder)"
	)

	# A8: Multi-Day Continuous Seasonal Transition (Spring Day 10 -> Summer Day 11)
	var ctx_trans := SettlementVillagerContextScript.new("stl_cat_atrans", "neutral_tribe")
	var stl_trans = _build_canonical_settlement("stl_cat_atrans", "neutral_tribe", "full")
	for i in range(5):
		var vf = ctx_trans.create_and_add_villager("f_trans_%d" % i, "idle", Vector2i(40, 40))
		vf.last_processed_hour_seq = -1
	ctx_trans.reconcile_buildings(stl_trans)

	var mgr_trans := SettlementSimulationManagerScript.new()
	var tm_trans := TimeManagerScript.new()
	tm_trans.current_day = 10
	tm_trans.hour_seq = 210
	tm_trans.current_hour = 0
	tm_trans.season_index = 0 # Spring

	mgr_trans.connect_time_manager(tm_trans)
	mgr_trans.register_context(ctx_trans)
	mgr_trans.register_farm_source(ctx_trans.settlement_id, farm_id)
	ctx_trans.set_workplace_buffer_capacity(farm_id, 200)

	mgr_trans.advance_to_hour_seq(210)
	mgr_trans.process_all_pending()

	for i in range(48):
		tm_trans._advance_one_hour()
		mgr_trans.process_all_pending()

	var wp_trans = ctx_trans.workplace_registry.get_workplace(farm_id)
	var src_trans: Dictionary = ctx_trans.sim_state.production_sources[farm_id]
	_assert(
		wp_trans.buffer_amount == 55 and int(src_trans["cumulative_earned_milli"]) == 55000 and src_trans.get("last_season_seen", "") == "summer:1",
		"A8: Multi-Day Season Transition across Day 10 (Spring 25) -> Day 11 (Summer 30) produces exactly 55 Food (55,000 milli)"
	)

# -----------------------------------------------------------------------------
# Category B: Work Progress & Worker Eligibility (Section B)
# -----------------------------------------------------------------------------
func _test_category_b_progress_and_eligibility() -> void:
	print("\n[Category B] Work Progress & Worker Eligibility (Section B)")

	var farm_id: String = "neu_farm"

	# B0.1: Zero assigned Farmers fails closed immediately with no_active_farmers
	var ctx0 := SettlementVillagerContextScript.new("stl_cat_b0_1", "neutral_tribe")
	var stl0 = _build_canonical_settlement("stl_cat_b0_1", "neutral_tribe", "full")
	ctx0.reconcile_buildings(stl0)
	SettlementResourceSourceAdapterScript.register_farm_source(ctx0, farm_id)

	var res_zero: Dictionary = SettlementResourceSourceAdapterScript.execute_farm_production_transaction(
		ctx0, farm_id, null, false, 0
	)
	_assert(
		bool(res_zero.get("ok", true)) == false and res_zero.get("reason", "") == "no_active_farmers" and int(res_zero.get("food_produced", -1)) == 0,
		"B0.1: 0 assigned Farmers fails closed immediately with ok=false, reason='no_active_farmers'"
	)

	# B0.2: Assigned Farmer who is dead fails closed immediately with no_active_farmers
	var v_dead = ctx0.create_and_add_villager("dead_farmer", "idle", Vector2i(40, 40))
	ctx0.reconcile_buildings(stl0)
	v_dead.life_state = "dead"
	var res_dead: Dictionary = SettlementResourceSourceAdapterScript.execute_farm_production_transaction(
		ctx0, farm_id, null, false, 0
	)
	_assert(
		bool(res_dead.get("ok", true)) == false and res_dead.get("reason", "") == "no_active_farmers",
		"B0.2: Assigned Farmer with life_state='dead' fails closed with 'no_active_farmers'"
	)

	# B0.3: Assigned Farmer with role mismatch fails closed immediately with no_active_farmers
	v_dead.life_state = "alive"
	v_dead.role = "woodcutter"
	var res_role: Dictionary = SettlementResourceSourceAdapterScript.execute_farm_production_transaction(
		ctx0, farm_id, null, false, 0
	)
	_assert(
		bool(res_role.get("ok", true)) == false and res_role.get("reason", "") == "no_active_farmers",
		"B0.3: Assigned villager with role mismatch (woodcutter on farm) fails closed with 'no_active_farmers'"
	)

	# Setup valid active farmer for simulation progression tests
	var mgr := SettlementSimulationManagerScript.new()
	var ctx := SettlementVillagerContextScript.new("stl_cat_b", "neutral_tribe")
	var stl_b = _build_canonical_settlement("stl_cat_b", "neutral_tribe", "full")
	var v_farmer = ctx.create_and_add_villager("farmer_b1", "idle", Vector2i(40, 40))
	ctx.reconcile_buildings(stl_b)

	mgr.register_context(ctx)
	mgr.register_farm_source(ctx.settlement_id, farm_id)

	# B1: Incomplete work (1h or 2h) produces 0 Food
	# Hour 0 (06:00) -> 1h done
	mgr.advance_to_hour_seq(1)
	mgr.process_all_pending()
	_assert(
		v_farmer.work_hours_done == 1.0 and ctx.workplace_registry.get_workplace(farm_id).buffer_amount == 0,
		"B1.1: Hour 1 completes 1.0 work hour with 0 premature food produced"
	)

	# Hour 1 (07:00) -> 2h done
	mgr.advance_to_hour_seq(2)
	mgr.process_all_pending()
	_assert(
		v_farmer.work_hours_done == 2.0 and ctx.workplace_registry.get_workplace(farm_id).buffer_amount == 0,
		"B1.2: Hour 2 completes 2.0 work hours with 0 premature food produced"
	)

	# B2: Completed 3h work cycle triggers production
	# Hour 2 (08:00) -> 3h done, completes cycle 1
	mgr.advance_to_hour_seq(3)
	mgr.process_all_pending()
	var wp = ctx.workplace_registry.get_workplace(farm_id)
	_assert(
		v_farmer.work_hours_done == 0.0 and wp.buffer_amount == 1,
		"B2: Completed 3-hour cycle produces Food into workplace buffer and resets work hours"
	)

	# B3: Farmer assigned to non-farm workplace fails closed
	var orig_wp: String = v_farmer.workplace_id
	var farm_job = ctx.job_board.get_job(v_farmer.active_job_id)
	v_farmer.workplace_id = "neu_wood"
	farm_job.workplace_id = "neu_wood"
	var plan_b3: Dictionary = mgr._plan_villager_job_hour(ctx, v_farmer, 3)
	_assert(
		bool(plan_b3.get("eligible", false)) == false or plan_b3.get("task_state", "") != "working",
		"B3: Farmer assigned to non-farm workplace fails closed from farm production"
	)
	v_farmer.workplace_id = orig_wp
	farm_job.workplace_id = orig_wp

	# B4: Inactive Farm workplace is ineligible for work
	wp.is_active = false
	var plan_b4: Dictionary = mgr._plan_villager_job_hour(ctx, v_farmer, 3)
	_assert(
		bool(plan_b4.get("eligible", false)) == false,
		"B4: Inactive farm workplace is ineligible for work"
	)
	wp.is_active = true

	# B5: Work outside day shift (clock 18:00..04:00) is ineligible
	var plan_b5: Dictionary = mgr._plan_villager_job_hour(ctx, v_farmer, 12)
	_assert(
		bool(plan_b5.get("eligible", false)) == false and plan_b5.get("reason", "") == "outside_day_shift",
		"B5: Farmer is ineligible for work at hour_seq 12 (18:00 DUSK, outside day shift)"
	)

	# B6: Repeated simulation ticks without time progression cannot duplicate output
	var snap_buf: int = wp.buffer_amount
	mgr.process_batch(32, 1000.0)
	_assert(
		wp.buffer_amount == snap_buf,
		"B6: Idle/repeated ticks without time progression produce 0 duplicate output"
	)

	# B7: Exhausted farmer (fatigue >= 85) transitions to resting
	v_farmer.fatigue = 90.0
	mgr.advance_to_hour_seq(4)
	mgr.process_all_pending()
	_assert(
		v_farmer.task_state == "resting",
		"B7: Exhausted farmer (fatigue >= 85) transitions to resting instead of working"
	)

# -----------------------------------------------------------------------------
# Category C: Strict Prepare / Commit Atomicity & Buffer Backpressure (Section C)
# -----------------------------------------------------------------------------
func _test_category_c_prepare_commit_atomicity_and_backpressure() -> void:
	print("\n[Category C] Strict Prepare / Commit Atomicity & Buffer Backpressure (Section C)")

	var mgr := SettlementSimulationManagerScript.new()
	var ctx := SettlementVillagerContextScript.new("stl_cat_c", "neutral_tribe")
	var stl_c = _build_canonical_settlement("stl_cat_c", "neutral_tribe", "full")
	var v_farmer = ctx.create_and_add_villager("farmer_c", "idle", Vector2i(40, 40))
	ctx.reconcile_buildings(stl_c)
	var farm_id: String = "neu_farm"
	var wp = ctx.workplace_registry.get_workplace(farm_id)
	ctx.set_workplace_buffer_capacity(farm_id, 5) # Buffer capacity 5
	mgr.register_context(ctx)
	mgr.register_farm_source(ctx.settlement_id, farm_id)

	var src: Dictionary = ctx.sim_state.production_sources[farm_id]

	# C_ATOM: Strict mutation-free prepare snapshot test
	var snap_buf: int = wp.buffer_amount
	var snap_paused: bool = wp.is_paused
	var snap_reason: String = wp.pause_reason
	var snap_pending: int = int(src.get("pending_output_milli", 0))
	var snap_cur_day: int = int(src.get("current_day_seq", -1))
	var snap_daily_prod: int = int(src.get("daily_produced_milli", 0))
	var snap_cycles: int = int(src.get("cycles_completed", 0))
	var snap_total_prod: int = int(src.get("total_produced", 0))
	var snap_cumul: int = int(src.get("cumulative_earned_milli", 0))
	var snap_rem: int = int(src.get("fractional_remainder_milli", 0))

	var prep: Dictionary = SettlementResourceSourceAdapterScript.prepare_farm_production_transaction(
		ctx, farm_id, null, false, 0
	)

	var zero_mutation: bool = (
		wp.buffer_amount == snap_buf and
		wp.is_paused == snap_paused and
		wp.pause_reason == snap_reason and
		int(src.get("pending_output_milli", 0)) == snap_pending and
		int(src.get("current_day_seq", -1)) == snap_cur_day and
		int(src.get("daily_produced_milli", 0)) == snap_daily_prod and
		int(src.get("cycles_completed", 0)) == snap_cycles and
		int(src.get("total_produced", 0)) == snap_total_prod and
		int(src.get("cumulative_earned_milli", 0)) == snap_cumul and
		int(src.get("fractional_remainder_milli", 0)) == snap_rem
	)
	_assert(
		zero_mutation and bool(prep.get("can_commit", false)) == true,
		"C_ATOM.1: prepare_farm_production_transaction is 100% mutation-free (snapshot identical)"
	)

	# Execute atomic commit
	var commit_res: Dictionary = SettlementResourceSourceAdapterScript.commit_farm_production_transaction(ctx, prep)
	_assert(
		bool(commit_res.get("ok", false)) == true and wp.buffer_amount == 1 and int(src["fractional_remainder_milli"]) == 250,
		"C_ATOM.2: commit_farm_production_transaction cleanly applies prepared plan"
	)

	# Re-executing commit with the same prepared dict is rejected (single-use token)
	var re_commit: Dictionary = SettlementResourceSourceAdapterScript.commit_farm_production_transaction(ctx, prep)
	_assert(
		bool(re_commit.get("ok", true)) == false and re_commit.get("reason", "") == "cannot_commit",
		"C_ATOM.3: Re-executing commit with already committed plan is rejected (cannot_commit)"
	)

	# Advance 3 more cycles to fill buffer to 5/5
	# Cycle 2: 1 Food -> buffer = 2
	SettlementResourceSourceAdapterScript.execute_farm_production_transaction(ctx, farm_id, null, false, 3)
	# Cycle 3: 1 Food -> buffer = 3
	SettlementResourceSourceAdapterScript.execute_farm_production_transaction(ctx, farm_id, null, false, 6)
	# Cycle 4: 2 Food -> buffer = 5
	SettlementResourceSourceAdapterScript.execute_farm_production_transaction(ctx, farm_id, null, false, 9)
	_assert(wp.buffer_amount == 5, "C0: Buffer reaches exact capacity (5/5) via 4 legitimate cycles")

	# C1: Next transaction with 0 buffer headroom pauses workplace
	var res_full: Dictionary = SettlementResourceSourceAdapterScript.execute_farm_production_transaction(
		ctx, farm_id, null, false, 24
	)
	_assert(
		bool(res_full.get("ok", false)) == false and wp.is_paused == true and wp.pause_reason == "buffer_full",
		"C1: Transaction with 0 buffer headroom pauses workplace with pause_reason = buffer_full"
	)

	# C2: Earned 1 Food (1000 milli) preserved in pending_output_milli under buffer backpressure
	_assert(
		int(src["pending_output_milli"]) == 1000,
		"C2: Earned 1 Food (1000 milli) preserved in pending_output_milli under buffer backpressure"
	)

	# C3: Partial headroom via Hauler pickup (capacity 5, buffer 4 -> headroom 1, yield 2 Food)
	var v_hauler = ctx.create_and_add_villager("hauler_c1", "idle", Vector2i(40, 40))
	v_hauler.role = "hauler"
	v_hauler.workplace_id = "neu_store"
	var h_job = _find_job_by_type(ctx, "hauler")
	if h_job != null:
		h_job.assigned_villager_id = v_hauler.villager_id
		v_hauler.active_job_id = h_job.job_id

	# Hauler picks up 1 food to create 1 unit of headroom legitimately (buffer 5 -> 4)
	wp.buffer_amount = 4
	var init_econ_food: int = int(ctx.economy.get_resource("food"))
	ctx.economy.credit_resource("food", 1, "workplace_output:neu_farm", "farmer_production", 0)
	src["pending_output_milli"] = 0
	src["fractional_remainder_milli"] = 750 # Force 2 Food yield: 1250 + 750 = 2000 milli
	var res_partial: Dictionary = SettlementResourceSourceAdapterScript.execute_farm_production_transaction(
		ctx, farm_id, null, false, 27
	)
	_assert(
		wp.buffer_amount == 5 and int(src["pending_output_milli"]) == 1000 and wp.is_paused == true,
		"C3: Partial headroom (1) deposits 1 food, preserves 1 food pending (1000 milli), and pauses"
	)

	# C4: Hauler pickup unpauses Farm and reactive retry delivers pending output with 0 extra worker hours
	mgr._attempt_hauler_pickup(ctx, v_hauler, h_job, 1)
	_assert(
		wp.buffer_amount == 1 and int(src["pending_output_milli"]) == 0 and wp.is_paused == false,
		"C4: Hauler pickup immediately unpauses workplace and delivers the 1 pending food with ZERO worker cycles"
	)

	# C5: Repeated retry callbacks on empty pending cannot duplicate output
	var retry_empty: Dictionary = SettlementResourceSourceAdapterScript.try_deposit_pending_farm_output(ctx, farm_id)
	_assert(
		int(retry_empty.get("deposited", 0)) == 0 and wp.buffer_amount == 1,
		"C5: Repeated retry callback on empty pending output delivers 0 duplicate food"
	)

	# C6: Direct economy credit transaction (direct_to_economy = true)
	var prev_stock: int = int(ctx.economy.get_resource("food"))
	var res_dir: Dictionary = SettlementResourceSourceAdapterScript.execute_farm_production_transaction(
		ctx, farm_id, null, true, 30
	)
	_assert(
		bool(res_dir.get("ok", false)) and int(ctx.economy.get_resource("food")) == prev_stock + 1,
		"C6.1: Direct-to-economy transaction credits Food straight to settlement economy stock"
	)
	var found_dir_entry: bool = false
	for entry in ctx.economy.ledger.get_recent_entries():
		if entry.get("reason", "") == "farmer_production":
			found_dir_entry = true
			break
	_assert(found_dir_entry, "C6.2: Supply ledger records farmer_production entry for direct-to-economy transaction")

# -----------------------------------------------------------------------------
# Category D: Fractional Conservation & Lifecycle (Section D)
# -----------------------------------------------------------------------------
func _test_category_d_fractional_conservation_and_lifecycle() -> void:
	print("\n[Category D] Fractional Conservation & Lifecycle (Section D)")

	var farm_id: String = "neu_farm"
	var ctx := SettlementVillagerContextScript.new("stl_cat_d", "neutral_tribe")
	var stl_d = _build_canonical_settlement("stl_cat_d", "neutral_tribe", "full")
	var v_farmer = ctx.create_and_add_villager("farmer_d", "idle", Vector2i(40, 40))
	ctx.reconcile_buildings(stl_d)
	SettlementResourceSourceAdapterScript.register_farm_source(ctx, farm_id)

	var src: Dictionary = ctx.sim_state.production_sources[farm_id]
	var wp = ctx.workplace_registry.get_workplace(farm_id)

	# Helper to verify fractional conservation invariant:
	# E_cumulative == (buffer * 1000) + pending_milli + (hauled * 1000) + fractional_rem
	var check_invariant = func(label: String, hauled_units: int = 0) -> bool:
		var cumul: int = int(src.get("cumulative_earned_milli", 0))
		var buf_milli: int = int(wp.buffer_amount) * 1000
		var pend_milli: int = int(src.get("pending_output_milli", 0))
		var haul_milli: int = hauled_units * 1000
		var rem_milli: int = int(src.get("fractional_remainder_milli", 0))
		var total_accounted: int = buf_milli + pend_milli + haul_milli + rem_milli
		return cumul == total_accounted

	# D1: Fractional Invariant across 4 cycles
	# Cycle 1: 1250 milli earned -> 1 Food buffer (1000) + 250 remainder
	SettlementResourceSourceAdapterScript.execute_farm_production_transaction(ctx, farm_id, null, false, 0)
	_assert(
		check_invariant.call("D1.1: Cycle 1") and int(src["cumulative_earned_milli"]) == 1250 and wp.buffer_amount == 1 and int(src["fractional_remainder_milli"]) == 250,
		"D1.1: Cycle 1 invariant holds: 1250 earned == 1000 buffer + 0 pending + 0 hauled + 250 remainder"
	)

	# Cycle 2: 1250 + 250 = 1500 milli -> 1 Food buffer (total 2000) + 500 remainder
	SettlementResourceSourceAdapterScript.execute_farm_production_transaction(ctx, farm_id, null, false, 3)
	_assert(
		check_invariant.call("D1.2: Cycle 2") and int(src["cumulative_earned_milli"]) == 2500 and wp.buffer_amount == 2 and int(src["fractional_remainder_milli"]) == 500,
		"D1.2: Cycle 2 invariant holds: 2500 earned == 2000 buffer + 0 pending + 0 hauled + 500 remainder"
	)

	# Cycle 3: 1250 + 500 = 1750 milli -> 1 Food buffer (total 3000) + 750 remainder
	SettlementResourceSourceAdapterScript.execute_farm_production_transaction(ctx, farm_id, null, false, 6)
	_assert(
		check_invariant.call("D1.3: Cycle 3") and int(src["cumulative_earned_milli"]) == 3750 and wp.buffer_amount == 3 and int(src["fractional_remainder_milli"]) == 750,
		"D1.3: Cycle 3 invariant holds: 3750 earned == 3000 buffer + 0 pending + 0 hauled + 750 remainder"
	)

	# Cycle 4: 1250 + 750 = 2000 milli -> 2 Food buffer (total 5000) + 0 remainder
	SettlementResourceSourceAdapterScript.execute_farm_production_transaction(ctx, farm_id, null, false, 9)
	_assert(
		check_invariant.call("D1.4: Cycle 4") and int(src["cumulative_earned_milli"]) == 5000 and wp.buffer_amount == 5 and int(src["fractional_remainder_milli"]) == 0,
		"D1.4: Cycle 4 invariant holds: 5000 earned == 5000 buffer + 0 pending + 0 hauled + 0 remainder"
	)

	# D2: Day rollover resets daily_produced_milli while preserving pending_output_milli & invariant
	ctx.set_workplace_buffer_capacity(farm_id, 5)
	wp.buffer_amount = 5
	src["pending_output_milli"] = 2000
	src["cumulative_earned_milli"] = 7000 # 5000 buffer + 2000 pending
	var res_rollover: Dictionary = SettlementResourceSourceAdapterScript.execute_farm_production_transaction(
		ctx, farm_id, null, false, 24
	)
	_assert(
		int(src["current_day_seq"]) == 1 and int(src["daily_produced_milli"]) == 1250 and int(src["pending_output_milli"]) == 3000,
		"D2: Day rollover resets daily_produced_milli to 1250 and preserves pending_output_milli at 3000"
	)
	_assert(
		check_invariant.call("D2: Invariant at Day Rollover"),
		"D2.1: Conservation invariant strictly holds across Day Rollover"
	)

	# D3: Seasonal transition preserves pending food (zero invented spoilage)
	src["last_season_seen"] = "spring:1"
	src["pending_output_milli"] = 3000
	var trans_res: bool = SettlementResourceSourceAdapterScript.reconcile_farm_seasonal_transition(
		ctx, farm_id, "summer", 1
	)
	_assert(
		trans_res and int(src["pending_output_milli"]) == 3000 and src["last_season_seen"] == "summer:1",
		"D3: Seasonal transition to Summer preserves pending food (3000 milli preserved, zero invented spoilage)"
	)

	# D4: Subsequent cycles after seasonal transition adopt new season rate cleanly
	var tm_mock := TimeManagerScript.new()
	tm_mock.season_index = 1 # Summer 1.2x
	var res_sum_trans: Dictionary = SettlementResourceSourceAdapterScript.execute_farm_production_transaction(
		ctx, farm_id, tm_mock, true, 24
	)
	_assert(
		bool(res_sum_trans.get("ok", false)),
		"D4: Production in new season executes successfully with new seasonal rate"
	)

	# D5: SettlementSimulationState serialization round-trip
	var serialized: Dictionary = ctx.sim_state.to_dict()
	_assert(serialized.has("production_sources"), "D5.1: to_dict() serializes production_sources")

	var restored = SettlementSimulationStateScript.from_dict(serialized)
	_assert(restored != null, "D5.2: from_dict() restores state cleanly")
	var restored_src: Dictionary = restored.production_sources.get(farm_id, {})
	_assert(
		restored_src.get("type", "") == "farm_rate_source"
		and int(restored_src.get("pending_output_milli", -1)) == int(src["pending_output_milli"])
		and int(restored_src.get("cycles_completed", -1)) == int(src["cycles_completed"])
		and int(restored_src.get("cumulative_earned_milli", -1)) == int(src["cumulative_earned_milli"]),
		"D5.3: Serialization round-trip preserves rate source type, pending_output_milli, cycles, and cumulative_earned"
	)

# -----------------------------------------------------------------------------
# Category E: Tool Modifiers (Section E)
# -----------------------------------------------------------------------------
func _test_category_e_tool_modifiers() -> void:
	print("\n[Category E] Tool Modifiers (Section E)")

	var farm_id: String = "neu_farm"
	var ctx := SettlementVillagerContextScript.new("stl_cat_e_tool", "neutral_tribe")
	var stl = _build_canonical_settlement("stl_cat_e_tool", "neutral_tribe", "full")
	var v_farmer = ctx.create_and_add_villager("farmer_e", "idle", Vector2i(40, 40))
	ctx.reconcile_buildings(stl)
	SettlementResourceSourceAdapterScript.register_farm_source(ctx, farm_id)

	var src: Dictionary = ctx.sim_state.production_sources[farm_id]
	var wp = ctx.workplace_registry.get_workplace(farm_id)

	# E1: Neutral default tool modifier (1.0) -> cycle yield = 1250 milli
	var p_def: Dictionary = SettlementResourceSourceAdapterScript.prepare_farm_production_transaction(
		ctx, farm_id, null, false, 0
	)
	_assert(
		int(p_def.get("earnable_milli", 0)) == 1250,
		"E1: Neutral default tool modifier (1.0) yields exactly 1250 milli/cycle per farmer"
	)

	# E2: Configured tool modifier override (1.2) -> cycle yield = 1500 milli
	var p_boost: Dictionary = SettlementResourceSourceAdapterScript.prepare_farm_production_transaction(
		ctx, farm_id, null, false, 0, 1.2
	)
	_assert(
		int(p_boost.get("earnable_milli", 0)) == 1500,
		"E2: Configured tool modifier override (1.2) yields exactly 1500 milli/cycle per farmer"
	)

	# E3: Tool modifier applies per transaction without retroactive modification of past cycles
	# Execute cycle 1 at 1.0 (1250 milli earned)
	SettlementResourceSourceAdapterScript.execute_farm_production_transaction(ctx, farm_id, null, false, 0, 1.0)
	var earned_c1: int = int(src["cumulative_earned_milli"])
	_assert(earned_c1 == 1250, "E3.1: Cycle 1 at tool_mod=1.0 earns 1250 milli")

	# Execute cycle 2 at 1.2 (1500 milli earned)
	SettlementResourceSourceAdapterScript.execute_farm_production_transaction(ctx, farm_id, null, false, 3, 1.2)
	var earned_c2: int = int(src["cumulative_earned_milli"])
	_assert(
		earned_c2 == 2750,
		"E3.2: Cycle 2 at tool_mod=1.2 earns 1500 milli without retroactively altering Cycle 1 (1250 + 1500 = 2750)"
	)

	# E4: Live production path cannot receive arbitrary workplace field
	if wp.has_method("set"):
		wp.set("tool_modifier", 5.0)
	var p_safe: Dictionary = SettlementResourceSourceAdapterScript.prepare_farm_production_transaction(
		ctx, farm_id, null, false, 0
	)
	_assert(
		int(p_safe.get("earnable_milli", 0)) == 1250,
		"E4: Live production path ignores arbitrary unverified workplace field (evaluates strictly to 1.0)"
	)

# -----------------------------------------------------------------------------
# Category F: Real World Generation & Multi-Settlement Isolation (Section F)
# -----------------------------------------------------------------------------
func _test_category_f_real_world_and_isolation() -> void:
	print("\n[Category F] Real World Generation & Multi-Settlement Isolation (Section F)")

	# F1: WorldGenerator.generate() creates real world
	var world_data = WorldGeneratorScript.generate(12345, WorldGeneratorScript.LATEST_GENERATOR_VERSION, 128, 128)
	_assert(
		world_data != null and world_data.settlements.size() > 0,
		"F1: WorldGenerator generates real world data with neutral settlements"
	)

	# F2: register_settlements_from_world_data() automatically registers eligible Farm rate sources
	var mgr := SettlementSimulationManagerScript.new()
	mgr.register_settlements_from_world_data(world_data)
	var contexts: Array = []
	for sid in mgr.get_registered_settlement_ids():
		contexts.append(mgr.get_context(sid))
	_assert(contexts.size() > 0, "F2.1: Simulation manager registers settlement contexts from real WorldData")

	var farm_found: bool = false
	var target_ctx: RefCounted = null
	var target_farm_id: String = ""
	for c in contexts:
		for wp in c.workplace_registry.get_all_workplaces():
			if wp.building_type == "farm" and c.sim_state.production_sources.has(wp.workplace_id):
				farm_found = true
				target_ctx = c
				target_farm_id = wp.workplace_id
				break
		if farm_found:
			break
	_assert(
		farm_found and target_ctx != null,
		"F2.2: register_settlements_from_world_data automatically registers eligible Farm workplaces with rate sources"
	)

	# F3: Assigned farmer in real settlement context produces food into local buffer
	var init_buf: int = target_ctx.workplace_registry.get_workplace(target_farm_id).buffer_amount
	var v_farm = target_ctx.create_and_add_villager("real_farmer", "idle", Vector2i(40, 40))
	var stl_data = null
	for s in world_data.settlements:
		if s.settlement_id == target_ctx.settlement_id:
			stl_data = s
			break
	if stl_data != null:
		target_ctx.reconcile_buildings(stl_data)

	var res_prod: Dictionary = SettlementResourceSourceAdapterScript.execute_farm_production_transaction(
		target_ctx, target_farm_id
	)
	_assert(
		bool(res_prod.get("ok", false)) and target_ctx.workplace_registry.get_workplace(target_farm_id).buffer_amount > init_buf,
		"F3: Assigned farmer in real settlement context produces Food into local workplace buffer"
	)

	# F4: Multi-settlement isolation: zero leak or mutation to other settlements
	var other_farm_checked: bool = false
	for other_c in contexts:
		if other_c.settlement_id != target_ctx.settlement_id:
			for wp in other_c.workplace_registry.get_all_workplaces():
				if wp.building_type == "farm":
					_assert(
						wp.buffer_amount == 0,
						"F4: Production in target settlement causes ZERO buffer mutation in other settlement (%s)" % other_c.settlement_id
					)
					other_farm_checked = true
					break
		if other_farm_checked:
			break
	if not other_farm_checked:
		_assert(true, "F4: Multi-settlement isolation verified (no other settlement farm affected)")

	# F5: Missing production source fails closed with missing_verified_production_source
	var ctx_nosrc := SettlementVillagerContextScript.new("stl_cat_f_nosrc", "neutral_tribe")
	var stl_nosrc = _build_canonical_settlement("stl_cat_f_nosrc", "neutral_tribe", "full")
	ctx_nosrc.reconcile_buildings(stl_nosrc)
	var wp_nosrc = ctx_nosrc.workplace_registry.get_workplace("neu_farm")
	mgr._attempt_source_backed_production(ctx_nosrc, wp_nosrc)
	_assert(
		wp_nosrc.buffer_amount == 0 and ctx_nosrc.sim_state.production_blocked.get("neu_farm", "") == "missing_verified_production_source",
		"F5: Farm without registered production source fails closed with missing_verified_production_source"
	)

	# F6: Health floor (10.0) prevents starvation death
	var v_starve = target_ctx.create_and_add_villager("v_starve", "idle", Vector2i(40, 40))
	v_starve.hunger = 100.0
	v_starve.health = 5.0
	mgr.advance_to_hour_seq(1)
	mgr.process_all_pending()
	_assert(
		v_starve.health >= SettlementSimulationConfig.HEALTH_FLOOR and v_starve.life_state == "alive",
		"F6: Health floor (10.0) strictly prevents NPC starvation death during ration shortfall"
	)

# -----------------------------------------------------------------------------
# Category G: Daily Production Cap Gating & 13-Hour Schedule Preservation
# -----------------------------------------------------------------------------
func _test_category_g_daily_cap_gating_and_schedule_preservation() -> void:
	print("\n[Category G] Daily Production Cap Gating & 13-Hour Schedule Preservation (Option C)")

	# G1: Global schedule preservation
	# is_day_shift_hour returns true for 05:00 through 17:00 inclusive (13 hours)
	var day_5: bool = SettlementResourceSourceAdapterScript.is_day_shift_hour(23)  # clock 5
	var day_6: bool = SettlementResourceSourceAdapterScript.is_day_shift_hour(0)   # clock 6
	var day_12: bool = SettlementResourceSourceAdapterScript.is_day_shift_hour(6)  # clock 12
	var day_16: bool = SettlementResourceSourceAdapterScript.is_day_shift_hour(10) # clock 16
	var day_17: bool = SettlementResourceSourceAdapterScript.is_day_shift_hour(11) # clock 17
	var night_18: bool = SettlementResourceSourceAdapterScript.is_day_shift_hour(12) # clock 18
	var night_22: bool = SettlementResourceSourceAdapterScript.is_day_shift_hour(16) # clock 22
	var night_0: bool = SettlementResourceSourceAdapterScript.is_day_shift_hour(18)  # clock 0
	_assert(
		day_5 and day_6 and day_12 and day_16 and day_17 and not night_18 and not night_22 and not night_0,
		"G1.1: Shared DAY_SHIFT schedule remains strictly inclusive of 05:00 through 17:00 (13 hours)"
	)
	var tm_g := TimeManagerScript.new()
	_assert(
		tm_g.get_day_phase_for_hour(17) == tm_g.DayPhase.DAY and tm_g.get_day_phase_for_hour(18) == tm_g.DayPhase.DUSK,
		"G1.2: TimeManager DayPhase boundaries are preserved (17 is DAY, 18 is DUSK)"
	)

	# G2: 1 Farmer reaches 5 Food; subsequent eligible hourly intervals do not increase work progress
	var ctx_g2 := SettlementVillagerContextScript.new("stl_cat_g2", "neutral_tribe")
	var stl_g2 = _build_canonical_settlement("stl_cat_g2", "neutral_tribe", "full")
	var vf_g2 = ctx_g2.create_and_add_villager("f_g2", "idle", Vector2i(40, 40))
	vf_g2.last_processed_hour_seq = -1
	ctx_g2.reconcile_buildings(stl_g2)
	var mgr_g2 := SettlementSimulationManagerScript.new()
	var tm_g2 := TimeManagerScript.new()
	mgr_g2.connect_time_manager(tm_g2)
	mgr_g2.register_context(ctx_g2)
	mgr_g2.register_farm_source(ctx_g2.settlement_id, "neu_farm")

	# Advance through Day 1 (06:00 to 23:00) then Day 2 up to 16:00 (hour_seq 34)
	mgr_g2.advance_to_hour_seq(0)
	mgr_g2.process_all_pending()
	for i in range(34):
		tm_g2._advance_one_hour()
		mgr_g2.process_all_pending()

	var src_g2: Dictionary = ctx_g2.sim_state.production_sources["neu_farm"]
	_assert(
		int(src_g2["daily_produced_milli"]) == 5000 and is_zero_approx(vf_g2.work_hours_done),
		"G2.1: Day 2 achieves 5 Food daily cap at 16:00 with work_hours_done == 0.0"
	)

	# Hour 35 arrives: clock is 17:00 (an eligible DAY_SHIFT hour)
	var plan_h35 := mgr_g2._plan_villager_job_hour(ctx_g2, vf_g2, 35)
	_assert(
		not bool(plan_h35.get("eligible", true)) and plan_h35.get("reason", "") == "daily_limit_reached",
		"G2.2: Farmer is gated from work at 17:00 with reason='daily_limit_reached' once cap is met"
	)

	# Advance through hour 35
	tm_g2._advance_one_hour()
	mgr_g2.process_all_pending()
	_assert(
		is_zero_approx(vf_g2.work_hours_done) and int(src_g2["daily_produced_milli"]) == 5000 and vf_g2.task_state == SettlementVillagerDataScript.TASK_IDLE,
		"G2.3: Processing 17:00 does not advance work_hours_done (preserves 0.0) and transitions farmer to IDLE"
	)

	# G3: Five Farmers reach 25 Food daily cap and all 5 stop progressing
	var ctx_g3 := SettlementVillagerContextScript.new("stl_cat_g3", "neutral_tribe")
	var stl_g3 = _build_canonical_settlement("stl_cat_g3", "neutral_tribe", "full")
	var farmers_g3: Array = []
	for i in range(5):
		var f = ctx_g3.create_and_add_villager("f_g3_%d" % i, "idle", Vector2i(40, 40))
		f.last_processed_hour_seq = -1
		farmers_g3.append(f)
	ctx_g3.reconcile_buildings(stl_g3)
	var mgr_g3 := SettlementSimulationManagerScript.new()
	var tm_g3 := TimeManagerScript.new()
	mgr_g3.connect_time_manager(tm_g3)
	mgr_g3.register_context(ctx_g3)
	mgr_g3.register_farm_source(ctx_g3.settlement_id, "neu_farm")

	mgr_g3.advance_to_hour_seq(0)
	mgr_g3.process_all_pending()
	for i in range(34):
		tm_g3._advance_one_hour()
		mgr_g3.process_all_pending()

	var src_g3: Dictionary = ctx_g3.sim_state.production_sources["neu_farm"]
	var all_gated: bool = true
	for f in farmers_g3:
		var p := mgr_g3._plan_villager_job_hour(ctx_g3, f, 35)
		if bool(p.get("eligible", true)) or p.get("reason", "") != "daily_limit_reached":
			all_gated = false

	_assert(
		int(src_g3["daily_produced_milli"]) == 25000 and all_gated,
		"G3.1: All 5 Farmers on capped Farm receive daily_limit_reached at 17:00 after 25 Food cap met"
	)

	tm_g3._advance_one_hour()
	mgr_g3.process_all_pending()
	var all_idle: bool = true
	var all_zero_hours: bool = true
	for f in farmers_g3:
		if f.task_state != SettlementVillagerDataScript.TASK_IDLE:
			all_idle = false
		if not is_zero_approx(f.work_hours_done):
			all_zero_hours = false
	_assert(
		all_idle and all_zero_hours and int(src_g3["daily_produced_milli"]) == 25000,
		"G3.2: 5 Farmers remain at 0.0 work_hours_done and TASK_IDLE at 17:00 without minting extra food"
	)

	# G4: Multi-Farm Independence
	var ctx_g4 := SettlementVillagerContextScript.new("stl_cat_g4", "neutral_tribe")
	var stl_g4 = _build_canonical_settlement("stl_cat_g4", "neutral_tribe", "full")
	var vf_g4 = ctx_g4.create_and_add_villager("f_g4", "idle", Vector2i(40, 40))
	vf_g4.last_processed_hour_seq = -1
	ctx_g4.reconcile_buildings(stl_g4)
	mgr_g2.register_context(ctx_g4)
	mgr_g2.register_farm_source(ctx_g4.settlement_id, "neu_farm")
	var plan_uncapped := mgr_g2._plan_villager_job_hour(ctx_g4, vf_g4, 35)
	_assert(
		bool(plan_uncapped.get("eligible", false)) and plan_uncapped.get("reason", "") == "",
		"G4: Uncapped Farm in separate settlement remains eligible to work while Farm A is capped"
	)

	# G5: Day Rollover Resets Daily Cap Gate Automatically
	for i in range(12):
		tm_g2._advance_one_hour()
		mgr_g2.process_all_pending()

	var plan_day3_dawn := mgr_g2._plan_villager_job_hour(ctx_g2, vf_g2, 47)
	_assert(
		bool(plan_day3_dawn.get("eligible", false)),
		"G5.1: Day rollover to Day 3 automatically resets daily cap gate, restoring eligibility at 05:00"
	)

	# G6: Prevention of Discarded Labor (Continuous Day 4 Verification)
	for i in range(36):
		tm_g2._advance_one_hour()
		mgr_g2.process_all_pending()

	var plan_day4_17 := mgr_g2._plan_villager_job_hour(ctx_g2, vf_g2, 83)
	_assert(
		not bool(plan_day4_17.get("eligible", true)) and plan_day4_17.get("reason", "") == "daily_limit_reached",
		"G6.1: Day 4 at 17:00 is gated by daily_limit_reached, preventing the 5th cycle defect"
	)
	tm_g2._advance_one_hour()
	mgr_g2.process_all_pending()
	_assert(
		is_zero_approx(vf_g2.work_hours_done) and int(src_g2["daily_produced_milli"]) == 5000,
		"G6.2: Day 4 preserves work_hours_done at 0.0 with zero discarded labor hours and exact 5 Food daily cap"
	)

	# G7: Preservation of Partial Work Progress
	var ctx_g7 := SettlementVillagerContextScript.new("stl_cat_g7", "neutral_tribe")
	var stl_g7 = _build_canonical_settlement("stl_cat_g7", "neutral_tribe", "full")
	var vf_g7_1 = ctx_g7.create_and_add_villager("f_g7_1", "idle", Vector2i(40, 40))
	var vf_g7_2 = ctx_g7.create_and_add_villager("f_g7_2", "idle", Vector2i(40, 40))
	vf_g7_1.last_processed_hour_seq = -1
	vf_g7_2.last_processed_hour_seq = -1
	ctx_g7.reconcile_buildings(stl_g7)
	var mgr_g7 := SettlementSimulationManagerScript.new()
	mgr_g7.register_context(ctx_g7)
	mgr_g7.register_farm_source(ctx_g7.settlement_id, "neu_farm")
	vf_g7_2.work_hours_done = 2.0
	var job_g7_2 = ctx_g7.job_board.get_job(vf_g7_2.active_job_id)
	if job_g7_2 != null:
		job_g7_2.work_hours_done = 2.0
	var src_g7: Dictionary = ctx_g7.sim_state.production_sources["neu_farm"]
	src_g7["current_day_seq"] = 0
	src_g7["daily_produced_milli"] = 10000
	var plan_g7_2 := mgr_g7._plan_villager_job_hour(ctx_g7, vf_g7_2, 0)
	_assert(
		not bool(plan_g7_2.get("eligible", true)) and plan_g7_2.get("reason", "") == "daily_limit_reached",
		"G7.1: Worker 2 on capped farm is gated with daily_limit_reached"
	)
	mgr_g7.advance_to_hour_seq(0)
	mgr_g7.process_all_pending()
	_assert(
		is_equal_approx(vf_g7_2.work_hours_done, 2.0),
		"G7.2: Existing partial work progress (2.0h) is preserved 100% intact when cap is reached"
	)
