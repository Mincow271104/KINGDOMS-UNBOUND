extends SceneTree
## Phase 5 Automated Test Suite: Population Growth & Immigration
## Covers Eligibility, Determinism, Identity & Registration, Daily Scheduling & Backlog,
## Economy & Player/NPC Isolation, and Serialization Compatibility.

const SettlementDataScript = preload("res://scripts/world/settlement_data.gd")
const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementVillagerContextScript = preload("res://scripts/world/settlement_villager_context.gd")
const SettlementEconomyScript = preload("res://scripts/world/settlement_economy.gd")
const SettlementSimulationConfigScript = preload("res://scripts/world/settlement_simulation_config.gd")
const SettlementSimulationStateScript = preload("res://scripts/world/settlement_simulation_state.gd")
const SettlementSimulationManagerScript = preload("res://scripts/world/settlement_simulation_manager.gd")
const SettlementImmigrationPolicyScript = preload("res://scripts/world/settlement_immigration_policy.gd")
const SettlementImmigrationServiceScript = preload("res://scripts/world/settlement_immigration_service.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const SettlementGeneratorScript = preload("res://scripts/world/settlement_generator.gd")
const TimeManagerScript = preload("res://scripts/core/time_manager.gd")

var _passed: int = 0
var _failed: int = 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] %s" % msg)
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)

func _make_eligible_context(
	sid: String = "stl_alpha",
	faction_id: String = "faction_tribe",
	house_count: int = 1,
	initial_villagers: int = 1
) -> RefCounted:
	var ctx := SettlementVillagerContextScript.new(sid, faction_id, faction_id, 1, true)
	var stl := SettlementDataScript.new(sid, faction_id, faction_id, SettlementDataScript.ROLE_VILLAGE, Vector2i(20, 20))
	var buildings: Array[Dictionary] = [
		{"id": "%s_th" % sid, "type": "townhall", "cell": Vector2i(20, 20), "size": Vector2i(2, 2), "role": "hq", "blocking": true}
	]
	for i in range(house_count):
		buildings.append({
			"id": "%s_house_%d" % [sid, i + 1],
			"type": "house",
			"cell": Vector2i(23 + i * 2, 20),
			"size": Vector2i(2, 2),
			"role": "residential",
			"blocking": true
		})
	stl.buildings = buildings
	ctx.reconcile_buildings(stl)
	for i in range(initial_villagers):
		ctx.create_and_add_villager("Starter %d" % (i + 1), SettlementVillagerDataScript.ROLE_IDLE, Vector2i(20, 20))
	return ctx

func _make_settlement_data(sid: String, faction_id: String, status: String = SettlementDataScript.STATUS_ACTIVE) -> RefCounted:
	var stl := SettlementDataScript.new(sid, faction_id, faction_id, SettlementDataScript.ROLE_VILLAGE, Vector2i(20, 20))
	stl.status = status
	return stl

func _drain_food_to(ctx: RefCounted, target_food: int) -> void:
	var cur: int = int(ctx.economy.get_resource(EconomyConfigScript.RES_FOOD))
	if cur > target_food:
		ctx.economy.debit_resource(EconomyConfigScript.RES_FOOD, cur - target_food, "test_drain", "test_setup", 0)
	elif cur < target_food:
		ctx.economy.credit_resource(EconomyConfigScript.RES_FOOD, target_food - cur, "test_seed", "test_setup", 0)

func _drain_non_food_economy(ctx: RefCounted) -> void:
	var all_res: Dictionary = ctx.economy.get_all_resources()
	for r in all_res.keys():
		var r_str: String = String(r)
		if r_str == EconomyConfigScript.RES_FOOD or r_str == EconomyConfigScript.RES_RAW_MEAT:
			continue
		var amt: int = int(all_res[r])
		if amt > 0:
			ctx.economy.debit_resource(r_str, amt, "test_drain", "test_setup", 0)
	var g: int = int(ctx.economy.get_gold())
	if g > 0:
		ctx.economy.debit_gold(g, "test_drain", "test_setup", 0)

