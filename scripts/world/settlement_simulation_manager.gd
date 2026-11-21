class_name SettlementSimulationManager
extends Node
## Central data-first Phase 4 simulation manager for Rival Settlements (Architecture v1.0).
## Owned by the runtime world (WorldView); strictly isolated from CitizenController,
## player JobManager/WorkplaceManager, /root/ResourceManager, and FactionData.population.

signal simulation_warning(settlement_id: String, reason: String)
signal settlement_isolated(settlement_id: String, reason: String)
signal survival_state_changed(settlement_id: String, new_state: String, old_state: String)
signal awaiting_resupply_changed(settlement_id: String, is_awaiting: bool)
signal backpressure_changed(active: bool, requested_speed: int, effective_speed: int)
signal batch_completed(summary: Dictionary)

const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementVillagerContextScript = preload("res://scripts/world/settlement_villager_context.gd")
const SettlementJobBoardScript = preload("res://scripts/world/settlement_job_board.gd")
const SettlementWorkplaceRegistryScript = preload("res://scripts/world/settlement_workplace_registry.gd")
const SettlementEconomyScript = preload("res://scripts/world/settlement_economy.gd")
const SettlementBuildingCapabilityAdapterScript = preload("res://scripts/world/settlement_building_capability_adapter.gd")
const SettlementSimulationConfigScript = preload("res://scripts/world/settlement_simulation_config.gd")
const SettlementSimulationStateScript = preload("res://scripts/world/settlement_simulation_state.gd")
const SettlementResourceSourceAdapterScript = preload("res://scripts/world/settlement_resource_source_adapter.gd")
const SettlementImmigrationPolicyScript = preload("res://scripts/world/settlement_immigration_policy.gd")
const SettlementImmigrationServiceScript = preload("res://scripts/world/settlement_immigration_service.gd")
const SettlementPopulationSeederScript = preload("res://scripts/world/settlement_population_seeder.gd")
const SettlementAmbientLocomotionScript = preload("res://scripts/world/settlement_ambient_locomotion.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")

var _contexts_by_id: Dictionary = {} # settlement_id -> SettlementVillagerContext
var _isolated_settlements: Dictionary = {} # settlement_id -> Dictionary
var _consecutive_failures: Dictionary = {} # settlement_id -> int
var diagnostic_trace_enabled: bool = false
var _diagnostic_events: Array[Dictionary] = []
const MAX_DIAGNOSTIC_EVENTS: int = 512
var _fault_injection_hooks: Dictionary = {} # settlement_id -> Callable (for deterministic tests)
var _stage_fault_hooks: Dictionary = {} # settlement_id -> Callable (sid, vid, h_seq, stage) -> bool

var _world_data: RefCounted = null
var _world_view: Node = null
var _world_seed: int = 12345
var _immigration_service: RefCounted = null
var _population_seeder: RefCounted = null
var _ambient_locomotion: RefCounted = null
var immigration_enabled: bool = true
var _globally_allocated_tree_cells: Dictionary = {} # Vector2i -> workplace_id (String)
var _last_wildlife_recovery_hour_seq: int = -1

var _time_manager: Node = null
var _required_hour_seq: int = 0
var _pending_queue: Array[Dictionary] = [] # [{settlement_id, villager_id, hour_seq}]
var _rr_cursor: int = 0

# Backpressure & Telemetry
var backpressure_enabled: bool = true:
	set(value):
		backpressure_enabled = value
		_evaluate_backpressure()
var _requested_speed: int = 1
var _effective_speed: int = 1
var _backpressure_active: bool = false
var _suppress_speed_signal_sync: bool = false

var max_villagers_per_batch: int = SettlementSimulationConfigScript.MAX_VILLAGERS_PER_BATCH
var soft_budget_ms_per_frame: float = SettlementSimulationConfigScript.SOFT_BUDGET_MS_PER_FRAME
var _last_batch_duration_ms: float = 0.0
var _max_batch_duration_ms: float = 0.0

# M0 Opt-In Benchmark Telemetry (disabled by default; zero gameplay impact)
const BENCH_SAMPLE_CAP: int = 256
var benchmark_telemetry_enabled: bool = false:
	set(value):
		benchmark_telemetry_enabled = value
		if _ambient_locomotion != null:
			_ambient_locomotion.benchmark_telemetry_enabled = value
var _bench_sim_samples_ms: PackedFloat64Array = PackedFloat64Array()
var _bench_sim_sample_cursor: int = 0
var _bench_sim_ticks: int = 0
var _bench_sim_total_ms: float = 0.0
var _bench_villagers_processed: int = 0
var _bench_settlements_processed: int = 0
var _bench_rebuild_queue_ms: float = 0.0
var _bench_update_settled_ms: float = 0.0
var _bench_eval_bp_ms: float = 0.0
var _bench_maintenance_villagers: int = 0

func _ready() -> void:
	set_process(false)

func _exit_tree() -> void:
	disconnect_time_manager()

# -----------------------------------------------------------------------------
# TimeManager Connection & Speed Backpressure
# -----------------------------------------------------------------------------
func connect_time_manager(tm: Node) -> bool:
	if tm == null:
		return false
	if _time_manager == tm:
		return true
	disconnect_time_manager()
	_time_manager = tm
	if tm.has_signal("hour_passed") and not tm.hour_passed.is_connected(_on_tm_hour_passed):
		tm.hour_passed.connect(_on_tm_hour_passed)
	if tm.has_signal("day_passed") and not tm.day_passed.is_connected(_on_tm_day_passed):
		tm.day_passed.connect(_on_tm_day_passed)
	if tm.has_signal("time_speed_changed") and not tm.time_speed_changed.is_connected(_on_tm_speed_changed):
		tm.time_speed_changed.connect(_on_tm_speed_changed)
	if tm.has_method("get_hour_seq"):
		_required_hour_seq = maxi(_required_hour_seq, int(tm.get_hour_seq()))
	var cur_spd: Variant = tm.get("current_speed")
	if cur_spd is int:
		_requested_speed = int(cur_spd)
		_effective_speed = int(cur_spd)
	return true

func disconnect_time_manager() -> void:
	if _time_manager == null or not is_instance_valid(_time_manager):
		_time_manager = null
		return
	if _time_manager.has_signal("hour_passed") and _time_manager.hour_passed.is_connected(_on_tm_hour_passed):
		_time_manager.hour_passed.disconnect(_on_tm_hour_passed)
	if _time_manager.has_signal("day_passed") and _time_manager.day_passed.is_connected(_on_tm_day_passed):
		_time_manager.day_passed.disconnect(_on_tm_day_passed)
	if _time_manager.has_signal("time_speed_changed") and _time_manager.time_speed_changed.is_connected(_on_tm_speed_changed):
		_time_manager.time_speed_changed.disconnect(_on_tm_speed_changed)
	_time_manager = null

func is_connected_to_time_manager() -> bool:
	return _time_manager != null and is_instance_valid(_time_manager)

func set_requested_speed(speed: int) -> void:
	_requested_speed = clampi(speed, 0, 3)
	_evaluate_backpressure()
	if not _backpressure_active and _time_manager != null and _time_manager.has_method("set_speed"):
		_suppress_speed_signal_sync = true
		_time_manager.set_speed(_requested_speed)
		_suppress_speed_signal_sync = false

func _on_tm_speed_changed(new_speed: int) -> void:
	if _suppress_speed_signal_sync:
		return
	_requested_speed = clampi(new_speed, 0, 3)
	if not _backpressure_active:
		_effective_speed = _requested_speed
	_evaluate_backpressure()

# -----------------------------------------------------------------------------
# Settlement Context Registration & Fault Isolation
# -----------------------------------------------------------------------------
func register_context(ctx: RefCounted) -> bool:
	if ctx == null or not ctx.has_method("is_valid") or not ctx.is_valid():
		return false
	var sid: String = String(ctx.settlement_id)
	if _contexts_by_id.has(sid):
		return false
	if ctx.sim_state == null:
		ctx.sim_state = SettlementSimulationStateScript.new()
	ctx.sim_state.initialized = true
	if int(ctx.sim_state.required_hour_seq) < _required_hour_seq:
		ctx.sim_state.required_hour_seq = _required_hour_seq
	else:
		_required_hour_seq = maxi(_required_hour_seq, int(ctx.sim_state.required_hour_seq))
	_contexts_by_id[sid] = ctx
	_rebuild_pending_queue()
	_evaluate_backpressure()
	return true

func unregister_context(settlement_id: String) -> bool:
	if not _contexts_by_id.has(settlement_id):
		return false
	_contexts_by_id.erase(settlement_id)
	_isolated_settlements.erase(settlement_id)
	_consecutive_failures.erase(settlement_id)
	_rebuild_pending_queue()
	_evaluate_backpressure()
	return true

func has_context(settlement_id: String) -> bool:
	return _contexts_by_id.has(settlement_id)

func get_context(settlement_id: String) -> RefCounted:
	return _contexts_by_id.get(settlement_id, null)

func get_registered_settlement_ids() -> Array[String]:
	var ids: Array[String] = []
	for k in _contexts_by_id.keys():
		ids.append(String(k))
	ids.sort()
	return ids

