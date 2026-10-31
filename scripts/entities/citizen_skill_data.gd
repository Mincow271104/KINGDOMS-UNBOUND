class_name CitizenSkillData
extends RefCounted
## Vocational Skill Progression Model for KINGDOMS UNBOUND (Package 2B).
## Tracks individual citizen experience and bounded efficiency multipliers per GDD §6.5.

const VOCATIONS: Array[String] = [
	"farming",
	"woodcutting",
	"mining",
	"smithing",
	"building",
	"hauling"
]

const LEVEL_THRESHOLDS: Array[int] = [0, 100, 300, 600, 1000]
const LEVEL_MULTIPLIERS: Array[float] = [1.00, 1.08, 1.16, 1.25, 1.35]
const MAX_XP: float = 1000.0
const MIN_XP: float = 0.0
const MAX_EFFICIENCY: float = 1.35

const VOCATION_NAMES: Dictionary = {
	"farming": "Nông nghiệp",
	"woodcutting": "Lâm nghiệp",
	"mining": "Khai khoáng",
	"smithing": "Rèn & Chế tác",
	"building": "Xây dựng",
	"hauling": "Vận chuyển"
}

const LEVEL_TITLES: Array[String] = [
	"Tập sự",        # Level 1: Novice
	"Học việc",       # Level 2: Apprentice
	"Thợ lành nghề",  # Level 3: Journeyman
	"Chuyên gia",     # Level 4: Expert
	"Bậc thầy"        # Level 5: Master
]

const JOB_TO_VOCATION: Dictionary = {
	"farmer": "farming",
	"farming": "farming",
	"woodcutter": "woodcutting",
	"woodcutting": "woodcutting",
	"miner": "mining",
	"quarryman": "mining",
	"mining": "mining",
	"smith": "smithing",
	"smithing": "smithing",
	"builder": "building",
	"building": "building",
	"hauler": "hauling",
	"hauling": "hauling"
}

# Cumulative XP storage per vocation (Float for fractional construction work time)
var _xp: Dictionary = {}

func _init() -> void:
	init_skills()

func init_skills() -> void:
	_xp.clear()
	for voc in VOCATIONS:
		_xp[voc] = 0.0

static func get_vocation_for_job(job_or_role: String) -> String:
	return JOB_TO_VOCATION.get(job_or_role.to_lower().strip_edges(), "")

static func is_valid_vocation(vocation: String) -> bool:
	return VOCATIONS.has(vocation)

func add_xp(vocation_or_job: String, amount: float) -> bool:
	var voc: String = get_vocation_for_job(vocation_or_job)
	if voc == "":
		return false
	if amount <= 0.0 or is_nan(amount) or is_inf(amount):
		return false
	var current: float = float(_xp.get(voc, 0.0))
	var new_val: float = clampf(current + amount, MIN_XP, MAX_XP)
	_xp[voc] = new_val
	return true

func set_xp(vocation_or_job: String, xp_val: float) -> void:
	var voc: String = get_vocation_for_job(vocation_or_job)
	if voc == "":
		return
	if is_nan(xp_val) or is_inf(xp_val):
		_xp[voc] = 0.0
		return
	_xp[voc] = clampf(xp_val, MIN_XP, MAX_XP)

func get_xp(vocation_or_job: String) -> float:
	var voc: String = get_vocation_for_job(vocation_or_job)
	if voc == "":
		return 0.0
	return float(_xp.get(voc, 0.0))

func get_level(vocation_or_job: String) -> int:
	var voc: String = get_vocation_for_job(vocation_or_job)
	if voc == "":
		return 1
	var xp_val: float = float(_xp.get(voc, 0.0))
	return get_level_for_xp(xp_val)

static func get_level_for_xp(xp_val: float) -> int:
	var clamped_xp: float = clampf(xp_val, MIN_XP, MAX_XP)
	if clamped_xp >= 1000.0:
		return 5
	elif clamped_xp >= 600.0:
		return 4
	elif clamped_xp >= 300.0:
		return 3
	elif clamped_xp >= 100.0:
		return 2
	return 1

func get_efficiency(vocation_or_job: String) -> float:
	var voc: String = get_vocation_for_job(vocation_or_job)
	if voc == "":
		return 1.00
	var lvl: int = get_level(voc)
	return get_efficiency_for_level(lvl)

static func get_efficiency_for_level(lvl: int) -> float:
	var idx: int = clampi(lvl - 1, 0, LEVEL_MULTIPLIERS.size() - 1)
	return LEVEL_MULTIPLIERS[idx]

func get_efficiency_bonus_percent(vocation_or_job: String) -> int:
	var mult: float = get_efficiency(vocation_or_job)
	return int(round((mult - 1.0) * 100.0))

func get_next_level_xp(vocation_or_job: String) -> int:
	var lvl: int = get_level(vocation_or_job)
	if lvl >= 5:
		return 1000
	return LEVEL_THRESHOLDS[lvl]

func get_current_level_base_xp(vocation_or_job: String) -> int:
	var lvl: int = get_level(vocation_or_job)
	return LEVEL_THRESHOLDS[clampi(lvl - 1, 0, LEVEL_THRESHOLDS.size() - 1)]

static func get_vocation_display_name(vocation_or_job: String) -> String:
	var voc: String = get_vocation_for_job(vocation_or_job)
	return VOCATION_NAMES.get(voc, "Chưa xác định")

static func get_level_title(lvl: int) -> String:
	var idx: int = clampi(lvl - 1, 0, LEVEL_TITLES.size() - 1)
	return LEVEL_TITLES[idx]

## Serializes cumulative XP dictionary for SaveManager.
## Format: { "farming": 340.0, "woodcutting": 100.0, ... }
func serialize() -> Dictionary:
	var out: Dictionary = {}
	for voc in VOCATIONS:
		out[voc] = float(_xp.get(voc, 0.0))
	return out

## Deserializes cumulative XP dictionary safely with fail-closed bounds checking.
## Tolerates missing keys (defaults to 0.0) and scalar or nested dict formats.
func deserialize(data: Variant) -> void:
	init_skills()
	if not (data is Dictionary):
		return
	var dict: Dictionary = data
	for voc in VOCATIONS:
		if dict.has(voc):
			var val = dict[voc]
			var parsed_xp: float = 0.0
			if val is int or val is float:
				parsed_xp = float(val)
			elif val is Dictionary and val.has("xp"):
				var inner = val["xp"]
				if inner is int or inner is float:
					parsed_xp = float(inner)
			if is_nan(parsed_xp) or is_inf(parsed_xp):
				parsed_xp = 0.0
			_xp[voc] = clampf(parsed_xp, MIN_XP, MAX_XP)
