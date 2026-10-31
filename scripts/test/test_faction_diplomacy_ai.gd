extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — Package 1T: Deterministic Autonomous Faction Diplomacy
## Validates deterministic, pure evaluation and bounded, idempotent execution of autonomous faction war/peace decisions:
## - TC-FDIP.1: Pure FactionDiplomacyPlanner war declaration eligibility (`military_expansion` & ascended `emerging_power`)
## - TC-FDIP.2: War declaration exact boundary thresholds (opinion -60 vs -59.99, mil 65 vs 64.99, stab 50 vs 49.99)
## - TC-FDIP.3: War declaration blocked by existing war, NAP, or Alliance
## - TC-FDIP.4: War declaration blocked for `trade_dominance`, pre-ascension `neutral_tribe`, and unascended `consolidate_power`
## - TC-FDIP.5: Pure FactionDiplomacyPlanner peace eligibility (`active` and `in_exile`, low military OR low stability)
## - TC-FDIP.6: Peace exact boundary thresholds (mil 20 vs 20.01, stab 25 vs 25.01, peaceful faction blocked)
## - TC-FDIP.7: Inactive/invalid states fail-closed (`in_exile` war blocked, `eliminated` all diplomacy blocked, invalid status/goal/NaN)
## - TC-FDIP.8: FactionDiplomacyPlanner 100% pure & side-effect-free across repeated evaluations
## - TC-FDIP.9: FactionManager autonomous war execution, signal emissions, opinion/disposition transition, and BattleCampaignManager raid scheduling
## - TC-FDIP.10: FactionManager autonomous peace execution (`active` and `in_exile`), signal emissions, opinion recovery, and pending raid cancellation
## - TC-FDIP.11: Daily simulation ordering: autonomous war declared on Day D immediately blocks `trade_expansion` / updates posture on Day D
## - TC-FDIP.12: Same-day idempotency & anti-oscillation (at most one diplomatic action per faction per game-day)
## - TC-FDIP.13: HUD Vietnamese event banner & diplomacy UI refresh on autonomous war and peace signals
## - TC-FDIP.14: Deterministic multi-day simulation equivalence across identical setups
## - TC-FDIP.15: Save/Load roundtrip, legacy save compatibility, double-load idempotency & fail-closed validation of `last_diplomacy_days`
## - TC-FDIP.16: Player-directed diplomacy regression (gifts, NAP, Alliance, manual war, manual peace remain intact)

const FactionDataScript = preload("res://scripts/factions/faction_data.gd")
const FactionDiplomacyPlannerScript = preload("res://scripts/factions/faction_diplomacy_planner.gd")
const FactionStrategyPlannerScript = preload("res://scripts/factions/faction_strategy_planner.gd")
const FactionStrategyExecutorScript = preload("res://scripts/factions/faction_strategy_executor.gd")
const FactionManagerScript = preload("res://scripts/factions/faction_manager.gd")
const BattleCampaignManagerScript = preload("res://scripts/combat/battle_campaign_manager.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")

var frame_count: int = 0
var world_instance: Node = null
var failures: int = 0
var passed_checks: int = 0

func _init() -> void:
	print("\n========================================================")
	print("  STARTING PACKAGE 1T AUTONOMOUS FACTION DIPLOMACY TESTS")
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
			print("  ALL PACKAGE 1T AUTONOMOUS FACTION DIPLOMACY TESTS PASSED! (Exit Code 0)")
			print("--------------------------------------------------------\n")
			quit(0)
			return true
		else:
			printerr("  PACKAGE 1T AUTONOMOUS FACTION DIPLOMACY TESTS FAILED WITH %d FAILURES! (Exit Code 1)" % failures)
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
	_assert_eq(fac.resources.size(), snap["resources"].size(), prefix + "-RES-SIZE")
	for k in snap["resources"]:
		_assert_eq(fac.resources.get(k, null), snap["resources"][k], prefix + "-RES-" + str(k))

func _run_all_tests() -> void:
	test_tc_fdip_1_planner_war_eligibility()
	test_tc_fdip_2_planner_war_boundary_thresholds()
	test_tc_fdip_3_planner_war_blocked_by_treaties_or_war()
	test_tc_fdip_4_planner_war_blocked_by_goal_or_pre_ascension()
	test_tc_fdip_5_planner_peace_eligibility()
	test_tc_fdip_6_planner_peace_boundary_thresholds()
	test_tc_fdip_7_planner_inactive_and_invalid_states_fail_closed()
	test_tc_fdip_8_planner_side_effect_free()
	test_tc_fdip_9_execution_war_and_raid_scheduling()
	test_tc_fdip_10_execution_peace_and_raid_cancellation()
	test_tc_fdip_11_daily_ordering_war_blocks_trade_expansion()
	test_tc_fdip_12_same_day_idempotency_and_anti_oscillation()
	test_tc_fdip_13_hud_vietnamese_notifications()
	test_tc_fdip_14_deterministic_multi_day_equivalence()
	test_tc_fdip_15_save_load_persistence_and_validation()
	test_tc_fdip_16_player_diplomacy_regression()

# -----------------------------------------------------------------------------
# TC-FDIP.1: Pure FactionDiplomacyPlanner war declaration eligibility
# -----------------------------------------------------------------------------
func test_tc_fdip_1_planner_war_eligibility() -> void:
	print("\n--- TC-FDIP.1: Planner War Eligibility (military_expansion & ascended emerging_power) ---")
	var fm := FactionManagerScript.new()

	# 1a. rival_military (military_expansion) meeting war criteria
	var mil: FactionData = fm.get_faction("rival_military")
	mil.opinion = -65.0
	mil.military_power = 75.0
	mil.stability = 80.0
	var dec_mil: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(mil)
	_assert_eq(dec_mil.get("faction_id", ""), "rival_military", "TC-FDIP.1-MIL-ID")
	_assert_eq(dec_mil.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_DECLARE_WAR, "TC-FDIP.1-MIL-ACTION")
	_assert_true(dec_mil.get("eligible", false), "TC-FDIP.1-MIL-ELIGIBLE")
	_assert_eq(dec_mil.get("reason_code", ""), FactionDiplomacyPlannerScript.REASON_WAR_PREREQUISITES_MET, "TC-FDIP.1-MIL-REASON")
	_assert_true(str(dec_mil.get("explanation", "")).length() > 10, "TC-FDIP.1-MIL-EXPLANATION")

	# 1b. Ascended emerging_power (consolidate_power) meeting war criteria
	var tribe: FactionData = fm.get_faction("neutral_tribe")
	tribe.type = FactionManagerScript.ASCENSION_NEW_TYPE
	tribe.name = FactionManagerScript.ASCENSION_NEW_NAME
	tribe.strategic_goal = FactionDataScript.GOAL_CONSOLIDATE_POWER
	tribe.opinion = -60.0
	tribe.military_power = 65.0
	tribe.stability = 50.0
	var dec_emerg: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(tribe)
	_assert_eq(dec_emerg.get("faction_id", ""), "neutral_tribe", "TC-FDIP.1-EMERG-ID")
	_assert_eq(dec_emerg.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_DECLARE_WAR, "TC-FDIP.1-EMERG-ACTION")
	_assert_true(dec_emerg.get("eligible", false), "TC-FDIP.1-EMERG-ELIGIBLE")
	_assert_eq(dec_emerg.get("reason_code", ""), FactionDiplomacyPlannerScript.REASON_WAR_PREREQUISITES_MET, "TC-FDIP.1-EMERG-REASON")

