class_name SettlementSupplyLedger
extends RefCounted
## Settlement-local economic supply and transaction ledger (Architecture v1.0 — Phase 2).
## Owns authoritative provenance, cumulative inflow/outflow totals, and bounded transaction history
## for a single rival settlement. Strictly isolated from player ResourceManager and FactionData.
##
## Accounting Invariant (for every resource and local gold):
##   Current Balance == Initial Balance + Total Inflows - Total Outflows

const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")

const DIR_INITIAL: String = "initial_endowment"
const DIR_INFLOW: String = "inflow"
const DIR_OUTFLOW: String = "outflow"
const DIR_PROVIDER_EVENT: String = "provider_event"

const STATUS_COMMITTED: String = "committed"

const DEFAULT_MAX_HISTORY_ENTRIES: int = 64

var _settlement_id: String = ""
var _identity_locked: bool = false
var _bound_to_economy: bool = false
var _allow_internal_mutation: bool = false

var settlement_id: String:
	get:
		return _settlement_id
	set(value):
		if _identity_locked or not _settlement_id.is_empty():
			return
		var clean := value.strip_edges()
		if SettlementVillagerDataScript.is_valid_identifier(clean):
			_settlement_id = clean

var _max_history_entries: int = DEFAULT_MAX_HISTORY_ENTRIES
var max_history_entries: int:
	get:
		return _max_history_entries
	set(value):
		if not (value is int) or int(value) < 1:
			return
		_max_history_entries = int(value)
		while _recent_entries.size() > _max_history_entries:
			_recent_entries.pop_front()

var _next_tx_seq: int = 1

# Per-resource accounting totals (includes physical resources + "gold")
var _initial_balances: Dictionary = {}
var _initial_provenance: Dictionary = {}
var _total_inflows: Dictionary = {}
var _total_outflows: Dictionary = {}
var _inflows_by_source: Dictionary = {}
var _outflows_by_destination: Dictionary = {}
var _provider_events_by_type: Dictionary = {}
var _recent_entries: Array[Dictionary] = []

func _init(p_settlement_id: String = "", p_max_history: int = DEFAULT_MAX_HISTORY_ENTRIES, p_bound_to_economy: bool = false) -> void:
	_settlement_id = p_settlement_id.strip_edges()
	if not _settlement_id.is_empty() and SettlementVillagerDataScript.is_valid_identifier(_settlement_id):
		_identity_locked = true
	_max_history_entries = maxi(1, p_max_history)
	_bound_to_economy = p_bound_to_economy
	_allow_internal_mutation = false
	_next_tx_seq = 1
	_reset_tables()

func _reset_tables() -> void:
	_initial_balances.clear()
	_initial_provenance.clear()
	_total_inflows.clear()
	_total_outflows.clear()
	_inflows_by_source.clear()
	_outflows_by_destination.clear()
	_provider_events_by_type.clear()
	_recent_entries.clear()
	for res_id in EconomyConfigScript.ALL_RESOURCES:
		_initial_balances[res_id] = 0
		_initial_provenance[res_id] = "uninitialized_zero"
		_total_inflows[res_id] = 0
		_total_outflows[res_id] = 0
		_inflows_by_source[res_id] = {}
		_outflows_by_destination[res_id] = {}

func lock_identity() -> void:
	_identity_locked = true

func bind_to_economy() -> void:
	_bound_to_economy = true
	_allow_internal_mutation = false

func _can_mutate() -> bool:
	return (not _bound_to_economy) or _allow_internal_mutation

func is_valid() -> bool:
	if not SettlementVillagerDataScript.is_valid_identifier(_settlement_id):
		return false
	if _max_history_entries < 1 or _next_tx_seq < 1:
		return false
	return true

static func format_tx_id(sid: String, seq: int) -> String:
	if not SettlementVillagerDataScript.is_valid_identifier(sid) or seq < 1:
		return ""
	return "econ_tx_%s_%d" % [sid, seq]

func get_next_tx_seq() -> int:
	return _next_tx_seq

func get_initial_balance(res_id: String) -> int:
	return int(_initial_balances.get(res_id, 0))

func get_initial_provenance(res_id: String) -> String:
	return String(_initial_provenance.get(res_id, ""))

func get_total_inflow(res_id: String) -> int:
	return int(_total_inflows.get(res_id, 0))

func get_total_outflow(res_id: String) -> int:
	return int(_total_outflows.get(res_id, 0))

