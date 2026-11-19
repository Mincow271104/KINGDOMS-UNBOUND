class_name SettlementVillagerContext
extends RefCounted
## Settlement-local NPC villager container, deterministic ID allocator, and boundary owner
## (Architecture v1.0 — Phase 1).
## Owns canonical SettlementVillagerData records, SettlementJobBoard, and SettlementWorkplaceRegistry
## for a single rival settlement. Strictly isolated from player systems and other settlements.
##
## Memory & Identity Guarantee:
## Uses a monotonic sequence watermark (`_next_villager_seq`) plus a transient `_unclaimed_allocated_seqs`
## set for IDs allocated via `allocate_villager_id()` that have not yet been inserted via `add_villager()`.
## Any sequence `< _next_villager_seq` not in `_unclaimed_allocated_seqs` is either active in `_villagers_by_id`
## or permanently retired, guaranteeing O(1) allocator memory with zero reuse or reinsertion of removed IDs.

const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementJobBoardScript = preload("res://scripts/world/settlement_job_board.gd")
const SettlementWorkplaceRegistryScript = preload("res://scripts/world/settlement_workplace_registry.gd")
const SettlementEconomyScript = preload("res://scripts/world/settlement_economy.gd")
const SettlementBuildingCapabilityAdapterScript = preload("res://scripts/world/settlement_building_capability_adapter.gd")
const SettlementSimulationStateScript = preload("res://scripts/world/settlement_simulation_state.gd")

var _settlement_id: String = ""
var _origin_faction_id: String = ""
var _owner_faction_id: String = ""

var settlement_id: String:
	get:
		return _settlement_id
	set(value):
		if not _settlement_id.is_empty():
			return
		var clean := value.strip_edges()
		if is_valid_settlement_id(clean):
			_settlement_id = clean

var origin_faction_id: String:
	get:
		return _origin_faction_id
	set(value):
		if not _origin_faction_id.is_empty():
			return
		var clean := value.strip_edges()
		if SettlementVillagerDataScript.is_valid_identifier(clean):
			_origin_faction_id = clean

var owner_faction_id: String:
	get:
		return _owner_faction_id
	set(value):
		var clean := value.strip_edges()
		if SettlementVillagerDataScript.is_valid_identifier(clean):
			_owner_faction_id = clean

var _next_villager_seq: int = 1
var _unclaimed_allocated_seqs: Dictionary = {} # seq (int) -> true
var _villagers_by_id: Dictionary = {} # villager_id (String) -> SettlementVillagerData
var _sorted_villagers_cache: Array = []
var _sorted_cache_dirty: bool = true
var _cache_rebuild_count: int = 0
var _cache_id_parse_count: int = 0
var _cache_hit_count: int = 0

var job_board: RefCounted = null
var workplace_registry: RefCounted = null
var _economy: RefCounted = null
var sim_state: RefCounted = null

# Derived Phase 3 building capabilities & housing state (rebuilt deterministically from SettlementData.buildings)
var _housing_capacity: int = 0
var _residential_buildings: Array[Dictionary] = []
var _building_descriptors: Array[Dictionary] = []
var _final_storage_ids: Array[String] = []
var _receiving_buffer_ids: Array[String] = []
var _output_buffer_ids: Array[String] = []
var _transport_routes: Array[Dictionary] = []
var _patrol_target_ids: Array[String] = []
var _patrol_targets: Array[Dictionary] = []
var _guard_patrol_descriptors: Array[Dictionary] = []

# Workplace effective buffer capacity tracking & salvaged buffer conservation (Review B)
var _workplace_effective_buffer_capacities: Dictionary = {} # workplace_id (String) -> int
var _salvaged_workplace_buffers: Dictionary = {} # workplace_id (String) -> Dictionary

var economy: RefCounted:
	get:
		return _economy
	set(value):
		set_economy(value)

func _init(
	p_settlement_id: String = "",
	p_origin_faction_id: String = "",
	p_owner_faction_id: String = "",
	p_initial_next_seq: int = 1,
	p_initialize_economy_endowment: bool = true
) -> void:
	_settlement_id = p_settlement_id.strip_edges()
	_origin_faction_id = p_origin_faction_id.strip_edges()
	_owner_faction_id = p_owner_faction_id.strip_edges() if not p_owner_faction_id.strip_edges().is_empty() else _origin_faction_id
	_next_villager_seq = maxi(1, p_initial_next_seq)
	_unclaimed_allocated_seqs = {}
	_villagers_by_id = {}
	job_board = SettlementJobBoardScript.new(_settlement_id)
	workplace_registry = SettlementWorkplaceRegistryScript.new(_settlement_id)
	_economy = SettlementEconomyScript.new(_settlement_id, _origin_faction_id, p_initialize_economy_endowment)
	sim_state = SettlementSimulationStateScript.new()

