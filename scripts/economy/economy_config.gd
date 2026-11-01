class_name EconomyConfig
extends RefCounted
## Central data-driven economy configuration for KINGDOMS UNBOUND.
## Defines resource IDs, names, starting quantities, and building blueprints.

# Stable Resource Identifiers
const RES_FOOD: String = "food"
const RES_WOOD: String = "wood"
const RES_STONE: String = "stone"
const RES_ORE: String = "ore"
const RES_METAL: String = "metal"
const RES_TOOLS: String = "tools"
const RES_CRYSTAL: String = "crystal"
const RES_HERBS: String = "herbs"
const RES_GOLD: String = "gold"

const ALL_RESOURCES: Array[String] = [
	RES_FOOD, RES_WOOD, RES_STONE, RES_ORE, RES_METAL,
	RES_TOOLS, RES_CRYSTAL, RES_HERBS, RES_GOLD
]

const RESOURCE_NAMES_VI: Dictionary = {
	RES_FOOD: "Lương thực",
	RES_WOOD: "Gỗ",
	RES_STONE: "Đá",
	RES_ORE: "Quặng thô",
	RES_METAL: "Kim loại",
	RES_TOOLS: "Công cụ",
	RES_CRYSTAL: "Pha lê ma thuật",
	RES_HERBS: "Thảo mộc",
	RES_GOLD: "Vàng"
}

# Post-Settlement Starting Quantities (from Master Prompt & GDD)
const STARTING_RESOURCES: Dictionary = {
	RES_FOOD: 150,
	RES_WOOD: 120,
	RES_STONE: 60,
	RES_ORE: 0,
	RES_METAL: 20,
	RES_TOOLS: 15,
	RES_CRYSTAL: 5,
	RES_HERBS: 10,
	RES_GOLD: 200
}

# Base Storage Capacities (prior to buildings)
const BASE_CAPACITIES: Dictionary = {
	RES_FOOD: 500,
	RES_WOOD: 500,
	RES_STONE: 500,
	RES_ORE: 300,
	RES_METAL: 300,
	RES_TOOLS: 200,
	RES_CRYSTAL: 100,
	RES_HERBS: 200,
	RES_GOLD: 999999 # Treasury has high unbounded capacity
}