func _run_eligibility_tests() -> void:
	print("\n[Category A] Immigration Eligibility Gates")
	var policy := SettlementImmigrationPolicyScript.new()
	policy.daily_admission_probability = 1.0
	var svc := SettlementImmigrationServiceScript.new(policy)

	# A1: Settlement with available housing passes housing gate
	var ctx_ok := _make_eligible_context("stl_a1", "neutral_tribe", 1, 1)
	var elig_ok: Dictionary = policy.evaluate_eligibility(ctx_ok)
	_assert(bool(elig_ok["eligible"]) and bool(elig_ok["housing"]["ok"]), "A1: Eligible settlement passes all 4 gates including housing")

	# A2: Settlement without housing capacity is rejected
	var ctx_no_house := _make_eligible_context("stl_a2", "neutral_tribe", 0, 0)
	# townhall gives compact baseline 4; fill all 4 slots
	for i in range(4):
		ctx_no_house.create_and_add_villager("Cap %d" % i)
	var elig_full: Dictionary = policy.evaluate_eligibility(ctx_no_house)
	_assert(not bool(elig_full["eligible"]) and not bool(elig_full["housing"]["ok"]), "A2a: Settlement at housing capacity is rejected")
	_assert(String(elig_full["rejection_reason"]) == "at_housing_capacity", "A2b: Rejection reason is at_housing_capacity")

	var ctx_zero_cap := SettlementVillagerContextScript.new("stl_a2z", "neutral_tribe", "neutral_tribe", 1, true)
	var elig_zero: Dictionary = policy.evaluate_eligibility(ctx_zero_cap)
	_assert(not bool(elig_zero["eligible"]) and String(elig_zero["rejection_reason"]) == "no_housing_capacity", "A2c: Zero housing capacity is rejected")

	# A3 & A4: Food below threshold rejected; raw_meat NEVER satisfies food requirement
	var ctx_meat := _make_eligible_context("stl_a3", "neutral_tribe", 1, 1)
	_drain_food_to(ctx_meat, 2)
	ctx_meat.economy.credit_resource(EconomyConfigScript.RES_RAW_MEAT, 150, "test_hunt", "test_setup", 0)
	var elig_meat: Dictionary = policy.evaluate_eligibility(ctx_meat)
	_assert(not bool(elig_meat["eligible"]) and not bool(elig_meat["food"]["ok"]), "A3/A4: Low food with 150 raw_meat is rejected by food gate")
	_assert(String(elig_meat["rejection_reason"]) == "insufficient_food_reserve", "A4b: Rejection reason is insufficient_food_reserve")

	# A5: Sufficient local food passes food gate
	_drain_food_to(ctx_meat, 30)
	var elig_food_ok: Dictionary = policy.evaluate_eligibility(ctx_meat)
	_assert(bool(elig_food_ok["eligible"]) and bool(elig_food_ok["food"]["ok"]), "A5: Sufficient local food passes food gate")

	# A6: Insufficient local economic capacity rejected (GDD §11.1 valuation, no heterogeneous raw-unit sum)
	var ctx_poor := _make_eligible_context("stl_a6", "neutral_tribe", 1, 1)
	_drain_non_food_economy(ctx_poor)
	var elig_poor: Dictionary = policy.evaluate_eligibility(ctx_poor)
	_assert(not bool(elig_poor["eligible"]) and bool(elig_poor["food"]["ok"]) and not bool(elig_poor["economy"]["ok"]), "A6: Insufficient local economy rejected while food passes")
	_assert(String(elig_poor["rejection_reason"]) == "insufficient_economic_capacity", "A6b: Rejection reason is insufficient_economic_capacity")

	# A6c: Heterogeneous valuation checks (10 wood = 30 < 60 fails; 5 tools = 75 >= 60 passes; 100 raw_meat = 0 fails)
	ctx_poor.economy.credit_resource(EconomyConfigScript.RES_WOOD, 10, "test_seed", "test_setup", 0)
	ctx_poor.economy.credit_resource(EconomyConfigScript.RES_RAW_MEAT, 100, "test_seed", "test_setup", 0)
	var elig_wood10: Dictionary = policy.evaluate_eligibility(ctx_poor)
	_assert(not bool(elig_wood10["economy"]["ok"]) and int(elig_wood10["economy"]["economic_value"]) == 30, "A6c: 10 wood (value 30) + 100 unpriced raw_meat (value 0) < 60 fails economy gate")
	ctx_poor.economy.credit_resource(EconomyConfigScript.RES_TOOLS, 5, "test_seed", "test_setup", 0)
	var elig_tools5: Dictionary = policy.evaluate_eligibility(ctx_poor)
	_assert(bool(elig_tools5["economy"]["ok"]) and int(elig_tools5["economy"]["economic_value"]) == 105, "A6d: Adding 5 tools (+75 = 105 gold-eq) passes economy gate")
	_drain_non_food_economy(ctx_poor)

	# A6e: Tribe, Military, and Merchant default endowments all pass economy gate
	var ctx_mil := _make_eligible_context("stl_a6m", "rival_military", 1, 1)
	var ctx_mer := _make_eligible_context("stl_a6r", "rival_merchant", 1, 1)
	_assert(bool(policy.evaluate_eligibility(ctx_mil)["economy"]["ok"]) and bool(policy.evaluate_eligibility(ctx_mer)["economy"]["ok"]), "A6e: Military and Merchant default endowments pass canonical economic valuation")

	# A7: Insufficient stability rejected (survival mode, ration shortfall, low morale, inactive status, isolated)
	var ctx_stab := _make_eligible_context("stl_a7", "neutral_tribe", 1, 1)
	ctx_stab.sim_state.survival_state = SettlementSimulationStateScript.SURVIVAL_SURVIVAL
	var elig_surv: Dictionary = policy.evaluate_eligibility(ctx_stab)
	_assert(not bool(elig_surv["eligible"]) and not bool(elig_surv["stability"]["ok"]), "A7a: SURVIVAL_SURVIVAL rejects stability gate")

	ctx_stab.sim_state.survival_state = SettlementSimulationStateScript.SURVIVAL_NORMAL
	ctx_stab.sim_state.ration_shortfall = true
	var elig_short: Dictionary = policy.evaluate_eligibility(ctx_stab)
	_assert(not bool(elig_short["eligible"]) and String(elig_short["rejection_reason"]) == "active_ration_shortfall", "A7b: Active ration shortfall rejects stability gate")

	ctx_stab.sim_state.ration_shortfall = false
	ctx_stab.get_all_villagers()[0].morale = 20.0
	var elig_morale: Dictionary = policy.evaluate_eligibility(ctx_stab)
	_assert(not bool(elig_morale["eligible"]) and String(elig_morale["rejection_reason"]) == "low_villager_morale", "A7c: Low villager morale rejects stability gate")

	ctx_stab.get_all_villagers()[0].morale = 75.0
	var stl_abandoned := _make_settlement_data("stl_a7", "neutral_tribe", SettlementDataScript.STATUS_ABANDONED)
	var elig_aband: Dictionary = policy.evaluate_eligibility(ctx_stab, stl_abandoned)
	_assert(not bool(elig_aband["eligible"]) and String(elig_aband["rejection_reason"]) == "settlement_not_active", "A7d: Non-active settlement status rejects stability gate")

	var elig_iso: Dictionary = policy.evaluate_eligibility(ctx_stab, null, true)
	_assert(not bool(elig_iso["eligible"]) and String(elig_iso["rejection_reason"]) == "settlement_isolated", "A7e: Isolated settlement rejects stability gate")

	# A7f: Empty active settlement has morale_measured=false, avg_morale=null (no synthetic 70.0), and is founding-eligible
	var ctx_empty := _make_eligible_context("stl_a7_empty", "neutral_tribe", 1, 0)
	var elig_empty: Dictionary = policy.evaluate_eligibility(ctx_empty)
	_assert(
		bool(elig_empty["eligible"]) and bool(elig_empty["stability"]["ok"]) and not bool(elig_empty["stability"]["morale_measured"]) and elig_empty["stability"]["avg_morale"] == null and String(elig_empty["stability"]["reason"]) == "ok_unpopulated_active",
		"A7f: Empty active settlement is founding-eligible without synthetic morale (morale_measured=false, avg_morale=null)"
	)
	ctx_empty.sim_state.survival_state = "invalid_state"
	var elig_bad_surv: Dictionary = policy.evaluate_eligibility(ctx_empty)
	_assert(not bool(elig_bad_surv["eligible"]) and String(elig_bad_surv["rejection_reason"]) == "invalid_survival_state", "A7g: Invalid survival_state fails closed")

	# A8: Missing/invalid info fails closed
	var elig_null: Dictionary = policy.evaluate_eligibility(null)
	_assert(not bool(elig_null["eligible"]) and String(elig_null["rejection_reason"]) == "invalid_context", "A8a: Null context fails closed")
	var ctx_no_sim := _make_eligible_context("stl_a8", "neutral_tribe", 1, 1)
	ctx_no_sim.sim_state = null
	var elig_nosim: Dictionary = policy.evaluate_eligibility(ctx_no_sim)
	_assert(not bool(elig_nosim["eligible"]) and String(elig_nosim["rejection_reason"]) == "missing_sim_state", "A8b: Missing sim_state fails closed")

	# A9: Rejected settlement undergoes zero partial mutations
	var before_count: int = ctx_poor.get_villager_count()
	var before_seq: int = ctx_poor.get_next_sequence()
	var res_fail: Dictionary = svc.process_daily_immigration(ctx_poor, 12345, 24)
	_assert(int(res_fail["admitted"]) == 0 and ctx_poor.get_villager_count() == before_count and ctx_poor.get_next_sequence() == before_seq, "A9: Failed admission leaves zero partial villager/ID mutations")

