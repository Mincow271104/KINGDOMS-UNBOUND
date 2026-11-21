class_name CitizenController
extends Node2D
## Citizen Entity & Behavior State Machine for KINGDOMS UNBOUND.
## Implements pathfinding traversal, job execution, need decay, and explainable status.

const LandClearingManagerScript = preload("res://scripts/economy/land_clearing_manager.gd")
const SchedulePolicyScript = preload("res://scripts/entities/citizen_schedule_policy.gd")

signal citizen_selected(citizen: CitizenController)
signal citizen_died(citizen_id: String)
signal manual_command_completed(citizen_id: String, cmd_type: String)
signal manual_command_cancelled(citizen_id: String, reason: String)

enum State {
	IDLE = 0,
	MOVING_TO_JOB = 1,
	WORKING = 2,
	SEEKING_FOOD = 3,
	RESTING = 4,
	HAULING = 5,
	GUARDING = 6
}

enum RestPhase {
	NONE = 0,
	RETURNING_HOME = 1,
	ENTERING_HOME = 2,
	RESTING_INSIDE = 3,
	EXITING_HOME = 4
}

const REST_TRANSITION_SECONDS: float = 0.25

enum CancelSource {
	PLAYER = 0,
	DEATH = 1,
	TARGET_INVALIDATED = 2,
	SYSTEM = 3
}

@export var citizen_id: String = ""
@export var citizen_name: String = ""
@export var role: String = "idle" # "farmer", "woodcutter", "builder", "hauler", "miner", "smith", "guard", "idle"
var can_scout_beyond_territory: bool = false
var workplace_id: String = ""

# Manual Citizen Command State (Package 2K)
var manual_command: Dictionary = {
	"type": "",
	"target_cell": Vector2i(-1, -1),
	"target_id": "",
	"work_hours_required": 0.0,
	"work_hours_done": 0.0,
	"is_active": false,
	"is_paused": false,
	"pause_reason": ""
}

var current_cell: Vector2i = Vector2i(32, 32)
var current_state: int = State.IDLE
var status_reason: String = "Đang nghỉ ngơi tại quảng trường"
var barracks_checker: Callable = Callable()
var construction_checker: Callable = Callable()
var construction_handler: Callable = Callable()
var world_view: Node = null
var world_data: WorldGenerator.WorldData = null
var event_system: RefCounted = null
var poi_manager: RefCounted = null

func set_poi_manager(pm: RefCounted) -> void:
	poi_manager = pm

func _get_poi_manager() -> RefCounted:
	if poi_manager != null:
		return poi_manager
	var wv := _get_world_view()
	if wv != null:
		if wv.get("poi_mgr") != null:
			return wv.get("poi_mgr")
		elif wv.has_meta("poi_mgr"):
			return wv.get_meta("poi_mgr")
	return null

var land_clearing_mgr: Object = null
var active_clearing_order_id: String = ""
var natural_resource_mgr: Object = null
var active_resource_node_id: String = ""
var _resource_work_hours_done: float = 0.0
var wildlife_mgr: Object = null
var active_hunt_target_id: String = ""
var _hunt_work_hours_done: float = 0.0
var _hunt_pursuit_hours: float = 0.0
var _hunt_repath_timer: float = 0.0
var _hunt_last_target_cell: Vector2i = Vector2i(-1, -1)

func _get_land_clearing_mgr() -> Object:
	if land_clearing_mgr != null:
		return land_clearing_mgr
	var wv := _get_world_view()
	if wv != null and wv.get("land_clearing_mgr") != null:
		return wv.get("land_clearing_mgr")
	return null

func _get_natural_resource_mgr() -> Object:
	if natural_resource_mgr != null:
		return natural_resource_mgr
	var wv := _get_world_view()
	if wv != null and wv.get("natural_resource_mgr") != null:
		return wv.get("natural_resource_mgr")
	return null

func _release_natural_resource_reservation() -> void:
	if active_resource_node_id != "":
		var nrm := _get_natural_resource_mgr()
		if nrm != null and nrm.has_method("release_node"):
			nrm.call("release_node", active_resource_node_id, citizen_id)
		active_resource_node_id = ""
		_resource_work_hours_done = 0.0

func _get_wildlife_mgr() -> Object:
	if wildlife_mgr != null:
		return wildlife_mgr
	var wv := _get_world_view()
	if wv != null and wv.get("wildlife_mgr") != null:
		return wv.get("wildlife_mgr")
	return null

func _get_fog_of_war() -> FogOfWar:
	var wv := _get_world_view()
	if wv != null and wv.get("fog_of_war") is FogOfWar:
		return wv.get("fog_of_war") as FogOfWar
	return null

func _release_hunt_reservation() -> void:
	if active_hunt_target_id != "":
		var wlm := _get_wildlife_mgr()
		if wlm != null and wlm.has_method("release_reservation"):
			wlm.call("release_reservation", active_hunt_target_id, citizen_id)
		active_hunt_target_id = ""
		_hunt_work_hours_done = 0.0
		_hunt_pursuit_hours = 0.0
		_hunt_repath_timer = 0.0
		_hunt_last_target_cell = Vector2i(-1, -1)

func _exit_tree() -> void:
	_release_natural_resource_reservation()
	_release_hunt_reservation()

func is_cell_permitted_for_hunter(cell: Vector2i) -> bool:
	if role != "hunter":
		return false
	var wlm := _get_wildlife_mgr()
	var tmgr := _get_territory_mgr()
	var fow := _get_fog_of_war()
	var wd = _get_clearing_world_data()
	if wlm != null and wlm.has_method("is_cell_permitted_for_hunter"):
		return bool(wlm.call("is_cell_permitted_for_hunter", cell, wd, tmgr, fow, nav))
	return tmgr != null and bool(tmgr.call("is_cell_owned", cell))

func _get_storage_dropoff_cell() -> Vector2i:
	if workplace_mgr != null and workplace_mgr.has_method("get_nearest_dropoff_cell"):
		return workplace_mgr.get_nearest_dropoff_cell(current_cell)
	if nav != null and nav.world_data != null:
		return nav.world_data.center_spawn
	return Vector2i(32, 32)

func _is_dropoff_cell(cell: Vector2i) -> bool:
	if workplace_mgr != null and "_dropoffs" in workplace_mgr:
		var drops = workplace_mgr.get("_dropoffs")
		if drops is Dictionary:
			for d in drops.values():
				if d != null and "access_cell" in d and cell == d.access_cell:
					return true
			if (role == "hunter" or carrying_resource == EconomyConfig.RES_RAW_MEAT) and drops.is_empty():
				return false
	elif role == "hunter" or carrying_resource == EconomyConfig.RES_RAW_MEAT:
		return false
	if cell == _get_storage_dropoff_cell():
		return true
	var fallback_center: Vector2i = nav.world_data.center_spawn if (nav != null and nav.world_data != null) else Vector2i(32, 32)
	if cell == fallback_center:
		return true
	return false

func _find_valid_hunter_dropoff_cell() -> Vector2i:
	if workplace_mgr == null or not ("_dropoffs" in workplace_mgr):
		return Vector2i(-1, -1)
	var drops = workplace_mgr.get("_dropoffs")
	if not (drops is Dictionary) or drops.is_empty():
		return Vector2i(-1, -1)
	var candidates: Array[Dictionary] = []
	for d in drops.values():
		if d != null and "access_cell" in d:
			var acc: Vector2i = d.access_cell
			candidates.append({"cell": acc, "dist": IsoMath.grid_distance(current_cell, acc)})
	if candidates.is_empty():
		return Vector2i(-1, -1)
	candidates.sort_custom(func(a, b): return int(a["dist"]) < int(b["dist"]))
	for entry in candidates:
		var acc: Vector2i = entry["cell"]
		if current_cell == acc or nav == null or not _find_civilian_path(current_cell, acc).is_empty():
			return acc
	return Vector2i(-1, -1)

func _is_at_storage_dropoff() -> bool:
	return _is_dropoff_cell(current_cell)

# Needs (0..100)
var hunger: float = 10.0
var fatigue: float = 10.0
var health: float = 100.0
var morale: float = 70.0

var current_path: Array[Vector2i] = []
var _path_follower: ContinuousPathFollower = ContinuousPathFollower.new()
var _follower_source_path: Array[Vector2i] = []
var facing_dir: int = ContinuousPathFollower.ScreenDir.E
var facing_name: String = "E"
var is_moving_visually: bool = false
var _walk_anim_phase: float = 0.0
var _visual_anim_clock: float = 0.0
var _visual_active_clip: String = ""
var _visual_idle_offset: float = 0.0
var active_job: JobManager.JobData = null
var _death_processed: bool = false
var death_cause: String = ""
var _custom_resource_mgr: Object = null
var _custom_time_mgr: Object = null
var _connected_time_mgr: Object = null

# Territory-constrained autonomous idle roaming
var is_roaming: bool = false
var roam_target: Vector2i = Vector2i(-1, -1)
var _roam_wait_timer: float = 3.0
var _roam_job_poll_timer: float = 0.0
var _roam_rng: RandomNumberGenerator = null
var _survival_retry_timer: float = 0.0
var _job_retry_timer: float = 0.0
var _cargo_retry_timer: float = 0.0

# Displaced-citizen territory recovery (Policy 2B)
var is_recovering_to_territory: bool = false
var recovery_target: Vector2i = Vector2i(-1, -1)
var _recovery_route_cells: Dictionary = {}
var _recovery_retry_timer: float = 0.0
var _last_territory_revision: int = -1

# Home & Indoor Resting State (Option C)
var home_building_id: String = ""
var rest_phase: int = RestPhase.NONE
var rest_house_id: String = ""
var rest_entry_cell: Vector2i = Vector2i(-1, -1)
var _rest_transition_timer: float = 0.0
var _rest_visual_start_pos: Vector2 = Vector2.ZERO
var _rest_visual_target_pos: Vector2 = Vector2.ZERO
var _rest_pending_interrupt: String = ""
var _rest_retry_timer: float = 0.0

var nav: GridNavigation = null
var job_mgr: JobManager = null
var workplace_mgr: RefCounted = null
var move_speed_px: float = 48.0 # Pixel speed per second

# Vocational Skill Progression (Package 2B)
var skill_data: CitizenSkillData = null

# Logistics & Cargo
var carrying_resource: String = ""
var carrying_amount: int = 0
var carrying_source_workplace_id: String = ""
var carrying_dest_cell: Vector2i = Vector2i(-1, -1)
var carry_capacity: int = 10
var is_stranded_with_cargo: bool = false
var is_waiting_at_dropoff: bool = false

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
		sprite.offset = EntityVisualRegistry.VILLAGER_SPRITE_OFFSET
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_visual_idle_offset = float(abs(hash(citizen_id)) % 400) * 0.01
	_sync_citizen_visuals(0.0)
		
	position = IsoMath.map_to_local(current_cell)
	z_index = IsoMath.world_y_to_z_index(position.y)
	
	# Connect to TimeManager for hourly need updates and DayPhase schedule transitions
	_connect_time_manager_signals(_get_time_manager())

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
	if _roam_rng == null:
		_roam_rng = RandomNumberGenerator.new()
		_roam_rng.seed = hash(p_id) ^ 0x517CC1B7
	_roam_wait_timer = _roam_rng.randf_range(2.0, 6.0)
	position = IsoMath.map_to_local(current_cell)
	z_index = IsoMath.world_y_to_z_index(position.y)
	_update_reason()

func get_skill_data() -> CitizenSkillData:
	if skill_data == null:
		skill_data = CitizenSkillData.new()
	return skill_data

func get_work_efficiency_multiplier() -> float:
	if active_meal_buff_id == "hearty_stew" and active_meal_buff_remaining_hours > 0.0:
		return 1.15
	return 1.0

func get_fatigue_gain_multiplier() -> float:
	if active_meal_buff_id == "herbal_broth" and active_meal_buff_remaining_hours > 0.0:
		return 0.85
	return 1.0

func get_skill_efficiency(vocation_or_job: String) -> float:
	var base: float = get_skill_data().get_efficiency(vocation_or_job)
	if vocation_or_job == "hauling":
		return base
	return base * get_work_efficiency_multiplier()

func award_work_xp(vocation_or_job: String, amount: float) -> bool:
	return get_skill_data().add_xp(vocation_or_job, amount)

func get_effective_move_speed() -> float:
	var hauler_mult: float = 1.0
	if role == "hauler" or (active_job != null and active_job.type == "hauler"):
		hauler_mult = get_skill_data().get_efficiency("hauling")
	var terrain_mult: float = 1.0
	if world_data != null and IsoMath.is_in_bounds(current_cell):
		if world_data.terrain[current_cell.x][current_cell.y] == WorldGenerator.TerrainType.HILLS:
			terrain_mult = 0.75
	return move_speed_px * hauler_mult * terrain_mult

# Temporary Cooked Meal Buffs (Phase 8)
var active_meal_buff_id: String = ""
var active_meal_buff_remaining_hours: float = 0.0
var meal_cooldown_remaining_hours: float = 0.0

func serialize_meal_buff() -> Dictionary:
	return {
		"active_meal_buff_id": active_meal_buff_id,
		"active_meal_buff_remaining_hours": active_meal_buff_remaining_hours,
		"meal_cooldown_remaining_hours": meal_cooldown_remaining_hours,
	}

func deserialize_meal_buff(data: Variant) -> void:
	if not (data is Dictionary):
		active_meal_buff_id = ""
		active_meal_buff_remaining_hours = 0.0
		meal_cooldown_remaining_hours = 0.0
		return
	var b_id: String = str(data.get("active_meal_buff_id", ""))
	var rem_h: float = maxf(0.0, float(data.get("active_meal_buff_remaining_hours", 0.0)))
	if b_id != "" and rem_h > 0.0 and not CookhouseConfig.get_buff_def(b_id).is_empty():
		active_meal_buff_id = b_id
		active_meal_buff_remaining_hours = rem_h
	else:
		active_meal_buff_id = ""
		active_meal_buff_remaining_hours = 0.0
	meal_cooldown_remaining_hours = maxf(0.0, float(data.get("meal_cooldown_remaining_hours", 0.0)))

func _advance_meal_buff_timers(delta: float) -> void:
	if active_meal_buff_remaining_hours <= 0.0 and meal_cooldown_remaining_hours <= 0.0:
		return
	var dh: float = _get_delta_hours(delta)
	if dh <= 0.0:
		return
	if active_meal_buff_remaining_hours > 0.0:
		active_meal_buff_remaining_hours = maxf(0.0, active_meal_buff_remaining_hours - dh)
		if active_meal_buff_remaining_hours <= 0.0:
			active_meal_buff_id = ""
	if meal_cooldown_remaining_hours > 0.0:
		meal_cooldown_remaining_hours = maxf(0.0, meal_cooldown_remaining_hours - dh)

func _try_consume_cooked_meal_on_rest_completion() -> bool:
	if active_meal_buff_id != "" or active_meal_buff_remaining_hours > 0.0:
		return false
	if meal_cooldown_remaining_hours > 0.0:
		return false
	var rm := _get_resource_manager()
	if rm == null or not rm.has_method("get_available_stock") or not rm.has_method("consume_resource"):
		return false
	for meal_res in CookhouseConfig.MEAL_PRIORITY:
		if int(rm.get_available_stock(meal_res)) >= 1:
			var b_def := CookhouseConfig.get_buff_for_meal(meal_res)
			if b_def.is_empty():
				continue
			if bool(rm.consume_resource(meal_res, 1)):
				active_meal_buff_id = str(b_def["buff_id"])
				active_meal_buff_remaining_hours = float(b_def.get("duration_hours", 8.0))
				meal_cooldown_remaining_hours = CookhouseConfig.MEAL_COOLDOWN_HOURS
				return true
	return false

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
	_connect_time_manager_signals(_get_time_manager())

func _connect_time_manager_signals(tm: Object) -> void:
	if _connected_time_mgr != null and is_instance_valid(_connected_time_mgr) and _connected_time_mgr != tm:
		if _connected_time_mgr.has_signal("hour_passed") and _connected_time_mgr.is_connected("hour_passed", Callable(self, "_on_hour_passed")):
			_connected_time_mgr.disconnect("hour_passed", Callable(self, "_on_hour_passed"))
		if _connected_time_mgr.has_signal("day_phase_changed") and _connected_time_mgr.is_connected("day_phase_changed", Callable(self, "_on_day_phase_changed")):
			_connected_time_mgr.disconnect("day_phase_changed", Callable(self, "_on_day_phase_changed"))
	_connected_time_mgr = tm
	if tm != null and is_instance_valid(tm):
		if tm.has_signal("hour_passed") and not tm.is_connected("hour_passed", Callable(self, "_on_hour_passed")):
			tm.connect("hour_passed", Callable(self, "_on_hour_passed"))
		if tm.has_signal("day_phase_changed") and not tm.is_connected("day_phase_changed", Callable(self, "_on_day_phase_changed")):
			tm.connect("day_phase_changed", Callable(self, "_on_day_phase_changed"))

func _get_current_day_phase() -> int:
	var tm := _get_time_manager()
	if tm != null:
		if tm.has_method("get_day_phase"):
			return int(tm.call("get_day_phase"))
		if tm.get("current_hour") != null and tm.has_method("get_day_phase_for_hour"):
			return int(tm.call("get_day_phase_for_hour", int(tm.get("current_hour"))))
	return SchedulePolicyScript.TimeManagerScript.DayPhase.DAY

