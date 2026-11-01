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
		"upgrade_level": 1,
		"construction_progress": construction_hours if is_active else 0.0,
		"construction_hours": construction_hours
	}
	world_data.buildings.append(b_data)

	# Apply storage bonuses only when active immediately
	if is_active:
		apply_completion_effects(b_data, resource_mgr)
	
	return {"success": true, "building": b_data}

static func apply_completion_effects(b_data: Dictionary, resource_mgr: Object) -> bool:
	if resource_mgr == null or b_data.is_empty():
		return false
	if b_data.get("storage_applied", false):
		return false # Guard against duplicating storage capacity
	var type: String = b_data.get("type", "")
	var bp: Dictionary = EconomyConfig.BLUEPRINTS.get(type, {})
	var storage_bonus: Dictionary = bp.get("storage_bonus", {})
	if storage_bonus.is_empty():
		return true
	if not resource_mgr.has_method("add_storage_capacity"):
		return false
	for res_id in storage_bonus:
		resource_mgr.add_storage_capacity(res_id, storage_bonus[res_id])
	b_data["storage_applied"] = true
	return true

static func advance_construction(b_data_or_id, delta_hours: float, world_data: WorldGenerator.WorldData) -> Dictionary:
	var b_data: Dictionary = {}
	if b_data_or_id is Dictionary:
		b_data = b_data_or_id
	elif b_data_or_id is String:
		b_data = get_building_by_id(b_data_or_id, world_data)

	if b_data.is_empty():
		return {"success": false, "completed": false, "progress": 0.0, "hours": 0.0, "progress_delta": 0.0}

	if b_data.get("state", "") != "under_construction":
		return {
			"success": false,
			"completed": false,
			"progress": float(b_data.get("construction_progress", 0.0)),
			"hours": float(b_data.get("construction_hours", 0.0)),
			"progress_delta": 0.0
		}

	var total_hours: float = float(b_data.get("construction_hours", 12.0))
	var cur_prog: float = float(b_data.get("construction_progress", 0.0))

	# Reject negative or invalid (NaN/inf) time deltas without reducing progress
	if delta_hours <= 0.0 or is_nan(delta_hours) or is_inf(delta_hours):
		return {
			"success": false,
			"completed": cur_prog >= (total_hours - 0.001),
			"progress": cur_prog,
			"hours": total_hours,
			"progress_delta": 0.0
		}

	var old_prog: float = cur_prog
	cur_prog = clampf(cur_prog + delta_hours, 0.0, total_hours)
	b_data["construction_progress"] = cur_prog
	var progress_made: float = maxf(0.0, cur_prog - old_prog)

	# Floating-point tolerance for required construction time (0.001 hours ~= 3.6 seconds)
	const PROGRESS_TOLERANCE: float = 0.001
	var completed: bool = cur_prog >= (total_hours - PROGRESS_TOLERANCE)
	return {
		"success": true,
		"completed": completed,
		"progress": cur_prog,
		"hours": total_hours,
		"progress_delta": progress_made
	}

static func complete_building(b_data_or_id, world_data: WorldGenerator.WorldData, resource_mgr: Object = null) -> bool:
	var b_data: Dictionary = {}
	if b_data_or_id is Dictionary:
		b_data = b_data_or_id
	elif b_data_or_id is String:
		b_data = get_building_by_id(b_data_or_id, world_data)

	if b_data.is_empty():
		return false

	if b_data.get("state", "") != "under_construction":
		return false # Idempotent: cannot complete if already active or other state

	var total_hours: float = float(b_data.get("construction_hours", 0.0))
	if is_nan(total_hours) or is_inf(total_hours) or total_hours <= 0.0:
		return false

	var cur_prog: float = float(b_data.get("construction_progress", 0.0))
	if is_nan(cur_prog) or is_inf(cur_prog):
		return false

	# Floating-point tolerance for required construction time (0.001 hours ~= 3.6 seconds)
	const PROGRESS_TOLERANCE: float = 0.001
	if cur_prog < (total_hours - PROGRESS_TOLERANCE):
		return false # Refuse premature activation at 0% or partial progress

	# Fail safely before changing construction state if required storage effects cannot be applied
	var type: String = b_data.get("type", "")
	var bp: Dictionary = EconomyConfig.BLUEPRINTS.get(type, {})
	var storage_bonus: Dictionary = bp.get("storage_bonus", {})
	if not storage_bonus.is_empty():
		if resource_mgr == null or not resource_mgr.has_method("add_storage_capacity"):
			return false

	b_data["state"] = "active"
	b_data["construction_progress"] = total_hours
	apply_completion_effects(b_data, resource_mgr)
	return true

static func is_valid_resource_manager_for_cancellation(resource_mgr: Object) -> bool:
	if resource_mgr == null or not is_instance_valid(resource_mgr):
		return false
	if not resource_mgr.has_method("get_total_stock"):
		return false
	if not resource_mgr.has_method("get_storage_capacity") and not resource_mgr.has_method("get_capacity"):
		return false
	if not resource_mgr.has_method("add_resources_atomic"):
		return false
	return true

