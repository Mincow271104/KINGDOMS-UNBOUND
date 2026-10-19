class_name InGameHUD
extends CanvasLayer
## In-Game HUD for KINGDOMS UNBOUND.
## Provides time controls, date/season/clock display, resource summary, building menu, citizen inspector, and pause menu.
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
@onready var ore_label: Label = $TopBar/PanelContainer/MarginContainer/HBoxContainer/Resources/OreLabel
@onready var metal_label: Label = $TopBar/PanelContainer/MarginContainer/HBoxContainer/Resources/MetalLabel
@onready var tools_label: Label = $TopBar/PanelContainer/MarginContainer/HBoxContainer/Resources/ToolsLabel
@onready var gold_label: Label = $TopBar/PanelContainer/MarginContainer/HBoxContainer/Resources/GoldLabel
@onready var pop_label: Label = $TopBar/PanelContainer/MarginContainer/HBoxContainer/Resources/PopLabel

@onready var tile_info_label: Label = $BottomBar/PanelContainer/MarginContainer/HBoxContainer/TileInfoLabel
@onready var open_build_btn: Button = $BottomBar/PanelContainer/MarginContainer/HBoxContainer/BuildBtn
@onready var open_research_btn: Button = $BottomBar/PanelContainer/MarginContainer/HBoxContainer/ResearchBtn
@onready var open_diplomacy_btn: Button = $BottomBar/PanelContainer/MarginContainer/HBoxContainer/DiplomacyBtn
@onready var open_military_btn: Button = $BottomBar/PanelContainer/MarginContainer/HBoxContainer.get_node_or_null("MilitaryBtn")
@onready var pause_menu_dialog: Control = $PauseMenuOverlay
@onready var save_game_btn: Button = $PauseMenuOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SaveGameBtn
@onready var load_game_btn: Button = $PauseMenuOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/LoadGameBtn
@onready var save_status_label: Label = $PauseMenuOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SaveStatusLabel
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

# Military / Army Panel
@onready var army_panel: Control = get_node_or_null("ArmyPanel")
@onready var army_count_label: Label = get_node_or_null("ArmyPanel/MarginContainer/VBoxContainer/ArmyStatsVBox/ArmyCountLabel")
@onready var barracks_count_label: Label = get_node_or_null("ArmyPanel/MarginContainer/VBoxContainer/ArmyStatsVBox/BarracksCountLabel")
@onready var deployment_label: Label = get_node_or_null("ArmyPanel/MarginContainer/VBoxContainer/ArmyStatsVBox/DeploymentLabel")
@onready var supply_status_label: Label = get_node_or_null("ArmyPanel/MarginContainer/VBoxContainer/ArmyStatsVBox/SupplyStatusLabel")
@onready var upkeep_label: Label = get_node_or_null("ArmyPanel/MarginContainer/VBoxContainer/ArmyStatsVBox/UpkeepLabel")
@onready var recruit_cost_label: Label = get_node_or_null("ArmyPanel/MarginContainer/VBoxContainer/ArmyStatsVBox/RecruitCostLabel")
@onready var recruit_btn: Button = get_node_or_null("ArmyPanel/MarginContainer/VBoxContainer/RecruitBtn")
@onready var move_army_btn: Button = get_node_or_null("ArmyPanel/MarginContainer/VBoxContainer/MoveArmyBtn")
@onready var return_home_btn: Button = get_node_or_null("ArmyPanel/MarginContainer/VBoxContainer/ReturnHomeBtn")
@onready var recruit_reason_label: Label = get_node_or_null("ArmyPanel/MarginContainer/VBoxContainer/RecruitReasonLabel")
@onready var close_army_btn: Button = get_node_or_null("ArmyPanel/MarginContainer/VBoxContainer/CloseArmyBtn")

var player_army_mgr: Object = null
var _army_move_targeting: bool = false

# Event Banner
@onready var event_banner: Control = $EventBanner
@onready var event_title: Label = $EventBanner/MarginContainer/VBoxContainer/EventTitle
@onready var event_desc: Label = $EventBanner/MarginContainer/VBoxContainer/EventDesc

# Crisis Banner
@onready var crisis_banner: Control = $CrisisBanner
@onready var crisis_title: Label = $CrisisBanner/MarginContainer/VBoxContainer/CrisisTitle
@onready var crisis_desc: Label = $CrisisBanner/MarginContainer/VBoxContainer/CrisisDesc

# Victory Panel
@onready var victory_panel: Control = $VictoryPanel
@onready var victory_stats_label: Label = $VictoryPanel/MarginContainer/VBoxContainer/VictoryStatsLabel
@onready var continue_victory_btn: Button = $VictoryPanel/MarginContainer/VBoxContainer/HBoxContainer/ContinueVictoryBtn
@onready var return_menu_victory_btn: Button = $VictoryPanel/MarginContainer/VBoxContainer/HBoxContainer/ReturnMenuVictoryBtn

# Collapse Panel
@onready var collapse_panel: Control = $CollapsePanel
@onready var collapse_reason_label: Label = $CollapsePanel/MarginContainer/VBoxContainer/CollapseReasonLabel
@onready var collapse_stats_label: Label = $CollapsePanel/MarginContainer/VBoxContainer/CollapseStatsLabel
@onready var return_menu_collapse_btn: Button = $CollapsePanel/MarginContainer/VBoxContainer/ReturnMenuCollapseBtn

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
var total_housing_cap: int = 24
var barracks_checker: Callable = Callable()

