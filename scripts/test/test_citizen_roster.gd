extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — PACKAGE 2L
## Settlement Citizen Roster Panel (GDD §14.4)
## Validates complete roster presentation, needs, skills, job/activity reflection,
## reason not working diagnostics, assign-work dispatch, barracks gating, death/immigration lifecycle,
## save/load restoration, and 50+ population layout scaling.

const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const CitizenControllerScript = preload("res://scripts/entities/citizen_controller.gd")
const CitizenSkillDataScript = preload("res://scripts/entities/citizen_skill_data.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const HUDScene: PackedScene = preload("res://scenes/ui/hud.tscn")

var frame_count: int = 0
var tests_executed: bool = false
var failures: int = 0
var passed_count: int = 0
var hud_instance: InGameHUD = null

func _assert(condition: bool, test_name: String, details: String = "") -> void:
	if condition:
		passed_count += 1
		print("  [PASS] %s" % test_name)
	else:
		failures += 1
		printerr("  [FAIL] %s - %s" % [test_name, details])

func _init() -> void:
	print("\n========================================================")
	print("  STARTING PACKAGE 2L CITIZEN ROSTER PANEL TEST SUITE")
	print("========================================================\n")

	hud_instance = HUDScene.instantiate() as InGameHUD
	root.add_child(hud_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count >= 2 and not tests_executed:
		tests_executed = true
		_run_all_tests()
		_print_summary()
		quit(0 if failures == 0 else 1)
		return true
	return false

func _run_all_tests() -> void:
	_run_tc_roster_1_population_count_display()
	_run_tc_roster_2_profession_role_mapping()
	_run_tc_roster_3_health_mapping()
	_run_tc_roster_4_hunger_mapping()
	_run_tc_roster_5_fatigue_mapping()
	_run_tc_roster_6_morale_mapping()
	_run_tc_roster_7_vocational_skill_levels_and_efficiency()
	_run_tc_roster_8_current_activity_states()
	_run_tc_roster_9_reason_not_working_diagnostics()
	_run_tc_roster_10_manual_command_states()
	_run_tc_roster_11_guard_role_and_barracks_gating()
	_run_tc_roster_12_assign_work_action_and_sync()
	_run_tc_roster_13_citizen_death_removal()
	_run_tc_roster_14_immigration_addition()
	_run_tc_roster_15_repeated_refresh_idempotency()
	_run_tc_roster_16_save_load_restoration()
	_run_tc_roster_17_row_selection_inspection_sync()
	_run_tc_roster_18_independent_inspector_coexistence()
	_run_tc_roster_19_mouse_input_consumption()
	_run_tc_roster_20_high_population_scale_50_plus()
	_run_tc_roster_21_vocation_filter()
	_run_tc_roster_22_toggle_and_pop_label_trigger()

func _create_dummy_citizen(cid: String, cname: String, role: String, hp: float = 100.0, hunger: float = 10.0, fatigue: float = 10.0, morale: float = 70.0) -> Node:
	var cit := CitizenControllerScript.new()
	cit.init_citizen(cid, cname, role, Vector2i(32, 32), null, null, null)
	cit.health = hp
	cit.hunger = hunger
	cit.fatigue = fatigue
	cit.morale = morale
	return cit

func _run_tc_roster_1_population_count_display() -> void:
	print("--- Running TC-ROSTER.1: Population Count & 24 Starting Citizens Display ---")
	var citizens: Array = []
	for i in range(24):
		var role := "farmer"
		if i >= 18:
			role = "woodcutter"
		elif i >= 12:
			role = "builder"
		elif i >= 6:
			role = "hauler"
		citizens.append(_create_dummy_citizen("cit_%d" % i, "Dan Lang %d" % i, role))

	hud_instance.set_citizen_list_for_test(citizens)
	hud_instance.open_citizen_roster()

	var rows = hud_instance._roster_rows
	_assert(rows.size() == 24, "TC-ROSTER.1.1", "Expected 24 citizen rows in roster, found: %d" % rows.size())
	_assert(hud_instance.citizen_roster_panel.visible, "TC-ROSTER.1.2", "Citizen roster panel is visible after open_citizen_roster()")

	var summary_text := hud_instance.roster_summary_label.text
	_assert(summary_text.contains("24/24"), "TC-ROSTER.1.3", "Roster summary contains 24/24: '%s'" % summary_text)

	for c in citizens:
		c.queue_free()

func _run_tc_roster_2_profession_role_mapping() -> void:
	print("\n--- Running TC-ROSTER.2: Profession / Role Mapping ---")
	var test_roles = [
		{"role": "farmer", "viet": "Nông Dân"},
		{"role": "woodcutter", "viet": "Tiều Phu"},
		{"role": "builder", "viet": "Thợ Xây"},
		{"role": "hauler", "viet": "Khuân Vác"},
		{"role": "miner", "viet": "Thợ Mỏ"},
		{"role": "smith", "viet": "Thợ Rèn"},
		{"role": "guard", "viet": "Vệ Binh"},
		{"role": "idle", "viet": "Dân Tự Do"}
	]

	var citizens: Array = []
	for i in range(test_roles.size()):
		var info = test_roles[i]
		citizens.append(_create_dummy_citizen("role_cit_%d" % i, "Tho %s" % info["role"], info["role"]))

	hud_instance.set_citizen_list_for_test(citizens)
	hud_instance.refresh_citizen_roster()

	for i in range(test_roles.size()):
		var info = test_roles[i]
		var cid = "role_cit_%d" % i
		var row = hud_instance._roster_rows.get(cid)
		_assert(row != null, "TC-ROSTER.2.1_%s" % info["role"], "Row exists for %s" % cid)
		if row != null:
			var role_lbl: Label = row.get("role_lbl")
			_assert(role_lbl != null and role_lbl.text == info["viet"], "TC-ROSTER.2.2_%s" % info["role"],
				"Expected role label '%s', found '%s'" % [info["viet"], role_lbl.text if role_lbl else "null"])

	for c in citizens:
		c.queue_free()

func _run_tc_roster_3_health_mapping() -> void:
	print("\n--- Running TC-ROSTER.3: Health Mapping & Color Feedback ---")
	var c_full = _create_dummy_citizen("hp_100", "Khoe Manh", "farmer", 100.0)
	var c_mid = _create_dummy_citizen("hp_50", "Bi Thuong", "farmer", 50.0)
	var c_low = _create_dummy_citizen("hp_20", "Hap Hoi", "farmer", 20.0)

	hud_instance.set_citizen_list_for_test([c_full, c_mid, c_low])
	hud_instance.refresh_citizen_roster()

	var r_full = hud_instance._roster_rows.get("hp_100")
	var r_mid = hud_instance._roster_rows.get("hp_50")
	var r_low = hud_instance._roster_rows.get("hp_20")

	_assert(r_full != null and r_full.hp_lbl.text == "100%", "TC-ROSTER.3.1", "100% health label mapped")
	_assert(r_mid != null and r_mid.hp_lbl.text == "50%", "TC-ROSTER.3.2", "50% health label mapped")
	_assert(r_low != null and r_low.hp_lbl.text == "20%", "TC-ROSTER.3.3", "20% health label mapped")

	c_full.queue_free()
	c_mid.queue_free()
	c_low.queue_free()

func _run_tc_roster_4_hunger_mapping() -> void:
	print("\n--- Running TC-ROSTER.4: Hunger Mapping & Warning Colors ---")
	var c_low = _create_dummy_citizen("h_10", "No Du", "farmer", 100.0, 10.0)
	var c_med = _create_dummy_citizen("h_60", "Doi Vua", "farmer", 100.0, 60.0)
	var c_crit = _create_dummy_citizen("h_90", "Doi Khan Cap", "farmer", 100.0, 90.0)

	hud_instance.set_citizen_list_for_test([c_low, c_med, c_crit])
	hud_instance.refresh_citizen_roster()

	var r_low = hud_instance._roster_rows.get("h_10")
	var r_med = hud_instance._roster_rows.get("h_60")
	var r_crit = hud_instance._roster_rows.get("h_90")

	_assert(r_low != null and r_low.hunger_lbl.text == "10%", "TC-ROSTER.4.1", "10% hunger label mapped")
	_assert(r_med != null and r_med.hunger_lbl.text == "60%", "TC-ROSTER.4.2", "60% hunger label mapped")
	_assert(r_crit != null and r_crit.hunger_lbl.text == "90%", "TC-ROSTER.4.3", "90% hunger label mapped")

	c_low.queue_free()
	c_med.queue_free()
	c_crit.queue_free()

func _run_tc_roster_5_fatigue_mapping() -> void:
	print("\n--- Running TC-ROSTER.5: Fatigue Mapping ---")
	var c_rested = _create_dummy_citizen("f_5", "Khoe Khoan", "farmer", 100.0, 10.0, 5.0)
	var c_tired = _create_dummy_citizen("f_70", "Moi Met", "farmer", 100.0, 10.0, 70.0)
	var c_exhaust = _create_dummy_citizen("f_95", "Kiet Suc", "farmer", 100.0, 10.0, 95.0)

	hud_instance.set_citizen_list_for_test([c_rested, c_tired, c_exhaust])
	hud_instance.refresh_citizen_roster()

	var r_rested = hud_instance._roster_rows.get("f_5")
	var r_tired = hud_instance._roster_rows.get("f_70")
	var r_exhaust = hud_instance._roster_rows.get("f_95")

	_assert(r_rested != null and r_rested.fatigue_lbl.text == "5%", "TC-ROSTER.5.1", "5% fatigue label mapped")
	_assert(r_tired != null and r_tired.fatigue_lbl.text == "70%", "TC-ROSTER.5.2", "70% fatigue label mapped")
	_assert(r_exhaust != null and r_exhaust.fatigue_lbl.text == "95%", "TC-ROSTER.5.3", "95% fatigue label mapped")

	c_rested.queue_free()
	c_tired.queue_free()
	c_exhaust.queue_free()

func _run_tc_roster_6_morale_mapping() -> void:
	print("\n--- Running TC-ROSTER.6: Morale Mapping ---")
	var c_high = _create_dummy_citizen("m_85", "Phan Khoi", "farmer", 100.0, 10.0, 10.0, 85.0)
	var c_low = _create_dummy_citizen("m_35", "U Ru", "farmer", 100.0, 10.0, 10.0, 35.0)

	hud_instance.set_citizen_list_for_test([c_high, c_low])
	hud_instance.refresh_citizen_roster()

	var r_high = hud_instance._roster_rows.get("m_85")
	var r_low = hud_instance._roster_rows.get("m_35")

	_assert(r_high != null and r_high.morale_lbl.text == "85%", "TC-ROSTER.6.1", "85% morale mapped")
	_assert(r_low != null and r_low.morale_lbl.text == "35%", "TC-ROSTER.6.2", "35% morale mapped")

	c_high.queue_free()
	c_low.queue_free()

func _run_tc_roster_7_vocational_skill_levels_and_efficiency() -> void:
	print("\n--- Running TC-ROSTER.7: Vocational Skill Progression & Efficiency Bonus ---")
	var cit := _create_dummy_citizen("skill_cit", "Tho Chuyen Nghiep", "woodcutter")
	cit.award_work_xp("woodcutting", 350.0) # Level 3, +16%

	hud_instance.set_citizen_list_for_test([cit])
	hud_instance.refresh_citizen_roster()

	var row = hud_instance._roster_rows.get("skill_cit")
	_assert(row != null, "TC-ROSTER.7.1", "Row exists for skilled citizen")
	if row != null:
		var skill_lbl: Label = row.skill_lbl
		_assert(skill_lbl.text.contains("Lâm nghiệp") or skill_lbl.text.contains("C.3"), "TC-ROSTER.7.2",
			"Skill text reflects vocation & Level 3: '%s'" % skill_lbl.text)
		_assert(skill_lbl.text.contains("+16%"), "TC-ROSTER.7.3",
			"Skill text reflects +16%% bonus: '%s'" % skill_lbl.text)

	# Promote to Level 5 Max
	cit.award_work_xp("woodcutting", 700.0) # 1000 XP max, Level 5, +35%
	hud_instance.refresh_citizen_roster()
	if row != null:
		_assert(row.skill_lbl.text.contains("C.5") and row.skill_lbl.text.contains("+35%"), "TC-ROSTER.7.4",
			"Skill text reflects Level 5 (+35%%): '%s'" % row.skill_lbl.text)

	cit.queue_free()

func _run_tc_roster_8_current_activity_states() -> void:
	print("\n--- Running TC-ROSTER.8: Current Job / Activity Reflection ---")
	var c_idle = _create_dummy_citizen("act_idle", "Nghi Ngoi", "idle")
	c_idle.current_state = CitizenControllerScript.State.IDLE

	var c_work = _create_dummy_citizen("act_work", "Dang Lam", "farmer")
	c_work.current_state = CitizenControllerScript.State.WORKING

	var c_haul = _create_dummy_citizen("act_haul", "Khuan Go", "hauler")
	c_haul.current_state = CitizenControllerScript.State.HAULING
	c_haul.carrying_resource = "wood"
	c_haul.carrying_amount = 5

	var c_food = _create_dummy_citizen("act_food", "Tim An", "farmer")
	c_food.current_state = CitizenControllerScript.State.SEEKING_FOOD

	var c_rest = _create_dummy_citizen("act_rest", "Ngu", "farmer")
	c_rest.current_state = CitizenControllerScript.State.RESTING

	var c_guard = _create_dummy_citizen("act_guard", "Tuan Tra", "guard")
	c_guard.current_state = CitizenControllerScript.State.GUARDING

	hud_instance.set_citizen_list_for_test([c_idle, c_work, c_haul, c_food, c_rest, c_guard])
	hud_instance.refresh_citizen_roster()

	_assert(hud_instance._roster_rows["act_idle"].act_lbl.text.contains("Chờ việc") or hud_instance._roster_rows["act_idle"].act_lbl.text.contains("Nghỉ"), "TC-ROSTER.8.1", "Idle activity")
	_assert(hud_instance._roster_rows["act_work"].act_lbl.text.contains("Đang làm"), "TC-ROSTER.8.2", "Working activity")
	_assert(hud_instance._roster_rows["act_haul"].act_lbl.text.contains("5 wood"), "TC-ROSTER.8.3", "Hauling cargo activity: '%s'" % hud_instance._roster_rows["act_haul"].act_lbl.text)
	_assert(hud_instance._roster_rows["act_food"].act_lbl.text.contains("thức ăn"), "TC-ROSTER.8.4", "Seeking food activity")
	_assert(hud_instance._roster_rows["act_rest"].act_lbl.text.contains("Nghỉ ngơi"), "TC-ROSTER.8.5", "Resting activity")
	_assert(hud_instance._roster_rows["act_guard"].act_lbl.text.contains("Canh gác") or hud_instance._roster_rows["act_guard"].act_lbl.text.contains("Tuần tra"), "TC-ROSTER.8.6", "Guarding activity")

	c_idle.queue_free()
	c_work.queue_free()
	c_haul.queue_free()
	c_food.queue_free()
	c_rest.queue_free()
	c_guard.queue_free()

func _run_tc_roster_9_reason_not_working_diagnostics() -> void:
	print("\n--- Running TC-ROSTER.9: Reason Not Working Diagnostics ---")
	var c_free = _create_dummy_citizen("diag_free", "Dan Tu Do", "idle")
	c_free.current_state = CitizenControllerScript.State.IDLE

	var c_strand = _create_dummy_citizen("diag_strand", "Mac Ket Hang", "hauler")
	c_strand.current_state = CitizenControllerScript.State.IDLE
	c_strand.carrying_amount = 5
	c_strand.carrying_resource = "wood"
	c_strand.is_stranded_with_cargo = true

	var c_full = _create_dummy_citizen("diag_full", "Kho Day", "hauler")
	c_full.current_state = CitizenControllerScript.State.IDLE
	c_full.carrying_amount = 5
	c_full.carrying_resource = "stone"
	c_full.is_waiting_at_dropoff = true

	var c_starve = _create_dummy_citizen("diag_starve", "Doi Nang", "farmer")
	c_starve.hunger = 92.0

	var c_exhaust = _create_dummy_citizen("diag_exhaust", "Kiet Suc", "miner")
	c_exhaust.fatigue = 96.0

	hud_instance.set_citizen_list_for_test([c_free, c_strand, c_full, c_starve, c_exhaust])
	hud_instance.refresh_citizen_roster()

	var r_free_text = hud_instance._roster_rows["diag_free"].reason_lbl.text
	var r_strand_text = hud_instance._roster_rows["diag_strand"].reason_lbl.text
	var r_full_text = hud_instance._roster_rows["diag_full"].reason_lbl.text
	var r_starve_text = hud_instance._roster_rows["diag_starve"].reason_lbl.text
	var r_exhaust_text = hud_instance._roster_rows["diag_exhaust"].reason_lbl.text

	_assert(r_free_text.contains("Chưa được phân công"), "TC-ROSTER.9.1", "Free idle reason: '%s'" % r_free_text)
	_assert(r_strand_text.contains("chưa tìm được đường về kho") or r_strand_text.contains("giữ hàng"), "TC-ROSTER.9.2", "Stranded reason: '%s'" % r_strand_text)
	_assert(r_full_text.contains("Kho đã đầy") or r_full_text.contains("chờ chỗ trống"), "TC-ROSTER.9.3", "Full storage reason: '%s'" % r_full_text)
	_assert(r_starve_text.contains("Đói khẩn cấp"), "TC-ROSTER.9.4", "Starvation reason: '%s'" % r_starve_text)
	_assert(r_exhaust_text.contains("Kiệt sức khẩn cấp"), "TC-ROSTER.9.5", "Exhaustion reason: '%s'" % r_exhaust_text)

	c_free.queue_free()
	c_strand.queue_free()
	c_full.queue_free()
	c_starve.queue_free()
	c_exhaust.queue_free()

func _run_tc_roster_10_manual_command_states() -> void:
	print("\n--- Running TC-ROSTER.10: Package 2K Manual Citizen Commands in Roster ---")
	var c_move = _create_dummy_citizen("man_move", "Di Chuyen", "farmer")
	c_move.manual_command = {"type": "move", "is_active": true, "target_cell": Vector2i(40, 40), "is_paused": false}

	var c_chop = _create_dummy_citizen("man_chop", "Chat Cay", "woodcutter")
	c_chop.manual_command = {"type": "chop", "is_active": true, "target_cell": Vector2i(35, 35), "is_paused": false}

	var c_mine = _create_dummy_citizen("man_mine", "Dao Da", "miner")
	c_mine.manual_command = {"type": "mine", "is_active": true, "target_cell": Vector2i(25, 25), "is_paused": false}

	var c_build = _create_dummy_citizen("man_build", "Xay Nha", "builder")
	c_build.manual_command = {"type": "build", "is_active": true, "target_cell": Vector2i(30, 30), "is_paused": false}

	var c_haul = _create_dummy_citizen("man_haul", "Van Chuyen", "hauler")
	c_haul.manual_command = {"type": "haul", "is_active": true, "target_cell": Vector2i(32, 32), "is_paused": false}

	var c_explore = _create_dummy_citizen("man_explore", "Kham Pha", "idle")
	c_explore.manual_command = {"type": "explore", "is_active": true, "target_cell": Vector2i(50, 50), "is_paused": false}

	var c_paused = _create_dummy_citizen("man_paused", "Tam Hoan", "farmer")
	c_paused.manual_command = {"type": "move", "is_active": true, "target_cell": Vector2i(45, 45), "is_paused": true}

	hud_instance.set_citizen_list_for_test([c_move, c_chop, c_mine, c_build, c_haul, c_explore, c_paused])
	hud_instance.refresh_citizen_roster()

	_assert(hud_instance._roster_rows["man_move"].act_lbl.text.contains("Di chuyển"), "TC-ROSTER.10.1", "Manual Move")
	_assert(hud_instance._roster_rows["man_chop"].act_lbl.text.contains("Chặt cây"), "TC-ROSTER.10.2", "Manual Chop")
	_assert(hud_instance._roster_rows["man_mine"].act_lbl.text.contains("Khai thác"), "TC-ROSTER.10.3", "Manual Mine")
	_assert(hud_instance._roster_rows["man_build"].act_lbl.text.contains("Xây dựng"), "TC-ROSTER.10.4", "Manual Build")
	_assert(hud_instance._roster_rows["man_haul"].act_lbl.text.contains("Vận chuyển"), "TC-ROSTER.10.5", "Manual Haul")
	_assert(hud_instance._roster_rows["man_explore"].act_lbl.text.contains("Khám phá"), "TC-ROSTER.10.6", "Manual Explore")
	_assert(hud_instance._roster_rows["man_paused"].act_lbl.text.contains("Tạm hoãn"), "TC-ROSTER.10.7", "Paused manual command")

	c_move.queue_free()
	c_chop.queue_free()
	c_mine.queue_free()
	c_build.queue_free()
	c_haul.queue_free()
	c_explore.queue_free()
	c_paused.queue_free()

func _run_tc_roster_11_guard_role_and_barracks_gating() -> void:
	print("\n--- Running TC-ROSTER.11: Guard Role & Barracks Gating Invariant ---")
	var cit := _create_dummy_citizen("guard_cit", "Linh Ve Binh", "farmer")

	# Case A: Barracks inactive -> Guard disabled and rejected
	hud_instance.set_barracks_checker(func(_b_id: String = ""): return false)
	hud_instance.set_citizen_list_for_test([cit])
	hud_instance.refresh_citizen_roster()

	var row = hud_instance._roster_rows.get("guard_cit")
	_assert(row != null, "TC-ROSTER.11.1", "Row exists for guard test citizen")
	if row != null:
		var assign_btn: OptionButton = row.assign_btn
		_assert(assign_btn.is_item_disabled(7), "TC-ROSTER.11.2", "Guard option (item 7) disabled when barracks inactive")
		_assert(assign_btn.get_item_text(7).contains("Cần Doanh Trại"), "TC-ROSTER.11.3", "Guard option shows prerequisite message: '%s'" % assign_btn.get_item_text(7))

	# Attempt to force assign guard role when barracks inactive
	hud_instance._on_roster_row_role_selected(cit, 7)
	_assert(cit.role != "guard", "TC-ROSTER.11.4", "Guard assignment rejected when barracks inactive, role remained '%s'" % cit.role)

	# Case B: Barracks active -> Guard enabled and accepted
	hud_instance.set_barracks_checker(func(_b_id: String = ""): return true)
	cit.set_barracks_checker(func(_b_id: String = ""): return true)
	hud_instance.refresh_citizen_roster()

	if row != null:
		var assign_btn: OptionButton = row.assign_btn
		_assert(not assign_btn.is_item_disabled(7), "TC-ROSTER.11.5", "Guard option enabled when barracks active")

	hud_instance._on_roster_row_role_selected(cit, 7)
	_assert(cit.role == "guard", "TC-ROSTER.11.6", "Guard role successfully assigned when barracks active")

	# Reset barracks checker
	hud_instance.set_barracks_checker(Callable())
	cit.queue_free()

func _run_tc_roster_12_assign_work_action_and_sync() -> void:
	print("\n--- Running TC-ROSTER.12: Assign Work Action & Immediate Roster Synchronization ---")
	var cit := _create_dummy_citizen("assign_cit", "Lao Dong", "farmer")
	hud_instance.set_citizen_list_for_test([cit])
	hud_instance.refresh_citizen_roster()

	var role_changed_emitted: Array = []
	var sig_callable = func(cid: String, n_role: String):
		role_changed_emitted.append({"cid": cid, "role": n_role})
	hud_instance.citizen_role_changed.connect(sig_callable)

	# Change from farmer (0) to miner (4)
	hud_instance._on_roster_row_role_selected(cit, 4)

	_assert(cit.role == "miner", "TC-ROSTER.12.1", "Citizen role changed to miner")
	_assert(role_changed_emitted.size() == 1 and role_changed_emitted[0]["role"] == "miner", "TC-ROSTER.12.2", "citizen_role_changed signal emitted")

	var row = hud_instance._roster_rows.get("assign_cit")
	_assert(row != null and row.role_lbl.text == "Thợ Mỏ", "TC-ROSTER.12.3", "Roster role label immediately reflects 'Thợ Mỏ': '%s'" % (row.role_lbl.text if row else "null"))
	_assert(row != null and row.assign_btn.selected == 4, "TC-ROSTER.12.4", "Assign dropdown selected index is 4")

	hud_instance.citizen_role_changed.disconnect(sig_callable)
	cit.queue_free()

func _run_tc_roster_13_citizen_death_removal() -> void:
	print("\n--- Running TC-ROSTER.13: Citizen Death Removal from Roster ---")
	var c1 = _create_dummy_citizen("live_cit", "Con Song", "farmer")
	var c2 = _create_dummy_citizen("dead_cit", "Tu Tran", "woodcutter")

	var cit_list = [c1, c2]
	hud_instance.set_citizen_list_for_test(cit_list)
	hud_instance.refresh_citizen_roster()

	_assert(hud_instance._roster_rows.size() == 2, "TC-ROSTER.13.1", "Both citizens in roster initially")

	# Citizen c2 dies: removed from active list and queued for free
	cit_list.erase(c2)
	c2.queue_free()

	hud_instance.refresh_citizen_roster()

	_assert(hud_instance._roster_rows.size() == 1, "TC-ROSTER.13.2", "Roster row count dropped to 1 after death")
	_assert(not hud_instance._roster_rows.has("dead_cit"), "TC-ROSTER.13.3", "Deceased citizen row eradicated from roster")
	_assert(hud_instance._roster_rows.has("live_cit"), "TC-ROSTER.13.4", "Living citizen remains in roster")

	c1.queue_free()

func _run_tc_roster_14_immigration_addition() -> void:
	print("\n--- Running TC-ROSTER.14: Immigration Wave Addition to Roster ---")
	var c1 = _create_dummy_citizen("c_base", "Dan Ban Dau", "farmer")
	var cit_list = [c1]
	hud_instance.set_citizen_list_for_test(cit_list)
	hud_instance.refresh_citizen_roster()

	_assert(hud_instance._roster_rows.size() == 1, "TC-ROSTER.14.1", "Initial 1 citizen in roster")

	# Immigrant arrives
	var c2 = _create_dummy_citizen("c_immigrant", "Dan Di Cu", "builder")
	cit_list.append(c2)

	hud_instance.refresh_citizen_roster()

	_assert(hud_instance._roster_rows.size() == 2, "TC-ROSTER.14.2", "Roster updated to 2 citizens")
	_assert(hud_instance._roster_rows.has("c_immigrant"), "TC-ROSTER.14.3", "Immigrant citizen present in roster")

	c1.queue_free()
	c2.queue_free()

func _run_tc_roster_15_repeated_refresh_idempotency() -> void:
	print("\n--- Running TC-ROSTER.15: Repeated Refresh Idempotency & Leak Prevention ---")
	var citizens: Array = []
	for i in range(10):
		citizens.append(_create_dummy_citizen("leak_cit_%d" % i, "Cit %d" % i, "farmer"))

	hud_instance.set_citizen_list_for_test(citizens)

	for cycle in range(10):
		hud_instance.refresh_citizen_roster()

	_assert(hud_instance._roster_rows.size() == 10, "TC-ROSTER.15.1", "Row dictionary size remains exactly 10 after 10 refreshes")
	_assert(hud_instance.roster_vbox.get_child_count() == 10, "TC-ROSTER.15.2", "Roster VBox child count remains exactly 10 without orphan duplicates")

	for c in citizens:
		c.queue_free()

func _run_tc_roster_16_save_load_restoration() -> void:
	print("\n--- Running TC-ROSTER.16: Save/Load Restoration Roundtrip ---")
	var cit := _create_dummy_citizen("save_cit_01", "Kiem Dinh Luu Tru", "miner", 88.0, 42.0, 33.0, 78.0)
	cit.award_work_xp("mining", 320.0) # Level 3, +16%

	var saved_dict: Dictionary = {
		"id": cit.citizen_id,
		"name": cit.citizen_name,
		"role": cit.role,
		"health": cit.health,
		"hunger": cit.hunger,
		"fatigue": cit.fatigue,
		"morale": cit.morale,
		"skills": cit.get_skill_data().serialize()
	}
	_assert(saved_dict.has("skills"), "TC-ROSTER.16.1", "Serialized citizen contains skills")

	# Restore into fresh citizen
	var restored_cit := CitizenControllerScript.new()
	restored_cit.init_citizen(saved_dict["id"], saved_dict["name"], saved_dict["role"], Vector2i(32, 32), null, null, null)
	restored_cit.health = saved_dict["health"]
	restored_cit.hunger = saved_dict["hunger"]
	restored_cit.fatigue = saved_dict["fatigue"]
	restored_cit.morale = saved_dict["morale"]
	restored_cit.get_skill_data().deserialize(saved_dict["skills"])

	hud_instance.set_citizen_list_for_test([restored_cit])
	hud_instance.refresh_citizen_roster()

	var row = hud_instance._roster_rows.get("save_cit_01")
	_assert(row != null, "TC-ROSTER.16.2", "Restored citizen reconstructed in roster")
	if row != null:
		_assert(row.role_lbl.text == "Thợ Mỏ", "TC-ROSTER.16.3", "Restored role is 'Thợ Mỏ'")
		_assert(row.hp_lbl.text == "88%", "TC-ROSTER.16.4", "Restored HP is 88%")
		_assert(row.hunger_lbl.text == "42%", "TC-ROSTER.16.5", "Restored hunger is 42%")
		_assert(row.fatigue_lbl.text == "33%", "TC-ROSTER.16.6", "Restored fatigue is 33%")
		_assert(row.morale_lbl.text == "78%", "TC-ROSTER.16.7", "Restored morale is 78%")
		_assert(row.skill_lbl.text.contains("Khai khoáng") and row.skill_lbl.text.contains("+16%"), "TC-ROSTER.16.8",
			"Restored skill shows Khai khoáng +16%%: '%s'" % row.skill_lbl.text)

	cit.queue_free()
	restored_cit.queue_free()

func _run_tc_roster_17_row_selection_inspection_sync() -> void:
	print("\n--- Running TC-ROSTER.17: Row Selection & Inspected Citizen Sync ---")
	var c_alpha = _create_dummy_citizen("cit_alpha", "Nguyen Alpha", "farmer")
	var c_beta = _create_dummy_citizen("cit_beta", "Tran Beta", "woodcutter")

	hud_instance.set_citizen_list_for_test([c_alpha, c_beta])
	hud_instance.refresh_citizen_roster()

	# Click on cit_alpha row
	hud_instance._on_roster_citizen_clicked(c_alpha)
	_assert(hud_instance.inspected_citizen == c_alpha, "TC-ROSTER.17.1", "Inspected citizen updated to c_alpha")
	_assert(hud_instance.citizen_panel.visible, "TC-ROSTER.17.2", "CitizenInspectPanel opened")
	_assert(hud_instance.citizen_name_label.text.contains("Nguyen Alpha"), "TC-ROSTER.17.3", "Inspector reflects Nguyen Alpha")

	# Click on cit_beta row
	hud_instance._on_roster_citizen_clicked(c_beta)
	_assert(hud_instance.inspected_citizen == c_beta, "TC-ROSTER.17.4", "Inspected citizen updated to c_beta")
	_assert(hud_instance.citizen_name_label.text.contains("Tran Beta"), "TC-ROSTER.17.5", "Inspector reflects Tran Beta")

	hud_instance.close_citizen_inspector()
	c_alpha.queue_free()
	c_beta.queue_free()

func _run_tc_roster_18_independent_inspector_coexistence() -> void:
	print("\n--- Running TC-ROSTER.18: Independent CitizenInspectPanel Coexistence ---")
	var cit := _create_dummy_citizen("coex_cit", "Dong Thoi", "farmer")
	hud_instance.set_citizen_list_for_test([cit])
	hud_instance.open_citizen_roster()

	hud_instance.show_citizen_inspector(cit)
	_assert(hud_instance.citizen_roster_panel.visible, "TC-ROSTER.18.1", "Citizen roster panel remains open when inspector opened")
	_assert(hud_instance.citizen_panel.visible, "TC-ROSTER.18.2", "Citizen inspector panel is open")

	# Change role in CitizenInspectPanel -> updates Roster
	hud_instance._on_role_option_selected(1) # woodcutter
	_assert(cit.role == "woodcutter", "TC-ROSTER.18.3", "Role changed to woodcutter via inspector")
	var row = hud_instance._roster_rows.get("coex_cit")
	_assert(row != null and row.role_lbl.text == "Tiều Phu", "TC-ROSTER.18.4", "Roster row reflects Tiều Phu immediately")

	# Close inspector only -> roster remains open
	hud_instance.close_citizen_inspector()
	_assert(not hud_instance.citizen_panel.visible, "TC-ROSTER.18.5", "Inspector closed")
	_assert(hud_instance.citizen_roster_panel.visible, "TC-ROSTER.18.6", "Roster remains open independently")

	cit.queue_free()

func _run_tc_roster_19_mouse_input_consumption() -> void:
	print("\n--- Running TC-ROSTER.19: Mouse Input Consumption (Stop Filter) ---")
	_assert(hud_instance.citizen_roster_panel.mouse_filter == Control.MOUSE_FILTER_STOP, "TC-ROSTER.19.1",
		"CitizenRosterPanel mouse_filter is MOUSE_FILTER_STOP (%d)" % hud_instance.citizen_roster_panel.mouse_filter)

	var margin = hud_instance.citizen_roster_panel.get_node_or_null("MarginContainer")
	_assert(margin != null and margin.mouse_filter == Control.MOUSE_FILTER_STOP, "TC-ROSTER.19.2",
		"MarginContainer mouse_filter is MOUSE_FILTER_STOP")

func _run_tc_roster_20_high_population_scale_50_plus() -> void:
	print("\n--- Running TC-ROSTER.20: High Population Scale (50+ Citizens) ---")
	var big_pop: Array = []
	for i in range(55):
		var r = "farmer" if i % 2 == 0 else "woodcutter"
		big_pop.append(_create_dummy_citizen("big_cit_%d" % i, "Dan So %d" % i, r))

	hud_instance.set_citizen_list_for_test(big_pop)
	hud_instance.refresh_citizen_roster()

	_assert(hud_instance._roster_rows.size() == 55, "TC-ROSTER.20.1", "55 citizen rows rendered successfully")
	_assert(hud_instance.roster_scroll != null, "TC-ROSTER.20.2", "ScrollContainer exists for large population")
	_assert(hud_instance.roster_scroll.custom_minimum_size.y >= 200.0, "TC-ROSTER.20.3", "ScrollContainer maintains minimum vertical size")
	_assert(hud_instance.roster_summary_label.text.contains("55/"), "TC-ROSTER.20.4", "Summary displays total 55: '%s'" % hud_instance.roster_summary_label.text)

	for c in big_pop:
		c.queue_free()

func _run_tc_roster_21_vocation_filter() -> void:
	print("\n--- Running TC-ROSTER.21: Vocation / Role Filter Options ---")
	var c_f1 = _create_dummy_citizen("flt_f1", "Nong 1", "farmer")
	var c_f2 = _create_dummy_citizen("flt_f2", "Nong 2", "farmer")
	var c_w1 = _create_dummy_citizen("flt_w1", "Tieu 1", "woodcutter")
	var c_b1 = _create_dummy_citizen("flt_b1", "Xay 1", "builder")

	hud_instance.set_citizen_list_for_test([c_f1, c_f2, c_w1, c_b1])
	hud_instance.refresh_citizen_roster()

	# All filter
	_assert(hud_instance._roster_rows.size() == 4, "TC-ROSTER.21.1", "All filter displays 4 citizens")

	# Farmer filter (index 2)
	hud_instance._on_roster_filter_selected(2)
	_assert(hud_instance._roster_rows.size() == 2, "TC-ROSTER.21.2", "Farmer filter displays 2 farmers")
	_assert(hud_instance._roster_rows.has("flt_f1") and hud_instance._roster_rows.has("flt_f2"), "TC-ROSTER.21.3", "Only farmers shown")

	# Reset filter to All (index 0)
	hud_instance._on_roster_filter_selected(0)
	_assert(hud_instance._roster_rows.size() == 4, "TC-ROSTER.21.4", "Filter reset to All displays 4 citizens")

	c_f1.queue_free()
	c_f2.queue_free()
	c_w1.queue_free()
	c_b1.queue_free()

func _run_tc_roster_22_toggle_and_pop_label_trigger() -> void:
	print("\n--- Running TC-ROSTER.22: Panel Toggling & PopLabel Click Trigger ---")
	hud_instance.close_citizen_roster()
	_assert(not hud_instance.citizen_roster_panel.visible, "TC-ROSTER.22.1", "Panel closed initially")

	hud_instance.toggle_citizen_roster()
	_assert(hud_instance.citizen_roster_panel.visible, "TC-ROSTER.22.2", "toggle_citizen_roster() opened panel")

	hud_instance.toggle_citizen_roster()
	_assert(not hud_instance.citizen_roster_panel.visible, "TC-ROSTER.22.3", "toggle_citizen_roster() closed panel")

	# Simulate PopLabel left-click
	var click_ev = InputEventMouseButton.new()
	click_ev.button_index = MOUSE_BUTTON_LEFT
	click_ev.pressed = true
	hud_instance._on_pop_label_gui_input(click_ev)
	_assert(hud_instance.citizen_roster_panel.visible, "TC-ROSTER.22.4", "PopLabel click opened roster panel")

	hud_instance.close_citizen_roster()

func _print_summary() -> void:
	print("\n========================================================")
	print("  CITIZEN ROSTER PANEL TEST SUMMARY (PACKAGE 2L)")
	print("  Passed: %d | Failed: %d" % [passed_count, failures])
	print("========================================================\n")

	hud_instance.queue_free()

	if failures == 0:
		print("🎉 ALL CITIZEN ROSTER TESTS PASSED!")
	else:
		printerr("❌ CITIZEN ROSTER TEST FAILURES DETECTED!")
