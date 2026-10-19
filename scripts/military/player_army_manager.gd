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

var world_view: Node = null
var soldier_count: int = 0
var is_supplied: bool = true
var last_upkeep_day: int = -1

# Authoritative Movement State (Package 1M)
var current_cell: Vector2i = Vector2i(32, 33)
var rally_cell: Vector2i = Vector2i(32, 33)
var destination_cell: Vector2i = Vector2i(32, 33)
var current_path: Array[Vector2i] = []
var movement_state: int = MovementState.GARRISONED
var step_accumulator: float = 0.0

# Dependency injection hooks for headless/unit testing
var _custom_resource_mgr: Object = null
var _custom_world_data: WorldGenerator.WorldData = null
var _custom_event_mgr: Object = null
var _custom_nav: GridNavigation = null
var _custom_time_mgr: Object = null

func _init(wv: Node = null) -> void:
	world_view = wv
	soldier_count = 0
	is_supplied = true
	last_upkeep_day = -1
	rally_cell = Vector2i(32, 33)
	current_cell = rally_cell
	destination_cell = rally_cell
	movement_state = MovementState.GARRISONED
	current_path = []
	step_accumulator = 0.0
	if is_instance_valid(world_view) and world_view.get("world_data") != null:
		rally_cell = get_default_rally_cell()
		current_cell = rally_cell
		destination_cell = rally_cell

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

	if movement_state == MovementState.MARCHING:
		return {"can_recruit": false, "reason": "Quân đội đang hành quân, chỉ có thể chiêu mộ khi đóng quân tại căn cứ"}
	if movement_state == MovementState.IDLE_AT_FIELD or current_cell != rally_cell:
		return {"can_recruit": false, "reason": "Quân đội đang dã chiến ngoài thành, chỉ có thể chiêu mộ khi đóng quân tại căn cứ"}
	if not current_path.is_empty():
		return {"can_recruit": false, "reason": "Quân đội đang di chuyển, chỉ có thể chiêu mộ khi đóng quân tại căn cứ"}

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
# Movement & Garrison Deployment (Package 1M)
# -----------------------------------------------------------------------------

func get_movement_state() -> int:
	return movement_state

func get_movement_state_string() -> String:
	return movement_state_to_string(movement_state)

func is_defense_eligible() -> bool:
	return soldier_count > 0 and movement_state == MovementState.GARRISONED and current_cell == rally_cell and current_path.is_empty()

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

	current_path = path
	destination_cell = target_cell
	step_accumulator = 0.0
	movement_state = MovementState.MARCHING
	movement_state_changed.emit(movement_state, current_cell, destination_cell)
	return {"success": true, "reason": "Đã nhận lệnh hành quân", "path_length": path.size()}

func cancel_move() -> Dictionary:
	if movement_state != MovementState.MARCHING:
		return {"success": false, "reason": "Quân đội hiện không có lệnh hành quân"}
	current_path.clear()
	step_accumulator = 0.0
	destination_cell = current_cell
	if current_cell == rally_cell:
		movement_state = MovementState.GARRISONED
	else:
		movement_state = MovementState.IDLE_AT_FIELD
	movement_state_changed.emit(movement_state, current_cell, destination_cell)
	return {"success": true, "reason": "Đã dừng hành quân tại vị trí hiện tại"}

func order_return_home() -> Dictionary:
	return order_move(rally_cell)

func advance_movement(delta: float, speed_mult: float = 1.0) -> void:
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
				movement_state = MovementState.GARRISONED if current_cell == rally_cell else MovementState.IDLE_AT_FIELD
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
	if current_cell == rally_cell:
		movement_state = MovementState.GARRISONED
	else:
		movement_state = MovementState.IDLE_AT_FIELD
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

func remove_casualties(count: int) -> int:
	if count <= 0:
		return 0
	var removed: int = mini(count, soldier_count)
	soldier_count = maxi(0, soldier_count - removed)
	if soldier_count == 0:
		current_path.clear()
		step_accumulator = 0.0
		movement_state = MovementState.GARRISONED
		current_cell = rally_cell
		destination_cell = rally_cell
		movement_state_changed.emit(movement_state, current_cell, destination_cell)
	army_changed.emit(soldier_count, get_army_capacity())
	return removed

# -----------------------------------------------------------------------------
# Serialization & Persistence
# -----------------------------------------------------------------------------

func serialize() -> Dictionary:
	var path_arr: Array = []
	for p in current_path:
		path_arr.append([p.x, p.y])

	return {
		"soldier_count": soldier_count,
		"is_supplied": is_supplied,
		"last_upkeep_day": last_upkeep_day,
		"current_cell": [current_cell.x, current_cell.y],
		"rally_cell": [rally_cell.x, rally_cell.y],
		"destination_cell": [destination_cell.x, destination_cell.y],
		"movement_state": movement_state_to_string(movement_state),
		"current_path": path_arr
	}

func deserialize(data: Dictionary) -> void:
	if data.is_empty():
		soldier_count = 0
		is_supplied = true
		last_upkeep_day = -1
		rally_cell = get_default_rally_cell()
		current_cell = rally_cell
		destination_cell = rally_cell
		movement_state = MovementState.GARRISONED
		current_path.clear()
		step_accumulator = 0.0
		army_changed.emit(soldier_count, get_army_capacity())
		movement_state_changed.emit(movement_state, current_cell, destination_cell)
		return

	soldier_count = clampi(int(data.get("soldier_count", 0)), 0, 1000)
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
	if nav != null and not nav.is_cell_walkable(current_cell):
		var safe_cell := def_rally
		if not nav.is_cell_walkable(safe_cell):
			safe_cell = get_default_rally_cell()
		current_cell = safe_cell
		current_path.clear()
		destination_cell = current_cell
		movement_state = MovementState.GARRISONED

	# Mutual consistency enforcement:
	if soldier_count == 0:
		movement_state = MovementState.GARRISONED
		current_cell = rally_cell
		destination_cell = rally_cell
		current_path.clear()
	elif movement_state == MovementState.GARRISONED:
		destination_cell = current_cell
		current_path.clear()
	elif movement_state == MovementState.MARCHING and current_path.is_empty():
		movement_state = MovementState.GARRISONED if current_cell == rally_cell else MovementState.IDLE_AT_FIELD
		destination_cell = current_cell

	step_accumulator = 0.0
	army_changed.emit(soldier_count, get_army_capacity())
	supply_status_changed.emit(is_supplied)
	movement_state_changed.emit(movement_state, current_cell, destination_cell)

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
