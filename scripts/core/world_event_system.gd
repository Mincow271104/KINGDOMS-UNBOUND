class_name WorldEventSystem
extends RefCounted
## World Events System for KINGDOMS UNBOUND.
## Generates periodic positive/negative colony events with deterministic cooldowns and UI notifications.

const DEFAULT_TIMED_EFFECT_DAYS: int = 2
const BASE_FARM_MODIFIER_BONUS: float = 0.0
const BASE_FATIGUE_MULTIPLIER: float = 1.0

# Event definitions with full effect-key consumer coverage (BUG-04A..D):
# - farm_modifier_bonus: Timed farm production bonus for DEFAULT_TIMED_EFFECT_DAYS days (consumed by CitizenController/WorldEventSystem).
# - bonus_food: Immediate one-time food stock addition (consumed by WorldEventSystem._apply_resource_effects).
# - fatigue_multiplier: Timed hourly fatigue accumulation multiplier for DEFAULT_TIMED_EFFECT_DAYS days (consumed by CitizenController._on_hour_passed).
# - grant_resource: Immediate one-time resource dictionary grant (consumed by WorldEventSystem._apply_resource_effects).
# - heal_citizens: Immediate one-time health restoration for alive citizens (consumed by WorldEventSystem.apply_citizen_effects).
# - morale_penalty: Immediate one-time morale change for alive citizens (consumed by WorldEventSystem.apply_citizen_effects).
const EVENTS: Array[Dictionary] = [
	{
		"id": "bountiful_harvest",
		"title": "Mùa Màng Bội Thu",
		"description": "Thời tiết thuận hòa, đồng ruộng tươi tốt. Nông trại tăng 50% sản lượng trong 2 ngày tiếp theo.",
		"is_positive": true,
		"duration_days": DEFAULT_TIMED_EFFECT_DAYS,
		"effect": {"farm_modifier_bonus": 0.5, "bonus_food": 30}
	},
	{
		"id": "heatwave",
		"title": "Đợt Nắng Nóng Gay Gắt",
		"description": "Nhiệt độ oi bức khiến dân làng nhanh kiệt sức. Thể lực tiêu hao nhanh hơn và nguy cơ thiếu nước tăng cao.",
		"is_positive": false,
		"duration_days": DEFAULT_TIMED_EFFECT_DAYS,
		"effect": {"fatigue_multiplier": 1.25}
	},
	{
		"id": "wandering_herbalist",
		"title": "Dược Sư Du Phương",
		"description": "Một đoàn y sĩ ghé thăm quảng trường định cư, chia sẻ 20 Thảo Dược và chăm sóc sức khỏe cho dân làng.",
		"is_positive": true,
		"effect": {"grant_resource": {EconomyConfig.RES_HERBS: 20}, "heal_citizens": 15.0}
	},
	{
		"id": "bandit_scouts",
		"title": "Dấu Vết Đạo Tặc",
		"description": "Lính tuần tra phát hiện toán cướp rừng rình rập ngoài rìa lãnh thổ. Tinh thần cư dân tạm thời giảm nhẹ.",
		"is_positive": false,
		"effect": {"morale_penalty": -8.0}
	},
	{
		"id": "merchant_tribute",
		"title": "Đoàn Buôn Triều Cống",
		"description": "Thương đoàn phương xa mượn đường an toàn qua vương quốc, đóng góp 50 Vàng vào kho bạc.",
		"is_positive": true,
		"effect": {"grant_resource": {EconomyConfig.RES_GOLD: 50}}
	}
]

var last_event_day: int = -99
var min_days_between_events: int = 4
var rng: RandomNumberGenerator
var _initial_seed: int = 12345

# Timed modifier state (BUG-04B & BUG-04C)
var _active_farm_modifier_bonus: float = BASE_FARM_MODIFIER_BONUS
var _farm_bonus_expires_day: int = -1
var _active_fatigue_multiplier: float = BASE_FATIGUE_MULTIPLIER
var _fatigue_mult_expires_day: int = -1

func _init(seed_val: int = 12345) -> void:
	_initial_seed = seed_val + 9999
	rng = RandomNumberGenerator.new()
	rng.seed = _initial_seed

func reset_state() -> void:
	last_event_day = -99
	min_days_between_events = 4
	_active_farm_modifier_bonus = BASE_FARM_MODIFIER_BONUS
	_farm_bonus_expires_day = -1
	_active_fatigue_multiplier = BASE_FATIGUE_MULTIPLIER
	_fatigue_mult_expires_day = -1
	rng.seed = _initial_seed

func serialize() -> Dictionary:
	return {
		"last_event_day": last_event_day,
		"min_days_between_events": min_days_between_events,
		"active_farm_modifier_bonus": _active_farm_modifier_bonus,
		"farm_bonus_expires_day": _farm_bonus_expires_day,
		"active_fatigue_multiplier": _active_fatigue_multiplier,
		"fatigue_mult_expires_day": _fatigue_mult_expires_day,
		"rng_state": str(rng.state)
	}

