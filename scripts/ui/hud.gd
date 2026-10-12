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
const TechTree = preload("res://scripts/research/tech_tree.gd")
const FactionData = preload("res://scripts/factions/faction_data.gd")
const TradeCaravan = preload("res://scripts/trade/trade_caravan.gd")

@onready var stone_label: Label = $TopBar/PanelContainer/MarginContainer/HBoxContainer/Resources/StoneLabel
@onready var gold_label: Label = $TopBar/PanelContainer/MarginContainer/HBoxContainer/Resources/GoldLabel
@onready var pop_label: Label = $TopBar/PanelContainer/MarginContainer/HBoxContainer/Resources/PopLabel

@onready var tile_info_label: Label = $BottomBar/PanelContainer/MarginContainer/HBoxContainer/TileInfoLabel
@onready var open_build_btn: Button = $BottomBar/PanelContainer/MarginContainer/HBoxContainer/BuildBtn
@onready var open_research_btn: Button = $BottomBar/PanelContainer/MarginContainer/HBoxContainer/ResearchBtn
@onready var open_diplomacy_btn: Button = $BottomBar/PanelContainer/MarginContainer/HBoxContainer/DiplomacyBtn
@onready var pause_menu_dialog: Control = $PauseMenuOverlay
@onready var build_menu_panel: Control = $BuildMenuPanel

# Diplomacy & Trade Panel
@onready var diplomacy_panel: Control = $DiplomacyPanel
@onready var caravan_status_label: Label = $DiplomacyPanel/MarginContainer/VBoxContainer/CaravanStatusLabel
@onready var factions_list_vbox: VBoxContainer = $DiplomacyPanel/MarginContainer/VBoxContainer/ScrollContainer/FactionsListVBox
@onready var close_diplomacy_btn: Button = $DiplomacyPanel/MarginContainer/VBoxContainer/CloseDiplomacyBtn

# Research Panel
@onready var research_menu_panel: Control = $ResearchMenuPanel
@onready var tech_status_label: Label = $ResearchMenuPanel/MarginContainer/VBoxContainer/TechStatusLabel
@onready var tech_list_vbox: VBoxContainer = $ResearchMenuPanel/MarginContainer/VBoxContainer/ScrollContainer/TechListVBox
@onready var close_research_btn: Button = $ResearchMenuPanel/MarginContainer/VBoxContainer/CloseResearchBtn

# Event Banner
@onready var event_banner: Control = $EventBanner
@onready var event_title: Label = $EventBanner/MarginContainer/VBoxContainer/EventTitle
@onready var event_desc: Label = $EventBanner/MarginContainer/VBoxContainer/EventDesc

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
var research_mgr: Object = null
var faction_mgr: Object = null
var world_view_ref: Node = null

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

	# Research Menu controls
	research_menu_panel.visible = false
	if open_research_btn:
		open_research_btn.pressed.connect(_toggle_research_menu)
	if close_research_btn:
		close_research_btn.pressed.connect(func(): research_menu_panel.visible = false)

	# Diplomacy & Trade controls
	diplomacy_panel.visible = false
	if open_diplomacy_btn:
		open_diplomacy_btn.pressed.connect(_toggle_diplomacy_menu)
	if close_diplomacy_btn:
		close_diplomacy_btn.pressed.connect(func(): diplomacy_panel.visible = false)

	# Event Banner controls
	if event_banner:
		event_banner.visible = false

	# Connect EventManager signals
	var loop = Engine.get_main_loop()
	if loop is SceneTree and loop.root.has_node("EventManager"):
		var em = loop.root.get_node("EventManager")
		em.event_triggered.connect(func(_id, title, desc, is_pos, _p): show_event_banner(title, desc, is_pos))
		em.poi_discovered.connect(func(_id, p_name, cell): show_event_banner("Khám Phá Địa Điểm!", "%s tại %s" % [p_name, cell], true))
		em.poi_claimed.connect(func(_id, p_name, _rew): show_event_banner("Thu Thập Kho Báu!", "Đã nhận phần thưởng từ %s" % p_name, true))
		em.tech_unlocked.connect(func(_id, t_name): show_event_banner("Nghiên Cứu Hoàn Tất!", "Đã khai mở: %s" % t_name, true))

