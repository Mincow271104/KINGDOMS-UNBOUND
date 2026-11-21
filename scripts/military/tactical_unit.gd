class_name TacticalUnit
extends Node2D
## Tactical Military Unit Actor (Package 1W)
## Represents an individual soldier deployed on the world map.
## Features dimetric isometric foot-anchored Y-sorting, discrete logical cell movement,
## continuous visual interpolation, selection indicators, and formation coordination.

enum OrderState {
	IDLE = 0,
	MOVING = 1,
	HOLDING = 2,
	ATTACKING = 3
}

const CELL_STEP_DURATION: float = 0.5 # Seconds per grid cell at 1x simulation speed

@export var unit_id: String = ""
@export var unit_name: String = ""
@export var unit_type: String = "swordsman"
@export var current_cell: Vector2i = Vector2i(32, 33)
@export var target_cell: Vector2i = Vector2i(32, 33)
@export var order_state: int = OrderState.IDLE
@export var formation: String = "Line"
@export var control_group_id: int = 0 # 0 = None, 1..3

# Combat Model (Package 1X)
@export var health: float = 100.0
@export var max_health: float = 100.0
@export var attack_damage: float = 25.0
@export var attack_range: int = 1 # Manhattan distance on discrete grid
@export var attack_cooldown: float = 1.2 # Seconds between attacks at 1x
@export var attack_cooldown_remaining: float = 0.0
@export var is_alive: bool = true
@export var faction_id: String = "player"
@export var target_actor_id: String = ""

var target_actor: Node = null
var damage_flash_timer: float = 0.0

var is_selected: bool = false
var current_path: Array[Vector2i] = []
var step_accumulator: float = 0.0
var move_speed_px: float = 36.0 # Continuous isometric march speed (matches 0.5s/cell parity)
var _path_follower: ContinuousPathFollower = ContinuousPathFollower.new()
var _follower_source_path: Array[Vector2i] = []
var facing_dir: int = ContinuousPathFollower.ScreenDir.E
var facing_name: String = "E"
var is_moving_visually: bool = false
var _walk_anim_phase: float = 0.0
var _unit_anim_clock: float = 0.0
var _unit_active_clip: String = ""

var sprite: Sprite2D = null
var world_view: Node = null
var _custom_time_mgr: Object = null
var _custom_player_army_mgr: Object = null

signal unit_reached_destination(unit_id: String, final_cell: Vector2i)
signal unit_cell_changed(unit_id: String, new_cell: Vector2i)
signal unit_attacked(attacker_id: String, target_id: String, damage: float)
signal unit_took_damage(unit_id: String, amount: float, current_hp: float, max_hp: float)
signal unit_defeated(unit_id: String, killer_id: String)

func _ready() -> void:
	y_sort_enabled = true
	_setup_visuals()
	position = IsoMath.map_to_local(current_cell)

func _setup_visuals() -> void:
	if sprite == null:
		sprite = get_node_or_null("Sprite2D")
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = "Sprite2D"
		add_child(sprite)
	var tex := EntityVisualRegistry.get_villager_sheet_texture("soldier")
	var lay := EntityVisualRegistry.get_villager_sheet_layout("soldier")
	if tex != null:
		sprite.texture = tex
		sprite.hframes = int(lay.get("hframes", 6))
		sprite.vframes = int(lay.get("vframes", 6))
	elif ResourceLoader.exists("res://assets/entities/citizen.png"):
		sprite.texture = load("res://assets/entities/citizen.png")
		sprite.hframes = 1
		sprite.vframes = 1
	sprite.offset = EntityVisualRegistry.VILLAGER_SPRITE_OFFSET
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.modulate = Color.WHITE
	_sync_unit_visuals(0.0)

func set_world_view(wv: Node) -> void:
	world_view = wv

func set_custom_time_manager(tm: Object) -> void:
	_custom_time_mgr = tm