## Preflights cancellation feasibility, calculating 50% refund and verifying storage space.
## Returns {"can_cancel": bool, "refund": Dictionary, "insufficient_storage": bool, "reason": String}.
static func can_cancel_construction(b_data_or_id, world_data: WorldGenerator.WorldData, resource_mgr: Object = null, refund_ratio: float = 0.5) -> Dictionary:
	var b_data: Dictionary = {}
	if b_data_or_id is Dictionary:
		b_data = b_data_or_id
	elif b_data_or_id is String:
		b_data = get_building_by_id(b_data_or_id, world_data)

	if b_data.is_empty():
		return {"can_cancel": false, "reason": "Công trình không tồn tại", "insufficient_storage": false, "refund": {}}

	if b_data.get("state", "") != "under_construction":
		return {"can_cancel": false, "reason": "Chỉ có thể hủy công trình đang xây dựng", "insufficient_storage": false, "refund": {}}

	var type: String = b_data.get("type", "")
	var bp: Dictionary = EconomyConfig.BLUEPRINTS.get(type, {})
	var cost: Dictionary = bp.get("cost", {})
	var planned_refund: Dictionary = {}
	for res_id in cost:
		var refund_amount: int = int(float(cost[res_id]) * refund_ratio)
		if refund_amount > 0:
			planned_refund[res_id] = refund_amount

	if not planned_refund.is_empty():
		if not is_valid_resource_manager_for_cancellation(resource_mgr):
			return {
				"can_cancel": false,
				"reason": "Yêu cầu ResourceManager hợp lệ có add_resources_atomic để hoàn trả tài nguyên",
				"insufficient_storage": false,
				"refund": planned_refund
			}
		for res_id in planned_refund:
			var refund_amount: int = planned_refund[res_id]
			var space: int = 999999
			if resource_mgr.has_method("get_storage_capacity") and resource_mgr.has_method("get_total_stock"):
				var cap: int = int(resource_mgr.get_storage_capacity(res_id))
				var cur: int = int(resource_mgr.get_total_stock(res_id))
				space = maxi(0, cap - cur)
			elif resource_mgr.has_method("get_capacity") and resource_mgr.has_method("get_total_stock"):
				var cap: int = int(resource_mgr.get_capacity(res_id))
				var cur: int = int(resource_mgr.get_total_stock(res_id))
				space = maxi(0, cap - cur)
			if space < refund_amount:
				return {
					"can_cancel": false,
					"reason": "Dung lượng kho chứa không đủ để nhận hoàn trả 50%% tài nguyên (%s: cần %d, còn trống %d)" % [res_id, refund_amount, space],
					"insufficient_storage": true,
					"refund": planned_refund
				}

	return {"can_cancel": true, "reason": "", "insufficient_storage": false, "refund": planned_refund}

static func cancel_construction(b_data_or_id, world_data: WorldGenerator.WorldData, resource_mgr: Object = null, job_mgr: Object = null, refund_ratio: float = 0.5) -> Dictionary:
	var b_data: Dictionary = {}
	if b_data_or_id is Dictionary:
		b_data = b_data_or_id
	elif b_data_or_id is String:
		b_data = get_building_by_id(b_data_or_id, world_data)

	if b_data.is_empty():
		return {"success": false, "reason": "Công trình không tồn tại", "insufficient_storage": false, "refunded": {}}

	if b_data.get("state", "") != "under_construction":
		return {"success": false, "reason": "Chỉ có thể hủy công trình đang xây dựng", "insufficient_storage": false, "refunded": {}}

	var check := can_cancel_construction(b_data, world_data, resource_mgr, refund_ratio)
	if not check.get("can_cancel", false):
		return {
			"success": false,
			"reason": check.get("reason", "Không thể hủy thi công"),
			"insufficient_storage": check.get("insufficient_storage", false),
			"refunded": {}
		}

	var b_id: String = b_data.get("id", "")
	var origin: Vector2i = b_data.get("cell", Vector2i(-1, -1))
	var size: Vector2i = b_data.get("size", Vector2i(1, 1))
	var planned_refund: Dictionary = check.get("refund", {})

	# Execute atomic refund: credit all resources using authoritative add_resources_atomic
	var refunded: Dictionary = {}
	if not planned_refund.is_empty():
		if not is_valid_resource_manager_for_cancellation(resource_mgr):
			return {"success": false, "reason": "Yêu cầu ResourceManager hợp lệ có add_resources_atomic để hoàn trả tài nguyên", "insufficient_storage": false, "refunded": {}}
		var atomic_res: Dictionary = resource_mgr.add_resources_atomic(planned_refund)
		if not atomic_res.get("success", false):
			return {"success": false, "reason": atomic_res.get("reason", "Không thể hoàn trả toàn bộ tài nguyên vào kho chứa"), "insufficient_storage": false, "refunded": {}}
		refunded = atomic_res.get("credited", {})

	# 1. Clear occupancy only for this building's footprint
	if world_data:
		for ox in range(size.x):
			for oy in range(size.y):
				var cell := origin + Vector2i(ox, oy)
				if IsoMath.is_in_bounds(cell):
					world_data.occupancy[cell.x][cell.y] = false

	# 2. Remove jobs from job_mgr using unambiguous separator-aware prefix matching
	if job_mgr and job_mgr.has_method("remove_jobs_for_building"):
		job_mgr.remove_jobs_for_building(b_id)

	# 3. Remove from world_data
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
			return b.get("state", "") == "under_construction" or bool(b.get("is_upgrading", false))
	return false

static func is_building_upgrading(world_data: WorldGenerator.WorldData, building_id: String = "") -> bool:
	if world_data == null or building_id == "":
		return false
	for b in world_data.buildings:
		if b.get("id", "") == building_id:
			return bool(b.get("is_upgrading", false))
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

const PAUSABLE_BUILDING_TYPES: Array[String] = [
	"farm",
	"woodcutter",
	"quarry",
	"mine",
	"workshop"
]