func set_barracks_checker(checker: Callable) -> void:
	barracks_checker = checker
	_refresh_role_options()

func is_barracks_active(barracks_id: String = "") -> bool:
	if barracks_checker.is_valid():
		var argc := barracks_checker.get_argument_count()
		if argc != 0:
			return bool(barracks_checker.call(barracks_id))
		return bool(barracks_checker.call())
	return false

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
	if save_game_btn:
		save_game_btn.pressed.connect(_on_save_game_pressed)
	if load_game_btn:
		load_game_btn.pressed.connect(_on_load_game_pressed)
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
	var btn_watchtower = $BuildMenuPanel/MarginContainer/VBoxContainer/GridContainer.get_node_or_null("WatchtowerBtn")
	if btn_watchtower:
		btn_watchtower.pressed.connect(func(): _select_building("watchtower"))
	var btn_quarry = $BuildMenuPanel/MarginContainer/VBoxContainer/GridContainer.get_node_or_null("QuarryBtn")
	if btn_quarry:
		btn_quarry.pressed.connect(func(): _select_building("quarry"))
	var btn_mine = $BuildMenuPanel/MarginContainer/VBoxContainer/GridContainer.get_node_or_null("MineBtn")
	if btn_mine:
		btn_mine.pressed.connect(func(): _select_building("mine"))
	var btn_workshop = $BuildMenuPanel/MarginContainer/VBoxContainer/GridContainer.get_node_or_null("WorkshopBtn")
	if btn_workshop:
		btn_workshop.pressed.connect(func(): _select_building("workshop"))
	var btn_research_hall = $BuildMenuPanel/MarginContainer/VBoxContainer/GridContainer.get_node_or_null("ResearchHallBtn")
	if btn_research_hall:
		btn_research_hall.pressed.connect(func(): _select_building("research_hall"))
	var btn_barracks = $BuildMenuPanel/MarginContainer/VBoxContainer/GridContainer.get_node_or_null("BarracksBtn")
	if btn_barracks:
		btn_barracks.pressed.connect(func(): _select_building("barracks"))
	var btn_palisade = $BuildMenuPanel/MarginContainer/VBoxContainer/GridContainer.get_node_or_null("PalisadeBtn")
	if btn_palisade:
		btn_palisade.pressed.connect(func(): _select_building("palisade"))
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

	# Military & Army Panel controls
	if army_panel:
		army_panel.visible = false
	if open_military_btn:
		open_military_btn.pressed.connect(_toggle_army_menu)
	if close_army_btn:
		close_army_btn.pressed.connect(func(): if army_panel: army_panel.visible = false)
	if recruit_btn:
		recruit_btn.pressed.connect(_on_recruit_btn_pressed)
	if move_army_btn:
		move_army_btn.pressed.connect(start_army_move_targeting)
	if return_home_btn:
		return_home_btn.pressed.connect(_on_return_home_btn_pressed)

	# Victory & Collapse dialog controls
	if continue_victory_btn:
		continue_victory_btn.pressed.connect(func():
			victory_panel.visible = false
			if get_node_or_null("/root/TimeManager"):
				get_node("/root/TimeManager").resume()
		)
	if return_menu_victory_btn:
		return_menu_victory_btn.pressed.connect(func(): return_to_menu_requested.emit())
	if return_menu_collapse_btn:
		return_menu_collapse_btn.pressed.connect(func(): return_to_menu_requested.emit())

	# Event & Crisis Banner controls
	if event_banner:
		event_banner.visible = false
	if crisis_banner:
		crisis_banner.visible = false
		crisis_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE

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
	role_option_btn.add_item("Thợ Mỏ / Khai Thác Đá & Quặng (Miner)", 4)
	role_option_btn.add_item("Dân Tự Do (Idle)", 5)
	role_option_btn.add_item("Thợ Xưởng (Smith)", 6)
	role_option_btn.add_item("Vệ Binh (Guard)", 7)
	_refresh_role_options()

func _refresh_role_options() -> void:
	if role_option_btn == null or role_option_btn.item_count <= 7:
		return
	var active: bool = is_barracks_active()
	if active:
		role_option_btn.set_item_text(7, "Vệ Binh (Guard)")
		role_option_btn.set_item_disabled(7, false)
	else:
		role_option_btn.set_item_text(7, "Vệ Binh (Cần Doanh Trại)")
		role_option_btn.set_item_disabled(7, true)

func set_research_manager(mgr: Object) -> void:
	if research_mgr == mgr and mgr != null:
		return
	research_mgr = mgr
	if research_mgr:
		if not research_mgr.tech_progress_updated.is_connected(_on_tech_progress_updated):
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
	var has_hall: bool = research_mgr.call("has_active_hall") if research_mgr.has_method("has_active_hall") else true

	if not has_hall:
		if active_id != "":
			var def: Dictionary = TechTree.TECHNOLOGIES.get(active_id, {})
			var t_name: String = def.get("name", active_id)
			var prog: float = research_mgr.get("active_progress_hours")
			var req: float = research_mgr.get("active_required_hours")
			tech_status_label.text = "⏸️ Tạm dừng: %s [%.1f / %.1f giờ] (Cần Viện Nghiên Cứu hoạt động)" % [t_name, prog, req]
		else:
			tech_status_label.text = "⚠️ Cần xây dựng Viện Nghiên Cứu Hoàng Gia để bắt đầu nghiên cứu"
	elif active_id != "":
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
			var cur_tech: String = str(tech_id)
			var check: Dictionary = research_mgr.call("can_research", cur_tech, rm)
			if check.get("valid", false):
				btn.text = " 🔬 %s (%s) — Chi phí: %s(%.0f giờ)" % [def.get("name"), def.get("branch"), cost_str, def.get("duration_hours", 12.0)]
				btn.pressed.connect(func():
					var ok: bool = research_mgr.call("start_research", cur_tech, rm)
					var am = get_node_or_null("/root/AudioManager")
					if ok and am:
						am.play_click()
					_refresh_research_ui()
				)
			else:
				btn.text = " 🔒 %s (%s) — [%s]" % [def.get("name"), def.get("branch"), check.get("reason", "Khóa")]
				btn.disabled = true
				btn.modulate = Color(0.7, 0.7, 0.7)
				
		tech_list_vbox.add_child(btn)

