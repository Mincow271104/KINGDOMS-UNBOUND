class_name FactionRelationData
extends RefCounted
## Authoritative Pairwise NPC-to-NPC Faction Relationship Model for KINGDOMS UNBOUND.
## Conforms to GDD Section 10.1, 10.2, 10.5 & Package 1U (Scope Decision 1.21):
## Represents the single canonical relationship record for an unordered pair of distinct NPC factions (A, B),
## storing directional opinions (`opinion_a_to_b`, `opinion_b_to_a`) and shared war/treaty state (`is_at_war`, `has_nap`, `has_alliance`).

const PAIR_KEY_SEPARATOR: String = "__"

const OPINION_MIN: float = -100.0
const OPINION_MAX: float = 100.0
const OPINION_DEFAULT: float = 0.0

const DELTA_DECLARE_WAR: float = -50.0
const DELTA_SIGN_PEACE: float = 20.0
const DELTA_SIGN_NAP: float = 15.0
const DELTA_SIGN_ALLIANCE: float = 25.0

const NAP_MIN_OPINION: float = 0.0
const ALLIANCE_MIN_OPINION: float = 60.0

var faction_a: String = "" # Lexicographically smaller faction ID (faction_a < faction_b)
var faction_b: String = "" # Lexicographically larger faction ID
var opinion_a_to_b: float = OPINION_DEFAULT
var opinion_b_to_a: float = OPINION_DEFAULT
var is_at_war: bool = false
var has_nap: bool = false
var has_alliance: bool = false

# Package 2E: Autonomous Inter-Faction Conflict Tracking
var truce_until_day: int = -1
var war_start_day: int = -1
var casus_belli: String = ""
var war_count: int = 0
var last_battle_report: Dictionary = {}

func _init(p_id_1: String = "", p_id_2: String = "") -> void:
	if not p_id_1.is_empty() and not p_id_2.is_empty() and p_id_1 != p_id_2:
		var ordered: Array[String] = make_ordered_pair(p_id_1, p_id_2)
		faction_a = ordered[0]
		faction_b = ordered[1]
	opinion_a_to_b = OPINION_DEFAULT
	opinion_b_to_a = OPINION_DEFAULT
	is_at_war = false
	has_nap = false
	has_alliance = false
	truce_until_day = -1
	war_start_day = -1
	casus_belli = ""
	war_count = 0
	last_battle_report = {}

static func is_valid_finite_number(val: Variant) -> bool:
	if val is int:
		return true
	if val is float:
		return not is_nan(val) and not is_inf(val)
	return false

static func make_ordered_pair(id_1: String, id_2: String) -> Array[String]:
	if id_1.is_empty() or id_2.is_empty() or id_1 == id_2:
		return []
	if id_1 < id_2:
		return [id_1, id_2]
	return [id_2, id_1]

static func make_pair_key(id_1: String, id_2: String) -> String:
	var ordered: Array[String] = make_ordered_pair(id_1, id_2)
	if ordered.size() != 2:
		return ""
	return ordered[0] + PAIR_KEY_SEPARATOR + ordered[1]

func get_pair_key() -> String:
	return make_pair_key(faction_a, faction_b)

func involves_faction(faction_id: String) -> bool:
	return not faction_id.is_empty() and (faction_id == faction_a or faction_id == faction_b)

func matches_pair(id_1: String, id_2: String) -> bool:
	var ordered: Array[String] = make_ordered_pair(id_1, id_2)
	if ordered.size() != 2:
		return false
	return faction_a == ordered[0] and faction_b == ordered[1]

func get_opinion(from_id: String, to_id: String) -> float:
	if from_id == faction_a and to_id == faction_b:
		return opinion_a_to_b
	if from_id == faction_b and to_id == faction_a:
		return opinion_b_to_a
	return OPINION_DEFAULT

func set_opinion(from_id: String, to_id: String, value: float) -> bool:
	if not is_valid_finite_number(value):
		return false
	var clamped: float = clampf(value, OPINION_MIN, OPINION_MAX)
	if from_id == faction_a and to_id == faction_b:
		opinion_a_to_b = clamped
		return true
	if from_id == faction_b and to_id == faction_a:
		opinion_b_to_a = clamped
		return true
	return false

func change_opinion(from_id: String, to_id: String, delta: float) -> bool:
	if not is_valid_finite_number(delta):
		return false
	if from_id == faction_a and to_id == faction_b:
		opinion_a_to_b = clampf(opinion_a_to_b + delta, OPINION_MIN, OPINION_MAX)
		return true
	if from_id == faction_b and to_id == faction_a:
		opinion_b_to_a = clampf(opinion_b_to_a + delta, OPINION_MIN, OPINION_MAX)
		return true
	return false

