class_name TestOutpostTerritorialControl
extends SceneTree
## Package 2G Test Suite: Outpost Capture & Territorial Control
## Validates authoritative outpost ownership model, player siege conquest,
## NPC-NPC autonomous territorial conquest, 35% health recovery, idempotency,
## conflict safety, and save/load backward compatibility.

const SiegeObjectiveActorScript = preload("res://scripts/combat/siege_objective_actor.gd")
const FieldSiegeManagerScript = preload("res://scripts/combat/field_siege_manager.gd")
const BattleCampaignManagerScript = preload("res://scripts/combat/battle_campaign_manager.gd")
const FactionManagerScript = preload("res://scripts/factions/faction_manager.gd")
const FactionDataScript = preload("res://scripts/factions/faction_data.gd")
const FactionRelationDataScript = preload("res://scripts/factions/faction_relation_data.gd")
const PlayerArmyManagerScript = preload("res://scripts/military/player_army_manager.gd")
const TacticalMilitaryManagerScript = preload("res://scripts/military/tactical_military_manager.gd")
const TacticalUnitScript = preload("res://scripts/military/tactical_unit.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")

var _tests_passed: int = 0
var _tests_failed: int = 0

func _init() -> void:
	call_deferred("_run_all_tests")

func _assert(condition: bool, message: String) -> void:
	if condition:
		_tests_passed += 1
		print("  [PASS] %s" % message)
	else:
		_tests_failed += 1
		printerr("  [FAIL] %s" % message)

func _run_all_tests() -> void:
	print("========================================================")
	print("  STARTING PACKAGE 2G TERRITORIAL CONTROL TEST SUITE")
	print("========================================================")

	_test_group_1_initial_ownership_and_migration()
	_test_group_2_player_siege_victory_captures_outpost()
	_test_group_3_player_siege_defeat_and_withdrawal_safety()
	_test_group_4_npc_attacker_victory_captures_outpost()
	_test_group_5_defender_victory_and_draw_safety()
	_test_group_6_duplicate_transaction_and_idempotency()
	_test_group_7_invalid_objective_and_conflict_safety()
	_test_group_8_save_load_persistence_and_recapture()

	print("========================================================")
	if _tests_failed == 0:
		print("  [SUCCESS] All Package 2G Tests PASSED! (%d assertions)" % _tests_passed)
		quit(0)
	else:
		printerr("  [FAILURE] %d assertions FAILED out of %d!" % [_tests_failed, _tests_passed + _tests_failed])
		quit(1)

# -----------------------------------------------------------------------------
# Group 1: Initial Ownership & Migration from Legacy Data
# -----------------------------------------------------------------------------

func _test_group_1_initial_ownership_and_migration() -> void:
	print("\n--- Group 1: Initial Ownership & Migration from Legacy Data ---")
	var obj := SiegeObjectiveActorScript.new()
	obj.objective_id = "outpost_alpha"
	obj.owning_faction_id = "rival_military"
	obj.current_cell = Vector2i(10, 10)
	obj.max_health = 300.0
	obj.health = 300.0
	obj._ready()

	_assert(obj.owning_faction_id == "rival_military", "G1.1: Initial owner matches assignment")
	_assert(obj.original_owner_id == "rival_military", "G1.2: Original owner matches initial owner")
	_assert(obj.previous_owner_id == "", "G1.3: Previous owner is initially empty")
	_assert(obj.capture_revision == 0, "G1.4: Capture revision starts at 0")
	_assert(obj.last_capture_tx_id == "", "G1.5: Last transaction ID starts empty")
	_assert(obj.is_captured == false, "G1.6: is_captured starts false")
	_assert(obj.is_alive == true, "G1.7: is_alive starts true")

	# Legacy Save Migration: lacks Package 2G fields
	var legacy_dict := {
		"objective_id": "outpost_legacy_1",
		"objective_name": "Tiền Đồn Cũ",
		"owning_faction_id": "rival_merchant",
		"current_cell": [20, 20],
		"health": 250.0,
		"max_health": 250.0,
		"is_alive": true,
		"is_captured": false,
		"is_under_active_siege": false,
		"garrison_count": 3,
		"defending_unit_ids": []
	}

	var migrated_obj := SiegeObjectiveActorScript.new()
	var ok: bool = migrated_obj.deserialize(legacy_dict)
	_assert(ok == true, "G1.8: Legacy dictionary deserialized successfully")
	_assert(migrated_obj.owning_faction_id == "rival_merchant", "G1.9: Migrated owning_faction_id matches legacy value")
	_assert(migrated_obj.original_owner_id == "rival_merchant", "G1.10: Migrated original_owner_id defaults to owning_faction_id")
	_assert(migrated_obj.previous_owner_id == "", "G1.11: Migrated previous_owner_id defaults to empty string")
	_assert(migrated_obj.capture_revision == 0, "G1.12: Migrated capture_revision defaults to 0")
	_assert(migrated_obj.last_capture_tx_id == "", "G1.13: Migrated last_capture_tx_id defaults to empty string")

	obj.free()
	migrated_obj.free()

# -----------------------------------------------------------------------------
# Group 2: Player Siege Victory Captures Outpost
# -----------------------------------------------------------------------------

