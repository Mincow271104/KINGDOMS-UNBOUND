extends RefCounted
## Centralized manager for Phase 6 Wildlife & Animal Ecosystem.
## Owns deterministic spawning, habitat validation, non-blocking movement/behavior,
## Fog of War visibility, debug inspection, and optional save/load persistence.

const WildlifeConfig = preload("res://scripts/world/wildlife_config.gd")
const WildlifeActor = preload("res://scripts/world/wildlife_actor.gd")

const CARDINAL_DIRS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]
const THREAT_SCAN_INTERVAL: float = 0.25

var animals: Array[Dictionary] = []
var animals_by_id: Dictionary = {}
var actors_by_id: Dictionary = {}
var reservations_by_animal_id: Dictionary = {}
var reservations_by_hunter_id: Dictionary = {}
var recovery_timers: Dictionary = {"rabbit": 0.0, "deer": 0.0}
var recovery_spawn_counters: Dictionary = {"rabbit": 0, "deer": 0}
var _hunter_range_cells: Dictionary = {}
var _hunter_range_rev: int = -1
var _hunter_range_bridge_count: int = -1
var _hunter_range_dirty: bool = true
var _wildlife_container: Node2D = null
var _rng := RandomNumberGenerator.new()
var _threat_scan_accum: float = 0.0
var _anim_time: float = 0.0

func set_container(container: Node2D) -> void:
	_wildlife_container = container

func clear_all() -> void:
	animals = []
	animals_by_id = {}
	reservations_by_animal_id.clear()
	reservations_by_hunter_id.clear()
	recovery_timers = {"rabbit": 0.0, "deer": 0.0}
	recovery_spawn_counters = {"rabbit": 0, "deer": 0}
	invalidate_hunter_range_cache()
	for a_id in actors_by_id.keys():
		var actor = actors_by_id[a_id]
		if actor != null and is_instance_valid(actor):
			actor.queue_free()
	actors_by_id.clear()
	_threat_scan_accum = 0.0
	_anim_time = 0.0

func invalidate_hunter_range_cache() -> void:
	_hunter_range_cells.clear()
	_hunter_range_rev = -1
	_hunter_range_bridge_count = -1
	_hunter_range_dirty = true

func generate_initial_population(world_data: WorldGenerator.WorldData, nav: GridNavigation = null) -> void:
	clear_all()
	if world_data == null:
		return
	var active_nav: GridNavigation = nav
	if active_nav == null:
		active_nav = GridNavigation.new(world_data)
	# Legacy V1-V4 worlds lack biome_grid; handle safely without rewriting world data.
	if world_data.biome_grid.is_empty():
		return

	if world_data.wildlife.is_empty():
		WorldGenerator.generate_canonical_wildlife(world_data, active_nav)

	animals = world_data.wildlife
	animals_by_id = world_data.wildlife_by_id

	for rec in animals:
		_spawn_actor_for_record(rec)

func _make_animal_record(a_id: String, species_id: String, cat: int, cell: Vector2i, state: int = WildlifeConfig.BehaviorState.IDLE) -> Dictionary:
	var spec: Dictionary = WildlifeConfig.get_species_def(species_id)
	var idle_t: float = _rng.randf_range(0.25, float(spec.get("idle_max", 4.0)))
	return {
		"id": a_id,
		"species_id": species_id,
		"category": cat,
		"cell": cell,
		"prev_cell": cell,
		"home_cell": cell,
		"target_cell": cell,
		"last_dir": Vector2i.ZERO,
		"burst_remaining": 0,
		"speed_jitter": _rng.randf_range(0.88, 1.12),
		"anim_phase": _rng.randf_range(0.0, TAU),
		"turn_blend": 1.0,
		"move_progress": 0.0,
		"state": state,
		"state_timer": idle_t,
		"threat_cell": Vector2i(-1, -1),
		"flip_h": false,
		"is_available": true,
		"reserved_by": "",
		"reservation_type": "",
		"recovery_hours_left": 0.0,
		"raw_meat_yield": 2 if species_id == "rabbit" else (4 if species_id == "deer" else 0),
		"hunt_duration_hours": 1.5 if species_id == "rabbit" else (2.5 if species_id == "deer" else 0.0),
		"recovery_hours": 48.0 if species_id == "rabbit" else (72.0 if species_id == "deer" else 0.0),
		"allocated_workplace_id": "",
		"allocated_settlement_id": "",
	}

func _spawn_actor_for_record(rec: Dictionary) -> void:
	if _wildlife_container == null or not is_instance_valid(_wildlife_container):
		return
	var a_id: String = str(rec["id"])
	var actor := WildlifeActor.new()
	actor.setup(a_id, str(rec["species_id"]), rec["cell"])
	_wildlife_container.add_child(actor)
	actors_by_id[a_id] = actor

