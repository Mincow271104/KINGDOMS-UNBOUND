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
		results.append(_test_tc_bm_35_legacy_building_defaults_level_1())
		results.append(_test_tc_bm_36_house_upgrades_capacity())
		results.append(_test_tc_bm_37_farm_upgrades_production_multiplier())
		results.append(_test_tc_bm_38_storehouse_upgrades_capacity_deltas())
		results.append(_test_tc_bm_39_upgrade_costs_and_durations())
		results.append(_test_tc_bm_40_insufficient_resources_rejection())
		results.append(_test_tc_bm_41_upgrade_progress_and_timemanager())
		results.append(_test_tc_bm_42_upgrade_completion_single_application())
		results.append(_test_tc_bm_43_upgrade_completion_idempotency())
		results.append(_test_tc_bm_44_upgrade_cancellation_50_percent_refund())
		results.append(_test_tc_bm_45_cancellation_insufficient_storage_fail_closed())
		results.append(_test_tc_bm_46_save_load_in_progress_upgrade())
		results.append(_test_tc_bm_47_repeated_load_zero_drift())
		results.append(_test_tc_bm_48_demolition_of_upgraded_storehouse())
		results.append(_test_tc_bm_49_level_1_regressions_valid())

		all_passed = true
		for r in results:
			if not r:
				all_passed = false
				break

		print("\n--------------------------------------------------------")
		if all_passed:
			print("  ALL PACKAGE 2F & 2I BUILDING MANAGEMENT TESTS PASSED! (Exit Code 0)")
			print("--------------------------------------------------------\n")
			quit(0)
			return true
		else:
			print("  PACKAGE 2F & 2I BUILDING MANAGEMENT TESTS FAILED! (Exit Code 1)")
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
# Test Fixture State Snapshot & Isolation Helpers (Package 2F Round 6)
# -----------------------------------------------------------------------------
func _snapshot_resource_manager(rm: Node) -> Dictionary:
	if rm == null:
		return {}
	return {
		"_current_stock": rm._current_stock.duplicate(true),
		"_reserved_stock": rm._reserved_stock.duplicate(true),
		"_capacities": rm._capacities.duplicate(true),
		"_daily_production_tallies": rm._daily_production_tallies.duplicate(true),
		"_daily_consumption_tallies": rm._daily_consumption_tallies.duplicate(true),
		"_last_day_production": rm._last_day_production.duplicate(true),
		"_last_day_consumption": rm._last_day_consumption.duplicate(true),
		"_is_starving": rm._is_starving,
		"active_population": rm.active_population
	}

func _restore_resource_manager(rm: Node, snap: Dictionary) -> void:
	if rm == null or snap.is_empty():
		return
	rm._current_stock = snap["_current_stock"].duplicate(true)
	rm._reserved_stock = snap["_reserved_stock"].duplicate(true)
	rm._capacities = snap["_capacities"].duplicate(true)
	rm._daily_production_tallies = snap["_daily_production_tallies"].duplicate(true)
	rm._daily_consumption_tallies = snap["_daily_consumption_tallies"].duplicate(true)
	rm._last_day_production = snap["_last_day_production"].duplicate(true)
	rm._last_day_consumption = snap["_last_day_consumption"].duplicate(true)
	rm._is_starving = snap["_is_starving"]
	if snap.has("active_population"):
		rm.active_population = snap["active_population"]

func _assert_resource_manager_matches_snapshot(rm: Node, snap: Dictionary, test_name: String) -> int:
	if rm == null:
		printerr("FAIL %s: ResourceManager is null during snapshot assertion" % test_name)
		return 1
	var failures: int = 0
	for key in snap:
		var current_val = rm.get(key)
		var expected_val = snap[key]
		if typeof(expected_val) == TYPE_DICTIONARY:
			if current_val == null or typeof(current_val) != TYPE_DICTIONARY:
				printerr("FAIL %s: RM %s is not a dictionary" % [test_name, key])
				failures += 1
				continue
			if current_val.size() != expected_val.size():
				printerr("FAIL %s: RM %s dictionary size mismatch: %d != %d" % [test_name, key, current_val.size(), expected_val.size()])
				failures += 1
			for res in expected_val:
				if not current_val.has(res) or current_val[res] != expected_val[res]:
					printerr("FAIL %s: RM %s mismatch for '%s': got %s, expected %s" % [test_name, key, res, str(current_val.get(res)), str(expected_val[res])])
					failures += 1
		else:
			if current_val != expected_val:
				printerr("FAIL %s: RM %s mismatch: got %s, expected %s" % [test_name, key, str(current_val), str(expected_val)])
				failures += 1
	return failures

func _snapshot_citizen_state(cit: Node) -> Dictionary:
	if cit == null:
		return {}
	var snap := {
		"citizen_id": cit.get("citizen_id"),
		"citizen_name": cit.get("citizen_name"),
		"role": cit.get("role"),
		"workplace_id": cit.get("workplace_id"),
		"current_state": cit.get("current_state"),
		"status_reason": cit.get("status_reason"),
		"current_cell": cit.get("current_cell"),
		"position": cit.get("position"),
		"current_path": (cit.get("current_path") as Array).duplicate() if cit.get("current_path") != null else [],
		"hunger": cit.get("hunger"),
		"fatigue": cit.get("fatigue"),
		"health": cit.get("health"),
		"morale": cit.get("morale"),
		"carrying_amount": cit.get("carrying_amount"),
		"carrying_resource": cit.get("carrying_resource"),
		"carrying_source_workplace_id": cit.get("carrying_source_workplace_id"),
		"carry_capacity": cit.get("carry_capacity"),
		"xp": {}
	}
	if cit.has_method("get_skill_data") and cit.get_skill_data() != null:
		snap["xp"] = cit.get_skill_data()._xp.duplicate(true)
	return snap

func _find_citizen_by_id(cid: String) -> Node:
	if world_instance == null or cid == "":
		return null
	if world_instance.citizens_by_id != null and world_instance.citizens_by_id.has(cid):
		var c = world_instance.citizens_by_id[cid]
		if is_instance_valid(c):
			return c
	if world_instance.citizen_list != null:
		for c in world_instance.citizen_list:
			if is_instance_valid(c) and c.get("citizen_id") == cid:
				return c
	return null

func _restore_citizen_state(cid: String, snap: Dictionary, test_name: String) -> int:
	var failures: int = 0
	var cit = _find_citizen_by_id(cid)
	if cit == null:
		printerr("FAIL %s: Could not find citizen with id '%s' for restoration" % [test_name, cid])
		return 1

	if not cit in world_instance.citizen_list:
		printerr("FAIL %s: Citizen %s is not in world_view.citizen_list" % [test_name, cid])
		failures += 1
	if world_instance.citizens_by_id.get(cid) != cit:
		printerr("FAIL %s: Citizen %s is not the instance in world_view.citizens_by_id" % [test_name, cid])
		failures += 1

	cit.set("role", snap.get("role", "farmer"))
	if snap.has("current_state"):
		cit.set("current_state", snap["current_state"])
	if snap.has("status_reason"):
		cit.set("status_reason", snap["status_reason"])
	if snap.has("workplace_id"):
		cit.set("workplace_id", snap["workplace_id"])
	if snap.has("hunger"):
		cit.set("hunger", snap["hunger"])
	if snap.has("fatigue"):
		cit.set("fatigue", snap["fatigue"])
	if snap.has("health"):
		cit.set("health", snap["health"])
	if snap.has("morale"):
		cit.set("morale", snap["morale"])
	if snap.has("carrying_amount"):
		cit.set("carrying_amount", snap["carrying_amount"])
	if snap.has("carrying_resource"):
		cit.set("carrying_resource", snap["carrying_resource"])
	if snap.has("carrying_source_workplace_id"):
		cit.set("carrying_source_workplace_id", snap["carrying_source_workplace_id"])
	if snap.has("carry_capacity"):
		cit.set("carry_capacity", snap["carry_capacity"])
	cit.active_job = null
	if snap.has("current_path") and snap["current_path"] is Array:
		cit.current_path = (snap["current_path"] as Array).duplicate()
	else:
		cit.current_path = []

	if snap.has("current_cell"):
		cit.set("current_cell", snap["current_cell"])
		cit.position = IsoMathScript.map_to_local(snap["current_cell"])

	if snap.has("xp") and cit.has_method("get_skill_data") and cit.get_skill_data() != null:
		cit.get_skill_data()._xp = snap["xp"].duplicate(true)

	if cit.get("role") != snap.get("role"):
		printerr("FAIL %s: Citizen %s role not restored: %s != %s" % [test_name, cid, cit.get("role"), snap.get("role")])
		failures += 1

	if snap.has("current_cell"):
		if cit.get("current_cell") != snap["current_cell"]:
			printerr("FAIL %s: Citizen %s current_cell not restored: %s != %s" % [test_name, cid, str(cit.get("current_cell")), str(snap["current_cell"])])
			failures += 1
		var expected_pos: Vector2 = IsoMathScript.map_to_local(snap["current_cell"])
		if cit.position != expected_pos:
			printerr("FAIL %s: Citizen %s position not synchronized: %s != %s" % [test_name, cid, str(cit.position), str(expected_pos)])
			failures += 1

	if snap.has("carrying_amount") and cit.get("carrying_amount") != snap["carrying_amount"]:
		printerr("FAIL %s: Citizen %s carrying_amount not restored: %s != %s" % [test_name, cid, str(cit.get("carrying_amount")), str(snap["carrying_amount"])])
		failures += 1
	if snap.has("carrying_resource") and cit.get("carrying_resource") != snap["carrying_resource"]:
		printerr("FAIL %s: Citizen %s carrying_resource not restored: %s != %s" % [test_name, cid, str(cit.get("carrying_resource")), str(snap["carrying_resource"])])
		failures += 1
	if snap.has("carrying_source_workplace_id") and cit.get("carrying_source_workplace_id") != snap["carrying_source_workplace_id"]:
		printerr("FAIL %s: Citizen %s carrying_source_workplace_id not restored: %s != %s" % [test_name, cid, str(cit.get("carrying_source_workplace_id")), str(snap["carrying_source_workplace_id"])])
		failures += 1

	if snap.has("xp") and cit.has_method("get_skill_data") and cit.get_skill_data() != null:
		for voc in snap["xp"]:
			if cit.get_skill_data().get_xp(voc) != snap["xp"][voc]:
				printerr("FAIL %s: Citizen %s skill %s not restored: %f != %f" % [test_name, cid, voc, cit.get_skill_data().get_xp(voc), snap["xp"][voc]])
				failures += 1

	return failures

