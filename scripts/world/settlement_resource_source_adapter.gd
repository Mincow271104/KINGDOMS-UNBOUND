class_name SettlementResourceSourceAdapter
extends RefCounted
## Deterministic Grounded Resource Ownership & Tree Felling Adapter (Architecture v1.0 — W1).
## Bridges neutral WorldData physical tree props with Rival Settlement workplace labor banking
## and atomic whole-tree harvesting.
##
## Guarantees:
## 1. Physical Conservation: 1 tree = exactly 5 Wood (5000 milli-units). Zero partial tree harvesting.
## 2. All-or-Nothing Atomicity: Felling debits 5000 work credit milli-units, deposits 5 Wood into
##    workplace buffer, removes tree from WorldData.props and clears occupancy synchronously.
## 3. Cross-System Non-Duplication: If Player clears a tree, Rival felling detects absence in WorldData.props
##    and fails closed with zero wood deposited and zero credit lost. If Rival fells a tree, Player
##    clearing order cancels upon arrival with zero wood awarded.
## 4. Exact-Once Labor Banking: 3h worker cycle adds 4000 work credit milli-units into
##    `production_sources[workplace_id]["work_credit_milli"]`. Preserved under buffer backpressure.
## 5. Reactive Retry: When Hauler pickup creates >= 5 headroom, felling retries using banked credit
##    with zero additional worker cycles.
## 6. DAY_SHIFT Clock Alignment: (6 + hour_seq) % 24 in [5..17].

const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const WildlifeConfigScript = preload("res://scripts/world/wildlife_config.gd")

const TREE_WOOD_UNITS: int = 5
const MILLI_PER_UNIT: int = 1000
const TREE_WOOD_MILLI: int = 5000
const CYCLE_WORK_CREDIT_MILLI: int = 4000
const TREE_FELL_COST_MILLI: int = 5000
const WOODCUTTER_CATCHMENT_RADIUS: int = 12

# Farm Constants (Architecture v1.0 — F1 / P4-19 Rate-Based Alignment)
const FARM_CYCLE_HOURS: float = 3.0
const FARM_WORK_HOURS_PER_DAY: float = 12.0 # 12 daytime daylight work hours (06:00..17:00)
const FARM_BASE_FOOD_PER_FARMER_DAY: float = 5.0 # GDD 5.4: 5 Food / farmer / day
const FARM_MAX_WORKERS: int = 5 # EconomyConfig: 5 max workers per Farm
const FARM_MAX_DAILY_FOOD: float = 25.0 # GDD 5.4: 25 Food / Farm / day at full staffing
const FARM_BASE_CYCLE_MILLI: int = 1250 # (3.0 / 12.0) * 5.0 * 1000 = 1250 milli per 3h cycle
const FARM_MILLI_PER_UNIT: int = 1000

const DAY_SHIFT_START_HOUR: int = 5
const DAY_SHIFT_END_HOUR: int = 17
const START_HOUR_OFFSET: int = 6 # TimeManager hour_seq = 0 starts at 06:00

# -----------------------------------------------------------------------------
# Clock & Time Mapping Helpers
# -----------------------------------------------------------------------------
static func clock_hour_from_hour_seq(h_seq: int) -> int:
	return (START_HOUR_OFFSET + h_seq) % 24

static func is_day_shift_hour(h_seq: int) -> bool:
	var ch: int = clock_hour_from_hour_seq(h_seq)
	return ch >= DAY_SHIFT_START_HOUR and ch <= DAY_SHIFT_END_HOUR

# -----------------------------------------------------------------------------
# Neutral Prop Identity & Lookup
# -----------------------------------------------------------------------------
static func make_prop_id(world_seed: int, gen_ver: int, prop_type: String, cell: Vector2i) -> String:
	return WorldGenerator.make_prop_id(world_seed, gen_ver, prop_type, cell)

static func get_player_protection_center(world_data: RefCounted, explicit_center: Vector2i = Vector2i(-999, -999)) -> Vector2i:
	return SettlementGenerator.resolve_player_center(world_data, explicit_center)

static func is_player_protected_cell(world_data: RefCounted, cell: Vector2i, player_center: Vector2i = Vector2i(-999, -999)) -> bool:
	if world_data == null:
		return true # Fail closed: invalid or missing world data is protected from rival harvesting
	if world_data.has_method("is_in_bounds") and not world_data.is_in_bounds(cell):
		return true # Fail closed: out-of-bounds cell is ineligible
	var pc: Vector2i = get_player_protection_center(world_data, player_center)
	if pc == Vector2i(-999, -999):
		return true # Fail closed: missing or invalid canonical player center treats candidate cells as protected/ineligible from rival harvesting
	var protected: Dictionary = SettlementGenerator.build_player_protected_cells(world_data, pc)
	return protected.has(cell)

static func find_tree_prop_at_cell(world_data: RefCounted, cell: Vector2i) -> Dictionary:
	if world_data == null or world_data.get("props") == null:
		return {}
	for p in world_data.props:
		if p.get("cell", Vector2i(-1, -1)) == cell and p.get("type", "") == "tree":
			return p
	return {}

static func is_tree_available(tree: Dictionary) -> bool:
	return int(tree.get("remaining_milli", 0)) == TREE_WOOD_MILLI

static func is_tree_felled(tree: Dictionary) -> bool:
	return int(tree.get("remaining_milli", 0)) == 0

static func calculate_remaining_wood(src: Dictionary) -> int:
	var count: int = 0
	for t in src.get("trees", []):
		if is_tree_available(t):
			count += 1
	return count * TREE_WOOD_UNITS

