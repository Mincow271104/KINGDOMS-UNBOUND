class_name JobManager
extends RefCounted
## Shared Job System for KINGDOMS UNBOUND.
## Manages job lifecycles (Available -> Reserved -> InProgress -> Completed/Cancelled).

enum JobState {
	AVAILABLE = 0,
	RESERVED = 1,
	IN_PROGRESS = 2,
	COMPLETED = 3,
	CANCELLED = 4
}

class JobData:
	var id: String
	var type: String # "farmer", "woodcutter", "builder", "hauler"
	var target_cell: Vector2i
	var target_building_id: String = ""
	var work_hours_required: float = 2.0
	var work_hours_done: float = 0.0
	var state: int = JobState.AVAILABLE
	var worker_id: String = ""
	var description: String = ""
	var priority: int = 1
	var is_recurring: bool = false
	var source_workplace_id: String = ""
	var source_cell: Vector2i = Vector2i.ZERO
	var dest_cell: Vector2i = Vector2i.ZERO
	var cargo_resource: String = ""
	var cargo_amount: int = 0
	var recipe_id: String = ""
	var workplace_channel_id: String = ""

var _jobs: Array[JobData] = []
var _next_job_id: int = 1

func create_job(
	type: String,
	target_cell: Vector2i,
	desc: String = "",
	building_id: String = "",
	duration_hours: float = 2.0,
	priority: int = 1,
	recurring: bool = false,
	recipe: String = "",
	channel_id: String = ""
) -> JobData:
	var job := JobData.new()
	job.id = "job_%d" % _next_job_id
	_next_job_id += 1
	job.type = type
	job.target_cell = target_cell
	job.target_building_id = building_id
	job.description = desc
	job.work_hours_required = duration_hours
	job.work_hours_done = 0.0
	job.state = JobState.AVAILABLE
	job.priority = priority
	job.is_recurring = recurring
	job.recipe_id = recipe
	job.workplace_channel_id = channel_id
	_jobs.append(job)
	return job

func create_hauling_job(workplace_id: String, source: Vector2i, dest: Vector2i, res_id: String, amount: int, desc: String = "", priority: int = 2) -> JobData:
	var job := JobData.new()
	job.id = "job_haul_%d" % _next_job_id
	_next_job_id += 1
	job.type = "hauler"
	job.target_cell = source
	job.source_cell = source
	job.dest_cell = dest
	job.source_workplace_id = workplace_id
	job.cargo_resource = res_id
	job.cargo_amount = amount
	job.description = desc
	job.work_hours_required = 0.5 # Fast pickup
	job.work_hours_done = 0.0
	job.state = JobState.AVAILABLE
	job.priority = priority
	_jobs.append(job)
	return job

var barracks_checker: Callable = Callable()

func set_barracks_checker(checker: Callable) -> void:
	barracks_checker = checker

func set_building_checker(checker: Callable) -> void:
	barracks_checker = checker

func _is_job_executable(job: JobData, wp_mgr: Object, resource_mgr: Node, custom_filter: Callable = Callable(), nav: GridNavigation = null) -> bool:
	if job.type == "guard":
		var b_id: String = job.target_building_id
		# Requirement 1: Guard job is invalid if target_building_id is empty
		if b_id == "":
			return false

		# Requirement 2: Prefer a valid per-call custom_filter when supplied.
		# It must be able to receive the specific Barracks ID and verify that building's active state.
		if custom_filter.is_valid():
			var argc := custom_filter.get_argument_count()
			if argc == 0:
				# Cannot verify a specific building ID
				return false
			if not bool(custom_filter.call(b_id)):
				return false
		# Requirement 3: Otherwise use barracks_checker, but only if it can check a specific Barracks ID.
		elif barracks_checker.is_valid():
			var argc := barracks_checker.get_argument_count()
			if argc == 0:
				# Cannot verify a specific building ID
				return false
			if not bool(barracks_checker.call(b_id)):
				return false
		# Requirement 4: If neither callback is available, return false.
		else:
			return false

		# Requirement 6: Keep the existing target walkability check.
		if nav != null and not nav.is_cell_walkable(job.target_cell):
			return false
		return true

	if job.type != "smith" or job.recipe_id == "":
		return true
	if wp_mgr == null or resource_mgr == null:
		return true
	var channel_id := job.workplace_channel_id
	if channel_id == "":
		channel_id = job.target_building_id
	var wp = wp_mgr.get_workplace(channel_id)
	if wp == null:
		return true
	# Check output buffer capacity
	if wp.buffer_amount >= wp.buffer_capacity:
		return false
	# Check input resources
	for in_res in wp.required_inputs:
		if resource_mgr.get_available_stock(in_res) < wp.required_inputs[in_res]:
			return false
	return true

