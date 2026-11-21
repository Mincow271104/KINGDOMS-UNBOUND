class_name SettlementEconomy
extends RefCounted
## Settlement-local economy and supply-profile state model (Architecture v1.0 — Phase 2).
## Authoritative owner of settlement-local resource stocks, storage capacities, local gold treasury,
## bounded external supply providers (Neutral Tribe forage, Military ration logistics, Merchant market pool),
## and SettlementSupplyLedger.
##
## Strictly isolated from:
## - /root/ResourceManager and player economy
## - CitizenController and player citizen inventory
## - FactionData.resources and FactionData.population

signal transaction_committed(receipt: Dictionary)

const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementSupplyLedgerScript = preload("res://scripts/world/settlement_supply_ledger.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")

const PROFILE_NEUTRAL_TRIBE: String = "neutral_tribe"
const PROFILE_MILITARY: String = "rival_military"
const PROFILE_MERCHANT: String = "rival_merchant"

const VALID_PROFILES: Array[String] = [
	PROFILE_NEUTRAL_TRIBE,
	PROFILE_MILITARY,
	PROFILE_MERCHANT
]

const PROVIDER_STATE_ACTIVE: String = "active"
const PROVIDER_STATE_FULL: String = "full"
const PROVIDER_STATE_WAITING_CAPACITY: String = "waiting_capacity"
const PROVIDER_STATE_DEPLETED: String = "depleted"
const PROVIDER_STATE_DISABLED: String = "disabled"

const VALID_PROVIDER_STATES: Array[String] = [
	PROVIDER_STATE_ACTIVE,
	PROVIDER_STATE_FULL,
	PROVIDER_STATE_WAITING_CAPACITY,
	PROVIDER_STATE_DEPLETED,
	PROVIDER_STATE_DISABLED
]

# Physical resources stored in _stock (excludes RES_GOLD, which lives in _gold treasury)
const PHYSICAL_RESOURCES: Array[String] = [
	EconomyConfigScript.RES_FOOD,
	EconomyConfigScript.RES_WOOD,
	EconomyConfigScript.RES_STONE,
	EconomyConfigScript.RES_ORE,
	EconomyConfigScript.RES_METAL,
	EconomyConfigScript.RES_TOOLS,
	EconomyConfigScript.RES_CRYSTAL,
	EconomyConfigScript.RES_HERBS,
	EconomyConfigScript.RES_RAW_MEAT,
	EconomyConfigScript.RES_HEARTY_MEAL,
	EconomyConfigScript.RES_HERBAL_BROTH
]

# Market-tradable resources for Merchant settlements (note: RES_ORE is deliberately excluded;
# no free Ore is seeded and Merchant Smith remains disabled by default).
const MERCHANT_MARKET_RESOURCES: Array[String] = [
	EconomyConfigScript.RES_FOOD,
	EconomyConfigScript.RES_WOOD,
	EconomyConfigScript.RES_STONE,
	EconomyConfigScript.RES_METAL,
	EconomyConfigScript.RES_TOOLS,
	EconomyConfigScript.RES_HERBS,
	EconomyConfigScript.RES_CRYSTAL
]

# Grounded in TradeCaravan.sell_prices (GDD §11.1)
const DEFAULT_MARKET_PRICES: Dictionary = {
	EconomyConfigScript.RES_FOOD: 2,
	EconomyConfigScript.RES_WOOD: 3,
	EconomyConfigScript.RES_STONE: 4,
	EconomyConfigScript.RES_METAL: 8,
	EconomyConfigScript.RES_TOOLS: 15,
	EconomyConfigScript.RES_HERBS: 6,
	EconomyConfigScript.RES_CRYSTAL: 35
}

# Provisional Phase 2 scenario endowments (explicit provenance: "scenario_endowment:<profile>")
const DEFAULT_TRIBE_INITIAL_STOCK: Dictionary = {
	EconomyConfigScript.RES_FOOD: 60,
	EconomyConfigScript.RES_WOOD: 40,
	EconomyConfigScript.RES_HERBS: 20
}
const DEFAULT_TRIBE_INITIAL_GOLD: int = 0

const DEFAULT_FORAGE_MAX_CAPACITY: int = 120
const DEFAULT_FORAGE_REGEN_AMOUNT: float = 4.0
const DEFAULT_FORAGE_INTERVAL_HOURS: int = 6

const DEFAULT_MILITARY_INITIAL_STOCK: Dictionary = {
	EconomyConfigScript.RES_FOOD: 80,
	EconomyConfigScript.RES_WOOD: 40,
	EconomyConfigScript.RES_STONE: 30,
	EconomyConfigScript.RES_METAL: 20,
	EconomyConfigScript.RES_TOOLS: 10
}
const DEFAULT_MILITARY_INITIAL_GOLD: int = 0
const DEFAULT_MILITARY_LOGISTICS_INITIAL_BUDGET: int = 120
const DEFAULT_MILITARY_LOGISTICS_MAX_ALLOCATION: int = 240
const DEFAULT_MILITARY_LOGISTICS_MAX_CUMULATIVE_TOP_UPS: int = 240
const DEFAULT_MILITARY_RATION_DELIVERY_AMOUNT: int = 20
const DEFAULT_MILITARY_DELIVERY_INTERVAL_HOURS: int = 24

const DEFAULT_MERCHANT_INITIAL_STOCK: Dictionary = {
	EconomyConfigScript.RES_FOOD: 70,
	EconomyConfigScript.RES_WOOD: 50,
	EconomyConfigScript.RES_STONE: 30,
	EconomyConfigScript.RES_TOOLS: 15,
	EconomyConfigScript.RES_HERBS: 15
}
const DEFAULT_MERCHANT_INITIAL_GOLD: int = 120

const DEFAULT_MERCHANT_MARKET_INITIAL_STOCK: Dictionary = {
	EconomyConfigScript.RES_FOOD: 60,
	EconomyConfigScript.RES_WOOD: 50,
	EconomyConfigScript.RES_STONE: 30,
	EconomyConfigScript.RES_METAL: 20,
	EconomyConfigScript.RES_TOOLS: 15,
	EconomyConfigScript.RES_HERBS: 20,
	EconomyConfigScript.RES_CRYSTAL: 4
}

const DEFAULT_MERCHANT_MARKET_CAPACITY: Dictionary = {
	EconomyConfigScript.RES_FOOD: 120,
	EconomyConfigScript.RES_WOOD: 100,
	EconomyConfigScript.RES_STONE: 60,
	EconomyConfigScript.RES_METAL: 40,
	EconomyConfigScript.RES_TOOLS: 30,
	EconomyConfigScript.RES_HERBS: 40,
	EconomyConfigScript.RES_CRYSTAL: 12
}

const DEFAULT_MERCHANT_MARKET_RESTOCK_ALLOCATION: Dictionary = {
	EconomyConfigScript.RES_FOOD: 120,
	EconomyConfigScript.RES_WOOD: 100,
	EconomyConfigScript.RES_STONE: 60,
	EconomyConfigScript.RES_METAL: 40,
	EconomyConfigScript.RES_TOOLS: 30,
	EconomyConfigScript.RES_HERBS: 40,
	EconomyConfigScript.RES_CRYSTAL: 8
}

const DEFAULT_MERCHANT_MARKET_MAX_ALLOCATION: Dictionary = {
	EconomyConfigScript.RES_FOOD: 240,
	EconomyConfigScript.RES_WOOD: 200,
	EconomyConfigScript.RES_STONE: 120,
	EconomyConfigScript.RES_METAL: 80,
	EconomyConfigScript.RES_TOOLS: 60,
	EconomyConfigScript.RES_HERBS: 80,
	EconomyConfigScript.RES_CRYSTAL: 20
}

const DEFAULT_MERCHANT_MARKET_RESTOCK_AMOUNT: Dictionary = {
	EconomyConfigScript.RES_FOOD: 20,
	EconomyConfigScript.RES_WOOD: 15,
	EconomyConfigScript.RES_STONE: 10,
	EconomyConfigScript.RES_METAL: 5,
	EconomyConfigScript.RES_TOOLS: 5,
	EconomyConfigScript.RES_HERBS: 5,
	EconomyConfigScript.RES_CRYSTAL: 2
}

const DEFAULT_MERCHANT_RESTOCK_INTERVAL_HOURS: int = 24

# --- Identity & Ownership (Immutable once initialized) ---
var _settlement_id: String = ""
var _origin_faction_id: String = ""
var _economy_profile_id: String = ""
var _identity_locked: bool = false

var settlement_id: String:
	get:
		return _settlement_id
	set(value):
		if _identity_locked or not _settlement_id.is_empty():
			return
		var clean := value.strip_edges()
		if SettlementVillagerDataScript.is_valid_identifier(clean):
			_settlement_id = clean

var origin_faction_id: String:
	get:
		return _origin_faction_id
	set(value):
		if _identity_locked or not _origin_faction_id.is_empty():
			return
		var clean := value.strip_edges()
		if SettlementVillagerDataScript.is_valid_identifier(clean):
			_origin_faction_id = clean

var economy_profile_id: String:
	get:
		return _economy_profile_id
	set(value):
		if _identity_locked or not _economy_profile_id.is_empty():
			return
		var clean := value.strip_edges()
		if VALID_PROFILES.has(clean):
			_economy_profile_id = clean

# Locked Architecture Invariant: Merchant Smith is disabled by default when sustainable Ore supply is absent.
var _merchant_smith_enabled: bool = false
var merchant_smith_enabled: bool:
	get:
		return _merchant_smith_enabled

var _is_endowment_initialized: bool = false
var is_endowment_initialized: bool:
	get:
		return _is_endowment_initialized

const MAX_SAFE_TRANSACTION_AMOUNT: int = 1000000000

# --- Authoritative Local Balances & Capacities ---
var _stock: Dictionary = {} # res_id -> int
var _base_capacities: Dictionary = {} # res_id -> int (EconomyConfig.BASE_CAPACITIES or explicit set_resource_capacity base)
var _derived_capacity_bonuses: Dictionary = {} # res_id -> int (building-derived storage bonus)
var _capacities: Dictionary = {} # res_id -> int (_base_capacities + _derived_capacity_bonuses)
var _over_capacity_resources: Dictionary = {} # res_id -> int (excess stock preserved when derived storage capacity decreases)
var _gold: int = 0
var _gold_capacity: int = 999999

# --- Authoritative Supply Ledger (Read-Only Property) ---
var _ledger: RefCounted = null
var ledger: RefCounted:
	get:
		return _ledger

# --- Independent Supply Provider States ---
var _forage_provider: Dictionary = {}
var _military_logistics: Dictionary = {}
var _market_provider: Dictionary = {}
var _pending_buffer_deliveries: Dictionary = {} # source_tag -> { res_id -> int }

func _init(
	p_settlement_id: String = "",
	p_origin_faction_id: String = "",
	p_initialize_default_endowment: bool = true
) -> void:
	_settlement_id = p_settlement_id.strip_edges()
	_origin_faction_id = p_origin_faction_id.strip_edges()
	_economy_profile_id = resolve_profile_for_origin(_origin_faction_id)
	_merchant_smith_enabled = false
	_is_endowment_initialized = false

	_init_zero_balances_and_base_capacities()
	_ledger = SettlementSupplyLedgerScript.new(_settlement_id, SettlementSupplyLedgerScript.DEFAULT_MAX_HISTORY_ENTRIES, true)
	_init_empty_providers()

	if not _settlement_id.is_empty() and not _origin_faction_id.is_empty() and not _economy_profile_id.is_empty():
		_identity_locked = true
		if p_initialize_default_endowment and is_valid():
			initialize_default_profile_endowment()

static func resolve_profile_for_origin(p_origin_faction_id: String) -> String:
	var clean := p_origin_faction_id.strip_edges()
	if VALID_PROFILES.has(clean):
		return clean
	return ""

func lock_identity() -> void:
	_identity_locked = true
	if ledger != null and ledger.has_method("lock_identity"):
		ledger.lock_identity()

func is_identity_locked() -> bool:
	return _identity_locked

func _init_zero_balances_and_base_capacities() -> void:
	_stock.clear()
	_base_capacities.clear()
	_derived_capacity_bonuses.clear()
	_capacities.clear()
	_over_capacity_resources.clear()
	for res_id in PHYSICAL_RESOURCES:
		var base_c: int = int(EconomyConfigScript.BASE_CAPACITIES.get(res_id, 500))
		_stock[res_id] = 0
		_base_capacities[res_id] = base_c
		_derived_capacity_bonuses[res_id] = 0
		_capacities[res_id] = base_c
	_gold = 0
	_gold_capacity = int(EconomyConfigScript.BASE_CAPACITIES.get(EconomyConfigScript.RES_GOLD, 999999))
	_pending_buffer_deliveries.clear()

func _commit_ledger_initial(res_id: String, amount: int, source: String, destination: String, hour_seq: int) -> Dictionary:
	_ledger._allow_internal_mutation = true
	var entry: Dictionary = _ledger.record_initial_endowment(res_id, amount, source, destination, hour_seq)
	_ledger._allow_internal_mutation = false
	return entry

func _commit_ledger_inflow(res_id: String, amount: int, source: String, destination: String, reason: String, hour_seq: int, balance_after: int) -> Dictionary:
	_ledger._allow_internal_mutation = true
	var entry: Dictionary = _ledger.record_inflow(res_id, amount, source, destination, reason, hour_seq, balance_after)
	_ledger._allow_internal_mutation = false
	return entry

func _commit_ledger_outflow(res_id: String, amount: int, source: String, destination: String, reason: String, hour_seq: int, balance_after: int) -> Dictionary:
	_ledger._allow_internal_mutation = true
	var entry: Dictionary = _ledger.record_outflow(res_id, amount, source, destination, reason, hour_seq, balance_after)
	_ledger._allow_internal_mutation = false
	return entry

func _commit_ledger_provider_event(res_id: String, amount: int, source: String, destination: String, reason: String, hour_seq: int, provider_balance_after: int) -> Dictionary:
	_ledger._allow_internal_mutation = true
	var entry: Dictionary = _ledger.record_provider_event(res_id, amount, source, destination, reason, hour_seq, provider_balance_after)
	_ledger._allow_internal_mutation = false
	return entry

func get_ledger_snapshot() -> Dictionary:
	return _ledger.to_dict() if _ledger != null else {}

