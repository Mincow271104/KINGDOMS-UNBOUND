class_name MonsterManager
extends RefCounted

const MonsterConfigScript := preload("res://scripts/world/monster_config.gd")
## Centralized manager for Phase 9 Hostile Monsters and Monster Nests.
## Handles deterministic placement, bounded AI, territory-based spawn suppression,
## Fog of War visibility, debug inspection, and persistence.

const MonsterActorScript := preload("res://scripts/world/monster_actor.gd")
const MonsterNestActorScript := preload("res://scripts/world/monster_nest_actor.gd")

var nests: Dictionary = {} # nest_id -> Dictionary
var monsters: Array[Dictionary] = []
var monster_actors: Dictionary = {} # monster_id -> MonsterActor
var nest_actors: Dictionary = {} # nest_id -> MonsterNestActor
var _container: Node = null
var _next_monster_seq: int = 1
var _scan_accumulator: float = 0.0
var _initialized_seed: int = -1
var _is_initialized: bool = false
var _roam_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _pending_return_queue: Array[Dictionary] = []
var _active_return_gen: Dictionary = {} # monster_id -> int
var _active_return_search: Dictionary = {} # monster_id -> Dictionary
var _non_combat_astar_calls_last_frame: int = 0
var _non_combat_astar_calls_total: int = 0
var _anim_time: float = 0.0
var _last_nav: GridNavigation = null

signal nest_discovered(nest_id: String, cell: Vector2i)
signal nest_destroyed_event(nest_id: String, cell: Vector2i)
signal monster_killed_event(monster_id: String, species_id: String, cell: Vector2i)

func set_container(container: Node) -> void:
	_container = container
	_sync_all_actors()

func clear_all() -> void:
	for a in monster_actors.values():
		if a != null and is_instance_valid(a):
			a.queue_free()
	for na in nest_actors.values():
		if na != null and is_instance_valid(na):
			na.queue_free()
	monster_actors.clear()
	nest_actors.clear()
	nests.clear()
	monsters.clear()
	_next_monster_seq = 1
	_scan_accumulator = 0.0
	_initialized_seed = -1
	_is_initialized = false
	_roam_rng = RandomNumberGenerator.new()
	_pending_return_queue.clear()
	_active_return_gen.clear()
	_active_return_search.clear()
	_non_combat_astar_calls_last_frame = 0
	_non_combat_astar_calls_total = 0
	_anim_time = 0.0
	_last_nav = null

func get_living_monster_count() -> int:
	var c := 0
	for m in monsters:
		if int(m.get("state", MonsterConfigScript.MonsterAIState.DEAD)) != MonsterConfigScript.MonsterAIState.DEAD and float(m.get("health", 0.0)) > 0.0:
			c += 1
	return c

func get_living_count_for_nest(nest_id: String) -> int:
	var c := 0
	for m in monsters:
		if str(m.get("home_nest_id", "")) == nest_id and int(m.get("state", MonsterConfigScript.MonsterAIState.DEAD)) != MonsterConfigScript.MonsterAIState.DEAD and float(m.get("health", 0.0)) > 0.0:
			c += 1
	return c

func get_monster_record(m_id: String) -> Dictionary:
	for m in monsters:
		if str(m.get("id", "")) == m_id:
			return m
	return {}

func get_monster_actor(m_id: String) -> Node2D:
	var a = monster_actors.get(m_id, null)
	return a if (a != null and is_instance_valid(a)) else null

func get_nest_actor(n_id: String) -> Node2D:
	var na = nest_actors.get(n_id, null)
	return na if (na != null and is_instance_valid(na)) else null

func get_monster_actor_at(cell: Vector2i) -> Node2D:
	for m in monsters:
		if int(m.get("state", MonsterConfigScript.MonsterAIState.DEAD)) != MonsterConfigScript.MonsterAIState.DEAD and m.get("cell") == cell:
			return get_monster_actor(str(m.get("id", "")))
	return null

func get_nest_actor_at(cell: Vector2i) -> Node2D:
	for nid in nests.keys():
		var nd: Dictionary = nests[nid]
		if nd.get("cell") == cell:
			return get_nest_actor(str(nid))
	return null

func get_all_nests() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for nd in nests.values():
		out.append(nd)
	return out

func get_living_monsters() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in monsters:
		if int(m.get("state", MonsterConfigScript.MonsterAIState.DEAD)) != MonsterConfigScript.MonsterAIState.DEAD and float(m.get("health", 0.0)) > 0.0:
			out.append(m)
	return out

func _is_cell_blocked_for_placement(cell: Vector2i, world_data: WorldGenerator.WorldData, nav: GridNavigation, territory_mgr: Object, poi_cells: Dictionary, resource_cells: Dictionary, prop_cells: Dictionary) -> bool:
	if not IsoMath.is_in_bounds(cell):
		return true
	if nav != null and not nav.is_cell_walkable(cell):
		return true
	if world_data == null:
		return true
	var t_type: int = int(world_data.terrain[cell.x][cell.y])
	if t_type == WorldGenerator.TerrainType.WATER or t_type == WorldGenerator.TerrainType.MOUNTAINS:
		return true
	if world_data.occupancy[cell.x][cell.y]:
		return true
	if territory_mgr != null and territory_mgr.has_method("is_cell_owned") and bool(territory_mgr.is_cell_owned(cell)):
		return true
	if IsoMath.grid_distance(cell, world_data.center_spawn) < MonsterConfigScript.SETTLEMENT_EXCLUSION_RADIUS:
		return true
	if poi_cells.has(cell) or resource_cells.has(cell) or prop_cells.has(cell):
		return true
	# Protect bridge decks
	if world_data.get("bridges") != null:
		for br in world_data.bridges:
			var b_cells: Array = br.get("cells", [])
			if b_cells.has(cell):
				return true
	return false

func _count_walkable_neighbors(cell: Vector2i, nav: GridNavigation) -> int:
	if nav == null:
		return 0
	var count := 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nc: Vector2i = cell + d
		if IsoMath.is_in_bounds(nc) and nav.is_cell_walkable(nc):
			count += 1
	return count

