class_name TradeCaravan
extends RefCounted
## Trade Caravan & Merchant System for KINGDOMS UNBOUND.
## Conforms to GDD Section 11:
## Finite goods, distinct buy/sell prices, opinion discounts, and atomic exchange transactions.

const EconomyConfig = preload("res://scripts/economy/economy_config.gd")

var caravan_id: String
var name: String
var origin_faction_id: String
var arrival_day: int
var departure_day: int
var is_active: bool = true

var inventory: Dictionary = {} # res_id -> int
var gold: int = 350
var sell_prices: Dictionary = {} # res_id -> unit cost for player to BUY
var buy_prices: Dictionary = {}  # res_id -> unit price caravan PAYS player to SELL

func _init(p_id: String = "", p_name: String = "", p_origin: String = "rival_merchant") -> void:
	caravan_id = p_id
	name = p_name
	origin_faction_id = p_origin

static func generate_caravan(seed_val: int, day: int, origin_faction: String = "rival_merchant") -> RefCounted:
	var script = load("res://scripts/trade/trade_caravan.gd")
	var c = script.new("caravan_%d" % day, "Đoàn Buôn Phương Nam (Ngày %d)" % day, origin_faction)
	c.arrival_day = day
	c.departure_day = day + 2 # Stays 2 days
	c.is_active = true
	
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + day * 555
	
	# Finite stock
	c.inventory = {
		EconomyConfig.RES_FOOD: rng.randi_range(30, 60),
		EconomyConfig.RES_WOOD: rng.randi_range(20, 50),
		EconomyConfig.RES_STONE: rng.randi_range(15, 30),
		EconomyConfig.RES_METAL: rng.randi_range(10, 25),
		EconomyConfig.RES_TOOLS: rng.randi_range(5, 15),
		EconomyConfig.RES_HERBS: rng.randi_range(10, 25),
		EconomyConfig.RES_CRYSTAL: rng.randi_range(2, 6)
	}
	c.gold = rng.randi_range(300, 600)
	
	# Asymmetric prices per GDD 11.1 (Sell price > Buy price)
	c.sell_prices = {
		EconomyConfig.RES_FOOD: 2,
		EconomyConfig.RES_WOOD: 3,
		EconomyConfig.RES_STONE: 4,
		EconomyConfig.RES_METAL: 8,
		EconomyConfig.RES_TOOLS: 15,
		EconomyConfig.RES_HERBS: 6,
		EconomyConfig.RES_CRYSTAL: 35
	}
	c.buy_prices = {
		EconomyConfig.RES_FOOD: 1,
		EconomyConfig.RES_WOOD: 2,
		EconomyConfig.RES_STONE: 2,
		EconomyConfig.RES_METAL: 5,
		EconomyConfig.RES_TOOLS: 10,
		EconomyConfig.RES_HERBS: 4,
		EconomyConfig.RES_CRYSTAL: 22
	}
	return c

func get_effective_sell_price(res_id: String, faction_opinion: float = 0.0) -> int:
	var base: int = sell_prices.get(res_id, 10)
	# Faction opinion discount: up to -20% discount if high opinion
	var mult := 1.0 - clampf(faction_opinion / 500.0, -0.2, 0.2)
	return maxi(1, int(round(base * mult)))

func get_effective_buy_price(res_id: String, faction_opinion: float = 0.0) -> int:
	var base: int = buy_prices.get(res_id, 5)
	# Faction opinion premium: up to +20% higher sale price if high opinion
	var mult := 1.0 + clampf(faction_opinion / 500.0, -0.2, 0.2)
	return maxi(1, int(round(base * mult)))

## Player BUYS goods from caravan (pays Gold, receives item)
func buy_from_caravan(
	item_id: String,
	amount: int,
	resource_mgr: Object,
	faction_opinion: float = 0.0
) -> Dictionary:
	if not is_active:
		return {"success": false, "reason": "Thương đoàn đã rời đi"}
	if amount <= 0:
		return {"success": false, "reason": "Số lượng mua không hợp lệ"}
	if not inventory.has(item_id) or inventory[item_id] < amount:
		return {"success": false, "reason": "Thương đoàn không còn đủ hàng (còn %d)" % inventory.get(item_id, 0)}
		
	var unit_price := get_effective_sell_price(item_id, faction_opinion)
	var total_cost := unit_price * amount
	
	if resource_mgr != null:
		if not resource_mgr.has_resource(EconomyConfig.RES_GOLD, total_cost):
			return {"success": false, "reason": "Không đủ vàng trong ngân khố (cần %d vàng)" % total_cost}
			
		# Check destination storage capacity
		var cur_total: int = resource_mgr.get_total_stock(item_id)
		var max_cap: int = resource_mgr.get_storage_capacity(item_id)
		if cur_total + amount > max_cap:
			return {"success": false, "reason": "Sức chứa kho hàng không đủ (còn trống %d)" % (max_cap - cur_total)}
			
		# Atomic execution
		resource_mgr.call("consume_resource", EconomyConfig.RES_GOLD, total_cost)
		resource_mgr.call("add_resource", item_id, amount)
		
	inventory[item_id] -= amount
	gold += total_cost
	
	return {
		"success": true,
		"item_id": item_id,
		"amount": amount,
		"total_cost": total_cost,
		"remaining_stock": inventory[item_id]
	}

## Player SELLS goods to caravan (delivers item, receives Gold)
func sell_to_caravan(
	item_id: String,
	amount: int,
	resource_mgr: Object,
	faction_opinion: float = 0.0
) -> Dictionary:
	if not is_active:
		return {"success": false, "reason": "Thương đoàn đã rời đi"}
	if amount <= 0:
		return {"success": false, "reason": "Số lượng bán không hợp lệ"}
		
	var unit_payout := get_effective_buy_price(item_id, faction_opinion)
	var total_payout := unit_payout * amount
	
	if gold < total_payout:
		return {"success": false, "reason": "Thương nhân không đủ vàng để chi trả (còn %d vàng)" % gold}
		
	if resource_mgr != null:
		if resource_mgr.get_available_stock(item_id) < amount:
			return {"success": false, "reason": "Không đủ tài nguyên khả dụng trong kho (còn %d)" % resource_mgr.get_available_stock(item_id)}
			
		# Check gold storage capacity
		var cur_gold: int = resource_mgr.get_total_stock(EconomyConfig.RES_GOLD)
		var max_gold_cap: int = resource_mgr.get_storage_capacity(EconomyConfig.RES_GOLD)
		if cur_gold + total_payout > max_gold_cap:
			return {"success": false, "reason": "Sức chứa kho vàng không đủ để nhận thanh toán"}
			
		# Atomic execution
		resource_mgr.call("consume_resource", item_id, amount)
		resource_mgr.call("add_resource", EconomyConfig.RES_GOLD, total_payout)
		
	gold -= total_payout
	inventory[item_id] = inventory.get(item_id, 0) + amount
	
	return {
		"success": true,
		"item_id": item_id,
		"amount": amount,
		"total_payout": total_payout,
		"remaining_caravan_gold": gold
	}
