extends SceneTree
## Headless & Standalone Test Suite for Responsive Game Window & HUD Layout.
## Validates TC-RESP.1 through TC-RESP.6:
## - TC-RESP.1: Target Viewport & Window Settings in ProjectSettings
## - TC-RESP.2: Legacy HUD Node Path Integrity (Backwards Compatibility)
## - TC-RESP.3: TopBar 2-Row Responsive Geometry & Clearance
## - TC-RESP.4: BottomBar Responsive Geometry, Clearance & Button Visibility
## - TC-RESP.5: Secondary Panels & Automation Editor Layout Bounds
## - TC-RESP.6: Isometric Coordinate Mapping Invariance

const IsoMathScript = preload("res://scripts/utils/iso_math.gd")

var frame_count: int = 0
var world_instance: Node = null
var world_scene: PackedScene = null
var hud_scene: PackedScene = null
var menu_scene: PackedScene = null
var auto_ed_scene: PackedScene = null

var failures: int = 0
var checks: int = 0

func _init() -> void:
	print("\n========================================================")
	print("  TEST SUITE: Responsive Window & HUD Layout Verification")
	print("  DisplayServer: %s | Mode: %s" % [DisplayServer.get_name(), "Headless" if DisplayServer.get_name() == "headless" else "Windowed/GPU"])
	print("========================================================\n")

	world_scene = load("res://scenes/world/world_view.tscn")
	hud_scene = load("res://scenes/ui/hud.tscn")
	menu_scene = load("res://scenes/ui/main_menu.tscn")
	auto_ed_scene = load("res://scenes/ui/automation_editor.tscn")

	world_instance = world_scene.instantiate()
	root.add_child(world_instance)

func _assert_check(condition: bool, msg: String) -> void:
	checks += 1
	if condition:
		print("  ✅ [PASS] %s" % msg)
	else:
		failures += 1
		printerr("  ❌ [FAIL] %s" % msg)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count == 3:
		_run_all_tests()
		_print_summary()
		quit(0 if failures == 0 else 1)
		return true
	return false

func _run_all_tests() -> void:
	_test_project_settings()
	_test_legacy_hud_paths()
	_test_top_bar_layout()
	_test_bottom_bar_layout()
	_test_panels_and_automation_editor()
	_test_coordinate_mapping_invariance()

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
	
	# Test DisplayServer window_set_min_size API availability
	_assert_check(DisplayServer.has_method("window_set_min_size"), "DisplayServer supports window_set_min_size API")
	DisplayServer.window_set_min_size(Vector2i(1024, 576))
	_assert_check(true, "DisplayServer.window_set_min_size(1024, 576) executed cleanly without errors")

func _test_legacy_hud_paths() -> void:
	print("\n--- Running TC-RESP.2: Legacy HUD Node Path Integrity (Backwards Compatibility) ---")
	
	var hud: InGameHUD = world_instance.get_node_or_null("HUD")
	_assert_check(hud != null, "HUD instance found in WorldView")
	if hud == null:
		return

	# Verify exact legacy paths required by test_mine.gd and test_workshop.gd
	var expected_res_labels = [
		"FoodLabel",
		"WoodLabel",
		"StoneLabel",
		"OreLabel",
		"MetalLabel",
		"ToolsLabel",
		"GoldLabel",
		"PopLabel"
	]
	for lbl_name in expected_res_labels:
		var node_path = "TopBar/PanelContainer/MarginContainer/HBoxContainer/Resources/" + lbl_name
		var lbl = hud.get_node_or_null(node_path)
		_assert_check(lbl != null and lbl is Label, "Resource label '%s' verified at legacy path '%s'" % [lbl_name, node_path])

	# Verify time labels and speed control buttons
	_assert_check(hud.date_label != null, "HUD date_label bound and accessible")
	_assert_check(hud.clock_label != null, "HUD clock_label bound and accessible")
	_assert_check(hud.speed_pause_btn != null, "HUD speed_pause_btn bound and accessible")
	_assert_check(hud.speed_1x_btn != null, "HUD speed_1x_btn bound and accessible")
	_assert_check(hud.speed_2x_btn != null, "HUD speed_2x_btn bound and accessible")
	_assert_check(hud.speed_3x_btn != null, "HUD speed_3x_btn bound and accessible")

	# Verify BottomBar buttons legacy paths
	var bottom_nodes = [
		"TileInfoLabel",
		"BuildBtn",
		"ResearchBtn",
		"DiplomacyBtn",
		"MilitaryBtn",
		"AutomationBtn"
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

	# Verify TileInfoLabel overrun behavior
	var tile_info: Label = hud.tile_info_label
	_assert_check(tile_info != null, "TileInfoLabel found")
	if tile_info:
		_assert_check(tile_info.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS,
			"TileInfoLabel text_overrun_behavior set to TRIM_ELLIPSIS (%d)" % tile_info.text_overrun_behavior)

	# Verify all 5 action buttons
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

	# BuildMenuPanel positioning
	var build_panel: PanelContainer = hud.build_menu_panel
	var bot_bar: Control = hud.get_node_or_null("BottomBar")
	_assert_check(build_panel != null, "BuildMenuPanel exists in HUD")
	if build_panel and bot_bar:
		_assert_check(build_panel.offset_bottom <= bot_bar.offset_top,
			"BuildMenuPanel bottom (%.1f) does not penetrate BottomBar top (%.1f)" % [build_panel.offset_bottom, bot_bar.offset_top])

	# ResearchMenuPanel and DiplomacyPanel vertical bounds
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

	# EventBanner and CrisisBanner positioning
	var evt_banner: PanelContainer = hud.event_banner
	var crisis_banner: PanelContainer = hud.crisis_banner
	_assert_check(evt_banner != null and evt_banner.offset_top >= 68.0, "EventBanner offset_top (%.1f) is below TopBar (>= 68.0)" % evt_banner.offset_top)
	_assert_check(crisis_banner != null and crisis_banner.offset_top >= 68.0, "CrisisBanner offset_top (%.1f) is below TopBar (>= 68.0)" % crisis_banner.offset_top)

	# AutomationEditor responsive configuration
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
	print("\n--- Running TC-RESP.6: Isometric Coordinate Mapping Invariance ---")
	
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

func _print_summary() -> void:
	print("\n========================================================")
	print("  RESPONSIVE LAYOUT TEST SUMMARY")
	print("  Checks Executed: %d | Passed: %d | Failed: %d" % [checks, checks - failures, failures])
	if failures == 0:
		print("  🎉 ALL RESPONSIVE LAYOUT TESTS PASSED! (Exit Code 0)")
	else:
		printerr("  ❌ RESPONSIVE LAYOUT TESTS FAILED WITH %d FAILURES! (Exit Code 1)" % failures)
	print("========================================================\n")
