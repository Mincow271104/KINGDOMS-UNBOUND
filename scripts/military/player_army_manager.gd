class_name PlayerArmyManager
extends RefCounted
## Player Army Manager (Package 1L & 1M)
## Authoritative manager for player-recruited abstract army units,
## Barracks capacity calculations, atomic recruitment transactions,
## daily food upkeep ticks, supply states, combat morale, casualty reductions,
## and authoritative logical grid movement / garrison deployment.

const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")

enum MovementState {
	GARRISONED = 0,
	MARCHING = 1,
	IDLE_AT_FIELD = 2
}

const CELL_STEP_DURATION: float = 0.5 # Seconds per grid cell at 1x simulation speed

signal army_changed(current_count: int, capacity: int)
signal supply_status_changed(is_supplied: bool)
signal upkeep_processed(day: int, cost_paid: int, success: bool)
signal recruitment_completed(count: int, cost: Dictionary)
signal movement_state_changed(state: int, current_cell: Vector2i, destination_cell: Vector2i)
signal army_moved(new_cell: Vector2i)
signal equipment_tier_changed(new_tier: int, multiplier: float)
signal garrison_changed(outpost_id: String, current_count: int, capacity: int)
signal reinforcement_dispatched(dispatch_id: String, outpost_id: String, count: int)
signal reinforcement_arrived(dispatch_id: String, outpost_id: String, count: int)

var world_view: Node = null
var soldier_count: int = 0
var equipment_tier: int = 1
var _is_upgrading_equipment: bool = false
var is_supplied: bool = true
var last_upkeep_day: int = -1

# Package 3A: Outpost Garrisoning & Reinforcements
var garrisons: Dictionary = {}
var active_reinforcements: Array[Dictionary] = []
var next_reinforce_id: int = 1
var next_soldier_id: int = 1
var _test_registered_outposts: Dictionary = {}
var _custom_field_siege_mgr: Object = null

const RALLY_PERIMETER_DISTANCE: int = 5
var tactical_military_mgr: Object = null

# Authoritative Movement State (Package 1M)
var current_cell: Vector2i = Vector2i(32, 33)
var rally_cell: Vector2i = Vector2i(32, 33)
var destination_cell: Vector2i = Vector2i(32, 33)
var current_path: Array[Vector2i] = []
var movement_state: int = MovementState.GARRISONED
var step_accumulator: float = 0.0
var is_deserializing: bool = false

# Dependency injection hooks for headless/unit testing
var _custom_resource_mgr: Object = null
var _custom_world_data: WorldGenerator.WorldData = null
var _custom_event_mgr: Object = null
var _custom_nav: GridNavigation = null
var _custom_time_mgr: Object = null

func _init(wv: Node = null) -> void:
	world_view = wv
	soldier_count = 0
	equipment_tier = 1
	is_supplied = true
	last_upkeep_day = -1
	rally_cell = Vector2i(32, 33)
	current_cell = rally_cell
	destination_cell = rally_cell
	movement_state = MovementState.GARRISONED
	current_path = []
	step_accumulator = 0.0
	tactical_military_mgr = null
	garrisons = {}
	active_reinforcements = []
	next_reinforce_id = 1
	next_soldier_id = 1
	_test_registered_outposts = {}
	_custom_field_siege_mgr = null
	if is_instance_valid(world_view) and world_view.get("world_data") != null:
		rally_cell = get_default_rally_cell()
		current_cell = rally_cell
		destination_cell = rally_cell

func set_tactical_military_manager(mgr: Object) -> void:
	if tactical_military_mgr == mgr:
		sync_state_from_tactical()
		return

	var old_mgr: Object = tactical_military_mgr
	tactical_military_mgr = null

	if old_mgr != null and is_instance_valid(old_mgr):
		_unbind_tactical_military_manager(old_mgr)
		if old_mgr.get("player_army_mgr") == self:
			if old_mgr.has_method("set_player_army_manager"):
				old_mgr.call("set_player_army_manager", null)
			else:
				old_mgr.set("player_army_mgr", null)
		if old_mgr.has_method("clear_all_units"):
			old_mgr.call("clear_all_units")

	tactical_military_mgr = mgr
	if tactical_military_mgr != null and is_instance_valid(tactical_military_mgr):
		_bind_tactical_military_manager(tactical_military_mgr)
		if tactical_military_mgr.get("player_army_mgr") != self:
			if tactical_military_mgr.has_method("set_player_army_manager"):
				tactical_military_mgr.call("set_player_army_manager", self)
			else:
				tactical_military_mgr.set("player_army_mgr", self)
		if tactical_military_mgr.has_method("sync_with_player_army"):
			tactical_military_mgr.call("sync_with_player_army")

	sync_state_from_tactical()

func _bind_tactical_military_manager(mgr: Object) -> void:
	if mgr == null or not is_instance_valid(mgr):
		return
	if mgr.has_signal("tactical_state_updated"):
		if not mgr.tactical_state_updated.is_connected(sync_state_from_tactical):
			mgr.tactical_state_updated.connect(sync_state_from_tactical)
	if mgr.has_method("_on_army_changed"):
		if not army_changed.is_connected(mgr._on_army_changed):
			army_changed.connect(mgr._on_army_changed)

func _unbind_tactical_military_manager(mgr: Object) -> void:
	if mgr == null or not is_instance_valid(mgr):
		return
	if mgr.has_signal("tactical_state_updated"):
		if mgr.tactical_state_updated.is_connected(sync_state_from_tactical):
			mgr.tactical_state_updated.disconnect(sync_state_from_tactical)
	if mgr.has_method("_on_army_changed"):
		if army_changed.is_connected(mgr._on_army_changed):
			army_changed.disconnect(mgr._on_army_changed)

# -----------------------------------------------------------------------------
# Dependency Accessors
# -----------------------------------------------------------------------------

func get_resource_manager() -> Object:
	if _custom_resource_mgr != null:
		return _custom_resource_mgr
	if Engine.has_singleton("ResourceManager"):
		return Engine.get_singleton("ResourceManager")
	if is_instance_valid(world_view) and world_view.is_inside_tree():
		return world_view.get_node_or_null("/root/ResourceManager")
	return null

func get_world_data() -> WorldGenerator.WorldData:
	if _custom_world_data != null:
		return _custom_world_data
	if is_instance_valid(world_view):
		return world_view.get("world_data")
	return null

func get_event_manager() -> Object:
	if _custom_event_mgr != null:
		return _custom_event_mgr
	if Engine.has_singleton("EventManager"):
		return Engine.get_singleton("EventManager")
	if is_instance_valid(world_view) and world_view.is_inside_tree():
		return world_view.get_node_or_null("/root/EventManager")
	return null

func set_custom_resource_manager(rm: Object) -> void:
	_custom_resource_mgr = rm

func set_custom_world_data(wd: WorldGenerator.WorldData) -> void:
	_custom_world_data = wd

func set_custom_event_manager(em: Object) -> void:
	_custom_event_mgr = em

func get_nav() -> GridNavigation:
	if _custom_nav != null:
		return _custom_nav
	if is_instance_valid(world_view) and world_view.get("nav") != null:
		return world_view.get("nav")
	var wd = get_world_data()
	if wd != null:
		return GridNavigation.new(wd)
	return null

func set_custom_nav(p_nav: GridNavigation) -> void:
	_custom_nav = p_nav

func get_time_manager() -> Object:
	if _custom_time_mgr != null:
		return _custom_time_mgr
	if is_instance_valid(world_view) and world_view.is_inside_tree() and world_view.has_node("/root/TimeManager"):
		return world_view.get_node("/root/TimeManager")
	if Engine.has_singleton("TimeManager"):
		return Engine.get_singleton("TimeManager")
	return null

func set_custom_time_manager(tm: Object) -> void:
	_custom_time_mgr = tm

# -----------------------------------------------------------------------------
# Army Capacity, Queries & Balance Values
# -----------------------------------------------------------------------------

func get_army_count() -> int:
	return soldier_count

func get_army_capacity() -> int:
	var wd = get_world_data()
	if wd == null:
		return 0
	var active_barracks_count: int = BuildingSystemScript.get_active_barracks_count(wd)
	return active_barracks_count * EconomyConfigScript.ARMY_CAPACITY_PER_BARRACKS