# -----------------------------------------------------------------------------
# Source Registration & Global Allocation
# -----------------------------------------------------------------------------
static func register_woodcutter_source(
	ctx: RefCounted,
	workplace_id: String,
	world_data: RefCounted = null,
	assigned_cells: Array = [],
	globally_allocated_cells: Dictionary = {},
	player_center: Vector2i = Vector2i(-999, -999)
) -> Dictionary:
	if ctx == null or ctx.sim_state == null:
		return {"ok": false, "reason": "invalid_context"}
	if ctx.workplace_registry == null or not ctx.workplace_registry.has_workplace(workplace_id):
		return {"ok": false, "reason": "workplace_not_found"}

	# Idempotency: avoid duplicate registration
	if ctx.sim_state.production_sources.has(workplace_id):
		var existing_src: Dictionary = ctx.sim_state.production_sources[workplace_id]
		return {
			"ok": true,
			"workplace_id": workplace_id,
			"already_registered": true,
			"tree_count": existing_src.get("trees", []).size(),
			"remaining_wood": calculate_remaining_wood(existing_src)
		}

	var wp = ctx.workplace_registry.get_workplace(workplace_id)
	var wp_cell: Vector2i = wp.access_cell if wp != null and wp.access_cell != Vector2i.ZERO else (wp.origin_cell if wp != null else Vector2i.ZERO)
	var tree_records: Array[Dictionary] = []
	var cells_to_bind: Array[Vector2i] = []

	var pc: Vector2i = get_player_protection_center(world_data, player_center)
	if pc == Vector2i(-999, -999):
		return {"ok": false, "reason": "missing_canonical_player_center"}

	if not assigned_cells.is_empty():
		for c in assigned_cells:
			if c is Vector2i:
				if is_player_protected_cell(world_data, c, player_center):
					continue
				if globally_allocated_cells.has(c) and String(globally_allocated_cells[c]) != workplace_id:
					continue
				if world_data != null and world_data.get("props") != null:
					var prop = find_tree_prop_at_cell(world_data, c)
					if prop.is_empty():
						continue
				cells_to_bind.append(c)
				globally_allocated_cells[c] = workplace_id
	elif world_data != null and world_data.get("props") != null:
		var candidate_trees: Array[Dictionary] = []
		for p in world_data.props:
			if p.get("type", "") != "tree":
				continue
			var c: Vector2i = p.get("cell", Vector2i(-1, -1))
			if c.x < 0 or c.y < 0:
				continue
			if world_data.has_method("is_in_bounds") and not world_data.is_in_bounds(c):
				continue
			if is_player_protected_cell(world_data, c, player_center):
				continue
			if globally_allocated_cells.has(c) and String(globally_allocated_cells[c]) != workplace_id:
				continue
			var d: int = absi(c.x - wp_cell.x) + absi(c.y - wp_cell.y)
			if d > WOODCUTTER_CATCHMENT_RADIUS:
				continue
			candidate_trees.append(p)

		candidate_trees.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var ca: Vector2i = a.get("cell", Vector2i.ZERO)
			var cb: Vector2i = b.get("cell", Vector2i.ZERO)
			var da: int = absi(ca.x - wp_cell.x) + absi(ca.y - wp_cell.y)
			var db: int = absi(cb.x - wp_cell.x) + absi(cb.y - wp_cell.y)
			if da != db:
				return da < db
			if ca.x != cb.x:
				return ca.x < cb.x
			return ca.y < cb.y
		)
		for tree_dict in candidate_trees:
			var c: Vector2i = tree_dict.get("cell", Vector2i.ZERO)
			cells_to_bind.append(c)
			globally_allocated_cells[c] = workplace_id

	if cells_to_bind.is_empty():
		return {"ok": false, "reason": "no_valid_trees_found"}

	var w_seed: int = int(world_data.seed_value) if world_data != null and world_data.get("seed_value") != null else 12345
	var gen_ver: int = int(world_data.generator_version) if world_data != null and world_data.get("generator_version") != null else 1

	for c in cells_to_bind:
		tree_records.append({
			"prop_id": make_prop_id(w_seed, gen_ver, "tree", c),
			"cell": c,
			"remaining_milli": TREE_WOOD_MILLI
		})

	var rem_wood: int = tree_records.size() * TREE_WOOD_UNITS
	var src_desc: Dictionary = {
		"type": "woodcutter_tree_source",
		"resource": "wood",
		"workplace_id": workplace_id,
		"trees": tree_records,
		"max_capacity": rem_wood,
		"work_credit_milli": 0,
		"felled_count": 0
	}

	ctx.sim_state.production_sources[workplace_id] = src_desc
	ctx.sim_state.production_blocked.erase(workplace_id)

	return {
		"ok": true,
		"workplace_id": workplace_id,
		"tree_count": tree_records.size(),
		"remaining_wood": rem_wood
	}

## Performs deterministic, order-independent global Voronoi tree allocation across all Woodcutter
## workplaces across all contexts.
## Guarantees:
## 1. Respects WOODCUTTER_CATCHMENT_RADIUS (12) from each workplace's access_cell (fallback origin_cell).
## 2. Order-independent tie-breaking: min(distance, settlement_id, workplace_id).
## 3. Disjoint allocations: 1 tree belongs to at most 1 workplace.
## 4. Full catchment allocation: binds all eligible candidate trees claimed within catchment radius.
## 5. Excludes player-protected cells (canonical SettlementGenerator protection rule).
## 6. Registers canonical sources without mutable aggregate 'remaining'.
static func allocate_global_woodcutter_sources(
	contexts: Array,
	world_data: RefCounted,
	player_center: Vector2i = Vector2i(-999, -999)
) -> Dictionary:
	var globally_allocated_cells: Dictionary = {} # Vector2i -> workplace_id (String)
	if contexts.is_empty() or world_data == null or world_data.get("props") == null:
		return globally_allocated_cells

	var pc: Vector2i = get_player_protection_center(world_data, player_center)
	if pc == Vector2i(-999, -999):
		return globally_allocated_cells # Fail closed: cannot allocate trees without valid canonical player protection center

	# 1. Collect and deterministically sort all candidate woodcutter workplaces
	var workplaces_list: Array[Dictionary] = []
	for ctx in contexts:
		if ctx == null or ctx.workplace_registry == null or ctx.sim_state == null:
			continue
		var sid: String = String(ctx.settlement_id)
		for wp in ctx.workplace_registry.get_all_workplaces():
			if wp != null and wp.building_type == "woodcutter":
				var w_pos: Vector2i = wp.access_cell if wp.access_cell != Vector2i.ZERO else wp.origin_cell
				var wp_key: String = "%s::%s" % [sid, String(wp.workplace_id)]
				workplaces_list.append({
					"ctx": ctx,
					"wp": wp,
					"settlement_id": sid,
					"workplace_id": String(wp.workplace_id),
					"wp_key": wp_key,
					"pos": w_pos
				})

	if workplaces_list.is_empty():
		return globally_allocated_cells

	workplaces_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["settlement_id"] != b["settlement_id"]:
			return a["settlement_id"] < b["settlement_id"]
		return a["workplace_id"] < b["workplace_id"]
	)

	# 2. Collect valid candidate tree props from world_data
	var candidate_cells: Array[Vector2i] = []
	for p in world_data.props:
		if p.get("type", "") != "tree":
			continue
		var c: Vector2i = p.get("cell", Vector2i(-1, -1))
		if c.x < 0 or c.y < 0:
			continue
		if world_data.has_method("is_in_bounds") and not world_data.is_in_bounds(c):
			continue
		if is_player_protected_cell(world_data, c, player_center):
			continue
		candidate_cells.append(c)

	candidate_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.x != b.x:
			return a.x < b.x
		return a.y < b.y
	)

	# 3. For each tree cell, find the best workplace within catchment radius
	var claims_by_wp_key: Dictionary = {} # wp_key -> Array[Dictionary]
	for w_info in workplaces_list:
		claims_by_wp_key[w_info["wp_key"]] = []

	for c in candidate_cells:
		var best_wp: Dictionary = {}
		var best_dist: int = 999999
		for w_info in workplaces_list:
			var wp_pos: Vector2i = w_info["pos"]
			var d: int = absi(c.x - wp_pos.x) + absi(c.y - wp_pos.y)
			if d > WOODCUTTER_CATCHMENT_RADIUS:
				continue
			if best_wp.is_empty():
				best_wp = w_info
				best_dist = d
			elif d < best_dist:
				best_wp = w_info
				best_dist = d
			elif d == best_dist:
				# Tie-break key: min(settlement_id, workplace_id)
				var sid_cmp: int = w_info["settlement_id"].casecmp_to(best_wp["settlement_id"])
				if sid_cmp < 0:
					best_wp = w_info
					best_dist = d
				elif sid_cmp == 0:
					if w_info["workplace_id"].casecmp_to(best_wp["workplace_id"]) < 0:
						best_wp = w_info
						best_dist = d

		if not best_wp.is_empty():
			claims_by_wp_key[best_wp["wp_key"]].append({
				"cell": c,
				"dist": best_dist
			})

	# 4. For each workplace, bind up to MAX_TREES_PER_WORKPLACE (10) nearest claimed trees
	var w_seed: int = int(world_data.seed_value) if world_data.get("seed_value") != null else 12345
	var gen_ver: int = int(world_data.generator_version) if world_data.get("generator_version") != null else 1

	for w_info in workplaces_list:
		var wpid: String = w_info["workplace_id"]
		var ctx = w_info["ctx"]
		var claims: Array = claims_by_wp_key.get(w_info["wp_key"], [])

		# Sort claimed cells by dist, then x, then y
		claims.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["dist"]) != int(b["dist"]):
				return int(a["dist"]) < int(b["dist"])
			var ca: Vector2i = a["cell"]
			var cb: Vector2i = b["cell"]
			if ca.x != cb.x:
				return ca.x < cb.x
			return ca.y < cb.y
		)

		var tree_records: Array[Dictionary] = []
		for claim in claims:
			var tc: Vector2i = claim["cell"]
			tree_records.append({
				"prop_id": make_prop_id(w_seed, gen_ver, "tree", tc),
				"cell": tc,
				"remaining_milli": TREE_WOOD_MILLI
			})
			globally_allocated_cells[tc] = wpid

		if not tree_records.is_empty():
			var rem_wood: int = tree_records.size() * TREE_WOOD_UNITS
			var src_desc: Dictionary = {
				"type": "woodcutter_tree_source",
				"resource": "wood",
				"workplace_id": wpid,
				"trees": tree_records,
				"max_capacity": rem_wood,
				"work_credit_milli": 0,
				"felled_count": 0
			}
			ctx.sim_state.production_sources[wpid] = src_desc
			ctx.sim_state.production_blocked.erase(wpid)

	return globally_allocated_cells

