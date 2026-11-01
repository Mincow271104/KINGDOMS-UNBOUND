extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — Package 2F: Building Inspection, Workplace Management & Demolition
## Authoritative Coverage: TC-BM.1 through TC-BM.34 (Fail-Closed Assertions)

const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")
const WorkplaceManagerScript = preload("res://scripts/economy/workplace_manager.gd")
const JobManagerScript = preload("res://scripts/jobs/job_manager.gd")
const JobData = JobManagerScript.JobData
const JobState = JobManagerScript.JobState
const BuildingSelectionHighlightScript = preload("res://scripts/world/building_selection_highlight.gd")
const CitizenSkillDataScript = preload("res://scripts/entities/citizen_skill_data.gd")
const IsoMathScript = preload("res://scripts/utils/iso_math.gd")
const VictoryManagerScript = preload("res://scripts/core/victory_manager.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")

var frame_count: int = 0
var world_instance: Node = null
var all_passed: bool = true

func _init() -> void:
	print("\n========================================================")
	print("  STARTING PACKAGE 2F BUILDING MANAGEMENT TEST SUITE")
	print("========================================================\n")

	var world_scene = load("res://scenes/world/world_view.tscn")
	world_instance = world_scene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count == 3:
		var results: Array[bool] = []
		results.append(_test_tc_bm_1_1x1_footprint())
		results.append(_test_tc_bm_2_2x2_footprint())
		results.append(_test_tc_bm_3_3x3_footprint())
		results.append(_test_tc_bm_4_ground_misses())
		results.append(_test_tc_bm_5_click_priority())
		results.append(_test_tc_bm_6_highlight_geometry())
		results.append(_test_tc_bm_7_panel_data_reflection())
		results.append(_test_tc_bm_8_buffer_saturation())
		results.append(_test_tc_bm_9_workshop_dual_channels())
		results.append(_test_tc_bm_10_worker_roster_skills())
		results.append(_test_tc_bm_11_worker_click_to_inspector())
		results.append(_test_tc_bm_12_civic_descriptions())
		results.append(_test_tc_bm_13_construction_inspection())
		results.append(_test_tc_bm_14_cancel_preflight())
		results.append(_test_tc_bm_15_cancel_fail_closed_storage())
		results.append(_test_tc_bm_16_cancel_execution())
		results.append(_test_tc_bm_17_demolish_preflight())
		results.append(_test_tc_bm_18_demolish_storage_preflight())
		results.append(_test_tc_bm_19_demolish_execution())
		results.append(_test_tc_bm_20_workplace_unregistration())
		results.append(_test_tc_bm_21_townhall_warning())
		results.append(_test_tc_bm_22_townhall_collapse_grace())
		results.append(_test_tc_bm_23_pause_lifecycle())
		results.append(_test_tc_bm_24_pause_halts_production())
		results.append(_test_tc_bm_25_pause_releases_workers())
		results.append(_test_tc_bm_26_pause_refuses_new_workers())
		results.append(_test_tc_bm_27_pause_allows_hauling())
		results.append(_test_tc_bm_28_resume_restores_operations())
		results.append(_test_tc_bm_29_save_load_persistence())
		results.append(_test_tc_bm_30_escape_key_hierarchy())
		results.append(_test_tc_bm_31_workshop_pause_channels())
		results.append(_test_tc_bm_32_atomic_refund_failure_injection())
		results.append(_test_tc_bm_33_cargo_conservation_scenarios())
		results.append(_test_tc_bm_34_starter_storage_capacity_invariant())

		all_passed = true
		for r in results:
			if not r:
				all_passed = false
				break

		print("\n--------------------------------------------------------")
		if all_passed:
			print("  ALL PACKAGE 2F BUILDING MANAGEMENT TESTS PASSED! (Exit Code 0)")
			print("--------------------------------------------------------\n")
			quit(0)
			return true
		else:
			print("  PACKAGE 2F BUILDING MANAGEMENT TESTS FAILED! (Exit Code 1)")
			print("--------------------------------------------------------\n")
			quit(1)
			return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.1: 1x1 Footprint Hit Testing
