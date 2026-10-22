extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — Package 1R: Deterministic Faction Strategic Decision Engine
## Validates deterministic faction strategic decision layer per GDD §10.1, §10.2, §10.3, §10.4:
## - TC-FSTRAT.1: Canonical Goal Mapping (4 goals -> 4 documented intents)
## - TC-FSTRAT.2: Deterministic Repeatability (identical inputs -> identical outputs, no state drift)
## - TC-FSTRAT.3: Invalid Profile Safety (unsupported goal/status/null fail-closed)
## - TC-FSTRAT.4: Existence-Status Gating (active eligible; in_exile and eliminated ineligible)
## - TC-FSTRAT.5: Daily Simulation Integration (FactionManager signal emissions, stable ordering, no duplication)
## - TC-FSTRAT.6: Emerging Faction Compatibility (ascension seamlessly transitions goal & intent)
## - TC-FSTRAT.7: No Unintended Gameplay Mutation (before/after snapshot immutability)

const FactionManagerScript = preload("res://scripts/factions/faction_manager.gd")
const FactionDataScript = preload("res://scripts/factions/faction_data.gd")
const FactionStrategyPlannerScript = preload("res://scripts/factions/faction_strategy_planner.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")

var frame_count: int = 0
var world_instance: Node = null
var failures: int = 0

func _init() -> void:
	print("\n========================================================")
	print("  STARTING PACKAGE 1R FACTION STRATEGY PLANNER TESTS")
	print("========================================================\n")
	world_instance = WorldViewScene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count == 3:
		_run_all_tests()
		print("\n--------------------------------------------------------")
		if failures == 0:
			print("  ALL PACKAGE 1R FACTION STRATEGY TESTS PASSED! (Exit Code 0)")
			print("--------------------------------------------------------\n")
			quit(0)
			return true
		else:
			printerr("  PACKAGE 1R FACTION STRATEGY TESTS FAILED WITH %d FAILURES! (Exit Code 1)" % failures)
			print("--------------------------------------------------------\n")
			quit(1)
			return true
	return false

func _assert_true(cond: bool, test_name: String, msg: String = "") -> void:
	if not cond:
		failures += 1
		printerr("  ❌ FAIL [%s]: Expected true. %s" % [test_name, msg])
	else:
		print("  ✅ PASS [%s]%s" % [test_name, (" - " + msg) if msg != "" else ""])

func _assert_false(cond: bool, test_name: String, msg: String = "") -> void:
	if cond:
		failures += 1
		printerr("  ❌ FAIL [%s]: Expected false. %s" % [test_name, msg])
	else:
		print("  ✅ PASS [%s]%s" % [test_name, (" - " + msg) if msg != "" else ""])

func _assert_eq(actual: Variant, expected: Variant, test_name: String, msg: String = "") -> void:
	if actual != expected:
		failures += 1
		printerr("  ❌ FAIL [%s]: Expected %s, got %s. %s" % [test_name, str(expected), str(actual), msg])
	else:
		print("  ✅ PASS [%s]: %s == %s%s" % [test_name, str(actual), str(expected), (" - " + msg) if msg != "" else ""])

func _run_all_tests() -> void:
	test_tc_fstrat_1_canonical_goal_mapping()
	test_tc_fstrat_2_deterministic_repeatability()
	test_tc_fstrat_3_invalid_profile_safety()
	test_tc_fstrat_4_existence_status_gating()
	test_tc_fstrat_5_daily_simulation_integration()
	test_tc_fstrat_6_emerging_faction_compatibility()
	test_tc_fstrat_7_no_unintended_gameplay_mutation()