static func register_all_settlement_woodcutter_sources(
	ctx: RefCounted,
	world_data: RefCounted,
	globally_allocated_cells: Dictionary = {},
	player_center: Vector2i = Vector2i(-999, -999)
) -> int:
	if ctx == null or ctx.workplace_registry == null or world_data == null:
		return 0
	var count: int = 0
	for wp in ctx.workplace_registry.get_all_workplaces():
		if wp != null and wp.building_type == "woodcutter":
			var res := register_woodcutter_source(ctx, wp.workplace_id, world_data, [], globally_allocated_cells, player_center)
			if bool(res.get("ok", false)):
				count += 1
	return count

# -----------------------------------------------------------------------------
# Atomic Tree Felling Transaction
# -----------------------------------------------------------------------------
static func execute_tree_felling_transaction(
	ctx: RefCounted,
	workplace_id: String,
	world_data: RefCounted = null,
	world_view: Node = null
) -> Dictionary:
	if ctx == null or ctx.sim_state == null:
		return {"ok": false, "reason": "invalid_context"}
	var st = ctx.sim_state
	if not st.production_sources.has(workplace_id):
		st.production_blocked[workplace_id] = "missing_verified_production_source"
		return {"ok": false, "reason": "missing_verified_production_source"}
	var src: Dictionary = st.production_sources[workplace_id]
	var wp = ctx.workplace_registry.get_workplace(workplace_id)
	if wp == null:
		return {"ok": false, "reason": "workplace_not_found"}

	var credit: int = int(src.get("work_credit_milli", 0))
	if credit < TREE_FELL_COST_MILLI:
		return {"ok": false, "reason": "insufficient_work_credit", "credit": credit}

	var eff_cap: int = ctx.get_workplace_effective_buffer_capacity(workplace_id)
	var headroom: int = maxi(0, eff_cap - int(wp.buffer_amount))
	if headroom < TREE_WOOD_UNITS:
		wp.is_paused = true
		wp.pause_reason = "buffer_full"
		return {"ok": false, "reason": "buffer_full", "headroom": headroom, "credit_preserved": credit}

	var trees: Array = src.get("trees", [])
	var target_tree: Dictionary = {}
	for i in range(trees.size()):
		var t: Dictionary = trees[i]
		if is_tree_available(t):
			target_tree = t
			break

	if target_tree.is_empty():
		st.production_blocked[workplace_id] = "source_depleted"
		return {"ok": false, "reason": "source_depleted"}

	var target_cell: Vector2i = target_tree.get("cell", Vector2i(-1, -1))
	var target_prop_id: String = String(target_tree.get("prop_id", ""))

	# Physical world validation if world_data is active
	var prop_idx: int = -1
	if world_data != null and world_data.get("props") != null:
		for i in range(world_data.props.size()):
			var p: Dictionary = world_data.props[i]
			if p.get("cell", Vector2i(-1, -1)) == target_cell and p.get("type", "") == "tree":
				prop_idx = i
				break
		if prop_idx == -1:
			# Prop missing from world (e.g. cleared by player).
			# STRICT MUTATION-FREE PREPARE: do NOT mutate target_tree or src during prepare.
			return {
				"ok": false,
				"reason": "prop_missing_in_world",
				"cell": target_cell,
				"prop_id": target_prop_id
			}

	# --- Phase B: All-or-Nothing Commit ---
	target_tree["remaining_milli"] = 0
	src["felled_count"] = int(src.get("felled_count", 0)) + 1
	src["work_credit_milli"] = credit - TREE_FELL_COST_MILLI

	wp.buffer_amount = int(wp.buffer_amount) + TREE_WOOD_UNITS
	wp.buffer_capacity = maxi(eff_cap, int(wp.buffer_amount))
	st.stats["produced"] = int(st.stats.get("produced", 0)) + TREE_WOOD_UNITS

	# WorldData sync
	if world_data != null and prop_idx >= 0:
		world_data.props.remove_at(prop_idx)
		if world_data.has_method("is_in_bounds") and world_data.is_in_bounds(target_cell):
			if world_data.get("occupancy") != null and target_cell.x < world_data.occupancy.size() and target_cell.y < world_data.occupancy[target_cell.x].size():
				world_data.occupancy[target_cell.x][target_cell.y] = false

	# WorldView visual removal
	if world_view != null and world_view.has_method("remove_prop_visual_at_cell"):
		world_view.remove_prop_visual_at_cell(target_cell)

	# Check unpausing if headroom allows further work
	if wp.is_paused and wp.pause_reason == "buffer_full":
		var new_headroom: int = eff_cap - int(wp.buffer_amount)
		if new_headroom >= TREE_WOOD_UNITS:
			wp.is_paused = false
			wp.pause_reason = ""

	return {
		"ok": true,
		"cell": target_cell,
		"prop_id": target_prop_id,
		"wood_produced": TREE_WOOD_UNITS,
		"remaining_credit": src["work_credit_milli"],
		"buffer_amount": wp.buffer_amount
	}

# -----------------------------------------------------------------------------
# Batch Felling & Backpressure Retry Engine
# -----------------------------------------------------------------------------
static func process_woodcutter_workplace_fellings(
	ctx: RefCounted,
	workplace_id: String,
	world_data: RefCounted = null,
	world_view: Node = null
) -> Dictionary:
	var total_felled: int = 0
	var total_wood: int = 0
	var last_reason: String = ""

	while true:
		var st = ctx.sim_state
		if st == null or not st.production_sources.has(workplace_id):
			break
		var src: Dictionary = st.production_sources[workplace_id]
		if int(src.get("work_credit_milli", 0)) < TREE_FELL_COST_MILLI:
			break
		var wp = ctx.workplace_registry.get_workplace(workplace_id)
		if wp == null:
			break
		var eff_cap: int = ctx.get_workplace_effective_buffer_capacity(workplace_id)
		var headroom: int = maxi(0, eff_cap - int(wp.buffer_amount))
		if headroom < TREE_WOOD_UNITS:
			wp.is_paused = true
			wp.pause_reason = "buffer_full"
			last_reason = "buffer_full"
			break

		var res := execute_tree_felling_transaction(ctx, workplace_id, world_data, world_view)
		if bool(res.get("ok", false)):
			total_felled += 1
			total_wood += int(res.get("wood_produced", TREE_WOOD_UNITS))
		else:
			last_reason = String(res.get("reason", "failed"))
			if last_reason == "prop_missing_in_world":
				var miss_cell: Vector2i = res.get("cell", Vector2i(-1, -1))
				reconcile_missing_allocated_tree(ctx, workplace_id, miss_cell)
				continue
			break

	return {
		"felled_count": total_felled,
		"wood_produced": total_wood,
		"last_reason": last_reason
	}

# -----------------------------------------------------------------------------
# Explicit Tree Reconciliation
# -----------------------------------------------------------------------------
static func reconcile_missing_allocated_tree(ctx: RefCounted, workplace_id: String, cell: Vector2i) -> bool:
	if ctx == null or ctx.sim_state == null:
		return false
	var src: Dictionary = ctx.sim_state.production_sources.get(workplace_id, {})
	for t in src.get("trees", []):
		if t.get("cell", Vector2i(-1, -1)) == cell and is_tree_available(t):
			t["remaining_milli"] = 0
			t["cleared_by_other"] = true
			return true
	return false

