extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — Package 1U: Pairwise Faction Relations Foundation
## Validates canonical, persistent, deterministic NPC-to-NPC pairwise relationships:
## - TC-FREL.1: Default initialization & canonical pair keys across all 3 unordered NPC faction pairs
## - TC-FREL.2: Canonical pair identity & symmetry (`(A, B)` and `(B, A)` resolve to the exact same record)
## - TC-FREL.3: Directional opinion independence, clamping (`[-100.0, 100.0]`), and disposition calculation
## - TC-FREL.4: Self-relation, unknown faction IDs, and non-finite (NaN / Inf / non-numeric) input rejection
## - TC-FREL.5: Pairwise war declaration (`declare_war_between_factions`) clears NAP/Alliance, applies -50.0 opinion delta, emits pair signals
## - TC-FREL.6: Pairwise peace (`sign_peace_between_factions`) requires war, clears war, applies +20.0 opinion delta, works for `active` & `in_exile`
## - TC-FREL.7: Pairwise NAP (`sign_nap_between_factions`) requires peace, no existing NAP, and mutual opinion >= 0.0
## - TC-FREL.8: Pairwise Alliance (`sign_alliance_between_factions`) requires peace, no existing Alliance, and mutual opinion >= 60.0 (sets NAP + Alliance)
## - TC-FREL.9: Existence status guards (`in_exile` and `eliminated` blocked from war/NAP/Alliance; `eliminated` blocked from peace)
## - TC-FREL.10: Isolation from player-facing `FactionData` fields, player-facing signals, and `BattleCampaignManager` settlement raids
## - TC-FREL.11: Neutral tribe ascension (`neutral_tribe` -> `emerging_power`) preserves canonical pair keys & existing pairwise relations
## - TC-FREL.12: Idempotent `initialize_pairwise_relations(false)` & daily simulation preservation of pairwise relations
## - TC-FREL.13: Save/Load roundtrip persistence of directional opinions, wars, NAPs, and Alliances across all NPC pairs
## - TC-FREL.14: Legacy save compatibility (omitted `pairwise_relations` initializes clean neutral defaults without disturbing player/executor state)
## - TC-FREL.15: Double-load idempotency & no state leakage from previous in-memory pairwise relations
## - TC-FREL.16: Fail-closed SaveManager validation for malformed `pairwise_relations` (non-Dict, self-pair, unknown ID, non-canonical order, mismatched key, duplicate pair, NaN/out-of-range opinion, non-bool flags, contradictory war+treaty or alliance-without-NAP)

const FactionDataScript = preload("res://scripts/factions/faction_data.gd")
const FactionRelationDataScript = preload("res://scripts/factions/faction_relation_data.gd")
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
	print("  STARTING PACKAGE 1U PAIRWISE FACTION RELATIONS TESTS")
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
			print("  ALL PACKAGE 1U PAIRWISE FACTION RELATIONS TESTS PASSED! (Exit Code 0)")
			print("--------------------------------------------------------\n")
			quit(0)
			return true
		else:
			printerr("  PACKAGE 1U PAIRWISE FACTION RELATIONS TESTS FAILED WITH %d FAILURES! (Exit Code 1)" % failures)
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
	_test_tc_frel_1_default_initialization()
	_test_tc_frel_2_canonical_pair_identity()
	_test_tc_frel_3_directional_opinions_and_clamping()
	_test_tc_frel_4_invalid_pair_and_number_rejection()
	_test_tc_frel_5_declare_war_between_factions()
	_test_tc_frel_6_sign_peace_between_factions()
	_test_tc_frel_7_sign_nap_between_factions()
	_test_tc_frel_8_sign_alliance_between_factions()
	_test_tc_frel_9_existence_status_guards()
	_test_tc_frel_10_isolation_from_player_diplomacy_and_raids()
	_test_tc_frel_11_neutral_tribe_ascension_preserves_relations()
	_test_tc_frel_12_idempotent_init_and_daily_sim_preservation()
	_test_tc_frel_13_save_load_roundtrip()
	_test_tc_frel_14_legacy_save_compatibility()
	_test_tc_frel_15_double_load_idempotency()
	_test_tc_frel_16_fail_closed_validation()

func _test_tc_frel_1_default_initialization() -> void:
	print("\n--- TC-FREL.1: Default initialization & canonical pair keys across all 3 unordered NPC faction pairs ---")
	var fm := FactionManagerScript.new()
	var all_rels: Array[Dictionary] = fm.get_all_faction_relations()
	_assert_eq(all_rels.size(), 3, "TC-FREL.1-COUNT", "3 unordered pairs for 3 NPC factions")

	var expected_keys: Array[String] = [
		"neutral_tribe__rival_merchant",
		"neutral_tribe__rival_military",
		"rival_merchant__rival_military"
	]
	for i in range(expected_keys.size()):
		var rec_dict: Dictionary = all_rels[i]
		_assert_eq(str(rec_dict.get("pair_key", "")), expected_keys[i], "TC-FREL.1-KEY-" + str(i))
		_assert_approx(float(rec_dict.get("opinion_a_to_b", -999.0)), 0.0, "TC-FREL.1-OP-AB-" + str(i))
		_assert_approx(float(rec_dict.get("opinion_b_to_a", -999.0)), 0.0, "TC-FREL.1-OP-BA-" + str(i))
		_assert_false(bool(rec_dict.get("is_at_war", true)), "TC-FREL.1-WAR-" + str(i))
		_assert_false(bool(rec_dict.get("has_nap", true)), "TC-FREL.1-NAP-" + str(i))
		_assert_false(bool(rec_dict.get("has_alliance", true)), "TC-FREL.1-ALLIANCE-" + str(i))

