class_name EnemyMilitaryManager
extends RefCounted
## Enemy Military Manager (Package 1X)
## Authoritative coordinator for hostile NPC faction tactical entities.
## Coordinates deterministic spawning, sorted AI simulation advancement,
## combat execution, casualty processing, and peace treaty transitions.

const EnemyTacticalUnitScript = preload("res://scripts/military/enemy_tactical_unit.gd")

signal enemy_spawned(enemy_id: String, faction_id: String, cell: Vector2i)
signal enemy_defeated(enemy_id: String, faction_id: String, killer_id: String)
signal enemy_despawned(enemy_id: String)
signal all_enemies_cleared()

var world_view: Node = null
var faction_mgr: Object = null
var enemy_units_container: Node = null

var enemies: Dictionary = {} # enemy_id: String -> EnemyTacticalUnit
var next_enemy_index: int = 1

var _custom_nav: GridNavigation = null
var _custom_time_mgr: Object = null

func _init(wv: Node = null, fm: Object = null) -> void:
	world_view = wv
	faction_mgr = fm
	enemies = {}
	next_enemy_index = 1
	_bind_faction_signals()

func set_world_view(wv: Node) -> void:
	world_view = wv

func set_faction_manager(fm: Object) -> void:
	_unbind_faction_signals()
	faction_mgr = fm
	_bind_faction_signals()

func set_enemy_units_container(container: Node) -> void:
	enemy_units_container = container

func set_custom_nav(p_nav: GridNavigation) -> void:
	_custom_nav = p_nav

func set_custom_time_manager(tm: Object) -> void:
	_custom_time_mgr = tm

func get_nav() -> GridNavigation:
	if _custom_nav != null:
		return _custom_nav
	if is_instance_valid(world_view) and world_view.get("nav") != null:
		return world_view.get("nav")
	return null

func get_time_manager() -> Object:
	if _custom_time_mgr != null:
		return _custom_time_mgr
	if is_instance_valid(world_view) and world_view.is_inside_tree() and world_view.has_node("/root/TimeManager"):
		return world_view.get_node("/root/TimeManager")
	if Engine.has_singleton("TimeManager"):
		return Engine.get_singleton("TimeManager")
	return null

func _bind_faction_signals() -> void:
	if faction_mgr != null and is_instance_valid(faction_mgr):
		if faction_mgr.has_signal("peace_signed") and not faction_mgr.peace_signed.is_connected(on_peace_signed):
			faction_mgr.peace_signed.connect(on_peace_signed)

func _unbind_faction_signals() -> void:
	if faction_mgr != null and is_instance_valid(faction_mgr):
		if faction_mgr.has_signal("peace_signed") and faction_mgr.peace_signed.is_connected(on_peace_signed):
			faction_mgr.peace_signed.disconnect(on_peace_signed)

# -----------------------------------------------------------------------------
# Spawning & Lifecycle
# -----------------------------------------------------------------------------

func get_enemy_count() -> int:
	return enemies.size()

func get_enemy(enemy_id: String) -> TacticalUnit:
	return enemies.get(enemy_id, null)

func get_all_enemies() -> Array:
	return enemies.values()

func get_enemies_by_faction(faction_id: String) -> Array:
	var result: Array = []
	for e in enemies.values():
		if is_instance_valid(e) and e.owning_faction_id == faction_id:
			result.append(e)
	return result