# -----------------------------------------------------------------------------
# TC-FDIP.2: War declaration exact boundary thresholds
# -----------------------------------------------------------------------------
func test_tc_fdip_2_planner_war_boundary_thresholds() -> void:
	print("\n--- TC-FDIP.2: War Declaration Boundary Thresholds ---")
	var fm := FactionManagerScript.new()
	var mil: FactionData = fm.get_faction("rival_military")

	# Exact thresholds: opinion = -60.0, military_power = 65.0, stability = 50.0 -> ELIGIBLE
	mil.opinion = -60.0
	mil.military_power = 65.0
	mil.stability = 50.0
	var dec_exact: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(mil)
	_assert_eq(dec_exact.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_DECLARE_WAR, "TC-FDIP.2-EXACT-WAR")
	_assert_true(dec_exact.get("eligible", false), "TC-FDIP.2-EXACT-ELIGIBLE")

	# Opinion just above threshold: -59.99 -> BLOCKED
	mil.opinion = -59.99
	var dec_op: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(mil)
	_assert_eq(dec_op.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_NONE, "TC-FDIP.2-OP-5999-NONE")
	_assert_false(dec_op.get("eligible", true), "TC-FDIP.2-OP-5999-INELIGIBLE")
	_assert_eq(dec_op.get("reason_code", ""), FactionDiplomacyPlannerScript.REASON_OPINION_ABOVE_WAR_THRESHOLD, "TC-FDIP.2-OP-5999-REASON")

	# Military power just below threshold: 64.99 -> BLOCKED
	mil.opinion = -60.0
	mil.military_power = 64.99
	var dec_mil: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(mil)
	_assert_eq(dec_mil.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_NONE, "TC-FDIP.2-MIL-6499-NONE")
	_assert_false(dec_mil.get("eligible", true), "TC-FDIP.2-MIL-6499-INELIGIBLE")
	_assert_eq(dec_mil.get("reason_code", ""), FactionDiplomacyPlannerScript.REASON_MILITARY_BELOW_WAR_THRESHOLD, "TC-FDIP.2-MIL-6499-REASON")

	# Stability just below threshold: 49.99 -> BLOCKED
	mil.military_power = 65.0
	mil.stability = 49.99
	var dec_stab: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(mil)
	_assert_eq(dec_stab.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_NONE, "TC-FDIP.2-STAB-4999-NONE")
	_assert_false(dec_stab.get("eligible", true), "TC-FDIP.2-STAB-4999-INELIGIBLE")
	_assert_eq(dec_stab.get("reason_code", ""), FactionDiplomacyPlannerScript.REASON_STABILITY_BELOW_WAR_THRESHOLD, "TC-FDIP.2-STAB-4999-REASON")

# -----------------------------------------------------------------------------
# TC-FDIP.3: War declaration blocked by existing war, NAP, or Alliance
# -----------------------------------------------------------------------------
func test_tc_fdip_3_planner_war_blocked_by_treaties_or_war() -> void:
	print("\n--- TC-FDIP.3: War Declaration Blocked by Treaties or Existing War ---")
	var fm := FactionManagerScript.new()
	var mil: FactionData = fm.get_faction("rival_military")
	mil.opinion = -80.0
	mil.military_power = 85.0
	mil.stability = 80.0

	# Blocked by NAP
	mil.has_nap = true
	var dec_nap: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(mil)
	_assert_eq(dec_nap.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_NONE, "TC-FDIP.3-NAP-NONE")
	_assert_false(dec_nap.get("eligible", true), "TC-FDIP.3-NAP-INELIGIBLE")
	_assert_eq(dec_nap.get("reason_code", ""), FactionDiplomacyPlannerScript.REASON_BLOCKED_BY_TREATY, "TC-FDIP.3-NAP-REASON")

	# Blocked by Alliance
	mil.has_nap = false
	mil.has_alliance = true
	var dec_all: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(mil)
	_assert_eq(dec_all.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_NONE, "TC-FDIP.3-ALLIANCE-NONE")
	_assert_false(dec_all.get("eligible", true), "TC-FDIP.3-ALLIANCE-INELIGIBLE")
	_assert_eq(dec_all.get("reason_code", ""), FactionDiplomacyPlannerScript.REASON_BLOCKED_BY_TREATY, "TC-FDIP.3-ALLIANCE-REASON")

	# Already at war (with high military and stability so peace is not triggered either)
	mil.has_alliance = false
	mil.is_at_war = true
	var dec_war: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(mil)
	_assert_eq(dec_war.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_NONE, "TC-FDIP.3-AT-WAR-NONE")
	_assert_false(dec_war.get("eligible", true), "TC-FDIP.3-AT-WAR-INELIGIBLE")
	_assert_eq(dec_war.get("reason_code", ""), FactionDiplomacyPlannerScript.REASON_WARTIME_CONTINUES, "TC-FDIP.3-AT-WAR-REASON")