func get_expected_balance(res_id: String) -> int:
	if not _initial_balances.has(res_id):
		return 0
	return int(_initial_balances[res_id]) + int(_total_inflows.get(res_id, 0)) - int(_total_outflows.get(res_id, 0))

func get_inflows_by_source(res_id: String) -> Dictionary:
	if not _inflows_by_source.has(res_id):
		return {}
	return (_inflows_by_source[res_id] as Dictionary).duplicate(true)

func get_outflows_by_destination(res_id: String) -> Dictionary:
	if not _outflows_by_destination.has(res_id):
		return {}
	return (_outflows_by_destination[res_id] as Dictionary).duplicate(true)

func get_provider_event_totals() -> Dictionary:
	return _provider_events_by_type.duplicate(true)

func get_recent_entries() -> Array[Dictionary]:
	var copy: Array[Dictionary] = []
	for entry in _recent_entries:
		copy.append(entry.duplicate(true))
	return copy

func get_recent_entry_count() -> int:
	return _recent_entries.size()

func verify_balance_consistency(live_stock: Dictionary, live_gold: int) -> bool:
	if not is_valid():
		return false
	for res_id in EconomyConfigScript.ALL_RESOURCES:
		var actual: int = live_gold if res_id == EconomyConfigScript.RES_GOLD else int(live_stock.get(res_id, 0))
		if actual != get_expected_balance(res_id):
			return false
	return true

func record_initial_endowment(
	res_id: String,
	amount: int,
	source: String,
	destination: String,
	hour_seq: int = 0
) -> Dictionary:
	if not _can_mutate() or not is_valid() or not _initial_balances.has(res_id):
		return {}
	var clean_src := source.strip_edges()
	var clean_dst := destination.strip_edges()
	if amount < 0 or clean_src.is_empty() or clean_dst.is_empty() or hour_seq < 0:
		return {}
	# Initial endowment may only be recorded once per resource when no prior endowment, inflows, or outflows exist
	if int(_initial_balances.get(res_id, 0)) != 0 or String(_initial_provenance.get(res_id, "uninitialized_zero")) != "uninitialized_zero":
		return {}
	if int(_total_inflows.get(res_id, 0)) != 0 or int(_total_outflows.get(res_id, 0)) != 0:
		return {}
	_initial_balances[res_id] = amount
	_initial_provenance[res_id] = clean_src
	return _append_committed_entry(
		res_id,
		amount,
		DIR_INITIAL,
		clean_src,
		clean_dst,
		"initial_endowment",
		hour_seq,
		amount
	)

func record_inflow(
	res_id: String,
	amount: int,
	source: String,
	destination: String,
	reason: String,
	hour_seq: int,
	balance_after: int
) -> Dictionary:
	if not _can_mutate() or not is_valid() or not _initial_balances.has(res_id):
		return {}
	var clean_src := source.strip_edges()
	var clean_dst := destination.strip_edges()
	var clean_reason := reason.strip_edges()
	if amount <= 0 or clean_src.is_empty() or clean_dst.is_empty() or clean_reason.is_empty() or hour_seq < 0:
		return {}
	_total_inflows[res_id] = int(_total_inflows.get(res_id, 0)) + amount
	var src_map: Dictionary = _inflows_by_source[res_id]
	src_map[clean_src] = int(src_map.get(clean_src, 0)) + amount
	return _append_committed_entry(
		res_id,
		amount,
		DIR_INFLOW,
		clean_src,
		clean_dst,
		clean_reason,
		hour_seq,
		balance_after
	)

func record_outflow(
	res_id: String,
	amount: int,
	source: String,
	destination: String,
	reason: String,
	hour_seq: int,
	balance_after: int
) -> Dictionary:
	if not _can_mutate() or not is_valid() or not _initial_balances.has(res_id):
		return {}
	var clean_src := source.strip_edges()
	var clean_dst := destination.strip_edges()
	var clean_reason := reason.strip_edges()
	if amount <= 0 or clean_src.is_empty() or clean_dst.is_empty() or clean_reason.is_empty() or hour_seq < 0:
		return {}
	_total_outflows[res_id] = int(_total_outflows.get(res_id, 0)) + amount
	var dst_map: Dictionary = _outflows_by_destination[res_id]
	dst_map[clean_dst] = int(dst_map.get(clean_dst, 0)) + amount
	return _append_committed_entry(
		res_id,
		amount,
		DIR_OUTFLOW,
		clean_src,
		clean_dst,
		clean_reason,
		hour_seq,
		balance_after
	)