func _on_tech_progress_updated(tech_id: String, progress_hours: float, total_hours: float) -> void:
	if research_menu_panel.visible:
		var has_hall: bool = research_mgr.call("has_active_hall") if (research_mgr and research_mgr.has_method("has_active_hall")) else true
		var def: Dictionary = TechTree.TECHNOLOGIES.get(tech_id, {})
		var t_name: String = def.get("name", tech_id)
		if not has_hall:
			tech_status_label.text = "⏸️ Tạm dừng: %s [%.1f / %.1f giờ] (Cần Viện Nghiên Cứu hoạt động)" % [t_name, progress_hours, total_hours]
		else:
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

var battle_campaign_mgr: Object = null

func set_battle_campaign_manager(mgr: Object) -> void:
	battle_campaign_mgr = mgr
	if battle_campaign_mgr != null:
		if not battle_campaign_mgr.raid_scheduled.is_connected(_on_battle_raid_scheduled):
			battle_campaign_mgr.raid_scheduled.connect(_on_battle_raid_scheduled)
		if not battle_campaign_mgr.raid_cancelled.is_connected(_on_battle_raid_cancelled):
			battle_campaign_mgr.raid_cancelled.connect(_on_battle_raid_cancelled)
		if not battle_campaign_mgr.battle_resolved.is_connected(_on_battle_resolved):
			battle_campaign_mgr.battle_resolved.connect(_on_battle_resolved)

func _on_battle_raid_scheduled(faction_id: String, scheduled_day: int, _is_first: bool) -> void:
	var fac_name: String = faction_id
	if faction_mgr != null:
		var f = faction_mgr.call("get_faction", faction_id)
		if f != null:
			fac_name = f.get("name")
	var msg: String = "⚠️ ĐỊCH CHUẨN BỊ TẤN CÔNG! %s sẽ mở cuộc đột kích vào Ngày %d!" % [fac_name, scheduled_day]
	show_event_banner("Cảnh Báo Đột Kích!", msg, false, 6.0)
	_refresh_diplomacy_ui()

func _on_battle_raid_cancelled(faction_id: String, reason: String) -> void:
	var fac_name: String = faction_id
	if faction_mgr != null:
		var f = faction_mgr.call("get_faction", faction_id)
		if f != null:
			fac_name = f.get("name")
	var msg: String = "Kế hoạch đột kích của %s đã bị hủy bỏ: %s." % [fac_name, reason]
	show_event_banner("Hủy Bỏ Đột Kích", msg, true, 5.0)
	_refresh_diplomacy_ui()

func _on_battle_resolved(report: BattleResolver.BattleReport, context: Dictionary) -> void:
	var victor: String = report.victor
	var is_win: bool = (victor == "defender")
	var title: String = "THẮNG TRẬN!" if is_win else ("THẤT THỦ!" if victor == "attacker" else "BẤT PHÂN THẮNG BẠI!")
	var army_lost: int = context.get("army_casualties", 0)
	var guards_lost: int = context.get("guards_killed", []).size()
	var enemy_lost: int = context.get("enemy_casualties", 0)
	var fort_lvl: int = report.details.get("fortification_level", 0)
	var fort_bonus: float = report.details.get("fortification_bonus", 1.0)
	var spoils: Dictionary = context.get("plundered_resources", {})
	var spoils_str: String = ""
	if not spoils.is_empty():
		spoils_str = " | Cướp phá: %s" % str(spoils)

	var desc: String = "%s\n[Quân đội mất: %d | Vệ binh mất: %d | Địch thương vong: %d | Công sự: Cấp %d (x%.2f)%s]" % [
		report.explanation,
		army_lost,
		guards_lost,
		enemy_lost,
		fort_lvl,
		fort_bonus,
		spoils_str
	]
	show_event_banner(title, desc, is_win, 8.0)
	_refresh_diplomacy_ui()
	_refresh_army_panel()

func _toggle_diplomacy_menu() -> void:
	diplomacy_panel.visible = not diplomacy_panel.visible
	if diplomacy_panel.visible:
		_refresh_diplomacy_ui()

# -----------------------------------------------------------------------------
# Military & Army Panel Methods (Package 1L)
# -----------------------------------------------------------------------------

func set_player_army_manager(mgr: Object) -> void:
	player_army_mgr = mgr
	if player_army_mgr != null:
		if not player_army_mgr.army_changed.is_connected(_on_army_changed):
			player_army_mgr.army_changed.connect(_on_army_changed)
		if not player_army_mgr.supply_status_changed.is_connected(_on_army_supply_changed):
			player_army_mgr.supply_status_changed.connect(_on_army_supply_changed)
		if not player_army_mgr.recruitment_completed.is_connected(_on_recruitment_completed):
			player_army_mgr.recruitment_completed.connect(_on_recruitment_completed)
		if player_army_mgr.has_signal("movement_state_changed") and not player_army_mgr.movement_state_changed.is_connected(_on_army_movement_state_changed):
			player_army_mgr.movement_state_changed.connect(_on_army_movement_state_changed)
		if player_army_mgr.has_signal("army_moved") and not player_army_mgr.army_moved.is_connected(_on_army_moved):
			player_army_mgr.army_moved.connect(_on_army_moved)
	_refresh_army_panel()

