class_name CitizenController
extends Node2D
## Citizen Entity & Behavior State Machine for KINGDOMS UNBOUND.
## Implements pathfinding traversal, job execution, need decay, and explainable status.

signal citizen_selected(citizen: CitizenController)
signal citizen_died(citizen_id: String)

enum State {
	IDLE = 0,
	MOVING_TO_JOB = 1,
	WORKING = 2,
	SEEKING_FOOD = 3,
	RESTING = 4,
	HAULING = 5,
	GUARDING = 6
}

@export var citizen_id: String = ""
@export var citizen_name: String = ""
@export var role: String = "idle" # "farmer", "woodcutter", "builder", "hauler", "miner", "smith", "guard", "idle"

var current_cell: Vector2i = Vector2i(32, 32)
var current_state: int = State.IDLE
var status_reason: String = "Đang nghỉ ngơi tại quảng trường"
var barracks_checker: Callable = Callable()
var construction_checker: Callable = Callable()
var construction_handler: Callable = Callable()
var world_view: Node = null
var world_data: WorldGenerator.WorldData = null

# Needs (0..100)
var hunger: float = 10.0
var fatigue: float = 10.0
var health: float = 100.0
var morale: float = 70.0

var current_path: Array[Vector2i] = []
var active_job: JobManager.JobData = null

var nav: GridNavigation = null
var job_mgr: JobManager = null
var workplace_mgr: RefCounted = null
var move_speed_px: float = 48.0 # Pixel speed per second

# Logistics & Cargo
var carrying_resource: String = ""
var carrying_amount: int = 0
var carry_capacity: int = 10

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

func init_citizen(p_id: String, p_name: String, p_role: String, p_cell: Vector2i, p_nav: GridNavigation, p_job_mgr: JobManager, p_workplace_mgr: RefCounted = null) -> void:
	citizen_id = p_id
	citizen_name = p_name
	role = p_role
	current_cell = p_cell
	nav = p_nav
	job_mgr = p_job_mgr
	workplace_mgr = p_workplace_mgr
	position = IsoMath.map_to_local(current_cell)
	_update_reason()

func set_barracks_checker(checker: Callable) -> void:
	barracks_checker = checker

func set_construction_checker(checker: Callable) -> void:
	construction_checker = checker

func set_construction_handler(handler: Callable) -> void:
	construction_handler = handler

func set_world_view(wv: Node) -> void:
	world_view = wv

func _get_world_view() -> Node:
	if world_view != null:
		return world_view
	if is_inside_tree():
		return get_tree().root.find_child("WorldView", true, false)
	return null

func is_building_under_construction(b_id: String = "") -> bool:
	if b_id == "":
		return false
	if construction_checker.is_valid():
		var argc := construction_checker.get_argument_count()
		if argc != 0:
			return bool(construction_checker.call(b_id))
		return bool(construction_checker.call())
	var wv = _get_world_view()
	if wv != null and wv.get("world_data") != null:
		return BuildingSystem.is_building_under_construction(wv.world_data, b_id)
	if world_data != null:
		return BuildingSystem.is_building_under_construction(world_data, b_id)
	return false

func is_barracks_active(barracks_id: String = "") -> bool:
	if barracks_checker.is_valid():
		var argc := barracks_checker.get_argument_count()
		if argc != 0:
			return bool(barracks_checker.call(barracks_id))
		return bool(barracks_checker.call())
	var wv = _get_world_view()
	if wv != null and wv.get("world_data") != null:
		return BuildingSystem.is_barracks_active(wv.world_data, barracks_id)
	return false