static func reconcile_player_cleared_tree(ctx: RefCounted, cell: Vector2i) -> bool:
	if ctx == null or ctx.sim_state == null:
		return false
	var modified: bool = false
	for wpid in ctx.sim_state.production_sources.keys():
		if reconcile_missing_allocated_tree(ctx, wpid, cell):
			modified = true
	return modified

# -----------------------------------------------------------------------------
# Farm Rate-Based Production & Accounting (GDD 5.4 / P4-19 Alignment)
# -----------------------------------------------------------------------------
static func count_assigned_farmers(ctx: RefCounted, workplace_id: String) -> int:
	if ctx == null:
		return 0
	var count: int = 0
	for v in ctx.get_all_villagers():
		if v != null and v.workplace_id == workplace_id and v.role == "farmer" and v.life_state == "alive":
			count += 1
	return count

static func register_farm_source(
	ctx: RefCounted,
	workplace_id: String,
	_remaining_amount: int = -1,
	_max_capacity: int = -1
) -> Dictionary:
	if ctx == null or ctx.sim_state == null:
		return {"ok": false, "reason": "invalid_context"}
	if ctx.workplace_registry == null or not ctx.workplace_registry.has_workplace(workplace_id):
		return {"ok": false, "reason": "workplace_not_found"}

	var wp = ctx.workplace_registry.get_workplace(workplace_id)
	if wp == null or wp.building_type != "farm":
		return {"ok": false, "reason": "invalid_workplace_type"}

	# Idempotency: avoid duplicate registration
	if ctx.sim_state.production_sources.has(workplace_id):
		return {
			"ok": true,
			"workplace_id": workplace_id,
			"already_registered": true,
			"type": "farm_rate_source"
		}

	var src_desc: Dictionary = {
		"type": "farm_rate_source",
		"resource": "food",
		"workplace_id": workplace_id,
		"pending_output_milli": 0,
		"cycles_completed": 0,
		"total_produced": 0,
		"cumulative_earned_milli": 0,
		"current_day_seq": -1,
		"daily_produced_milli": 0,
		"fractional_remainder_milli": 0,
		"last_season_seen": ""
	}

	ctx.sim_state.production_sources[workplace_id] = src_desc
	ctx.sim_state.production_blocked.erase(workplace_id)

	return {
		"ok": true,
		"workplace_id": workplace_id,
		"type": "farm_rate_source"
	}

static func register_all_farm_sources(contexts: Array) -> int:
	var registered_count: int = 0
	for ctx in contexts:
		if ctx == null or ctx.workplace_registry == null:
			continue
		for wp in ctx.workplace_registry.get_all_workplaces():
			if wp != null and wp.building_type == "farm" and wp.is_active:
				var res := register_farm_source(ctx, wp.workplace_id)
				if bool(res.get("ok", false)):
					registered_count += 1
	return registered_count

static func is_farm_daily_cap_reached(
	ctx: RefCounted,
	workplace_id: String,
	time_manager: Node = null,
	hour_seq: int = -1,
	tool_mod_override: float = -1.0,
	farmer_count_override: int = -1
) -> bool:
	if ctx == null or ctx.sim_state == null:
		return false
	var st = ctx.sim_state
	if not st.production_sources.has(workplace_id):
		return false
	var src: Dictionary = st.production_sources[workplace_id]
	var src_type: String = String(src.get("type", ""))
	if src_type != "farm_rate_source" and src_type != "rate":
		return false

	var wp = ctx.workplace_registry.get_workplace(workplace_id)
	if wp == null or wp.building_type != "farm":
		return false

	var farmer_count: int = farmer_count_override if farmer_count_override >= 0 else count_assigned_farmers(ctx, workplace_id)
	var effective_farmers: int = clampi(farmer_count, 0, FARM_MAX_WORKERS)
	if effective_farmers <= 0:
		return true

	var day_seq: int = int((hour_seq + START_HOUR_OFFSET) / 24) if hour_seq >= 0 else 0
	if time_manager != null and is_instance_valid(time_manager) and "current_day" in time_manager:
		day_seq = int(time_manager.current_day) - 1
	elif time_manager != null and is_instance_valid(time_manager) and time_manager.has_method("get_hour_seq"):
		day_seq = int((int(time_manager.get_hour_seq()) + START_HOUR_OFFSET) / 24)

	var cur_day_seq: int = int(src.get("current_day_seq", -1))
	var daily_produced: int = int(src.get("daily_produced_milli", 0))
	if cur_day_seq != day_seq:
		return false

	var seasonal_mod: float = 1.0
	if time_manager != null and is_instance_valid(time_manager) and time_manager.has_method("get_seasonal_farm_modifier"):
		seasonal_mod = float(time_manager.get_seasonal_farm_modifier())

	var tool_mod: float = 1.0
	if tool_mod_override > 0.0:
		tool_mod = tool_mod_override

	var daily_cap_milli: int = int(round(float(effective_farmers) * 5000.0 * seasonal_mod * tool_mod))
	return daily_produced >= daily_cap_milli