func generate_initial_world(world_data: WorldGenerator.WorldData, nav: GridNavigation, territory_mgr: Object = null, poi_mgr: Object = null, natural_resource_mgr: Object = null) -> void:
	clear_all()
	if world_data == null:
		return
	_last_nav = nav
	_initialized_seed = int(world_data.seed_value)
	_is_initialized = true
	_roam_rng.seed = int(world_data.seed_value) + MonsterConfigScript.MONSTER_RNG_SALT + 101

	# Safe legacy V1-V4 fallback: do not fabricate biomes
	if world_data.biome_grid.is_empty():
		return

	var poi_cells: Dictionary = {}
	if poi_mgr != null and poi_mgr.has_method("get_all_pois"):
		for p in poi_mgr.get_all_pois():
			if p != null:
				poi_cells[p.cell] = true

	var resource_cells: Dictionary = {}
	if natural_resource_mgr != null and natural_resource_mgr.get("nodes_by_cell") != null:
		for rc in natural_resource_mgr.nodes_by_cell.keys():
			resource_cells[rc] = true

	var prop_cells: Dictionary = {}
	if world_data.get("props") != null:
		for pr in world_data.props:
			if pr is Dictionary and pr.has("cell"):
				prop_cells[pr["cell"]] = true

	var nest_rng := RandomNumberGenerator.new()
	nest_rng.seed = int(world_data.seed_value) + MonsterConfigScript.NEST_RNG_SALT
	var monster_rng := RandomNumberGenerator.new()
	monster_rng.seed = int(world_data.seed_value) + MonsterConfigScript.MONSTER_RNG_SALT

	var target_nests: int = nest_rng.randi_range(MonsterConfigScript.MIN_INITIAL_NESTS, MonsterConfigScript.MAX_INITIAL_NESTS)
	var candidates: Array[Vector2i] = []
	var w: int = world_data.map_width
	var h: int = world_data.map_height
	for x in range(2, w - 2):
		for y in range(2, h - 2):
			var c := Vector2i(x, y)
			if _is_cell_blocked_for_placement(c, world_data, nav, territory_mgr, poi_cells, resource_cells, prop_cells):
				continue
			if _count_walkable_neighbors(c, nav) < 2:
				continue
			var biome: int = int(world_data.biome_grid[x][y])
			if MonsterConfigScript.get_species_for_biome(biome).is_empty():
				continue
			candidates.append(c)

	# Deterministic Fisher-Yates shuffle
	for i in range(candidates.size() - 1, 0, -1):
		var j := nest_rng.randi_range(0, i)
		var tmp := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp

	var placed_nest_cells: Array[Vector2i] = []
	var nest_idx := 0
	for c in candidates:
		if placed_nest_cells.size() >= target_nests:
			break
		var too_close := false
		for pc in placed_nest_cells:
			if IsoMath.grid_distance(c, pc) < MonsterConfigScript.MIN_NEST_SPACING:
				too_close = true
				break
		if too_close:
			continue
		for pcell in poi_cells.keys():
			if IsoMath.grid_distance(c, pcell) < 6:
				too_close = true
				break
		if too_close:
			continue

		nest_idx += 1
		var biome: int = int(world_data.biome_grid[c.x][c.y])
		var sp_options: Array[String] = MonsterConfigScript.get_species_for_biome(biome)
		var sp_id: String = sp_options[nest_rng.randi_range(0, sp_options.size() - 1)]
		var nid := "nest_%d" % nest_idx
		var spec := MonsterConfigScript.get_species_def(sp_id)
		nests[nid] = {
			"id": nid,
			"species_id": sp_id,
			"name": str(spec.get("nest_name", "Ổ Quái Vật")),
			"cell": c,
			"shared_anchor_cell": c,
			"needs_shared_anchor_init": false,
			"health": MonsterConfigScript.NEST_MAX_HEALTH,
			"max_health": MonsterConfigScript.NEST_MAX_HEALTH,
			"is_destroyed": false,
			"spawn_timer_hours": 0.0,
			"discovered": false,
		}
		placed_nest_cells.append(c)

		# Initial monsters for this nest (1-2)
		var m_count: int = monster_rng.randi_range(MonsterConfigScript.INITIAL_MONSTERS_MIN, MonsterConfigScript.INITIAL_MONSTERS_MAX)
		for _k in range(m_count):
			if get_living_monster_count() >= MonsterConfigScript.GLOBAL_MONSTER_CAP:
				break
			if get_living_count_for_nest(nid) >= MonsterConfigScript.LOCAL_MONSTER_CAP_PER_NEST:
				break
			var spawn_c := _find_spawn_cell_near(c, sp_id, world_data, nav, territory_mgr, monster_rng)
			if spawn_c != Vector2i(-1, -1):
				_create_monster_record(sp_id, spawn_c, nid, c)

	_sync_all_actors()

func _find_spawn_cell_near(nest_cell: Vector2i, species_id: String, world_data: WorldGenerator.WorldData, nav: GridNavigation, territory_mgr: Object, rng: RandomNumberGenerator = null) -> Vector2i:
	if world_data == null or nav == null or world_data.biome_grid.is_empty():
		return Vector2i(-1, -1)
	var allowed: Array = MonsterConfigScript.get_species_def(species_id).get("allowed_biomes", [])
	var valid: Array[Vector2i] = []
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var c := nest_cell + Vector2i(dx, dy)
			if not IsoMath.is_in_bounds(c):
				continue
			if not nav.is_cell_walkable(c):
				continue
			if world_data.occupancy[c.x][c.y]:
				continue
			if territory_mgr != null and territory_mgr.has_method("is_cell_owned") and bool(territory_mgr.is_cell_owned(c)):
				continue
			var b: int = int(world_data.biome_grid[c.x][c.y])
			if not allowed.has(b):
				continue
			valid.append(c)
	if valid.is_empty():
		return Vector2i(-1, -1)
	if rng != null:
		return valid[rng.randi_range(0, valid.size() - 1)]
	return valid[0]

func _roll_idle_duration(species_id: String) -> float:
	var spec := MonsterConfigScript.get_species_def(species_id)
	var idle_min: float = float(spec.get("idle_min", 2.0))
	var idle_max: float = float(spec.get("idle_max", 4.5))
	return _roam_rng.randf_range(idle_min, maxf(idle_min, idle_max))

func _create_monster_record(species_id: String, cell: Vector2i, home_nest_id: String, anchor_cell: Vector2i) -> Dictionary:
	var spec := MonsterConfigScript.get_species_def(species_id)
	var mid := "monster_%d" % _next_monster_seq
	_next_monster_seq += 1
	var max_hp: float = float(spec.get("max_health", 75.0))
	var rec := {
		"id": mid,
		"species_id": species_id,
		"cell": cell,
		"prev_cell": cell,
		"move_progress": 1.0,
		"facing_left": false,
		"home_nest_id": home_nest_id,
		"anchor_cell": anchor_cell,
		"is_displaced": false,
		"health": max_hp,
		"max_health": max_hp,
		"armor": float(spec.get("armor", 0.0)),
		"attack_damage": float(spec.get("attack_damage", 14.0)),
		"attack_range": int(spec.get("attack_range", 1)),
		"attack_cooldown": float(spec.get("attack_cooldown", 1.0)),
		"attack_cooldown_remaining": 0.0,
		"move_step_duration": float(spec.get("move_step_duration", 0.5)),
		"roam_step_duration": float(spec.get("roam_step_duration", 0.65)),
		"step_accumulator": 0.0,
		"state": MonsterConfigScript.MonsterAIState.IDLE,
		"state_timer": _roll_idle_duration(species_id),
		"alert_visual_timer": 0.0,
		"return_retry_timer": 0.0,
		"return_req_gen": 0,
		"needs_return_retry": false,
		"target_unit_id": "",
		"cached_path": [] as Array[Vector2i],
	}
	monsters.append(rec)
	return rec

func _sync_all_actors() -> void:
	if _container == null or not is_instance_valid(_container):
		return
	for nid in nests.keys():
		var nd: Dictionary = nests[nid]
		var na = nest_actors.get(nid, null)
		if na == null or not is_instance_valid(na):
			na = MonsterNestActorScript.new()
			na.name = nid
			_container.add_child(na)
			nest_actors[nid] = na
			na.nest_damaged.connect(_on_nest_damaged)
			na.nest_destroyed.connect(_on_nest_destroyed)
		na.configure(nid, str(nd["species_id"]), nd["cell"], float(nd["health"]), float(nd["max_health"]), bool(nd["is_destroyed"]))

	for m in monsters:
		var mid := str(m["id"])
		var alive := int(m.get("state", MonsterConfigScript.MonsterAIState.DEAD)) != MonsterConfigScript.MonsterAIState.DEAD and float(m.get("health", 0.0)) > 0.0
		var ma = monster_actors.get(mid, null)
		if not alive:
			if ma != null and is_instance_valid(ma):
				ma.is_alive = false
				ma.health = 0.0
				ma.queue_free()
				monster_actors.erase(mid)
			continue
		if ma == null or not is_instance_valid(ma):
			ma = MonsterActorScript.new()
			ma.name = mid
			_container.add_child(ma)
			monster_actors[mid] = ma
			ma.monster_damaged.connect(_on_monster_damaged)
			ma.monster_died.connect(_on_monster_died)
		ma.configure(mid, str(m["species_id"]), m["cell"], str(m["home_nest_id"]), float(m["health"]), float(m["max_health"]), float(m["armor"]), int(m["state"]))

func _on_monster_damaged(m_id: String, _amt: float, cur_hp: float, _max_hp: float, _atk_id: String) -> void:
	for m in monsters:
		if str(m["id"]) == m_id:
			m["health"] = cur_hp
			break

