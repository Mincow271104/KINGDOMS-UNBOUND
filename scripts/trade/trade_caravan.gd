class_name TradeCaravan
extends RefCounted
## Trade Caravan & Merchant System for KINGDOMS UNBOUND.
## Conforms to GDD Section 11:
## Finite goods, distinct buy/sell prices, opinion discounts, and atomic exchange transactions.

var caravan_id: String
var name: String
var origin_faction_id: String
var arrival_day: int
var departure_day: int
var is_active: bool = true
var is_origin_at_war: bool = false

const WARTIME_PRICE_SURCHARGE: float = 0.15

# Midpoint reference stock of generated caravan inventory per GDD / Package 2H specification
const CARAVAN_REFERENCE_STOCK: Dictionary = {
	EconomyConfig.RES_FOOD: 45.0,
	EconomyConfig.RES_WOOD: 35.0,
	EconomyConfig.RES_STONE: 22.5,
	EconomyConfig.RES_METAL: 17.5,
	EconomyConfig.RES_TOOLS: 10.0,
	EconomyConfig.RES_HERBS: 17.5,
	EconomyConfig.RES_CRYSTAL: 4.0
}

var inventory: Dictionary = {} # res_id -> int
var gold: int = 350
var sell_prices: Dictionary = {} # res_id -> unit cost for player to BUY
var buy_prices: Dictionary = {}  # res_id -> unit price caravan PAYS player to SELL

func _init(p_id: String = "", p_name: String = "", p_origin: String = "rival_merchant") -> void:
	caravan_id = p_id
	name = p_name
	origin_faction_id = p_origin
	is_origin_at_war = false

static func generate_caravan(seed_val: int, day: int, origin_faction: String = "rival_merchant", is_at_war: bool = false) -> RefCounted:
	var script = load("res://scripts/trade/trade_caravan.gd")
	var c = script.new("caravan_%d" % day, "Đoàn Buôn Phương Nam (Ngày %d)" % day, origin_faction)
	c.arrival_day = day
	c.departure_day = day + 2 # Stays 2 days
	c.is_active = true
	c.is_origin_at_war = is_at_war
	
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

## Dynamic Pricing Breakdown Helper (Package 2H)
## Unifies deterministic supply-demand calculations between UI quote and transaction execution.
func get_price_breakdown(res_id: String, faction_opinion: float = 0.0, resource_mgr: Object = null) -> Dictionary:
	var base_sell: int = sell_prices.get(res_id, 10)
	var base_buy: int = buy_prices.get(res_id, 5)

	# 1. Local Kingdom reference and available stock
	var local_ref: float = float(EconomyConfig.STARTING_RESOURCES.get(res_id, 0.0))
	var local_stock: int = 0
	var has_local_stock: bool = false
	if resource_mgr != null and resource_mgr.has_method("get_available_stock"):
		local_stock = resource_mgr.get_available_stock(res_id)
		has_local_stock = true

	var local_stock_ratio: float = 1.0
	var local_pressure: float = 0.0
	if has_local_stock and local_ref > 0.0:
		local_stock_ratio = clampf(float(local_stock) / local_ref, 0.0, 2.0)
		local_pressure = clampf(1.0 - local_stock_ratio, -1.0, 1.0) * 0.10

	# 2. Caravan reference and inventory stock
	var caravan_ref: float = float(CARAVAN_REFERENCE_STOCK.get(res_id, 0.0))
	var caravan_stock: int = int(inventory.get(res_id, 0))
	var caravan_stock_ratio: float = 1.0
	var caravan_pressure: float = 0.0
	if caravan_ref > 0.0:
		caravan_stock_ratio = clampf(float(caravan_stock) / caravan_ref, 0.0, 2.0)
		caravan_pressure = clampf(1.0 - caravan_stock_ratio, -1.0, 1.0) * 0.10

	# 3. Market multiplier [0.80, 1.20]
	var market_multiplier: float = clampf(1.0 + local_pressure + caravan_pressure, 0.80, 1.20)

	# 4. Diplomatic opinion adjustments [-0.20, +0.20]
	var opinion_clamped: float = clampf(faction_opinion / 500.0, -0.2, 0.2)
	var sell_opinion_mult: float = 1.0 - opinion_clamped
	var buy_opinion_mult: float = 1.0 + opinion_clamped

	# 5. Route risk surcharge (+15% to sell price when origin is at war)
	var route_risk_surcharge: float = WARTIME_PRICE_SURCHARGE if is_origin_at_war else 0.0

	# 6. Effective Sell Price (Player BUYS from caravan)
	var effective_sell_mult: float = (sell_opinion_mult + route_risk_surcharge) * market_multiplier
	var raw_sell_price: int = int(round(base_sell * effective_sell_mult))
	if is_origin_at_war and raw_sell_price <= base_sell:
		raw_sell_price = base_sell + 1
	var final_sell_price: int = maxi(2, raw_sell_price)

	# 7. Effective Buy Price (Player SELLS to caravan)
	var effective_buy_mult: float = buy_opinion_mult * market_multiplier
	var raw_buy_price: int = int(round(base_buy * effective_buy_mult))
	# Enforce bid <= ask - 1 and bid >= 1 (spread >= 1 Gold, no arbitrage, no <= 0 price)
	var final_buy_price: int = clampi(raw_buy_price, 1, final_sell_price - 1)

	return {
		"resource_id": res_id,
		"base_sell_price": base_sell,
		"base_buy_price": base_buy,
		"local_stock": local_stock,
		"local_reference_stock": local_ref,
		"local_stock_ratio": local_stock_ratio,
		"local_pressure": local_pressure,
		"caravan_stock": caravan_stock,
		"caravan_reference_stock": caravan_ref,
		"caravan_stock_ratio": caravan_stock_ratio,
		"caravan_pressure": caravan_pressure,
		"market_multiplier": market_multiplier,
		"opinion_adjustment": opinion_clamped,
		"route_risk_surcharge": route_risk_surcharge,
		"is_origin_at_war": is_origin_at_war,
		"final_sell_price": final_sell_price,
		"final_buy_price": final_buy_price,
		"unit_sell_price": final_sell_price,
		"unit_buy_price": final_buy_price
	}

