class_name FactionData
extends RefCounted
## Faction Data Model for KINGDOMS UNBOUND.
## Conforms to GDD Section 10.1 & 10.2:
## Manages faction ID, name, military strength, stability, opinion, and diplomatic pacts.

enum Disposition {
	HOSTILE = 0,
	NEUTRAL = 1,
	FRIENDLY = 2,
	ALLIED = 3
}

# Strategic Goal constants (Package 1Q, GDD §10.1)
const GOAL_MILITARY_EXPANSION: String = "military_expansion"
const GOAL_TRADE_DOMINANCE: String = "trade_dominance"
const GOAL_COMMUNITY_GROWTH: String = "community_growth"
const GOAL_CONSOLIDATE_POWER: String = "consolidate_power"

const VALID_STRATEGIC_GOALS: Array[String] = [
	GOAL_MILITARY_EXPANSION,
	GOAL_TRADE_DOMINANCE,
	GOAL_COMMUNITY_GROWTH,
	GOAL_CONSOLIDATE_POWER
]

# Existence Status constants (Package 1Q, GDD §10.1, §10.5)
const STATUS_ACTIVE: String = "active"
const STATUS_IN_EXILE: String = "in_exile"
const STATUS_ELIMINATED: String = "eliminated"

const VALID_EXISTENCE_STATUSES: Array[String] = [
	STATUS_ACTIVE,
	STATUS_IN_EXILE,
	STATUS_ELIMINATED
]

var id: String
var name: String
var type: String # "player", "rival_military", "rival_merchant", "neutral_tribe"
var disposition: int = Disposition.NEUTRAL
var opinion: float = 0.0 # -100.0 to +100.0
var military_power: float = 50.0
var stability: float = 70.0 # 0.0 to 100.0
var is_at_war: bool = false
var has_nap: bool = false # Non-Aggression Pact
var has_alliance: bool = false
var resources: Dictionary = {}
var population: int = 40
var strategic_goal: String = GOAL_COMMUNITY_GROWTH
var existence_status: String = STATUS_ACTIVE

func _init(
	p_id: String = "",
	p_name: String = "",
	p_type: String = "neutral_tribe",
	p_disp: int = Disposition.NEUTRAL,
	p_opinion: float = 0.0,
	p_mil: float = 50.0,
	p_goal: String = "",
	p_status: String = STATUS_ACTIVE
) -> void:
	id = p_id
	name = p_name
	type = p_type
	disposition = p_disp
	opinion = p_opinion
	military_power = p_mil
	if not p_goal.is_empty() and VALID_STRATEGIC_GOALS.has(p_goal):
		strategic_goal = p_goal
	else:
		strategic_goal = get_default_strategic_goal(p_id, p_type)
	if VALID_EXISTENCE_STATUSES.has(p_status):
		existence_status = p_status
	else:
		existence_status = STATUS_ACTIVE

func change_opinion(delta: float) -> void:
	opinion = clampf(opinion + delta, -100.0, 100.0)
	_update_disposition_from_opinion()

func recalculate_disposition() -> void:
	_update_disposition_from_opinion()

func _update_disposition_from_opinion() -> void:
	if is_at_war:
		disposition = Disposition.HOSTILE
		return
		
	if opinion <= -40.0:
		disposition = Disposition.HOSTILE
	elif opinion < 25.0:
		disposition = Disposition.NEUTRAL
	elif opinion < 75.0:
		disposition = Disposition.FRIENDLY
	else:
		disposition = Disposition.ALLIED

func declare_war() -> void:
	is_at_war = true
	has_nap = false
	has_alliance = false
	disposition = Disposition.HOSTILE
	change_opinion(-50.0)

func sign_peace() -> void:
	is_at_war = false
	change_opinion(20.0)

func sign_nap() -> bool:
	if is_at_war or opinion < 0.0:
		return false
	has_nap = true
	change_opinion(15.0)
	return true

func sign_alliance() -> bool:
	if is_at_war or opinion < 60.0:
		return false
	has_alliance = true
	has_nap = true
	disposition = Disposition.ALLIED
	change_opinion(25.0)
	return true

func get_disposition_name() -> String:
	if is_at_war:
		return "Chiến Tranh (Hostile)"
	match disposition:
		Disposition.HOSTILE: return "Thù Địch (Hostile)"
		Disposition.NEUTRAL: return "Trung Lập (Neutral)"
		Disposition.FRIENDLY: return "Hữu Hảo (Friendly)"
		Disposition.ALLIED: return "Đồng Minh (Allied)"
		_: return "Không xác định"

static func get_default_strategic_goal(fac_id: String, fac_type: String = "") -> String:
	if fac_type == "emerging_power":
		return GOAL_CONSOLIDATE_POWER
	match fac_id:
		"rival_military":
			return GOAL_MILITARY_EXPANSION
		"rival_merchant":
			return GOAL_TRADE_DOMINANCE
		"neutral_tribe":
			return GOAL_COMMUNITY_GROWTH
		_:
			match fac_type:
				"rival_military": return GOAL_MILITARY_EXPANSION
				"rival_merchant": return GOAL_TRADE_DOMINANCE
				"emerging_power": return GOAL_CONSOLIDATE_POWER
				_: return GOAL_COMMUNITY_GROWTH

static func get_strategic_goal_label(goal_id: String) -> String:
	match goal_id:
		GOAL_MILITARY_EXPANSION: return "Mở rộng quân sự"
		GOAL_TRADE_DOMINANCE: return "Phát triển thương mại"
		GOAL_COMMUNITY_GROWTH: return "Phát triển cộng đồng"
		GOAL_CONSOLIDATE_POWER: return "Củng cố thế lực"
		_: return "Không xác định"

func get_strategic_goal_name() -> String:
	return get_strategic_goal_label(strategic_goal)

static func get_existence_status_label(status_id: String) -> String:
	match status_id:
		STATUS_ACTIVE: return "Hoạt động"
		STATUS_IN_EXILE: return "Lưu vong"
		STATUS_ELIMINATED: return "Bị loại bỏ"
		_: return "Không xác định"

func get_existence_status_name() -> String:
	return get_existence_status_label(existence_status)

func set_strategic_goal(new_goal: String) -> bool:
	if not VALID_STRATEGIC_GOALS.has(new_goal):
		return false
	strategic_goal = new_goal
	return true

func set_existence_status(new_status: String) -> bool:
	if not VALID_EXISTENCE_STATUSES.has(new_status):
		return false
	existence_status = new_status
	return true