func get_time_manager() -> Object:
	if _custom_time_mgr != null:
		return _custom_time_mgr
	if is_instance_valid(world_view) and world_view.is_inside_tree() and world_view.has_node("/root/TimeManager"):
		return world_view.get_node("/root/TimeManager")
	if Engine.has_singleton("TimeManager"):
		return Engine.get_singleton("TimeManager")
	if is_inside_tree() and has_node("/root/TimeManager"):
		return get_node("/root/TimeManager")
	return null

func set_player_army_manager(mgr: Object) -> void:
	_custom_player_army_mgr = mgr

func get_player_army_manager() -> Object:
	if _custom_player_army_mgr != null:
		return _custom_player_army_mgr
	if is_instance_valid(world_view) and world_view.get("player_army_mgr") != null:
		return world_view.get("player_army_mgr")
	return null

func get_equipment_multiplier() -> float:
	if faction_id != "player":
		return 1.0
	var mgr = get_player_army_manager()
	if mgr != null and mgr.has_method("get_equipment_combat_multiplier"):
		return float(mgr.call("get_equipment_combat_multiplier"))
	return 1.0

func get_effective_attack_damage() -> float:
	return attack_damage * get_equipment_multiplier()

func set_selected(selected: bool) -> void:
	if is_selected != selected:
		is_selected = selected
		queue_redraw()

func _draw() -> void:
	if is_selected:
		# Draw dimetric isometric selection ellipse at ground contact (2:1 slope)
		var center := Vector2(0.0, 0.0)
		var rx := 14.0
		var ry := 7.0
		var points := PackedVector2Array()
		var segs := 24
		for i in range(segs + 1):
			var th := (float(i) / float(segs)) * TAU
			points.append(center + Vector2(cos(th) * rx, sin(th) * ry))
		
		# Glow outline
		draw_polyline(points, Color(0.1, 0.7, 1.0, 0.4), 3.0, true)
		# Crisp inner outline
		draw_polyline(points, Color(0.3, 0.95, 1.0, 0.95), 1.5, true)

	# Health bar: render above head when selected, injured, attacking, or taking damage
	if is_alive and (is_selected or health < max_health or damage_flash_timer > 0.0 or order_state == OrderState.ATTACKING):
		var bar_w := 24.0
		var bar_h := 3.5
		var bar_pos := Vector2(-bar_w / 2.0, -38.0)
		var hp_ratio := clampf(health / max_health, 0.0, 1.0)
		# Dark background
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.1, 0.1, 0.1, 0.85), true)
		# Fill: green for player, red/crimson for non-player
		var fill_color := Color(0.2, 0.85, 0.25, 0.95) if faction_id == "player" else Color(0.95, 0.25, 0.25, 0.95)
		draw_rect(Rect2(bar_pos, Vector2(bar_w * hp_ratio, bar_h)), fill_color, true)
		# Border outline
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.0, 0.0, 0.0, 0.8), false, 1.0)

	# Non-player faction 7x7 marker above head, below HP bar (y=-30)
	if is_alive and not faction_id.is_empty() and faction_id != "player":
		EntityVisualRegistry.draw_faction_marker_7x7(self, faction_id, EntityVisualRegistry.FACTION_MARKER_OFFSET)

	# Combat flash visual indicator
	if damage_flash_timer > 0.0:
		var flash_pts := PackedVector2Array([
			Vector2(-6.0, -22.0),
			Vector2(6.0, -14.0)
		])
		draw_polyline(flash_pts, Color(1.0, 0.2, 0.2, 0.85), 2.5, false)

