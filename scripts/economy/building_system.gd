class_name BuildingSystem
extends RefCounted
## Building Placement & Construction Manager for KINGDOMS UNBOUND.
## Enforces terrain legality, occupancy collision, cost deduction, and storage expansion.


static func can_place_building(type: String, origin: Vector2i, world_data: WorldGenerator.WorldData, resource_mgr: Node) -> Dictionary:
	var bp: Dictionary = EconomyConfig.BLUEPRINTS.get(type, {})
	if bp.is_empty():
		return {"valid": false, "reason": "Bản thiết kế không tồn tại"}
		
	var size: Vector2i = bp["footprint"]
	var cost: Dictionary = bp["cost"]
	
	# 1. Resource affordability check
	if not cost.is_empty():
		if resource_mgr == null:
			return {"valid": false, "reason": "Hệ thống tài nguyên không khả dụng"}
		if not resource_mgr.can_afford(cost):
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
				
	# 3. Accessibility check for production workplaces and barracks
	if bp.get("output_resource", "") != "" or bp.has("recipes") or type in ["workshop", "barracks"]:
		var access_cell := find_access_cell(origin, size, world_data)
		if access_cell == Vector2i(-1, -1):
			return {"valid": false, "reason": "Không có vị trí tiếp cận khả dụng"}

	return {"valid": true, "reason": ""}

static func find_access_cell(origin: Vector2i, size: Vector2i, world_data: WorldGenerator.WorldData) -> Vector2i:
	if world_data == null:
		return Vector2i(-1, -1)

	var candidates: Array[Vector2i] = []
	# Perimeter adjacent cells outside footprint (cardinal edges)
	# 1. Left edge: (origin.x - 1, origin.y + oy)
	for oy in range(size.y):
		candidates.append(Vector2i(origin.x - 1, origin.y + oy))
	# 2. Top edge: (origin.x + ox, origin.y - 1)
	for ox in range(size.x):
		candidates.append(Vector2i(origin.x + ox, origin.y - 1))
	# 3. Right edge: (origin.x + size.x, origin.y + oy)
	for oy in range(size.y):
		candidates.append(Vector2i(origin.x + size.x, origin.y + oy))
	# 4. Bottom edge: (origin.x + ox, origin.y + size.y)
	for ox in range(size.x):
		candidates.append(Vector2i(origin.x + ox, origin.y + size.y))

	for cell in candidates:
		if not IsoMath.is_in_bounds(cell):
			continue
		if world_data.terrain[cell.x][cell.y] == WorldGenerator.TerrainType.WATER:
			continue
		if world_data.occupancy[cell.x][cell.y]:
			continue
		return cell

	return Vector2i(-1, -1)

static func place_building(type: String, origin: Vector2i, world_data: WorldGenerator.WorldData, resource_mgr: Node, initial_state: String = "under_construction") -> Dictionary:
	var check := can_place_building(type, origin, world_data, resource_mgr)
	if not check["valid"]:
		return {"success": false, "reason": check["reason"]}
		
	var bp: Dictionary = EconomyConfig.BLUEPRINTS[type]
	var cost: Dictionary = bp["cost"]
	var size: Vector2i = bp["footprint"]
	
	# Atomic cost reservation and deduction
	if not cost.is_empty():
		if resource_mgr == null:
			return {"success": false, "reason": "Hệ thống tài nguyên không khả dụng"}
		var reserved: bool = resource_mgr.reserve_cost(cost)
		if not reserved:
			return {"success": false, "reason": "Không thể khóa tài nguyên (thiếu hụt)"}
		resource_mgr.commit_cost(cost)
		
	# Mark cells as occupied
	for ox in range(size.x):
		for oy in range(size.y):
			var cell := origin + Vector2i(ox, oy)
			world_data.occupancy[cell.x][cell.y] = true

	var construction_hours: float = float(bp.get("construction_hours", 12.0))
	var is_active: bool = (initial_state == "active")
			
	var b_data := {
		"id": "bld_%s_%d_%d" % [type, origin.x, origin.y],
		"type": type,
		"cell": origin,
		"size": size,
		"state": initial_state,
		"health": 100,
		"max_health": 100,
		"construction_progress": construction_hours if is_active else 0.0,
		"construction_hours": construction_hours
	}
	world_data.buildings.append(b_data)

	# Apply storage bonuses only when active immediately
	if is_active:
		apply_completion_effects(b_data, resource_mgr)
	
	return {"success": true, "building": b_data}