func _setup_role_options() -> void:
	role_option_btn.clear()
	role_option_btn.add_item("Nông Dân (Farmer)", 0)
	role_option_btn.add_item("Tiều Phu (Woodcutter)", 1)
	role_option_btn.add_item("Thợ Xây (Builder)", 2)
	role_option_btn.add_item("Khuân Vác (Hauler)", 3)
	role_option_btn.add_item("Dân Tự Do (Idle)", 4)

func set_research_manager(mgr: Object) -> void:
	research_mgr = mgr
	if research_mgr:
		research_mgr.tech_started.connect(func(_id): _refresh_research_ui())
		research_mgr.tech_progress_updated.connect(_on_tech_progress_updated)
		research_mgr.tech_completed.connect(func(_id): _refresh_research_ui())
		research_mgr.tech_cancelled.connect(func(_id, _r): _refresh_research_ui())

func _toggle_research_menu() -> void:
	research_menu_panel.visible = not research_menu_panel.visible
	if research_menu_panel.visible:
		_refresh_research_ui()

func _refresh_research_ui() -> void:
	if not research_mgr:
		return
		
	var active_id: String = research_mgr.get("active_tech_id")
	if active_id != "":
		var def: Dictionary = TechTree.TECHNOLOGIES.get(active_id, {})
		var t_name: String = def.get("name", active_id)
		var prog: float = research_mgr.get("active_progress_hours")
		var req: float = research_mgr.get("active_required_hours")
		var pct: float = (prog / maxf(req, 0.001)) * 100.0
		tech_status_label.text = "Đang tiến hành: %s [%.1f / %.1f giờ] (%.0f%%)" % [t_name, prog, req, pct]
	else:
		tech_status_label.text = "Chưa có dự án nghiên cứu nào đang tiến hành"
		
	for child in tech_list_vbox.get_children():
		child.queue_free()
		
	var rm = get_node_or_null("/root/ResourceManager")
	
	for tech_id in TechTree.TECHNOLOGIES:
		var def: Dictionary = TechTree.TECHNOLOGIES[tech_id]
		var is_unlocked: bool = research_mgr.call("is_unlocked", tech_id)
		var is_active: bool = (active_id == tech_id)
		
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 36)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		
		var cost_str := ""
		var cost_dict: Dictionary = def.get("cost", {})
		for c_res in cost_dict:
			cost_str += "%s: %d  " % [c_res, cost_dict[c_res]]
			
		if is_unlocked:
			btn.text = " ✅ %s (%s) — [ĐÃ KHAI MỞ]" % [def.get("name"), def.get("branch")]
			btn.disabled = true
			btn.modulate = Color(0.6, 1.2, 0.6)
		elif is_active:
			btn.text = " ⏳ %s (%s) — [ĐANG NGHIÊN CỨU...]" % [def.get("name"), def.get("branch")]
			btn.disabled = true
			btn.modulate = Color(1.2, 1.2, 0.4)
		else:
			var check: Dictionary = research_mgr.call("can_research", tech_id, rm)
			if check.get("valid", false):
				btn.text = " 🔬 %s (%s) — Chi phí: %s(%.0f giờ)" % [def.get("name"), def.get("branch"), cost_str, def.get("duration_hours", 12.0)]
				btn.pressed.connect(func():
					research_mgr.call("start_research", tech_id, rm)
					_refresh_research_ui()
				)
			else:
				btn.text = " 🔒 %s (%s) — [%s]" % [def.get("name"), def.get("branch"), check.get("reason", "Khóa")]
				btn.disabled = true
				btn.modulate = Color(0.7, 0.7, 0.7)
				
		tech_list_vbox.add_child(btn)

