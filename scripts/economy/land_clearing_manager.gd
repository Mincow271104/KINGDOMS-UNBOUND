class_name LandClearingManager
extends RefCounted

const SchedulePolicyScript = preload("res://scripts/entities/citizen_schedule_policy.gd")
## Authoritative Land Clearing & Resource Recovery Manager (KU-POST-MVP-LAND-CLEARING-01).
## Manages queued tree/rock clearing orders, atomic worker/slot reservations,
## fatigue-safe work lifecycle, idempotent ResourceManager rewards, and persistence.

signal clearing_orders_changed()
signal prop_cleared(prop_id: String, prop_type: String, cell: Vector2i, reward_resource: String, reward_amount: int)
signal clearing_order_blocked(order_id: String, reason: String)
signal clearing_order_waiting_storage(order_id: String, reward_resource: String, reward_amount: int)

enum OrderState {
	QUEUED,
	RESERVED,
	MOVING,
	WORKING,
	PAUSED_FOR_REST,
	WAITING_FOR_STORAGE,
	COMPLETED,
	BLOCKED,
	CANCELLED
}

var orders_by_id: Dictionary = {}          # order_id (String) -> Dictionary
var active_order_by_cell: Dictionary = {}  # Vector2i -> order_id (String)
var cleared_prop_ids: Dictionary = {}      # prop_id (String) -> true
var committed_reward_tx_ids: Dictionary = {} # tx_id (String) -> true
var reserved_work_slots: Dictionary = {}   # Vector2i -> order_id (String)
var _next_order_seq: int = 1
var _finalizing_waiting: bool = false

static func make_prop_id(world_seed: int, gen_ver: int, prop_type: String, cell: Vector2i) -> String:
	return WorldGenerator.make_prop_id(world_seed, gen_ver, prop_type, cell)

static func state_to_string(st: int) -> String:
	match st:
		OrderState.QUEUED: return "QUEUED"
		OrderState.RESERVED: return "RESERVED"
		OrderState.MOVING: return "MOVING"
		OrderState.WORKING: return "WORKING"
		OrderState.PAUSED_FOR_REST: return "PAUSED_FOR_REST"
		OrderState.WAITING_FOR_STORAGE: return "WAITING_FOR_STORAGE"
		OrderState.COMPLETED: return "COMPLETED"
		OrderState.BLOCKED: return "BLOCKED"
		OrderState.CANCELLED: return "CANCELLED"
		_: return "UNKNOWN"

func clear_all() -> void:
	orders_by_id.clear()
	active_order_by_cell.clear()
	cleared_prop_ids.clear()
	committed_reward_tx_ids.clear()
	reserved_work_slots.clear()
	_next_order_seq = 1
	clearing_orders_changed.emit()

func is_prop_cleared(prop_id: String) -> bool:
	return cleared_prop_ids.has(prop_id)

func get_order(order_id: String) -> Dictionary:
	return orders_by_id.get(order_id, {})

func get_order_at_cell(cell: Vector2i) -> Dictionary:
	var oid: String = str(active_order_by_cell.get(cell, ""))
	if oid == "":
		return {}
	return orders_by_id.get(oid, {})

func get_active_orders() -> Array[Dictionary]:
	var res: Array[Dictionary] = []
	for oid in orders_by_id:
		var o: Dictionary = orders_by_id[oid]
		var st: int = int(o.get("state", OrderState.CANCELLED))
		if st != OrderState.COMPLETED and st != OrderState.CANCELLED:
			res.append(o)
	return res

func get_outstanding_count() -> int:
	return get_active_orders().size()

func find_prop_at_cell(world_data: WorldGenerator.WorldData, cell: Vector2i) -> Dictionary:
	if world_data == null or world_data.get("props") == null:
		return {}
	for p in world_data.props:
		if p.get("cell", Vector2i(-1, -1)) == cell:
			return p
	return {}