static func is_building_pausable(b_type: String) -> bool:
	return b_type in PAUSABLE_BUILDING_TYPES

static func is_valid_resource_manager_for_demolition(resource_mgr: Object, requires_storage: bool = false) -> bool:
	if resource_mgr == null or not is_instance_valid(resource_mgr):
		return false
	if not resource_mgr.has_method("get_total_stock"):
		return false
	if not resource_mgr.has_method("get_storage_capacity") and not resource_mgr.has_method("get_capacity"):
		return false
	if not resource_mgr.has_method("add_resources_atomic"):
		return false
	if requires_storage and not resource_mgr.has_method("remove_storage_capacity"):
		return false
	return true

## Preflights demolition feasibility, calculating 50% refund and verifying storage space.
## Takes into account storage capacity reductions if demolishing a storage provider,
## as well as any extra carried cargo required to be deposited into central storage.
## Returns {"can_demolish": bool, "refund": Dictionary, "is_townhall": bool, "reason": String}.
static func can_demolish_building(b_data_or_id, world_data: WorldGenerator.WorldData, resource_mgr: Object = null, refund_ratio: float = 0.5, extra_required_resources: Dictionary = {}) -> Dictionary:
	var b_data: Dictionary = {}
	if b_data_or_id is Dictionary:
		b_data = b_data_or_id
	elif b_data_or_id is String:
		b_data = get_building_by_id(b_data_or_id, world_data)

	if b_data.is_empty():
		return {"can_demolish": false, "reason": "Công trình không tồn tại", "refund": {}, "is_townhall": false}

	var state: String = b_data.get("state", "active")
	if state == "under_construction":
		return {"can_demolish": false, "reason": "Công trình đang thi công phải sử dụng lệnh hủy thi công", "refund": {}, "is_townhall": false}
	if state == "destroyed":
		return {"can_demolish": false, "reason": "Công trình đã bị phá hủy hoàn toàn", "refund": {}, "is_townhall": false}
	if bool(b_data.get("is_upgrading", false)):
		return {"can_demolish": false, "reason": "Công trình đang nâng cấp. Vui lòng hủy nâng cấp trước khi dỡ bỏ", "refund": {}, "is_townhall": false}

	var type: String = b_data.get("type", "")
	var level: int = clampi(int(b_data.get("upgrade_level", 1)), 1, EconomyConfig.MAX_BUILDING_LEVEL)
	var is_townhall: bool = (type == "townhall")
	var bp: Dictionary = EconomyConfig.BLUEPRINTS.get(type, {})
	var cost: Dictionary = bp.get("cost", {})
	var planned_refund: Dictionary = {}
	for res_id in cost:
		var refund_amount: int = int(float(cost[res_id]) * refund_ratio)
		if refund_amount > 0:
			planned_refund[res_id] = refund_amount

	var storage_bonus: Dictionary = EconomyConfig.get_building_storage_bonus(type, level)
	var requires_rm: bool = not planned_refund.is_empty() or not storage_bonus.is_empty() or not extra_required_resources.is_empty()
	if requires_rm:
		if not is_valid_resource_manager_for_demolition(resource_mgr, not storage_bonus.is_empty()):
			return {
				"can_demolish": false,
				"reason": "Yêu cầu ResourceManager hợp lệ để hoàn trả tài nguyên và điều chỉnh kho chứa",
				"refund": planned_refund,
				"is_townhall": is_townhall
			}

	# Storage capacity preflight: check post-demolition storage capacity for refund + extra cargo!
	if resource_mgr != null:
		var total_incoming: Dictionary = {}
		for res_id in planned_refund:
			total_incoming[res_id] = total_incoming.get(res_id, 0) + int(planned_refund[res_id])
		for res_id in extra_required_resources:
			total_incoming[res_id] = total_incoming.get(res_id, 0) + int(extra_required_resources[res_id])

		for res_id in total_incoming:
			var needed_amount: int = total_incoming[res_id]
			if needed_amount <= 0:
				continue
			var space: int = 999999
			if resource_mgr.has_method("get_storage_capacity") and resource_mgr.has_method("get_total_stock"):
				var cur_cap: int = int(resource_mgr.get_storage_capacity(res_id))
				var post_cap: int = maxi(0, cur_cap - int(storage_bonus.get(res_id, 0)))
				var cur_stock: int = int(resource_mgr.get_total_stock(res_id))
				space = maxi(0, post_cap - cur_stock)
			elif resource_mgr.has_method("get_capacity") and resource_mgr.has_method("get_total_stock"):
				var cur_cap: int = int(resource_mgr.get_capacity(res_id))
				var post_cap: int = maxi(0, cur_cap - int(storage_bonus.get(res_id, 0)))
				var cur_stock: int = int(resource_mgr.get_total_stock(res_id))
				space = maxi(0, post_cap - cur_stock)
			if space < needed_amount:
				return {
					"can_demolish": false,
					"reason": "Dung lượng kho chứa không đủ để nhận hoàn trả 50%% tài nguyên sau khi dỡ bỏ (%s: cần %d, còn trống %d)" % [res_id, needed_amount, space],
					"insufficient_storage": true,
					"refund": planned_refund,
					"is_townhall": is_townhall
				}

	return {
		"can_demolish": true,
		"reason": "",
		"refund": planned_refund,
		"is_townhall": is_townhall
	}

