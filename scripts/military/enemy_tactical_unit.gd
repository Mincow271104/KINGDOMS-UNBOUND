class_name EnemyTacticalUnit
extends TacticalUnit
## Enemy Tactical Military Unit Actor (Package 1X)
## Represents an individual hostile soldier belonging to an NPC faction.
## Features crimson armor modulation, deterministic AI state machine
## (HOLD, PATROL, ACQUIRE_TARGET, PURSUE, ATTACK, RECOVER_RETREAT),
## Manhattan range verification, and diplomatic peace responsiveness.

enum AIState {
	HOLD = 0,
	PATROL = 1,
	ACQUIRE_TARGET = 2,
	PURSUE = 3,
	ATTACK = 4,
	RECOVER_RETREAT = 5
}

const CRIMSON_MODULATE := Color(0.95, 0.3, 0.3, 1.0)

@export var ai_state: int = AIState.ACQUIRE_TARGET
@export var owning_faction_id: String = ""
@export var detection_range: int = 8 # Manhattan grid distance
@export var patrol_origin: Vector2i = Vector2i(0, 0)
@export var patrol_radius: int = 3
@export var retreat_destination: Vector2i = Vector2i(0, 0)
@export var is_garrison_defender: bool = false
@export var assigned_objective_id: String = ""

signal ai_state_changed(enemy_id: String, old_state: int, new_state: int)
signal enemy_retreated(enemy_id: String)

func _ready() -> void:
	super._ready()
	faction_id = owning_faction_id if not owning_faction_id.is_empty() else "enemy"
	if sprite != null:
		sprite.modulate = CRIMSON_MODULATE

func _setup_visuals() -> void:
	super._setup_visuals()
	if sprite != null:
		sprite.modulate = CRIMSON_MODULATE

func set_ai_state(new_state: int) -> void:
	if ai_state != new_state:
		var old = ai_state
		ai_state = new_state
		ai_state_changed.emit(unit_id, old, new_state)

func update_ai(delta: float, speed_mult: float, nav: GridNavigation, player_units: Array, faction_mgr: Object = null) -> void:
	if not is_alive:
		return

	var tm = get_time_manager()
	if tm != null and tm.has_method("is_paused") and tm.is_paused():
		return
	if speed_mult <= 0.0:
		return

	# Diplomatic peace check: If no longer at war, retreat peacefully
	if faction_mgr != null and not owning_faction_id.is_empty():
		var at_war: bool = false
		if faction_mgr.has_method("get_faction"):
			var fac = faction_mgr.get_faction(owning_faction_id)
			if fac != null:
				at_war = bool(fac.is_at_war)
		elif faction_mgr.has_method("are_factions_at_war"):
			at_war = faction_mgr.are_factions_at_war(owning_faction_id, "player")
		
		if not at_war:
			# Peace declared: immediately cease hostility
			if order_state == OrderState.ATTACKING:
				target_actor = null
				target_actor_id = ""
				order_state = OrderState.IDLE
			if ai_state != AIState.RECOVER_RETREAT:
				set_ai_state(AIState.RECOVER_RETREAT)

	match ai_state:
		AIState.HOLD:
			_ai_tick_hold(player_units)

		AIState.PATROL:
			_ai_tick_patrol(delta, speed_mult, nav, player_units)

		AIState.ACQUIRE_TARGET:
			_ai_tick_acquire(player_units)

		AIState.PURSUE:
			_ai_tick_pursue(delta, speed_mult, nav)

		AIState.ATTACK:
			_ai_tick_attack()

		AIState.RECOVER_RETREAT:
			_ai_tick_retreat(delta, speed_mult, nav)

func _ai_tick_hold(player_units: Array) -> void:
	# Scan for threats within detection range
	var target = _find_best_player_target(player_units)
	if target != null:
		_engage_target(target)

func _ai_tick_patrol(_delta: float, _speed_mult: float, _nav: GridNavigation, player_units: Array) -> void:
	var target = _find_best_player_target(player_units)
	if target != null:
		_engage_target(target)
		return
	# When idle, maintain patrol perimeter around patrol_origin
	if order_state == OrderState.IDLE and IsoMath.is_in_bounds(patrol_origin):
		if IsoMath.grid_distance(current_cell, patrol_origin) > patrol_radius:
			if _nav != null:
				var path: Array[Vector2i] = _nav.find_path(current_cell, patrol_origin)
				if path.size() > 1:
					order_move(path, patrol_origin)
				else:
					# Unreachable path back to origin: safe transition to HOLD
					set_ai_state(AIState.HOLD)
			else:
				set_ai_state(AIState.HOLD)

func _ai_tick_acquire(player_units: Array) -> void:
	var target = _find_best_player_target(player_units)
	if target != null:
		_engage_target(target)
	else:
		if patrol_origin != Vector2i(0, 0):
			set_ai_state(AIState.PATROL)
		else:
			set_ai_state(AIState.HOLD)

func _ai_tick_pursue(_delta: float, _speed_mult: float, _nav: GridNavigation) -> void:
	if not _is_target_valid():
		target_actor = null
		target_actor_id = ""
		set_ai_state(AIState.ACQUIRE_TARGET)
		return

	var raw_tgt = target_actor.get("current_cell")
	var tgt_c: Vector2i = raw_tgt if (raw_tgt is Vector2i) else Vector2i(-1, -1)
	if IsoMath.grid_distance(current_cell, tgt_c) <= attack_range:
		set_ai_state(AIState.ATTACK)

