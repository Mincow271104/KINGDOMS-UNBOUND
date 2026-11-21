class_name SettlementVillagerData
extends RefCounted
## Canonical data-first state model for a single Rival Settlement NPC villager (Architecture v1.0 — Phase 1).
## Strictly isolated from player CitizenController, SceneTree Nodes, and /root/ResourceManager.
## Future RivalVillagerActor instances are presentation projections only; this class is the sole authority.

const LIFE_ALIVE: String = "alive"
const LIFE_DEAD: String = "dead"
const LIFE_REMOVED: String = "removed"

const VALID_LIFE_STATES: Array[String] = [
	LIFE_ALIVE,
	LIFE_DEAD,
	LIFE_REMOVED
]

const ROLE_IDLE: String = "idle"
const ROLE_FARMER: String = "farmer"
const ROLE_WOODCUTTER: String = "woodcutter"
const ROLE_SMITH: String = "smith"
const ROLE_HAULER: String = "hauler"
const ROLE_GUARD: String = "guard"
const ROLE_HUNTER: String = "hunter"

const VALID_ROLES: Array[String] = [
	ROLE_IDLE,
	ROLE_FARMER,
	ROLE_WOODCUTTER,
	ROLE_SMITH,
	ROLE_HAULER,
	ROLE_GUARD,
	ROLE_HUNTER
]

const TASK_IDLE: String = "idle"
const TASK_MOVING_TO_JOB: String = "moving_to_job"
const TASK_WORKING: String = "working"
const TASK_HAULING: String = "hauling"
const TASK_SEEKING_FOOD: String = "seeking_food"
const TASK_RESTING: String = "resting"
const TASK_GUARDING: String = "guarding"

const VALID_TASK_STATES: Array[String] = [
	TASK_IDLE,
	TASK_MOVING_TO_JOB,
	TASK_WORKING,
	TASK_HAULING,
	TASK_SEEKING_FOOD,
	TASK_RESTING,
	TASK_GUARDING
]

const REST_NONE: String = "none"
const REST_RETURNING_HOME: String = "returning_home"
const REST_RESTING_INSIDE: String = "resting_inside"

const VALID_REST_PHASES: Array[String] = [
	REST_NONE,
	REST_RETURNING_HOME,
	REST_RESTING_INSIDE
]

# --- Identity & Affiliation ---
# Immutable once initialized/registered: villager_id, settlement_id, origin_faction_id.
# Mutable affiliation fields (validated identifiers only): home_settlement_id, current_faction_id.
var _villager_id: String = ""
var _settlement_id: String = ""
var _home_settlement_id: String = ""
var _origin_faction_id: String = ""
var _current_faction_id: String = ""
var _identity_locked: bool = false

var villager_id: String:
	get:
		return _villager_id
	set(value):
		if _identity_locked or not _villager_id.is_empty():
			return
		var clean := value.strip_edges()
		if is_valid_identifier(clean):
			_villager_id = clean

var villager_name: String = ""

var settlement_id: String:
	get:
		return _settlement_id
	set(value):
		if _identity_locked or not _settlement_id.is_empty():
			return
		var clean := value.strip_edges()
		if is_valid_identifier(clean):
			_settlement_id = clean

var home_settlement_id: String:
	get:
		return _home_settlement_id
	set(value):
		var clean := value.strip_edges()
		if is_valid_identifier(clean):
			_home_settlement_id = clean

var origin_faction_id: String:
	get:
		return _origin_faction_id
	set(value):
		if _identity_locked or not _origin_faction_id.is_empty():
			return
		var clean := value.strip_edges()
		if is_valid_identifier(clean):
			_origin_faction_id = clean

var current_faction_id: String:
	get:
		return _current_faction_id
	set(value):
		var clean := value.strip_edges()
		if is_valid_identifier(clean):
			_current_faction_id = clean

# --- Simulation Lifecycle & Needs ---
var life_state: String = LIFE_ALIVE
var role: String = ROLE_IDLE
var task_state: String = TASK_IDLE
var rest_phase: String = REST_NONE
var cell: Vector2i = Vector2i.ZERO

var hunger: float = 10.0
var fatigue: float = 10.0
var health: float = 100.0
var morale: float = 70.0

# --- Assignments & Work Progress ---
var home_building_id: String = ""
var workplace_id: String = ""
var active_job_id: String = ""
var work_target_id: String = ""
var work_hours_done: float = 0.0

# --- Deterministic Simulation Sequence ---
var last_processed_hour_seq: int = 0
var admission_hour_seq: int = -1

