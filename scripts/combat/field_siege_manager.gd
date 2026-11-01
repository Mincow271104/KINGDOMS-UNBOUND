class_name FieldSiegeManager
extends RefCounted
## Field Siege Manager (Package 1X)
## Authoritative coordinator for tactical field siege operations on hostile outposts.
## Manages eligibility gating, outpost objectives, defender mobilization,
## tactical victory/defeat/withdrawal resolution, plunder awards, and faction power impact.

const SiegeObjectiveActorScript = preload("res://scripts/combat/siege_objective_actor.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")

signal field_siege_started(siege_id: String, faction_id: String, objective_id: String)
signal field_siege_resolved(siege_id: String, outcome: String, details: Dictionary)
signal objective_registered(objective_id: String, cell: Vector2i, faction_id: String)
signal outpost_ownership_changed(objective_id: String, prev_owner: String, new_owner: String, tx_id: String)

var world_view: Node = null
var faction_mgr: Object = null
var player_army_mgr: Object = null
var enemy_military_mgr: Object = null
var resource_mgr: Object = null
var objectives_container: Node = null

var objectives: Dictionary = {} # objective_id: String -> SiegeObjectiveActor
var active_sieges: Dictionary = {} # siege_id: String -> Dictionary
var next_siege_index: int = 1

const SIEGE_RADIUS: int = 12
const PLUNDER_REWARDS: Dictionary = {
	"gold": 60,
	"food": 40,
	"wood": 30,
	"metal": 20
}

func _init(wv: Node = null, fm: Object = null, army_mgr: Object = null, enemy_mgr: Object = null) -> void:
	world_view = wv
	faction_mgr = fm
	player_army_mgr = army_mgr
	enemy_military_mgr = enemy_mgr
	objectives = {}
	active_sieges = {}
	next_siege_index = 1

func set_world_view(wv: Node) -> void:
	world_view = wv

func set_faction_manager(fm: Object) -> void:
	faction_mgr = fm

func set_player_army_manager(army_mgr: Object) -> void:
	player_army_mgr = army_mgr

func set_enemy_military_manager(enemy_mgr: Object) -> void:
	enemy_military_mgr = enemy_mgr
	if enemy_military_mgr != null and enemy_military_mgr.has_method("set_field_siege_manager"):
		enemy_military_mgr.set_field_siege_manager(self)

func set_resource_manager(rm: Object) -> void:
	resource_mgr = rm

func set_objectives_container(container: Node) -> void:
	objectives_container = container

func get_resource_manager() -> Object:
	if resource_mgr != null:
		return resource_mgr
	if is_instance_valid(world_view) and world_view.get("resource_manager") != null:
		return world_view.get("resource_manager")
	if Engine.has_singleton("ResourceManager"):
		return Engine.get_singleton("ResourceManager")
	if is_instance_valid(world_view) and world_view.is_inside_tree() and world_view.has_node("/root/ResourceManager"):
		return world_view.get_node("/root/ResourceManager")
	return null

func get_faction_manager() -> Object:
	if faction_mgr != null:
		return faction_mgr
	if is_instance_valid(world_view) and world_view.get("faction_manager") != null:
		return world_view.get("faction_manager")
	return null

func get_player_army_manager() -> Object:
	if player_army_mgr != null:
		return player_army_mgr
	if is_instance_valid(world_view) and world_view.get("player_army_mgr") != null:
		return world_view.get("player_army_mgr")
	return null

func get_enemy_military_manager() -> Object:
	if enemy_military_mgr != null:
		return enemy_military_mgr
	if is_instance_valid(world_view) and world_view.get("enemy_military_mgr") != null:
		return world_view.get("enemy_military_mgr")
	return null

# -----------------------------------------------------------------------------
# Outpost Objectives Management
# -----------------------------------------------------------------------------

