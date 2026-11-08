class_name CrisisManager
extends RefCounted
## Endgame Crisis Scenarios & Settlement Resilience Manager for KINGDOMS UNBOUND (Package 4A / GDD §12.1, §12.2).
## Coordinates deterministic crisis lifecycles: Warning -> Active -> Consequences -> Resolution -> Recovery.
## Supports three authoritative scenarios:
## 1. Drought (Hạn hán) - Summer crop failure, water/food depletion pressure.
## 2. Blizzard (Bão tuyết) - Winter cold freezing, wood heating fuel requirement, hypothermia, building snow load.
## 3. Bandit Horde (Đạo tặc) - Outpost interception, garrison engagement, field army defense, settlement plunder/damage.

signal crisis_warning_issued(crisis_data: Dictionary)
signal crisis_started(crisis_data: Dictionary)
signal crisis_resolved(crisis_data: Dictionary)
signal crisis_recovered(crisis_data: Dictionary)
signal crisis_stage_changed(stage: String, crisis_type: String)
signal bandit_raid_resolved(raid_summary: Dictionary)

const CRISIS_NONE: String = "none"
const CRISIS_DROUGHT: String = "drought"
const CRISIS_BLIZZARD: String = "blizzard"
const CRISIS_BANDIT_HORDE: String = "bandit_horde"

const STAGE_INACTIVE: String = "inactive"
const STAGE_WARNING: String = "warning"
const STAGE_ACTIVE: String = "active"
const STAGE_RECOVERY: String = "recovery"

# Default Durations (simulation hours)
const DEFAULT_WARNING_HOURS: float = 24.0      # 1 game day warning
const DEFAULT_DROUGHT_HOURS: float = 72.0      # 3 game days
const DEFAULT_BLIZZARD_HOURS: float = 48.0     # 2 game days
const DEFAULT_BANDIT_HOURS: float = 24.0       # 1 game day raid window
const DEFAULT_RECOVERY_HOURS: float = 24.0     # 1 game day recovery
const DEFAULT_COOLDOWN_HOURS: float = 120.0    # 5 game days minimum between crises

# Modifiers & Baselines
const DROUGHT_FARM_MULTIPLIER: float = 0.40    # 60% crop failure
const BLIZZARD_FARM_MULTIPLIER: float = 0.0    # Frozen agriculture
const RECOVERY_FARM_MULTIPLIER: float = 1.10   # Post-crisis soil revitalization (+10%)
const BLIZZARD_FATIGUE_MULTIPLIER: float = 1.50 # +50% outdoor fatigue rate
const BASE_WOOD_HEATING_DEMAND_PER_HOUR: int = 2

# State variables
var current_crisis_type: String = CRISIS_NONE
var current_stage: String = STAGE_INACTIVE

var warning_hours_remaining: float = 0.0
var active_hours_remaining: float = 0.0
var recovery_hours_remaining: float = 0.0
var cooldown_hours_remaining: float = 0.0

var crisis_seed: int = 12345
var rng: RandomNumberGenerator
var total_crises_faced: int = 0
var total_crises_survived: int = 0

var active_crisis_data: Dictionary = {}
var cold_hypothermia_active: bool = false
var last_raid_result: Dictionary = {}

func _init(seed_val: int = 12345) -> void:
	crisis_seed = seed_val + 4040
	rng = RandomNumberGenerator.new()
	rng.seed = crisis_seed

func is_crisis_active() -> bool:
	return current_stage == STAGE_ACTIVE

func is_in_warning() -> bool:
	return current_stage == STAGE_WARNING

func is_in_recovery() -> bool:
	return current_stage == STAGE_RECOVERY

func is_hypothermia_active() -> bool:
	return cold_hypothermia_active

func get_crisis_display_name(c_type: String = "") -> String:
	var target_type := c_type if not c_type.is_empty() else current_crisis_type
	match target_type:
		CRISIS_DROUGHT:
			return "Hạn Hán Khắc Nghiệt"
		CRISIS_BLIZZARD:
			return "Bão Tuyết Băng Giá"
		CRISIS_BANDIT_HORDE:
			return "Đại Họa Đạo Tặc"
		_:
			return "Bình Yên"

