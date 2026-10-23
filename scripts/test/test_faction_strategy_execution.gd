extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — Package 1S: Faction Strategic Intent Execution
## Validates deterministic, bounded, atomic, and idempotent faction intent execution:
## - TC-FEXEC.1: Valid military_buildup execution (resource cost, military_power gain, cap, wartime compatibility)
## - TC-FEXEC.2: Valid trade_expansion execution & wartime block (tools -> gold + stability, cap, BLOCKED_BY_WAR)
## - TC-FEXEC.3: Valid community_development execution & neutral tribe pre-ascension compatibility
## - TC-FEXEC.4: Valid power_consolidation execution & post-ascension state gating
## - TC-FEXEC.5: Insufficient resources fail-closed (no partial deduction, no attribute mutation)
## - TC-FEXEC.6: Cap reached fail-closed (no wasted resource deduction at ceiling)
## - TC-FEXEC.7: Inactive factions (in_exile, eliminated) rejected with zero mutation & zero daily execution
## - TC-FEXEC.8: Invalid goal / status / decision / day / null faction fail-closed
## - TC-FEXEC.9: Same-day idempotency & deterministic alphabetical execution order
## - TC-FEXEC.10: Ascension-day ordering & non-duplication with power_consolidation
## - TC-FEXEC.11: FactionStrategyPlanner remains 100% pure and side-effect-free
## - TC-FEXEC.12: Deterministic multi-day simulation equivalence across identical setups
## - TC-FEXEC.13: Save/Load roundtrip, legacy save fallback, double-load idempotency & fail-closed validation
## - TC-FEXEC.14: Cross-system regression (diplomacy, war, raid, offensive campaign, world events)

const FactionDataScript = preload("res://scripts/factions/faction_data.gd")
const FactionStrategyPlannerScript = preload("res://scripts/factions/faction_strategy_planner.gd")
const FactionStrategyExecutorScript = preload("res://scripts/factions/faction_strategy_executor.gd")
const FactionManagerScript = preload("res://scripts/factions/faction_manager.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")

var frame_count: int = 0
var world_instance: Node = null
var failures: int = 0
var passed_checks: int = 0

func _init() -> void:
	print("\n========================================================")
	print("  STARTING PACKAGE 1S FACTION STRATEGY EXECUTION TESTS")
	print("========================================================\n")
	world_instance = WorldViewScene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count == 3:
		_run_all_tests()
		print("\n--------------------------------------------------------")
		print("  Checks Passed: %d | Failures: %d" % [passed_checks, failures])
		if failures == 0:
			print("  ALL PACKAGE 1S FACTION STRATEGY EXECUTION TESTS PASSED! (Exit Code 0)")
			print("--------------------------------------------------------\n")
			quit(0)
			return true
		else:
			printerr("  PACKAGE 1S FACTION STRATEGY EXECUTION TESTS FAILED WITH %d FAILURES! (Exit Code 1)" % failures)
			print("--------------------------------------------------------\n")
			quit(1)
			return true
	return false

func _assert_true(cond: bool, test_name: String, msg: String = "") -> void:
	if not cond:
		failures += 1
		printerr("  ❌ FAIL [%s]: Expected true. %s" % [test_name, msg])
	else:
		passed_checks += 1
		print("  ✅ PASS [%s]%s" % [test_name, (" - " + msg) if msg != "" else ""])

func _assert_false(cond: bool, test_name: String, msg: String = "") -> void:
	if cond:
		failures += 1
		printerr("  ❌ FAIL [%s]: Expected false. %s" % [test_name, msg])
	else:
		passed_checks += 1
		print("  ✅ PASS [%s]%s" % [test_name, (" - " + msg) if msg != "" else ""])

func _assert_eq(actual: Variant, expected: Variant, test_name: String, msg: String = "") -> void:
	if actual != expected:
		failures += 1
		printerr("  ❌ FAIL [%s]: Expected %s, got %s. %s" % [test_name, str(expected), str(actual), msg])
	else:
		passed_checks += 1
		print("  ✅ PASS [%s]: %s == %s%s" % [test_name, str(actual), str(expected), (" - " + msg) if msg != "" else ""])

func _assert_approx(actual: float, expected: float, test_name: String, tol: float = 0.001) -> void:
	if abs(actual - expected) > tol:
		failures += 1
		printerr("  ❌ FAIL [%s]: Expected approx %f, got %f (tol %f)" % [test_name, expected, actual, tol])
	else:
		passed_checks += 1
		print("  ✅ PASS [%s]: Approx %f == %f" % [test_name, actual, expected])