func register_objective(obj_id: String, cell: Vector2i, faction_id: String, max_hp: float = 250.0, garrison: int = 3) -> Node2D:
	if objectives.has(obj_id):
		return objectives[obj_id]

	var obj = SiegeObjectiveActorScript.new()
	obj.objective_id = obj_id
	obj.objective_name = "Tiền Đồn %s" % faction_id.capitalize()
	obj.owning_faction_id = faction_id
	obj.original_owner_id = faction_id
	obj.previous_owner_id = ""
	obj.capture_revision = 0
	obj.last_capture_tx_id = ""
	obj.current_cell = cell
	obj.max_health = max_hp
	obj.health = max_hp
	obj.garrison_count = garrison

	obj.objective_destroyed.connect(_on_objective_destroyed)

	var container = _get_container()
	if container != null and is_instance_valid(container):
		container.add_child(obj)

	objectives[obj_id] = obj
	objective_registered.emit(obj_id, cell, faction_id)
	return obj

func is_valid_owner_id(owner_id: String) -> bool:
	if owner_id.strip_edges().is_empty():
		return false
	if owner_id == "player":
		return true
	var fm = get_faction_manager()
	if fm != null and fm.has_method("get_faction"):
		return fm.get_faction(owner_id) != null
	return true

## Authoritative outpost territorial transfer method with strict idempotency and validation.
func transfer_outpost_ownership(obj_id: String, new_owner_id: String, tx_id: String = "") -> Dictionary:
	var obj = get_objective(obj_id)
	if obj == null or not is_instance_valid(obj):
		return {
			"success": false,
			"already_applied": false,
			"reason": "Mục tiêu tiền đồn không tồn tại: %s" % obj_id
		}

	if not is_valid_owner_id(new_owner_id):
		return {
			"success": false,
			"already_applied": false,
			"reason": "Chủ sở hữu mới không hợp lệ hoặc chưa được xác thực: %s" % new_owner_id
		}

	var prev_owner := str(obj.owning_faction_id)
	var res: Dictionary = obj.transfer_ownership(new_owner_id, tx_id)
	if bool(res.get("success", false)) and not bool(res.get("already_applied", false)):
		outpost_ownership_changed.emit(obj_id, prev_owner, new_owner_id, tx_id)
	return res

func get_objective(obj_id: String) -> Node2D:
	return objectives.get(obj_id, null)

func get_all_objectives() -> Array:
	return objectives.values()

func _get_container() -> Node:
	if objectives_container != null and is_instance_valid(objectives_container):
		return objectives_container
	if is_instance_valid(world_view):
		var existing = world_view.get_node_or_null("SiegeObjectivesContainer")
		if existing != null:
			return existing
		var new_container := Node2D.new()
		new_container.name = "SiegeObjectivesContainer"
		new_container.y_sort_enabled = true
		world_view.add_child(new_container)
		objectives_container = new_container
		return new_container
	return null

# -----------------------------------------------------------------------------
# Eligibility & Operation Launch
# -----------------------------------------------------------------------------