func _is_cell_protected(world_data: WorldGenerator.WorldData, cell: Vector2i, poi_mgr: Object = null) -> bool:
	if world_data == null or not IsoMath.is_in_bounds(cell):
		return true
	if world_data.terrain[cell.x][cell.y] == WorldGenerator.TerrainType.WATER:
		return true
	for b in world_data.buildings:
		var bp: Dictionary = EconomyConfig.BLUEPRINTS.get(b.get("type", ""), {})
		var size: Vector2i = bp.get("footprint", Vector2i(1, 1))
		var origin: Vector2i = b.get("cell", Vector2i(-1, -1))
		if cell.x >= origin.x and cell.x < origin.x + size.x and cell.y >= origin.y and cell.y < origin.y + size.y:
			return true
	if poi_mgr != null and poi_mgr.has_method("get_all_pois"):
		for poi in poi_mgr.call("get_all_pois"):
			if poi != null and poi.cell == cell:
				return true
	return false

func queue_clearing_order(world_data: WorldGenerator.WorldData, cell: Vector2i, world_seed: int, gen_ver: int, poi_mgr: Object = null) -> Dictionary:
	if world_data == null or not IsoMath.is_in_bounds(cell):
		return {"success": false, "reason": "Vị trí nằm ngoài bản đồ."}

	if _is_cell_protected(world_data, cell, poi_mgr):
		return {"success": false, "reason": "Vị trí là công trình, địa danh hoặc mặt nước được bảo vệ."}

	if world_data.owned_cells.size() == world_data.map_width and not bool(world_data.owned_cells[cell.x][cell.y]):
		return {"success": false, "reason": "Không thể khai hoang ngoài lãnh thổ vương quốc."}

	if active_order_by_cell.has(cell):
		return {"success": false, "reason": "Mục tiêu này đã nằm trong hàng đợi dọn mặt bằng."}

	var prop := find_prop_at_cell(world_data, cell)
	if prop.is_empty():
		return {"success": false, "reason": "Không có cây cối hoặc đá tảng hợp lệ tại ô này."}

	var p_type: String = str(prop.get("type", ""))
	var spec: Dictionary = EconomyConfig.get_land_clearing_spec(p_type)
	if spec.is_empty():
		return {"success": false, "reason": "Đối tượng '%s' không thể dọn mặt bằng." % p_type}

	var prop_id: String = make_prop_id(world_seed, gen_ver, p_type, cell)
	if cleared_prop_ids.has(prop_id):
		return {"success": false, "reason": "Mục tiêu này đã được dọn sạch trước đó."}

	var reward_res: String = str(spec.get("reward_resource", ""))
	var reward_amt: int = int(spec.get("reward_amount", 0))
	if prop.has("remaining_resource") and int(prop.get("remaining_resource", 0)) > 0:
		reward_amt = int(prop.get("remaining_resource", reward_amt))
	if prop.has("resource_type") and str(prop.get("resource_type", "")) != "":
		reward_res = str(prop.get("resource_type", reward_res))

	var order_id: String = "clr_%d_%s" % [_next_order_seq, prop_id]
	_next_order_seq += 1

	var order: Dictionary = {
		"order_id": order_id,
		"prop_id": prop_id,
		"prop_type": p_type,
		"cell": cell,
		"required_role": str(spec.get("required_role", "woodcutter")),
		"required_role_vn": str(spec.get("required_role_vn", "Thợ Đốn Gỗ")),
		"skill": str(spec.get("skill", "woodcutting")),
		"work_hours_required": float(spec.get("work_hours", 4.0)),
		"work_hours_done": 0.0,
		"reward_resource": reward_res,
		"reward_amount": reward_amt,
		"tx_id": "clear_reward:" + prop_id,
		"state": OrderState.QUEUED,
		"assigned_citizen_id": "",
		"work_slot": Vector2i(-1, -1),
		"status_reason": "Đang chờ %s rảnh" % str(spec.get("required_role_vn", "Thợ"))
	}
	orders_by_id[order_id] = order
	active_order_by_cell[cell] = order_id
	clearing_orders_changed.emit()
	return {"success": true, "order_id": order_id, "order": order}

func cancel_clearing_order(order_id: String, citizen_list: Array = []) -> Dictionary:
	if not orders_by_id.has(order_id):
		return {"success": false, "reason": "Không tìm thấy lệnh dọn mặt bằng."}
	var order: Dictionary = orders_by_id[order_id]
	var st: int = int(order.get("state", OrderState.CANCELLED))
	if st == OrderState.COMPLETED or st == OrderState.CANCELLED:
		return {"success": false, "reason": "Lệnh đã hoàn tất hoặc đã bị hủy."}

	_release_order_reservations(order, citizen_list)
	order["state"] = OrderState.CANCELLED
	order["status_reason"] = "Người chơi đã hủy lệnh"
	var cell: Vector2i = order.get("cell", Vector2i(-1, -1))
	if active_order_by_cell.get(cell, "") == order_id:
		active_order_by_cell.erase(cell)
	orders_by_id.erase(order_id)
	clearing_orders_changed.emit()
	return {"success": true, "order_id": order_id}

