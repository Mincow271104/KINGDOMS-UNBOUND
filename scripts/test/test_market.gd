extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — Package 2A: Market Infrastructure & Settlement Commerce Integration
## Covers TC-MKT-01 through TC-MKT-15 with strict fail-closed assertions:
## TC-MKT-01: Blueprint registration, footprint (3x3), cost (25W, 10S), hours (12.0), no workers/housing/storage
## TC-MKT-02: Placement validation (resource affordability, bounds, water, occupancy, success)
## TC-MKT-03: Construction builder capacity follows 3x3 standard (4 workers)
## TC-MKT-04: Construction progression, completion, and active-state transition
## TC-MKT-05: Construction cancellation 50% refund and occupancy cleanup
## TC-MKT-06: Active Market deterministic discovery via BuildingSystem
## TC-MKT-07: Market docking position adjacency, boundary, terrain, and occupancy legality
## TC-MKT-08: Town Hall fallback when no Market exists or Market is under construction
## TC-MKT-09: Blocked Market perimeter safely falls back to Town Hall
## TC-MKT-10: Demolition of Market during active caravan visit re-docks to Town Hall without corrupting caravan data
## TC-MKT-11: Multiple active Markets resolve deterministically regardless of array insertion order
## TC-MKT-12: Trade buy/sell transactions through TradeCaravan preserve stock, gold, price and capacity invariants
## TC-MKT-13: Backward compatibility: save game without Market loads cleanly
## TC-MKT-14: Save/load persistence of Market and active caravan; marker reconstruction without duplication
## TC-MKT-15: Re-entrancy idempotency: repeated refresh and departure do not leak or duplicate marker nodes
## Package 2H: Dynamic Market Pricing & Supply-Demand Economy:
## TC-MKT-16: Dynamic Pricing Neutral Baseline (multiplier == 1.0, exact match with base prices)
## TC-MKT-17: Kingdom Scarcity & Surplus Price Reaction (low stock increases price, high stock decreases price)
## TC-MKT-18: Caravan Scarcity & Surplus Price Reaction (low caravan stock increases price, high caravan stock decreases price)
## TC-MKT-19: Strict Multiplier Bounding [0.80, 1.20] under extreme local and caravan stock conditions
## TC-MKT-20: Bid/Ask Spread Invariant (caravan_sell_price >= caravan_buy_price + 1 and buy_price >= 1) across all resources
## TC-MKT-21: Price Breakdown API completeness and consistency with get_effective_sell_price and get_effective_buy_price
## TC-MKT-22: Quote and Transaction Parity (exact same unit price used for affordability check and balance execution)
## TC-MKT-23: Transaction Failure Atomicity & State Rollback (insufficient gold, stock, capacity full do not mutate state)
## TC-MKT-24: Post-Transaction Dynamic Quote Update (buying/selling changes stock and immediately refreshes subsequent quotes)
## TC-MKT-25: Wartime Surcharge and Diplomatic Opinion Combination (preserves Package 2E +15% and opinion discount/premium)
## TC-MKT-26: Legacy Save/Load Compatibility & Dynamic Recomputation (deserializing legacy data produces valid dynamic prices)