func get_remaining_capacity() -> int:
	return maxi(0, get_army_capacity() - get_total_soldier_count())

func notify_capacity_changed() -> void:
	army_changed.emit(soldier_count, get_army_capacity())

func get_recruitment_cost(count: int = 1) -> Dictionary:
	if count <= 0:
		return {}
	var result: Dictionary = {}
	for res_id in EconomyConfigScript.ARMY_RECRUIT_COST:
		result[res_id] = EconomyConfigScript.ARMY_RECRUIT_COST[res_id] * count
	return result

func get_combat_morale() -> float:
	return EconomyConfigScript.ARMY_MORALE_SUPPLIED if is_supplied else EconomyConfigScript.ARMY_MORALE_UNSUPPLIED

# -----------------------------------------------------------------------------
# Equipment Tier Progression (Package 2J)
# -----------------------------------------------------------------------------

func get_equipment_tier() -> int:
	return equipment_tier

func get_equipment_combat_multiplier() -> float:
	return EconomyConfigScript.get_army_equipment_multiplier(equipment_tier)

func get_equipment_tier_name() -> String:
	return EconomyConfigScript.get_army_equipment_name(equipment_tier)

func get_equipment_upgrade_cost(target_tier: int = -1) -> Dictionary:
	var target: int = target_tier
	if target < 0:
		target = equipment_tier + 1
	return EconomyConfigScript.get_army_equipment_cost(target)

func is_upgrading_equipment() -> bool:
	return _is_upgrading_equipment

func can_upgrade_equipment(target_tier: int = -1) -> Dictionary:
	if _is_upgrading_equipment:
		return {
			"can_upgrade": false,
			"reason": "Giao dịch nâng cấp trang bị đang được xử lý"
		}

	var target: int = target_tier
	if target < 0:
		target = equipment_tier + 1

	if equipment_tier >= EconomyConfigScript.MAX_ARMY_EQUIPMENT_TIER:
		return {
			"can_upgrade": false,
			"reason": "Trang bị quân đội đã đạt cấp tối đa (Cấp %d)" % EconomyConfigScript.MAX_ARMY_EQUIPMENT_TIER
		}

	if target != equipment_tier + 1:
		return {
			"can_upgrade": false,
			"reason": "Chỉ có thể nâng cấp tuần tự lên cấp kế tiếp (Cấp %d)" % (equipment_tier + 1)
		}

	if target > EconomyConfigScript.MAX_ARMY_EQUIPMENT_TIER or target <= EconomyConfigScript.MIN_ARMY_EQUIPMENT_TIER:
		return {
			"can_upgrade": false,
			"reason": "Cấp trang bị mục tiêu không hợp lệ (%d)" % target
		}

	if soldier_count <= 0:
		return {
			"can_upgrade": false,
			"reason": "Cần ít nhất một binh sĩ để nâng cấp trang bị quân đội"
		}

	var wd = get_world_data()
	if wd == null:
		return {
			"can_upgrade": false,
			"reason": "Không tìm thấy dữ liệu bản đồ"
		}

	var active_barracks_count: int = BuildingSystemScript.get_active_barracks_count(wd)
	if active_barracks_count <= 0:
		return {
			"can_upgrade": false,
			"reason": "Cần ít nhất một Doanh Trại đang hoạt động để nâng cấp trang bị"
		}

	if movement_state == MovementState.MARCHING or not current_path.is_empty():
		return {
			"can_upgrade": false,
			"reason": "Quân đội đang hành quân, chỉ có thể nâng cấp khi đóng quân tại căn cứ"
		}

	if current_cell != rally_cell:
		return {
			"can_upgrade": false,
			"reason": "Quân đội đang dã chiến ngoài thành, chỉ có thể nâng cấp khi đóng quân tại căn cứ"
		}

	if movement_state != MovementState.GARRISONED:
		return {
			"can_upgrade": false,
			"reason": "Quân đội phải ở trạng thái đóng quân tại căn cứ để nâng cấp"
		}

	var cost: Dictionary = get_equipment_upgrade_cost(target)
	if cost.is_empty():
		return {
			"can_upgrade": false,
			"reason": "Không tìm thấy chi phí nâng cấp cho cấp %d" % target
		}

	var rm = get_resource_manager()
	if rm == null:
		return {
			"can_upgrade": false,
			"reason": "Không tìm thấy kho tài nguyên"
		}

	if not rm.has_method("can_afford") or not rm.can_afford(cost):
		return {
			"can_upgrade": false,
			"reason": "Không đủ tài nguyên nâng cấp trang bị (Yêu cầu: %d Gỗ, %d Kim loại)" % [cost.get(EconomyConfigScript.RES_WOOD, 0), cost.get(EconomyConfigScript.RES_METAL, 0)]
		}

	return {
		"can_upgrade": true,
		"reason": "",
		"target_tier": target,
		"cost": cost
	}

func upgrade_equipment(target_tier: int = -1) -> Dictionary:
	if _is_upgrading_equipment:
		return {
			"success": false,
			"reason": "Giao dịch nâng cấp trang bị đang được xử lý",
			"tier": equipment_tier,
			"multiplier": get_equipment_combat_multiplier()
		}

	var check: Dictionary = can_upgrade_equipment(target_tier)
	if not check.get("can_upgrade", false):
		return {
			"success": false,
			"reason": check.get("reason", "Không thể nâng cấp trang bị"),
			"tier": equipment_tier,
			"multiplier": get_equipment_combat_multiplier()
		}

	var cost: Dictionary = check.get("cost", {})
	var target: int = int(check.get("target_tier", equipment_tier + 1))
	var rm = get_resource_manager()
	if rm == null or not (rm.has_method("reserve_cost") and rm.has_method("commit_cost")):
		return {
			"success": false,
			"reason": "Giao dịch tài nguyên không khả dụng",
			"tier": equipment_tier,
			"multiplier": get_equipment_combat_multiplier()
		}

	_is_upgrading_equipment = true
	var res: Dictionary = _execute_upgrade_transaction(rm, cost, target)
	_is_upgrading_equipment = false
	return res

func _execute_upgrade_transaction(rm: Object, cost: Dictionary, target: int) -> Dictionary:
	# Atomic transaction: reserve, then commit
	var reserved: bool = rm.call("reserve_cost", cost)
	if not reserved:
		return {
			"success": false,
			"reason": "Không thể dự trữ tài nguyên nâng cấp",
			"tier": equipment_tier,
			"multiplier": get_equipment_combat_multiplier()
		}

	rm.call("commit_cost", cost)

	equipment_tier = target
	var new_mult: float = get_equipment_combat_multiplier()
	equipment_tier_changed.emit(equipment_tier, new_mult)

	var em = get_event_manager()
	if em != null and em.has_method("log_event"):
		em.call("log_event", "Trang bị quân đội đã được nâng cấp lên %s (x%.2f sức chiến đấu)." % [get_equipment_tier_name(), new_mult])

	return {
		"success": true,
		"tier": equipment_tier,
		"multiplier": new_mult,
		"cost": cost
	}


# -----------------------------------------------------------------------------
# Recruitment Transaction
# -----------------------------------------------------------------------------

func can_recruit(count: int = 1) -> Dictionary:
	if count <= 0:
		return {"can_recruit": false, "reason": "Số lượng chiêu mộ phải lớn hơn 0"}

	if soldier_count > 0:
		if movement_state == MovementState.MARCHING or not current_path.is_empty():
			return {"can_recruit": false, "reason": "Quân đội đang hành quân, chỉ có thể chiêu mộ khi đóng quân tại căn cứ"}
		if current_cell != rally_cell:
			return {"can_recruit": false, "reason": "Quân đội đang dã chiến ngoài thành, chỉ có thể chiêu mộ khi đóng quân tại căn cứ"}

	var cap: int = get_army_capacity()
	if cap <= 0:
		return {"can_recruit": false, "reason": "Cần ít nhất một Doanh Trại đang hoạt động để chiêu mộ quân đội"}

	var total_cur: int = get_total_soldier_count()
	if total_cur + count > cap:
		return {"can_recruit": false, "reason": "Vượt quá sức chứa Doanh Trại (Hiện có: %d/%d)" % [total_cur, cap]}

	var cost: Dictionary = get_recruitment_cost(count)
	var rm = get_resource_manager()
	if rm == null:
		return {"can_recruit": false, "reason": "Không tìm thấy kho tài nguyên"}

	if not rm.has_method("can_afford") or not rm.can_afford(cost):
		return {"can_recruit": false, "reason": "Không đủ tài nguyên chiêu mộ"}

	if tactical_military_mgr != null and tactical_military_mgr.has_method("can_allocate_spawns"):
		if not tactical_military_mgr.call("can_allocate_spawns", count, rally_cell, get_nav()):
			return {"can_recruit": false, "reason": "Không đủ vị trí trống an toàn xung quanh điểm tập kết để chiêu mộ"}

	return {"can_recruit": true, "reason": "", "cost": cost}

