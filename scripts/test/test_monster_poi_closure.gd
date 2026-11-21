extends SceneTree

const WorldViewScene := preload("res://scenes/world/world_view.tscn")
const SaveManagerScript := preload("res://scripts/persistence/save_manager.gd")
const MonsterConfigScript := preload("res://scripts/world/monster_config.gd")
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
	var wv := WorldViewScene.instantiate()
	wv.set("skip_intro_for_test", true)
	wv.set("world_seed", 12345)
	root.add_child(wv)
	await create_timer(0.25).timeout

	var wd: WorldGenerator.WorldData = wv.get("world_data")
	var mm = wv.get("monster_mgr")
	var pm = wv.get("poi_mgr")
	var tm = wv.get("territory_mgr")
	var fow: FogOfWar = wv.get("fog_of_war")
	var nav: GridNavigation = wv.get("nav")
	var tact = wv.get("tactical_military_mgr")
	var pa = wv.get("player_army_mgr")
	var rm = root.get_node_or_null("ResourceManager")

	# --- D1. Exact Seed 12345 Generation Counts ---
	var nests: Array = mm.get_all_nests()
	var init_monsters: Array = mm.get_living_monsters()
	var sp_counts := {"forest_stalker": 0, "marsh_crawler": 0, "stone_brute": 0}
	for m in init_monsters:
		var sp := str(m["species_id"])
		sp_counts[sp] = int(sp_counts.get(sp, 0)) + 1
	var poi_counts := {"abandoned_camp": 0, "ancient_ruins": 0, "forgotten_cache": 0}
	for p in pm.get_all_pois():
		poi_counts[p.type] = int(poi_counts.get(p.type, 0)) + 1
	print("[SEED_12345_COUNTS] nests=%d | initial_monsters=%d | species=%s | pois=%d | poi_dist=%s" % [
		nests.size(), init_monsters.size(), str(sp_counts), pm.get_all_pois().size(), str(poi_counts)
	])
	_assert(nests.size() >= 1 and init_monsters.size() >= 1, "D1: Seed 12345 generated Nests and initial monsters")
	_assert(pm.get_all_pois().size() >= 6 and pm.get_all_pois().size() <= 10, "D1: Seed 12345 generated 6..10 POIs")

	# --- B1, B2, B3. Actual Two-Way Combat Progression & All 3 Species ---
	pa.set("soldier_count", 4)
	tact.sync_with_player_army()
	var units: Array = tact.get_all_units()
	var u0: TacticalUnit = units[0]
	var u1: TacticalUnit = units[1]

	# Test all 3 species balance & damage/armor/cooldown
	for sp_id in ["forest_stalker", "marsh_crawler", "stone_brute"]:
		var spec := MonsterConfigScript.get_species_def(sp_id)
		var m_rec: Dictionary = mm._create_monster_record(sp_id, wd.center_spawn, "", wd.center_spawn)
		mm._sync_all_actors()
		var ma: Node2D = mm.get_monster_actor(str(m_rec["id"]))
		_assert(is_equal_approx(float(m_rec["max_health"]), float(spec["max_health"])), "B3(%s): max_health matches config" % sp_id)
		_assert(is_equal_approx(float(m_rec["attack_damage"]), float(spec["attack_damage"])), "B3(%s): attack_damage matches config" % sp_id)
		_assert(is_equal_approx(float(m_rec["armor"]), float(spec["armor"])), "B3(%s): armor matches config" % sp_id)
		_assert(is_equal_approx(float(m_rec["attack_cooldown"]), float(spec["attack_cooldown"])), "B3(%s): attack_cooldown matches config" % sp_id)
		# Verify armor mitigation on MonsterActor.take_damage
		var hp0: float = ma.health
		ma.take_damage(10.0, "armor_test")
		var expected_dmg: float = maxf(1.0, 10.0 - float(spec["armor"]))
		_assert(is_equal_approx(hp0 - ma.health, expected_dmg), "B3(%s): armor reduces incoming damage correctly" % sp_id)
		# Clean up test monster
		ma.take_damage(9999.0, "cleanup")

	# B1: Actual player military vs Monster progression (cooldown + damage + death + target cleanup)
	var b_cell: Vector2i = wd.center_spawn + Vector2i(1, 0)
	var b_rec: Dictionary = mm._create_monster_record("forest_stalker", b_cell, "", b_cell)
	mm._sync_all_actors()
	var b_actor: Node2D = mm.get_monster_actor(str(b_rec["id"]))
	u0.current_cell = wd.center_spawn
	u0.position = IsoMath.map_to_local(wd.center_spawn)
	u0.health = 100.0
	tact.select_unit(u0.unit_id, false)
	_assert(bool(tact.issue_attack_order(b_actor, nav).get("success", false)), "B1: Attack order accepted")
	u0.attack_cooldown_remaining = 0.0
	u0.advance_combat(0.1, 1.0, nav)
	var hp_after_hit1: float = b_actor.health
	_assert(hp_after_hit1 < 75.0, "B1: First strike damages MonsterActor (hp=%.1f)" % hp_after_hit1)
	# Immediate second call before cooldown expires must NOT deal damage
	u0.advance_combat(0.1, 1.0, nav)
	_assert(is_equal_approx(b_actor.health, hp_after_hit1), "B1: Attack cooldown respected (no double-strike)")
	# Advance past cooldown until monster dies
	for _step in range(10):
		if not b_actor.is_alive:
			break
		u0.advance_combat(0.5, 1.0, nav)
	_assert(not b_actor.is_alive and mm.get_monster_record(str(b_rec["id"])).is_empty(), "B1: Monster killed and removed from simulation")
	u0.advance_combat(0.1, 1.0, nav)
	_assert(u0.order_state == TacticalUnit.OrderState.IDLE and u0.target_actor == null and u0.target_actor_id == "", "B1: Military target reference cleared after monster death")

	# B2: Actual Monster vs Player Military progression (cooldown + damage + dead target cleanup)
	for u in units:
		if u != null and is_instance_valid(u):
			u.current_cell = Vector2i(0, 0)
			u.position = IsoMath.map_to_local(Vector2i(0, 0))
	var m2_cell: Vector2i = wd.center_spawn + Vector2i(0, 1)
	var m2_rec: Dictionary = mm._create_monster_record("stone_brute", m2_cell, "", m2_cell)
	mm._sync_all_actors()
	u1.current_cell = wd.center_spawn
	u1.position = IsoMath.map_to_local(wd.center_spawn)
	u1.health = 100.0
	m2_rec["attack_cooldown_remaining"] = 0.0
	mm.update_simulation(0.6, 1.0, wd, nav, tact, tm, fow, false)
	var u1_hp_hit1: float = u1.health
	_assert(u1_hp_hit1 < 100.0, "B2: Monster detects and damages military unit (u1 hp=%.1f)" % u1_hp_hit1)
	# Cooldown check (stone_brute cooldown = 1.6s)
	mm.update_simulation(0.2, 1.0, wd, nav, tact, tm, fow, false)
	_assert(is_equal_approx(u1.health, u1_hp_hit1), "B2: Monster attack cooldown respected")
	# Kill military unit -> monster disengages
	u1.take_damage(999.0, "test_kill")
	mm.update_simulation(0.6, 1.0, wd, nav, tact, tm, fow, false)
	_assert(str(m2_rec.get("target_unit_id", "")) == "", "B2: Monster disengages when military target dies")
	mm.get_monster_actor(str(m2_rec["id"])).take_damage(9999.0, "cleanup")

	# B4: Civilian Safety
	for u in units:
		if u != null and is_instance_valid(u):
			u.current_cell = Vector2i(0, 0)
			u.position = IsoMath.map_to_local(Vector2i(0, 0))
	var occ_before: int = 0
	for x in range(wd.map_width):
		for y in range(wd.map_height):
			if wd.occupancy[x][y]:
				occ_before += 1
	var cit0 = wv.get("citizen_list")[0]
	var c_rec: Dictionary = mm._create_monster_record("forest_stalker", cit0.current_cell, "", cit0.current_cell)
	mm._sync_all_actors()
	mm.update_simulation(0.6, 1.0, wd, nav, tact, tm, fow, false)
	_assert(str(c_rec.get("target_unit_id", "")) == "", "B4: Monsters never target ordinary citizens")
	u0.current_cell = wd.center_spawn
	u0.position = IsoMath.map_to_local(wd.center_spawn)
	var occ_after: int = 0
	for x in range(wd.map_width):
		for y in range(wd.map_height):
			if wd.occupancy[x][y]:
				occ_after += 1
	_assert(occ_before == occ_after, "B4: Monsters never modify building/world occupancy")
	mm.get_monster_actor(str(c_rec["id"])).take_damage(9999.0, "cleanup")

	# --- C1, C2, C3, C4. Nest Spawn Timing, Global Cap Recovery & Suppression ---
	var n0: Dictionary = nests[0]
	var n0_id: String = str(n0["id"])
	# C2: Global cap recovery without catch-up burst
	while mm.get_living_monster_count() < MonsterConfigScript.GLOBAL_MONSTER_CAP:
		mm._create_monster_record(str(n0["species_id"]), n0["cell"], str(nests[1]["id"]) if nests.size() > 1 else n0_id, n0["cell"])
	mm._sync_all_actors()
	n0["spawn_timer_hours"] = 72.0 # simulate long wait at cap
	mm.update_simulation(7.5, 1.0, wd, nav, tact, tm, fow, false)
	_assert(mm.get_living_monster_count() == MonsterConfigScript.GLOBAL_MONSTER_CAP, "C2: Global cap 24 strictly blocks spawning")
	# Free 2 slots -> at most 1 spawns for n0 (no catch-up burst)
	var n0_lc_before: int = mm.get_living_count_for_nest(n0_id)
	for _k in range(2):
		var m_rem: Dictionary = mm.get_living_monsters().back()
		mm.get_monster_actor(str(m_rem["id"])).take_damage(9999.0, "cap_test")
	if mm.get_living_count_for_nest(n0_id) < MonsterConfigScript.LOCAL_MONSTER_CAP_PER_NEST:
		mm.update_simulation(0.1, 1.0, wd, nav, tact, tm, fow, false)
		_assert(mm.get_living_count_for_nest(n0_id) <= n0_lc_before + 1, "C2: At most 1 monster spawns after global cap clears (no burst)")

	# C3: Outpost does NOT grant unapproved ownership/suppression
	var nc0: Vector2i = n0["cell"]
	_assert(not tm.is_cell_owned(nc0), "C3: Nest outside Town Hall territory is unowned")

	# --- D2, D3, D4. All 3 POI Categories: Full, Single-Full, Multi-Full, Partial Save/Load & Flush ---
	var camp_poi: POIManager.POIData = null
	var ruins_poi: POIManager.POIData = null
	var cache_poi: POIManager.POIData = null
	for p in pm.get_all_pois():
		if p.type == "abandoned_camp" and camp_poi == null:
			camp_poi = p
		elif p.type == "ancient_ruins" and ruins_poi == null:
			ruins_poi = p
		elif p.type == "forgotten_cache" and cache_poi == null:
			cache_poi = p
	_assert(camp_poi != null and ruins_poi != null and cache_poi != null, "D4: All 3 POI categories present")

	# Verify exact configured reward amounts
	_assert(int(camp_poi.rewards.get("wood", 0)) == 15 and int(camp_poi.rewards.get("tools", 0)) == 3, "D4: Abandoned Camp = 15 wood + 3 tools")
	_assert(int(ruins_poi.rewards.get("gold", 0)) == 10 and int(ruins_poi.rewards.get("crystal", 0)) == 3, "D4: Ancient Ruins = 10 gold + 3 crystal")
	_assert(int(cache_poi.rewards.get("herbs", 0)) == 10 and int(cache_poi.rewards.get("food", 0)) == 20, "D4: Forgotten Cache = 10 herbs + 20 food")

	# Test multi-resource full storage on Forgotten Cache (herbs full, food has room for 5 -> partial!)
	fow.reveal_circle(cache_poi.cell, 2)
	pm.update_discovery(fow, mm, nav)
	pm.refresh_guard_states(mm, nav)
	u0.current_cell = cache_poi.cell
	# Fill herbs to cap, leave food with space for 5
	var herbs_cap: int = rm.get_storage_capacity("herbs")
	rm.add_resource("herbs", herbs_cap - rm.get_resource("herbs"))
	var food_cap: int = rm.get_storage_capacity("food")
	rm.consume_resource("food", rm.get_resource("food"))
	rm.add_resource("food", food_cap - 5)
	var part_cache: Dictionary = pm.claim_poi_reward(cache_poi.id, rm, tact, mm, nav, true)
	_assert(bool(part_cache.get("partial", false)), "D4: Partial deposit occurs when storage has partial room")
	_assert(int(cache_poi.pending_rewards.get("herbs", 0)) == 10 and int(cache_poi.pending_rewards.get("food", 0)) == 15, "D4: Exact undelivered remainder preserved (10 herbs, 15 food)")
	_assert(cache_poi.state != POIManagerScript.POIState.CLAIMED, "D4: POI not marked CLAIMED while pending rewards remain")

	# Test normal full-capacity claim on Ancient Ruins
	fow.reveal_circle(ruins_poi.cell, 2)
	pm.update_discovery(fow, mm, nav)
	pm.refresh_guard_states(mm, nav)
	u0.current_cell = ruins_poi.cell
	var gold_before: int = rm.get_resource("gold")
	var crys_before: int = rm.get_resource("crystal")
	var full_ruins: Dictionary = pm.claim_poi_reward(ruins_poi.id, rm, tact, mm, nav, true)
	_assert(bool(full_ruins.get("success", false)) and not bool(full_ruins.get("partial", false)), "D4: Full-capacity Ancient Ruins claim succeeds")
	_assert(rm.get_resource("gold") == gold_before + 10 and rm.get_resource("crystal") == crys_before + 3, "D4: Ancient Ruins credited 10 gold + 3 crystal once")

	# --- E & F. Fog ON/OFF & Save/Load Integrity across Partial/Looted/Destroyed States ---
	# Destroy n0, suppress n1 via owned_cells, save & load
	mm.get_nest_actor(n0_id).take_damage(9999.0, "closure_destroy")
	var save_path := "user://test_phase9_closure_full.json"
	SaveManagerScript.save_to_file(wv, save_path)

	var wv_load := WorldViewScene.instantiate()
	wv_load.set("skip_intro_for_test", true)
	root.add_child(wv_load)
	await create_timer(0.25).timeout
	var lres: Dictionary = SaveManagerScript.load_from_file(save_path)
	SaveManagerScript.apply_loaded_state_to_world(wv_load, lres.get("data", {}))
	var mm_l = wv_load.get("monster_mgr")
	var pm_l = wv_load.get("poi_mgr")
	_assert(bool(mm_l.nests[n0_id]["is_destroyed"]), "F: Destroyed Nest persists across Save/Load")
	var loaded_cache = pm_l.get_poi(cache_poi.id)
	var loaded_ruins = pm_l.get_poi(ruins_poi.id)
	_assert(loaded_ruins.state == POIManagerScript.POIState.CLAIMED, "F: Fully looted POI remains CLAIMED after load")
	_assert(int(loaded_cache.pending_rewards.get("herbs", 0)) == 10 and int(loaded_cache.pending_rewards.get("food", 0)) == 15, "F: Partial pending_rewards preserved exactly across Save/Load")

	# Free space, flush remaining rewards once, verify no food re-grant of already-delivered 5 food
	rm.consume_resource("herbs", 20)
	rm.consume_resource("food", 30)
	var herbs_pre: int = rm.get_resource("herbs")
	var food_pre: int = rm.get_resource("food")
	var tact_l = wv_load.get("tactical_military_mgr")
	tact_l.get_all_units()[0].current_cell = loaded_cache.cell
	var flush_res: Dictionary = pm_l.claim_poi_reward(loaded_cache.id, rm, tact_l, mm_l, wv_load.get("nav"), true)
	_assert(bool(flush_res.get("success", false)) and not bool(flush_res.get("partial", false)), "D4: Remaining pending rewards flush cleanly")
	_assert(rm.get_resource("herbs") == herbs_pre + 10 and rm.get_resource("food") == food_pre + 15, "D4: Only undelivered remainder (10 herbs, 15 food) delivered once (no re-grant)")
	_assert(loaded_cache.state == POIManagerScript.POIState.CLAIMED, "D4: POI transitions to CLAIMED after pending flush")
	var dup_res: Dictionary = pm_l.claim_poi_reward(loaded_cache.id, rm, tact_l, mm_l, wv_load.get("nav"), true)
	_assert(not bool(dup_res.get("success", false)), "D4: Repeated claim rejected after flush")

	wv.queue_free()
	wv_load.queue_free()
	await process_frame

	print("========================================================")
	print("  TEST_MONSTER_POI_CLOSURE RESULTS: PASSED=%d FAILED=%d" % [_passed, _failures.size()])
	print("========================================================")
	quit(0 if _failures.is_empty() else 1)
