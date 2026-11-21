class_name PathRequestScheduler
extends RefCounted
## Phase 6 Bounded Incremental PathRequestScheduler.
## Enforces a global per-frame A* node-expansion budget across all Rival Settlements,
## round-robin settlement fairness, deduplication by (settlement_id, villager_id),
## stale cancellation, and bounded queue overflow eviction.

const GridNavigationScript = preload("res://scripts/navigation/grid_navigation.gd")

# Provisional Phase 6 Budgets
const MAX_ASTAR_EXPANSIONS_PER_FRAME: int = 256
const MAX_PATH_REQUESTS_PER_FRAME: int = 4
const MAX_QUEUE_SIZE: int = 128
const RETRY_COOLDOWN_SEC: float = 2.0

const PRIO_VISIBLE_NEAR: int = 1
const PRIO_NEAR: int = 2
const PRIO_MID: int = 3
const PRIO_BACKGROUND: int = 4

class PathRequest extends RefCounted:
	var key: String = "" # "<settlement_id>:<villager_id>"
	var settlement_id: String = ""
	var villager_id: String = ""
	var start_cell: Vector2i = Vector2i.ZERO
	var goal_cell: Vector2i = Vector2i.ZERO
	var intent_key: String = ""
	var nav_revision: int = 0
	var priority: int = PRIO_MID
	var nav_ctx: RefCounted = null
	var villager_ref: RefCounted = null
	var search_state: GridNavigationScript.IncrementalAStarSearch = null
	var seq: int = 0
	var enqueue_usec: int = 0

var max_expansions_per_frame: int = MAX_ASTAR_EXPANSIONS_PER_FRAME
var max_admissions_per_frame: int = MAX_PATH_REQUESTS_PER_FRAME
var max_queue_size: int = MAX_QUEUE_SIZE

var _pending_by_key: Dictionary = {} # key -> PathRequest
var _active_by_key: Dictionary = {} # key -> PathRequest (currently has IncrementalAStarSearch)
var _settlement_rr_order: Array[String] = []
var _rr_cursor: int = 0
var _next_seq: int = 1

# Instrumentation for tests & telemetry
var last_frame_expansions: int = 0
var last_frame_admitted: int = 0
var last_frame_completed: int = 0
var total_expansions: int = 0
var total_completed: int = 0
var total_cancelled: int = 0
var total_dropped_overflow: int = 0

# M0 Opt-In Benchmark Telemetry (disabled by default; zero gameplay impact)
const BENCH_SAMPLE_CAP: int = 256
var benchmark_telemetry_enabled: bool = false
var _bench_submitted: int = 0
var _bench_accepted: int = 0
var _bench_rejected: int = 0
var _bench_max_queue_depth: int = 0
var _bench_prio_counts: Dictionary = {}
var _bench_wait_samples_ms: PackedFloat64Array = PackedFloat64Array()
var _bench_wait_cursor: int = 0
var _bench_wait_total_ms: float = 0.0
var _bench_wait_count: int = 0
var _bench_last_step_ms: float = 0.0

func get_queue_size() -> int:
	return _pending_by_key.size() + _active_by_key.size()

func get_pending_count() -> int:
	return _pending_by_key.size()

func get_active_count() -> int:
	return _active_by_key.size()

func has_request(settlement_id: String, villager_id: String) -> bool:
	var k := "%s:%s" % [settlement_id, villager_id]
	return _pending_by_key.has(k) or _active_by_key.has(k)

func enqueue(
	settlement_id: String,
	villager_id: String,
	start_cell: Vector2i,
	goal_cell: Vector2i,
	intent_key: String,
	nav_revision: int,
	priority: int,
	nav_ctx: RefCounted,
	villager_ref: RefCounted
) -> bool:
	if settlement_id.is_empty() or villager_id.is_empty() or nav_ctx == null or villager_ref == null:
		if benchmark_telemetry_enabled:
			_bench_submitted += 1
			_bench_rejected += 1
		return false
	if benchmark_telemetry_enabled:
		_bench_submitted += 1
	var k := "%s:%s" % [settlement_id, villager_id]

	# Deduplicate: if an active or pending request already matches exact intent & revision, keep it (update priority if higher)
	if _active_by_key.has(k):
		var act: PathRequest = _active_by_key[k]
		if act.intent_key == intent_key and act.nav_revision == nav_revision and act.goal_cell == goal_cell:
			act.priority = mini(act.priority, priority)
			return true
		# Superseded active request: cancel it
		_active_by_key.erase(k)
		total_cancelled += 1

	if _pending_by_key.has(k):
		var pend: PathRequest = _pending_by_key[k]
		if pend.intent_key == intent_key and pend.nav_revision == nav_revision and pend.goal_cell == goal_cell:
			pend.priority = mini(pend.priority, priority)
			return true
		_pending_by_key.erase(k)
		total_cancelled += 1

	# Enforce bounded queue capacity (evict lowest priority / oldest pending if full)
	if get_queue_size() >= max_queue_size:
		if not _evict_lowest_priority_pending(priority):
			total_dropped_overflow += 1
			if benchmark_telemetry_enabled:
				_bench_rejected += 1
			return false

	var req := PathRequest.new()
	req.key = k
	req.settlement_id = settlement_id
	req.villager_id = villager_id
	req.start_cell = start_cell
	req.goal_cell = goal_cell
	req.intent_key = intent_key
	req.nav_revision = nav_revision
	req.priority = priority
	req.nav_ctx = nav_ctx
	req.villager_ref = villager_ref
	req.seq = _next_seq
	_next_seq += 1
	if benchmark_telemetry_enabled:
		req.enqueue_usec = Time.get_ticks_usec()
		_bench_accepted += 1
		_bench_prio_counts[priority] = int(_bench_prio_counts.get(priority, 0)) + 1

	_pending_by_key[k] = req
	if benchmark_telemetry_enabled:
		_bench_max_queue_depth = maxi(_bench_max_queue_depth, get_queue_size())
	if not _settlement_rr_order.has(settlement_id):
		_settlement_rr_order.append(settlement_id)
		_settlement_rr_order.sort()
	return true

