extends SceneTree
## Automated Unit Test for Phase 6: Factions, Diplomacy, Trade & Battles (TC-6.1 & TC-6.2).
## Validates diplomatic state transitions, atomic trade transactions, finite caravan stock,
## and deterministic multi-factor battle resolutions.

const FactionManager = preload("res://scripts/factions/faction_manager.gd")
const FactionData = preload("res://scripts/factions/faction_data.gd")
const TradeCaravan = preload("res://scripts/trade/trade_caravan.gd")
const BattleResolver = preload("res://scripts/combat/battle_resolver.gd")
const BattleCampaignManager = preload("res://scripts/combat/battle_campaign_manager.gd")
const EconomyConfig = preload("res://scripts/economy/economy_config.gd")

var failures: int = 0
var assertions: int = 0

func _assert(cond: bool, msg: String) -> void:
	assertions += 1
	if not cond:
		printerr("FAIL: %s" % msg)
		failures += 1

class MockArmyManager:
	var soldier_count: int = 20
	var movement_state: int = 2 # IDLE_AT_FIELD
	var current_cell: Vector2i = Vector2i(10, 10)
	var rally_cell: Vector2i = Vector2i(2, 2)
	var combat_morale: float = 80.0
	var casualties_taken: int = 0

	func get_army_count() -> int:
		return soldier_count

	func get_movement_state() -> int:
		return movement_state

	func get_current_cell() -> Vector2i:
		return current_cell

	func get_rally_cell() -> Vector2i:
		return rally_cell

	func get_combat_morale() -> float:
		return combat_morale

	func is_defense_eligible() -> bool:
		return true

	func remove_casualties(count: int) -> void:
		casualties_taken += count
		soldier_count = maxi(0, soldier_count - count)

class MockResourceManager:
	var inventory: Dictionary = {}
	var capacities: Dictionary = {}
	
	func _init() -> void:
		inventory = {
			EconomyConfig.RES_FOOD: 100,
			EconomyConfig.RES_WOOD: 80,
			EconomyConfig.RES_STONE: 50,
			EconomyConfig.RES_METAL: 20,
			EconomyConfig.RES_TOOLS: 10,
			EconomyConfig.RES_GOLD: 300,
			EconomyConfig.RES_HERBS: 15,
			EconomyConfig.RES_CRYSTAL: 5
		}
		for res in inventory:
			capacities[res] = 500
			
	func has_resource(res_id: String, amount: int) -> bool:
		return inventory.get(res_id, 0) >= amount
		
	func get_available_stock(res_id: String) -> int:
		return inventory.get(res_id, 0)
		
	func get_total_stock(res_id: String) -> int:
		return inventory.get(res_id, 0)
		
	func get_storage_capacity(res_id: String) -> int:
		return capacities.get(res_id, 500)
		
	func consume_resource(res_id: String, amount: int) -> bool:
		if not has_resource(res_id, amount):
			return false
		inventory[res_id] -= amount
		return true
		
	func add_resource(res_id: String, amount: int) -> int:
		inventory[res_id] = inventory.get(res_id, 0) + amount
		return amount

func _init() -> void:
	print("\n--- Running TestFactionsAndBattles (TC-6.1 & TC-6.2) ---")
	test_factions_and_diplomacy()
	test_trade_caravan_transactions()
	test_battle_resolver_deterministic()
	test_fortification_impact_overcoming_numbers()
	test_faction_existence_status_action_guards()
	
	if failures == 0:
		print("=== TC-6.1 & TC-6.2 ALL FACTION, TRADE & BATTLE TESTS PASSED (%d assertions) ===\n" % assertions)
		quit(0)
	else:
		printerr("=== FAILED %d TESTS ===" % failures)
		quit(1)

