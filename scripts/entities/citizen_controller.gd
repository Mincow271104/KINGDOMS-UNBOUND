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
var workplace_id: String = ""

var current_cell: Vector2i = Vector2i(32, 32)
var current_state: int = State.IDLE
var status_reason: String = "Đang nghỉ ngơi tại quảng trường"
var barracks_checker: Callable = Callable()
var construction_checker: Callable = Callable()
var construction_handler: Callable = Callable()
var world_view: Node = null
var world_data: WorldGenerator.WorldData = null
var event_system: RefCounted = null

# Needs (0..100)
var hunger: float = 10.0
var fatigue: float = 10.0
var health: float = 100.0
var morale: float = 70.0

var current_path: Array[Vector2i] = []
var active_job: JobManager.JobData = null
var _death_processed: bool = false
var death_cause: String = ""
var _custom_resource_mgr: Object = null
var _custom_time_mgr: Object = null

var nav: GridNavigation = null
var job_mgr: JobManager = null
var workplace_mgr: RefCounted = null
var move_speed_px: float = 48.0 # Pixel speed per second

# Vocational Skill Progression (Package 2B)
var skill_data: CitizenSkillData = null

# Logistics & Cargo
var carrying_resource: String = ""
var carrying_amount: int = 0
var carry_capacity: int = 10

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D")

func _init() -> void:
	if skill_data == null:
		skill_data = CitizenSkillData.new()

func _ready() -> void:
	if skill_data == null:
		skill_data = CitizenSkillData.new()
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
	_death_processed = false
	if skill_data == null:
		skill_data = CitizenSkillData.new()
	position = IsoMath.map_to_local(current_cell)
	_update_reason()

func get_skill_data() -> CitizenSkillData:
	if skill_data == null:
		skill_data = CitizenSkillData.new()
	return skill_data

func get_skill_efficiency(vocation_or_job: String) -> float:
	return get_skill_data().get_efficiency(vocation_or_job)

func award_work_xp(vocation_or_job: String, amount: float) -> bool:
	return get_skill_data().add_xp(vocation_or_job, amount)

func get_effective_move_speed() -> float:
	var hauler_mult: float = 1.0
	if role == "hauler" or (active_job != null and active_job.type == "hauler"):
		hauler_mult = get_skill_efficiency("hauling")
	return move_speed_px * hauler_mult

func serialize_skills() -> Dictionary:
	return get_skill_data().serialize()

func deserialize_skills(data: Variant) -> void:
	get_skill_data().deserialize(data)

func set_barracks_checker(checker: Callable) -> void:
	barracks_checker = checker

func set_construction_checker(checker: Callable) -> void:
	construction_checker = checker

func set_construction_handler(handler: Callable) -> void:
	construction_handler = handler

func set_world_view(wv: Node) -> void:
	world_view = wv

func set_event_system(es: RefCounted) -> void:
	event_system = es

func _get_world_view() -> Node:
	if world_view != null:
		return world_view
	if is_inside_tree():
		return get_tree().root.find_child("WorldView", true, false)
	return null

func _get_event_system() -> RefCounted:
	if event_system != null:
		return event_system
	var wv := _get_world_view()
	if wv != null and wv.get("event_system") != null:
		return wv.get("event_system")
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

func set_custom_resource_manager(rm: Object) -> void:
	_custom_resource_mgr = rm

func set_custom_time_manager(tm: Object) -> void:
	_custom_time_mgr = tm

func _get_resource_manager() -> Object:
	if _custom_resource_mgr != null and is_instance_valid(_custom_resource_mgr):
		return _custom_resource_mgr
	if is_inside_tree() and has_node("/root/ResourceManager"):
		return get_node("/root/ResourceManager")
	var ml = Engine.get_main_loop()
	if ml is SceneTree and ml.root != null:
		var rm = ml.root.get_node_or_null("ResourceManager")
		if rm != null:
			return rm
	return null

