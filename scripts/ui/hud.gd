class_name InGameHUD
extends CanvasLayer
## In-Game HUD for KINGDOMS UNBOUND.
## Provides time controls, date/season/clock display, resource summary, and pause menu.

signal pause_menu_requested
signal return_to_menu_requested

@onready var clock_label: Label = $TopBar/PanelContainer/MarginContainer/HBoxContainer/TimeInfo/ClockLabel
@onready var date_label: Label = $TopBar/PanelContainer/MarginContainer/HBoxContainer/TimeInfo/DateLabel
@onready var speed_pause_btn: Button = $TopBar/PanelContainer/MarginContainer/HBoxContainer/SpeedControls/PauseBtn
@onready var speed_1x_btn: Button = $TopBar/PanelContainer/MarginContainer/HBoxContainer/SpeedControls/Speed1xBtn
@onready var speed_2x_btn: Button = $TopBar/PanelContainer/MarginContainer/HBoxContainer/SpeedControls/Speed2xBtn
@onready var speed_3x_btn: Button = $TopBar/PanelContainer/MarginContainer/HBoxContainer/SpeedControls/Speed3xBtn

@onready var food_label: Label = $TopBar/PanelContainer/MarginContainer/HBoxContainer/Resources/FoodLabel
@onready var wood_label: Label = $TopBar/PanelContainer/MarginContainer/HBoxContainer/Resources/WoodLabel
@onready var stone_label: Label = $TopBar/PanelContainer/MarginContainer/HBoxContainer/Resources/StoneLabel
@onready var gold_label: Label = $TopBar/PanelContainer/MarginContainer/HBoxContainer/Resources/GoldLabel
@onready var pop_label: Label = $TopBar/PanelContainer/MarginContainer/HBoxContainer/Resources/PopLabel

@onready var tile_info_label: Label = $BottomBar/PanelContainer/MarginContainer/HBoxContainer/TileInfoLabel
@onready var pause_menu_dialog: Control = $PauseMenuOverlay

func _ready() -> void:
	# Connect to TimeManager signals
	if Engine.has_singleton("TimeManager") or get_node_or_null("/root/TimeManager"):
		var tm = get_node("/root/TimeManager")
		tm.time_speed_changed.connect(_on_speed_changed)
		tm.hour_passed.connect(_on_hour_passed)
		tm.day_passed.connect(_on_day_passed)
		_update_time_display()
		_update_speed_buttons(tm.current_speed)
		
	# Speed buttons
	speed_pause_btn.pressed.connect(func(): get_node("/root/TimeManager").set_speed(0))
	speed_1x_btn.pressed.connect(func(): get_node("/root/TimeManager").set_speed(1))
	speed_2x_btn.pressed.connect(func(): get_node("/root/TimeManager").set_speed(2))
	speed_3x_btn.pressed.connect(func(): get_node("/root/TimeManager").set_speed(3))
	
	# Default starter quantities (Phase 0 / Phase 1 baseline)
	set_resources(150, 120, 60, 200, 24, 24)
	
	# Pause menu controls
	pause_menu_dialog.visible = false
	var resume_btn = $PauseMenuOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ResumeBtn
	var menu_btn = $PauseMenuOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/MenuBtn
	if resume_btn:
		resume_btn.pressed.connect(_close_pause_menu)
	if menu_btn:
		menu_btn.pressed.connect(func(): return_to_menu_requested.emit())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event as InputEventKey
		if k.keycode == KEY_ESCAPE:
			_toggle_pause_menu()
		elif k.keycode == KEY_SPACE:
			get_node("/root/TimeManager").toggle_pause()
		elif k.keycode == KEY_1:
			get_node("/root/TimeManager").set_speed(1)
		elif k.keycode == KEY_2:
			get_node("/root/TimeManager").set_speed(2)
		elif k.keycode == KEY_3:
			get_node("/root/TimeManager").set_speed(3)

func _toggle_pause_menu() -> void:
	pause_menu_dialog.visible = not pause_menu_dialog.visible
	if pause_menu_dialog.visible:
		get_node("/root/TimeManager").pause()

func _close_pause_menu() -> void:
	pause_menu_dialog.visible = false
	get_node("/root/TimeManager").resume()

func _on_speed_changed(new_speed: int) -> void:
	_update_speed_buttons(new_speed)

func _update_speed_buttons(speed: int) -> void:
	speed_pause_btn.modulate = Color(1.2, 0.4, 0.4) if speed == 0 else Color(1, 1, 1, 0.7)
	speed_1x_btn.modulate = Color(0.4, 1.2, 0.4) if speed == 1 else Color(1, 1, 1, 0.7)
	speed_2x_btn.modulate = Color(0.4, 1.2, 0.4) if speed == 2 else Color(1, 1, 1, 0.7)
	speed_3x_btn.modulate = Color(0.4, 1.2, 0.4) if speed == 3 else Color(1, 1, 1, 0.7)

func _on_hour_passed(_hour: int, _day: int) -> void:
	_update_time_display()

func _on_day_passed(_day: int, _season: String, _year: int) -> void:
	_update_time_display()

func _update_time_display() -> void:
	if not get_node_or_null("/root/TimeManager"):
		return
	var tm = get_node("/root/TimeManager")
	clock_label.text = tm.get_clock_string()
	date_label.text = tm.get_date_string()

func set_resources(food: int, wood: int, stone: int, gold: int, pop: int, max_pop: int) -> void:
	food_label.text = "🌾 Lương thực: %d" % food
	wood_label.text = "🪵 Gỗ: %d" % wood
	stone_label.text = "🪨 Đá: %d" % stone
	gold_label.text = "🪙 Vàng: %d" % gold
	pop_label.text = "👥 Dân số: %d/%d" % [pop, max_pop]

func set_tile_info(cell: Vector2i, terrain_name: String, building_name: String = "") -> void:
	if building_name != "":
		tile_info_label.text = "Ô: (%d, %d) | Địa hình: %s | Công trình: %s" % [cell.x, cell.y, terrain_name, building_name]
	else:
		tile_info_label.text = "Ô: (%d, %d) | Địa hình: %s" % [cell.x, cell.y, terrain_name]