func spawn_enemy_unit(faction_id: String, cell: Vector2i, enemy_id: String = "", custom_hp: float = 100.0, custom_dmg: float = 20.0) -> TacticalUnit:
	if not IsoMath.is_in_bounds(cell):
		return null

	var e_id := enemy_id
	if e_id.is_empty():
		e_id = "enemy_unit_%d" % next_enemy_index
		next_enemy_index += 1
		while enemies.has(e_id):
			e_id = "enemy_unit_%d" % next_enemy_index
			next_enemy_index += 1

	var unit = EnemyTacticalUnitScript.new()
	unit.unit_id = e_id
	unit.unit_name = "Kẻ Thù #%s" % e_id.replace("enemy_unit_", "")
	unit.unit_type = "hostile_swordsman"
	unit.owning_faction_id = faction_id
	unit.faction_id = faction_id
	unit.current_cell = cell
	unit.target_cell = cell
	unit.health = custom_hp
	unit.max_health = custom_hp
	unit.attack_damage = custom_dmg
	unit.patrol_origin = cell
	unit.set_world_view(world_view)
	if _custom_time_mgr != null:
		unit.set_custom_time_manager(_custom_time_mgr)

	unit.unit_defeated.connect(_on_unit_defeated)
	unit.enemy_retreated.connect(_on_enemy_retreated)

	var container = _get_container()
	if container != null and is_instance_valid(container):
		container.add_child(unit)

	enemies[e_id] = unit
	enemy_spawned.emit(e_id, faction_id, cell)
	return unit

func spawn_enemy_force(faction_id: String, center_cell: Vector2i, count: int, nav: GridNavigation = null) -> Array[TacticalUnit]:
	var result: Array[TacticalUnit] = []
	if count <= 0 or not IsoMath.is_in_bounds(center_cell):
		return result

	if nav == null:
		nav = get_nav()

	var slots := _find_distinct_walkable_cells(center_cell, count, nav)
	for slot in slots:
		var u = spawn_enemy_unit(faction_id, slot)
		if u != null:
			result.append(u)
	return result

func _find_distinct_walkable_cells(center: Vector2i, count: int, nav: GridNavigation) -> Array[Vector2i]:
	var slots: Array[Vector2i] = []
	if count <= 0:
		return slots

	var occupied_cells: Array[Vector2i] = []
	for e in enemies.values():
		if is_instance_valid(e):
			occupied_cells.append(e.current_cell)

	var is_cell_free = func(c: Vector2i) -> bool:
		if not IsoMath.is_in_bounds(c):
			return false
		if occupied_cells.has(c) or slots.has(c):
			return false
		if nav != null and not nav.is_cell_walkable(c):
			return false
		return true

	if is_cell_free.call(center):
		slots.append(center)

	var max_radius := 15
	for radius in range(1, max_radius + 1):
		if slots.size() >= count:
			break
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var candidate := center + Vector2i(dx, dy)
				if is_cell_free.call(candidate):
					slots.append(candidate)
					if slots.size() >= count:
						break
			if slots.size() >= count:
				break

	return slots

func _get_container() -> Node:
	if enemy_units_container != null and is_instance_valid(enemy_units_container):
		return enemy_units_container
	if is_instance_valid(world_view):
		var existing = world_view.get_node_or_null("EnemyUnitsContainer")
		if existing != null:
			return existing
		var new_container := Node2D.new()
		new_container.name = "EnemyUnitsContainer"
		new_container.y_sort_enabled = true
		world_view.add_child(new_container)
		enemy_units_container = new_container
		return new_container
	return null

# -----------------------------------------------------------------------------
# Simulation Loop & Determinism
# -----------------------------------------------------------------------------

func advance_simulation(delta: float, speed_mult: float = 1.0, nav: GridNavigation = null, player_units: Array = []) -> void:
	if nav == null:
		nav = get_nav()

	# Deterministic iteration: process enemies in sorted ID order
	var sorted_ids := enemies.keys()
	sorted_ids.sort()

	for eid in sorted_ids:
		var unit = enemies.get(eid, null)
		if unit != null and is_instance_valid(unit) and unit.is_alive:
			unit.update_ai(delta, speed_mult, nav, player_units, faction_mgr)
			if unit.order_state == TacticalUnit.OrderState.MOVING:
				unit.advance_movement(delta, speed_mult, nav)
			unit.advance_combat(delta, speed_mult, nav)

