class_name CookhouseManager
extends RefCounted
## Centralized manager for Cookhouse buildings, production queues, atomic ingredient consumption,
## pending full-storage outputs, and save/load persistence.

signal cookhouse_changed(building_id: String)

var cookhouses: Dictionary = {} # building_id (String) -> Dictionary

func clear_all() -> void:
	cookhouses.clear()

func _make_entry(b_id: String) -> Dictionary:
	return {
		"building_id": b_id,
		"active_recipe_id": "",
		"progress_hours": 0.0,
		"queue": [],
		"paused": false,
		"waiting_ingredients": false,
		"pending_output_resource": "",
		"pending_output_amount": 0,
		"_retry_timer": 0.0,
	}

func register_cookhouse(b_id: String) -> Dictionary:
	if b_id == "":
		return {}
	if not cookhouses.has(b_id):
		cookhouses[b_id] = _make_entry(b_id)
		cookhouse_changed.emit(b_id)
	return cookhouses[b_id]

func unregister_cookhouse(b_id: String) -> void:
	if cookhouses.has(b_id):
		cookhouses.erase(b_id)
		cookhouse_changed.emit(b_id)

func has_cookhouse(b_id: String) -> bool:
	return cookhouses.has(b_id)

func get_cookhouse(b_id: String) -> Dictionary:
	return cookhouses.get(b_id, {})

func get_total_batch_count(b_id: String) -> int:
	if not cookhouses.has(b_id):
		return 0
	var entry: Dictionary = cookhouses[b_id]
	var cnt: int = (entry["queue"] as Array).size()
	if str(entry.get("active_recipe_id", "")) != "":
		cnt += 1
	return cnt

func can_remove_cookhouse(b_id: String) -> Dictionary:
	if not cookhouses.has(b_id):
		return {"can_remove": true, "reason": ""}
	var entry: Dictionary = cookhouses[b_id]
	if str(entry.get("active_recipe_id", "")) != "":
		return {"can_remove": false, "reason": "Nhà Bếp đang có mẻ nấu đang thực hiện, hãy chờ hoàn tất trước khi dỡ bỏ"}
	if int(entry.get("pending_output_amount", 0)) > 0:
		return {"can_remove": false, "reason": "Nhà Bếp còn món ăn đã nấu xong chờ nhập kho, hãy giải phóng kho trước khi dỡ bỏ"}
	return {"can_remove": true, "reason": ""}

func sync_from_world_data(world_data: WorldGenerator.WorldData) -> void:
	if world_data == null:
		return
	var active_ids: Dictionary = {}
	for b in world_data.buildings:
		if str(b.get("type", "")) == "cookhouse" and str(b.get("state", "active")) == "active":
			var bid: String = str(b.get("id", ""))
			if bid != "":
				active_ids[bid] = true
				register_cookhouse(bid)
	var to_remove: Array[String] = []
	for bid in cookhouses.keys():
		if not active_ids.has(bid):
			to_remove.append(str(bid))
	for bid in to_remove:
		unregister_cookhouse(bid)

func add_batch(b_id: String, recipe_id: String, resource_mgr: Object = null) -> Dictionary:
	if not cookhouses.has(b_id):
		return {"success": false, "reason": "Nhà Bếp chưa sẵn sàng"}
	var recipe := CookhouseConfig.get_recipe(recipe_id)
	if recipe.is_empty():
		return {"success": false, "reason": "Công thức không hợp lệ"}
	if get_total_batch_count(b_id) >= CookhouseConfig.MAX_QUEUE_SIZE:
		return {"success": false, "reason": "Hàng đợi đã đầy (tối đa %d mẻ)" % CookhouseConfig.MAX_QUEUE_SIZE}
	var entry: Dictionary = cookhouses[b_id]
	(entry["queue"] as Array).append(recipe_id)
	entry["_retry_timer"] = 0.0
	if resource_mgr != null and not bool(entry.get("paused", false)) and str(entry.get("active_recipe_id", "")) == "" and int(entry.get("pending_output_amount", 0)) <= 0:
		_try_start_next_batch(entry, resource_mgr)
	cookhouse_changed.emit(b_id)
	return {"success": true, "reason": ""}

func remove_pending_batch(b_id: String, queue_index: int) -> bool:
	if not cookhouses.has(b_id):
		return false
	var entry: Dictionary = cookhouses[b_id]
	var q: Array = entry["queue"]
	if queue_index < 0 or queue_index >= q.size():
		return false
	q.remove_at(queue_index)
	if q.is_empty():
		entry["waiting_ingredients"] = false
	cookhouse_changed.emit(b_id)
	return true