func _on_army_changed(_count: int, _cap: int) -> void:
	_refresh_army_panel()

func _on_army_supply_changed(_supplied: bool) -> void:
	_refresh_army_panel()

func _on_recruitment_completed(_count: int, _cost: Dictionary) -> void:
	_refresh_army_panel()
	_refresh_all_resources()

func _on_army_movement_state_changed(_state: int, _cur: Vector2i, _dest: Vector2i) -> void:
	_refresh_army_panel()

func _on_army_moved(_new_cell: Vector2i) -> void:
	_refresh_army_panel()

func _toggle_army_menu() -> void:
	if not army_panel:
		return
	if _army_move_targeting:
		cancel_army_move_targeting()
	army_panel.visible = not army_panel.visible
	if army_panel.visible:
		build_menu_panel.visible = false
		research_menu_panel.visible = false
		if diplomacy_panel:
			diplomacy_panel.visible = false
		_refresh_army_panel()

func _refresh_army_panel() -> void:
	if not army_panel or not is_instance_valid(army_panel):
		return
	if player_army_mgr == null:
		if army_count_label: army_count_label.text = "⚔️ Quân số chính quy: 0 / 0 lính"
		if recruit_btn: recruit_btn.disabled = true
		if move_army_btn: move_army_btn.disabled = true
		if return_home_btn: return_home_btn.disabled = true
		if recruit_reason_label: recruit_reason_label.text = "Hệ thống quân đội chưa khởi tạo"
		return

	var count: int = player_army_mgr.call("get_army_count")
	var cap: int = player_army_mgr.call("get_army_capacity")
	var is_sup: bool = player_army_mgr.get("is_supplied")
	var morale: float = player_army_mgr.call("get_combat_morale")
	var upkeep: int = count * EconomyConfig.ARMY_DAILY_FOOD_UPKEEP

	var active_barracks: int = int(cap / float(maxi(1, EconomyConfig.ARMY_CAPACITY_PER_BARRACKS)))
	if barracks_count_label:
		barracks_count_label.text = "🏰 Doanh trại hoạt động: %d (Sức chứa tối đa: %d lính)" % [active_barracks, cap]

	if army_count_label:
		army_count_label.text = "⚔️ Quân số chính quy: %d / %d lính" % [count, cap]

	if deployment_label:
		var m_state_int: int = player_army_mgr.get("movement_state") if player_army_mgr.get("movement_state") != null else 0
		var cur_cell: Vector2i = player_army_mgr.call("get_current_cell") if player_army_mgr.has_method("get_current_cell") else Vector2i.ZERO
		var deploy_text: String = ""
		match m_state_int:
			0: # GARRISONED
				deploy_text = "🛡️ Trạng thái: Đóng quân tại căn cứ (%d, %d)" % [cur_cell.x, cur_cell.y]
				deployment_label.modulate = Color(0.6, 1.0, 0.6)
			1: # MARCHING
				var dest_cell: Vector2i = player_army_mgr.get("destination_cell") if player_army_mgr.get("destination_cell") != null else cur_cell
				deploy_text = "🚩 Trạng thái: Đang hành quân đến (%d, %d)" % [dest_cell.x, dest_cell.y]
				deployment_label.modulate = Color(1.0, 0.85, 0.3)
			2: # IDLE_AT_FIELD
				deploy_text = "⚔️ Trạng thái: Dã chiến tại (%d, %d) [Không thủ thành]" % [cur_cell.x, cur_cell.y]
				deployment_label.modulate = Color(1.0, 0.6, 0.4)
		deployment_label.text = deploy_text

	if supply_status_label:
		if is_sup:
			supply_status_label.text = "🍖 Tình trạng tiếp tế: Đầy đủ (Nhuệ khí: %.0f)" % morale
			supply_status_label.modulate = Color(0.5, 1.0, 0.5)
		else:
			supply_status_label.text = "⚠️ Tình trạng tiếp tế: Thiếu lương (Nhuệ khí: %.0f)" % morale
			supply_status_label.modulate = Color(1.0, 0.4, 0.4)

	if upkeep_label:
		upkeep_label.text = "🌾 Chi phí duy trì: %d Lương thực / ngày" % upkeep

	if recruit_cost_label:
		var cost_parts: Array[String] = []
		for res_id in EconomyConfig.ARMY_RECRUIT_COST:
			var amt: int = EconomyConfig.ARMY_RECRUIT_COST[res_id]
			var r_name: String = EconomyConfig.RESOURCE_NAMES_VI.get(res_id, res_id.capitalize())
			cost_parts.append("%d %s" % [amt, r_name])
		recruit_cost_label.text = "💰 Chi phí mỗi lính: " + ", ".join(cost_parts)

	var check: Dictionary = player_army_mgr.call("can_recruit", 1)
	var can_r: bool = check.get("can_recruit", false)
	var reason: String = check.get("reason", "")

	if recruit_btn:
		recruit_btn.disabled = not can_r
	if recruit_reason_label:
		recruit_reason_label.text = reason if not can_r else ""

	if move_army_btn:
		move_army_btn.disabled = (count <= 0)
	if return_home_btn:
		var is_home: bool = player_army_mgr.call("is_defense_eligible") if player_army_mgr.has_method("is_defense_eligible") else true
		return_home_btn.disabled = (count <= 0 or is_home)

