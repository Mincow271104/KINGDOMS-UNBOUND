extends SceneTree
## =============================================================================
## KINGDOMS UNBOUND — Package 2D Regression Test Suite
## In-Game Player Field Guide & 30-Day Starter Manual Verification
## =============================================================================

const PlayerFieldGuideScript = preload("res://scripts/ui/player_field_guide.gd")
const CitizenSkillDataScript = preload("res://scripts/entities/citizen_skill_data.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")

const TEST_RESOLUTIONS = [
	Vector2i(1280, 720),
	Vector2i(1024, 576)
]

var total_tests: int = 0
var passed_tests: int = 0
var failed_tests: int = 0

var world_inst: Node = null
var hud_inst: Node = null
var guide_inst: Control = null
var frame_counter: int = 0

func _init() -> void:
	print("\n========================================================")
	print("  TEST SUITE: Package 2D — Player Field Guide & Starter Manual")
	print("========================================================\n")

func _process(_delta: float) -> bool:
	frame_counter += 1
	if frame_counter == 1:
		_setup_test_world()
		return false
	elif frame_counter == 2:
		_run_all_tests()
		_print_summary()
		_cleanup()
		quit(0 if failed_tests == 0 else 1)
		return true
	return false

func _assert(cond: bool, code: String, desc: String) -> void:
	total_tests += 1
	if cond:
		passed_tests += 1
		print("  [PASS] %s: %s" % [code, desc])
	else:
		failed_tests += 1
		printerr("  ❌ [FAIL] %s: %s" % [code, desc])

func _setup_test_world() -> void:
	var world_scene = load("res://scenes/world/world_view.tscn")
	world_inst = world_scene.instantiate()
	world_inst.set("world_seed", 12345)
	root.add_child(world_inst)
	hud_inst = world_inst.get_node_or_null("HUD")
	if hud_inst:
		guide_inst = hud_inst.get_node_or_null("PlayerFieldGuide") as Control

func _run_all_tests() -> void:
	test_01_scene_and_node_integrity()
	test_02_guide_open_close_api_and_signals()
	test_03_all_six_chapters_accessible()
	test_04_authoritative_content_and_formulas()
	test_05_world_state_and_time_non_interference()
	test_06_input_isolation_and_mouse_blocking()
	test_07_keyboard_shortcuts()
	test_08_hud_and_pause_menu_integration()
	test_09_responsive_bounds_and_geometry()

# -----------------------------------------------------------------------------
# Test 1: Scene & Node Integrity
# -----------------------------------------------------------------------------
func test_01_scene_and_node_integrity() -> void:
	print("\n--- Test 1: Scene & Node Structure Integrity ---")
	_assert(guide_inst != null, "TC-2D.1.1", "PlayerFieldGuide node exists in HUD scene")
	_assert(guide_inst.get_script() == PlayerFieldGuideScript, "TC-2D.1.2", "PlayerFieldGuide is of correct script type")
	_assert(guide_inst.visible == false, "TC-2D.1.3", "PlayerFieldGuide is hidden by default on game load")

	var modal_bd = guide_inst.get_node_or_null("ModalBackdrop")
	_assert(modal_bd != null and modal_bd is ColorRect, "TC-2D.1.4", "ModalBackdrop ColorRect exists")
	if modal_bd:
		_assert(modal_bd.mouse_filter == Control.MOUSE_FILTER_STOP, "TC-2D.1.5", "ModalBackdrop stops mouse clicks from bleeding through")

	var panel = guide_inst.get_node_or_null("CenterContainer/GuidePanel")
	_assert(panel != null and panel is PanelContainer, "TC-2D.1.6", "GuidePanel PanelContainer exists")
	if panel:
		_assert(panel.mouse_filter == Control.MOUSE_FILTER_STOP, "TC-2D.1.7", "GuidePanel stops mouse clicks")

	var close_btn = guide_inst.close_btn
	_assert(close_btn != null and close_btn is Button, "TC-2D.1.8", "CloseBtn exists")

	var scroll = guide_inst.content_scroll
	_assert(scroll != null and scroll is ScrollContainer, "TC-2D.1.9", "ContentScroll ScrollContainer exists")

	var content_txt = guide_inst.content_text
	_assert(content_txt != null and content_txt is RichTextLabel, "TC-2D.1.10", "ContentText RichTextLabel exists")
	if content_txt:
		_assert(content_txt.bbcode_enabled, "TC-2D.1.11", "ContentText has bbcode_enabled = true")

