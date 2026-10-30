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

func _ready() -> void:
	DisplayServer.window_set_min_size(Vector2i(1024, 576))
	new_world_overlay.visible = false
	settings_overlay.visible = false
	
	# Main menu buttons
	btn_new_world.pressed.connect(_on_open_new_world)
	
	# Check if save file exists to enable Load World
	var save_file := "user://saves/world_save.json"
	var bak_file := "user://saves/world_save.json.bak"
	if FileAccess.file_exists(save_file) or FileAccess.file_exists(bak_file):
		btn_load_world.disabled = false
		btn_load_world.tooltip_text = "Tải thế giới đã lưu gần nhất"
	else:
		btn_load_world.disabled = true
		btn_load_world.tooltip_text = "Chưa có bản lưu nào"
	btn_load_world.pressed.connect(_on_load_world)

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

	var profile = LegacyProfileManagerScript.get_instance()
	if profile and not profile.balance_changed.is_connected(_on_legacy_balance_changed):
		profile.balance_changed.connect(_on_legacy_balance_changed)

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
	new_world_overlay.visible = true

func _on_open_settings() -> void:
	_play_click()
	var cur_mode := DisplayServer.window_get_mode()
	var is_fs := (cur_mode == DisplayServer.WINDOW_MODE_FULLSCREEN or cur_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	fullscreen_checkbox.set_pressed_no_signal(is_fs)
	settings_overlay.visible = true

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
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
	
	var root := get_tree().root
	root.add_child(world_scene)
	get_tree().current_scene = world_scene
	queue_free()

func _on_load_world() -> void:
	_play_click()
	var am = get_node_or_null("/root/AudioManager")
	var load_res: Dictionary = SaveManager.load_from_file()
	if not load_res.get("success", false):
		print("[MainMenu] Failed to load save file: %s" % load_res.get("error", ""))
		if am: am.play_error()
		return
		
	if am: am.play_coin()
		
	var save_data: Dictionary = load_res.get("data", {})
	var meta: Dictionary = save_data.get("metadata", {})
	var s_val: int = meta.get("world_seed", 12345)
	
	# Instantiates WorldView scene
	var world_scene: Node = load("res://scenes/world/world_view.tscn").instantiate()
	world_scene.set("world_seed", s_val)
	var WorldViewScript = load("res://scripts/world/world_view.gd")
	if WorldViewScript != null and WorldViewScript.has_method("generate_unique_world_id"):
		world_scene.set("world_id", WorldViewScript.generate_unique_world_id(s_val))
	world_scene.set("is_world_id_persisted", false)
	
	var root := get_tree().root
	root.add_child(world_scene)
	get_tree().current_scene = world_scene
	queue_free()
	
	# Wait for child nodes to complete _ready()
	await get_tree().process_frame
	
	# Apply loaded state to world
	SaveManager.apply_loaded_state_to_world(world_scene, save_data)

func _on_fullscreen_toggled(is_fullscreen: bool) -> void:
	if is_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _on_quit() -> void:
	get_tree().quit()
