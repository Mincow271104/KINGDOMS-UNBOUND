class_name EntityHoverTooltip
extends PanelContainer
## Unified Lightweight Contextual Hover Tooltip (M6-1).
## Displays concise localized name, category, and key status for hovered world entities
## without flickering across adjacent cells of the same entity or blocking mouse input.

var _icon_rect: TextureRect = null
var _title_label: Label = null
var _category_label: Label = null
var _status_label: Label = null

var _current_entity_key: String = ""
var _last_signature: String = ""

func _init() -> void:
	name = "EntityHoverTooltip"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()

func _build_ui() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.13, 0.94)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.55, 0.48, 0.28, 0.85)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 9)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 8)
	margin.add_child(hbox)

	_icon_rect = TextureRect.new()
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_rect.custom_minimum_size = Vector2(24, 24)
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hbox.add_child(_icon_rect)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 1)
	hbox.add_child(vbox)

	_title_label = Label.new()
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.add_theme_font_size_override("font_size", 12)
	_title_label.add_theme_color_override("font_color", Color(0.96, 0.88, 0.56, 1.0))
	vbox.add_child(_title_label)

	_category_label = Label.new()
	_category_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_category_label.add_theme_font_size_override("font_size", 10)
	_category_label.add_theme_color_override("font_color", Color(0.68, 0.74, 0.82, 1.0))
	vbox.add_child(_category_label)

	_status_label = Label.new()
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.add_theme_color_override("font_color", Color(0.88, 0.92, 0.96, 1.0))
	vbox.add_child(_status_label)

func update_tooltip(summary: Dictionary, screen_pos: Vector2, viewport_size: Vector2, icon_tex: Texture2D = null) -> void:
	if summary.is_empty() or not bool(summary.get("valid", false)):
		hide_tooltip()
		return

	var key := str(summary.get("entity_key", ""))
	var icon_k := str(summary.get("icon_key", ""))
	var title := str(summary.get("title", ""))
	var cat_lbl := str(summary.get("category_label", ""))
	var status_txt := str(summary.get("status_text", ""))
	var sig := "%s|%s|%s|%s|%s" % [key, icon_k, title, cat_lbl, status_txt]

	if sig != _last_signature:
		_last_signature = sig
		_current_entity_key = key
		_icon_rect.texture = icon_tex
		_title_label.text = title
		_category_label.text = cat_lbl
		_status_label.text = status_txt
		var col: Color = summary.get("accent_color", Color(0.88, 0.92, 0.96, 1.0))
		_status_label.add_theme_color_override("font_color", col)
		reset_size()

	visible = true
	var tip_size := get_combined_minimum_size()
	if size.x > tip_size.x:
		tip_size.x = size.x
	if size.y > tip_size.y:
		tip_size.y = size.y

	var pos := screen_pos + Vector2(18.0, 16.0)
	if pos.x + tip_size.x > viewport_size.x - 10.0:
		pos.x = screen_pos.x - tip_size.x - 14.0
	if pos.y + tip_size.y > viewport_size.y - 52.0:
		pos.y = screen_pos.y - tip_size.y - 12.0
	pos.x = clampf(pos.x, 8.0, maxf(8.0, viewport_size.x - tip_size.x - 8.0))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, viewport_size.y - tip_size.y - 52.0))
	global_position = pos

func hide_tooltip() -> void:
	if visible:
		visible = false
	_current_entity_key = ""
	_last_signature = ""

func get_current_entity_key() -> String:
	return _current_entity_key