func can_launch_field_siege(target_faction_id: String, objective_id: String) -> Dictionary:
	var fm = get_faction_manager()
	if fm == null:
		return {"can_launch": false, "reason": "Không tìm thấy FactionManager"}

	var fac = null
	if fm.has_method("get_faction"):
		fac = fm.get_faction(target_faction_id)
	if fac == null:
		return {"can_launch": false, "reason": "Thế lực mục tiêu không tồn tại"}

	if fac.get("existence_status") != null and fac.get("existence_status") != "active":
		return {"can_launch": false, "reason": "Không thể công thành thế lực không còn hoạt động"}

	var is_war: bool = false
	if fac.get("is_at_war") != null:
		is_war = bool(fac.is_at_war)
	elif fm.has_method("are_factions_at_war"):
		is_war = fm.are_factions_at_war(target_faction_id, "player")

	if not is_war:
		return {"can_launch": false, "reason": "Chưa tuyên chiến với thế lực này"}

	var obj = get_objective(objective_id)
	if obj == null:
		return {"can_launch": false, "reason": "Mục tiêu công thành không tồn tại"}

	# Fixture reset compatibility: if marked not captured but left as player, restore original owner
	if not obj.is_captured and not obj.original_owner_id.is_empty() and obj.owning_faction_id == "player":
		obj.owning_faction_id = obj.original_owner_id

	if not obj.is_alive:
		return {"can_launch": false, "reason": "Mục tiêu công thành đã bị phá hủy"}
	if obj.owning_faction_id == "player":
		return {"can_launch": false, "reason": "Không thể công thành tiền đồn thuộc quyền kiểm soát của bạn"}
	if obj.owning_faction_id != target_faction_id:
		return {"can_launch": false, "reason": "Mục tiêu không thuộc thế lực chỉ định"}

	var army = get_player_army_manager()
	if army == null:
		return {"can_launch": false, "reason": "Không tìm thấy PlayerArmyManager"}

	var field_troops: int = army.get_field_unit_count() if army.has_method("get_field_unit_count") else 0
	if field_troops <= 0:
		return {"can_launch": false, "reason": "Cần có ít nhất một đơn vị dã chiến bên ngoài căn cứ để công thành"}

	# Army must be in the field and within reasonable range of objective
	var dist: int = IsoMath.grid_distance(army.get_current_cell(), obj.current_cell)
	if dist > SIEGE_RADIUS:
		return {"can_launch": false, "reason": "Quân dã chiến ở quá xa mục tiêu (%d ô > tối đa %d ô)" % [dist, SIEGE_RADIUS]}

	# Check if already sieging this objective
	for s in active_sieges.values():
		if s.get("objective_id") == objective_id and s.get("status") == "active":
			return {"can_launch": false, "reason": "Chiến dịch công thành mục tiêu này đang diễn ra"}

	return {"can_launch": true, "reason": ""}

func launch_field_siege(target_faction_id: String, objective_id: String) -> Dictionary:
	var check: Dictionary = can_launch_field_siege(target_faction_id, objective_id)
	if not bool(check.get("can_launch", false)):
		return {
			"success": false,
			"reason": check.get("reason", "Không thể phát động công thành"),
			"siege_id": ""
		}

	var obj = get_objective(objective_id)
	var em = get_enemy_military_manager()

	# Mobilize garrison defenders around objective:
	# Reuse living existing defenders, assign eligible nearby faction units, and spawn only missing defenders.
	var defender_ids: Array[String] = []
	if em != null and obj != null:
		var living_defenders: Array[TacticalUnit] = []
		for uid in obj.defending_unit_ids:
			var u = em.get_enemy(uid)
			if u != null and is_instance_valid(u) and u.is_alive and not living_defenders.has(u):
				living_defenders.append(u)

		if em.has_method("get_garrison_defenders_by_objective"):
			var assigned = em.get_garrison_defenders_by_objective(objective_id)
			for u in assigned:
				if u != null and is_instance_valid(u) and u.is_alive and not living_defenders.has(u):
					living_defenders.append(u)

		# If still below target garrison capacity, reuse unassigned faction units in proximity
		if living_defenders.size() < obj.garrison_count and em.has_method("get_enemies_by_faction"):
			var faction_units: Array = em.get_enemies_by_faction(target_faction_id)
			for u in faction_units:
				if living_defenders.size() >= obj.garrison_count:
					break
				if u != null and is_instance_valid(u) and u.is_alive and not living_defenders.has(u):
					if not u.get("is_garrison_defender") or u.get("assigned_objective_id") == "":
						var dist: int = IsoMath.grid_distance(u.current_cell, obj.current_cell)
						if dist <= 8:
							u.is_garrison_defender = true
							u.assigned_objective_id = objective_id
							living_defenders.append(u)

		# Spawn only genuinely missing defenders up to garrison_count
		var needed: int = maxi(0, obj.garrison_count - living_defenders.size())
		var new_defenders: Array[TacticalUnit] = []
		if needed > 0:
			var nav = em.get_nav() if em.has_method("get_nav") else null
			new_defenders = em.spawn_enemy_force(target_faction_id, obj.current_cell, needed, nav, true, true, objective_id)

		for d in living_defenders:
			if d != null and is_instance_valid(d):
				defender_ids.append(d.unit_id)
				d.patrol_origin = obj.current_cell
				d.patrol_radius = 4
				d.is_garrison_defender = true
				d.assigned_objective_id = objective_id
				if d.has_method("set_ai_state"):
					d.set_ai_state(0) # 0 = HOLD

		for d in new_defenders:
			if d != null and is_instance_valid(d):
				defender_ids.append(d.unit_id)
				d.patrol_origin = obj.current_cell
				d.patrol_radius = 4
				d.is_garrison_defender = true
				d.assigned_objective_id = objective_id
				if d.has_method("set_ai_state"):
					d.set_ai_state(0) # 0 = HOLD

		obj.defending_unit_ids = defender_ids

	var s_id := "siege_%d" % next_siege_index
	next_siege_index += 1

	if obj != null:
		obj.is_under_active_siege = true

	var army = get_player_army_manager()
	var init_total: int = army.get_army_count() if (army != null and army.has_method("get_army_count")) else 0
	var init_garrison: int = army.get_defending_soldier_count() if (army != null and army.has_method("get_defending_soldier_count")) else 0
	var siege_record: Dictionary = {
		"siege_id": s_id,
		"faction_id": target_faction_id,
		"objective_id": objective_id,
		"status": "active",
		"defending_unit_ids": defender_ids,
		"initial_soldier_count": init_total,
		"initial_garrison_count": init_garrison
	}
	active_sieges[s_id] = siege_record
	field_siege_started.emit(s_id, target_faction_id, objective_id)

	return {
		"success": true,
		"reason": "Phát động công thành thành công",
		"siege_id": s_id,
		"defenders": defender_ids.size()
	}

