extends SceneTree
## Focused Phase 2 Test Suite: Rival Settlement Villager System — Local Economy & Resource Supply
## Covers Sections 12.1 through 12.8 (Architecture v1.0 — LOCKED).

const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementVillagerContextScript = preload("res://scripts/world/settlement_villager_context.gd")
const SettlementEconomyScript = preload("res://scripts/world/settlement_economy.gd")
const SettlementSupplyLedgerScript = preload("res://scripts/world/settlement_supply_ledger.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const FactionManagerScript = preload("res://scripts/factions/faction_manager.gd")

var _passed: int = 0
var _failed: int = 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] %s" % msg)
	else:
		_failed += 1
		printerr("  [FAIL] %s" % msg)

func _init() -> void:
	print("\n========================================================")
	print("  TEST SUITE: Rival Settlement Economy Phase 2")
	print("========================================================")

	_test_12_1_settlement_economy_core()
	_test_12_2_ledger_and_accounting()
	_test_12_3_neutral_tribe_forage()
	_test_12_4_military_logistics()
	_test_12_5_merchant_market()
	_test_12_6_resource_semantics()
	_test_12_7_serialization_and_context_integration()
	_test_12_8_architectural_isolation()
	_test_12_9_hardening_reviews_a_to_g()
	_test_12_10_final_api_and_supply_integrity_audit()

	print("--------------------------------------------------------")
	print("  Results: %d passed, %d failed" % [_passed, _failed])
	print("========================================================")
	quit(1 if _failed > 0 else 0)

func _test_12_1_settlement_economy_core() -> void:
	print("\n[12.1] SettlementEconomy Core, Ownership, Capacities & Atomic Validation")
	var econ_a := SettlementEconomyScript.new("stl_mil_alpha", "rival_military", true)
	var econ_b := SettlementEconomyScript.new("stl_mil_beta", "rival_military", true)
	var econ_empty := SettlementEconomyScript.new("stl_tribe_empty", "neutral_tribe", false)

	_assert(econ_a.is_valid() and econ_b.is_valid() and econ_empty.is_valid(), "Valid economies pass is_valid()")
	_assert(econ_empty.get_resource("food") == 0 and econ_empty.get_gold() == 0 and not econ_empty.is_endowment_initialized, "Unendowed economy starts with zero balances and does not mint resources")

	# Identity & profile immutability
	econ_a.settlement_id = "stl_hacked"
	econ_a.origin_faction_id = "neutral_tribe"
	econ_a.economy_profile_id = "neutral_tribe"
	_assert(
		econ_a.settlement_id == "stl_mil_alpha"
		and econ_a.origin_faction_id == "rival_military"
		and econ_a.economy_profile_id == "rival_military",
		"SettlementEconomy settlement_id, origin_faction_id, and economy_profile_id are immutable"
	)

	# Independent stock and gold between settlements
	var r_cred: Dictionary = econ_a.credit_resource("wood", 25, "test_harvest", "wood_inflow", 10)
	var g_cred: Dictionary = econ_a.credit_gold(50, "test_tax", "local_tax", 10)
	_assert(bool(r_cred.get("ok", false)) and econ_a.get_resource("wood") == 65, "Crediting wood on Settlement A updates A's balance (40 + 25 = 65)")
	_assert(econ_b.get_resource("wood") == 40, "Settlement B wood balance remains completely isolated (40)")
	_assert(bool(g_cred.get("ok", false)) and econ_a.get_gold() == 50 and econ_b.get_gold() == 0, "Gold treasury is isolated per settlement")

	# Capacity enforcement & invalid input rejection (no silent clamping)
	var food_before: int = econ_a.get_resource("food")
	var tx_seq_before: int = econ_a.ledger.get_next_tx_seq()
	_assert(not bool(econ_a.credit_resource("unknown_res", 10, "src", "rsn", 11).get("ok", false)), "Unknown resource ID rejected")
	_assert(not bool(econ_a.credit_resource("food", 0, "src", "rsn", 11).get("ok", false)), "Zero credit amount rejected")
	_assert(not bool(econ_a.credit_resource("food", -5, "src", "rsn", 11).get("ok", false)), "Negative credit amount rejected")
	_assert(not bool(econ_a.credit_resource("food", 2.5, "src", "rsn", 11).get("ok", false)), "Non-integer float credit amount rejected without clamping")
	_assert(not bool(econ_a.credit_resource("food", NAN, "src", "rsn", 11).get("ok", false)), "NaN credit amount rejected")
	_assert(not bool(econ_a.credit_resource("food", 10, "", "rsn", 11).get("ok", false)), "Empty source rejected")
	_assert(not bool(econ_a.credit_resource("food", 9999, "src", "rsn", 11).get("ok", false)), "Over-capacity credit rejected without clamping")
	_assert(not bool(econ_a.debit_resource("food", 9999, "dst", "rsn", 11).get("ok", false)), "Over-balance debit rejected without negative balance")
	_assert(not bool(econ_a.debit_gold(9999, "dst", "rsn", 11).get("ok", false)), "Over-balance gold debit rejected")
	_assert(econ_a.get_resource("food") == food_before and econ_a.ledger.get_next_tx_seq() == tx_seq_before, "Failed transactions leave balances and ledger sequence untouched")

	# Capacity modification guards
	_assert(not econ_a.set_resource_capacity("food", 10), "Cannot lower resource capacity below current stock (80)")
	_assert(econ_a.set_resource_capacity("food", 300) and econ_a.get_capacity("food") == 300, "Valid capacity update succeeds")

	# Defensive snapshot isolation
	var res_snap: Dictionary = econ_a.get_all_resources()
	res_snap["food"] = 99999
	_assert(econ_a.get_resource("food") == food_before, "Mutating get_all_resources() snapshot does not affect live stock")

func _test_12_2_ledger_and_accounting() -> void:
	print("\n[12.2] SettlementSupplyLedger Provenance, Accounting Invariant & Bounded History")
	var econ := SettlementEconomyScript.new("stl_ledger_test", "neutral_tribe", true)
	var ledger = econ.ledger

	_assert(ledger.get_initial_balance("food") == 60 and ledger.get_initial_provenance("food") == "scenario_endowment:neutral_tribe", "Initial endowment recorded with explicit provenance")
	_assert(ledger.verify_balance_consistency(econ.get_all_resources(), econ.get_gold()), "Initial balances satisfy accounting equation")

	# Perform inflows and outflows from multiple sources/destinations
	_assert(bool(econ.credit_resource("food", 30, "source_alpha", "forage_bonus", 12).get("ok", false)), "Inflow 1 committed")
	_assert(bool(econ.credit_resource("food", 15, "source_beta", "tribute", 14).get("ok", false)), "Inflow 2 committed")
	_assert(bool(econ.debit_resource("food", 25, "villager_consumption", "daily_meal", 18).get("ok", false)), "Outflow 1 committed")

	# Current Balance = 60 + (30 + 15) - 25 = 80
	_assert(econ.get_resource("food") == 80, "Live food balance is 80")
	_assert(ledger.get_total_inflow("food") == 45 and ledger.get_total_outflow("food") == 25, "Ledger cumulative inflows (45) and outflows (25) match")
	_assert(ledger.get_expected_balance("food") == 80 and ledger.verify_balance_consistency(econ.get_all_resources(), econ.get_gold()), "Accounting invariant Current = Initial + Inflows - Outflows holds")

	var by_src: Dictionary = ledger.get_inflows_by_source("food")
	var by_dst: Dictionary = ledger.get_outflows_by_destination("food")
	_assert(int(by_src.get("source_alpha", 0)) == 30 and int(by_src.get("source_beta", 0)) == 15, "Inflows tracked accurately by source")
	_assert(int(by_dst.get("villager_consumption", 0)) == 25, "Outflows tracked accurately by destination")

	# Bounded transaction history test
	var small_ledger_econ := SettlementEconomyScript.new("stl_bounded_hist", "neutral_tribe", false)
	small_ledger_econ.ledger.max_history_entries = 8
	for i in range(20):
		small_ledger_econ.credit_resource("wood", 1, "src_%d" % i, "test_bounded", i + 1)
	_assert(small_ledger_econ.get_resource("wood") == 20 and small_ledger_econ.ledger.get_total_inflow("wood") == 20, "Cumulative totals remain exact across > max_history_entries transactions")
	_assert(small_ledger_econ.ledger.get_recent_entry_count() == 8, "Recent journal is strictly bounded by max_history_entries (8)")
	var entries: Array[Dictionary] = small_ledger_econ.ledger.get_recent_entries()
	_assert(int(entries[0]["tx_seq"]) == 13 and int(entries[7]["tx_seq"]) == 20, "Bounded journal retains most recent entries in deterministic order")

