class_name SettlementImmigrationService
extends RefCounted
## Phase 5 Settlement Immigration Service for Rival Settlements.
## Evaluates centralized immigration policy, makes deterministic seeded admission decisions,
## allocates unique villager IDs, constructs canonical SettlementVillagerData, and commits
## registration into the settlement's SettlementVillagerContext using Prepare -> Commit -> Notify.

signal immigration_evaluated(settlement_id: String, daily_seq: int, result: Dictionary)
signal villager_admitted(settlement_id: String, villager_id: String, daily_seq: int)

const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementImmigrationPolicyScript = preload("res://scripts/world/settlement_immigration_policy.gd")

const FNV1A_64_OFFSET_BASIS: int = -3750763034362895579 # 0xcbf29ce484222325 as signed 64-bit
const FNV1A_64_PRIME: int = 1099511628211

const IMMIGRANT_GIVEN_NAMES: Array[String] = [
	"An", "Binh", "Chi", "Duc", "Gia", "Hai", "Khang", "Lan",
	"Minh", "Nam", "Oanh", "Phong", "Quan", "Son", "Tam", "Uy"
]
const IMMIGRANT_FAMILY_NAMES: Array[String] = [
	"Bui", "Dang", "Do", "Ho", "Hoang", "Le", "Ly", "Ngo",
	"Nguyen", "Pham", "Phan", "Tran", "Truong", "Vo", "Vu", "Duong"
]

var policy: RefCounted = null

func _init(p_policy: RefCounted = null) -> void:
	if p_policy != null:
		policy = p_policy
	else:
		policy = SettlementImmigrationPolicyScript.new()

## Derives a deterministic 64-bit integer seed from stable simulation inputs.
## Independent of global RNG state and settlement iteration order.
static func derive_deterministic_seed(
	world_seed: int,
	settlement_id: String,
	daily_seq: int,
	attempt_index: int = 0
) -> int:
	var h: int = FNV1A_64_OFFSET_BASIS
	var payload: String = "%d|%s|%d|%d" % [world_seed, settlement_id, daily_seq, attempt_index]
	var bytes: PackedByteArray = payload.to_utf8_buffer()
	for b in bytes:
		h = h ^ int(b)
		h = h * FNV1A_64_PRIME
	if h == 0:
		h = 1
	return h