func get_farm_production_multiplier() -> float:
	if current_stage == STAGE_ACTIVE:
		if current_crisis_type == CRISIS_DROUGHT:
			return DROUGHT_FARM_MULTIPLIER
		elif current_crisis_type == CRISIS_BLIZZARD:
			return BLIZZARD_FARM_MULTIPLIER
	elif current_stage == STAGE_RECOVERY and current_crisis_type == CRISIS_DROUGHT:
		return RECOVERY_FARM_MULTIPLIER
	return 1.0

func get_citizen_fatigue_multiplier() -> float:
	if current_stage == STAGE_ACTIVE and current_crisis_type == CRISIS_BLIZZARD:
		return BLIZZARD_FATIGUE_MULTIPLIER
	return 1.0

func get_warning_data_for(crisis_type: String) -> Dictionary:
	match crisis_type:
		CRISIS_DROUGHT:
			return {
				"crisis_type": CRISIS_DROUGHT,
				"title": "CẢNH BÁO THIÊN TAI: ĐỢT HẠN HÁN SẮP ĐẾN",
				"cause": "Thời tiết mùa hè nắng gắt cực độ kéo dài làm sông hồ cạn đáy.",
				"severity": "critical",
				"hours_remaining": warning_hours_remaining,
				"projected_consequences": "Sản lượng nông trại sẽ giảm 60% trong 72 giờ. Cư dân tiêu hao lương thực nhanh hơn.",
				"recommended_action": "Tích trữ tối thiểu 100 lương thực hoặc chuẩn bị mua lương thực từ các đoàn buôn.",
				"message": "Nắng nóng gay gắt sắp đổ bộ. Nông trại sẽ giảm 60% năng suất trong 3 ngày tới."
			}
		CRISIS_BLIZZARD:
			return {
				"crisis_type": CRISIS_BLIZZARD,
				"title": "CẢNH BÁO THIÊN TAI: BÃO TUYẾT BĂNG GIÁ",
				"cause": "Đợt không khí lạnh cực độ từ phương bắc tràn về giữa mùa đông.",
				"severity": "critical",
				"hours_remaining": warning_hours_remaining,
				"projected_consequences": "Nông trại bị đóng băng hoàn toàn (0% sản lượng). Cần 2 Gỗ/giờ để sưởi ấm. Nếu hết Gỗ, cư dân sẽ bị hạ thân nhiệt và tử vong.",
				"recommended_action": "Tích trữ khẩn cấp Gỗ và Lương thực, phân công thợ mộc sẵn sàng gia cố mái nhà.",
				"message": "Bão tuyết sắp ập đến. Cần tích trữ Gỗ để sưởi ấm và Lương thực cho cư dân sống sót qua mùa đông."
			}
		CRISIS_BANDIT_HORDE:
			return {
				"crisis_type": CRISIS_BANDIT_HORDE,
				"title": "CẢNH BÁO QUÂN SỰ: ĐẠI HỌA ĐẠO TẶC ÁP SÁT",
				"cause": "Sự thịnh vượng của vương quốc đã thu hút toán thổ phỉ vũ trang quy mô lớn từ rừng sâu.",
				"severity": "emergency",
				"hours_remaining": warning_hours_remaining,
				"projected_consequences": "Nếu không được tiền đồn chặn đứng, thổ phỉ sẽ cướp bóc 20% Ngân khố và Lương thực, đồng thời phá hủy các công trình định cư.",
				"recommended_action": "Điều động binh lính đồn trú tại các Tiền Đồn biên giới hoặc duy trì đạo quân sẵn sàng nghênh chiến.",
				"message": "Toán cướp vũ trang đang tiến về vương quốc. Cần bố trí quân đồn trú tại các tiền đồn để đánh chặn."
			}
		_:
			return {
				"crisis_type": CRISIS_NONE,
				"title": "TÌNH HÌNH ỔN ĐỊNH",
				"cause": "Không có hiểm họa trực tiếp nào đe dọa vương quốc.",
				"severity": "low",
				"hours_remaining": 0.0,
				"projected_consequences": "Các hoạt động sản xuất và sinh hoạt diễn ra bình thường.",
				"recommended_action": "Tiếp tục phát triển vương quốc.",
				"message": "Vương quốc đang trong thời kỳ bình yên."
			}

func get_active_crisis_data() -> Dictionary:
	return active_crisis_data

