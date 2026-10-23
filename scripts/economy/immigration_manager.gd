class_name ImmigrationManager
extends RefCounted
## Deterministic Immigration & Population Growth Manager for KINGDOMS UNBOUND.
## Paces migrant arrivals based on housing capacity, food reserves, stability, and morale.

signal immigration_evaluated(allowed: bool, reason: String, count: int)
signal immigrants_arrived(immigrants_data: Array[Dictionary])

const VIETNAMESE_FIRST_NAMES: Array[String] = [
	"Nguyễn", "Trần", "Lê", "Phạm", "Hoàng", "Huỳnh", "Phan", "Vũ", "Võ", "Đặng",
	"Bùi", "Đỗ", "Hồ", "Ngô", "Dương", "Lý", "Đào", "Đinh", "Đoàn", "Lâm"
]

const VIETNAMESE_MIDDLE_NAMES: Array[String] = [
	"Văn", "Thị", "Hữu", "Đức", "Quốc", "Gia", "Thành", "Quang", "Minh", "Hải",
	"Ngọc", "Tuấn", "Hoài", "Bảo", "Đình", "Thế", "Trọng", "Nhật", "Huy", "Hồng"
]

const VIETNAMESE_LAST_NAMES: Array[String] = [
	"An", "Bình", "Cường", "Dũng", "Em", "Phúc", "Giáp", "Hùng", "Khang", "Long",
	"Nam", "Oanh", "Phát", "Quân", "Sơn", "Thắng", "Uy", "Vũ", "Xuân", "Yên",
	"Bảo", "Chiến", "Đạt", "Hậu", "Khánh", "Linh", "Nghĩa", "Phong", "Tài", "Tâm"
]

var immigration_interval_days: int = 3
var check_hour: int = 6
var min_food_threshold: int = 30
var min_stability_threshold: float = 50.0
var min_morale_threshold: float = 60.0
var max_wave_size: int = 4

var last_immigration_day: int = 0
var total_immigrants_admitted: int = 0
var next_citizen_index: int = 25 # Starter citizens are 1..24

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _init(seed_val: int = 12345) -> void:
	_rng.seed = seed_val

func can_evaluate_today(day: int, hour: int) -> bool:
	if day <= last_immigration_day:
		return false
	if day % immigration_interval_days != 0:
		return false
	if hour != check_hour:
		return false
	return true

func evaluate_immigration(housing_cap: int, current_pop: int, food: int, stability: float, morale: float, current_day: int = 0) -> Dictionary:
	var vacancies: int = housing_cap - current_pop
	
	# 1. Housing capacity check
	if vacancies <= 0:
		var reason: String = "Thiếu chỗ ở: Dân số (%d) đã đạt sức chứa tối đa (%d chỗ ở). Cần xây thêm Nhà Ở." % [current_pop, housing_cap]
		immigration_evaluated.emit(false, reason, 0)
		return {"allowed": false, "count": 0, "reason": reason, "immigrants": []}
		
	# 2. Food reserve check
	if food < min_food_threshold:
		var reason: String = "Thiếu lương thực dự trữ: Cần ít nhất %d đơn vị lương thực (hiện có %d)." % [min_food_threshold, food]
		immigration_evaluated.emit(false, reason, 0)
		return {"allowed": false, "count": 0, "reason": reason, "immigrants": []}
		
	# 3. Stability check
	if stability < min_stability_threshold:
		var reason: String = "Mức độ ổn định quá thấp: Cần tối thiểu %.0f%% (hiện tại %.1f%%)." % [min_stability_threshold, stability]
		immigration_evaluated.emit(false, reason, 0)
		return {"allowed": false, "count": 0, "reason": reason, "immigrants": []}
		
	# 4. Morale check
	if morale < min_morale_threshold:
		var reason: String = "Sĩ khí trung bình quá thấp: Cần tối thiểu %.0f%% (hiện tại %.1f%%)." % [min_morale_threshold, morale]
		immigration_evaluated.emit(false, reason, 0)
		return {"allowed": false, "count": 0, "reason": reason, "immigrants": []}

	# Deterministic wave size: bounded by vacancies and max_wave_size
	var wave_size: int = mini(vacancies, max_wave_size)
	# High prosperity bonus: if food >= 100 and stability >= 80, admit full wave
	if wave_size < 2 and vacancies >= 2:
		wave_size = 2
	
	var immigrants: Array[Dictionary] = []
	for i in range(wave_size):
		var imm_data: Dictionary = _generate_immigrant_data()
		immigrants.append(imm_data)
		
	var success_reason: String = "Đoàn người di cư (%d người) đã gia nhập vương quốc nhờ cuộc sống ấm no và ổn định." % wave_size
	immigration_evaluated.emit(true, success_reason, wave_size)
	
	if current_day > 0:
		last_immigration_day = current_day
	total_immigrants_admitted += wave_size
	
	immigrants_arrived.emit(immigrants)
	return {
		"allowed": true,
		"count": wave_size,
		"reason": success_reason,
		"immigrants": immigrants
	}

func _generate_immigrant_data() -> Dictionary:
	var cid: String = "citizen_%d" % next_citizen_index
	next_citizen_index += 1
	
	var fn: String = VIETNAMESE_FIRST_NAMES[_rng.randi() % VIETNAMESE_FIRST_NAMES.size()]
	var mn: String = VIETNAMESE_MIDDLE_NAMES[_rng.randi() % VIETNAMESE_MIDDLE_NAMES.size()]
	var ln: String = VIETNAMESE_LAST_NAMES[_rng.randi() % VIETNAMESE_LAST_NAMES.size()]
	var full_name: String = "%s %s %s" % [fn, mn, ln]
	
	# Initial assigned role: default to idle so player or JobManager can allocate
	return {
		"id": cid,
		"name": full_name,
		"role": "idle",
		"hunger": 15.0,
		"fatigue": 10.0,
		"health": 100.0,
		"morale": 75.0
	}

func serialize() -> Dictionary:
	return {
		"last_immigration_day": last_immigration_day,
		"total_immigrants_admitted": total_immigrants_admitted,
		"next_citizen_index": next_citizen_index
	}

func deserialize(data: Dictionary, existing_citizens: Array = []) -> void:
	last_immigration_day = maxi(0, int(data.get("last_immigration_day", 0)))
	total_immigrants_admitted = maxi(0, int(data.get("total_immigrants_admitted", 0)))
	var next_idx: int = maxi(25, int(data.get("next_citizen_index", 25)))
	# DEBT-03 fix: Guarantee next_citizen_index never collides with any existing citizen_<N> ID
	for c in existing_citizens:
		if c is Dictionary and c.has("id"):
			var cid_str: String = String(c["id"])
			if cid_str.begins_with("citizen_"):
				var num_part: String = cid_str.substr(8)
				if num_part.is_valid_int():
					var parsed_idx: int = int(num_part)
					if parsed_idx >= next_idx:
						next_idx = parsed_idx + 1
	next_citizen_index = next_idx