## Registers canonical rival settlements from WorldData without fabricating any villagers.
func register_settlements_from_world_data(world_data: RefCounted) -> int:
	set_world_data(world_data)
	if world_data == null or world_data.get("settlements") == null:
		return 0
	var added: int = 0
	var contexts_list: Array = []
	for stl in world_data.settlements:
		if stl == null:
			continue
		var sid: String = String(stl.get("settlement_id"))
		var orig_fid: String = String(stl.get("origin_faction_id"))
		var own_fid: String = String(stl.get("owner_faction_id"))
		if sid.is_empty():
			continue
		var ctx: RefCounted = null
		if _contexts_by_id.has(sid):
			ctx = _contexts_by_id[sid]
		else:
			ctx = SettlementVillagerContextScript.new(sid, orig_fid, own_fid)
			if not ctx.is_valid():
				continue
			ctx.reconcile_buildings(stl)
			if register_context(ctx):
				added += 1
		if ctx != null:
			contexts_list.append(ctx)

	# Global order-independent tree allocation across all registered contexts
	_globally_allocated_tree_cells = SettlementResourceSourceAdapterScript.allocate_global_woodcutter_sources(
		contexts_list,
		_world_data
	)
	# Automatic registration of all eligible Farm workplaces across registered contexts (F1)
	SettlementResourceSourceAdapterScript.register_all_farm_sources(contexts_list)
	# Automatic registration of all eligible Hunter workplaces across registered contexts (H1)
	SettlementResourceSourceAdapterScript.register_all_hunter_sources(contexts_list, _world_data)
	# M1: Configure validated road graphs for canonical ambient wandering
	get_ambient_locomotion().configure_from_world_data(_world_data)
	return added

func get_ambient_locomotion() -> RefCounted:
	if _ambient_locomotion == null:
		_ambient_locomotion = SettlementAmbientLocomotionScript.new()
		_ambient_locomotion.world_seed = _world_seed
		_ambient_locomotion.benchmark_telemetry_enabled = benchmark_telemetry_enabled
	return _ambient_locomotion

func step_ambient_locomotion(sim_dt: float) -> void:
	if sim_dt <= 0.0:
		return
	get_ambient_locomotion().step_simulation_time(sim_dt, self)

func set_world_data(world_data: RefCounted) -> void:
	_world_data = world_data
	if _world_data != null:
		var s_val: Variant = _world_data.get("seed_value")
		if s_val is int:
			_world_seed = int(s_val)

func set_world_seed(seed_val: int) -> void:
	_world_seed = seed_val

func get_world_seed() -> int:
	return _world_seed

func get_immigration_service() -> RefCounted:
	if _immigration_service == null:
		_immigration_service = SettlementImmigrationServiceScript.new()
	return _immigration_service

func get_population_seeder() -> RefCounted:
	if _population_seeder == null:
		_population_seeder = SettlementPopulationSeederScript.new()
	return _population_seeder

## Seeds initial founding residents for all eligible unseeded active settlements.
## Intended for fresh-world initialization only (idempotent; skips already-seeded or populated contexts).
func seed_initial_populations() -> Dictionary:
	var seeder := get_population_seeder()
	var total_seeded: int = 0
	var per_settlement: Dictionary = {}
	var hunter_contexts: Array = []
	for sid in get_registered_settlement_ids():
		var ctx = _contexts_by_id.get(sid, null)
		if ctx == null:
			continue
		var stl_data := _find_settlement_data(sid)
		if String(ctx.origin_faction_id) == "neutral_tribe" and stl_data != null:
			var had_hunter: bool = ctx.has_meta("enable_hunter") and bool(ctx.get_meta("enable_hunter"))
			if not had_hunter:
				ctx.set_meta("enable_hunter", true)
				ctx.reconcile_buildings(stl_data)
				hunter_contexts.append(ctx)
	if not hunter_contexts.is_empty():
		SettlementResourceSourceAdapterScript.register_all_hunter_sources(hunter_contexts, _world_data)
	for sid in get_registered_settlement_ids():
		var ctx = _contexts_by_id.get(sid, null)
		if ctx == null:
			continue
		var stl_data := _find_settlement_data(sid)
		var res: Dictionary = seeder.seed_settlement(ctx, _world_seed, stl_data, _world_data)
		per_settlement[sid] = res
		total_seeded += int(res.get("seeded", 0))
	if total_seeded > 0:
		_rebuild_pending_queue()
		_evaluate_backpressure()
	return {"ok": true, "total_seeded": total_seeded, "per_settlement": per_settlement}

func set_immigration_policy(p_policy: RefCounted) -> void:
	var svc := get_immigration_service()
	if p_policy != null:
		svc.policy = p_policy

func set_immigration_enabled(enabled: bool) -> void:
	immigration_enabled = enabled

func is_immigration_enabled() -> bool:
	return immigration_enabled

func _find_settlement_data(sid: String) -> RefCounted:
	if _world_data == null or _world_data.get("settlements") == null:
		return null
	for stl in _world_data.settlements:
		if stl != null and String(stl.get("settlement_id")) == sid:
			return stl
	return null

func get_world_data() -> RefCounted:
	return _world_data

func set_world_view(world_view: Node) -> void:
	_world_view = world_view

func _get_world_view() -> Node:
	if _world_view != null and is_instance_valid(_world_view):
		return _world_view
	var p = get_parent()
	if p != null and is_instance_valid(p) and p.has_method("remove_prop_visual_at_cell"):
		return p
	return null

func is_settlement_isolated(settlement_id: String) -> bool:
	return _isolated_settlements.has(settlement_id)

func clear_settlement_isolation(settlement_id: String) -> void:
	_isolated_settlements.erase(settlement_id)
	_consecutive_failures[settlement_id] = 0
	_rebuild_pending_queue()

func set_fault_hook_for_test(settlement_id: String, hook: Callable) -> void:
	if hook.is_valid():
		_fault_injection_hooks[settlement_id] = hook
	else:
		_fault_injection_hooks.erase(settlement_id)

func set_stage_fault_hook_for_test(settlement_id: String, hook: Callable) -> void:
	if hook.is_valid():
		_stage_fault_hooks[settlement_id] = hook
	else:
		_stage_fault_hooks.erase(settlement_id)

func _check_stage_ok(sid: String, vid: String, h_seq: int, stage: String) -> bool:
	if not _stage_fault_hooks.has(sid):
		return true
	var hook: Callable = _stage_fault_hooks[sid]
	if not bool(hook.call(sid, vid, h_seq, stage)):
		_record_settlement_failure(sid, "injected_stage_fault:%s:h%d" % [stage, h_seq])
		return false
	return true

func _record_settlement_failure(settlement_id: String, reason: String) -> void:
	var ctx = _contexts_by_id.get(settlement_id, null)
	if ctx != null and ctx.sim_state != null:
		ctx.sim_state.record_error(reason)
	var fails: int = int(_consecutive_failures.get(settlement_id, 0)) + 1
	_consecutive_failures[settlement_id] = fails
	simulation_warning.emit(settlement_id, reason)
	if fails >= SettlementSimulationConfigScript.FAULT_ISOLATION_CONSECUTIVE_FAILURES:
		_isolated_settlements[settlement_id] = {"reason": reason, "failures": fails}
		settlement_isolated.emit(settlement_id, reason)

## Registers a verified finite production source for a Farm or Woodcutter workplace.
func register_production_source(settlement_id: String, workplace_id: String, resource_id: String, remaining_amount: int, max_capacity: int = -1) -> bool:
	var ctx = _contexts_by_id.get(settlement_id, null)
	if ctx == null or ctx.sim_state == null or remaining_amount < 0:
		return false
	if ctx.workplace_registry == null or not ctx.workplace_registry.has_workplace(workplace_id):
		return false
	var cap: int = max_capacity if max_capacity >= remaining_amount else remaining_amount
	var wp = ctx.workplace_registry.get_workplace(workplace_id)
	if wp != null and wp.building_type == "woodcutter":
		# Woodcutter sources MUST be backed by physical trees in WorldData.
		# Synthetic tree generation is strictly disallowed.
		if _world_data == null:
			return false
		var res := register_woodcutter_source(settlement_id, workplace_id)
		return bool(res.get("ok", false))
	if wp != null and wp.building_type == "farm":
		var res_farm := register_farm_source(settlement_id, workplace_id, remaining_amount, cap)
		return bool(res_farm.get("ok", false))

	ctx.sim_state.production_sources[workplace_id] = {
		"resource": resource_id,
		"remaining": remaining_amount,
		"max_capacity": cap
	}
	ctx.sim_state.production_blocked.erase(workplace_id)
	return true

## Registers a verified rate-based production source for a Farm workplace (F1).
func register_farm_source(settlement_id: String, workplace_id: String, remaining_amount: int = -1, max_capacity: int = -1) -> Dictionary:
	var ctx = _contexts_by_id.get(settlement_id, null)
	if ctx == null:
		return {"ok": false, "reason": "unknown_settlement"}
	return SettlementResourceSourceAdapterScript.register_farm_source(
		ctx,
		workplace_id,
		remaining_amount,
		max_capacity
	)

