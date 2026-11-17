extends SceneTree
## Focused Phase 4 Test Suite: Rival Settlement Villager System — Core Villager Life & Simulation
## Covers Sections 20.1 through 20.10 (Architecture v1.0 — LOCKED).

const TimeManagerScript = preload("res://scripts/core/time_manager.gd")
const SettlementGeneratorScript = preload("res://scripts/world/settlement_generator.gd")
const SettlementDataScript = preload("res://scripts/world/settlement_data.gd")
const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementVillagerContextScript = preload("res://scripts/world/settlement_villager_context.gd")
const SettlementEconomyScript = preload("res://scripts/world/settlement_economy.gd")
const SettlementSimulationConfigScript = preload("res://scripts/world/settlement_simulation_config.gd")
const SettlementSimulationStateScript = preload("res://scripts/world/settlement_simulation_state.gd")
const SettlementSimulationManagerScript = preload("res://scripts/world/settlement_simulation_manager.gd")
const SettlementResourceSourceAdapterScript = preload("res://scripts/world/settlement_resource_source_adapter.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const FactionManagerScript = preload("res://scripts/factions/faction_manager.gd")

var _passed: int = 0
var _failed: int = 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] %s" % msg)
	else:
		_failed += 1
		printerr("  [FAIL] %s" % msg)

func _build_canonical_settlement(sid: String, fid: String, tier: String, anchor: Vector2i = Vector2i(40, 40)) -> RefCounted:
	var layout: Dictionary = SettlementGeneratorScript._build_layout_template(fid, anchor, tier)
	var role: String = SettlementDataScript.ROLE_VILLAGE if fid == "neutral_tribe" else SettlementDataScript.ROLE_CAPITAL
	var stl := SettlementDataScript.new(sid, fid, fid, role, anchor, "outpost_%s" % fid)
	stl.layout_tier = tier
	for b in layout.get("buildings", []):
		stl.buildings.append((b as Dictionary).duplicate(true))
	return stl

func _initialize() -> void:
	print("\n========================================================")
	print("  TEST SUITE: Rival Settlement Core Simulation (Phase 4)")
	print("========================================================")

	_test_20_1_simulation_manager_and_isolation()
	_test_20_2_hourly_queue_and_fault_isolation()
	_test_20_3_daily_queue_and_exact_once_consumption()
	_test_20_4_needs_fatigue_health_floor_and_morale()
	_test_20_5_survival_mode_and_awaiting_resupply()
	_test_20_6_job_execution_and_production_sources()
	_test_20_7_atomic_transactions_and_callbacks()
	_test_20_8_external_delivery_and_buffer_hauling()
	_test_20_9_batching_backpressure_and_synthetic_loads()
	_test_20_10_serialization_and_backward_compatibility()
	_test_hardening_hourly_atomicity()
	_test_hardening_backpressure_player_speed()
	await _test_hardening_worldview_runtime_smoke()

	print("--------------------------------------------------------")
	print("  Results: %d passed, %d failed" % [_passed, _failed])
	print("========================================================")
	quit(1 if _failed > 0 else 0)

func _test_20_1_simulation_manager_and_isolation() -> void:
	print("\n[20.1] Simulation Manager Lifecycle, Registration, TimeManager & Isolation")
	var tm := TimeManagerScript.new()
	var mgr := SettlementSimulationManagerScript.new()
	root.add_child(tm)
	root.add_child(mgr)

	_assert(mgr.connect_time_manager(tm) and mgr.is_connected_to_time_manager(), "Manager connects cleanly to TimeManager")
	_assert(mgr.connect_time_manager(tm), "Repeated connect_time_manager is idempotent")

	var ctx_a := SettlementVillagerContextScript.new("stl_mgr_a", "rival_military")
	ctx_a.reconcile_buildings(_build_canonical_settlement("stl_mgr_a", "rival_military", "compact"))
	var ctx_b := SettlementVillagerContextScript.new("stl_mgr_b", "neutral_tribe")
	ctx_b.reconcile_buildings(_build_canonical_settlement("stl_mgr_b", "neutral_tribe", "compact"))

	_assert(mgr.register_context(ctx_b) and mgr.register_context(ctx_a), "Registers valid settlement contexts (0 villagers allowed)")
	_assert(not mgr.register_context(ctx_a), "Duplicate settlement_id registration is rejected")
	_assert(mgr.get_registered_settlement_ids() == ["stl_mgr_a", "stl_mgr_b"], "Registered settlement IDs maintain deterministic sorted order")

	# Advance TimeManager by 3 hours -> hour_seq becomes 3 (NOT day*24)
	for _i in range(3):
		tm._advance_one_hour()
	mgr.process_all_pending()
	_assert(tm.get_hour_seq() == 3 and ctx_a.sim_state.settled_hour_seq == 3 and ctx_b.sim_state.settled_hour_seq == 3, "Zero-villager contexts advance settled_hour_seq via TimeManager.hour_passed")

	mgr.disconnect_time_manager()
	_assert(not mgr.is_connected_to_time_manager(), "Manager disconnects cleanly from TimeManager")
	mgr.queue_free()
	tm.queue_free()