func order_move(path: Array, dest: Vector2i) -> void:
	target_actor = null
	target_actor_id = ""
	var new_path: Array[Vector2i] = []
	for p in path:
		if p is Vector2i:
			new_path.append(p)
	if not new_path.is_empty() and new_path[0] == current_cell:
		new_path.remove_at(0)

	# Idempotent re-issue check:
	# If already MOVING towards dest with the identical remaining path, do not reset step_accumulator or replace path
	if order_state == OrderState.MOVING and target_cell == dest and current_path == new_path:
		return
	if order_state == OrderState.IDLE and target_cell == dest and current_cell == dest and current_path.is_empty() and new_path.is_empty():
		return

	var was_moving := (order_state == OrderState.MOVING)
	current_path = new_path
	target_cell = dest
	step_accumulator = 0.0
	_follower_source_path.clear()
	if not was_moving and IsoMath.local_to_map(position) != current_cell:
		position = IsoMath.map_to_local(current_cell)
	if current_path.is_empty():
		current_cell = dest
		order_state = OrderState.IDLE
	else:
		order_state = OrderState.MOVING

func order_hold() -> void:
	target_actor = null
	target_actor_id = ""
	current_path.clear()
	target_cell = current_cell
	step_accumulator = 0.0
	order_state = OrderState.HOLDING

func order_stop() -> void:
	target_actor = null
	target_actor_id = ""
	current_path.clear()
	target_cell = current_cell
	step_accumulator = 0.0
	order_state = OrderState.IDLE

func _stop_walk_animation() -> void:
	is_moving_visually = false
	if sprite != null:
		sprite.offset = EntityVisualRegistry.VILLAGER_SPRITE_OFFSET

func _update_walk_visuals(velocity: Vector2, speed_mult: float, delta: float) -> void:
	if velocity.length_squared() < ContinuousPathFollower.VEL_DEADZONE_SQ:
		_stop_walk_animation()
		return
	is_moving_visually = true
	facing_dir = _path_follower.update_facing_from_velocity(velocity)
	facing_name = ContinuousPathFollower.dir_to_name(facing_dir)
	_walk_anim_phase = fmod(_walk_anim_phase + delta * speed_mult * 10.0, TAU)
	if sprite != null:
		sprite.flip_h = _path_follower.last_flip_h
		sprite.offset = EntityVisualRegistry.VILLAGER_SPRITE_OFFSET
	_sync_unit_visuals(delta * speed_mult)

func _sync_unit_visuals(anim_dt: float) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	var lay := EntityVisualRegistry.get_villager_sheet_layout("soldier")
	var tex := EntityVisualRegistry.get_villager_sheet_texture("soldier")
	if tex == null:
		return
	if sprite.texture != tex:
		sprite.texture = tex
	sprite.hframes = int(lay.get("hframes", 6))
	sprite.vframes = int(lay.get("vframes", 6))
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.offset = EntityVisualRegistry.VILLAGER_SPRITE_OFFSET

	var is_back := (facing_dir == ContinuousPathFollower.ScreenDir.NW or facing_dir == ContinuousPathFollower.ScreenDir.N or facing_dir == ContinuousPathFollower.ScreenDir.NE)
	var clip := "idle"
	var row := 2 if is_back else 0
	var fcount := int(lay.get("idle_frames", 4))
	var fps := float(lay.get("idle_fps", 2.0))
	if is_moving_visually or order_state == OrderState.MOVING:
		clip = "walk"
		row = 3 if is_back else 1
		fcount = int(lay.get("walk_frames", 6))
		fps = float(lay.get("walk_fps", 9.5))
	elif order_state == OrderState.ATTACKING:
		clip = "attack"
		row = 5 if is_back else 4
		fcount = int(lay.get("work_frames", 6))
		fps = float(lay.get("work_fps", 7.5))

	if clip != _unit_active_clip:
		_unit_active_clip = clip
		_unit_anim_clock = 0.0
	elif anim_dt > 0.0:
		_unit_anim_clock += anim_dt

	var frame_idx := int(floor(_unit_anim_clock * fps)) % maxi(1, fcount)
	sprite.frame_coords = Vector2i(frame_idx, row)

