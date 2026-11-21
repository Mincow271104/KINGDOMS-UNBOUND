extends SceneTree

const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const GridNavigationScript = preload("res://scripts/navigation/grid_navigation.gd")
const FogOfWarScript = preload("res://scripts/world/fog_of_war.gd")
const WildlifeConfigScript = preload("res://scripts/world/wildlife_config.gd")
const WildlifeManagerScript = preload("res://scripts/world/wildlife_manager.gd")
const WildlifeActorScript = preload("res://scripts/world/wildlife_actor.gd")
const EntityVisualRegistryScript = preload("res://scripts/world/entity_visual_registry.gd")

const WARMUP_FRAMES: int = 30
const PURE_SYNC_FRAMES: int = 300
const FULL_SIM_FRAMES: int = 120
const SIM_DT: float = 0.016

var _passed: int = 0
var _failed: int = 0

func _init() -> void:
	call_deferred("_run")

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("  [FAIL] " + msg)

func _percentile(sorted_arr: Array[float], q: float) -> float:
	if sorted_arr.is_empty():
		return 0.0
	var idx := clampi(int(ceil(q * float(sorted_arr.size()))) - 1, 0, sorted_arr.size() - 1)
	return sorted_arr[idx]

func _build_fixture(count: int, mode: String, fog_visible: bool) -> Dictionary:
	var wd = WorldGeneratorScript.generate(12345, WorldGeneratorScript.LATEST_GENERATOR_VERSION, 128, 128)
	var nav := GridNavigationScript.new(wd)
	var fow := FogOfWarScript.new(128, 128)
	var cont := Node2D.new()
	root.add_child(cont)

	var mgr := WildlifeManagerScript.new()
	mgr.set_container(cont)
	mgr._rng.seed = 600001

	var walkable: Array[Vector2i] = []
	for y in range(18, 112, 2):
		for x in range(18, 112, 2):
			var c := Vector2i(x, y)
			if nav.is_cell_walkable(c) and not wd.occupancy[x][y]:
				walkable.append(c)
				if walkable.size() >= 80:
					break
		if walkable.size() >= 80:
			break

	var sp_list: Array[String] = WildlifeConfigScript.SPECIES_ORDER
	var mixed_states: Array[int] = [
		WildlifeConfigScript.BehaviorState.IDLE,
		WildlifeConfigScript.BehaviorState.WANDERING,
		WildlifeConfigScript.BehaviorState.FLEEING,
		WildlifeConfigScript.BehaviorState.DEFENSIVE_DISPLAY,
	]

	for i in range(count):
		var sp: String = sp_list[i % sp_list.size()]
		var spec := WildlifeConfigScript.get_species_def(sp)
		var cat := int(spec.get("category", 0))
		var c: Vector2i = walkable[i % walkable.size()]
		var rec: Dictionary = mgr._make_animal_record("bench_wl_%d" % i, sp, cat, c)
		var st: int = WildlifeConfigScript.BehaviorState.IDLE
		match mode:
			"idle":
				st = WildlifeConfigScript.BehaviorState.IDLE
				rec["state_timer"] = 100.0
			"wandering":
				st = WildlifeConfigScript.BehaviorState.WANDERING
				rec["target_cell"] = walkable[(i + 1) % walkable.size()]
				rec["move_progress"] = 0.5
				rec["burst_remaining"] = 5
			"fleeing":
				st = WildlifeConfigScript.BehaviorState.FLEEING
				rec["target_cell"] = walkable[(i + 1) % walkable.size()]
				rec["move_progress"] = 0.5
				rec["state_timer"] = 100.0
			"defensive":
				st = WildlifeConfigScript.BehaviorState.DEFENSIVE_DISPLAY if cat == WildlifeConfigScript.Category.DEFENSIVE else WildlifeConfigScript.BehaviorState.IDLE
				rec["state_timer"] = 100.0
			_:
				st = mixed_states[i % mixed_states.size()]
				if st == WildlifeConfigScript.BehaviorState.DEFENSIVE_DISPLAY and cat != WildlifeConfigScript.Category.DEFENSIVE:
					st = WildlifeConfigScript.BehaviorState.IDLE
				if st == WildlifeConfigScript.BehaviorState.FLEEING and cat == WildlifeConfigScript.Category.AMBIENT:
					st = WildlifeConfigScript.BehaviorState.WANDERING
				if st == WildlifeConfigScript.BehaviorState.WANDERING or st == WildlifeConfigScript.BehaviorState.FLEEING:
					rec["target_cell"] = walkable[(i + 1) % walkable.size()]
					rec["move_progress"] = 0.5
					rec["burst_remaining"] = 3
				rec["state_timer"] = 50.0
		rec["state"] = st
		rec["flip_h"] = (i % 2 == 1)
		mgr.animals.append(rec)
		mgr.animals_by_id[rec["id"]] = rec
		if fog_visible:
			fow.set_state(c, FogOfWarScript.State.VISIBLE)
		else:
			fow.set_state(c, FogOfWarScript.State.UNEXPLORED)

	mgr.spawn_all_actors()
	mgr.refresh_visibility(fow, false)

	return {"wd": wd, "nav": nav, "fow": fow, "cont": cont, "mgr": mgr}