func _on_monster_died(m_id: String, _killer_id: String) -> void:
	for i in range(monsters.size() - 1, -1, -1):
		if str(monsters[i]["id"]) == m_id:
			var m := monsters[i]
			if int(m["state"]) == MonsterConfigScript.MonsterAIState.DEAD:
				return
			m["state"] = MonsterConfigScript.MonsterAIState.DEAD
			m["health"] = 0.0
			m["target_unit_id"] = ""
			m["cached_path"] = [] as Array[Vector2i]
			_invalidate_return_request(m)
			var sp := str(m["species_id"])
			var c: Vector2i = m["cell"]
			monsters.remove_at(i)
			var ma = monster_actors.get(m_id, null)
			if ma != null and is_instance_valid(ma):
				ma.is_alive = false
				ma.queue_free()
			monster_actors.erase(m_id)
			monster_killed_event.emit(m_id, sp, c)
			return

func _on_nest_damaged(n_id: String, _amt: float, cur_hp: float, _max_hp: float, _atk_id: String) -> void:
	if nests.has(n_id):
		nests[n_id]["health"] = cur_hp

func _compute_shared_nest_anchor(nest_cell: Vector2i, nav: GridNavigation) -> Vector2i:
	if nav == null:
		return nest_cell
	if IsoMath.is_in_bounds(nest_cell) and nav.is_cell_walkable(nest_cell):
		return nest_cell
	for r in range(1, MonsterConfigScript.SHARED_ANCHOR_SPIRAL_MAX_RADIUS + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) + absi(dy) != r:
					continue
				var c := nest_cell + Vector2i(dx, dy)
				if IsoMath.is_in_bounds(c) and nav.is_cell_walkable(c):
					return c
	return nest_cell

func _finalize_destroyed_nest_anchors(nav: GridNavigation) -> void:
	if nav == null:
		return
	for nid in nests.keys():
		var nd: Dictionary = nests[nid]
		if not bool(nd.get("is_destroyed", false)):
			continue
		if not bool(nd.get("needs_shared_anchor_init", false)):
			continue
		var shared: Vector2i = _compute_shared_nest_anchor(nd["cell"], nav)
		nd["shared_anchor_cell"] = shared
		nd["needs_shared_anchor_init"] = false
		for m in monsters:
			if str(m.get("home_nest_id", "")) == str(nid) and int(m.get("state", MonsterConfigScript.MonsterAIState.DEAD)) != MonsterConfigScript.MonsterAIState.DEAD:
				m["is_displaced"] = true
				m["anchor_cell"] = shared

func _on_nest_destroyed(n_id: String, _killer_id: String) -> void:
	if nests.has(n_id):
		var nd: Dictionary = nests[n_id]
		if bool(nd.get("is_destroyed", false)):
			return
		nd["health"] = 0.0
		nd["is_destroyed"] = true
		if _last_nav != null:
			var shared: Vector2i = _compute_shared_nest_anchor(nd["cell"], _last_nav)
			nd["shared_anchor_cell"] = shared
			nd["needs_shared_anchor_init"] = false
			for m in monsters:
				if str(m.get("home_nest_id", "")) == n_id and int(m.get("state", MonsterConfigScript.MonsterAIState.DEAD)) != MonsterConfigScript.MonsterAIState.DEAD:
					m["is_displaced"] = true
					m["anchor_cell"] = shared
		else:
			nd["needs_shared_anchor_init"] = true
			for m in monsters:
				if str(m.get("home_nest_id", "")) == n_id and int(m.get("state", MonsterConfigScript.MonsterAIState.DEAD)) != MonsterConfigScript.MonsterAIState.DEAD:
					m["is_displaced"] = true
		nest_destroyed_event.emit(n_id, nd["cell"])

func _get_nest_anchor(m: Dictionary) -> Vector2i:
	var nid := str(m.get("home_nest_id", ""))
	if nests.has(nid):
		var nd: Dictionary = nests[nid]
		if not bool(nd.get("is_destroyed", false)):
			return nd["cell"]
		if not bool(nd.get("needs_shared_anchor_init", false)) and nd.has("shared_anchor_cell"):
			return nd["shared_anchor_cell"]
	return m.get("anchor_cell", m.get("cell", Vector2i.ZERO))

func _is_nest_alive(m: Dictionary) -> bool:
	var nid := str(m.get("home_nest_id", ""))
	return nests.has(nid) and not bool(nests[nid].get("is_destroyed", false))

func _path_distance(a: Vector2i, b: Vector2i, nav: GridNavigation) -> int:
	if a == b:
		return 0
	if nav == null:
		return IsoMath.grid_distance(a, b)
	var p: Array[Vector2i] = nav.find_path(a, b)
	if p.is_empty():
		return 999999
	return maxi(0, p.size() - 1)

func get_non_combat_astar_calls_last_frame() -> int:
	return _non_combat_astar_calls_last_frame

func get_non_combat_astar_calls_total() -> int:
	return _non_combat_astar_calls_total

func get_pending_return_queue_size() -> int:
	return _pending_return_queue.size()

func _invalidate_return_request(m: Dictionary) -> void:
	var mid := str(m.get("id", ""))
	m["return_req_gen"] = int(m.get("return_req_gen", 0)) + 1
	_active_return_gen.erase(mid)
	_active_return_search.erase(mid)

func _enqueue_return_request(m: Dictionary) -> void:
	var mid := str(m.get("id", ""))
	if mid.is_empty():
		return
	if int(m.get("state", MonsterConfigScript.MonsterAIState.DEAD)) != MonsterConfigScript.MonsterAIState.RETURNING:
		return
	if not (m.get("cached_path", []) as Array).is_empty():
		return
	if float(m.get("return_retry_timer", 0.0)) > 0.0:
		return
	if _active_return_gen.has(mid):
		return
	var gen: int = int(m.get("return_req_gen", 0)) + 1
	m["return_req_gen"] = gen
	_active_return_gen[mid] = gen
	_pending_return_queue.append({"monster_id": mid, "gen": gen})

func _build_return_candidates(anchor: Vector2i, effective_radius: int, nav: GridNavigation) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if nav == null or not IsoMath.is_in_bounds(anchor):
		return out
	if nav.is_cell_walkable(anchor):
		out.append(anchor)
		return out
	for r in range(1, maxi(1, effective_radius) + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) + absi(dy) != r:
					continue
				var c := anchor + Vector2i(dx, dy)
				if IsoMath.is_in_bounds(c) and nav.is_cell_walkable(c):
					out.append(c)
	return out