func cancel_clearing_at_cell(cell: Vector2i, citizen_list: Array = []) -> Dictionary:
	var oid: String = str(active_order_by_cell.get(cell, ""))
	if oid == "":
		return {"success": false, "reason": "Không có lệnh dọn mặt bằng tại ô này."}
	return cancel_clearing_order(oid, citizen_list)

func _release_order_reservations(order: Dictionary, citizen_list: Array = []) -> void:
	var cid: String = str(order.get("assigned_citizen_id", ""))
	if cid != "":
		for c in citizen_list:
			if c != null and is_instance_valid(c) and str(c.get("citizen_id")) == cid:
				if str(c.get("active_clearing_order_id")) == str(order.get("order_id", "")):
					c.set("active_clearing_order_id", "")
					if c.get("current_state") in [1, 2]: # MOVING_TO_JOB or WORKING
						c.set("current_path", [] as Array[Vector2i])
						c.set("current_state", 0) # IDLE
						c.set("status_reason", "Lệnh dọn mặt bằng đã bị hủy")
				break
	var slot: Vector2i = order.get("work_slot", Vector2i(-1, -1))
	if slot != Vector2i(-1, -1) and reserved_work_slots.get(slot, "") == str(order.get("order_id", "")):
		reserved_work_slots.erase(slot)
	order["assigned_citizen_id"] = ""
	order["work_slot"] = Vector2i(-1, -1)

func _find_legal_work_slot(target_cell: Vector2i, worker_cell: Vector2i, nav: GridNavigation, order_id: String) -> Vector2i:
	if nav == null:
		return Vector2i(-1, -1)
	var has_territory: bool = nav.world_data != null and nav.world_data.owned_cells.size() == nav.world_data.map_width
	var pred: Callable = Callable()
	if has_territory:
		pred = func(c: Vector2i) -> bool:
			return IsoMath.is_in_bounds(c) and bool(nav.world_data.owned_cells[c.x][c.y])
	var neighbors := IsoMath.get_cardinal_neighbors(target_cell)
	var best_slot := Vector2i(-1, -1)
	var best_dist := 999999
	for n in neighbors:
		if not nav.is_cell_walkable(n):
			continue
		if has_territory and not bool(nav.world_data.owned_cells[n.x][n.y]):
			continue
		var holder: String = str(reserved_work_slots.get(n, ""))
		if holder != "" and holder != order_id:
			continue
		if worker_cell != n:
			var path := nav.find_path_with_predicate(worker_cell, n, pred) if has_territory else nav.find_path(worker_cell, n)
			if path.is_empty():
				continue
		var d := IsoMath.grid_distance(worker_cell, n)
		if d < best_dist:
			best_dist = d
			best_slot = n
	return best_slot