# -----------------------------------------------------------------------------
# Test 2: Guide Open/Close API & Signals
# -----------------------------------------------------------------------------
func test_02_guide_open_close_api_and_signals() -> void:
	print("\n--- Test 2: Guide Open / Close API & Signals ---")
	var sig_state := {"opened": false, "closed": false}
	var cb_open := func(): sig_state["opened"] = true
	var cb_close := func(): sig_state["closed"] = true

	guide_inst.guide_opened.connect(cb_open)
	guide_inst.guide_closed.connect(cb_close)

	_assert(not guide_inst.is_guide_open(), "TC-2D.2.1", "Guide initially reported closed")

	guide_inst.open_guide()
	_assert(guide_inst.is_guide_open(), "TC-2D.2.2", "Guide open_guide() sets is_guide_open() == true")
	_assert(guide_inst.visible, "TC-2D.2.3", "Guide node is visible when opened")
	_assert(sig_state["opened"], "TC-2D.2.4", "guide_opened signal was emitted")

	guide_inst.close_guide()
	_assert(not guide_inst.is_guide_open(), "TC-2D.2.5", "Guide close_guide() sets is_guide_open() == false")
	_assert(not guide_inst.visible, "TC-2D.2.6", "Guide node is hidden when closed")
	_assert(sig_state["closed"], "TC-2D.2.7", "guide_closed signal was emitted")

	# Test toggle_guide
	guide_inst.toggle_guide()
	_assert(guide_inst.is_guide_open(), "TC-2D.2.8", "toggle_guide() opens when closed")
	guide_inst.toggle_guide()
	_assert(not guide_inst.is_guide_open(), "TC-2D.2.9", "toggle_guide() closes when open")

	guide_inst.guide_opened.disconnect(cb_open)
	guide_inst.guide_closed.disconnect(cb_close)

# -----------------------------------------------------------------------------
# Test 3: All 6 Chapters Accessible
# -----------------------------------------------------------------------------
func test_03_all_six_chapters_accessible() -> void:
	print("\n--- Test 3: Non-Linear Access to All 6 Chapters ---")
	_assert(PlayerFieldGuideScript.TOTAL_CHAPTERS == 6, "TC-2D.3.1", "Guide declares exactly 6 chapters")

	var sig_state := {"selected": -1}
	var cb_chap := func(idx: int): sig_state["selected"] = idx
	guide_inst.chapter_selected.connect(cb_chap)

	for i in range(PlayerFieldGuideScript.TOTAL_CHAPTERS):
		guide_inst.select_chapter(i)
		_assert(guide_inst.get_current_chapter() == i, "TC-2D.3.2_%d" % i, "Selected chapter %d correctly" % i)
		_assert(sig_state["selected"] == i, "TC-2D.3.3_%d" % i, "chapter_selected signal emitted with index %d" % i)
		_assert(guide_inst.get_chapter_title(i) != "", "TC-2D.3.4_%d" % i, "Chapter %d has non-empty title" % i)
		_assert(guide_inst.get_chapter_subtitle(i) != "", "TC-2D.3.5_%d" % i, "Chapter %d has non-empty subtitle" % i)
		_assert(guide_inst.get_chapter_content(i) != "", "TC-2D.3.6_%d" % i, "Chapter %d has non-empty content" % i)

	# Test Prev / Next button navigation
	guide_inst.select_chapter(0)
	_assert(guide_inst.prev_btn.disabled, "TC-2D.3.7", "PrevBtn is disabled on Chapter 0")
	_assert(not guide_inst.next_btn.disabled, "TC-2D.3.8", "NextBtn is enabled on Chapter 0")

	guide_inst._on_next_pressed()
	_assert(guide_inst.get_current_chapter() == 1, "TC-2D.3.9", "NextBtn advances to Chapter 1")

	guide_inst.select_chapter(5)
	_assert(guide_inst.next_btn.disabled, "TC-2D.3.10", "NextBtn is disabled on Chapter 5")
	_assert(not guide_inst.prev_btn.disabled, "TC-2D.3.11", "PrevBtn is enabled on Chapter 5")

	guide_inst._on_prev_pressed()
	_assert(guide_inst.get_current_chapter() == 4, "TC-2D.3.12", "PrevBtn retreats to Chapter 4")

	guide_inst.chapter_selected.disconnect(cb_chap)

