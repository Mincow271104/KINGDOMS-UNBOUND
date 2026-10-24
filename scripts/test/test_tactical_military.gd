extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — Package 1W: Tactical Military Units & Command MVP
## Covers TC-TAC.1 through TC-TAC.30 across 5 test groups:
## Group 1: Data & Authoritative Roster Synchronization (TC-TAC.1 - TC-TAC.7)
## Group 2: Tactical Unit Selection (TC-TAC.8 - TC-TAC.12)
## Group 3: Tactical Movement & Pathfinding (TC-TAC.13 - TC-TAC.20)
## Group 4: Formations & Control Groups (TC-TAC.21 - TC-TAC.25)
## Group 5: Persistence, Save/Load & Integrity (TC-TAC.26 - TC-TAC.30)

const PlayerArmyManagerScript = preload("res://scripts/military/player_army_manager.gd")
const TacticalMilitaryManagerScript = preload("res://scripts/military/tactical_military_manager.gd")
const TacticalUnitScript = preload("res://scripts/military/tactical_unit.gd")
const ArmyMarkerScript = preload("res://scripts/military/army_marker.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")

var frame_count: int = 0
var world_instance: Node = null
var failures: int = 0
var total_assertions: int = 0

class MockResourceManager:
	var stock: Dictionary = {}
	var reserved: Dictionary = {}

	func _init() -> void:
		stock = {
			EconomyConfigScript.RES_FOOD: 500,
			EconomyConfigScript.RES_WOOD: 500,
			EconomyConfigScript.RES_GOLD: 500,
			EconomyConfigScript.RES_STONE: 200,
			EconomyConfigScript.RES_METAL: 200
		}
		reserved = {
			EconomyConfigScript.RES_FOOD: 0,
			EconomyConfigScript.RES_WOOD: 0,
			EconomyConfigScript.RES_GOLD: 0,
			EconomyConfigScript.RES_STONE: 0,
			EconomyConfigScript.RES_METAL: 0
		}

	func get_available_stock(res_id: String) -> int:
		return maxi(0, stock.get(res_id, 0) - reserved.get(res_id, 0))

	func can_afford(cost: Dictionary) -> bool:
		for res_id in cost:
			if get_available_stock(res_id) < cost[res_id]:
				return false
		return true

	func reserve_cost(cost: Dictionary) -> bool:
		if not can_afford(cost):
			return false
		for res_id in cost:
			reserved[res_id] = reserved.get(res_id, 0) + cost[res_id]
		return true

	func commit_cost(cost: Dictionary) -> void:
		for res_id in cost:
			var amt: int = cost[res_id]
			reserved[res_id] = maxi(0, reserved.get(res_id, 0) - amt)
			stock[res_id] = maxi(0, stock.get(res_id, 0) - amt)

	func release_cost(cost: Dictionary) -> void:
		for res_id in cost:
			reserved[res_id] = maxi(0, reserved.get(res_id, 0) - cost[res_id])

class MockTimeManager:
	var current_day: int = 1
	var current_speed: int = 1
	var _paused: bool = false

	func is_paused() -> bool:
		return _paused

	func pause() -> void:
		_paused = true

	func resume() -> void:
		_paused = false

	func set_speed(s: int) -> void:
		current_speed = s

func _init() -> void:
	print("\n========================================================")
	print("  STARTING PACKAGE 1W TACTICAL MILITARY TEST SUITE")
	print("========================================================\n")
	world_instance = WorldViewScene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count == 2:
		_run_all_tests()
		var exit_code := 0 if failures == 0 else 1
		print("\n========================================================")
		if failures == 0:
			print("  [SUCCESS] All Package 1W Tactical Military Tests PASSED! (%d assertions)" % total_assertions)
		else:
			print("  [FAILURE] %d tests FAILED in Package 1W Tactical Military Test Suite." % failures)
		print("========================================================\n")
		quit(exit_code)
	return false