## Manually or script-triggers a crisis.
func trigger_crisis(crisis_type: String, skip_warning: bool = false, custom_duration: float = -1.0, force: bool = false) -> Dictionary:
	if current_stage != STAGE_INACTIVE:
		return {
			"success": false,
			"reason": "Một cuộc khủng hoảng đang diễn ra hoặc đang trong giai đoạn phục hồi/cảnh báo."
		}

	if cooldown_hours_remaining > 0.0 and not force:
		return {
			"success": false,
			"reason": "Vương quốc đang trong thời gian hồi phục (cooldown: %.1f giờ)." % cooldown_hours_remaining
		}

	if not [CRISIS_DROUGHT, CRISIS_BLIZZARD, CRISIS_BANDIT_HORDE].has(crisis_type):
		return {
			"success": false,
			"reason": "Loại khủng hoảng không hợp lệ: %s" % crisis_type
		}

	current_crisis_type = crisis_type
	total_crises_faced += 1
	var duration: float = custom_duration
	if duration <= 0.0:
		match crisis_type:
			CRISIS_DROUGHT:
				duration = DEFAULT_DROUGHT_HOURS
			CRISIS_BLIZZARD:
				duration = DEFAULT_BLIZZARD_HOURS
			CRISIS_BANDIT_HORDE:
				duration = DEFAULT_BANDIT_HOURS

	if skip_warning:
		current_stage = STAGE_ACTIVE
		active_hours_remaining = duration
		warning_hours_remaining = 0.0
		active_crisis_data = get_warning_data_for(crisis_type)
		active_crisis_data["duration_hours"] = duration
		active_crisis_data["stage"] = STAGE_ACTIVE
		crisis_stage_changed.emit(STAGE_ACTIVE, current_crisis_type)
		crisis_started.emit(active_crisis_data)
		return {"success": true, "stage": STAGE_ACTIVE, "crisis_type": crisis_type, "duration": duration}
	else:
		current_stage = STAGE_WARNING
		warning_hours_remaining = DEFAULT_WARNING_HOURS
		active_hours_remaining = duration
		active_crisis_data = get_warning_data_for(crisis_type)
		active_crisis_data["duration_hours"] = duration
		active_crisis_data["stage"] = STAGE_WARNING
		crisis_stage_changed.emit(STAGE_WARNING, current_crisis_type)
		crisis_warning_issued.emit(active_crisis_data)
		return {"success": true, "stage": STAGE_WARNING, "crisis_type": crisis_type, "warning_hours": warning_hours_remaining}

## Evaluates scheduled crisis potential once per game day.
func process_day(day: int, _season_name: String, season_index: int, _world_data: Variant, _rm: Variant, citizen_count: int, treasury: int) -> Dictionary:
	if current_stage != STAGE_INACTIVE:
		return {"action": "ongoing_crisis", "type": current_crisis_type, "stage": current_stage}

	if cooldown_hours_remaining > 0.0:
		return {"action": "in_cooldown", "cooldown_remaining": cooldown_hours_remaining}

	# Deterministic seasonal crisis candidate selection
	# Season indices: 0 = Spring, 1 = Summer, 2 = Autumn, 3 = Winter
	var candidate_type: String = CRISIS_NONE

	# Winter Blizzard check: days 31-40 or season_index == 3
	if season_index == 3:
		if day % 10 >= 3 and day % 10 <= 7:
			candidate_type = CRISIS_BLIZZARD
	# Summer Drought check: season_index == 1
	elif season_index == 1:
		if day % 10 >= 3 and day % 10 <= 7:
			candidate_type = CRISIS_DROUGHT
	# Mid/Late game Bandit Horde: day >= 10 and prosperity
	elif day >= 10 and (citizen_count >= 15 or treasury >= 350):
		var roll := rng.randf()
		if roll < 0.30:
			candidate_type = CRISIS_BANDIT_HORDE

	if candidate_type != CRISIS_NONE:
		return trigger_crisis(candidate_type, false)

	return {"action": "none"}