func _on_day_phase_changed(_new_phase: int, _old_phase: int) -> void:
	var tm := _get_time_manager()
	if tm != null and tm.has_method("is_paused") and bool(tm.call("is_paused")):
		return
	_evaluate_schedule_transition()

func _evaluate_schedule_transition() -> bool:
	if not is_alive():
		return false
	var tmgr := _get_territory_mgr()
	if tmgr != null and int(tmgr.call("get_owned_count")) <= 0:
		return false
	if has_manual_command():
		return false
	if carrying_amount > 0:
		return false
	if current_state == State.SEEKING_FOOD or current_state == State.RESTING:
		return false

	var phase: int = _get_current_day_phase()
	if SchedulePolicyScript.should_enforce_curfew(role, phase):
		interrupt_current_job("Đã tối, trở về nhà nghỉ ngơi", false)
		_seek_rest()
		return true

	if SchedulePolicyScript.should_wind_down(role, phase):
		if current_state == State.IDLE:
			if active_job != null or active_resource_node_id != "" or active_hunt_target_id != "":
				interrupt_current_job("Hoàng hôn, kết thúc ngày làm việc", false)
			else:
				cancel_roaming()
			_seek_rest()
			return true
		if current_state == State.MOVING_TO_JOB:
			if is_roaming:
				cancel_roaming()
				_seek_rest()
				return true
			if active_clearing_order_id != "":
				current_path.clear()
				_follower_source_path.clear()
				_path_follower.clear()
				_stop_walk_animation()
				_seek_rest()
				return true
			if active_job != null and active_job.state == JobManager.JobState.RESERVED:
				interrupt_current_job("Hoàng hôn, kết thúc ngày làm việc", false)
				_seek_rest()
				return true
			if active_resource_node_id != "" or active_hunt_target_id != "":
				interrupt_current_job("Hoàng hôn, kết thúc ngày làm việc", false)
				_seek_rest()
				return true
	return false

func _get_resource_manager() -> Object:
	if _custom_resource_mgr != null and is_instance_valid(_custom_resource_mgr):
		return _custom_resource_mgr
	if world_view != null and is_instance_valid(world_view) and world_view.has_method("_get_resource_mgr"):
		var wv_rm = world_view.call("_get_resource_mgr")
		if wv_rm != null and is_instance_valid(wv_rm):
			return wv_rm
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
		_stop_walk_animation()
		return

	_advance_meal_buff_timers(delta)

	var tmgr_proc := _get_territory_mgr()
	var zero_territory_frozen: bool = false
	if tmgr_proc != null:
		var rev_now := _get_territory_revision(tmgr_proc)
		if rev_now != _last_territory_revision:
			_last_territory_revision = rev_now
			_recovery_retry_timer = 0.0
			_survival_retry_timer = 0.0
			_job_retry_timer = 0.0
			_cargo_retry_timer = 0.0
		if int(tmgr_proc.call("get_owned_count")) <= 0 and not _is_valid_townhall_repair_exception():
			zero_territory_frozen = true

	# Priority 2: Vital survival emergency pauses manual command
	if not zero_territory_frozen and has_manual_command() and not bool(manual_command.get("is_paused", false)):
		if hunger >= 85.0 and _is_central_food_available():
			manual_command["is_paused"] = true
			manual_command["pause_reason"] = "Đói bụng cần ăn lương thực"
			current_path.clear()
			_seek_food()
			return
		elif fatigue >= 90.0:
			manual_command["is_paused"] = true
			manual_command["pause_reason"] = "Kiệt sức cần nghỉ ngơi"
			current_path.clear()
			_seek_rest()
			return

	match current_state:
		State.IDLE:
			_stop_walk_animation()
			_process_idle(delta)
		State.MOVING_TO_JOB, State.HAULING:
			_process_movement(delta)
		State.WORKING:
			_stop_walk_animation()
			_process_working(delta)
		State.GUARDING:
			_stop_walk_animation()
			_process_guarding(delta)
		State.SEEKING_FOOD:
			_process_movement(delta)
		State.RESTING:
			_process_resting(delta)

	var anim_speed := float(tm.get("current_speed")) if tm != null and tm.get("current_speed") != null else 1.0
	if anim_speed > 0.0:
		_sync_citizen_visuals(delta * anim_speed)

func _process_idle(delta: float = 0.0) -> void:
	if delta > 0.0:
		_survival_retry_timer = maxf(0.0, _survival_retry_timer - delta)
		_job_retry_timer = maxf(0.0, _job_retry_timer - delta)
		_cargo_retry_timer = maxf(0.0, _cargo_retry_timer - delta)
		_recovery_retry_timer = maxf(0.0, _recovery_retry_timer - delta)

	var tmgr_idle := _get_territory_mgr()
	if tmgr_idle != null:
		var owned_cnt_idle: int = int(tmgr_idle.call("get_owned_count"))
		if owned_cnt_idle <= 0:
			if is_roaming:
				cancel_roaming()
			if is_recovering_to_territory:
				_clear_territory_recovery()
			if fatigue >= 85.0:
				current_path.clear()
				current_state = State.RESTING
				status_reason = "Quá kiệt sức, nghỉ ngơi tại chỗ"
				return
			if _is_valid_townhall_repair_exception():
				if has_manual_command() and not bool(manual_command.get("is_paused", false)):
					_execute_active_manual_command()
					return
				if active_job != null:
					var th_path := _find_civilian_path(current_cell, active_job.target_cell)
					if not th_path.is_empty():
						current_path = th_path
						current_state = State.MOVING_TO_JOB
						_update_reason()
						return
			if role == "builder" and active_job == null and job_mgr != null and nav != null and _job_retry_timer <= 0.0:
				var wd_th = _get_clearing_world_data()
				var rm_th: Node = _get_resource_manager() if (_get_resource_manager() is Node) else null
				var th_filter := func(b_id: String) -> bool:
					if wd_th == null:
						return false
					var bd := BuildingSystem.get_building_by_id(b_id, wd_th)
					if bd.is_empty() or str(bd.get("type", "")) != "townhall":
						return false
					return str(bd.get("state", "")) == "under_construction" or bool(bd.get("is_repairing", false))
				var th_job = job_mgr.request_job(citizen_id, role, current_cell, nav, workplace_mgr, rm_th, th_filter)
				if th_job != null:
					active_job = th_job
					var th_p := _find_civilian_path(current_cell, active_job.target_cell)
					if not th_p.is_empty():
						current_path = th_p
						current_state = State.MOVING_TO_JOB
						_update_reason()
						return
					job_mgr.release_job(active_job)
					active_job = null
					_job_retry_timer = 2.0
			current_path.clear()
			status_reason = "Vương quốc chưa có lãnh thổ hoạt động"
			return
		elif not bool(tmgr_idle.call("is_cell_owned", current_cell)):
			if is_roaming:
				cancel_roaming()
			if nav != null:
				_attempt_territory_recovery(tmgr_idle)
			return
		elif is_recovering_to_territory:
			_clear_territory_recovery()

	# Priority 3: Manual Command overrides autonomous jobs
	if has_manual_command() and not bool(manual_command.get("is_paused", false)):
		_execute_active_manual_command()
		return

	if job_mgr == null or nav == null:
		return

	# Check urgent needs first
	if hunger >= 70.0 and _is_central_food_available() and _survival_retry_timer <= 0.0:
		_seek_food()
		return
	if fatigue >= 85.0:
		_seek_rest()
		return

	# If citizen holds remaining cargo from partial delivery or interrupted hauling, handle existing cargo first; do not request or accept new jobs
	if carrying_amount > 0:
		if carrying_resource != "":
			if is_stranded_with_cargo or not _is_at_storage_dropoff():
				# Citizen is stranded away from storage or route was blocked: retry finding path
				var drop_cell := _find_valid_hunter_dropoff_cell() if (role == "hunter" or carrying_resource == EconomyConfig.RES_RAW_MEAT) else _get_storage_dropoff_cell()
				if carrying_dest_cell != Vector2i(-1, -1) and _is_dropoff_cell(carrying_dest_cell):
					drop_cell = carrying_dest_cell
				elif active_job != null and active_job.type == "hauler" and _is_dropoff_cell(active_job.dest_cell):
					drop_cell = active_job.dest_cell
				if drop_cell != Vector2i(-1, -1) and nav != null and current_path.is_empty() and _cargo_retry_timer <= 0.0:
					current_path = _find_civilian_path(current_cell, drop_cell)
				if not current_path.is_empty():
					current_state = State.HAULING
					is_stranded_with_cargo = false
					status_reason = "Đang vận chuyển %d %s về kho" % [carrying_amount, carrying_resource]
				else:
					current_state = State.IDLE
					is_stranded_with_cargo = true
					var tmgr := _get_territory_mgr()
					if tmgr != null and not bool(tmgr.call("is_cell_owned", drop_cell)):
						_cargo_retry_timer = 3.0
					else:
						_cargo_retry_timer = 0.0
					status_reason = "Đang giữ %d %s, chưa tìm được đường về kho trong lãnh thổ" % [carrying_amount, carrying_resource]
				return

			var rm: Object = _get_resource_manager()
			if rm != null and rm.has_method("add_resource"):
				var space: int = 999999
				if rm.has_method("get_storage_capacity") and rm.has_method("get_total_stock"):
					space = maxi(0, int(rm.get_storage_capacity(carrying_resource)) - int(rm.get_total_stock(carrying_resource)))
				elif rm.has_method("get_capacity") and rm.has_method("get_total_stock"):
					space = maxi(0, int(rm.get_capacity(carrying_resource)) - int(rm.get_total_stock(carrying_resource)))
				if space > 0:
					_deposit_hauler_cargo()
					return
				else:
					status_reason = "Kho trung tâm đã đầy, còn giữ %d %s" % [carrying_amount, carrying_resource]
					return
			else:
				status_reason = "ResourceManager không khả dụng, còn giữ %d %s" % [carrying_amount, carrying_resource]
				return
		else:
			status_reason = "Hàng hóa không xác định, còn giữ %d đơn vị" % carrying_amount
			return

	# Priority 5: Scheduled rest gate (DUSK/NIGHT for DAY_SHIFT; after manual command, survival, and cargo delivery)
	var cur_phase_idle: int = _get_current_day_phase()
	if SchedulePolicyScript.should_hold_rest(role, cur_phase_idle):
		if active_job != null or active_resource_node_id != "" or active_hunt_target_id != "":
			interrupt_current_job("Đã hết giờ làm việc", false)
		else:
			cancel_roaming()
		_seek_rest()
		return

	# Priority 6: Active Land Clearing Order (after cargo & scheduled rest gate)
	if active_clearing_order_id != "":
		_process_active_clearing_order()
		return

	# Resume preserved active_job if citizen was temporarily suspended (e.g., territory restoration)
	if active_job != null and _job_retry_timer <= 0.0:
		var target_dest_resumed: Vector2i = active_job.dest_cell if (active_job.type == "hauler" and carrying_amount > 0) else (active_job.source_cell if active_job.type == "hauler" else active_job.target_cell)
		var path_resumed := _find_civilian_path(current_cell, target_dest_resumed)
		if not path_resumed.is_empty():
			current_path = path_resumed
			current_state = State.HAULING if (active_job.type == "hauler" and carrying_amount > 0) else State.MOVING_TO_JOB
			_update_reason()
			return
		_job_retry_timer = 2.0
		status_reason = "Không thể tiếp cận nơi làm việc trong lãnh thổ"
		return

	# Request work
	if role != "idle" and _job_retry_timer <= 0.0:
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
			var path := _find_civilian_path(current_cell, target_dest)
			if not path.is_empty():
				current_path = path
				current_state = State.MOVING_TO_JOB
				_update_reason()
			else:
				job_mgr.release_job(active_job)
				active_job = null
				_job_retry_timer = 2.0
				status_reason = "Không thể tiếp cận nơi làm việc trong lãnh thổ"
		else:
			if role == "hunter" and carrying_amount == 0 and _job_retry_timer <= 0.0:
				_try_start_hunting_work()
				return
			if role in ["miner", "farmer"] and carrying_amount == 0:
				var nrm := _get_natural_resource_mgr()
				var wd_nr = _get_clearing_world_data()
				if nrm != null and wd_nr != null and nrm.has_method("find_and_reserve_nearest_node"):
					var tmgr_nr = _get_territory_mgr()
					var nr_res: Dictionary = nrm.call("find_and_reserve_nearest_node", role, current_cell, wd_nr, tmgr_nr, nav, citizen_id, Callable(self, "_find_civilian_path"))
					if not nr_res.is_empty():
						var node_d: Dictionary = nr_res["node"]
						active_resource_node_id = str(node_d.get("id", ""))
						_resource_work_hours_done = 0.0
						current_path = nr_res["path"]
						current_state = State.MOVING_TO_JOB
						status_reason = "Di chuyển tới nguồn tài nguyên tự nhiên"
						return
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

	# Autonomous territory-constrained idle roaming (when truly idle & unblocked)
	if delta > 0.0 and not is_roaming:
		var tm := _get_time_manager()
		var speed_mult: float = 1.0
		if tm != null and tm.get("current_speed") != null:
			speed_mult = float(tm.get("current_speed"))
		if speed_mult > 0.0:
			_roam_wait_timer -= delta * speed_mult
			if _roam_wait_timer <= 0.0:
				_try_start_idle_roam()

func _get_territory_mgr() -> RefCounted:
	if nav == null or nav.world_data == null or nav.world_data.owned_cells.size() != nav.world_data.map_width:
		return null
	var wv := _get_world_view()
	if wv != null and wv.get("territory_mgr") is RefCounted:
		return wv.get("territory_mgr") as RefCounted
	return null

func _get_roam_territory_predicate() -> Callable:
	var tmgr := _get_territory_mgr()
	if tmgr == null:
		return Callable()
	return Callable(tmgr, "is_cell_owned")

func _get_territory_revision(tmgr: RefCounted) -> int:
	if tmgr == null:
		return -1
	var rev = tmgr.get("_revision")
	return int(rev) if rev != null else -1

func _is_valid_townhall_repair_exception(goal: Vector2i = Vector2i(-1, -1)) -> bool:
	if role != "builder":
		return false
	var wd = _get_clearing_world_data()
	if wd == null:
		return false
	var b_id := ""
	var expected_cell := Vector2i(-1, -1)
	if active_job != null and active_job.type == "builder" and active_job.target_building_id != "":
		b_id = active_job.target_building_id
		expected_cell = active_job.target_cell
	elif has_manual_command() and not bool(manual_command.get("is_paused", false)) and str(manual_command.get("type", "")) == "build":
		b_id = str(manual_command.get("target_id", ""))
		expected_cell = manual_command.get("target_cell", Vector2i(-1, -1))
	else:
		return false
	if b_id == "":
		return false
	var bd: Dictionary = BuildingSystem.get_building_by_id(b_id, wd)
	if bd.is_empty() or str(bd.get("type", "")) != "townhall":
		return false
	var b_state: String = str(bd.get("state", "active"))
	if b_state != "under_construction" and not bool(bd.get("is_repairing", false)):
		return false
	if goal != Vector2i(-1, -1) and expected_cell != Vector2i(-1, -1) and goal != expected_cell:
		var origin: Vector2i = bd.get("cell", bd.get("origin", Vector2i.ZERO))
		var b_size: Vector2i = bd.get("size", Vector2i(3, 3))
		var in_th_perimeter: bool = (
			goal.x >= origin.x - 1 and goal.x <= origin.x + b_size.x and
			goal.y >= origin.y - 1 and goal.y <= origin.y + b_size.y
		)
		if not in_th_perimeter:
			return false
	return true

func _clear_territory_recovery() -> void:
	is_recovering_to_territory = false
	recovery_target = Vector2i(-1, -1)
	_recovery_route_cells.clear()
	if citizen_id != "":
		var tmgr := _get_territory_mgr()
		if tmgr != null and tmgr.has_method("cancel_recovery"):
			tmgr.call("cancel_recovery", citizen_id)

func _attempt_territory_recovery(tmgr: RefCounted) -> bool:
	if tmgr == null or nav == null:
		return false
	var rev := _get_territory_revision(tmgr)
	if rev != _last_territory_revision:
		_last_territory_revision = rev
		_recovery_retry_timer = 0.0
	if _recovery_retry_timer > 0.0:
		return false
	var rec_res: Dictionary = {}
	if tmgr.has_method("request_recovery") and citizen_id != "":
		rec_res = tmgr.call("request_recovery", citizen_id, current_cell, nav)
	else:
		rec_res = nav.find_path_to_nearest_matching_detailed(current_cell, Callable(tmgr, "is_cell_owned"))
	var st_code: int = int(rec_res.get("status", GridNavigation.NearestSearchStatus.UNREACHABLE))
	if st_code == GridNavigation.NearestSearchStatus.IN_PROGRESS or st_code == GridNavigation.NearestSearchStatus.INVALIDATED:
		current_path.clear()
		current_state = State.IDLE
		status_reason = "Đang tìm đường trở lại lãnh thổ vương quốc"
		return false
	if st_code != GridNavigation.NearestSearchStatus.FOUND:
		_clear_territory_recovery()
		_recovery_retry_timer = 3.0
		current_path.clear()
		current_state = State.IDLE
		status_reason = "Mắc kẹt ngoài lãnh thổ, chưa tìm được đường về"
		return false
	var rec_path: Array[Vector2i] = rec_res.get("path", [])
	if rec_path.is_empty():
		_clear_territory_recovery()
		_recovery_retry_timer = 3.0
		current_path.clear()
		current_state = State.IDLE
		status_reason = "Mắc kẹt ngoài lãnh thổ, chưa tìm được đường về"
		return false
	is_recovering_to_territory = true
	recovery_target = rec_path[-1]
	_recovery_route_cells.clear()
	for c in rec_path:
		_recovery_route_cells[c] = true
	current_path = rec_path
	current_state = State.MOVING_TO_JOB
	status_reason = "Đang quay trở lại lãnh thổ vương quốc"
	return true