func spawn_all_actors() -> void:
	if _wildlife_container == null or not is_instance_valid(_wildlife_container):
		return
	for rec in animals:
		var a_id: String = str(rec["id"])
		if not actors_by_id.has(a_id) or not is_instance_valid(actors_by_id[a_id]):
			_spawn_actor_for_record(rec)

func advance_simulation(delta: float, speed_mult: float, world_data: WorldGenerator.WorldData, nav: GridNavigation, citizen_list: Array, player_units: Array) -> void:
	if speed_mult <= 0.0 or delta <= 0.0 or world_data == null or nav == null:
		return
	var delta_hours: float = (delta * speed_mult) / 7.5
	advance_recovery(delta_hours, world_data, nav)
	if animals.is_empty():
		return

	var sim_dt: float = minf(delta, 0.05) * speed_mult
	_anim_time += sim_dt
	_threat_scan_accum += sim_dt
	var do_threat_scan: bool = _threat_scan_accum >= THREAT_SCAN_INTERVAL
	var threat_cells: Array[Vector2i] = []
	if do_threat_scan:
		_threat_scan_accum = 0.0
		for cit in citizen_list:
			if cit != null and is_instance_valid(cit):
				var cc = cit.get("current_cell")
				if cc is Vector2i:
					threat_cells.append(cc)
		for u in player_units:
			if u is Dictionary:
				if u.get("is_alive", true) == true and u.get("current_cell") is Vector2i:
					threat_cells.append(u["current_cell"])
			elif u != null and is_instance_valid(u) and u.get("is_alive") == true:
				var uc = u.get("current_cell")
				if uc is Vector2i:
					threat_cells.append(uc)

	for rec in animals:
		if int(rec["state"]) == WildlifeConfig.BehaviorState.BEING_HUNTED:
			var bh_id: String = str(rec["id"])
			if actors_by_id.has(bh_id):
				var bh_actor: WildlifeActor = actors_by_id[bh_id]
				if bh_actor != null and is_instance_valid(bh_actor):
					bh_actor.sync_visual(IsoMath.map_to_local(rec["cell"]), int(rec["state"]), bool(rec["flip_h"]))
			continue
		var spec: Dictionary = WildlifeConfig.get_species_def(str(rec["species_id"]))
		var cat: int = int(rec["category"])
		var awareness: int = int(spec.get("awareness_radius", 0))

		# Periodic threat detection for Passive Huntable & Defensive wildlife
		if do_threat_scan and awareness > 0 and not threat_cells.is_empty():
			var a_cell: Vector2i = rec["cell"]
			var nearest_threat := Vector2i(-1, -1)
			var best_d: int = awareness + 1
			for tc in threat_cells:
				var d: int = IsoMath.grid_distance(a_cell, tc)
				if d < best_d:
					best_d = d
					nearest_threat = tc
			if nearest_threat.x >= 0:
				rec["threat_cell"] = nearest_threat
				if cat == WildlifeConfig.Category.PASSIVE_HUNTABLE:
					if int(rec["state"]) != WildlifeConfig.BehaviorState.FLEEING:
						rec["state"] = WildlifeConfig.BehaviorState.FLEEING
						rec["state_timer"] = 2.0
				elif cat == WildlifeConfig.Category.DEFENSIVE:
					var st: int = int(rec["state"])
					if st == WildlifeConfig.BehaviorState.IDLE or st == WildlifeConfig.BehaviorState.WANDERING:
						rec["state"] = WildlifeConfig.BehaviorState.DEFENSIVE_DISPLAY
						rec["state_timer"] = float(spec.get("warning_duration", 1.1))
						rec["target_cell"] = rec["cell"]
						rec["move_progress"] = 0.0

		rec["turn_blend"] = minf(1.0, float(rec.get("turn_blend", 1.0)) + sim_dt * 7.0)

		# Advance current movement step if moving between cells
		if rec["target_cell"] != rec["cell"]:
			var base_spd: float = float(spec.get("flee_speed", 3.0)) if int(rec["state"]) == WildlifeConfig.BehaviorState.FLEEING else float(spec.get("move_speed", 2.0))
			var spd: float = base_spd * float(rec.get("speed_jitter", 1.0))
			rec["move_progress"] = float(rec["move_progress"]) + spd * sim_dt
			if float(rec["move_progress"]) >= 1.0:
				rec["prev_cell"] = rec["cell"]
				rec["cell"] = rec["target_cell"]
				rec["move_progress"] = 0.0
				if int(rec["state"]) == WildlifeConfig.BehaviorState.WANDERING:
					var rem_burst: int = maxi(0, int(rec.get("burst_remaining", 0)) - 1)
					rec["burst_remaining"] = rem_burst
					if rem_burst > 0:
						var cont_cell := _pick_wander_cell(rec, world_data, nav)
						if cont_cell != rec["cell"]:
							_apply_step_facing(rec, rec["cell"], cont_cell)
							rec["last_dir"] = cont_cell - rec["cell"]
							rec["target_cell"] = cont_cell
						else:
							rec["burst_remaining"] = 0
							rec["state"] = WildlifeConfig.BehaviorState.IDLE
							rec["state_timer"] = _rng.randf_range(float(spec.get("idle_min", 1.8)), float(spec.get("idle_max", 4.2)))
					else:
						rec["state"] = WildlifeConfig.BehaviorState.IDLE
						rec["state_timer"] = _rng.randf_range(float(spec.get("idle_min", 1.8)), float(spec.get("idle_max", 4.2)))

		# State machine step when at cell center
		if rec["target_cell"] == rec["cell"]:
			var st: int = int(rec["state"])
			if st == WildlifeConfig.BehaviorState.IDLE:
				rec["state_timer"] = float(rec["state_timer"]) - sim_dt
				if float(rec["state_timer"]) <= 0.0:
					var b_min: int = maxi(1, int(spec.get("burst_min", 1)))
					var b_max: int = maxi(b_min, int(spec.get("burst_max", 3)))
					rec["burst_remaining"] = _rng.randi_range(b_min, b_max)
					var next_cell := _pick_wander_cell(rec, world_data, nav)
					if next_cell != rec["cell"]:
						_apply_step_facing(rec, rec["cell"], next_cell)
						rec["last_dir"] = next_cell - rec["cell"]
						rec["target_cell"] = next_cell
						rec["move_progress"] = 0.0
						rec["state"] = WildlifeConfig.BehaviorState.WANDERING
					else:
						rec["burst_remaining"] = 0
						rec["state_timer"] = _rng.randf_range(1.2, 2.5)
			elif st == WildlifeConfig.BehaviorState.ALERT or st == WildlifeConfig.BehaviorState.DEFENSIVE_DISPLAY:
				rec["state_timer"] = float(rec["state_timer"]) - sim_dt
				if float(rec["state_timer"]) <= 0.0:
					rec["state"] = WildlifeConfig.BehaviorState.FLEEING
					rec["state_timer"] = 1.8
			elif st == WildlifeConfig.BehaviorState.FLEEING:
				rec["state_timer"] = float(rec["state_timer"]) - sim_dt
				if float(rec["state_timer"]) <= 0.0:
					rec["state"] = WildlifeConfig.BehaviorState.IDLE
					rec["state_timer"] = _rng.randf_range(1.5, 3.0)
				else:
					var flee_cell := _pick_flee_cell(rec, world_data, nav)
					if flee_cell != rec["cell"]:
						_apply_step_facing(rec, rec["cell"], flee_cell)
						rec["last_dir"] = flee_cell - rec["cell"]
						rec["target_cell"] = flee_cell
						rec["move_progress"] = 0.0
					else:
						rec["state"] = WildlifeConfig.BehaviorState.IDLE
						rec["state_timer"] = 1.5

		# Sync lightweight actor position (presentation-only)
		var a_id: String = str(rec["id"])
		if actors_by_id.has(a_id):
			var actor: WildlifeActor = actors_by_id[a_id]
			if actor != null and is_instance_valid(actor):
				var p0 := IsoMath.map_to_local(rec["cell"])
				var p1 := IsoMath.map_to_local(rec["target_cell"])
				var prog: float = float(rec["move_progress"])
				var is_moving: bool = rec["target_cell"] != rec["cell"]
				var t_vis: float = prog
				if is_moving and int(rec.get("burst_remaining", 0)) <= 1 and int(rec["state"]) == WildlifeConfig.BehaviorState.WANDERING:
					t_vis = smoothstep(0.0, 1.0, prog)
				actor.sync_visual(
					p0.lerp(p1, t_vis),
					int(rec["state"]),
					bool(rec["flip_h"]),
					t_vis,
					is_moving,
					_anim_time + float(rec.get("anim_phase", 0.0)),
					float(rec.get("turn_blend", 1.0))
				)