# -----------------------------------------------------------------------------
# TC-FDIP.4: War declaration blocked for trade_dominance, pre-ascension tribe & unascended consolidate_power
# -----------------------------------------------------------------------------
func test_tc_fdip_4_planner_war_blocked_by_goal_or_pre_ascension() -> void:
	print("\n--- TC-FDIP.4: War Blocked for trade_dominance, Pre-Ascension Tribe & Unascended consolidate_power ---")
	var fm := FactionManagerScript.new()

	# 4a. rival_merchant (trade_dominance) even with -100 opinion, 100 mil, 100 stab
	var merch: FactionData = fm.get_faction("rival_merchant")
	merch.opinion = -100.0
	merch.military_power = 100.0
	merch.stability = 100.0
	var dec_merch: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(merch)
	_assert_eq(dec_merch.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_NONE, "TC-FDIP.4-MERCH-NONE")
	_assert_false(dec_merch.get("eligible", true), "TC-FDIP.4-MERCH-INELIGIBLE")
	_assert_eq(dec_merch.get("reason_code", ""), FactionDiplomacyPlannerScript.REASON_INELIGIBLE_GOAL, "TC-FDIP.4-MERCH-REASON")

	# 4b. Pre-ascension neutral_tribe (community_growth) even with -100 opinion, 100 mil, 100 stab
	var tribe: FactionData = fm.get_faction("neutral_tribe")
	tribe.opinion = -100.0
	tribe.military_power = 100.0
	tribe.stability = 100.0
	var dec_tribe: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(tribe)
	_assert_eq(dec_tribe.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_NONE, "TC-FDIP.4-TRIBE-NONE")
	_assert_false(dec_tribe.get("eligible", true), "TC-FDIP.4-TRIBE-INELIGIBLE")
	_assert_eq(dec_tribe.get("reason_code", ""), FactionDiplomacyPlannerScript.REASON_INELIGIBLE_GOAL, "TC-FDIP.4-TRIBE-REASON")

	# 4c. Unascended neutral_tribe forced to consolidate_power without ascending to emerging_power
	tribe.strategic_goal = FactionDataScript.GOAL_CONSOLIDATE_POWER
	tribe.type = "neutral_tribe"
	var dec_unasc: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(tribe)
	_assert_eq(dec_unasc.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_NONE, "TC-FDIP.4-UNASC-NONE")
	_assert_false(dec_unasc.get("eligible", true), "TC-FDIP.4-UNASC-INELIGIBLE")
	_assert_eq(dec_unasc.get("reason_code", ""), FactionDiplomacyPlannerScript.REASON_INELIGIBLE_UNASCENDED_CONSOLIDATION, "TC-FDIP.4-UNASC-REASON")

# -----------------------------------------------------------------------------
# TC-FDIP.5: Pure FactionDiplomacyPlanner peace eligibility
# -----------------------------------------------------------------------------
func test_tc_fdip_5_planner_peace_eligibility() -> void:
	print("\n--- TC-FDIP.5: Planner Peace Eligibility (active & in_exile, low mil OR low stab) ---")
	var fm := FactionManagerScript.new()
	var mil: FactionData = fm.get_faction("rival_military")
	mil.is_at_war = true

	# 5a. Active faction at war with low military_power (18.0 <= 20.0) and high stability (80.0)
	mil.existence_status = FactionDataScript.STATUS_ACTIVE
	mil.military_power = 18.0
	mil.stability = 80.0
	var dec_low_mil: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(mil)
	_assert_eq(dec_low_mil.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_SIGN_PEACE, "TC-FDIP.5-LOW-MIL-ACTION")
	_assert_true(dec_low_mil.get("eligible", false), "TC-FDIP.5-LOW-MIL-ELIGIBLE")
	_assert_eq(dec_low_mil.get("reason_code", ""), FactionDiplomacyPlannerScript.REASON_PEACE_MILITARY_DEPLETED, "TC-FDIP.5-LOW-MIL-REASON")

	# 5b. Active faction at war with high military_power (75.0) and low stability (22.0 <= 25.0)
	mil.military_power = 75.0
	mil.stability = 22.0
	var dec_low_stab: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(mil)
	_assert_eq(dec_low_stab.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_SIGN_PEACE, "TC-FDIP.5-LOW-STAB-ACTION")
	_assert_true(dec_low_stab.get("eligible", false), "TC-FDIP.5-LOW-STAB-ELIGIBLE")
	_assert_eq(dec_low_stab.get("reason_code", ""), FactionDiplomacyPlannerScript.REASON_PEACE_STABILITY_LOW, "TC-FDIP.5-LOW-STAB-REASON")

	# 5c. In-exile faction at war with both low military (15.0) and low stability (20.0)
	mil.existence_status = FactionDataScript.STATUS_IN_EXILE
	mil.military_power = 15.0
	mil.stability = 20.0
	var dec_exile_both: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(mil)
	_assert_eq(dec_exile_both.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_SIGN_PEACE, "TC-FDIP.5-EXILE-BOTH-ACTION")
	_assert_true(dec_exile_both.get("eligible", false), "TC-FDIP.5-EXILE-BOTH-ELIGIBLE")
	_assert_eq(dec_exile_both.get("reason_code", ""), FactionDiplomacyPlannerScript.REASON_PEACE_MILITARY_AND_STABILITY_LOW, "TC-FDIP.5-EXILE-BOTH-REASON")

# -----------------------------------------------------------------------------
# TC-FDIP.6: Peace exact boundary thresholds
# -----------------------------------------------------------------------------
func test_tc_fdip_6_planner_peace_boundary_thresholds() -> void:
	print("\n--- TC-FDIP.6: Peace Exact Boundary Thresholds ---")
	var fm := FactionManagerScript.new()
	var merch: FactionData = fm.get_faction("rival_merchant")
	merch.is_at_war = true

	# Exact military_power = 20.0, stability = 25.01 -> ELIGIBLE (military threshold)
	merch.military_power = 20.0
	merch.stability = 25.01
	var dec_mil_20: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(merch)
	_assert_eq(dec_mil_20.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_SIGN_PEACE, "TC-FDIP.6-MIL-20-PEACE")
	_assert_true(dec_mil_20.get("eligible", false), "TC-FDIP.6-MIL-20-ELIGIBLE")

	# Exact stability = 25.0, military_power = 20.01 -> ELIGIBLE (stability threshold)
	merch.military_power = 20.01
	merch.stability = 25.0
	var dec_stab_25: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(merch)
	_assert_eq(dec_stab_25.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_SIGN_PEACE, "TC-FDIP.6-STAB-25-PEACE")
	_assert_true(dec_stab_25.get("eligible", false), "TC-FDIP.6-STAB-25-ELIGIBLE")

	# Both just above threshold: military_power = 20.01, stability = 25.01 -> NOT ELIGIBLE
	merch.military_power = 20.01
	merch.stability = 25.01
	var dec_above: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(merch)
	_assert_eq(dec_above.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_NONE, "TC-FDIP.6-ABOVE-NONE")
	_assert_false(dec_above.get("eligible", true), "TC-FDIP.6-ABOVE-INELIGIBLE")
	_assert_eq(dec_above.get("reason_code", ""), FactionDiplomacyPlannerScript.REASON_WARTIME_CONTINUES, "TC-FDIP.6-ABOVE-REASON")

	# Peaceful faction with low military (10.0) and low stability (10.0) cannot sign peace when not at war
	merch.is_at_war = false
	merch.military_power = 10.0
	merch.stability = 10.0
	var dec_peaceful: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(merch)
	_assert_eq(dec_peaceful.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_NONE, "TC-FDIP.6-PEACEFUL-NONE")
	_assert_false(dec_peaceful.get("eligible", true), "TC-FDIP.6-PEACEFUL-INELIGIBLE")