func _sync_path_follower() -> void:
	var needs_sync := current_path.size() != _follower_source_path.size()
	if not needs_sync and not current_path.is_empty():
		if current_path[0] != _follower_source_path[0] or current_path[-1] != _follower_source_path[-1]:
			needs_sync = true
		elif current_path != _follower_source_path:
			needs_sync = true
	if needs_sync:
		_follower_source_path = current_path.duplicate()
		var full_path: Array[Vector2i] = []
		var start_cell := IsoMath.local_to_map(position)
		if not IsoMath.is_in_bounds(start_cell):
			start_cell = current_cell
		full_path.append(start_cell)
		for c in current_path:
			if full_path.is_empty() or full_path[-1] != c:
				full_path.append(c)
		_path_follower.set_path(full_path, _get_active_nav(), position)

func _get_active_nav() -> GridNavigation:
	if is_instance_valid(world_view) and world_view.get("nav") is GridNavigation:
		return world_view.get("nav")
	return null

func advance_movement(delta: float, speed_mult: float = 1.0, nav: GridNavigation = null) -> void:
	if order_state != OrderState.MOVING or current_path.is_empty():
		_stop_walk_animation()
		if order_state == OrderState.MOVING and current_path.is_empty():
			order_state = OrderState.IDLE
			target_cell = current_cell
			unit_reached_destination.emit(unit_id, current_cell)
		return

	if speed_mult <= 0.0:
		_stop_walk_animation()
		return

	var tm = get_time_manager()
	if tm != null and tm.has_method("is_paused") and tm.is_paused():
		_stop_walk_animation()
		return

	# Sync follower using provided nav if available
	var active_nav := nav if nav != null else _get_active_nav()
	var needs_sync := current_path.size() != _follower_source_path.size()
	if not needs_sync and not current_path.is_empty():
		if current_path[0] != _follower_source_path[0] or current_path[-1] != _follower_source_path[-1]:
			needs_sync = true
		elif current_path != _follower_source_path:
			needs_sync = true
	if needs_sync:
		_follower_source_path = current_path.duplicate()
		if IsoMath.local_to_map(position) != current_cell:
			position = IsoMath.map_to_local(current_cell)
		var full_path: Array[Vector2i] = []
		full_path.append(current_cell)
		for c in current_path:
			if full_path.is_empty() or full_path[-1] != c:
				full_path.append(c)
		_path_follower.set_path(full_path, active_nav, position)

	# Verify next smoothed waypoint is still walkable if nav is provided
	if active_nav != null and _path_follower.waypoint_index < _path_follower.smoothed_cells.size():
		var next_wp_cell: Vector2i = _path_follower.smoothed_cells[_path_follower.waypoint_index]
		if not active_nav.is_cell_walkable(next_wp_cell):
			var rerouted: Array[Vector2i] = active_nav.find_path(current_cell, target_cell)
			if rerouted.is_empty():
				current_path.clear()
				_follower_source_path.clear()
				step_accumulator = 0.0
				target_cell = current_cell
				order_state = OrderState.IDLE
				_stop_walk_animation()
				unit_reached_destination.emit(unit_id, current_cell)
				return
			else:
				if rerouted[0] == current_cell:
					rerouted.remove_at(0)
				if rerouted.is_empty():
					current_path.clear()
					_follower_source_path.clear()
					step_accumulator = 0.0
					target_cell = current_cell
					order_state = OrderState.IDLE
					_stop_walk_animation()
					unit_reached_destination.emit(unit_id, current_cell)
					return
				current_path = rerouted
				_sync_path_follower()

	step_accumulator = fmod(step_accumulator + delta * speed_mult, CELL_STEP_DURATION)
	if step_accumulator <= 0.0 and delta * speed_mult > 0.0:
		step_accumulator = 0.001
	var step_dist := move_speed_px * delta * speed_mult
	var res := _path_follower.advance(position, step_dist)
	var new_pos: Vector2 = res["position"]
	var new_cell: Vector2i = res["cell"]

	position = new_pos
	_update_walk_visuals(res["velocity"], speed_mult, delta)

	if new_cell != current_cell and IsoMath.is_in_bounds(new_cell):
		current_cell = new_cell
		# Trim passed prefix from current_path while keeping target_cell as final element
		while current_path.size() > 1 and current_path[0] == current_cell:
			current_path.remove_at(0)
		_follower_source_path = current_path.duplicate()
		unit_cell_changed.emit(unit_id, current_cell)

	if bool(res["arrived"]):
		position = IsoMath.map_to_local(target_cell)
		if current_cell != target_cell:
			current_cell = target_cell
			unit_cell_changed.emit(unit_id, current_cell)
		current_path.clear()
		_follower_source_path.clear()
		step_accumulator = 0.0
		order_state = OrderState.IDLE
		_stop_walk_animation()
		unit_reached_destination.emit(unit_id, current_cell)