func deserialize(data: Dictionary, current_day: int = -1) -> void:
	reset_state()
	if data == null or data.is_empty():
		return

	if data.has("last_event_day"):
		var raw_last: int = int(data.get("last_event_day", -99))
		if current_day >= 1 and raw_last > current_day:
			raw_last = current_day
		last_event_day = raw_last

	if data.has("min_days_between_events"):
		min_days_between_events = maxi(1, int(data.get("min_days_between_events", 4)))

	var restored_farm_bonus: float = maxf(0.0, float(data.get("active_farm_modifier_bonus", BASE_FARM_MODIFIER_BONUS)))
	var restored_farm_exp: int = int(data.get("farm_bonus_expires_day", -1))
	if restored_farm_exp >= 1 and restored_farm_bonus > 0.0:
		_active_farm_modifier_bonus = restored_farm_bonus
		_farm_bonus_expires_day = restored_farm_exp
	else:
		_active_farm_modifier_bonus = BASE_FARM_MODIFIER_BONUS
		_farm_bonus_expires_day = -1

	var restored_fatigue_mult: float = float(data.get("active_fatigue_multiplier", BASE_FATIGUE_MULTIPLIER))
	if is_nan(restored_fatigue_mult) or is_inf(restored_fatigue_mult) or restored_fatigue_mult <= 0.0:
		restored_fatigue_mult = BASE_FATIGUE_MULTIPLIER
	var restored_fatigue_exp: int = int(data.get("fatigue_mult_expires_day", -1))
	if restored_fatigue_exp >= 1 and not is_equal_approx(restored_fatigue_mult, BASE_FATIGUE_MULTIPLIER):
		_active_fatigue_multiplier = restored_fatigue_mult
		_fatigue_mult_expires_day = restored_fatigue_exp
	else:
		_active_fatigue_multiplier = BASE_FATIGUE_MULTIPLIER
		_fatigue_mult_expires_day = -1

	if data.has("rng_state"):
		var raw_rng = data.get("rng_state")
		if raw_rng is String and String(raw_rng).is_valid_int():
			rng.state = int(String(raw_rng))
		elif raw_rng is int:
			rng.state = raw_rng

	if current_day >= 1:
		update_daily_modifiers(current_day)

func update_daily_modifiers(current_day: int) -> void:
	if _farm_bonus_expires_day >= 0 and current_day >= _farm_bonus_expires_day:
		_active_farm_modifier_bonus = BASE_FARM_MODIFIER_BONUS
		_farm_bonus_expires_day = -1
	if _fatigue_mult_expires_day >= 0 and current_day >= _fatigue_mult_expires_day:
		_active_fatigue_multiplier = BASE_FATIGUE_MULTIPLIER
		_fatigue_mult_expires_day = -1

func get_active_farm_modifier_bonus(current_day: int = -1) -> float:
	if current_day >= 0:
		update_daily_modifiers(current_day)
	elif _farm_bonus_expires_day < 0:
		return BASE_FARM_MODIFIER_BONUS
	return _active_farm_modifier_bonus

func get_farm_production_multiplier(base_season_modifier: float = 1.0, current_day: int = -1) -> float:
	var bonus := get_active_farm_modifier_bonus(current_day)
	return maxf(0.0, base_season_modifier * (1.0 + bonus))

func get_active_fatigue_multiplier(current_day: int = -1) -> float:
	if current_day >= 0:
		update_daily_modifiers(current_day)
	elif _fatigue_mult_expires_day < 0:
		return BASE_FATIGUE_MULTIPLIER
	return _active_fatigue_multiplier

func is_farm_bonus_active(current_day: int = -1) -> bool:
	return get_active_farm_modifier_bonus(current_day) > 0.0

func is_heatwave_active(current_day: int = -1) -> bool:
	return get_active_fatigue_multiplier(current_day) > 1.0

func get_event_definition(event_id: String) -> Dictionary:
	for ev in EVENTS:
		if str(ev.get("id", "")) == event_id:
			return ev.duplicate(true)
	return {}

## Checks whether a scheduled world event should trigger on a given day.
func check_and_trigger_event(
	current_day: int,
	resource_mgr: Object,
	event_mgr: Object,
	citizen_list: Array = []
) -> Dictionary:
	update_daily_modifiers(current_day)
	if current_day - last_event_day < min_days_between_events:
		return {}

	# Trigger event
	var event_idx: int = rng.randi_range(0, EVENTS.size() - 1)
	var ev: Dictionary = EVENTS[event_idx].duplicate(true)
	last_event_day = current_day
	return _execute_event_instance(ev, current_day, resource_mgr, event_mgr, citizen_list)

## Deterministically triggers a specific event by ID for testing or scripted scenarios.
func trigger_event_by_id(
	event_id: String,
	current_day: int,
	resource_mgr: Object = null,
	event_mgr: Object = null,
	citizen_list: Array = []
) -> Dictionary:
	update_daily_modifiers(current_day)
	var ev := get_event_definition(event_id)
	if ev.is_empty():
		return {}
	last_event_day = current_day
	return _execute_event_instance(ev, current_day, resource_mgr, event_mgr, citizen_list)