static func apply_completion_effects(b_data: Dictionary, resource_mgr: Node) -> void:
	if resource_mgr == null or b_data.is_empty():
		return
	var type: String = b_data.get("type", "")
	var bp: Dictionary = EconomyConfig.BLUEPRINTS.get(type, {})
	var storage_bonus: Dictionary = bp.get("storage_bonus", {})
	for res_id in storage_bonus:
		resource_mgr.add_storage_capacity(res_id, storage_bonus[res_id])

static func advance_construction(b_data_or_id, delta_hours: float, world_data: WorldGenerator.WorldData) -> Dictionary:
	var b_data: Dictionary = {}
	if b_data_or_id is Dictionary:
		b_data = b_data_or_id
	elif b_data_or_id is String:
		b_data = get_building_by_id(b_data_or_id, world_data)

	if b_data.is_empty():
		return {"success": false, "completed": false, "progress": 0.0, "hours": 0.0}

	if b_data.get("state", "") != "under_construction":
		return {
			"success": false,
			"completed": false,
			"progress": float(b_data.get("construction_progress", 0.0)),
			"hours": float(b_data.get("construction_hours", 0.0))
		}

	var total_hours: float = float(b_data.get("construction_hours", 12.0))
	var cur_prog: float = float(b_data.get("construction_progress", 0.0))
	cur_prog = clampf(cur_prog + delta_hours, 0.0, total_hours)
	b_data["construction_progress"] = cur_prog

	var completed: bool = cur_prog >= total_hours
	return {
		"success": true,
		"completed": completed,
		"progress": cur_prog,
		"hours": total_hours
	}

static func complete_building(b_data_or_id, world_data: WorldGenerator.WorldData, resource_mgr: Node = null) -> bool:
	var b_data: Dictionary = {}
	if b_data_or_id is Dictionary:
		b_data = b_data_or_id
	elif b_data_or_id is String:
		b_data = get_building_by_id(b_data_or_id, world_data)

	if b_data.is_empty():
		return false

	if b_data.get("state", "") != "under_construction":
		return false # Idempotent: cannot complete if already active or other state

	b_data["state"] = "active"
	b_data["construction_progress"] = float(b_data.get("construction_hours", 0.0))
	apply_completion_effects(b_data, resource_mgr)
	return true

static func cancel_construction(b_data_or_id, world_data: WorldGenerator.WorldData, resource_mgr: Node = null, job_mgr: Object = null) -> Dictionary:
	var b_data: Dictionary = {}
	if b_data_or_id is Dictionary:
		b_data = b_data_or_id
	elif b_data_or_id is String:
		b_data = get_building_by_id(b_data_or_id, world_data)

	if b_data.is_empty():
		return {"success": false, "reason": "Công trình không tồn tại"}

	if b_data.get("state", "") != "under_construction":
		return {"success": false, "reason": "Chỉ có thể hủy công trình đang xây dựng"}

	var b_id: String = b_data.get("id", "")
	var type: String = b_data.get("type", "")
	var origin: Vector2i = b_data.get("cell", Vector2i(-1, -1))
	var size: Vector2i = b_data.get("size", Vector2i(1, 1))
	var bp: Dictionary = EconomyConfig.BLUEPRINTS.get(type, {})

	# 1. Clear occupancy
	if world_data:
		for ox in range(size.x):
			for oy in range(size.y):
				var cell := origin + Vector2i(ox, oy)
				if IsoMath.is_in_bounds(cell):
					world_data.occupancy[cell.x][cell.y] = false

	# 2. 50% material refund
	var refund_ratio: float = 0.5
	var refunded: Dictionary = {}
	if resource_mgr and not bp.is_empty():
		var cost: Dictionary = bp.get("cost", {})
		for res_id in cost:
			var refund_amount: int = int(float(cost[res_id]) * refund_ratio)
			if refund_amount > 0:
				resource_mgr.add_resource(res_id, refund_amount)
				refunded[res_id] = refund_amount

	# 3. Remove jobs from job_mgr
	if job_mgr and job_mgr.has_method("remove_jobs_for_building"):
		job_mgr.remove_jobs_for_building(b_id)

	# 4. Remove from world_data
	if world_data:
		world_data.buildings.erase(b_data)

	return {"success": true, "refunded": refunded}