func is_siege_active_for_objective(obj_id: String) -> bool:
	for s in active_sieges.values():
		if s.get("objective_id") == obj_id and s.get("status") == "active":
			return true
	return false

func cancel_active_sieges_for_faction(faction_id: String, reason: String = "WITHDRAWAL") -> void:
	for s_id in active_sieges.keys():
		var s = active_sieges[s_id]
		if s.get("faction_id") == faction_id and s.get("status") == "active":
			var obj = get_objective(s.get("objective_id", ""))
			if obj != null:
				obj.is_under_active_siege = false
			_resolve_siege_outcome(s_id, reason)

# -----------------------------------------------------------------------------
# Evaluation & Victory Conditions
# -----------------------------------------------------------------------------

func evaluate_siege_status(siege_id: String) -> Dictionary:
	if not active_sieges.has(siege_id):
		return {"status": "not_found", "outcome": "NONE"}

	var record: Dictionary = active_sieges[siege_id]
	if record.get("status") != "active":
		return {"status": record.get("status"), "outcome": record.get("outcome", "NONE"), "details": record.get("details", {})}

	var obj_id: String = record.get("objective_id", "")
	var obj = get_objective(obj_id)
	var faction_id: String = record.get("faction_id", "")
	var army = get_player_army_manager()

	# Victory Check: Outpost destroyed or captured
	if obj != null and (not obj.is_alive or obj.is_captured):
		return _resolve_siege_outcome(siege_id, "VICTORY")

	# Total army wipeout is always DEFEAT
	var total_soldiers: int = army.get_army_count() if (army != null and army.has_method("get_army_count")) else 0
	if total_soldiers <= 0:
		return _resolve_siege_outcome(siege_id, "DEFEAT")

	var tac_mgr = army.get("tactical_military_mgr") if army != null else null
	if tac_mgr != null and tac_mgr.has_method("get_all_field_units"):
		var rally_c: Vector2i = army.get_rally_cell() if army.has_method("get_rally_cell") else Vector2i(32, 33)
		var raw_field: Array = tac_mgr.get_all_field_units(rally_c)
		var living_field: Array = []
		for u in raw_field:
			if u != null and is_instance_valid(u) and (u.get("is_alive") == null or bool(u.get("is_alive"))) and float(u.get("health") if u.get("health") != null else 100.0) > 0.0:
				living_field.append(u)

		if living_field.is_empty():
			# No living units remain in the field: distinguish combat elimination of field force from return to garrison
			var init_total: int = int(record.get("initial_soldier_count", total_soldiers))
			var init_garrison: int = int(record.get("initial_garrison_count", 0))
			var cur_garrison: int = tac_mgr.get_garrisoned_unit_count(rally_c) if tac_mgr.has_method("get_garrisoned_unit_count") else total_soldiers
			if total_soldiers < init_total and cur_garrison <= init_garrison:
				return _resolve_siege_outcome(siege_id, "DEFEAT")
			return _resolve_siege_outcome(siege_id, "WITHDRAWAL")

		if obj != null:
			var in_siege_zone: int = 0
			for u in living_field:
				if IsoMath.grid_distance(u.current_cell, obj.current_cell) <= (SIEGE_RADIUS + 4):
					in_siege_zone += 1
			if in_siege_zone == 0:
				return _resolve_siege_outcome(siege_id, "WITHDRAWAL")
	else:
		# Strategic-only fallback when no TacticalMilitaryManager is attached
		if army != null and obj != null:
			var dist: int = IsoMath.grid_distance(army.get_current_cell(), obj.current_cell)
			if dist > (SIEGE_RADIUS + 4) or (army.get_movement_state() == PlayerArmyManager.MovementState.GARRISONED and army.get_current_cell() == army.get_rally_cell()):
				return _resolve_siege_outcome(siege_id, "WITHDRAWAL")
		var field_troops: int = army.get_field_unit_count() if (army != null and army.has_method("get_field_unit_count")) else 0
		if field_troops <= 0:
			return _resolve_siege_outcome(siege_id, "DEFEAT")

	return {"status": "active", "outcome": "NONE"}