func set_economy(p_economy: RefCounted) -> bool:
	if p_economy == null or not p_economy.has_method("is_valid") or not p_economy.is_valid():
		return false
	if p_economy.settlement_id != _settlement_id or p_economy.origin_faction_id != _origin_faction_id:
		return false
	_economy = p_economy
	return true

static func is_valid_settlement_id(sid: String) -> bool:
	return SettlementVillagerDataScript.is_valid_identifier(sid)

static func format_villager_id(sid: String, seq: int) -> String:
	if not is_valid_settlement_id(sid) or seq < 1:
		return ""
	return "npc_%s_%d" % [sid, seq]

func is_valid() -> bool:
	if not is_valid_settlement_id(settlement_id):
		return false
	if not SettlementVillagerDataScript.is_valid_identifier(origin_faction_id):
		return false
	if not SettlementVillagerDataScript.is_valid_identifier(owner_faction_id):
		return false
	if _next_villager_seq < 1:
		return false
	return true

func get_next_sequence() -> int:
	return _next_villager_seq

func allocate_villager_id() -> String:
	if not is_valid():
		return ""
	var seq: int = _next_villager_seq
	var vid: String = format_villager_id(settlement_id, seq)
	_next_villager_seq += 1
	while _villagers_by_id.has(vid) or _unclaimed_allocated_seqs.has(seq):
		seq = _next_villager_seq
		vid = format_villager_id(settlement_id, seq)
		_next_villager_seq += 1
	_unclaimed_allocated_seqs[seq] = true
	return vid

func restore_allocator_state(next_seq: int, historical_ids: Array = []) -> bool:
	if not is_valid() or next_seq < 1:
		return false
	var computed_next: int = maxi(_next_villager_seq, next_seq)
	for hid in historical_ids:
		if not (hid is String):
			return false
		var parsed := SettlementVillagerDataScript.parse_villager_sequence_for_settlement(String(hid), settlement_id)
		if parsed < 1:
			return false
		if parsed >= computed_next:
			computed_next = parsed + 1
	for existing_id in _villagers_by_id.keys():
		var parsed_ex := SettlementVillagerDataScript.parse_villager_sequence_for_settlement(String(existing_id), settlement_id)
		if parsed_ex >= computed_next:
			computed_next = parsed_ex + 1
	_next_villager_seq = computed_next
	_unclaimed_allocated_seqs.clear()
	return true

func add_villager(villager: RefCounted) -> bool:
	return _add_villager_internal(villager, false)

## Safe registration contract for a villager admitted while an hourly or daily queue is active (Phase 4 §6.5).
## Stamps `last_processed_hour_seq` to `sim_state.required_hour_seq` and records `latest_captured_daily_seq`
## so the new villager begins on the next eligible tick and is never retroactively charged.
func register_villager_for_next_tick(villager: RefCounted) -> bool:
	if villager == null or sim_state == null:
		return false
	var target_h: int = maxi(0, int(sim_state.required_hour_seq))
	villager.last_processed_hour_seq = maxi(int(villager.last_processed_hour_seq), target_h)
	if not add_villager(villager):
		return false
	sim_state.registered[villager.villager_id] = target_h
	if int(sim_state.latest_captured_daily_seq) >= 0:
		sim_state.villager_daily_seq[villager.villager_id] = int(sim_state.latest_captured_daily_seq)
	return true

func _add_villager_internal(villager: RefCounted, is_restoring_snapshot: bool) -> bool:
	if not is_valid() or villager == null:
		return false
	if not villager.is_valid():
		return false
	# Strict settlement isolation: reject cross-settlement villagers
	if villager.settlement_id != settlement_id or not is_valid_settlement_id(villager.home_settlement_id):
		return false
	if not is_restoring_snapshot and villager.home_settlement_id != settlement_id:
		return false
	var parsed_seq: int = SettlementVillagerDataScript.parse_villager_sequence_for_settlement(villager.villager_id, settlement_id)
	if parsed_seq < 1:
		return false
	# Reject duplicate active IDs
	if _villagers_by_id.has(villager.villager_id):
		return false

	if not is_restoring_snapshot:
		# During runtime, a sequence < _next_villager_seq is only valid if it was just allocated
		# by allocate_villager_id() and not yet claimed or removed. Any other sequence < _next_villager_seq
		# is a retired/historical sequence and is strictly rejected.
		if parsed_seq < _next_villager_seq and not _unclaimed_allocated_seqs.has(parsed_seq):
			return false

	if villager.has_method("lock_identity"):
		villager.lock_identity()
	_unclaimed_allocated_seqs.erase(parsed_seq)
	_villagers_by_id[villager.villager_id] = villager
	_sorted_cache_dirty = true
	if parsed_seq >= _next_villager_seq:
		_next_villager_seq = parsed_seq + 1
	return true

