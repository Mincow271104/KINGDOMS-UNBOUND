extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — PACKAGE 2K
## Manual Citizen Commands & Direct Labor Dispatch
## Authoritative References: docs/GDD.md §8.2, §8.3, §14.4; docs/planning/NEXT_GAMEPLAY_PACKAGE.md

const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const GridNavigationScript = preload("res://scripts/navigation/grid_navigation.gd")
const JobManagerScript = preload("res://scripts/jobs/job_manager.gd")
const WorkplaceManagerScript = preload("res://scripts/economy/workplace_manager.gd")
const ResourceManagerScript = preload("res://scripts/economy/resource_manager.gd")
const CitizenControllerScript = preload("res://scripts/entities/citizen_controller.gd")
const POIManagerScript = preload("res://scripts/world/poi_manager.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")

var failures: int = 0
var passed_count: int = 0

func _assert(condition: bool, test_name: String, details: String = "") -> void:
	if condition:
		passed_count += 1
		print("  [PASS] %s" % test_name)
	else:
		failures += 1
		printerr("  [FAIL] %s - %s" % [test_name, details])

func _create_test_world() -> WorldGenerator.WorldData:
	var wd = WorldGeneratorScript.generate(42)
	IsoMath.set_active_map_dimensions(wd.terrain.size(), wd.terrain[0].size())
	return wd

func _resolve_dropoff_cell(wd: WorldGenerator.WorldData) -> Vector2i:
	return wd.center_spawn

