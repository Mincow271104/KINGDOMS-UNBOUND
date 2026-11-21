class_name SettlementWorkplaceRegistry
extends RefCounted
## Settlement-scoped NPC workplace registry boundary (Architecture v1.0 — Phase 1).
## Strictly isolated per settlement; has zero dependency on player WorkplaceManager,
## /root/ResourceManager, or CitizenController.

const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")

class NpcWorkplaceRecord extends RefCounted:
	# Identity & ownership fields: write-once before registration, immutable once set/registered.
	var _workplace_id: String = ""
	var _settlement_id: String = ""
	var _building_id: String = ""
	var _identity_locked: bool = false

	var workplace_id: String:
		get:
			return _workplace_id
		set(value):
			if _identity_locked or not _workplace_id.is_empty():
				return
			var clean := value.strip_edges()
			if SettlementVillagerDataScript.is_valid_identifier(clean):
				_workplace_id = clean

	var settlement_id: String:
		get:
			return _settlement_id
		set(value):
			if _identity_locked or not _settlement_id.is_empty():
				return
			var clean := value.strip_edges()
			if SettlementVillagerDataScript.is_valid_identifier(clean):
				_settlement_id = clean

	var building_id: String:
		get:
			return _building_id
		set(value):
			if _identity_locked or not _building_id.is_empty():
				return
			var clean := value.strip_edges()
			if SettlementVillagerDataScript.is_valid_identifier(clean):
				_building_id = clean

	var building_type: String = ""
	var origin_cell: Vector2i = Vector2i.ZERO
	var size: Vector2i = Vector2i.ONE
	var access_cell: Vector2i = Vector2i.ZERO
	var output_resource: String = ""
	var buffer_amount: int = 0
	var buffer_capacity: int = 50
	var worker_quota: int = 0
	var is_dropoff: bool = false
	var is_active: bool = true
	var is_paused: bool = false
	var pause_reason: String = ""

	func lock_identity() -> void:
		_identity_locked = true

	func is_identity_locked() -> bool:
		return _identity_locked

	func is_valid_for_settlement(expected_sid: String) -> bool:
		if not SettlementVillagerDataScript.is_valid_identifier(expected_sid):
			return false
		if settlement_id != expected_sid:
			return false
		if not SettlementVillagerDataScript.is_valid_identifier(workplace_id):
			return false
		if not SettlementVillagerDataScript.is_valid_identifier(building_id):
			return false
		if building_type.strip_edges().is_empty():
			return false
		if size.x <= 0 or size.y <= 0:
			return false
		if buffer_capacity < 0 or buffer_amount < 0 or buffer_amount > buffer_capacity:
			return false
		if worker_quota < 0:
			return false
		return true

	func to_dict() -> Dictionary:
		return {
			"workplace_id": workplace_id,
			"settlement_id": settlement_id,
			"building_id": building_id,
			"building_type": building_type,
			"origin_cell": {"x": origin_cell.x, "y": origin_cell.y},
			"size": {"x": size.x, "y": size.y},
			"access_cell": {"x": access_cell.x, "y": access_cell.y},
			"output_resource": output_resource,
			"buffer_amount": buffer_amount,
			"buffer_capacity": buffer_capacity,
			"worker_quota": worker_quota,
			"is_dropoff": is_dropoff,
			"is_active": is_active,
			"is_paused": is_paused,
			"pause_reason": pause_reason
		}

	static func from_dict(data: Variant) -> NpcWorkplaceRecord:
		if not (data is Dictionary):
			return null
		var d: Dictionary = data
		if not (d.get("workplace_id") is String) or not (d.get("settlement_id") is String) or not (d.get("building_type") is String):
			return null
		for str_key in ["building_id", "output_resource"]:
			if d.has(str_key) and not (d[str_key] is String):
				return null
		for vec_key in ["origin_cell", "size", "access_cell"]:
			if d.has(vec_key) and not SettlementVillagerDataScript._is_valid_vec2i_input(d[vec_key]):
				return null
		for num_key in ["buffer_capacity", "buffer_amount", "worker_quota"]:
			if d.has(num_key) and not SettlementVillagerDataScript._is_valid_finite_number(d[num_key]):
				return null
		if d.has("is_dropoff") and not (d["is_dropoff"] is bool):
			return null
		if d.has("is_active") and not (d["is_active"] is bool):
			return null

		var rec := NpcWorkplaceRecord.new()
		rec.workplace_id = String(d["workplace_id"]).strip_edges()
		rec.settlement_id = String(d["settlement_id"]).strip_edges()
		rec.building_id = String(d.get("building_id", rec.workplace_id)).strip_edges()
		rec.building_type = String(d["building_type"]).strip_edges()
		rec.origin_cell = SettlementVillagerDataScript._parse_vec2i(d.get("origin_cell", Vector2i.ZERO), Vector2i.ZERO)
		rec.size = SettlementVillagerDataScript._parse_vec2i(d.get("size", Vector2i.ONE), Vector2i.ONE)
		rec.access_cell = SettlementVillagerDataScript._parse_vec2i(d.get("access_cell", Vector2i.ZERO), Vector2i.ZERO)
		rec.output_resource = String(d.get("output_resource", "")).strip_edges()
		rec.buffer_capacity = int(d.get("buffer_capacity", 50))
		rec.buffer_amount = int(d.get("buffer_amount", 0))
		rec.worker_quota = int(d.get("worker_quota", 0))
		rec.is_dropoff = bool(d.get("is_dropoff", false))
		rec.is_active = bool(d.get("is_active", true))
		rec.is_paused = bool(d.get("is_paused", false))
		rec.pause_reason = String(d.get("pause_reason", ""))
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