func _apply_step_facing(rec: Dictionary, from_cell: Vector2i, to_cell: Vector2i) -> void:
	var dx_screen: float = IsoMath.map_to_local(to_cell).x - IsoMath.map_to_local(from_cell).x
	if absf(dx_screen) <= 0.01:
		return
	var new_flip: bool = dx_screen < 0.0
	if new_flip != bool(rec.get("flip_h", false)):
		rec["flip_h"] = new_flip
		rec["turn_blend"] = 0.0

func _pick_wander_cell(rec: Dictionary, world_data: WorldGenerator.WorldData, nav: GridNavigation) -> Vector2i:
	var c: Vector2i = rec["cell"]
	var prev_c: Vector2i = rec.get("prev_cell", c)
	var home_c: Vector2i = rec.get("home_cell", c)
	var last_dir: Vector2i = rec.get("last_dir", Vector2i.ZERO)
	var species_id: String = str(rec["species_id"])
	var spec: Dictionary = WildlifeConfig.get_species_def(species_id)
	var wander_rad: int = int(spec.get("wander_radius", 7))
	var turn_persist: float = float(spec.get("turn_persistence", 0.5))

	var biome_matches: Array[Vector2i] = []
	var fallback_walkable: Array[Vector2i] = []
	for d in CARDINAL_DIRS:
		var nb: Vector2i = c + d
		if not nav.is_cell_walkable(nb):
			continue
		if IsoMath.grid_distance(nb, world_data.center_spawn) <= 4:
			continue
		if WildlifeConfig.is_biome_allowed(species_id, world_data.get_biome(nb)):
			biome_matches.append(nb)
		else:
			fallback_walkable.append(nb)

	if not biome_matches.is_empty():
		# Anti-oscillation: avoid stepping back onto prev_cell when alternatives exist
		var non_backtrack: Array[Vector2i] = []
		for nb in biome_matches:
			if nb != prev_c:
				non_backtrack.append(nb)
		var pool: Array[Vector2i] = non_backtrack if not non_backtrack.is_empty() else biome_matches

		# Soft home-area tether: keep within wander_radius (or step closer to home_cell if outside)
		var in_radius: Array[Vector2i] = []
		for nb in pool:
			if IsoMath.grid_distance(nb, home_c) <= wander_rad:
				in_radius.append(nb)
		if not in_radius.is_empty():
			pool = in_radius
		elif IsoMath.grid_distance(c, home_c) > wander_rad:
			var cur_d: int = IsoMath.grid_distance(c, home_c)
			var closer: Array[Vector2i] = []
			for nb in pool:
				if IsoMath.grid_distance(nb, home_c) < cur_d:
					closer.append(nb)
			if not closer.is_empty():
				pool = closer

		# Heading continuity: preserve forward direction with species-specific turn_persistence
		if last_dir != Vector2i.ZERO and pool.has(c + last_dir) and _rng.randf() < turn_persist:
			return c + last_dir
		return pool[_rng.randi_range(0, pool.size() - 1)]

	if not fallback_walkable.is_empty() and not WildlifeConfig.is_biome_allowed(species_id, world_data.get_biome(c)):
		return fallback_walkable[_rng.randi_range(0, fallback_walkable.size() - 1)]
	return c

