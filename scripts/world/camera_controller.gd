class_name CameraController
extends Camera2D
## Isometric Camera Controller with WASD pan, middle-mouse drag, and mouse-wheel zoom.
## Clamped to 64x64 dimetric map boundary.

@export var pan_speed: float = 600.0
@export var zoom_speed: float = 0.15
@export var min_zoom: float = 0.5
@export var max_zoom: float = 3.0

var _is_dragging: bool = false
var _drag_start_mouse: Vector2 = Vector2.ZERO
var _drag_start_camera: Vector2 = Vector2.ZERO

# Isometric map bounding extents (64x64 tiles with 32x16 tile dimensions)
# Top vertex: (0, 0)
# Right vertex: map_to_local(63, 0) = (63*16, 63*8) = (1008, 504)
# Bottom vertex: map_to_local(63, 63) = (0, 1008)
# Left vertex: map_to_local(0, 63) = (-1008, 504)
const MAP_BOUND_LEFT: float = -1200.0
const MAP_BOUND_RIGHT: float = 1200.0
const MAP_BOUND_TOP: float = -200.0
const MAP_BOUND_BOTTOM: float = 1200.0

@export var start_grid_pos: Vector2i = Vector2i(32, 32)
@export var auto_center_on_start: bool = true

func _ready() -> void:
	zoom = Vector2(1.5, 1.5) # Default comfortable zoom level
	if auto_center_on_start:
		position = IsoMath.map_to_local(start_grid_pos)

func _process(delta: float) -> void:
	var move_dir := Vector2.ZERO
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		move_dir.x += 1.0
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		move_dir.x -= 1.0
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		move_dir.y += 1.0
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		move_dir.y -= 1.0
		
	if move_dir != Vector2.ZERO:
		# Scale pan speed inversely with zoom so high zoom moves comfortably
		var current_speed: float = pan_speed / zoom.x
		position += move_dir.normalized() * current_speed * delta
		_clamp_position()

func _unhandled_input(event: InputEvent) -> void:
	# Middle mouse drag
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_is_dragging = true
				_drag_start_mouse = mb.position
				_drag_start_camera = position
			else:
				_is_dragging = false
		# Mouse wheel zoom
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_apply_zoom(zoom_speed)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_apply_zoom(-zoom_speed)
			
	elif event is InputEventMouseMotion and _is_dragging:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		var drag_delta: Vector2 = (mm.position - _drag_start_mouse) / zoom.x
		position = _drag_start_camera - drag_delta
		_clamp_position()

func _apply_zoom(factor: float) -> void:
	var new_zoom_val: float = clampf(zoom.x + factor, min_zoom, max_zoom)
	zoom = Vector2(new_zoom_val, new_zoom_val)

func _clamp_position() -> void:
	position.x = clampf(position.x, MAP_BOUND_LEFT, MAP_BOUND_RIGHT)
	position.y = clampf(position.y, MAP_BOUND_TOP, MAP_BOUND_BOTTOM)

func focus_on_cell(grid_pos: Vector2i) -> void:
	position = IsoMath.map_to_local(grid_pos)
	_clamp_position()