func _process_pending_return_queue(nav: GridNavigation, budget_left: int) -> int:
	if nav == null or budget_left <= 0 or _pending_return_queue.is_empty():
		return budget_left
	while budget_left > 0 and not _pending_return_queue.is_empty():
		var entry: Dictionary = _pending_return_queue.pop_front()
		var mid := str(entry.get("monster_id", ""))
		var gen: int = int(entry.get("gen", -1))
		var m := get_monster_record(mid)
		if m.is_empty():
			continue
		var st: int = int(m.get("state", MonsterConfigScript.MonsterAIState.DEAD))
		var hp: float = float(m.get("health", 0.0))
		if st == MonsterConfigScript.MonsterAIState.DEAD or hp <= 0.0:
			continue
		if st != MonsterConfigScript.MonsterAIState.RETURNING:
			continue
		if not (m.get("cached_path", []) as Array).is_empty():
			continue
		var anchor: Vector2i = _get_nest_anchor(m)
		if not IsoMath.is_in_bounds(anchor):
			continue
		if int(_active_return_gen.get(mid, -1)) != gen or int(m.get("return_req_gen", 0)) != gen:
			continue

		var sp := str(m.get("species_id", "forest_stalker"))
		var disp: bool = bool(m.get("is_displaced", false))
		var eff_radius: int = MonsterConfigScript.get_effective_roam_radius(sp, disp)

		var search_state: Dictionary = _active_return_search.get(mid, {})
		if search_state.is_empty() or int(search_state.get("gen", -1)) != gen:
			var cands := _build_return_candidates(anchor, eff_radius, nav)
			var href: Vector2i = anchor if nav.is_cell_walkable(anchor) else (cands[0] if not cands.is_empty() else anchor)
			search_state = {
				"gen": gen,
				"candidates": cands,
				"home_ref_cell": href,
				"cand_idx": 0,
				"home_conn_verified": false,
			}
			_active_return_search[mid] = search_state

		var candidates: Array = search_state["candidates"]
		var href_cell: Vector2i = search_state["home_ref_cell"]
		var cand_idx: int = int(search_state["cand_idx"])
		var home_conn_verified: bool = bool(search_state["home_conn_verified"])
		var m_cell: Vector2i = m["cell"]
		var finished_or_arrived := false

		while cand_idx < candidates.size() and budget_left > 0:
			var c: Vector2i = candidates[cand_idx]
			if not home_conn_verified:
				if c == href_cell:
					home_conn_verified = true
				else:
					budget_left -= 1
					_non_combat_astar_calls_last_frame += 1
					_non_combat_astar_calls_total += 1
					var conn_path: Array[Vector2i] = nav.find_path(c, href_cell)
					var conn_ok: bool = not conn_path.is_empty()
					if conn_ok:
						for p_cell in conn_path:
							if IsoMath.grid_distance(p_cell, anchor) > eff_radius:
								conn_ok = false
								break
					if conn_ok:
						home_conn_verified = true
					else:
						cand_idx += 1
						home_conn_verified = false
						continue

			if home_conn_verified:
				if m_cell == c:
					# start == goal: already at valid operational destination
					if int(_active_return_gen.get(mid, -1)) == gen:
						_active_return_gen.erase(mid)
					_active_return_search.erase(mid)
					m["return_req_gen"] = int(m.get("return_req_gen", 0)) + 1
					m["cached_path"] = [] as Array[Vector2i]
					m["return_retry_timer"] = 0.0
					m["needs_return_retry"] = false
					m["state"] = MonsterConfigScript.MonsterAIState.IDLE
					m["state_timer"] = _roll_idle_duration(sp)
					finished_or_arrived = true
					break
				elif budget_left > 0:
					budget_left -= 1
					_non_combat_astar_calls_last_frame += 1
					_non_combat_astar_calls_total += 1
					var ret_path: Array[Vector2i] = nav.find_path(m_cell, c)
					if not ret_path.is_empty():
						if ret_path[0] == m_cell:
							ret_path.remove_at(0)
						if int(_active_return_gen.get(mid, -1)) == gen:
							_active_return_gen.erase(mid)
						_active_return_search.erase(mid)
						m["cached_path"] = ret_path
						m["needs_return_retry"] = false
						finished_or_arrived = true
						break
					else:
						cand_idx += 1
						home_conn_verified = false

		if finished_or_arrived:
			continue

		if cand_idx >= candidates.size():
			# All candidates exhausted -> search failed
			if int(_active_return_gen.get(mid, -1)) == gen:
				_active_return_gen.erase(mid)
			_active_return_search.erase(mid)
			m["return_req_gen"] = int(m.get("return_req_gen", 0)) + 1
			m["return_retry_timer"] = MonsterConfigScript.RETURN_RETRY_BACKOFF_SEC
			m["needs_return_retry"] = true
			m["state"] = MonsterConfigScript.MonsterAIState.IDLE
			m["state_timer"] = MonsterConfigScript.RETURN_RETRY_BACKOFF_SEC
		else:
			# Budget exhausted mid-search -> suspend & resume next frame at head of queue
			search_state["cand_idx"] = cand_idx
			search_state["home_conn_verified"] = home_conn_verified
			_active_return_search[mid] = search_state
			_pending_return_queue.push_front(entry)
			break

	return budget_left

static func is_valid_transition_cell(cell: Vector2i, species_id: String, world_data: WorldGenerator.WorldData, nav: GridNavigation) -> bool:
	if nav == null or not nav.is_cell_walkable(cell):
		return false
	if world_data == null or world_data.biome_grid.is_empty():
		return true
	var spec := MonsterConfigScript.get_species_def(species_id)
	var allowed_biomes: Array = spec.get("allowed_biomes", [])
	var trans_biomes: Array = spec.get("allowed_transition_biomes", [])
	var b: int = world_data.get_biome(cell)
	if not trans_biomes.has(b):
		return false
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nc: Vector2i = cell + d
		if IsoMath.is_in_bounds(nc) and allowed_biomes.has(world_data.get_biome(nc)):
			return true
	return false

func _pick_roam_path(m: Dictionary, anchor: Vector2i, world_data: WorldGenerator.WorldData, nav: GridNavigation, budget_left: int) -> Dictionary:
	var result := {"path": [] as Array[Vector2i], "budget_left": budget_left}
	if nav == null or budget_left <= 0:
		return result
	var sp := str(m.get("species_id", "forest_stalker"))
	var spec := MonsterConfigScript.get_species_def(sp)
	var disp: bool = bool(m.get("is_displaced", false))
	var eff_radius: int = MonsterConfigScript.get_effective_roam_radius(sp, disp)
	var hop_min: int = int(spec.get("hop_min", 1))
	var hop_max: int = int(spec.get("hop_max", 3))
	var allowed_biomes: Array = spec.get("allowed_biomes", [])
	var max_trans_steps: int = int(spec.get("allowed_transition_steps", 1))
	var has_biomes: bool = world_data != null and not world_data.biome_grid.is_empty()
	var m_cell: Vector2i = m["cell"]
	var prev_cell: Vector2i = m.get("prev_cell", m_cell)

	var pool: Array[Vector2i] = []
	for dx in range(-eff_radius, eff_radius + 1):
		for dy in range(-eff_radius, eff_radius + 1):
			var c := anchor + Vector2i(dx, dy)
			if c == m_cell or c == prev_cell:
				continue
			if not IsoMath.is_in_bounds(c):
				continue
			if IsoMath.grid_distance(c, anchor) > eff_radius:
				continue
			var hop_d: int = IsoMath.grid_distance(m_cell, c)
			if hop_d < hop_min or hop_d > hop_max:
				continue
			if not nav.is_cell_walkable(c):
				continue
			if has_biomes:
				var cb: int = world_data.get_biome(c)
				if not allowed_biomes.has(cb) and not is_valid_transition_cell(c, sp, world_data, nav):
					continue
			pool.append(c)

	if pool.is_empty():
		return result

	# Deterministic Fisher-Yates shuffle using dedicated _roam_rng, then score preferred biomes first
	for i in range(pool.size() - 1, 0, -1):
		var j := _roam_rng.randi_range(0, i)
		var tmp := pool[i]
		pool[i] = pool[j]
		pool[j] = tmp

	if has_biomes:
		var pref_pool: Array[Vector2i] = []
		var trans_pool: Array[Vector2i] = []
		for c in pool:
			if allowed_biomes.has(world_data.get_biome(c)):
				pref_pool.append(c)
			else:
				trans_pool.append(c)
		pool = pref_pool + trans_pool

	var max_samples: int = mini(pool.size(), MonsterConfigScript.ROAM_CANDIDATE_SAMPLE_LIMIT)
	var checks_done: int = 0
	for idx in range(max_samples):
		if budget_left <= 0 or checks_done >= MonsterConfigScript.ROAM_ASTAR_CHECK_LIMIT:
			break
		var cand: Vector2i = pool[idx]
		budget_left -= 1
		checks_done += 1
		_non_combat_astar_calls_last_frame += 1
		_non_combat_astar_calls_total += 1
		var p: Array[Vector2i] = nav.find_path(m_cell, cand)
		if p.is_empty():
			continue
		if p[0] == m_cell:
			p.remove_at(0)
		if p.is_empty():
			continue

		var valid := true
		var trans_count := 0
		for step_c in p:
			if not nav.is_cell_walkable(step_c):
				valid = false
				break
			if IsoMath.grid_distance(step_c, anchor) > eff_radius:
				valid = false
				break
			if has_biomes:
				var sb: int = world_data.get_biome(step_c)
				if not allowed_biomes.has(sb):
					if not is_valid_transition_cell(step_c, sp, world_data, nav):
						valid = false
						break
					trans_count += 1
					if trans_count > max_trans_steps:
						valid = false
						break
		if valid:
			result["path"] = p
			result["budget_left"] = budget_left
			return result

	result["budget_left"] = budget_left
	return result

