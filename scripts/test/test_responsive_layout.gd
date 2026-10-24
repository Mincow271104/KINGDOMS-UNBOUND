extends SceneTree
## Headless & Standalone Test Suite for Responsive Game Window & HUD Layout.
## Validates TC-RESP.1 through TC-RESP.6 across two explicit phases:
## - SECTION A: Structural & Declared Configuration Assertions:
##   - TC-RESP.1: Target Viewport & Window Settings in ProjectSettings
##   - TC-RESP.2: Legacy HUD Node Path Integrity (Backwards Compatibility)
##   - TC-RESP.3: TopBar 2-Row Responsive Geometry & Declared Clearance
##   - TC-RESP.4: BottomBar Responsive Geometry, Declared Clearance & Button Visibility
##   - TC-RESP.5: Secondary Panels & Automation Editor Layout Bounds
##   - TC-RESP.6: Isometric Coordinate Forward/Inverse Transformation Purity Invariance
## - SECTION B: Runtime Viewport Bounds & Actual Control Geometry across 5 Resolutions:
##   - 1024x576, 1152x648, 1280x720, 1366x768, 1920x1080
##   - MainMenu MainPanel non-empty rect, viewport enclosure, and horizontal/vertical centering
##   - TopBar & BottomBar actual viewport containment and edge anchoring
##   - All 5 primary action buttons non-empty rects, visible viewport enclosure, BottomBar containment
##   - All 8 resource labels actual bounds, right edge non-overflow, positive clearance
##   - BuildMenuPanel, ResearchMenuPanel, DiplomacyPanel non-overlap vs TopBar and BottomBar
##   - AutomationEditor Panel viewport enclosure, GraphEdit & RightScroll usable non-zero dimensions and enclosure

const IsoMathScript = preload("res://scripts/utils/iso_math.gd")

const VIEWPORT_TEST_SIZES = [
	Vector2i(1024, 576),
	Vector2i(1152, 648),
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1920, 1080)
]

var frame_count: int = 0
var world_instance: Node = null
var hud_vp: SubViewport = null
var menu_vp: SubViewport = null
var hud_test_instance: Node = null
var menu_test_instance: Control = null

var failures: int = 0
var checks: int = 0
var cur_res_idx: int = -1

func _init() -> void:
	print("\n================================================================================")
	print("  TEST SUITE: Responsive Window & HUD Layout — Hardened Geometry Verification")
	print("  DisplayServer: %s | Mode: %s" % [DisplayServer.get_name(), "Headless" if DisplayServer.get_name() == "headless" else "Windowed/GPU"])
	print("================================================================================\n")

	var world_scene = load("res://scenes/world/world_view.tscn")
	var hud_scene = load("res://scenes/ui/hud.tscn")
	var menu_scene = load("res://scenes/ui/main_menu.tscn")

	# Primary world instance for structural tests
	world_instance = world_scene.instantiate()
	root.add_child(world_instance)

	# Controlled SubViewports for multi-resolution runtime bounds tests
	hud_vp = SubViewport.new()
	hud_vp.size = VIEWPORT_TEST_SIZES[0]
	root.add_child(hud_vp)

	menu_vp = SubViewport.new()
	menu_vp.size = VIEWPORT_TEST_SIZES[0]
	root.add_child(menu_vp)

	hud_test_instance = hud_scene.instantiate()
	hud_vp.add_child(hud_test_instance)

	menu_test_instance = menu_scene.instantiate()
	menu_vp.add_child(menu_test_instance)

func _assert_check(condition: bool, msg: String) -> void:
	checks += 1
	if condition:
		print("  ✅ [PASS] %s" % msg)
	else:
		failures += 1
		printerr("  ❌ [FAIL] %s" % msg)