# -----------------------------------------------------------------------------
# Combat Model & Time-Sliced Resolution (Package 1X)
# -----------------------------------------------------------------------------

func take_damage(amount: float, attacker_id: String = "") -> void:
	if not is_alive or amount <= 0.0:
		return
	health = clampf(health - amount, 0.0, max_health)
	damage_flash_timer = 0.25
	unit_took_damage.emit(unit_id, amount, health, max_health)
	if health <= 0.0:
		is_alive = false
		order_state = OrderState.IDLE
		target_actor = null
		target_actor_id = ""
		current_path.clear()
		step_accumulator = 0.0
		unit_defeated.emit(unit_id, attacker_id)
	queue_redraw()

func can_attack_target(target: Node) -> bool:
	if not is_alive or target == null or not is_instance_valid(target):
		return false
	var alive_val = target.get("is_alive")
	if alive_val != null and not bool(alive_val):
		return false
	var hp_val = target.get("health")
	if hp_val != null and float(hp_val) <= 0.0:
		return false
	var fac_val = target.get("faction_id")
	if fac_val == null:
		fac_val = target.get("owning_faction_id")
	var tgt_faction: String = str(fac_val) if fac_val != null else ""
	if tgt_faction == faction_id and not faction_id.is_empty():
		return false # Friendly fire strictly blocked
	return true

func order_attack(target: Node) -> void:
	if not is_alive or target == null or not is_instance_valid(target):
		return
	target_actor = target
	var id_val = target.get("unit_id")
	if id_val == null:
		id_val = target.get("objective_id")
	target_actor_id = str(id_val) if id_val != null else ""
	order_state = OrderState.ATTACKING
	current_path.clear()
	step_accumulator = 0.0
	queue_redraw()

func advance_combat(delta: float, speed_mult: float = 1.0, nav: GridNavigation = null) -> void:
	if not is_alive:
		return
	if damage_flash_timer > 0.0:
		damage_flash_timer = maxf(0.0, damage_flash_timer - delta * speed_mult)
		if damage_flash_timer == 0.0:
			queue_redraw()

	var tm = get_time_manager()
	if tm != null and tm.has_method("is_paused") and tm.is_paused():
		return
	if speed_mult <= 0.0:
		return

	if attack_cooldown_remaining > 0.0:
		attack_cooldown_remaining = maxf(0.0, attack_cooldown_remaining - delta * speed_mult)

	if order_state != OrderState.ATTACKING:
		return

	if target_actor == null and not target_actor_id.is_empty():
		resolve_target_actor()

	# Target soft-reference validation
	if target_actor == null or not is_instance_valid(target_actor):
		clear_combat_and_pursuit_to_idle()
		return

	var tgt_alive_val = target_actor.get("is_alive")
	var tgt_alive: bool = bool(tgt_alive_val) if tgt_alive_val != null else true
	var tgt_hp_val = target_actor.get("health")
	var tgt_hp: float = float(tgt_hp_val) if tgt_hp_val != null else 1.0
	if not tgt_alive or tgt_hp <= 0.0:
		clear_combat_and_pursuit_to_idle()
		return

	var raw_tgt_cell = target_actor.get("current_cell")
	var tgt_cell: Vector2i = raw_tgt_cell if (raw_tgt_cell is Vector2i) else Vector2i(-1, -1)
	if not IsoMath.is_in_bounds(tgt_cell):
		clear_combat_and_pursuit_to_idle()
		return

	var dist: int = IsoMath.grid_distance(current_cell, tgt_cell)
	if dist <= attack_range:
		# In range: halt movement path and strike when cooldown expires
		if not current_path.is_empty():
			current_path.clear()
			step_accumulator = 0.0
		if attack_cooldown_remaining <= 0.0:
			attack_cooldown_remaining = attack_cooldown
			var eff_damage: float = get_effective_attack_damage()
			if target_actor.has_method("take_damage"):
				target_actor.take_damage(eff_damage, unit_id)
			unit_attacked.emit(unit_id, target_actor_id, eff_damage)
			queue_redraw()
	else:
		# Out of range: step towards target cell
		_advance_pursuit(tgt_cell, delta, speed_mult, nav)

