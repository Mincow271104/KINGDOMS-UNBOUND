class_name SettlementImmigrationPolicy
extends RefCounted
## Centralized Phase 5 Immigration Policy & Eligibility Evaluator for Rival Settlements.
## Every threshold below is a PROVISIONAL Phase 5 design parameter unless its comment names
## an existing approved source (such as SettlementSimulationConfig.DAILY_RATION_FOOD).

const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementSimulationConfigScript = preload("res://scripts/world/settlement_simulation_config.gd")
const SettlementSimulationStateScript = preload("res://scripts/world/settlement_simulation_state.gd")
const SettlementEconomyScript = preload("res://scripts/world/settlement_economy.gd")
const SettlementDataScript = preload("res://scripts/world/settlement_data.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")

# --- Provisional Phase 5 Default Policy Parameters ---
# Bounded daily admission probability when all 4 eligibility gates pass (0.0 .. 1.0).
const DEFAULT_DAILY_ADMISSION_PROBABILITY: float = 0.5
# Maximum number of immigrants a single settlement may admit in one simulation day.
const DEFAULT_MAX_ADMISSIONS_PER_DAY: int = 1
# Projected population food sustainability horizon (grounded in SettlementSimulationConfig.SURVIVAL_EXIT_DAYS = 3.0).
const DEFAULT_FOOD_RESERVE_DAYS: float = SettlementSimulationConfigScript.SURVIVAL_EXIT_DAYS
# Minimum physical RES_FOOD floor required before any settlement can admit newcomers (PROVISIONAL).
const DEFAULT_MIN_FOOD_RESERVE: int = 10
# Minimum local non-food economic value (in gold-equivalent units via SettlementEconomy.DEFAULT_MARKET_PRICES + local gold) (PROVISIONAL).
const DEFAULT_MIN_ECONOMIC_RESERVE: int = 60
# Minimum average living-villager morale (0..100) required for stability eligibility when residents exist (PROVISIONAL).
const DEFAULT_MIN_STABILITY_MORALE: float = 50.0

var daily_admission_probability: float = DEFAULT_DAILY_ADMISSION_PROBABILITY
var max_admissions_per_day: int = DEFAULT_MAX_ADMISSIONS_PER_DAY
var food_reserve_days: float = DEFAULT_FOOD_RESERVE_DAYS
var min_food_reserve: int = DEFAULT_MIN_FOOD_RESERVE
var min_economic_reserve: int = DEFAULT_MIN_ECONOMIC_RESERVE
var min_stability_morale: float = DEFAULT_MIN_STABILITY_MORALE

func is_valid() -> bool:
	if is_nan(daily_admission_probability) or is_inf(daily_admission_probability):
		return false
	if daily_admission_probability < 0.0 or daily_admission_probability > 1.0:
		return false
	if max_admissions_per_day < 0:
		return false
	if is_nan(food_reserve_days) or is_inf(food_reserve_days) or food_reserve_days < 0.0:
		return false
	if min_food_reserve < 0 or min_economic_reserve < 0:
		return false
	if is_nan(min_stability_morale) or is_inf(min_stability_morale) or min_stability_morale < 0.0 or min_stability_morale > 100.0:
		return false
	return true

