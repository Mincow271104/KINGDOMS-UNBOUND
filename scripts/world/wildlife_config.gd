class_name WildlifeConfig
extends RefCounted
## Configuration and taxonomy for Phase 6 Wildlife & Animal Ecosystem.

enum Category {
	AMBIENT = 0,
	PASSIVE_HUNTABLE = 1,
	DEFENSIVE = 2,
}

enum BehaviorState {
	IDLE = 0,
	WANDERING = 1,
	FLEEING = 2,
	ALERT = 3,
	DEFENSIVE_DISPLAY = 4,
	BEING_HUNTED = 5,
}

enum GaitType {
	FLUTTER = 0,
	HOP = 1,
	WALK = 2,
	TROT = 3,
}

const WILDLIFE_RNG_SALT: int = 600001
const MAX_TOTAL_POPULATION: int = 70
const HUNTER_MAX_RANGE_STEPS: int = 14
const HUNTER_MAX_PURSUIT_HOURS: float = 4.0

const SPECIES_ORDER: Array[String] = [
	"bird",
	"frog",
	"rabbit",
	"deer",
	"wild_boar",
	"mountain_goat",
]

const SPECIES_DEFS: Dictionary = {
	"bird": {
		"display_name": "Small Bird",
		"category": Category.AMBIENT,
		"biomes": [
			WorldGenerator.BiomeType.GRASSLAND,
			WorldGenerator.BiomeType.TEMPERATE_FOREST,
			WorldGenerator.BiomeType.PINE_FOREST,
		],
		"max_pop": 18,
		"cells_per_spawn": 140,
		"move_speed": 2.4,
		"flee_speed": 2.4,
		"idle_min": 1.6,
		"idle_max": 3.8,
		"gait_type": GaitType.FLUTTER,
		"burst_min": 2,
		"burst_max": 5,
		"turn_persistence": 0.70,
		"wander_radius": 10,
		"hop_height": 5.0,
		"idle_bob_amp": 0.6,
		"idle_bob_freq": 3.2,
		"awareness_radius": 0,
		"warning_duration": 0.0,
		"huntable": false,
		"raw_meat_yield": 0,
		"hunt_duration_hours": 0.0,
		"recovery_hours": 0.0,
	},
	"frog": {
		"display_name": "Frog",
		"category": Category.AMBIENT,
		"biomes": [
			WorldGenerator.BiomeType.WETLANDS,
		],
		"max_pop": 12,
		"cells_per_spawn": 90,
		"move_speed": 1.5,
		"flee_speed": 1.5,
		"idle_min": 2.4,
		"idle_max": 5.6,
		"gait_type": GaitType.HOP,
		"burst_min": 1,
		"burst_max": 2,
		"turn_persistence": 0.45,
		"wander_radius": 5,
		"hop_height": 4.0,
		"idle_bob_amp": 0.5,
		"idle_bob_freq": 1.8,
		"awareness_radius": 0,
		"warning_duration": 0.0,
		"huntable": false,
		"raw_meat_yield": 0,
		"hunt_duration_hours": 0.0,
		"recovery_hours": 0.0,
	},
	"rabbit": {
		"display_name": "Rabbit",
		"category": Category.PASSIVE_HUNTABLE,
		"biomes": [
			WorldGenerator.BiomeType.GRASSLAND,
			WorldGenerator.BiomeType.TEMPERATE_FOREST,
		],
		"max_pop": 12,
		"cells_per_spawn": 180,
		"move_speed": 2.3,
		"flee_speed": 3.6,
		"idle_min": 1.8,
		"idle_max": 4.2,
		"gait_type": GaitType.HOP,
		"burst_min": 2,
		"burst_max": 4,
		"turn_persistence": 0.55,
		"wander_radius": 7,
		"hop_height": 3.5,
		"idle_bob_amp": 0.7,
		"idle_bob_freq": 3.6,
		"awareness_radius": 4,
		"warning_duration": 0.0,
		"huntable": true,
		"raw_meat_yield": 2,
		"hunt_duration_hours": 1.5,
		"recovery_hours": 48.0,
	},
	"deer": {
		"display_name": "Deer",
		"category": Category.PASSIVE_HUNTABLE,
		"biomes": [
			WorldGenerator.BiomeType.GRASSLAND,
			WorldGenerator.BiomeType.TEMPERATE_FOREST,
			WorldGenerator.BiomeType.PINE_FOREST,
		],
		"max_pop": 12,
		"cells_per_spawn": 220,
		"move_speed": 2.0,
		"flee_speed": 3.5,
		"idle_min": 2.8,
		"idle_max": 6.2,
		"gait_type": GaitType.WALK,
		"burst_min": 3,
		"burst_max": 6,
		"turn_persistence": 0.80,
		"wander_radius": 9,
		"hop_height": 1.2,
		"idle_bob_amp": 0.4,
		"idle_bob_freq": 1.5,
		"awareness_radius": 5,
		"warning_duration": 0.0,
		"huntable": true,
		"raw_meat_yield": 4,
		"hunt_duration_hours": 2.5,
		"recovery_hours": 72.0,
	},
	"wild_boar": {
		"display_name": "Wild Boar",
		"category": Category.DEFENSIVE,
		"biomes": [
			WorldGenerator.BiomeType.TEMPERATE_FOREST,
			WorldGenerator.BiomeType.WETLANDS,
		],
		"max_pop": 8,
		"cells_per_spawn": 240,
		"move_speed": 1.8,
		"flee_speed": 2.8,
		"idle_min": 2.4,
		"idle_max": 5.0,
		"gait_type": GaitType.TROT,
		"burst_min": 2,
		"burst_max": 4,
		"turn_persistence": 0.60,
		"wander_radius": 7,
		"hop_height": 1.5,
		"idle_bob_amp": 0.8,
		"idle_bob_freq": 2.8,
		"awareness_radius": 4,
		"warning_duration": 1.1,
		"huntable": false,
		"raw_meat_yield": 0,
		"hunt_duration_hours": 0.0,
		"recovery_hours": 0.0,
	},
	"mountain_goat": {
		"display_name": "Mountain Goat",
		"category": Category.DEFENSIVE,
		"biomes": [
			WorldGenerator.BiomeType.HIGHLANDS,
		],
		"max_pop": 8,
		"cells_per_spawn": 160,
		"move_speed": 1.9,
		"flee_speed": 2.9,
		"idle_min": 2.4,
		"idle_max": 5.0,
		"gait_type": GaitType.WALK,
		"burst_min": 2,
		"burst_max": 4,
		"turn_persistence": 0.65,
		"wander_radius": 6,
		"hop_height": 2.2,
		"idle_bob_amp": 0.5,
		"idle_bob_freq": 2.0,
		"awareness_radius": 4,
		"warning_duration": 1.1,
		"huntable": false,
		"raw_meat_yield": 0,
		"hunt_duration_hours": 0.0,
		"recovery_hours": 0.0,
	},
}