func set_paused(b_id: String, is_paused: bool) -> void:
	if not cookhouses.has(b_id):
		return
	var entry: Dictionary = cookhouses[b_id]
	if bool(entry.get("paused", false)) != is_paused:
		entry["paused"] = is_paused
		if not is_paused:
			entry["_retry_timer"] = 0.0
		cookhouse_changed.emit(b_id)

func _get_available_space(resource_mgr: Object, res_id: String) -> int:
	if resource_mgr == null:
		return 0
	var cap: int = 200
	if resource_mgr.has_method("get_storage_capacity"):
		cap = int(resource_mgr.get_storage_capacity(res_id))
	var cur: int = int(resource_mgr.get_total_stock(res_id)) if resource_mgr.has_method("get_total_stock") else 0
	return maxi(0, cap - cur)

func _deposit_output(entry: Dictionary, out_res: String, out_amt: int, resource_mgr: Object) -> void:
	if out_amt <= 0 or out_res == "" or resource_mgr == null or not resource_mgr.has_method("add_resource"):
		return
	var space: int = _get_available_space(resource_mgr, out_res)
	if space <= 0:
		entry["pending_output_resource"] = out_res
		entry["pending_output_amount"] = int(entry.get("pending_output_amount", 0)) + out_amt
		return
	var to_add: int = mini(out_amt, space)
	var added: int = int(resource_mgr.add_resource(out_res, to_add))
	var rem: int = out_amt - added
	if rem > 0:
		entry["pending_output_resource"] = out_res
		entry["pending_output_amount"] = int(entry.get("pending_output_amount", 0)) + rem

func _try_flush_pending_output(entry: Dictionary, resource_mgr: Object) -> bool:
	var pend_amt: int = int(entry.get("pending_output_amount", 0))
	if pend_amt <= 0:
		return true
	var pend_res: String = str(entry.get("pending_output_resource", ""))
	if pend_res == "" or resource_mgr == null or not resource_mgr.has_method("add_resource"):
		return false
	var space: int = _get_available_space(resource_mgr, pend_res)
	if space <= 0:
		return false
	var to_add: int = mini(pend_amt, space)
	var added: int = int(resource_mgr.add_resource(pend_res, to_add))
	if added > 0:
		pend_amt -= added
		entry["pending_output_amount"] = maxi(0, pend_amt)
		if pend_amt <= 0:
			entry["pending_output_resource"] = ""
		cookhouse_changed.emit(str(entry["building_id"]))
	return int(entry.get("pending_output_amount", 0)) <= 0

func _try_start_next_batch(entry: Dictionary, resource_mgr: Object) -> bool:
	if bool(entry.get("paused", false)):
		return false
	if str(entry.get("active_recipe_id", "")) != "":
		return false
	if int(entry.get("pending_output_amount", 0)) > 0:
		return false
	var q: Array = entry["queue"]
	if q.is_empty():
		entry["waiting_ingredients"] = false
		return false
	if resource_mgr == null or not resource_mgr.has_method("get_available_stock") or not resource_mgr.has_method("consume_resource"):
		entry["waiting_ingredients"] = true
		return false

	var next_recipe_id: String = str(q[0])
	var recipe := CookhouseConfig.get_recipe(next_recipe_id)
	if recipe.is_empty():
		q.remove_at(0)
		return false

	var inputs: Dictionary = recipe.get("inputs", {})
	for res_id in inputs.keys():
		var req: int = int(inputs[res_id])
		if int(resource_mgr.get_available_stock(str(res_id))) < req:
			entry["waiting_ingredients"] = true
			entry["_retry_timer"] = 0.25
			return false

	# Atomic deduction: all ingredients verified available
	for res_id in inputs.keys():
		var req: int = int(inputs[res_id])
		if not bool(resource_mgr.consume_resource(str(res_id), req)):
			entry["waiting_ingredients"] = true
			entry["_retry_timer"] = 0.25
			return false

	q.remove_at(0)
	entry["active_recipe_id"] = next_recipe_id
	entry["progress_hours"] = 0.0
	entry["waiting_ingredients"] = false
	entry["_retry_timer"] = 0.0
	cookhouse_changed.emit(str(entry["building_id"]))
	return true