func _test_tc_frel_2_canonical_pair_identity() -> void:
	print("\n--- TC-FREL.2: Canonical pair identity & symmetry ((A, B) and (B, A) resolve to exact same record) ---")
	var fm := FactionManagerScript.new()
	var key_1: String = fm.get_faction_pair_key("rival_military", "rival_merchant")
	var key_2: String = fm.get_faction_pair_key("rival_merchant", "rival_military")
	_assert_eq(key_1, "rival_merchant__rival_military", "TC-FREL.2-KEY-1")
	_assert_eq(key_2, "rival_merchant__rival_military", "TC-FREL.2-KEY-2")

	var rec_1: FactionRelationData = fm.get_faction_relation_record("rival_military", "rival_merchant")
	var rec_2: FactionRelationData = fm.get_faction_relation_record("rival_merchant", "rival_military")
	_assert_true(rec_1 != null and rec_1 == rec_2, "TC-FREL.2-SAME-INSTANCE", "Both argument orders return the exact same FactionRelationData object")
	_assert_eq(rec_1.faction_a, "rival_merchant", "TC-FREL.2-FACTION-A")
	_assert_eq(rec_1.faction_b, "rival_military", "TC-FREL.2-FACTION-B")

func _test_tc_frel_3_directional_opinions_and_clamping() -> void:
	print("\n--- TC-FREL.3: Directional opinion independence, clamping [-100, 100], and disposition calculation ---")
	var fm := FactionManagerScript.new()
	var sig_events: Array = []
	fm.faction_pair_opinion_changed.connect(func(from_id: String, to_id: String, new_op: float, disp: int):
		sig_events.append({"from": from_id, "to": to_id, "op": new_op, "disp": disp})
	)

	var res_ab: Dictionary = fm.set_faction_pair_opinion("rival_merchant", "rival_military", 45.0)
	_assert_true(bool(res_ab.get("success", false)), "TC-FREL.3-SET-AB-OK")
	_assert_approx(fm.get_directed_faction_opinion("rival_merchant", "rival_military"), 45.0, "TC-FREL.3-GET-AB")
	_assert_approx(fm.get_directed_faction_opinion("rival_military", "rival_merchant"), 0.0, "TC-FREL.3-GET-BA-UNCHANGED")
	_assert_eq(sig_events.size(), 1, "TC-FREL.3-SIG-1")
	_assert_eq(int(res_ab.get("disposition", -1)), FactionDataScript.Disposition.FRIENDLY, "TC-FREL.3-DISP-FRIENDLY")

	var res_ba: Dictionary = fm.modify_faction_pair_opinion("rival_military", "rival_merchant", -55.0)
	_assert_true(bool(res_ba.get("success", false)), "TC-FREL.3-MOD-BA-OK")
	_assert_approx(fm.get_directed_faction_opinion("rival_military", "rival_merchant"), -55.0, "TC-FREL.3-GET-BA-HOSTILE")
	_assert_approx(fm.get_directed_faction_opinion("rival_merchant", "rival_military"), 45.0, "TC-FREL.3-GET-AB-STILL-45")
	_assert_eq(int(res_ba.get("disposition", -1)), FactionDataScript.Disposition.HOSTILE, "TC-FREL.3-DISP-HOSTILE")

	var view_ab: Dictionary = fm.get_faction_relation("rival_merchant", "rival_military")
	var view_ba: Dictionary = fm.get_faction_relation("rival_military", "rival_merchant")
	_assert_approx(float(view_ab.get("opinion", 0.0)), 45.0, "TC-FREL.3-VIEW-AB-OP")
	_assert_approx(float(view_ab.get("reverse_opinion", 0.0)), -55.0, "TC-FREL.3-VIEW-AB-REV")
	_assert_approx(float(view_ba.get("opinion", 0.0)), -55.0, "TC-FREL.3-VIEW-BA-OP")
	_assert_approx(float(view_ba.get("reverse_opinion", 0.0)), 45.0, "TC-FREL.3-VIEW-BA-REV")

	# Clamping tests
	fm.set_faction_pair_opinion("neutral_tribe", "rival_merchant", 250.0)
	_assert_approx(fm.get_directed_faction_opinion("neutral_tribe", "rival_merchant"), 100.0, "TC-FREL.3-CLAMP-MAX")
	fm.modify_faction_pair_opinion("neutral_tribe", "rival_merchant", -500.0)
	_assert_approx(fm.get_directed_faction_opinion("neutral_tribe", "rival_merchant"), -100.0, "TC-FREL.3-CLAMP-MIN")