func cancel_villager(settlement_id: String, villager_id: String) -> void:
	var k := "%s:%s" % [settlement_id, villager_id]
	if _pending_by_key.erase(k):
		total_cancelled += 1
	if _active_by_key.erase(k):
		total_cancelled += 1

func cancel_settlement(settlement_id: String) -> void:
	for k in _pending_by_key.keys():
		if (_pending_by_key[k] as PathRequest).settlement_id == settlement_id:
			_pending_by_key.erase(k)
			total_cancelled += 1
	for k in _active_by_key.keys():
		if (_active_by_key[k] as PathRequest).settlement_id == settlement_id:
			_active_by_key.erase(k)
			total_cancelled += 1
	_settlement_rr_order.erase(settlement_id)

func clear_all() -> void:
	_pending_by_key.clear()
	_active_by_key.clear()
	_settlement_rr_order.clear()
	_rr_cursor = 0

func _evict_lowest_priority_pending(incoming_priority: int) -> bool:
	var worst_key: String = ""
	var worst_prio: int = -1
	var worst_seq: int = 999999999
	for k in _pending_by_key.keys():
		var r: PathRequest = _pending_by_key[k]
		if r.priority > worst_prio or (r.priority == worst_prio and r.seq < worst_seq):
			worst_prio = r.priority
			worst_seq = r.seq
			worst_key = k
	if worst_key.is_empty() or worst_prio <= incoming_priority:
		return false
	_pending_by_key.erase(worst_key)
	total_dropped_overflow += 1
	return true

func _is_request_valid(req: PathRequest) -> bool:
	if req == null or req.nav_ctx == null or req.villager_ref == null:
		return false
	if req.nav_ctx.nav_revision != req.nav_revision:
		return false
	if not req.nav_ctx.has_locomotion(req.villager_id):
		return false
	var loc = req.nav_ctx.get_or_create_locomotion(req.villager_ref)
	if loc == null or loc.intent_key != req.intent_key:
		return false
	return true

