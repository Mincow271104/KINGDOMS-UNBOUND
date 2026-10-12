class_name JobManager
extends RefCounted
## Shared Job System for KINGDOMS UNBOUND.
## Manages job lifecycles (Available -> Reserved -> InProgress -> Completed/Cancelled).

const IsoMath = preload("res://scripts/utils/iso_math.gd")
const GridNavigation = preload("res://scripts/navigation/grid_navigation.gd")

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

var _jobs: Array[JobData] = []
var _next_job_id: int = 1

func create_job(type: String, target_cell: Vector2i, desc: String = "", building_id: String = "", duration_hours: float = 2.0) -> JobData:
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
	_jobs.append(job)
	return job

## Finds the best reachable job matching the citizen's role.
func request_job(citizen_id: String, role: String, citizen_cell: Vector2i, nav: GridNavigation) -> JobData:
	if role == "idle":
		return null
		
	var best_job: JobData = null
	var best_dist := 999999
	
	for job in _jobs:
		if job.state != JobState.AVAILABLE:
			continue
		if job.type != role:
			continue
			
		# Check reachability
		var path := nav.find_path(citizen_cell, job.target_cell)
		if path.is_empty():
			continue
			
		var dist: int = path.size()
		if dist < best_dist:
			best_dist = dist
			best_job = job
			
	if best_job != null:
		best_job.state = JobState.RESERVED
		best_job.worker_id = citizen_id
		
	return best_job

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
	job.state = JobState.COMPLETED
	# Release worker
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