func _bench_pure_actor_sync(fix: Dictionary) -> Dictionary:
	var mgr = fix["mgr"]
	var animals: Array = mgr.animals
	var actors: Array = []
	for rec in animals:
		actors.append(mgr.actors_by_id.get(str(rec["id"])))

	var t_sim := 0.0
	for _w in range(WARMUP_FRAMES):
		t_sim += SIM_DT
		for i in range(animals.size()):
			var rec: Dictionary = animals[i]
			var a: WildlifeActorScript = actors[i]
			var p0 := IsoMath.map_to_local(rec["cell"])
			var p1 := IsoMath.map_to_local(rec["target_cell"])
			var prog := float(rec["move_progress"])
			a.sync_visual(p0.lerp(p1, prog), int(rec["state"]), bool(rec["flip_h"]), prog, rec["target_cell"] != rec["cell"], t_sim + float(rec["anim_phase"]), 1.0)

	var samples: Array[float] = []
	samples.resize(PURE_SYNC_FRAMES)
	var total_ms := 0.0
	for f in range(PURE_SYNC_FRAMES):
		t_sim += SIM_DT
		var t0 := Time.get_ticks_usec()
		for i in range(animals.size()):
			var rec: Dictionary = animals[i]
			var a: WildlifeActorScript = actors[i]
			var p0 := IsoMath.map_to_local(rec["cell"])
			var p1 := IsoMath.map_to_local(rec["target_cell"])
			var prog := float(rec["move_progress"])
			a.sync_visual(p0.lerp(p1, prog), int(rec["state"]), bool(rec["flip_h"]), prog, rec["target_cell"] != rec["cell"], t_sim + float(rec["anim_phase"]), 1.0)
		var dt_ms := float(Time.get_ticks_usec() - t0) / 1000.0
		samples[f] = dt_ms
		total_ms += dt_ms

	var sorted := samples.duplicate()
	sorted.sort()
	return {"avg_ms": total_ms / float(PURE_SYNC_FRAMES), "p95_ms": _percentile(sorted, 0.95)}

func _bench_full_advance(fix: Dictionary) -> Dictionary:
	var mgr = fix["mgr"]
	var wd = fix["wd"]
	var nav = fix["nav"]

	for _w in range(WARMUP_FRAMES):
		mgr.advance_simulation(SIM_DT, 1.0, wd, nav, [], [])

	var samples: Array[float] = []
	samples.resize(FULL_SIM_FRAMES)
	var total_ms := 0.0
	for f in range(FULL_SIM_FRAMES):
		var t0 := Time.get_ticks_usec()
		mgr.advance_simulation(SIM_DT, 1.0, wd, nav, [], [])
		var dt_ms := float(Time.get_ticks_usec() - t0) / 1000.0
		samples[f] = dt_ms
		total_ms += dt_ms

	var sorted := samples.duplicate()
	sorted.sort()
	return {"avg_ms": total_ms / float(FULL_SIM_FRAMES), "p95_ms": _percentile(sorted, 0.95)}