var _workplaces_by_id: Dictionary = {}

func _init(p_settlement_id: String = "") -> void:
	_settlement_id = p_settlement_id.strip_edges()

func is_valid() -> bool:
	return SettlementVillagerDataScript.is_valid_identifier(settlement_id)

func register_workplace_record(wp_or_dict: Variant) -> bool:
	if not is_valid():
		return false
	var rec: NpcWorkplaceRecord = null
	if wp_or_dict is NpcWorkplaceRecord:
		rec = wp_or_dict
	elif wp_or_dict is Dictionary:
		rec = NpcWorkplaceRecord.from_dict(wp_or_dict)
	if rec == null or not rec.is_valid_for_settlement(settlement_id):
		return false
	if _workplaces_by_id.has(rec.workplace_id):
		return false
	rec.lock_identity()
	_workplaces_by_id[rec.workplace_id] = rec
	return true

func register_workplace(
	p_workplace_id: String,
	p_building_type: String,
	p_origin_cell: Vector2i = Vector2i.ZERO,
	p_size: Vector2i = Vector2i.ONE,
	p_access_cell: Vector2i = Vector2i.ZERO,
	p_output_resource: String = "",
	p_buffer_capacity: int = 50,
	p_worker_quota: int = 0,
	p_is_dropoff: bool = false,
	p_building_id: String = ""
) -> NpcWorkplaceRecord:
	if not is_valid():
		return null
	var rec := NpcWorkplaceRecord.new()
	rec.workplace_id = p_workplace_id.strip_edges()
	rec.settlement_id = settlement_id
	rec.building_id = p_building_id.strip_edges() if not p_building_id.strip_edges().is_empty() else rec.workplace_id
	rec.building_type = p_building_type.strip_edges()
	rec.origin_cell = p_origin_cell
	rec.size = p_size
	rec.access_cell = p_access_cell
	rec.output_resource = p_output_resource.strip_edges()
	rec.buffer_capacity = p_buffer_capacity
	rec.buffer_amount = 0
	rec.worker_quota = p_worker_quota
	rec.is_dropoff = p_is_dropoff
	if not register_workplace_record(rec):
		return null
	return rec

## Returns the live canonical NpcWorkplaceRecord reference for `workplace_id`, or `null` if absent.
## Mutations to the returned object directly update canonical workplace state in this registry.
func get_workplace(workplace_id: String) -> NpcWorkplaceRecord:
	return _workplaces_by_id.get(workplace_id, null)

func has_workplace(workplace_id: String) -> bool:
	return _workplaces_by_id.has(workplace_id)

func unregister_workplace(workplace_id: String) -> bool:
	if not _workplaces_by_id.has(workplace_id):
		return false
	_workplaces_by_id.erase(workplace_id)
	return true

## Returns a newly allocated Array[NpcWorkplaceRecord] sorted by `workplace_id` containing live
## canonical NpcWorkplaceRecord references. Mutating the returned Array container does not affect
## registry membership; mutating a returned NpcWorkplaceRecord element updates canonical state.
func get_all_workplaces() -> Array[NpcWorkplaceRecord]:
	var keys: Array = _workplaces_by_id.keys()
	keys.sort()
	var out: Array[NpcWorkplaceRecord] = []
	for k in keys:
		out.append(_workplaces_by_id[k])
	return out

func get_workplace_count() -> int:
	return _workplaces_by_id.size()

func clear() -> void:
	_workplaces_by_id.clear()

func to_dict() -> Dictionary:
	var list: Array[Dictionary] = []
	for wp in get_all_workplaces():
		list.append(wp.to_dict())
	return {
		"settlement_id": settlement_id,
		"workplaces": list
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
	if d.has("workplaces") and not (d["workplaces"] is Array):
		return null
	var reg := new(sid)
	var raw_wps: Array = d.get("workplaces", [])
	for item in raw_wps:
		if not reg.register_workplace_record(item):
			return null
	return reg

static func deserialize(data: Variant) -> RefCounted:
	return from_dict(data)