func update_simulation(delta: float, speed_mult: float, world_data: WorldGenerator.WorldData, nav: GridNavigation, tactical_mgr: Object, territory_mgr: Object, fog: FogOfWar = null, debug_fog: bool = false) -> void:
	if speed_mult <= 0.0 or delta <= 0.0:
		return

	_last_nav = nav
	_non_combat_astar_calls_last_frame = 0
	var non_combat_budget: int = MonsterConfigScript.MAX_NON_COMBAT_ASTAR_PER_FRAME
	var dt: float = delta * speed_mult
	_anim_time += dt

	if nav != null:
		_finalize_destroyed_nest_anchors(nav)

	# 1. Nest Discovery & Spawning (36 in-game hours interval; 7.5 real sec = 1h at 1x)
	var delta_hours: float = dt / 7.5
	for nid in nests.keys():
		var nd: Dictionary = nests[nid]
		if fog != null and not bool(nd.get("discovered", false)) and fog.is_explored(nd["cell"]):
			nd["discovered"] = true
			nest_discovered.emit(nid, nd["cell"])
		if bool(nd.get("is_destroyed", false)):
			continue
		var nest_owned: bool = territory_mgr != null and territory_mgr.has_method("is_cell_owned") and bool(territory_mgr.is_cell_owned(nd["cell"]))
		if nest_owned:
			# Territory-based suppression: cap timer, do not spawn, do not accumulate catch-up bursts
			nd["spawn_timer_hours"] = minf(float(nd.get("spawn_timer_hours", 0.0)), MonsterConfigScript.RESPAWN_INTERVAL_HOURS)
			continue

		nd["spawn_timer_hours"] = float(nd.get("spawn_timer_hours", 0.0)) + delta_hours
		if float(nd["spawn_timer_hours"]) >= MonsterConfigScript.RESPAWN_INTERVAL_HOURS:
			if get_living_count_for_nest(nid) < MonsterConfigScript.LOCAL_MONSTER_CAP_PER_NEST and get_living_monster_count() < MonsterConfigScript.GLOBAL_MONSTER_CAP:
				var sc := _find_spawn_cell_near(nd["cell"], str(nd["species_id"]), world_data, nav, territory_mgr, null)
				if sc != Vector2i(-1, -1):
					_create_monster_record(str(nd["species_id"]), sc, nid, nd["cell"])
					nd["spawn_timer_hours"] = 0.0
					_sync_all_actors()
				else:
					nd["spawn_timer_hours"] = MonsterConfigScript.RESPAWN_INTERVAL_HOURS
			else:
				nd["spawn_timer_hours"] = MonsterConfigScript.RESPAWN_INTERVAL_HOURS

	# 2. Throttled AI target scan (only player military units, NEVER citizens or civilian buildings)
	_scan_accumulator += dt
	var do_scan: bool = _scan_accumulator >= 0.35
	if do_scan:
		_scan_accumulator = 0.0

	var military_units: Array = []
	if do_scan and tactical_mgr != null and tactical_mgr.has_method("get_all_units"):
		military_units = tactical_mgr.get_all_units()

	var roam_ready_monsters: Array[Dictionary] = []

	for m in monsters:
		var st: int = int(m.get("state", MonsterConfigScript.MonsterAIState.DEAD))
		if st == MonsterConfigScript.MonsterAIState.DEAD or float(m.get("health", 0.0)) <= 0.0:
			continue
		# Normalize deprecated legacy states if encountered at runtime
		if st == MonsterConfigScript.MonsterAIState.GUARDING or st == MonsterConfigScript.MonsterAIState.ALERT:
			st = MonsterConfigScript.MonsterAIState.IDLE
			m["state"] = st

		m["attack_cooldown_remaining"] = maxf(0.0, float(m.get("attack_cooldown_remaining", 0.0)) - dt)
		m["alert_visual_timer"] = maxf(0.0, float(m.get("alert_visual_timer", 0.0)) - dt)
		m["return_retry_timer"] = maxf(0.0, float(m.get("return_retry_timer", 0.0)) - dt)

		var sp := str(m.get("species_id", "forest_stalker"))
		var disp: bool = bool(m.get("is_displaced", false))
		var eff_radius: int = MonsterConfigScript.get_effective_roam_radius(sp, disp)
		var eff_thresh: int = MonsterConfigScript.get_effective_return_threshold(sp, disp)
		var m_cell: Vector2i = m["cell"]
		var anchor: Vector2i = _get_nest_anchor(m)

		# Resolve current target unit (military only)
		var tgt_id := str(m.get("target_unit_id", ""))
		var tgt_unit: Node2D = null
		if not tgt_id.is_empty() and tactical_mgr != null and tactical_mgr.has_method("get_unit"):
			var cand = tactical_mgr.get_unit(tgt_id)
			if cand != null and is_instance_valid(cand) and bool(cand.get("is_alive")):
				tgt_unit = cand
			else:
				m["target_unit_id"] = ""
				tgt_id = ""

		if do_scan:
			# Check combat pursuit leash (<= 12 path cells from anchor; applies to CHASING/ATTACKING only)
			if st in [MonsterConfigScript.MonsterAIState.CHASING, MonsterConfigScript.MonsterAIState.ATTACKING]:
				var leash_dist: int = _path_distance(m_cell, anchor, nav)
				if leash_dist > MonsterConfigScript.MAX_PURSUIT_PATH_CELLS:
					m["target_unit_id"] = ""
					tgt_unit = null
					st = MonsterConfigScript.MonsterAIState.RETURNING
					m["cached_path"] = [] as Array[Vector2i]

			# Acquire nearest military unit within 6 path cells
			if tgt_unit == null:
				var can_chase: bool = true
				if st == MonsterConfigScript.MonsterAIState.RETURNING:
					# RETURNING may re-enter CHASING only if pursuit-leash condition also holds
					can_chase = _path_distance(m_cell, anchor, nav) <= MonsterConfigScript.MAX_PURSUIT_PATH_CELLS
				if can_chase:
					var best_u: Node2D = null
					var best_d: int = MonsterConfigScript.DETECTION_RADIUS_PATH_CELLS + 1
					for u in military_units:
						if u == null or not is_instance_valid(u) or not bool(u.get("is_alive")):
							continue
						var uc: Vector2i = u.get("current_cell")
						if IsoMath.grid_distance(m_cell, uc) > MonsterConfigScript.DETECTION_RADIUS_PATH_CELLS:
							continue
						var pd: int = _path_distance(m_cell, uc, nav)
						if pd <= MonsterConfigScript.DETECTION_RADIUS_PATH_CELLS and pd < best_d:
							best_d = pd
							best_u = u
					if best_u != null:
						if st == MonsterConfigScript.MonsterAIState.RETURNING:
							_invalidate_return_request(m)
						m["target_unit_id"] = str(best_u.get("unit_id"))
						tgt_unit = best_u
						if st != MonsterConfigScript.MonsterAIState.CHASING:
							m["alert_visual_timer"] = MonsterConfigScript.ALERT_VISUAL_DURATION
						st = MonsterConfigScript.MonsterAIState.CHASING
						m["cached_path"] = [] as Array[Vector2i]

		# State execution (Combat first, exempt from non-combat A* budget)
		if tgt_unit != null:
			var uc: Vector2i = tgt_unit.get("current_cell")
			var mdist: int = IsoMath.grid_distance(m_cell, uc)
			if mdist <= int(m.get("attack_range", 1)):
				st = MonsterConfigScript.MonsterAIState.ATTACKING
				m["cached_path"] = [] as Array[Vector2i]
				if float(m.get("attack_cooldown_remaining", 0.0)) <= 0.0:
					m["attack_cooldown_remaining"] = float(m.get("attack_cooldown", 1.0))
					if tgt_unit.has_method("take_damage"):
						tgt_unit.take_damage(float(m.get("attack_damage", 14.0)), str(m["id"]))
			else:
				if st != MonsterConfigScript.MonsterAIState.CHASING:
					m["alert_visual_timer"] = MonsterConfigScript.ALERT_VISUAL_DURATION
				st = MonsterConfigScript.MonsterAIState.CHASING
				if do_scan or (m["cached_path"] as Array).is_empty():
					if nav != null:
						var p: Array[Vector2i] = nav.find_path(m_cell, uc)
						if p.size() > 1:
							if p[0] == m_cell:
								p.remove_at(0)
							if not p.is_empty() and p[-1] == uc:
								p.remove_at(p.size() - 1)
							m["cached_path"] = p
						else:
							# Unreachable -> disengage and return
							m["target_unit_id"] = ""
							st = MonsterConfigScript.MonsterAIState.RETURNING
							m["cached_path"] = [] as Array[Vector2i]
		else:
			if st in [MonsterConfigScript.MonsterAIState.CHASING, MonsterConfigScript.MonsterAIState.ATTACKING]:
				st = MonsterConfigScript.MonsterAIState.RETURNING
				m["cached_path"] = [] as Array[Vector2i]
			elif st == MonsterConfigScript.MonsterAIState.IDLE:
				m["state_timer"] = maxf(0.0, float(m.get("state_timer", 0.0)) - dt)
				var retry_failed_return: bool = bool(m.get("needs_return_retry", false)) and float(m.get("return_retry_timer", 0.0)) <= 0.0
				if retry_failed_return or (float(m.get("state_timer", 0.0)) <= 0.0 and IsoMath.grid_distance(m_cell, anchor) > eff_thresh):
					if float(m.get("return_retry_timer", 0.0)) <= 0.0:
						st = MonsterConfigScript.MonsterAIState.RETURNING
						m["cached_path"] = [] as Array[Vector2i]
				elif float(m.get("state_timer", 0.0)) <= 0.0:
					roam_ready_monsters.append(m)
			elif st == MonsterConfigScript.MonsterAIState.ROAMING:
				if (m["cached_path"] as Array).is_empty():
					st = MonsterConfigScript.MonsterAIState.IDLE
					m["state_timer"] = _roll_idle_duration(sp)

		m["state"] = st
		if st == MonsterConfigScript.MonsterAIState.RETURNING and (m["cached_path"] as Array).is_empty():
			_enqueue_return_request(m)

	# 3. Process Global Non-Combat A* Budget (RETURNING strictly prioritized over ROAMING)
	non_combat_budget = _process_pending_return_queue(nav, non_combat_budget)

	for m in roam_ready_monsters:
		if int(m.get("state", MonsterConfigScript.MonsterAIState.DEAD)) != MonsterConfigScript.MonsterAIState.IDLE:
			continue
		var sp := str(m.get("species_id", "forest_stalker"))
		if non_combat_budget <= 0:
			m["state_timer"] = MonsterConfigScript.ROAM_BUDGET_DEFER_SEC
			continue
		var anchor: Vector2i = _get_nest_anchor(m)
		var roam_res := _pick_roam_path(m, anchor, world_data, nav, non_combat_budget)
		non_combat_budget = int(roam_res.get("budget_left", non_combat_budget))
		var rpath: Array = roam_res.get("path", [])
		if not rpath.is_empty():
			m["cached_path"] = rpath
			m["state"] = MonsterConfigScript.MonsterAIState.ROAMING
		else:
			m["state"] = MonsterConfigScript.MonsterAIState.IDLE
			m["state_timer"] = MonsterConfigScript.ROAM_BIOME_IDLE_RETRY_SEC

	# 4. Step movement along cached_path & sync presentation visuals
	for m in monsters:
		var st: int = int(m.get("state", MonsterConfigScript.MonsterAIState.DEAD))
		if st == MonsterConfigScript.MonsterAIState.DEAD or float(m.get("health", 0.0)) <= 0.0:
			continue
		var sp := str(m.get("species_id", "forest_stalker"))
		var disp: bool = bool(m.get("is_displaced", false))
		var eff_radius: int = MonsterConfigScript.get_effective_roam_radius(sp, disp)
		var anchor: Vector2i = _get_nest_anchor(m)

		var path_arr: Array = m.get("cached_path", [])
		var step_dur: float = maxf(0.1, float(m.get("roam_step_duration", 0.65)) if st == MonsterConfigScript.MonsterAIState.ROAMING else float(m.get("move_step_duration", 0.5)))

		if not path_arr.is_empty():
			m["step_accumulator"] = float(m.get("step_accumulator", 0.0)) + dt
			while float(m["step_accumulator"]) >= step_dur and not path_arr.is_empty():
				m["step_accumulator"] = float(m["step_accumulator"]) - step_dur
				var next_c: Vector2i = path_arr[0]
				if nav != null and not nav.is_cell_walkable(next_c):
					path_arr.clear()
					m["step_accumulator"] = 0.0
					if st == MonsterConfigScript.MonsterAIState.ROAMING:
						st = MonsterConfigScript.MonsterAIState.IDLE
						m["state"] = st
						m["state_timer"] = _roll_idle_duration(sp)
					break
				if st == MonsterConfigScript.MonsterAIState.CHASING:
					if IsoMath.grid_distance(next_c, anchor) > MonsterConfigScript.MAX_PURSUIT_PATH_CELLS and _path_distance(next_c, anchor, nav) > MonsterConfigScript.MAX_PURSUIT_PATH_CELLS:
						m["target_unit_id"] = ""
						st = MonsterConfigScript.MonsterAIState.RETURNING
						m["state"] = st
						path_arr.clear()
						_enqueue_return_request(m)
						break
				var old_c: Vector2i = m["cell"]
				m["prev_cell"] = old_c
				m["cell"] = next_c
				var p_old := IsoMath.map_to_local(old_c)
				var p_new := IsoMath.map_to_local(next_c)
				if p_new.x < p_old.x - 0.01:
					m["facing_left"] = true
				elif p_new.x > p_old.x + 0.01:
					m["facing_left"] = false
				path_arr.remove_at(0)

			m["cached_path"] = path_arr
			if path_arr.is_empty():
				m["step_accumulator"] = 0.0
				m["move_progress"] = 1.0
				m["prev_cell"] = m["cell"]
				if st == MonsterConfigScript.MonsterAIState.ROAMING:
					st = MonsterConfigScript.MonsterAIState.IDLE
					m["state"] = st
					m["state_timer"] = _roll_idle_duration(sp)
				elif st == MonsterConfigScript.MonsterAIState.RETURNING:
					if IsoMath.grid_distance(m["cell"], anchor) <= eff_radius and (nav == null or nav.is_cell_walkable(m["cell"])):
						st = MonsterConfigScript.MonsterAIState.IDLE
						m["state"] = st
						m["state_timer"] = _roll_idle_duration(sp)
						m["needs_return_retry"] = false
						_invalidate_return_request(m)
			else:
				m["move_progress"] = clampf(float(m["step_accumulator"]) / step_dur, 0.0, 1.0)
		else:
			m["step_accumulator"] = 0.0
			m["move_progress"] = 1.0
			m["prev_cell"] = m["cell"]

		var ma_sync = get_monster_actor(str(m["id"]))
		if ma_sync != null:
			if ma_sync.has_method("sync_visual"):
				ma_sync.sync_visual(
					m.get("prev_cell", m["cell"]),
					m["cell"],
					float(m.get("move_progress", 1.0)),
					int(m["state"]),
					bool(m.get("facing_left", false)),
					float(m.get("alert_visual_timer", 0.0)),
					_anim_time
				)
			else:
				ma_sync.ai_state = int(m["state"])

	refresh_visibility(fog, debug_fog)