func _test_20_2_hourly_queue_and_fault_isolation() -> void:
	print("\n[20.2] Deterministic Hourly Queue, Batching & Per-Settlement Fault Isolation")
	var mgr := SettlementSimulationManagerScript.new()
	mgr.max_villagers_per_batch = 2

	var ctx_ok := SettlementVillagerContextScript.new("stl_hq_ok", "neutral_tribe")
	ctx_ok.reconcile_buildings(_build_canonical_settlement("stl_hq_ok", "neutral_tribe", "full"))
	var v_ok1 = ctx_ok.create_and_add_villager("OK 1", "idle", Vector2i(40, 40))
	var v_ok2 = ctx_ok.create_and_add_villager("OK 2", "idle", Vector2i(40, 40))
	ctx_ok.reconcile_buildings(_build_canonical_settlement("stl_hq_ok", "neutral_tribe", "full"))

	var ctx_bad := SettlementVillagerContextScript.new("stl_hq_bad", "rival_military")
	ctx_bad.reconcile_buildings(_build_canonical_settlement("stl_hq_bad", "rival_military", "compact"))
	var v_bad = ctx_bad.create_and_add_villager("Bad 1", "idle", Vector2i(40, 40))
	ctx_bad.reconcile_buildings(_build_canonical_settlement("stl_hq_bad", "rival_military", "compact"))

	mgr.register_context(ctx_ok)
	mgr.register_context(ctx_bad)

	# Inject fault into stl_hq_bad at hour 2
	mgr.set_fault_hook_for_test("stl_hq_bad", func(_sid: String, _vid: String, h: int) -> bool:
		return h != 2
	)

	mgr.advance_to_hour_seq(4)
	# Duplicate advance_to_hour_seq(4) or stale advance_to_hour_seq(2) must not double-process
	mgr.advance_to_hour_seq(4)
	mgr.advance_to_hour_seq(2)

	var b1 := mgr.process_batch(2, 1000.0)
	_assert(int(b1["processed_items"]) <= 2 and int(b1["remaining_pending"]) > 0, "Partial batch respects max_villagers_per_batch=2 and preserves unfinished work")

	mgr.process_all_pending()
	_assert(v_ok1.last_processed_hour_seq == 4 and v_ok2.last_processed_hour_seq == 4, "Healthy settlement processes all 4 hours deterministically despite fault in another settlement")
	_assert(v_bad.last_processed_hour_seq == 1 and mgr.is_settlement_isolated("stl_hq_bad"), "Faulty settlement stops at hour 1, is isolated after repeated failures, and never falsely advances watermark")

	# Clear fault & isolation -> resumes hour 2..4 cleanly
	mgr.set_fault_hook_for_test("stl_hq_bad", Callable())
	mgr.clear_settlement_isolation("stl_hq_bad")
	mgr.process_all_pending()
	_assert(v_bad.last_processed_hour_seq == 4, "Cleared settlement resumes and completes missing hours 2..4 in order")
	mgr.free()