func _test_group_2_player_siege_victory_captures_outpost() -> void:
	print("\n--- Group 2: Player Siege Victory Captures Outpost ---")
	var fm = MockFactionManager.new()
	var fac = MockFactionData.new()
	fac.id = "rival_military"
	fac.is_at_war = true
	fac.military_power = 80.0
	fm.add_faction(fac)

	var army_mgr = PlayerArmyManagerScript.new()
	var tac_mgr = TacticalMilitaryManagerScript.new(null, army_mgr)
	army_mgr.set_tactical_military_manager(tac_mgr)
	army_mgr.soldier_count = 3
	tac_mgr.sync_with_player_army()
	for u in tac_mgr.get_all_units():
		u.current_cell = Vector2i(10, 11)
	army_mgr.current_cell = Vector2i(10, 11)
	army_mgr.destination_cell = Vector2i(10, 11)
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD

	var sm = FieldSiegeManagerScript.new(null, fm, army_mgr, null)
	var rm = MockResourceManager.new()
	sm.set_resource_manager(rm)

	var obj = sm.register_objective("obj_vic_1", Vector2i(10, 10), "rival_military", 200.0, 3)

	var signal_captured := {"emitted": false, "new_owner": "", "prev_owner": "", "tx_id": ""}
	sm.outpost_ownership_changed.connect(func(oid, prev_o, new_o, tx):
		signal_captured["emitted"] = true
		signal_captured["prev_owner"] = prev_o
		signal_captured["new_owner"] = new_o
		signal_captured["tx_id"] = tx
	)

	var launch_res = sm.launch_field_siege("rival_military", "obj_vic_1")
	_assert(launch_res.get("success", false) == true, "G2.1: Field siege launched successfully")

	# Destroy the outpost with lethal damage
	obj.take_damage(200.0, "player_catapult")
	var s_id: String = launch_res.get("siege_id", "")
	var eval = sm.evaluate_siege_status(s_id)

	_assert(eval.get("outcome") == "VICTORY", "G2.2: Siege status evaluated to VICTORY")
	_assert(obj.owning_faction_id == "player", "G2.3: Outpost owning_faction_id transferred to 'player'")
	_assert(obj.previous_owner_id == "rival_military", "G2.4: Outpost previous_owner_id recorded as 'rival_military'")
	_assert(obj.original_owner_id == "rival_military", "G2.5: Outpost original_owner_id preserved as 'rival_military'")
	_assert(obj.capture_revision == 1, "G2.6: Outpost capture_revision incremented to 1")
	_assert(obj.is_captured == true, "G2.7: Outpost marked is_captured = true")
	_assert(obj.is_alive == true, "G2.8: Outpost is_alive restored to true (not permanently dead)")
	_assert(obj.health == 70.0, "G2.9: Outpost recovered to 35% health (round(200 * 0.35) = 70)")
	_assert(obj.is_under_active_siege == false, "G2.10: Outpost is_under_active_siege reset to false")
	_assert(obj.objective_name == "Tiền Đồn Vương Quốc", "G2.11: Outpost name updated to 'Tiền Đồn Vương Quốc'")
	_assert(signal_captured["emitted"] == true, "G2.12: outpost_ownership_changed signal emitted")
	_assert(signal_captured["new_owner"] == "player", "G2.13: Signal reported new_owner 'player'")
	_assert(signal_captured["prev_owner"] == "rival_military", "G2.14: Signal reported prev_owner 'rival_military'")
	_assert(rm.get_resource("gold") == 160, "G2.15: Plunder awarded gold (100 -> 160)")

	sm.clear_all_objectives()

# -----------------------------------------------------------------------------
# Group 3: Player Siege Defeat & Withdrawal Safety
# -----------------------------------------------------------------------------