func _execute_event_instance(
	ev: Dictionary,
	current_day: int,
	resource_mgr: Object,
	event_mgr: Object,
	citizen_list: Array = []
) -> Dictionary:
	_apply_timed_effects(ev, current_day)
	_apply_resource_effects(ev, resource_mgr)
	if citizen_list != null and not citizen_list.is_empty():
		apply_citizen_effects(ev, citizen_list)

	# Dispatch to EventManager
	if event_mgr != null and event_mgr.has_method("trigger_event"):
		event_mgr.call("trigger_event", ev["id"], ev["title"], ev["description"], ev["is_positive"], ev)

	return ev

func _apply_timed_effects(ev: Dictionary, current_day: int) -> void:
	if bool(ev.get("_timed_effects_applied", false)):
		return
	var effect: Dictionary = ev.get("effect", {})
	var duration_days: int = maxi(1, int(ev.get("duration_days", DEFAULT_TIMED_EFFECT_DAYS)))

	if effect.has("farm_modifier_bonus"):
		var bonus: float = float(effect["farm_modifier_bonus"])
		if not is_nan(bonus) and not is_inf(bonus):
			# Set (replace, never stack infinitely) timed farm bonus for duration_days
			_active_farm_modifier_bonus = maxf(0.0, bonus)
			_farm_bonus_expires_day = current_day + duration_days

	if effect.has("fatigue_multiplier"):
		var mult: float = float(effect["fatigue_multiplier"])
		if not is_nan(mult) and not is_inf(mult) and mult > 0.0:
			# Set (replace, never stack infinitely) timed fatigue multiplier for duration_days
			_active_fatigue_multiplier = mult
			_fatigue_mult_expires_day = current_day + duration_days

	ev["_timed_effects_applied"] = true

func _apply_resource_effects(ev: Dictionary, resource_mgr: Object) -> void:
	if bool(ev.get("_resource_effects_applied", false)):
		return
	if resource_mgr == null or not resource_mgr.has_method("add_resource"):
		return

	var effect: Dictionary = ev.get("effect", {})
	if effect.has("grant_resource") and effect["grant_resource"] is Dictionary:
		var grants: Dictionary = effect["grant_resource"]
		for res_id in grants:
			var amt: int = int(grants[res_id])
			if amt > 0:
				resource_mgr.call("add_resource", str(res_id), amt)

	if effect.has("bonus_food"):
		var food_amt: int = int(effect["bonus_food"])
		if food_amt > 0:
			resource_mgr.call("add_resource", EconomyConfig.RES_FOOD, food_amt)

	ev["_resource_effects_applied"] = true

static func _is_citizen_eligible(cit: Variant) -> bool:
	if cit == null or not is_instance_valid(cit):
		return false
	if cit is Node and (cit as Node).is_queued_for_deletion():
		return false
	if cit.has_method("is_alive"):
		if not bool(cit.call("is_alive")):
			return false
	var death_processed: Variant = cit.get("_death_processed")
	if death_processed != null and bool(death_processed):
		return false
	var cur_health_val: Variant = cit.get("health")
	if cur_health_val == null:
		return false
	var cur_health: float = float(cur_health_val)
	if is_nan(cur_health) or is_inf(cur_health) or cur_health <= 0.0:
		return false
	return true

func apply_citizen_effects(ev: Dictionary, citizen_list: Array) -> int:
	if ev.is_empty() or citizen_list == null:
		return 0
	if bool(ev.get("_citizen_effects_applied", false)):
		return 0

	var effect: Dictionary = ev.get("effect", ev)
	var has_morale: bool = effect.has("morale_penalty")
	var has_heal: bool = effect.has("heal_citizens")
	if not has_morale and not has_heal:
		ev["_citizen_effects_applied"] = true
		return 0

	var morale_delta: float = float(effect.get("morale_penalty", 0.0)) if has_morale else 0.0
	var heal_amount: float = float(effect.get("heal_citizens", 0.0)) if has_heal else 0.0

	var affected_count: int = 0
	var seen_citizens: Dictionary = {}

	for cit in citizen_list:
		if not _is_citizen_eligible(cit):
			continue
		var instance_id: int = cit.get_instance_id()
		if seen_citizens.has(instance_id):
			continue
		seen_citizens[instance_id] = true

		var modified: bool = false
		if has_morale and not is_nan(morale_delta) and not is_inf(morale_delta):
			var cur_morale_val: Variant = cit.get("morale")
			if cur_morale_val != null:
				var cur_morale: float = float(cur_morale_val)
				cit.set("morale", clampf(cur_morale + morale_delta, 0.0, 100.0))
				modified = true

		if has_heal and not is_nan(heal_amount) and not is_inf(heal_amount) and heal_amount > 0.0:
			var cur_health: float = float(cit.get("health"))
			if cur_health > 0.0:
				cit.set("health", clampf(cur_health + heal_amount, 0.0, 100.0))
				modified = true

		if modified:
			affected_count += 1

	ev["_citizen_effects_applied"] = true
	return affected_count