func _run_determinism_tests() -> void:
	print("\n[Category B] Determinism & Seeded RNG")
	var policy := SettlementImmigrationPolicyScript.new()
	policy.daily_admission_probability = 0.5

	# B1: Identical inputs produce identical decisions and rolls
	var ctx1 := _make_eligible_context("stl_det", "neutral_tribe", 2, 1)
	var ctx2 := _make_eligible_context("stl_det", "neutral_tribe", 2, 1)
	var svc1 := SettlementImmigrationServiceScript.new(policy)
	var svc2 := SettlementImmigrationServiceScript.new(policy)
	var r1: Dictionary = svc1.process_daily_immigration(ctx1, 99991, 24)
	var r2: Dictionary = svc2.process_daily_immigration(ctx2, 99991, 24)
	_assert(is_equal_approx(float(r1.get("roll", -1.0)), float(r2.get("roll", -2.0))) and int(r1["admitted"]) == int(r2["admitted"]), "B1: Identical seed/settlement/day produces identical roll and admission decision")

	# B2: Different settlement IDs are independently evaluated
	var s_a: int = SettlementImmigrationServiceScript.derive_deterministic_seed(99991, "stl_alpha", 24)
	var s_b: int = SettlementImmigrationServiceScript.derive_deterministic_seed(99991, "stl_beta", 24)
	_assert(s_a != s_b, "B2: Different settlement IDs derive distinct deterministic seeds")

	# B3: Different simulation days derive distinct deterministic seeds
	var s_d1: int = SettlementImmigrationServiceScript.derive_deterministic_seed(99991, "stl_alpha", 24)
	var s_d2: int = SettlementImmigrationServiceScript.derive_deterministic_seed(99991, "stl_alpha", 48)
	_assert(s_d1 != s_d2, "B3: Different simulation days derive distinct deterministic seeds")

	# B4: Global RNG activity does not influence immigration decisions
	randomize()
	for _i in range(25):
		var _discard := randi()
	var ctx3 := _make_eligible_context("stl_det", "neutral_tribe", 2, 1)
	var r3: Dictionary = SettlementImmigrationServiceScript.new(policy).process_daily_immigration(ctx3, 99991, 24)
	_assert(is_equal_approx(float(r1.get("roll", -1.0)), float(r3.get("roll", -2.0))) and int(r1["admitted"]) == int(r3["admitted"]), "B4: Global RNG activity does not alter immigration roll")

	# B5: Processing order (A then B vs B then A) does not alter decisions
	var ctx_a1 := _make_eligible_context("stl_ord_a", "neutral_tribe", 2, 1)
	var ctx_b1 := _make_eligible_context("stl_ord_b", "rival_merchant", 2, 1)
	var ctx_a2 := _make_eligible_context("stl_ord_a", "neutral_tribe", 2, 1)
	var ctx_b2 := _make_eligible_context("stl_ord_b", "rival_merchant", 2, 1)
	var ra1: Dictionary = svc1.process_daily_immigration(ctx_a1, 7777, 24)
	var rb1: Dictionary = svc1.process_daily_immigration(ctx_b1, 7777, 24)
	var rb2: Dictionary = svc2.process_daily_immigration(ctx_b2, 7777, 24)
	var ra2: Dictionary = svc2.process_daily_immigration(ctx_a2, 7777, 24)
	_assert(is_equal_approx(float(ra1["roll"]), float(ra2["roll"])) and is_equal_approx(float(rb1["roll"]), float(rb2["roll"])), "B5: Settlement processing order does not affect any settlement's roll")

	# B6: Repeating an already processed day cannot create another admission
	var r_repeat: Dictionary = svc1.process_daily_immigration(ctx1, 99991, 24)
	_assert(int(r_repeat["admitted"]) == 0 and String(r_repeat["rejection_reason"]) == "already_evaluated_for_day", "B6: Repeating same daily_seq is idempotent and rejected")