func _pick_flee_cell(rec: Dictionary, world_data: WorldGenerator.WorldData, nav: GridNavigation) -> Vector2i:
	var c: Vector2i = rec["cell"]
	var threat: Vector2i = rec.get("threat_cell", Vector2i(-1, -1))
	var species_id: String = str(rec["species_id"])
	var best_cell: Vector2i = c
	var best_score: int = IsoMath.grid_distance(c, threat) if threat.x >= 0 else 0
	for d in CARDINAL_DIRS:
		var nb: Vector2i = c + d
		if not nav.is_cell_walkable(nb):
			continue
		var dist: int = IsoMath.grid_distance(nb, threat) if threat.x >= 0 else 1
		var biome_bonus: int = 1 if WildlifeConfig.is_biome_allowed(species_id, world_data.get_biome(nb)) else 0
		var score: int = dist * 2 + biome_bonus
		if score > best_score:
			best_score = score
			best_cell = nb
	return best_cell

func refresh_visibility(fog_of_war: FogOfWar, debug_fog_disabled: bool) -> void:
	for rec in animals:
		var a_id: String = str(rec["id"])
		var actor: WildlifeActor = actors_by_id.get(a_id)
		if actor != null and is_instance_valid(actor):
			var c: Vector2i = rec["cell"]
			# Living animals are ONLY visible in currently VISIBLE cells when Fog is ON.
			actor.visible = debug_fog_disabled or (fog_of_war != null and fog_of_war.is_visible(c))