func _test_12_3_neutral_tribe_forage() -> void:
	print("\n[12.3] Neutral Tribe — Bounded Local Forage Regeneration")
	var tribe_a := SettlementEconomyScript.new("stl_tribe_a", "neutral_tribe", true)
	var tribe_b := SettlementEconomyScript.new("stl_tribe_b", "neutral_tribe", true)

	var fp_init: Dictionary = tribe_a.get_forage_provider_state()
	_assert(bool(fp_init["enabled"]) and int(fp_init["current_stock"]) == 60 and int(fp_init["max_capacity"]) == 120, "Neutral Tribe forage initialized (60 / 120)")

	# Sub-interval call (3 hours < 6-hour interval) does not regenerate yet but records elapsed remainder
	var sub_res: Dictionary = tribe_a.process_forage_regeneration(3)
	_assert(bool(sub_res["ok"]) and int(sub_res["added"]) == 0 and tribe_a.get_resource("food") == 60, "Sub-interval advance (hour 3) adds 0 food")

	# Advancing to hour 6 completes the first 6-hour interval (+4 food -> 64)
	var r6: Dictionary = tribe_a.process_forage_regeneration(6)
	_assert(bool(r6["ok"]) and int(r6["added"]) == 4 and tribe_a.get_resource("food") == 64, "Reaching hour 6 deterministically regenerates +4 food (64)")

	# Repeated call at hour 6 or earlier hour 5 must be rejected without regenerating twice
	var dup6: Dictionary = tribe_a.process_forage_regeneration(6)
	var old5: Dictionary = tribe_a.process_forage_regeneration(5)
	_assert(not bool(dup6["ok"]) and not bool(old5["ok"]) and tribe_a.get_resource("food") == 64, "Repeated or earlier hour_seq calls do not regenerate twice")

	# Fractional rate & remainder preservation (2.5 food per 6 hours)
	_assert(tribe_a.configure_forage_provider(120, 2.5, 6), "Configured fractional forage rate 2.5 / 6h")
	var r12: Dictionary = tribe_a.process_forage_regeneration(12) # +2.5 -> +2 whole, 0.5 remainder -> 66
	_assert(bool(r12["ok"]) and int(r12["added"]) == 2 and is_equal_approx(float(r12["fractional_remainder"]), 0.5) and tribe_a.get_resource("food") == 66, "Fractional rate step 1 adds 2 and retains 0.5 remainder")
	var r18: Dictionary = tribe_a.process_forage_regeneration(18) # +2.5 + 0.5 = +3 whole, 0.0 remainder -> 69
	_assert(bool(r18["ok"]) and int(r18["added"]) == 3 and is_equal_approx(float(r18["fractional_remainder"]), 0.0) and tribe_a.get_resource("food") == 69, "Fractional rate step 2 consumes 0.5 remainder to add 3 (69)")

	# Large time jump capped at max_capacity (120)
	var r_jump: Dictionary = tribe_a.process_forage_regeneration(300)
	_assert(bool(r_jump["ok"]) and tribe_a.get_resource("food") == 120 and int(tribe_a.get_forage_provider_state()["current_stock"]) == 120, "Large time jump caps forage at max_capacity (120)")
	_assert(String(tribe_a.get_forage_provider_state()["state"]) == SettlementEconomyScript.PROVIDER_STATE_FULL, "Forage provider enters 'full' state at cap")

	# Further regeneration while full adds 0 and does not exceed cap
	var r_full: Dictionary = tribe_a.process_forage_regeneration(312)
	_assert(bool(r_full["ok"]) and int(r_full["added"]) == 0 and tribe_a.get_resource("food") == 120, "Full forage cap prevents generating resources beyond 120")
	_assert(tribe_a.ledger.verify_balance_consistency(tribe_a.get_all_resources(), tribe_a.get_gold()), "Ledger remains consistent after capped forage regeneration")
	_assert(tribe_b.get_resource("food") == 60, "Second Neutral Tribe settlement forage state is completely independent")