# Building Blueprints
const BLUEPRINTS: Dictionary = {
	"house": {
		"id": "house",
		"name_vi": "Nhà Ở",
		"footprint": Vector2i(2, 2),
		"cost": {RES_WOOD: 25, RES_STONE: 10},
		"construction_hours": 8.0,
		"housing_capacity": 6,
		"storage_bonus": {},
		"max_workers": 0,
		"job_type": ""
	},
	"storehouse": {
		"id": "storehouse",
		"name_vi": "Kho Lương & Vật Liệu",
		"footprint": Vector2i(2, 2),
		"cost": {RES_WOOD: 40, RES_STONE: 25},
		"construction_hours": 12.0,
		"housing_capacity": 0,
		"storage_bonus": {
			RES_FOOD: 500, RES_WOOD: 500, RES_STONE: 500,
			RES_ORE: 300, RES_METAL: 300
		},
		"max_workers": 2,
		"job_type": "hauler"
	},
	"farm": {
		"id": "farm",
		"name_vi": "Nông Trại",
		"footprint": Vector2i(2, 2),
		"cost": {RES_WOOD: 30, RES_STONE: 5},
		"construction_hours": 10.0,
		"housing_capacity": 0,
		"storage_bonus": {},
		"max_workers": 5,
		"job_type": "farmer",
		"output_resource": RES_FOOD,
		"base_daily_output": 25.0
	},
	"woodcutter": {
		"id": "woodcutter",
		"name_vi": "Trại Tiều Phu",
		"footprint": Vector2i(2, 2),
		"cost": {RES_WOOD: 20, RES_STONE: 5},
		"construction_hours": 6.0,
		"housing_capacity": 0,
		"storage_bonus": {},
		"max_workers": 4,
		"job_type": "woodcutter",
		"output_resource": RES_WOOD,
		"base_daily_output": 20.0
	},
	"townhall": {
		"id": "townhall",
		"name_vi": "Tòa Thị Chính",
		"footprint": Vector2i(3, 3),
		"cost": {RES_WOOD: 100, RES_STONE: 80, RES_GOLD: 150},
		"construction_hours": 24.0,
		"housing_capacity": 0,
		"storage_bonus": {
			RES_FOOD: 500, RES_WOOD: 500, RES_STONE: 500,
			RES_ORE: 300, RES_METAL: 300, RES_TOOLS: 200,
			RES_CRYSTAL: 100, RES_HERBS: 200
		},
		"max_workers": 0,
		"job_type": ""
	},
	"watchtower": {
		"id": "watchtower",
		"name_vi": "Tháp Canh",
		"footprint": Vector2i(1, 1),
		"cost": {RES_WOOD: 20, RES_STONE: 15},
		"construction_hours": 6.0,
		"housing_capacity": 0,
		"storage_bonus": {},
		"max_workers": 0,
		"job_type": "",
		"vision_radius": 15
	},
	"quarry": {
		"id": "quarry",
		"name_vi": "Mỏ Khai Thác Đá",
		"footprint": Vector2i(2, 2),
		"cost": {RES_WOOD: 15, RES_TOOLS: 5},
		"construction_hours": 8.0,
		"housing_capacity": 0,
		"storage_bonus": {},
		"max_workers": 4,
		"job_type": "miner",
		"output_resource": RES_STONE,
		"base_daily_output": 20.0
	},
	"mine": {
		"id": "mine",
		"name_vi": "Mỏ Khai Thác Quặng",
		"footprint": Vector2i(2, 2),
		"cost": {RES_WOOD: 20, RES_STONE: 10},
		"construction_hours": 8.0,
		"housing_capacity": 0,
		"storage_bonus": {},
		"max_workers": 4,
		"job_type": "miner",
		"output_resource": RES_ORE,
		"base_daily_output": 20.0
	},
	"workshop": {
		"id": "workshop",
		"name_vi": "Xưởng Chế Tác",
		"footprint": Vector2i(2, 2),
		"cost": {RES_WOOD: 20, RES_STONE: 15, RES_METAL: 5},
		"construction_hours": 8.0,
		"housing_capacity": 0,
		"storage_bonus": {},
		"max_workers": 4,
		"job_type": "smith",
		"output_resource": RES_METAL,
		"recipes": {
			"smelt_metal": {
				"id": "smelt_metal",
				"name_vi": "Luyện Kim Loại",
				"inputs": {RES_ORE: 2},
				"output": RES_METAL,
				"output_amount": 1,
				"duration_hours": 3.0,
				"buffer_capacity": 40,
				"worker_quota": 2
			},
			"craft_tools": {
				"id": "craft_tools",
				"name_vi": "Rèn Công Cụ",
				"inputs": {RES_METAL: 2, RES_WOOD: 1},
				"output": RES_TOOLS,
				"output_amount": 1,
				"duration_hours": 3.0,
				"buffer_capacity": 40,
				"worker_quota": 2
			}
		}
	},
	"research_hall": {
		"id": "research_hall",
		"name_vi": "Viện Nghiên Cứu Hoàng Gia",
		"footprint": Vector2i(3, 3),
		"cost": {RES_WOOD: 25, RES_STONE: 10},
		"construction_hours": 12.0,
		"housing_capacity": 0,
		"storage_bonus": {},
		"max_workers": 0,
		"job_type": ""
	},
	"barracks": {
		"id": "barracks",
		"name_vi": "Doanh Trại",
		"footprint": Vector2i(3, 3),
		"cost": {RES_WOOD: 25, RES_STONE: 20, RES_METAL: 5},
		"construction_hours": 12.0,
		"housing_capacity": 0,
		"storage_bonus": {},
		"max_workers": 2,
		"guard_capacity": 2,
		"job_type": "guard"
	},
	"palisade": {
		"id": "palisade",
		"name_vi": "Tường Rào Phòng Ngự",
		"footprint": Vector2i(1, 1),
		"cost": {RES_WOOD: 4, RES_STONE: 2},
		"construction_hours": 3.0,
		"housing_capacity": 0,
		"storage_bonus": {},
		"max_workers": 0,
		"job_type": ""
	},
	"market": {
		"id": "market",
		"name_vi": "Chợ",
		"footprint": Vector2i(3, 3),
		"cost": {RES_WOOD: 25, RES_STONE: 10},
		"construction_hours": 12.0,
		"housing_capacity": 0,
		"storage_bonus": {},
		"max_workers": 0,
		"job_type": ""
	}
}

# -----------------------------------------------------------------------------
# Military & Player Army Configuration (Package 1L)
# -----------------------------------------------------------------------------
const ARMY_CAPACITY_PER_BARRACKS: int = 5
const ARMY_RECRUIT_COST: Dictionary = {
	RES_GOLD: 20,
	RES_METAL: 2,
	RES_FOOD: 5
}
const ARMY_DAILY_FOOD_UPKEEP: int = 1
const ARMY_MORALE_SUPPLIED: float = 70.0
const ARMY_MORALE_UNSUPPLIED: float = 45.0

