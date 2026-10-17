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
	}
}