# -----------------------------------------------------------------------------
# TC-FDIP.7: Inactive/invalid states fail-closed
# -----------------------------------------------------------------------------
func test_tc_fdip_7_planner_inactive_and_invalid_states_fail_closed() -> void:
	print("\n--- TC-FDIP.7: Inactive & Invalid States Fail-Closed ---")
	var fm := FactionManagerScript.new()
	var mil: FactionData = fm.get_faction("rival_military")

	# 7a. Null faction
	var dec_null: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(null)
	_assert_eq(dec_null.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_NONE, "TC-FDIP.7-NULL-ACTION")
	_assert_false(dec_null.get("eligible", true), "TC-FDIP.7-NULL-INELIGIBLE")
	_assert_eq(dec_null.get("reason_code", ""), FactionDiplomacyPlannerScript.REASON_ERR_NULL_FACTION, "TC-FDIP.7-NULL-REASON")

	# 7b. in_exile faction at peace cannot declare war even with -100 opinion, 90 mil, 90 stab
	mil.existence_status = FactionDataScript.STATUS_IN_EXILE
	mil.is_at_war = false
	mil.opinion = -100.0
	mil.military_power = 90.0
	mil.stability = 90.0
	var dec_exile_war: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(mil)
	_assert_eq(dec_exile_war.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_NONE, "TC-FDIP.7-EXILE-WAR-NONE")
	_assert_false(dec_exile_war.get("eligible", true), "TC-FDIP.7-EXILE-WAR-INELIGIBLE")
	_assert_eq(dec_exile_war.get("reason_code", ""), FactionDiplomacyPlannerScript.REASON_INELIGIBLE_EXILE_PEACETIME, "TC-FDIP.7-EXILE-WAR-REASON")

	# 7c. eliminated faction cannot declare war OR sign peace
	mil.existence_status = FactionDataScript.STATUS_ELIMINATED
	mil.is_at_war = false
	var dec_elim_peace: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(mil)
	_assert_eq(dec_elim_peace.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_NONE, "TC-FDIP.7-ELIM-1-NONE")
	_assert_false(dec_elim_peace.get("eligible", true), "TC-FDIP.7-ELIM-1-INELIGIBLE")
	_assert_eq(dec_elim_peace.get("reason_code", ""), FactionDiplomacyPlannerScript.REASON_INELIGIBLE_ELIMINATED, "TC-FDIP.7-ELIM-1-REASON")

	mil.is_at_war = true
	mil.military_power = 0.0
	mil.stability = 0.0
	var dec_elim_war: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(mil)
	_assert_eq(dec_elim_war.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_NONE, "TC-FDIP.7-ELIM-2-NONE")
	_assert_false(dec_elim_war.get("eligible", true), "TC-FDIP.7-ELIM-2-INELIGIBLE")
	_assert_eq(dec_elim_war.get("reason_code", ""), FactionDiplomacyPlannerScript.REASON_INELIGIBLE_ELIMINATED, "TC-FDIP.7-ELIM-2-REASON")

	# 7d. Invalid status / goal / NaN numeric fields fail closed
	mil.existence_status = "ghost_status"
	var dec_bad_st: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(mil)
	_assert_eq(dec_bad_st.get("reason_code", ""), FactionDiplomacyPlannerScript.REASON_ERR_INVALID_STATUS, "TC-FDIP.7-BAD-STATUS")

	mil.existence_status = FactionDataScript.STATUS_ACTIVE
	mil.strategic_goal = "unknown_goal"
	var dec_bad_goal: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(mil)
	_assert_eq(dec_bad_goal.get("reason_code", ""), FactionDiplomacyPlannerScript.REASON_ERR_INVALID_GOAL, "TC-FDIP.7-BAD-GOAL")

	mil.strategic_goal = FactionDataScript.GOAL_MILITARY_EXPANSION
	mil.opinion = NAN
	var dec_nan: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(mil)
	_assert_eq(dec_nan.get("reason_code", ""), FactionDiplomacyPlannerScript.REASON_ERR_INVALID_STATE, "TC-FDIP.7-NAN-OPINION")

	# Executor also rejects eliminated or invalid factions without recording last_diplomacy_day
	mil.opinion = -80.0
	mil.military_power = 80.0
	mil.stability = 80.0
	mil.is_at_war = false
	mil.existence_status = FactionDataScript.STATUS_ELIMINATED
	var exec_elim: Dictionary = fm.execute_faction_diplomatic_action("rival_military", 5)
	_assert_false(exec_elim.get("success", true), "TC-FDIP.7-EXEC-ELIM-FALSE")
	_assert_eq(exec_elim.get("reason_code", ""), FactionDiplomacyPlannerScript.REASON_INELIGIBLE_ELIMINATED, "TC-FDIP.7-EXEC-ELIM-REASON")
	_assert_eq(fm.get_faction_last_diplomacy_day("rival_military"), -1, "TC-FDIP.7-EXEC-ELIM-DAY-UNSET")

# -----------------------------------------------------------------------------
# TC-FDIP.8: FactionDiplomacyPlanner 100% pure & side-effect-free
# -----------------------------------------------------------------------------
func test_tc_fdip_8_planner_side_effect_free() -> void:
	print("\n--- TC-FDIP.8: FactionDiplomacyPlanner 100% Side-Effect-Free ---")
	var fm := FactionManagerScript.new()
	var mil: FactionData = fm.get_faction("rival_military")
	mil.opinion = -75.0
	mil.military_power = 80.0
	mil.stability = 75.0

	var merch: FactionData = fm.get_faction("rival_merchant")
	merch.is_at_war = true
	merch.military_power = 15.0

	var tribe: FactionData = fm.get_faction("neutral_tribe")

	var snap_mil: Dictionary = _take_snapshot(mil)
	var snap_merch: Dictionary = _take_snapshot(merch)
	var snap_tribe: Dictionary = _take_snapshot(tribe)

	for _i in range(25):
		var d1: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(mil)
		var d2: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(merch)
		var d3: Dictionary = FactionDiplomacyPlannerScript.evaluate_diplomatic_action(tribe)
		_assert_eq(d1.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_DECLARE_WAR, "TC-FDIP.8-PURE-D1")
		_assert_eq(d2.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_SIGN_PEACE, "TC-FDIP.8-PURE-D2")
		_assert_eq(d3.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_NONE, "TC-FDIP.8-PURE-D3")
		fm.get_faction_diplomatic_decision("rival_military")
		fm.evaluate_all_diplomatic_decisions()

	_verify_snapshot(mil, snap_mil, "TC-FDIP.8-SNAP-MIL")
	_verify_snapshot(merch, snap_merch, "TC-FDIP.8-SNAP-MERCH")
	_verify_snapshot(tribe, snap_tribe, "TC-FDIP.8-SNAP-TRIBE")
	_assert_eq(fm.get_faction_last_diplomacy_day("rival_military"), -1, "TC-FDIP.8-NO-DAY-RECORDED")