func _run_scenario(label: String, count: int, mode: String, fog_visible: bool) -> Dictionary:
	var fix := _build_fixture(count, mode, fog_visible)
	var cache_before := EntityVisualRegistryScript._texture_cache.size()
	var pure := _bench_pure_actor_sync(fix)
	var full := _bench_full_advance(fix)
	var cache_after := EntityVisualRegistryScript._texture_cache.size()
	var mgr = fix["mgr"]
	var cont: Node2D = fix["cont"]

	var uniq_tex := {}
	for a in mgr.actors_by_id.values():
		if a != null and is_instance_valid(a) and a._sprite != null and a._sprite.texture != null:
			uniq_tex[a._sprite.texture.get_instance_id()] = true

	var per_actor_us: float = (float(pure["avg_ms"]) * 1000.0) / float(maxi(1, count)) if count > 0 else 0.0
	print("  [%s | n=%2d | mode=%-9s | vis=%-5s] ActorSync: avg=%.4fms p95=%.4fms (%.2f us/actor) | FullSim+Pres: avg=%.4fms p95=%.4fms | actors=%d nodes=%d texCache=%d uniqTex=%d" % [
		label, count, mode, str(fog_visible),
		pure["avg_ms"], pure["p95_ms"], per_actor_us,
		full["avg_ms"], full["p95_ms"],
		mgr.actors_by_id.size(), cont.get_child_count(),
		cache_after, uniq_tex.size()
	])

	_assert(mgr.actors_by_id.size() == count, "%s: actor count == %d" % [label, count])
	_assert(cont.get_child_count() == count, "%s: zero stray nodes (nodes == %d)" % [label, count])
	_assert(cache_after == cache_before, "%s: zero per-frame cache churn (%d == %d)" % [label, cache_after, cache_before])
	if count >= 6:
		_assert(uniq_tex.size() == 6, "%s: all 6 species share exact 6 cached sheets (uniq=%d)" % [label, uniq_tex.size()])

	if is_instance_valid(cont):
		cont.queue_free()
	await process_frame
	return {"pure": pure, "full": full}

func _run() -> void:
	print("==========================================================================")
	print("  M6-4 DEDICATED WILDLIFE ACTOR VISUAL & ANIMATION BENCHMARK")
	print("  Godot=4.7-stable | PureSync=%df (warmup=%df) | FullSim=%df | dt=%.3fs" % [PURE_SYNC_FRAMES, WARMUP_FRAMES, FULL_SIM_FRAMES, SIM_DT])
	print("==========================================================================")

	print("\n[1. Scaling Matrix — Mixed States, All 6 Species, Fog Visible]")
	for n in [0, 10, 25, 50, 70]:
		await _run_scenario("Scale", n, "mixed", true)

	print("\n[2. State & Fog Visibility Breakdown at Maximum Cap (70 Wildlife)]")
	await _run_scenario("MaxCap", 70, "idle", true)
	await _run_scenario("MaxCap", 70, "wandering", true)
	await _run_scenario("MaxCap", 70, "fleeing", true)
	await _run_scenario("MaxCap", 70, "defensive", true)
	var r_vis := await _run_scenario("MaxCap", 70, "mixed", true)
	var r_hid := await _run_scenario("MaxCap", 70, "mixed", false)

	_assert(float(r_hid["pure"]["avg_ms"]) <= float(r_vis["pure"]["avg_ms"]) * 1.15, "Fog-hidden 70 wildlife sync overhead <= Fog-visible cost")

	print("--------------------------------------------------------------------------")
	print("  Assertions: %d passed, %d failed | Cache entries=%d | Portrait cache=%d" % [
		_passed, _failed, EntityVisualRegistryScript._texture_cache.size(), EntityVisualRegistryScript._portrait_cache.size()
	])
	print("==========================================================================")
	quit(0 if _failed == 0 else 1)