# Phase 1: Prepare (Strictly mutation-free)
static func prepare_farm_production_transaction(
	ctx: RefCounted,
	workplace_id: String,
	time_manager: Node = null,
	direct_to_economy: bool = false,
	hour_seq: int = 0,
	tool_mod_override: float = -1.0,
	farmer_count_override: int = -1
) -> Dictionary:
	if ctx == null or ctx.sim_state == null:
		return {"ok": false, "reason": "invalid_context", "can_commit": false}
	var st = ctx.sim_state
	if not st.production_sources.has(workplace_id):
		return {"ok": false, "reason": "missing_verified_production_source", "can_commit": false}

	var wp = ctx.workplace_registry.get_workplace(workplace_id)
	if wp == null or wp.settlement_id != ctx.settlement_id:
		return {"ok": false, "reason": "workplace_not_found", "can_commit": false}
	if wp.building_type != "farm":
		return {"ok": false, "reason": "unsupported_production_building", "can_commit": false}

	var src: Dictionary = st.production_sources[workplace_id]
	var res_id: String = String(src.get("resource", ""))
	if res_id != "food" and res_id != wp.output_resource:
		return {"ok": false, "reason": "resource_mismatch", "can_commit": false}

	# Count active assigned farmers on this farm (clamped 0 to FARM_MAX_WORKERS = 5)
	var farmer_count: int = farmer_count_override if farmer_count_override >= 0 else count_assigned_farmers(ctx, workplace_id)
	var effective_farmers: int = clampi(farmer_count, 0, FARM_MAX_WORKERS)
	if effective_farmers <= 0:
		return {
			"ok": false,
			"reason": "no_active_farmers",
			"can_commit": false,
			"workplace_id": workplace_id,
			"food_produced": 0,
			"pending_output_milli": int(src.get("pending_output_milli", 0)),
			"buffer_amount": int(wp.buffer_amount)
		}

	var eff_cap: int = ctx.get_workplace_effective_buffer_capacity(workplace_id)
	var headroom: int = maxi(0, eff_cap - int(wp.buffer_amount)) if not direct_to_economy else 999999

	# Determine current day_seq aligned with calendar day boundary (00:00 midnight)
	var day_seq: int = int((hour_seq + START_HOUR_OFFSET) / 24) if hour_seq >= 0 else 0
	if time_manager != null and is_instance_valid(time_manager) and "current_day" in time_manager:
		day_seq = int(time_manager.current_day) - 1
	elif time_manager != null and is_instance_valid(time_manager) and time_manager.has_method("get_hour_seq"):
		day_seq = int((int(time_manager.get_hour_seq()) + START_HOUR_OFFSET) / 24)

	# Modifiers
	var seasonal_mod: float = 1.0
	if time_manager != null and is_instance_valid(time_manager) and time_manager.has_method("get_seasonal_farm_modifier"):
		seasonal_mod = float(time_manager.get_seasonal_farm_modifier())

	# Tool modifier: neutral default 1.0 unless explicit override provided
	var tool_mod: float = 1.0
	if tool_mod_override > 0.0:
		tool_mod = tool_mod_override

	# Daily production cap for this farm on this day
	var daily_cap_milli: int = int(round(float(effective_farmers) * 5000.0 * seasonal_mod * tool_mod))

	# Reconcile day rollover
	var cur_day_seq: int = int(src.get("current_day_seq", -1))
	var daily_produced: int = int(src.get("daily_produced_milli", 0))
	if cur_day_seq != day_seq:
		cur_day_seq = day_seq
		daily_produced = 0

	var daily_headroom: int = maxi(0, daily_cap_milli - daily_produced)

	# Cycle yield = round(1250 * Seasonal * Tool)
	var cycle_yield_milli: int = int(round(float(FARM_BASE_CYCLE_MILLI) * seasonal_mod * tool_mod))
	var earnable_milli: int = mini(cycle_yield_milli, daily_headroom)

	var pending_milli: int = int(src.get("pending_output_milli", 0))
	var pending_units: int = int(pending_milli / FARM_MILLI_PER_UNIT)

	# Check if daily cap reached AND buffer full (no pending can drain and no new production earnable)
	if earnable_milli <= 0 and (headroom <= 0 or pending_units <= 0):
		if not direct_to_economy and headroom <= 0:
			return {
				"ok": false,
				"reason": "buffer_full",
				"can_commit": false,
				"headroom": 0,
				"pending_units": pending_units,
				"credit_preserved": true
			}
		return {
			"ok": true,
			"can_commit": false,
			"food_produced": 0,
			"reason": "daily_limit_reached",
			"pending_output_milli": pending_milli,
			"buffer_amount": int(wp.buffer_amount)
		}

	# Compute plan without mutating anything
	var take_pending: int = 0
	var sim_headroom: int = headroom
	var sim_pending_milli: int = pending_milli

	if not direct_to_economy and pending_units > 0 and sim_headroom > 0:
		take_pending = mini(pending_units, sim_headroom)
		sim_headroom -= take_pending
		sim_pending_milli = maxi(0, sim_pending_milli - take_pending * FARM_MILLI_PER_UNIT)

	var whole_units: int = 0
	var new_fractional_rem: int = int(src.get("fractional_remainder_milli", 0))
	if earnable_milli > 0:
		var total_available_milli: int = earnable_milli + new_fractional_rem
		whole_units = int(total_available_milli / FARM_MILLI_PER_UNIT)
		new_fractional_rem = total_available_milli % FARM_MILLI_PER_UNIT

	var delivered_from_new: int = 0
	var undelivered_from_new: int = 0
	var pause_after: bool = false
	var pause_reason: String = ""

	if whole_units > 0:
		if direct_to_economy:
			delivered_from_new = whole_units
		elif sim_headroom >= whole_units:
			delivered_from_new = whole_units
			sim_headroom -= whole_units
		elif sim_headroom > 0:
			delivered_from_new = sim_headroom
			undelivered_from_new = whole_units - delivered_from_new
			sim_headroom = 0
			sim_pending_milli += undelivered_from_new * FARM_MILLI_PER_UNIT
			pause_after = true
			pause_reason = "buffer_full"
		else:
			# Zero headroom for new whole units
			undelivered_from_new = whole_units
			sim_pending_milli += undelivered_from_new * FARM_MILLI_PER_UNIT
			pause_after = true
			pause_reason = "buffer_full"

	var total_to_deliver: int = take_pending + delivered_from_new
	if not direct_to_economy and total_to_deliver <= 0 and whole_units > 0 and headroom <= 0:
		return {
			"ok": true,
			"can_commit": true,
			"workplace_id": workplace_id,
			"day_seq": cur_day_seq,
			"new_daily_produced_milli": daily_produced + earnable_milli,
			"earnable_milli": earnable_milli,
			"drain_pending": 0,
			"delivered_to_buffer": 0,
			"delivered_to_economy": 0,
			"new_pending_output_milli": sim_pending_milli,
			"new_fractional_remainder_milli": new_fractional_rem,
			"should_pause": true,
			"pause_reason": "buffer_full",
			"direct_to_economy": direct_to_economy,
			"hour_seq": hour_seq,
			"is_full_buffer_block": true
		}

	var should_unpause: bool = false
	if not direct_to_economy and wp.is_paused and wp.pause_reason == "buffer_full":
		if (eff_cap - (int(wp.buffer_amount) + total_to_deliver)) > 0 and sim_pending_milli < FARM_MILLI_PER_UNIT:
			should_unpause = true

	return {
		"ok": true,
		"can_commit": true,
		"workplace_id": workplace_id,
		"day_seq": cur_day_seq,
		"new_daily_produced_milli": daily_produced + earnable_milli,
		"earnable_milli": earnable_milli,
		"drain_pending": take_pending,
		"delivered_to_buffer": total_to_deliver if not direct_to_economy else 0,
		"delivered_to_economy": delivered_from_new if direct_to_economy else 0,
		"new_pending_output_milli": sim_pending_milli,
		"new_fractional_remainder_milli": new_fractional_rem,
		"should_pause": pause_after,
		"pause_reason": pause_reason,
		"should_unpause": should_unpause,
		"direct_to_economy": direct_to_economy,
		"hour_seq": hour_seq,
		"is_full_buffer_block": false
	}

# Phase 2: Commit
static func commit_farm_production_transaction(ctx: RefCounted, prepared: Dictionary) -> Dictionary:
	if ctx == null or ctx.sim_state == null:
		return {"ok": false, "reason": "invalid_context"}
	if not bool(prepared.get("can_commit", false)):
		return {"ok": false, "reason": "cannot_commit"}
	prepared["can_commit"] = false

	var workplace_id: String = String(prepared.get("workplace_id", ""))
	var st = ctx.sim_state
	var wp = ctx.workplace_registry.get_workplace(workplace_id)
	var src: Dictionary = st.production_sources.get(workplace_id, {})
	var eff_cap: int = ctx.get_workplace_effective_buffer_capacity(workplace_id)

	# Apply day rollover and rate accrual
	src["current_day_seq"] = int(prepared.get("day_seq", 0))
	src["daily_produced_milli"] = int(prepared.get("new_daily_produced_milli", 0))
	src["fractional_remainder_milli"] = int(prepared.get("new_fractional_remainder_milli", 0))
	src["pending_output_milli"] = int(prepared.get("new_pending_output_milli", 0))

	var earnable_milli: int = int(prepared.get("earnable_milli", 0))
	if earnable_milli > 0:
		src["cycles_completed"] = int(src.get("cycles_completed", 0)) + 1
		src["cumulative_earned_milli"] = int(src.get("cumulative_earned_milli", 0)) + earnable_milli

	var delivered_buf: int = int(prepared.get("delivered_to_buffer", 0))
	var delivered_econ: int = int(prepared.get("delivered_to_economy", 0))

	if delivered_econ > 0 and ctx.economy != null:
		var cred_res: Dictionary = ctx.economy.credit_resource(
			"food",
			delivered_econ,
			"workplace_output:%s" % workplace_id,
			"farmer_production",
			int(prepared.get("hour_seq", 0))
		)
		if bool(cred_res.get("ok", false)):
			st.stats["produced"] = int(st.stats.get("produced", 0)) + delivered_econ
			src["total_produced"] = int(src.get("total_produced", 0)) + delivered_econ
		else:
			# Rollback and preserve in pending
			src["pending_output_milli"] = int(src["pending_output_milli"]) + delivered_econ * FARM_MILLI_PER_UNIT
			wp.is_paused = true
			wp.pause_reason = "storage_full"
			return {"ok": false, "reason": String(cred_res.get("reason", "economy_credit_failed"))}
	elif delivered_buf > 0:
		wp.buffer_amount = int(wp.buffer_amount) + delivered_buf
		wp.buffer_capacity = maxi(eff_cap, int(wp.buffer_amount))
		st.stats["produced"] = int(st.stats.get("produced", 0)) + delivered_buf
		src["total_produced"] = int(src.get("total_produced", 0)) + delivered_buf

	if bool(prepared.get("should_pause", false)):
		wp.is_paused = true
		wp.pause_reason = String(prepared.get("pause_reason", "buffer_full"))
	elif bool(prepared.get("should_unpause", false)):
		wp.is_paused = false
		wp.pause_reason = ""

	# If this was a full buffer blockage with 0 delivery, return ok: false so caller knows buffer is blocked
	if bool(prepared.get("is_full_buffer_block", false)):
		return {
			"ok": false,
			"reason": "buffer_full",
			"workplace_id": workplace_id,
			"food_produced": 0,
			"pending_output_milli": int(src["pending_output_milli"]),
			"buffer_amount": int(wp.buffer_amount),
			"fractional_remainder_milli": int(src["fractional_remainder_milli"]),
			"cumulative_earned_milli": int(src.get("cumulative_earned_milli", 0))
		}

	return {
		"ok": true,
		"workplace_id": workplace_id,
		"food_produced": delivered_buf + delivered_econ,
		"pending_output_milli": int(src["pending_output_milli"]),
		"buffer_amount": int(wp.buffer_amount),
		"fractional_remainder_milli": int(src["fractional_remainder_milli"]),
		"cumulative_earned_milli": int(src.get("cumulative_earned_milli", 0))
	}