func _get_civilian_territory_predicate(_start: Vector2i = Vector2i(-1, -1), goal: Vector2i = Vector2i(-1, -1)) -> Callable:
	var tmgr := _get_territory_mgr()
	if tmgr == null:
		return Callable()
	var owned_cnt: int = int(tmgr.call("get_owned_count"))
	if owned_cnt <= 0:
		# Policy 1C: Only an explicitly assigned Town Hall repair/construction builder may move outside territory.
		if _is_valid_townhall_repair_exception(goal):
			return Callable()
		return func(_c: Vector2i) -> bool:
			return false
	if is_recovering_to_territory:
		# Policy 2B: Strictly scoped to owned cells or the computed recovery route cells.
		return func(c: Vector2i) -> bool:
			return bool(tmgr.call("is_cell_owned", c)) or _recovery_route_cells.has(c)
	if role == "hunter" and (active_hunt_target_id != "" or carrying_resource == EconomyConfig.RES_RAW_MEAT or not bool(tmgr.call("is_cell_owned", current_cell))):
		return Callable(self, "is_cell_permitted_for_hunter")
	return Callable(tmgr, "is_cell_owned")

func _find_civilian_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if nav == null:
		return []
	var pred := _get_civilian_territory_predicate(start, goal)
	if not pred.is_valid():
		return nav.find_path(start, goal)
	return nav.find_path_with_predicate(start, goal, pred)

func cancel_roaming() -> void:
	if not is_roaming:
		return
	is_roaming = false
	roam_target = Vector2i(-1, -1)
	_roam_job_poll_timer = 0.0
	current_path.clear()
	_follower_source_path.clear()
	_path_follower.clear()
	if current_state == State.MOVING_TO_JOB and active_job == null and not has_manual_command() and active_clearing_order_id == "":
		current_state = State.IDLE
	_stop_walk_animation()
	_update_reason()

func _try_start_idle_roam() -> void:
	if _roam_rng == null:
		_roam_rng = RandomNumberGenerator.new()
		_roam_rng.seed = hash(citizen_id) ^ 0x517CC1B7
	var tmgr := _get_territory_mgr()
	if tmgr == null or nav == null:
		_roam_wait_timer = _roam_rng.randf_range(2.0, 5.0)
		return
	var walkable_owned: Array[Vector2i] = tmgr.get_walkable_owned_cells(nav)
	if walkable_owned.size() <= 1:
		_roam_wait_timer = _roam_rng.randf_range(2.0, 5.0)
		return

	var reserved: Dictionary = {}
	var wv := _get_world_view()
	if wv != null and wv.get("citizen_list") is Array:
		for other in wv.get("citizen_list"):
			if other != null and other != self and is_instance_valid(other) and bool(other.get("is_roaming")):
				reserved[other.get("roam_target")] = true

	var pred := _get_roam_territory_predicate()
	var preferred: Array[Vector2i] = []
	var fallback: Array[Vector2i] = []
	var sample_count: int = mini(24, walkable_owned.size())
	for _i in range(sample_count):
		var idx: int = _roam_rng.randi_range(0, walkable_owned.size() - 1)
		var cand: Vector2i = walkable_owned[idx]
		if cand == current_cell or reserved.has(cand):
			continue
		var dist: int = IsoMath.grid_distance(current_cell, cand)
		if dist >= 3 and dist <= 12:
			preferred.append(cand)
		elif dist >= 1:
			fallback.append(cand)

	var candidates: Array[Vector2i] = preferred if not preferred.is_empty() else fallback
	for cand in candidates:
		var path := nav.find_path_with_predicate(current_cell, cand, pred)
		if path.size() >= 2:
			is_roaming = true
			roam_target = path[-1]
			_roam_job_poll_timer = 0.0
			current_path = path
			current_state = State.MOVING_TO_JOB
			status_reason = "Đang dạo quanh lãnh thổ"
			return

	_roam_wait_timer = _roam_rng.randf_range(2.0, 4.0)

func serialize_roaming() -> Dictionary:
	return {
		"is_roaming": is_roaming,
		"roam_target_x": roam_target.x,
		"roam_target_y": roam_target.y,
		"roam_wait_timer": _roam_wait_timer
	}

func restore_roaming(data: Dictionary) -> void:
	if data.is_empty():
		return
	_roam_wait_timer = maxf(0.0, float(data.get("roam_wait_timer", 3.0)))
	var was_roaming := bool(data.get("is_roaming", false))
	var tx := int(data.get("roam_target_x", -1))
	var ty := int(data.get("roam_target_y", -1))
	if not was_roaming or tx < 0 or ty < 0:
		is_roaming = false
		roam_target = Vector2i(-1, -1)
		return
	var target := Vector2i(tx, ty)
	var tmgr := _get_territory_mgr()
	if tmgr != null and tmgr.is_cell_owned(target) and nav != null and nav.is_cell_walkable(target):
		var pred := _get_roam_territory_predicate()
		var path := nav.find_path_with_predicate(current_cell, target, pred)
		if path.size() >= 2:
			is_roaming = true
			roam_target = target
			current_path = path
			current_state = State.MOVING_TO_JOB
			status_reason = "Đang dạo quanh lãnh thổ"
			return
	is_roaming = false
	roam_target = Vector2i(-1, -1)

func _stop_walk_animation() -> void:
	is_moving_visually = false
	var spr := get_node_or_null("Sprite2D") as Sprite2D
	if spr != null:
		spr.offset = EntityVisualRegistry.VILLAGER_SPRITE_OFFSET

func _update_walk_visuals(velocity: Vector2, speed_mult: float, delta: float) -> void:
	if velocity.length_squared() < ContinuousPathFollower.VEL_DEADZONE_SQ:
		_stop_walk_animation()
		return
	is_moving_visually = true
	facing_dir = _path_follower.update_facing_from_velocity(velocity)
	facing_name = ContinuousPathFollower.dir_to_name(facing_dir)
	_walk_anim_phase = fmod(_walk_anim_phase + delta * speed_mult * 10.0, TAU)
	var spr := get_node_or_null("Sprite2D") as Sprite2D
	if spr != null:
		spr.flip_h = _path_follower.last_flip_h
		spr.offset = EntityVisualRegistry.VILLAGER_SPRITE_OFFSET

func _sync_citizen_visuals(anim_dt: float) -> void:
	var spr := sprite if sprite != null and is_instance_valid(sprite) else (get_node_or_null("Sprite2D") as Sprite2D)
	if spr == null:
		return
	var norm_role := EntityVisualRegistry.normalize_villager_role(role)
	var layout := EntityVisualRegistry.get_villager_sheet_layout(norm_role)
	var tex := EntityVisualRegistry.get_villager_sheet_texture(norm_role)
	if tex == null:
		return
	var hframes_cnt := int(layout.get("hframes", 6))
	var vframes_cnt := int(layout.get("vframes", 6))
	if spr.texture != tex:
		spr.texture = tex
	if spr.hframes != hframes_cnt:
		spr.hframes = hframes_cnt
	if spr.vframes != vframes_cnt:
		spr.vframes = vframes_cnt
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.offset = EntityVisualRegistry.VILLAGER_SPRITE_OFFSET

	var is_back := (facing_dir == ContinuousPathFollower.ScreenDir.NW or facing_dir == ContinuousPathFollower.ScreenDir.N or facing_dir == ContinuousPathFollower.ScreenDir.NE)
	var clip := "idle"
	var row := 2 if is_back else 0
	var fcount := int(layout.get("idle_frames", 4))
	var fps := float(layout.get("idle_fps", 2.2))

	if norm_role == "hauler" and current_state == State.HAULING:
		if is_moving_visually:
			clip = "carry_walk"
			row = 5 if is_back else 4
			fcount = int(layout.get("work_frames", 6))
			fps = float(layout.get("walk_fps", 9.0))
		else:
			clip = "carry_idle"
			row = 7 if is_back else 6
			fcount = int(layout.get("idle_frames", 4))
			fps = float(layout.get("idle_fps", 2.2))
	elif is_moving_visually:
		clip = "walk"
		row = 3 if is_back else 1
		fcount = int(layout.get("walk_frames", 6))
		fps = float(layout.get("walk_fps", 9.0))
	elif current_state == State.WORKING or current_state == State.GUARDING:
		clip = "work"
		row = 5 if is_back else 4
		fcount = int(layout.get("work_frames", 6))
		fps = float(layout.get("work_fps", 5.5))

	if clip != _visual_active_clip:
		_visual_active_clip = clip
		_visual_anim_clock = 0.0
	elif anim_dt > 0.0:
		_visual_anim_clock += anim_dt

	var use_idle_off := (clip == "idle" or clip == "carry_idle")
	var eff_t := (_visual_anim_clock + _visual_idle_offset) if use_idle_off else _visual_anim_clock
	var frame_idx := int(floor(eff_t * fps)) % maxi(1, fcount)
	spr.frame_coords = Vector2i(frame_idx, row)

func _sync_path_follower() -> void:
	var needs_sync := current_path.size() != _follower_source_path.size()
	if not needs_sync and not current_path.is_empty():
		if current_path[0] != _follower_source_path[0] or current_path[-1] != _follower_source_path[-1]:
			needs_sync = true
		elif current_path != _follower_source_path:
			needs_sync = true
	if needs_sync:
		_follower_source_path = current_path.duplicate()
		var goal_cell: Vector2i = current_path[-1] if not current_path.is_empty() else current_cell
		var pred := _get_civilian_territory_predicate(current_cell, goal_cell)
		_path_follower.set_path(current_path, nav, position, pred)

func _process_movement(delta: float) -> void:
	var tmgr_mv := _get_territory_mgr()
	if tmgr_mv != null:
		var owned_cnt_mv: int = int(tmgr_mv.call("get_owned_count"))
		if owned_cnt_mv <= 0:
			if is_recovering_to_territory:
				_clear_territory_recovery()
			if is_roaming:
				cancel_roaming()
				return
			if not _is_valid_townhall_repair_exception():
				current_path.clear()
				_follower_source_path.clear()
				_path_follower.clear()
				_stop_walk_animation()
				current_state = State.IDLE
				status_reason = "Vương quốc chưa có lãnh thổ hoạt động"
				return
		elif is_recovering_to_territory:
			if bool(tmgr_mv.call("is_cell_owned", current_cell)):
				_clear_territory_recovery()
				current_path.clear()
				_follower_source_path.clear()
				_path_follower.clear()
				_stop_walk_animation()
				current_state = State.IDLE
				_update_reason()
				return
			var rev_mv := _get_territory_revision(tmgr_mv)
			if rev_mv != _last_territory_revision:
				_last_territory_revision = rev_mv
				_recovery_retry_timer = 0.0
				if not (role == "hunter" and (active_hunt_target_id != "" or carrying_resource == EconomyConfig.RES_RAW_MEAT) and is_cell_permitted_for_hunter(current_cell)):
					_attempt_territory_recovery(tmgr_mv)

	if current_state == State.MOVING_TO_JOB and active_hunt_target_id != "":
		if not _step_hunter_pursuit(delta):
			return

	if SchedulePolicyScript.should_hold_rest(role, _get_current_day_phase()):
		if _evaluate_schedule_transition():
			return

	if is_roaming:
		if (hunger >= 70.0 and _is_central_food_available()) or fatigue >= 85.0 or has_manual_command() or active_clearing_order_id != "" or carrying_amount > 0:
			cancel_roaming()
			return
		if role != "idle" and job_mgr != null:
			_roam_job_poll_timer += delta
			if _roam_job_poll_timer >= 0.5:
				_roam_job_poll_timer = 0.0
				cancel_roaming()
				return

	if current_path.is_empty():
		_stop_walk_animation()
		_arrive_at_destination()
		return

	var speed_mult: float = 1.0
	var tm := _get_time_manager()
	if tm != null and tm.get("current_speed") != null:
		speed_mult = float(tm.get("current_speed"))
	if speed_mult <= 0.0:
		_stop_walk_animation()
		return

	_sync_path_follower()
	if _path_follower.is_finished():
		current_path.clear()
		_follower_source_path.clear()
		_stop_walk_animation()
		_arrive_at_destination()
		return

	# Dynamic obstacle safety: if next smoothed waypoint became unwalkable, reroute cleanly
	if nav != null and _path_follower.waypoint_index < _path_follower.smoothed_cells.size():
		var next_wp_cell := _path_follower.smoothed_cells[_path_follower.waypoint_index]
		var final_wp_cell := _path_follower.smoothed_cells[-1]
		if next_wp_cell != final_wp_cell and not nav.is_cell_walkable(next_wp_cell):
			if is_recovering_to_territory and tmgr_mv != null:
				_recovery_retry_timer = 0.0
				if _attempt_territory_recovery(tmgr_mv):
					_sync_path_follower()
				else:
					return
			else:
				var rerouted := _find_civilian_path(current_cell, final_wp_cell)
				if not rerouted.is_empty():
					current_path = rerouted
					_sync_path_follower()
				elif is_roaming:
					cancel_roaming()
					return

	var step_dist: float = get_effective_move_speed() * delta * speed_mult
	var res := _path_follower.advance(position, step_dist)
	var new_pos: Vector2 = res["position"]

	# Lightweight local separation from nearby moving citizens (obstacle-safe)
	var wv := _get_world_view()
	if wv != null and wv.get("citizen_list") is Array and not bool(res["arrived"]):
		var nearby_pos: Array = []
		var c_list: Array = wv.get("citizen_list")
		for other in c_list:
			if other != null and other != self and is_instance_valid(other) and other.get("is_moving_visually"):
				var op: Vector2 = other.position
				if new_pos.distance_squared_to(op) < 100.0:
					nearby_pos.append(op)
		if not nearby_pos.is_empty():
			var nudge := ContinuousPathFollower.compute_separation_nudge(new_pos, nearby_pos, 10.0, 0.5)
			if nudge != Vector2.ZERO:
				var cand := new_pos + nudge
				var cand_cell := IsoMath.local_to_map(cand)
				var goal_cell := _path_follower.smoothed_cells[-1] if not _path_follower.smoothed_cells.is_empty() else current_cell
				var pred := _get_civilian_territory_predicate(current_cell, goal_cell)
				if (nav == null or nav.is_cell_walkable(cand_cell)) and (not pred.is_valid() or bool(pred.call(cand_cell))):
					new_pos = cand

	position = new_pos
	z_index = IsoMath.world_y_to_z_index(new_pos.y)
	current_cell = IsoMath.local_to_map(new_pos)
	is_waiting_at_dropoff = false
	_update_walk_visuals(res["velocity"], speed_mult, delta)

	if is_recovering_to_territory and tmgr_mv != null and bool(tmgr_mv.call("is_cell_owned", current_cell)):
		_clear_territory_recovery()
		current_path.clear()
		_follower_source_path.clear()
		_path_follower.clear()
		_stop_walk_animation()
		current_state = State.IDLE
		_update_reason()
		return

	if bool(res["arrived"]):
		current_path.clear()
		_follower_source_path.clear()
		_stop_walk_animation()
		_arrive_at_destination()

func _arrive_at_destination() -> void:
	if is_roaming:
		is_roaming = false
		roam_target = Vector2i(-1, -1)
		_roam_job_poll_timer = 0.0
		if _roam_rng == null:
			_roam_rng = RandomNumberGenerator.new()
			_roam_rng.seed = hash(citizen_id) ^ 0x517CC1B7
		_roam_wait_timer = _roam_rng.randf_range(2.0, 5.0)
		current_state = State.IDLE
		_update_reason()
		return
	match current_state:
		State.MOVING_TO_JOB:
			if has_manual_command():
				_arrive_at_manual_destination()
				return
			if active_clearing_order_id != "":
				_arrive_at_clearing_slot()
				return
			if active_hunt_target_id != "":
				_arrive_at_hunt_target()
				return
			if active_resource_node_id != "":
				var nrm := _get_natural_resource_mgr()
				var node_d: Dictionary = nrm.call("get_node_by_id", active_resource_node_id) if (nrm != null and nrm.has_method("get_node_by_id")) else {}
				if node_d.is_empty() or bool(node_d.get("depleted", false)) or int(node_d.get("remaining_qty", 0)) <= 0:
					_release_natural_resource_reservation()
					current_state = State.IDLE
				else:
					current_state = State.WORKING
					status_reason = "Đang khai thác tài nguyên tự nhiên"
				return
			if active_job != null:
				if not _is_at_authoritative_work_location():
					_redirect_to_work_location()
					return
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
			if not _is_at_storage_dropoff():
				var drop_cell := _find_valid_hunter_dropoff_cell() if (role == "hunter" or carrying_resource == EconomyConfig.RES_RAW_MEAT) else _get_storage_dropoff_cell()
				if carrying_dest_cell != Vector2i(-1, -1) and _is_dropoff_cell(carrying_dest_cell):
					drop_cell = carrying_dest_cell
				elif active_job != null and active_job.type == "hauler" and _is_dropoff_cell(active_job.dest_cell):
					drop_cell = active_job.dest_cell
				var new_path = _find_civilian_path(current_cell, drop_cell) if (nav != null and drop_cell != Vector2i(-1, -1)) else []
				if not new_path.is_empty():
					current_path = new_path
				else:
					current_state = State.IDLE
					is_stranded_with_cargo = true
					status_reason = "Đang giữ %d %s, chưa tìm được đường về kho" % [carrying_amount, carrying_resource]
				return
			_deposit_hauler_cargo()
		State.SEEKING_FOOD:
			_eat_food()
		State.RESTING:
			if rest_phase == RestPhase.RETURNING_HOME:
				_on_arrived_at_home_access()
			else:
				status_reason = "Đang ngủ nghỉ hồi phục thể lực"