func _is_central_food_available() -> bool:
	var rm := _get_resource_manager()
	if rm == null:
		return true
	if rm.has_method("get_available_stock"):
		if int(rm.call("get_available_stock", EconomyConfig.RES_FOOD)) <= 0:
			return false
	if rm.has_method("is_starving") and bool(rm.call("is_starving")):
		return false
	return true

func _get_time_manager() -> Object:
	if _custom_time_mgr != null and is_instance_valid(_custom_time_mgr):
		return _custom_time_mgr
	if is_inside_tree() and has_node("/root/TimeManager"):
		return get_node("/root/TimeManager")
	var ml = Engine.get_main_loop()
	if ml is SceneTree and ml.root != null:
		var tm = ml.root.get_node_or_null("TimeManager")
		if tm != null:
			return tm
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
	if hunger >= 70.0 and _is_central_food_available():
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

		var rm_node: Node = _get_resource_manager() if (_get_resource_manager() is Node) else null
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
			if hunger >= 70.0 and not _is_central_food_available():
				status_reason = "Kho lương thực trống rỗng (Đang đói)"
			elif role == "smith":
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
		if hunger >= 70.0 and not _is_central_food_available():
			status_reason = "Kho lương thực trống rỗng (Đang đói)"
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

	var speed_mult: float = 1.0
	var tm := _get_time_manager()
	if tm != null and tm.get("current_speed") != null:
		speed_mult = float(tm.get("current_speed"))
	if speed_mult <= 0.0:
		return
	var step_dist: float = get_effective_move_speed() * delta * speed_mult

	if dist <= step_dist:
		position = target_local
		current_cell = target_cell
		current_path.remove_at(0)
		if current_path.is_empty():
			_arrive_at_destination()
	else:
		position += dir.normalized() * step_dist

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
	if carrying_amount <= 0:
		if active_job != null:
			job_mgr.complete_job(active_job)
			active_job = null
		current_state = State.IDLE
		status_reason = "Không có hàng để dỡ"
		return

	var delivered_amount: int = carrying_amount
	var delivered_res: String = carrying_resource
	var rm: Object = _get_resource_manager()
	var added: int = 0
	if rm != null and rm.has_method("add_resource"):
		added = rm.add_resource(delivered_res, delivered_amount)
	else:
		added = delivered_amount

	carrying_amount -= added

	if carrying_amount <= 0:
		carrying_amount = 0
		carrying_resource = ""
		# Full cargo batch successfully deposited: award +10 hauling XP
		award_work_xp("hauling", 10.0)
		if active_job != null:
			job_mgr.complete_job(active_job)
			active_job = null
		current_state = State.IDLE
		status_reason = "Đã dỡ hàng vào kho an toàn"
	else:
		# Partial deposit: central storage space was insufficient to receive full batch.
		# Remaining cargo is safely preserved in hauler inventory (no loss, no duplication).
		# Zero XP awarded until complete batch is deposited.
		if active_job != null:
			job_mgr.release_job(active_job)
			active_job = null
		current_state = State.IDLE
		status_reason = "Kho trung tâm đã đầy, còn giữ %d %s" % [carrying_amount, carrying_resource]

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
		
	var skill_mult := get_skill_efficiency(active_job.type)
	var effective_work_hours := delta_hours * skill_mult
	var completed := job_mgr.progress_job(active_job, effective_work_hours)
	if completed:
		# Production at workplace deposits to buffer (not central storage)
		if workplace_mgr != null and active_job != null:
			var job_type: String = active_job.type
			var target_wp_id: String = active_job.target_building_id
			if active_job.get("workplace_channel_id") != null and active_job.get("workplace_channel_id") != "":
				target_wp_id = active_job.get("workplace_channel_id")
			elif workplace_mgr.has_method("get_workplace_channel") and active_job.get("recipe_id") != null and active_job.get("recipe_id") != "":
				var ch = workplace_mgr.get_workplace_channel(target_wp_id, active_job.get("recipe_id"))
				if ch:
					target_wp_id = ch.id

			if active_job.type in ["farmer", "woodcutter", "miner", "quarryman", "smith"] or (workplace_mgr.has_method("has_workplace") and workplace_mgr.has_workplace(target_wp_id)):
				var season_mod := 1.0
				if active_job.type == "farmer":
					if tm != null and tm.has_method("get_farm_efficiency_modifier"):
						season_mod = tm.get_farm_efficiency_modifier()
					var es := _get_event_system()
					if es != null and es.has_method("get_farm_production_multiplier"):
						var cur_day: int = int(tm.get("current_day")) if (tm != null and tm.get("current_day") != null) else -1
						season_mod = float(es.call("get_farm_production_multiplier", season_mod, cur_day))
				var rm_node: Node = get_node_or_null("/root/ResourceManager") if (is_inside_tree() and has_node("/root/ResourceManager")) else null

				var expected_qty: int = 1
				if workplace_mgr.has_method("get_expected_cycle_production"):
					expected_qty = workplace_mgr.get_expected_cycle_production(target_wp_id, season_mod)
				elif workplace_mgr.has_method("get_workplace"):
					var wp_obj = workplace_mgr.get_workplace(target_wp_id)
					if wp_obj != null:
						if wp_obj.has_recipe():
							expected_qty = wp_obj.output_amount
						else:
							var prod: float = wp_obj.base_production_per_cycle
							if wp_obj.output_resource == EconomyConfig.RES_FOOD:
								prod *= season_mod
							expected_qty = maxi(1, int(round(prod)))

				var produced_qty: int = workplace_mgr.produce_to_buffer(target_wp_id, season_mod, rm_node)
				if produced_qty >= expected_qty and expected_qty > 0:
					status_reason = "Hoàn thành công việc, chuẩn bị việc mới"
					award_work_xp(job_type, 10.0)
				elif produced_qty > 0:
					# Partial production cycle: buffer did not have capacity for full cycle output
					status_reason = "Kho đệm xưởng gần đầy, sản lượng bị giới hạn"
				else:
					var wp_obj = workplace_mgr.get_workplace(target_wp_id) if workplace_mgr.has_method("get_workplace") else null
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
	if hunger >= 70.0 and _is_central_food_available():
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

	# Advance construction factoring builder vocational skill multiplier
	var skill_mult := get_skill_efficiency("building")
	var effective_delta_hours := delta_hours * skill_mult

	# Capture progress before advance for robust calculation
	var prev_prog: float = -1.0
	if world_data != null:
		var b_obj = BuildingSystem.get_building_by_id(b_id, world_data)
		if not b_obj.is_empty():
			prev_prog = float(b_obj.get("construction_progress", 0.0))

	# Advance construction
	var res: Dictionary = {}
	if construction_handler.is_valid():
		var argc := construction_handler.get_argument_count()
		if argc >= 2:
			res = construction_handler.call(b_id, effective_delta_hours)
		else:
			res = construction_handler.call(effective_delta_hours)
	else:
		var wv = _get_world_view()
		if wv != null and wv.has_method("advance_construction_work"):
			res = wv.advance_construction_work(b_id, effective_delta_hours)
		elif world_data != null:
			res = BuildingSystem.advance_construction(b_id, effective_delta_hours, world_data)
			if res.get("completed", false):
				var rm_node: Node = get_node_or_null("/root/ResourceManager") if (is_inside_tree() and has_node("/root/ResourceManager")) else null
				BuildingSystem.complete_building(b_id, world_data, rm_node)

	if not res.get("success", false):
		active_job = null
		current_state = State.IDLE
		status_reason = "Công trình xây dựng đã hoàn thành hoặc bị hủy"
		return

	# Calculate actual progress made and active labor hours contributed
	var progress_made: float = 0.0
	if res.has("progress_delta"):
		progress_made = maxf(0.0, float(res.get("progress_delta", 0.0)))
	elif prev_prog >= 0.0 and res.has("progress"):
		progress_made = maxf(0.0, float(res.get("progress", 0.0)) - prev_prog)
	elif res.has("progress") and res.has("hours"):
		var cur_p: float = float(res.get("progress", 0.0))
		var max_h: float = float(res.get("hours", 0.0))
		progress_made = clampf(effective_delta_hours, 0.0, max_h)
	else:
		progress_made = effective_delta_hours

	var actual_labor_hours: float = 0.0
	if skill_mult > 0.0:
		actual_labor_hours = progress_made / skill_mult

	if actual_labor_hours > 0.0:
		# Award construction XP based strictly on actual game-hours contributed (5 XP per game-hour)
		award_work_xp("building", actual_labor_hours * 5.0)

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
	if hunger >= 70.0 and _is_central_food_available():
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
	if not _is_central_food_available():
		current_state = State.IDLE
		status_reason = "Kho lương thực trống rỗng (Đang đói)"
		return
	hunger = maxf(0.0, hunger - 50.0)
	current_state = State.IDLE
	status_reason = "Đã ăn no, sẵn sàng làm việc"