static func compute_disposition(opinion_val: float, at_war: bool, allied: bool) -> int:
	if at_war:
		return FactionData.Disposition.HOSTILE
	if allied:
		return FactionData.Disposition.ALLIED
	if opinion_val <= -40.0:
		return FactionData.Disposition.HOSTILE
	elif opinion_val < 25.0:
		return FactionData.Disposition.NEUTRAL
	elif opinion_val < 75.0:
		return FactionData.Disposition.FRIENDLY
	else:
		return FactionData.Disposition.ALLIED

func get_disposition(from_id: String, to_id: String) -> int:
	return compute_disposition(get_opinion(from_id, to_id), is_at_war, has_alliance)

func apply_declare_war(start_day: int = -1, reason: String = "") -> void:
	is_at_war = true
	has_nap = false
	has_alliance = false
	war_start_day = start_day
	casus_belli = reason
	war_count += 1
	opinion_a_to_b = clampf(opinion_a_to_b + DELTA_DECLARE_WAR, OPINION_MIN, OPINION_MAX)
	opinion_b_to_a = clampf(opinion_b_to_a + DELTA_DECLARE_WAR, OPINION_MIN, OPINION_MAX)

func apply_sign_peace(truce_duration: int = 6, current_day: int = -1) -> void:
	is_at_war = false
	if current_day >= 1 and truce_duration > 0:
		truce_until_day = current_day + truce_duration
	else:
		truce_until_day = -1
	opinion_a_to_b = clampf(opinion_a_to_b + DELTA_SIGN_PEACE, OPINION_MIN, OPINION_MAX)
	opinion_b_to_a = clampf(opinion_b_to_a + DELTA_SIGN_PEACE, OPINION_MIN, OPINION_MAX)

func is_on_truce(current_day: int) -> bool:
	return not is_at_war and truce_until_day >= 1 and current_day < truce_until_day

func record_battle(report_dict: Dictionary) -> void:
	last_battle_report = report_dict.duplicate(true)

func apply_sign_nap() -> void:
	has_nap = true
	opinion_a_to_b = clampf(opinion_a_to_b + DELTA_SIGN_NAP, OPINION_MIN, OPINION_MAX)
	opinion_b_to_a = clampf(opinion_b_to_a + DELTA_SIGN_NAP, OPINION_MIN, OPINION_MAX)

func apply_sign_alliance() -> void:
	has_alliance = true
	has_nap = true
	opinion_a_to_b = clampf(opinion_a_to_b + DELTA_SIGN_ALLIANCE, OPINION_MIN, OPINION_MAX)
	opinion_b_to_a = clampf(opinion_b_to_a + DELTA_SIGN_ALLIANCE, OPINION_MIN, OPINION_MAX)

func to_directed_view(from_id: String, to_id: String) -> Dictionary:
	var op_ft: float = get_opinion(from_id, to_id)
	var op_tf: float = get_opinion(to_id, from_id)
	return {
		"pair_key": get_pair_key(),
		"faction_a": faction_a,
		"faction_b": faction_b,
		"from_id": from_id,
		"to_id": to_id,
		"opinion": op_ft,
		"reverse_opinion": op_tf,
		"opinion_a_to_b": opinion_a_to_b,
		"opinion_b_to_a": opinion_b_to_a,
		"disposition": compute_disposition(op_ft, is_at_war, has_alliance),
		"reverse_disposition": compute_disposition(op_tf, is_at_war, has_alliance),
		"is_at_war": is_at_war,
		"has_nap": has_nap,
		"has_alliance": has_alliance,
		"truce_until_day": truce_until_day,
		"war_start_day": war_start_day,
		"casus_belli": casus_belli,
		"war_count": war_count,
		"last_battle_report": last_battle_report.duplicate(true)
	}

func serialize() -> Dictionary:
	return {
		"pair_key": get_pair_key(),
		"faction_a": faction_a,
		"faction_b": faction_b,
		"opinion_a_to_b": opinion_a_to_b,
		"opinion_b_to_a": opinion_b_to_a,
		"is_at_war": is_at_war,
		"has_nap": has_nap,
		"has_alliance": has_alliance,
		"truce_until_day": truce_until_day,
		"war_start_day": war_start_day,
		"casus_belli": casus_belli,
		"war_count": war_count,
		"last_battle_report": last_battle_report.duplicate(true)
	}