# -----------------------------------------------------------------------------
# TC-FSTRAT.1: Canonical Goal Mapping
# -----------------------------------------------------------------------------
func test_tc_fstrat_1_canonical_goal_mapping() -> void:
	print("\n--- TC-FSTRAT.1: Canonical Goal Mapping ---")

	# Test mapping helper get_intent_for_goal
	_assert_eq(
		FactionStrategyPlannerScript.get_intent_for_goal(FactionDataScript.GOAL_MILITARY_EXPANSION),
		FactionStrategyPlannerScript.INTENT_MILITARY_BUILDUP,
		"TC-FSTRAT.1-MAP-MIL",
		"military_expansion maps to military_buildup"
	)
	_assert_eq(
		FactionStrategyPlannerScript.get_intent_for_goal(FactionDataScript.GOAL_TRADE_DOMINANCE),
		FactionStrategyPlannerScript.INTENT_TRADE_EXPANSION,
		"TC-FSTRAT.1-MAP-TRADE",
		"trade_dominance maps to trade_expansion"
	)
	_assert_eq(
		FactionStrategyPlannerScript.get_intent_for_goal(FactionDataScript.GOAL_COMMUNITY_GROWTH),
		FactionStrategyPlannerScript.INTENT_COMMUNITY_DEVELOPMENT,
		"TC-FSTRAT.1-MAP-GROWTH",
		"community_growth maps to community_development"
	)
	_assert_eq(
		FactionStrategyPlannerScript.get_intent_for_goal(FactionDataScript.GOAL_CONSOLIDATE_POWER),
		FactionStrategyPlannerScript.INTENT_POWER_CONSOLIDATION,
		"TC-FSTRAT.1-MAP-POWER",
		"consolidate_power maps to power_consolidation"
	)
	_assert_eq(
		FactionStrategyPlannerScript.get_intent_for_goal("non_existent_goal"),
		FactionStrategyPlannerScript.INTENT_NONE,
		"TC-FSTRAT.1-MAP-UNKNOWN",
		"Unknown goal maps to INTENT_NONE"
	)

	# Test full evaluation on live/mock factions for each canonical goal
	var fac_mil := FactionDataScript.new("test_mil", "Cổ Thành", "rival_military", FactionDataScript.Disposition.NEUTRAL, -10.0, 75.0, FactionDataScript.GOAL_MILITARY_EXPANSION)
	var res_mil: Dictionary = FactionStrategyPlannerScript.evaluate_faction_intent(fac_mil)
	_assert_eq(res_mil.get("faction_id", ""), "test_mil", "TC-FSTRAT.1-RES-MIL-ID", "Correct faction_id for military")
	_assert_eq(res_mil.get("strategic_goal", ""), FactionDataScript.GOAL_MILITARY_EXPANSION, "TC-FSTRAT.1-RES-MIL-GOAL", "Correct strategic_goal for military")
	_assert_eq(res_mil.get("intent_id", ""), FactionStrategyPlannerScript.INTENT_MILITARY_BUILDUP, "TC-FSTRAT.1-RES-MIL-INTENT", "Correct intent_id for military")
	_assert_true(res_mil.get("eligible", false), "TC-FSTRAT.1-RES-MIL-ELIGIBLE", "Military faction is eligible")
	_assert_eq(res_mil.get("reason_code", ""), FactionStrategyPlannerScript.REASON_GOAL_ALIGNED, "TC-FSTRAT.1-RES-MIL-REASON", "Reason code is GOAL_ALIGNED")
	_assert_eq(res_mil.get("posture", ""), "peacetime", "TC-FSTRAT.1-RES-MIL-POSTURE", "Peacetime posture")

	var fac_trade := FactionDataScript.new("test_trade", "Vân Đồn", "rival_merchant", FactionDataScript.Disposition.NEUTRAL, 15.0, 50.0, FactionDataScript.GOAL_TRADE_DOMINANCE)
	var res_trade: Dictionary = FactionStrategyPlannerScript.evaluate_faction_intent(fac_trade)
	_assert_eq(res_trade.get("faction_id", ""), "test_trade", "TC-FSTRAT.1-RES-TRADE-ID", "Correct faction_id for trade")
	_assert_eq(res_trade.get("strategic_goal", ""), FactionDataScript.GOAL_TRADE_DOMINANCE, "TC-FSTRAT.1-RES-TRADE-GOAL", "Correct strategic_goal for trade")
	_assert_eq(res_trade.get("intent_id", ""), FactionStrategyPlannerScript.INTENT_TRADE_EXPANSION, "TC-FSTRAT.1-RES-TRADE-INTENT", "Correct intent_id for trade")
	_assert_true(res_trade.get("eligible", false), "TC-FSTRAT.1-RES-TRADE-ELIGIBLE", "Trade faction is eligible")
	_assert_eq(res_trade.get("reason_code", ""), FactionStrategyPlannerScript.REASON_GOAL_ALIGNED, "TC-FSTRAT.1-RES-TRADE-REASON", "Reason code is GOAL_ALIGNED")

	var fac_growth := FactionDataScript.new("test_growth", "Bản Làng", "neutral_tribe", FactionDataScript.Disposition.FRIENDLY, 30.0, 30.0, FactionDataScript.GOAL_COMMUNITY_GROWTH)
	var res_growth: Dictionary = FactionStrategyPlannerScript.evaluate_faction_intent(fac_growth)
	_assert_eq(res_growth.get("faction_id", ""), "test_growth", "TC-FSTRAT.1-RES-GROWTH-ID", "Correct faction_id for growth")
	_assert_eq(res_growth.get("strategic_goal", ""), FactionDataScript.GOAL_COMMUNITY_GROWTH, "TC-FSTRAT.1-RES-GROWTH-GOAL", "Correct strategic_goal for growth")
	_assert_eq(res_growth.get("intent_id", ""), FactionStrategyPlannerScript.INTENT_COMMUNITY_DEVELOPMENT, "TC-FSTRAT.1-RES-GROWTH-INTENT", "Correct intent_id for growth")
	_assert_true(res_growth.get("eligible", false), "TC-FSTRAT.1-RES-GROWTH-ELIGIBLE", "Growth faction is eligible")
	_assert_eq(res_growth.get("reason_code", ""), FactionStrategyPlannerScript.REASON_GOAL_ALIGNED, "TC-FSTRAT.1-RES-GROWTH-REASON", "Reason code is GOAL_ALIGNED")

	var fac_power := FactionDataScript.new("test_power", "Liên Minh", "emerging_power", FactionDataScript.Disposition.FRIENDLY, 30.0, 55.0, FactionDataScript.GOAL_CONSOLIDATE_POWER)
	var res_power: Dictionary = FactionStrategyPlannerScript.evaluate_faction_intent(fac_power)
	_assert_eq(res_power.get("faction_id", ""), "test_power", "TC-FSTRAT.1-RES-POWER-ID", "Correct faction_id for power")
	_assert_eq(res_power.get("strategic_goal", ""), FactionDataScript.GOAL_CONSOLIDATE_POWER, "TC-FSTRAT.1-RES-POWER-GOAL", "Correct strategic_goal for power")
	_assert_eq(res_power.get("intent_id", ""), FactionStrategyPlannerScript.INTENT_POWER_CONSOLIDATION, "TC-FSTRAT.1-RES-POWER-INTENT", "Correct intent_id for power")
	_assert_true(res_power.get("eligible", false), "TC-FSTRAT.1-RES-POWER-ELIGIBLE", "Power faction is eligible")
	_assert_eq(res_power.get("reason_code", ""), FactionStrategyPlannerScript.REASON_GOAL_ALIGNED, "TC-FSTRAT.1-RES-POWER-REASON", "Reason code is GOAL_ALIGNED")

	# Test localized intent labels
	_assert_eq(FactionStrategyPlannerScript.get_intent_label(FactionStrategyPlannerScript.INTENT_MILITARY_BUILDUP), "Tăng cường quân sự", "TC-FSTRAT.1-LBL-MIL")
	_assert_eq(FactionStrategyPlannerScript.get_intent_label(FactionStrategyPlannerScript.INTENT_TRADE_EXPANSION), "Mở rộng giao thương", "TC-FSTRAT.1-LBL-TRADE")
	_assert_eq(FactionStrategyPlannerScript.get_intent_label(FactionStrategyPlannerScript.INTENT_COMMUNITY_DEVELOPMENT), "Phát triển cộng đồng", "TC-FSTRAT.1-LBL-GROWTH")
	_assert_eq(FactionStrategyPlannerScript.get_intent_label(FactionStrategyPlannerScript.INTENT_POWER_CONSOLIDATION), "Củng cố quyền lực", "TC-FSTRAT.1-LBL-POWER")
	_assert_eq(FactionStrategyPlannerScript.get_intent_label("unknown_intent"), "Không xác định", "TC-FSTRAT.1-LBL-UNKNOWN")