func refresh_visibility(fog: FogOfWar, debug_fog: bool = false) -> void:
	for nid in nest_actors.keys():
		var na = nest_actors[nid]
		if na == null or not is_instance_valid(na):
			continue
		var nd: Dictionary = nests.get(nid, {})
		var c: Vector2i = nd.get("cell", Vector2i.ZERO)
		var show_nest: bool = debug_fog or bool(nd.get("discovered", false)) or (fog != null and fog.is_explored(c))
		na.visible = show_nest
	for mid in monster_actors.keys():
		var ma = monster_actors[mid]
		if ma == null or not is_instance_valid(ma):
			continue
		if not ma.is_alive:
			ma.visible = false
			continue
		var show_m: bool = debug_fog or (fog != null and fog.is_visible(ma.current_cell))
		ma.visible = show_m

func get_nest_record(n_id: String) -> Dictionary:
	return nests.get(n_id, {})

func inspect_cell(cell: Vector2i, world_data: WorldGenerator.WorldData, fog: FogOfWar, debug_fog: bool) -> Dictionary:
	# 1. Monster at cell
	for m in monsters:
		if int(m.get("state", MonsterConfigScript.MonsterAIState.DEAD)) == MonsterConfigScript.MonsterAIState.DEAD:
			continue
		if m.get("cell") == cell:
			var is_vis: bool = debug_fog or (fog != null and fog.is_visible(cell))
			if not is_vis:
				continue
			var spec := MonsterConfigScript.get_species_def(str(m["species_id"]))
			var biome_name := "-"
			if world_data != null and IsoMath.is_in_bounds(cell):
				biome_name = WildlifeConfig.biome_name(world_data.get_biome(cell))
			var nest_id: String = str(m.get("home_nest_id", ""))
			var nd: Dictionary = nests.get(nest_id, {})
			var nest_label: String = str(nd.get("name", spec.get("nest_name", "-")))
			return {
				"is_debug_inspect": debug_fog,
				"category": "monster",
				"id": str(m["id"]),
				"species_id": str(m["species_id"]),
				"cell": cell,
				"size": Vector2i(1, 1),
				"biome": biome_name,
				"armor": float(m.get("armor", spec.get("armor", 0.0))),
				"attack_damage": float(m.get("attack_damage", spec.get("attack_damage", 14.0))),
				"attack_cooldown": float(m.get("attack_cooldown", spec.get("attack_cooldown", 1.0))),
				"attack_range": int(m.get("attack_range", spec.get("attack_range", 1))),
				"detection_radius": int(spec.get("detection_radius", MonsterConfigScript.DETECTION_RADIUS_PATH_CELLS)),
				"max_pursuit_distance": int(spec.get("max_pursuit_distance", MonsterConfigScript.MAX_PURSUIT_PATH_CELLS)),
				"is_displaced": bool(m.get("is_displaced", false)),
				"home_nest_id": nest_id,
				"ai_state_int": int(m["state"]),
				"title": "%s%s" % [str(spec.get("display_name_vi", spec.get("display_name", m["species_id"]))), " [Debug]" if debug_fog else ""],
				"coords_text": "Tọa độ: (%d, %d) | Quần xã: %s" % [cell.x, cell.y, biome_name],
				"state_text": "Trạng thái: %s | Ổ: %s" % [MonsterConfigScript.get_ai_state_name(int(m["state"])), nest_label],
				"state_color": Color(0.95, 0.35, 0.35, 1.0),
				"detail_text": "HP: %d / %d | Sát thương: %d | Giáp: %.0f" % [int(m["health"]), int(m["max_health"]), int(m["attack_damage"]), float(m.get("armor", 0.0))],
				"show_bar": true,
				"bar_max": maxi(1, int(m["max_health"])),
				"bar_value": int(m["health"]),
			}
	# 2. Nest at cell
	for nid in nests.keys():
		var nd: Dictionary = nests[nid]
		if nd.get("cell") == cell:
			var is_vis_n: bool = debug_fog or bool(nd.get("discovered", false)) or (fog != null and fog.is_explored(cell))
			if not is_vis_n:
				continue
			var destroyed: bool = bool(nd.get("is_destroyed", false))
			var living_cnt: int = get_living_count_for_nest(nid)
			var rem_h: float = maxf(0.0, MonsterConfigScript.RESPAWN_INTERVAL_HOURS - float(nd.get("spawn_timer_hours", 0.0)))
			var biome_name_n: String = WildlifeConfig.biome_name(world_data.get_biome(cell)) if world_data != null else "-"
			return {
				"is_debug_inspect": debug_fog,
				"category": "monster_nest",
				"id": str(nid),
				"nest_id": str(nid),
				"species_id": str(nd["species_id"]),
				"cell": cell,
				"size": Vector2i(1, 1),
				"biome": biome_name_n,
				"is_destroyed": destroyed,
				"living_count": living_cnt,
				"monster_cap": MonsterConfigScript.LOCAL_MONSTER_CAP_PER_NEST,
				"spawn_timer_hours": float(nd.get("spawn_timer_hours", 0.0)),
				"respawn_interval_hours": MonsterConfigScript.RESPAWN_INTERVAL_HOURS,
				"title": "%s%s" % [str(nd["name"]), " [Debug]" if debug_fog else ""],
				"coords_text": "Tọa độ: (%d, %d) | Quần xã: %s | Quái sống: %d/%d" % [cell.x, cell.y, biome_name_n, living_cnt, MonsterConfigScript.LOCAL_MONSTER_CAP_PER_NEST],
				"state_text": "[ĐÃ PHÁ HỦY]" if destroyed else "[ĐANG HOẠT ĐỘNG]",
				"state_color": Color(0.65, 0.65, 0.65, 1.0) if destroyed else Color(0.95, 0.45, 0.25, 1.0),
				"detail_text": "Độ bền: %d / %d | Tái sinh sau: %.1fh" % [int(nd["health"]), int(nd["max_health"]), 0.0 if destroyed else rem_h],
				"show_bar": true,
				"bar_max": maxi(1, int(nd["max_health"])),
				"bar_value": int(nd["health"]),
			}
	return {}

