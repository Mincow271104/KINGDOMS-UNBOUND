class_name EntityInspectPanel
extends PanelContainer
## Unified Read-Only World Entity Inspector Panel (M6-1).
## Displays structured, localized inspection for Wildlife, Monsters, Caves / Nests,
## POIs, Individual Military Units, and Natural Resource Nodes.
## Uses explicit user-clicked action_requested signal for lawful contextual commands
## (Claim POI, Attack Nest, Target Monster when units selected) without ever mutating state passively.

signal close_requested()
signal action_requested(action_id: String, target_id: String)

var _icon_rect: TextureRect = null
var _title_label: Label = null
var _subtitle_label: Label = null
var _close_btn: Button = null
var _coords_label: Label = null
var _status_label: Label = null
var _bar_container: VBoxContainer = null
var _bar_label: Label = null
var _progress_bar: ProgressBar = null
var _bar_fill_style: StyleBoxFlat = null
var _rows_vbox: VBoxContainer = null
var _footer_label: Label = null
var _action_btn: Button = null

var _current_action_id: String = ""
var _current_target_id: String = ""

func _init() -> void:
	name = "EntityInspectPanel"
	visible = false
	_build_ui()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	anchor_top = 1.0
	anchor_bottom = 1.0
	anchor_left = 0.0
	anchor_right = 0.0
	offset_left = 16.0
	offset_top = -430.0
	offset_right = 388.0
	offset_bottom = -56.0
	grow_vertical = Control.GROW_DIRECTION_BEGIN

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.10, 0.14, 0.94)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.55, 0.46, 0.25, 0.85)
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 6)
	margin.add_child(root_vbox)

	# Header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	root_vbox.add_child(header)

	_icon_rect = TextureRect.new()
	_icon_rect.custom_minimum_size = Vector2(36, 32)
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	header.add_child(_icon_rect)

	var title_vbox := VBoxContainer.new()
	title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_vbox.add_theme_constant_override("separation", 1)
	header.add_child(title_vbox)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 15)
	_title_label.add_theme_color_override("font_color", Color(0.96, 0.84, 0.42, 1.0))
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_vbox.add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.add_theme_font_size_override("font_size", 11)
	_subtitle_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.86, 1.0))
	_subtitle_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_vbox.add_child(_subtitle_label)

	_close_btn = Button.new()
	_close_btn.name = "CloseEntityInspectBtn"
	_close_btn.text = "✕"
	_close_btn.custom_minimum_size = Vector2(28, 28)
	_close_btn.pressed.connect(func(): close_requested.emit())
	header.add_child(_close_btn)

	# Meta / Coordinates + Status
	_coords_label = Label.new()
	_coords_label.add_theme_font_size_override("font_size", 11)
	_coords_label.add_theme_color_override("font_color", Color(0.68, 0.74, 0.82, 1.0))
	_coords_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_vbox.add_child(_coords_label)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_vbox.add_child(_status_label)

	# Progress Bar Section (HP / Resource Qty)
	_bar_container = VBoxContainer.new()
	_bar_container.add_theme_constant_override("separation", 3)
	_bar_container.visible = false
	root_vbox.add_child(_bar_container)

	_bar_label = Label.new()
	_bar_label.add_theme_font_size_override("font_size", 11)
	_bar_label.add_theme_color_override("font_color", Color(0.90, 0.92, 0.95, 1.0))
	_bar_container.add_child(_bar_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(0, 14)
	_progress_bar.show_percentage = false
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.16, 0.18, 0.22, 1.0)
	bar_bg.corner_radius_top_left = 3
	bar_bg.corner_radius_top_right = 3
	bar_bg.corner_radius_bottom_left = 3
	bar_bg.corner_radius_bottom_right = 3
	_progress_bar.add_theme_stylebox_override("background", bar_bg)
	_bar_fill_style = StyleBoxFlat.new()
	_bar_fill_style.bg_color = Color(0.35, 0.80, 0.55, 1.0)
	_bar_fill_style.corner_radius_top_left = 3
	_bar_fill_style.corner_radius_top_right = 3
	_bar_fill_style.corner_radius_bottom_left = 3
	_bar_fill_style.corner_radius_bottom_right = 3
	_progress_bar.add_theme_stylebox_override("fill", _bar_fill_style)
	_bar_container.add_child(_progress_bar)

	var sep := HSeparator.new()
	root_vbox.add_child(sep)

	# Scrollable Details
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll)

	_rows_vbox = VBoxContainer.new()
	_rows_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_vbox.add_theme_constant_override("separation", 5)
	scroll.add_child(_rows_vbox)

	# Footer Hint & Action Button
	_footer_label = Label.new()
	_footer_label.add_theme_font_size_override("font_size", 11)
	_footer_label.add_theme_color_override("font_color", Color(0.68, 0.72, 0.78, 1.0))
	_footer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer_label.visible = false
	root_vbox.add_child(_footer_label)

	_action_btn = Button.new()
	_action_btn.name = "EntityInspectActionBtn"
	_action_btn.visible = false
	_action_btn.pressed.connect(func():
		if not _current_action_id.is_empty() and not _current_target_id.is_empty():
			action_requested.emit(_current_action_id, _current_target_id)
	)
	root_vbox.add_child(_action_btn)

