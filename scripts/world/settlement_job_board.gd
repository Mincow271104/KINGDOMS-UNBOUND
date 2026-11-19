class_name SettlementJobBoard
extends RefCounted
## Settlement-scoped NPC job board boundary (Architecture v1.0 — Phase 1).
## Strictly isolated per settlement; has zero dependency on player JobManager,
## /root/ResourceManager, or CitizenController.

const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")

const STATE_AVAILABLE: String = "available"
const STATE_RESERVED: String = "reserved"
const STATE_IN_PROGRESS: String = "in_progress"
const STATE_COMPLETED: String = "completed"
const STATE_CANCELLED: String = "cancelled"

const VALID_JOB_STATES: Array[String] = [
	STATE_AVAILABLE,
	STATE_RESERVED,
	STATE_IN_PROGRESS,
	STATE_COMPLETED,
	STATE_CANCELLED
]

class NpcJobRecord extends RefCounted:
	# Identity & ownership fields: write-once before registration, immutable once set/registered.
	var _job_id: String = ""
	var _settlement_id: String = ""
	var _identity_locked: bool = false

	var job_id: String:
		get:
			return _job_id
		set(value):
			if _identity_locked or not _job_id.is_empty():
				return
			var clean := value.strip_edges()
			if SettlementVillagerDataScript.is_valid_identifier(clean):
				_job_id = clean

	var settlement_id: String:
		get:
			return _settlement_id
		set(value):
			if _identity_locked or not _settlement_id.is_empty():
				return
			var clean := value.strip_edges()
			if SettlementVillagerDataScript.is_valid_identifier(clean):
				_settlement_id = clean

	var job_type: String = ""
	var workplace_id: String = ""
	var target_cell: Vector2i = Vector2i.ZERO
	var source_cell: Vector2i = Vector2i.ZERO
	var dest_cell: Vector2i = Vector2i.ZERO
	var state: String = STATE_AVAILABLE
	var assigned_villager_id: String = ""
	var work_hours_required: float = 2.0
	var work_hours_done: float = 0.0
	var priority: int = 1
	var cargo_resource: String = ""
	var cargo_amount: int = 0

	func lock_identity() -> void:
		_identity_locked = true

	func is_identity_locked() -> bool:
		return _identity_locked

	func is_valid_for_settlement(expected_sid: String) -> bool:
		if not SettlementVillagerDataScript.is_valid_identifier(expected_sid):
			return false
		if settlement_id != expected_sid:
			return false
		if not SettlementVillagerDataScript.is_valid_identifier(job_id):
			return false
		if job_type.strip_edges().is_empty():
			return false
		if not VALID_JOB_STATES.has(state):
			return false
		if is_nan(work_hours_required) or is_inf(work_hours_required) or work_hours_required <= 0.0:
			return false
		if is_nan(work_hours_done) or is_inf(work_hours_done) or work_hours_done < 0.0:
			return false
		if priority < 1 or priority > 20:
			return false
		if cargo_amount < 0:
			return false
		return true

	func to_dict() -> Dictionary:
		return {
			"job_id": job_id,
			"settlement_id": settlement_id,
			"job_type": job_type,
			"workplace_id": workplace_id,
			"target_cell": {"x": target_cell.x, "y": target_cell.y},
			"source_cell": {"x": source_cell.x, "y": source_cell.y},
			"dest_cell": {"x": dest_cell.x, "y": dest_cell.y},
			"state": state,
			"assigned_villager_id": assigned_villager_id,
			"work_hours_required": work_hours_required,
			"work_hours_done": work_hours_done,
			"priority": priority,
			"cargo_resource": cargo_resource,
			"cargo_amount": cargo_amount
		}

	static func from_dict(data: Variant) -> NpcJobRecord:
		if not (data is Dictionary):
			return null
		var d: Dictionary = data
		if not (d.get("job_id") is String) or not (d.get("settlement_id") is String) or not (d.get("job_type") is String):
			return null
		for str_key in ["workplace_id", "state", "assigned_villager_id", "cargo_resource"]:
			if d.has(str_key) and not (d[str_key] is String):
				return null
		for vec_key in ["target_cell", "source_cell", "dest_cell"]:
			if d.has(vec_key) and not SettlementVillagerDataScript._is_valid_vec2i_input(d[vec_key]):
				return null
		for num_key in ["work_hours_required", "work_hours_done", "priority", "cargo_amount"]:
			if d.has(num_key) and not SettlementVillagerDataScript._is_valid_finite_number(d[num_key]):
				return null

		var rec := NpcJobRecord.new()
		rec.job_id = String(d["job_id"]).strip_edges()
		rec.settlement_id = String(d["settlement_id"]).strip_edges()
		rec.job_type = String(d["job_type"]).strip_edges()
		rec.workplace_id = String(d.get("workplace_id", "")).strip_edges()
		rec.target_cell = SettlementVillagerDataScript._parse_vec2i(d.get("target_cell", Vector2i.ZERO), Vector2i.ZERO)
		rec.source_cell = SettlementVillagerDataScript._parse_vec2i(d.get("source_cell", Vector2i.ZERO), Vector2i.ZERO)
		rec.dest_cell = SettlementVillagerDataScript._parse_vec2i(d.get("dest_cell", Vector2i.ZERO), Vector2i.ZERO)
		rec.state = String(d.get("state", STATE_AVAILABLE)).strip_edges()
		rec.assigned_villager_id = String(d.get("assigned_villager_id", "")).strip_edges()
		rec.work_hours_required = float(d.get("work_hours_required", 2.0))
		rec.work_hours_done = float(d.get("work_hours_done", 0.0))
		rec.priority = int(d.get("priority", 1))
		rec.cargo_resource = String(d.get("cargo_resource", "")).strip_edges()
		rec.cargo_amount = int(d.get("cargo_amount", 0))
		if not rec.is_valid_for_settlement(rec.settlement_id):
			return null
		rec.lock_identity()
		return rec

