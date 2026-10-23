class_name FactionStrategyExecutor
extends RefCounted
## Deterministic Faction Strategic Intent Execution Engine for KINGDOMS UNBOUND.
## Conforms to GDD Section 10.1, 10.3, 10.5 & Package 1S:
## Translates pure strategic intent decisions from FactionStrategyPlanner into
## bounded, atomic, explainable, and idempotent faction state mutations.

# Canonical Strategic Action Constants
const MILITARY_BUILDUP_COST_METAL: int = 10
const MILITARY_BUILDUP_COST_GOLD: int = 25
const MILITARY_BUILDUP_GAIN_POWER: float = 5.0
const MILITARY_BUILDUP_CAP_POWER: float = 120.0

const TRADE_EXPANSION_COST_TOOLS: int = 5
const TRADE_EXPANSION_GAIN_GOLD: int = 30
const TRADE_EXPANSION_CAP_GOLD: int = 1000
const TRADE_EXPANSION_GAIN_STABILITY: float = 2.0
const TRADE_EXPANSION_CAP_STABILITY: float = 95.0

const COMMUNITY_DEV_COST_WOOD: int = 10
const COMMUNITY_DEV_COST_HERBS: int = 5
const COMMUNITY_DEV_GAIN_POPULATION: int = 1
const COMMUNITY_DEV_CAP_POPULATION: int = 80
const COMMUNITY_DEV_GAIN_STABILITY: float = 2.0
const COMMUNITY_DEV_CAP_STABILITY: float = 90.0

const POWER_CONSOLIDATION_COST_WOOD: int = 15
const POWER_CONSOLIDATION_COST_HERBS: int = 10
const POWER_CONSOLIDATION_GAIN_POWER: float = 4.0
const POWER_CONSOLIDATION_CAP_POWER: float = 90.0
const POWER_CONSOLIDATION_GAIN_STABILITY: float = 2.0
const POWER_CONSOLIDATION_CAP_STABILITY: float = 95.0

# Canonical Execution Reason Codes
const REASON_EXECUTED: String = "EXECUTED"
const REASON_ALREADY_EXECUTED_TODAY: String = "ALREADY_EXECUTED_TODAY"
const REASON_INELIGIBLE_STATUS: String = "INELIGIBLE_STATUS"
const REASON_INELIGIBLE_INTENT: String = "INELIGIBLE_INTENT"
const REASON_INSUFFICIENT_RESOURCES: String = "INSUFFICIENT_RESOURCES"
const REASON_AT_CAP: String = "AT_CAP"
const REASON_BLOCKED_BY_WAR: String = "BLOCKED_BY_WAR"
const REASON_ASCENDED_THIS_TICK: String = "ASCENDED_THIS_TICK"
const REASON_INELIGIBLE_CONSOLIDATION_STATE: String = "INELIGIBLE_CONSOLIDATION_STATE"
const REASON_ERR_NULL_FACTION: String = "ERR_NULL_FACTION"
const REASON_ERR_INVALID_DAY: String = "ERR_INVALID_DAY"
const REASON_ERR_INVALID_DECISION: String = "ERR_INVALID_DECISION"
const REASON_ERR_INVALID_RESOURCES: String = "ERR_INVALID_RESOURCES"

# Per-faction daily execution tracking (faction_id -> int day)
var _last_executed_days: Dictionary = {}

func reset_state() -> void:
	_last_executed_days.clear()

func get_last_executed_day(faction_id: String) -> int:
	return int(_last_executed_days.get(faction_id, -1))

func set_last_executed_day(faction_id: String, day: int) -> void:
	if faction_id.is_empty():
		return
	if day < 1:
		_last_executed_days.erase(faction_id)
	else:
		_last_executed_days[faction_id] = day

func serialize() -> Dictionary:
	var out: Dictionary = {}
	var sorted_ids: Array = _last_executed_days.keys()
	sorted_ids.sort()
	for fid in sorted_ids:
		var d: int = int(_last_executed_days[fid])
		if d >= 1:
			out[str(fid)] = d
	return {
		"last_executed_days": out
	}