func _pickup_hauler_cargo() -> void:
	if active_job == null:
		current_state = State.IDLE
		return
	if not _is_at_authoritative_work_location():
		_redirect_to_work_location()
		return

	# Defensive guard: never overwrite an existing cargo batch
	if carrying_amount > 0:
		status_reason = "Đang giữ lô hàng dở dang (%d %s), không thể bốc hàng mới" % [carrying_amount, carrying_resource]
		if active_job != null and job_mgr != null:
			job_mgr.release_job(active_job)
			active_job = null
		current_state = State.IDLE
		return
		
	var picked_up := 0
	if workplace_mgr != null and workplace_mgr.has_method("pickup_from_buffer"):
		picked_up = workplace_mgr.pickup_from_buffer(active_job.source_workplace_id, carry_capacity)
	else:
		picked_up = mini(carry_capacity, active_job.cargo_amount)
		
	if picked_up > 0:
		var src_id: String = active_job.source_workplace_id if active_job.source_workplace_id != "" else active_job.target_building_id
		var dest_cell: Vector2i = active_job.dest_cell
		var path := _find_civilian_path(current_cell, dest_cell)
		if not path.is_empty():
			carrying_resource = active_job.cargo_resource
			carrying_amount = picked_up
			carrying_source_workplace_id = src_id
			carrying_dest_cell = dest_cell
			if job_mgr != null:
				job_mgr.complete_job(active_job)
			active_job = null
			current_path = path
			current_state = State.HAULING
			is_stranded_with_cargo = false
			_update_reason()
		else:
			# Destination blocked: return goods safely via WorkplaceManager API
			var returned: int = 0
			if workplace_mgr != null and workplace_mgr.has_method("return_to_buffer"):
				returned = int(workplace_mgr.return_to_buffer(active_job.source_workplace_id, picked_up))
			var unreturned: int = picked_up - returned
			if unreturned <= 0:
				carrying_amount = 0
				carrying_resource = ""
				carrying_source_workplace_id = ""
				carrying_dest_cell = Vector2i(-1, -1)
				if job_mgr != null:
					job_mgr.release_job(active_job)
				active_job = null
				current_state = State.IDLE
				status_reason = "Đường vận chuyển về kho bị chặn"
			else:
				carrying_resource = active_job.cargo_resource
				carrying_amount = unreturned
				carrying_source_workplace_id = src_id
				carrying_dest_cell = dest_cell
				is_stranded_with_cargo = true
				if job_mgr != null:
					job_mgr.complete_job(active_job)
				active_job = null
				current_state = State.IDLE
				status_reason = "Đường vận chuyển bị chặn, giữ %d %s" % [unreturned, carrying_resource]
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
		if has_manual_command():
			var cmd_type: String = String(manual_command.get("type", ""))
			manual_command["is_active"] = false
			manual_command_completed.emit(citizen_id, cmd_type)
		current_state = State.IDLE
		is_waiting_at_dropoff = false
		is_stranded_with_cargo = false
		status_reason = "Không có hàng để dỡ"
		return

	# Fail-closed guard: never deposit cargo if stranded or route to storage is blocked
	if is_stranded_with_cargo:
		return

	# Fail-closed guard: never deposit cargo if citizen is away from storage dropoff
	if not _is_at_storage_dropoff():
		return

	var delivered_amount: int = carrying_amount
	var delivered_res: String = carrying_resource
	var rm: Object = _get_resource_manager()
	if rm == null or not rm.has_method("add_resource"):
		# Fail-closed when ResourceManager is unavailable: preserve all cargo fields
		if active_job != null:
			if job_mgr != null:
				job_mgr.release_job(active_job)
			active_job = null
		current_state = State.IDLE
		status_reason = "ResourceManager không khả dụng, bảo lưu %d %s" % [carrying_amount, carrying_resource]
		return

	var added: int = rm.add_resource(delivered_res, delivered_amount)
	carrying_amount -= added

	if carrying_amount <= 0:
		current_path.clear()
		carrying_amount = 0
		carrying_resource = ""
		carrying_source_workplace_id = ""
		carrying_dest_cell = Vector2i(-1, -1)
		is_waiting_at_dropoff = false
		is_stranded_with_cargo = false
		# Full cargo batch successfully deposited: award +10 hauling XP
		award_work_xp("hauling", 10.0)
		if active_job != null:
			if job_mgr != null:
				job_mgr.complete_job(active_job)
			active_job = null
		if has_manual_command():
			var cmd_type: String = String(manual_command.get("type", ""))
			manual_command["is_active"] = false
			manual_command_completed.emit(citizen_id, cmd_type)
		current_state = State.IDLE
		status_reason = "Đã dỡ hàng vào kho an toàn"
	else:
		# Partial deposit: central storage space was insufficient to receive full batch.
		# Remaining cargo is safely preserved in hauler inventory (no loss, no duplication).
		# carrying_source_workplace_id is preserved so demolition checks and future delivery can trace it!
		current_path.clear()
		is_waiting_at_dropoff = true
		if active_job != null:
			if job_mgr != null:
				job_mgr.release_job(active_job)
			active_job = null
		current_state = State.IDLE
		status_reason = "Kho trung tâm đã đầy, còn giữ %d %s" % [carrying_amount, carrying_resource]

func recover_cargo(target_rm: Object = null) -> Dictionary:
	if carrying_amount <= 0 or carrying_resource.is_empty():
		return {"recovered": 0, "resource": "", "remaining": 0, "status": "no_cargo"}

	var rm: Object = target_rm if target_rm != null else _get_resource_manager()
	if rm == null or not rm.has_method("add_resource"):
		push_error("[CitizenController] Cannot recover cargo for citizen %s: ResourceManager unavailable" % citizen_id)
		return {"recovered": 0, "resource": carrying_resource, "remaining": carrying_amount, "status": "error_no_rm"}

	var to_recover: int = carrying_amount
	var res_type: String = carrying_resource
	var added: int = int(rm.call("add_resource", res_type, to_recover))
	carrying_amount -= added

	if carrying_amount <= 0:
		carrying_amount = 0
		carrying_resource = ""
		carrying_source_workplace_id = ""
		carrying_dest_cell = Vector2i(-1, -1)
		return {"recovered": added, "resource": res_type, "remaining": 0, "status": "success"}
	else:
		push_warning("[CitizenController] Partial cargo recovery for citizen %s: %d %s deposited, %d %s remains (storage at capacity)" % [citizen_id, added, res_type, carrying_amount, res_type])
		return {"recovered": added, "resource": res_type, "remaining": carrying_amount, "status": "partial_capacity"}

func _get_delta_hours(delta: float) -> float:
	var tm := _get_time_manager()
	if tm == null:
		return delta
	if tm.has_method("get_game_hours_for_delta"):
		return float(tm.get_game_hours_for_delta(delta))
	var spd = tm.get("current_speed")
	return delta * (float(spd) if spd != null else 1.0) / 7.5

func _get_authoritative_work_cell() -> Vector2i:
	if active_job == null:
		return Vector2i(-1, -1)
	if active_job.type == "hauler":
		return active_job.dest_cell if carrying_amount > 0 else active_job.source_cell
	return active_job.target_cell

func _is_at_authoritative_work_location() -> bool:
	if active_job == null:
		return false
	var target_cell := _get_authoritative_work_cell()
	if target_cell != Vector2i(-1, -1):
		if current_cell == target_cell:
			return true
		if nav != null and not nav.is_walkable(target_cell):
			return IsoMath.grid_distance(current_cell, target_cell) <= 1
		return false
	if active_job.target_building_id != "" and world_data != null:
		var bd := BuildingSystem.get_building_by_id(active_job.target_building_id, world_data)
		if not bd.is_empty():
			var bpos := Vector2i(int(bd.get("x", -1)), int(bd.get("y", -1)))
			if bpos.x >= 0 and bpos.y >= 0:
				return IsoMath.grid_distance(current_cell, bpos) <= 2
	return false

func _redirect_to_work_location() -> void:
	if active_job == null or job_mgr == null:
		current_state = State.IDLE
		return
	var target_dest := _get_authoritative_work_cell()
	var path: Array[Vector2i] = []
	if target_dest != Vector2i(-1, -1):
		path = _find_civilian_path(current_cell, target_dest)
	if not path.is_empty():
		current_path = path
		current_state = State.HAULING if (active_job.type == "hauler" and carrying_amount > 0) else State.MOVING_TO_JOB
		_update_reason()
	else:
		job_mgr.release_job(active_job)
		active_job = null
		current_path.clear()
		current_state = State.IDLE
		_job_retry_timer = 2.0
		status_reason = "Không thể tiếp cận nơi làm việc"

func _process_working(delta: float) -> void:
	if has_manual_command():
		_process_manual_working(delta)
		return
	if SchedulePolicyScript.should_enforce_curfew(role, _get_current_day_phase()) and carrying_amount == 0:
		if _evaluate_schedule_transition():
			return
	if active_clearing_order_id != "":
		_process_clearing_work(delta)
		return
	if active_hunt_target_id != "":
		_process_hunting_work(delta)
		return
	if active_resource_node_id != "":
		_process_natural_resource_work(delta)
		return

	if active_job == null or job_mgr == null:
		current_state = State.IDLE
		return

	if not _is_at_authoritative_work_location():
		_redirect_to_work_location()
		return
		
	# 7.5 real seconds = 1 game hour at 1x speed (GDD §4.1)
	var tm := _get_time_manager()
	var delta_hours := _get_delta_hours(delta)

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
							var mult: float = float(wp_obj.get("level_multiplier", 1.0))
							var prod: float = wp_obj.base_production_per_cycle * mult
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
					elif season_mod <= 0.0 and active_job.type == "farmer":
						status_reason = "Cánh đồng bị đóng băng trong bão tuyết"
					else:
						status_reason = "Thiếu nguyên liệu chế tác tại xưởng"
		active_job = null
		current_state = State.IDLE

func _process_building_work(delta_hours: float) -> void:
	if active_job == null or job_mgr == null:
		current_state = State.IDLE
		return
	if not _is_at_authoritative_work_location():
		_redirect_to_work_location()
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
			var b_obj = BuildingSystem.get_building_by_id(b_id, world_data)
			if not b_obj.is_empty() and bool(b_obj.get("is_upgrading", false)):
				res = BuildingSystem.advance_upgrade(b_obj, effective_delta_hours, world_data)
				if res.get("completed", false):
					var rm_node: Node = get_node_or_null("/root/ResourceManager") if (is_inside_tree() and has_node("/root/ResourceManager")) else null
					var comp_res := BuildingSystem.complete_building_upgrade(b_obj, world_data, rm_node)
					if not comp_res.get("success", false):
						res["completed"] = false
						res["completion_blocked"] = true
						res["reason"] = "Nâng cấp hoàn thành thời gian thi công nhưng chưa thể hoàn tất (chờ ResourceManager sẵn sàng)"
			else:
				res = BuildingSystem.advance_construction(b_id, effective_delta_hours, world_data)
				if res.get("completed", false):
					var rm_node: Node = get_node_or_null("/root/ResourceManager") if (is_inside_tree() and has_node("/root/ResourceManager")) else null
					var comp_success := BuildingSystem.complete_building(b_id, world_data, rm_node)
					if not comp_success:
						res["completed"] = false
						res["completion_blocked"] = true

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

	var delta_hours := _get_delta_hours(delta)

	var completed := job_mgr.progress_job(active_job, delta_hours)
	if completed:
		active_job = null
		current_state = State.IDLE
		status_reason = "Hoàn thành ca gác, sẵn sàng nhiệm vụ mới"

func _get_sim_speed_multiplier() -> float:
	var tm := _get_time_manager()
	if tm == null:
		return 1.0
	if tm.has_method("is_paused") and bool(tm.call("is_paused")):
		return 0.0
	var spd = tm.get("current_speed")
	return maxf(0.0, float(spd) if spd != null else 1.0)

func _get_rest_world_data():
	if world_data != null:
		return world_data
	var wv := _get_world_view()
	if wv != null and wv.get("world_data") != null:
		return wv.get("world_data")
	return null

func is_resting_inside() -> bool:
	return current_state == State.RESTING and rest_phase == RestPhase.RESTING_INSIDE

func _register_indoor_occupant(house_id: String) -> bool:
	if house_id == "" or citizen_id == "":
		return false
	var wv := _get_world_view()
	if wv == null or not wv.has_method("register_house_occupant"):
		return false
	return bool(wv.call("register_house_occupant", house_id, citizen_id))

func _unregister_indoor_occupant(house_id: String = "") -> void:
	if citizen_id == "":
		return
	var wv := _get_world_view()
	if wv != null and wv.has_method("unregister_house_occupant"):
		wv.call("unregister_house_occupant", citizen_id, house_id)

func _is_cell_valid_for_citizen(cell: Vector2i) -> bool:
	if not IsoMath.is_in_bounds(cell):
		return false
	if nav != null and not nav.is_cell_walkable(cell):
		return false
	var tmgr := _get_territory_mgr()
	if tmgr != null and int(tmgr.call("get_owned_count")) > 0:
		if not bool(tmgr.call("is_cell_owned", cell)):
			return false
	return true

func _is_house_active_and_owned(house_id: String) -> bool:
	if house_id == "":
		return false
	var wv := _get_world_view()
	if wv != null and wv.has_method("is_house_active_and_owned"):
		return bool(wv.call("is_house_active_and_owned", house_id))
	var wd = _get_rest_world_data()
	if wd == null:
		return false
	var b_data: Dictionary = BuildingSystem.get_building_by_id(house_id, wd)
	if b_data.is_empty():
		return false
	if str(b_data.get("type", "")) != "house":
		return false
	if str(b_data.get("state", "active")) != "active":
		return false
	var tmgr := _get_territory_mgr()
	if tmgr != null:
		if int(tmgr.call("get_owned_count")) <= 0:
			return false
		var origin: Vector2i = b_data.get("cell", Vector2i(-1, -1))
		var b_size: Vector2i = b_data.get("size", Vector2i(2, 2))
		if tmgr.has_method("is_footprint_owned"):
			if not bool(tmgr.call("is_footprint_owned", origin, b_size)):
				return false
		elif not bool(tmgr.call("is_cell_owned", origin)):
			return false
	return true

func _get_house_visual_center(house_id: String) -> Vector2:
	var wd = _get_rest_world_data()
	if wd != null and house_id != "":
		var b_data: Dictionary = BuildingSystem.get_building_by_id(house_id, wd)
		if not b_data.is_empty():
			var origin: Vector2i = b_data.get("cell", Vector2i.ZERO)
			var b_size: Vector2i = b_data.get("size", Vector2i(2, 2))
			var center_cell := Vector2(origin.x + (b_size.x - 1) * 0.5, origin.y + (b_size.y - 1) * 0.5)
			var c_grid := Vector2i(roundi(center_cell.x), roundi(center_cell.y))
			return IsoMath.map_to_local(c_grid)
	return position

func _find_house_perimeter_access(house_id: String, prefer_cell: Vector2i = Vector2i(-1, -1)) -> Vector2i:
	if _is_cell_valid_for_citizen(prefer_cell):
		return prefer_cell
	var wd = _get_rest_world_data()
	if wd == null or house_id == "":
		return Vector2i(-1, -1)
	var b_data: Dictionary = BuildingSystem.get_building_by_id(house_id, wd)
	if b_data.is_empty():
		return Vector2i(-1, -1)
	var origin: Vector2i = b_data.get("cell", Vector2i(-1, -1))
	var b_size: Vector2i = b_data.get("size", Vector2i(2, 2))
	var candidates: Array[Vector2i] = []
	for oy in range(b_size.y):
		candidates.append(Vector2i(origin.x - 1, origin.y + oy))
	for ox in range(b_size.x):
		candidates.append(Vector2i(origin.x + ox, origin.y - 1))
	for oy in range(b_size.y):
		candidates.append(Vector2i(origin.x + b_size.x, origin.y + oy))
	for ox in range(b_size.x):
		candidates.append(Vector2i(origin.x + ox, origin.y + b_size.y))
	var best_cell := Vector2i(-1, -1)
	var best_dist: int = 999999
	for cand in candidates:
		if not _is_cell_valid_for_citizen(cand):
			continue
		if wd.terrain[cand.x][cand.y] == WorldGenerator.TerrainType.WATER:
			continue
		if wd.occupancy[cand.x][cand.y]:
			continue
		var d := IsoMath.grid_distance(current_cell, cand)
		if d < best_dist:
			best_dist = d
			best_cell = cand
	return best_cell