var _settlement_id: String = ""
var settlement_id: String:
	get:
		return _settlement_id
	set(value):
		if not _settlement_id.is_empty():
			return
		var clean := value.strip_edges()
		if SettlementVillagerDataScript.is_valid_identifier(clean):
			_settlement_id = clean

var _next_job_seq: int = 1
var _jobs_by_id: Dictionary = {}

func _init(p_settlement_id: String = "") -> void:
	_settlement_id = p_settlement_id.strip_edges()

func is_valid() -> bool:
	return SettlementVillagerDataScript.is_valid_identifier(settlement_id)

func allocate_job_id() -> String:
	if not is_valid():
		return ""
	var jid: String = "npc_job_%s_%d" % [settlement_id, _next_job_seq]
	_next_job_seq += 1
	while _jobs_by_id.has(jid):
		jid = "npc_job_%s_%d" % [settlement_id, _next_job_seq]
		_next_job_seq += 1
	return jid

func register_job(job_or_dict: Variant) -> bool:
	if not is_valid():
		return false
	var rec: NpcJobRecord = null
	if job_or_dict is NpcJobRecord:
		rec = job_or_dict
	elif job_or_dict is Dictionary:
		rec = NpcJobRecord.from_dict(job_or_dict)
	if rec == null or not rec.is_valid_for_settlement(settlement_id):
		return false
	if _jobs_by_id.has(rec.job_id):
		return false
	rec.lock_identity()
	_jobs_by_id[rec.job_id] = rec
	var prefix := "npc_job_%s_" % settlement_id
	if rec.job_id.begins_with(prefix):
		var suf := rec.job_id.substr(prefix.length())
		if suf.is_valid_int() and int(suf) >= _next_job_seq:
			_next_job_seq = int(suf) + 1
	return true

func create_job_record(
	p_job_type: String,
	p_workplace_id: String = "",
	p_target_cell: Vector2i = Vector2i.ZERO,
	p_work_hours_required: float = 2.0,
	p_priority: int = 1
) -> NpcJobRecord:
	if not is_valid() or p_job_type.strip_edges().is_empty():
		return null
	var jid := allocate_job_id()
	if jid.is_empty():
		return null
	var rec := NpcJobRecord.new()
	rec.job_id = jid
	rec.settlement_id = settlement_id
	rec.job_type = p_job_type.strip_edges()
	rec.workplace_id = p_workplace_id.strip_edges()
	rec.target_cell = p_target_cell
	rec.work_hours_required = maxf(0.1, p_work_hours_required)
	rec.priority = clampi(p_priority, 1, 20)
	if not register_job(rec):
		return null
	return rec

## Returns the live canonical NpcJobRecord reference for `job_id`, or `null` if absent.
## Mutations to the returned object directly update canonical job state on this board.
func get_job(job_id: String) -> NpcJobRecord:
	return _jobs_by_id.get(job_id, null)

func has_job(job_id: String) -> bool:
	return _jobs_by_id.has(job_id)

func remove_job(job_id: String) -> bool:
	if not _jobs_by_id.has(job_id):
		return false
	_jobs_by_id.erase(job_id)
	return true

## Returns a newly allocated Array[NpcJobRecord] sorted by `job_id` containing live canonical
## NpcJobRecord references. Mutating the returned Array container does not affect board membership;
## mutating a returned NpcJobRecord element updates canonical state.
func get_all_jobs() -> Array[NpcJobRecord]:
	var keys: Array = _jobs_by_id.keys()
	keys.sort()
	var out: Array[NpcJobRecord] = []
	for k in keys:
		out.append(_jobs_by_id[k])
	return out

func get_job_count() -> int:
	return _jobs_by_id.size()

func clear() -> void:
	_jobs_by_id.clear()

func to_dict() -> Dictionary:
	var list: Array[Dictionary] = []
	for j in get_all_jobs():
		list.append(j.to_dict())
	return {
		"settlement_id": settlement_id,
		"next_job_seq": _next_job_seq,
		"jobs": list
	}

func serialize() -> Dictionary:
	return to_dict()

static func from_dict(data: Variant) -> RefCounted:
	if not (data is Dictionary):
		return null
	var d: Dictionary = data
	if not (d.get("settlement_id") is String):
		return null
	var sid := String(d["settlement_id"]).strip_edges()
	if not SettlementVillagerDataScript.is_valid_identifier(sid):
		return null
	if d.has("next_job_seq"):
		if not SettlementVillagerDataScript._is_valid_finite_number(d["next_job_seq"]) or int(d["next_job_seq"]) < 1:
			return null
	if d.has("jobs") and not (d["jobs"] is Array):
		return null
	var board := new(sid)
	board._next_job_seq = int(d.get("next_job_seq", 1))
	var raw_jobs: Array = d.get("jobs", [])
	for item in raw_jobs:
		if not board.register_job(item):
			return null
	return board

static func deserialize(data: Variant) -> RefCounted:
	return from_dict(data)
