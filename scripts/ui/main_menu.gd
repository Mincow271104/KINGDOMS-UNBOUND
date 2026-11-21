class_name MainMenu
extends Control
## Main Menu for KINGDOMS UNBOUND.
## Features: New World (seed, difficulty), Load World (disabled), Settings, and Quit.

const LegacyProfileManagerScript = preload("res://scripts/legacy/legacy_profile_manager.gd")

@onready var main_buttons: VBoxContainer = $CenterContainer/MainPanel/MarginContainer/VBoxContainer/ActionButtons
@onready var new_world_dialog: PanelContainer = $NewWorldOverlay/CenterContainer/NewWorldPanel
@onready var new_world_overlay: Control = $NewWorldOverlay
@onready var settings_overlay: Control = $SettingsOverlay

@onready var world_name_input: LineEdit = $NewWorldOverlay/CenterContainer/NewWorldPanel/MarginContainer/VBoxContainer/NameField/WorldNameInput
@onready var seed_input: LineEdit = $NewWorldOverlay/CenterContainer/NewWorldPanel/MarginContainer/VBoxContainer/SeedField/HBoxContainer/SeedInput
@onready var random_seed_btn: Button = $NewWorldOverlay/CenterContainer/NewWorldPanel/MarginContainer/VBoxContainer/SeedField/HBoxContainer/RandomSeedBtn
@onready var difficulty_options: OptionButton = $NewWorldOverlay/CenterContainer/NewWorldPanel/MarginContainer/VBoxContainer/DifficultyField/DifficultyOptions

@onready var start_game_btn: Button = $NewWorldOverlay/CenterContainer/NewWorldPanel/MarginContainer/VBoxContainer/ButtonBox/StartBtn
@onready var cancel_new_world_btn: Button = $NewWorldOverlay/CenterContainer/NewWorldPanel/MarginContainer/VBoxContainer/ButtonBox/CancelBtn

@onready var btn_new_world: Button = $CenterContainer/MainPanel/MarginContainer/VBoxContainer/ActionButtons/NewWorldBtn
@onready var btn_load_world: Button = $CenterContainer/MainPanel/MarginContainer/VBoxContainer/ActionButtons/LoadWorldBtn
@onready var btn_settings: Button = $CenterContainer/MainPanel/MarginContainer/VBoxContainer/ActionButtons/SettingsBtn
@onready var btn_quit: Button = $CenterContainer/MainPanel/MarginContainer/VBoxContainer/ActionButtons/QuitBtn

@onready var close_settings_btn: Button = $SettingsOverlay/CenterContainer/SettingsPanel/MarginContainer/VBoxContainer/CloseSettingsBtn
@onready var fullscreen_checkbox: CheckBox = $SettingsOverlay/CenterContainer/SettingsPanel/MarginContainer/VBoxContainer/FullscreenCheck
@onready var legacy_fund_label: Label = get_node_or_null("CenterContainer/MainPanel/MarginContainer/VBoxContainer/TitleBox/LegacyFundLabel")

var perks_container: VBoxContainer = null
var modifiers_container: VBoxContainer = null
var perk_checkboxes: Dictionary = {} # perk_id -> CheckBox
var perk_buttons: Dictionary = {} # perk_id -> Button
var modifier_checkboxes: Dictionary = {} # mod_id -> CheckBox

var _compat_overlay: Control = null
var _compat_v1_btn: Button = null
var _compat_v2_btn: Button = null
var _compat_cancel_btn: Button = null
var _compat_title_label: Label = null
var _compat_msg_label: Label = null
var _pending_ambiguous_save_data: Dictionary = {}
var _pending_ambiguous_source: String = ""
var _is_load_in_progress: bool = false
var _load_error_label: Label = null
var last_load_error: String = ""
var last_loaded_world: Node = null