func _resolve_valid_exit_cell(house_id: String) -> Vector2i:
	var c := _find_house_perimeter_access(house_id, rest_entry_cell)
	if c != Vector2i(-1, -1):
		return c
	# Fallback: nearest walkable cell around rest_entry_cell or current_cell (without teleporting inside footprint)
	var anchor := rest_entry_cell if IsoMath.is_in_bounds(rest_entry_cell) else current_cell
	if _is_cell_valid_for_citizen(anchor):
		return anchor
	for r in range(1, 5):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if absi(dx) + absi(dy) != r:
					continue
				var cand := anchor + Vector2i(dx, dy)
				if _is_cell_valid_for_citizen(cand):
					return cand
	return Vector2i(-1, -1)

func _resolve_rest_house_and_path() -> Dictionary:
	var wv := _get_world_view()
	if wv != null and wv.has_method("resolve_home_for_citizen"):
		return wv.call("resolve_home_for_citizen", self)
	var wd = _get_rest_world_data()
	if wd == null or nav == null:
		return {}
	var tmgr := _get_territory_mgr()
	if tmgr != null and int(tmgr.call("get_owned_count")) <= 0:
		return {}
	# Fallback direct scan when WorldView is absent (e.g. isolated unit tests)
	if home_building_id != "" and _is_house_active_and_owned(home_building_id):
		var acc := _find_house_perimeter_access(home_building_id)
		if acc != Vector2i(-1, -1):
			var p := _find_civilian_path(current_cell, acc)
			if not p.is_empty() or current_cell == acc:
				return {"house_id": home_building_id, "access_cell": acc, "path": p}
	var best_id: String = ""
	var best_acc := Vector2i(-1, -1)
	var best_path: Array[Vector2i] = []
	var best_dist: int = 999999
	for b in wd.buildings:
		if str(b.get("type", "")) != "house" or str(b.get("state", "active")) != "active":
			continue
		var bid := str(b.get("id", ""))
		if not _is_house_active_and_owned(bid):
			continue
		var acc := _find_house_perimeter_access(bid)
		if acc == Vector2i(-1, -1):
			continue
		var p := _find_civilian_path(current_cell, acc)
		if p.is_empty() and current_cell != acc:
			continue
		var d := IsoMath.grid_distance(current_cell, acc)
		if d < best_dist:
			best_dist = d
			best_id = bid
			best_acc = acc
			best_path = p
	if best_id != "":
		home_building_id = best_id
		return {"house_id": best_id, "access_cell": best_acc, "path": best_path}
	return {}

func _on_arrived_at_home_access() -> void:
	_stop_walk_animation()
	if not _is_house_active_and_owned(rest_house_id) or not _is_cell_valid_for_citizen(rest_entry_cell):
		# Target house invalidated before entry: try another or fall back to outdoor rest
		var alt := _resolve_rest_house_and_path()
		if not alt.is_empty():
			rest_house_id = str(alt.get("house_id", ""))
			rest_entry_cell = alt.get("access_cell", Vector2i(-1, -1))
			var alt_path: Array[Vector2i] = alt.get("path", [])
			if not alt_path.is_empty() and current_cell != rest_entry_cell:
				current_path = alt_path
				rest_phase = RestPhase.RETURNING_HOME
				status_reason = "Đang trở về nhà nghỉ"
				return
		else:
			rest_phase = RestPhase.NONE
			rest_house_id = ""
			rest_entry_cell = Vector2i(-1, -1)
			status_reason = "Nghỉ ngơi tại chỗ (không có nhà khả dụng)"
			return

	rest_phase = RestPhase.ENTERING_HOME
	_rest_transition_timer = 0.0
	_rest_visual_start_pos = position
	var center_pos := _get_house_visual_center(rest_house_id)
	_rest_visual_target_pos = position.lerp(center_pos, 0.35)
	status_reason = "Đang vào nhà nghỉ ngơi"

func _begin_exit_home(pending_interrupt: String = "") -> void:
	var exit_cell := _resolve_valid_exit_cell(rest_house_id)
	if exit_cell == Vector2i(-1, -1):
		# No valid exit cell right now; remain safely hidden and retry briefly
		_rest_retry_timer = 0.5
		return
	_unregister_indoor_occupant(rest_house_id)
	_rest_pending_interrupt = pending_interrupt
	rest_entry_cell = exit_cell
	current_cell = exit_cell
	var exit_pos := IsoMath.map_to_local(exit_cell)
	var center_pos := _get_house_visual_center(rest_house_id)
	_rest_visual_start_pos = exit_pos.lerp(center_pos, 0.35)
	_rest_visual_target_pos = exit_pos
	position = _rest_visual_start_pos
	visible = true
	modulate.a = 0.0
	scale = Vector2(0.85, 0.85)
	_rest_transition_timer = 0.0
	rest_phase = RestPhase.EXITING_HOME
	status_reason = "Đang rời khỏi nhà"

func wake_from_indoor_rest() -> void:
	_unregister_indoor_occupant(rest_house_id)
	if rest_phase == RestPhase.RESTING_INSIDE or rest_phase == RestPhase.ENTERING_HOME or rest_phase == RestPhase.EXITING_HOME:
		var exit_cell := _resolve_valid_exit_cell(rest_house_id)
		if exit_cell != Vector2i(-1, -1):
			current_cell = exit_cell
		position = IsoMath.map_to_local(current_cell)
	z_index = IsoMath.world_y_to_z_index(position.y)
	visible = true
	modulate.a = 1.0
	scale = Vector2.ONE
	rest_phase = RestPhase.NONE
	rest_house_id = ""
	rest_entry_cell = Vector2i(-1, -1)
	_rest_transition_timer = 0.0
	_rest_pending_interrupt = ""
	current_path.clear()

func evict_from_house(house_id: String, reason_text: String = "Nhà ở đã bị phá hủy") -> void:
	_unregister_indoor_occupant(house_id)
	if home_building_id == house_id:
		home_building_id = ""
	if rest_house_id != house_id:
		return
	if rest_phase in [RestPhase.ENTERING_HOME, RestPhase.RESTING_INSIDE, RestPhase.EXITING_HOME]:
		var exit_cell := _resolve_valid_exit_cell(house_id)
		if exit_cell != Vector2i(-1, -1):
			current_cell = exit_cell
		position = IsoMath.map_to_local(current_cell)
	z_index = IsoMath.world_y_to_z_index(position.y)
	visible = true
	modulate.a = 1.0
	scale = Vector2.ONE
	rest_phase = RestPhase.NONE
	rest_house_id = ""
	rest_entry_cell = Vector2i(-1, -1)
	_rest_transition_timer = 0.0
	_rest_pending_interrupt = ""
	current_path.clear()
	_follower_source_path.clear()
	_path_follower.clear()
	_stop_walk_animation()
	if current_state == State.RESTING and (fatigue > 15.0 or SchedulePolicyScript.should_hold_rest(role, _get_current_day_phase())):
		_seek_rest()
		if rest_phase == RestPhase.NONE:
			status_reason = reason_text
	elif current_state == State.RESTING:
		current_state = State.IDLE
		status_reason = reason_text

func _finish_resting_to_idle() -> void:
	visible = true
	modulate.a = 1.0
	scale = Vector2.ONE
	rest_phase = RestPhase.NONE
	rest_house_id = ""
	rest_entry_cell = Vector2i(-1, -1)
	_rest_transition_timer = 0.0
	_rest_pending_interrupt = ""
	current_state = State.IDLE
	_update_reason()
	if has_manual_command() and bool(manual_command.get("is_paused", false)):
		_resume_paused_manual_command()

func _process_resting(delta: float) -> void:
	if delta > 0.0 and _rest_retry_timer > 0.0:
		_rest_retry_timer = maxf(0.0, _rest_retry_timer - delta)

	match rest_phase:
		RestPhase.RETURNING_HOME:
			if not _is_house_active_and_owned(rest_house_id) or not _is_cell_valid_for_citizen(rest_entry_cell):
				_stop_walk_animation()
				current_path.clear()
				var alt := _resolve_rest_house_and_path()
				if not alt.is_empty():
					rest_house_id = str(alt.get("house_id", ""))
					rest_entry_cell = alt.get("access_cell", Vector2i(-1, -1))
					current_path = alt.get("path", [])
					if current_path.is_empty() and current_cell == rest_entry_cell:
						_on_arrived_at_home_access()
					return
				# Controlled fallback to outdoor rest
				rest_phase = RestPhase.NONE
				rest_house_id = ""
				rest_entry_cell = Vector2i(-1, -1)
				status_reason = "Quá kiệt sức, nghỉ ngơi tại chỗ"
				return
			if current_cell == rest_entry_cell and current_path.is_empty():
				_on_arrived_at_home_access()
				return
			_process_movement(delta)
			return

		RestPhase.ENTERING_HOME:
			_stop_walk_animation()
			if not _is_house_active_and_owned(rest_house_id):
				wake_from_indoor_rest()
				_seek_rest()
				return
			var spd := _get_sim_speed_multiplier()
			if spd <= 0.0:
				return
			_rest_transition_timer += delta * spd
			var t := clampf(_rest_transition_timer / REST_TRANSITION_SECONDS, 0.0, 1.0)
			position = _rest_visual_start_pos.lerp(_rest_visual_target_pos, t)
			modulate.a = 1.0 - t
			scale = Vector2.ONE.lerp(Vector2(0.85, 0.85), t)
			if t >= 1.0:
				if not _register_indoor_occupant(rest_house_id):
					visible = true
					modulate.a = 1.0
					scale = Vector2.ONE
					_rest_transition_timer = 0.0
					_rest_pending_interrupt = ""
					rest_phase = RestPhase.NONE
					rest_house_id = ""
					rest_entry_cell = Vector2i(-1, -1)
					if _get_world_view() != null:
						_seek_rest()
					else:
						status_reason = "Nghỉ ngơi tại chỗ (không thể đăng ký vào nhà)"
					return
				current_cell = rest_entry_cell
				position = IsoMath.map_to_local(rest_entry_cell)
				visible = false
				modulate.a = 1.0
				scale = Vector2.ONE
				rest_phase = RestPhase.RESTING_INSIDE
				if active_clearing_order_id != "":
					status_reason = "Đang nghỉ trong nhà, công việc khai hoang được giữ lại"
				else:
					status_reason = "Đang nghỉ ngơi trong nhà"
			return

		RestPhase.RESTING_INSIDE:
			_stop_walk_animation()
			visible = false
			if not _is_house_active_and_owned(rest_house_id):
				# If house was destroyed/unowned without external eviction, self-heal safely
				evict_from_house(rest_house_id, "Nhà ở không còn khả dụng")
				return
			# Critical hunger interrupt
			if hunger >= 85.0 and _is_central_food_available():
				if _rest_retry_timer <= 0.0:
					_begin_exit_home("seek_food")
				return
			var delta_hours := _get_delta_hours(delta)
			fatigue = maxf(0.0, fatigue - 12.5 * delta_hours)
			if active_clearing_order_id != "":
				status_reason = "Đang nghỉ trong nhà, công việc khai hoang được giữ lại"
			if SchedulePolicyScript.should_wake_from_scheduled_rest(role, _get_current_day_phase(), fatigue):
				if _rest_retry_timer <= 0.0:
					_begin_exit_home("")
			return

		RestPhase.EXITING_HOME:
			_stop_walk_animation()
			var spd := _get_sim_speed_multiplier()
			if spd <= 0.0:
				return
			_rest_transition_timer += delta * spd
			var t := clampf(_rest_transition_timer / REST_TRANSITION_SECONDS, 0.0, 1.0)
			position = _rest_visual_start_pos.lerp(_rest_visual_target_pos, t)
			modulate.a = t
			scale = Vector2(0.85, 0.85).lerp(Vector2.ONE, t)
			if t >= 1.0:
				position = _rest_visual_target_pos
				current_cell = IsoMath.local_to_map(_rest_visual_target_pos)
				visible = true
				modulate.a = 1.0
				scale = Vector2.ONE
				var pend := _rest_pending_interrupt
				var exited_house_id := rest_house_id
				rest_phase = RestPhase.NONE
				rest_house_id = ""
				rest_entry_cell = Vector2i(-1, -1)
				_rest_transition_timer = 0.0
				_rest_pending_interrupt = ""
				if pend == "seek_food":
					_seek_food()
				else:
					if pend == "" and exited_house_id != "":
						_try_consume_cooked_meal_on_rest_completion()
					_finish_resting_to_idle()
			return

		_:
			# Outdoor fallback rest (no eligible reachable house)
			_stop_walk_animation()
			var delta_hours := _get_delta_hours(delta)
			fatigue = maxf(0.0, fatigue - 12.5 * delta_hours)
			if active_clearing_order_id != "":
				status_reason = "Đang nghỉ, công việc khai hoang được giữ lại"
			if SchedulePolicyScript.should_wake_from_scheduled_rest(role, _get_current_day_phase(), fatigue):
				_finish_resting_to_idle()

func _seek_food() -> void:
	_release_hunt_reservation()
	if nav:
		var fallback_food: Vector2i = nav.world_data.center_spawn if nav.world_data != null else Vector2i(32, 32)
		var path := _find_civilian_path(current_cell, fallback_food)
		if path.is_empty() and _get_territory_mgr() != null:
			current_path.clear()
			current_state = State.IDLE
			_survival_retry_timer = 5.0
			status_reason = "Kho lương thực nằm ngoài lãnh thổ hoặc không thể tiếp cận"
			return
		current_path = path
	current_state = State.SEEKING_FOOD
	status_reason = "Đang đói, đi tìm lương thực tại kho"

func _eat_food() -> void:
	if not _is_central_food_available():
		current_state = State.IDLE
		status_reason = "Kho lương thực trống rỗng (Đang đói)"
		return
	hunger = maxf(0.0, hunger - 50.0)
	current_state = State.IDLE
	status_reason = "Đã ăn no, sẵn sàng làm việc"
	if has_manual_command() and bool(manual_command.get("is_paused", false)):
		_resume_paused_manual_command()

func _seek_rest() -> void:
	_release_hunt_reservation()
	current_state = State.RESTING
	if active_clearing_order_id != "":
		var lcm := _get_land_clearing_mgr()
		if lcm != null and lcm.has_method("get_order"):
			var ord: Dictionary = lcm.call("get_order", active_clearing_order_id)
			if not ord.is_empty():
				ord["state"] = LandClearingManagerScript.OrderState.PAUSED_FOR_REST
				ord["status_reason"] = "Đang nghỉ, công việc khai hoang được giữ lại"
	var tmgr_rest := _get_territory_mgr()
	if tmgr_rest != null and int(tmgr_rest.call("get_owned_count")) <= 0:
		current_path.clear()
		rest_phase = RestPhase.NONE
		rest_house_id = ""
		rest_entry_cell = Vector2i(-1, -1)
		status_reason = "Quá kiệt sức, nghỉ ngơi tại chỗ"
		return
	var resolved := _resolve_rest_house_and_path()
	if not resolved.is_empty():
		rest_house_id = str(resolved.get("house_id", ""))
		rest_entry_cell = resolved.get("access_cell", Vector2i(-1, -1))
		var r_path: Array[Vector2i] = resolved.get("path", [])
		rest_phase = RestPhase.RETURNING_HOME
		status_reason = "Đang trở về nhà nghỉ"
		if current_cell == rest_entry_cell:
			current_path.clear()
			_on_arrived_at_home_access()
		else:
			current_path = r_path
	else:
		current_path.clear()
		rest_phase = RestPhase.NONE
		rest_house_id = ""
		rest_entry_cell = Vector2i(-1, -1)
		status_reason = "Quá kiệt sức, nghỉ ngơi tại chỗ"

func _on_hour_passed(_hour: int, _day: int) -> void:
	if not is_alive():
		return

	var fatigue_mult: float = 1.0
	var es := _get_event_system()
	if es != null and es.has_method("get_active_fatigue_multiplier"):
		fatigue_mult = float(es.call("get_active_fatigue_multiplier", _day))
		if is_nan(fatigue_mult) or is_inf(fatigue_mult) or fatigue_mult <= 0.0:
			fatigue_mult = 1.0
	fatigue_mult *= get_fatigue_gain_multiplier()

	match current_state:
		State.WORKING, State.HAULING, State.GUARDING:
			hunger = minf(100.0, hunger + 4.167)
			fatigue = minf(100.0, fatigue + 4.0 * fatigue_mult)
		State.IDLE:
			hunger = minf(100.0, hunger + 2.0)
			fatigue = minf(100.0, fatigue + 1.0 * fatigue_mult)
		State.RESTING:
			# Fatigue recovery for State.RESTING is handled exclusively by _process_resting(delta) at 12.5/game-hour.
			pass

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
	if rest_phase != RestPhase.NONE or rest_house_id != "":
		wake_from_indoor_rest()
	current_state = State.IDLE
	is_stranded_with_cargo = false
	is_waiting_at_dropoff = false
	if has_manual_command():
		cancel_manual_command("Dân làng tử vong", CancelSource.DEATH)
	if active_clearing_order_id != "":
		var lcm := _get_land_clearing_mgr()
		if lcm != null and lcm.has_method("get_order"):
			var ord: Dictionary = lcm.call("get_order", active_clearing_order_id)
			if not ord.is_empty():
				ord["assigned_citizen_id"] = ""
				ord["state"] = LandClearingManagerScript.OrderState.QUEUED
		active_clearing_order_id = ""
	if current_path != null:
		current_path.clear()
	if active_job != null:
		if job_mgr != null:
			job_mgr.release_job(active_job)
		active_job = null

	if not _death_processed:
		_death_processed = true
		# Conserve carried cargo on death (BUG-001) before emitting death signal
		if carrying_amount > 0 and not carrying_resource.is_empty():
			if _get_resource_manager() != null:
				recover_cargo()
		citizen_died.emit(citizen_id)