func _init_empty_providers() -> void:
	_forage_provider = {
		"enabled": false,
		"resource_id": EconomyConfigScript.RES_FOOD,
		"initial_stock": 0,
		"current_stock": 0,
		"max_capacity": DEFAULT_FORAGE_MAX_CAPACITY,
		"regen_amount_per_interval": DEFAULT_FORAGE_REGEN_AMOUNT,
		"regen_interval_hours": DEFAULT_FORAGE_INTERVAL_HOURS,
		"last_processed_hour_seq": 0,
		"elapsed_hours_remainder": 0,
		"fractional_remainder": 0.0,
		"state": PROVIDER_STATE_DISABLED,
		"total_regenerated": 0
	}
	_military_logistics = {
		"enabled": false,
		"resource_id": EconomyConfigScript.RES_FOOD,
		"initial_allocation": 0,
		"remaining_budget": 0,
		"max_allocation": DEFAULT_MILITARY_LOGISTICS_MAX_ALLOCATION,
		"max_cumulative_top_ups": DEFAULT_MILITARY_LOGISTICS_MAX_CUMULATIVE_TOP_UPS,
		"ration_amount_per_delivery": DEFAULT_MILITARY_RATION_DELIVERY_AMOUNT,
		"delivery_interval_hours": DEFAULT_MILITARY_DELIVERY_INTERVAL_HOURS,
		"next_delivery_hour_seq": DEFAULT_MILITARY_DELIVERY_INTERVAL_HOURS,
		"last_completed_delivery_hour_seq": 0,
		"state": PROVIDER_STATE_DISABLED,
		"total_delivered": 0,
		"total_top_ups": 0,
		"processed_grant_ids": {}
	}
	var m_init_stock: Dictionary = {}
	var m_stock: Dictionary = {}
	var m_cap: Dictionary = {}
	var m_init_alloc: Dictionary = {}
	var m_rem_alloc: Dictionary = {}
	var m_max_alloc: Dictionary = {}
	var m_max_cum_top: Dictionary = {}
	var m_restock_amt: Dictionary = {}
	for res_id in MERCHANT_MARKET_RESOURCES:
		m_init_stock[res_id] = 0
		m_stock[res_id] = 0
		m_cap[res_id] = int(DEFAULT_MERCHANT_MARKET_CAPACITY.get(res_id, 50))
		m_init_alloc[res_id] = 0
		m_rem_alloc[res_id] = 0
		m_max_alloc[res_id] = int(DEFAULT_MERCHANT_MARKET_MAX_ALLOCATION.get(res_id, 100))
		m_max_cum_top[res_id] = int(DEFAULT_MERCHANT_MARKET_MAX_ALLOCATION.get(res_id, 100))
		m_restock_amt[res_id] = int(DEFAULT_MERCHANT_MARKET_RESTOCK_AMOUNT.get(res_id, 5))
	_market_provider = {
		"enabled": false,
		"initial_stock": m_init_stock,
		"stock": m_stock,
		"capacity": m_cap,
		"initial_allocation": m_init_alloc,
		"remaining_restock_allocation": m_rem_alloc,
		"max_restock_allocation": m_max_alloc,
		"max_cumulative_top_ups": m_max_cum_top,
		"restock_amount_per_interval": m_restock_amt,
		"prices": DEFAULT_MARKET_PRICES.duplicate(true),
		"restock_interval_hours": DEFAULT_MERCHANT_RESTOCK_INTERVAL_HOURS,
		"next_restock_hour_seq": DEFAULT_MERCHANT_RESTOCK_INTERVAL_HOURS,
		"last_completed_restock_hour_seq": 0,
		"state": PROVIDER_STATE_DISABLED,
		"total_restocked": {},
		"total_purchased": {},
		"total_allocation_top_ups": {},
		"processed_grant_ids": {}
	}
	for res_id in MERCHANT_MARKET_RESOURCES:
		_market_provider["total_restocked"][res_id] = 0
		_market_provider["total_purchased"][res_id] = 0
		_market_provider["total_allocation_top_ups"][res_id] = 0

func is_valid() -> bool:
	if not SettlementVillagerDataScript.is_valid_identifier(_settlement_id):
		return false
	if not SettlementVillagerDataScript.is_valid_identifier(_origin_faction_id):
		return false
	if not VALID_PROFILES.has(_economy_profile_id):
		return false
	if _economy_profile_id != resolve_profile_for_origin(_origin_faction_id):
		return false
	if _gold < 0 or _gold_capacity < 0 or _gold > _gold_capacity:
		return false
	for res_id in PHYSICAL_RESOURCES:
		if not _stock.has(res_id) or not _capacities.has(res_id):
			return false
		var s: int = int(_stock[res_id])
		var c: int = int(_capacities[res_id])
		if s < 0 or c < 0:
			return false
		if s > c and not _over_capacity_resources.has(res_id):
			return false
	if _ledger == null or not _ledger.is_valid() or _ledger.settlement_id != _settlement_id:
		return false
	if not _ledger.verify_balance_consistency(_stock, _gold):
		return false
	if not verify_provider_conservation():
		return false
	return true

## Verifies that all three supply providers obey strict account conservation and match ledger records.
func verify_provider_conservation() -> bool:
	if _ledger == null:
		return false
	# 1. Neutral Tribe Forage conservation
	var fp_enabled: bool = bool(_forage_provider.get("enabled", false))
	if fp_enabled and _economy_profile_id != PROFILE_NEUTRAL_TRIBE:
		return false
	var fp_reg: int = int(_forage_provider.get("total_regenerated", 0))
	var ledger_forage_in: int = int(_ledger.get_inflows_by_source(EconomyConfigScript.RES_FOOD).get("provider:neutral_tribe_forage", 0))
	if fp_reg != ledger_forage_in:
		return false
	if fp_enabled:
		var fp_cap: int = int(_forage_provider.get("max_capacity", DEFAULT_FORAGE_MAX_CAPACITY))
		var expected_cur: int = mini(fp_cap, int(_stock.get(EconomyConfigScript.RES_FOOD, 0)))
		if int(_forage_provider.get("current_stock", -1)) != expected_cur:
			return false

	# 2. Military Logistics conservation: remaining_budget == initial_allocation + total_top_ups - total_delivered
	var ml_enabled: bool = bool(_military_logistics.get("enabled", false))
	if ml_enabled and _economy_profile_id != PROFILE_MILITARY:
		return false
	var ml_init: int = int(_military_logistics.get("initial_allocation", 0))
	var ml_rem: int = int(_military_logistics.get("remaining_budget", 0))
	var ml_del: int = int(_military_logistics.get("total_delivered", 0))
	var ml_top: int = int(_military_logistics.get("total_top_ups", 0))
	if ml_rem != (ml_init + ml_top - ml_del):
		return false
	var ledger_mil_in: int = int(_ledger.get_inflows_by_source(EconomyConfigScript.RES_FOOD).get("provider:military_offmap_logistics", 0))
	var pending_mil_in: int = int((_pending_buffer_deliveries.get("provider:military_offmap_logistics", {}) as Dictionary).get(EconomyConfigScript.RES_FOOD, 0))
	if ml_del != (ledger_mil_in + pending_mil_in):
		return false

	# 3. Merchant Market conservation (both restock allocation and market inventory per resource)
	var mp_enabled: bool = bool(_market_provider.get("enabled", false))
	if mp_enabled and _economy_profile_id != PROFILE_MERCHANT:
		return false
	var m_init_stock_map: Dictionary = _market_provider.get("initial_stock", {})
	var m_stock_map: Dictionary = _market_provider.get("stock", {})
	var m_init_alloc_map: Dictionary = _market_provider.get("initial_allocation", {})
	var m_rem_alloc_map: Dictionary = _market_provider.get("remaining_restock_allocation", {})
	var m_restocked_map: Dictionary = _market_provider.get("total_restocked", {})
	var m_purchased_map: Dictionary = _market_provider.get("total_purchased", {})
	var m_top_up_map: Dictionary = _market_provider.get("total_allocation_top_ups", {})
	for res_id in MERCHANT_MARKET_RESOURCES:
		var init_s: int = int(m_init_stock_map.get(res_id, 0))
		var cur_s: int = int(m_stock_map.get(res_id, 0))
		var init_a: int = int(m_init_alloc_map.get(res_id, 0))
		var rem_a: int = int(m_rem_alloc_map.get(res_id, 0))
		var tot_r: int = int(m_restocked_map.get(res_id, 0))
		var tot_p: int = int(m_purchased_map.get(res_id, 0))
		var tot_top: int = int(m_top_up_map.get(res_id, 0))
		if rem_a != (init_a + tot_top - tot_r):
			return false
		if cur_s != (init_s + tot_r - tot_p):
			return false
		var ledger_mkt_in: int = int(_ledger.get_inflows_by_source(res_id).get("provider:merchant_market", 0))
		var pending_mkt_in: int = int((_pending_buffer_deliveries.get("provider:merchant_market", {}) as Dictionary).get(res_id, 0))
		if tot_p != (ledger_mkt_in + pending_mkt_in):
			return false
	return true

## Initializes the settlement economy with the approved default profile endowment and provider configuration.
## May only be called once on an unendowed economy with zero transactions.
func initialize_default_profile_endowment(hour_seq: int = 0) -> bool:
	if not is_valid() or _is_endowment_initialized or not _is_valid_strict_int(hour_seq) or int(hour_seq) < 0:
		return false
	if _ledger.get_next_tx_seq() != 1:
		return false
	if bool(_forage_provider.get("enabled", false)) or bool(_military_logistics.get("enabled", false)) or bool(_market_provider.get("enabled", false)):
		return false
	for res_id in EconomyConfigScript.ALL_RESOURCES:
		if _ledger.get_total_inflow(res_id) != 0 or _ledger.get_total_outflow(res_id) != 0 or _ledger.get_initial_balance(res_id) != 0:
			return false
		if _ledger.get_initial_provenance(res_id) != "uninitialized_zero":
			return false

	var provenance_src: String = "scenario_endowment:%s" % _economy_profile_id
	match _economy_profile_id:
		PROFILE_NEUTRAL_TRIBE:
			for res_id in DEFAULT_TRIBE_INITIAL_STOCK.keys():
				var amt: int = int(DEFAULT_TRIBE_INITIAL_STOCK[res_id])
				_stock[res_id] = amt
				_commit_ledger_initial(res_id, amt, provenance_src, "settlement_stock:%s" % res_id, hour_seq)
			_gold = DEFAULT_TRIBE_INITIAL_GOLD
			var init_food: int = int(_stock[EconomyConfigScript.RES_FOOD])
			_forage_provider["enabled"] = true
			_forage_provider["initial_stock"] = init_food
			_forage_provider["current_stock"] = mini(DEFAULT_FORAGE_MAX_CAPACITY, init_food)
			_forage_provider["max_capacity"] = DEFAULT_FORAGE_MAX_CAPACITY
			_forage_provider["regen_amount_per_interval"] = DEFAULT_FORAGE_REGEN_AMOUNT
			_forage_provider["regen_interval_hours"] = DEFAULT_FORAGE_INTERVAL_HOURS
			_forage_provider["last_processed_hour_seq"] = hour_seq
			_forage_provider["elapsed_hours_remainder"] = 0
			_forage_provider["fractional_remainder"] = 0.0
			_forage_provider["state"] = PROVIDER_STATE_FULL if init_food >= DEFAULT_FORAGE_MAX_CAPACITY else PROVIDER_STATE_ACTIVE
			_forage_provider["total_regenerated"] = 0

		PROFILE_MILITARY:
			for res_id in DEFAULT_MILITARY_INITIAL_STOCK.keys():
				var amt_m: int = int(DEFAULT_MILITARY_INITIAL_STOCK[res_id])
				_stock[res_id] = amt_m
				_commit_ledger_initial(res_id, amt_m, provenance_src, "settlement_stock:%s" % res_id, hour_seq)
			_gold = DEFAULT_MILITARY_INITIAL_GOLD
			_military_logistics["enabled"] = true
			_military_logistics["initial_allocation"] = DEFAULT_MILITARY_LOGISTICS_INITIAL_BUDGET
			_military_logistics["remaining_budget"] = DEFAULT_MILITARY_LOGISTICS_INITIAL_BUDGET
			_military_logistics["max_allocation"] = DEFAULT_MILITARY_LOGISTICS_MAX_ALLOCATION
			_military_logistics["max_cumulative_top_ups"] = DEFAULT_MILITARY_LOGISTICS_MAX_CUMULATIVE_TOP_UPS
			_military_logistics["ration_amount_per_delivery"] = DEFAULT_MILITARY_RATION_DELIVERY_AMOUNT
			_military_logistics["delivery_interval_hours"] = DEFAULT_MILITARY_DELIVERY_INTERVAL_HOURS
			_military_logistics["next_delivery_hour_seq"] = hour_seq + DEFAULT_MILITARY_DELIVERY_INTERVAL_HOURS
			_military_logistics["last_completed_delivery_hour_seq"] = hour_seq
			_military_logistics["state"] = PROVIDER_STATE_ACTIVE
			_military_logistics["total_delivered"] = 0
			_military_logistics["total_top_ups"] = 0
			_military_logistics["processed_grant_ids"] = {}
			_commit_ledger_provider_event(
				EconomyConfigScript.RES_FOOD,
				DEFAULT_MILITARY_LOGISTICS_INITIAL_BUDGET,
				provenance_src,
				"provider:military_offmap_logistics",
				"initial_logistics_allocation",
				hour_seq,
				DEFAULT_MILITARY_LOGISTICS_INITIAL_BUDGET
			)

		PROFILE_MERCHANT:
			for res_id in DEFAULT_MERCHANT_INITIAL_STOCK.keys():
				var amt_mer: int = int(DEFAULT_MERCHANT_INITIAL_STOCK[res_id])
				_stock[res_id] = amt_mer
				_commit_ledger_initial(res_id, amt_mer, provenance_src, "settlement_stock:%s" % res_id, hour_seq)
			_gold = DEFAULT_MERCHANT_INITIAL_GOLD
			_commit_ledger_initial(
				EconomyConfigScript.RES_GOLD,
				DEFAULT_MERCHANT_INITIAL_GOLD,
				provenance_src,
				"settlement_treasury",
				hour_seq
			)
			_market_provider["enabled"] = true
			_market_provider["processed_grant_ids"] = {}
			for res_id in MERCHANT_MARKET_RESOURCES:
				var init_m_stock: int = int(DEFAULT_MERCHANT_MARKET_INITIAL_STOCK.get(res_id, 0))
				var init_m_alloc: int = int(DEFAULT_MERCHANT_MARKET_RESTOCK_ALLOCATION.get(res_id, 0))
				_market_provider["initial_stock"][res_id] = init_m_stock
				_market_provider["stock"][res_id] = init_m_stock
				_market_provider["capacity"][res_id] = int(DEFAULT_MERCHANT_MARKET_CAPACITY.get(res_id, 50))
				_market_provider["initial_allocation"][res_id] = init_m_alloc
				_market_provider["remaining_restock_allocation"][res_id] = init_m_alloc
				_market_provider["max_restock_allocation"][res_id] = int(DEFAULT_MERCHANT_MARKET_MAX_ALLOCATION.get(res_id, 100))
				_market_provider["max_cumulative_top_ups"][res_id] = int(DEFAULT_MERCHANT_MARKET_MAX_ALLOCATION.get(res_id, 100))
				_market_provider["restock_amount_per_interval"][res_id] = int(DEFAULT_MERCHANT_MARKET_RESTOCK_AMOUNT.get(res_id, 5))
				_market_provider["total_restocked"][res_id] = 0
				_market_provider["total_purchased"][res_id] = 0
				_market_provider["total_allocation_top_ups"][res_id] = 0
				if init_m_stock > 0:
					_commit_ledger_provider_event(
						res_id,
						init_m_stock,
						provenance_src,
						"provider:merchant_market",
						"initial_market_stock",
						hour_seq,
						init_m_stock
					)
			_market_provider["prices"] = DEFAULT_MARKET_PRICES.duplicate(true)
			_market_provider["restock_interval_hours"] = DEFAULT_MERCHANT_RESTOCK_INTERVAL_HOURS
			_market_provider["next_restock_hour_seq"] = hour_seq + DEFAULT_MERCHANT_RESTOCK_INTERVAL_HOURS
			_market_provider["last_completed_restock_hour_seq"] = hour_seq
			_market_provider["state"] = PROVIDER_STATE_ACTIVE

	_is_endowment_initialized = true
	return true