static func demolish_building(b_data_or_id, world_data: WorldGenerator.WorldData, resource_mgr: Object = null, job_mgr: Object = null, refund_ratio: float = 0.5, extra_required_resources: Dictionary = {}) -> Dictionary:
	if world_data == null:
		return {"success": false, "reason": "Dữ liệu thế giới không hợp lệ", "refunded": {}}

	var b_data: Dictionary = {}
	if b_data_or_id is Dictionary:
		b_data = b_data_or_id
	elif b_data_or_id is String:
		b_data = get_building_by_id(b_data_or_id, world_data)

	if b_data.is_empty():
		return {"success": false, "reason": "Công trình không tồn tại", "refunded": {}}

	var check := can_demolish_building(b_data, world_data, resource_mgr, refund_ratio, extra_required_resources)
	if not check.get("can_demolish", false):
		return {
			"success": false,
			"reason": check.get("reason", "Không thể dỡ bỏ công trình"),
			"insufficient_storage": check.get("insufficient_storage", false),
			"refunded": {}
		}

	var b_id: String = b_data.get("id", "")
	var type: String = b_data.get("type", "")
	var level: int = clampi(int(b_data.get("upgrade_level", 1)), 1, EconomyConfig.MAX_BUILDING_LEVEL)
	var origin: Vector2i = b_data.get("cell", Vector2i(-1, -1))
	var size: Vector2i = b_data.get("size", Vector2i(1, 1))
	var bp: Dictionary = EconomyConfig.BLUEPRINTS.get(type, {})
	var planned_refund: Dictionary = check.get("refund", {})
	var storage_bonus: Dictionary = EconomyConfig.get_building_storage_bonus(type, level)

	# Double check resource_mgr validity if refund or storage bonus applies
	if not planned_refund.is_empty() or not storage_bonus.is_empty() or not extra_required_resources.is_empty():
		if not is_valid_resource_manager_for_demolition(resource_mgr, not storage_bonus.is_empty()):
			return {"success": false, "reason": "ResourceManager không hợp lệ", "refunded": {}}

	# 1. Execute atomic refund using authoritative add_resources_atomic
	var refunded: Dictionary = {}
	if resource_mgr != null and not planned_refund.is_empty():
		if not resource_mgr.has_method("add_resources_atomic"):
			return {"success": false, "reason": "Yêu cầu ResourceManager hỗ trợ add_resources_atomic để hoàn trả tài nguyên", "refunded": {}}
		var atomic_res: Dictionary = resource_mgr.add_resources_atomic(planned_refund)
		if not atomic_res.get("success", false):
			return {"success": false, "reason": atomic_res.get("reason", "Không thể hoàn trả toàn bộ tài nguyên vào kho chứa"), "refunded": {}}
		refunded = atomic_res.get("credited", {})

	# Deduct storage capacity if this building granted storage
	if resource_mgr != null and not storage_bonus.is_empty() and resource_mgr.has_method("remove_storage_capacity"):
		for res_id in storage_bonus:
			resource_mgr.remove_storage_capacity(res_id, int(storage_bonus[res_id]))
		b_data["storage_applied"] = false

	# 2. Clear occupancy
	if world_data.occupancy != null:
		for ox in range(size.x):
			for oy in range(size.y):
				var cell := origin + Vector2i(ox, oy)
				if IsoMath.is_in_bounds(cell):
					world_data.occupancy[cell.x][cell.y] = false

	# 3. Remove jobs
	if job_mgr and job_mgr.has_method("remove_jobs_for_building") and b_id != "":
		job_mgr.remove_jobs_for_building(b_id)

	# 4. Erase building record
	if world_data.buildings != null:
		world_data.buildings.erase(b_data)

	return {"success": true, "refunded": refunded, "building": b_data}

static func is_building_active_by_id(b_id: String, world_data: WorldGenerator.WorldData) -> bool:
	var b := get_building_by_id(b_id, world_data)
	return not b.is_empty() and b.get("state", "active") == "active"

static func is_building_paused_by_id(b_id: String, world_data: WorldGenerator.WorldData) -> bool:
	var b := get_building_by_id(b_id, world_data)
	return not b.is_empty() and b.get("state", "active") == "paused"

static func get_total_housing_capacity(world_data: WorldGenerator.WorldData) -> int:
	if world_data == null:
		return 0
	var total: int = 0
	for b in world_data.buildings:
		if b.get("state", "active") == "active":
			var b_type: String = b.get("type", "")
			if b_type == "house":
				var lvl: int = clampi(int(b.get("upgrade_level", 1)), 1, EconomyConfig.MAX_BUILDING_LEVEL)
				total += EconomyConfig.get_house_capacity(lvl)
			else:
				var bp: Dictionary = EconomyConfig.BLUEPRINTS.get(b_type, {})
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

static func get_active_barracks_count(world_data: WorldGenerator.WorldData) -> int:
	if world_data == null:
		return 0
	var count: int = 0
	for b in world_data.buildings:
		if b.get("type", "") == "barracks" and b.get("state", "active") == "active":
			count += 1
	return count

static func is_market_active(world_data: WorldGenerator.WorldData, market_id: String = "") -> bool:
	if world_data == null or world_data.buildings == null:
		return false
	for b in world_data.buildings:
		if b.get("type", "") == "market":
			var b_id: String = b.get("id", "")
			if market_id == "" or b_id == market_id:
				if b.get("state", "active") == "active":
					return true
	return false