# -----------------------------------------------------------------------------
# Test 4: Authoritative Content & Formulas
# -----------------------------------------------------------------------------
func test_04_authoritative_content_and_formulas() -> void:
	print("\n--- Test 4: Authoritative Gameplay Rules & Formula Accuracy ---")

	# Chapter A assertions
	var c_a = guide_inst.get_chapter_content(0)
	_assert("24 công dân" in c_a, "TC-2D.4.1", "Chapter A explains exactly 24 starting citizens")
	_assert("5 Nông dân" in c_a and "4 Tiều phu" in c_a and "3 Thợ xây" in c_a and "3 Người vận chuyển" in c_a and "9 Công dân nhàn rỗi" in c_a,
		"TC-2D.4.2", "Chapter A itemizes starting role breakdown (5, 4, 3, 3, 9)")
	_assert("8 công trình" in c_a, "TC-2D.4.3", "Chapter A explains exactly 8 starting buildings")
	_assert("150" in c_a and "120" in c_a and "60" in c_a and "200" in c_a, "TC-2D.4.4", "Chapter A includes starting resources (Food 150, Wood 120, Stone 60, Gold 200)")

	# Chapter B assertions
	var c_b = guide_inst.get_chapter_content(1)
	_assert("Nông nghiệp" in c_b and "Lâm nghiệp" in c_b and "Khai khoáng" in c_b and "Rèn & Chế tác" in c_b and "Xây dựng" in c_b and "Vận chuyển" in c_b,
		"TC-2D.4.5", "Chapter B documents all 6 vocations from Package 2B")
	_assert("1,00×" in c_b and "1,08×" in c_b and "1,16×" in c_b and "1,25×" in c_b and "1,35×" in c_b,
		"TC-2D.4.6", "Chapter B cites exact efficiency multipliers (1.00x, 1.08x, 1.16x, 1.25x, 1.35x)")
	_assert("100" in c_b and "300" in c_b and "600" in c_b and "1.000" in c_b,
		"TC-2D.4.7", "Chapter B cites exact XP thresholds (100, 300, 600, 1000)")
	_assert("Đói" in c_b and "Mệt mỏi" in c_b and "Sức khỏe" in c_b and "Tinh thần" in c_b,
		"TC-2D.4.8", "Chapter B covers citizen survival needs (Hunger, Fatigue, Health, Morale)")

	# Chapter C assertions
	var c_c = guide_inst.get_chapter_content(2)
	_assert("Kho đệm nội bộ" in c_c or "kho đệm" in c_c, "TC-2D.4.9", "Chapter C introduces workplace output buffer")
	_assert("CHƯA PHẢI" in c_c or "chưa có" in c_c, "TC-2D.4.10", "Chapter C emphasizes resources in buffer are not available in central stockpile")
	_assert("Hauler" in c_c or "Người vận chuyển" in c_c, "TC-2D.4.11", "Chapter C highlights critical hauling logistics")
	_assert("đầy tràn" in c_c or "Saturation" in c_c, "TC-2D.4.12", "Chapter C explains buffer saturation halting production")

	# Chapter D assertions
	var c_d = guide_inst.get_chapter_content(3)
	_assert("40 ngày" in c_d, "TC-2D.4.13", "Chapter D establishes 40-day year calendar")
	_assert("1,0×" in c_d and "1,2×" in c_d and "0,5×" in c_d, "TC-2D.4.14", "Chapter D provides seasonal multipliers (Spring 1.0x, Summer 1.2x, Autumn 1.0x, Winter 0.5x)")
	_assert("CHỈ ÁP DỤNG DUY NHẤT" in c_d or "CHỈ ÁP DỤNG" in c_d, "TC-2D.4.15", "Chapter D clarifies seasonal modifier applies strictly to farm food")
	_assert("Ngày 1 – 10" in c_d and "Ngày 11 – 20" in c_d and "Ngày 21 – 30" in c_d and "Ngày 31 – 40" in c_d,
		"TC-2D.4.16", "Chapter D covers all 4 stages of the 40-day starter roadmap")

	# Chapter E assertions
	var c_e = guide_inst.get_chapter_content(4)
	_assert("EventManager" in c_e or "Sự kiện" in c_e, "TC-2D.4.17", "Chapter E details world events and crisis alerts")
	_assert("Ngoại Giao" in c_e and "NAP" in c_e, "TC-2D.4.18", "Chapter E covers faction diplomacy, treaties, and NAP")
	_assert("Caravan" in c_e and "Chợ" in c_e, "TC-2D.4.19", "Chapter E covers trade caravans and market infrastructure")
	_assert("Doanh trại" in c_e and "Upkeep" in c_e, "TC-2D.4.20", "Chapter E covers barracks recruitment and military upkeep")

	# Chapter F assertions
	var c_f = guide_inst.get_chapter_content(5)
	_assert("phồn vinh" in c_f.to_lower() or "prosperity" in c_f.to_lower(), "TC-2D.4.21", "Chapter F documents Prosperity Victory condition")
	_assert("+100 Điểm Di Sản" in c_f, "TC-2D.4.22", "Chapter F documents base victory +100 LP award")
	_assert("1.000 Vàng" in c_f, "TC-2D.4.23", "Chapter F documents 1,000 Gold protected reserve")
	_assert("100 Vàng thặng dư = 1 Điểm Di Sản" in c_f, "TC-2D.4.24", "Chapter F documents 100:1 conversion rate")
	_assert("80%" in c_f, "TC-2D.4.25", "Chapter F specifies >=80% stability prerequisite")
	_assert("sụp đổ" in c_f and "0 Điểm Di Sản" in c_f, "TC-2D.4.26", "Chapter F clarifies collapsed kingdom is ineligible for treasury conversion")
	_assert("một lần duy nhất" in c_f or "Exactly-Once" in c_f, "TC-2D.4.27", "Chapter F notes exactly-once per World ID idempotency")