func _on_recruit_btn_pressed() -> void:
	if player_army_mgr == null:
		return
	var res: Dictionary = player_army_mgr.call("recruit", 1)
	if res.get("success", false):
		var am = get_node_or_null("/root/AudioManager")
		if am: am.play_coin()
		show_event_banner("Tuyển Binh Thành Công!", "Đã chiêu mộ thành công 1 binh sĩ vào quân đội hoàng gia.", true, 4.0)
	else:
		var am = get_node_or_null("/root/AudioManager")
		if am: am.play_error()
		show_event_banner("Chiêu Mộ Thất Bại", res.get("reason", "Không thể chiêu mộ binh sĩ"), false, 4.0)
	_refresh_army_panel()
	_refresh_all_resources()

func is_army_move_targeting() -> bool:
	return _army_move_targeting

func start_army_move_targeting() -> void:
	if player_army_mgr == null:
		return
	var count: int = player_army_mgr.call("get_army_count")
	if count <= 0:
		show_event_banner("Chưa Có Binh Sĩ", "Cần tuyển ít nhất 1 binh sĩ để điều động quân đội.", false, 3.0)
		return

	# Mutually exclusive input modes: cancel active building placement and clear ghost preview
	var wv = world_view_ref if world_view_ref != null else (get_parent() if get_parent() != null else null)
	if wv != null and wv.get("placing_building_type") != "":
		if wv.has_method("_cancel_placement"):
			wv.call("_cancel_placement")
		else:
			wv.set("placing_building_type", "")
			var ghost = wv.get("ghost_building_node")
			if ghost:
				ghost.visible = false

	_army_move_targeting = true
	if army_panel:
		army_panel.visible = false
	show_event_banner("Điều Động Quân Đội", "Nhấp chuột trái vào ô trên bản đồ để hành quân. Nhấp chuột phải hoặc ESC để hủy.", true, 4.0)

func cancel_army_move_targeting() -> void:
	if _army_move_targeting:
		_army_move_targeting = false
		show_event_banner("Hủy Điều Động", "Đã hủy chế độ điều động quân đội.", false, 2.0)

func execute_army_move_target(target_cell: Vector2i) -> void:
	if not _army_move_targeting:
		return
	if player_army_mgr == null:
		_army_move_targeting = false
		return
	var res: Dictionary = player_army_mgr.call("order_move", target_cell)
	if res.get("success", false):
		_army_move_targeting = false
		var steps: int = int(res.get("steps", 0))
		var am = get_node_or_null("/root/AudioManager")
		if am and am.has_method("play_click"): am.play_click()
		show_event_banner("Hành Quân!", "Quân đội bắt đầu hành quân đến ô (%d, %d) (%d bước)." % [target_cell.x, target_cell.y, steps], true, 3.0)
	else:
		var am = get_node_or_null("/root/AudioManager")
		if am and am.has_method("play_error"): am.play_error()
		show_event_banner("Không Thể Di Chuyển", res.get("reason", "Vị trí đích không hợp lệ."), false, 3.0)

func _on_return_home_btn_pressed() -> void:
	if player_army_mgr == null:
		return
	var res: Dictionary = player_army_mgr.call("order_return_home")
	if res.get("success", false):
		var am = get_node_or_null("/root/AudioManager")
		if am and am.has_method("play_click"): am.play_click()
		show_event_banner("Rút Về Căn Cứ", "Quân đội đang hành quân trở về căn cứ doanh trại.", true, 3.0)
	else:
		var am = get_node_or_null("/root/AudioManager")
		if am and am.has_method("play_error"): am.play_error()
		show_event_banner("Lệnh Thất Bại", res.get("reason", "Không thể ra lệnh rút về."), false, 3.0)
	_refresh_army_panel()

var _diplomacy_feedback_message: String = ""
var _diplomacy_feedback_is_error: bool = false

func _show_diplomacy_feedback(message: String, is_error: bool = false) -> void:
	_diplomacy_feedback_message = message
	_diplomacy_feedback_is_error = is_error
	var am = get_node_or_null("/root/AudioManager")
	if am:
		if is_error:
			am.play_sfx("error")
		else:
			am.play_sfx("coin")
	_refresh_all_resources()
	_refresh_diplomacy_ui()