# -----------------------------------------------------------------------------
# Validation Helpers (No silent clamping of transaction inputs)
# -----------------------------------------------------------------------------
static func _is_valid_strict_int(val: Variant) -> bool:
	if val is bool:
		return false
	if val is int:
		return true
	if val is float:
		var f: float = float(val)
		if is_nan(f) or is_inf(f):
			return false
		return is_equal_approx(f, roundf(f))
	return false

static func is_valid_physical_resource(res_id: String) -> bool:
	return PHYSICAL_RESOURCES.has(res_id)

# -----------------------------------------------------------------------------
# Resource Balance, Capacity & Gold Treasury APIs
# -----------------------------------------------------------------------------
func get_resource(res_id: String) -> int:
	if res_id == EconomyConfigScript.RES_GOLD:
		return _gold
	if not _stock.has(res_id):
		return 0
	return int(_stock[res_id])

func get_capacity(res_id: String) -> int:
	if res_id == EconomyConfigScript.RES_GOLD:
		return _gold_capacity
	if not _capacities.has(res_id):
		return 0
	return int(_capacities[res_id])

func get_available_headroom(res_id: String) -> int:
	if res_id == EconomyConfigScript.RES_GOLD:
		return maxi(0, _gold_capacity - _gold)
	if not _stock.has(res_id) or not _capacities.has(res_id):
		return 0
	return maxi(0, int(_capacities[res_id]) - int(_stock[res_id]))

func has_resource(res_id: String, amount: Variant) -> bool:
	if not _is_valid_strict_int(amount):
		return false
	var req: int = int(amount)
	if req < 0:
		return false
	if res_id == EconomyConfigScript.RES_GOLD:
		return _gold >= req
	if not _stock.has(res_id):
		return false
	return int(_stock[res_id]) >= req

func set_resource_capacity(res_id: String, new_capacity: Variant) -> bool:
	if not is_valid_physical_resource(res_id) or not _is_valid_strict_int(new_capacity):
		return false
	var cap: int = int(new_capacity)
	if cap < 0 or cap < int(_stock[res_id]):
		return false
	_base_capacities[res_id] = maxi(0, cap - int(_derived_capacity_bonuses.get(res_id, 0)))
	_capacities[res_id] = cap
	_over_capacity_resources.erase(res_id)
	return true

func get_base_capacity(res_id: String) -> int:
	if res_id == EconomyConfigScript.RES_GOLD:
		return _gold_capacity
	if not _base_capacities.has(res_id):
		return 0
	return int(_base_capacities[res_id])

func get_derived_capacity_bonus(res_id: String) -> int:
	if not _derived_capacity_bonuses.has(res_id):
		return 0
	return int(_derived_capacity_bonuses[res_id])

func get_all_derived_capacity_bonuses() -> Dictionary:
	return _derived_capacity_bonuses.duplicate(true)

## Atomically applies derived building storage capacities across physical resources.
## Explicitly clears previous building-derived capacity bonuses before applying the new derivation
## (`_capacities[res_id] = _base_capacities[res_id] + new_bonus`) so base capacity is added only once
## and repeated reconciliation never accumulates bonuses.
## Never destroys or clamps existing stock if a building removal lowers capacity below current stock;
## instead, marks the affected resource in `_over_capacity_resources` so new inflows are blocked
## until stock is consumed below the new capacity.
func apply_derived_capacities(new_capacities: Variant, new_bonuses: Variant = null) -> Dictionary:
	if not (new_capacities is Dictionary):
		return {"ok": false, "reason": "invalid_capacities_dict"}
	var cap_dict: Dictionary = new_capacities
	var bonus_dict: Dictionary = new_bonuses if (new_bonuses is Dictionary) else {}
	var staged_caps: Dictionary = {}
	var staged_bonuses: Dictionary = {}

	for k in cap_dict.keys():
		var res_id := String(k)
		if not is_valid_physical_resource(res_id) or not _is_valid_strict_int(cap_dict[k]):
			return {"ok": false, "reason": "invalid_resource_or_capacity"}
		var c_val: int = int(cap_dict[k])
		if c_val < 0 or c_val > MAX_SAFE_TRANSACTION_AMOUNT:
			return {"ok": false, "reason": "capacity_out_of_bounds"}
		var base_c: int = int(_base_capacities.get(res_id, EconomyConfigScript.BASE_CAPACITIES.get(res_id, 500)))
		var b_val: int = maxi(0, c_val - base_c)
		if bonus_dict.has(res_id):
			if not _is_valid_strict_int(bonus_dict[res_id]) or int(bonus_dict[res_id]) < 0:
				return {"ok": false, "reason": "invalid_derived_bonus"}
			b_val = int(bonus_dict[res_id])
			c_val = base_c + b_val
		staged_caps[res_id] = c_val
		staged_bonuses[res_id] = b_val

	# Remove previous derived bonuses and apply the new derivation atomically
	for res_id in staged_caps.keys():
		var new_cap: int = int(staged_caps[res_id])
		var new_bon: int = int(staged_bonuses[res_id])
		var cur_s: int = int(_stock.get(res_id, 0))
		_derived_capacity_bonuses[res_id] = new_bon
		_capacities[res_id] = new_cap
		if cur_s > new_cap:
			_over_capacity_resources[res_id] = cur_s - new_cap
		else:
			_over_capacity_resources.erase(res_id)

	return {
		"ok": true,
		"capacities": _capacities.duplicate(true),
		"derived_capacity_bonuses": _derived_capacity_bonuses.duplicate(true),
		"over_capacity_resources": _over_capacity_resources.duplicate(true)
	}

func is_over_capacity(res_id: String) -> bool:
	if not is_valid_physical_resource(res_id):
		return false
	return int(_stock.get(res_id, 0)) > int(_capacities.get(res_id, 0))

func get_over_capacity_resources() -> Dictionary:
	var out: Dictionary = {}
	for res_id in PHYSICAL_RESOURCES:
		var s: int = int(_stock.get(res_id, 0))
		var c: int = int(_capacities.get(res_id, 0))
		if s > c:
			out[res_id] = s - c
	return out

func get_all_resources() -> Dictionary:
	return _stock.duplicate(true)

func get_all_capacities() -> Dictionary:
	return _capacities.duplicate(true)

func get_gold() -> int:
	return _gold

func get_gold_capacity() -> int:
	return _gold_capacity

func has_gold(amount: Variant) -> bool:
	if not _is_valid_strict_int(amount):
		return false
	var req: int = int(amount)
	return req >= 0 and _gold >= req

## Atomically credits a physical resource from an identified source.
## Ordering: Validate -> Calculate -> Mutate -> Commit Ledger -> Notify
func credit_resource(
	res_id: String,
	amount: Variant,
	source: String,
	reason: String = "resource_credit",
	hour_seq: int = 0
) -> Dictionary:
	# 1. Validate
	if not is_valid() or not is_valid_physical_resource(res_id):
		return {"ok": false, "reason": "invalid_resource_id"}
	if not _is_valid_strict_int(amount):
		return {"ok": false, "reason": "invalid_amount_type"}
	var qty: int = int(amount)
	if qty <= 0:
		return {"ok": false, "reason": "non_positive_amount"}
	var clean_src := source.strip_edges()
	var clean_reason := reason.strip_edges()
	if clean_src.is_empty() or clean_reason.is_empty() or hour_seq < 0:
		return {"ok": false, "reason": "invalid_metadata"}
	var cur_bal: int = int(_stock[res_id])
	var cap: int = int(_capacities[res_id])
	# 2. Calculate
	var new_bal: int = cur_bal + qty
	if new_bal > cap:
		return {"ok": false, "reason": "exceeds_capacity"}

	# 3. Mutate authoritative state
	_stock[res_id] = new_bal
	if new_bal <= int(_capacities[res_id]):
		_over_capacity_resources.erase(res_id)
	else:
		_over_capacity_resources[res_id] = new_bal - int(_capacities[res_id])
	_sync_forage_stock_if_needed(res_id)

	# 4. Commit accounting
	var entry: Dictionary = _commit_ledger_inflow(
		res_id,
		qty,
		clean_src,
		"settlement_stock:%s" % res_id,
		clean_reason,
		hour_seq,
		new_bal
	)
	var receipt: Dictionary = {
		"ok": true,
		"tx_id": String(entry.get("tx_id", "")),
		"resource_id": res_id,
		"amount": qty,
		"balance_after": new_bal,
		"source": clean_src,
		"reason": clean_reason,
		"hour_seq": hour_seq
	}
	# 5. Notify
	transaction_committed.emit(receipt.duplicate(true))
	return receipt




## Atomically debits a physical resource to an identified destination.
## Ordering: Validate -> Calculate -> Mutate -> Commit Ledger -> Notify
func debit_resource(
	res_id: String,
	amount: Variant,
	destination: String,
	reason: String = "resource_debit",
	hour_seq: int = 0
) -> Dictionary:
	# 1. Validate
	if not is_valid() or not is_valid_physical_resource(res_id):
		return {"ok": false, "reason": "invalid_resource_id"}
	if not _is_valid_strict_int(amount):
		return {"ok": false, "reason": "invalid_amount_type"}
	var qty: int = int(amount)
	if qty <= 0:
		return {"ok": false, "reason": "non_positive_amount"}
	var clean_dst := destination.strip_edges()
	var clean_reason := reason.strip_edges()
	if clean_dst.is_empty() or clean_reason.is_empty() or hour_seq < 0:
		return {"ok": false, "reason": "invalid_metadata"}
	var cur_bal: int = int(_stock[res_id])
	if cur_bal < qty:
		return {"ok": false, "reason": "insufficient_balance"}

	# 2. Calculate
	var new_bal: int = cur_bal - qty

	# 3. Mutate authoritative state
	_stock[res_id] = new_bal
	if new_bal <= int(_capacities[res_id]):
		_over_capacity_resources.erase(res_id)
	else:
		_over_capacity_resources[res_id] = new_bal - int(_capacities[res_id])
	_sync_forage_stock_if_needed(res_id)

	# 4. Commit accounting
	var entry: Dictionary = _commit_ledger_outflow(
		res_id,
		qty,
		"settlement_stock:%s" % res_id,
		clean_dst,
		clean_reason,
		hour_seq,
		new_bal
	)
	var receipt: Dictionary = {
		"ok": true,
		"tx_id": String(entry.get("tx_id", "")),
		"resource_id": res_id,
		"amount": qty,
		"balance_after": new_bal,
		"destination": clean_dst,
		"reason": clean_reason,
		"hour_seq": hour_seq
	}
	# 5. Notify
	transaction_committed.emit(receipt.duplicate(true))
	return receipt




func credit_gold(
	amount: Variant,
	source: String,
	reason: String = "gold_credit",
	hour_seq: int = 0
) -> Dictionary:
	if not is_valid():
		return {"ok": false, "reason": "invalid_economy"}
	if not _is_valid_strict_int(amount):
		return {"ok": false, "reason": "invalid_amount_type"}
	var qty: int = int(amount)
	if qty <= 0:
		return {"ok": false, "reason": "non_positive_amount"}
	var clean_src := source.strip_edges()
	var clean_reason := reason.strip_edges()
	if clean_src.is_empty() or clean_reason.is_empty() or hour_seq < 0:
		return {"ok": false, "reason": "invalid_metadata"}
	var new_gold: int = _gold + qty
	if new_gold > _gold_capacity:
		return {"ok": false, "reason": "exceeds_gold_capacity"}

	_gold = new_gold
	var entry: Dictionary = _commit_ledger_inflow(
		EconomyConfigScript.RES_GOLD,
		qty,
		clean_src,
		"settlement_treasury",
		clean_reason,
		hour_seq,
		new_gold
	)
	var receipt: Dictionary = {
		"ok": true,
		"tx_id": String(entry.get("tx_id", "")),
		"resource_id": EconomyConfigScript.RES_GOLD,
		"amount": qty,
		"balance_after": new_gold,
		"source": clean_src,
		"reason": clean_reason,
		"hour_seq": hour_seq
	}
	transaction_committed.emit(receipt.duplicate(true))
	return receipt