# -----------------------------------------------------------------------------
# TC-FSTRAT.2: Deterministic Repeatability
# -----------------------------------------------------------------------------
func test_tc_fstrat_2_deterministic_repeatability() -> void:
	print("\n--- TC-FSTRAT.2: Deterministic Repeatability ---")
	var fac := FactionDataScript.new("repeat_fac", "Thành Trì Mẫu", "rival_military", FactionDataScript.Disposition.NEUTRAL, 5.0, 60.0, FactionDataScript.GOAL_MILITARY_EXPANSION)
	fac.resources = {EconomyConfigScript.RES_WOOD: 100, EconomyConfigScript.RES_FOOD: 200}
	fac.population = 45
	fac.stability = 75.0

	var baseline_res: Dictionary = FactionStrategyPlannerScript.evaluate_faction_intent(fac)
	var all_identical: bool = true

	for i in range(50):
		var repeat_res: Dictionary = FactionStrategyPlannerScript.evaluate_faction_intent(fac)
		if repeat_res["faction_id"] != baseline_res["faction_id"] \
			or repeat_res["strategic_goal"] != baseline_res["strategic_goal"] \
			or repeat_res["intent_id"] != baseline_res["intent_id"] \
			or repeat_res["eligible"] != baseline_res["eligible"] \
			or repeat_res["reason_code"] != baseline_res["reason_code"] \
			or repeat_res["posture"] != baseline_res["posture"]:
			all_identical = false
			break

	_assert_true(all_identical, "TC-FSTRAT.2-REPEATABLE", "50 consecutive evaluations produced 100% identical outputs")
	_assert_eq(fac.opinion, 5.0, "TC-FSTRAT.2-OPINION-UNMUTATED", "Faction opinion unaffected by repeated evaluation")
	_assert_eq(fac.military_power, 60.0, "TC-FSTRAT.2-MIL-UNMUTATED", "Faction military_power unaffected by repeated evaluation")
	_assert_eq(fac.population, 45, "TC-FSTRAT.2-POP-UNMUTATED", "Faction population unaffected by repeated evaluation")
	_assert_eq(fac.strategic_goal, FactionDataScript.GOAL_MILITARY_EXPANSION, "TC-FSTRAT.2-GOAL-UNMUTATED", "Faction goal unaffected by repeated evaluation")
	_assert_eq(fac.existence_status, FactionDataScript.STATUS_ACTIVE, "TC-FSTRAT.2-STATUS-UNMUTATED", "Faction status unaffected by repeated evaluation")