func _test_12_4_military_logistics() -> void:
	print("\n[12.4] Military — Finite Off-Map Ration Logistics")
	var fm := FactionManagerScript.new()
	var strat_mil_gold_before: int = int(fm.get_faction("rival_military").resources.get("gold", 0))
	var strat_mil_metal_before: int = int(fm.get_faction("rival_military").resources.get("metal", 0))

	var mil_a := SettlementEconomyScript.new("stl_mil_a", "rival_military", true)
	var mil_b := SettlementEconomyScript.new("stl_mil_b", "rival_military", true)

	var ml_state: Dictionary = mil_a.get_military_logistics_state()
	_assert(bool(ml_state["enabled"]) and int(ml_state["remaining_budget"]) == 120 and int(ml_state["ration_amount_per_delivery"]) == 20, "Military logistics initialized with finite budget 120 and batch 20")

	# Before due hour (hour 12 < 24), no delivery occurs
	var early: Dictionary = mil_a.process_military_logistics(12)
	_assert(not bool(early["ok"]) and mil_a.get_resource("food") == 80 and int(mil_a.get_military_logistics_state()["remaining_budget"]) == 120, "Military logistics does not deliver before next_delivery_hour_seq (24)")

	# At hour 24, delivers 20 rations -> food = 100, remaining_budget = 100
	var d24: Dictionary = mil_a.process_military_logistics(24)
	_assert(bool(d24["ok"]) and int(d24["delivered"]) == 20 and mil_a.get_resource("food") == 100 and int(d24["remaining_budget"]) == 100, "Hour 24 delivery credits 20 food and debits 20 logistics budget")

	# Duplicate call at hour 24 is rejected without double delivery
	var dup24: Dictionary = mil_a.process_military_logistics(24)
	_assert(not bool(dup24["ok"]) and mil_a.get_resource("food") == 100 and int(mil_a.get_military_logistics_state()["remaining_budget"]) == 100, "Repeated call at hour 24 does not duplicate ration delivery")

	# Full-capacity protection: lower food capacity to 110 (only 10 headroom < 20 batch)
	_assert(mil_a.set_resource_capacity("food", 110), "Set food capacity to 110 (headroom 10 < 20 ration batch)")
	var blocked48: Dictionary = mil_a.process_military_logistics(48)
	_assert(
		not bool(blocked48["ok"])
		and String(blocked48["reason"]) == "waiting_capacity"
		and String(mil_a.get_military_logistics_state()["state"]) == SettlementEconomyScript.PROVIDER_STATE_WAITING_CAPACITY
		and int(mil_a.get_military_logistics_state()["remaining_budget"]) == 100
		and mil_a.get_resource("food") == 100,
		"Full/insufficient capacity enters 'waiting_capacity' without discarding logistics budget"
	)

	# Restore capacity to 500 and process due delivery at hour 48
	_assert(mil_a.set_resource_capacity("food", 500), "Restored food capacity to 500")
	var d48: Dictionary = mil_a.process_military_logistics(48)
	_assert(bool(d48["ok"]) and int(d48["delivered"]) == 20 and int(d48["remaining_budget"]) == 80 and mil_a.get_resource("food") == 120, "Delivery resumes once capacity is available")

	# Exhaust remaining 80 budget across hours 72, 96, 120, 144 (4 intervals * 20 = 80)
	var d144: Dictionary = mil_a.process_military_logistics(144)
	_assert(
		bool(d144["ok"])
		and int(d144["delivered"]) == 80
		and int(d144["remaining_budget"]) == 0
		and String(d144["state"]) == SettlementEconomyScript.PROVIDER_STATE_DEPLETED
		and mil_a.get_resource("food") == 200,
		"Exhausting finite budget delivers remaining 80 rations and transitions provider to 'depleted'"
	)

	# Subsequent due hour (168) stops and delivers 0
	var d168: Dictionary = mil_a.process_military_logistics(168)
	_assert(not bool(d168["ok"]) and String(d168["reason"]) == "budget_depleted" and mil_a.get_resource("food") == 200, "Depleted military provider stops and delivers 0 at hour 168")

	# Explicit top-up / recovery allocation
	var top_up: Dictionary = mil_a.top_up_military_logistics(40, "high_command_convoy", 170)
	_assert(bool(top_up["ok"]) and int(top_up["remaining_budget"]) == 40 and String(top_up["state"]) == SettlementEconomyScript.PROVIDER_STATE_ACTIVE, "Explicit top_up_military_logistics restores budget (40) and 'active' state")
	var d192: Dictionary = mil_a.process_military_logistics(192)
	_assert(bool(d192["ok"]) and int(d192["delivered"]) == 20 and int(d192["remaining_budget"]) == 20 and mil_a.get_resource("food") == 220, "Resumed delivery after top-up succeeds")

	# Verify FactionData.resources was never touched and mil_b is untouched
	_assert(
		int(fm.get_faction("rival_military").resources.get("gold", 0)) == strat_mil_gold_before
		and int(fm.get_faction("rival_military").resources.get("metal", 0)) == strat_mil_metal_before,
		"Military ration logistics never debits FactionData.resources"
	)
	_assert(mil_b.get_resource("food") == 80 and int(mil_b.get_military_logistics_state()["remaining_budget"]) == 120, "Second Military settlement has independent budget and stock")

func _test_12_5_merchant_market() -> void:
	print("\n[12.5] Merchant — Finite Market Pool, Atomic Purchases & Bounded Restock")
	var mer_a := SettlementEconomyScript.new("stl_mer_a", "rival_merchant", true)
	var mer_b := SettlementEconomyScript.new("stl_mer_b", "rival_merchant", true)

	_assert(mer_a.get_gold() == 120 and mer_a.get_resource("food") == 70 and mer_a.get_market_stock("food") == 60, "Merchant local treasury (120g), settlement food (70), and market food (60) initialized independently")

	# Successful atomic purchase: 10 food @ 2 gold = 20 gold
	var buy_ok: Dictionary = mer_a.purchase_from_market("food", 10, 8)
	_assert(
		bool(buy_ok["ok"])
		and int(buy_ok["total_cost"]) == 20
		and mer_a.get_gold() == 100
		and mer_a.get_market_stock("food") == 50
		and mer_a.get_resource("food") == 80,
		"Successful purchase deducts 20 gold, deducts 10 market food, and credits 10 settlement food"
	)
	_assert(mer_a.ledger.verify_balance_consistency(mer_a.get_all_resources(), mer_a.get_gold()), "Ledger accounting matches after market purchase")

	# Rejections must leave gold, market stock, settlement stock, and ledger untouched
	var gold_before: int = mer_a.get_gold()
	var m_food_before: int = mer_a.get_market_stock("food")
	var s_food_before: int = mer_a.get_resource("food")
	var seq_before: int = mer_a.ledger.get_next_tx_seq()

	# 1. Insufficient market stock (request 55 > 50 available in market, cost 110? Wait: give extra gold first or test crystal where 4 in stock @ 35g)
	# Wait: for tools, market stock is 15 @ 15g; if we set price of food to 1g and request 60 (> 50 market stock, cost 60 <= 100g):
	_assert(mer_a.set_market_price("food", 1), "Set food market price to 1g for stock limit test")
	var fail_m_stock: Dictionary = mer_a.purchase_from_market("food", 60, 9)
	_assert(not bool(fail_m_stock["ok"]) and String(fail_m_stock["reason"]) == "insufficient_market_stock", "Insufficient market stock rejected")
	_assert(mer_a.set_market_price("food", 2), "Restored food market price to 2g")

	# 2. Insufficient local gold (request 10 tools @ 15g = 150g > 100g local gold, while market has 15 tools)
	var fail_gold: Dictionary = mer_a.purchase_from_market("tools", 10, 9)
	_assert(not bool(fail_gold["ok"]) and String(fail_gold["reason"]) == "insufficient_local_gold", "Insufficient local gold rejected")

	# 3. Insufficient destination settlement capacity
	_assert(mer_a.set_resource_capacity("food", 85), "Lowered settlement food capacity to 85 (headroom 5)")
	var fail_cap: Dictionary = mer_a.purchase_from_market("food", 10, 9)
	_assert(not bool(fail_cap["ok"]) and String(fail_cap["reason"]) == "insufficient_settlement_capacity", "Insufficient destination settlement capacity rejected")
	_assert(mer_a.set_resource_capacity("food", 500), "Restored settlement food capacity to 500")

	# 4. Invalid resource ("ore" is not sold in market; "invalid_res" is unknown) and invalid quantity
	var fail_ore: Dictionary = mer_a.purchase_from_market("ore", 1, 9)
	var fail_qty: Dictionary = mer_a.purchase_from_market("food", -3, 9)
	_assert(not bool(fail_ore["ok"]) and not bool(fail_qty["ok"]), "Purchasing forbidden/invalid resource ('ore') or negative quantity rejected")

	_assert(
		mer_a.get_gold() == gold_before
		and mer_a.get_market_stock("food") == m_food_before
		and mer_a.get_resource("food") == s_food_before
		and mer_a.ledger.get_next_tx_seq() == seq_before,
		"All failed market purchases left gold, market stock, settlement stock, and ledger completely unchanged"
	)

	# Market restock interval, duplicate protection, exhaustion, and explicit recovery
	var restock24: Dictionary = mer_a.process_market_restock(24)
	_assert(
		bool(restock24["ok"])
		and mer_a.get_market_stock("food") == 70
		and mer_a.get_market_remaining_allocation("food") == 100,
		"Market restock at hour 24 adds 20 food to market pool (50 -> 70) and debits restock allocation (120 -> 100)"
	)
	var dup_restock24: Dictionary = mer_a.process_market_restock(24)
	_assert(not bool(dup_restock24["ok"]) and mer_a.get_market_stock("food") == 70, "Duplicate restock call at hour 24 does not duplicate market goods")

	# Exhaust market restock allocations across large jump and verify 'depleted' state
	# Buy some stock first or jump hours so allocations are consumed up to capacity, then drain remaining
	for cycle in range(1, 10):
		var h: int = 24 + cycle * 24
		mer_a.process_market_restock(h)
		# Drain market stock via internal test helper or credit gold + buy so market has headroom for all allocations
		mer_a.credit_gold(2000, "trade_dividend", "test_drain", h)
		for m_res in SettlementEconomyScript.MERCHANT_MARKET_RESOURCES:
			var m_avail: int = mer_a.get_market_stock(m_res)
			var s_headroom: int = mer_a.get_available_headroom(m_res)
			var buy_q: int = mini(m_avail, s_headroom)
			if buy_q > 0:
				mer_a.purchase_from_market(m_res, buy_q, h)

	var mp_after_drain: Dictionary = mer_a.get_market_provider_state()
	_assert(String(mp_after_drain["state"]) == SettlementEconomyScript.PROVIDER_STATE_DEPLETED, "Market provider enters 'depleted' state when all finite restock allocations are exhausted")
	var depleted_try: Dictionary = mer_a.process_market_restock(500)
	_assert(not bool(depleted_try["ok"]) and String(depleted_try["reason"]) == "allocation_depleted", "Depleted market provider does not restock")

	# Explicit allocation recovery
	var top_mkt: Dictionary = mer_a.top_up_market_allocation("food", 30, "southern_merchant_fleet", 504)
	_assert(bool(top_mkt["ok"]) and mer_a.get_market_remaining_allocation("food") == 30 and String(top_mkt["state"]) == SettlementEconomyScript.PROVIDER_STATE_ACTIVE, "Explicit top_up_market_allocation restores food restock allocation (30) and 'active' state")
	_assert(mer_b.get_gold() == 120 and mer_b.get_market_stock("food") == 60, "Second Merchant settlement market and treasury remain completely isolated")