static func get_building_by_id(b_id: String, world_data: WorldGenerator.WorldData) -> Dictionary:
	if world_data == null or b_id == "":
		return {}
	for b in world_data.buildings:
		if b.get("id", "") == b_id:
			return b
	return {}

static func is_building_under_construction(world_data: WorldGenerator.WorldData, building_id: String = "") -> bool:
	if world_data == null or building_id == "":
		return false
	for b in world_data.buildings:
		if b.get("id", "") == building_id:
			return b.get("state", "") == "under_construction"
	return false

static func get_construction_worker_capacity(type: String) -> int:
	var bp: Dictionary = EconomyConfig.BLUEPRINTS.get(type, {})
	var size: Vector2i = bp.get("footprint", Vector2i(1, 1))
	var max_dim: int = maxi(size.x, size.y)
	if max_dim <= 1:
		return 2
	elif max_dim == 2:
		return 3
	else:
		return 4

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
		if b.get("state", "active") == "active":
			var bp: Dictionary = EconomyConfig.BLUEPRINTS.get(b.get("type", ""), {})
			total += bp.get("housing_capacity", 0)
	return total

static func is_town_hall_active(world_data: WorldGenerator.WorldData) -> bool:
	if world_data == null:
		return false
	for b in world_data.buildings:
		if b.get("type", "") == "townhall" and b.get("state", "active") == "active":
			return true
	return false

static func is_research_hall_active(world_data: WorldGenerator.WorldData) -> bool:
	if world_data == null:
		return false
	for b in world_data.buildings:
		if b.get("type", "") == "research_hall" and b.get("state", "active") == "active":
			return true
	return false

static func is_barracks_active(world_data: WorldGenerator.WorldData, barracks_id: String = "") -> bool:
	if world_data == null:
		return false
	for b in world_data.buildings:
		if b.get("type", "") == "barracks":
			var b_id: String = b.get("id", "")
			if barracks_id == "" or b_id == barracks_id:
				if b.get("state", "active") == "active":
					return true
	return false

static func find_perimeter_cells(origin: Vector2i, size: Vector2i, world_data: WorldGenerator.WorldData, max_count: int = 2, excluded_cells: Array = []) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if world_data == null:
		return result

	var candidates: Array[Vector2i] = []
	# 1. Front/South edge: (origin.x + ox, origin.y + size.y)
	for ox in range(size.x):
		candidates.append(Vector2i(origin.x + ox, origin.y + size.y))
	# 2. Right/East edge: (origin.x + size.x, origin.y + oy)
	for oy in range(size.y):
		candidates.append(Vector2i(origin.x + size.x, origin.y + oy))
	# 3. Left/West edge: (origin.x - 1, origin.y + oy)
	for oy in range(size.y):
		candidates.append(Vector2i(origin.x - 1, origin.y + oy))
	# 4. Back/North edge: (origin.x + ox, origin.y - 1)
	for ox in range(size.x):
		candidates.append(Vector2i(origin.x + ox, origin.y - 1))

	for cell in candidates:
		if not IsoMath.is_in_bounds(cell):
			continue
		if world_data.terrain[cell.x][cell.y] == WorldGenerator.TerrainType.WATER:
			continue
		if world_data.occupancy[cell.x][cell.y]:
			continue
		if excluded_cells.has(cell):
			continue
		if not result.has(cell):
			result.append(cell)
			if result.size() >= max_count:
				break

	return result