# -----------------------------------------------------------------------------
# TC-FSTRAT.3: Invalid Profile Safety (Fail-Closed)
# -----------------------------------------------------------------------------
func test_tc_fstrat_3_invalid_profile_safety() -> void:
	print("\n--- TC-FSTRAT.3: Invalid Profile Safety ---")

	# 1. Null faction pointer
	var res_null: Dictionary = FactionStrategyPlannerScript.evaluate_faction_intent(null)
	_assert_false(res_null.get("eligible", true), "TC-FSTRAT.3-NULL-INELIGIBLE", "Null faction returns ineligible")
	_assert_eq(res_null.get("intent_id", ""), FactionStrategyPlannerScript.INTENT_NONE, "TC-FSTRAT.3-NULL-INTENT-NONE", "Null faction has INTENT_NONE")
	_assert_eq(res_null.get("reason_code", ""), FactionStrategyPlannerScript.REASON_ERR_NULL_FACTION, "TC-FSTRAT.3-NULL-REASON", "Reason code identifies ERR_NULL_FACTION")

	# 2. Unsupported strategic goal
	var fac_bad_goal := FactionDataScript.new("bad_goal_fac", "Thế Lực Lỗi", "neutral_tribe")
	fac_bad_goal.strategic_goal = "galactic_conquest"
	var res_bad_goal: Dictionary = FactionStrategyPlannerScript.evaluate_faction_intent(fac_bad_goal)
	_assert_false(res_bad_goal.get("eligible", true), "TC-FSTRAT.3-BAD-GOAL-INELIGIBLE", "Unsupported goal returns ineligible")
	_assert_eq(res_bad_goal.get("intent_id", ""), FactionStrategyPlannerScript.INTENT_NONE, "TC-FSTRAT.3-BAD-GOAL-INTENT-NONE", "Unsupported goal has INTENT_NONE")
	_assert_eq(res_bad_goal.get("reason_code", ""), FactionStrategyPlannerScript.REASON_ERR_INVALID_GOAL, "TC-FSTRAT.3-BAD-GOAL-REASON", "Reason code identifies ERR_INVALID_GOAL")
	_assert_eq(fac_bad_goal.strategic_goal, "galactic_conquest", "TC-FSTRAT.3-BAD-GOAL-UNMUTATED", "Evaluator did not mutate invalid goal")

	# 3. Empty strategic goal
	var fac_empty_goal := FactionDataScript.new("empty_goal_fac", "Thế Lực Trống", "neutral_tribe")
	fac_empty_goal.strategic_goal = ""
	fac_empty_goal.existence_status = FactionDataScript.STATUS_ACTIVE
	fac_empty_goal.opinion = 15.0
	fac_empty_goal.military_power = 40.0
	var res_empty_goal: Dictionary = FactionStrategyPlannerScript.evaluate_faction_intent(fac_empty_goal)
	_assert_false(res_empty_goal.get("eligible", true), "TC-FSTRAT.3-EMPTY-GOAL-INELIGIBLE", "Empty goal returns ineligible")
	_assert_eq(res_empty_goal.get("intent_id", ""), FactionStrategyPlannerScript.INTENT_NONE, "TC-FSTRAT.3-EMPTY-GOAL-INTENT-NONE", "Empty goal has INTENT_NONE")
	_assert_eq(res_empty_goal.get("reason_code", ""), FactionStrategyPlannerScript.REASON_ERR_INVALID_GOAL, "TC-FSTRAT.3-EMPTY-GOAL-REASON", "Empty goal has ERR_INVALID_GOAL reason")
	_assert_eq(fac_empty_goal.strategic_goal, "", "TC-FSTRAT.3-EMPTY-GOAL-UNMUTATED", "Evaluator did not mutate empty goal")
	_assert_eq(fac_empty_goal.existence_status, FactionDataScript.STATUS_ACTIVE, "TC-FSTRAT.3-EMPTY-GOAL-STATUS-UNMUTATED", "Faction status unmutated")
	_assert_eq(fac_empty_goal.opinion, 15.0, "TC-FSTRAT.3-EMPTY-GOAL-OPINION-UNMUTATED", "Faction opinion unmutated")
	_assert_eq(fac_empty_goal.military_power, 40.0, "TC-FSTRAT.3-EMPTY-GOAL-MIL-UNMUTATED", "Faction military power unmutated")

	# 4. Unsupported existence status
	var fac_bad_status := FactionDataScript.new("bad_status_fac", "Thế Lực Ảo", "neutral_tribe")
	fac_bad_status.existence_status = "nether_realm"
	var res_bad_status: Dictionary = FactionStrategyPlannerScript.evaluate_faction_intent(fac_bad_status)
	_assert_false(res_bad_status.get("eligible", true), "TC-FSTRAT.3-BAD-STATUS-INELIGIBLE", "Unsupported status returns ineligible")
	_assert_eq(res_bad_status.get("intent_id", ""), FactionStrategyPlannerScript.INTENT_NONE, "TC-FSTRAT.3-BAD-STATUS-INTENT-NONE", "Unsupported status has INTENT_NONE")
	_assert_eq(res_bad_status.get("reason_code", ""), FactionStrategyPlannerScript.REASON_ERR_INVALID_STATUS, "TC-FSTRAT.3-BAD-STATUS-REASON", "Reason code identifies ERR_INVALID_STATUS")
	_assert_eq(fac_bad_status.existence_status, "nether_realm", "TC-FSTRAT.3-BAD-STATUS-UNMUTATED", "Evaluator did not mutate invalid status")

# -----------------------------------------------------------------------------
# TC-FSTRAT.4: Existence-Status Gating
# -----------------------------------------------------------------------------
func test_tc_fstrat_4_existence_status_gating() -> void:
	print("\n--- TC-FSTRAT.4: Existence-Status Gating ---")

	# Active faction receives eligible intent
	var fac_active := FactionDataScript.new("active_fac", "Thế Lực Hoạt Động", "rival_merchant", FactionDataScript.Disposition.NEUTRAL, 10.0, 50.0, FactionDataScript.GOAL_TRADE_DOMINANCE, FactionDataScript.STATUS_ACTIVE)
	var res_active: Dictionary = FactionStrategyPlannerScript.evaluate_faction_intent(fac_active)
	_assert_true(res_active.get("eligible", false), "TC-FSTRAT.4-ACTIVE-ELIGIBLE", "Active faction is eligible")
	_assert_eq(res_active.get("intent_id", ""), FactionStrategyPlannerScript.INTENT_TRADE_EXPANSION, "TC-FSTRAT.4-ACTIVE-INTENT", "Active faction receives valid intent")

	# In-exile faction does not receive active-world intent
	var fac_exile := FactionDataScript.new("exile_fac", "Thế Lực Lưu Vong", "rival_military", FactionDataScript.Disposition.HOSTILE, -50.0, 20.0, FactionDataScript.GOAL_MILITARY_EXPANSION, FactionDataScript.STATUS_IN_EXILE)
	var res_exile: Dictionary = FactionStrategyPlannerScript.evaluate_faction_intent(fac_exile)
	_assert_false(res_exile.get("eligible", true), "TC-FSTRAT.4-EXILE-INELIGIBLE", "In-exile faction is ineligible")
	_assert_eq(res_exile.get("intent_id", ""), FactionStrategyPlannerScript.INTENT_NONE, "TC-FSTRAT.4-EXILE-INTENT-NONE", "In-exile faction has INTENT_NONE")
	_assert_eq(res_exile.get("reason_code", ""), FactionStrategyPlannerScript.REASON_INELIGIBLE_EXILE, "TC-FSTRAT.4-EXILE-REASON", "Reason is INELIGIBLE_IN_EXILE")
	_assert_eq(fac_exile.existence_status, FactionDataScript.STATUS_IN_EXILE, "TC-FSTRAT.4-EXILE-STATUS-INTACT", "Status remains strictly in_exile")

	# Eliminated faction does not receive active-world intent
	var fac_elim := FactionDataScript.new("elim_fac", "Thế Lực Bị Loại", "neutral_tribe", FactionDataScript.Disposition.NEUTRAL, 0.0, 0.0, FactionDataScript.GOAL_COMMUNITY_GROWTH, FactionDataScript.STATUS_ELIMINATED)
	var res_elim: Dictionary = FactionStrategyPlannerScript.evaluate_faction_intent(fac_elim)
	_assert_false(res_elim.get("eligible", true), "TC-FSTRAT.4-ELIM-INELIGIBLE", "Eliminated faction is ineligible")
	_assert_eq(res_elim.get("intent_id", ""), FactionStrategyPlannerScript.INTENT_NONE, "TC-FSTRAT.4-ELIM-INTENT-NONE", "Eliminated faction has INTENT_NONE")
	_assert_eq(res_elim.get("reason_code", ""), FactionStrategyPlannerScript.REASON_INELIGIBLE_ELIMINATED, "TC-FSTRAT.4-ELIM-REASON", "Reason is INELIGIBLE_ELIMINATED")
	_assert_eq(fac_elim.existence_status, FactionDataScript.STATUS_ELIMINATED, "TC-FSTRAT.4-ELIM-STATUS-INTACT", "Status remains strictly eliminated")

	# Faction with zero military power but active status is NOT treated as eliminated
	var fac_zero_mil := FactionDataScript.new("zero_mil_fac", "Hòa Bình", "neutral_tribe", FactionDataScript.Disposition.FRIENDLY, 20.0, 0.0, FactionDataScript.GOAL_COMMUNITY_GROWTH, FactionDataScript.STATUS_ACTIVE)
	var res_zero_mil: Dictionary = FactionStrategyPlannerScript.evaluate_faction_intent(fac_zero_mil)
	_assert_true(res_zero_mil.get("eligible", false), "TC-FSTRAT.4-ZERO-MIL-ELIGIBLE", "Zero military power faction with active status remains eligible")
	_assert_eq(res_zero_mil.get("intent_id", ""), FactionStrategyPlannerScript.INTENT_COMMUNITY_DEVELOPMENT, "TC-FSTRAT.4-ZERO-MIL-INTENT", "Zero military power receives community_development")