func _run_identity_and_registration_tests() -> void:
	print("\n[Category C] Identity, Registration & Job Lifecycle")
	var policy := SettlementImmigrationPolicyScript.new()
	policy.daily_admission_probability = 1.0
	var svc := SettlementImmigrationServiceScript.new(policy)

	var ctx_a := _make_eligible_context("stl_id_a", "neutral_tribe", 1, 1)
	var ctx_b := _make_eligible_context("stl_id_b", "rival_military", 1, 1)

	# Add a workplace with 1 open slot to ctx_a (1 farm slot, starter is idle -> starter or newcomer gets it)
	var stl_a := SettlementDataScript.new("stl_id_a", "neutral_tribe", "neutral_tribe", SettlementDataScript.ROLE_VILLAGE, Vector2i(20, 20))
	stl_a.buildings = [
		{"id": "a_th", "type": "townhall", "cell": Vector2i(20, 20), "size": Vector2i(2, 2), "role": "hq", "blocking": true},
		{"id": "a_h1", "type": "house", "cell": Vector2i(23, 20), "size": Vector2i(2, 2), "role": "residential", "blocking": true},
		{"id": "a_farm", "type": "farm", "cell": Vector2i(26, 20), "size": Vector2i(2, 2), "role": "production", "blocking": true, "worker_quota": 1}
	]
	ctx_a.reconcile_buildings(stl_a)
	var existing_v = ctx_a.get_all_villagers()[0]
	var existing_id_before: String = existing_v.villager_id

	var admitted_signals: Array = []
	svc.villager_admitted.connect(func(sid: String, vid: String, d_seq: int) -> void:
		admitted_signals.append({"sid": sid, "vid": vid, "d_seq": d_seq})
	)

	var res_a: Dictionary = svc.process_daily_immigration(ctx_a, 12345, 24, stl_a)
	var res_b: Dictionary = svc.process_daily_immigration(ctx_b, 12345, 24)
	_assert(bool(res_a["ok"]) and int(res_a["admitted"]) == 1, "C1: Settlement A admits exactly 1 villager")
	_assert(bool(res_b["ok"]) and int(res_b["admitted"]) == 1, "C2: Settlement B admits exactly 1 villager")

	var new_id_a: String = String(res_a["admitted_ids"][0])
	var new_id_b: String = String(res_b["admitted_ids"][0])
	_assert(new_id_a != existing_id_before and new_id_a != new_id_b, "C3: New villager IDs are unique across residents and settlements")
	_assert(ctx_a.has_villager(new_id_a) and not ctx_b.has_villager(new_id_a), "C4: Newcomer belongs exclusively to Settlement A")

	var new_v_a = ctx_a.get_villager(new_id_a)
	_assert(new_v_a != null and new_v_a.is_valid() and new_v_a.settlement_id == "stl_id_a", "C5: Newcomer is valid canonical SettlementVillagerData")
	_assert(new_v_a.admission_hour_seq == 24 and new_v_a.last_processed_hour_seq == 24, "C6: Newcomer stamped with admission_hour_seq=24 and last_processed_hour_seq=24")
	_assert(ctx_a.get_villager_count() == 2 and ctx_a.sim_state.total_immigrants_admitted == 1, "C7: Derived resident count (2) and admitted total (1) updated")
	_assert(admitted_signals.size() == 2, "C8: villager_admitted signal emitted post-commit for both admissions")

	# Verify workplace quota (1) is not exceeded even with 2 villagers
	var integrity: Dictionary = ctx_a.verify_assignment_integrity()
	_assert(bool(integrity.get("ok", false)), "C9: Job assignment integrity preserved without exceeding workplace slots")