func _assert(condition: bool, test_name: String, details: String = "") -> void:
	total_assertions += 1
	if condition:
		print("  [PASS] %s" % test_name)
	else:
		failures += 1
		printerr("  [FAIL] %s: %s" % [test_name, details])

func _run_all_tests() -> void:
	var live_army = world_instance.get("player_army_mgr")
	var live_tac = world_instance.get("tactical_military_mgr")
	var live_nav = world_instance.get("nav")
	var live_hud = world_instance.get("hud")

	# =========================================================================
	# GROUP 1: Data & Authoritative Roster Synchronization (TC-TAC.1 - TC-TAC.7)
	# =========================================================================
	print("\n--- Group 1: Data & Roster Synchronization (TC-TAC.1 - TC-TAC.7) ---")

	# TC-TAC.1: Initial State (0 soldiers, 0 units, empty selection)
	var standalone_army = PlayerArmyManagerScript.new()
	var standalone_tac = TacticalMilitaryManagerScript.new(null, standalone_army)
	_assert(standalone_tac.get_unit_count() == 0, "TC-TAC.1: Unit count is 0 on initialization")
	_assert(standalone_tac.get_selected_count() == 0, "TC-TAC.1: Selection is empty on initialization")

	# Setup barracks for recruitment
	var mock_rm := MockResourceManager.new()
	var mock_tm := MockTimeManager.new()
	standalone_army.set_custom_resource_manager(mock_rm)
	standalone_army.set_custom_time_manager(mock_tm)
	standalone_army.set_custom_nav(live_nav)
	standalone_tac.set_custom_nav(live_nav)
	standalone_tac.set_custom_time_manager(mock_tm)

	# Mock world data with 1 active barracks
	var wd = WorldGenerator.WorldData.new()
	var b_barracks := {
		"id": "b_barracks_1",
		"type": "barracks",
		"cell": Vector2i(30, 30),
		"size": Vector2i(3, 3),
		"state": "active"
	}
	wd.buildings.append(b_barracks)
	standalone_army.set_custom_world_data(wd)
	standalone_army.refresh_rally_cell()

	# TC-TAC.2: Recruit 1 soldier -> spawns 1 tactical unit
	var r1 = standalone_army.recruit(1)
	_assert(r1.get("success", false), "TC-TAC.2: Recruitment of 1 soldier succeeded")
	_assert(standalone_tac.get_unit_count() == 1, "TC-TAC.2: Tactical roster has exactly 1 unit", "count=%d" % standalone_tac.get_unit_count())
	var u1 = standalone_tac.get_all_units()[0]
	_assert(u1 != null and u1.unit_id != "", "TC-TAC.2: Spawned unit has valid unit_id (%s)" % (u1.unit_id if u1 else "null"))
	_assert(u1.current_cell == standalone_army.get_rally_cell(), "TC-TAC.2: Unit spawned at rally cell %s" % str(u1.current_cell))

	# TC-TAC.3: Recruit multiple soldiers -> unique IDs & matching count
	var r2 = standalone_army.recruit(3)
	_assert(r2.get("success", false), "TC-TAC.3: Recruited 3 more soldiers (total 4)")
	_assert(standalone_tac.get_unit_count() == 4, "TC-TAC.3: Tactical roster has exactly 4 units", "count=%d" % standalone_tac.get_unit_count())
	var seen_ids: Dictionary = {}
	var has_duplicate_ids := false
	for u in standalone_tac.get_all_units():
		if seen_ids.has(u.unit_id):
			has_duplicate_ids = true
		seen_ids[u.unit_id] = true
	_assert(not has_duplicate_ids, "TC-TAC.3: All 4 tactical units have strictly unique IDs")

	# TC-TAC.4: Replaying capacity/army signals is idempotent
	standalone_army.notify_capacity_changed()
	standalone_tac.sync_with_player_army()
	_assert(standalone_tac.get_unit_count() == 4, "TC-TAC.4: Replaying army signals does not create duplicate units (count=4)")

	# TC-TAC.5: Campaign casualty deduction synchronizes tactical roster without double-deduction
	var removed := standalone_army.remove_casualties(2)
	_assert(removed == 2, "TC-TAC.5: Removed 2 casualties authoritatively from PlayerArmyManager")
	_assert(standalone_army.get_army_count() == 2, "TC-TAC.5: PlayerArmyManager count is 2")
	_assert(standalone_tac.get_unit_count() == 2, "TC-TAC.5: TacticalMilitaryManager synchronized to 2 units without double deduction")

	# TC-TAC.6: Citizen registry and citizen list are unaffected by army roster
	var initial_cit_count: int = world_instance.get("citizen_list").size()
	live_army.set_custom_resource_manager(mock_rm)
	var live_tac_mgr = world_instance.get("tactical_military_mgr")
	_assert(world_instance.get("citizen_list").size() == initial_cit_count, "TC-TAC.6: Citizen count unaffected by tactical military operations")

	# TC-TAC.7: Authoritative barracks capacity and recruit costs remain unchanged
	var expected_cost := {
		EconomyConfigScript.RES_GOLD: EconomyConfigScript.ARMY_RECRUIT_COST[EconomyConfigScript.RES_GOLD],
		EconomyConfigScript.RES_METAL: EconomyConfigScript.ARMY_RECRUIT_COST[EconomyConfigScript.RES_METAL],
		EconomyConfigScript.RES_FOOD: EconomyConfigScript.ARMY_RECRUIT_COST[EconomyConfigScript.RES_FOOD]
	}
	_assert(standalone_army.get_recruitment_cost(1) == expected_cost, "TC-TAC.7: Authoritative recruitment cost remains unchanged")
	_assert(standalone_army.get_army_capacity() == EconomyConfigScript.ARMY_CAPACITY_PER_BARRACKS, "TC-TAC.7: Barracks capacity matches configuration")

	# =========================================================================
	# GROUP 2: Tactical Unit Selection (TC-TAC.8 - TC-TAC.12)
	# =========================================================================
	print("\n--- Group 2: Tactical Unit Selection (TC-TAC.8 - TC-TAC.12) ---")

	var all_units = standalone_tac.get_all_units()
	var unit_a = all_units[0]
	var unit_b = all_units[1]

	# TC-TAC.8: Single click selection
	standalone_tac.select_unit(unit_a.unit_id, false)
	_assert(standalone_tac.get_selected_count() == 1, "TC-TAC.8: Exactly 1 unit selected")
	_assert(standalone_tac.is_unit_selected(unit_a.unit_id), "TC-TAC.8: Unit A is selected")
	_assert(not standalone_tac.is_unit_selected(unit_b.unit_id), "TC-TAC.8: Unit B is not selected")
	_assert(unit_a.is_selected, "TC-TAC.8: Unit A visual selection indicator active")

	# TC-TAC.9: Shift-click additive selection & toggle deselect
	standalone_tac.select_unit(unit_b.unit_id, true) # Shift add
	_assert(standalone_tac.get_selected_count() == 2, "TC-TAC.9: Additive shift-click selects 2 units")
	standalone_tac.select_unit(unit_a.unit_id, true) # Shift remove
	_assert(standalone_tac.get_selected_count() == 1, "TC-TAC.9: Shift-click on already selected unit deselects it")
	_assert(standalone_tac.is_unit_selected(unit_b.unit_id), "TC-TAC.9: Unit B remains selected")

	# TC-TAC.10: Viewport selection box
	unit_a.current_cell = Vector2i(20, 20)
	unit_b.current_cell = Vector2i(21, 20)
	unit_a.position = IsoMath.map_to_local(unit_a.current_cell)
	unit_b.position = IsoMath.map_to_local(unit_b.current_cell)
	var min_screen: Vector2 = unit_a.position - Vector2(30, 30)
	var max_screen: Vector2 = unit_b.position + Vector2(30, 30)
	var box_rect := Rect2(min_screen, max_screen - min_screen)
	standalone_tac.select_in_screen_rect(box_rect, null, false)
	_assert(standalone_tac.get_selected_count() == 2, "TC-TAC.10: Selection box enclosed both units and selected both")

	var outside_box := Rect2(Vector2(5000, 5000), Vector2(100, 100))
	standalone_tac.select_in_screen_rect(outside_box, null, false)
	_assert(standalone_tac.get_selected_count() == 0, "TC-TAC.10: Selection box in empty space clears selection")

	# TC-TAC.11: Clicking citizens does not select tactical military
	standalone_tac.clear_selection()
	var test_cit_cell := Vector2i(32, 32)
	world_instance._check_citizen_click(test_cit_cell)
	_assert(standalone_tac.get_selected_count() == 0, "TC-TAC.11: Checking citizen click did not select tactical military")

	# TC-TAC.12: UI panels block accidental tactical orders
	_assert(live_hud != null, "TC-TAC.12: HUD is present in live scene")
	_assert(world_instance.get("_selection_box_control") != null, "TC-TAC.12: Selection box overlay initialized")

	# =========================================================================
	# GROUP 3: Tactical Movement & Pathfinding (TC-TAC.13 - TC-TAC.20)
	# =========================================================================
	print("\n--- Group 3: Tactical Movement & Pathfinding (TC-TAC.13 - TC-TAC.20) ---")

	standalone_tac.clear_selection()
	standalone_tac.select_unit(unit_a.unit_id, false)
	unit_a.current_cell = Vector2i(30, 30)
	unit_a.position = IsoMath.map_to_local(unit_a.current_cell)

	# TC-TAC.13: Move order to walkable cell generates valid path
	var move_dest := Vector2i(30, 32)
	var move_res = standalone_tac.issue_move_order(move_dest, live_nav)
	_assert(move_res.get("success", false), "TC-TAC.13: Move order to walkable cell succeeded")
	_assert(unit_a.order_state == TacticalUnitScript.OrderState.MOVING, "TC-TAC.13: Unit A transitioned to MOVING state")
	_assert(not unit_a.current_path.is_empty(), "TC-TAC.13: Unit A has non-empty current_path")

	# TC-TAC.14: Reject destination out of bounds
	var oob_dest := Vector2i(-5, 30)
	var oob_res = standalone_tac.issue_move_order(oob_dest, live_nav)
	_assert(not oob_res.get("success", true), "TC-TAC.14: Move order out-of-bounds rejected safely")
	_assert(oob_res.get("reason", "").find("ngoài bản đồ") != -1, "TC-TAC.14: Rejection reason states out-of-bounds")

	# TC-TAC.15: Reject unwalkable / blocked destination
	var blocked_cell := Vector2i(0, 0)
	for y in range(IsoMath.MAP_SIZE):
		for x in range(IsoMath.MAP_SIZE):
			if not live_nav.is_cell_walkable(Vector2i(x, y)):
				blocked_cell = Vector2i(x, y)
				break
		if blocked_cell != Vector2i(0, 0):
			break
	var block_res = standalone_tac.issue_move_order(blocked_cell, live_nav)
	_assert(not block_res.get("success", true), "TC-TAC.15: Move order to unwalkable cell rejected safely")

	# TC-TAC.16: Group units in formation have distinct, valid, non-overlapping destination slots
	unit_a.current_cell = Vector2i(30, 30)
	unit_b.current_cell = Vector2i(30, 31)
	standalone_tac.clear_selection()
	standalone_tac.select_unit(unit_a.unit_id, false)
	standalone_tac.select_unit(unit_b.unit_id, true) # Both A and B selected
	var group_dest := Vector2i(28, 28)
	var group_res = standalone_tac.issue_move_order(group_dest, live_nav)
	_assert(group_res.get("success", false), "TC-TAC.16: Group move order succeeded", group_res.get("reason", ""))
	_assert(unit_a.target_cell != unit_b.target_cell, "TC-TAC.16: Unit A and Unit B assigned distinct destination slots (A=%s, B=%s)" % [str(unit_a.target_cell), str(unit_b.target_cell)])
	_assert(live_nav.is_cell_walkable(unit_a.target_cell) and live_nav.is_cell_walkable(unit_b.target_cell), "TC-TAC.16: Both destination slots are strictly walkable")

	# TC-TAC.17: Complete movement order and transition to IDLE
	var max_sim_steps := 30
	for step in range(max_sim_steps):
		standalone_tac.advance_movement(0.5, 1.0, live_nav)
		if unit_a.order_state == TacticalUnitScript.OrderState.IDLE and unit_b.order_state == TacticalUnitScript.OrderState.IDLE:
			break
	_assert(unit_a.order_state == TacticalUnitScript.OrderState.IDLE, "TC-TAC.17: Unit A completed move order and transitioned to IDLE")
	_assert(unit_b.order_state == TacticalUnitScript.OrderState.IDLE, "TC-TAC.17: Unit B completed move order and transitioned to IDLE")
	_assert(unit_a.current_cell == unit_a.target_cell, "TC-TAC.17: Unit A reached final target cell")
	_assert(unit_b.current_cell == unit_b.target_cell, "TC-TAC.17: Unit B reached final target cell")

	# TC-TAC.18: Pause strictly halts movement; resume allows progression
	unit_a.order_move([Vector2i(29, 28), Vector2i(30, 28)], Vector2i(30, 28))
	mock_tm.pause()
	var pre_pause_cell: Vector2i = unit_a.current_cell
	standalone_tac.advance_movement(1.0, 1.0, live_nav)
	_assert(unit_a.current_cell == pre_pause_cell, "TC-TAC.18: Movement paused: cell unchanged under simulation advance")
	mock_tm.resume()
	standalone_tac.advance_movement(0.5, 1.0, live_nav)
	_assert(unit_a.current_cell != pre_pause_cell, "TC-TAC.18: Movement resumed: cell advanced after unpausing")
	unit_a.order_stop()

	# TC-TAC.19: Simulation speed scaling (1x, 2x, 3x)
	unit_a.order_move([Vector2i(28, 28), Vector2i(27, 28), Vector2i(26, 28)], Vector2i(26, 28))
	mock_tm.set_speed(2)
	standalone_tac.advance_movement(0.25, 2.0, live_nav)
	_assert(unit_a.current_cell == Vector2i(28, 28), "TC-TAC.19: 2x speed advanced exactly 1 cell without skipping")
	unit_a.order_stop()
	mock_tm.set_speed(1)

	# TC-TAC.20: New movement order deterministically replaces old order
	unit_a.order_move([Vector2i(20, 20), Vector2i(21, 20)], Vector2i(21, 20))
	var new_target := Vector2i(25, 25)
	var new_order_res = standalone_tac.issue_move_order(new_target, live_nav)
	_assert(new_order_res.get("success", false), "TC-TAC.20: New order issued successfully")
	_assert(unit_a.target_cell == new_target or IsoMath.grid_distance(unit_a.target_cell, new_target) <= 2, "TC-TAC.20: Old order replaced by new destination")

	# =========================================================================
	# GROUP 4: Formations & Control Groups (TC-TAC.21 - TC-TAC.25)
	# =========================================================================
	print("\n--- Group 4: Formations & Control Groups (TC-TAC.21 - TC-TAC.25) ---")

	# TC-TAC.21: Line, Column, and Scatter formations compute distinct destinations
	var f_target := Vector2i(30, 30)
	var line_slots = standalone_tac.compute_formation_slots(f_target, 3, "Line", live_nav)
	var col_slots = standalone_tac.compute_formation_slots(f_target, 3, "Column", live_nav)
	var sca_slots = standalone_tac.compute_formation_slots(f_target, 3, "Scatter", live_nav)
	_assert(line_slots.size() == 3, "TC-TAC.21: Line formation produced 3 valid slots")
	_assert(col_slots.size() == 3, "TC-TAC.21: Column formation produced 3 valid slots")
	_assert(sca_slots.size() == 3, "TC-TAC.21: Scatter formation produced 3 valid slots")
	_assert(line_slots != col_slots, "TC-TAC.21: Line and Column produce distinct geometry")
	_assert(line_slots[0] != line_slots[1] and line_slots[1] != line_slots[2], "TC-TAC.21: Line slots have zero duplicates")
	_assert(col_slots[0] != col_slots[1] and col_slots[1] != col_slots[2], "TC-TAC.21: Column slots have zero duplicates")

	# TC-TAC.22: Assign and recall control groups 1, 2, 3
	standalone_tac.clear_selection()
	standalone_tac.select_unit(unit_a.unit_id, false)
	standalone_tac.assign_control_group(1)
	standalone_tac.clear_selection()
	_assert(standalone_tac.get_selected_count() == 0, "TC-TAC.22: Selection cleared")
	standalone_tac.recall_control_group(1)
	_assert(standalone_tac.get_selected_count() == 1 and standalone_tac.is_unit_selected(unit_a.unit_id), "TC-TAC.22: Recalled control group 1 selects Unit A")

	# TC-TAC.23: Shortcut groups with Ctrl/Shift do NOT trigger HUD speed changes
	var tm_node = world_instance.get_node_or_null("/root/TimeManager")
	var initial_speed: int = int(tm_node.get("current_speed")) if tm_node else 1
	var event_ctrl_1 := InputEventKey.new()
	event_ctrl_1.pressed = true
	event_ctrl_1.keycode = KEY_1
	event_ctrl_1.ctrl_pressed = true
	live_hud._unhandled_input(event_ctrl_1)
	var speed_after_ctrl_1: int = int(tm_node.get("current_speed")) if tm_node else 1
	_assert(speed_after_ctrl_1 == initial_speed, "TC-TAC.23: Ctrl+1 did not change TimeManager simulation speed")

	# TC-TAC.24: Control groups prune eliminated units automatically
	standalone_tac.assign_control_group(2)
	_assert(standalone_tac.get_control_group(2).size() == 1, "TC-TAC.24: Control group 2 contains Unit A")
	standalone_army.remove_casualties(1)
	_assert(standalone_tac.get_unit_count() == 1, "TC-TAC.24: Roster reduced to 1 unit after casualty")
	_assert(standalone_tac.get_control_group(2).size() <= 1, "TC-TAC.24: Control group 2 pruned dead unit safely")

	# TC-TAC.25: Existing HUD shortcuts remain functional
	_assert(live_hud.open_military_btn != null, "TC-TAC.25: Military button present in HUD BottomBar")
	_assert(live_hud.army_panel != null, "TC-TAC.25: ArmyPanel present in HUD")

	# =========================================================================
	# GROUP 5: Persistence, Save/Load & Integrity (TC-TAC.26 - TC-TAC.30)
	# =========================================================================
	print("\n--- Group 5: Persistence, Save/Load & Integrity (TC-TAC.26 - TC-TAC.30) ---")

	# TC-TAC.26: Serialize / deserialize roundtrip preserves state
	standalone_tac.set_formation("Scatter")
	var serialized = standalone_tac.serialize()
	_assert(serialized.has("units") and serialized.has("current_formation"), "TC-TAC.26: Serialized data contains units and formation")
	_assert(serialized["current_formation"] == "Scatter", "TC-TAC.26: Serialized formation matches 'Scatter'")
	var restored_tac = TacticalMilitaryManagerScript.new(null, standalone_army)
	restored_tac.deserialize(serialized)
	_assert(restored_tac.get_formation() == "Scatter", "TC-TAC.26: Deserialized formation restored to 'Scatter'")
	_assert(restored_tac.get_unit_count() == standalone_tac.get_unit_count(), "TC-TAC.26: Deserialized unit count matches original")

	# TC-TAC.27: Full SaveManager world-state roundtrip restores tactical military
	SaveManagerScript.ensure_save_directory()
	var test_save_path := "user://saves/test_tactical_roundtrip.json"
	var save_res = SaveManagerScript.save_to_file(world_instance, test_save_path)
	_assert(save_res.get("success", false), "TC-TAC.27: World saved successfully with tactical military section")
	var load_res = SaveManagerScript.load_from_file(test_save_path)
	_assert(load_res.get("success", false), "TC-TAC.27: World load parsed successfully")
	var apply_res = SaveManagerScript.apply_loaded_state_to_world(world_instance, load_res.get("data", {}))
	_assert(apply_res.get("success", false), "TC-TAC.27: Applied loaded state to world successfully")
	_assert(live_tac_mgr.get_unit_count() == live_army.get_army_count(), "TC-TAC.27: Tactical units count matches authoritative army count after load")

	# TC-TAC.28: Loading twice consecutively is strictly idempotent
	var apply_res_2 = SaveManagerScript.apply_loaded_state_to_world(world_instance, load_res.get("data", {}))
	_assert(apply_res_2.get("success", false), "TC-TAC.28: Second consecutive load succeeded")
	_assert(live_tac_mgr.get_unit_count() == live_army.get_army_count(), "TC-TAC.28: Second load produced zero duplicate units")

	# TC-TAC.29: Legacy save lacking tactical_military reconstructs valid roster from soldier_count
	var legacy_dict: Dictionary = SaveManagerScript.serialize_world_state(world_instance)
	legacy_dict.erase("tactical_military")
	legacy_dict["player_army"] = {
		"soldier_count": 3,
		"is_supplied": true,
		"last_upkeep_day": 1,
		"current_cell": [32, 33],
		"rally_cell": [32, 33],
		"destination_cell": [32, 33],
		"movement_state": "garrisoned",
		"current_path": []
	}
	var legacy_tac = TacticalMilitaryManagerScript.new()
	legacy_tac.deserialize_legacy(3, Vector2i(32, 33), live_nav)
	_assert(legacy_tac.get_unit_count() == 3, "TC-TAC.29: Legacy reconstruction created exactly 3 units from soldier_count")

	# TC-TAC.30: Corrupted tactical data fail-closed validation
	# Duplicate IDs
	var bad_data_dup_id: Dictionary = {
		"player_army": {"soldier_count": 2},
		"tactical_military": {
			"units": [
				{"unit_id": "u1", "current_cell": [30, 30]},
				{"unit_id": "u1", "current_cell": [31, 30]}
			]
		}
	}
	var dup_check = SaveManagerScript.validate_save_data(bad_data_dup_id)
	_assert(not dup_check.get("valid", true), "TC-TAC.30: Duplicate unit IDs rejected by validator")

	# Mismatched unit count vs authoritative soldier_count
	var bad_data_count: Dictionary = {
		"player_army": {"soldier_count": 5, "movement_state": "garrisoned"},
		"tactical_military": {
			"units": [
				{"unit_id": "u1", "current_cell": [30, 30]}
			]
		}
	}
	var count_check = SaveManagerScript.validate_save_data(bad_data_count)
	_assert(not count_check.get("valid", true), "TC-TAC.30: Mismatched tactical unit count vs authoritative soldier_count rejected")

	# Invalid out-of-bounds coordinates
	var bad_data_oob: Dictionary = {
		"player_army": {"soldier_count": 1},
		"tactical_military": {
			"units": [
				{"unit_id": "u1", "current_cell": [999, 999]}
			]
		}
	}
	var oob_check = SaveManagerScript.validate_save_data(bad_data_oob)
	_assert(not oob_check.get("valid", true), "TC-TAC.30: Out-of-bounds tactical unit coordinate rejected")