# -----------------------------------------------------------------------------
# TC-FSTRAT.5: Daily Simulation Integration
# -----------------------------------------------------------------------------
func test_tc_fstrat_5_daily_simulation_integration() -> void:
	print("\n--- TC-FSTRAT.5: Daily Simulation Integration ---")
	var fm := FactionManagerScript.new()

	var emitted_intents: Array[Dictionary] = []
	var on_intent_evaluated := func(fac_id: String, intent_data: Dictionary):
		emitted_intents.append({"faction_id": fac_id, "data": intent_data})
	fm.strategic_intent_evaluated.connect(on_intent_evaluated)

	# 1. Day 1 update: all 3 standard factions active
	fm.update_daily_simulation(1)
	_assert_eq(emitted_intents.size(), 3, "TC-FSTRAT.5-DAY1-COUNT", "Exactly 3 intent signals emitted on Day 1")

	# Verify stable deterministic processing order (sorted keys: neutral_tribe, rival_merchant, rival_military)
	_assert_eq(emitted_intents[0]["faction_id"], "neutral_tribe", "TC-FSTRAT.5-ORDER-1", "First evaluated faction is neutral_tribe")
	_assert_eq(emitted_intents[0]["data"]["intent_id"], FactionStrategyPlannerScript.INTENT_COMMUNITY_DEVELOPMENT, "TC-FSTRAT.5-ORDER-1-INTENT")

	_assert_eq(emitted_intents[1]["faction_id"], "rival_merchant", "TC-FSTRAT.5-ORDER-2", "Second evaluated faction is rival_merchant")
	_assert_eq(emitted_intents[1]["data"]["intent_id"], FactionStrategyPlannerScript.INTENT_TRADE_EXPANSION, "TC-FSTRAT.5-ORDER-2-INTENT")

	_assert_eq(emitted_intents[2]["faction_id"], "rival_military", "TC-FSTRAT.5-ORDER-3", "Third evaluated faction is rival_military")
	_assert_eq(emitted_intents[2]["data"]["intent_id"], FactionStrategyPlannerScript.INTENT_MILITARY_BUILDUP, "TC-FSTRAT.5-ORDER-3-INTENT")

	# 2. Inactive status skipping: put rival_merchant in exile
	emitted_intents.clear()
	var merch: FactionData = fm.get_faction("rival_merchant")
	merch.existence_status = FactionDataScript.STATUS_IN_EXILE

	fm.update_daily_simulation(2)
	_assert_eq(emitted_intents.size(), 2, "TC-FSTRAT.5-EXILE-SKIP-COUNT", "Exactly 2 intent signals emitted when 1 faction in exile")
	_assert_eq(emitted_intents[0]["faction_id"], "neutral_tribe", "TC-FSTRAT.5-EXILE-REMAIN-1")
	_assert_eq(emitted_intents[1]["faction_id"], "rival_military", "TC-FSTRAT.5-EXILE-REMAIN-2")

	var merch_query: Dictionary = fm.get_faction_strategic_intent("rival_merchant")
	_assert_false(merch_query.get("eligible", true), "TC-FSTRAT.5-EXILE-QUERY-INELIGIBLE", "Direct query for exiled faction reports ineligible")
	_assert_eq(merch_query.get("reason_code", ""), FactionStrategyPlannerScript.REASON_INELIGIBLE_EXILE, "TC-FSTRAT.5-EXILE-QUERY-REASON")

	# 3. Put rival_military in eliminated status
	emitted_intents.clear()
	var mil: FactionData = fm.get_faction("rival_military")
	mil.existence_status = FactionDataScript.STATUS_ELIMINATED

	fm.update_daily_simulation(3)
	_assert_eq(emitted_intents.size(), 1, "TC-FSTRAT.5-ELIM-SKIP-COUNT", "Exactly 1 intent signal emitted when 2 factions inactive")
	_assert_eq(emitted_intents[0]["faction_id"], "neutral_tribe", "TC-FSTRAT.5-ELIM-REMAIN-1")

	# 4. Restore both to active, verify clean recovery and evaluate_all_strategic_intents
	merch.existence_status = FactionDataScript.STATUS_ACTIVE
	mil.existence_status = FactionDataScript.STATUS_ACTIVE

	var all_intents: Array[Dictionary] = fm.evaluate_all_strategic_intents()
	_assert_eq(all_intents.size(), 3, "TC-FSTRAT.5-ALL-QUERY-COUNT", "evaluate_all_strategic_intents returns 3 items")
	_assert_true(all_intents[0]["eligible"], "TC-FSTRAT.5-ALL-ITEM1-ELIGIBLE")
	_assert_true(all_intents[1]["eligible"], "TC-FSTRAT.5-ALL-ITEM2-ELIGIBLE")
	_assert_true(all_intents[2]["eligible"], "TC-FSTRAT.5-ALL-ITEM3-ELIGIBLE")

	# 5. Wartime posture evaluation (direct planner evaluation and daily simulation signal)
	mil.is_at_war = true
	var mil_pre_war_opinion: float = mil.opinion
	var mil_pre_war_mil: float = mil.military_power
	var mil_pre_war_pop: int = mil.population

	# Direct planner evaluation of wartime faction
	var wartime_direct: Dictionary = FactionStrategyPlannerScript.evaluate_faction_intent(mil)
	_assert_true(wartime_direct.get("eligible", false), "TC-FSTRAT.5-WAR-DIRECT-ELIGIBLE", "Active faction at war remains eligible")
	_assert_eq(wartime_direct.get("intent_id", ""), FactionStrategyPlannerScript.INTENT_MILITARY_BUILDUP, "TC-FSTRAT.5-WAR-DIRECT-INTENT", "Wartime intent matches strategic goal")
	_assert_eq(wartime_direct.get("posture", ""), "wartime", "TC-FSTRAT.5-WAR-DIRECT-POSTURE", "Wartime posture is 'wartime'")
	_assert_eq(wartime_direct.get("reason_code", ""), FactionStrategyPlannerScript.REASON_WARTIME_POSTURE, "TC-FSTRAT.5-WAR-DIRECT-REASON", "Wartime reason code is WARTIME_POSTURE")
	_assert_true(mil.is_at_war, "TC-FSTRAT.5-WAR-FIELD-IS-WAR", "Faction is_at_war unchanged by planner")
	_assert_eq(mil.strategic_goal, FactionDataScript.GOAL_MILITARY_EXPANSION, "TC-FSTRAT.5-WAR-FIELD-GOAL", "Faction strategic_goal unchanged by planner")
	_assert_eq(mil.existence_status, FactionDataScript.STATUS_ACTIVE, "TC-FSTRAT.5-WAR-FIELD-STATUS", "Faction existence_status unchanged by planner")
	_assert_eq(mil.opinion, mil_pre_war_opinion, "TC-FSTRAT.5-WAR-FIELD-OPINION", "Faction opinion unchanged by planner")
	_assert_eq(mil.military_power, mil_pre_war_mil, "TC-FSTRAT.5-WAR-FIELD-MIL", "Faction military_power unchanged by planner")
	_assert_eq(mil.population, mil_pre_war_pop, "TC-FSTRAT.5-WAR-FIELD-POP", "Faction population unchanged by planner")

	# Simulation update with wartime faction
	emitted_intents.clear()
	fm.update_daily_simulation(4)
	var mil_sim_data: Dictionary = {}
	for item in emitted_intents:
		if item["faction_id"] == "rival_military":
			mil_sim_data = item["data"]
			break
	_assert_true(mil_sim_data.get("eligible", false), "TC-FSTRAT.5-WAR-SIM-ELIGIBLE", "Emitted signal indicates wartime faction is eligible")
	_assert_eq(mil_sim_data.get("intent_id", ""), FactionStrategyPlannerScript.INTENT_MILITARY_BUILDUP, "TC-FSTRAT.5-WAR-SIM-INTENT", "Emitted signal carries aligned intent")
	_assert_eq(mil_sim_data.get("posture", ""), "wartime", "TC-FSTRAT.5-WAR-SIM-POSTURE", "Emitted signal carries wartime posture")
	_assert_eq(mil_sim_data.get("reason_code", ""), FactionStrategyPlannerScript.REASON_WARTIME_POSTURE, "TC-FSTRAT.5-WAR-SIM-REASON", "Emitted signal carries WARTIME_POSTURE reason")

	# Restore test fixture
	mil.is_at_war = false

	fm.strategic_intent_evaluated.disconnect(on_intent_evaluated)