## Registers a grounded tree-backed Woodcutter production source with atomic felling & labor banking (W1).
func register_woodcutter_source(settlement_id: String, workplace_id: String, assigned_cells: Array = []) -> Dictionary:
	var ctx = _contexts_by_id.get(settlement_id, null)
	if ctx == null:
		return {"ok": false, "reason": "unknown_settlement"}
	return SettlementResourceSourceAdapterScript.register_woodcutter_source(
		ctx,
		workplace_id,
		_world_data,
		assigned_cells,
		_globally_allocated_tree_cells
	)

# -----------------------------------------------------------------------------
# Hourly & Daily Event Capture + Queue Reconstruction
# -----------------------------------------------------------------------------
func _on_tm_hour_passed(_current_hour: int, _current_day: int) -> void:
	var next_seq: int = _required_hour_seq + 1
	if _time_manager != null and _time_manager.has_method("get_hour_seq"):
		next_seq = maxi(next_seq, int(_time_manager.get_hour_seq()))
	advance_to_hour_seq(next_seq)

func _on_tm_day_passed(_current_day: int, _season: String, _year: int) -> void:
	var captured_seq: int = _required_hour_seq
	if _time_manager != null and _time_manager.has_method("get_hour_seq"):
		captured_seq = int(_time_manager.get_hour_seq())
	capture_daily_event(captured_seq)
	if not _season.is_empty():
		for sid in get_registered_settlement_ids():
			var ctx = _contexts_by_id.get(sid, null)
			if ctx != null and ctx.workplace_registry != null:
				for wp in ctx.workplace_registry.get_all_workplaces():
					if wp != null and wp.building_type == "farm":
						SettlementResourceSourceAdapterScript.reconcile_farm_seasonal_transition(ctx, wp.workplace_id, _season, _year)

## Sets the target hourly sequence and reconstructs unfinished queue work once.
func advance_to_hour_seq(target_hour_seq: int) -> void:
	if target_hour_seq <= _required_hour_seq:
		return
	_required_hour_seq = target_hour_seq
	for sid in get_registered_settlement_ids():
		if _isolated_settlements.has(sid):
			continue
		var ctx = _contexts_by_id[sid]
		if ctx.sim_state == null:
			ctx.sim_state = SettlementSimulationStateScript.new()
		ctx.sim_state.required_hour_seq = maxi(int(ctx.sim_state.required_hour_seq), target_hour_seq)
	_rebuild_pending_queue()
	_evaluate_backpressure()
	if not _pending_queue.is_empty():
		set_process(true)

## Captures a daily event at its exact monotonic `hour_seq` (never `(day - 1) * 24`).
func capture_daily_event(hour_seq: int) -> void:
	if hour_seq < 0:
		return
	for sid in get_registered_settlement_ids():
		if _isolated_settlements.has(sid):
			continue
		var ctx = _contexts_by_id[sid]
		var st = ctx.sim_state
		if st == null:
			continue
		if hour_seq <= int(st.latest_captured_daily_seq) or st.pending_daily.has(hour_seq):
			continue
		st.latest_captured_daily_seq = hour_seq
		st.pending_daily.append(hour_seq)
		st.pending_daily.sort()
	set_process(true)

func _rebuild_pending_queue() -> void:
	var rq_start: int = Time.get_ticks_usec() if benchmark_telemetry_enabled else 0
	_pending_queue.clear()
	var sids: Array[String] = get_registered_settlement_ids()
	if sids.is_empty():
		return
	# Build per-settlement sorted lists of pending (villager_id, hour_seq) items, then interleave
	# round-robin across settlements so no large settlement starves smaller ones.
	var per_stl: Dictionary = {}
	var max_len: int = 0
	for sid in sids:
		if _isolated_settlements.has(sid):
			continue
		var ctx = _contexts_by_id[sid]
		var st = ctx.sim_state
		if st == null:
			continue
		var target_h: int = int(st.required_hour_seq)
		var list: Array[Dictionary] = []
		var villagers: Array = ctx.get_all_villagers_cached_view()
		if villagers.is_empty():
			# Zero-villager settlement still advances its settled_hour_seq for economy providers
			for h in range(int(st.settled_hour_seq) + 1, target_h + 1):
				list.append({"settlement_id": sid, "villager_id": "", "hour_seq": h})
		else:
			var min_h: int = target_h
			for v in villagers:
				min_h = mini(min_h, int(v.last_processed_hour_seq))
			for h in range(min_h + 1, target_h + 1):
				for v in villagers:
					if int(v.last_processed_hour_seq) < h:
						list.append({"settlement_id": sid, "villager_id": v.villager_id, "hour_seq": h})
		per_stl[sid] = list
		max_len = maxi(max_len, list.size())

	if max_len == 0:
		return
	var start_idx: int = _rr_cursor % sids.size()
	for i in range(max_len):
		for offset in range(sids.size()):
			var sid: String = sids[(start_idx + offset) % sids.size()]
			var slist: Array = per_stl.get(sid, [])
			if i < slist.size():
				_pending_queue.append(slist[i])
	_rr_cursor = (start_idx + 1) % maxi(1, sids.size())
	if benchmark_telemetry_enabled:
		_bench_rebuild_queue_ms += float(Time.get_ticks_usec() - rq_start) / 1000.0

func _process(_delta: float) -> void:
	if _pending_queue.is_empty() and not _has_any_pending_daily():
		set_process(false)
		return
	process_batch(max_villagers_per_batch, soft_budget_ms_per_frame)

func _has_any_pending_daily() -> bool:
	for sid in get_registered_settlement_ids():
		if _isolated_settlements.has(sid):
			continue
		var ctx = _contexts_by_id[sid]
		if ctx.sim_state != null and not ctx.sim_state.pending_daily.is_empty():
			return true
	return false

# -----------------------------------------------------------------------------
# Batch Processing & Backpressure
# -----------------------------------------------------------------------------
func process_all_pending(max_iterations: int = 10000) -> Dictionary:
	var total_processed: int = 0
	var iters: int = 0
	while (not _pending_queue.is_empty() or _has_any_pending_daily()) and iters < max_iterations:
		iters += 1
		var res := process_batch(max_villagers_per_batch, 1000.0)
		total_processed += int(res.get("processed_items", 0))
		if int(res.get("processed_items", 0)) == 0 and int(res.get("daily_completed", 0)) == 0 and not bool(res.get("had_failures", false)):
			break
	return {"ok": true, "processed_items": total_processed, "remaining_pending": _pending_queue.size()}

func process_batch(batch_limit: int = -1, budget_ms: float = -1.0) -> Dictionary:
	var limit: int = batch_limit if batch_limit > 0 else max_villagers_per_batch
	var soft_ms: float = budget_ms if budget_ms > 0.0 else soft_budget_ms_per_frame
	var start_usec: int = Time.get_ticks_usec()
	var processed: int = 0
	var daily_done: int = 0
	var failed_sids: Dictionary = {}

	var idx: int = 0
	while processed < limit and idx < _pending_queue.size():
		if processed > 0:
			var elapsed_ms: float = float(Time.get_ticks_usec() - start_usec) / 1000.0
			if elapsed_ms >= soft_ms:
				break
		var item: Dictionary = _pending_queue[idx]
		var sid: String = String(item["settlement_id"])
		var vid: String = String(item["villager_id"])
		var h_seq: int = int(item["hour_seq"])
		if _isolated_settlements.has(sid):
			_pending_queue.remove_at(idx)
			continue
		if failed_sids.has(sid):
			idx += 1
			continue
		var ok: bool = _execute_single_hour_item(sid, vid, h_seq)
		if ok:
			_pending_queue.remove_at(idx)
			_consecutive_failures[sid] = 0
			processed += 1
		else:
			failed_sids[sid] = true
			idx += 1

	# Update settled_hour_seq for settlements that finished an hour & run eligible daily events
	var maint_start: int = Time.get_ticks_usec() if benchmark_telemetry_enabled else 0
	for sid in get_registered_settlement_ids():
		if _isolated_settlements.has(sid):
			continue
		var ctx = _contexts_by_id[sid]
		_update_settled_hour(ctx)
		daily_done += _process_eligible_daily_events(ctx)
	if benchmark_telemetry_enabled:
		_bench_update_settled_ms += float(Time.get_ticks_usec() - maint_start) / 1000.0

	var total_ms: float = float(Time.get_ticks_usec() - start_usec) / 1000.0
	_last_batch_duration_ms = total_ms
	_max_batch_duration_ms = maxf(_max_batch_duration_ms, total_ms)
	if benchmark_telemetry_enabled:
		_bench_sim_ticks += 1
		_bench_sim_total_ms += total_ms
		_bench_villagers_processed += processed
		_bench_settlements_processed += maxi(0, _contexts_by_id.size() - _isolated_settlements.size())
		if _bench_sim_samples_ms.size() < BENCH_SAMPLE_CAP:
			_bench_sim_samples_ms.append(total_ms)
		else:
			_bench_sim_samples_ms[_bench_sim_sample_cursor] = total_ms
			_bench_sim_sample_cursor = (_bench_sim_sample_cursor + 1) % BENCH_SAMPLE_CAP
	var bp_start: int = Time.get_ticks_usec() if benchmark_telemetry_enabled else 0
	_evaluate_backpressure()
	if benchmark_telemetry_enabled:
		_bench_eval_bp_ms += float(Time.get_ticks_usec() - bp_start) / 1000.0
	if _pending_queue.is_empty() and not _has_any_pending_daily():
		set_process(false)
	var summary := {
		"processed_items": processed,
		"daily_completed": daily_done,
		"had_failures": not failed_sids.is_empty(),
		"remaining_pending": _pending_queue.size(),
		"duration_ms": total_ms
	}
	batch_completed.emit(summary)
	return summary