func inspect_cell(cell: Vector2i, world_data: WorldGenerator.WorldData, fog_of_war: FogOfWar, debug_fog_disabled: bool) -> Dictionary:
	for rec in animals:
		var a_cell: Vector2i = rec["cell"]
		if a_cell != cell:
			continue
		if not debug_fog_disabled and (fog_of_war == null or not fog_of_war.is_visible(a_cell)):
			continue
		var species_id: String = str(rec["species_id"])
		var spec: Dictionary = WildlifeConfig.get_species_def(species_id)
		var display_name: String = str(spec.get("display_name", species_id.capitalize()))
		var cat_str: String = WildlifeConfig.category_name(int(rec["category"]))
		var state_str: String = WildlifeConfig.state_name(int(rec["state"]))
		var biome_str: String = WildlifeConfig.biome_name(world_data.get_biome(a_cell)) if world_data != null else "Unknown"
		var a_id: String = str(rec["id"])
		var biome_id: int = world_data.get_biome(a_cell) if world_data != null else -1
		var huntable: bool = WildlifeConfig.is_huntable_species(species_id)
		var meat_yield: int = int(rec.get("raw_meat_yield", spec.get("raw_meat_yield", 0)))
		var hunt_hours: float = float(rec.get("hunt_duration_hours", spec.get("hunt_duration_hours", 0.0)))
		var rec_hours: float = float(rec.get("recovery_hours", spec.get("recovery_hours", 0.0)))
		var res_by: String = get_reserved_hunter(a_id)
		var res_type: String = str(rec.get("reservation_type", ""))
		return {
			"is_debug_inspect": true,
			"category": "wildlife",
			"id": "debug_wl_%s" % a_id,
			"entity_id": a_id,
			"species_id": species_id,
			"display_name": display_name,
			"wildlife_category": cat_str,
			"category_int": int(rec["category"]),
			"biome": biome_str,
			"biome_id": biome_id,
			"cell": a_cell,
			"size": Vector2i(1, 1),
			"behavior_state": state_str,
			"state_int": int(rec["state"]),
			"huntable": huntable,
			"raw_meat_yield": meat_yield,
			"hunt_duration_hours": hunt_hours,
			"recovery_hours": rec_hours,
			"is_reserved": is_animal_reserved(a_id),
			"reserved_by": res_by,
			"reservation_type": res_type,
			"title": "%s [Debug]" % display_name,
			"coords_text": "Tọa độ: (%d, %d) | Quần xã: %s | Loài: %s" % [a_cell.x, a_cell.y, biome_str, species_id],
			"state_text": "[%s — %s]" % [cat_str.to_upper(), state_str],
			"state_color": Color(0.55, 0.90, 0.65, 1.0),
			"detail_text": "Hành vi: %s | Săn bắt: %s" % [state_str, "Có (+%d thịt sống)" % meat_yield if huntable else "Không"],
			"show_bar": false,
		}
	return {}

func get_all_animals() -> Array[Dictionary]:
	return animals

func get_animal_by_id(a_id: String) -> Dictionary:
	return animals_by_id.get(a_id, {})

# ==============================================================================
# PHASE 7: HUNTER RANGE, RESERVATION, HUNTING & POPULATION RECOVERY
# ==============================================================================

func get_hunter_permitted_cells(world_data: WorldGenerator.WorldData, territory_mgr: RefCounted, fog_of_war: FogOfWar, nav: GridNavigation) -> Dictionary:
	if world_data == null or territory_mgr == null or nav == null:
		return {}
	var rev_val = territory_mgr.get("_revision")
	var cur_rev: int = int(rev_val) if rev_val != null else 0
	var b_count: int = world_data.bridge_walkable_cells.size()
	if not _hunter_range_dirty and cur_rev == _hunter_range_rev and b_count == _hunter_range_bridge_count:
		return _hunter_range_cells

	_hunter_range_cells.clear()
	_hunter_range_rev = cur_rev
	_hunter_range_bridge_count = b_count
	_hunter_range_dirty = false

	var queue: Array[Vector2i] = []
	var owned_list: Array = territory_mgr.call("get_owned_cells") if territory_mgr.has_method("get_owned_cells") else []
	for oc in owned_list:
		if fog_of_war == null or fog_of_war.is_explored(oc):
			if nav.is_cell_walkable(oc):
				_hunter_range_cells[oc] = 0
				queue.append(oc)

	var head: int = 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var d: int = int(_hunter_range_cells[cur])
		if d >= WildlifeConfig.HUNTER_MAX_RANGE_STEPS:
			continue
		for dir in CARDINAL_DIRS:
			var nb: Vector2i = cur + dir
			if _hunter_range_cells.has(nb):
				continue
			if not nav.is_cell_walkable(nb):
				continue
			if fog_of_war == null or not fog_of_war.is_explored(nb):
				continue
			_hunter_range_cells[nb] = d + 1
			queue.append(nb)

	return _hunter_range_cells