# -----------------------------------------------------------------------------
# TC-FDIP.9: Autonomous war execution, signals & BattleCampaignManager raid scheduling
# -----------------------------------------------------------------------------
func test_tc_fdip_9_execution_war_and_raid_scheduling() -> void:
	print("\n--- TC-FDIP.9: Autonomous War Execution & Raid Scheduling ---")
	var fm := FactionManagerScript.new()
	var bcm := BattleCampaignManagerScript.new(null, fm, 12345)

	var mil: FactionData = fm.get_faction("rival_military")
	mil.opinion = -60.0
	mil.military_power = 75.0
	mil.stability = 80.0

	var war_signals: Array[String] = []
	var rel_signals: Array[Dictionary] = []
	var eval_signals: Array[Dictionary] = []
	var exec_signals: Array[Dictionary] = []
	var scheduled_raids: Array[Dictionary] = []

	fm.war_declared.connect(func(fid: String): war_signals.append(fid))
	fm.relation_changed.connect(func(fid: String, op: float, disp: int): rel_signals.append({"fid": fid, "op": op, "disp": disp}))
	fm.diplomatic_action_evaluated.connect(func(fid: String, dec: Dictionary): eval_signals.append({"fid": fid, "dec": dec}))
	fm.diplomatic_action_executed.connect(func(fid: String, res: Dictionary): exec_signals.append({"fid": fid, "res": res}))
	bcm.raid_scheduled.connect(func(fid: String, r_day: int, is_first: bool): scheduled_raids.append({"fid": fid, "day": r_day, "first": is_first}))

	var exec_res: Dictionary = fm.execute_faction_diplomatic_action("rival_military", 4)
	_assert_true(exec_res.get("success", false), "TC-FDIP.9-EXEC-SUCCESS")
	_assert_eq(exec_res.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_DECLARE_WAR, "TC-FDIP.9-EXEC-ACTION")
	_assert_eq(exec_res.get("reason_code", ""), FactionManagerScript.DIPLO_REASON_EXECUTED_WAR, "TC-FDIP.9-EXEC-REASON")
	_assert_true(mil.is_at_war, "TC-FDIP.9-MIL-IS-AT-WAR")
	_assert_approx(mil.opinion, -100.0, "TC-FDIP.9-MIL-OPINION-CLAMPED")
	_assert_eq(mil.disposition, FactionDataScript.Disposition.HOSTILE, "TC-FDIP.9-MIL-HOSTILE")
	_assert_eq(fm.get_faction_last_diplomacy_day("rival_military"), 4, "TC-FDIP.9-LAST-DAY-4")

	_assert_eq(war_signals, ["rival_military"], "TC-FDIP.9-WAR-SIG")
	_assert_eq(rel_signals.size(), 1, "TC-FDIP.9-REL-SIG-COUNT")
	_assert_eq(eval_signals.size(), 1, "TC-FDIP.9-EVAL-SIG-COUNT")
	_assert_eq(exec_signals.size(), 1, "TC-FDIP.9-EXEC-SIG-COUNT")
	_assert_eq(scheduled_raids.size(), 1, "TC-FDIP.9-RAID-SCHEDULED-COUNT")
	if not scheduled_raids.is_empty():
		_assert_eq(scheduled_raids[0]["fid"], "rival_military", "TC-FDIP.9-RAID-FID")
		_assert_true(scheduled_raids[0]["first"], "TC-FDIP.9-RAID-IS-FIRST")

# -----------------------------------------------------------------------------
# TC-FDIP.10: Autonomous peace execution (`active` and `in_exile`) & raid cancellation
# -----------------------------------------------------------------------------
func test_tc_fdip_10_execution_peace_and_raid_cancellation() -> void:
	print("\n--- TC-FDIP.10: Autonomous Peace Execution & Pending Raid Cancellation ---")
	var fm := FactionManagerScript.new()
	var bcm := BattleCampaignManagerScript.new(null, fm, 12345)

	# Put rival_military at war first (schedules a raid in BattleCampaignManager)
	fm.declare_war("rival_military")
	var mil: FactionData = fm.get_faction("rival_military")
	_assert_true(mil.is_at_war, "TC-FDIP.10-PRE-AT-WAR")
	_assert_true(bcm.get_pending_raid("rival_military") != null and not bcm.get_pending_raid("rival_military").is_empty(), "TC-FDIP.10-PRE-HAS-RAID")

	# Deplete stability to trigger autonomous peace on Day 6
	mil.stability = 20.0
	var prev_op: float = mil.opinion

	var peace_signals: Array[String] = []
	var cancelled_raids: Array[Dictionary] = []
	fm.peace_signed.connect(func(fid: String): peace_signals.append(fid))
	bcm.raid_cancelled.connect(func(fid: String, reason: String): cancelled_raids.append({"fid": fid, "reason": reason}))

	var res_peace: Dictionary = fm.execute_faction_diplomatic_action("rival_military", 6)
	_assert_true(res_peace.get("success", false), "TC-FDIP.10-ACTIVE-PEACE-SUCCESS")
	_assert_eq(res_peace.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_SIGN_PEACE, "TC-FDIP.10-ACTIVE-PEACE-ACTION")
	_assert_eq(res_peace.get("reason_code", ""), FactionManagerScript.DIPLO_REASON_EXECUTED_PEACE, "TC-FDIP.10-ACTIVE-PEACE-REASON")
	_assert_false(mil.is_at_war, "TC-FDIP.10-MIL-AT-PEACE")
	_assert_approx(mil.opinion, prev_op + 20.0, "TC-FDIP.10-OPINION-GAIN-20")
	_assert_eq(peace_signals, ["rival_military"], "TC-FDIP.10-PEACE-SIG")
	_assert_eq(cancelled_raids.size(), 1, "TC-FDIP.10-RAID-CANCELLED")
	_assert_true(bcm.get_pending_raid("rival_military").is_empty(), "TC-FDIP.10-PENDING-RAID-CLEARED")

	# Test in_exile faction at war signing autonomous peace via daily simulation
	var merch: FactionData = fm.get_faction("rival_merchant")
	fm.declare_war("rival_merchant")
	merch.existence_status = FactionDataScript.STATUS_IN_EXILE
	merch.military_power = 12.0
	merch.stability = 40.0
	var merch_op_before: float = merch.opinion

	fm.update_daily_simulation(7)
	_assert_false(merch.is_at_war, "TC-FDIP.10-EXILE-PEACE-SUCCESS")
	_assert_approx(merch.opinion, merch_op_before + 20.0, "TC-FDIP.10-EXILE-OPINION-GAIN")
	_assert_eq(fm.get_faction_last_diplomacy_day("rival_merchant"), 7, "TC-FDIP.10-EXILE-LAST-DAY-7")

