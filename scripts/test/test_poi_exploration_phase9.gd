extends SceneTree

const WorldViewScene := preload("res://scenes/world/world_view.tscn")
const SaveManagerScript := preload("res://scripts/persistence/save_manager.gd")
const POIManagerScript := preload("res://scripts/world/poi_manager.gd")
const MonsterConfigScript := preload("res://scripts/world/monster_config.gd")

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
	var pm = wv.get("poi_mgr")
	var mm = wv.get("monster_mgr")
	var fow: FogOfWar = wv.get("fog_of_war")
	var nav: GridNavigation = wv.get("nav")
	var tact = wv.get("tactical_military_mgr")
	var rm = root.get_node_or_null("ResourceManager")

	var pois: Array = pm.get_all_pois()
	_assert(pois.size() >= 3, "1.1 Phase 9 POIs generated (got %d)" % pois.size())
	var types_seen := {}
	for p in pois:
		types_seen[p.type] = true
		_assert(p.state == POIManagerScript.POIState.UNDISCOVERED, "1.2 POI %s starts UNDISCOVERED" % p.id)
	_assert(types_seen.has("abandoned_camp") and types_seen.has("ancient_ruins") and types_seen.has("forgotten_cache"), "1.3 All 3 Phase 9 POI categories generated")

	# Pick a POI outside starter fog
	var test_poi: POIManager.POIData = null
	for p in pois:
		if not fow.is_explored(p.cell):
			test_poi = p
			break
	_assert(test_poi != null, "1.4 Found unexplored POI for Fog/Discovery tests")

	# Fog OFF must NOT mark POI discovered, cleared, or claimed
	wv.set_debug_fog_disabled(true)
	pm.update_discovery(fow, mm, nav)
	_assert(test_poi.state == POIManagerScript.POIState.UNDISCOVERED, "2.1 Fog OFF does NOT mark POI discovered")
	var dbg_insp: Dictionary = wv.inspect_cell_in_debug_mode(test_poi.cell)
	_assert(dbg_insp.get("category") == "poi" and bool(dbg_insp.get("is_debug_inspect", false)), "2.2 Fog OFF reveals POI for read-only debug inspection")

	# Live monsters in UNEXPLORED vs EXPLORED vs VISIBLE under Fog ON/OFF
	var m_list: Array = mm.get_living_monsters()
	_assert(not m_list.is_empty(), "2.3 Living monsters exist for Fog tests")
	var m0: Dictionary = m_list[0]
	var m0_cell: Vector2i = m0["cell"]
	var m0_actor: Node2D = mm.get_monster_actor(str(m0["id"]))
	_assert(m0_actor.visible, "2.4 Fog OFF reveals live monster actor")
	wv.set_debug_fog_disabled(false)
	_assert(not fow.is_explored(test_poi.cell), "2.5 Fog toggle never mutates real FogOfWar exploration data")
	if not fow.is_visible(m0_cell):
		_assert(not m0_actor.visible, "2.6 Fog ON hides live monster outside VISIBLE cells")

	# Real visibility reveals POI & Monster
	fow.reveal_circle(test_poi.cell, 2)
	pm.update_discovery(fow, mm, nav)
	_assert(test_poi.state != POIManagerScript.POIState.UNDISCOVERED, "3.1 Real visibility discovers POI")
	fow.reveal_circle(m0_cell, 2)
	mm.refresh_visibility(fow, false)
	_assert(m0_actor.visible, "3.2 Real visibility reveals live monster in VISIBLE cell")

	# Guarded vs Cleared & Unrelated Monsters
	# Place a temporary monster at test_poi.cell (guard radius <= 5)
	var guard_rec: Dictionary = mm._create_monster_record("forest_stalker", test_poi.cell, "", test_poi.cell)
	mm._sync_all_actors()
	pm.refresh_guard_states(mm, nav)
	_assert(test_poi.state == POIManagerScript.POIState.GUARDED, "3.3 Nearby monster within 5 path cells marks POI GUARDED")

	# Attempt claim while guarded -> rejected
	var pa_mgr = wv.get("player_army_mgr")
	pa_mgr.set("soldier_count", 2)
	tact.sync_with_player_army()
	var u0: TacticalUnit = tact.get_all_units()[0]
	u0.current_cell = test_poi.cell
	var fail_guard: Dictionary = pm.claim_poi_reward(test_poi.id, rm, tact, mm, nav, true)
	_assert(not bool(fail_guard.get("success", false)), "3.4 Guarded POI rejects claim")

	# Kill guard -> CLEARED (unrelated distant monsters do not block)
	var g_actor: Node2D = mm.get_monster_actor(str(guard_rec["id"]))
	g_actor.take_damage(999.0, u0.unit_id)
	pm.refresh_guard_states(mm, nav)
	_assert(test_poi.state == POIManagerScript.POIState.CLEARED, "3.5 Defeating local guards transitions POI to CLEARED even while distant monsters exist")

	# Claim without nearby military -> rejected
	u0.current_cell = wd.center_spawn
	var fail_dist: Dictionary = pm.claim_poi_reward(test_poi.id, rm, tact, mm, nav, true)
	_assert(not bool(fail_dist.get("success", false)), "3.6 Claim without nearby military (<= 1 path cell) is rejected")

	# Full storage capacity preserves pending_rewards across Save/Load and delivers once when space freed
	u0.current_cell = test_poi.cell
	var first_res_key: String = str(test_poi.rewards.keys()[0])
	var cap_now: int = rm.get_storage_capacity(first_res_key)
	var cur_now: int = rm.get_resource(first_res_key)
	if cap_now > cur_now:
		rm.add_resource(first_res_key, cap_now - cur_now)
	var partial_res: Dictionary = pm.claim_poi_reward(test_poi.id, rm, tact, mm, nav, true)
	_assert(bool(partial_res.get("partial", false)), "4.1 Full storage triggers partial/pending reward preservation")
	_assert(test_poi.state != POIManagerScript.POIState.CLAIMED and not test_poi.pending_rewards.is_empty(), "4.2 POI with pending rewards is NOT marked CLAIMED yet")
	var expected_pending_amt: int = int(test_poi.pending_rewards.get(first_res_key, 0))
	_assert(expected_pending_amt == int(test_poi.rewards[first_res_key]), "4.3 Pending reward equals exact undeposited remainder")

	# Save/Load preserves pending_rewards
	var save_path := "user://test_phase9_poi_pending.json"
	SaveManagerScript.save_to_file(wv, save_path)
	var wv_load := WorldViewScene.instantiate()
	wv_load.set("skip_intro_for_test", true)
	root.add_child(wv_load)
	await create_timer(0.25).timeout
	var lres: Dictionary = SaveManagerScript.load_from_file(save_path)
	SaveManagerScript.apply_loaded_state_to_world(wv_load, lres.get("data", {}))
	var pm_load = wv_load.get("poi_mgr")
	var loaded_poi = pm_load.get_poi(test_poi.id)
	_assert(loaded_poi != null and int(loaded_poi.pending_rewards.get(first_res_key, 0)) == expected_pending_amt, "4.4 Pending rewards persist through Save/Load")

	# Free space and complete claim -> exact single deposit, repeat claim rejected
	rm.consume_resource(first_res_key, expected_pending_amt)
	var stock_before_flush: int = rm.get_resource(first_res_key)
	var tact_load = wv_load.get("tactical_military_mgr")
	if tact_load.get_all_units().is_empty():
		wv_load.get("player_army_mgr").set("soldier_count", 1)
		tact_load.sync_with_player_army()
	tact_load.get_all_units()[0].current_cell = loaded_poi.cell
	var finish_res: Dictionary = pm_load.claim_poi_reward(loaded_poi.id, rm, tact_load, wv_load.get("monster_mgr"), wv_load.get("nav"), true)
	_assert(bool(finish_res.get("success", false)) and not bool(finish_res.get("partial", false)), "4.5 Pending reward flushes cleanly when space freed")
	_assert(rm.get_resource(first_res_key) == stock_before_flush + expected_pending_amt, "4.6 Remaining reward deposited exactly once")
	_assert(loaded_poi.state == POIManagerScript.POIState.CLAIMED, "4.7 POI transitions to CLAIMED/LOOTED after all rewards delivered")
	var dup_res: Dictionary = pm_load.claim_poi_reward(loaded_poi.id, rm, tact_load, wv_load.get("monster_mgr"), wv_load.get("nav"), true)
	_assert(not bool(dup_res.get("success", false)), "4.8 Already looted POI rejects duplicate claim")

	wv.queue_free()
	wv_load.queue_free()
	await process_frame

	print("========================================================")
	print("  TEST_POI_EXPLORATION_PHASE9 RESULTS: PASSED=%d FAILED=%d" % [_passed, _failures.size()])
	print("========================================================")
	quit(0 if _failures.is_empty() else 1)