func _evaluate_backpressure() -> void:
	var pending: int = _pending_queue.size()
	var new_eff: int = _requested_speed
	var new_bp: bool = _backpressure_active
	if not backpressure_enabled or _requested_speed <= 1:
		new_bp = false
		new_eff = _requested_speed
	else:
		if pending >= SettlementSimulationConfigScript.BACKPRESSURE_STEP_DOWN_1X_PENDING:
			new_eff = 1
			new_bp = true
		elif pending >= SettlementSimulationConfigScript.BACKPRESSURE_STEP_DOWN_2X_PENDING:
			new_eff = mini(_requested_speed, 2)
			new_bp = (new_eff < _requested_speed)
		elif _backpressure_active and pending <= SettlementSimulationConfigScript.BACKPRESSURE_RESTORE_PENDING:
			new_eff = _requested_speed
			new_bp = false
		elif _backpressure_active:
			new_eff = mini(_effective_speed, _requested_speed)
	if new_bp != _backpressure_active or new_eff != _effective_speed:
		_backpressure_active = new_bp
		_effective_speed = new_eff
		if _time_manager != null and _time_manager.has_method("set_speed"):
			_suppress_speed_signal_sync = true
			_time_manager.set_speed(_effective_speed)
			_suppress_speed_signal_sync = false
		backpressure_changed.emit(_backpressure_active, _requested_speed, _effective_speed)

# -----------------------------------------------------------------------------
# Per-Hour Execution & Economic Provider Scheduling
# -----------------------------------------------------------------------------
func _execute_single_hour_item(sid: String, vid: String, h_seq: int) -> bool:
	var ctx = _contexts_by_id.get(sid, null)
	if ctx == null or not ctx.is_valid():
		_record_settlement_failure(sid, "invalid_context")
		return false
	if _fault_injection_hooks.has(sid):
		var hook: Callable = _fault_injection_hooks[sid]
		if not bool(hook.call(sid, vid, h_seq)):
			_record_settlement_failure(sid, "injected_fault_at_hour_%d" % h_seq)
			return false

	# Ensure settlement-level providers & survival state advance once for h_seq before villager work
	if int(ctx.sim_state.settled_hour_seq) < h_seq:
		_advance_settlement_providers_for_hour(ctx, h_seq)

	if vid.is_empty():
		ctx.sim_state.settled_hour_seq = maxi(int(ctx.sim_state.settled_hour_seq), h_seq)
		return true

	var v = ctx.get_villager(vid)
	if v == null:
		return true # Missing villager: safely ignore without blocking queue
	if int(v.last_processed_hour_seq) >= h_seq:
		return true # Already processed (exactly-once guard)

	if v.life_state == SettlementVillagerDataScript.LIFE_ALIVE:
		if not _simulate_villager_hour(ctx, v, h_seq):
			return false

	# Advance watermark ONLY after all villager & economic mutations succeeded
	v.last_processed_hour_seq = h_seq
	ctx.sim_state.stats["hours_processed"] = int(ctx.sim_state.stats.get("hours_processed", 0)) + 1
	return true

func _advance_settlement_providers_for_hour(ctx: RefCounted, h_seq: int) -> void:
	var econ = ctx.economy
	if econ == null:
		return
	var profile: String = String(econ.economy_profile_id)
	if profile == SettlementEconomyScript.PROFILE_NEUTRAL_TRIBE:
		econ.process_forage_regeneration(h_seq)
	elif profile == SettlementEconomyScript.PROFILE_MILITARY:
		var rec_ids: Array[String] = ctx.get_receiving_buffer_ids()
		if not rec_ids.is_empty() and ctx.workplace_registry.has_workplace(rec_ids[0]):
			var b_wp = ctx.workplace_registry.get_workplace(rec_ids[0])
			var eff_cap: int = ctx.get_workplace_effective_buffer_capacity(rec_ids[0])
			econ.process_military_logistics_to_buffer(h_seq, b_wp, eff_cap)
		else:
			econ.process_military_logistics(h_seq)
	elif profile == SettlementEconomyScript.PROFILE_MERCHANT:
		econ.process_market_restock(h_seq)
	if h_seq > _last_wildlife_recovery_hour_seq:
		_last_wildlife_recovery_hour_seq = h_seq
		if _world_data != null:
			SettlementResourceSourceAdapterScript.advance_wildlife_recovery(_world_data, 1.0)
	_evaluate_survival_mode(ctx)

func _update_settled_hour(ctx: RefCounted) -> void:
	var st = ctx.sim_state
	var villagers: Array = ctx.get_all_villagers_cached_view()
	if benchmark_telemetry_enabled:
		_bench_maintenance_villagers += villagers.size()
	if villagers.is_empty():
		return
	var min_h: int = int(st.required_hour_seq)
	for v in villagers:
		min_h = mini(min_h, int(v.last_processed_hour_seq))
	if min_h > int(st.settled_hour_seq):
		st.settled_hour_seq = min_h

# -----------------------------------------------------------------------------
# Survival Mode & Awaiting-Resupply State (§9, §17)
# -----------------------------------------------------------------------------
func _get_total_available_food(ctx: RefCounted) -> int:
	var total: int = int(ctx.economy.get_resource(EconomyConfigScript.RES_FOOD))
	for wp in ctx.workplace_registry.get_all_workplaces():
		if wp.output_resource == EconomyConfigScript.RES_FOOD:
			total += int(wp.buffer_amount)
	for v in ctx.get_all_villagers_cached_view():
		if v.get_carrying_resource() == EconomyConfigScript.RES_FOOD:
			total += v.get_carrying_amount()
	return total

func _evaluate_survival_mode(ctx: RefCounted) -> void:
	var st = ctx.sim_state
	var living: int = 0
	for v in ctx.get_all_villagers_cached_view():
		if v.life_state == SettlementVillagerDataScript.LIFE_ALIVE:
			living += 1
	var daily_need: int = maxi(1, living * SettlementSimulationConfigScript.DAILY_RATION_FOOD)
	var enter_thresh: int = int(ceil(float(daily_need) * SettlementSimulationConfigScript.SURVIVAL_ENTER_DAYS))
	var exit_thresh: int = int(ceil(float(daily_need) * SettlementSimulationConfigScript.SURVIVAL_EXIT_DAYS))
	var avail_food: int = _get_total_available_food(ctx)
	var old_state: String = String(st.survival_state)
	var new_state: String = old_state

	if living == 0:
		new_state = SettlementSimulationStateScript.SURVIVAL_NORMAL
		st.ration_shortfall = false
	elif avail_food < daily_need or st.ration_shortfall:
		new_state = SettlementSimulationStateScript.SURVIVAL_AWAITING_RESUPPLY
		st.recovery_hours_left = 0
	elif avail_food <= enter_thresh:
		new_state = SettlementSimulationStateScript.SURVIVAL_SURVIVAL
		st.recovery_hours_left = 0
	elif old_state == SettlementSimulationStateScript.SURVIVAL_SURVIVAL or old_state == SettlementSimulationStateScript.SURVIVAL_AWAITING_RESUPPLY:
		if avail_food >= exit_thresh:
			new_state = SettlementSimulationStateScript.SURVIVAL_RECOVERY
			st.recovery_hours_left = SettlementSimulationConfigScript.SURVIVAL_RECOVERY_HOURS
	elif old_state == SettlementSimulationStateScript.SURVIVAL_RECOVERY:
		if avail_food < enter_thresh:
			new_state = SettlementSimulationStateScript.SURVIVAL_SURVIVAL
			st.recovery_hours_left = 0
		elif st.recovery_hours_left > 0:
			st.recovery_hours_left -= 1
			if st.recovery_hours_left == 0:
				new_state = SettlementSimulationStateScript.SURVIVAL_NORMAL
		else:
			new_state = SettlementSimulationStateScript.SURVIVAL_NORMAL

	if new_state != old_state:
		st.survival_state = new_state
		survival_state_changed.emit(ctx.settlement_id, new_state, old_state)
		var was_wait: bool = (old_state == SettlementSimulationStateScript.SURVIVAL_AWAITING_RESUPPLY)
		var is_wait: bool = (new_state == SettlementSimulationStateScript.SURVIVAL_AWAITING_RESUPPLY)
		if was_wait != is_wait:
			awaiting_resupply_changed.emit(ctx.settlement_id, is_wait)