## Records a provider-internal supply event (such as external market restock into the market pool
## or external top-up of off-map logistics allocation) that has explicit provenance without
## directly changing the settlement's own stock balance.
func record_provider_event(
	res_id: String,
	amount: int,
	source: String,
	destination: String,
	reason: String,
	hour_seq: int,
	provider_balance_after: int
) -> Dictionary:
	if not _can_mutate() or not is_valid() or not _initial_balances.has(res_id):
		return {}
	var clean_src := source.strip_edges()
	var clean_dst := destination.strip_edges()
	var clean_reason := reason.strip_edges()
	if amount <= 0 or clean_src.is_empty() or clean_dst.is_empty() or clean_reason.is_empty() or hour_seq < 0:
		return {}
	_provider_events_by_type[clean_reason] = int(_provider_events_by_type.get(clean_reason, 0)) + amount
	return _append_committed_entry(
		res_id,
		amount,
		DIR_PROVIDER_EVENT,
		clean_src,
		clean_dst,
		clean_reason,
		hour_seq,
		provider_balance_after
	)

func _append_committed_entry(
	res_id: String,
	amount: int,
	direction: String,
	source: String,
	destination: String,
	reason: String,
	hour_seq: int,
	balance_after: int
) -> Dictionary:
	var seq: int = _next_tx_seq
	var tx_id: String = format_tx_id(_settlement_id, seq)
	_next_tx_seq += 1
	var entry: Dictionary = {
		"tx_id": tx_id,
		"tx_seq": seq,
		"settlement_id": _settlement_id,
		"resource_id": res_id,
		"amount": amount,
		"direction": direction,
		"source": source,
		"destination": destination,
		"reason": reason,
		"hour_seq": hour_seq,
		"status": STATUS_COMMITTED,
		"balance_after": balance_after
	}
	_recent_entries.append(entry)
	while _recent_entries.size() > max_history_entries:
		_recent_entries.pop_front()
	return entry.duplicate(true)