func _ready() -> void:
	DisplayServer.window_set_min_size(Vector2i(1024, 576))
	new_world_overlay.visible = false
	settings_overlay.visible = false
	
	# Main menu buttons
	btn_new_world.pressed.connect(_on_open_new_world)
	
	# Check if save file exists to enable Load World
	var save_file := SaveManager._resolve_filepath(SaveManager.DEFAULT_SAVE_PATH)
	var bak_file := save_file + ".bak"
	if FileAccess.file_exists(save_file) or FileAccess.file_exists(bak_file):
		btn_load_world.disabled = false
		btn_load_world.tooltip_text = "Tải thế giới đã lưu gần nhất"
	else:
		btn_load_world.disabled = true
		btn_load_world.tooltip_text = "Chưa có bản lưu nào"
	btn_load_world.pressed.connect(_on_load_world)

	# Check if autosave exists to provide explicit Autosave restore
	if SaveManager.has_autosave():
		var btn_load_autosave: Button = main_buttons.get_node_or_null("LoadAutosaveBtn")
		if btn_load_autosave == null:
			btn_load_autosave = Button.new()
			btn_load_autosave.name = "LoadAutosaveBtn"
			btn_load_autosave.custom_minimum_size = Vector2(0, 42)
			btn_load_autosave.text = "🔄 Tải Bản Tự Động Lưu"
			btn_load_autosave.tooltip_text = "Tải thế giới từ bản tự động lưu gần nhất"
			main_buttons.add_child(btn_load_autosave)
			main_buttons.move_child(btn_load_autosave, btn_load_world.get_index() + 1)
			btn_load_autosave.pressed.connect(_on_load_autosave)

	btn_settings.pressed.connect(_on_open_settings)
	btn_quit.pressed.connect(_on_quit)
	
	# New world dialog
	random_seed_btn.pressed.connect(_on_randomize_seed)
	start_game_btn.pressed.connect(_on_start_game)
	cancel_new_world_btn.pressed.connect(func(): new_world_overlay.visible = false)
	
	# Settings dialog
	close_settings_btn.pressed.connect(func(): settings_overlay.visible = false)
	var cur_mode := DisplayServer.window_get_mode()
	var is_fs := (cur_mode == DisplayServer.WINDOW_MODE_FULLSCREEN or cur_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	fullscreen_checkbox.set_pressed_no_signal(is_fs)
	fullscreen_checkbox.toggled.connect(_on_fullscreen_toggled)
	
	_setup_difficulty_options()
	_on_randomize_seed()
	_refresh_legacy_display()
	_setup_perks_and_modifiers_ui()

	var profile = LegacyProfileManagerScript.get_instance()
	if profile and not profile.balance_changed.is_connected(_on_legacy_balance_changed):
		profile.balance_changed.connect(_on_legacy_balance_changed)

func _setup_perks_and_modifiers_ui() -> void:
	var vbox: VBoxContainer = $NewWorldOverlay/CenterContainer/NewWorldPanel/MarginContainer/VBoxContainer
	var btn_box = vbox.get_node_or_null("ButtonBox")
	var idx = btn_box.get_index() if btn_box else -1

	var scroll = ScrollContainer.new()
	scroll.name = "MetaProgressionScroll"
	scroll.custom_minimum_size = Vector2(440, 160)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)

	# 1. Perks section
	var sep1 = HSeparator.new()
	content.add_child(sep1)

	var p_hdr = Label.new()
	p_hdr.text = "🏛️ ĐẶC QUYỀN KHỞI ĐẦU (STARTING PERKS):"
	p_hdr.add_theme_color_override("font_color", Color(0.95, 0.85, 0.35, 1.0))
	content.add_child(p_hdr)

	perks_container = VBoxContainer.new()
	perks_container.name = "PerksContainer"
	content.add_child(perks_container)

	# 2. Modifiers section
	var sep2 = HSeparator.new()
	content.add_child(sep2)

	var m_hdr = Label.new()
	m_hdr.text = "🌍 BIẾN TỐ THẾ GIỚI (WORLD MODIFIERS):"
	m_hdr.add_theme_color_override("font_color", Color(0.6, 0.85, 0.95, 1.0))
	content.add_child(m_hdr)

	modifiers_container = VBoxContainer.new()
	modifiers_container.name = "ModifiersContainer"
	content.add_child(modifiers_container)

	if idx >= 0:
		vbox.add_child(scroll)
		vbox.move_child(scroll, idx)
	else:
		vbox.add_child(scroll)

	_populate_perks_ui()
	_populate_modifiers_ui()

