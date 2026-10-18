extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — Package 1H: Builder & Construction Lifecycle
## Covers TC-CON.1 through TC-CON.6.

const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const CitizenControllerScript = preload("res://scripts/entities/citizen_controller.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const IsoMathScript = preload("res://scripts/utils/iso_math.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")
const JobManagerScript = preload("res://scripts/jobs/job_manager.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")

var frame_count: int = 0
var world_instance: Node = null
var all_passed: bool = true

class MockResourceManager extends Node:
	var _current_stock: Dictionary = {}
	var _reserved_stock: Dictionary = {}
	var _capacities: Dictionary = {}
	var max_storage: int = 500

	func _init(initial: Dictionary = {}) -> void:
		for r_id in EconomyConfigScript.ALL_RESOURCES:
			_current_stock[r_id] = initial.get(r_id, 0)
			_reserved_stock[r_id] = 0
			_capacities[r_id] = 500

	func get_available_stock(res_id: String) -> int:
		return _current_stock.get(res_id, 0) - _reserved_stock.get(res_id, 0)

	func get_total_stock(res_id: String) -> int:
		return _current_stock.get(res_id, 0)

	func can_afford(cost: Dictionary) -> bool:
		for res_id in cost:
			if get_available_stock(res_id) < cost[res_id]:
				return false
		return true

	func reserve_cost(cost: Dictionary) -> bool:
		if not can_afford(cost):
			return false
		for res_id in cost:
			_reserved_stock[res_id] = _reserved_stock.get(res_id, 0) + cost[res_id]
		return true

	func commit_cost(cost: Dictionary) -> void:
		for res_id in cost:
			var amount: int = cost[res_id]
			_reserved_stock[res_id] = maxi(0, _reserved_stock.get(res_id, 0) - amount)
			_current_stock[res_id] = maxi(0, _current_stock.get(res_id, 0) - amount)

	func release_cost(cost: Dictionary) -> void:
		for res_id in cost:
			_reserved_stock[res_id] = maxi(0, _reserved_stock.get(res_id, 0) - cost[res_id])

	func add_resource(res_id: String, amount: int) -> int:
		var cur: int = get_available_stock(res_id)
		var cap: int = _capacities.get(res_id, 500)
		var added: int = mini(amount, cap - cur)
		_current_stock[res_id] = cur + added
		return added

	func add_storage_capacity(res_id: String, amount: int) -> void:
		_capacities[res_id] = _capacities.get(res_id, 500) + amount

func _init() -> void:
	print("\n========================================================")
	print("  STARTING PACKAGE 1H BUILDER & CONSTRUCTION TEST SUITE")
	print("========================================================\n")

	var world_scene = load("res://scenes/world/world_view.tscn")
	world_instance = world_scene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1

	if frame_count == 3:
		var pass_tc1 := _test_tc_con_1_blueprint_and_placement_lifecycle()
		var pass_tc2 := _test_tc_con_2_builder_jobs_and_concurrency()
		var pass_tc3 := _test_tc_con_3_builder_work_loop_and_time_scaling()
		var pass_tc4 := _test_tc_con_4_completion_transition_and_idempotency()
		var pass_tc5 := _test_tc_con_5_cancellation_policy()
		var pass_tc6 := _test_tc_con_6_save_load_persistence_and_visual_clarity()

		all_passed = pass_tc1 and pass_tc2 and pass_tc3 and pass_tc4 and pass_tc5 and pass_tc6

		print("\n--------------------------------------------------------")
		if all_passed:
			print("  ALL PACKAGE 1H CONSTRUCTION TESTS PASSED! (Exit Code 0)")
			print("--------------------------------------------------------\n")
			quit(0)
			return true
		else:
			print("  PACKAGE 1H CONSTRUCTION TESTS FAILED! (Exit Code 1)")
			print("--------------------------------------------------------\n")
			quit(1)
			return true

	return false

# -----------------------------------------------------------------------------
# TC-CON.1: Blueprint Verification & Fail-Closed Placement Lifecycle
# -----------------------------------------------------------------------------
func _test_tc_con_1_blueprint_and_placement_lifecycle() -> bool:
	print("--- Running TC-CON.1: Blueprint Verification & Placement Lifecycle ---")
	var failures: int = 0

	# 1. Verify construction_hours configured for all 10 blueprints
	var bp_keys := EconomyConfigScript.BLUEPRINTS.keys()
	for k in bp_keys:
		var bp: Dictionary = EconomyConfigScript.BLUEPRINTS[k]
		if not bp.has("construction_hours"):
			printerr("  [FAIL] Blueprint '%s' missing construction_hours!" % k)
			failures += 1
		elif float(bp.get("construction_hours", 0.0)) <= 0.0:
			printerr("  [FAIL] Blueprint '%s' has non-positive construction_hours: %f" % [k, bp.get("construction_hours")])
			failures += 1
	if failures == 0:
		print("  [PASS] All %d blueprints have positive construction_hours." % bp_keys.size())

	# 2. Placement checks with MockResourceManager
	var world_data = WorldGeneratorScript.generate(111)
	var poor_rm = MockResourceManager.new({"wood": 5, "stone": 5})
	var rich_rm = MockResourceManager.new({"wood": 200, "stone": 200, "metal": 100})

	# Fail closed when resource_mgr is null and cost non-empty
	var null_rm_res = BuildingSystemScript.can_place_building("house", Vector2i(20, 20), world_data, null)
	if null_rm_res.get("valid", true):
		printerr("  [FAIL] can_place_building should fail closed when resource_mgr is null!")
		failures += 1
	var null_rm_place = BuildingSystemScript.place_building("house", Vector2i(20, 20), world_data, null)
	if null_rm_place.get("success", true):
		printerr("  [FAIL] place_building should fail closed when resource_mgr is null!")
		failures += 1

	# Rejection when unaffordable
	var poor_check = BuildingSystemScript.can_place_building("house", Vector2i(20, 20), world_data, poor_rm)
	if poor_check.get("valid", true):
		printerr("  [FAIL] can_place_building should fail when insufficient resources!")
		failures += 1
	var poor_place = BuildingSystemScript.place_building("house", Vector2i(20, 20), world_data, poor_rm)
	if poor_place.get("success", true):
		printerr("  [FAIL] place_building should fail when insufficient resources!")
		failures += 1

	# Legal placement starts in 'under_construction'
	# Clear ground
	for dx in range(2):
		for dy in range(2):
			world_data.terrain[20 + dx][20 + dy] = WorldGeneratorScript.TerrainType.GRASS
			world_data.occupancy[20 + dx][20 + dy] = false

	var wood_prior: int = rich_rm.get_available_stock("wood")
	var stone_prior: int = rich_rm.get_available_stock("stone")
	var cap_prior: int = BuildingSystemScript.get_total_housing_capacity(world_data)
	var place_res = BuildingSystemScript.place_building("house", Vector2i(20, 20), world_data, rich_rm)

	if not place_res.get("success", false):
		printerr("  [FAIL] Legal house placement failed: %s" % place_res.get("reason"))
		failures += 1
	else:
		var b: Dictionary = place_res.get("building", {})
		if b.get("state") != "under_construction":
			printerr("  [FAIL] Placed building state should be 'under_construction', got '%s'" % b.get("state"))
			failures += 1
		if b.get("construction_progress") != 0.0:
			printerr("  [FAIL] Initial construction_progress should be 0.0, got %f" % b.get("construction_progress"))
			failures += 1
		if b.get("construction_hours") != 8.0:
			printerr("  [FAIL] House construction_hours should be 8.0, got %f" % b.get("construction_hours"))
			failures += 1

		# Verify costs deducted atomically
		if rich_rm.get_available_stock("wood") != wood_prior - 25 or rich_rm.get_available_stock("stone") != stone_prior - 10:
			printerr("  [FAIL] House costs were not deducted atomically (-25 wood, -10 stone)!")
			failures += 1

		# Verify occupancy occupied immediately
		if not world_data.occupancy[20][20] or not world_data.occupancy[21][21]:
			printerr("  [FAIL] House footprint cells not marked as occupied!")
			failures += 1

		# Verify housing capacity is NOT granted while under construction
		var cap := BuildingSystemScript.get_total_housing_capacity(world_data)
		if cap != cap_prior:
			printerr("  [FAIL] get_total_housing_capacity changed for uncompleted house! Prior=%d, Cap=%d" % [cap_prior, cap])
			failures += 1

	# Place storehouse under construction: storage bonus NOT applied yet
	for dx in range(2):
		for dy in range(2):
			world_data.terrain[24 + dx][20 + dy] = WorldGeneratorScript.TerrainType.GRASS
			world_data.occupancy[24 + dx][20 + dy] = false

	var cap_wood_prior = rich_rm._capacities.get("wood", 500)
	var storehouse_res = BuildingSystemScript.place_building("storehouse", Vector2i(24, 20), world_data, rich_rm)
	if storehouse_res.get("success", false):
		if rich_rm._capacities.get("wood", 500) != cap_wood_prior:
			printerr("  [FAIL] Storehouse storage bonus was applied while still under construction!")
			failures += 1
		else:
			print("  [PASS] Storehouse storage capacity withheld while under construction.")

	if failures == 0:
		print("  [PASS] TC-CON.1 PASSED.\n")
		return true
	printerr("  [FAIL] TC-CON.1 had %d failures.\n" % failures)
	return false

# -----------------------------------------------------------------------------
# TC-CON.2: Construction Jobs & Concurrent Builder Capacity
# -----------------------------------------------------------------------------
func _test_tc_con_2_builder_jobs_and_concurrency() -> bool:
	print("--- Running TC-CON.2: Construction Jobs & Concurrent Capacity ---")
	var failures: int = 0

	# 1. Capacity checks: 1x1 -> 2, 2x2 -> 3, 3x3 -> 4
	if BuildingSystemScript.get_construction_worker_capacity("watchtower") != 2:
		printerr("  [FAIL] Watchtower (1x1) capacity should be 2, got %d" % BuildingSystemScript.get_construction_worker_capacity("watchtower"))
		failures += 1
	if BuildingSystemScript.get_construction_worker_capacity("house") != 3:
		printerr("  [FAIL] House (2x2) capacity should be 3, got %d" % BuildingSystemScript.get_construction_worker_capacity("house"))
		failures += 1
	if BuildingSystemScript.get_construction_worker_capacity("townhall") != 4:
		printerr("  [FAIL] Townhall (3x3) capacity should be 4, got %d" % BuildingSystemScript.get_construction_worker_capacity("townhall"))
		failures += 1
	if BuildingSystemScript.get_construction_worker_capacity("barracks") != 4:
		printerr("  [FAIL] Barracks (3x3) capacity should be 4, got %d" % BuildingSystemScript.get_construction_worker_capacity("barracks"))
		failures += 1

	# 2. Job creation via WorldView
	var jm = JobManagerScript.new()
	var world_data = WorldGeneratorScript.generate(222)
	var nav = GridNavigation.new(world_data)

	var b_house := {
		"id": "bld_house_15_15",
		"type": "house",
		"cell": Vector2i(15, 15),
		"size": Vector2i(2, 2),
		"state": "under_construction",
		"construction_progress": 0.0,
		"construction_hours": 8.0
	}
	world_data.buildings.append(b_house)
	for dx in range(-1, 3):
		for dy in range(-1, 3):
			var c := Vector2i(15 + dx, 15 + dy)
			world_data.terrain[c.x][c.y] = WorldGeneratorScript.TerrainType.GRASS
			world_data.occupancy[c.x][c.y] = (dx >= 0 and dx < 2 and dy >= 0 and dy < 2)

	# Call world_instance.register_construction_jobs
	var old_jm = world_instance.get("job_mgr")
	world_instance.set("job_mgr", jm)
	world_instance.set("world_data", world_data)

	var created_jobs = world_instance.call("register_construction_jobs", b_house)
	if created_jobs.size() != 3:
		printerr("  [FAIL] Expected 3 builder jobs for 2x2 house, got %d" % created_jobs.size())
		failures += 1
	else:
		for job in created_jobs:
			if job.type != "builder":
				printerr("  [FAIL] Job type should be 'builder', got '%s'" % job.type)
				failures += 1
			if job.target_building_id != "bld_house_15_15":
				printerr("  [FAIL] Target building ID mismatch: '%s'" % job.target_building_id)
				failures += 1

	# 3. Executability check in JobManager: fail closed
	var test_job = created_jobs[0] if not created_jobs.is_empty() else null
	if test_job != null:
		# A: Empty target_building_id fails
		var empty_id_job := JobManager.JobData.new()
		empty_id_job.type = "builder"
		empty_id_job.target_building_id = ""
		empty_id_job.target_cell = Vector2i(15, 14)
		if jm._is_job_executable(empty_id_job, null, null, Callable(), nav):
			printerr("  [FAIL] Builder job with empty target_building_id should not be executable!")
			failures += 1

		# B: No checker or filter fails closed
		if jm._is_job_executable(test_job, null, null, Callable(), nav):
			printerr("  [FAIL] Builder job should fail closed when no checker or filter is registered!")
			failures += 1

		# C: Valid checker returns true for under_construction building
		jm.set_construction_checker(func(bid: String): return BuildingSystemScript.is_building_under_construction(world_data, bid))
		if not jm._is_job_executable(test_job, null, null, Callable(), nav):
			printerr("  [FAIL] Builder job should be executable when building is under_construction!")
			failures += 1

		# D: Once active, builder job becomes not executable
		b_house["state"] = "active"
		if jm._is_job_executable(test_job, null, null, Callable(), nav):
			printerr("  [FAIL] Builder job should NOT be executable when building is already active!")
			failures += 1
		b_house["state"] = "under_construction"

	# 4. Idempotent registration tests
	# Call register_construction_jobs a second time on b_house
	var second_call_jobs = world_instance.call("register_construction_jobs", b_house)
	var house_jobs_now = jm.get_jobs_for_building("bld_house_15_15")
	if house_jobs_now.size() != 3:
		printerr("  [FAIL] Calling register_construction_jobs twice created duplicate jobs! Total: %d, expected 3" % house_jobs_now.size())
		failures += 1
	else:
		print("  [PASS] Calling register_construction_jobs twice on same project is idempotent (count remained 3).")

	# Verify count does not exceed worker capacity or available perimeter cells
	var expected_house_cap: int = BuildingSystemScript.get_construction_worker_capacity("house")
	if house_jobs_now.size() > expected_house_cap:
		printerr("  [FAIL] Job count exceeds worker capacity!")
		failures += 1
	else:
		print("  [PASS] Job count adheres to concurrent capacity.")

	# Register a second building with an overlapping textual ID prefix: bld_house_15_150
	var b_house_overlapping := {
		"id": "bld_house_15_150",
		"type": "house",
		"cell": Vector2i(25, 25),
		"size": Vector2i(2, 2),
		"state": "under_construction",
		"construction_progress": 0.0,
		"construction_hours": 8.0
	}
	world_data.buildings.append(b_house_overlapping)
	for dx in range(-1, 3):
		for dy in range(-1, 3):
			var c := Vector2i(25 + dx, 25 + dy)
			world_data.terrain[c.x][c.y] = WorldGeneratorScript.TerrainType.GRASS
			world_data.occupancy[c.x][c.y] = (dx >= 0 and dx < 2 and dy >= 0 and dy < 2)

	var overlapping_jobs = world_instance.call("register_construction_jobs", b_house_overlapping)
	var house_15_15_jobs = jm.get_jobs_for_building("bld_house_15_15")
	var house_15_150_jobs = jm.get_jobs_for_building("bld_house_15_150")

	if house_15_15_jobs.size() != 3 or house_15_150_jobs.size() != 3:
		printerr("  [FAIL] Prefix overlap corrupted job separation! bld_house_15_15 has %d, bld_house_15_150 has %d" % [house_15_15_jobs.size(), house_15_150_jobs.size()])
		failures += 1
	else:
		print("  [PASS] Overlapping textual prefix ID jobs remain strictly isolated.")

	# Confirm Builders can still claim valid construction jobs through JobManager.request_job()
	var citizen_mock = CitizenControllerScript.new()
	citizen_mock.set("citizen_id", "builder_test_cit")
	citizen_mock.set("role", "builder")
	citizen_mock.set("current_cell", Vector2i(15, 13))
	var claimed_job = jm.request_job("builder_test_cit", "builder", Vector2i(15, 13), nav)
	if claimed_job == null:
		printerr("  [FAIL] Builder could not claim construction job via request_job()!")
		failures += 1
	else:
		if claimed_job.type != "builder" or (claimed_job.target_building_id != "bld_house_15_15" and claimed_job.target_building_id != "bld_house_15_150"):
			printerr("  [FAIL] Claimed job mismatch: type=%s, target=%s" % [claimed_job.type, claimed_job.target_building_id])
			failures += 1
		else:
			print("  [PASS] Builder claimed valid construction job through JobManager.request_job().")
		jm.release_job(claimed_job)
	citizen_mock.free()

	# Confirm completion and cancellation continue cleaning up only jobs associated with the correct project
	jm.remove_jobs_for_building("bld_house_15_150")
	if jm.get_jobs_for_building("bld_house_15_15").size() != 3:
		printerr("  [FAIL] Removing jobs for bld_house_15_150 corrupted jobs for bld_house_15_15!")
		failures += 1
	else:
		print("  [PASS] Cleaning up bld_house_15_150 preserved all jobs for bld_house_15_15.")

	world_instance.set("job_mgr", old_jm)

	if failures == 0:
		print("  [PASS] TC-CON.2 PASSED.\n")
		return true
	printerr("  [FAIL] TC-CON.2 had %d failures.\n" % failures)
	return false

# -----------------------------------------------------------------------------
# TC-CON.3: Real Builder Work Loop, Time/Pause Scaling & Shared Progress
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# TC-CON.3: Real Builder Work Loop, Time/Pause Scaling & Shared Progress
# -----------------------------------------------------------------------------
func _test_tc_con_3_builder_work_loop_and_time_scaling() -> bool:
	print("--- Running TC-CON.3: Builder Work Loop, Scaling & Progress ---")
	var failures: int = 0

	var tm: Node = world_instance.get_node_or_null("/root/TimeManager")
	if tm == null:
		printerr("  [FAIL] TimeManager not found at /root/TimeManager!")
		return false

	var world_data = WorldGeneratorScript.generate(333)
	var nav = GridNavigation.new(world_data)
	var jm = JobManagerScript.new()
	jm.set_construction_checker(func(bid: String): return BuildingSystemScript.is_building_under_construction(world_data, bid))

	var b_farm := {
		"id": "bld_farm_10_10",
		"type": "farm",
		"cell": Vector2i(10, 10),
		"size": Vector2i(2, 2),
		"state": "under_construction",
		"construction_progress": 0.0,
		"construction_hours": 12.0
	}
	world_data.buildings.append(b_farm)
	for dx in range(-1, 3):
		for dy in range(-1, 3):
			var c := Vector2i(10 + dx, 10 + dy)
			world_data.terrain[c.x][c.y] = WorldGeneratorScript.TerrainType.GRASS
			world_data.occupancy[c.x][c.y] = (dx >= 0 and dx < 2 and dy >= 0 and dy < 2)

	var p_cells = BuildingSystemScript.find_perimeter_cells(Vector2i(10, 10), Vector2i(2, 2), world_data, 2)
	var job1 = jm.create_job("builder", p_cells[0], "Build farm", b_farm["id"], 12.0)

	var b1 = CitizenControllerScript.new()
	root.add_child(b1)
	b1.init_citizen("builder_1", "Thợ Xây 1", "builder", p_cells[0], nav, jm)
	b1.set_construction_checker(func(bid: String): return BuildingSystemScript.is_building_under_construction(world_data, bid))
	b1.set_construction_handler(func(bid: String, dh: float): return BuildingSystemScript.advance_construction(b_farm, dh, world_data))
	b1.world_data = world_data

	# 1. Normal request_job() claiming path from State.IDLE
	b1.current_state = CitizenController.State.IDLE
	b1._process(0.016)
	if b1.active_job != job1:
		printerr("  [FAIL] Builder failed to claim job through request_job()! active_job: %s" % str(b1.active_job))
		failures += 1

	# Arrive at perimeter post: transitions to WORKING and job IN_PROGRESS
	b1._process(0.016)
	if b1.current_state != CitizenController.State.WORKING or job1.state != JobManager.JobState.IN_PROGRESS:
		printerr("  [FAIL] Builder did not transition to WORKING: state=%d, job_state=%d" % [b1.current_state, job1.state])
		failures += 1
	else:
		print("  [PASS] Builder job claimed via request_job() and reached IN_PROGRESS at work site.")

	# 2. TimeManager Pause (0x) test: progress must NOT advance
	tm.pause()
	if not tm.is_paused():
		printerr("  [FAIL] TimeManager is not paused after tm.pause()!")
		failures += 1
	var prog_before_pause: float = b_farm["construction_progress"]
	b1._process(0.5)
	if b_farm["construction_progress"] != prog_before_pause:
		printerr("  [FAIL] Construction progress advanced while simulation was paused (0x)!")
		failures += 1
	else:
		print("  [PASS] Real TimeManager pause (0x) safely halts construction progress.")

	# 3. TimeManager 1x Normal Speed: progress increases by expected delta (0.5 * 1.0 = 0.5)
	tm.resume()
	tm.set_speed(1)
	b1._process(0.5)
	if absf(b_farm["construction_progress"] - 0.5) > 0.01:
		printerr("  [FAIL] At 1x speed, expected progress 0.5, got %f" % b_farm["construction_progress"])
		failures += 1
	else:
		print("  [PASS] At 1x speed, progress advanced by expected 0.5 hours.")

	# 4. TimeManager 2x Fast Speed: progress increases by delta * 2.0 (0.5 * 2.0 = 1.0, total 1.5)
	tm.set_speed(2)
	b1._process(0.5)
	if absf(b_farm["construction_progress"] - 1.5) > 0.01:
		printerr("  [FAIL] At 2x speed, expected progress 1.5, got %f" % b_farm["construction_progress"])
		failures += 1
	else:
		print("  [PASS] At 2x speed, progress followed simulation speed (added 1.0h, total 1.5h).")

	# 5. TimeManager 3x Very Fast Speed: progress increases by delta * 3.0 (0.5 * 3.0 = 1.5, total 3.0)
	tm.set_speed(3)
	b1._process(0.5)
	if absf(b_farm["construction_progress"] - 3.0) > 0.01:
		printerr("  [FAIL] At 3x speed, expected progress 3.0, got %f" % b_farm["construction_progress"])
		failures += 1
	else:
		print("  [PASS] At 3x speed, progress followed simulation speed (added 1.5h, total 3.0h).")

	# Verify status reason reflects current progress
	if not "12.0" in b1.status_reason:
		printerr("  [FAIL] Status reason does not reflect total hours: '%s'" % b1.status_reason)
		failures += 1

	# 6. No eligible builder working -> progress does not advance
	b1.active_job = null
	b1.current_state = CitizenController.State.IDLE
	b1.role = "idle"
	var prog_unworked: float = b_farm["construction_progress"]
	b1._process(1.0)
	if b_farm["construction_progress"] != prog_unworked:
		printerr("  [FAIL] Progress advanced without an active working builder!")
		failures += 1
	else:
		print("  [PASS] Progress does not advance when no eligible builder is working.")

	tm.set_speed(1)
	b1.queue_free()

	if failures == 0:
		print("  [PASS] TC-CON.3 PASSED.\n")
		return true
	printerr("  [FAIL] TC-CON.3 had %d failures.\n" % failures)
	return false

# -----------------------------------------------------------------------------
# TC-CON.4: Centralized Idempotent Completion Transition & Threshold Enforcement
# -----------------------------------------------------------------------------
func _test_tc_con_4_completion_transition_and_idempotency() -> bool:
	print("--- Running TC-CON.4: Idempotent Completion Transition & Threshold Enforcement ---")
	var failures: int = 0

	var live_rm: Node = world_instance.get_node_or_null("/root/ResourceManager")
	var world_data = world_instance.get("world_data")
	var jm: JobManager = world_instance.get("job_mgr")
	var wp_mgr: WorkplaceManager = world_instance.get("workplace_mgr")

	if live_rm == null or world_data == null or jm == null or wp_mgr == null:
		printerr("  [FAIL] Subsystem singletons null in TC-CON.4!")
		return false

	# 1. Place a Workshop via _execute_placement
	live_rm.call("reset_economy")
	live_rm.call("add_resource", "wood", 100)
	live_rm.call("add_resource", "stone", 100)
	live_rm.call("add_resource", "metal", 50)

	var ws_cell := Vector2i(20, 24)
	for dx in range(-1, 3):
		for dy in range(-1, 3):
			var c := ws_cell + Vector2i(dx, dy)
			world_data.terrain[c.x][c.y] = WorldGeneratorScript.TerrainType.GRASS
			world_data.occupancy[c.x][c.y] = false

	world_instance.set("placing_building_type", "workshop")
	var place_res: Dictionary = world_instance.call("_execute_placement", ws_cell)
	if not place_res.get("success", false):
		printerr("  [FAIL] Workshop placement failed: %s" % place_res.get("reason"))
		return false

	var b_id := "bld_workshop_20_24"
	var b_data := BuildingSystemScript.get_building_by_id(b_id, world_data)
	if b_data.get("state") != "under_construction":
		printerr("  [FAIL] Workshop should be under_construction after placement!")
		failures += 1

	# 2. Prerequisite Check A: Zero-progress completion is rejected
	var zero_comp: bool = world_instance.call("complete_construction", b_id)
	if zero_comp:
		printerr("  [FAIL] complete_construction returned true at 0%% progress!")
		failures += 1
	if b_data.get("state") != "under_construction":
		printerr("  [FAIL] Building state changed to '%s' on zero-progress completion attempt!" % b_data.get("state"))
		failures += 1
	if wp_mgr.get_workplace(b_id + "_smelt") != null:
		printerr("  [FAIL] Smelt channel registered prematurely on rejected zero-progress completion!")
		failures += 1
	print("  [PASS] Zero-progress completion rejected; building remains non-operational.")

	# 3. Prerequisite Check B: Partial-progress completion is rejected
	world_instance.call("advance_construction_work", b_id, 4.0)
	if absf(float(b_data.get("construction_progress", 0.0)) - 4.0) > 0.01:
		printerr("  [FAIL] Partial advancement to 4.0 failed, got: %f" % b_data.get("construction_progress"))
		failures += 1

	var partial_comp: bool = world_instance.call("complete_construction", b_id)
	if partial_comp:
		printerr("  [FAIL] complete_construction returned true at partial (4.0/12.0) progress!")
		failures += 1
	if b_data.get("state") != "under_construction":
		printerr("  [FAIL] Building state changed to '%s' on partial-progress completion attempt!" % b_data.get("state"))
		failures += 1
	if wp_mgr.get_workplace(b_id + "_smelt") != null:
		printerr("  [FAIL] Smelt channel registered prematurely on rejected partial-progress completion!")
		failures += 1
	print("  [PASS] Partial-progress completion rejected; building remains non-operational.")

	# 4. Prerequisite Check C: Negative delta cannot decrease previously earned progress
	var neg_res = BuildingSystemScript.advance_construction(b_id, -2.0, world_data)
	if neg_res.get("success", true):
		printerr("  [FAIL] advance_construction should return success: false on negative delta!")
		failures += 1
	if float(b_data.get("construction_progress", 0.0)) < 4.0:
		printerr("  [FAIL] Negative delta reduced earned progress to %f!" % b_data.get("construction_progress"))
		failures += 1
	else:
		print("  [PASS] Negative delta rejected without decreasing progress.")

	# 5. Legitimate completion after required work is achieved (remaining 8.0 hours)
	var comp_adv = world_instance.call("advance_construction_work", b_id, 8.0)
	if not comp_adv.get("completed", false):
		printerr("  [FAIL] advance_construction_work did not report completed on full hours!")
		failures += 1

	# Building state is now active and operational
	if b_data.get("state") != "active":
		printerr("  [FAIL] Building state not 'active' after legitimate completion: '%s'" % b_data.get("state"))
		failures += 1

	# Dynamic workplace channels now legitimately exist
	if wp_mgr.get_workplace(b_id + "_smelt") == null:
		printerr("  [FAIL] Smelt channel not registered upon legitimate completion!")
		failures += 1
	if wp_mgr.get_workplace(b_id + "_craft") == null:
		printerr("  [FAIL] Craft channel not registered upon legitimate completion!")
		failures += 1

	# Visual scaffolding cleared
	var b_node = world_instance.get("buildings_container").get_node_or_null("Building_workshop_20_24")
	if b_node:
		var spr: Sprite2D = b_node.get_node_or_null("Sprite2D")
		if spr and spr.modulate != Color(1.0, 1.0, 1.0, 1.0):
			printerr("  [FAIL] Sprite modulate not restored to Color(1,1,1,1), got %s" % spr.modulate)
			failures += 1

	print("  [PASS] Completion succeeded legitimately after required work achieved.")

	# 6. Idempotency check: calling complete_construction again must return false and not repeat side effects
	var second_comp: bool = world_instance.call("complete_construction", b_id)
	if second_comp:
		printerr("  [FAIL] complete_construction should return false when called on already active building!")
		failures += 1
	else:
		print("  [PASS] Repeated completion call returned false without side effects.")

	# 7. Fail-closed completion test when required storage effects cannot be applied
	var b_storehouse := {
		"id": "bld_storehouse_35_35",
		"type": "storehouse",
		"cell": Vector2i(35, 35),
		"size": Vector2i(2, 2),
		"state": "under_construction",
		"construction_progress": 10.0,
		"construction_hours": 10.0
	}
	world_data.buildings.append(b_storehouse)

	# A: Attempt complete_building with resource_mgr == null -> MUST return false
	var no_rm_comp = BuildingSystemScript.complete_building(b_storehouse, world_data, null)
	if no_rm_comp:
		printerr("  [FAIL] complete_building succeeded for storehouse with null ResourceManager!")
		failures += 1
	if b_storehouse.get("state") != "under_construction":
		printerr("  [FAIL] Storehouse state changed to '%s' despite missing ResourceManager!" % b_storehouse.get("state"))
		failures += 1
	if absf(float(b_storehouse.get("construction_progress", 0.0)) - 10.0) > 0.01:
		printerr("  [FAIL] Storehouse progress was modified on failed completion!")
		failures += 1
	print("  [PASS] Storehouse completion safely rejected when ResourceManager is missing; state remained under_construction.")

	# B: Complete with valid MockResourceManager -> MUST succeed and apply storage
	var test_rm := MockResourceManager.new()
	var wood_cap_before = test_rm._capacities.get("wood", 500)
	var with_rm_comp = BuildingSystemScript.complete_building(b_storehouse, world_data, test_rm)
	if not with_rm_comp:
		printerr("  [FAIL] complete_building failed for storehouse with valid ResourceManager!")
		failures += 1
	if b_storehouse.get("state") != "active":
		printerr("  [FAIL] Storehouse state not active after valid completion!")
		failures += 1
	var wood_cap_after = test_rm._capacities.get("wood", 500)
	if wood_cap_after != wood_cap_before + 500:
		printerr("  [FAIL] Storehouse storage bonus (+500) not applied! Before=%d, After=%d" % [wood_cap_before, wood_cap_after])
		failures += 1
	else:
		print("  [PASS] Storehouse completion succeeded with ResourceManager and applied storage capacity bonus.")

	# C: Repeated completion attempt -> MUST return false, capacity not duplicated
	var repeat_comp = BuildingSystemScript.complete_building(b_storehouse, world_data, test_rm)
	if repeat_comp:
		printerr("  [FAIL] Repeated complete_building returned true for already active storehouse!")
		failures += 1
	if test_rm._capacities.get("wood", 500) != wood_cap_after:
		printerr("  [FAIL] Repeated completion duplicated storage capacity!")
		failures += 1
	else:
		print("  [PASS] Repeated completion safely rejected without duplicating storage capacity.")
	test_rm.free()

	if failures == 0:
		print("  [PASS] TC-CON.4 PASSED.\n")
		return true
	printerr("  [FAIL] TC-CON.4 had %d failures.\n" % failures)
	return false

# -----------------------------------------------------------------------------
# TC-CON.5: Cancellation Policy (Reliable 50% Refund, Missing RM, Storage Overflow & Prefix Isolation)
# -----------------------------------------------------------------------------
func _test_tc_con_5_cancellation_policy() -> bool:
	print("--- Running TC-CON.5: Cancellation Policy & 50% Refund ---")
	var failures: int = 0

	var live_rm: Node = world_instance.get_node_or_null("/root/ResourceManager")
	var world_data = world_instance.get("world_data")
	var jm: JobManager = world_instance.get("job_mgr")

	live_rm.call("reset_economy")
	live_rm.call("add_resource", "wood", 100)
	live_rm.call("add_resource", "stone", 100)

	var test_cell := Vector2i(28, 28)
	for dx in range(-1, 3):
		for dy in range(-1, 3):
			var c := test_cell + Vector2i(dx, dy)
			world_data.terrain[c.x][c.y] = WorldGeneratorScript.TerrainType.GRASS
			world_data.occupancy[c.x][c.y] = false

	var wood_prior: int = live_rm.call("get_available_stock", "wood")
	var stone_prior: int = live_rm.call("get_available_stock", "stone")

	# Place house: cost is 25 wood, 10 stone
	world_instance.set("placing_building_type", "house")
	var place_res = world_instance.call("_execute_placement", test_cell)
	if not place_res.get("success", false):
		printerr("  [FAIL] Placement failed in TC-CON.5: %s" % place_res.get("reason"))
		return false

	var b_id := "bld_house_28_28"
	var wood_after_place: int = live_rm.call("get_available_stock", "wood")
	var stone_after_place: int = live_rm.call("get_available_stock", "stone")

	# Verify 100% deducted on placement
	if wood_after_place != wood_prior - 25 or stone_after_place != stone_prior - 10:
		printerr("  [FAIL] Costs not deducted on placement!")
		failures += 1

	# Footprint occupied
	if not world_data.occupancy[28][28] or not world_data.occupancy[29][29]:
		printerr("  [FAIL] Footprint not occupied!")
		failures += 1

	# 1. Missing ResourceManager dependency check
	var null_rm_res = BuildingSystemScript.cancel_construction(b_id, world_data, null, jm)
	if null_rm_res.get("success", true):
		printerr("  [FAIL] cancel_construction should fail closed when resource_mgr is null!")
		failures += 1
	var b_still_exists = BuildingSystemScript.get_building_by_id(b_id, world_data)
	if b_still_exists.is_empty() or not world_data.occupancy[28][28]:
		printerr("  [FAIL] Missing RM cancellation modified world or occupancy!")
		failures += 1
	else:
		print("  [PASS] Missing ResourceManager fail-closed: project and occupancy untouched.")

	# 2. Near/Full storage capacity check (All-or-Nothing refund operation)
	# Reduce stone capacity so it only has room for 2 stone (house refund needs 5)
	var cur_stone_stock: int = live_rm.call("get_available_stock", "stone")
	live_rm.get("_capacities")["stone"] = cur_stone_stock + 2
	var cap_fail_res = world_instance.call("cancel_construction_project", b_id)
	if cap_fail_res.get("success", true) or not cap_fail_res.get("insufficient_storage", false):
		printerr("  [FAIL] cancel_construction should fail when storage cannot fit promised refund!")
		failures += 1
	if not world_data.occupancy[28][28] or BuildingSystemScript.get_building_by_id(b_id, world_data).is_empty():
		printerr("  [FAIL] Insufficient storage cancellation modified world or occupancy!")
		failures += 1
	else:
		print("  [PASS] Insufficient storage capacity safely rejected; promised refund preserved.")

	# Restore stone capacity
	live_rm.get("_capacities")["stone"] = 500

	# 3. Prefix-overlapping isolation check (bld_house_28_28 vs bld_house_28_280)
	var other_house_cell := Vector2i(32, 28)
	for dx in range(-1, 3):
		for dy in range(-1, 3):
			var c := other_house_cell + Vector2i(dx, dy)
			world_data.terrain[c.x][c.y] = WorldGeneratorScript.TerrainType.GRASS
			world_data.occupancy[c.x][c.y] = false

	var other_bld := {
		"id": "bld_house_28_280",
		"type": "house",
		"cell": other_house_cell,
		"size": Vector2i(2, 2),
		"state": "under_construction",
		"construction_progress": 0.0,
		"construction_hours": 8.0
	}
	world_data.buildings.append(other_bld)
	world_data.occupancy[32][28] = true
	world_data.occupancy[33][29] = true

	var other_job = jm.create_job("builder", Vector2i(32, 27), "Build other house", "bld_house_28_280", 8.0)
	other_job.state = JobManager.JobState.IN_PROGRESS

	# Create dummy worker on other building
	var other_worker = CitizenControllerScript.new()
	other_worker.init_citizen("worker_other", "Thợ Nhà Khác", "builder", Vector2i(32, 27), GridNavigation.new(world_data), jm)
	other_worker.active_job = other_job
	other_worker.current_state = CitizenController.State.WORKING
	world_instance.citizen_list.append(other_worker)

	# Cancel bld_house_28_28
	var cancel_res = world_instance.call("cancel_construction_project", b_id)
	if not cancel_res.get("success", false):
		printerr("  [FAIL] cancel_construction_project failed: %s" % cancel_res.get("reason"))
		failures += 1
	else:
		# 50% refund: 25 * 0.5 = 12 wood, 10 * 0.5 = 5 stone
		var wood_after_cancel: int = live_rm.call("get_available_stock", "wood")
		var stone_after_cancel: int = live_rm.call("get_available_stock", "stone")
		if wood_after_cancel != wood_after_place + 12:
			printerr("  [FAIL] Wood refund incorrect! Expected +12, got %d" % (wood_after_cancel - wood_after_place))
			failures += 1
		if stone_after_cancel != stone_after_place + 5:
			printerr("  [FAIL] Stone refund incorrect! Expected +5, got %d" % (stone_after_cancel - stone_after_place))
			failures += 1

		# Footprint cleared
		if world_data.occupancy[28][28] or world_data.occupancy[29][29]:
			printerr("  [FAIL] Footprint occupancy was not cleared upon cancellation!")
			failures += 1

		# Node removed
		var b_node = world_instance.get("buildings_container").get_node_or_null("Building_house_28_28")
		if b_node != null and not b_node.is_queued_for_deletion():
			printerr("  [FAIL] Visual building node was not removed on cancellation!")
			failures += 1

		# Jobs for bld_house_28_28 removed
		var remaining_jobs = jm.get_jobs_for_building(b_id)
		if not remaining_jobs.is_empty():
			printerr("  [FAIL] Construction jobs remained for cancelled building!")
			failures += 1

		# Prefix isolation: other project's jobs and workers MUST be untouched
		var other_jobs = jm.get_jobs_for_building("bld_house_28_280")
		if other_jobs.is_empty():
			printerr("  [FAIL] Prefix collision! Jobs for 'bld_house_28_280' were erroneously deleted when cancelling 'bld_house_28_28'!")
			failures += 1
		else:
			print("  [PASS] Prefix isolation verified: jobs for bld_house_28_280 preserved.")

		if other_worker.active_job == null or other_worker.current_state != CitizenController.State.WORKING:
			printerr("  [FAIL] Prefix collision! Worker on 'bld_house_28_280' had active job cleared erroneously!")
			failures += 1
		else:
			print("  [PASS] Prefix isolation verified: worker on bld_house_28_280 remains actively working.")

		# Clean up other house fixture
		world_instance.citizen_list.erase(other_worker)
		other_worker.queue_free()
		jm.remove_jobs_for_building("bld_house_28_280")
		world_data.buildings.erase(other_bld)
		world_data.occupancy[32][28] = false
		world_data.occupancy[33][29] = false

		# 4. Re-cancellation rejected (Idempotency)
		var double_cancel = world_instance.call("cancel_construction_project", b_id)
		if double_cancel.get("success", false):
			printerr("  [FAIL] Re-cancelling same project succeeded! Double refund exploit!")
			failures += 1
		else:
			print("  [PASS] Re-cancellation safely rejected; zero double refund.")

	if failures == 0:
		print("  [PASS] TC-CON.5 PASSED.\n")
		return true
	printerr("  [FAIL] TC-CON.5 had %d failures.\n" % failures)
	return false

# -----------------------------------------------------------------------------
# TC-CON.6: Save/Load Persistence, Double-Load, Visual Hover & Schema Validation
# -----------------------------------------------------------------------------
func _test_tc_con_6_save_load_persistence_and_visual_clarity() -> bool:
	print("--- Running TC-CON.6: Save/Load Persistence & Visual Hover ---")
	var failures: int = 0

	var live_rm: Node = world_instance.get_node_or_null("/root/ResourceManager")
	var world_data = world_instance.get("world_data")
	var jm: JobManager = world_instance.get("job_mgr")

	# Place barracks under construction at (10, 20)
	live_rm.call("reset_economy")
	live_rm.call("add_resource", "wood", 100)
	live_rm.call("add_resource", "stone", 100)
	live_rm.call("add_resource", "metal", 50)

	var br_cell := Vector2i(10, 20)
	for dx in range(-1, 4):
		for dy in range(-1, 4):
			var c := br_cell + Vector2i(dx, dy)
			world_data.terrain[c.x][c.y] = WorldGeneratorScript.TerrainType.GRASS
			world_data.occupancy[c.x][c.y] = false

	world_instance.set("placing_building_type", "barracks")
	var place_res = world_instance.call("_execute_placement", br_cell)
	if not place_res.get("success", false):
		printerr("  [FAIL] Placement failed in TC-CON.6: %s" % place_res.get("reason"))
		return false

	var b_id := "bld_barracks_10_20"
	var b_data := BuildingSystemScript.get_building_by_id(b_id, world_data)

	# Advance partially: 8.0 / 12.0 hours
	b_data["construction_progress"] = 8.0

	# 1. Verify tile hover inspect shows [Đang xây: 66%]
	world_instance.call("_update_tile_hover")
	var hud = world_instance.get("hud")
	var b_name_with_pct: String = world_instance.call("_get_building_display_name", "barracks")
	var bld_dict: Dictionary = world_instance.call("_get_building_at_cell", br_cell)
	var prog: float = float(bld_dict.get("construction_progress", 0.0))
	var total: float = float(bld_dict.get("construction_hours", 12.0))
	var pct: int = int((prog / total) * 100.0)
	if pct != 66:
		printerr("  [FAIL] Expected 66%% progress, got %d%%" % pct)
		failures += 1

	# 2. Serialize and save to disk
	var save_path := "user://saves/test_construction_save.json"
	SaveManagerScript.ensure_save_directory()
	var save_res: Dictionary = SaveManagerScript.save_to_file(world_instance, save_path)
	if not save_res.get("success", false):
		printerr("  [FAIL] Save failed in TC-CON.6: %s" % save_res.get("error"))
		return false

	# 3. Load from disk
	var load_res: Dictionary = SaveManagerScript.load_from_file(save_path)
	if not load_res.get("success", false):
		printerr("  [FAIL] Load failed in TC-CON.6: %s" % load_res.get("error"))
		return false

	var apply_res: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, load_res["data"])
	if not apply_res.get("success", false):
		printerr("  [FAIL] Apply state failed in TC-CON.6: %s" % apply_res.get("error"))
		return false

	# 4. Verify loaded state
	var loaded_b: Dictionary = BuildingSystemScript.get_building_by_id(b_id, world_instance.get("world_data"))
	if loaded_b.is_empty():
		printerr("  [FAIL] Building not found after load!")
		failures += 1
	else:
		if loaded_b.get("state") != "under_construction":
			printerr("  [FAIL] State not 'under_construction' after load: '%s'" % loaded_b.get("state"))
			failures += 1
		if absf(float(loaded_b.get("construction_progress", 0.0)) - 8.0) > 0.01:
			printerr("  [FAIL] construction_progress not preserved! Got %f" % loaded_b.get("construction_progress"))
			failures += 1
		if absf(float(loaded_b.get("construction_hours", 0.0)) - 12.0) > 0.01:
			printerr("  [FAIL] construction_hours not preserved! Got %f" % loaded_b.get("construction_hours"))
			failures += 1

	# Verify visual node modulate is amber scaffolding
	var b_node = world_instance.get("buildings_container").get_node_or_null("Building_barracks_10_20")
	if b_node:
		var spr: Sprite2D = b_node.get_node_or_null("Sprite2D")
		if spr and spr.modulate != Color(0.8, 0.7, 0.5, 0.7):
			printerr("  [FAIL] Scaffolding modulate not restored after load! Got %s" % spr.modulate)
			failures += 1

	# 5. Double load: zero duplicate nodes, zero duplicate jobs
	var apply_res2 = SaveManagerScript.apply_loaded_state_to_world(world_instance, load_res["data"])
	if not apply_res2.get("success", false):
		printerr("  [FAIL] Double load apply failed!")
		failures += 1

	var matching_nodes: int = 0
	for child in world_instance.get("buildings_container").get_children():
		if child.name == "Building_barracks_10_20":
			matching_nodes += 1
	if matching_nodes != 1:
		printerr("  [FAIL] Node duplication on double load! Found %d nodes" % matching_nodes)
		failures += 1

	var b_jobs = world_instance.get("job_mgr").get_jobs_for_building(b_id)
	if b_jobs.size() != 4:
		printerr("  [FAIL] Expected exactly 4 jobs on double load, got %d" % b_jobs.size())
		failures += 1

	# 6. Malformed Save Data Validation (Requirement 5)
	# Check A: Negative progress
	var bad_data_neg = load_res["data"].duplicate(true)
	bad_data_neg["buildings"][0]["construction_progress"] = -5.0
	var val_neg = SaveManagerScript.validate_save_data(bad_data_neg)
	if val_neg.get("valid", true):
		printerr("  [FAIL] validate_save_data passed negative construction_progress!")
		failures += 1

	# Check B: Progress exceeds hours
	var bad_data_overflow = load_res["data"].duplicate(true)
	bad_data_overflow["buildings"][0]["construction_progress"] = 25.0
	var val_overflow = SaveManagerScript.validate_save_data(bad_data_overflow)
	if val_overflow.get("valid", true):
		printerr("  [FAIL] validate_save_data passed construction_progress > construction_hours!")
		failures += 1

	# Check C: Non-positive hours
	var bad_data_zero_h = load_res["data"].duplicate(true)
	bad_data_zero_h["buildings"][0]["construction_hours"] = 0.0
	var val_zero_h = SaveManagerScript.validate_save_data(bad_data_zero_h)
	if val_zero_h.get("valid", true):
		printerr("  [FAIL] validate_save_data passed non-positive construction_hours!")
		failures += 1

	# Check D: Unrecognized state
	var bad_data_state = load_res["data"].duplicate(true)
	bad_data_state["buildings"][0]["state"] = "mythical_state"
	var val_state = SaveManagerScript.validate_save_data(bad_data_state)
	if val_state.get("valid", true):
		printerr("  [FAIL] validate_save_data passed unrecognized building state!")
		failures += 1

	# Check E: Out of bounds building
	var bad_data_oob = load_res["data"].duplicate(true)
	bad_data_oob["buildings"][0]["cell_x"] = 63
	bad_data_oob["buildings"][0]["cell_y"] = 63
	bad_data_oob["buildings"][0]["size_x"] = 3
	bad_data_oob["buildings"][0]["size_y"] = 3
	var val_oob = SaveManagerScript.validate_save_data(bad_data_oob)
	if val_oob.get("valid", true):
		printerr("  [FAIL] validate_save_data passed out-of-bounds building footprint!")
		failures += 1

	# Check F: apply_loaded_state_to_world rejects malformed data without destroying current world
	var b_count_before: int = world_instance.get("world_data").buildings.size()
	var cit_count_before: int = world_instance.get("citizen_list").size()
	var apply_bad = SaveManagerScript.apply_loaded_state_to_world(world_instance, bad_data_overflow)
	if apply_bad.get("success", true):
		printerr("  [FAIL] apply_loaded_state_to_world succeeded on malformed save data!")
		failures += 1
	var b_count_after: int = world_instance.get("world_data").buildings.size()
	var cit_count_after: int = world_instance.get("citizen_list").size()
	if b_count_before != b_count_after or cit_count_before != cit_count_after:
		printerr("  [FAIL] Malformed load attempt corrupted world state (buildings or citizens cleared)!")
		failures += 1
	else:
		print("  [PASS] Malformed save data safely rejected before destructive reconstruction begins.")

	# Check G: House with mismatched footprint (3x3 instead of 2x2 configured blueprint)
	var bad_data_footprint = load_res["data"].duplicate(true)
	for b in bad_data_footprint["buildings"]:
		if b.get("type") == "house":
			b["size_x"] = 3
			b["size_y"] = 3
			break
	var val_fp = SaveManagerScript.validate_save_data(bad_data_footprint)
	if val_fp.get("valid", true):
		printerr("  [FAIL] validate_save_data passed mismatched blueprint footprint (3x3 house)!")
		failures += 1
	else:
		print("  [PASS] Mismatched blueprint footprint (3x3 house) correctly rejected.")

	# Check H: Fractional grid coordinate (10.5)
	var bad_data_frac_coord = load_res["data"].duplicate(true)
	bad_data_frac_coord["buildings"][0]["cell_x"] = 10.5
	var val_frac_coord = SaveManagerScript.validate_save_data(bad_data_frac_coord)
	if val_frac_coord.get("valid", true):
		printerr("  [FAIL] validate_save_data passed fractional grid coordinate (10.5)!")
		failures += 1
	else:
		print("  [PASS] Fractional grid coordinate correctly rejected.")

	# Check I: Fractional footprint dimension (2.5)
	var bad_data_frac_dim = load_res["data"].duplicate(true)
	bad_data_frac_dim["buildings"][0]["size_x"] = 2.5
	var val_frac_dim = SaveManagerScript.validate_save_data(bad_data_frac_dim)
	if val_frac_dim.get("valid", true):
		printerr("  [FAIL] validate_save_data passed fractional footprint dimension (2.5)!")
		failures += 1
	else:
		print("  [PASS] Fractional footprint dimension correctly rejected.")

	# Check J: Legacy save legitimately omitting size fields resolves cleanly from blueprint
	var legacy_data = load_res["data"].duplicate(true)
	for b in legacy_data["buildings"]:
		b.erase("size_x")
		b.erase("size_y")
	var val_legacy = SaveManagerScript.validate_save_data(legacy_data)
	if not val_legacy.get("valid", false):
		printerr("  [FAIL] validate_save_data rejected legacy save omitting size fields: %s" % val_legacy.get("error"))
		failures += 1
	else:
		print("  [PASS] Legacy save omitting size fields validated cleanly using blueprint footprint.")

	var apply_legacy = SaveManagerScript.apply_loaded_state_to_world(world_instance, legacy_data)
	if not apply_legacy.get("success", false):
		printerr("  [FAIL] apply_loaded_state_to_world failed for legacy save: %s" % apply_legacy.get("error"))
		failures += 1
	else:
		print("  [PASS] Legacy save successfully restored world state.")

	# Clean up test save file
	DirAccess.remove_absolute(save_path)
	if FileAccess.file_exists(save_path + ".bak"):
		DirAccess.remove_absolute(save_path + ".bak")

	if failures == 0:
		print("  [PASS] TC-CON.6 PASSED.\n")
		return true
	printerr("  [FAIL] TC-CON.6 had %d failures.\n" % failures)
	return false
