class_name MainMenu
extends Control
## Main Menu for KINGDOMS UNBOUND.
## Features: New World (seed, difficulty), Load World (disabled), Settings, and Quit.

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

func _ready() -> void:
	new_world_overlay.visible = false
	settings_overlay.visible = false
	
	# Main menu buttons
	btn_new_world.pressed.connect(_on_open_new_world)
	btn_load_world.disabled = true # Disabled until persistence phases
	btn_load_world.tooltip_text = "Hệ thống lưu trữ sẽ mở ở Phase 6/8"
	btn_settings.pressed.connect(_on_open_settings)
	btn_quit.pressed.connect(_on_quit)
	
	# New world dialog
	random_seed_btn.pressed.connect(_on_randomize_seed)
	start_game_btn.pressed.connect(_on_start_game)
	cancel_new_world_btn.pressed.connect(func(): new_world_overlay.visible = false)
	
	# Settings dialog
	close_settings_btn.pressed.connect(func(): settings_overlay.visible = false)
	fullscreen_checkbox.toggled.connect(_on_fullscreen_toggled)
	
	_setup_difficulty_options()
	_on_randomize_seed()

func _setup_difficulty_options() -> void:
	difficulty_options.clear()
	difficulty_options.add_item("Dễ (Nhiều tài nguyên, dân ít đói)", 0)
	difficulty_options.add_item("Tiêu Chuẩn (Cân bằng GDD v1.0)", 1)
	difficulty_options.add_item("Thử Thách (Mùa đông khắc nghiệt)", 2)
	difficulty_options.select(1) # Default: Standard

func _on_open_new_world() -> void:
	new_world_overlay.visible = true

func _on_open_settings() -> void:
	settings_overlay.visible = true

func _on_randomize_seed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	seed_input.text = str(rng.randi_range(10000, 9999999))

func _on_start_game() -> void:
	var s_val := int(seed_input.text)
	if s_val == 0:
		s_val = 12345
		
	# Reset TimeManager clock for the new world
	if get_node_or_null("/root/TimeManager"):
		get_node("/root/TimeManager").reset_time(6, 1, 1)
		
	# Instantiates WorldView scene
	var world_scene: Node = load("res://scenes/world/world_view.tscn").instantiate()
	world_scene.set("world_seed", s_val)
	
	var root := get_tree().root
	root.add_child(world_scene)
	get_tree().current_scene = world_scene
	queue_free()

func _on_fullscreen_toggled(is_fullscreen: bool) -> void:
	if is_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _on_quit() -> void:
	get_tree().quit()