func _refresh_diplomacy_ui() -> void:
	if faction_mgr == null:
		return
		
	for child in factions_list_vbox.get_children():
		child.queue_free()
		
	# Display feedback banner if present
	if not _diplomacy_feedback_message.is_empty():
		var fb_panel := PanelContainer.new()
		var fb_lbl := Label.new()
		fb_lbl.text = _diplomacy_feedback_message
		fb_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fb_lbl.modulate = Color(1.5, 0.4, 0.4) if _diplomacy_feedback_is_error else Color(0.4, 1.3, 0.6)
		fb_panel.add_child(fb_lbl)
		factions_list_vbox.add_child(fb_panel)
		
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
		c_vbox.add_theme_constant_override("separation", 6)
		
		var c_title := Label.new()
		c_title.text = "HÀNG HÓA THƯƠNG ĐOÀN (Giao dịch 10 món):"
		c_title.modulate = Color(0.4, 1.2, 0.6)
		c_vbox.add_child(c_title)
		
		var c_grid := GridContainer.new()
		c_grid.columns = 3
		c_grid.add_theme_constant_override("h_separation", 8)
		c_grid.add_theme_constant_override("v_separation", 6)
		
		var rm = get_node_or_null("/root/ResourceManager")
		var inv: Dictionary = active_caravan.get("inventory")
		for res_id in inv:
			if inv[res_id] > 0:
				var cur_res: String = res_id
				var buy_btn := Button.new()
				var price: int = active_caravan.call("get_effective_sell_price", cur_res, 0.0)
				buy_btn.text = "Mua 10 %s (%d Vàng)" % [cur_res, price * 10]
				buy_btn.pressed.connect(func():
					_handle_caravan_buy(cur_res, 10)
				)
				c_grid.add_child(buy_btn)
				
		# Also provide selling surplus goods to caravan for gold
		for res_id in [EconomyConfig.RES_WOOD, EconomyConfig.RES_FOOD, EconomyConfig.RES_STONE, EconomyConfig.RES_HERBS, EconomyConfig.RES_METAL]:
			var cur_res: String = res_id
			var avail_stock: int = rm.get_available_stock(cur_res) if rm != null else 0
			if avail_stock >= 10:
				var sell_price: int = active_caravan.call("get_effective_buy_price", cur_res, 0.0)
				var sell_btn := Button.new()
				sell_btn.text = "Bán 10 %s (+%d Vàng)" % [cur_res, sell_price * 10]
				sell_btn.modulate = Color(1.1, 1.1, 0.7)
				sell_btn.pressed.connect(func():
					_handle_caravan_sell(cur_res, 10)
				)
				c_grid.add_child(sell_btn)
				
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
		var cur_fac_id: String = fac.get("id")
		var cur_fac_name: String = fac.get("name")
		var card := PanelContainer.new()
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)
		
		var title_lbl := Label.new()
		title_lbl.text = "⚔️ %s (%s)" % [cur_fac_name, fac.call("get_disposition_name")]
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

		if fac.get("is_at_war") and battle_campaign_mgr != null:
			var pending: Dictionary = battle_campaign_mgr.call("get_pending_raid", cur_fac_id)
			if not pending.is_empty():
				var raid_lbl := Label.new()
				raid_lbl.text = "⚠️ KẾ HOẠCH ĐỘT KÍCH: Dự kiến tấn công vào Ngày %d (Đợt %d)" % [pending.get("scheduled_day"), pending.get("raid_sequence")]
				raid_lbl.modulate = Color(1.5, 0.4, 0.2)
				vbox.add_child(raid_lbl)
		
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		
		var gift_btn := Button.new()
		gift_btn.text = "Tặng 50 Vàng (+Thiện cảm)"
		gift_btn.pressed.connect(func():
			_handle_faction_gift(cur_fac_id, cur_fac_name, 50)
		)
		hbox.add_child(gift_btn)
		
		if not fac.get("has_nap") and not fac.get("is_at_war"):
			var nap_btn := Button.new()
			nap_btn.text = "Ký Hiệp Ước NAP"
			nap_btn.pressed.connect(func():
				_handle_propose_treaty(cur_fac_id, "nap")
			)
			hbox.add_child(nap_btn)
			
		if not fac.get("is_at_war"):
			var war_btn := Button.new()
			war_btn.text = "Tuyên Chiến"
			war_btn.modulate = Color(1.5, 0.4, 0.4)
			war_btn.pressed.connect(func():
				_handle_declare_war(cur_fac_id)
			)
			hbox.add_child(war_btn)
		else:
			var peace_btn := Button.new()
			peace_btn.text = "Đàm Phán Hòa Bình"
			peace_btn.pressed.connect(func():
				_handle_propose_treaty(cur_fac_id, "peace")
			)
			hbox.add_child(peace_btn)
			
		vbox.add_child(hbox)
		card.add_child(vbox)
		factions_list_vbox.add_child(card)

func _handle_caravan_buy(res_id: String, amount: int) -> void:
	var active_caravan = world_view_ref.get("active_caravan") if world_view_ref != null else null
	if active_caravan == null or not active_caravan.get("is_active"):
		_show_diplomacy_feedback("❌ Thương đoàn đã rời đi!", true)
		return
	var rm = get_node_or_null("/root/ResourceManager")
	var res: Dictionary = active_caravan.call("buy_from_caravan", res_id, amount, rm, 0.0)
	if res.get("success", false):
		_show_diplomacy_feedback("✅ Đã mua %d %s (-%d Vàng) thành công!" % [amount, res_id, res.get("total_cost", 0)], false)
	else:
		_show_diplomacy_feedback("❌ %s" % res.get("reason", "Không thể mua hàng"), true)

func _handle_caravan_sell(res_id: String, amount: int) -> void:
	var active_caravan = world_view_ref.get("active_caravan") if world_view_ref != null else null
	if active_caravan == null or not active_caravan.get("is_active"):
		_show_diplomacy_feedback("❌ Thương đoàn đã rời đi!", true)
		return
	var rm = get_node_or_null("/root/ResourceManager")
	var res: Dictionary = active_caravan.call("sell_to_caravan", res_id, amount, rm, 0.0)
	if res.get("success", false):
		_show_diplomacy_feedback("✅ Đã bán %d %s (+%d Vàng) cho thương đoàn!" % [amount, res_id, res.get("total_payout", 0)], false)
	else:
		_show_diplomacy_feedback("❌ %s" % res.get("reason", "Không thể bán hàng"), true)

