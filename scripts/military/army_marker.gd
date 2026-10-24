class_name ArmyMarker
extends Node2D
## Strategic Rally Point & Command Marker (Package 1W & 1M)
## Represents the royal army's rally point and strategic staging marker in the world.
## In tactical unit mode, marks the authoritative rally point (rally_cell) with a
## command banner to avoid visual soldier duplication with deployed tactical unit actors.

var army_mgr: RefCounted = null
var move_speed_px: float = 48.0 # Pixel speed per second

var sprite: Sprite2D = null
var count_label: Label = null
var is_rally_banner_mode: bool = true

func _ready() -> void:
	y_sort_enabled = true
	_setup_visuals()
	if army_mgr != null:
		_bind_army_manager(army_mgr)

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
		sprite.modulate = Color(1.0, 0.35, 0.35, 0.85) # Crimson banner flag tint
		# When tactical units are active, hide the duplicate soldier body so only the rally banner/label displays
		sprite.visible = not is_rally_banner_mode
		add_child(sprite)

	if count_label == null:
		count_label = get_node_or_null("CountLabel")
	if count_label == null:
		count_label = Label.new()
		count_label.name = "CountLabel"
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_label.position = Vector2(-40.0, -36.0)
		count_label.size = Vector2(80.0, 16.0)
		count_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4, 1.0))
		count_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		count_label.add_theme_constant_override("shadow_offset_x", 1)
		count_label.add_theme_constant_override("shadow_offset_y", 1)
		count_label.add_theme_font_size_override("font_size", 10)
		add_child(count_label)

func set_player_army_manager(mgr: RefCounted) -> void:
	army_mgr = mgr
	if is_inside_tree() and mgr != null:
		_bind_army_manager(mgr)

func _bind_army_manager(mgr: RefCounted) -> void:
	if mgr == null:
		return
	if mgr.has_signal("army_changed") and not mgr.army_changed.is_connected(_on_army_changed):
		mgr.army_changed.connect(_on_army_changed)
	if mgr.has_signal("movement_state_changed") and not mgr.movement_state_changed.is_connected(_on_movement_state_changed):
		mgr.movement_state_changed.connect(_on_movement_state_changed)
	if mgr.has_signal("army_moved") and not mgr.army_moved.is_connected(_on_army_moved):
		mgr.army_moved.connect(_on_army_moved)

	update_display()
	_update_target_position()

func _on_army_changed(_count: int, _cap: int) -> void:
	update_display()

func _on_movement_state_changed(_state: int, _cur: Vector2i, _dest: Vector2i) -> void:
	update_display()
	_update_target_position()

func _on_army_moved(_new_cell: Vector2i) -> void:
	update_display()
	_update_target_position()

func _get_target_cell() -> Vector2i:
	if army_mgr == null:
		return Vector2i(32, 33)
	if is_rally_banner_mode and army_mgr.has_method("get_rally_cell"):
		return army_mgr.call("get_rally_cell")
	if army_mgr.has_method("get_current_cell"):
		return army_mgr.call("get_current_cell")
	return Vector2i(32, 33)

func _update_target_position() -> void:
	var target_cell := _get_target_cell()
	position = IsoMath.map_to_local(target_cell)

func update_display() -> void:
	if army_mgr == null:
		visible = false
		return

	var count: int = int(army_mgr.call("get_army_count")) if army_mgr.has_method("get_army_count") else 0
	if count <= 0:
		visible = false
		return

	visible = true
	if sprite != null:
		sprite.visible = not is_rally_banner_mode

	if count_label != null:
		if is_rally_banner_mode:
			count_label.text = "🚩 Tập kết (%d)" % count
		else:
			var is_garrisoned: bool = bool(army_mgr.call("is_defense_eligible")) if army_mgr.has_method("is_defense_eligible") else true
			var prefix: String = "🛡️" if is_garrisoned else "⚔️"
			count_label.text = "%s %d" % [prefix, count]

func _process(delta: float) -> void:
	if army_mgr == null:
		visible = false
		return

	var count: int = int(army_mgr.call("get_army_count")) if army_mgr.has_method("get_army_count") else 0
	if count <= 0:
		visible = false
		return

	visible = true
	var target_cell := _get_target_cell()
	var target_pos := IsoMath.map_to_local(target_cell)
	var diff := target_pos - position

	if diff.length_squared() > 0.25:
		var speed_mult: float = 1.0
		if army_mgr.has_method("get_time_manager"):
			var tm = army_mgr.call("get_time_manager")
			if tm != null:
				if tm.has_method("is_paused") and tm.is_paused():
					return # Strictly freeze visual movement while paused
				if tm.get("current_speed") != null:
					speed_mult = float(tm.get("current_speed"))
		var step := move_speed_px * speed_mult * delta * 2.5
		if diff.length() <= step:
			position = target_pos
		else:
			position += diff.normalized() * step
	else:
		position = target_pos