func _test_tc_frel_4_invalid_pair_and_number_rejection() -> void:
	print("\n--- TC-FREL.4: Self-relation, unknown faction IDs, and non-finite input rejection ---")
	var fm := FactionManagerScript.new()
	var before_all: Array[Dictionary] = fm.get_all_faction_relations()

	# Self-relation rejected across all APIs
	_assert_eq(fm.get_faction_pair_key("rival_military", "rival_military"), "", "TC-FREL.4-SELF-KEY")
	_assert_true(fm.get_faction_relation("rival_military", "rival_military").is_empty(), "TC-FREL.4-SELF-VIEW")
	var self_op: Dictionary = fm.set_faction_pair_opinion("rival_military", "rival_military", 50.0)
	_assert_false(bool(self_op.get("success", true)), "TC-FREL.4-SELF-OP")
	_assert_eq(str(self_op.get("reason_code", "")), FactionManagerScript.PAIR_REASON_ERR_SELF_RELATION, "TC-FREL.4-SELF-OP-CODE")

	var self_war: Dictionary = fm.declare_war_between_factions("rival_military", "rival_military")
	_assert_false(bool(self_war.get("success", true)), "TC-FREL.4-SELF-WAR")
	_assert_eq(str(self_war.get("reason_code", "")), FactionManagerScript.PAIR_REASON_ERR_SELF_RELATION, "TC-FREL.4-SELF-WAR-CODE")

	# Unknown faction rejected
	var unk_war: Dictionary = fm.declare_war_between_factions("rival_military", "unknown_kingdom")
	_assert_false(bool(unk_war.get("success", true)), "TC-FREL.4-UNK-WAR")
	_assert_eq(str(unk_war.get("reason_code", "")), FactionManagerScript.PAIR_REASON_ERR_UNKNOWN_FACTION, "TC-FREL.4-UNK-WAR-CODE")

	var empty_id: Dictionary = fm.sign_nap_between_factions("", "rival_merchant")
	_assert_false(bool(empty_id.get("success", true)), "TC-FREL.4-EMPTY-ID")
	_assert_eq(str(empty_id.get("reason_code", "")), FactionManagerScript.PAIR_REASON_ERR_UNKNOWN_FACTION, "TC-FREL.4-EMPTY-ID-CODE")

	# Non-finite numbers rejected
	var nan_res: Dictionary = fm.set_faction_pair_opinion("rival_merchant", "rival_military", NAN)
	_assert_false(bool(nan_res.get("success", true)), "TC-FREL.4-NAN")
	_assert_eq(str(nan_res.get("reason_code", "")), FactionManagerScript.PAIR_REASON_ERR_INVALID_NUMBER, "TC-FREL.4-NAN-CODE")

	var inf_res: Dictionary = fm.modify_faction_pair_opinion("rival_merchant", "rival_military", INF)
	_assert_false(bool(inf_res.get("success", true)), "TC-FREL.4-INF")
	_assert_eq(str(inf_res.get("reason_code", "")), FactionManagerScript.PAIR_REASON_ERR_INVALID_NUMBER, "TC-FREL.4-INF-CODE")

	var str_res: Dictionary = fm.set_faction_pair_opinion("rival_merchant", "rival_military", "invalid")
	_assert_false(bool(str_res.get("success", true)), "TC-FREL.4-STR")
	_assert_eq(str(str_res.get("reason_code", "")), FactionManagerScript.PAIR_REASON_ERR_INVALID_NUMBER, "TC-FREL.4-STR-CODE")

	_assert_eq(fm.get_all_faction_relations(), before_all, "TC-FREL.4-NO-MUTATION")

func _test_tc_frel_5_declare_war_between_factions() -> void:
	print("\n--- TC-FREL.5: Pairwise war declaration clears NAP/Alliance, applies -50 opinion delta, emits pair signals ---")
	var fm := FactionManagerScript.new()
	fm.set_faction_pair_opinion("rival_merchant", "rival_military", 70.0)
	fm.set_faction_pair_opinion("rival_military", "rival_merchant", 65.0)
	var all_res: Dictionary = fm.sign_alliance_between_factions("rival_merchant", "rival_military")
	_assert_true(bool(all_res.get("success", false)), "TC-FREL.5-SETUP-ALLIANCE")
	_assert_true(fm.do_factions_have_alliance("rival_merchant", "rival_military"), "TC-FREL.5-HAS-ALLIANCE")
	_assert_true(fm.do_factions_have_nap("rival_merchant", "rival_military"), "TC-FREL.5-HAS-NAP")

	var war_signals: Array = []
	fm.faction_pair_war_declared.connect(func(init_id: String, tgt_id: String, p_key: String):
		war_signals.append({"init": init_id, "tgt": tgt_id, "key": p_key})
	)

	# Opinions after alliance were 70+25=95 and 65+25=90. Declaring war applies -50 -> 45 and 40.
	var war_res: Dictionary = fm.declare_war_between_factions("rival_military", "rival_merchant")
	_assert_true(bool(war_res.get("success", false)), "TC-FREL.5-WAR-OK")
	_assert_true(fm.are_factions_at_war("rival_merchant", "rival_military"), "TC-FREL.5-AT-WAR-1")
	_assert_true(fm.are_factions_at_war("rival_military", "rival_merchant"), "TC-FREL.5-AT-WAR-2")
	_assert_false(fm.do_factions_have_nap("rival_merchant", "rival_military"), "TC-FREL.5-NAP-CLEARED")
	_assert_false(fm.do_factions_have_alliance("rival_merchant", "rival_military"), "TC-FREL.5-ALLIANCE-CLEARED")
	_assert_approx(fm.get_directed_faction_opinion("rival_merchant", "rival_military"), 45.0, "TC-FREL.5-OP-AB-AFTER-WAR")
	_assert_approx(fm.get_directed_faction_opinion("rival_military", "rival_merchant"), 40.0, "TC-FREL.5-OP-BA-AFTER-WAR")
	_assert_eq(war_signals.size(), 1, "TC-FREL.5-WAR-SIGNAL-COUNT")
	_assert_eq(str(war_signals[0]["init"]), "rival_military", "TC-FREL.5-WAR-SIGNAL-INIT")
	_assert_eq(str(war_signals[0]["tgt"]), "rival_merchant", "TC-FREL.5-WAR-SIGNAL-TGT")

	# Duplicate war declaration rejected
	var dup_war: Dictionary = fm.declare_war_between_factions("rival_merchant", "rival_military")
	_assert_false(bool(dup_war.get("success", true)), "TC-FREL.5-DUP-WAR-REJECTED")
	_assert_eq(str(dup_war.get("reason_code", "")), FactionManagerScript.PAIR_REASON_ERR_ALREADY_AT_WAR, "TC-FREL.5-DUP-WAR-CODE")