func to_dict() -> Dictionary:
	return {
		"settlement_id": _settlement_id,
		"max_history_entries": max_history_entries,
		"next_tx_seq": _next_tx_seq,
		"initial_balances": _initial_balances.duplicate(true),
		"initial_provenance": _initial_provenance.duplicate(true),
		"total_inflows": _total_inflows.duplicate(true),
		"total_outflows": _total_outflows.duplicate(true),
		"inflows_by_source": _inflows_by_source.duplicate(true),
		"outflows_by_destination": _outflows_by_destination.duplicate(true),
		"provider_events_by_type": _provider_events_by_type.duplicate(true),
		"recent_entries": get_recent_entries()
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

	var max_hist: int = DEFAULT_MAX_HISTORY_ENTRIES
	if d.has("max_history_entries"):
		if not SettlementVillagerDataScript._is_valid_finite_number(d["max_history_entries"]) or int(d["max_history_entries"]) < 1:
			return null
		max_hist = int(d["max_history_entries"])

	var next_seq: int = 1
	if d.has("next_tx_seq"):
		if not SettlementVillagerDataScript._is_valid_finite_number(d["next_tx_seq"]) or int(d["next_tx_seq"]) < 1:
			return null
		next_seq = int(d["next_tx_seq"])

	for dict_key in [
		"initial_balances",
		"initial_provenance",
		"total_inflows",
		"total_outflows",
		"inflows_by_source",
		"outflows_by_destination",
		"provider_events_by_type"
	]:
		if d.has(dict_key) and not (d[dict_key] is Dictionary):
			return null

	if d.has("recent_entries") and not (d["recent_entries"] is Array):
		return null

	var ledger := new(sid, max_hist)
	ledger._next_tx_seq = next_seq

	if d.has("initial_balances"):
		var ib: Dictionary = d["initial_balances"]
		for k in ib.keys():
			var k_str := String(k)
			if not ledger._initial_balances.has(k_str):
				return null
			if not SettlementVillagerDataScript._is_valid_finite_number(ib[k]) or int(ib[k]) < 0:
				return null
			ledger._initial_balances[k_str] = int(ib[k])

	if d.has("initial_provenance"):
		var ip: Dictionary = d["initial_provenance"]
		for k in ip.keys():
			var k_str := String(k)
			if not ledger._initial_provenance.has(k_str) or not (ip[k] is String):
				return null
			var prov := String(ip[k]).strip_edges()
			if prov.is_empty():
				return null
			ledger._initial_provenance[k_str] = prov

	if d.has("total_inflows"):
		var ti: Dictionary = d["total_inflows"]
		for k in ti.keys():
			var k_str := String(k)
			if not ledger._total_inflows.has(k_str):
				return null
			if not SettlementVillagerDataScript._is_valid_finite_number(ti[k]) or int(ti[k]) < 0:
				return null
			ledger._total_inflows[k_str] = int(ti[k])

	if d.has("total_outflows"):
		var to_map: Dictionary = d["total_outflows"]
		for k in to_map.keys():
			var k_str := String(k)
			if not ledger._total_outflows.has(k_str):
				return null
			if not SettlementVillagerDataScript._is_valid_finite_number(to_map[k]) or int(to_map[k]) < 0:
				return null
			ledger._total_outflows[k_str] = int(to_map[k])

	for res_id in EconomyConfigScript.ALL_RESOURCES:
		if ledger.get_expected_balance(res_id) < 0:
			return null

	if d.has("inflows_by_source"):
		var ibs: Dictionary = d["inflows_by_source"]
		for res_k in ibs.keys():
			var res_str := String(res_k)
			if not ledger._inflows_by_source.has(res_str) or not (ibs[res_k] is Dictionary):
				return null
			var inner: Dictionary = ibs[res_k]
			var clean_inner: Dictionary = {}
			var sum_in: int = 0
			for src_k in inner.keys():
				if not (src_k is String) or String(src_k).strip_edges().is_empty():
					return null
				if not SettlementVillagerDataScript._is_valid_finite_number(inner[src_k]) or int(inner[src_k]) < 0:
					return null
				var v_in: int = int(inner[src_k])
				clean_inner[String(src_k).strip_edges()] = v_in
				sum_in += v_in
			if sum_in != int(ledger._total_inflows[res_str]):
				return null
			ledger._inflows_by_source[res_str] = clean_inner

	if d.has("outflows_by_destination"):
		var obd: Dictionary = d["outflows_by_destination"]
		for res_k in obd.keys():
			var res_str := String(res_k)
			if not ledger._outflows_by_destination.has(res_str) or not (obd[res_k] is Dictionary):
				return null
			var inner_out: Dictionary = obd[res_k]
			var clean_inner_out: Dictionary = {}
			var sum_out: int = 0
			for dst_k in inner_out.keys():
				if not (dst_k is String) or String(dst_k).strip_edges().is_empty():
					return null
				if not SettlementVillagerDataScript._is_valid_finite_number(inner_out[dst_k]) or int(inner_out[dst_k]) < 0:
					return null
				var v_out: int = int(inner_out[dst_k])
				clean_inner_out[String(dst_k).strip_edges()] = v_out
				sum_out += v_out
			if sum_out != int(ledger._total_outflows[res_str]):
				return null
			ledger._outflows_by_destination[res_str] = clean_inner_out

	if d.has("provider_events_by_type"):
		var pev: Dictionary = d["provider_events_by_type"]
		for k in pev.keys():
			if not (k is String) or String(k).strip_edges().is_empty():
				return null
			if not SettlementVillagerDataScript._is_valid_finite_number(pev[k]) or int(pev[k]) < 0:
				return null
			ledger._provider_events_by_type[String(k).strip_edges()] = int(pev[k])

	if d.has("recent_entries"):
		var raw_entries: Array = d["recent_entries"]
		if raw_entries.size() > max_hist:
			return null
		for item in raw_entries:
			if not (item is Dictionary):
				return null
			var entry_d: Dictionary = item
			if String(entry_d.get("settlement_id", "")) != sid:
				return null
			if not (entry_d.get("tx_id") is String) or String(entry_d["tx_id"]).strip_edges().is_empty():
				return null
			if not SettlementVillagerDataScript._is_valid_finite_number(entry_d.get("tx_seq", -1)) or int(entry_d["tx_seq"]) < 1:
				return null
			if not SettlementVillagerDataScript._is_valid_finite_number(entry_d.get("amount", -1)) or int(entry_d["amount"]) < 0:
				return null
			if not SettlementVillagerDataScript._is_valid_finite_number(entry_d.get("hour_seq", -1)) or int(entry_d["hour_seq"]) < 0:
				return null
			if not SettlementVillagerDataScript._is_valid_finite_number(entry_d.get("balance_after", -1)) or int(entry_d["balance_after"]) < 0:
				return null
			var t_seq: int = int(entry_d["tx_seq"])
			if t_seq >= ledger._next_tx_seq:
				ledger._next_tx_seq = t_seq + 1
			ledger._recent_entries.append(entry_d.duplicate(true))

	ledger.lock_identity()
	return ledger

static func deserialize(data: Variant) -> RefCounted:
	return from_dict(data)