## Evaluates and (if eligible and rolled) admits up to policy.max_admissions_per_day
## canonical villagers for `ctx` at `daily_seq`.
func process_daily_immigration(
	ctx: RefCounted,
	world_seed: int,
	daily_seq: int,
	settlement_data: RefCounted = null,
	is_isolated: bool = false
) -> Dictionary:
	var base_res := {
		"ok": false,
		"evaluated": false,
		"admitted": 0,
		"admitted_ids": [],
		"eligible": false,
		"rejection_reason": "",
		"daily_seq": daily_seq
	}

	if policy == null or not policy.has_method("is_valid") or not policy.is_valid():
		base_res["rejection_reason"] = "invalid_policy"
		return base_res

	if ctx == null or not ctx.has_method("is_valid") or not ctx.is_valid():
		base_res["rejection_reason"] = "invalid_context"
		return base_res

	var st: RefCounted = ctx.sim_state
	if st == null:
		base_res["rejection_reason"] = "missing_sim_state"
		return base_res

	if daily_seq < 0:
		base_res["rejection_reason"] = "invalid_daily_seq"
		return base_res

	# Idempotency guard: at most one immigration evaluation per settlement per daily_seq
	if daily_seq <= int(st.last_immigration_daily_seq):
		base_res["ok"] = true
		base_res["rejection_reason"] = "already_evaluated_for_day"
		return base_res

	var sid: String = String(ctx.settlement_id)
	var elig: Dictionary = policy.evaluate_eligibility(ctx, settlement_data, is_isolated)
	base_res["evaluated"] = true
	base_res["eligible"] = bool(elig.get("eligible", false))
	base_res["eligibility"] = elig

	if not bool(elig.get("eligible", false)):
		st.last_immigration_daily_seq = daily_seq
		base_res["ok"] = true
		base_res["rejection_reason"] = String(elig.get("rejection_reason", "ineligible"))
		immigration_evaluated.emit(sid, daily_seq, base_res)
		return base_res

	# Deterministic seeded roll
	var rng := RandomNumberGenerator.new()
	rng.seed = derive_deterministic_seed(world_seed, sid, daily_seq, 0)
	var roll: float = rng.randf()
	base_res["roll"] = roll

	if float(policy.daily_admission_probability) <= 0.0 or roll >= float(policy.daily_admission_probability):
		st.last_immigration_daily_seq = daily_seq
		base_res["ok"] = true
		base_res["rejection_reason"] = "probability_roll_declined"
		immigration_evaluated.emit(sid, daily_seq, base_res)
		return base_res

	var slots: int = int(ctx.get_available_housing_slots())
	var permit_count: int = mini(int(policy.max_admissions_per_day), slots)
	if permit_count <= 0:
		st.last_immigration_daily_seq = daily_seq
		base_res["ok"] = true
		base_res["rejection_reason"] = "no_available_slots"
		immigration_evaluated.emit(sid, daily_seq, base_res)
		return base_res

	# --- PREPARE PHASE (no context/villager/job mutations yet) ---
	var spawn_cell: Vector2i = Vector2i.ZERO
	if settlement_data != null:
		var raw_anchor: Variant = settlement_data.get("anchor_cell")
		if raw_anchor is Vector2i and raw_anchor.x >= 0 and raw_anchor.y >= 0:
			spawn_cell = raw_anchor

	var prepared_villagers: Array = []
	for i in range(permit_count):
		var vid: String = String(ctx.allocate_villager_id())
		if vid.is_empty() or ctx.has_villager(vid):
			st.last_immigration_daily_seq = daily_seq
			base_res["rejection_reason"] = "id_allocation_failed"
			immigration_evaluated.emit(sid, daily_seq, base_res)
			return base_res

		var v_name: String = _generate_deterministic_name(rng, vid)
		var v := SettlementVillagerDataScript.new(
			vid,
			sid,
			String(ctx.origin_faction_id),
			v_name,
			SettlementVillagerDataScript.ROLE_IDLE,
			spawn_cell
		)
		v.current_faction_id = String(ctx.owner_faction_id)
		v.admission_hour_seq = daily_seq
		v.last_processed_hour_seq = daily_seq
		if not v.is_valid():
			st.last_immigration_daily_seq = daily_seq
			base_res["rejection_reason"] = "invalid_prepared_villager"
			immigration_evaluated.emit(sid, daily_seq, base_res)
			return base_res
		prepared_villagers.append(v)

	# --- COMMIT PHASE ---
	var committed_ids: Array[String] = []
	for v in prepared_villagers:
		if not ctx.add_villager(v):
			# Roll back any villagers added in this batch so admission is atomic
			for added_id in committed_ids:
				ctx.remove_villager(added_id)
				st.registered.erase(added_id)
				st.villager_daily_seq.erase(added_id)
			st.last_immigration_daily_seq = daily_seq
			base_res["rejection_reason"] = "registration_commit_failed"
			immigration_evaluated.emit(sid, daily_seq, base_res)
			return base_res
		st.registered[v.villager_id] = daily_seq
		st.villager_daily_seq[v.villager_id] = daily_seq
		committed_ids.append(v.villager_id)

	st.last_immigration_daily_seq = daily_seq
	st.total_immigrants_admitted = int(st.total_immigrants_admitted) + committed_ids.size()
	st.stats["immigrants_admitted"] = int(st.stats.get("immigrants_admitted", 0)) + committed_ids.size()

	# Integrate newcomers into existing Phase 3 job assignment lifecycle
	if ctx.job_board != null and ctx.workplace_registry != null:
		ctx.assign_villagers_to_jobs()

	base_res["ok"] = true
	base_res["admitted"] = committed_ids.size()
	base_res["admitted_ids"] = committed_ids
	base_res["rejection_reason"] = ""

	# --- NOTIFY PHASE ---
	for vid in committed_ids:
		villager_admitted.emit(sid, vid, daily_seq)
	immigration_evaluated.emit(sid, daily_seq, base_res)
	return base_res

static func _generate_deterministic_name(rng: RandomNumberGenerator, fallback_id: String) -> String:
	if rng == null or IMMIGRANT_FAMILY_NAMES.is_empty() or IMMIGRANT_GIVEN_NAMES.is_empty():
		return fallback_id
	var fam: String = IMMIGRANT_FAMILY_NAMES[rng.randi() % IMMIGRANT_FAMILY_NAMES.size()]
	var giv: String = IMMIGRANT_GIVEN_NAMES[rng.randi() % IMMIGRANT_GIVEN_NAMES.size()]
	return "%s %s" % [fam, giv]