func _test_tc_frel_6_sign_peace_between_factions() -> void:
	print("\n--- TC-FREL.6: Pairwise peace requires war, clears war, applies +20 opinion delta, works for active & in_exile ---")
	var fm := FactionManagerScript.new()

	# Peace when not at war fails
	var early_peace: Dictionary = fm.sign_peace_between_factions("neutral_tribe", "rival_military")
	_assert_false(bool(early_peace.get("success", true)), "TC-FREL.6-PEACE-WHEN-PEACEFUL-REJECTED")
	_assert_eq(str(early_peace.get("reason_code", "")), FactionManagerScript.PAIR_REASON_ERR_NOT_AT_WAR, "TC-FREL.6-NOT-AT-WAR-CODE")

	fm.declare_war_between_factions("rival_military", "neutral_tribe")
	# Both opinions are now -50.0. Put neutral_tribe in exile and verify peace is still permitted.
	var tribe: FactionData = fm.get_faction("neutral_tribe")
	tribe.existence_status = FactionDataScript.STATUS_IN_EXILE

	var peace_signals: Array = []
	fm.faction_pair_peace_signed.connect(func(fa: String, fb: String, pk: String):
		peace_signals.append({"fa": fa, "fb": fb, "key": pk})
	)

	var peace_res: Dictionary = fm.propose_treaty_between_factions("rival_military", "neutral_tribe", "peace")
	_assert_true(bool(peace_res.get("success", false)), "TC-FREL.6-PEACE-OK-IN-EXILE")
	_assert_false(fm.are_factions_at_war("neutral_tribe", "rival_military"), "TC-FREL.6-WAR-CLEARED")
	_assert_approx(fm.get_directed_faction_opinion("neutral_tribe", "rival_military"), -30.0, "TC-FREL.6-OP-AB-RECOVERED")
	_assert_approx(fm.get_directed_faction_opinion("rival_military", "neutral_tribe"), -30.0, "TC-FREL.6-OP-BA-RECOVERED")
	_assert_eq(peace_signals.size(), 1, "TC-FREL.6-PEACE-SIG-COUNT")

func _test_tc_frel_7_sign_nap_between_factions() -> void:
	print("\n--- TC-FREL.7: Pairwise NAP requires peace, no existing NAP, and mutual opinion >= 0.0 ---")
	var fm := FactionManagerScript.new()

	# Asymmetric negative opinion blocks NAP
	fm.set_faction_pair_opinion("neutral_tribe", "rival_merchant", 10.0)
	fm.set_faction_pair_opinion("rival_merchant", "neutral_tribe", -0.01)
	var low_op_nap: Dictionary = fm.sign_nap_between_factions("neutral_tribe", "rival_merchant")
	_assert_false(bool(low_op_nap.get("success", true)), "TC-FREL.7-LOW-OP-REJECTED")
	_assert_eq(str(low_op_nap.get("reason_code", "")), FactionManagerScript.PAIR_REASON_ERR_INSUFFICIENT_OPINION, "TC-FREL.7-LOW-OP-CODE")

	# Exact 0.0 boundary succeeds
	fm.set_faction_pair_opinion("rival_merchant", "neutral_tribe", 0.0)
	var nap_res: Dictionary = fm.sign_nap_between_factions("rival_merchant", "neutral_tribe")
	_assert_true(bool(nap_res.get("success", false)), "TC-FREL.7-NAP-OK")
	_assert_true(fm.do_factions_have_nap("neutral_tribe", "rival_merchant"), "TC-FREL.7-HAS-NAP")
	_assert_approx(fm.get_directed_faction_opinion("neutral_tribe", "rival_merchant"), 25.0, "TC-FREL.7-OP-AB-PLUS-15")
	_assert_approx(fm.get_directed_faction_opinion("rival_merchant", "neutral_tribe"), 15.0, "TC-FREL.7-OP-BA-PLUS-15")

	# Duplicate NAP rejected
	var dup_nap: Dictionary = fm.sign_nap_between_factions("neutral_tribe", "rival_merchant")
	_assert_false(bool(dup_nap.get("success", true)), "TC-FREL.7-DUP-NAP-REJECTED")
	_assert_eq(str(dup_nap.get("reason_code", "")), FactionManagerScript.PAIR_REASON_ERR_ALREADY_HAS_NAP, "TC-FREL.7-DUP-NAP-CODE")

	# NAP while at war rejected
	fm.declare_war_between_factions("rival_merchant", "rival_military")
	fm.set_faction_pair_opinion("rival_merchant", "rival_military", 20.0)
	fm.set_faction_pair_opinion("rival_military", "rival_merchant", 20.0)
	var war_nap: Dictionary = fm.sign_nap_between_factions("rival_merchant", "rival_military")
	_assert_false(bool(war_nap.get("success", true)), "TC-FREL.7-WAR-NAP-REJECTED")
	_assert_eq(str(war_nap.get("reason_code", "")), FactionManagerScript.PAIR_REASON_ERR_AT_WAR, "TC-FREL.7-WAR-NAP-CODE")