func debit_gold(
	amount: Variant,
	destination: String,
	reason: String = "gold_debit",
	hour_seq: int = 0
) -> Dictionary:
	if not is_valid():
		return {"ok": false, "reason": "invalid_economy"}
	if not _is_valid_strict_int(amount):
		return {"ok": false, "reason": "invalid_amount_type"}
	var qty: int = int(amount)
	if qty <= 0:
		return {"ok": false, "reason": "non_positive_amount"}
	var clean_dst := destination.strip_edges()
	var clean_reason := reason.strip_edges()
	if clean_dst.is_empty() or clean_reason.is_empty() or hour_seq < 0:
		return {"ok": false, "reason": "invalid_metadata"}
	if _gold < qty:
		return {"ok": false, "reason": "insufficient_gold"}

	var new_gold: int = _gold - qty
	_gold = new_gold
	var entry: Dictionary = _commit_ledger_outflow(
		EconomyConfigScript.RES_GOLD,
		qty,
		"settlement_treasury",
		clean_dst,
		clean_reason,
		hour_seq,
		new_gold
	)
	var receipt: Dictionary = {
		"ok": true,
		"tx_id": String(entry.get("tx_id", "")),
		"resource_id": EconomyConfigScript.RES_GOLD,
		"amount": qty,
		"balance_after": new_gold,
		"destination": clean_dst,
		"reason": clean_reason,
		"hour_seq": hour_seq
	}
	transaction_committed.emit(receipt.duplicate(true))
	return receipt


# -----------------------------------------------------------------------------
# Profile 1: Neutral Tribe — Bounded Local Forage
# -----------------------------------------------------------------------------
func _sync_forage_stock_if_needed(res_id: String) -> void:
	if _economy_profile_id != PROFILE_NEUTRAL_TRIBE or not bool(_forage_provider.get("enabled", false)):
		return
	if res_id != String(_forage_provider.get("resource_id", EconomyConfigScript.RES_FOOD)):
		return
	var max_cap: int = int(_forage_provider.get("max_capacity", DEFAULT_FORAGE_MAX_CAPACITY))
	var cur_food: int = int(_stock.get(res_id, 0))
	_forage_provider["current_stock"] = mini(max_cap, cur_food)
	if cur_food >= max_cap or cur_food >= int(_capacities.get(res_id, 500)):
		_forage_provider["state"] = PROVIDER_STATE_FULL
	else:
		_forage_provider["state"] = PROVIDER_STATE_ACTIVE

func get_forage_provider_state() -> Dictionary:
	return _forage_provider.duplicate(true)

func configure_forage_provider(
	max_capacity: int,
	regen_amount_per_interval: float,
	regen_interval_hours: int
) -> bool:
	if _economy_profile_id != PROFILE_NEUTRAL_TRIBE:
		return false
	if max_capacity < 1 or regen_interval_hours < 1:
		return false
	if is_nan(regen_amount_per_interval) or is_inf(regen_amount_per_interval) or regen_amount_per_interval <= 0.0:
		return false
	var cur_food: int = int(_stock.get(EconomyConfigScript.RES_FOOD, 0))
	if max_capacity < cur_food or max_capacity > int(_capacities.get(EconomyConfigScript.RES_FOOD, 500)):
		return false
	_forage_provider["enabled"] = true
	_forage_provider["max_capacity"] = max_capacity
	_forage_provider["current_stock"] = mini(max_capacity, cur_food)
	_forage_provider["regen_amount_per_interval"] = regen_amount_per_interval
	_forage_provider["regen_interval_hours"] = regen_interval_hours
	_forage_provider["state"] = PROVIDER_STATE_FULL if cur_food >= max_capacity else PROVIDER_STATE_ACTIVE
	return true

## Deterministically processes Neutral Tribe forage regeneration up to `current_hour_seq`.
func process_forage_regeneration(current_hour_seq: int) -> Dictionary:
	# 1. Validate
	if not is_valid() or _economy_profile_id != PROFILE_NEUTRAL_TRIBE:
		return {"ok": false, "reason": "wrong_economy_profile", "added": 0}
	if not bool(_forage_provider.get("enabled", false)):
		return {"ok": false, "reason": "provider_disabled", "added": 0}
	if current_hour_seq < 0:
		return {"ok": false, "reason": "invalid_hour_seq", "added": 0}
	var last_seq: int = int(_forage_provider.get("last_processed_hour_seq", 0))
	if current_hour_seq <= last_seq:
		return {
			"ok": false,
			"reason": "already_processed_hour_seq",
			"added": 0,
			"last_processed_hour_seq": last_seq
		}

	# 2. Calculate elapsed intervals & remainder
	var interval_h: int = maxi(1, int(_forage_provider.get("regen_interval_hours", DEFAULT_FORAGE_INTERVAL_HOURS)))
	var prev_rem_h: int = maxi(0, int(_forage_provider.get("elapsed_hours_remainder", 0)))
	var total_elapsed_h: int = prev_rem_h + (current_hour_seq - last_seq)
	var intervals_due: int = int(total_elapsed_h / interval_h)
	var new_rem_h: int = total_elapsed_h % interval_h

	var res_id: String = String(_forage_provider.get("resource_id", EconomyConfigScript.RES_FOOD))
	var cur_food: int = int(_stock.get(res_id, 0))
	var forage_cap: int = int(_forage_provider.get("max_capacity", DEFAULT_FORAGE_MAX_CAPACITY))
	var storage_cap: int = int(_capacities.get(res_id, 500))
	var eff_cap: int = mini(forage_cap, storage_cap)
	var headroom: int = maxi(0, eff_cap - cur_food)

	if intervals_due <= 0:
		_forage_provider["last_processed_hour_seq"] = current_hour_seq
		_forage_provider["elapsed_hours_remainder"] = new_rem_h
		return {
			"ok": true,
			"reason": "interval_not_yet_elapsed",
			"added": 0,
			"intervals_processed": 0,
			"current_stock": int(_forage_provider.get("current_stock", cur_food)),
			"fractional_remainder": float(_forage_provider.get("fractional_remainder", 0.0)),
			"state": String(_forage_provider.get("state", PROVIDER_STATE_ACTIVE))
		}

	var rate: float = float(_forage_provider.get("regen_amount_per_interval", DEFAULT_FORAGE_REGEN_AMOUNT))
	var prev_frac: float = float(_forage_provider.get("fractional_remainder", 0.0))
	var raw_gen: float = float(intervals_due) * rate + prev_frac
	var whole_gen: int = int(floor(raw_gen + 1e-9))
	var new_frac: float = maxf(0.0, raw_gen - float(whole_gen))

	var added: int = mini(whole_gen, headroom)
	var new_food: int = cur_food + added
	if new_food >= eff_cap:
		# Do not accumulate overflow remainder once capped
		new_frac = 0.0

	# 3. Mutate authoritative state
	_stock[res_id] = new_food
	_forage_provider["current_stock"] = mini(forage_cap, new_food)
	_forage_provider["last_processed_hour_seq"] = current_hour_seq
	_forage_provider["elapsed_hours_remainder"] = new_rem_h
	_forage_provider["fractional_remainder"] = new_frac
	_forage_provider["total_regenerated"] = int(_forage_provider.get("total_regenerated", 0)) + added
	_forage_provider["state"] = PROVIDER_STATE_FULL if new_food >= eff_cap else PROVIDER_STATE_ACTIVE

	# 4. Commit accounting (if resources were added)
	var tx_id: String = ""
	if added > 0:
		var entry: Dictionary = _commit_ledger_inflow(
			res_id,
			added,
			"provider:neutral_tribe_forage",
			"settlement_stock:%s" % res_id,
			"forage_regeneration",
			current_hour_seq,
			new_food
		)
		tx_id = String(entry.get("tx_id", ""))

	var receipt: Dictionary = {
		"ok": true,
		"reason": "regenerated" if added > 0 else ("at_capacity" if headroom == 0 else "fractional_accumulated"),
		"tx_id": tx_id,
		"resource_id": res_id,
		"added": added,
		"intervals_processed": intervals_due,
		"current_stock": int(_forage_provider["current_stock"]),
		"fractional_remainder": new_frac,
		"state": String(_forage_provider["state"]),
		"hour_seq": current_hour_seq
	}
	# 5. Notify
	if added > 0:
		transaction_committed.emit(receipt.duplicate(true))
	return receipt


# -----------------------------------------------------------------------------
# Profile 2: Military — Finite Off-Map Ration Logistics
# -----------------------------------------------------------------------------
func get_military_logistics_state() -> Dictionary:
	return _military_logistics.duplicate(true)

func configure_military_logistics(
	remaining_budget: int,
	max_allocation: int,
	ration_amount_per_delivery: int,
	delivery_interval_hours: int,
	next_delivery_hour_seq: int = -1
) -> bool:
	if _economy_profile_id != PROFILE_MILITARY:
		return false
	if remaining_budget < 0 or max_allocation < 1 or remaining_budget > max_allocation:
		return false
	if ration_amount_per_delivery < 1 or delivery_interval_hours < 1:
		return false
	var tot_del: int = int(_military_logistics.get("total_delivered", 0))
	var tot_top: int = int(_military_logistics.get("total_top_ups", 0))
	if tot_del != 0 or tot_top != 0:
		if remaining_budget != int(_military_logistics.get("remaining_budget", 0)):
			return false
	else:
		_military_logistics["initial_allocation"] = remaining_budget
		_military_logistics["remaining_budget"] = remaining_budget
	_military_logistics["enabled"] = true
	_military_logistics["max_allocation"] = max_allocation
	_military_logistics["ration_amount_per_delivery"] = ration_amount_per_delivery
	_military_logistics["delivery_interval_hours"] = delivery_interval_hours
	if next_delivery_hour_seq >= 1:
		_military_logistics["next_delivery_hour_seq"] = next_delivery_hour_seq
	_military_logistics["state"] = PROVIDER_STATE_DEPLETED if remaining_budget == 0 else PROVIDER_STATE_ACTIVE
	return true

## Processes due Military off-map ration deliveries at `current_hour_seq`.
## Never debits FactionData.resources. Preserves finite budget when settlement storage is full.
func process_military_logistics(current_hour_seq: Variant) -> Dictionary:
	# 1. Validate
	if not is_valid() or _economy_profile_id != PROFILE_MILITARY:
		return {"ok": false, "reason": "wrong_economy_profile", "delivered": 0}
	if not bool(_military_logistics.get("enabled", false)):
		return {"ok": false, "reason": "provider_disabled", "delivered": 0}
	if not _is_valid_strict_int(current_hour_seq) or int(current_hour_seq) < 0:
		return {"ok": false, "reason": "invalid_hour_seq", "delivered": 0}
	var h_seq: int = int(current_hour_seq)

	var last_done: int = int(_military_logistics.get("last_completed_delivery_hour_seq", 0))
	var next_due: int = int(_military_logistics.get("next_delivery_hour_seq", DEFAULT_MILITARY_DELIVERY_INTERVAL_HOURS))
	if h_seq <= last_done or h_seq < next_due:
		return {
			"ok": false,
			"reason": "not_due_or_already_processed",
			"delivered": 0,
			"next_delivery_hour_seq": next_due,
			"last_completed_delivery_hour_seq": last_done,
			"state": String(_military_logistics.get("state", PROVIDER_STATE_ACTIVE))
		}

	var rem_budget: int = int(_military_logistics.get("remaining_budget", 0))
	if rem_budget <= 0:
		_military_logistics["state"] = PROVIDER_STATE_DEPLETED
		return {
			"ok": false,
			"reason": "budget_depleted",
			"delivered": 0,
			"remaining_budget": 0,
			"state": PROVIDER_STATE_DEPLETED
		}

	var res_id: String = String(_military_logistics.get("resource_id", EconomyConfigScript.RES_FOOD))
	var cur_stock: int = int(_stock.get(res_id, 0))
	var cap: int = int(_capacities.get(res_id, 500))
	var headroom: int = maxi(0, cap - cur_stock)
	var ration_amt: int = maxi(1, int(_military_logistics.get("ration_amount_per_delivery", DEFAULT_MILITARY_RATION_DELIVERY_AMOUNT)))
	var interval_h: int = maxi(1, int(_military_logistics.get("delivery_interval_hours", DEFAULT_MILITARY_DELIVERY_INTERVAL_HOURS)))

	var single_batch: int = mini(ration_amt, rem_budget)
	if headroom <= 0 or headroom < single_batch:
		# Capacity is full or cannot fit a delivery batch: do NOT discard logistics budget
		_military_logistics["state"] = PROVIDER_STATE_WAITING_CAPACITY
		return {
			"ok": false,
			"reason": "waiting_capacity",
			"delivered": 0,
			"remaining_budget": rem_budget,
			"state": PROVIDER_STATE_WAITING_CAPACITY
		}

	# 2. Calculate due deliveries within budget and capacity
	var due_intervals: int = 1 + int((h_seq - next_due) / interval_h)
	var total_delivered: int = 0
	var intervals_completed: int = 0
	var temp_budget: int = rem_budget
	var temp_headroom: int = headroom

	for _i in range(due_intervals):
		if temp_budget <= 0:
			break
		var batch: int = mini(ration_amt, temp_budget)
		if temp_headroom < batch:
			break
		total_delivered += batch
		temp_budget -= batch
		temp_headroom -= batch
		intervals_completed += 1

	var new_stock: int = cur_stock + total_delivered
	var new_next_due: int = next_due + intervals_completed * interval_h
	var new_state: String = PROVIDER_STATE_ACTIVE
	var new_last_done: int = h_seq
	if temp_budget == 0:
		new_state = PROVIDER_STATE_DEPLETED
	elif intervals_completed < due_intervals and temp_headroom < mini(ration_amt, temp_budget):
		new_state = PROVIDER_STATE_WAITING_CAPACITY
		new_last_done = next_due + (intervals_completed - 1) * interval_h

	# 3. Mutate authoritative state
	_stock[res_id] = new_stock
	_military_logistics["remaining_budget"] = temp_budget
	_military_logistics["last_completed_delivery_hour_seq"] = new_last_done
	_military_logistics["next_delivery_hour_seq"] = new_next_due
	_military_logistics["total_delivered"] = int(_military_logistics.get("total_delivered", 0)) + total_delivered
	_military_logistics["state"] = new_state

	# 4. Commit accounting
	var entry: Dictionary = _commit_ledger_inflow(
		res_id,
		total_delivered,
		"provider:military_offmap_logistics",
		"settlement_stock:%s" % res_id,
		"military_ration_delivery",
		h_seq,
		new_stock
	)
	var receipt: Dictionary = {
		"ok": true,
		"tx_id": String(entry.get("tx_id", "")),
		"resource_id": res_id,
		"delivered": total_delivered,
		"intervals_completed": intervals_completed,
		"remaining_budget": temp_budget,
		"balance_after": new_stock,
		"next_delivery_hour_seq": new_next_due,
		"state": new_state,
		"hour_seq": h_seq
	}
	# 5. Notify
	transaction_committed.emit(receipt.duplicate(true))
	return receipt