func _on_tech_progress_updated(tech_id: String, progress_hours: float, total_hours: float) -> void:
	if research_menu_panel.visible:
		var def: Dictionary = TechTree.TECHNOLOGIES.get(tech_id, {})
		var t_name: String = def.get("name", tech_id)
		var pct: float = (progress_hours / maxf(total_hours, 0.001)) * 100.0
		tech_status_label.text = "Đang tiến hành: %s [%.1f / %.1f giờ] (%.0f%%)" % [t_name, progress_hours, total_hours, pct]

func show_event_banner(title: String, desc: String, is_positive: bool = true, duration: float = 6.0) -> void:
	if not event_banner:
		return
	event_title.text = title
	event_desc.text = desc
	event_title.modulate = Color(0.2, 1.0, 0.4) if is_positive else Color(1.0, 0.3, 0.3)
	event_banner.visible = true
	
	var timer := get_tree().create_timer(duration)
	timer.timeout.connect(func():
		if is_instance_valid(event_banner):
			event_banner.visible = false
	)

func set_faction_manager(mgr: Object, world_ref: Node = null) -> void:
	faction_mgr = mgr
	world_view_ref = world_ref
	if faction_mgr != null:
		faction_mgr.relation_changed.connect(func(_id, _op, _disp): _refresh_diplomacy_ui())
		faction_mgr.treaty_signed.connect(func(_id, treaty): show_event_banner("Ký Kết Hiệp Ước!", "Đã ký thành công hiệp ước %s" % treaty, true))
		faction_mgr.war_declared.connect(func(_id): show_event_banner("Chiến Tranh!", "Đã nổ ra chiến tranh với thế lực!", false))

func _toggle_diplomacy_menu() -> void:
	diplomacy_panel.visible = not diplomacy_panel.visible
	if diplomacy_panel.visible:
		_refresh_diplomacy_ui()