static func get_all_active_markets(world_data: WorldGenerator.WorldData) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if world_data == null or world_data.buildings == null:
		return result
	for b in world_data.buildings:
		if b.get("type", "") == "market" and b.get("state", "active") == "active":
			result.append(b)
	# Stable deterministic selection: primary sort by coordinate (y * 64 + x), secondary by id
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca: Vector2i = a.get("cell", Vector2i(-1, -1))
		var cb: Vector2i = b.get("cell", Vector2i(-1, -1))
		var ka: int = ca.y * 64 + ca.x
		var kb: int = cb.y * 64 + cb.x
		if ka != kb:
			return ka < kb
		return String(a.get("id", "")) < String(b.get("id", ""))
	)
	return result

static func get_active_market(world_data: WorldGenerator.WorldData) -> Dictionary:
	var markets := get_all_active_markets(world_data)
	if markets.is_empty():
		return {}
	return markets[0]

static func get_town_hall(world_data: WorldGenerator.WorldData) -> Dictionary:
	if world_data == null or world_data.buildings == null:
		return {}
	# Prefer active townhall
	for b in world_data.buildings:
		if b.get("type", "") == "townhall" and b.get("state", "active") == "active":
			return b
	# Fallback to any townhall building record
	for b in world_data.buildings:
		if b.get("type", "") == "townhall":
			return b
	return {}

static func find_caravan_docking_cell(world_data: WorldGenerator.WorldData) -> Dictionary:
	if world_data == null:
		return {"cell": Vector2i(-1, -1), "is_market": false, "target_building": {}}

	# 1. Primary: Dock beside an active Market if present and accessible
	var active_mkt := get_active_market(world_data)
	if not active_mkt.is_empty():
		var m_origin: Vector2i = active_mkt.get("cell", Vector2i(-1, -1))
		var m_size: Vector2i = active_mkt.get("size", Vector2i(3, 3))
		var m_perim := find_perimeter_cells(m_origin, m_size, world_data, 1)
		if not m_perim.is_empty():
			return {"cell": m_perim[0], "is_market": true, "target_building": active_mkt}

	# 2. Fallback: Emergency docking beside the Town Hall
	var th := get_town_hall(world_data)
	if not th.is_empty():
		var th_origin: Vector2i = th.get("cell", Vector2i(-1, -1))
		var th_size: Vector2i = th.get("size", Vector2i(3, 3))
		var th_perim := find_perimeter_cells(th_origin, th_size, world_data, 1)
		if not th_perim.is_empty():
			return {"cell": th_perim[0], "is_market": false, "target_building": th}

	# 3. Emergency safe state: Return invalid cell without crashing
	return {"cell": Vector2i(-1, -1), "is_market": false, "target_building": th}


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

static func calculate_fortification_level(world_data: WorldGenerator.WorldData) -> int:
	if world_data == null or world_data.buildings == null:
		return 0
	var active_palisade_cells: Dictionary = {}
	for b in world_data.buildings:
		if b.get("type", "") == "palisade" and b.get("state", "") == "active":
			var cell = b.get("cell", Vector2i(-1, -1))
			if cell != Vector2i(-1, -1) and IsoMath.is_in_bounds(cell):
				active_palisade_cells[cell] = true

	var count: int = active_palisade_cells.size()
	if count == 0:
		return 0
	elif count < 5:
		return 1
	elif count < 10:
		return 2
	else:
		return 3

# -----------------------------------------------------------------------------
# Settlement Building Upgrades Lifecycle (Package 2I)
# -----------------------------------------------------------------------------

## Checks whether a building is eligible to start upgrading.
static func can_start_upgrade(b_data_or_id, world_data: WorldGenerator.WorldData, resource_mgr: Object = null) -> Dictionary:
	var b_data: Dictionary = {}
	if b_data_or_id is Dictionary:
		b_data = b_data_or_id
	elif b_data_or_id is String:
		b_data = get_building_by_id(b_data_or_id, world_data)

	if b_data.is_empty():
		return {"can_upgrade": false, "reason": "Công trình không tồn tại", "cost": {}, "target_level": 0, "duration": 0.0, "insufficient_resources": false}

	var state: String = b_data.get("state", "active")
	if state != "active":
		return {"can_upgrade": false, "reason": "Chỉ công trình đang hoạt động bình thường mới có thể nâng cấp", "cost": {}, "target_level": 0, "duration": 0.0, "insufficient_resources": false}

	if bool(b_data.get("is_upgrading", false)):
		return {"can_upgrade": false, "reason": "Công trình đang được nâng cấp", "cost": {}, "target_level": 0, "duration": 0.0, "insufficient_resources": false}

	var type: String = b_data.get("type", "")
	if not EconomyConfig.is_building_upgradeable(type):
		return {"can_upgrade": false, "reason": "Loại công trình này không hỗ trợ nâng cấp", "cost": {}, "target_level": 0, "duration": 0.0, "insufficient_resources": false}

	var cur_level: int = clampi(int(b_data.get("upgrade_level", 1)), 1, EconomyConfig.MAX_BUILDING_LEVEL)
	if cur_level >= EconomyConfig.MAX_BUILDING_LEVEL:
		return {"can_upgrade": false, "reason": "Công trình đã đạt cấp tối đa (Cấp %d)" % EconomyConfig.MAX_BUILDING_LEVEL, "cost": {}, "target_level": cur_level, "duration": 0.0, "insufficient_resources": false}

	var target_level: int = cur_level + 1
	var cost: Dictionary = EconomyConfig.get_upgrade_cost(type, target_level)
	var duration: float = EconomyConfig.get_upgrade_duration(type, target_level)

	if not cost.is_empty():
		if resource_mgr == null or not is_instance_valid(resource_mgr):
			return {
				"can_upgrade": false,
				"reason": "Yêu cầu ResourceManager hợp lệ để kiểm tra và khấu trừ tài nguyên nâng cấp",
				"cost": cost,
				"target_level": target_level,
				"duration": duration,
				"insufficient_resources": true
			}
		var has_deduct_capability: bool = (resource_mgr.has_method("reserve_cost") and resource_mgr.has_method("commit_cost")) or resource_mgr.has_method("deduct_resources_atomic")
		if not has_deduct_capability or not resource_mgr.has_method("can_afford"):
			return {
				"can_upgrade": false,
				"reason": "ResourceManager không hỗ trợ kiểm tra hoặc khấu trừ tài nguyên nâng cấp",
				"cost": cost,
				"target_level": target_level,
				"duration": duration,
				"insufficient_resources": true
			}
		if not resource_mgr.can_afford(cost):
			return {
				"can_upgrade": false,
				"reason": "Không đủ tài nguyên để nâng cấp lên Cấp %d" % target_level,
				"cost": cost,
				"target_level": target_level,
				"duration": duration,
				"insufficient_resources": true
			}

	return {
		"can_upgrade": true,
		"reason": "",
		"cost": cost,
		"target_level": target_level,
		"duration": duration,
		"insufficient_resources": false
	}