func _advance_pursuit(tgt_cell: Vector2i, delta: float, speed_mult: float, nav: GridNavigation) -> void:
	if nav == null:
		return
	# Recompute route if empty or target moved away from path destination
	if current_path.is_empty() or IsoMath.grid_distance(current_path[-1], tgt_cell) > attack_range:
		var p: Array[Vector2i] = nav.find_path(current_cell, tgt_cell)
		if p.size() > 1:
			if p[0] == current_cell:
				p.remove_at(0)
			# Do not step onto the occupied target cell itself if attack_range >= 1
			if not p.is_empty() and p[-1] == tgt_cell and attack_range > 0:
				p.remove_at(p.size() - 1)
			current_path = p
			if not current_path.is_empty():
				target_cell = current_path[-1]
		elif p.size() == 1 and p[0] != current_cell:
			current_path = p
			target_cell = p[0]
		else:
			return # No reachable route

	if current_path.is_empty():
		return

	step_accumulator += delta * speed_mult
	while step_accumulator >= CELL_STEP_DURATION and not current_path.is_empty():
		step_accumulator -= CELL_STEP_DURATION
		var next_c: Vector2i = current_path[0]
		if not nav.is_cell_walkable(next_c):
			current_path.clear()
			step_accumulator = 0.0
			break
		current_cell = next_c
		current_path.remove_at(0)
		unit_cell_changed.emit(unit_id, current_cell)
		if IsoMath.grid_distance(current_cell, tgt_cell) <= attack_range:
			current_path.clear()
			step_accumulator = 0.0
			break

func clear_combat_and_pursuit_to_idle() -> void:
	target_actor = null
	target_actor_id = ""
	order_state = OrderState.IDLE
	current_path.clear()
	target_cell = current_cell
	step_accumulator = 0.0
	queue_redraw()

func resolve_target_actor() -> void:
	if target_actor != null and is_instance_valid(target_actor):
		return
	if target_actor_id.is_empty():
		if order_state == OrderState.ATTACKING:
			clear_combat_and_pursuit_to_idle()
		return
	if is_instance_valid(world_view):
		var em = world_view.get("enemy_military_mgr")
		if em != null and em.has_method("get_enemy"):
			var e = em.get_enemy(target_actor_id)
			if e != null and is_instance_valid(e) and e.is_alive:
				target_actor = e
				return
		var sm = world_view.get("field_siege_mgr")
		if sm != null and sm.has_method("get_objective"):
			var o = sm.get_objective(target_actor_id)
			if o != null and is_instance_valid(o) and o.is_alive:
				target_actor = o
				return
		var tm = world_view.get("tactical_military_mgr")
		if tm != null and tm.has_method("get_unit"):
			var u = tm.get_unit(target_actor_id)
			if u != null and is_instance_valid(u) and u.is_alive:
				target_actor = u
				return
		var mm = world_view.get("monster_mgr")
		if mm != null:
			if mm.has_method("get_monster_actor"):
				var ma = mm.get_monster_actor(target_actor_id)
				if ma != null and is_instance_valid(ma) and ma.is_alive:
					target_actor = ma
					return
			if mm.has_method("get_nest_actor"):
				var na = mm.get_nest_actor(target_actor_id)
				if na != null and is_instance_valid(na) and na.is_alive:
					target_actor = na
					return
	if order_state == OrderState.ATTACKING:
		clear_combat_and_pursuit_to_idle()