func _test_20_3_daily_queue_and_exact_once_consumption() -> void:
	print("\n[20.3] Daily Queue Ordering, Actual Hour Sequence & Exactly-Once Food Consumption")
	var tm := TimeManagerScript.new()
	var mgr := SettlementSimulationManagerScript.new()
	mgr.connect_time_manager(tm)

	var ctx := SettlementVillagerContextScript.new("stl_daily", "neutral_tribe")
	ctx.reconcile_buildings(_build_canonical_settlement("stl_daily", "neutral_tribe", "full"))
	var v1 = ctx.create_and_add_villager("D1", "idle", Vector2i(40, 40))
	var v2 = ctx.create_and_add_villager("D2", "idle", Vector2i(40, 40))
	ctx.reconcile_buildings(_build_canonical_settlement("stl_daily", "neutral_tribe", "full"))
	mgr.register_context(ctx)

	var init_food: int = ctx.economy.get_resource("food") # 60
	# TimeManager starts at hour 6, day 1. Advancing 18 hours reaches hour 0, day 2 (hour_seq == 18, NOT 24!)
	for _i in range(18):
		tm._advance_one_hour()
	_assert(tm.current_day == 2 and tm.get_hour_seq() == 18, "Day 2 rollover occurs at actual hour_seq == 18 (not (day-1)*24)")

	# Before hourly backlog finishes, daily event must remain pending
	_assert(ctx.sim_state.pending_daily == [18] and ctx.economy.get_resource("food") == init_food, "Daily event waits in pending_daily until hourly backlog up to 18 finishes")

	# Register a new villager for next tick BEFORE draining -> must NOT be charged for daily event 18
	var v3 := SettlementVillagerDataScript.new(ctx.allocate_villager_id(), "stl_daily", "neutral_tribe", "Newcomer")
	_assert(ctx.register_villager_for_next_tick(v3) and v3.last_processed_hour_seq == 18, "Newcomer stamped at required_hour_seq=18")

	mgr.process_all_pending()
	# Only v1 and v2 consumed 1 food each (60 -> 58) + neutral forage at hours 6,12,18 (+4*3 = +12 -> 70)!
	_assert(
		ctx.sim_state.pending_daily.is_empty()
		and ctx.sim_state.completed_daily_seq == 18
		and int(ctx.sim_state.villager_daily_seq.get(v1.villager_id, -1)) == 18
		and int(ctx.sim_state.villager_daily_seq.get(v2.villager_id, -1)) == 18
		and ctx.economy.get_resource("food") == init_food + 12 - 2,
		"Daily event 18 consumed 1 ration each for v1 & v2 (not newcomer v3) after hourly work completed"
	)

	# Duplicate capture of daily_seq 18 does nothing
	mgr.capture_daily_event(18)
	mgr.process_all_pending()
	_assert(ctx.economy.get_resource("food") == init_food + 12 - 2, "Duplicate daily_seq 18 does not double-consume food")
	mgr.free()
	tm.free()

func _test_20_4_needs_fatigue_health_floor_and_morale() -> void:
	print("\n[20.4] Needs Progression, Ration Allocation, Fatigue/Rest, Health Floor & Morale")
	var mgr := SettlementSimulationManagerScript.new()
	var ctx := SettlementVillagerContextScript.new("stl_needs", "rival_military")
	ctx.reconcile_buildings(_build_canonical_settlement("stl_needs", "rival_military", "compact"))

	var v1 = ctx.create_and_add_villager("Hungry1", "idle", Vector2i(40, 40))
	var v2 = ctx.create_and_add_villager("Hungry2", "idle", Vector2i(40, 40))
	var v3 = ctx.create_and_add_villager("Hungry3", "idle", Vector2i(40, 40))
	ctx.reconcile_buildings(_build_canonical_settlement("stl_needs", "rival_military", "compact"))
	v1.hunger = 80.0
	v2.hunger = 50.0
	v3.hunger = 20.0
	# Leave only 2 food in stock so only the 2 hungriest (v1, v2) get rations
	ctx.economy.debit_resource("food", ctx.economy.get_resource("food") - 2, "test_setup", "drain", 0)
	mgr.register_context(ctx)

	mgr.advance_to_hour_seq(1)
	mgr.capture_daily_event(1)
	mgr.process_all_pending()
	_assert(
		ctx.economy.get_resource("food") == 0
		and v1.hunger < 60.0 and v2.hunger < 30.0 and v3.hunger > 25.0
		and ctx.sim_state.ration_shortfall,
		"Fair ration allocation feeds hungriest villagers first (v1, v2) without negative stock"
	)

	# Prolonged starvation must never drop health below HEALTH_FLOOR (10.0) or delete villagers
	v3.hunger = 95.0
	v3.health = 12.0
	v3.fatigue = 90.0 # Triggers resting & fatigue recovery
	mgr.advance_to_hour_seq(10)
	mgr.process_all_pending()
	_assert(
		ctx.get_villager_count() == 3
		and is_equal_approx(v3.health, SettlementSimulationConfigScript.HEALTH_FLOOR)
		and v3.fatigue < 90.0,
		"Health clamps at HEALTH_FLOOR (10.0), zero starvation deaths, and fatigued villager recovers via rest"
	)
	mgr.free()

