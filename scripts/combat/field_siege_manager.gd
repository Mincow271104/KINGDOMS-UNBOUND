class_name FieldSiegeManager
extends RefCounted
## Field Siege Manager (Package 1X)
## Authoritative coordinator for tactical field siege operations on hostile outposts.
## Manages eligibility gating, outpost objectives, defender mobilization,
## tactical victory/defeat/withdrawal resolution, plunder awards, and faction power impact.

const SiegeObjectiveActorScript = preload("res://scripts/combat/siege_objective_actor.gd")

signal field_siege_started(siege_id: String, faction_id: String, objective_id: String)
signal field_siege_resolved(siege_id: String, outcome: String, details: Dictionary)
signal objective_registered(objective_id: String, cell: Vector2i, faction_id: String)

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
	"iron": 20
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
	if not obj.is_alive or obj.is_captured:
		return {"can_launch": false, "reason": "Mục tiêu công thành đã bị phá hủy hoặc chiếm đóng"}
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

	# Mobilize garrison defenders around objective if needed
	var defender_ids: Array[String] = []
	if em != null and obj != null:
		var defenders = em.spawn_enemy_force(target_faction_id, obj.current_cell, obj.garrison_count)
		for d in defenders:
			if d != null:
				defender_ids.append(d.unit_id)
				# Defenders defend objective
				d.patrol_origin = obj.current_cell
				d.patrol_radius = 4
				if d.has_method("set_ai_state"):
					d.set_ai_state(0) # 0 = HOLD
		obj.defending_unit_ids = defender_ids

	var s_id := "siege_%d" % next_siege_index
	next_siege_index += 1

	var siege_record: Dictionary = {
		"siege_id": s_id,
		"faction_id": target_faction_id,
		"objective_id": objective_id,
		"status": "active",
		"defending_unit_ids": defender_ids
	}
	active_sieges[s_id] = siege_record
	field_siege_started.emit(s_id, target_faction_id, objective_id)

	return {
		"success": true,
		"reason": "Phát động công thành thành công",
		"siege_id": s_id,
		"defenders": defender_ids.size()
	}

# -----------------------------------------------------------------------------
# Evaluation & Victory Conditions
# -----------------------------------------------------------------------------

func evaluate_siege_status(siege_id: String) -> Dictionary:
	if not active_sieges.has(siege_id):
		return {"status": "not_found", "outcome": "NONE"}

	var record: Dictionary = active_sieges[siege_id]
	if record.get("status") != "active":
		return {"status": record.get("status"), "outcome": record.get("outcome", "NONE")}

	var obj_id: String = record.get("objective_id", "")
	var obj = get_objective(obj_id)
	var faction_id: String = record.get("faction_id", "")
	var army = get_player_army_manager()

	# Victory Check: Outpost destroyed or captured
	if obj != null and (not obj.is_alive or obj.is_captured):
		return _resolve_siege_outcome(siege_id, "VICTORY")

	# Defeat Check: Player field army wiped out completely
	var field_troops: int = army.get_field_unit_count() if (army != null and army.has_method("get_field_unit_count")) else 0
	var total_soldiers: int = army.get_army_count() if (army != null and army.has_method("get_army_count")) else 0
	if total_soldiers <= 0 or field_troops <= 0:
		return _resolve_siege_outcome(siege_id, "DEFEAT")

	# Withdrawal Check: Player moved out of siege radius
	if army != null and obj != null:
		var dist: int = IsoMath.grid_distance(army.get_current_cell(), obj.current_cell)
		if dist > (SIEGE_RADIUS + 4) or (army.get_movement_state() == PlayerArmyManager.MovementState.GARRISONED and army.get_current_cell() == army.get_rally_cell()):
			return _resolve_siege_outcome(siege_id, "WITHDRAWAL")

	return {"status": "active", "outcome": "NONE"}

func _resolve_siege_outcome(siege_id: String, outcome: String) -> Dictionary:
	if not active_sieges.has(siege_id):
		return {}

	var record: Dictionary = active_sieges[siege_id]
	record["status"] = "resolved"
	record["outcome"] = outcome

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

		# 2. Award plunder resources
		var rm = get_resource_manager()
		var plunder: Dictionary = PLUNDER_REWARDS.duplicate()
		if rm != null and rm.has_method("add_resource"):
			for r_type in plunder:
				rm.call("add_resource", r_type, plunder[r_type])
		details["plunder"] = plunder

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
	clear_all_objectives()
	active_sieges.clear()
	if data.is_empty():
		return true

	next_siege_index = maxi(1, int(data.get("next_siege_index", 1)))

	var raw_objs = data.get("objectives")
	if raw_objs is Array:
		for item in raw_objs:
			if not (item is Dictionary):
				continue
			var obj := SiegeObjectiveActorScript.new()
			if not obj.deserialize(item):
				obj.free()
				continue
			obj.objective_destroyed.connect(_on_objective_destroyed)
			var container = _get_container()
			if container != null and is_instance_valid(container):
				container.add_child(obj)
			objectives[obj.objective_id] = obj

	var raw_sieges = data.get("active_sieges")
	if raw_sieges is Dictionary:
		active_sieges = raw_sieges.duplicate(true)

	return true

func clear_all_objectives() -> void:
	for k in objectives.keys():
		var o = objectives[k]
		if is_instance_valid(o) and o is Node:
			o.queue_free()
	objectives.clear()