func _handle_faction_gift(fac_id: String, fac_name: String, amount: int) -> void:
	if faction_mgr == null:
		return
	var rm = get_node_or_null("/root/ResourceManager")
	var res: Dictionary = faction_mgr.call("send_gift", fac_id, EconomyConfig.RES_GOLD, amount, rm)
	if res.get("success", false):
		_show_diplomacy_feedback("✅ Đã gửi tặng %d Vàng cho %s (+%.0f Thiện cảm)!" % [amount, fac_name, res.get("opinion_gain", 0.0)], false)
	else:
		_show_diplomacy_feedback("❌ %s" % res.get("reason", "Lỗi gửi quà"), true)

func _handle_propose_treaty(fac_id: String, treaty_type: String) -> void:
	if faction_mgr == null:
		return
	var res: Dictionary = faction_mgr.call("propose_treaty", fac_id, treaty_type)
	if res.get("success", false):
		var treaty_name: String = "Hiệp ước Bất Tương Xâm Phạm (NAP)" if treaty_type == "nap" else "Hiệp ước Hòa Bình"
		_show_diplomacy_feedback("✅ Ký kết thành công %s!" % treaty_name, false)
	else:
		_show_diplomacy_feedback("❌ %s" % res.get("reason", "Ký kết hiệp ước thất bại"), true)

func _handle_declare_war(fac_id: String) -> void:
	if faction_mgr == null:
		return
	var res: Dictionary = faction_mgr.call("declare_war", fac_id)
	if res.get("success", false):
		_show_diplomacy_feedback("⚠️ ĐÃ TUYÊN CHIẾN!", true)
	else:
		_show_diplomacy_feedback("❌ %s" % res.get("reason", "Không thể tuyên chiến"), true)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event as InputEventKey
		if k.keycode == KEY_ESCAPE:
			if _army_move_targeting:
				cancel_army_move_targeting()
			elif citizen_panel.visible:
				citizen_panel.visible = false
			elif build_menu_panel.visible:
				build_menu_panel.visible = false
			elif research_menu_panel.visible:
				research_menu_panel.visible = false
			elif diplomacy_panel.visible:
				diplomacy_panel.visible = false
			elif army_panel and army_panel.visible:
				army_panel.visible = false
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
		elif k.keycode == KEY_U:
			_toggle_army_menu()
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
	_refresh_role_options()
	_refresh_inspected_citizen()
	
	# Select current role in dropdown
	var role_str: String = cit.get("role")
	match role_str:
		"farmer": role_option_btn.select(0)
		"woodcutter": role_option_btn.select(1)
		"builder": role_option_btn.select(2)
		"hauler": role_option_btn.select(3)
		"miner", "quarryman": role_option_btn.select(4)
		"smith": role_option_btn.select(6)
		"guard": role_option_btn.select(7)
		_: role_option_btn.select(5)

func _reselect_current_citizen_role() -> void:
	if inspected_citizen == null:
		return
	var cur_role: String = inspected_citizen.get("role")
	match cur_role:
		"farmer": role_option_btn.select(0)
		"woodcutter": role_option_btn.select(1)
		"builder": role_option_btn.select(2)
		"hauler": role_option_btn.select(3)
		"miner", "quarryman": role_option_btn.select(4)
		"smith": role_option_btn.select(6)
		"guard": role_option_btn.select(7)
		_: role_option_btn.select(5)

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
		4: new_role = "miner"
		5: new_role = "idle"
		6: new_role = "smith"
		7:
			if not is_barracks_active():
				var am = get_node_or_null("/root/AudioManager")
				if am:
					am.play_error()
				_reselect_current_citizen_role()
				return
			new_role = "guard"

	var success = inspected_citizen.call("set_role", new_role)
	if success is bool and not success:
		var am = get_node_or_null("/root/AudioManager")
		if am:
			am.play_error()
		_reselect_current_citizen_role()
		return

	citizen_role_changed.emit(inspected_citizen.get("citizen_id"), new_role)
	_refresh_inspected_citizen()

func _toggle_build_menu() -> void:
	build_menu_panel.visible = not build_menu_panel.visible

func _select_building(type: String) -> void:
	if _army_move_targeting:
		cancel_army_move_targeting()
	build_menu_panel.visible = false
	build_requested.emit(type)

func _toggle_pause_menu() -> void:
	pause_menu_dialog.visible = not pause_menu_dialog.visible
	if pause_menu_dialog.visible:
		if save_status_label:
			save_status_label.text = ""
		get_node("/root/TimeManager").pause()

func _close_pause_menu() -> void:
	pause_menu_dialog.visible = false
	get_node("/root/TimeManager").resume()

func _on_save_game_pressed() -> void:
	if world_view_ref == null and get_parent() != null:
		world_view_ref = get_parent()
	if world_view_ref == null:
		if save_status_label:
			save_status_label.text = "Lỗi: Không tìm thấy WorldView"
			save_status_label.modulate = Color(1.0, 0.4, 0.4)
		return
		
	var res: Dictionary = SaveManager.save_to_file(world_view_ref)
	if res.get("success", false):
		var am = get_node_or_null("/root/AudioManager")
		if am: am.play_coin()
		if save_status_label:
			save_status_label.text = "✅ Đã lưu thế giới thành công!"
			save_status_label.modulate = Color(0.5, 1.0, 0.5)
	else:
		var am = get_node_or_null("/root/AudioManager")
		if am: am.play_error()
		if save_status_label:
			save_status_label.text = "❌ Lỗi: " + res.get("error", "Không thể lưu tệp")
			save_status_label.modulate = Color(1.0, 0.4, 0.4)

