class_name SettlementPopulationSeeder
extends RefCounted
## P5-07 Initial Settlement Population Seeder for Rival Settlements.
## Creates canonical founding residents for newly generated active settlements using
## Prepare -> Commit -> Notify, strictly separate from Phase 5 ongoing daily immigration.

signal population_seeded(settlement_id: String, villager_ids: Array[String])

const SettlementDataScript = preload("res://scripts/world/settlement_data.gd")
const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementJobBoardScript = preload("res://scripts/world/settlement_job_board.gd")
const SettlementEconomyScript = preload("res://scripts/world/settlement_economy.gd")
const SettlementSimulationConfigScript = preload("res://scripts/world/settlement_simulation_config.gd")
const SettlementImmigrationPolicyScript = preload("res://scripts/world/settlement_immigration_policy.gd")
const SettlementImmigrationServiceScript = preload("res://scripts/world/settlement_immigration_service.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")

const FNV1A_64_OFFSET_BASIS: int = -3750763034362895579
const FNV1A_64_PRIME: int = 1099511628211

# Approved P5-07 profile + layout-tier initial population targets and role compositions.
# Note: Only roles actually supported by Phase 3-6 exist here; remaining residents are ROLE_IDLE.
const PROFILE_SEED_SPECS: Dictionary = {
	"neutral_tribe": {
		"full": {
			"target": 7,
			"roles": [
				{"role": SettlementVillagerDataScript.ROLE_HUNTER, "count": 1},
				{"role": SettlementVillagerDataScript.ROLE_FARMER, "count": 2},
				{"role": SettlementVillagerDataScript.ROLE_WOODCUTTER, "count": 2},
				{"role": SettlementVillagerDataScript.ROLE_HAULER, "count": 1}
			]
		},
		"compact": {
			"target": 3,
			"roles": [
				{"role": SettlementVillagerDataScript.ROLE_HUNTER, "count": 1},
				{"role": SettlementVillagerDataScript.ROLE_WOODCUTTER, "count": 1},
				{"role": SettlementVillagerDataScript.ROLE_HAULER, "count": 1}
			]
		}
	},
	"rival_military": {
		"full": {
			"target": 8,
			"roles": [
				{"role": SettlementVillagerDataScript.ROLE_GUARD, "count": 2},
				{"role": SettlementVillagerDataScript.ROLE_HAULER, "count": 2}
			]
		},
		"compact": {
			"target": 4,
			"roles": [
				{"role": SettlementVillagerDataScript.ROLE_GUARD, "count": 2}
			]
		}
	},
	"rival_merchant": {
		"full": {
			"target": 7,
			"roles": [
				{"role": SettlementVillagerDataScript.ROLE_HAULER, "count": 4}
			]
		},
		"compact": {
			"target": 3,
			"roles": [
				{"role": SettlementVillagerDataScript.ROLE_HAULER, "count": 2}
			]
		}
	}
}

static func derive_seed(world_seed: int, settlement_id: String) -> int:
	var h: int = FNV1A_64_OFFSET_BASIS
	var payload: String = "%d|%s|initial_seed" % [world_seed, settlement_id]
	for b in payload.to_utf8_buffer():
		h = h ^ int(b)
		h = h * FNV1A_64_PRIME
	return 1 if h == 0 else h

static func resolve_profile_spec(profile_id: String, layout_tier: String) -> Dictionary:
	var p_key: String = profile_id if PROFILE_SEED_SPECS.has(profile_id) else SettlementEconomyScript.PROFILE_NEUTRAL_TRIBE
	var tier_key: String = "compact" if layout_tier == "compact" else "full"
	var p_dict: Dictionary = PROFILE_SEED_SPECS[p_key]
	return (p_dict.get(tier_key, p_dict["full"]) as Dictionary).duplicate(true)

static func resolve_layout_tier(ctx: RefCounted, settlement_data: RefCounted) -> String:
	if settlement_data != null:
		var lt: Variant = settlement_data.get("layout_tier")
		if lt is String and (String(lt) == "compact" or String(lt) == "full"):
			return String(lt)
	if ctx != null and int(ctx.get_housing_capacity()) <= 6:
		return "compact"
	return "full"

