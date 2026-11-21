class_name FactionStrategyPlanner
extends RefCounted
## Deterministic Faction Strategic Decision Engine for KINGDOMS UNBOUND.
## Conforms to GDD Section 10.1 & Package 1R:
## Translates authoritative FactionData profile and state into explainable strategic intents.

# Canonical Strategic Intent IDs
const INTENT_MILITARY_BUILDUP: String = "military_buildup"
const INTENT_TRADE_EXPANSION: String = "trade_expansion"
const INTENT_COMMUNITY_DEVELOPMENT: String = "community_development"
const INTENT_POWER_CONSOLIDATION: String = "power_consolidation"
const INTENT_NONE: String = "none"

const VALID_STRATEGIC_INTENTS: Array[String] = [
	INTENT_MILITARY_BUILDUP,
	INTENT_TRADE_EXPANSION,
	INTENT_COMMUNITY_DEVELOPMENT,
	INTENT_POWER_CONSOLIDATION
]

# Reason Codes
const REASON_GOAL_ALIGNED: String = "GOAL_ALIGNED"
const REASON_WARTIME_POSTURE: String = "WARTIME_POSTURE"
const REASON_INELIGIBLE_EXILE: String = "INELIGIBLE_IN_EXILE"
const REASON_INELIGIBLE_ELIMINATED: String = "INELIGIBLE_ELIMINATED"
const REASON_ERR_INVALID_STATUS: String = "ERR_INVALID_STATUS"
const REASON_ERR_INVALID_GOAL: String = "ERR_INVALID_GOAL"
const REASON_ERR_NULL_FACTION: String = "ERR_NULL_FACTION"

## Maps canonical strategic goal to primary strategic intent
static func get_intent_for_goal(goal: String) -> String:
	match goal:
		FactionData.GOAL_MILITARY_EXPANSION:
			return INTENT_MILITARY_BUILDUP
		FactionData.GOAL_TRADE_DOMINANCE:
			return INTENT_TRADE_EXPANSION
		FactionData.GOAL_COMMUNITY_GROWTH:
			return INTENT_COMMUNITY_DEVELOPMENT
		FactionData.GOAL_CONSOLIDATE_POWER:
			return INTENT_POWER_CONSOLIDATION
		_:
			return INTENT_NONE

## Returns localized Vietnamese label for strategic intent
static func get_intent_label(intent_id: String) -> String:
	match intent_id:
		INTENT_MILITARY_BUILDUP:
			return "Tăng cường quân sự"
		INTENT_TRADE_EXPANSION:
			return "Mở rộng giao thương"
		INTENT_COMMUNITY_DEVELOPMENT:
			return "Phát triển cộng đồng"
		INTENT_POWER_CONSOLIDATION:
			return "Củng cố quyền lực"
		_:
			return "Không xác định"

## Evaluates a single faction deterministically, returning structured decision output
static func evaluate_faction_intent(fac: FactionData) -> Dictionary:
	if fac == null:
		return {
			"faction_id": "",
			"strategic_goal": "",
			"intent_id": INTENT_NONE,
			"eligible": false,
			"reason_code": REASON_ERR_NULL_FACTION,
			"posture": "unknown"
		}

	# Fail-closed validation for unrecognized existence_status
	if not FactionData.VALID_EXISTENCE_STATUSES.has(fac.existence_status):
		return {
			"faction_id": fac.id,
			"strategic_goal": fac.strategic_goal,
			"intent_id": INTENT_NONE,
			"eligible": false,
			"reason_code": REASON_ERR_INVALID_STATUS,
			"posture": "unknown"
		}

	# Fail-closed validation for unrecognized strategic_goal
	if not FactionData.VALID_STRATEGIC_GOALS.has(fac.strategic_goal):
		return {
			"faction_id": fac.id,
			"strategic_goal": fac.strategic_goal,
			"intent_id": INTENT_NONE,
			"eligible": false,
			"reason_code": REASON_ERR_INVALID_GOAL,
			"posture": "unknown"
		}

	# Existence-status gating (GDD 10.1, 10.5, Package 1R)
	# Non-active factions do not receive ordinary active-world intents
	if fac.existence_status == FactionData.STATUS_IN_EXILE:
		return {
			"faction_id": fac.id,
			"strategic_goal": fac.strategic_goal,
			"intent_id": INTENT_NONE,
			"eligible": false,
			"reason_code": REASON_INELIGIBLE_EXILE,
			"posture": "exiled"
		}

	if fac.existence_status == FactionData.STATUS_ELIMINATED:
		return {
			"faction_id": fac.id,
			"strategic_goal": fac.strategic_goal,
			"intent_id": INTENT_NONE,
			"eligible": false,
			"reason_code": REASON_INELIGIBLE_ELIMINATED,
			"posture": "eliminated"
		}

	# Active faction evaluation
	var intent: String = get_intent_for_goal(fac.strategic_goal)
	var posture: String = "wartime" if fac.is_at_war else "peacetime"
	var reason: String = REASON_WARTIME_POSTURE if fac.is_at_war else REASON_GOAL_ALIGNED

	return {
		"faction_id": fac.id,
		"strategic_goal": fac.strategic_goal,
		"intent_id": intent,
		"eligible": true,
		"reason_code": reason,
		"posture": posture
	}