# -----------------------------------------------------------------------------
# TC-FDIP.11: Daily simulation ordering: war declared on Day D updates posture & blocks trade_expansion on Day D
# -----------------------------------------------------------------------------
func test_tc_fdip_11_daily_ordering_war_blocks_trade_expansion() -> void:
	print("\n--- TC-FDIP.11: Daily Simulation Ordering (Diplomacy Before Strategic Execution) ---")
	var fm := FactionManagerScript.new()

	# Case A: rival_military declares war on Day 3 -> its strategic intent on Day 3 must be evaluated in WARTIME posture
	var mil: FactionData = fm.get_faction("rival_military")
	mil.opinion = -70.0
	mil.military_power = 75.0
	mil.stability = 80.0

	var mil_eval_intents: Array[Dictionary] = []
	var call_sequence: Array[String] = []
	fm.diplomatic_action_executed.connect(func(fid: String, _res: Dictionary):
		if fid == "rival_military":
			call_sequence.append("diplomacy:" + fid)
	)
	fm.strategic_intent_evaluated.connect(func(fid: String, dec: Dictionary):
		if fid == "rival_military":
			call_sequence.append("strategy_eval:" + fid)
			mil_eval_intents.append(dec)
	)

	fm.update_daily_simulation(3)
	_assert_true(mil.is_at_war, "TC-FDIP.11-MIL-WAR-DECLARED")
	_assert_eq(call_sequence, ["diplomacy:rival_military", "strategy_eval:rival_military"], "TC-FDIP.11-ORDER-DIPLO-BEFORE-STRAT")
	_assert_eq(mil_eval_intents.size(), 1, "TC-FDIP.11-STRAT-EVAL-COUNT")
	if not mil_eval_intents.is_empty():
		_assert_eq(mil_eval_intents[0].get("posture", ""), "wartime", "TC-FDIP.11-MIL-POSTURE-WARTIME-SAME-DAY")
		_assert_eq(mil_eval_intents[0].get("reason_code", ""), FactionStrategyPlannerScript.REASON_WARTIME_POSTURE, "TC-FDIP.11-MIL-WARTIME-REASON")

	# Case B: Verify that if a faction signs peace on Day 4 (`rival_merchant` at war with low mil=15.0), its diplomacy runs BEFORE strategy
	# so on Day 4 it is already at peace when `trade_expansion` is evaluated and executed (+30 Gold, -5 Tools)!
	var merch: FactionData = fm.get_faction("rival_merchant")
	merch.is_at_war = true
	merch.military_power = 15.0
	merch.stability = 60.0
	var gold_before: int = int(merch.resources.get(EconomyConfigScript.RES_GOLD, 0))
	var tools_before: int = int(merch.resources.get(EconomyConfigScript.RES_TOOLS, 0))

	fm.update_daily_simulation(4)
	_assert_false(merch.is_at_war, "TC-FDIP.11-MERCH-SIGNED-PEACE-FIRST")
	_assert_eq(int(merch.resources.get(EconomyConfigScript.RES_GOLD, 0)), gold_before + FactionStrategyExecutorScript.TRADE_EXPANSION_GAIN_GOLD, "TC-FDIP.11-MERCH-TRADE-RAN-AFTER-PEACE")
	_assert_eq(int(merch.resources.get(EconomyConfigScript.RES_TOOLS, 0)), tools_before - FactionStrategyExecutorScript.TRADE_EXPANSION_COST_TOOLS, "TC-FDIP.11-MERCH-TOOLS-USED")

	# Case C: Verify that a faction declaring war on Day 5 CANNOT complete peacetime trade_expansion on that same tick
	# (and tampered/invalid decision_override or invalid day fails closed)
	var bad_day_res: Dictionary = fm.execute_faction_diplomatic_action("rival_military", 0)
	_assert_false(bad_day_res.get("success", true), "TC-FDIP.11-BAD-DAY-FALSE")
	_assert_eq(bad_day_res.get("reason_code", ""), FactionManagerScript.DIPLO_REASON_ERR_INVALID_DAY, "TC-FDIP.11-BAD-DAY-REASON")

	var bad_ov_res: Dictionary = fm.execute_faction_diplomatic_action("rival_merchant", 5, {"faction_id": "rival_merchant", "action_id": "declare_war", "eligible": true})
	_assert_false(bad_ov_res.get("success", true), "TC-FDIP.11-TAMPERED-OVERRIDE-FALSE")
	_assert_eq(bad_ov_res.get("reason_code", ""), FactionManagerScript.DIPLO_REASON_ERR_INVALID_DECISION, "TC-FDIP.11-TAMPERED-OVERRIDE-REASON")
	_assert_false(merch.is_at_war, "TC-FDIP.11-TAMPERED-OVERRIDE-NO-WAR")

# -----------------------------------------------------------------------------
# TC-FDIP.12: Same-day idempotency & anti-oscillation
# -----------------------------------------------------------------------------
func test_tc_fdip_12_same_day_idempotency_and_anti_oscillation() -> void:
	print("\n--- TC-FDIP.12: Same-Day Idempotency & Anti-Oscillation ---")
	var fm := FactionManagerScript.new()
	var mil: FactionData = fm.get_faction("rival_military")
	mil.opinion = -65.0
	mil.military_power = 70.0
	mil.stability = 60.0

	var eval_signals: Array[String] = []
	var exec_signals: Array[String] = []
	fm.diplomatic_action_evaluated.connect(func(fid: String, _d: Dictionary): eval_signals.append(fid))
	fm.diplomatic_action_executed.connect(func(fid: String, _r: Dictionary): exec_signals.append(fid))

	# First call on Day 5 declares war
	var res1: Dictionary = fm.execute_faction_diplomatic_action("rival_military", 5)
	_assert_true(res1.get("success", false), "TC-FDIP.12-FIRST-CALL-WAR")
	_assert_true(mil.is_at_war, "TC-FDIP.12-IS-AT-WAR")
	_assert_eq(eval_signals.size(), 1, "TC-FDIP.12-EVAL-COUNT-1")
	_assert_eq(exec_signals.size(), 1, "TC-FDIP.12-EXEC-COUNT-1")

	# Even if military_power drops to 10.0 on the SAME Day 5 (e.g. from battle), calling execute_faction_diplomatic_action or update_daily_simulation on Day 5 MUST NOT oscillate back to peace on Day 5!
	mil.military_power = 10.0
	var snap_after_drop: Dictionary = _take_snapshot(mil)
	var res2: Dictionary = fm.execute_faction_diplomatic_action("rival_military", 5)
	_assert_false(res2.get("success", true), "TC-FDIP.12-NO-SAME-DAY-OSCILLATION")
	_assert_eq(res2.get("reason_code", ""), FactionManagerScript.DIPLO_REASON_ALREADY_EVALUATED_TODAY, "TC-FDIP.12-ALREADY-EVALUATED-REASON")
	_verify_snapshot(mil, snap_after_drop, "TC-FDIP.12-NO-MUTATION-SAME-DAY")
	_assert_eq(eval_signals.size(), 1, "TC-FDIP.12-EVAL-STILL-1")
	_assert_eq(exec_signals.size(), 1, "TC-FDIP.12-EXEC-STILL-1")

	# On the NEXT day (Day 6), autonomous peace can legitimately execute
	var res3: Dictionary = fm.execute_faction_diplomatic_action("rival_military", 6)
	_assert_true(res3.get("success", false), "TC-FDIP.12-DAY6-PEACE-OK")
	_assert_eq(res3.get("action_id", ""), FactionDiplomacyPlannerScript.ACTION_SIGN_PEACE, "TC-FDIP.12-DAY6-ACTION-PEACE")
	_assert_false(mil.is_at_war, "TC-FDIP.12-DAY6-AT-PEACE")