func _test_group_3_player_siege_defeat_and_withdrawal_safety() -> void:
	print("\n--- Group 3: Player Siege Defeat & Withdrawal Safety ---")
	var fm = MockFactionManager.new()
	var fac = MockFactionData.new()
	fac.id = "neutral_tribe"
	fac.is_at_war = true
	fac.military_power = 60.0
	fm.add_faction(fac)

	var army_mgr = PlayerArmyManagerScript.new()
	var tac_mgr = TacticalMilitaryManagerScript.new(null, army_mgr)
	army_mgr.set_tactical_military_manager(tac_mgr)
	army_mgr.soldier_count = 2
	tac_mgr.sync_with_player_army()
	for u in tac_mgr.get_all_units():
		u.current_cell = Vector2i(15, 16)
	army_mgr.current_cell = Vector2i(15, 16)
	army_mgr.destination_cell = Vector2i(15, 16)
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD

	var sm = FieldSiegeManagerScript.new(null, fm, army_mgr, null)
	var obj = sm.register_objective("obj_def_1", Vector2i(15, 15), "neutral_tribe", 250.0, 3)

	var signal_captured := {"emitted": false}
	sm.outpost_ownership_changed.connect(func(_oid, _prev_o, _new_o, _tx):
		signal_captured["emitted"] = true
	)

	# 1. Defeat test (wiping out army)
	var launch_res = sm.launch_field_siege("neutral_tribe", "obj_def_1")
	var s_id: String = launch_res.get("siege_id", "")
	army_mgr.soldier_count = 0
	tac_mgr.clear_all_units()
	var eval_defeat = sm.evaluate_siege_status(s_id)

	_assert(eval_defeat.get("outcome") == "DEFEAT", "G3.1: Wipeout resolves as DEFEAT")
	_assert(obj.owning_faction_id == "neutral_tribe", "G3.2: Outpost ownership unchanged on DEFEAT")
	_assert(obj.capture_revision == 0, "G3.3: Capture revision remains 0 on DEFEAT")
	_assert(obj.is_captured == false, "G3.4: is_captured remains false on DEFEAT")
	_assert(signal_captured["emitted"] == false, "G3.5: No ownership change signal emitted on DEFEAT")

	# 2. Withdrawal test
	army_mgr.soldier_count = 2
	tac_mgr.sync_with_player_army()
	for u in tac_mgr.get_all_units():
		u.current_cell = Vector2i(15, 16)
	army_mgr.current_cell = Vector2i(15, 16)
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD

	var launch_res2 = sm.launch_field_siege("neutral_tribe", "obj_def_1")
	var s_id2: String = launch_res2.get("siege_id", "")
	for u in tac_mgr.get_all_units():
		u.current_cell = Vector2i(32, 33)
	army_mgr.current_cell = Vector2i(32, 33)
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.GARRISONED

	var eval_with = sm.evaluate_siege_status(s_id2)
	_assert(eval_with.get("outcome") == "WITHDRAWAL", "G3.6: Retreat resolves as WITHDRAWAL")
	_assert(obj.owning_faction_id == "neutral_tribe", "G3.7: Outpost ownership unchanged on WITHDRAWAL")
	_assert(obj.capture_revision == 0, "G3.8: Capture revision remains 0 on WITHDRAWAL")
	_assert(signal_captured["emitted"] == false, "G3.9: No ownership change signal emitted on WITHDRAWAL")

	sm.clear_all_objectives()

# -----------------------------------------------------------------------------
# Group 4: NPC-NPC Attacker Victory Captures Outpost
# -----------------------------------------------------------------------------

func _test_group_4_npc_attacker_victory_captures_outpost() -> void:
	print("\n--- Group 4: NPC-NPC Attacker Victory Captures Outpost ---")
	var fm := FactionManagerScript.new()
	var bcm := BattleCampaignManagerScript.new()
	var fsm := FieldSiegeManagerScript.new()
	fsm.set_faction_manager(fm)
	bcm.set_faction_manager(fm)
	bcm.set_custom_field_siege_manager(fsm)

	# Register defender outpost with 20 HP (lethal damage will breach it)
	var def_outpost = fsm.register_objective("outpost_rival_merchant", Vector2i(45, 20), "rival_merchant", 200.0, 3)
	def_outpost.health = 20.0

	var mil_fac = fm.get_faction("rival_military")
	var mer_fac = fm.get_faction("rival_merchant")
	mil_fac.military_power = 95.0
	mer_fac.military_power = 10.0
	mer_fac.stability = 60.0

	# War declaration auto-schedules campaign for Day 4 (Day 2 + 2)
	bcm.set_custom_current_day(2)
	fm.declare_war_between_factions("rival_military", "rival_merchant", "Border dispute", 2)

	var p_key: String = FactionRelationDataScript.make_pair_key("rival_military", "rival_merchant")
	var camp: Dictionary = bcm.get_pending_inter_faction_campaign_for_pair(p_key)
	_assert(not camp.is_empty(), "G4.1: Inter-faction campaign auto-scheduled for pair")

	var camp_id: String = camp.get("campaign_id", "")
	var sched_day: int = int(camp.get("scheduled_day", 4))
	bcm.set_custom_current_day(sched_day)
	var resolve_res = bcm.resolve_inter_faction_campaign(camp_id, sched_day)

	_assert(resolve_res.get("success", false) == true, "G4.2: Campaign resolved successfully")
	var ctx: Dictionary = resolve_res.get("context", {})
	_assert(ctx.get("victor") == "attacker", "G4.3: Attacker won the battle")
	_assert(ctx.get("outpost_sacked") == true, "G4.4: Context records outpost_sacked = true")
	_assert(ctx.get("outpost_captured") == true, "G4.5: Context records outpost_captured = true")
	_assert(ctx.get("captured_outpost_id") == "outpost_rival_merchant", "G4.6: Captured outpost ID recorded")
	_assert(ctx.get("new_owner_id") == "rival_military", "G4.7: New owner recorded as rival_military")
	_assert(ctx.get("previous_owner_id") == "rival_merchant", "G4.8: Previous owner recorded as rival_merchant")

	# Check live outpost actor state
	_assert(def_outpost.owning_faction_id == "rival_military", "G4.9: Outpost owning_faction_id transferred to rival_military")
	_assert(def_outpost.previous_owner_id == "rival_merchant", "G4.10: Outpost previous_owner_id is rival_merchant")
	_assert(def_outpost.original_owner_id == "rival_merchant", "G4.11: Outpost original_owner_id is preserved as rival_merchant")
	_assert(def_outpost.capture_revision == 1, "G4.12: Outpost capture_revision incremented to 1")
	_assert(def_outpost.is_captured == true, "G4.13: Outpost is_captured is true")
	_assert(def_outpost.is_alive == true, "G4.14: Outpost is_alive restored to true")
	_assert(def_outpost.health == 70.0, "G4.15: Outpost restored to 35% health (round(200 * 0.35) = 70)")
	_assert(resolve_res.get("peace_signed") == true, "G4.16: Sacking outpost triggers peace treaty")

	def_outpost.free()