func _test_12_6_resource_semantics() -> void:
	print("\n[12.6] Resource Semantics: Distinct food vs raw_meat, No Free Ore, Merchant Smith Disabled")
	var tribe := SettlementEconomyScript.new("stl_sem_tribe", "neutral_tribe", true)
	var mil := SettlementEconomyScript.new("stl_sem_mil", "rival_military", true)
	var mer := SettlementEconomyScript.new("stl_sem_mer", "rival_merchant", true)

	# raw_meat and food are strictly distinct
	var food_init: int = tribe.get_resource("food")
	_assert(tribe.get_resource("raw_meat") == 0, "Initial raw_meat is 0")
	_assert(bool(tribe.credit_resource("raw_meat", 18, "hunter_return", "hunt_yield", 4).get("ok", false)), "Crediting raw_meat succeeds")
	_assert(tribe.get_resource("raw_meat") == 18 and tribe.get_resource("food") == food_init, "Crediting raw_meat never modifies food balance (no implicit 1:1 conversion)")
	_assert(bool(tribe.debit_resource("raw_meat", 8, "spoilage_or_use", "test_debit", 5).get("ok", false)), "Debiting raw_meat succeeds")
	_assert(tribe.get_resource("raw_meat") == 10 and tribe.get_resource("food") == food_init, "Debiting raw_meat leaves food untouched")

	# No free Ore in any profile, and Merchant Smith disabled by default
	_assert(tribe.get_resource("ore") == 0 and mil.get_resource("ore") == 0 and mer.get_resource("ore") == 0, "Zero free Ore in Neutral Tribe, Military, and Merchant initial stocks")
	_assert(mer.get_market_stock("ore") == 0 and mer.get_market_remaining_allocation("ore") == 0, "Merchant market pool contains zero Ore and zero Ore restock allocation")
	_assert(mer.merchant_smith_enabled == false, "Merchant Smith is disabled by default when sustainable Ore supply is absent")

func _test_12_7_serialization_and_context_integration() -> void:
	print("\n[12.7] Serialization, Context Integration & Phase 1 Backward Compatibility")
	var ctx_mer := SettlementVillagerContextScript.new("stl_ctx_mer", "rival_merchant")
	var ctx_mil := SettlementVillagerContextScript.new("stl_ctx_mil", "rival_military")

	_assert(ctx_mer.economy != null and ctx_mer.economy.settlement_id == "stl_ctx_mer" and ctx_mer.economy.economy_profile_id == "rival_merchant", "SettlementVillagerContext owns matching SettlementEconomy")
	_assert(not ctx_mer.set_economy(ctx_mil.economy) and ctx_mer.economy.settlement_id == "stl_ctx_mer", "Cross-settlement economy attachment is rejected")

	# Changing owner_faction_id on context does NOT switch economy_profile_id
	ctx_mer.owner_faction_id = "rival_military"
	_assert(ctx_mer.economy.economy_profile_id == "rival_merchant" and ctx_mer.economy.origin_faction_id == "rival_merchant", "Changing owner_faction_id preserves origin economy_profile_id")

	# Perform transactions, serialize context, and restore
	ctx_mer.create_and_add_villager("Thương Gia 1", "hauler", Vector2i(30, 30))
	ctx_mer.economy.purchase_from_market("wood", 5, 10)
	ctx_mer.economy.process_market_restock(24)

	var snap: Dictionary = ctx_mer.to_dict()
	var restored_ctx = SettlementVillagerContextScript.from_dict(snap)
	_assert(restored_ctx != null and restored_ctx.economy != null and restored_ctx.economy.is_valid(), "Context round-trip with economy succeeds")
	_assert(
		restored_ctx.economy.get_gold() == ctx_mer.economy.get_gold()
		and restored_ctx.economy.get_resource("wood") == ctx_mer.economy.get_resource("wood")
		and restored_ctx.economy.get_market_stock("wood") == ctx_mer.economy.get_market_stock("wood"),
		"Restored context preserves exact gold, settlement stock, and market stock"
	)
	_assert(restored_ctx.economy.ledger.verify_balance_consistency(restored_ctx.economy.get_all_resources(), restored_ctx.economy.get_gold()), "Restored ledger matches restored balances")

	# Repeated schedule processing on restored economy at hour 24 must not duplicate restock
	var repeat24: Dictionary = restored_ctx.economy.process_market_restock(24)
	_assert(not bool(repeat24["ok"]) and String(repeat24["reason"]) == "not_due_or_already_processed", "Restored economy rejects duplicate schedule processing for already completed hour 24")

	# Snapshot independence (mutating live economy does not mutate prior snapshot)
	var gold_in_snap: int = int(snap["economy"]["gold"])
	ctx_mer.economy.credit_gold(77, "external_caravan", "dividend", 30)
	_assert(int(snap["economy"]["gold"]) == gold_in_snap, "Serialization snapshot is independent of subsequent live economy mutations")

	# Backward compatibility: Phase 1 context dictionary WITHOUT "economy" key
	var legacy_phase1_dict: Dictionary = {
		"settlement_id": "stl_legacy_p1",
		"origin_faction_id": "rival_military",
		"owner_faction_id": "rival_military",
		"next_villager_seq": 2,
		"villagers": [
			{
				"villager_id": "npc_stl_legacy_p1_1",
				"settlement_id": "stl_legacy_p1",
				"origin_faction_id": "rival_military",
				"name": "Legacy Guard",
				"role": "guard"
			}
		],
		"job_board": {},
		"workplace_registry": {}
	}
	var legacy_ctx = SettlementVillagerContextScript.from_dict(legacy_phase1_dict)
	_assert(legacy_ctx != null and legacy_ctx.get_villager_count() == 1, "Legacy Phase 1 context dict without 'economy' key restores villagers cleanly")
	_assert(
		legacy_ctx.economy != null
		and not legacy_ctx.economy.is_endowment_initialized
		and legacy_ctx.economy.get_resource("food") == 0
		and legacy_ctx.economy.get_gold() == 0
		and int(legacy_ctx.economy.get_military_logistics_state()["remaining_budget"]) == 0,
		"Restoring legacy Phase 1 context creates safe zero-balance non-minting economy"
	)
	_assert(legacy_ctx.economy.initialize_default_profile_endowment(6) and legacy_ctx.economy.get_resource("food") == 80, "Unendowed restored economy supports later explicit initialization")

	# Reject corrupt serialized economy dicts
	var corrupt_neg_stock: Dictionary = ctx_mer.economy.to_dict()
	corrupt_neg_stock["stock"]["food"] = -10
	_assert(SettlementEconomyScript.from_dict(corrupt_neg_stock) == null, "Corrupt negative stock rejected by SettlementEconomy.from_dict()")

	var corrupt_over_cap: Dictionary = ctx_mer.economy.to_dict()
	corrupt_over_cap["stock"]["food"] = 99999
	_assert(SettlementEconomyScript.from_dict(corrupt_over_cap) == null, "Corrupt over-capacity stock rejected by SettlementEconomy.from_dict()")

	var corrupt_ledger_mismatch: Dictionary = ctx_mer.economy.to_dict()
	corrupt_ledger_mismatch["gold"] = 999
	_assert(SettlementEconomyScript.from_dict(corrupt_ledger_mismatch) == null, "Corrupt balance/ledger mismatch rejected by SettlementEconomy.from_dict()")

	var corrupt_smith_enabled: Dictionary = ctx_mer.economy.to_dict()
	corrupt_smith_enabled["merchant_smith_enabled"] = true
	_assert(SettlementEconomyScript.from_dict(corrupt_smith_enabled) == null, "Enabling merchant_smith_enabled in serialized dict is rejected")