func _test_tc_frel_8_sign_alliance_between_factions() -> void:
	print("\n--- TC-FREL.8: Pairwise Alliance requires peace, no existing Alliance, and mutual opinion >= 60.0 ---")
	var fm := FactionManagerScript.new()
	fm.set_faction_pair_opinion("neutral_tribe", "rival_merchant", 60.0)
	fm.set_faction_pair_opinion("rival_merchant", "neutral_tribe", 59.99)

	var low_all: Dictionary = fm.sign_alliance_between_factions("neutral_tribe", "rival_merchant")
	_assert_false(bool(low_all.get("success", true)), "TC-FREL.8-59-99-REJECTED")
	_assert_eq(str(low_all.get("reason_code", "")), FactionManagerScript.PAIR_REASON_ERR_INSUFFICIENT_OPINION, "TC-FREL.8-LOW-OP-CODE")

	fm.set_faction_pair_opinion("rival_merchant", "neutral_tribe", 60.0)
	var all_res: Dictionary = fm.propose_treaty_between_factions("neutral_tribe", "rival_merchant", "alliance")
	_assert_true(bool(all_res.get("success", false)), "TC-FREL.8-ALLIANCE-OK")
	_assert_true(fm.do_factions_have_alliance("neutral_tribe", "rival_merchant"), "TC-FREL.8-HAS-ALLIANCE")
	_assert_true(fm.do_factions_have_nap("neutral_tribe", "rival_merchant"), "TC-FREL.8-ALLIANCE-IMPLIES-NAP")
	_assert_approx(fm.get_directed_faction_opinion("neutral_tribe", "rival_merchant"), 85.0, "TC-FREL.8-OP-AB-85")
	_assert_approx(fm.get_directed_faction_opinion("rival_merchant", "neutral_tribe"), 85.0, "TC-FREL.8-OP-BA-85")

	# Duplicate Alliance rejected
	var dup_all: Dictionary = fm.sign_alliance_between_factions("rival_merchant", "neutral_tribe")
	_assert_false(bool(dup_all.get("success", true)), "TC-FREL.8-DUP-ALLIANCE-REJECTED")
	_assert_eq(str(dup_all.get("reason_code", "")), FactionManagerScript.PAIR_REASON_ERR_ALREADY_ALLIED, "TC-FREL.8-DUP-ALLIANCE-CODE")

	# Unknown treaty type rejected
	var unk_treaty: Dictionary = fm.propose_treaty_between_factions("neutral_tribe", "rival_merchant", "vassalage")
	_assert_false(bool(unk_treaty.get("success", true)), "TC-FREL.8-UNK-TREATY-REJECTED")
	_assert_eq(str(unk_treaty.get("reason_code", "")), FactionManagerScript.PAIR_REASON_ERR_UNKNOWN_TREATY, "TC-FREL.8-UNK-TREATY-CODE")

func _test_tc_frel_9_existence_status_guards() -> void:
	print("\n--- TC-FREL.9: Existence status guards (in_exile and eliminated blocked from war/NAP/Alliance; eliminated blocked from peace) ---")
	var fm := FactionManagerScript.new()
	fm.set_faction_pair_opinion("rival_merchant", "rival_military", 80.0)
	fm.set_faction_pair_opinion("rival_military", "rival_merchant", 80.0)

	var merch: FactionData = fm.get_faction("rival_merchant")
	merch.existence_status = FactionDataScript.STATUS_IN_EXILE

	_assert_eq(str(fm.declare_war_between_factions("rival_merchant", "rival_military").get("reason_code", "")), FactionManagerScript.PAIR_REASON_ERR_INVALID_STATUS, "TC-FREL.9-EXILE-WAR")
	_assert_eq(str(fm.sign_nap_between_factions("rival_merchant", "rival_military").get("reason_code", "")), FactionManagerScript.PAIR_REASON_ERR_INVALID_STATUS, "TC-FREL.9-EXILE-NAP")
	_assert_eq(str(fm.sign_alliance_between_factions("rival_merchant", "rival_military").get("reason_code", "")), FactionManagerScript.PAIR_REASON_ERR_INVALID_STATUS, "TC-FREL.9-EXILE-ALLIANCE")

	# Put them at war while active, then mark one eliminated -> peace blocked
	merch.existence_status = FactionDataScript.STATUS_ACTIVE
	fm.declare_war_between_factions("rival_merchant", "rival_military")
	merch.existence_status = FactionDataScript.STATUS_ELIMINATED
	var elim_peace: Dictionary = fm.sign_peace_between_factions("rival_merchant", "rival_military")
	_assert_false(bool(elim_peace.get("success", true)), "TC-FREL.9-ELIM-PEACE-BLOCKED")
	_assert_eq(str(elim_peace.get("reason_code", "")), FactionManagerScript.PAIR_REASON_ERR_INVALID_STATUS, "TC-FREL.9-ELIM-PEACE-CODE")
	_assert_true(fm.are_factions_at_war("rival_merchant", "rival_military"), "TC-FREL.9-STILL-AT-WAR")