func _ai_tick_attack() -> void:
	if not _is_target_valid():
		target_actor = null
		target_actor_id = ""
		set_ai_state(AIState.ACQUIRE_TARGET)
		return

	var raw_tgt = target_actor.get("current_cell")
	var tgt_c: Vector2i = raw_tgt if (raw_tgt is Vector2i) else Vector2i(-1, -1)
	if IsoMath.grid_distance(current_cell, tgt_c) > attack_range:
		set_ai_state(AIState.PURSUE)

func _ai_tick_retreat(delta: float, speed_mult: float, nav: GridNavigation) -> void:
	if retreat_destination == Vector2i(0, 0):
		# Default retreat towards map border
		retreat_destination = Vector2i(0, current_cell.y)

	if current_cell == retreat_destination or IsoMath.grid_distance(current_cell, retreat_destination) <= 1:
		enemy_retreated.emit(unit_id)
		return

	if order_state != OrderState.MOVING:
		if nav != null:
			var p = nav.find_path(current_cell, retreat_destination)
			if not p.is_empty():
				order_move(p, retreat_destination)

func _engage_target(target: Node) -> void:
	order_attack(target)
	var raw_tgt = target.get("current_cell")
	var tgt_c: Vector2i = raw_tgt if (raw_tgt is Vector2i) else Vector2i(-1, -1)
	if IsoMath.grid_distance(current_cell, tgt_c) <= attack_range:
		set_ai_state(AIState.ATTACK)
	else:
		set_ai_state(AIState.PURSUE)

func _is_target_valid() -> bool:
	if target_actor == null or not is_instance_valid(target_actor):
		return false
	var alive_val = target_actor.get("is_alive")
	if alive_val != null and not bool(alive_val):
		return false
	var hp_val = target_actor.get("health")
	if hp_val != null and float(hp_val) <= 0.0:
		return false
	return true

func _find_best_player_target(player_units: Array) -> Node:
	var best_target: Node = null
	var best_dist: int = 999999
	var best_id: String = ""

	for u in player_units:
		if u == null or not is_instance_valid(u):
			continue
		var alive_val = u.get("is_alive")
		if alive_val != null and not bool(alive_val):
			continue
		var hp_val = u.get("health")
		if hp_val != null and float(hp_val) <= 0.0:
			continue
		var raw_u_cell = u.get("current_cell")
		if not (raw_u_cell is Vector2i):
			continue
		var u_cell: Vector2i = raw_u_cell
		var dist: int = IsoMath.grid_distance(current_cell, u_cell)
		if dist <= detection_range:
			var u_id: String = str(u.get("unit_id"))
			# Deterministic tie-breaker: closest Manhattan distance, then lowest alphabetical ID
			if dist < best_dist or (dist == best_dist and (best_id.is_empty() or u_id < best_id)):
				best_dist = dist
				best_target = u
				best_id = u_id

	return best_target

static func ai_state_to_string(state: int) -> String:
	match state:
		AIState.HOLD:
			return "hold"
		AIState.PATROL:
			return "patrol"
		AIState.ACQUIRE_TARGET:
			return "acquire_target"
		AIState.PURSUE:
			return "pursue"
		AIState.ATTACK:
			return "attack"
		AIState.RECOVER_RETREAT:
			return "recover_retreat"
		_:
			return "acquire_target"

static func string_to_ai_state(s: String) -> int:
	match s.to_lower():
		"hold":
			return AIState.HOLD
		"patrol":
			return AIState.PATROL
		"acquire_target":
			return AIState.ACQUIRE_TARGET
		"pursue":
			return AIState.PURSUE
		"attack":
			return AIState.ATTACK
		"recover_retreat":
			return AIState.RECOVER_RETREAT
		_:
			return AIState.ACQUIRE_TARGET

func serialize() -> Dictionary:
	var dict: Dictionary = super.serialize()
	dict["owning_faction_id"] = owning_faction_id
	dict["ai_state"] = ai_state_to_string(ai_state)
	dict["detection_range"] = detection_range
	dict["patrol_origin"] = [patrol_origin.x, patrol_origin.y]
	dict["patrol_radius"] = patrol_radius
	dict["retreat_destination"] = [retreat_destination.x, retreat_destination.y]
	dict["is_garrison_defender"] = is_garrison_defender
	dict["assigned_objective_id"] = assigned_objective_id
	return dict

func deserialize(data: Dictionary) -> bool:
	if not super.deserialize(data):
		return false
	owning_faction_id = String(data.get("owning_faction_id", "")).strip_edges()
	if owning_faction_id.is_empty():
		return false
	ai_state = string_to_ai_state(String(data.get("ai_state", "acquire_target")))
	detection_range = maxi(1, int(data.get("detection_range", 8)))
	is_garrison_defender = bool(data.get("is_garrison_defender", false))
	assigned_objective_id = String(data.get("assigned_objective_id", ""))
	var raw_p_orig = data.get("patrol_origin")
	if raw_p_orig is Array and raw_p_orig.size() >= 2:
		patrol_origin = Vector2i(int(raw_p_orig[0]), int(raw_p_orig[1]))
	elif raw_p_orig is Vector2i:
		patrol_origin = raw_p_orig
	if not IsoMath.is_in_bounds(patrol_origin):
		patrol_origin = current_cell

	patrol_radius = maxi(1, int(data.get("patrol_radius", 3)))
	var raw_ret = data.get("retreat_destination")
	if raw_ret is Array and raw_ret.size() >= 2:
		retreat_destination = Vector2i(int(raw_ret[0]), int(raw_ret[1]))
	elif raw_ret is Vector2i:
		retreat_destination = raw_ret

	faction_id = owning_faction_id
	if order_state == OrderState.ATTACKING:
		resolve_target_actor()
		if target_actor == null:
			order_state = OrderState.IDLE
			ai_state = AIState.ACQUIRE_TARGET

	if sprite != null:
		sprite.modulate = CRIMSON_MODULATE
	return true