func create_and_add_villager(
	p_name: String = "",
	p_role: String = SettlementVillagerDataScript.ROLE_IDLE,
	p_cell: Vector2i = Vector2i.ZERO
) -> RefCounted:
	if not is_valid():
		return null
	var vid: String = allocate_villager_id()
	if vid.is_empty():
		return null
	var v := SettlementVillagerDataScript.new(vid, settlement_id, origin_faction_id, p_name, p_role, p_cell)
	v.current_faction_id = owner_faction_id
	if not add_villager(v):
		return null
	return v

## Returns the live canonical SettlementVillagerData reference for `villager_id`, or `null` if absent.
## Mutations to the returned object directly update canonical villager state in this context.
func get_villager(villager_id: String) -> RefCounted:
	return _villagers_by_id.get(villager_id, null)

func has_villager(villager_id: String) -> bool:
	return _villagers_by_id.has(villager_id)

func remove_villager(villager_id: String) -> bool:
	if not _villagers_by_id.has(villager_id):
		return false
	var parsed_seq: int = SettlementVillagerDataScript.parse_villager_sequence_for_settlement(villager_id, settlement_id)
	_unclaimed_allocated_seqs.erase(parsed_seq)
	_villagers_by_id.erase(villager_id)
	_sorted_cache_dirty = true
	if parsed_seq >= _next_villager_seq:
		_next_villager_seq = parsed_seq + 1
	if job_board != null:
		for j in job_board.get_all_jobs():
			if j.assigned_villager_id == villager_id:
				j.assigned_villager_id = ""
				if j.state == SettlementJobBoardScript.STATE_RESERVED or j.state == SettlementJobBoardScript.STATE_IN_PROGRESS:
					j.state = SettlementJobBoardScript.STATE_AVAILABLE
	return true

func _rebuild_sorted_cache_if_needed() -> void:
	if not _sorted_cache_dirty:
		_cache_hit_count += 1
		return
	_cache_rebuild_count += 1
	var keyed: Array[Dictionary] = []
	keyed.resize(_villagers_by_id.size())
	var idx: int = 0
	for v in _villagers_by_id.values():
		_cache_id_parse_count += 1
		var seq: int = SettlementVillagerDataScript.parse_villager_sequence_for_settlement(v.villager_id, v.settlement_id)
		keyed[idx] = {"v": v, "seq": seq, "id": v.villager_id}
		idx += 1
	keyed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa: int = int(a["seq"])
		var sb: int = int(b["seq"])
		if sa != sb:
			return sa < sb
		return String(a["id"]) < String(b["id"])
	)
	_sorted_villagers_cache.clear()
	_sorted_villagers_cache.resize(keyed.size())
	for i in range(keyed.size()):
		_sorted_villagers_cache[i] = keyed[i]["v"]
	_sorted_cache_dirty = false

## Returns a newly allocated Array sorted by villager sequence containing the live canonical
## SettlementVillagerData references. Mutating the returned Array container does not affect
## context membership; mutating a returned SettlementVillagerData element updates canonical state.
func get_all_villagers() -> Array:
	_rebuild_sorted_cache_if_needed()
	return _sorted_villagers_cache.duplicate()

## Internal read-only-by-contract cached view (zero-allocation for trusted simulation/presentation loops).
## Callers MUST NOT mutate the returned Array.
func get_all_villagers_cached_view() -> Array:
	_rebuild_sorted_cache_if_needed()
	return _sorted_villagers_cache

func get_villager_cache_telemetry() -> Dictionary:
	return {
		"rebuilds": _cache_rebuild_count,
		"id_parses": _cache_id_parse_count,
		"hits": _cache_hit_count,
		"cached_size": _sorted_villagers_cache.size(),
		"dirty": _sorted_cache_dirty,
	}

func reset_villager_cache_telemetry() -> void:
	_cache_rebuild_count = 0
	_cache_id_parse_count = 0
	_cache_hit_count = 0

func get_villager_count() -> int:
	return _villagers_by_id.size()

# -----------------------------------------------------------------------------
# Phase 3: Housing Capacity, Building Capability Derivation & Job Reconciliation
# -----------------------------------------------------------------------------
func get_housing_capacity() -> int:
	return _housing_capacity

func get_available_housing_slots() -> int:
	return maxi(0, _housing_capacity - get_villager_count())

func is_at_housing_capacity() -> bool:
	return get_villager_count() >= _housing_capacity

func get_residential_buildings() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rb in _residential_buildings:
		out.append(rb.duplicate(true))
	return out

func get_building_descriptors() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for bd in _building_descriptors:
		out.append(bd.duplicate(true))
	return out

func get_final_storage_ids() -> Array[String]:
	return _final_storage_ids.duplicate()

func get_receiving_buffer_ids() -> Array[String]:
	return _receiving_buffer_ids.duplicate()

func get_output_buffer_ids() -> Array[String]:
	return _output_buffer_ids.duplicate()