func _test_tc_frel_10_isolation_from_player_diplomacy_and_raids() -> void:
	print("\n--- TC-FREL.10: Isolation from player-facing FactionData fields, signals, and BattleCampaignManager raids ---")
	var fm: FactionManager = world_instance.get("faction_mgr")
	var bcm = world_instance.get("battle_campaign_mgr")
	fm._initialize_factions()
	bcm.deserialize({})

	var player_war_sigs: Array = []
	var player_peace_sigs: Array = []
	var player_treaty_sigs: Array = []
	var cb_war := func(fid: String): player_war_sigs.append(fid)
	var cb_peace := func(fid: String): player_peace_sigs.append(fid)
	var cb_treaty := func(fid: String, ttype: String): player_treaty_sigs.append(fid + ":" + ttype)
	fm.war_declared.connect(cb_war)
	fm.peace_signed.connect(cb_peace)
	fm.treaty_signed.connect(cb_treaty)

	var mil: FactionData = fm.get_faction("rival_military")
	var merch: FactionData = fm.get_faction("rival_merchant")
	var mil_op_before: float = mil.opinion
	var merch_op_before: float = merch.opinion

	# Execute NPC-vs-NPC war, peace, NAP, and alliance
	fm.declare_war_between_factions("rival_military", "rival_merchant")
	_assert_false(mil.is_at_war, "TC-FREL.10-MIL-PLAYER-WAR-UNCHANGED")
	_assert_false(merch.is_at_war, "TC-FREL.10-MERCH-PLAYER-WAR-UNCHANGED")
	_assert_approx(mil.opinion, mil_op_before, "TC-FREL.10-MIL-PLAYER-OP-UNCHANGED")
	_assert_approx(merch.opinion, merch_op_before, "TC-FREL.10-MERCH-PLAYER-OP-UNCHANGED")
	_assert_eq(player_war_sigs.size(), 0, "TC-FREL.10-NO-PLAYER-WAR-SIG")
	_assert_false(bcm.has_pending_raid("rival_military"), "TC-FREL.10-NO-RAID-MIL")
	_assert_false(bcm.has_pending_raid("rival_merchant"), "TC-FREL.10-NO-RAID-MERCH")

	fm.sign_peace_between_factions("rival_military", "rival_merchant")
	fm.set_faction_pair_opinion("rival_military", "rival_merchant", 70.0)
	fm.set_faction_pair_opinion("rival_merchant", "rival_military", 70.0)
	fm.sign_alliance_between_factions("rival_military", "rival_merchant")

	_assert_false(mil.has_nap or mil.has_alliance, "TC-FREL.10-MIL-PLAYER-TREATY-UNCHANGED")
	_assert_false(merch.has_nap or merch.has_alliance, "TC-FREL.10-MERCH-PLAYER-TREATY-UNCHANGED")
	_assert_eq(player_peace_sigs.size(), 0, "TC-FREL.10-NO-PLAYER-PEACE-SIG")
	_assert_eq(player_treaty_sigs.size(), 0, "TC-FREL.10-NO-PLAYER-TREATY-SIG")

	fm.war_declared.disconnect(cb_war)
	fm.peace_signed.disconnect(cb_peace)
	fm.treaty_signed.disconnect(cb_treaty)

func _test_tc_frel_11_neutral_tribe_ascension_preserves_relations() -> void:
	print("\n--- TC-FREL.11: Neutral tribe ascension (neutral_tribe -> emerging_power) preserves canonical pair keys & relations ---")
	var fm := FactionManagerScript.new()
	fm.set_faction_pair_opinion("neutral_tribe", "rival_merchant", 42.0)
	fm.set_faction_pair_opinion("rival_merchant", "neutral_tribe", 18.0)
	fm.sign_nap_between_factions("neutral_tribe", "rival_merchant")
	fm.declare_war_between_factions("rival_military", "neutral_tribe")

	var tribe: FactionData = fm.get_faction("neutral_tribe")
	tribe.population = 44 # Will grow to 45 on day 12 and ascend
	tribe.stability = 80.0
	tribe.resources[EconomyConfigScript.RES_WOOD] = 120
	tribe.resources[EconomyConfigScript.RES_HERBS] = 60

	fm.update_daily_simulation(12)
	_assert_eq(tribe.type, "emerging_power", "TC-FREL.11-ASCENDED")
	_assert_eq(tribe.id, "neutral_tribe", "TC-FREL.11-ID-STABLE")
	_assert_true(fm.do_factions_have_nap("neutral_tribe", "rival_merchant"), "TC-FREL.11-NAP-PRESERVED")
	_assert_approx(fm.get_directed_faction_opinion("neutral_tribe", "rival_merchant"), 57.0, "TC-FREL.11-OP-MERCH-PRESERVED")
	_assert_true(fm.are_factions_at_war("neutral_tribe", "rival_military"), "TC-FREL.11-WAR-MIL-PRESERVED")

func _test_tc_frel_12_idempotent_init_and_daily_sim_preservation() -> void:
	print("\n--- TC-FREL.12: Idempotent initialize_pairwise_relations(false) & daily simulation preservation ---")
	var fm := FactionManagerScript.new()
	fm.set_faction_pair_opinion("rival_merchant", "rival_military", -33.5)
	fm.declare_war_between_factions("rival_merchant", "rival_military")

	var snap_before: Dictionary = fm.serialize_pairwise_relations()
	fm.initialize_pairwise_relations(false)
	var snap_after_init: Dictionary = fm.serialize_pairwise_relations()
	_assert_eq(snap_after_init, snap_before, "TC-FREL.12-IDEMPOTENT-INIT")

	fm.update_daily_simulation(5)
	var snap_after_sim: Dictionary = fm.serialize_pairwise_relations()
	_assert_eq(snap_after_sim, snap_before, "TC-FREL.12-PRESERVED-ACROSS-DAILY-SIM")

