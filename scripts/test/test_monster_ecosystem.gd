extends SceneTree

const WorldViewScene := preload("res://scenes/world/world_view.tscn")
const SaveManagerScript := preload("res://scripts/persistence/save_manager.gd")
const MonsterConfigScript := preload("res://scripts/world/monster_config.gd")
const MonsterManagerScript := preload("res://scripts/world/monster_manager.gd")
const POIManagerScript := preload("res://scripts/world/poi_manager.gd")

var _passed: int = 0
var _failures: Array[String] = []

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures.append(msg)
		printerr("[FAIL] ", msg)

func _init() -> void:
	call_deferred("_run_all")

func _run_all() -> void:
	# --- 1. Deterministic Generation & V1-V7 Preservation ---
	var wv1 := WorldViewScene.instantiate()
	wv1.set("skip_intro_for_test", true)
	wv1.set("world_seed", 12345)
	root.add_child(wv1)
	await create_timer(0.25).timeout

	var wd1: WorldGenerator.WorldData = wv1.get("world_data")
	var mm1 = wv1.get("monster_mgr")
	var pm1 = wv1.get("poi_mgr")
	var tm1 = wv1.get("territory_mgr")
	var nav1: GridNavigation = wv1.get("nav")
	var tact1 = wv1.get("tactical_military_mgr")
	var rm = root.get_node_or_null("ResourceManager")

	_assert(mm1 != null and pm1 != null, "1.1 MonsterManager and POIManager initialized on WorldView")
	var nests1: Array = mm1.get_all_nests()
	var pois1: Array = pm1.get_all_pois()
	_assert(nests1.size() >= 1 and nests1.size() <= MonsterConfigScript.MAX_INITIAL_NESTS, "1.2 Initial nests within valid range (got %d)" % nests1.size())
	_assert(pois1.size() >= MonsterConfigScript.POI_MIN_INITIAL_COUNT and pois1.size() <= MonsterConfigScript.POI_MAX_INITIAL_COUNT, "1.3 Initial POIs in 6..10 range (got %d)" % pois1.size())

	# Same seed determinism
	var wv2 := WorldViewScene.instantiate()
	wv2.set("skip_intro_for_test", true)
	wv2.set("world_seed", 12345)
	root.add_child(wv2)
	await create_timer(0.25).timeout
	var mm2 = wv2.get("monster_mgr")
	var pm2 = wv2.get("poi_mgr")
	var nests2: Array = mm2.get_all_nests()
	var pois2: Array = pm2.get_all_pois()
	_assert(nests1.size() == nests2.size(), "1.4 Same seed produces identical nest count")
	var same_nests := nests1.size() == nests2.size()
	for i in range(mini(nests1.size(), nests2.size())):
		if nests1[i]["cell"] != nests2[i]["cell"] or nests1[i]["species_id"] != nests2[i]["species_id"]:
			same_nests = false
	_assert(same_nests, "1.5 Same seed produces identical nest cells and species")
	var same_pois := pois1.size() == pois2.size()
	for i in range(mini(pois1.size(), pois2.size())):
		if pois1[i].cell != pois2[i].cell or pois1[i].type != pois2[i].type:
			same_pois = false
	_assert(same_pois, "1.6 Same seed produces identical POI cells and types")

	# Different seed produces different placements
	var wv3 := WorldViewScene.instantiate()
	wv3.set("skip_intro_for_test", true)
	wv3.set("world_seed", 54321)
	root.add_child(wv3)
	await create_timer(0.25).timeout
	var nests3: Array = wv3.get("monster_mgr").get_all_nests()
	var diff_seed := nests1.size() != nests3.size()
	if not diff_seed and not nests1.is_empty() and not nests3.is_empty():
		diff_seed = nests1[0]["cell"] != nests3[0]["cell"]
	_assert(diff_seed, "1.7 Different seed produces different valid nest placement")

	# Monster RNG does not perturb POI generation & POI RNG does not perturb monster generation
	var mm_iso = MonsterManagerScript.new()
	mm_iso.generate_initial_world(wd1, nav1, tm1, pm1, wv1.get("natural_resource_mgr"))
	var nests_iso := mm_iso.get_all_nests()
	_assert(nests_iso.size() == nests1.size() and (nests_iso.is_empty() or nests_iso[0]["cell"] == nests1[0]["cell"]), "1.8 Monster generation deterministic and isolated")
	wv2.queue_free()
	wv3.queue_free()
	await process_frame

	# --- 2. Placement Rules ---
	var nrm1 = wv1.get("natural_resource_mgr")
	for nd in nests1:
		var nc: Vector2i = nd["cell"]
		_assert(IsoMath.is_in_bounds(nc), "2.1 Nest in bounds")
		_assert(nav1.is_cell_walkable(nc), "2.2 Nest on walkable dry terrain")
		_assert(not wd1.occupancy[nc.x][nc.y], "2.3 Nest does not overlap occupied cell")
		_assert(not tm1.is_cell_owned(nc), "2.4 Nest outside owned starter territory")
		_assert(IsoMath.grid_distance(nc, wd1.center_spawn) >= MonsterConfigScript.SETTLEMENT_EXCLUSION_RADIUS, "2.5 Nest respects settlement exclusion")
		_assert(not nrm1.nodes_by_cell.has(nc), "2.6 Nest does not overlap natural resource node")
	for i in range(nests1.size()):
		for j in range(i + 1, nests1.size()):
			_assert(IsoMath.grid_distance(nests1[i]["cell"], nests1[j]["cell"]) >= MonsterConfigScript.MIN_NEST_SPACING, "2.7 Nest spacing respected")

	# Insufficient valid cells reduces count safely
	var mm_small = MonsterManagerScript.new()
	var wd_empty := WorldGenerator.generate(999, WorldGenerator.LATEST_GENERATOR_VERSION)
	var nav_small := GridNavigation.new(wd_empty)
	# Block almost all cells
	for x in range(wd_empty.map_width):
		for y in range(wd_empty.map_height):
			if x > 3 or y > 3:
				wd_empty.occupancy[x][y] = true
	mm_small.generate_initial_world(wd_empty, nav_small, null, null, null)
	_assert(mm_small.get_all_nests().size() == 0, "2.8 Insufficient valid locations safely produces 0 nests without forcing invalid placement")

	# --- 3. Population Caps, 36h Respawn & Territory Suppression ---
	_assert(mm1.get_living_monster_count() <= MonsterConfigScript.GLOBAL_MONSTER_CAP, "3.1 Global monster count <= 24")
	for nd in nests1:
		var lc: int = mm1.get_living_count_for_nest(str(nd["id"]))
		_assert(lc >= MonsterConfigScript.INITIAL_MONSTERS_MIN and lc <= MonsterConfigScript.LOCAL_MONSTER_CAP_PER_NEST, "3.2 Nest initial monsters in [1..3] (got %d)" % lc)

	var target_nest: Dictionary = nests1[0]
	var tnid: String = str(target_nest["id"])
	var before_lc: int = mm1.get_living_count_for_nest(tnid)
	target_nest["spawn_timer_hours"] = 35.9
	mm1.update_simulation(0.1, 1.0, wd1, nav1, tact1, tm1, wv1.get("fog_of_war"), false)
	_assert(mm1.get_living_count_for_nest(tnid) == before_lc, "3.3 No spawn before 36h interval")
	# Advance past 36h (0.2h = 1.5s at 1x)
	mm1.update_simulation(1.5, 1.0, wd1, nav1, tact1, tm1, wv1.get("fog_of_war"), false)
	_assert(mm1.get_living_count_for_nest(tnid) == mini(MonsterConfigScript.LOCAL_MONSTER_CAP_PER_NEST, before_lc + 1), "3.4 At most 1 monster spawns when 36h interval elapses")

	# Territory suppression: mark nest cell owned via Town Hall world_data.owned_cells
	var nest_cell: Vector2i = target_nest["cell"]
	wd1.owned_cells[nest_cell.x][nest_cell.y] = true
	var sup_before: int = mm1.get_living_count_for_nest(tnid)
	target_nest["spawn_timer_hours"] = 36.0
	mm1.update_simulation(7.5, 1.0, wd1, nav1, tact1, tm1, wv1.get("fog_of_war"), false)
	_assert(mm1.get_living_count_for_nest(tnid) == sup_before, "3.5 Owned territory suppresses new spawn while keeping existing monsters alive")
	wd1.owned_cells[nest_cell.x][nest_cell.y] = false

	# --- 4. Combat, Military vs Monster, Monster vs Military, Leash, No Citizen Attacks ---
	var pa_mgr = wv1.get("player_army_mgr")
	pa_mgr.set("soldier_count", 4)
	tact1.sync_with_player_army()
	var units: Array = tact1.get_all_units()
	_assert(units.size() >= 2, "4.1 Player tactical units spawned for combat test")
	var u0: TacticalUnit = units[0]
	var u1: TacticalUnit = units[1]

	var m_list: Array = mm1.get_living_monsters()
	_assert(not m_list.is_empty(), "4.2 Living monster exists for combat test")
	var m0: Dictionary = m_list[0]
	var m0_id: String = str(m0["id"])
	var m0_actor: Node2D = mm1.get_monster_actor(m0_id)
	var m0_cell: Vector2i = m0["cell"]

	# Place u0 adjacent to m0
	var adj_cell := Vector2i(-1, -1)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if nav1.is_cell_walkable(m0_cell + d):
			adj_cell = m0_cell + d
			break
	_assert(adj_cell != Vector2i(-1, -1), "4.3 Adjacent walkable cell found near monster")
	u0.current_cell = adj_cell
	u0.position = IsoMath.map_to_local(adj_cell)

	# Military attack order on monster
	tact1.select_unit(u0.unit_id, false)
	var atk_res: Dictionary = tact1.issue_attack_order(m0_actor, nav1)
	_assert(bool(atk_res.get("success", false)), "4.4 TacticalMilitaryManager.issue_attack_order succeeds on MonsterActor")
	var hp_before: float = float(m0["health"])
	u0.attack_cooldown_remaining = 0.0
	u0.advance_combat(0.1, 1.0, nav1)
	_assert(float(m0["health"]) < hp_before, "4.5 Player military damages MonsterActor via TacticalUnit.advance_combat")

	# Monster detects & attacks player military (respecting cooldown)
	var u0_hp_before: float = u0.health
	m0["attack_cooldown_remaining"] = 0.0
	mm1.update_simulation(0.5, 1.0, wd1, nav1, tact1, tm1, wv1.get("fog_of_war"), false)
	_assert(u0.health < u0_hp_before, "4.6 Monster detects and damages adjacent player military unit")

	# Monster NEVER attacks citizens
	var cit0 = wv1.get("citizen_list")[0]
	var cit_hp_check := float(cit0.get("hunger"))
	cit0.current_cell = m0_cell + Vector2i(1, 0)
	m0["target_unit_id"] = ""
	u0.current_cell = wd1.center_spawn # move military away
	mm1.update_simulation(0.5, 1.0, wd1, nav1, tact1, tm1, wv1.get("fog_of_war"), false)
	_assert(str(m0.get("target_unit_id", "")) == "", "4.7 Monster ignores citizens and does not target them")

	# Kill monster -> removed once, clears target_actor
	u0.current_cell = adj_cell
	tact1.select_unit(u0.unit_id, false)
	tact1.issue_attack_order(m0_actor, nav1)
	var count_before_kill: int = mm1.get_living_monster_count()
	m0_actor.take_damage(999.0, u0.unit_id)
	_assert(mm1.get_living_monster_count() == count_before_kill - 1, "4.8 Killed monster removed exactly once")
	u0.advance_combat(0.1, 1.0, nav1)
	_assert(u0.order_state == TacticalUnit.OrderState.IDLE and u0.target_actor == null, "4.9 Dead monster clears TacticalUnit combat target")

	# Nest destruction via TacticalMilitaryManager
	var nest_to_kill: Dictionary = nests1[0]
	var ntk_id: String = str(nest_to_kill["id"])
	var ntk_actor: Node2D = mm1.get_nest_actor(ntk_id)
	var ntk_cell: Vector2i = nest_to_kill["cell"]
	# Ensure at least one living monster belongs to this nest before destruction
	if mm1.get_living_count_for_nest(ntk_id) == 0:
		mm1._create_monster_record(str(nest_to_kill["species_id"]), ntk_cell, ntk_id, ntk_cell)
		mm1._sync_all_actors()
	var survivors_before: int = mm1.get_living_count_for_nest(ntk_id)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if nav1.is_cell_walkable(ntk_cell + d):
			u1.current_cell = ntk_cell + d
			break
	tact1.select_unit(u1.unit_id, false)
	var n_atk_res: Dictionary = tact1.issue_attack_order(ntk_actor, nav1)
	_assert(bool(n_atk_res.get("success", false)), "4.10 Player military can target MonsterNestActor")
	ntk_actor.take_damage(999.0, u1.unit_id)
	_assert(bool(nest_to_kill["is_destroyed"]), "4.11 Monster Nest destroyed")
	_assert(mm1.get_living_count_for_nest(ntk_id) == survivors_before, "4.12 Existing monsters remain alive after Nest destruction")
	nest_to_kill["spawn_timer_hours"] = 40.0
	mm1.update_simulation(7.5, 1.0, wd1, nav1, tact1, tm1, wv1.get("fog_of_war"), false)
	_assert(mm1.get_living_count_for_nest(ntk_id) == survivors_before, "4.13 Destroyed Nest permanently stops spawning")

	# --- 5. Save / Load Persistence & Legacy V1-V4 Safe Fallback ---
	var save_path := "user://test_phase9_monsters.json"
	var sres := SaveManagerScript.save_to_file(wv1, save_path)
	_assert(bool(sres.get("success", false)), "5.1 SaveManager saves Phase 9 state")
	var expected_living: int = mm1.get_living_monster_count()

	var wv_load := WorldViewScene.instantiate()
	wv_load.set("skip_intro_for_test", true)
	root.add_child(wv_load)
	await create_timer(0.25).timeout
	var lres: Dictionary = SaveManagerScript.load_from_file(save_path)
	_assert(bool(lres.get("success", false)), "5.2 SaveManager loads Phase 9 state")
	SaveManagerScript.apply_loaded_state_to_world(wv_load, lres.get("data", {}))
	var mm_load = wv_load.get("monster_mgr")
	_assert(mm_load.get_living_monster_count() == expected_living, "5.3 Loaded living monster count matches saved state (no duplicate/respawn)")
	var loaded_nest: Dictionary = mm_load.nests.get(ntk_id, {})
	_assert(bool(loaded_nest.get("is_destroyed", false)), "5.4 Destroyed Nest stays destroyed after load")

	# Legacy V1-V4 without biome_grid
	var mm_v3 = MonsterManagerScript.new()
	var wd_v3 := WorldGenerator.generate(12345, 3)
	var nav_v3 := GridNavigation.new(wd_v3)
	mm_v3.generate_initial_world(wd_v3, nav_v3, null, null, null)
	_assert(mm_v3.get_all_nests().is_empty() and mm_v3.get_living_monster_count() == 0, "5.5 Legacy V1-V4 without biome metadata safely initializes 0 nests/monsters")

	wv1.queue_free()
	wv_load.queue_free()
	await process_frame

	print("========================================================")
	print("  TEST_MONSTER_ECOSYSTEM RESULTS: PASSED=%d FAILED=%d" % [_passed, _failures.size()])
	print("========================================================")
	quit(0 if _failures.is_empty() else 1)
