class_name FactionDiplomacyPlanner
extends RefCounted
## Deterministic Autonomous Faction Diplomacy Planner for KINGDOMS UNBOUND.
## Conforms to GDD Section 10.1, 10.2, 10.5 & Package 1T (Scope Decision 1.20):
## Pure, side-effect-free evaluator that inspects authoritative FactionData state and
## returns structured, explainable autonomous diplomacy decisions (declare_war, sign_peace, none).

# Canonical Autonomous Diplomacy Action IDs
const ACTION_DECLARE_WAR: String = "declare_war"
const ACTION_SIGN_PEACE: String = "sign_peace"
const ACTION_NONE: String = "none"

const VALID_DIPLOMACY_ACTIONS: Array[String] = [
	ACTION_DECLARE_WAR,
	ACTION_SIGN_PEACE
]
const VALID_ACTIONS: Array[String] = [
	ACTION_DECLARE_WAR,
	ACTION_SIGN_PEACE,
	ACTION_NONE
]
const ASCENDED_FACTION_TYPE: String = "emerging_power"

# Authoritative Autonomous War Thresholds (Package 1T)
const WAR_MAX_OPINION: float = -60.0
const WAR_MIN_MILITARY_POWER: float = 65.0
const WAR_MIN_STABILITY: float = 50.0

# Authoritative Autonomous Peace Thresholds (Package 1T)
const PEACE_MAX_MILITARY_POWER: float = 20.0
const PEACE_MAX_STABILITY: float = 25.0

# Canonical Reason Codes
const REASON_WAR_PREREQUISITES_MET: String = "WAR_PREREQUISITES_MET"
const REASON_PEACE_MILITARY_DEPLETED: String = "PEACE_MILITARY_DEPLETED"
const REASON_PEACE_STABILITY_LOW: String = "PEACE_STABILITY_LOW"
const REASON_PEACE_MILITARY_AND_STABILITY_LOW: String = "PEACE_MILITARY_AND_STABILITY_LOW"
const REASON_WARTIME_CONTINUES: String = "WARTIME_CONTINUES"
const REASON_INELIGIBLE_ELIMINATED: String = "INELIGIBLE_ELIMINATED"
const REASON_INELIGIBLE_EXILE_PEACETIME: String = "INELIGIBLE_EXILE_PEACETIME"
const REASON_INELIGIBLE_GOAL: String = "INELIGIBLE_GOAL"
const REASON_INELIGIBLE_UNASCENDED_CONSOLIDATION: String = "INELIGIBLE_UNASCENDED_CONSOLIDATION"
const REASON_BLOCKED_BY_TREATY: String = "BLOCKED_BY_TREATY"
const REASON_OPINION_ABOVE_WAR_THRESHOLD: String = "OPINION_ABOVE_WAR_THRESHOLD"
const REASON_MILITARY_BELOW_WAR_THRESHOLD: String = "MILITARY_BELOW_WAR_THRESHOLD"
const REASON_STABILITY_BELOW_WAR_THRESHOLD: String = "STABILITY_BELOW_WAR_THRESHOLD"
const REASON_ERR_NULL_FACTION: String = "ERR_NULL_FACTION"
const REASON_ERR_INVALID_STATUS: String = "ERR_INVALID_STATUS"
const REASON_ERR_INVALID_GOAL: String = "ERR_INVALID_GOAL"
const REASON_ERR_INVALID_STATE: String = "ERR_INVALID_STATE"

## Returns localized Vietnamese label for autonomous diplomacy action
static func get_action_label(action_id: String) -> String:
	match action_id:
		ACTION_DECLARE_WAR:
			return "Tự động tuyên chiến"
		ACTION_SIGN_PEACE:
			return "Đề nghị đình chiến"
		ACTION_NONE:
			return "Giữ nguyên trạng thái ngoại giao"
		_:
			return "Không xác định"

static func _make_decision(
	faction_id: String,
	action_id: String,
	eligible: bool,
	reason_code: String,
	inputs: Dictionary,
	explanation_vi: String
) -> Dictionary:
	return {
		"faction_id": faction_id,
		"action_id": action_id,
		"eligible": eligible,
		"reason_code": reason_code,
		"inputs": inputs,
		"explanation": explanation_vi
	}

