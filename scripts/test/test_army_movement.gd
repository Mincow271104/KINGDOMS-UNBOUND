extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — Package 1M: Player Army Marching & Garrison Deployment
## Covers TC-MOVE.1 through TC-MOVE.28 across 5 test groups:
## Group 1: Authoritative State, Rally Point & Basic Navigation (TC-MOVE.1 - TC-MOVE.7)
## Group 2: Interruption, Dynamic Obstruction & Simulation Clock (TC-MOVE.8 - TC-MOVE.13)
## Group 3: Defense Eligibility, Raid Casualties & Recruitment Gate (TC-MOVE.14 - TC-MOVE.18)
## Group 4: Persistence, Save/Load Validation & Recovery (TC-MOVE.19 - TC-MOVE.24)
## Group 5: HUD Wiring & Targeting Mode (TC-MOVE.25 - TC-MOVE.28)

const PlayerArmyManagerScript = preload("res://scripts/military/player_army_manager.gd")
const BattleCampaignManagerScript = preload("res://scripts/combat/battle_campaign_manager.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const FactionManagerScript = preload("res://scripts/factions/faction_manager.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")
const ArmyMarkerScript = preload("res://scripts/military/army_marker.gd")

var frame_count: int = 0
var world_instance: Node = null
var failures: int = 0

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

class MockEventManager:
	var events_triggered: Array = []

	func trigger_event(event_id: String, title: String, desc: String, is_positive: bool, payload: Dictionary = {}) -> void:
		events_triggered.append({
			"id": event_id,
			"title": title,
			"desc": desc,
			"positive": is_positive,
			"payload": payload
		})

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

func _init() -> void:
	print("\n========================================================")
	print("  STARTING PACKAGE 1M ARMY MARCHING TEST SUITE")
	print("========================================================\n")
	world_instance = WorldViewScene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count == 3:
		_run_all_tests()
		print("\n--------------------------------------------------------")
		if failures == 0:
			print("  ALL PACKAGE 1M ARMY MARCHING TESTS PASSED! (Exit Code 0)")
			print("--------------------------------------------------------\n")
			quit(0)
			return true
		else:
			printerr("  PACKAGE 1M ARMY MARCHING TESTS FAILED WITH %d FAILURES! (Exit Code 1)" % failures)
			print("--------------------------------------------------------\n")
			quit(1)
			return true
	return false

func _run_all_tests() -> void:
	_test_group_state_and_navigation()
	_test_group_interruption_and_clock()
	_test_group_defense_and_recruitment()
	_test_group_persistence_and_recovery()
	_test_group_hud_and_targeting()

# -----------------------------------------------------------------------------
# GROUP 1: STATE, RALLY POINT & BASIC NAVIGATION (TC-MOVE.1 - TC-MOVE.7)
# -----------------------------------------------------------------------------
func _test_group_state_and_navigation() -> void:
	print("=== GROUP 1: STATE, RALLY POINT & BASIC NAVIGATION (TC-MOVE.1 - TC-MOVE.7) ===")

	var mock_rm := MockResourceManager.new()
	var mock_em := MockEventManager.new()
	var mock_tm := MockTimeManager.new()
	var world_data := WorldGeneratorScript.generate(12345)
	var nav := GridNavigation.new(world_data)

	var army_mgr := PlayerArmyManagerScript.new()
	army_mgr.set_custom_resource_manager(mock_rm)
	army_mgr.set_custom_world_data(world_data)
	army_mgr.set_custom_event_manager(mock_em)
	army_mgr.set_custom_nav(nav)
	army_mgr.set_custom_time_manager(mock_tm)

	# TC-MOVE.1: Initial State & Rally Cell
	print("--- Running TC-MOVE.1: Initial State & Rally Cell ---")
	var rally := army_mgr.get_rally_cell()
	var cur := army_mgr.get_current_cell()
	var dest := army_mgr.get_destination_cell()
	var state_int: int = army_mgr.get_movement_state()
	var path: Array[Vector2i] = army_mgr.get_current_path()

	if cur != rally or dest != rally or state_int != PlayerArmyManagerScript.MovementState.GARRISONED:
		printerr("  [FAIL] TC-MOVE.1: Initial coordinates or state mismatch: cur=%s, rally=%s, state=%d" % [str(cur), str(rally), state_int])
		failures += 1
	elif not path.is_empty():
		printerr("  [FAIL] TC-MOVE.1: Initial path is not empty!")
		failures += 1
	elif army_mgr.is_defense_eligible():
		printerr("  [FAIL] TC-MOVE.1: Zero-soldier army must not be defense-eligible!")
		failures += 1
	else:
		print("  [PASS] TC-MOVE.1: Initial state strictly garrisoned at rally cell (%s), empty path, not defense-eligible." % str(rally))

	# TC-MOVE.2: Zero-Soldier Immobility
	print("--- Running TC-MOVE.2: Zero-Soldier Immobility ---")
	var target_cell := Vector2i(rally.x + 2, rally.y + 2)
	var res_zero: Dictionary = army_mgr.order_move(target_cell)
	if res_zero.get("success", true):
		printerr("  [FAIL] TC-MOVE.2: Zero-soldier army move order succeeded unexpectedly!")
		failures += 1
	elif army_mgr.get_movement_state() != PlayerArmyManagerScript.MovementState.GARRISONED or not army_mgr.get_current_path().is_empty():
		printerr("  [FAIL] TC-MOVE.2: Zero-soldier army state modified despite rejection!")
		failures += 1
	else:
		print("  [PASS] TC-MOVE.2: Zero-soldier army move order rejected safely: %s" % res_zero.get("reason", ""))

	# Setup barracks to recruit soldiers
	world_data.buildings.append({
		"id": "bld_barracks_test",
		"type": "barracks",
		"cell": Vector2i(30, 25),
		"size": Vector2i(3, 3),
		"state": "active",
		"construction_progress": 18.0,
		"construction_hours": 18.0
	})
	var r_res: Dictionary = army_mgr.recruit(5)
	if not r_res.get("success", false) or army_mgr.get_army_count() != 5:
		printerr("  [FAIL] Prerequisite recruitment failed: %s" % str(r_res))
		failures += 1

	# TC-MOVE.3: Valid Route Execution (A* Pathing)
	print("--- Running TC-MOVE.3: Valid Route Execution ---")
	# Find a clear walkable target 4 tiles away
	var target_walkable := Vector2i(rally.x + 3, rally.y)
	if not nav.is_cell_walkable(target_walkable):
		target_walkable = Vector2i(rally.x, rally.y + 3)

	var move_res: Dictionary = army_mgr.order_move(target_walkable)
	if not move_res.get("success", false):
		printerr("  [FAIL] TC-MOVE.3: Valid move order rejected: %s" % move_res.get("reason", ""))
		failures += 1
	elif army_mgr.get_movement_state() != PlayerArmyManagerScript.MovementState.MARCHING:
		printerr("  [FAIL] TC-MOVE.3: MovementState not MARCHING after valid move order!")
		failures += 1
	elif army_mgr.get_destination_cell() != target_walkable:
		printerr("  [FAIL] TC-MOVE.3: Destination mismatch: %s != %s" % [str(army_mgr.get_destination_cell()), str(target_walkable)])
		failures += 1
	elif army_mgr.get_current_path().is_empty():
		printerr("  [FAIL] TC-MOVE.3: Path is empty after valid move order!")
		failures += 1
	else:
		print("  [PASS] TC-MOVE.3: Valid move order calculated path of %d steps to %s." % [army_mgr.get_current_path().size(), str(target_walkable)])

	# TC-MOVE.4: Out-of-bounds, Blocked Cell & Same Cell Rejection (Atomic)
	print("--- Running TC-MOVE.4: Invalid Target Rejections (Atomic) ---")
	var saved_cur := army_mgr.get_current_cell()
	var saved_dest := army_mgr.get_destination_cell()
	var saved_path_len := army_mgr.get_current_path().size()
	var saved_state := army_mgr.get_movement_state()

	var bad_targets := [
		Vector2i(-1, 10),
		Vector2i(64, 30),
		Vector2i(31, 31), # Town Hall center footprint (blocked)
		saved_cur # Moving to current cell
	]
	var all_bad_rejected := true
	for bad in bad_targets:
		var bad_res := army_mgr.order_move(bad)
		if bad_res.get("success", false):
			all_bad_rejected = false
			printerr("  [FAIL] TC-MOVE.4: Bad target %s unexpectedly accepted!" % str(bad))
			failures += 1

	if army_mgr.get_current_cell() != saved_cur or army_mgr.get_destination_cell() != saved_dest or army_mgr.get_current_path().size() != saved_path_len or army_mgr.get_movement_state() != saved_state:
		printerr("  [FAIL] TC-MOVE.4: Internal state mutated after rejected bad targets!")
		failures += 1
	elif all_bad_rejected:
		print("  [PASS] TC-MOVE.4: All invalid targets rejected atomically with zero state mutation.")

	# TC-MOVE.5: Step-by-Step Movement Advancement
	print("--- Running TC-MOVE.5: Step-by-Step Movement Advancement ---")
	var pre_step_cell := army_mgr.get_current_cell()
	var next_waypoint: Vector2i = army_mgr.get_current_path()[0]

	# Partial step (0.25s < 0.5s)
	army_mgr.advance_movement(0.25, 1.0)
	if army_mgr.get_current_cell() != pre_step_cell:
		printerr("  [FAIL] TC-MOVE.5: Cell changed prematurely on partial step accumulator!")
		failures += 1

	# Complete step (another 0.25s => total 0.5s >= CELL_STEP_DURATION)
	var moved_signal_fired: Array = []
	army_mgr.army_moved.connect(func(c): moved_signal_fired.append(c))
	army_mgr.advance_movement(0.25, 1.0)

	if army_mgr.get_current_cell() != next_waypoint:
		printerr("  [FAIL] TC-MOVE.5: Did not advance to next waypoint! cur=%s, expected=%s" % [str(army_mgr.get_current_cell()), str(next_waypoint)])
		failures += 1
	elif moved_signal_fired.is_empty() or moved_signal_fired[0] != next_waypoint:
		printerr("  [FAIL] TC-MOVE.5: army_moved signal not emitted correctly!")
		failures += 1
	else:
		print("  [PASS] TC-MOVE.5: Advanced exactly 1 waypoint (%s) on 0.5s accumulator tick." % str(next_waypoint))

	# TC-MOVE.6: Arrival and State Transition to IDLE_AT_FIELD
	print("--- Running TC-MOVE.6: Arrival Transition to IDLE_AT_FIELD ---")
	while not army_mgr.get_current_path().is_empty():
		army_mgr.advance_movement(0.5, 1.0)

	if army_mgr.get_current_cell() != target_walkable:
		printerr("  [FAIL] TC-MOVE.6: Did not reach final target: cur=%s, expected=%s" % [str(army_mgr.get_current_cell()), str(target_walkable)])
		failures += 1
	elif army_mgr.get_movement_state() != PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD:
		printerr("  [FAIL] TC-MOVE.6: State not IDLE_AT_FIELD upon reaching field destination: %d" % army_mgr.get_movement_state())
		failures += 1
	elif army_mgr.is_defense_eligible():
		printerr("  [FAIL] TC-MOVE.6: Army idle at field must NOT be defense-eligible!")
		failures += 1
	else:
		print("  [PASS] TC-MOVE.6: Reached destination (%s); transitioned to IDLE_AT_FIELD; defense ineligible." % str(target_walkable))

	# TC-MOVE.7: Return Home & Garrison Transition
	print("--- Running TC-MOVE.7: Return Home & Garrison Transition ---")
	var ret_res: Dictionary = army_mgr.order_return_home()
	if not ret_res.get("success", false):
		printerr("  [FAIL] TC-MOVE.7: order_return_home failed: %s" % ret_res.get("reason", ""))
		failures += 1
	elif army_mgr.get_destination_cell() != rally:
		printerr("  [FAIL] TC-MOVE.7: Return destination is not rally cell!")
		failures += 1

	while not army_mgr.get_current_path().is_empty():
		army_mgr.advance_movement(0.5, 1.0)

	if army_mgr.get_current_cell() != rally:
		printerr("  [FAIL] TC-MOVE.7: Did not reach rally cell upon return!")
		failures += 1
	elif army_mgr.get_movement_state() != PlayerArmyManagerScript.MovementState.GARRISONED:
		printerr("  [FAIL] TC-MOVE.7: State not GARRISONED upon return home: %d" % army_mgr.get_movement_state())
		failures += 1
	elif not army_mgr.is_defense_eligible():
		printerr("  [FAIL] TC-MOVE.7: Army garrisoned at home with soldiers MUST be defense-eligible!")
		failures += 1
	else:
		print("  [PASS] TC-MOVE.7: Returned home to rally (%s); transitioned to GARRISONED; defense-eligible restored." % str(rally))

# -----------------------------------------------------------------------------
# GROUP 2: INTERRUPTION, DYNAMIC OBSTRUCTION & CLOCK (TC-MOVE.8 - TC-MOVE.13)
# -----------------------------------------------------------------------------
func _test_group_interruption_and_clock() -> void:
	print("=== GROUP 2: INTERRUPTION, DYNAMIC OBSTRUCTION & CLOCK (TC-MOVE.8 - TC-MOVE.13) ===")

	var mock_rm := MockResourceManager.new()
	var mock_tm := MockTimeManager.new()
	var world_data := WorldGeneratorScript.generate(12345)
	var nav := GridNavigation.new(world_data)

	var army_mgr := PlayerArmyManagerScript.new()
	army_mgr.set_custom_resource_manager(mock_rm)
	army_mgr.set_custom_world_data(world_data)
	army_mgr.set_custom_nav(nav)
	army_mgr.set_custom_time_manager(mock_tm)

	world_data.buildings.append({
		"id": "bld_barracks_test",
		"type": "barracks",
		"cell": Vector2i(30, 25),
		"size": Vector2i(3, 3),
		"state": "active",
		"construction_progress": 18.0,
		"construction_hours": 18.0
	})
	army_mgr.recruit(5)
	var rally := army_mgr.get_rally_cell()

	# TC-MOVE.8: Move Cancellation while Marching
	print("--- Running TC-MOVE.8: Move Cancellation while Marching ---")
	var target_far := Vector2i(rally.x + 4, rally.y)
	army_mgr.order_move(target_far)
	army_mgr.advance_movement(0.5, 1.0) # Move 1 step
	var mid_cell := army_mgr.get_current_cell()

	army_mgr.cancel_move()
	if army_mgr.get_current_cell() != mid_cell:
		printerr("  [FAIL] TC-MOVE.8: Cell mutated on cancel_move!")
		failures += 1
	elif not army_mgr.get_current_path().is_empty():
		printerr("  [FAIL] TC-MOVE.8: Path not cleared on cancel_move!")
		failures += 1
	elif army_mgr.get_movement_state() != PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD:
		printerr("  [FAIL] TC-MOVE.8: State not IDLE_AT_FIELD after canceling in field!")
		failures += 1
	else:
		print("  [PASS] TC-MOVE.8: Movement successfully canceled at %s; path cleared; state IDLE_AT_FIELD." % str(mid_cell))

	# TC-MOVE.9: Re-targeting while Marching
	print("--- Running TC-MOVE.9: Re-targeting while Marching ---")
	var dest_a := Vector2i(rally.x + 5, rally.y)
	var dest_b := Vector2i(rally.x, rally.y + 4)
	army_mgr.order_move(dest_a)
	army_mgr.advance_movement(0.5, 1.0) # Move 1 step towards A

	var re_res: Dictionary = army_mgr.order_move(dest_b)
	if not re_res.get("success", false):
		printerr("  [FAIL] TC-MOVE.9: Re-targeting failed: %s" % re_res.get("reason", ""))
		failures += 1
	elif army_mgr.get_destination_cell() != dest_b:
		printerr("  [FAIL] TC-MOVE.9: Destination not updated to dest_b!")
		failures += 1
	elif army_mgr.get_movement_state() != PlayerArmyManagerScript.MovementState.MARCHING:
		printerr("  [FAIL] TC-MOVE.9: MovementState not MARCHING after re-targeting!")
		failures += 1
	else:
		print("  [PASS] TC-MOVE.9: Seamlessly re-targeted to %s while in transit." % str(dest_b))

	# TC-MOVE.10: TimeManager Paused Safety
	print("--- Running TC-MOVE.10: TimeManager Paused Safety ---")
	var cur_before_pause := army_mgr.get_current_cell()
	var path_before_pause := army_mgr.get_current_path().duplicate()

	# Simulate paused condition (speed_mult = 0.0)
	army_mgr.advance_movement(10.0, 0.0)
	if army_mgr.get_current_cell() != cur_before_pause or army_mgr.get_current_path().size() != path_before_pause.size():
		printerr("  [FAIL] TC-MOVE.10: Movement advanced while paused!")
		failures += 1
	else:
		print("  [PASS] TC-MOVE.10: Movement strictly frozen when simulation is paused.")

	# TC-MOVE.11: TimeManager Speed Scaling (1x, 2x, 3x)
	print("--- Running TC-MOVE.11: TimeManager Speed Scaling ---")
	var pre_scale_cell := army_mgr.get_current_cell()
	var path_rem := army_mgr.get_current_path().duplicate()

	# At 2x speed, delta = 0.25 gives effective 0.5s (1 full step)
	army_mgr.advance_movement(0.25, 2.0)
	if army_mgr.get_current_cell() == pre_scale_cell and not path_rem.is_empty():
		printerr("  [FAIL] TC-MOVE.11: 2x speed did not scale accumulator correctly!")
		failures += 1
	else:
		print("  [PASS] TC-MOVE.11: Speed scaling verified (2x completed 1 step in 0.25s real time).")

	# Finish path to clear
	while not army_mgr.get_current_path().is_empty():
		army_mgr.advance_movement(0.5, 3.0)

	# TC-MOVE.12: Dynamic Obstruction Rerouting
	print("--- Running TC-MOVE.12: Dynamic Obstruction Rerouting ---")
	var start_pt := army_mgr.get_current_cell()
	var end_pt := Vector2i(start_pt.x + 4, start_pt.y)
	army_mgr.order_move(end_pt)
	var planned_path := army_mgr.get_current_path().duplicate()

	# Now block the immediate next waypoint by placing an obstacle on world_data
	var blocked_waypoint: Vector2i = planned_path[0]
	world_data.occupancy[blocked_waypoint.x][blocked_waypoint.y] = true

	# Advance movement: should detect obstacle, dynamically reroute around it
	army_mgr.advance_movement(0.5, 1.0)
	if army_mgr.get_current_cell() == blocked_waypoint:
		printerr("  [FAIL] TC-MOVE.12: Army walked into blocked cell %s!" % str(blocked_waypoint))
		failures += 1
	elif army_mgr.get_movement_state() != PlayerArmyManagerScript.MovementState.MARCHING:
		printerr("  [FAIL] TC-MOVE.12: Movement state aborted prematurely during reroute!")
		failures += 1
	else:
		print("  [PASS] TC-MOVE.12: Obstacle detected; dynamically avoided blocked cell %s." % str(blocked_waypoint))

	# TC-MOVE.13: Dynamic Obstruction Trapped / No Path Safe Halt
	print("--- Running TC-MOVE.13: Dynamic Obstruction Trapped Safe Halt ---")
	# Block immediate next waypoint and surround destination so no route exists
	if not army_mgr.get_current_path().is_empty():
		var next_w: Vector2i = army_mgr.get_current_path()[0]
		world_data.occupancy[next_w.x][next_w.y] = true

	var trapped_dest := army_mgr.get_destination_cell()
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var c := trapped_dest + Vector2i(dx, dy)
			if IsoMath.is_in_bounds(c) and c != army_mgr.get_current_cell():
				world_data.occupancy[c.x][c.y] = true

	army_mgr.advance_movement(0.5, 1.0)
	if army_mgr.get_movement_state() == PlayerArmyManagerScript.MovementState.MARCHING and army_mgr.get_current_path().is_empty():
		printerr("  [FAIL] TC-MOVE.13: Army still marching with empty path!")
		failures += 1
	elif army_mgr.get_movement_state() != PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD:
		printerr("  [FAIL] TC-MOVE.13: State not safely transitioned to IDLE_AT_FIELD when trapped: %d" % army_mgr.get_movement_state())
		failures += 1
	else:
		print("  [PASS] TC-MOVE.13: Trapped path safely halted at %s with IDLE_AT_FIELD." % str(army_mgr.get_current_cell()))

# -----------------------------------------------------------------------------
# GROUP 3: DEFENSE ELIGIBILITY, RAID CASUALTIES & RECRUITMENT (TC-MOVE.14 - TC-MOVE.18)
# -----------------------------------------------------------------------------
func _test_group_defense_and_recruitment() -> void:
	print("=== GROUP 3: DEFENSE ELIGIBILITY & RECRUITMENT (TC-MOVE.14 - TC-MOVE.18) ===")

	var mock_rm := MockResourceManager.new()
	var mock_em := MockEventManager.new()
	var world_data := WorldGeneratorScript.generate(12345)
	var nav := GridNavigation.new(world_data)
	var fac_mgr := FactionManagerScript.new()

	var army_mgr := PlayerArmyManagerScript.new()
	army_mgr.set_custom_resource_manager(mock_rm)
	army_mgr.set_custom_world_data(world_data)
	army_mgr.set_custom_event_manager(mock_em)
	army_mgr.set_custom_nav(nav)

	world_data.buildings.append({
		"id": "bld_barracks_test",
		"type": "barracks",
		"cell": Vector2i(30, 25),
		"size": Vector2i(3, 3),
		"state": "active",
		"construction_progress": 18.0,
		"construction_hours": 18.0
	})
	army_mgr.recruit(4)
	var rally := army_mgr.get_rally_cell()

	# TC-MOVE.14: Recruitment Blocked while Marching or in Field
	print("--- Running TC-MOVE.14: Recruitment Blocked while Deployed ---")
	var target_field := Vector2i(rally.x + 3, rally.y)
	army_mgr.order_move(target_field)

	var check_marching: Dictionary = army_mgr.can_recruit(1)
	if check_marching.get("can_recruit", true):
		printerr("  [FAIL] TC-MOVE.14: can_recruit returned true while MARCHING!")
		failures += 1
	elif not check_marching.get("reason", "").contains("hành quân"):
		printerr("  [FAIL] TC-MOVE.14: Reason does not mention marching: %s" % check_marching.get("reason", ""))
		failures += 1

	while not army_mgr.get_current_path().is_empty():
		army_mgr.advance_movement(0.5, 1.0)

	var check_field: Dictionary = army_mgr.can_recruit(1)
	if check_field.get("can_recruit", true):
		printerr("  [FAIL] TC-MOVE.14: can_recruit returned true while IDLE_AT_FIELD!")
		failures += 1
	elif not check_field.get("reason", "").contains("dã chiến"):
		printerr("  [FAIL] TC-MOVE.14: Reason does not mention field deployment: %s" % check_field.get("reason", ""))
		failures += 1

	var recruit_fail_res: Dictionary = army_mgr.recruit(1)
	if recruit_fail_res.get("success", false):
		printerr("  [FAIL] TC-MOVE.14: recruit succeeded while in field!")
		failures += 1
	else:
		print("  [PASS] TC-MOVE.14: Recruitment strictly blocked while deployed: %s" % check_field.get("reason", ""))

	# Mock world view for BattleCampaignManager
	var mock_wv = Node.new()
	mock_wv.set("world_data", world_data)
	var campaign_mgr = BattleCampaignManagerScript.new(mock_wv, fac_mgr, 12345)
	campaign_mgr.set_custom_army_manager(army_mgr)
	var bandit = fac_mgr.get_faction("bandit_clan")
	if bandit:
		bandit.is_at_war = true

	# TC-MOVE.15: Settlement Defense Exclusion while Absent
	print("--- Running TC-MOVE.15: Defense Exclusion while Absent ---")
	# 4 soldiers deployed at field, 0 guards
	var def_force_absent: Dictionary = campaign_mgr.construct_defending_force()
	if def_force_absent.get("army_soldiers", -1) != 0:
		printerr("  [FAIL] TC-MOVE.15: Absent army soldiers included in defense force! count=%d" % def_force_absent.get("army_soldiers", -1))
		failures += 1
	elif def_force_absent.get("troops", -1) != 0:
		printerr("  [FAIL] TC-MOVE.15: Total defending troops non-zero when army is absent and no guards: %d" % def_force_absent.get("troops", -1))
		failures += 1
	else:
		print("  [PASS] TC-MOVE.15: Defending force strictly excluded absent army (troops = 0).")

	# TC-MOVE.16: Raid Casualties Protection while Absent
	print("--- Running TC-MOVE.16: Raid Casualties Protection while Absent ---")
	# If a raid executes while army is away, casualty deductions must not touch absent army
	var prev_army_count := army_mgr.get_army_count()
	# Directly apply raid resolution with 1 casualty
	# Defending force has 0 army soldiers, so any casualties go to guards
	campaign_mgr.resolve_and_apply_raid("bandit_clan", 5)
	if army_mgr.get_army_count() != prev_army_count:
		printerr("  [FAIL] TC-MOVE.16: Absent army suffered casualties while away from settlement! prev=%d, now=%d" % [prev_army_count, army_mgr.get_army_count()])
		failures += 1
	else:
		print("  [PASS] TC-MOVE.16: Absent army took 0 casualties during settlement defense raid (%d preserved)." % army_mgr.get_army_count())

	# TC-MOVE.17: Settlement Defense Participation when Garrisoned
	print("--- Running TC-MOVE.17: Defense Participation when Garrisoned ---")
	army_mgr.order_return_home()
	while not army_mgr.get_current_path().is_empty():
		army_mgr.advance_movement(0.5, 1.0)

	var def_force_home: Dictionary = campaign_mgr.construct_defending_force()
	if def_force_home.get("army_soldiers", 0) != 4 or def_force_home.get("troops", 0) != 4:
		printerr("  [FAIL] TC-MOVE.17: Garrisoned army not included in defense force! army_soldiers=%d" % def_force_home.get("army_soldiers", 0))
		failures += 1
	else:
		print("  [PASS] TC-MOVE.17: Garrisoned army correctly joined defense force (%d soldiers)." % def_force_home.get("troops", 0))

	# TC-MOVE.18: Total Wipeout Auto-Recovery to Garrison
	print("--- Running TC-MOVE.18: Total Wipeout Auto-Recovery to Garrison ---")
	# Move into field first
	army_mgr.order_move(target_field)
	while not army_mgr.get_current_path().is_empty():
		army_mgr.advance_movement(0.5, 1.0)

	if army_mgr.get_movement_state() != PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD:
		printerr("  [FAIL] TC-MOVE.18: Pre-condition: Army not in field!")
		failures += 1

	# Wipe out army casualties
	army_mgr.remove_casualties(4)
	if army_mgr.get_army_count() != 0:
		printerr("  [FAIL] TC-MOVE.18: Army count not 0 after wipeout!")
		failures += 1
	elif army_mgr.get_movement_state() != PlayerArmyManagerScript.MovementState.GARRISONED:
		printerr("  [FAIL] TC-MOVE.18: Depleted army did not auto-recover to GARRISONED state: %d" % army_mgr.get_movement_state())
		failures += 1
	elif army_mgr.get_current_cell() != rally:
		printerr("  [FAIL] TC-MOVE.18: Depleted army current_cell not reset to rally: %s" % str(army_mgr.get_current_cell()))
		failures += 1
	else:
		print("  [PASS] TC-MOVE.18: Depleted army automatically recovered to clean GARRISONED state at rally (%s)." % str(rally))

	mock_wv.free()

# -----------------------------------------------------------------------------
# GROUP 4: PERSISTENCE, VALIDATION & RECOVERY (TC-MOVE.19 - TC-MOVE.24)
# -----------------------------------------------------------------------------
func _test_group_persistence_and_recovery() -> void:
	print("=== GROUP 4: PERSISTENCE, VALIDATION & RECOVERY (TC-MOVE.19 - TC-MOVE.24) ===")

	var mock_rm := MockResourceManager.new()
	var mock_em := MockEventManager.new()
	var world_data := WorldGeneratorScript.generate(12345)
	var nav := GridNavigation.new(world_data)

	var army_mgr := PlayerArmyManagerScript.new()
	army_mgr.set_custom_resource_manager(mock_rm)
	army_mgr.set_custom_world_data(world_data)
	army_mgr.set_custom_event_manager(mock_em)
	army_mgr.set_custom_nav(nav)

	world_data.buildings.append({
		"id": "bld_barracks_test",
		"type": "barracks",
		"cell": Vector2i(30, 25),
		"size": Vector2i(3, 3),
		"state": "active",
		"construction_progress": 18.0,
		"construction_hours": 18.0
	})
	army_mgr.recruit(5)
	var rally := army_mgr.get_rally_cell()
	var target_field := Vector2i(rally.x + 3, rally.y)
	army_mgr.order_move(target_field)
	army_mgr.advance_movement(0.5, 1.0) # Mid-march

	# TC-MOVE.19: Save Serialization & Roundtrip
	print("--- Running TC-MOVE.19: Serialization & Roundtrip ---")
	var serialized := army_mgr.serialize()
	if not serialized.has("current_cell") or not serialized.has("rally_cell") or not serialized.has("destination_cell") or not serialized.has("movement_state") or not serialized.has("current_path"):
		printerr("  [FAIL] TC-MOVE.19: Serialized dictionary missing movement fields: %s" % str(serialized))
		failures += 1
	elif serialized["movement_state"] != "marching":
		printerr("  [FAIL] TC-MOVE.19: movement_state serialized incorrectly: %s" % str(serialized["movement_state"]))
		failures += 1
	else:
		# Deserialize into fresh manager
		var fresh_mgr := PlayerArmyManagerScript.new()
		fresh_mgr.set_custom_world_data(world_data)
		fresh_mgr.set_custom_nav(nav)
		fresh_mgr.deserialize(serialized)

		if fresh_mgr.get_current_cell() != army_mgr.get_current_cell():
			printerr("  [FAIL] TC-MOVE.19: current_cell not restored: %s != %s" % [str(fresh_mgr.get_current_cell()), str(army_mgr.get_current_cell())])
			failures += 1
		elif fresh_mgr.get_destination_cell() != target_field:
			printerr("  [FAIL] TC-MOVE.19: destination_cell not restored: %s != %s" % [str(fresh_mgr.get_destination_cell()), str(target_field)])
			failures += 1
		elif fresh_mgr.get_movement_state() != PlayerArmyManagerScript.MovementState.MARCHING:
			printerr("  [FAIL] TC-MOVE.19: movement_state not restored to MARCHING: %d" % fresh_mgr.get_movement_state())
			failures += 1
		elif fresh_mgr.get_current_path().size() != army_mgr.get_current_path().size():
			printerr("  [FAIL] TC-MOVE.19: path size mismatch: %d != %d" % [fresh_mgr.get_current_path().size(), army_mgr.get_current_path().size()])
			failures += 1
		else:
			print("  [PASS] TC-MOVE.19: Movement state, path, and coordinates preserved through serialization roundtrip.")

	# TC-MOVE.20: SaveManager End-to-End & Double Load Idempotency
	print("--- Running TC-MOVE.20: SaveManager End-to-End & Double Load ---")
	var save_dict := SaveManagerScript.serialize_world_state(world_instance)
	var apply_res_1 := SaveManagerScript.apply_loaded_state_to_world(world_instance, save_dict)
	if not apply_res_1.get("success", false):
		printerr("  [FAIL] TC-MOVE.20: First apply_loaded_state_to_world failed: %s" % apply_res_1.get("error", ""))
		failures += 1

	var marker_count_1 := 0
	for child in world_instance.get("citizens_container").get_children():
		if child.name == "ArmyMarker":
			marker_count_1 += 1

	var apply_res_2 := SaveManagerScript.apply_loaded_state_to_world(world_instance, save_dict)
	if not apply_res_2.get("success", false):
		printerr("  [FAIL] TC-MOVE.20: Second apply_loaded_state_to_world failed: %s" % apply_res_2.get("error", ""))
		failures += 1

	var marker_count_2 := 0
	for child in world_instance.get("citizens_container").get_children():
		if child.name == "ArmyMarker":
			marker_count_2 += 1

	if marker_count_1 != 1 or marker_count_2 != 1:
		printerr("  [FAIL] TC-MOVE.20: Node duplication detected for ArmyMarker: count1=%d, count2=%d" % [marker_count_1, marker_count_2])
		failures += 1
	else:
		print("  [PASS] TC-MOVE.20: Double load strictly idempotent with zero ArmyMarker node duplication.")

	# TC-MOVE.21: Legacy Save Compatibility
	print("--- Running TC-MOVE.21: Legacy Save Compatibility ---")
	var legacy_dict := save_dict.duplicate(true)
	legacy_dict["player_army"] = {
		"soldier_count": 3,
		"is_supplied": true,
		"last_upkeep_day": 1
	}
	var legacy_apply := SaveManagerScript.apply_loaded_state_to_world(world_instance, legacy_dict)
	if not legacy_apply.get("success", false):
		printerr("  [FAIL] TC-MOVE.21: Legacy save application failed: %s" % legacy_apply.get("error", ""))
		failures += 1
	else:
		var live_army = world_instance.get("player_army_mgr")
		if live_army.get_movement_state() != PlayerArmyManagerScript.MovementState.GARRISONED:
			printerr("  [FAIL] TC-MOVE.21: Legacy save did not default to GARRISONED: %d" % live_army.get_movement_state())
			failures += 1
		elif live_army.get_current_cell() != live_army.get_rally_cell():
			printerr("  [FAIL] TC-MOVE.21: Legacy save current_cell not at rally: %s != %s" % [str(live_army.get_current_cell()), str(live_army.get_rally_cell())])
			failures += 1
		else:
			print("  [PASS] TC-MOVE.21: Legacy save loaded safely; defaulted to GARRISONED at rally cell.")

	# TC-MOVE.22: Save Validation Rejections (Fail-Closed)
	print("--- Running TC-MOVE.22: Save Validation Fail-Closed Checks ---")
	var bad_saves := [
		{"player_army": {"current_cell": [-5, 10]}},
		{"player_army": {"current_cell": [65, 10]}},
		{"player_army": {"rally_cell": "not_an_array"}},
		{"player_army": {"movement_state": "flying"}},
		{"player_army": {"current_path": [[10, 10], [99, 99]]}}
	]
	var all_val_rejected := true
	for bs in bad_saves:
		var test_doc := save_dict.duplicate(true)
		for k in bs["player_army"]:
			test_doc["player_army"][k] = bs["player_army"][k]
		var val_res := SaveManagerScript.validate_save_data(test_doc)
		if val_res.get("valid", true):
			all_val_rejected = false
			printerr("  [FAIL] TC-MOVE.22: Corrupted player_army payload accepted! %s" % str(bs))
			failures += 1

	if all_val_rejected:
		print("  [PASS] TC-MOVE.22: Save validator strictly rejected all 5 malformed movement payloads.")

	# TC-MOVE.23: Blocked Cell Recovery on Load
	print("--- Running TC-MOVE.23: Blocked Cell Recovery on Load ---")
	# Create a save where current_cell is inside Town Hall footprint (blocked)
	var blocked_load_data := {
		"soldier_count": 3,
		"is_supplied": true,
		"last_upkeep_day": 1,
		"current_cell": [31, 31], # Blocked
		"rally_cell": [rally.x, rally.y],
		"destination_cell": [31, 31],
		"movement_state": "idle_at_field",
		"current_path": []
	}
	var recovery_mgr := PlayerArmyManagerScript.new()
	recovery_mgr.set_custom_world_data(world_data)
	recovery_mgr.set_custom_nav(nav)
	recovery_mgr.deserialize(blocked_load_data)

	if recovery_mgr.get_current_cell() == Vector2i(31, 31):
		printerr("  [FAIL] TC-MOVE.23: Army remained on blocked tile (31, 31) after loading!")
		failures += 1
	elif not nav.is_cell_walkable(recovery_mgr.get_current_cell()):
		printerr("  [FAIL] TC-MOVE.23: Recovered cell %s is not walkable!" % str(recovery_mgr.get_current_cell()))
		failures += 1
	elif recovery_mgr.get_movement_state() != PlayerArmyManagerScript.MovementState.GARRISONED:
		printerr("  [FAIL] TC-MOVE.23: Recovered state not GARRISONED: %d" % recovery_mgr.get_movement_state())
		failures += 1
	else:
		print("  [PASS] TC-MOVE.23: Army loaded on blocked tile safely recovered to walkable rally cell (%s)." % str(recovery_mgr.get_current_cell()))

	# TC-MOVE.24: ArmyMarker Display & Visual Synchronization
	print("--- Running TC-MOVE.24: ArmyMarker Display & Synchronization ---")
	var live_mgr = world_instance.get("player_army_mgr")
	var marker: Node2D = world_instance.get_army_marker()
	if marker == null:
		printerr("  [FAIL] TC-MOVE.24: ArmyMarker node not found in WorldView!")
		failures += 1
	else:
		# When army has soldiers, marker visible
		marker.update_display()
		if not marker.visible:
			printerr("  [FAIL] TC-MOVE.24: ArmyMarker not visible when soldiers > 0!")
			failures += 1

		# When army has 0 soldiers, marker hidden
		live_mgr.remove_casualties(live_mgr.get_army_count())
		marker.update_display()
		if marker.visible:
			printerr("  [FAIL] TC-MOVE.24: ArmyMarker still visible when soldiers == 0!")
			failures += 1
		else:
			print("  [PASS] TC-MOVE.24: ArmyMarker visibility dynamically toggles with army count (hidden at 0, visible > 0).")

# -----------------------------------------------------------------------------
# GROUP 5: HUD WIRING & TARGETING MODE (TC-MOVE.25 - TC-MOVE.28)
# -----------------------------------------------------------------------------
func _test_group_hud_and_targeting() -> void:
	print("=== GROUP 5: HUD WIRING & TARGETING MODE (TC-MOVE.25 - TC-MOVE.28) ===")

	var hud = world_instance.get("hud")
	var army_mgr = world_instance.get("player_army_mgr")
	if hud == null or army_mgr == null:
		printerr("  [FAIL] Prerequisite HUD or PlayerArmyManager missing from world_instance!")
		failures += 1
		return

	var world_data = world_instance.get("world_data")
	world_data.buildings.append({
		"id": "bld_barracks_live_test",
		"type": "barracks",
		"cell": Vector2i(22, 22),
		"size": Vector2i(3, 3),
		"state": "active",
		"construction_progress": 18.0,
		"construction_hours": 18.0
	})
	army_mgr.notify_capacity_changed()
	army_mgr.recruit(3)

	# TC-MOVE.25: HUD Deployment Status Display
	print("--- Running TC-MOVE.25: HUD Deployment Status Display ---")
	hud.call("_refresh_army_panel")
	var dep_label: Label = hud.get_node_or_null("ArmyPanel/MarginContainer/VBoxContainer/ArmyStatsVBox/DeploymentLabel")
	if dep_label == null:
		printerr("  [FAIL] TC-MOVE.25: DeploymentLabel node missing in HUD scene!")
		failures += 1
	elif not dep_label.text.contains("căn cứ"):
		printerr("  [FAIL] TC-MOVE.25: DeploymentLabel text does not indicate home garrison: '%s'" % dep_label.text)
		failures += 1
	else:
		print("  [PASS] TC-MOVE.25: DeploymentLabel displays: '%s'." % dep_label.text)

	# TC-MOVE.26: HUD Move & Return Buttons Enable/Disable State
	print("--- Running TC-MOVE.26: Move & Return Buttons State ---")
	var move_btn: Button = hud.get_node_or_null("ArmyPanel/MarginContainer/VBoxContainer/MoveArmyBtn")
	var return_btn: Button = hud.get_node_or_null("ArmyPanel/MarginContainer/VBoxContainer/ReturnHomeBtn")
	if move_btn == null or return_btn == null:
		printerr("  [FAIL] TC-MOVE.26: MoveArmyBtn or ReturnHomeBtn missing from HUD!")
		failures += 1
	elif move_btn.disabled:
		printerr("  [FAIL] TC-MOVE.26: MoveArmyBtn is disabled when soldiers > 0!")
		failures += 1
	elif not return_btn.disabled:
		printerr("  [FAIL] TC-MOVE.26: ReturnHomeBtn should be disabled when already at home rally!")
		failures += 1
	else:
		print("  [PASS] TC-MOVE.26: Button states correct when garrisoned (Move enabled, Return disabled).")

	# TC-MOVE.27: HUD Targeting Mode Start, Execute & Cancel
	print("--- Running TC-MOVE.27: HUD Targeting Mode ---")
	hud.call("start_army_move_targeting")
	if not hud.call("is_army_move_targeting"):
		printerr("  [FAIL] TC-MOVE.27: is_army_move_targeting returned false after start!")
		failures += 1

	hud.call("cancel_army_move_targeting")
	if hud.call("is_army_move_targeting"):
		printerr("  [FAIL] TC-MOVE.27: is_army_move_targeting still true after cancel!")
		failures += 1

	hud.call("start_army_move_targeting")
	var rally: Vector2i = army_mgr.get_rally_cell()
	var move_target := Vector2i(rally.x + 2, rally.y)
	hud.call("execute_army_move_target", move_target)

	if hud.call("is_army_move_targeting"):
		printerr("  [FAIL] TC-MOVE.27: is_army_move_targeting still true after execute!")
		failures += 1
	elif army_mgr.get_destination_cell() != move_target:
		printerr("  [FAIL] TC-MOVE.27: Army destination not updated to target %s!" % str(move_target))
		failures += 1
	else:
		print("  [PASS] TC-MOVE.27: Targeting mode start, cancel, and execute verified seamlessly.")

	# TC-MOVE.28: ESC Key Cancels Targeting
	print("--- Running TC-MOVE.28: ESC Key Handling ---")
	hud.call("start_army_move_targeting")
	var esc_event := InputEventKey.new()
	esc_event.pressed = true
	esc_event.keycode = KEY_ESCAPE
	hud._unhandled_input(esc_event)

	if hud.call("is_army_move_targeting"):
		printerr("  [FAIL] TC-MOVE.28: ESC did not cancel targeting mode!")
		failures += 1
	else:
		print("  [PASS] TC-MOVE.28: ESC key cleanly canceled army targeting mode.")
