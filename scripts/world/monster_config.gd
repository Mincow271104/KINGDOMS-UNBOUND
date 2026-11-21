class_name MonsterConfig
extends RefCounted
## Centralized configuration for Phase 9 Hostile Monsters, Monster Nests & POIs.
## Combat values are derived directly from TacticalUnit baseline (100 HP, 25 dmg, 1.2s cd, 0.5s/cell).

enum MonsterAIState {
	IDLE = 0,
	GUARDING = 1,   # Deprecated legacy state; normalized to IDLE on load
	ALERT = 2,      # Deprecated legacy state; normalized to IDLE on load
	CHASING = 3,
	ATTACKING = 4,
	RETURNING = 5,
	DEAD = 6,
	ROAMING = 7,    # Non-combat ecological patrol/wander state
}

const FACTION_ID := "hostile_monsters"

# Nest & Population Constants
const MIN_INITIAL_NESTS: int = 4
const MAX_INITIAL_NESTS: int = 6
const INITIAL_MONSTERS_MIN: int = 1
const INITIAL_MONSTERS_MAX: int = 2
const LOCAL_MONSTER_CAP_PER_NEST: int = 3
const GLOBAL_MONSTER_CAP: int = 24
const RESPAWN_INTERVAL_HOURS: float = 36.0
const DETECTION_RADIUS_PATH_CELLS: int = 6
const MAX_PURSUIT_PATH_CELLS: int = 12
const NEST_MAX_HEALTH: float = 220.0
const MIN_NEST_SPACING: int = 14
const SETTLEMENT_EXCLUSION_RADIUS: int = 16

# Ecological Movement & Non-Combat A* Budget Constants
const MAX_NON_COMBAT_ASTAR_PER_FRAME: int = 2
const RETURN_RETRY_BACKOFF_SEC: float = 3.0
const ROAM_BUDGET_DEFER_SEC: float = 0.05
const ROAM_BIOME_IDLE_RETRY_SEC: float = 2.0
const ALERT_VISUAL_DURATION: float = 0.35
const ROAM_CANDIDATE_SAMPLE_LIMIT: int = 8
const ROAM_ASTAR_CHECK_LIMIT: int = 2
const SHARED_ANCHOR_SPIRAL_MAX_RADIUS: int = 4

# Deterministic RNG Salts (completely independent of WorldGenerator V1-V7 & POIManager)
const NEST_RNG_SALT: int = 918273
const MONSTER_RNG_SALT: int = 928374

# POI Phase 9 Constants
const POI_MIN_INITIAL_COUNT: int = 6
const POI_MAX_INITIAL_COUNT: int = 10
const POI_MIN_SPACING: int = 10
const POI_GUARD_RADIUS_PATH_CELLS: int = 5
const POI_CLAIM_PROXIMITY_PATH_CELLS: int = 1