func dispatch_orders(world_data: WorldGenerator.WorldData, citizen_list: Array, nav: GridNavigation) -> void:
	if world_data == null or nav == null:
		return

	# 1. Validate existing active reservations (orphan/dead/invalid target cleanup)
	var to_cancel: Array[String] = []
	for oid in orders_by_id.keys():
		var order: Dictionary = orders_by_id[oid]
		var st: int = int(order.get("state", OrderState.CANCELLED))
		if st == OrderState.COMPLETED or st == OrderState.CANCELLED:
			continue
		var cell: Vector2i = order.get("cell", Vector2i(-1, -1))
		var prop := find_prop_at_cell(world_data, cell)
		if prop.is_empty() and st != OrderState.WAITING_FOR_STORAGE:
			to_cancel.append(oid)
			continue

		var cid: String = str(order.get("assigned_citizen_id", ""))
		if cid != "":
			var worker: Object = null
			for c in citizen_list:
				if c != null and is_instance_valid(c) and str(c.get("citizen_id")) == cid:
					worker = c
					break
			var worker_valid: bool = (
				worker != null
				and worker.has_method("is_alive") and bool(worker.call("is_alive"))
				and str(worker.get("role")) == str(order.get("required_role", ""))
				and str(worker.get("active_clearing_order_id")) == oid
			)
			if not worker_valid:
				_release_order_reservations(order, citizen_list)
				if st != OrderState.WAITING_FOR_STORAGE:
					order["state"] = OrderState.QUEUED
					order["status_reason"] = "Đang chờ %s rảnh" % str(order.get("required_role_vn", "Thợ"))

	for oid in to_cancel:
		cancel_clearing_order(oid, citizen_list)

	# 2. Assign QUEUED or BLOCKED orders to nearest eligible reachable worker
	for oid in orders_by_id.keys():
		var order: Dictionary = orders_by_id[oid]
		var st: int = int(order.get("state", OrderState.CANCELLED))
		if st != OrderState.QUEUED and st != OrderState.BLOCKED:
			continue

		var req_role: String = str(order.get("required_role", ""))
		var target_cell: Vector2i = order.get("cell", Vector2i(-1, -1))
		var any_role_worker := false
		var best_worker: Object = null
		var best_slot := Vector2i(-1, -1)
		var best_dist := 999999

		for c in citizen_list:
			if c == null or not is_instance_valid(c):
				continue
			if not (c.has_method("is_alive") and bool(c.call("is_alive"))):
				continue
			if str(c.get("role")) != req_role:
				continue
			any_role_worker = true
			if str(c.get("active_clearing_order_id")) != "":
				continue
			if c.has_method("has_manual_command") and bool(c.call("has_manual_command")):
				continue
			if int(c.get("carrying_amount")) > 0:
				continue
			if float(c.get("fatigue")) >= 85.0 or float(c.get("hunger")) >= 70.0:
				continue
			if int(c.get("current_state")) in [3, 4]: # SEEKING_FOOD, RESTING
				continue
			var c_phase: int = SchedulePolicyScript.TimeManagerScript.DayPhase.DAY
			if c.has_method("_get_current_day_phase"):
				c_phase = int(c.call("_get_current_day_phase"))
			else:
				var ml = Engine.get_main_loop()
				if ml is SceneTree and ml.root != null:
					var tm = ml.root.get_node_or_null("TimeManager")
					if tm != null and tm.has_method("get_day_phase"):
						c_phase = int(tm.call("get_day_phase"))
			if not SchedulePolicyScript.can_accept_autonomous_job(req_role, c_phase):
				continue

			var w_cell: Vector2i = c.get("current_cell")
			var slot := _find_legal_work_slot(target_cell, w_cell, nav, oid)
			if slot == Vector2i(-1, -1):
				continue
			var d := IsoMath.grid_distance(w_cell, slot)
			if d < best_dist:
				best_dist = d
				best_worker = c
				best_slot = slot

		if best_worker != null and best_slot != Vector2i(-1, -1):
			# Release any autonomous job cleanly before reserving for player clearing order
			if best_worker.get("active_job") != null and best_worker.get("job_mgr") != null:
				best_worker.get("job_mgr").release_job(best_worker.get("active_job"))
				best_worker.set("active_job", null)
			best_worker.set("active_clearing_order_id", oid)
			best_worker.set("current_path", [] as Array[Vector2i])
			best_worker.set("current_state", 0) # IDLE -> _process_idle will route to work_slot
			order["assigned_citizen_id"] = str(best_worker.get("citizen_id"))
			order["work_slot"] = best_slot
			reserved_work_slots[best_slot] = oid
			order["state"] = OrderState.RESERVED
			order["status_reason"] = "Đang đi dọn %s tại (%d, %d)" % [
				"cây" if str(order.get("prop_type")) == "tree" else "đá",
				target_cell.x,
				target_cell.y
			]
			clearing_orders_changed.emit()
		else:
			if not any_role_worker:
				order["state"] = OrderState.QUEUED
				order["status_reason"] = "Chưa có %s khả dụng" % str(order.get("required_role_vn", req_role))
			else:
				# Check if any cardinal neighbor is even walkable at all
				var has_any_walkable := false
				for n in IsoMath.get_cardinal_neighbors(target_cell):
					if nav.is_cell_walkable(n):
						has_any_walkable = true
						break
				if not has_any_walkable:
					order["state"] = OrderState.BLOCKED
					order["status_reason"] = "Không tìm được đường đến mục tiêu"
					clearing_order_blocked.emit(oid, order["status_reason"])
				else:
					order["state"] = OrderState.QUEUED
					order["status_reason"] = "Đang chờ %s rảnh" % str(order.get("required_role_vn", req_role))