func _populate_perks_ui() -> void:
	if perks_container == null:
		return
	for c in perks_container.get_children():
		c.queue_free()
	perk_checkboxes.clear()
	perk_buttons.clear()

	var profile = LegacyProfileManagerScript.get_instance()
	var perks_dict: Dictionary = LegacyProfileManagerScript.STARTING_PERKS

	for pid in perks_dict:
		var p_info: Dictionary = perks_dict[pid]
		var hbox = HBoxContainer.new()
		hbox.name = "PerkRow_" + pid

		var chk = CheckBox.new()
		chk.name = "PerkCheck_" + pid
		chk.text = "%s: %s" % [p_info.get("name", pid), p_info.get("description", "")]
		chk.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var is_unlocked: bool = profile != null and profile.is_perk_unlocked(pid)
		chk.disabled = not is_unlocked
		chk.button_pressed = is_unlocked

		var btn_unlock = Button.new()
		btn_unlock.name = "UnlockBtn_" + pid
		var cost: int = int(p_info.get("cost", 0))
		btn_unlock.text = "Mở khóa (%d điểm)" % cost

		if is_unlocked:
			btn_unlock.visible = false
		else:
			btn_unlock.visible = true
			var check_res: Dictionary = profile.can_purchase_perk(pid) if profile else {"can_purchase": false}
			btn_unlock.disabled = not check_res.get("can_purchase", false)
			if not check_res.get("can_purchase", false):
				btn_unlock.tooltip_text = check_res.get("error", "")

		var captured_pid = pid
		btn_unlock.pressed.connect(func():
			_on_unlock_perk_pressed(captured_pid)
		)

		hbox.add_child(chk)
		hbox.add_child(btn_unlock)
		perks_container.add_child(hbox)

		perk_checkboxes[pid] = chk
		perk_buttons[pid] = btn_unlock

func _on_unlock_perk_pressed(perk_id: String) -> void:
	var profile = LegacyProfileManagerScript.get_instance()
	if profile == null:
		return
	var res: Dictionary = profile.purchase_perk(perk_id)
	if res.get("success", false):
		var am = get_node_or_null("/root/AudioManager")
		if am: am.play_coin()
		_populate_perks_ui()
		_refresh_legacy_display()
	else:
		var am = get_node_or_null("/root/AudioManager")
		if am: am.play_error()
		print("[MainMenu] Failed to purchase perk (%s): %s" % [perk_id, res.get("error", "")])

func _populate_modifiers_ui() -> void:
	if modifiers_container == null:
		return
	for c in modifiers_container.get_children():
		c.queue_free()
	modifier_checkboxes.clear()

	var mods_dict: Dictionary = LegacyProfileManagerScript.WORLD_MODIFIERS
	for mid in mods_dict:
		var m_info: Dictionary = mods_dict[mid]
		var chk = CheckBox.new()
		chk.name = "ModCheck_" + mid
		chk.text = "%s: %s" % [m_info.get("name", mid), m_info.get("description", "")]
		chk.button_pressed = false
		modifiers_container.add_child(chk)
		modifier_checkboxes[mid] = chk

func get_selected_perks() -> Array[String]:
	var res: Array[String] = []
	for pid in perk_checkboxes:
		if is_instance_valid(perk_checkboxes[pid]) and perk_checkboxes[pid].button_pressed:
			res.append(pid)
	return res

func get_selected_modifiers() -> Array[String]:
	var res: Array[String] = []
	for mid in modifier_checkboxes:
		if is_instance_valid(modifier_checkboxes[mid]) and modifier_checkboxes[mid].button_pressed:
			res.append(mid)
	return res

func set_perk_selected(perk_id: String, selected: bool) -> void:
	if perk_checkboxes.has(perk_id) and is_instance_valid(perk_checkboxes[perk_id]):
		if not perk_checkboxes[perk_id].disabled or not selected:
			perk_checkboxes[perk_id].button_pressed = selected

func set_modifier_selected(mod_id: String, selected: bool) -> void:
	if modifier_checkboxes.has(mod_id) and is_instance_valid(modifier_checkboxes[mod_id]):
		modifier_checkboxes[mod_id].button_pressed = selected

func _refresh_legacy_display() -> void:
	if legacy_fund_label:
		var profile = LegacyProfileManagerScript.get_instance()
		if profile == null:
			legacy_fund_label.text = "🏛️ Quỹ Di Sản: Không khả dụng"
			return
		if profile.has_method("is_available") and not profile.is_available():
			legacy_fund_label.text = "🏛️ Quỹ Di Sản: [Lỗi Dữ Liệu]"
			return
		var bal: int = profile.legacy_balance
		legacy_fund_label.text = "🏛️ Quỹ Di Sản: %d điểm" % bal