func _is_job_eligible_in_survival(ctx: RefCounted, job: RefCounted) -> bool:
	var st_name: String = String(ctx.sim_state.survival_state)
	if st_name == SettlementSimulationStateScript.SURVIVAL_NORMAL or st_name == SettlementSimulationStateScript.SURVIVAL_RECOVERY:
		return true
	if job.job_type == SettlementVillagerDataScript.ROLE_FARMER:
		return true
	if job.job_type == SettlementVillagerDataScript.ROLE_HUNTER:
		return true
	if job.job_type == SettlementVillagerDataScript.ROLE_GUARD:
		return true
	if job.job_type == SettlementVillagerDataScript.ROLE_HAULER:
		return job.cargo_resource == EconomyConfigScript.RES_FOOD or job.cargo_resource.is_empty()
	return false

# -----------------------------------------------------------------------------
# Daily Queue & Exactly-Once Food Consumption (§7, §8.1-8.2)
# -----------------------------------------------------------------------------
func _process_eligible_daily_events(ctx: RefCounted) -> int:
	var st = ctx.sim_state
	if st == null or st.pending_daily.is_empty():
		return 0
	var completed: int = 0
	var admitted_any: bool = false
	while not st.pending_daily.is_empty():
		var d_seq: int = int(st.pending_daily[0])
		if not _all_villagers_reached_hour(ctx, d_seq):
			break
		if _execute_daily_event(ctx, d_seq):
			admitted_any = true
		st.pending_daily.pop_front()
		st.completed_daily_seq = maxi(int(st.completed_daily_seq), d_seq)
		st.stats["daily_processed"] = int(st.stats.get("daily_processed", 0)) + 1
		completed += 1
	if admitted_any:
		_rebuild_pending_queue()
	return completed

func _all_villagers_reached_hour(ctx: RefCounted, target_h: int) -> bool:
	for v in ctx.get_all_villagers_cached_view():
		if int(v.last_processed_hour_seq) < target_h:
			return false
	return true

func _execute_daily_event(ctx: RefCounted, daily_seq: int) -> bool:
	var st = ctx.sim_state
	var eligible: Array = []
	for v in ctx.get_all_villagers_cached_view():
		if v.life_state != SettlementVillagerDataScript.LIFE_ALIVE:
			continue
		var last_d: int = int(st.villager_daily_seq.get(v.villager_id, -1))
		if last_d >= daily_seq:
			continue
		eligible.append(v)

	# Fair deterministic ration allocation: hungriest first, tie-break by villager_id
	eligible.sort_custom(func(a, b) -> bool:
		if not is_equal_approx(a.hunger, b.hunger):
			return a.hunger > b.hunger
		return a.villager_id < b.villager_id
	)

	var any_shortfall: bool = false
	var ration: int = SettlementSimulationConfigScript.DAILY_RATION_FOOD
	for v in eligible:
		if ctx.economy.has_resource(EconomyConfigScript.RES_FOOD, ration):
			var deb: Dictionary = ctx.economy.debit_resource(
				EconomyConfigScript.RES_FOOD,
				ration,
				"villager_ration:%s" % v.villager_id,
				"daily_food_consumption",
				daily_seq
			)
			if bool(deb.get("ok", false)):
				v.hunger = maxf(0.0, v.hunger - SettlementSimulationConfigScript.RATION_HUNGER_RESTORE)
			else:
				any_shortfall = true
				v.hunger = minf(SettlementSimulationConfigScript.HUNGER_MAX, v.hunger + SettlementSimulationConfigScript.MISSING_RATION_HUNGER_PENALTY)
		else:
			any_shortfall = true
			v.hunger = minf(SettlementSimulationConfigScript.HUNGER_MAX, v.hunger + SettlementSimulationConfigScript.MISSING_RATION_HUNGER_PENALTY)
		st.villager_daily_seq[v.villager_id] = daily_seq

	st.ration_shortfall = any_shortfall
	_evaluate_survival_mode(ctx)

	# Phase 5: Evaluate daily population immigration after existing residents & rations settle
	if not immigration_enabled:
		return false
	var svc := get_immigration_service()
	var stl_data := _find_settlement_data(ctx.settlement_id)
	var imm_res: Dictionary = svc.process_daily_immigration(
		ctx,
		_world_seed,
		daily_seq,
		stl_data,
		is_settlement_isolated(ctx.settlement_id)
	)
	return int(imm_res.get("admitted", 0)) > 0

# -----------------------------------------------------------------------------
# Per-Villager Needs & Logical Job Execution (§8.3-8.5, §10, §11, §12, §13)
# Strictly atomic: computes candidate state first, checks stage boundaries & executes
# economic/buffer transactions before committing villager, job, or watermark state.
# -----------------------------------------------------------------------------
func _record_diagnostic_event(ctx: RefCounted, v: RefCounted, h_seq: int, event_name: String) -> void:
	if not diagnostic_trace_enabled or ctx == null or v == null:
		return
	if _diagnostic_events.size() >= MAX_DIAGNOSTIC_EVENTS:
		_diagnostic_events.pop_front()
	var nctx = ctx.get_meta("nav_context") if ctx.has_meta("nav_context") else null
	var home_bd := _get_valid_home_building(ctx, v)
	var home_ac: Vector2i = home_bd.get("access_cell", home_bd.get("origin_cell", Vector2i(-1, -1))) if not home_bd.is_empty() else Vector2i(-1, -1)
	var loc = nctx.get_or_create_locomotion(v) if (nctx != null and nctx.has_method("get_or_create_locomotion")) else null
	_diagnostic_events.append({
		"h_seq": h_seq,
		"clock_hour": SettlementResourceSourceAdapterScript.clock_hour_from_hour_seq(h_seq) if h_seq >= 0 else -1,
		"event": event_name,
		"settlement_id": String(ctx.settlement_id),
		"faction_id": String(ctx.owner_faction_id),
		"villager_id": String(v.villager_id),
		"role": String(v.role),
		"cell": v.cell,
		"home_building_id": String(v.home_building_id),
		"home_access_cell": home_ac,
		"workplace_id": String(v.workplace_id),
		"task_state": String(v.task_state),
		"rest_phase": String(v.rest_phase),
		"cargo_amount": v.get_carrying_amount(),
		"cargo_resource": String(v.cargo.get("resource", "")),
		"nav_intent": String(loc.intent_key) if loc != null else "",
		"nav_status": int(loc.status) if loc != null else -1,
		"lod_is_far": bool(ctx.get_meta("lod_is_far", false)),
	})

func get_diagnostic_events() -> Array[Dictionary]:
	return _diagnostic_events.duplicate(true)

func clear_diagnostic_events() -> void:
	_diagnostic_events.clear()

func _is_daytime_hour(ctx: RefCounted, h_seq: int) -> bool:
	var tm_ref: Node = _time_manager
	if tm_ref == null and ctx != null and ctx.has_meta("time_manager"):
		tm_ref = ctx.get_meta("time_manager")
	if tm_ref != null and is_instance_valid(tm_ref) and tm_ref.has_method("get_day_phase"):
		var tm_seq: int = int(tm_ref.get_hour_seq()) if tm_ref.has_method("get_hour_seq") else -1
		if h_seq < 0 or tm_seq == h_seq:
			var dp: int = int(tm_ref.call("get_day_phase"))
			return dp == 0 or dp == 1 # DAWN (5..6) or DAY (7..17)
	if h_seq >= 0:
		return SettlementResourceSourceAdapterScript.is_day_shift_hour(h_seq)
	return true

func _get_valid_home_building(ctx: RefCounted, v: RefCounted) -> Dictionary:
	var hb_id: String = String(v.home_building_id)
	if hb_id.is_empty() or ctx == null or not ctx.has_method("get_residential_buildings"):
		return {}
	var is_res := false
	for rb in ctx.get_residential_buildings():
		if rb is Dictionary and String(rb.get("building_id", "")) == hb_id and int(rb.get("capacity", 0)) > 0:
			is_res = true
			break
	if not is_res:
		return {}
	if ctx.has_method("get_building_descriptors"):
		for bd in ctx.get_building_descriptors():
			if bd is Dictionary and String(bd.get("building_id", "")) == hb_id:
				return bd
	return {"building_id": hb_id}

func _has_valid_assigned_home(ctx: RefCounted, v: RefCounted) -> bool:
	return not _get_valid_home_building(ctx, v).is_empty()

## Immediately transitions a returning villager to REST_RESTING_INSIDE upon physical arrival at home.
func complete_home_arrival_if_eligible(ctx: RefCounted, v: RefCounted) -> bool:
	if ctx == null or v == null:
		return false
	if String(v.life_state) != SettlementVillagerDataScript.LIFE_ALIVE:
		return false
	if String(v.task_state) != SettlementVillagerDataScript.TASK_RESTING:
		return false
	if String(v.rest_phase) != SettlementVillagerDataScript.REST_RETURNING_HOME:
		return false
	if not _has_valid_assigned_home(ctx, v) or not _is_at_assigned_home(ctx, v):
		return false
	v.rest_phase = SettlementVillagerDataScript.REST_RESTING_INSIDE
	return true

func _is_at_assigned_home(ctx: RefCounted, v: RefCounted) -> bool:
	var bd := _get_valid_home_building(ctx, v)
	if bd.is_empty():
		return false
	var ac: Variant = bd.get("access_cell")
	if not (ac is Vector2i):
		ac = bd.get("origin_cell")
	if not (ac is Vector2i):
		return false
	var ac_cell: Vector2i = ac
	if ac_cell.x < 0 or ac_cell.y < 0:
		return false
	return IsoMath.grid_distance(v.cell, ac_cell) <= 2