func _resolve_siege_outcome(siege_id: String, outcome: String) -> Dictionary:
	if not active_sieges.has(siege_id):
		return {}

	var record: Dictionary = active_sieges[siege_id]
	if record.get("status") != "active":
		return {
			"status": record.get("status", "resolved"),
			"outcome": record.get("outcome", outcome),
			"details": record.get("details", {})
		}

	record["status"] = "resolved"
	record["outcome"] = outcome

	var obj = get_objective(record.get("objective_id", ""))
	if obj != null:
		obj.is_under_active_siege = false

	var details: Dictionary = {"outcome": outcome}
	var faction_id: String = record.get("faction_id", "")

	if outcome == "VICTORY":
		# 1. Reduce target faction military power
		var fm = get_faction_manager()
		if fm != null and fm.has_method("get_faction"):
			var fac = fm.get_faction(faction_id)
			if fac != null:
				fac.military_power = maxf(0.0, fac.military_power - 20.0)
				details["faction_military_power"] = fac.military_power

		# 2. Award plunder resources (recording actual added amounts)
		var rm = get_resource_manager()
		var plunder: Dictionary = {}
		for r_type in PLUNDER_REWARDS:
			var req_amt: int = int(PLUNDER_REWARDS[r_type])
			if rm != null and rm.has_method("add_resource"):
				var actual_added = rm.call("add_resource", r_type, req_amt)
				plunder[r_type] = int(actual_added) if actual_added != null else req_amt
			else:
				plunder[r_type] = req_amt
		details["plunder"] = plunder

		# 3. Clean up / route surviving defenders of captured outpost
		var em = get_enemy_military_manager()
		if em != null and obj != null:
			for uid in obj.defending_unit_ids:
				var u = em.get_enemy(uid)
				if u != null and is_instance_valid(u) and u.is_alive:
					if u.has_method("retreat_and_despawn"):
						u.retreat_and_despawn()
					elif u.has_method("set_ai_state"):
						u.set_ai_state(5) # 5 = RECOVER_RETREAT
			obj.defending_unit_ids.clear()

		# 4. Package 2G: Authoritative Outpost Ownership Transfer to Player
		var tx_id: String = "player_siege_%s" % siege_id
		var transfer_res: Dictionary = transfer_outpost_ownership(record.get("objective_id", ""), "player", tx_id)
		details["ownership_transfer"] = transfer_res

	record["details"] = details
	field_siege_resolved.emit(siege_id, outcome, details)
	return {
		"status": "resolved",
		"outcome": outcome,
		"details": details
	}