func get_transport_routes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for tr in _transport_routes:
		out.append(tr.duplicate(true))
	return out

func get_patrol_target_ids() -> Array[String]:
	return _patrol_target_ids.duplicate()

func get_patrol_targets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pt in _patrol_targets:
		out.append(pt.duplicate(true))
	return out

func get_guard_patrol_descriptors() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for gp in _guard_patrol_descriptors:
		out.append(gp.duplicate(true))
	return out

func get_guard_patrol_for_job(job_id: String) -> Dictionary:
	if job_board == null or not job_board.has_job(job_id):
		return {"ok": false, "reason": "job_not_found"}
	var j = job_board.get_job(job_id)
	if j.settlement_id != _settlement_id or j.job_type != SettlementVillagerDataScript.ROLE_GUARD:
		return {"ok": false, "reason": "not_a_guard_job"}
	var barracks_id: String = j.workplace_id
	for gp in _guard_patrol_descriptors:
		if String(gp.get("barracks_workplace_id", "")) == barracks_id:
			var parsed: Dictionary = SettlementBuildingCapabilityAdapterScript.parse_deterministic_job_id(job_id)
			var slot_idx: int = maxi(1, int(parsed.get("slot_index", 1)))
			var targets: Array = gp.get("patrol_targets", [])
			var initial_target_id: String = barracks_id
			var initial_target_cell: Vector2i = gp.get("barracks_access_cell", j.target_cell)
			if not targets.is_empty():
				var t_rec: Dictionary = targets[(slot_idx - 1) % targets.size()]
				initial_target_id = String(t_rec.get("building_id", barracks_id))
				initial_target_cell = t_rec.get("access_cell", initial_target_cell)
			var res: Dictionary = gp.duplicate(true)
			res["ok"] = true
			res["job_id"] = job_id
			res["slot_index"] = slot_idx
			res["initial_target_id"] = initial_target_id
			res["initial_target_cell"] = initial_target_cell
			return res
	return {"ok": false, "reason": "patrol_descriptor_not_found"}

## Returns the deterministic next patrol waypoint (Watchtower or owning Barracks) given `current_target_id`.
## If `current_target_id` is missing/removed, safely falls back to the first valid Watchtower target (or Barracks if none exist).
func get_next_patrol_target(current_target_id: String, barracks_id: String = "") -> Dictionary:
	var gp: Dictionary = {}
	for cand in _guard_patrol_descriptors:
		if barracks_id.is_empty() or String(cand.get("barracks_workplace_id", "")) == barracks_id:
			gp = cand
			break
	if gp.is_empty():
		return {"ok": false, "reason": "no_guard_patrol_descriptor"}
	var b_id: String = String(gp.get("barracks_building_id", ""))
	var b_cell: Vector2i = gp.get("barracks_access_cell", Vector2i.ZERO)
	var targets: Array = gp.get("patrol_targets", [])
	if targets.is_empty():
		return {
			"ok": true,
			"target_id": b_id,
			"building_id": b_id,
			"building_type": "barracks",
			"settlement_id": _settlement_id,
			"access_cell": b_cell,
			"is_barracks_fallback": true
		}
	var clean_cur := current_target_id.strip_edges()
	if clean_cur == b_id:
		var first_t: Dictionary = (targets[0] as Dictionary).duplicate(true)
		first_t["ok"] = true
		first_t["is_barracks_fallback"] = false
		return first_t
	for i in range(targets.size()):
		var t_item: Dictionary = targets[i]
		if String(t_item.get("building_id", "")) == clean_cur:
			var next_idx: int = (i + 1) % targets.size()
			var next_t: Dictionary = (targets[next_idx] as Dictionary).duplicate(true)
			next_t["ok"] = true
			next_t["is_barracks_fallback"] = false
			return next_t
	# Missing or removed Watchtower target: deterministically fall back to the first valid Watchtower
	var fallback_t: Dictionary = (targets[0] as Dictionary).duplicate(true)
	fallback_t["ok"] = true
	fallback_t["recovered_from_missing_target"] = true
	fallback_t["is_barracks_fallback"] = false
	return fallback_t

func get_workplace_effective_buffer_capacity(workplace_id: String) -> int:
	if workplace_registry == null or not workplace_registry.has_workplace(workplace_id):
		return 0
	var wp = workplace_registry.get_workplace(workplace_id)
	if _workplace_effective_buffer_capacities.has(workplace_id):
		return int(_workplace_effective_buffer_capacities[workplace_id])
	return int(wp.buffer_capacity)

func is_workplace_buffer_over_capacity(workplace_id: String) -> bool:
	if workplace_registry == null or not workplace_registry.has_workplace(workplace_id):
		return false
	var wp = workplace_registry.get_workplace(workplace_id)
	return int(wp.buffer_amount) > get_workplace_effective_buffer_capacity(workplace_id)