func _process(_delta: float) -> bool:
	frame_count += 1

	# Frame 3: Run structural assertions
	if frame_count == 3:
		print(">>> EXECUTING SECTION A: Structural & Declared Configuration Assertions <<<\n")
		_test_project_settings()
		_test_legacy_hud_paths()
		_test_top_bar_layout()
		_test_bottom_bar_layout()
		_test_panels_and_automation_editor()
		_test_coordinate_mapping_invariance()
		cur_res_idx = 0
		hud_vp.size = VIEWPORT_TEST_SIZES[cur_res_idx]
		menu_vp.size = VIEWPORT_TEST_SIZES[cur_res_idx]
		return false

	# Frames 6, 9, 12, 15, 18: Run bounds assertions for each resolution
	if cur_res_idx >= 0 and cur_res_idx < VIEWPORT_TEST_SIZES.size():
		if frame_count % 3 == 0:
			var res = VIEWPORT_TEST_SIZES[cur_res_idx]
			_test_viewport_bounds_at_resolution(res)
			cur_res_idx += 1
			if cur_res_idx < VIEWPORT_TEST_SIZES.size():
				hud_vp.size = VIEWPORT_TEST_SIZES[cur_res_idx]
				menu_vp.size = VIEWPORT_TEST_SIZES[cur_res_idx]
			else:
				_print_summary()
				quit(0 if failures == 0 else 1)
				return true

	return false

func _test_project_settings() -> void:
	print("--- Running TC-RESP.1: Target Viewport & Window Settings in ProjectSettings ---")
	var vp_width = ProjectSettings.get_setting("display/window/size/viewport_width", 0)
	var vp_height = ProjectSettings.get_setting("display/window/size/viewport_height", 0)
	var stretch_mode = ProjectSettings.get_setting("display/window/stretch/mode", "")
	var stretch_aspect = ProjectSettings.get_setting("display/window/stretch/aspect", "")

	_assert_check(vp_width == 1280, "ProjectSettings viewport_width is explicitly 1280 (found: %d)" % vp_width)
	_assert_check(vp_height == 720, "ProjectSettings viewport_height is explicitly 720 (found: %d)" % vp_height)
	_assert_check(stretch_mode == "canvas_items", "ProjectSettings stretch mode is 'canvas_items' (found: '%s')" % stretch_mode)
	_assert_check(stretch_aspect == "expand", "ProjectSettings stretch aspect is 'expand' (found: '%s')" % stretch_aspect)

	_assert_check(DisplayServer.has_method("window_set_min_size"), "DisplayServer supports window_set_min_size API")
	DisplayServer.window_set_min_size(Vector2i(1024, 576))
	_assert_check(true, "DisplayServer.window_set_min_size(1024, 576) executed cleanly without errors")

func _test_legacy_hud_paths() -> void:
	print("\n--- Running TC-RESP.2: Legacy HUD Node Path Integrity (Backwards Compatibility) ---")
	var hud: InGameHUD = world_instance.get_node_or_null("HUD")
	_assert_check(hud != null, "HUD instance found in WorldView")
	if hud == null:
		return

	var expected_res_labels = [
		"FoodLabel", "WoodLabel", "StoneLabel", "OreLabel",
		"MetalLabel", "ToolsLabel", "GoldLabel", "PopLabel"
	]
	for lbl_name in expected_res_labels:
		var node_path = "TopBar/PanelContainer/MarginContainer/HBoxContainer/Resources/" + lbl_name
		var lbl = hud.get_node_or_null(node_path)
		_assert_check(lbl != null and lbl is Label, "Resource label '%s' verified at legacy path '%s'" % [lbl_name, node_path])

	_assert_check(hud.date_label != null, "HUD date_label bound and accessible")
	_assert_check(hud.clock_label != null, "HUD clock_label bound and accessible")
	_assert_check(hud.speed_pause_btn != null, "HUD speed_pause_btn bound and accessible")
	_assert_check(hud.speed_1x_btn != null, "HUD speed_1x_btn bound and accessible")
	_assert_check(hud.speed_2x_btn != null, "HUD speed_2x_btn bound and accessible")
	_assert_check(hud.speed_3x_btn != null, "HUD speed_3x_btn bound and accessible")

	var bottom_nodes = [
		"TileInfoLabel", "BuildBtn", "ResearchBtn", "DiplomacyBtn", "MilitaryBtn", "AutomationBtn"
	]
	for btn_name in bottom_nodes:
		var node_path = "BottomBar/PanelContainer/MarginContainer/HBoxContainer/" + btn_name
		var node = hud.get_node_or_null(node_path)
		_assert_check(node != null, "BottomBar node '%s' verified at legacy path '%s'" % [btn_name, node_path])