func _is_villager_at_cell_target(ctx: RefCounted, v: RefCounted, target_cell: Vector2i, max_dist: int = 2) -> bool:
	if target_cell.x < 0 or target_cell.y < 0:
		return false
	if v.cell == target_cell or IsoMath.grid_distance(v.cell, target_cell) <= max_dist:
		return true
	if ctx != null and ctx.has_meta("nav_context"):
		var nctx = ctx.get_meta("nav_context")
		if nctx != null and nctx.has_method("find_closest_walkable_adjacent"):
			var adj: Vector2i = nctx.call("find_closest_walkable_adjacent", target_cell, v.cell)
			if adj != Vector2i(-1, -1) and v.cell == adj:
				return true
	return false

func _should_enforce_work_location(ctx: RefCounted) -> bool:
	if ctx == null:
		return false
	if ctx.has_meta("nav_context"):
		return true
	if ctx.has_meta("enforce_work_location_auth") and bool(ctx.get_meta("enforce_work_location_auth")):
		return true
	return false

func _is_villager_at_work_location(ctx: RefCounted, v: RefCounted, j: RefCounted, wp: RefCounted) -> bool:
	if not _should_enforce_work_location(ctx):
		return true
	if ctx == null or v == null or j == null or wp == null:
		return false
	if not (j is SettlementJobBoardScript.NpcJobRecord) or not (wp is SettlementWorkplaceRegistryScript.NpcWorkplaceRecord):
		return false
	if String(j.settlement_id) != String(ctx.settlement_id) or String(wp.settlement_id) != String(ctx.settlement_id):
		return false
	if not wp.is_active:
		return false
	var wp_cell: Vector2i = wp.access_cell if (wp.access_cell.x >= 0 and wp.access_cell.y >= 0) else wp.origin_cell
	if j.job_type == SettlementVillagerDataScript.ROLE_HAULER:
		if v.get_carrying_amount() > 0:
			var dcell: Vector2i = j.dest_cell
			if dcell.x < 0 or dcell.y < 0:
				dcell = wp_cell
			return _is_villager_at_cell_target(ctx, v, dcell, 2)
		var scell: Vector2i = j.source_cell
		if scell.x < 0 or scell.y < 0:
			scell = wp_cell
		return _is_villager_at_cell_target(ctx, v, scell, 2)
	if j.job_type == SettlementVillagerDataScript.ROLE_GUARD:
		var wt_id: String = String(v.work_target_id)
		if ctx.has_method("get_patrol_targets"):
			for pt in ctx.get_patrol_targets():
				if pt is Dictionary and String(pt.get("building_id", "")) == wt_id:
					var pac = pt.get("access_cell")
					if pac is Vector2i and _is_villager_at_cell_target(ctx, v, pac, 2):
						return true
	var tcell: Vector2i = j.target_cell
	if tcell.x < 0 or tcell.y < 0:
		tcell = wp_cell
	if _is_villager_at_cell_target(ctx, v, tcell, 2):
		return true
	return _is_villager_at_cell_target(ctx, v, wp_cell, 2)

func _simulate_villager_hour(ctx: RefCounted, v: RefCounted, h_seq: int) -> bool:
	var sid: String = ctx.settlement_id
	var vid: String = v.villager_id

	# 1. Compute candidate hunger
	var cand_hunger: float = minf(SettlementSimulationConfigScript.HUNGER_MAX, v.hunger + SettlementSimulationConfigScript.HUNGER_PER_HOUR)
	if not _check_stage_ok(sid, vid, h_seq, "after_needs"):
		return false

	# 1b. Advance offscreen FAR-LOD travel along valid cached/computed routes at hourly cadence
	if bool(ctx.get_meta("lod_is_far", false)) and ctx.has_meta("nav_context"):
		var far_nctx = ctx.get_meta("nav_context")
		if far_nctx != null and far_nctx.has_method("advance_far_hour"):
			far_nctx.call("advance_far_hour", ctx, v)

	# 2. Compute candidate fatigue / rest phase (exhaustion + scheduled night curfew)
	var is_daytime: bool = _is_daytime_hour(ctx, h_seq)
	var is_night_curfew: bool = (
		not is_daytime
		and v.role != SettlementVillagerDataScript.ROLE_GUARD
		and v.get_carrying_amount() == 0
	)
	var has_valid_home: bool = _has_valid_assigned_home(ctx, v)
	var at_home: bool = has_valid_home and _is_at_assigned_home(ctx, v)

	var cand_task: String = v.task_state
	var cand_rest: String = v.rest_phase
	var cand_fatigue: float = v.fatigue
	if cand_fatigue >= SettlementSimulationConfigScript.FATIGUE_EXHAUSTED:
		cand_task = SettlementVillagerDataScript.TASK_RESTING
		cand_rest = SettlementVillagerDataScript.REST_RESTING_INSIDE if (has_valid_home and (at_home or not _should_enforce_work_location(ctx))) else (SettlementVillagerDataScript.REST_RETURNING_HOME if has_valid_home else SettlementVillagerDataScript.REST_NONE)
	elif is_night_curfew:
		cand_task = SettlementVillagerDataScript.TASK_RESTING
		if has_valid_home:
			cand_rest = SettlementVillagerDataScript.REST_RESTING_INSIDE if at_home else SettlementVillagerDataScript.REST_RETURNING_HOME
		else:
			cand_rest = SettlementVillagerDataScript.REST_NONE
	elif cand_task == SettlementVillagerDataScript.TASK_RESTING:
		if is_daytime and cand_fatigue <= SettlementSimulationConfigScript.FATIGUE_RESUME:
			cand_task = SettlementVillagerDataScript.TASK_IDLE
			cand_rest = SettlementVillagerDataScript.REST_NONE
		elif has_valid_home and cand_rest == SettlementVillagerDataScript.REST_RETURNING_HOME and at_home:
			cand_rest = SettlementVillagerDataScript.REST_RESTING_INSIDE

	if not _check_stage_ok(sid, vid, h_seq, "before_job"):
		return false

	# 3. Evaluate candidate job execution (no mutation to v or job until commit)
	var target_job: RefCounted = null
	var target_wp: RefCounted = null
	var cand_job_state: String = ""
	var cand_job_hours: float = 0.0
	var cand_work_target: String = v.work_target_id
	var cand_work_hours: float = v.work_hours_done
	var executed_work: bool = false
	var should_deposit: bool = (v.get_carrying_amount() > 0)
	var can_deposit_at_loc: bool = true
	if should_deposit and _should_enforce_work_location(ctx):
		var drop_cell: Vector2i = Vector2i(v.cargo.get("dest_cell_x", -1), v.cargo.get("dest_cell_y", -1))
		if drop_cell.x < 0 or drop_cell.y < 0:
			var stl_d := _find_settlement_data(sid)
			if stl_d != null:
				drop_cell = stl_d.anchor_cell
		can_deposit_at_loc = _is_villager_at_cell_target(ctx, v, drop_cell, 2)
	var should_pickup: bool = false
	var should_produce_wp: RefCounted = null

	if cand_task == SettlementVillagerDataScript.TASK_RESTING:
		cand_fatigue = maxf(0.0, cand_fatigue - SettlementSimulationConfigScript.FATIGUE_REST_PER_HOUR)
	else:
		var job_plan := _plan_villager_job_hour(ctx, v, h_seq)
		if bool(job_plan.get("eligible", false)):
			if not _check_stage_ok(sid, vid, h_seq, "during_job"):
				return false
			target_job = job_plan["job"]
			var wp: RefCounted = job_plan["workplace"]
			target_wp = wp
			var is_arrived: bool = bool(job_plan.get("arrived", true))

			if not is_arrived:
				cand_task = String(job_plan["task_state"])
				cand_job_state = SettlementJobBoardScript.STATE_IN_PROGRESS
				cand_job_hours = target_job.work_hours_done
				cand_work_hours = v.work_hours_done
			else:
				# Immediate authoritative re-check before advancing labor progress
				var is_farmer_capped: bool = false
				if target_job.job_type == SettlementVillagerDataScript.ROLE_FARMER:
					var tm_ref: Node = _time_manager
					if tm_ref == null and ctx != null and ctx.has_meta("time_manager"):
						tm_ref = ctx.get_meta("time_manager")
					if SettlementResourceSourceAdapterScript.is_farm_daily_cap_reached(ctx, wp.workplace_id, tm_ref, h_seq):
						is_farmer_capped = true

				if is_farmer_capped:
					cand_task = SettlementVillagerDataScript.TASK_IDLE
					cand_fatigue = maxf(0.0, cand_fatigue - SettlementSimulationConfigScript.FATIGUE_IDLE_RECOVERY_PER_HOUR)
					target_job = null
				else:
					executed_work = true
					cand_task = String(job_plan["task_state"])
					cand_job_state = SettlementJobBoardScript.STATE_IN_PROGRESS
					cand_job_hours = target_job.work_hours_done + 1.0
					cand_work_hours = cand_job_hours
					if target_job.job_type == SettlementVillagerDataScript.ROLE_GUARD:
						if cand_job_hours >= target_job.work_hours_required:
							cand_job_hours = 0.0
							cand_work_hours = 0.0
							var next_t: Dictionary = ctx.get_next_patrol_target(cand_work_target, wp.workplace_id)
							if bool(next_t.get("ok", false)):
								cand_work_target = String(next_t.get("building_id", wp.workplace_id))
					elif target_job.job_type == SettlementVillagerDataScript.ROLE_HAULER:
						if not should_deposit:
							should_pickup = true
						if cand_job_hours >= target_job.work_hours_required:
							cand_job_hours = 0.0
							cand_work_hours = 0.0
					elif target_job.job_type == SettlementVillagerDataScript.ROLE_FARMER or target_job.job_type == SettlementVillagerDataScript.ROLE_WOODCUTTER:
						if cand_job_hours >= target_job.work_hours_required:
							cand_job_hours = 0.0
							cand_work_hours = 0.0
							should_produce_wp = wp
					elif target_job.job_type == SettlementVillagerDataScript.ROLE_HUNTER:
						var tm_ref: Node = _time_manager
						if tm_ref == null and ctx != null and ctx.has_meta("time_manager"):
							tm_ref = ctx.get_meta("time_manager")
						var h_res := SettlementResourceSourceAdapterScript.execute_hunter_production_transaction(
							ctx, wp.workplace_id, _world_data, tm_ref, v, 1.0, h_seq
						)
						cand_work_hours = v.work_hours_done
						cand_job_hours = v.work_hours_done
						if not bool(h_res.get("ok", false)) and String(h_res.get("reason", "")) == "no_available_prey":
							cand_task = SettlementVillagerDataScript.TASK_IDLE
					cand_fatigue = minf(SettlementSimulationConfigScript.FATIGUE_MAX, cand_fatigue + SettlementSimulationConfigScript.fatigue_per_work_hour(v.role))
		else:
			cand_task = SettlementVillagerDataScript.TASK_IDLE
			cand_fatigue = maxf(0.0, cand_fatigue - SettlementSimulationConfigScript.FATIGUE_IDLE_RECOVERY_PER_HOUR)

	# 4. Execute atomic economic/buffer steps (after all stage checks for that step pass)
	if should_deposit and can_deposit_at_loc:
		if not _check_stage_ok(sid, vid, h_seq, "during_deposit"):
			return false
		_attempt_hauler_deposit(ctx, v, h_seq)
		if executed_work and is_daytime and target_job != null and target_wp != null and target_job.job_type == SettlementVillagerDataScript.ROLE_HAULER and v.get_carrying_amount() == 0:
			if _is_villager_at_work_location(ctx, v, target_job, target_wp):
				should_pickup = true

	if should_pickup and target_job != null:
		if not _check_stage_ok(sid, vid, h_seq, "during_pickup"):
			return false
		_attempt_hauler_pickup(ctx, v, target_job, h_seq)

	if should_produce_wp != null:
		if not _check_stage_ok(sid, vid, h_seq, "during_production"):
			return false
		_attempt_source_backed_production(ctx, should_produce_wp)

	# 5. Compute candidate health & morale
	var cand_health: float = v.health
	if cand_hunger >= SettlementSimulationConfigScript.HEALTH_STARVING_HUNGER:
		cand_health = maxf(SettlementSimulationConfigScript.HEALTH_FLOOR, cand_health - SettlementSimulationConfigScript.HEALTH_DECLINE_PER_HOUR)
	elif cand_hunger <= SettlementSimulationConfigScript.HEALTH_RECOVERY_HUNGER_MAX:
		cand_health = minf(100.0, cand_health + SettlementSimulationConfigScript.HEALTH_RECOVERY_PER_HOUR)

	var cand_morale: float = v.morale
	if cand_hunger >= SettlementSimulationConfigScript.MORALE_STRESS_HUNGER or cand_fatigue >= SettlementSimulationConfigScript.MORALE_STRESS_FATIGUE:
		cand_morale = maxf(0.0, cand_morale - SettlementSimulationConfigScript.MORALE_LOSS_PER_HOUR)
	elif cand_hunger <= SettlementSimulationConfigScript.MORALE_COMFORT_HUNGER and cand_fatigue <= SettlementSimulationConfigScript.MORALE_COMFORT_FATIGUE:
		cand_morale = minf(100.0, cand_morale + SettlementSimulationConfigScript.MORALE_GAIN_PER_HOUR)

	# 6. Commit all authoritative villager & job fields together
	var prev_task: String = String(v.task_state)
	var prev_rest: String = String(v.rest_phase)
	v.hunger = cand_hunger
	v.task_state = cand_task
	v.rest_phase = cand_rest
	v.fatigue = cand_fatigue
	v.health = cand_health
	v.morale = cand_morale
	v.work_target_id = cand_work_target
	v.work_hours_done = cand_work_hours
	if target_job != null:
		target_job.state = cand_job_state
		target_job.work_hours_done = cand_job_hours
	if diagnostic_trace_enabled and (prev_task != cand_task or prev_rest != cand_rest):
		_record_diagnostic_event(ctx, v, h_seq, "%s:%s->%s:%s" % [prev_task, prev_rest, cand_task, cand_rest])
	return true