# -----------------------------------------------------------------------------
# Group 5: Defender Victory & Draw Safety
# -----------------------------------------------------------------------------

func _test_group_5_defender_victory_and_draw_safety() -> void:
	print("\n--- Group 5: Defender Victory & Draw Safety ---")
	var fm := FactionManagerScript.new()
	var bcm := BattleCampaignManagerScript.new()
	var fsm := FieldSiegeManagerScript.new()
	fsm.set_faction_manager(fm)
	bcm.set_faction_manager(fm)
	bcm.set_custom_field_siege_manager(fsm)

	# 1. Defender Victory Scenario
	var def_outpost = fsm.register_objective("outpost_rival_military", Vector2i(10, 10), "rival_military", 300.0, 4)

	bcm.set_custom_current_day(2)
	fm.declare_war_between_factions("rival_merchant", "rival_military", "Revenge", 2)

	# Overpower defender: rival_military (def) 95 power vs rival_merchant (atk) 10 power
	var atk_fac = fm.get_faction("rival_merchant")
	var def_fac = fm.get_faction("rival_military")
	atk_fac.military_power = 10.0
	def_fac.military_power = 95.0

	var p_key: String = FactionRelationDataScript.make_pair_key("rival_merchant", "rival_military")
	var camp: Dictionary = bcm.get_pending_inter_faction_campaign_for_pair(p_key)
	var camp_id: String = camp.get("campaign_id", "")
	var sched_day: int = int(camp.get("scheduled_day", 4))
	bcm.set_custom_current_day(sched_day)
	var resolve_res = bcm.resolve_inter_faction_campaign(camp_id, sched_day)

	_assert(resolve_res.get("success", false) == true, "G5.1: Campaign resolved successfully")
	var ctx: Dictionary = resolve_res.get("context", {})
	_assert(ctx.get("victor") == "defender", "G5.2: Defender won the battle")
	_assert(ctx.get("outpost_sacked") == false, "G5.3: Outpost was NOT sacked")
	_assert(def_outpost.owning_faction_id == "rival_military", "G5.4: Outpost ownership remains with defender rival_military")
	_assert(def_outpost.capture_revision == 0, "G5.5: Capture revision remains 0")
	_assert(def_outpost.is_captured == false, "G5.6: is_captured remains false")
	_assert(def_outpost.health == 300.0, "G5.7: Outpost health unharmed by defeated attacker")

	def_outpost.free()

	# 2. Draw / Stalemate Scenario
	var def_outpost2 = fsm.register_objective("outpost_draw_test", Vector2i(12, 12), "rival_merchant", 300.0, 4)
	bcm.set_custom_current_day(10)
	fm.declare_war_between_factions("rival_military", "rival_merchant", "Border dispute", 10)
	var atk_mil = fm.get_faction("rival_military")
	var def_merch = fm.get_faction("rival_merchant")
	atk_mil.military_power = 60.0
	atk_mil.stability = 70.0
	def_merch.military_power = 60.0
	def_merch.stability = 70.0

	var p_key_draw: String = FactionRelationDataScript.make_pair_key("rival_military", "rival_merchant")
	var camp_draw: Dictionary = bcm.get_pending_inter_faction_campaign_for_pair(p_key_draw)
	var camp_id_draw: String = camp_draw.get("campaign_id", "")
	var sched_day_draw: int = int(camp_draw.get("scheduled_day", 12))
	bcm.set_custom_current_day(sched_day_draw)
	var resolve_draw = bcm.resolve_inter_faction_campaign(camp_id_draw, sched_day_draw)

	_assert(resolve_draw.get("success", false) == true, "G5.8: Draw campaign resolved successfully")
	var rep_draw: BattleResolver.BattleReport = resolve_draw.get("report")
	var is_real_draw: bool = (rep_draw != null and (rep_draw.victor == "draw" or rep_draw.victor == "stalemate"))
	_assert(is_real_draw, "G5.9: Battle result is genuine draw/stalemate (report.victor == '%s')" % (rep_draw.victor if rep_draw else "null"))
	var ctx_draw: Dictionary = resolve_draw.get("context", {})
	_assert(ctx_draw.get("outpost_sacked") == false, "G5.10: Outpost was NOT sacked in draw/stalemate")
	_assert(def_outpost2.owning_faction_id == "rival_merchant", "G5.11: Outpost owner unchanged in draw")
	_assert(def_outpost2.capture_revision == 0, "G5.12: Capture revision unchanged in draw")
	_assert(def_outpost2.is_captured == false, "G5.13: is_captured remains false in draw")
	_assert(def_outpost2.health == 300.0, "G5.14: Outpost health unharmed in draw")

	def_outpost2.free()

# -----------------------------------------------------------------------------
# Group 6: Duplicate Transaction & Idempotency
# -----------------------------------------------------------------------------