func get_workplace_buffer_over_capacity_amount(workplace_id: String) -> int:
	if workplace_registry == null or not workplace_registry.has_workplace(workplace_id):
		return 0
	var wp = workplace_registry.get_workplace(workplace_id)
	return maxi(0, int(wp.buffer_amount) - get_workplace_effective_buffer_capacity(workplace_id))

func get_over_capacity_workplaces() -> Dictionary:
	var out: Dictionary = {}
	if workplace_registry == null:
		return out
	for wp in workplace_registry.get_all_workplaces():
		var eff_cap: int = get_workplace_effective_buffer_capacity(wp.workplace_id)
		if int(wp.buffer_amount) > eff_cap:
			out[wp.workplace_id] = {
				"workplace_id": wp.workplace_id,
				"building_id": wp.building_id,
				"output_resource": wp.output_resource,
				"buffer_amount": int(wp.buffer_amount),
				"effective_capacity": eff_cap,
				"ceiling_capacity": int(wp.buffer_capacity),
				"excess_amount": int(wp.buffer_amount) - eff_cap
			}
	return out

## Non-destructively updates the effective buffer capacity of a registered workplace.
## If `new_capacity < wp.buffer_amount`, all existing buffer contents are preserved without clamping,
## `wp.buffer_capacity` is held at the ceiling `wp.buffer_amount` until legitimate withdrawals reduce
## contents, and `_workplace_effective_buffer_capacities[workplace_id]` records `new_capacity` so new
## deposits are blocked while over-capacity.
func set_workplace_buffer_capacity(workplace_id: String, new_capacity: Variant) -> Dictionary:
	if workplace_registry == null or not workplace_registry.has_workplace(workplace_id):
		return {"ok": false, "reason": "workplace_not_found"}
	if not SettlementEconomyScript._is_valid_strict_int(new_capacity) or int(new_capacity) < 0:
		return {"ok": false, "reason": "invalid_buffer_capacity"}
	var eff_cap: int = int(new_capacity)
	var wp = workplace_registry.get_workplace(workplace_id)
	_workplace_effective_buffer_capacities[workplace_id] = eff_cap
	wp.buffer_capacity = maxi(eff_cap, int(wp.buffer_amount))
	return {
		"ok": true,
		"workplace_id": workplace_id,
		"buffer_amount": int(wp.buffer_amount),
		"effective_capacity": eff_cap,
		"is_over_capacity": int(wp.buffer_amount) > eff_cap,
		"excess_amount": maxi(0, int(wp.buffer_amount) - eff_cap)
	}

## Deposits `amount` into a workplace buffer, strictly enforcing the workplace's effective buffer capacity.
## Rejects any deposit when the workplace is at or over its effective capacity.
func deposit_to_workplace_buffer(workplace_id: String, amount: Variant) -> Dictionary:
	if workplace_registry == null or not workplace_registry.has_workplace(workplace_id):
		return {"ok": false, "reason": "workplace_not_found"}
	if not SettlementEconomyScript._is_valid_strict_int(amount) or int(amount) <= 0:
		return {"ok": false, "reason": "invalid_deposit_amount"}
	var qty: int = int(amount)
	var wp = workplace_registry.get_workplace(workplace_id)
	var eff_cap: int = get_workplace_effective_buffer_capacity(workplace_id)
	var cur_amt: int = int(wp.buffer_amount)
	if cur_amt >= eff_cap or (cur_amt + qty) > eff_cap:
		return {
			"ok": false,
			"reason": "exceeds_effective_buffer_capacity",
			"buffer_amount": cur_amt,
			"effective_capacity": eff_cap
		}
	wp.buffer_amount = cur_amt + qty
	wp.buffer_capacity = maxi(eff_cap, int(wp.buffer_amount))
	return {
		"ok": true,
		"workplace_id": workplace_id,
		"deposited": qty,
		"buffer_amount": int(wp.buffer_amount),
		"effective_capacity": eff_cap,
		"is_over_capacity": int(wp.buffer_amount) > eff_cap
	}

## Withdraws `amount` from a workplace buffer. If the workplace had a pending capacity reduction,
## shrinking `buffer_amount` lowers `wp.buffer_capacity` toward `effective_capacity` and clears
## the over-capacity state once `buffer_amount <= effective_capacity`.
func withdraw_from_workplace_buffer(workplace_id: String, amount: Variant) -> Dictionary:
	if workplace_registry == null or not workplace_registry.has_workplace(workplace_id):
		return {"ok": false, "reason": "workplace_not_found"}
	if not SettlementEconomyScript._is_valid_strict_int(amount) or int(amount) <= 0:
		return {"ok": false, "reason": "invalid_withdraw_amount"}
	var qty: int = int(amount)
	var wp = workplace_registry.get_workplace(workplace_id)
	var cur_amt: int = int(wp.buffer_amount)
	if qty > cur_amt:
		return {
			"ok": false,
			"reason": "insufficient_buffer_amount",
			"buffer_amount": cur_amt
		}
	var eff_cap: int = get_workplace_effective_buffer_capacity(workplace_id)
	var new_amt: int = cur_amt - qty
	wp.buffer_amount = new_amt
	wp.buffer_capacity = maxi(eff_cap, new_amt)
	return {
		"ok": true,
		"workplace_id": workplace_id,
		"withdrawn": qty,
		"buffer_amount": new_amt,
		"effective_capacity": eff_cap,
		"is_over_capacity": new_amt > eff_cap,
		"excess_amount": maxi(0, new_amt - eff_cap)
	}