func _run_scheduling_and_backlog_tests() -> void:
	print("\n[Category D] Daily Scheduling, Backlog & Retroactive Protection")
	var mgr := SettlementSimulationManagerScript.new()
	var policy := SettlementImmigrationPolicyScript.new()
	policy.daily_admission_probability = 1.0
	policy.max_admissions_per_day = 1
	mgr.set_world_seed(424242)
	mgr.set_immigration_policy(policy)

	var ctx := _make_eligible_context("stl_sched", "neutral_tribe", 2, 1)
	var starter = ctx.get_all_villagers()[0]
	mgr.register_context(ctx)

	# D1/D2: Hourly ticks before daily boundary do NOT trigger immigration
	mgr.advance_to_hour_seq(12)
	mgr.process_all_pending()
	_assert(ctx.get_villager_count() == 1 and ctx.sim_state.last_immigration_daily_seq == -1, "D1: 12 hourly ticks without daily event do not trigger immigration")

	# D3/D4/D5/D6: Multi-day backlog (Day 1 @ 24, Day 2 @ 48, Day 3 @ 72)
	mgr.advance_to_hour_seq(72)
	mgr.capture_daily_event(24)
	mgr.capture_daily_event(48)
	mgr.capture_daily_event(72)
	# Duplicate capture of 24 must be ignored
	mgr.capture_daily_event(24)
	mgr.process_all_pending()

	_assert(ctx.get_villager_count() == 4, "D2: 3-day backlog admits 1/day (1 starter + 3 newcomers = 4)")
	_assert(ctx.sim_state.total_immigrants_admitted == 3, "D3: total_immigrants_admitted == 3 after 3 daily boundaries")
	_assert(ctx.sim_state.completed_daily_seq == 72 and ctx.sim_state.last_immigration_daily_seq == 72, "D4: Daily watermarks advanced to 72")

	var all_v: Array = ctx.get_all_villagers()
	var imm1 = all_v[1] # Admitted at h=24
	var imm2 = all_v[2] # Admitted at h=48
	var imm3 = all_v[3] # Admitted at h=72
	_assert(imm1.admission_hour_seq == 24 and imm1.last_processed_hour_seq == 72, "D5a: Day 1 immigrant admitted at 24 and simulated through 72")
	_assert(imm2.admission_hour_seq == 48 and imm2.last_processed_hour_seq == 72, "D5b: Day 2 immigrant admitted at 48 and simulated through 72")
	_assert(imm3.admission_hour_seq == 72 and imm3.last_processed_hour_seq == 72, "D5c: Day 3 immigrant admitted at 72 and NOT retroactively simulated")

	# Verify exact ration count (no retroactive rations!):
	# Starter ate at 24, 48, 72 (3 rations).
	# imm1 ate at 48, 72 (2 rations, NOT 24).
	# imm2 ate at 72 (1 ration, NOT 24 or 48).
	# imm3 ate 0 rations (admitted at 72).
	# Total rations debited = 3 + 2 + 1 + 0 = 6!
	var total_rations: int = int(ctx.economy.ledger.get_total_outflow(EconomyConfigScript.RES_FOOD))
	_assert(total_rations == 6, "D6: Exact non-retroactive ration count (3 + 2 + 1 + 0 = 6, got %d)" % total_rations)

	# Verify imm3 becomes eligible for future ticks (hour 73)
	mgr.advance_to_hour_seq(73)
	mgr.process_all_pending()
	_assert(imm3.last_processed_hour_seq == 73, "D7: Day 3 immigrant participates normally in future hour 73")

	# D8: Repeated processing of already processed day does not duplicate residents
	mgr.capture_daily_event(72)
	mgr.process_all_pending()
	_assert(ctx.get_villager_count() == 4, "D8: Re-capturing already processed day 72 does not duplicate residents")

	# D9: TimeManager integration test
	var tm := TimeManagerScript.new()
	var mgr_tm := SettlementSimulationManagerScript.new()
	mgr_tm.set_immigration_policy(policy)
	var ctx_tm := _make_eligible_context("stl_tm", "neutral_tribe", 1, 1)
	mgr_tm.register_context(ctx_tm)
	mgr_tm.connect_time_manager(tm)
	for _h in range(24):
		tm._advance_one_hour()
	mgr_tm.process_all_pending()
	_assert(ctx_tm.get_villager_count() == 2, "D9: TimeManager 24h day_passed triggers exactly 1 admission")
	mgr_tm.disconnect_time_manager()
	mgr.free()
	mgr_tm.free()
	tm.free()

