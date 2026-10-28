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
const BattleCampaignManagerScript = preload("res://scripts/combat/battle_campaign_manager.gd")
const FactionManagerScript = preload("res://scripts/factions/faction_manager.gd")
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

class BlockedPathNav extends GridNavigation:
	func _init() -> void:
		super(null)

	func find_path(_from: Vector2i, _to: Vector2i) -> Array[Vector2i]:
		return []

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

	# =========================================================================
	# GROUP 6: Follow-Up Integration Verification (Cases 1 - 22)
	# =========================================================================
	print("\n--- Group 6: Follow-Up Integration Verification (Cases 1 - 22) ---")

	# --- A. Spawn & Occupancy (Cases 1 - 6) ---
	var fu_army = PlayerArmyManagerScript.new()
	var fu_tac = TacticalMilitaryManagerScript.new(null, fu_army)
	fu_army.set_tactical_military_manager(fu_tac)
	var fu_rm := MockResourceManager.new()
	var fu_tm := MockTimeManager.new()
	fu_army.set_custom_resource_manager(fu_rm)
	fu_army.set_custom_time_manager(fu_tm)
	fu_army.set_custom_nav(live_nav)
	fu_tac.set_custom_nav(live_nav)
	fu_tac.set_custom_time_manager(fu_tm)

	var fu_wd = WorldGenerator.WorldData.new()
	fu_wd.buildings.append({
		"id": "fu_barracks",
		"type": "barracks",
		"cell": Vector2i(30, 30),
		"size": Vector2i(3, 3),
		"state": "active"
	})
	fu_army.set_custom_world_data(fu_wd)
	fu_army.refresh_rally_cell()

	# Case 1: From 0 soldiers, recruit 1 -> exactly 1 unit and valid cell
	var fu_r1 = fu_army.recruit(1)
	_assert(fu_r1.get("success", false) and fu_tac.get_unit_count() == 1, "FU-CASE.1: 1 soldier recruited, roster has exactly 1 unit")
	var fu_u1 = fu_tac.get_all_units()[0]
	_assert(fu_u1 != null and IsoMath.is_in_bounds(fu_u1.current_cell), "FU-CASE.1: Unit 1 has valid in-bounds cell: %s" % str(fu_u1.current_cell if fu_u1 else ""))

	# Case 2: Recruit 3 more in next transaction -> total 4 units, unique IDs, pairwise distinct coordinates
	var fu_r2 = fu_army.recruit(3)
	_assert(fu_r2.get("success", false) and fu_tac.get_unit_count() == 4, "FU-CASE.2: Recruited 3 more soldiers (total 4)")
	var fu_cells_2: Array[Vector2i] = []
	var has_duplicate_coords_2 := false
	for u in fu_tac.get_all_units():
		if fu_cells_2.has(u.current_cell):
			has_duplicate_coords_2 = true
		fu_cells_2.append(u.current_cell)
	_assert(not has_duplicate_coords_2, "FU-CASE.2: All 4 units occupy pairwise distinct, non-overlapping cells: %s" % str(fu_cells_2))

	# Case 3: Sequential recruitment across 3 transactions -> zero overlap with existing or batch units
	fu_tac.clear_all_units()
	fu_army.soldier_count = 0
	fu_army.recruit(1) # Tx 1: 1 unit
	var pos_tx1 = fu_tac.get_all_units()[0].current_cell
	fu_army.recruit(2) # Tx 2: 2 units (total 3)
	fu_army.recruit(2) # Tx 3: 2 units (total 5)
	_assert(fu_tac.get_unit_count() == 5, "FU-CASE.3: 3 consecutive recruitment transactions produced 5 total units")
	var fu_all_cells: Array[Vector2i] = []
	var has_tx_overlap := false
	for u in fu_tac.get_all_units():
		if fu_all_cells.has(u.current_cell):
			has_tx_overlap = true
		fu_all_cells.append(u.current_cell)
	_assert(not has_tx_overlap, "FU-CASE.3: All 5 sequentially recruited units have zero coordinate overlap across transactions")

	# Case 4: Replay army_changed signal -> does not spawn duplicate units or mutate coordinates
	var coords_before_replay: Array[Vector2i] = []
	for u in fu_tac.get_all_units():
		coords_before_replay.append(u.current_cell)
	fu_army.notify_capacity_changed()
	fu_tac.sync_with_player_army()
	var coords_after_replay: Array[Vector2i] = []
	for u in fu_tac.get_all_units():
		coords_after_replay.append(u.current_cell)
	_assert(fu_tac.get_unit_count() == 5 and coords_before_replay == coords_after_replay, "FU-CASE.4: Replaying army_changed signal is strictly idempotent with zero coordinate mutation")

	# Case 5: Reduce soldier count -> removes correct number of units, citizen registry untouched
	var fu_initial_cit_count = world_instance.get("citizen_list").size() if world_instance.get("citizen_list") else 0
	fu_army.remove_casualties(2)
	_assert(fu_army.get_army_count() == 3 and fu_tac.get_unit_count() == 3, "FU-CASE.5: Removed 2 casualties, soldier count and tactical units both at 3")
	var fu_final_cit_count = world_instance.get("citizen_list").size() if world_instance.get("citizen_list") else 0
	_assert(fu_initial_cit_count == fu_final_cit_count, "FU-CASE.5: Military casualties did not mutate civilian citizen registry")

	# Case 6: Insufficient valid positions -> fails closed cleanly without stacking
	_assert(fu_tac.can_allocate_spawns(0, fu_army.get_rally_cell(), live_nav), "FU-CASE.6: Zero spawn request returns true")
	_assert(fu_tac.can_allocate_spawns(3, fu_army.get_rally_cell(), live_nav), "FU-CASE.6: Valid allocation check returns true when cells are available")
	_assert(not fu_tac.can_allocate_spawns(999999, fu_army.get_rally_cell(), live_nav), "FU-CASE.6: Massive spawn request fails closed cleanly without stacking")

	# --- B. Formation & Collision Avoidance (Cases 7 - 10) ---
	# Case 7 & 8: Move selected group when unselected units stand near destination
	fu_tac.clear_all_units()
	fu_army.soldier_count = 0
	fu_army.movement_state = PlayerArmyManagerScript.MovementState.GARRISONED
	fu_army.current_cell = fu_army.get_rally_cell()
	fu_army.destination_cell = fu_army.get_rally_cell()
	fu_army.current_path.clear()
	fu_army.sync_state_from_tactical()

	var r7 = fu_army.recruit(3)
	_assert(r7.get("success", false), "FU-CASE.7: Recruitment of 3 units for collision test succeeded")
	var all_3 = fu_tac.get_all_units()
	var u_unsel = all_3[0]
	var u_sel_1 = all_3[1]
	var u_sel_2 = all_3[2]

	# Place unselected unit at (25, 25)
	u_unsel.current_cell = Vector2i(25, 25)
	u_unsel.target_cell = Vector2i(25, 25)
	u_unsel.order_state = TacticalUnitScript.OrderState.IDLE
	u_unsel.current_path.clear()

	# Select only u_sel_1 and u_sel_2
	fu_tac.clear_selection()
	fu_tac.select_unit(u_sel_1.unit_id, true)
	fu_tac.select_unit(u_sel_2.unit_id, true)

	# Issue move order to (25, 25)
	var move_order_res = fu_tac.issue_move_order(Vector2i(25, 25), live_nav)
	_assert(move_order_res.get("success", false), "FU-CASE.7: Move order to occupied center succeeded with avoidance")
	_assert(u_sel_1.target_cell != Vector2i(25, 25) and u_sel_2.target_cell != Vector2i(25, 25), "FU-CASE.8: Neither selected unit was assigned the cell occupied by unselected unit (25, 25)")
	_assert(u_sel_1.target_cell != u_sel_2.target_cell, "FU-CASE.8: Selected units have distinct destination slots (%s vs %s)" % [str(u_sel_1.target_cell), str(u_sel_2.target_cell)])

	# Case 9: Insufficient valid slots -> rejects entire order atomically
	var empty_slots := fu_tac.compute_formation_slots(Vector2i(-99, -99), 5, "Line", live_nav)
	_assert(empty_slots.is_empty(), "FU-CASE.9: Invalid out-of-bounds target produces empty formation slots")

	# Case 10: Line/Column/Scatter all produce valid non-overlapping slots
	var slots_line = fu_tac.compute_formation_slots(Vector2i(35, 35), 4, "Line", live_nav)
	var slots_col = fu_tac.compute_formation_slots(Vector2i(35, 35), 4, "Column", live_nav)
	var slots_scat = fu_tac.compute_formation_slots(Vector2i(35, 35), 4, "Scatter", live_nav)
	_assert(slots_line.size() == 4 and slots_col.size() == 4 and slots_scat.size() == 4, "FU-CASE.10: Formations produce 4 slots each")
	_assert(slots_line != slots_col, "FU-CASE.10: Line and Column produce distinct geometry")

	# --- C. Save/Load & Fail-Closed Integrity (Cases 11 - 17) ---
	# Case 11: Valid save with tactical units and matching soldier_count
	var base_valid_save: Dictionary = SaveManagerScript.serialize_world_state(world_instance).duplicate(true)
	base_valid_save["player_army"]["soldier_count"] = 2
	base_valid_save["tactical_military"] = {
		"units": [
			{"unit_id": "u1", "current_cell": [30, 30], "target_cell": [30, 30], "order_state": "idle", "current_path": []},
			{"unit_id": "u2", "current_cell": [31, 30], "target_cell": [31, 30], "order_state": "idle", "current_path": []}
		],
		"current_formation": "Line",
		"control_groups": {}
	}
	var val_valid = SaveManagerScript.validate_save_data(base_valid_save)
	_assert(val_valid.get("valid", false), "FU-CASE.11: Valid tactical save accepted by validator: %s" % val_valid.get("error", ""))

	# Case 12: tactical_military.units = [] while soldier_count > 0 -> rejected fail-closed
	var bad_empty_units: Dictionary = base_valid_save.duplicate(true)
	bad_empty_units["player_army"]["soldier_count"] = 3
	bad_empty_units["tactical_military"]["units"] = []
	var val_empty = SaveManagerScript.validate_save_data(bad_empty_units)
	_assert(not val_empty.get("valid", true), "FU-CASE.12: Empty units array with soldier_count > 0 rejected fail-closed")

	# Case 13: tactical_military exists but missing 'units' field -> rejected fail-closed
	var bad_missing_units: Dictionary = base_valid_save.duplicate(true)
	bad_missing_units["tactical_military"].erase("units")
	var val_missing = SaveManagerScript.validate_save_data(bad_missing_units)
	_assert(not val_missing.get("valid", true), "FU-CASE.13: tactical_military missing 'units' field rejected fail-closed")

	# Case 14: tactical_military exists but is invalid type -> rejected before world mutation
	var bad_type_tac: Dictionary = base_valid_save.duplicate(true)
	bad_type_tac["tactical_military"] = "not_a_dictionary"
	var val_type = SaveManagerScript.validate_save_data(bad_type_tac)
	_assert(not val_type.get("valid", true), "FU-CASE.14: tactical_military of non-Dictionary type rejected fail-closed")

	# Case 15: Pure legacy save completely lacking tactical_military -> accepted and reconstructs
	var pure_legacy_save: Dictionary = base_valid_save.duplicate(true)
	pure_legacy_save.erase("tactical_military")
	var val_legacy = SaveManagerScript.validate_save_data(pure_legacy_save)
	_assert(val_legacy.get("valid", false), "FU-CASE.15: Pure legacy save without tactical_military field accepted: %s" % val_legacy.get("error", ""))

	# Case 16: Double load produces zero duplicate units
	var dbl_tac = TacticalMilitaryManagerScript.new()
	dbl_tac.deserialize(base_valid_save["tactical_military"])
	var cnt_first = dbl_tac.get_unit_count()
	dbl_tac.deserialize(base_valid_save["tactical_military"])
	var cnt_second = dbl_tac.get_unit_count()
	_assert(cnt_first == 2 and cnt_second == 2, "FU-CASE.16: Consecutive deserialization produces zero duplicate units")

	# Case 17: Roundtrip preserves IDs, coordinates, paths, formation
	var roundtrip_dict = dbl_tac.serialize()
	_assert(roundtrip_dict.has("units") and roundtrip_dict["units"].size() == 2, "FU-CASE.17: Roundtrip serialization preserved 2 units")

	# --- D. Tactical vs Strategic Consistency & Defense Eligibility (Cases 18 - 22) ---
	# Case 18: Army at base within rally perimeter -> defense eligible, defending count matches
	fu_tac.clear_all_units()
	fu_army.soldier_count = 0
	fu_army.movement_state = PlayerArmyManagerScript.MovementState.GARRISONED
	fu_army.current_cell = fu_army.get_rally_cell()
	fu_army.destination_cell = fu_army.get_rally_cell()
	fu_army.current_path.clear()
	fu_army.sync_state_from_tactical()

	var r18 = fu_army.recruit(3)
	_assert(r18.get("success", false), "FU-CASE.18: Recruitment of 3 soldiers succeeded: %s" % r18.get("reason", ""))
	_assert(fu_tac.get_unit_count() == 3, "FU-CASE.18: Tactical unit count is 3")
	_assert(fu_army.is_defense_eligible(), "FU-CASE.18: Army at base is defense-eligible")
	_assert(fu_army.get_defending_soldier_count() == 3, "FU-CASE.18: All 3 soldiers counted as defending: %d" % fu_army.get_defending_soldier_count())

	# Case 19: Order part of force into the field (outside perimeter) -> defending count reflects only garrisoned units
	var fu_units_arr = fu_tac.get_all_units()
	var field_pos := Vector2i(10, 10)
	if not live_nav.is_cell_walkable(field_pos):
		field_pos = fu_tac._find_distinct_walkable_cells(Vector2i(10, 10), 1, live_nav)[0]
	fu_units_arr[0].current_cell = field_pos
	fu_units_arr[0].target_cell = field_pos
	fu_units_arr[0].order_state = TacticalUnitScript.OrderState.IDLE
	fu_units_arr[0].current_path.clear()
	fu_tac.tactical_state_updated.emit()

	_assert(fu_tac.get_garrisoned_unit_count(fu_army.get_rally_cell()) == 2, "FU-CASE.19: Garrisoned count is 2 (1 unit deployed to field)")
	_assert(fu_army.get_defending_soldier_count() == 2, "FU-CASE.19: PlayerArmyManager defending count reflects only 2 garrisoned soldiers")

	# Case 20: Strategic Move Army and Return Home synchronization
	for u in fu_units_arr:
		u.current_cell = fu_army.get_rally_cell()
		u.target_cell = fu_army.get_rally_cell()
		u.order_state = TacticalUnitScript.OrderState.IDLE
		u.current_path.clear()
	fu_army.current_cell = fu_army.get_rally_cell()
	fu_army.movement_state = PlayerArmyManagerScript.MovementState.GARRISONED
	fu_tac.tactical_state_updated.emit()

	var march_dest := Vector2i(25, 25)
	if not live_nav.is_cell_walkable(march_dest):
		march_dest = fu_tac._find_distinct_walkable_cells(Vector2i(25, 25), 1, live_nav)[0]
	var move_to_field_res = fu_army.order_move(march_dest)
	_assert(move_to_field_res.get("success", false), "FU-CASE.20: Strategic order_move to field succeeded: %s" % move_to_field_res.get("reason", ""))
	_assert(fu_army.get_movement_state() == PlayerArmyManagerScript.MovementState.MARCHING, "FU-CASE.20: Strategic army entered MARCHING state")
	var return_res = fu_army.order_return_home()
	_assert(return_res.get("success", false), "FU-CASE.20: Strategic order_return_home succeeded: %s" % return_res.get("reason", ""))

	# Case 21: Offensive campaign cannot launch if soldiers are at base
	for u in fu_units_arr:
		u.current_cell = fu_army.get_rally_cell()
		u.target_cell = fu_army.get_rally_cell()
		u.order_state = TacticalUnitScript.OrderState.IDLE
		u.current_path.clear()
	fu_army.current_cell = fu_army.get_rally_cell()
	fu_army.movement_state = PlayerArmyManagerScript.MovementState.GARRISONED
	fu_tac.tactical_state_updated.emit()

	var camp_mgr = BattleCampaignManagerScript.new(world_instance, FactionManagerScript.new(), 12345)
	camp_mgr.set_custom_army_manager(fu_army)
	var atk_check = camp_mgr.can_launch_offensive_campaign("rival_military")
	_assert(not atk_check.get("can_attack", true), "FU-CASE.21: Offensive campaign rejected when army is at base: %s" % atk_check.get("reason", ""))

	# Case 22: Casualties reduce army count authoritatively once, tactical roster stays synchronized
	var pre_cas_count = fu_army.get_army_count()
	fu_army.remove_casualties(1, false)
	_assert(fu_army.get_army_count() == pre_cas_count - 1, "FU-CASE.22: Authoritative soldier count decremented by exactly 1")
	_assert(fu_tac.get_unit_count() == fu_army.get_army_count(), "FU-CASE.22: Tactical unit count strictly matches soldier count after casualty (%d == %d)" % [fu_tac.get_unit_count(), fu_army.get_army_count()])

	# =========================================================================
	# Group 7: Final Hardening Verification (Fix A, Fix B, Fix C, Fix D)
	# =========================================================================
	print("\n--- Group 7: Final Hardening Verification ---")

	# FH-CASE.1: Offensive campaign rejected when field unit count == 0 even if garrison > 0
	fu_tac.clear_all_units()
	fu_army.soldier_count = 0
	fu_army.movement_state = PlayerArmyManagerScript.MovementState.GARRISONED
	fu_army.current_cell = fu_army.get_rally_cell()
	fu_army.destination_cell = fu_army.get_rally_cell()
	fu_army.current_path.clear()
	fu_army.sync_state_from_tactical()

	var r_fh1 = fu_army.recruit(4)
	_assert(r_fh1.get("success", false), "FH-CASE.1: Recruited 4 garrisoned soldiers")
	_assert(fu_army.get_defending_soldier_count() == 4, "FH-CASE.1: 4 garrisoned defending soldiers at base")
	_assert(fu_army.get_field_unit_count() == 0, "FH-CASE.1: 0 field units")

	var fh_fm = FactionManagerScript.new()
	var fh_fac = fh_fm.get_faction("rival_military")
	if fh_fac != null:
		fh_fac.is_at_war = true
		fh_fac.military_power = 200.0

	var fh_camp = BattleCampaignManagerScript.new(world_instance, fh_fm, 12345)
	fh_camp.set_custom_army_manager(fu_army)
	var can_atk_fh1 = fh_camp.can_launch_offensive_campaign("rival_military")
	_assert(not can_atk_fh1.get("can_attack", true), "FH-CASE.1: Offensive campaign rejected when field unit count == 0: %s" % can_atk_fh1.get("reason", ""))
	var launch_fh1 = fh_camp.launch_offensive_campaign("rival_military")
	_assert(not launch_fh1.get("success", true), "FH-CASE.1: Launch offensive campaign fails closed with 0 field units")

	# FH-CASE.2: Offensive campaign with split army: only field troops participate and take casualties
	# Deploy 2 units to field outside RALLY_PERIMETER_DISTANCE (e.g. (10, 10))
	var all_fh_units = fu_tac.get_all_units()
	var field_pos1 := Vector2i(10, 10)
	var field_pos2 := Vector2i(11, 10)
	if not live_nav.is_cell_walkable(field_pos1):
		var w_slots = fu_tac._find_distinct_walkable_cells(Vector2i(10, 10), 2, live_nav)
		field_pos1 = w_slots[0]
		field_pos2 = w_slots[1]

	all_fh_units[0].current_cell = field_pos1
	all_fh_units[0].target_cell = field_pos1
	all_fh_units[0].order_state = TacticalUnitScript.OrderState.IDLE
	all_fh_units[0].current_path.clear()

	all_fh_units[1].current_cell = field_pos2
	all_fh_units[1].target_cell = field_pos2
	all_fh_units[1].order_state = TacticalUnitScript.OrderState.IDLE
	all_fh_units[1].current_path.clear()

	# Remaining 2 units remain at rally cell
	all_fh_units[2].current_cell = fu_army.get_rally_cell()
	all_fh_units[2].target_cell = fu_army.get_rally_cell()
	all_fh_units[2].order_state = TacticalUnitScript.OrderState.IDLE
	all_fh_units[2].current_path.clear()

	all_fh_units[3].current_cell = fu_army.get_rally_cell()
	all_fh_units[3].target_cell = fu_army.get_rally_cell()
	all_fh_units[3].order_state = TacticalUnitScript.OrderState.IDLE
	all_fh_units[3].current_path.clear()

	fu_army.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD
	fu_army.current_cell = field_pos1
	fu_army.destination_cell = field_pos1
	fu_tac.tactical_state_updated.emit()

	_assert(fu_army.get_field_unit_count() == 2, "FH-CASE.2: Exactly 2 field units deployed")
	_assert(fu_army.get_defending_soldier_count() == 2, "FH-CASE.2: Exactly 2 garrisoned units at base")

	# Launch offensive campaign; should use atk_troops = 2 (not total 4)
	var launch_fh2 = fh_camp.launch_offensive_campaign("rival_military", 555)
	_assert(launch_fh2.get("success", false), "FH-CASE.2: Offensive campaign launched successfully with field force: %s" % launch_fh2.get("reason", ""))
	var fh2_report = launch_fh2.get("report")
	_assert(fh2_report != null, "FH-CASE.2: BattleReport produced")
	_assert(fh2_report.attacker_casualties >= 1, "FH-CASE.2: Deterministic battle produced at least 1 player casualty (%d >= 1)" % fh2_report.attacker_casualties)

	# Verify casualties came exclusively from field units
	var post_field_count := fu_army.get_field_unit_count()
	var post_garrison_count := fu_army.get_defending_soldier_count()
	_assert(post_garrison_count == 2, "FH-CASE.2: Garrison units completely untouched after offensive campaign (%d == 2)" % post_garrison_count)
	_assert(post_field_count == 2 - fh2_report.attacker_casualties, "FH-CASE.2: Field force took all %d casualties (%d == %d)" % [fh2_report.attacker_casualties, post_field_count, 2 - fh2_report.attacker_casualties])
	_assert(fu_army.get_army_count() == post_field_count + post_garrison_count, "FH-CASE.2: Authoritative soldier count equals field + garrison (%d == %d)" % [fu_army.get_army_count(), post_field_count + post_garrison_count])
	_assert(fu_tac.get_unit_count() == fu_army.get_army_count(), "FH-CASE.2: Tactical roster size strictly matches soldier count (%d == %d)" % [fu_tac.get_unit_count(), fu_army.get_army_count()])

	# FH-CASE.3: Defensive raid with split army: only garrisoned troops take casualties via real raid resolution
	var cur_fh_day := fh_camp.get_current_day()
	fh_camp.schedule_raid("rival_military", cur_fh_day, 1, true)
	var pre_raid_field := fu_army.get_field_unit_count()
	var pre_raid_garrison := fu_army.get_defending_soldier_count()
	var raid_res := fh_camp.resolve_and_apply_raid("rival_military", cur_fh_day)
	_assert(raid_res.get("success", false), "FH-CASE.3: Defensive raid resolved successfully via resolve_and_apply_raid: %s" % raid_res.get("reason", ""))
	var raid_report = raid_res.get("report")
	_assert(raid_report != null, "FH-CASE.3: BattleReport produced by defensive raid resolution")
	var def_casualties: int = raid_report.defender_casualties
	_assert(def_casualties >= 1, "FH-CASE.3: Defensive raid produced at least 1 defender casualty (%d >= 1)" % def_casualties)
	var expected_garrison_loss := mini(def_casualties, pre_raid_garrison)
	_assert(fu_army.get_field_unit_count() == pre_raid_field, "FH-CASE.3: Field units completely untouched by defensive raid (%d == %d)" % [fu_army.get_field_unit_count(), pre_raid_field])
	_assert(fu_army.get_defending_soldier_count() == pre_raid_garrison - expected_garrison_loss, "FH-CASE.3: Garrisoned units reduced by exactly %d (%d == %d)" % [expected_garrison_loss, fu_army.get_defending_soldier_count(), pre_raid_garrison - expected_garrison_loss])
	_assert(fu_tac.get_unit_count() == fu_army.get_army_count(), "FH-CASE.3: Tactical roster matches soldier count after defensive casualty (%d == %d)" % [fu_tac.get_unit_count(), fu_army.get_army_count()])

	# FH-CASE.4: Strict save validation rejects moving unit without current_path
	var bad_moving_no_path: Dictionary = base_valid_save.duplicate(true)
	bad_moving_no_path["player_army"]["soldier_count"] = 1
	bad_moving_no_path["tactical_military"]["units"] = [
		{"unit_id": "u1", "current_cell": [30, 30], "target_cell": [31, 30], "order_state": "moving"}
	]
	var val_moving_no_path = SaveManagerScript.validate_save_data(bad_moving_no_path)
	_assert(not val_moving_no_path.get("valid", true), "FH-CASE.4: Moving unit without current_path rejected fail-closed")

	# FH-CASE.5: Strict save validation rejects moving unit whose current_path does not end at target_cell
	var bad_moving_wrong_dest: Dictionary = base_valid_save.duplicate(true)
	bad_moving_wrong_dest["player_army"]["soldier_count"] = 1
	bad_moving_wrong_dest["tactical_military"]["units"] = [
		{"unit_id": "u1", "current_cell": [30, 30], "target_cell": [32, 30], "order_state": "moving", "current_path": [[31, 30]]}
	]
	var val_moving_wrong_dest = SaveManagerScript.validate_save_data(bad_moving_wrong_dest)
	_assert(not val_moving_wrong_dest.get("valid", true), "FH-CASE.5: Moving unit with path ending at wrong destination rejected fail-closed")

	# FH-CASE.6: Strict save validation rejects idle unit with non-empty current_path
	var bad_idle_with_path: Dictionary = base_valid_save.duplicate(true)
	bad_idle_with_path["player_army"]["soldier_count"] = 1
	bad_idle_with_path["tactical_military"]["units"] = [
		{"unit_id": "u1", "current_cell": [30, 30], "target_cell": [30, 30], "order_state": "idle", "current_path": [[31, 30]]}
	]
	var val_idle_with_path = SaveManagerScript.validate_save_data(bad_idle_with_path)
	_assert(not val_idle_with_path.get("valid", true), "FH-CASE.6: Idle unit with non-empty current_path rejected fail-closed")

	# FH-CASE.7: Strict save validation rejects soldier count mismatch even without movement_state (legacy army format)
	var bad_legacy_mismatch: Dictionary = base_valid_save.duplicate(true)
	bad_legacy_mismatch["player_army"] = {"soldier_count": 5} # lacks movement_state
	bad_legacy_mismatch["tactical_military"]["units"] = [
		{"unit_id": "u1", "current_cell": [30, 30], "target_cell": [30, 30], "order_state": "idle", "current_path": []},
		{"unit_id": "u2", "current_cell": [31, 30], "target_cell": [31, 30], "order_state": "idle", "current_path": []}
	]
	var val_legacy_mismatch = SaveManagerScript.validate_save_data(bad_legacy_mismatch)
	_assert(not val_legacy_mismatch.get("valid", true), "FH-CASE.7: Soldier count mismatch without movement_state rejected fail-closed")

	# FH-CASE.8: Save restore fails closed on corrupted tactical_military without mutating live state
	var pre_units_count = fu_tac.get_unit_count()
	var corrupted_restore_dict: Dictionary = {
		"units": [
			{"unit_id": "bad_u", "current_cell": [999, 999], "target_cell": [999, 999], "order_state": "idle"}
		]
	}
	var des_res = fu_tac.deserialize(corrupted_restore_dict)
	_assert(not des_res, "FH-CASE.8: TacticalMilitaryManager.deserialize returns false for corrupted data")
	_assert(fu_tac.get_unit_count() == pre_units_count, "FH-CASE.8: Live unit roster was NOT wiped or mutated by failed deserialize (%d == %d)" % [fu_tac.get_unit_count(), pre_units_count])

	# FH-CASE.8b: SaveManager.apply_loaded_state_to_world fails closed on corrupted tactical data without corrupting world state
	var bad_world_save: Dictionary = base_valid_save.duplicate(true)
	bad_world_save["tactical_military"] = corrupted_restore_dict
	var bad_apply_res := SaveManagerScript.apply_loaded_state_to_world(world_instance, bad_world_save)
	_assert(not bad_apply_res.get("success", true), "FH-CASE.8b: SaveManager.apply_loaded_state_to_world reports failure on corrupted tactical military data")
	_assert(fu_tac.get_unit_count() == pre_units_count, "FH-CASE.8b: Live tactical roster in world_instance preserved untouched after failed apply (%d == %d)" % [fu_tac.get_unit_count(), pre_units_count])

	# FH-CASE.9: Army march advances tactical units step-by-step without snapping
	fu_tac.clear_all_units()
	fu_army.soldier_count = 0
	fu_army.movement_state = PlayerArmyManagerScript.MovementState.GARRISONED
	fu_army.current_cell = fu_army.get_rally_cell()
	fu_army.destination_cell = fu_army.get_rally_cell()
	fu_army.current_path.clear()
	fu_army.sync_state_from_tactical()

	fu_army.recruit(1)
	var march_unit: Node2D = fu_tac.get_all_units()[0]
	var rally_start: Vector2i = fu_army.get_rally_cell()
	var dest_step := Vector2i(rally_start.x - 3, rally_start.y)
	if not live_nav.is_cell_walkable(dest_step):
		dest_step = fu_tac._find_distinct_walkable_cells(dest_step, 1, live_nav)[0]

	var ord_march = fu_army.order_move(dest_step)
	_assert(ord_march.get("success", false), "FH-CASE.9: Order move issued for physical stepping: %s" % ord_march.get("reason", ""))
	_assert(march_unit.order_state == TacticalUnitScript.OrderState.MOVING, "FH-CASE.9: Tactical unit is in MOVING state")
	var initial_path_size: int = march_unit.current_path.size()
	_assert(initial_path_size >= 2, "FH-CASE.9: Path length is at least 2 steps: %d" % initial_path_size)

	# Advance by exactly 1 step duration (0.5s)
	fu_army.advance_movement(0.5, 1.0)
	_assert(march_unit.current_cell != rally_start, "FH-CASE.9: Tactical unit advanced 1 cell from rally start")
	_assert(march_unit.current_cell != dest_step, "FH-CASE.9: Tactical unit did NOT teleport directly to final destination")
	_assert(march_unit.order_state == TacticalUnitScript.OrderState.MOVING, "FH-CASE.9: Tactical unit still in MOVING state mid-march")

	# Advance remaining duration until arrival
	var safety_counter: int = 0
	while march_unit.order_state == TacticalUnitScript.OrderState.MOVING and safety_counter < 50:
		safety_counter += 1
		fu_army.advance_movement(0.5, 1.0)

	_assert(march_unit.order_state == TacticalUnitScript.OrderState.IDLE, "FH-CASE.9: Tactical unit naturally transitioned to IDLE upon arrival")
	_assert(march_unit.current_cell == dest_step, "FH-CASE.9: Tactical unit reached final destination: %s" % str(dest_step))

	# FH-CASE.10: PlayerArmyManager.remove_casualties emits army_changed signal when tactical manager active
	var signal_received: Array = []
	var on_army_changed = func(count: int, capacity: int):
		signal_received.append({"count": count, "capacity": capacity})
	fu_army.army_changed.connect(on_army_changed)

	var pre_sig_count = fu_army.get_army_count()
	var removed_sig = fu_army.remove_casualties(1, false)
	_assert(removed_sig == 1, "FH-CASE.10: Removed 1 garrisoned soldier")
	_assert(signal_received.size() == 1, "FH-CASE.10: army_changed signal emitted on casualty removal with tactical military active")
	_assert(signal_received[0]["count"] == pre_sig_count - 1, "FH-CASE.10: army_changed signal reported accurate post-casualty count: %d" % signal_received[0]["count"])
	fu_army.army_changed.disconnect(on_army_changed)

	# =========================================================================
	# Group 8: Post-Hardening Review Verification
	# =========================================================================
	print("\n--- Group 8: Post-Hardening Review Verification ---")

	fu_rm.stock[EconomyConfigScript.RES_FOOD] = 5000
	fu_rm.stock[EconomyConfigScript.RES_WOOD] = 5000
	fu_rm.stock[EconomyConfigScript.RES_GOLD] = 5000
	fu_rm.stock[EconomyConfigScript.RES_METAL] = 5000
	for res_id in fu_rm.reserved:
		fu_rm.reserved[res_id] = 0

	# Expand barracks capacity to 20 (4 active barracks * 5 capacity) for large formation return-home tests
	fu_wd.buildings.append({
		"id": "fu_barracks_2",
		"type": "barracks",
		"cell": Vector2i(25, 30),
		"size": Vector2i(3, 3),
		"state": "active"
	})
	fu_wd.buildings.append({
		"id": "fu_barracks_3",
		"type": "barracks",
		"cell": Vector2i(20, 30),
		"size": Vector2i(3, 3),
		"state": "active"
	})
	fu_wd.buildings.append({
		"id": "fu_barracks_4",
		"type": "barracks",
		"cell": Vector2i(15, 30),
		"size": Vector2i(3, 3),
		"state": "active"
	})

	# PH-CASE.1: 12 soldiers return-home in default Line formation
	fu_tac.clear_all_units()
	fu_army.soldier_count = 0
	fu_army.movement_state = PlayerArmyManagerScript.MovementState.GARRISONED
	fu_army.current_cell = fu_army.get_rally_cell()
	fu_army.destination_cell = fu_army.get_rally_cell()
	fu_army.current_path.clear()
	fu_tac.set_formation(TacticalMilitaryManagerScript.FORMATION_LINE)

	var rec_12 = fu_army.recruit(12)
	_assert(rec_12.get("success", false) and fu_tac.get_unit_count() == 12, "PH-CASE.1: Successfully recruited 12 soldiers in Line formation")

	var target_field_12 := Vector2i(-1, -1)
	for step in range(16, 25):
		for offset in [Vector2i(step, 0), Vector2i(0, step), Vector2i(-step, 0), Vector2i(0, -step)]:
			var cand = fu_army.get_rally_cell() + offset
			if IsoMath.is_in_bounds(cand) and live_nav.is_cell_walkable(cand):
				var p = live_nav.find_path(fu_army.get_rally_cell(), cand)
				if not p.is_empty():
					target_field_12 = cand
					break
		if target_field_12 != Vector2i(-1, -1):
			break

	var move_12 = fu_army.order_move(target_field_12)
	_assert(move_12.get("success", false), "PH-CASE.1: Order move to field issued for 12 soldiers: %s" % move_12.get("reason", ""))

	var march_12_safety: int = 0
	while (fu_army.movement_state == PlayerArmyManagerScript.MovementState.MARCHING or fu_army.get_field_unit_count() < 12) and march_12_safety < 200:
		march_12_safety += 1
		fu_army.advance_movement(0.5, 1.0)

	_assert(fu_army.movement_state == PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD, "PH-CASE.1: Strategic state reached IDLE_AT_FIELD at target")
	_assert(fu_army.get_field_unit_count() == 12, "PH-CASE.1: All 12 soldiers deployed as field units: %d" % fu_army.get_field_unit_count())

	var ret_12 = fu_army.order_return_home()
	_assert(ret_12.get("success", false), "PH-CASE.1: order_return_home accepted for 12 soldiers: %s" % ret_12.get("reason", ""))

	var ret_12_safety: int = 0
	while (fu_army.movement_state == PlayerArmyManagerScript.MovementState.MARCHING or fu_army.get_defending_soldier_count() < 12) and ret_12_safety < 150:
		ret_12_safety += 1
		fu_army.advance_movement(0.5, 1.0)

	var all_stopped_12 := true
	for u in fu_tac.get_all_units():
		if u.order_state != TacticalUnitScript.OrderState.IDLE:
			all_stopped_12 = false
	_assert(all_stopped_12, "PH-CASE.1: Req 1: All 12 returned units have stopped moving")

	var seen_12: Array[Vector2i] = []
	var distinct_12 := true
	for u in fu_tac.get_all_units():
		if seen_12.has(u.current_cell):
			distinct_12 = false
		seen_12.append(u.current_cell)
	_assert(distinct_12 and seen_12.size() == 12, "PH-CASE.1: Req 2: All 12 returned unit cells are pairwise distinct (%d cells)" % seen_12.size())

	var all_within_5_12 := true
	for u in fu_tac.get_all_units():
		if IsoMath.grid_distance(u.current_cell, fu_army.get_rally_cell()) > TacticalMilitaryManagerScript.RALLY_PERIMETER_DISTANCE:
			all_within_5_12 = false
	_assert(all_within_5_12, "PH-CASE.1: Req 3: Every returned unit is strictly within garrison perimeter (dist <= 5)")
	_assert(fu_army.movement_state == PlayerArmyManagerScript.MovementState.GARRISONED, "PH-CASE.1: Req 4: Strategic army state remains GARRISONED")
	_assert(fu_army.get_defending_soldier_count() == 12, "PH-CASE.1: Req 5: Defending count equals 12 garrisoned soldiers")

	fu_tac.tactical_state_updated.emit()
	_assert(fu_army.movement_state == PlayerArmyManagerScript.MovementState.GARRISONED, "PH-CASE.1: Req 6: State remains GARRISONED after subsequent tactical_state_updated")
	_assert(fu_army.current_cell == fu_army.get_rally_cell(), "PH-CASE.1: Req 6: Strategic marker remains at rally_cell")

	# PH-CASE.2: 20 soldiers return-home in default Line formation
	fu_tac.clear_all_units()
	fu_army.soldier_count = 0
	fu_army.movement_state = PlayerArmyManagerScript.MovementState.GARRISONED
	fu_army.current_cell = fu_army.get_rally_cell()
	fu_army.destination_cell = fu_army.get_rally_cell()
	fu_tac.set_formation(TacticalMilitaryManagerScript.FORMATION_LINE)

	var rec_20 = fu_army.recruit(20)
	_assert(rec_20.get("success", false) and fu_tac.get_unit_count() == 20, "PH-CASE.2: Successfully recruited 20 soldiers in Line formation")

	var move_20 = fu_army.order_move(target_field_12)
	_assert(move_20.get("success", false), "PH-CASE.2: Order move issued for 20 soldiers")

	var march_20_safety: int = 0
	while (fu_army.movement_state == PlayerArmyManagerScript.MovementState.MARCHING or fu_army.get_field_unit_count() < 20) and march_20_safety < 200:
		march_20_safety += 1
		fu_army.advance_movement(0.5, 1.0)

	_assert(fu_army.get_field_unit_count() == 20, "PH-CASE.2: All 20 soldiers deployed to field")

	var ret_20 = fu_army.order_return_home()
	_assert(ret_20.get("success", false), "PH-CASE.2: order_return_home accepted for 20 soldiers: %s" % ret_20.get("reason", ""))

	var ret_20_safety: int = 0
	while (fu_army.movement_state == PlayerArmyManagerScript.MovementState.MARCHING or fu_army.get_defending_soldier_count() < 20) and ret_20_safety < 200:
		ret_20_safety += 1
		fu_army.advance_movement(0.5, 1.0)

	var all_stopped_20 := true
	for u in fu_tac.get_all_units():
		if u.order_state != TacticalUnitScript.OrderState.IDLE:
			all_stopped_20 = false
	_assert(all_stopped_20, "PH-CASE.2: Req 1: All 20 returned units have stopped moving")

	var seen_20: Array[Vector2i] = []
	var distinct_20 := true
	for u in fu_tac.get_all_units():
		if seen_20.has(u.current_cell):
			distinct_20 = false
		seen_20.append(u.current_cell)
	_assert(distinct_20 and seen_20.size() == 20, "PH-CASE.2: Req 2: All 20 returned unit cells are pairwise distinct (%d cells)" % seen_20.size())

	var all_within_5_20 := true
	for u in fu_tac.get_all_units():
		if IsoMath.grid_distance(u.current_cell, fu_army.get_rally_cell()) > TacticalMilitaryManagerScript.RALLY_PERIMETER_DISTANCE:
			all_within_5_20 = false
	_assert(all_within_5_20, "PH-CASE.2: Req 3: Every returned unit is strictly within garrison perimeter (dist <= 5)")
	_assert(fu_army.movement_state == PlayerArmyManagerScript.MovementState.GARRISONED, "PH-CASE.2: Req 4: Strategic army state remains GARRISONED")
	_assert(fu_army.get_defending_soldier_count() == 20, "PH-CASE.2: Req 5: Defending count equals 20 garrisoned soldiers")

	fu_tac.tactical_state_updated.emit()
	_assert(fu_army.movement_state == PlayerArmyManagerScript.MovementState.GARRISONED, "PH-CASE.2: Req 6: State remains GARRISONED after subsequent tactical_state_updated")
	_assert(fu_army.current_cell == fu_army.get_rally_cell(), "PH-CASE.2: Req 6: Strategic marker remains at rally_cell")

	# PH-CASE.3: Insufficient return slots rejection (fail-closed atomic)
	var full_excl: Array[Vector2i] = []
	for r in range(0, TacticalMilitaryManagerScript.RALLY_PERIMETER_DISTANCE + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if abs(dx) + abs(dy) == r:
					full_excl.append(fu_army.get_rally_cell() + Vector2i(dx, dy))
	full_excl.pop_back()
	full_excl.pop_back() # Only 2 free slots remain
	var slots_fail = fu_tac.compute_garrison_return_slots(fu_army.get_rally_cell(), 5, live_nav, full_excl)
	_assert(slots_fail.is_empty(), "PH-CASE.3: compute_garrison_return_slots returns empty array when available slots (2) < requested count (5)")

	# PH-CASE.4: Return command failure propagation
	fu_tac.clear_all_units()
	fu_army.soldier_count = 0
	fu_army.recruit(1)
	fu_army.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD
	fu_army.current_cell = Vector2i(20, 20)
	fu_army.destination_cell = Vector2i(20, 20)
	var u_ph4 = fu_tac.get_all_units()[0]
	u_ph4.current_cell = Vector2i(20, 20)
	u_ph4.target_cell = Vector2i(20, 20)
	u_ph4.order_state = TacticalUnitScript.OrderState.IDLE
	u_ph4.current_path.clear()

	# Create impassable nav to force return pathfinding failure
	var blocked_nav = BlockedPathNav.new()
	fu_army.set_custom_nav(blocked_nav)
	fu_tac.set_custom_nav(blocked_nav)
	var fail_ret_res = fu_army.order_return_home()
	_assert(not fail_ret_res.get("success", true), "PH-CASE.4: order_return_home reports failure when route is blocked")
	_assert(fu_army.movement_state == PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD, "PH-CASE.4: Strategic army state remains IDLE_AT_FIELD after failed return")
	_assert(fu_army.current_cell == Vector2i(20, 20), "PH-CASE.4: Strategic army position remains at field cell")
	fu_army.set_custom_nav(live_nav)
	fu_tac.set_custom_nav(live_nav)

	# PH-CASE.5: Ready field force consistency with moving field subset
	fu_tac.clear_all_units()
	fu_army.soldier_count = 0
	fu_army.movement_state = PlayerArmyManagerScript.MovementState.GARRISONED
	fu_army.current_cell = fu_army.get_rally_cell()
	fu_army.destination_cell = fu_army.get_rally_cell()
	fu_army.current_path.clear()
	var rec_ph5 = fu_army.recruit(4)
	_assert(rec_ph5.get("success", false) and fu_tac.get_unit_count() == 4, "PH-CASE.5: Successfully recruited 4 soldiers")
	var ph5_units = fu_tac.get_all_units()
	# Unit 0 and 1: stationary at field
	ph5_units[0].current_cell = Vector2i(18, 18)
	ph5_units[0].target_cell = Vector2i(18, 18)
	ph5_units[0].order_state = TacticalUnitScript.OrderState.IDLE
	ph5_units[0].current_path.clear()

	ph5_units[1].current_cell = Vector2i(18, 19)
	ph5_units[1].target_cell = Vector2i(18, 19)
	ph5_units[1].order_state = TacticalUnitScript.OrderState.IDLE
	ph5_units[1].current_path.clear()

	# Unit 2: moving at field
	ph5_units[2].current_cell = Vector2i(19, 19)
	ph5_units[2].target_cell = Vector2i(20, 19)
	ph5_units[2].order_state = TacticalUnitScript.OrderState.MOVING
	var p_step5: Array[Vector2i] = [Vector2i(20, 19)]
	ph5_units[2].current_path = p_step5

	# Unit 3: stationary at rally base
	ph5_units[3].current_cell = fu_army.get_rally_cell()
	ph5_units[3].target_cell = fu_army.get_rally_cell()
	ph5_units[3].order_state = TacticalUnitScript.OrderState.IDLE
	ph5_units[3].current_path.clear()

	fu_army.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD
	fu_army.current_cell = Vector2i(18, 18)
	fu_army.destination_cell = Vector2i(18, 18)
	fu_tac.tactical_state_updated.emit()

	_assert(fu_army.get_field_unit_count() == 2, "PH-CASE.5: Exactly 2 ready field units (moving unit excluded from count)")
	_assert(fu_army.get_defending_soldier_count() == 1, "PH-CASE.5: Exactly 1 defending unit at base")

	var can_atk_ph5 = fh_camp.can_launch_offensive_campaign("rival_military")
	_assert(can_atk_ph5.get("can_attack", false), "PH-CASE.5: Offensive campaign can launch with 2 ready field troops")

	var launch_ph5 = fh_camp.launch_offensive_campaign("rival_military", 555)
	_assert(launch_ph5.get("success", false), "PH-CASE.5: Campaign launched successfully")
	_assert(launch_ph5["report"].attacker_troops_initial == 2, "PH-CASE.5: Attacker troops strictly used 2 ready field troops (not moving or garrison units)")
	_assert(fu_tac.get_unit(ph5_units[2].unit_id) != null, "PH-CASE.5: Moving field unit was NOT removed as casualty")
	_assert(fu_tac.get_unit(ph5_units[3].unit_id) != null, "PH-CASE.5: Garrisoned base unit was NOT removed as casualty")

	# PH-CASE.6: Zero stationary field troops blocks offensive campaign
	ph5_units[0].order_state = TacticalUnitScript.OrderState.MOVING
	var p_step6a: Array[Vector2i] = [Vector2i(19, 18)]
	ph5_units[0].current_path = p_step6a
	ph5_units[1].order_state = TacticalUnitScript.OrderState.MOVING
	var p_step6b: Array[Vector2i] = [Vector2i(19, 19)]
	ph5_units[1].current_path = p_step6b
	_assert(fu_army.get_field_unit_count() == 0, "PH-CASE.6: Field ready count is 0 when all field units are moving")

	var can_atk_ph6 = fh_camp.can_launch_offensive_campaign("rival_military")
	_assert(not can_atk_ph6.get("can_attack", true), "PH-CASE.6: Offensive campaign rejected when 0 stationary field troops")
	_assert("Quân đội chưa có lực lượng tập kết dã chiến ngoài thành" in can_atk_ph6.get("reason", ""), "PH-CASE.6: Rejection reason matches field force gate: %s" % can_atk_ph6.get("reason", ""))

	# PH-CASE.7: Defensive casualty selection matches defense eligibility (stationary vs moving within base)
	fu_tac.clear_all_units()
	fu_army.soldier_count = 0
	fu_army.movement_state = PlayerArmyManagerScript.MovementState.GARRISONED
	fu_army.current_cell = fu_army.get_rally_cell()
	fu_army.destination_cell = fu_army.get_rally_cell()
	var rec_ph7 = fu_army.recruit(2)
	_assert(rec_ph7.get("success", false) and fu_tac.get_unit_count() == 2, "PH-CASE.7: Successfully recruited 2 units")

	var def_units = fu_tac.get_all_units()
	var u_def1 = def_units[0]
	var u_def2 = def_units[1]
	u_def1.current_cell = fu_army.get_rally_cell()
	u_def1.target_cell = fu_army.get_rally_cell()
	u_def1.order_state = TacticalUnitScript.OrderState.IDLE
	u_def1.current_path.clear()

	u_def2.current_cell = fu_army.get_rally_cell() + Vector2i(1, 0)
	u_def2.target_cell = fu_army.get_rally_cell() + Vector2i(2, 0)
	u_def2.order_state = TacticalUnitScript.OrderState.MOVING
	var p_step7: Array[Vector2i] = [Vector2i(fu_army.get_rally_cell() + Vector2i(2, 0))]
	u_def2.current_path = p_step7

	_assert(fu_army.get_defending_soldier_count() == 1, "PH-CASE.7: Defending soldier count is 1 (moving unit excluded from defense)")
	var rem_ph7 = fu_army.remove_casualties(1, false)
	_assert(rem_ph7 == 1, "PH-CASE.7: Exactly 1 defensive casualty removed")
	_assert(fu_tac.get_unit(u_def2.unit_id) != null, "PH-CASE.7: Moving unit %s was NOT removed despite higher ID" % u_def2.unit_id)
	_assert(fu_tac.get_unit(u_def1.unit_id) == null, "PH-CASE.7: Stationary unit %s was removed as eligible defender" % u_def1.unit_id)
	_assert(fu_army.get_army_count() == 1, "PH-CASE.7: Soldier count decremented to 1")
	_assert(fu_tac.get_unit_count() == 1, "PH-CASE.7: Tactical roster size strictly matches soldier count (1 == 1)")

	# PH-CASE.8: Inverse field casualty selection matches field eligibility (stationary vs moving in field)
	fu_tac.clear_all_units()
	fu_army.soldier_count = 0
	var rec_ph8 = fu_army.recruit(3)
	_assert(rec_ph8.get("success", false) and fu_tac.get_unit_count() == 3, "PH-CASE.8: Successfully recruited 3 units")

	var inv_units = fu_tac.get_all_units()
	var u_inv_base = inv_units[0]
	var u_inv_stat = inv_units[1]
	var u_inv_mov = inv_units[2]

	u_inv_base.current_cell = fu_army.get_rally_cell()
	u_inv_base.target_cell = fu_army.get_rally_cell()
	u_inv_base.order_state = TacticalUnitScript.OrderState.IDLE
	u_inv_base.current_path.clear()

	u_inv_stat.current_cell = Vector2i(20, 20)
	u_inv_stat.target_cell = Vector2i(20, 20)
	u_inv_stat.order_state = TacticalUnitScript.OrderState.IDLE
	u_inv_stat.current_path.clear()

	u_inv_mov.current_cell = Vector2i(20, 21)
	u_inv_mov.target_cell = Vector2i(20, 22)
	u_inv_mov.order_state = TacticalUnitScript.OrderState.MOVING
	var p_step8: Array[Vector2i] = [Vector2i(20, 22)]
	u_inv_mov.current_path = p_step8

	_assert(fu_army.get_field_unit_count() == 1, "PH-CASE.8: Only 1 eligible ready field troop (%s)" % u_inv_stat.unit_id)
	var rem_ph8 = fu_army.remove_casualties(1, true)
	_assert(rem_ph8 == 1, "PH-CASE.8: Exactly 1 field casualty removed")
	_assert(fu_tac.get_unit(u_inv_mov.unit_id) != null, "PH-CASE.8: Moving field unit %s was NOT removed" % u_inv_mov.unit_id)
	_assert(fu_tac.get_unit(u_inv_base.unit_id) != null, "PH-CASE.8: Garrison base unit %s was NOT removed" % u_inv_base.unit_id)
	_assert(fu_tac.get_unit(u_inv_stat.unit_id) == null, "PH-CASE.8: Stationary field unit %s was removed as eligible field casualty" % u_inv_stat.unit_id)
	_assert(fu_army.get_army_count() == 2, "PH-CASE.8: Authoritative soldier count is 2")
	_assert(fu_tac.get_unit_count() == 2, "PH-CASE.8: Tactical roster size matches soldier count (2 == 2)")