func recruit(count: int = 1) -> Dictionary:
	var check: Dictionary = can_recruit(count)
	if not check.get("can_recruit", false):
		return {
			"success": false,
			"reason": check.get("reason", "Không thể chiêu mộ"),
			"recruited": 0
		}

	var cost: Dictionary = check.get("cost", {})
	var rm = get_resource_manager()
	if rm == null or not (rm.has_method("reserve_cost") and rm.has_method("commit_cost")):
		return {
			"success": false,
			"reason": "Giao dịch tài nguyên không khả dụng",
			"recruited": 0
		}

	# Atomic transaction: reserve all-or-nothing, then commit
	var reserved: bool = rm.call("reserve_cost", cost)
	if not reserved:
		return {
			"success": false,
			"reason": "Không thể dự trữ tài nguyên chiêu mộ",
			"recruited": 0
		}

	rm.call("commit_cost", cost)

	if soldier_count == 0:
		current_cell = rally_cell
		destination_cell = rally_cell
		current_path.clear()
		step_accumulator = 0.0

	soldier_count += count

	var prev_state := movement_state
	movement_state = get_settled_state_for_cell(current_cell)
	if movement_state != prev_state:
		movement_state_changed.emit(movement_state, current_cell, destination_cell)

	army_changed.emit(soldier_count, get_army_capacity())

	if tactical_military_mgr != null and tactical_military_mgr.has_method("sync_with_player_army"):
		tactical_military_mgr.call("sync_with_player_army")
		var post_sync_state: int = get_settled_state_for_cell(current_cell)
		if post_sync_state != movement_state:
			movement_state = post_sync_state
			movement_state_changed.emit(movement_state, current_cell, destination_cell)

	recruitment_completed.emit(count, cost)

	return {
		"success": true,
		"reason": "Chiêu mộ thành công",
		"recruited": count,
		"cost": cost
	}

# -----------------------------------------------------------------------------
# Daily Food Upkeep
# -----------------------------------------------------------------------------

func process_daily_upkeep(day: int) -> Dictionary:
	if day <= last_upkeep_day:
		return {
			"success": true,
			"already_processed": true,
			"cost": 0,
			"supplied": is_supplied
		}

	var em = get_event_manager()

	# Zero-soldier army incurs zero food upkeep across central, garrisons, and transit
	var total_soldiers: int = get_total_soldier_count()
	if total_soldiers <= 0:
		last_upkeep_day = day
		is_supplied = true
		return {
			"success": true,
			"cost": 0,
			"supplied": true
		}

	var food_needed: int = total_soldiers * EconomyConfigScript.ARMY_DAILY_FOOD_UPKEEP
	var rm = get_resource_manager()
	if rm == null or not (rm.has_method("reserve_cost") and rm.has_method("commit_cost")):
		return {
			"success": false,
			"reason": "ResourceManager không khả dụng cho duy trì quân đội",
			"cost": 0,
			"supplied": is_supplied
		}

	var upkeep_cost: Dictionary = {EconomyConfigScript.RES_FOOD: food_needed}
	var reserved: bool = rm.call("reserve_cost", upkeep_cost)
	if reserved:
		rm.call("commit_cost", upkeep_cost)
		var was_unsupplied: bool = not is_supplied
		is_supplied = true
		last_upkeep_day = day
		if was_unsupplied:
			supply_status_changed.emit(true)
			if em != null and em.has_method("trigger_event"):
				em.trigger_event(
					"army_supplied",
					"Quân Đội Được Tiếp Tế",
					"Đã thanh toán đủ lương thực duy trì quân đội (%d Lương thực). Binh sĩ hồi phục nhuệ khí." % food_needed,
					true,
					{"day": day, "cost": food_needed}
				)
		upkeep_processed.emit(day, food_needed, true)
		return {
			"success": true,
			"cost": food_needed,
			"supplied": true
		}
	else:
		# Insufficient food: do not deduct partial food or delete soldiers; mark unsupplied
		var was_supplied: bool = is_supplied
		is_supplied = false
		last_upkeep_day = day
		if was_supplied:
			supply_status_changed.emit(false)
			if em != null and em.has_method("trigger_event"):
				em.trigger_event(
					"army_unsupplied",
					"Quân Đội Thiếu Lương",
					"Không đủ lương thực duy trì binh sĩ (%d lính cần %d Lương thực). Tinh thần chiến đấu suy giảm!" % [total_soldiers, food_needed],
					false,
					{"day": day, "needed": food_needed}
				)
		upkeep_processed.emit(day, 0, false)
		return {
			"success": false,
			"reason": "Không đủ lương thực duy trì quân đội",
			"cost": 0,
			"supplied": false
		}

# -----------------------------------------------------------------------------
# Movement & Garrison Deployment (Package 1M)
# -----------------------------------------------------------------------------

func get_movement_state() -> int:
	return movement_state

func get_movement_state_string() -> String:
	return movement_state_to_string(movement_state)

func is_defense_eligible() -> bool:
	if soldier_count <= 0:
		return false
	if tactical_military_mgr != null and tactical_military_mgr.has_method("get_garrisoned_unit_count"):
		var garrisoned: int = int(tactical_military_mgr.call("get_garrisoned_unit_count", rally_cell))
		return garrisoned > 0
	if movement_state != MovementState.GARRISONED:
		return false
	return current_cell == rally_cell and current_path.is_empty()

func get_defending_soldier_count() -> int:
	if not is_defense_eligible():
		return 0
	if tactical_military_mgr != null and tactical_military_mgr.has_method("get_garrisoned_unit_count"):
		return maxi(0, int(tactical_military_mgr.call("get_garrisoned_unit_count", rally_cell)))
	return soldier_count

func get_field_unit_count() -> int:
	if soldier_count <= 0:
		return 0
	if tactical_military_mgr != null and tactical_military_mgr.has_method("get_field_unit_count"):
		return maxi(0, int(tactical_military_mgr.call("get_field_unit_count", rally_cell)))
	if movement_state == MovementState.IDLE_AT_FIELD and current_cell != rally_cell:
		return soldier_count
	return 0

func is_garrisoned() -> bool:
	return is_defense_eligible()

func get_current_cell() -> Vector2i:
	return current_cell

func get_rally_cell() -> Vector2i:
	return rally_cell

func get_destination_cell() -> Vector2i:
	return destination_cell

func get_current_path() -> Array[Vector2i]:
	return current_path

func get_default_rally_cell() -> Vector2i:
	var wd: WorldGenerator.WorldData = get_world_data()
	var base_target := Vector2i(32, 33) # default center plaza

	if wd != null:
		# Find townhall building
		var th = null
		for b in wd.buildings:
			if b.get("type", "") == "townhall":
				th = b
				break
		if th != null:
			var th_cell: Vector2i = th.get("cell", Vector2i(31, 30))
			var th_size: Vector2i = th.get("size", Vector2i(3, 3))
			base_target = Vector2i(th_cell.x + int(float(th_size.x) / 2.0), th_cell.y + th_size.y)
		elif wd.get("center_spawn") != null:
			base_target = wd.center_spawn

	var nav: GridNavigation = get_nav()
	if nav == null:
		return base_target

	if nav.is_cell_walkable(base_target):
		return base_target

	# Deterministic outward search (Manhattan distance 1..10)
	for r in range(1, 11):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if abs(dx) + abs(dy) == r:
					var cand := base_target + Vector2i(dx, dy)
					if IsoMath.is_in_bounds(cand) and nav.is_cell_walkable(cand):
						return cand

	return base_target