## Advances crisis simulation clock by 1 hour.
func tick_hourly(
	hour: int,
	day: int,
	_season: String,
	world_data: Variant = null,
	rm: Variant = null,
	citizen_list: Array = [],
	player_army_mgr: Variant = null,
	field_siege_mgr: Variant = null,
	_hud: Variant = null
) -> Dictionary:
	# 1. If inactive, advance cooldown clock
	if current_stage == STAGE_INACTIVE:
		if cooldown_hours_remaining > 0.0:
			cooldown_hours_remaining = maxf(0.0, cooldown_hours_remaining - 1.0)
		return {"stage": STAGE_INACTIVE, "type": CRISIS_NONE, "cooldown_left": cooldown_hours_remaining}

	# 2. Stage: Warning countdown
	if current_stage == STAGE_WARNING:
		warning_hours_remaining = maxf(0.0, warning_hours_remaining - 1.0)
		if warning_hours_remaining <= 0.0:
			# Transition to ACTIVE!
			current_stage = STAGE_ACTIVE
			active_crisis_data["stage"] = STAGE_ACTIVE
			crisis_stage_changed.emit(STAGE_ACTIVE, current_crisis_type)
			crisis_started.emit(active_crisis_data)

			# If Bandit Horde: raid resolution happens upon reaching active raid phase
			if current_crisis_type == CRISIS_BANDIT_HORDE:
				var raid_res := resolve_bandit_raid(world_data, rm, citizen_list, player_army_mgr, field_siege_mgr)
				last_raid_result = raid_res
				bandit_raid_resolved.emit(raid_res)

		return {
			"stage": current_stage,
			"type": current_crisis_type,
			"warning_hours_left": warning_hours_remaining
		}

	# 3. Stage: Active crisis
	if current_stage == STAGE_ACTIVE:
		active_hours_remaining = maxf(0.0, active_hours_remaining - 1.0)

		# Execute scenario-specific hourly consequences
		match current_crisis_type:
			CRISIS_BLIZZARD:
				_process_blizzard_hour(rm, citizen_list, world_data, hour)
			CRISIS_DROUGHT:
				_process_drought_hour(citizen_list)
			CRISIS_BANDIT_HORDE:
				# Resolve raid once on active entry if not yet resolved
				if last_raid_result.is_empty():
					var raid_res := resolve_bandit_raid(world_data, rm, citizen_list, player_army_mgr, field_siege_mgr)
					last_raid_result = raid_res
					bandit_raid_resolved.emit(raid_res)

		if active_hours_remaining <= 0.0:
			# Transition to RECOVERY!
			current_stage = STAGE_RECOVERY
			recovery_hours_remaining = DEFAULT_RECOVERY_HOURS
			cold_hypothermia_active = false
			total_crises_survived += 1
			active_crisis_data["stage"] = STAGE_RECOVERY
			crisis_stage_changed.emit(STAGE_RECOVERY, current_crisis_type)
			crisis_resolved.emit(active_crisis_data)

		return {
			"stage": current_stage,
			"type": current_crisis_type,
			"active_hours_left": active_hours_remaining,
			"hypothermia": cold_hypothermia_active
		}

	# 4. Stage: Recovery countdown
	if current_stage == STAGE_RECOVERY:
		recovery_hours_remaining = maxf(0.0, recovery_hours_remaining - 1.0)
		if recovery_hours_remaining <= 0.0:
			# Fully recovered!
			var resolved_type := current_crisis_type
			current_stage = STAGE_INACTIVE
			current_crisis_type = CRISIS_NONE
			cooldown_hours_remaining = DEFAULT_COOLDOWN_HOURS
			active_crisis_data = {}
			last_raid_result = {}
			crisis_stage_changed.emit(STAGE_INACTIVE, CRISIS_NONE)
			crisis_recovered.emit({"crisis_type": resolved_type})

		return {
			"stage": current_stage,
			"type": current_crisis_type,
			"recovery_hours_left": recovery_hours_remaining
		}

	return {"stage": current_stage, "type": current_crisis_type}

func _process_blizzard_hour(rm: Variant, citizen_list: Array, world_data: Variant, hour: int) -> void:
	# 1. Wood consumption for heating
	var wood_needed: int = BASE_WOOD_HEATING_DEMAND_PER_HOUR
	var wood_stock: int = 0
	if rm != null and rm.has_method("get_available_stock"):
		wood_stock = int(rm.call("get_available_stock", "wood"))

	if wood_stock >= wood_needed and rm != null and rm.has_method("consume_resource"):
		rm.call("consume_resource", "wood", wood_needed)
		cold_hypothermia_active = false
	else:
		# Wood exhausted: hypothermia sets in
		cold_hypothermia_active = true
		for cit in citizen_list:
			if cit != null and is_instance_valid(cit) and cit.has_method("is_alive") and cit.call("is_alive"):
				var cur_h: float = float(cit.get("health")) if cit.get("health") != null else 100.0
				cur_h = maxf(0.0, cur_h - 1.0)
				cit.set("health", cur_h)
				if cur_h <= 0.0 and cit.has_method("die"):
					cit.call("die", "Đã qua đời vì hạ thân nhiệt trong bão tuyết", "hypothermia_or_cold")

	# 2. Snow load structural wear (every 12 hours)
	if hour % 12 == 0 and world_data != null and world_data.get("buildings") != null:
		var buildings: Array = world_data.get("buildings")
		if not buildings.is_empty():
			var BuildingSystemScript = load("res://scripts/economy/building_system.gd")
			if BuildingSystemScript != null and BuildingSystemScript.has_method("apply_damage"):
				var idx: int = rng.randi_range(0, buildings.size() - 1)
				var b = buildings[idx]
				if b is Dictionary and b.get("state") != "destroyed":
					BuildingSystemScript.call("apply_damage", b, 2, world_data)