# -----------------------------------------------------------------------------
# Settlement Building Upgrades Configuration (Package 2I)
# -----------------------------------------------------------------------------
const UPGRADEABLE_BUILDINGS: Array[String] = ["house", "farm", "storehouse"]
const MAX_BUILDING_LEVEL: int = 3
const MIN_UPGRADE_DURATION_HOURS: float = 2.0

const UPGRADE_TIERS: Dictionary = {
	2: {
		"cost_mult": 0.75,
		"duration_mult": 0.50
	},
	3: {
		"cost_mult": 1.25,
		"duration_mult": 0.75
	}
}

const UPGRADE_PROFILES: Dictionary = {
	"house": {
		"capacities": {1: 6, 2: 8, 3: 10}
	},
	"farm": {
		"multipliers": {1: 1.00, 2: 1.15, 3: 1.30}
	},
	"storehouse": {
		"multipliers": {1: 1.00, 2: 1.25, 3: 1.50}
	}
}

static func is_building_upgradeable(type: String) -> bool:
	return type in UPGRADEABLE_BUILDINGS

static func get_upgrade_cost(type: String, target_level: int) -> Dictionary:
	if not is_building_upgradeable(type) or target_level < 2 or target_level > MAX_BUILDING_LEVEL:
		return {}
	var tier_cfg: Dictionary = UPGRADE_TIERS.get(target_level, {})
	var cost_mult: float = float(tier_cfg.get("cost_mult", 1.0))
	var bp: Dictionary = BLUEPRINTS.get(type, {})
	var base_cost: Dictionary = bp.get("cost", {})
	var result: Dictionary = {}
	for res_id in base_cost:
		result[res_id] = int(ceil(float(base_cost[res_id]) * cost_mult))
	return result

static func get_upgrade_duration(type: String, target_level: int) -> float:
	if not is_building_upgradeable(type) or target_level < 2 or target_level > MAX_BUILDING_LEVEL:
		return 0.0
	var tier_cfg: Dictionary = UPGRADE_TIERS.get(target_level, {})
	var duration_mult: float = float(tier_cfg.get("duration_mult", 0.5))
	var bp: Dictionary = BLUEPRINTS.get(type, {})
	var base_hours: float = float(bp.get("construction_hours", 12.0))
	return maxf(MIN_UPGRADE_DURATION_HOURS, ceil(base_hours * duration_mult))

static func get_house_capacity(level: int) -> int:
	var lvl: int = clampi(level, 1, MAX_BUILDING_LEVEL)
	var caps: Dictionary = UPGRADE_PROFILES["house"]["capacities"]
	return int(caps.get(lvl, 6))

static func get_farm_multiplier(level: int) -> float:
	var lvl: int = clampi(level, 1, MAX_BUILDING_LEVEL)
	var mults: Dictionary = UPGRADE_PROFILES["farm"]["multipliers"]
	return float(mults.get(lvl, 1.00))

static func get_storehouse_multiplier(level: int) -> float:
	var lvl: int = clampi(level, 1, MAX_BUILDING_LEVEL)
	var mults: Dictionary = UPGRADE_PROFILES["storehouse"]["multipliers"]
	return float(mults.get(lvl, 1.00))

static func get_storehouse_bonus(level: int) -> Dictionary:
	var lvl: int = clampi(level, 1, MAX_BUILDING_LEVEL)
	var mult: float = get_storehouse_multiplier(lvl)
	var bp: Dictionary = BLUEPRINTS.get("storehouse", {})
	var base_bonus: Dictionary = bp.get("storage_bonus", {})
	var result: Dictionary = {}
	for res_id in base_bonus:
		result[res_id] = int(round(float(base_bonus[res_id]) * mult))
	return result

static func get_storehouse_bonus_delta(from_level: int, to_level: int) -> Dictionary:
	var from_bonus: Dictionary = get_storehouse_bonus(from_level)
	var to_bonus: Dictionary = get_storehouse_bonus(to_level)
	var delta: Dictionary = {}
	for res_id in to_bonus:
		var diff: int = int(to_bonus[res_id]) - int(from_bonus.get(res_id, 0))
		if diff != 0:
			delta[res_id] = diff
	return delta

static func get_building_storage_bonus(type: String, level: int = 1) -> Dictionary:
	if type == "storehouse":
		return get_storehouse_bonus(level)
	var bp: Dictionary = BLUEPRINTS.get(type, {})
	return bp.get("storage_bonus", {}).duplicate()