func select() -> void:
	citizen_selected.emit(self)

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
		State.MOVING_TO_JOB, State.HAULING:
			_process_movement(delta)
		State.WORKING:
			_process_working(delta)
		State.GUARDING:
			_process_guarding(delta)
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
		if role == "guard" and not is_barracks_active():
			status_reason = "Cần Doanh Trại đang hoạt động"
			return

		var rm_node: Node = get_node_or_null("/root/ResourceManager") if (is_inside_tree() and has_node("/root/ResourceManager")) else null
		var filter_cb := func(b_id: String) -> bool:
			if role == "guard":
				return is_barracks_active(b_id)
			elif role == "builder":
				return is_building_under_construction(b_id)
			return true
		var job = job_mgr.request_job(citizen_id, role, current_cell, nav, workplace_mgr, rm_node, filter_cb)
		if job != null:
			active_job = job
			var target_dest: Vector2i = job.source_cell if job.type == "hauler" else job.target_cell
			var path := nav.find_path(current_cell, target_dest)
			if not path.is_empty():
				current_path = path
				current_state = State.MOVING_TO_JOB
				_update_reason()
			else:
				job_mgr.release_job(active_job)
				active_job = null
				status_reason = "Không thể tiếp cận nơi làm việc (bị chặn đường)"
		else:
			if role == "smith":
				status_reason = "Chờ nguyên liệu chế tác hoặc kho đệm xưởng giải phóng"
			elif role == "guard":
				if not is_barracks_active():
					status_reason = "Cần Doanh Trại đang hoạt động"
				else:
					status_reason = "Đang chờ phân công vị trí canh gác"
			elif role == "builder":
				status_reason = "Chờ công trình cần thi công xây dựng"
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
				if active_job.type == "hauler":
					_pickup_hauler_cargo()
				elif active_job.type == "guard":
					current_state = State.GUARDING
					active_job.state = JobManager.JobState.IN_PROGRESS
					_update_reason()
				else:
					current_state = State.WORKING
					active_job.state = JobManager.JobState.IN_PROGRESS
					_update_reason()
			else:
				current_state = State.IDLE
		State.HAULING:
			_deposit_hauler_cargo()
		State.SEEKING_FOOD:
			_eat_food()
		State.RESTING:
			status_reason = "Đang ngủ nghỉ hồi phục thể lực"

func _pickup_hauler_cargo() -> void:
	if active_job == null:
		current_state = State.IDLE
		return
		
	var picked_up := 0
	if workplace_mgr != null and workplace_mgr.has_method("pickup_from_buffer"):
		picked_up = workplace_mgr.pickup_from_buffer(active_job.source_workplace_id, carry_capacity)
	else:
		picked_up = mini(carry_capacity, active_job.cargo_amount)
		
	if picked_up > 0:
		carrying_resource = active_job.cargo_resource
		carrying_amount = picked_up
		var path := nav.find_path(current_cell, active_job.dest_cell)
		if not path.is_empty():
			current_path = path
			current_state = State.HAULING
			_update_reason()
		else:
			# Destination blocked: return goods
			if workplace_mgr != null and workplace_mgr.has_method("get_workplace"):
				var wp = workplace_mgr.get_workplace(active_job.source_workplace_id)
				if wp:
					wp.buffer_amount += picked_up
			carrying_amount = 0
			carrying_resource = ""
			job_mgr.release_job(active_job)
			active_job = null
			current_state = State.IDLE
			status_reason = "Đường vận chuyển về kho bị chặn"
	else:
		# Nothing available to haul
		job_mgr.complete_job(active_job)
		active_job = null
		current_state = State.IDLE
		status_reason = "Kho tạm đã hết hàng, sẵn sàng việc mới"

func _deposit_hauler_cargo() -> void:
	if carrying_amount > 0:
		var rm: Node = get_node("/root/ResourceManager") if (is_inside_tree() and has_node("/root/ResourceManager")) else null
		if rm != null:
			rm.add_resource(carrying_resource, carrying_amount)
		carrying_amount = 0
		carrying_resource = ""
		
	if active_job != null:
		job_mgr.complete_job(active_job)
		active_job = null
		
	current_state = State.IDLE
	status_reason = "Đã dỡ hàng vào kho an toàn"