func refresh_rally_cell() -> void:
	rally_cell = get_default_rally_cell()
	if soldier_count == 0 or (movement_state == MovementState.GARRISONED and current_path.is_empty()):
		current_cell = rally_cell
		destination_cell = rally_cell

func are_all_tactical_units_settled_at_base() -> bool:
	if soldier_count <= 0:
		if tactical_military_mgr == null:
			return true
		var units_when_soldier_count_is_zero: Array = tactical_military_mgr.call("get_all_units")
		return units_when_soldier_count_is_zero.is_empty()

	if tactical_military_mgr == null:
		return false

	var all_units: Array = tactical_military_mgr.call("get_all_units")
	if all_units.is_empty() or all_units.size() != soldier_count:
		return false
	for u in all_units:
		if u.get("order_state") == 1: # OrderState.MOVING
			return false
		var u_cell: Vector2i = u.get("current_cell")
		if IsoMath.grid_distance(u_cell, rally_cell) > RALLY_PERIMETER_DISTANCE:
			return false
	return true

func has_moving_tactical_units() -> bool:
	if tactical_military_mgr == null:
		return false
	var all_units: Array = tactical_military_mgr.call("get_all_units")
	for u in all_units:
		if u.get("order_state") == 1: # OrderState.MOVING
			return true
	return false

func get_settled_state_for_cell(cell: Vector2i) -> int:
	if cell != rally_cell:
		return MovementState.IDLE_AT_FIELD
	if soldier_count == 0:
		if tactical_military_mgr != null:
			var all_units: Array = tactical_military_mgr.call("get_all_units") if tactical_military_mgr.has_method("get_all_units") else []
			if not all_units.is_empty():
				return MovementState.IDLE_AT_FIELD
		return MovementState.GARRISONED
	if tactical_military_mgr == null:
		return MovementState.IDLE_AT_FIELD
	if tactical_military_mgr.get_unit_count() != soldier_count:
		return MovementState.IDLE_AT_FIELD
	if are_all_tactical_units_settled_at_base():
		return MovementState.GARRISONED
	if has_moving_tactical_units():
		return MovementState.MARCHING
	return MovementState.IDLE_AT_FIELD

func order_move(target_cell: Vector2i) -> Dictionary:
	if soldier_count <= 0:
		return {"success": false, "reason": "Không có binh sĩ để điều động"}

	if not IsoMath.is_in_bounds(target_cell):
		return {"success": false, "reason": "Vị trí nằm ngoài bản đồ"}

	var nav: GridNavigation = get_nav()
	if nav == null:
		return {"success": false, "reason": "Hệ thống dẫn đường không khả dụng"}

	if not nav.is_cell_walkable(target_cell):
		return {"success": false, "reason": "Vị trí chỉ định bị cản trở hoặc không thể đi tới"}

	if target_cell == current_cell:
		return {"success": false, "reason": "Quân đội đã ở vị trí này"}

	var path: Array[Vector2i] = nav.find_path(current_cell, target_cell)
	if path.is_empty():
		return {"success": false, "reason": "Không tìm thấy đường đi tới vị trí chỉ định"}

	# First cell in A* path is typically current_cell; strip it so path contains subsequent waypoints
	if path.size() > 0 and path[0] == current_cell:
		path.remove_at(0)

	if path.is_empty():
		return {"success": false, "reason": "Không tìm thấy đường đi tới vị trí chỉ định"}

	# Idempotent re-issue check: if already marching to target_cell with identical route
	if movement_state == MovementState.MARCHING and destination_cell == target_cell and current_path == path:
		if tactical_military_mgr != null:
			var tac_res: Dictionary = {}
			if target_cell == rally_cell and tactical_military_mgr.has_method("order_return_all_to_rally"):
				tac_res = tactical_military_mgr.call("order_return_all_to_rally", rally_cell, nav)
			elif tactical_military_mgr.has_method("order_move_all"):
				tac_res = tactical_military_mgr.call("order_move_all", target_cell, nav)
			if not tac_res.get("success", false):
				return tac_res
		return {"success": true, "reason": "Đã nhận lệnh hành quân", "steps": path.size(), "path_length": path.size()}

	if tactical_military_mgr != null:
		var tac_res: Dictionary = {}
		if target_cell == rally_cell and tactical_military_mgr.has_method("order_return_all_to_rally"):
			tac_res = tactical_military_mgr.call("order_return_all_to_rally", rally_cell, nav)
		elif tactical_military_mgr.has_method("order_move_all"):
			tac_res = tactical_military_mgr.call("order_move_all", target_cell, nav)
		if not tac_res.get("success", false):
			return tac_res

	current_path = path
	destination_cell = target_cell
	step_accumulator = 0.0
	movement_state = MovementState.MARCHING
	movement_state_changed.emit(movement_state, current_cell, destination_cell)
	return {"success": true, "reason": "Đã nhận lệnh hành quân", "steps": path.size(), "path_length": path.size()}

func cancel_move() -> Dictionary:
	if movement_state != MovementState.MARCHING:
		return {"success": false, "reason": "Quân đội hiện không có lệnh hành quân"}
	current_path.clear()
	step_accumulator = 0.0
	destination_cell = current_cell
	movement_state = get_settled_state_for_cell(current_cell)
	movement_state_changed.emit(movement_state, current_cell, destination_cell)
	return {"success": true, "reason": "Đã dừng hành quân tại vị trí hiện tại"}

func order_return_home() -> Dictionary:
	if soldier_count <= 0:
		return {"success": false, "reason": "Không có binh sĩ để điều động"}

	var nav: GridNavigation = get_nav()
	if current_cell == rally_cell:
		if tactical_military_mgr != null and tactical_military_mgr.has_method("order_return_all_to_rally"):
			var tac_res: Dictionary = tactical_military_mgr.call("order_return_all_to_rally", rally_cell, nav)
			if not tac_res.get("success", false):
				return tac_res

		var settled := are_all_tactical_units_settled_at_base()
		if settled:
			current_path.clear()
			step_accumulator = 0.0
			destination_cell = rally_cell
			var prev_state := movement_state
			movement_state = MovementState.GARRISONED
			movement_state_changed.emit(movement_state, current_cell, destination_cell)
			if prev_state == MovementState.MARCHING:
				return {
					"success": true,
					"reason": "Đã hủy hành quân, quân đội tiếp tục đóng quân tại căn cứ",
					"action": "canceled_at_rally"
				}
			elif prev_state == MovementState.IDLE_AT_FIELD:
				return {
					"success": true,
					"reason": "Quân đội đã trở về đóng quân tại căn cứ",
					"action": "returned_to_garrison"
				}
			else:
				return {
					"success": true,
					"reason": "Quân đội đã ở căn cứ",
					"action": "already_garrisoned"
				}
		elif has_moving_tactical_units():
			# Tactical roster is still in transit towards garrison slots: maintain MARCHING in-transit state
			current_path.clear()
			step_accumulator = 0.0
			destination_cell = rally_cell
			movement_state = MovementState.MARCHING
			movement_state_changed.emit(movement_state, current_cell, destination_cell)
			return {
				"success": true,
				"reason": "Quân đội đang hành quân trở về căn cứ",
				"action": "marching_home"
			}
		else:
			# Tactical units are not moving, but outside perimeter, or manager is missing/mismatched:
			# State remains or becomes IDLE_AT_FIELD at rally_cell
			current_path.clear()
			step_accumulator = 0.0
			destination_cell = current_cell
			movement_state = get_settled_state_for_cell(current_cell)
			movement_state_changed.emit(movement_state, current_cell, destination_cell)
			return {
				"success": true,
				"reason": "Quân đội dừng tại điểm tập kết",
				"action": "idle_at_rally"
			}

	# current_cell != rally_cell
	# If already marching to rally_cell with identical route, don't reset step_accumulator or re-dispatch destructively
	if movement_state == MovementState.MARCHING and destination_cell == rally_cell:
		if tactical_military_mgr != null and tactical_military_mgr.has_method("order_return_all_to_rally"):
			var tac_res: Dictionary = tactical_military_mgr.call("order_return_all_to_rally", rally_cell, nav)
			if not tac_res.get("success", false):
				return tac_res
		return {
			"success": true,
			"reason": "Quân đội đang hành quân trở về căn cứ",
			"action": "marching_home"
		}

	var move_res: Dictionary = order_move(rally_cell)
	if move_res.get("success", false):
		move_res["action"] = "marching_home"
		move_res["reason"] = "Quân đội đang hành quân trở về căn cứ"
	return move_res

