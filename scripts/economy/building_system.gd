class_name BuildingSystem
extends RefCounted

const EconomyConfig = preload("res://scripts/economy/economy_config.gd")
const IsoMath = preload("res://scripts/utils/iso_math.gd")
## Building Placement & Construction Manager for KINGDOMS UNBOUND.
## Enforces terrain legality, occupancy collision, cost deduction, and storage expansion.

signal building_placed(building_data: Dictionary)
signal building_completed(building_data: Dictionary)
signal building_demolished(building_data: Dictionary)

static func can_place_building(type: String, origin: Vector2i, world_data: WorldGenerator.WorldData, resource_mgr: Node) -> Dictionary:
	var bp: Dictionary = EconomyConfig.BLUEPRINTS.get(type, {})
	if bp.is_empty():
		return {"valid": false, "reason": "Bản thiết kế không tồn tại"}
		
	var size: Vector2i = bp["footprint"]
	var cost: Dictionary = bp["cost"]
	
	# 1. Resource affordability check
	if resource_mgr and not resource_mgr.can_afford(cost):
		return {"valid": false, "reason": "Không đủ tài nguyên xây dựng"}
		
	# 2. Footprint boundary, terrain, and occupancy checks
	for ox in range(size.x):
		for oy in range(size.y):
			var cell := origin + Vector2i(ox, oy)
			
			# Map boundary
			if not IsoMath.is_in_bounds(cell):
				return {"valid": false, "reason": "Vị trí nằm ngoài ranh giới bản đồ"}
				
			# Water terrain check
			if world_data.terrain[cell.x][cell.y] == WorldGenerator.TerrainType.WATER:
				return {"valid": false, "reason": "Không thể xây dựng trên mặt nước"}
				
			# Occupancy collision check
			if world_data.occupancy[cell.x][cell.y]:
				return {"valid": false, "reason": "Vị trí đã bị chiếm dụng bởi công trình hoặc chướng ngại vật"}
				
	return {"valid": true, "reason": ""}

static func place_building(type: String, origin: Vector2i, world_data: WorldGenerator.WorldData, resource_mgr: Node) -> Dictionary:
	var check := can_place_building(type, origin, world_data, resource_mgr)
	if not check["valid"]:
		return {"success": false, "reason": check["reason"]}
		
	var bp: Dictionary = EconomyConfig.BLUEPRINTS[type]
	var cost: Dictionary = bp["cost"]
	var size: Vector2i = bp["footprint"]
	
	# Atomic cost reservation and deduction
	if resource_mgr:
		var reserved: bool = resource_mgr.reserve_cost(cost)
		if not reserved:
			return {"success": false, "reason": "Không thể khóa tài nguyên (thiếu hụt)"}
		resource_mgr.commit_cost(cost)
		
	# Mark cells as occupied
	for ox in range(size.x):
		for oy in range(size.y):
			var cell := origin + Vector2i(ox, oy)
			world_data.occupancy[cell.x][cell.y] = true
			
	# Apply storage bonuses if applicable
	var storage_bonus: Dictionary = bp.get("storage_bonus", {})
	if resource_mgr:
		for res_id in storage_bonus:
			resource_mgr.add_storage_capacity(res_id, storage_bonus[res_id])
			
	var b_data := {
		"id": "bld_%s_%d_%d" % [type, origin.x, origin.y],
		"type": type,
		"cell": origin,
		"size": size,
		"state": "active",
		"health": 100,
		"max_health": 100
	}
	world_data.buildings.append(b_data)
	
	return {"success": true, "building": b_data}

static func demolish_building(b_data: Dictionary, world_data: WorldGenerator.WorldData, resource_mgr: Node, refund_ratio: float = 0.5) -> Dictionary:
	var type: String = b_data["type"]
	var origin: Vector2i = b_data["cell"]
	var size: Vector2i = b_data["size"]
	var bp: Dictionary = EconomyConfig.BLUEPRINTS.get(type, {})
	
	# Clear occupancy
	for ox in range(size.x):
		for oy in range(size.y):
			var cell := origin + Vector2i(ox, oy)
			if IsoMath.is_in_bounds(cell):
				world_data.occupancy[cell.x][cell.y] = false
				
	# Refund portion of materials
	if resource_mgr and not bp.is_empty():
		var cost: Dictionary = bp["cost"]
		for res_id in cost:
			var refund_amount: int = int(float(cost[res_id]) * refund_ratio)
			if refund_amount > 0:
				resource_mgr.add_resource(res_id, refund_amount)
				
	world_data.buildings.erase(b_data)
	return {"success": true}

static func get_total_housing_capacity(world_data: WorldGenerator.WorldData) -> int:
	if world_data == null:
		return 0
	var total: int = 0
	for b in world_data.buildings:
		if b.get("state", "active") != "destroyed":
			var bp: Dictionary = EconomyConfig.BLUEPRINTS.get(b.get("type", ""), {})
			total += bp.get("housing_capacity", 0)
	return total

static func is_town_hall_active(world_data: WorldGenerator.WorldData) -> bool:
	if world_data == null:
		return false
	for b in world_data.buildings:
		if b.get("type", "") == "townhall" and b.get("state", "active") != "destroyed":
			return true
	return false
