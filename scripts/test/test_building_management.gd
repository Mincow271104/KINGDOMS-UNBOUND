extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — Package 2F: Building Inspection, Workplace Management & Demolition
## Authoritative Coverage: TC-BM.1 through TC-BM.30 (Fail-Closed Assertions)

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
# TC-BM.5: Selection Priority Order
# -----------------------------------------------------------------------------
func _test_tc_bm_5_click_priority() -> bool:
	print("--- Running TC-BM.5: Selection Priority Hierarchy ---")
	var failures: int = 0
	var hud = world_instance.hud
	var origin := Vector2i(12, 12)
	var b_data := {
		"id": "priority_test_bld",
		"type": "farm",
		"cell": origin,
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100
	}
	world_instance.world_data.buildings.append(b_data)

	# 1. Click on empty building cell -> selects building
	world_instance._handle_left_click(origin)
	if world_instance.selected_building_id != "priority_test_bld":
		printerr("FAIL: Building was not selected when clicked directly")
		failures += 1
	if not hud.building_inspect_panel.visible:
		printerr("FAIL: HUD building inspect panel not opened on building click")
		failures += 1

	# 2. Click on empty ground -> clears building selection
	world_instance._handle_left_click(Vector2i(0, 0))
	if world_instance.selected_building_id != "":
		printerr("FAIL: Building selection not cleared on empty ground click")
		failures += 1
	if hud.building_inspect_panel.visible:
		printerr("FAIL: HUD building inspect panel remained open on empty ground click")
		failures += 1

	world_instance.world_data.buildings.erase(b_data)
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
	# Add stock up to post_cap
	if post_cap > cur_stock:
		rm.add_resource("wood", post_cap - cur_stock)

	var res := BuildingSystemScript.can_demolish_building(b_data, world_instance.world_data, rm)
	if res.get("can_demolish", true):
		printerr("FAIL: Demolishing storehouse should fail closed when post-demolition space is less than refund")
		failures += 1
	if not res.get("insufficient_storage", false):
		printerr("FAIL: insufficient_storage flag expected on storehouse rejection")
		failures += 1

	world_instance.world_data.buildings.erase(b_data)
	if failures == 0:
		print("  [PASS] TC-BM.18: Post-demolition storage reduction preflight verified.")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BM.19: Demolition Execution
# -----------------------------------------------------------------------------
func _test_tc_bm_19_demolish_execution() -> bool:
	print("--- Running TC-BM.19: Demolition Execution ---")
	var failures: int = 0
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
# TC-BM.22: Town Hall Collapse Grace Period
# -----------------------------------------------------------------------------
func _test_tc_bm_22_townhall_collapse_grace() -> bool:
	print("--- Running TC-BM.22: Town Hall 72h Grace Period & Collapse Trigger ---")
	var failures: int = 0
	var vm = VictoryManagerScript.new()

	# 1. When townhall is destroyed/missing, tick 71 hours -> still running
	for h in range(71):
		var res := vm.tick_hourly(20, 500, 500, 80.0, 80.0, 3, false, 5)
		if res.get("status") == "collapse":
			printerr("FAIL: Collapse prematurely triggered at hour %d (< 72)" % h)
			failures += 1

	# 2. At hour 72 -> collapse triggered!
	var res72 := vm.tick_hourly(20, 500, 500, 80.0, 80.0, 3, false, 5)
	if res72.get("status") != "collapse":
		printerr("FAIL: Terminal collapse was not triggered after 72 hours of destroyed townhall")
		failures += 1
	if not "Mất thủ đô" in res72.get("reason", ""):
		printerr("FAIL: Reason must indicate lost capital: '%s'" % res72.get("reason", ""))
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
# TC-BM.29: Save/Load Persistence of Paused State
# -----------------------------------------------------------------------------
func _test_tc_bm_29_save_load_persistence() -> bool:
	print("--- Running TC-BM.29: Save/Load Persistence of Paused Buildings ---")
	var failures: int = 0
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

	# Serialize
	var save_dict: Dictionary = SaveManagerScript.serialize_world_state(world_instance)
	var buildings_arr: Array = save_dict.get("buildings", [])
	var found_paused := false
	for b in buildings_arr:
		if b.get("id") == "bld_save_pause_test" and b.get("state") == "paused":
			found_paused = true
			break

	if not found_paused:
		printerr("FAIL: Paused state not serialized in saved buildings")
		failures += 1

	# Test sync_workplaces_after_load restores paused state
	world_instance.sync_workplaces_after_load()
	if not world_instance.workplace_mgr.is_workplace_paused("bld_save_pause_test"):
		printerr("FAIL: sync_workplaces_after_load did not restore workplace is_paused")
		failures += 1

	world_instance.workplace_mgr.unregister_workplace("bld_save_pause_test")
	world_instance.world_data.buildings.erase(b_data)
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
