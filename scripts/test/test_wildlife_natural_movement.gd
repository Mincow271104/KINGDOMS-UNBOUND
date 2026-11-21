extends SceneTree

const WildlifeConfig = preload("res://scripts/world/wildlife_config.gd")
const WildlifeManager = preload("res://scripts/world/wildlife_manager.gd")
const WildlifeActor = preload("res://scripts/world/wildlife_actor.gd")
const FogOfWarScript = preload("res://scripts/world/fog_of_war.gd")

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
	# --- 1. Species config completeness for all 6 species ---
	var expected_species := ["bird", "frog", "rabbit", "deer", "wild_boar", "mountain_goat"]
	for sp in expected_species:
		var def: Dictionary = WildlifeConfig.get_species_def(sp)
		_assert(not def.is_empty(), "Case 1a: Species %s exists" % sp)
		_assert(def.has("gait_type") and def.has("burst_min") and def.has("burst_max"), "Case 1b: Species %s has gait & burst config" % sp)
		_assert(def.has("turn_persistence") and def.has("wander_radius") and def.has("hop_height"), "Case 1c: Species %s has turn/wander/hop config" % sp)
		_assert(int(def["burst_max"]) >= int(def["burst_min"]) and int(def["burst_min"]) >= 1, "Case 1d: Species %s valid burst range" % sp)

	_assert(int(WildlifeConfig.get_species_def("bird")["gait_type"]) == WildlifeConfig.GaitType.FLUTTER, "Case 1e: Bird uses FLUTTER gait")
	_assert(int(WildlifeConfig.get_species_def("frog")["gait_type"]) == WildlifeConfig.GaitType.HOP, "Case 1f: Frog uses HOP gait")
	_assert(int(WildlifeConfig.get_species_def("rabbit")["gait_type"]) == WildlifeConfig.GaitType.HOP, "Case 1g: Rabbit uses HOP gait")
	_assert(int(WildlifeConfig.get_species_def("deer")["gait_type"]) == WildlifeConfig.GaitType.WALK, "Case 1h: Deer uses WALK gait")
	_assert(int(WildlifeConfig.get_species_def("wild_boar")["gait_type"]) == WildlifeConfig.GaitType.TROT, "Case 1i: Boar uses TROT gait")
	_assert(int(WildlifeConfig.get_species_def("mountain_goat")["gait_type"]) == WildlifeConfig.GaitType.WALK, "Case 1j: Goat uses WALK gait")

	# --- 2. Spawn all 6 species & check desynchronization ---
	var wd := WorldGenerator.generate(12345, WorldGenerator.LATEST_GENERATOR_VERSION, 128, 128)
	var nav := GridNavigation.new(wd)
	var mgr := WildlifeManager.new()
	mgr.generate_initial_population(wd, nav)
	var animals := mgr.get_all_animals()
	_assert(animals.size() > 0 and animals.size() <= WildlifeConfig.MAX_TOTAL_POPULATION, "Case 2a: Population spawned within cap")

	var species_seen: Dictionary = {}
	var jitters: Dictionary = {}
	var phases: Dictionary = {}
	var timers: Dictionary = {}
	for rec in animals:
		species_seen[rec["species_id"]] = true
		jitters[snappedf(float(rec.get("speed_jitter", 1.0)), 0.001)] = true
		phases[snappedf(float(rec.get("anim_phase", 0.0)), 0.01)] = true
		timers[snappedf(float(rec.get("state_timer", 0.0)), 0.01)] = true

	for sp in expected_species:
		_assert(species_seen.has(sp), "Case 2b: Species %s spawned on seed 12345" % sp)
	_assert(jitters.size() > 3, "Case 2c: Population has varied speed_jitter (desynchronized)")
	_assert(phases.size() > 3, "Case 2d: Population has varied anim_phase (desynchronized)")
	_assert(timers.size() > 3, "Case 2e: Population has staggered initial state_timer")

	# --- 3. Visual interpolation, gait offset, turn smoothing & idle bobbing ---
	var root := Node2D.new()
	get_root().add_child(root)
	var actor := WildlifeActor.new()
	actor.setup("test_rabbit", "rabbit", Vector2i(10, 10))
	root.add_child(actor)

	var p0: Vector2 = IsoMath.map_to_local(Vector2i(10, 10))
	var p1: Vector2 = IsoMath.map_to_local(Vector2i(11, 10))
	var mid_pos: Vector2 = p0.lerp(p1, 0.5)
	actor.sync_visual(mid_pos, WildlifeConfig.BehaviorState.WANDERING, false, 0.5, true, 1.0, 0.5)
	_assert(actor.position.distance_to(mid_pos) < 0.01, "Case 3a: Actor position interpolates smoothly between cells")
	_assert(actor._sprite.offset.y < -5.0, "Case 3b: Rabbit HOP gait lifts sprite offset.y mid-hop")
	_assert(absf(actor._sprite.scale.x - lerpf(0.35, 1.0, 0.5)) < 0.01, "Case 3c: Turn blend smoothly scales sprite.x")

	actor.sync_visual(p0, WildlifeConfig.BehaviorState.IDLE, false, 0.0, false, 0.7, 1.0)
	var idle_off_a: float = actor._sprite.offset.y
	actor.sync_visual(p0, WildlifeConfig.BehaviorState.IDLE, false, 0.0, false, 1.4, 1.0)
	var idle_off_b: float = actor._sprite.offset.y
	_assert(not is_equal_approx(idle_off_a, idle_off_b), "Case 3d: IDLE breathing/bobbing animates offset.y over time")

	actor.sync_visual(p0, WildlifeConfig.BehaviorState.BEING_HUNTED, false, 0.0, false, 1.4, 1.0)
	_assert(is_equal_approx(actor._sprite.offset.y, -5.0), "Case 3e: BEING_HUNTED stops idle bobbing (base offset -5.0)")

	# --- 4. Multi-step burst movement, anti-oscillation & biome/walkability invariants ---
	mgr._wildlife_container = root
	mgr.spawn_all_actors()
	var saw_multi_step_continue: bool = false
	var saw_burst_finish_to_idle: bool = false
	var saw_mid_cell_interpolation: bool = false
	var prev_burst: Dictionary = {}
	for rec in animals:
		prev_burst[rec["id"]] = int(rec.get("burst_remaining", 0))

	var bad_biome := 0
	var bad_walkable := 0
	for _tick in range(180):
		mgr.advance_simulation(0.1, 1.0, wd, nav, [], [])
		for rec in mgr.get_all_animals():
			var aid: String = rec["id"]
			var st: int = int(rec["state"])
			var b_now: int = int(rec.get("burst_remaining", 0))
			var b_prev: int = int(prev_burst.get(aid, 0))
			if st == WildlifeConfig.BehaviorState.WANDERING and b_prev > b_now and b_now > 0:
				saw_multi_step_continue = true
			if b_prev > 0 and b_now == 0 and st == WildlifeConfig.BehaviorState.IDLE:
				saw_burst_finish_to_idle = true
			prev_burst[aid] = b_now

			var mp: float = float(rec.get("move_progress", 0.0))
			if mp > 0.05 and mp < 0.95 and mgr.actors_by_id.has(aid):
				var a_node: WildlifeActor = mgr.actors_by_id[aid]
				var w_from: Vector2 = IsoMath.map_to_local(rec["cell"])
				var w_to: Vector2 = IsoMath.map_to_local(rec["target_cell"])
				if a_node.position.distance_to(w_from) > 1.0 and a_node.position.distance_to(w_to) > 1.0:
					saw_mid_cell_interpolation = true

			var c: Vector2i = rec["cell"]
			var tc: Vector2i = rec["target_cell"]
			if not nav.is_cell_walkable(c) or not nav.is_cell_walkable(tc):
				bad_walkable += 1
			if not WildlifeConfig.is_biome_allowed(rec["species_id"], wd.get_biome(c)):
				bad_biome += 1

	_assert(saw_multi_step_continue, "Case 4a: Burst movement continues across multiple cells without stopping")
	_assert(saw_burst_finish_to_idle, "Case 4b: Burst completion transitions cleanly to IDLE")
	_assert(saw_mid_cell_interpolation, "Case 4c: Actors visually interpolate mid-cell during movement")
	_assert(bad_walkable == 0, "Case 4d: All cells and targets stay walkable (bad=%d)" % bad_walkable)
	_assert(bad_biome == 0, "Case 4e: All animals remain in allowed biomes (bad=%d)" % bad_biome)

	# --- 5. Anti-oscillation check on _pick_wander_cell ---
	var test_prey: Dictionary = {}
	for rec in mgr.get_all_animals():
		if rec["species_id"] == "deer" or rec["species_id"] == "rabbit":
			test_prey = rec
			break
	_assert(not test_prey.is_empty(), "Case 5a: Found prey animal for anti-oscillation & flee check")
	if not test_prey.is_empty():
		var c_now: Vector2i = test_prey["cell"]
		var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		var valid_neighbors: Array[Vector2i] = []
		for d in dirs:
			var nc: Vector2i = c_now + d
			if wd.is_in_bounds(nc) and nav.is_cell_walkable(nc) and WildlifeConfig.is_biome_allowed(test_prey["species_id"], wd.get_biome(nc)):
				valid_neighbors.append(nc)
		if valid_neighbors.size() >= 2:
			test_prey["prev_cell"] = valid_neighbors[0]
			test_prey["last_dir"] = c_now - valid_neighbors[0]
			var backtrack_count := 0
			for _i in range(12):
				var picked: Vector2i = mgr._pick_wander_cell(test_prey, wd, nav)
				if picked == valid_neighbors[0]:
					backtrack_count += 1
			_assert(backtrack_count == 0, "Case 5b: _pick_wander_cell avoids immediate prev_cell when alternatives exist")

		# --- 6. Fleeing behavior ---
		test_prey["state"] = WildlifeConfig.BehaviorState.IDLE
		test_prey["target_cell"] = test_prey["cell"]
		var fake_unit := {"current_cell": test_prey["cell"] + Vector2i(1, 0), "is_alive": true}
		mgr._threat_scan_accum = WildlifeManager.THREAT_SCAN_INTERVAL
		mgr.advance_simulation(0.05, 1.0, wd, nav, [], [fake_unit])
		_assert(int(test_prey["state"]) == WildlifeConfig.BehaviorState.FLEEING, "Case 6: Prey flees from nearby unit")

	# --- 7. Fog of War visibility follows logical cell ---
	var fog := FogOfWarScript.new(wd.map_width, wd.map_height)
	mgr.refresh_visibility(fog, true)
	var all_vis_debug := true
	for aid in mgr.actors_by_id:
		if not (mgr.actors_by_id[aid] as WildlifeActor).visible:
			all_vis_debug = false
			break
	_assert(all_vis_debug, "Case 7a: debug_fog_disabled makes all wildlife actors visible")

	mgr.refresh_visibility(fog, false)
	var all_hidden_unexplored := true
	for rec in mgr.get_all_animals():
		if fog.get_state(rec["cell"]) != FogOfWar.State.VISIBLE:
			if mgr.actors_by_id.has(rec["id"]) and (mgr.actors_by_id[rec["id"]] as WildlifeActor).visible:
				all_hidden_unexplored = false
				break
	_assert(all_hidden_unexplored, "Case 7b: Unexplored wildlife actors stay hidden under Fog of War")

	# --- 8. Hunting reservation & death ---
	var hunt_target := ""
	for rec in mgr.get_all_animals():
		if rec["species_id"] == "rabbit" or rec["species_id"] == "deer":
			hunt_target = rec["id"]
			break
	_assert(hunt_target != "", "Case 8a: Found huntable animal")
	if hunt_target != "":
		var count_before := mgr.get_all_animals().size()
		_assert(mgr.reserve_animal(hunt_target, "hunter_test_1"), "Case 8b: reserve_animal succeeds")
		_assert(mgr.begin_hunting_interaction(hunt_target, "hunter_test_1"), "Case 8c: begin_hunting_interaction transitions to BEING_HUNTED")
		var rec_h := mgr.get_animal_by_id(hunt_target)
		_assert(int(rec_h["state"]) == WildlifeConfig.BehaviorState.BEING_HUNTED, "Case 8d: Animal is in BEING_HUNTED state")
		var loot := mgr.complete_hunt(hunt_target, "hunter_test_1")
		_assert(bool(loot.get("success", false)), "Case 8e: complete_hunt succeeds")
		_assert(mgr.get_all_animals().size() == count_before - 1, "Case 8f: complete_hunt removes dead animal")

	# --- 9. Save/Load roundtrip ---
	var saved := mgr.serialize()
	var mgr_loaded := WildlifeManager.new()
	mgr_loaded.deserialize_or_init(saved, wd, nav)
	_assert(mgr_loaded.get_all_animals().size() == mgr.get_all_animals().size(), "Case 9a: Save/Load preserves animal count")
	var load_fields_ok := true
	for rec in mgr_loaded.get_all_animals():
		if not rec.has("prev_cell") or not rec.has("speed_jitter") or not rec.has("anim_phase") or not rec.has("turn_blend"):
			load_fields_ok = false
			break
	_assert(load_fields_ok, "Case 9b: Loaded animals initialize movement presentation fields")
	mgr_loaded.advance_simulation(0.1, 1.0, wd, nav, [], [])
	_assert(mgr_loaded.get_all_animals().size() == mgr.get_all_animals().size(), "Case 9c: Loaded animals simulate cleanly")

	# --- 9d-9j. Save/Load D-01 regression: WANDERING / FLEEING / BEING_HUNTED normalization ---
	var bird_rec: Dictionary = {}
	var rabbit_rec: Dictionary = {}
	var deer_rec: Dictionary = {}
	for rec in mgr_loaded.get_all_animals():
		if rec["species_id"] == "bird" and bird_rec.is_empty():
			bird_rec = rec
		elif rec["species_id"] == "rabbit" and rabbit_rec.is_empty():
			rabbit_rec = rec
		elif rec["species_id"] == "deer" and deer_rec.is_empty():
			deer_rec = rec

	_assert(not bird_rec.is_empty() and not rabbit_rec.is_empty() and not deer_rec.is_empty(), "Case 9d: Found bird, rabbit, deer for Save/Load state regression")
	if not bird_rec.is_empty() and not rabbit_rec.is_empty() and not deer_rec.is_empty():
		var bird_id: String = bird_rec["id"]
		var rabbit_id: String = rabbit_rec["id"]
		var deer_id: String = deer_rec["id"]
		var bird_home_cell: Vector2i = bird_rec["cell"]
		# 1) Bird in WANDERING mid-step
		bird_rec["state"] = WildlifeConfig.BehaviorState.WANDERING
		bird_rec["target_cell"] = bird_rec["cell"] + Vector2i(1, 0)
		bird_rec["move_progress"] = 0.45
		# 2) Rabbit in FLEEING
		rabbit_rec["state"] = WildlifeConfig.BehaviorState.FLEEING
		rabbit_rec["threat_cell"] = rabbit_rec["cell"] + Vector2i(1, 0)
		# 3) Deer in BEING_HUNTED
		deer_rec["state"] = WildlifeConfig.BehaviorState.BEING_HUNTED

		var saved_states := mgr_loaded.serialize()
		var mgr_reg := WildlifeManager.new()
		mgr_reg.deserialize_or_init(saved_states, wd, nav)

		var loaded_bird := mgr_reg.get_animal_by_id(bird_id)
		var loaded_rabbit := mgr_reg.get_animal_by_id(rabbit_id)
		var loaded_deer := mgr_reg.get_animal_by_id(deer_id)

		_assert(int(loaded_bird["state"]) == WildlifeConfig.BehaviorState.IDLE and loaded_bird["target_cell"] == loaded_bird["cell"] and is_equal_approx(float(loaded_bird["move_progress"]), 0.0), "Case 9e: Mid-step WANDERING normalizes to stationary IDLE on Save/Load")
		_assert(int(loaded_rabbit["state"]) == WildlifeConfig.BehaviorState.IDLE and loaded_rabbit["threat_cell"] == Vector2i(-1, -1), "Case 9f: FLEEING normalizes to IDLE with cleared threat_cell on Save/Load")
		_assert(int(loaded_deer["state"]) == WildlifeConfig.BehaviorState.IDLE, "Case 9g: BEING_HUNTED normalization to IDLE preserved")

		# Legacy/direct payload with state == WANDERING at cell center & FLEEING must also normalize in deserialize_or_init
		var raw_payload := mgr_loaded.serialize()
		for item in raw_payload["animals"]:
			if item["id"] == bird_id:
				item["state"] = WildlifeConfig.BehaviorState.WANDERING
			elif item["id"] == rabbit_id:
				item["state"] = WildlifeConfig.BehaviorState.FLEEING
		var mgr_legacy := WildlifeManager.new()
		mgr_legacy.deserialize_or_init(raw_payload, wd, nav)
		var leg_bird := mgr_legacy.get_animal_by_id(bird_id)
		var leg_rabbit := mgr_legacy.get_animal_by_id(rabbit_id)
		_assert(int(leg_bird["state"]) == WildlifeConfig.BehaviorState.IDLE, "Case 9h: Direct WANDERING payload normalizes to IDLE on deserialize")
		_assert(int(leg_rabbit["state"]) == WildlifeConfig.BehaviorState.IDLE and leg_rabbit["threat_cell"] == Vector2i(-1, -1), "Case 9i: Direct FLEEING payload normalizes to IDLE on deserialize")

		# Advance simulation so loaded bird resumes normal wandering (not stuck)
		var bird_resumed := false
		for _step in range(80):
			mgr_reg.advance_simulation(0.1, 1.0, wd, nav, [], [])
			if loaded_bird["cell"] != bird_home_cell or loaded_bird["target_cell"] != loaded_bird["cell"]:
				bird_resumed = true
				break
		_assert(bird_resumed, "Case 9j: Normalized WANDERING bird resumes normal movement after load")

		# Normal fleeing still works when a valid threat exists after load
		var threat_unit := {"current_cell": loaded_rabbit["cell"] + Vector2i(1, 0), "is_alive": true}
		mgr_reg._threat_scan_accum = WildlifeManager.THREAT_SCAN_INTERVAL
		mgr_reg.advance_simulation(0.05, 1.0, wd, nav, [], [threat_unit])
		_assert(int(loaded_rabbit["state"]) == WildlifeConfig.BehaviorState.FLEEING and loaded_rabbit["threat_cell"] == threat_unit["current_cell"], "Case 9k: Normal fleeing works with valid threat after load")

		# All 6 species remain valid after Save/Load
		var sp_after: Dictionary = {}
		for rec in mgr_reg.get_all_animals():
			sp_after[rec["species_id"]] = true
		var all_six_ok := true
		for sp in expected_species:
			if not sp_after.has(sp):
				all_six_ok = false
				break
		_assert(all_six_ok, "Case 9l: All 6 species remain valid after Save/Load")

	root.queue_free()
	print("[test_wildlife_natural_movement] Passed: %d | Failed: %d" % [_passed, _failures.size()])
	if _failures.is_empty():
		quit(0)
	else:
		quit(1)
