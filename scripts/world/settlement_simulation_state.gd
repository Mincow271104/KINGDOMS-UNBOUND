class_name SettlementSimulationState
extends RefCounted
## Context-owned Phase 4 simulation state (queue markers, daily watermarks, survival, production sources,
## in-transit accounting and transfer idempotency markers). Pure data; fully serializable.
## Canonical villager/economy/job/workplace state stays in the accepted Phase 1-3 models.

const SURVIVAL_NORMAL: String = "normal"
const SURVIVAL_SURVIVAL: String = "survival"
const SURVIVAL_AWAITING_RESUPPLY: String = "awaiting_resupply"
const SURVIVAL_RECOVERY: String = "recovery"
const VALID_SURVIVAL_STATES: Array[String] = [
	SURVIVAL_NORMAL, SURVIVAL_SURVIVAL, SURVIVAL_AWAITING_RESUPPLY, SURVIVAL_RECOVERY
]

var initialized: bool = false
var required_hour_seq: int = 0
var settled_hour_seq: int = 0
var latest_captured_daily_seq: int = -1
var completed_daily_seq: int = -1
var last_immigration_daily_seq: int = -1
var total_immigrants_admitted: int = 0
var initial_population_seeded: bool = false
var initial_seed_hour_seq: int = -1
var pending_daily: Array = []
var villager_daily_seq: Dictionary = {}
var registered: Dictionary = {}
var survival_state: String = SURVIVAL_NORMAL
var ration_shortfall: bool = false
var recovery_hours_left: int = 0
var production_sources: Dictionary = {}
var production_blocked: Dictionary = {}
var transit_in: Dictionary = {}
var transit_out: Dictionary = {}
var transit_baseline: Dictionary = {}
var baseline_captured: bool = false
var processed_transfers: Dictionary = {}
var recent_errors: Array = []
var stats: Dictionary = {
	"hours_processed": 0,
	"daily_processed": 0,
	"pickups": 0,
	"deposits": 0,
	"produced": 0,
	"immigrants_admitted": 0
}

static func _is_int(val: Variant) -> bool:
	if val is bool:
		return false
	if val is int:
		return true
	if val is float:
		var f: float = float(val)
		return not (is_nan(f) or is_inf(f)) and is_equal_approx(f, roundf(f))
	return false

func add_transit(dict_name: String, res_id: String, amount: int) -> void:
	var d: Dictionary = transit_in if dict_name == "in" else transit_out
	d[res_id] = int(d.get(res_id, 0)) + amount

func mark_transfer(transfer_id: String) -> bool:
	if processed_transfers.has(transfer_id):
		return false
	processed_transfers[transfer_id] = true
	while processed_transfers.size() > 256:
		processed_transfers.erase(processed_transfers.keys()[0])
	return true

func unmark_transfer(transfer_id: String) -> void:
	processed_transfers.erase(transfer_id)

func record_error(message: String) -> void:
	recent_errors.append(message)
	while recent_errors.size() > 8:
		recent_errors.pop_front()

func _serialize_production_sources() -> Dictionary:
	var out: Dictionary = {}
	for k in production_sources.keys():
		var src: Dictionary = (production_sources[k] as Dictionary).duplicate(true)
		if src.has("trees") and src["trees"] is Array:
			var norm_trees: Array = []
			for t in src["trees"]:
				if t is Dictionary:
					var tc: Dictionary = (t as Dictionary).duplicate(true)
					tc.erase("felled")
					if tc.get("cell") is Vector2i:
						var c: Vector2i = tc["cell"]
						tc["cell"] = {"x": c.x, "y": c.y}
					norm_trees.append(tc)
			src["trees"] = norm_trees
		out[String(k)] = src
	return out

func to_dict() -> Dictionary:
	return {
		"initialized": initialized,
		"required_hour_seq": required_hour_seq,
		"settled_hour_seq": settled_hour_seq,
		"latest_captured_daily_seq": latest_captured_daily_seq,
		"completed_daily_seq": completed_daily_seq,
		"last_immigration_daily_seq": last_immigration_daily_seq,
		"total_immigrants_admitted": total_immigrants_admitted,
		"initial_population_seeded": initial_population_seeded,
		"initial_seed_hour_seq": initial_seed_hour_seq,
		"pending_daily": pending_daily.duplicate(),
		"villager_daily_seq": villager_daily_seq.duplicate(true),
		"registered": registered.duplicate(true),
		"survival_state": survival_state,
		"ration_shortfall": ration_shortfall,
		"recovery_hours_left": recovery_hours_left,
		"production_sources": _serialize_production_sources(),
		"production_blocked": production_blocked.duplicate(true),
		"transit_in": transit_in.duplicate(true),
		"transit_out": transit_out.duplicate(true),
		"transit_baseline": transit_baseline.duplicate(true),
		"baseline_captured": baseline_captured,
		"processed_transfers": processed_transfers.keys(),
		"recent_errors": recent_errors.duplicate(),
		"stats": stats.duplicate(true)
	}