func _on_legacy_balance_changed(new_balance: int) -> void:
	if legacy_fund_label:
		var profile = LegacyProfileManagerScript.get_instance()
		if profile != null and profile.has_method("is_available") and not profile.is_available():
			legacy_fund_label.text = "🏛️ Quỹ Di Sản: [Lỗi Dữ Liệu]"
		else:
			legacy_fund_label.text = "🏛️ Quỹ Di Sản: %d điểm" % new_balance

func _setup_difficulty_options() -> void:
	difficulty_options.clear()
	difficulty_options.add_item("Dễ (Nhiều tài nguyên, dân ít đói)", 0)
	difficulty_options.add_item("Tiêu Chuẩn (Cân bằng GDD v1.0)", 1)
	difficulty_options.add_item("Thử Thách (Mùa đông khắc nghiệt)", 2)
	difficulty_options.select(1) # Default: Standard

func _play_click() -> void:
	var am = get_node_or_null("/root/AudioManager")
	if am: am.play_click()

func _on_open_new_world() -> void:
	_play_click()
	_populate_perks_ui()
	new_world_overlay.visible = true

func _on_open_settings() -> void:
	_play_click()
	var cur_mode := DisplayServer.window_get_mode()
	var is_fs := (cur_mode == DisplayServer.WINDOW_MODE_FULLSCREEN or cur_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	fullscreen_checkbox.set_pressed_no_signal(is_fs)
	settings_overlay.visible = true

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if is_compatibility_dialog_open() and event.keycode == KEY_ESCAPE:
			cancel_compatibility_dialog()
			if get_viewport() != null:
				get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F11:
			var cur_mode := DisplayServer.window_get_mode()
			var is_fs := (cur_mode == DisplayServer.WINDOW_MODE_FULLSCREEN or cur_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			_on_fullscreen_toggled(not is_fs)
			if fullscreen_checkbox:
				fullscreen_checkbox.set_pressed_no_signal(not is_fs)

func _on_randomize_seed() -> void:
	_play_click()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	seed_input.text = str(rng.randi_range(10000, 9999999))

func _on_start_game() -> void:
	_play_click()
	var s_val := int(seed_input.text)
	if s_val == 0:
		s_val = 12345
		
	# Reset TimeManager clock for the new world
	if get_node_or_null("/root/TimeManager"):
		get_node("/root/TimeManager").reset_time(6, 1, 1)
		
	# Instantiates WorldView scene
	var world_scene: Node = load("res://scenes/world/world_view.tscn").instantiate()
	world_scene.set("world_seed", s_val)
	var WorldViewScript = load("res://scripts/world/world_view.gd")
	if WorldViewScript != null and WorldViewScript.has_method("generate_unique_world_id"):
		world_scene.set("world_id", WorldViewScript.generate_unique_world_id(s_val))
	world_scene.set("is_world_id_persisted", false)

	# Package 4B: Pass active perks, world modifiers, and difficulty
	world_scene.set("active_perks", get_selected_perks())
	world_scene.set("world_modifiers", get_selected_modifiers())
	var diff_str := "normal"
	if difficulty_options.selected == 0:
		diff_str = "easy"
	elif difficulty_options.selected == 2:
		diff_str = "hard"
	world_scene.set("difficulty", diff_str)
	
	var root := get_tree().root
	root.add_child(world_scene)
	get_tree().current_scene = world_scene
	queue_free()

func _on_load_world() -> void:
	_load_save_data_into_world(SaveManager.DEFAULT_SAVE_PATH)

func _on_load_autosave() -> void:
	_load_save_data_into_world(SaveManager.get_autosave_path())

func _load_save_data_into_world(save_filepath: String) -> void:
	if _is_load_in_progress or is_compatibility_dialog_open():
		return
	_play_click()
	var am = get_node_or_null("/root/AudioManager")
	var load_res: Dictionary = SaveManager.load_from_file(save_filepath)
	if not load_res.get("success", false):
		_report_load_error(load_res.get("error", "Không thể đọc tệp bản lưu."), save_filepath)
		if am: am.play_error()
		return

	var save_data: Dictionary = load_res.get("data", {})
	await start_load_from_save_data(save_data, save_filepath)

func start_load_from_save_data(save_data: Dictionary, source_label: String = "in_memory") -> void:
	if _is_load_in_progress or is_compatibility_dialog_open():
		return
	last_load_error = ""
	if _load_error_label != null:
		_load_error_label.visible = false
	var am = get_node_or_null("/root/AudioManager")
	var val_res: Dictionary = SaveManager.validate_save_data(save_data)
	if not val_res.get("valid", false):
		_report_load_error(val_res.get("error", "Dữ liệu bản lưu không hợp lệ."), source_label)
		if am: am.play_error()
		return

	var meta: Dictionary = save_data.get("metadata", {})
	var gen_res: Dictionary = SaveManager.resolve_save_generator_version(meta)
	var gen_status: int = int(gen_res.get("status", SaveManager.GeneratorVersionStatus.UNSUPPORTED))

	if gen_status == SaveManager.GeneratorVersionStatus.UNSUPPORTED:
		_report_load_error(gen_res.get("error", "Phiên bản bộ tạo thế giới không được hỗ trợ."), source_label)
		if am: am.play_error()
		return

	if gen_status == SaveManager.GeneratorVersionStatus.AMBIGUOUS_MISSING:
		_open_compatibility_dialog(save_data, source_label)
		return

	var explicit_ver: int = int(gen_res.get("version", -1))
	await _execute_world_load_with_version(save_data, explicit_ver, source_label)

func _execute_world_load_with_version(save_data: Dictionary, gen_ver: int, source_label: String) -> void:
	if _is_load_in_progress:
		return
	_is_load_in_progress = true
	var am = get_node_or_null("/root/AudioManager")
	var meta: Dictionary = save_data.get("metadata", {})
	var s_val: int = meta.get("world_seed", 12345)

	# Instantiates WorldView scene in staged recovery mode before retiring MainMenu
	var world_scene: Node = load("res://scenes/world/world_view.tscn").instantiate()
	world_scene.set("is_loading_save", true)
	world_scene.set("world_seed", s_val)
	world_scene.set("world_generator_version", gen_ver)
	var WorldViewScript = load("res://scripts/world/world_view.gd")
	if WorldViewScript != null and WorldViewScript.has_method("generate_unique_world_id"):
		world_scene.set("world_id", WorldViewScript.generate_unique_world_id(s_val))
	world_scene.set("is_world_id_persisted", false)

	var root := get_tree().root
	root.add_child(world_scene)

	# Wait for child nodes to complete _ready()
	await get_tree().process_frame

	# Apply loaded state to world and verify restoration succeeded before switching scenes
	var apply_res: Dictionary = SaveManager.apply_loaded_state_to_world(world_scene, save_data, false, gen_ver)
	if not apply_res.get("success", false):
		_report_load_error(apply_res.get("error", "Không thể áp dụng trạng thái bản lưu."), source_label)
		if is_instance_valid(world_scene):
			if world_scene.get_parent() == root:
				root.remove_child(world_scene)
			world_scene.queue_free()
		_is_load_in_progress = false
		if am: am.play_error()
		return

	last_loaded_world = world_scene
	_is_load_in_progress = false
	if am: am.play_coin()
	get_tree().current_scene = world_scene
	queue_free()

func _report_load_error(err_msg: String, source_label: String = "") -> void:
	last_load_error = err_msg
	print("[MainMenu] Load error (%s): %s" % [source_label, err_msg])
	if _load_error_label == null and main_buttons != null:
		_load_error_label = Label.new()
		_load_error_label.name = "LoadErrorLabel"
		_load_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_load_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_load_error_label.add_theme_color_override("font_color", Color(1.0, 0.42, 0.42))
		main_buttons.add_child(_load_error_label)
	if _load_error_label != null:
		_load_error_label.text = err_msg
		_load_error_label.visible = true

func _ensure_compatibility_dialog() -> void:
	if _compat_overlay != null:
		return
	_compat_overlay = Control.new()
	_compat_overlay.name = "GeneratorCompatibilityOverlay"
	_compat_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_compat_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_compat_overlay.visible = false
	_compat_overlay.z_index = 100

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.04, 0.05, 0.08, 0.78)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_compat_overlay.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	_compat_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.13, 0.17, 0.98)
	sb.border_color = Color(0.76, 0.63, 0.35, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	_compat_title_label = Label.new()
	_compat_title_label.text = "World Generator Compatibility"
	_compat_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_compat_title_label.add_theme_font_size_override("font_size", 20)
	_compat_title_label.add_theme_color_override("font_color", Color(0.96, 0.85, 0.55))
	vbox.add_child(_compat_title_label)

	_compat_msg_label = Label.new()
	_compat_msg_label.text = "Save này chưa lưu phiên bản tạo bản đồ. Hãy chọn phiên bản phù hợp với thế giới đã lưu."
	_compat_msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_compat_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_compat_msg_label)

	_compat_v1_btn = Button.new()
	_compat_v1_btn.name = "SelectV1Btn"
	_compat_v1_btn.text = "V1: Pre-Batch 03"
	_compat_v1_btn.custom_minimum_size = Vector2(0, 40)
	_compat_v1_btn.focus_mode = Control.FOCUS_ALL
	_compat_v1_btn.pressed.connect(func(): select_compatibility_version(1))
	vbox.add_child(_compat_v1_btn)

	var v1_desc := Label.new()
	v1_desc.text = "Bản đồ cũ, chưa có Hills/Mountains."
	v1_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v1_desc.add_theme_color_override("font_color", Color(0.75, 0.78, 0.84))
	vbox.add_child(v1_desc)

	_compat_v2_btn = Button.new()
	_compat_v2_btn.name = "SelectV2Btn"
	_compat_v2_btn.text = "V2: Batch 03"
	_compat_v2_btn.custom_minimum_size = Vector2(0, 40)
	_compat_v2_btn.focus_mode = Control.FOCUS_ALL
	_compat_v2_btn.pressed.connect(func(): select_compatibility_version(2))
	vbox.add_child(_compat_v2_btn)

	var v2_desc := Label.new()
	v2_desc.text = "Bản đồ có Hills/Mountains theo thuật toán Batch 03 ban đầu."
	v2_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v2_desc.add_theme_color_override("font_color", Color(0.75, 0.78, 0.84))
	vbox.add_child(v2_desc)

	_compat_cancel_btn = Button.new()
	_compat_cancel_btn.name = "CancelCompatBtn"
	_compat_cancel_btn.text = "Hủy"
	_compat_cancel_btn.custom_minimum_size = Vector2(0, 38)
	_compat_cancel_btn.focus_mode = Control.FOCUS_ALL
	_compat_cancel_btn.pressed.connect(cancel_compatibility_dialog)
	vbox.add_child(_compat_cancel_btn)

	add_child(_compat_overlay)

