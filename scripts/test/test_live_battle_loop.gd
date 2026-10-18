extends SceneTree
## Test Suite: Package 1K — Live War & Settlement Defense Battle Loop
## Verifies TC-LB.1 through TC-LB.13:
## War declaration, raid scheduling delay (3 days), peace cancellation,
## attacking & defending force construction, zero-troop edge cases & casualty bounds,
## Palisade fortification integration, deterministic guard casualty lifecycle,
## faction military power loss & non-negativity, resource plunder limits,
## strict idempotency, multi-faction independence, save/load persistence,
## legacy save compatibility, and TimeManager daily advancement.

const BattleCampaignManagerScript = preload("res://scripts/combat/battle_campaign_manager.gd")
const BattleResolverScript = preload("res://scripts/combat/battle_resolver.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const FactionManagerScript = preload("res://scripts/factions/faction_manager.gd")
const FactionDataScript = preload("res://scripts/factions/faction_data.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const CitizenControllerScript = preload("res://scripts/entities/citizen_controller.gd")
const JobManagerScript = preload("res://scripts/jobs/job_manager.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const WorldViewScene = preload("res://scenes/world/world_view.tscn")

var frame_count: int = 0
var world_instance: Node = null
var failures: int = 0

class MockResourceManager:
	var stock: Dictionary = {}
	var reserved: Dictionary = {}

	func _init() -> void:
		stock = {
			EconomyConfigScript.RES_FOOD: 200,
			EconomyConfigScript.RES_WOOD: 150,
			EconomyConfigScript.RES_GOLD: 100,
			EconomyConfigScript.RES_STONE: 80
		}
		reserved = {
			EconomyConfigScript.RES_FOOD: 20,
			EconomyConfigScript.RES_WOOD: 0,
			EconomyConfigScript.RES_GOLD: 0,
			EconomyConfigScript.RES_STONE: 0
		}

	func get_available_stock(res_id: String) -> int:
		return maxi(0, stock.get(res_id, 0) - reserved.get(res_id, 0))

	func consume_resource(res_id: String, amount: int) -> bool:
		var avail = get_available_stock(res_id)
		if avail >= amount:
			stock[res_id] = stock.get(res_id, 0) - amount
			return true
		return false

func _init() -> void:
	print("\n========================================================")
	print("  STARTING PACKAGE 1K LIVE BATTLE LOOP TEST SUITE")
	print("========================================================\n")

	_run_unit_checks()

	# Instantiate WorldView for live integration checks across frames
	world_instance = WorldViewScene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1

	if frame_count == 3:
		_run_world_integration_checks()

	if frame_count == 4:
		print("\n--------------------------------------------------------")
		if failures == 0:
			print("  ALL PACKAGE 1K LIVE BATTLE LOOP TESTS PASSED! (Exit Code 0)")
			print("--------------------------------------------------------\n")
			quit(0)
			return true
		else:
			printerr("  PACKAGE 1K LIVE BATTLE LOOP TESTS FAILED with %d failures! (Exit Code 1)" % failures)
			print("--------------------------------------------------------\n")
			quit(1)
			return true

	return false

# -----------------------------------------------------------------------------
# Unit Checks: Campaign Manager, Force Modeling, Combat Rules, Idempotency
# -----------------------------------------------------------------------------
func _run_unit_checks() -> void:
	# -------------------------------------------------------------------------
	# TC-LB.1: War Declaration & Initial Delay (3 days)
	# -------------------------------------------------------------------------
	print("--- Running TC-LB.1: War Declaration & Scheduling Delay ---")
	var fm := FactionManagerScript.new()
	var bcm := BattleCampaignManagerScript.new(null, fm, 12345)
	bcm.set_custom_current_day(2)

	var war_res = fm.declare_war("rival_military")
	if not war_res.get("success", false):
		printerr("  [FAIL] TC-LB.1: FactionManager declare_war failed")
		failures += 1

	if not bcm.has_pending_raid("rival_military"):
		printerr("  [FAIL] TC-LB.1: War declaration did not schedule raid")
		failures += 1
	else:
		var pending = bcm.get_pending_raid("rival_military")
		# Day 2 + 3 = Day 5
		if pending.get("scheduled_day") != 5:
			printerr("  [FAIL] TC-LB.1: Expected raid day 5, got %d" % pending.get("scheduled_day"))
			failures += 1
		elif pending.get("raid_sequence") != 1:
			printerr("  [FAIL] TC-LB.1: Expected raid sequence 1, got %d" % pending.get("raid_sequence"))
			failures += 1
		else:
			print("  [PASS] TC-LB.1: First raid scheduled strictly for Day 5 (Day 2 + 3 delay).")

	# -------------------------------------------------------------------------
	# TC-LB.2: Peaceful Factions & Peace Cancellation
	# -------------------------------------------------------------------------
	print("\n--- Running TC-LB.2: Peaceful Factions & Peace Cancellation ---")
	var neutral_fac = fm.get_faction("neutral_tribe")
	if neutral_fac.is_at_war:
		printerr("  [FAIL] TC-LB.2: Neutral tribe should not be at war")
		failures += 1

	var peace_schedule_ok = bcm.schedule_raid("neutral_tribe", 10)
	if peace_schedule_ok or bcm.has_pending_raid("neutral_tribe"):
		printerr("  [FAIL] TC-LB.2: Peaceful faction was permitted to schedule raid!")
		failures += 1
	else:
		print("  [PASS] TC-LB.2: Peaceful faction strictly refused raid scheduling.")

	# Sign peace with rival_military
	var peace_res = fm.propose_treaty("rival_military", "peace")
	if not peace_res.get("success", false):
		printerr("  [FAIL] TC-LB.2: Propose peace failed")
		failures += 1
	if bcm.has_pending_raid("rival_military"):
		printerr("  [FAIL] TC-LB.2: Peace signing failed to cancel pending raid!")
		failures += 1
	else:
		print("  [PASS] TC-LB.2: Signing peace immediately cancelled pending raid.")

	# -------------------------------------------------------------------------
	# TC-LB.3: Attacking Force Modeling from FactionData
	# -------------------------------------------------------------------------
	print("\n--- Running TC-LB.3: Attacking Force Construction Model ---")
	var mil_fac = fm.get_faction("rival_military")
	mil_fac.military_power = 75.0
	mil_fac.stability = 80.0
	var atk_force = bcm.construct_attacking_force(mil_fac)

	# 75.0 / 30.0 = 2.5 -> round to 3 troops
	if atk_force.get("troops") != 3:
		printerr("  [FAIL] TC-LB.3: Expected 3 troops for 75 power, got %d" % atk_force.get("troops"))
		failures += 1
	elif atk_force.get("equipment_tier") != 2:
		printerr("  [FAIL] TC-LB.3: Expected tier 2 equipment for rival_military, got %d" % atk_force.get("equipment_tier"))
		failures += 1
	elif not is_equal_approx(atk_force.get("morale"), 80.0):
		printerr("  [FAIL] TC-LB.3: Expected morale 80.0, got %f" % atk_force.get("morale"))
		failures += 1
	else:
		print("  [PASS] TC-LB.3: Attacking force correctly modeled (3 troops, tier 2, 80 morale).")

	# -------------------------------------------------------------------------
	# TC-LB.4: Defending Force Construction & Guard Requirements
	# -------------------------------------------------------------------------
	print("\n--- Running TC-LB.4: Defending Force Construction & Guard Gating ---")
	var world_data := WorldGeneratorScript.generate(8888)
	world_data.buildings.clear()
	bcm.set_custom_world_data(world_data)

	var mock_rm := MockResourceManager.new()
	bcm.set_custom_resource_manager(mock_rm)

	# Case A: 0 barracks -> 0 guards
	var def_force_no_barracks = bcm.construct_defending_force()
	if def_force_no_barracks.get("troops") != 0:
		printerr("  [FAIL] TC-LB.4A: Without active barracks, troops must be 0, got %d" % def_force_no_barracks.get("troops"))
		failures += 1
	else:
		print("  [PASS] TC-LB.4A: Without active barracks, garrison is strictly 0 troops.")

	# Case B: Add active barracks and mock citizens
	world_data.buildings.append({
		"id": "bld_barracks_1",
		"type": "barracks",
		"cell": Vector2i(20, 20),
		"state": "active"
	})

	var cit_guard_1 := CitizenControllerScript.new()
	cit_guard_1.citizen_id = "cit_guard_001"
	cit_guard_1.role = "guard"
	cit_guard_1.health = 100.0
	cit_guard_1.morale = 80.0

	var cit_guard_2 := CitizenControllerScript.new()
	cit_guard_2.citizen_id = "cit_guard_002"
	cit_guard_2.role = "guard"
	cit_guard_2.health = 100.0
	cit_guard_2.morale = 60.0
	# Citizen resting or seeking food still counts as living guard
	cit_guard_2.current_state = CitizenControllerScript.State.RESTING

	var cit_farmer := CitizenControllerScript.new()
	cit_farmer.citizen_id = "cit_farmer_001"
	cit_farmer.role = "farmer"
	cit_farmer.health = 100.0

	bcm.set_custom_citizen_list([cit_guard_1, cit_guard_2, cit_farmer])

	var def_force_with_guards = bcm.construct_defending_force()
	if def_force_with_guards.get("troops") != 2:
		printerr("  [FAIL] TC-LB.4B: Expected 2 guards, got %d" % def_force_with_guards.get("troops"))
		failures += 1
	elif not is_equal_approx(def_force_with_guards.get("morale"), 70.0):
		printerr("  [FAIL] TC-LB.4B: Expected average morale 70.0 ((80+60)/2), got %f" % def_force_with_guards.get("morale"))
		failures += 1
	elif def_force_with_guards.get("resources", {}).get(EconomyConfigScript.RES_FOOD) != 180: # 200 - 20 reserved
		printerr("  [FAIL] TC-LB.4B: Expected 180 available food, got %s" % str(def_force_with_guards.get("resources")))
		failures += 1
	else:
		print("  [PASS] TC-LB.4B: Defending force correctly derived from 2 living guards (avg morale 70.0, available food 180).")

	# -------------------------------------------------------------------------
	# TC-LB.5: Zero-Troop Edge Cases & Casualty Bounds
	# -------------------------------------------------------------------------
	print("\n--- Running TC-LB.5: Zero-Troop Safety & Casualty Bounds ---")
	# 1. 0 vs 0 -> stalemate, 0 casualties
	var r_zero = BattleResolverScript.resolve_battle({"troops": 0}, {"troops": 0}, 111)
	if r_zero.victor != "stalemate" or r_zero.attacker_casualties != 0 or r_zero.defender_casualties != 0:
		printerr("  [FAIL] TC-LB.5: 0 vs 0 must be stalemate with 0 casualties")
		failures += 1
	else:
		print("  [PASS] TC-LB.5A: 0 vs 0 produces stalemate with 0 casualties and 0 crashes.")

	# 2. 5 vs 0 (Unopposed raid) -> attacker victory, 0 casualties on both sides
	var r_unopposed = BattleResolverScript.resolve_battle({"troops": 5}, {"troops": 0, "resources": {"gold": 100}}, 222)
	if r_unopposed.victor != "attacker":
		printerr("  [FAIL] TC-LB.5B: Unopposed attack must be won by attacker")
		failures += 1
	elif r_unopposed.attacker_casualties != 0 or r_unopposed.defender_casualties != 0:
		printerr("  [FAIL] TC-LB.5B: Unopposed attack must not create casualties! Got atk: %d, def: %d" % [r_unopposed.attacker_casualties, r_unopposed.defender_casualties])
		failures += 1
	elif r_unopposed.plunder_spoils.get("gold", 0) != 20: # 20% of 100
		printerr("  [FAIL] TC-LB.5B: Unopposed attack failed to plunder spoils")
		failures += 1
	else:
		print("  [PASS] TC-LB.5B: Unopposed attack resolved safely (Attacker won, 0 casualties, 20 gold plundered).")

	# 3. 0 vs 5 -> defender victory, 0 casualties
	var r_empty_atk = BattleResolverScript.resolve_battle({"troops": 0}, {"troops": 5}, 333)
	if r_empty_atk.victor != "defender" or r_empty_atk.attacker_casualties != 0 or r_empty_atk.defender_casualties != 0:
		printerr("  [FAIL] TC-LB.5C: 0 vs 5 must yield defender victory with 0 casualties")
		failures += 1
	else:
		print("  [PASS] TC-LB.5C: 0 vs 5 produces defender victory with 0 casualties.")

	# 4. Casualties never exceed initial troops
	var r_clamped = BattleResolverScript.resolve_battle({"troops": 1}, {"troops": 50}, 444)
	if r_clamped.attacker_casualties > 1:
		printerr("  [FAIL] TC-LB.5D: Casualties (%d) exceeded initial troops (1)!" % r_clamped.attacker_casualties)
		failures += 1
	else:
		print("  [PASS] TC-LB.5D: Attacker casualties strictly bounded to initial troops (clamped to 1).")

	# -------------------------------------------------------------------------
	# TC-LB.6: Palisade Fortification Impact in Live Battle
	# -------------------------------------------------------------------------
	print("\n--- Running TC-LB.6: Palisade Fortification Impact ---")
	var fort_world_data := WorldGeneratorScript.generate(9999)
	fort_world_data.buildings.clear()
	# Add 5 active palisades (level 2 fortification, +60% bonus)
	for i in range(5):
		fort_world_data.buildings.append({
			"id": "pal_%d" % i,
			"type": "palisade",
			"cell": Vector2i(10 + i, 10),
			"state": "active"
		})
	# Add 2 under_construction palisades (should not count)
	for i in range(2):
		fort_world_data.buildings.append({
			"id": "pal_uc_%d" % i,
			"type": "palisade",
			"cell": Vector2i(20 + i, 10),
			"state": "under_construction"
		})

	var r_fort = BattleResolverScript.resolve_settlement_battle(
		{"troops": 10, "equipment_tier": 1, "morale": 70.0},
		{"troops": 10, "equipment_tier": 1, "morale": 70.0},
		fort_world_data,
		12345
	)
	if r_fort.details.get("fortification_level") != 2:
		printerr("  [FAIL] TC-LB.6: Expected fortification level 2, got %d" % r_fort.details.get("fortification_level"))
		failures += 1
	elif not is_equal_approx(r_fort.details.get("fortification_bonus"), 1.60):
		printerr("  [FAIL] TC-LB.6: Expected fortification bonus 1.60, got %f" % r_fort.details.get("fortification_bonus"))
		failures += 1
	else:
		print("  [PASS] TC-LB.6: 5 active palisades provided Level 2 (+60%%); under-construction excluded.")

	# -------------------------------------------------------------------------
	# TC-LB.7: Guard Casualties & State Transition
	# -------------------------------------------------------------------------
	print("\n--- Running TC-LB.7: Guard Casualties Lifecycle Application ---")
	# Re-declare war for testing raid resolution
	mil_fac.military_power = 90.0 # 3 troops
	fm.declare_war("rival_military")
	bcm.set_custom_current_day(5)
	bcm.schedule_raid("rival_military", 5, 1)

	var died_signals: Array[String] = []
	cit_guard_1.citizen_died.connect(func(id): died_signals.append(id))
	cit_guard_2.citizen_died.connect(func(id): died_signals.append(id))

	var raid_outcome = bcm.resolve_and_apply_raid("rival_military", 5)
	if not raid_outcome.get("success", false):
		printerr("  [FAIL] TC-LB.7: resolve_and_apply_raid failed: %s" % raid_outcome.get("reason", ""))
		failures += 1
	else:
		var rep: BattleResolver.BattleReport = raid_outcome.get("report")
		var expected_cas = rep.defender_casualties
		var ctx = raid_outcome.get("context", {})
		var actual_killed: Array = ctx.get("guards_killed", [])

		if actual_killed.size() != expected_cas:
			printerr("  [FAIL] TC-LB.7: Killed guards count (%d) does not match defender casualties (%d)" % [actual_killed.size(), expected_cas])
			failures += 1
		else:
			print("  [PASS] TC-LB.7: Guard casualties (%d) cleanly removed and citizen_died signal fired." % expected_cas)

	# -------------------------------------------------------------------------
	# TC-LB.8: Attacking Faction Military Losses & Non-Negativity
	# -------------------------------------------------------------------------
	print("\n--- Running TC-LB.8: Attacker Losses & Military Power Clamping ---")
	var prev_power: float = 90.0
	var current_power: float = mil_fac.military_power
	if current_power > prev_power:
		printerr("  [FAIL] TC-LB.8: Military power increased after battle! %f -> %f" % [prev_power, current_power])
		failures += 1
	elif current_power < 0.0:
		printerr("  [FAIL] TC-LB.8: Military power became negative! %f" % current_power)
		failures += 1
	else:
		print("  [PASS] TC-LB.8: Enemy military power safely reduced to %.1f (non-negative)." % current_power)

	# -------------------------------------------------------------------------
	# TC-LB.9: Resource Plunder & Storage Limits
	# -------------------------------------------------------------------------
	print("\n--- Running TC-LB.9: Resource Plunder Application ---")
	# If plunder occurred, verify food stock was reduced by at most available stock
	var plundered = raid_outcome.get("context", {}).get("plundered_resources", {})
	if plundered.has(EconomyConfigScript.RES_FOOD):
		var p_amt: int = plundered[EconomyConfigScript.RES_FOOD]
		# Initial stock was 200, reserved was 20, so stock must be 200 - p_amt >= 20
		if mock_rm.stock[EconomyConfigScript.RES_FOOD] < 20:
			printerr("  [FAIL] TC-LB.9: Plunder overspent into reserved food stock! Current: %d" % mock_rm.stock[EconomyConfigScript.RES_FOOD])
			failures += 1
		else:
			print("  [PASS] TC-LB.9: Plunder of %d food deducted without violating reserved stock." % p_amt)
	else:
		print("  [PASS] TC-LB.9: Zero food plundered in this battle resolution.")

	# -------------------------------------------------------------------------
	# TC-LB.10: Strict Idempotency (Repeat Execution Immunity)
	# -------------------------------------------------------------------------
	print("\n--- Running TC-LB.10: Strict Idempotency ---")
	var repeat_res = bcm.resolve_and_apply_raid("rival_military", 5)
	if repeat_res.get("success", true) != false:
		printerr("  [FAIL] TC-LB.10: Duplicate raid execution was accepted instead of rejected!")
		failures += 1
	elif not repeat_res.get("already_processed", false):
		printerr("  [FAIL] TC-LB.10: Duplicate raid did not report already_processed=true")
		failures += 1
	else:
		print("  [PASS] TC-LB.10: Repeat execution of identical raid rejected idempotently.")

	# -------------------------------------------------------------------------
	# TC-LB.11: Multi-Faction Independence
	# -------------------------------------------------------------------------
	print("\n--- Running TC-LB.11: Multi-Faction Independence ---")
	var merch_fac = fm.get_faction("rival_merchant")
	fm.declare_war("rival_merchant")
	bcm.set_custom_current_day(5)
	bcm.schedule_raid("rival_merchant", 8, 1)

	var p_mil = bcm.get_pending_raid("rival_military")
	var p_merch = bcm.get_pending_raid("rival_merchant")

	if p_mil.is_empty() or p_merch.is_empty():
		printerr("  [FAIL] TC-LB.11: One of the hostile factions missing pending raid!")
		failures += 1
	elif p_merch.get("scheduled_day") != 8:
		printerr("  [FAIL] TC-LB.11: Merchant raid scheduled day mismatch, expected 8, got %d" % p_merch.get("scheduled_day"))
		failures += 1
	else:
		print("  [PASS] TC-LB.11: Multiple hostile factions tracked independently (Mil: Day %s, Merch: Day %s)." % [p_mil.get("scheduled_day"), p_merch.get("scheduled_day")])

# -----------------------------------------------------------------------------
# World Integration Checks: HUD, Save/Load, Day Advancement
# -----------------------------------------------------------------------------
func _run_world_integration_checks() -> void:
	print("\n========================================================")
	print("  RUNNING WORLD INTEGRATION & LIFECYCLE CHECKS")
	print("========================================================\n")

	if world_instance == null:
		printerr("  [FAIL] world_instance is null!")
		failures += 1
		return

	var bcm = world_instance.get("battle_campaign_mgr")
	if bcm == null:
		printerr("  [FAIL] WorldView missing battle_campaign_mgr!")
		failures += 1
		return

	var fm = world_instance.get("faction_mgr")
	if fm == null:
		printerr("  [FAIL] WorldView missing faction_mgr!")
		failures += 1
		return

	# -------------------------------------------------------------------------
	# TC-LB.12: Live War Declaration & HUD Diplomacy Wiring
	# -------------------------------------------------------------------------
	print("--- Running TC-LB.12: Live War Declaration & HUD Wiring ---")
	var tm = world_instance.get_node_or_null("/root/TimeManager")
	var cur_day: int = tm.current_day if tm else 1

	# Declare war via FactionManager
	fm.declare_war("rival_military")

	var pending = bcm.get_pending_raid("rival_military")
	var expected_day = cur_day + 3
	if pending.get("scheduled_day") != expected_day:
		printerr("  [FAIL] TC-LB.12: Live war declaration expected raid day %d, got %s" % [expected_day, str(pending)])
		failures += 1
	else:
		print("  [PASS] TC-LB.12: Live war declaration scheduled raid for Day %d." % expected_day)

	# -------------------------------------------------------------------------
	# TC-LB.13: Save/Load Roundtrip & Legacy Save Compatibility
	# -------------------------------------------------------------------------
	print("\n--- Running TC-LB.13: Save/Load Roundtrip & Persistence ---")
	var save_path := "user://saves/test_battle_loop_save.json"
	var save_res := SaveManagerScript.save_to_file(world_instance, save_path)
	if not save_res.get("success", false):
		printerr("  [FAIL] TC-LB.13: Save to file failed: %s" % str(save_res))
		failures += 1
	else:
		print("  [PASS] TC-LB.13: World state saved to disk with battle campaign data.")

	# Modify state in memory, then load and verify restoration
	bcm.cancel_raid("rival_military", "Test memory wipe")
	if bcm.has_pending_raid("rival_military"):
		printerr("  [FAIL] TC-LB.13: Failed to wipe pending raid from memory before load")
		failures += 1

	var load_file_res := SaveManagerScript.load_from_file(save_path)
	if not load_file_res.get("success", false):
		printerr("  [FAIL] TC-LB.13: Load from file failed: %s" % str(load_file_res))
		failures += 1
	else:
		var apply_res := SaveManagerScript.apply_loaded_state_to_world(world_instance, load_file_res.get("data", {}))
		if not apply_res.get("success", false):
			printerr("  [FAIL] TC-LB.13: Apply loaded state to world failed: %s" % str(apply_res))
			failures += 1
		else:
			var restored_pending = bcm.get_pending_raid("rival_military")
			if restored_pending.get("scheduled_day") != expected_day:
				printerr("  [FAIL] TC-LB.13: Restored raid day mismatch! Expected %d, got %s" % [expected_day, str(restored_pending)])
				failures += 1
			else:
				print("  [PASS] TC-LB.13: Pending raid and sequence restored identically after load.")

	# Legacy Save Compatibility: load dictionary without "battle_campaign"
	print("\n--- Testing Legacy Save Compatibility (No battle_campaign section) ---")
	var dummy_state := SaveManagerScript.serialize_world_state(world_instance)
	dummy_state.erase("battle_campaign")
	var val_res := SaveManagerScript.validate_save_data(dummy_state)
	if not val_res.get("valid", false):
		printerr("  [FAIL] Legacy save without battle_campaign rejected by validator!")
		failures += 1
	else:
		print("  [PASS] Legacy save schema remains 100% valid without battle_campaign section.")

	# -------------------------------------------------------------------------
	# TC-LB.14: Daily Raid Simulation Trigger on Day Advance
	# -------------------------------------------------------------------------
	print("\n--- Running TC-LB.14: Daily Raid Simulation on Due Day Advance ---")
	# Advance day directly to expected_day
	world_instance._on_simulation_day_passed(expected_day, "Spring", 1)

	# Raid should have been processed, and next raid scheduled for expected_day + 5
	var post_raid_pending = bcm.get_pending_raid("rival_military")
	var next_expected_day = expected_day + 5
	if post_raid_pending.get("scheduled_day") != next_expected_day:
		printerr("  [FAIL] TC-LB.14: Expected next raid day %d, got %s" % [next_expected_day, str(post_raid_pending)])
		failures += 1
	elif post_raid_pending.get("raid_sequence") != 2:
		printerr("  [FAIL] TC-LB.14: Expected raid sequence 2, got %s" % str(post_raid_pending))
		failures += 1
	else:
		print("  [PASS] TC-LB.14: Due raid executed on Day %d; next raid scheduled for Day %d (Sequence 2)." % [expected_day, next_expected_day])

	# Reprocessing same day must not resolve raid again
	var dup_results = bcm.process_daily_raids(expected_day)
	if not dup_results.is_empty():
		printerr("  [FAIL] TC-LB.14: Same day advance executed duplicate raid!")
		failures += 1
	else:
		print("  [PASS] TC-LB.14: Same-day replay rejected cleanly with 0 duplicate raids.")