## Steps active searches and admits new searches within global per-frame expansion & admission budgets.
func step_frame(sim_manager: Object = null) -> void:
	var step_start_usec: int = Time.get_ticks_usec() if benchmark_telemetry_enabled else 0
	last_frame_expansions = 0
	last_frame_admitted = 0
	last_frame_completed = 0

	var remaining_expansions: int = max_expansions_per_frame

	# 1. Admit up to max_admissions_per_frame new searches using round-robin across settlements
	var admitted_now: int = 0
	if not _pending_by_key.is_empty() and not _settlement_rr_order.is_empty():
		var s_count: int = _settlement_rr_order.size()
		var attempts: int = 0
		var max_attempts: int = s_count * maxi(1, max_admissions_per_frame)
		while admitted_now < max_admissions_per_frame and not _pending_by_key.is_empty() and attempts < max_attempts:
			attempts += 1
			var sid: String = _settlement_rr_order[_rr_cursor % s_count]
			_rr_cursor = (_rr_cursor + 1) % s_count
			var best_req: PathRequest = _pick_best_pending_for_settlement(sid)
			if best_req == null:
				continue
			_pending_by_key.erase(best_req.key)
			if not _is_request_valid(best_req) or (sim_manager != null and not sim_manager.has_context(sid)):
				total_cancelled += 1
				continue
			var gnav: GridNavigation = best_req.nav_ctx.grid_nav
			if gnav == null:
				total_cancelled += 1
				continue
			best_req.search_state = gnav.create_incremental_astar_search(
				best_req.start_cell,
				best_req.goal_cell,
				best_req.nav_ctx.get_walkability_predicate(),
				2048,
				best_req.nav_revision
			)
			_active_by_key[best_req.key] = best_req
			admitted_now += 1
	last_frame_admitted = admitted_now

	if _active_by_key.is_empty() or remaining_expansions <= 0:
		return

	# 2. Step active searches in priority + round-robin order without ever exceeding remaining_expansions
	var active_list: Array[PathRequest] = []
	for k in _active_by_key.keys():
		active_list.append(_active_by_key[k])
	active_list.sort_custom(func(a: PathRequest, b: PathRequest) -> bool:
		if a.priority != b.priority:
			return a.priority < b.priority
		return a.seq < b.seq
	)

	var active_idx: int = 0
	while remaining_expansions > 0 and not active_list.is_empty():
		if active_idx >= active_list.size():
			active_idx = 0
		var req: PathRequest = active_list[active_idx]
		if not _is_request_valid(req) or (sim_manager != null and not sim_manager.has_context(req.settlement_id)):
			_active_by_key.erase(req.key)
			active_list.remove_at(active_idx)
			total_cancelled += 1
			continue

		# Fair slice per active search, never exceeding remaining_expansions
		var slice_budget: int = mini(remaining_expansions, maxi(16, int(ceil(float(remaining_expansions) / float(active_list.size())))))
		var gnav: GridNavigation = req.nav_ctx.grid_nav
		var res: Dictionary = gnav.step_incremental_astar_search(req.search_state, slice_budget)
		var used: int = int(res.get("step_expansions", 0))
		remaining_expansions = maxi(0, remaining_expansions - used)
		last_frame_expansions += used
		total_expansions += used

		var st_code: int = int(res.get("status", GridNavigationScript.NearestSearchStatus.UNREACHABLE))
		if st_code == GridNavigationScript.NearestSearchStatus.IN_PROGRESS:
			active_idx += 1
			if used == 0:
				break
			continue

		# Search finished (FOUND / UNREACHABLE / BUDGET_EXHAUSTED / INVALID_INPUT)
		_active_by_key.erase(req.key)
		active_list.remove_at(active_idx)
		if _is_request_valid(req):
			var path: Array[Vector2i] = res.get("path", []) if st_code == GridNavigationScript.NearestSearchStatus.FOUND else ([] as Array[Vector2i])
			if not path.is_empty():
				req.nav_ctx.store_cached_path(req.start_cell, req.goal_cell, path)
			req.nav_ctx.apply_computed_path(req.villager_ref, path, req.intent_key, req.nav_revision)
			last_frame_completed += 1
			total_completed += 1
			if benchmark_telemetry_enabled and req.enqueue_usec > 0:
				var wait_ms: float = float(Time.get_ticks_usec() - req.enqueue_usec) / 1000.0
				_bench_wait_total_ms += wait_ms
				_bench_wait_count += 1
				if _bench_wait_samples_ms.size() < BENCH_SAMPLE_CAP:
					_bench_wait_samples_ms.append(wait_ms)
				else:
					_bench_wait_samples_ms[_bench_wait_cursor] = wait_ms
					_bench_wait_cursor = (_bench_wait_cursor + 1) % BENCH_SAMPLE_CAP
		else:
			total_cancelled += 1
	if benchmark_telemetry_enabled:
		_bench_last_step_ms = float(Time.get_ticks_usec() - step_start_usec) / 1000.0
		_bench_max_queue_depth = maxi(_bench_max_queue_depth, get_queue_size())

func _pick_best_pending_for_settlement(sid: String) -> PathRequest:
	var best: PathRequest = null
	for k in _pending_by_key.keys():
		var r: PathRequest = _pending_by_key[k]
		if r.settlement_id != sid:
			continue
		if best == null or r.priority < best.priority or (r.priority == best.priority and r.seq < best.seq):
			best = r
	return best

func reset_benchmark_metrics() -> void:
	_bench_submitted = 0
	_bench_accepted = 0
	_bench_rejected = 0
	_bench_max_queue_depth = get_queue_size()
	_bench_prio_counts.clear()
	_bench_wait_samples_ms = PackedFloat64Array()
	_bench_wait_cursor = 0
	_bench_wait_total_ms = 0.0
	_bench_wait_count = 0
	_bench_last_step_ms = 0.0

func get_benchmark_metrics() -> Dictionary:
	var n: int = _bench_wait_samples_ms.size()
	var avg_wait: float = (_bench_wait_total_ms / float(_bench_wait_count)) if _bench_wait_count > 0 else 0.0
	var p95_wait: float = 0.0
	if n > 0:
		var sorted: Array[float] = []
		sorted.resize(n)
		for i in range(n):
			sorted[i] = _bench_wait_samples_ms[i]
		sorted.sort()
		var idx: int = clampi(int(ceil(0.95 * float(n))) - 1, 0, n - 1)
		p95_wait = sorted[idx]
	return {
		"enabled": benchmark_telemetry_enabled,
		"submitted": _bench_submitted,
		"accepted": _bench_accepted,
		"rejected": _bench_rejected,
		"cancelled": total_cancelled,
		"dropped_overflow": total_dropped_overflow,
		"queue_depth": get_queue_size(),
		"max_queue_depth": _bench_max_queue_depth,
		"active_searches": _active_by_key.size(),
		"last_frame_expansions": last_frame_expansions,
		"total_expansions": total_expansions,
		"last_step_ms": _bench_last_step_ms,
		"avg_wait_ms": avg_wait,
		"p95_wait_ms": p95_wait,
		"prio_counts": _bench_prio_counts.duplicate(),
	}