func _open_compatibility_dialog(save_data: Dictionary, source_label: String) -> void:
	_ensure_compatibility_dialog()
	_pending_ambiguous_save_data = save_data
	_pending_ambiguous_source = source_label
	_compat_v1_btn.disabled = false
	_compat_v2_btn.disabled = false
	_compat_cancel_btn.disabled = false
	_compat_overlay.visible = true

func is_compatibility_dialog_open() -> bool:
	return _compat_overlay != null and _compat_overlay.visible

func select_compatibility_version(version: int) -> void:
	if not is_compatibility_dialog_open() or _is_load_in_progress:
		return
	if not (version in [WorldGenerator.LEGACY_GENERATOR_VERSION, WorldGenerator.BATCH03_GENERATOR_VERSION]):
		return
	var save_copy: Dictionary = _pending_ambiguous_save_data
	var source_copy: String = _pending_ambiguous_source
	_pending_ambiguous_save_data = {}
	_pending_ambiguous_source = ""
	_compat_v1_btn.disabled = true
	_compat_v2_btn.disabled = true
	_compat_cancel_btn.disabled = true
	_compat_overlay.visible = false
	call_deferred("_execute_world_load_with_version", save_copy, version, source_copy)

func cancel_compatibility_dialog() -> void:
	if not is_compatibility_dialog_open() or _is_load_in_progress:
		return
	_pending_ambiguous_save_data = {}
	_pending_ambiguous_source = ""
	_compat_overlay.visible = false

func _on_fullscreen_toggled(is_fullscreen: bool) -> void:
	if is_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _on_quit() -> void:
	get_tree().quit()