func _on_objective_destroyed(obj_id: String, _killer_id: String) -> void:
	for s_id in active_sieges.keys():
		var s = active_sieges[s_id]
		if s.get("objective_id") == obj_id and s.get("status") == "active":
			_resolve_siege_outcome(s_id, "VICTORY")

# -----------------------------------------------------------------------------
# Serialization
# -----------------------------------------------------------------------------

func serialize() -> Dictionary:
	var obj_arr: Array = []
	var sorted_obj_keys := objectives.keys()
	sorted_obj_keys.sort()
	for k in sorted_obj_keys:
		var o = objectives[k]
		if is_instance_valid(o):
			obj_arr.append(o.serialize())

	return {
		"objectives": obj_arr,
		"active_sieges": active_sieges.duplicate(true),
		"next_siege_index": next_siege_index
	}

func deserialize(data: Dictionary) -> bool:
	if data.is_empty():
		clear_all_objectives()
		active_sieges.clear()
		next_siege_index = 1
		return true

	var raw_objs = data.get("objectives")
	if raw_objs != null and not (raw_objs is Array):
		return false

	var raw_sieges = data.get("active_sieges")
	if raw_sieges != null and not (raw_sieges is Dictionary):
		return false

	var staged_objs: Dictionary = {}
	if raw_objs is Array:
		for item in raw_objs:
			if not (item is Dictionary):
				_free_staged_objs(staged_objs)
				return false
			var obj := SiegeObjectiveActorScript.new()
			if not obj.deserialize(item):
				obj.free()
				_free_staged_objs(staged_objs)
				return false
			if staged_objs.has(obj.objective_id):
				obj.free()
				_free_staged_objs(staged_objs)
				return false
			staged_objs[obj.objective_id] = obj

	var staged_sieges: Dictionary = {}
	if raw_sieges is Dictionary:
		for s_id in raw_sieges.keys():
			var s = raw_sieges[s_id]
			if not (s is Dictionary):
				_free_staged_objs(staged_objs)
				return false
			var target_obj_id = String(s.get("objective_id", ""))
			if not staged_objs.has(target_obj_id):
				_free_staged_objs(staged_objs)
				return false
			var status_str = String(s.get("status", ""))
			if status_str != "active" and status_str != "resolved" and status_str != "cancelled":
				_free_staged_objs(staged_objs)
				return false
			staged_sieges[String(s_id)] = s.duplicate(true)

	# Validation succeeded completely: replace live state atomically
	clear_all_objectives()
	active_sieges.clear()
	next_siege_index = maxi(1, int(data.get("next_siege_index", 1)))

	for obj_id in staged_objs.keys():
		var obj = staged_objs[obj_id]
		obj.objective_destroyed.connect(_on_objective_destroyed)
		var container = _get_container()
		if container != null and is_instance_valid(container):
			container.add_child(obj)
		objectives[obj_id] = obj

	active_sieges = staged_sieges
	return true

func _free_staged_objs(staged: Dictionary) -> void:
	for o in staged.values():
		if is_instance_valid(o) and o is Node:
			o.free()
	staged.clear()

func clear_all_objectives() -> void:
	for k in objectives.keys():
		var o = objectives[k]
		if is_instance_valid(o) and o is Node:
			if o.get_parent() != null:
				o.get_parent().remove_child(o)
			o.queue_free()
	objectives.clear()