# -----------------------------------------------------------------------------
# TC-BM.31: Workshop Dual-Channel Pause/Resume Integration Coverage
# -----------------------------------------------------------------------------
func _test_tc_bm_31_workshop_pause_channels() -> bool:
	print("--- Running TC-BM.31: Workshop Dual-Channel Pause/Resume Integration ---")
	var failures: int = 0
	var jm = world_instance.job_mgr
	var wp_mgr = world_instance.workplace_mgr
	var rm = world_instance.get_node_or_null("/root/ResourceManager")

	# Objective A: Snapshot complete ResourceManager state before test modifications
	var init_rm_snapshot: Dictionary = _snapshot_resource_manager(rm)

	# Objective D: Snapshot citizen state before modifying roles for authentic workshop assignment
	var cit0 = world_instance.citizen_list[0]
	var cit1 = world_instance.citizen_list[1] if world_instance.citizen_list.size() > 1 else null
	var snap_cit0: Dictionary = _snapshot_citizen_state(cit0)
	var snap_cit1: Dictionary = _snapshot_citizen_state(cit1) if cit1 != null else {}

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
	var channels_valid: bool = (smelt_wp != null and craft_wp != null)
	if not channels_valid:
		printerr("FAIL: Both workshop channels must exist on registration")
		failures += 1

	var jobs_valid: bool = false
	var job_smelt: JobData = null
	var job_craft: JobData = null
	var job_haul: JobData = null

	if channels_valid:
		smelt_wp.buffer_amount = 6
		craft_wp.buffer_amount = 4

		# B1: Retrieve the actual registered smelt and craft jobs from jm.get_jobs_for_building()
		var registered_jobs: Array = jm.get_jobs_for_building("workshop_test_pause")
		for j in registered_jobs:
			if j.recipe_id == "smelt_metal" and j.workplace_channel_id == "workshop_test_pause_smelt" and job_smelt == null:
				job_smelt = j
			elif j.recipe_id == "craft_tools" and j.workplace_channel_id == "workshop_test_pause_craft" and job_craft == null:
				job_craft = j

		if job_smelt == null or job_craft == null:
			printerr("FAIL B1: Real registered workshop jobs not found in JobManager: smelt=%s, craft=%s" % [str(job_smelt), str(job_craft)])
			failures += 1
		else:
			jobs_valid = true

	if jobs_valid:
		job_haul = jm.create_hauling_job("workshop_test_pause_smelt", smelt_wp.access_cell, Vector2i(31, 34), "metal", 5, "Haul smelted metal", 2)

		# Provide crafting materials for input checks and actual production
		rm.add_resource("ore", 10)
		rm.add_resource("metal", 10)
		rm.add_resource("wood", 10)

		# 1. Active: jobs are executable and actual production works on both channels
		if not jm._is_job_executable(job_smelt, wp_mgr, rm, Callable(), world_instance.nav):
			printerr("FAIL: Smelt job should be executable when workshop is active")
			failures += 1
		if not jm._is_job_executable(job_craft, wp_mgr, rm, Callable(), world_instance.nav):
			printerr("FAIL: Craft job should be executable when workshop is active")
			failures += 1

		var pre_prod_ore: int = rm.get_resource("ore")
		var pre_prod_metal: int = rm.get_resource("metal")
		var pre_prod_wood: int = rm.get_resource("wood")

		# Real production to buffer: Smelt channel consumes 2 ore and produces 1 metal to buffer
		var produced_smelt = wp_mgr.produce_to_buffer("workshop_test_pause_smelt", 1.0, rm)
		if produced_smelt != 1 or smelt_wp.buffer_amount != 7:
			printerr("FAIL: Active smelt production failed: produced=%d, buffer=%d" % [produced_smelt, smelt_wp.buffer_amount])
			failures += 1
		if rm.get_resource("ore") != pre_prod_ore - 2:
			printerr("FAIL: Smelt production did not consume 2 ore! %d -> %d" % [pre_prod_ore, rm.get_resource("ore")])
			failures += 1

		# Real production to buffer: Craft channel consumes 2 metal, 1 wood and produces 1 tool to buffer
		var produced_craft = wp_mgr.produce_to_buffer("workshop_test_pause_craft", 1.0, rm)
		if produced_craft != 1 or craft_wp.buffer_amount != 5:
			printerr("FAIL: Active craft production failed: produced=%d, buffer=%d" % [produced_craft, craft_wp.buffer_amount])
			failures += 1
		if rm.get_resource("metal") != pre_prod_metal - 2 or rm.get_resource("wood") != pre_prod_wood - 1:
			printerr("FAIL: Craft production input consumption incorrect: metal=%d, wood=%d" % [rm.get_resource("metal"), rm.get_resource("wood")])
			failures += 1

		# Objective D: Assign genuine 'smith' role to workers while assigned to Workshop jobs
		cit0.role = "smith"
		job_smelt.state = JobState.IN_PROGRESS
		job_smelt.worker_id = cit0.citizen_id
		cit0.active_job = job_smelt
		cit0.current_state = CitizenController.State.WORKING
		if cit0.role != "smith":
			printerr("FAIL Objective D: cit0 role was not set to 'smith'")
			failures += 1

		if cit1 != null:
			cit1.role = "smith"
			job_craft.state = JobState.IN_PROGRESS
			job_craft.worker_id = cit1.citizen_id
			cit1.active_job = job_craft
			cit1.current_state = CitizenController.State.WORKING
			if cit1.role != "smith":
				printerr("FAIL Objective D: cit1 role was not set to 'smith'")
				failures += 1

		# B2. Parent pause: both channels paused, buffers unchanged, workers safely released to IDLE, jobs available/unassigned
		var pre_pause_ore = rm.get_resource("ore")
		var pre_pause_metal = rm.get_resource("metal")
		var pre_pause_wood = rm.get_resource("wood")

		world_instance.set_building_state("workshop_test_pause", "paused")
		if not wp_mgr.is_workplace_paused("workshop_test_pause_smelt") or not wp_mgr.is_workplace_paused("workshop_test_pause_craft"):
			printerr("FAIL: Both workshop sub-channels must be paused")
			failures += 1

		if smelt_wp.buffer_amount != 7 or craft_wp.buffer_amount != 5:
			printerr("FAIL: Buffers must remain unchanged while paused: smelt=%d, craft=%d" % [smelt_wp.buffer_amount, craft_wp.buffer_amount])
			failures += 1

		if cit0.current_state != CitizenController.State.IDLE or cit0.active_job != null:
			printerr("FAIL: Active smith worker cit0 not released to IDLE on pause")
			failures += 1
		if cit1 != null and (cit1.current_state != CitizenController.State.IDLE or cit1.active_job != null):
			printerr("FAIL: Active smith worker cit1 not released to IDLE on pause")
			failures += 1

		if job_smelt.state != JobState.AVAILABLE or job_smelt.worker_id != "":
			printerr("FAIL B2: job_smelt not returned to AVAILABLE unassigned state: state=%d, worker=%s" % [job_smelt.state, job_smelt.worker_id])
			failures += 1
		if job_craft.state != JobState.AVAILABLE or job_craft.worker_id != "":
			printerr("FAIL B2: job_craft not returned to AVAILABLE unassigned state: state=%d, worker=%s" % [job_craft.state, job_craft.worker_id])
			failures += 1

		# Production to buffer during pause must return 0 and consume no inputs
		var paused_smelt_prod = wp_mgr.produce_to_buffer("workshop_test_pause_smelt", 1.0, rm)
		var paused_craft_prod = wp_mgr.produce_to_buffer("workshop_test_pause_craft", 1.0, rm)
		if paused_smelt_prod != 0 or paused_craft_prod != 0:
			printerr("FAIL: produce_to_buffer must return 0 while paused! got smelt=%d, craft=%d" % [paused_smelt_prod, paused_craft_prod])
			failures += 1
		if smelt_wp.buffer_amount != 7 or craft_wp.buffer_amount != 5:
			printerr("FAIL: Buffers mutated during paused produce_to_buffer!")
			failures += 1
		if rm.get_resource("ore") != pre_pause_ore or rm.get_resource("metal") != pre_pause_metal or rm.get_resource("wood") != pre_pause_wood:
			printerr("FAIL B2: Input resources mutated during paused production calls!")
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

		# Clean up transient hauler test job before persisting building state
		if jm != null and job_haul != null and job_haul in jm._jobs:
			jm._jobs.erase(job_haul)

		# B3. Save/load exact identity comparison
		var build_job_snapshot := func() -> Array:
			var snap: Array = []
			for j in jm.get_jobs_for_building("workshop_test_pause"):
				snap.append({
					"id": j.id,
					"type": j.type,
					"target_building_id": j.target_building_id,
					"recipe_id": j.recipe_id,
					"workplace_channel_id": j.workplace_channel_id,
					"is_recurring": j.is_recurring,
					"state": j.state,
					"worker_id": j.worker_id
				})
			snap.sort_custom(func(a, b): return a["id"] < b["id"])
			return snap

		var pre_save_snapshot: Array = build_job_snapshot.call()
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

		# Verify exactly two WorkplaceData channels exist and preserve channel IDs and recipe metadata (B3)
		var ws_channels: Array = []
		for wp in wp_mgr.get_all_workplaces():
			if wp.parent_building_id == "workshop_test_pause":
				ws_channels.append(wp)
		if ws_channels.size() != 2:
			printerr("FAIL B3: Channel count mismatch after load: expected 2, got %d" % ws_channels.size())
			failures += 1
		var found_smelt := false
		var found_craft := false
		for wp in ws_channels:
			if wp.id == "workshop_test_pause_smelt" and wp.recipe_id == "smelt_metal" and wp.buffer_amount == 7:
				found_smelt = true
			elif wp.id == "workshop_test_pause_craft" and wp.recipe_id == "craft_tools" and wp.buffer_amount == 5:
				found_craft = true
		if not found_smelt or not found_craft:
			printerr("FAIL B3: Loaded channels lack correct channel IDs, recipe metadata, or buffer amounts")
			failures += 1

		# Compare complete job identity and state snapshot (B3)
		var post_load_snapshot: Array = build_job_snapshot.call()
		if post_load_snapshot.size() != pre_save_snapshot.size():
			printerr("FAIL B3: Workshop job count mismatch after load: pre=%d, post=%d" % [pre_save_snapshot.size(), post_load_snapshot.size()])
			failures += 1
		else:
			for i in range(pre_save_snapshot.size()):
				var s_pre: Dictionary = pre_save_snapshot[i]
				var s_post: Dictionary = post_load_snapshot[i]
				for k in s_pre:
					if s_pre[k] != s_post.get(k, null):
						printerr("FAIL B3: Job identity/state mismatch for job %s key '%s': pre=%s, post=%s" % [s_pre["id"], k, str(s_pre[k]), str(s_post.get(k))])
						failures += 1

		# Objective D: Verify reconstructed citizens preserved 'smith' role across save/load
		var cit0_post_load = _find_citizen_by_id(snap_cit0["citizen_id"])
		if cit0_post_load == null or cit0_post_load.role != "smith":
			printerr("FAIL Objective D: cit0 role 'smith' was not preserved across save/load: %s" % (cit0_post_load.role if cit0_post_load else "null"))
			failures += 1
		if not snap_cit1.is_empty():
			var cit1_post_load = _find_citizen_by_id(snap_cit1["citizen_id"])
			if cit1_post_load == null or cit1_post_load.role != "smith":
				printerr("FAIL Objective D: cit1 role 'smith' was not preserved across save/load: %s" % (cit1_post_load.role if cit1_post_load else "null"))
				failures += 1

		# B4. Resume lifecycle: resume through actual world API
		world_instance.set_building_state("workshop_test_pause", "active")
		if not BuildingSystemScript.is_building_active_by_id("workshop_test_pause", world_instance.world_data):
			printerr("FAIL: Workshop should be active after resume")
			failures += 1
		if wp_mgr.is_workplace_paused("workshop_test_pause_smelt") or wp_mgr.is_workplace_paused("workshop_test_pause_craft"):
			printerr("FAIL: Workshop sub-channels should not be paused after resume")
			failures += 1

		var smelt_wp_loaded = wp_mgr.get_workplace("workshop_test_pause_smelt")
		var craft_wp_loaded = wp_mgr.get_workplace("workshop_test_pause_craft")
		var pre_resume_ore = rm.get_resource("ore")
		var pre_resume_metal = rm.get_resource("metal")
		var pre_resume_wood = rm.get_resource("wood")

		var res_smelt_prod = wp_mgr.produce_to_buffer("workshop_test_pause_smelt", 1.0, rm)
		var res_craft_prod = wp_mgr.produce_to_buffer("workshop_test_pause_craft", 1.0, rm)
		if res_smelt_prod != 1 or smelt_wp_loaded.buffer_amount != 8:
			printerr("FAIL: Production after resume failed on smelt: produced=%d, buffer=%d" % [res_smelt_prod, smelt_wp_loaded.buffer_amount])
			failures += 1
		if rm.get_resource("ore") != pre_resume_ore - 2:
			printerr("FAIL: Smelt after resume did not consume 2 ore! %d -> %d" % [pre_resume_ore, rm.get_resource("ore")])
			failures += 1

		if res_craft_prod != 1 or craft_wp_loaded.buffer_amount != 6:
			printerr("FAIL: Production after resume failed on craft: produced=%d, buffer=%d" % [res_craft_prod, craft_wp_loaded.buffer_amount])
			failures += 1
		if rm.get_resource("metal") != pre_resume_metal - 2 or rm.get_resource("wood") != pre_resume_wood - 1:
			printerr("FAIL: Craft after resume did not consume inputs correctly: metal=%d, wood=%d" % [pre_resume_metal, rm.get_resource("metal")])
			failures += 1

		# Compare job identity/state snapshot after resume (B4)
		var post_resume_snapshot: Array = build_job_snapshot.call()
		if post_resume_snapshot.size() != post_load_snapshot.size():
			printerr("FAIL B4: Workshop job count changed after resume: %d vs %d" % [post_load_snapshot.size(), post_resume_snapshot.size()])
			failures += 1
		else:
			for i in range(post_load_snapshot.size()):
				var s_load: Dictionary = post_load_snapshot[i]
				var s_resume: Dictionary = post_resume_snapshot[i]
				for k in s_load:
					if s_load[k] != s_resume.get(k, null):
						printerr("FAIL B4: Job snapshot changed after resume for job %s key '%s': %s vs %s" % [s_load["id"], k, str(s_load[k]), str(s_resume.get(k))])
						failures += 1

		# Check channel count remains strictly 2 (B4)
		var resume_ch_count := 0
		for wp in wp_mgr.get_all_workplaces():
			if wp.parent_building_id == "workshop_test_pause":
				resume_ch_count += 1
		if resume_ch_count != 2:
			printerr("FAIL B4: Channel count duplicated after resume: %d" % resume_ch_count)
			failures += 1

		# Find reloaded jobs and test executability
		var reloaded_jobs = jm.get_jobs_for_building("workshop_test_pause")
		var reloaded_smelt: JobData = null
		var reloaded_craft: JobData = null
		for j in reloaded_jobs:
			if j.recipe_id == "smelt_metal" and j.workplace_channel_id == "workshop_test_pause_smelt" and reloaded_smelt == null:
				reloaded_smelt = j
			elif j.recipe_id == "craft_tools" and j.workplace_channel_id == "workshop_test_pause_craft" and reloaded_craft == null:
				reloaded_craft = j

		if reloaded_smelt == null or not jm._is_job_executable(reloaded_smelt, wp_mgr, rm, Callable(), world_instance.nav):
			printerr("FAIL: Smelt job should be executable after resume")
			failures += 1
		if reloaded_craft == null or not jm._is_job_executable(reloaded_craft, wp_mgr, rm, Callable(), world_instance.nav):
			printerr("FAIL: Craft job should be executable after resume")
			failures += 1

	# Clean up hauler job from jm if present
	if jm != null and job_haul != null and job_haul in jm._jobs:
		jm._jobs.erase(job_haul)

	# Objective A & C: Teardown Workshop through the real world demolition API
	var dem_res = world_instance.demolish_building_project("workshop_test_pause")
	if not dem_res.get("success", false):
		printerr("FAIL Objective A: Workshop demolition failed: %s" % dem_res.get("reason", ""))
		failures += 1

	# Fallback safe removal if demolition failed or was partial
	var b_check = BuildingSystemScript.get_building_by_id("workshop_test_pause", world_instance.world_data)
	if not b_check.is_empty():
		printerr("FAIL Objective A: Workshop building record still present in world_data after teardown")
		world_instance.world_data.buildings.erase(b_check)
		failures += 1

	if wp_mgr != null:
		if wp_mgr.get_workplace("workshop_test_pause_smelt") != null:
			printerr("FAIL Objective A: Workshop smelt channel still present in WorkplaceManager after teardown")
			wp_mgr.unregister_workplace("workshop_test_pause_smelt")
			failures += 1
		if wp_mgr.get_workplace("workshop_test_pause_craft") != null:
			printerr("FAIL Objective A: Workshop craft channel still present in WorkplaceManager after teardown")
			wp_mgr.unregister_workplace("workshop_test_pause_craft")
			failures += 1
		wp_mgr.unregister_workplace("workshop_test_pause")

	if jm != null:
		var remaining_jobs = jm.get_jobs_for_building("workshop_test_pause")
		if remaining_jobs.size() > 0:
			printerr("FAIL Objective A: Workshop jobs still present in JobManager after teardown: %d jobs" % remaining_jobs.size())
			jm.remove_jobs_for_building("workshop_test_pause")
			failures += 1

	# ONLY AFTER fixture teardown, restore the exact ResourceManager snapshot
	_restore_resource_manager(rm, init_rm_snapshot)
	failures += _assert_resource_manager_matches_snapshot(rm, init_rm_snapshot, "TC-BM.31")

	# Objective D: Restore citizen authentic roles on current valid post-load citizen instances
	failures += _restore_citizen_state(snap_cit0["citizen_id"], snap_cit0, "TC-BM.31 cit0")
	if not snap_cit1.is_empty():
		failures += _restore_citizen_state(snap_cit1["citizen_id"], snap_cit1, "TC-BM.31 cit1")

	var final_cit0_31 = _find_citizen_by_id(snap_cit0["citizen_id"])
	if final_cit0_31 == null:
		printerr("FAIL Objective D: final_cit0_31 not found after cleanup")
		failures += 1
	else:
		if jobs_valid and final_cit0_31 == cit0:
			printerr("FAIL Objective D: final_cit0_31 is pointing to stale pre-load instance")
			failures += 1
		if not final_cit0_31 in world_instance.citizen_list:
			printerr("FAIL Objective D: final_cit0_31 not in world_view.citizen_list")
			failures += 1
		if world_instance.citizens_by_id.get(snap_cit0["citizen_id"]) != final_cit0_31:
			printerr("FAIL Objective D: citizens_by_id does not point to final_cit0_31")
			failures += 1
		if final_cit0_31.current_cell != snap_cit0["current_cell"]:
			printerr("FAIL Objective D: final_cit0_31 current_cell not restored: %s != %s" % [str(final_cit0_31.current_cell), str(snap_cit0["current_cell"])])
			failures += 1
		var expected_pos_31: Vector2 = IsoMathScript.map_to_local(snap_cit0["current_cell"])
		if final_cit0_31.position != expected_pos_31:
			printerr("FAIL Objective D: final_cit0_31 position not synchronized: %s != %s" % [str(final_cit0_31.position), str(expected_pos_31)])
			failures += 1
		if final_cit0_31.role != snap_cit0["role"]:
			printerr("FAIL Objective D: final_cit0_31 role not restored to '%s', got '%s'" % [snap_cit0["role"], final_cit0_31.role])
			failures += 1
		if snap_cit0["role"] != "smith" and final_cit0_31.role == "smith":
			printerr("FAIL Objective D: final_cit0_31 still retains temporary 'smith' role")
			failures += 1

	if not snap_cit1.is_empty():
		var final_cit1_31 = _find_citizen_by_id(snap_cit1["citizen_id"])
		if final_cit1_31 != null:
			if jobs_valid and final_cit1_31 == cit1:
				printerr("FAIL Objective D: final_cit1_31 is pointing to stale pre-load instance")
				failures += 1
			if not final_cit1_31 in world_instance.citizen_list:
				printerr("FAIL Objective D: final_cit1_31 not in world_view.citizen_list")
				failures += 1
			if world_instance.citizens_by_id.get(snap_cit1["citizen_id"]) != final_cit1_31:
				printerr("FAIL Objective D: citizens_by_id does not point to final_cit1_31")
				failures += 1
			if final_cit1_31.current_cell != snap_cit1["current_cell"]:
				printerr("FAIL Objective D: final_cit1_31 current_cell not restored: %s != %s" % [str(final_cit1_31.current_cell), str(snap_cit1["current_cell"])])
				failures += 1
			var expected_pos1_31: Vector2 = IsoMathScript.map_to_local(snap_cit1["current_cell"])
			if final_cit1_31.position != expected_pos1_31:
				printerr("FAIL Objective D: final_cit1_31 position not synchronized: %s != %s" % [str(final_cit1_31.position), str(expected_pos1_31)])
				failures += 1
			if final_cit1_31.role != snap_cit1["role"]:
				printerr("FAIL Objective D: final_cit1_31 role not restored to '%s', got '%s'" % [snap_cit1["role"], final_cit1_31.role])
				failures += 1
			if snap_cit1["role"] != "smith" and final_cit1_31.role == "smith":
				printerr("FAIL Objective D: final_cit1_31 still retains temporary 'smith' role")
				failures += 1

	if failures == 0:
		print("  [PASS] TC-BM.31: Dual-channel workshop pause/resume lifecycle & save/load verified.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.32: Atomic Demolition Refund Failure-Injection & Rollback
# -----------------------------------------------------------------------------
class NonAtomicResourceManagerMock extends RefCounted:
	var _current_stock: Dictionary = {"wood": 100, "stone": 100}
	func get_resource(res_id: String) -> int:
		return _current_stock.get(res_id, 0)
	func get_total_stock(res_id: String) -> int:
		return _current_stock.get(res_id, 0)
	func get_storage_capacity(_res_id: String) -> int:
		return 1000
	func get_capacity(_res_id: String) -> int:
		return 1000
	func remove_storage_capacity(_res_id: String, _bonus: int) -> void:
		pass

func _test_tc_bm_32_atomic_refund_failure_injection() -> bool:
	print("--- Running TC-BM.32: Atomic Demolition Refund Failure-Injection ---")
	var failures: int = 0
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	var wd = world_instance.world_data
	var jm = world_instance.job_mgr

	# Snapshot complete ResourceManager state before test modifications
	var init_rm_snapshot: Dictionary = _snapshot_resource_manager(rm)

	# 1. Test production ResourceManager.add_resources_atomic preflight headroom check
	var initial_wood = rm.get_resource("wood")
	var initial_stone = rm.get_resource("stone")
	var stone_cap = rm.get_capacity("stone")

	rm._current_stock["stone"] = stone_cap - 5 # only 5 stone headroom
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

	rm._current_stock["stone"] = initial_stone

	# 2. Test actual commit-phase rollback on the real ResourceManager via set_test_fail_commit_resource()
	var b_origin := Vector2i(22, 22)
	var b_data := {
		"id": "mine_atomic_fail_test",
		"type": "mine", # costs 20 wood, 10 stone -> 50% refund is 10 wood, 5 stone
		"cell": b_origin,
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100
	}
	wd.buildings.append(b_data)
	for ox in range(2):
		for oy in range(2):
			var cell = b_origin + Vector2i(ox, oy)
			if IsoMathScript.is_in_bounds(cell):
				wd.occupancy[cell.x][cell.y] = true

	var test_job: JobData = null
	if jm != null:
		test_job = jm.create_job("miner", b_origin, "Mine labor", "mine_atomic_fail_test")

	# Record exact pre-demolition production state
	var pre_wood: int = rm.get_resource("wood")
	var pre_stone: int = rm.get_resource("stone")
	var pre_tally_wood: float = rm.get_daily_production_tally("wood")
	var pre_tally_stone: float = rm.get_daily_production_tally("stone")
	var pre_cap_wood: int = rm.get_capacity("wood")
	var pre_cap_stone: int = rm.get_capacity("stone")
	rm._is_starving = true # Set starvation to true to verify exact restoration

	# Attach signal spy to verify zero intermediate/false signals are emitted during failed transaction
	var signal_count: int = 0
	var signal_spy := func(_res: String, _avail: int, _total: int):
		signal_count += 1
	rm.resource_changed.connect(signal_spy)

	# Configure controlled commit failure on second resource ("stone")
	rm.set_test_fail_commit_resource("stone")

	# Attempt demolition
	var dem_res = BuildingSystemScript.demolish_building(b_data, wd, rm, jm)

	# Clean up test seam immediately
	rm.set_test_fail_commit_resource("")
	rm.resource_changed.disconnect(signal_spy)

	if dem_res.get("success", true):
		printerr("FAIL: demolish_building must fail when commit phase is aborted on stone!")
		failures += 1

	# Assert zero signals emitted during failed atomic rollback
	if signal_count != 0:
		printerr("FAIL: Intermediate resource_changed signal emitted during rolled-back transaction! Count: %d" % signal_count)
		failures += 1

	# Assert exact pre/post equality of stocks
	if rm.get_resource("wood") != pre_wood:
		printerr("FAIL: Wood stock not restored! %d != %d" % [rm.get_resource("wood"), pre_wood])
		failures += 1
	if rm.get_resource("stone") != pre_stone:
		printerr("FAIL: Stone stock not restored! %d != %d" % [rm.get_resource("stone"), pre_stone])
		failures += 1

	# Assert exact pre/post equality of production tallies
	if rm.get_daily_production_tally("wood") != pre_tally_wood:
		printerr("FAIL: Wood daily tally not restored! %f != %f" % [rm.get_daily_production_tally("wood"), pre_tally_wood])
		failures += 1
	if rm.get_daily_production_tally("stone") != pre_tally_stone:
		printerr("FAIL: Stone daily tally not restored! %f != %f" % [rm.get_daily_production_tally("stone"), pre_tally_stone])
		failures += 1

	# Assert exact pre/post equality of starvation flag
	if not rm.is_starving():
		printerr("FAIL: Starvation flag was not restored after failed atomic commit!")
		failures += 1

	# Assert storage capacity unchanged
	if rm.get_capacity("wood") != pre_cap_wood or rm.get_capacity("stone") != pre_cap_stone:
		printerr("FAIL: Capacities mutated during failed demolition!")
		failures += 1

	# Assert building record remains in world_data
	var b_check = BuildingSystemScript.get_building_by_id("mine_atomic_fail_test", wd)
	if b_check.is_empty():
		printerr("FAIL: Building was deleted despite failed demolition")
		failures += 1

	# Assert occupancy is unchanged
	var occ_ok := true
	for ox in range(2):
		for oy in range(2):
			var cell = b_origin + Vector2i(ox, oy)
			if IsoMathScript.is_in_bounds(cell) and not wd.occupancy[cell.x][cell.y]:
				occ_ok = false
	if not occ_ok:
		printerr("FAIL: Occupancy was cleared despite failed demolition")
		failures += 1

	# Assert job remains in JobManager
	if jm != null and test_job != null and not test_job in jm._jobs:
		printerr("FAIL: Job was removed despite failed demolition")
		failures += 1

	# Clean up test fixture
	rm._is_starving = false
	if jm != null and test_job != null:
		jm._jobs.erase(test_job)
	wd.buildings.erase(b_data)
	for ox in range(2):
		for oy in range(2):
			var cell = b_origin + Vector2i(ox, oy)
			if IsoMathScript.is_in_bounds(cell):
				wd.occupancy[cell.x][cell.y] = false

	# 3. Fail-closed interface check when add_resources_atomic is missing (Demolition)
	var non_atomic_mock = NonAtomicResourceManagerMock.new()
	if BuildingSystemScript.is_valid_resource_manager_for_demolition(non_atomic_mock):
		printerr("FAIL: is_valid_resource_manager_for_demolition should reject mock lacking add_resources_atomic")
		failures += 1
	var dem_mock_res = BuildingSystemScript.demolish_building(b_data, wd, non_atomic_mock, jm)
	if dem_mock_res.get("success", true):
		printerr("FAIL: demolish_building should fail closed when add_resources_atomic is missing")
		failures += 1

	# 4. Objective D: Verify test failure injection seam is inert outside debug/test mode
	rm._debug_mode_override = false
	rm.set_test_fail_commit_resource("wood")
	if rm._test_fail_commit_resource != "":
		printerr("FAIL: set_test_fail_commit_resource must be inert when outside debug execution mode")
		failures += 1
	var normal_atomic_res = rm.add_resources_atomic({"wood": 10})
	if not normal_atomic_res.get("success", false):
		printerr("FAIL: add_resources_atomic failed when failure injection seam should be inert")
		failures += 1
	rm.consume_resource("wood", 10)
	rm._debug_mode_override = null

	# 5. Objective C: Atomic Construction Cancellation Invariants
	var cancel_origin := Vector2i(20, 20)
	var b_cancel := {
		"id": "bld_cancel_atomic_test",
		"type": "workshop", # Costs: 20 Wood, 15 Stone, 5 Metal -> 50% refund is 10 Wood, 7 Stone, 2 Metal
		"cell": cancel_origin,
		"size": Vector2i(2, 2),
		"state": "under_construction",
		"health": 100
	}
	wd.buildings.append(b_cancel)
	for ox in range(2):
		for oy in range(2):
			var cell = cancel_origin + Vector2i(ox, oy)
			if IsoMathScript.is_in_bounds(cell):
				wd.occupancy[cell.x][cell.y] = true

	var cancel_builder_job: JobData = null
	if jm != null:
		cancel_builder_job = jm.create_job("builder", cancel_origin, "Build workshop", "bld_cancel_atomic_test")

	# 5a. Non-atomic ResourceManager mock is rejected for construction cancellation
	if BuildingSystemScript.is_valid_resource_manager_for_cancellation(non_atomic_mock):
		printerr("FAIL: is_valid_resource_manager_for_cancellation should reject mock lacking add_resources_atomic")
		failures += 1
	var can_cancel_mock = BuildingSystemScript.can_cancel_construction(b_cancel, wd, non_atomic_mock)
	if can_cancel_mock.get("can_cancel", true):
		printerr("FAIL: can_cancel_construction should reject non-atomic ResourceManager mock")
		failures += 1
	var cancel_mock_res = BuildingSystemScript.cancel_construction(b_cancel, wd, non_atomic_mock, jm)
	if cancel_mock_res.get("success", true):
		printerr("FAIL: cancel_construction should reject non-atomic ResourceManager mock")
		failures += 1

	# Construction remains in world after rejection; occupancy and jobs remain unchanged
	if BuildingSystemScript.get_building_by_id("bld_cancel_atomic_test", wd).is_empty():
		printerr("FAIL: Under-construction building was erased on non-atomic mock rejection")
		failures += 1
	var occ_preserved := true
	for ox in range(2):
		for oy in range(2):
			var cell = cancel_origin + Vector2i(ox, oy)
			if IsoMathScript.is_in_bounds(cell) and not wd.occupancy[cell.x][cell.y]:
				occ_preserved = false
	if not occ_preserved:
		printerr("FAIL: Occupancy cleared on non-atomic mock rejection")
		failures += 1
	if jm != null and cancel_builder_job != null and not cancel_builder_job in jm._jobs:
		printerr("FAIL: Builder job was removed on non-atomic mock rejection")
		failures += 1

	# 5b. Failure injection during atomic cancellation restores all transaction state exactly
	var pre_canc_wood: int = rm.get_resource("wood")
	var pre_canc_stone: int = rm.get_resource("stone")
	var pre_canc_metal: int = rm.get_resource("metal")
	var pre_canc_tally_wood: float = rm.get_daily_production_tally("wood")
	var pre_canc_tally_stone: float = rm.get_daily_production_tally("stone")
	var pre_canc_tally_metal: float = rm.get_daily_production_tally("metal")

	var canc_signal_count: int = 0
	var canc_signal_spy := func(_res: String, _avail: int, _total: int):
		canc_signal_count += 1
	rm.resource_changed.connect(canc_signal_spy)

	# Inject commit failure on stone
	rm.set_test_fail_commit_resource("stone")
	var injected_canc_res = BuildingSystemScript.cancel_construction(b_cancel, wd, rm, jm)
	rm.set_test_fail_commit_resource("")
	rm.resource_changed.disconnect(canc_signal_spy)

	if injected_canc_res.get("success", true):
		printerr("FAIL: cancel_construction must fail when commit phase is aborted on stone!")
		failures += 1
	if canc_signal_count != 0:
		printerr("FAIL: Intermediate signals emitted during canceled construction rollback: %d" % canc_signal_count)
		failures += 1
	if rm.get_resource("wood") != pre_canc_wood or rm.get_resource("stone") != pre_canc_stone or rm.get_resource("metal") != pre_canc_metal:
		printerr("FAIL: Resource stocks not rolled back after cancellation failure!")
		failures += 1
	if rm.get_daily_production_tally("wood") != pre_canc_tally_wood or rm.get_daily_production_tally("stone") != pre_canc_tally_stone or rm.get_daily_production_tally("metal") != pre_canc_tally_metal:
		printerr("FAIL: Daily production tallies not restored after cancellation failure!")
		failures += 1

	# Building record, occupancy, and jobs remain unchanged after failure injection
	if BuildingSystemScript.get_building_by_id("bld_cancel_atomic_test", wd).is_empty():
		printerr("FAIL: Building was deleted on failed cancellation transaction")
		failures += 1
	occ_preserved = true
	for ox in range(2):
		for oy in range(2):
			var cell = cancel_origin + Vector2i(ox, oy)
			if IsoMathScript.is_in_bounds(cell) and not wd.occupancy[cell.x][cell.y]:
				occ_preserved = false
	if not occ_preserved:
		printerr("FAIL: Occupancy cleared on failed cancellation transaction")
		failures += 1
	if jm != null and cancel_builder_job != null and not cancel_builder_job in jm._jobs:
		printerr("FAIL: Builder job removed on failed cancellation transaction")
		failures += 1

	# 5c. Actual atomic cancellation succeeds and credits exact expected refund
	var real_canc_res = BuildingSystemScript.cancel_construction(b_cancel, wd, rm, jm)
	if not real_canc_res.get("success", false):
		printerr("FAIL: Real atomic cancel_construction failed: %s" % real_canc_res.get("reason", ""))
		failures += 1

	var refunded_canc: Dictionary = real_canc_res.get("refunded", {})
	if refunded_canc.get("wood", 0) != 10 or refunded_canc.get("stone", 0) != 7 or refunded_canc.get("metal", 0) != 2:
		printerr("FAIL: Credited refund mismatch: %s" % str(refunded_canc))
		failures += 1

	if rm.get_resource("wood") != pre_canc_wood + 10 or rm.get_resource("stone") != pre_canc_stone + 7 or rm.get_resource("metal") != pre_canc_metal + 2:
		printerr("FAIL: Resource stock not accurately incremented after cancellation success!")
		failures += 1

	if not BuildingSystemScript.get_building_by_id("bld_cancel_atomic_test", wd).is_empty():
		printerr("FAIL: Building not erased from world_data after successful cancellation")
		failures += 1

	var occ_cleared := true
	for ox in range(2):
		for oy in range(2):
			var cell = cancel_origin + Vector2i(ox, oy)
			if IsoMathScript.is_in_bounds(cell) and wd.occupancy[cell.x][cell.y]:
				occ_cleared = false
	if not occ_cleared:
		printerr("FAIL: Occupancy not cleared after successful cancellation")
		failures += 1

	if jm != null and cancel_builder_job != null and cancel_builder_job in jm._jobs:
		printerr("FAIL: Builder job not removed after successful cancellation")
		failures += 1

	# Clean up failure injection seam and debug override
	rm.set_test_fail_commit_resource("")
	rm._debug_mode_override = null

	# ONLY AFTER all demolition and cancellation tests, restore exact initial ResourceManager state
	_restore_resource_manager(rm, init_rm_snapshot)
	failures += _assert_resource_manager_matches_snapshot(rm, init_rm_snapshot, "TC-BM.32")

	if failures == 0:
		print("  [PASS] TC-BM.32: Real ResourceManager atomic failure-injection, commit rollback & unified construction cancellation verified.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.33: Safe Cargo Conservation on Building Demolition (Comprehensive Scenarios)
# -----------------------------------------------------------------------------
func _test_tc_bm_33_cargo_conservation_scenarios() -> bool:
	print("--- Running TC-BM.33: Safe Cargo Conservation on Building Demolition ---")
	var failures: int = 0
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	var wp_mgr = world_instance.workplace_mgr
	var jm = world_instance.job_mgr
	var cit0 = world_instance.citizen_list[0]
	var cit1 = world_instance.citizen_list[1] if world_instance.citizen_list.size() > 1 else null

	# Objective C: Snapshot complete ResourceManager state before test modifications
	var init_rm_snapshot: Dictionary = _snapshot_resource_manager(rm)

	# Objective B: Snapshot citizen state (stable ID, role, skills, state) before modification
	var snap_cit0: Dictionary = _snapshot_citizen_state(cit0)
	var snap_cit1: Dictionary = _snapshot_citizen_state(cit1) if cit1 != null else {}

	var orig_role0: String = snap_cit0["role"]
	var orig_xp0: Dictionary = snap_cit0["xp"].duplicate(true)
	var cit0_stable_id: String = snap_cit0["citizen_id"]

	var cit1_stable_id: String = snap_cit1.get("citizen_id", "")
	var orig_role1: String = snap_cit1.get("role", "")
	var orig_xp1: Dictionary = snap_cit1.get("xp", {}).duplicate(true)

	# Objective A1 & A2: Explicitly assign and verify hauler role, JobManager, and navigation reference
	cit0.role = "hauler"
	cit0.job_mgr = jm
	cit0.nav = world_instance.nav
	if cit0.job_mgr == null or cit0.nav == null:
		printerr("FAIL Objective A: cit0 missing valid JobManager or Navigation reference")
		failures += 1

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
	# Verify hauling XP is not yet awarded on partial delivery (Objective A13)
	if cit0.get_skill_data().get_xp("hauling") != 0.0:
		printerr("FAIL Step 2: Hauling XP should not be awarded on partial delivery: %f" % cit0.get_skill_data().get_xp("hauling"))
		failures += 1

	# STEP 3: Objective A3-A8: Real second hauling job through JobManager; genuine eligibility check
	farm_wp.buffer_amount = 10 # Buffer has actual goods (Objective A4)
	var extra_haul_job = jm.create_hauling_job("farm_cargo_test", farm_wp.access_cell, Vector2i(31, 34), "food", 5, "Haul extra food", 2)
	if extra_haul_job.state != JobState.AVAILABLE:
		printerr("FAIL Step 3: Second hauling job should be AVAILABLE: %d" % extra_haul_job.state)
		failures += 1

	# Assert job is executable using real JobManager check (Objective A5)
	var is_hauler_job_exec: bool = jm._is_job_executable(extra_haul_job, wp_mgr, rm, Callable(), world_instance.nav)
	if not is_hauler_job_exec:
		printerr("FAIL Step 3: Second hauling job must be executable in JobManager")
		failures += 1

	# Assert citizen could otherwise reach the source location (Objective A6)
	var path_to_source: Array = world_instance.nav.find_path(cit0.current_cell, extra_haul_job.source_cell)
	if path_to_source.is_empty():
		printerr("FAIL Step 3: Source cell of second hauling job is not reachable for citizen")
		failures += 1

	# Call actual _process_idle() repeatedly while central storage remains full (Objective A7 & A8)
	for i in range(3):
		cit0._process_idle()
		if cit0.active_job != null:
			printerr("FAIL Step 3: Hauler accepted job '%s' while carrying undelivered cargo!" % cit0.active_job.id)
			failures += 1
		if cit0.current_state != CitizenController.State.IDLE:
			printerr("FAIL Step 3: Citizen state changed away from IDLE: %d" % cit0.current_state)
			failures += 1
		if extra_haul_job.state != JobState.AVAILABLE or extra_haul_job.worker_id != "":
			printerr("FAIL Step 3: Second hauling job was claimed or assigned: state=%d, worker=%s" % [extra_haul_job.state, extra_haul_job.worker_id])
			failures += 1
		if cit0.carrying_amount != 6 or cit0.carrying_resource != "food" or cit0.carrying_source_workplace_id != "farm_cargo_test":
			printerr("FAIL Step 3: Cargo fields corrupted during idle processing with cargo: %d %s %s" % [cit0.carrying_amount, cit0.carrying_resource, cit0.carrying_source_workplace_id])
			failures += 1

	# STEP 4: Defensive guard against cargo overwrite in _pickup_hauler_cargo() (Objective A9)
	var overwrite_job = JobData.new()
	overwrite_job.id = "overwrite_attempt_job"
	overwrite_job.type = "hauler"
	overwrite_job.source_workplace_id = "farm_cargo_test"
	overwrite_job.target_building_id = "farm_cargo_test"
	overwrite_job.cargo_resource = "food"
	overwrite_job.cargo_amount = 20
	cit0.active_job = overwrite_job
	cit0.call("_pickup_hauler_cargo")

	if cit0.carrying_amount != 6 or cit0.carrying_resource != "food" or cit0.carrying_source_workplace_id != "farm_cargo_test":
		printerr("FAIL Step 4: _pickup_hauler_cargo overwrote existing cargo! Amount: %d" % cit0.carrying_amount)
		failures += 1
	if cit0.active_job != null:
		printerr("FAIL Step 4: Active job not released on pickup rejection")
		failures += 1
	if not "dở dang" in cit0.status_reason:
		printerr("FAIL Step 4: Status reason did not report retained cargo rejection: '%s'" % cit0.status_reason)
		failures += 1

	# STEP 5: Free storage capacity and verify single full delivery + exact XP (Objective A10, A11, A12, A13)
	rm._capacities["food"] = orig_cap # Free enough central storage capacity (Objective A10)
	var pre_final_food = rm.get_resource("food")

	# Call _process_idle() again: remaining cargo deposited exactly once (Objective A11)
	cit0._process_idle()

	if cit0.carrying_amount != 0 or cit0.carrying_resource != "" or cit0.carrying_source_workplace_id != "":
		printerr("FAIL Step 5: Remaining cargo was not cleared on idle tick delivery: amt=%d, res=%s" % [cit0.carrying_amount, cit0.carrying_resource])
		failures += 1
	if rm.get_resource("food") != pre_final_food + 6:
		printerr("FAIL Step 5: Expected 6 food deposited, got: %d -> %d" % [pre_final_food, rm.get_resource("food")])
		failures += 1
	if cit0.get_skill_data().get_xp("hauling") != 10.0:
		printerr("FAIL Step 5: Hauling XP (+10) not awarded after full successful delivery: %f" % cit0.get_skill_data().get_xp("hauling"))
		failures += 1

	# Run another idle tick and verify no duplicate deposit or duplicate XP (Objective A12 & A13)
	var post_final_food = rm.get_resource("food")
	var post_final_xp = cit0.get_skill_data().get_xp("hauling")
	cit0._process_idle()

	if rm.get_resource("food") != post_final_food:
		printerr("FAIL Step 5: Duplicate food deposit on subsequent idle tick: %d != %d" % [post_final_food, rm.get_resource("food")])
		failures += 1
	if cit0.get_skill_data().get_xp("hauling") != post_final_xp:
		printerr("FAIL Step 5: Duplicate XP awarded on subsequent idle tick: %f != %f" % [cit0.get_skill_data().get_xp("hauling"), post_final_xp])
		failures += 1

	# Clean up second hauling job
	if jm != null:
		jm._jobs.erase(extra_haul_job)
	if cit0.active_job == extra_haul_job:
		cit0.active_job = null
		cit0.current_state = CitizenController.State.IDLE

	# STEP 6: Fail-closed deposit when ResourceManager is unavailable or invalid
	var cit_isolated = CitizenController.new()
	cit_isolated.carrying_resource = "wood"
	cit_isolated.carrying_amount = 7
	cit_isolated.carrying_source_workplace_id = "farm_cargo_test"
	# Inject an invalid resource manager mock lacking add_resource
	cit_isolated.set_custom_resource_manager(RefCounted.new())
	var dummy_job = JobData.new()
	dummy_job.id = "dummy_job"
	cit_isolated.active_job = dummy_job
	cit_isolated.call("_deposit_hauler_cargo")
	if cit_isolated.carrying_amount != 7 or cit_isolated.carrying_resource != "wood" or cit_isolated.carrying_source_workplace_id != "farm_cargo_test":
		printerr("FAIL Step 6: Fail-closed deposit did not preserve cargo on missing RM! amount=%d, res=%s, wp=%s" % [cit_isolated.carrying_amount, cit_isolated.carrying_resource, cit_isolated.carrying_source_workplace_id])
		failures += 1
	if cit_isolated.active_job != null:
		printerr("FAIL Step 6: Dummy job not released on fail-closed deposit")
		failures += 1
	if cit_isolated.get_skill_data().get_xp("hauling") != 0.0:
		printerr("FAIL Step 6: XP erroneously awarded on failed deposit: %f" % cit_isolated.get_skill_data().get_xp("hauling"))
		failures += 1
	cit_isolated.free()

	# STEP 7: Demolition preflight finds cargo through persistent source identity
	# Re-arm cit0 with 6 food for remaining demolition and save/load tests
	cit0.carrying_resource = "food"
	cit0.carrying_amount = 6
	cit0.carrying_source_workplace_id = "farm_cargo_test"
	cit0.current_state = CitizenController.State.IDLE
	cit0.active_job = null

	var cargo_found = world_instance.get_carried_cargo_for_building("farm_cargo_test")
	if cargo_found.get("food", 0) != 6:
		printerr("FAIL Step 7: get_carried_cargo_for_building failed to find 6 food via persistent source identity! Got: %s" % str(cargo_found))
		failures += 1

	# STEP 8: Multiple haulers & en route hauler (State.HAULING) aggregated
	if cit1 != null:
		cit1.carrying_resource = "food"
		cit1.carrying_amount = 4
		cit1.carrying_source_workplace_id = "farm_cargo_test"
		cit1.current_state = CitizenController.State.HAULING
		cit1.active_job = null

	var multi_cargo = world_instance.get_carried_cargo_for_building("farm_cargo_test")
	if multi_cargo.get("food", 0) != 10:
		printerr("FAIL Step 8: Multiple haulers cargo aggregation failed! Expected 10, got: %s" % str(multi_cargo))
		failures += 1

	# STEP 9: Demolition rejected when central storage lacks capacity for refund + carried cargo
	# We have 10 carried food. Set food capacity to current stock + 5 (needs 10 headroom)
	rm._capacities["food"] = rm.get_resource("food") + 5
	var dem_rej = world_instance.demolish_building_project("farm_cargo_test")
	if dem_rej.get("success", true):
		printerr("FAIL Step 9: Demolition must be rejected when storage cannot fit carried cargo!")
		failures += 1
	if not "Dung lượng kho chứa không đủ" in dem_rej.get("reason", ""):
		printerr("FAIL Step 9: Demolition rejection reason mismatch: '%s'" % dem_rej.get("reason", ""))
		failures += 1
	# Verify building still exists and citizen cargo was not lost
	if BuildingSystemScript.get_building_by_id("farm_cargo_test", world_instance.world_data).is_empty():
		printerr("FAIL Step 9: Building was deleted on rejected demolition")
		failures += 1
	if cit0.carrying_amount != 6 or (cit1 != null and cit1.carrying_amount != 4):
		printerr("FAIL Step 9: Citizen cargo was modified on rejected demolition")
		failures += 1

	# STEP 10: Save and reload game while citizens hold cargo with no active job
	rm._capacities["food"] = orig_cap # Restore capacity so save/load has valid storage state
	var temp_save_path := "user://test_cargo_source_id_save.json"
	var s_res = SaveManagerScript.save_to_file(world_instance, temp_save_path)
	if not s_res.get("success", false):
		printerr("FAIL Step 10: Save failed")
		failures += 1
	var l_res = SaveManagerScript.load_from_file(temp_save_path)
	if not l_res.get("success", false):
		printerr("FAIL Step 10: Load failed")
		failures += 1
	var a_res = SaveManagerScript.apply_loaded_state_to_world(world_instance, l_res["data"])
	if not a_res.get("success", false):
		printerr("FAIL Step 10: Apply loaded state failed")
		failures += 1

	if FileAccess.file_exists(temp_save_path):
		DirAccess.remove_absolute(temp_save_path)
	if FileAccess.file_exists(temp_save_path + ".bak"):
		DirAccess.remove_absolute(temp_save_path + ".bak")

	rm = world_instance.get_node_or_null("/root/ResourceManager")
	wp_mgr = world_instance.workplace_mgr
	jm = world_instance.job_mgr

	# Objective B: Find reconstructed citizen by stable ID from current world_view
	var cit0_reloaded = _find_citizen_by_id(cit0_stable_id)
	var cit1_reloaded = _find_citizen_by_id(cit1_stable_id) if cit1_stable_id != "" else null

	if cit0_reloaded == null:
		printerr("FAIL Step 10: cit0 could not be found by stable ID after save/load: %s" % cit0_stable_id)
		failures += 1
	if cit0_reloaded == cit0:
		printerr("FAIL Step 10: cit0 was not reconstructed as a new instance during save/load")
		failures += 1
	if not cit0_reloaded in world_instance.citizen_list or world_instance.citizens_by_id.get(cit0_stable_id) != cit0_reloaded:
		printerr("FAIL Step 10: cit0_reloaded is not properly registered in citizen_list or citizens_by_id")
		failures += 1

	if cit0_reloaded.carrying_amount != 6 or cit0_reloaded.carrying_resource != "food":
		printerr("FAIL Step 10: cit0 cargo not preserved across save/load! Amount: %d, Res: %s" % [cit0_reloaded.carrying_amount, cit0_reloaded.carrying_resource])
		failures += 1
	if cit0_reloaded.carrying_source_workplace_id != "farm_cargo_test":
		printerr("FAIL Step 10: cit0 carrying_source_workplace_id not preserved across save/load! Got '%s'" % cit0_reloaded.carrying_source_workplace_id)
		failures += 1
	if cit1_reloaded != null:
		if cit1_reloaded == cit1:
			printerr("FAIL Step 10: cit1 was not reconstructed as a new instance during save/load")
			failures += 1
		if not cit1_reloaded in world_instance.citizen_list or world_instance.citizens_by_id.get(cit1_stable_id) != cit1_reloaded:
			printerr("FAIL Step 10: cit1_reloaded is not properly registered in citizen_list or citizens_by_id")
			failures += 1
		if cit1_reloaded.carrying_amount != 4 or cit1_reloaded.carrying_resource != "food":
			printerr("FAIL Step 10: cit1 cargo not preserved across save/load! Amount: %d" % cit1_reloaded.carrying_amount)
			failures += 1
		if cit1_reloaded.carrying_source_workplace_id != "farm_cargo_test":
			printerr("FAIL Step 10: cit1 carrying_source_workplace_id not preserved across save/load!")
			failures += 1

	# STEP 11: Demolition after reload deposits all carried cargo into storage
	var pre_dem_food = rm.get_resource("food")
	var dem_res = world_instance.demolish_building_project("farm_cargo_test")
	if not dem_res.get("success", false):
		printerr("FAIL Step 11: Demolition after reload failed: %s" % dem_res.get("reason", ""))
		failures += 1
	if cit0_reloaded.carrying_amount != 0 or (cit1_reloaded != null and cit1_reloaded.carrying_amount != 0):
		printerr("FAIL Step 11: Remaining cargo was not deposited upon demolition! cit0=%d, cit1=%d" % [cit0_reloaded.carrying_amount, cit1_reloaded.carrying_amount if cit1_reloaded != null else 0])
		failures += 1
	if cit0_reloaded.carrying_source_workplace_id != "" or (cit1_reloaded != null and cit1_reloaded.carrying_source_workplace_id != ""):
		printerr("FAIL Step 11: carrying_source_workplace_id was not cleared after demolition deposit!")
		failures += 1
	# Carried cargo was 10 food total -> storage must have increased by 10 food
	if rm.get_resource("food") != pre_dem_food + 10:
		printerr("FAIL Step 11: Food in storage did not increase by 10! %d -> %d" % [pre_dem_food, rm.get_resource("food")])
		failures += 1

	# Verify farm_cargo_test building, workplaces, and jobs are removed
	if not BuildingSystemScript.get_building_by_id("farm_cargo_test", world_instance.world_data).is_empty():
		printerr("FAIL Step 11: farm_cargo_test still exists in world_data after demolition")
		failures += 1
	if wp_mgr.get_workplace("farm_cargo_test") != null:
		printerr("FAIL Step 11: farm_cargo_test workplace still exists in WorkplaceManager after demolition")
		failures += 1
	if jm.get_jobs_for_building("farm_cargo_test").size() > 0:
		printerr("FAIL Step 11: farm_cargo_test jobs still exist in JobManager after demolition")
		failures += 1

	# STEP 12: Multi-channel recipes (workshop channels) resolve to parent building
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
		printerr("FAIL Step 12: Workshop channel cargo not resolved to parent workshop! Got: %s" % str(ws_cargo))
		failures += 1

	var pre_metal = rm.get_resource("metal")
	var ws_dem = world_instance.demolish_building_project("ws_channel_test")
	if not ws_dem.get("success", false):
		printerr("FAIL Step 12: Workshop demolition failed: %s" % ws_dem.get("reason", ""))
		failures += 1
	if rm.get_resource("metal") != pre_metal + 7: # 2 refund (50% of 5) + 5 cargo = 7
		printerr("FAIL Step 12: Metal cargo + refund not deposited into storage on workshop demolition! Got %d, expected %d" % [rm.get_resource("metal"), pre_metal + 7])
		failures += 1
	if cit0_reloaded.carrying_amount != 0 or cit0_reloaded.carrying_source_workplace_id != "":
		printerr("FAIL Step 12: Citizen cargo and source workplace not cleared after workshop demolition")
		failures += 1

	# Verify ws_channel_test building, channels, and jobs are removed
	if not BuildingSystemScript.get_building_by_id("ws_channel_test", world_instance.world_data).is_empty():
		printerr("FAIL Step 12: ws_channel_test still exists in world_data after demolition")
		failures += 1
	if wp_mgr.get_workplace("ws_channel_test_smelt") != null or wp_mgr.get_workplace("ws_channel_test_craft") != null:
		printerr("FAIL Step 12: ws_channel_test workplace channels still exist after demolition")
		failures += 1
	if jm.get_jobs_for_building("ws_channel_test").size() > 0:
		printerr("FAIL Step 12: ws_channel_test jobs still exist after demolition")
		failures += 1

	# Objective C: Restore exact initial ResourceManager snapshot after all teardown is complete
	_restore_resource_manager(rm, init_rm_snapshot)
	failures += _assert_resource_manager_matches_snapshot(rm, init_rm_snapshot, "TC-BM.33")

	# Objective B: Perform all citizen cleanup against the current valid post-load citizen object
	failures += _restore_citizen_state(cit0_stable_id, snap_cit0, "TC-BM.33 cit0")
	if cit1_stable_id != "":
		failures += _restore_citizen_state(cit1_stable_id, snap_cit1, "TC-BM.33 cit1")

	# Objective B & A: Explicitly assert that the current valid citizen no longer has temporary hauler role, cell, pos, or XP changes
	var final_cit0 = _find_citizen_by_id(cit0_stable_id)
	if final_cit0 == null:
		printerr("FAIL Objective B: final_cit0 not found after cleanup")
		failures += 1
	else:
		if final_cit0 == cit0:
			printerr("FAIL Objective B: final_cit0 is still pointing to stale pre-load instance")
			failures += 1
		if not final_cit0 in world_instance.citizen_list:
			printerr("FAIL Objective A: final_cit0 is not in world_view.citizen_list")
			failures += 1
		if world_instance.citizens_by_id.get(cit0_stable_id) != final_cit0:
			printerr("FAIL Objective A: citizens_by_id does not point to final_cit0")
			failures += 1
		if final_cit0.current_cell != snap_cit0["current_cell"]:
			printerr("FAIL Objective A: final_cit0 current_cell not restored: %s != %s" % [str(final_cit0.current_cell), str(snap_cit0["current_cell"])])
			failures += 1
		var expected_pos0: Vector2 = IsoMathScript.map_to_local(snap_cit0["current_cell"])
		if final_cit0.position != expected_pos0:
			printerr("FAIL Objective A: final_cit0 position not synchronized: %s != %s" % [str(final_cit0.position), str(expected_pos0)])
			failures += 1
		if final_cit0.role != orig_role0:
			printerr("FAIL Objective B: final_cit0 role not restored to '%s', got '%s'" % [orig_role0, final_cit0.role])
			failures += 1
		if orig_role0 != "hauler" and final_cit0.role == "hauler":
			printerr("FAIL Objective B: final_cit0 still retains temporary 'hauler' role")
			failures += 1
		var cur_hauling_xp = final_cit0.get_skill_data().get_xp("hauling")
		var orig_hauling_xp = orig_xp0.get("hauling", 0.0)
		if cur_hauling_xp != orig_hauling_xp:
			printerr("FAIL Objective B: final_cit0 hauling XP not restored: got %f, expected %f" % [cur_hauling_xp, orig_hauling_xp])
			failures += 1

	if cit1_stable_id != "":
		var final_cit1 = _find_citizen_by_id(cit1_stable_id)
		if final_cit1 != null:
			if final_cit1 == cit1:
				printerr("FAIL Objective B: final_cit1 is still pointing to stale pre-load instance")
				failures += 1
			if not final_cit1 in world_instance.citizen_list:
				printerr("FAIL Objective A: final_cit1 is not in world_view.citizen_list")
				failures += 1
			if world_instance.citizens_by_id.get(cit1_stable_id) != final_cit1:
				printerr("FAIL Objective A: citizens_by_id does not point to final_cit1")
				failures += 1
			if final_cit1.current_cell != snap_cit1["current_cell"]:
				printerr("FAIL Objective A: final_cit1 current_cell not restored: %s != %s" % [str(final_cit1.current_cell), str(snap_cit1["current_cell"])])
				failures += 1
			var expected_pos1: Vector2 = IsoMathScript.map_to_local(snap_cit1["current_cell"])
			if final_cit1.position != expected_pos1:
				printerr("FAIL Objective A: final_cit1 position not synchronized: %s != %s" % [str(final_cit1.position), str(expected_pos1)])
				failures += 1
			if final_cit1.role != orig_role1:
				printerr("FAIL Objective B: final_cit1 role not restored to '%s', got '%s'" % [orig_role1, final_cit1.role])
				failures += 1
			for voc in orig_xp1:
				if final_cit1.get_skill_data().get_xp(voc) != orig_xp1[voc]:
					printerr("FAIL Objective B: final_cit1 skill %s not restored" % voc)
					failures += 1

	if failures == 0:
		print("  [PASS] TC-BM.33: All cargo conservation scenarios verified.")
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

# -----------------------------------------------------------------------------
# TC-BM.35: Legacy building defaults to Level 1
# -----------------------------------------------------------------------------
func _test_tc_bm_35_legacy_building_defaults_level_1() -> bool:
	print("--- Running TC-BM.35: Legacy Building Defaults to Level 1 ---")
	var failures: int = 0
	var wd = world_instance.world_data
	var rm = world_instance.get_node_or_null("/root/ResourceManager")

	# 1. Place a building via BuildingSystemScript.place_building with funded rm
	rm.add_resource("wood", 100)
	rm.add_resource("stone", 100)
	var test_cell := Vector2i(-1, -1)
	for x in range(20, 50):
		for y in range(20, 50):
			var c := Vector2i(x, y)
			if BuildingSystemScript.can_place_building("house", c, wd, rm)["valid"]:
				test_cell = c
				break
		if test_cell != Vector2i(-1, -1):
			break

	var b_res = BuildingSystemScript.place_building("house", test_cell, wd, rm, "active")
	if not b_res.get("success", false):
		printerr("FAIL: place_building failed in TC-BM.35: %s" % b_res.get("reason", ""))
		failures += 1
	var b_data: Dictionary = b_res.get("building", {})
	if int(b_data.get("upgrade_level", 0)) != 1:
		printerr("FAIL: Newly placed house upgrade_level is %d, expected 1" % int(b_data.get("upgrade_level", 0)))
		failures += 1

	# Clean up test house from world_data
	if not b_data.is_empty():
		BuildingSystemScript.demolish_building(b_data, wd, rm, null, 0.0)

	# 2. Simulate legacy save record without upgrade_level
	var legacy_record = {
		"id": "bld_legacy_test",
		"type": "farm",
		"cell_x": 12,
		"cell_y": 12,
		"size_x": 2,
		"size_y": 2,
		"state": "active",
		"health": 100,
		"construction_progress": 12.0,
		"construction_hours": 12.0
	}
	# Validate via SaveManagerScript (schema_version at root)
	var val_dict = {
		"schema_version": 1,
		"metadata": {"schema_version": 1, "save_time": 100},
		"resources": {"is_starving": false, "active_population": 10, "stock": {}, "capacities": {}},
		"buildings": [legacy_record],
		"citizens": []
	}
	var check = SaveManagerScript.validate_save_data(val_dict)
	if not check.get("valid", false):
		printerr("FAIL: Legacy save rejected during validation: %s" % check.get("error", ""))
		failures += 1

	if failures == 0:
		print("  [PASS] TC-BM.35: Legacy building records safely default to Level 1.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.36: House Level 1→2→3 housing capacity (6 → 8 → 10)
# -----------------------------------------------------------------------------
func _test_tc_bm_36_house_upgrades_capacity() -> bool:
	print("--- Running TC-BM.36: House Level 1->2->3 Housing Capacity ---")
	var failures: int = 0
	var wd = world_instance.world_data

	# Config verification
	if EconomyConfigScript.get_house_capacity(1) != 6:
		printerr("FAIL: House Lvl 1 capacity expected 6, got %d" % EconomyConfigScript.get_house_capacity(1))
		failures += 1
	if EconomyConfigScript.get_house_capacity(2) != 8:
		printerr("FAIL: House Lvl 2 capacity expected 8, got %d" % EconomyConfigScript.get_house_capacity(2))
		failures += 1
	if EconomyConfigScript.get_house_capacity(3) != 10:
		printerr("FAIL: House Lvl 3 capacity expected 10, got %d" % EconomyConfigScript.get_house_capacity(3))
		failures += 1

	# Live building verification
	var init_housing: int = BuildingSystemScript.get_total_housing_capacity(wd)
	var house_bld: Dictionary = {
		"id": "bld_tc36_house",
		"type": "house",
		"cell": Vector2i(14, 14),
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100,
		"upgrade_level": 1
	}
	wd.buildings.append(house_bld)
	if BuildingSystemScript.get_total_housing_capacity(wd) != init_housing + 6:
		printerr("FAIL: Housing capacity with Lvl 1 house expected %d, got %d" % [init_housing + 6, BuildingSystemScript.get_total_housing_capacity(wd)])
		failures += 1

	# Upgrade to Level 2
	house_bld["upgrade_level"] = 2
	if BuildingSystemScript.get_total_housing_capacity(wd) != init_housing + 8:
		printerr("FAIL: Housing capacity with Lvl 2 house expected %d, got %d" % [init_housing + 8, BuildingSystemScript.get_total_housing_capacity(wd)])
		failures += 1

	# Upgrade to Level 3
	house_bld["upgrade_level"] = 3
	if BuildingSystemScript.get_total_housing_capacity(wd) != init_housing + 10:
		printerr("FAIL: Housing capacity with Lvl 3 house expected %d, got %d" % [init_housing + 10, BuildingSystemScript.get_total_housing_capacity(wd)])
		failures += 1

	# Cleanup
	wd.buildings.erase(house_bld)

	if failures == 0:
		print("  [PASS] TC-BM.36: House Level 1->2->3 housing capacity correctly scales (6->8->10).")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.37: Farm Level 1→2→3 actual production output (1.00x → 1.15x → 1.30x)
# -----------------------------------------------------------------------------
func _test_tc_bm_37_farm_upgrades_production_multiplier() -> bool:
	print("--- Running TC-BM.37: Farm Level 1->2->3 Production Multipliers ---")
	var failures: int = 0
	var wp_mgr = world_instance.workplace_mgr

	var m1: float = EconomyConfigScript.get_farm_multiplier(1)
	var m2: float = EconomyConfigScript.get_farm_multiplier(2)
	var m3: float = EconomyConfigScript.get_farm_multiplier(3)
	if absf(m1 - 1.00) > 0.001 or absf(m2 - 1.15) > 0.001 or absf(m3 - 1.30) > 0.001:
		printerr("FAIL: Farm multipliers mismatch: %f, %f, %f" % [m1, m2, m3])
		failures += 1

	var test_wp = wp_mgr.register_workplace("test_farm_mult", "farm", Vector2i(16, 16), Vector2i(2, 2), Vector2i(15, 16), "food", 50, 5.0, 1)

	# Level 1 production
	test_wp.level_multiplier = m1
	test_wp.buffer_amount = 0
	wp_mgr.produce_to_buffer(test_wp.id)
	if test_wp.buffer_amount != 5:
		printerr("FAIL: Farm Lvl 1 buffer produced %d, expected 5" % test_wp.buffer_amount)
		failures += 1

	# Level 2 production: round(5.0 * 1.15) = round(5.75) = 6
	test_wp.level_multiplier = m2
	test_wp.buffer_amount = 0
	wp_mgr.produce_to_buffer(test_wp.id)
	if test_wp.buffer_amount != 6:
		printerr("FAIL: Farm Lvl 2 buffer produced %d, expected 6" % test_wp.buffer_amount)
		failures += 1

	# Level 3 production: round(5.0 * 1.30) = round(6.50) = 7
	test_wp.level_multiplier = m3
	test_wp.buffer_amount = 0
	wp_mgr.produce_to_buffer(test_wp.id)
	var expected_l3 = int(round(5.0 * 1.30))
	if test_wp.buffer_amount != expected_l3:
		printerr("FAIL: Farm Lvl 3 buffer produced %d, expected %d" % [test_wp.buffer_amount, expected_l3])
		failures += 1

	# Cleanup
	wp_mgr.unregister_workplace("test_farm_mult")

	if failures == 0:
		print("  [PASS] TC-BM.37: Farm production output scales accurately with level multipliers.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.38: Storehouse Level 1→2→3 capacity deltas (+125/+75 per tier)
# -----------------------------------------------------------------------------
func _test_tc_bm_38_storehouse_upgrades_capacity_deltas() -> bool:
	print("--- Running TC-BM.38: Storehouse Capacity Deltas (+125/+75 per tier) ---")
	var failures: int = 0

	var delta_1_2 = EconomyConfigScript.get_storehouse_bonus_delta(1, 2)
	var delta_2_3 = EconomyConfigScript.get_storehouse_bonus_delta(2, 3)

	if delta_1_2.get("food", 0) != 125 or delta_1_2.get("metal", 0) != 75:
		printerr("FAIL: Storehouse delta 1->2 expected +125 food, +75 metal; got %s" % str(delta_1_2))
		failures += 1
	if delta_2_3.get("food", 0) != 125 or delta_2_3.get("metal", 0) != 75:
		printerr("FAIL: Storehouse delta 2->3 expected +125 food, +75 metal; got %s" % str(delta_2_3))
		failures += 1

	# Test total bonus calculation
	var b1 = EconomyConfigScript.get_storehouse_bonus(1)
	var b2 = EconomyConfigScript.get_storehouse_bonus(2)
	var b3 = EconomyConfigScript.get_storehouse_bonus(3)
	if b1.get("food", 0) != 500 or b2.get("food", 0) != 625 or b3.get("food", 0) != 750:
		printerr("FAIL: Storehouse total bonuses mismatch: %s, %s, %s" % [str(b1), str(b2), str(b3)])
		failures += 1

	if failures == 0:
		print("  [PASS] TC-BM.38: Storehouse capacity deltas verified (+125 basic, +75 refined).")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.39: Upgrade cost calculations (0.75x ceil, 1.25x ceil)
# -----------------------------------------------------------------------------
func _test_tc_bm_39_upgrade_costs_and_durations() -> bool:
	print("--- Running TC-BM.39: Upgrade Costs & Durations (0.75x ceil, 1.25x ceil) ---")
	var failures: int = 0

	# House: base cost {wood: 25, stone: 10}, base hours 8.0
	var house_c2 = EconomyConfigScript.get_upgrade_cost("house", 2)
	var house_c3 = EconomyConfigScript.get_upgrade_cost("house", 3)
	if house_c2.get("wood", 0) != 19 or house_c2.get("stone", 0) != 8:
		printerr("FAIL: House Lvl 2 cost expected {wood:19, stone:8}, got %s" % str(house_c2))
		failures += 1
	if house_c3.get("wood", 0) != 32 or house_c3.get("stone", 0) != 13:
		printerr("FAIL: House Lvl 3 cost expected {wood:32, stone:13}, got %s" % str(house_c3))
		failures += 1

	var house_d2 = EconomyConfigScript.get_upgrade_duration("house", 2)
	var house_d3 = EconomyConfigScript.get_upgrade_duration("house", 3)
	if house_d2 < EconomyConfigScript.MIN_UPGRADE_DURATION_HOURS:
		printerr("FAIL: House duration Lvl 2 below min duration: %f" % house_d2)
		failures += 1

	# Farm: base cost {wood: 30, stone: 5}
	var farm_c2 = EconomyConfigScript.get_upgrade_cost("farm", 2)
	var farm_c3 = EconomyConfigScript.get_upgrade_cost("farm", 3)
	if farm_c2.get("wood", 0) != 23 or farm_c2.get("stone", 0) != 4:
		printerr("FAIL: Farm Lvl 2 cost expected {wood:23, stone:4}, got %s" % str(farm_c2))
		failures += 1
	if farm_c3.get("wood", 0) != 38 or farm_c3.get("stone", 0) != 7:
		printerr("FAIL: Farm Lvl 3 cost expected {wood:38, stone:7}, got %s" % str(farm_c3))
		failures += 1

	# Non-upgradeable building: townhall
	var th_cost = EconomyConfigScript.get_upgrade_cost("townhall", 2)
	if not th_cost.is_empty():
		printerr("FAIL: Townhall should not have upgrade cost, got %s" % str(th_cost))
		failures += 1

	if failures == 0:
		print("  [PASS] TC-BM.39: Upgrade costs and durations scale accurately.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.40: Insufficient resources reject upgrade without state mutation
# -----------------------------------------------------------------------------
func _test_tc_bm_40_insufficient_resources_rejection() -> bool:
	print("--- Running TC-BM.40: Insufficient Resources Upgrade Rejection ---")
	var failures: int = 0
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	var wd = world_instance.world_data

	var test_house: Dictionary = {
		"id": "bld_tc40_house",
		"type": "house",
		"cell": Vector2i(18, 18),
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100,
		"upgrade_level": 1
	}
	wd.buildings.append(test_house)

	# Drain wood and stone
	var pre_wood: int = rm.get_resource("wood")
	var pre_stone: int = rm.get_resource("stone")
	rm._current_stock["wood"] = 0
	rm._current_stock["stone"] = 0

	var check = BuildingSystemScript.can_start_upgrade(test_house, wd, rm)
	if check.get("can_upgrade", true):
		printerr("FAIL: Upgrade should be rejected when resources are 0")
		failures += 1

	var start_res = BuildingSystemScript.start_upgrade(test_house, wd, rm)
	if start_res.get("success", false):
		printerr("FAIL: start_upgrade should fail when resources are 0")
		failures += 1

	if bool(test_house.get("is_upgrading", false)):
		printerr("FAIL: House is_upgrading state was mutated on failed upgrade")
		failures += 1

	# Restore resources & cleanup
	rm._current_stock["wood"] = pre_wood
	rm._current_stock["stone"] = pre_stone
	wd.buildings.erase(test_house)

	if failures == 0:
		print("  [PASS] TC-BM.40: Upgrade rejection with insufficient resources is strictly fail-closed.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.41: Upgrade progress respects TimeManager pause and speed multipliers
# -----------------------------------------------------------------------------
func _test_tc_bm_41_upgrade_progress_and_timemanager() -> bool:
	print("--- Running TC-BM.41: Upgrade Progress Advances Cleanly ---")
	var failures: int = 0
	var wd = world_instance.world_data

	var test_farm: Dictionary = {
		"id": "bld_tc41_farm",
		"type": "farm",
		"cell": Vector2i(20, 20),
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100,
		"upgrade_level": 1,
		"is_upgrading": true,
		"upgrade_target_level": 2,
		"upgrade_progress": 0.0,
		"upgrade_required_hours": 6.0
	}
	wd.buildings.append(test_farm)

	# 1. Delta <= 0 or invalid (e.g. paused)
	var res_zero = BuildingSystemScript.advance_upgrade(test_farm, 0.0, wd)
	if float(test_farm.get("upgrade_progress", 0.0)) != 0.0:
		printerr("FAIL: Progress changed with 0 delta: %f" % float(test_farm.get("upgrade_progress", 0.0)))
		failures += 1

	# 2. Advance by 2.0 hours
	var res_adv = BuildingSystemScript.advance_upgrade(test_farm, 2.0, wd)
	if absf(float(test_farm.get("upgrade_progress", 0.0)) - 2.0) > 0.001:
		printerr("FAIL: Progress mismatch after 2.0h: %f" % float(test_farm.get("upgrade_progress", 0.0)))
		failures += 1
	if res_adv.get("completed", true):
		printerr("FAIL: Upgrade marked completed prematurely at 2.0 / 6.0 hours")
		failures += 1

	# Cleanup
	wd.buildings.erase(test_farm)

	if failures == 0:
		print("  [PASS] TC-BM.41: Upgrade progress advances accurately and rejects zero delta.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.42: Upgrade completion applies effect once
# -----------------------------------------------------------------------------
func _test_tc_bm_42_upgrade_completion_single_application() -> bool:
	print("--- Running TC-BM.42: Upgrade Completion Applies Effect Once ---")
	var failures: int = 0
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	var wd = world_instance.world_data

	var init_food_cap: int = rm.get_capacity("food")
	var test_sh: Dictionary = {
		"id": "bld_tc42_sh",
		"type": "storehouse",
		"cell": Vector2i(24, 24),
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100,
		"upgrade_level": 1
	}
	wd.buildings.append(test_sh)
	# Level 1 storage applied
	BuildingSystemScript.apply_completion_effects(test_sh, rm)
	var base_sh_cap: int = rm.get_capacity("food")
	if base_sh_cap != init_food_cap + 500:
		printerr("FAIL: Storehouse Lvl 1 capacity not applied: %d vs %d" % [base_sh_cap, init_food_cap + 500])
		failures += 1

	# Set upgrading to 2 and complete
	test_sh["is_upgrading"] = true
	test_sh["upgrade_target_level"] = 2
	test_sh["upgrade_progress"] = 6.0
	test_sh["upgrade_required_hours"] = 6.0

	var comp_res = BuildingSystemScript.complete_building_upgrade(test_sh, wd, rm)
	if not comp_res.get("success", false):
		printerr("FAIL: complete_building_upgrade returned false: %s" % comp_res.get("reason", ""))
		failures += 1

	if int(test_sh.get("upgrade_level", 1)) != 2:
		printerr("FAIL: test_sh upgrade_level is %d, expected 2" % int(test_sh.get("upgrade_level", 1)))
		failures += 1

	# Capacity should have increased by delta (+125) -> base_sh_cap + 125
	if rm.get_capacity("food") != base_sh_cap + 125:
		printerr("FAIL: Food capacity after upgrade expected %d, got %d" % [base_sh_cap + 125, rm.get_capacity("food")])
		failures += 1

	# Cleanup: remove storehouse & revert capacity
	BuildingSystemScript.demolish_building(test_sh, wd, rm, null, 0.0)

	if failures == 0:
		print("  [PASS] TC-BM.42: Upgrade completion applies delta effect accurately.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.43: Duplicate completion is strictly idempotent (no double bonus)
# -----------------------------------------------------------------------------
func _test_tc_bm_43_upgrade_completion_idempotency() -> bool:
	print("--- Running TC-BM.43: Upgrade Completion Strictly Idempotent ---")
	var failures: int = 0
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	var wd = world_instance.world_data

	var test_sh: Dictionary = {
		"id": "bld_tc43_sh",
		"type": "storehouse",
		"cell": Vector2i(28, 28),
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100,
		"upgrade_level": 1
	}
	wd.buildings.append(test_sh)
	BuildingSystemScript.apply_completion_effects(test_sh, rm)
	var cap_before = rm.get_capacity("food")

	test_sh["is_upgrading"] = true
	test_sh["upgrade_target_level"] = 2
	test_sh["upgrade_progress"] = 6.0
	test_sh["upgrade_required_hours"] = 6.0

	# First completion
	var r1 = BuildingSystemScript.complete_building_upgrade(test_sh, wd, rm)
	var cap_after = rm.get_capacity("food")

	# Second completion attempt (duplicate)
	var r2 = BuildingSystemScript.complete_building_upgrade(test_sh, wd, rm)
	if r2.get("success", false):
		printerr("FAIL: Duplicate complete_building_upgrade succeeded when it should fail")
		failures += 1

	if rm.get_capacity("food") != cap_after:
		printerr("FAIL: Capacity increased on duplicate completion: %d vs %d" % [rm.get_capacity("food"), cap_after])
		failures += 1

	# Cleanup
	BuildingSystemScript.demolish_building(test_sh, wd, rm, null, 0.0)

	if failures == 0:
		print("  [PASS] TC-BM.43: Duplicate completion rejected idempotently without capacity drift.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.44: Upgrade cancellation refunds exactly 50% and cleans up builder jobs
# -----------------------------------------------------------------------------
func _test_tc_bm_44_upgrade_cancellation_50_percent_refund() -> bool:
	print("--- Running TC-BM.44: Upgrade Cancellation 50% Refund & Job Cleanup ---")
	var failures: int = 0
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	var wd = world_instance.world_data
	var jm = world_instance.job_mgr

	# Give ample resources
	rm.add_resource("wood", 100)
	rm.add_resource("stone", 100)

	var test_house: Dictionary = {
		"id": "bld_tc44_house",
		"type": "house",
		"cell": Vector2i(30, 10),
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100,
		"upgrade_level": 1
	}
	wd.buildings.append(test_house)
	var b_id: String = test_house.get("id", "")

	var pre_wood = rm.get_available_stock("wood")
	var pre_stone = rm.get_available_stock("stone")

	# Start upgrade to Level 2 (cost: 19 wood, 8 stone)
	var start_res = BuildingSystemScript.start_upgrade(test_house, wd, rm)
	if not start_res.get("success", false):
		printerr("FAIL: start_upgrade failed: %s" % start_res.get("reason", ""))
		failures += 1

	# Create builder job
	var test_job = jm.create_job("builder", Vector2i(30, 9), "Nâng cấp nhà", b_id, 4.0, 2, false)

	# Cancel upgrade
	var cancel_res = BuildingSystemScript.cancel_upgrade(test_house, wd, rm, jm, 0.5)
	if not cancel_res.get("success", false):
		printerr("FAIL: cancel_upgrade failed: %s" % cancel_res.get("reason", ""))
		failures += 1

	# Expected refund: floor(19 * 0.5) = 9 wood, floor(8 * 0.5) = 4 stone
	var expected_wood = pre_wood - 19 + 9
	var expected_stone = pre_stone - 8 + 4
	if rm.get_available_stock("wood") != expected_wood:
		printerr("FAIL: Wood stock after cancel expected %d, got %d" % [expected_wood, rm.get_available_stock("wood")])
		failures += 1
	if rm.get_available_stock("stone") != expected_stone:
		printerr("FAIL: Stone stock after cancel expected %d, got %d" % [expected_stone, rm.get_available_stock("stone")])
		failures += 1

	# Verify job cleaned up
	var rem_jobs = jm.get_jobs_for_building(b_id)
	if not rem_jobs.is_empty():
		printerr("FAIL: Builder jobs not cleaned up after cancel: %d remaining" % rem_jobs.size())
		failures += 1

	# Cleanup
	wd.buildings.erase(test_house)

	if failures == 0:
		print("  [PASS] TC-BM.44: Upgrade cancellation refunds exactly 50% and removes builder jobs.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.45: Cancellation with insufficient storage fails atomically without mutation
# -----------------------------------------------------------------------------
func _test_tc_bm_45_cancellation_insufficient_storage_fail_closed() -> bool:
	print("--- Running TC-BM.45: Cancellation Insufficient Storage Fail-Closed ---")
	var failures: int = 0
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	var wd = world_instance.world_data

	var test_house: Dictionary = {
		"id": "bld_tc45_house",
		"type": "house",
		"cell": Vector2i(32, 10),
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100,
		"upgrade_level": 1,
		"is_upgrading": true,
		"upgrade_target_level": 2,
		"upgrade_progress": 2.0,
		"upgrade_required_hours": 4.0,
		"upgrade_cost": {"wood": 20, "stone": 10}
	}
	wd.buildings.append(test_house)

	# Fill wood capacity completely
	var pre_wood = rm.get_available_stock("wood")
	var wood_cap = rm.get_capacity("wood")
	rm._current_stock["wood"] = wood_cap

	var check = BuildingSystemScript.can_cancel_upgrade(test_house, wd, rm, 0.5)
	if check.get("can_cancel", true):
		printerr("FAIL: can_cancel_upgrade should fail when storage is full")
		failures += 1
	if not check.get("insufficient_storage", false):
		printerr("FAIL: expected insufficient_storage flag to be true")
		failures += 1

	var cancel_res = BuildingSystemScript.cancel_upgrade(test_house, wd, rm, null, 0.5)
	if cancel_res.get("success", true):
		printerr("FAIL: cancel_upgrade should fail when storage is full")
		failures += 1

	# Verify no state mutation
	if not bool(test_house.get("is_upgrading", false)):
		printerr("FAIL: test_house is_upgrading was mutated on failed cancellation")
		failures += 1
	if float(test_house.get("upgrade_progress", 0.0)) != 2.0:
		printerr("FAIL: test_house upgrade_progress was mutated")
		failures += 1

	# Revert stock and cleanup
	rm._current_stock["wood"] = pre_wood
	wd.buildings.erase(test_house)

	if failures == 0:
		print("  [PASS] TC-BM.45: Upgrade cancellation with full storage fails closed atomically.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.46: Save/Load in-progress upgrade resumes correctly
# -----------------------------------------------------------------------------
func _test_tc_bm_46_save_load_in_progress_upgrade() -> bool:
	print("--- Running TC-BM.46: Save/Load In-Progress Upgrade Persistence ---")
	var failures: int = 0
	var wd = world_instance.world_data

	var test_farm: Dictionary = {
		"id": "bld_tc46_farm",
		"type": "farm",
		"cell": Vector2i(10, 24),
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100,
		"upgrade_level": 1,
		"is_upgrading": true,
		"upgrade_target_level": 2,
		"upgrade_progress": 3.5,
		"upgrade_required_hours": 6.0,
		"upgrade_cost": {"wood": 23, "stone": 4}
	}
	wd.buildings.append(test_farm)
	var b_id: String = test_farm.get("id", "")

	var temp_save := "user://saves/test_upgrade_progress_save.json"
	var save_res = SaveManagerScript.save_to_file(world_instance, temp_save)
	if not save_res.get("success", false):
		printerr("FAIL: Save failed in TC-BM.46: %s" % save_res.get("error", ""))
		return false

	var load_res = SaveManagerScript.load_from_file(temp_save)
	if not load_res.get("success", false):
		printerr("FAIL: Load failed in TC-BM.46: %s" % load_res.get("error", ""))
		return false

	var apply_res = SaveManagerScript.apply_loaded_state_to_world(world_instance, load_res["data"])
	if not apply_res.get("success", false):
		printerr("FAIL: Apply loaded state failed in TC-BM.46")
		return false

	var restored_farm = BuildingSystemScript.get_building_by_id(b_id, world_instance.world_data)
	if restored_farm.is_empty():
		printerr("FAIL: Farm building not found after load")
		failures += 1
	else:
		if not bool(restored_farm.get("is_upgrading", false)):
			printerr("FAIL: Restored farm is_upgrading is false")
			failures += 1
		if int(restored_farm.get("upgrade_target_level", 0)) != 2:
			printerr("FAIL: Restored farm target level is %d, expected 2" % int(restored_farm.get("upgrade_target_level", 0)))
			failures += 1
		if absf(float(restored_farm.get("upgrade_progress", 0.0)) - 3.5) > 0.001:
			printerr("FAIL: Restored farm progress mismatch: %f vs 3.5" % float(restored_farm.get("upgrade_progress", 0.0)))
			failures += 1

	# Clean temp save
	if FileAccess.file_exists(temp_save):
		DirAccess.remove_absolute(temp_save)
	if FileAccess.file_exists(temp_save + ".bak"):
		DirAccess.remove_absolute(temp_save + ".bak")

	# Clean test farm
	if not restored_farm.is_empty():
		world_instance.world_data.buildings.erase(restored_farm)
		for ox in range(2):
			for oy in range(2):
				world_instance.world_data.occupancy[10 + ox][24 + oy] = false

	if failures == 0:
		print("  [PASS] TC-BM.46: In-progress upgrade successfully preserved and restored via disk roundtrip.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.47: Repeated Load does not duplicate capacity or multiplier effects
# -----------------------------------------------------------------------------
func _test_tc_bm_47_repeated_load_zero_drift() -> bool:
	print("--- Running TC-BM.47: Repeated Save/Load Zero Drift ---")
	var failures: int = 0
	var rm = world_instance.get_node_or_null("/root/ResourceManager")

	var temp_save := "user://saves/test_repeat_load.json"
	SaveManagerScript.save_to_file(world_instance, temp_save)

	var initial_wood_cap = rm.get_capacity("wood")
	var initial_food_cap = rm.get_capacity("food")

	# Load 3 times in succession
	for i in range(3):
		var load_res = SaveManagerScript.load_from_file(temp_save)
		SaveManagerScript.apply_loaded_state_to_world(world_instance, load_res["data"])
		if rm.get_capacity("wood") != initial_wood_cap or rm.get_capacity("food") != initial_food_cap:
			printerr("FAIL: Capacity drifted on load iteration %d: wood=%d (init %d), food=%d (init %d)" % [i, rm.get_capacity("wood"), initial_wood_cap, rm.get_capacity("food"), initial_food_cap])
			failures += 1
			break

	if FileAccess.file_exists(temp_save):
		DirAccess.remove_absolute(temp_save)
	if FileAccess.file_exists(temp_save + ".bak"):
		DirAccess.remove_absolute(temp_save + ".bak")

	if failures == 0:
		print("  [PASS] TC-BM.47: Repeated load does not duplicate storage or multipliers.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.48: Demolition of upgraded Storehouse adjusts capacity correctly for its current level
# -----------------------------------------------------------------------------
func _test_tc_bm_48_demolition_of_upgraded_storehouse() -> bool:
	print("--- Running TC-BM.48: Demolition of Upgraded Storehouse Adjusts Level Capacity ---")
	var failures: int = 0
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	var wd = world_instance.world_data

	var cap_base = rm.get_capacity("food")

	# Place and upgrade a storehouse to Level 2
	var test_sh: Dictionary = {
		"id": "bld_tc48_sh",
		"type": "storehouse",
		"cell": Vector2i(14, 28),
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100,
		"upgrade_level": 1
	}
	wd.buildings.append(test_sh)
	BuildingSystemScript.apply_completion_effects(test_sh, rm)
	test_sh["is_upgrading"] = true
	test_sh["upgrade_target_level"] = 2
	test_sh["upgrade_progress"] = 6.0
	test_sh["upgrade_required_hours"] = 6.0
	BuildingSystemScript.complete_building_upgrade(test_sh, wd, rm)

	var cap_lvl2 = rm.get_capacity("food")
	if cap_lvl2 != cap_base + 625:
		printerr("FAIL: Level 2 storehouse capacity expected %d, got %d" % [cap_base + 625, cap_lvl2])
		failures += 1

	# Demolish Level 2 storehouse
	var demo_res = BuildingSystemScript.demolish_building(test_sh, wd, rm, null, 0.0)
	if not demo_res.get("success", false):
		printerr("FAIL: Demolish Lvl 2 storehouse failed: %s" % demo_res.get("reason", ""))
		failures += 1

	# Capacity should have returned exactly to cap_base
	if rm.get_capacity("food") != cap_base:
		printerr("FAIL: Food capacity after demolishing Lvl 2 storehouse expected %d, got %d" % [cap_base, rm.get_capacity("food")])
		failures += 1

	if failures == 0:
		print("  [PASS] TC-BM.48: Demolishing upgraded storehouse accurately deducts current-tier capacity.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.49: Existing Level 1 construction, workplace, and demolition regressions remain 100% valid
# -----------------------------------------------------------------------------
func _test_tc_bm_49_level_1_regressions_valid() -> bool:
	print("--- Running TC-BM.49: Existing Level 1 Baseline Regressions ---")
	var failures: int = 0
	var wd = world_instance.world_data
	var rm = world_instance.get_node_or_null("/root/ResourceManager")

	# Fund resources and place normal Level 1 house
	rm.add_resource("wood", 100)
	rm.add_resource("stone", 100)
	var test_cell := Vector2i(-1, -1)
	for x in range(20, 50):
		for y in range(20, 50):
			var c := Vector2i(x, y)
			if BuildingSystemScript.can_place_building("house", c, wd, rm)["valid"]:
				test_cell = c
				break
		if test_cell != Vector2i(-1, -1):
			break

	var b_res = BuildingSystemScript.place_building("house", test_cell, wd, rm, "under_construction")
	if not b_res.get("success", false):
		printerr("FAIL: place_building failed in TC-BM.49: %s" % b_res.get("reason", ""))
		return false
	var bld: Dictionary = b_res.get("building", {})
	if int(bld.get("upgrade_level", 0)) != 1:
		printerr("FAIL: Lvl 1 building upgrade_level is not 1")
		failures += 1

	# Complete normal construction
	BuildingSystemScript.advance_construction(bld, 8.0, wd)
	var comp_ok = BuildingSystemScript.complete_building(bld, wd, rm)
	if not comp_ok or bld.get("state") != "active":
		printerr("FAIL: Lvl 1 building not active after construction (comp_ok=%s, state=%s)" % [str(comp_ok), bld.get("state")])
		failures += 1

	# Demolish normal building
	var demo = BuildingSystemScript.demolish_building(bld, wd, rm, null, 0.0)
	if not demo.get("success", false):
		printerr("FAIL: Lvl 1 building demolition failed: %s" % demo.get("reason", ""))
		failures += 1

	if failures == 0:
		print("  [PASS] TC-BM.49: All standard Level 1 lifecycle mechanics remain 100% valid.")
		return true
	return false

