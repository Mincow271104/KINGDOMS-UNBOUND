extends SceneTree

const MonsterConfigScript := preload("res://scripts/world/monster_config.gd")
const MonsterManagerScript := preload("res://scripts/world/monster_manager.gd")
const MonsterActorScript := preload("res://scripts/world/monster_actor.gd")

var _passed: int = 0
var _failures: Array[String] = []

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures.append(msg)
		printerr("[FAIL] ", msg)

func _make_clean_world(seed_val: int = 777, gen_ver: int = WorldGenerator.LATEST_GENERATOR_VERSION, default_biome: int = WorldGenerator.BiomeType.GRASSLAND) -> WorldGenerator.WorldData:
	var wd := WorldGenerator.WorldData.new()
	wd.seed_value = seed_val
	wd.generator_version = gen_ver
	wd.map_width = 64
	wd.map_height = 64
	wd.center_spawn = Vector2i(32, 32)
	wd.terrain = []
	wd.occupancy = []
	wd.owned_cells = []
	wd.biome_grid = []
	for x in range(64):
		var t_col: Array[int] = []
		var o_col: Array[bool] = []
		var own_col: Array[bool] = []
		var b_col: Array[int] = []
		for y in range(64):
			t_col.append(WorldGenerator.TerrainType.GRASS)
			o_col.append(false)
			own_col.append(false)
			b_col.append(default_biome)
		wd.terrain.append(t_col)
		wd.occupancy.append(o_col)
		wd.owned_cells.append(own_col)
		wd.biome_grid.append(b_col)
	return wd

func _init() -> void:
	call_deferred("_run_all")