## Explicit external recovery/top-up for Military off-map ration logistics budget.
## Requires a valid external `source` and unique `grant_id` (defaults to `source` when omitted).
## Enforces idempotency against duplicate grants, current `max_allocation`, and lifetime `max_cumulative_top_ups`.
func top_up_military_logistics(
	amount: Variant,
	source: String,
	hour_seq: Variant = 0,
	grant_id: String = ""
) -> Dictionary:
	if not is_valid() or _economy_profile_id != PROFILE_MILITARY:
		return {"ok": false, "reason": "wrong_economy_profile"}
	if not bool(_military_logistics.get("enabled", false)):
		return {"ok": false, "reason": "provider_disabled"}
	if not _is_valid_strict_int(amount) or not _is_valid_strict_int(hour_seq):
		return {"ok": false, "reason": "invalid_amount_type"}
	var qty: int = int(amount)
	var h_seq: int = int(hour_seq)
	var clean_src := source.strip_edges()
	var clean_grant := grant_id.strip_edges() if not grant_id.strip_edges().is_empty() else clean_src
	if qty <= 0 or clean_src.is_empty() or clean_grant.is_empty() or h_seq < 0:
		return {"ok": false, "reason": "invalid_top_up_input"}
	if not SettlementVillagerDataScript.is_valid_identifier(clean_grant):
		return {"ok": false, "reason": "invalid_grant_id"}
	var grants_map: Dictionary = _military_logistics.get("processed_grant_ids", {})
	if grants_map.has(clean_grant):
		return {"ok": false, "reason": "duplicate_grant_id", "grant_id": clean_grant}

	var cur_budget: int = int(_military_logistics.get("remaining_budget", 0))
	var max_alloc: int = int(_military_logistics.get("max_allocation", DEFAULT_MILITARY_LOGISTICS_MAX_ALLOCATION))
	if cur_budget + qty > max_alloc:
		return {"ok": false, "reason": "exceeds_max_allocation"}
	var cur_top_ups: int = int(_military_logistics.get("total_top_ups", 0))
	var max_cum_top: int = int(_military_logistics.get("max_cumulative_top_ups", DEFAULT_MILITARY_LOGISTICS_MAX_CUMULATIVE_TOP_UPS))
	if cur_top_ups + qty > max_cum_top:
		return {"ok": false, "reason": "exceeds_max_cumulative_top_ups"}

	var new_budget: int = cur_budget + qty
	var interval_h: int = maxi(1, int(_military_logistics.get("delivery_interval_hours", DEFAULT_MILITARY_DELIVERY_INTERVAL_HOURS)))
	var next_due: int = int(_military_logistics.get("next_delivery_hour_seq", interval_h))
	if cur_budget == 0 and h_seq >= next_due:
		_military_logistics["next_delivery_hour_seq"] = (int(h_seq / interval_h) + 1) * interval_h
	_military_logistics["remaining_budget"] = new_budget
	_military_logistics["total_top_ups"] = cur_top_ups + qty
	_military_logistics["processed_grant_ids"][clean_grant] = {
		"amount": qty,
		"source": clean_src,
		"hour_seq": h_seq
	}
	_military_logistics["state"] = PROVIDER_STATE_ACTIVE

	var entry: Dictionary = _commit_ledger_provider_event(
		String(_military_logistics.get("resource_id", EconomyConfigScript.RES_FOOD)),
		qty,
		clean_src,
		"provider:military_offmap_logistics",
		"military_logistics_top_up",
		h_seq,
		new_budget
	)
	var receipt: Dictionary = {
		"ok": true,
		"tx_id": String(entry.get("tx_id", "")),
		"grant_id": clean_grant,
		"added_budget": qty,
		"remaining_budget": new_budget,
		"source": clean_src,
		"state": PROVIDER_STATE_ACTIVE,
		"hour_seq": h_seq
	}
	transaction_committed.emit(receipt.duplicate(true))
	return receipt


# -----------------------------------------------------------------------------
# Profile 3: Merchant — Finite Market Pool and Local Gold Purchase
# -----------------------------------------------------------------------------
func get_market_provider_state() -> Dictionary:
	return _market_provider.duplicate(true)

func get_market_stock(res_id: String) -> int:
	var s_map: Dictionary = _market_provider.get("stock", {})
	return int(s_map.get(res_id, 0))

func get_market_capacity(res_id: String) -> int:
	var c_map: Dictionary = _market_provider.get("capacity", {})
	return int(c_map.get(res_id, 0))

func set_market_capacity(res_id: String, new_capacity: Variant) -> bool:
	if _economy_profile_id != PROFILE_MERCHANT or not MERCHANT_MARKET_RESOURCES.has(res_id):
		return false
	if not _is_valid_strict_int(new_capacity):
		return false
	var cap: int = int(new_capacity)
	if cap < 0 or cap < get_market_stock(res_id) or cap > MAX_SAFE_TRANSACTION_AMOUNT:
		return false
	_market_provider["capacity"][res_id] = cap
	_refresh_market_provider_state()
	return true

func get_market_remaining_allocation(res_id: String) -> int:
	var a_map: Dictionary = _market_provider.get("remaining_restock_allocation", {})
	return int(a_map.get(res_id, 0))

func get_market_price(res_id: String) -> int:
	var p_map: Dictionary = _market_provider.get("prices", {})
	return int(p_map.get(res_id, -1))

## Explicit scenario/settlement configuration API to override a market resource's authoritative unit price.
## Accepts only approved Merchant market resources and strict positive integers in [1, MAX_SAFE_TRANSACTION_AMOUNT].
func set_market_price(res_id: String, unit_price: Variant) -> bool:
	if _economy_profile_id != PROFILE_MERCHANT or not MERCHANT_MARKET_RESOURCES.has(res_id):
		return false
	if not _is_valid_strict_int(unit_price):
		return false
	var p: int = int(unit_price)
	if p < 1 or p > MAX_SAFE_TRANSACTION_AMOUNT:
		return false
	_market_provider["prices"][res_id] = p
	return true

## Atomically executes a Merchant purchase from the settlement's finite market pool using local gold.
## Signature contract:
##   - `res_id`: market resource identifier (`food`, `wood`, `stone`, `metal`, `tools`, `herbs`, `crystal`).
##   - `quantity`: positive integer quantity to purchase.
##   - `hour_seq`: simulation hour sequence (`>= 0`) recorded in the ledger for this transaction.
##   - `caller_unit_price`: optional caller-quoted unit price. When `null` (default), uses the authoritative
##     market price from `_market_provider["prices"][res_id]`. When provided, must be a positive integer
##     strictly equal to the authoritative market price; lower, higher, non-positive, or non-integer values
##     are rejected before any state mutation.
## Follows the 11-step atomic contract (Validate 1–5 -> Calculate 6 -> Mutate 7–9 -> Commit 10 -> Return 11).
func purchase_from_market(
	res_id: String,
	quantity: Variant,
	hour_seq: Variant = 0,
	caller_unit_price: Variant = null
) -> Dictionary:
	# 1. Validate profile, provider enabled, requested resource, and hour_seq
	if not is_valid() or _economy_profile_id != PROFILE_MERCHANT:
		return {"ok": false, "reason": "wrong_economy_profile"}
	if not bool(_market_provider.get("enabled", false)):
		return {"ok": false, "reason": "market_disabled"}
	if not MERCHANT_MARKET_RESOURCES.has(res_id) or not is_valid_physical_resource(res_id):
		return {"ok": false, "reason": "invalid_market_resource"}
	if not _is_valid_strict_int(hour_seq) or int(hour_seq) < 0:
		return {"ok": false, "reason": "invalid_hour_seq"}
	var h_seq: int = int(hour_seq)

	# 2. Validate quantity, authoritative unit price, optional caller quote, and overflow bounds
	if not _is_valid_strict_int(quantity):
		return {"ok": false, "reason": "invalid_quantity_type"}
	var qty: int = int(quantity)
	if qty <= 0:
		return {"ok": false, "reason": "non_positive_quantity"}
	var unit_price: int = get_market_price(res_id)
	if unit_price < 1:
		return {"ok": false, "reason": "invalid_price"}
	if caller_unit_price != null:
		if not _is_valid_strict_int(caller_unit_price):
			return {"ok": false, "reason": "invalid_caller_price_type"}
		var quoted_p: int = int(caller_unit_price)
		if quoted_p <= 0:
			return {"ok": false, "reason": "non_positive_price"}
		if quoted_p < unit_price:
			return {"ok": false, "reason": "price_below_configured_market_price"}
		if quoted_p > unit_price:
			return {"ok": false, "reason": "price_mismatch_with_configured_market_price"}
	if qty > MAX_SAFE_TRANSACTION_AMOUNT or unit_price > MAX_SAFE_TRANSACTION_AMOUNT or qty > int(MAX_SAFE_TRANSACTION_AMOUNT / unit_price):
		return {"ok": false, "reason": "transaction_cost_overflow"}

	# 3. Validate market provider inventory
	var cur_market_stock: int = get_market_stock(res_id)
	if cur_market_stock < qty:
		return {"ok": false, "reason": "insufficient_market_stock"}

	# 4 & 6. Calculate total transaction cost and validate local gold
	var total_cost: int = qty * unit_price
	if total_cost <= 0:
		return {"ok": false, "reason": "transaction_cost_overflow"}
	if _gold < total_cost:
		return {"ok": false, "reason": "insufficient_local_gold"}

	# 5. Validate destination settlement resource capacity
	var cur_stl_stock: int = int(_stock.get(res_id, 0))
	var stl_cap: int = int(_capacities.get(res_id, 0))
	if cur_stl_stock + qty > stl_cap:
		return {"ok": false, "reason": "insufficient_settlement_capacity"}

	# 7. Commit market stock reduction
	var new_market_stock: int = cur_market_stock - qty
	_market_provider["stock"][res_id] = new_market_stock
	_market_provider["total_purchased"][res_id] = int(_market_provider["total_purchased"].get(res_id, 0)) + qty
	_refresh_market_provider_state()

	# 8. Commit local gold reduction
	var new_gold: int = _gold - total_cost
	_gold = new_gold

	# 9. Commit settlement inventory increase
	var new_stl_stock: int = cur_stl_stock + qty
	_stock[res_id] = new_stl_stock

	# 10. Commit all associated ledger entries
	var gold_entry: Dictionary = _commit_ledger_outflow(
		EconomyConfigScript.RES_GOLD,
		total_cost,
		"settlement_treasury",
		"provider:merchant_market",
		"market_purchase_payment",
		h_seq,
		new_gold
	)
	var goods_entry: Dictionary = _commit_ledger_inflow(
		res_id,
		qty,
		"provider:merchant_market",
		"settlement_stock:%s" % res_id,
		"market_purchase_goods",
		h_seq,
		new_stl_stock
	)

	# 11. Return deterministic receipt & notify
	var receipt: Dictionary = {
		"ok": true,
		"resource_id": res_id,
		"quantity": qty,
		"unit_price": unit_price,
		"total_cost": total_cost,
		"gold_after": new_gold,
		"settlement_stock_after": new_stl_stock,
		"market_stock_after": new_market_stock,
		"gold_tx_id": String(gold_entry.get("tx_id", "")),
		"goods_tx_id": String(goods_entry.get("tx_id", "")),
		"hour_seq": h_seq
	}
	transaction_committed.emit(receipt.duplicate(true))
	return receipt


func _refresh_market_provider_state() -> void:
	if not bool(_market_provider.get("enabled", false)):
		_market_provider["state"] = PROVIDER_STATE_DISABLED
		return
	var rem_map: Dictionary = _market_provider.get("remaining_restock_allocation", {})
	var stock_map: Dictionary = _market_provider.get("stock", {})
	var cap_map: Dictionary = _market_provider.get("capacity", {})
	var total_rem: int = 0
	var any_can_fit: bool = false
	for res_id in MERCHANT_MARKET_RESOURCES:
		var r_alloc: int = int(rem_map.get(res_id, 0))
		total_rem += r_alloc
		if r_alloc > 0 and int(stock_map.get(res_id, 0)) < int(cap_map.get(res_id, 0)):
			any_can_fit = true
	if total_rem <= 0:
		_market_provider["state"] = PROVIDER_STATE_DEPLETED
	elif not any_can_fit:
		_market_provider["state"] = PROVIDER_STATE_WAITING_CAPACITY
	else:
		_market_provider["state"] = PROVIDER_STATE_ACTIVE