# -----------------------------------------------------------------------------
# TC-FSTRAT.6: Emerging Faction Compatibility
# -----------------------------------------------------------------------------
func test_tc_fstrat_6_emerging_faction_compatibility() -> void:
	print("\n--- TC-FSTRAT.6: Emerging Faction Compatibility ---")
	var fm := FactionManagerScript.new()

	var emitted_intents: Array[Dictionary] = []
	var on_intent_evaluated := func(fac_id: String, intent_data: Dictionary):
		emitted_intents.append({"faction_id": fac_id, "data": intent_data})
	fm.strategic_intent_evaluated.connect(on_intent_evaluated)

	var tribe: FactionData = fm.get_faction("neutral_tribe")
	_assert_eq(tribe.strategic_goal, FactionDataScript.GOAL_COMMUNITY_GROWTH, "TC-FSTRAT.6-PRE-GOAL", "Initial tribe goal is community_growth")

	# Day 9 simulation: not yet ascended
	fm.update_daily_simulation(9)
	var tribe_day9_intent: Dictionary = {}
	for item in emitted_intents:
		if item["faction_id"] == "neutral_tribe":
			tribe_day9_intent = item["data"]
			break
	_assert_eq(tribe_day9_intent.get("strategic_goal", ""), FactionDataScript.GOAL_COMMUNITY_GROWTH, "TC-FSTRAT.6-DAY9-GOAL")
	_assert_eq(tribe_day9_intent.get("intent_id", ""), FactionStrategyPlannerScript.INTENT_COMMUNITY_DEVELOPMENT, "TC-FSTRAT.6-DAY9-INTENT")

	# Configure tribe conditions for ascension at Day 10
	tribe.population = 44 # Will increment to 45 in update_daily_simulation
	tribe.resources = {EconomyConfigScript.RES_WOOD: 120, EconomyConfigScript.RES_HERBS: 60}
	tribe.stability = 85.0

	emitted_intents.clear()
	var ascension_signals: Array = []
	var on_ascended := func(fac_id: String, new_name: String):
		ascension_signals.append({"id": fac_id, "name": new_name})
	fm.emerging_faction_ascended.connect(on_ascended)

	# Execute Day 10 tick: ascension triggers, followed by strategic intent evaluation
	fm.update_daily_simulation(10)
	_assert_eq(ascension_signals.size(), 1, "TC-FSTRAT.6-ASCENDED-SIGNAL", "emerging_faction_ascended emitted once")
	_assert_eq(tribe.type, FactionManagerScript.ASCENSION_NEW_TYPE, "TC-FSTRAT.6-TYPE-ASCENDED", "Tribe evolved to emerging_power")
	_assert_eq(tribe.strategic_goal, FactionDataScript.GOAL_CONSOLIDATE_POWER, "TC-FSTRAT.6-GOAL-ASCENDED", "Tribe strategic_goal mutated to consolidate_power")

	# Confirm intent evaluated during same Day 10 tick reflects updated goal and intent
	var tribe_day10_intent: Dictionary = {}
	for item in emitted_intents:
		if item["faction_id"] == "neutral_tribe":
			tribe_day10_intent = item["data"]
			break
	_assert_eq(tribe_day10_intent.get("strategic_goal", ""), FactionDataScript.GOAL_CONSOLIDATE_POWER, "TC-FSTRAT.6-DAY10-GOAL-CONSOLIDATE", "Day 10 intent reflects consolidate_power")
	_assert_eq(tribe_day10_intent.get("intent_id", ""), FactionStrategyPlannerScript.INTENT_POWER_CONSOLIDATION, "TC-FSTRAT.6-DAY10-INTENT-POWER", "Day 10 intent reflects power_consolidation")
	_assert_true(tribe_day10_intent.get("eligible", false), "TC-FSTRAT.6-DAY10-ELIGIBLE")

	# Day 11 tick: maintains consolidate_power and power_consolidation without re-emitting ascension
	emitted_intents.clear()
	fm.update_daily_simulation(11)
	_assert_eq(ascension_signals.size(), 1, "TC-FSTRAT.6-NO-REASCEND", "No re-ascension on Day 11")

	var tribe_day11_intent: Dictionary = {}
	for item in emitted_intents:
		if item["faction_id"] == "neutral_tribe":
			tribe_day11_intent = item["data"]
			break
	_assert_eq(tribe_day11_intent.get("strategic_goal", ""), FactionDataScript.GOAL_CONSOLIDATE_POWER, "TC-FSTRAT.6-DAY11-GOAL")
	_assert_eq(tribe_day11_intent.get("intent_id", ""), FactionStrategyPlannerScript.INTENT_POWER_CONSOLIDATION, "TC-FSTRAT.6-DAY11-INTENT")

	fm.strategic_intent_evaluated.disconnect(on_intent_evaluated)
	fm.emerging_faction_ascended.disconnect(on_ascended)