func _test_tc_frel_13_save_load_roundtrip() -> void:
	print("\n--- TC-FREL.13: Save/Load roundtrip persistence of directional opinions, wars, NAPs, and Alliances ---")
	var fm: FactionManager = world_instance.get("faction_mgr")
	fm._initialize_factions()

	# Pair 1: neutral_tribe & rival_merchant -> Allied
	fm.set_faction_pair_opinion("neutral_tribe", "rival_merchant", 65.0)
	fm.set_faction_pair_opinion("rival_merchant", "neutral_tribe", 70.0)
	fm.sign_alliance_between_factions("neutral_tribe", "rival_merchant")

	# Pair 2: neutral_tribe & rival_military -> NAP with asymmetric opinions
	fm.set_faction_pair_opinion("neutral_tribe", "rival_military", 12.5)
	fm.set_faction_pair_opinion("rival_military", "neutral_tribe", 4.0)
	fm.sign_nap_between_factions("neutral_tribe", "rival_military")

	# Pair 3: rival_merchant & rival_military -> At War
	fm.set_faction_pair_opinion("rival_merchant", "rival_military", -10.0)
	fm.set_faction_pair_opinion("rival_military", "rival_merchant", -25.0)
	fm.declare_war_between_factions("rival_military", "rival_merchant")

	var expected_serialized: Dictionary = fm.serialize_pairwise_relations()
	var save_path: String = "user://saves/test_package_1u_roundtrip.json"
	var save_res: Dictionary = SaveManagerScript.save_to_file(world_instance, save_path)
	_assert_true(bool(save_res.get("success", false)), "TC-FREL.13-SAVE-OK")

	# Mutate in-memory state completely before loading
	fm._initialize_factions()
	_assert_false(fm.are_factions_at_war("rival_merchant", "rival_military"), "TC-FREL.13-RESET-BEFORE-LOAD")

	var load_res: Dictionary = SaveManagerScript.load_from_file(save_path)
	_assert_true(bool(load_res.get("success", false)), "TC-FREL.13-LOAD-OK")
	var apply_res: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, load_res["data"])
	_assert_true(bool(apply_res.get("success", false)), "TC-FREL.13-APPLY-OK")

	_assert_eq(fm.serialize_pairwise_relations(), expected_serialized, "TC-FREL.13-EXACT-ROUNDTRIP-MATCH")
	_assert_true(fm.do_factions_have_alliance("neutral_tribe", "rival_merchant"), "TC-FREL.13-RESTORED-ALLIANCE")
	_assert_true(fm.do_factions_have_nap("neutral_tribe", "rival_military"), "TC-FREL.13-RESTORED-NAP")
	_assert_true(fm.are_factions_at_war("rival_merchant", "rival_military"), "TC-FREL.13-RESTORED-WAR")

func _test_tc_frel_14_legacy_save_compatibility() -> void:
	print("\n--- TC-FREL.14: Legacy save compatibility (omitted pairwise_relations initializes clean neutral defaults) ---")
	var fm: FactionManager = world_instance.get("faction_mgr")
	fm._initialize_factions()
	fm.declare_war_between_factions("rival_merchant", "rival_military")
	fm.get_faction("rival_military").opinion = -42.0
	fm.set_faction_last_diplomacy_day("rival_military", 1)

	var state_dict: Dictionary = SaveManagerScript.serialize_world_state(world_instance)
	state_dict["factions"].erase("pairwise_relations")

	var val_res: Dictionary = SaveManagerScript.validate_save_data(state_dict)
	_assert_true(bool(val_res.get("valid", false)), "TC-FREL.14-LEGACY-VALID")

	var apply_res: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, state_dict)
	_assert_true(bool(apply_res.get("success", false)), "TC-FREL.14-LEGACY-APPLY-OK")
	_assert_false(fm.are_factions_at_war("rival_merchant", "rival_military"), "TC-FREL.14-LEGACY-PAIR-RESET-TO-PEACE")
	_assert_approx(fm.get_directed_faction_opinion("rival_merchant", "rival_military"), 0.0, "TC-FREL.14-LEGACY-PAIR-OP-0")
	_assert_approx(fm.get_faction("rival_military").opinion, -42.0, "TC-FREL.14-PLAYER-OP-PRESERVED")
	_assert_eq(fm.get_faction_last_diplomacy_day("rival_military"), 1, "TC-FREL.14-DIPLO-DAY-PRESERVED")

func _test_tc_frel_15_double_load_idempotency() -> void:
	print("\n--- TC-FREL.15: Double-load idempotency & no state leakage from previous in-memory pairwise relations ---")
	var fm: FactionManager = world_instance.get("faction_mgr")
	fm._initialize_factions()
	fm.set_faction_pair_opinion("rival_merchant", "rival_military", 33.0)
	fm.sign_nap_between_factions("rival_merchant", "rival_military")

	var saved_state: Dictionary = SaveManagerScript.serialize_world_state(world_instance)

	# Dirty state before load 1
	fm.declare_war_between_factions("neutral_tribe", "rival_military")
	SaveManagerScript.apply_loaded_state_to_world(world_instance, saved_state)
	var snap_1: Dictionary = fm.serialize_pairwise_relations()

	# Load 2 immediately
	SaveManagerScript.apply_loaded_state_to_world(world_instance, saved_state)
	var snap_2: Dictionary = fm.serialize_pairwise_relations()

	_assert_eq(snap_1, snap_2, "TC-FREL.15-DOUBLE-LOAD-IDENTICAL")
	_assert_false(fm.are_factions_at_war("neutral_tribe", "rival_military"), "TC-FREL.15-NO-DIRTY-LEAKAGE")