func _process_working(delta: float) -> void:
	if active_job == null or job_mgr == null:
		current_state = State.IDLE
		return
		
	# 1 real second = 1 game hour at 1x speed
	var delta_hours := delta
	var tm := _get_time_manager()
	if tm != null:
		delta_hours = delta * float(tm.current_speed)

	if active_job.type == "builder":
		_process_building_work(delta_hours)
		return
		
	var completed := job_mgr.progress_job(active_job, delta_hours)
	if completed:
		# Production at workplace deposits to buffer (not central storage)
		if workplace_mgr != null and active_job != null:
			var target_wp_id: String = active_job.target_building_id
			if active_job.get("workplace_channel_id") != null and active_job.get("workplace_channel_id") != "":
				target_wp_id = active_job.get("workplace_channel_id")
			elif workplace_mgr.has_method("get_workplace_channel") and active_job.get("recipe_id") != null and active_job.get("recipe_id") != "":
				var ch = workplace_mgr.get_workplace_channel(target_wp_id, active_job.get("recipe_id"))
				if ch:
					target_wp_id = ch.id

			if active_job.type in ["farmer", "woodcutter", "miner", "quarryman", "smith"] or (workplace_mgr.has_method("has_workplace") and workplace_mgr.has_workplace(target_wp_id)):
				var season_mod := 1.0
				if tm != null and tm.has_method("get_farm_efficiency_modifier") and active_job.type == "farmer":
					season_mod = tm.get_farm_efficiency_modifier()
				var rm_node: Node = get_node_or_null("/root/ResourceManager") if (is_inside_tree() and has_node("/root/ResourceManager")) else null
				var produced_qty: int = workplace_mgr.produce_to_buffer(target_wp_id, season_mod, rm_node)
				if produced_qty > 0:
					status_reason = "Hoàn thành công việc, chuẩn bị việc mới"
				else:
					var wp_obj = workplace_mgr.get_workplace(target_wp_id)
					if wp_obj and wp_obj.buffer_amount >= wp_obj.buffer_capacity:
						status_reason = "Kho đệm xưởng đã đầy, chờ vận chuyển"
					else:
						status_reason = "Thiếu nguyên liệu chế tác tại xưởng"
		active_job = null
		current_state = State.IDLE

func _process_building_work(delta_hours: float) -> void:
	if active_job == null or job_mgr == null:
		current_state = State.IDLE
		return

	# Urgent needs interrupt work
	if hunger >= 70.0:
		job_mgr.release_job(active_job)
		active_job = null
		_seek_food()
		return
	if fatigue >= 85.0:
		job_mgr.release_job(active_job)
		active_job = null
		_seek_rest()
		return

	var b_id: String = active_job.target_building_id
	if b_id == "":
		job_mgr.cancel_job(active_job)
		active_job = null
		current_state = State.IDLE
		_update_reason()
		return

	# Advance construction
	var res: Dictionary = {}
	if construction_handler.is_valid():
		var argc := construction_handler.get_argument_count()
		if argc >= 2:
			res = construction_handler.call(b_id, delta_hours)
		else:
			res = construction_handler.call(delta_hours)
	else:
		var wv = _get_world_view()
		if wv != null and wv.has_method("advance_construction_work"):
			res = wv.advance_construction_work(b_id, delta_hours)
		elif world_data != null:
			res = BuildingSystem.advance_construction(b_id, delta_hours, world_data)
			if res.get("completed", false):
				var rm_node: Node = get_node_or_null("/root/ResourceManager") if (is_inside_tree() and has_node("/root/ResourceManager")) else null
				BuildingSystem.complete_building(b_id, world_data, rm_node)

	if not res.get("success", false):
		active_job = null
		current_state = State.IDLE
		status_reason = "Công trình xây dựng đã hoàn thành hoặc bị hủy"
		return

	if res.get("completed", false):
		active_job = null
		current_state = State.IDLE
		status_reason = "Công trình đã hoàn thành thi công"
		return

	status_reason = "Đang thi công xây dựng công trình (%.1f / %.1f giờ)" % [
		res.get("progress", 0.0),
		res.get("hours", 0.0)
	]