## Deducts cost atomically and transitions the building into the upgrading state.
static func start_upgrade(b_data_or_id, world_data: WorldGenerator.WorldData, resource_mgr: Object = null) -> Dictionary:
	var b_data: Dictionary = {}
	if b_data_or_id is Dictionary:
		b_data = b_data_or_id
	elif b_data_or_id is String:
		b_data = get_building_by_id(b_data_or_id, world_data)

	if b_data.is_empty():
		return {"success": false, "reason": "Công trình không tồn tại", "building": {}}

	var check := can_start_upgrade(b_data, world_data, resource_mgr)
	if not check.get("can_upgrade", false):
		return {
			"success": false,
			"reason": check.get("reason", "Không thể nâng cấp công trình"),
			"insufficient_resources": check.get("insufficient_resources", false),
			"building": b_data
		}

	var cost: Dictionary = check.get("cost", {})
	if not cost.is_empty():
		if resource_mgr == null or not is_instance_valid(resource_mgr):
			return {
				"success": false,
				"reason": "Yêu cầu ResourceManager hợp lệ để khấu trừ tài nguyên nâng cấp",
				"insufficient_resources": true,
				"building": b_data
			}
		if resource_mgr.has_method("reserve_cost") and resource_mgr.has_method("commit_cost"):
			var reserved: bool = resource_mgr.reserve_cost(cost)
			if not reserved:
				return {
					"success": false,
					"reason": "Không thể khóa tài nguyên nâng cấp (thiếu hụt)",
					"insufficient_resources": true,
					"building": b_data
				}
			resource_mgr.commit_cost(cost)
		elif resource_mgr.has_method("deduct_resources_atomic"):
			var d_res = resource_mgr.deduct_resources_atomic(cost)
			if not d_res.get("success", false):
				return {
					"success": false,
					"reason": d_res.get("reason", "Khấu trừ tài nguyên nâng cấp thất bại"),
					"insufficient_resources": true,
					"building": b_data
				}
		else:
			return {
				"success": false,
				"reason": "ResourceManager không hỗ trợ khấu trừ tài nguyên nâng cấp",
				"insufficient_resources": true,
				"building": b_data
			}

	var target_lvl: int = int(check.get("target_level", 2))
	var duration: float = float(check.get("duration", 2.0))

	b_data["is_upgrading"] = true
	b_data["upgrade_target_level"] = target_lvl
	b_data["upgrade_progress"] = 0.0
	b_data["upgrade_required_hours"] = duration
	b_data["upgrade_cost"] = cost.duplicate()

	return {
		"success": true,
		"reason": "",
		"building": b_data,
		"target_level": target_lvl,
		"cost": cost,
		"duration": duration
	}

## Advances upgrade progress by delta_hours. Returns completion flag.
static func advance_upgrade(b_data_or_id, delta_hours: float, world_data: WorldGenerator.WorldData = null) -> Dictionary:
	var b_data: Dictionary = {}
	if b_data_or_id is Dictionary:
		b_data = b_data_or_id
	elif b_data_or_id is String:
		b_data = get_building_by_id(b_data_or_id, world_data)

	if b_data.is_empty():
		return {"success": false, "completed": false, "progress": 0.0, "required": 0.0, "progress_delta": 0.0}

	if not bool(b_data.get("is_upgrading", false)):
		return {
			"success": false,
			"completed": false,
			"progress": float(b_data.get("upgrade_progress", 0.0)),
			"required": float(b_data.get("upgrade_required_hours", 0.0)),
			"progress_delta": 0.0
		}

	var total_hours: float = float(b_data.get("upgrade_required_hours", 2.0))
	var cur_prog: float = float(b_data.get("upgrade_progress", 0.0))

	if delta_hours <= 0.0 or is_nan(delta_hours) or is_inf(delta_hours):
		return {
			"success": false,
			"completed": cur_prog >= (total_hours - 0.001),
			"progress": cur_prog,
			"required": total_hours,
			"progress_delta": 0.0
		}

	var old_prog: float = cur_prog
	cur_prog = clampf(cur_prog + delta_hours, 0.0, total_hours)
	b_data["upgrade_progress"] = cur_prog
	var progress_made: float = maxf(0.0, cur_prog - old_prog)

	const PROGRESS_TOLERANCE: float = 0.001
	var completed: bool = cur_prog >= (total_hours - PROGRESS_TOLERANCE)
	return {
		"success": true,
		"completed": completed,
		"progress": cur_prog,
		"required": total_hours,
		"progress_delta": progress_made,
		"target_level": int(b_data.get("upgrade_target_level", 2))
	}

