extends SceneTree
## =============================================================================
## KINGDOMS UNBOUND — Package 3C Regression Test Suite
## Dynamic Trade Route Risk & Caravan Economy (GDD §11.1, §11.2)
## Verifies route corridor calculation, Fog of War evaluation, territorial security,
## hostile outpost interception, deterministic pricing, transaction atomicity,
## bid/ask spread invariants, and save/load persistence.
## =============================================================================

const TradeCaravanScript = preload("res://scripts/trade/trade_caravan.gd")
const TradeRouteCalculatorScript = preload("res://scripts/trade/trade_route_calculator.gd")
const WorldViewScene = preload("res://scenes/world/world_view.tscn")
const FogOfWarScript = preload("res://scripts/world/fog_of_war.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const SiegeObjectiveActorScript = preload("res://scripts/combat/siege_objective_actor.gd")

class MockFSM extends RefCounted:
	var objectives: Array = []
	func get_all_objectives() -> Array:
		return objectives

class MockResourceManager extends RefCounted:
	var gold: int = 0
	var stock: Dictionary = {}

	func has_resource(res_id: String, amount: int) -> bool:
		if res_id == EconomyConfigScript.RES_GOLD:
			return gold >= amount
		return stock.get(res_id, 0) >= amount

	func get_available_stock(res_id: String) -> int:
		if res_id == EconomyConfigScript.RES_GOLD:
			return gold
		return stock.get(res_id, 0)

	func get_total_stock(res_id: String) -> int:
		return get_available_stock(res_id)

	func get_storage_capacity(_res_id: String) -> int:
		return 999999

	func consume_resource(res_id: String, amount: int) -> bool:
		if res_id == EconomyConfigScript.RES_GOLD:
			if gold >= amount:
				gold -= amount
				return true
			return false
		if stock.get(res_id, 0) >= amount:
			stock[res_id] -= amount
			return true
		return false

	func add_resource(res_id: String, amount: int) -> int:
		if res_id == EconomyConfigScript.RES_GOLD:
			gold += amount
			return amount
		stock[res_id] = stock.get(res_id, 0) + amount
		return amount

var _tests_passed: int = 0
var _tests_failed: int = 0

func _init() -> void:
	print("\n========================================================")
	print("  RUNNING PACKAGE 3C TEST SUITE: DYNAMIC TRADE ROUTE RISK")
	print("========================================================\n")

	_run_all_tests()

	print("\n========================================================")
	print("  PACKAGE 3C TEST RESULTS SUMMARY")
	print("  Passed: %d | Failed: %d" % [_tests_passed, _tests_failed])
	print("========================================================\n")

	if _tests_failed > 0:
		quit(1)
	else:
		quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_tests_passed += 1
		print("  [PASS] %s" % message)
	else:
		_tests_failed += 1
		printerr("  [FAIL] %s" % message)

func _run_all_tests() -> void:
	test_tc_tr_01_bresenham_line_corridor()
	test_tc_tr_02_neutral_baseline_pricing()
	test_tc_tr_03_deterministic_route_risk()
	test_tc_tr_04_unexplored_fog_surcharge()
	test_tc_tr_05_player_outpost_security_discount()
	test_tc_tr_06_player_watchtower_security()
	test_tc_tr_07_enemy_outposts_do_not_grant_player_security()
	test_tc_tr_08_outpost_ownership_transfer_and_destruction()
	test_tc_tr_09_quote_equals_transaction_price()
	test_tc_tr_10_no_double_modifier_application()
	test_tc_tr_11_failed_transactions_resource_conservation()
	test_tc_tr_12_bid_ask_spread_and_no_arbitrage()
	test_tc_tr_13_legacy_save_compatibility()
	test_tc_tr_14_route_risk_save_load_roundtrip()
	test_tc_tr_15_world_view_event_driven_integration()

	# Package 3C.1 Targeted 18-Scenario Matrix
	test_sc_01_horizontal_corridor()
	test_sc_02_vertical_corridor()
	test_sc_03_diagonal_symmetric_corridor()
	test_sc_04_non_square_displacement()
	test_sc_05_out_of_bounds_endpoints()
	test_sc_06_same_cell_corridor()
	test_sc_07_map_boundary_coordinates()
	test_sc_08_null_missing_fow_fallback()
	test_sc_09_fully_unexplored_corridor()
	test_sc_10_single_friendly_outpost()
	test_sc_11_overlapping_friendly_outposts()
	test_sc_12_friendly_watchtower_and_outpost_overlap()
	test_sc_13_overlapping_hostile_outposts()
	test_sc_14_contested_cell_cancels_and_exposes_both_reasons()
	test_sc_15_destroyed_stale_outpost_safely_rejected()
	test_sc_16_origin_faction_wartime_status()
	test_sc_17_restless_bandits_modifier()
	test_sc_18_final_risk_clamp_exact_boundaries()

# -----------------------------------------------------------------------------
# 1. TC-TR.01: Bresenham Line Corridor Traversal
# -----------------------------------------------------------------------------
func test_tc_tr_01_bresenham_line_corridor() -> void:
	print("\n--- TC-TR.01: Bresenham Line Corridor Traversal ---")
	var line_h := TradeRouteCalculatorScript.compute_route_cells(Vector2i(10, 10), Vector2i(14, 10))
	_assert(line_h.size() == 5, "TC-TR.01.1: Horizontal 4-cell step produces 5 corridor cells")
	_assert(line_h[0] == Vector2i(10, 10), "TC-TR.01.2: First cell is start")
	_assert(line_h[4] == Vector2i(14, 10), "TC-TR.01.3: Last cell is end")

	var line_diag := TradeRouteCalculatorScript.compute_route_cells(Vector2i(20, 20), Vector2i(23, 23))
	_assert(line_diag.size() == 4, "TC-TR.01.4: Diagonal step produces 4 cells")
	_assert(line_diag[1] == Vector2i(21, 21), "TC-TR.01.5: Diagonal midpoint (21, 21) traversed")

	var single := TradeRouteCalculatorScript.compute_route_cells(Vector2i(15, 15), Vector2i(15, 15))
	_assert(single.size() == 1, "TC-TR.01.6: Single identical cell step produces 1 cell")

# -----------------------------------------------------------------------------
# 2. TC-TR.02: Neutral Baseline Pricing Unchanged
# -----------------------------------------------------------------------------
func test_tc_tr_02_neutral_baseline_pricing() -> void:
	print("\n--- TC-TR.02: Neutral Baseline Pricing Unchanged ---")
	var fow = FogOfWarScript.new(64)
	# Mark all cells in route as EXPLORED
	var route := [Vector2i(10, 10), Vector2i(11, 10), Vector2i(12, 10), Vector2i(13, 10)]
	for c in route:
		fow.set_state(c, FogOfWarScript.State.EXPLORED)

	var res: Dictionary = TradeRouteCalculatorScript.evaluate_route_risk(route, fow, null, null, false)
	_assert(is_equal_approx(float(res.get("net_risk", 1.0)), 0.0), "TC-TR.02.1: Neutral route net risk is identically 0.0")

	var caravan = TradeCaravanScript.generate_caravan(12345, 3, "rival_merchant", false)
	caravan.set_route_risk(res.get("net_risk"), res)
	var bd: Dictionary = caravan.get_price_breakdown(EconomyConfigScript.RES_WOOD, 0.0, null)
	_assert(is_equal_approx(float(bd.get("route_risk_surcharge", -1.0)), 0.0), "TC-TR.02.2: Neutral route risk surcharge is 0.0")
	_assert(bd.get("final_sell_price") == 3, "TC-TR.02.3: Baseline Wood sell price is 3 Gold")
	_assert(bd.get("final_buy_price") == 2, "TC-TR.02.4: Baseline Wood buy price is 2 Gold")

# -----------------------------------------------------------------------------
# 3. TC-TR.03: Deterministic Route Risk
# -----------------------------------------------------------------------------
func test_tc_tr_03_deterministic_route_risk() -> void:
	print("\n--- TC-TR.03: Deterministic Route Risk ---")
	var fow = FogOfWarScript.new(64)
	var route := [Vector2i(20, 20), Vector2i(21, 20), Vector2i(22, 20), Vector2i(23, 20)]
	fow.set_state(route[0], FogOfWarScript.State.UNEXPLORED)
	fow.set_state(route[1], FogOfWarScript.State.EXPLORED)
	fow.set_state(route[2], FogOfWarScript.State.VISIBLE)
	fow.set_state(route[3], FogOfWarScript.State.UNEXPLORED)

	var res1 := TradeRouteCalculatorScript.evaluate_route_risk(route, fow, null, null, false)
	var res2 := TradeRouteCalculatorScript.evaluate_route_risk(route, fow, null, null, false)
	_assert(is_equal_approx(float(res1["net_risk"]), float(res2["net_risk"])), "TC-TR.03.1: Repeated evaluations return identical net risk")
	_assert(int(res1["unexplored_cells"]) == int(res2["unexplored_cells"]), "TC-TR.03.2: Identical unexplored cell counts")
	_assert(is_equal_approx(float(res1["unexplored_ratio"]), 0.50), "TC-TR.03.3: 2 of 4 cells unexplored produces exactly 0.50 ratio")

# -----------------------------------------------------------------------------
# 4. TC-TR.04: Unexplored Fog Surcharge
# -----------------------------------------------------------------------------
func test_tc_tr_04_unexplored_fog_surcharge() -> void:
	print("\n--- TC-TR.04: Unexplored Fog Surcharge ---")
	var fow = FogOfWarScript.new(64)
	var route := [Vector2i(30, 30), Vector2i(31, 30), Vector2i(32, 30), Vector2i(33, 30)]
	# All 4 cells start UNEXPLORED
	var res := TradeRouteCalculatorScript.evaluate_route_risk(route, fow, null, null, false)
	_assert(is_equal_approx(float(res["unexplored_ratio"]), 1.0), "TC-TR.04.1: 100% unexplored path")
	_assert(is_equal_approx(float(res["net_risk"]), 0.15), "TC-TR.04.2: 100% unexplored path produces exactly +0.15 surcharge")

	var caravan = TradeCaravanScript.generate_caravan(12345, 3, "rival_merchant", false)
	caravan.set_route_risk(res["net_risk"], res)
	var bd: Dictionary = caravan.get_price_breakdown(EconomyConfigScript.RES_METAL, 0.0, null)
	_assert(is_equal_approx(float(bd["route_risk_surcharge"]), 0.15), "TC-TR.04.3: Price breakdown incorporates +15% route risk")
	# Base sell for Metal is 8 -> 8 * 1.15 = 9.2 -> 9 Gold
	_assert(bd["final_sell_price"] == 9, "TC-TR.04.4: Metal sell price increases from 8 to 9 Gold under wilderness risk")

# -----------------------------------------------------------------------------
# 5. TC-TR.05: Player Outpost Security Discount
# -----------------------------------------------------------------------------
func test_tc_tr_05_player_outpost_security_discount() -> void:
	print("\n--- TC-TR.05: Player Outpost Security Discount ---")
	# Mock FieldSiegeManager with player-owned outpost at (20, 20) with radius 6
	var mock_fsm = MockFSM.new()
	var mock_outpost := SiegeObjectiveActorScript.new()
	mock_outpost.objective_id = "test_player_outpost"
	mock_outpost.current_cell = Vector2i(20, 20)
	mock_outpost.owning_faction_id = "player"
	mock_outpost.vision_radius = 6
	mock_outpost.is_alive = true
	mock_outpost.health = 300.0
	mock_fsm.objectives = [mock_outpost]

	# Route completely within outpost influence (e.g. dist <= 6 from (20, 20))
	var route := [Vector2i(19, 20), Vector2i(20, 20), Vector2i(21, 20), Vector2i(22, 20)]
	var fow = FogOfWarScript.new(64)
	for c in route: fow.set_state(c, FogOfWarScript.State.VISIBLE)

	# Direct evaluation test
	var res := TradeRouteCalculatorScript.evaluate_route_risk(route, fow, mock_fsm, null, false)
	_assert(int(res["secured_cells"]) == 4, "TC-TR.05.1: All 4 cells secured by player outpost")
	_assert(is_equal_approx(float(res["secured_ratio"]), 1.0), "TC-TR.05.2: 100% secured ratio")
	_assert(is_equal_approx(float(res["net_risk"]), -0.10), "TC-TR.05.3: Net risk is exactly -0.10 (-10% discount)")

	var caravan = TradeCaravanScript.generate_caravan(12345, 3, "rival_merchant", false)
	caravan.set_route_risk(res["net_risk"], res)
	var bd: Dictionary = caravan.get_price_breakdown(EconomyConfigScript.RES_TOOLS, 0.0, null)
	# Tools base sell is 15 -> 15 * 0.90 = 13.5 -> 14 Gold
	_assert(bd["final_sell_price"] == 14, "TC-TR.05.4: Tools sell price discounted from 15 to 14 Gold on secured route")

	mock_outpost.free()

# -----------------------------------------------------------------------------
# 6. TC-TR.06: Player Watchtower Security
# -----------------------------------------------------------------------------
func test_tc_tr_06_player_watchtower_security() -> void:
	print("\n--- TC-TR.06: Player Watchtower Security ---")
	var mock_wd = WorldGenerator.WorldData.new()
	var blds: Array[Dictionary] = [
		{
			"id": "bld_wt_1",
			"type": "watchtower",
			"cell": Vector2i(30, 30),
			"state": "active"
		}
	]
	mock_wd.buildings = blds
	var fow = FogOfWarScript.new(64)
	# Cells within radius 15 of watchtower (30, 30)
	var route := [Vector2i(30, 32), Vector2i(30, 33), Vector2i(30, 34)]
	for c in route: fow.set_state(c, FogOfWarScript.State.VISIBLE)

	var res := TradeRouteCalculatorScript.evaluate_route_risk(route, fow, null, mock_wd, false)
	_assert(int(res["secured_cells"]) == 3, "TC-TR.06.1: All cells secured by active Watchtower")
	_assert(is_equal_approx(float(res["net_risk"]), -0.10), "TC-TR.06.2: Watchtower protection grants full -10% discount")

# -----------------------------------------------------------------------------
# 7. TC-TR.07: Enemy Outposts Do NOT Grant Player Security
# -----------------------------------------------------------------------------
func test_tc_tr_07_enemy_outposts_do_not_grant_player_security() -> void:
	print("\n--- TC-TR.07: Enemy Outposts Hostile Interception ---")
	var mock_fsm = MockFSM.new()
	var enemy_outpost := SiegeObjectiveActorScript.new()
	enemy_outpost.objective_id = "enemy_outpost_1"
	enemy_outpost.current_cell = Vector2i(20, 20)
	enemy_outpost.owning_faction_id = "rival_military" # Enemy
	enemy_outpost.vision_radius = 6
	enemy_outpost.is_alive = true
	enemy_outpost.health = 300.0
	mock_fsm.objectives = [enemy_outpost]

	var route := [Vector2i(20, 20), Vector2i(21, 20), Vector2i(22, 20)]
	var fow = FogOfWarScript.new(64)
	for c in route: fow.set_state(c, FogOfWarScript.State.EXPLORED)

	var res := TradeRouteCalculatorScript.evaluate_route_risk(route, fow, mock_fsm, null, false)
	_assert(int(res["secured_cells"]) == 0, "TC-TR.07.1: Enemy outpost grants ZERO secured cells")
	_assert(int(res["hostile_cells"]) == 3, "TC-TR.07.2: Route within enemy outpost zone marked as hostile")
	_assert(is_equal_approx(float(res["net_risk"]), 0.10), "TC-TR.07.3: Enemy presence adds +0.10 (+10%) hostile surcharge")

	enemy_outpost.free()

# -----------------------------------------------------------------------------
# 8. TC-TR.08: Outpost Ownership Transfer and Destruction
# -----------------------------------------------------------------------------
func test_tc_tr_08_outpost_ownership_transfer_and_destruction() -> void:
	print("\n--- TC-TR.08: Outpost Ownership Transfer & Destruction ---")
	var mock_fsm = MockFSM.new()
	var test_outpost := SiegeObjectiveActorScript.new()
	test_outpost.objective_id = "trans_outpost"
	test_outpost.current_cell = Vector2i(15, 15)
	test_outpost.owning_faction_id = "rival_military" # Starts hostile
	test_outpost.vision_radius = 6
	test_outpost.is_alive = true
	test_outpost.health = 250.0
	mock_fsm.objectives = [test_outpost]

	var route := [Vector2i(15, 15), Vector2i(16, 15)]
	var fow = FogOfWarScript.new(64)
	for c in route: fow.set_state(c, FogOfWarScript.State.EXPLORED)

	# 1. Hostile initial state
	var res1 := TradeRouteCalculatorScript.evaluate_route_risk(route, fow, mock_fsm, null, false)
	_assert(is_equal_approx(float(res1["net_risk"]), 0.10), "TC-TR.08.1: Hostile outpost adds +10% risk")

	# 2. Player captures outpost
	test_outpost.owning_faction_id = "player"
	var res2 := TradeRouteCalculatorScript.evaluate_route_risk(route, fow, mock_fsm, null, false)
	_assert(is_equal_approx(float(res2["net_risk"]), -0.10), "TC-TR.08.2: Captured outpost immediately converts to -10% security discount")

	# 3. Outpost destroyed
	test_outpost.health = 0.0
	test_outpost.is_alive = false
	var res3 := TradeRouteCalculatorScript.evaluate_route_risk(route, fow, mock_fsm, null, false)
	_assert(is_equal_approx(float(res3["net_risk"]), 0.0), "TC-TR.08.3: Destroyed outpost ceases contributing security (neutral 0.0)")

	test_outpost.free()

# -----------------------------------------------------------------------------
# 9. TC-TR.09: Displayed Quote Equals Transaction Price
# -----------------------------------------------------------------------------
func test_tc_tr_09_quote_equals_transaction_price() -> void:
	print("\n--- TC-TR.09: Quote Equals Transaction Price ---")
	var caravan = TradeCaravanScript.generate_caravan(9999, 5, "rival_merchant", false)
	caravan.set_route_risk(0.15, {"unexplored_ratio": 1.0})

	# Mock resource manager
	var rm = MockResourceManager.new()
	rm.gold = 500
	rm.stock = {"wood": 100, "metal": 50}

	for res_id in [EconomyConfigScript.RES_FOOD, EconomyConfigScript.RES_WOOD, EconomyConfigScript.RES_METAL]:
		var bd: Dictionary = caravan.get_price_breakdown(res_id, 0.0, rm)
		var quote_sell: int = int(bd["final_sell_price"])
		var eff_sell: int = caravan.get_effective_sell_price(res_id, 0.0, rm)
		_assert(quote_sell == eff_sell, "TC-TR.09.1 (%s): Breakdown quote (%d) equals effective sell price (%d)" % [res_id, quote_sell, eff_sell])

		var quote_buy: int = int(bd["final_buy_price"])
		var eff_buy: int = caravan.get_effective_buy_price(res_id, 0.0, rm)
		_assert(quote_buy == eff_buy, "TC-TR.09.2 (%s): Breakdown quote (%d) equals effective buy price (%d)" % [res_id, quote_buy, eff_buy])

# -----------------------------------------------------------------------------
# 10. TC-TR.10: No Double Modifier Application
# -----------------------------------------------------------------------------
func test_tc_tr_10_no_double_modifier_application() -> void:
	print("\n--- TC-TR.10: No Double Modifier Application ---")
	var caravan = TradeCaravanScript.generate_caravan(8888, 3, "rival_merchant", false)
	caravan.set_route_risk(0.20, {"wartime": true})

	var price_1: int = caravan.get_effective_sell_price(EconomyConfigScript.RES_METAL)
	var price_2: int = caravan.get_effective_sell_price(EconomyConfigScript.RES_METAL)
	var price_3: int = caravan.get_effective_sell_price(EconomyConfigScript.RES_METAL)
	_assert(price_1 == price_2 and price_2 == price_3, "TC-TR.10.1: Multiple queries return identical invariant price (%d)" % price_1)

# -----------------------------------------------------------------------------
# 11. TC-TR.11: Failed Transactions Resource Conservation
# -----------------------------------------------------------------------------
func test_tc_tr_11_failed_transactions_resource_conservation() -> void:
	print("\n--- TC-TR.11: Failed Transactions Resource Conservation ---")
	var caravan = TradeCaravanScript.generate_caravan(7777, 3, "rival_merchant", false)
	caravan.set_route_risk(0.25, {})
	caravan.inventory[EconomyConfigScript.RES_CRYSTAL] = 2

	var rm = MockResourceManager.new()
	rm.gold = 10 # Cannot afford crystal (costs > 35)

	var res: Dictionary = caravan.buy_from_caravan(EconomyConfigScript.RES_CRYSTAL, 1, rm, 0.0)
	_assert(not res.get("success", false), "TC-TR.11.1: Buy transaction fails due to insufficient gold")
	_assert(int(rm.gold) == 10, "TC-TR.11.2: Player gold conserved at exactly 10")
	_assert(int(caravan.inventory[EconomyConfigScript.RES_CRYSTAL]) == 2, "TC-TR.11.3: Caravan crystal inventory conserved at 2")

# -----------------------------------------------------------------------------
# 12. TC-TR.12: Bid/Ask Spread Invariant Across All Risk Levels
# -----------------------------------------------------------------------------
func test_tc_tr_12_bid_ask_spread_and_no_arbitrage() -> void:
	print("\n--- TC-TR.12: Bid/Ask Spread Invariant ---")
	var caravan = TradeCaravanScript.generate_caravan(6666, 3, "rival_merchant", false)

	for test_risk in [-0.10, -0.05, 0.0, 0.10, 0.15, 0.25]:
		caravan.set_route_risk(test_risk)
		for res_id in [EconomyConfigScript.RES_FOOD, EconomyConfigScript.RES_WOOD, EconomyConfigScript.RES_STONE, EconomyConfigScript.RES_METAL, EconomyConfigScript.RES_TOOLS, EconomyConfigScript.RES_HERBS, EconomyConfigScript.RES_CRYSTAL]:
			var sell_p: int = caravan.get_effective_sell_price(res_id)
			var buy_p: int = caravan.get_effective_buy_price(res_id)
			_assert(sell_p >= 2, "TC-TR.12.1 (Risk %.2f, %s): Sell price >= 2 (%d)" % [test_risk, res_id, sell_p])
			_assert(buy_p >= 1, "TC-TR.12.2 (Risk %.2f, %s): Buy price >= 1 (%d)" % [test_risk, res_id, buy_p])
			_assert(sell_p > buy_p, "TC-TR.12.3 (Risk %.2f, %s): Spread strictly positive: sell (%d) > buy (%d)" % [test_risk, res_id, sell_p, buy_p])

# -----------------------------------------------------------------------------
# 13. TC-TR.13: Legacy Save Compatibility
# -----------------------------------------------------------------------------
func test_tc_tr_13_legacy_save_compatibility() -> void:
	print("\n--- TC-TR.13: Legacy Save Compatibility ---")
	# Legacy data completely lacking route_risk, has_explicit_route_risk, route_summary
	var legacy_data := {
		"caravan_id": "legacy_caravan_1",
		"name": "Đoàn Buôn Cũ",
		"origin_faction_id": "rival_merchant",
		"arrival_day": 3,
		"departure_day": 5,
		"is_active": true,
		"is_origin_at_war": false,
		"gold": 400,
		"inventory": {"wood": 25, "food": 30},
		"sell_prices": {"wood": 3, "food": 2},
		"buy_prices": {"wood": 2, "food": 1}
	}

	var caravan = TradeCaravanScript.deserialize(legacy_data)
	_assert(caravan != null, "TC-TR.13.1: Legacy caravan deserializes successfully")
	_assert(is_equal_approx(float(caravan.get("route_risk")), 0.0), "TC-TR.13.2: Legacy caravan defaults route_risk to 0.0")
	_assert(not bool(caravan.get("has_explicit_route_risk")), "TC-TR.13.3: has_explicit_route_risk defaults to false")
	_assert(caravan.get("route_summary").is_empty(), "TC-TR.13.4: route_summary defaults to empty dictionary")

# -----------------------------------------------------------------------------
# 14. TC-TR.14: Save/Load Roundtrip
# -----------------------------------------------------------------------------
func test_tc_tr_14_route_risk_save_load_roundtrip() -> void:
	print("\n--- TC-TR.14: Save/Load Roundtrip ---")
	var original = TradeCaravanScript.generate_caravan(5555, 3, "rival_merchant", true)
	original.set_route_risk(0.18, {
		"total_cells": 20,
		"unexplored_cells": 12,
		"unexplored_ratio": 0.60,
		"secured_cells": 4,
		"secured_ratio": 0.20,
		"hostile_cells": 2,
		"hostile_ratio": 0.10,
		"is_origin_at_war": true,
		"net_risk": 0.18
	})

	var serialized: Dictionary = original.serialize()
	_assert(serialized.has("route_risk"), "TC-TR.14.1: Serialized data contains 'route_risk'")
	_assert(is_equal_approx(float(serialized["route_risk"]), 0.18), "TC-TR.14.2: Serialized route_risk is 0.18")
	_assert(serialized.has("route_summary"), "TC-TR.14.3: Serialized data contains 'route_summary'")

	var restored = TradeCaravanScript.deserialize(serialized)
	_assert(restored != null, "TC-TR.14.4: Deserialization succeeds")
	_assert(is_equal_approx(float(restored.get("route_risk")), 0.18), "TC-TR.14.5: Restored route_risk matches 0.18")
	_assert(bool(restored.get("has_explicit_route_risk")), "TC-TR.14.6: Restored has_explicit_route_risk is true")
	_assert(int(restored.get("route_summary")["total_cells"]) == 20, "TC-TR.14.7: Restored route_summary total_cells matches 20")

# -----------------------------------------------------------------------------
# 15. TC-TR.15: WorldView Event-Driven Integration
# -----------------------------------------------------------------------------
func test_tc_tr_15_world_view_event_driven_integration() -> void:
	print("\n--- TC-TR.15: WorldView Event-Driven Integration ---")
	var wv = WorldViewScene.instantiate()
	root.add_child(wv)

	# Verify active caravan generation and automatic route risk assignment
	wv.active_caravan = TradeCaravanScript.generate_caravan(wv.world_seed, 3, "rival_merchant", false)
	wv.refresh_caravan_marker()

	_assert(wv.active_caravan != null, "TC-TR.15.1: Active caravan present")
	_assert(bool(wv.active_caravan.get("has_explicit_route_risk")), "TC-TR.15.2: Automatic route risk evaluated on caravan generation")
	var initial_risk: float = float(wv.active_caravan.get("route_risk"))
	print("  [INFO] Initial caravan route risk: %.3f" % initial_risk)

	# Add a player outpost directly on the route corridor to improve security
	var fsm = wv.get("field_siege_mgr")
	if fsm != null:
		var p_outpost = fsm.register_objective("trade_sec_outpost", Vector2i(40, 20), "player", 300.0, 3)
		wv.refresh_world_vision()
		var updated_risk: float = float(wv.active_caravan.get("route_risk"))
		print("  [INFO] Updated caravan route risk with player outpost: %.3f" % updated_risk)
		_assert(updated_risk <= initial_risk, "TC-TR.15.3: Securing route with player outpost decreases or maintains risk (%.3f <= %.3f)" % [updated_risk, initial_risk])

		# Unregister outpost and verify recalculation
		fsm.unregister_objective("trade_sec_outpost")
		wv.refresh_world_vision()
		var restored_risk: float = float(wv.active_caravan.get("route_risk"))
		_assert(is_equal_approx(restored_risk, initial_risk), "TC-TR.15.4: Unregistering outpost restores original risk level (%.3f == %.3f)" % [restored_risk, initial_risk])

	wv.queue_free()

# =============================================================================
# PACKAGE 3C.1 VALIDATION MATRIX: 18 TARGETED SCENARIOS
# =============================================================================

# Scenario 1: Horizontal corridor traversal
func test_sc_01_horizontal_corridor() -> void:
	print("\n--- Scenario 1: Horizontal Corridor Traversal ---")
	var cells := TradeRouteCalculatorScript.compute_route_cells(Vector2i(5, 10), Vector2i(9, 10))
	_assert(cells.size() == 5, "SC-01.1: Horizontal 5-cell span has size 5")
	_assert(cells[0] == Vector2i(5, 10) and cells[4] == Vector2i(9, 10), "SC-01.2: Endpoints match start and end")
	for i in range(cells.size()):
		_assert(cells[i].y == 10 and cells[i].x == 5 + i, "SC-01.3: Cell %d is strictly horizontal (x=%d, y=10)" % [i, 5 + i])

# Scenario 2: Vertical corridor traversal
func test_sc_02_vertical_corridor() -> void:
	print("\n--- Scenario 2: Vertical Corridor Traversal ---")
	var cells := TradeRouteCalculatorScript.compute_route_cells(Vector2i(10, 5), Vector2i(10, 9))
	_assert(cells.size() == 5, "SC-02.1: Vertical 5-cell span has size 5")
	_assert(cells[0] == Vector2i(10, 5) and cells[4] == Vector2i(10, 9), "SC-02.2: Endpoints match start and end")
	for i in range(cells.size()):
		_assert(cells[i].x == 10 and cells[i].y == 5 + i, "SC-02.3: Cell %d is strictly vertical (x=10, y=%d)" % [i, 5 + i])

# Scenario 3: Diagonal symmetric corridor traversal
func test_sc_03_diagonal_symmetric_corridor() -> void:
	print("\n--- Scenario 3: Diagonal Symmetric Corridor Traversal ---")
	var cells := TradeRouteCalculatorScript.compute_route_cells(Vector2i(10, 10), Vector2i(14, 14))
	_assert(cells.size() == 5, "SC-03.1: Symmetric diagonal (10,10)->(14,14) produces 5 cells")
	for i in range(cells.size()):
		_assert(cells[i] == Vector2i(10 + i, 10 + i), "SC-03.2: Step %d is symmetric diagonal (%d, %d)" % [i, 10 + i, 10 + i])

# Scenario 4: Non-square endpoint displacement
func test_sc_04_non_square_displacement() -> void:
	print("\n--- Scenario 4: Non-Square Endpoint Displacement ---")
	var cells := TradeRouteCalculatorScript.compute_route_cells(Vector2i(10, 10), Vector2i(15, 12))
	_assert(cells.size() == 6, "SC-04.1: Non-square span dx=5, dy=2 produces 6 cells (max(dx,dy)+1)")
	_assert(cells[0] == Vector2i(10, 10), "SC-04.2: First cell is start")
	_assert(cells[cells.size() - 1] == Vector2i(15, 12), "SC-04.3: Last cell is end")
	for i in range(1, cells.size()):
		_assert(cells[i].x >= cells[i-1].x and cells[i].y >= cells[i-1].y, "SC-04.4: Monotonic traversal progression at %d" % i)

# Scenario 5: Out-of-bounds endpoint coordinates
func test_sc_05_out_of_bounds_endpoints() -> void:
	print("\n--- Scenario 5: Out-of-Bounds Endpoint Coordinates ---")
	var oob_start := TradeRouteCalculatorScript.compute_route_cells(Vector2i(-1, -1), Vector2i(10, 10))
	_assert(oob_start.is_empty(), "SC-05.1: Negative start (-1, -1) returns empty array immediately")

	var oob_end := TradeRouteCalculatorScript.compute_route_cells(Vector2i(10, 10), Vector2i(64, 10))
	_assert(oob_end.is_empty(), "SC-05.2: Over-bounds end (64, 10) returns empty array immediately")

	var oob_both := TradeRouteCalculatorScript.compute_route_cells(Vector2i(-5, 70), Vector2i(80, -2))
	_assert(oob_both.is_empty(), "SC-05.3: Both endpoints out-of-bounds returns empty array")

	var eval_oob := TradeRouteCalculatorScript.evaluate_route_risk_between(Vector2i(-1, -1), Vector2i(10, 10))
	_assert(eval_oob["total_cells"] == 0, "SC-05.4: OOB route evaluates total_cells == 0")
	_assert(is_equal_approx(float(eval_oob["unexplored_ratio"]), 1.0), "SC-05.5: OOB route assigns unexplored_ratio == 1.0")
	_assert(is_equal_approx(float(eval_oob["net_risk"]), 0.15), "SC-05.6: OOB route applies conservative +15% net risk")
	_assert(eval_oob["reasons"].has("unexplored"), "SC-05.7: Reasons list contains 'unexplored'")

# Scenario 6: Same-cell corridor
func test_sc_06_same_cell_corridor() -> void:
	print("\n--- Scenario 6: Same-Cell Corridor ---")
	var same := TradeRouteCalculatorScript.compute_route_cells(Vector2i(25, 25), Vector2i(25, 25))
	_assert(same.size() == 1, "SC-06.1: Same cell start==end returns exactly 1 cell")
	_assert(same[0] == Vector2i(25, 25), "SC-06.2: Single cell is exactly (25, 25)")

	var same_oob := TradeRouteCalculatorScript.compute_route_cells(Vector2i(-1, -1), Vector2i(-1, -1))
	_assert(same_oob.is_empty(), "SC-06.3: Same cell out-of-bounds returns empty array")

# Scenario 7: Map boundary coordinates
func test_sc_07_map_boundary_coordinates() -> void:
	print("\n--- Scenario 7: Map Boundary Coordinates ---")
	var diag_full := TradeRouteCalculatorScript.compute_route_cells(Vector2i(0, 0), Vector2i(63, 63))
	_assert(diag_full.size() == 64, "SC-07.1: Full map diagonal (0,0)->(63,63) produces 64 cells")
	_assert(diag_full[0] == Vector2i(0, 0), "SC-07.2: First cell is (0, 0)")
	_assert(diag_full[63] == Vector2i(63, 63), "SC-07.3: Last cell is (63, 63)")

	var edge_h := TradeRouteCalculatorScript.compute_route_cells(Vector2i(0, 63), Vector2i(63, 63))
	_assert(edge_h.size() == 64, "SC-07.4: Edge horizontal y=63 produces 64 cells")
	_assert(edge_h[0] == Vector2i(0, 63) and edge_h[63] == Vector2i(63, 63), "SC-07.5: Edge endpoints correct")

# Scenario 8: Null/missing FOW fallback
func test_sc_08_null_missing_fow_fallback() -> void:
	print("\n--- Scenario 8: Null/Missing FOW Fallback ---")
	var route := [Vector2i(10, 10), Vector2i(11, 10), Vector2i(12, 10)]
	var eval_null_fow := TradeRouteCalculatorScript.evaluate_route_risk(route, null, null, null, false)
	_assert(int(eval_null_fow["unexplored_cells"]) == 3, "SC-08.1: Null FOW treats all 3 cells as unexplored")
	_assert(is_equal_approx(float(eval_null_fow["unexplored_ratio"]), 1.0), "SC-08.2: Null FOW unexplored_ratio is 1.0")
	_assert(is_equal_approx(float(eval_null_fow["net_risk"]), 0.15), "SC-08.3: Null FOW applies maximum +15% surcharge")
	_assert(eval_null_fow["reasons"].has("unexplored"), "SC-08.4: Null FOW reasons includes 'unexplored'")

# Scenario 9: Fully unexplored corridor
func test_sc_09_fully_unexplored_corridor() -> void:
	print("\n--- Scenario 9: Fully Unexplored Corridor ---")
	var fow = FogOfWarScript.new(64)
	var route := [Vector2i(20, 20), Vector2i(21, 20), Vector2i(22, 20), Vector2i(23, 20)]
	var eval := TradeRouteCalculatorScript.evaluate_route_risk(route, fow, null, null, false)
	_assert(int(eval["unexplored_cells"]) == 4, "SC-09.1: All 4 cells are unexplored")
	_assert(is_equal_approx(float(eval["unexplored_ratio"]), 1.0), "SC-09.2: Unexplored ratio is exactly 1.0")
	_assert(is_equal_approx(float(eval["net_risk"]), 0.15), "SC-09.3: Net risk is +0.15")

# Scenario 10: Single friendly outpost coverage
func test_sc_10_single_friendly_outpost() -> void:
	print("\n--- Scenario 10: Single Friendly Outpost Coverage ---")
	var mock_fsm = MockFSM.new()
	var outpost := SiegeObjectiveActorScript.new()
	outpost.current_cell = Vector2i(30, 30)
	outpost.owning_faction_id = "player"
	outpost.vision_radius = 6
	outpost.is_alive = true
	outpost.health = 200.0
	mock_fsm.objectives = [outpost]

	var fow = FogOfWarScript.new(64)
	var route := [Vector2i(30, 30), Vector2i(31, 30), Vector2i(32, 30)]
	for c in route: fow.set_state(c, FogOfWarScript.State.EXPLORED)

	var eval := TradeRouteCalculatorScript.evaluate_route_risk(route, fow, mock_fsm, null, false)
	_assert(int(eval["secured_cells"]) == 3, "SC-10.1: All 3 cells secured by player outpost")
	_assert(is_equal_approx(float(eval["secured_ratio"]), 1.0), "SC-10.2: 100% secured ratio")
	_assert(is_equal_approx(float(eval["net_risk"]), -0.10), "SC-10.3: Applies full -10% discount (-0.10)")
	_assert(eval["reasons"].has("secured"), "SC-10.4: Reasons includes 'secured'")
	outpost.free()

# Scenario 11: Overlapping friendly outposts (no double-counting)
func test_sc_11_overlapping_friendly_outposts() -> void:
	print("\n--- Scenario 11: Overlapping Friendly Outposts ---")
	var mock_fsm = MockFSM.new()
	var op1 := SiegeObjectiveActorScript.new()
	op1.current_cell = Vector2i(30, 30)
	op1.owning_faction_id = "player"
	op1.vision_radius = 6
	op1.is_alive = true
	op1.health = 200.0

	var op2 := SiegeObjectiveActorScript.new()
	op2.current_cell = Vector2i(31, 30)
	op2.owning_faction_id = "player"
	op2.vision_radius = 6
	op2.is_alive = true
	op2.health = 200.0
	mock_fsm.objectives = [op1, op2]

	var fow = FogOfWarScript.new(64)
	var route := [Vector2i(30, 30), Vector2i(31, 30)]
	for c in route: fow.set_state(c, FogOfWarScript.State.EXPLORED)

	var eval := TradeRouteCalculatorScript.evaluate_route_risk(route, fow, mock_fsm, null, false)
	_assert(int(eval["secured_cells"]) == 2, "SC-11.1: 2 corridor cells secured once each (no double count)")
	_assert(is_equal_approx(float(eval["secured_ratio"]), 1.0), "SC-11.2: Secured ratio remains 1.0 (not 2.0)")
	_assert(is_equal_approx(float(eval["net_risk"]), -0.10), "SC-11.3: Net risk capped at -10% (no stacked -20%)")
	op1.free()
	op2.free()

# Scenario 12: Friendly watchtower and outpost overlap
func test_sc_12_friendly_watchtower_and_outpost_overlap() -> void:
	print("\n--- Scenario 12: Friendly Watchtower and Outpost Overlap ---")
	var mock_fsm = MockFSM.new()
	var op := SiegeObjectiveActorScript.new()
	op.current_cell = Vector2i(20, 20)
	op.owning_faction_id = "player"
	op.vision_radius = 6
	op.is_alive = true
	op.health = 200.0
	mock_fsm.objectives = [op]

	var mock_wd = WorldGenerator.WorldData.new()
	var blds: Array[Dictionary] = [
		{"type": "watchtower", "cell": Vector2i(21, 20), "state": "active"}
	]
	mock_wd.buildings = blds

	var fow = FogOfWarScript.new(64)
	var route := [Vector2i(20, 20)]
	fow.set_state(route[0], FogOfWarScript.State.EXPLORED)

	var eval := TradeRouteCalculatorScript.evaluate_route_risk(route, fow, mock_fsm, mock_wd, false)
	_assert(int(eval["secured_cells"]) == 1, "SC-12.1: Single cell covered by both outpost and watchtower counts exactly once")
	_assert(is_equal_approx(float(eval["secured_ratio"]), 1.0), "SC-12.2: Secured ratio is 1.0")
	_assert(is_equal_approx(float(eval["net_risk"]), -0.10), "SC-12.3: Discount is exactly -10%")
	op.free()

# Scenario 13: Overlapping hostile outposts (no double-counting)
func test_sc_13_overlapping_hostile_outposts() -> void:
	print("\n--- Scenario 13: Overlapping Hostile Outposts ---")
	var mock_fsm = MockFSM.new()
	var enemy1 := SiegeObjectiveActorScript.new()
	enemy1.current_cell = Vector2i(40, 40)
	enemy1.owning_faction_id = "rival_military"
	enemy1.vision_radius = 6
	enemy1.is_alive = true
	enemy1.health = 300.0

	var enemy2 := SiegeObjectiveActorScript.new()
	enemy2.current_cell = Vector2i(41, 40)
	enemy2.owning_faction_id = "rival_military"
	enemy2.vision_radius = 6
	enemy2.is_alive = true
	enemy2.health = 300.0
	mock_fsm.objectives = [enemy1, enemy2]

	var fow = FogOfWarScript.new(64)
	var route := [Vector2i(40, 40), Vector2i(41, 40)]
	for c in route: fow.set_state(c, FogOfWarScript.State.EXPLORED)

	var eval := TradeRouteCalculatorScript.evaluate_route_risk(route, fow, mock_fsm, null, false)
	_assert(int(eval["hostile_cells"]) == 2, "SC-13.1: 2 corridor cells counted once each for hostile presence")
	_assert(is_equal_approx(float(eval["hostile_ratio"]), 1.0), "SC-13.2: Hostile ratio is 1.0 (not 2.0)")
	_assert(is_equal_approx(float(eval["net_risk"]), 0.10), "SC-13.3: Hostile surcharge capped at +10% (no double +20%)")
	enemy1.free()
	enemy2.free()

# Scenario 14: Contested cell (covered by both, nets to 0, both reasons exposed)
func test_sc_14_contested_cell_cancels_and_exposes_both_reasons() -> void:
	print("\n--- Scenario 14: Contested Cell (Friendly + Hostile) ---")
	var mock_fsm = MockFSM.new()
	var friendly := SiegeObjectiveActorScript.new()
	friendly.current_cell = Vector2i(35, 35)
	friendly.owning_faction_id = "player"
	friendly.vision_radius = 6
	friendly.is_alive = true
	friendly.health = 300.0

	var enemy := SiegeObjectiveActorScript.new()
	enemy.current_cell = Vector2i(36, 35)
	enemy.owning_faction_id = "rival_military"
	enemy.vision_radius = 6
	enemy.is_alive = true
	enemy.health = 300.0
	mock_fsm.objectives = [friendly, enemy]

	var fow = FogOfWarScript.new(64)
	var route := [Vector2i(35, 35)]
	fow.set_state(route[0], FogOfWarScript.State.EXPLORED)

	var eval := TradeRouteCalculatorScript.evaluate_route_risk(route, fow, mock_fsm, null, false)
	_assert(int(eval["secured_cells"]) == 1, "SC-14.1: Cell is counted as secured")
	_assert(int(eval["hostile_cells"]) == 1, "SC-14.2: Cell is counted as hostile")
	_assert(is_equal_approx(float(eval["raw_risk"]), 0.0), "SC-14.3: Friendly and hostile effects cancel out to 0.0 raw risk")
	_assert(is_equal_approx(float(eval["net_risk"]), 0.0), "SC-14.4: Net risk is 0.0")
	_assert(eval["reasons"].has("secured"), "SC-14.5: Reasons preserves 'secured'")
	_assert(eval["reasons"].has("hostile_outpost"), "SC-14.6: Reasons preserves 'hostile_outpost'")
	friendly.free()
	enemy.free()

# Scenario 15: Destroyed/stale outpost reference safely rejected
func test_sc_15_destroyed_stale_outpost_safely_rejected() -> void:
	print("\n--- Scenario 15: Destroyed/Stale Outpost Safely Rejected ---")
	var mock_fsm = MockFSM.new()
	var dead_op := SiegeObjectiveActorScript.new()
	dead_op.current_cell = Vector2i(10, 10)
	dead_op.owning_faction_id = "player"
	dead_op.vision_radius = 6
	dead_op.is_alive = false
	dead_op.health = 0.0

	var zero_hp_op := SiegeObjectiveActorScript.new()
	zero_hp_op.current_cell = Vector2i(10, 10)
	zero_hp_op.owning_faction_id = "player"
	zero_hp_op.vision_radius = 6
	zero_hp_op.is_alive = true
	zero_hp_op.health = 0.0

	var oob_op := SiegeObjectiveActorScript.new()
	oob_op.current_cell = Vector2i(999, 999)
	oob_op.owning_faction_id = "player"
	oob_op.vision_radius = 6
	oob_op.is_alive = true
	oob_op.health = 100.0

	mock_fsm.objectives = [dead_op, zero_hp_op, oob_op, null]

	var fow = FogOfWarScript.new(64)
	var route := [Vector2i(10, 10)]
	fow.set_state(route[0], FogOfWarScript.State.EXPLORED)

	var eval := TradeRouteCalculatorScript.evaluate_route_risk(route, fow, mock_fsm, null, false)
	_assert(int(eval["secured_cells"]) == 0, "SC-15.1: Dead, zero-hp, and OOB outposts contribute 0 security")
	_assert(is_equal_approx(float(eval["net_risk"]), 0.0), "SC-15.2: Net risk remains neutral 0.0")
	dead_op.free()
	zero_hp_op.free()
	oob_op.free()

# Scenario 16: Origin faction wartime status
func test_sc_16_origin_faction_wartime_status() -> void:
	print("\n--- Scenario 16: Origin Faction Wartime Status ---")
	var fow = FogOfWarScript.new(64)
	var route := [Vector2i(10, 10), Vector2i(11, 10)]
	for c in route: fow.set_state(c, FogOfWarScript.State.EXPLORED)

	var eval_peace := TradeRouteCalculatorScript.evaluate_route_risk(route, fow, null, null, false)
	var eval_war := TradeRouteCalculatorScript.evaluate_route_risk(route, fow, null, null, true)
	_assert(is_equal_approx(float(eval_peace["net_risk"]), 0.0), "SC-16.1: Peaceful route net risk is 0.0")
	_assert(is_equal_approx(float(eval_war["net_risk"]), 0.10), "SC-16.2: Wartime route net risk is exactly +0.10 (+10%)")
	_assert(eval_war["reasons"].has("wartime"), "SC-16.3: Wartime reason present in reasons list")

# Scenario 17: Restless Bandits modifier
func test_sc_17_restless_bandits_modifier() -> void:
	print("\n--- Scenario 17: Restless Bandits Modifier ---")
	var fow = FogOfWarScript.new(64)
	var route := [Vector2i(10, 10), Vector2i(11, 10)]
	for c in route: fow.set_state(c, FogOfWarScript.State.EXPLORED)

	var eval_bandits := TradeRouteCalculatorScript.evaluate_route_risk(route, fow, null, null, false, ["restless_bandits"])
	_assert(is_equal_approx(float(eval_bandits["net_risk"]), 0.10), "SC-17.1: restless_bandits adds +0.10 (+10%) risk")
	_assert(eval_bandits["reasons"].has("restless_bandits"), "SC-17.2: Reasons contains 'restless_bandits'")

	var eval_null_mod := TradeRouteCalculatorScript.evaluate_route_risk(route, fow, null, null, false, null)
	_assert(is_equal_approx(float(eval_null_mod["net_risk"]), 0.0), "SC-17.3: Null modifier input handled safely as empty")

	var eval_invalid_mod := TradeRouteCalculatorScript.evaluate_route_risk(route, fow, null, null, false, 12345)
	_assert(is_equal_approx(float(eval_invalid_mod["net_risk"]), 0.0), "SC-17.4: Non-array modifier input handled safely as empty")

# Scenario 18: Final risk clamp at exact boundaries
func test_sc_18_final_risk_clamp_exact_boundaries() -> void:
	print("\n--- Scenario 18: Final Risk Clamp Exact Boundaries ---")
	var mock_fsm = MockFSM.new()
	var p_op := SiegeObjectiveActorScript.new()
	p_op.current_cell = Vector2i(10, 10)
	p_op.owning_faction_id = "player"
	p_op.vision_radius = 6
	p_op.is_alive = true
	p_op.health = 200.0
	mock_fsm.objectives = [p_op]

	var fow = FogOfWarScript.new(64)
	var route := [Vector2i(10, 10)]
	fow.set_state(route[0], FogOfWarScript.State.EXPLORED)

	var eval_min := TradeRouteCalculatorScript.evaluate_route_risk(route, fow, mock_fsm, null, false)
	_assert(is_equal_approx(float(eval_min["net_risk"]), -0.10), "SC-18.1: Minimum discount clamp at exactly -0.10 (-10%)")

	var hostile_op := SiegeObjectiveActorScript.new()
	hostile_op.current_cell = Vector2i(10, 10)
	hostile_op.owning_faction_id = "rival_military"
	hostile_op.vision_radius = 6
	hostile_op.is_alive = true
	hostile_op.health = 200.0
	mock_fsm.objectives = [hostile_op]

	var fow_unex = FogOfWarScript.new(64)
	var eval_max := TradeRouteCalculatorScript.evaluate_route_risk(route, fow_unex, mock_fsm, null, true, ["restless_bandits"])
	_assert(eval_max["raw_risk"] > 0.25, "SC-18.2: Raw risk exceeds maximum (observed: %.2f)" % float(eval_max["raw_risk"]))
	_assert(is_equal_approx(float(eval_max["net_risk"]), 0.25), "SC-18.3: Net risk strictly clamped to +0.25 (+25%)")

	var caravan = TradeCaravanScript.generate_caravan(9999, 5, "rival_merchant", false)
	for extreme_risk in [-0.10, 0.25]:
		caravan.set_route_risk(extreme_risk)
		for res_id in [EconomyConfigScript.RES_FOOD, EconomyConfigScript.RES_WOOD, EconomyConfigScript.RES_METAL, EconomyConfigScript.RES_TOOLS, EconomyConfigScript.RES_CRYSTAL]:
			var bp: Dictionary = caravan.get_price_breakdown(res_id)
			var buy_p: int = int(bp["final_buy_price"])
			var sell_p: int = int(bp["final_sell_price"])
			_assert(buy_p <= sell_p - 1, "SC-18.4 (Risk %.2f, %s): Anti-arbitrage hold: buy (%d) <= sell (%d) - 1" % [extreme_risk, res_id, buy_p, sell_p])

	p_op.free()
	hostile_op.free()