func _test_12_8_architectural_isolation() -> void:
	print("\n[12.8] Architectural Isolation & FactionData Strategic Invariance")
	var phase2_files: Array[String] = [
		"res://scripts/world/settlement_supply_ledger.gd",
		"res://scripts/world/settlement_economy.gd",
		"res://scripts/world/settlement_villager_context.gd"
	]
	var forbidden_tokens: Array[String] = [
		"CitizenController",
		"/root/ResourceManager",
		"ResourceManager.",
		"JobManager.",
		"WorkplaceManager.",
		"citizen_controller.gd",
		"job_manager.gd",
		"workplace_manager.gd",
		"resource_manager.gd",
		"FactionData"
	]
	for path in phase2_files:
		var f := FileAccess.open(path, FileAccess.READ)
		_assert(f != null, "Opened %s for static isolation audit" % path.get_file())
		if f != null:
			var code_lines := f.get_as_text().split("\n")
			var clean := true
			for line in code_lines:
				var trimmed := line.strip_edges()
				if trimmed.begins_with("#"):
					continue
				for tok in forbidden_tokens:
					if trimmed.find(tok) >= 0:
						clean = false
						printerr("Forbidden token '%s' in %s: %s" % [tok, path, trimmed])
			_assert(clean, "%s has zero code references to player ResourceManager/CitizenController/JobManager/WorkplaceManager/FactionData" % path.get_file())

	# Runtime check: FactionData.resources and FactionData.population remain completely unchanged
	var fm := FactionManagerScript.new()
	var mil_res_before: Dictionary = fm.get_faction("rival_military").resources.duplicate(true)
	var mer_res_before: Dictionary = fm.get_faction("rival_merchant").resources.duplicate(true)
	var tri_res_before: Dictionary = fm.get_faction("neutral_tribe").resources.duplicate(true)
	var mil_pop_before: int = fm.get_faction("rival_military").population
	var mer_pop_before: int = fm.get_faction("rival_merchant").population
	var tri_pop_before: int = fm.get_faction("neutral_tribe").population

	var c1 := SettlementVillagerContextScript.new("stl_iso_tribe", "neutral_tribe")
	var c2 := SettlementVillagerContextScript.new("stl_iso_mil", "rival_military")
	var c3 := SettlementVillagerContextScript.new("stl_iso_mer", "rival_merchant")
	c1.economy.process_forage_regeneration(24)
	c2.economy.process_military_logistics(24)
	c3.economy.purchase_from_market("food", 10, 12)
	c3.economy.process_market_restock(24)

	_assert(
		fm.get_faction("rival_military").resources == mil_res_before
		and fm.get_faction("rival_merchant").resources == mer_res_before
		and fm.get_faction("neutral_tribe").resources == tri_res_before
		and fm.get_faction("rival_military").population == mil_pop_before
		and fm.get_faction("rival_merchant").population == mer_pop_before
		and fm.get_faction("neutral_tribe").population == tri_pop_before,
		"FactionData.resources and FactionData.population remain 100% unchanged after all Phase 2 operations"
	)