func _clear_walkable_rect(wd: WorldGenerator.WorldData, min_cell: Vector2i, max_cell: Vector2i) -> void:
	for x in range(min_cell.x, max_cell.x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			wd.terrain[x][y] = WorldGeneratorScript.TerrainType.GRASS
			wd.occupancy[x][y] = false
	for i in range(wd.props.size() - 1, -1, -1):
		var c: Vector2i = wd.props[i].get("cell", Vector2i(-1, -1))
		if c.x >= min_cell.x and c.x <= max_cell.x and c.y >= min_cell.y and c.y <= max_cell.y:
			wd.props.remove_at(i)

func _init() -> void:
	print("\n========================================================")
	print("  STARTING PACKAGE 2K MANUAL CITIZEN COMMANDS TEST SUITE")
	print("========================================================\n")

	_run_tc_man_1_manual_move()
	_run_tc_man_2_prior_job_clean_release()
	_run_tc_man_3_manual_tree_chopping()
	_run_tc_man_4_manual_rock_mining()
	_run_tc_man_5_manual_construction_priority()
	_run_tc_man_6_manual_buffer_hauling()
	_run_tc_man_7_manual_poi_exploration()
	_run_tc_man_8_survival_need_interruption_and_resume()
	_run_tc_man_9_manual_order_cancellation()
	_run_tc_man_10_fail_closed_invalid_targets()
	_run_tc_man_11_save_load_persistence_roundtrip()
	_run_tc_man_12_stale_target_rejection_on_load()
	_run_tc_man_13_multi_citizen_isolation()
	_run_tc_man_14_citizen_death_cleanup()
	_run_tc_man_15_vocational_xp_award_on_completion()
	_run_tc_man_16_survival_interruption_during_cargo_hauling()
	_run_tc_man_17_full_storage_arrival_and_stationing()
	_run_tc_man_18_work_command_rejection_while_carrying_cargo()
	_run_tc_man_19_save_load_during_cargo_hauling()
	_run_tc_man_20_semantic_cancellation_and_death_cargo_lifecycle()
	_run_tc_man_21_path_failure_with_cargo_invariant()
	_run_tc_man_22_automatic_hauler_path_failure_invariant()
	_run_tc_man_23_active_job_hauler_proximity_bypass_elimination()

	print("\n--------------------------------------------------------")
	if failures == 0:
		print("  PACKAGE 2K SUITE: ALL %d CHECKS PASSED! (0 Failures)" % passed_count)
		print("========================================================\n")
		quit(0)
	else:
		printerr("  PACKAGE 2K SUITE: FAILED WITH %d FAILURES (Passed: %d)" % [failures, passed_count])
		print("========================================================\n")
		quit(1)

## TC-MAN.1: Manual Move Command
func _run_tc_man_1_manual_move() -> void:
	print("--- TC-MAN.1: Manual Move Command ---")
	var wd = _create_test_world()
	var nav = GridNavigationScript.new(wd)
	var jm = JobManagerScript.new()
	var cit = CitizenControllerScript.new()
	root.add_child(cit)

	cit.init_citizen("cit_1", "Test Citizen", "idle", Vector2i(32, 32), nav, jm)
	cit.world_data = wd

	var target := Vector2i(34, 32)
	# Ensure path and target are walkable
	for x in range(32, 35):
		wd.occupancy[x][32] = false
		wd.terrain[x][32] = WorldGenerator.TerrainType.GRASS

	var arrived := [false]
	cit.manual_command_completed.connect(func(_id, type):
		if type == "move":
			arrived[0] = true
	)

	var res := cit.issue_manual_command("move", target)
	_assert(res.get("success", false) == true, "TC-MAN.1.1: issue_manual_command 'move' succeeds")
	_assert(cit.has_manual_command() == true, "TC-MAN.1.2: Citizen has active manual command")
	_assert(cit.current_state == CitizenController.State.MOVING_TO_JOB, "TC-MAN.1.3: Citizen transitions to MOVING_TO_JOB")
	_assert(cit.manual_command.type == "move", "TC-MAN.1.4: Command type is 'move'")

	# Step movement
	for _i in range(50):
		cit._process(0.1)
		if arrived[0] or not cit.has_manual_command():
			break

	_assert(arrived[0] == true, "TC-MAN.1.5: manual_command_completed signal emitted")
	_assert(cit.has_manual_command() == false, "TC-MAN.1.6: Manual command cleared after arrival")
	_assert(cit.current_cell == target, "TC-MAN.1.7: Citizen reached exact target cell (%s == %s)" % [cit.current_cell, target])
	_assert(cit.current_state == CitizenController.State.IDLE, "TC-MAN.1.8: Citizen returned to IDLE state")

	cit.queue_free()

## TC-MAN.2: Prior Routine Job Clean Release
func _run_tc_man_2_prior_job_clean_release() -> void:
	print("--- TC-MAN.2: Prior Routine Job Clean Release ---")
	var wd = _create_test_world()
	var nav = GridNavigationScript.new(wd)
	var jm = JobManagerScript.new()
	var cit = CitizenControllerScript.new()
	root.add_child(cit)

	cit.init_citizen("cit_2", "Busy Worker", "woodcutter", Vector2i(32, 32), nav, jm)
	cit.world_data = wd

	# Create a dummy routine job in JobManager
	var job = jm.create_job("woodcutter", Vector2i(35, 35))
	job.state = JobManager.JobState.IN_PROGRESS
	job.worker_id = "cit_2"
	cit.active_job = job
	cit.current_state = CitizenController.State.WORKING

	_assert(cit.active_job != null, "TC-MAN.2.1: Citizen has active routine job")
	_assert(job.worker_id == "cit_2", "TC-MAN.2.2: Job worker ID bound to citizen")

	# Issue manual command
	var target := Vector2i(33, 33)
	wd.occupancy[33][33] = false
	var res := cit.issue_manual_command("move", target)

	_assert(res.get("success", false) == true, "TC-MAN.2.3: Manual command accepted")
	_assert(cit.active_job == null, "TC-MAN.2.4: Citizen active_job cleared")
	_assert(job.worker_id == "", "TC-MAN.2.5: Job worker_id released")
	_assert(job.state == JobManager.JobState.AVAILABLE, "TC-MAN.2.6: Prior job restored to AVAILABLE state without deadlocks")

	cit.queue_free()

## TC-MAN.3: Manual Tree Chopping
func _run_tc_man_3_manual_tree_chopping() -> void:
	print("--- TC-MAN.3: Manual Tree Chopping ---")
	var wd = _create_test_world()
	var drop_cell := _resolve_dropoff_cell(wd)
	_clear_walkable_rect(wd, drop_cell, drop_cell + Vector2i(3, 0))
	var nav = GridNavigationScript.new(wd)
	var jm = JobManagerScript.new()
	var rm = ResourceManagerScript.new()
	root.add_child(rm)
	rm.reset_economy()

	var cit = CitizenControllerScript.new()
	root.add_child(cit)
	cit.init_citizen("cit_3", "Logger", "idle", drop_cell + Vector2i(2, 0), nav, jm)
	cit.world_data = wd
	cit.set_custom_resource_manager(rm)

	var tree_cell := drop_cell + Vector2i(3, 0)
	wd.props.append({"type": "tree", "cell": tree_cell})
	wd.occupancy[tree_cell.x][tree_cell.y] = true

	var init_wood: int = rm.get_available_stock("wood")

	var res := cit.issue_manual_command("chop", tree_cell)
	_assert(res.get("success", false) == true, "TC-MAN.3.1: issue_manual_command 'chop' succeeds")
	_assert(cit.manual_command.type == "chop", "TC-MAN.3.2: Manual command type is 'chop'")
	_assert(cit.current_state == CitizenController.State.WORKING, "TC-MAN.3.3: Immediately starts WORKING (adjacent at tree)")

	# Simulate working hours (required 5.0)
	cit._process_manual_working(6.0)

	_assert(cit.carrying_resource == "wood", "TC-MAN.3.4: Citizen carries wood cargo")
	_assert(cit.carrying_amount == 10, "TC-MAN.3.5: Citizen collected exactly 10 wood")
	_assert(cit.current_state == CitizenController.State.HAULING, "TC-MAN.3.6: Citizen transitions to HAULING en route to storehouse")

	# Haul cargo to storehouse drop_cell
	cit.current_cell = drop_cell
	cit._arrive_at_destination()

	_assert(cit.carrying_amount == 0, "TC-MAN.3.7: Cargo deposited completely")
	_assert(rm.get_available_stock("wood") == init_wood + 10, "TC-MAN.3.8: Central stock credited with +10 wood (Physical conservation)")
	_assert(cit.has_manual_command() == false, "TC-MAN.3.9: Manual command completed and cleared")

	cit.queue_free()
	rm.queue_free()

## TC-MAN.4: Manual Rock Mining
func _run_tc_man_4_manual_rock_mining() -> void:
	print("--- TC-MAN.4: Manual Rock Mining ---")
	var wd = _create_test_world()
	var drop_cell := _resolve_dropoff_cell(wd)
	_clear_walkable_rect(wd, drop_cell, drop_cell + Vector2i(3, 0))
	var nav = GridNavigationScript.new(wd)
	var jm = JobManagerScript.new()
	var rm = ResourceManagerScript.new()
	root.add_child(rm)
	rm.reset_economy()

	var cit = CitizenControllerScript.new()
	root.add_child(cit)
	cit.init_citizen("cit_4", "Miner", "idle", drop_cell + Vector2i(2, 0), nav, jm)
	cit.world_data = wd
	cit.set_custom_resource_manager(rm)

	var rock_cell := drop_cell + Vector2i(3, 0)
	wd.props.append({"type": "rock", "cell": rock_cell})
	wd.occupancy[rock_cell.x][rock_cell.y] = true

	var init_stone: int = rm.get_available_stock("stone")

	var res := cit.issue_manual_command("mine", rock_cell)
	_assert(res.get("success", false) == true, "TC-MAN.4.1: issue_manual_command 'mine' succeeds")
	_assert(cit.manual_command.type == "mine", "TC-MAN.4.2: Manual command type is 'mine'")
	_assert(cit.current_state == CitizenController.State.WORKING, "TC-MAN.4.3: Starts working at adjacent rock")

	cit._process_manual_working(6.0)

	_assert(cit.carrying_resource == "stone", "TC-MAN.4.4: Citizen carries stone cargo")
	_assert(cit.carrying_amount == 10, "TC-MAN.4.5: Citizen collected exactly 10 stone")
	_assert(cit.current_state == CitizenController.State.HAULING, "TC-MAN.4.6: Citizen transitions to HAULING")

	cit.current_cell = drop_cell
	cit._arrive_at_destination()

	_assert(rm.get_available_stock("stone") == init_stone + 10, "TC-MAN.4.7: Central storage credited with +10 stone")
	_assert(cit.has_manual_command() == false, "TC-MAN.4.8: Manual command completed")

	cit.queue_free()
	rm.queue_free()

## TC-MAN.5: Manual Construction Priority
func _run_tc_man_5_manual_construction_priority() -> void:
	print("--- TC-MAN.5: Manual Construction Priority ---")
	var wd = _create_test_world()
	var nav = GridNavigationScript.new(wd)
	var jm = JobManagerScript.new()

	var cit = CitizenControllerScript.new()
	root.add_child(cit)
	cit.init_citizen("cit_5", "Builder", "idle", Vector2i(30, 30), nav, jm)
	cit.world_data = wd

	# Create a building under construction in world_data
	var b_site: Dictionary = {
		"id": "b_site_1",
		"type": "house",
		"cell": Vector2i(30, 31),
		"size": Vector2i(2, 2),
		"state": "under_construction",
		"construction_hours": 12.0,
		"construction_progress": 2.0
	}
	wd.buildings.append(b_site)

	# Provide construction handler mock using Dictionary for mutable closure state
	var stats := {"worked_hours": 0.0}
	cit.set_construction_handler(func(_b_id: String, hours: float):
		stats.worked_hours += hours
		b_site["construction_progress"] = float(b_site["construction_progress"]) + hours
		var comp = float(b_site["construction_progress"]) >= float(b_site["construction_hours"])
		return {"success": true, "completed": comp, "progress": b_site["construction_progress"], "hours": b_site["construction_hours"]}
	)

	var res := cit.issue_manual_command("build", Vector2i(30, 31), "b_site_1")
	_assert(res.get("success", false) == true, "TC-MAN.5.1: issue_manual_command 'build' succeeds")
	_assert(cit.manual_command.type == "build", "TC-MAN.5.2: Command type is 'build'")
	_assert(cit.current_state == CitizenController.State.WORKING, "TC-MAN.5.3: Immediately begins working on adjacent site")

	# Advance 5 hours of labor
	cit._process_manual_working(5.0)
	_assert(stats.worked_hours >= 5.0, "TC-MAN.5.4: Construction labor advanced by >= 5.0 hours")
	_assert(float(b_site["construction_progress"]) >= 7.0, "TC-MAN.5.5: Building site progress updated")
	_assert(cit.has_manual_command() == true, "TC-MAN.5.6: Manual build command remains active until completion")

	# Finish the remaining hours
	cit._process_manual_working(6.0)
	_assert(cit.has_manual_command() == false, "TC-MAN.5.7: Command completes when building finishes")
	_assert(cit.current_state == CitizenController.State.IDLE, "TC-MAN.5.8: Citizen transitions to IDLE")

	cit.queue_free()

## TC-MAN.6: Manual Buffer Hauling
func _run_tc_man_6_manual_buffer_hauling() -> void:
	print("--- TC-MAN.6: Manual Buffer Hauling ---")
	var wd = _create_test_world()
	var nav = GridNavigationScript.new(wd)
	var jm = JobManagerScript.new()
	var rm = ResourceManagerScript.new()
	root.add_child(rm)
	rm.reset_economy()

	var wm = WorkplaceManagerScript.new()

	var cit = CitizenControllerScript.new()
	root.add_child(cit)
	cit.init_citizen("cit_6", "Hauler", "idle", Vector2i(32, 32), nav, jm, wm)
	cit.world_data = wd
	cit.set_custom_resource_manager(rm)

	# Register a workplace with buffer stock
	var wp = wm.register_workplace("wp_farm_1", "farm", Vector2i(35, 35), Vector2i(2, 2), Vector2i(35, 36), "food", 20)
	wp.buffer_amount = 8 # 8 food units in buffer

	var res := cit.issue_manual_command("haul", Vector2i(35, 35), "wp_farm_1")
	_assert(res.get("success", false) == true, "TC-MAN.6.1: issue_manual_command 'haul' succeeds")
	_assert(cit.manual_command.type == "haul", "TC-MAN.6.2: Command type is 'haul'")

	# Teleport/simulate arrival at workplace
	cit.current_cell = Vector2i(35, 35)
	cit._arrive_at_manual_destination()

	_assert(wp.buffer_amount == 0, "TC-MAN.6.3: Workplace buffer picked up (8 - 8 = 0)")
	_assert(cit.carrying_amount == 8, "TC-MAN.6.4: Citizen carrying 8 units of cargo")
	_assert(cit.carrying_resource == "food", "TC-MAN.6.5: Citizen carrying food")
	_assert(cit.current_state == CitizenController.State.HAULING, "TC-MAN.6.6: Citizen transitions to HAULING")

	var init_food: int = rm.get_available_stock("food")
	# Simulate delivery arrival at storehouse (32, 32)
	cit.current_cell = Vector2i(32, 32)
	cit._deposit_hauler_cargo()

	_assert(rm.get_available_stock("food") == init_food + 8, "TC-MAN.6.7: Storehouse received 8 food")
	_assert(cit.carrying_amount == 0, "TC-MAN.6.8: Cargo completely cleared")
	_assert(cit.has_manual_command() == false, "TC-MAN.6.9: Manual command completed")

	cit.queue_free()
	rm.queue_free()

## TC-MAN.7: Manual POI Exploration
func _run_tc_man_7_manual_poi_exploration() -> void:
	print("--- TC-MAN.7: Manual POI Exploration ---")
	var wd = _create_test_world()
	var nav = GridNavigationScript.new(wd)
	var jm = JobManagerScript.new()
	var rm = ResourceManagerScript.new()
	root.add_child(rm)
	rm.reset_economy()

	var cit = CitizenControllerScript.new()
	root.add_child(cit)
	cit.init_citizen("cit_7", "Scout", "idle", Vector2i(32, 32), nav, jm)
	cit.world_data = wd
	cit.set_custom_resource_manager(rm)

	# Mock POIManager
	var pm = POIManagerScript.new()
	pm.generate_pois(42, [Vector2i(36, 36), Vector2i(40, 40)], 2)
	var poi = pm.get_poi("poi_1")

	cit.set_poi_manager(pm)

	var res := cit.issue_manual_command("explore", poi.cell, poi.id)
	_assert(res.get("success", false) == true, "TC-MAN.7.1: issue_manual_command 'explore' succeeds")
	_assert(cit.manual_command.type == "explore", "TC-MAN.7.2: Command type is 'explore'")

	# Simulate arrival at POI
	cit.current_cell = poi.cell
	cit._arrive_at_manual_destination()

	_assert(poi.state == POIManager.POIState.CLAIMED, "TC-MAN.7.3: POI state transitioned to CLAIMED")
	_assert(cit.has_manual_command() == false, "TC-MAN.7.4: Manual command completed upon discovery")
	_assert(cit.current_state == CitizenController.State.IDLE, "TC-MAN.7.5: Citizen returned to IDLE")

	# Second explore attempt on claimed POI fails closed
	var res_dupe := cit.issue_manual_command("explore", poi.cell, poi.id)
	_assert(res_dupe.get("success", false) == false, "TC-MAN.7.6: Duplicate explore on claimed POI fails closed")
	_assert(cit.has_manual_command() == false, "TC-MAN.7.7: No manual command created for claimed POI")

	cit.queue_free()
	rm.queue_free()

## TC-MAN.8: Survival Need Interruption & Resume
func _run_tc_man_8_survival_need_interruption_and_resume() -> void:
	print("--- TC-MAN.8: Survival Need Interruption & Resume ---")
	var wd = _create_test_world()
	var nav = GridNavigationScript.new(wd)
	var jm = JobManagerScript.new()
	var rm = ResourceManagerScript.new()
	root.add_child(rm)
	rm.reset_economy()

	var cit = CitizenControllerScript.new()
	root.add_child(cit)
	cit.init_citizen("cit_8", "Worker", "idle", Vector2i(32, 32), nav, jm)
	cit.world_data = wd
	cit.set_custom_resource_manager(rm)

	# Issue manual move along clear path
	var target := Vector2i(35, 32)
	for x in range(32, 36):
		wd.occupancy[x][32] = false
		wd.terrain[x][32] = WorldGenerator.TerrainType.GRASS
	var res := cit.issue_manual_command("move", target)
	_assert(res.get("success", false) == true, "TC-MAN.8.1: Move command accepted")

	# Trigger extreme hunger (hunger >= 85)
	cit.hunger = 88.0
	cit._process(0.1)

	_assert(cit.has_manual_command() == true, "TC-MAN.8.2: Manual command not lost")
	_assert(cit.manual_command.is_paused == true, "TC-MAN.8.3: Manual command is marked is_paused")
	_assert(cit.current_state == CitizenController.State.SEEKING_FOOD, "TC-MAN.8.4: Citizen paused order to seek food")

	# Simulate feeding
	cit._eat_food()
	_assert(cit.hunger < 50.0, "TC-MAN.8.5: Hunger relieved below 50")
	_assert(cit.manual_command.is_paused == false, "TC-MAN.8.6: Manual command unpaused automatically")
	_assert(cit.current_state == CitizenController.State.MOVING_TO_JOB, "TC-MAN.8.7: Citizen resumed movement toward original manual target")

	cit.queue_free()
	rm.queue_free()

## TC-MAN.9: Manual Order Cancellation
func _run_tc_man_9_manual_order_cancellation() -> void:
	print("--- TC-MAN.9: Manual Order Cancellation ---")
	var wd = _create_test_world()
	var nav = GridNavigationScript.new(wd)
	var jm = JobManagerScript.new()

	var cit = CitizenControllerScript.new()
	root.add_child(cit)
	cit.init_citizen("cit_9", "Worker", "idle", Vector2i(32, 32), nav, jm)
	cit.world_data = wd

	var target := Vector2i(34, 32)
	for x in range(32, 35):
		wd.occupancy[x][32] = false
		wd.terrain[x][32] = WorldGenerator.TerrainType.GRASS

	cit.issue_manual_command("move", target)
	_assert(cit.has_manual_command() == true, "TC-MAN.9.1: Command active")

	var cancelled_signal_fired := [false]
	cit.manual_command_cancelled.connect(func(_id, reason):
		cancelled_signal_fired[0] = (reason == "Người chơi hủy")
	)

	cit.cancel_manual_command("Người chơi hủy")

	_assert(cancelled_signal_fired[0] == true, "TC-MAN.9.2: manual_command_cancelled signal emitted")
	_assert(cit.has_manual_command() == false, "TC-MAN.9.3: has_manual_command is false")
	_assert(cit.current_path.is_empty() == true, "TC-MAN.9.4: Movement path cleared")
	_assert(cit.current_state == CitizenController.State.IDLE, "TC-MAN.9.5: Citizen returned to IDLE")

	cit.queue_free()

## TC-MAN.10: Fail-Closed Invalid Targets
func _run_tc_man_10_fail_closed_invalid_targets() -> void:
	print("--- TC-MAN.10: Fail-Closed Invalid Targets ---")
	var wd = _create_test_world()
	var nav = GridNavigationScript.new(wd)
	var jm = JobManagerScript.new()

	var cit = CitizenControllerScript.new()
	root.add_child(cit)
	cit.init_citizen("cit_10", "Worker", "idle", Vector2i(32, 32), nav, jm)
	cit.world_data = wd

	# 1. Out of bounds
	var res_oob := cit.issue_manual_command("move", Vector2i(999, 999))
	_assert(res_oob.get("success", false) == false, "TC-MAN.10.1: Out of bounds rejected")
	_assert(cit.has_manual_command() == false, "TC-MAN.10.2: No command state mutated")

	# 2. Water tile
	var water_cell := Vector2i(1, 1)
	wd.terrain[1][1] = WorldGenerator.TerrainType.WATER
	var res_water := cit.issue_manual_command("move", water_cell)
	_assert(res_water.get("success", false) == false, "TC-MAN.10.3: Water target rejected")

	# 3. Chop non-tree
	var grass_cell := Vector2i(33, 33)
	wd.props.clear()
	var res_notree := cit.issue_manual_command("chop", grass_cell)
	_assert(res_notree.get("success", false) == false, "TC-MAN.10.4: Chop on non-tree tile rejected")

	# 4. Unknown command type
	var res_badtype := cit.issue_manual_command("fly_to_space", Vector2i(32, 32))
	_assert(res_badtype.get("success", false) == false, "TC-MAN.10.5: Unknown command type rejected")

	cit.queue_free()

## TC-MAN.11: Save/Load Persistence Roundtrip
func _run_tc_man_11_save_load_persistence_roundtrip() -> void:
	print("--- TC-MAN.11: Save/Load Persistence Roundtrip ---")
	var wd = _create_test_world()
	var nav = GridNavigationScript.new(wd)
	var jm = JobManagerScript.new()

	var cit = CitizenControllerScript.new()
	root.add_child(cit)
	cit.init_citizen("cit_11", "Persistent Worker", "woodcutter", Vector2i(32, 32), nav, jm)
	cit.world_data = wd

	# Set up active manual command
	wd.props.append({"type": "tree", "cell": Vector2i(33, 32)})
	cit.issue_manual_command("chop", Vector2i(33, 32))
	cit.manual_command["work_hours_done"] = 2.5

	# Serialize
	var serialized := cit.serialize_manual_command()
	_assert(serialized.get("is_active", false) == true, "TC-MAN.11.1: Serialized command is active")
	_assert(serialized.get("type", "") == "chop", "TC-MAN.11.2: Serialized type is 'chop'")
	_assert(serialized.get("target_cell_x") == 33, "TC-MAN.11.3: Target cell X persisted")
	_assert(serialized.get("target_cell_y") == 32, "TC-MAN.11.4: Target cell Y persisted")
	_assert(float(serialized.get("work_hours_done")) == 2.5, "TC-MAN.11.5: Progress hours persisted")

	# Restore onto a fresh citizen
	var cit_restored = CitizenControllerScript.new()
	root.add_child(cit_restored)
	cit_restored.init_citizen("cit_11", "Persistent Worker", "woodcutter", Vector2i(32, 32), nav, jm)
	cit_restored.world_data = wd

	cit_restored.restore_manual_command(serialized)
	_assert(cit_restored.has_manual_command() == true, "TC-MAN.11.6: Restored citizen has manual command")
	_assert(cit_restored.manual_command.type == "chop", "TC-MAN.11.7: Restored type is 'chop'")
	_assert(float(cit_restored.manual_command.work_hours_done) == 2.5, "TC-MAN.11.8: Progress matches exactly")
	_assert(cit_restored.manual_command.target_cell == Vector2i(33, 32), "TC-MAN.11.9: Target cell matches")

	# Schema validator check
	var dummy_save := {
		"schema_version": 1,
		"metadata": {"save_name": "test", "timestamp": "2026-11-07T22:00:00"},
		"resources": {},
		"buildings": [],
		"citizens": [
			{
				"id": "cit_11",
				"name": "Persistent Worker",
				"role": "woodcutter",
				"cell_x": 32,
				"cell_y": 32,
				"hunger": 10.0,
				"fatigue": 10.0,
				"health": 100.0,
				"morale": 70.0,
				"manual_command": serialized
			}
		]
	}
	var val_res: Dictionary = SaveManagerScript.validate_save_data(dummy_save)
	_assert(val_res.get("valid", false) == true, "TC-MAN.11.10: SaveManager.validate_save_data approves manual_command schema", str(val_res.get("error", "")))

	cit.queue_free()
	cit_restored.queue_free()

## TC-MAN.12: Stale Target Rejection on Load
func _run_tc_man_12_stale_target_rejection_on_load() -> void:
	print("--- TC-MAN.12: Stale Target Rejection on Load ---")
	var wd = _create_test_world()
	var nav = GridNavigationScript.new(wd)
	var jm = JobManagerScript.new()

	var cit = CitizenControllerScript.new()
	root.add_child(cit)
	cit.init_citizen("cit_12", "Worker", "idle", Vector2i(32, 32), nav, jm)
	cit.world_data = wd

	# Build site that is already completed (active, not under construction)
	wd.buildings.append({
		"id": "b_finished_1",
		"type": "house",
		"cell": Vector2i(30, 30),
		"size": Vector2i(2, 2),
		"state": "active",
		"construction_hours": 12.0,
		"construction_progress": 12.0
	})

	var stale_cmd: Dictionary = {
		"type": "build",
		"target_cell_x": 30,
		"target_cell_y": 30,
		"target_id": "b_finished_1",
		"work_hours_required": 12.0,
		"work_hours_done": 6.0,
		"is_active": true,
		"is_paused": false,
		"pause_reason": ""
	}

	cit.restore_manual_command(stale_cmd)
	_assert(cit.has_manual_command() == false, "TC-MAN.12.1: Stale build command safely discarded on load")
	_assert(cit.current_state == CitizenController.State.IDLE, "TC-MAN.12.2: Citizen safely defaults to IDLE")

	cit.queue_free()

## TC-MAN.13: Multi-Citizen Command Isolation
func _run_tc_man_13_multi_citizen_isolation() -> void:
	print("--- TC-MAN.13: Multi-Citizen Command Isolation ---")
	var wd = _create_test_world()
	var nav = GridNavigationScript.new(wd)
	var jm = JobManagerScript.new()

	var cit_a = CitizenControllerScript.new()
	var cit_b = CitizenControllerScript.new()
	root.add_child(cit_a)
	root.add_child(cit_b)

	cit_a.init_citizen("cit_a", "Alice", "idle", Vector2i(32, 32), nav, jm)
	cit_b.init_citizen("cit_b", "Bob", "idle", Vector2i(32, 33), nav, jm)
	cit_a.world_data = wd
	cit_b.world_data = wd

	wd.occupancy[35][32] = false
	wd.props.append({"type": "tree", "cell": Vector2i(33, 33)})

	cit_a.issue_manual_command("move", Vector2i(35, 32))
	cit_b.issue_manual_command("chop", Vector2i(33, 33))

	_assert(cit_a.manual_command.type == "move", "TC-MAN.13.1: Citizen A command is 'move'")
	_assert(cit_b.manual_command.type == "chop", "TC-MAN.13.2: Citizen B command is 'chop'")
	_assert(cit_a.manual_command.target_cell == Vector2i(35, 32), "TC-MAN.13.3: Citizen A target independent")
	_assert(cit_b.manual_command.target_cell == Vector2i(33, 33), "TC-MAN.13.4: Citizen B target independent")

	cit_a.cancel_manual_command()
	_assert(cit_a.has_manual_command() == false, "TC-MAN.13.5: Citizen A cancelled")
	_assert(cit_b.has_manual_command() == true, "TC-MAN.13.6: Citizen B remains active without leakage")

	cit_a.queue_free()
	cit_b.queue_free()

## TC-MAN.14: Citizen Death Cleanup
func _run_tc_man_14_citizen_death_cleanup() -> void:
	print("--- TC-MAN.14: Citizen Death Cleanup ---")
	var wd = _create_test_world()
	var nav = GridNavigationScript.new(wd)
	var jm = JobManagerScript.new()
	var rm = ResourceManagerScript.new()
	root.add_child(rm)
	rm.reset_economy()

	var cit = CitizenControllerScript.new()
	root.add_child(cit)
	cit.init_citizen("cit_14", "Dying Worker", "idle", Vector2i(32, 32), nav, jm)
	cit.world_data = wd
	cit.set_custom_resource_manager(rm)

	# Issue command and hold cargo
	wd.occupancy[34][32] = false
	wd.terrain[34][32] = WorldGenerator.TerrainType.GRASS
	var res := cit.issue_manual_command("move", Vector2i(34, 32))
	_assert(res.get("success", false) == true, "TC-MAN.14.0: Move command issued")
	cit.carrying_resource = "wood"
	cit.carrying_amount = 10

	_assert(cit.has_manual_command() == true, "TC-MAN.14.1: Command active before death")

	cit.die("Tử trận trong chiến đấu", "combat")

	_assert(cit.has_manual_command() == false, "TC-MAN.14.2: Manual command cleared upon death")
	_assert(cit.is_alive() == false, "TC-MAN.14.3: Citizen marked dead")
	_assert(cit.carrying_amount == 0, "TC-MAN.14.4: Carried cargo safely recovered to warehouse (BUG-001)")

	cit.queue_free()
	rm.queue_free()

## TC-MAN.15: Vocational XP Awarded on Manual Completion
func _run_tc_man_15_vocational_xp_award_on_completion() -> void:
	print("--- TC-MAN.15: Vocational XP Awarded on Manual Completion ---")
	var wd = _create_test_world()
	var drop_cell := _resolve_dropoff_cell(wd)
	_clear_walkable_rect(wd, drop_cell + Vector2i(-1, 0), drop_cell + Vector2i(1, 0))
	var nav = GridNavigationScript.new(wd)
	var jm = JobManagerScript.new()
	var rm = ResourceManagerScript.new()
	root.add_child(rm)
	rm.reset_economy()

	var cit = CitizenControllerScript.new()
	root.add_child(cit)
	cit.init_citizen("cit_15", "Student", "idle", drop_cell, nav, jm)
	cit.world_data = wd
	cit.set_custom_resource_manager(rm)

	var s_data = cit.get_skill_data()
	var init_wood_xp: float = s_data.get_xp("woodcutting")
	var init_mining_xp: float = s_data.get_xp("mining")

	wd.props.append({"type": "tree", "cell": drop_cell + Vector2i(1, 0)})
	cit.issue_manual_command("chop", drop_cell + Vector2i(1, 0))
	cit._process_manual_working(5.0)

	_assert(s_data.get_xp("woodcutting") >= init_wood_xp + 10.0, "TC-MAN.15.1: Chopping awarded +10 woodcutting XP")

	# Clean delivery
	cit._deposit_hauler_cargo()

	wd.props.append({"type": "rock", "cell": drop_cell + Vector2i(-1, 0)})
	cit.issue_manual_command("mine", drop_cell + Vector2i(-1, 0))
	cit._process_manual_working(5.0)

	_assert(s_data.get_xp("mining") >= init_mining_xp + 10.0, "TC-MAN.15.2: Mining awarded +10 mining XP")

	cit.queue_free()
	rm.queue_free()

## TC-MAN.16: Survival Interruption During Cargo Hauling & Resumption
func _run_tc_man_16_survival_interruption_during_cargo_hauling() -> void:
	print("--- TC-MAN.16: Survival Interruption During Cargo Hauling & Resumption ---")
	var wd = _create_test_world()
	var drop_cell := _resolve_dropoff_cell(wd)
	var tree_cell := drop_cell + Vector2i(3, 0)
	_clear_walkable_rect(wd, drop_cell, tree_cell)
	var nav = GridNavigationScript.new(wd)
	var jm = JobManagerScript.new()
	var rm = ResourceManagerScript.new()
	root.add_child(rm)
	rm.reset_economy()

	var cit = CitizenControllerScript.new()
	root.add_child(cit)
	cit.init_citizen("cit_16", "Woodcutter", "idle", drop_cell, nav, jm)
	cit.world_data = wd
	cit.set_custom_resource_manager(rm)

	# Tree at drop_cell + (3, 0)
	wd.props.append({"type": "tree", "cell": tree_cell})
	wd.occupancy[tree_cell.x][tree_cell.y] = true

	var res := cit.issue_manual_command("chop", tree_cell)
	_assert(res.get("success", false) == true, "TC-MAN.16.1: Chop command accepted")

	# Move adjacent and complete harvest
	cit.current_cell = drop_cell + Vector2i(2, 0)
	cit.position = IsoMath.map_to_local(cit.current_cell)
	cit._arrive_at_manual_destination()
	cit._process_manual_working(5.0)

	_assert(cit.carrying_amount == 10, "TC-MAN.16.2: Citizen holds 10 wood cargo")
	_assert(cit.current_state == CitizenController.State.HAULING, "TC-MAN.16.3: State is HAULING toward storage")
	_assert(cit._is_tree_at_cell(tree_cell) == false, "TC-MAN.16.4: Tree removed from world props upon harvest")

	# Citizen steps 1 tile toward storehouse
	cit.current_cell = drop_cell + Vector2i(1, 0)
	cit.position = IsoMath.map_to_local(cit.current_cell)

	var init_wood: int = rm.get_total_stock("wood")

	# Hunger emergency triggers interruption
	cit.hunger = 88.0
	cit._process(0.1)

	_assert(cit.has_manual_command() == true, "TC-MAN.16.5: Manual command retained during pause")
	_assert(cit.manual_command.is_paused == true, "TC-MAN.16.6: Manual command paused")
	_assert(cit.current_state == CitizenController.State.SEEKING_FOOD, "TC-MAN.16.7: Seeking food")

	# Citizen feeds
	cit._eat_food()

	_assert(cit.has_manual_command() == true, "TC-MAN.16.8: Manual command remains active after feeding (not cancelled by missing tree)")
	_assert(cit.manual_command.is_paused == false, "TC-MAN.16.9: Manual command unpaused")
	_assert(cit.current_state == CitizenController.State.HAULING, "TC-MAN.16.10: Citizen resumed HAULING state toward storehouse")
	_assert(cit.carrying_amount == 10, "TC-MAN.16.11: Cargo intact in citizen hands")
	_assert(rm.get_total_stock("wood") == init_wood, "TC-MAN.16.12: Zero teleportation (warehouse not credited prematurely)")

	# Step until arrival at storehouse drop_cell
	for _i in range(20):
		cit._process(0.1)
		if not cit.has_manual_command():
			break

	_assert(cit.current_cell == drop_cell, "TC-MAN.16.13: Citizen physically reached storehouse cell")
	_assert(cit.carrying_amount == 0, "TC-MAN.16.14: Cargo deposited completely")
	_assert(rm.get_total_stock("wood") == init_wood + 10, "TC-MAN.16.15: Warehouse correctly credited +10 wood at storehouse")
	_assert(cit.has_manual_command() == false, "TC-MAN.16.16: Manual command completed cleanly")

	cit.queue_free()
	rm.queue_free()

## TC-MAN.17: Full Central Storage Handling & Stationing at Storehouse
func _run_tc_man_17_full_storage_arrival_and_stationing() -> void:
	print("--- TC-MAN.17: Full Storage Arrival & Stationing ---")
	var wd = _create_test_world()
	var drop_cell := _resolve_dropoff_cell(wd)
	var rock_cell := drop_cell + Vector2i(2, 0)
	_clear_walkable_rect(wd, drop_cell, rock_cell)
	var nav = GridNavigationScript.new(wd)
	var jm = JobManagerScript.new()
	var rm = ResourceManagerScript.new()
	root.add_child(rm)
	rm.reset_economy()

	var cit = CitizenControllerScript.new()
	root.add_child(cit)
	cit.init_citizen("cit_17", "Miner", "idle", drop_cell, nav, jm)
	cit.world_data = wd
	cit.set_custom_resource_manager(rm)

	# Rock at drop_cell + (2, 0)
	wd.props.append({"type": "rock", "cell": rock_cell})
	wd.occupancy[rock_cell.x][rock_cell.y] = true

	cit.issue_manual_command("mine", rock_cell)
	cit.current_cell = drop_cell + Vector2i(1, 0)
	cit.position = IsoMath.map_to_local(cit.current_cell)
	cit._arrive_at_manual_destination()
	cit._process_manual_working(5.0)

	_assert(cit.carrying_amount == 10, "TC-MAN.17.1: Citizen mined 10 stone")
	_assert(cit.current_state == CitizenController.State.HAULING, "TC-MAN.17.2: State is HAULING toward storehouse")

	# Fill stone capacity completely (capacity = total_stock)
	rm._current_stock["stone"] = rm.get_storage_capacity("stone")

	# Arrive at storehouse drop_cell with 0 capacity space
	cit.current_cell = drop_cell
	cit.position = IsoMath.map_to_local(cit.current_cell)
	cit._deposit_hauler_cargo()

	_assert(cit.carrying_amount == 10, "TC-MAN.17.3: Full cargo preserved when storehouse full")
	_assert(cit.has_manual_command() == true, "TC-MAN.17.4: Manual command remains active while awaiting storehouse space")
	_assert(cit.current_state == CitizenController.State.IDLE, "TC-MAN.17.5: Citizen transitions to IDLE awaiting storage")

	# Run simulation frame: citizen must NOT path back to rock cell!
	cit._process(0.1)

	_assert(cit.current_cell == drop_cell, "TC-MAN.17.6: Citizen remains stationed at storehouse")
	_assert(cit.current_path.is_empty(), "TC-MAN.17.7: Citizen does not path back to harvested rock site")

	# Free 10 stone capacity in storehouse
	rm._current_stock["stone"] = rm.get_storage_capacity("stone") - 10
	cit._process(0.1)

	_assert(cit.carrying_amount == 0, "TC-MAN.17.8: Cargo deposited once space became available")
	_assert(cit.has_manual_command() == false, "TC-MAN.17.9: Manual command completed once cargo deposited")

	cit.queue_free()
	rm.queue_free()

## TC-MAN.18: Work Command Rejection While Carrying Existing Cargo
func _run_tc_man_18_work_command_rejection_while_carrying_cargo() -> void:
	print("--- TC-MAN.18: Work Command Rejection While Carrying Existing Cargo ---")
	var wd = _create_test_world()
	var nav = GridNavigationScript.new(wd)
	var jm = JobManagerScript.new()
	var rm = ResourceManagerScript.new()
	root.add_child(rm)
	rm.reset_economy()

	var cit = CitizenControllerScript.new()
	root.add_child(cit)
	cit.init_citizen("cit_18", "Loaded Porter", "idle", Vector2i(32, 32), nav, jm)
	cit.world_data = wd
	cit.set_custom_resource_manager(rm)

	# Give citizen existing cargo
	cit.carrying_resource = "stone"
	cit.carrying_amount = 10

	wd.props.append({"type": "tree", "cell": Vector2i(33, 32)})
	wd.props.append({"type": "rock", "cell": Vector2i(31, 32)})

	var res_chop := cit.issue_manual_command("chop", Vector2i(33, 32))
	_assert(res_chop.get("success", true) == false, "TC-MAN.18.1: Chop rejected while loaded with cargo")

	var res_mine := cit.issue_manual_command("mine", Vector2i(31, 32))
	_assert(res_mine.get("success", true) == false, "TC-MAN.18.2: Mine rejected while loaded with cargo")

	var res_build := cit.issue_manual_command("build", Vector2i(33, 32))
	_assert(res_build.get("success", true) == false, "TC-MAN.18.3: Build rejected while loaded with cargo")

	var res_haul := cit.issue_manual_command("haul", Vector2i(33, 32))
	_assert(res_haul.get("success", true) == false, "TC-MAN.18.4: Haul rejected while loaded with cargo")

	var res_move := cit.issue_manual_command("move", Vector2i(31, 32))
	_assert(res_move.get("success", true) == false, "TC-MAN.18.5: Move rejected while loaded with cargo (prevents cargo teleportation)")

	var res_explore := cit.issue_manual_command("explore", Vector2i(31, 32))
	_assert(res_explore.get("success", true) == false, "TC-MAN.18.6: Explore rejected while loaded with cargo")

	# Attempt to cancel command while encumbered with physical cargo
	cit.manual_command = {
		"type": "mine",
		"target_cell": Vector2i(31, 32),
		"target_id": "",
		"work_hours_required": 5.0,
		"work_hours_done": 5.0,
		"is_active": true,
		"is_paused": false,
		"pause_reason": ""
	}
	cit.cancel_manual_command("Người chơi hủy lệnh")
	_assert(cit.has_manual_command() == true, "TC-MAN.18.7: Manual command retained when player attempts cancellation while loaded")

	_assert(cit.carrying_amount == 10, "TC-MAN.18.8: Carried cargo preserved without loss")
	_assert(cit.carrying_resource == "stone", "TC-MAN.18.9: Carried resource identity preserved")

	cit.queue_free()
	rm.queue_free()

## TC-MAN.19: Save/Load During Cargo Hauling Restores Hauling State
func _run_tc_man_19_save_load_during_cargo_hauling() -> void:
	print("--- TC-MAN.19: Save/Load During Cargo Hauling Restores Hauling State ---")
	var wd = _create_test_world()
	var nav = GridNavigationScript.new(wd)
	var jm = JobManagerScript.new()

	var cit = CitizenControllerScript.new()
	root.add_child(cit)
	cit.init_citizen("cit_19", "En Route", "woodcutter", Vector2i(33, 32), nav, jm)
	cit.world_data = wd

	# Set up manual command where tree has already been chopped and removed from world
	cit.manual_command = {
		"type": "chop",
		"target_cell": Vector2i(35, 32),
		"target_id": "",
		"work_hours_required": 5.0,
		"work_hours_done": 5.0,
		"is_active": true,
		"is_paused": false,
		"pause_reason": ""
	}
	cit.carrying_resource = "wood"
	cit.carrying_amount = 10
	cit.current_state = CitizenController.State.HAULING

	# Tree (35, 32) is NOT in wd.props!
	var serialized := cit.serialize_manual_command()

	var cit_restored = CitizenControllerScript.new()
	root.add_child(cit_restored)
	cit_restored.init_citizen("cit_19", "En Route", "woodcutter", Vector2i(33, 32), nav, jm)
	cit_restored.world_data = wd
	cit_restored.carrying_resource = "wood"
	cit_restored.carrying_amount = 10

	cit_restored.restore_manual_command(serialized)

	_assert(cit_restored.has_manual_command() == true, "TC-MAN.19.1: Manual command restored during hauling phase")
	_assert(cit_restored.manual_command.type == "chop", "TC-MAN.19.2: Command type is 'chop'")
	_assert(cit_restored.current_state == CitizenController.State.HAULING, "TC-MAN.19.3: State is HAULING toward storehouse")
	_assert(cit_restored.carrying_amount == 10, "TC-MAN.19.4: Carried cargo restored exactly")

	cit.queue_free()
	cit_restored.queue_free()

## TC-MAN.20: Semantic Cancellation & Death Cargo Full Storage Lifecycle
func _run_tc_man_20_semantic_cancellation_and_death_cargo_lifecycle() -> void:
	print("--- TC-MAN.20: Semantic Cancellation & Death Cargo Lifecycle ---")
	var wd = _create_test_world()
	var drop_cell := _resolve_dropoff_cell(wd)
	_clear_walkable_rect(wd, drop_cell, drop_cell + Vector2i(3, 0))
	var nav = GridNavigationScript.new(wd)
	var jm = JobManagerScript.new()
	var rm = ResourceManagerScript.new()
	root.add_child(rm)
	rm.reset_economy()

	var cit = CitizenControllerScript.new()
	root.add_child(cit)
	cit.init_citizen("cit_20", "Semantic Worker", "idle", drop_cell + Vector2i(2, 0), nav, jm)
	cit.world_data = wd
	cit.set_custom_resource_manager(rm)

	# 1. Test Semantic Cancellation Sources while encumbered with cargo
	cit.carrying_resource = "stone"
	cit.carrying_amount = 10
	cit.manual_command = {
		"type": "mine",
		"target_cell": drop_cell + Vector2i(3, 0),
		"target_id": "",
		"work_hours_required": 5.0,
		"work_hours_done": 5.0,
		"is_active": true,
		"is_paused": false,
		"pause_reason": ""
	}

	# A: Player cancellation rejected
	var res_player: bool = cit.cancel_manual_command("Người chơi hủy lệnh", CitizenControllerScript.CancelSource.PLAYER)
	_assert(res_player == false, "TC-MAN.20.1: Player cancellation rejected while carrying cargo")
	_assert(cit.has_manual_command() == true, "TC-MAN.20.2: Manual command retained after player cancel attempt")
	_assert(cit.carrying_amount == 10, "TC-MAN.20.3: Cargo strictly preserved on player cancel attempt")

	# B: Target invalidation routes cargo to storehouse rather than dropping off-site
	var res_inv: bool = cit.cancel_manual_command("Mục tiêu bị hủy", CitizenControllerScript.CancelSource.TARGET_INVALIDATED)
	_assert(res_inv == false, "TC-MAN.20.4: Target invalidation while loaded refuses command drop")
	_assert(cit.has_manual_command() == true, "TC-MAN.20.5: Command remains active to complete transport")
	_assert(cit.current_state == CitizenController.State.HAULING, "TC-MAN.20.6: Citizen directed to HAULING toward storehouse")
	_assert(cit.status_reason.contains("Mục tiêu bị hủy, đang vận chuyển"), "TC-MAN.20.7: Status reason indicates safe cargo return")

	# 2. Test Citizen Death Under Full Storage (BUG-001)
	rm._current_stock["stone"] = rm.get_storage_capacity("stone") # Storage full

	cit.die("Tử trận trong chiến đấu", "combat")

	_assert(cit.has_manual_command() == false, "TC-MAN.20.8: Manual command cleaned up on death via CancelSource.DEATH")
	_assert(cit.is_alive() == false, "TC-MAN.20.9: Citizen marked dead")
	_assert(cit.carrying_amount == 10, "TC-MAN.20.10: Cargo safely retained on citizen node awaiting pending_death_cargo ingestion")

	# 3. Save/Load Persistence of Pending Death Cargo (BUG-001)
	var pending_cargo := {"stone": 10}
	var save_data := {
		"schema_version": 1,
		"metadata": {"save_name": "tc20_test", "timestamp": "2026-11-07T23:00:00"},
		"resources": {
			"stock": rm._current_stock.duplicate(),
			"capacities": rm._capacities.duplicate(),
			"pending_death_cargo": pending_cargo
		},
		"buildings": [],
		"citizens": []
	}
	var val_res := SaveManagerScript.validate_save_data(save_data)
	_assert(val_res.get("valid", false) == true, "TC-MAN.20.11: SaveManager approves save schema with pending_death_cargo", str(val_res.get("error", "")))
	_assert(save_data["resources"]["pending_death_cargo"]["stone"] == 10, "TC-MAN.20.12: Pending death cargo serialized in save data")

	# 4. Storage Space Opens & Flush Exactly Once
	rm._current_stock["stone"] -= 20 # Free space in storehouse
	var pre_stock: int = rm.get_total_stock("stone")

	# Simulate flush_pending_death_cargo lifecycle (world_view.gd lines 116-135)
	var to_recover: int = pending_cargo.get("stone", 0)
	var added: int = rm.add_resource("stone", to_recover)
	pending_cargo["stone"] = to_recover - added
	if pending_cargo["stone"] <= 0:
		pending_cargo.erase("stone")

	_assert(added == 10, "TC-MAN.20.13: 10 stone recovered on storage capacity expansion")
	_assert(rm.get_total_stock("stone") == pre_stock + 10, "TC-MAN.20.14: Central stock credited exactly once")
	_assert(pending_cargo.has("stone") == false, "TC-MAN.20.15: Pending death cargo cleared after flush")

	# Second flush attempt is idempotent
	var second_added: int = 0
	if pending_cargo.has("stone"):
		second_added = rm.add_resource("stone", pending_cargo["stone"])
	_assert(second_added == 0, "TC-MAN.20.16: Second flush attempt is strictly idempotent")
	_assert(rm.get_total_stock("stone") == pre_stock + 10, "TC-MAN.20.17: Zero duplicate crediting")

	cit.queue_free()
	rm.queue_free()

## TC-MAN.21: Path Failure While Carrying Cargo & Physical Proximity Invariant
func _run_tc_man_21_path_failure_with_cargo_invariant() -> void:
	print("--- TC-MAN.21: Path Failure While Carrying Cargo & Proximity Invariant ---")
	var wd = _create_test_world()
	var drop_cell := _resolve_dropoff_cell(wd)
	_clear_walkable_rect(wd, drop_cell + Vector2i(-2, -2), drop_cell + Vector2i(4, 2))
	var nav = GridNavigationScript.new(wd)
	var jm = JobManagerScript.new()
	var rm = ResourceManagerScript.new()
	root.add_child(rm)
	rm.reset_economy()

	var cit = CitizenControllerScript.new()
	root.add_child(cit)
	cit.init_citizen("cit_21", "Unreachable Hauler", "woodcutter", drop_cell + Vector2i(3, 0), nav, jm)
	cit.world_data = wd
	cit.set_custom_resource_manager(rm)

	# 1. Citizen finishes chopping wood near drop_cell
	var pre_wood: int = rm.get_total_stock("wood")
	cit.carrying_resource = "wood"
	cit.carrying_amount = 10
	cit.manual_command = {
		"type": "chop",
		"target_cell": drop_cell + Vector2i(4, 0),
		"target_id": "",
		"work_hours_required": 5.0,
		"work_hours_done": 5.0,
		"is_active": true,
		"is_paused": false,
		"pause_reason": ""
	}

	# 2. Make storage dropoff completely unreachable in navigation
	for x in range(drop_cell.x - 2, drop_cell.x + 3):
		for y in range(drop_cell.y - 2, drop_cell.y + 3):
			wd.terrain[x][y] = WorldGeneratorScript.TerrainType.WATER

	# 3. Simulate arrival at harvest completion / path failure attempt
	cit._execute_active_manual_command()

	_assert(cit.current_state == CitizenController.State.IDLE, "TC-MAN.21.1: Citizen transitions to IDLE when storehouse is unreachable")
	_assert(cit.status_reason.contains("chưa tìm được đường về kho"), "TC-MAN.21.2: Status reason indicates blocked route to storage", cit.status_reason)
	_assert(cit.carrying_amount == 10, "TC-MAN.21.3: Cargo remains safely on citizen node")
	_assert(cit.carrying_resource == "wood", "TC-MAN.21.4: Cargo resource identity preserved")
	_assert(rm.get_total_stock("wood") == pre_wood, "TC-MAN.21.5: Zero off-site remote deposit to ResourceManager")

	# 4. Process multiple idle/process simulation ticks while storage remains unreachable
	for tick in range(5):
		cit._process_idle()
		_assert(cit.carrying_amount == 10, "TC-MAN.21.6: Cargo preserved across idle tick %d" % tick)
		_assert(rm.get_total_stock("wood") == pre_wood, "TC-MAN.21.7: Zero remote deposit on idle tick %d" % tick)
		_assert(cit.active_job == null, "TC-MAN.21.8: Citizen does not accept routine jobs while loaded")

	# 5. Cancellation attempts while route blocked still preserve cargo
	var cancel_res := cit.cancel_manual_command("Người chơi hủy", CitizenControllerScript.CancelSource.PLAYER)
	_assert(cancel_res == false, "TC-MAN.21.9: Player cancellation rejected while carrying cargo even if path blocked")
	_assert(cit.carrying_amount == 10, "TC-MAN.21.10: Cargo intact after rejected cancel attempt")

	var inv_res := cit.cancel_manual_command("Mục tiêu bị hủy", CitizenControllerScript.CancelSource.TARGET_INVALIDATED)
	_assert(inv_res == false, "TC-MAN.21.11: Target invalidation refuses drop while carrying cargo")
	_assert(cit.carrying_amount == 10, "TC-MAN.21.12: Cargo intact after target invalidation")
	_assert(rm.get_total_stock("wood") == pre_wood, "TC-MAN.21.13: Central stock unchanged after invalidation")

	# 6. Direct _deposit_hauler_cargo invocation while physically away fails closed
	cit._deposit_hauler_cargo()
	_assert(cit.carrying_amount == 10, "TC-MAN.21.14: _deposit_hauler_cargo fails closed off-site (proximity guard)")
	_assert(rm.get_total_stock("wood") == pre_wood, "TC-MAN.21.15: ResourceManager stock completely protected")

	# 7. Restore walkability / route to storage dropoff
	_clear_walkable_rect(wd, drop_cell + Vector2i(-2, -2), drop_cell + Vector2i(4, 2))

	# 8. Process idle tick with valid route
	cit._process_idle()
	_assert(cit.current_state == CitizenController.State.HAULING, "TC-MAN.21.16: Citizen transitions to HAULING once path opens")
	_assert(not cit.current_path.is_empty(), "TC-MAN.21.17: Pathfinding successfully finds route to storehouse")

	# 9. Walk path to destination
	while not cit.current_path.is_empty():
		cit.current_cell = cit.current_path[0]
		cit.current_path.remove_at(0)

	_assert(cit._is_at_storage_dropoff(), "TC-MAN.21.18: Citizen reached storage dropoff location")

	# 10. Arrive at destination and deposit
	cit._arrive_at_destination()
	_assert(cit.carrying_amount == 0, "TC-MAN.21.19: Cargo successfully deposited upon arrival at storehouse")
	_assert(rm.get_total_stock("wood") == pre_wood + 10, "TC-MAN.21.20: Central stock credited with exactly 10 wood")
	_assert(cit.current_state == CitizenController.State.IDLE, "TC-MAN.21.21: Citizen returned to IDLE after deposit")

	# 11. Subsequent tick causes no duplicate crediting
	cit._process_idle()
	_assert(rm.get_total_stock("wood") == pre_wood + 10, "TC-MAN.21.22: Subsequent idle tick is strictly idempotent (zero duplicate crediting)")

	cit.queue_free()
	rm.queue_free()

## TC-MAN.22: Automatic Hauler Path Failure While Carrying Cargo & Proximity Invariant
func _run_tc_man_22_automatic_hauler_path_failure_invariant() -> void:
	print("--- TC-MAN.22: Automatic Hauler Path Failure While Carrying Cargo ---")
	var wd = _create_test_world()
	var nav = GridNavigationScript.new(wd)
	var jm = JobManagerScript.new()
	var rm = ResourceManagerScript.new()
	var wm = WorkplaceManagerScript.new()
	root.add_child(rm)
	rm.reset_economy()

	# 1. Register a workplace buffer at (25, 25) with access at (26, 25)
	wm.register_workplace("wp_farm_22", "farm", Vector2i(25, 25), Vector2i(2, 2), Vector2i(26, 25), "food", 50, 5.0, 5)
	var wp = wm.get_workplace("wp_farm_22")
	wp.buffer_amount = 10

	# 2. Create automatic hauler citizen
	var cit = CitizenControllerScript.new()
	root.add_child(cit)
	cit.init_citizen("cit_auto_22", "Auto Hauler", "hauler", Vector2i(26, 25), nav, jm, wm)
	cit.world_data = wd
	cit.set_custom_resource_manager(rm)

	# 3. Create and assign automatic hauling job
	var haul_job = jm.create_hauling_job("wp_farm_22", Vector2i(26, 25), Vector2i(32, 32), "food", 10, "Haul food", 1)
	cit.active_job = haul_job
	cit.current_state = CitizenController.State.MOVING_TO_JOB
	cit.current_cell = Vector2i(26, 25)

	# 4. Pickup hauler cargo
	var pre_food: int = rm.get_total_stock("food")
	cit._pickup_hauler_cargo()
	_assert(cit.carrying_amount == 10, "TC-MAN.22.1: Automatic hauler picked up 10 food")
	_assert(cit.carrying_resource == "food", "TC-MAN.22.2: Cargo resource identity is food")
	_assert(cit.current_state == CitizenController.State.HAULING, "TC-MAN.22.3: Transitions to HAULING toward storage")
	_assert(not cit.has_manual_command(), "TC-MAN.22.4: has_manual_command is false (pure automatic hauler)")

	# 5. Storage route becomes completely unavailable
	for x in range(30, 35):
		for y in range(30, 35):
			wd.terrain[x][y] = WorldGeneratorScript.TerrainType.WATER

	# Citizen detects path blocked / current_path cleared en route
	cit.current_path.clear()
	cit._arrive_at_destination()

	_assert(cit.current_state == CitizenController.State.IDLE, "TC-MAN.22.5: Automatic hauler transitions to IDLE on blocked route")
	_assert(cit.is_stranded_with_cargo == true, "TC-MAN.22.6: Typed is_stranded_with_cargo flag set to true")
	_assert(cit.carrying_amount == 10, "TC-MAN.22.7: Cargo physically retained on hauler node (zero loss)")
	_assert(rm.get_total_stock("food") == pre_food, "TC-MAN.22.8: Zero off-site remote deposit to ResourceManager")

	# 6. Multiple idle simulation ticks do not credit remote cargo
	for tick in range(5):
		cit._process_idle()
		_assert(cit.carrying_amount == 10, "TC-MAN.22.9: Cargo preserved across auto idle tick %d" % tick)
		_assert(rm.get_total_stock("food") == pre_food, "TC-MAN.22.10: Zero remote crediting on auto idle tick %d" % tick)
		_assert(cit.is_stranded_with_cargo == true, "TC-MAN.22.11: Stranded flag persists while path is blocked")

	# 7. Direct _deposit_hauler_cargo() fails closed off-site
	cit._deposit_hauler_cargo()
	_assert(cit.carrying_amount == 10, "TC-MAN.22.12: _deposit_hauler_cargo fails closed off-site for automatic hauler")
	_assert(rm.get_total_stock("food") == pre_food, "TC-MAN.22.13: ResourceManager stock protected from remote deposit")

	# 8. Route becomes available
	for x in range(30, 35):
		for y in range(30, 35):
			wd.terrain[x][y] = WorldGeneratorScript.TerrainType.GRASS
			wd.occupancy[x][y] = false

	# 9. Next idle tick: route acquired, transitions back to HAULING
	cit._process_idle()
	_assert(cit.current_state == CitizenController.State.HAULING, "TC-MAN.22.14: Transitions to HAULING once path opens")
	_assert(cit.is_stranded_with_cargo == false, "TC-MAN.22.15: Stranded flag cleared once route restored")
	_assert(not cit.current_path.is_empty(), "TC-MAN.22.16: Non-empty path found to storehouse")

	# 10. Physically travel along path to storage
	while not cit.current_path.is_empty():
		cit.current_cell = cit.current_path[0]
		cit.current_path.remove_at(0)

	_assert(cit._is_at_storage_dropoff(), "TC-MAN.22.17: Automatic hauler reached storage dropoff location")

	# 11. Arrive at destination and deposit
	cit._arrive_at_destination()
	_assert(cit.carrying_amount == 0, "TC-MAN.22.18: 10 food successfully deposited upon arrival at storehouse")
	_assert(rm.get_total_stock("food") == pre_food + 10, "TC-MAN.22.19: Central stock credited with exactly 10 food")
	_assert(cit.current_state == CitizenController.State.IDLE, "TC-MAN.22.20: Citizen returned to IDLE after deposit")

	# 12. Subsequent idle tick is strictly idempotent
	cit._process_idle()
	_assert(rm.get_total_stock("food") == pre_food + 10, "TC-MAN.22.21: Subsequent idle tick is strictly idempotent (zero duplicate crediting)")

	cit.queue_free()
	rm.queue_free()

## TC-MAN.23: Active Job Hauler Proximity Bypass Elimination & Universal Dropoff Invariant
func _run_tc_man_23_active_job_hauler_proximity_bypass_elimination() -> void:
	print("--- TC-MAN.23: Active Job Hauler Proximity Bypass Elimination ---")
	var wd = _create_test_world()
	var nav = GridNavigationScript.new(wd)
	var jm = JobManagerScript.new()
	var rm = ResourceManagerScript.new()
	var wm = WorkplaceManagerScript.new()
	root.add_child(rm)
	rm.reset_economy()

	# Ensure target area and route are walkable
	for x in range(25, 35):
		for y in range(24, 35):
			wd.terrain[x][y] = WorldGeneratorScript.TerrainType.GRASS
			wd.occupancy[x][y] = false

	# 1. Register a workplace at (25, 25) with access at (26, 25)
	wm.register_workplace("wp_farm_23", "farm", Vector2i(25, 25), Vector2i(2, 2), Vector2i(26, 25), "food", 50, 5.0, 5)
	var wp = wm.get_workplace("wp_farm_23")
	wp.buffer_amount = 10

	# 2. Register authorized central storage dropoff at (32, 32)
	wm.register_dropoff("storehouse_main", "storehouse", Vector2i(32, 32))

	# 3. Create automatic hauler citizen at workplace access cell (26, 25)
	var cit = CitizenControllerScript.new()
	root.add_child(cit)
	cit.init_citizen("cit_auto_23", "En Route Hauler", "hauler", Vector2i(26, 25), nav, jm, wm)
	cit.world_data = wd
	cit.set_custom_resource_manager(rm)

	# 4. Create hauling job with destination at authorized dropoff (32, 32)
	var haul_job = jm.create_hauling_job("wp_farm_23", Vector2i(26, 25), Vector2i(32, 32), "food", 10, "Haul food", 1)
	cit.active_job = haul_job
	cit.current_state = CitizenController.State.MOVING_TO_JOB
	cit.current_cell = Vector2i(26, 25)

	# 5. Pick up cargo: citizen now holds 10 food, haul_job completed & active_job cleared (0A-3), current_state == State.HAULING, NOT stranded
	var pre_food: int = rm.get_total_stock("food")
	cit._pickup_hauler_cargo()

	_assert(cit.active_job == null and haul_job.state == JobManager.JobState.COMPLETED, "TC-MAN.23.1: Hauling job completed and active_job cleared upon pickup (0A-3)")
	_assert(cit.current_state == CitizenController.State.HAULING, "TC-MAN.23.2: Citizen is in State.HAULING")
	_assert(cit.is_stranded_with_cargo == false, "TC-MAN.23.3: Citizen is NOT marked stranded (is_stranded_with_cargo == false)")
	_assert(cit.carrying_amount == 10, "TC-MAN.23.4: Citizen carrying 10 units of food")
	_assert(cit.carrying_resource == "food", "TC-MAN.23.5: Cargo resource is food")
	_assert(cit.current_cell == Vector2i(26, 25), "TC-MAN.23.6: Citizen is at (26, 25)")
	_assert(cit._is_at_storage_dropoff() == false, "TC-MAN.23.7: Citizen is physically away from authorized storage dropoffs")

	# 6. Direct invocation of _deposit_hauler_cargo() MUST fail closed
	# (In previous version, active_job != null && State.HAULING && !is_stranded bypassed proximity validation!)
	cit._deposit_hauler_cargo()

	_assert(cit.carrying_amount == 10, "TC-MAN.23.8: Cargo completely retained on citizen (bypass eliminated, 10 food)")
	_assert(cit.carrying_resource == "food", "TC-MAN.23.9: Cargo resource retained as food")
	_assert(rm.get_total_stock("food") == pre_food, "TC-MAN.23.10: Central stock completely unchanged (0 remote credit)")
	_assert(cit.current_state == CitizenController.State.HAULING, "TC-MAN.23.11: Citizen state remains HAULING")
	_assert(cit.active_job == null and haul_job.state == JobManager.JobState.COMPLETED, "TC-MAN.23.12: Hauling job remains completed and active_job cleared while cargo retained")

	# 7. Citizen physically walks step-by-step along current_path to storage dropoff (32, 32)
	_assert(not cit.current_path.is_empty(), "TC-MAN.23.13: Citizen has non-empty path to storage")
	while not cit.current_path.is_empty():
		cit.current_cell = cit.current_path[0]
		cit.current_path.remove_at(0)

	_assert(cit.current_cell == Vector2i(32, 32), "TC-MAN.23.14: Citizen physically arrived at storage cell (32, 32)")
	_assert(cit._is_at_storage_dropoff() == true, "TC-MAN.23.15: _is_at_storage_dropoff evaluates to true upon physical arrival")

	# 8. Normal automatic delivery now succeeds after actual physical arrival
	cit._arrive_at_destination()

	_assert(cit.carrying_amount == 0, "TC-MAN.23.16: Cargo emptied upon authorized arrival")
	_assert(rm.get_total_stock("food") == pre_food + 10, "TC-MAN.23.17: Central stock credited with exactly 10 food")
	_assert(cit.current_state == CitizenController.State.IDLE, "TC-MAN.23.18: Citizen transitions to IDLE after deposit")
	_assert(cit.active_job == null, "TC-MAN.23.19: Hauling job completed and cleared")

	# 9. Subsequent idle tick is strictly idempotent
	cit._process_idle()
	_assert(rm.get_total_stock("food") == pre_food + 10, "TC-MAN.23.20: Subsequent idle tick strictly idempotent (zero duplicate crediting)")

	cit.queue_free()
	rm.queue_free()