# -----------------------------------------------------------------------------
# Casualty & Peace Handling
# -----------------------------------------------------------------------------

func _on_unit_defeated(u_id: String, killer_id: String) -> void:
	var unit = enemies.get(u_id, null)
	var fac_id := ""
	if unit != null and is_instance_valid(unit):
		fac_id = unit.owning_faction_id
	enemy_defeated.emit(u_id, fac_id, killer_id)
	remove_enemy(u_id)

func _on_enemy_retreated(u_id: String) -> void:
	remove_enemy(u_id)

func remove_enemy(enemy_id: String) -> void:
	if not enemies.has(enemy_id):
		return
	var unit = enemies[enemy_id]
	enemies.erase(enemy_id)
	enemy_despawned.emit(enemy_id)
	if is_instance_valid(unit) and unit is Node:
		unit.queue_free()
	if enemies.is_empty():
		all_enemies_cleared.emit()

func clear_all_enemies() -> void:
	for eid in enemies.keys():
		var unit = enemies[eid]
		if is_instance_valid(unit) and unit is Node:
			unit.queue_free()
		enemy_despawned.emit(eid)
	enemies.clear()
	all_enemies_cleared.emit()

func on_peace_signed(faction_id: String) -> void:
	# All units of faction cease attack immediately and retreat
	for eid in enemies.keys():
		var unit = enemies[eid]
		if is_instance_valid(unit) and unit.owning_faction_id == faction_id:
			unit.target_actor = null
			unit.target_actor_id = ""
			unit.order_state = TacticalUnit.OrderState.IDLE
			unit.set_ai_state(EnemyTacticalUnitScript.AIState.RECOVER_RETREAT)

# -----------------------------------------------------------------------------
# Serialization
# -----------------------------------------------------------------------------

func serialize() -> Dictionary:
	var enemies_arr: Array = []
	var sorted_ids := enemies.keys()
	sorted_ids.sort()

	for eid in sorted_ids:
		var u = enemies[eid]
		if is_instance_valid(u):
			enemies_arr.append(u.serialize())

	return {
		"enemies": enemies_arr,
		"next_enemy_index": next_enemy_index
	}

func deserialize(data: Dictionary) -> bool:
	if data.is_empty():
		clear_all_enemies()
		next_enemy_index = 1
		return true

	var raw_enemies = data.get("enemies")
	if raw_enemies != null and not (raw_enemies is Array):
		return false

	var staged_units: Dictionary = {}
	if raw_enemies is Array:
		for item in raw_enemies:
			if not (item is Dictionary):
				_free_staged_enemies(staged_units)
				return false
			var u_id = String(item.get("unit_id", "")).strip_edges()
			if u_id.is_empty() or staged_units.has(u_id):
				_free_staged_enemies(staged_units)
				return false
			var unit := EnemyTacticalUnitScript.new()
			unit.set_world_view(world_view)
			if _custom_time_mgr != null:
				unit.set_custom_time_manager(_custom_time_mgr)
			if not unit.deserialize(item):
				unit.free()
				_free_staged_enemies(staged_units)
				return false
			staged_units[u_id] = unit

	# 100% Validated: Atomically replace live state
	clear_all_enemies()
	next_enemy_index = maxi(1, int(data.get("next_enemy_index", 1)))

	for u_id in staged_units.keys():
		var unit = staged_units[u_id]
		unit.unit_defeated.connect(_on_unit_defeated)
		unit.enemy_retreated.connect(_on_enemy_retreated)
		var container = _get_container()
		if container != null and is_instance_valid(container):
			container.add_child(unit)
		enemies[u_id] = unit
		enemy_spawned.emit(u_id, unit.owning_faction_id, unit.current_cell)

	return true

func _free_staged_enemies(staged: Dictionary) -> void:
	for u in staged.values():
		if is_instance_valid(u) and u is Node:
			u.free()
	staged.clear()