func _process_drought_hour(citizen_list: Array) -> void:
	# Slight water/thirst stress: additional fatigue on working citizens
	for cit in citizen_list:
		if cit != null and is_instance_valid(cit) and cit.has_method("is_alive") and cit.call("is_alive"):
			var st = cit.get("current_state")
			# If working, fatigue slightly accumulates faster
			if st != null and int(st) == 1: # State.WORKING
				var fat: float = float(cit.get("fatigue")) if cit.get("fatigue") != null else 10.0
				cit.set("fatigue", minf(100.0, fat + 0.5))

## Evaluates and resolves the Bandit Horde attack using existing military & outpost systems.
func resolve_bandit_raid(
	world_data: Variant,
	rm: Variant,
	citizen_list: Array,
	player_army_mgr: Variant,
	field_siege_mgr: Variant
) -> Dictionary:
	var base_threat: int = rng.randi_range(8, 14)
	var threat_remaining: int = base_threat

	var garrison_intercepted: int = 0
	var garrison_casualties: int = 0
	var field_intercepted: int = 0
	var field_casualties: int = 0

	# 1. Phase 1: Outpost Garrison Interception (Package 3A Integration)
	if player_army_mgr != null and player_army_mgr.get("garrisons") != null:
		var garrisons_dict: Dictionary = player_army_mgr.get("garrisons")
		for o_id in garrisons_dict.keys():
			if threat_remaining <= 0:
				break
			var s_list: Array = garrisons_dict[o_id].get("soldiers", [])
			var gar_count: int = s_list.size()
			if gar_count > 0:
				# Each garrison soldier eliminates up to 2 bandits
				var max_kills: int = gar_count * 2
				var kills: int = mini(threat_remaining, max_kills)
				threat_remaining -= kills
				garrison_intercepted += kills

				# Garrison risk: 1 casualty per 3 bandits eliminated
				var cas: int = kills / 3
				if cas > 0 and player_army_mgr.has_method("apply_outpost_casualties"):
					var removed: int = int(player_army_mgr.call("apply_outpost_casualties", o_id, cas))
					garrison_casualties += removed

	# 2. Phase 2: Settlement Field Defense (Player Army)
	if threat_remaining > 0 and player_army_mgr != null:
		var army_count: int = int(player_army_mgr.get("soldier_count")) if player_army_mgr.get("soldier_count") != null else 0
		if army_count > 0:
			var max_field_kills: int = army_count * 2
			var kills: int = mini(threat_remaining, max_field_kills)
			threat_remaining -= kills
			field_intercepted += kills

			var army_cas: int = kills / 3
			if army_cas > 0 and player_army_mgr.has_method("remove_casualties"):
				var removed: int = int(player_army_mgr.call("remove_casualties", army_cas, false))
				field_casualties += removed

	# 3. Phase 3: Breach Consequences (if bandits penetrated defenses)
	var plundered_food: int = 0
	var plundered_gold: int = 0
	var damaged_buildings: Array[String] = []
	var morale_penalty: float = 0.0

	if threat_remaining > 0:
		# Bandits plunder Food and Gold (20% of stock, bounded)
		if rm != null and rm.has_method("get_available_stock") and rm.has_method("consume_resource"):
			var cur_food: int = int(rm.call("get_available_stock", "food"))
			var cur_gold: int = int(rm.call("get_available_stock", "gold"))
			plundered_food = mini(int(cur_food * 0.20), 100)
			plundered_gold = mini(int(cur_gold * 0.20), 150)
			if plundered_food > 0:
				rm.call("consume_resource", "food", plundered_food)
			if plundered_gold > 0:
				rm.call("consume_resource", "gold", plundered_gold)

		# Bandits damage 1-2 buildings (Package 2M BuildingSystem durability)
		if world_data != null and world_data.get("buildings") != null:
			var b_list: Array = world_data.get("buildings")
			var BuildingSystemScript = load("res://scripts/economy/building_system.gd")
			if BuildingSystemScript != null and BuildingSystemScript.has_method("apply_damage"):
				var candidates: Array = []
				for b in b_list:
					if b is Dictionary and b.get("type") != "town_hall" and b.get("state") != "destroyed":
						candidates.append(b)
				if candidates.is_empty() and not b_list.is_empty():
					candidates = b_list

				var count_to_damage := mini(2, candidates.size())
				for i in range(count_to_damage):
					var target_b = candidates[i]
					BuildingSystemScript.call("apply_damage", target_b, 25, world_data)
					damaged_buildings.append(str(target_b.get("id", "")))

		# Citizen morale penalty
		morale_penalty = -10.0
		for cit in citizen_list:
			if cit != null and is_instance_valid(cit) and cit.has_method("is_alive") and cit.call("is_alive"):
				var cur_m: float = float(cit.get("morale")) if cit.get("morale") != null else 70.0
				cit.set("morale", clampf(cur_m + morale_penalty, 0.0, 100.0))

	var intercepted_completely: bool = (threat_remaining <= 0)

	var summary: Dictionary = {
		"threat_strength": base_threat,
		"garrison_intercepted": garrison_intercepted,
		"garrison_casualties": garrison_casualties,
		"field_intercepted": field_intercepted,
		"field_casualties": field_casualties,
		"breached_bandits": threat_remaining,
		"plundered_food": plundered_food,
		"plundered_gold": plundered_gold,
		"damaged_buildings": damaged_buildings,
		"morale_penalty": morale_penalty,
		"intercepted_completely": intercepted_completely
	}
	return summary