# Unified execute wrapper
static func execute_farm_production_transaction(
	ctx: RefCounted,
	workplace_id: String,
	time_manager: Node = null,
	direct_to_economy: bool = false,
	hour_seq: int = 0,
	tool_mod_override: float = -1.0,
	farmer_count_override: int = -1
) -> Dictionary:
	var prepared := prepare_farm_production_transaction(
		ctx, workplace_id, time_manager, direct_to_economy, hour_seq, tool_mod_override, farmer_count_override
	)
	if not bool(prepared.get("ok", false)):
		if ctx != null and ctx.sim_state != null:
			var r: String = String(prepared.get("reason", ""))
			if r == "missing_verified_production_source" or r == "unsupported_production_building" or r == "resource_mismatch":
				ctx.sim_state.production_blocked[workplace_id] = r
		return prepared
	if not bool(prepared.get("can_commit", false)):
		return prepared
	return commit_farm_production_transaction(ctx, prepared)

static func process_farm_workplace_production(
	ctx: RefCounted,
	workplace_id: String,
	time_manager: Node = null
) -> Dictionary:
	var h_seq: int = 0
	if time_manager != null and is_instance_valid(time_manager) and time_manager.has_method("get_hour_seq"):
		h_seq = int(time_manager.get_hour_seq())
	return execute_farm_production_transaction(ctx, workplace_id, time_manager, false, h_seq)

static func try_deposit_pending_farm_output(
	ctx: RefCounted,
	workplace_id: String,
	_time_manager: Node = null
) -> Dictionary:
	if ctx == null or ctx.sim_state == null:
		return {"ok": false, "reason": "invalid_context"}
	var st = ctx.sim_state
	if not st.production_sources.has(workplace_id):
		return {"ok": false, "reason": "missing_production_source"}
	var src: Dictionary = st.production_sources[workplace_id]
	if int(src.get("pending_output_milli", 0)) < FARM_MILLI_PER_UNIT:
		return {"ok": true, "reason": "no_pending_output", "deposited": 0}
	var wp = ctx.workplace_registry.get_workplace(workplace_id)
	if wp == null:
		return {"ok": false, "reason": "workplace_not_found"}

	var eff_cap: int = ctx.get_workplace_effective_buffer_capacity(workplace_id)
	var headroom: int = maxi(0, eff_cap - int(wp.buffer_amount))
	if headroom <= 0:
		wp.is_paused = true
		wp.pause_reason = "buffer_full"
		return {"ok": false, "reason": "buffer_full", "headroom": 0}

	var pending_milli: int = int(src.get("pending_output_milli", 0))
	var pending_units: int = int(pending_milli / FARM_MILLI_PER_UNIT)
	var take: int = mini(pending_units, headroom)
	if take <= 0:
		return {"ok": true, "deposited": 0}

	wp.buffer_amount = int(wp.buffer_amount) + take
	wp.buffer_capacity = maxi(eff_cap, int(wp.buffer_amount))
	st.stats["produced"] = int(st.stats.get("produced", 0)) + take
	src["total_produced"] = int(src.get("total_produced", 0)) + take

	src["pending_output_milli"] = maxi(0, pending_milli - take * FARM_MILLI_PER_UNIT)

	if (eff_cap - int(wp.buffer_amount)) > 0 and int(src.get("pending_output_milli", 0)) < FARM_MILLI_PER_UNIT:
		if wp.is_paused and wp.pause_reason == "buffer_full":
			wp.is_paused = false
			wp.pause_reason = ""

	return {
		"ok": true,
		"deposited": take,
		"remaining_pending_milli": int(src["pending_output_milli"]),
		"buffer_amount": int(wp.buffer_amount)
	}

static func reconcile_farm_seasonal_transition(
	ctx: RefCounted,
	workplace_id: String,
	new_season_key: String,
	year: int
) -> bool:
	if ctx == null or ctx.sim_state == null:
		return false
	var st = ctx.sim_state
	if not st.production_sources.has(workplace_id):
		return false
	var src: Dictionary = st.production_sources[workplace_id]
	var wp = ctx.workplace_registry.get_workplace(workplace_id)
	if wp == null or wp.building_type != "farm":
		return false

	var season_id: String = "%s:%d" % [new_season_key, year]
	var last_season: String = String(src.get("last_season_seen", ""))
	if last_season == season_id:
		return false

	# Season changed: record new season. Completed pending output is preserved (no invented spoilage).
	src["last_season_seen"] = season_id

	var eff_cap: int = ctx.get_workplace_effective_buffer_capacity(workplace_id)
	if wp.is_paused and wp.pause_reason == "buffer_full":
		if (eff_cap - int(wp.buffer_amount)) > 0 and int(src.get("pending_output_milli", 0)) < FARM_MILLI_PER_UNIT:
			wp.is_paused = false
			wp.pause_reason = ""
			return true

	return true

# -----------------------------------------------------------------------------
# Hunter Production & Canonical Wildlife Tracking (Phase 4 / P4-20 / H1)
# -----------------------------------------------------------------------------