# --- Per-Instance Owned Mutable Containers (Never Shared Across Instances) ---
var cargo: Dictionary = {}
var skills: Dictionary = {}

func _init(
	p_villager_id: String = "",
	p_settlement_id: String = "",
	p_origin_faction_id: String = "",
	p_name: String = "",
	p_role: String = ROLE_IDLE,
	p_cell: Vector2i = Vector2i.ZERO
) -> void:
	_villager_id = p_villager_id.strip_edges()
	_settlement_id = p_settlement_id.strip_edges()
	_home_settlement_id = _settlement_id
	_origin_faction_id = p_origin_faction_id.strip_edges()
	_current_faction_id = _origin_faction_id
	villager_name = p_name.strip_edges() if not p_name.strip_edges().is_empty() else _villager_id
	role = p_role if VALID_ROLES.has(p_role) else ROLE_IDLE
	cell = p_cell
	cargo = _make_default_cargo()
	skills = _make_default_skills()
	if not _villager_id.is_empty() and not _settlement_id.is_empty() and not _origin_faction_id.is_empty():
		_identity_locked = true

func lock_identity() -> void:
	_identity_locked = true

func is_identity_locked() -> bool:
	return _identity_locked

static func _make_default_cargo() -> Dictionary:
	return {
		"resource": "",
		"amount": 0,
		"source_workplace_id": "",
		"dest_cell": Vector2i(-1, -1)
	}

static func _make_default_skills() -> Dictionary:
	return {
		"farming": 0.0,
		"woodcutting": 0.0,
		"mining": 0.0,
		"smithing": 0.0,
		"building": 0.0,
		"hauling": 0.0,
		"hunting": 0.0
	}