func is_cell_permitted_for_hunter(cell: Vector2i, world_data: WorldGenerator.WorldData, territory_mgr: RefCounted, fog_of_war: FogOfWar, nav: GridNavigation) -> bool:
	var permitted := get_hunter_permitted_cells(world_data, territory_mgr, fog_of_war, nav)
	return permitted.has(cell)

func is_animal_reserved(a_id: String) -> bool:
	return reservations_by_animal_id.has(a_id)

func get_reserved_hunter(a_id: String) -> String:
	return str(reservations_by_animal_id.get(a_id, ""))

func get_hunter_reserved_animal_id(hunter_id: String) -> String:
	return str(reservations_by_hunter_id.get(hunter_id, ""))

func reserve_animal(a_id: String, hunter_id: String) -> bool:
	if a_id == "" or hunter_id == "":
		return false
	var rec: Dictionary = animals_by_id.get(a_id, {})
	if rec.is_empty() or not WildlifeConfig.is_huntable_species(str(rec.get("species_id", ""))):
		return false
	if not bool(rec.get("is_available", true)):
		if str(rec.get("reserved_by", "")) != hunter_id:
			return false
	if reservations_by_animal_id.has(a_id):
		return str(reservations_by_animal_id[a_id]) == hunter_id
	if reservations_by_hunter_id.has(hunter_id):
		release_hunter_reservations(hunter_id)
	reservations_by_animal_id[a_id] = hunter_id
	reservations_by_hunter_id[hunter_id] = a_id
	rec["is_available"] = false
	rec["reserved_by"] = hunter_id
	rec["reservation_type"] = "player"
	return true

func release_reservation(a_id: String, hunter_id: String = "") -> void:
	if a_id == "" or not reservations_by_animal_id.has(a_id):
		return
	var owner_id: String = str(reservations_by_animal_id[a_id])
	if hunter_id != "" and owner_id != hunter_id:
		return
	reservations_by_animal_id.erase(a_id)
	if reservations_by_hunter_id.get(owner_id, "") == a_id:
		reservations_by_hunter_id.erase(owner_id)
	var rec: Dictionary = animals_by_id.get(a_id, {})
	if not rec.is_empty():
		if str(rec.get("reserved_by", "")) == owner_id:
			rec["is_available"] = true
			rec["reserved_by"] = ""
			rec["reservation_type"] = ""
		if int(rec.get("state", 0)) == WildlifeConfig.BehaviorState.BEING_HUNTED:
			rec["state"] = WildlifeConfig.BehaviorState.IDLE
			rec["state_timer"] = 1.0

func release_hunter_reservations(hunter_id: String) -> void:
	if hunter_id == "" or not reservations_by_hunter_id.has(hunter_id):
		return
	var a_id: String = str(reservations_by_hunter_id[hunter_id])
	release_reservation(a_id, hunter_id)

func begin_hunting_interaction(a_id: String, hunter_id: String) -> bool:
	if a_id == "" or hunter_id == "":
		return false
	if str(reservations_by_animal_id.get(a_id, "")) != hunter_id:
		return false
	var rec: Dictionary = animals_by_id.get(a_id, {})
	if rec.is_empty() or not WildlifeConfig.is_huntable_species(str(rec.get("species_id", ""))):
		return false
	rec["state"] = WildlifeConfig.BehaviorState.BEING_HUNTED
	rec["target_cell"] = rec["cell"]
	rec["move_progress"] = 0.0
	return true

func complete_hunt(a_id: String, hunter_id: String) -> Dictionary:
	if a_id == "" or hunter_id == "":
		return {"success": false}
	if str(reservations_by_animal_id.get(a_id, "")) != hunter_id:
		return {"success": false}
	var rec: Dictionary = animals_by_id.get(a_id, {})
	if rec.is_empty():
		release_reservation(a_id, hunter_id)
		return {"success": false}
	var sp: String = str(rec.get("species_id", ""))
	if not WildlifeConfig.is_huntable_species(sp):
		release_reservation(a_id, hunter_id)
		return {"success": false}

	var spec: Dictionary = WildlifeConfig.get_species_def(sp)
	var yield_amt: int = int(spec.get("raw_meat_yield", 0))

	# Atomically remove prey and reservation
	reservations_by_animal_id.erase(a_id)
	if reservations_by_hunter_id.get(hunter_id, "") == a_id:
		reservations_by_hunter_id.erase(hunter_id)
	animals_by_id.erase(a_id)
	for i in range(animals.size()):
		if str(animals[i].get("id", "")) == a_id:
			animals.remove_at(i)
			break
	if actors_by_id.has(a_id):
		var actor = actors_by_id[a_id]
		actors_by_id.erase(a_id)
		if actor != null and is_instance_valid(actor):
			actor.queue_free()

	return {
		"success": true,
		"species_id": sp,
		"resource": EconomyConfig.RES_RAW_MEAT,
		"yield": yield_amt,
	}

