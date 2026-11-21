class_name SettlementSimulationConfig
extends RefCounted
## Centralized Phase 4 tuning for the Rival Settlement Villager simulation (Architecture v1.0).
## Every value below is PROVISIONAL tuning unless its comment names an existing approved source.

const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")

const HOURS_PER_DAY: int = 24

# --- Scheduler budgets (locked baseline targets from Architecture v1.0; provisional, not guarantees) ---
const MAX_WORLD_NPC_POPULATION: int = 120
const MAX_VILLAGERS_PER_BATCH: int = 32
const SOFT_BUDGET_MS_PER_FRAME: float = 1.5

# --- Backpressure (provisional). Thresholds are pending villager-hour work units. ---
const BACKPRESSURE_STEP_DOWN_2X_PENDING: int = 96
const BACKPRESSURE_STEP_DOWN_1X_PENDING: int = 192
const BACKPRESSURE_RESTORE_PENDING: int = 32

# --- Fault isolation (provisional) ---
const FAULT_ISOLATION_CONSECUTIVE_FAILURES: int = 3
const RECENT_ERROR_LIMIT: int = 8
const TRANSFER_ID_HISTORY_LIMIT: int = 256

# --- Needs. Hunger: 0 = fed, 100 = starving (SettlementVillagerData default 10). ---
# Ration is grounded in the existing approved EconomyConfig.ARMY_DAILY_FOOD_UPKEEP (1 food/day);
# no NPC-specific approved ration exists, so applying it to villagers is PROVISIONAL.
const DAILY_RATION_FOOD: int = EconomyConfigScript.ARMY_DAILY_FOOD_UPKEEP
const HUNGER_PER_HOUR: float = 1.0
const RATION_HUNGER_RESTORE: float = 30.0
const MISSING_RATION_HUNGER_PENALTY: float = 10.0
const HUNGER_MAX: float = 100.0

# --- Health (health floor 10 is the PROVISIONAL suggested floor; villagers are never removed) ---
const HEALTH_FLOOR: float = 10.0
const HEALTH_CRITICAL_THRESHOLD: float = 25.0
const HEALTH_STARVING_HUNGER: float = 90.0
const HEALTH_DECLINE_PER_HOUR: float = 1.0
const HEALTH_RECOVERY_HUNGER_MAX: float = 50.0
const HEALTH_RECOVERY_PER_HOUR: float = 0.5

# --- Fatigue ---
const FATIGUE_MAX: float = 100.0
const FATIGUE_EXHAUSTED: float = 85.0
const FATIGUE_RESUME: float = 40.0
const FATIGUE_REST_PER_HOUR: float = 8.0
const FATIGUE_IDLE_RECOVERY_PER_HOUR: float = 4.0
const FATIGUE_WORK_PER_HOUR_BY_ROLE: Dictionary = {
	SettlementVillagerDataScript.ROLE_GUARD: 2.0,
	SettlementVillagerDataScript.ROLE_HUNTER: 4.0,
	SettlementVillagerDataScript.ROLE_FARMER: 4.0,
	SettlementVillagerDataScript.ROLE_WOODCUTTER: 4.0,
	SettlementVillagerDataScript.ROLE_HAULER: 3.0,
	SettlementVillagerDataScript.ROLE_SMITH: 4.0
}

# --- Morale ---
const MORALE_GAIN_PER_HOUR: float = 1.0
const MORALE_LOSS_PER_HOUR: float = 1.0
const MORALE_STRESS_HUNGER: float = 70.0
const MORALE_STRESS_FATIGUE: float = 85.0
const MORALE_COMFORT_HUNGER: float = 50.0
const MORALE_COMFORT_FATIGUE: float = 70.0

# --- Survival Mode (thresholds are multiples of one day of rations for the living population) ---
const SURVIVAL_ENTER_DAYS: float = 1.5
const SURVIVAL_EXIT_DAYS: float = 3.0
const SURVIVAL_RECOVERY_HOURS: int = 12

# --- Hauler ---
const HAULER_CARRY_LIMIT: int = 10

static func fatigue_per_work_hour(role: String) -> float:
	return float(FATIGUE_WORK_PER_HOUR_BY_ROLE.get(role, 3.0))

## Output per completed work cycle for source-backed production. Derived from the existing approved
## EconomyConfig.BLUEPRINTS[type].base_daily_output scaled by the cycle length (PROVISIONAL derivation).
static func production_output_per_cycle(building_type: String, cycle_hours: float) -> int:
	var bp: Dictionary = EconomyConfigScript.BLUEPRINTS.get(building_type, {})
	var base_daily: float = float(bp.get("base_daily_output", 0.0))
	if base_daily <= 0.0:
		return 0
	return maxi(1, int(floor(base_daily * cycle_hours / float(HOURS_PER_DAY))))