func _process(delta: float) -> void:
	# When MOVING, advance_movement() drives continuous position & walk animation directly.
	var tm = get_time_manager()
	if tm != null and tm.has_method("is_paused") and tm.is_paused():
		_stop_walk_animation()
		return

	if order_state == OrderState.MOVING and not current_path.is_empty():
		return

	_stop_walk_animation()
	var speed_mult_proc: float = 1.0
	if tm != null and tm.get("current_speed") != null:
		speed_mult_proc = float(tm.get("current_speed"))
	if speed_mult_proc > 0.0:
		_sync_unit_visuals(delta * speed_mult_proc)
	var target_local := IsoMath.map_to_local(current_cell)
	var diff := target_local - position
	if diff.length_squared() > 0.25:
		var speed_mult: float = 1.0
		if tm != null and tm.get("current_speed") != null:
			speed_mult = float(tm.get("current_speed"))
		var step := move_speed_px * speed_mult * delta * 2.5
		if diff.length() <= step:
			position = target_local
		else:
			position += diff.normalized() * step
	else:
		position = target_local

static func order_state_to_string(state: int) -> String:
	match state:
		OrderState.MOVING:
			return "moving"
		OrderState.HOLDING:
			return "holding"
		OrderState.ATTACKING:
			return "attacking"
		OrderState.IDLE, _:
			return "idle"

static func string_to_order_state(s: String) -> int:
	match s.to_lower():
		"moving":
			return OrderState.MOVING
		"holding":
			return OrderState.HOLDING
		"attacking":
			return OrderState.ATTACKING
		"idle", _:
			return OrderState.IDLE

func serialize() -> Dictionary:
	var path_arr: Array = []
	for p in current_path:
		path_arr.append([p.x, p.y])

	return {
		"unit_id": unit_id,
		"unit_name": unit_name,
		"unit_type": unit_type,
		"current_cell": [current_cell.x, current_cell.y],
		"target_cell": [target_cell.x, target_cell.y],
		"order_state": order_state_to_string(order_state),
		"formation": formation,
		"control_group_id": control_group_id,
		"current_path": path_arr,
		"health": health,
		"max_health": max_health,
		"attack_damage": attack_damage,
		"attack_range": attack_range,
		"attack_cooldown": attack_cooldown,
		"attack_cooldown_remaining": attack_cooldown_remaining,
		"is_alive": is_alive,
		"faction_id": faction_id,
		"target_actor_id": target_actor_id,
		"pos_x": position.x,
		"pos_y": position.y,
		"facing_dir": facing_dir
	}