static func is_valid_identifier(id_str: String) -> bool:
	if id_str.is_empty() or id_str != id_str.strip_edges():
		return false
	for i in range(id_str.length()):
		var code: int = id_str.unicode_at(i)
		var is_alnum: bool = (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
		var is_sep: bool = (code == 95 or code == 45) # '_' or '-'
		if not is_alnum and not is_sep:
			return false
	return true

static func parse_villager_sequence_for_settlement(p_villager_id: String, p_settlement_id: String) -> int:
	if not is_valid_identifier(p_villager_id) or not is_valid_identifier(p_settlement_id):
		return -1
	var prefix: String = "npc_%s_" % p_settlement_id
	if not p_villager_id.begins_with(prefix):
		return -1
	var suffix: String = p_villager_id.substr(prefix.length())
	if suffix.is_empty() or suffix.begins_with("0") or not suffix.is_valid_int():
		return -1
	for i in range(suffix.length()):
		var c: int = suffix.unicode_at(i)
		if c < 48 or c > 57:
			return -1
	var seq: int = int(suffix)
	return seq if seq >= 1 else -1

func is_valid() -> bool:
	if not is_valid_identifier(villager_id):
		return false
	if not is_valid_identifier(settlement_id):
		return false
	if not is_valid_identifier(home_settlement_id):
		return false
	if not is_valid_identifier(origin_faction_id):
		return false
	if not is_valid_identifier(current_faction_id):
		return false
	if parse_villager_sequence_for_settlement(villager_id, settlement_id) < 1:
		return false
	if not VALID_LIFE_STATES.has(life_state):
		return false
	if not VALID_ROLES.has(role):
		return false
	if not VALID_TASK_STATES.has(task_state):
		return false
	if not VALID_REST_PHASES.has(rest_phase):
		return false
	if is_nan(hunger) or is_inf(hunger) or hunger < 0.0 or hunger > 100.0:
		return false
	if is_nan(fatigue) or is_inf(fatigue) or fatigue < 0.0 or fatigue > 100.0:
		return false
	if is_nan(health) or is_inf(health) or health < 0.0 or health > 100.0:
		return false
	if is_nan(morale) or is_inf(morale) or morale < 0.0 or morale > 100.0:
		return false
	if is_nan(work_hours_done) or is_inf(work_hours_done) or work_hours_done < 0.0:
		return false
	if last_processed_hour_seq < 0:
		return false
	if admission_hour_seq < -1:
		return false
	return true

func set_cargo(res_id: String, amount: int, source_wp_id: String = "", dest: Vector2i = Vector2i(-1, -1)) -> void:
	if amount <= 0 or res_id.strip_edges().is_empty():
		clear_cargo()
		return
	cargo = {
		"resource": res_id.strip_edges(),
		"amount": maxi(0, amount),
		"source_workplace_id": source_wp_id.strip_edges(),
		"dest_cell": dest
	}

func clear_cargo() -> void:
	cargo = _make_default_cargo()

func get_carrying_resource() -> String:
	return str(cargo.get("resource", ""))

func get_carrying_amount() -> int:
	return maxi(0, int(cargo.get("amount", 0)))

static func _is_valid_finite_number(val: Variant) -> bool:
	if not (val is int or val is float):
		return false
	var f: float = float(val)
	return not (is_nan(f) or is_inf(f))

static func _is_valid_vec2i_input(val: Variant) -> bool:
	if val is Vector2i:
		return true
	if val is Dictionary:
		return val.has("x") and val.has("y") and _is_valid_finite_number(val["x"]) and _is_valid_finite_number(val["y"])
	if val is Array and val.size() >= 2:
		return _is_valid_finite_number(val[0]) and _is_valid_finite_number(val[1])
	return false

static func _parse_vec2i(val: Variant, fallback: Vector2i = Vector2i.ZERO) -> Vector2i:
	if val is Vector2i:
		return val
	if val is Dictionary and _is_valid_vec2i_input(val):
		return Vector2i(int(val["x"]), int(val["y"]))
	if val is Array and _is_valid_vec2i_input(val):
		return Vector2i(int(val[0]), int(val[1]))
	return fallback

func to_dict() -> Dictionary:
	var dest_c: Vector2i = _parse_vec2i(cargo.get("dest_cell", Vector2i(-1, -1)), Vector2i(-1, -1))
	var skills_out: Dictionary = _make_default_skills()
	for k in skills.keys():
		var k_str := str(k)
		if skills_out.has(k_str):
			var v = skills[k]
			if _is_valid_finite_number(v):
				skills_out[k_str] = clampf(float(v), 0.0, 1000.0)

	return {
		"villager_id": villager_id,
		"name": villager_name,
		"settlement_id": settlement_id,
		"home_settlement_id": home_settlement_id,
		"origin_faction_id": origin_faction_id,
		"current_faction_id": current_faction_id,
		"life_state": life_state,
		"role": role,
		"task_state": task_state,
		"rest_phase": rest_phase,
		"cell": {"x": cell.x, "y": cell.y},
		"hunger": hunger,
		"fatigue": fatigue,
		"health": health,
		"morale": morale,
		"home_building_id": home_building_id,
		"workplace_id": workplace_id,
		"active_job_id": active_job_id,
		"work_target_id": work_target_id,
		"work_hours_done": work_hours_done,
		"last_processed_hour_seq": last_processed_hour_seq,
		"admission_hour_seq": admission_hour_seq,
		"cargo": {
			"resource": str(cargo.get("resource", "")),
			"amount": maxi(0, int(cargo.get("amount", 0))),
			"source_workplace_id": str(cargo.get("source_workplace_id", "")),
			"dest_cell": {"x": dest_c.x, "y": dest_c.y}
		},
		"skills": skills_out
	}

func serialize() -> Dictionary:
	return to_dict()

static func from_dict(data: Variant) -> RefCounted:
	if not (data is Dictionary):
		return null
	var d: Dictionary = data
	if not (d.get("villager_id") is String) or not (d.get("settlement_id") is String) or not (d.get("origin_faction_id") is String):
		return null

	var vid: String = String(d["villager_id"]).strip_edges()
	var sid: String = String(d["settlement_id"]).strip_edges()
	var orig_fid: String = String(d["origin_faction_id"]).strip_edges()

	if d.has("home_settlement_id") and not (d["home_settlement_id"] is String):
		return null
	var home_sid: String = String(d.get("home_settlement_id", sid)).strip_edges()
	if home_sid.is_empty():
		home_sid = sid

	if d.has("current_faction_id") and not (d["current_faction_id"] is String):
		return null
	var cur_fid: String = String(d.get("current_faction_id", orig_fid)).strip_edges()
	if cur_fid.is_empty():
		cur_fid = orig_fid

	if d.has("name") and not (d["name"] is String):
		return null
	if d.has("role") and not (d["role"] is String):
		return null
	if d.has("life_state") and not (d["life_state"] is String):
		return null
	if d.has("task_state") and not (d["task_state"] is String):
		return null
	if d.has("rest_phase") and not (d["rest_phase"] is String):
		return null
	if d.has("cell") and not _is_valid_vec2i_input(d["cell"]):
		return null

	if not is_valid_identifier(vid) or not is_valid_identifier(sid) or not is_valid_identifier(home_sid):
		return null
	if not is_valid_identifier(orig_fid) or not is_valid_identifier(cur_fid):
		return null
	if parse_villager_sequence_for_settlement(vid, sid) < 1:
		return null

	var raw_role: String = String(d.get("role", ROLE_IDLE)).strip_edges()
	if not VALID_ROLES.has(raw_role):
		return null
	var raw_life: String = String(d.get("life_state", LIFE_ALIVE)).strip_edges()
	if not VALID_LIFE_STATES.has(raw_life):
		return null
	var raw_task: String = String(d.get("task_state", TASK_IDLE)).strip_edges()
	if not VALID_TASK_STATES.has(raw_task):
		return null
	var raw_rest: String = String(d.get("rest_phase", REST_NONE)).strip_edges()
	if not VALID_REST_PHASES.has(raw_rest):
		return null

	for need_key in ["hunger", "fatigue", "health", "morale"]:
		if d.has(need_key):
			if not _is_valid_finite_number(d[need_key]):
				return null
			var nf := float(d[need_key])
			if nf < 0.0 or nf > 100.0:
				return null

	for str_key in ["home_building_id", "workplace_id", "active_job_id", "work_target_id"]:
		if d.has(str_key) and not (d[str_key] is String):
			return null

	if d.has("work_hours_done"):
		if not _is_valid_finite_number(d["work_hours_done"]) or float(d["work_hours_done"]) < 0.0:
			return null

	if d.has("last_processed_hour_seq"):
		if not _is_valid_finite_number(d["last_processed_hour_seq"]) or int(d["last_processed_hour_seq"]) < 0:
			return null

	if d.has("admission_hour_seq"):
		if not _is_valid_finite_number(d["admission_hour_seq"]) or int(d["admission_hour_seq"]) < -1:
			return null

	if d.has("cargo") and not (d["cargo"] is Dictionary):
		return null
	if d.has("skills") and not (d["skills"] is Dictionary):
		return null

	var v := new(
		vid,
		sid,
		orig_fid,
		String(d.get("name", vid)),
		raw_role,
		_parse_vec2i(d.get("cell", Vector2i.ZERO), Vector2i.ZERO)
	)
	v.home_settlement_id = home_sid
	v.current_faction_id = cur_fid
	v.life_state = raw_life
	v.task_state = raw_task
	v.rest_phase = raw_rest

	v.hunger = float(d.get("hunger", 10.0))
	v.fatigue = float(d.get("fatigue", 10.0))
	v.health = float(d.get("health", 100.0))
	v.morale = float(d.get("morale", 70.0))

	v.home_building_id = String(d.get("home_building_id", "")).strip_edges()
	v.workplace_id = String(d.get("workplace_id", "")).strip_edges()
	v.active_job_id = String(d.get("active_job_id", "")).strip_edges()
	v.work_target_id = String(d.get("work_target_id", "")).strip_edges()
	v.work_hours_done = float(d.get("work_hours_done", 0.0))
	v.last_processed_hour_seq = int(d.get("last_processed_hour_seq", 0))
	v.admission_hour_seq = int(d.get("admission_hour_seq", -1))

	if d.has("cargo"):
		var raw_cargo: Dictionary = d["cargo"]
		if raw_cargo.has("resource") and not (raw_cargo["resource"] is String):
			return null
		if raw_cargo.has("amount") and (not _is_valid_finite_number(raw_cargo["amount"]) or int(raw_cargo["amount"]) < 0):
			return null
		if raw_cargo.has("source_workplace_id") and not (raw_cargo["source_workplace_id"] is String):
			return null
		if raw_cargo.has("dest_cell") and not _is_valid_vec2i_input(raw_cargo["dest_cell"]):
			return null
		var c_res: String = String(raw_cargo.get("resource", "")).strip_edges()
		var c_amt: int = int(raw_cargo.get("amount", 0))
		var c_src: String = String(raw_cargo.get("source_workplace_id", "")).strip_edges()
		var c_dst: Vector2i = _parse_vec2i(raw_cargo.get("dest_cell", Vector2i(-1, -1)), Vector2i(-1, -1))
		if c_amt > 0 and c_res.is_empty():
			return null
		v.set_cargo(c_res, c_amt, c_src, c_dst)

	if d.has("skills"):
		var raw_skills: Dictionary = d["skills"]
		for k in raw_skills.keys():
			var k_str := String(k)
			if not v.skills.has(k_str):
				return null
			var sv = raw_skills[k]
			if not _is_valid_finite_number(sv) or float(sv) < 0.0 or float(sv) > 1000.0:
				return null
			v.skills[k_str] = float(sv)

	return v if v.is_valid() else null

static func deserialize(data: Variant) -> RefCounted:
	return from_dict(data)