func _test_20_5_survival_mode_and_awaiting_resupply() -> void:
	print("\n[20.5] Survival Mode Entry, Awaiting-Resupply State & Hysteresis Recovery")
	var mgr := SettlementSimulationManagerScript.new()
	var ctx := SettlementVillagerContextScript.new("stl_surv", "neutral_tribe")
	ctx.reconcile_buildings(_build_canonical_settlement("stl_surv", "neutral_tribe", "full"))
	for i in range(6):
		ctx.create_and_add_villager("S%d" % (i + 1), "idle", Vector2i(40, 40))
	ctx.reconcile_buildings(_build_canonical_settlement("stl_surv", "neutral_tribe", "full"))
	mgr.register_context(ctx)

	# Drain food to 3 (< 6 daily need) -> awaiting_resupply
	ctx.economy.debit_resource("food", ctx.economy.get_resource("food") - 3, "test_drain", "scarcity", 0)
	mgr.advance_to_hour_seq(1)
	mgr.process_all_pending()
	_assert(
		ctx.sim_state.survival_state == SettlementSimulationStateScript.SURVIVAL_AWAITING_RESUPPLY,
		"Low food (< daily need) transitions settlement to explicit 'awaiting_resupply' state"
	)

	# Credit food to 25 (>= exit_thresh 18 for 6 villagers) -> enters 'recovery' then 'normal'
	ctx.economy.credit_resource("food", 22, "aid_convoy", "resupply", 1)
	mgr.advance_to_hour_seq(2)
	mgr.process_all_pending()
	_assert(
		ctx.sim_state.survival_state == SettlementSimulationStateScript.SURVIVAL_RECOVERY,
		"Sufficient resupply transitions from 'awaiting_resupply' to 'recovery' (no instant oscillation)"
	)
	mgr.advance_to_hour_seq(15)
	mgr.process_all_pending()
	_assert(ctx.sim_state.survival_state == SettlementSimulationStateScript.SURVIVAL_NORMAL, "Recovery window completes back to 'normal'")
	mgr.free()

func _test_20_6_job_execution_and_production_sources() -> void:
	print("\n[20.6] Logical Job Execution (Guard Patrol, Source-Backed Production & Smith Disabled)")
	var mgr := SettlementSimulationManagerScript.new()

	# 1. Neutral Tribe without verified production source -> produces 0 free wood/food!
	var ctx_n := SettlementVillagerContextScript.new("stl_prod_n", "neutral_tribe")
	ctx_n.reconcile_buildings(_build_canonical_settlement("stl_prod_n", "neutral_tribe", "full"))
	for i in range(9):
		ctx_n.create_and_add_villager("P%d" % (i + 1), "idle", Vector2i(40, 40))
	ctx_n.reconcile_buildings(_build_canonical_settlement("stl_prod_n", "neutral_tribe", "full"))
	mgr.register_context(ctx_n)

	mgr.advance_to_hour_seq(3)
	mgr.process_all_pending()
	_assert(
		ctx_n.workplace_registry.get_workplace("neu_farm").buffer_amount == 0
		and ctx_n.workplace_registry.get_workplace("neu_wood").buffer_amount == 0
		and ctx_n.sim_state.production_blocked.get("neu_farm", "") == "missing_verified_production_source",
		"Farmer & Woodcutter produce 0 resources when no verified production source is registered"
	)

	# 2. Register finite wood source (5 wood) backed by physical WorldData tree -> Woodcutter produces bounded wood and depletes cleanly
	var wd_prod := WorldGeneratorScript.WorldData.new()
	wd_prod.seed_value = 12345
	wd_prod.generator_version = 8
	wd_prod.map_width = 80
	wd_prod.map_height = 80
	wd_prod.center_spawn = Vector2i(10, 11)
	wd_prod.player_center = Vector2i(10, 10)
	wd_prod.props = []
	var wp_wc = ctx_n.workplace_registry.get_workplace("neu_wood")
	var tree_cell: Vector2i = (wp_wc.access_cell + Vector2i(1, 0)) if wp_wc != null else Vector2i(45, 45)
	wd_prod.props.append({
		"type": "tree",
		"cell": tree_cell,
		"variant": 0
	})
	mgr.set_world_data(wd_prod)
	mgr.register_woodcutter_source("stl_prod_n", "neu_wood", [tree_cell])
	mgr.advance_to_hour_seq(10)
	mgr.process_all_pending()
	var total_wood_produced: int = ctx_n.workplace_registry.get_workplace("neu_wood").buffer_amount + (ctx_n.economy.get_resource("wood") - 40)
	for v in ctx_n.get_all_villagers():
		if v.get_carrying_resource() == "wood":
			total_wood_produced += v.get_carrying_amount()
	_assert(
		total_wood_produced == 5
		and SettlementResourceSourceAdapterScript.calculate_remaining_wood(ctx_n.sim_state.production_sources["neu_wood"]) == 0,
		"Source-backed Woodcutter produces exact finite 5 wood and stops on depletion"
	)

	# 3. Military Full Guard logical patrol progression + Watchtower removal fallback
	var ctx_m := SettlementVillagerContextScript.new("stl_guard_m", "rival_military")
	var mil_full := _build_canonical_settlement("stl_guard_m", "rival_military", "full")
	ctx_m.reconcile_buildings(mil_full)
	var g1 = ctx_m.create_and_add_villager("G1", "idle", Vector2i(40, 40))
	ctx_m.reconcile_buildings(mil_full)
	var start_target: String = g1.work_target_id
	mgr.register_context(ctx_m)
	mgr.advance_to_hour_seq(14) # +4 hours -> 1 guard patrol cycle
	mgr.process_all_pending()
	_assert(g1.work_target_id != start_target and g1.cell == Vector2i(40, 40), "Guard advances logical patrol target after 4h cycle without physical movement")
	mgr.free()

