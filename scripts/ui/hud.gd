class_name InGameHUD
extends CanvasLayer
## In-Game HUD for KINGDOMS UNBOUND.
## Provides time controls, date/season/clock display, resource summary, building menu, citizen inspector, and pause menu.

signal pause_menu_requested
signal return_to_menu_requested
signal build_requested(building_type: String)
signal citizen_role_changed(citizen_id: String, new_role: String)

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
@onready var open_build_btn: Button = $BottomBar/PanelContainer/MarginContainer/HBoxContainer/BuildBtn
@onready var pause_menu_dialog: Control = $PauseMenuOverlay
@onready var build_menu_panel: Control = $BuildMenuPanel

# Citizen Inspection Panel
@onready var citizen_panel: Control = $CitizenInspectPanel
@onready var citizen_name_label: Label = $CitizenInspectPanel/MarginContainer/VBoxContainer/CitizenNameLabel
@onready var citizen_role_label: Label = $CitizenInspectPanel/MarginContainer/VBoxContainer/CitizenRoleLabel
@onready var citizen_reason_label: Label = $CitizenInspectPanel/MarginContainer/VBoxContainer/CitizenReasonLabel
@onready var hunger_bar: ProgressBar = $CitizenInspectPanel/MarginContainer/VBoxContainer/NeedsGrid/HungerBar
@onready var fatigue_bar: ProgressBar = $CitizenInspectPanel/MarginContainer/VBoxContainer/NeedsGrid/FatigueBar
@onready var health_bar: ProgressBar = $CitizenInspectPanel/MarginContainer/VBoxContainer/NeedsGrid/HealthBar
@onready var morale_bar: ProgressBar = $CitizenInspectPanel/MarginContainer/VBoxContainer/NeedsGrid/MoraleBar
@onready var role_option_btn: OptionButton = $CitizenInspectPanel/MarginContainer/VBoxContainer/RoleHBox/RoleOptionBtn
@onready var close_citizen_btn: Button = $CitizenInspectPanel/MarginContainer/VBoxContainer/CloseCitizenBtn

var inspected_citizen: Node = null

func _ready() -> void:
	# Connect to TimeManager signals
	if Engine.has_singleton("TimeManager") or get_node_or_null("/root/TimeManager"):
		var tm = get_node("/root/TimeManager")
		tm.time_speed_changed.connect(_on_speed_changed)
		tm.hour_passed.connect(_on_hour_passed)
		tm.day_passed.connect(_on_day_passed)
		_update_time_display()
		_update_speed_buttons(tm.current_speed)
		
	# Connect to ResourceManager signals
	if Engine.has_singleton("ResourceManager") or get_node_or_null("/root/ResourceManager"):
		var rm = get_node("/root/ResourceManager")
		rm.resource_changed.connect(_on_resource_changed)
		_refresh_all_resources()
		
	# Speed buttons
	speed_pause_btn.pressed.connect(func(): get_node("/root/TimeManager").set_speed(0))
	speed_1x_btn.pressed.connect(func(): get_node("/root/TimeManager").set_speed(1))
	speed_2x_btn.pressed.connect(func(): get_node("/root/TimeManager").set_speed(2))
	speed_3x_btn.pressed.connect(func(): get_node("/root/TimeManager").set_speed(3))
	
	# Pause menu controls
	pause_menu_dialog.visible = false
	var resume_btn = $PauseMenuOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ResumeBtn
	var menu_btn = $PauseMenuOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/MenuBtn
	if resume_btn:
		resume_btn.pressed.connect(_close_pause_menu)
	if menu_btn:
		menu_btn.pressed.connect(func(): return_to_menu_requested.emit())

	# Build Menu controls
	build_menu_panel.visible = false
	open_build_btn.pressed.connect(_toggle_build_menu)
	
	var btn_house = $BuildMenuPanel/MarginContainer/VBoxContainer/GridContainer/HouseBtn
	var btn_storehouse = $BuildMenuPanel/MarginContainer/VBoxContainer/GridContainer/StorehouseBtn
	var btn_farm = $BuildMenuPanel/MarginContainer/VBoxContainer/GridContainer/FarmBtn
	var btn_woodcutter = $BuildMenuPanel/MarginContainer/VBoxContainer/GridContainer/WoodcutterBtn
	var btn_close_build = $BuildMenuPanel/MarginContainer/VBoxContainer/CloseBuildBtn
	
	btn_house.pressed.connect(func(): _select_building("house"))
	btn_storehouse.pressed.connect(func(): _select_building("storehouse"))
	btn_farm.pressed.connect(func(): _select_building("farm"))
	btn_woodcutter.pressed.connect(func(): _select_building("woodcutter"))
	btn_close_build.pressed.connect(func(): build_menu_panel.visible = false)

	# Citizen inspector controls
	citizen_panel.visible = false
	close_citizen_btn.pressed.connect(func(): citizen_panel.visible = false)
	_setup_role_options()
	role_option_btn.item_selected.connect(_on_role_option_selected)