func render_view_model(vm: Dictionary, icon_tex: Texture2D = null) -> void:
	if vm.is_empty() or not bool(vm.get("valid", false)):
		clear_and_hide()
		return

	_icon_rect.texture = icon_tex
	_title_label.text = str(vm.get("title", "Thực Thể"))
	_subtitle_label.text = str(vm.get("subtitle", ""))
	_coords_label.text = str(vm.get("coords_text", ""))

	var st_col: Color = vm.get("status_color", Color(0.85, 0.88, 0.92, 1.0))
	_status_label.text = "Trạng thái: %s" % str(vm.get("status_text", ""))
	_status_label.add_theme_color_override("font_color", st_col)

	var show_bar := bool(vm.get("show_bar", false))
	_bar_container.visible = show_bar
	if show_bar:
		_progress_bar.max_value = maxf(1.0, float(vm.get("bar_max", 100.0)))
		_progress_bar.value = clampf(float(vm.get("bar_value", 0.0)), 0.0, _progress_bar.max_value)
		_bar_label.text = str(vm.get("bar_text", ""))
		_bar_fill_style.bg_color = vm.get("bar_color", Color(0.35, 0.80, 0.55, 1.0))

	# Rebuild rows cleanly
	for c in _rows_vbox.get_children():
		_rows_vbox.remove_child(c)
		c.queue_free()

	var rows: Array = vm.get("rows", [])
	for r in rows:
		if not (r is Dictionary):
			continue
		if r.has("section"):
			var sec_lbl := Label.new()
			sec_lbl.text = str(r["section"])
			sec_lbl.add_theme_font_size_override("font_size", 11)
			sec_lbl.add_theme_color_override("font_color", Color(0.60, 0.80, 0.95, 1.0))
			_rows_vbox.add_child(sec_lbl)
			continue

		var row_hbox := HBoxContainer.new()
		row_hbox.add_theme_constant_override("separation", 8)
		_rows_vbox.add_child(row_hbox)

		var k_lbl := Label.new()
		k_lbl.text = "%s:" % str(r.get("label", ""))
		k_lbl.custom_minimum_size = Vector2(116, 0)
		k_lbl.add_theme_font_size_override("font_size", 12)
		k_lbl.add_theme_color_override("font_color", Color(0.72, 0.76, 0.82, 1.0))
		row_hbox.add_child(k_lbl)

		var v_lbl := Label.new()
		v_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v_lbl.text = str(r.get("value", ""))
		v_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v_lbl.add_theme_font_size_override("font_size", 12)
		v_lbl.add_theme_color_override("font_color", r.get("color", Color(0.94, 0.95, 0.97, 1.0)))
		row_hbox.add_child(v_lbl)

	var action: Dictionary = vm.get("action", {})
	var footer_note: String = str(vm.get("footer_note", ""))
	if not action.is_empty():
		_current_action_id = str(action.get("action_id", ""))
		_current_target_id = str(action.get("target_id", ""))
		_action_btn.text = str(action.get("label", ""))
		_action_btn.disabled = not bool(action.get("enabled", false))
		_action_btn.visible = true
		var hint_txt: String = str(action.get("hint", ""))
		if not hint_txt.is_empty():
			_footer_label.text = hint_txt
			_footer_label.visible = true
		elif not footer_note.is_empty():
			_footer_label.text = footer_note
			_footer_label.visible = true
		else:
			_footer_label.visible = false
	else:
		_current_action_id = ""
		_current_target_id = ""
		_action_btn.visible = false
		if not footer_note.is_empty():
			_footer_label.text = footer_note
			_footer_label.visible = true
		else:
			_footer_label.visible = false

	visible = true

func clear_and_hide() -> void:
	visible = false
	_current_action_id = ""
	_current_target_id = ""
	_action_btn.visible = false
