extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — Package 2E: Autonomous Faction Conflict & Inter-Faction Warfare
## Validates autonomous NPC-NPC conflict evaluation, campaign scheduling, BattleResolver resolution,
## resource plunder, outpost damage, truce cooldowns, player isolation, caravan surcharges, and save persistence:
## - TC-2E.1: Pairwise war evaluation eligibility & threshold boundaries
## - TC-2E.2: Pairwise war evaluation blocking conditions (opinion, mil, stab, power ratio, treaty, status)
## - TC-2E.3: Anti-oscillation & Truce duration enforcement (6 days, blocked during truce)
## - TC-2E.4: Autonomous war declaration execution & event signals
## - TC-2E.5: Automatic inter-faction campaign scheduling via BattleCampaignManager
## - TC-2E.6: Real battle resolution via BattleResolver (troops, casualties, victor)
## - TC-2E.7: Conservation of resources & strict plunder transfer (no phantom resources)
## - TC-2E.8: Concrete world impact (outpost damage, sacking, stability loss, population loss)
## - TC-2E.9: Autonomous peace declaration, war weariness, truce establishment & campaign cancellation
## - TC-2E.10: Player isolation (zero mutation to player treaties, player opinion, or player raids)
## - TC-2E.11: Trade caravan wartime price surcharge (+15% markup when origin at war)
## - TC-2E.12: Deterministic outcomes with identical seeds
## - TC-2E.13: Save / Load roundtrip persistence & fail-closed schema validation
## - TC-2E.14: HUD banner & Diplomacy UI Section 3 integration