func get_effective_sell_price(res_id: String, faction_opinion: float = 0.0, resource_mgr: Object = null) -> int:
	var bd: Dictionary = get_price_breakdown(res_id, faction_opinion, resource_mgr)
	return int(bd.get("final_sell_price", 2))

func get_effective_buy_price(res_id: String, faction_opinion: float = 0.0, resource_mgr: Object = null) -> int:
	var bd: Dictionary = get_price_breakdown(res_id, faction_opinion, resource_mgr)
	return int(bd.get("final_buy_price", 1))

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
		
	var unit_price := get_effective_sell_price(item_id, faction_opinion, resource_mgr)
	var total_cost := unit_price * amount
	
	if resource_mgr != null:
		var has_gold: bool = false
		if resource_mgr.has_method("has_resource"):
			has_gold = resource_mgr.has_resource(EconomyConfig.RES_GOLD, total_cost)
		elif resource_mgr.has_method("get_available_stock"):
			has_gold = resource_mgr.get_available_stock(EconomyConfig.RES_GOLD) >= total_cost
		if not has_gold:
			return {"success": false, "reason": "Không đủ vàng trong ngân khố (cần %d vàng)" % total_cost}
			
		# Check destination storage capacity
		var cur_total: int = resource_mgr.get_total_stock(item_id) if resource_mgr.has_method("get_total_stock") else 0
		var max_cap: int = 999999
		if resource_mgr.has_method("get_storage_capacity"):
			max_cap = resource_mgr.get_storage_capacity(item_id)
		elif resource_mgr.has_method("get_capacity"):
			max_cap = resource_mgr.get_capacity(item_id)
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
		"unit_price": unit_price,
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
		
	var unit_payout := get_effective_buy_price(item_id, faction_opinion, resource_mgr)
	var total_payout := unit_payout * amount
	
	if gold < total_payout:
		return {"success": false, "reason": "Thương nhân không đủ vàng để chi trả (còn %d vàng)" % gold}
		
	if resource_mgr != null:
		if resource_mgr.get_available_stock(item_id) < amount:
			return {"success": false, "reason": "Không đủ tài nguyên khả dụng trong kho (còn %d)" % resource_mgr.get_available_stock(item_id)}
			
		# Check gold storage capacity
		var cur_gold: int = resource_mgr.get_total_stock(EconomyConfig.RES_GOLD) if resource_mgr.has_method("get_total_stock") else 0
		var max_gold_cap: int = 999999
		if resource_mgr.has_method("get_storage_capacity"):
			max_gold_cap = resource_mgr.get_storage_capacity(EconomyConfig.RES_GOLD)
		elif resource_mgr.has_method("get_capacity"):
			max_gold_cap = resource_mgr.get_capacity(EconomyConfig.RES_GOLD)
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
		"unit_payout": unit_payout,
		"total_payout": total_payout,
		"remaining_caravan_gold": gold
	}

func serialize() -> Dictionary:
	return {
		"caravan_id": caravan_id,
		"name": name,
		"origin_faction_id": origin_faction_id,
		"arrival_day": arrival_day,
		"departure_day": departure_day,
		"is_active": is_active,
		"is_origin_at_war": is_origin_at_war,
		"inventory": inventory.duplicate(true),
		"gold": gold,
		"sell_prices": sell_prices.duplicate(true),
		"buy_prices": buy_prices.duplicate(true)
	}

static func deserialize(data: Dictionary) -> RefCounted:
	if data.is_empty():
		return null
	var c_id := String(data.get("caravan_id", "")).strip_edges()
	var c_name := String(data.get("name", "")).strip_edges()
	var c_origin := String(data.get("origin_faction_id", "rival_merchant")).strip_edges()
	if c_id.is_empty() or c_origin.is_empty():
		return null
	var script = load("res://scripts/trade/trade_caravan.gd")
	var c = script.new(c_id, c_name if not c_name.is_empty() else ("Đoàn Buôn (%s)" % c_id), c_origin)
	c.arrival_day = int(data.get("arrival_day", 1))
	c.departure_day = int(data.get("departure_day", c.arrival_day + 2))
	c.is_active = bool(data.get("is_active", true))
	c.is_origin_at_war = bool(data.get("is_origin_at_war", false))
	c.gold = maxi(0, int(data.get("gold", 0)))

	c.inventory = {}
	var raw_inv = data.get("inventory", {})
	if raw_inv is Dictionary:
		for k in raw_inv.keys():
			c.inventory[String(k)] = maxi(0, int(raw_inv[k]))

	c.sell_prices = {}
	var raw_sell = data.get("sell_prices", {})
	if raw_sell is Dictionary:
		for k in raw_sell.keys():
			c.sell_prices[String(k)] = maxi(1, int(raw_sell[k]))

	c.buy_prices = {}
	var raw_buy = data.get("buy_prices", {})
	if raw_buy is Dictionary:
		for k in raw_buy.keys():
			c.buy_prices[String(k)] = maxi(1, int(raw_buy[k]))

	return c