func _test_12_9_hardening_reviews_a_to_g() -> void:
	print("\n[12.9] Independent Review & Economic Integrity Hardening (Reviews A–G)")

	# --- Review A: Initial Endowment & Repeated Initialization ---
	# Scenario A & B: New context & repeated initialization attempts
	var ctx_new := SettlementVillagerContextScript.new("stl_rev_a_mer", "rival_merchant")
	var snap_after_init: Dictionary = ctx_new.economy.to_dict()
	var tx_seq_after_init: int = ctx_new.economy.ledger.get_next_tx_seq()
	_assert(not ctx_new.economy.initialize_default_profile_endowment(0), "Review A.1: Calling initialize_default_profile_endowment() on already initialized context is rejected")
	_assert(not ctx_new.economy.initialize_default_profile_endowment(12), "Review A.2: Consecutive initialize_default_profile_endowment(12) is rejected")
	_assert(ctx_new.economy.ledger.record_initial_endowment("food", 500, "exploit_attempt", "settlement_stock:food", 1).is_empty(), "Review A.3: Direct ledger.record_initial_endowment() cannot overwrite existing endowment")
	_assert(ctx_new.economy.to_dict() == snap_after_init and ctx_new.economy.ledger.get_next_tx_seq() == tx_seq_after_init, "Review A.4: Repeated initialization attempts leave stock, gold, provider allocations, and tx_seq unchanged")

	# Scenario C & D: Legacy Phase 1 context initialized once, then rejected on repeat and after serialize/restore
	var legacy_dict: Dictionary = {
		"settlement_id": "stl_rev_a_legacy",
		"origin_faction_id": "neutral_tribe",
		"owner_faction_id": "neutral_tribe",
		"next_villager_seq": 1,
		"villagers": [],
		"job_board": {},
		"workplace_registry": {}
	}
	var leg_ctx = SettlementVillagerContextScript.from_dict(legacy_dict)
	_assert(leg_ctx != null and not leg_ctx.economy.is_endowment_initialized and leg_ctx.economy.get_resource("food") == 0, "Review A.5: Legacy Phase 1 context starts unendowed with 0 food")
	var uninit_restored = SettlementVillagerContextScript.from_dict(leg_ctx.to_dict())
	_assert(uninit_restored != null and not uninit_restored.economy.is_endowment_initialized, "Review A.6: Serializing and restoring uninitialized legacy economy preserves unendowed state")
	_assert(uninit_restored.economy.initialize_default_profile_endowment(6) and uninit_restored.economy.get_resource("food") == 60, "Review A.7: Explicit initialization on restored unendowed economy grants endowment once (60 food)")
	_assert(not uninit_restored.economy.initialize_default_profile_endowment(6), "Review A.8: Second initialization on legacy economy is rejected")
	var init_restored = SettlementVillagerContextScript.from_dict(uninit_restored.to_dict())
	_assert(init_restored != null and init_restored.economy.is_endowment_initialized and not init_restored.economy.initialize_default_profile_endowment(12), "Review A.9: Restored initialized economy rejects initialize_default_profile_endowment()")

	# Reject forged dictionary claiming is_endowment_initialized == false while holding stock/ledger history
	var forged_uninit: Dictionary = init_restored.economy.to_dict()
	forged_uninit["is_endowment_initialized"] = false
	_assert(SettlementEconomyScript.from_dict(forged_uninit) == null, "Review A.10: Forged dict with is_endowment_initialized=false and non-zero endowment is rejected")

	# --- Review B: Complete Accounting & Resource Conservation Across All 6 Accounts ---
	var mer_cons := SettlementEconomyScript.new("stl_rev_b_mer", "rival_merchant", true)
	mer_cons.purchase_from_market("food", 15, 10)
	mer_cons.process_market_restock(24)
	mer_cons.top_up_market_allocation("food", 25, "caravan_charter", 30)
	_assert(mer_cons.verify_provider_conservation() and mer_cons.ledger.verify_balance_consistency(mer_cons.get_all_resources(), mer_cons.get_gold()), "Review B.1: Merchant conservation holds across stock, gold, market stock, and restock allocation")
	# Internal transfer rule: market restock (20 food) must NOT be counted as settlement stock inflow; only purchased food (15) is settlement inflow
	_assert(mer_cons.ledger.get_total_inflow("food") == 15, "Review B.2: Market restock is not double-counted as settlement inventory inflow (only 15 purchased food is inflow)")
	# Single-authority gold check: _stock never contains a separate 'gold' entry
	_assert(not mer_cons.get_all_resources().has("gold") and mer_cons.get_resource("gold") == mer_cons.get_gold(), "Review B.3: Gold has single authoritative storage in _gold treasury")

	# Corrupting provider conservation totals in serialized dict is rejected
	var bad_mkt_cons: Dictionary = mer_cons.to_dict()
	bad_mkt_cons["market_provider"]["remaining_restock_allocation"]["food"] = 5
	_assert(SettlementEconomyScript.from_dict(bad_mkt_cons) == null, "Review B.4: Corrupt market restock allocation violating conservation equation is rejected")

	# --- Review C: Merchant Price Authority & Purchase Safety ---
	var mer_price := SettlementEconomyScript.new("stl_rev_c_mer", "rival_merchant", true)
	var snap_before_price_tests: Dictionary = mer_price.to_dict()
	_assert(not bool(mer_price.purchase_from_market("food", 5, 10, 1).get("ok", false)), "Review C.1: Caller-supplied lower price (1 < configured 2) rejected")
	_assert(not bool(mer_price.purchase_from_market("food", 5, 10, 5).get("ok", false)), "Review C.2: Caller-supplied higher price (5 > configured 2) rejected")
	_assert(not bool(mer_price.purchase_from_market("food", 5, 10, 0).get("ok", false)), "Review C.3: Zero caller price rejected")
	_assert(not bool(mer_price.purchase_from_market("food", 5, 10, -2).get("ok", false)), "Review C.4: Negative caller price rejected")
	_assert(not bool(mer_price.purchase_from_market("food", 5, 10, 2.5).get("ok", false)), "Review C.5: Non-integer caller price rejected")
	_assert(not bool(mer_price.purchase_from_market("food", 2000000000, 10).get("ok", false)), "Review C.6: Overflow / excessive purchase quantity rejected before multiplication")
	_assert(mer_price.to_dict() == snap_before_price_tests, "Review C.7: All rejected price/overflow purchase attempts leave complete economy snapshot 100% unchanged")
	var valid_quoted_buy: Dictionary = mer_price.purchase_from_market("food", 5, 10, 2)
	_assert(bool(valid_quoted_buy["ok"]) and int(valid_quoted_buy["unit_price"]) == 2 and int(valid_quoted_buy["total_cost"]) == 10, "Review C.8: Matching caller-quoted price (2) succeeds and charges authoritative total (10)")

	# --- Review D: Complete Snapshot Immutability on Rejected Provider Operations ---
	var mil_atom := SettlementEconomyScript.new("stl_rev_d_mil", "rival_military", true)
	var mil_snap_before: Dictionary = mil_atom.to_dict()
	_assert(not bool(mil_atom.process_military_logistics(10).get("ok", false)), "Review D.1: Early military logistics call rejected")
	_assert(not bool(mil_atom.top_up_military_logistics(500, "overflow_src", 10).get("ok", false)), "Review D.2: Over-max military logistics top-up rejected")
	_assert(not bool(mil_atom.top_up_military_logistics(10, "", 10).get("ok", false)), "Review D.3: Empty-source military logistics top-up rejected")
	_assert(mil_atom.to_dict() == mil_snap_before, "Review D.4: Complete military economy & ledger snapshot unchanged after rejected operations")

	# --- Review E & F: Chunked vs Single-Call Schedule Equivalence & Partial Capacity Recovery ---
	# 1. Forage: chunked (hours 3, 6, 9, 12, 18, 24 @ 2.5/6h) vs single-call (hour 24 @ 2.5/6h)
	var tribe_chunk := SettlementEconomyScript.new("stl_rev_e_chunk", "neutral_tribe", true)
	var tribe_single := SettlementEconomyScript.new("stl_rev_e_single", "neutral_tribe", true)
	tribe_chunk.configure_forage_provider(120, 2.5, 6)
	tribe_single.configure_forage_provider(120, 2.5, 6)
	for h in [3, 6, 9, 12, 18, 24]:
		tribe_chunk.process_forage_regeneration(h)
	tribe_single.process_forage_regeneration(24)
	_assert(
		tribe_chunk.get_resource("food") == 70
		and tribe_single.get_resource("food") == 70
		and is_equal_approx(float(tribe_chunk.get_forage_provider_state()["fractional_remainder"]), float(tribe_single.get_forage_provider_state()["fractional_remainder"]))
		and int(tribe_chunk.get_forage_provider_state()["elapsed_hours_remainder"]) == int(tribe_single.get_forage_provider_state()["elapsed_hours_remainder"]),
		"Review E.1: Chunked vs single-call forage regeneration across 24 hours produces identical stock (70) and remainders (0.0)"
	)

	# 2. Military partial capacity block during multi-interval jump (hours 24, 48, 72, 96 with headroom for only 2 batches = 40)
	var mil_part := SettlementEconomyScript.new("stl_rev_e_mil_part", "rival_military", true)
	mil_part.set_resource_capacity("food", 120) # initial food is 80 -> headroom is 40 (2 batches of 20)
	var p96_first: Dictionary = mil_part.process_military_logistics(96)
	_assert(
		bool(p96_first["ok"])
		and int(p96_first["delivered"]) == 40
		and int(p96_first["intervals_completed"]) == 2
		and String(p96_first["state"]) == SettlementEconomyScript.PROVIDER_STATE_WAITING_CAPACITY
		and int(p96_first["next_delivery_hour_seq"]) == 72,
		"Review E.2: Multi-interval military jump capped at 2 batches delivers 40, sets state='waiting_capacity', and preserves next_delivery_hour_seq=72"
	)
	mil_part.set_resource_capacity("food", 500)
	var p96_resume: Dictionary = mil_part.process_military_logistics(96)
	_assert(
		bool(p96_resume["ok"])
		and int(p96_resume["delivered"]) == 40
		and mil_part.get_resource("food") == 160
		and int(p96_resume["next_delivery_hour_seq"]) == 120,
		"Review E.3: Freeing capacity allows completing remaining 2 due batches at hour 96 without losing rations"
	)

	# --- Review G: Unknown Economy Profile Behavior ---
	var unknown_econ := SettlementEconomyScript.new("stl_rev_g_unknown", "unknown_faction_type", true)
	_assert(
		not unknown_econ.is_valid()
		and not unknown_econ.is_endowment_initialized
		and unknown_econ.get_resource("food") == 0
		and unknown_econ.get_gold() == 0
		and not unknown_econ.initialize_default_profile_endowment(0)
		and not bool(unknown_econ.credit_resource("food", 10, "src", "rsn", 1).get("ok", false)),
		"Review G.1: Unknown economy profile fails explicitly, remains at zero balances, and never mints resources"
	)