func _run_economy_isolation_and_serialization_tests() -> void:
	print("\n[Category E] Economy, Isolation & Persistence Compatibility")
	var policy := SettlementImmigrationPolicyScript.new()
	policy.daily_admission_probability = 1.0
	var svc := SettlementImmigrationServiceScript.new(policy)

	var ctx_a := _make_eligible_context("stl_iso_a", "neutral_tribe", 1, 1)
	var ctx_b := _make_eligible_context("stl_iso_b", "rival_merchant", 1, 1)

	var food_before_a: int = int(ctx_a.economy.get_resource(EconomyConfigScript.RES_FOOD))
	var meat_before_a: int = int(ctx_a.economy.get_resource(EconomyConfigScript.RES_RAW_MEAT))
	var gold_before_a: int = int(ctx_a.economy.get_gold())
	var food_before_b: int = int(ctx_b.economy.get_resource(EconomyConfigScript.RES_FOOD))
	var gold_before_b: int = int(ctx_b.economy.get_gold())
	var count_before_b: int = ctx_b.get_villager_count()

	var res: Dictionary = svc.process_daily_immigration(ctx_a, 12345, 24)
	_assert(int(res["admitted"]) == 1, "E1: Settlement A admitted 1 immigrant")
	_assert(int(ctx_a.economy.get_resource(EconomyConfigScript.RES_FOOD)) == food_before_a, "E2: Admission creates/deletes 0 food")
	_assert(int(ctx_a.economy.get_resource(EconomyConfigScript.RES_RAW_MEAT)) == meat_before_a, "E3: Admission leaves raw_meat untouched")
	_assert(int(ctx_a.economy.get_gold()) == gold_before_a, "E4: Admission leaves local gold untouched")
	_assert(int(ctx_b.economy.get_resource(EconomyConfigScript.RES_FOOD)) == food_before_b and int(ctx_b.economy.get_gold()) == gold_before_b and ctx_b.get_villager_count() == count_before_b, "E5: Settlement B context & economy untouched by Settlement A immigration")

	# E6: Serialization round-trip & backward compatibility
	var ctx_dict: Dictionary = ctx_a.to_dict()
	var ctx_restored = SettlementVillagerContextScript.from_dict(ctx_dict)
	_assert(ctx_restored != null and ctx_restored.get_villager_count() == 2, "E6a: Context round-trip preserves admitted villagers")
	_assert(ctx_restored.sim_state.last_immigration_daily_seq == 24 and ctx_restored.sim_state.total_immigrants_admitted == 1, "E6b: SimulationState round-trip preserves immigration watermarks")
	var new_vid: String = String(res["admitted_ids"][0])
	var rest_v = ctx_restored.get_villager(new_vid)
	_assert(rest_v != null and rest_v.admission_hour_seq == 24, "E6c: VillagerData round-trip preserves admission_hour_seq")

	# Backward compatibility with Phase 4 dict missing Phase 5 fields
	var legacy_state_dict: Dictionary = ctx_a.sim_state.to_dict()
	legacy_state_dict.erase("last_immigration_daily_seq")
	legacy_state_dict.erase("total_immigrants_admitted")
	var legacy_state = SettlementSimulationStateScript.from_dict(legacy_state_dict)
	_assert(legacy_state != null and legacy_state.last_immigration_daily_seq == -1 and legacy_state.total_immigrants_admitted == 0, "E6d: Phase 4 sim_state dict without Phase 5 fields loads cleanly")

