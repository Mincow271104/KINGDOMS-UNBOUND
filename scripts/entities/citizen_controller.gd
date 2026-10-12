class_name CitizenController
extends Node2D
## Citizen Entity & Behavior State Machine for KINGDOMS UNBOUND.
## Implements pathfinding traversal, job execution, need decay, and explainable status.

signal citizen_selected(citizen: CitizenController)

const IsoMath = preload("res://scripts/utils/iso_math.gd")
const GridNavigation = preload("res://scripts/navigation/grid_navigation.gd")
const JobManager = preload("res://scripts/jobs/job_manager.gd")

enum State {
	IDLE = 0,
	MOVING_TO_JOB = 1,
	WORKING = 2,
	SEEKING_FOOD = 3,
	RESTING = 4
}

@export var citizen_id: String = ""
@export var citizen_name: String = ""
@export var role: String = "idle" # "farmer", "woodcutter", "builder", "hauler", "idle"

var current_cell: Vector2i = Vector2i(32, 32)
var current_state: int = State.IDLE
var status_reason: String = "Đang nghỉ ngơi tại quảng trường"

# Needs (0..100)
var hunger: float = 10.0
var fatigue: float = 10.0
var health: float = 100.0
var morale: float = 70.0

var current_path: Array[Vector2i] = []
var active_job: JobManager.JobData = null

var nav: GridNavigation = null
var job_mgr: JobManager = null
var move_speed_px: float = 48.0 # Pixel speed per second

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D")

func _ready() -> void:
	y_sort_enabled = true
	if sprite == null:
		sprite = get_node_or_null("Sprite2D")
	if sprite:
		sprite.offset = Vector2(-12.0, -30.0) # Ground contact foot pivot
		sprite.centered = false
		
	position = IsoMath.map_to_local(current_cell)
	
	# Connect to TimeManager for hourly need updates
	if is_inside_tree() and (Engine.has_singleton("TimeManager") or get_node_or_null("/root/TimeManager")) :
		var tm = get_node("/root/TimeManager")
		tm.hour_passed.connect(_on_hour_passed)

func init_citizen(p_id: String, p_name: String, p_role: String, p_cell: Vector2i, p_nav: GridNavigation, p_job_mgr: JobManager) -> void:
	citizen_id = p_id
	citizen_name = p_name
	role = p_role
	current_cell = p_cell
	nav = p_nav
	job_mgr = p_job_mgr
	position = IsoMath.map_to_local(current_cell)
	_update_reason()

func _get_time_manager() -> Node:
	if is_inside_tree() and has_node("/root/TimeManager"):
		return get_node("/root/TimeManager")
	return null

func _process(delta: float) -> void:
	# Check if simulation paused
	var tm := _get_time_manager()
	if tm != null and tm.is_paused():
		return
			
	match current_state:
		State.IDLE:
			_process_idle()
		State.MOVING_TO_JOB:
			_process_movement(delta)
		State.WORKING:
			_process_working(delta)
		State.SEEKING_FOOD:
			_process_movement(delta)
		State.RESTING:
			_process_resting(delta)

func _process_idle() -> void:
	if job_mgr == null or nav == null:
		return
		
	# Check urgent needs first
	if hunger >= 70.0:
		_seek_food()
		return
	if fatigue >= 85.0:
		_seek_rest()
		return
		
	# Request work
	if role != "idle":
		var job = job_mgr.request_job(citizen_id, role, current_cell, nav)
		if job != null:
			active_job = job
			var path := nav.find_path(current_cell, job.target_cell)
			if not path.is_empty():
				current_path = path
				current_state = State.MOVING_TO_JOB
				_update_reason()
			else:
				job_mgr.release_job(active_job)
				active_job = null
				status_reason = "Không thể tiếp cận nơi làm việc (bị chặn đường)"
		else:
			status_reason = "Chờ công việc phù hợp với vai trò: " + role
	else:
		status_reason = "Dân tự do (Chưa được phân công việc)"