# -----------------------------------------------------------------------------
# TC-FDIP.13: HUD Vietnamese event banner & diplomacy UI refresh on war and peace
# -----------------------------------------------------------------------------
func test_tc_fdip_13_hud_vietnamese_notifications() -> void:
	print("\n--- TC-FDIP.13: HUD Vietnamese Event Banner on Autonomous War & Peace ---")
	var hud: Node = world_instance.get_node_or_null("HUD")
	var fm: FactionManager = world_instance.get("faction_mgr")
	_assert_true(hud != null, "TC-FDIP.13-HUD-EXISTS")
	_assert_true(fm != null, "TC-FDIP.13-FM-EXISTS")
	if hud == null or fm == null:
		return

	fm._initialize_factions()
	var mil: FactionData = fm.get_faction("rival_military")
	mil.opinion = -70.0
	mil.military_power = 75.0
	mil.stability = 80.0

	# Trigger autonomous war on Day 2
	fm.execute_faction_diplomatic_action("rival_military", 2)
	var title_lbl: Label = hud.get("event_title")
	var desc_lbl: Label = hud.get("event_desc")
	var banner: Control = hud.get("event_banner")
	_assert_true(banner != null and banner.visible, "TC-FDIP.13-WAR-BANNER-VISIBLE")
	if title_lbl != null and desc_lbl != null:
		_assert_eq(title_lbl.text, "Chiến Sự Bùng Nổ!", "TC-FDIP.13-WAR-BANNER-TITLE")
		_assert_true(desc_lbl.text.find("Cổ Thành Thiết Giáp") != -1, "TC-FDIP.13-WAR-BANNER-FACTION-NAME")

	# Trigger autonomous peace on Day 3
	mil.military_power = 15.0
	fm.execute_faction_diplomatic_action("rival_military", 3)
	_assert_true(banner != null and banner.visible, "TC-FDIP.13-PEACE-BANNER-VISIBLE")
	if title_lbl != null and desc_lbl != null:
		_assert_eq(title_lbl.text, "Hòa Bình Lập Lại!", "TC-FDIP.13-PEACE-BANNER-TITLE")
		_assert_true(desc_lbl.text.find("Cổ Thành Thiết Giáp") != -1, "TC-FDIP.13-PEACE-BANNER-FACTION-NAME")

# -----------------------------------------------------------------------------
# TC-FDIP.14: Deterministic multi-day simulation equivalence
# -----------------------------------------------------------------------------
func test_tc_fdip_14_deterministic_multi_day_equivalence() -> void:
	print("\n--- TC-FDIP.14: Deterministic Multi-Day Equivalence ---")
	var fm_a := FactionManagerScript.new()
	var fm_b := FactionManagerScript.new()

	# Configure identical starting hostility so autonomous diplomacy triggers during the multi-day run
	fm_a.get_faction("rival_military").opinion = -65.0
	fm_b.get_faction("rival_military").opinion = -65.0

	for d in range(1, 15):
		if d == 6:
			fm_a.get_faction("rival_military").stability = 20.0
			fm_b.get_faction("rival_military").stability = 20.0
		fm_a.update_daily_simulation(d)
		fm_b.update_daily_simulation(d)

	for fid in ["neutral_tribe", "rival_merchant", "rival_military"]:
		var fac_a: FactionData = fm_a.get_faction(fid)
		var fac_b: FactionData = fm_b.get_faction(fid)
		var snap_b: Dictionary = _take_snapshot(fac_b)
		_verify_snapshot(fac_a, snap_b, "TC-FDIP.14-" + fid.to_upper())
		_assert_eq(fm_a.get_faction_last_diplomacy_day(fid), fm_b.get_faction_last_diplomacy_day(fid), "TC-FDIP.14-DIPLO-DAY-" + fid.to_upper())
		_assert_eq(fm_a.get_faction_last_executed_day(fid), fm_b.get_faction_last_executed_day(fid), "TC-FDIP.14-EXEC-DAY-" + fid.to_upper())