const FactionDataScript = preload("res://scripts/factions/faction_data.gd")
const FactionRelationDataScript = preload("res://scripts/factions/faction_relation_data.gd")
const FactionDiplomacyPlannerScript = preload("res://scripts/factions/faction_diplomacy_planner.gd")
const FactionManagerScript = preload("res://scripts/factions/faction_manager.gd")
const BattleCampaignManagerScript = preload("res://scripts/combat/battle_campaign_manager.gd")
const BattleResolverScript = preload("res://scripts/combat/battle_resolver.gd")
const FieldSiegeManagerScript = preload("res://scripts/combat/field_siege_manager.gd")
const TradeCaravanScript = preload("res://scripts/trade/trade_caravan.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const SiegeObjectiveActorScript = preload("res://scripts/combat/siege_objective_actor.gd")
const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")

class SpyObjectiveActor extends Node2D:
	var objective_id: String = ""
	var owning_faction_id: String = ""
	var health: float = 200.0
	var max_health: float = 200.0
	var is_alive: bool = true
	var is_captured: bool = false
	var redraw_called_count: int = 0

	@warning_ignore("native_method_override")
	func queue_redraw() -> void:
		redraw_called_count += 1
		super.queue_redraw()

var frame_count: int = 0
var world_instance: Node = null
var failures: int = 0
var passed_checks: int = 0

func _init() -> void:
	print("\n========================================================")
	print("  STARTING PACKAGE 2E AUTONOMOUS FACTION CONFLICT TESTS")
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
			print("  ALL PACKAGE 2E AUTONOMOUS FACTION CONFLICT TESTS PASSED! (Exit Code 0)")
			print("--------------------------------------------------------\n")
			quit(0)
			return true
		else:
			printerr("  PACKAGE 2E TESTS FAILED WITH %d FAILURES! (Exit Code 1)" % failures)
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

func _run_all_tests() -> void:
	_test_tc_2e_1_pairwise_war_evaluation_eligibility()
	_test_tc_2e_2_pairwise_war_blocking_conditions()
	_test_tc_2e_3_anti_oscillation_and_truce_enforcement()
	_test_tc_2e_4_autonomous_war_execution_and_signals()
	_test_tc_2e_5_automatic_campaign_scheduling()
	_test_tc_2e_6_real_battle_resolution()
	_test_tc_2e_7_conservation_of_resources_and_plunder()
	_test_tc_2e_8_concrete_world_impact_and_outpost_damage()
	_test_tc_2e_9_autonomous_peace_and_weariness()
	_test_tc_2e_10_player_isolation()
	_test_tc_2e_11_trade_caravan_wartime_surcharge()
	_test_tc_2e_12_deterministic_simulation_equivalence()
	_test_tc_2e_13_save_load_roundtrip_persistence()
	_test_tc_2e_14_hud_integration_authoritative_state()
	_test_tc_2e_15_bug_fixes_verification()
	_test_tc_2e_16_campaign_sequence_and_lifecycle_interval()

# -----------------------------------------------------------------------------
# TC-2E.1: Pairwise war evaluation eligibility & threshold boundaries
# -----------------------------------------------------------------------------
func _test_tc_2e_1_pairwise_war_evaluation_eligibility() -> void:
	print("\n--- TC-2E.1: Pairwise war evaluation eligibility & threshold boundaries ---")
	var planner := FactionDiplomacyPlannerScript.new()
	var fm := FactionManagerScript.new()

	var mil_fac = fm.get_faction("rival_military")
	var mer_fac = fm.get_faction("rival_merchant")
	var rel = fm.get_pairwise_relation_between("rival_military", "rival_merchant")

	# Setup baseline war condition: military expansion, high power, high stability, opinion <= -50.0
	mil_fac.military_power = 60.0
	mil_fac.stability = 50.0
	mer_fac.military_power = 50.0
	mer_fac.stability = 60.0
	rel.set_opinion("rival_military", "rival_merchant", -55.0)
	rel.set_opinion("rival_merchant", "rival_military", -40.0)
	rel.is_at_war = false
	rel.has_nap = false
	rel.has_alliance = false
	rel.truce_until_day = 0

	var eval = planner.evaluate_pairwise_diplomatic_action(mil_fac, mer_fac, rel, 5)
	_assert_eq(eval.get("action_id"), FactionDiplomacyPlannerScript.ACTION_DECLARE_WAR, "TC-2E.1-ACTION", "Should evaluate ACTION_DECLARE_WAR")
	_assert_eq(eval.get("reason_code"), FactionDiplomacyPlannerScript.REASON_WAR_PREREQUISITES_MET, "TC-2E.1-REASON", "Reason should be REASON_WAR_PREREQUISITES_MET")
	_assert_eq(eval.get("initiator_id"), "rival_military", "TC-2E.1-INIT", "Initiator should be rival_military")
	_assert_eq(eval.get("target_id"), "rival_merchant", "TC-2E.1-TGT", "Target should be rival_merchant")

	# Test pair wrapper evaluate_pair_diplomatic_action
	var pair_eval = planner.evaluate_pair_diplomatic_action(mil_fac, mer_fac, rel, 5)
	_assert_eq(pair_eval.get("action_id"), FactionDiplomacyPlannerScript.ACTION_DECLARE_WAR, "TC-2E.1-PAIR-ACTION", "Pair evaluation matches")

# -----------------------------------------------------------------------------
# TC-2E.2: Pairwise war evaluation blocking conditions
# -----------------------------------------------------------------------------
func _test_tc_2e_2_pairwise_war_blocking_conditions() -> void:
	print("\n--- TC-2E.2: Pairwise war evaluation blocking conditions ---")
	var planner := FactionDiplomacyPlannerScript.new()
	var fm := FactionManagerScript.new()

	var mil_fac = fm.get_faction("rival_military")
	var mer_fac = fm.get_faction("rival_merchant")
	var rel = fm.get_pairwise_relation_between("rival_military", "rival_merchant")

	mil_fac.military_power = 60.0
	mil_fac.stability = 50.0
	mer_fac.military_power = 50.0
	rel.is_at_war = false
	rel.has_nap = false
	rel.has_alliance = false
	rel.truce_until_day = 0

	# 1. Opinion above threshold (> -50.0)
	rel.set_opinion("rival_military", "rival_merchant", -49.9)
	var eval_op = planner.evaluate_pairwise_diplomatic_action(mil_fac, mer_fac, rel, 5)
	_assert_eq(eval_op.get("action_id"), FactionDiplomacyPlannerScript.ACTION_NONE, "TC-2E.2-OPINION-ABOVE", "Blocked by opinion > -50.0")
	_assert_eq(eval_op.get("reason_code"), FactionDiplomacyPlannerScript.REASON_OPINION_ABOVE_WAR_THRESHOLD, "TC-2E.2-OPINION-REASON", "Reason matches")

	rel.set_opinion("rival_military", "rival_merchant", -60.0)

	# 2. Insufficient military power (< 40.0)
	mil_fac.military_power = 39.9
	var eval_mil = planner.evaluate_pairwise_diplomatic_action(mil_fac, mer_fac, rel, 5)
	_assert_eq(eval_mil.get("action_id"), FactionDiplomacyPlannerScript.ACTION_NONE, "TC-2E.2-LOW-MIL", "Blocked by military power < 40.0")
	_assert_eq(eval_mil.get("reason_code"), FactionDiplomacyPlannerScript.REASON_MILITARY_BELOW_WAR_THRESHOLD, "TC-2E.2-LOW-MIL-REASON", "Reason code matches")

	mil_fac.military_power = 60.0

	# 3. Insufficient stability (< 30.0)
	mil_fac.stability = 29.9
	var eval_stab = planner.evaluate_pairwise_diplomatic_action(mil_fac, mer_fac, rel, 5)
	_assert_eq(eval_stab.get("action_id"), FactionDiplomacyPlannerScript.ACTION_NONE, "TC-2E.2-LOW-STAB", "Blocked by stability < 30.0")
	_assert_eq(eval_stab.get("reason_code"), FactionDiplomacyPlannerScript.REASON_STABILITY_BELOW_WAR_THRESHOLD, "TC-2E.2-LOW-STAB-REASON", "Reason code matches")

	mil_fac.stability = 50.0

	# 4. Insufficient power ratio (< 0.65)
	mil_fac.military_power = 40.0
	mer_fac.military_power = 100.0 # ratio = 0.40 < 0.65
	var eval_ratio = planner.evaluate_pairwise_diplomatic_action(mil_fac, mer_fac, rel, 5)
	_assert_eq(eval_ratio.get("action_id"), FactionDiplomacyPlannerScript.ACTION_NONE, "TC-2E.2-LOW-RATIO", "Blocked by power ratio < 0.65")
	_assert_eq(eval_ratio.get("reason_code"), FactionDiplomacyPlannerScript.REASON_INSUFFICIENT_POWER_RATIO, "TC-2E.2-LOW-RATIO-REASON", "Reason code matches")

	mil_fac.military_power = 60.0
	mer_fac.military_power = 50.0

	# 5. Blocked by NAP
	rel.has_nap = true
	var eval_nap = planner.evaluate_pairwise_diplomatic_action(mil_fac, mer_fac, rel, 5)
	_assert_eq(eval_nap.get("action_id"), FactionDiplomacyPlannerScript.ACTION_NONE, "TC-2E.2-NAP-BLOCKED", "Blocked by active NAP")
	_assert_eq(eval_nap.get("reason_code"), FactionDiplomacyPlannerScript.REASON_BLOCKED_BY_TREATY, "TC-2E.2-NAP-REASON", "Reason code matches")
	rel.has_nap = false

	# 6. Blocked by Alliance
	rel.has_alliance = true
	var eval_ally = planner.evaluate_pairwise_diplomatic_action(mil_fac, mer_fac, rel, 5)
	_assert_eq(eval_ally.get("action_id"), FactionDiplomacyPlannerScript.ACTION_NONE, "TC-2E.2-ALLY-BLOCKED", "Blocked by active Alliance")
	_assert_eq(eval_ally.get("reason_code"), FactionDiplomacyPlannerScript.REASON_BLOCKED_BY_TREATY, "TC-2E.2-ALLY-REASON", "Reason code matches")
	rel.has_alliance = false

	# 7. Blocked if initiator in_exile or eliminated
	mil_fac.existence_status = FactionDataScript.STATUS_IN_EXILE
	var eval_exile = planner.evaluate_pairwise_diplomatic_action(mil_fac, mer_fac, rel, 5)
	_assert_eq(eval_exile.get("action_id"), FactionDiplomacyPlannerScript.ACTION_NONE, "TC-2E.2-EXILE-BLOCKED", "Blocked when in_exile")
	mil_fac.existence_status = FactionDataScript.STATUS_ACTIVE

# -----------------------------------------------------------------------------
# TC-2E.3: Anti-oscillation & Truce duration enforcement
# -----------------------------------------------------------------------------
func _test_tc_2e_3_anti_oscillation_and_truce_enforcement() -> void:
	print("\n--- TC-2E.3: Anti-oscillation & Truce duration enforcement ---")
	var planner := FactionDiplomacyPlannerScript.new()
	var fm := FactionManagerScript.new()

	var mil_fac = fm.get_faction("rival_military")
	var mer_fac = fm.get_faction("rival_merchant")
	var rel = fm.get_pairwise_relation_between("rival_military", "rival_merchant")

	mil_fac.military_power = 60.0
	mil_fac.stability = 50.0
	mer_fac.military_power = 50.0
	rel.set_opinion("rival_military", "rival_merchant", -60.0)
	rel.set_opinion("rival_merchant", "rival_military", -55.0)
	rel.is_at_war = false
	rel.has_nap = false
	rel.has_alliance = false

	# Put on truce until Day 10
	rel.truce_until_day = 10
	_assert_true(rel.is_on_truce(5), "TC-2E.3-TRUCE-ACTIVE-DAY-5", "Should be on truce at day 5")
	_assert_true(rel.is_on_truce(9), "TC-2E.3-TRUCE-ACTIVE-DAY-9", "Should be on truce at day 9")
	_assert_false(rel.is_on_truce(10), "TC-2E.3-TRUCE-EXPIRED-DAY-10", "Truce expires on day 10")

	# Evaluate during truce (Day 8) -> Must be blocked
	var eval_truce = planner.evaluate_pairwise_diplomatic_action(mil_fac, mer_fac, rel, 8)
	_assert_eq(eval_truce.get("action_id"), FactionDiplomacyPlannerScript.ACTION_NONE, "TC-2E.3-BLOCKED-ACTION", "War evaluation blocked during truce")
	_assert_eq(eval_truce.get("reason_code"), FactionDiplomacyPlannerScript.REASON_BLOCKED_BY_TRUCE, "TC-2E.3-BLOCKED-REASON", "Reason code is BLOCKED_BY_TRUCE")

	# Direct declaration attempt during truce must fail closed
	var res_decl = fm.declare_war_between_factions("rival_military", "rival_merchant", "Border dispute", 8)
	_assert_false(res_decl.get("success", true), "TC-2E.3-DECL-FAIL", "declare_war fails during truce")
	_assert_eq(res_decl.get("reason_code"), FactionManagerScript.PAIR_REASON_ERR_ON_TRUCE, "TC-2E.3-DECL-ERR-REASON", "Failure reason is ERR_ON_TRUCE")

	# After truce expires (Day 10) -> Can evaluate war
	var eval_post_truce = planner.evaluate_pairwise_diplomatic_action(mil_fac, mer_fac, rel, 10)
	_assert_eq(eval_post_truce.get("action_id"), FactionDiplomacyPlannerScript.ACTION_DECLARE_WAR, "TC-2E.3-POST-TRUCE-ACTION", "War allowed after truce expires")

# -----------------------------------------------------------------------------
# TC-2E.4: Autonomous war declaration execution & event signals
# -----------------------------------------------------------------------------
func _test_tc_2e_4_autonomous_war_execution_and_signals() -> void:
	print("\n--- TC-2E.4: Autonomous war declaration execution & event signals ---")
	var fm := FactionManagerScript.new()

	var pair_key: String = "rival_merchant__rival_military"
	var rel = fm.get_pairwise_relation(pair_key)
	rel.opinion_a_to_b = -55.0
	rel.opinion_b_to_a = -50.0
	rel.is_at_war = false
	rel.truce_until_day = 0

	var signal_emitted: Array = []
	fm.faction_pair_war_declared.connect(func(init, tgt, pk):
		signal_emitted.append({"initiator": init, "target": tgt, "key": pk})
	)

	var res = fm.declare_war_between_factions("rival_military", "rival_merchant", "Expansionist Conquest", 3)
	_assert_true(res.get("success", false), "TC-2E.4-EXEC-SUCCESS", "War declared successfully")
	_assert_eq(signal_emitted.size(), 1, "TC-2E.4-SIGNAL-COUNT", "faction_pair_war_declared emitted exactly once")
	_assert_eq(signal_emitted[0]["initiator"], "rival_military", "TC-2E.4-SIGNAL-INIT", "Initiator matches")
	_assert_eq(signal_emitted[0]["target"], "rival_merchant", "TC-2E.4-SIGNAL-TGT", "Target matches")

	# Check relation fields updated
	_assert_true(rel.is_at_war, "TC-2E.4-REL-WAR", "Relation marked is_at_war = true")
	_assert_eq(rel.war_start_day, 3, "TC-2E.4-REL-START-DAY", "war_start_day recorded")
	_assert_eq(rel.casus_belli, "Expansionist Conquest", "TC-2E.4-REL-CB", "casus_belli recorded")
	_assert_eq(rel.war_count, 1, "TC-2E.4-REL-WAR-COUNT", "war_count incremented to 1")

# -----------------------------------------------------------------------------
# TC-2E.5: Automatic inter-faction campaign scheduling via BattleCampaignManager
# -----------------------------------------------------------------------------
func _test_tc_2e_5_automatic_campaign_scheduling() -> void:
	print("\n--- TC-2E.5: Automatic inter-faction campaign scheduling via BattleCampaignManager ---")
	var fm := FactionManagerScript.new()
	var bcm := BattleCampaignManagerScript.new()
	bcm.set_faction_manager(fm)

	var sched_signals: Array = []
	bcm.inter_faction_campaign_scheduled.connect(func(camp_data: Dictionary):
		sched_signals.append(camp_data)
	)

	bcm.set_custom_current_day(4)

	# Declare war between rival_military and rival_merchant on Day 4
	var res = fm.declare_war_between_factions("rival_military", "rival_merchant", "Territorial Ambition", 4)
	_assert_true(res.get("success", false), "TC-2E.5-WAR-SUCCESS", "War declared")

	_assert_eq(sched_signals.size(), 1, "TC-2E.5-SCHED-COUNT", "inter_faction_campaign_scheduled emitted")
	_assert_eq(sched_signals[0]["attacker_id"], "rival_military", "TC-2E.5-ATK", "Attacker is rival_military")
	_assert_eq(sched_signals[0]["defender_id"], "rival_merchant", "TC-2E.5-DEF", "Defender is rival_merchant")
	_assert_eq(sched_signals[0]["scheduled_day"], 4 + BattleCampaignManagerScript.INTER_FACTION_CAMPAIGN_PREP_DAYS, "TC-2E.5-DAY", "Scheduled for Day + 2")

	var pair_key: String = "rival_merchant__rival_military"
	_assert_true(bcm.has_pending_inter_faction_campaign_for_pair(pair_key), "TC-2E.5-HAS-PENDING", "Has pending campaign for pair")
	var pending = bcm.get_pending_inter_faction_campaign_for_pair(pair_key)
	_assert_eq(pending.get("attacker_id"), "rival_military", "TC-2E.5-PENDING-ATK", "Pending attacker matches")
	_assert_eq(pending.get("defender_id"), "rival_merchant", "TC-2E.5-PENDING-DEF", "Pending defender matches")

# -----------------------------------------------------------------------------
# TC-2E.6: Real battle resolution via BattleResolver
# -----------------------------------------------------------------------------
func _test_tc_2e_6_real_battle_resolution() -> void:
	print("\n--- TC-2E.6: Real battle resolution via BattleResolver ---")
	var fm := FactionManagerScript.new()
	var bcm := BattleCampaignManagerScript.new()
	bcm.set_faction_manager(fm)

	# Must declare war before scheduling campaign
	fm.declare_war_between_factions("rival_military", "rival_merchant", "Conquest", 4)

	var mil_fac = fm.get_faction("rival_military")
	var mer_fac = fm.get_faction("rival_merchant")
	mil_fac.military_power = 75.0
	mer_fac.military_power = 40.0

	var resolved_reports: Array = []
	bcm.inter_faction_battle_resolved.connect(func(report, context):
		resolved_reports.append({"report": report, "context": context})
	)

	# Schedule campaign directly for Day 6
	var camp = bcm.schedule_inter_faction_campaign("rival_military", "rival_merchant", 6, 1)
	_assert_false(camp.is_empty(), "TC-2E.6-SCHED", "Campaign scheduled")

	# Process daily campaigns on Day 6
	var results = bcm.process_daily_inter_faction_campaigns(6)
	_assert_eq(results.size(), 1, "TC-2E.6-RES-COUNT", "One battle resolved on Day 6")
	_assert_eq(resolved_reports.size(), 1, "TC-2E.6-SIGNAL-COUNT", "inter_faction_battle_resolved signal emitted")

	var report = resolved_reports[0]["report"]
	var context = resolved_reports[0]["context"]
	_assert_true(report.victor in ["attacker", "defender", "draw"], "TC-2E.6-VICTOR", "Valid victor decided: %s" % report.victor)
	_assert_true(context.get("attacker_casualties", 0) >= 0, "TC-2E.6-ATK-CAS", "Non-negative attacker casualties")
	_assert_true(context.get("defender_casualties", 0) >= 0, "TC-2E.6-DEF-CAS", "Non-negative defender casualties")

	# Troops must have been deducted from military power
	_assert_true(mil_fac.military_power < 75.0, "TC-2E.6-ATK-MIL-REDUCED", "Attacker military power reduced from casualties")
	_assert_true(mer_fac.military_power < 40.0, "TC-2E.6-DEF-MIL-REDUCED", "Defender military power reduced from casualties")

	# Verify relation data recorded last_battle_report
	var rel = fm.get_pairwise_relation_between("rival_military", "rival_merchant")
	_assert_false(rel.last_battle_report.is_empty(), "TC-2E.6-REL-REPORT", "last_battle_report recorded on relation")
	_assert_eq(rel.last_battle_report.get("day"), 6, "TC-2E.6-REPORT-DAY", "Battle report day is 6")

# -----------------------------------------------------------------------------
# TC-2E.7: Conservation of resources & strict plunder transfer
# -----------------------------------------------------------------------------
func _test_tc_2e_7_conservation_of_resources_and_plunder() -> void:
	print("\n--- TC-2E.7: Conservation of resources & strict plunder transfer ---")
	var fm := FactionManagerScript.new()
	var bcm := BattleCampaignManagerScript.new()
	bcm.set_faction_manager(fm)

	fm.declare_war_between_factions("rival_military", "rival_merchant", "Resource raid", 5)

	var mil_fac = fm.get_faction("rival_military")
	var mer_fac = fm.get_faction("rival_merchant")

	# Resources setup
	mil_fac.resources = {"gold": 50, "food": 50, "wood": 50}
	mer_fac.resources = {"gold": 200, "food": 100, "wood": 100}
	mil_fac.military_power = 90.0 # High power ensures attacker victory
	mer_fac.military_power = 15.0

	var camp = bcm.schedule_inter_faction_campaign("rival_military", "rival_merchant", 7, 1)
	var initial_total_gold: int = int(mil_fac.resources.get("gold", 0)) + int(mer_fac.resources.get("gold", 0))
	var initial_total_food: int = int(mil_fac.resources.get("food", 0)) + int(mer_fac.resources.get("food", 0))

	var results = bcm.process_daily_inter_faction_campaigns(7)
	_assert_eq(results.size(), 1, "TC-2E.7-RES", "Battle processed")

	var report = results[0]["report"]
	if report.victor == "attacker":
		var final_total_gold: int = int(mil_fac.resources.get("gold", 0)) + int(mer_fac.resources.get("gold", 0))
		var final_total_food: int = int(mil_fac.resources.get("food", 0)) + int(mer_fac.resources.get("food", 0))
		_assert_eq(final_total_gold, initial_total_gold, "TC-2E.7-CONSERVE-GOLD", "Gold strictly conserved across factions (no fabrication)")
		_assert_eq(final_total_food, initial_total_food, "TC-2E.7-CONSERVE-FOOD", "Food strictly conserved across factions (no fabrication)")
		_assert_true(int(mil_fac.resources.get("gold", 0)) > 50, "TC-2E.7-PLUNDER-GAINED", "Attacker gained plundered gold")
		_assert_true(int(mer_fac.resources.get("gold", 0)) < 200, "TC-2E.7-PLUNDER-LOST", "Defender lost plundered gold")

# -----------------------------------------------------------------------------
# TC-2E.8: Concrete world impact (outpost damage, sacking, stability loss)
# -----------------------------------------------------------------------------
func _test_tc_2e_8_concrete_world_impact_and_outpost_damage() -> void:
	print("\n--- TC-2E.8: Concrete world impact (outpost damage, sacking, stability loss) ---")
	var fm := FactionManagerScript.new()
	var bcm := BattleCampaignManagerScript.new()
	var fsm := FieldSiegeManagerScript.new()
	bcm.set_faction_manager(fm)
	bcm.set_custom_field_siege_manager(fsm)

	fm.declare_war_between_factions("rival_military", "rival_merchant", "Siege assault", 5)

	# Register defender outpost with 250 HP
	fsm.register_objective("outpost_rival_merchant", Vector2i(50, 16), "rival_merchant", 250.0, 3)

	var mil_fac = fm.get_faction("rival_military")
	var mer_fac = fm.get_faction("rival_merchant")
	mil_fac.military_power = 95.0
	mer_fac.military_power = 10.0
	mer_fac.stability = 60.0

	var camp = bcm.schedule_inter_faction_campaign("rival_military", "rival_merchant", 8, 1)
	var results = bcm.process_daily_inter_faction_campaigns(8)

	var obj = fsm.get_objective("outpost_rival_merchant")
	_assert_true(obj != null, "TC-2E.8-OUTPOST-EXISTS", "Outpost tracked")
	_assert_true(obj.health < 250.0, "TC-2E.8-OUTPOST-DAMAGED", "Outpost sustained real damage: health now %.1f" % obj.health)
	_assert_true(mer_fac.stability < 60.0, "TC-2E.8-STABILITY-LOST", "Defender lost stability from defeat: now %.1f" % mer_fac.stability)

# -----------------------------------------------------------------------------
# TC-2E.9: Autonomous peace declaration, war weariness, truce establishment & campaign cancellation
# -----------------------------------------------------------------------------
func _test_tc_2e_9_autonomous_peace_and_weariness() -> void:
	print("\n--- TC-2E.9: Autonomous peace declaration, war weariness, truce establishment & campaign cancellation ---")
	var planner := FactionDiplomacyPlannerScript.new()
	var fm := FactionManagerScript.new()
	var bcm := BattleCampaignManagerScript.new()
	bcm.set_faction_manager(fm)

	var mil_fac = fm.get_faction("rival_military")
	var mer_fac = fm.get_faction("rival_merchant")
	var pair_key: String = "rival_merchant__rival_military"
	var rel = fm.get_pairwise_relation(pair_key)

	# Setup active war that started on Day 1
	rel.is_at_war = true
	rel.war_start_day = 1
	rel.truce_until_day = 0
	mil_fac.military_power = 50.0
	mer_fac.military_power = 50.0

	# 1. Day 2: war has lasted only 1 day (< INTER_WAR_MIN_DURATION_DAYS) -> PEACE_TOO_EARLY
	var eval_early = planner.evaluate_pairwise_diplomatic_action(mil_fac, mer_fac, rel, 2)
	_assert_eq(eval_early.get("action_id"), FactionDiplomacyPlannerScript.ACTION_NONE, "TC-2E.9-EARLY-NONE", "Cannot peace out on day 2")
	_assert_eq(eval_early.get("reason_code"), FactionDiplomacyPlannerScript.REASON_PEACE_TOO_EARLY, "TC-2E.9-EARLY-REASON", "Reason is PEACE_TOO_EARLY")

	# 2. Day 14: war has lasted 13 days (>= INTER_WAR_WEARINESS_DAYS = 12) -> Evaluates ACTION_SIGN_PEACE
	var eval_weary = planner.evaluate_pairwise_diplomatic_action(mil_fac, mer_fac, rel, 14)
	_assert_eq(eval_weary.get("action_id"), FactionDiplomacyPlannerScript.ACTION_SIGN_PEACE, "TC-2E.9-WEARY-PEACE", "Evaluates peace due to war weariness")
	_assert_eq(eval_weary.get("reason_code"), FactionDiplomacyPlannerScript.REASON_PEACE_WAR_WEARINESS, "TC-2E.9-WEARY-REASON", "Reason is PEACE_WAR_WEARINESS")

	# 3. Schedule pending campaign for Day 16
	bcm.schedule_inter_faction_campaign("rival_military", "rival_merchant", 16, 2)
	_assert_true(bcm.has_pending_inter_faction_campaign_for_pair(pair_key), "TC-2E.9-HAS-PENDING", "Has pending campaign before peace")

	# 4. Sign peace on Day 14
	var cancelled_camps: Array = []
	bcm.inter_faction_campaign_cancelled.connect(func(camp_id: String, reason: String):
		cancelled_camps.append({"camp_id": camp_id, "reason": reason})
	)

	var peace_res = fm.sign_peace_between_factions("rival_military", "rival_merchant", 6, 14)
	_assert_true(peace_res.get("success", false), "TC-2E.9-PEACE-SUCCESS", "Peace signed")

	# Verify relation updated
	_assert_false(rel.is_at_war, "TC-2E.9-NOT-AT-WAR", "War state cleared")
	_assert_eq(rel.truce_until_day, 14 + 6, "TC-2E.9-TRUCE-SET", "Truce set until Day 20")
	_assert_true(rel.is_on_truce(15), "TC-2E.9-ON-TRUCE", "Is on truce on Day 15")

	# Pending campaign must have been automatically cancelled
	_assert_false(bcm.has_pending_inter_faction_campaign_for_pair(pair_key), "TC-2E.9-CAMP-CANCELLED", "Pending campaign cancelled on peace")
	_assert_eq(cancelled_camps.size(), 1, "TC-2E.9-CANCEL-SIGNAL", "Campaign cancelled signal emitted")

# -----------------------------------------------------------------------------
# TC-2E.10: Player isolation
# -----------------------------------------------------------------------------
func _test_tc_2e_10_player_isolation() -> void:
	print("\n--- TC-2E.10: Player isolation (zero mutation to player treaties, opinion, or raids) ---")
	var fm := FactionManagerScript.new()
	var bcm := BattleCampaignManagerScript.new()
	bcm.set_faction_manager(fm)

	var mil_fac = fm.get_faction("rival_military")
	var mer_fac = fm.get_faction("rival_merchant")

	# Player initial states
	mil_fac.opinion = 25.0
	mil_fac.has_nap = true
	mer_fac.opinion = 40.0
	mer_fac.has_alliance = true

	# NPC-NPC war declared and battle fought
	fm.declare_war_between_factions("rival_military", "rival_merchant", "Border dispute", 2)
	bcm.schedule_inter_faction_campaign("rival_military", "rival_merchant", 3, 1)
	bcm.process_daily_inter_faction_campaigns(3)

	# Verify player-facing fields remain untouched
	_assert_approx(mil_fac.opinion, 25.0, "TC-2E.10-MIL-PLAYER-OPINION", 0.001)
	_assert_true(mil_fac.has_nap, "TC-2E.10-MIL-PLAYER-NAP", "Player NAP intact")
	_assert_approx(mer_fac.opinion, 40.0, "TC-2E.10-MER-PLAYER-OPINION", 0.001)
	_assert_true(mer_fac.has_alliance, "TC-2E.10-MER-PLAYER-ALLY", "Player Alliance intact")
	_assert_false(mil_fac.is_at_war, "TC-2E.10-MIL-PLAYER-WAR", "Rival military not at war with player")
	_assert_false(mer_fac.is_at_war, "TC-2E.10-MER-PLAYER-WAR", "Rival merchant not at war with player")

# -----------------------------------------------------------------------------
# TC-2E.11: Trade caravan wartime price surcharge
# -----------------------------------------------------------------------------
func _test_tc_2e_11_trade_caravan_wartime_surcharge() -> void:
	print("\n--- TC-2E.11: Trade caravan wartime price surcharge (+15% markup) ---")
	var caravan_peace = TradeCaravanScript.generate_caravan(12345, 1, "rival_merchant", false)
	var caravan_war = TradeCaravanScript.generate_caravan(12345, 1, "rival_merchant", true)

	var res_id: String = EconomyConfigScript.RES_WOOD
	var price_peace: int = caravan_peace.get_effective_sell_price(res_id, 0.0)
	var price_war: int = caravan_war.get_effective_sell_price(res_id, 0.0)

	_assert_true(price_war > price_peace, "TC-2E.11-SURCHARGE-HIGHER", "Wartime price (%d) > Peaceful price (%d)" % [price_war, price_peace])
	_assert_eq(price_war, price_peace + 1, "TC-2E.11-SURCHARGE-VALUE", "Wartime price increases by risk surcharge (+1 min)")

# -----------------------------------------------------------------------------
# TC-2E.12: Deterministic simulation equivalence
# -----------------------------------------------------------------------------
func _test_tc_2e_12_deterministic_simulation_equivalence() -> void:
	print("\n--- TC-2E.12: Deterministic simulation equivalence ---")
	var run_sim = func(test_seed: int) -> Dictionary:
		var fm := FactionManagerScript.new()
		var bcm := BattleCampaignManagerScript.new()
		bcm.set_faction_manager(fm)
		fm.declare_war_between_factions("rival_military", "rival_merchant", "Border clash", 3)
		var mil = fm.get_faction("rival_military")
		var mer = fm.get_faction("rival_merchant")
		mil.military_power = 65.0
		mer.military_power = 45.0
		bcm.schedule_inter_faction_campaign("rival_military", "rival_merchant", 5, 1)

		seed(test_seed)
		var results = bcm.process_daily_inter_faction_campaigns(5)
		var rep = results[0]["report"]
		var ctx = results[0]["context"]
		return {
			"victor": rep.victor,
			"attacker_casualties": ctx.get("attacker_casualties"),
			"defender_casualties": ctx.get("defender_casualties"),
			"attacker_score": rep.details.get("attacker_combat_score"),
			"defender_score": rep.details.get("defender_combat_score")
		}

	var res1 = run_sim.call(424242)
	var res2 = run_sim.call(424242)

	_assert_eq(res1["victor"], res2["victor"], "TC-2E.12-VICTOR-MATCH", "Identical victor across identical seeds")
	_assert_eq(res1["attacker_casualties"], res2["attacker_casualties"], "TC-2E.12-ATK-CAS-MATCH", "Identical attacker casualties")
	_assert_eq(res1["defender_casualties"], res2["defender_casualties"], "TC-2E.12-DEF-CAS-MATCH", "Identical defender casualties")
	_assert_approx(res1["attacker_score"], res2["attacker_score"], "TC-2E.12-ATK-SCORE-MATCH", 0.0001)
	_assert_approx(res1["defender_score"], res2["defender_score"], "TC-2E.12-DEF-SCORE-MATCH", 0.0001)

# -----------------------------------------------------------------------------
# TC-2E.13: Save / Load roundtrip persistence & fail-closed schema validation
# -----------------------------------------------------------------------------
func _test_tc_2e_13_save_load_roundtrip_persistence() -> void:
	print("\n--- TC-2E.13: Save / Load roundtrip persistence & fail-closed schema validation ---")
	var fm := FactionManagerScript.new()
	var bcm := BattleCampaignManagerScript.new()
	bcm.set_faction_manager(fm)

	# Setup pairwise war, truce, pending campaign, processed campaign, and battle report
	var pair_key: String = "rival_merchant__rival_military"
	var rel = fm.get_pairwise_relation(pair_key)
	rel.is_at_war = true
	rel.war_start_day = 4
	rel.casus_belli = "Strategic Rivalry"
	rel.war_count = 2
	rel.truce_until_day = 18
	rel.last_battle_report = {
		"day": 6,
		"victor": "rival_military",
		"casualties_a": 4,
		"casualties_b": 9
	}

	bcm.schedule_inter_faction_campaign("rival_military", "rival_merchant", 8, 1)

	# Serialize
	var bcm_data: Dictionary = bcm.serialize()
	var fm_rel_data: Dictionary = fm.serialize_pairwise_relations()
	var fm_exec_data: Dictionary = fm.serialize_executor_state()

	# Validate schema using SaveManager
	var test_save_payload: Dictionary = {
		"schema_version": SaveManagerScript.SAVE_SCHEMA_VERSION,
		"game_version": "0.1.0",
		"timestamp": 12345678,
		"metadata": {"version": "0.1.0", "world_id": "test_world"},
		"world": {"seed": 12345, "width": 64, "height": 64, "tiles": []},
		"resources": {
			"stocks": {},
			"production_rates": {},
			"consumption_rates": {}
		},
		"citizens": [],
		"time": {"current_day": 7, "current_hour": 10.0, "current_year": 1, "simulation_speed": 1},
		"buildings": [],
		"research": {"unlocked_techs": [], "active_tech_id": "", "active_progress_hours": 0.0},
		"factions": {
			"relations": fm_rel_data,
			"pairwise_relations": fm_rel_data,
			"strategy_planner": {},
			"strategy_executor": fm_exec_data,
			"factions": {}
		},
		"battle_campaign": bcm_data,
		"player_army": {},
		"dynamic_workplaces": {}
	}

	var sm := SaveManagerScript.new()
	var val_result: Dictionary = sm.validate_save_data(test_save_payload)
	_assert_true(val_result.get("valid", false), "TC-2E.13-SCHEMA-VALID", "Save schema valid with inter-faction data (error: %s)" % val_result.get("error", ""))

	# Deserialize into new managers
	var fm_new := FactionManagerScript.new()
	var bcm_new := BattleCampaignManagerScript.new()
	bcm_new.set_faction_manager(fm_new)

	fm_new.deserialize_pairwise_relations(fm_rel_data)
	bcm_new.deserialize(bcm_data)

	var rel_restored = fm_new.get_pairwise_relation(pair_key)
	_assert_true(rel_restored.is_at_war, "TC-2E.13-RESTORE-WAR", "War restored")
	_assert_eq(rel_restored.war_start_day, 4, "TC-2E.13-RESTORE-START-DAY", "war_start_day restored")
	_assert_eq(rel_restored.casus_belli, "Strategic Rivalry", "TC-2E.13-RESTORE-CB", "casus_belli restored")
	_assert_eq(rel_restored.war_count, 2, "TC-2E.13-RESTORE-COUNT", "war_count restored")
	_assert_eq(rel_restored.truce_until_day, 18, "TC-2E.13-RESTORE-TRUCE", "truce_until_day restored")
	_assert_eq(rel_restored.last_battle_report.get("victor"), "rival_military", "TC-2E.13-RESTORE-REP-VICTOR", "last_battle_report victor restored")

	_assert_true(bcm_new.has_pending_inter_faction_campaign_for_pair(pair_key), "TC-2E.13-RESTORE-BCM-PENDING", "Pending campaign restored in BCM")

# -----------------------------------------------------------------------------
# TC-2E.14: HUD integration & authoritative state display
# -----------------------------------------------------------------------------
func _test_tc_2e_14_hud_integration_authoritative_state() -> void:
	print("\n--- TC-2E.14: HUD integration & authoritative state display ---")
	var hud = world_instance.get_node_or_null("HUD")
	_assert_true(hud != null, "TC-2E.14-HUD-EXISTS", "HUD exists in world scene")

	var fm: Object = world_instance.get("faction_mgr")
	var bcm: Object = world_instance.get("battle_campaign_mgr")
	_assert_true(fm != null, "TC-2E.14-FM-EXISTS", "World has faction_mgr")
	_assert_true(bcm != null, "TC-2E.14-BCM-EXISTS", "World has battle_campaign_mgr")

	# Test signal wiring & event banner
	hud.show_event_banner("Tin Chiến Sự Thế Giới!", "⚔️ Phe Quân Sự đã tuyên chiến với Phe Thương Nhân!", false, 1.0)
	var banner = hud.get_node_or_null("EventBanner")
	_assert_true(banner != null, "TC-2E.14-BANNER-EXISTS", "EventBanner exists")
	_assert_true(banner.visible, "TC-2E.14-BANNER-VISIBLE", "Banner is visible when triggered")

	# Test diplomacy UI refresh creates Section 3
	hud._refresh_diplomacy_ui()
	var list_vbox = hud.get_node_or_null("DiplomacyPanel/MarginContainer/VBoxContainer/ScrollContainer/FactionsListVBox")
	_assert_true(list_vbox != null, "TC-2E.14-LIST-EXISTS", "FactionsListVBox exists")
	_assert_true(list_vbox.get_child_count() > 3, "TC-2E.14-LIST-HAS-CHILDREN", "List populated with faction cards + Section 3")

# -----------------------------------------------------------------------------
# TC-2E.15: Verification of 6 Review Bug Fixes (BUG-2E-01 to BUG-2E-06)
# -----------------------------------------------------------------------------
func _test_tc_2e_15_bug_fixes_verification() -> void:
	print("\n--- TC-2E.15: Verification of 6 Review Bug Fixes (BUG-2E-01 to BUG-2E-06) ---")

	# 1. BUG-2E-01: Real end-to-end HUD signal integration for inter-faction battle
	print("  - BUG-2E-01: Verifying real end-to-end HUD signal integration...")
	var hud = world_instance.get_node_or_null("HUD")
	_assert_true(hud != null, "TC-2E.15-BUG-01-HUD-EXISTS", "HUD exists in world for signal check")
	var event_banner = hud.get_node_or_null("EventBanner")
	_assert_true(event_banner != null, "TC-2E.15-BUG-01-BANNER-NODE", "EventBanner node exists on HUD")
	var banner_title_lbl = event_banner.get_node_or_null("MarginContainer/VBoxContainer/EventTitle")

	# Set up real BattleCampaignManager connected to HUD
	var test_bcm := BattleCampaignManagerScript.new()
	var test_fm := FactionManagerScript.new()
	test_bcm.set_faction_manager(test_fm)
	test_bcm.world_seed = 12345

	# Connect signals directly to HUD (replicating hud.connect_subsystems)
	if not test_bcm.battle_resolved.is_connected(hud._on_battle_resolved):
		test_bcm.battle_resolved.connect(hud._on_battle_resolved)
	if not test_bcm.inter_faction_battle_resolved.is_connected(hud._on_inter_faction_battle_resolved):
		test_bcm.inter_faction_battle_resolved.connect(hud._on_inter_faction_battle_resolved)

	# Setup at-war factions
	test_fm.set_faction_pair_opinion("rival_military", "rival_merchant", -70.0)
	test_fm.set_faction_pair_opinion("rival_merchant", "rival_military", -70.0)
	var rel_init = test_fm.get_pairwise_relation_between("rival_military", "rival_merchant")
	rel_init.is_at_war = true
	rel_init.war_start_day = 1

	# Schedule and resolve a real campaign through test_bcm
	var sched = test_bcm.schedule_inter_faction_campaign("rival_military", "rival_merchant", 4, 1, "End-to-end signal test")
	_assert_true(sched.get("success", false), "TC-2E.15-BUG-01-SCHED-OK", "Scheduled inter-faction campaign")
	var camp_id: String = sched.get("campaign_id")

	# Resolving the campaign emits BOTH battle_resolved and inter_faction_battle_resolved through real signal dispatch
	var res_battle = test_bcm.resolve_inter_faction_campaign(camp_id, 4)
	_assert_true(res_battle.get("success", false), "TC-2E.15-BUG-01-RESOLVE-OK", "Resolved campaign")

	# Inspect HUD state after both signals fired
	var live_banner_title: String = banner_title_lbl.text if banner_title_lbl != null else ""
	_assert_true("KẾT QUẢ CHIẾN SỰ" in live_banner_title, "TC-2E.15-BUG-01-WORLD-BANNER-ACTIVE", "World war outcome banner active: %s" % live_banner_title)
	_assert_false("THẤT THỦ!" in live_banner_title, "TC-2E.15-BUG-01-NO-DEFEAT-BANNER", "Settlement defeat banner 'THẤT THỦ!' was NOT triggered")
	_assert_false("THẮNG TRẬN!" in live_banner_title, "TC-2E.15-BUG-01-NO-WIN-BANNER", "Settlement victory banner 'THẮNG TRẬN!' was NOT triggered")
	_assert_false("CHIẾN DỊCH THẤT BẠI!" in live_banner_title, "TC-2E.15-BUG-01-NO-CAMPAIGN-FAIL", "Settlement offensive fail banner was NOT triggered")

	# 2. BUG-2E-02: TradeCaravan is_origin_at_war persistence through SaveManager
	print("  - BUG-2E-02: Verifying TradeCaravan wartime flag persistence...")
	var caravan_war = TradeCaravanScript.generate_caravan(12345, 10, "rival_merchant", true)
	_assert_true(caravan_war.is_origin_at_war, "TC-2E.15-BUG-02-INIT-FLAG", "Caravan initialized with is_origin_at_war = true")

	# Test direct serialize / deserialize
	var car_dict: Dictionary = caravan_war.serialize()
	_assert_true(car_dict.has("is_origin_at_war"), "TC-2E.15-BUG-02-SER-HAS-KEY", "Serialized dict contains is_origin_at_war")
	_assert_true(car_dict.get("is_origin_at_war"), "TC-2E.15-BUG-02-SER-VAL", "Serialized value is true")

	var car_deser = TradeCaravanScript.deserialize(car_dict)
	_assert_true(car_deser.is_origin_at_war, "TC-2E.15-BUG-02-DESER-VAL", "Deserialized caravan has is_origin_at_war = true")
	var base_wood_price: int = caravan_war.sell_prices.get(EconomyConfigScript.RES_WOOD, 3)
	_assert_true(car_deser.get_effective_sell_price(EconomyConfigScript.RES_WOOD, 0.0) > base_wood_price, "TC-2E.15-BUG-02-PRICE-SURCHARGED", "Wartime price surcharge preserved after deserialize")

	# Test backward compatibility: old save without is_origin_at_war
	var old_car_dict: Dictionary = car_dict.duplicate(true)
	old_car_dict.erase("is_origin_at_war")
	var car_old_compat = TradeCaravanScript.deserialize(old_car_dict)
	_assert_false(car_old_compat.is_origin_at_war, "TC-2E.15-BUG-02-OLD-COMPAT", "Old save without flag defaults safely to false")

	# Real SaveManager persistence check with isolated temporary directory
	var temp_dir := "user://__test_temp__/package_2e/"
	if not DirAccess.dir_exists_absolute(temp_dir):
		DirAccess.make_dir_recursive_absolute(temp_dir)
	var temp_save_path := temp_dir + "test_p2e_caravan_persistence.json"
	world_instance.set("active_caravan", caravan_war)
	var save_res = SaveManagerScript.save_to_file(world_instance, temp_save_path)
	_assert_true(save_res.get("success", false), "TC-2E.15-BUG-02-SM-SAVE-OK", "SaveManager successfully saved world with active caravan")

	world_instance.set("active_caravan", null)
	var load_res = SaveManagerScript.load_from_file(temp_save_path)
	_assert_true(load_res.get("success", false), "TC-2E.15-BUG-02-SM-LOAD-OK", "SaveManager successfully loaded file")
	var apply_res = SaveManagerScript.apply_loaded_state_to_world(world_instance, load_res.get("data", {}))
	_assert_true(apply_res.get("success", false), "TC-2E.15-BUG-02-SM-APPLY-OK", "SaveManager successfully applied loaded state")

	var restored_caravan = world_instance.get("active_caravan")
	_assert_true(restored_caravan != null, "TC-2E.15-BUG-02-CARAVAN-RESTORED", "Active caravan restored by SaveManager")
	_assert_true(restored_caravan.is_origin_at_war, "TC-2E.15-BUG-02-CARAVAN-WAR-PERSISTED", "is_origin_at_war is true after full SaveManager load")
	_assert_true(restored_caravan.get_effective_sell_price(EconomyConfigScript.RES_WOOD, 0.0) > base_wood_price, "TC-2E.15-BUG-02-SURCHARGE-AFTER-LOAD", "Wartime surcharge active after full SaveManager load")

	# Clean up temporary test file and directory
	if FileAccess.file_exists(temp_save_path):
		DirAccess.remove_absolute(temp_save_path)
	if DirAccess.dir_exists_absolute(temp_dir):
		DirAccess.remove_absolute(temp_dir)

	# 3. BUG-2E-03: FactionManager self-protecting diplomacy rules (treaties & truce)
	print("  - BUG-2E-03: Verifying FactionManager treaty & truce protection...")
	var fm := FactionManagerScript.new()
	fm.set_custom_current_day(5)

	# 3a. Block war when Alliance active
	fm.set_faction_pair_opinion("rival_merchant", "rival_military", 70.0)
	fm.set_faction_pair_opinion("rival_military", "rival_merchant", 65.0)
	fm.sign_alliance_between_factions("rival_merchant", "rival_military")
	var war_under_alliance = fm.declare_war_between_factions("rival_military", "rival_merchant", "Attack ally", 5)
	_assert_false(war_under_alliance.get("success", true), "TC-2E.15-BUG-03-ALLIANCE-BLOCKED", "War declaration blocked by Alliance")
	_assert_eq(war_under_alliance.get("reason_code"), FactionManagerScript.PAIR_REASON_ERR_BLOCKED_BY_TREATY, "TC-2E.15-BUG-03-ALLIANCE-REASON", "Reason is ERR_BLOCKED_BY_TREATY")
	_assert_true(fm.do_factions_have_alliance("rival_merchant", "rival_military"), "TC-2E.15-BUG-03-ALLIANCE-UNTOUCHED", "Alliance treaty preserved")

	# 3b. Block war when NAP active
	var rel_nm = fm.get_pairwise_relation_between("neutral_tribe", "rival_military")
	rel_nm.has_alliance = false
	rel_nm.has_nap = true
	var war_under_nap = fm.declare_war_between_factions("rival_military", "neutral_tribe", "Attack NAP partner", 5)
	_assert_false(war_under_nap.get("success", true), "TC-2E.15-BUG-03-NAP-BLOCKED", "War declaration blocked by NAP")
	_assert_eq(war_under_nap.get("reason_code"), FactionManagerScript.PAIR_REASON_ERR_BLOCKED_BY_TREATY, "TC-2E.15-BUG-03-NAP-REASON", "Reason is ERR_BLOCKED_BY_TREATY")
	_assert_true(rel_nm.has_nap, "TC-2E.15-BUG-03-NAP-UNTOUCHED", "NAP treaty preserved")

	# 3c. Block war during Truce
	rel_nm.has_nap = false
	rel_nm.truce_until_day = 11
	var war_under_truce = fm.declare_war_between_factions("rival_military", "neutral_tribe", "Break truce", 7)
	_assert_false(war_under_truce.get("success", true), "TC-2E.15-BUG-03-TRUCE-BLOCKED", "War declaration blocked by Truce at Day 7")
	_assert_eq(war_under_truce.get("reason_code"), FactionManagerScript.PAIR_REASON_ERR_ON_TRUCE, "TC-2E.15-BUG-03-TRUCE-REASON", "Reason is ERR_ON_TRUCE")

	# 3d. Missing day parameter cannot bypass Truce (fail-closed if day cannot be resolved)
	fm.set_custom_current_day(-999)
	var war_no_day = fm.declare_war_between_factions("rival_military", "neutral_tribe", "Break truce with no day", -1)
	_assert_false(war_no_day.get("success", true), "TC-2E.15-BUG-03-NO-DAY-FAIL-CLOSED", "Missing day fails closed when truce is present")
	_assert_eq(war_no_day.get("reason_code"), FactionManagerScript.PAIR_REASON_ERR_INVALID_DAY, "TC-2E.15-BUG-03-NO-DAY-CODE", "Reason is ERR_INVALID_DAY")

	# 3e. War allowed after Truce expires
	var war_post_truce = fm.declare_war_between_factions("rival_military", "neutral_tribe", "Post truce war", 11)
	_assert_true(war_post_truce.get("success", false), "TC-2E.15-BUG-03-POST-TRUCE-OK", "War allowed after Truce expires on Day 11")
	_assert_true(fm.are_factions_at_war("neutral_tribe", "rival_military"), "TC-2E.15-BUG-03-AT-WAR", "Factions now at war")

	# 4. BUG-2E-04: Auto-recovery of campaigns for at-war pairs missing pending campaigns
	print("  - BUG-2E-04: Verifying auto-recovery of missing campaigns...")
	var bcm := BattleCampaignManagerScript.new()
	bcm.set_faction_manager(fm)

	var p_key_nm: String = "neutral_tribe__rival_military"
	bcm.cancel_inter_faction_campaigns_for_pair(p_key_nm, "Simulated missing campaign")
	_assert_false(bcm.has_pending_inter_faction_campaign_for_pair(p_key_nm), "TC-2E.15-BUG-04-NO-PENDING-BEFORE", "No pending campaign initially")

	# 4a. Inactive faction blocks recovery
	var fac_tribe = fm.get_faction("neutral_tribe")
	fac_tribe.existence_status = FactionDataScript.STATUS_IN_EXILE
	bcm.process_daily_inter_faction_campaigns(11)
	_assert_false(bcm.has_pending_inter_faction_campaign_for_pair(p_key_nm), "TC-2E.15-BUG-04-INACTIVE-NO-RECOVERY", "Recovery rejected when faction is inactive")

	# 4b. Reactivating faction allows daily tick to recover
	fac_tribe.existence_status = FactionDataScript.STATUS_ACTIVE
	# Set a last battle report with sequence 2 to verify sequence increment
	rel_nm.last_battle_report = {
		"sequence": 2,
		"attacker_id": "neutral_tribe",
		"defender_id": "rival_military"
	}
	bcm.process_daily_inter_faction_campaigns(11)
	_assert_true(bcm.has_pending_inter_faction_campaign_for_pair(p_key_nm), "TC-2E.15-BUG-04-RECOVERED", "Campaign auto-recovered on daily tick once active")
	var rec_camp = bcm.get_pending_inter_faction_campaign_for_pair(p_key_nm)
	_assert_eq(rec_camp.get("scheduled_day"), 11 + BattleCampaignManagerScript.INTER_FACTION_CAMPAIGN_PREP_DAYS, "TC-2E.15-BUG-04-PREP-DAYS", "Scheduled with 2-day prep delay (Day 13)")
	_assert_eq(rec_camp.get("sequence"), 3, "TC-2E.15-BUG-04-SEQ-INCREMENTED", "Recovered sequence increments from last_battle_report (2 + 1 = 3)")
	_assert_eq(rec_camp.get("attacker_id"), "rival_military", "TC-2E.15-BUG-04-ROLE-SWITCHED", "Roles switched from last battle report attacker")

	# 4c. Running on Day 12 must NOT duplicate or reset the prep day
	bcm.process_daily_inter_faction_campaigns(12)
	var rec_camp_day12 = bcm.get_pending_inter_faction_campaign_for_pair(p_key_nm)
	_assert_eq(rec_camp_day12.get("scheduled_day"), 13, "TC-2E.15-BUG-04-NO-RESET", "Scheduled day remains Day 13 without resetting")
	_assert_eq(bcm.get_all_pending_inter_faction_campaigns().size(), 1, "TC-2E.15-BUG-04-NO-DUPLICATE", "No duplicate campaigns generated")

	# 4d. Signing peace cancels the recovered campaign
	fm.sign_peace_between_factions("rival_military", "neutral_tribe", 6, 12)
	_assert_false(bcm.has_pending_inter_faction_campaign_for_pair(p_key_nm), "TC-2E.15-BUG-04-PEACE-CANCELLED", "Peace cancels recovered campaign")

	# 5. BUG-2E-05: Outpost damage visual redraw trigger verified via test spy
	print("  - BUG-2E-05: Verifying outpost redraw call on damage via test spy...")
	var fsm := FieldSiegeManagerScript.new()
	var spy_outpost = SpyObjectiveActor.new()
	spy_outpost.objective_id = "outpost_neutral_tribe"
	spy_outpost.owning_faction_id = "neutral_tribe"
	spy_outpost.health = 200.0
	spy_outpost.max_health = 200.0
	spy_outpost.is_alive = true
	fsm.objectives["outpost_neutral_tribe"] = spy_outpost
	bcm.set_custom_field_siege_manager(fsm)

	_assert_eq(spy_outpost.redraw_called_count, 0, "TC-2E.15-BUG-05-REDRAW-ZERO-INIT", "Spy outpost redraw count is initially 0")

	# Prepare war targeting neutral_tribe outpost
	fm.set_faction_pair_opinion("rival_military", "neutral_tribe", -70.0)
	fm.set_faction_pair_opinion("neutral_tribe", "rival_military", -70.0)
	var rel_nm_war = fm.get_pairwise_relation_between("rival_military", "neutral_tribe")
	rel_nm_war.is_at_war = true
	rel_nm_war.war_start_day = 12

	var camp_outpost = bcm.schedule_inter_faction_campaign("rival_military", "neutral_tribe", 14, 1, "Outpost siege test")
	_assert_true(camp_outpost.get("success", false), "TC-2E.15-BUG-05-OUTPOST-CAMP-SCHED", "Campaign targeting outpost scheduled")
	var camp_outpost_id: String = camp_outpost.get("campaign_id")

	# Resolve battle where rival_military attacks and damages the outpost
	var res_outpost = bcm.resolve_inter_faction_campaign(camp_outpost_id, 14)
	_assert_true(res_outpost.get("success", false), "TC-2E.15-BUG-05-OUTPOST-RESOLVE-OK", "Outpost campaign resolved")
	_assert_true(spy_outpost.redraw_called_count >= 1, "TC-2E.15-BUG-05-REDRAW-INVOKED", "Outpost queue_redraw() was invoked on damage (called %d times)" % spy_outpost.redraw_called_count)

	spy_outpost.free()

	# 6. BUG-2E-06 & BUG-2E-08: propose_treaty_between_factions peace fail-closed validation & truce setting
	print("  - BUG-2E-08: Verifying propose_treaty_between_factions day resolution and fail-closed validation...")
	var rel_mm = fm.get_pairwise_relation_between("rival_military", "rival_merchant")
	rel_mm.has_alliance = false
	rel_mm.has_nap = false
	rel_mm.is_at_war = true
	rel_mm.truce_until_day = -1
	rel_mm.opinion_a_to_b = -50.0
	rel_mm.opinion_b_to_a = -50.0

	# 6a. Explicit day passed -> Sets 6-day truce accurately (Day 20 -> Day 26)
	var treaty_res_explicit = fm.propose_treaty_between_factions("rival_military", "rival_merchant", "peace", 20)
	_assert_true(treaty_res_explicit.get("success", false), "TC-2E.15-BUG-08-EXPLICIT-OK", "Peace succeeds with explicit day")
	_assert_eq(rel_mm.truce_until_day, 26, "TC-2E.15-BUG-08-EXPLICIT-TRUCE", "truce_until_day set to 26 (20 + 6)")
	_assert_false(rel_mm.is_at_war, "TC-2E.15-BUG-08-EXPLICIT-WAR-CLEARED", "War cleared")

	# Reset for test 6b: Day resolved via TimeManager
	rel_mm.is_at_war = true
	rel_mm.truce_until_day = -1
	rel_mm.opinion_a_to_b = -50.0
	rel_mm.opinion_b_to_a = -50.0
	fm.set_custom_current_day(15) # Simulates active day 15
	var treaty_res_tm = fm.propose_treaty_between_factions("rival_military", "rival_merchant", "peace")
	_assert_true(treaty_res_tm.get("success", false), "TC-2E.15-BUG-08-TM-DAY-OK", "Peace succeeds when day is resolved via TimeManager/source")
	_assert_eq(rel_mm.truce_until_day, 21, "TC-2E.15-BUG-08-TM-DAY-TRUCE", "truce_until_day set to 21 (15 + 6)")
	_assert_false(rel_mm.is_at_war, "TC-2E.15-BUG-08-TM-WAR-CLEARED", "War cleared")

	# Reset for test 6c: Unresolvable day must fail closed with ERR_INVALID_DAY and ZERO mutation
	rel_mm.is_at_war = true
	rel_mm.truce_until_day = -1
	rel_mm.opinion_a_to_b = -50.0
	rel_mm.opinion_b_to_a = -50.0
	fm.set_custom_current_day(-999) # Explicit sentinel simulating no valid time source

	var treaty_res_unresolvable = fm.propose_treaty_between_factions("rival_military", "rival_merchant", "peace")
	_assert_false(treaty_res_unresolvable.get("success", true), "TC-2E.15-BUG-08-UNRESOLVABLE-FAIL", "Peace rejected when day cannot be resolved")
	_assert_eq(treaty_res_unresolvable.get("reason_code"), FactionManagerScript.PAIR_REASON_ERR_INVALID_DAY, "TC-2E.15-BUG-08-UNRESOLVABLE-CODE", "Reason code is ERR_INVALID_DAY")
	_assert_true(rel_mm.is_at_war, "TC-2E.15-BUG-08-NO-MUTATION-WAR", "is_at_war remains true (zero mutation)")
	_assert_eq(rel_mm.truce_until_day, -1, "TC-2E.15-BUG-08-NO-MUTATION-TRUCE", "truce_until_day remains -1 (zero mutation)")
	_assert_approx(rel_mm.opinion_a_to_b, -50.0, "TC-2E.15-BUG-08-NO-MUTATION-OP-AB")
	_assert_approx(rel_mm.opinion_b_to_a, -50.0, "TC-2E.15-BUG-08-NO-MUTATION-OP-BA")

	# 6d. NAP and Alliance proposals remain functional and unaffected by day parameter
	fm.set_faction_pair_opinion("neutral_tribe", "rival_merchant", 20.0)
	fm.set_faction_pair_opinion("rival_merchant", "neutral_tribe", 20.0)
	var rel_nt_rm = fm.get_pairwise_relation_between("neutral_tribe", "rival_merchant")
	rel_nt_rm.is_at_war = false
	var nap_res = fm.propose_treaty_between_factions("neutral_tribe", "rival_merchant", "nap")
	_assert_true(nap_res.get("success", false), "TC-2E.15-BUG-08-NAP-UNAFFECTED", "NAP proposal succeeds independently of day")
	_assert_true(rel_nt_rm.has_nap, "TC-2E.15-BUG-08-NAP-SIGNED", "NAP signed successfully")

# -----------------------------------------------------------------------------
# TC-2E.16: Campaign Sequence & Lifecycle Interval Across Consecutive Battles (BUG-2E-07)
# -----------------------------------------------------------------------------
func _test_tc_2e_16_campaign_sequence_and_lifecycle_interval() -> void:
	print("\n--- TC-2E.16: Campaign Sequence & Lifecycle Interval Across Consecutive Battles (BUG-2E-07) ---")
	var fm := FactionManagerScript.new()
	var bcm := BattleCampaignManagerScript.new()
	bcm.set_faction_manager(fm)
	bcm.world_seed = 12345

	# Factions setup with ample power and stability to sustain multiple battles
	var mil_fac: FactionData = fm.get_faction("rival_military")
	var merch_fac: FactionData = fm.get_faction("rival_merchant")
	mil_fac.military_power = 95.0
	mil_fac.stability = 90.0
	merch_fac.military_power = 90.0
	merch_fac.stability = 85.0

	# Fortified outpost with high durability so it is not sacked prematurely
	var fsm := FieldSiegeManagerScript.new()
	var outpost_merch = fsm.register_objective("outpost_rival_merchant", Vector2i(30, 30), "rival_merchant", 500.0, 4)
	var outpost_mil = fsm.register_objective("outpost_rival_military", Vector2i(10, 10), "rival_military", 500.0, 4)
	bcm.set_custom_field_siege_manager(fsm)

	# 1. Initialize war on Day 4
	bcm.set_custom_current_day(4)
	fm.set_faction_pair_opinion("rival_military", "rival_merchant", -60.0)
	fm.set_faction_pair_opinion("rival_merchant", "rival_military", -60.0)
	var war_decl = fm.declare_war_between_factions("rival_military", "rival_merchant", "War for territory", 4)
	_assert_true(war_decl.get("success", false), "TC-2E.16-WAR-INIT", "War initialized between rival_military and rival_merchant")

	# 1b. Verify initial campaign auto-scheduled for Day 6 (Day 4 + 2 prep delay) with sequence 1
	var pair_km = "rival_merchant__rival_military"
	_assert_true(bcm.has_pending_inter_faction_campaign_for_pair(pair_km), "TC-2E.16-INIT-SCHED-EXISTS", "Initial campaign auto-scheduled for pair")
	var init_camp = bcm.get_pending_inter_faction_campaign_for_pair(pair_km)
	_assert_eq(init_camp.get("scheduled_day"), 6, "TC-2E.16-INIT-DAY-6", "Initial campaign scheduled for Day 6")
	_assert_eq(init_camp.get("sequence"), 1, "TC-2E.16-INIT-SEQ-1", "Initial campaign has sequence 1")

	# 2. Run first battle on Day 6
	bcm.set_custom_current_day(6)
	var daily_res_6 = bcm.process_daily_inter_faction_campaigns(6)
	_assert_eq(daily_res_6.size(), 1, "TC-2E.16-BATTLE-1-RESOLVED-COUNT", "Battle 1 resolved on Day 6")
	_assert_true(daily_res_6[0].get("success", false), "TC-2E.16-BATTLE-1-SUCCESS", "Battle 1 succeeded")
	_assert_false(daily_res_6[0].get("peace_signed", true), "TC-2E.16-BATTLE-1-WAR-CONTINUES", "War continues after Battle 1")

	# 3. Check subsequent campaign scheduled at exactly Day 10 (Day 6 + 4, NOT Day 8) with sequence 2
	var pending_camps_post_6 = bcm.get_all_pending_inter_faction_campaigns()
	_assert_eq(pending_camps_post_6.size(), 1, "TC-2E.16-POST-1-PENDING-COUNT", "Exactly one pending campaign after Battle 1")
	var camp_2 = pending_camps_post_6[0]
	_assert_eq(camp_2.get("scheduled_day"), 10, "TC-2E.16-BATTLE-2-DAY-10", "Next campaign scheduled on Day 10 (Day + 4, NOT Day 8)")
	_assert_eq(camp_2.get("sequence"), 2, "TC-2E.16-BATTLE-2-SEQ-2", "Next campaign has sequence 2")
	_assert_eq(camp_2.get("attacker_id"), "rival_merchant", "TC-2E.16-BATTLE-2-COUNTER-ATTACKER", "Attacker switched to counter-attacking defender")
	_assert_eq(camp_2.get("defender_id"), "rival_military", "TC-2E.16-BATTLE-2-DEFENDER", "Defender switched to rival_military")

	# 4. Advance through intervening days (Day 7, 8, 9) and verify no duplicate or early resolution
	for d in [7, 8, 9]:
		bcm.set_custom_current_day(d)
		var mid_res = bcm.process_daily_inter_faction_campaigns(d)
		_assert_eq(mid_res.size(), 0, "TC-2E.16-DAY-%d-NO-BATTLE" % d, "No battle prematurely resolved on Day %d" % d)
		_assert_eq(bcm.get_all_pending_inter_faction_campaigns().size(), 1, "TC-2E.16-DAY-%d-ONE-PENDING" % d, "Still exactly one pending campaign on Day %d" % d)

	# 5. Run second battle on Day 10
	bcm.set_custom_current_day(10)
	var daily_res_10 = bcm.process_daily_inter_faction_campaigns(10)
	_assert_eq(daily_res_10.size(), 1, "TC-2E.16-BATTLE-2-RESOLVED-COUNT", "Battle 2 resolved on Day 10")
	_assert_true(daily_res_10[0].get("success", false), "TC-2E.16-BATTLE-2-SUCCESS", "Battle 2 succeeded")
	_assert_false(daily_res_10[0].get("peace_signed", true), "TC-2E.16-BATTLE-2-WAR-CONTINUES", "War continues after Battle 2")

	# 6. Check third campaign scheduled at Day 14 (Day 10 + 4) with sequence 3
	var pending_camps_post_10 = bcm.get_all_pending_inter_faction_campaigns()
	_assert_eq(pending_camps_post_10.size(), 1, "TC-2E.16-POST-2-PENDING-COUNT", "Exactly one pending campaign after Battle 2")
	var camp_3 = pending_camps_post_10[0]
	_assert_eq(camp_3.get("scheduled_day"), 14, "TC-2E.16-BATTLE-3-DAY-14", "Third campaign scheduled on Day 14 (Day 10 + 4)")
	_assert_eq(camp_3.get("sequence"), 3, "TC-2E.16-BATTLE-3-SEQ-3", "Third campaign has sequence 3")
	_assert_eq(camp_3.get("attacker_id"), "rival_military", "TC-2E.16-BATTLE-3-ATTACKER", "Attacker switched back to rival_military")
	_assert_eq(camp_3.get("defender_id"), "rival_merchant", "TC-2E.16-BATTLE-3-DEFENDER", "Defender switched back to rival_merchant")

	# 7. Verify no duplicate campaigns across multiple recovery probes
	bcm.recover_missing_inter_faction_campaigns(10)
	bcm.recover_missing_inter_faction_campaigns(11)
	_assert_eq(bcm.get_all_pending_inter_faction_campaigns().size(), 1, "TC-2E.16-NO-DUPLICATES", "No duplicate campaigns generated by recovery or tick")

	outpost_merch.free()
	outpost_mil.free()