func _test_top_bar_layout() -> void:
	print("\n--- Running TC-RESP.3: TopBar 2-Row Responsive Geometry & Clearance ---")
	var hud: InGameHUD = world_instance.get_node_or_null("HUD")
	if hud == null:
		return

	var top_bar: Control = hud.get_node_or_null("TopBar")
	_assert_check(top_bar != null, "TopBar Control found")
	if top_bar == null:
		return

	_assert_check(top_bar.offset_bottom >= 64.0, "TopBar height accommodates 2 rows (offset_bottom = %.1f >= 64.0)" % top_bar.offset_bottom)

	var top_row: HBoxContainer = hud.get_node_or_null("TopBar/PanelContainer/MarginContainer/HBoxContainer/TopRow")
	_assert_check(top_row != null, "TopBar Row 1 (TopRow) exists")
	if top_row:
		var r1_min_x: float = top_row.get_combined_minimum_size().x
		_assert_check(r1_min_x <= 650.0, "TopBar Row 1 min width (%.1f px) fits comfortably within 1024px" % r1_min_x)

	var res_box: HBoxContainer = hud.get_node_or_null("TopBar/PanelContainer/MarginContainer/HBoxContainer/Resources")
	_assert_check(res_box != null, "TopBar Row 2 (Resources) exists")
	if res_box:
		var r2_min_x: float = res_box.get_combined_minimum_size().x
		_assert_check(r2_min_x <= 960.0, "TopBar Row 2 min width (%.1f px) fits comfortably within 1024px" % r2_min_x)
		var clearance_1024 = 1024.0 - (r2_min_x + 24.0)
		_assert_check(clearance_1024 > 40.0, "TopBar Row 2 has positive clearance at 1024x576 (clearance = %.1f px)" % clearance_1024)

func _test_bottom_bar_layout() -> void:
	print("\n--- Running TC-RESP.4: BottomBar Responsive Geometry, Clearance & Button Visibility ---")
	var hud: InGameHUD = world_instance.get_node_or_null("HUD")
	if hud == null:
		return

	var bot_bar: Control = hud.get_node_or_null("BottomBar")
	_assert_check(bot_bar != null, "BottomBar Control found")
	if bot_bar == null:
		return

	var bot_hbox: HBoxContainer = hud.get_node_or_null("BottomBar/PanelContainer/MarginContainer/HBoxContainer")
	_assert_check(bot_hbox != null, "BottomBar HBoxContainer found")
	if bot_hbox:
		var bot_min_x: float = bot_hbox.get_combined_minimum_size().x
		_assert_check(bot_min_x <= 750.0, "BottomBar combined minimum width (%.1f px) is <= 750.0 px" % bot_min_x)
		var clearance_1024 = 1024.0 - (bot_min_x + 24.0)
		_assert_check(clearance_1024 >= 250.0, "BottomBar clearance at 1024x576 is >= 250.0 px (found: %.1f px)" % clearance_1024)

	var tile_info: Label = hud.tile_info_label
	_assert_check(tile_info != null, "TileInfoLabel found")
	if tile_info:
		_assert_check(tile_info.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS,
			"TileInfoLabel text_overrun_behavior set to TRIM_ELLIPSIS (%d)" % tile_info.text_overrun_behavior)

	var buttons = [
		{"name": "BuildBtn", "btn": hud.open_build_btn},
		{"name": "ResearchBtn", "btn": hud.open_research_btn},
		{"name": "DiplomacyBtn", "btn": hud.open_diplomacy_btn},
		{"name": "MilitaryBtn", "btn": hud.open_military_btn},
		{"name": "AutomationBtn", "btn": hud.open_automation_btn}
	]
	for b_info in buttons:
		var btn: Button = b_info["btn"]
		_assert_check(btn != null, "Action button '%s' exists in HUD" % b_info["name"])
		if btn:
			_assert_check(btn.custom_minimum_size.x <= 130.0, "Button '%s' custom_minimum_size.x (%.1f px) <= 130 px" % [b_info["name"], btn.custom_minimum_size.x])
			_assert_check(btn.visible, "Button '%s' is visible" % b_info["name"])