func advance_movement(delta: float, speed_mult: float = 1.0) -> void:
	if tactical_military_mgr != null and tactical_military_mgr.has_method("advance_movement"):
		tactical_military_mgr.call("advance_movement", delta, speed_mult, get_nav())

	if soldier_count <= 0:
		if movement_state != MovementState.GARRISONED or not current_path.is_empty():
			current_path.clear()
			step_accumulator = 0.0
			movement_state = MovementState.GARRISONED
			current_cell = rally_cell
			destination_cell = rally_cell
			movement_state_changed.emit(movement_state, current_cell, destination_cell)
		return

	if movement_state != MovementState.MARCHING or current_path.is_empty():
		return

	# Stop logical movement completely at 0x / pause
	if speed_mult <= 0.0:
		return

	var tm = get_time_manager()
	if tm != null and tm.has_method("is_paused") and tm.is_paused():
		return

	step_accumulator += delta * speed_mult
	var nav: GridNavigation = get_nav()

	while step_accumulator >= CELL_STEP_DURATION and not current_path.is_empty():
		step_accumulator -= CELL_STEP_DURATION
		var next_cell: Vector2i = current_path[0]

		# Verify that next cell is still walkable
		if nav != null and not nav.is_cell_walkable(next_cell):
			# Route obstructed dynamically! Attempt rerouting to destination_cell
			var rerouted: Array[Vector2i] = nav.find_path(current_cell, destination_cell)
			if rerouted.is_empty():
				# Safe halt at current position
				current_path.clear()
				step_accumulator = 0.0
				destination_cell = current_cell
				movement_state = get_settled_state_for_cell(current_cell)
				movement_state_changed.emit(movement_state, current_cell, destination_cell)
				return
			else:
				if rerouted[0] == current_cell:
					rerouted.remove_at(0)
				if rerouted.is_empty():
					_arrive_at_destination()
					return
				current_path = rerouted
				next_cell = current_path[0]

		current_cell = next_cell
		current_path.remove_at(0)
		army_moved.emit(current_cell)

		if current_path.is_empty():
			_arrive_at_destination()
			break

func _arrive_at_destination() -> void:
	current_path.clear()
	step_accumulator = 0.0
	destination_cell = current_cell
	movement_state = get_settled_state_for_cell(current_cell)
	movement_state_changed.emit(movement_state, current_cell, destination_cell)

static func movement_state_to_string(state: int) -> String:
	match state:
		MovementState.GARRISONED:
			return "garrisoned"
		MovementState.MARCHING:
			return "marching"
		MovementState.IDLE_AT_FIELD:
			return "idle_at_field"
		_:
			return "garrisoned"

static func string_to_movement_state(s: String) -> int:
	match s:
		"marching":
			return MovementState.MARCHING
		"idle_at_field":
			return MovementState.IDLE_AT_FIELD
		"garrisoned", _:
			return MovementState.GARRISONED

# -----------------------------------------------------------------------------
# Casualty Allocation
# -----------------------------------------------------------------------------

func remove_casualties(count: int, from_field: bool = false) -> int:
	if count <= 0:
		return 0
	var max_available: int = soldier_count
	if tactical_military_mgr != null:
		if from_field:
			max_available = get_field_unit_count()
		else:
			max_available = get_defending_soldier_count()
	elif from_field:
		max_available = get_field_unit_count()
	var removed: int = mini(count, max_available)
	if removed <= 0:
		return 0
	soldier_count = maxi(0, soldier_count - removed)
	if soldier_count == 0:
		current_path.clear()
		step_accumulator = 0.0
		movement_state = MovementState.GARRISONED
		current_cell = rally_cell
		destination_cell = rally_cell
		movement_state_changed.emit(movement_state, current_cell, destination_cell)
	if tactical_military_mgr != null and tactical_military_mgr.has_method("sync_with_player_army"):
		tactical_military_mgr.call("sync_with_player_army", from_field, true)
	army_changed.emit(soldier_count, get_army_capacity())
	return removed

func on_tactical_unit_killed(_unit_id: String = "") -> void:
	if soldier_count <= 0:
		return
	soldier_count -= 1
	if soldier_count == 0:
		current_path.clear()
		step_accumulator = 0.0
		movement_state = MovementState.GARRISONED
		current_cell = rally_cell
		destination_cell = rally_cell
		movement_state_changed.emit(movement_state, current_cell, destination_cell)
	army_changed.emit(soldier_count, get_army_capacity())

func sync_state_from_tactical() -> void:
	if tactical_military_mgr == null:
		if soldier_count > 0 and movement_state == MovementState.GARRISONED:
			movement_state = MovementState.IDLE_AT_FIELD
			movement_state_changed.emit(movement_state, current_cell, destination_cell)
		elif soldier_count <= 0 and (movement_state != MovementState.GARRISONED or current_cell != rally_cell):
			movement_state = MovementState.GARRISONED
			current_cell = rally_cell
			destination_cell = rally_cell
			current_path.clear()
			movement_state_changed.emit(movement_state, current_cell, destination_cell)
		return
	if soldier_count <= 0:
		var all_tac: Array = tactical_military_mgr.call("get_all_units") if tactical_military_mgr.has_method("get_all_units") else []
		if not all_tac.is_empty():
			if movement_state != MovementState.IDLE_AT_FIELD:
				movement_state = MovementState.IDLE_AT_FIELD
				movement_state_changed.emit(movement_state, current_cell, destination_cell)
			return
		if movement_state != MovementState.GARRISONED or current_cell != rally_cell:
			movement_state = MovementState.GARRISONED
			current_cell = rally_cell
			destination_cell = rally_cell
			current_path.clear()
			movement_state_changed.emit(movement_state, current_cell, destination_cell)
		return

	# If the strategic army is actively marching on a path, never abort or clear current_path
	if movement_state == MovementState.MARCHING and not current_path.is_empty():
		return

	var all_units: Array = tactical_military_mgr.call("get_all_units")
	if all_units.is_empty():
		if soldier_count > 0 and movement_state == MovementState.GARRISONED:
			movement_state = MovementState.IDLE_AT_FIELD
			movement_state_changed.emit(movement_state, current_cell, destination_cell)
		return

	var any_moving: bool = false
	for u in all_units:
		if u.get("order_state") == 1: # OrderState.MOVING
			any_moving = true
			break

	if any_moving:
		# Enforce strict garrison/field invariant: strategic army cannot be GARRISONED while any tactical unit is moving,
		# and if all field units are moving (no stationary field force remains), strategic state transitions to MARCHING.
		if movement_state == MovementState.GARRISONED or (movement_state == MovementState.IDLE_AT_FIELD and current_cell == rally_cell) or get_field_unit_count() == 0:
			if movement_state != MovementState.MARCHING:
				movement_state = MovementState.MARCHING
				movement_state_changed.emit(movement_state, current_cell, destination_cell)
		return

	# All units are stationary (idle, holding, or attacking): evaluate spatial distribution vs rally_cell
	var all_at_base: bool = (all_units.size() == soldier_count)
	var first_field_cell := Vector2i(-1, -1)
	var has_field_unit_near_current: bool = false
	var current_is_field: bool = (IsoMath.grid_distance(current_cell, rally_cell) > RALLY_PERIMETER_DISTANCE)

	for u in all_units:
		var u_cell: Vector2i = u.get("current_cell")
		var dist: int = IsoMath.grid_distance(u_cell, rally_cell)
		if dist > RALLY_PERIMETER_DISTANCE:
			all_at_base = false
			if first_field_cell == Vector2i(-1, -1):
				first_field_cell = u_cell
			if current_is_field and IsoMath.grid_distance(u_cell, current_cell) <= 3:
				has_field_unit_near_current = true

	if all_at_base:
		if movement_state != MovementState.GARRISONED or current_cell != rally_cell:
			movement_state = MovementState.GARRISONED
			current_cell = rally_cell
			destination_cell = rally_cell
			current_path.clear()
			movement_state_changed.emit(movement_state, current_cell, destination_cell)
	elif first_field_cell == Vector2i(-1, -1):
		# Roster mismatch while all spawned units are at base: cannot claim GARRISONED, preserve current_cell
		if movement_state != MovementState.IDLE_AT_FIELD:
			movement_state = MovementState.IDLE_AT_FIELD
			current_path.clear()
			movement_state_changed.emit(movement_state, current_cell, destination_cell)
	else:
		var target_loc: Vector2i = current_cell if (current_is_field and has_field_unit_near_current) else first_field_cell
		if movement_state != MovementState.IDLE_AT_FIELD or current_cell != target_loc:
			movement_state = MovementState.IDLE_AT_FIELD
			current_cell = target_loc
			destination_cell = target_loc
			current_path.clear()
			movement_state_changed.emit(movement_state, current_cell, destination_cell)