func get_salvaged_workplace_buffers() -> Dictionary:
	return _salvaged_workplace_buffers.duplicate(true)

func set_workplace_quota(workplace_id: String, new_quota: Variant) -> Dictionary:
	if workplace_registry == null or not workplace_registry.has_workplace(workplace_id):
		return {"ok": false, "reason": "workplace_not_found"}
	if not SettlementEconomyScript._is_valid_strict_int(new_quota) or int(new_quota) < 0:
		return {"ok": false, "reason": "invalid_worker_quota"}
	var wp = workplace_registry.get_workplace(workplace_id)
	wp.worker_quota = int(new_quota)
	return assign_villagers_to_jobs()

func set_workplace_active(workplace_id: String, active: bool) -> Dictionary:
	if workplace_registry == null or not workplace_registry.has_workplace(workplace_id):
		return {"ok": false, "reason": "workplace_not_found"}
	var wp = workplace_registry.get_workplace(workplace_id)
	wp.is_active = active
	return assign_villagers_to_jobs()

func verify_assignment_integrity() -> Dictionary:
	return SettlementBuildingCapabilityAdapterScript.verify_context_assignment_integrity(self)

func _set_derived_building_state(
	p_housing_capacity: int,
	p_residential: Array,
	p_descriptors: Array,
	p_final_storage: Array,
	p_receiving_buffers: Array,
	p_routes: Array,
	p_output_buffers: Array = [],
	p_patrol_target_ids: Array = [],
	p_patrol_targets: Array = [],
	p_guard_patrol_descriptors: Array = []
) -> void:
	_housing_capacity = maxi(0, p_housing_capacity)
	_residential_buildings.clear()
	for rb in p_residential:
		if rb is Dictionary:
			_residential_buildings.append((rb as Dictionary).duplicate(true))
	_building_descriptors.clear()
	for bd in p_descriptors:
		if bd is Dictionary:
			_building_descriptors.append((bd as Dictionary).duplicate(true))
	_final_storage_ids.clear()
	for fs in p_final_storage:
		_final_storage_ids.append(String(fs))
	_receiving_buffer_ids.clear()
	for rbuf in p_receiving_buffers:
		_receiving_buffer_ids.append(String(rbuf))
	_output_buffer_ids.clear()
	for obuf in p_output_buffers:
		_output_buffer_ids.append(String(obuf))
	_transport_routes.clear()
	for tr in p_routes:
		if tr is Dictionary:
			_transport_routes.append((tr as Dictionary).duplicate(true))
	_patrol_target_ids.clear()
	for pt_id in p_patrol_target_ids:
		_patrol_target_ids.append(String(pt_id))
	_patrol_targets.clear()
	for pt in p_patrol_targets:
		if pt is Dictionary:
			_patrol_targets.append((pt as Dictionary).duplicate(true))
	_guard_patrol_descriptors.clear()
	for gp in p_guard_patrol_descriptors:
		if gp is Dictionary:
			_guard_patrol_descriptors.append((gp as Dictionary).duplicate(true))

## Derives and reconciles functional building capabilities, housing capacity, storage capacity bonuses,
## workplace registrations, transport routes, job slots, and initial villager assignments from either
## a `SettlementData` instance or a `SettlementData.buildings` Array.
func reconcile_buildings(buildings_or_settlement: Variant, strict_reject_malformed: bool = true) -> Dictionary:
	if not is_valid():
		return {"ok": false, "reason": "invalid_context"}
	var buildings_arr: Variant = buildings_or_settlement
	if buildings_or_settlement is RefCounted and not (buildings_or_settlement is Array):
		var stl_sid = buildings_or_settlement.get("settlement_id")
		if stl_sid is String and not String(stl_sid).is_empty() and String(stl_sid) != _settlement_id:
			return {"ok": false, "reason": "cross_settlement_building_source"}
		buildings_arr = buildings_or_settlement.get("buildings")
	return SettlementBuildingCapabilityAdapterScript.reconcile_context_with_buildings(
		self,
		buildings_arr,
		strict_reject_malformed
	)

## Deterministically assigns/reconciles existing settlement villagers to valid open job slots.
func assign_villagers_to_jobs() -> Dictionary:
	return SettlementBuildingCapabilityAdapterScript.assign_villagers_deterministically(self)

