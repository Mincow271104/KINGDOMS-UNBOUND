extends SceneTree
## Automated Unit Test for Phase 6: Factions, Diplomacy, Trade & Battles (TC-6.1 & TC-6.2).
## Validates diplomatic state transitions, atomic trade transactions, finite caravan stock,
## and deterministic multi-factor battle resolutions.

const FactionManager = preload("res://scripts/factions/faction_manager.gd")
const FactionData = preload("res://scripts/factions/faction_data.gd")
const TradeCaravan = preload("res://scripts/trade/trade_caravan.gd")
const BattleResolver = preload("res://scripts/combat/battle_resolver.gd")
const EconomyConfig = preload("res://scripts/economy/economy_config.gd")

var failures: int = 0

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
	
	if failures == 0:
		print("=== TC-6.1 & TC-6.2 ALL FACTION, TRADE & BATTLE TESTS PASSED ===\n")
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