func _setup_role_options() -> void:
	role_option_btn.clear()
	role_option_btn.add_item("Nông Dân (Farmer)", 0)
	role_option_btn.add_item("Tiều Phu (Woodcutter)", 1)
	role_option_btn.add_item("Thợ Xây (Builder)", 2)
	role_option_btn.add_item("Khuân Vác (Hauler)", 3)
	role_option_btn.add_item("Dân Tự Do (Idle)", 4)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event as InputEventKey
		if k.keycode == KEY_ESCAPE:
			if citizen_panel.visible:
				citizen_panel.visible = false
			elif build_menu_panel.visible:
				build_menu_panel.visible = false
			else:
				_toggle_pause_menu()
		elif k.keycode == KEY_SPACE:
			get_node("/root/TimeManager").toggle_pause()
		elif k.keycode == KEY_B:
			_toggle_build_menu()
		elif k.keycode == KEY_1:
			get_node("/root/TimeManager").set_speed(1)
		elif k.keycode == KEY_2:
			get_node("/root/TimeManager").set_speed(2)
		elif k.keycode == KEY_3:
			get_node("/root/TimeManager").set_speed(3)

func _process(_delta: float) -> void:
	if citizen_panel.visible and inspected_citizen != null:
		_refresh_inspected_citizen()

func show_citizen_inspector(cit: Node) -> void:
	inspected_citizen = cit
	citizen_panel.visible = true
	_refresh_inspected_citizen()
	
	# Select current role in dropdown
	var role_str: String = cit.get("role")
	match role_str:
		"farmer": role_option_btn.select(0)
		"woodcutter": role_option_btn.select(1)
		"builder": role_option_btn.select(2)
		"hauler": role_option_btn.select(3)
		_: role_option_btn.select(4)

func _refresh_inspected_citizen() -> void:
	if inspected_citizen == null:
		return
	citizen_name_label.text = "%s (%s)" % [inspected_citizen.get("citizen_name"), inspected_citizen.get("citizen_id")]
	citizen_role_label.text = "Nghề nghiệp: %s | Vị trí: %s" % [inspected_citizen.get("role"), inspected_citizen.get("current_cell")]
	citizen_reason_label.text = "Hành vi: %s" % [inspected_citizen.get("status_reason")]
	
	hunger_bar.value = inspected_citizen.get("hunger")
	fatigue_bar.value = inspected_citizen.get("fatigue")
	health_bar.value = inspected_citizen.get("health")
	morale_bar.value = inspected_citizen.get("morale")

func _on_role_option_selected(idx: int) -> void:
	if inspected_citizen == null:
		return
	var new_role := "idle"
	match idx:
		0: new_role = "farmer"
		1: new_role = "woodcutter"
		2: new_role = "builder"
		3: new_role = "hauler"
		4: new_role = "idle"
	inspected_citizen.call("set_role", new_role)
	citizen_role_changed.emit(inspected_citizen.get("citizen_id"), new_role)
	_refresh_inspected_citizen()

func _toggle_build_menu() -> void:
	build_menu_panel.visible = not build_menu_panel.visible

func _select_building(type: String) -> void:
	build_menu_panel.visible = false
	build_requested.emit(type)

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

func _on_resource_changed(_id: String, _avail: int, _total: int) -> void:
	_refresh_all_resources()

func _refresh_all_resources() -> void:
	if not get_node_or_null("/root/ResourceManager"):
		return
	var rm = get_node("/root/ResourceManager")
	food_label.text = "🌾 Lương thực: %d" % rm.get_available_stock("food")
	wood_label.text = "🪵 Gỗ: %d" % rm.get_available_stock("wood")
	stone_label.text = "🪨 Đá: %d" % rm.get_available_stock("stone")
	gold_label.text = "🪙 Vàng: %d" % rm.get_available_stock("gold")
	pop_label.text = "👥 Dân số: %d/24" % rm.active_population

func set_tile_info(cell: Vector2i, terrain_name: String, building_name: String = "") -> void:
	if building_name != "":
		tile_info_label.text = "Ô: (%d, %d) | Địa hình: %s | Công trình: %s" % [cell.x, cell.y, terrain_name, building_name]
	else:
		tile_info_label.text = "Ô: (%d, %d) | Địa hình: %s" % [cell.x, cell.y, terrain_name]