func _process_guarding(delta: float) -> void:
	if active_job == null or job_mgr == null:
		current_state = State.IDLE
		return

	# If the specific barracks for this job becomes inactive while on duty, stop duty
	var target_b_id: String = active_job.target_building_id if active_job != null else ""
	if not is_barracks_active(target_b_id):
		job_mgr.release_job(active_job)
		active_job = null
		current_state = State.IDLE
		status_reason = "Cần Doanh Trại đang hoạt động"
		return

	# If guard post became occupied/unwalkable, release duty
	if nav != null and not nav.is_cell_walkable(current_cell):
		job_mgr.release_job(active_job)
		active_job = null
		current_state = State.IDLE
		status_reason = "Không thể tiếp cận nơi làm việc (bị chặn đường)"
		return

	# Check urgent needs
	if hunger >= 70.0:
		job_mgr.release_job(active_job)
		active_job = null
		_seek_food()
		return
	if fatigue >= 85.0:
		job_mgr.release_job(active_job)
		active_job = null
		_seek_rest()
		return

	var delta_hours := delta
	var tm := _get_time_manager()
	if tm != null:
		delta_hours = delta * float(tm.current_speed)

	var completed := job_mgr.progress_job(active_job, delta_hours)
	if completed:
		active_job = null
		current_state = State.IDLE
		status_reason = "Hoàn thành ca gác, sẵn sàng nhiệm vụ mới"

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
		State.WORKING, State.HAULING, State.GUARDING:
			hunger = minf(100.0, hunger + 4.167)
			fatigue = minf(100.0, fatigue + 4.0)
		State.IDLE:
			hunger = minf(100.0, hunger + 2.0)
			fatigue = minf(100.0, fatigue + 1.0)
		State.RESTING:
			fatigue = maxf(0.0, fatigue - 12.5)

	# Starvation escalation logic
	var is_starving: bool = (hunger >= 100.0)
	if is_inside_tree() and has_node("/root/ResourceManager"):
		var rm: Node = get_node("/root/ResourceManager")
		if rm.has_method("is_starving") and rm.is_starving():
			is_starving = true
		elif rm.call("get_available_stock", "food") <= 0:
			is_starving = true
			
	if is_starving:
		# Stage 1: Morale drops by ~15/day (-0.625/hr), Fatigue +20/day (+0.833/hr)
		morale = maxf(0.0, morale - 0.625)
		fatigue = minf(100.0, fatigue + 0.833)
		# Stage 2: Health drops by ~5%/day (-0.208/hr)
		health = maxf(0.0, health - 0.208)
		if health <= 0.0:
			health = 0.0
			status_reason = "Đã qua đời vì suy kiệt"
			if active_job != null and job_mgr != null:
				job_mgr.release_job(active_job)
				active_job = null
			citizen_died.emit(citizen_id)
	else:
		# Recovery: when well-fed and not starving, health recovers by ~10%/day (+0.417/hr)
		if hunger < 50.0 and health < 100.0:
			health = minf(100.0, health + 0.417)

func is_alive() -> bool:
	return health > 0.0

func set_role(new_role: String) -> bool:
	if new_role == "guard" and not is_barracks_active():
		status_reason = "Cần Doanh Trại đang hoạt động"
		return false

	if role != new_role:
		if active_job != null and job_mgr != null:
			job_mgr.release_job(active_job)
			active_job = null
		role = new_role
		current_state = State.IDLE
		_update_reason()
	return true

func _update_reason() -> void:
	match current_state:
		State.IDLE:
			if role == "guard" and not is_barracks_active():
				status_reason = "Cần Doanh Trại đang hoạt động"
			else:
				status_reason = "Sẵn sàng làm việc (" + role + ")"
		State.MOVING_TO_JOB:
			if active_job != null and active_job.type == "guard":
				status_reason = "Đang di chuyển đến vị trí canh gác"
			else:
				status_reason = "Đang di chuyển đến vị trí làm việc"
		State.WORKING:
			if active_job != null and active_job.type == "smith":
				status_reason = "Đang luyện kim hoặc rèn công cụ tại xưởng"
			elif active_job != null and active_job.type == "builder":
				status_reason = "Đang thi công xây dựng công trình"
			else:
				status_reason = "Đang tích cực lao động sản xuất"
		State.GUARDING:
			status_reason = "Đang canh gác tại Doanh Trại"
		State.HAULING:
			status_reason = "Đang vận chuyển %d %s về kho" % [carrying_amount, carrying_resource]
		State.SEEKING_FOOD:
			status_reason = "Đang tìm lương thực"
		State.RESTING:
			status_reason = "Đang nghỉ ngơi hồi sức"