# -----------------------------------------------------------------------------
# Serialization & Persistence
# -----------------------------------------------------------------------------

func serialize() -> Dictionary:
	var path_arr: Array = []
	for p in current_path:
		path_arr.append([p.x, p.y])

	var res := {
		"soldier_count": soldier_count,
		"equipment_tier": equipment_tier,
		"is_supplied": is_supplied,
		"last_upkeep_day": last_upkeep_day,
		"current_cell": [current_cell.x, current_cell.y],
		"rally_cell": [rally_cell.x, rally_cell.y],
		"destination_cell": [destination_cell.x, destination_cell.y],
		"movement_state": movement_state_to_string(movement_state),
		"current_path": path_arr
	}
	var g_data := serialize_garrisons()
	res["garrisons"] = g_data["garrisons"]
	res["reinforcements"] = g_data["reinforcements"]
	return res

func deserialize(data: Dictionary) -> void:
	is_deserializing = true
	if data.is_empty():
		soldier_count = 0
		equipment_tier = 1
		is_supplied = true
		last_upkeep_day = -1
		garrisons.clear()
		active_reinforcements.clear()
		rally_cell = get_default_rally_cell()
		current_cell = rally_cell
		destination_cell = rally_cell
		current_path.clear()
		step_accumulator = 0.0
		if tactical_military_mgr != null and tactical_military_mgr.has_method("clear_all_units"):
			tactical_military_mgr.call("clear_all_units")
		movement_state = get_settled_state_for_cell(current_cell)
		army_changed.emit(soldier_count, get_army_capacity())
		equipment_tier_changed.emit(equipment_tier, get_equipment_combat_multiplier())
		movement_state_changed.emit(movement_state, current_cell, destination_cell)
		is_deserializing = false
		return

	soldier_count = clampi(int(data.get("soldier_count", 0)), 0, 1000)
	deserialize_garrisons(data)
	equipment_tier = clampi(int(data.get("equipment_tier", 1)), EconomyConfigScript.MIN_ARMY_EQUIPMENT_TIER, EconomyConfigScript.MAX_ARMY_EQUIPMENT_TIER)
	is_supplied = bool(data.get("is_supplied", true))
	var raw_last_upkeep: int = int(data.get("last_upkeep_day", -1))
	if raw_last_upkeep < -1:
		raw_last_upkeep = -1

	# Fail-closed normalization: if world_view or singleton TimeManager has current_day,
	# ensure last_upkeep_day does not exceed current_day so upkeep cannot be avoided indefinitely
	var tm = get_time_manager()
	if tm != null and tm.get("current_day") != null:
		var cur_day: int = int(tm.get("current_day"))
		if raw_last_upkeep > cur_day:
			raw_last_upkeep = cur_day

	last_upkeep_day = raw_last_upkeep

	# Restore or derive movement fields
	var def_rally: Vector2i = get_default_rally_cell()
	rally_cell = _parse_coord(data.get("rally_cell"), def_rally)

	# If legacy save lacks movement fields:
	if not data.has("current_cell"):
		current_cell = rally_cell
		destination_cell = rally_cell
		movement_state = MovementState.GARRISONED
		current_path.clear()
	else:
		current_cell = _parse_coord(data.get("current_cell"), rally_cell)
		destination_cell = _parse_coord(data.get("destination_cell"), current_cell)
		movement_state = string_to_movement_state(String(data.get("movement_state", "garrisoned")))

		current_path.clear()
		var raw_path = data.get("current_path")
		if raw_path is Array:
			for item in raw_path:
				var c: Vector2i = _parse_coord(item, Vector2i(-1, -1))
				if c != Vector2i(-1, -1) and IsoMath.is_in_bounds(c):
					current_path.append(c)

	# Safety check: if current_cell is blocked, recover safely to nearest walkable cell or rally cell
	var nav = get_nav()
	if nav != null and not nav.is_cell_walkable(rally_cell):
		rally_cell = def_rally
		if not nav.is_cell_walkable(rally_cell):
			rally_cell = get_default_rally_cell()

	if nav != null and not nav.is_cell_walkable(current_cell):
		var safe_cell := rally_cell
		if not nav.is_cell_walkable(safe_cell):
			safe_cell = get_default_rally_cell()
		current_cell = safe_cell
		current_path.clear()
		destination_cell = current_cell
		movement_state = get_settled_state_for_cell(current_cell)

	# Mutual consistency and route walkability enforcement:
	if soldier_count == 0:
		if tactical_military_mgr != null and tactical_military_mgr.has_method("clear_all_units"):
			tactical_military_mgr.call("clear_all_units")
		current_cell = rally_cell
		destination_cell = rally_cell
		current_path.clear()
		step_accumulator = 0.0
		movement_state = get_settled_state_for_cell(current_cell)
	elif movement_state == MovementState.GARRISONED:
		current_path.clear()
		if current_cell == rally_cell:
			if soldier_count == 0:
				destination_cell = rally_cell
			elif tactical_military_mgr == null:
				# Without tactical military manager, non-empty army cannot be GARRISONED; set safe IDLE_AT_FIELD
				movement_state = MovementState.IDLE_AT_FIELD
				destination_cell = current_cell
			elif tactical_military_mgr.get_unit_count() == soldier_count:
				movement_state = get_settled_state_for_cell(current_cell)
				if movement_state == MovementState.GARRISONED:
					destination_cell = rally_cell
				else:
					destination_cell = current_cell
			else:
				# Defer GARRISONED status until tactical roster is ready and reconciled
				movement_state = MovementState.IDLE_AT_FIELD
				destination_cell = current_cell
		else:
			movement_state = MovementState.IDLE_AT_FIELD
			destination_cell = current_cell
	elif movement_state == MovementState.IDLE_AT_FIELD:
		current_path.clear()
		destination_cell = current_cell
		movement_state = get_settled_state_for_cell(current_cell)
	elif movement_state == MovementState.MARCHING:
		var route_valid := true
		if current_path.is_empty() or destination_cell == current_cell:
			route_valid = false
		elif not _is_cardinal_adjacent(current_cell, current_path[0]):
			route_valid = false
		elif current_path[-1] != destination_cell:
			route_valid = false
		else:
			for i in range(current_path.size() - 1):
				if not _is_cardinal_adjacent(current_path[i], current_path[i + 1]):
					route_valid = false
					break
			if route_valid and nav != null:
				for step in current_path:
					if not nav.is_cell_walkable(step):
						route_valid = false
						break
				if route_valid and not nav.is_cell_walkable(destination_cell):
					route_valid = false

		if not route_valid:
			# Route or destination is obstructed or malformed.
			# Attempt to repair path if destination is walkable and reachable without teleporting.
			var repaired := false
			if nav != null and IsoMath.is_in_bounds(destination_cell) and nav.is_cell_walkable(destination_cell) and destination_cell != current_cell:
				var new_path: Array[Vector2i] = nav.find_path(current_cell, destination_cell)
				if new_path.size() > 0 and new_path[0] == current_cell:
					new_path.remove_at(0)
				if not new_path.is_empty():
					current_path = new_path
					repaired = true

			if not repaired:
				current_path.clear()
				destination_cell = current_cell
				movement_state = get_settled_state_for_cell(current_cell)

	step_accumulator = 0.0
	army_changed.emit(soldier_count, get_army_capacity())
	supply_status_changed.emit(is_supplied)
	equipment_tier_changed.emit(equipment_tier, get_equipment_combat_multiplier())
	movement_state_changed.emit(movement_state, current_cell, destination_cell)
	is_deserializing = false