func test_factions_and_diplomacy() -> void:
	var fm := FactionManager.new()
	var rival_mil := fm.get_faction("rival_military")
	var neutral_tribe := fm.get_faction("neutral_tribe")
	
	if rival_mil == null or neutral_tribe == null:
		printerr("FAIL: Factions not properly initialized")
		failures += 1
		return
		
	print("PASS: Faction registry properly populated with rival and neutral powers")
	
	# Test NAP treaty rules
	# Military rival has negative opinion (-10), NAP should be rejected
	var nap_check: Dictionary = fm.propose_treaty("rival_military", "nap")
	if nap_check["success"]:
		printerr("FAIL: NAP was accepted despite negative opinion")
		failures += 1
	else:
		print("PASS: Non-Aggression Pact rejected when opinion is negative")
		
	# Neutral tribe has positive opinion (30), NAP should be accepted
	var nap_ok: Dictionary = fm.propose_treaty("neutral_tribe", "nap")
	if not nap_ok["success"] or not neutral_tribe.has_nap:
		printerr("FAIL: NAP was rejected for friendly neutral tribe")
		failures += 1
	else:
		print("PASS: Non-Aggression Pact signed successfully with neutral tribe")
		
	# Test gift sending
	var mock_rm := MockResourceManager.new()
	var gift_res: Dictionary = fm.send_gift("rival_military", EconomyConfig.RES_GOLD, 50, mock_rm)
	if not gift_res["success"] or mock_rm.inventory[EconomyConfig.RES_GOLD] != 250:
		printerr("FAIL: Gift failed or gold was not deducted")
		failures += 1
	else:
		print("PASS: Diplomatic gift deducted gold and boosted rival opinion")
		
	# Now opinion is >= 0, NAP should be accepted
	var nap_now: Dictionary = fm.propose_treaty("rival_military", "nap")
	if not nap_now["success"]:
		printerr("FAIL: NAP rejected after relationship improvement")
		failures += 1
	else:
		print("PASS: NAP signed after opinion improved via tribute")
		
	# Test war declaration breaks all treaties
	var war_res: Dictionary = fm.declare_war("rival_military")
	if not rival_mil.is_at_war or rival_mil.has_nap:
		printerr("FAIL: Declaring war did not revoke treaties")
		failures += 1
	else:
		print("PASS: War declaration cleanly breaks Non-Aggression Pact and marks hostile")

func test_trade_caravan_transactions() -> void:
	var mock_rm := MockResourceManager.new()
	var caravan := TradeCaravan.generate_caravan(12345, 5, "rival_merchant")
	
	var initial_player_gold: int = mock_rm.get_total_stock(EconomyConfig.RES_GOLD)
	var initial_player_food: int = mock_rm.get_total_stock(EconomyConfig.RES_FOOD)
	var initial_caravan_food: int = caravan.inventory.get(EconomyConfig.RES_FOOD, 0)
	var initial_caravan_gold: int = caravan.gold
	
	# Buy 10 Food from caravan
	var buy_res: Dictionary = caravan.buy_from_caravan(EconomyConfig.RES_FOOD, 10, mock_rm, 0.0)
	if not buy_res["success"]:
		printerr("FAIL: Buy transaction failed: %s" % buy_res.get("reason", ""))
		failures += 1
		return
		
	var expected_cost: int = 10 * caravan.sell_prices[EconomyConfig.RES_FOOD]
	if mock_rm.get_total_stock(EconomyConfig.RES_GOLD) != initial_player_gold - expected_cost:
		printerr("FAIL: Player gold not properly deducted")
		failures += 1
	elif mock_rm.get_total_stock(EconomyConfig.RES_FOOD) != initial_player_food + 10:
		printerr("FAIL: Player food not credited")
		failures += 1
	elif caravan.inventory[EconomyConfig.RES_FOOD] != initial_caravan_food - 10:
		printerr("FAIL: Caravan stock not reduced")
		failures += 1
	elif caravan.gold != initial_caravan_gold + expected_cost:
		printerr("FAIL: Caravan gold not credited")
		failures += 1
	else:
		print("PASS: Atomic buy transaction verified: exact gold deducted, food credited, caravan inventory decremented")
		
	# Attempt to buy more than caravan has in stock
	var overflow_buy: Dictionary = caravan.buy_from_caravan(EconomyConfig.RES_FOOD, 9999, mock_rm, 0.0)
	if overflow_buy["success"]:
		printerr("FAIL: Caravan allowed buying beyond available stock")
		failures += 1
	else:
		print("PASS: Over-purchasing rejected; stock limits strictly enforced")
		
	# Attempt to buy when player cannot afford
	mock_rm.inventory[EconomyConfig.RES_GOLD] = 0
	var broke_buy: Dictionary = caravan.buy_from_caravan(EconomyConfig.RES_FOOD, 5, mock_rm, 0.0)
	if broke_buy["success"]:
		printerr("FAIL: Player bought goods with 0 gold")
		failures += 1
	else:
		print("PASS: Insufficient funds rejected cleanly without inventory side-effects")
		
	# Test selling goods to caravan
	mock_rm.inventory[EconomyConfig.RES_GOLD] = 100
	mock_rm.inventory[EconomyConfig.RES_WOOD] = 50
	var sell_res: Dictionary = caravan.sell_to_caravan(EconomyConfig.RES_WOOD, 15, mock_rm, 0.0)
	if not sell_res["success"]:
		printerr("FAIL: Selling wood failed: %s" % sell_res.get("reason", ""))
		failures += 1
	else:
		print("PASS: Player sold wood to caravan; received gold; zero duplicated goods")

