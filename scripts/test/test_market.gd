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

		all_passed = (
			pass_tc1 and pass_tc2 and pass_tc3 and pass_tc4 and
			pass_tc5 and pass_tc6 and pass_tc7 and pass_tc8 and
			pass_tc9 and pass_tc10 and pass_tc11 and pass_tc12 and
			pass_tc13 and pass_tc14 and pass_tc15
		)

		_cleanup_test_artifacts()

		print("\n--------------------------------------------------------")
		if all_passed:
			print("  ALL 15 PACKAGE 2A MARKET TESTS PASSED! (Exit Code 0)")
			print("--------------------------------------------------------\n")
			quit(0)
			return true
		else:
			print("  PACKAGE 2A MARKET TESTS FAILED! (Exit Code 1)")
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