func _run_all() -> void:
	# === A. Enum & Configuration ===
	_assert(MonsterConfigScript.MonsterAIState.IDLE == 0, "A.1 IDLE == 0")
	_assert(MonsterConfigScript.MonsterAIState.GUARDING == 1, "A.2 GUARDING == 1")
	_assert(MonsterConfigScript.MonsterAIState.ALERT == 2, "A.3 ALERT == 2")
	_assert(MonsterConfigScript.MonsterAIState.CHASING == 3, "A.4 CHASING == 3")
	_assert(MonsterConfigScript.MonsterAIState.ATTACKING == 4, "A.5 ATTACKING == 4")
	_assert(MonsterConfigScript.MonsterAIState.RETURNING == 5, "A.6 RETURNING == 5")
	_assert(MonsterConfigScript.MonsterAIState.DEAD == 6, "A.7 DEAD == 6")
	_assert(MonsterConfigScript.MonsterAIState.ROAMING == 7, "A.8 ROAMING == 7")
	_assert(MonsterConfigScript.MAX_NON_COMBAT_ASTAR_PER_FRAME == 2, "A.9 MAX_NON_COMBAT_ASTAR_PER_FRAME == 2")

	var fs := MonsterConfigScript.get_species_def("forest_stalker")
	var mc := MonsterConfigScript.get_species_def("marsh_crawler")
	var sb := MonsterConfigScript.get_species_def("stone_brute")
	_assert(is_equal_approx(float(fs.get("roam_step_duration", 0.0)), 0.55) and int(fs.get("roam_radius", 0)) == 5 and int(fs.get("displaced_roam_radius", 0)) == 4 and int(fs.get("allowed_transition_steps", 0)) == 2, "A.10 forest_stalker params match design")
	_assert(is_equal_approx(float(mc.get("roam_step_duration", 0.0)), 0.85) and int(mc.get("roam_radius", 0)) == 3 and int(mc.get("displaced_roam_radius", 0)) == 2 and int(mc.get("allowed_transition_steps", 0)) == 1, "A.11 marsh_crawler params match design")
	_assert(is_equal_approx(float(sb.get("roam_step_duration", 0.0)), 0.95) and int(sb.get("roam_radius", 0)) == 3 and int(sb.get("displaced_roam_radius", 0)) == 2 and int(sb.get("allowed_transition_steps", 0)) == 1, "A.12 stone_brute params match design")

	# === B. Ecological Movement & Biome Rules ===
	var wd := _make_clean_world(101, WorldGenerator.LATEST_GENERATOR_VERSION, WorldGenerator.BiomeType.GRASSLAND)
	var nav := GridNavigation.new(wd)
	var mm := MonsterManagerScript.new()
	mm._initialized_seed = 101
	mm._is_initialized = true
	mm._roam_rng.seed = 101 + MonsterConfigScript.MONSTER_RNG_SALT + 101
	var anchor := Vector2i(20, 20)
	mm.nests["n1"] = {"id": "n1", "species_id": "forest_stalker", "name": "Test", "cell": anchor, "shared_anchor_cell": anchor, "needs_shared_anchor_init": false, "health": 220.0, "max_health": 220.0, "is_destroyed": false, "spawn_timer_hours": 0.0, "discovered": false}
	var m1 := mm._create_monster_record("forest_stalker", anchor, "n1", anchor)
	m1["state_timer"] = 0.05
	mm.update_simulation(0.1, 1.0, wd, nav, null, null, null, false)
	_assert(int(m1["state"]) == MonsterConfigScript.MonsterAIState.ROAMING, "B.1 IDLE transitions to ROAMING when state_timer <= 0")
	var rpath: Array = m1["cached_path"]
	_assert(not rpath.is_empty(), "B.2 ROAMING has non-empty cached_path")
	var all_within_radius := true
	for c in rpath:
		if IsoMath.grid_distance(c, anchor) > 5:
			all_within_radius = false
	_assert(all_within_radius, "B.3 Every intermediate ROAMING cell is within roam_radius (5)")

	# Advance until ROAMING completes -> returns to IDLE
	for _i in range(40):
		mm.update_simulation(0.2, 1.0, wd, nav, null, null, null, false)
		if int(m1["state"]) == MonsterConfigScript.MonsterAIState.IDLE:
			break
	_assert(int(m1["state"]) == MonsterConfigScript.MonsterAIState.IDLE, "B.4 ROAMING returns to IDLE upon arrival")

	# Full-path radius boundary rejection when obstacle forces A* outside effective_roam_radius
	var wd_wall := _make_clean_world(102, WorldGenerator.LATEST_GENERATOR_VERSION, WorldGenerator.BiomeType.WETLANDS)
	# Ring around (20, 20) at radius 3: block direct path from (20,20) to (23,20) so A* would have to exit radius 3
	for dy in range(-3, 4):
		wd_wall.occupancy[21][20 + dy] = true
	var nav_wall := GridNavigation.new(wd_wall)
	var mm_wall := MonsterManagerScript.new()
	mm_wall._roam_rng.seed = 202
	mm_wall.nests["n1"] = {"id": "n1", "species_id": "marsh_crawler", "name": "Test", "cell": Vector2i(20, 20), "shared_anchor_cell": Vector2i(20, 20), "needs_shared_anchor_init": false, "health": 220.0, "max_health": 220.0, "is_destroyed": false, "spawn_timer_hours": 0.0, "discovered": false}
	var m_w := mm_wall._create_monster_record("marsh_crawler", Vector2i(20, 20), "n1", Vector2i(20, 20))
	m_w["state_timer"] = 0.01
	mm_wall.update_simulation(0.05, 1.0, wd_wall, nav_wall, null, null, null, false)
	var wall_ok := true
	for c in (m_w["cached_path"] as Array):
		if IsoMath.grid_distance(c, Vector2i(20, 20)) > 3:
			wall_ok = false
	_assert(wall_ok, "B.5 ROAMING never exits effective_roam_radius even around obstacles")

	# V5-V7 Biome transition restriction: stone_brute surrounded by WETLANDS (disallowed) stays IDLE
	var wd_bio := _make_clean_world(103, WorldGenerator.LATEST_GENERATOR_VERSION, WorldGenerator.BiomeType.WETLANDS)
	wd_bio.biome_grid[20][20] = WorldGenerator.BiomeType.HIGHLANDS
	var nav_bio := GridNavigation.new(wd_bio)
	var mm_bio := MonsterManagerScript.new()
	mm_bio._roam_rng.seed = 303
	mm_bio.nests["n1"] = {"id": "n1", "species_id": "stone_brute", "name": "Test", "cell": Vector2i(20, 20), "shared_anchor_cell": Vector2i(20, 20), "needs_shared_anchor_init": false, "health": 220.0, "max_health": 220.0, "is_destroyed": false, "spawn_timer_hours": 0.0, "discovered": false}
	var m_bio := mm_bio._create_monster_record("stone_brute", Vector2i(20, 20), "n1", Vector2i(20, 20))
	m_bio["state_timer"] = 0.01
	mm_bio.update_simulation(0.05, 1.0, wd_bio, nav_bio, null, null, null, false)
	_assert(int(m_bio["state"]) == MonsterConfigScript.MonsterAIState.IDLE and (m_bio["cached_path"] as Array).is_empty(), "B.6 V5-V7 never bypasses biome transition restrictions")

	# Legacy V1-V4 no-biome fallback
	var wd_v3 := _make_clean_world(104, 3, WorldGenerator.BiomeType.GRASSLAND)
	wd_v3.biome_grid.clear()
	var nav_v3 := GridNavigation.new(wd_v3)
	var mm_v3 := MonsterManagerScript.new()
	mm_v3._roam_rng.seed = 404
	mm_v3.nests["n1"] = {"id": "n1", "species_id": "stone_brute", "name": "Test", "cell": Vector2i(20, 20), "shared_anchor_cell": Vector2i(20, 20), "needs_shared_anchor_init": false, "health": 220.0, "max_health": 220.0, "is_destroyed": false, "spawn_timer_hours": 0.0, "discovered": false}
	var m_v3 := mm_v3._create_monster_record("stone_brute", Vector2i(20, 20), "n1", Vector2i(20, 20))
	m_v3["state_timer"] = 0.01
	mm_v3.update_simulation(0.05, 1.0, wd_v3, nav_v3, null, null, null, false)
	_assert(int(m_v3["state"]) == MonsterConfigScript.MonsterAIState.ROAMING, "B.7 Legacy V1-V4 without biome_grid allows walkable roaming")

	# === C. Displaced Pack & Operational Return Destination ===
	var wd_disp := _make_clean_world(105, WorldGenerator.LATEST_GENERATOR_VERSION, WorldGenerator.BiomeType.GRASSLAND)
	wd_disp.occupancy[20][20] = true # Make Nest cell non-walkable at destruction time
	var nav_disp := GridNavigation.new(wd_disp)
	var mm_disp := MonsterManagerScript.new()
	mm_disp._last_nav = nav_disp
	mm_disp._roam_rng.seed = 505
	mm_disp.nests["n1"] = {"id": "n1", "species_id": "forest_stalker", "name": "Test", "cell": Vector2i(20, 20), "shared_anchor_cell": Vector2i(20, 20), "needs_shared_anchor_init": false, "health": 220.0, "max_health": 220.0, "is_destroyed": false, "spawn_timer_hours": 0.0, "discovered": false}
	var md1 := mm_disp._create_monster_record("forest_stalker", Vector2i(20, 21), "n1", Vector2i(20, 20))
	var md2 := mm_disp._create_monster_record("forest_stalker", Vector2i(38, 20), "n1", Vector2i(20, 20)) # > 12 path cells away
	mm_disp._on_nest_destroyed("n1", "u1")
	var shared_a: Vector2i = mm_disp.nests["n1"]["shared_anchor_cell"]
	_assert(shared_a != Vector2i(20, 20) and nav_disp.is_cell_walkable(shared_a), "C.1 Destroyed Nest with non-walkable cell selects deterministic walkable spiral shared_anchor_cell")
	_assert(bool(md1["is_displaced"]) and bool(md2["is_displaced"]) and md1["anchor_cell"] == shared_a and md2["anchor_cell"] == shared_a, "C.2 All survivors share exact same shared_anchor_cell and is_displaced=true")

	# Distant monster (> 12 path cells) can RETURNING without leash rejection
	md2["state"] = MonsterConfigScript.MonsterAIState.RETURNING
	mm_disp.update_simulation(0.05, 1.0, wd_disp, nav_disp, null, null, null, false)
	_assert(not (md2["cached_path"] as Array).is_empty(), "C.3 Distant monster (> 12 path cells) successfully paths in RETURNING")

	# start == goal immediate arrival (0 A* calls, no endless retry loop)
	var md_goal := mm_disp._create_monster_record("forest_stalker", shared_a, "n1", shared_a)
	md_goal["state"] = MonsterConfigScript.MonsterAIState.RETURNING
	mm_disp.update_simulation(0.05, 1.0, wd_disp, nav_disp, null, null, null, false)
	_assert(int(md_goal["state"]) == MonsterConfigScript.MonsterAIState.IDLE and mm_disp.get_non_combat_astar_calls_last_frame() == 0, "C.4 start == goal completes RETURNING -> IDLE immediately with 0 A* calls")

	# Isolated walkable anchor -> fails, enters local IDLE with 3.0s backoff, succeeds after bridge/unblock
	var wd_iso := _make_clean_world(106, WorldGenerator.LATEST_GENERATOR_VERSION, WorldGenerator.BiomeType.GRASSLAND)
	for y in range(64):
		wd_iso.terrain[25][y] = WorldGenerator.TerrainType.WATER
	var nav_iso := GridNavigation.new(wd_iso)
	var mm_iso2 := MonsterManagerScript.new()
	mm_iso2._roam_rng.seed = 606
	mm_iso2.nests["n1"] = {"id": "n1", "species_id": "forest_stalker", "name": "Test", "cell": Vector2i(10, 20), "shared_anchor_cell": Vector2i(10, 20), "needs_shared_anchor_init": false, "health": 220.0, "max_health": 220.0, "is_destroyed": false, "spawn_timer_hours": 0.0, "discovered": false}
	var m_iso := mm_iso2._create_monster_record("forest_stalker", Vector2i(30, 20), "n1", Vector2i(10, 20))
	m_iso["state"] = MonsterConfigScript.MonsterAIState.RETURNING
	mm_iso2.update_simulation(0.05, 1.0, wd_iso, nav_iso, null, null, null, false)
	_assert(int(m_iso["state"]) == MonsterConfigScript.MonsterAIState.IDLE and float(m_iso["return_retry_timer"]) > 2.5, "C.5 Isolated anchor enters local IDLE with 3.0s retry backoff")
	# Build bridge at (25, 20) and advance 3.1s
	wd_iso.bridge_walkable_cells[Vector2i(25, 20)] = true
	mm_iso2.update_simulation(3.1, 1.0, wd_iso, nav_iso, null, null, null, false)
	_assert(int(m_iso["state"]) == MonsterConfigScript.MonsterAIState.RETURNING and not (m_iso["cached_path"] as Array).is_empty(), "C.6 After 3.0s backoff and bridge added, monster retries RETURNING and succeeds")

	# === D. Global Non-Combat A* Budget & Queue Lifecycle ===
	var wd_b := _make_clean_world(107, WorldGenerator.LATEST_GENERATOR_VERSION, WorldGenerator.BiomeType.GRASSLAND)
	var nav_b := GridNavigation.new(wd_b)
	var mm_b := MonsterManagerScript.new()
	mm_b._roam_rng.seed = 707
	mm_b.nests["n1"] = {"id": "n1", "species_id": "forest_stalker", "name": "Test", "cell": Vector2i(20, 20), "shared_anchor_cell": Vector2i(20, 20), "needs_shared_anchor_init": false, "health": 220.0, "max_health": 220.0, "is_destroyed": false, "spawn_timer_hours": 0.0, "discovered": false}
	for i in range(12):
		var mr := mm_b._create_monster_record("forest_stalker", Vector2i(30 + (i % 4), 20 + int(i / 4)), "n1", Vector2i(20, 20))
		mr["state"] = MonsterConfigScript.MonsterAIState.RETURNING
	var m_roam_wait := mm_b._create_monster_record("forest_stalker", Vector2i(20, 21), "n1", Vector2i(20, 20))
	m_roam_wait["state_timer"] = 0.01

	var max_calls_seen := 0
	for _f in range(6):
		mm_b.update_simulation(0.05, 1.0, wd_b, nav_b, null, null, null, false)
		max_calls_seen = maxi(max_calls_seen, mm_b.get_non_combat_astar_calls_last_frame())
		if _f == 0:
			_assert(int(m_roam_wait["state"]) == MonsterConfigScript.MonsterAIState.IDLE, "D.1 RETURNING has priority over ROAMING when budget is full")
	_assert(max_calls_seen <= 2, "D.2 Non-combat A* calls per frame never exceed 2 (saw %d)" % max_calls_seen)

	# Stale token rejection & generation safety
	var m_tok := mm_b.monsters[0]
	m_tok["state"] = MonsterConfigScript.MonsterAIState.RETURNING
	m_tok["cached_path"] = [] as Array[Vector2i]
	m_tok["return_retry_timer"] = 0.0
	mm_b._invalidate_return_request(m_tok)
	mm_b._enqueue_return_request(m_tok)
	var old_gen: int = int(m_tok["return_req_gen"])
	mm_b._invalidate_return_request(m_tok)
	m_tok["state"] = MonsterConfigScript.MonsterAIState.RETURNING
	mm_b._enqueue_return_request(m_tok)
	var new_gen: int = int(m_tok["return_req_gen"])
	_assert(new_gen > old_gen and int(mm_b._active_return_gen.get(str(m_tok["id"]), -1)) == new_gen, "D.3 Re-enqueue increments return_req_gen and stale entry cannot overwrite newer active token")

	# === E. Save/Load, Legacy Migration & Visual Sync ===
	var saved_dict := mm_b.serialize()
	var rng_state_before: int = mm_b._roam_rng.state
	var mm_load := MonsterManagerScript.new()
	_assert(mm_load.deserialize(saved_dict), "E.1 deserialize succeeds")
	_assert(mm_load._roam_rng.state == rng_state_before, "E.2 _roam_rng state preserved across serialize/deserialize")
	_assert(mm_load._active_return_search.is_empty(), "E.3 Transient search cursor cleared on load")

	# Legacy Phase 9 payload migration (GUARDING=1, ALERT=2, CHASING=3, ATTACKING=4, RETURNING=5, DEAD=6, missing shared_anchor_cell)
	var legacy_payload := {
		"initialized": true,
		"seed": 999,
		"next_monster_seq": 10,
		"nests": [
			{"id": "ln1", "species_id": "forest_stalker", "name": "Old", "cell": [15, 15], "health": 0.0, "max_health": 220.0, "is_destroyed": true, "spawn_timer_hours": 0.0, "discovered": true}
		],
		"monsters": [
			{"id": "lm1", "species_id": "forest_stalker", "cell": [16, 15], "home_nest_id": "ln1", "anchor_cell": [15, 15], "health": 75.0, "max_health": 75.0, "state": 1},
			{"id": "lm2", "species_id": "forest_stalker", "cell": [17, 15], "home_nest_id": "ln1", "anchor_cell": [15, 15], "health": 75.0, "max_health": 75.0, "state": 2},
			{"id": "lm3", "species_id": "forest_stalker", "cell": [30, 15], "home_nest_id": "ln1", "anchor_cell": [15, 15], "health": 75.0, "max_health": 75.0, "state": 3},
			{"id": "lm4", "species_id": "forest_stalker", "cell": [18, 15], "home_nest_id": "ln1", "anchor_cell": [15, 15], "health": 75.0, "max_health": 75.0, "state": 5},
			{"id": "lm5", "species_id": "forest_stalker", "cell": [19, 15], "home_nest_id": "ln1", "anchor_cell": [15, 15], "health": 0.0, "max_health": 75.0, "state": 6},
		]
	}
	var mm_leg := MonsterManagerScript.new()
	mm_leg.deserialize(legacy_payload)
	_assert(mm_leg.get_living_monster_count() == 4, "E.4 DEAD legacy monster skipped on load")
	_assert(bool(mm_leg.nests["ln1"]["needs_shared_anchor_init"]), "E.5 Legacy destroyed nest defers shared_anchor_init until nav != null")
	_assert(int(mm_leg.get_monster_record("lm1")["state"]) == MonsterConfigScript.MonsterAIState.IDLE and bool(mm_leg.get_monster_record("lm1")["is_displaced"]), "E.6 GUARDING(1) -> IDLE(0) and infers is_displaced")
	_assert(int(mm_leg.get_monster_record("lm2")["state"]) == MonsterConfigScript.MonsterAIState.IDLE, "E.7 ALERT(2) -> IDLE(0)")
	_assert(int(mm_leg.get_monster_record("lm3")["state"]) == MonsterConfigScript.MonsterAIState.RETURNING, "E.8 Distant CHASING(3) -> RETURNING(5)")
	_assert(mm_leg.get_pending_return_queue_size() >= 2, "E.9 RETURNING monsters reconstructed into _pending_return_queue on load")
	mm_leg.update_simulation(0.05, 1.0, wd_b, nav_b, null, null, null, false)
	_assert(not bool(mm_leg.nests["ln1"]["needs_shared_anchor_init"]), "E.10 Deferred destroyed-nest shared anchor finalized once nav != null")

	# Visual interpolation check on MonsterActor
	var actor := MonsterActorScript.new()
	actor.configure("va1", "forest_stalker", Vector2i(10, 10), "n1", 75.0, 75.0, 0.0, MonsterConfigScript.MonsterAIState.ROAMING)
	actor.sync_visual(Vector2i(10, 10), Vector2i(11, 10), 0.5, MonsterConfigScript.MonsterAIState.ROAMING, true, 0.35, 1.0)
	var expected_pos := IsoMath.map_to_local(Vector2i(10, 10)).lerp(IsoMath.map_to_local(Vector2i(11, 10)), 0.5)
	_assert(actor.position.distance_to(expected_pos) < 0.01 and actor.facing_left and actor.current_cell == Vector2i(11, 10), "E.11 MonsterActor.sync_visual interpolates position while preserving authoritative current_cell")
	actor.free()

	# === F. Audit Coverage Gap Tests ===
	# F.1 Explicit ATTACKING (4) legacy migration (near -> IDLE, far -> RETURNING + queued)
	var leg_atk_payload := {
		"initialized": true,
		"seed": 888,
		"next_monster_seq": 5,
		"nests": [
			{"id": "an1", "species_id": "forest_stalker", "name": "N", "cell": [20, 20], "health": 220.0, "max_health": 220.0, "is_destroyed": false, "spawn_timer_hours": 0.0, "discovered": true}
		],
		"monsters": [
			{"id": "am_near", "species_id": "forest_stalker", "cell": [21, 20], "home_nest_id": "an1", "anchor_cell": [20, 20], "health": 75.0, "max_health": 75.0, "state": 4},
			{"id": "am_far", "species_id": "forest_stalker", "cell": [35, 20], "home_nest_id": "an1", "anchor_cell": [20, 20], "health": 75.0, "max_health": 75.0, "state": 4},
		]
	}
	var mm_atk := MonsterManagerScript.new()
	mm_atk.deserialize(leg_atk_payload)
	_assert(int(mm_atk.get_monster_record("am_near")["state"]) == MonsterConfigScript.MonsterAIState.IDLE, "F.1a Legacy ATTACKING(4) within return threshold migrates to IDLE(0)")
	_assert(int(mm_atk.get_monster_record("am_far")["state"]) == MonsterConfigScript.MonsterAIState.RETURNING and mm_atk.get_pending_return_queue_size() == 1, "F.1b Legacy ATTACKING(4) outside return threshold migrates to RETURNING(5) and queues request")

	# F.2 Return completion cannot occur from Manhattan distance alone (inside effective_roam_radius across water barrier)
	var wd_bar := _make_clean_world(201, WorldGenerator.LATEST_GENERATOR_VERSION, WorldGenerator.BiomeType.GRASSLAND)
	for y in range(64):
		wd_bar.terrain[21][y] = WorldGenerator.TerrainType.WATER
	var nav_bar := GridNavigation.new(wd_bar)
	var mm_bar := MonsterManagerScript.new()
	mm_bar._roam_rng.seed = 901
	mm_bar.nests["n1"] = {"id": "n1", "species_id": "forest_stalker", "name": "B", "cell": Vector2i(20, 20), "shared_anchor_cell": Vector2i(20, 20), "needs_shared_anchor_init": false, "health": 220.0, "max_health": 220.0, "is_destroyed": false, "spawn_timer_hours": 0.0, "discovered": false}
	# (22, 20) is Manhattan distance 2 (<= roam_radius 5) from (20, 20), but separated by water at x=21
	var m_bar := mm_bar._create_monster_record("forest_stalker", Vector2i(22, 20), "n1", Vector2i(20, 20))
	m_bar["state"] = MonsterConfigScript.MonsterAIState.RETURNING
	mm_bar.update_simulation(0.05, 1.0, wd_bar, nav_bar, null, null, null, false)
	_assert(bool(m_bar["needs_return_retry"]) and float(m_bar["return_retry_timer"]) > 2.5, "F.2 Return within Manhattan radius across impassable barrier fails with retry backoff instead of false completion")

	# F.3 Walkable but isolated logical anchor does not fall back to arbitrary nearby cells
	_assert(mm_bar.get_monster_record(str(m_bar["id"]))["anchor_cell"] == Vector2i(20, 20) and (m_bar["cached_path"] as Array).is_empty(), "F.3 Walkable isolated anchor keeps single logical anchor without arbitrary fallback")

	# F.4 Home-area connectivity rejection across an impassable barrier when logical anchor is non-walkable
	var wd_hconn := _make_clean_world(202, WorldGenerator.LATEST_GENERATOR_VERSION, WorldGenerator.BiomeType.GRASSLAND)
	wd_hconn.occupancy[20][20] = true # Non-walkable logical anchor
	for y in range(64):
		wd_hconn.terrain[21][y] = WorldGenerator.TerrainType.WATER # Separates Side A (x<=20, where home_ref_cell (20,19) lies) from Side B (x>=22)
	var nav_hconn := GridNavigation.new(wd_hconn)
	var mm_hconn := MonsterManagerScript.new()
	mm_hconn._roam_rng.seed = 902
	mm_hconn.nests["n1"] = {"id": "n1", "species_id": "marsh_crawler", "name": "HC", "cell": Vector2i(20, 20), "shared_anchor_cell": Vector2i(20, 20), "needs_shared_anchor_init": false, "health": 220.0, "max_health": 220.0, "is_destroyed": true, "spawn_timer_hours": 0.0, "discovered": false}
	# Side B has walkable cell (22, 20) inside roam_radius 3 of (20, 20), but disconnected from home_ref_cell (20, 19) on Side A
	var m_hc := mm_hconn._create_monster_record("marsh_crawler", Vector2i(22, 20), "n1", Vector2i(20, 20))
	m_hc["is_displaced"] = true
	m_hc["state"] = MonsterConfigScript.MonsterAIState.RETURNING
	for _step in range(10):
		mm_hconn.update_simulation(0.05, 1.0, wd_hconn, nav_hconn, null, null, null, false)
	_assert(bool(m_hc["needs_return_retry"]) and (m_hc["cached_path"] as Array).is_empty(), "F.4 Non-walkable anchor rejects walkable cells on monster's isolated side that lack home-area connectivity")

	# F.5 Exact two-call budget under simultaneous RETURNING (1) and ROAMING (2 ready)
	var wd_sim := _make_clean_world(203, WorldGenerator.LATEST_GENERATOR_VERSION, WorldGenerator.BiomeType.GRASSLAND)
	var nav_sim := GridNavigation.new(wd_sim)
	var mm_sim := MonsterManagerScript.new()
	mm_sim._roam_rng.seed = 903
	mm_sim.nests["n1"] = {"id": "n1", "species_id": "forest_stalker", "name": "S", "cell": Vector2i(20, 20), "shared_anchor_cell": Vector2i(20, 20), "needs_shared_anchor_init": false, "health": 220.0, "max_health": 220.0, "is_destroyed": false, "spawn_timer_hours": 0.0, "discovered": false}
	var m_ret1 := mm_sim._create_monster_record("forest_stalker", Vector2i(30, 20), "n1", Vector2i(20, 20))
	m_ret1["state"] = MonsterConfigScript.MonsterAIState.RETURNING
	var m_roam1 := mm_sim._create_monster_record("forest_stalker", Vector2i(20, 21), "n1", Vector2i(20, 20))
	m_roam1["state_timer"] = 0.01
	var m_roam2 := mm_sim._create_monster_record("forest_stalker", Vector2i(20, 22), "n1", Vector2i(20, 20))
	m_roam2["state_timer"] = 0.01
	mm_sim.update_simulation(0.05, 1.0, wd_sim, nav_sim, null, null, null, false)
	_assert(mm_sim.get_non_combat_astar_calls_last_frame() == 2 and not (m_ret1["cached_path"] as Array).is_empty() and int(m_roam1["state"]) == MonsterConfigScript.MonsterAIState.ROAMING and int(m_roam2["state"]) == MonsterConfigScript.MonsterAIState.IDLE, "F.5 Simultaneous RETURNING + ROAMING uses exact 2 A* calls (1 RETURNING + 1 ROAMING) and defers 2nd ROAMING")

	# F.6 Suspended search resumes without repeating completed candidates and without false 3.0s backoff
	var wd_sus := _make_clean_world(204, WorldGenerator.LATEST_GENERATOR_VERSION, WorldGenerator.BiomeType.GRASSLAND)
	wd_sus.occupancy[20][20] = true # Non-walkable anchor
	var nav_sus := GridNavigation.new(wd_sus)
	var mm_sus := MonsterManagerScript.new()
	mm_sus._roam_rng.seed = 904
	mm_sus.nests["n1"] = {"id": "n1", "species_id": "marsh_crawler", "name": "Sus", "cell": Vector2i(20, 20), "shared_anchor_cell": Vector2i(20, 20), "needs_shared_anchor_init": false, "health": 220.0, "max_health": 220.0, "is_destroyed": true, "spawn_timer_hours": 0.0, "discovered": false}
	# Use m_pre (1 A* call) ahead in queue so m_sus only gets 1 A* call on Frame 1
	var m_pre := mm_sus._create_monster_record("marsh_crawler", Vector2i(32, 20), "n1", Vector2i(20, 20))
	m_pre["is_displaced"] = true
	m_pre["state"] = MonsterConfigScript.MonsterAIState.RETURNING
	# Block cand 0 (20,19) with occupancy on its 4 neighbors? No: make (20,19) unreachable from (30,20) by blocking (20,19) itself?
	# Even cleaner: make (20,19) walkable & isolated on (20,19), while (19,20) is open? No, if (20,19) is isolated, cand 1 cannot connect to home_ref_cell (20,19)!
	# Instead, put m_sus on an open world with m_pre + m_pre2 using 2 calls on Frame 1 -> m_sus is queued, OR:
	# Make m_pre use 1 call, and m_sus has cand 0 = (20,19) unreachable ONLY if (20,19) is isolated, wait: if (20,19) is NOT isolated, cand 0 succeeds in 1 call!
	# So test suspension via home_conn_verified: on Frame 1, m_pre uses 1 call; m_sus checks cand 0 = (20,19) (fails ret_path if m_sus is at (30,20) and (20,19) is isolated -> cand_idx advances to 1) -> suspended at cand_idx=1!
	wd_sus.occupancy[20][18] = true
	wd_sus.occupancy[19][19] = true
	wd_sus.occupancy[21][19] = true
	var m_sus := mm_sus._create_monster_record("marsh_crawler", Vector2i(30, 20), "n1", Vector2i(20, 20))
	m_sus["is_displaced"] = true
	m_sus["state"] = MonsterConfigScript.MonsterAIState.RETURNING
	# Frame 1: m_pre uses 1 call (succeeds on (20,19)? No, (20,19) is isolated -> m_pre uses 2 calls? Let's put m_pre on anchor (10,10) so m_pre uses 1 call and succeeds!)
	mm_sus.nests["n2"] = {"id": "n2", "species_id": "marsh_crawler", "name": "Pre", "cell": Vector2i(10, 10), "shared_anchor_cell": Vector2i(10, 10), "needs_shared_anchor_init": false, "health": 220.0, "max_health": 220.0, "is_destroyed": false, "spawn_timer_hours": 0.0, "discovered": false}
	m_pre["home_nest_id"] = "n2"
	m_pre["anchor_cell"] = Vector2i(10, 10)
	m_pre["is_displaced"] = false
	mm_sus.update_simulation(0.05, 1.0, wd_sus, nav_sus, null, null, null, false)
	var sus_id := str(m_sus["id"])
	var sus_cursor: Dictionary = mm_sus._active_return_search.get(sus_id, {})
	_assert(int(sus_cursor.get("cand_idx", -1)) == 1 and float(m_sus["return_retry_timer"]) == 0.0 and mm_sus._active_return_gen.has(sus_id), "F.6a Suspended search preserves cand_idx=1 without false 3.0s backoff")
	# Frame 2: resumes at cand_idx=1 without repeating cand_idx=0 (uses <= 2 calls, advances cand_idx further)
	mm_sus.update_simulation(0.05, 1.0, wd_sus, nav_sus, null, null, null, false)
	var sus_cursor_2: Dictionary = mm_sus._active_return_search.get(sus_id, {})
	_assert(int(sus_cursor_2.get("cand_idx", -1)) >= 2 and mm_sus.get_non_combat_astar_calls_last_frame() <= 2, "F.6b Resumed search continues from cand_idx=1 without restarting")

	# F.7 Old generation queue entry cannot erase newer active request
	m_roam2["state_timer"] = 10.0
	var stale_mid := str(m_ret1["id"])
	mm_sim._invalidate_return_request(m_ret1)
	m_ret1["state"] = MonsterConfigScript.MonsterAIState.RETURNING
	m_ret1["cached_path"] = [] as Array[Vector2i]
	m_ret1["return_retry_timer"] = 0.0
	mm_sim._enqueue_return_request(m_ret1)
	var newer_gen: int = int(mm_sim._active_return_gen.get(stale_mid, -1))
	mm_sim._pending_return_queue.push_front({"monster_id": stale_mid, "gen": newer_gen - 1})
	mm_sim.update_simulation(0.05, 1.0, wd_sim, nav_sim, null, null, null, false)
	_assert(mm_sim.get_non_combat_astar_calls_last_frame() == 1 and not (m_ret1["cached_path"] as Array).is_empty(), "F.7 Stale entry in queue is discarded with 0 A* calls and never erases newer active request")

	# F.8 All 24 simultaneous RETURNING monsters drain and complete cleanly
	var wd_24 := _make_clean_world(205, WorldGenerator.LATEST_GENERATOR_VERSION, WorldGenerator.BiomeType.GRASSLAND)
	var nav_24 := GridNavigation.new(wd_24)
	var mm_24 := MonsterManagerScript.new()
	mm_24._roam_rng.seed = 905
	mm_24.nests["n1"] = {"id": "n1", "species_id": "forest_stalker", "name": "24", "cell": Vector2i(20, 20), "shared_anchor_cell": Vector2i(20, 20), "needs_shared_anchor_init": false, "health": 220.0, "max_health": 220.0, "is_destroyed": false, "spawn_timer_hours": 0.0, "discovered": false}
	for i in range(24):
		var m24 := mm_24._create_monster_record("forest_stalker", Vector2i(35 + (i % 4), 20 + int(i / 4)), "n1", Vector2i(20, 20))
		m24["state"] = MonsterConfigScript.MonsterAIState.RETURNING
	var max_24 := 0
	var drain_astar_24 := -1
	for _f in range(12):
		mm_24.update_simulation(0.0167, 1.0, wd_24, nav_24, null, null, null, false)
		max_24 = maxi(max_24, mm_24.get_non_combat_astar_calls_last_frame())
	drain_astar_24 = mm_24.get_non_combat_astar_calls_total()
	_assert(max_24 <= 2 and drain_astar_24 == 24 and mm_24.get_pending_return_queue_size() == 0, "F.8a All 24 simultaneous RETURNING requests drain in 12 frames with exactly 24 A* calls (<=2/frame)")
	for _f2 in range(240):
		mm_24.update_simulation(0.05, 1.0, wd_24, nav_24, null, null, null, false)
		# Check right when all 24 have finished RETURNING
		var still_ret := 0
		for m24 in mm_24.monsters:
			if int(m24["state"]) == MonsterConfigScript.MonsterAIState.RETURNING:
				still_ret += 1
		if still_ret == 0:
			break
	var idle_or_roam_ok_24 := 0
	for m24 in mm_24.monsters:
		if int(m24["state"]) in [MonsterConfigScript.MonsterAIState.IDLE, MonsterConfigScript.MonsterAIState.ROAMING] and not bool(m24.get("needs_return_retry", false)):
			idle_or_roam_ok_24 += 1
	_assert(idle_or_roam_ok_24 == 24, "F.8b All 24 returning monsters complete return cleanly with 0 failures")


	print("========================================================")
	print("  TEST_MONSTER_MOVEMENT_ECOLOGY RESULTS: PASSED=%d FAILED=%d" % [_passed, _failures.size()])
	print("========================================================")
	quit(0 if _failures.is_empty() else 1)