static func _is_cardinal_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return abs(a.x - b.x) + abs(a.y - b.y) == 1

static func _parse_coord(val, default_val: Vector2i) -> Vector2i:
	if val is Array and val.size() >= 2:
		var x: int = int(val[0])
		var y: int = int(val[1])
		if IsoMath.is_in_bounds(Vector2i(x, y)):
			return Vector2i(x, y)
	elif val is Vector2i:
		if IsoMath.is_in_bounds(val):
			return val
	return default_val

# -----------------------------------------------------------------------------
# Package 3A: Outpost Garrisoning & Reinforcements
# -----------------------------------------------------------------------------

func set_custom_field_siege_manager(fsm: Object) -> void:
	_custom_field_siege_mgr = fsm

func get_field_siege_manager() -> Object:
	if _custom_field_siege_mgr != null:
		return _custom_field_siege_mgr
	if is_instance_valid(world_view) and world_view.get("field_siege_mgr") != null:
		return world_view.get("field_siege_mgr")
	return null

func register_outpost_for_testing(outpost_id: String, capacity: int, cell: Vector2i = Vector2i.ZERO, owner_id: String = "player") -> void:
	_test_registered_outposts[outpost_id] = {
		"outpost_id": outpost_id,
		"capacity": capacity,
		"cell": cell,
		"owner": owner_id,
		"is_alive": true
	}

func get_total_soldier_count() -> int:
	return soldier_count + get_all_garrisoned_count() + get_in_transit_count()

func get_all_garrisoned_count() -> int:
	var total: int = 0
	for o_id in garrisons:
		total += get_garrison_count(o_id)
	return total

func get_in_transit_count(outpost_id: String = "") -> int:
	var total: int = 0
	for r in active_reinforcements:
		if outpost_id.is_empty() or str(r.get("outpost_id", "")) == outpost_id:
			total += int(r.get("soldier_count", 0))
	return total

func get_garrison(outpost_id: String) -> Dictionary:
	return garrisons.get(outpost_id, {})

func get_garrison_count(outpost_id: String) -> int:
	if garrisons.has(outpost_id):
		var s_list = garrisons[outpost_id].get("soldiers", [])
		if s_list is Array:
			return s_list.size()
	return 0

func get_garrison_capacity(outpost_id: String) -> int:
	if garrisons.has(outpost_id) and garrisons[outpost_id].has("capacity"):
		return int(garrisons[outpost_id]["capacity"])
	var info := get_outpost_info(outpost_id)
	return int(info.get("capacity", 0))

func get_outpost_info(outpost_id: String) -> Dictionary:
	if _test_registered_outposts.has(outpost_id):
		var t_info = _test_registered_outposts[outpost_id]
		var is_p: bool = (str(t_info.get("owner", "player")) == "player")
		var is_a: bool = bool(t_info.get("is_alive", true))
		return {
			"valid": is_p and is_a,
			"type": "outpost",
			"owner": str(t_info.get("owner", "player")),
			"is_alive": is_a,
			"cell": t_info.get("cell", Vector2i.ZERO),
			"capacity": maxi(1, int(t_info.get("capacity", 4))),
			"name": outpost_id,
			"reason": "" if (is_p and is_a) else "Tiền đồn không thuộc quyền kiểm soát của bạn hoặc đã bị phá hủy"
		}

	# Check FieldSiegeManager objectives
	var fsm = get_field_siege_manager()
	if fsm != null and fsm.has_method("get_objective"):
		var obj = fsm.get_objective(outpost_id)
		if obj != null and is_instance_valid(obj):
			var owner_str: String = str(obj.get("owning_faction_id"))
			var alive: bool = bool(obj.get("is_alive")) if obj.get("is_alive") != null else true
			var is_player: bool = (owner_str == "player")
			var cap: int = maxi(1, int(obj.get("garrison_count"))) if obj.get("garrison_count") != null and int(obj.get("garrison_count")) > 0 else 4
			return {
				"valid": is_player and alive,
				"type": "objective",
				"owner": owner_str,
				"is_alive": alive,
				"cell": obj.get("current_cell") if obj.get("current_cell") != null else Vector2i.ZERO,
				"capacity": cap,
				"name": str(obj.get("objective_name")),
				"is_under_siege": bool(obj.get("is_under_active_siege")) if obj.get("is_under_active_siege") != null else false,
				"reason": "" if (is_player and alive) else ("Tiền đồn không thuộc quyền kiểm soát của bạn" if not is_player else "Tiền đồn đã bị phá hủy")
			}

	# Check WorldData buildings
	var wd: WorldGenerator.WorldData = get_world_data()
	if wd != null:
		var b_data := BuildingSystemScript.get_building_by_id(outpost_id, wd)
		if not b_data.is_empty():
			var b_type: String = str(b_data.get("type", ""))
			var b_state: String = str(b_data.get("state", "active"))
			var cap: int = BuildingSystemScript.get_building_garrison_capacity(b_type)
			if cap <= 0:
				return {
					"valid": false,
					"type": "building",
					"capacity": 0,
					"reason": "Công trình này không hỗ trợ đồn trú quân"
				}
			if b_state != "active":
				return {
					"valid": false,
					"type": "building",
					"capacity": cap,
					"reason": "Công trình chưa hoàn thành hoặc đang hư hỏng/tạm dừng (%s)" % b_state
				}
			return {
				"valid": true,
				"type": "building",
				"owner": "player",
				"is_alive": (b_state != "destroyed"),
				"cell": b_data.get("cell", Vector2i.ZERO),
				"capacity": cap,
				"name": b_type.capitalize(),
				"reason": ""
			}

	# If already recorded in garrisons (e.g. from loaded save)
	if garrisons.has(outpost_id):
		return {
			"valid": true,
			"type": "outpost",
			"owner": "player",
			"is_alive": true,
			"cell": rally_cell,
			"capacity": int(garrisons[outpost_id].get("capacity", 4)),
			"name": outpost_id,
			"reason": ""
		}

	return {
		"valid": false,
		"reason": "Không tìm thấy tiền đồn hoặc công trình: %s" % outpost_id
	}

func station_soldier(outpost_id: String, count: int = 1) -> Dictionary:
	if count <= 0:
		return {"success": false, "reason": "Số lượng điều binh phải lớn hơn 0"}
	if soldier_count < count:
		return {"success": false, "reason": "Không đủ binh sĩ tại căn cứ trung tâm (Hiện có: %d lính dự bị, yêu cầu: %d)" % [soldier_count, count]}

	var info := get_outpost_info(outpost_id)
	if not bool(info.get("valid", false)):
		return {"success": false, "reason": info.get("reason", "Tiền đồn không hợp lệ")}

	var cap: int = int(info.get("capacity", 4))
	var cur: int = get_garrison_count(outpost_id)
	var in_transit: int = get_in_transit_count(outpost_id)
	if cur + in_transit + count > cap:
		return {"success": false, "reason": "Vượt quá sức chứa đồn trú của tiền đồn (Hiện có: %d/%d, đang tiếp viện: %d)" % [cur, cap, in_transit]}

	soldier_count -= count
	if not garrisons.has(outpost_id):
		garrisons[outpost_id] = {
			"outpost_id": outpost_id,
			"capacity": cap,
			"soldiers": []
		}

	for i in range(count):
		var s_id := "soldier_gar_%d" % next_soldier_id
		next_soldier_id += 1
		garrisons[outpost_id]["soldiers"].append({
			"soldier_id": s_id,
			"equipment_tier": equipment_tier,
			"health": 100.0,
			"max_health": 100.0,
			"stationed_at": outpost_id
		})

	if tactical_military_mgr != null and tactical_military_mgr.has_method("sync_with_player_army"):
		tactical_military_mgr.sync_with_player_army()

	garrison_changed.emit(outpost_id, get_garrison_count(outpost_id), cap)
	army_changed.emit(soldier_count, get_army_capacity())
	return {
		"success": true,
		"stationed": count,
		"remaining_reserve": soldier_count,
		"outpost_count": get_garrison_count(outpost_id),
		"capacity": cap
	}