func _refresh_diplomacy_ui() -> void:
	if faction_mgr == null:
		return
		
	for child in factions_list_vbox.get_children():
		child.queue_free()
		
	# 1. Update Visiting Caravan Status
	var active_caravan = world_view_ref.get("active_caravan") if world_view_ref != null else null
	if active_caravan != null and active_caravan.get("is_active"):
		caravan_status_label.text = "🐪 Đang có mặt: %s (Rời đi ngày %d) | Ngân sách: %d Vàng" % [
			active_caravan.get("name"),
			active_caravan.get("departure_day"),
			active_caravan.get("gold")
		]
		
		# Add caravan quick trade section
		var c_panel := PanelContainer.new()
		var c_vbox := VBoxContainer.new()
		c_vbox.add_theme_constant_override("separation", 4)
		
		var c_title := Label.new()
		c_title.text = "HÀNG HÓA THƯƠNG ĐOÀN (Bấm để mua nhanh 10 món):"
		c_title.modulate = Color(0.4, 1.2, 0.6)
		c_vbox.add_child(c_title)
		
		var c_grid := GridContainer.new()
		c_grid.columns = 3
		c_grid.add_theme_constant_override("h_separation", 8)
		
		var rm = get_node_or_null("/root/ResourceManager")
		var inv: Dictionary = active_caravan.get("inventory")
		for res_id in inv:
			if inv[res_id] > 0:
				var buy_btn := Button.new()
				var price = active_caravan.call("get_effective_sell_price", res_id, 0.0)
				buy_btn.text = "Mua 10 %s (%d Vàng)" % [res_id, price * 10]
				buy_btn.pressed.connect(func():
					active_caravan.call("buy_from_caravan", res_id, 10, rm, 0.0)
					_refresh_diplomacy_ui()
				)
				c_grid.add_child(buy_btn)
				
		c_vbox.add_child(c_grid)
		c_panel.add_child(c_vbox)
		factions_list_vbox.add_child(c_panel)
	else:
		var tm = get_node_or_null("/root/TimeManager")
		var cur_day: int = tm.current_day if tm else 1
		var next_day: int = cur_day + (3 - (cur_day % 5)) if (cur_day % 5) <= 3 else cur_day + (8 - (cur_day % 5))
		caravan_status_label.text = "Chưa có thương đoàn tại quảng trường (Dự kiến đến ngày %d)" % next_day
		
	# 2. List Factions
	var factions = faction_mgr.call("get_all_factions")
	for fac in factions:
		var card := PanelContainer.new()
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)
		
		var title_lbl := Label.new()
		title_lbl.text = "⚔️ %s (%s)" % [fac.get("name"), fac.call("get_disposition_name")]
		title_lbl.modulate = Color(1.0, 0.85, 0.3)
		vbox.add_child(title_lbl)
		
		var info_lbl := Label.new()
		info_lbl.text = "Thiện cảm: %.1f | Quân lực: %.0f | Dân số: %d | NAP: %s | Đồng minh: %s" % [
			fac.get("opinion"),
			fac.get("military_power"),
			fac.get("population"),
			"Có" if fac.get("has_nap") else "Không",
			"Có" if fac.get("has_alliance") else "Không"
		]
		vbox.add_child(info_lbl)
		
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		
		var gift_btn := Button.new()
		gift_btn.text = "Tặng 50 Vàng (+Thiện cảm)"
		gift_btn.pressed.connect(func():
			var rm = get_node_or_null("/root/ResourceManager")
			faction_mgr.call("send_gift", fac.get("id"), EconomyConfig.RES_GOLD, 50, rm)
			_refresh_diplomacy_ui()
		)
		hbox.add_child(gift_btn)
		
		if not fac.get("has_nap") and not fac.get("is_at_war"):
			var nap_btn := Button.new()
			nap_btn.text = "Ký Hiệp Ước NAP"
			nap_btn.pressed.connect(func():
				faction_mgr.call("propose_treaty", fac.get("id"), "nap")
				_refresh_diplomacy_ui()
			)
			hbox.add_child(nap_btn)
			
		if not fac.get("is_at_war"):
			var war_btn := Button.new()
			war_btn.text = "Tuyên Chiến"
			war_btn.modulate = Color(1.5, 0.4, 0.4)
			war_btn.pressed.connect(func():
				faction_mgr.call("declare_war", fac.get("id"))
				_refresh_diplomacy_ui()
			)
			hbox.add_child(war_btn)
		else:
			var peace_btn := Button.new()
			peace_btn.text = "Đàm Phán Hòa Bình"
			peace_btn.pressed.connect(func():
				faction_mgr.call("propose_treaty", fac.get("id"), "peace")
				_refresh_diplomacy_ui()
			)
			hbox.add_child(peace_btn)
			
		vbox.add_child(hbox)
		card.add_child(vbox)
		factions_list_vbox.add_child(card)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event as InputEventKey
		if k.keycode == KEY_ESCAPE:
			if citizen_panel.visible:
				citizen_panel.visible = false
			elif build_menu_panel.visible:
				build_menu_panel.visible = false
			elif research_menu_panel.visible:
				research_menu_panel.visible = false
			elif diplomacy_panel.visible:
				diplomacy_panel.visible = false
			else:
				_toggle_pause_menu()
		elif k.keycode == KEY_SPACE:
			get_node("/root/TimeManager").toggle_pause()
		elif k.keycode == KEY_B:
			_toggle_build_menu()
		elif k.keycode == KEY_T:
			_toggle_research_menu()
		elif k.keycode == KEY_Y:
			_toggle_diplomacy_menu()
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
	var role_text := "Nghề nghiệp: %s | Vị trí: %s" % [inspected_citizen.get("role"), inspected_citizen.get("current_cell")]
	var carry_amt: int = inspected_citizen.get("carrying_amount")
	if carry_amt > 0:
		role_text += " | Mang: %d %s" % [carry_amt, inspected_citizen.get("carrying_resource")]
	citizen_role_label.text = role_text
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