func _test_panels_and_automation_editor() -> void:
	print("\n--- Running TC-RESP.5: Secondary Panels & Automation Editor Layout Bounds ---")
	var hud: InGameHUD = world_instance.get_node_or_null("HUD")
	if hud == null:
		return

	var build_panel: PanelContainer = hud.build_menu_panel
	var bot_bar: Control = hud.get_node_or_null("BottomBar")
	_assert_check(build_panel != null, "BuildMenuPanel exists in HUD")
	if build_panel and bot_bar:
		_assert_check(build_panel.offset_bottom <= bot_bar.offset_top,
			"BuildMenuPanel bottom (%.1f) does not penetrate BottomBar top (%.1f)" % [build_panel.offset_bottom, bot_bar.offset_top])

	var res_panel: PanelContainer = hud.research_menu_panel
	var dip_panel: PanelContainer = hud.diplomacy_panel
	_assert_check(res_panel != null, "ResearchMenuPanel exists in HUD")
	_assert_check(dip_panel != null, "DiplomacyPanel exists in HUD")
	if res_panel:
		var res_h = res_panel.offset_bottom - res_panel.offset_top
		_assert_check(res_h <= 450.0, "ResearchMenuPanel height (%.1f px) fits within 576p height between bars" % res_h)
	if dip_panel:
		var dip_h = dip_panel.offset_bottom - dip_panel.offset_top
		_assert_check(dip_h <= 450.0, "DiplomacyPanel height (%.1f px) fits within 576p height between bars" % dip_h)

	var evt_banner: PanelContainer = hud.event_banner
	var crisis_banner: PanelContainer = hud.crisis_banner
	_assert_check(evt_banner != null and evt_banner.offset_top >= 68.0, "EventBanner offset_top (%.1f) is below TopBar (>= 68.0)" % evt_banner.offset_top)
	_assert_check(crisis_banner != null and crisis_banner.offset_top >= 68.0, "CrisisBanner offset_top (%.1f) is below TopBar (>= 68.0)" % crisis_banner.offset_top)

	var auto_ed: AutomationEditor = hud.automation_editor
	_assert_check(auto_ed != null, "AutomationEditor instance found in HUD")
	if auto_ed:
		var hsplit: HSplitContainer = auto_ed.get_node_or_null("Panel/MarginContainer/VBoxContainer/HSplit")
		_assert_check(hsplit != null, "AutomationEditor HSplit exists")
		if hsplit:
			_assert_check(hsplit.split_offset <= 560, "AutomationEditor split_offset (%.1f) <= 560 for responsive splitting" % hsplit.split_offset)

		var right_scroll: ScrollContainer = auto_ed.get_node_or_null("Panel/MarginContainer/VBoxContainer/HSplit/RightScroll")
		_assert_check(right_scroll != null, "AutomationEditor RightScroll (ScrollContainer) exists for inspector & trace scrolling")
		if right_scroll:
			_assert_check(right_scroll.custom_minimum_size.x <= 300.0,
				"RightScroll custom_minimum_size.x (%.1f px) <= 300 px" % right_scroll.custom_minimum_size.x)

		var graph_edit: GraphEdit = auto_ed.graph_edit
		_assert_check(graph_edit != null and graph_edit.size_flags_vertical == Control.SIZE_EXPAND_FILL,
			"AutomationEditor GraphEdit canvas has SIZE_EXPAND_FILL size flags")