## Finds the best reachable job matching the citizen's role, prioritized by priority score.
func request_job(citizen_id: String, role: String, citizen_cell: Vector2i, nav: GridNavigation, wp_mgr: Object = null, resource_mgr: Node = null, job_filter: Callable = Callable()) -> JobData:
	if role == "idle":
		return null
		
	var best_job: JobData = null
	var best_score := -999999
	
	for job in _jobs:
		if job.state != JobState.AVAILABLE:
			continue
		if job.type != role:
			continue
			
		# Check executability for crafting and guard jobs
		if not _is_job_executable(job, wp_mgr, resource_mgr, job_filter, nav):
			continue

		# Check reachability
		var check_target: Vector2i = job.source_cell if job.type == "hauler" else job.target_cell
		var path := nav.find_path(citizen_cell, check_target)
		if path.is_empty():
			continue
			
		var dist: int = path.size()
		# Score formula: priority has heavy weight, shorter distance breaks ties
		var score: int = (job.priority * 1000) - dist
		if score > best_score:
			best_score = score
			best_job = job
			
	if best_job != null:
		best_job.state = JobState.RESERVED
		best_job.worker_id = citizen_id
		
	return best_job

func boost_jobs_priority(job_type: String, boost_delta: int) -> int:
	var modified := 0
	for job in _jobs:
		if job.type == job_type and job.state == JobState.AVAILABLE:
			job.priority += boost_delta
			modified += 1
	return modified

func get_all_jobs() -> Array[JobData]:
	return _jobs

func get_jobs_for_building(building_id: String) -> Array[JobData]:
	var result: Array[JobData] = []
	for job in _jobs:
		if job.target_building_id == building_id or job.source_workplace_id == building_id or job.workplace_channel_id == building_id or (job.target_building_id != "" and job.target_building_id.begins_with(building_id)) or (job.workplace_channel_id != "" and job.workplace_channel_id.begins_with(building_id)):
			result.append(job)
	return result

func remove_jobs_for_building(building_id: String) -> void:
	var remaining: Array[JobData] = []
	for job in _jobs:
		var matches_bld := (job.target_building_id == building_id or job.source_workplace_id == building_id or job.workplace_channel_id == building_id or (job.target_building_id != "" and job.target_building_id.begins_with(building_id)) or (job.workplace_channel_id != "" and job.workplace_channel_id.begins_with(building_id)))
		if not matches_bld:
			remaining.append(job)
	_jobs = remaining

func clear_dynamic_jobs(preserve_building_ids: Array = ["farm_starter", "woodcutter_starter"]) -> void:
	var remaining: Array[JobData] = []
	for job in _jobs:
		# Preserve recurring starter jobs and reset transient runtime state
		if job.target_building_id in preserve_building_ids and job.is_recurring:
			job.state = JobState.AVAILABLE
			job.worker_id = ""
			job.work_hours_done = 0.0
			remaining.append(job)
		# Preserve non-building jobs if any
		elif job.target_building_id == "" and job.source_workplace_id == "":
			remaining.append(job)
	_jobs = remaining

func progress_job(job: JobData, delta_hours: float) -> bool:
	if job == null or job.state != JobState.IN_PROGRESS:
		return false
		
	job.work_hours_done += delta_hours
	if job.work_hours_done >= job.work_hours_required:
		complete_job(job)
		return true
	return false

func complete_job(job: JobData) -> void:
	if job == null:
		return
	if job.is_recurring:
		job.state = JobState.AVAILABLE
		job.work_hours_done = 0.0
		job.worker_id = ""
	else:
		job.state = JobState.COMPLETED
		job.worker_id = ""

func release_job(job: JobData) -> void:
	if job == null:
		return
	if job.state == JobState.RESERVED or job.state == JobState.IN_PROGRESS:
		job.state = JobState.AVAILABLE
		job.worker_id = ""

func cancel_job(job: JobData, _reason: String = "") -> void:
	if job == null:
		return
	job.state = JobState.CANCELLED
	job.worker_id = ""

func get_active_jobs_count() -> int:
	var count := 0
	for j in _jobs:
		if j.state == JobState.IN_PROGRESS or j.state == JobState.RESERVED:
			count += 1
	return count

func get_available_jobs_count() -> int:
	var count := 0
	for j in _jobs:
		if j.state == JobState.AVAILABLE:
			count += 1
	return count