func serialize() -> Dictionary:
	var n_arr: Array[Dictionary] = []
	for nid in nests.keys():
		var nd: Dictionary = nests[nid]
		var c: Vector2i = nd["cell"]
		var sac: Vector2i = nd.get("shared_anchor_cell", c)
		n_arr.append({
			"id": str(nd["id"]),
			"species_id": str(nd["species_id"]),
			"name": str(nd["name"]),
			"cell": [c.x, c.y],
			"shared_anchor_cell": [sac.x, sac.y],
			"needs_shared_anchor_init": bool(nd.get("needs_shared_anchor_init", false)),
			"health": float(nd["health"]),
			"max_health": float(nd["max_health"]),
			"is_destroyed": bool(nd["is_destroyed"]),
			"spawn_timer_hours": float(nd["spawn_timer_hours"]),
			"discovered": bool(nd.get("discovered", false)),
		})
	var m_arr: Array[Dictionary] = []
	for m in monsters:
		if int(m.get("state", MonsterConfigScript.MonsterAIState.DEAD)) == MonsterConfigScript.MonsterAIState.DEAD:
			continue
		var c: Vector2i = m["cell"]
		var ac: Vector2i = m.get("anchor_cell", c)
		m_arr.append({
			"id": str(m["id"]),
			"species_id": str(m["species_id"]),
			"cell": [c.x, c.y],
			"home_nest_id": str(m["home_nest_id"]),
			"anchor_cell": [ac.x, ac.y],
			"is_displaced": bool(m.get("is_displaced", false)),
			"health": float(m["health"]),
			"max_health": float(m["max_health"]),
			"state": int(m["state"]),
			"state_timer": float(m.get("state_timer", 0.0)),
			"facing_left": bool(m.get("facing_left", false)),
			"attack_cooldown_remaining": float(m.get("attack_cooldown_remaining", 0.0)),
			"return_req_gen": int(m.get("return_req_gen", 0)),
		})
	return {
		"initialized": _is_initialized,
		"seed": _initialized_seed,
		"next_monster_seq": _next_monster_seq,
		"roam_rng_state": str(_roam_rng.state),
		"nests": n_arr,
		"monsters": m_arr,
	}