func _run_phase4_f1_integration_test() -> void:
	print("\n[Category F] Phase 4/F1 Production Integration (Default Immigration Config)")
	var mgr := SettlementSimulationManagerScript.new()
	_assert(mgr.is_immigration_enabled(), "F1: Immigration is enabled by default on SettlementSimulationManager")

	# Find a deterministic world_seed where default policy (p=0.5) admits on Day 1 (hour_seq=18)
	var sid := "stl_f1_integ"
	var chosen_seed: int = 12345
	for cand_seed in range(1, 50):
		var rng := RandomNumberGenerator.new()
		rng.seed = SettlementImmigrationServiceScript.derive_deterministic_seed(cand_seed, sid, 18, 0)
		if rng.randf() < SettlementImmigrationPolicyScript.DEFAULT_DAILY_ADMISSION_PROBABILITY:
			chosen_seed = cand_seed
			break
	mgr.set_world_seed(chosen_seed)

	var layout: Dictionary = SettlementGeneratorScript._build_layout_template("neutral_tribe", Vector2i(40, 40), "full")
	var stl := SettlementDataScript.new(sid, "neutral_tribe", "neutral_tribe", SettlementDataScript.ROLE_VILLAGE, Vector2i(40, 40))
	for b in layout.get("buildings", []):
		stl.buildings.append((b as Dictionary).duplicate(true))

	var ctx := SettlementVillagerContextScript.new(sid, "neutral_tribe")
	var vf1 = ctx.create_and_add_villager("Starter Farmer", SettlementVillagerDataScript.ROLE_IDLE, Vector2i(40, 40))
	vf1.last_processed_hour_seq = -1
	ctx.reconcile_buildings(stl)

	var tm := TimeManagerScript.new()
	mgr.connect_time_manager(tm)
	mgr.register_context(ctx)
	mgr.register_farm_source(sid, "neu_farm")

	# Day 1 (hours 0..23): day_passed fires at hour 18 (midnight), admitting newcomer imm1
	mgr.advance_to_hour_seq(0)
	mgr.process_all_pending()
	for _h in range(23):
		tm._advance_one_hour()
		mgr.process_all_pending()

	_assert(ctx.get_villager_count() == 2, "F2: Eligible canonical settlement admits 1 newcomer under default immigration config")
	var villagers: Array = ctx.get_all_villagers()
	var imm1 = villagers[1]
	_assert(imm1.admission_hour_seq == 18 and imm1.last_processed_hour_seq == 23, "F3: Newcomer admitted at hour 18, never processed for 0..17, and simulated through 23")
	_assert(imm1.role == SettlementVillagerDataScript.ROLE_FARMER and imm1.active_job_id != vf1.active_job_id and not imm1.active_job_id.is_empty(), "F4: Newcomer assigned via Phase 3 job lifecycle to distinct Farm slot")
	_assert(bool(ctx.verify_assignment_integrity().get("ok", false)), "F5: Phase 3 assignment integrity verified with no duplicate assignments")

	var farm_wp = ctx.workplace_registry.get_workplace("neu_farm")
	var farm_src: Dictionary = ctx.sim_state.production_sources["neu_farm"]
	_assert(farm_wp.buffer_amount == 5 and int(farm_src["total_produced"]) == 5, "F6: Day 1 Farm output remains exact 5 Food (no retroactive newcomer production)")

	# Day 2 (hours 24..41, up to 23:00 Day 2 before Day 3 midnight/dawn): both starter and newcomer participate, obeying F1 daily cap (5 Food/day)
	for _h in range(18):
		tm._advance_one_hour()
		mgr.process_all_pending()

	_assert(int(farm_src["daily_produced_milli"]) == 10000 and int(farm_src["total_produced"]) == 15, "F7: Day 2 with 2 Farmers obeys F1 daily cap (2 * 5 = 10 Food/day, total=15)")
	mgr.disconnect_time_manager()
	mgr.free()
	tm.free()

func _init() -> void:
	print("========================================================")
	print("  TEST SUITE: Phase 5 Population Growth & Immigration")
	print("========================================================")

	_run_eligibility_tests()
	_run_determinism_tests()
	_run_identity_and_registration_tests()
	_run_scheduling_and_backlog_tests()
	_run_economy_isolation_and_serialization_tests()
	_run_phase4_f1_integration_test()

	print("\n--------------------------------------------------------")
	print("  Results: %d passed, %d failed" % [_passed, _failed])
	print("========================================================")
	if _failed == 0:
		print("ALL %d ASSERTIONS PASSED! (Exit Code 0)" % _passed)
		quit(0)
	else:
		print("FAILED WITH %d FAILURES! (Exit Code 1)" % _failed)
		quit(1)