const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")
const TradeCaravanScript = preload("res://scripts/trade/trade_caravan.gd")
const CaravanMarkerScript = preload("res://scripts/trade/caravan_marker.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const IsoMathScript = preload("res://scripts/utils/iso_math.gd")

const TEST_SAVE_PATH: String = "user://test_market_save.json"

class MockTestResourceManager extends Node:
	var stock: Dictionary = {}
	var capacities: Dictionary = {}
	var reserve_calls: int = 0
	var commit_calls: int = 0

	func _init(initial: Dictionary = {}) -> void:
		for r in EconomyConfig.ALL_RESOURCES:
			stock[r] = initial.get(r, 0)
			capacities[r] = 500
		capacities[EconomyConfig.RES_GOLD] = 999999

	func get_available_stock(res_id: String) -> int:
		return stock.get(res_id, 0)

	func get_total_stock(res_id: String) -> int:
		return stock.get(res_id, 0)

	func get_storage_capacity(res_id: String) -> int:
		return capacities.get(res_id, 500)

	func get_capacity(res_id: String) -> int:
		return capacities.get(res_id, 500)

	func can_afford(cost: Dictionary) -> bool:
		for r in cost:
			if get_available_stock(r) < cost[r]:
				return false
		return true

	func reserve_cost(cost: Dictionary) -> bool:
		reserve_calls += 1
		return can_afford(cost)

	func commit_cost(cost: Dictionary) -> void:
		commit_calls += 1
		for r in cost:
			stock[r] = get_available_stock(r) - cost[r]

	func consume_resource(res_id: String, amount: int) -> bool:
		if get_available_stock(res_id) >= amount:
			stock[res_id] = get_available_stock(res_id) - amount
			return true
		return false

	func add_resource(res_id: String, amount: int) -> int:
		var cur = get_available_stock(res_id)
		var max_cap = capacities.get(res_id, 500)
		var added = mini(amount, max_cap - cur)
		stock[res_id] = cur + added
		return added

	func add_resources_atomic(resources: Dictionary) -> Dictionary:
		for r in resources:
			var amt: int = int(resources[r])
			var cur: int = get_available_stock(r)
			var max_cap: int = capacities.get(r, 500)
			if cur + amt > max_cap:
				return {"success": false, "reason": "Dung lượng kho chứa không đủ", "credited": {}}
		var credited: Dictionary = {}
		for r in resources:
			var amt: int = int(resources[r])
			var cur: int = get_available_stock(r)
			stock[r] = cur + amt
			credited[r] = amt
		return {"success": true, "credited": credited}

	func has_resource(res_id: String, amount: int) -> bool:
		return get_available_stock(res_id) >= amount

var frame_count: int = 0
var world_instance: Node = null
var all_passed: bool = true

func _init() -> void:
	print("\n========================================================")
	print("  STARTING PACKAGE 2A MARKET & CARAVAN TEST SUITE")
	print("========================================================\n")

	# Secure save isolation
	SaveManagerScript.set_test_default_save_path(TEST_SAVE_PATH)

	var world_scene = load("res://scenes/world/world_view.tscn")
	world_instance = world_scene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1

	if frame_count == 3:
		var pass_tc1 := _test_tc_mkt_01_blueprint()
		var pass_tc2 := _test_tc_mkt_02_placement()
		var pass_tc3 := _test_tc_mkt_03_builder_capacity()
		var pass_tc4 := _test_tc_mkt_04_construction_and_completion()
		var pass_tc5 := _test_tc_mkt_05_cancellation_refund()
		var pass_tc6 := _test_tc_mkt_06_deterministic_market_discovery()
		var pass_tc7 := _test_tc_mkt_07_docking_perimeter_legality()
		var pass_tc8 := _test_tc_mkt_08_townhall_fallback()
		var pass_tc9 := _test_tc_mkt_09_blocked_perimeter_fallback()
		var pass_tc10 := _test_tc_mkt_10_demolition_during_caravan_visit()
		var pass_tc11 := _test_tc_mkt_11_multiple_markets_deterministic()
		var pass_tc12 := _test_tc_mkt_12_trade_transactions_invariants()
		var pass_tc13 := _test_tc_mkt_13_backward_compatible_save_load()
		var pass_tc14 := _test_tc_mkt_14_save_load_persistence_and_marker()
		var pass_tc15 := _test_tc_mkt_15_marker_idempotency_and_departure()
		var pass_tc16 := _test_tc_mkt_16_neutral_baseline()
		var pass_tc17 := _test_tc_mkt_17_kingdom_scarcity_and_surplus()
		var pass_tc18 := _test_tc_mkt_18_caravan_scarcity_and_surplus()
		var pass_tc19 := _test_tc_mkt_19_strict_multiplier_bounds()
		var pass_tc20 := _test_tc_mkt_20_spread_and_positive_prices()
		var pass_tc21 := _test_tc_mkt_21_price_breakdown_consistency()
		var pass_tc22 := _test_tc_mkt_22_quote_and_transaction_parity()
		var pass_tc23 := _test_tc_mkt_23_transaction_failure_rollback()
		var pass_tc24 := _test_tc_mkt_24_post_trade_quote_update()
		var pass_tc25 := _test_tc_mkt_25_wartime_and_diplomacy_combination()
		var pass_tc26 := _test_tc_mkt_26_legacy_save_compatibility()

		all_passed = (
			pass_tc1 and pass_tc2 and pass_tc3 and pass_tc4 and
			pass_tc5 and pass_tc6 and pass_tc7 and pass_tc8 and
			pass_tc9 and pass_tc10 and pass_tc11 and pass_tc12 and
			pass_tc13 and pass_tc14 and pass_tc15 and pass_tc16 and
			pass_tc17 and pass_tc18 and pass_tc19 and pass_tc20 and
			pass_tc21 and pass_tc22 and pass_tc23 and pass_tc24 and
			pass_tc25 and pass_tc26
		)

		_cleanup_test_artifacts()

		print("\n--------------------------------------------------------")
		if all_passed:
			print("  ALL 26 MARKET & DYNAMIC PRICING TESTS PASSED! (Exit Code 0)")
			print("--------------------------------------------------------\n")
			quit(0)
			return true
		else:
			print("  MARKET & DYNAMIC PRICING TESTS FAILED! (Exit Code 1)")
			print("--------------------------------------------------------\n")
			quit(1)
			return false

	return false

func _cleanup_test_artifacts() -> void:
	SaveManagerScript.set_test_default_save_path("")
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(TEST_SAVE_PATH)
	if FileAccess.file_exists(TEST_SAVE_PATH + ".bak"):
		DirAccess.remove_absolute(TEST_SAVE_PATH + ".bak")

func _test_tc_mkt_01_blueprint() -> bool:
	print("[TC-MKT-01] Testing Market blueprint configuration integrity...")
	var bp = EconomyConfigScript.BLUEPRINTS.get("market", {})
	if bp.is_empty():
		printerr("FAIL: 'market' not registered in EconomyConfig.BLUEPRINTS")
		return false
	if bp.get("id") != "market":
		printerr("FAIL: Blueprint id must be 'market', got: %s" % bp.get("id"))
		return false
	if bp.get("name_vi") != "Chợ":
		printerr("FAIL: Blueprint name_vi must be 'Chợ', got: %s" % bp.get("name_vi"))
		return false
	if bp.get("footprint") != Vector2i(3, 3):
		printerr("FAIL: Blueprint footprint must be Vector2i(3, 3), got: %s" % bp.get("footprint"))
		return false
	var expected_cost = {EconomyConfigScript.RES_WOOD: 25, EconomyConfigScript.RES_STONE: 10}
	if bp.get("cost") != expected_cost:
		printerr("FAIL: Blueprint cost must be %s, got: %s" % [expected_cost, bp.get("cost")])
		return false
	if float(bp.get("construction_hours", 0.0)) != 12.0:
		printerr("FAIL: Blueprint construction_hours must be 12.0, got: %s" % bp.get("construction_hours"))
		return false
	if int(bp.get("housing_capacity", 0)) != 0:
		printerr("FAIL: Market must not provide housing capacity")
		return false
	if not bp.get("storage_bonus", {}).is_empty():
		printerr("FAIL: Market must not have storage bonus")
		return false
	if int(bp.get("max_workers", 0)) != 0:
		printerr("FAIL: Market must have 0 permanent workers")
		return false
	if bp.get("job_type", "") != "":
		printerr("FAIL: Market job_type must be empty string")
		return false

	print("  PASS: TC-MKT-01 Blueprint configuration is valid and strictly GDD-compliant")
	return true

func _test_tc_mkt_02_placement() -> bool:
	print("[TC-MKT-02] Testing Market placement rules and validation...")
	var wd = WorldGeneratorScript.generate(5555)
	var rich_rm = MockTestResourceManager.new({EconomyConfigScript.RES_WOOD: 100, EconomyConfigScript.RES_STONE: 100})
	var poor_rm = MockTestResourceManager.new({EconomyConfigScript.RES_WOOD: 5, EconomyConfigScript.RES_STONE: 0})

	# 1. Unaffordable rejection
	var check_poor = BuildingSystemScript.can_place_building("market", Vector2i(20, 20), wd, poor_rm)
	if check_poor.get("valid", true):
		printerr("FAIL: can_place_building should reject when unaffordable")
		return false

	# 2. Out of bounds
	var check_oob = BuildingSystemScript.can_place_building("market", Vector2i(63, 63), wd, rich_rm)
	if check_oob.get("valid", true):
		printerr("FAIL: can_place_building should reject when 3x3 footprint exceeds map bounds")
		return false

	# 3. Water terrain rejection
	var water_cell := Vector2i(-1, -1)
	for x in range(64):
		for y in range(64):
			if wd.terrain[x][y] == WorldGeneratorScript.TerrainType.WATER:
				water_cell = Vector2i(x, y)
				break
		if water_cell != Vector2i(-1, -1):
			break
	if water_cell != Vector2i(-1, -1):
		var check_water = BuildingSystemScript.can_place_building("market", water_cell, wd, rich_rm)
		if check_water.get("valid", true):
			printerr("FAIL: can_place_building should reject on water terrain")
			return false

	# 4. Valid placement & cost deduction
	var test_origin := Vector2i(15, 15)
	for ox in range(3):
		for oy in range(3):
			wd.occupancy[test_origin.x + ox][test_origin.y + oy] = false
			wd.terrain[test_origin.x + ox][test_origin.y + oy] = WorldGeneratorScript.TerrainType.GRASS

	var place_res = BuildingSystemScript.place_building("market", test_origin, wd, rich_rm, "under_construction")
	if not place_res.get("success", false):
		printerr("FAIL: place_building failed unexpectedly: %s" % place_res.get("reason"))
		return false

	if rich_rm.get_available_stock(EconomyConfigScript.RES_WOOD) != 75:
		printerr("FAIL: Wood cost was not deducted correctly")
		return false
	if rich_rm.get_available_stock(EconomyConfigScript.RES_STONE) != 90:
		printerr("FAIL: Stone cost was not deducted correctly")
		return false

	# 5. Occupied collision rejection
	var check_occupied = BuildingSystemScript.can_place_building("market", test_origin, wd, rich_rm)
	if check_occupied.get("valid", true):
		printerr("FAIL: can_place_building should reject on already occupied cells")
		return false

	print("  PASS: TC-MKT-02 Placement validation, bounds, water, and costs verified")
	return true

func _test_tc_mkt_03_builder_capacity() -> bool:
	print("[TC-MKT-03] Testing Market construction worker capacity...")
	var cap = BuildingSystemScript.get_construction_worker_capacity("market")
	if cap != 4:
		printerr("FAIL: Market (3x3) builder capacity should naturally be 4, got: %d" % cap)
		return false
	print("  PASS: TC-MKT-03 Builder capacity correctly returns 4 for 3x3 footprint")
	return true

func _test_tc_mkt_04_construction_and_completion() -> bool:
	print("[TC-MKT-04] Testing construction progress and completion lifecycle...")
	var wd = WorldGeneratorScript.generate(7777)
	var rm = MockTestResourceManager.new({EconomyConfigScript.RES_WOOD: 100, EconomyConfigScript.RES_STONE: 100})
	var cell := Vector2i(20, 20)
	for ox in range(3):
		for oy in range(3):
			wd.occupancy[cell.x + ox][cell.y + oy] = false
			wd.terrain[cell.x + ox][cell.y + oy] = WorldGeneratorScript.TerrainType.GRASS

	var place_res = BuildingSystemScript.place_building("market", cell, wd, rm, "under_construction")
	var b_data = place_res.get("building", {})

	# Premature completion check
	if BuildingSystemScript.complete_building(b_data, wd, rm):
		printerr("FAIL: complete_building must not succeed at 0.0h progress")
		return false
	if BuildingSystemScript.is_market_active(wd):
		printerr("FAIL: is_market_active must be false while under construction")
		return false

	# Partial advance
	BuildingSystemScript.advance_construction(b_data, 6.0, wd)
	if BuildingSystemScript.complete_building(b_data, wd, rm):
		printerr("FAIL: complete_building must not succeed at 6.0h / 12.0h progress")
		return false

	# Complete advance
	var adv_res = BuildingSystemScript.advance_construction(b_data, 6.0, wd)
	if not adv_res.get("completed", false):
		printerr("FAIL: advance_construction should report completed after reaching 12.0h")
		return false

	if not BuildingSystemScript.complete_building(b_data, wd, rm):
		printerr("FAIL: complete_building should succeed when progress reached 12.0h")
		return false

	if b_data.get("state") != "active":
		printerr("FAIL: Building state should now be 'active'")
		return false
	if not BuildingSystemScript.is_market_active(wd):
		printerr("FAIL: is_market_active must be true after completion")
		return false

	print("  PASS: TC-MKT-04 Construction progression and active-state transition verified")
	return true

func _test_tc_mkt_05_cancellation_refund() -> bool:
	print("[TC-MKT-05] Testing cancellation 50% refund and occupancy cleanup...")
	var wd = WorldGeneratorScript.generate(8888)
	var rm = MockTestResourceManager.new({EconomyConfigScript.RES_WOOD: 50, EconomyConfigScript.RES_STONE: 50})
	var cell := Vector2i(25, 25)
	for ox in range(3):
		for oy in range(3):
			wd.occupancy[cell.x + ox][cell.y + oy] = false
			wd.terrain[cell.x + ox][cell.y + oy] = WorldGeneratorScript.TerrainType.GRASS

	var place_res = BuildingSystemScript.place_building("market", cell, wd, rm, "under_construction")
	var b_data = place_res.get("building", {})

	# Wood was 50 - 25 = 25; Stone was 50 - 10 = 40
	var cancel_res = BuildingSystemScript.cancel_construction(b_data, wd, rm)
	if not cancel_res.get("success", false):
		printerr("FAIL: cancel_construction failed: %s" % cancel_res.get("reason"))
		return false

	# Refund: int(25 * 0.5) = 12 Wood, int(10 * 0.5) = 5 Stone
	if rm.get_available_stock(EconomyConfigScript.RES_WOOD) != 37: # 25 + 12
		printerr("FAIL: Wood 50%% refund expected 37, got %d" % rm.get_available_stock(EconomyConfigScript.RES_WOOD))
		return false
	if rm.get_available_stock(EconomyConfigScript.RES_STONE) != 45: # 40 + 5
		printerr("FAIL: Stone 50%% refund expected 45, got %d" % rm.get_available_stock(EconomyConfigScript.RES_STONE))
		return false

	for ox in range(3):
		for oy in range(3):
			if wd.occupancy[cell.x + ox][cell.y + oy]:
				printerr("FAIL: Occupancy was not cleared after cancellation at %s" % (cell + Vector2i(ox, oy)))
				return false

	print("  PASS: TC-MKT-05 Cancellation 50% refund and occupancy cleanup verified")
	return true

func _test_tc_mkt_06_deterministic_market_discovery() -> bool:
	print("[TC-MKT-06] Testing deterministic active Market selection...")
	var wd = WorldGeneratorScript.generate(1234)
	wd.buildings.clear()

	var m1 = {"id": "bld_market_30_30", "type": "market", "cell": Vector2i(30, 30), "size": Vector2i(3, 3), "state": "active"}
	var m2 = {"id": "bld_market_10_10", "type": "market", "cell": Vector2i(10, 10), "size": Vector2i(3, 3), "state": "active"}
	var m3 = {"id": "bld_market_20_20", "type": "market", "cell": Vector2i(20, 20), "size": Vector2i(3, 3), "state": "under_construction"}

	# Add in non-sorted order
	wd.buildings.append(m1)
	wd.buildings.append(m2)
	wd.buildings.append(m3)

	var selected = BuildingSystemScript.get_active_market(wd)
	if selected.is_empty():
		printerr("FAIL: get_active_market returned empty dictionary")
		return false
	if selected.get("id") != "bld_market_10_10":
		printerr("FAIL: Deterministic selection should pick lowest coordinate (10, 10), got: %s" % selected.get("id"))
		return false

	print("  PASS: TC-MKT-06 Active Market is selected deterministically")
	return true

func _test_tc_mkt_07_docking_perimeter_legality() -> bool:
	print("[TC-MKT-07] Testing Market docking perimeter cell legality...")
	var wd = WorldGeneratorScript.generate(2222)
	wd.buildings.clear()

	var m_origin := Vector2i(25, 25)
	for ox in range(-2, 5):
		for oy in range(-2, 5):
			wd.occupancy[m_origin.x + ox][m_origin.y + oy] = false
			wd.terrain[m_origin.x + ox][m_origin.y + oy] = WorldGeneratorScript.TerrainType.GRASS

	for ox in range(3):
		for oy in range(3):
			wd.occupancy[m_origin.x + ox][m_origin.y + oy] = true

	var m_bld := {"id": "bld_market_25_25", "type": "market", "cell": m_origin, "size": Vector2i(3, 3), "state": "active"}
	wd.buildings.append(m_bld)

	var dock_info := BuildingSystemScript.find_caravan_docking_cell(wd)
	if not dock_info.get("is_market", false):
		printerr("FAIL: Docking should identify Market as active docking location")
		return false

	var cell: Vector2i = dock_info.get("cell", Vector2i(-1, -1))
	if not IsoMathScript.is_in_bounds(cell):
		printerr("FAIL: Docking cell out of bounds: %s" % cell)
		return false
	if wd.occupancy[cell.x][cell.y]:
		printerr("FAIL: Docking cell is occupied: %s" % cell)
		return false
	if wd.terrain[cell.x][cell.y] == WorldGeneratorScript.TerrainType.WATER:
		printerr("FAIL: Docking cell is on water: %s" % cell)
		return false

	# Must be adjacent to 3x3 footprint
	var dist_x: int = maxi(0, maxi(m_origin.x - cell.x, cell.x - (m_origin.x + 2)))
	var dist_y: int = maxi(0, maxi(m_origin.y - cell.y, cell.y - (m_origin.y + 2)))
	if dist_x > 1 or dist_y > 1 or (dist_x == 0 and dist_y == 0):
		printerr("FAIL: Docking cell %s is not an adjacent perimeter cell to Market %s" % [cell, m_origin])
		return false

	print("  PASS: TC-MKT-07 Docking cell is an adjacent, legal, unoccupied perimeter cell")
	return true

func _test_tc_mkt_08_townhall_fallback() -> bool:
	print("[TC-MKT-08] Testing Town Hall fallback when no Market exists or under construction...")
	var wd = WorldGeneratorScript.generate(3333)
	wd.buildings.clear()

	var th_origin := Vector2i(31, 30)
	for ox in range(3):
		for oy in range(3):
			wd.occupancy[th_origin.x + ox][th_origin.y + oy] = true
	var th_bld := {"id": "bld_townhall_31_30", "type": "townhall", "cell": th_origin, "size": Vector2i(3, 3), "state": "active"}
	wd.buildings.append(th_bld)

	# Case A: No market
	var dock_a = BuildingSystemScript.find_caravan_docking_cell(wd)
	if dock_a.get("is_market", true):
		printerr("FAIL: is_market must be false when no market exists")
		return false
	var cell_a: Vector2i = dock_a.get("cell", Vector2i(-1, -1))
	if cell_a == Vector2i(-1, -1) or not IsoMathScript.is_in_bounds(cell_a):
		printerr("FAIL: Fallback to Town Hall produced invalid cell: %s" % cell_a)
		return false

	# Case B: Market under construction
	var m_constr := {"id": "bld_market_15_15", "type": "market", "cell": Vector2i(15, 15), "size": Vector2i(3, 3), "state": "under_construction"}
	wd.buildings.append(m_constr)
	var dock_b = BuildingSystemScript.find_caravan_docking_cell(wd)
	if dock_b.get("is_market", true):
		printerr("FAIL: is_market must be false when market is under construction")
		return false
	if dock_b.get("cell") != cell_a:
		printerr("FAIL: Fallback position changed unexpectedly while Market is under construction")
		return false

	print("  PASS: TC-MKT-08 Fallback to Town Hall operational without active Market")
	return true

func _test_tc_mkt_09_blocked_perimeter_fallback() -> bool:
	print("[TC-MKT-09] Testing fallback when Market perimeter is fully blocked...")
	var wd = WorldGeneratorScript.generate(4444)
	wd.buildings.clear()

	var th_origin := Vector2i(31, 30)
	for ox in range(3):
		for oy in range(3):
			wd.occupancy[th_origin.x + ox][th_origin.y + oy] = true
	wd.buildings.append({"id": "bld_townhall", "type": "townhall", "cell": th_origin, "size": Vector2i(3, 3), "state": "active"})

	var m_origin := Vector2i(15, 15)
	for ox in range(3):
		for oy in range(3):
			wd.occupancy[m_origin.x + ox][m_origin.y + oy] = true
	wd.buildings.append({"id": "bld_market", "type": "market", "cell": m_origin, "size": Vector2i(3, 3), "state": "active"})

	# Block entire perimeter around Market
	for dx in range(-1, 4):
		for dy in range(-1, 4):
			var c := m_origin + Vector2i(dx, dy)
			if IsoMathScript.is_in_bounds(c):
				wd.occupancy[c.x][c.y] = true

	var dock = BuildingSystemScript.find_caravan_docking_cell(wd)
	if dock.get("is_market", true):
		printerr("FAIL: Market perimeter is blocked; should have fallen back to Town Hall")
		return false
	var cell: Vector2i = dock.get("cell", Vector2i(-1, -1))
	if cell == Vector2i(-1, -1):
		printerr("FAIL: Blocked Market failed to find Town Hall fallback cell")
		return false

	print("  PASS: TC-MKT-09 Blocked Market perimeter cleanly routes to Town Hall")
	return true

func _test_tc_mkt_10_demolition_during_caravan_visit() -> bool:
	print("[TC-MKT-10] Testing Market demolition while caravan is visiting...")
	var wv = world_instance
	if wv == null:
		printerr("FAIL: world_instance is null")
		return false

	# Ensure townhall exists
	var th_found := false
	for b in wv.world_data.buildings:
		if b.get("type") == "townhall":
			th_found = true
			break
	if not th_found:
		wv.world_data.buildings.append({"id": "bld_townhall_31_30", "type": "townhall", "cell": Vector2i(31, 30), "size": Vector2i(3, 3), "state": "active"})

	# Place active market
	var m_origin := Vector2i(20, 20)
	for ox in range(3):
		for oy in range(3):
			wv.world_data.occupancy[m_origin.x + ox][m_origin.y + oy] = true
	var mkt_dict := {"id": "bld_market_demo_test", "type": "market", "cell": m_origin, "size": Vector2i(3, 3), "state": "active"}
	wv.world_data.buildings.append(mkt_dict)

	# Setup active caravan
	var c = TradeCaravanScript.generate_caravan(1234, 3, "rival_merchant")
	wv.set("active_caravan", c)
	wv.refresh_caravan_marker()

	var marker: Node2D = wv.get_caravan_marker()
	if marker == null or not marker.visible:
		printerr("FAIL: Caravan marker was not instantiated for active caravan")
		return false
	if not wv.is_caravan_docked_at_market():
		printerr("FAIL: Caravan should be docked at Market")
		return false

	var initial_gold: int = c.gold
	var initial_wood: int = c.inventory.get(EconomyConfigScript.RES_WOOD, 0)

	# Demolish Market
	wv.demolish_building_project("bld_market_demo_test")

	# Verify Market destroyed
	if BuildingSystemScript.is_market_active(wv.world_data, "bld_market_demo_test"):
		printerr("FAIL: Market still active after demolition")
		return false

	# Caravan data must be 100% preserved
	if c.gold != initial_gold or c.inventory.get(EconomyConfigScript.RES_WOOD, 0) != initial_wood:
		printerr("FAIL: Caravan gold or stock was modified by building demolition")
		return false

	# Marker must now be re-docked at Town Hall
	if wv.is_caravan_docked_at_market():
		printerr("FAIL: Caravan marker should no longer be docked at Market after demolition")
		return false
	if not marker.visible:
		printerr("FAIL: Caravan marker should remain visible at Town Hall fallback")
		return false

	print("  PASS: TC-MKT-10 Demolition during caravan visit gracefully re-routes without data loss")
	return true

func _test_tc_mkt_11_multiple_markets_deterministic() -> bool:
	print("[TC-MKT-11] Testing multiple Markets deterministic resolution...")
	var wd = WorldGeneratorScript.generate(9999)
	wd.buildings.clear()

	var m_a := {"id": "bld_market_25_25", "type": "market", "cell": Vector2i(25, 25), "size": Vector2i(3, 3), "state": "active"}
	var m_b := {"id": "bld_market_10_40", "type": "market", "cell": Vector2i(10, 40), "size": Vector2i(3, 3), "state": "active"}
	var m_c := {"id": "bld_market_05_05", "type": "market", "cell": Vector2i(5, 5), "size": Vector2i(3, 3), "state": "active"}

	# Permutation 1
	wd.buildings.clear()
	wd.buildings.append_array([m_a, m_b, m_c])
	var sel_1 = BuildingSystemScript.get_active_market(wd)

	# Permutation 2
	wd.buildings.clear()
	wd.buildings.append_array([m_c, m_a, m_b])
	var sel_2 = BuildingSystemScript.get_active_market(wd)

	# Permutation 3
	wd.buildings.clear()
	wd.buildings.append_array([m_b, m_c, m_a])
	var sel_3 = BuildingSystemScript.get_active_market(wd)

	if sel_1.get("id") != sel_2.get("id") or sel_2.get("id") != sel_3.get("id"):
		printerr("FAIL: Multiple markets selected inconsistently across array orders: %s vs %s vs %s" % [sel_1.get("id"), sel_2.get("id"), sel_3.get("id")])
		return false

	if sel_1.get("id") != "bld_market_05_05":
		printerr("FAIL: Expected lowest coordinate market (5, 5), got: %s" % sel_1.get("id"))
		return false

	print("  PASS: TC-MKT-11 Multiple active Markets resolve deterministically across all permutations")
	return true

func _test_tc_mkt_12_trade_transactions_invariants() -> bool:
	print("[TC-MKT-12] Testing trade transactions atomic invariants...")
	var c = TradeCaravanScript.generate_caravan(54321, 5, "rival_merchant")
	var rm = MockTestResourceManager.new({
		EconomyConfigScript.RES_GOLD: 100,
		EconomyConfigScript.RES_WOOD: 50
	})

	var initial_c_wood = c.inventory.get(EconomyConfigScript.RES_WOOD, 0)
	var initial_c_gold = c.gold
	var unit_sell_price = c.get_effective_sell_price(EconomyConfigScript.RES_WOOD, 0.0)

	# Player buys 10 Wood
	var buy_res = c.buy_from_caravan(EconomyConfigScript.RES_WOOD, 10, rm, 0.0)
	if not buy_res.get("success", false):
		printerr("FAIL: buy_from_caravan failed: %s" % buy_res.get("reason"))
		return false

	if c.inventory[EconomyConfigScript.RES_WOOD] != initial_c_wood - 10:
		printerr("FAIL: Caravan inventory did not decrease by 10")
		return false
	if rm.get_available_stock(EconomyConfigScript.RES_WOOD) != 60:
		printerr("FAIL: Player wood did not increase to 60")
		return false
	if rm.get_available_stock(EconomyConfigScript.RES_GOLD) != 100 - (unit_sell_price * 10):
		printerr("FAIL: Player gold not deducted correctly")
		return false
	if c.gold != initial_c_gold + (unit_sell_price * 10):
		printerr("FAIL: Caravan gold not credited correctly")
		return false

	# Player sells 10 Wood back
	var pre_sell_c_gold = c.gold
	var unit_buy_price = c.get_effective_buy_price(EconomyConfigScript.RES_WOOD, 0.0)
	var sell_res = c.sell_to_caravan(EconomyConfigScript.RES_WOOD, 10, rm, 0.0)
	if not sell_res.get("success", false):
		printerr("FAIL: sell_to_caravan failed: %s" % sell_res.get("reason"))
		return false

	if c.gold != pre_sell_c_gold - (unit_buy_price * 10):
		printerr("FAIL: Caravan gold not deducted correctly on sell")
		return false
	if rm.get_available_stock(EconomyConfigScript.RES_WOOD) != 50:
		printerr("FAIL: Player wood not deducted correctly on sell")
		return false

	print("  PASS: TC-MKT-12 Buy/sell transactions preserve stock, gold, price and capacity invariants")
	return true

func _test_tc_mkt_13_backward_compatible_save_load() -> bool:
	print("[TC-MKT-13] Testing backward compatibility with saves containing no Market...")
	var wv = world_instance
	# Remove any markets
	var filtered_blds: Array[Dictionary] = []
	for b in wv.world_data.buildings:
		if b.get("type") != "market":
			filtered_blds.append(b)
	wv.world_data.buildings.clear()
	wv.world_data.buildings.append_array(filtered_blds)

	var save_res = SaveManagerScript.save_to_file(wv, TEST_SAVE_PATH)
	if not save_res.get("success", false):
		printerr("FAIL: SaveManager.save_to_file failed: %s" % save_res.get("error"))
		return false

	var load_res = SaveManagerScript.load_from_file(TEST_SAVE_PATH)
	if not load_res.get("success", false):
		printerr("FAIL: SaveManager.load_from_file failed on legacy save: %s" % load_res.get("error"))
		return false

	var apply_res = SaveManagerScript.apply_loaded_state_to_world(wv, load_res["data"])
	if not apply_res.get("success", false):
		printerr("FAIL: apply_loaded_state_to_world failed on legacy save: %s" % apply_res.get("error"))
		return false

	if BuildingSystemScript.is_market_active(wv.world_data):
		printerr("FAIL: Market should not exist in reloaded legacy world")
		return false

	print("  PASS: TC-MKT-13 Legacy save without Market loads smoothly with zero errors")
	return true

func _test_tc_mkt_14_save_load_persistence_and_marker() -> bool:
	print("[TC-MKT-14] Testing Market and active caravan save/load persistence...")
	var wv = world_instance

	# Place active Market on valid grass land
	var m_origin := Vector2i(22, 22)
	for ox in range(-1, 4):
		for oy in range(-1, 4):
			wv.world_data.terrain[m_origin.x + ox][m_origin.y + oy] = WorldGeneratorScript.TerrainType.GRASS
			wv.world_data.occupancy[m_origin.x + ox][m_origin.y + oy] = false

	for ox in range(3):
		for oy in range(3):
			wv.world_data.occupancy[m_origin.x + ox][m_origin.y + oy] = true

	var m_bld := {
		"id": "bld_market_persist_test",
		"type": "market",
		"cell": m_origin,
		"size": Vector2i(3, 3),
		"state": "active",
		"health": 100,
		"max_health": 100,
		"construction_progress": 12.0,
		"construction_hours": 12.0
	}
	wv.world_data.buildings.append(m_bld)

	# Active caravan
	var c = TradeCaravanScript.generate_caravan(8888, 8, "rival_merchant")
	c.gold = 525
	wv.set("active_caravan", c)
	wv.refresh_caravan_marker()

	# Save to isolated file
	var save_res = SaveManagerScript.save_to_file(wv, TEST_SAVE_PATH)
	if not save_res.get("success", false):
		printerr("FAIL: Save failed: %s" % save_res.get("error"))
		return false

	# Clear runtime state
	wv.set("active_caravan", null)
	wv.refresh_caravan_marker()

	# Reload from file
	var load_res = SaveManagerScript.load_from_file(TEST_SAVE_PATH)
	if not load_res.get("success", false):
		printerr("FAIL: Load failed: %s" % load_res.get("error"))
		return false

	var apply_res = SaveManagerScript.apply_loaded_state_to_world(wv, load_res["data"])
	if not apply_res.get("success", false):
		printerr("FAIL: Apply loaded state failed: %s" % apply_res.get("error"))
		return false

	# Verify Market restored
	if not BuildingSystemScript.is_market_active(wv.world_data, "bld_market_persist_test"):
		printerr("FAIL: Market was not restored to active state")
		return false

	# Verify active caravan restored
	var restored_caravan = wv.get("active_caravan")
	if restored_caravan == null or not bool(restored_caravan.get("is_active")):
		printerr("FAIL: Active caravan was not restored")
		return false
	if int(restored_caravan.get("gold")) != 525:
		printerr("FAIL: Restored caravan gold expected 525, got: %s" % restored_caravan.get("gold"))
		return false

	# Verify marker reconstructed and docked at Market
	var marker: Node2D = wv.get_caravan_marker()
	if marker == null:
		printerr("FAIL: Caravan marker was not reconstructed after load")
		return false
	if not marker.visible:
		printerr("FAIL: Restored caravan marker is not visible")
		return false
	if not wv.is_caravan_docked_at_market():
		printerr("FAIL: Restored caravan marker should be docked at Market")
		return false

	# Verify no duplicate marker nodes in citizens_container
	var marker_count := 0
	if wv.citizens_container != null:
		for child in wv.citizens_container.get_children():
			if child is CaravanMarkerScript or child.name == "CaravanMarker":
				marker_count += 1
	if marker_count != 1:
		printerr("FAIL: Expected exactly 1 CaravanMarker in container, found: %d" % marker_count)
		return false

	print("  PASS: TC-MKT-14 Market & caravan persist cleanly and marker reconstructs without duplicate")
	return true

func _test_tc_mkt_15_marker_idempotency_and_departure() -> bool:
	print("[TC-MKT-15] Testing marker idempotency and departure cleanup...")
	var wv = world_instance

	# 1. Repeated calls to refresh_caravan_marker()
	for i in range(5):
		wv.refresh_caravan_marker()

	var count_during := 0
	if wv.citizens_container != null:
		for child in wv.citizens_container.get_children():
			if child is CaravanMarkerScript or child.name == "CaravanMarker":
				count_during += 1
	if count_during != 1:
		printerr("FAIL: Repeated refresh calls created duplicate CaravanMarker nodes: %d" % count_during)
		return false

	# 2. Caravan departure
	var c = wv.get("active_caravan")
	if c != null:
		c.set("is_active", false)
	wv.set("active_caravan", null)
	wv.refresh_caravan_marker()

	var marker: Node2D = wv.get_caravan_marker()
	if marker != null and marker.visible:
		printerr("FAIL: Caravan marker should not be visible after caravan departure")
		return false

	var count_after := 0
	if wv.citizens_container != null:
		for child in wv.citizens_container.get_children():
			if (child is CaravanMarkerScript or child.name == "CaravanMarker") and child.visible:
				count_after += 1
	if count_after != 0:
		printerr("FAIL: Found visible CaravanMarker nodes after departure: %d" % count_after)
		return false

	print("  PASS: TC-MKT-15 Repeated refresh is strictly idempotent and departure cleans up cleanly")
	return true

func _test_tc_mkt_16_neutral_baseline() -> bool:
	print("[TC-MKT-16] Testing Dynamic Pricing Neutral Baseline (multiplier == 1.0)...")
	var c = TradeCaravanScript.new("test_caravan_neutral", "Đoàn Buôn Thử Nghiệm", "rival_merchant")
	c.inventory = {
		EconomyConfigScript.RES_FOOD: 45,
		EconomyConfigScript.RES_WOOD: 35,
		EconomyConfigScript.RES_STONE: 22,
		EconomyConfigScript.RES_METAL: 17,
		EconomyConfigScript.RES_TOOLS: 10,
		EconomyConfigScript.RES_HERBS: 17,
		EconomyConfigScript.RES_CRYSTAL: 4
	}
	c.gold = 500
	c.sell_prices = {
		EconomyConfigScript.RES_FOOD: 2, EconomyConfigScript.RES_WOOD: 3,
		EconomyConfigScript.RES_STONE: 4, EconomyConfigScript.RES_METAL: 8,
		EconomyConfigScript.RES_TOOLS: 15, EconomyConfigScript.RES_HERBS: 6,
		EconomyConfigScript.RES_CRYSTAL: 35
	}
	c.buy_prices = {
		EconomyConfigScript.RES_FOOD: 1, EconomyConfigScript.RES_WOOD: 2,
		EconomyConfigScript.RES_STONE: 2, EconomyConfigScript.RES_METAL: 5,
		EconomyConfigScript.RES_TOOLS: 10, EconomyConfigScript.RES_HERBS: 4,
		EconomyConfigScript.RES_CRYSTAL: 22
	}
	var rm = MockTestResourceManager.new({
		EconomyConfigScript.RES_FOOD: 150,
		EconomyConfigScript.RES_WOOD: 120,
		EconomyConfigScript.RES_STONE: 60,
		EconomyConfigScript.RES_METAL: 20,
		EconomyConfigScript.RES_TOOLS: 15,
		EconomyConfigScript.RES_HERBS: 10,
		EconomyConfigScript.RES_CRYSTAL: 5
	})

	for res_id in [EconomyConfigScript.RES_FOOD, EconomyConfigScript.RES_WOOD, EconomyConfigScript.RES_TOOLS, EconomyConfigScript.RES_CRYSTAL]:
		var bd = c.get_price_breakdown(res_id, 0.0, rm)
		if absf(float(bd.get("market_multiplier", 0.0)) - 1.0) > 0.01:
			printerr("FAIL: TC-MKT-16 expected market_multiplier 1.0 for %s, got %f" % [res_id, bd.get("market_multiplier")])
			return false
		if bd.get("final_sell_price") != c.sell_prices[res_id]:
			printerr("FAIL: TC-MKT-16 sell price for %s expected %d, got %d" % [res_id, c.sell_prices[res_id], bd.get("final_sell_price")])
			return false
		if bd.get("final_buy_price") != c.buy_prices[res_id]:
			printerr("FAIL: TC-MKT-16 buy price for %s expected %d, got %d" % [res_id, c.buy_prices[res_id], bd.get("final_buy_price")])
			return false

	print("  PASS: TC-MKT-16 Neutral baseline strictly preserves base sell/buy prices at reference stock")
	return true

func _test_tc_mkt_17_kingdom_scarcity_and_surplus() -> bool:
	print("[TC-MKT-17] Testing Kingdom Scarcity & Surplus price elasticity...")
	var c = TradeCaravanScript.new("test_caravan_elasticity", "Đoàn Buôn", "rival_merchant")
	c.inventory = {EconomyConfigScript.RES_TOOLS: 10}
	c.sell_prices = {EconomyConfigScript.RES_TOOLS: 15}
	c.buy_prices = {EconomyConfigScript.RES_TOOLS: 10}

	# 1. Scarcity: 0 tools in kingdom (ref = 15) -> local pressure = +0.10, mult = 1.10
	var rm_scarce = MockTestResourceManager.new({EconomyConfigScript.RES_TOOLS: 0})
	var bd_scarce = c.get_price_breakdown(EconomyConfigScript.RES_TOOLS, 0.0, rm_scarce)
	if absf(float(bd_scarce.get("local_pressure", 0.0)) - 0.10) > 0.001:
		printerr("FAIL: TC-MKT-17 local_pressure expected 0.10, got %f" % bd_scarce.get("local_pressure"))
		return false
	if absf(float(bd_scarce.get("market_multiplier", 0.0)) - 1.10) > 0.001:
		printerr("FAIL: TC-MKT-17 market_multiplier expected 1.10, got %f" % bd_scarce.get("market_multiplier"))
		return false
	if bd_scarce.get("final_sell_price") != 17: # 15 * 1.10 = 16.5 -> 17
		printerr("FAIL: TC-MKT-17 scarce sell price expected 17, got %d" % bd_scarce.get("final_sell_price"))
		return false
	if bd_scarce.get("final_buy_price") != 11: # 10 * 1.10 = 11.0 -> 11
		printerr("FAIL: TC-MKT-17 scarce buy price expected 11, got %d" % bd_scarce.get("final_buy_price"))
		return false

	# 2. Surplus: 30 tools in kingdom (>= 2 * 15) -> local pressure = -0.10, mult = 0.90
	var rm_surplus = MockTestResourceManager.new({EconomyConfigScript.RES_TOOLS: 30})
	var bd_surplus = c.get_price_breakdown(EconomyConfigScript.RES_TOOLS, 0.0, rm_surplus)
	if absf(float(bd_surplus.get("local_pressure", 0.0)) - (-0.10)) > 0.001:
		printerr("FAIL: TC-MKT-17 local_pressure expected -0.10, got %f" % bd_surplus.get("local_pressure"))
		return false
	if absf(float(bd_surplus.get("market_multiplier", 0.0)) - 0.90) > 0.001:
		printerr("FAIL: TC-MKT-17 market_multiplier expected 0.90, got %f" % bd_surplus.get("market_multiplier"))
		return false
	if bd_surplus.get("final_sell_price") != 14: # 15 * 0.90 = 13.5 -> 14
		printerr("FAIL: TC-MKT-17 surplus sell price expected 14, got %d" % bd_surplus.get("final_sell_price"))
		return false
	if bd_surplus.get("final_buy_price") != 9: # 10 * 0.90 = 9.0 -> 9
		printerr("FAIL: TC-MKT-17 surplus buy price expected 9, got %d" % bd_surplus.get("final_buy_price"))
		return false

	print("  PASS: TC-MKT-17 Kingdom scarcity raises price (+10%) and surplus lowers price (-10%)")
	return true

func _test_tc_mkt_18_caravan_scarcity_and_surplus() -> bool:
	print("[TC-MKT-18] Testing Caravan Scarcity & Surplus price elasticity...")
	var rm = MockTestResourceManager.new({EconomyConfigScript.RES_TOOLS: 15}) # ref is 15 -> local_p = 0

	# 1. Caravan Scarcity: 0 tools in caravan (ref = 10) -> caravan pressure = +0.10, mult = 1.10
	var c_scarce = TradeCaravanScript.new("c_scarce", "Đoàn Buôn", "rival_merchant")
	c_scarce.inventory = {EconomyConfigScript.RES_TOOLS: 0}
	c_scarce.sell_prices = {EconomyConfigScript.RES_TOOLS: 15}
	c_scarce.buy_prices = {EconomyConfigScript.RES_TOOLS: 10}
	var bd_scarce = c_scarce.get_price_breakdown(EconomyConfigScript.RES_TOOLS, 0.0, rm)
	if absf(float(bd_scarce.get("caravan_pressure", 0.0)) - 0.10) > 0.001:
		printerr("FAIL: TC-MKT-18 caravan_pressure expected 0.10, got %f" % bd_scarce.get("caravan_pressure"))
		return false
	if bd_scarce.get("final_sell_price") != 17:
		printerr("FAIL: TC-MKT-18 scarce sell price expected 17, got %d" % bd_scarce.get("final_sell_price"))
		return false

	# 2. Caravan Surplus: 20 tools in caravan (>= 2 * 10) -> caravan pressure = -0.10, mult = 0.90
	var c_surplus = TradeCaravanScript.new("c_surplus", "Đoàn Buôn", "rival_merchant")
	c_surplus.inventory = {EconomyConfigScript.RES_TOOLS: 20}
	c_surplus.sell_prices = {EconomyConfigScript.RES_TOOLS: 15}
	c_surplus.buy_prices = {EconomyConfigScript.RES_TOOLS: 10}
	var bd_surplus = c_surplus.get_price_breakdown(EconomyConfigScript.RES_TOOLS, 0.0, rm)
	if absf(float(bd_surplus.get("caravan_pressure", 0.0)) - (-0.10)) > 0.001:
		printerr("FAIL: TC-MKT-18 caravan_pressure expected -0.10, got %f" % bd_surplus.get("caravan_pressure"))
		return false
	if bd_surplus.get("final_sell_price") != 14:
		printerr("FAIL: TC-MKT-18 surplus sell price expected 14, got %d" % bd_surplus.get("final_sell_price"))
		return false

	print("  PASS: TC-MKT-18 Caravan stock scarcity increases price and stock surplus reduces price")
	return true

func _test_tc_mkt_19_strict_multiplier_bounds() -> bool:
	print("[TC-MKT-19] Testing strict market multiplier bounds [0.80, 1.20] across extremes...")
	var c = TradeCaravanScript.new("c_bounds", "Đoàn Buôn", "rival_merchant")
	c.sell_prices = {EconomyConfigScript.RES_TOOLS: 15}
	c.buy_prices = {EconomyConfigScript.RES_TOOLS: 10}

	# Extreme Scarcity: 0 on both sides
	c.inventory = {EconomyConfigScript.RES_TOOLS: 0}
	var rm_zero = MockTestResourceManager.new({EconomyConfigScript.RES_TOOLS: 0})
	var bd_max = c.get_price_breakdown(EconomyConfigScript.RES_TOOLS, 0.0, rm_zero)
	if absf(float(bd_max.get("market_multiplier", 0.0)) - 1.20) > 0.001:
		printerr("FAIL: TC-MKT-19 max multiplier expected 1.20, got %f" % bd_max.get("market_multiplier"))
		return false

	# Extreme Surplus: massive stock on both sides
	c.inventory = {EconomyConfigScript.RES_TOOLS: 99999}
	var rm_mega = MockTestResourceManager.new({EconomyConfigScript.RES_TOOLS: 99999})
	var bd_min = c.get_price_breakdown(EconomyConfigScript.RES_TOOLS, 0.0, rm_mega)
	if absf(float(bd_min.get("market_multiplier", 0.0)) - 0.80) > 0.001:
		printerr("FAIL: TC-MKT-19 min multiplier expected 0.80, got %f" % bd_min.get("market_multiplier"))
		return false

	# Stress test arbitrary values
	for test_c_stock in [0, 1, 5, 10, 20, 50, 500, 5000]:
		c.inventory[EconomyConfigScript.RES_TOOLS] = test_c_stock
		for test_p_stock in [0, 1, 7, 15, 30, 100, 1000]:
			var rm_test = MockTestResourceManager.new({EconomyConfigScript.RES_TOOLS: test_p_stock})
			var bd = c.get_price_breakdown(EconomyConfigScript.RES_TOOLS, 0.0, rm_test)
			var mult = float(bd.get("market_multiplier", 0.0))
			if mult < 0.7999 or mult > 1.2001:
				printerr("FAIL: TC-MKT-19 multiplier out of bounds: %f (c_stock=%d, p_stock=%d)" % [mult, test_c_stock, test_p_stock])
				return false

	print("  PASS: TC-MKT-19 Multiplier strictly bounded within [0.80, 1.20] across all scenarios")
	return true

func _test_tc_mkt_20_spread_and_positive_prices() -> bool:
	print("[TC-MKT-20] Testing bid/ask spread invariant (sell > buy by >= 1) and positive prices...")
	var c = TradeCaravanScript.generate_caravan(8888, 7, "rival_merchant")

	var opinions = [-250.0, -100.0, -50.0, 0.0, 50.0, 100.0, 250.0]
	var wars = [false, true]
	var test_resources = [
		EconomyConfigScript.RES_FOOD,
		EconomyConfigScript.RES_WOOD,
		EconomyConfigScript.RES_STONE,
		EconomyConfigScript.RES_METAL,
		EconomyConfigScript.RES_TOOLS,
		EconomyConfigScript.RES_HERBS,
		EconomyConfigScript.RES_CRYSTAL
	]

	for war_state in wars:
		c.is_origin_at_war = war_state
		for op in opinions:
			# Test with various kingdom stock states (scarcity, neutral, surplus)
			for p_stock_mode in [0, 1, 2]:
				var rm_stocks: Dictionary = {}
				for res in test_resources:
					var ref_val = float(EconomyConfigScript.STARTING_RESOURCES.get(res, 10))
					if p_stock_mode == 0:
						rm_stocks[res] = 0
					elif p_stock_mode == 1:
						rm_stocks[res] = int(ref_val)
					else:
						rm_stocks[res] = int(ref_val * 3.0)
				var rm = MockTestResourceManager.new(rm_stocks)

				for res in test_resources:
					var bd = c.get_price_breakdown(res, op, rm)
					var sell_p = int(bd.get("final_sell_price", 0))
					var buy_p = int(bd.get("final_buy_price", 0))

					if sell_p < 2:
						printerr("FAIL: TC-MKT-20 sell_price must be >= 2 for %s, got %d" % [res, sell_p])
						return false
					if buy_p < 1:
						printerr("FAIL: TC-MKT-20 buy_price must be >= 1 for %s, got %d" % [res, buy_p])
						return false
					if sell_p <= buy_p:
						printerr("FAIL: TC-MKT-20 spread violation: sell (%d) <= buy (%d) for %s (war=%s, op=%f)" % [sell_p, buy_p, res, war_state, op])
						return false

	print("  PASS: TC-MKT-20 Spread invariant (caravan_sell > caravan_buy by >= 1) strictly preserved across all cases")
	return true

func _test_tc_mkt_21_price_breakdown_consistency() -> bool:
	print("[TC-MKT-21] Testing Price Breakdown API completeness and accessor parity...")
	var c = TradeCaravanScript.generate_caravan(9999, 4, "rival_merchant")
	var rm = MockTestResourceManager.new({EconomyConfigScript.RES_WOOD: 50, EconomyConfigScript.RES_FOOD: 80})

	var required_keys = [
		"resource_id", "base_sell_price", "base_buy_price",
		"local_stock", "local_reference_stock", "local_stock_ratio", "local_pressure",
		"caravan_stock", "caravan_reference_stock", "caravan_stock_ratio", "caravan_pressure",
		"market_multiplier", "opinion_adjustment", "route_risk_surcharge",
		"is_origin_at_war", "final_sell_price", "final_buy_price"
	]

	for res_id in [EconomyConfigScript.RES_WOOD, EconomyConfigScript.RES_FOOD]:
		var bd = c.get_price_breakdown(res_id, 25.0, rm)
		for key in required_keys:
			if not bd.has(key):
				printerr("FAIL: TC-MKT-21 breakdown missing key '%s'" % key)
				return false
		var eff_sell = c.get_effective_sell_price(res_id, 25.0, rm)
		var eff_buy = c.get_effective_buy_price(res_id, 25.0, rm)
		if eff_sell != bd.final_sell_price:
			printerr("FAIL: TC-MKT-21 get_effective_sell_price (%d) != bd.final_sell_price (%d)" % [eff_sell, bd.final_sell_price])
			return false
		if eff_buy != bd.final_buy_price:
			printerr("FAIL: TC-MKT-21 get_effective_buy_price (%d) != bd.final_buy_price (%d)" % [eff_buy, bd.final_buy_price])
			return false

	print("  PASS: TC-MKT-21 Price breakdown API contains all schema keys and exactly matches accessors")
	return true

func _test_tc_mkt_22_quote_and_transaction_parity() -> bool:
	print("[TC-MKT-22] Testing exact price quote and transaction execution parity...")
	var c = TradeCaravanScript.generate_caravan(1111, 2, "rival_merchant")
	var rm = MockTestResourceManager.new({
		EconomyConfigScript.RES_GOLD: 500,
		EconomyConfigScript.RES_WOOD: 100
	})
	var res_id = EconomyConfigScript.RES_WOOD

	# Buying parity
	var quoted_sell = c.get_effective_sell_price(res_id, 0.0, rm)
	var pre_gold = rm.get_available_stock(EconomyConfigScript.RES_GOLD)
	var buy_res = c.buy_from_caravan(res_id, 10, rm, 0.0)
	if not buy_res.get("success", false):
		printerr("FAIL: TC-MKT-22 buy failed: %s" % buy_res.get("reason"))
		return false
	if buy_res.get("unit_price") != quoted_sell:
		printerr("FAIL: TC-MKT-22 executed unit_price (%d) != quoted (%d)" % [buy_res.get("unit_price"), quoted_sell])
		return false
	if buy_res.get("total_cost") != quoted_sell * 10:
		printerr("FAIL: TC-MKT-22 total_cost mismatch")
		return false
	if rm.get_available_stock(EconomyConfigScript.RES_GOLD) != pre_gold - (quoted_sell * 10):
		printerr("FAIL: TC-MKT-22 gold deduction mismatch")
		return false

	# Selling parity
	var quoted_buy = c.get_effective_buy_price(res_id, 0.0, rm)
	pre_gold = rm.get_available_stock(EconomyConfigScript.RES_GOLD)
	var pre_c_gold = c.gold
	var sell_res = c.sell_to_caravan(res_id, 10, rm, 0.0)
	if not sell_res.get("success", false):
		printerr("FAIL: TC-MKT-22 sell failed: %s" % sell_res.get("reason"))
		return false
	if sell_res.get("unit_payout") != quoted_buy:
		printerr("FAIL: TC-MKT-22 executed unit_payout (%d) != quoted (%d)" % [sell_res.get("unit_payout"), quoted_buy])
		return false
	if rm.get_available_stock(EconomyConfigScript.RES_GOLD) != pre_gold + (quoted_buy * 10):
		printerr("FAIL: TC-MKT-22 gold credit mismatch")
		return false
	if c.gold != pre_c_gold - (quoted_buy * 10):
		printerr("FAIL: TC-MKT-22 caravan gold deduction mismatch")
		return false

	print("  PASS: TC-MKT-22 Quoted prices and executed prices match 100% with zero deviation")
	return true

func _test_tc_mkt_23_transaction_failure_rollback() -> bool:
	print("[TC-MKT-23] Testing transaction failure atomicity and state immutability...")
	var c = TradeCaravanScript.generate_caravan(2222, 3, "rival_merchant")
	c.gold = 5 # Caravan only has 5 gold
	c.inventory[EconomyConfigScript.RES_WOOD] = 5

	var rm = MockTestResourceManager.new({
		EconomyConfigScript.RES_GOLD: 10,
		EconomyConfigScript.RES_WOOD: 20
	})

	var snap_c_inv = c.inventory.duplicate(true)
	var snap_c_gold = c.gold
	var snap_rm_wood = rm.get_available_stock(EconomyConfigScript.RES_WOOD)
	var snap_rm_gold = rm.get_available_stock(EconomyConfigScript.RES_GOLD)

	# 1. Failure: Insufficient caravan stock (wants 10, has 5)
	var fail_stock = c.buy_from_caravan(EconomyConfigScript.RES_WOOD, 10, rm, 0.0)
	if fail_stock.get("success", true):
		printerr("FAIL: TC-MKT-23 should fail on insufficient caravan stock")
		return false

	# 2. Failure: Insufficient player gold
	c.inventory[EconomyConfigScript.RES_WOOD] = 20
	snap_c_inv[EconomyConfigScript.RES_WOOD] = 20
	var fail_gold = c.buy_from_caravan(EconomyConfigScript.RES_WOOD, 10, rm, 0.0)
	if fail_gold.get("success", true):
		printerr("FAIL: TC-MKT-23 should fail on insufficient player gold")
		return false

	# 3. Failure: Insufficient caravan gold on player sell (caravan has 5 gold, payout for 20 wood is >= 20 gold)
	var fail_c_gold = c.sell_to_caravan(EconomyConfigScript.RES_WOOD, 20, rm, 0.0)
	if fail_c_gold.get("success", true):
		printerr("FAIL: TC-MKT-23 should fail on insufficient caravan gold")
		return false

	# 4. Failure: Insufficient player stock on sell
	var fail_p_stock = c.sell_to_caravan(EconomyConfigScript.RES_FOOD, 10, rm, 0.0) # rm has 0 food
	if fail_p_stock.get("success", true):
		printerr("FAIL: TC-MKT-23 should fail on insufficient player stock")
		return false

	# Verify zero state mutation across standard failures
	if c.gold != snap_c_gold or c.inventory[EconomyConfigScript.RES_WOOD] != snap_c_inv[EconomyConfigScript.RES_WOOD]:
		printerr("FAIL: TC-MKT-23 caravan state mutated during failure")
		return false
	if rm.get_available_stock(EconomyConfigScript.RES_GOLD) != snap_rm_gold or rm.get_available_stock(EconomyConfigScript.RES_WOOD) != snap_rm_wood:
		printerr("FAIL: TC-MKT-23 resource manager state mutated during failure")
		return false

	# 5. Scenario C1: Destination inventory capacity full on buy
	# Player has enough gold (500) and caravan has enough stock (20), but warehouse is at capacity (20/20)
	rm.stock[EconomyConfigScript.RES_GOLD] = 500
	rm.stock[EconomyConfigScript.RES_WOOD] = 20
	rm.capacities[EconomyConfigScript.RES_WOOD] = 20
	c.gold = 500
	c.inventory[EconomyConfigScript.RES_WOOD] = 20

	var c1_snap_c_gold = c.gold
	var c1_snap_c_stock = c.inventory[EconomyConfigScript.RES_WOOD]
	var c1_snap_p_gold = rm.get_available_stock(EconomyConfigScript.RES_GOLD)
	var c1_snap_p_stock = rm.get_available_stock(EconomyConfigScript.RES_WOOD)

	var fail_cap_buy = c.buy_from_caravan(EconomyConfigScript.RES_WOOD, 10, rm, 0.0)
	if fail_cap_buy.get("success", true):
		printerr("FAIL: TC-MKT-23 should fail on full destination inventory capacity")
		return false
	if c.gold != c1_snap_c_gold or c.inventory[EconomyConfigScript.RES_WOOD] != c1_snap_c_stock:
		printerr("FAIL: TC-MKT-23 caravan state mutated during destination capacity failure")
		return false
	if rm.get_available_stock(EconomyConfigScript.RES_GOLD) != c1_snap_p_gold or rm.get_available_stock(EconomyConfigScript.RES_WOOD) != c1_snap_p_stock:
		printerr("FAIL: TC-MKT-23 resource manager state mutated during destination capacity failure")
		return false

	# 6. Scenario C2: Player gold storage capacity full on sell
	# Player has enough goods (20) and caravan has enough gold (500), but player gold vault is at capacity (100/100)
	rm.stock[EconomyConfigScript.RES_GOLD] = 100
	rm.capacities[EconomyConfigScript.RES_GOLD] = 100
	rm.capacities[EconomyConfigScript.RES_WOOD] = 500

	var c2_snap_c_gold = c.gold
	var c2_snap_c_stock = c.inventory[EconomyConfigScript.RES_WOOD]
	var c2_snap_p_gold = rm.get_available_stock(EconomyConfigScript.RES_GOLD)
	var c2_snap_p_stock = rm.get_available_stock(EconomyConfigScript.RES_WOOD)

	var fail_cap_sell = c.sell_to_caravan(EconomyConfigScript.RES_WOOD, 10, rm, 0.0)
	if fail_cap_sell.get("success", true):
		printerr("FAIL: TC-MKT-23 should fail on full player gold capacity")
		return false
	if c.gold != c2_snap_c_gold or c.inventory[EconomyConfigScript.RES_WOOD] != c2_snap_c_stock:
		printerr("FAIL: TC-MKT-23 caravan state mutated during gold capacity failure")
		return false
	if rm.get_available_stock(EconomyConfigScript.RES_GOLD) != c2_snap_p_gold or rm.get_available_stock(EconomyConfigScript.RES_WOOD) != c2_snap_p_stock:
		printerr("FAIL: TC-MKT-23 resource manager state mutated during gold capacity failure")
		return false

	print("  PASS: TC-MKT-23 All failure paths (stock, gold, warehouse cap, gold cap) fail-closed with zero state corruption")
	return true

func _test_tc_mkt_24_post_trade_quote_update() -> bool:
	print("[TC-MKT-24] Testing post-trade price quote elasticity update...")
	# Fixture using Crystal:
	# Local reference stock = 5.0 (EconomyConfig.STARTING_RESOURCES[RES_CRYSTAL])
	# Caravan reference stock = 4.0 (TradeCaravan.CARAVAN_REFERENCE_STOCK[RES_CRYSTAL])
	# Base sell price = 35 Gold, Base buy price = 22 Gold
	var c = TradeCaravanScript.new("c_elastic", "Đoàn Buôn", "rival_merchant")
	c.gold = 1000
	c.inventory = {EconomyConfigScript.RES_CRYSTAL: 4}
	c.sell_prices = {EconomyConfigScript.RES_CRYSTAL: 35}
	c.buy_prices = {EconomyConfigScript.RES_CRYSTAL: 22}

	# Initial kingdom stock: 5 Crystal (neutral reference stock)
	var rm = MockTestResourceManager.new({
		EconomyConfigScript.RES_GOLD: 1000,
		EconomyConfigScript.RES_CRYSTAL: 5
	})

	# 1. Neutral baseline verification
	# Local: 5 / 5.0 -> ratio 1.0 -> local_pressure = 0.0
	# Caravan: 4 / 4.0 -> ratio 1.0 -> caravan_pressure = 0.0
	# market_multiplier = 1.000
	# Unit sell quote: round(35 * 1.000) = 35
	var bd_init = c.get_price_breakdown(EconomyConfigScript.RES_CRYSTAL, 0.0, rm)
	var quote_initial: int = c.get_effective_sell_price(EconomyConfigScript.RES_CRYSTAL, 0.0, rm)
	if absf(float(bd_init.get("market_multiplier", 0.0)) - 1.000) > 0.001:
		printerr("FAIL: TC-MKT-24 initial multiplier expected 1.000, got %f" % bd_init.get("market_multiplier"))
		return false
	if quote_initial != 35:
		printerr("FAIL: TC-MKT-24 initial quote expected 35, got %d" % quote_initial)
		return false

	# 2. Player buys 3 Crystal from caravan
	# Trade execution: 3 Crystal for 3 * 35 = 105 Gold
	var buy_res = c.buy_from_caravan(EconomyConfigScript.RES_CRYSTAL, 3, rm, 0.0)
	if not buy_res.get("success", false):
		printerr("FAIL: TC-MKT-24 buy failed: %s" % buy_res.get("reason"))
		return false
	if buy_res.get("unit_price") != quote_initial:
		printerr("FAIL: TC-MKT-24 executed buy price (%d) != quote_initial (%d)" % [buy_res.get("unit_price"), quote_initial])
		return false

	# Balances after purchase:
	# Kingdom stock: 5 + 3 = 8
	# Caravan inventory: 4 - 3 = 1
	var bd_after_buy = c.get_price_breakdown(EconomyConfigScript.RES_CRYSTAL, 0.0, rm)
	if bd_after_buy.get("local_stock") != 8:
		printerr("FAIL: TC-MKT-24 local_stock expected 8, got %d" % bd_after_buy.get("local_stock"))
		return false
	if bd_after_buy.get("caravan_stock") != 1:
		printerr("FAIL: TC-MKT-24 caravan_stock expected 1, got %d" % bd_after_buy.get("caravan_stock"))
		return false

	# Elasticity calculation after purchase:
	# local_ratio = 8.0 / 5.0 = 1.6 -> local_pressure = (1.0 - 1.6) * 0.10 = -0.060
	# caravan_ratio = 1.0 / 4.0 = 0.25 -> caravan_pressure = (1.0 - 0.25) * 0.10 = +0.075
	# market_multiplier = 1.0 + (-0.060) + 0.075 = 1.015
	# New unit sell quote: round(35 * 1.015) = round(35.525) = 36
	var mult_after_buy: float = float(bd_after_buy.get("market_multiplier", 0.0))
	if absf(mult_after_buy - 1.015) > 0.001:
		printerr("FAIL: TC-MKT-24 multiplier after buy expected 1.015, got %f" % mult_after_buy)
		return false

	var quote_after_buy: int = c.get_effective_sell_price(EconomyConfigScript.RES_CRYSTAL, 0.0, rm)
	if quote_after_buy != 36:
		printerr("FAIL: TC-MKT-24 quote after buy expected 36, got %d" % quote_after_buy)
		return false
	if quote_after_buy <= quote_initial:
		printerr("FAIL: TC-MKT-24 quote after buy (%d) must be strictly greater than quote_initial (%d)" % [quote_after_buy, quote_initial])
		return false

	# 3. Player sells 3 Crystal back to caravan
	# Caravan buys at unit buy price: round(22 * 1.015) = round(22.33) = 22
	var sell_res = c.sell_to_caravan(EconomyConfigScript.RES_CRYSTAL, 3, rm, 0.0)
	if not sell_res.get("success", false):
		printerr("FAIL: TC-MKT-24 sell failed: %s" % sell_res.get("reason"))
		return false

	# Balances after sale:
	# Kingdom stock restored: 8 - 3 = 5
	# Caravan inventory restored: 1 + 3 = 4
	var bd_after_sell = c.get_price_breakdown(EconomyConfigScript.RES_CRYSTAL, 0.0, rm)
	if bd_after_sell.get("local_stock") != 5:
		printerr("FAIL: TC-MKT-24 local_stock restored expected 5, got %d" % bd_after_sell.get("local_stock"))
		return false
	if bd_after_sell.get("caravan_stock") != 4:
		printerr("FAIL: TC-MKT-24 caravan_stock restored expected 4, got %d" % bd_after_sell.get("caravan_stock"))
		return false

	# Elasticity restored to baseline:
	# local_pressure = 0.0, caravan_pressure = 0.0, market_multiplier = 1.000
	# Unit sell quote restored: round(35 * 1.000) = 35 < 36
	var mult_after_sell: float = float(bd_after_sell.get("market_multiplier", 0.0))
	if absf(mult_after_sell - 1.000) > 0.001:
		printerr("FAIL: TC-MKT-24 multiplier after sell expected 1.000, got %f" % mult_after_sell)
		return false

	var quote_after_sell: int = c.get_effective_sell_price(EconomyConfigScript.RES_CRYSTAL, 0.0, rm)
	if quote_after_sell != 35:
		printerr("FAIL: TC-MKT-24 quote after sell expected 35, got %d" % quote_after_sell)
		return false
	if quote_after_sell >= quote_after_buy:
		printerr("FAIL: TC-MKT-24 quote after sell (%d) must be strictly less than quote_after_buy (%d)" % [quote_after_sell, quote_after_buy])
		return false

	print("  PASS: TC-MKT-24 Post-trade price quotes update dynamically from new inventory and stock (35 -> 36 -> 35)")
	return true

func _test_tc_mkt_25_wartime_and_diplomacy_combination() -> bool:
	print("[TC-MKT-25] Testing wartime surcharge (+15%) and diplomatic opinion combination...")
	var c = TradeCaravanScript.new("c_war", "Đoàn Buôn Chiến Sự", "hostile_faction")
	c.inventory = {EconomyConfigScript.RES_TOOLS: 10}
	c.sell_prices = {EconomyConfigScript.RES_TOOLS: 15}
	c.buy_prices = {EconomyConfigScript.RES_TOOLS: 10}

	var rm = MockTestResourceManager.new({EconomyConfigScript.RES_TOOLS: 15}) # local pressure = 0

	# 1. Peace and neutral opinion (multiplier = 1.0)
	c.is_origin_at_war = false
	var p_peace = c.get_effective_sell_price(EconomyConfigScript.RES_TOOLS, 0.0, rm)
	if p_peace != 15:
		printerr("FAIL: TC-MKT-25 peace price expected 15, got %d" % p_peace)
		return false

	# 2. War without diplomatic discount
	c.is_origin_at_war = true
	var p_war = c.get_effective_sell_price(EconomyConfigScript.RES_TOOLS, 0.0, rm)
	# 15 * (1.0 + 0.15) = 17.25 -> round 17
	if p_war != 17:
		printerr("FAIL: TC-MKT-25 wartime price expected 17, got %d" % p_war)
		return false
	if p_war <= p_peace:
		printerr("FAIL: TC-MKT-25 wartime price must be higher than peace price")
		return false

	# 3. War with friendly opinion (+100 opinion -> -20% discount)
	# mult = (1.0 - 0.20 + 0.15) * 1.0 = 0.95. 15 * 0.95 = 14.25 -> 14.
	# But rule: if is_origin_at_war and price <= base, price = base + 1 = 16!
	var p_war_friend = c.get_effective_sell_price(EconomyConfigScript.RES_TOOLS, 100.0, rm)
	if p_war_friend != 16:
		printerr("FAIL: TC-MKT-25 wartime floor expected 16, got %d" % p_war_friend)
		return false

	print("  PASS: TC-MKT-25 Wartime surcharge (+15%) and diplomatic adjustments combine accurately")
	return true

func _test_tc_mkt_26_legacy_save_compatibility() -> bool:
	print("[TC-MKT-26] Testing legacy save deserialization and pricing recomputation...")
	# Simulate legacy save data (prior to Package 2H, no dynamic pricing fields saved)
	var legacy_caravan_data = {
		"caravan_id": "caravan_legacy_99",
		"name": "Đoàn Buôn Cũ",
		"origin_faction_id": "rival_merchant",
		"arrival_day": 5,
		"departure_day": 7,
		"is_active": true,
		"is_origin_at_war": false,
		"gold": 400,
		"inventory": {
			EconomyConfigScript.RES_WOOD: 30,
			EconomyConfigScript.RES_FOOD: 40
		},
		"sell_prices": {
			EconomyConfigScript.RES_WOOD: 3,
			EconomyConfigScript.RES_FOOD: 2
		},
		"buy_prices": {
			EconomyConfigScript.RES_WOOD: 2,
			EconomyConfigScript.RES_FOOD: 1
		}
	}

	var c = TradeCaravanScript.deserialize(legacy_caravan_data)
	if c == null:
		printerr("FAIL: TC-MKT-26 legacy deserialize returned null")
		return false

	var rm = MockTestResourceManager.new({
		EconomyConfigScript.RES_WOOD: 120,
		EconomyConfigScript.RES_FOOD: 150
	})

	var bd_wood = c.get_price_breakdown(EconomyConfigScript.RES_WOOD, 0.0, rm)
	if bd_wood.is_empty():
		printerr("FAIL: TC-MKT-26 get_price_breakdown returned empty on legacy caravan")
		return false

	var sell_wood = c.get_effective_sell_price(EconomyConfigScript.RES_WOOD, 0.0, rm)
	var buy_wood = c.get_effective_buy_price(EconomyConfigScript.RES_WOOD, 0.0, rm)
	if sell_wood <= buy_wood:
		printerr("FAIL: TC-MKT-26 spread violation on legacy caravan")
		return false

	# Reserialize and verify clean roundtrip
	var reserialized = c.serialize()
	var c_roundtrip = TradeCaravanScript.deserialize(reserialized)
	if c_roundtrip == null or c_roundtrip.gold != 400:
		printerr("FAIL: TC-MKT-26 reserialize roundtrip failed")
		return false

	print("  PASS: TC-MKT-26 Legacy caravan saves deserialize cleanly and recompute dynamic prices with 0 errors")
	return true