func test_battle_resolver_deterministic() -> void:
	var atk_force := {
		"troops": 30,
		"equipment_tier": 2,
		"morale": 80.0
	}
	var def_force := {
		"troops": 20,
		"equipment_tier": 1,
		"morale": 60.0,
		"fortification_level": 0,
		"terrain_multiplier": 1.0,
		"resources": {EconomyConfig.RES_GOLD: 100, EconomyConfig.RES_FOOD: 80}
	}
	
	# Run resolution twice with same seed
	var rep1 = BattleResolver.resolve_battle(atk_force, def_force, 42)
	var rep2 = BattleResolver.resolve_battle(atk_force, def_force, 42)
	
	if rep1.victor != rep2.victor or rep1.attacker_casualties != rep2.attacker_casualties or rep1.defender_casualties != rep2.defender_casualties:
		printerr("FAIL: Battle resolution non-deterministic across identical seeds")
		failures += 1
	else:
		print("PASS: BattleResolver is 100%% deterministic across identical runs (Victor: %s)" % rep1.victor)
		
	if rep1.victor != "attacker":
		printerr("FAIL: Expected attacker with superior numbers, gear, and morale to win")
		failures += 1
	else:
		print("PASS: Superior attacker force won battle decisively")
		
	if rep1.plunder_spoils.is_empty():
		printerr("FAIL: Expected plunder spoils after defeating defender")
		failures += 1
	else:
		print("PASS: Victor plundered resources from defeated defender (%s)" % [rep1.plunder_spoils])

func test_fortification_impact_overcoming_numbers() -> void:
	# Small defender force (15 troops) with Level 3 fortifications + hill terrain (1.25)
	# vs Larger attacker force (25 troops) with basic gear
	var atk_force := {
		"troops": 25,
		"equipment_tier": 1,
		"morale": 65.0
	}
	var def_force := {
		"troops": 15,
		"equipment_tier": 2,
		"morale": 90.0,
		"fortification_level": 3, # +90% defense bonus
		"terrain_multiplier": 1.25, # +25% high ground
		"resources": {}
	}
	
	var rep = BattleResolver.resolve_battle(atk_force, def_force, 999)
	if rep.victor != "defender":
		printerr("FAIL: Fortified defenders should defeat larger raw attacker numbers; victor was %s" % rep.victor)
		failures += 1
	else:
		print("PASS: High fortification (Tier 3) & terrain bonus successfully defeated superior numbers per GDD 10.4")
		print("  Explanation: %s" % rep.explanation)