## Serialization for Save/Load persistence.
func serialize() -> Dictionary:
	return {
		"version": 1,
		"current_crisis_type": current_crisis_type,
		"current_stage": current_stage,
		"warning_hours_remaining": warning_hours_remaining,
		"active_hours_remaining": active_hours_remaining,
		"recovery_hours_remaining": recovery_hours_remaining,
		"cooldown_hours_remaining": cooldown_hours_remaining,
		"crisis_seed": crisis_seed,
		"rng_state": str(rng.state),
		"total_crises_faced": total_crises_faced,
		"total_crises_survived": total_crises_survived,
		"active_crisis_data": active_crisis_data.duplicate(true),
		"cold_hypothermia_active": cold_hypothermia_active,
		"last_raid_result": last_raid_result.duplicate(true)
	}

## Deserialization with safe fallback for legacy saves.
func deserialize(data: Dictionary) -> void:
	if data == null or data.is_empty():
		current_crisis_type = CRISIS_NONE
		current_stage = STAGE_INACTIVE
		warning_hours_remaining = 0.0
		active_hours_remaining = 0.0
		recovery_hours_remaining = 0.0
		cooldown_hours_remaining = 0.0
		active_crisis_data = {}
		cold_hypothermia_active = false
		last_raid_result = {}
		return

	current_crisis_type = str(data.get("current_crisis_type", CRISIS_NONE))
	current_stage = str(data.get("current_stage", STAGE_INACTIVE))
	warning_hours_remaining = float(data.get("warning_hours_remaining", 0.0))
	active_hours_remaining = float(data.get("active_hours_remaining", 0.0))
	recovery_hours_remaining = float(data.get("recovery_hours_remaining", 0.0))
	cooldown_hours_remaining = float(data.get("cooldown_hours_remaining", 0.0))
	crisis_seed = int(data.get("crisis_seed", crisis_seed))
	total_crises_faced = int(data.get("total_crises_faced", 0))
	total_crises_survived = int(data.get("total_crises_survived", 0))
	active_crisis_data = data.get("active_crisis_data", {}).duplicate(true)
	cold_hypothermia_active = bool(data.get("cold_hypothermia_active", false))
	last_raid_result = data.get("last_raid_result", {}).duplicate(true)

	if data.has("rng_state") and not str(data.get("rng_state")).is_empty():
		rng.state = int(str(data.get("rng_state")))
	else:
		rng.seed = crisis_seed
