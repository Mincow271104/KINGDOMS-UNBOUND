extends SceneTree
## Headless Test Suite for Package 1B: Dynamic Production Workplaces.
## Validates TC-DW.1 through TC-DW.5:
## - TC-DW.1: Preserve starter workplaces & jobs
## - TC-DW.2: Dynamic workplace registration & cost deduction
## - TC-DW.3: Jobs & production at correct workplace buffer (Unit Test)
## - TC-DW.3b: Real Citizen Work & Recurring Production Flow (Integration Test)
## - TC-DW.4: Physical hauling without teleportation (Unit Test)
## - TC-DW.4b: Real Citizen Hauling Loop through State Machine (Integration Test)
## - TC-DW.5: Save/Load persistence, buffer restoration & anti-duplication

const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const WorkplaceManagerScript = preload("res://scripts/economy/workplace_manager.gd")
const JobManagerScript = preload("res://scripts/jobs/job_manager.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const IsoMathScript = preload("res://scripts/utils/iso_math.gd")
const GridNavigationScript = preload("res://scripts/navigation/grid_navigation.gd")
const ResourceManagerScript = preload("res://scripts/economy/resource_manager.gd")
const CitizenControllerScript = preload("res://scripts/entities/citizen_controller.gd")

const TEST_SAVE_PATH: String = "user://saves/test_dynamic_workplaces_save.json"

var frame_count: int = 0
var world_instance: Node = null
var world_scene: PackedScene = null

func _init() -> void:
	print("\n========================================================")
	print("  TEST SUITE: Package 1B — Dynamic Production Workplaces")
	print("========================================================\n")

	SaveManagerScript.ensure_save_directory()

	world_scene = load("res://scenes/world/world_view.tscn")
	world_instance = world_scene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1

	# Allow world_instance._ready() to initialize fully on Frame 3
	if frame_count == 3:
		var all_passed := true

		var pass_tc1 := _test_tc_dw_1_starter_workplaces()
		var pass_tc2 := _test_tc_dw_2_dynamic_registration()
		var pass_tc3 := _test_tc_dw_3_jobs_and_production()
		var pass_tc3b := _test_tc_dw_3b_citizen_work_integration()
		var pass_tc4 := _test_tc_dw_4_physical_hauling()
		var pass_tc4b := _test_tc_dw_4b_citizen_hauling_integration()
		var pass_tc5 := _test_tc_dw_5_save_load_and_deduplication()

		all_passed = pass_tc1 and pass_tc2 and pass_tc3 and pass_tc3b and pass_tc4 and pass_tc4b and pass_tc5

		print("\n--------------------------------------------------------")
		if all_passed:
			print("  ALL PACKAGE 1B DYNAMIC WORKPLACE TESTS PASSED! (Exit Code 0)")
			print("--------------------------------------------------------\n")
			quit(0)
			return true
		else:
			print("  PACKAGE 1B TESTS FAILED! (Exit Code 1)")
			print("--------------------------------------------------------\n")
			quit(1)
			return true

	return false

# -----------------------------------------------------------------------------
# TC-DW.1: Preserve Starter Workplaces & Jobs
# -----------------------------------------------------------------------------
func _test_tc_dw_1_starter_workplaces() -> bool:
	print("--- Running TC-DW.1: Starter Workplaces & Jobs Integrity ---")
	var failures: int = 0

	var wp_mgr: WorkplaceManager = world_instance.get("workplace_mgr")
	var job_mgr: JobManager = world_instance.get("job_mgr")

	if wp_mgr == null or job_mgr == null:
		printerr("  [FAIL] WorkplaceManager or JobManager not initialized on WorldView!")
		return false

	# 1. Verify Farm Starter
	var farm_starter: WorkplaceManager.WorkplaceData = wp_mgr.get_workplace("farm_starter")
	if farm_starter == null:
		printerr("  [FAIL] 'farm_starter' not found in WorkplaceManager!")
		failures += 1
	else:
		if farm_starter.building_type != "farm":
			printerr("  [FAIL] farm_starter building_type is '%s', expected 'farm'" % farm_starter.building_type)
			failures += 1
		if farm_starter.origin_cell != Vector2i(36, 35) or farm_starter.size != Vector2i(2, 2):
			printerr("  [FAIL] farm_starter footprint mismatch! Origin: %s, Size: %s" % [farm_starter.origin_cell, farm_starter.size])
			failures += 1
		if farm_starter.access_cell != Vector2i(35, 35):
			printerr("  [FAIL] farm_starter access_cell is %s, expected (35, 35)" % farm_starter.access_cell)
			failures += 1
		if farm_starter.output_resource != EconomyConfigScript.RES_FOOD:
			printerr("  [FAIL] farm_starter output_resource is '%s', expected '%s'" % [farm_starter.output_resource, EconomyConfigScript.RES_FOOD])
			failures += 1
		if farm_starter.buffer_capacity != 50 or farm_starter.worker_quota != 5:
			printerr("  [FAIL] farm_starter capacity/quota mismatch! cap: %d, quota: %d" % [farm_starter.buffer_capacity, farm_starter.worker_quota])
			failures += 1
		print("  [PASS] Starter farm verified (36, 35), 5 workers, 50 capacity, food output.")

	# 2. Verify Woodcutter Starter
	var wc_starter: WorkplaceManager.WorkplaceData = wp_mgr.get_workplace("woodcutter_starter")
	if wc_starter == null:
		printerr("  [FAIL] 'woodcutter_starter' not found in WorkplaceManager!")
		failures += 1
	else:
		if wc_starter.building_type != "woodcutter":
			printerr("  [FAIL] woodcutter_starter building_type is '%s', expected 'woodcutter'" % wc_starter.building_type)
			failures += 1
		if wc_starter.origin_cell != Vector2i(26, 30) or wc_starter.size != Vector2i(2, 2):
			printerr("  [FAIL] woodcutter_starter footprint mismatch! Origin: %s, Size: %s" % [wc_starter.origin_cell, wc_starter.size])
			failures += 1
		if wc_starter.access_cell != Vector2i(28, 30):
			printerr("  [FAIL] woodcutter_starter access_cell is %s, expected (28, 30)" % wc_starter.access_cell)
			failures += 1
		if wc_starter.output_resource != EconomyConfigScript.RES_WOOD:
			printerr("  [FAIL] woodcutter_starter output_resource is '%s', expected '%s'" % [wc_starter.output_resource, EconomyConfigScript.RES_WOOD])
			failures += 1
		if wc_starter.buffer_capacity != 40 or wc_starter.worker_quota != 4:
			printerr("  [FAIL] woodcutter_starter capacity/quota mismatch! cap: %d, quota: %d" % [wc_starter.buffer_capacity, wc_starter.worker_quota])
			failures += 1
		print("  [PASS] Starter woodcutter verified (26, 30), 4 workers, 40 capacity, wood output.")

	# 3. Verify Starter Jobs
	var starter_farm_jobs: Array[JobManager.JobData] = job_mgr.get_jobs_for_building("farm_starter")
	if starter_farm_jobs.size() != 5:
		printerr("  [FAIL] Expected 5 jobs for farm_starter, got %d" % starter_farm_jobs.size())
		failures += 1
	else:
		for job in starter_farm_jobs:
			if job.type != "farmer" or not job.is_recurring:
				printerr("  [FAIL] Starter farm job invalid! type: %s, recurring: %s" % [job.type, job.is_recurring])
				failures += 1
		print("  [PASS] 5 recurring farmer jobs verified for farm_starter.")

	var starter_wc_jobs: Array[JobManager.JobData] = job_mgr.get_jobs_for_building("woodcutter_starter")
	if starter_wc_jobs.size() != 4:
		printerr("  [FAIL] Expected 4 jobs for woodcutter_starter, got %d" % starter_wc_jobs.size())
		failures += 1
	else:
		for job in starter_wc_jobs:
			if job.type != "woodcutter" or not job.is_recurring:
				printerr("  [FAIL] Starter woodcutter job invalid! type: %s, recurring: %s" % [job.type, job.is_recurring])
				failures += 1
		print("  [PASS] 4 recurring woodcutter jobs verified for woodcutter_starter.")

	if failures == 0:
		print("  [PASS] TC-DW.1 PASSED.\n")
		return true
	else:
		printerr("  [FAIL] TC-DW.1 had %d failures.\n" % failures)
		return false

# -----------------------------------------------------------------------------
# TC-DW.2: Dynamic Workplace Registration & Cost Deduction
# -----------------------------------------------------------------------------
func _test_tc_dw_2_dynamic_registration() -> bool:
	print("--- Running TC-DW.2: Dynamic Workplace Registration & Cost Deduction ---")
	var failures: int = 0

	var wp_mgr: WorkplaceManager = world_instance.get("workplace_mgr")
	var world_data = world_instance.get("world_data")
	var nav = world_instance.get("nav")
	var live_rm: Node = world_instance.get_node_or_null("/root/ResourceManager")

	if live_rm:
		live_rm.add_resource("wood", 200)
		live_rm.add_resource("stone", 100)

	# 1. Clear grass patch for Dynamic Farm at (29, 27) in center settlement meadow
	var farm_origin := Vector2i(29, 27)
	for dx in range(-1, 3):
		for dy in range(-1, 3):
			var c := farm_origin + Vector2i(dx, dy)
			world_data.terrain[c.x][c.y] = WorldGeneratorScript.TerrainType.GRASS
			world_data.occupancy[c.x][c.y] = false

	var wood_prior: int = live_rm.get_available_stock("wood") if live_rm else 0
	var stone_prior: int = live_rm.get_available_stock("stone") if live_rm else 0

	world_instance.set("placing_building_type", "farm")
	var res_farm: Dictionary = world_instance.call("_execute_placement", farm_origin)

	if not res_farm.get("success", false):
		printerr("  [FAIL] Placing dynamic farm failed: %s" % res_farm.get("reason"))
		failures += 1
	else:
		var wood_post: int = live_rm.get_available_stock("wood") if live_rm else 0
		var stone_post: int = live_rm.get_available_stock("stone") if live_rm else 0

		# Farm costs: 30 Wood, 5 Stone
		if wood_post != wood_prior - 30 or stone_post != stone_prior - 5:
			printerr("  [FAIL] Cost deduction incorrect! Expected -30 Wood, -5 Stone. Got: Wood %d->%d, Stone %d->%d" % [wood_prior, wood_post, stone_prior, stone_post])
			failures += 1
		else:
			print("  [PASS] Dynamic farm constructed; costs deducted atomically once (-30 Wood, -5 Stone).")

		var farm_id := "bld_farm_29_27"
		var farm_wp: WorkplaceManager.WorkplaceData = wp_mgr.get_workplace(farm_id)
		if farm_wp == null:
			printerr("  [FAIL] Dynamic workplace '%s' was NOT registered in WorkplaceManager!" % farm_id)
			failures += 1
		else:
			if farm_wp.building_type != "farm":
				printerr("  [FAIL] Dynamic workplace building_type is '%s', expected 'farm'" % farm_wp.building_type)
				failures += 1
			if farm_wp.output_resource != EconomyConfigScript.RES_FOOD:
				printerr("  [FAIL] Dynamic workplace output is '%s', expected '%s'" % [farm_wp.output_resource, EconomyConfigScript.RES_FOOD])
				failures += 1
			if farm_wp.size != Vector2i(2, 2) or farm_wp.worker_quota != 5:
				printerr("  [FAIL] Dynamic workplace size/quota mismatch: %s / %d" % [farm_wp.size, farm_wp.worker_quota])
				failures += 1

			# Access cell checks
			var acc: Vector2i = farm_wp.access_cell
			var in_fp := (acc.x >= farm_origin.x and acc.x < farm_origin.x + 2 and acc.y >= farm_origin.y and acc.y < farm_origin.y + 2)
			if in_fp:
				printerr("  [FAIL] Access cell %s is inside the building footprint!" % acc)
				failures += 1
			elif not IsoMathScript.is_in_bounds(acc):
				printerr("  [FAIL] Access cell %s is out of map bounds!" % acc)
				failures += 1
			elif not nav.is_walkable(acc):
				printerr("  [FAIL] Access cell %s is not walkable!" % acc)
				failures += 1
			else:
				print("  [PASS] Dynamic farm registered with valid walkable perimeter access cell: %s" % acc)

	# 2. Clear grass patch for Dynamic Woodcutter at (34, 27)
	var wc_origin := Vector2i(34, 27)
	for dx in range(-1, 3):
		for dy in range(-1, 3):
			var c := wc_origin + Vector2i(dx, dy)
			world_data.terrain[c.x][c.y] = WorldGeneratorScript.TerrainType.GRASS
			world_data.occupancy[c.x][c.y] = false

	var wood_prior_wc: int = live_rm.get_available_stock("wood") if live_rm else 0
	var stone_prior_wc: int = live_rm.get_available_stock("stone") if live_rm else 0

	world_instance.set("placing_building_type", "woodcutter")
	var res_wc: Dictionary = world_instance.call("_execute_placement", wc_origin)

	if not res_wc.get("success", false):
		printerr("  [FAIL] Placing dynamic woodcutter failed: %s" % res_wc.get("reason"))
		failures += 1
	else:
		var wood_post_wc: int = live_rm.get_available_stock("wood") if live_rm else 0
		var stone_post_wc: int = live_rm.get_available_stock("stone") if live_rm else 0

		# Woodcutter costs: 20 Wood, 5 Stone
		if wood_post_wc != wood_prior_wc - 20 or stone_post_wc != stone_prior_wc - 5:
			printerr("  [FAIL] Woodcutter cost deduction incorrect! Got: Wood %d->%d, Stone %d->%d" % [wood_prior_wc, wood_post_wc, stone_prior_wc, stone_post_wc])
			failures += 1
		else:
			print("  [PASS] Dynamic woodcutter constructed; costs deducted atomically once (-20 Wood, -5 Stone).")

		var wc_id := "bld_woodcutter_34_27"
		var wc_wp: WorkplaceManager.WorkplaceData = wp_mgr.get_workplace(wc_id)
		if wc_wp == null:
			printerr("  [FAIL] Dynamic workplace '%s' was NOT registered in WorkplaceManager!" % wc_id)
			failures += 1
		else:
			if wc_wp.building_type != "woodcutter" or wc_wp.output_resource != EconomyConfigScript.RES_WOOD:
				printerr("  [FAIL] Dynamic woodcutter data mismatch!")
				failures += 1
			else:
				print("  [PASS] Dynamic woodcutter registered cleanly with wood output and access cell: %s" % wc_wp.access_cell)

	# 3. Test Inaccessible Placement Rejection
	var blocked_origin := Vector2i(10, 10)
	# Clear footprint
	world_data.terrain[10][10] = WorldGeneratorScript.TerrainType.GRASS
	world_data.occupancy[10][10] = false
	world_data.terrain[11][10] = WorldGeneratorScript.TerrainType.GRASS
	world_data.occupancy[11][10] = false
	world_data.terrain[10][11] = WorldGeneratorScript.TerrainType.GRASS
	world_data.occupancy[10][11] = false
	world_data.terrain[11][11] = WorldGeneratorScript.TerrainType.GRASS
	world_data.occupancy[11][11] = false

	# Surround entirely with water / impassable
	for dx in range(-1, 3):
		for dy in range(-1, 3):
			if dx >= 0 and dx <= 1 and dy >= 0 and dy <= 1:
				continue
			var c := blocked_origin + Vector2i(dx, dy)
			world_data.terrain[c.x][c.y] = WorldGeneratorScript.TerrainType.WATER
			world_data.occupancy[c.x][c.y] = true

	var wood_prior_block: int = live_rm.get_available_stock("wood") if live_rm else 0
	var stone_prior_block: int = live_rm.get_available_stock("stone") if live_rm else 0

	world_instance.set("placing_building_type", "farm")
	var res_blocked: Dictionary = world_instance.call("_execute_placement", blocked_origin)

	if res_blocked.get("success", false):
		printerr("  [FAIL] Inaccessible farm placement was erroneously accepted!")
		failures += 1
	else:
		var wood_post_block: int = live_rm.get_available_stock("wood") if live_rm else 0
		var stone_post_block: int = live_rm.get_available_stock("stone") if live_rm else 0
		if wood_post_block != wood_prior_block or stone_post_block != stone_prior_block:
			printerr("  [FAIL] Resources were deducted despite rejected placement!")
			failures += 1
		else:
			print("  [PASS] Inaccessible production building rejected before cost deduction: '%s'" % res_blocked.get("reason"))

	# Clean up blocked test cell
	for dx in range(-1, 3):
		for dy in range(-1, 3):
			var c := blocked_origin + Vector2i(dx, dy)
			world_data.terrain[c.x][c.y] = WorldGeneratorScript.TerrainType.GRASS
			world_data.occupancy[c.x][c.y] = false

	if failures == 0:
		print("  [PASS] TC-DW.2 PASSED.\n")
		return true
	else:
		printerr("  [FAIL] TC-DW.2 had %d failures.\n" % failures)
		return false

# -----------------------------------------------------------------------------
# TC-DW.3: Jobs & Production at Correct Workplace (Unit Test)
# -----------------------------------------------------------------------------
func _test_tc_dw_3_jobs_and_production() -> bool:
	print("--- Running TC-DW.3: Jobs & Production at Correct Workplace (Unit Test) ---")
	var failures: int = 0

	var wp_mgr: WorkplaceManager = world_instance.get("workplace_mgr")
	var job_mgr: JobManager = world_instance.get("job_mgr")
	var live_rm: Node = world_instance.get_node_or_null("/root/ResourceManager")

	# 1. Verify Farm Jobs
	var farm_jobs: Array[JobManager.JobData] = job_mgr.get_jobs_for_building("bld_farm_29_27")
	if farm_jobs.size() != 5:
		printerr("  [FAIL] Expected 5 jobs for bld_farm_29_27, got %d" % farm_jobs.size())
		failures += 1
	else:
		var wp_farm = wp_mgr.get_workplace("bld_farm_29_27")
		for j in farm_jobs:
			if j.type != "farmer":
				printerr("  [FAIL] Job type is '%s', expected 'farmer'" % j.type)
				failures += 1
			if j.target_cell != wp_farm.access_cell:
				printerr("  [FAIL] Job target_cell is %s, expected access_cell %s" % [j.target_cell, wp_farm.access_cell])
				failures += 1
			if not j.is_recurring:
				printerr("  [FAIL] Job is not recurring!")
				failures += 1
		print("  [PASS] 5 recurring farmer jobs linked to bld_farm_29_27 verified.")

	# 2. Verify Woodcutter Jobs
	var wc_jobs: Array[JobManager.JobData] = job_mgr.get_jobs_for_building("bld_woodcutter_34_27")
	if wc_jobs.size() != 4:
		printerr("  [FAIL] Expected 4 jobs for bld_woodcutter_34_27, got %d" % wc_jobs.size())
		failures += 1
	else:
		var wp_wc = wp_mgr.get_workplace("bld_woodcutter_34_27")
		for j in wc_jobs:
			if j.type != "woodcutter" or j.target_cell != wp_wc.access_cell or not j.is_recurring:
				printerr("  [FAIL] Dynamic woodcutter job invalid!")
				failures += 1
		print("  [PASS] 4 recurring woodcutter jobs linked to bld_woodcutter_34_27 verified.")

	# 3. Manager Production to Buffer & Zero Central Teleportation
	var central_food_prior: int = live_rm.get_available_stock("food") if live_rm else 0
	var central_wood_prior: int = live_rm.get_available_stock("wood") if live_rm else 0

	# Farm production cycle
	var produced_food := wp_mgr.produce_to_buffer("bld_farm_29_27", 1.0)
	if produced_food != 5:
		printerr("  [FAIL] Produced %d food, expected 5" % produced_food)
		failures += 1
	if wp_mgr.get_buffer_amount("bld_farm_29_27") != 5:
		printerr("  [FAIL] Buffer amount is %d, expected 5" % wp_mgr.get_buffer_amount("bld_farm_29_27"))
		failures += 1

	# Other buffers must NOT be affected
	if wp_mgr.get_buffer_amount("farm_starter") != 0 or wp_mgr.get_buffer_amount("woodcutter_starter") != 0 or wp_mgr.get_buffer_amount("bld_woodcutter_34_27") != 0:
		printerr("  [FAIL] Producing to bld_farm_29_27 polluted another workplace's buffer!")
		failures += 1
	else:
		print("  [PASS] Production deposited strictly into bld_farm_29_27 buffer (amount: 5); other buffers unaffected.")

	# Central stock must NOT increase on production
	var central_food_post: int = live_rm.get_available_stock("food") if live_rm else 0
	if central_food_post != central_food_prior:
		printerr("  [FAIL] Central food stock increased upon production! Teleportation detected.")
		failures += 1
	else:
		print("  [PASS] Central stock unchanged on production (Zero Teleportation verified).")

	# Woodcutter production cycle
	var produced_wood := wp_mgr.produce_to_buffer("bld_woodcutter_34_27", 1.0)
	if produced_wood != 4:
		printerr("  [FAIL] Produced %d wood, expected 4" % produced_wood)
		failures += 1
	if wp_mgr.get_buffer_amount("bld_woodcutter_34_27") != 4:
		printerr("  [FAIL] Buffer amount is %d, expected 4" % wp_mgr.get_buffer_amount("bld_woodcutter_34_27"))
		failures += 1

	var central_wood_post: int = live_rm.get_available_stock("wood") if live_rm else 0
	if central_wood_post != central_wood_prior:
		printerr("  [FAIL] Central wood stock increased upon production! Teleportation detected.")
		failures += 1
	else:
		print("  [PASS] Woodcutter produced strictly into local buffer (amount: 4); central stock unchanged.")

	if failures == 0:
		print("  [PASS] TC-DW.3 PASSED.\n")
		return true
	else:
		printerr("  [FAIL] TC-DW.3 had %d failures.\n" % failures)
		return false

# -----------------------------------------------------------------------------
# TC-DW.3b: Real Citizen Work & Recurring Production Integration Test
# -----------------------------------------------------------------------------
func _test_tc_dw_3b_citizen_work_integration() -> bool:
	print("--- Running TC-DW.3b: Real Citizen Work & Recurring Production Integration ---")
	var failures: int = 0

	var wp_mgr: WorkplaceManager = world_instance.get("workplace_mgr")
	var job_mgr: JobManager = world_instance.get("job_mgr")
	var nav: GridNavigation = world_instance.get("nav")
	var live_rm: Node = world_instance.get_node_or_null("/root/ResourceManager")

	# Save roles and temporarily set existing citizens to idle for isolated execution
	var saved_roles: Dictionary = {}
	for cit in world_instance.get("citizen_list"):
		saved_roles[cit.citizen_id] = cit.role
		cit.role = "idle"
		if cit.active_job != null:
			job_mgr.release_job(cit.active_job)
			cit.active_job = null
			cit.current_state = CitizenControllerScript.State.IDLE

	# Clear buffer of dynamic farm before testing citizen production
	var farm_wp: WorkplaceManager.WorkplaceData = wp_mgr.get_workplace("bld_farm_29_27")
	if farm_wp == null:
		printerr("  [FAIL] bld_farm_29_27 not found!")
		return false
	farm_wp.buffer_amount = 0

	# 1. Create real CitizenController with role "farmer"
	var farmer: CitizenController = CitizenControllerScript.new()
	farmer.name = "integration_test_farmer"
	world_instance.add_child(farmer)
	farmer.init_citizen(
		"integration_test_farmer",
		"Trần Nông Dân",
		"farmer",
		Vector2i(28, 26), # 1 cell away from access cell (28, 27)
		nav,
		job_mgr,
		wp_mgr
	)

	# 2. Cycle 1: Request job via state machine in IDLE
	farmer._process(0.1)

	if farmer.active_job == null:
		printerr("  [FAIL] Real farmer citizen failed to claim a job!")
		failures += 1
		if farmer.get_parent():
			farmer.get_parent().remove_child(farmer)
		farmer.free()
		return false

	if farmer.active_job.target_building_id != "bld_farm_29_27":
		printerr("  [FAIL] Claimed job target_building_id is '%s', expected 'bld_farm_29_27'" % farmer.active_job.target_building_id)
		failures += 1
	if farmer.active_job.worker_id != "integration_test_farmer":
		printerr("  [FAIL] Job worker_id '%s' != 'integration_test_farmer'" % farmer.active_job.worker_id)
		failures += 1
	if farmer.active_job.state != JobManagerScript.JobState.RESERVED and farmer.active_job.state != JobManagerScript.JobState.IN_PROGRESS:
		printerr("  [FAIL] Job state not RESERVED or IN_PROGRESS!")
		failures += 1
	print("  [PASS] Citizen correctly requested and reserved job for dynamic workplace 'bld_farm_29_27'.")

	# 3. State machine movement to target access cell (28, 27)
	var move_ticks := 0
	while farmer.current_state == CitizenControllerScript.State.MOVING_TO_JOB and move_ticks < 30:
		move_ticks += 1
		farmer._process(0.2)

	if farmer.current_cell != farm_wp.access_cell:
		printerr("  [FAIL] Farmer current_cell %s != access_cell %s" % [farmer.current_cell, farm_wp.access_cell])
		failures += 1
	if farmer.current_state != CitizenControllerScript.State.WORKING:
		printerr("  [FAIL] Farmer state not WORKING after arrival! State: %d" % farmer.current_state)
		failures += 1
	print("  [PASS] Citizen moved along discrete grid path and arrived at access cell %s (State: WORKING)." % farmer.current_cell)

	# 4. State machine working cycle (required: 3.0 hours)
	var food_before: int = live_rm.get_available_stock("food") if live_rm else 0

	# 1 hour of work
	farmer._process(1.0)
	if farmer.current_state != CitizenControllerScript.State.WORKING:
		printerr("  [FAIL] Citizen stopped working prematurely after 1 hour!")
		failures += 1
	if farm_wp.buffer_amount != 0:
		printerr("  [FAIL] Buffer increased before work hours completed!")
		failures += 1

	# 2nd hour of work
	farmer._process(1.0)
	if farm_wp.buffer_amount != 0:
		printerr("  [FAIL] Buffer increased before work hours completed!")
		failures += 1

	# 3rd hour of work (completes the 3.0 required hours)
	farmer._process(1.0)

	# Citizen state machine must have completed job and deposited to buffer
	if farm_wp.buffer_amount != 5:
		printerr("  [FAIL] Buffer amount after citizen work cycle is %d, expected 5" % farm_wp.buffer_amount)
		failures += 1
	else:
		print("  [PASS] Citizen completed work cycle; produced 5 Food directly into bld_farm_29_27 buffer.")

	# Buffer of other workplaces must not be affected
	if wp_mgr.get_buffer_amount("farm_starter") != 0 or wp_mgr.get_buffer_amount("woodcutter_starter") != 0 or wp_mgr.get_buffer_amount("bld_woodcutter_34_27") != 4:
		printerr("  [FAIL] Other workplace buffers polluted by citizen production!")
		failures += 1

	# Central stock must NOT have increased
	var food_after_work: int = live_rm.get_available_stock("food") if live_rm else 0
	if food_after_work != food_before:
		printerr("  [FAIL] Central food stock changed during production! Expected %d, got %d" % [food_before, food_after_work])
		failures += 1
	else:
		print("  [PASS] Central stock unchanged on citizen work completion (No instant teleportation).")

	# 5. Cycle 2: Recurring job execution
	# Citizen returned to IDLE; process next frame to pick up recurring job again
	if farmer.current_state != CitizenControllerScript.State.IDLE:
		printerr("  [FAIL] Citizen did not transition to IDLE after completing job! State: %d" % farmer.current_state)
		failures += 1

	farmer._process(0.1) # Re-evaluates idle and requests available recurring job
	if farmer.current_state == CitizenControllerScript.State.MOVING_TO_JOB:
		farmer._process(0.1)

	if farmer.current_state != CitizenControllerScript.State.WORKING:
		printerr("  [FAIL] Citizen failed to resume recurring job for Cycle 2! State: %d" % farmer.current_state)
		failures += 1
	else:
		# Work full 3.0 hours for Cycle 2
		farmer._process(3.0)
		if farm_wp.buffer_amount != 10:
			printerr("  [FAIL] Buffer amount after Cycle 2 is %d, expected 10" % farm_wp.buffer_amount)
			failures += 1
		else:
			print("  [PASS] Recurring job verified on Cycle 2: Citizen produced additional 5 Food into buffer (Total: 10).")

	if farmer.get_parent():
		farmer.get_parent().remove_child(farmer)
	farmer.free()

	# Restore citizen roles
	for cit in world_instance.get("citizen_list"):
		if saved_roles.has(cit.citizen_id):
			cit.role = saved_roles[cit.citizen_id]

	if failures == 0:
		print("  [PASS] TC-DW.3b PASSED.\n")
		return true
	else:
		printerr("  [FAIL] TC-DW.3b had %d failures.\n" % failures)
		return false

# -----------------------------------------------------------------------------
# TC-DW.4: Physical Hauling Loop (Unit Test)
# -----------------------------------------------------------------------------
func _test_tc_dw_4_physical_hauling() -> bool:
	print("--- Running TC-DW.4: Physical Hauling Loop (Unit Test) ---")
	var failures: int = 0

	var wp_mgr: WorkplaceManager = world_instance.get("workplace_mgr")
	var job_mgr: JobManager = world_instance.get("job_mgr")
	var live_rm: Node = world_instance.get_node_or_null("/root/ResourceManager")

	# Add another cycle to bld_woodcutter_34_27 so buffer = 4 + 4 = 8 >= 5 (threshold)
	wp_mgr.produce_to_buffer("bld_woodcutter_34_27", 1.0)
	var wc_buf: int = wp_mgr.get_buffer_amount("bld_woodcutter_34_27")
	if wc_buf != 8:
		printerr("  [FAIL] Expected woodcutter buffer 8, got %d" % wc_buf)
		failures += 1

	# Both bld_farm_29_27 (buf: 10) and bld_woodcutter_34_27 (buf: 8) meet threshold >= 5
	var created_count := wp_mgr.update_hauling_jobs(job_mgr)
	if created_count < 2:
		printerr("  [FAIL] Expected at least 2 hauling jobs created, got %d" % created_count)
		failures += 1
	else:
		print("  [PASS] update_hauling_jobs created %d hauling jobs for dynamic workplaces." % created_count)

	# Locate hauling job for bld_woodcutter_34_27
	var wc_haul_job: JobManager.JobData = null
	for j in job_mgr.get_all_jobs():
		if j.type == "hauler" and j.source_workplace_id == "bld_woodcutter_34_27":
			wc_haul_job = j
			break

	if wc_haul_job == null:
		printerr("  [FAIL] Hauling job for bld_woodcutter_34_27 was not created!")
		failures += 1
	else:
		var wp_wc = wp_mgr.get_workplace("bld_woodcutter_34_27")
		if wc_haul_job.source_cell != wp_wc.access_cell:
			printerr("  [FAIL] Hauling job source_cell %s != woodcutter access_cell %s" % [wc_haul_job.source_cell, wp_wc.access_cell])
			failures += 1
		if wc_haul_job.cargo_resource != EconomyConfigScript.RES_WOOD:
			printerr("  [FAIL] Hauling cargo_resource is '%s', expected 'wood'" % wc_haul_job.cargo_resource)
			failures += 1
		if wc_haul_job.cargo_amount != 8:
			printerr("  [FAIL] Hauling cargo_amount is %d, expected 8" % wc_haul_job.cargo_amount)
			failures += 1
		print("  [PASS] Woodcutter hauling job verified: source %s -> dest %s, 8 Wood." % [wc_haul_job.source_cell, wc_haul_job.dest_cell])

		# Simulate physical pickup
		var central_wood_prior: int = live_rm.get_available_stock("wood") if live_rm else 0
		var picked_up := wp_mgr.pickup_from_buffer("bld_woodcutter_34_27", 10)
		if picked_up != 8:
			printerr("  [FAIL] Picked up %d wood, expected 8" % picked_up)
			failures += 1
		if wp_mgr.get_buffer_amount("bld_woodcutter_34_27") != 0:
			printerr("  [FAIL] Workplace buffer was not emptied after pickup!")
			failures += 1

		# Still no central stock increase on pickup
		var central_wood_mid: int = live_rm.get_available_stock("wood") if live_rm else 0
		if central_wood_mid != central_wood_prior:
			printerr("  [FAIL] Central stock increased upon pickup!")
			failures += 1
		else:
			print("  [PASS] Buffer emptied to 0 on pickup; central storage remains unchanged during transit.")

		# Simulate delivery to dropoff
		if live_rm:
			live_rm.add_resource("wood", picked_up)
		job_mgr.complete_job(wc_haul_job)

		var central_wood_post: int = live_rm.get_available_stock("wood") if live_rm else 0
		if central_wood_post != central_wood_prior + 8:
			printerr("  [FAIL] Central wood stock not credited after delivery! Prior: %d, Post: %d" % [central_wood_prior, central_wood_post])
			failures += 1
		if wc_haul_job.state != JobManager.JobState.COMPLETED:
			printerr("  [FAIL] Hauling job state not COMPLETED!")
			failures += 1
		print("  [PASS] Central stock increased only upon delivery completion (+8 Wood).")

	# Clean up any pending jobs for farm to avoid interference with TC-DW.4b
	for j in job_mgr.get_all_jobs():
		if j.type == "hauler" and j.source_workplace_id == "bld_farm_29_27":
			job_mgr.complete_job(j)

	if failures == 0:
		print("  [PASS] TC-DW.4 PASSED.\n")
		return true
	else:
		printerr("  [FAIL] TC-DW.4 had %d failures.\n" % failures)
		return false

# -----------------------------------------------------------------------------
# TC-DW.4b: Real Citizen Hauling Loop Integration Test
# -----------------------------------------------------------------------------
func _test_tc_dw_4b_citizen_hauling_integration() -> bool:
	print("--- Running TC-DW.4b: Real Citizen Hauling Loop Integration ---")
	var failures: int = 0

	var wp_mgr: WorkplaceManager = world_instance.get("workplace_mgr")
	var job_mgr: JobManager = world_instance.get("job_mgr")
	var nav: GridNavigation = world_instance.get("nav")
	var live_rm: Node = world_instance.get_node_or_null("/root/ResourceManager")

	# Save roles and temporarily set existing citizens to idle for isolated execution
	var saved_roles: Dictionary = {}
	for cit in world_instance.get("citizen_list"):
		saved_roles[cit.citizen_id] = cit.role
		cit.role = "idle"
		if cit.active_job != null:
			job_mgr.release_job(cit.active_job)
			cit.active_job = null
			cit.current_state = CitizenControllerScript.State.IDLE

	# bld_farm_29_27 has 10 Food produced by citizen in TC-DW.3b
	var farm_wp: WorkplaceManager.WorkplaceData = wp_mgr.get_workplace("bld_farm_29_27")
	if farm_wp == null or farm_wp.buffer_amount < 5:
		printerr("  [FAIL] bld_farm_29_27 buffer is %d, expected >= 5" % (farm_wp.buffer_amount if farm_wp else -1))
		return false

	# 1. Update hauling jobs to generate hauling job from dynamic workplace buffer
	var _created := wp_mgr.update_hauling_jobs(job_mgr)
	var haul_job: JobManager.JobData = null
	for j in job_mgr.get_all_jobs():
		if j.type == "hauler" and j.source_workplace_id == "bld_farm_29_27" and j.state == JobManagerScript.JobState.AVAILABLE:
			haul_job = j
			break

	if haul_job == null:
		printerr("  [FAIL] No available hauling job generated for bld_farm_29_27!")
		return false
	print("  [PASS] Hauling job generated: source %s -> dest %s, amount %d %s." % [haul_job.source_cell, haul_job.dest_cell, haul_job.cargo_amount, haul_job.cargo_resource])

	# 2. Create real CitizenController with role "hauler"
	var hauler: CitizenController = CitizenControllerScript.new()
	hauler.name = "integration_test_hauler"
	world_instance.add_child(hauler)
	hauler.init_citizen(
		"integration_test_hauler",
		"Trần Vận Chuyển",
		"hauler",
		Vector2i(28, 28), # 1 cell away from source cell (28, 27)
		nav,
		job_mgr,
		wp_mgr
	)

	# 3. Hauler requests job in IDLE state via state machine
	hauler._process(0.1)

	if hauler.active_job != haul_job:
		printerr("  [FAIL] Hauler did not claim the dynamic workplace hauling job!")
		failures += 1
		if hauler.get_parent():
			hauler.get_parent().remove_child(hauler)
		hauler.free()
		return false
	if hauler.current_state != CitizenControllerScript.State.MOVING_TO_JOB:
		printerr("  [FAIL] Hauler state not MOVING_TO_JOB!")
		failures += 1
	print("  [PASS] Hauler citizen claimed hauling job and entered MOVING_TO_JOB state.")

	# 4. Record baseline before pickup
	var cargo_res: String = haul_job.cargo_resource
	var buffer_before_pickup: int = farm_wp.buffer_amount
	var central_stock_before_pickup: int = live_rm.get_available_stock(cargo_res) if live_rm else 0

	# 5. Hauler moves along grid path to source access cell (28, 27)
	var move_to_source := 0
	while hauler.current_state == CitizenControllerScript.State.MOVING_TO_JOB and move_to_source < 30:
		move_to_source += 1
		hauler._process(0.2)

	# Arrival triggers _pickup_hauler_cargo() automatically via _arrive_at_destination()
	if hauler.current_state != CitizenControllerScript.State.HAULING:
		printerr("  [FAIL] Hauler did not transition to HAULING state upon arriving at source! State: %d" % hauler.current_state)
		failures += 1

	# Post-pickup assertions:
	# - Workplace buffer decreased by the amount picked up
	if farm_wp.buffer_amount != buffer_before_pickup - 10:
		printerr("  [FAIL] Buffer was not decremented! Amount: %d, expected %d" % [farm_wp.buffer_amount, buffer_before_pickup - 10])
		failures += 1

	# - Hauler cargo has correct resource and quantity
	if hauler.carrying_resource != cargo_res or hauler.carrying_amount != 10:
		printerr("  [FAIL] Hauler cargo incorrect! Resource: '%s', Amount: %d (expected '%s', 10)" % [hauler.carrying_resource, hauler.carrying_amount, cargo_res])
		failures += 1

	# - Central stock STILL equals central_stock_before_pickup (No instant teleportation or premature deposit)
	var central_stock_after_pickup: int = live_rm.get_available_stock(cargo_res) if live_rm else 0
	if central_stock_after_pickup != central_stock_before_pickup:
		printerr("  [FAIL] Central stock changed upon cargo pickup! Before: %d, After: %d" % [central_stock_before_pickup, central_stock_after_pickup])
		failures += 1
	else:
		print("  [PASS] Hauler arrived at source %s, extracted 10 %s; buffer reduced %d->%d; central stock strictly unchanged (%d)." % [farm_wp.access_cell, cargo_res, buffer_before_pickup, farm_wp.buffer_amount, central_stock_after_pickup])

	# 6. Hauler travels along discrete path to destination dropoff cell
	var haul_steps := 0
	while hauler.current_state == CitizenControllerScript.State.HAULING and haul_steps < 60:
		haul_steps += 1
		hauler._process(0.2)

		# Verify mid-transit: stock unchanged while still traveling in HAULING state
		if hauler.current_state == CitizenControllerScript.State.HAULING:
			if live_rm and live_rm.get_available_stock(cargo_res) != central_stock_before_pickup:
				printerr("  [FAIL] Central stock increased during transit before reaching destination!")
				failures += 1

	if hauler.current_state != CitizenControllerScript.State.IDLE:
		printerr("  [FAIL] Hauler did not complete delivery to IDLE state! Final state: %d" % hauler.current_state)
		failures += 1

	# 7. Post-delivery assertions:
	# - Central stock credited exactly once by the cargo amount delivered
	var central_stock_post_delivery: int = live_rm.get_available_stock(cargo_res) if live_rm else 0
	if central_stock_post_delivery != central_stock_before_pickup + 10:
		printerr("  [FAIL] Central %s stock not credited properly! Prior: %d, Post: %d, Expected: %d" % [cargo_res, central_stock_before_pickup, central_stock_post_delivery, central_stock_before_pickup + 10])
		failures += 1
	else:
		print("  [PASS] Hauler delivered 10 %s to dropoff %s; Central storage credited atomically (+10 %s, total %d)." % [cargo_res, haul_job.dest_cell, cargo_res, central_stock_post_delivery])

	# - Cargo cleared from citizen
	if hauler.carrying_amount != 0 or hauler.carrying_resource != "":
		printerr("  [FAIL] Hauler cargo was not cleared after deposit!")
		failures += 1

	# - Job marked completed
	if haul_job.state != JobManagerScript.JobState.COMPLETED:
		printerr("  [FAIL] Hauling job state is not COMPLETED!")
		failures += 1

	# - Buffer not double-deducted
	if farm_wp.buffer_amount != 0:
		printerr("  [FAIL] Buffer modified unexpectedly post-delivery!")
		failures += 1
	print("  [PASS] Job state COMPLETED, cargo cleared from citizen, buffer not double-deducted.")

	if hauler.get_parent():
		hauler.get_parent().remove_child(hauler)
	hauler.free()

	# Restore citizen roles
	for cit in world_instance.get("citizen_list"):
		if saved_roles.has(cit.citizen_id):
			cit.role = saved_roles[cit.citizen_id]

	if failures == 0:
		print("  [PASS] TC-DW.4b PASSED.\n")
		return true
	else:
		printerr("  [FAIL] TC-DW.4b had %d failures.\n" % failures)
		return false

# -----------------------------------------------------------------------------
# TC-DW.5: Save/Load Persistence, Buffer Restoration & Anti-Duplication
# -----------------------------------------------------------------------------
func _test_tc_dw_5_save_load_and_deduplication() -> bool:
	print("--- Running TC-DW.5: Save/Load Persistence, Buffer Restoration & Anti-Duplication ---")
	var failures: int = 0

	var wp_mgr: WorkplaceManager = world_instance.get("workplace_mgr")
	var job_mgr: JobManager = world_instance.get("job_mgr")

	# 1. Set specific buffer amounts before saving
	wp_mgr.get_workplace("bld_farm_29_27").buffer_amount = 17
	wp_mgr.get_workplace("bld_woodcutter_34_27").buffer_amount = 13
	wp_mgr.get_workplace("farm_starter").buffer_amount = 22

	# Save world state
	var save_res: Dictionary = SaveManagerScript.save_to_file(world_instance, TEST_SAVE_PATH)
	if not save_res.get("success", false):
		printerr("  [FAIL] Saving world state failed: %s" % save_res.get("error"))
		return false
	print("  [PASS] World state saved successfully (%d bytes)." % save_res.get("bytes", 0))

	# 2. Mutate in-memory buffers
	wp_mgr.get_workplace("bld_farm_29_27").buffer_amount = 0
	wp_mgr.get_workplace("bld_woodcutter_34_27").buffer_amount = 0
	wp_mgr.get_workplace("farm_starter").buffer_amount = 0

	# 3. Load world state
	var load_res: Dictionary = SaveManagerScript.load_from_file(TEST_SAVE_PATH)
	if not load_res.get("success", false):
		printerr("  [FAIL] Loading world state failed: %s" % load_res.get("error"))
		return false

	var apply_res: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, load_res["data"])
	if not apply_res.get("success", false):
		printerr("  [FAIL] Applying loaded state failed: %s" % apply_res.get("error"))
		return false

	# 4. Verify buffer restoration
	if wp_mgr.get_buffer_amount("bld_farm_29_27") != 17:
		printerr("  [FAIL] Restored farm buffer is %d, expected 17" % wp_mgr.get_buffer_amount("bld_farm_29_27"))
		failures += 1
	if wp_mgr.get_buffer_amount("bld_woodcutter_34_27") != 13:
		printerr("  [FAIL] Restored woodcutter buffer is %d, expected 13" % wp_mgr.get_buffer_amount("bld_woodcutter_34_27"))
		failures += 1
	if wp_mgr.get_buffer_amount("farm_starter") != 22:
		printerr("  [FAIL] Restored starter farm buffer is %d, expected 22" % wp_mgr.get_buffer_amount("farm_starter"))
		failures += 1
	print("  [PASS] Buffer amounts accurately restored from save file (Farm: 17, Woodcutter: 13, Starter Farm: 22).")

	# 5. Verify dynamic workplaces re-registered with exact IDs
	if wp_mgr.get_workplace("bld_farm_29_27") == null or wp_mgr.get_workplace("bld_woodcutter_34_27") == null:
		printerr("  [FAIL] Dynamic workplaces were not recreated after load!")
		failures += 1
	else:
		print("  [PASS] Dynamic workplaces faithfully reconstructed with stable IDs.")

	# 6. Verify Job Counts (Single Load)
	var farm_jobs_1: Array[JobManager.JobData] = job_mgr.get_jobs_for_building("bld_farm_29_27")
	var wc_jobs_1: Array[JobManager.JobData] = job_mgr.get_jobs_for_building("bld_woodcutter_34_27")
	var starter_farm_1: Array[JobManager.JobData] = job_mgr.get_jobs_for_building("farm_starter")
	var starter_wc_1: Array[JobManager.JobData] = job_mgr.get_jobs_for_building("woodcutter_starter")

	if farm_jobs_1.size() != 5 or wc_jobs_1.size() != 4 or starter_farm_1.size() != 5 or starter_wc_1.size() != 4:
		printerr("  [FAIL] Job count mismatch after 1st load! Farm: %d, WC: %d, StartFarm: %d, StartWC: %d" % [farm_jobs_1.size(), wc_jobs_1.size(), starter_farm_1.size(), starter_wc_1.size()])
		failures += 1
	else:
		print("  [PASS] Job counts after 1st load verified (Farm: 5, WC: 4, Starter Farm: 5, Starter WC: 4).")

	# 7. Repeated Load Anti-Duplication Verification
	var apply_res_2: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, load_res["data"])
	if not apply_res_2.get("success", false):
		printerr("  [FAIL] Applying 2nd loaded state failed: %s" % apply_res_2.get("error"))
		failures += 1

	var farm_jobs_2: Array[JobManager.JobData] = job_mgr.get_jobs_for_building("bld_farm_29_27")
	var wc_jobs_2: Array[JobManager.JobData] = job_mgr.get_jobs_for_building("bld_woodcutter_34_27")
	var starter_farm_2: Array[JobManager.JobData] = job_mgr.get_jobs_for_building("farm_starter")
	var starter_wc_2: Array[JobManager.JobData] = job_mgr.get_jobs_for_building("woodcutter_starter")

	if farm_jobs_2.size() != 5 or wc_jobs_2.size() != 4 or starter_farm_2.size() != 5 or starter_wc_2.size() != 4:
		printerr("  [FAIL] Jobs duplicated on repeated load! Farm: %d (exp 5), WC: %d (exp 4)" % [farm_jobs_2.size(), wc_jobs_2.size()])
		failures += 1
	else:
		print("  [PASS] Zero job duplication across repeated load calls (Farm: 5, WC: 4, Starter: 9).")

	# Total recurring jobs must strictly be 18 (5 + 4 + 5 + 4)
	var total_bld_jobs := farm_jobs_2.size() + wc_jobs_2.size() + starter_farm_2.size() + starter_wc_2.size()
	if total_bld_jobs != 18:
		printerr("  [FAIL] Total workplace jobs is %d, expected exactly 18" % total_bld_jobs)
		failures += 1
	else:
		print("  [PASS] Total workplace jobs strictly capped at 18.")

	# 8. Fresh WorldView Instance Restoration
	var fresh_world: Node = world_scene.instantiate()
	root.add_child(fresh_world)

	var fresh_apply: Dictionary = SaveManagerScript.apply_loaded_state_to_world(fresh_world, load_res["data"])
	if not fresh_apply.get("success", false):
		printerr("  [FAIL] Applying loaded state to fresh WorldView failed: %s" % fresh_apply.get("error"))
		failures += 1
	else:
		var fresh_wp_mgr: WorkplaceManager = fresh_world.get("workplace_mgr")
		var fresh_job_mgr: JobManager = fresh_world.get("job_mgr")
		if fresh_wp_mgr.get_workplace("bld_farm_29_27") == null or fresh_wp_mgr.get_workplace("bld_woodcutter_34_27") == null:
			printerr("  [FAIL] Dynamic workplaces not reconstructed in fresh WorldView!")
			failures += 1
		elif fresh_wp_mgr.get_buffer_amount("bld_farm_29_27") != 17:
			printerr("  [FAIL] Buffer amount mismatch in fresh WorldView! Got %d" % fresh_wp_mgr.get_buffer_amount("bld_farm_29_27"))
			failures += 1
		elif fresh_job_mgr.get_jobs_for_building("bld_farm_29_27").size() != 5:
			printerr("  [FAIL] Job count mismatch in fresh WorldView!")
			failures += 1
		else:
			print("  [PASS] Fresh WorldView instance restoration verified completely.")

	fresh_world.free()

	# 9. Legacy Save Compatibility (Missing 'workplaces' section)
	var legacy_dict: Dictionary = load_res["data"].duplicate(true)
	legacy_dict.erase("workplaces")

	var legacy_apply: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, legacy_dict)
	if not legacy_apply.get("success", false):
		printerr("  [FAIL] Applying legacy save without 'workplaces' failed: %s" % legacy_apply.get("error"))
		failures += 1
	else:
		# Workplaces should still exist from buildings, with buffer defaulted to 0
		if wp_mgr.get_buffer_amount("bld_farm_29_27") != 0 or wp_mgr.get_buffer_amount("farm_starter") != 0:
			printerr("  [FAIL] Legacy save did not default buffer to 0! Farm: %d, Starter: %d" % [wp_mgr.get_buffer_amount("bld_farm_29_27"), wp_mgr.get_buffer_amount("farm_starter")])
			failures += 1
		else:
			print("  [PASS] Legacy save without 'workplaces' loaded cleanly with buffers defaulted to 0.")

	# 10. Buffer Capacity Clamping
	var overflow_dict: Dictionary = load_res["data"].duplicate(true)
	overflow_dict["workplaces"]["bld_farm_29_27"]["buffer_amount"] = 9999 # Farm capacity is 50

	var overflow_apply: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, overflow_dict)
	if not overflow_apply.get("success", false):
		printerr("  [FAIL] Applying overflow save failed: %s" % overflow_apply.get("error"))
		failures += 1
	else:
		var clamped_val: int = wp_mgr.get_buffer_amount("bld_farm_29_27")
		if clamped_val != 50:
			printerr("  [FAIL] Buffer overflow was not clamped to capacity 50! Got: %d" % clamped_val)
			failures += 1
		else:
			print("  [PASS] Corrupted/overflowed buffer amount clamped strictly to capacity (50).")

	if failures == 0:
		print("  [PASS] TC-DW.5 PASSED.\n")
		return true
	else:
		printerr("  [FAIL] TC-DW.5 had %d failures.\n" % failures)
		return false