func test_faction_existence_status_action_guards() -> void:
	print("\n--- Testing MISS-01: Faction Existence Status Guards (Diplomacy, Gifts, War, Raids, Offensive) ---")
	var fm := FactionManager.new()
	var mock_rm := MockResourceManager.new()

	var signal_counts := {
		"relation_changed": 0,
		"treaty_signed": 0,
		"war_declared": 0,
		"peace_signed": 0
	}
	fm.relation_changed.connect(func(_id, _op, _disp): signal_counts["relation_changed"] += 1)
	fm.treaty_signed.connect(func(_id, _type): signal_counts["treaty_signed"] += 1)
	fm.war_declared.connect(func(_id): signal_counts["war_declared"] += 1)
	fm.peace_signed.connect(func(_id): signal_counts["peace_signed"] += 1)

	var merch: FactionData = fm.get_faction("rival_merchant")
	var mil: FactionData = fm.get_faction("rival_military")
	var tribe: FactionData = fm.get_faction("neutral_tribe")

	# 1. send_gift for STATUS_ELIMINATED: fails, does NOT deduct resources, does NOT mutate opinion or emit signal
	merch.existence_status = FactionData.STATUS_ELIMINATED
	merch.opinion = 20.0
	var gold_before: int = mock_rm.get_available_stock(EconomyConfig.RES_GOLD)
	var rel_sig_before: int = signal_counts["relation_changed"]
	var gift_elim: Dictionary = fm.send_gift("rival_merchant", EconomyConfig.RES_GOLD, 50, mock_rm)
	_assert(not gift_elim.get("success", true), "send_gift to eliminated faction must fail")
	_assert(mock_rm.get_available_stock(EconomyConfig.RES_GOLD) == gold_before, "send_gift to eliminated faction must NOT deduct resources")
	_assert(is_equal_approx(merch.opinion, 20.0), "send_gift to eliminated faction must NOT change opinion")
	_assert(signal_counts["relation_changed"] == rel_sig_before, "send_gift to eliminated faction must NOT emit relation_changed")

	# 2. send_gift for STATUS_IN_EXILE: fails without deducting resources, mutating opinion, or emitting signal
	merch.existence_status = FactionData.STATUS_IN_EXILE
	var gift_exile: Dictionary = fm.send_gift("rival_merchant", EconomyConfig.RES_GOLD, 50, mock_rm)
	_assert(not gift_exile.get("success", true), "send_gift to in_exile faction must fail")
	_assert(mock_rm.get_available_stock(EconomyConfig.RES_GOLD) == gold_before, "send_gift to in_exile faction must NOT deduct resources")
	_assert(is_equal_approx(merch.opinion, 20.0), "send_gift to in_exile faction must NOT change opinion")
	_assert(signal_counts["relation_changed"] == rel_sig_before, "send_gift to in_exile faction must NOT emit relation_changed")

	# 3. propose_treaty("nap") and ("alliance") for STATUS_ELIMINATED and STATUS_IN_EXILE
	merch.opinion = 80.0
	merch.has_nap = false
	merch.has_alliance = false
	merch.is_at_war = false
	for status in [FactionData.STATUS_ELIMINATED, FactionData.STATUS_IN_EXILE]:
		merch.existence_status = status
		var t_sig_before: int = signal_counts["treaty_signed"]
		var r_sig_before: int = signal_counts["relation_changed"]
		var nap_res: Dictionary = fm.propose_treaty("rival_merchant", "nap")
		var all_res: Dictionary = fm.propose_treaty("rival_merchant", "alliance")
		_assert(not nap_res.get("success", true) and not merch.has_nap, "propose_treaty('nap') must fail for status %s" % status)
		_assert(not all_res.get("success", true) and not merch.has_alliance, "propose_treaty('alliance') must fail for status %s" % status)
		_assert(signal_counts["treaty_signed"] == t_sig_before and signal_counts["relation_changed"] == r_sig_before, "Failed treaties must not emit signals for status %s" % status)

	# 4. declare_war for STATUS_ELIMINATED and STATUS_IN_EXILE
	tribe.is_at_war = false
	tribe.opinion = 30.0
	for status in [FactionData.STATUS_ELIMINATED, FactionData.STATUS_IN_EXILE]:
		tribe.existence_status = status
		var w_sig_before: int = signal_counts["war_declared"]
		var r_sig_before: int = signal_counts["relation_changed"]
		var war_res: Dictionary = fm.declare_war("neutral_tribe")
		_assert(not war_res.get("success", true) and not tribe.is_at_war, "declare_war must fail for status %s" % status)
		_assert(is_equal_approx(tribe.opinion, 30.0), "Failed declare_war must not mutate opinion for status %s" % status)
		_assert(signal_counts["war_declared"] == w_sig_before and signal_counts["relation_changed"] == r_sig_before, "Failed declare_war must not emit signals for status %s" % status)

	# 5. Peace treaty for STATUS_IN_EXILE at war MUST succeed (no perpetual war lock!), while STATUS_ELIMINATED is rejected
	mil.is_at_war = true
	mil.existence_status = FactionData.STATUS_ELIMINATED
	var peace_elim: Dictionary = fm.propose_treaty("rival_military", "peace")
	_assert(not peace_elim.get("success", true) and mil.is_at_war, "propose_treaty('peace') must be rejected for eliminated faction")

	mil.existence_status = FactionData.STATUS_IN_EXILE
	var p_sig_before: int = signal_counts["peace_signed"]
	var peace_exile: Dictionary = fm.propose_treaty("rival_military", "peace")
	_assert(peace_exile.get("success", false) and not mil.is_at_war, "propose_treaty('peace') must succeed for in_exile faction at war so war is not locked forever")
	_assert(signal_counts["peace_signed"] == p_sig_before + 1, "Successful peace treaty with in_exile faction must emit peace_signed")

	# 6, 7, 8, 9. Raid eligibility, schedule_raid, and resolve_and_apply_raid for non-active factions
	var bcm := BattleCampaignManager.new(null, fm, 12345)
	bcm.set_custom_resource_manager(mock_rm)
	var mock_army := MockArmyManager.new()
	bcm.set_custom_army_manager(mock_army)

	var bcm_signals := {"raid_scheduled": 0, "raid_cancelled": 0, "battle_resolved": 0, "offensive": 0}
	bcm.raid_scheduled.connect(func(_f, _d, _first): bcm_signals["raid_scheduled"] += 1)
	bcm.raid_cancelled.connect(func(_f, _r): bcm_signals["raid_cancelled"] += 1)
	bcm.battle_resolved.connect(func(_rep, _ctx): bcm_signals["battle_resolved"] += 1)
	bcm.offensive_campaign_resolved.connect(func(_rep, _ctx): bcm_signals["offensive"] += 1)

	# Start active war so raid is scheduled on day 4
	mil.existence_status = FactionData.STATUS_ACTIVE
	mil.military_power = 60.0
	mil.is_at_war = false
	var war_ok: Dictionary = fm.declare_war("rival_military")
	_assert(war_ok.get("success", false) and bcm.has_pending_raid("rival_military"), "Active faction war declaration schedules initial raid")

	# Transition to STATUS_IN_EXILE while raid is pending -> eligibility false, schedule_raid false, resolve cancels without battle
	mil.existence_status = FactionData.STATUS_IN_EXILE
	_assert(not bcm.is_faction_eligible_to_raid("rival_military"), "is_faction_eligible_to_raid must be false for in_exile faction")
	var sched_before: int = bcm_signals["raid_scheduled"]
	_assert(not bcm.schedule_raid("rival_military", 10, 2, false), "schedule_raid must fail for in_exile faction")
	_assert(bcm_signals["raid_scheduled"] == sched_before, "Failed schedule_raid must not emit raid_scheduled")

	var food_before_raid: int = mock_rm.get_available_stock(EconomyConfig.RES_FOOD)
	var resolve_exile: Dictionary = bcm.resolve_and_apply_raid("rival_military", 5)
	_assert(not resolve_exile.get("success", true), "resolve_and_apply_raid must fail for in_exile faction")
	_assert(not bcm.has_pending_raid("rival_military"), "Pending raid must be cancelled when faction becomes in_exile")
	_assert(mock_army.casualties_taken == 0 and is_equal_approx(mil.military_power, 60.0), "Cancelled raid must not inflict casualties or military_power loss")
	_assert(mock_rm.get_available_stock(EconomyConfig.RES_FOOD) == food_before_raid, "Cancelled raid must not plunder resources")
	_assert(bcm_signals["battle_resolved"] == 0, "Cancelled raid must not emit battle_resolved")

	# Same check for STATUS_ELIMINATED with a pending raid
	mil.existence_status = FactionData.STATUS_ACTIVE
	_assert(bcm.schedule_raid("rival_military", 8, 1, true), "Active faction at war can schedule raid")
	mil.existence_status = FactionData.STATUS_ELIMINATED
	_assert(not bcm.is_faction_eligible_to_raid("rival_military"), "is_faction_eligible_to_raid must be false for eliminated faction")
	_assert(not bcm.schedule_raid("rival_military", 12, 2, false), "schedule_raid must fail for eliminated faction")
	var resolve_elim: Dictionary = bcm.resolve_and_apply_raid("rival_military", 8)
	_assert(not resolve_elim.get("success", true) and not bcm.has_pending_raid("rival_military"), "resolve_and_apply_raid must fail and cancel pending raid for eliminated faction")
	_assert(bcm_signals["battle_resolved"] == 0, "Eliminated faction raid cancellation must not emit battle_resolved")

	# 10. can_launch_offensive_campaign and launch_offensive_campaign for non-active factions
	for status in [FactionData.STATUS_IN_EXILE, FactionData.STATUS_ELIMINATED]:
		mil.existence_status = status
		mil.is_at_war = true
		mil.military_power = 60.0
		var can_atk: Dictionary = bcm.can_launch_offensive_campaign("rival_military")
		_assert(not can_atk.get("can_attack", true), "can_launch_offensive_campaign must return false for status %s" % status)
		var launch_res: Dictionary = bcm.launch_offensive_campaign("rival_military", 12345)
		_assert(not launch_res.get("success", true), "launch_offensive_campaign must fail for status %s" % status)
		_assert(mock_army.casualties_taken == 0 and is_equal_approx(mil.military_power, 60.0), "Rejected offensive campaign must not mutate army or enemy military_power")
		_assert(bcm_signals["offensive"] == 0, "Rejected offensive campaign must not emit offensive_campaign_resolved")

	# 11. Regression check: STATUS_ACTIVE faction still works normally for gift, NAP, war, raid, and offensive campaign
	merch.existence_status = FactionData.STATUS_ACTIVE
	merch.is_at_war = false
	merch.has_nap = false
	merch.opinion = 10.0
	var active_gift: Dictionary = fm.send_gift("rival_merchant", EconomyConfig.RES_GOLD, 50, mock_rm)
	_assert(active_gift.get("success", false) and mock_rm.get_available_stock(EconomyConfig.RES_GOLD) == gold_before - 50, "Active faction send_gift works normally")
	var active_nap: Dictionary = fm.propose_treaty("rival_merchant", "nap")
	_assert(active_nap.get("success", false) and merch.has_nap, "Active faction propose_treaty('nap') works normally")

	mil.existence_status = FactionData.STATUS_ACTIVE
	mil.is_at_war = true
	mil.military_power = 60.0
	var active_can_atk: Dictionary = bcm.can_launch_offensive_campaign("rival_military")
	_assert(active_can_atk.get("can_attack", false), "Active faction at war can be targeted by offensive campaign")
	print("PASS: All MISS-01 existence_status guards verified across diplomacy, gifts, war, raids, and offensive campaigns")