func is_alive() -> bool:
	return health > 0.0 and not _death_processed

func interrupt_current_job(reason: String = "", allow_interrupt_rest: bool = false) -> bool:
	var is_resting: bool = rest_phase != RestPhase.NONE or current_state == State.RESTING
	if is_resting:
		if not allow_interrupt_rest:
			return false
		if not rest_house_id.is_empty():
			_unregister_indoor_occupant(rest_house_id)
		if rest_phase in [RestPhase.ENTERING_HOME, RestPhase.RESTING_INSIDE, RestPhase.EXITING_HOME]:
			if not rest_house_id.is_empty():
				var exit_cell: Vector2i = _resolve_valid_exit_cell(rest_house_id)
				if exit_cell != Vector2i(-1, -1):
					current_cell = exit_cell
					position = IsoMath.map_to_local(exit_cell)
		_finish_resting_to_idle()

	cancel_roaming()
	_release_natural_resource_reservation()
	_release_hunt_reservation()

	if active_job != null:
		if job_mgr != null:
			job_mgr.release_job(active_job)
		active_job = null

	current_path.clear()
	_follower_source_path.clear()
	_path_follower.clear()
	_stop_walk_animation()

	if carrying_amount > 0 and not carrying_resource.is_empty():
		is_stranded_with_cargo = false
		_cargo_retry_timer = 0.0

	current_state = State.IDLE
	if not reason.is_empty():
		status_reason = reason
	else:
		_update_reason()
	return true

func can_accept_role_change(new_role: String, force: bool = false) -> bool:
	if new_role == "guard" and not is_barracks_active():
		return false
	if not force:
		if carrying_amount > 0:
			return false
		if has_manual_command():
			return false
		if rest_phase != RestPhase.NONE or current_state == State.RESTING:
			return false
	return true

func set_role(new_role: String, force: bool = false) -> bool:
	if new_role == "guard" and not is_barracks_active():
		status_reason = "Cần Doanh Trại đang hoạt động"
		return false
	if not can_accept_role_change(new_role, force):
		return false

	if role != new_role:
		interrupt_current_job("", force)
		role = new_role
		current_state = State.IDLE
		_update_reason()
		_evaluate_schedule_transition()
	return true

func _update_reason() -> void:
	if has_manual_command():
		if bool(manual_command.get("is_paused", false)):
			if current_state == State.SEEKING_FOOD:
				status_reason = "Tạm hoãn lệnh: Đang đói, đi tìm lương thực tại kho"
				return
			elif current_state == State.RESTING:
				status_reason = "Tạm hoãn lệnh: Quá kiệt sức, nghỉ ngơi hồi phục"
				return
		var cmd_type: String = String(manual_command.get("type", ""))
		match cmd_type:
			"move":
				var t_cell: Vector2i = manual_command.get("target_cell", Vector2i(-1, -1))
				status_reason = "Đang di chuyển theo lệnh đến (%d, %d)" % [t_cell.x, t_cell.y]
			"chop":
				if current_state == State.HAULING:
					status_reason = "Đang vận chuyển %d %s về kho theo lệnh" % [carrying_amount, carrying_resource]
				elif current_state == State.WORKING:
					status_reason = "Đang chặt cây theo lệnh (%.1f / %.1f giờ)" % [
						float(manual_command.get("work_hours_done", 0.0)),
						float(manual_command.get("work_hours_required", 5.0))
					]
				else:
					status_reason = "Đang di chuyển đến khu vực đốn gỗ theo lệnh"
			"mine":
				if current_state == State.HAULING:
					status_reason = "Đang vận chuyển %d %s về kho theo lệnh" % [carrying_amount, carrying_resource]
				elif current_state == State.WORKING:
					status_reason = "Đang khai thác đá theo lệnh (%.1f / %.1f giờ)" % [
						float(manual_command.get("work_hours_done", 0.0)),
						float(manual_command.get("work_hours_required", 5.0))
					]
				else:
					status_reason = "Đang di chuyển đến khu vực khai thác đá theo lệnh"
			"build":
				if current_state == State.WORKING:
					status_reason = "Đang thi công xây dựng theo lệnh"
				else:
					status_reason = "Đang di chuyển đến công trường xây dựng theo lệnh"
			"haul":
				if current_state == State.HAULING:
					status_reason = "Đang vận chuyển %d %s về kho theo lệnh" % [carrying_amount, carrying_resource]
				else:
					status_reason = "Đang di chuyển đến nơi bốc hàng theo lệnh"
			"explore":
				status_reason = "Đang di chuyển khám phá điểm mốc theo lệnh"
		return

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

# ==============================================================================
# PACKAGE 2K: MANUAL CITIZEN COMMANDS & DIRECT LABOR DISPATCH
# ==============================================================================

func has_manual_command() -> bool:
	return bool(manual_command.get("is_active", false))

func get_manual_command() -> Dictionary:
	return manual_command.duplicate()

func serialize_manual_command() -> Dictionary:
	var t_cell: Vector2i = manual_command.get("target_cell", Vector2i(-1, -1))
	return {
		"type": String(manual_command.get("type", "")),
		"target_cell_x": t_cell.x,
		"target_cell_y": t_cell.y,
		"target_id": String(manual_command.get("target_id", "")),
		"work_hours_required": float(manual_command.get("work_hours_required", 0.0)),
		"work_hours_done": float(manual_command.get("work_hours_done", 0.0)),
		"is_active": bool(manual_command.get("is_active", false)),
		"is_paused": bool(manual_command.get("is_paused", false)),
		"pause_reason": String(manual_command.get("pause_reason", ""))
	}

func restore_manual_command(cmd_data: Dictionary) -> void:
	if not (cmd_data is Dictionary) or not bool(cmd_data.get("is_active", false)):
		manual_command = {
			"type": "",
			"target_cell": Vector2i(-1, -1),
			"target_id": "",
			"work_hours_required": 0.0,
			"work_hours_done": 0.0,
			"is_active": false,
			"is_paused": false,
			"pause_reason": ""
		}
		return

	var c_type: String = String(cmd_data.get("type", ""))
	var target_cell := Vector2i(int(cmd_data.get("target_cell_x", -1)), int(cmd_data.get("target_cell_y", -1)))
	if cmd_data.has("target_cell") and cmd_data["target_cell"] is Vector2i:
		target_cell = cmd_data["target_cell"]
	var target_id: String = String(cmd_data.get("target_id", ""))

	if carrying_amount <= 0:
		var is_valid := _check_manual_target_validity(c_type, target_cell, target_id)
		if not is_valid:
			manual_command = {
				"type": "",
				"target_cell": Vector2i(-1, -1),
				"target_id": "",
				"work_hours_required": 0.0,
				"work_hours_done": 0.0,
				"is_active": false,
				"is_paused": false,
				"pause_reason": ""
			}
			current_state = State.IDLE
			status_reason = "Lệnh thủ công từ bản lưu trước không còn mục tiêu hợp lệ"
			return

	manual_command = {
		"type": c_type,
		"target_cell": target_cell,
		"target_id": target_id,
		"work_hours_required": float(cmd_data.get("work_hours_required", 0.0)),
		"work_hours_done": float(cmd_data.get("work_hours_done", 0.0)),
		"is_active": true,
		"is_paused": bool(cmd_data.get("is_paused", false)),
		"pause_reason": String(cmd_data.get("pause_reason", ""))
	}

	if not manual_command["is_paused"]:
		if carrying_amount > 0:
			var drop_cell := _get_storage_dropoff_cell()
			if current_cell == drop_cell:
				_deposit_hauler_cargo()
			else:
				if nav != null:
					current_path = _find_civilian_path(current_cell, drop_cell)
				current_state = State.HAULING
				_update_reason()
		elif current_cell == target_cell or (c_type in ["chop", "mine"] and IsoMath.grid_distance(current_cell, target_cell) <= 1):
			_arrive_at_manual_destination()
		else:
			if nav != null:
				current_path = _find_civilian_path(current_cell, target_cell)
			current_state = State.MOVING_TO_JOB
			_update_reason()

func _is_tree_at_cell(cell: Vector2i) -> bool:
	if world_data == null:
		return true
	if world_data.get("props") != null:
		for p in world_data.props:
			if p.get("cell") == cell and p.get("type") in ["tree", "forest"]:
				return true
	return false

func _is_rock_at_cell(cell: Vector2i) -> bool:
	if world_data == null:
		return true
	if world_data.get("props") != null:
		for p in world_data.props:
			if p.get("cell") == cell and p.get("type") in ["rock", "mountain", "stone"]:
				return true
	return false

func _find_building_at_cell(cell: Vector2i) -> Dictionary:
	if world_data != null and world_data.get("buildings") != null:
		for b in world_data.buildings:
			var origin: Vector2i = b.get("cell", Vector2i(-1, -1))
			var size: Vector2i = b.get("size", Vector2i(1, 1))
			if cell.x >= origin.x and cell.x < origin.x + size.x and cell.y >= origin.y and cell.y < origin.y + size.y:
				return b
	var wv := _get_world_view()
	if wv != null and wv.has_method("_get_building_at_cell"):
		return wv.call("_get_building_at_cell", cell)
	return {}

func _remove_harvested_prop_at_cell(cell: Vector2i) -> void:
	if world_data != null and world_data.get("props") != null:
		for i in range(world_data.props.size() - 1, -1, -1):
			if world_data.props[i].get("cell") == cell:
				world_data.props.remove_at(i)
				break
		if world_data.get("occupancy") != null and IsoMath.is_in_bounds(cell):
			world_data.occupancy[cell.x][cell.y] = false
	var wv := _get_world_view()
	if wv != null and wv.get("props_container") != null:
		for child in wv.props_container.get_children():
			if child.get_meta("cell", Vector2i(-1, -1)) == cell or (child is Node2D and IsoMath.local_to_map(child.position) == cell):
				child.queue_free()
				break

func issue_manual_command(cmd_type: String, target_cell: Vector2i, target_id: String = "", extra_data: Dictionary = {}) -> Dictionary:
	if not is_alive():
		return {"success": false, "reason": "Dân làng đã tử vong, không thể nhận lệnh"}

	const VALID_COMMANDS: Array[String] = ["move", "chop", "mine", "build", "haul", "explore"]
	if not (cmd_type in VALID_COMMANDS):
		return {"success": false, "reason": "Loại lệnh không hợp lệ: %s" % cmd_type}

	if not IsoMath.is_in_bounds(target_cell):
		return {"success": false, "reason": "Tọa độ mục tiêu (%d, %d) nằm ngoài bản đồ" % [target_cell.x, target_cell.y]}

	var tmgr := _get_territory_mgr()
	if tmgr != null:
		if int(tmgr.call("get_owned_count")) <= 0:
			var allow_th_build: bool = false
			if role == "builder" and cmd_type == "build":
				var wd_cmd = _get_clearing_world_data()
				var th_id_cmd := target_id
				if th_id_cmd == "" and wd_cmd != null:
					var bd_at := _find_building_at_cell(target_cell)
					if not bd_at.is_empty():
						th_id_cmd = str(bd_at.get("id", ""))
				if th_id_cmd != "" and wd_cmd != null:
					var bd_th := BuildingSystem.get_building_by_id(th_id_cmd, wd_cmd)
					if not bd_th.is_empty() and str(bd_th.get("type", "")) == "townhall" and (str(bd_th.get("state", "")) == "under_construction" or bool(bd_th.get("is_repairing", false))):
						allow_th_build = true
			if not allow_th_build:
				return {"success": false, "reason": "Không có lãnh thổ hợp lệ để dân làng di chuyển"}
		elif cmd_type in ["move", "chop", "mine", "build", "explore"] and not bool(tmgr.call("is_cell_owned", target_cell)):
			return {"success": false, "reason": "Mục tiêu (%d, %d) nằm ngoài lãnh thổ vương quốc" % [target_cell.x, target_cell.y]}

	if carrying_amount > 0:
		return {"success": false, "reason": "Dân làng đang mang hàng trên người (%d %s), hãy dỡ hàng về kho trước khi nhận lệnh mới" % [carrying_amount, carrying_resource]}

	cancel_roaming()

	# Specific command validation
	match cmd_type:
		"move":
			if nav != null and not nav.is_cell_walkable(target_cell):
				return {"success": false, "reason": "Vị trí đích không thể đi tới (bị chặn hoặc mặt nước)"}
			if nav != null and _get_territory_mgr() != null and _find_civilian_path(current_cell, target_cell).is_empty():
				return {"success": false, "reason": "Không tìm được đường hợp lệ trong lãnh thổ tới (%d, %d)" % [target_cell.x, target_cell.y]}
			if nav != null:
				var path := _find_civilian_path(current_cell, target_cell)
				if path.is_empty() and current_cell != target_cell:
					return {"success": false, "reason": "Không thể tìm đường đi tới vị trí chỉ định"}
		"chop":
			if not _is_tree_at_cell(target_cell):
				return {"success": false, "reason": "Mục tiêu không phải là cây cối hoặc rừng"}
			if nav != null:
				var path := _find_civilian_path(current_cell, target_cell)
				if path.is_empty() and IsoMath.grid_distance(current_cell, target_cell) > 1:
					return {"success": false, "reason": "Không thể tiếp cận khu vực đốn gỗ (bị chặn đường)"}
		"mine":
			if not _is_rock_at_cell(target_cell):
				return {"success": false, "reason": "Mục tiêu không phải là mỏ đá hoặc núi đá"}
			if nav != null:
				var path := _find_civilian_path(current_cell, target_cell)
				if path.is_empty() and IsoMath.grid_distance(current_cell, target_cell) > 1:
					return {"success": false, "reason": "Không thể tiếp cận khu vực khai thác đá (bị chặn đường)"}
		"build":
			if target_id == "":
				var b_data := _find_building_at_cell(target_cell)
				if not b_data.is_empty():
					target_id = b_data.get("id", "")
			if target_id == "":
				return {"success": false, "reason": "Không tìm thấy công trình tại vị trí chỉ định"}
			var is_uc := is_building_under_construction(target_id)
			var is_upg := false
			if world_data != null:
				var b_obj = BuildingSystem.get_building_by_id(target_id, world_data)
				if not b_obj.is_empty() and bool(b_obj.get("is_upgrading", false)):
					is_upg = true
			if not is_uc and not is_upg:
				return {"success": false, "reason": "Công trình không ở trạng thái thi công hoặc nâng cấp"}
			if nav != null:
				var path := _find_civilian_path(current_cell, target_cell)
				if path.is_empty() and IsoMath.grid_distance(current_cell, target_cell) > 1:
					return {"success": false, "reason": "Không thể tiếp cận công trường xây dựng"}
		"haul":
			if workplace_mgr != null and target_id != "":
				var wp = workplace_mgr.get_workplace(target_id)
				if wp == null or wp.buffer_amount <= 0:
					return {"success": false, "reason": "Kho đệm của nơi làm việc này đang trống, không có hàng"}
			elif workplace_mgr != null and target_id == "":
				var b_data := _find_building_at_cell(target_cell)
				if not b_data.is_empty():
					target_id = b_data.get("id", "")
					var wp = workplace_mgr.get_workplace(target_id)
					if wp == null or wp.buffer_amount <= 0:
						return {"success": false, "reason": "Kho đệm của nơi làm việc này đang trống, không có hàng"}
				else:
					return {"success": false, "reason": "Không tìm thấy nơi làm việc tại vị trí chỉ định"}
			if carrying_amount > 0:
				return {"success": false, "reason": "Dân làng đang mang hàng khác trên người (%d %s), hãy dỡ hàng trước" % [carrying_amount, carrying_resource]}
			if nav != null:
				var path := _find_civilian_path(current_cell, target_cell)
				if path.is_empty() and IsoMath.grid_distance(current_cell, target_cell) > 1:
					return {"success": false, "reason": "Không thể tiếp cận nơi làm việc"}
		"explore":
			var p_mgr := _get_poi_manager()
			if p_mgr != null:
				var poi = p_mgr.get_poi(target_id) if target_id != "" else null
				if poi == null:
					for p_item in p_mgr.get_all_pois():
						if p_item.cell == target_cell:
							poi = p_item
							target_id = poi.id
							break
				if poi != null and poi.state == POIManager.POIState.CLAIMED:
					return {"success": false, "reason": "Điểm khám phá này đã được khai phá từ trước"}
			if nav != null:
				var path := _find_civilian_path(current_cell, target_cell)
				if path.is_empty() and IsoMath.grid_distance(current_cell, target_cell) > 2:
					return {"success": false, "reason": "Không có đường đi tới điểm khám phá (bị chặn đường)"}

	# Clean release of any autonomous routine job
	_release_natural_resource_reservation()
	_release_hunt_reservation()
	if active_job != null:
		if job_mgr != null:
			job_mgr.release_job(active_job)
		active_job = null

	# Wake cleanly if citizen was resting indoors or mid-transition
	if current_state == State.RESTING and rest_phase != RestPhase.NONE:
		wake_from_indoor_rest()

	var req_hours: float = 5.0 if cmd_type in ["chop", "mine"] else float(extra_data.get("work_hours_required", 0.0))
	manual_command = {
		"type": cmd_type,
		"target_cell": target_cell,
		"target_id": target_id,
		"work_hours_required": req_hours,
		"work_hours_done": 0.0,
		"is_active": true,
		"is_paused": false,
		"pause_reason": ""
	}

	# Immediate arrival check (e.g. already at target or adjacent to harvest/building/poi)
	var is_adjacent: bool = false
	if cmd_type in ["chop", "mine"] and IsoMath.grid_distance(current_cell, target_cell) <= 1:
		is_adjacent = true
	elif cmd_type == "build" and IsoMath.grid_distance(current_cell, target_cell) <= 2:
		is_adjacent = true
	elif cmd_type == "explore" and IsoMath.grid_distance(current_cell, target_cell) <= 2:
		is_adjacent = true

	if current_cell == target_cell or is_adjacent:
		current_path.clear()
		_arrive_at_manual_destination()
	else:
		if nav != null:
			current_path = _find_civilian_path(current_cell, target_cell)
		current_state = State.MOVING_TO_JOB
		_update_reason()

	return {"success": true, "command": manual_command.duplicate()}