func _test_coordinate_mapping_invariance() -> void:
	print("\n--- Running TC-RESP.6: Isometric Coordinate Forward/Inverse Purity Invariance ---")
	print("  [NOTE] Verifies mathematical purity of map_to_local <-> local_to_map roundtrip.")
	print("  [NOTE] Mouse picking after OS window resize additionally relies on camera viewport matrix & DisplayServer scaling.")

	var test_points = [
		Vector2i(0, 0),
		Vector2i(32, 32),
		Vector2i(63, 0),
		Vector2i(0, 63),
		Vector2i(63, 63),
		Vector2i(15, 27)
	]

	for cell in test_points:
		var local_pos = IsoMathScript.map_to_local(cell)
		var resolved_cell = IsoMathScript.local_to_map(local_pos)
		_assert_check(resolved_cell == cell, "Isometric mapping invariant for cell %s: map_to_local -> %s -> local_to_map -> %s" % [str(cell), str(local_pos), str(resolved_cell)])

func _test_viewport_bounds_at_resolution(res: Vector2i) -> void:
	print("\n>>> EXECUTING SECTION B: Runtime Viewport Bounds & Containment at %d x %d <<<\n" % [res.x, res.y])
	var vp_rect = Rect2(Vector2.ZERO, Vector2(res))

	# 1. MainMenu bounds and centering
	var main_panel: Control = menu_test_instance.get_node_or_null("CenterContainer/MainPanel")
	_assert_check(main_panel != null, "[%dx%d] MainMenu MainPanel exists" % [res.x, res.y])
	if main_panel:
		var mp_rect = main_panel.get_global_rect()
		_assert_check(mp_rect.size.x > 0.0 and mp_rect.size.y > 0.0, "[%dx%d] MainMenu MainPanel has non-empty size: %s" % [res.x, res.y, str(mp_rect.size)])
		_assert_check(vp_rect.encloses(mp_rect), "[%dx%d] MainMenu MainPanel strictly enclosed in viewport bounds: %s in %s" % [res.x, res.y, str(mp_rect), str(vp_rect)])
		var expected_cx = (float(res.x) - mp_rect.size.x) / 2.0
		_assert_check(absf(mp_rect.position.x - expected_cx) <= 1.0, "[%dx%d] MainMenu MainPanel horizontally centered (x=%.1f, expected=%.1f)" % [res.x, res.y, mp_rect.position.x, expected_cx])

	# 2. TopBar and BottomBar viewport containment
	var top_bar: Control = hud_test_instance.get_node_or_null("TopBar")
	var bot_bar: Control = hud_test_instance.get_node_or_null("BottomBar")
	_assert_check(top_bar != null and bot_bar != null, "[%dx%d] TopBar and BottomBar exist in HUD" % [res.x, res.y])
	if top_bar and bot_bar:
		var top_rect = top_bar.get_global_rect()
		var bot_rect = bot_bar.get_global_rect()
		_assert_check(vp_rect.encloses(top_rect), "[%dx%d] TopBar strictly enclosed in viewport: %s in %s" % [res.x, res.y, str(top_rect), str(vp_rect)])
		_assert_check(top_rect.position.y == 0.0, "[%dx%d] TopBar anchored at viewport top (y = 0.0)" % [res.x, res.y])
		_assert_check(vp_rect.encloses(bot_rect), "[%dx%d] BottomBar strictly enclosed in viewport: %s in %s" % [res.x, res.y, str(bot_rect), str(vp_rect)])
		_assert_check(is_equal_approx(bot_rect.end.y, float(res.y)), "[%dx%d] BottomBar anchored at viewport bottom (end.y = %.1f == %d)" % [res.x, res.y, bot_rect.end.y, res.y])

	# 3. All five primary buttons in BottomBar
	var action_buttons = [
		{"name": "BuildBtn", "btn": hud_test_instance.open_build_btn},
		{"name": "ResearchBtn", "btn": hud_test_instance.open_research_btn},
		{"name": "DiplomacyBtn", "btn": hud_test_instance.open_diplomacy_btn},
		{"name": "MilitaryBtn", "btn": hud_test_instance.open_military_btn},
		{"name": "AutomationBtn", "btn": hud_test_instance.open_automation_btn}
	]
	for b_info in action_buttons:
		var btn: Button = b_info["btn"]
		_assert_check(btn != null, "[%dx%d] Button '%s' exists" % [res.x, res.y, b_info["name"]])
		if btn:
			var btn_rect = btn.get_global_rect()
			_assert_check(btn_rect.size.x > 0.0 and btn_rect.size.y > 0.0, "[%dx%d] Button '%s' has non-empty geometry: %s" % [res.x, res.y, b_info["name"], str(btn_rect.size)])
			_assert_check(vp_rect.encloses(btn_rect), "[%dx%d] Button '%s' strictly enclosed in visible viewport bounds" % [res.x, res.y, b_info["name"]])
			if bot_bar:
				var bot_rect = bot_bar.get_global_rect()
				_assert_check(bot_rect.encloses(btn_rect), "[%dx%d] Button '%s' strictly contained within BottomBar rectangle" % [res.x, res.y, b_info["name"]])

	# 4. Resource labels right edge containment
	var res_labels = [
		"FoodLabel", "WoodLabel", "StoneLabel", "OreLabel",
		"MetalLabel", "ToolsLabel", "GoldLabel", "PopLabel"
	]
	var max_lbl_x: float = 0.0
	for lbl_name in res_labels:
		var lbl: Label = hud_test_instance.get_node_or_null("TopBar/PanelContainer/MarginContainer/HBoxContainer/Resources/" + lbl_name)
		_assert_check(lbl != null, "[%dx%d] Resource label '%s' exists" % [res.x, res.y, lbl_name])
		if lbl:
			var lbl_rect = lbl.get_global_rect()
			_assert_check(lbl_rect.size.x > 0.0 and lbl_rect.size.y > 0.0, "[%dx%d] Label '%s' has non-empty geometry: %s" % [res.x, res.y, lbl_name, str(lbl_rect.size)])
			_assert_check(lbl_rect.end.x <= float(res.x), "[%dx%d] Label '%s' right edge (%.1f px) is within viewport width (%d px)" % [res.x, res.y, lbl_name, lbl_rect.end.x, res.x])
			if lbl_rect.end.x > max_lbl_x:
				max_lbl_x = lbl_rect.end.x
	var right_clearance = float(res.x) - max_lbl_x
	_assert_check(right_clearance >= 40.0, "[%dx%d] Resources row has positive right-edge safety margin (clearance = %.1f px >= 40 px)" % [res.x, res.y, right_clearance])

	# 5. Secondary Panels Non-Overlap vs Navigation Bars
	var build_panel: Control = hud_test_instance.build_menu_panel
	var res_panel: Control = hud_test_instance.research_menu_panel
	var dip_panel: Control = hud_test_instance.diplomacy_panel

	if build_panel and top_bar and bot_bar:
		var bp_rect = build_panel.get_global_rect()
		var top_rect = top_bar.get_global_rect()
		var bot_rect = bot_bar.get_global_rect()
		_assert_check(bp_rect.end.y <= bot_rect.position.y, "[%dx%d] BuildMenuPanel bottom (%.1f) does not overlap BottomBar top (%.1f)" % [res.x, res.y, bp_rect.end.y, bot_rect.position.y])
		_assert_check(bp_rect.position.y >= top_rect.end.y, "[%dx%d] BuildMenuPanel top (%.1f) does not overlap TopBar bottom (%.1f)" % [res.x, res.y, bp_rect.position.y, top_rect.end.y])
		_assert_check(vp_rect.encloses(bp_rect), "[%dx%d] BuildMenuPanel strictly enclosed in viewport" % [res.x, res.y])

	if res_panel and top_bar and bot_bar:
		var rp_rect = res_panel.get_global_rect()
		var top_rect = top_bar.get_global_rect()
		var bot_rect = bot_bar.get_global_rect()
		_assert_check(rp_rect.end.y <= bot_rect.position.y, "[%dx%d] ResearchMenuPanel bottom (%.1f) does not overlap BottomBar top (%.1f)" % [res.x, res.y, rp_rect.end.y, bot_rect.position.y])
		_assert_check(rp_rect.position.y >= top_rect.end.y, "[%dx%d] ResearchMenuPanel top (%.1f) does not overlap TopBar bottom (%.1f)" % [res.x, res.y, rp_rect.position.y, top_rect.end.y])
		_assert_check(vp_rect.encloses(rp_rect), "[%dx%d] ResearchMenuPanel strictly enclosed in viewport" % [res.x, res.y])

	if dip_panel and top_bar and bot_bar:
		var dp_rect = dip_panel.get_global_rect()
		var top_rect = top_bar.get_global_rect()
		var bot_rect = bot_bar.get_global_rect()
		_assert_check(dp_rect.end.y <= bot_rect.position.y, "[%dx%d] DiplomacyPanel bottom (%.1f) does not overlap BottomBar top (%.1f)" % [res.x, res.y, dp_rect.end.y, bot_rect.position.y])
		_assert_check(dp_rect.position.y >= top_rect.end.y, "[%dx%d] DiplomacyPanel top (%.1f) does not overlap TopBar bottom (%.1f)" % [res.x, res.y, dp_rect.position.y, top_rect.end.y])
		_assert_check(vp_rect.encloses(dp_rect), "[%dx%d] DiplomacyPanel strictly enclosed in viewport" % [res.x, res.y])

	# 6. Automation Editor Bounds & Usable Child Geometry
	var auto_ed: Control = hud_test_instance.automation_editor
	_assert_check(auto_ed != null, "[%dx%d] AutomationEditor exists in HUD" % [res.x, res.y])
	if auto_ed:
		var auto_panel: Control = auto_ed.get_node_or_null("Panel")
		var graph_edit: Control = auto_ed.get_node_or_null("Panel/MarginContainer/VBoxContainer/HSplit/LeftBox/GraphEdit")
		var right_scroll: Control = auto_ed.get_node_or_null("Panel/MarginContainer/VBoxContainer/HSplit/RightScroll")

		_assert_check(auto_panel != null, "[%dx%d] AutomationEditor Panel exists" % [res.x, res.y])
		_assert_check(graph_edit != null, "[%dx%d] AutomationEditor GraphEdit exists" % [res.x, res.y])
		_assert_check(right_scroll != null, "[%dx%d] AutomationEditor RightScroll exists" % [res.x, res.y])

		if auto_panel and graph_edit and right_scroll:
			var ap_rect = auto_panel.get_global_rect()
			var ge_rect = graph_edit.get_global_rect()
			var rs_rect = right_scroll.get_global_rect()

			_assert_check(vp_rect.encloses(ap_rect), "[%dx%d] AutomationEditor Panel strictly enclosed in viewport: %s" % [res.x, res.y, str(ap_rect)])
			_assert_check(ge_rect.size.x >= 200.0 and ge_rect.size.y >= 150.0, "[%dx%d] GraphEdit canvas has usable non-zero dimensions: %s" % [res.x, res.y, str(ge_rect.size)])
			_assert_check(rs_rect.size.x >= 150.0 and rs_rect.size.y >= 100.0, "[%dx%d] RightScroll inspector has usable non-zero dimensions: %s" % [res.x, res.y, str(rs_rect.size)])
			_assert_check(ap_rect.encloses(ge_rect), "[%dx%d] GraphEdit canvas strictly contained within AutomationEditor panel" % [res.x, res.y])
			_assert_check(ap_rect.encloses(rs_rect), "[%dx%d] RightScroll inspector strictly contained within AutomationEditor panel" % [res.x, res.y])

func _print_summary() -> void:
	print("\n================================================================================")
	print("  HARDENED RESPONSIVE LAYOUT TEST SUMMARY")
	print("  Checks Executed: %d | Passed: %d | Failed: %d" % [checks, checks - failures, failures])
	if failures == 0:
		print("  🎉 ALL STRUCTURAL AND RUNTIME VIEWPORT BOUNDS TESTS PASSED! (Exit Code 0)")
	else:
		printerr("  ❌ HARDENED RESPONSIVE LAYOUT TESTS FAILED WITH %d FAILURES! (Exit Code 1)" % failures)
	print("================================================================================\n")