func complete_or_hold_for_storage(order_id: String, world_data: WorldGenerator.WorldData, rm: Object, world_view: Object = null, citizen_list: Array = []) -> Dictionary:
	if not orders_by_id.has(order_id):
		return {"success": false, "reason": "Không tìm thấy lệnh."}
	var order: Dictionary = orders_by_id[order_id]
	var st: int = int(order.get("state", OrderState.CANCELLED))
	if st == OrderState.COMPLETED or st == OrderState.CANCELLED:
		return {"success": false, "reason": "Lệnh đã kết thúc."}

	# Release worker so citizen is never stuck waiting indefinitely on full storage
	_release_order_reservations(order, citizen_list)

	var tx_id: String = str(order.get("tx_id", ""))
	var prop_id: String = str(order.get("prop_id", ""))
	var p_type: String = str(order.get("prop_type", ""))
	var cell: Vector2i = order.get("cell", Vector2i(-1, -1))
	var res_id: String = str(order.get("reward_resource", ""))
	var amt: int = int(order.get("reward_amount", 0))

	if not committed_reward_tx_ids.has(tx_id):
		if rm == null or not rm.has_method("add_resources_atomic"):
			order["state"] = OrderState.WAITING_FOR_STORAGE
			order["status_reason"] = "Chờ kho khả dụng để nhận %d %s" % [amt, res_id]
			clearing_orders_changed.emit()
			return {"success": false, "waiting_storage": true}
		committed_reward_tx_ids[tx_id] = true
		var tx_res: Dictionary = rm.call("add_resources_atomic", {res_id: amt})
		if not bool(tx_res.get("success", false)):
			committed_reward_tx_ids.erase(tx_id)
			order["state"] = OrderState.WAITING_FOR_STORAGE
			order["status_reason"] = "Kho đầy, chờ chỗ chứa %d %s" % [amt, res_id]
			clearing_order_waiting_storage.emit(order_id, res_id, amt)
			clearing_orders_changed.emit()
			return {"success": false, "waiting_storage": true}

	# Reward safely committed -> permanently remove prop from authoritative world_data & occupancy
	cleared_prop_ids[prop_id] = true
	if world_data != null:
		for i in range(world_data.props.size() - 1, -1, -1):
			if world_data.props[i].get("cell", Vector2i(-1, -1)) == cell:
				world_data.props.remove_at(i)
				break
		if IsoMath.is_in_bounds(cell) and not _is_cell_protected(world_data, cell, null):
			var t_type: int = world_data.terrain[cell.x][cell.y]
			var is_v2_mtn: bool = (world_data.generator_version == WorldGenerator.BATCH03_GENERATOR_VERSION and t_type == WorldGenerator.TerrainType.MOUNTAINS)
			if not is_v2_mtn:
				world_data.occupancy[cell.x][cell.y] = false

	if world_view != null and world_view.has_method("remove_prop_visual_at_cell"):
		world_view.call("remove_prop_visual_at_cell", cell)

	order["state"] = OrderState.COMPLETED
	order["status_reason"] = "Đã hoàn tất dọn mặt bằng"
	if active_order_by_cell.get(cell, "") == order_id:
		active_order_by_cell.erase(cell)
	orders_by_id.erase(order_id)

	prop_cleared.emit(prop_id, p_type, cell, res_id, amt)
	clearing_orders_changed.emit()
	return {"success": true, "prop_id": prop_id, "reward_resource": res_id, "reward_amount": amt}

func try_finalize_waiting_orders(world_data: WorldGenerator.WorldData, rm: Object, world_view: Object = null, citizen_list: Array = []) -> void:
	if _finalizing_waiting:
		return
	_finalizing_waiting = true
	for oid in orders_by_id.keys():
		var order: Dictionary = orders_by_id[oid]
		if int(order.get("state", -1)) == OrderState.WAITING_FOR_STORAGE:
			complete_or_hold_for_storage(oid, world_data, rm, world_view, citizen_list)
	_finalizing_waiting = false