func _process_movement(delta: float) -> void:
	if current_path.is_empty():
		_arrive_at_destination()
		return
		
	var target_cell := current_path[0]
	var target_local := IsoMath.map_to_local(target_cell)
	var dir := target_local - position
	var dist := dir.length()
	
	if dist <= move_speed_px * delta:
		position = target_local
		current_cell = target_cell
		current_path.remove_at(0)
		if current_path.is_empty():
			_arrive_at_destination()
	else:
		position += dir.normalized() * move_speed_px * delta

func _arrive_at_destination() -> void:
	match current_state:
		State.MOVING_TO_JOB:
			if active_job != null:
				current_state = State.WORKING
				active_job.state = JobManager.JobState.IN_PROGRESS
				_update_reason()
			else:
				current_state = State.IDLE
		State.SEEKING_FOOD:
			_eat_food()
		State.RESTING:
			status_reason = "Đang ngủ nghỉ hồi phục thể lực"

func _process_working(delta: float) -> void:
	if active_job == null or job_mgr == null:
		current_state = State.IDLE
		return
		
	# 1 real second = 1 game hour at 1x speed
	var delta_hours := delta
	var tm := _get_time_manager()
	if tm != null:
		delta_hours = delta * float(tm.current_speed)
		
	var completed := job_mgr.progress_job(active_job, delta_hours)
	if completed:
		active_job = null
		current_state = State.IDLE
		status_reason = "Hoàn thành công việc, chuẩn bị việc mới"

func _process_resting(delta: float) -> void:
	var delta_hours := delta
	var tm := _get_time_manager()
	if tm != null:
		delta_hours = delta * float(tm.current_speed)
		
	fatigue = maxf(0.0, fatigue - 12.5 * delta_hours)
	if fatigue <= 15.0:
		current_state = State.IDLE
		_update_reason()

func _seek_food() -> void:
	current_state = State.SEEKING_FOOD
	status_reason = "Đang đói, đi tìm lương thực tại kho"
	# Navigate to plaza / storehouse
	if nav:
		current_path = nav.find_path(current_cell, Vector2i(32, 32))

func _eat_food() -> void:
	hunger = maxf(0.0, hunger - 50.0)
	current_state = State.IDLE
	status_reason = "Đã ăn no, sẵn sàng làm việc"

func _seek_rest() -> void:
	current_state = State.RESTING
	status_reason = "Quá kiệt sức, tìm nơi nghỉ ngơi"
	if nav:
		current_path = nav.find_path(current_cell, Vector2i(31, 35))

func _on_hour_passed(_hour: int, _day: int) -> void:
	match current_state:
		State.WORKING:
			hunger = minf(100.0, hunger + 4.167)
			fatigue = minf(100.0, fatigue + 4.0)
		State.IDLE:
			hunger = minf(100.0, hunger + 2.0)
			fatigue = minf(100.0, fatigue + 1.0)
		State.RESTING:
			fatigue = maxf(0.0, fatigue - 12.5)

	# Health impact from extreme starvation
	if hunger >= 100.0:
		health = maxf(0.0, health - 0.2) # ~5% per day
		morale = maxf(0.0, morale - 0.6)

func set_role(new_role: String) -> void:
	if role != new_role:
		if active_job != null and job_mgr != null:
			job_mgr.release_job(active_job)
			active_job = null
		role = new_role
		current_state = State.IDLE
		_update_reason()

func _update_reason() -> void:
	match current_state:
		State.IDLE:
			status_reason = "Sẵn sàng làm việc (" + role + ")"
		State.MOVING_TO_JOB:
			status_reason = "Đang di chuyển đến vị trí làm việc"
		State.WORKING:
			status_reason = "Đang tích cực lao động sản xuất"
		State.SEEKING_FOOD:
			status_reason = "Đang tìm lương thực"
		State.RESTING:
			status_reason = "Đang nghỉ ngơi hồi sức"