func _test_group_6_duplicate_transaction_and_idempotency() -> void:
	print("\n--- Group 6: Duplicate Transaction & Idempotency ---")
	var sm = FieldSiegeManagerScript.new()
	var obj = sm.register_objective("obj_idem_1", Vector2i(25, 25), "rival_military", 200.0, 3)

	var sig_tracker := {"count": 0}
	sm.outpost_ownership_changed.connect(func(_oid, _po, _no, _tx):
		sig_tracker["count"] = int(sig_tracker["count"]) + 1
	)

	# 1. First transfer with transaction ID "tx_001"
	var res1 = sm.transfer_outpost_ownership("obj_idem_1", "player", "tx_001")
	_assert(res1.get("success", false) == true, "G6.1: First transfer succeeds")
	_assert(res1.get("already_applied", true) == false, "G6.2: First transfer already_applied is false")
	_assert(obj.capture_revision == 1, "G6.3: Capture revision is 1")
	_assert(obj.owning_faction_id == "player", "G6.4: Owner is player")
	_assert(int(sig_tracker["count"]) == 1, "G6.5: Signal emitted exactly once")

	# Modify health to check it doesn't get re-overwritten
	obj.health = 50.0

	# 2. Duplicate transfer with identical transaction ID "tx_001"
	var res2 = sm.transfer_outpost_ownership("obj_idem_1", "player", "tx_001")
	_assert(res2.get("success", false) == true, "G6.6: Duplicate transfer returns success")
	_assert(res2.get("already_applied", false) == true, "G6.7: Duplicate transfer flagged already_applied = true")
	_assert(obj.capture_revision == 1, "G6.8: Capture revision did NOT increment (remains 1)")
	_assert(obj.health == 50.0, "G6.9: Outpost health was NOT re-overwritten by duplicate transaction")
	_assert(int(sig_tracker["count"]) == 1, "G6.10: Zero duplicate signals emitted")

	# 3. Transfer to same owner with a different transaction ID
	var res3 = sm.transfer_outpost_ownership("obj_idem_1", "player", "tx_002")
	_assert(res3.get("success", false) == true, "G6.11: Transfer to existing owner returns success")
	_assert(res3.get("already_applied", false) == true, "G6.12: Transfer to existing owner flagged already_applied = true")
	_assert(obj.capture_revision == 1, "G6.13: Capture revision still 1")
	_assert(int(sig_tracker["count"]) == 1, "G6.14: Zero signals emitted when owner unchanged")

	sm.clear_all_objectives()

# -----------------------------------------------------------------------------
# Group 7: Invalid Objective & Conflict Safety
# -----------------------------------------------------------------------------

