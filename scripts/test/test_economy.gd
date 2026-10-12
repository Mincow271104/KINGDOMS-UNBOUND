extends SceneTree

const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const ResourceManagerScript = preload("res://scripts/economy/resource_manager.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")

func _init() -> void:
	print("--- Running TestEconomy (TC-2.1 & TC-2.2) ---")
	var failures: int = 0
	
	var rm = ResourceManagerScript.new()
	root.add_child(rm)
	rm.reset_economy()
	
	# Test 1: Initial starter stock matches GDD specification
	var start_wood: int = rm.get_available_stock(EconomyConfigScript.RES_WOOD)
	var start_stone: int = rm.get_available_stock(EconomyConfigScript.RES_STONE)
	var start_food: int = rm.get_available_stock(EconomyConfigScript.RES_FOOD)
	var start_gold: int = rm.get_available_stock(EconomyConfigScript.RES_GOLD)
	
	if start_wood != 120 or start_stone != 60 or start_food != 150 or start_gold != 200:
		printerr("FAIL: Starting stock mismatch! Wood=%d, Stone=%d, Food=%d, Gold=%d" % [start_wood, start_stone, start_food, start_gold])
		failures += 1
	else:
		print("PASS: Starting inventory verified (Wood 120, Stone 60, Food 150, Gold 200)")

	# Test 2: Storage limits enforcement
	var initial_wood_cap: int = rm.get_capacity(EconomyConfigScript.RES_WOOD)
	var space: int = initial_wood_cap - start_wood
	var added: int = rm.add_resource(EconomyConfigScript.RES_WOOD, space + 500)
	if added != space:
		printerr("FAIL: add_resource allowed exceeding storage cap! Added %d, expected %d" % [added, space])
		failures += 1
	elif rm.get_total_stock(EconomyConfigScript.RES_WOOD) != initial_wood_cap:
		printerr("FAIL: Total stock %d exceeds cap %d" % [rm.get_total_stock(EconomyConfigScript.RES_WOOD), initial_wood_cap])
		failures += 1
	else:
		print("PASS: Storage capacity strictly enforced; cannot exceed max capacity")

	# Test 3: Atomic reservation & Double-spending prevention
	rm.reset_economy()
	var initial_wood: int = rm.get_available_stock(EconomyConfigScript.RES_WOOD) # 120
	var order_cost: Dictionary = {EconomyConfigScript.RES_WOOD: 100}
	
	var reserved: bool = rm.reserve_cost(order_cost)
	if not reserved:
		printerr("FAIL: reserve_cost failed when affordable!")
		failures += 1
	elif rm.get_available_stock(EconomyConfigScript.RES_WOOD) != 20:
		printerr("FAIL: available stock should be 20, got %d" % rm.get_available_stock(EconomyConfigScript.RES_WOOD))
		failures += 1
	elif rm.get_total_stock(EconomyConfigScript.RES_WOOD) != 120:
		printerr("FAIL: total stock should still be 120 while reserved, got %d" % rm.get_total_stock(EconomyConfigScript.RES_WOOD))
		failures += 1
	else:
		print("PASS: Atomic reservation locks available stock while preserving total stock")

	# Attempt to double-spend the locked wood with another 50 wood order (should FAIL, only 20 available)
	var second_order: Dictionary = {EconomyConfigScript.RES_WOOD: 50}
	if rm.can_afford(second_order) or rm.reserve_cost(second_order):
		printerr("FAIL: Double-spending allowed! Second order was accepted when only 20 available")
		failures += 1
	else:
		print("PASS: Double-spending strictly prevented; second order rejected")

	# Release reservation
	rm.release_cost(order_cost)
	if rm.get_available_stock(EconomyConfigScript.RES_WOOD) != initial_wood:
		printerr("FAIL: release_cost did not restore available stock!")
		failures += 1
	else:
		print("PASS: release_cost restores available stock cleanly")

	# Test 4: All-or-nothing cost reservation
	# Request 50 wood (we have 120) and 999 stone (we only have 60)
	var partial_cost: Dictionary = {EconomyConfigScript.RES_WOOD: 50, EconomyConfigScript.RES_STONE: 999}
	if rm.reserve_cost(partial_cost):
		printerr("FAIL: reserve_cost succeeded with insufficient stone!")
		failures += 1
	elif rm.get_available_stock(EconomyConfigScript.RES_WOOD) != 120:
		printerr("FAIL: partial reservation leaked! Wood was locked when stone was missing")
		failures += 1
	else:
		print("PASS: All-or-nothing reservation prevents partial resource lock")

	# Test 5: Building placement and cost deduction
	var world_data = WorldGeneratorScript.generate(12345)
	
	# House cost: 25 wood, 10 stone
	var house_origin := Vector2i(20, 20)
	# Clear occupancy for test cell (20, 20)
	world_data.occupancy[20][20] = false
	world_data.occupancy[21][20] = false
	world_data.occupancy[20][21] = false
	world_data.occupancy[21][21] = false
	world_data.terrain[20][20] = WorldGeneratorScript.TerrainType.GRASS
	world_data.terrain[21][20] = WorldGeneratorScript.TerrainType.GRASS
	world_data.terrain[20][21] = WorldGeneratorScript.TerrainType.GRASS
	world_data.terrain[21][21] = WorldGeneratorScript.TerrainType.GRASS
	
	var wood_before: int = rm.get_available_stock(EconomyConfigScript.RES_WOOD)
	var stone_before: int = rm.get_available_stock(EconomyConfigScript.RES_STONE)
	
	var res: Dictionary = BuildingSystemScript.place_building("house", house_origin, world_data, rm)
	if not res["success"]:
		printerr("FAIL: Valid building placement failed: %s" % res["reason"])
		failures += 1
	elif rm.get_available_stock(EconomyConfigScript.RES_WOOD) != wood_before - 25:
		printerr("FAIL: Wood cost deducted incorrectly!")
		failures += 1
	elif rm.get_available_stock(EconomyConfigScript.RES_STONE) != stone_before - 10:
		printerr("FAIL: Stone cost deducted incorrectly!")
		failures += 1
	elif not world_data.occupancy[20][20] or not world_data.occupancy[21][21]:
		printerr("FAIL: Building footprint not marked occupied!")
		failures += 1
	else:
		print("PASS: Building placed successfully; costs deducted exactly once; footprint occupied")

	# Attempt placing second building on top of the first (should FAIL)
	var collision_res: Dictionary = BuildingSystemScript.place_building("house", house_origin, world_data, rm)
	if collision_res["success"]:
		printerr("FAIL: Overlapping building placement permitted!")
		failures += 1
	else:
		print("PASS: Collision detection rejects building placement on occupied cell")

	# Attempt placing building on water (should FAIL)
	world_data.terrain[10][10] = WorldGeneratorScript.TerrainType.WATER
	var water_res: Dictionary = BuildingSystemScript.place_building("house", Vector2i(10, 10), world_data, rm)
	if water_res["success"]:
		printerr("FAIL: Building placement on water permitted!")
		failures += 1
	else:
		print("PASS: Terrain check rejects building placement on water")

	# Test 6: Daily food consumption tick
	rm.reset_economy()
	var food_start: int = rm.get_available_stock(EconomyConfigScript.RES_FOOD) # 150
	rm._execute_daily_accounting_tick() # 24 citizens consume 20 food
	var food_after_1_day: int = rm.get_available_stock(EconomyConfigScript.RES_FOOD)
	if food_after_1_day != food_start - 20:
		printerr("FAIL: Daily food tick deducted %d, expected 20" % (food_start - food_after_1_day))
		failures += 1
	else:
		print("PASS: Daily food consumption tick deducted exactly 20 food for 24 citizens")

	rm.queue_free()

	if failures == 0:
		print("=== TC-2.1 & TC-2.2 ALL ECONOMY & BUILDING TESTS PASSED ===")
		quit(0)
	else:
		printerr("=== TC-2.1 & TC-2.2 FAILED WITH %d FAILURES ===" % failures)
		quit(1)