func cancel_manual_command(reason: String = "Người chơi hủy lệnh", source: int = CancelSource.PLAYER) -> bool:
	if not has_manual_command():
		return false

	# Player cancellation rejected while carrying cargo to prevent cargo loss or off-site deposits
	if source == CancelSource.PLAYER and carrying_amount > 0:
		status_reason = "Không thể hủy khi đang mang hàng (%d %s), hãy chờ dỡ hàng về kho" % [carrying_amount, carrying_resource]
		return false

	# Target invalidation while carrying cargo: cargo must be conserved by routing to storehouse, never cancelled off-site
	if source == CancelSource.TARGET_INVALIDATED and carrying_amount > 0:
		if _is_at_storage_dropoff():
			_deposit_hauler_cargo()
		else:
			var drop_cell := _get_storage_dropoff_cell()
			if nav != null:
				current_path = _find_civilian_path(current_cell, drop_cell)
			if not current_path.is_empty():
				current_state = State.HAULING
				is_stranded_with_cargo = false
				status_reason = "Mục tiêu bị hủy, đang vận chuyển %d %s về kho an toàn" % [carrying_amount, carrying_resource]
			else:
				current_state = State.IDLE
				is_stranded_with_cargo = true
				status_reason = "Đang giữ %d %s, chưa tìm được đường về kho" % [carrying_amount, carrying_resource]
		return false

	manual_command = {
		"type": "",
		"target_cell": Vector2i(-1, -1),
		"target_id": "",
		"work_hours_required": 0.0,
		"work_hours_done": 0.0,
		"is_active": false,
		"is_paused": false,
		"pause_reason": ""
	}
	current_path.clear()
	current_state = State.IDLE
	status_reason = "Đã hủy lệnh: %s" % reason
	manual_command_cancelled.emit(citizen_id, reason)
	return true

func _check_manual_target_validity(cmd_type: String, target_cell: Vector2i, target_id: String) -> bool:
	match cmd_type:
		"move":
			return nav == null or nav.is_cell_walkable(target_cell)
		"chop":
			return _is_tree_at_cell(target_cell)
		"mine":
			return _is_rock_at_cell(target_cell)
		"build":
			if target_id != "":
				var is_uc := is_building_under_construction(target_id)
				var is_upg := false
				if world_data != null:
					var b_obj = BuildingSystem.get_building_by_id(target_id, world_data)
					if not b_obj.is_empty() and bool(b_obj.get("is_upgrading", false)):
						is_upg = true
				return is_uc or is_upg
			return false
		"haul":
			if workplace_mgr != null and workplace_mgr.has_method("get_workplace"):
				var wp = workplace_mgr.get_workplace(target_id)
				return wp != null and wp.buffer_amount > 0
			return true
		"explore":
			var p_mgr := _get_poi_manager()
			if p_mgr != null:
				var poi = p_mgr.get_poi(target_id)
				return poi != null and poi.state != POIManager.POIState.CLAIMED
			return true
	return true

func _resume_paused_manual_command() -> void:
	if not has_manual_command():
		return
	manual_command["is_paused"] = false
	manual_command["pause_reason"] = ""

	if carrying_amount > 0:
		if _is_at_storage_dropoff():
			_deposit_hauler_cargo()
		else:
			var drop_cell := _get_storage_dropoff_cell()
			if nav != null:
				current_path = _find_civilian_path(current_cell, drop_cell)
				if current_path.is_empty():
					current_state = State.IDLE
					is_stranded_with_cargo = true
					status_reason = "Đang giữ %d %s, chưa tìm được đường về kho" % [carrying_amount, carrying_resource]
					return
			current_state = State.HAULING
			is_stranded_with_cargo = false
			status_reason = "Đang vận chuyển %d %s về kho theo lệnh" % [carrying_amount, carrying_resource]
		return

	var is_valid := _check_manual_target_validity(manual_command.type, manual_command.target_cell, manual_command.target_id)
	if not is_valid:
		cancel_manual_command("Mục tiêu lệnh không còn hợp lệ sau khi hồi phục thể lực", CancelSource.TARGET_INVALIDATED)
		return

	if current_cell == manual_command.target_cell or (manual_command.type in ["chop", "mine"] and IsoMath.grid_distance(current_cell, manual_command.target_cell) <= 1):
		_arrive_at_manual_destination()
	else:
		if nav != null:
			current_path = _find_civilian_path(current_cell, manual_command.target_cell)
			if current_path.is_empty():
				cancel_manual_command("Không thể tìm đường trở lại mục tiêu lệnh", CancelSource.TARGET_INVALIDATED)
				return
		current_state = State.MOVING_TO_JOB
		_update_reason()

func _execute_active_manual_command() -> void:
	if carrying_amount > 0:
		if _is_at_storage_dropoff():
			_deposit_hauler_cargo()
		else:
			var drop_cell := _get_storage_dropoff_cell()
			if nav != null and current_path.is_empty():
				current_path = _find_civilian_path(current_cell, drop_cell)
			if not current_path.is_empty():
				current_state = State.HAULING
				is_stranded_with_cargo = false
				status_reason = "Đang vận chuyển %d %s về kho theo lệnh" % [carrying_amount, carrying_resource]
			else:
				current_state = State.IDLE
				is_stranded_with_cargo = true
				status_reason = "Đang giữ %d %s, chưa tìm được đường về kho" % [carrying_amount, carrying_resource]
		return

	if current_path.is_empty():
		if current_cell == manual_command.target_cell or (manual_command.type in ["chop", "mine"] and IsoMath.grid_distance(current_cell, manual_command.target_cell) <= 1):
			_arrive_at_manual_destination()
		else:
			if nav != null:
				current_path = _find_civilian_path(current_cell, manual_command.target_cell)
			if not current_path.is_empty():
				current_state = State.MOVING_TO_JOB
				_update_reason()
			else:
				cancel_manual_command("Không tìm thấy đường đi tới mục tiêu", CancelSource.TARGET_INVALIDATED)

func _arrive_at_manual_destination() -> void:
	var cmd_type: String = String(manual_command.get("type", ""))
	match cmd_type:
		"move":
			manual_command["is_active"] = false
			current_state = State.IDLE
			status_reason = "Đã đến điểm chỉ định"
			manual_command_completed.emit(citizen_id, "move")
		"chop", "mine":
			current_state = State.WORKING
			_update_reason()
		"build":
			current_state = State.WORKING
			_update_reason()
		"haul":
			var wp_id: String = String(manual_command.get("target_id", ""))
			var picked_up := 0
			if workplace_mgr != null and workplace_mgr.has_method("pickup_from_buffer"):
				picked_up = workplace_mgr.pickup_from_buffer(wp_id, carry_capacity)
			if picked_up > 0:
				var wp = workplace_mgr.get_workplace(wp_id) if workplace_mgr.has_method("get_workplace") else null
				carrying_resource = wp.output_resource if wp != null else "wood"
				carrying_amount = picked_up
				carrying_source_workplace_id = wp_id
				var drop_cell := _get_storage_dropoff_cell()
				if current_cell == drop_cell:
					_deposit_hauler_cargo()
				else:
					if nav != null:
						current_path = _find_civilian_path(current_cell, drop_cell)
					if not current_path.is_empty():
						current_state = State.HAULING
						is_stranded_with_cargo = false
						status_reason = "Đang vận chuyển %d %s về kho theo lệnh" % [carrying_amount, carrying_resource]
					else:
						current_state = State.IDLE
						is_stranded_with_cargo = true
						status_reason = "Đang giữ %d %s, chưa tìm được đường về kho" % [carrying_amount, carrying_resource]
			else:
				manual_command["is_active"] = false
				current_state = State.IDLE
				status_reason = "Kho đệm đã hết hàng"
				manual_command_completed.emit(citizen_id, "haul")
		"explore":
			var poi_id: String = String(manual_command.get("target_id", ""))
			var p_mgr := _get_poi_manager()
			var rm: Object = _get_resource_manager()
			if p_mgr != null and rm != null and poi_id != "":
				p_mgr.claim_poi_reward(poi_id, rm)
			manual_command["is_active"] = false
			current_state = State.IDLE
			status_reason = "Đã khám phá điểm mốc thành công"
			manual_command_completed.emit(citizen_id, "explore")

func _process_manual_working(delta: float) -> void:
	var delta_hours := _get_delta_hours(delta)

	# Priority 2 survival check
	if hunger >= 85.0 and _is_central_food_available():
		manual_command["is_paused"] = true
		manual_command["pause_reason"] = "Đói bụng cần ăn lương thực"
		_seek_food()
		return
	if fatigue >= 90.0:
		manual_command["is_paused"] = true
		manual_command["pause_reason"] = "Kiệt sức cần nghỉ ngơi"
		_seek_rest()
		return

	var cmd_type: String = String(manual_command.get("type", ""))
	match cmd_type:
		"chop":
			var skill_mult := get_skill_efficiency("woodcutting")
			var effective_work_hours := delta_hours * skill_mult
			manual_command["work_hours_done"] = float(manual_command.get("work_hours_done", 0.0)) + effective_work_hours
			var req_h: float = float(manual_command.get("work_hours_required", 5.0))
			if float(manual_command["work_hours_done"]) >= req_h:
				award_work_xp("woodcutting", 10.0)
				carrying_resource = "wood"
				carrying_amount = mini(10, carry_capacity)
				var t_cell: Vector2i = manual_command.get("target_cell", Vector2i(-1, -1))
				_remove_harvested_prop_at_cell(t_cell)
				var drop_cell := _get_storage_dropoff_cell()
				if current_cell == drop_cell:
					_deposit_hauler_cargo()
				else:
					if nav != null:
						current_path = _find_civilian_path(current_cell, drop_cell)
					if not current_path.is_empty():
						current_state = State.HAULING
						is_stranded_with_cargo = false
						status_reason = "Đang vận chuyển %d gỗ về kho theo lệnh" % carrying_amount
					else:
						current_state = State.IDLE
						is_stranded_with_cargo = true
						status_reason = "Đang giữ %d gỗ, chưa tìm được đường về kho" % carrying_amount
			else:
				status_reason = "Đang chặt cây theo lệnh (%.1f / %.1f giờ)" % [
					float(manual_command["work_hours_done"]),
					req_h
				]
		"mine":
			var skill_mult := get_skill_efficiency("mining")
			var effective_work_hours := delta_hours * skill_mult
			manual_command["work_hours_done"] = float(manual_command.get("work_hours_done", 0.0)) + effective_work_hours
			var req_h: float = float(manual_command.get("work_hours_required", 5.0))
			if float(manual_command["work_hours_done"]) >= req_h:
				award_work_xp("mining", 10.0)
				carrying_resource = "stone"
				carrying_amount = mini(10, carry_capacity)
				var t_cell: Vector2i = manual_command.get("target_cell", Vector2i(-1, -1))
				_remove_harvested_prop_at_cell(t_cell)
				var drop_cell := _get_storage_dropoff_cell()
				if current_cell == drop_cell:
					_deposit_hauler_cargo()
				else:
					if nav != null:
						current_path = _find_civilian_path(current_cell, drop_cell)
					if not current_path.is_empty():
						current_state = State.HAULING
						is_stranded_with_cargo = false
						status_reason = "Đang vận chuyển %d đá về kho theo lệnh" % carrying_amount
					else:
						current_state = State.IDLE
						is_stranded_with_cargo = true
						status_reason = "Đang giữ %d đá, chưa tìm được đường về kho" % carrying_amount
			else:
				status_reason = "Đang khai thác đá theo lệnh (%.1f / %.1f giờ)" % [
					float(manual_command["work_hours_done"]),
					req_h
				]
		"build":
			var b_id: String = String(manual_command.get("target_id", ""))
			if b_id == "":
				cancel_manual_command("Không có mã công trình để thi công")
				return
			var skill_mult := get_skill_efficiency("building")
			var effective_delta_hours := delta_hours * skill_mult

			var res: Dictionary = {}
			if construction_handler.is_valid():
				var argc := construction_handler.get_argument_count()
				if argc >= 2:
					res = construction_handler.call(b_id, effective_delta_hours)
				else:
					res = construction_handler.call(effective_delta_hours)
			else:
				var wv := _get_world_view()
				if wv != null and wv.has_method("advance_construction_work"):
					res = wv.advance_construction_work(b_id, effective_delta_hours)
				elif world_data != null:
					var b_obj = BuildingSystem.get_building_by_id(b_id, world_data)
					if not b_obj.is_empty() and bool(b_obj.get("is_upgrading", false)):
						res = BuildingSystem.advance_upgrade(b_obj, effective_delta_hours, world_data)
						if res.get("completed", false):
							var rm_node: Node = get_node_or_null("/root/ResourceManager") if (is_inside_tree() and has_node("/root/ResourceManager")) else null
							var comp_res := BuildingSystem.complete_building_upgrade(b_obj, world_data, rm_node)
							if not comp_res.get("success", false):
								res["completed"] = false
					else:
						res = BuildingSystem.advance_construction(b_id, effective_delta_hours, world_data)
						if res.get("completed", false):
							var rm_node: Node = get_node_or_null("/root/ResourceManager") if (is_inside_tree() and has_node("/root/ResourceManager")) else null
							BuildingSystem.complete_building(b_id, world_data, rm_node)

			if not res.get("success", false):
				cancel_manual_command("Công trình xây dựng đã hoàn thành hoặc bị hủy", CancelSource.TARGET_INVALIDATED)
				return

			award_work_xp("building", effective_delta_hours * 5.0)

			if res.get("completed", false):
				manual_command["is_active"] = false
				current_state = State.IDLE
				status_reason = "Công trình đã hoàn thành thi công theo lệnh"
				manual_command_completed.emit(citizen_id, "build")
				return

			status_reason = "Đang thi công xây dựng theo lệnh (%.1f / %.1f giờ)" % [
				res.get("progress", 0.0),
				res.get("hours", 0.0)
			]

# =============================================================================
# LAND CLEARING & RESOURCE RECOVERY INTEGRATION (KU-POST-MVP-LAND-CLEARING-01)
# =============================================================================

func _process_active_clearing_order() -> void:
	var lcm := _get_land_clearing_mgr()
	if lcm == null or not lcm.has_method("get_order"):
		active_clearing_order_id = ""
		return
	var ord: Dictionary = lcm.call("get_order", active_clearing_order_id)
	if ord.is_empty():
		active_clearing_order_id = ""
		return
	var st: int = int(ord.get("state", LandClearingManagerScript.OrderState.CANCELLED))
	if st == LandClearingManagerScript.OrderState.COMPLETED or st == LandClearingManagerScript.OrderState.CANCELLED:
		active_clearing_order_id = ""
		return
	if str(ord.get("required_role", "")) != role:
		lcm.call("_release_order_reservations", ord, [self])
		ord["state"] = LandClearingManagerScript.OrderState.QUEUED
		active_clearing_order_id = ""
		return

	var target_cell: Vector2i = ord.get("cell", Vector2i(-1, -1))
	var slot: Vector2i = ord.get("work_slot", Vector2i(-1, -1))
	if slot == Vector2i(-1, -1) and nav != null:
		slot = nav.find_closest_walkable_adjacent(target_cell, current_cell)
		ord["work_slot"] = slot

	if current_cell != target_cell and IsoMath.grid_distance(current_cell, target_cell) <= 1 and (nav == null or nav.is_cell_walkable(current_cell)):
		_arrive_at_clearing_slot()
		return

	if nav != null and slot != Vector2i(-1, -1):
		var tmgr_clr := _get_territory_mgr()
		if tmgr_clr != null and int(tmgr_clr.call("get_owned_count")) <= 0:
			current_path.clear()
			status_reason = "Lãnh thổ không khả dụng, tạm dừng khai hoang"
			return
		var path := _find_civilian_path(current_cell, slot)
		if not path.is_empty():
			current_path = path
			current_state = State.MOVING_TO_JOB
			ord["state"] = LandClearingManagerScript.OrderState.MOVING
			var noun := "cây" if str(ord.get("prop_type", "")) == "tree" else "đá"
			status_reason = "Đang đi dọn %s tại (%d, %d)" % [noun, target_cell.x, target_cell.y]
			ord["status_reason"] = status_reason
			return

	# Path blocked -> release slot reservation and mark BLOCKED
	ord["state"] = LandClearingManagerScript.OrderState.BLOCKED
	status_reason = "Không tìm được đường đến mục tiêu"
	ord["status_reason"] = status_reason
	lcm.call("_release_order_reservations", ord, [self])
	active_clearing_order_id = ""

