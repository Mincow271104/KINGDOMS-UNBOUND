class_name ArmyMarker
extends Node2D
## Visual marker representing the player's recruited army in the world.
## Provides dimetric isometric Y-sorting, ground-anchored foot pivot,
## troop-count indicator, and visual position interpolation toward
## authoritative logical grid coordinates.

var army_mgr: RefCounted = null
var move_speed_px: float = 48.0 # Pixel speed per second

var sprite: Sprite2D = null
var count_label: Label = null

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
		sprite.modulate = Color(1.0, 0.82, 0.35, 1.0) # Distinct gold/royal military attire
		add_child(sprite)

	if count_label == null:
		count_label = get_node_or_null("CountLabel")
	if count_label == null:
		count_label = Label.new()
		count_label.name = "CountLabel"
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_label.position = Vector2(-24.0, -46.0)
		count_label.size = Vector2(48.0, 16.0)
		count_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5, 1.0))
		count_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
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
	if mgr.has_method("get_current_cell"):
		var cur_cell: Vector2i = mgr.call("get_current_cell")
		position = IsoMath.map_to_local(cur_cell)

func _on_army_changed(_count: int, _cap: int) -> void:
	update_display()

func _on_movement_state_changed(_state: int, _cur: Vector2i, _dest: Vector2i) -> void:
	update_display()
	var cur_pos := IsoMath.map_to_local(_cur)
	if (position - cur_pos).length_squared() > 10000.0:
		position = cur_pos

func _on_army_moved(new_cell: Vector2i) -> void:
	update_display()
	# Fast catch-up if teleported/loaded
	if (position - IsoMath.map_to_local(new_cell)).length_squared() > 10000.0:
		position = IsoMath.map_to_local(new_cell)

func update_display() -> void:
	if army_mgr == null:
		visible = false
		return

	var count: int = int(army_mgr.call("get_army_count")) if army_mgr.has_method("get_army_count") else 0
	if count <= 0:
		visible = false
		return

	visible = true
	if count_label != null:
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

	var target_cell: Vector2i = army_mgr.call("get_current_cell") if army_mgr.has_method("get_current_cell") else Vector2i(32, 33)
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