func _take_snapshot(fac: FactionData) -> Dictionary:
	var res_copy: Dictionary = {}
	for k in fac.resources:
		res_copy[k] = fac.resources[k]
	return {
		"id": str(fac.id),
		"name": str(fac.name),
		"type": str(fac.type),
		"disposition": int(fac.disposition),
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

func _verify_snapshot(fac: FactionData, snap: Dictionary, prefix: String) -> void:
	_assert_eq(str(fac.id), snap["id"], prefix + "-ID")
	_assert_eq(fac.name, snap["name"], prefix + "-NAME")
	_assert_eq(fac.type, snap["type"], prefix + "-TYPE")
	_assert_eq(fac.disposition, snap["disposition"], prefix + "-DISP")
	_assert_approx(fac.opinion, snap["opinion"], prefix + "-OPINION")
	_assert_approx(fac.military_power, snap["military_power"], prefix + "-MIL")
	_assert_approx(fac.stability, snap["stability"], prefix + "-STAB")
	_assert_eq(fac.population, snap["population"], prefix + "-POP")
	_assert_eq(fac.is_at_war, snap["is_at_war"], prefix + "-WAR")
	_assert_eq(fac.has_nap, snap["has_nap"], prefix + "-NAP")
	_assert_eq(fac.has_alliance, snap["has_alliance"], prefix + "-ALLIANCE")
	_assert_eq(fac.strategic_goal, snap["strategic_goal"], prefix + "-GOAL")
	_assert_eq(fac.existence_status, snap["existence_status"], prefix + "-STATUS")
	_assert_eq(fac.resources.size(), snap["resources"].size(), prefix + "-RES-COUNT")
	for k in snap["resources"]:
		_assert_eq(fac.resources.get(k, 0), snap["resources"][k], prefix + "-RES-" + str(k).to_upper())

func _run_all_tests() -> void:
	test_tc_fexec_1_military_buildup()
	test_tc_fexec_2_trade_expansion()
	test_tc_fexec_3_community_development()
	test_tc_fexec_4_power_consolidation()
	test_tc_fexec_5_insufficient_resources_fail_closed()
	test_tc_fexec_6_cap_reached_fail_closed()
	test_tc_fexec_7_inactive_factions_gating()
	test_tc_fexec_8_invalid_input_fail_closed()
	test_tc_fexec_9_same_day_idempotency_and_order()
	test_tc_fexec_10_ascension_and_consolidation_ordering()
	test_tc_fexec_11_planner_remains_side_effect_free()
	test_tc_fexec_12_deterministic_multi_day_equivalence()
	test_tc_fexec_13_save_load_persistence_and_validation()
	test_tc_fexec_14_cross_system_regression()

# -----------------------------------------------------------------------------
# TC-FEXEC.1: Valid military_buildup execution
# -----------------------------------------------------------------------------
func test_tc_fexec_1_military_buildup() -> void:
	print("\n--- TC-FEXEC.1: Valid military_buildup Execution ---")
	var fm := FactionManagerScript.new()
	var mil: FactionData = fm.get_faction("rival_military")

	_assert_approx(mil.military_power, 75.0, "TC-FEXEC.1-PRE-MIL")
	_assert_eq(mil.resources.get(EconomyConfigScript.RES_METAL, 0), 80, "TC-FEXEC.1-PRE-METAL")
	_assert_eq(mil.resources.get(EconomyConfigScript.RES_GOLD, 0), 150, "TC-FEXEC.1-PRE-GOLD")

	var exec_res: Dictionary = fm.execute_faction_strategic_intent("rival_military", 1)
	_assert_true(exec_res.get("success", false), "TC-FEXEC.1-SUCCESS")
	_assert_eq(exec_res.get("intent_id", ""), FactionStrategyPlannerScript.INTENT_MILITARY_BUILDUP, "TC-FEXEC.1-INTENT")
	_assert_eq(exec_res.get("reason_code", ""), FactionStrategyExecutorScript.REASON_EXECUTED, "TC-FEXEC.1-REASON")
	_assert_eq(exec_res.get("posture", ""), "peacetime", "TC-FEXEC.1-POSTURE-PEACE")
	_assert_approx(mil.military_power, 80.0, "TC-FEXEC.1-POST-MIL")
	_assert_eq(mil.resources.get(EconomyConfigScript.RES_METAL, 0), 70, "TC-FEXEC.1-POST-METAL")
	_assert_eq(mil.resources.get(EconomyConfigScript.RES_GOLD, 0), 125, "TC-FEXEC.1-POST-GOLD")
	_assert_eq(mil.strategic_goal, FactionDataScript.GOAL_MILITARY_EXPANSION, "TC-FEXEC.1-GOAL-INTACT")
	_assert_eq(mil.existence_status, FactionDataScript.STATUS_ACTIVE, "TC-FEXEC.1-STATUS-INTACT")

	# Wartime execution of military_buildup succeeds with wartime posture
	mil.is_at_war = true
	var war_res: Dictionary = fm.execute_faction_strategic_intent("rival_military", 2)
	_assert_true(war_res.get("success", false), "TC-FEXEC.1-WAR-SUCCESS")
	_assert_eq(war_res.get("posture", ""), "wartime", "TC-FEXEC.1-WAR-POSTURE")
	_assert_approx(mil.military_power, 85.0, "TC-FEXEC.1-WAR-MIL")
	_assert_eq(mil.resources.get(EconomyConfigScript.RES_METAL, 0), 60, "TC-FEXEC.1-WAR-METAL")
	_assert_eq(mil.resources.get(EconomyConfigScript.RES_GOLD, 0), 100, "TC-FEXEC.1-WAR-GOLD")

	# Clamping near cap (118.0 -> 120.0)
	mil.military_power = 118.0
	var cap_res: Dictionary = fm.execute_faction_strategic_intent("rival_military", 3)
	_assert_true(cap_res.get("success", false), "TC-FEXEC.1-NEAR-CAP-OK")
	_assert_approx(mil.military_power, FactionStrategyExecutorScript.MILITARY_BUILDUP_CAP_POWER, "TC-FEXEC.1-CLAMPED-120")
	_assert_approx(float(cap_res["changes"].get("military_power_delta", 0.0)), 2.0, "TC-FEXEC.1-DELTA-2")

# -----------------------------------------------------------------------------
# TC-FEXEC.2: Valid trade_expansion execution & wartime block
# -----------------------------------------------------------------------------
func test_tc_fexec_2_trade_expansion() -> void:
	print("\n--- TC-FEXEC.2: Valid trade_expansion Execution & Wartime Block ---")
	var fm := FactionManagerScript.new()
	var merch: FactionData = fm.get_faction("rival_merchant")

	_assert_eq(merch.resources.get(EconomyConfigScript.RES_GOLD, 0), 400, "TC-FEXEC.2-PRE-GOLD")
	_assert_eq(merch.resources.get(EconomyConfigScript.RES_TOOLS, 0), 50, "TC-FEXEC.2-PRE-TOOLS")
	_assert_approx(merch.stability, 70.0, "TC-FEXEC.2-PRE-STAB")

	var exec_res: Dictionary = fm.execute_faction_strategic_intent("rival_merchant", 1)
	_assert_true(exec_res.get("success", false), "TC-FEXEC.2-SUCCESS")
	_assert_eq(exec_res.get("intent_id", ""), FactionStrategyPlannerScript.INTENT_TRADE_EXPANSION, "TC-FEXEC.2-INTENT")
	_assert_eq(exec_res.get("reason_code", ""), FactionStrategyExecutorScript.REASON_EXECUTED, "TC-FEXEC.2-REASON")
	_assert_eq(merch.resources.get(EconomyConfigScript.RES_TOOLS, 0), 45, "TC-FEXEC.2-POST-TOOLS")
	_assert_eq(merch.resources.get(EconomyConfigScript.RES_GOLD, 0), 430, "TC-FEXEC.2-POST-GOLD")
	_assert_approx(merch.stability, 72.0, "TC-FEXEC.2-POST-STAB")

	# Wartime blocks trade_expansion without consuming tools or changing gold/stability
	merch.is_at_war = true
	var snap_war: Dictionary = _take_snapshot(merch)
	var war_res: Dictionary = fm.execute_faction_strategic_intent("rival_merchant", 2)
	_assert_false(war_res.get("success", true), "TC-FEXEC.2-WAR-BLOCKED")
	_assert_eq(war_res.get("reason_code", ""), FactionStrategyExecutorScript.REASON_BLOCKED_BY_WAR, "TC-FEXEC.2-WAR-REASON")
	_verify_snapshot(merch, snap_war, "TC-FEXEC.2-WAR-UNCHANGED")

	# Peace restores trade_expansion capability on the same day since Day 2 had not executed yet
	merch.is_at_war = false
	var peace_res: Dictionary = fm.execute_faction_strategic_intent("rival_merchant", 2)
	_assert_true(peace_res.get("success", false), "TC-FEXEC.2-PEACE-RESUMED")
	_assert_eq(merch.resources.get(EconomyConfigScript.RES_TOOLS, 0), 40, "TC-FEXEC.2-PEACE-TOOLS")
	_assert_eq(merch.resources.get(EconomyConfigScript.RES_GOLD, 0), 460, "TC-FEXEC.2-PEACE-GOLD")
	_assert_approx(merch.stability, 74.0, "TC-FEXEC.2-PEACE-STAB")

# -----------------------------------------------------------------------------
# TC-FEXEC.3: Valid community_development execution
# -----------------------------------------------------------------------------
func test_tc_fexec_3_community_development() -> void:
	print("\n--- TC-FEXEC.3: Valid community_development Execution ---")
	# 1. Direct execution on an active community_growth faction consumes wood & herbs and boosts pop & stability
	var fm := FactionManagerScript.new()
	var custom_comm := FactionDataScript.new(
		"custom_village",
		"Thôn Bình An",
		"custom_settlement",
		FactionDataScript.Disposition.FRIENDLY,
		25.0,
		30.0,
		FactionDataScript.GOAL_COMMUNITY_GROWTH,
		FactionDataScript.STATUS_ACTIVE
	)
	custom_comm.population = 40
	custom_comm.stability = 70.0
	custom_comm.resources = {EconomyConfigScript.RES_WOOD: 50, EconomyConfigScript.RES_HERBS: 25}
	fm._factions[custom_comm.id] = custom_comm

	var exec_res: Dictionary = fm.execute_faction_strategic_intent("custom_village", 1)
	_assert_true(exec_res.get("success", false), "TC-FEXEC.3-DIRECT-OK")
	_assert_eq(exec_res.get("intent_id", ""), FactionStrategyPlannerScript.INTENT_COMMUNITY_DEVELOPMENT, "TC-FEXEC.3-INTENT")
	_assert_eq(exec_res.get("reason_code", ""), FactionStrategyExecutorScript.REASON_EXECUTED, "TC-FEXEC.3-REASON")
	_assert_eq(custom_comm.population, 41, "TC-FEXEC.3-POP")
	_assert_approx(custom_comm.stability, 72.0, "TC-FEXEC.3-STAB")
	_assert_eq(custom_comm.resources.get(EconomyConfigScript.RES_WOOD, 0), 40, "TC-FEXEC.3-WOOD")
	_assert_eq(custom_comm.resources.get(EconomyConfigScript.RES_HERBS, 0), 20, "TC-FEXEC.3-HERBS")

	# 2. Pre-ascension neutral_tribe in update_daily_simulation grows +1 pop/day and preserves Wood/Herbs for ascension
	var fm2 := FactionManagerScript.new()
	var tribe: FactionData = fm2.get_faction("neutral_tribe")
	var exec_signals: Array[Dictionary] = []
	fm2.strategic_intent_executed.connect(func(fid: String, res: Dictionary):
		if fid == "neutral_tribe":
			exec_signals.append(res)
	)
	fm2.update_daily_simulation(1)
	_assert_eq(exec_signals.size(), 1, "TC-FEXEC.3-TRIBE-SIG")
	_assert_true(exec_signals[0].get("success", false), "TC-FEXEC.3-TRIBE-SUCCESS")
	_assert_eq(tribe.population, 36, "TC-FEXEC.3-TRIBE-POP-36")
	_assert_eq(tribe.resources.get(EconomyConfigScript.RES_WOOD, 0), 120, "TC-FEXEC.3-TRIBE-WOOD-120")
	_assert_eq(tribe.resources.get(EconomyConfigScript.RES_HERBS, 0), 60, "TC-FEXEC.3-TRIBE-HERBS-60")

# -----------------------------------------------------------------------------
# TC-FEXEC.4: Valid power_consolidation execution
# -----------------------------------------------------------------------------
func test_tc_fexec_4_power_consolidation() -> void:
	print("\n--- TC-FEXEC.4: Valid power_consolidation Execution ---")
	var fm := FactionManagerScript.new()
	var tribe: FactionData = fm.get_faction("neutral_tribe")
	tribe.type = FactionManagerScript.ASCENSION_NEW_TYPE
	tribe.name = FactionManagerScript.ASCENSION_NEW_NAME
	tribe.strategic_goal = FactionDataScript.GOAL_CONSOLIDATE_POWER
	tribe.military_power = 55.0
	tribe.stability = 85.0
	tribe.resources = {EconomyConfigScript.RES_WOOD: 120, EconomyConfigScript.RES_HERBS: 60}

	var exec_res: Dictionary = fm.execute_faction_strategic_intent("neutral_tribe", 11)
	_assert_true(exec_res.get("success", false), "TC-FEXEC.4-SUCCESS")
	_assert_eq(exec_res.get("intent_id", ""), FactionStrategyPlannerScript.INTENT_POWER_CONSOLIDATION, "TC-FEXEC.4-INTENT")
	_assert_eq(exec_res.get("reason_code", ""), FactionStrategyExecutorScript.REASON_EXECUTED, "TC-FEXEC.4-REASON")
	_assert_approx(tribe.military_power, 59.0, "TC-FEXEC.4-POST-MIL")
	_assert_approx(tribe.stability, 87.0, "TC-FEXEC.4-POST-STAB")
	_assert_eq(tribe.resources.get(EconomyConfigScript.RES_WOOD, 0), 105, "TC-FEXEC.4-POST-WOOD")
	_assert_eq(tribe.resources.get(EconomyConfigScript.RES_HERBS, 0), 50, "TC-FEXEC.4-POST-HERBS")
	_assert_eq(tribe.strategic_goal, FactionDataScript.GOAL_CONSOLIDATE_POWER, "TC-FEXEC.4-GOAL-INTACT")
	_assert_eq(tribe.existence_status, FactionDataScript.STATUS_ACTIVE, "TC-FEXEC.4-STATUS-INTACT")

	# Non-ascended faction with consolidate_power goal is rejected fail-closed
	var unascended := FactionDataScript.new(
		"fake_consolidator",
		"Giả Mạo",
		"neutral_tribe",
		FactionDataScript.Disposition.NEUTRAL,
		0.0,
		40.0,
		FactionDataScript.GOAL_CONSOLIDATE_POWER,
		FactionDataScript.STATUS_ACTIVE
	)
	unascended.resources = {EconomyConfigScript.RES_WOOD: 100, EconomyConfigScript.RES_HERBS: 100}
	fm._factions[unascended.id] = unascended
	var snap_fake: Dictionary = _take_snapshot(unascended)
	var fake_res: Dictionary = fm.execute_faction_strategic_intent("fake_consolidator", 11)
	_assert_false(fake_res.get("success", true), "TC-FEXEC.4-UNASCENDED-REJECT")
	_assert_eq(fake_res.get("reason_code", ""), FactionStrategyExecutorScript.REASON_INELIGIBLE_CONSOLIDATION_STATE, "TC-FEXEC.4-UNASCENDED-REASON")
	_verify_snapshot(unascended, snap_fake, "TC-FEXEC.4-UNASCENDED-SNAP")

# -----------------------------------------------------------------------------
# TC-FEXEC.5: Insufficient resources fail-closed
# -----------------------------------------------------------------------------
func test_tc_fexec_5_insufficient_resources_fail_closed() -> void:
	print("\n--- TC-FEXEC.5: Insufficient Resources Fail-Closed ---")
	var fm := FactionManagerScript.new()

	# 1. military_buildup: enough metal (10), insufficient gold (24 < 25) -> zero metal deducted
	var mil: FactionData = fm.get_faction("rival_military")
	mil.resources = {EconomyConfigScript.RES_METAL: 10, EconomyConfigScript.RES_GOLD: 24}
	var snap_mil: Dictionary = _take_snapshot(mil)
	var res_mil: Dictionary = fm.execute_faction_strategic_intent("rival_military", 1)
	_assert_false(res_mil.get("success", true), "TC-FEXEC.5-MIL-FAIL")
	_assert_eq(res_mil.get("reason_code", ""), FactionStrategyExecutorScript.REASON_INSUFFICIENT_RESOURCES, "TC-FEXEC.5-MIL-REASON")
	_verify_snapshot(mil, snap_mil, "TC-FEXEC.5-MIL-SNAP")

	# 2. trade_expansion: insufficient tools (4 < 5)
	var merch: FactionData = fm.get_faction("rival_merchant")
	merch.resources = {EconomyConfigScript.RES_GOLD: 400, EconomyConfigScript.RES_TOOLS: 4}
	var snap_merch: Dictionary = _take_snapshot(merch)
	var res_merch: Dictionary = fm.execute_faction_strategic_intent("rival_merchant", 1)
	_assert_false(res_merch.get("success", true), "TC-FEXEC.5-MERCH-FAIL")
	_assert_eq(res_merch.get("reason_code", ""), FactionStrategyExecutorScript.REASON_INSUFFICIENT_RESOURCES, "TC-FEXEC.5-MERCH-REASON")
	_verify_snapshot(merch, snap_merch, "TC-FEXEC.5-MERCH-SNAP")

	# 3. community_development: enough wood (10), insufficient herbs (4 < 5) -> zero wood deducted
	var comm := FactionDataScript.new("comm_poor", "Thôn Nghèo", "custom_settlement", FactionDataScript.Disposition.FRIENDLY, 20.0, 25.0, FactionDataScript.GOAL_COMMUNITY_GROWTH)
	comm.resources = {EconomyConfigScript.RES_WOOD: 10, EconomyConfigScript.RES_HERBS: 4}
	fm._factions[comm.id] = comm
	var snap_comm: Dictionary = _take_snapshot(comm)
	var res_comm: Dictionary = fm.execute_faction_strategic_intent("comm_poor", 1)
	_assert_false(res_comm.get("success", true), "TC-FEXEC.5-COMM-FAIL")
	_assert_eq(res_comm.get("reason_code", ""), FactionStrategyExecutorScript.REASON_INSUFFICIENT_RESOURCES, "TC-FEXEC.5-COMM-REASON")
	_verify_snapshot(comm, snap_comm, "TC-FEXEC.5-COMM-SNAP")

	# 4. power_consolidation: enough wood (15), insufficient herbs (9 < 10) -> zero wood deducted
	var tribe: FactionData = fm.get_faction("neutral_tribe")
	tribe.type = FactionManagerScript.ASCENSION_NEW_TYPE
	tribe.strategic_goal = FactionDataScript.GOAL_CONSOLIDATE_POWER
	tribe.resources = {EconomyConfigScript.RES_WOOD: 15, EconomyConfigScript.RES_HERBS: 9}
	var snap_tribe: Dictionary = _take_snapshot(tribe)
	var res_tribe: Dictionary = fm.execute_faction_strategic_intent("neutral_tribe", 1)
	_assert_false(res_tribe.get("success", true), "TC-FEXEC.5-CONSOL-FAIL")
	_assert_eq(res_tribe.get("reason_code", ""), FactionStrategyExecutorScript.REASON_INSUFFICIENT_RESOURCES, "TC-FEXEC.5-CONSOL-REASON")
	_verify_snapshot(tribe, snap_tribe, "TC-FEXEC.5-CONSOL-SNAP")

# -----------------------------------------------------------------------------
# TC-FEXEC.6: Cap reached fail-closed (no wasted resource deduction)
# -----------------------------------------------------------------------------
func test_tc_fexec_6_cap_reached_fail_closed() -> void:
	print("\n--- TC-FEXEC.6: Cap Reached Fail-Closed ---")
	var fm := FactionManagerScript.new()

	# 1. military_buildup at cap (120.0)
	var mil: FactionData = fm.get_faction("rival_military")
	mil.military_power = FactionStrategyExecutorScript.MILITARY_BUILDUP_CAP_POWER
	var snap_mil: Dictionary = _take_snapshot(mil)
	var res_mil: Dictionary = fm.execute_faction_strategic_intent("rival_military", 1)
	_assert_false(res_mil.get("success", true), "TC-FEXEC.6-MIL-AT-CAP")
	_assert_eq(res_mil.get("reason_code", ""), FactionStrategyExecutorScript.REASON_AT_CAP, "TC-FEXEC.6-MIL-REASON")
	_verify_snapshot(mil, snap_mil, "TC-FEXEC.6-MIL-SNAP")

	# 2. trade_expansion at cap (gold == 1000 and stability == 95.0)
	var merch: FactionData = fm.get_faction("rival_merchant")
	merch.resources[EconomyConfigScript.RES_GOLD] = FactionStrategyExecutorScript.TRADE_EXPANSION_CAP_GOLD
	merch.stability = FactionStrategyExecutorScript.TRADE_EXPANSION_CAP_STABILITY
	var snap_merch: Dictionary = _take_snapshot(merch)
	var res_merch: Dictionary = fm.execute_faction_strategic_intent("rival_merchant", 1)
	_assert_false(res_merch.get("success", true), "TC-FEXEC.6-MERCH-AT-CAP")
	_assert_eq(res_merch.get("reason_code", ""), FactionStrategyExecutorScript.REASON_AT_CAP, "TC-FEXEC.6-MERCH-REASON")
	_verify_snapshot(merch, snap_merch, "TC-FEXEC.6-MERCH-SNAP")

	# 3. community_development at cap (pop == 80 and stability == 90.0)
	var comm := FactionDataScript.new("comm_cap", "Thôn Đầy", "custom_settlement", FactionDataScript.Disposition.FRIENDLY, 30.0, 30.0, FactionDataScript.GOAL_COMMUNITY_GROWTH)
	comm.population = FactionStrategyExecutorScript.COMMUNITY_DEV_CAP_POPULATION
	comm.stability = FactionStrategyExecutorScript.COMMUNITY_DEV_CAP_STABILITY
	comm.resources = {EconomyConfigScript.RES_WOOD: 100, EconomyConfigScript.RES_HERBS: 100}
	fm._factions[comm.id] = comm
	var snap_comm: Dictionary = _take_snapshot(comm)
	var res_comm: Dictionary = fm.execute_faction_strategic_intent("comm_cap", 1)
	_assert_false(res_comm.get("success", true), "TC-FEXEC.6-COMM-AT-CAP")
	_assert_eq(res_comm.get("reason_code", ""), FactionStrategyExecutorScript.REASON_AT_CAP, "TC-FEXEC.6-COMM-REASON")
	_verify_snapshot(comm, snap_comm, "TC-FEXEC.6-COMM-SNAP")

	# 4. power_consolidation at cap (military_power == 90.0 and stability == 95.0)
	var tribe: FactionData = fm.get_faction("neutral_tribe")
	tribe.type = FactionManagerScript.ASCENSION_NEW_TYPE
	tribe.strategic_goal = FactionDataScript.GOAL_CONSOLIDATE_POWER
	tribe.military_power = FactionStrategyExecutorScript.POWER_CONSOLIDATION_CAP_POWER
	tribe.stability = FactionStrategyExecutorScript.POWER_CONSOLIDATION_CAP_STABILITY
	var snap_tribe: Dictionary = _take_snapshot(tribe)
	var res_tribe: Dictionary = fm.execute_faction_strategic_intent("neutral_tribe", 1)
	_assert_false(res_tribe.get("success", true), "TC-FEXEC.6-CONSOL-AT-CAP")
	_assert_eq(res_tribe.get("reason_code", ""), FactionStrategyExecutorScript.REASON_AT_CAP, "TC-FEXEC.6-CONSOL-REASON")
	_verify_snapshot(tribe, snap_tribe, "TC-FEXEC.6-CONSOL-SNAP")

# -----------------------------------------------------------------------------
# TC-FEXEC.7: Inactive factions (in_exile, eliminated) gating
# -----------------------------------------------------------------------------
func test_tc_fexec_7_inactive_factions_gating() -> void:
	print("\n--- TC-FEXEC.7: Inactive Factions Gating ---")
	var fm := FactionManagerScript.new()
	var mil: FactionData = fm.get_faction("rival_military")
	var merch: FactionData = fm.get_faction("rival_merchant")

	mil.existence_status = FactionDataScript.STATUS_IN_EXILE
	merch.existence_status = FactionDataScript.STATUS_ELIMINATED

	var snap_mil: Dictionary = _take_snapshot(mil)
	var snap_merch: Dictionary = _take_snapshot(merch)

	var exec_signals: Array[String] = []
	fm.strategic_intent_executed.connect(func(fid: String, _res: Dictionary):
		exec_signals.append(fid)
	)

	var res_mil: Dictionary = fm.execute_faction_strategic_intent("rival_military", 1)
	_assert_false(res_mil.get("success", true), "TC-FEXEC.7-EXILE-DIRECT")
	_assert_eq(res_mil.get("reason_code", ""), FactionStrategyExecutorScript.REASON_INELIGIBLE_STATUS, "TC-FEXEC.7-EXILE-REASON")
	_verify_snapshot(mil, snap_mil, "TC-FEXEC.7-EXILE-SNAP")

	var res_merch: Dictionary = fm.execute_faction_strategic_intent("rival_merchant", 1)
	_assert_false(res_merch.get("success", true), "TC-FEXEC.7-ELIM-DIRECT")
	_assert_eq(res_merch.get("reason_code", ""), FactionStrategyExecutorScript.REASON_INELIGIBLE_STATUS, "TC-FEXEC.7-ELIM-REASON")
	_verify_snapshot(merch, snap_merch, "TC-FEXEC.7-ELIM-SNAP")

	# Daily simulation skips inactive factions and emits only for active neutral_tribe
	fm.update_daily_simulation(1)
	_assert_eq(exec_signals.size(), 1, "TC-FEXEC.7-DAILY-SIG-COUNT")
	_assert_eq(exec_signals[0], "neutral_tribe", "TC-FEXEC.7-DAILY-ONLY-ACTIVE")
	_verify_snapshot(mil, snap_mil, "TC-FEXEC.7-EXILE-POST-DAILY")
	_verify_snapshot(merch, snap_merch, "TC-FEXEC.7-ELIM-POST-DAILY")

# -----------------------------------------------------------------------------
# TC-FEXEC.8: Invalid goal / status / decision / day / null faction fail-closed
# -----------------------------------------------------------------------------
func test_tc_fexec_8_invalid_input_fail_closed() -> void:
	print("\n--- TC-FEXEC.8: Invalid Input Fail-Closed ---")
	var executor := FactionStrategyExecutorScript.new()

	# 1. Null faction
	var null_res: Dictionary = executor.execute_intent(null, {}, 1)
	_assert_false(null_res.get("success", true), "TC-FEXEC.8-NULL-FAC")
	_assert_eq(null_res.get("reason_code", ""), FactionStrategyExecutorScript.REASON_ERR_NULL_FACTION, "TC-FEXEC.8-NULL-REASON")

	# 2. Invalid day (0 and -5)
	var fac := FactionDataScript.new("test_fac", "Thử Nghiệm", "rival_military", FactionDataScript.Disposition.NEUTRAL, 0.0, 60.0, FactionDataScript.GOAL_MILITARY_EXPANSION)
	fac.resources = {EconomyConfigScript.RES_METAL: 50, EconomyConfigScript.RES_GOLD: 100}
	var snap_fac: Dictionary = _take_snapshot(fac)
	var decision: Dictionary = FactionStrategyPlannerScript.evaluate_faction_intent(fac)

	var day0_res: Dictionary = executor.execute_intent(fac, decision, 0)
	_assert_false(day0_res.get("success", true), "TC-FEXEC.8-DAY0-FAIL")
	_assert_eq(day0_res.get("reason_code", ""), FactionStrategyExecutorScript.REASON_ERR_INVALID_DAY, "TC-FEXEC.8-DAY0-REASON")
	_verify_snapshot(fac, snap_fac, "TC-FEXEC.8-DAY0-SNAP")

	# 3. Empty/malformed decision dictionary
	var empty_dec_res: Dictionary = executor.execute_intent(fac, {}, 1)
	_assert_false(empty_dec_res.get("success", true), "TC-FEXEC.8-EMPTY-DEC")
	_assert_eq(empty_dec_res.get("reason_code", ""), FactionStrategyExecutorScript.REASON_ERR_INVALID_DECISION, "TC-FEXEC.8-EMPTY-DEC-REASON")
	_verify_snapshot(fac, snap_fac, "TC-FEXEC.8-EMPTY-DEC-SNAP")

	# 4. Mismatched decision intent vs faction strategic goal
	var mismatched_dec: Dictionary = decision.duplicate()
	mismatched_dec["intent_id"] = FactionStrategyPlannerScript.INTENT_TRADE_EXPANSION
	var mismatch_res: Dictionary = executor.execute_intent(fac, mismatched_dec, 1)
	_assert_false(mismatch_res.get("success", true), "TC-FEXEC.8-MISMATCH-FAIL")
	_assert_eq(mismatch_res.get("reason_code", ""), FactionStrategyExecutorScript.REASON_INELIGIBLE_INTENT, "TC-FEXEC.8-MISMATCH-REASON")
	_verify_snapshot(fac, snap_fac, "TC-FEXEC.8-MISMATCH-SNAP")

	# 5. Unrecognized strategic_goal and existence_status on faction
	fac.strategic_goal = "unknown_goal"
	var bad_goal_res: Dictionary = executor.execute_intent(fac, decision, 1)
	_assert_false(bad_goal_res.get("success", true), "TC-FEXEC.8-BAD-GOAL")
	_assert_eq(bad_goal_res.get("reason_code", ""), FactionStrategyExecutorScript.REASON_INELIGIBLE_INTENT, "TC-FEXEC.8-BAD-GOAL-REASON")

	fac.strategic_goal = FactionDataScript.GOAL_MILITARY_EXPANSION
	fac.existence_status = "corrupted_status"
	var bad_status_res: Dictionary = executor.execute_intent(fac, decision, 1)
	_assert_false(bad_status_res.get("success", true), "TC-FEXEC.8-BAD-STATUS")
	_assert_eq(bad_status_res.get("reason_code", ""), FactionStrategyExecutorScript.REASON_INELIGIBLE_STATUS, "TC-FEXEC.8-BAD-STATUS-REASON")

	# 6. BUG-1S-02: Direct executor rejects malformed/negative/non-integer/non-finite faction resources (including Gold in trade_expansion)
	var fm_res := FactionManagerScript.new()
	var merch_res: FactionData = fm_res.get_faction("rival_merchant")

	# 6a. Negative Gold on trade_expansion must fail closed without deducting Tools or mutating Gold/Stability/last_executed_day
	merch_res.resources = {EconomyConfigScript.RES_GOLD: -50, EconomyConfigScript.RES_TOOLS: 50}
	var snap_neg_gold: Dictionary = _take_snapshot(merch_res)
	var neg_gold_res: Dictionary = fm_res.execute_faction_strategic_intent("rival_merchant", 1)
	_assert_false(neg_gold_res.get("success", true), "TC-FEXEC.8-NEG-GOLD-REJECT")
	_assert_eq(neg_gold_res.get("reason_code", ""), FactionStrategyExecutorScript.REASON_ERR_INVALID_RESOURCES, "TC-FEXEC.8-NEG-GOLD-REASON")
	_verify_snapshot(merch_res, snap_neg_gold, "TC-FEXEC.8-NEG-GOLD-SNAP")
	_assert_eq(fm_res.get_faction_last_executed_day("rival_merchant"), -1, "TC-FEXEC.8-NEG-GOLD-LAST-DAY")

	# 6b. String Gold on trade_expansion must fail closed
	merch_res.resources = {EconomyConfigScript.RES_GOLD: "400", EconomyConfigScript.RES_TOOLS: 50}
	var snap_str_gold: Dictionary = _take_snapshot(merch_res)
	var str_gold_res: Dictionary = fm_res.execute_faction_strategic_intent("rival_merchant", 1)
	_assert_false(str_gold_res.get("success", true), "TC-FEXEC.8-STR-GOLD-REJECT")
	_assert_eq(str_gold_res.get("reason_code", ""), FactionStrategyExecutorScript.REASON_ERR_INVALID_RESOURCES, "TC-FEXEC.8-STR-GOLD-REASON")
	_verify_snapshot(merch_res, snap_str_gold, "TC-FEXEC.8-STR-GOLD-SNAP")
	_assert_eq(fm_res.get_faction_last_executed_day("rival_merchant"), -1, "TC-FEXEC.8-STR-GOLD-LAST-DAY")

	# 6c. Non-integer fractional float Gold (e.g. 400.5) on trade_expansion must fail closed
	merch_res.resources = {EconomyConfigScript.RES_GOLD: 400.5, EconomyConfigScript.RES_TOOLS: 50}
	var snap_frac_gold: Dictionary = _take_snapshot(merch_res)
	var frac_gold_res: Dictionary = fm_res.execute_faction_strategic_intent("rival_merchant", 1)
	_assert_false(frac_gold_res.get("success", true), "TC-FEXEC.8-FRAC-GOLD-REJECT")
	_assert_eq(frac_gold_res.get("reason_code", ""), FactionStrategyExecutorScript.REASON_ERR_INVALID_RESOURCES, "TC-FEXEC.8-FRAC-GOLD-REASON")
	_verify_snapshot(merch_res, snap_frac_gold, "TC-FEXEC.8-FRAC-GOLD-SNAP")
	_assert_eq(fm_res.get_faction_last_executed_day("rival_merchant"), -1, "TC-FEXEC.8-FRAC-GOLD-LAST-DAY")

	# 6d. Non-finite (INF / NaN) resource value on trade_expansion must fail closed
	merch_res.resources = {EconomyConfigScript.RES_GOLD: INF, EconomyConfigScript.RES_TOOLS: 50}
	var inf_gold_res: Dictionary = fm_res.execute_faction_strategic_intent("rival_merchant", 1)
	_assert_false(inf_gold_res.get("success", true), "TC-FEXEC.8-INF-GOLD-REJECT")
	_assert_eq(inf_gold_res.get("reason_code", ""), FactionStrategyExecutorScript.REASON_ERR_INVALID_RESOURCES, "TC-FEXEC.8-INF-GOLD-REASON")
	_assert_eq(merch_res.resources.get(EconomyConfigScript.RES_TOOLS, 0), 50, "TC-FEXEC.8-INF-GOLD-TOOLS-INTACT")
	_assert_eq(fm_res.get_faction_last_executed_day("rival_merchant"), -1, "TC-FEXEC.8-INF-GOLD-LAST-DAY")

	# 6e. Boolean resource value on military_buildup must fail closed without mutating state
	var mil_res: FactionData = fm_res.get_faction("rival_military")
	mil_res.resources = {EconomyConfigScript.RES_METAL: true, EconomyConfigScript.RES_GOLD: 150}
	var snap_bool_res: Dictionary = _take_snapshot(mil_res)
	var bool_res_out: Dictionary = fm_res.execute_faction_strategic_intent("rival_military", 1)
	_assert_false(bool_res_out.get("success", true), "TC-FEXEC.8-BOOL-RES-REJECT")
	_assert_eq(bool_res_out.get("reason_code", ""), FactionStrategyExecutorScript.REASON_ERR_INVALID_RESOURCES, "TC-FEXEC.8-BOOL-RES-REASON")
	_verify_snapshot(mil_res, snap_bool_res, "TC-FEXEC.8-BOOL-RES-SNAP")
	_assert_eq(fm_res.get_faction_last_executed_day("rival_military"), -1, "TC-FEXEC.8-BOOL-RES-LAST-DAY")

	# 6f. Restoring valid resources allows normal execution immediately
	merch_res.resources = {EconomyConfigScript.RES_GOLD: 400, EconomyConfigScript.RES_TOOLS: 50}
	var valid_merch_out: Dictionary = fm_res.execute_faction_strategic_intent("rival_merchant", 1)
	_assert_true(valid_merch_out.get("success", false), "TC-FEXEC.8-RECOVERED-VALID-EXEC")
	_assert_eq(merch_res.resources.get(EconomyConfigScript.RES_GOLD, 0), 430, "TC-FEXEC.8-RECOVERED-GOLD-430")
	_assert_eq(merch_res.resources.get(EconomyConfigScript.RES_TOOLS, 0), 45, "TC-FEXEC.8-RECOVERED-TOOLS-45")
	_assert_eq(fm_res.get_faction_last_executed_day("rival_merchant"), 1, "TC-FEXEC.8-RECOVERED-LAST-DAY-1")

# -----------------------------------------------------------------------------
# TC-FEXEC.9: Same-day idempotency & deterministic alphabetical order
# -----------------------------------------------------------------------------
func test_tc_fexec_9_same_day_idempotency_and_order() -> void:
	print("\n--- TC-FEXEC.9: Same-Day Idempotency & Deterministic Order ---")
	var fm := FactionManagerScript.new()
	var executed_order: Array[String] = []
	var executed_results: Array[Dictionary] = []

	fm.strategic_intent_executed.connect(func(fid: String, res: Dictionary):
		executed_order.append(fid)
		executed_results.append(res)
	)

	# First call on Day 5 executes all 3 factions in sorted order
	fm.update_daily_simulation(5)
	_assert_eq(executed_order, ["neutral_tribe", "rival_merchant", "rival_military"], "TC-FEXEC.9-ORDER")
	_assert_true(executed_results[0].get("success", false), "TC-FEXEC.9-FIRST-TRIBE-OK")
	_assert_true(executed_results[1].get("success", false), "TC-FEXEC.9-FIRST-MERCH-OK")
	_assert_true(executed_results[2].get("success", false), "TC-FEXEC.9-FIRST-MIL-OK")

	var mil: FactionData = fm.get_faction("rival_military")
	var merch: FactionData = fm.get_faction("rival_merchant")
	var tribe: FactionData = fm.get_faction("neutral_tribe")
	var snap_mil: Dictionary = _take_snapshot(mil)
	var snap_merch: Dictionary = _take_snapshot(merch)
	var snap_tribe: Dictionary = _take_snapshot(tribe)

	# Second call on the same Day 5 must NOT double-execute or mutate any faction
	executed_results.clear()
	fm.update_daily_simulation(5)
	_assert_eq(executed_results.size(), 3, "TC-FEXEC.9-SECOND-CALL-COUNT")
	for i in range(3):
		_assert_false(executed_results[i].get("success", true), "TC-FEXEC.9-SECOND-NO-EXEC-" + str(i))
		_assert_eq(executed_results[i].get("reason_code", ""), FactionStrategyExecutorScript.REASON_ALREADY_EXECUTED_TODAY, "TC-FEXEC.9-SECOND-REASON-" + str(i))

	_verify_snapshot(mil, snap_mil, "TC-FEXEC.9-IDEMP-MIL")
	_verify_snapshot(merch, snap_merch, "TC-FEXEC.9-IDEMP-MERCH")
	_verify_snapshot(tribe, snap_tribe, "TC-FEXEC.9-IDEMP-TRIBE")

# -----------------------------------------------------------------------------
# TC-FEXEC.10: Ascension-day ordering & non-duplication with power_consolidation
# -----------------------------------------------------------------------------
func test_tc_fexec_10_ascension_and_consolidation_ordering() -> void:
	print("\n--- TC-FEXEC.10: Ascension & power_consolidation Ordering ---")
	var fm := FactionManagerScript.new()
	var tribe: FactionData = fm.get_faction("neutral_tribe")
	tribe.population = 44 # Becomes 45 on Day 10 and ascends

	var tribe_execs: Array[Dictionary] = []
	fm.strategic_intent_executed.connect(func(fid: String, res: Dictionary):
		if fid == "neutral_tribe":
			tribe_execs.append(res)
	)

	# Day 10: tribe ascends to emerging_power (mil=55.0, stab=85.0, wood=120, herbs=60).
	# power_consolidation recognizes ASCENDED_THIS_TICK and does NOT double-boost or deduct wood/herbs on Day 10.
	fm.update_daily_simulation(10)
	_assert_eq(tribe_execs.size(), 1, "TC-FEXEC.10-D10-SIG-COUNT")
	var d10_exec: Dictionary = tribe_execs[0] if not tribe_execs.is_empty() else {}
	_assert_eq(tribe.type, FactionManagerScript.ASCENSION_NEW_TYPE, "TC-FEXEC.10-D10-TYPE")
	_assert_eq(tribe.strategic_goal, FactionDataScript.GOAL_CONSOLIDATE_POWER, "TC-FEXEC.10-D10-GOAL")
	_assert_eq(d10_exec.get("intent_id", ""), FactionStrategyPlannerScript.INTENT_POWER_CONSOLIDATION, "TC-FEXEC.10-D10-INTENT")
	_assert_false(d10_exec.get("success", true), "TC-FEXEC.10-D10-NO-DOUBLE-MUTATION")
	_assert_eq(d10_exec.get("reason_code", ""), FactionStrategyExecutorScript.REASON_ASCENDED_THIS_TICK, "TC-FEXEC.10-D10-REASON")
	_assert_approx(tribe.military_power, 55.0, "TC-FEXEC.10-D10-MIL-55")
	_assert_approx(tribe.stability, 85.0, "TC-FEXEC.10-D10-STAB-85")
	_assert_eq(tribe.resources.get(EconomyConfigScript.RES_WOOD, 0), 120, "TC-FEXEC.10-D10-WOOD-120")
	_assert_eq(tribe.resources.get(EconomyConfigScript.RES_HERBS, 0), 60, "TC-FEXEC.10-D10-HERBS-60")

	# Day 11: power_consolidation executes normally (-15 wood, -10 herbs, +4.0 mil, +2.0 stab)
	tribe_execs.clear()
	fm.update_daily_simulation(11)
	_assert_eq(tribe_execs.size(), 1, "TC-FEXEC.10-D11-SIG-COUNT")
	var d11_exec: Dictionary = tribe_execs[0] if not tribe_execs.is_empty() else {}
	_assert_true(d11_exec.get("success", false), "TC-FEXEC.10-D11-SUCCESS")
	_assert_eq(d11_exec.get("reason_code", ""), FactionStrategyExecutorScript.REASON_EXECUTED, "TC-FEXEC.10-D11-REASON")
	_assert_approx(tribe.military_power, 59.0, "TC-FEXEC.10-D11-MIL-59")
	_assert_approx(tribe.stability, 87.0, "TC-FEXEC.10-D11-STAB-87")
	_assert_eq(tribe.resources.get(EconomyConfigScript.RES_WOOD, 0), 105, "TC-FEXEC.10-D11-WOOD-105")
	_assert_eq(tribe.resources.get(EconomyConfigScript.RES_HERBS, 0), 50, "TC-FEXEC.10-D11-HERBS-50")

# -----------------------------------------------------------------------------
# TC-FEXEC.11: Planner remains 100% side-effect-free
# -----------------------------------------------------------------------------
func test_tc_fexec_11_planner_remains_side_effect_free() -> void:
	print("\n--- TC-FEXEC.11: Planner Remains Side-Effect-Free ---")
	var fm := FactionManagerScript.new()
	var mil: FactionData = fm.get_faction("rival_military")
	var merch: FactionData = fm.get_faction("rival_merchant")
	var tribe: FactionData = fm.get_faction("neutral_tribe")

	var snap_mil: Dictionary = _take_snapshot(mil)
	var snap_merch: Dictionary = _take_snapshot(merch)
	var snap_tribe: Dictionary = _take_snapshot(tribe)

	for i in range(30):
		FactionStrategyPlannerScript.evaluate_faction_intent(mil)
		FactionStrategyPlannerScript.evaluate_faction_intent(merch)
		FactionStrategyPlannerScript.evaluate_faction_intent(tribe)
		fm.get_faction_strategic_intent("rival_military")
		fm.get_faction_strategic_intent("rival_merchant")
		fm.get_faction_strategic_intent("neutral_tribe")
		fm.evaluate_all_strategic_intents()

	_verify_snapshot(mil, snap_mil, "TC-FEXEC.11-MIL")
	_verify_snapshot(merch, snap_merch, "TC-FEXEC.11-MERCH")
	_verify_snapshot(tribe, snap_tribe, "TC-FEXEC.11-TRIBE")
	_assert_eq(fm.get_faction_last_executed_day("rival_military"), -1, "TC-FEXEC.11-EXEC-DAY-UNTOUCHED")

# -----------------------------------------------------------------------------
# TC-FEXEC.12: Deterministic multi-day simulation equivalence
# -----------------------------------------------------------------------------
func test_tc_fexec_12_deterministic_multi_day_equivalence() -> void:
	print("\n--- TC-FEXEC.12: Deterministic Multi-Day Equivalence ---")
	var fm_a := FactionManagerScript.new()
	var fm_b := FactionManagerScript.new()

	for d in range(1, 15):
		fm_a.update_daily_simulation(d)
		fm_b.update_daily_simulation(d)

	for fid in ["neutral_tribe", "rival_merchant", "rival_military"]:
		var fac_a: FactionData = fm_a.get_faction(fid)
		var fac_b: FactionData = fm_b.get_faction(fid)
		var snap_b: Dictionary = _take_snapshot(fac_b)
		_verify_snapshot(fac_a, snap_b, "TC-FEXEC.12-" + fid.to_upper())
		_assert_eq(fm_a.get_faction_last_executed_day(fid), fm_b.get_faction_last_executed_day(fid), "TC-FEXEC.12-LAST-DAY-" + fid.to_upper())

# -----------------------------------------------------------------------------
# TC-FEXEC.13: Save/Load roundtrip, legacy save fallback, double-load & validation
# -----------------------------------------------------------------------------
func test_tc_fexec_13_save_load_persistence_and_validation() -> void:
	print("\n--- TC-FEXEC.13: Save/Load Persistence, Double-Load & Validation ---")
	var fm: FactionManager = world_instance.get("faction_mgr")
	var tm: Node = world_instance.get_node_or_null("/root/TimeManager")
	if tm != null:
		tm.set("current_day", 12)

	# Reset factions on live world_instance to deterministic state and run days 10..12
	fm._initialize_factions()
	var tribe: FactionData = fm.get_faction("neutral_tribe")
	tribe.population = 44
	fm.update_daily_simulation(10)
	fm.update_daily_simulation(11)
	fm.update_daily_simulation(12)

	var mil: FactionData = fm.get_faction("rival_military")
	var merch: FactionData = fm.get_faction("rival_merchant")
	var snap_mil_saved: Dictionary = _take_snapshot(mil)
	var snap_merch_saved: Dictionary = _take_snapshot(merch)
	var snap_tribe_saved: Dictionary = _take_snapshot(tribe)

	var saved_data: Dictionary = SaveManagerScript.serialize_world_state(world_instance)
	var val_ok: Dictionary = SaveManagerScript.validate_save_data(saved_data)
	_assert_true(val_ok.get("valid", false), "TC-FEXEC.13-VALID-SCHEMA", str(val_ok.get("error", "")))

	var exec_sec: Dictionary = saved_data.get("factions", {}).get("strategy_executor", {})
	_assert_true(exec_sec.has("last_executed_days"), "TC-FEXEC.13-HAS-LAST-DAYS")
	_assert_eq(int(exec_sec.get("last_executed_days", {}).get("rival_military", -1)), 12, "TC-FEXEC.13-SAVED-MIL-DAY12")
	_assert_eq(int(exec_sec.get("last_executed_days", {}).get("rival_merchant", -1)), 12, "TC-FEXEC.13-SAVED-MERCH-DAY12")
	_assert_eq(int(exec_sec.get("last_executed_days", {}).get("neutral_tribe", -1)), 12, "TC-FEXEC.13-SAVED-TRIBE-DAY12")

	# Perturb live state before loading
	mil.military_power = 10.0
	mil.resources = {EconomyConfigScript.RES_METAL: 1, EconomyConfigScript.RES_GOLD: 1}
	merch.resources = {EconomyConfigScript.RES_GOLD: 5, EconomyConfigScript.RES_TOOLS: 1}
	tribe.military_power = 20.0
	fm.deserialize_executor_state({})

	# Load 1
	var apply_1: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, saved_data)
	_assert_true(apply_1.get("success", false), "TC-FEXEC.13-APPLY-1")
	_verify_snapshot(fm.get_faction("rival_military"), snap_mil_saved, "TC-FEXEC.13-REST1-MIL")
	_verify_snapshot(fm.get_faction("rival_merchant"), snap_merch_saved, "TC-FEXEC.13-REST1-MERCH")
	_verify_snapshot(fm.get_faction("neutral_tribe"), snap_tribe_saved, "TC-FEXEC.13-REST1-TRIBE")
	_assert_eq(fm.get_faction_last_executed_day("rival_military"), 12, "TC-FEXEC.13-REST1-DAY12")

	# Re-running Day 12 after load does NOT re-execute Day 12 actions!
	fm.update_daily_simulation(12)
	_verify_snapshot(fm.get_faction("rival_military"), snap_mil_saved, "TC-FEXEC.13-NO-REEXEC-D12-MIL")
	_verify_snapshot(fm.get_faction("rival_merchant"), snap_merch_saved, "TC-FEXEC.13-NO-REEXEC-D12-MERCH")
	_verify_snapshot(fm.get_faction("neutral_tribe"), snap_tribe_saved, "TC-FEXEC.13-NO-REEXEC-D12-TRIBE")

	# Load 2 (Double-load idempotency)
	var apply_2: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, saved_data)
	_assert_true(apply_2.get("success", false), "TC-FEXEC.13-APPLY-2")
	_verify_snapshot(fm.get_faction("rival_military"), snap_mil_saved, "TC-FEXEC.13-REST2-MIL")

	# Legacy save lacking strategy_executor section loads cleanly and resets executor state to -1
	var legacy_data: Dictionary = saved_data.duplicate(true)
	legacy_data["factions"].erase("strategy_executor")
	var val_legacy: Dictionary = SaveManagerScript.validate_save_data(legacy_data)
	_assert_true(val_legacy.get("valid", false), "TC-FEXEC.13-LEGACY-VALID")
	var apply_legacy: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, legacy_data)
	_assert_true(apply_legacy.get("success", false), "TC-FEXEC.13-LEGACY-APPLY")
	_assert_eq(fm.get_faction_last_executed_day("rival_military"), -1, "TC-FEXEC.13-LEGACY-RESET-DAY")

	# Restore Day 12 save so last_executed_day is 12 before testing rejected payloads
	var apply_restore_d12: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, saved_data)
	_assert_true(apply_restore_d12.get("success", false), "TC-FEXEC.13-RESTORE-D12-BASELINE")
	_assert_eq(fm.get_faction_last_executed_day("rival_military"), 12, "TC-FEXEC.13-BASELINE-MIL-DAY12")
	_assert_eq(fm.get_faction_last_executed_day("rival_merchant"), 12, "TC-FEXEC.13-BASELINE-MERCH-DAY12")
	_assert_eq(fm.get_faction_last_executed_day("neutral_tribe"), 12, "TC-FEXEC.13-BASELINE-TRIBE-DAY12")

	# Take full live world snapshots BEFORE attempting rejected loads
	var live_snap_mil: Dictionary = _take_snapshot(fm.get_faction("rival_military"))
	var live_snap_merch: Dictionary = _take_snapshot(fm.get_faction("rival_merchant"))
	var live_snap_tribe: Dictionary = _take_snapshot(fm.get_faction("neutral_tribe"))

	# Fail-closed validation on corrupted strategy_executor payloads (BUG-1S-01)
	var bad_exec_type: Dictionary = saved_data.duplicate(true)
	bad_exec_type["factions"]["strategy_executor"] = "not_a_dict"
	_assert_false(SaveManagerScript.validate_save_data(bad_exec_type).get("valid", true), "TC-FEXEC.13-BAD-EXEC-TYPE")

	# 1. Future last_executed_days (13 > game_clock.current_day == 12) must be rejected before world mutation
	var bad_day_13: Dictionary = saved_data.duplicate(true)
	bad_day_13["game_clock"]["current_day"] = 12
	bad_day_13["factions"]["strategy_executor"]["last_executed_days"]["rival_military"] = 13
	bad_day_13["factions"]["factions"]["rival_military"]["military_power"] = 119.0
	var val_day_13: Dictionary = SaveManagerScript.validate_save_data(bad_day_13)
	_assert_false(val_day_13.get("valid", true), "TC-FEXEC.13-REJECT-FUTURE-DAY13", str(val_day_13.get("error", "")))
	var apply_day_13: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, bad_day_13)
	_assert_false(apply_day_13.get("success", true), "TC-FEXEC.13-APPLY-REJECT-FUTURE-DAY13")
	_verify_snapshot(fm.get_faction("rival_military"), live_snap_mil, "TC-FEXEC.13-NO-MUTATION-ON-DAY13-MIL")
	_assert_eq(fm.get_faction_last_executed_day("rival_military"), 12, "TC-FEXEC.13-NO-MUTATION-ON-DAY13-EXEC-DAY")

	# 2. Future last_tribe_growth_day (13 > game_clock.current_day == 12) must be rejected before world mutation
	var bad_tribe_growth_13: Dictionary = saved_data.duplicate(true)
	bad_tribe_growth_13["game_clock"]["current_day"] = 12
	bad_tribe_growth_13["factions"]["strategy_executor"]["last_tribe_growth_day"] = 13
	bad_tribe_growth_13["factions"]["factions"]["neutral_tribe"]["population"] = 79
	var val_growth_13: Dictionary = SaveManagerScript.validate_save_data(bad_tribe_growth_13)
	_assert_false(val_growth_13.get("valid", true), "TC-FEXEC.13-REJECT-FUTURE-TRIBE-GROWTH-13", str(val_growth_13.get("error", "")))
	var apply_growth_13: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, bad_tribe_growth_13)
	_assert_false(apply_growth_13.get("success", true), "TC-FEXEC.13-APPLY-REJECT-FUTURE-TRIBE-GROWTH-13")
	_verify_snapshot(fm.get_faction("neutral_tribe"), live_snap_tribe, "TC-FEXEC.13-NO-MUTATION-ON-GROWTH13-TRIBE")

	# 3. Separate test for day exceeding absolute ceiling 36500
	var bad_day_abs_ceiling: Dictionary = saved_data.duplicate(true)
	bad_day_abs_ceiling["factions"]["strategy_executor"] = {"last_executed_days": {"rival_military": 99999}}
	_assert_false(SaveManagerScript.validate_save_data(bad_day_abs_ceiling).get("valid", true), "TC-FEXEC.13-BAD-ABS-CEILING-DAY")

	var bad_day_neg: Dictionary = saved_data.duplicate(true)
	bad_day_neg["factions"]["strategy_executor"] = {"last_executed_days": {"rival_military": 0}}
	_assert_false(SaveManagerScript.validate_save_data(bad_day_neg).get("valid", true), "TC-FEXEC.13-BAD-ZERO-DAY")

	# 4. Second-layer deserialize defense: direct deserialize_executor_state filters future days (> current_day)
	var fm_deser := FactionManagerScript.new()
	fm_deser.deserialize_executor_state({
		"last_executed_days": {"rival_military": 13, "rival_merchant": 12},
		"last_tribe_growth_day": 13
	}, 12)
	_assert_eq(fm_deser.get_faction_last_executed_day("rival_military"), -1, "TC-FEXEC.13-DESER-FILTER-FUTURE-MIL")
	_assert_eq(fm_deser.get_faction_last_executed_day("rival_merchant"), 12, "TC-FEXEC.13-DESER-KEEP-VALID-MERCH")
	_assert_eq(fm_deser._last_tribe_growth_day, -1, "TC-FEXEC.13-DESER-FILTER-FUTURE-GROWTH")

	# 5. BUG-1S-02: Fail-closed validation on corrupted faction resources in save data (before any world mutation)
	# 5a. resources not a Dictionary
	var bad_res_not_dict: Dictionary = saved_data.duplicate(true)
	bad_res_not_dict["factions"]["factions"]["rival_merchant"]["resources"] = "not_a_dictionary"
	bad_res_not_dict["factions"]["factions"]["rival_merchant"]["stability"] = 10.0
	_assert_false(SaveManagerScript.validate_save_data(bad_res_not_dict).get("valid", true), "TC-FEXEC.13-REJECT-RES-NOT-DICT")
	_assert_false(SaveManagerScript.apply_loaded_state_to_world(world_instance, bad_res_not_dict).get("success", true), "TC-FEXEC.13-APPLY-REJECT-RES-NOT-DICT")
	_verify_snapshot(fm.get_faction("rival_merchant"), live_snap_merch, "TC-FEXEC.13-NO-MUTATION-RES-NOT-DICT")

	# 5b. Negative resource quantity
	var bad_res_neg: Dictionary = saved_data.duplicate(true)
	bad_res_neg["factions"]["factions"]["rival_merchant"]["resources"][EconomyConfigScript.RES_GOLD] = -10
	bad_res_neg["factions"]["factions"]["rival_merchant"]["stability"] = 15.0
	_assert_false(SaveManagerScript.validate_save_data(bad_res_neg).get("valid", true), "TC-FEXEC.13-REJECT-RES-NEGATIVE")
	_assert_false(SaveManagerScript.apply_loaded_state_to_world(world_instance, bad_res_neg).get("success", true), "TC-FEXEC.13-APPLY-REJECT-RES-NEGATIVE")
	_verify_snapshot(fm.get_faction("rival_merchant"), live_snap_merch, "TC-FEXEC.13-NO-MUTATION-RES-NEGATIVE")

	# 5c. Wrong resource value type (String / Bool / Fractional Float / INF)
	var bad_res_str: Dictionary = saved_data.duplicate(true)
	bad_res_str["factions"]["factions"]["rival_military"]["resources"][EconomyConfigScript.RES_METAL] = "eighty"
	_assert_false(SaveManagerScript.validate_save_data(bad_res_str).get("valid", true), "TC-FEXEC.13-REJECT-RES-STRING")
	_assert_false(SaveManagerScript.apply_loaded_state_to_world(world_instance, bad_res_str).get("success", true), "TC-FEXEC.13-APPLY-REJECT-RES-STRING")
	_verify_snapshot(fm.get_faction("rival_military"), live_snap_mil, "TC-FEXEC.13-NO-MUTATION-RES-STRING")

	var bad_res_bool: Dictionary = saved_data.duplicate(true)
	bad_res_bool["factions"]["factions"]["rival_military"]["resources"][EconomyConfigScript.RES_METAL] = true
	_assert_false(SaveManagerScript.validate_save_data(bad_res_bool).get("valid", true), "TC-FEXEC.13-REJECT-RES-BOOL")

	var bad_res_frac: Dictionary = saved_data.duplicate(true)
	bad_res_frac["factions"]["factions"]["rival_merchant"]["resources"][EconomyConfigScript.RES_TOOLS] = 12.5
	_assert_false(SaveManagerScript.validate_save_data(bad_res_frac).get("valid", true), "TC-FEXEC.13-REJECT-RES-FRACTIONAL")

	var bad_res_inf: Dictionary = saved_data.duplicate(true)
	bad_res_inf["factions"]["factions"]["rival_merchant"]["resources"][EconomyConfigScript.RES_GOLD] = INF
	_assert_false(SaveManagerScript.validate_save_data(bad_res_inf).get("valid", true), "TC-FEXEC.13-REJECT-RES-INF")

	var bad_res_key: Dictionary = saved_data.duplicate(true)
	bad_res_key["factions"]["factions"]["rival_merchant"]["resources"]["unknown_unobtanium"] = 50
	_assert_false(SaveManagerScript.validate_save_data(bad_res_key).get("valid", true), "TC-FEXEC.13-REJECT-RES-UNKNOWN-KEY")
	_verify_snapshot(fm.get_faction("rival_military"), live_snap_mil, "TC-FEXEC.13-FINAL-IMMUTABLE-MIL")
	_verify_snapshot(fm.get_faction("rival_merchant"), live_snap_merch, "TC-FEXEC.13-FINAL-IMMUTABLE-MERCH")
	_verify_snapshot(fm.get_faction("neutral_tribe"), live_snap_tribe, "TC-FEXEC.13-FINAL-IMMUTABLE-TRIBE")