func deserialize(data: Dictionary, current_day: int = -1) -> void:
	reset_state()
	if data.is_empty():
		return
	var raw_days = data.get("last_executed_days", {})
	if not (raw_days is Dictionary):
		return
	for fid in raw_days:
		if not (fid is String) or String(fid).is_empty():
			continue
		var val = raw_days[fid]
		if _is_valid_non_negative_int(val):
			var d: int = int(val)
			# BUG-1S-01 second-layer defense: never restore a future execution day (> current_day)
			if d >= 1 and d <= 36500 and (current_day < 1 or d <= current_day):
				_last_executed_days[str(fid)] = d

static func _is_valid_non_negative_int(val: Variant) -> bool:
	if val is int:
		return val >= 0
	if val is float:
		return not is_nan(val) and not is_inf(val) and floor(val) == val and int(val) >= 0
	return false

static func _are_faction_resources_valid(fac: FactionData) -> bool:
	if fac == null or not (fac.resources is Dictionary):
		return false
	for res_key in fac.resources:
		if not (res_key is String) or String(res_key).is_empty() or not EconomyConfig.ALL_RESOURCES.has(String(res_key)):
			return false
		if not _is_valid_non_negative_int(fac.resources[res_key]):
			return false
	return true

static func _make_result(
	faction_id: String,
	day: int,
	intent_id: String,
	success: bool,
	reason_code: String,
	changes: Dictionary,
	posture: String
) -> Dictionary:
	return {
		"faction_id": faction_id,
		"day": day,
		"intent_id": intent_id,
		"success": success,
		"reason_code": reason_code,
		"changes": changes,
		"posture": posture
	}

static func _has_resources(fac: FactionData, cost: Dictionary) -> bool:
	if not _are_faction_resources_valid(fac):
		return false
	for res_id in cost:
		var required: int = int(cost[res_id])
		if required <= 0:
			continue
		if not fac.resources.has(res_id):
			return false
		var cur_val = fac.resources.get(res_id, 0)
		if not _is_valid_non_negative_int(cur_val):
			return false
		if int(cur_val) < required:
			return false
	return true

static func _deduct_resources(fac: FactionData, cost: Dictionary, changes: Dictionary) -> void:
	var spent: Dictionary = {}
	for res_id in cost:
		var amount: int = int(cost[res_id])
		if amount <= 0:
			continue
		var before: int = int(fac.resources.get(res_id, 0))
		fac.resources[res_id] = maxi(0, before - amount)
		spent[res_id] = -amount
	changes["resources_delta"] = spent