func _on_load_game_pressed() -> void:
	if world_view_ref == null and get_parent() != null:
		world_view_ref = get_parent()
	if world_view_ref == null:
		return
		
	var load_res: Dictionary = SaveManager.load_from_file()
	if not load_res.get("success", false):
		var am = get_node_or_null("/root/AudioManager")
		if am: am.play_error()
		if save_status_label:
			save_status_label.text = "❌ Lỗi đọc bản lưu: " + load_res.get("error", "")
			save_status_label.modulate = Color(1.0, 0.4, 0.4)
		return
		
	var apply_res: Dictionary = SaveManager.apply_loaded_state_to_world(world_view_ref, load_res["data"])
	if apply_res.get("success", false):
		var am = get_node_or_null("/root/AudioManager")
		if am: am.play_coin()
		if save_status_label:
			save_status_label.text = "✅ Đã tải thế giới thành công!"
			save_status_label.modulate = Color(0.5, 1.0, 0.5)
		_close_pause_menu()
	else:
		var am = get_node_or_null("/root/AudioManager")
		if am: am.play_error()
		if save_status_label:
			save_status_label.text = "❌ Lỗi áp dụng bản lưu: " + apply_res.get("error", "")
			save_status_label.modulate = Color(1.0, 0.4, 0.4)

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
	if army_panel and army_panel.visible:
		_refresh_army_panel()

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
	if ore_label != null:
		ore_label.text = "⛏️ Quặng: %d" % rm.get_available_stock("ore")
	if metal_label != null:
		metal_label.text = "⚔️ Kim loại: %d" % rm.get_available_stock("metal")
	if tools_label != null:
		tools_label.text = "🛠️ Công cụ: %d" % rm.get_available_stock("tools")
	gold_label.text = "🪙 Vàng: %d" % rm.get_available_stock("gold")
	pop_label.text = "👥 Dân số: %d/%d" % [rm.active_population, total_housing_cap]
	if army_panel and army_panel.visible:
		_refresh_army_panel()

func update_population_display(current_pop: int, max_pop: int) -> void:
	total_housing_cap = max_pop
	pop_label.text = "👥 Dân số: %d/%d" % [current_pop, total_housing_cap]

func show_crisis_warning(data: Dictionary) -> void:
	if not crisis_banner:
		return
	crisis_title.text = "⚠️ " + data.get("title", "CẢNH BÁO NGUY CƠ")
	crisis_desc.text = "%s\nKhuyến nghị: %s" % [data.get("message", ""), data.get("recommended_action", "")]
	crisis_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crisis_banner.visible = true
	var timer := get_tree().create_timer(7.0)
	timer.timeout.connect(func():
		if is_instance_valid(crisis_banner):
			crisis_banner.visible = false
	)

func hide_crisis_warning() -> void:
	if crisis_banner:
		crisis_banner.visible = false

func show_victory_panel(report: Dictionary) -> void:
	if not victory_panel:
		return
	if get_node_or_null("/root/TimeManager"):
		get_node("/root/TimeManager").pause()
	var days: int = report.get("days_survived", 0)
	var peak: int = report.get("peak_population", 30)
	var food: int = report.get("food_reserve", 0)
	var gold: int = report.get("treasury", 0)
	var techs: int = report.get("technologies_unlocked", 0)
	var legacy: int = report.get("legacy_points", 100)
	
	victory_stats_label.text = "• Thời gian sinh tồn: %d ngày\n• Dân số đạt đỉnh: %d người\n• Lương thực dự trữ: %d | Ngân khố: %d vàng\n• Công nghệ đã mở khóa: %d\n• Điểm di sản Legacy nhận được: +%d điểm" % [days, peak, food, gold, techs, legacy]
	victory_panel.visible = true
	var am = get_node_or_null("/root/AudioManager")
	if am:
		am.play_fanfare()

func show_collapse_panel(report: Dictionary) -> void:
	if not collapse_panel:
		return
	if get_node_or_null("/root/TimeManager"):
		get_node("/root/TimeManager").pause()
	var days: int = report.get("days_survived", 0)
	var hours: int = report.get("hours_survived", 0)
	var peak: int = report.get("peak_population", 24)
	var cause: String = report.get("primary_cause", "Không rõ nguyên nhân")
	var buildings: int = report.get("buildings_count", 0)
	var techs: int = report.get("technologies_unlocked", 0)
	
	collapse_reason_label.text = "Nguyên nhân chính: %s" % cause
	collapse_stats_label.text = "• Thời gian duy trì: %d ngày %d giờ\n• Dân số cao nhất: %d người\n• Công trình đã xây: %d\n• Công nghệ hoàn thành: %d\n\n(Lưu ý: Dữ liệu thế giới được bảo toàn nguyên vẹn, bạn có thể xem lại hoặc tải bản lưu bất kỳ lúc nào)" % [days, hours, peak, buildings, techs]
	collapse_panel.visible = true
	var am = get_node_or_null("/root/AudioManager")
	if am:
		am.play_alarm()

func set_tile_info(cell: Vector2i, terrain_name: String, building_name: String = "") -> void:
	if building_name != "":
		tile_info_label.text = "Ô: (%d, %d) | Địa hình: %s | Công trình: %s" % [cell.x, cell.y, terrain_name, building_name]
	else:
		tile_info_label.text = "Ô: (%d, %d) | Địa hình: %s" % [cell.x, cell.y, terrain_name]