func seed_settlement(
	ctx: RefCounted,
	world_seed: int,
	settlement_data: RefCounted = null,
	world_data: RefCounted = null
) -> Dictionary:
	var res := {
		"ok": false,
		"seeded": 0,
		"villager_ids": [],
		"reason": ""
	}

	if ctx == null or not ctx.has_method("is_valid") or not ctx.is_valid():
		res["reason"] = "invalid_context"
		return res
	var st: RefCounted = ctx.sim_state
	if st == null:
		res["reason"] = "missing_sim_state"
		return res
	if bool(st.initial_population_seeded):
		res["ok"] = true
		res["reason"] = "already_seeded"
		return res
	if ctx.get_villager_count() > 0:
		res["ok"] = true
		res["reason"] = "already_populated"
		return res
	if settlement_data != null and String(settlement_data.get("status")) != SettlementDataScript.STATUS_ACTIVE:
		res["reason"] = "settlement_not_active"
		return res

	var housing_cap: int = int(ctx.get_housing_capacity())
	if housing_cap <= 0:
		res["reason"] = "no_housing_capacity"
		return res

	var econ: RefCounted = ctx.economy
	if econ == null or not econ.has_method("is_valid") or not econ.is_valid():
		res["reason"] = "invalid_economy"
		return res

	# Evaluate Food sustainability (physical RES_FOOD only; raw_meat never counts)
	var food_stock: int = int(econ.get_resource(EconomyConfigScript.RES_FOOD))
	if food_stock < SettlementImmigrationPolicyScript.DEFAULT_MIN_FOOD_RESERVE:
		res["reason"] = "insufficient_food_reserve"
		return res
	var food_per_resident: float = float(SettlementSimulationConfigScript.DAILY_RATION_FOOD) * SettlementImmigrationPolicyScript.DEFAULT_FOOD_RESERVE_DAYS
	var max_food_pop: int = int(floor(float(food_stock) / maxf(1.0, food_per_resident)))
	if max_food_pop <= 0:
		res["reason"] = "insufficient_food_reserve"
		return res

	var profile_id: String = String(econ.economy_profile_id)
	var layout_tier: String = resolve_layout_tier(ctx, settlement_data)
	var spec: Dictionary = resolve_profile_spec(profile_id, layout_tier)
	var target_pop: int = mini(int(spec.get("target", 0)), mini(housing_cap, max_food_pop))
	if target_pop <= 0:
		res["reason"] = "zero_permitted_population"
		return res

	var sid: String = String(ctx.settlement_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = derive_seed(world_seed, sid)

	# --- PREPARE PHASE ---
	# 1. Deterministic role-to-job matching using real SettlementJobBoard records
	var available_jobs: Array = []
	if ctx.job_board != null:
		for j in ctx.job_board.get_all_jobs():
			if j == null or j.settlement_id != sid:
				continue
			if j.state != SettlementJobBoardScript.STATE_AVAILABLE or not j.assigned_villager_id.is_empty():
				continue
			var wp = ctx.workplace_registry.get_workplace(j.workplace_id) if ctx.workplace_registry != null else null
			if wp == null or wp.settlement_id != sid or not wp.is_active or wp.worker_quota <= 0:
				continue
			available_jobs.append(j)
		available_jobs.sort_custom(func(a, b) -> bool:
			return String(a.job_id) < String(b.job_id)
		)

	var claimed_job_ids: Dictionary = {}
	var wp_used_counts: Dictionary = {}
	var planned_jobs: Array = [] # Parallel to target_pop: NpcJobRecord or null

	for role_spec in spec.get("roles", []):
		if planned_jobs.size() >= target_pop:
			break
		var want_role: String = String(role_spec.get("role", ""))
		var want_cnt: int = int(role_spec.get("count", 0))
		var assigned_for_role: int = 0
		for j in available_jobs:
			if assigned_for_role >= want_cnt or planned_jobs.size() >= target_pop:
				break
			if claimed_job_ids.has(j.job_id) or j.job_type != want_role:
				continue
			var wp = ctx.workplace_registry.get_workplace(j.workplace_id)
			var used_wp: int = int(wp_used_counts.get(j.workplace_id, 0))
			if used_wp >= int(wp.worker_quota):
				continue
			claimed_job_ids[j.job_id] = true
			wp_used_counts[j.workplace_id] = used_wp + 1
			planned_jobs.append(j)
			assigned_for_role += 1

	while planned_jobs.size() < target_pop:
		planned_jobs.append(null) # Remaining residents are ROLE_IDLE

	# 2. Deterministic home assignment across real residential buildings
	var home_assignments: Array[String] = _plan_home_assignments(ctx, target_pop)

	# 3. Deterministic distinct walkable spawn cells
	var spawn_cells: Array[Vector2i] = _plan_spawn_cells(settlement_data, world_data, target_pop)
	if spawn_cells.size() < target_pop:
		res["reason"] = "no_valid_spawn_cells"
		return res

	# 4. Prepare canonical SettlementVillagerData records
	var init_h_seq: int = maxi(0, int(st.required_hour_seq))
	var prepared: Array = []
	for i in range(target_pop):
		var vid: String = String(ctx.allocate_villager_id())
		if vid.is_empty() or ctx.has_villager(vid):
			res["reason"] = "id_allocation_failed"
			return res
		var v_name: String = SettlementImmigrationServiceScript._generate_deterministic_name(rng, vid)
		var job = planned_jobs[i]
		var v_role: String = String(job.job_type) if job != null else SettlementVillagerDataScript.ROLE_IDLE
		var v := SettlementVillagerDataScript.new(
			vid,
			sid,
			String(ctx.origin_faction_id),
			v_name,
			v_role,
			spawn_cells[i]
		)
		v.current_faction_id = String(ctx.owner_faction_id)
		v.home_building_id = home_assignments[i]
		v.last_processed_hour_seq = init_h_seq
		v.admission_hour_seq = -1 # Founding resident marker (distinct from Phase 5 immigrants >= 0)
		if not v.is_valid():
			res["reason"] = "invalid_prepared_villager"
			return res
		prepared.append({"villager": v, "job": job})

	# --- COMMIT PHASE ---
	var committed_ids: Array[String] = []
	var committed_jobs: Array = []
	for entry in prepared:
		var v = entry["villager"]
		var job = entry["job"]
		if not ctx.add_villager(v):
			for cid in committed_ids:
				ctx.remove_villager(cid)
				st.registered.erase(cid)
			for cj in committed_jobs:
				cj.assigned_villager_id = ""
				cj.state = SettlementJobBoardScript.STATE_AVAILABLE
			res["reason"] = "registration_commit_failed"
			return res
		st.registered[v.villager_id] = init_h_seq
		committed_ids.append(v.villager_id)

		if job != null:
			job.assigned_villager_id = v.villager_id
			job.state = SettlementJobBoardScript.STATE_RESERVED
			v.active_job_id = job.job_id
			v.workplace_id = job.workplace_id
			if job.job_type == SettlementVillagerDataScript.ROLE_GUARD and ctx.has_method("get_guard_patrol_for_job"):
				var patrol: Dictionary = ctx.get_guard_patrol_for_job(job.job_id)
				if bool(patrol.get("ok", false)):
					v.work_target_id = String(patrol.get("initial_target_id", ""))
			committed_jobs.append(job)

	st.initial_population_seeded = true
	st.initial_seed_hour_seq = init_h_seq

	res["ok"] = true
	res["seeded"] = committed_ids.size()
	res["villager_ids"] = committed_ids
	res["reason"] = ""

	# --- NOTIFY PHASE ---
	population_seeded.emit(sid, committed_ids)
	return res

static func _plan_home_assignments(ctx: RefCounted, count: int) -> Array[String]:
	var out: Array[String] = []
	var res_blds: Array[Dictionary] = ctx.get_residential_buildings() if ctx.has_method("get_residential_buildings") else []
	res_blds.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("building_id", "")) < String(b.get("building_id", ""))
	)
	var capacities: Array[int] = []
	var used: Array[int] = []
	for rb in res_blds:
		var cap: int = int(rb.get("capacity", EconomyConfigScript.get_house_capacity(int(rb.get("level", 1)))))
		capacities.append(maxi(0, cap))
		used.append(0)

	var rr_idx: int = 0
	for _i in range(count):
		var assigned_id: String = ""
		if not res_blds.is_empty():
			for attempt in range(res_blds.size()):
				var idx: int = (rr_idx + attempt) % res_blds.size()
				if used[idx] < capacities[idx]:
					used[idx] += 1
					assigned_id = String(res_blds[idx].get("building_id", ""))
					rr_idx = (idx + 1) % res_blds.size()
					break
		out.append(assigned_id)
	return out