func _get_clearing_world_data():
	if world_data != null:
		return world_data
	var wv := _get_world_view()
	if wv != null:
		return wv.get("world_data")
	return null

func _arrive_at_clearing_slot() -> void:
	var lcm := _get_land_clearing_mgr()
	if lcm == null or not lcm.has_method("get_order"):
		active_clearing_order_id = ""
		current_state = State.IDLE
		return
	var ord: Dictionary = lcm.call("get_order", active_clearing_order_id)
	if ord.is_empty():
		active_clearing_order_id = ""
		current_state = State.IDLE
		return
	var target_cell: Vector2i = ord.get("cell", Vector2i(-1, -1))
	if current_cell == target_cell or IsoMath.grid_distance(current_cell, target_cell) > 1:
		_process_active_clearing_order()
		return
	var wd_cur = _get_clearing_world_data()
	var prop: Dictionary = lcm.call("find_prop_at_cell", wd_cur, target_cell)
	if prop.is_empty():
		lcm.call("cancel_clearing_order", active_clearing_order_id, [self])
		active_clearing_order_id = ""
		current_state = State.IDLE
		return
	current_state = State.WORKING
	ord["state"] = LandClearingManagerScript.OrderState.WORKING
	var pct := int(clampf(float(ord.get("work_hours_done", 0.0)) / maxf(0.01, float(ord.get("work_hours_required", 4.0))) * 100.0, 0.0, 100.0))
	var verb := "Đang chặt cây" if str(ord.get("prop_type", "")) == "tree" else "Đang phá đá"
	status_reason = "%s — %d%%" % [verb, pct]
	ord["status_reason"] = status_reason

func _process_clearing_work(delta: float) -> void:
	var lcm := _get_land_clearing_mgr()
	if lcm == null or not lcm.has_method("get_order"):
		active_clearing_order_id = ""
		current_state = State.IDLE
		return
	var ord: Dictionary = lcm.call("get_order", active_clearing_order_id)
	if ord.is_empty():
		active_clearing_order_id = ""
		current_state = State.IDLE
		return
	if str(ord.get("required_role", "")) != role:
		lcm.call("_release_order_reservations", ord, [self])
		ord["state"] = LandClearingManagerScript.OrderState.QUEUED
		active_clearing_order_id = ""
		current_state = State.IDLE
		return

	if hunger >= 85.0 and _is_central_food_available():
		ord["state"] = LandClearingManagerScript.OrderState.PAUSED_FOR_REST
		ord["status_reason"] = "Đói bụng cần ăn lương thực"
		_seek_food()
		return
	if fatigue >= 90.0:
		_seek_rest()
		return

	var target_cell: Vector2i = ord.get("cell", Vector2i(-1, -1))
	if current_cell == target_cell or IsoMath.grid_distance(current_cell, target_cell) > 1:
		current_state = State.IDLE
		_process_active_clearing_order()
		return
	var wd_cur = _get_clearing_world_data()
	var prop: Dictionary = lcm.call("find_prop_at_cell", wd_cur, target_cell)
	if prop.is_empty():
		lcm.call("cancel_clearing_order", active_clearing_order_id, [self])
		active_clearing_order_id = ""
		current_state = State.IDLE
		return

	var delta_hours := _get_delta_hours(delta)
	if delta_hours <= 0.0:
		return

	var skill_name: String = str(ord.get("skill", "woodcutting"))
	var eff := get_skill_efficiency(skill_name)
	var done_h: float = float(ord.get("work_hours_done", 0.0)) + delta_hours * eff
	var req_h: float = maxf(0.01, float(ord.get("work_hours_required", 4.0)))
	ord["work_hours_done"] = done_h
	ord["state"] = LandClearingManagerScript.OrderState.WORKING

	if done_h >= req_h:
		award_work_xp(skill_name, 10.0)
		var rm: Object = _get_resource_manager()
		var wv := _get_world_view()
		var oid := active_clearing_order_id
		active_clearing_order_id = ""
		current_state = State.IDLE
		var comp_res: Dictionary = lcm.call("complete_or_hold_for_storage", oid, wd_cur, rm, wv, [self])
		if bool(comp_res.get("waiting_storage", false)):
			status_reason = "Kho đầy, chờ chỗ chứa tài nguyên khai hoang"
		else:
			status_reason = "Đã dọn mặt bằng thành công"
		return

	var pct := int(clampf(done_h / req_h * 100.0, 0.0, 99.0))
	var verb := "Đang chặt cây" if str(ord.get("prop_type", "")) == "tree" else "Đang phá đá"
	status_reason = "%s — %d%%" % [verb, pct]
	ord["status_reason"] = status_reason

func _process_natural_resource_work(delta: float) -> void:
	var nrm := _get_natural_resource_mgr()
	var wd_cur = _get_clearing_world_data()
	if nrm == null or wd_cur == null or active_resource_node_id == "":
		_release_natural_resource_reservation()
		current_state = State.IDLE
		return

	if hunger >= 70.0 and _is_central_food_available():
		_release_natural_resource_reservation()
		_seek_food()
		return
	if fatigue >= 85.0:
		_release_natural_resource_reservation()
		_seek_rest()
		return
	if carrying_amount >= carry_capacity:
		_release_natural_resource_reservation()
		current_state = State.IDLE
		return

	var node_d: Dictionary = nrm.call("get_node_by_id", active_resource_node_id)
	if node_d.is_empty() or bool(node_d.get("depleted", false)) or int(node_d.get("remaining_qty", 0)) <= 0:
		_release_natural_resource_reservation()
		current_state = State.IDLE
		return
	var node_cell: Vector2i = node_d.get("cell", Vector2i(-1, -1))
	if node_cell.x < 0 or node_cell.y < 0 or IsoMath.grid_distance(current_cell, node_cell) > 1:
		var nr_path: Array[Vector2i] = []
		if nav != null and node_cell.x >= 0 and node_cell.y >= 0:
			nr_path = _find_civilian_path(current_cell, node_cell)
		if not nr_path.is_empty():
			current_path = nr_path
			current_state = State.MOVING_TO_JOB
		else:
			_release_natural_resource_reservation()
			current_state = State.IDLE
		return

	var p_type: String = str(node_d.get("type", ""))
	var spec := EconomyConfig.get_natural_resource_spec(p_type)
	var req_hours: float = maxf(0.1, float(spec.get("work_hours", 2.0)))
	var skill_name: String = str(spec.get("skill", "mining"))
	var delta_hours: float = _get_delta_hours(delta)
	var eff: float = get_skill_efficiency(skill_name)
	_resource_work_hours_done += delta_hours * eff

	if _resource_work_hours_done >= req_hours:
		var free_space: int = maxi(0, carry_capacity - carrying_amount)
		var res: Dictionary = nrm.call("harvest_node", active_resource_node_id, citizen_id, free_space, wd_cur)
		var harvested: int = int(res.get("harvested", 0))
		var res_id: String = str(res.get("resource", ""))
		if harvested > 0 and res_id != "":
			if carrying_resource == "" or carrying_resource == res_id:
				carrying_resource = res_id
				carrying_amount += harvested
			award_work_xp(skill_name, 8.0)
		_release_natural_resource_reservation()
		if carrying_amount > 0:
			var drop_cell := _find_valid_hunter_dropoff_cell()
			if _is_at_storage_dropoff():
				_deposit_hauler_cargo()
			elif drop_cell != Vector2i(-1, -1):
				var path := _find_civilian_path(current_cell, drop_cell)
				if not path.is_empty():
					current_path = path
					current_state = State.HAULING
					is_stranded_with_cargo = false
					status_reason = "Mang tài nguyên về kho"
				else:
					is_stranded_with_cargo = true
					current_state = State.IDLE
			else:
				is_stranded_with_cargo = true
				current_state = State.IDLE
		else:
			current_state = State.IDLE
		return

	var pct := int(clampf(_resource_work_hours_done / req_hours * 100.0, 0.0, 99.0))
	status_reason = "Khai thác %s — %d%%" % [str(spec.get("label", "tài nguyên")), pct]

# ==============================================================================
# PHASE 7: HUNTER PROFESSION & WILDLIFE HUNTING LOOP
# ==============================================================================

const WildlifeConfigScript = preload("res://scripts/world/wildlife_config.gd")

func _has_storage_for_raw_meat(min_amount: int = 2) -> bool:
	var drop_cell := _find_valid_hunter_dropoff_cell()
	if drop_cell == Vector2i(-1, -1):
		return false
	var rm := _get_resource_manager()
	if rm == null or not rm.has_method("add_resource"):
		return false
	var cap: int = 300
	if rm.has_method("get_storage_capacity"):
		cap = int(rm.get_storage_capacity(EconomyConfig.RES_RAW_MEAT))
	var cur: int = int(rm.get_total_stock(EconomyConfig.RES_RAW_MEAT)) if rm.has_method("get_total_stock") else 0
	if cap - cur < min_amount:
		return false
	return true

func _try_start_hunting_work() -> void:
	if carrying_amount > 0:
		return
	var wlm := _get_wildlife_mgr()
	var wd_cur = _get_clearing_world_data()
	var tmgr := _get_territory_mgr()
	var fow := _get_fog_of_war()
	if wlm == null or wd_cur == null or tmgr == null or nav == null:
		_job_retry_timer = 1.5
		status_reason = "Chờ hệ thống săn bắn sẵn sàng"
		return
	if not _has_storage_for_raw_meat(2):
		_job_retry_timer = 2.0
		status_reason = "Kho chưa sẵn sàng hoặc đã đầy thịt sống"
		return
	var res: Dictionary = wlm.call("find_and_reserve_nearest_prey", citizen_id, current_cell, wd_cur, tmgr, fow, nav, Callable(self, "_find_civilian_path"))
	if res.is_empty():
		_job_retry_timer = 1.5
		status_reason = "Không tìm thấy con mồi phù hợp trong phạm vi săn"
		return
	var animal_rec: Dictionary = res["animal"]
	active_hunt_target_id = str(animal_rec.get("id", ""))
	_hunt_work_hours_done = 0.0
	_hunt_pursuit_hours = 0.0
	_hunt_repath_timer = 0.0
	_hunt_last_target_cell = animal_rec.get("cell", Vector2i(-1, -1))
	current_path = res["path"]
	current_state = State.MOVING_TO_JOB
	var sp_name: String = str(WildlifeConfigScript.get_species_def(str(animal_rec.get("species_id", ""))).get("display_name", "con mồi"))
	status_reason = "Đang tiếp cận %s" % sp_name

func _step_hunter_pursuit(delta: float) -> bool:
	var wlm := _get_wildlife_mgr()
	if wlm == null or active_hunt_target_id == "":
		_release_hunt_reservation()
		current_state = State.IDLE
		return false
	if hunger >= 70.0 and _is_central_food_available():
		_release_hunt_reservation()
		_seek_food()
		return false
	if fatigue >= 85.0:
		_release_hunt_reservation()
		_seek_rest()
		return false

	_hunt_pursuit_hours += _get_delta_hours(delta)
	if _hunt_pursuit_hours >= WildlifeConfigScript.HUNTER_MAX_PURSUIT_HOURS:
		_release_hunt_reservation()
		current_path.clear()
		current_state = State.IDLE
		_job_retry_timer = 1.0
		status_reason = "Mất dấu con mồi sau thời gian truy đuổi"
		return false

	var animal_rec: Dictionary = wlm.call("get_animal_by_id", active_hunt_target_id)
	if animal_rec.is_empty() or not is_cell_permitted_for_hunter(animal_rec["cell"]):
		_release_hunt_reservation()
		current_path.clear()
		current_state = State.IDLE
		status_reason = "Con mồi rời khỏi khu vực săn bắn"
		return false

	var a_cell: Vector2i = animal_rec["cell"]
	if IsoMath.grid_distance(current_cell, a_cell) <= 1:
		current_path.clear()
		_arrive_at_hunt_target()
		return false

	_hunt_repath_timer += delta
	if _hunt_repath_timer >= 0.4 and a_cell != _hunt_last_target_cell:
		_hunt_repath_timer = 0.0
		_hunt_last_target_cell = a_cell
		var best_path: Array[Vector2i] = []
		var candidates: Array[Vector2i] = [a_cell, a_cell + Vector2i(1, 0), a_cell + Vector2i(-1, 0), a_cell + Vector2i(0, 1), a_cell + Vector2i(0, -1)]
		for app in candidates:
			if nav != null and nav.is_cell_walkable(app) and is_cell_permitted_for_hunter(app):
				var p := _find_civilian_path(current_cell, app)
				if not p.is_empty():
					best_path = p
					break
		if not best_path.is_empty():
			current_path = best_path
		else:
			_release_hunt_reservation()
			current_path.clear()
			current_state = State.IDLE
			status_reason = "Không thể tiếp cận con mồi"
			return false
	return true

func _arrive_at_hunt_target() -> void:
	var wlm := _get_wildlife_mgr()
	if wlm == null or active_hunt_target_id == "":
		_release_hunt_reservation()
		current_state = State.IDLE
		return
	var animal_rec: Dictionary = wlm.call("get_animal_by_id", active_hunt_target_id)
	if animal_rec.is_empty():
		_release_hunt_reservation()
		current_state = State.IDLE
		return
	var a_cell: Vector2i = animal_rec["cell"]
	if IsoMath.grid_distance(current_cell, a_cell) <= 1:
		if bool(wlm.call("begin_hunting_interaction", active_hunt_target_id, citizen_id)):
			current_state = State.WORKING
			_hunt_work_hours_done = 0.0
			var sp_name: String = str(WildlifeConfigScript.get_species_def(str(animal_rec.get("species_id", ""))).get("display_name", "con mồi"))
			status_reason = "Đang săn %s" % sp_name
		else:
			_release_hunt_reservation()
			current_state = State.IDLE
	else:
		if is_cell_permitted_for_hunter(a_cell):
			var p := _find_civilian_path(current_cell, a_cell)
			if not p.is_empty():
				current_path = p
				current_state = State.MOVING_TO_JOB
				return
		_release_hunt_reservation()
		current_state = State.IDLE

func _process_hunting_work(delta: float) -> void:
	var wlm := _get_wildlife_mgr()
	if wlm == null or active_hunt_target_id == "":
		_release_hunt_reservation()
		current_state = State.IDLE
		return
	if hunger >= 70.0 and _is_central_food_available():
		_release_hunt_reservation()
		_seek_food()
		return
	if fatigue >= 85.0:
		_release_hunt_reservation()
		_seek_rest()
		return

	var animal_rec: Dictionary = wlm.call("get_animal_by_id", active_hunt_target_id)
	if animal_rec.is_empty():
		_release_hunt_reservation()
		current_state = State.IDLE
		return
	var a_cell: Vector2i = animal_rec.get("cell", Vector2i(-1, -1))
	if a_cell.x < 0 or a_cell.y < 0 or IsoMath.grid_distance(current_cell, a_cell) > 1:
		current_state = State.MOVING_TO_JOB
		return
	var sp: String = str(animal_rec.get("species_id", ""))
	var spec: Dictionary = WildlifeConfigScript.get_species_def(sp)
	var yield_amt: int = int(spec.get("raw_meat_yield", 0))
	if carrying_amount + yield_amt > carry_capacity:
		_release_hunt_reservation()
		current_state = State.IDLE
		return

	var req_hours: float = maxf(0.1, float(spec.get("hunt_duration_hours", 1.5)))
	_hunt_work_hours_done += _get_delta_hours(delta) * get_skill_efficiency("hunting")
	if _hunt_work_hours_done >= req_hours:
		var res: Dictionary = wlm.call("complete_hunt", active_hunt_target_id, citizen_id)
		active_hunt_target_id = ""
		_hunt_work_hours_done = 0.0
		_hunt_pursuit_hours = 0.0
		if bool(res.get("success", false)):
			var got_amt: int = int(res.get("yield", 0))
			var got_res: String = str(res.get("resource", EconomyConfig.RES_RAW_MEAT))
			if got_amt > 0 and (carrying_resource == "" or carrying_resource == got_res):
				carrying_resource = got_res
				carrying_amount += got_amt
			award_work_xp("hunting", 10.0)
		if carrying_amount > 0:
			var drop_cell := _find_valid_hunter_dropoff_cell()
			if _is_at_storage_dropoff():
				_deposit_hauler_cargo()
			elif drop_cell != Vector2i(-1, -1):
				var ret_path := _find_civilian_path(current_cell, drop_cell)
				if not ret_path.is_empty():
					current_path = ret_path
					current_state = State.HAULING
					is_stranded_with_cargo = false
					status_reason = "Mang thịt sống về kho"
				else:
					is_stranded_with_cargo = true
					current_state = State.IDLE
			else:
				is_stranded_with_cargo = true
				current_state = State.IDLE
		else:
			current_state = State.IDLE
		return

	var pct := int(clampf(_hunt_work_hours_done / req_hours * 100.0, 0.0, 99.0))
	status_reason = "Đang săn %s — %d%%" % [str(spec.get("display_name", sp)), pct]