## Deterministically processes due Merchant market restocks from finite external restock allocations.
## Steps interval-by-interval so that when market capacity blocks further restocking midway through
## a multi-interval jump, the remaining due intervals stay pending and can be completed once capacity frees up.
func process_market_restock(current_hour_seq: Variant) -> Dictionary:
	if not is_valid() or _economy_profile_id != PROFILE_MERCHANT:
		return {"ok": false, "reason": "wrong_economy_profile", "total_restocked": 0}
	if not bool(_market_provider.get("enabled", false)):
		return {"ok": false, "reason": "market_disabled", "total_restocked": 0}
	if not _is_valid_strict_int(current_hour_seq) or int(current_hour_seq) < 0:
		return {"ok": false, "reason": "invalid_hour_seq", "total_restocked": 0}
	var h_seq: int = int(current_hour_seq)

	var last_done: int = int(_market_provider.get("last_completed_restock_hour_seq", 0))
	var next_due: int = int(_market_provider.get("next_restock_hour_seq", DEFAULT_MERCHANT_RESTOCK_INTERVAL_HOURS))
	if h_seq <= last_done or h_seq < next_due:
		return {
			"ok": false,
			"reason": "not_due_or_already_processed",
			"total_restocked": 0,
			"next_restock_hour_seq": next_due,
			"last_completed_restock_hour_seq": last_done,
			"state": String(_market_provider.get("state", PROVIDER_STATE_ACTIVE))
		}

	var rem_map: Dictionary = _market_provider["remaining_restock_allocation"]
	var stock_map: Dictionary = _market_provider["stock"]
	var cap_map: Dictionary = _market_provider["capacity"]
	var rate_map: Dictionary = _market_provider["restock_amount_per_interval"]
	var interval_h: int = maxi(1, int(_market_provider.get("restock_interval_hours", DEFAULT_MERCHANT_RESTOCK_INTERVAL_HOURS)))

	var total_rem_before: int = 0
	for res_id in MERCHANT_MARKET_RESOURCES:
		total_rem_before += int(rem_map.get(res_id, 0))
	if total_rem_before <= 0:
		_market_provider["state"] = PROVIDER_STATE_DEPLETED
		return {
			"ok": false,
			"reason": "allocation_depleted",
			"total_restocked": 0,
			"state": PROVIDER_STATE_DEPLETED
		}

	var due_intervals: int = 1 + int((h_seq - next_due) / interval_h)
	var restocked_by_res: Dictionary = {}
	var total_restocked: int = 0
	var intervals_completed: int = 0
	var blocked_by_capacity: bool = false

	for _i in range(due_intervals):
		var any_alloc_left: bool = false
		var interval_added: int = 0

		for res_id in MERCHANT_MARKET_RESOURCES:
			var rem_alloc: int = int(rem_map.get(res_id, 0))
			var per_int: int = maxi(0, int(rate_map.get(res_id, 0)))
			if rem_alloc <= 0 or per_int <= 0:
				continue
			any_alloc_left = true
			var cur_m_stock: int = int(stock_map.get(res_id, 0))
			var m_cap: int = int(cap_map.get(res_id, 0))
			var headroom: int = maxi(0, m_cap - cur_m_stock)
			var batch: int = mini(per_int, rem_alloc)
			var add_qty: int = mini(batch, headroom)
			if add_qty > 0:
				stock_map[res_id] = cur_m_stock + add_qty
				rem_map[res_id] = rem_alloc - add_qty
				_market_provider["total_restocked"][res_id] = int(_market_provider["total_restocked"].get(res_id, 0)) + add_qty
				restocked_by_res[res_id] = int(restocked_by_res.get(res_id, 0)) + add_qty
				total_restocked += add_qty
				interval_added += add_qty

		if not any_alloc_left:
			break
		if interval_added == 0:
			blocked_by_capacity = true
			break
		intervals_completed += 1

	if total_restocked == 0:
		# Market is full for all remaining allocated goods; do not consume allocation or schedule
		_market_provider["state"] = PROVIDER_STATE_WAITING_CAPACITY
		return {
			"ok": false,
			"reason": "waiting_capacity",
			"total_restocked": 0,
			"intervals_completed": 0,
			"next_restock_hour_seq": next_due,
			"last_completed_restock_hour_seq": last_done,
			"state": PROVIDER_STATE_WAITING_CAPACITY
		}

	for res_id in MERCHANT_MARKET_RESOURCES:
		if restocked_by_res.has(res_id):
			_commit_ledger_provider_event(
				res_id,
				int(restocked_by_res[res_id]),
				"provider:external_merchant_caravan_supply",
				"provider:merchant_market",
				"market_restock",
				h_seq,
				int(stock_map[res_id])
			)

	var new_next_due: int = next_due + intervals_completed * interval_h
	var new_last_done: int = h_seq
	_refresh_market_provider_state()
	if intervals_completed < due_intervals and (blocked_by_capacity or String(_market_provider["state"]) == PROVIDER_STATE_WAITING_CAPACITY):
		_market_provider["state"] = PROVIDER_STATE_WAITING_CAPACITY
		new_last_done = next_due + (intervals_completed - 1) * interval_h

	_market_provider["last_completed_restock_hour_seq"] = new_last_done
	_market_provider["next_restock_hour_seq"] = new_next_due

	var receipt: Dictionary = {
		"ok": true,
		"total_restocked": total_restocked,
		"intervals_completed": intervals_completed,
		"restocked_by_resource": restocked_by_res,
		"next_restock_hour_seq": new_next_due,
		"last_completed_restock_hour_seq": new_last_done,
		"state": String(_market_provider["state"]),
		"hour_seq": h_seq
	}
	transaction_committed.emit(receipt.duplicate(true))
	return receipt


## Explicit external recovery/top-up for Merchant market restock allocation.
## Requires a valid external `source` and unique `grant_id` (defaults to `source` when omitted).
## Enforces idempotency against duplicate grants, current `max_restock_allocation`, and lifetime `max_cumulative_top_ups`.
func top_up_market_allocation(
	res_id: String,
	amount: Variant,
	source: String,
	hour_seq: Variant = 0,
	grant_id: String = ""
) -> Dictionary:
	if not is_valid() or _economy_profile_id != PROFILE_MERCHANT:
		return {"ok": false, "reason": "wrong_economy_profile"}
	if not bool(_market_provider.get("enabled", false)):
		return {"ok": false, "reason": "market_disabled"}
	if not MERCHANT_MARKET_RESOURCES.has(res_id):
		return {"ok": false, "reason": "invalid_market_resource"}
	if not _is_valid_strict_int(amount) or not _is_valid_strict_int(hour_seq):
		return {"ok": false, "reason": "invalid_amount_type"}
	var qty: int = int(amount)
	var h_seq: int = int(hour_seq)
	var clean_src := source.strip_edges()
	var clean_grant := grant_id.strip_edges() if not grant_id.strip_edges().is_empty() else clean_src
	if qty <= 0 or clean_src.is_empty() or clean_grant.is_empty() or h_seq < 0:
		return {"ok": false, "reason": "invalid_top_up_input"}
	if not SettlementVillagerDataScript.is_valid_identifier(clean_grant):
		return {"ok": false, "reason": "invalid_grant_id"}
	var grants_map: Dictionary = _market_provider.get("processed_grant_ids", {})
	if grants_map.has(clean_grant):
		return {"ok": false, "reason": "duplicate_grant_id", "grant_id": clean_grant}

	var cur_alloc: int = int(_market_provider["remaining_restock_allocation"].get(res_id, 0))
	var max_alloc: int = int(_market_provider["max_restock_allocation"].get(res_id, 0))
	if cur_alloc + qty > max_alloc:
		return {"ok": false, "reason": "exceeds_max_allocation"}
	var cur_top_ups: int = int(_market_provider["total_allocation_top_ups"].get(res_id, 0))
	var max_cum_top: int = int(_market_provider.get("max_cumulative_top_ups", {}).get(res_id, max_alloc))
	if cur_top_ups + qty > max_cum_top:
		return {"ok": false, "reason": "exceeds_max_cumulative_top_ups"}

	var was_depleted: bool = (String(_market_provider.get("state", "")) == PROVIDER_STATE_DEPLETED)
	var new_alloc: int = cur_alloc + qty
	_market_provider["remaining_restock_allocation"][res_id] = new_alloc
	_market_provider["total_allocation_top_ups"][res_id] = cur_top_ups + qty
	_market_provider["processed_grant_ids"][clean_grant] = {
		"resource_id": res_id,
		"amount": qty,
		"source": clean_src,
		"hour_seq": h_seq
	}
	var interval_h: int = maxi(1, int(_market_provider.get("restock_interval_hours", DEFAULT_MERCHANT_RESTOCK_INTERVAL_HOURS)))
	var next_due: int = int(_market_provider.get("next_restock_hour_seq", interval_h))
	if was_depleted and h_seq >= next_due:
		_market_provider["next_restock_hour_seq"] = (int(h_seq / interval_h) + 1) * interval_h
	_refresh_market_provider_state()

	var entry: Dictionary = _commit_ledger_provider_event(
		res_id,
		qty,
		clean_src,
		"provider:merchant_market_allocation",
		"market_allocation_top_up",
		h_seq,
		new_alloc
	)
	var receipt: Dictionary = {
		"ok": true,
		"tx_id": String(entry.get("tx_id", "")),
		"grant_id": clean_grant,
		"resource_id": res_id,
		"added_allocation": qty,
		"remaining_allocation": new_alloc,
		"source": clean_src,
		"state": String(_market_provider["state"]),
		"hour_seq": h_seq
	}
	transaction_committed.emit(receipt.duplicate(true))
	return receipt


## Atomically delivers due Military off-map rations directly into a receiving workplace buffer
## (e.g. Military Full `mil_hq` Barracks buffer) instead of final settlement stock.
## Debits logistics budget, updates delivery schedule, credits `workplace.buffer_amount`, records
## pending buffer provenance and ledger provider event, and emits `transaction_committed` as one transaction.
func process_military_logistics_to_buffer(
	current_hour_seq: Variant,
	workplace: RefCounted,
	effective_buffer_cap: int
) -> Dictionary:
	if not is_valid() or _economy_profile_id != PROFILE_MILITARY:
		return {"ok": false, "reason": "wrong_economy_profile", "delivered": 0}
	if not bool(_military_logistics.get("enabled", false)):
		return {"ok": false, "reason": "provider_disabled", "delivered": 0}
	if not _is_valid_strict_int(current_hour_seq) or int(current_hour_seq) < 0:
		return {"ok": false, "reason": "invalid_hour_seq", "delivered": 0}
	if workplace == null or workplace.settlement_id != _settlement_id or workplace.is_dropoff:
		return {"ok": false, "reason": "invalid_receiving_buffer", "delivered": 0}
	if effective_buffer_cap <= 0:
		return {"ok": false, "reason": "non_positive_buffer_capacity", "delivered": 0}
	var h_seq: int = int(current_hour_seq)

	var last_done: int = int(_military_logistics.get("last_completed_delivery_hour_seq", 0))
	var next_due: int = int(_military_logistics.get("next_delivery_hour_seq", DEFAULT_MILITARY_DELIVERY_INTERVAL_HOURS))
	if h_seq <= last_done or h_seq < next_due:
		return {
			"ok": false,
			"reason": "not_due_or_already_processed",
			"delivered": 0,
			"next_delivery_hour_seq": next_due,
			"last_completed_delivery_hour_seq": last_done,
			"state": String(_military_logistics.get("state", PROVIDER_STATE_ACTIVE))
		}

	var rem_budget: int = int(_military_logistics.get("remaining_budget", 0))
	if rem_budget <= 0:
		_military_logistics["state"] = PROVIDER_STATE_DEPLETED
		return {"ok": false, "reason": "budget_depleted", "delivered": 0, "remaining_budget": 0, "state": PROVIDER_STATE_DEPLETED}

	var res_id: String = String(_military_logistics.get("resource_id", EconomyConfigScript.RES_FOOD))
	var cur_buf: int = int(workplace.buffer_amount)
	var headroom: int = maxi(0, effective_buffer_cap - cur_buf)
	var ration_amt: int = maxi(1, int(_military_logistics.get("ration_amount_per_delivery", DEFAULT_MILITARY_RATION_DELIVERY_AMOUNT)))
	var interval_h: int = maxi(1, int(_military_logistics.get("delivery_interval_hours", DEFAULT_MILITARY_DELIVERY_INTERVAL_HOURS)))

	var single_batch: int = mini(ration_amt, rem_budget)
	if headroom <= 0 or headroom < single_batch:
		_military_logistics["state"] = PROVIDER_STATE_WAITING_CAPACITY
		return {
			"ok": false,
			"reason": "waiting_capacity",
			"delivered": 0,
			"remaining_budget": rem_budget,
			"state": PROVIDER_STATE_WAITING_CAPACITY
		}

	var due_intervals: int = 1 + int((h_seq - next_due) / interval_h)
	var total_delivered: int = 0
	var intervals_completed: int = 0
	var temp_budget: int = rem_budget
	var temp_headroom: int = headroom
	for _i in range(due_intervals):
		if temp_budget <= 0:
			break
		var batch: int = mini(ration_amt, temp_budget)
		if temp_headroom < batch:
			break
		total_delivered += batch
		temp_budget -= batch
		temp_headroom -= batch
		intervals_completed += 1

	var new_buf: int = cur_buf + total_delivered
	var new_next_due: int = next_due + intervals_completed * interval_h
	var new_state: String = PROVIDER_STATE_ACTIVE
	var new_last_done: int = h_seq
	if temp_budget == 0:
		new_state = PROVIDER_STATE_DEPLETED
	elif intervals_completed < due_intervals and temp_headroom < mini(ration_amt, temp_budget):
		new_state = PROVIDER_STATE_WAITING_CAPACITY
		new_last_done = next_due + (intervals_completed - 1) * interval_h

	# Mutate all authoritative state together
	workplace.buffer_amount = new_buf
	workplace.buffer_capacity = maxi(effective_buffer_cap, new_buf)
	_military_logistics["remaining_budget"] = temp_budget
	_military_logistics["last_completed_delivery_hour_seq"] = new_last_done
	_military_logistics["next_delivery_hour_seq"] = new_next_due
	_military_logistics["total_delivered"] = int(_military_logistics.get("total_delivered", 0)) + total_delivered
	_military_logistics["state"] = new_state
	if not _pending_buffer_deliveries.has("provider:military_offmap_logistics"):
		_pending_buffer_deliveries["provider:military_offmap_logistics"] = {}
	var mil_pend: Dictionary = _pending_buffer_deliveries["provider:military_offmap_logistics"]
	mil_pend[res_id] = int(mil_pend.get(res_id, 0)) + total_delivered

	var entry: Dictionary = _commit_ledger_provider_event(
		res_id,
		total_delivered,
		"provider:military_offmap_logistics",
		"workplace_buffer:%s" % workplace.workplace_id,
		"military_ration_delivery_to_buffer",
		h_seq,
		new_buf
	)
	var receipt: Dictionary = {
		"ok": true,
		"tx_id": String(entry.get("tx_id", "")),
		"resource_id": res_id,
		"delivered": total_delivered,
		"intervals_completed": intervals_completed,
		"remaining_budget": temp_budget,
		"buffer_after": new_buf,
		"workplace_id": workplace.workplace_id,
		"next_delivery_hour_seq": new_next_due,
		"state": new_state,
		"hour_seq": h_seq
	}
	transaction_committed.emit(receipt.duplicate(true))
	return receipt