# -----------------------------------------------------------------------------
# TC-FDIP.15: Save/Load roundtrip, legacy save fallback, double-load & fail-closed validation
# -----------------------------------------------------------------------------
func test_tc_fdip_15_save_load_persistence_and_validation() -> void:
	print("\n--- TC-FDIP.15: Save/Load Persistence & Fail-Closed Validation ---")
	var fm: FactionManager = world_instance.get("faction_mgr")
	var tm: Node = world_instance.get_node_or_null("/root/TimeManager")
	if tm != null:
		tm.set("current_day", 8)

	fm._initialize_factions()
	var mil: FactionData = fm.get_faction("rival_military")
	mil.opinion = -65.0
	fm.update_daily_simulation(8)
	_assert_true(mil.is_at_war, "TC-FDIP.15-PRE-SAVE-WAR")
	_assert_eq(fm.get_faction_last_diplomacy_day("rival_military"), 8, "TC-FDIP.15-PRE-SAVE-DIPLO-DAY8")

	var snap_mil_saved: Dictionary = _take_snapshot(mil)
	var snap_merch_saved: Dictionary = _take_snapshot(fm.get_faction("rival_merchant"))
	var snap_tribe_saved: Dictionary = _take_snapshot(fm.get_faction("neutral_tribe"))

	var saved_data: Dictionary = SaveManagerScript.serialize_world_state(world_instance)
	var val_ok: Dictionary = SaveManagerScript.validate_save_data(saved_data)
	_assert_true(val_ok.get("valid", false), "TC-FDIP.15-VALID-SCHEMA", str(val_ok.get("error", "")))

	var exec_sec: Dictionary = saved_data.get("factions", {}).get("strategy_executor", {})
	_assert_true(exec_sec.has("last_diplomacy_days"), "TC-FDIP.15-HAS-LAST-DIPLO-DAYS")
	_assert_eq(int(exec_sec.get("last_diplomacy_days", {}).get("rival_military", -1)), 8, "TC-FDIP.15-SAVED-MIL-DAY8")

	# Perturb live state before loading
	mil.is_at_war = false
	mil.opinion = 50.0
	fm.deserialize_executor_state({})
	_assert_eq(fm.get_faction_last_diplomacy_day("rival_military"), -1, "TC-FDIP.15-PERTURBED-DAY-RESET")

	# Load 1
	var apply_1: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, saved_data)
	_assert_true(apply_1.get("success", false), "TC-FDIP.15-APPLY-1")
	_verify_snapshot(fm.get_faction("rival_military"), snap_mil_saved, "TC-FDIP.15-REST1-MIL")
	_verify_snapshot(fm.get_faction("rival_merchant"), snap_merch_saved, "TC-FDIP.15-REST1-MERCH")
	_verify_snapshot(fm.get_faction("neutral_tribe"), snap_tribe_saved, "TC-FDIP.15-REST1-TRIBE")
	_assert_eq(fm.get_faction_last_diplomacy_day("rival_military"), 8, "TC-FDIP.15-REST1-DIPLO-DAY8")

	# Re-running Day 8 after load must NOT re-evaluate or oscillate diplomacy on Day 8
	fm.get_faction("rival_military").stability = 15.0
	var res_reexec: Dictionary = fm.execute_faction_diplomatic_action("rival_military", 8)
	_assert_false(res_reexec.get("success", true), "TC-FDIP.15-NO-REEXEC-DAY8")
	_assert_eq(res_reexec.get("reason_code", ""), FactionManagerScript.DIPLO_REASON_ALREADY_EVALUATED_TODAY, "TC-FDIP.15-NO-REEXEC-REASON")
	_assert_true(fm.get_faction("rival_military").is_at_war, "TC-FDIP.15-STILL-AT-WAR-DAY8")

	# Load 2 (Double-load idempotency)
	var apply_2: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, saved_data)
	_assert_true(apply_2.get("success", false), "TC-FDIP.15-APPLY-2")
	_verify_snapshot(fm.get_faction("rival_military"), snap_mil_saved, "TC-FDIP.15-REST2-MIL")

	# Legacy save omitting last_diplomacy_days loads cleanly
	var legacy_data: Dictionary = saved_data.duplicate(true)
	legacy_data["factions"]["strategy_executor"].erase("last_diplomacy_days")
	_assert_true(SaveManagerScript.validate_save_data(legacy_data).get("valid", false), "TC-FDIP.15-LEGACY-VALID")
	_assert_true(SaveManagerScript.apply_loaded_state_to_world(world_instance, legacy_data).get("success", false), "TC-FDIP.15-LEGACY-APPLY")
	_assert_eq(fm.get_faction_last_diplomacy_day("rival_military"), -1, "TC-FDIP.15-LEGACY-RESET-DIPLO-DAY")

	# Restore baseline Day 8 before testing rejected payloads
	SaveManagerScript.apply_loaded_state_to_world(world_instance, saved_data)
	var live_snap_mil: Dictionary = _take_snapshot(fm.get_faction("rival_military"))

	# Fail-closed validation: non-dictionary last_diplomacy_days
	var bad_type: Dictionary = saved_data.duplicate(true)
	bad_type["factions"]["strategy_executor"]["last_diplomacy_days"] = "invalid"
	_assert_false(SaveManagerScript.validate_save_data(bad_type).get("valid", true), "TC-FDIP.15-REJECT-NON-DICT")

	# Fail-closed validation: future diplomacy day (9 > game_clock.current_day == 8)
	var bad_future: Dictionary = saved_data.duplicate(true)
	bad_future["game_clock"]["current_day"] = 8
	bad_future["factions"]["strategy_executor"]["last_diplomacy_days"]["rival_military"] = 9
	bad_future["factions"]["factions"]["rival_military"]["military_power"] = 123.0
	var val_future: Dictionary = SaveManagerScript.validate_save_data(bad_future)
	_assert_false(val_future.get("valid", true), "TC-FDIP.15-REJECT-FUTURE-DIPLO-DAY")
	var apply_future: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, bad_future)
	_assert_false(apply_future.get("success", true), "TC-FDIP.15-APPLY-REJECT-FUTURE-DIPLO-DAY")
	_verify_snapshot(fm.get_faction("rival_military"), live_snap_mil, "TC-FDIP.15-NO-MUTATION-ON-REJECT")
	_assert_eq(fm.get_faction_last_diplomacy_day("rival_military"), 8, "TC-FDIP.15-DIPLO-DAY-PRESERVED-ON-REJECT")

	# Fail-closed validation: negative / zero diplomacy day
	var bad_zero: Dictionary = saved_data.duplicate(true)
	bad_zero["factions"]["strategy_executor"]["last_diplomacy_days"]["rival_military"] = 0
	_assert_false(SaveManagerScript.validate_save_data(bad_zero).get("valid", true), "TC-FDIP.15-REJECT-ZERO-DIPLO-DAY")

	# Second-layer defense in FactionManager.deserialize_executor_state
	fm.deserialize_executor_state({"last_diplomacy_days": {"rival_military": 99}}, 8)
	_assert_eq(fm.get_faction_last_diplomacy_day("rival_military"), -1, "TC-FDIP.15-SECOND-LAYER-FILTERS-FUTURE-DAY")

# -----------------------------------------------------------------------------
# TC-FDIP.16: Player-directed diplomacy regression
# -----------------------------------------------------------------------------
func test_tc_fdip_16_player_diplomacy_regression() -> void:
	print("\n--- TC-FDIP.16: Player-Directed Diplomacy Regression ---")
	var fm := FactionManagerScript.new()

	# Gift increases opinion
	var gift_res: Dictionary = fm.send_gift("rival_merchant", EconomyConfigScript.RES_GOLD, 50, null)
	_assert_true(gift_res.get("success", false), "TC-FDIP.16-GIFT-OK")

	# NAP signing
	var nap_res: Dictionary = fm.propose_treaty("rival_merchant", "nap")
	_assert_true(nap_res.get("success", false), "TC-FDIP.16-NAP-OK")
	_assert_true(fm.get_faction("rival_merchant").has_nap, "TC-FDIP.16-HAS-NAP")

	# Alliance signing after raising opinion >= 60
	fm.modify_opinion("rival_merchant", 50.0)
	var all_res: Dictionary = fm.propose_treaty("rival_merchant", "alliance")
	_assert_true(all_res.get("success", false), "TC-FDIP.16-ALLIANCE-OK")
	_assert_true(fm.get_faction("rival_merchant").has_alliance, "TC-FDIP.16-HAS-ALLIANCE")

	# Manual war & manual peace still work even if autonomous diplomacy ran earlier today
	fm.update_daily_simulation(1)
	var man_war: Dictionary = fm.declare_war("rival_military")
	_assert_true(man_war.get("success", false), "TC-FDIP.16-MANUAL-WAR-OK")
	_assert_true(fm.get_faction("rival_military").is_at_war, "TC-FDIP.16-MANUAL-IS-AT-WAR")
	var man_peace: Dictionary = fm.propose_treaty("rival_military", "peace")
	_assert_true(man_peace.get("success", false), "TC-FDIP.16-MANUAL-PEACE-OK")
	_assert_false(fm.get_faction("rival_military").is_at_war, "TC-FDIP.16-MANUAL-AT-PEACE")