## Applies the newly achieved level effect and clears upgrade state. Strictly idempotent.
static func complete_building_upgrade(b_data_or_id, world_data: WorldGenerator.WorldData, resource_mgr: Object = null) -> Dictionary:
	var b_data: Dictionary = {}
	if b_data_or_id is Dictionary:
		b_data = b_data_or_id
	elif b_data_or_id is String:
		b_data = get_building_by_id(b_data_or_id, world_data)

	if b_data.is_empty():
		return {"success": false, "reason": "Công trình không tồn tại", "building": {}}

	# 1. Building type must be upgradeable
	var type: String = b_data.get("type", "")
	if not EconomyConfig.is_building_upgradeable(type):
		return {"success": false, "reason": "Loại công trình '%s' không hỗ trợ nâng cấp" % type, "building": b_data}

	# 2. Upgrade state must be active
	if not bool(b_data.get("is_upgrading", false)):
		return {"success": false, "reason": "Công trình không ở trạng thái nâng cấp", "building": b_data}

	# 3. Current level must be valid and lower than MAX_BUILDING_LEVEL
	if not b_data.has("upgrade_level"):
		return {"success": false, "reason": "Thiếu dữ liệu cấp độ công trình 'upgrade_level'", "building": b_data}
	var ul_val = b_data.get("upgrade_level")
	if not (ul_val is int or (ul_val is float and float(ul_val) == float(int(ul_val)))):
		return {"success": false, "reason": "Cấp độ công trình 'upgrade_level' phải là số nguyên", "building": b_data}
	var old_level: int = int(ul_val)
	if old_level < 1 or old_level >= EconomyConfig.MAX_BUILDING_LEVEL:
		return {"success": false, "reason": "Cấp độ công trình (%d) không hợp lệ để hoàn thành nâng cấp" % old_level, "building": b_data}

	# 4. Target level must be exactly old_level + 1 and not exceed MAX_BUILDING_LEVEL
	if not b_data.has("upgrade_target_level"):
		return {"success": false, "reason": "Thiếu dữ liệu cấp độ đích 'upgrade_target_level'", "building": b_data}
	var tgt_val = b_data.get("upgrade_target_level")
	if not (tgt_val is int or (tgt_val is float and float(tgt_val) == float(int(tgt_val)))):
		return {"success": false, "reason": "Cấp độ đích 'upgrade_target_level' phải là số nguyên", "building": b_data}
	var target_level: int = int(tgt_val)
	if target_level != old_level + 1:
		return {"success": false, "reason": "Cấp độ đích (%d) phải đúng bằng cấp độ hiện tại + 1 (%d)" % [target_level, old_level + 1], "building": b_data}
	if target_level > EconomyConfig.MAX_BUILDING_LEVEL:
		return {"success": false, "reason": "Cấp độ đích (%d) vượt quá cấp tối đa (%d)" % [target_level, EconomyConfig.MAX_BUILDING_LEVEL], "building": b_data}

	# 5. Required hours and progress verification
	if not b_data.has("upgrade_required_hours"):
		return {"success": false, "reason": "Thiếu thời gian yêu cầu nâng cấp 'upgrade_required_hours'", "building": b_data}
	var req_h_val = b_data.get("upgrade_required_hours")
	if not (req_h_val is int or req_h_val is float) or float(req_h_val) <= 0.0 or is_nan(float(req_h_val)) or is_inf(float(req_h_val)):
		return {"success": false, "reason": "Thời gian yêu cầu nâng cấp không hợp lệ", "building": b_data}
	var total_hours: float = float(req_h_val)

	var cur_prog_val = b_data.get("upgrade_progress", 0.0)
	if not (cur_prog_val is int or cur_prog_val is float) or is_nan(float(cur_prog_val)) or is_inf(float(cur_prog_val)):
		return {"success": false, "reason": "Tiến độ nâng cấp không hợp lệ", "building": b_data}
	var cur_prog: float = float(cur_prog_val)
	const PROGRESS_TOLERANCE: float = 0.001
	if cur_prog < (total_hours - PROGRESS_TOLERANCE):
		return {"success": false, "reason": "Chưa hoàn thành thời gian thi công nâng cấp (%f / %f)" % [cur_prog, total_hours], "building": b_data}

	# 6. If storehouse, apply capacity delta (fail closed before mutating state if resource_mgr is unavailable)
	if type == "storehouse":
		if resource_mgr == null or not is_instance_valid(resource_mgr) or not resource_mgr.has_method("add_storage_capacity"):
			return {
				"success": false,
				"reason": "Yêu cầu ResourceManager hợp lệ có add_storage_capacity để hoàn thành nâng cấp Kho chứa",
				"building": b_data
			}
		var delta: Dictionary = EconomyConfig.get_storehouse_bonus_delta(old_level, target_level)
		for res_id in delta:
			resource_mgr.add_storage_capacity(res_id, int(delta[res_id]))

	# 7. Apply new level and clear upgrade status
	b_data["upgrade_level"] = target_level
	b_data["is_upgrading"] = false
	b_data.erase("upgrade_target_level")
	b_data.erase("upgrade_progress")
	b_data.erase("upgrade_required_hours")
	b_data.erase("upgrade_cost")

	return {
		"success": true,
		"reason": "",
		"old_level": old_level,
		"new_level": target_level,
		"building": b_data
	}