## Atomically purchases from the finite Merchant market pool and delivers directly into a
## Market receiving buffer (`workplace.is_dropoff == false`) so a Hauler moves it to Storehouse.
func purchase_from_market_to_buffer(
	res_id: String,
	quantity: Variant,
	hour_seq: Variant,
	workplace: RefCounted,
	effective_buffer_cap: int,
	caller_unit_price: Variant = null
) -> Dictionary:
	if not is_valid() or _economy_profile_id != PROFILE_MERCHANT:
		return {"ok": false, "reason": "wrong_economy_profile"}
	if not bool(_market_provider.get("enabled", false)):
		return {"ok": false, "reason": "market_disabled"}
	if not MERCHANT_MARKET_RESOURCES.has(res_id) or not is_valid_physical_resource(res_id):
		return {"ok": false, "reason": "invalid_market_resource"}
	if not _is_valid_strict_int(hour_seq) or int(hour_seq) < 0:
		return {"ok": false, "reason": "invalid_hour_seq"}
	if workplace == null or workplace.settlement_id != _settlement_id or workplace.is_dropoff:
		return {"ok": false, "reason": "invalid_receiving_buffer"}
	if effective_buffer_cap <= 0:
		return {"ok": false, "reason": "non_positive_buffer_capacity"}
	var h_seq: int = int(hour_seq)

	if not _is_valid_strict_int(quantity):
		return {"ok": false, "reason": "invalid_quantity_type"}
	var qty: int = int(quantity)
	if qty <= 0:
		return {"ok": false, "reason": "non_positive_quantity"}
	var unit_price: int = get_market_price(res_id)
	if unit_price < 1:
		return {"ok": false, "reason": "invalid_price"}
	if caller_unit_price != null:
		if not _is_valid_strict_int(caller_unit_price):
			return {"ok": false, "reason": "invalid_caller_price_type"}
		var quoted_p: int = int(caller_unit_price)
		if quoted_p <= 0:
			return {"ok": false, "reason": "non_positive_price"}
		if quoted_p != unit_price:
			return {"ok": false, "reason": "price_mismatch_with_configured_market_price"}
	if qty > MAX_SAFE_TRANSACTION_AMOUNT or unit_price > MAX_SAFE_TRANSACTION_AMOUNT or qty > int(MAX_SAFE_TRANSACTION_AMOUNT / unit_price):
		return {"ok": false, "reason": "transaction_cost_overflow"}

	var cur_market_stock: int = get_market_stock(res_id)
	if cur_market_stock < qty:
		return {"ok": false, "reason": "insufficient_market_stock"}

	var total_cost: int = qty * unit_price
	if total_cost <= 0 or _gold < total_cost:
		return {"ok": false, "reason": "insufficient_local_gold"}

	var cur_buf: int = int(workplace.buffer_amount)
	if cur_buf + qty > effective_buffer_cap:
		return {"ok": false, "reason": "insufficient_receiving_buffer_capacity"}

	var new_market_stock: int = cur_market_stock - qty
	_market_provider["stock"][res_id] = new_market_stock
	_market_provider["total_purchased"][res_id] = int(_market_provider["total_purchased"].get(res_id, 0)) + qty
	_refresh_market_provider_state()

	var new_gold: int = _gold - total_cost
	_gold = new_gold

	var new_buf: int = cur_buf + qty
	workplace.buffer_amount = new_buf
	workplace.buffer_capacity = maxi(effective_buffer_cap, new_buf)

	if not _pending_buffer_deliveries.has("provider:merchant_market"):
		_pending_buffer_deliveries["provider:merchant_market"] = {}
	var mkt_pend: Dictionary = _pending_buffer_deliveries["provider:merchant_market"]
	mkt_pend[res_id] = int(mkt_pend.get(res_id, 0)) + qty

	var gold_entry: Dictionary = _commit_ledger_outflow(
		EconomyConfigScript.RES_GOLD,
		total_cost,
		"settlement_treasury",
		"provider:merchant_market",
		"market_purchase_payment",
		h_seq,
		new_gold
	)
	var buf_entry: Dictionary = _commit_ledger_provider_event(
		res_id,
		qty,
		"provider:merchant_market",
		"workplace_buffer:%s" % workplace.workplace_id,
		"market_purchase_to_buffer",
		h_seq,
		new_buf
	)
	var receipt: Dictionary = {
		"ok": true,
		"resource_id": res_id,
		"quantity": qty,
		"unit_price": unit_price,
		"total_cost": total_cost,
		"gold_after": new_gold,
		"buffer_after": new_buf,
		"workplace_id": workplace.workplace_id,
		"market_stock_after": new_market_stock,
		"gold_tx_id": String(gold_entry.get("tx_id", "")),
		"buffer_tx_id": String(buf_entry.get("tx_id", "")),
		"hour_seq": h_seq
	}
	transaction_committed.emit(receipt.duplicate(true))
	return receipt

## Deposits hauled goods into settlement final storage while resolving any pending provider
## buffer provenance (`provider:military_offmap_logistics` or `provider:merchant_market`)
## so aggregate conservation across providers, buffers, cargo, and ledger holds exactly.
func deposit_hauled_resource(
	res_id: String,
	amount: Variant,
	default_source: String,
	reason: String = "hauler_deposit",
	hour_seq: int = 0
) -> Dictionary:
	if not is_valid() or not is_valid_physical_resource(res_id):
		return {"ok": false, "reason": "invalid_resource_id"}
	if not _is_valid_strict_int(amount) or int(amount) <= 0:
		return {"ok": false, "reason": "invalid_amount"}
	var qty: int = int(amount)
	var clean_src := default_source.strip_edges()
	var clean_reason := reason.strip_edges()
	if clean_src.is_empty() or clean_reason.is_empty() or hour_seq < 0:
		return {"ok": false, "reason": "invalid_metadata"}
	var cur_bal: int = int(_stock[res_id])
	var cap: int = int(_capacities[res_id])
	if cur_bal + qty > cap:
		return {"ok": false, "reason": "exceeds_capacity"}

	# Allocate deposited amount against pending provider buffer deliveries first (if any)
	var provider_tags: Array[String] = ["provider:military_offmap_logistics", "provider:merchant_market"]
	var remaining: int = qty
	var committed_entries: Array[Dictionary] = []
	var running_bal: int = cur_bal
	_stock[res_id] = cur_bal + qty

	for ptag in provider_tags:
		if remaining <= 0:
			break
		if not _pending_buffer_deliveries.has(ptag):
			continue
		var p_map: Dictionary = _pending_buffer_deliveries[ptag]
		var pend_amt: int = int(p_map.get(res_id, 0))
		if pend_amt > 0:
			var take: int = mini(remaining, pend_amt)
			p_map[res_id] = pend_amt - take
			if int(p_map[res_id]) <= 0:
				p_map.erase(res_id)
			if p_map.is_empty():
				_pending_buffer_deliveries.erase(ptag)
			remaining -= take
			running_bal += take
			committed_entries.append(_commit_ledger_inflow(
				res_id,
				take,
				ptag,
				"settlement_stock:%s" % res_id,
				clean_reason,
				hour_seq,
				running_bal
			))

	if remaining > 0:
		running_bal += remaining
		committed_entries.append(_commit_ledger_inflow(
			res_id,
			remaining,
			clean_src,
			"settlement_stock:%s" % res_id,
			clean_reason,
			hour_seq,
			running_bal
		))

	_sync_forage_stock_if_needed(res_id)
	var last_tx_id: String = String(committed_entries[-1].get("tx_id", "")) if not committed_entries.is_empty() else ""
	var receipt: Dictionary = {
		"ok": true,
		"tx_id": last_tx_id,
		"resource_id": res_id,
		"amount": qty,
		"balance_after": running_bal,
		"source": clean_src,
		"reason": clean_reason,
		"hour_seq": hour_seq
	}
	transaction_committed.emit(receipt.duplicate(true))
	return receipt

func get_pending_buffer_deliveries() -> Dictionary:
	return _pending_buffer_deliveries.duplicate(true)

# -----------------------------------------------------------------------------
# Data-Level Serialization & Restoration
# -----------------------------------------------------------------------------
func to_dict() -> Dictionary:
	return {
		"settlement_id": _settlement_id,
		"origin_faction_id": _origin_faction_id,
		"economy_profile_id": _economy_profile_id,
		"merchant_smith_enabled": _merchant_smith_enabled,
		"is_endowment_initialized": _is_endowment_initialized,
		"stock": _stock.duplicate(true),
		"capacities": _capacities.duplicate(true),
		"over_capacity_resources": get_over_capacity_resources(),
		"gold": _gold,
		"gold_capacity": _gold_capacity,
		"forage_provider": _forage_provider.duplicate(true),
		"military_logistics": _military_logistics.duplicate(true),
		"market_provider": _market_provider.duplicate(true),
		"pending_buffer_deliveries": _pending_buffer_deliveries.duplicate(true),
		"ledger": _ledger.to_dict() if _ledger != null else {}
	}

func serialize() -> Dictionary:
	return to_dict()

static func from_dict(data: Variant) -> RefCounted:
	if not (data is Dictionary):
		return null
	var d: Dictionary = data
	if not (d.get("settlement_id") is String) or not (d.get("origin_faction_id") is String):
		return null
	var sid := String(d["settlement_id"]).strip_edges()
	var orig_fid := String(d["origin_faction_id"]).strip_edges()
	if not SettlementVillagerDataScript.is_valid_identifier(sid) or not SettlementVillagerDataScript.is_valid_identifier(orig_fid):
		return null
	var expected_profile := resolve_profile_for_origin(orig_fid)
	if expected_profile.is_empty():
		return null
	if d.has("economy_profile_id"):
		if not (d["economy_profile_id"] is String) or String(d["economy_profile_id"]).strip_edges() != expected_profile:
			return null
	if d.has("merchant_smith_enabled"):
		if not (d["merchant_smith_enabled"] is bool) or bool(d["merchant_smith_enabled"]) != false:
			return null
	if d.has("is_endowment_initialized") and not (d["is_endowment_initialized"] is bool):
		return null

	for num_k in ["gold", "gold_capacity"]:
		if d.has(num_k) and not _is_valid_strict_int(d[num_k]):
			return null

	for dict_k in ["stock", "capacities", "over_capacity_resources", "forage_provider", "military_logistics", "market_provider", "ledger"]:
		if d.has(dict_k) and not (d[dict_k] is Dictionary):
			return null

	var econ := new(sid, orig_fid, false)

	if d.has("gold_capacity"):
		var gc: int = int(d["gold_capacity"])
		if gc < 0:
			return null
		econ._gold_capacity = gc

	if d.has("gold"):
		var g: int = int(d["gold"])
		if g < 0 or g > econ._gold_capacity:
			return null
		econ._gold = g

	if d.has("capacities"):
		var raw_caps: Dictionary = d["capacities"]
		for k in raw_caps.keys():
			var k_str := String(k)
			if not is_valid_physical_resource(k_str) or not _is_valid_strict_int(raw_caps[k]):
				return null
			var c_val: int = int(raw_caps[k])
			if c_val < 0:
				return null
			var default_base: int = int(EconomyConfigScript.BASE_CAPACITIES.get(k_str, 500))
			econ._capacities[k_str] = c_val
			econ._base_capacities[k_str] = mini(default_base, c_val) if c_val < default_base else default_base
			econ._derived_capacity_bonuses[k_str] = maxi(0, c_val - int(econ._base_capacities[k_str]))

	var allowed_over_cap: Dictionary = {}
	if d.has("over_capacity_resources"):
		var raw_oc: Dictionary = d["over_capacity_resources"]
		for k in raw_oc.keys():
			var k_str := String(k)
			if not is_valid_physical_resource(k_str) or not _is_valid_strict_int(raw_oc[k]) or int(raw_oc[k]) <= 0:
				return null
			allowed_over_cap[k_str] = int(raw_oc[k])

	if d.has("stock"):
		var raw_stock: Dictionary = d["stock"]
		for k in raw_stock.keys():
			var k_str := String(k)
			if not is_valid_physical_resource(k_str) or not _is_valid_strict_int(raw_stock[k]):
				return null
			var s_val: int = int(raw_stock[k])
			var cap_val: int = int(econ._capacities[k_str])
			if s_val < 0:
				return null
			if s_val > cap_val:
				if not allowed_over_cap.has(k_str) or (s_val - cap_val) != int(allowed_over_cap[k_str]):
					return null
				econ._over_capacity_resources[k_str] = s_val - cap_val
			econ._stock[k_str] = s_val

	if d.has("forage_provider"):
		if not _restore_forage_provider(econ, d["forage_provider"]):
			return null

	if d.has("military_logistics"):
		if not _restore_military_logistics(econ, d["military_logistics"]):
			return null

	if d.has("market_provider"):
		if not _restore_market_provider(econ, d["market_provider"]):
			return null

	if d.has("pending_buffer_deliveries"):
		if not (d["pending_buffer_deliveries"] is Dictionary):
			return null
		var raw_pbd: Dictionary = d["pending_buffer_deliveries"]
		for ptag in raw_pbd.keys():
			if not (ptag is String) or not (raw_pbd[ptag] is Dictionary):
				return null
			var inner: Dictionary = raw_pbd[ptag]
			var clean_inner: Dictionary = {}
			for r_k in inner.keys():
				var r_str := String(r_k)
				if not is_valid_physical_resource(r_str) or not _is_valid_strict_int(inner[r_k]) or int(inner[r_k]) < 0:
					return null
				if int(inner[r_k]) > 0:
					clean_inner[r_str] = int(inner[r_k])
			if not clean_inner.is_empty():
				econ._pending_buffer_deliveries[String(ptag)] = clean_inner

	if d.has("ledger") and not (d["ledger"] as Dictionary).is_empty():
		var restored_ledger := SettlementSupplyLedgerScript.from_dict(d["ledger"])
		if restored_ledger == null or restored_ledger.settlement_id != sid:
			return null
		restored_ledger.bind_to_economy()
		econ._ledger = restored_ledger

	var has_any_activity_or_endowment: bool = (
		econ._ledger.get_next_tx_seq() > 1
		or bool(econ._forage_provider.get("enabled", false))
		or bool(econ._military_logistics.get("enabled", false))
		or bool(econ._market_provider.get("enabled", false))
	)
	if not has_any_activity_or_endowment:
		for res_id in EconomyConfigScript.ALL_RESOURCES:
			if econ._ledger.get_initial_balance(res_id) != 0 or econ._ledger.get_total_inflow(res_id) != 0 or econ._ledger.get_total_outflow(res_id) != 0:
				has_any_activity_or_endowment = true
				break

	if d.has("is_endowment_initialized"):
		var explicit_init: bool = bool(d["is_endowment_initialized"])
		if not explicit_init and has_any_activity_or_endowment:
			return null
		econ._is_endowment_initialized = explicit_init
	else:
		econ._is_endowment_initialized = has_any_activity_or_endowment

	if not econ.is_valid():
		return null
	econ.lock_identity()
	return econ

