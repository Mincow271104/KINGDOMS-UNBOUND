class_name PlayerArmyManager
extends RefCounted
## Player Army Manager (Package 1L)
## Authoritative manager for player-recruited abstract army units,
## Barracks capacity calculations, atomic recruitment transactions,
## daily food upkeep ticks, supply states, combat morale, and casualty reductions.

const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")

signal army_changed(current_count: int, capacity: int)
signal supply_status_changed(is_supplied: bool)
signal upkeep_processed(day: int, cost_paid: int, success: bool)
signal recruitment_completed(count: int, cost: Dictionary)

var world_view: Node = null
var soldier_count: int = 0
var is_supplied: bool = true
var last_upkeep_day: int = -1

# Dependency injection hooks for headless/unit testing
var _custom_resource_mgr: Object = null
var _custom_world_data: WorldGenerator.WorldData = null
var _custom_event_mgr: Object = null

func _init(wv: Node = null) -> void:
	world_view = wv
	soldier_count = 0
	is_supplied = true
	last_upkeep_day = -1

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
	return maxi(0, get_army_capacity() - soldier_count)

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
# Recruitment Transaction
# -----------------------------------------------------------------------------

func can_recruit(count: int = 1) -> Dictionary:
	if count <= 0:
		return {"can_recruit": false, "reason": "Số lượng chiêu mộ phải lớn hơn 0"}

	var cap: int = get_army_capacity()
	if cap <= 0:
		return {"can_recruit": false, "reason": "Cần ít nhất một Doanh Trại đang hoạt động để chiêu mộ quân đội"}

	if soldier_count + count > cap:
		return {"can_recruit": false, "reason": "Vượt quá sức chứa Doanh Trại (Hiện có: %d/%d)" % [soldier_count, cap]}

	var cost: Dictionary = get_recruitment_cost(count)
	var rm = get_resource_manager()
	if rm == null:
		return {"can_recruit": false, "reason": "Không tìm thấy kho tài nguyên"}

	if not rm.has_method("can_afford") or not rm.can_afford(cost):
		return {"can_recruit": false, "reason": "Không đủ tài nguyên chiêu mộ"}

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
	soldier_count += count
	army_changed.emit(soldier_count, get_army_capacity())
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

	# Zero-soldier army incurs zero food upkeep
	if soldier_count <= 0:
		last_upkeep_day = day
		is_supplied = true
		return {
			"success": true,
			"cost": 0,
			"supplied": true
		}

	var food_needed: int = soldier_count * EconomyConfigScript.ARMY_DAILY_FOOD_UPKEEP
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
					"Không đủ lương thực duy trì binh sĩ (%d lính cần %d Lương thực). Tinh thần chiến đấu suy giảm!" % [soldier_count, food_needed],
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
# Casualty Allocation
# -----------------------------------------------------------------------------

func remove_casualties(count: int) -> int:
	if count <= 0:
		return 0
	var removed: int = mini(count, soldier_count)
	soldier_count = maxi(0, soldier_count - removed)
	army_changed.emit(soldier_count, get_army_capacity())
	return removed

# -----------------------------------------------------------------------------
# Serialization & Persistence
# -----------------------------------------------------------------------------

func serialize() -> Dictionary:
	return {
		"soldier_count": soldier_count,
		"is_supplied": is_supplied,
		"last_upkeep_day": last_upkeep_day
	}

func deserialize(data: Dictionary) -> void:
	if data.is_empty():
		soldier_count = 0
		is_supplied = true
		last_upkeep_day = -1
		army_changed.emit(soldier_count, get_army_capacity())
		return

	soldier_count = clampi(int(data.get("soldier_count", 0)), 0, 1000)
	is_supplied = bool(data.get("is_supplied", true))
	var raw_last_upkeep: int = int(data.get("last_upkeep_day", -1))
	if raw_last_upkeep < -1:
		raw_last_upkeep = -1

	# Fail-closed normalization: if world_view or singleton TimeManager has current_day,
	# ensure last_upkeep_day does not exceed current_day so upkeep cannot be avoided indefinitely
	var tm = null
	if is_instance_valid(world_view) and world_view.is_inside_tree():
		tm = world_view.get_node_or_null("/root/TimeManager")
	elif Engine.has_singleton("TimeManager"):
		tm = Engine.get_singleton("TimeManager")
	if tm != null and tm.get("current_day") != null:
		var cur_day: int = int(tm.get("current_day"))
		if raw_last_upkeep > cur_day:
			raw_last_upkeep = cur_day

	last_upkeep_day = raw_last_upkeep
	army_changed.emit(soldier_count, get_army_capacity())
	supply_status_changed.emit(is_supplied)