func deserialize(data: Dictionary) -> bool:
	if data.is_empty():
		return false

	var raw_id = data.get("unit_id")
	if not (raw_id is String) or String(raw_id).strip_edges().is_empty():
		return false

	var raw_cur = data.get("current_cell")
	var cur_c := Vector2i(-1, -1)
	if raw_cur is Array and raw_cur.size() >= 2:
		cur_c = Vector2i(int(raw_cur[0]), int(raw_cur[1]))
	elif raw_cur is Vector2i:
		cur_c = raw_cur
	if not IsoMath.is_in_bounds(cur_c):
		return false

	var raw_os = data.get("order_state", "idle")
	var o_state_str: String = ""
	if raw_os is String:
		o_state_str = raw_os.to_lower()
	elif typeof(raw_os) == TYPE_INT or typeof(raw_os) == TYPE_FLOAT:
		var os_int: int = int(raw_os)
		if float(raw_os) != float(os_int) or os_int < 0 or os_int > 3:
			return false
		o_state_str = order_state_to_string(os_int)
	else:
		return false
	if not (o_state_str in ["idle", "moving", "holding", "attacking"]):
		return false
	var o_state_val = string_to_order_state(o_state_str)

	var has_explicit_tgt: bool = data.has("target_cell")
	var tgt_c := cur_c
	if has_explicit_tgt:
		var raw_tgt = data.get("target_cell")
		if raw_tgt is Array and raw_tgt.size() >= 2:
			tgt_c = Vector2i(int(raw_tgt[0]), int(raw_tgt[1]))
		elif raw_tgt is Vector2i:
			tgt_c = raw_tgt
		else:
			return false
	elif o_state_val == OrderState.MOVING:
		return false

	if not IsoMath.is_in_bounds(tgt_c):
		return false

	var parsed_path: Array[Vector2i] = []
	if data.has("current_path"):
		var raw_p = data.get("current_path")
		if not (raw_p is Array):
			return false
		for item in raw_p:
			if item is Array and item.size() >= 2:
				var pt := Vector2i(int(item[0]), int(item[1]))
				if not IsoMath.is_in_bounds(pt):
					return false
				parsed_path.append(pt)
			elif item is Vector2i:
				if not IsoMath.is_in_bounds(item):
					return false
				parsed_path.append(item)
			else:
				return false

	if o_state_val == OrderState.MOVING:
		if parsed_path.is_empty() or parsed_path[-1] != tgt_c:
			return false
	elif o_state_val == OrderState.HOLDING or o_state_val == OrderState.IDLE:
		if not parsed_path.is_empty():
			return false
	elif o_state_val == OrderState.ATTACKING:
		if not parsed_path.is_empty():
			if not has_explicit_tgt:
				tgt_c = parsed_path[-1]
			elif parsed_path[-1] != tgt_c:
				return false

	# All validation passed! Mutate state
	unit_id = String(raw_id).strip_edges()
	unit_name = String(data.get("unit_name", unit_id))
	unit_type = String(data.get("unit_type", "swordsman"))
	formation = String(data.get("formation", "Line"))
	control_group_id = int(data.get("control_group_id", 0))
	current_cell = cur_c
	target_cell = tgt_c
	order_state = o_state_val
	current_path = parsed_path
	step_accumulator = 0.0
	if data.has("pos_x") and data.has("pos_y"):
		var loaded_pos := Vector2(float(data.get("pos_x", 0.0)), float(data.get("pos_y", 0.0)))
		if IsoMath.is_in_bounds(IsoMath.local_to_map(loaded_pos)):
			position = loaded_pos
		else:
			position = IsoMath.map_to_local(current_cell)
	else:
		position = IsoMath.map_to_local(current_cell)
	facing_dir = clampi(int(data.get("facing_dir", ContinuousPathFollower.ScreenDir.E)), 0, 7)
	facing_name = ContinuousPathFollower.dir_to_name(facing_dir)
	_path_follower.last_screen_dir = facing_dir
	_path_follower.last_flip_h = ContinuousPathFollower.should_flip_h(facing_dir, false)
	if sprite != null:
		sprite.flip_h = _path_follower.last_flip_h
	_follower_source_path.clear()

	# Combat properties restoration (Package 1X)
	health = clampf(float(data.get("health", 100.0)), 0.0, float(data.get("max_health", 100.0)))
	max_health = maxf(1.0, float(data.get("max_health", 100.0)))
	attack_damage = maxf(0.0, float(data.get("attack_damage", 25.0)))
	attack_range = maxi(1, int(data.get("attack_range", 1)))
	attack_cooldown = maxf(0.1, float(data.get("attack_cooldown", 1.2)))
	attack_cooldown_remaining = maxf(0.0, float(data.get("attack_cooldown_remaining", 0.0)))
	is_alive = bool(data.get("is_alive", health > 0.0))
	faction_id = String(data.get("faction_id", "player"))
	target_actor_id = String(data.get("target_actor_id", ""))
	target_actor = null
	if order_state == OrderState.ATTACKING and target_actor_id.is_empty():
		clear_combat_and_pursuit_to_idle()
	damage_flash_timer = 0.0
	return true
