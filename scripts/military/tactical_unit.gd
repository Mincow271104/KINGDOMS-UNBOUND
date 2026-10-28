class_name TacticalUnit
extends Node2D
## Tactical Military Unit Actor (Package 1W)
## Represents an individual soldier deployed on the world map.
## Features dimetric isometric foot-anchored Y-sorting, discrete logical cell movement,
## continuous visual interpolation, selection indicators, and formation coordination.

enum OrderState {
	IDLE = 0,
	MOVING = 1,
	HOLDING = 2
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

var is_selected: bool = false
var current_path: Array[Vector2i] = []
var step_accumulator: float = 0.0
var move_speed_px: float = 48.0 # Visual catchup speed

var sprite: Sprite2D = null
var world_view: Node = null
var _custom_time_mgr: Object = null

signal unit_reached_destination(unit_id: String, final_cell: Vector2i)
signal unit_cell_changed(unit_id: String, new_cell: Vector2i)

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
		if ResourceLoader.exists("res://assets/entities/citizen.png"):
			sprite.texture = load("res://assets/entities/citizen.png")
		sprite.offset = Vector2(-12.0, -30.0) # Ground contact foot pivot
		sprite.centered = false
		# Distinct royal military golden armor tint
		sprite.modulate = Color(1.0, 0.85, 0.35, 1.0)
		add_child(sprite)

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

func order_move(path: Array, dest: Vector2i) -> void:
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

	current_path = new_path
	target_cell = dest
	step_accumulator = 0.0
	if current_path.is_empty():
		current_cell = dest
		order_state = OrderState.IDLE
	else:
		order_state = OrderState.MOVING

func order_hold() -> void:
	current_path.clear()
	target_cell = current_cell
	step_accumulator = 0.0
	order_state = OrderState.HOLDING

func order_stop() -> void:
	current_path.clear()
	target_cell = current_cell
	step_accumulator = 0.0
	order_state = OrderState.IDLE

func advance_movement(delta: float, speed_mult: float = 1.0, nav: GridNavigation = null) -> void:
	if order_state != OrderState.MOVING or current_path.is_empty():
		if order_state == OrderState.MOVING and current_path.is_empty():
			order_state = OrderState.IDLE
			target_cell = current_cell
			unit_reached_destination.emit(unit_id, current_cell)
		return

	if speed_mult <= 0.0:
		return

	var tm = get_time_manager()
	if tm != null and tm.has_method("is_paused") and tm.is_paused():
		return

	step_accumulator += delta * speed_mult
	while step_accumulator >= CELL_STEP_DURATION and not current_path.is_empty():
		step_accumulator -= CELL_STEP_DURATION
		var next_cell: Vector2i = current_path[0]

		# Verify next cell is still walkable if nav is provided
		if nav != null and not nav.is_cell_walkable(next_cell):
			# Route dynamically obstructed: attempt rerouting to target_cell
			var rerouted: Array[Vector2i] = nav.find_path(current_cell, target_cell)
			if rerouted.is_empty():
				# Halt safely at current cell
				current_path.clear()
				step_accumulator = 0.0
				target_cell = current_cell
				order_state = OrderState.IDLE
				unit_reached_destination.emit(unit_id, current_cell)
				return
			else:
				if rerouted[0] == current_cell:
					rerouted.remove_at(0)
				if rerouted.is_empty():
					current_path.clear()
					step_accumulator = 0.0
					target_cell = current_cell
					order_state = OrderState.IDLE
					unit_reached_destination.emit(unit_id, current_cell)
					return
				current_path = rerouted
				next_cell = current_path[0]

		current_cell = next_cell
		current_path.remove_at(0)
		unit_cell_changed.emit(unit_id, current_cell)

		if current_path.is_empty():
			target_cell = current_cell
			order_state = OrderState.IDLE
			unit_reached_destination.emit(unit_id, current_cell)
			break

func _process(delta: float) -> void:
	# Continuous visual interpolation towards authoritative current_cell local position
	var tm = get_time_manager()
	if tm != null and tm.has_method("is_paused") and tm.is_paused():
		return

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
		OrderState.IDLE, _:
			return "idle"

static func string_to_order_state(s: String) -> int:
	match s.to_lower():
		"moving":
			return OrderState.MOVING
		"holding":
			return OrderState.HOLDING
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
		"current_path": path_arr
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

	var o_state_str = String(data.get("order_state", "idle")).to_lower()
	if not (o_state_str in ["idle", "moving", "holding"]):
		return false
	var o_state_val = string_to_order_state(o_state_str)

	var tgt_c := cur_c
	if data.has("target_cell"):
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
	else:
		if not parsed_path.is_empty():
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
	position = IsoMath.map_to_local(current_cell)
	return true