func _plan_villager_job_hour(ctx: RefCounted, v: RefCounted, h_seq: int = -1) -> Dictionary:
	if v.active_job_id.is_empty():
		return {"eligible": false}
	var j = ctx.job_board.get_job(v.active_job_id)
	if j == null or j.settlement_id != ctx.settlement_id or j.assigned_villager_id != v.villager_id:
		return {"eligible": false}
	var wp = ctx.workplace_registry.get_workplace(j.workplace_id)
	if wp == null or wp.settlement_id != ctx.settlement_id or not wp.is_active or wp.worker_quota <= 0:
		return {"eligible": false}
	if v.role != j.job_type:
		return {"eligible": false, "reason": "role_mismatch"}
	if j.job_type == SettlementVillagerDataScript.ROLE_FARMER and wp.building_type != "farm":
		return {"eligible": false, "reason": "workplace_mismatch"}
	if j.job_type == SettlementVillagerDataScript.ROLE_WOODCUTTER and wp.building_type != "woodcutter":
		return {"eligible": false, "reason": "workplace_mismatch"}
	if j.job_type == SettlementVillagerDataScript.ROLE_HUNTER and wp.building_type != "townhall":
		return {"eligible": false, "reason": "workplace_mismatch"}
	if wp.is_paused:
		return {"eligible": false, "reason": "workplace_paused"}
	if not _is_job_eligible_in_survival(ctx, j):
		return {"eligible": false}
	if (j.job_type == SettlementVillagerDataScript.ROLE_WOODCUTTER or j.job_type == SettlementVillagerDataScript.ROLE_FARMER or j.job_type == SettlementVillagerDataScript.ROLE_HUNTER) and h_seq >= 0:
		if not SettlementResourceSourceAdapterScript.is_day_shift_hour(h_seq):
			return {"eligible": false, "reason": "outside_day_shift"}
	if j.job_type == SettlementVillagerDataScript.ROLE_FARMER:
		var tm_node: Node = _time_manager
		if tm_node == null and ctx != null and ctx.has_meta("time_manager"):
			tm_node = ctx.get_meta("time_manager")
		var eff_h_seq: int = h_seq
		if eff_h_seq < 0 and tm_node != null and is_instance_valid(tm_node) and tm_node.has_method("get_hour_seq"):
			eff_h_seq = int(tm_node.get_hour_seq())
		if SettlementResourceSourceAdapterScript.is_farm_daily_cap_reached(ctx, wp.workplace_id, tm_node, eff_h_seq):
			return {"eligible": false, "reason": "daily_limit_reached"}
	var t_state: String = ""
	match j.job_type:
		SettlementVillagerDataScript.ROLE_GUARD:
			t_state = SettlementVillagerDataScript.TASK_GUARDING
		SettlementVillagerDataScript.ROLE_HAULER:
			t_state = SettlementVillagerDataScript.TASK_HAULING
		SettlementVillagerDataScript.ROLE_FARMER, SettlementVillagerDataScript.ROLE_WOODCUTTER, SettlementVillagerDataScript.ROLE_HUNTER:
			t_state = SettlementVillagerDataScript.TASK_WORKING
		_:
			return {"eligible": false}
	var arrived: bool = _is_villager_at_work_location(ctx, v, j, wp)
	if not arrived:
		t_state = SettlementVillagerDataScript.TASK_HAULING if j.job_type == SettlementVillagerDataScript.ROLE_HAULER else SettlementVillagerDataScript.TASK_MOVING_TO_JOB
	return {"eligible": true, "arrived": arrived, "job": j, "workplace": wp, "task_state": t_state}