func advance_production(delta_hours: float, resource_mgr: Object) -> void:
	if delta_hours <= 0.0 or cookhouses.is_empty() or resource_mgr == null:
		return
	for b_id in cookhouses.keys():
		var entry: Dictionary = cookhouses[b_id]
		if int(entry.get("pending_output_amount", 0)) > 0:
			if not _try_flush_pending_output(entry, resource_mgr):
				continue
		if bool(entry.get("paused", false)):
			continue
		var active_id: String = str(entry.get("active_recipe_id", ""))
		if active_id != "":
			var recipe := CookhouseConfig.get_recipe(active_id)
			if recipe.is_empty():
				entry["active_recipe_id"] = ""
				entry["progress_hours"] = 0.0
				continue
			var dur: float = maxf(0.1, float(recipe.get("duration_hours", 1.0)))
			entry["progress_hours"] = float(entry.get("progress_hours", 0.0)) + delta_hours
			if float(entry["progress_hours"]) >= dur:
				entry["active_recipe_id"] = ""
				entry["progress_hours"] = 0.0
				var out_res: String = str(recipe.get("output_resource", ""))
				var out_amt: int = int(recipe.get("output_amount", 1))
				_deposit_output(entry, out_res, out_amt, resource_mgr)
				cookhouse_changed.emit(str(b_id))
				if int(entry.get("pending_output_amount", 0)) <= 0 and not (entry["queue"] as Array).is_empty():
					_try_start_next_batch(entry, resource_mgr)
		elif not (entry["queue"] as Array).is_empty():
			var rt: float = float(entry.get("_retry_timer", 0.0)) - delta_hours
			entry["_retry_timer"] = maxf(0.0, rt)
			if float(entry["_retry_timer"]) <= 0.0:
				_try_start_next_batch(entry, resource_mgr)

func serialize() -> Dictionary:
	var list: Array = []
	for b_id in cookhouses.keys():
		var entry: Dictionary = cookhouses[b_id]
		list.append({
			"building_id": str(entry.get("building_id", b_id)),
			"active_recipe_id": str(entry.get("active_recipe_id", "")),
			"progress_hours": float(entry.get("progress_hours", 0.0)),
			"queue": (entry.get("queue", []) as Array).duplicate(),
			"paused": bool(entry.get("paused", false)),
			"waiting_ingredients": bool(entry.get("waiting_ingredients", false)),
			"pending_output_resource": str(entry.get("pending_output_resource", "")),
			"pending_output_amount": int(entry.get("pending_output_amount", 0)),
		})
	return {
		"version": 1,
		"cookhouses": list,
	}

func deserialize(saved_data: Variant, world_data: WorldGenerator.WorldData = null) -> void:
	clear_all()
	if saved_data is Dictionary and saved_data.has("cookhouses") and saved_data["cookhouses"] is Array:
		for item in saved_data["cookhouses"]:
			if not (item is Dictionary):
				continue
			var b_id: String = str(item.get("building_id", ""))
			if b_id == "":
				continue
			if world_data != null:
				var b_data := BuildingSystem.get_building_by_id(b_id, world_data)
				if b_data.is_empty() or str(b_data.get("type", "")) != "cookhouse" or str(b_data.get("state", "active")) != "active":
					continue
			var entry := _make_entry(b_id)
			var active_id: String = str(item.get("active_recipe_id", ""))
			if active_id != "" and not CookhouseConfig.get_recipe(active_id).is_empty():
				entry["active_recipe_id"] = active_id
				entry["progress_hours"] = maxf(0.0, float(item.get("progress_hours", 0.0)))
			var raw_q = item.get("queue", [])
			if raw_q is Array:
				var max_pending: int = CookhouseConfig.MAX_QUEUE_SIZE - (1 if entry["active_recipe_id"] != "" else 0)
				for r in raw_q:
					var rid: String = str(r)
					if not CookhouseConfig.get_recipe(rid).is_empty() and (entry["queue"] as Array).size() < max_pending:
						(entry["queue"] as Array).append(rid)
			entry["paused"] = bool(item.get("paused", false))
			entry["waiting_ingredients"] = bool(item.get("waiting_ingredients", false))
			var p_amt: int = int(item.get("pending_output_amount", 0))
			var p_res: String = str(item.get("pending_output_resource", ""))
			if p_amt > 0 and p_res != "":
				entry["pending_output_resource"] = p_res
				entry["pending_output_amount"] = p_amt
			cookhouses[b_id] = entry
	if world_data != null:
		sync_from_world_data(world_data)