## Evaluates all four canonical eligibility gates (Housing, Food, Economy, Stability)
## without mutating any settlement state. Fails closed on missing or invalid data.
func evaluate_eligibility(
	ctx: RefCounted,
	settlement_data: RefCounted = null,
	is_isolated: bool = false
) -> Dictionary:
	var result := {
		"eligible": false,
		"rejection_reason": "",
		"housing": {"ok": false, "reason": "uninitialized", "capacity": 0, "population": 0, "available_slots": 0},
		"food": {"ok": false, "reason": "uninitialized", "food_stock": 0, "required_food": 0},
		"economy": {"ok": false, "reason": "uninitialized", "economic_value": 0, "required_value": min_economic_reserve},
		"stability": {"ok": false, "reason": "uninitialized", "survival_state": "", "living_count": 0, "morale_measured": false, "avg_morale": null}
	}

	if not is_valid():
		result["rejection_reason"] = "invalid_policy"
		return result

	if ctx == null or not ctx.has_method("is_valid") or not ctx.is_valid():
		result["rejection_reason"] = "invalid_context"
		result["housing"]["reason"] = "invalid_context"
		result["food"]["reason"] = "invalid_context"
		result["economy"]["reason"] = "invalid_context"
		result["stability"]["reason"] = "invalid_context"
		return result

	if max_admissions_per_day <= 0:
		result["rejection_reason"] = "admissions_disabled_by_policy"
		return result

	# 1. Housing Gate (Phase 3 canonical housing capacity)
	var housing_cap: int = int(ctx.get_housing_capacity())
	var current_pop: int = int(ctx.get_villager_count())
	var available_slots: int = int(ctx.get_available_housing_slots())
	var housing_ok: bool = (housing_cap > 0 and available_slots > 0 and not ctx.is_at_housing_capacity())
	var housing_reason: String = "ok"
	if housing_cap <= 0:
		housing_reason = "no_housing_capacity"
	elif available_slots <= 0 or ctx.is_at_housing_capacity():
		housing_reason = "at_housing_capacity"
	result["housing"] = {
		"ok": housing_ok,
		"reason": housing_reason,
		"capacity": housing_cap,
		"population": current_pop,
		"available_slots": available_slots
	}

	# 2. Food Gate (SettlementEconomy physical RES_FOOD only; raw_meat NEVER counts as food)
	var econ: RefCounted = ctx.economy
	var living_count: int = 0
	var morale_sum: float = 0.0
	for v in ctx.get_all_villagers():
		if v != null and v.life_state == SettlementVillagerDataScript.LIFE_ALIVE:
			living_count += 1
			morale_sum += float(v.morale)

	var projected_pop: int = living_count + 1
	var ration_per_day: int = SettlementSimulationConfigScript.DAILY_RATION_FOOD
	var required_food: int = maxi(
		min_food_reserve,
		int(ceil(float(projected_pop * ration_per_day) * food_reserve_days))
	)
	var food_stock: int = 0
	var food_ok: bool = false
	var food_reason: String = "ok"
	if econ == null or not econ.has_method("is_valid") or not econ.is_valid():
		food_reason = "missing_or_invalid_economy"
	else:
		food_stock = int(econ.get_resource(EconomyConfigScript.RES_FOOD))
		if food_stock < required_food:
			food_reason = "insufficient_food_reserve"
		else:
			food_ok = true
	result["food"] = {
		"ok": food_ok,
		"reason": food_reason,
		"food_stock": food_stock,
		"required_food": required_food
	}

	# 3. Economy Gate (Canonical GDD §11.1 valuation via SettlementEconomy.DEFAULT_MARKET_PRICES + local gold)
	# Never sums heterogeneous physical quantities as raw units; unpriced resources contribute 0.
	# RES_FOOD is excluded here so Food and Economy remain orthogonal gates.
	var econ_ok: bool = false
	var econ_reason: String = "ok"
	var econ_value: int = 0
	if econ == null or not econ.has_method("is_valid") or not econ.is_valid():
		econ_reason = "missing_or_invalid_economy"
	elif econ.has_method("verify_provider_conservation") and not econ.verify_provider_conservation():
		econ_reason = "economy_conservation_failed"
	else:
		var all_res: Dictionary = econ.get_all_resources()
		for res_id in all_res.keys():
			var r_str := String(res_id)
			if r_str == EconomyConfigScript.RES_FOOD:
				continue
			var unit_price: int = int(SettlementEconomyScript.DEFAULT_MARKET_PRICES.get(r_str, 0))
			if unit_price <= 0:
				continue
			econ_value += maxi(0, int(all_res[res_id])) * unit_price
		econ_value += maxi(0, int(econ.get_gold()))
		if econ_value < min_economic_reserve:
			econ_reason = "insufficient_economic_capacity"
		else:
			econ_ok = true
	result["economy"] = {
		"ok": econ_ok,
		"reason": econ_reason,
		"economic_value": econ_value,
		"required_value": min_economic_reserve
	}

	# 4. Stability Gate (SettlementSimulationState survival/shortfall + SettlementData.status + living morale)
	# Empty active settlements (living_count == 0) have no measured morale (morale_measured=false, avg_morale=null)
	# and are founding-eligible only when active, non-isolated, in SURVIVAL_NORMAL, with no ration shortfall.
	var st: RefCounted = ctx.sim_state
	var stab_ok: bool = false
	var stab_reason: String = "ok"
	var surv_state: String = ""
	var morale_measured: bool = (living_count > 0)
	var avg_morale: Variant = (morale_sum / float(living_count)) if morale_measured else null

	if is_isolated:
		stab_reason = "settlement_isolated"
	elif st == null:
		stab_reason = "missing_sim_state"
	elif settlement_data != null and String(settlement_data.get("status")) != SettlementDataScript.STATUS_ACTIVE:
		stab_reason = "settlement_not_active"
	else:
		surv_state = String(st.survival_state)
		if not SettlementSimulationStateScript.VALID_SURVIVAL_STATES.has(surv_state):
			stab_reason = "invalid_survival_state"
		elif bool(st.ration_shortfall):
			stab_reason = "active_ration_shortfall"
		elif surv_state != SettlementSimulationStateScript.SURVIVAL_NORMAL:
			stab_reason = "unstable_survival_state:%s" % surv_state
		elif morale_measured and (is_nan(float(avg_morale)) or is_inf(float(avg_morale)) or float(avg_morale) < min_stability_morale):
			stab_reason = "low_villager_morale"
		else:
			stab_ok = true
			if not morale_measured:
				stab_reason = "ok_unpopulated_active"
	result["stability"] = {
		"ok": stab_ok,
		"reason": stab_reason,
		"survival_state": surv_state,
		"living_count": living_count,
		"morale_measured": morale_measured,
		"avg_morale": avg_morale
	}

	# Overall gate
	if not housing_ok:
		result["rejection_reason"] = housing_reason
	elif not food_ok:
		result["rejection_reason"] = food_reason
	elif not econ_ok:
		result["rejection_reason"] = econ_reason
	elif not stab_ok:
		result["rejection_reason"] = stab_reason
	else:
		result["eligible"] = true
		result["rejection_reason"] = ""

	return result