func _seek_rest() -> void:
	current_state = State.RESTING
	status_reason = "Quá kiệt sức, tìm nơi nghỉ ngơi"
	if nav:
		current_path = nav.find_path(current_cell, Vector2i(31, 35))

func _on_hour_passed(_hour: int, _day: int) -> void:
	if not is_alive():
		return

	var fatigue_mult: float = 1.0
	var es := _get_event_system()
	if es != null and es.has_method("get_active_fatigue_multiplier"):
		fatigue_mult = float(es.call("get_active_fatigue_multiplier", _day))
		if is_nan(fatigue_mult) or is_inf(fatigue_mult) or fatigue_mult <= 0.0:
			fatigue_mult = 1.0

	match current_state:
		State.WORKING, State.HAULING, State.GUARDING:
			hunger = minf(100.0, hunger + 4.167)
			fatigue = minf(100.0, fatigue + 4.0 * fatigue_mult)
		State.IDLE:
			hunger = minf(100.0, hunger + 2.0)
			fatigue = minf(100.0, fatigue + 1.0 * fatigue_mult)
		State.RESTING:
			fatigue = maxf(0.0, fatigue - 12.5)

	# Starvation escalation logic
	var is_starving: bool = (hunger >= 100.0)
	var rm_check := _get_resource_manager()
	if rm_check != null:
		if rm_check.has_method("is_starving") and bool(rm_check.call("is_starving")):
			is_starving = true
		elif rm_check.has_method("get_available_stock") and int(rm_check.call("get_available_stock", "food")) <= 0:
			is_starving = true
			
	if is_starving:
		# Stage 1: Morale drops by ~15/day (-0.625/hr), Fatigue +20/day (+0.833/hr)
		morale = maxf(0.0, morale - 0.625)
		fatigue = minf(100.0, fatigue + 0.833 * fatigue_mult)
		# Stage 2: Health drops by ~5%/day (-0.208/hr)
		health = maxf(0.0, health - 0.208)
		if health <= 0.0:
			die("Đã qua đời vì suy kiệt", "starvation_or_exhaustion")
	else:
		# Recovery: when well-fed and not starving, health recovers by ~10%/day (+0.417/hr)
		if hunger < 50.0 and health < 100.0:
			health = minf(100.0, health + 0.417)

func die(reason: String = "Đã qua đời vì suy kiệt", cause: String = "") -> void:
	var cleanup_complete := (
		health <= 0.0
		and active_job == null
		and (current_path == null or current_path.is_empty())
		and current_state == State.IDLE
	)
	if _death_processed and cleanup_complete:
		return

	if not cause.is_empty():
		death_cause = cause
	elif death_cause.is_empty():
		if reason.contains("Tử trận"):
			death_cause = "combat"
		else:
			death_cause = "starvation_or_exhaustion"

	health = 0.0
	status_reason = reason
	current_state = State.IDLE
	if current_path != null:
		current_path.clear()
	if active_job != null:
		if job_mgr != null:
			job_mgr.release_job(active_job)
		active_job = null

	if not _death_processed:
		_death_processed = true
		citizen_died.emit(citizen_id)

func is_alive() -> bool:
	return health > 0.0 and not _death_processed

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