func _test_12_10_final_api_and_supply_integrity_audit() -> void:
	print("\n[12.10] Final Economic API & Supply Integrity Audit (Reviews A–E)")

	# --- Final Review A: Ledger Mutation API & Ownership ---
	var econ_la := SettlementEconomyScript.new("stl_final_rev_a", "neutral_tribe", true)
	var snap_la_before: Dictionary = econ_la.to_dict()
	var seq_la_before: int = econ_la.ledger.get_next_tx_seq()
	_assert(econ_la.ledger.record_inflow("food", 50, "bypass_src", "settlement_stock:food", "bypass", 10, 110).is_empty(), "Final A.1: Direct external econ.ledger.record_inflow() is rejected")
	_assert(econ_la.ledger.record_outflow("food", 10, "settlement_stock:food", "bypass_dst", "bypass", 10, 50).is_empty(), "Final A.2: Direct external econ.ledger.record_outflow() is rejected")
	_assert(econ_la.ledger.record_provider_event("food", 20, "bypass_src", "provider:test", "bypass", 10, 20).is_empty(), "Final A.3: Direct external econ.ledger.record_provider_event() is rejected")
	_assert(econ_la.ledger.record_initial_endowment("stone", 99, "bypass_src", "settlement_stock:stone", 0).is_empty(), "Final A.4: Direct external econ.ledger.record_initial_endowment() is rejected")
	econ_la.ledger.max_history_entries = 0
	econ_la.ledger.max_history_entries = -5
	_assert(
		econ_la.to_dict() == snap_la_before
		and econ_la.ledger.get_next_tx_seq() == seq_la_before
		and econ_la.is_valid(),
		"Final A.5: External ledger mutation attempts leave authoritative ledger, tx_seq, and economy validity 100% unchanged"
	)
	var l_snap: Dictionary = econ_la.get_ledger_snapshot()
	l_snap["total_inflows"]["food"] = 99999
	_assert(econ_la.ledger.get_total_inflow("food") == 0, "Final A.6: get_ledger_snapshot() returns an independent defensive copy")

	# --- Final Review B: Finite External Top-Up & Grant Replay Protection ---
	var mil_b := SettlementEconomyScript.new("stl_final_rev_b_mil", "rival_military", true)
	# Drain initial 120 budget across 6 deliveries (hours 24..144) so remaining_budget == 0
	mil_b.process_military_logistics(144)
	_assert(int(mil_b.get_military_logistics_state()["remaining_budget"]) == 0, "Final B.1: Military initial logistics budget depleted (0)")

	var top_ok: Dictionary = mil_b.top_up_military_logistics(40, "high_command_convoy", 150, "grant_mil_001")
	_assert(bool(top_ok["ok"]) and int(top_ok["remaining_budget"]) == 40, "Final B.2: Valid authorized top-up ('grant_mil_001', 40) succeeds")

	var mil_b_snap_after_g1: Dictionary = mil_b.to_dict()
	# Duplicate grant ID with same amount, different amount, invalid grant ID, non-positive amount, and over-max amount
	_assert(not bool(mil_b.top_up_military_logistics(40, "high_command_convoy", 152, "grant_mil_001").get("ok", false)), "Final B.3: Duplicate grant_id ('grant_mil_001') with same amount is rejected")
	_assert(not bool(mil_b.top_up_military_logistics(15, "high_command_convoy", 152, "grant_mil_001").get("ok", false)), "Final B.4: Duplicate grant_id ('grant_mil_001') with different amount is rejected")
	_assert(not bool(mil_b.top_up_military_logistics(20, "high_command_convoy", 152, "invalid grant id!").get("ok", false)), "Final B.5: Malformed grant_id with spaces/symbols is rejected")
	_assert(not bool(mil_b.top_up_military_logistics(0, "high_command_convoy", 152, "grant_mil_zero").get("ok", false)), "Final B.6: Zero top-up amount is rejected")
	_assert(not bool(mil_b.top_up_military_logistics(250, "high_command_convoy", 152, "grant_mil_over").get("ok", false)), "Final B.7: Top-up exceeding max_allocation is rejected")
	_assert(mil_b.to_dict() == mil_b_snap_after_g1, "Final B.8: All rejected/duplicate military grant attempts leave economy & ledger untouched")

	# Restore from dict and verify duplicate grant is still rejected after save/load
	var mil_b_restored = SettlementEconomyScript.from_dict(mil_b.to_dict())
	_assert(mil_b_restored != null and not bool(mil_b_restored.top_up_military_logistics(40, "high_command_convoy", 160, "grant_mil_001").get("ok", false)), "Final B.9: Restored economy rejects replay of previously processed grant 'grant_mil_001'")

	# Distinct valid grants succeed up to max_cumulative_top_ups (240), then further grants are rejected even if remaining_budget is drained
	_assert(bool(mil_b_restored.top_up_military_logistics(200, "high_command_convoy", 160, "grant_mil_002").get("ok", false)), "Final B.10: Distinct authorized grant 'grant_mil_002' (+200, cumulative 240/240) succeeds")
	mil_b_restored.set_resource_capacity("food", 1000)
	mil_b_restored.process_military_logistics(240) # drains some remaining_budget so current budget < 240
	var over_cum: Dictionary = mil_b_restored.top_up_military_logistics(20, "high_command_convoy", 242, "grant_mil_003")
	_assert(not bool(over_cum["ok"]) and String(over_cum["reason"]) == "exceeds_max_cumulative_top_ups", "Final B.11: Cumulative lifetime top-up cap prevents unbounded lifetime supply across repeated grants")

	# Same grant replay & cumulative cap verification for Merchant top_up_market_allocation
	var mer_b := SettlementEconomyScript.new("stl_final_rev_b_mer", "rival_merchant", true)
	mer_b.process_market_restock(24) # consumes 20 food restock allocation (120 -> 100)
	_assert(bool(mer_b.top_up_market_allocation("food", 20, "south_sea_charter", 30, "mkt_grant_01").get("ok", false)), "Final B.12: Valid Merchant market allocation grant 'mkt_grant_01' succeeds")
	_assert(not bool(mer_b.top_up_market_allocation("food", 10, "south_sea_charter", 32, "mkt_grant_01").get("ok", false)), "Final B.13: Duplicate Merchant grant 'mkt_grant_01' with different amount is rejected")
	var mer_b_restored = SettlementEconomyScript.from_dict(mer_b.to_dict())
	_assert(mer_b_restored != null and not bool(mer_b_restored.top_up_market_allocation("food", 10, "south_sea_charter", 36, "mkt_grant_01").get("ok", false)), "Final B.14: Restored Merchant economy rejects replay of 'mkt_grant_01'")

	# --- Final Review C: Merchant Market Price Authority ---
	var mer_c := SettlementEconomyScript.new("stl_final_rev_c", "rival_merchant", true)
	_assert(mer_c.get_market_price("food") == 2, "Final C.1: Default configured food price is 2")
	_assert(not mer_c.set_market_price("ore", 5) and not mer_c.set_market_price("unknown", 5), "Final C.2: set_market_price rejects unapproved/invalid resources ('ore', 'unknown')")
	_assert(
		not mer_c.set_market_price("food", 0)
		and not mer_c.set_market_price("food", -3)
		and not mer_c.set_market_price("food", 2.5)
		and not mer_c.set_market_price("food", "bad")
		and not mer_c.set_market_price("food", SettlementEconomyScript.MAX_SAFE_TRANSACTION_AMOUNT + 1),
		"Final C.3: set_market_price rejects zero, negative, fractional, non-numeric, and overflow prices"
	)
	_assert(mer_c.set_market_price("food", 3) and mer_c.get_market_price("food") == 3, "Final C.4: Approved configuration override updates food price to 3")
	_assert(not bool(mer_c.purchase_from_market("food", 4, 12, 2).get("ok", false)), "Final C.5: Caller quote of old price (2 < 3) is rejected after price override")
	var buy_at_3: Dictionary = mer_c.purchase_from_market("food", 4, 12, 3)
	_assert(bool(buy_at_3["ok"]) and int(buy_at_3["unit_price"]) == 3 and int(buy_at_3["total_cost"]) == 12, "Final C.6: Purchase uses updated configured price (4 * 3 = 12 gold)")
	var mer_c_restored = SettlementEconomyScript.from_dict(mer_c.to_dict())
	_assert(mer_c_restored != null and mer_c_restored.get_market_price("food") == 3, "Final C.7: Configured market price persists across serialization/restoration")
	var bad_price_dict: Dictionary = mer_c.to_dict()
	bad_price_dict["market_provider"]["prices"]["food"] = 0
	_assert(SettlementEconomyScript.from_dict(bad_price_dict) == null, "Final C.8: Serialized market dict with price <= 0 is rejected")

	# --- Final Review D: Merchant Multi-Interval Restock Under Capacity Blocking (Steps 1–13) ---
	var mer_d := SettlementEconomyScript.new("stl_final_rev_d", "rival_merchant", true)
	# Cap non-food resources at their current initial market stock so only 'food' has headroom for exactly 2 batches (2 * 20 = 40 -> cap 100)
	for res_id in SettlementEconomyScript.MERCHANT_MARKET_RESOURCES:
		if res_id == "food":
			_assert(mer_d.set_market_capacity("food", 100), "Final D.1: Configured food market capacity to 100 (initial 60 + 2 batches of 20)")
		else:
			mer_d.set_market_capacity(res_id, mer_d.get_market_stock(res_id))

	# Step 5: Call process_market_restock(96) covering 4 due intervals (hours 24, 48, 72, 96)
	var m_r96_first: Dictionary = mer_d.process_market_restock(96)
	_assert(
		bool(m_r96_first["ok"])
		and int(m_r96_first["intervals_completed"]) == 2
		and int(m_r96_first["total_restocked"]) == 40
		and mer_d.get_market_stock("food") == 100
		and mer_d.get_market_remaining_allocation("food") == 80
		and int(m_r96_first["next_restock_hour_seq"]) == 72
		and int(m_r96_first["last_completed_restock_hour_seq"]) == 48
		and String(m_r96_first["state"]) == SettlementEconomyScript.PROVIDER_STATE_WAITING_CAPACITY,
		"Final D.2 (Steps 5–8): 4-interval jump with 2-batch headroom applies 2 batches (+40 food), preserves remaining 80 allocation, leaves next_restock_hour_seq=72 pending, and sets 'waiting_capacity'"
	)

	# Serialize & restore while waiting for capacity at hour 96
	var mer_d_restored = SettlementEconomyScript.from_dict(mer_d.to_dict())
	_assert(mer_d_restored != null and mer_d_restored.is_valid(), "Final D.3: Serialization & restoration while in 'waiting_capacity' succeeds")
	var m_r96_still_blocked: Dictionary = mer_d_restored.process_market_restock(96)
	_assert(not bool(m_r96_still_blocked["ok"]) and String(m_r96_still_blocked["reason"]) == "waiting_capacity" and mer_d_restored.get_market_remaining_allocation("food") == 80, "Final D.4: Calling process_market_restock(96) while still full preserves allocation")

	# Steps 9–13: Increase food market capacity to 160 and call process_market_restock(96) at the same hour_seq = 96
	_assert(mer_d_restored.set_market_capacity("food", 160), "Final D.5 (Step 9): Increased food market capacity to 160")
	var m_r96_resume: Dictionary = mer_d_restored.process_market_restock(96)
	_assert(
		bool(m_r96_resume["ok"])
		and int(m_r96_resume["intervals_completed"]) == 2
		and int(m_r96_resume["total_restocked"]) == 40
		and mer_d_restored.get_market_stock("food") == 140
		and mer_d_restored.get_market_remaining_allocation("food") == 40
		and int(m_r96_resume["next_restock_hour_seq"]) == 120
		and int(m_r96_resume["last_completed_restock_hour_seq"]) == 96,
		"Final D.6 (Steps 10–12): Resuming at same hour_seq=96 completes remaining 2 intervals (+40 food -> 140, rem_alloc=40, next_due=120)"
	)
	var m_r96_dup: Dictionary = mer_d_restored.process_market_restock(96)
	_assert(not bool(m_r96_dup["ok"]) and String(m_r96_dup["reason"]) == "not_due_or_already_processed", "Final D.7: Subsequent call at hour 96 is rejected without duplicate restock")
	_assert(mer_d_restored.verify_provider_conservation() and mer_d_restored.ledger.verify_balance_consistency(mer_d_restored.get_all_resources(), mer_d_restored.get_gold()), "Final D.8 (Step 13): All ledger and provider conservation equations hold after resumed restock")

	# --- Final Review E: Transaction Notification & Reentrancy Safety ---
	var mer_e := SettlementEconomyScript.new("stl_final_rev_e", "rival_merchant", true)
	var callback_records: Array[Dictionary] = []
	var did_nested_purchase: Array[bool] = [false]

	var cb_callable := func(receipt: Dictionary) -> void:
		var valid_in_cb: bool = mer_e.is_valid() and mer_e.verify_provider_conservation() and mer_e.ledger.verify_balance_consistency(mer_e.get_all_resources(), mer_e.get_gold())
		# Attempt replay of the same restock inside callback (must fail because state is already committed)
		var replay_try: Dictionary = mer_e.process_market_restock(24)
		callback_records.append({
			"receipt": receipt,
			"valid_in_cb": valid_in_cb,
			"replay_rejected": not bool(replay_try.get("ok", false))
		})
		# Trigger one nested purchase from inside the restock callback
		if not did_nested_purchase[0] and receipt.has("total_restocked"):
			did_nested_purchase[0] = true
			mer_e.purchase_from_market("food", 5, 24)

	mer_e.transaction_committed.connect(cb_callable)
	var restock_e24: Dictionary = mer_e.process_market_restock(24)
	mer_e.transaction_committed.disconnect(cb_callable)
	_assert(bool(restock_e24["ok"]) and callback_records.size() == 2, "Final E.1: Restock and nested purchase each emitted transaction_committed in order")
	_assert(
		bool(callback_records[0]["valid_in_cb"])
		and bool(callback_records[0]["replay_rejected"])
		and bool(callback_records[1]["valid_in_cb"]),
		"Final E.2: Callbacks observe 100% committed/consistent state and cannot replay an in-flight schedule event"
	)
	var nested_receipt: Dictionary = callback_records[1]["receipt"]
	_assert(
		String(nested_receipt.get("gold_tx_id", "")) != String(nested_receipt.get("goods_tx_id", ""))
		and mer_e.get_resource("food") == 75
		and mer_e.get_gold() == 110
		and mer_e.is_valid(),
		"Final E.3: Nested transaction initiated from callback receives distinct tx_ids and preserves full accounting consistency"
	)