static func is_huntable_species(species_id: String) -> bool:
	var def: Dictionary = SPECIES_DEFS.get(species_id, {})
	return bool(def.get("huntable", false))

static func get_species_def(species_id: String) -> Dictionary:
	return SPECIES_DEFS.get(species_id, {})

static func is_biome_allowed(species_id: String, biome_id: int) -> bool:
	var def: Dictionary = SPECIES_DEFS.get(species_id, {})
	if def.is_empty():
		return false
	var allowed: Array = def.get("biomes", [])
	return allowed.has(biome_id)

static func category_name(cat: int) -> String:
	match cat:
		Category.AMBIENT:
			return "Ambient"
		Category.PASSIVE_HUNTABLE:
			return "Passive Huntable"
		Category.DEFENSIVE:
			return "Defensive"
	return "Unknown"

static func state_name(st: int) -> String:
	match st:
		BehaviorState.IDLE:
			return "IDLE"
		BehaviorState.WANDERING:
			return "WANDERING"
		BehaviorState.FLEEING:
			return "FLEEING"
		BehaviorState.ALERT:
			return "ALERT"
		BehaviorState.DEFENSIVE_DISPLAY:
			return "DEFENSIVE_DISPLAY"
		BehaviorState.BEING_HUNTED:
			return "BEING_HUNTED"
	return "UNKNOWN"

static func biome_name(biome_id: int) -> String:
	match biome_id:
		WorldGenerator.BiomeType.GRASSLAND:
			return "Grassland"
		WorldGenerator.BiomeType.TEMPERATE_FOREST:
			return "Temperate Forest"
		WorldGenerator.BiomeType.PINE_FOREST:
			return "Pine Forest"
		WorldGenerator.BiomeType.HIGHLANDS:
			return "Highlands"
		WorldGenerator.BiomeType.WETLANDS:
			return "Wetlands"
	return "Unknown"
