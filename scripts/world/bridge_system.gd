class_name BridgeSystem
extends RefCounted
## Bridge Geometry, Placement Validation, Cost Scaling & Walkability Registry (Phase 4).

static func is_dry_walkable_land(cell: Vector2i, world_data: WorldGenerator.WorldData) -> bool:
	if world_data == null or not IsoMath.is_in_bounds(cell, world_data.map_width, world_data.map_height):
		return false
	var t_type: int = world_data.terrain[cell.x][cell.y]
	if t_type == WorldGenerator.TerrainType.WATER:
		return false
	if world_data.generator_version == WorldGenerator.BATCH03_GENERATOR_VERSION and t_type == WorldGenerator.TerrainType.MOUNTAINS:
		return false
	if world_data.occupancy[cell.x][cell.y]:
		return false
	return true

static func is_cell_owned(cell: Vector2i, world_data: WorldGenerator.WorldData) -> bool:
	if world_data == null or not IsoMath.is_in_bounds(cell, world_data.map_width, world_data.map_height):
		return false
	if world_data.owned_cells.size() != world_data.map_width:
		return true
	return bool(world_data.owned_cells[cell.x][cell.y])

static func get_deck_cells(b_data: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var origin: Vector2i = b_data.get("cell", Vector2i.ZERO)
	var size: Vector2i = b_data.get("size", Vector2i.ONE)
	for ox in range(size.x):
		for oy in range(size.y):
			cells.append(origin + Vector2i(ox, oy))
	return cells

static func _is_cell_claimed_by_bridge(cell: Vector2i, world_data: WorldGenerator.WorldData) -> bool:
	if world_data == null:
		return false
	for b in world_data.buildings:
		if not (b is Dictionary):
			continue
		if str(b.get("type", "")) != "bridge":
			continue
		if str(b.get("state", "active")) == "destroyed":
			continue
		var origin: Vector2i = b.get("cell", Vector2i.ZERO)
		var size: Vector2i = b.get("size", Vector2i.ONE)
		if cell.x >= origin.x and cell.x < origin.x + size.x and cell.y >= origin.y and cell.y < origin.y + size.y:
			return true
	return false

static func _compute_access_cells(start_bank: Vector2i, axis: String, width: int, width_offset: int, world_data: WorldGenerator.WorldData) -> Array[Vector2i]:
	var access: Array[Vector2i] = []
	if world_data == null:
		return access
	var perp: Vector2i = Vector2i(0, 1) if axis == "x" else Vector2i(1, 0)
	var seen: Dictionary = {}
	for w_idx in range(width):
		var bank_cell := start_bank + perp * (width_offset + w_idx)
		if is_dry_walkable_land(bank_cell, world_data) and is_cell_owned(bank_cell, world_data) and not seen.has(bank_cell):
			seen[bank_cell] = true
			access.append(bank_cell)
	# Also include dry owned neighbors adjacent to the start bank lanes as fallback access positions
	for w_idx in range(width):
		var bank_cell := start_bank + perp * (width_offset + w_idx)
		for n in IsoMath.get_cardinal_neighbors(bank_cell):
			if is_dry_walkable_land(n, world_data) and is_cell_owned(n, world_data) and not seen.has(n):
				seen[n] = true
				access.append(n)
	return access

static func get_owned_access_cells(b_data: Dictionary, world_data: WorldGenerator.WorldData) -> Array[Vector2i]:
	var start_bank: Vector2i = b_data.get("start_bank", b_data.get("cell", Vector2i.ZERO))
	var axis: String = str(b_data.get("axis", "x"))
	var width: int = int(b_data.get("width", 1))
	var width_offset: int = int(b_data.get("width_offset", 0))
	var access := _compute_access_cells(start_bank, axis, width, width_offset, world_data)
	if access.is_empty():
		var end_bank: Vector2i = b_data.get("end_bank", start_bank)
		access = _compute_access_cells(end_bank, axis, width, width_offset, world_data)
	return access

static func validate_bridge_placement(
	start_bank: Vector2i,
	end_bank: Vector2i,
	width: int,
	world_data: WorldGenerator.WorldData,
	fog_of_war: FogOfWar = null,
	resource_mgr: Object = null,
	width_offset: int = 0
) -> Dictionary:
	var base_fail := {
		"valid": false,
		"reason": "",
		"axis": "x",
		"length": 0,
		"width": width,
		"width_offset": width_offset,
		"deck_origin": Vector2i.ZERO,
		"deck_size": Vector2i.ZERO,
		"deck_cells": [],
		"start_bank": start_bank,
		"end_bank": end_bank,
		"cost": {},
		"construction_hours": 0.0
	}

	if world_data == null:
		base_fail["reason"] = "Dữ liệu thế giới không khả dụng"
		return base_fail

	if width < EconomyConfig.BRIDGE_MIN_WIDTH or width > EconomyConfig.BRIDGE_MAX_WIDTH:
		base_fail["reason"] = "Chiều rộng cầu không hợp lệ (chỉ hỗ trợ 1, 2 hoặc 3)"
		return base_fail

	if not IsoMath.is_in_bounds(start_bank, world_data.map_width, world_data.map_height) or not IsoMath.is_in_bounds(end_bank, world_data.map_width, world_data.map_height):
		base_fail["reason"] = "Vị trí cầu nằm ngoài ranh giới bản đồ"
		return base_fail

	if start_bank == end_bank:
		base_fail["reason"] = "Điểm đầu và điểm cuối không thể trùng nhau"
		return base_fail

	var axis: String = ""
	var dir := Vector2i.ZERO
	var perp := Vector2i.ZERO
	var span_dist: int = 0
	if start_bank.y == end_bank.y:
		axis = "x"
		dir = Vector2i(1 if end_bank.x > start_bank.x else -1, 0)
		perp = Vector2i(0, 1)
		span_dist = absi(end_bank.x - start_bank.x)
	elif start_bank.x == end_bank.x:
		axis = "y"
		dir = Vector2i(0, 1 if end_bank.y > start_bank.y else -1)
		perp = Vector2i(1, 0)
		span_dist = absi(end_bank.y - start_bank.y)
	else:
		base_fail["reason"] = "Cầu phải thẳng hàng theo trục lưới X hoặc Y"
		return base_fail

	var length: int = span_dist - 1
	if length < 1:
		base_fail["reason"] = "Cần ít nhất 1 ô mặt nước giữa hai bờ để bắc cầu"
		return base_fail

	var cost: Dictionary = EconomyConfig.calculate_bridge_cost(length, width)
	var hours: float = EconomyConfig.calculate_bridge_construction_hours(length, width)

	# Compute deterministic bounding box for preview even if terrain fails below
	var min_x: int = 999999
	var max_x: int = -999999
	var min_y: int = 999999
	var max_y: int = -999999
	var deck_cells: Array[Vector2i] = []
	for w_idx in range(width):
		var lane_shift: Vector2i = perp * (width_offset + w_idx)
		for step in range(1, length + 1):
			var c: Vector2i = start_bank + lane_shift + dir * step
			deck_cells.append(c)
			min_x = mini(min_x, c.x)
			max_x = maxi(max_x, c.x)
			min_y = mini(min_y, c.y)
			max_y = maxi(max_y, c.y)

	var deck_origin := Vector2i(min_x, min_y)
	var deck_size := Vector2i(max_x - min_x + 1, max_y - min_y + 1)

	var result := {
		"valid": false,
		"reason": "",
		"axis": axis,
		"length": length,
		"width": width,
		"width_offset": width_offset,
		"deck_origin": deck_origin,
		"deck_size": deck_size,
		"deck_cells": deck_cells,
		"start_bank": start_bank,
		"end_bank": end_bank,
		"cost": cost,
		"construction_hours": hours
	}

	# Validate start bank & end bank for every lane
	for w_idx in range(width):
		var lane_shift: Vector2i = perp * (width_offset + w_idx)
		var s_lane: Vector2i = start_bank + lane_shift
		var e_lane: Vector2i = end_bank + lane_shift

		if not IsoMath.is_in_bounds(s_lane, world_data.map_width, world_data.map_height) or not IsoMath.is_in_bounds(e_lane, world_data.map_width, world_data.map_height):
			result["reason"] = "Bề rộng cầu vượt ngoài ranh giới bản đồ"
			return result

		if not is_cell_owned(s_lane, world_data):
			result["reason"] = "Bờ xuất phát phải nằm trong lãnh thổ vương quốc"
			return result

		if not is_dry_walkable_land(s_lane, world_data):
			result["reason"] = "Bờ xuất phát phải là đất khô bằng phẳng, không bị chiếm dụng"
			return result

		if fog_of_war != null and fog_of_war.is_unexplored(e_lane):
			result["reason"] = "Bờ bên kia chưa được khám phá (cần trinh sát trước)"
			return result

		if not is_dry_walkable_land(e_lane, world_data):
			result["reason"] = "Bờ bên kia phải là đất khô trống, không bị chiếm dụng"
			return result

	# Validate continuous water corridor for every deck cell
	for c in deck_cells:
		if not IsoMath.is_in_bounds(c, world_data.map_width, world_data.map_height):
			result["reason"] = "Mặt cầu vượt ngoài ranh giới bản đồ"
			return result
		if world_data.terrain[c.x][c.y] != WorldGenerator.TerrainType.WATER:
			result["reason"] = "Toàn bộ nhịp cầu phải bắc qua mặt nước liên tục"
			return result
		if _is_cell_claimed_by_bridge(c, world_data):
			result["reason"] = "Vị trí mặt nước đã có cầu khác chiếm dụng"
			return result

	# Verify owned-side builder access
	var access := _compute_access_cells(start_bank, axis, width, width_offset, world_data)
	if access.is_empty():
		result["reason"] = "Không có vị trí tiếp cận hợp lệ bên bờ xuất phát cho thợ xây"
		return result

	# Check resource affordability
	if resource_mgr != null and resource_mgr.has_method("can_afford") and not bool(resource_mgr.can_afford(cost)):
		result["reason"] = "Không đủ tài nguyên (cần %d Gỗ, %d Đá)" % [int(cost.get(EconomyConfig.RES_WOOD, 0)), int(cost.get(EconomyConfig.RES_STONE, 0))]
		return result

	result["valid"] = true
	return result

static func place_bridge(
	start_bank: Vector2i,
	end_bank: Vector2i,
	width: int,
	world_data: WorldGenerator.WorldData,
	fog_of_war: FogOfWar = null,
	resource_mgr: Object = null,
	initial_state: String = "under_construction",
	width_offset: int = 0
) -> Dictionary:
	var check := validate_bridge_placement(start_bank, end_bank, width, world_data, fog_of_war, resource_mgr, width_offset)
	if not bool(check.get("valid", false)):
		return {"success": false, "reason": str(check.get("reason", "Vị trí đặt cầu không hợp lệ"))}

	var cost: Dictionary = check["cost"]
	if resource_mgr != null and not cost.is_empty():
		if not resource_mgr.has_method("reserve_cost") or not resource_mgr.has_method("commit_cost"):
			return {"success": false, "reason": "Hệ thống tài nguyên không khả dụng"}
		if not bool(resource_mgr.reserve_cost(cost)):
			return {"success": false, "reason": "Không thể khóa tài nguyên xây cầu"}
		resource_mgr.commit_cost(cost)

	var deck_origin: Vector2i = check["deck_origin"]
	var deck_size: Vector2i = check["deck_size"]
	var axis: String = str(check["axis"])
	var length: int = int(check["length"])
	var hours: float = float(check["construction_hours"])
	var is_active: bool = (initial_state == "active")

	var base_id := "bld_bridge_%d_%d_%s" % [deck_origin.x, deck_origin.y, axis]
	var b_id := base_id
	var suffix := 2
	while not BuildingSystem.get_building_by_id(b_id, world_data).is_empty():
		b_id = "%s_%d" % [base_id, suffix]
		suffix += 1

	var b_data := {
		"id": b_id,
		"type": "bridge",
		"cell": deck_origin,
		"size": deck_size,
		"axis": axis,
		"start_bank": start_bank,
		"end_bank": end_bank,
		"length": length,
		"width": width,
		"width_offset": width_offset,
		"cost": cost.duplicate(),
		"state": initial_state,
		"health": 100,
		"max_health": 100,
		"upgrade_level": 1,
		"construction_progress": hours if is_active else 0.0,
		"construction_hours": hours
	}
	world_data.buildings.append(b_data)
	if is_active:
		rebuild_bridge_walkability(world_data)

	return {"success": true, "building": b_data}

static func rebuild_bridge_walkability(world_data: WorldGenerator.WorldData) -> void:
	if world_data == null:
		return
	world_data.bridge_walkable_cells.clear()
	for b in world_data.buildings:
		if not (b is Dictionary):
			continue
		if str(b.get("type", "")) != "bridge":
			continue
		if str(b.get("state", "active")) != "active":
			continue
		var b_id: String = str(b.get("id", ""))
		for c in get_deck_cells(b):
			if IsoMath.is_in_bounds(c, world_data.map_width, world_data.map_height) and world_data.terrain[c.x][c.y] == WorldGenerator.TerrainType.WATER:
				world_data.bridge_walkable_cells[c] = b_id

static func has_living_units_on_bridge(b_data: Dictionary, citizen_list: Array, tactical_military_mgr: Object = null, enemy_military_mgr: Object = null) -> bool:
	if b_data.is_empty():
		return false
	var deck_set: Dictionary = {}
	for c in get_deck_cells(b_data):
		deck_set[c] = true

	for cit in citizen_list:
		if cit == null or not is_instance_valid(cit):
			continue
		if cit.get("is_inside_home") == true:
			continue
		var c_cell: Variant = cit.get("current_cell")
		if c_cell is Vector2i and deck_set.has(c_cell):
			return true
		if cit is Node2D:
			var pos_cell := IsoMath.local_to_map((cit as Node2D).position)
			if deck_set.has(pos_cell):
				return true

	if tactical_military_mgr != null and tactical_military_mgr.has_method("get_all_units"):
		for u in tactical_military_mgr.call("get_all_units"):
			if u == null or not is_instance_valid(u):
				continue
			if u.get("hp") != null and int(u.get("hp")) <= 0:
				continue
			var u_cell: Variant = u.get("current_cell")
			if u_cell is Vector2i and deck_set.has(u_cell):
				return true
			if u is Node2D and deck_set.has(IsoMath.local_to_map((u as Node2D).position)):
				return true

	if enemy_military_mgr != null and enemy_military_mgr.get("units") is Dictionary:
		for uid in enemy_military_mgr.units:
			var eu = enemy_military_mgr.units[uid]
			if eu == null or not is_instance_valid(eu):
				continue
			if eu.get("hp") != null and int(eu.get("hp")) <= 0:
				continue
			var e_cell: Variant = eu.get("current_cell")
			if e_cell is Vector2i and deck_set.has(e_cell):
				return true
			if eu is Node2D and deck_set.has(IsoMath.local_to_map((eu as Node2D).position)):
				return true

	return false