static func _restore_forage_provider(econ: RefCounted, fp: Dictionary) -> bool:
	if fp.has("enabled") and not (fp["enabled"] is bool):
		return false
	if fp.has("resource_id") and (not (fp["resource_id"] is String) or String(fp["resource_id"]) != EconomyConfigScript.RES_FOOD):
		return false
	for int_k in ["initial_stock", "current_stock", "max_capacity", "regen_interval_hours", "last_processed_hour_seq", "elapsed_hours_remainder", "total_regenerated"]:
		if fp.has(int_k) and not _is_valid_strict_int(fp[int_k]):
			return false
	for flt_k in ["regen_amount_per_interval", "fractional_remainder"]:
		if fp.has(flt_k) and not SettlementVillagerDataScript._is_valid_finite_number(fp[flt_k]):
			return false
	if fp.has("state") and (not (fp["state"] is String) or not VALID_PROVIDER_STATES.has(String(fp["state"]))):
		return false

	var max_cap: int = int(fp.get("max_capacity", DEFAULT_FORAGE_MAX_CAPACITY))
	var cur_stock: int = int(fp.get("current_stock", 0))
	var init_stock: int = int(fp.get("initial_stock", 0))
	var interval_h: int = int(fp.get("regen_interval_hours", DEFAULT_FORAGE_INTERVAL_HOURS))
	var last_seq: int = int(fp.get("last_processed_hour_seq", 0))
	var rem_h: int = int(fp.get("elapsed_hours_remainder", 0))
	var total_reg: int = int(fp.get("total_regenerated", 0))
	var rate: float = float(fp.get("regen_amount_per_interval", DEFAULT_FORAGE_REGEN_AMOUNT))
	var frac: float = float(fp.get("fractional_remainder", 0.0))

	if max_cap < 1 or cur_stock < 0 or cur_stock > max_cap or init_stock < 0 or interval_h < 1 or last_seq < 0 or rem_h < 0 or total_reg < 0:
		return false
	if rate <= 0.0 or frac < 0.0 or frac >= 1.0:
		return false

	econ._forage_provider["enabled"] = bool(fp.get("enabled", false))
	econ._forage_provider["resource_id"] = EconomyConfigScript.RES_FOOD
	econ._forage_provider["initial_stock"] = init_stock
	econ._forage_provider["current_stock"] = cur_stock
	econ._forage_provider["max_capacity"] = max_cap
	econ._forage_provider["regen_amount_per_interval"] = rate
	econ._forage_provider["regen_interval_hours"] = interval_h
	econ._forage_provider["last_processed_hour_seq"] = last_seq
	econ._forage_provider["elapsed_hours_remainder"] = rem_h
	econ._forage_provider["fractional_remainder"] = frac
	econ._forage_provider["state"] = String(fp.get("state", PROVIDER_STATE_DISABLED))
	econ._forage_provider["total_regenerated"] = total_reg
	return true

static func _restore_military_logistics(econ: RefCounted, ml: Dictionary) -> bool:
	if ml.has("enabled") and not (ml["enabled"] is bool):
		return false
	if ml.has("resource_id") and (not (ml["resource_id"] is String) or String(ml["resource_id"]) != EconomyConfigScript.RES_FOOD):
		return false
	for int_k in [
		"initial_allocation",
		"remaining_budget",
		"max_allocation",
		"max_cumulative_top_ups",
		"ration_amount_per_delivery",
		"delivery_interval_hours",
		"next_delivery_hour_seq",
		"last_completed_delivery_hour_seq",
		"total_delivered",
		"total_top_ups"
	]:
		if ml.has(int_k) and not _is_valid_strict_int(ml[int_k]):
			return false
	if ml.has("processed_grant_ids") and not (ml["processed_grant_ids"] is Dictionary):
		return false
	if ml.has("state") and (not (ml["state"] is String) or not VALID_PROVIDER_STATES.has(String(ml["state"]))):
		return false

	var init_alloc: int = int(ml.get("initial_allocation", 0))
	var rem_budget: int = int(ml.get("remaining_budget", 0))
	var max_alloc: int = int(ml.get("max_allocation", DEFAULT_MILITARY_LOGISTICS_MAX_ALLOCATION))
	var max_cum_top: int = int(ml.get("max_cumulative_top_ups", DEFAULT_MILITARY_LOGISTICS_MAX_CUMULATIVE_TOP_UPS))
	var ration_amt: int = int(ml.get("ration_amount_per_delivery", DEFAULT_MILITARY_RATION_DELIVERY_AMOUNT))
	var interval_h: int = int(ml.get("delivery_interval_hours", DEFAULT_MILITARY_DELIVERY_INTERVAL_HOURS))
	var next_seq: int = int(ml.get("next_delivery_hour_seq", DEFAULT_MILITARY_DELIVERY_INTERVAL_HOURS))
	var last_seq: int = int(ml.get("last_completed_delivery_hour_seq", 0))
	var tot_del: int = int(ml.get("total_delivered", 0))
	var tot_top: int = int(ml.get("total_top_ups", 0))

	if init_alloc < 0 or rem_budget < 0 or max_alloc < 1 or rem_budget > max_alloc or max_cum_top < 0 or tot_top > max_cum_top:
		return false
	if ration_amt < 1 or interval_h < 1 or next_seq < 1 or last_seq < 0 or tot_del < 0 or tot_top < 0:
		return false

	var clean_grants: Dictionary = {}
	if ml.has("processed_grant_ids"):
		var raw_g: Dictionary = ml["processed_grant_ids"]
		for gk in raw_g.keys():
			if not (gk is String) or not SettlementVillagerDataScript.is_valid_identifier(String(gk)):
				return false
			if not (raw_g[gk] is Dictionary):
				return false
			clean_grants[String(gk)] = (raw_g[gk] as Dictionary).duplicate(true)

	econ._military_logistics["enabled"] = bool(ml.get("enabled", false))
	econ._military_logistics["resource_id"] = EconomyConfigScript.RES_FOOD
	econ._military_logistics["initial_allocation"] = init_alloc
	econ._military_logistics["remaining_budget"] = rem_budget
	econ._military_logistics["max_allocation"] = max_alloc
	econ._military_logistics["max_cumulative_top_ups"] = max_cum_top
	econ._military_logistics["ration_amount_per_delivery"] = ration_amt
	econ._military_logistics["delivery_interval_hours"] = interval_h
	econ._military_logistics["next_delivery_hour_seq"] = next_seq
	econ._military_logistics["last_completed_delivery_hour_seq"] = last_seq
	econ._military_logistics["state"] = String(ml.get("state", PROVIDER_STATE_DISABLED))
	econ._military_logistics["total_delivered"] = tot_del
	econ._military_logistics["total_top_ups"] = tot_top
	econ._military_logistics["processed_grant_ids"] = clean_grants
	return true

static func _restore_market_provider(econ: RefCounted, mp: Dictionary) -> bool:
	if mp.has("enabled") and not (mp["enabled"] is bool):
		return false
	for dict_k in [
		"initial_stock",
		"stock",
		"capacity",
		"initial_allocation",
		"remaining_restock_allocation",
		"max_restock_allocation",
		"max_cumulative_top_ups",
		"restock_amount_per_interval",
		"prices",
		"total_restocked",
		"total_purchased",
		"total_allocation_top_ups",
		"processed_grant_ids"
	]:
		if mp.has(dict_k) and not (mp[dict_k] is Dictionary):
			return false
	for int_k in ["restock_interval_hours", "next_restock_hour_seq", "last_completed_restock_hour_seq"]:
		if mp.has(int_k) and not _is_valid_strict_int(mp[int_k]):
			return false
	if mp.has("state") and (not (mp["state"] is String) or not VALID_PROVIDER_STATES.has(String(mp["state"]))):
		return false

	var interval_h: int = int(mp.get("restock_interval_hours", DEFAULT_MERCHANT_RESTOCK_INTERVAL_HOURS))
	var next_seq: int = int(mp.get("next_restock_hour_seq", DEFAULT_MERCHANT_RESTOCK_INTERVAL_HOURS))
	var last_seq: int = int(mp.get("last_completed_restock_hour_seq", 0))
	if interval_h < 1 or next_seq < 1 or last_seq < 0:
		return false

	if mp.has("capacity"):
		var c_in: Dictionary = mp["capacity"]
		for k in c_in.keys():
			var k_str := String(k)
			if not MERCHANT_MARKET_RESOURCES.has(k_str) or not _is_valid_strict_int(c_in[k]) or int(c_in[k]) < 0:
				return false
			econ._market_provider["capacity"][k_str] = int(c_in[k])

	if mp.has("initial_stock"):
		var is_in: Dictionary = mp["initial_stock"]
		for k in is_in.keys():
			var k_str := String(k)
			if not MERCHANT_MARKET_RESOURCES.has(k_str) or not _is_valid_strict_int(is_in[k]):
				return false
			var isv: int = int(is_in[k])
			if isv < 0 or isv > int(econ._market_provider["capacity"][k_str]):
				return false
			econ._market_provider["initial_stock"][k_str] = isv

	if mp.has("stock"):
		var s_in: Dictionary = mp["stock"]
		for k in s_in.keys():
			var k_str := String(k)
			if not MERCHANT_MARKET_RESOURCES.has(k_str) or not _is_valid_strict_int(s_in[k]):
				return false
			var sv: int = int(s_in[k])
			if sv < 0 or sv > int(econ._market_provider["capacity"][k_str]):
				return false
			econ._market_provider["stock"][k_str] = sv
			if not mp.has("initial_stock"):
				econ._market_provider["initial_stock"][k_str] = sv

	if mp.has("max_restock_allocation"):
		var ma_in: Dictionary = mp["max_restock_allocation"]
		for k in ma_in.keys():
			var k_str := String(k)
			if not MERCHANT_MARKET_RESOURCES.has(k_str) or not _is_valid_strict_int(ma_in[k]) or int(ma_in[k]) < 0:
				return false
			econ._market_provider["max_restock_allocation"][k_str] = int(ma_in[k])

	if mp.has("max_cumulative_top_ups"):
		var mct_in: Dictionary = mp["max_cumulative_top_ups"]
		for k in mct_in.keys():
			var k_str := String(k)
			if not MERCHANT_MARKET_RESOURCES.has(k_str) or not _is_valid_strict_int(mct_in[k]) or int(mct_in[k]) < 0:
				return false
			econ._market_provider["max_cumulative_top_ups"][k_str] = int(mct_in[k])

	if mp.has("initial_allocation"):
		var ia_in: Dictionary = mp["initial_allocation"]
		for k in ia_in.keys():
			var k_str := String(k)
			if not MERCHANT_MARKET_RESOURCES.has(k_str) or not _is_valid_strict_int(ia_in[k]) or int(ia_in[k]) < 0:
				return false
			econ._market_provider["initial_allocation"][k_str] = int(ia_in[k])

	if mp.has("remaining_restock_allocation"):
		var ra_in: Dictionary = mp["remaining_restock_allocation"]
		for k in ra_in.keys():
			var k_str := String(k)
			if not MERCHANT_MARKET_RESOURCES.has(k_str) or not _is_valid_strict_int(ra_in[k]):
				return false
			var rv: int = int(ra_in[k])
			if rv < 0 or rv > int(econ._market_provider["max_restock_allocation"][k_str]):
				return false
			econ._market_provider["remaining_restock_allocation"][k_str] = rv

	if mp.has("restock_amount_per_interval"):
		var rpi_in: Dictionary = mp["restock_amount_per_interval"]
		for k in rpi_in.keys():
			var k_str := String(k)
			if not MERCHANT_MARKET_RESOURCES.has(k_str) or not _is_valid_strict_int(rpi_in[k]) or int(rpi_in[k]) < 0:
				return false
			econ._market_provider["restock_amount_per_interval"][k_str] = int(rpi_in[k])

	if mp.has("prices"):
		var p_in: Dictionary = mp["prices"]
		for k in p_in.keys():
			var k_str := String(k)
			if not MERCHANT_MARKET_RESOURCES.has(k_str) or not _is_valid_strict_int(p_in[k]):
				return false
			var pv: int = int(p_in[k])
			if pv < 1 or pv > MAX_SAFE_TRANSACTION_AMOUNT:
				return false
			econ._market_provider["prices"][k_str] = pv

	for tally_key in ["total_restocked", "total_purchased", "total_allocation_top_ups"]:
		if mp.has(tally_key):
			var t_in: Dictionary = mp[tally_key]
			for k in t_in.keys():
				var k_str := String(k)
				if not MERCHANT_MARKET_RESOURCES.has(k_str) or not _is_valid_strict_int(t_in[k]) or int(t_in[k]) < 0:
					return false
				econ._market_provider[tally_key][k_str] = int(t_in[k])

	for res_id in MERCHANT_MARKET_RESOURCES:
		if int(econ._market_provider["total_allocation_top_ups"].get(res_id, 0)) > int(econ._market_provider["max_cumulative_top_ups"].get(res_id, 0)):
			return false

	var clean_mkt_grants: Dictionary = {}
	if mp.has("processed_grant_ids"):
		var raw_mg: Dictionary = mp["processed_grant_ids"]
		for gk in raw_mg.keys():
			if not (gk is String) or not SettlementVillagerDataScript.is_valid_identifier(String(gk)):
				return false
			if not (raw_mg[gk] is Dictionary):
				return false
			clean_mkt_grants[String(gk)] = (raw_mg[gk] as Dictionary).duplicate(true)
	econ._market_provider["processed_grant_ids"] = clean_mkt_grants

	econ._market_provider["enabled"] = bool(mp.get("enabled", false))
	econ._market_provider["restock_interval_hours"] = interval_h
	econ._market_provider["next_restock_hour_seq"] = next_seq
	econ._market_provider["last_completed_restock_hour_seq"] = last_seq
	econ._market_provider["state"] = String(mp.get("state", PROVIDER_STATE_DISABLED))
	return true

static func deserialize(data: Variant) -> RefCounted:
	return from_dict(data)