## Preflights upgrade cancellation feasibility, checking 50% refund storage capacity.
static func can_cancel_upgrade(b_data_or_id, world_data: WorldGenerator.WorldData, resource_mgr: Object = null, refund_ratio: float = 0.5) -> Dictionary:
	var b_data: Dictionary = {}
	if b_data_or_id is Dictionary:
		b_data = b_data_or_id
	elif b_data_or_id is String:
		b_data = get_building_by_id(b_data_or_id, world_data)

	if b_data.is_empty():
		return {"can_cancel": false, "reason": "Công trình không tồn tại", "insufficient_storage": false, "refund": {}}

	if not bool(b_data.get("is_upgrading", false)):
		return {"can_cancel": false, "reason": "Công trình không ở trạng thái nâng cấp", "insufficient_storage": false, "refund": {}}

	var type: String = b_data.get("type", "")
	var target_level: int = int(b_data.get("upgrade_target_level", 2))
	var cost: Dictionary = b_data.get("upgrade_cost", {})
	if cost.is_empty():
		cost = EconomyConfig.get_upgrade_cost(type, target_level)

	var planned_refund: Dictionary = {}
	for res_id in cost:
		var refund_amount: int = int(floor(float(cost[res_id]) * refund_ratio))
		if refund_amount > 0:
			planned_refund[res_id] = refund_amount

	if not planned_refund.is_empty():
		if not is_valid_resource_manager_for_cancellation(resource_mgr):
			return {
				"can_cancel": false,
				"reason": "Yêu cầu ResourceManager hợp lệ có add_resources_atomic để hoàn trả tài nguyên",
				"insufficient_storage": false,
				"refund": planned_refund
			}
		for res_id in planned_refund:
			var refund_amount: int = planned_refund[res_id]
			var space: int = 999999
			if resource_mgr.has_method("get_storage_capacity") and resource_mgr.has_method("get_total_stock"):
				var cap: int = int(resource_mgr.get_storage_capacity(res_id))
				var cur: int = int(resource_mgr.get_total_stock(res_id))
				space = maxi(0, cap - cur)
			elif resource_mgr.has_method("get_capacity") and resource_mgr.has_method("get_total_stock"):
				var cap: int = int(resource_mgr.get_capacity(res_id))
				var cur: int = int(resource_mgr.get_total_stock(res_id))
				space = maxi(0, cap - cur)
			if space < refund_amount:
				return {
					"can_cancel": false,
					"reason": "Dung lượng kho chứa không đủ để nhận hoàn trả 50%% tài nguyên khi hủy nâng cấp (%s: cần %d, còn trống %d)" % [res_id, refund_amount, space],
					"insufficient_storage": true,
					"refund": planned_refund
				}

	return {"can_cancel": true, "reason": "", "insufficient_storage": false, "refund": planned_refund}

## Cancels an in-progress upgrade, returning 50% refund and clearing builder jobs.
static func cancel_upgrade(b_data_or_id, world_data: WorldGenerator.WorldData, resource_mgr: Object = null, job_mgr: Object = null, refund_ratio: float = 0.5) -> Dictionary:
	var b_data: Dictionary = {}
	if b_data_or_id is Dictionary:
		b_data = b_data_or_id
	elif b_data_or_id is String:
		b_data = get_building_by_id(b_data_or_id, world_data)

	if b_data.is_empty():
		return {"success": false, "reason": "Công trình không tồn tại", "insufficient_storage": false, "refunded": {}}

	if not bool(b_data.get("is_upgrading", false)):
		return {"success": false, "reason": "Công trình không ở trạng thái nâng cấp", "insufficient_storage": false, "refunded": {}}

	var check := can_cancel_upgrade(b_data, world_data, resource_mgr, refund_ratio)
	if not check.get("can_cancel", false):
		return {
			"success": false,
			"reason": check.get("reason", "Không thể hủy nâng cấp"),
			"insufficient_storage": check.get("insufficient_storage", false),
			"refunded": {}
		}

	var planned_refund: Dictionary = check.get("refund", {})
	var refunded: Dictionary = {}
	if not planned_refund.is_empty():
		if resource_mgr == null or not is_instance_valid(resource_mgr) or not resource_mgr.has_method("add_resources_atomic"):
			return {"success": false, "reason": "Yêu cầu ResourceManager hợp lệ có add_resources_atomic để hoàn trả tài nguyên", "refunded": {}}
		var atomic_res: Dictionary = resource_mgr.add_resources_atomic(planned_refund)
		if not atomic_res.get("success", false):
			return {"success": false, "reason": atomic_res.get("reason", "Không thể hoàn trả tài nguyên nâng cấp"), "refunded": {}}
		refunded = atomic_res.get("credited", {})

	# Remove upgrade builder jobs
	var b_id: String = b_data.get("id", "")
	if job_mgr != null and job_mgr.has_method("remove_jobs_for_building") and b_id != "":
		job_mgr.remove_jobs_for_building(b_id)

	# Reset upgrade fields
	b_data["is_upgrading"] = false
	b_data.erase("upgrade_target_level")
	b_data.erase("upgrade_progress")
	b_data.erase("upgrade_required_hours")
	b_data.erase("upgrade_cost")

	return {"success": true, "reason": "", "refunded": refunded, "building": b_data}