# -----------------------------------------------------------------------------
# TC-FSTRAT.7: No Unintended Gameplay Mutation
# -----------------------------------------------------------------------------
func _take_faction_snapshot(fac: FactionData) -> Dictionary:
	var res_copy: Dictionary = {}
	for k in fac.resources:
		res_copy[k] = fac.resources[k]

	return {
		"id": str(fac.id),
		"name": str(fac.name),
		"type": str(fac.type),
		"opinion": float(fac.opinion),
		"military_power": float(fac.military_power),
		"stability": float(fac.stability),
		"resources": res_copy,
		"population": int(fac.population),
		"is_at_war": bool(fac.is_at_war),
		"has_nap": bool(fac.has_nap),
		"has_alliance": bool(fac.has_alliance),
		"strategic_goal": str(fac.strategic_goal),
		"existence_status": str(fac.existence_status)
	}

func _verify_faction_snapshot(fac: FactionData, snap: Dictionary, prefix: String) -> void:
	_assert_eq(str(fac.id), snap["id"], prefix + "-ID", "id unmutated")
	_assert_eq(fac.name, snap["name"], prefix + "-NAME", "name unmutated")
	_assert_eq(fac.type, snap["type"], prefix + "-TYPE", "type unmutated")
	_assert_eq(fac.opinion, snap["opinion"], prefix + "-OPINION", "opinion unmutated")
	_assert_eq(fac.military_power, snap["military_power"], prefix + "-MIL", "military_power unmutated")
	_assert_eq(fac.stability, snap["stability"], prefix + "-STAB", "stability unmutated")
	_assert_eq(fac.population, snap["population"], prefix + "-POP", "population unmutated")
	_assert_eq(fac.is_at_war, snap["is_at_war"], prefix + "-WAR", "is_at_war unmutated")
	_assert_eq(fac.has_nap, snap["has_nap"], prefix + "-NAP", "has_nap unmutated")
	_assert_eq(fac.has_alliance, snap["has_alliance"], prefix + "-ALLIANCE", "has_alliance unmutated")
	_assert_eq(fac.strategic_goal, snap["strategic_goal"], prefix + "-GOAL", "strategic_goal unmutated")
	_assert_eq(fac.existence_status, snap["existence_status"], prefix + "-STATUS", "existence_status unmutated")
	_assert_eq(fac.resources.size(), snap["resources"].size(), prefix + "-RES-COUNT", "resources count unmutated")
	for k in snap["resources"]:
		_assert_eq(fac.resources.get(k, 0), snap["resources"][k], prefix + "-RES-" + str(k).to_upper(), "resource " + str(k) + " unmutated")