static func from_dict(data: Variant) -> RefCounted:
	if not (data is Dictionary):
		return null
	var d: Dictionary = data
	var st: RefCounted = (load("res://scripts/world/settlement_simulation_state.gd") as GDScript).new()
	for k in ["required_hour_seq", "settled_hour_seq", "latest_captured_daily_seq", "completed_daily_seq", "last_immigration_daily_seq", "total_immigrants_admitted", "initial_seed_hour_seq", "recovery_hours_left"]:
		if d.has(k) and not _is_int(d[k]):
			return null
	if d.has("survival_state") and (not (d["survival_state"] is String) or not VALID_SURVIVAL_STATES.has(String(d["survival_state"]))):
		return null
	for k in ["initialized", "ration_shortfall", "baseline_captured", "initial_population_seeded"]:
		if d.has(k) and not (d[k] is bool):
			return null
	for k in ["villager_daily_seq", "registered", "production_sources", "production_blocked", "transit_in", "transit_out", "transit_baseline", "stats"]:
		if d.has(k) and not (d[k] is Dictionary):
			return null
	for k in ["pending_daily", "processed_transfers", "recent_errors"]:
		if d.has(k) and not (d[k] is Array):
			return null
	st.initialized = bool(d.get("initialized", false))
	st.required_hour_seq = int(d.get("required_hour_seq", 0))
	st.settled_hour_seq = int(d.get("settled_hour_seq", 0))
	if st.required_hour_seq < 0 or st.settled_hour_seq < 0 or st.settled_hour_seq > st.required_hour_seq:
		return null
	st.latest_captured_daily_seq = int(d.get("latest_captured_daily_seq", -1))
	st.completed_daily_seq = int(d.get("completed_daily_seq", -1))
	st.last_immigration_daily_seq = int(d.get("last_immigration_daily_seq", -1))
	st.total_immigrants_admitted = maxi(0, int(d.get("total_immigrants_admitted", 0)))
	st.initial_population_seeded = bool(d.get("initial_population_seeded", false))
	st.initial_seed_hour_seq = int(d.get("initial_seed_hour_seq", -1))
	for s in d.get("pending_daily", []):
		if not _is_int(s):
			return null
		st.pending_daily.append(int(s))
	st.pending_daily.sort()
	for k in (d.get("villager_daily_seq", {}) as Dictionary).keys():
		if not _is_int(d["villager_daily_seq"][k]):
			return null
		st.villager_daily_seq[String(k)] = int(d["villager_daily_seq"][k])
	for k in (d.get("registered", {}) as Dictionary).keys():
		if not _is_int(d["registered"][k]):
			return null
		st.registered[String(k)] = int(d["registered"][k])
	st.survival_state = String(d.get("survival_state", SURVIVAL_NORMAL))
	st.ration_shortfall = bool(d.get("ration_shortfall", false))
	st.recovery_hours_left = maxi(0, int(d.get("recovery_hours_left", 0)))
	for k in (d.get("production_sources", {}) as Dictionary).keys():
		var src_raw: Variant = d["production_sources"][k]
		if not (src_raw is Dictionary):
			return null
		var src: Dictionary = (src_raw as Dictionary).duplicate(true)
		if not _is_int(src.get("remaining", 0)) or int(src.get("remaining", 0)) < 0:
			return null
		if src.has("work_credit_milli"):
			if not _is_int(src["work_credit_milli"]) or int(src["work_credit_milli"]) < 0:
				return null
			src["work_credit_milli"] = int(src["work_credit_milli"])
		if src.has("trees"):
			if not (src["trees"] is Array):
				return null
			var restored_trees: Array = []
			for t in src["trees"]:
				if not (t is Dictionary):
					return null
				var tc: Dictionary = (t as Dictionary).duplicate(true)
				if tc.has("cell"):
					var raw_c: Variant = tc["cell"]
					if raw_c is Vector2i:
						pass
					elif raw_c is Dictionary and _is_int(raw_c.get("x", null)) and _is_int(raw_c.get("y", null)):
						tc["cell"] = Vector2i(int(raw_c["x"]), int(raw_c["y"]))
					else:
						return null
				if tc.has("remaining_milli"):
					if not _is_int(tc["remaining_milli"]) or int(tc["remaining_milli"]) < 0:
						return null
					var rem_m: int = int(tc["remaining_milli"])
					if rem_m != 0 and rem_m != 5000:
						return null
					tc["remaining_milli"] = rem_m

				if tc.has("felled"):
					if not (tc["felled"] is bool):
						return null
					var is_felled_legacy: bool = bool(tc["felled"])
					if tc.has("remaining_milli"):
						var rem_check: int = int(tc["remaining_milli"])
						if is_felled_legacy and rem_check > 0:
							return null
						if not is_felled_legacy and rem_check == 0:
							return null
					else:
						tc["remaining_milli"] = 0 if is_felled_legacy else 5000
					tc.erase("felled")
				elif not tc.has("remaining_milli"):
					return null
				restored_trees.append(tc)
			src["trees"] = restored_trees
		st.production_sources[String(k)] = src
	st.production_blocked = (d.get("production_blocked", {}) as Dictionary).duplicate(true)
	for dn in ["transit_in", "transit_out", "transit_baseline"]:
		for k in (d.get(dn, {}) as Dictionary).keys():
			if not _is_int(d[dn][k]) or int(d[dn][k]) < 0:
				return null
			(st.get(dn) as Dictionary)[String(k)] = int(d[dn][k])
	st.baseline_captured = bool(d.get("baseline_captured", false))
	for t in d.get("processed_transfers", []):
		if t is String:
			st.processed_transfers[String(t)] = true
	for e in d.get("recent_errors", []):
		st.recent_errors.append(str(e))
	var raw_stats: Dictionary = d.get("stats", {})
	for k in st.stats.keys():
		if raw_stats.has(k) and _is_int(raw_stats[k]):
			st.stats[k] = int(raw_stats[k])
	return st