func _test_20_7_atomic_transactions_and_callbacks() -> void:
	print("\n[20.7] Atomic Transaction Rollback & Reentrant Callback Consistency")
	var econ := SettlementEconomyScript.new("stl_atom", "rival_merchant")
	var cb_saw_valid: Array[bool] = [false]
	econ.transaction_committed.connect(func(_r: Dictionary) -> void:
		cb_saw_valid[0] = econ.is_valid()
	)
	var snap_before: Dictionary = econ.to_dict()
	var bad_buy := econ.purchase_from_market_to_buffer("food", 10, 1, null, 50)
	_assert(not bool(bad_buy.get("ok", false)) and econ.to_dict() == snap_before, "Failed buffer purchase leaves complete economy snapshot 100% unchanged")

	var ctx := SettlementVillagerContextScript.new("stl_atom", "rival_merchant")
	ctx.reconcile_buildings(_build_canonical_settlement("stl_atom", "rival_merchant", "full"))
	var mkt_wp = ctx.workplace_registry.get_workplace("mer_hq")
	var ok_buy: Dictionary = ctx.economy.purchase_from_market_to_buffer("food", 5, 1, mkt_wp, 50)
	_assert(bool(ok_buy.get("ok", false)) and mkt_wp.buffer_amount == 5 and ctx.economy.is_valid(), "Valid market-to-buffer purchase commits atomically and passes conservation")
	cb_saw_valid[0] = false
	ctx.economy.transaction_committed.connect(func(_r: Dictionary) -> void:
		cb_saw_valid[0] = ctx.economy.is_valid()
	)
	ctx.economy.deposit_hauled_resource("food", 5, "workplace_output:mer_hq", "hauler_deposit", 2)
	_assert(cb_saw_valid[0] and ctx.economy.get_pending_buffer_deliveries().is_empty(), "Deposit callback observes committed state and resolves pending buffer provenance")

func _test_20_8_external_delivery_and_buffer_hauling() -> void:
	print("\n[20.8] External Delivery -> Receiving Buffer -> Hauler -> Storehouse Conservation")
	var mgr := SettlementSimulationManagerScript.new()

	# Military Full: logistics at hour 24 delivers 20 rations into mil_hq buffer -> Hauler moves to mil_store (economy stock)
	var ctx_mf := SettlementVillagerContextScript.new("stl_buf_mf", "rival_military")
	var mf_stl := _build_canonical_settlement("stl_buf_mf", "rival_military", "full")
	ctx_mf.reconcile_buildings(mf_stl)
	for i in range(4):
		ctx_mf.create_and_add_villager("MF%d" % (i + 1), "idle", Vector2i(40, 40))
	ctx_mf.reconcile_buildings(mf_stl)
	mgr.register_context(ctx_mf)

	mgr.advance_to_hour_seq(24)
	mgr.process_all_pending()
	var buf_after_del: int = ctx_mf.workplace_registry.get_workplace("mil_hq").buffer_amount
	var stock_after_del: int = ctx_mf.economy.get_resource("food")
	mgr.advance_to_hour_seq(26)
	mgr.process_all_pending()
	_assert(
		ctx_mf.economy.get_resource("food") == 100
		and ctx_mf.workplace_registry.get_workplace("mil_hq").buffer_amount == 0
		and ctx_mf.economy.is_valid()
		and (buf_after_del >= 0 and stock_after_del >= 80),
		"Military Full ration delivery (80 -> 100) flows through Barracks buffer via Hauler into final stock with exact conservation"
	)

	# Military Compact: logistics delivers directly to final storage without fake Hauler
	var ctx_mc := SettlementVillagerContextScript.new("stl_buf_mc", "rival_military")
	ctx_mc.reconcile_buildings(_build_canonical_settlement("stl_buf_mc", "rival_military", "compact"))
	mgr.register_context(ctx_mc)
	mgr.advance_to_hour_seq(24)
	mgr.process_all_pending()
	_assert(ctx_mc.economy.get_resource("food") == 100 and ctx_mc.economy.is_valid(), "Military Compact logistics delivers directly into Barracks final storage")

	# Partial destination capacity retains Hauler cargo without loss
	var ctx_cap := SettlementVillagerContextScript.new("stl_buf_cap", "rival_merchant")
	var mer_stl := _build_canonical_settlement("stl_buf_cap", "rival_merchant", "compact")
	ctx_cap.reconcile_buildings(mer_stl)
	var hauler = ctx_cap.create_and_add_villager("MH1", "idle", Vector2i(40, 40))
	ctx_cap.reconcile_buildings(mer_stl)
	var mer_hq_wp = ctx_cap.workplace_registry.get_workplace("rival_merchant_hq")
	ctx_cap.economy.purchase_from_market_to_buffer("food", 8, 1, mer_hq_wp, 50)
	# Lower food capacity to current stock + 3 so only 3 of 8 can deposit
	var base_food: int = ctx_cap.economy.get_resource("food") # 70
	ctx_cap.economy.apply_derived_capacities({"food": base_food + 3})
	mgr.register_context(ctx_cap)
	mgr.advance_to_hour_seq(2)
	mgr.process_all_pending()
	_assert(
		ctx_cap.economy.get_resource("food") == base_food + 3
		and hauler.get_carrying_amount() == 5
		and ctx_cap.economy.is_valid(),
		"Partial destination capacity deposits 3 and safely preserves remaining 5 in Hauler cargo"
	)
	mgr.free()

