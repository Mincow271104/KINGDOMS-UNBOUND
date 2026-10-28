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
	is_supplied = true
	last_upkeep_day = -1
	rally_cell = Vector2i(32, 33)
	current_cell = rally_cell
	destination_cell = rally_cell
	movement_state = MovementState.GARRISONED
	current_path = []
	step_accumulator = 0.0
	tactical_military_mgr = null
	if is_instance_valid(world_view) and world_view.get("world_data") != null:
		rally_cell = get_default_rally_cell()
		current_cell = rally_cell
		destination_cell = rally_cell

func set_tactical_military_manager(mgr: Object) -> void:
	if tactical_military_mgr != null and is_instance_valid(tactical_military_mgr) and tactical_military_mgr.has_signal("tactical_state_updated"):
		if tactical_military_mgr.tactical_state_updated.is_connected(sync_state_from_tactical):
			tactical_military_mgr.tactical_state_updated.disconnect(sync_state_from_tactical)
	tactical_military_mgr = mgr
	if tactical_military_mgr != null and is_instance_valid(tactical_military_mgr) and tactical_military_mgr.has_signal("tactical_state_updated"):
		if not tactical_military_mgr.tactical_state_updated.is_connected(sync_state_from_tactical):
			tactical_military_mgr.tactical_state_updated.connect(sync_state_from_tactical)
	sync_state_from_tactical()

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

	if soldier_count > 0:
		if movement_state == MovementState.MARCHING or not current_path.is_empty():
			return {"can_recruit": false, "reason": "Quân đội đang hành quân, chỉ có thể chiêu mộ khi đóng quân tại căn cứ"}
		if current_cell != rally_cell:
			return {"can_recruit": false, "reason": "Quân đội đang dã chiến ngoài thành, chỉ có thể chiêu mộ khi đóng quân tại căn cứ"}

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
		var all_units: Array = tactical_military_mgr.call("get_all_units")
		return all_units.is_empty()

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
		# Enforce strict garrison invariant: strategic army cannot be GARRISONED while any tactical unit is moving
		if movement_state == MovementState.GARRISONED or (movement_state == MovementState.IDLE_AT_FIELD and current_cell == rally_cell):
			movement_state = MovementState.MARCHING
			movement_state_changed.emit(movement_state, current_cell, destination_cell)
		return

	# If army is already IDLE_AT_FIELD at a valid field position and no units are moving:
	if movement_state == MovementState.IDLE_AT_FIELD and current_cell != rally_cell:
		return

	# All units are idle: evaluate spatial distribution vs rally_cell
	var all_at_base: bool = (all_units.size() == soldier_count)
	var first_field_cell := Vector2i(-1, -1)

	for u in all_units:
		var u_cell: Vector2i = u.get("current_cell")
		var dist: int = IsoMath.grid_distance(u_cell, rally_cell)
		if dist > RALLY_PERIMETER_DISTANCE:
			all_at_base = false
			if first_field_cell == Vector2i(-1, -1):
				first_field_cell = u_cell

	if all_at_base:
		if movement_state != MovementState.GARRISONED or current_cell != rally_cell:
			movement_state = MovementState.GARRISONED
			current_cell = rally_cell
			destination_cell = rally_cell
			current_path.clear()
			movement_state_changed.emit(movement_state, current_cell, destination_cell)
	else:
		var fallback_cell: Vector2i = all_units[0].current_cell if all_units[0] is Node2D else Vector2i(all_units[0].get("current_cell"))
		var target_loc: Vector2i = first_field_cell if first_field_cell != Vector2i(-1, -1) else fallback_cell
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
	is_deserializing = true
	if data.is_empty():
		soldier_count = 0
		is_supplied = true
		last_upkeep_day = -1
		rally_cell = get_default_rally_cell()
		current_cell = rally_cell
		destination_cell = rally_cell
		current_path.clear()
		step_accumulator = 0.0
		if tactical_military_mgr != null and tactical_military_mgr.has_method("clear_all_units"):
			tactical_military_mgr.call("clear_all_units")
		movement_state = get_settled_state_for_cell(current_cell)
		army_changed.emit(soldier_count, get_army_capacity())
		movement_state_changed.emit(movement_state, current_cell, destination_cell)
		is_deserializing = false
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