static func _plan_spawn_cells(settlement_data: RefCounted, world_data: RefCounted, count: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var anchor: Vector2i = Vector2i.ZERO
	var building_cells: Dictionary = {}
	var road_cells: Array[Vector2i] = []

	if settlement_data != null:
		var raw_a: Variant = settlement_data.get("anchor_cell")
		if raw_a is Vector2i and raw_a.x >= 0 and raw_a.y >= 0:
			anchor = raw_a
		if settlement_data.has_method("get_building_cells"):
			for bc in settlement_data.get_building_cells():
				building_cells[bc] = true
		var raw_roads: Variant = settlement_data.get("roads")
		if raw_roads is Array:
			for r in raw_roads:
				if r is Vector2i:
					road_cells.append(r)

	road_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da: int = IsoMath.grid_distance(a, anchor)
		var db: int = IsoMath.grid_distance(b, anchor)
		if da != db:
			return da < db
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)

	var candidates: Array[Vector2i] = []
	var seen: Dictionary = {}
	for rc in road_cells:
		if not seen.has(rc) and _is_spawn_cell_walkable(rc, building_cells, world_data):
			seen[rc] = true
			candidates.append(rc)

	# Spiral around anchor_cell for any additional distinct walkable cells
	for rad in range(0, 7):
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if absi(dx) != rad and absi(dy) != rad:
					continue
				var c := anchor + Vector2i(dx, dy)
				if not seen.has(c) and _is_spawn_cell_walkable(c, building_cells, world_data):
					seen[c] = true
					candidates.append(c)

	if candidates.is_empty():
		return out

	for i in range(count):
		out.append(candidates[i % candidates.size()])
	return out

static func _is_spawn_cell_walkable(cell: Vector2i, building_cells: Dictionary, world_data: RefCounted) -> bool:
	if building_cells.has(cell):
		return false
	if world_data != null:
		if not world_data.is_in_bounds(cell):
			return false
		var t_type: int = int(world_data.terrain[cell.x][cell.y])
		if t_type == 0: # TerrainType.WATER
			if not world_data.bridge_walkable_cells.has(cell):
				return false
		if t_type == 5 and int(world_data.generator_version) == 2: # BATCH03 MOUNTAINS
			return false
		if world_data.occupancy[cell.x][cell.y]:
			return false
	elif not IsoMath.is_in_bounds(cell):
		return false
	return true