func test_tc_fstrat_7_no_unintended_gameplay_mutation() -> void:
	print("\n--- TC-FSTRAT.7: No Unintended Gameplay Mutation ---")
	var fac := FactionDataScript.new("immut_fac", "Bảo Vệ Đô", "rival_military", FactionDataScript.Disposition.NEUTRAL, -5.0, 80.0, FactionDataScript.GOAL_MILITARY_EXPANSION)
	fac.stability = 75.0
	fac.population = 50
	fac.resources = {EconomyConfigScript.RES_METAL: 50, EconomyConfigScript.RES_GOLD: 200}
	fac.is_at_war = false
	fac.has_nap = true
	fac.has_alliance = false

	# 1. Direct evaluator call immutability
	var snap_before_eval: Dictionary = _take_faction_snapshot(fac)
	var eval_res: Dictionary = FactionStrategyPlannerScript.evaluate_faction_intent(fac)
	_assert_true(eval_res.get("eligible", false), "TC-FSTRAT.7-DIRECT-OK")
	_verify_faction_snapshot(fac, snap_before_eval, "TC-FSTRAT.7-DIRECT")

	# 2. Repeated direct evaluations immutability
	for i in range(25):
		FactionStrategyPlannerScript.evaluate_faction_intent(fac)
	_verify_faction_snapshot(fac, snap_before_eval, "TC-FSTRAT.7-MULTI-DIRECT")

	# 3. FactionManager daily simulation integration & baseline simulation effects
	var fm := FactionManagerScript.new()
	var mil: FactionData = fm.get_faction("rival_military")
	var merch: FactionData = fm.get_faction("rival_merchant")
	var tribe: FactionData = fm.get_faction("neutral_tribe")
	var snap_mil: Dictionary = _take_faction_snapshot(mil)
	var snap_merch: Dictionary = _take_faction_snapshot(merch)
	var snap_tribe: Dictionary = _take_faction_snapshot(tribe)

	# Run multiple daily simulation ticks on pre-ascension world (day 1..5)
	for d in range(1, 6):
		fm.update_daily_simulation(d)

	# Factions without simulation rules (rival_military, rival_merchant) remain 100% unchanged
	_verify_faction_snapshot(mil, snap_mil, "TC-FSTRAT.7-SIM-MIL")
	_verify_faction_snapshot(merch, snap_merch, "TC-FSTRAT.7-SIM-MERCH")

	# neutral_tribe: pre-existing simulation rule intentionally increments population (+1 per day)
	_assert_eq(tribe.population, snap_tribe["population"] + 5, "TC-FSTRAT.7-SIM-TRIBE-POP", "neutral_tribe population increased by exactly 5 across 5 simulation days")
	# neutral_tribe: all other fields remain completely unmutated by strategic planner integration
	_assert_eq(str(tribe.id), snap_tribe["id"], "TC-FSTRAT.7-SIM-TRIBE-ID", "id unmutated")
	_assert_eq(tribe.name, snap_tribe["name"], "TC-FSTRAT.7-SIM-TRIBE-NAME", "name unmutated")
	_assert_eq(tribe.type, snap_tribe["type"], "TC-FSTRAT.7-SIM-TRIBE-TYPE", "type unmutated")
	_assert_eq(tribe.opinion, snap_tribe["opinion"], "TC-FSTRAT.7-SIM-TRIBE-OPINION", "opinion unmutated")
	_assert_eq(tribe.military_power, snap_tribe["military_power"], "TC-FSTRAT.7-SIM-TRIBE-MIL", "military_power unmutated")
	_assert_eq(tribe.stability, snap_tribe["stability"], "TC-FSTRAT.7-SIM-TRIBE-STAB", "stability unmutated")
	_assert_eq(tribe.is_at_war, snap_tribe["is_at_war"], "TC-FSTRAT.7-SIM-TRIBE-WAR", "is_at_war unmutated")
	_assert_eq(tribe.has_nap, snap_tribe["has_nap"], "TC-FSTRAT.7-SIM-TRIBE-NAP", "has_nap unmutated")
	_assert_eq(tribe.has_alliance, snap_tribe["has_alliance"], "TC-FSTRAT.7-SIM-TRIBE-ALLIANCE", "has_alliance unmutated")
	_assert_eq(tribe.strategic_goal, snap_tribe["strategic_goal"], "TC-FSTRAT.7-SIM-TRIBE-GOAL", "strategic_goal unmutated")
	_assert_eq(tribe.existence_status, snap_tribe["existence_status"], "TC-FSTRAT.7-SIM-TRIBE-STATUS", "existence_status unmutated")
	_assert_eq(tribe.resources.size(), snap_tribe["resources"].size(), "TC-FSTRAT.7-SIM-TRIBE-RES-COUNT", "resources count unmutated")
	for k in snap_tribe["resources"]:
		_assert_eq(tribe.resources.get(k, 0), snap_tribe["resources"][k], "TC-FSTRAT.7-SIM-TRIBE-RES-" + str(k).to_upper(), "resource " + str(k) + " unmutated")