func recall_soldier(outpost_id: String, count: int = 1) -> Dictionary:
	if count <= 0:
		return {"success": false, "reason": "Số lượng rút quân phải lớn hơn 0"}
	var cur: int = get_garrison_count(outpost_id)
	if cur < count:
		return {"success": false, "reason": "Không đủ quân đồn trú để rút (Hiện có: %d lính đồn trú, yêu cầu: %d)" % [cur, count]}

	var s_list: Array = garrisons[outpost_id].get("soldiers", [])
	for i in range(count):
		s_list.pop_back()

	soldier_count += count
	if tactical_military_mgr != null and tactical_military_mgr.has_method("sync_with_player_army"):
		tactical_military_mgr.sync_with_player_army()

	var cap: int = get_garrison_capacity(outpost_id)
	garrison_changed.emit(outpost_id, get_garrison_count(outpost_id), cap)
	army_changed.emit(soldier_count, get_army_capacity())
	return {
		"success": true,
		"recalled": count,
		"reserve_count": soldier_count,
		"outpost_count": get_garrison_count(outpost_id)
	}

func dispatch_reinforcements(outpost_id: String, count: int = 1, travel_hours: float = -1.0) -> Dictionary:
	if count <= 0:
		return {"success": false, "reason": "Số lượng điều binh phải lớn hơn 0"}
	if soldier_count < count:
		return {"success": false, "reason": "Không đủ binh sĩ tại căn cứ trung tâm (Hiện có: %d lính dự bị, yêu cầu: %d)" % [soldier_count, count]}

	var info := get_outpost_info(outpost_id)
	if not bool(info.get("valid", false)):
		return {"success": false, "reason": info.get("reason", "Tiền đồn không hợp lệ")}

	var cap: int = int(info.get("capacity", 4))
	var cur: int = get_garrison_count(outpost_id)
	var in_transit: int = get_in_transit_count(outpost_id)
	if cur + in_transit + count > cap:
		return {"success": false, "reason": "Vượt quá sức chứa đồn trú của tiền đồn (Hiện có: %d/%d, đang tiếp viện: %d)" % [cur, cap, in_transit]}

	var dist: int = IsoMath.grid_distance(rally_cell, info.get("cell", rally_cell))
	var calc_travel := travel_hours
	if calc_travel < 0.0:
		calc_travel = maxf(1.0, float(dist) * 0.1)

	if calc_travel <= 0.0:
		return station_soldier(outpost_id, count)

	soldier_count -= count
	var dispatched_soldiers: Array[Dictionary] = []
	for i in range(count):
		var s_id := "soldier_reinf_%d" % next_soldier_id
		next_soldier_id += 1
		dispatched_soldiers.append({
			"soldier_id": s_id,
			"equipment_tier": equipment_tier,
			"health": 100.0,
			"max_health": 100.0,
			"stationed_at": outpost_id
		})

	var disp_id := "reinf_%d" % next_reinforce_id
	next_reinforce_id += 1
	var reinf_rec := {
		"dispatch_id": disp_id,
		"outpost_id": outpost_id,
		"soldier_count": count,
		"soldiers": dispatched_soldiers,
		"elapsed_hours": 0.0,
		"travel_hours": calc_travel,
		"source_cell": rally_cell,
		"target_cell": info.get("cell", rally_cell)
	}
	active_reinforcements.append(reinf_rec)
	reinforcement_dispatched.emit(disp_id, outpost_id, count)
	army_changed.emit(soldier_count, get_army_capacity())
	if tactical_military_mgr != null and tactical_military_mgr.has_method("sync_with_player_army"):
		tactical_military_mgr.sync_with_player_army()

	return {
		"success": true,
		"dispatch_id": disp_id,
		"travel_hours": calc_travel,
		"soldier_count": count
	}

func advance_reinforcements(delta_hours: float) -> Array[Dictionary]:
	if delta_hours <= 0.0 or active_reinforcements.is_empty():
		return []

	var completed: Array[Dictionary] = []
	var remaining: Array[Dictionary] = []

	for r in active_reinforcements:
		r["elapsed_hours"] = float(r.get("elapsed_hours", 0.0)) + delta_hours
		var travel: float = float(r.get("travel_hours", 1.0))
		if r["elapsed_hours"] >= travel:
			var out_id: String = str(r.get("outpost_id", ""))
			var s_list: Array = r.get("soldiers", [])
			var c_count: int = int(r.get("soldier_count", s_list.size()))

			var info := get_outpost_info(out_id)
			if bool(info.get("valid", false)):
				if not garrisons.has(out_id):
					garrisons[out_id] = {
						"outpost_id": out_id,
						"capacity": int(info.get("capacity", 4)),
						"soldiers": []
					}
				for s in s_list:
					garrisons[out_id]["soldiers"].append(s)
				garrison_changed.emit(out_id, get_garrison_count(out_id), get_garrison_capacity(out_id))
			else:
				# Outpost lost while in transit: retreat to central reserve
				soldier_count += c_count
				army_changed.emit(soldier_count, get_army_capacity())
				if tactical_military_mgr != null and tactical_military_mgr.has_method("sync_with_player_army"):
					tactical_military_mgr.sync_with_player_army()

			reinforcement_arrived.emit(str(r.get("dispatch_id", "")), out_id, c_count)
			completed.append(r)
		else:
			remaining.append(r)

	active_reinforcements = remaining
	return completed

func apply_outpost_casualties(outpost_id: String, count: int) -> int:
	if count <= 0 or not garrisons.has(outpost_id):
		return 0
	var s_list: Array = garrisons[outpost_id].get("soldiers", [])
	var actual_removed := mini(count, s_list.size())
	for i in range(actual_removed):
		s_list.pop_back()
	garrison_changed.emit(outpost_id, get_garrison_count(outpost_id), get_garrison_capacity(outpost_id))
	return actual_removed

func evict_outpost_garrison(outpost_id: String, retreat_to_central: bool = false) -> Array:
	if not garrisons.has(outpost_id):
		return []
	var s_list: Array = garrisons[outpost_id].get("soldiers", [])
	var count := s_list.size()
	garrisons.erase(outpost_id)
	if retreat_to_central and count > 0:
		soldier_count += count
		army_changed.emit(soldier_count, get_army_capacity())
		if tactical_military_mgr != null and tactical_military_mgr.has_method("sync_with_player_army"):
			tactical_military_mgr.sync_with_player_army()
	garrison_changed.emit(outpost_id, 0, 0)
	return s_list

func serialize_garrisons() -> Dictionary:
	var result: Dictionary = {
		"garrisons": {},
		"reinforcements": []
	}
	for o_id in garrisons:
		var g = garrisons[o_id]
		var s_copy: Array = []
		for s in g.get("soldiers", []):
			if s is Dictionary:
				s_copy.append(s.duplicate())
		result["garrisons"][o_id] = {
			"outpost_id": o_id,
			"capacity": int(g.get("capacity", 4)),
			"soldiers": s_copy
		}
	for r in active_reinforcements:
		result["reinforcements"].append(r.duplicate(true))
	return result

func deserialize_garrisons(data: Dictionary) -> bool:
	garrisons.clear()
	active_reinforcements.clear()
	if data.is_empty():
		return true

	var raw_gar = data.get("garrisons")
	if raw_gar is Dictionary:
		for o_id in raw_gar:
			var g_rec = raw_gar[o_id]
			if g_rec is Dictionary:
				var s_list: Array = []
				var raw_s = g_rec.get("soldiers")
				if raw_s is Array:
					for s in raw_s:
						if s is Dictionary:
							s_list.append(s.duplicate())
				garrisons[str(o_id)] = {
					"outpost_id": str(o_id),
					"capacity": maxi(1, int(g_rec.get("capacity", 4))),
					"soldiers": s_list
				}

	var raw_reinf = data.get("reinforcements")
	if raw_reinf is Array:
		for r in raw_reinf:
			if r is Dictionary:
				active_reinforcements.append(r.duplicate(true))

	return true