## Deterministically allocates huntable canonical wildlife (Rabbit & Deer) across active
## Town Hall Hunter workplaces in registered settlement contexts.
static func allocate_global_hunter_sources(
	contexts: Array,
	world_data: RefCounted,
	player_center: Vector2i = Vector2i(-999, -999)
) -> Dictionary:
	if world_data == null:
		return {}
	var wildlife_list: Array = world_data.get("wildlife") if "wildlife" in world_data else []
	if wildlife_list.is_empty():
		return {}

	# 1. Discover all active Hunter workplaces across all contexts
	var hunter_workplaces: Array[Dictionary] = []
	for ctx in contexts:
		if ctx == null or ctx.workplace_registry == null:
			continue
		for wp in ctx.workplace_registry.get_all_workplaces():
			if wp == null or not wp.is_active:
				continue
			if wp.output_resource == EconomyConfigScript.RES_RAW_MEAT or wp.workplace_id.ends_with("__hunter"):
				var w_cell: Vector2i = wp.access_cell if wp.access_cell != Vector2i.ZERO else wp.origin_cell
				hunter_workplaces.append({
					"ctx": ctx,
					"wp": wp,
					"cell": w_cell,
					"workplace_id": wp.workplace_id,
					"settlement_id": ctx.settlement_id
				})

	if hunter_workplaces.is_empty():
		return {}

	# Sort workplaces deterministically
	hunter_workplaces.sort_custom(func(a, b):
		if a["settlement_id"] != b["settlement_id"]:
			return a["settlement_id"] < b["settlement_id"]
		return a["workplace_id"] < b["workplace_id"]
	)

	var allocations: Dictionary = {}
	for hwp in hunter_workplaces:
		allocations[hwp["workplace_id"]] = []

	# 2. Assign each huntable animal to the nearest hunter workplace
	for rec in wildlife_list:
		if not (rec is Dictionary):
			continue
		var sp: String = String(rec.get("species_id", ""))
		if sp != "rabbit" and sp != "deer":
			continue
		var a_cell: Vector2i = rec.get("cell", Vector2i(-1, -1))
		if a_cell.x < 0 or a_cell.y < 0:
			continue

		var best_wpid: String = ""
		var best_dist: int = 999999
		var best_sid: String = ""

		for hwp in hunter_workplaces:
			var d: int = IsoMath.grid_distance(a_cell, hwp["cell"])
			if d > 40:
				continue
			if d < best_dist:
				best_dist = d
				best_wpid = hwp["workplace_id"]
				best_sid = hwp["settlement_id"]
			elif d == best_dist:
				if hwp["settlement_id"] < best_sid or (hwp["settlement_id"] == best_sid and hwp["workplace_id"] < best_wpid):
					best_wpid = hwp["workplace_id"]
					best_sid = hwp["settlement_id"]

		if not best_wpid.is_empty():
			var a_id: String = String(rec.get("id", ""))
			rec["allocated_workplace_id"] = best_wpid
			rec["allocated_settlement_id"] = best_sid
			(allocations[best_wpid] as Array).append(a_id)

	return allocations

## Registers a verified hunter source for a Town Hall Hunter workplace.
static func register_hunter_source(
	ctx: RefCounted,
	workplace_id: String,
	world_data: RefCounted = null,
	assigned_animals: Array = []
) -> Dictionary:
	if ctx == null or ctx.sim_state == null:
		return {"ok": false, "reason": "invalid_context"}
	if ctx.workplace_registry == null or not ctx.workplace_registry.has_workplace(workplace_id):
		return {"ok": false, "reason": "workplace_not_found"}

	var wp = ctx.workplace_registry.get_workplace(workplace_id)
	if wp == null or (wp.output_resource != EconomyConfigScript.RES_RAW_MEAT and not wp.workplace_id.ends_with("__hunter") and wp.building_type != "townhall"):
		return {"ok": false, "reason": "invalid_workplace_type"}

	# Idempotency
	if ctx.sim_state.production_sources.has(workplace_id):
		var ex_src: Dictionary = ctx.sim_state.production_sources[workplace_id]
		return {
			"ok": true,
			"workplace_id": workplace_id,
			"already_registered": true,
			"type": "hunter_source",
			"allocated_count": (ex_src.get("allocated_animals", []) as Array).size()
		}

	var bound_animal_ids: Array[String] = []
	if not assigned_animals.is_empty():
		for item in assigned_animals:
			var aid: String = ""
			if item is String:
				aid = item
			elif item is Dictionary and item.has("id"):
				aid = String(item["id"])
			if not aid.is_empty() and not bound_animal_ids.has(aid):
				bound_animal_ids.append(aid)
				if world_data != null and world_data.has_method("get_animal_by_id"):
					var a_rec: Dictionary = world_data.get_animal_by_id(aid)
					if not a_rec.is_empty():
						a_rec["allocated_workplace_id"] = workplace_id
						a_rec["allocated_settlement_id"] = ctx.settlement_id
	elif world_data != null and ("wildlife" in world_data):
		var wl: Array = world_data.wildlife
		for rec in wl:
			if rec is Dictionary:
				if String(rec.get("allocated_workplace_id", "")) == workplace_id:
					bound_animal_ids.append(String(rec.get("id", "")))

	var src_desc: Dictionary = {
		"type": "hunter_source",
		"resource": EconomyConfigScript.RES_RAW_MEAT,
		"workplace_id": workplace_id,
		"allocated_animals": bound_animal_ids,
		"remaining": bound_animal_ids.size(),
		"pending_output": 0,
		"cycles_completed": 0,
		"total_produced": 0,
		"current_prey_id": "",
	}

	ctx.sim_state.production_sources[workplace_id] = src_desc
	ctx.sim_state.production_blocked.erase(workplace_id)

	return {
		"ok": true,
		"workplace_id": workplace_id,
		"type": "hunter_source",
		"allocated_count": bound_animal_ids.size()
	}

static func register_all_hunter_sources(
	contexts: Array,
	world_data: RefCounted = null,
	player_center: Vector2i = Vector2i(-999, -999)
) -> int:
	if world_data != null and ("wildlife" in world_data):
		allocate_global_hunter_sources(contexts, world_data, player_center)

	var count: int = 0
	for ctx in contexts:
		if ctx == null or ctx.workplace_registry == null:
			continue
		for wp in ctx.workplace_registry.get_all_workplaces():
			if wp != null and wp.is_active and (wp.output_resource == EconomyConfigScript.RES_RAW_MEAT or wp.workplace_id.ends_with("__hunter")):
				var res := register_hunter_source(ctx, wp.workplace_id, world_data)
				if bool(res.get("ok", false)):
					count += 1
	return count