## Executes a single faction's strategic intent deterministically and atomically.
func execute_intent(
	fac: FactionData,
	decision: Dictionary,
	day: int,
	context: Dictionary = {}
) -> Dictionary:
	if fac == null:
		return _make_result("", day, FactionStrategyPlanner.INTENT_NONE, false, REASON_ERR_NULL_FACTION, {}, "unknown")

	var posture: String = str(decision.get("posture", "wartime" if fac.is_at_war else "peacetime"))
	var intent_id: String = str(decision.get("intent_id", FactionStrategyPlanner.INTENT_NONE))

	if day < 1:
		return _make_result(fac.id, day, intent_id, false, REASON_ERR_INVALID_DAY, {}, posture)

	if decision.is_empty() or not decision.has("intent_id") or not decision.has("eligible"):
		return _make_result(fac.id, day, FactionStrategyPlanner.INTENT_NONE, false, REASON_ERR_INVALID_DECISION, {}, "unknown")

	# Validate authoritative faction status and goal fail-closed
	if not FactionData.VALID_EXISTENCE_STATUSES.has(fac.existence_status) or fac.existence_status != FactionData.STATUS_ACTIVE:
		return _make_result(fac.id, day, intent_id, false, REASON_INELIGIBLE_STATUS, {}, posture)

	if not FactionData.VALID_STRATEGIC_GOALS.has(fac.strategic_goal):
		return _make_result(fac.id, day, intent_id, false, REASON_INELIGIBLE_INTENT, {}, posture)

	if not bool(decision.get("eligible", false)) or intent_id == FactionStrategyPlanner.INTENT_NONE:
		return _make_result(fac.id, day, intent_id, false, REASON_INELIGIBLE_INTENT, {}, posture)

	if not FactionStrategyPlanner.VALID_STRATEGIC_INTENTS.has(intent_id):
		return _make_result(fac.id, day, intent_id, false, REASON_INELIGIBLE_INTENT, {}, posture)

	# Ensure decision intent matches authoritative faction strategic goal
	var expected_intent: String = FactionStrategyPlanner.get_intent_for_goal(fac.strategic_goal)
	if intent_id != expected_intent:
		return _make_result(fac.id, day, intent_id, false, REASON_INELIGIBLE_INTENT, {}, posture)

	# Guard against negative/corrupted faction numeric state
	if is_nan(fac.military_power) or is_inf(fac.military_power) or fac.military_power < 0.0:
		return _make_result(fac.id, day, intent_id, false, REASON_ERR_INVALID_DECISION, {}, posture)
	if is_nan(fac.stability) or is_inf(fac.stability) or fac.stability < 0.0 or fac.stability > 100.0:
		return _make_result(fac.id, day, intent_id, false, REASON_ERR_INVALID_DECISION, {}, posture)
	if fac.population < 0:
		return _make_result(fac.id, day, intent_id, false, REASON_ERR_INVALID_DECISION, {}, posture)

	# BUG-1S-02: Validate all faction resource entries fail-closed before any action or cap check
	if not _are_faction_resources_valid(fac):
		return _make_result(fac.id, day, intent_id, false, REASON_ERR_INVALID_RESOURCES, {}, posture)

	# Per-faction daily idempotency guard: prevent duplicate execution on the same or earlier day
	var last_day: int = get_last_executed_day(fac.id)
	if last_day >= day:
		return _make_result(fac.id, day, intent_id, false, REASON_ALREADY_EXECUTED_TODAY, {}, posture)

	match intent_id:
		FactionStrategyPlanner.INTENT_MILITARY_BUILDUP:
			return _execute_military_buildup(fac, day, posture)
		FactionStrategyPlanner.INTENT_TRADE_EXPANSION:
			return _execute_trade_expansion(fac, day, posture)
		FactionStrategyPlanner.INTENT_COMMUNITY_DEVELOPMENT:
			return _execute_community_development(fac, day, posture, context)
		FactionStrategyPlanner.INTENT_POWER_CONSOLIDATION:
			return _execute_power_consolidation(fac, day, posture, context)
		_:
			return _make_result(fac.id, day, intent_id, false, REASON_INELIGIBLE_INTENT, {}, posture)

func _execute_military_buildup(fac: FactionData, day: int, posture: String) -> Dictionary:
	if fac.military_power >= MILITARY_BUILDUP_CAP_POWER - 0.0001:
		return _make_result(fac.id, day, FactionStrategyPlanner.INTENT_MILITARY_BUILDUP, false, REASON_AT_CAP, {}, posture)

	var cost := {
		EconomyConfig.RES_METAL: MILITARY_BUILDUP_COST_METAL,
		EconomyConfig.RES_GOLD: MILITARY_BUILDUP_COST_GOLD
	}
	if not _has_resources(fac, cost):
		return _make_result(fac.id, day, FactionStrategyPlanner.INTENT_MILITARY_BUILDUP, false, REASON_INSUFFICIENT_RESOURCES, {}, posture)

	var changes: Dictionary = {}
	_deduct_resources(fac, cost, changes)

	var prev_power: float = fac.military_power
	fac.military_power = clampf(prev_power + MILITARY_BUILDUP_GAIN_POWER, 0.0, MILITARY_BUILDUP_CAP_POWER)
	changes["military_power_delta"] = fac.military_power - prev_power
	changes["military_power"] = fac.military_power

	set_last_executed_day(fac.id, day)
	return _make_result(fac.id, day, FactionStrategyPlanner.INTENT_MILITARY_BUILDUP, true, REASON_EXECUTED, changes, posture)