# -----------------------------------------------------------------------------
# TC-FEXEC.14: Cross-system regression (diplomacy, war, raid, offensive campaign)
# -----------------------------------------------------------------------------
func test_tc_fexec_14_cross_system_regression() -> void:
	print("\n--- TC-FEXEC.14: Cross-System Regression ---")
	var fm: FactionManager = world_instance.get("faction_mgr")
	var campaign_mgr = world_instance.get("battle_campaign_mgr")
	var rm: Node = world_instance.get_node_or_null("/root/ResourceManager")

	fm._initialize_factions()
	var mil: FactionData = fm.get_faction("rival_military")

	# 1. Military buildup increases rival_military power from 75.0 -> 85.0 over 2 days
	fm.update_daily_simulation(1)
	fm.update_daily_simulation(2)
	_assert_approx(mil.military_power, 85.0, "TC-FEXEC.14-MIL-85")

	# 2. Declare war and verify raid force derivation reflects updated military_power (round(85/30) = 3 troops)
	var war_res: Dictionary = fm.declare_war("rival_military")
	_assert_true(war_res.get("success", false), "TC-FEXEC.14-DECLARE-WAR")
	_assert_true(mil.is_at_war, "TC-FEXEC.14-IS-AT-WAR")
	if campaign_mgr != null:
		var atk_force: Dictionary = campaign_mgr.construct_attacking_force(mil)
		_assert_eq(int(atk_force.get("troops", 0)), 3, "TC-FEXEC.14-ATK-TROOPS-3")

	# 3. Sign peace and send gift to active faction
	var peace_res: Dictionary = fm.propose_treaty("rival_military", "peace")
	_assert_true(peace_res.get("success", false), "TC-FEXEC.14-SIGN-PEACE")
	_assert_false(mil.is_at_war, "TC-FEXEC.14-PEACE-RESTORED")

	if rm != null:
		rm.add_resource(EconomyConfigScript.RES_GOLD, 100)
		var gift_res: Dictionary = fm.send_gift("rival_military", EconomyConfigScript.RES_GOLD, 20, rm)
		_assert_true(gift_res.get("success", false), "TC-FEXEC.14-GIFT-OK")