func _attempt_source_backed_production(ctx: RefCounted, wp: RefCounted) -> void:
	var st = ctx.sim_state
	if not st.production_sources.has(wp.workplace_id):
		st.production_blocked[wp.workplace_id] = "missing_verified_production_source"
		return
	var src: Dictionary = st.production_sources[wp.workplace_id]

	# W1: Grounded Woodcutter with physical trees & exact-once labor banking
	if wp.building_type == "woodcutter":
		if not (src is Dictionary) or not src.has("trees") or not (src["trees"] is Array):
			st.production_blocked[wp.workplace_id] = "missing_verified_production_source"
			return
		if String(src.get("resource", "")) != "wood" and String(src.get("resource", "")) != wp.output_resource:
			st.production_blocked[wp.workplace_id] = "resource_mismatch"
			return
		if SettlementResourceSourceAdapterScript.calculate_remaining_wood(src) <= 0:
			st.production_blocked[wp.workplace_id] = "source_depleted"
			return
		src["work_credit_milli"] = int(src.get("work_credit_milli", 0)) + SettlementResourceSourceAdapterScript.CYCLE_WORK_CREDIT_MILLI
		SettlementResourceSourceAdapterScript.process_woodcutter_workplace_fellings(ctx, wp.workplace_id, _world_data, _get_world_view())
		return

	# F1: Farm crop production with exact-once quota accounting & backpressure preservation
	if wp.building_type == "farm":
		SettlementResourceSourceAdapterScript.process_farm_workplace_production(ctx, wp.workplace_id, _time_manager)
		return

	st.production_blocked[wp.workplace_id] = "unsupported_production_building"

func _attempt_hauler_pickup(ctx: RefCounted, v: RefCounted, j: RefCounted, h_seq: int) -> void:
	var st = ctx.sim_state
	var routes: Array[Dictionary] = ctx.get_transport_routes()
	for r in routes:
		if String(r.get("dest_workplace_id", "")) != j.workplace_id:
			continue
		var src_wp_id: String = String(r.get("source_workplace_id", ""))
		var src_wp = ctx.workplace_registry.get_workplace(src_wp_id)
		if src_wp == null or src_wp.settlement_id != ctx.settlement_id or int(src_wp.buffer_amount) <= 0:
			continue
		var res_id: String = String(r.get("cargo_resource", src_wp.output_resource))
		if res_id.is_empty():
			continue
		var tid: String = "pickup:%s:%s:%d" % [v.villager_id, src_wp_id, h_seq]
		if not st.mark_transfer(tid):
			continue
		var qty: int = mini(int(src_wp.buffer_amount), SettlementSimulationConfigScript.HAULER_CARRY_LIMIT)
		if qty <= 0:
			st.unmark_transfer(tid)
			continue
		src_wp.buffer_amount = int(src_wp.buffer_amount) - qty
		var eff_cap: int = ctx.get_workplace_effective_buffer_capacity(src_wp_id)
		src_wp.buffer_capacity = maxi(eff_cap, int(src_wp.buffer_amount))
		if src_wp.is_paused and src_wp.pause_reason == "buffer_full":
			var new_headroom: int = eff_cap - int(src_wp.buffer_amount)
			if src_wp.building_type == "woodcutter" and new_headroom >= SettlementResourceSourceAdapterScript.TREE_WOOD_UNITS:
				src_wp.is_paused = false
				src_wp.pause_reason = ""
				if st.production_sources.has(src_wp_id) and st.production_sources[src_wp_id].has("trees"):
					SettlementResourceSourceAdapterScript.process_woodcutter_workplace_fellings(ctx, src_wp_id, _world_data, _get_world_view())
			elif src_wp.building_type == "farm" and new_headroom > 0:
				src_wp.is_paused = false
				src_wp.pause_reason = ""
				if st.production_sources.has(src_wp_id):
					SettlementResourceSourceAdapterScript.try_deposit_pending_farm_output(ctx, src_wp_id, _time_manager)
		v.set_cargo(res_id, qty, src_wp_id, j.dest_cell)
		st.stats["pickups"] = int(st.stats.get("pickups", 0)) + 1
		return

func _attempt_hauler_deposit(ctx: RefCounted, v: RefCounted, h_seq: int) -> void:
	var amt: int = v.get_carrying_amount()
	var res_id: String = v.get_carrying_resource()
	if amt <= 0 or res_id.is_empty():
		return
	var tid: String = "deposit:%s:%s:%d:%d" % [v.villager_id, res_id, h_seq, amt]
	if not ctx.sim_state.mark_transfer(tid):
		return
	var headroom: int = ctx.economy.get_available_headroom(res_id)
	var dep_amt: int = mini(amt, headroom)
	if dep_amt <= 0:
		ctx.sim_state.unmark_transfer(tid)
		return
	var src_wp_id: String = String(v.cargo.get("source_workplace_id", "hauler_cargo"))
	var res: Dictionary = ctx.economy.deposit_hauled_resource(
		res_id,
		dep_amt,
		"workplace_output:%s" % src_wp_id,
		"hauler_deposit",
		h_seq
	)
	if not bool(res.get("ok", false)):
		ctx.sim_state.unmark_transfer(tid)
		return
	var rem: int = amt - dep_amt
	if rem > 0:
		v.set_cargo(res_id, rem, src_wp_id, v.cargo.get("dest_cell", Vector2i(-1, -1)))
	else:
		v.clear_cargo()
	ctx.sim_state.stats["deposits"] = int(ctx.sim_state.stats.get("deposits", 0)) + 1

# -----------------------------------------------------------------------------
# Read-Only Telemetry & Status API (§16.4)
# -----------------------------------------------------------------------------
func get_telemetry() -> Dictionary:
	var total_villagers: int = 0
	var max_lag: int = 0
	var pending_daily_total: int = 0
	for sid in get_registered_settlement_ids():
		var ctx = _contexts_by_id[sid]
		total_villagers += ctx.get_villager_count()
		if ctx.sim_state != null:
			pending_daily_total += ctx.sim_state.pending_daily.size()
			for v in ctx.get_all_villagers_cached_view():
				max_lag = maxi(max_lag, maxi(0, _required_hour_seq - int(v.last_processed_hour_seq)))
	return {
		"required_hour_seq": _required_hour_seq,
		"oldest_villager_lag": max_lag,
		"pending_villager_hours": _pending_queue.size(),
		"pending_daily_events": pending_daily_total,
		"last_batch_duration_ms": _last_batch_duration_ms,
		"max_batch_duration_ms": _max_batch_duration_ms,
		"registered_settlements": _contexts_by_id.size(),
		"registered_villagers": total_villagers,
		"isolated_settlements": _isolated_settlements.size(),
		"requested_speed": _requested_speed,
		"effective_speed": _effective_speed,
		"backpressure_active": _backpressure_active,
		"backpressure_enabled": backpressure_enabled
	}

func reset_benchmark_metrics() -> void:
	_bench_sim_samples_ms = PackedFloat64Array()
	_bench_sim_sample_cursor = 0
	_bench_sim_ticks = 0
	_bench_sim_total_ms = 0.0
	_bench_villagers_processed = 0
	_bench_settlements_processed = 0
	_bench_rebuild_queue_ms = 0.0
	_bench_update_settled_ms = 0.0
	_bench_eval_bp_ms = 0.0
	_bench_maintenance_villagers = 0
	for sid in get_registered_settlement_ids():
		var ctx = _contexts_by_id.get(sid, null)
		if ctx != null and ctx.has_method("reset_villager_cache_telemetry"):
			ctx.reset_villager_cache_telemetry()
	if _ambient_locomotion != null:
		_ambient_locomotion.reset_benchmark_metrics()

func get_benchmark_metrics() -> Dictionary:
	var n: int = _bench_sim_samples_ms.size()
	var avg_ms: float = (_bench_sim_total_ms / float(_bench_sim_ticks)) if _bench_sim_ticks > 0 else 0.0
	var p95_ms: float = 0.0
	if n > 0:
		var sorted: Array[float] = []
		sorted.resize(n)
		for i in range(n):
			sorted[i] = _bench_sim_samples_ms[i]
		sorted.sort()
		var idx: int = clampi(int(ceil(0.95 * float(n))) - 1, 0, n - 1)
		p95_ms = sorted[idx]
	var cache_rebuilds: int = 0
	var cache_parses: int = 0
	var cache_hits: int = 0
	for sid in get_registered_settlement_ids():
		var ctx = _contexts_by_id.get(sid, null)
		if ctx != null and ctx.has_method("get_villager_cache_telemetry"):
			var ct: Dictionary = ctx.get_villager_cache_telemetry()
			cache_rebuilds += int(ct.get("rebuilds", 0))
			cache_parses += int(ct.get("id_parses", 0))
			cache_hits += int(ct.get("hits", 0))
	return {
		"enabled": benchmark_telemetry_enabled,
		"sim_ticks": _bench_sim_ticks,
		"total_sim_ms": _bench_sim_total_ms,
		"avg_sim_ms": avg_ms,
		"p95_sim_ms": p95_ms,
		"max_sim_ms": _max_batch_duration_ms,
		"villagers_processed": _bench_villagers_processed,
		"active_settlements_processed": _bench_settlements_processed,
		"rebuild_queue_ms": _bench_rebuild_queue_ms,
		"update_settled_ms": _bench_update_settled_ms,
		"eval_bp_ms": _bench_eval_bp_ms,
		"maintenance_villagers": _bench_maintenance_villagers,
		"cache_rebuilds": cache_rebuilds,
		"cache_id_parses": cache_parses,
		"cache_hits": cache_hits,
		"ambient_locomotion": _ambient_locomotion.get_benchmark_metrics() if _ambient_locomotion != null else {},
	}