func _execute_trade_expansion(fac: FactionData, day: int, posture: String) -> Dictionary:
	# Peacetime-only economic expansion: wartime factions cannot expand trade routes
	if fac.is_at_war:
		return _make_result(fac.id, day, FactionStrategyPlanner.INTENT_TRADE_EXPANSION, false, REASON_BLOCKED_BY_WAR, {}, posture)

	var raw_gold: Variant = fac.resources.get(EconomyConfig.RES_GOLD, 0)
	if not _is_valid_non_negative_int(raw_gold):
		return _make_result(fac.id, day, FactionStrategyPlanner.INTENT_TRADE_EXPANSION, false, REASON_ERR_INVALID_RESOURCES, {}, posture)
	var cur_gold: int = int(raw_gold)
	var gold_at_cap: bool = cur_gold >= TRADE_EXPANSION_CAP_GOLD
	var stab_at_cap: bool = fac.stability >= TRADE_EXPANSION_CAP_STABILITY - 0.0001
	if gold_at_cap and stab_at_cap:
		return _make_result(fac.id, day, FactionStrategyPlanner.INTENT_TRADE_EXPANSION, false, REASON_AT_CAP, {}, posture)

	var cost := {
		EconomyConfig.RES_TOOLS: TRADE_EXPANSION_COST_TOOLS
	}
	if not _has_resources(fac, cost):
		return _make_result(fac.id, day, FactionStrategyPlanner.INTENT_TRADE_EXPANSION, false, REASON_INSUFFICIENT_RESOURCES, {}, posture)

	var changes: Dictionary = {}
	_deduct_resources(fac, cost, changes)

	var new_gold: int = mini(cur_gold + TRADE_EXPANSION_GAIN_GOLD, TRADE_EXPANSION_CAP_GOLD)
	var gold_gain: int = new_gold - cur_gold
	fac.resources[EconomyConfig.RES_GOLD] = new_gold
	changes["resources_delta"][EconomyConfig.RES_GOLD] = gold_gain
	changes["gold"] = new_gold

	var prev_stab: float = fac.stability
	fac.stability = clampf(prev_stab + TRADE_EXPANSION_GAIN_STABILITY, 0.0, TRADE_EXPANSION_CAP_STABILITY)
	changes["stability_delta"] = fac.stability - prev_stab
	changes["stability"] = fac.stability

	set_last_executed_day(fac.id, day)
	return _make_result(fac.id, day, FactionStrategyPlanner.INTENT_TRADE_EXPANSION, true, REASON_EXECUTED, changes, posture)

func _execute_community_development(fac: FactionData, day: int, posture: String, context: Dictionary) -> Dictionary:
	# Neutral tribe has its own pre-ascension daily settlement growth (+1 pop/day) and non-consumptive
	# Wood >= 60 / Herbs >= 30 ascension gates in FactionManager (Package 1P/1Q).
	var pre_ascension_growth_handled: bool = bool(context.get("pre_ascension_growth_handled", false))
	if pre_ascension_growth_handled:
		set_last_executed_day(fac.id, day)
		return _make_result(
			fac.id,
			day,
			FactionStrategyPlanner.INTENT_COMMUNITY_DEVELOPMENT,
			true,
			REASON_EXECUTED,
			{
				"population_delta": int(context.get("population_delta", 1)),
				"population": fac.population,
				"resources_delta": {}
			},
			posture
		)

	var pop_at_cap: bool = fac.population >= COMMUNITY_DEV_CAP_POPULATION
	var stab_at_cap: bool = fac.stability >= COMMUNITY_DEV_CAP_STABILITY - 0.0001
	if pop_at_cap and stab_at_cap:
		return _make_result(fac.id, day, FactionStrategyPlanner.INTENT_COMMUNITY_DEVELOPMENT, false, REASON_AT_CAP, {}, posture)

	var cost := {
		EconomyConfig.RES_WOOD: COMMUNITY_DEV_COST_WOOD,
		EconomyConfig.RES_HERBS: COMMUNITY_DEV_COST_HERBS
	}
	if not _has_resources(fac, cost):
		return _make_result(fac.id, day, FactionStrategyPlanner.INTENT_COMMUNITY_DEVELOPMENT, false, REASON_INSUFFICIENT_RESOURCES, {}, posture)

	var changes: Dictionary = {}
	_deduct_resources(fac, cost, changes)

	var prev_pop: int = fac.population
	fac.population = mini(prev_pop + COMMUNITY_DEV_GAIN_POPULATION, COMMUNITY_DEV_CAP_POPULATION)
	changes["population_delta"] = fac.population - prev_pop
	changes["population"] = fac.population

	var prev_stab: float = fac.stability
	fac.stability = clampf(prev_stab + COMMUNITY_DEV_GAIN_STABILITY, 0.0, COMMUNITY_DEV_CAP_STABILITY)
	changes["stability_delta"] = fac.stability - prev_stab
	changes["stability"] = fac.stability

	set_last_executed_day(fac.id, day)
	return _make_result(fac.id, day, FactionStrategyPlanner.INTENT_COMMUNITY_DEVELOPMENT, true, REASON_EXECUTED, changes, posture)