func find_and_reserve_nearest_prey(hunter_id: String, hunter_cell: Vector2i, world_data: WorldGenerator.WorldData, territory_mgr: RefCounted, fog_of_war: FogOfWar, nav: GridNavigation, path_fn: Callable) -> Dictionary:
	if hunter_id == "" or world_data == null or territory_mgr == null or nav == null or not path_fn.is_valid():
		return {}
	var permitted := get_hunter_permitted_cells(world_data, territory_mgr, fog_of_war, nav)
	if permitted.is_empty():
		return {}

	var candidates: Array[Dictionary] = []
	for rec in animals:
		var sp: String = str(rec.get("species_id", ""))
		if not WildlifeConfig.is_huntable_species(sp):
			continue
		if not bool(rec.get("is_available", true)):
			continue
		var a_id: String = str(rec.get("id", ""))
		if reservations_by_animal_id.has(a_id) or str(rec.get("reserved_by", "")) != "":
			continue
		var a_cell: Vector2i = rec["cell"]
		if not permitted.has(a_cell):
			continue
		if fog_of_war == null or not fog_of_war.is_explored(a_cell):
			continue
		candidates.append({"rec": rec, "dist": IsoMath.grid_distance(hunter_cell, a_cell)})

	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a, b): return int(a["dist"]) < int(b["dist"]))

	for entry in candidates:
		var rec: Dictionary = entry["rec"]
		var a_id: String = str(rec["id"])
		var a_cell: Vector2i = rec["cell"]
		var approach_cells: Array[Vector2i] = []
		if permitted.has(a_cell) and nav.is_cell_walkable(a_cell):
			approach_cells.append(a_cell)
		for d in CARDINAL_DIRS:
			var nb: Vector2i = a_cell + d
			if permitted.has(nb) and nav.is_cell_walkable(nb):
				approach_cells.append(nb)
		for app in approach_cells:
			var path: Array = path_fn.call(hunter_cell, app)
			if not path.is_empty():
				if reserve_animal(a_id, hunter_id):
					return {"animal": rec, "path": path, "approach_cell": app}
				break
	return {}

func advance_recovery(delta_hours: float, world_data: WorldGenerator.WorldData, nav: GridNavigation) -> void:
	if delta_hours <= 0.0 or world_data == null or nav == null or world_data.biome_grid.is_empty():
		return
	for sp in ["rabbit", "deer"]:
		var spec: Dictionary = WildlifeConfig.get_species_def(sp)
		var max_pop: int = int(spec.get("max_pop", 12))
		var interval: float = float(spec.get("recovery_hours", 48.0))
		if interval <= 0.0:
			continue
		var cur_count: int = 0
		for rec in animals:
			if str(rec.get("species_id", "")) == sp:
				cur_count += 1
		if cur_count >= max_pop or animals.size() >= WildlifeConfig.MAX_TOTAL_POPULATION:
			recovery_timers[sp] = 0.0
			continue
		recovery_timers[sp] = float(recovery_timers.get(sp, 0.0)) + delta_hours
		if float(recovery_timers[sp]) >= interval:
			if _try_spawn_recovered_animal(sp, world_data, nav):
				recovery_timers[sp] = float(recovery_timers[sp]) - interval
			else:
				recovery_timers[sp] = interval