func _test_group_7_invalid_objective_and_conflict_safety() -> void:
	print("\n--- Group 7: Invalid Objective & Conflict Safety ---")
	var sm = FieldSiegeManagerScript.new()
	var obj = sm.register_objective("obj_safe_1", Vector2i(20, 20), "rival_military", 200.0, 3)

	# 1. Non-existent objective
	var res_bad_obj = sm.transfer_outpost_ownership("non_existent_objective", "player", "tx_bad_obj")
	_assert(res_bad_obj.get("success", true) == false, "G7.1: Non-existent objective rejected")
	_assert(res_bad_obj.get("already_applied", true) == false, "G7.2: Rejected transaction is not already_applied")

	# 2. Invalid owner ID
	var res_bad_owner = sm.transfer_outpost_ownership("obj_safe_1", "   ", "tx_bad_owner")
	_assert(res_bad_owner.get("success", true) == false, "G7.3: Empty owner ID rejected")

	# 3. Active siege conflict: NPC campaign must NOT capture an outpost under active player siege
	var bcm := BattleCampaignManagerScript.new()
	var fm := FactionManagerScript.new()
	sm.set_faction_manager(fm)
	bcm.set_faction_manager(fm)
	bcm.set_custom_field_siege_manager(sm)

	bcm.set_custom_current_day(1)
	fm.declare_war_between_factions("rival_merchant", "rival_military", "War", 1)
	var atk_fac_c = fm.get_faction("rival_merchant")
	var def_fac_c = fm.get_faction("rival_military")
	atk_fac_c.military_power = 95.0
	def_fac_c.military_power = 10.0
	obj.health = 10.0
	obj.is_under_active_siege = true # Outpost currently under player siege!

	var p_key: String = FactionRelationDataScript.make_pair_key("rival_merchant", "rival_military")
	var camp: Dictionary = bcm.get_pending_inter_faction_campaign_for_pair(p_key)
	var camp_id: String = camp.get("campaign_id", "")
	var sched_day: int = int(camp.get("scheduled_day", 3))
	bcm.set_custom_current_day(sched_day)
	var res_conflict = bcm.resolve_inter_faction_campaign(camp_id, sched_day)
	var rep_conflict: BattleResolver.BattleReport = res_conflict.get("report")

	_assert(res_conflict.get("success", false) == true, "G7.4: Battle resolved")
	_assert(rep_conflict != null and rep_conflict.victor == "attacker", "G7.5: NPC attacker won the battle decisively (assert victor == attacker)")
	_assert(res_conflict.get("context", {}).get("outpost_sacked") == false, "G7.6: Outpost under active player siege was NOT sacked despite attacker victory")
	_assert(obj.owning_faction_id == "rival_military", "G7.7: Outpost ownership unchanged during active siege conflict")
	_assert(obj.health == 10.0, "G7.8: Outpost health unharmed (10.0 HP preserved)")
	_assert(obj.capture_revision == 0, "G7.9: Capture revision did not increment during active siege collision")

	# 4. Defender owns no outposts: abstract battle resolves without creating phantom territory change
	var bcm2 := BattleCampaignManagerScript.new()
	var fm2 := FactionManagerScript.new()
	var sm_empty := FieldSiegeManagerScript.new()
	bcm2.set_faction_manager(fm2)
	bcm2.set_custom_field_siege_manager(sm_empty)
	bcm2.set_custom_current_day(1)
	fm2.declare_war_between_factions("rival_military", "neutral_tribe", "Ghost war", 1)
	var p_key2: String = FactionRelationDataScript.make_pair_key("rival_military", "neutral_tribe")
	var camp2: Dictionary = bcm2.get_pending_inter_faction_campaign_for_pair(p_key2)
	var sched_day2: int = int(camp2.get("scheduled_day", 3))
	bcm2.set_custom_current_day(sched_day2)
	var res_no_outpost = bcm2.resolve_inter_faction_campaign(camp2.get("campaign_id", ""), sched_day2)
	_assert(res_no_outpost.get("success", false) == true, "G7.10: Campaign with no defender outposts resolved cleanly")
	_assert(res_no_outpost.get("context", {}).get("outpost_sacked") == false, "G7.11: Zero phantom outpost sackings when defender has no outposts")

	# 5. Player cannot launch siege against player-owned outpost
	obj.is_under_active_siege = false
	sm.transfer_outpost_ownership("obj_safe_1", "player", "tx_player_claim")
	var army_mgr = PlayerArmyManagerScript.new()
	var tac_mgr = TacticalMilitaryManagerScript.new(null, army_mgr)
	army_mgr.set_tactical_military_manager(tac_mgr)
	army_mgr.soldier_count = 5
	tac_mgr.sync_with_player_army()
	for u in tac_mgr.get_all_units():
		u.current_cell = Vector2i(20, 21)
	army_mgr.current_cell = Vector2i(20, 21)
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD
	sm.set_player_army_manager(army_mgr)
	sm.set_faction_manager(fm)

	var mil_fac = fm.get_faction("rival_military")
	mil_fac.is_at_war = true
	var check_self = sm.can_launch_field_siege("rival_military", "obj_safe_1")
	_assert(check_self.get("can_launch", true) == false, "G7.12: Player cannot launch siege against player-owned outpost")
	_assert(check_self.get("reason", "").find("quyền kiểm soát của bạn") != -1, "G7.13: Rejection reason clearly states outpost is player-owned")

	# 6. Invalid Input Validation Tests (Section 4E)
	# A. Empty / Whitespace transaction ID rejected with zero side-effects
	var pre_hp = obj.health
	var pre_rev = obj.capture_revision
	var res_ws_tx = sm.transfer_outpost_ownership("obj_safe_1", "player", "   \t  ")
	_assert(res_ws_tx.get("success", true) == false, "G7.14: Whitespace transaction ID rejected")
	_assert(obj.owning_faction_id == "player", "G7.15: Owner unchanged on whitespace tx_id")
	_assert(obj.capture_revision == pre_rev, "G7.16: Revision unchanged on whitespace tx_id")
	_assert(obj.health == pre_hp, "G7.17: Health unchanged on whitespace tx_id")

	# B. Non-existent owner ID rejected with zero side-effects
	var res_bad_owner_id = sm.transfer_outpost_ownership("obj_safe_1", "unknown_empire_xyz", "tx_valid_but_unknown")
	_assert(res_bad_owner_id.get("success", true) == false, "G7.18: Non-existent faction owner ID rejected")
	_assert(obj.owning_faction_id == "player", "G7.19: Owner unchanged on non-existent owner ID")
	_assert(obj.capture_revision == pre_rev, "G7.20: Revision unchanged on non-existent owner ID")

	# C. No FactionManager present: attempting to transfer to unknown non-player owner fails closed
	var sm_no_fm = FieldSiegeManagerScript.new()
	var obj_no_fm = sm_no_fm.register_objective("obj_no_fm_test", Vector2i(5, 5), "neutral_tribe", 200.0)
	var res_no_fm = sm_no_fm.transfer_outpost_ownership("obj_no_fm_test", "rival_merchant", "tx_no_fm_01")
	_assert(res_no_fm.get("success", true) == false, "G7.21: Fail-closed when no FactionManager and non-player owner")
	_assert(obj_no_fm.owning_faction_id == "neutral_tribe", "G7.22: Outpost owner unchanged when FactionManager is null")
	_assert(obj_no_fm.capture_revision == 0, "G7.23: Capture revision unchanged when FactionManager is null")
	_assert(obj_no_fm.health == 200.0, "G7.24: Outpost health unchanged when FactionManager is null")

	# D. Direct actor transfer fails closed without FactionManager
	var direct_actor = SiegeObjectiveActorScript.new()
	direct_actor.owning_faction_id = "neutral_tribe"
	direct_actor.health = 200.0
	var res_direct_unknown = direct_actor.transfer_ownership("rival_merchant", "tx_direct_01")
	_assert(res_direct_unknown.get("success", true) == false, "G7.25: Direct actor transfer to non-player fails closed without FactionManager")
	_assert(direct_actor.owning_faction_id == "neutral_tribe", "G7.26: Direct actor owner unchanged")
	_assert(direct_actor.capture_revision == 0, "G7.27: Direct actor revision unchanged")
	_assert(direct_actor.health == 200.0, "G7.28: Direct actor health unchanged")
	direct_actor.free()
	sm_no_fm.clear_all_objectives()

	sm.clear_all_objectives()