func apply_cleared_props_to_world_data(world_data: WorldGenerator.WorldData, world_seed: int, gen_ver: int) -> void:
	if world_data == null or cleared_prop_ids.is_empty():
		return
	for i in range(world_data.props.size() - 1, -1, -1):
		var p: Dictionary = world_data.props[i]
		var p_type: String = str(p.get("type", ""))
		var cell: Vector2i = p.get("cell", Vector2i(-1, -1))
		var pid: String = make_prop_id(world_seed, gen_ver, p_type, cell)
		if cleared_prop_ids.has(pid):
			world_data.props.remove_at(i)

func serialize() -> Dictionary:
	var saved_orders: Array[Dictionary] = []
	for oid in orders_by_id:
		var o: Dictionary = orders_by_id[oid]
		var c: Vector2i = o.get("cell", Vector2i(-1, -1))
		var ws: Vector2i = o.get("work_slot", Vector2i(-1, -1))
		saved_orders.append({
			"order_id": str(o.get("order_id", "")),
			"prop_id": str(o.get("prop_id", "")),
			"prop_type": str(o.get("prop_type", "")),
			"cell": [c.x, c.y],
			"required_role": str(o.get("required_role", "")),
			"required_role_vn": str(o.get("required_role_vn", "")),
			"skill": str(o.get("skill", "")),
			"work_hours_required": float(o.get("work_hours_required", 4.0)),
			"work_hours_done": float(o.get("work_hours_done", 0.0)),
			"reward_resource": str(o.get("reward_resource", "")),
			"reward_amount": int(o.get("reward_amount", 0)),
			"tx_id": str(o.get("tx_id", "")),
			"state": int(o.get("state", OrderState.QUEUED)),
			"assigned_citizen_id": str(o.get("assigned_citizen_id", "")),
			"work_slot": [ws.x, ws.y],
			"status_reason": str(o.get("status_reason", ""))
		})
	return {
		"next_order_seq": _next_order_seq,
		"cleared_prop_ids": cleared_prop_ids.keys(),
		"committed_reward_tx_ids": committed_reward_tx_ids.keys(),
		"orders": saved_orders
	}

func deserialize(data: Dictionary) -> void:
	clear_all()
	if data.is_empty():
		return
	_next_order_seq = maxi(1, int(data.get("next_order_seq", 1)))
	for pid in data.get("cleared_prop_ids", []):
		cleared_prop_ids[str(pid)] = true
	for tx in data.get("committed_reward_tx_ids", []):
		committed_reward_tx_ids[str(tx)] = true
	for raw_o in data.get("orders", []):
		if not (raw_o is Dictionary):
			continue
		var c_arr: Array = raw_o.get("cell", [-1, -1])
		var cell := Vector2i(int(c_arr[0]), int(c_arr[1])) if c_arr.size() >= 2 else Vector2i(-1, -1)
		var ws_arr: Array = raw_o.get("work_slot", [-1, -1])
		var ws := Vector2i(int(ws_arr[0]), int(ws_arr[1])) if ws_arr.size() >= 2 else Vector2i(-1, -1)
		var oid: String = str(raw_o.get("order_id", ""))
		if oid == "":
			continue
		var order: Dictionary = {
			"order_id": oid,
			"prop_id": str(raw_o.get("prop_id", "")),
			"prop_type": str(raw_o.get("prop_type", "")),
			"cell": cell,
			"required_role": str(raw_o.get("required_role", "")),
			"required_role_vn": str(raw_o.get("required_role_vn", "")),
			"skill": str(raw_o.get("skill", "")),
			"work_hours_required": float(raw_o.get("work_hours_required", 4.0)),
			"work_hours_done": float(raw_o.get("work_hours_done", 0.0)),
			"reward_resource": str(raw_o.get("reward_resource", "")),
			"reward_amount": int(raw_o.get("reward_amount", 0)),
			"tx_id": str(raw_o.get("tx_id", "")),
			"state": int(raw_o.get("state", OrderState.QUEUED)),
			"assigned_citizen_id": str(raw_o.get("assigned_citizen_id", "")),
			"work_slot": ws,
			"status_reason": str(raw_o.get("status_reason", ""))
		}
		orders_by_id[oid] = order
		var st: int = int(order["state"])
		if st != OrderState.COMPLETED and st != OrderState.CANCELLED:
			active_order_by_cell[cell] = oid
			if ws != Vector2i(-1, -1):
				reserved_work_slots[ws] = oid
	clearing_orders_changed.emit()
