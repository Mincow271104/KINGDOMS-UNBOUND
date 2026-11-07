extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — BUG-002: Job Lifecycle Pruning
## Authoritative Coverage: TC-JOB.1 through TC-JOB.10 with Fail-Closed Assertions

const JobManagerScript = preload("res://scripts/jobs/job_manager.gd")
const WorkplaceManagerScript = preload("res://scripts/economy/workplace_manager.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const CitizenControllerScript = preload("res://scripts/entities/citizen_controller.gd")
const GridNavigationScript = preload("res://scripts/navigation/grid_navigation.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")

var frame_count: int = 0
var all_passed: bool = true
var test_results: Array[Dictionary] = []

func _init() -> void:
	print("\n========================================================")
	print("  STARTING BUG-002 JOB LIFECYCLE PRUNING TEST SUITE")
	print("========================================================\n")

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count == 2:
		_run_all_tests()
	return false

func _record(test_id: String, passed: bool, message: String) -> void:
	test_results.append({"id": test_id, "passed": passed, "message": message})
	if passed:
		print("  [PASS] %s: %s" % [test_id, message])
	else:
		printerr("  [FAIL] %s: %s" % [test_id, message])
		all_passed = false

func _run_all_tests() -> void:
	_test_tc_job_1_completed_non_recurring_pruned()
	_test_tc_job_2_cancelled_non_recurring_pruned()
	_test_tc_job_3_recurring_job_preserved()
	_test_tc_job_4_active_and_in_progress_jobs_preserved()
	_test_tc_job_5_citizen_completion_cleanup_valid()
	_test_tc_job_6_workplace_hauling_pending_check()
	_test_tc_job_7_zero_duplicate_pending_hauling_jobs()
	_test_tc_job_8_1000_cycles_bounded_size()
	_test_tc_job_9_bounded_terminal_history()
	_test_tc_job_10_clear_dynamic_jobs_compatibility()

	var total_tests := test_results.size()
	var passed_count := 0
	for r in test_results:
		if r["passed"]:
			passed_count += 1

	print("\n--------------------------------------------------------")
	print("  BUG-002 RESULTS: %d / %d Tests Passed" % [passed_count, total_tests])
	if all_passed and passed_count == total_tests:
		print("  ALL %d BUG-002 JOB LIFECYCLE PRUNING TESTS PASSED! (Exit Code 0)" % total_tests)
		print("--------------------------------------------------------\n")
		quit(0)
	else:
		printerr("  BUG-002 TEST SUITE FAILED! (Exit Code 1)")
		print("--------------------------------------------------------\n")
		quit(1)

# TC-JOB.1: Completed non-recurring job removed from active registry
func _test_tc_job_1_completed_non_recurring_pruned() -> void:
	var jm = JobManagerScript.new()
	var haul_job = jm.create_hauling_job("farm_1", Vector2i(5, 5), Vector2i(10, 10), "food", 10, "Test Haul")
	var build_job = jm.create_job("builder", Vector2i(20, 20), "Test Build", "bld_house_1", 2.0, 1, false)

	if jm.get_all_jobs().size() != 2:
		_record("TC-JOB.1", false, "Failed to register initial non-recurring jobs. Size: %d" % jm.get_all_jobs().size())
		return

	# Complete haul job
	jm.complete_job(haul_job)
	var active_after_haul := jm.get_all_jobs()
	if haul_job.state != JobManagerScript.JobState.COMPLETED:
		_record("TC-JOB.1", false, "Haul job state is not COMPLETED: %d" % haul_job.state)
		return
	if active_after_haul.has(haul_job) or haul_job in jm._jobs:
		_record("TC-JOB.1", false, "Completed haul job still present in active registry!")
		return
	if not active_after_haul.has(build_job):
		_record("TC-JOB.1", false, "Active build job was inadvertently removed!")
		return

	# Complete builder job
	jm.complete_job(build_job)
	if build_job.state != JobManagerScript.JobState.COMPLETED:
		_record("TC-JOB.1", false, "Builder job state is not COMPLETED: %d" % build_job.state)
		return
	if not jm.get_all_jobs().is_empty():
		_record("TC-JOB.1", false, "Active registry is not empty after completing all non-recurring jobs!")
		return

	_record("TC-JOB.1", true, "Completed non-recurring jobs are pruned from active registry while retaining COMPLETED state")

# TC-JOB.2: Cancelled non-recurring job removed from active registry
func _test_tc_job_2_cancelled_non_recurring_pruned() -> void:
	var jm = JobManagerScript.new()
	var build_job = jm.create_job("builder", Vector2i(15, 15), "Cancelled House", "bld_house_2", 2.0, 1, false)

	if jm.get_all_jobs().size() != 1:
		_record("TC-JOB.2", false, "Failed to register builder job.")
		return

	jm.cancel_job(build_job, "Demolished prior to start")
	if build_job.state != JobManagerScript.JobState.CANCELLED:
		_record("TC-JOB.2", false, "Job state is not CANCELLED: %d" % build_job.state)
		return
	if jm.get_all_jobs().has(build_job) or build_job in jm._jobs:
		_record("TC-JOB.2", false, "Cancelled non-recurring job still present in active registry!")
		return

	_record("TC-JOB.2", true, "Cancelled non-recurring jobs are cleanly pruned from active registry")

# TC-JOB.3: Recurring job preserved upon completion
func _test_tc_job_3_recurring_job_preserved() -> void:
	var jm = JobManagerScript.new()
	var farm_job = jm.create_job("farmer", Vector2i(36, 35), "Farm crop", "farm_starter", 2.0, 1, true)

	farm_job.state = JobManagerScript.JobState.IN_PROGRESS
	farm_job.worker_id = "cit_1"
	farm_job.work_hours_done = 2.0

	jm.complete_job(farm_job)

	if farm_job.state != JobManagerScript.JobState.AVAILABLE:
		_record("TC-JOB.3", false, "Recurring job state should reset to AVAILABLE, got: %d" % farm_job.state)
		return
	if farm_job.worker_id != "":
		_record("TC-JOB.3", false, "Recurring job worker_id should reset to empty, got: '%s'" % farm_job.worker_id)
		return
	if farm_job.work_hours_done != 0.0:
		_record("TC-JOB.3", false, "Recurring job work_hours_done should reset to 0.0, got: %f" % farm_job.work_hours_done)
		return
	if not jm.get_all_jobs().has(farm_job) or not (farm_job in jm._jobs):
		_record("TC-JOB.3", false, "Recurring job was improperly pruned from active registry!")
		return

	_record("TC-JOB.3", true, "Recurring jobs reset to AVAILABLE and remain in active registry upon completion")

# TC-JOB.4: Active and in-progress jobs preserved
func _test_tc_job_4_active_and_in_progress_jobs_preserved() -> void:
	var jm = JobManagerScript.new()
	var j_avail = jm.create_job("farmer", Vector2i(1, 1), "Avail", "farm_1", 2.0, 1, true)
	var j_res = jm.create_hauling_job("farm_1", Vector2i(2, 2), Vector2i(3, 3), "food", 5)
	j_res.state = JobManagerScript.JobState.RESERVED
	var j_prog = jm.create_job("builder", Vector2i(4, 4), "Prog", "bld_1", 2.0, 1, false)
	j_prog.state = JobManagerScript.JobState.IN_PROGRESS

	if jm.get_active_jobs_count() != 2:
		_record("TC-JOB.4", false, "get_active_jobs_count expected 2, got: %d" % jm.get_active_jobs_count())
		return
	if jm.get_available_jobs_count() != 1:
		_record("TC-JOB.4", false, "get_available_jobs_count expected 1, got: %d" % jm.get_available_jobs_count())
		return

	# Add and complete an unrelated non-recurring job
	var j_temp = jm.create_hauling_job("temp", Vector2i(0, 0), Vector2i(0, 0), "wood", 2)
	jm.complete_job(j_temp)

	if jm.get_active_jobs_count() != 2:
		_record("TC-JOB.4", false, "Active jobs count disturbed by temp job completion!")
		return
	if jm.get_available_jobs_count() != 1:
		_record("TC-JOB.4", false, "Available jobs count disturbed by temp job completion!")
		return
	if not (j_avail in jm._jobs and j_res in jm._jobs and j_prog in jm._jobs):
		_record("TC-JOB.4", false, "Active/in-progress jobs were lost from registry!")
		return

	_record("TC-JOB.4", true, "Active, reserved, and in-progress jobs are strictly preserved")

# TC-JOB.5: Citizen completion and cleanup references remain valid
func _test_tc_job_5_citizen_completion_cleanup_valid() -> void:
	var jm = JobManagerScript.new()
	var cit = CitizenControllerScript.new()
	var job = jm.create_hauling_job("wp_1", Vector2i(10, 10), Vector2i(20, 20), "food", 10)

	cit.job_mgr = jm
	cit.active_job = job
	cit.current_state = CitizenControllerScript.State.WORKING
	cit.carrying_resource = "food"
	cit.carrying_amount = 0 # Empty cargo ready to finish

	cit._deposit_hauler_cargo()

	if cit.active_job != null:
		_record("TC-JOB.5", false, "Citizen active_job was not cleared upon deposit completion!")
		cit.free()
		return
	if cit.current_state != CitizenControllerScript.State.IDLE:
		_record("TC-JOB.5", false, "Citizen current_state should be IDLE, got: %d" % cit.current_state)
		cit.free()
		return
	if job.state != JobManagerScript.JobState.COMPLETED:
		_record("TC-JOB.5", false, "Completed job reference state is not COMPLETED: %d" % job.state)
		cit.free()
		return
	if jm.get_all_jobs().has(job):
		_record("TC-JOB.5", false, "Completed job was not pruned from job manager!")
		cit.free()
		return

	cit.free()
	_record("TC-JOB.5", true, "Citizen job completion correctly clears active_job and prunes job without dangling references")

# TC-JOB.6: Workplace hauling pending check behaves correctly with pruned jobs
func _test_tc_job_6_workplace_hauling_pending_check() -> void:
	var jm = JobManagerScript.new()
	var wm = WorkplaceManagerScript.new()
	wm.register_workplace("quarry_test", "quarry", Vector2i(29, 27), Vector2i(2, 2), Vector2i(28, 27), "stone", 50, 5.0, 5)

	# No jobs initially
	if wm._has_pending_hauling_job(jm, "quarry_test"):
		_record("TC-JOB.6", false, "Empty job manager should not report pending hauling job")
		return

	# Add hauling job
	var haul_job = jm.create_hauling_job("quarry_test", Vector2i(28, 27), Vector2i(32, 29), "stone", 10)
	if not wm._has_pending_hauling_job(jm, "quarry_test"):
		_record("TC-JOB.6", false, "Expected pending hauling job to be true when AVAILABLE")
		return

	haul_job.state = JobManagerScript.JobState.IN_PROGRESS
	if not wm._has_pending_hauling_job(jm, "quarry_test"):
		_record("TC-JOB.6", false, "Expected pending hauling job to be true when IN_PROGRESS")
		return

	# Complete job
	jm.complete_job(haul_job)
	if wm._has_pending_hauling_job(jm, "quarry_test"):
		_record("TC-JOB.6", false, "Expected pending hauling job to be false after completion and pruning")
		return

	_record("TC-JOB.6", true, "WorkplaceManager._has_pending_hauling_job correctly transitions false -> true -> false on pruning")

# TC-JOB.7: Zero duplicate pending hauling jobs across multiple simulation cycles
func _test_tc_job_7_zero_duplicate_pending_hauling_jobs() -> void:
	var jm = JobManagerScript.new()
	var wm = WorkplaceManagerScript.new()
	wm.register_workplace("mine_test", "mine", Vector2i(40, 40), Vector2i(2, 2), Vector2i(39, 40), "iron_ore", 50, 5.0, 5)
	wm.register_dropoff("storehouse_test", "storehouse", Vector2i(32, 29))

	for cycle in range(5):
		wm.produce_to_buffer("mine_test", 10.0) # Fills buffer to threshold
		var created := wm.update_hauling_jobs(jm)
		if created != 1:
			_record("TC-JOB.7", false, "Cycle %d: Expected exactly 1 hauling job created, got %d" % [cycle, created])
			return

		# Find the created job and complete it
		var jobs := jm.get_all_jobs()
		if jobs.size() != 1:
			_record("TC-JOB.7", false, "Cycle %d: Expected exactly 1 active job in JobManager, got %d" % [cycle, jobs.size()])
			return

		var h_job: JobManagerScript.JobData = jobs[0]
		jm.complete_job(h_job)

		# Verify registry is empty immediately
		if not jm.get_all_jobs().is_empty():
			_record("TC-JOB.7", false, "Cycle %d: Active jobs not empty after hauling completion" % cycle)
			return

	_record("TC-JOB.7", true, "5 consecutive production/hauling cycles maintain zero duplicate pending jobs and zero bloat")

# TC-JOB.8: 1000 completion/cancellation cycles maintain strictly bounded _jobs size
func _test_tc_job_8_1000_cycles_bounded_size() -> void:
	var jm = JobManagerScript.new()

	# Register 4 recurring base jobs (farm, woodcutter, quarry, mine)
	jm.create_job("farmer", Vector2i(1, 1), "Farm", "farm_base", 2.0, 1, true)
	jm.create_job("woodcutter", Vector2i(2, 2), "Lumber", "woodcutter_base", 2.0, 1, true)
	jm.create_job("quarryman", Vector2i(3, 3), "Quarry", "quarry_base", 2.0, 1, true)
	jm.create_job("miner", Vector2i(4, 4), "Mine", "mine_base", 2.0, 1, true)

	if jm.get_all_jobs().size() != 4:
		_record("TC-JOB.8", false, "Base recurring jobs count mismatch. Expected 4, got: %d" % jm.get_all_jobs().size())
		return

	# Execute 1000 dynamic job lifecycles
	for i in range(1000):
		if i % 2 == 0:
			var haul = jm.create_hauling_job("wp_%d" % i, Vector2i(i, i), Vector2i(i + 1, i + 1), "food", 10)
			haul.state = JobManagerScript.JobState.IN_PROGRESS
			jm.complete_job(haul)
		else:
			var bld = jm.create_job("builder", Vector2i(i, i), "Build %d" % i, "bld_%d" % i, 2.0, 1, false)
			bld.state = JobManagerScript.JobState.RESERVED
			jm.cancel_job(bld, "Cancelled")

	var final_size := jm.get_all_jobs().size()
	if final_size != 4:
		_record("TC-JOB.8", false, "Registry bloat detected! Expected exactly 4 active jobs, got: %d" % final_size)
		return

	_record("TC-JOB.8", true, "1000 completion/cancellation cycles maintained strictly bounded active registry size (exactly 4)")

# TC-JOB.9: Bounded terminal history and callback safety
func _test_tc_job_9_bounded_terminal_history() -> void:
	var jm = JobManagerScript.new()

	# Complete 80 jobs (exceeding MAX_TERMINAL_HISTORY of 50)
	var last_job: JobManagerScript.JobData = null
	for i in range(80):
		var j = jm.create_hauling_job("wp", Vector2i.ZERO, Vector2i.ZERO, "food", 1)
		jm.complete_job(j)
		last_job = j

	var history := jm.get_recent_terminal_jobs()
	if history.size() != JobManagerScript.MAX_TERMINAL_HISTORY:
		_record("TC-JOB.9", false, "Terminal history size expected %d, got: %d" % [JobManagerScript.MAX_TERMINAL_HISTORY, history.size()])
		return
	if jm.get_terminal_jobs_count() != JobManagerScript.MAX_TERMINAL_HISTORY:
		_record("TC-JOB.9", false, "get_terminal_jobs_count expected %d, got: %d" % [JobManagerScript.MAX_TERMINAL_HISTORY, jm.get_terminal_jobs_count()])
		return
	if not history.has(last_job):
		_record("TC-JOB.9", false, "Latest completed job missing from terminal history ring buffer")
		return

	_record("TC-JOB.9", true, "Terminal history ring buffer is strictly bounded at %d elements" % JobManagerScript.MAX_TERMINAL_HISTORY)

# TC-JOB.10: Save/load and clear_dynamic_jobs compatibility
func _test_tc_job_10_clear_dynamic_jobs_compatibility() -> void:
	var jm = JobManagerScript.new()

	# Add starter recurring jobs
	var farm_starter = jm.create_job("farmer", Vector2i(36, 35), "Starter Farm", "farm_starter", 2.0, 1, true)
	var wood_starter = jm.create_job("woodcutter", Vector2i(26, 30), "Starter Wood", "woodcutter_starter", 2.0, 1, true)
	farm_starter.state = JobManagerScript.JobState.IN_PROGRESS
	farm_starter.worker_id = "cit_1"
	farm_starter.work_hours_done = 1.2

	# Add dynamic workplace job and hauling job
	jm.create_job("quarryman", Vector2i(20, 20), "Quarry", "quarry_dyn", 2.0, 1, true)
	var haul_dyn = jm.create_hauling_job("farm_starter", Vector2i(35, 35), Vector2i(32, 29), "food", 10)
	jm.complete_job(haul_dyn)

	# Clear dynamic jobs preserving starter buildings
	jm.clear_dynamic_jobs(["farm_starter", "woodcutter_starter"])

	var preserved_jobs := jm.get_all_jobs()
	if preserved_jobs.size() != 2:
		_record("TC-JOB.10", false, "Expected exactly 2 preserved starter jobs, got: %d" % preserved_jobs.size())
		return
	if farm_starter.state != JobManagerScript.JobState.AVAILABLE or farm_starter.worker_id != "" or farm_starter.work_hours_done != 0.0:
		_record("TC-JOB.10", false, "farm_starter runtime state was not properly reset on clear_dynamic_jobs")
		return
	if jm.get_terminal_jobs_count() != 0:
		_record("TC-JOB.10", false, "clear_dynamic_jobs should reset terminal history, got: %d" % jm.get_terminal_jobs_count())
		return

	_record("TC-JOB.10", true, "clear_dynamic_jobs preserves starter recurring jobs, resets runtime state, and clears terminal history")
