class_name CookhouseConfig
extends RefCounted
## Central configuration for Cookhouse recipes, cooked meals, and temporary citizen buffs.

const MAX_QUEUE_SIZE: int = 5
const MEAL_COOLDOWN_HOURS: float = 24.0

const RECIPES: Dictionary = {
	"hearty_stew": {
		"id": "hearty_stew",
		"name_vi": "Thịt Hầm Bổ Dưỡng",
		"inputs": {
			EconomyConfig.RES_RAW_MEAT: 2,
			EconomyConfig.RES_HERBS: 1,
		},
		"output_resource": EconomyConfig.RES_HEARTY_MEAL,
		"output_amount": 1,
		"duration_hours": 3.0,
		"buff_id": "hearty_stew",
		"buff_duration_hours": 8.0,
		"effect_desc_vi": "+15% hiệu suất làm việc",
	},
	"herbal_broth": {
		"id": "herbal_broth",
		"name_vi": "Canh Thảo Mộc",
		"inputs": {
			EconomyConfig.RES_RAW_MEAT: 1,
			EconomyConfig.RES_HERBS: 2,
		},
		"output_resource": EconomyConfig.RES_HERBAL_BROTH,
		"output_amount": 1,
		"duration_hours": 2.0,
		"buff_id": "herbal_broth",
		"buff_duration_hours": 8.0,
		"effect_desc_vi": "-15% tốc độ tích lũy mệt mỏi",
	},
}

const RECIPE_ORDER: Array[String] = ["hearty_stew", "herbal_broth"]
const MEAL_PRIORITY: Array[String] = ["hearty_meal", "herbal_broth"]

const MEAL_TO_BUFF: Dictionary = {
	"hearty_meal": {
		"buff_id": "hearty_stew",
		"name_vi": "Thịt Hầm Bổ Dưỡng",
		"duration_hours": 8.0,
		"work_efficiency_mult": 1.15,
		"fatigue_gain_mult": 1.0,
		"effect_desc_vi": "+15% hiệu suất làm việc",
	},
	"herbal_broth": {
		"buff_id": "herbal_broth",
		"name_vi": "Canh Thảo Mộc",
		"duration_hours": 8.0,
		"work_efficiency_mult": 1.0,
		"fatigue_gain_mult": 0.85,
		"effect_desc_vi": "-15% tốc độ tích lũy mệt mỏi",
	},
}

const BUFF_DEFS: Dictionary = {
	"hearty_stew": {
		"buff_id": "hearty_stew",
		"name_vi": "Thịt Hầm Bổ Dưỡng",
		"duration_hours": 8.0,
		"work_efficiency_mult": 1.15,
		"fatigue_gain_mult": 1.0,
		"effect_desc_vi": "+15% hiệu suất làm việc",
	},
	"herbal_broth": {
		"buff_id": "herbal_broth",
		"name_vi": "Canh Thảo Mộc",
		"duration_hours": 8.0,
		"work_efficiency_mult": 1.0,
		"fatigue_gain_mult": 0.85,
		"effect_desc_vi": "-15% tốc độ tích lũy mệt mỏi",
	},
}

static func get_recipe(recipe_id: String) -> Dictionary:
	return RECIPES.get(recipe_id, {})

static func get_buff_def(buff_id: String) -> Dictionary:
	return BUFF_DEFS.get(buff_id, {})

static func get_buff_for_meal(meal_resource: String) -> Dictionary:
	return MEAL_TO_BUFF.get(meal_resource, {})
