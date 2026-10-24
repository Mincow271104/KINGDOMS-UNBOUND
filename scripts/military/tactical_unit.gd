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
	current_path.clear()
	for p in path:
		if p is Vector2i:
			current_path.append(p)
	if not current_path.is_empty() and current_path[0] == current_cell:
		current_path.remove_at(0)
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

func deserialize(data: Dictionary) -> void:
	unit_id = String(data.get("unit_id", ""))
	unit_name = String(data.get("unit_name", unit_id))
	unit_type = String(data.get("unit_type", "swordsman"))
	formation = String(data.get("formation", "Line"))
	control_group_id = int(data.get("control_group_id", 0))

	var raw_cur = data.get("current_cell")
	if raw_cur is Array and raw_cur.size() >= 2:
		current_cell = Vector2i(int(raw_cur[0]), int(raw_cur[1]))
	elif raw_cur is Vector2i:
		current_cell = raw_cur

	var raw_tgt = data.get("target_cell")
	if raw_tgt is Array and raw_tgt.size() >= 2:
		target_cell = Vector2i(int(raw_tgt[0]), int(raw_tgt[1]))
	elif raw_tgt is Vector2i:
		target_cell = raw_tgt
	else:
		target_cell = current_cell

	order_state = string_to_order_state(String(data.get("order_state", "idle")))

	current_path.clear()
	var raw_path = data.get("current_path")
	if raw_path is Array:
		for item in raw_path:
			if item is Array and item.size() >= 2:
				var pt := Vector2i(int(item[0]), int(item[1]))
				if IsoMath.is_in_bounds(pt):
					current_path.append(pt)

	step_accumulator = 0.0
	position = IsoMath.map_to_local(current_cell)