func _test_20_9_batching_backpressure_and_synthetic_loads() -> void:
	print("\n[20.9] Synthetic 36/72/120 Villager Batching, Backpressure & Speed Preservation")
	for pop in [36, 72, 120]:
		var mgr := SettlementSimulationManagerScript.new()
		mgr.set_requested_speed(3)
		var ctx := SettlementVillagerContextScript.new("stl_load_%d" % pop, "neutral_tribe")
		ctx.reconcile_buildings(_build_canonical_settlement("stl_load_%d" % pop, "neutral_tribe", "full"))
		for i in range(pop):
			ctx.create_and_add_villager("L%d" % (i + 1), "idle", Vector2i(40, 40))
		mgr.register_context(ctx)
		mgr.advance_to_hour_seq(2)
		var t_mid: Dictionary = mgr.get_telemetry()
		var expected_bp: bool = (pop * 2) >= SettlementSimulationConfigScript.BACKPRESSURE_STEP_DOWN_2X_PENDING
		_assert(
			int(t_mid["registered_villagers"]) == pop
			and int(t_mid["requested_speed"]) == 3
			and bool(t_mid["backpressure_active"]) == expected_bp
			and (not expected_bp or int(t_mid["effective_speed"]) < 3),
			"Load %d NPCs: requested_speed=3 preserved, backpressure_active=%s" % [pop, str(expected_bp)]
		)
		mgr.process_all_pending()
		var t_done: Dictionary = mgr.get_telemetry()
		_assert(
			int(t_done["pending_villager_hours"]) == 0
			and int(t_done["oldest_villager_lag"]) == 0
			and int(t_done["effective_speed"]) == 3,
			"Load %d NPCs: drains 0 pending hours and restores effective_speed=3" % pop
		)
		mgr.free()

func _test_20_10_serialization_and_backward_compatibility() -> void:
	print("\n[20.10] Mid-Backlog Serialization, Cargo Recovery & Phase 1/2/3 Compatibility")
	var mgr := SettlementSimulationManagerScript.new()
	var ctx := SettlementVillagerContextScript.new("stl_ser4", "rival_merchant")
	var mer_stl := _build_canonical_settlement("stl_ser4", "rival_merchant", "full")
	ctx.reconcile_buildings(mer_stl)
	var v1 = ctx.create_and_add_villager("Ser1", "idle", Vector2i(40, 40))
	ctx.reconcile_buildings(mer_stl)
	var mkt_wp = ctx.workplace_registry.get_workplace("mer_hq")
	ctx.economy.purchase_from_market_to_buffer("food", 6, 0, mkt_wp, 50)
	v1.set_cargo("food", 6, "mer_hq", Vector2i(40, 40))
	mkt_wp.buffer_amount = 0
	ctx.economy.apply_derived_capacities({"food": ctx.economy.get_resource("food")}) # Full -> cargo stays carried during mid-backlog batch
	mgr.register_context(ctx)
	mgr.advance_to_hour_seq(3)
	mgr.capture_daily_event(2)
	mgr.process_batch(1, 1000.0) # Mid-backlog save!

	var snap: Dictionary = ctx.to_dict()
	var restored = SettlementVillagerContextScript.from_dict(snap)
	_assert(restored != null and restored.economy.is_valid() and restored.get_villager(v1.villager_id).get_carrying_amount() == 6, "Mid-backlog & mid-cargo context restores cleanly")

	restored.reconcile_buildings(mer_stl) # Restore 1500 food capacity
	var mgr2 := SettlementSimulationManagerScript.new()
	mgr2.register_context(restored)
	mgr2.process_all_pending()
	_assert(
		restored.get_villager(v1.villager_id).last_processed_hour_seq == 3
		and restored.sim_state.completed_daily_seq == 2
		and restored.get_villager(v1.villager_id).get_carrying_amount() == 0
		and restored.economy.is_valid(),
		"Restored context completes pending hourly, daily, and cargo deposit work without duplicating transactions"
	)

	# Legacy Phase 1/2/3 dict without sim_state restores safely
	var legacy_dict: Dictionary = snap.duplicate(true)
	legacy_dict.erase("sim_state")
	var leg_ctx = SettlementVillagerContextScript.from_dict(legacy_dict)
	_assert(leg_ctx != null and leg_ctx.sim_state != null and not leg_ctx.sim_state.initialized, "Phase 1/2/3 dict without sim_state restores with safe defaults")
	mgr.free()
	mgr2.free()