## Pure, deterministic evaluation of a single faction's autonomous diplomatic action.
## Never mutates faction state, resources, treaties, or raid schedules.
static func evaluate_diplomatic_action(fac: FactionData) -> Dictionary:
	if fac == null:
		return _make_decision(
			"",
			ACTION_NONE,
			false,
			REASON_ERR_NULL_FACTION,
			{},
			"Thế lực rỗng (null)"
		)

	var snap_inputs: Dictionary = {
		"type": str(fac.type),
		"strategic_goal": str(fac.strategic_goal),
		"existence_status": str(fac.existence_status),
		"is_at_war": bool(fac.is_at_war),
		"opinion": float(fac.opinion),
		"military_power": float(fac.military_power),
		"stability": float(fac.stability),
		"has_nap": bool(fac.has_nap),
		"has_alliance": bool(fac.has_alliance)
	}

	# Fail-closed validation on existence_status
	if not FactionData.VALID_EXISTENCE_STATUSES.has(fac.existence_status):
		return _make_decision(
			fac.id,
			ACTION_NONE,
			false,
			REASON_ERR_INVALID_STATUS,
			snap_inputs,
			"Trạng thái tồn tại không hợp lệ (%s)" % str(fac.existence_status)
		)

	# Fail-closed validation on strategic_goal
	if not FactionData.VALID_STRATEGIC_GOALS.has(fac.strategic_goal):
		return _make_decision(
			fac.id,
			ACTION_NONE,
			false,
			REASON_ERR_INVALID_GOAL,
			snap_inputs,
			"Mục tiêu chiến lược không hợp lệ (%s)" % str(fac.strategic_goal)
		)

	# Fail-closed validation on numeric state bounds
	if is_nan(fac.opinion) or is_inf(fac.opinion) or fac.opinion < -100.0 or fac.opinion > 100.0:
		return _make_decision(
			fac.id,
			ACTION_NONE,
			false,
			REASON_ERR_INVALID_STATE,
			snap_inputs,
			"Chỉ số thiện cảm không hợp lệ"
		)
	if is_nan(fac.military_power) or is_inf(fac.military_power) or fac.military_power < 0.0:
		return _make_decision(
			fac.id,
			ACTION_NONE,
			false,
			REASON_ERR_INVALID_STATE,
			snap_inputs,
			"Chỉ số sức mạnh quân sự không hợp lệ"
		)
	if is_nan(fac.stability) or is_inf(fac.stability) or fac.stability < 0.0 or fac.stability > 100.0:
		return _make_decision(
			fac.id,
			ACTION_NONE,
			false,
			REASON_ERR_INVALID_STATE,
			snap_inputs,
			"Chỉ số ổn định không hợp lệ"
		)

	# Eliminated factions never execute autonomous diplomacy
	if fac.existence_status == FactionData.STATUS_ELIMINATED:
		return _make_decision(
			fac.id,
			ACTION_NONE,
			false,
			REASON_INELIGIBLE_ELIMINATED,
			snap_inputs,
			"Thế lực đã bị loại bỏ không thực hiện ngoại giao"
		)

	# -------------------------------------------------------------------------
	# Branch A: Faction is currently at war -> Evaluate Autonomous Peace
	# -------------------------------------------------------------------------
	if fac.is_at_war:
		# Active and in_exile factions may sign peace when military_power <= 20.0 or stability <= 25.0
		var mil_depleted: bool = fac.military_power <= PEACE_MAX_MILITARY_POWER
		var stab_low: bool = fac.stability <= PEACE_MAX_STABILITY
		if mil_depleted and stab_low:
			return _make_decision(
				fac.id,
				ACTION_SIGN_PEACE,
				true,
				REASON_PEACE_MILITARY_AND_STABILITY_LOW,
				snap_inputs,
				"Quân lực suy kiệt (%.1f <= %.1f) và nội bộ bất ổn (%.1f <= %.1f), chủ động cầu hòa" % [
					fac.military_power, PEACE_MAX_MILITARY_POWER, fac.stability, PEACE_MAX_STABILITY
				]
			)
		elif mil_depleted:
			return _make_decision(
				fac.id,
				ACTION_SIGN_PEACE,
				true,
				REASON_PEACE_MILITARY_DEPLETED,
				snap_inputs,
				"Quân lực suy kiệt (%.1f <= %.1f), chủ động cầu hòa" % [
					fac.military_power, PEACE_MAX_MILITARY_POWER
				]
			)
		elif stab_low:
			return _make_decision(
				fac.id,
				ACTION_SIGN_PEACE,
				true,
				REASON_PEACE_STABILITY_LOW,
				snap_inputs,
				"Nội bộ bất ổn nghiêm trọng (%.1f <= %.1f), chủ động cầu hòa" % [
					fac.stability, PEACE_MAX_STABILITY
				]
			)
		else:
			return _make_decision(
				fac.id,
				ACTION_NONE,
				false,
				REASON_WARTIME_CONTINUES,
				snap_inputs,
				"Đang giao chiến và vẫn còn đủ quân lực (%.1f) cùng độ ổn định (%.1f)" % [
					fac.military_power, fac.stability
				]
			)

	# -------------------------------------------------------------------------
	# Branch B: Faction is not at war -> Evaluate Autonomous War Declaration
	# -------------------------------------------------------------------------
	# 1. Only active factions can initiate war (in_exile cannot declare war)
	if fac.existence_status != FactionData.STATUS_ACTIVE:
		return _make_decision(
			fac.id,
			ACTION_NONE,
			false,
			REASON_INELIGIBLE_EXILE_PEACETIME,
			snap_inputs,
			"Thế lực đang lưu vong không thể chủ động tuyên chiến"
		)

	# 2. Strategic goal & post-ascension type gating:
	# Only military_expansion OR post-ascension emerging_power with consolidate_power may initiate war.
	if fac.strategic_goal == FactionData.GOAL_CONSOLIDATE_POWER:
		if fac.type != ASCENDED_FACTION_TYPE:
			return _make_decision(
				fac.id,
				ACTION_NONE,
				false,
				REASON_INELIGIBLE_UNASCENDED_CONSOLIDATION,
				snap_inputs,
				"Chưa trỗi dậy thành cường bang mới nổi nên không thể chủ động tuyên chiến"
			)
	elif fac.strategic_goal != FactionData.GOAL_MILITARY_EXPANSION:
		return _make_decision(
			fac.id,
			ACTION_NONE,
			false,
			REASON_INELIGIBLE_GOAL,
			snap_inputs,
			"Mục tiêu chiến lược (%s) không chủ động phát động chiến tranh" % fac.get_strategic_goal_name()
		)

	# 3. Non-Aggression Pact or Defensive Alliance blocks war initiation
	if fac.has_nap or fac.has_alliance:
		return _make_decision(
			fac.id,
			ACTION_NONE,
			false,
			REASON_BLOCKED_BY_TREATY,
			snap_inputs,
			"Đang bị ràng buộc bởi hiệp ước không xâm phạm hoặc liên minh phòng thủ"
		)

	# 4. Opinion threshold: opinion <= -60.0
	if fac.opinion > WAR_MAX_OPINION:
		return _make_decision(
			fac.id,
			ACTION_NONE,
			false,
			REASON_OPINION_ABOVE_WAR_THRESHOLD,
			snap_inputs,
			"Thiện cảm (%.1f) chưa giảm xuống ngưỡng tuyên chiến (<= %.1f)" % [fac.opinion, WAR_MAX_OPINION]
		)

	# 5. Military power threshold: military_power >= 65.0
	if fac.military_power < WAR_MIN_MILITARY_POWER:
		return _make_decision(
			fac.id,
			ACTION_NONE,
			false,
			REASON_MILITARY_BELOW_WAR_THRESHOLD,
			snap_inputs,
			"Sức mạnh quân sự (%.1f) chưa đạt ngưỡng tuyên chiến (>= %.1f)" % [fac.military_power, WAR_MIN_MILITARY_POWER]
		)

	# 6. Stability threshold: stability >= 50.0
	if fac.stability < WAR_MIN_STABILITY:
		return _make_decision(
			fac.id,
			ACTION_NONE,
			false,
			REASON_STABILITY_BELOW_WAR_THRESHOLD,
			snap_inputs,
			"Độ ổn định nội bộ (%.1f) chưa đạt ngưỡng tuyên chiến (>= %.1f)" % [fac.stability, WAR_MIN_STABILITY]
		)

	return _make_decision(
		fac.id,
		ACTION_DECLARE_WAR,
		true,
		REASON_WAR_PREREQUISITES_MET,
		snap_inputs,
		"%s hội đủ điều kiện quân lực (%.1f), ổn định (%.1f) và thù địch (%.1f) để tuyên chiến" % [
			fac.name, fac.military_power, fac.stability, fac.opinion
		]
	)