func _execute_power_consolidation(fac: FactionData, day: int, posture: String, context: Dictionary) -> Dictionary:
	# Verify post-ascension state and strategic goal
	if fac.type != FactionManager.ASCENSION_NEW_TYPE or fac.strategic_goal != FactionData.GOAL_CONSOLIDATE_POWER:
		return _make_result(fac.id, day, FactionStrategyPlanner.INTENT_POWER_CONSOLIDATION, false, REASON_INELIGIBLE_CONSOLIDATION_STATE, {}, posture)

	# Do not double-apply consolidation mutation on the exact tick ascension already boosted military/stability
	if bool(context.get("ascended_today", false)):
		set_last_executed_day(fac.id, day)
		return _make_result(fac.id, day, FactionStrategyPlanner.INTENT_POWER_CONSOLIDATION, false, REASON_ASCENDED_THIS_TICK, {}, posture)

	var mil_at_cap: bool = fac.military_power >= POWER_CONSOLIDATION_CAP_POWER - 0.0001
	var stab_at_cap: bool = fac.stability >= POWER_CONSOLIDATION_CAP_STABILITY - 0.0001
	if mil_at_cap and stab_at_cap:
		return _make_result(fac.id, day, FactionStrategyPlanner.INTENT_POWER_CONSOLIDATION, false, REASON_AT_CAP, {}, posture)

	var cost := {
		EconomyConfig.RES_WOOD: POWER_CONSOLIDATION_COST_WOOD,
		EconomyConfig.RES_HERBS: POWER_CONSOLIDATION_COST_HERBS
	}
	if not _has_resources(fac, cost):
		return _make_result(fac.id, day, FactionStrategyPlanner.INTENT_POWER_CONSOLIDATION, false, REASON_INSUFFICIENT_RESOURCES, {}, posture)

	var changes: Dictionary = {}
	_deduct_resources(fac, cost, changes)

	var prev_power: float = fac.military_power
	fac.military_power = clampf(prev_power + POWER_CONSOLIDATION_GAIN_POWER, 0.0, POWER_CONSOLIDATION_CAP_POWER)
	changes["military_power_delta"] = fac.military_power - prev_power
	changes["military_power"] = fac.military_power

	var prev_stab: float = fac.stability
	fac.stability = clampf(prev_stab + POWER_CONSOLIDATION_GAIN_STABILITY, 0.0, POWER_CONSOLIDATION_CAP_STABILITY)
	changes["stability_delta"] = fac.stability - prev_stab
	changes["stability"] = fac.stability

	set_last_executed_day(fac.id, day)
	return _make_result(fac.id, day, FactionStrategyPlanner.INTENT_POWER_CONSOLIDATION, true, REASON_EXECUTED, changes, posture)