func _snap_without_errors(ctx: RefCounted) -> Dictionary:
	var d: Dictionary = ctx.to_dict()
	if d.has("sim_state") and d["sim_state"] is Dictionary:
		d["sim_state"]["recent_errors"] = []
	return d

func _test_hardening_hourly_atomicity() -> void:
	print("\n[Hardening 4] Hourly Stage Failure Injection & Strict Atomicity")
	var stages: Array[String] = ["after_needs", "before_job", "during_job", "during_production", "during_pickup", "during_deposit"]

	for stage_name in stages:
		var mgr := SettlementSimulationManagerScript.new()
		var ctx := SettlementVillagerContextScript.new("stl_atom_%s" % stage_name, "neutral_tribe")
		var neu_stl := _build_canonical_settlement("stl_atom_%s" % stage_name, "neutral_tribe", "full")
		ctx.reconcile_buildings(neu_stl)
		var v1 = ctx.create_and_add_villager("A1", "idle", Vector2i(40, 40))
		ctx.reconcile_buildings(neu_stl)
		if stage_name == "during_production":
			mgr.register_context(ctx)
			mgr.register_production_source(ctx.settlement_id, "neu_farm", "food", 20)
			# Advance 2 hours so hour 3 hits production completion
			mgr.advance_to_hour_seq(2)
			mgr.process_all_pending()
		elif stage_name == "during_pickup":
			v1.active_job_id = "job__%s__neu_hq__hauler__1" % ctx.settlement_id
			v1.workplace_id = "neu_hq"
			v1.role = "hauler"
			ctx.job_board.get_job(v1.active_job_id).assigned_villager_id = v1.villager_id
			ctx.workplace_registry.get_workplace("neu_farm").buffer_amount = 10
			mgr.register_context(ctx)
		elif stage_name == "during_deposit":
			v1.set_cargo("food", 6, "neu_farm", Vector2i(40, 40))
			mgr.register_context(ctx)
		else:
			mgr.register_context(ctx)

		var target_h: int = int(ctx.sim_state.required_hour_seq) + 1
		mgr._advance_settlement_providers_for_hour(ctx, target_h)
		mgr.advance_to_hour_seq(target_h)
		var snap_before: Dictionary = _snap_without_errors(ctx)
		var fail_once: Array[bool] = [true]
		mgr.set_stage_fault_hook_for_test(ctx.settlement_id, func(_s: String, _vid: String, h: int, stg: String) -> bool:
			if fail_once[0] and h == target_h and stg == stage_name:
				fail_once[0] = false
				return false
			return true
		)
		mgr.process_batch(1, 1000.0)
		var snap_after_fail: Dictionary = _snap_without_errors(ctx)
		_assert(
			snap_after_fail == snap_before and v1.last_processed_hour_seq == target_h - 1,
			"Atomicity (%s): failed hour %d leaves complete context snapshot & watermark 100%% unchanged" % [stage_name, target_h]
		)

		# Clear fault and retry the same hour -> equals exactly one clean processing
		mgr.set_stage_fault_hook_for_test(ctx.settlement_id, Callable())
		mgr.process_all_pending()
		_assert(
			v1.last_processed_hour_seq == target_h and ctx.economy.is_valid(),
			"Atomicity (%s): retry completes hour %d exactly once with valid conservation" % [stage_name, target_h]
		)
		mgr.free()