# -----------------------------------------------------------------------------
# Test 5: World State & Time Non-Interference
# -----------------------------------------------------------------------------
func test_05_world_state_and_time_non_interference() -> void:
	print("\n--- Test 5: Non-Interference with World State & Simulation Clock ---")
	var tm = root.get_node_or_null("TimeManager")
	var rm = root.get_node_or_null("ResourceManager")

	_assert(tm != null, "TC-2D.5.1", "TimeManager active in tree")
	_assert(rm != null, "TC-2D.5.2", "ResourceManager active in tree")

	# Capture baseline
	var orig_speed: int = tm.current_speed if tm else 1
	var orig_hour: int = tm.current_hour if tm else 6
	var orig_day: int = tm.current_day if tm else 1
	var orig_year: int = tm.current_year if tm else 1
	var orig_food: int = rm.get_total_stock("food") if rm else 150
	var orig_gold: int = rm.get_total_stock("gold") if rm else 200
	var orig_wood: int = rm.get_total_stock("wood") if rm else 120
	var orig_cit_count: int = world_inst.get("citizen_list").size() if world_inst.get("citizen_list") else 24

	# Open guide and cycle through all chapters
	guide_inst.open_guide()
	for i in range(PlayerFieldGuideScript.TOTAL_CHAPTERS):
		guide_inst.select_chapter(i)
	guide_inst.close_guide()

	# Assert zero mutation
	_assert(tm.current_speed == orig_speed, "TC-2D.5.3", "TimeManager speed unchanged after guide cycle")
	_assert(tm.current_hour == orig_hour, "TC-2D.5.4", "TimeManager hour unchanged")
	_assert(tm.current_day == orig_day, "TC-2D.5.5", "TimeManager day unchanged")
	_assert(tm.current_year == orig_year, "TC-2D.5.6", "TimeManager year unchanged")
	_assert(rm.get_total_stock("food") == orig_food, "TC-2D.5.7", "Food stock unchanged")
	_assert(rm.get_total_stock("gold") == orig_gold, "TC-2D.5.8", "Gold stock unchanged")
	_assert(rm.get_total_stock("wood") == orig_wood, "TC-2D.5.9", "Wood stock unchanged")
	_assert(world_inst.get("citizen_list").size() == orig_cit_count, "TC-2D.5.10", "Citizen population unchanged")

# -----------------------------------------------------------------------------
# Test 6: Input Isolation & Mouse Blocking
# -----------------------------------------------------------------------------
func test_06_input_isolation_and_mouse_blocking() -> void:
	print("\n--- Test 6: Input Isolation & Mouse Blocking ---")
	_assert(guide_inst.mouse_filter == Control.MOUSE_FILTER_STOP, "TC-2D.6.1", "PlayerFieldGuide root stops mouse events")
	_assert(guide_inst.modal_backdrop.mouse_filter == Control.MOUSE_FILTER_STOP, "TC-2D.6.2", "ModalBackdrop stops mouse events")
	_assert(guide_inst.guide_panel.mouse_filter == Control.MOUSE_FILTER_STOP, "TC-2D.6.3", "GuidePanel stops mouse events")

