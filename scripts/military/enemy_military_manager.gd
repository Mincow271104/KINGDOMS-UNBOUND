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
var field_siege_mgr: Object = null
var tactical_military_mgr: Object = null

const MAX_FIELD_FORCE_PER_FACTION: int = 3

var enemies: Dictionary = {} # enemy_id: String -> EnemyTacticalUnit
var next_enemy_index: int = 1

var _custom_nav: GridNavigation = null
var _custom_time_mgr: Object = null

func _init(wv: Node = null, fm: Object = null) -> void:
	world_view = wv
	faction_mgr = fm
	field_siege_mgr = null
	tactical_military_mgr = null
	enemies = {}
	next_enemy_index = 1
	_bind_faction_signals()

func set_world_view(wv: Node) -> void:
	world_view = wv

func set_faction_manager(fm: Object) -> void:
	_unbind_faction_signals()
	faction_mgr = fm
	_bind_faction_signals()

func set_field_siege_manager(fsm: Object) -> void:
	field_siege_mgr = fsm

func set_tactical_military_manager(tmm: Object) -> void:
	tactical_military_mgr = tmm

func get_field_siege_manager() -> Object:
	if field_siege_mgr != null:
		return field_siege_mgr
	if is_instance_valid(world_view) and world_view.get("field_siege_mgr") != null:
		return world_view.get("field_siege_mgr")
	return null

func get_tactical_military_manager() -> Object:
	if tactical_military_mgr != null:
		return tactical_military_mgr
	if is_instance_valid(world_view) and world_view.get("tactical_military_mgr") != null:
		return world_view.get("tactical_military_mgr")
	return null

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

func get_field_enemies_by_faction(faction_id: String) -> Array:
	var result: Array = []
	for e in enemies.values():
		if is_instance_valid(e) and e.owning_faction_id == faction_id and not e.get("is_garrison_defender"):
			result.append(e)
	return result

func get_garrison_defenders_by_objective(objective_id: String) -> Array:
	var result: Array = []
	for e in enemies.values():
		if is_instance_valid(e) and e.get("is_garrison_defender") and e.get("assigned_objective_id") == objective_id:
			result.append(e)
	return result

## Release all garrison defenders currently assigned to an objective upon ownership transfer.
## Routes surviving units into RECOVER_RETREAT (5) while leaving their owning faction intact.
func release_garrison_defenders(objective_id: String, objective: Object = null) -> Array:
	var released_units: Array = []
	if objective_id.strip_edges().is_empty():
		return released_units

	var obj = objective
	if obj == null:
		var fsm = get_field_siege_manager()
		if fsm != null and fsm.has_method("get_objective"):
			obj = fsm.get_objective(objective_id)

	var candidates: Array = []
	if obj != null and is_instance_valid(obj) and obj.get("defending_unit_ids") != null:
		var uids = obj.get("defending_unit_ids")
		if uids is Array:
			for uid in uids:
				var u = get_enemy(str(uid))
				if u != null and is_instance_valid(u) and not candidates.has(u):
					candidates.append(u)

	var assigned = get_garrison_defenders_by_objective(objective_id)
	for u in assigned:
		if u != null and is_instance_valid(u) and not candidates.has(u):
			candidates.append(u)

	for unit in candidates:
		if unit == null or not is_instance_valid(unit):
			continue
		var alive_val = unit.get("is_alive")
		var is_alive: bool = bool(alive_val) if alive_val != null else true
		var hp_val = unit.get("health")
		var hp: float = float(hp_val) if hp_val != null else 1.0
		if not is_alive or hp <= 0.0:
			continue

		if unit.has_method("clear_combat_and_pursuit_to_idle"):
			unit.clear_combat_and_pursuit_to_idle()
		else:
			unit.set("target_actor", null)
			unit.set("target_actor_id", "")
			unit.set("order_state", TacticalUnit.OrderState.IDLE)
			var p = unit.get("current_path")
			if p != null and p is Array:
				p.clear()
			unit.set("target_cell", unit.get("current_cell"))

		unit.set("is_garrison_defender", false)
		unit.set("assigned_objective_id", "")

		if unit.has_method("set_ai_state"):
			unit.set_ai_state(EnemyTacticalUnitScript.AIState.RECOVER_RETREAT)
		elif unit.get("ai_state") != null:
			unit.set("ai_state", 5)

		released_units.append(unit)

	if obj != null and is_instance_valid(obj) and obj.get("defending_unit_ids") != null:
		var uids = obj.get("defending_unit_ids")
		if uids is Array:
			uids.clear()

	return released_units

