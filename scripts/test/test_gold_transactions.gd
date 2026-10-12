extends SceneTree

const FactionManagerScript = preload("res://scripts/factions/faction_manager.gd")
const TradeCaravanScript = preload("res://scripts/trade/trade_caravan.gd")
const RMScript = preload("res://scripts/economy/resource_manager.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")

func _init() -> void:
	print("\n========================================================")
	print("  FUNCTIONAL QA TEST: Gold Transactions, Trade & Gifting")
	print("========================================================")
	
	var passed := 0
	var failed := 0
	
	# Instantiate a real ResourceManager
	var rm = RMScript.new()
	rm._ready()
	
	# TC-G.1: Verify ResourceManager API Contract
	print("\n--- TC-G.1: ResourceManager Contract Validation ---")
	if not rm.has_method("has_resource"):
		printerr("  [FAIL] rm.has_resource does not exist")
		failed += 1
	elif not rm.has_method("get_storage_capacity"):
		printerr("  [FAIL] rm.get_storage_capacity does not exist")
		failed += 1
	else:
		print("  [PASS] rm.has_resource and rm.get_storage_capacity methods exist.")
		passed += 1
		
	# TC-G.2: Gold Purchasing - Sufficient Gold
	print("\n--- TC-G.2: Gold Purchasing - Sufficient Gold ---")
	var initial_gold: int = rm.get_available_stock("gold")
	var initial_food: int = rm.get_available_stock("food")
	var caravan = TradeCaravanScript.generate_caravan(12345, 3, "rival_merchant")
	var food_price: int = caravan.get_effective_sell_price("food", 0.0)
	var expected_cost: int = food_price * 10
	var buy_res: Dictionary = caravan.buy_from_caravan("food", 10, rm, 0.0)
	if not buy_res.get("success", false):
		printerr("  [FAIL] buy_from_caravan failed: %s" % buy_res.get("reason", ""))
		failed += 1
	elif rm.get_available_stock("gold") != initial_gold - expected_cost:
		printerr("  [FAIL] Gold not properly deducted: expected %d, got %d" % [initial_gold - expected_cost, rm.get_available_stock("gold")])
		failed += 1
	elif rm.get_available_stock("food") != initial_food + 10:
		printerr("  [FAIL] Food not credited: expected %d, got %d" % [initial_food + 10, rm.get_available_stock("food")])
		failed += 1
	else:
		print("  [PASS] Successfully bought 10 food for %d gold. Balances: Gold=%d, Food=%d" % [expected_cost, rm.get_available_stock("gold"), rm.get_available_stock("food")])
		passed += 1

	# TC-G.3: Gold Purchasing - Insufficient & Zero Gold
	print("\n--- TC-G.3: Gold Purchasing - Insufficient & Zero Gold ---")
	# Drain gold to 5
	var cur_gold = rm.get_available_stock("gold")
	rm.consume_resource("gold", cur_gold - 5)
	assert(rm.get_available_stock("gold") == 5)
	
	# Attempt to buy 10 food (costs 20 gold, player only has 5)
	var broke_buy: Dictionary = caravan.buy_from_caravan("food", 10, rm, 0.0)
	if broke_buy.get("success", false):
		printerr("  [FAIL] Purchase succeeded despite insufficient gold!")
		failed += 1
	elif rm.get_available_stock("gold") != 5:
		printerr("  [FAIL] Partial gold deduction occurred! Gold=%d" % rm.get_available_stock("gold"))
		failed += 1
	else:
		print("  [PASS] Purchase rejected cleanly on insufficient gold: '%s'" % broke_buy.get("reason", ""))
		passed += 1
		
	# Drain to zero
	rm.consume_resource("gold", 5)
	assert(rm.get_available_stock("gold") == 0)
	var zero_buy: Dictionary = caravan.buy_from_caravan("food", 10, rm, 0.0)
	if zero_buy.get("success", false):
		printerr("  [FAIL] Purchase succeeded with 0 gold!")
		failed += 1
	else:
		print("  [PASS] Purchase rejected cleanly with 0 gold.")
		passed += 1

	# TC-G.4: Diplomatic Gold Gifting - Sufficient Gold
	print("\n--- TC-G.4: Diplomatic Gold Gifting - Sufficient Gold ---")
	rm.add_resource("gold", 100) # give player 100 gold
	var fm = FactionManagerScript.new()
	var rival_mil = fm.get_faction("rival_military")
	var initial_opinion: float = rival_mil.opinion
	
	var gift_res: Dictionary = fm.send_gift("rival_military", EconomyConfigScript.RES_GOLD, 50, rm)
	if not gift_res.get("success", false):
		printerr("  [FAIL] send_gift failed: %s" % gift_res.get("reason", ""))
		failed += 1
	elif rm.get_available_stock("gold") != 50:
		printerr("  [FAIL] Gold not properly deducted after gift: expected 50, got %d" % rm.get_available_stock("gold"))
		failed += 1
	elif rival_mil.opinion <= initial_opinion:
		printerr("  [FAIL] Faction opinion did not increase! (old=%.1f, new=%.1f)" % [initial_opinion, rival_mil.opinion])
		failed += 1
	else:
		print("  [PASS] Gift of 50 gold succeeded: Gold deducted to 50, Opinion boosted from %.1f to %.1f (+%.1f)" % [
			initial_opinion, rival_mil.opinion, gift_res.get("opinion_gain", 0.0)
		])
		passed += 1

	# TC-G.5: Diplomatic Gold Gifting - Insufficient Gold
	print("\n--- TC-G.5: Diplomatic Gold Gifting - Insufficient Gold ---")
	# Player only has 50 gold, try to gift 100 gold
	var broke_gift: Dictionary = fm.send_gift("rival_military", EconomyConfigScript.RES_GOLD, 100, rm)
	if broke_gift.get("success", false):
		printerr("  [FAIL] Gift succeeded despite insufficient gold!")
		failed += 1
	elif rm.get_available_stock("gold") != 50:
		printerr("  [FAIL] Partial gold deduction occurred! Gold=%d" % rm.get_available_stock("gold"))
		failed += 1
	else:
		print("  [PASS] Gift rejected cleanly on insufficient gold: '%s'" % broke_gift.get("reason", ""))
		passed += 1

	# TC-G.6: Diplomatic Gold Gifting - Invalid Target
	print("\n--- TC-G.6: Diplomatic Gold Gifting - Invalid Target ---")
	var invalid_gift: Dictionary = fm.send_gift("nonexistent_kingdom", EconomyConfigScript.RES_GOLD, 50, rm)
	if invalid_gift.get("success", false):
		printerr("  [FAIL] Gift succeeded with nonexistent target!")
		failed += 1
	else:
		print("  [PASS] Gift rejected cleanly for nonexistent faction.")
		passed += 1

	# TC-G.7: Selling Resources to Caravan for Gold
	print("\n--- TC-G.7: Selling Resources to Caravan for Gold ---")
	rm.add_resource("wood", 50)
	var wood_before: int = rm.get_available_stock("wood")
	var gold_before: int = rm.get_available_stock("gold")
	var caravan_gold_before: int = caravan.gold
	var sell_unit_price: int = caravan.get_effective_buy_price("wood", 0.0)
	var expected_payout: int = sell_unit_price * 10
	
	var sell_res: Dictionary = caravan.sell_to_caravan("wood", 10, rm, 0.0)
	if not sell_res.get("success", false):
		printerr("  [FAIL] sell_to_caravan failed: %s" % sell_res.get("reason", ""))
		failed += 1
	elif rm.get_available_stock("wood") != wood_before - 10:
		printerr("  [FAIL] Wood not deducted: expected %d, got %d" % [wood_before - 10, rm.get_available_stock("wood")])
		failed += 1
	elif rm.get_available_stock("gold") != gold_before + expected_payout:
		printerr("  [FAIL] Gold payout not credited: expected %d, got %d" % [gold_before + expected_payout, rm.get_available_stock("gold")])
		failed += 1
	elif caravan.gold != caravan_gold_before - expected_payout:
		printerr("  [FAIL] Caravan gold not deducted: expected %d, got %d" % [caravan_gold_before - expected_payout, caravan.gold])
		failed += 1
	else:
		print("  [PASS] Sold 10 wood for %d gold. Player gold: %d -> %d. Caravan gold: %d -> %d" % [
			expected_payout, gold_before, rm.get_available_stock("gold"), caravan_gold_before, caravan.gold
		])
		passed += 1

	# TC-G.8: Rapid Repeated Transactions & Atomic Safety
	print("\n--- TC-G.8: Rapid Repeated Transactions & Exact Depletion ---")
	# Player has some gold; buy until depleted
	var current_gold: int = rm.get_available_stock("gold")
	var transactions := 0
	while rm.get_available_stock("gold") >= food_price * 5 and caravan.inventory.get("food", 0) >= 5:
		var r = caravan.buy_from_caravan("food", 5, rm, 0.0)
		if r.get("success", false):
			transactions += 1
		else:
			break
	print("  [PASS] Executed %d consecutive rapid purchases until depletion. Remaining gold: %d" % [transactions, rm.get_available_stock("gold")])
	passed += 1

	print("\n--------------------------------------------------------")
	print("  RESULTS: %d PASSED, %d FAILED" % [passed, failed])
	print("--------------------------------------------------------\n")
	
	if failed == 0:
		print("ALL GOLD TRANSACTION TESTS PASSED SUCCESSFULLY! (Exit Code 0)")
		quit(0)
	else:
		printerr("GOLD TRANSACTION TESTS FAILED!")
		quit(1)