# -----------------------------------------------------------------------------
# Test 7: Keyboard Shortcuts
# -----------------------------------------------------------------------------
func test_07_keyboard_shortcuts() -> void:
	print("\n--- Test 7: Keyboard Shortcuts & Strict Input Isolation ---")
	var tm = root.get_node_or_null("TimeManager")
	_assert(not guide_inst.is_guide_open(), "TC-2D.7.1", "Guide starts closed")

	# Simulate pressing H in HUD
	var ev_h := InputEventKey.new()
	ev_h.keycode = KEY_H
	ev_h.pressed = true
	hud_inst._unhandled_input(ev_h)
	_assert(guide_inst.is_guide_open(), "TC-2D.7.2", "Pressing [H] opens guide")

	# Verify keyboard isolation while guide is open
	# Pressing B must NOT open Build menu
	var ev_b := InputEventKey.new()
	ev_b.keycode = KEY_B
	ev_b.pressed = true
	hud_inst._unhandled_input(ev_b)
	_assert(hud_inst.build_menu_panel.visible == false, "TC-2D.7.3", "Pressing [B] while guide open does NOT open build menu")

	# Pressing Space must NOT toggle pause
	var orig_speed: int = tm.current_speed if tm else 1
	var ev_sp := InputEventKey.new()
	ev_sp.keycode = KEY_SPACE
	ev_sp.pressed = true
	hud_inst._unhandled_input(ev_sp)
	_assert(tm.current_speed == orig_speed, "TC-2D.7.4", "Pressing [Space] while guide open does NOT alter pause state")

	# Pressing 2 or 3 must NOT change speed
	var ev_3 := InputEventKey.new()
	ev_3.keycode = KEY_3
	ev_3.pressed = true
	hud_inst._unhandled_input(ev_3)
	_assert(tm.current_speed == orig_speed, "TC-2D.7.5", "Pressing [3] while guide open does NOT alter speed")

	# Pressing T (Research) or Y (Diplomacy) must NOT open menus
	var ev_t := InputEventKey.new()
	ev_t.keycode = KEY_T
	ev_t.pressed = true
	hud_inst._unhandled_input(ev_t)
	_assert(hud_inst.research_menu_panel.visible == false, "TC-2D.7.6", "Pressing [T] while guide open does NOT open research menu")

	# Simulate pressing Esc while open from HUD
	var ev_esc := InputEventKey.new()
	ev_esc.keycode = KEY_ESCAPE
	ev_esc.pressed = true
	hud_inst._unhandled_input(ev_esc)
	_assert(not guide_inst.is_guide_open(), "TC-2D.7.7", "Pressing [Esc] closes guide")
	_assert(hud_inst.pause_menu_dialog.visible == false, "TC-2D.7.8", "Closing guide via [Esc] does NOT open Pause Menu")

	# Simulate pressing F1 to open, then H to toggle closed
	var ev_f1 := InputEventKey.new()
	ev_f1.keycode = KEY_F1
	ev_f1.pressed = true
	hud_inst._unhandled_input(ev_f1)
	_assert(guide_inst.is_guide_open(), "TC-2D.7.9", "Pressing [F1] opens guide")

	hud_inst._unhandled_input(ev_h)
	_assert(not guide_inst.is_guide_open(), "TC-2D.7.10", "Pressing [H] toggles guide closed")

	# Test Escape hierarchy when opened from Pause Menu:
	# 1. Open Pause Menu
	hud_inst._toggle_pause_menu()
	_assert(hud_inst.pause_menu_dialog.visible == true, "TC-2D.7.11", "Pause Menu opened")

	# 2. Open Guide from Pause Menu
	hud_inst._on_pause_guide_pressed()
	_assert(guide_inst.is_guide_open(), "TC-2D.7.12", "Guide opened from Pause Menu")
	_assert(hud_inst.pause_menu_dialog.visible == true, "TC-2D.7.13", "Pause Menu preserved underneath guide")

	# 3. Press Escape: must close Guide only, NOT close Pause Menu
	hud_inst._unhandled_input(ev_esc)
	_assert(not guide_inst.is_guide_open(), "TC-2D.7.14", "First [Esc] closes guide")
	_assert(hud_inst.pause_menu_dialog.visible == true, "TC-2D.7.15", "Pause Menu remains open after guide closed")

	# 4. Press Escape a second time: now closes Pause Menu
	hud_inst._unhandled_input(ev_esc)
	_assert(hud_inst.pause_menu_dialog.visible == false, "TC-2D.7.16", "Second [Esc] resumes game and closes Pause Menu")

