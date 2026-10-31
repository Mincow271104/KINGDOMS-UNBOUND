class_name CaravanMarker
extends Node2D
## World Presentation Actor for Visiting Trade Caravans (Package 2A)
## Renders a merchant actor and banner at the designated docking perimeter cell.
## Strictly world presentation: trade transactions and persistence remain with TradeCaravan & HUD.

var caravan_ref: RefCounted = null
var docking_cell: Vector2i = Vector2i(-1, -1)
var is_market_dock: bool = false

var sprite: Sprite2D = null
var name_label: Label = null

func _ready() -> void:
	y_sort_enabled = true
	_setup_visuals()

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
		sprite.modulate = Color(1.2, 1.05, 0.4, 1.0) # Warm merchant saffron/gold tint
		add_child(sprite)

	if name_label == null:
		name_label = get_node_or_null("NameLabel")
	if name_label == null:
		name_label = Label.new()
		name_label.name = "NameLabel"
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.position = Vector2(-40.0, -38.0)
		name_label.size = Vector2(80.0, 16.0)
		name_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.45, 1.0))
		name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		name_label.add_theme_constant_override("shadow_offset_x", 1)
		name_label.add_theme_constant_override("shadow_offset_y", 1)
		name_label.add_theme_font_size_override("font_size", 9)
		name_label.text = "🐪 Đoàn Buôn"
		add_child(name_label)

func update_docking(cell: Vector2i, at_market: bool, caravan: RefCounted = null) -> void:
	docking_cell = cell
	is_market_dock = at_market
	caravan_ref = caravan
	_setup_visuals()

	if caravan != null:
		var c_name: String = String(caravan.get("name")) if caravan.get("name") != null else "Đoàn Buôn"
		if name_label != null:
			name_label.text = "🐪 %s" % c_name

	if cell != Vector2i(-1, -1) and IsoMath.is_in_bounds(cell):
		position = IsoMath.map_to_local(cell)
		visible = true
	else:
		visible = false

func get_docking_cell() -> Vector2i:
	return docking_cell

func is_docked_at_market() -> bool:
	return is_market_dock