func to_dict() -> Dictionary:
	var v_list: Array[Dictionary] = []
	for v in get_all_villagers():
		v_list.append(v.to_dict())
	return {
		"settlement_id": settlement_id,
		"origin_faction_id": origin_faction_id,
		"owner_faction_id": owner_faction_id,
		"next_villager_seq": _next_villager_seq,
		"housing_capacity": _housing_capacity,
		"residential_buildings": get_residential_buildings(),
		"final_storage_ids": get_final_storage_ids(),
		"receiving_buffer_ids": get_receiving_buffer_ids(),
		"output_buffer_ids": get_output_buffer_ids(),
		"transport_routes": get_transport_routes(),
		"patrol_target_ids": get_patrol_target_ids(),
		"patrol_targets": get_patrol_targets(),
		"guard_patrol_descriptors": get_guard_patrol_descriptors(),
		"workplace_effective_buffer_capacities": _workplace_effective_buffer_capacities.duplicate(true),
		"salvaged_workplace_buffers": _salvaged_workplace_buffers.duplicate(true),
		"villagers": v_list,
		"job_board": job_board.to_dict() if job_board != null else {},
		"workplace_registry": workplace_registry.to_dict() if workplace_registry != null else {},
		"economy": _economy.to_dict() if _economy != null else {},
		"sim_state": sim_state.to_dict() if sim_state != null else {}
	}

func serialize() -> Dictionary:
	return to_dict()