# -----------------------------------------------------------------------------
# Test 8: HUD & Pause Menu Integration
# -----------------------------------------------------------------------------
func test_08_hud_and_pause_menu_integration() -> void:
	print("\n--- Test 8: HUD & Pause Menu Integration ---")
	var hud_btn: Button = hud_inst.open_guide_btn
	_assert(hud_btn != null, "TC-2D.8.1", "HUD GuideHudBtn exists on HUD")
	if hud_btn:
		_assert(hud_btn.visible, "TC-2D.8.2", "GuideHudBtn is visible during gameplay")
		_assert("Cẩm Nang" in hud_btn.text, "TC-2D.8.3", "GuideHudBtn displays Vietnamese label 'Cẩm Nang'")

	var pause_btn: Button = hud_inst.pause_guide_btn
	_assert(pause_btn != null, "TC-2D.8.4", "PauseMenu GuideBtn exists inside PauseMenuOverlay")
	if pause_btn:
		_assert("Cẩm Nang" in pause_btn.text, "TC-2D.8.5", "PauseMenu GuideBtn displays 'Cẩm Nang'")

	# Test clicking HUD guide button
	guide_inst.close_guide()
	hud_inst._toggle_field_guide()
	_assert(guide_inst.is_guide_open(), "TC-2D.8.6", "Clicking HUD guide button opens guide")

	# Test clicking PauseMenu guide button
	guide_inst.close_guide()
	hud_inst._on_pause_guide_pressed()
	_assert(guide_inst.is_guide_open(), "TC-2D.8.7", "Clicking Pause menu guide button opens guide")
	guide_inst.close_guide()

# -----------------------------------------------------------------------------
# Test 9: Responsive Bounds & Geometry at 1280x720 and 1024x576
# -----------------------------------------------------------------------------
func test_09_responsive_bounds_and_geometry() -> void:
	print("\n--- Test 9: Responsive Bounds & Layout Enclosure ---")
	var guide_panel: PanelContainer = guide_inst.guide_panel
	_assert(guide_panel != null, "TC-2D.9.1", "GuidePanel exists for geometry checks")
	if not guide_panel:
		return

	for res in TEST_RESOLUTIONS:
		var vp_rect := Rect2(Vector2.ZERO, Vector2(res))
		var min_size := guide_panel.get_combined_minimum_size()

		_assert(min_size.x <= float(res.x), "TC-2D.9.2_%dx%d" % [res.x, res.y],
			"GuidePanel min width (%.1f px) <= viewport width (%d px)" % [min_size.x, res.x])
		_assert(min_size.y <= float(res.y), "TC-2D.9.3_%dx%d" % [res.x, res.y],
			"GuidePanel min height (%.1f px) <= viewport height (%d px)" % [min_size.y, res.y])

		var clearance_x = float(res.x) - min_size.x
		var clearance_y = float(res.y) - min_size.y
		_assert(clearance_x >= 40.0, "TC-2D.9.4_%dx%d" % [res.x, res.y],
			"GuidePanel has positive horizontal margin >= 40px (found: %.1f px)" % clearance_x)
		_assert(clearance_y >= 30.0, "TC-2D.9.5_%dx%d" % [res.x, res.y],
			"GuidePanel has positive vertical margin >= 30px (found: %.1f px)" % clearance_y)

	var scroll = guide_inst.content_scroll
	_assert(scroll.size_flags_vertical == Control.SIZE_EXPAND_FILL, "TC-2D.9.6", "ContentScroll expands to fill available height")

# -----------------------------------------------------------------------------
# Summary & Cleanup
# -----------------------------------------------------------------------------
func _print_summary() -> void:
	print("\n--------------------------------------------------------")
	print("  PACKAGE 2D RESULTS: %d/%d TESTS PASSED" % [passed_tests, total_tests])
	print("--------------------------------------------------------\n")
	if failed_tests == 0:
		print("  ALL PACKAGE 2D FIELD GUIDE REQUIREMENTS VERIFIED! (Exit Code 0)\n")
	else:
		printerr("  SOME TESTS FAILED! (Exit Code 1)\n")

func _cleanup() -> void:
	if is_instance_valid(world_inst):
		root.remove_child(world_inst)
		world_inst.free()