func _try_spawn_recovered_animal(species_id: String, world_data: WorldGenerator.WorldData, nav: GridNavigation) -> bool:
	if animals.size() >= WildlifeConfig.MAX_TOTAL_POPULATION:
		return false
	var spec: Dictionary = WildlifeConfig.get_species_def(species_id)
	var max_pop: int = int(spec.get("max_pop", 12))
	var cur_count: int = 0
	for rec in animals:
		if str(rec.get("species_id", "")) == species_id:
			cur_count += 1
	if cur_count >= max_pop:
		return false

	var counter: int = int(recovery_spawn_counters.get(species_id, 0)) + 1
	var r_rng := RandomNumberGenerator.new()
	r_rng.seed = int(world_data.seed_value) ^ WildlifeConfig.WILDLIFE_RNG_SALT ^ hash(species_id) ^ counter

	var occupied: Dictionary = {}
	for rec in animals:
		occupied[rec["cell"]] = true
	var building_cells: Array[Vector2i] = []
	for b in world_data.buildings:
		var origin: Vector2i = b.get("cell", Vector2i.ZERO)
		var b_size: Vector2i = b.get("size", Vector2i.ONE)
		for ox in range(b_size.x):
			for oy in range(b_size.y):
				building_cells.append(origin + Vector2i(ox, oy))

	var pool: Array[Vector2i] = []
	for x in range(world_data.map_width):
		for y in range(world_data.map_height):
			var c := Vector2i(x, y)
			if occupied.has(c) or not nav.is_cell_walkable(c):
				continue
			if not WildlifeConfig.is_biome_allowed(species_id, world_data.get_biome(c)):
				continue
			if IsoMath.grid_distance(c, world_data.center_spawn) <= 5:
				continue
			var close_bld: bool = false
			for bc in building_cells:
				if IsoMath.grid_distance(c, bc) <= 2:
					close_bld = true
					break
			if close_bld:
				continue
			var w_nb: int = 0
			for d in CARDINAL_DIRS:
				if nav.is_cell_walkable(c + d):
					w_nb += 1
			if w_nb >= 2:
				pool.append(c)

	if pool.is_empty():
		return false
	var chosen: Vector2i = pool[r_rng.randi_range(0, pool.size() - 1)]
	var a_id := "wl_%s_r%03d" % [species_id, counter]
	while animals_by_id.has(a_id):
		counter += 1
		a_id = "wl_%s_r%03d" % [species_id, counter]
	recovery_spawn_counters[species_id] = counter
	var new_rec := _make_animal_record(a_id, species_id, int(spec.get("category", 0)), chosen)
	animals.append(new_rec)
	animals_by_id[a_id] = new_rec
	_spawn_actor_for_record(new_rec)
	return true

func serialize() -> Dictionary:
	var list: Array = []
	for rec in animals:
		var c: Vector2i = rec["cell"]
		var hc: Vector2i = rec["home_cell"]
		var st: int = int(rec["state"])
		if st == WildlifeConfig.BehaviorState.BEING_HUNTED or st == WildlifeConfig.BehaviorState.WANDERING or st == WildlifeConfig.BehaviorState.FLEEING:
			st = WildlifeConfig.BehaviorState.IDLE
		list.append({
			"id": str(rec["id"]),
			"species_id": str(rec["species_id"]),
			"cell_x": c.x,
			"cell_y": c.y,
			"home_x": hc.x,
			"home_y": hc.y,
			"state": st,
		})
	return {
		"version": 2,
		"animals": list,
		"recovery_timers": recovery_timers.duplicate(),
		"recovery_spawn_counters": recovery_spawn_counters.duplicate(),
	}

func deserialize_or_init(saved_data: Variant, world_data: WorldGenerator.WorldData, nav: GridNavigation) -> void:
	if saved_data is Dictionary and saved_data.has("animals") and saved_data["animals"] is Array:
		clear_all()
		_rng.seed = int(world_data.seed_value) ^ WildlifeConfig.WILDLIFE_RNG_SALT if world_data != null else WildlifeConfig.WILDLIFE_RNG_SALT
		var rt = saved_data.get("recovery_timers", {})
		if rt is Dictionary:
			recovery_timers["rabbit"] = float(rt.get("rabbit", 0.0))
			recovery_timers["deer"] = float(rt.get("deer", 0.0))
		var rc = saved_data.get("recovery_spawn_counters", {})
		if rc is Dictionary:
			recovery_spawn_counters["rabbit"] = int(rc.get("rabbit", 0))
			recovery_spawn_counters["deer"] = int(rc.get("deer", 0))
		var seen_ids: Dictionary = {}
		for item in saved_data["animals"]:
			if not (item is Dictionary):
				continue
			var a_id: String = str(item.get("id", ""))
			var species_id: String = str(item.get("species_id", ""))
			if a_id == "" or seen_ids.has(a_id):
				continue
			var spec: Dictionary = WildlifeConfig.get_species_def(species_id)
			if spec.is_empty():
				continue
			var c := Vector2i(int(item.get("cell_x", 0)), int(item.get("cell_y", 0)))
			if world_data != null and not world_data.is_in_bounds(c):
				continue
			if nav != null and not nav.is_cell_walkable(c):
				continue
			seen_ids[a_id] = true
			var st_val: int = int(item.get("state", 0))
			if st_val == WildlifeConfig.BehaviorState.BEING_HUNTED or st_val == WildlifeConfig.BehaviorState.WANDERING or st_val == WildlifeConfig.BehaviorState.FLEEING:
				st_val = WildlifeConfig.BehaviorState.IDLE
			var rec := _make_animal_record(a_id, species_id, int(spec.get("category", 0)), c, st_val)
			rec["home_cell"] = Vector2i(int(item.get("home_x", c.x)), int(item.get("home_y", c.y)))
			animals.append(rec)
			animals_by_id[a_id] = rec
			_spawn_actor_for_record(rec)
		return
	# Old save without wildlife section: deterministic init if biome_grid exists, else empty.
	generate_initial_population(world_data, nav)