static func from_dict(data: Variant) -> RefCounted:
	if not (data is Dictionary):
		return null
	var d: Dictionary = data
	if not (d.get("settlement_id") is String) or not (d.get("origin_faction_id") is String):
		return null
	if d.has("owner_faction_id") and not (d["owner_faction_id"] is String):
		return null
	var sid := String(d["settlement_id"]).strip_edges()
	var orig_fid := String(d["origin_faction_id"]).strip_edges()
	var own_fid := String(d.get("owner_faction_id", orig_fid)).strip_edges()
	if own_fid.is_empty():
		own_fid = orig_fid
	if d.has("next_villager_seq") and not SettlementVillagerDataScript._is_valid_finite_number(d["next_villager_seq"]):
		return null
	var nseq_raw: int = int(d.get("next_villager_seq", 1))
	if nseq_raw < 1:
		return null
	var hcap_raw: int = 0
	if d.has("housing_capacity"):
		if not SettlementVillagerDataScript._is_valid_finite_number(d["housing_capacity"]) or int(d["housing_capacity"]) < 0:
			return null
		hcap_raw = int(d["housing_capacity"])

	# Create context with an unendowed, non-minting economy by default; if "economy" is present
	# in `d`, it will be restored below. If "economy" is absent (Phase 1 backward compatibility),
	# the context retains this safe zero-balance economy without fabricating resources.
	var ctx := new(sid, orig_fid, own_fid, nseq_raw, false)
	if not ctx.is_valid():
		return null
	ctx._housing_capacity = hcap_raw

	if d.has("villagers") and not (d["villagers"] is Array):
		return null
	var raw_villagers: Array = d.get("villagers", [])
	for v_item in raw_villagers:
		var v := SettlementVillagerDataScript.from_dict(v_item)
		if v == null or not ctx._add_villager_internal(v, true):
			return null

	if d.has("job_board"):
		if not (d["job_board"] is Dictionary):
			return null
		if not d["job_board"].is_empty():
			var jb := SettlementJobBoardScript.from_dict(d["job_board"])
			if jb == null or jb.settlement_id != sid:
				return null
			ctx.job_board = jb

	if d.has("workplace_registry"):
		if not (d["workplace_registry"] is Dictionary):
			return null
		if not d["workplace_registry"].is_empty():
			var wr := SettlementWorkplaceRegistryScript.from_dict(d["workplace_registry"])
			if wr == null or wr.settlement_id != sid:
				return null
			ctx.workplace_registry = wr

	if d.has("economy"):
		if not (d["economy"] is Dictionary):
			return null
		if not d["economy"].is_empty():
			var econ := SettlementEconomyScript.from_dict(d["economy"])
			if econ == null or not ctx.set_economy(econ):
				return null

	if d.has("residential_buildings"):
		if not (d["residential_buildings"] is Array):
			return null
		for rb in d["residential_buildings"]:
			if not (rb is Dictionary):
				return null
			ctx._residential_buildings.append((rb as Dictionary).duplicate(true))

	for arr_key in ["final_storage_ids", "receiving_buffer_ids", "output_buffer_ids", "patrol_target_ids"]:
		if d.has(arr_key):
			if not (d[arr_key] is Array):
				return null
			for s_item in d[arr_key]:
				if not (s_item is String):
					return null
				var s_clean := String(s_item).strip_edges()
				if arr_key == "final_storage_ids":
					ctx._final_storage_ids.append(s_clean)
				elif arr_key == "receiving_buffer_ids":
					ctx._receiving_buffer_ids.append(s_clean)
				elif arr_key == "output_buffer_ids":
					ctx._output_buffer_ids.append(s_clean)
				else:
					ctx._patrol_target_ids.append(s_clean)

	if d.has("patrol_targets"):
		if not (d["patrol_targets"] is Array):
			return null
		for pt in d["patrol_targets"]:
			if not (pt is Dictionary):
				return null
			var pt_copy: Dictionary = (pt as Dictionary).duplicate(true)
			if pt_copy.has("origin_cell"):
				pt_copy["origin_cell"] = SettlementVillagerDataScript._parse_vec2i(pt_copy["origin_cell"], Vector2i.ZERO)
			if pt_copy.has("size"):
				pt_copy["size"] = SettlementVillagerDataScript._parse_vec2i(pt_copy["size"], Vector2i.ONE)
			if pt_copy.has("access_cell"):
				pt_copy["access_cell"] = SettlementVillagerDataScript._parse_vec2i(pt_copy["access_cell"], Vector2i.ZERO)
			ctx._patrol_targets.append(pt_copy)

	if d.has("guard_patrol_descriptors"):
		if not (d["guard_patrol_descriptors"] is Array):
			return null
		for gp in d["guard_patrol_descriptors"]:
			if not (gp is Dictionary):
				return null
			var gp_copy: Dictionary = (gp as Dictionary).duplicate(true)
			if gp_copy.has("barracks_access_cell"):
				gp_copy["barracks_access_cell"] = SettlementVillagerDataScript._parse_vec2i(gp_copy["barracks_access_cell"], Vector2i.ZERO)
			if gp_copy.has("patrol_targets") and gp_copy["patrol_targets"] is Array:
				var norm_pts: Array[Dictionary] = []
				for pt in gp_copy["patrol_targets"]:
					if pt is Dictionary:
						var pt_c: Dictionary = (pt as Dictionary).duplicate(true)
						if pt_c.has("origin_cell"):
							pt_c["origin_cell"] = SettlementVillagerDataScript._parse_vec2i(pt_c["origin_cell"], Vector2i.ZERO)
						if pt_c.has("size"):
							pt_c["size"] = SettlementVillagerDataScript._parse_vec2i(pt_c["size"], Vector2i.ONE)
						if pt_c.has("access_cell"):
							pt_c["access_cell"] = SettlementVillagerDataScript._parse_vec2i(pt_c["access_cell"], Vector2i.ZERO)
						norm_pts.append(pt_c)
				gp_copy["patrol_targets"] = norm_pts
			ctx._guard_patrol_descriptors.append(gp_copy)

	if d.has("transport_routes"):
		if not (d["transport_routes"] is Array):
			return null
		for tr in d["transport_routes"]:
			if not (tr is Dictionary):
				return null
			var tr_copy: Dictionary = (tr as Dictionary).duplicate(true)
			if tr_copy.has("source_cell"):
				tr_copy["source_cell"] = SettlementVillagerDataScript._parse_vec2i(tr_copy["source_cell"], Vector2i(-1, -1))
			if tr_copy.has("dest_cell"):
				tr_copy["dest_cell"] = SettlementVillagerDataScript._parse_vec2i(tr_copy["dest_cell"], Vector2i(-1, -1))
			ctx._transport_routes.append(tr_copy)

	if d.has("workplace_effective_buffer_capacities"):
		if not (d["workplace_effective_buffer_capacities"] is Dictionary):
			return null
		var raw_eff: Dictionary = d["workplace_effective_buffer_capacities"]
		for k in raw_eff.keys():
			if not (k is String) or not SettlementEconomyScript._is_valid_strict_int(raw_eff[k]) or int(raw_eff[k]) < 0:
				return null
			ctx._workplace_effective_buffer_capacities[String(k)] = int(raw_eff[k])

	if d.has("salvaged_workplace_buffers"):
		if not (d["salvaged_workplace_buffers"] is Dictionary):
			return null
		var raw_salv: Dictionary = d["salvaged_workplace_buffers"]
		for k in raw_salv.keys():
			if not (k is String) or not (raw_salv[k] is Dictionary):
				return null
			ctx._salvaged_workplace_buffers[String(k)] = (raw_salv[k] as Dictionary).duplicate(true)

	if d.has("sim_state") and not (d["sim_state"] as Dictionary if d["sim_state"] is Dictionary else {}).is_empty():
		var restored_sim = SettlementSimulationStateScript.from_dict(d["sim_state"])
		if restored_sim == null:
			return null
		ctx.sim_state = restored_sim
	elif d.has("sim_state") and not (d["sim_state"] is Dictionary):
		return null

	return ctx

static func deserialize(data: Variant) -> RefCounted:
	return from_dict(data)