func deserialize(saved: Variant) -> bool:
	if typeof(saved) != TYPE_DICTIONARY or saved.is_empty():
		return false
	clear_all()
	_is_initialized = bool(saved.get("initialized", true))
	_initialized_seed = int(saved.get("seed", -1))
	_next_monster_seq = maxi(1, int(saved.get("next_monster_seq", 1)))
	if saved.has("roam_rng_state"):
		_roam_rng.state = int(str(saved.get("roam_rng_state", "0")))
	elif _initialized_seed >= 0:
		_roam_rng.seed = _initialized_seed + MonsterConfigScript.MONSTER_RNG_SALT + 101

	for nd_raw in saved.get("nests", []):
		if typeof(nd_raw) != TYPE_DICTIONARY:
			continue
		var ca: Array = nd_raw.get("cell", [0, 0])
		var nid := str(nd_raw.get("id", ""))
		if nid.is_empty():
			continue
		var cell_v := Vector2i(int(ca[0]), int(ca[1]))
		var is_dest: bool = bool(nd_raw.get("is_destroyed", false))
		var has_shared: bool = nd_raw.has("shared_anchor_cell") and typeof(nd_raw.get("shared_anchor_cell")) == TYPE_ARRAY
		var sac_v := cell_v
		if has_shared:
			var saca: Array = nd_raw.get("shared_anchor_cell", [cell_v.x, cell_v.y])
			if saca.size() >= 2:
				sac_v = Vector2i(int(saca[0]), int(saca[1]))
		var needs_init: bool = bool(nd_raw.get("needs_shared_anchor_init", is_dest and not has_shared))
		nests[nid] = {
			"id": nid,
			"species_id": str(nd_raw.get("species_id", "forest_stalker")),
			"name": str(nd_raw.get("name", "Ổ Quái Vật")),
			"cell": cell_v,
			"shared_anchor_cell": sac_v,
			"needs_shared_anchor_init": needs_init,
			"health": float(nd_raw.get("health", MonsterConfigScript.NEST_MAX_HEALTH)),
			"max_health": float(nd_raw.get("max_health", MonsterConfigScript.NEST_MAX_HEALTH)),
			"is_destroyed": is_dest,
			"spawn_timer_hours": float(nd_raw.get("spawn_timer_hours", 0.0)),
			"discovered": bool(nd_raw.get("discovered", false)),
		}

	var idx := 0
	for md_raw in saved.get("monsters", []):
		if typeof(md_raw) != TYPE_DICTIONARY:
			continue
		var mid := str(md_raw.get("id", ""))
		var sp := str(md_raw.get("species_id", "forest_stalker"))
		var spec := MonsterConfigScript.get_species_def(sp)
		if mid.is_empty() or spec.is_empty():
			continue
		var ca: Array = md_raw.get("cell", [0, 0])
		var aca: Array = md_raw.get("anchor_cell", ca)
		var m_cell := Vector2i(int(ca[0]), int(ca[1]))
		var a_cell := Vector2i(int(aca[0]), int(aca[1]))
		var home_nid := str(md_raw.get("home_nest_id", ""))
		var hp: float = float(md_raw.get("health", spec.get("max_health", 75.0)))
		var st: int = int(md_raw.get("state", MonsterConfigScript.MonsterAIState.IDLE))
		if st == MonsterConfigScript.MonsterAIState.DEAD or hp <= 0.0:
			continue

		var nest_alive := nests.has(home_nid) and not bool(nests[home_nid].get("is_destroyed", false))
		var is_disp: bool = bool(md_raw.get("is_displaced", not nest_alive))
		if not nest_alive and nests.has(home_nid) and not bool(nests[home_nid].get("needs_shared_anchor_init", false)):
			a_cell = nests[home_nid].get("shared_anchor_cell", a_cell)
		var eff_thresh: int = MonsterConfigScript.get_effective_return_threshold(sp, is_disp)
		var st_timer: float = float(md_raw.get("state_timer", -1.0))

		if st == MonsterConfigScript.MonsterAIState.IDLE:
			if st_timer < 0.0:
				st_timer = 1.0 + float(idx % 5) * 0.4
		elif st == MonsterConfigScript.MonsterAIState.GUARDING or st == MonsterConfigScript.MonsterAIState.ALERT:
			st = MonsterConfigScript.MonsterAIState.IDLE
			if st_timer < 0.0:
				st_timer = 1.0 + float(idx % 5) * 0.4
		elif st == MonsterConfigScript.MonsterAIState.CHASING or st == MonsterConfigScript.MonsterAIState.ATTACKING:
			if IsoMath.grid_distance(m_cell, a_cell) > eff_thresh:
				st = MonsterConfigScript.MonsterAIState.RETURNING
			else:
				st = MonsterConfigScript.MonsterAIState.IDLE
				st_timer = 1.0 + float(idx % 5) * 0.4
		elif st == MonsterConfigScript.MonsterAIState.ROAMING:
			st = MonsterConfigScript.MonsterAIState.IDLE
			st_timer = 0.5 + float(idx % 5) * 0.25
		elif st == MonsterConfigScript.MonsterAIState.RETURNING:
			st_timer = maxf(0.0, st_timer)
		else:
			st = MonsterConfigScript.MonsterAIState.IDLE
			st_timer = 1.0 + float(idx % 5) * 0.4

		var rec := {
			"id": mid,
			"species_id": sp,
			"cell": m_cell,
			"prev_cell": m_cell,
			"move_progress": 1.0,
			"facing_left": bool(md_raw.get("facing_left", false)),
			"home_nest_id": home_nid,
			"anchor_cell": a_cell,
			"is_displaced": is_disp,
			"health": hp,
			"max_health": float(md_raw.get("max_health", spec.get("max_health", 75.0))),
			"armor": float(spec.get("armor", 0.0)),
			"attack_damage": float(spec.get("attack_damage", 14.0)),
			"attack_range": int(spec.get("attack_range", 1)),
			"attack_cooldown": float(spec.get("attack_cooldown", 1.0)),
			"attack_cooldown_remaining": maxf(0.0, float(md_raw.get("attack_cooldown_remaining", 0.0))),
			"move_step_duration": float(spec.get("move_step_duration", 0.5)),
			"roam_step_duration": float(spec.get("roam_step_duration", 0.65)),
			"step_accumulator": 0.0,
			"state": st,
			"state_timer": maxf(0.0, st_timer),
			"alert_visual_timer": 0.0,
			"return_retry_timer": 0.0,
			"return_req_gen": int(md_raw.get("return_req_gen", 0)),
			"needs_return_retry": false,
			"target_unit_id": "",
			"cached_path": [] as Array[Vector2i],
		}
		monsters.append(rec)
		if st == MonsterConfigScript.MonsterAIState.RETURNING:
			_enqueue_return_request(rec)
		idx += 1
	_sync_all_actors()
	return true