static func prepare_hunter_production_transaction(
	ctx: RefCounted,
	workplace_id: String,
	world_data: RefCounted,
	time_manager: Node = null,
	villager: RefCounted = null,
	delta_hours: float = 1.0,
	hour_seq: int = -1
) -> Dictionary:
	if ctx == null or ctx.sim_state == null:
		return {"ok": false, "reason": "invalid_context", "can_commit": false}
	if ctx.workplace_registry == null or not ctx.workplace_registry.has_workplace(workplace_id):
		return {"ok": false, "reason": "workplace_not_found", "can_commit": false}

	var wp = ctx.workplace_registry.get_workplace(workplace_id)
	if wp == null or (wp.output_resource != EconomyConfigScript.RES_RAW_MEAT and not wp.workplace_id.ends_with("__hunter") and wp.building_type != "townhall"):
		return {"ok": false, "reason": "invalid_workplace_type", "can_commit": false}
	if not wp.is_active:
		return {"ok": false, "reason": "workplace_inactive", "can_commit": false}
	if wp.is_paused:
		return {"ok": false, "reason": "workplace_paused", "can_commit": false}

	var st = ctx.sim_state
	if not st.production_sources.has(workplace_id):
		return {"ok": false, "reason": "missing_verified_production_source", "can_commit": false}

	var src: Dictionary = st.production_sources[workplace_id]
	if String(src.get("type", "")) != "hunter_source":
		return {"ok": false, "reason": "source_type_mismatch", "can_commit": false}

	var eff_h_seq: int = hour_seq
	if eff_h_seq < 0:
		if time_manager != null and is_instance_valid(time_manager) and time_manager.has_method("get_hour_seq"):
			eff_h_seq = int(time_manager.get_hour_seq())
		else:
			eff_h_seq = 0

	if not is_day_shift_hour(eff_h_seq):
		return {"ok": false, "reason": "outside_day_shift", "can_commit": false}

	if villager == null:
		return {"ok": false, "reason": "missing_hunter_villager", "can_commit": false}
	if villager.life_state != SettlementVillagerDataScript.LIFE_ALIVE:
		return {"ok": false, "reason": "villager_not_alive", "can_commit": false}
	if villager.role != SettlementVillagerDataScript.ROLE_HUNTER:
		return {"ok": false, "reason": "villager_role_mismatch", "can_commit": false}

	if world_data == null:
		return {"ok": false, "reason": "missing_world_data", "can_commit": false}

	# Identify or validate target prey
	var target_prey_id: String = String(src.get("current_prey_id", ""))
	var prey_rec: Dictionary = {}
	if not target_prey_id.is_empty():
		prey_rec = world_data.get_animal_by_id(target_prey_id) if world_data.has_method("get_animal_by_id") else {}
		var is_avail: bool = bool(prey_rec.get("is_available", true))
		var res_by: String = String(prey_rec.get("reserved_by", ""))
		if prey_rec.is_empty() or (not is_avail and res_by != villager.villager_id):
			target_prey_id = ""
			prey_rec = {}

	if target_prey_id.is_empty():
		var allocated: Array = src.get("allocated_animals", [])
		for aid in allocated:
			var cand_rec: Dictionary = world_data.get_animal_by_id(aid) if world_data.has_method("get_animal_by_id") else {}
			if cand_rec.is_empty():
				continue
			if not bool(cand_rec.get("is_available", true)):
				continue
			if not String(cand_rec.get("reserved_by", "")).is_empty():
				continue
			if float(cand_rec.get("recovery_hours_left", 0.0)) > 0.0:
				continue
			target_prey_id = String(aid)
			prey_rec = cand_rec
			break

	if target_prey_id.is_empty() or prey_rec.is_empty():
		return {"ok": false, "reason": "no_available_prey", "can_commit": false}

	var sp: String = String(prey_rec.get("species_id", ""))
	var req_hours: float = 1.5 if sp == "rabbit" else 2.5
	var yield_amt: int = 2 if sp == "rabbit" else 4
	var rec_hours: float = 48.0 if sp == "rabbit" else 72.0

	var prev_done: float = float(villager.work_hours_done)
	var new_done: float = prev_done + delta_hours
	var hunt_completed: bool = new_done >= req_hours
	var remainder_hours: float = (new_done - req_hours) if hunt_completed else new_done
	var meat_to_deliver: int = yield_amt if hunt_completed else 0

	# Category E: fail closed if settlement raw meat storage capacity is full
	if hunt_completed and meat_to_deliver > 0 and ctx.economy != null:
		var cur_meat: int = ctx.economy.get_resource(EconomyConfigScript.RES_RAW_MEAT) if ctx.economy.has_method("get_resource") else (ctx.economy.get_stock(EconomyConfigScript.RES_RAW_MEAT) if ctx.economy.has_method("get_stock") else 0)
		var cap_meat: int = ctx.economy.get_capacity(EconomyConfigScript.RES_RAW_MEAT) if ctx.economy.has_method("get_capacity") else 999999
		if cur_meat + meat_to_deliver > cap_meat:
			return {
				"ok": false,
				"reason": "storage_full",
				"can_commit": false,
				"workplace_id": workplace_id,
				"current_stock": cur_meat,
				"capacity": cap_meat
			}

	return {
		"ok": true,
		"can_commit": true,
		"workplace_id": workplace_id,
		"villager": villager,
		"target_prey_id": target_prey_id,
		"prey_species": sp,
		"req_hours": req_hours,
		"yield_amount": yield_amt,
		"recovery_hours": rec_hours,
		"delta_hours": delta_hours,
		"new_work_hours_done": remainder_hours,
		"hunt_completed": hunt_completed,
		"meat_to_deliver": meat_to_deliver,
		"hour_seq": eff_h_seq
	}

static func commit_hunter_production_transaction(
	ctx: RefCounted,
	prepared: Dictionary,
	world_data: RefCounted
) -> Dictionary:
	if ctx == null or ctx.sim_state == null:
		return {"ok": false, "reason": "invalid_context"}
	if not bool(prepared.get("can_commit", false)):
		return {"ok": false, "reason": "cannot_commit"}
	prepared["can_commit"] = false

	var wpid: String = String(prepared.get("workplace_id", ""))
	var villager: RefCounted = prepared.get("villager")
	var target_prey_id: String = String(prepared.get("target_prey_id", ""))
	var hunt_completed: bool = bool(prepared.get("hunt_completed", false))
	var meat_to_deliver: int = int(prepared.get("meat_to_deliver", 0))
	var new_done: float = float(prepared.get("new_work_hours_done", 0.0))
	var h_seq: int = int(prepared.get("hour_seq", 0))

	var src: Dictionary = ctx.sim_state.production_sources.get(wpid, {})
	var prey_rec: Dictionary = world_data.get_animal_by_id(target_prey_id) if (world_data != null and world_data.has_method("get_animal_by_id")) else {}

	villager.work_hours_done = new_done

	if hunt_completed:
		src["current_prey_id"] = ""
		src["cycles_completed"] = int(src.get("cycles_completed", 0)) + 1
		src["total_produced"] = int(src.get("total_produced", 0)) + meat_to_deliver
		ctx.sim_state.stats["produced"] = int(ctx.sim_state.stats.get("produced", 0)) + meat_to_deliver

		# Update animal record to recovery
		if not prey_rec.is_empty():
			prey_rec["is_available"] = false
			prey_rec["reserved_by"] = ""
			prey_rec["reservation_type"] = ""
			prey_rec["recovery_hours_left"] = float(prepared.get("recovery_hours", 48.0))

		# Credit raw meat to settlement economy stock
		if ctx.economy != null:
			var cred_res: Dictionary = ctx.economy.credit_resource(
				EconomyConfigScript.RES_RAW_MEAT,
				meat_to_deliver,
				"workplace_output:%s" % wpid,
				"hunter_production",
				h_seq
			)
			if not bool(cred_res.get("ok", false)):
				var fail_reason: String = String(cred_res.get("reason", "credit_failed"))
				if fail_reason == "exceeds_capacity":
					fail_reason = "storage_full"
				return {"ok": false, "reason": fail_reason}
	else:
		src["current_prey_id"] = target_prey_id
		if not prey_rec.is_empty():
			prey_rec["is_available"] = false
			prey_rec["reserved_by"] = villager.villager_id
			prey_rec["reservation_type"] = "rival"

	return {
		"ok": true,
		"workplace_id": wpid,
		"villager_id": villager.villager_id,
		"prey_id": target_prey_id,
		"species_id": String(prepared.get("prey_species", "")),
		"hunt_completed": hunt_completed,
		"meat_produced": meat_to_deliver,
		"work_hours_done": new_done,
		"hour_seq": h_seq
	}

static func execute_hunter_production_transaction(
	ctx: RefCounted,
	workplace_id: String,
	world_data: RefCounted,
	time_manager: Node = null,
	villager: RefCounted = null,
	delta_hours: float = 1.0,
	hour_seq: int = -1
) -> Dictionary:
	var prep := prepare_hunter_production_transaction(
		ctx, workplace_id, world_data, time_manager, villager, delta_hours, hour_seq
	)
	if not bool(prep.get("ok", false)) or not bool(prep.get("can_commit", false)):
		return prep
	return commit_hunter_production_transaction(ctx, prep, world_data)

static func advance_wildlife_recovery(world_data: RefCounted, delta_hours: float = 1.0) -> int:
	if world_data == null:
		return 0
	var wl: Array = world_data.get("wildlife") if "wildlife" in world_data else []
	if wl.is_empty():
		return 0
	var recovered_count: int = 0
	for rec in wl:
		if not (rec is Dictionary):
			continue
		var rec_hours: float = float(rec.get("recovery_hours_left", 0.0))
		if rec_hours > 0.0:
			rec_hours = maxf(0.0, rec_hours - delta_hours)
			rec["recovery_hours_left"] = rec_hours
			if rec_hours <= 0.0:
				rec["is_available"] = true
				rec["reserved_by"] = ""
				rec["reservation_type"] = ""
				recovered_count += 1
	return recovered_count