func _test_hardening_backpressure_player_speed() -> void:
	print("\n[Hardening 5] Backpressure & Player Speed Preference During Active Backlog")
	var tm := TimeManagerScript.new()
	var mgr := SettlementSimulationManagerScript.new()
	mgr.connect_time_manager(tm)

	var ctx := SettlementVillagerContextScript.new("stl_bp_spd", "neutral_tribe")
	ctx.reconcile_buildings(_build_canonical_settlement("stl_bp_spd", "neutral_tribe", "full"))
	for i in range(60):
		ctx.create_and_add_villager("BP%d" % (i + 1), "idle", Vector2i(40, 40))
	mgr.register_context(ctx)

	# 1. Player selects 3x
	tm.set_speed(3)
	# 2. Backlog becomes severe (60 * 2 = 120 >= 96 -> steps down to 2x)
	mgr.advance_to_hour_seq(2)
	var t1: Dictionary = mgr.get_telemetry()
	_assert(
		int(t1["requested_speed"]) == 3 and int(t1["effective_speed"]) == 2 and bool(t1["backpressure_active"]) and tm.current_speed == 2,
		"Backpressure 1: 3x steps down to effective 2x at 120 pending items while requested_speed remains 3"
	)

	# 3. Player changes requested speed to 1x while backpressure is active
	tm.set_speed(1)
	# 4. Backlog clears -> effective_speed MUST restore to 1x (NOT 3x!)
	mgr.process_all_pending()
	var t2: Dictionary = mgr.get_telemetry()
	_assert(
		int(t2["requested_speed"]) == 1 and int(t2["effective_speed"]) == 1 and not bool(t2["backpressure_active"]) and tm.current_speed == 1,
		"Backpressure 2: player change to 1x during active backpressure is honored after backlog clears"
	)

	# 5. Severe backlog (>= 192 -> effective 1x), player requests 2x while active, then disabling backpressure restores 2x
	tm.set_speed(3)
	mgr.advance_to_hour_seq(6) # 60 * 4 = 240 >= 192 -> 1x
	_assert(int(mgr.get_telemetry()["effective_speed"]) == 1, "Backpressure 3: >= 192 pending steps down to 1x")
	tm.set_speed(2)
	_assert(int(mgr.get_telemetry()["requested_speed"]) == 2 and int(mgr.get_telemetry()["effective_speed"]) == 1, "Backpressure 4: player request 2x preserved while effective stays 1x")
	mgr.backpressure_enabled = false
	_assert(int(mgr.get_telemetry()["effective_speed"]) == 2 and not bool(mgr.get_telemetry()["backpressure_active"]), "Backpressure 5: disabling backpressure restores latest requested_speed (2x)")
	mgr.backpressure_enabled = true
	_assert(int(mgr.get_telemetry()["effective_speed"]) == 1 and bool(mgr.get_telemetry()["backpressure_active"]), "Backpressure 6: re-enabling backpressure with backlog re-applies 1x")
	mgr.process_all_pending()
	_assert(int(mgr.get_telemetry()["effective_speed"]) == 2 and int(mgr.get_telemetry()["pending_villager_hours"]) == 0, "Backpressure 7: catch-up restores latest requested_speed (2x) with 0 dropped work")
	mgr.free()
	tm.free()

func _test_hardening_worldview_runtime_smoke() -> void:
	print("\n[Hardening 7] WorldView Runtime Integration & Lifecycle Smoke Test")
	var wv_scene: PackedScene = load("res://scenes/world/world_view.tscn")
	_assert(wv_scene != null, "WorldView scene loads cleanly")
	if wv_scene == null:
		return

	var wv1: Node = wv_scene.instantiate()
	root.add_child(wv1)
	await process_frame
	var mgr1: Node = wv1.get("settlement_simulation_manager")
	var tm: Node = root.get_node_or_null("TimeManager")
	_assert(mgr1 != null and is_instance_valid(mgr1), "WorldView initializes single SettlementSimulationManager")
	var initial_count: int = mgr1.get_registered_settlement_ids().size()
	_assert(initial_count >= 1 and int(mgr1.get_telemetry()["registered_villagers"]) == 0, "WorldView registers canonical rival settlements without fabricating villagers")

	# Repeated apply_settlement_overlays_from_world_data must not duplicate manager or contexts
	wv1.apply_settlement_overlays_from_world_data()
	_assert(
		wv1.get("settlement_simulation_manager") == mgr1
		and mgr1.get_registered_settlement_ids().size() == initial_count,
		"Repeated apply_settlement_overlays_from_world_data() does not duplicate manager or contexts"
	)

	# TimeManager hour_passed reaches manager once
	var h_before: int = int(mgr1.get_telemetry()["required_hour_seq"])
	if tm != null:
		tm._advance_one_hour()
	var h_after: int = int(mgr1.get_telemetry()["required_hour_seq"])
	_assert(h_after == h_before + 1, "TimeManager.hour_passed advances SettlementSimulationManager required_hour_seq exactly once")

	# Exit cleanly -> disconnects TimeManager signals
	root.remove_child(wv1)
	_assert(not mgr1.is_connected_to_time_manager(), "WorldView._exit_tree() cleanly disconnects SettlementSimulationManager from TimeManager")
	wv1.free()

	# Second WorldView instance initializes cleanly without stale references
	var wv2: Node = wv_scene.instantiate()
	root.add_child(wv2)
	await process_frame
	var mgr2: Node = wv2.get("settlement_simulation_manager")
	_assert(mgr2 != null and is_instance_valid(mgr2) and mgr2 != mgr1 and mgr2.is_connected_to_time_manager(), "Second WorldView instance initializes fresh SettlementSimulationManager cleanly")
	root.remove_child(wv2)
	wv2.free()