# -----------------------------------------------------------------------------
func _test_tc_bm_1_1x1_footprint() -> bool:
	print("--- Running TC-BM.1: 1x1 Footprint Selection ---")
	var failures: int = 0
	var wd = world_instance.world_data
	var cell := Vector2i(10, 10)
	var b_data := {
		"id": "test_watchtower_1",
		"type": "watchtower",
		"cell": cell,
		"size": Vector2i(1, 1),
		"state": "active",
		"health": 100
	}
	wd.buildings.append(b_data)

	var hit = world_instance._get_building_at_cell(cell)
	if hit.is_empty() or hit.get("id") != "test_watchtower_1":
		printerr("FAIL: 1x1 building not detected at exact cell (10, 10)")
		failures += 1

	var miss = world_instance._get_building_at_cell(Vector2i(11, 10))
	if not miss.is_empty() and miss.get("id") == "test_watchtower_1":
		printerr("FAIL: 1x1 building falsely hit outside cell at (11, 10)")
		failures += 1

	wd.buildings.erase(b_data)
	if failures == 0:
		print("  [PASS] TC-BM.1: 1x1 footprint selection verified.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.2: 2x2 Footprint Hit Testing
# -----------------------------------------------------------------------------
func _test_tc_bm_2_2x2_footprint() -> bool:
	print("--- Running TC-BM.2: 2x2 Footprint Selection ---")
	var failures: int = 0
	var wd = world_instance.world_data
	var origin := Vector2i(15, 15)
	var b_data := {
		"id": "test_farm_2x2",
		"type": "farm",
		"cell": origin,
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100
	}
	wd.buildings.append(b_data)

	# Verify all 4 footprint cells
	var cells := [Vector2i(15, 15), Vector2i(16, 15), Vector2i(15, 16), Vector2i(16, 16)]
	for c in cells:
		var hit = world_instance._get_building_at_cell(c)
		if hit.is_empty() or hit.get("id") != "test_farm_2x2":
			printerr("FAIL: 2x2 building not hit at internal cell %s" % str(c))
			failures += 1

	var outside := [Vector2i(14, 15), Vector2i(17, 15), Vector2i(15, 14), Vector2i(15, 17)]
	for oc in outside:
		var miss = world_instance._get_building_at_cell(oc)
		if not miss.is_empty() and miss.get("id") == "test_farm_2x2":
			printerr("FAIL: 2x2 building falsely hit outside at %s" % str(oc))
			failures += 1

	wd.buildings.erase(b_data)
	if failures == 0:
		print("  [PASS] TC-BM.2: 2x2 footprint selection verified on all 4 cells.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.3: 3x3 Footprint Hit Testing
# -----------------------------------------------------------------------------
func _test_tc_bm_3_3x3_footprint() -> bool:
	print("--- Running TC-BM.3: 3x3 Footprint Selection ---")
	var failures: int = 0
	var wd = world_instance.world_data
	var origin := Vector2i(20, 20)
	var b_data := {
		"id": "test_townhall_3x3",
		"type": "townhall",
		"cell": origin,
		"size": Vector2i(3, 3),
		"state": "active",
		"health": 100
	}
	wd.buildings.append(b_data)

	# Verify all 9 footprint cells
	for ox in range(3):
		for oy in range(3):
			var c := origin + Vector2i(ox, oy)
			var hit = world_instance._get_building_at_cell(c)
			if hit.is_empty() or hit.get("id") != "test_townhall_3x3":
				printerr("FAIL: 3x3 building not hit at internal cell %s" % str(c))
				failures += 1

	var miss = world_instance._get_building_at_cell(Vector2i(23, 20))
	if not miss.is_empty() and miss.get("id") == "test_townhall_3x3":
		printerr("FAIL: 3x3 building falsely hit outside at (23, 20)")
		failures += 1

	wd.buildings.erase(b_data)
	if failures == 0:
		print("  [PASS] TC-BM.3: 3x3 footprint selection verified on all 9 cells.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.4: Ground Misses
# -----------------------------------------------------------------------------
func _test_tc_bm_4_ground_misses() -> bool:
	print("--- Running TC-BM.4: Non-Building Ground Clicks ---")
	var failures: int = 0
	var hit = world_instance._get_building_at_cell(Vector2i(0, 0))
	if not hit.is_empty():
		printerr("FAIL: Unexpected building found at (0, 0)")
		failures += 1

	hit = world_instance._get_building_at_cell(Vector2i(-5, -5))
	if not hit.is_empty():
		printerr("FAIL: Unexpected building found at (-5, -5)")
		failures += 1

	if failures == 0:
		print("  [PASS] TC-BM.4: Non-building ground clicks safely return empty.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.5: Selection Priority Order & Real Mouse Input Handling
# -----------------------------------------------------------------------------
func _simulate_mouse_click(world: Node, cell: Vector2i, shift: bool = false) -> void:
	var press_event := InputEventMouseButton.new()
	press_event.button_index = MOUSE_BUTTON_LEFT
	press_event.pressed = true
	press_event.shift_pressed = shift
	press_event.set_meta("target_cell", cell)
	world._unhandled_input(press_event)

	var release_event := InputEventMouseButton.new()
	release_event.button_index = MOUSE_BUTTON_LEFT
	release_event.pressed = false
	release_event.shift_pressed = shift
	release_event.set_meta("target_cell", cell)
	world._unhandled_input(release_event)

func _test_tc_bm_5_click_priority() -> bool:
	print("--- Running TC-BM.5: Selection Priority Hierarchy ---")
	var failures: int = 0
	var hud = world_instance.hud

	# Setup buildings for testing 1x1, 2x2, and 3x3 footprints
	var b_1x1 := {
		"id": "pri_test_1x1",
		"type": "watchtower",
		"cell": Vector2i(10, 10),
		"size": Vector2i(1, 1),
		"state": "active",
		"health": 100
	}
	var b_2x2 := {
		"id": "pri_test_2x2",
		"type": "farm",
		"cell": Vector2i(12, 12),
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100
	}
	var b_3x3 := {
		"id": "pri_test_3x3",
		"type": "townhall",
		"cell": Vector2i(16, 16),
		"size": Vector2i(3, 3),
		"state": "active",
		"health": 100
	}
	world_instance.world_data.buildings.append(b_1x1)
	world_instance.world_data.buildings.append(b_2x2)
	world_instance.world_data.buildings.append(b_3x3)

	# 1. 1x1 Building click through _unhandled_input
	_simulate_mouse_click(world_instance, Vector2i(10, 10))
	if world_instance.selected_building_id != "pri_test_1x1":
		printerr("FAIL: 1x1 building was not selected via _unhandled_input mouse click")
		failures += 1
	if not hud.building_inspect_panel.visible:
		printerr("FAIL: Building inspect panel not opened on 1x1 building click")
		failures += 1

	# 2. 2x2 Building click through _unhandled_input across all 4 cells
	for ox in range(2):
		for oy in range(2):
			_simulate_mouse_click(world_instance, Vector2i(12 + ox, 12 + oy))
			if world_instance.selected_building_id != "pri_test_2x2":
				printerr("FAIL: 2x2 building not selected on cell (%d, %d)" % [12 + ox, 12 + oy])
				failures += 1

	# 3. 3x3 Building click through _unhandled_input across all 9 cells
	for ox in range(3):
		for oy in range(3):
			_simulate_mouse_click(world_instance, Vector2i(16 + ox, 16 + oy))
			if world_instance.selected_building_id != "pri_test_3x3":
				printerr("FAIL: 3x3 building not selected on cell (%d, %d)" % [16 + ox, 16 + oy])
				failures += 1

	# 4. Exact-cell citizen click takes priority over empty ground & opens CitizenInspectPanel
	var test_cit = world_instance.citizen_list[0]
	var orig_cit_cell = test_cit.current_cell
	test_cit.current_cell = Vector2i(20, 20)
	_simulate_mouse_click(world_instance, Vector2i(20, 20))
	if not hud.citizen_panel.visible:
		printerr("FAIL: Citizen panel not opened when exact citizen cell was clicked")
		failures += 1
	if hud.inspected_citizen != test_cit:
		printerr("FAIL: Inspected citizen not set to clicked citizen")
		failures += 1
	if world_instance.selected_building_id != "":
		printerr("FAIL: Building selection should be cleared when citizen is clicked")
		failures += 1
	test_cit.current_cell = orig_cit_cell
	hud.close_citizen_inspector()

	# 5. Tactical unit takes priority over building underneath
	if world_instance.tactical_military_mgr != null:
		var tac_mgr = world_instance.tactical_military_mgr
		var tac_u = tac_mgr._create_unit_instance("pri_test_soldier", Vector2i(12, 12))
		tac_mgr.units["pri_test_soldier"] = tac_u
		_simulate_mouse_click(world_instance, Vector2i(12, 12))
		if not tac_mgr.is_unit_selected("pri_test_soldier"):
			printerr("FAIL: Tactical unit on building was not selected over building")
			failures += 1
		if world_instance.selected_building_id != "":
			printerr("FAIL: Building should NOT be selected when tactical unit on it is clicked")
			failures += 1
		tac_mgr.clear_selection()
		tac_mgr._remove_unit("pri_test_soldier")

	# 6. Click on empty ground clears building selection and closes panels
	_simulate_mouse_click(world_instance, Vector2i(12, 12)) # select building
	if world_instance.selected_building_id != "pri_test_2x2":
		printerr("FAIL: Re-selection failed")
		failures += 1
	_simulate_mouse_click(world_instance, Vector2i(0, 0)) # click empty ground
	if world_instance.selected_building_id != "":
		printerr("FAIL: Building selection not cleared on empty ground click")
		failures += 1
	if hud.building_inspect_panel.visible:
		printerr("FAIL: Building inspect panel remained visible on empty ground click")
		failures += 1

	# 7. Drag box does not trigger simple building selection
	var press_drag := InputEventMouseButton.new()
	press_drag.button_index = MOUSE_BUTTON_LEFT
	press_drag.pressed = true
	press_drag.position = Vector2(100, 100)
	world_instance._unhandled_input(press_drag)
	var move_drag := InputEventMouseMotion.new()
	move_drag.position = Vector2(250, 250)
	world_instance._unhandled_input(move_drag)
	var release_drag := InputEventMouseButton.new()
	release_drag.button_index = MOUSE_BUTTON_LEFT
	release_drag.pressed = false
	release_drag.position = Vector2(250, 250)
	world_instance._unhandled_input(release_drag)
	if world_instance.selected_building_id != "":
		printerr("FAIL: Drag selection falsely triggered building selection")
		failures += 1

	# 8. Building placement mode does not trigger building selection
	world_instance.placing_building_type = "farm"
	_simulate_mouse_click(world_instance, Vector2i(12, 12))
	if world_instance.selected_building_id != "":
		printerr("FAIL: Building selected during placement mode")
		failures += 1
	world_instance.placing_building_type = ""

	# 9. Army move targeting mode does not trigger building selection
	if hud.has_method("set_army_move_targeting"):
		hud.set_army_move_targeting(true)
		_simulate_mouse_click(world_instance, Vector2i(12, 12))
		if world_instance.selected_building_id != "":
			printerr("FAIL: Building selected during army move targeting mode")
			failures += 1
		hud.set_army_move_targeting(false)

	# Clean up test buildings
	world_instance.world_data.buildings.erase(b_1x1)
	world_instance.world_data.buildings.erase(b_2x2)
	world_instance.world_data.buildings.erase(b_3x3)
	hud.close_building_inspector()

	if failures == 0:
		print("  [PASS] TC-BM.5: Selection priority and dismissal verified.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.6: BuildingSelectionHighlight Diamond Geometry
# -----------------------------------------------------------------------------
func _test_tc_bm_6_highlight_geometry() -> bool:
	print("--- Running TC-BM.6: Diamond Footprint Highlight Geometry ---")
	var failures: int = 0

	# 1x1 Diamond
	var pts_1x1 := BuildingSelectionHighlightScript.compute_diamond_vertices(Vector2i(10, 10), Vector2i(1, 1))
	if pts_1x1.size() != 4:
		printerr("FAIL: 1x1 diamond vertices count must be 4, got: %d" % pts_1x1.size())
		failures += 1
	var top_1x1 := IsoMathScript.map_to_local(Vector2i(10, 10)) + Vector2(0, -16)
	if pts_1x1[0] != top_1x1:
		printerr("FAIL: 1x1 top vertex mismatch: expected %s, got %s" % [str(top_1x1), str(pts_1x1[0])])
		failures += 1

	# 2x2 Diamond
	var pts_2x2 := BuildingSelectionHighlightScript.compute_diamond_vertices(Vector2i(10, 10), Vector2i(2, 2))
	if pts_2x2.size() != 4:
		printerr("FAIL: 2x2 diamond vertices count must be 4, got: %d" % pts_2x2.size())
		failures += 1
	var bottom_2x2 := IsoMathScript.map_to_local(Vector2i(11, 11)) + Vector2(0, 0)
	if pts_2x2[2] != bottom_2x2:
		printerr("FAIL: 2x2 bottom vertex mismatch: expected %s, got %s" % [str(bottom_2x2), str(pts_2x2[2])])
		failures += 1

	# 3x3 Diamond
	var pts_3x3 := BuildingSelectionHighlightScript.compute_diamond_vertices(Vector2i(10, 10), Vector2i(3, 3))
	if pts_3x3.size() != 4:
		printerr("FAIL: 3x3 diamond vertices count must be 4, got: %d" % pts_3x3.size())
		failures += 1
	var right_3x3 := IsoMathScript.map_to_local(Vector2i(12, 10)) + Vector2(16, -8)
	if pts_3x3[1] != right_3x3:
		printerr("FAIL: 3x3 right vertex mismatch: expected %s, got %s" % [str(right_3x3), str(pts_3x3[1])])
		failures += 1

	if failures == 0:
		print("  [PASS] TC-BM.6: Diamond highlight mathematical vertices verified.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.7: BuildingInspectPanel Live Data Reflection
# -----------------------------------------------------------------------------
func _test_tc_bm_7_panel_data_reflection() -> bool:
	print("--- Running TC-BM.7: BuildingInspectPanel Live Reflection ---")
	var failures: int = 0
	var hud = world_instance.hud
	var b_data := {
		"id": "panel_ref_test",
		"type": "farm",
		"cell": Vector2i(14, 18),
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 85
	}
	world_instance.world_data.buildings.append(b_data)

	hud.show_building_inspector(b_data)
	if hud.building_title_label.text != "Nông Trại":
		printerr("FAIL: Panel title expected 'Nông Trại', got: '%s'" % hud.building_title_label.text)
		failures += 1
	if not "(14, 18)" in hud.building_coords_label.text:
		printerr("FAIL: Coordinates label missing (14, 18): '%s'" % hud.building_coords_label.text)
		failures += 1
	if hud.building_health_bar.value != 85.0:
		printerr("FAIL: Expected health bar value 85, got: %f" % hud.building_health_bar.value)
		failures += 1
	if not "85 / 100" in hud.building_health_label.text:
		printerr("FAIL: Health label missing '85 / 100': '%s'" % hud.building_health_label.text)
		failures += 1
	if hud.building_state_label.text != "[ĐANG HOẠT ĐỘNG]":
		printerr("FAIL: State badge expected '[ĐANG HOẠT ĐỘNG]', got: '%s'" % hud.building_state_label.text)
		failures += 1

	hud.close_building_inspector()
	world_instance.world_data.buildings.erase(b_data)
	if failures == 0:
		print("  [PASS] TC-BM.7: Authoritative building panel data verified.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.8: Workplace Buffer Saturation Indicators
# -----------------------------------------------------------------------------
func _test_tc_bm_8_buffer_saturation() -> bool:
	print("--- Running TC-BM.8: Buffer Saturation Warnings ---")
	var failures: int = 0
	var hud = world_instance.hud
	var wp_mgr = world_instance.workplace_mgr

	var wp = wp_mgr.get_workplace("farm_starter")
	if wp == null:
		printerr("FAIL: farm_starter workplace not found")
		return false

	var b_data := {"id": "farm_starter", "type": "farm", "cell": Vector2i(36, 35), "size": Vector2i(2, 2), "state": "active"}

	# 1. Normal state (< 80%)
	wp.buffer_amount = 10
	wp.buffer_capacity = 50
	hud.show_building_inspector(b_data)
	if not "bình thường" in hud.buffer_saturation_label.text.to_lower():
		printerr("FAIL: Expected normal status for 10/50, got: '%s'" % hud.buffer_saturation_label.text)
		failures += 1

	# 2. Warning state (>= 80%)
	wp.buffer_amount = 40
	hud.refresh_building_inspector()
	if not "cảnh báo" in hud.buffer_saturation_label.text.to_lower():
		printerr("FAIL: Expected warning status for 40/50, got: '%s'" % hud.buffer_saturation_label.text)
		failures += 1

	# 3. Full / Blocked state (100%)
	wp.buffer_amount = 50
	hud.refresh_building_inspector()
	if not "đầy kho đệm" in hud.buffer_saturation_label.text.to_lower():
		printerr("FAIL: Expected full blocked status for 50/50, got: '%s'" % hud.buffer_saturation_label.text)
		failures += 1

	wp.buffer_amount = 0
	hud.close_building_inspector()
	if failures == 0:
		print("  [PASS] TC-BM.8: Buffer saturation thresholds (<80%, >=80%, 100%) verified.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.9: Workshop Dual-Channel Buffer Display
# -----------------------------------------------------------------------------
func _test_tc_bm_9_workshop_dual_channels() -> bool:
	print("--- Running TC-BM.9: Workshop Dual-Channel Buffer Reflection ---")
	var failures: int = 0
	var hud = world_instance.hud
	var origin := Vector2i(22, 22)
	var b_data := {
		"id": "bld_ws_dual_test",
		"type": "workshop",
		"cell": origin,
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100
	}
	world_instance.world_data.buildings.append(b_data)
	world_instance.register_dynamic_workplace(b_data)

	var smelt_wp = world_instance.workplace_mgr.get_workplace("bld_ws_dual_test_smelt")
	var craft_wp = world_instance.workplace_mgr.get_workplace("bld_ws_dual_test_craft")
	if smelt_wp == null or craft_wp == null:
		printerr("FAIL: Workshop channels failed registration")
		world_instance.workplace_mgr.unregister_workplace("bld_ws_dual_test")
		world_instance.world_data.buildings.erase(b_data)
		return false

	smelt_wp.buffer_amount = 15
	craft_wp.buffer_amount = 8

	hud.show_building_inspector(b_data)
	if not hud.workshop_channels_container.visible:
		printerr("FAIL: Workshop channels container not visible for workshop")
		failures += 1
	if hud.workshop_channels_container.get_child_count() != 2:
		printerr("FAIL: Expected 2 channel UI blocks in container, got: %d" % hud.workshop_channels_container.get_child_count())
		failures += 1

	hud.close_building_inspector()
	world_instance.workplace_mgr.unregister_workplace("bld_ws_dual_test")
	world_instance.world_data.buildings.erase(b_data)
	if failures == 0:
		print("  [PASS] TC-BM.9: Workshop dual-channel UI reflection verified.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.10: Worker Roster & Package 2B Skills
# -----------------------------------------------------------------------------
func _test_tc_bm_10_worker_roster_skills() -> bool:
	print("--- Running TC-BM.10: Worker Roster with Package 2B Skills ---")
	var failures: int = 0
	var hud = world_instance.hud
	if world_instance.citizen_list.is_empty():
		printerr("FAIL: Citizen list is empty")
		return false

	var cit = world_instance.citizen_list[0]
	cit.role = "farmer"
	var s_data: CitizenSkillData = cit.get_skill_data()
	s_data.set_xp("farming", 300.0)

	var job = JobData.new()
	job.id = "roster_test_job"
	job.type = "farmer"
	job.target_building_id = "farm_starter"
	job.state = JobState.IN_PROGRESS
	cit.active_job = job

	var b_data := {"id": "farm_starter", "type": "farm", "cell": Vector2i(36, 35), "size": Vector2i(2, 2), "state": "active"}
	hud.show_building_inspector(b_data)

	var roster = hud.workers_container
	var btn: Button = null
	for ch in roster.get_children():
		if ch is Button:
			btn = ch
			break

	if btn != null:
		if not "Cấp 3" in btn.text or not "+16%" in btn.text:
			printerr("FAIL: Worker button missing vocational skill string: '%s'" % btn.text)
			failures += 1
	else:
		printerr("FAIL: No worker button found in roster")
		failures += 1

	cit.active_job = null
	hud.close_building_inspector()
	if failures == 0:
		print("  [PASS] TC-BM.10: Worker roster reflects Package 2B vocational skills.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.11: Worker Click to Inspector
# -----------------------------------------------------------------------------
func _test_tc_bm_11_worker_click_to_inspector() -> bool:
	print("--- Running TC-BM.11: Worker Roster Click to Citizen Inspector ---")
	var failures: int = 0
	var hud = world_instance.hud
	var cit = world_instance.citizen_list[0]
	cit.role = "farmer"
	var job = JobData.new()
	job.id = "inspect_test_job"
	job.type = "farmer"
	job.target_building_id = "farm_starter"
	cit.active_job = job

	var b_data := {"id": "farm_starter", "type": "farm", "cell": Vector2i(36, 35), "size": Vector2i(2, 2), "state": "active"}
	hud.show_building_inspector(b_data)

	var roster = hud.workers_container
	var found_btn: Button = null
	for ch in roster.get_children():
		if ch is Button:
			found_btn = ch
			break

	if found_btn != null:
		found_btn.emit_signal("pressed")
		if not hud.citizen_panel.visible:
			printerr("FAIL: Citizen panel not opened when worker button was clicked")
			failures += 1
		if hud.inspected_citizen != cit:
			printerr("FAIL: Inspected citizen not set to clicked worker")
			failures += 1
	else:
		printerr("FAIL: No worker button found to click")
		failures += 1

	cit.active_job = null
	hud.close_citizen_inspector()
	hud.close_building_inspector()
	if failures == 0:
		print("  [PASS] TC-BM.11: Seamless transition from building worker to citizen inspector.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.12: Civic Descriptions & Stats
# -----------------------------------------------------------------------------
func _test_tc_bm_12_civic_descriptions() -> bool:
	print("--- Running TC-BM.12: Civic Buildings Description & Stats ---")
	var failures: int = 0
	var hud = world_instance.hud
	var civic_types := ["townhall", "house", "storehouse", "barracks", "watchtower", "market", "research_hall"]

	for t in civic_types:
		var b_data := {"id": "test_" + t, "type": t, "cell": Vector2i(1, 1), "size": Vector2i(1, 1), "state": "active"}
		hud.show_building_inspector(b_data)
		if not hud.civic_section.visible:
			printerr("FAIL: Civic section not visible for civic building type '%s'" % t)
			failures += 1
		if hud.civic_desc_label.text.is_empty() or hud.civic_stats_label.text.is_empty():
			printerr("FAIL: Civic text empty for '%s'" % t)
			failures += 1

		# Data-driven blueprint value assertions
		var bp: Dictionary = EconomyConfigScript.BLUEPRINTS.get(t, {})
		var s_bonus: Dictionary = bp.get("storage_bonus", {})
		if t == "townhall":
			if "10 cư dân" in hud.civic_stats_label.text or "8 ô" in hud.civic_stats_label.text:
				printerr("FAIL: Town Hall stats must NOT contain ungrounded housing (10) or vision (8)")
				failures += 1
			for res in s_bonus:
				var r_name: String = EconomyConfigScript.RESOURCE_NAMES_VI.get(res, res)
				var expected_part := "%s +%d" % [r_name, int(s_bonus[res])]
				if not expected_part in hud.civic_stats_label.text:
					printerr("FAIL: Town Hall stats missing derived blueprint bonus: '%s'" % expected_part)
					failures += 1
			if not "72 giờ" in hud.civic_stats_label.text:
				printerr("FAIL: Town Hall stats must reflect 72h emergency collapse warning")
				failures += 1
		elif t == "house":
			var h_cap: int = int(bp.get("housing_capacity", 6))
			var expected_cap := "%d cư dân" % h_cap
			if not expected_cap in hud.civic_stats_label.text:
				printerr("FAIL: House stats missing derived blueprint capacity: '%s'" % expected_cap)
				failures += 1
		elif t == "storehouse":
			for res in s_bonus:
				var r_name: String = EconomyConfigScript.RESOURCE_NAMES_VI.get(res, res)
				var expected_part := "%s +%d" % [r_name, int(s_bonus[res])]
				if not expected_part in hud.civic_stats_label.text:
					printerr("FAIL: Storehouse stats missing derived blueprint bonus: '%s'" % expected_part)
					failures += 1
		elif t == "watchtower":
			var v_rad: int = int(bp.get("vision_radius", 15))
			var expected_rad := "%d ô" % v_rad
			if not expected_rad in hud.civic_stats_label.text:
				printerr("FAIL: Watchtower stats missing derived blueprint vision radius: '%s'" % expected_rad)
				failures += 1
		elif t == "barracks":
			var guard_cap: int = int(bp.get("guard_capacity", 0))
			var expected_guard := "%d Vệ Binh" % guard_cap
			var expected_army := "+%d binh sĩ" % EconomyConfigScript.ARMY_CAPACITY_PER_BARRACKS
			if not expected_guard in hud.civic_stats_label.text or not expected_army in hud.civic_stats_label.text:
				printerr("FAIL: Barracks stats missing derived guard/army capacity: '%s', '%s'" % [expected_guard, expected_army])
				failures += 1

	hud.close_building_inspector()
	if failures == 0:
		print("  [PASS] TC-BM.12: All 7 civic building types provide verified descriptions and stats.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.13: Construction Inspection
# -----------------------------------------------------------------------------
func _test_tc_bm_13_construction_inspection() -> bool:
	print("--- Running TC-BM.13: Construction Site Live Inspection ---")
	var failures: int = 0
	var hud = world_instance.hud
	var b_data := {
		"id": "bld_under_constr_test",
		"type": "farm",
		"cell": Vector2i(30, 30),
		"size": Vector2i(2, 2),
		"state": "under_construction",
		"construction_progress": 6.0,
		"construction_hours": 12.0,
		"health": 100
	}
	world_instance.world_data.buildings.append(b_data)

	hud.show_building_inspector(b_data)
	if not hud.construction_section.visible:
		printerr("FAIL: Construction section not visible for building under construction")
		failures += 1
	if hud.construction_prog_bar.value != 50.0:
		printerr("FAIL: Expected progress bar 50%, got: %f" % hud.construction_prog_bar.value)
		failures += 1
	if not "6.0 / 12.0" in hud.construction_prog_label.text:
		printerr("FAIL: Construction hours label missing '6.0 / 12.0': '%s'" % hud.construction_prog_label.text)
		failures += 1
	if hud.pause_resume_btn.visible:
		printerr("FAIL: Pause button must be hidden during construction")
		failures += 1

	hud.close_building_inspector()
	world_instance.world_data.buildings.erase(b_data)
	if failures == 0:
		print("  [PASS] TC-BM.13: Construction site progress bar, hours, and controls verified.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.14: Construction Cancellation Preflight (50% Refund)
# -----------------------------------------------------------------------------
func _test_tc_bm_14_cancel_preflight() -> bool:
	print("--- Running TC-BM.14: Construction Cancellation Preflight (50% Refund) ---")
	var failures: int = 0
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	var b_data := {
		"id": "cancel_pre_test",
		"type": "workshop", # cost: 20 Wood, 15 Stone, 5 Metal
		"cell": Vector2i(30, 30),
		"size": Vector2i(2, 2),
		"state": "under_construction"
	}

	var res := BuildingSystemScript.can_cancel_construction(b_data, world_instance.world_data, rm)
	if not res.get("can_cancel", false):
		printerr("FAIL: can_cancel_construction returned false: %s" % res.get("reason", ""))
		failures += 1
	var refund: Dictionary = res.get("refund", {})
	if refund.get("wood", 0) != 10 or refund.get("stone", 0) != 7 or refund.get("metal", 0) != 2:
		printerr("FAIL: Refund mismatch: expected {wood:10, stone:7, metal:2}, got: %s" % str(refund))
		failures += 1

	if failures == 0:
		print("  [PASS] TC-BM.14: 50% refund calculation accurately preflighted.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.15: Construction Cancellation Fail-Closed on Storage
# -----------------------------------------------------------------------------
func _test_tc_bm_15_cancel_fail_closed_storage() -> bool:
	print("--- Running TC-BM.15: Cancellation Fail-Closed on Storage Constraint ---")
	var failures: int = 0
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	var b_data := {
		"id": "cancel_fail_test",
		"type": "workshop",
		"cell": Vector2i(30, 30),
		"size": Vector2i(2, 2),
		"state": "under_construction"
	}

	# Fill wood storage to capacity
	var cap: int = rm.get_storage_capacity("wood")
	var cur: int = rm.get_total_stock("wood")
	rm.add_resource("wood", cap - cur)

	var res := BuildingSystemScript.can_cancel_construction(b_data, world_instance.world_data, rm)
	if res.get("can_cancel", true):
		printerr("FAIL: can_cancel_construction should fail closed when storage is full")
		failures += 1
	if not res.get("insufficient_storage", false):
		printerr("FAIL: insufficient_storage flag not set on rejection")
		failures += 1

	# Consume added wood back
	rm.consume_resource("wood", cap - cur)
	if failures == 0:
		print("  [PASS] TC-BM.15: Cancellation fails closed when storage cannot fit refund.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.16: Construction Cancellation Execution
# -----------------------------------------------------------------------------
func _test_tc_bm_16_cancel_execution() -> bool:
	print("--- Running TC-BM.16: Construction Cancellation Execution ---")
	var failures: int = 0
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	var init_wood = rm.get_total_stock("wood")

	# Find a clear 2x2 location on grass
	var target_cell := Vector2i(40, 40)
	var found_cell := false
	for cx in range(35, 55):
		for cy in range(35, 55):
			var occ = false
			for ox in range(2):
				for oy in range(2):
					if world_instance.world_data.occupancy[cx + ox][cy + oy]:
						occ = true
						break
				if occ: break
			if not occ:
				target_cell = Vector2i(cx, cy)
				found_cell = true
				break
		if found_cell: break

	# Place building site
	world_instance._on_build_requested("farm")
	var res_place: Dictionary = world_instance._execute_placement(target_cell)
	if not res_place.get("success", false):
		printerr("FAIL: Failed to execute building placement in TC-BM.16 at %s: %s" % [str(target_cell), res_place.get("reason", "")])
		return false
	var b_data: Dictionary = res_place.get("building", {})
	var b_id: String = b_data.get("id", "")

	# Select it in world view
	world_instance.select_building(b_data)

	var res = world_instance.cancel_construction_project(b_id)
	if not res.get("success", false):
		printerr("FAIL: cancel_construction_project failed: %s" % res.get("reason", ""))
		failures += 1

	# Check selection was cleared
	if world_instance.selected_building_id != "":
		printerr("FAIL: Selected building ID not cleared after cancellation")
		failures += 1

	# Check building removed from world data
	if not BuildingSystemScript.get_building_by_id(b_id, world_instance.world_data).is_empty():
		printerr("FAIL: Building still exists in world_data after cancellation")
		failures += 1

	if failures == 0:
		print("  [PASS] TC-BM.16: Construction cancellation execution verified.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.17: Demolition Preflight (50% Refund)
# -----------------------------------------------------------------------------
func _test_tc_bm_17_demolish_preflight() -> bool:
	print("--- Running TC-BM.17: Demolition Preflight (50% Refund) ---")
	var failures: int = 0
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	var b_data := {
		"id": "demolish_pre_test",
		"type": "farm", # cost: 15 Wood, 5 Stone
		"cell": Vector2i(30, 30),
		"size": Vector2i(2, 2),
		"state": "active"
	}
	world_instance.world_data.buildings.append(b_data)

	var res := BuildingSystemScript.can_demolish_building(b_data, world_instance.world_data, rm)
	if not res.get("can_demolish", false):
		printerr("FAIL: can_demolish_building returned false: %s" % res.get("reason", ""))
		failures += 1
	var refund: Dictionary = res.get("refund", {})
	if refund.get("wood", 0) != 15 or refund.get("stone", 0) != 2:
		printerr("FAIL: Expected refund {wood:15, stone:2}, got: %s" % str(refund))
		failures += 1

	# Fail-closed test with null resource_mgr (BUG-2F-03)
	var res_null := BuildingSystemScript.can_demolish_building(b_data, world_instance.world_data, null)
	if res_null.get("can_demolish", true):
		printerr("FAIL: can_demolish_building must return false when resource_mgr is null")
		failures += 1

	# Fail-closed test with invalid resource_mgr missing required methods
	var res_invalid := BuildingSystemScript.can_demolish_building(b_data, world_instance.world_data, RefCounted.new())
	if res_invalid.get("can_demolish", true):
		printerr("FAIL: can_demolish_building must return false when resource_mgr is invalid")
		failures += 1

	world_instance.world_data.buildings.erase(b_data)
	if failures == 0:
		print("  [PASS] TC-BM.17: Demolition 50% refund accurately preflighted.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.18: Demolition Preflight Storage Constraint (Storehouse Deduction)
# -----------------------------------------------------------------------------
func _test_tc_bm_18_demolish_storage_preflight() -> bool:
	print("--- Running TC-BM.18: Demolition Storage Capacity Preflight ---")
	var failures: int = 0
	var rm = world_instance.get_node_or_null("/root/ResourceManager")

	var b_data := {
		"id": "demolish_storehouse_test",
		"type": "storehouse", # cost: 25 Wood, 15 Stone. storage_bonus: 500 each
		"cell": Vector2i(30, 30),
		"size": Vector2i(2, 2),
		"state": "active"
	}
	world_instance.world_data.buildings.append(b_data)

	# Set wood stock such that current stock + refund exceeds post-demolition capacity (cap - 500)
	var cur_cap: int = rm.get_storage_capacity("wood")
	var post_cap: int = cur_cap - 500
	var cur_stock: int = rm.get_total_stock("wood")
	var added_wood: int = 0
	# Add stock up to post_cap
	if post_cap > cur_stock:
		added_wood = post_cap - cur_stock
		rm.add_resource("wood", added_wood)

	var res := BuildingSystemScript.can_demolish_building(b_data, world_instance.world_data, rm)
	if res.get("can_demolish", true):
		printerr("FAIL: Demolishing storehouse should fail closed when post-demolition space is less than refund")
		failures += 1
	if not res.get("insufficient_storage", false):
		printerr("FAIL: insufficient_storage flag expected on storehouse rejection")
		failures += 1

	if added_wood > 0:
		rm.consume_resource("wood", added_wood)
	world_instance.world_data.buildings.erase(b_data)
	if failures == 0:
		print("  [PASS] TC-BM.18: Post-demolition storage reduction preflight verified.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.19: Demolition Execution & Workforce/Resource Conservation
# -----------------------------------------------------------------------------
func _test_tc_bm_19_demolish_execution() -> bool:
	print("--- Running TC-BM.19: Demolition Execution ---")
	var failures: int = 0
	var rm = world_instance.get_node_or_null("/root/ResourceManager")

	# 1. Fail-closed: Demolition must fail without valid ResourceManager (BUG-2F-03)
	var fail_b := {
		"id": "bld_fail_null_rm",
		"type": "farm",
		"cell": Vector2i(22, 22),
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100
	}
	world_instance.world_data.buildings.append(fail_b)
	world_instance.world_data.occupancy[22][22] = true
	var res_null = BuildingSystemScript.demolish_building(fail_b, world_instance.world_data, null)
	if res_null.get("success", false):
		printerr("FAIL: demolish_building must fail closed when resource_mgr is null")
		failures += 1
	if BuildingSystemScript.get_building_by_id("bld_fail_null_rm", world_instance.world_data).is_empty():
		printerr("FAIL: Building was deleted despite null resource_mgr")
		failures += 1
	if not world_instance.world_data.occupancy[22][22]:
		printerr("FAIL: Occupancy was cleared despite null resource_mgr")
		failures += 1
	world_instance.world_data.buildings.erase(fail_b)
	world_instance.world_data.occupancy[22][22] = false

	# 2. Fail-closed: Demolition must fail with invalid ResourceManager missing methods
	world_instance.world_data.buildings.append(fail_b)
	var res_inv = BuildingSystemScript.demolish_building(fail_b, world_instance.world_data, RefCounted.new())
	if res_inv.get("success", false):
		printerr("FAIL: demolish_building must fail closed when resource_mgr is invalid")
		failures += 1
	world_instance.world_data.buildings.erase(fail_b)

	# 3. Successful execution: Workplace demolition & state clearance
	var origin := Vector2i(24, 24)
	var b_data := {
		"id": "demolish_exec_test",
		"type": "farm",
		"cell": origin,
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100
	}
	world_instance.world_data.buildings.append(b_data)
	world_instance.register_dynamic_workplace(b_data)
	world_instance._instantiate_building_node("farm", origin, Vector2i(2, 2), "active")
	world_instance.select_building(b_data)

	var res = world_instance.demolish_building_project("demolish_exec_test")
	if not res.get("success", false):
		printerr("FAIL: demolish_building_project failed: %s" % res.get("reason", ""))
		failures += 1
	if world_instance.selected_building_id != "":
		printerr("FAIL: Selected building not cleared after demolition")
		failures += 1
	if not BuildingSystemScript.get_building_by_id("demolish_exec_test", world_instance.world_data).is_empty():
		printerr("FAIL: Building was not removed from world_data")
		failures += 1

	# 4. Storage capacity decrement and existing stock conservation (BUG-2F-05)
	var initial_food_cap = rm.get_storage_capacity("food")
	var initial_ore_cap = rm.get_storage_capacity("ore")
	var b_store := {
		"id": "test_storehouse_cap_exec",
		"type": "storehouse",
		"cell": Vector2i(20, 20),
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100
	}
	world_instance.world_data.buildings.append(b_store)
	BuildingSystemScript.apply_completion_effects(b_store, rm)
	if rm.get_storage_capacity("food") != initial_food_cap + 500:
		printerr("FAIL: Storehouse did not increase food capacity by 500")
		failures += 1
	if rm.get_storage_capacity("ore") != initial_ore_cap + 300:
		printerr("FAIL: Storehouse did not increase ore capacity by 300")
		failures += 1

	# Fill food stock to full capacity before demolition
	var full_food_cap: int = rm.get_storage_capacity("food")
	var cur_food_stock: int = rm.get_total_stock("food")
	var added_fill: int = 0
	if full_food_cap > cur_food_stock:
		added_fill = full_food_cap - cur_food_stock
		rm.add_resource("food", added_fill)
	if rm.get_total_stock("food") != full_food_cap:
		printerr("FAIL: Food was not filled to capacity: %d != %d" % [rm.get_total_stock("food"), full_food_cap])
		failures += 1
	var stock_before_demolish = rm.get_total_stock("food")

	var res_store = world_instance.demolish_building_project("test_storehouse_cap_exec")
	if not res_store.get("success", false):
		printerr("FAIL: Failed to demolish storehouse: %s" % res_store.get("reason", ""))
		failures += 1
	if rm.get_storage_capacity("food") != initial_food_cap:
		printerr("FAIL: Food capacity did not decrease by 500 upon storehouse demolition")
		failures += 1
	if rm.get_storage_capacity("ore") != initial_ore_cap:
		printerr("FAIL: Ore capacity did not decrease by 300 upon storehouse demolition")
		failures += 1
	if rm.get_total_stock("food") != stock_before_demolish:
		printerr("FAIL: Existing stock was silently deleted/clamped on capacity reduction! %d != %d" % [rm.get_total_stock("food"), stock_before_demolish])
		failures += 1
	# Stock now exceeds the new capacity: verify further additions are strictly rejected
	var rejected_add: int = rm.add_resource("food", 50)
	if rejected_add != 0:
		printerr("FAIL: Adding food should be rejected when stock exceeds capacity, got: %d" % rejected_add)
		failures += 1

	# Clean up excess food so later tests have clean headroom
	if added_fill > 0:
		rm.consume_resource("food", added_fill)

	# 5. Worker and hauling cargo cleanup without inventory loss (BUG-2F-06)
	var cit_hauler = world_instance.citizen_list[1]
	cit_hauler.role = "hauler"
	cit_hauler.set("carrying_amount", 10)
	cit_hauler.set("carrying_resource", "wood")
	var hauler_job = JobData.new()
	hauler_job.id = "hauler_demolish_test_job"
	hauler_job.type = "hauler"
	hauler_job.target_building_id = "demolish_cargo_bld"
	cit_hauler.active_job = hauler_job

	var b_cargo := {
		"id": "demolish_cargo_bld",
		"type": "farm",
		"cell": Vector2i(26, 26),
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100
	}
	world_instance.world_data.buildings.append(b_cargo)
	var wood_before = rm.get_total_stock("wood")
	world_instance.demolish_building_project("demolish_cargo_bld")
	var wood_after = rm.get_total_stock("wood")

	# +10 wood from carried cargo deposit + 15 wood from 50% farm refund = +25 wood
	if wood_after < wood_before + 25:
		printerr("FAIL: Carried cargo (+10) was not deposited into storage on demolition! %d -> %d" % [wood_before, wood_after])
		failures += 1
	if cit_hauler.get("carrying_amount") != 0:
		printerr("FAIL: Hauler cargo was not cleared after demolition deposit")
		failures += 1
	if cit_hauler.get("status_reason") != "Công trình đã bị dỡ bỏ":
		printerr("FAIL: Hauler status reason mismatch: '%s'" % cit_hauler.get("status_reason"))
		failures += 1

	if failures == 0:
		print("  [PASS] TC-BM.19: Demolition execution atomically removed building and cleared state.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.20: Workplace Unregistration on Demolition
# -----------------------------------------------------------------------------
func _test_tc_bm_20_workplace_unregistration() -> bool:
	print("--- Running TC-BM.20: Workplace Unregistration on Demolition ---")
	var failures: int = 0
	var origin := Vector2i(24, 24)
	var b_data := {
		"id": "unreg_wp_test",
		"type": "quarry",
		"cell": origin,
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100
	}
	world_instance.world_data.buildings.append(b_data)
	world_instance.register_dynamic_workplace(b_data)

	if world_instance.workplace_mgr.get_workplace("unreg_wp_test") == null:
		printerr("FAIL: Workplace not registered before test")
		return false

	world_instance.demolish_building_project("unreg_wp_test")

	if world_instance.workplace_mgr.get_workplace("unreg_wp_test") != null:
		printerr("FAIL: Workplace still registered in WorkplaceManager after demolition")
		failures += 1

	if failures == 0:
		print("  [PASS] TC-BM.20: Workplace cleanly unregistered upon demolition.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.21: Town Hall Warning on Demolition
# -----------------------------------------------------------------------------
func _test_tc_bm_21_townhall_warning() -> bool:
	print("--- Running TC-BM.21: Town Hall Demolition Warning ---")
	var failures: int = 0
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	var b_data := {
		"id": "th_warn_test",
		"type": "townhall",
		"cell": Vector2i(10, 10),
		"size": Vector2i(3, 3),
		"state": "active"
	}
	world_instance.world_data.buildings.append(b_data)

	var check := BuildingSystemScript.can_demolish_building(b_data, world_instance.world_data, rm)
	if not check.get("is_townhall", false):
		printerr("FAIL: is_townhall flag must be true for townhall preflight")
		failures += 1

	world_instance.world_data.buildings.erase(b_data)
	if failures == 0:
		print("  [PASS] TC-BM.21: Town Hall demolition correctly triggers emergency warning flag.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.22: Town Hall Collapse Grace Period & Pause Rejection
# -----------------------------------------------------------------------------
func _test_tc_bm_22_townhall_collapse_grace() -> bool:
	print("--- Running TC-BM.22: Town Hall 72h Grace Period & Collapse Trigger ---")
	var failures: int = 0

	# 1. Pausing Town Hall must be rejected fail-closed (BUG-2F-02)
	var pause_th_res = world_instance.set_building_state("townhall_starter", "paused")
	if pause_th_res:
		printerr("FAIL: set_building_state must refuse pausing Town Hall!")
		failures += 1
	var th_bld = BuildingSystemScript.get_building_by_id("townhall_starter", world_instance.world_data)
	if th_bld.get("state") != "active":
		printerr("FAIL: Town Hall state was altered to '%s'" % th_bld.get("state"))
		failures += 1
	if not BuildingSystemScript.is_town_hall_active(world_instance.world_data):
		printerr("FAIL: is_town_hall_active must remain true!")
		failures += 1
	if world_instance.victory_mgr.townhall_ruin_hours > 0.0:
		printerr("FAIL: Town Hall loss countdown was triggered by pause attempt!")
		failures += 1

	# Verify pausing civic structures (House, Storehouse, Barracks, Market) is also rejected
	var mock_civics := [
		{"id": "mock_house", "type": "house"},
		{"id": "storehouse_starter", "type": "storehouse"},
		{"id": "mock_barracks", "type": "barracks"},
		{"id": "mock_market", "type": "market"}
	]
	for c in mock_civics:
		world_instance.world_data.buildings.append({"id": c["id"], "type": c["type"], "cell": Vector2i(1, 1), "size": Vector2i(2, 2), "state": "active", "health": 100})
		var p_res = world_instance.set_building_state(c["id"], "paused")
		if p_res:
			printerr("FAIL: Non-workplace building '%s' was permitted to pause!" % c["type"])
			failures += 1
		world_instance.world_data.buildings.erase(BuildingSystemScript.get_building_by_id(c["id"], world_instance.world_data))

	# 2. Actual Town Hall demolition through WorldView integration (BUG-2F-07)
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	if rm != null:
		var free_wood = rm.get_storage_capacity("wood") - rm.get_total_stock("wood")
		if free_wood < 50:
			rm.consume_resource("wood", 50 - free_wood)
		var free_stone = rm.get_storage_capacity("stone") - rm.get_total_stock("stone")
		if free_stone < 50:
			rm.consume_resource("stone", 50 - free_stone)

	var th_origin: Vector2i = th_bld.get("cell", Vector2i(30, 30))
	var res_demolish = world_instance.demolish_building_project("townhall_starter")
	if not res_demolish.get("success", false):
		printerr("FAIL: Failed to demolish townhall_starter: %s" % res_demolish.get("reason", ""))
		failures += 1
	if BuildingSystemScript.is_town_hall_active(world_instance.world_data):
		printerr("FAIL: is_town_hall_active should be false after Town Hall demolition")
		failures += 1

	# Hourly simulation tick detects missing capital and initiates 72h countdown
	world_instance._on_simulation_hour_passed(1, 1)
	if world_instance.victory_mgr.townhall_ruin_hours <= 0.0:
		printerr("FAIL: VictoryManager did not start town hall lost countdown after demolition")
		failures += 1
	if world_instance.victory_mgr.townhall_ruin_hours != 1.0:
		printerr("FAIL: Countdown hours mismatch: %f" % world_instance.victory_mgr.townhall_ruin_hours)
		failures += 1

	# Reconstructing/Restoring Town Hall cancels countdown
	var restored_th := {
		"id": "townhall_starter",
		"type": "townhall",
		"cell": th_origin,
		"size": Vector2i(3, 3),
		"state": "active",
		"health": 100,
		"storage_applied": true
	}
	world_instance.world_data.buildings.append(restored_th)
	world_instance._on_simulation_hour_passed(2, 1)
	if world_instance.victory_mgr.townhall_ruin_hours != 0.0:
		printerr("FAIL: Countdown was not cancelled after Town Hall was restored")
		failures += 1

	# 3. Verify complete 72-hour grace period and terminal collapse through real WorldView integration
	world_instance.world_data.buildings.erase(restored_th)
	world_instance.victory_mgr.townhall_ruin_hours = 0.0
	world_instance.victory_mgr.is_collapse_triggered = false

	for h in range(1, 72): # Hours 1 to 71
		var cur_sim_hour: int = h % 24
		var cur_sim_day: int = int(float(h) / 24.0) + 1
		world_instance._on_simulation_hour_passed(cur_sim_hour, cur_sim_day)
		if world_instance.victory_mgr.is_collapse_triggered:
			printerr("FAIL: Collapse prematurely triggered at hour %d (< 72) in live WorldView" % h)
			failures += 1
		if world_instance.victory_mgr.townhall_ruin_hours != float(h):
			printerr("FAIL: Hourly townhall_ruin_hours mismatch at hour %d: got %f" % [h, world_instance.victory_mgr.townhall_ruin_hours])
			failures += 1

	# Hour 72: triggers collapse
	world_instance._on_simulation_hour_passed(0, 4)
	if not world_instance.victory_mgr.is_collapse_triggered:
		printerr("FAIL: Terminal collapse was not triggered at hour 72 in live WorldView")
		failures += 1
	if not "Mất thủ đô" in world_instance.victory_mgr.primary_collapse_reason:
		printerr("FAIL: Reason must indicate lost capital: '%s'" % world_instance.victory_mgr.primary_collapse_reason)
		failures += 1

	# Clean up and restore complete Town Hall world fixture for subsequent tests
	restored_th["storage_applied"] = false
	BuildingSystemScript.apply_completion_effects(restored_th, rm)
	world_instance.world_data.buildings.append(restored_th)
	for ox in range(3):
		for oy in range(3):
			var cell := th_origin + Vector2i(ox, oy)
			if IsoMathScript.is_in_bounds(cell):
				world_instance.world_data.occupancy[cell.x][cell.y] = true
	world_instance._instantiate_building_node("townhall", th_origin, Vector2i(3, 3), "active")
	world_instance.victory_mgr.townhall_ruin_hours = 0.0
	world_instance.victory_mgr.is_collapse_triggered = false
	world_instance.victory_mgr.primary_collapse_reason = ""
	world_instance._on_simulation_hour_passed(1, 5)

	if not BuildingSystemScript.is_town_hall_active(world_instance.world_data):
		printerr("FAIL: Town Hall fixture was not cleanly restored")
		failures += 1
	if world_instance.victory_mgr.townhall_ruin_hours != 0.0:
		printerr("FAIL: Town Hall ruin hours not reset on cleanup")
		failures += 1

	if failures == 0:
		print("  [PASS] TC-BM.22: 72h Town Hall emergency collapse countdown verified.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.23: Operational Pause Lifecycle
# -----------------------------------------------------------------------------
func _test_tc_bm_23_pause_lifecycle() -> bool:
	print("--- Running TC-BM.23: Operational Pause & Resume Lifecycle ---")
	var failures: int = 0
	var origin := Vector2i(28, 28)
	var b_data := {
		"id": "bld_pause_lifecycle",
		"type": "farm",
		"cell": origin,
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100
	}
	world_instance.world_data.buildings.append(b_data)
	world_instance.register_dynamic_workplace(b_data)

	# 1. Pause
	world_instance.set_building_state("bld_pause_lifecycle", "paused")
	if not BuildingSystemScript.is_building_paused_by_id("bld_pause_lifecycle", world_instance.world_data):
		printerr("FAIL: BuildingSystem.is_building_paused_by_id returned false after pause")
		failures += 1
	if not world_instance.workplace_mgr.is_workplace_paused("bld_pause_lifecycle"):
		printerr("FAIL: WorkplaceManager is_workplace_paused returned false after pause")
		failures += 1

	# 2. Resume
	world_instance.set_building_state("bld_pause_lifecycle", "active")
	if not BuildingSystemScript.is_building_active_by_id("bld_pause_lifecycle", world_instance.world_data):
		printerr("FAIL: BuildingSystem.is_building_active_by_id returned false after resume")
		failures += 1
	if world_instance.workplace_mgr.is_workplace_paused("bld_pause_lifecycle"):
		printerr("FAIL: WorkplaceManager is_workplace_paused returned true after resume")
		failures += 1

	world_instance.workplace_mgr.unregister_workplace("bld_pause_lifecycle")
	world_instance.world_data.buildings.erase(b_data)
	if failures == 0:
		print("  [PASS] TC-BM.23: Pause/Resume lifecycle verified across subsystems.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.24: Production Halted When Paused
# -----------------------------------------------------------------------------
func _test_tc_bm_24_pause_halts_production() -> bool:
	print("--- Running TC-BM.24: Production Halted When Workplace is Paused ---")
	var failures: int = 0
	var wp_mgr = world_instance.workplace_mgr
	var wp = wp_mgr.get_workplace("farm_starter")
	wp.buffer_amount = 5

	# Pause workplace
	wp_mgr.set_workplace_paused("farm_starter", true)

	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	var produced: int = wp_mgr.produce_to_buffer("farm_starter", 1.0, rm)
	if produced != 0:
		printerr("FAIL: produce_to_buffer should produce 0 when workplace is paused, got: %d" % produced)
		failures += 1
	if wp.buffer_amount != 5:
		printerr("FAIL: Buffer amount should remain strictly unchanged when paused: %d" % wp.buffer_amount)
		failures += 1

	# Unpause
	wp_mgr.set_workplace_paused("farm_starter", false)
	wp.buffer_amount = 0

	if failures == 0:
		print("  [PASS] TC-BM.24: Production strictly suspended while workplace is paused.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.25: Workers Released to IDLE on Pause
# -----------------------------------------------------------------------------
func _test_tc_bm_25_pause_releases_workers() -> bool:
	print("--- Running TC-BM.25: Workers Safely Released to IDLE on Pause ---")
	var failures: int = 0
	var cit = world_instance.citizen_list[0]
	var job = JobData.new()
	job.id = "pause_rel_job"
	job.type = "farmer"
	job.target_building_id = "farm_starter"
	cit.active_job = job
	cit.current_state = 3 # State.WORKING

	world_instance.set_building_state("farm_starter", "paused")

	if cit.active_job != null:
		printerr("FAIL: Active job not released on pause")
		failures += 1
	if cit.current_state != 0: # State.IDLE
		printerr("FAIL: Citizen state not reset to IDLE on pause: %d" % cit.current_state)
		failures += 1
	if not "tạm dừng" in cit.status_reason:
		printerr("FAIL: Status reason missing pause notice: '%s'" % cit.status_reason)
		failures += 1

	world_instance.set_building_state("farm_starter", "active")
	if failures == 0:
		print("  [PASS] TC-BM.25: Workers cleanly released to IDLE with pause reason.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.26: Idle Workers Refuse Paused Building Jobs
# -----------------------------------------------------------------------------
func _test_tc_bm_26_pause_refuses_new_workers() -> bool:
	print("--- Running TC-BM.26: Idle Workers Refuse Paused Workplace Jobs ---")
	var failures: int = 0
	var jm = world_instance.job_mgr
	var wp_mgr = world_instance.workplace_mgr
	var rm = world_instance.get_node_or_null("/root/ResourceManager")

	var job = JobData.new()
	job.id = "paused_exec_job"
	job.type = "farmer"
	job.target_building_id = "farm_starter"
	job.workplace_channel_id = "farm_starter"

	# When active: executable
	wp_mgr.set_workplace_paused("farm_starter", false)
	if not jm._is_job_executable(job, wp_mgr, rm, Callable(), world_instance.nav):
		printerr("FAIL: Job should be executable when workplace is active")
		failures += 1

	# When paused: not executable
	wp_mgr.set_workplace_paused("farm_starter", true)
	if jm._is_job_executable(job, wp_mgr, rm, Callable(), world_instance.nav):
		printerr("FAIL: Job must NOT be executable when workplace is paused")
		failures += 1

	wp_mgr.set_workplace_paused("farm_starter", false)
	if failures == 0:
		print("  [PASS] TC-BM.26: Paused workplaces fail closed during job request check.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.27: Hauler Jobs Remain Executable for Paused Workplaces
# -----------------------------------------------------------------------------
func _test_tc_bm_27_pause_allows_hauling() -> bool:
	print("--- Running TC-BM.27: Hauler Jobs Remain Executable for Paused Workplaces ---")
	var failures: int = 0
	var jm = world_instance.job_mgr
	var wp_mgr = world_instance.workplace_mgr
	var rm = world_instance.get_node_or_null("/root/ResourceManager")

	wp_mgr.set_workplace_paused("farm_starter", true)

	var haul_job = JobData.new()
	haul_job.id = "haul_paused_wp_job"
	haul_job.type = "hauler"
	haul_job.target_building_id = "farm_starter"
	haul_job.source_workplace_id = "farm_starter"

	if not jm._is_job_executable(haul_job, wp_mgr, rm, Callable(), world_instance.nav):
		printerr("FAIL: Hauler job must remain executable for paused workplace to empty buffer")
		failures += 1

	wp_mgr.set_workplace_paused("farm_starter", false)
	if failures == 0:
		print("  [PASS] TC-BM.27: Haulers successfully permitted to clear paused buffers.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.28: Resuming Restores Normal Operations
# -----------------------------------------------------------------------------
func _test_tc_bm_28_resume_restores_operations() -> bool:
	print("--- Running TC-BM.28: Resuming Paused Workplace Restores Operations ---")
	var failures: int = 0
	var jm = world_instance.job_mgr
	var wp_mgr = world_instance.workplace_mgr
	var rm = world_instance.get_node_or_null("/root/ResourceManager")

	var job = JobData.new()
	job.id = "resume_test_job"
	job.type = "woodcutter"
	job.target_building_id = "woodcutter_starter"

	world_instance.set_building_state("woodcutter_starter", "paused")
	if jm._is_job_executable(job, wp_mgr, rm, Callable(), world_instance.nav):
		printerr("FAIL: Job was executable while paused")
		failures += 1

	world_instance.set_building_state("woodcutter_starter", "active")
	if not jm._is_job_executable(job, wp_mgr, rm, Callable(), world_instance.nav):
		printerr("FAIL: Job was not executable after resume")
		failures += 1

	if failures == 0:
		print("  [PASS] TC-BM.28: Resuming building restores job executability.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.29: Save/Load Persistence of Paused State (Real Disk Roundtrip)
# -----------------------------------------------------------------------------
func _test_tc_bm_29_save_load_persistence() -> bool:
	print("--- Running TC-BM.29: Save/Load Persistence of Paused Buildings ---")
	var failures: int = 0
	var temp_save_path := "user://test_save_p2f_temp.json"
	var origin := Vector2i(26, 26)
	var b_data := {
		"id": "bld_save_pause_test",
		"type": "farm",
		"cell": origin,
		"size": Vector2i(2, 2),
		"state": "paused",
		"health": 100
	}
	world_instance.world_data.buildings.append(b_data)
	world_instance.register_dynamic_workplace(b_data)
	world_instance.workplace_mgr.set_workplace_paused("bld_save_pause_test", true)
	var wp = world_instance.workplace_mgr.get_workplace("bld_save_pause_test")
	if wp != null:
		wp.buffer_amount = 17

	# 1. Real save to disk at isolated temporary path
	var save_res := SaveManagerScript.save_to_file(world_instance, temp_save_path)
	if not save_res.get("success", false):
		printerr("FAIL: Temporary file save failed: %s" % save_res.get("error", ""))
		failures += 1

	# Mutate live memory before loading to confirm loaded data actually overwrites state
	wp.buffer_amount = 0
	world_instance.workplace_mgr.set_workplace_paused("bld_save_pause_test", false)
	b_data["state"] = "active"

	# 2. Real load from disk
	var load_res := SaveManagerScript.load_from_file(temp_save_path)
	if not load_res.get("success", false):
		printerr("FAIL: Temporary file load failed: %s" % load_res.get("error", ""))
		failures += 1

	var apply_res := SaveManagerScript.apply_loaded_state_to_world(world_instance, load_res["data"])
	if not apply_res.get("success", false):
		printerr("FAIL: Applying loaded state failed: %s" % apply_res.get("error", ""))
		failures += 1

	# 3. Verify paused building state and workplace pause are restored
	var loaded_b := BuildingSystemScript.get_building_by_id("bld_save_pause_test", world_instance.world_data)
	if loaded_b.get("state") != "paused":
		printerr("FAIL: Building state was not restored to 'paused', got '%s'" % loaded_b.get("state"))
		failures += 1

	if not world_instance.workplace_mgr.is_workplace_paused("bld_save_pause_test"):
		printerr("FAIL: WorkplaceManager is_workplace_paused was not restored to true")
		failures += 1

	var restored_wp = world_instance.workplace_mgr.get_workplace("bld_save_pause_test")
	if restored_wp == null or restored_wp.buffer_amount != 17:
		printerr("FAIL: Workplace buffer amount was not restored to 17, got %d" % (restored_wp.buffer_amount if restored_wp else -1))
		failures += 1

	# 4. Verify no jobs execute while paused
	var jm = world_instance.job_mgr
	var wp_mgr = world_instance.workplace_mgr
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	var jobs = jm.get_jobs_for_building("bld_save_pause_test")
	for j in jobs:
		if j.type != "hauler" and jm._is_job_executable(j, wp_mgr, rm, Callable(), world_instance.nav):
			printerr("FAIL: Job '%s' should not be executable while workplace is paused" % j.id)
			failures += 1

	# 5. Verify resume works cleanly after load
	var resume_ok = world_instance.set_building_state("bld_save_pause_test", "active")
	if not resume_ok:
		printerr("FAIL: Failed to resume paused workplace after load")
		failures += 1
	if world_instance.workplace_mgr.is_workplace_paused("bld_save_pause_test"):
		printerr("FAIL: Workplace still paused after resume")
		failures += 1

	# 6. Clean up temporary save file and test building
	if FileAccess.file_exists(temp_save_path):
		DirAccess.remove_absolute(temp_save_path)
	if FileAccess.file_exists(temp_save_path + ".bak"):
		DirAccess.remove_absolute(temp_save_path + ".bak")
	if FileAccess.file_exists(temp_save_path + ".bak.old"):
		DirAccess.remove_absolute(temp_save_path + ".bak.old")
	world_instance.demolish_building_project("bld_save_pause_test")

	if failures == 0:
		print("  [PASS] TC-BM.29: Paused state survives save/load serialization.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.30: Escape Key Hierarchy & UI Dismissal
# -----------------------------------------------------------------------------
func _test_tc_bm_30_escape_key_hierarchy() -> bool:
	print("--- Running TC-BM.30: Escape Key Dismissal Hierarchy ---")
	var failures: int = 0
	var hud = world_instance.hud

	# 1. Overlay open -> Escape closes overlay first, keeps panel open
	hud.show_building_inspector({"id": "farm_starter", "type": "farm", "cell": Vector2i(36, 35), "size": Vector2i(2, 2), "state": "active"})
	hud.demolish_confirm_overlay.visible = true

	var esc_event := InputEventKey.new()
	esc_event.pressed = true
	esc_event.keycode = KEY_ESCAPE

	hud._unhandled_input(esc_event)
	if hud.demolish_confirm_overlay.visible:
		printerr("FAIL: Demolish confirm overlay not closed by Escape")
		failures += 1
	if not hud.building_inspect_panel.visible:
		printerr("FAIL: Building panel should remain open when overlay is closed")
		failures += 1

	# 2. Second Escape -> closes building inspector
	hud._unhandled_input(esc_event)
	if hud.building_inspect_panel.visible:
		printerr("FAIL: Building inspect panel not closed by second Escape")
		failures += 1

	if failures == 0:
		print("  [PASS] TC-BM.30: Escape key hierarchy gracefully dismisses overlays then panels.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.31: Workshop Dual-Channel Pause/Resume Integration Coverage
# -----------------------------------------------------------------------------
func _test_tc_bm_31_workshop_pause_channels() -> bool:
	print("--- Running TC-BM.31: Workshop Dual-Channel Pause/Resume Integration ---")
	var failures: int = 0
	var jm = world_instance.job_mgr
	var wp_mgr = world_instance.workplace_mgr
	var rm = world_instance.get_node_or_null("/root/ResourceManager")

	# Setup workshop test fixture
	var origin := Vector2i(28, 28)
	var b_data := {
		"id": "workshop_test_pause",
		"type": "workshop",
		"cell": origin,
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100
	}
	world_instance.world_data.buildings.append(b_data)
	world_instance.register_dynamic_workplace(b_data)

	var smelt_wp = wp_mgr.get_workplace("workshop_test_pause_smelt")
	var craft_wp = wp_mgr.get_workplace("workshop_test_pause_craft")
	if smelt_wp == null or craft_wp == null:
		printerr("FAIL: Both workshop channels must exist on registration")
		return false

	smelt_wp.buffer_amount = 6
	craft_wp.buffer_amount = 4

	# Setup jobs
	var job_smelt = JobData.new()
	job_smelt.id = "smelt_test_job"
	job_smelt.type = "smith"
	job_smelt.recipe_id = "smelt_metal"
	job_smelt.target_building_id = "workshop_test_pause"
	job_smelt.workplace_channel_id = "workshop_test_pause_smelt"

	var job_craft = JobData.new()
	job_craft.id = "craft_test_job"
	job_craft.type = "smith"
	job_craft.recipe_id = "craft_tools"
	job_craft.target_building_id = "workshop_test_pause"
	job_craft.workplace_channel_id = "workshop_test_pause_craft"

	var job_haul = JobData.new()
	job_haul.id = "haul_test_job"
	job_haul.type = "hauler"
	job_haul.target_building_id = "workshop_test_pause"
	job_haul.source_workplace_id = "workshop_test_pause_smelt"

	# Provide crafting materials for input check
	rm.add_resource("ore", 10)
	rm.add_resource("metal", 10)
	rm.add_resource("wood", 10)

	# 1. Active: jobs are executable
	if not jm._is_job_executable(job_smelt, wp_mgr, rm, Callable(), world_instance.nav):
		printerr("FAIL: Smelt job should be executable when workshop is active")
		failures += 1
	if not jm._is_job_executable(job_craft, wp_mgr, rm, Callable(), world_instance.nav):
		printerr("FAIL: Craft job should be executable when workshop is active")
		failures += 1

	# Assign workers to both channels
	var cit0 = world_instance.citizen_list[0]
	var cit1 = world_instance.citizen_list[1] if world_instance.citizen_list.size() > 1 else null
	cit0.active_job = job_smelt
	cit0.current_state = CitizenController.State.WORKING
	if cit1 != null:
		cit1.active_job = job_craft
		cit1.current_state = CitizenController.State.WORKING

	# 2. Parent pause: both channels paused, buffers unchanged, workers safely released to IDLE
	world_instance.set_building_state("workshop_test_pause", "paused")
	if not wp_mgr.is_workplace_paused("workshop_test_pause_smelt") or not wp_mgr.is_workplace_paused("workshop_test_pause_craft"):
		printerr("FAIL: Both workshop sub-channels must be paused")
		failures += 1

	if smelt_wp.buffer_amount != 6 or craft_wp.buffer_amount != 4:
		printerr("FAIL: Buffers must remain unchanged while paused")
		failures += 1

	if cit0.current_state != CitizenController.State.IDLE or cit0.active_job != null:
		printerr("FAIL: Active smith worker cit0 not released to IDLE on pause")
		failures += 1
	if cit1 != null and (cit1.current_state != CitizenController.State.IDLE or cit1.active_job != null):
		printerr("FAIL: Active smith worker cit1 not released to IDLE on pause")
		failures += 1

	# Smith jobs non-executable while paused, hauler jobs remain executable
	if jm._is_job_executable(job_smelt, wp_mgr, rm, Callable(), world_instance.nav):
		printerr("FAIL: Smelt job should NOT be executable when paused")
		failures += 1
	if jm._is_job_executable(job_craft, wp_mgr, rm, Callable(), world_instance.nav):
		printerr("FAIL: Craft job should NOT be executable when paused")
		failures += 1
	if not jm._is_job_executable(job_haul, wp_mgr, rm, Callable(), world_instance.nav):
		printerr("FAIL: Hauler job should remain executable for paused workshop channel")
		failures += 1

	# 3. Save/Load roundtrip preserving paused state and both channel buffers
	var temp_save_path := "user://test_workshop_pause_save.json"
	var s_res = SaveManagerScript.save_to_file(world_instance, temp_save_path)
	if not s_res.get("success", false):
		printerr("FAIL: Save failed during workshop pause test")
		failures += 1
	var l_res = SaveManagerScript.load_from_file(temp_save_path)
	if not l_res.get("success", false):
		printerr("FAIL: Load failed during workshop pause test")
		failures += 1
	var a_res = SaveManagerScript.apply_loaded_state_to_world(world_instance, l_res["data"])
	if not a_res.get("success", false):
		printerr("FAIL: Apply loaded state failed during workshop pause test")
		failures += 1

	if FileAccess.file_exists(temp_save_path):
		DirAccess.remove_absolute(temp_save_path)
	if FileAccess.file_exists(temp_save_path + ".bak"):
		DirAccess.remove_absolute(temp_save_path + ".bak")

	# Re-fetch managers after load
	wp_mgr = world_instance.workplace_mgr
	jm = world_instance.job_mgr
	rm = world_instance.get_node_or_null("/root/ResourceManager")

	if not BuildingSystemScript.is_building_paused_by_id("workshop_test_pause", world_instance.world_data):
		printerr("FAIL: Workshop should remain paused after load")
		failures += 1
	if not wp_mgr.is_workplace_paused("workshop_test_pause_smelt") or not wp_mgr.is_workplace_paused("workshop_test_pause_craft"):
		printerr("FAIL: Workshop sub-channels should remain paused after load")
		failures += 1

	var smelt_wp_loaded = wp_mgr.get_workplace("workshop_test_pause_smelt")
	var craft_wp_loaded = wp_mgr.get_workplace("workshop_test_pause_craft")
	if smelt_wp_loaded == null or craft_wp_loaded == null:
		printerr("FAIL: Channels missing after load")
		failures += 1
	elif smelt_wp_loaded.buffer_amount != 6 or craft_wp_loaded.buffer_amount != 4:
		printerr("FAIL: Buffer amounts not preserved across save/load! Smelt: %d, Craft: %d" % [smelt_wp_loaded.buffer_amount, craft_wp_loaded.buffer_amount])
		failures += 1

	# 4. Resume after load: both channels active again, no duplicate channels
	world_instance.set_building_state("workshop_test_pause", "active")
	if not BuildingSystemScript.is_building_active_by_id("workshop_test_pause", world_instance.world_data):
		printerr("FAIL: Workshop should be active after resume")
		failures += 1
	if wp_mgr.is_workplace_paused("workshop_test_pause_smelt") or wp_mgr.is_workplace_paused("workshop_test_pause_craft"):
		printerr("FAIL: Workshop sub-channels should not be paused after resume")
		failures += 1

	if not jm._is_job_executable(job_smelt, wp_mgr, rm, Callable(), world_instance.nav):
		printerr("FAIL: Smelt job should be executable after resume")
		failures += 1
	if not jm._is_job_executable(job_craft, wp_mgr, rm, Callable(), world_instance.nav):
		printerr("FAIL: Craft job should be executable after resume")
		failures += 1

	rm.consume_resource("ore", 10)
	rm.consume_resource("metal", 10)
	rm.consume_resource("wood", 10)

	# Cleanup
	world_instance.demolish_building_project("workshop_test_pause")

	if failures == 0:
		print("  [PASS] TC-BM.31: Dual-channel workshop pause/resume lifecycle & save/load verified.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.32: Atomic Demolition Refund Failure-Injection & Rollback
# -----------------------------------------------------------------------------
class FailingRollbackRM extends RefCounted:
	var _current_stock: Dictionary = {"wood": 100, "stone": 100, "food": 0}
	var _daily_production_tallies: Dictionary = {"wood": 0.0, "stone": 0.0, "food": 0.0}
	var _capacities: Dictionary = {"wood": 1000, "stone": 1000, "food": 1000}
	var _is_starving: bool = true
	var rollback_called: bool = false
	var rolled_back_credited: Dictionary = {}
	var restored_starving: Variant = null

	func get_resource(res_id: String) -> int:
		return _current_stock.get(res_id, 0)

	func get_total_stock(res_id: String) -> int:
		return _current_stock.get(res_id, 0)

	func get_storage_capacity(res_id: String) -> int:
		return _capacities.get(res_id, 1000)

	func get_capacity(res_id: String) -> int:
		return _capacities.get(res_id, 1000)

	func is_starving() -> bool:
		return _is_starving

	func get_daily_production_tally(res_id: String) -> float:
		return _daily_production_tallies.get(res_id, 0.0)

	func remove_storage_capacity(_res_id: String, _bonus: int) -> void:
		pass

	func add_resources_atomic(resources: Dictionary) -> Dictionary:
		var prev_starving: bool = _is_starving
		var credited: Dictionary = {}

		# Simulate partial stock mutation: first resource succeeds, subsequent resource fails
		var idx: int = 0
		for res_id in resources:
			var amt: int = int(resources[res_id])
			if idx == 0:
				_current_stock[res_id] = _current_stock.get(res_id, 0) + amt
				_daily_production_tallies[res_id] = _daily_production_tallies.get(res_id, 0.0) + float(amt)
				_is_starving = false
				credited[res_id] = amt
			else:
				# Failure injection: trigger rollback
				rollback_added_resources(credited, prev_starving)
				return {
					"success": false,
					"reason": "Injected transaction failure on %s" % res_id,
					"credited": {}
				}
			idx += 1

		return {"success": true, "credited": credited}

	func rollback_added_resources(credited: Dictionary, restore_starving: Variant = null) -> void:
		rollback_called = true
		rolled_back_credited = credited.duplicate(true)
		restored_starving = restore_starving
		for res_id in credited:
			var amt: int = int(credited[res_id])
			_current_stock[res_id] = maxi(0, _current_stock.get(res_id, 0) - amt)
			_daily_production_tallies[res_id] = maxf(0.0, _daily_production_tallies.get(res_id, 0.0) - float(amt))
		if restore_starving != null:
			_is_starving = bool(restore_starving)

func _test_tc_bm_32_atomic_refund_failure_injection() -> bool:
	print("--- Running TC-BM.32: Atomic Demolition Refund Failure-Injection ---")
	var failures: int = 0
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	var wd = world_instance.world_data

	# 1. Test production ResourceManager.add_resources_atomic rollback directly
	var initial_wood = rm.get_resource("wood")
	var initial_stone = rm.get_resource("stone")
	var stone_cap = rm.get_capacity("stone")

	# Set stone stock near cap so it will reject in preflight
	rm._current_stock["stone"] = stone_cap - 5 # only 5 stone headroom

	# Try atomic transaction requiring 50 wood and 20 stone
	var batch := {"wood": 50, "stone": 20}
	var res = rm.add_resources_atomic(batch)
	if res.get("success", false):
		printerr("FAIL: add_resources_atomic should fail when headroom is insufficient")
		failures += 1

	if rm.get_resource("wood") != initial_wood:
		printerr("FAIL: Wood was not rolled back after atomic failure! Got %d, expected %d" % [rm.get_resource("wood"), initial_wood])
		failures += 1
	if rm.get_resource("stone") != stone_cap - 5:
		printerr("FAIL: Stone was not rolled back after atomic failure! Got %d, expected %d" % [rm.get_resource("stone"), stone_cap - 5])
		failures += 1

	# Restore stone
	rm._current_stock["stone"] = initial_stone

	# 2. Test BuildingSystem.demolish_building failure injection via FailingRollbackRM
	var b_data := {
		"id": "bld_atomic_fail_test",
		"type": "farm",
		"cell": Vector2i(22, 22),
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100
	}
	wd.buildings.append(b_data)
	for ox in range(2):
		for oy in range(2):
			var cell = Vector2i(22, 22) + Vector2i(ox, oy)
			if IsoMathScript.is_in_bounds(cell):
				wd.occupancy[cell.x][cell.y] = true

	# Register a mock job for this building to verify job preservation
	var test_job: JobData = null
	if world_instance.job_mgr != null:
		test_job = world_instance.job_mgr.create_job("farmer", Vector2i(22, 22), "Farm labor", "bld_atomic_fail_test")

	var failing_rm = FailingRollbackRM.new()
	var dem_res = BuildingSystemScript.demolish_building(b_data, wd, failing_rm, world_instance.job_mgr)

	if dem_res.get("success", true):
		printerr("FAIL: demolish_building should fail when second refund resource fails to credit")
		failures += 1

	# Verify rollback was called with exact first resource credited (farm refund is 15 wood)
	if not failing_rm.rollback_called or not failing_rm.rolled_back_credited.has("wood") or failing_rm.rolled_back_credited["wood"] != 15:
		printerr("FAIL: rollback_added_resources was not called with credited wood! Got %s" % str(failing_rm.rolled_back_credited))
		failures += 1

	# Verify stock was rolled back
	if failing_rm.get_resource("wood") != 100:
		printerr("FAIL: Wood stock not rolled back to 100! Got %d" % failing_rm.get_resource("wood"))
		failures += 1

	# Verify daily production tally was rolled back
	if failing_rm.get_daily_production_tally("wood") != 0.0:
		printerr("FAIL: Wood production tally not rolled back! Got %f" % failing_rm.get_daily_production_tally("wood"))
		failures += 1

	# Verify starvation state was restored
	if not failing_rm.is_starving():
		printerr("FAIL: Starvation state was not restored after atomic rollback")
		failures += 1

	# Verify building remains in world_data
	var b_check = BuildingSystemScript.get_building_by_id("bld_atomic_fail_test", wd)
	if b_check.is_empty():
		printerr("FAIL: Building was deleted despite failed demolition")
		failures += 1

	# Verify occupancy is intact
	var occ_ok := true
	for ox in range(2):
		for oy in range(2):
			var cell = Vector2i(22, 22) + Vector2i(ox, oy)
			if IsoMathScript.is_in_bounds(cell) and not wd.occupancy[cell.x][cell.y]:
				occ_ok = false
	if not occ_ok:
		printerr("FAIL: Occupancy was mutated despite failed demolition")
		failures += 1

	# Verify job was preserved
	if world_instance.job_mgr != null and test_job != null and not test_job in world_instance.job_mgr._jobs:
		printerr("FAIL: Job was removed despite failed demolition")
		failures += 1

	# Clean up test fixture
	if world_instance.job_mgr != null and test_job != null:
		world_instance.job_mgr._jobs.erase(test_job)
	wd.buildings.erase(b_data)
	for ox in range(2):
		for oy in range(2):
			var cell = Vector2i(22, 22) + Vector2i(ox, oy)
			if IsoMathScript.is_in_bounds(cell):
				wd.occupancy[cell.x][cell.y] = false

	if failures == 0:
		print("  [PASS] TC-BM.32: Atomic refund failure injection & rollback verified.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.33: Safe Cargo Conservation on Building Demolition (6 Coverage Scenarios)
# -----------------------------------------------------------------------------
func _test_tc_bm_33_cargo_conservation_scenarios() -> bool:
	print("--- Running TC-BM.33: Safe Cargo Conservation on Building Demolition ---")
	var failures: int = 0
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	var wp_mgr = world_instance.workplace_mgr
	var cit0 = world_instance.citizen_list[0]

	# STEP 1: Hauler picks up cargo from workplace using real _pickup_hauler_cargo
	var origin := Vector2i(26, 26)
	var b_data := {
		"id": "farm_cargo_test",
		"type": "farm",
		"cell": origin,
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100
	}
	world_instance.world_data.buildings.append(b_data)
	for ox in range(2):
		for oy in range(2):
			var cell = origin + Vector2i(ox, oy)
			if IsoMathScript.is_in_bounds(cell):
				world_instance.world_data.occupancy[cell.x][cell.y] = true
	world_instance.register_dynamic_workplace(b_data)

	var farm_wp = wp_mgr.get_workplace("farm_cargo_test")
	if farm_wp != null:
		farm_wp.buffer_amount = 10

	var hauler_job = JobData.new()
	hauler_job.id = "haul_farm_test"
	hauler_job.type = "hauler"
	hauler_job.source_workplace_id = "farm_cargo_test"
	hauler_job.target_building_id = "farm_cargo_test"
	hauler_job.cargo_resource = "food"
	hauler_job.cargo_amount = 10
	hauler_job.dest_cell = Vector2i(32, 32)

	cit0.active_job = hauler_job
	cit0.current_state = CitizenController.State.MOVING_TO_JOB
	cit0.current_cell = Vector2i(26, 25) # adjacent cell
	cit0.call("_pickup_hauler_cargo")

	if cit0.carrying_resource != "food" or cit0.carrying_amount != 10:
		printerr("FAIL Step 1: Hauler did not pick up 10 food! Got %d %s" % [cit0.carrying_amount, cit0.carrying_resource])
		failures += 1
	if cit0.carrying_source_workplace_id != "farm_cargo_test":
		printerr("FAIL Step 1: carrying_source_workplace_id was not assigned on pickup! Got '%s'" % cit0.carrying_source_workplace_id)
		failures += 1

	# STEP 2: Partial delivery occurs; central storage accepts partial amount; remainder retained; job released; IDLE; source ID preserved
	var pre_stock = rm.get_resource("food")
	var orig_cap = rm.get_capacity("food")
	rm._capacities["food"] = pre_stock + 4 # Only 4 food space available

	cit0.call("_deposit_hauler_cargo")

	if cit0.carrying_amount != 6:
		printerr("FAIL Step 2: Expected remainder 6 food on citizen, got %d" % cit0.carrying_amount)
		failures += 1
	if cit0.active_job != null:
		printerr("FAIL Step 2: active_job should be released on partial delivery")
		failures += 1
	if cit0.current_state != CitizenController.State.IDLE:
		printerr("FAIL Step 2: Citizen should be IDLE after partial delivery")
		failures += 1
	if cit0.carrying_source_workplace_id != "farm_cargo_test":
		printerr("FAIL Step 2: carrying_source_workplace_id lost after partial delivery! Got '%s'" % cit0.carrying_source_workplace_id)
		failures += 1

	# STEP 3: Source workplace demolition preflight & discovery finds cargo through source identity alone
	var cargo_found = world_instance.get_carried_cargo_for_building("farm_cargo_test")
	if cargo_found.get("food", 0) != 6:
		printerr("FAIL Step 3: get_carried_cargo_for_building failed to find 6 food via persistent source identity! Got: %s" % str(cargo_found))
		failures += 1

	# STEP 4: Save and reload game while citizen holds remainder cargo with no active job
	var temp_save_path := "user://test_cargo_source_id_save.json"
	var s_res = SaveManagerScript.save_to_file(world_instance, temp_save_path)
	if not s_res.get("success", false):
		printerr("FAIL Step 4: Save failed")
		failures += 1
	var l_res = SaveManagerScript.load_from_file(temp_save_path)
	if not l_res.get("success", false):
		printerr("FAIL Step 4: Load failed")
		failures += 1
	var a_res = SaveManagerScript.apply_loaded_state_to_world(world_instance, l_res["data"])
	if not a_res.get("success", false):
		printerr("FAIL Step 4: Apply loaded state failed")
		failures += 1

	if FileAccess.file_exists(temp_save_path):
		DirAccess.remove_absolute(temp_save_path)
	if FileAccess.file_exists(temp_save_path + ".bak"):
		DirAccess.remove_absolute(temp_save_path + ".bak")

	rm = world_instance.get_node_or_null("/root/ResourceManager")
	var cit0_reloaded = world_instance.citizen_list[0]
	if cit0_reloaded.carrying_amount != 6 or cit0_reloaded.carrying_resource != "food":
		printerr("FAIL Step 4: Cargo not preserved across save/load! Amount: %d, Res: %s" % [cit0_reloaded.carrying_amount, cit0_reloaded.carrying_resource])
		failures += 1
	if cit0_reloaded.carrying_source_workplace_id != "farm_cargo_test":
		printerr("FAIL Step 4: carrying_source_workplace_id not preserved across save/load! Got '%s'" % cit0_reloaded.carrying_source_workplace_id)
		failures += 1

	# STEP 5: Demolition after reload correctly finds and handles remainder cargo
	rm._capacities["food"] = orig_cap # restore capacity so refund and cargo can fit
	var dem_res = world_instance.demolish_building_project("farm_cargo_test")
	if not dem_res.get("success", false):
		printerr("FAIL Step 5: Demolition after reload failed: %s" % dem_res.get("reason", ""))
		failures += 1
	if cit0_reloaded.carrying_amount != 0:
		printerr("FAIL Step 5: Remaining cargo was not deposited upon demolition! Still carrying %d" % cit0_reloaded.carrying_amount)
		failures += 1
	if cit0_reloaded.carrying_source_workplace_id != "":
		printerr("FAIL Step 5: carrying_source_workplace_id was not cleared after successful demolition deposit! Got '%s'" % cit0_reloaded.carrying_source_workplace_id)
		failures += 1

	# Clean up food added from test
	rm.consume_resource("food", 10)

	# STEP 6: Multi-channel recipes (workshop channels) resolve to parent building
	var ws_origin := Vector2i(28, 28)
	var ws_data := {
		"id": "ws_channel_test",
		"type": "workshop",
		"cell": ws_origin,
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100
	}
	world_instance.world_data.buildings.append(ws_data)
	for ox in range(2):
		for oy in range(2):
			var cell = ws_origin + Vector2i(ox, oy)
			if IsoMathScript.is_in_bounds(cell):
				world_instance.world_data.occupancy[cell.x][cell.y] = true
	world_instance.register_dynamic_workplace(ws_data)

	cit0_reloaded.carrying_resource = "metal"
	cit0_reloaded.carrying_amount = 5
	cit0_reloaded.carrying_source_workplace_id = "ws_channel_test_smelt"
	cit0_reloaded.active_job = null
	cit0_reloaded.set("workplace_id", "")

	var ws_cargo = world_instance.get_carried_cargo_for_building("ws_channel_test")
	if ws_cargo.get("metal", 0) != 5:
		printerr("FAIL Step 6: Workshop channel cargo not resolved to parent workshop! Got: %s" % str(ws_cargo))
		failures += 1

	var pre_metal = rm.get_resource("metal")
	var ws_dem = world_instance.demolish_building_project("ws_channel_test")
	if not ws_dem.get("success", false):
		printerr("FAIL Step 6: Workshop demolition failed: %s" % ws_dem.get("reason", ""))
		failures += 1
	if rm.get_resource("metal") != pre_metal + 7: # 2 refund (50% of 5) + 5 cargo = 7
		printerr("FAIL Step 6: Metal cargo + refund not deposited into storage on workshop demolition! Got %d, expected %d" % [rm.get_resource("metal"), pre_metal + 7])
		failures += 1
	if cit0_reloaded.carrying_amount != 0 or cit0_reloaded.carrying_source_workplace_id != "":
		printerr("FAIL Step 6: Citizen cargo and source workplace not cleared after workshop demolition")
		failures += 1

	rm.consume_resource("metal", 7)
	rm.consume_resource("wood", 10)
	rm.consume_resource("stone", 7)

	if failures == 0:
		print("  [PASS] TC-BM.33: All 6 safe cargo conservation scenarios verified.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.34: Starter Storage Capacity Invariant & Dual Demolition Baseline
# -----------------------------------------------------------------------------
func _test_tc_bm_34_starter_storage_capacity_invariant() -> bool:
	print("--- Running TC-BM.34: Starter Storage Capacity Invariant ---")
	var failures: int = 0
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	var wd = world_instance.world_data

	# 1. Verify single authoritative starter capacity invariant
	var expected_starter_caps := {
		"food": 1500,
		"wood": 1500,
		"stone": 1500,
		"ore": 900,
		"metal": 900,
		"tools": 400,
		"herbs": 400,
		"crystal": 200,
		"gold": 999999
	}
	for res_id in expected_starter_caps:
		var cap = rm.get_capacity(res_id)
		if cap != expected_starter_caps[res_id]:
			printerr("FAIL: Initial capacity mismatch for %s: got %d, expected %d" % [res_id, cap, expected_starter_caps[res_id]])
			failures += 1

	# Backup starter building entries before demolition
	var th_entry = BuildingSystemScript.get_building_by_id("townhall_starter", wd).duplicate(true)
	var sh_entry = BuildingSystemScript.get_building_by_id("storehouse_starter", wd).duplicate(true)

	# 2. Demolish Storehouse
	var pre_wood = rm.get_resource("wood")
	var pre_stone = rm.get_resource("stone")
	rm._current_stock["wood"] = 0
	rm._current_stock["stone"] = 0

	var sh_res = world_instance.demolish_building_project("storehouse_starter")
	if not sh_res.get("success", false):
		printerr("FAIL: Storehouse demolition failed: %s" % sh_res.get("reason", ""))
		failures += 1

	# Post-storehouse capacities: Food/Wood/Stone 1000, Ore/Metal 600, Tools/Herbs 400, Crystal 200
	if rm.get_capacity("food") != 1000 or rm.get_capacity("ore") != 600:
		printerr("FAIL: Post-storehouse capacity incorrect: food=%d, ore=%d" % [rm.get_capacity("food"), rm.get_capacity("ore")])
		failures += 1

	# 3. Demolish Town Hall
	var th_res = world_instance.demolish_building_project("townhall_starter")
	if not th_res.get("success", false):
		printerr("FAIL: Townhall demolition failed: %s" % th_res.get("reason", ""))
		failures += 1

	# 4. Invariant check: When both are demolished, every resource returns EXACTLY to BASE_CAPACITIES
	for res_id in EconomyConfigScript.BASE_CAPACITIES:
		var cap = rm.get_capacity(res_id)
		var base_cap = EconomyConfigScript.BASE_CAPACITIES[res_id]
		if cap != base_cap:
			printerr("FAIL: Base capacity mismatch for %s: got %d, expected base %d" % [res_id, cap, base_cap])
			failures += 1

	# 5. Verify SaveManager serialization/deserialization doesn't alter capacities
	var temp_save_path := "user://test_cap_save_temp.json"
	var save_res = SaveManagerScript.save_to_file(world_instance, temp_save_path)
	if not save_res.get("success", false):
		printerr("FAIL: Save failed in TC-BM.34")
		failures += 1
	var load_res = SaveManagerScript.load_from_file(temp_save_path)
	if not load_res.get("success", false):
		printerr("FAIL: Load failed in TC-BM.34")
		failures += 1
	var apply_res = SaveManagerScript.apply_loaded_state_to_world(world_instance, load_res["data"])
	if not apply_res.get("success", false):
		printerr("FAIL: Apply loaded state failed in TC-BM.34")
		failures += 1

	for res_id in EconomyConfigScript.BASE_CAPACITIES:
		if rm.get_capacity(res_id) != EconomyConfigScript.BASE_CAPACITIES[res_id]:
			printerr("FAIL: Capacity changed after save/load: %s is %d" % [res_id, rm.get_capacity(res_id)])
			failures += 1

	# Clean temp save file
	if FileAccess.file_exists(temp_save_path):
		DirAccess.remove_absolute(temp_save_path)
	if FileAccess.file_exists(temp_save_path + ".bak"):
		DirAccess.remove_absolute(temp_save_path + ".bak")
	if FileAccess.file_exists(temp_save_path + ".bak.old"):
		DirAccess.remove_absolute(temp_save_path + ".bak.old")

	# Clean restoration of Town Hall and Storehouse
	rm.reset_economy()
	rm._current_stock["wood"] = pre_wood
	rm._current_stock["stone"] = pre_stone

	if not th_entry.is_empty():
		th_entry["storage_applied"] = true
		wd.buildings.append(th_entry)
		for ox in range(th_entry.get("size", Vector2i(3, 3)).x):
			for oy in range(th_entry.get("size", Vector2i(3, 3)).y):
				var cell = th_entry.get("cell", Vector2i.ZERO) + Vector2i(ox, oy)
				if IsoMathScript.is_in_bounds(cell):
					wd.occupancy[cell.x][cell.y] = true
		world_instance._instantiate_building_node("townhall", th_entry.get("cell", Vector2i.ZERO), Vector2i(3, 3), "active")

	if not sh_entry.is_empty():
		sh_entry["storage_applied"] = true
		wd.buildings.append(sh_entry)
		for ox in range(sh_entry.get("size", Vector2i(2, 2)).x):
			for oy in range(sh_entry.get("size", Vector2i(2, 2)).y):
				var cell = sh_entry.get("cell", Vector2i.ZERO) + Vector2i(ox, oy)
				if IsoMathScript.is_in_bounds(cell):
					wd.occupancy[cell.x][cell.y] = true
		world_instance._instantiate_building_node("storehouse", sh_entry.get("cell", Vector2i.ZERO), Vector2i(2, 2), "active")

	if world_instance.victory_mgr != null:
		world_instance.victory_mgr.townhall_ruin_hours = 0.0
		world_instance.victory_mgr.is_collapse_triggered = false
		world_instance.victory_mgr.primary_collapse_reason = ""

	if failures == 0:
		print("  [PASS] TC-BM.34: Starter storage capacity invariant and clean restoration verified.")
		return true
	return false