static func get_species_defs() -> Dictionary:
	return {
		"forest_stalker": {
			"species_id": "forest_stalker",
			"display_name": "Forest Stalker",
			"display_name_vi": "Thú Rình Rập Rừng",
			"allowed_biomes": [
				WorldGenerator.BiomeType.GRASSLAND,
				WorldGenerator.BiomeType.TEMPERATE_FOREST,
				WorldGenerator.BiomeType.PINE_FOREST
			],
			"max_health": 75.0,
			"attack_damage": 14.0,
			"armor": 0.0,
			"attack_range": 1,
			"attack_cooldown": 1.0,
			"move_step_duration": 0.40,
			"roam_step_duration": 0.55,
			"idle_min": 2.0,
			"idle_max": 4.5,
			"roam_radius": 5,
			"displaced_roam_radius": 4,
			"hop_min": 2,
			"hop_max": 4,
			"allowed_transition_biomes": [
				WorldGenerator.BiomeType.HIGHLANDS,
				WorldGenerator.BiomeType.WETLANDS
			],
			"allowed_transition_steps": 2,
			"detection_radius": DETECTION_RADIUS_PATH_CELLS,
			"max_pursuit_distance": MAX_PURSUIT_PATH_CELLS,
			"nest_name": "Ổ Thú Rình Rập",
			"color": Color(0.72, 0.24, 0.22, 1.0),
			"accent_color": Color(0.95, 0.45, 0.25, 1.0),
		},
		"marsh_crawler": {
			"species_id": "marsh_crawler",
			"display_name": "Marsh Crawler",
			"display_name_vi": "Bò Sát Đầm Lầy",
			"allowed_biomes": [
				WorldGenerator.BiomeType.WETLANDS
			],
			"max_health": 115.0,
			"attack_damage": 12.0,
			"armor": 2.0,
			"attack_range": 1,
			"attack_cooldown": 1.4,
			"move_step_duration": 0.65,
			"roam_step_duration": 0.85,
			"idle_min": 3.5,
			"idle_max": 7.0,
			"roam_radius": 3,
			"displaced_roam_radius": 2,
			"hop_min": 1,
			"hop_max": 3,
			"allowed_transition_biomes": [
				WorldGenerator.BiomeType.GRASSLAND,
				WorldGenerator.BiomeType.TEMPERATE_FOREST
			],
			"allowed_transition_steps": 1,
			"detection_radius": DETECTION_RADIUS_PATH_CELLS,
			"max_pursuit_distance": MAX_PURSUIT_PATH_CELLS,
			"nest_name": "Ổ Đầm Lầy",
			"color": Color(0.32, 0.56, 0.34, 1.0),
			"accent_color": Color(0.62, 0.88, 0.42, 1.0),
		},
		"stone_brute": {
			"species_id": "stone_brute",
			"display_name": "Stone Brute",
			"display_name_vi": "Quái Đá Cao Nguyên",
			"allowed_biomes": [
				WorldGenerator.BiomeType.HIGHLANDS
			],
			"max_health": 160.0,
			"attack_damage": 22.0,
			"armor": 3.0,
			"attack_range": 1,
			"attack_cooldown": 1.6,
			"move_step_duration": 0.70,
			"roam_step_duration": 0.95,
			"idle_min": 4.5,
			"idle_max": 9.0,
			"roam_radius": 3,
			"displaced_roam_radius": 2,
			"hop_min": 1,
			"hop_max": 2,
			"allowed_transition_biomes": [
				WorldGenerator.BiomeType.PINE_FOREST,
				WorldGenerator.BiomeType.GRASSLAND
			],
			"allowed_transition_steps": 1,
			"detection_radius": DETECTION_RADIUS_PATH_CELLS,
			"max_pursuit_distance": MAX_PURSUIT_PATH_CELLS,
			"nest_name": "Hang Quái Đá",
			"color": Color(0.48, 0.45, 0.50, 1.0),
			"accent_color": Color(0.90, 0.58, 0.22, 1.0),
		}
	}

static func get_species_def(species_id: String) -> Dictionary:
	var defs := get_species_defs()
	return defs.get(species_id, {})

static func get_species_for_biome(biome: int) -> Array[String]:
	var matches: Array[String] = []
	var defs := get_species_defs()
	for sp_id in defs.keys():
		var allowed: Array = defs[sp_id].get("allowed_biomes", [])
		if allowed.has(biome):
			matches.append(sp_id)
	return matches

static func get_effective_roam_radius(species_id: String, is_displaced: bool) -> int:
	var spec := get_species_def(species_id)
	if is_displaced:
		return int(spec.get("displaced_roam_radius", 2))
	return int(spec.get("roam_radius", 3))

static func get_effective_return_threshold(species_id: String, is_displaced: bool) -> int:
	return get_effective_roam_radius(species_id, is_displaced) + 1

static func get_ai_state_name(state: int) -> String:
	match state:
		MonsterAIState.IDLE: return "IDLE"
		MonsterAIState.GUARDING: return "GUARDING"
		MonsterAIState.ALERT: return "ALERT"
		MonsterAIState.CHASING: return "CHASING"
		MonsterAIState.ATTACKING: return "ATTACKING"
		MonsterAIState.RETURNING: return "RETURNING"
		MonsterAIState.DEAD: return "DEAD"
		MonsterAIState.ROAMING: return "ROAMING"
	return "UNKNOWN"

static func get_phase9_poi_defs() -> Array[Dictionary]:
	return [
		{
			"type": "abandoned_camp",
			"name": "Abandoned Camp",
			"name_vi": "Trại Bỏ Hoang",
			"rewards": {
				EconomyConfig.RES_WOOD: 15,
				EconomyConfig.RES_TOOLS: 3
			},
			"desc": "Khu trại cũ bị bỏ lại ngoài biên giới, còn gỗ xây dựng và công cụ hữu ích."
		},
		{
			"type": "ancient_ruins",
			"name": "Ancient Ruins",
			"name_vi": "Phế Tích Cổ Đại",
			"rewards": {
				EconomyConfig.RES_GOLD: 10,
				EconomyConfig.RES_CRYSTAL: 3
			},
			"desc": "Di tích cổ đại còn lưu giữ vàng ròng và pha lê."
		},
		{
			"type": "forgotten_cache",
			"name": "Forgotten Cache",
			"name_vi": "Kho Tàng Lãng Quên",
			"rewards": {
				EconomyConfig.RES_HERBS: 10,
				EconomyConfig.RES_FOOD: 20
			},
			"desc": "Hầm chứa đồ tiếp tế bị lãng quên gồm thảo dược và lương thực."
		}
	]