func _test_tc_frel_16_fail_closed_validation() -> void:
	print("\n--- TC-FREL.16: Fail-closed SaveManager validation for malformed pairwise_relations ---")
	var fm: FactionManager = world_instance.get("faction_mgr")
	fm._initialize_factions()
	fm.set_faction_pair_opinion("neutral_tribe", "rival_merchant", 22.0)
	var clean_before: Dictionary = fm.serialize_pairwise_relations()
	var base_save: Dictionary = SaveManagerScript.serialize_world_state(world_instance)

	# 1. Non-dictionary pairwise_relations
	var bad_1: Dictionary = base_save.duplicate(true)
	bad_1["factions"]["pairwise_relations"] = "not_a_dict"
	_assert_false(bool(SaveManagerScript.validate_save_data(bad_1).get("valid", true)), "TC-FREL.16-NON-DICT")

	# 2. Self-relation
	var bad_2: Dictionary = base_save.duplicate(true)
	bad_2["factions"]["pairwise_relations"]["rival_military__rival_military"] = {
		"pair_key": "rival_military__rival_military",
		"faction_a": "rival_military",
		"faction_b": "rival_military",
		"opinion_a_to_b": 0.0,
		"opinion_b_to_a": 0.0,
		"is_at_war": false,
		"has_nap": false,
		"has_alliance": false
	}
	_assert_false(bool(SaveManagerScript.validate_save_data(bad_2).get("valid", true)), "TC-FREL.16-SELF-PAIR")

	# 3. Unknown faction ID
	var bad_3: Dictionary = base_save.duplicate(true)
	bad_3["factions"]["pairwise_relations"]["neutral_tribe__unknown_empire"] = {
		"pair_key": "neutral_tribe__unknown_empire",
		"faction_a": "neutral_tribe",
		"faction_b": "unknown_empire",
		"opinion_a_to_b": 0.0,
		"opinion_b_to_a": 0.0,
		"is_at_war": false,
		"has_nap": false,
		"has_alliance": false
	}
	_assert_false(bool(SaveManagerScript.validate_save_data(bad_3).get("valid", true)), "TC-FREL.16-UNKNOWN-ID")

	# 4. Non-canonical ordering (faction_a > faction_b)
	var bad_4: Dictionary = base_save.duplicate(true)
	bad_4["factions"]["pairwise_relations"]["rival_military__rival_merchant"] = {
		"pair_key": "rival_military__rival_merchant",
		"faction_a": "rival_military",
		"faction_b": "rival_merchant",
		"opinion_a_to_b": 0.0,
		"opinion_b_to_a": 0.0,
		"is_at_war": false,
		"has_nap": false,
		"has_alliance": false
	}
	_assert_false(bool(SaveManagerScript.validate_save_data(bad_4).get("valid", true)), "TC-FREL.16-NON-CANONICAL-ORDER")

	# 5. Mismatched dictionary key vs faction_a/faction_b
	var bad_5: Dictionary = base_save.duplicate(true)
	bad_5["factions"]["pairwise_relations"]["wrong_key"] = {
		"pair_key": "neutral_tribe__rival_merchant",
		"faction_a": "neutral_tribe",
		"faction_b": "rival_merchant",
		"opinion_a_to_b": 0.0,
		"opinion_b_to_a": 0.0,
		"is_at_war": false,
		"has_nap": false,
		"has_alliance": false
	}
	_assert_false(bool(SaveManagerScript.validate_save_data(bad_5).get("valid", true)), "TC-FREL.16-MISMATCHED-KEY")

	# 6. Out-of-range opinion (> 100.0)
	var bad_6: Dictionary = base_save.duplicate(true)
	bad_6["factions"]["pairwise_relations"]["neutral_tribe__rival_merchant"]["opinion_a_to_b"] = 105.0
	_assert_false(bool(SaveManagerScript.validate_save_data(bad_6).get("valid", true)), "TC-FREL.16-OUT-OF-RANGE-OPINION")

	# 7. Non-finite opinion (NaN)
	var bad_7: Dictionary = base_save.duplicate(true)
	bad_7["factions"]["pairwise_relations"]["neutral_tribe__rival_merchant"]["opinion_b_to_a"] = NAN
	_assert_false(bool(SaveManagerScript.validate_save_data(bad_7).get("valid", true)), "TC-FREL.16-NAN-OPINION")

	# 8. Non-boolean flag
	var bad_8: Dictionary = base_save.duplicate(true)
	bad_8["factions"]["pairwise_relations"]["neutral_tribe__rival_merchant"]["is_at_war"] = "yes"
	_assert_false(bool(SaveManagerScript.validate_save_data(bad_8).get("valid", true)), "TC-FREL.16-NON-BOOL-FLAG")

	# 9. Contradictory war + NAP
	var bad_9: Dictionary = base_save.duplicate(true)
	bad_9["factions"]["pairwise_relations"]["neutral_tribe__rival_merchant"]["is_at_war"] = true
	bad_9["factions"]["pairwise_relations"]["neutral_tribe__rival_merchant"]["has_nap"] = true
	_assert_false(bool(SaveManagerScript.validate_save_data(bad_9).get("valid", true)), "TC-FREL.16-CONTRADICTORY-WAR-AND-NAP")

	# 10. Contradictory Alliance without NAP
	var bad_10: Dictionary = base_save.duplicate(true)
	bad_10["factions"]["pairwise_relations"]["neutral_tribe__rival_merchant"]["has_alliance"] = true
	bad_10["factions"]["pairwise_relations"]["neutral_tribe__rival_merchant"]["has_nap"] = false
	_assert_false(bool(SaveManagerScript.validate_save_data(bad_10).get("valid", true)), "TC-FREL.16-ALLIANCE-WITHOUT-NAP")

	# Verify apply_loaded_state_to_world rejects invalid payload before mutating live world state
	var apply_bad: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, bad_9)
	_assert_false(bool(apply_bad.get("success", true)), "TC-FREL.16-APPLY-REJECTED")
	_assert_eq(fm.serialize_pairwise_relations(), clean_before, "TC-FREL.16-WORLD-STATE-UNTOUCHED")