# -----------------------------------------------------------------------------
# Group 8: Save/Load Persistence, Recapture, and Tamper Resistance
# -----------------------------------------------------------------------------

func _test_group_8_save_load_persistence_and_recapture() -> void:
	print("\n--- Group 8: Save/Load Persistence, Recapture, and Tamper Resistance ---")
	var fm_g8 := FactionManagerScript.new()
	var sm1 = FieldSiegeManagerScript.new()
	sm1.set_faction_manager(fm_g8)
	var obj = sm1.register_objective("outpost_pers_1", Vector2i(32, 32), "neutral_tribe", 250.0, 3)

	# 1. First capture: player takes neutral_tribe outpost
	var res_cap1 = sm1.transfer_outpost_ownership("outpost_pers_1", "player", "tx_cap_01")
	_assert(res_cap1.get("success", false) == true, "G8.1: Player capture succeeded")
	_assert(obj.owning_faction_id == "player", "G8.2: Owner is player")
	_assert(obj.capture_revision == 1, "G8.3: Revision is 1")

	# 2. Recapture: rival_military recaptures the outpost from player!
	# Verifies is_captured does NOT prevent recapture
	var res_recap = sm1.transfer_outpost_ownership("outpost_pers_1", "rival_military", "tx_cap_02")
	_assert(res_recap.get("success", false) == true, "G8.4: Recapture succeeded (is_captured does not block recapture)")
	_assert(obj.owning_faction_id == "rival_military", "G8.5: Owner is rival_military")
	_assert(obj.previous_owner_id == "player", "G8.6: Previous owner is player")
	_assert(obj.original_owner_id == "neutral_tribe", "G8.7: Original owner is preserved as neutral_tribe")
	_assert(obj.capture_revision == 2, "G8.8: Capture revision is 2")
	_assert(obj.last_capture_tx_id == "tx_cap_02", "G8.9: Last transaction ID is tx_cap_02")
	_assert(obj.is_alive == true, "G8.10: Outpost is alive after recapture")
	_assert(obj.health == 88.0, "G8.11: 35% health restored on recapture (round(250 * 0.35) = 88)")

	# 3. Roundtrip serialization
	var serialized: Dictionary = sm1.serialize()
	_assert(serialized.has("objectives"), "G8.12: Serialized data contains objectives")

	# Validate schema with SaveManager.validate_save_data
	var full_save_data := {
		"schema_version": 1,
		"metadata": {"save_time": 1000, "game_version": "1.0"},
		"resources": {"stock": {}, "capacities": {}, "active_population": 0, "is_starving": false},
		"buildings": [],
		"citizens": [],
		"field_siege": serialized
	}
	var val_res = SaveManagerScript.validate_save_data(full_save_data)
	_assert(val_res.get("valid", false) == true, "G8.13: Serialized outpost data passes SaveManager validation")

	# 4. Tamper test: corrupt capture_revision with non-integer or negative
	var corrupt_save = full_save_data.duplicate(true)
	corrupt_save["field_siege"]["objectives"][0]["capture_revision"] = "not_an_int"
	var val_corrupt = SaveManagerScript.validate_save_data(corrupt_save)
	_assert(val_corrupt.get("valid", true) == false, "G8.14: Tampered capture_revision rejected fail-closed")

	# 5. Deserialize into a clean manager
	var sm2 = FieldSiegeManagerScript.new()
	sm2.set_faction_manager(fm_g8)
	var des_ok: bool = sm2.deserialize(serialized)
	_assert(des_ok == true, "G8.15: Deserialization into clean manager succeeded")

	var restored_obj = sm2.get_objective("outpost_pers_1")
	_assert(restored_obj != null, "G8.16: Restored objective exists")
	_assert(restored_obj.owning_faction_id == "rival_military", "G8.17: Restored owning_faction_id is rival_military")
	_assert(restored_obj.previous_owner_id == "player", "G8.18: Restored previous_owner_id is player")
	_assert(restored_obj.original_owner_id == "neutral_tribe", "G8.19: Restored original_owner_id is neutral_tribe")
	_assert(restored_obj.capture_revision == 2, "G8.20: Restored capture_revision is 2")
	_assert(restored_obj.last_capture_tx_id == "tx_cap_02", "G8.21: Restored last_capture_tx_id is tx_cap_02")
	_assert(restored_obj.health == 88.0, "G8.22: Restored health is 88.0")
	_assert(restored_obj.is_alive == true, "G8.23: Restored is_alive is true")
	_assert(restored_obj.is_captured == true, "G8.24: Restored is_captured is true")

	sm1.clear_all_objectives()
	sm2.clear_all_objectives()

	# 6. End-to-End SaveManager Workflow with Live World Scene (Section 4C & 4D)
	var world_scene: PackedScene = load("res://scenes/world/world_view.tscn")
	var live_world = world_scene.instantiate()
	root.add_child(live_world)

	var live_fsm = live_world.get("field_siege_mgr")
	_assert(live_fsm != null, "G8.25: Live WorldView field_siege_mgr exists")

	# Register and capture outpost in live world
	var live_obj = live_fsm.register_objective("outpost_e2e_live", Vector2i(22, 22), "rival_military", 300.0, 3)
	var e2e_cap = live_fsm.transfer_outpost_ownership("outpost_e2e_live", "player", "tx_e2e_01")
	_assert(e2e_cap.get("success", false) == true, "G8.26: Live world outpost capture succeeded")
	_assert(live_obj.owning_faction_id == "player", "G8.27: Live outpost owner is player")
	_assert(live_obj.original_owner_id == "rival_military", "G8.28: Live outpost original owner is rival_military")
	_assert(live_obj.previous_owner_id == "rival_military", "G8.29: Live outpost previous owner is rival_military")
	_assert(live_obj.capture_revision == 1, "G8.30: Live outpost capture revision is 1")
	_assert(live_obj.last_capture_tx_id == "tx_e2e_01", "G8.31: Live outpost last_capture_tx_id is tx_e2e_01")
	_assert(live_obj.health == 105.0, "G8.32: Live outpost health is 105.0 (35% of 300)")

	# Serialize via real SaveManager.serialize_world_state()
	var e2e_save_data: Dictionary = SaveManagerScript.serialize_world_state(live_world)
	_assert(e2e_save_data.has("field_siege"), "G8.33: Serialized world state has field_siege section")
	_assert(e2e_save_data["field_siege"].has("objectives"), "G8.34: Serialized field_siege has objectives array")

	# Mutate live world state to verify loaded state genuinely restores
	live_obj.owning_faction_id = "rival_military"
	live_obj.previous_owner_id = "unknown"
	live_obj.capture_revision = 999
	live_obj.last_capture_tx_id = "tx_corrupted"
	live_obj.health = 5.0

	# Apply loaded state via real SaveManager.apply_loaded_state_to_world()
	var apply_e2e = SaveManagerScript.apply_loaded_state_to_world(live_world, e2e_save_data)
	_assert(apply_e2e.get("success", false) == true, "G8.35: SaveManager.apply_loaded_state_to_world succeeded")

	var e2e_restored = live_fsm.get_objective("outpost_e2e_live")
	_assert(e2e_restored != null, "G8.36: Restored outpost exists in live world")
	_assert(e2e_restored.owning_faction_id == "player", "G8.37: Restored owner is player")
	_assert(e2e_restored.original_owner_id == "rival_military", "G8.38: Restored original owner is rival_military")
	_assert(e2e_restored.previous_owner_id == "rival_military", "G8.39: Restored previous owner is rival_military")
	_assert(e2e_restored.capture_revision == 1, "G8.40: Restored capture revision is 1")
	_assert(e2e_restored.last_capture_tx_id == "tx_e2e_01", "G8.41: Restored last_capture_tx_id is tx_e2e_01")
	_assert(e2e_restored.health == 105.0, "G8.42: Restored health is 105.0")

	# 7. Legacy Save Migration Test via real SaveManager (Section 4D)
	var legacy_save_data: Dictionary = e2e_save_data.duplicate(true)
	var fs_objs: Array = legacy_save_data.get("field_siege", {}).get("objectives", [])
	for o_dict in fs_objs:
		o_dict.erase("original_owner_id")
		o_dict.erase("previous_owner_id")
		o_dict.erase("capture_revision")
		o_dict.erase("last_capture_tx_id")

	var apply_leg = SaveManagerScript.apply_loaded_state_to_world(live_world, legacy_save_data)
	_assert(apply_leg.get("success", false) == true, "G8.43: SaveManager.apply_loaded_state_to_world succeeded on legacy save")

	var leg_restored = live_fsm.get_objective("outpost_e2e_live")
	_assert(leg_restored != null, "G8.44: Legacy restored objective exists in live world")
	_assert(leg_restored.original_owner_id == leg_restored.owning_faction_id, "G8.45: Legacy migration defaults original_owner_id = owning_faction_id")
	_assert(leg_restored.previous_owner_id == "", "G8.46: Legacy migration defaults previous_owner_id = empty")
	_assert(leg_restored.capture_revision == 0, "G8.47: Legacy migration defaults capture_revision = 0")
	_assert(leg_restored.last_capture_tx_id == "", "G8.48: Legacy migration defaults last_capture_tx_id = empty")

	live_world.queue_free()

# -----------------------------------------------------------------------------
# Test Helper Doubles (Mock Classes)
# -----------------------------------------------------------------------------

class MockFactionData extends RefCounted:
	var id: String = ""
	var name: String = "Mock Faction"
	var existence_status: String = "active"
	var is_at_war: bool = false
	var military_power: float = 50.0

class MockFactionManager extends RefCounted:
	var _factions: Dictionary = {}
	func add_faction(fac: MockFactionData) -> void:
		_factions[fac.id] = fac
	func get_faction(fac_id: String) -> MockFactionData:
		return _factions.get(fac_id, null)
	func are_factions_at_war(f1: String, f2: String) -> bool:
		var fac = get_faction(f1) if f1 != "player" else get_faction(f2)
		return fac.is_at_war if fac != null else false

class MockResourceManager extends RefCounted:
	var resources: Dictionary = {"gold": 100, "food": 100, "wood": 100, "metal": 100}
	func add_resource(r_type: String, amt: int) -> int:
		resources[r_type] = int(resources.get(r_type, 0)) + amt
		return amt
	func get_resource(r_type: String) -> int:
		return int(resources.get(r_type, 0))