func get_authoritative_occupied_cells(extra_excluded: Array = []) -> Dictionary:
	var occupied: Dictionary = {}

	# 1. Registered siege objective cells
	var fsm = get_field_siege_manager()
	if fsm != null and fsm.has_method("get_all_objectives"):
		for obj in fsm.get_all_objectives():
			if obj != null and is_instance_valid(obj):
				occupied[obj.current_cell] = true

	# 2. Existing living enemy units
	for e in enemies.values():
		if e != null and is_instance_valid(e) and e.is_alive:
			occupied[e.current_cell] = true
			if e.target_cell != null and e.target_cell != e.current_cell:
				occupied[e.target_cell] = true

	# 3. Living player tactical units
	var tmm = get_tactical_military_manager()
	if tmm != null and tmm.has_method("get_all_units"):
		for u in tmm.get_all_units():
			if u != null and is_instance_valid(u) and u.is_alive:
				occupied[u.current_cell] = true
				if u.target_cell != null and u.target_cell != u.current_cell:
					occupied[u.target_cell] = true

	# 4. Living citizens
	if is_instance_valid(world_view) and world_view.get("citizen_list") != null:
		var c_list = world_view.get("citizen_list")
		if c_list is Array:
			for cit in c_list:
				if cit != null and is_instance_valid(cit):
					var alive := true
					if cit.has_method("is_alive"):
						alive = bool(cit.call("is_alive"))
					elif cit.get("health") != null:
						alive = float(cit.get("health")) > 0.0
					if alive:
						var c_pos = cit.get("current_cell")
						if c_pos is Vector2i:
							occupied[c_pos] = true

	# 5. Building footprints from WorldData
	var wd = null
	if is_instance_valid(world_view) and world_view.get("world_data") != null:
		wd = world_view.get("world_data")
	if wd != null and wd.get("buildings") is Array:
		for b in wd.buildings:
			if b is Dictionary:
				var b_cell: Vector2i = b.get("cell", Vector2i(-1, -1))
				var b_size: Vector2i = b.get("size", Vector2i(1, 1))
				for bx in range(b_size.x):
					for by in range(b_size.y):
						occupied[b_cell + Vector2i(bx, by)] = true

	# 6. Extra excluded cells
	for c in extra_excluded:
		if c is Vector2i:
			occupied[c] = true

	return occupied

func is_cell_spawn_eligible(c: Vector2i, nav: GridNavigation = null, occupied: Dictionary = {}) -> bool:
	if not IsoMath.is_in_bounds(c):
		return false
	if occupied.has(c):
		return false
	if nav != null and not nav.is_cell_walkable(c):
		return false

	var wd = null
	if is_instance_valid(world_view) and world_view.get("world_data") != null:
		wd = world_view.get("world_data")
	if wd != null:
		if wd.get("terrain") != null and wd.terrain[c.x][c.y] == WorldGenerator.TerrainType.WATER:
			return false
		if wd.get("occupancy") != null and wd.occupancy[c.x][c.y]:
			return false

	return true

func spawn_enemy_unit(
	faction_id: String,
	cell: Vector2i,
	enemy_id: String = "",
	custom_hp: float = 100.0,
	custom_dmg: float = 20.0,
	is_defender: bool = false,
	objective_id: String = ""
) -> TacticalUnit:
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
	unit.is_garrison_defender = is_defender
	unit.assigned_objective_id = objective_id
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

func spawn_enemy_force(
	faction_id: String,
	center_cell: Vector2i,
	count: int,
	nav: GridNavigation = null,
	exclude_center: bool = false,
	is_defender: bool = false,
	objective_id: String = ""
) -> Array[TacticalUnit]:
	var result: Array[TacticalUnit] = []
	if count <= 0 or not IsoMath.is_in_bounds(center_cell):
		return result

	if nav == null:
		nav = get_nav()

	var slots := _find_distinct_walkable_cells(center_cell, count, nav, [], exclude_center)
	for slot in slots:
		var u = spawn_enemy_unit(faction_id, slot, "", 100.0, 20.0, is_defender, objective_id)
		if u != null:
			result.append(u)
	return result

func _find_distinct_walkable_cells(
	center: Vector2i,
	count: int,
	nav: GridNavigation = null,
	extra_excluded: Array = [],
	exclude_center: bool = false
) -> Array[Vector2i]:
	var slots: Array[Vector2i] = []
	if count <= 0:
		return slots

	if nav == null:
		nav = get_nav()

	var occupied := get_authoritative_occupied_cells(extra_excluded)
	if exclude_center:
		occupied[center] = true

	if not occupied.has(center) and is_cell_spawn_eligible(center, nav, occupied):
		slots.append(center)
		occupied[center] = true

	if slots.size() >= count:
		return slots

	var max_radius: int = IsoMath.MAP_SIZE
	for radius in range(1, max_radius):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var candidate := center + Vector2i(dx, dy)
				if not occupied.has(candidate) and is_cell_spawn_eligible(candidate, nav, occupied):
					slots.append(candidate)
					occupied[candidate] = true
					if slots.size() >= count:
						return slots
	return slots

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
	# All units of faction cease attack immediately, clear pursuit paths, and retreat
	for eid in enemies.keys():
		var unit = enemies[eid]
		if is_instance_valid(unit) and unit.owning_faction_id == faction_id:
			if unit.has_method("clear_combat_and_pursuit_to_idle"):
				unit.clear_combat_and_pursuit_to_idle()
			else:
				unit.target_actor = null
				unit.target_actor_id = ""
				unit.order_state = TacticalUnit.OrderState.IDLE
				unit.current_path.clear()
				unit.target_cell = unit.current_cell
			unit.set_ai_state(EnemyTacticalUnitScript.AIState.RECOVER_RETREAT)

func resolve_all_combat_targets() -> void:
	for eid in enemies.keys():
		var unit = enemies[eid]
		if is_instance_valid(unit) and unit.order_state == TacticalUnit.OrderState.ATTACKING:
			unit.set_world_view(world_view)
			unit.resolve_target_actor()

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
