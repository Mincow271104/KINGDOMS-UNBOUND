class_name FactionManager
extends RefCounted
## Faction & Diplomacy Management System for KINGDOMS UNBOUND.
## Conforms to GDD Section 10:
## Manages 2 rival kingdoms, 1 neutral tribe, opinion changes, treaties, and diplomatic gifts.



const OPINION_PENALTY_OFFENSIVE_CAMPAIGN: float = 8.0
const OPINION_PENALTY_SETTLEMENT_RAID: float = 10.0

const ASCENSION_MIN_POPULATION: int = 45
const ASCENSION_MIN_DAY: int = 10
const ASCENSION_MIN_WOOD: int = 60
const ASCENSION_MIN_HERBS: int = 30
const ASCENSION_MIN_STABILITY: float = 50.0

const ASCENSION_NEW_TYPE: String = "emerging_power"
const ASCENSION_NEW_NAME: String = "Liên Minh Rừng Thiêng"
const ASCENSION_NEW_MILITARY_POWER: float = 55.0
const ASCENSION_NEW_STABILITY: float = 85.0
const ASCENSION_NEW_STRATEGIC_GOAL: String = FactionData.GOAL_CONSOLIDATE_POWER

# Autonomous Diplomacy Execution Reason Codes (Package 1T)
const DIPLO_REASON_EXECUTED_WAR: String = "EXECUTED_DECLARE_WAR"
const DIPLO_REASON_EXECUTED_PEACE: String = "EXECUTED_SIGN_PEACE"
const DIPLO_REASON_ALREADY_EVALUATED_TODAY: String = "ALREADY_EVALUATED_TODAY"
const DIPLO_REASON_NO_ACTION: String = "NO_ACTION"
const DIPLO_REASON_API_REJECTED: String = "API_REJECTED"
const DIPLO_REASON_ERR_NULL_FACTION: String = "ERR_NULL_FACTION"
const DIPLO_REASON_ERR_INVALID_DAY: String = "ERR_INVALID_DAY"
const DIPLO_REASON_ERR_INVALID_DECISION: String = "ERR_INVALID_DECISION"

# Pairwise Faction Relations Reason Codes (Package 1U)
const PAIR_REASON_OK: String = "OK"
const PAIR_REASON_ERR_SELF_RELATION: String = "ERR_SELF_RELATION"
const PAIR_REASON_ERR_UNKNOWN_FACTION: String = "ERR_UNKNOWN_FACTION"
const PAIR_REASON_ERR_INVALID_NUMBER: String = "ERR_INVALID_NUMBER"
const PAIR_REASON_ERR_INVALID_STATUS: String = "ERR_INVALID_STATUS"
const PAIR_REASON_ERR_ALREADY_AT_WAR: String = "ERR_ALREADY_AT_WAR"
const PAIR_REASON_ERR_NOT_AT_WAR: String = "ERR_NOT_AT_WAR"
const PAIR_REASON_ERR_AT_WAR: String = "ERR_AT_WAR"
const PAIR_REASON_ERR_ALREADY_HAS_NAP: String = "ERR_ALREADY_HAS_NAP"
const PAIR_REASON_ERR_ALREADY_ALLIED: String = "ERR_ALREADY_ALLIED"
const PAIR_REASON_ERR_INSUFFICIENT_OPINION: String = "ERR_INSUFFICIENT_OPINION"
const PAIR_REASON_ERR_UNKNOWN_TREATY: String = "ERR_UNKNOWN_TREATY"

signal relation_changed(faction_id: String, new_opinion: float, disposition: int)
signal treaty_signed(faction_id: String, treaty_type: String)
signal war_declared(faction_id: String)
signal peace_signed(faction_id: String)
signal emerging_faction_ascended(faction_id: String, new_name: String)
signal strategic_intent_evaluated(faction_id: String, intent_data: Dictionary)
signal strategic_intent_executed(faction_id: String, execution_result: Dictionary)
signal diplomatic_action_evaluated(faction_id: String, decision_data: Dictionary)
signal diplomatic_action_executed(faction_id: String, execution_result: Dictionary)
signal faction_pair_opinion_changed(from_id: String, to_id: String, new_opinion: float, disposition: int)
signal faction_pair_war_declared(initiator_id: String, target_id: String, pair_key: String)
signal faction_pair_peace_signed(faction_a: String, faction_b: String, pair_key: String)
signal faction_pair_treaty_signed(faction_a: String, faction_b: String, treaty_type: String, pair_key: String)

var _factions: Dictionary = {} # id -> FactionData
var _pairwise_relations: Dictionary = {} # canonical pair_key -> FactionRelationData
var _strategy_executor: FactionStrategyExecutor = FactionStrategyExecutor.new()
var _last_tribe_growth_day: int = -1
var _last_diplomacy_days: Dictionary = {} # faction_id -> int day

func _init() -> void:
	_initialize_factions()

func _initialize_factions() -> void:
	_factions.clear()
	if _strategy_executor != null:
		_strategy_executor.reset_state()
	_last_tribe_growth_day = -1
	_last_diplomacy_days.clear()
	
	# Rival 1: Military Kingdom
	var rival_mil := FactionData.new(
		"rival_military",
		"Cổ Thành Thiết Giáp",
		"rival_military",
		FactionData.Disposition.NEUTRAL,
		-10.0,
		75.0
	)
	rival_mil.resources = {EconomyConfig.RES_METAL: 80, EconomyConfig.RES_GOLD: 150}
	rival_mil.population = 60
	rival_mil.strategic_goal = FactionData.GOAL_MILITARY_EXPANSION
	rival_mil.existence_status = FactionData.STATUS_ACTIVE
	_factions[rival_mil.id] = rival_mil
	
	# Rival 2: Mercantile Syndicate
	var rival_merch := FactionData.new(
		"rival_merchant",
		"Thương Hội Vân Đồn",
		"rival_merchant",
		FactionData.Disposition.NEUTRAL,
		15.0,
		50.0
	)
	rival_merch.resources = {EconomyConfig.RES_GOLD: 400, EconomyConfig.RES_TOOLS: 50}
	rival_merch.population = 50
	rival_merch.strategic_goal = FactionData.GOAL_TRADE_DOMINANCE
	rival_merch.existence_status = FactionData.STATUS_ACTIVE
	_factions[rival_merch.id] = rival_merch
	
	# Neutral Tribe
	var neutral_tribe := FactionData.new(
		"neutral_tribe",
		"Bản Làng Rừng Xanh",
		"neutral_tribe",
		FactionData.Disposition.FRIENDLY,
		30.0,
		30.0
	)
	neutral_tribe.resources = {EconomyConfig.RES_WOOD: 120, EconomyConfig.RES_HERBS: 60}
	neutral_tribe.population = 35
	neutral_tribe.strategic_goal = FactionData.GOAL_COMMUNITY_GROWTH
	neutral_tribe.existence_status = FactionData.STATUS_ACTIVE
	_factions[neutral_tribe.id] = neutral_tribe
	initialize_pairwise_relations(true)

func initialize_pairwise_relations(reset_existing: bool = false) -> void:
	if reset_existing:
		_pairwise_relations.clear()
	var sorted_ids: Array = _factions.keys()
	sorted_ids.sort()
	for i in range(sorted_ids.size()):
		var id_a: String = str(sorted_ids[i])
		for j in range(i + 1, sorted_ids.size()):
			var id_b: String = str(sorted_ids[j])
			var p_key: String = FactionRelationData.make_pair_key(id_a, id_b)
			if p_key.is_empty():
				continue
			if not _pairwise_relations.has(p_key):
				_pairwise_relations[p_key] = FactionRelationData.new(id_a, id_b)

func get_faction_pair_key(id_1: String, id_2: String) -> String:
	if id_1.is_empty() or id_2.is_empty() or id_1 == id_2:
		return ""
	if get_faction(id_1) == null or get_faction(id_2) == null:
		return ""
	return FactionRelationData.make_pair_key(id_1, id_2)

func get_faction_relation_record(id_1: String, id_2: String) -> FactionRelationData:
	var p_key: String = get_faction_pair_key(id_1, id_2)
	if p_key.is_empty():
		return null
	if not _pairwise_relations.has(p_key):
		initialize_pairwise_relations(false)
	return _pairwise_relations.get(p_key, null)

func get_faction_relation(from_id: String, to_id: String) -> Dictionary:
	var rec: FactionRelationData = get_faction_relation_record(from_id, to_id)
	if rec == null:
		return {}
	return rec.to_directed_view(from_id, to_id)

func get_directed_faction_opinion(from_id: String, to_id: String) -> float:
	var rec: FactionRelationData = get_faction_relation_record(from_id, to_id)
	if rec == null:
		return 0.0
	return rec.get_opinion(from_id, to_id)

func are_factions_at_war(id_1: String, id_2: String) -> bool:
	var rec: FactionRelationData = get_faction_relation_record(id_1, id_2)
	if rec == null:
		return false
	return rec.is_at_war

func do_factions_have_nap(id_1: String, id_2: String) -> bool:
	var rec: FactionRelationData = get_faction_relation_record(id_1, id_2)
	if rec == null:
		return false
	return rec.has_nap

func do_factions_have_alliance(id_1: String, id_2: String) -> bool:
	var rec: FactionRelationData = get_faction_relation_record(id_1, id_2)
	if rec == null:
		return false
	return rec.has_alliance

func get_all_faction_relations() -> Array[Dictionary]:
	initialize_pairwise_relations(false)
	var out: Array[Dictionary] = []
	var sorted_keys: Array = _pairwise_relations.keys()
	sorted_keys.sort()
	for k in sorted_keys:
		var rec: FactionRelationData = _pairwise_relations.get(k, null)
		if rec != null:
			out.append(rec.serialize())
	return out

func _validate_faction_pair_ids(id_1: String, id_2: String) -> Dictionary:
	if id_1 == id_2 and not id_1.is_empty():
		return {
			"valid": false,
			"reason_code": PAIR_REASON_ERR_SELF_RELATION,
			"reason": "Một thế lực không thể thiết lập quan hệ ngoại giao với chính mình (%s)" % id_1
		}
	var fac_1: FactionData = get_faction(id_1)
	var fac_2: FactionData = get_faction(id_2)
	if fac_1 == null or fac_2 == null:
		return {
			"valid": false,
			"reason_code": PAIR_REASON_ERR_UNKNOWN_FACTION,
			"reason": "Một hoặc cả hai thế lực không tồn tại (%s, %s)" % [id_1, id_2]
		}
	var rec: FactionRelationData = get_faction_relation_record(id_1, id_2)
	if rec == null:
		return {
			"valid": false,
			"reason_code": PAIR_REASON_ERR_UNKNOWN_FACTION,
			"reason": "Không tìm thấy bản ghi quan hệ giữa (%s, %s)" % [id_1, id_2]
		}
	return {
		"valid": true,
		"fac_1": fac_1,
		"fac_2": fac_2,
		"record": rec,
		"pair_key": rec.get_pair_key()
	}

func _emit_pair_opinion_signals(rec: FactionRelationData) -> void:
	if rec == null:
		return
	faction_pair_opinion_changed.emit(
		rec.faction_a,
		rec.faction_b,
		rec.opinion_a_to_b,
		rec.get_disposition(rec.faction_a, rec.faction_b)
	)
	faction_pair_opinion_changed.emit(
		rec.faction_b,
		rec.faction_a,
		rec.opinion_b_to_a,
		rec.get_disposition(rec.faction_b, rec.faction_a)
	)

func set_faction_pair_opinion(from_id: String, to_id: String, value: Variant) -> Dictionary:
	var check: Dictionary = _validate_faction_pair_ids(from_id, to_id)
	if not bool(check.get("valid", false)):
		return {
			"success": false,
			"reason_code": str(check.get("reason_code", PAIR_REASON_ERR_UNKNOWN_FACTION)),
			"reason": str(check.get("reason", ""))
		}
	if not FactionRelationData.is_valid_finite_number(value):
		return {
			"success": false,
			"reason_code": PAIR_REASON_ERR_INVALID_NUMBER,
			"reason": "Giá trị thiện cảm phải là số hữu hạn hợp lệ"
		}
	var rec: FactionRelationData = check["record"]
	var prev_op: float = rec.get_opinion(from_id, to_id)
	rec.set_opinion(from_id, to_id, float(value))
	var new_op: float = rec.get_opinion(from_id, to_id)
	var new_disp: int = rec.get_disposition(from_id, to_id)
	faction_pair_opinion_changed.emit(from_id, to_id, new_op, new_disp)
	return {
		"success": true,
		"reason_code": PAIR_REASON_OK,
		"pair_key": rec.get_pair_key(),
		"from_id": from_id,
		"to_id": to_id,
		"previous_opinion": prev_op,
		"new_opinion": new_op,
		"disposition": new_disp
	}

func modify_faction_pair_opinion(from_id: String, to_id: String, delta: Variant) -> Dictionary:
	var check: Dictionary = _validate_faction_pair_ids(from_id, to_id)
	if not bool(check.get("valid", false)):
		return {
			"success": false,
			"reason_code": str(check.get("reason_code", PAIR_REASON_ERR_UNKNOWN_FACTION)),
			"reason": str(check.get("reason", ""))
		}
	if not FactionRelationData.is_valid_finite_number(delta):
		return {
			"success": false,
			"reason_code": PAIR_REASON_ERR_INVALID_NUMBER,
			"reason": "Độ biến thiên thiện cảm phải là số hữu hạn hợp lệ"
		}
	var rec: FactionRelationData = check["record"]
	var prev_op: float = rec.get_opinion(from_id, to_id)
	rec.change_opinion(from_id, to_id, float(delta))
	var new_op: float = rec.get_opinion(from_id, to_id)
	var new_disp: int = rec.get_disposition(from_id, to_id)
	faction_pair_opinion_changed.emit(from_id, to_id, new_op, new_disp)
	return {
		"success": true,
		"reason_code": PAIR_REASON_OK,
		"pair_key": rec.get_pair_key(),
		"from_id": from_id,
		"to_id": to_id,
		"previous_opinion": prev_op,
		"new_opinion": new_op,
		"disposition": new_disp
	}

func declare_war_between_factions(initiator_id: String, target_id: String) -> Dictionary:
	var check: Dictionary = _validate_faction_pair_ids(initiator_id, target_id)
	if not bool(check.get("valid", false)):
		return {
			"success": false,
			"reason_code": str(check.get("reason_code", PAIR_REASON_ERR_UNKNOWN_FACTION)),
			"reason": str(check.get("reason", ""))
		}
	var fac_1: FactionData = check["fac_1"]
	var fac_2: FactionData = check["fac_2"]
	if not FactionData.VALID_EXISTENCE_STATUSES.has(fac_1.existence_status) or fac_1.existence_status != FactionData.STATUS_ACTIVE:
		return {
			"success": false,
			"reason_code": PAIR_REASON_ERR_INVALID_STATUS,
			"reason": "Thế lực phát động '%s' không ở trạng thái hoạt động (%s)" % [fac_1.id, fac_1.existence_status]
		}
	if not FactionData.VALID_EXISTENCE_STATUSES.has(fac_2.existence_status) or fac_2.existence_status != FactionData.STATUS_ACTIVE:
		return {
			"success": false,
			"reason_code": PAIR_REASON_ERR_INVALID_STATUS,
			"reason": "Thế lực mục tiêu '%s' không ở trạng thái hoạt động (%s)" % [fac_2.id, fac_2.existence_status]
		}
	var rec: FactionRelationData = check["record"]
	if rec.is_at_war:
		return {
			"success": false,
			"reason_code": PAIR_REASON_ERR_ALREADY_AT_WAR,
			"reason": "Hai thế lực đã ở trong tình trạng chiến tranh"
		}
	rec.apply_declare_war()
	var p_key: String = rec.get_pair_key()
	faction_pair_war_declared.emit(initiator_id, target_id, p_key)
	_emit_pair_opinion_signals(rec)
	return {
		"success": true,
		"reason_code": PAIR_REASON_OK,
		"pair_key": p_key,
		"initiator_id": initiator_id,
		"target_id": target_id,
		"is_at_war": rec.is_at_war,
		"has_nap": rec.has_nap,
		"has_alliance": rec.has_alliance,
		"opinion_a_to_b": rec.opinion_a_to_b,
		"opinion_b_to_a": rec.opinion_b_to_a
	}

func sign_peace_between_factions(id_1: String, id_2: String) -> Dictionary:
	var check: Dictionary = _validate_faction_pair_ids(id_1, id_2)
	if not bool(check.get("valid", false)):
		return {
			"success": false,
			"reason_code": str(check.get("reason_code", PAIR_REASON_ERR_UNKNOWN_FACTION)),
			"reason": str(check.get("reason", ""))
		}
	var fac_1: FactionData = check["fac_1"]
	var fac_2: FactionData = check["fac_2"]
	if not FactionData.VALID_EXISTENCE_STATUSES.has(fac_1.existence_status) or fac_1.existence_status == FactionData.STATUS_ELIMINATED:
		return {
			"success": false,
			"reason_code": PAIR_REASON_ERR_INVALID_STATUS,
			"reason": "Thế lực '%s' không thể ký hòa ước ở trạng thái (%s)" % [fac_1.id, fac_1.existence_status]
		}
	if not FactionData.VALID_EXISTENCE_STATUSES.has(fac_2.existence_status) or fac_2.existence_status == FactionData.STATUS_ELIMINATED:
		return {
			"success": false,
			"reason_code": PAIR_REASON_ERR_INVALID_STATUS,
			"reason": "Thế lực '%s' không thể ký hòa ước ở trạng thái (%s)" % [fac_2.id, fac_2.existence_status]
		}
	var rec: FactionRelationData = check["record"]
	if not rec.is_at_war:
		return {
			"success": false,
			"reason_code": PAIR_REASON_ERR_NOT_AT_WAR,
			"reason": "Hai thế lực đang trong trạng thái hòa bình"
		}
	rec.apply_sign_peace()
	var p_key: String = rec.get_pair_key()
	faction_pair_peace_signed.emit(rec.faction_a, rec.faction_b, p_key)
	_emit_pair_opinion_signals(rec)
	return {
		"success": true,
		"reason_code": PAIR_REASON_OK,
		"pair_key": p_key,
		"faction_a": rec.faction_a,
		"faction_b": rec.faction_b,
		"is_at_war": rec.is_at_war,
		"opinion_a_to_b": rec.opinion_a_to_b,
		"opinion_b_to_a": rec.opinion_b_to_a
	}

func sign_nap_between_factions(id_1: String, id_2: String) -> Dictionary:
	var check: Dictionary = _validate_faction_pair_ids(id_1, id_2)
	if not bool(check.get("valid", false)):
		return {
			"success": false,
			"reason_code": str(check.get("reason_code", PAIR_REASON_ERR_UNKNOWN_FACTION)),
			"reason": str(check.get("reason", ""))
		}
	var fac_1: FactionData = check["fac_1"]
	var fac_2: FactionData = check["fac_2"]
	if not FactionData.VALID_EXISTENCE_STATUSES.has(fac_1.existence_status) or fac_1.existence_status != FactionData.STATUS_ACTIVE:
		return {
			"success": false,
			"reason_code": PAIR_REASON_ERR_INVALID_STATUS,
			"reason": "Thế lực '%s' không ở trạng thái hoạt động (%s)" % [fac_1.id, fac_1.existence_status]
		}
	if not FactionData.VALID_EXISTENCE_STATUSES.has(fac_2.existence_status) or fac_2.existence_status != FactionData.STATUS_ACTIVE:
		return {
			"success": false,
			"reason_code": PAIR_REASON_ERR_INVALID_STATUS,
			"reason": "Thế lực '%s' không ở trạng thái hoạt động (%s)" % [fac_2.id, fac_2.existence_status]
		}
	var rec: FactionRelationData = check["record"]
	if rec.is_at_war:
		return {
			"success": false,
			"reason_code": PAIR_REASON_ERR_AT_WAR,
			"reason": "Đang có chiến tranh, không thể ký Hiệp Ước Không Xâm Phạm"
		}
	if rec.has_nap:
		return {
			"success": false,
			"reason_code": PAIR_REASON_ERR_ALREADY_HAS_NAP,
			"reason": "Hai thế lực đã có Hiệp Ước Không Xâm Phạm"
		}
	if rec.opinion_a_to_b < FactionRelationData.NAP_MIN_OPINION or rec.opinion_b_to_a < FactionRelationData.NAP_MIN_OPINION:
		return {
			"success": false,
			"reason_code": PAIR_REASON_ERR_INSUFFICIENT_OPINION,
			"reason": "Thiện cảm song phương chưa đủ (cần >= 0 từ cả hai phía)"
		}
	rec.apply_sign_nap()
	var p_key: String = rec.get_pair_key()
	faction_pair_treaty_signed.emit(rec.faction_a, rec.faction_b, "nap", p_key)
	_emit_pair_opinion_signals(rec)
	return {
		"success": true,
		"reason_code": PAIR_REASON_OK,
		"pair_key": p_key,
		"treaty_type": "nap",
		"has_nap": rec.has_nap,
		"has_alliance": rec.has_alliance,
		"opinion_a_to_b": rec.opinion_a_to_b,
		"opinion_b_to_a": rec.opinion_b_to_a
	}

func sign_alliance_between_factions(id_1: String, id_2: String) -> Dictionary:
	var check: Dictionary = _validate_faction_pair_ids(id_1, id_2)
	if not bool(check.get("valid", false)):
		return {
			"success": false,
			"reason_code": str(check.get("reason_code", PAIR_REASON_ERR_UNKNOWN_FACTION)),
			"reason": str(check.get("reason", ""))
		}
	var fac_1: FactionData = check["fac_1"]
	var fac_2: FactionData = check["fac_2"]
	if not FactionData.VALID_EXISTENCE_STATUSES.has(fac_1.existence_status) or fac_1.existence_status != FactionData.STATUS_ACTIVE:
		return {
			"success": false,
			"reason_code": PAIR_REASON_ERR_INVALID_STATUS,
			"reason": "Thế lực '%s' không ở trạng thái hoạt động (%s)" % [fac_1.id, fac_1.existence_status]
		}
	if not FactionData.VALID_EXISTENCE_STATUSES.has(fac_2.existence_status) or fac_2.existence_status != FactionData.STATUS_ACTIVE:
		return {
			"success": false,
			"reason_code": PAIR_REASON_ERR_INVALID_STATUS,
			"reason": "Thế lực '%s' không ở trạng thái hoạt động (%s)" % [fac_2.id, fac_2.existence_status]
		}
	var rec: FactionRelationData = check["record"]
	if rec.is_at_war:
		return {
			"success": false,
			"reason_code": PAIR_REASON_ERR_AT_WAR,
			"reason": "Đang có chiến tranh, không thể ký Liên Minh Phòng Thủ"
		}
	if rec.has_alliance:
		return {
			"success": false,
			"reason_code": PAIR_REASON_ERR_ALREADY_ALLIED,
			"reason": "Hai thế lực đã trong Liên Minh Phòng Thủ"
		}
	if rec.opinion_a_to_b < FactionRelationData.ALLIANCE_MIN_OPINION or rec.opinion_b_to_a < FactionRelationData.ALLIANCE_MIN_OPINION:
		return {
			"success": false,
			"reason_code": PAIR_REASON_ERR_INSUFFICIENT_OPINION,
			"reason": "Thiện cảm song phương chưa đủ cao (cần >= 60 từ cả hai phía)"
		}
	rec.apply_sign_alliance()
	var p_key: String = rec.get_pair_key()
	faction_pair_treaty_signed.emit(rec.faction_a, rec.faction_b, "alliance", p_key)
	_emit_pair_opinion_signals(rec)
	return {
		"success": true,
		"reason_code": PAIR_REASON_OK,
		"pair_key": p_key,
		"treaty_type": "alliance",
		"has_nap": rec.has_nap,
		"has_alliance": rec.has_alliance,
		"opinion_a_to_b": rec.opinion_a_to_b,
		"opinion_b_to_a": rec.opinion_b_to_a
	}

func propose_treaty_between_factions(id_1: String, id_2: String, treaty_type: String) -> Dictionary:
	match treaty_type:
		"peace":
			return sign_peace_between_factions(id_1, id_2)
		"nap":
			return sign_nap_between_factions(id_1, id_2)
		"alliance":
			return sign_alliance_between_factions(id_1, id_2)
		_:
			var check: Dictionary = _validate_faction_pair_ids(id_1, id_2)
			if not bool(check.get("valid", false)):
				return {
					"success": false,
					"reason_code": str(check.get("reason_code", PAIR_REASON_ERR_UNKNOWN_FACTION)),
					"reason": str(check.get("reason", ""))
				}
			return {
				"success": false,
				"reason_code": PAIR_REASON_ERR_UNKNOWN_TREATY,
				"reason": "Loại hiệp ước không xác định: %s" % treaty_type
			}

func serialize_pairwise_relations() -> Dictionary:
	initialize_pairwise_relations(false)
	var out: Dictionary = {}
	var sorted_keys: Array = _pairwise_relations.keys()
	sorted_keys.sort()
	for k in sorted_keys:
		var rec: FactionRelationData = _pairwise_relations.get(k, null)
		if rec != null:
			out[String(k)] = rec.serialize()
	return out

func deserialize_pairwise_relations(data: Dictionary) -> void:
	initialize_pairwise_relations(true)
	if data.is_empty():
		return
	var sorted_keys: Array = data.keys()
	sorted_keys.sort()
	for raw_key in sorted_keys:
		if not (raw_key is String):
			continue
		var entry = data[raw_key]
		if not (entry is Dictionary):
			continue
		var fa: String = str(entry.get("faction_a", ""))
		var fb: String = str(entry.get("faction_b", ""))
		if fa.is_empty() or fb.is_empty() or fa == fb:
			continue
		if get_faction(fa) == null or get_faction(fb) == null:
			continue
		var p_key: String = FactionRelationData.make_pair_key(fa, fb)
		if p_key.is_empty() or not _pairwise_relations.has(p_key):
			continue
		var rec: FactionRelationData = _pairwise_relations[p_key]
		var raw_op_ab = entry.get("opinion_a_to_b", 0.0)
		var raw_op_ba = entry.get("opinion_b_to_a", 0.0)
		var op_ab: float = float(raw_op_ab) if FactionRelationData.is_valid_finite_number(raw_op_ab) else 0.0
		var op_ba: float = float(raw_op_ba) if FactionRelationData.is_valid_finite_number(raw_op_ba) else 0.0
		if fa == rec.faction_a and fb == rec.faction_b:
			rec.set_opinion(rec.faction_a, rec.faction_b, op_ab)
			rec.set_opinion(rec.faction_b, rec.faction_a, op_ba)
		else:
			rec.set_opinion(rec.faction_a, rec.faction_b, op_ba)
			rec.set_opinion(rec.faction_b, rec.faction_a, op_ab)
		var at_war: bool = bool(entry.get("is_at_war", false)) if (entry.get("is_at_war", false) is bool) else false
		var nap: bool = bool(entry.get("has_nap", false)) if (entry.get("has_nap", false) is bool) else false
		var allied: bool = bool(entry.get("has_alliance", false)) if (entry.get("has_alliance", false) is bool) else false
		if at_war:
			rec.is_at_war = true
			rec.has_nap = false
			rec.has_alliance = false
		elif allied:
			rec.is_at_war = false
			rec.has_alliance = true
			rec.has_nap = true
		else:
			rec.is_at_war = false
			rec.has_alliance = false
			rec.has_nap = nap

func get_faction(id: String) -> FactionData:
	return _factions.get(id, null)

func get_all_factions() -> Array:
	return _factions.values()

func get_faction_strategic_intent(faction_id: String) -> Dictionary:
	var fac: FactionData = get_faction(faction_id)
	return FactionStrategyPlanner.evaluate_faction_intent(fac)

func evaluate_all_strategic_intents() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var sorted_ids: Array = _factions.keys()
	sorted_ids.sort()
	for fid in sorted_ids:
		var fac: FactionData = _factions[fid]
		if fac != null:
			results.append(FactionStrategyPlanner.evaluate_faction_intent(fac))
	return results

func get_faction_diplomatic_decision(faction_id: String) -> Dictionary:
	var fac: FactionData = get_faction(faction_id)
	return FactionDiplomacyPlanner.evaluate_diplomatic_action(fac)

func evaluate_all_diplomatic_decisions() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var sorted_ids: Array = _factions.keys()
	sorted_ids.sort()
	for fid in sorted_ids:
		var fac: FactionData = _factions[fid]
		if fac != null:
			results.append(FactionDiplomacyPlanner.evaluate_diplomatic_action(fac))
	return results

func get_faction_last_diplomacy_day(faction_id: String) -> int:
	if faction_id.is_empty():
		return -1
	return int(_last_diplomacy_days.get(faction_id, -1))

func set_faction_last_diplomacy_day(faction_id: String, day: int) -> void:
	if faction_id.is_empty():
		return
	if day >= 1:
		_last_diplomacy_days[faction_id] = day
	else:
		_last_diplomacy_days.erase(faction_id)

func execute_faction_diplomatic_action(faction_id: String, day: int, decision_override: Dictionary = {}) -> Dictionary:
	var fac: FactionData = get_faction(faction_id)
	if fac == null:
		return {
			"faction_id": faction_id,
			"day": day,
			"action_id": FactionDiplomacyPlanner.ACTION_NONE,
			"success": false,
			"reason_code": DIPLO_REASON_ERR_NULL_FACTION,
			"planner_reason_code": FactionDiplomacyPlanner.REASON_ERR_NULL_FACTION,
			"changes": {}
		}
	if day < 1:
		return {
			"faction_id": fac.id,
			"day": day,
			"action_id": FactionDiplomacyPlanner.ACTION_NONE,
			"success": false,
			"reason_code": DIPLO_REASON_ERR_INVALID_DAY,
			"planner_reason_code": "",
			"changes": {}
		}

	var expected_decision: Dictionary = FactionDiplomacyPlanner.evaluate_diplomatic_action(fac)
	var decision: Dictionary = expected_decision if decision_override.is_empty() else decision_override

	if not decision_override.is_empty():
		var ov_fid: String = str(decision.get("faction_id", ""))
		var ov_act: String = str(decision.get("action_id", ""))
		var ov_elig: Variant = decision.get("eligible", null)
		if ov_fid != fac.id or not FactionDiplomacyPlanner.VALID_ACTIONS.has(ov_act) or not (ov_elig is bool):
			return {
				"faction_id": fac.id,
				"day": day,
				"action_id": FactionDiplomacyPlanner.ACTION_NONE,
				"success": false,
				"reason_code": DIPLO_REASON_ERR_INVALID_DECISION,
				"planner_reason_code": str(expected_decision.get("reason_code", "")),
				"changes": {}
			}
		if ov_act != str(expected_decision.get("action_id", "")) or bool(ov_elig) != bool(expected_decision.get("eligible", false)):
			return {
				"faction_id": fac.id,
				"day": day,
				"action_id": FactionDiplomacyPlanner.ACTION_NONE,
				"success": false,
				"reason_code": DIPLO_REASON_ERR_INVALID_DECISION,
				"planner_reason_code": str(expected_decision.get("reason_code", "")),
				"changes": {}
			}

	var planner_reason: String = str(decision.get("reason_code", ""))
	if planner_reason in [
		FactionDiplomacyPlanner.REASON_ERR_NULL_FACTION,
		FactionDiplomacyPlanner.REASON_ERR_INVALID_STATUS,
		FactionDiplomacyPlanner.REASON_ERR_INVALID_GOAL,
		FactionDiplomacyPlanner.REASON_ERR_INVALID_STATE,
		FactionDiplomacyPlanner.REASON_INELIGIBLE_ELIMINATED
	]:
		return {
			"faction_id": fac.id,
			"day": day,
			"action_id": FactionDiplomacyPlanner.ACTION_NONE,
			"success": false,
			"reason_code": planner_reason,
			"planner_reason_code": planner_reason,
			"changes": {}
		}

	if get_faction_last_diplomacy_day(fac.id) >= day:
		return {
			"faction_id": fac.id,
			"day": day,
			"action_id": FactionDiplomacyPlanner.ACTION_NONE,
			"success": false,
			"reason_code": DIPLO_REASON_ALREADY_EVALUATED_TODAY,
			"planner_reason_code": planner_reason,
			"changes": {}
		}

	set_faction_last_diplomacy_day(fac.id, day)
	diplomatic_action_evaluated.emit(fac.id, decision)

	var action_id: String = str(decision.get("action_id", FactionDiplomacyPlanner.ACTION_NONE))
	var eligible: bool = bool(decision.get("eligible", false))
	if not eligible or action_id == FactionDiplomacyPlanner.ACTION_NONE:
		return {
			"faction_id": fac.id,
			"day": day,
			"action_id": FactionDiplomacyPlanner.ACTION_NONE,
			"success": false,
			"reason_code": DIPLO_REASON_NO_ACTION,
			"planner_reason_code": planner_reason,
			"changes": {}
		}

	var prev_war: bool = fac.is_at_war
	var prev_opinion: float = fac.opinion
	var prev_disp: int = fac.disposition
	var prev_nap: bool = fac.has_nap
	var prev_alliance: bool = fac.has_alliance

	if action_id == FactionDiplomacyPlanner.ACTION_DECLARE_WAR:
		var api_res: Dictionary = declare_war(fac.id)
		if not bool(api_res.get("success", false)):
			return {
				"faction_id": fac.id,
				"day": day,
				"action_id": action_id,
				"success": false,
				"reason_code": DIPLO_REASON_API_REJECTED,
				"planner_reason_code": planner_reason,
				"changes": {}
			}
		var res_war: Dictionary = {
			"faction_id": fac.id,
			"day": day,
			"action_id": FactionDiplomacyPlanner.ACTION_DECLARE_WAR,
			"success": true,
			"reason_code": DIPLO_REASON_EXECUTED_WAR,
			"planner_reason_code": planner_reason,
			"changes": {
				"is_at_war_before": prev_war,
				"is_at_war_after": fac.is_at_war,
				"opinion_before": prev_opinion,
				"opinion_after": fac.opinion,
				"disposition_before": prev_disp,
				"disposition_after": fac.disposition,
				"has_nap_before": prev_nap,
				"has_nap_after": fac.has_nap,
				"has_alliance_before": prev_alliance,
				"has_alliance_after": fac.has_alliance
			}
		}
		diplomatic_action_executed.emit(fac.id, res_war)
		return res_war

	if action_id == FactionDiplomacyPlanner.ACTION_SIGN_PEACE:
		var api_res_peace: Dictionary = propose_treaty(fac.id, "peace")
		if not bool(api_res_peace.get("success", false)):
			return {
				"faction_id": fac.id,
				"day": day,
				"action_id": action_id,
				"success": false,
				"reason_code": DIPLO_REASON_API_REJECTED,
				"planner_reason_code": planner_reason,
				"changes": {}
			}
		var res_peace: Dictionary = {
			"faction_id": fac.id,
			"day": day,
			"action_id": FactionDiplomacyPlanner.ACTION_SIGN_PEACE,
			"success": true,
			"reason_code": DIPLO_REASON_EXECUTED_PEACE,
			"planner_reason_code": planner_reason,
			"changes": {
				"is_at_war_before": prev_war,
				"is_at_war_after": fac.is_at_war,
				"opinion_before": prev_opinion,
				"opinion_after": fac.opinion,
				"disposition_before": prev_disp,
				"disposition_after": fac.disposition
			}
		}
		diplomatic_action_executed.emit(fac.id, res_peace)
		return res_peace

	return {
		"faction_id": fac.id,
		"day": day,
		"action_id": FactionDiplomacyPlanner.ACTION_NONE,
		"success": false,
		"reason_code": DIPLO_REASON_ERR_INVALID_DECISION,
		"planner_reason_code": planner_reason,
		"changes": {}
	}

func get_strategy_executor() -> FactionStrategyExecutor:
	return _strategy_executor

func get_faction_last_executed_day(faction_id: String) -> int:
	if _strategy_executor == null:
		return -1
	return _strategy_executor.get_last_executed_day(faction_id)

func execute_faction_strategic_intent(faction_id: String, day: int, context: Dictionary = {}) -> Dictionary:
	var fac: FactionData = get_faction(faction_id)
	var decision: Dictionary = FactionStrategyPlanner.evaluate_faction_intent(fac)
	var exec_res: Dictionary = _strategy_executor.execute_intent(fac, decision, day, context)
	if fac != null and decision.get("eligible", false):
		strategic_intent_executed.emit(fac.id, exec_res)
	return exec_res

func serialize_executor_state() -> Dictionary:
	var out: Dictionary = _strategy_executor.serialize() if _strategy_executor != null else {"last_executed_days": {}}
	out["last_tribe_growth_day"] = _last_tribe_growth_day
	out["last_diplomacy_days"] = _last_diplomacy_days.duplicate(true)
	return out

func deserialize_executor_state(data: Dictionary, current_day: int = -1) -> void:
	if _strategy_executor == null:
		_strategy_executor = FactionStrategyExecutor.new()
	_strategy_executor.deserialize(data, current_day)
	_last_diplomacy_days.clear()
	if data.is_empty():
		_last_tribe_growth_day = -1
		return
	var raw_growth = data.get("last_tribe_growth_day", -1)
	if raw_growth is int or (raw_growth is float and not is_nan(raw_growth) and not is_inf(raw_growth) and floor(raw_growth) == raw_growth):
		var g_day: int = int(raw_growth)
		# BUG-1S-01 second-layer defense: never restore a future tribe growth day (> current_day)
		if g_day >= 1 and g_day <= 36500 and (current_day < 1 or g_day <= current_day):
			_last_tribe_growth_day = g_day
		else:
			_last_tribe_growth_day = -1
	else:
		_last_tribe_growth_day = -1

	var raw_diplo = data.get("last_diplomacy_days", {})
	if raw_diplo is Dictionary:
		for fid in raw_diplo.keys():
			if not (fid is String) or String(fid).is_empty():
				continue
			var d_val = raw_diplo[fid]
			if d_val is int or (d_val is float and not is_nan(d_val) and not is_inf(d_val) and floor(d_val) == d_val):
				var d: int = int(d_val)
				if d >= 1 and d <= 36500 and (current_day < 1 or d <= current_day):
					_last_diplomacy_days[String(fid)] = d

func modify_opinion(faction_id: String, delta: float) -> Dictionary:
	var fac: FactionData = get_faction(faction_id)
	if fac == null:
		return {"success": false, "reason": "Thế lực không tồn tại"}
	var prev_opinion: float = fac.opinion
	fac.change_opinion(delta)
	relation_changed.emit(fac.id, fac.opinion, fac.disposition)
	return {
		"success": true,
		"faction_id": fac.id,
		"previous_opinion": prev_opinion,
		"new_opinion": fac.opinion,
		"disposition": fac.disposition
	}

func send_gift(faction_id: String, resource_id: String, amount: int, resource_mgr: Object) -> Dictionary:
	var fac: FactionData = get_faction(faction_id)
	if fac == null:
		return {"success": false, "reason": "Thế lực không tồn tại"}
	# MISS-01: Block gifts to non-active factions (eliminated / in_exile / invalid) before resource check or deduction.
	if not FactionData.VALID_EXISTENCE_STATUSES.has(fac.existence_status) or fac.existence_status != FactionData.STATUS_ACTIVE:
		return {"success": false, "reason": "Không thể gửi quà tặng cho thế lực không còn hoạt động (%s)" % fac.existence_status}
		
	if amount <= 0:
		return {"success": false, "reason": "Số lượng quà tặng không hợp lệ"}
		
	if resource_mgr != null:
		var has_res: bool = false
		if resource_mgr.has_method("has_resource"):
			has_res = resource_mgr.has_resource(resource_id, amount)
		elif resource_mgr.has_method("get_available_stock"):
			has_res = resource_mgr.get_available_stock(resource_id) >= amount
		if not has_res:
			return {"success": false, "reason": "Không đủ tài nguyên trong kho"}
		resource_mgr.call("consume_resource", resource_id, amount)
		
	# Opinion calculation based on gift value
	var value_per_unit := 1.0
	match resource_id:
		EconomyConfig.RES_GOLD: value_per_unit = 0.3
		EconomyConfig.RES_CRYSTAL: value_per_unit = 2.0
		EconomyConfig.RES_METAL: value_per_unit = 1.0
		EconomyConfig.RES_HERBS: value_per_unit = 0.8
		EconomyConfig.RES_FOOD: value_per_unit = 0.4
		EconomyConfig.RES_WOOD: value_per_unit = 0.25
		_: value_per_unit = 0.3
		
	var op_gain: float = clampf(amount * value_per_unit, 5.0, 35.0)
	fac.change_opinion(op_gain)
	relation_changed.emit(fac.id, fac.opinion, fac.disposition)
	
	return {"success": true, "opinion_gain": op_gain, "new_opinion": fac.opinion}

func propose_treaty(faction_id: String, treaty_type: String) -> Dictionary:
	var fac: FactionData = get_faction(faction_id)
	if fac == null:
		return {"success": false, "reason": "Thế lực không tồn tại"}
	if not FactionData.VALID_EXISTENCE_STATUSES.has(fac.existence_status):
		return {"success": false, "reason": "Trạng thái tồn tại của thế lực không hợp lệ (%s)" % fac.existence_status}
		
	match treaty_type:
		"nap":
			# MISS-01: Only active factions may sign new non-aggression pacts.
			if fac.existence_status != FactionData.STATUS_ACTIVE:
				return {"success": false, "reason": "Không thể ký hiệp ước không xâm phạm với thế lực không còn hoạt động (%s)" % fac.existence_status}
			if fac.is_at_war:
				return {"success": false, "reason": "Đang có chiến tranh, không thể ký hiệp ước bất tương xâm phạm"}
			if fac.opinion < 0.0:
				return {"success": false, "reason": "Mối quan hệ quá thấp (cần thiện cảm >= 0)"}
			fac.sign_nap()
			treaty_signed.emit(fac.id, "nap")
			relation_changed.emit(fac.id, fac.opinion, fac.disposition)
			return {"success": true, "message": "Đã ký kết Hiệp Ước Không Xâm Phạm thành công"}
			
		"alliance":
			# MISS-01: Only active factions may sign new defensive alliances.
			if fac.existence_status != FactionData.STATUS_ACTIVE:
				return {"success": false, "reason": "Không thể ký liên minh với thế lực không còn hoạt động (%s)" % fac.existence_status}
			if fac.is_at_war:
				return {"success": false, "reason": "Đang có chiến tranh"}
			if fac.opinion < 60.0:
				return {"success": false, "reason": "Thiện cảm chưa đủ cao (cần thiện cảm >= 60)"}
			fac.sign_alliance()
			treaty_signed.emit(fac.id, "alliance")
			relation_changed.emit(fac.id, fac.opinion, fac.disposition)
			return {"success": true, "message": "Đã ký kết Liên Minh Phòng Thủ thành công"}
			
		"peace":
			# MISS-01: Active and in-exile factions may sign peace to resolve an ongoing war; eliminated factions cannot.
			if fac.existence_status == FactionData.STATUS_ELIMINATED:
				return {"success": false, "reason": "Không thể ký hiệp định đình chiến với thế lực đã bị tiêu diệt (%s)" % fac.existence_status}
			if not fac.is_at_war:
				return {"success": false, "reason": "Hai bên đang trong trạng thái hòa bình"}
			fac.sign_peace()
			peace_signed.emit(fac.id)
			relation_changed.emit(fac.id, fac.opinion, fac.disposition)
			return {"success": true, "message": "Đã ký hiệp định đình chiến thành công"}
			
		_:
			return {"success": false, "reason": "Loại hiệp ước không xác định"}

func declare_war(faction_id: String) -> Dictionary:
	var fac: FactionData = get_faction(faction_id)
	if fac == null:
		return {"success": false, "reason": "Thế lực không tồn tại"}
	# MISS-01: Block war declaration against non-active factions.
	if not FactionData.VALID_EXISTENCE_STATUSES.has(fac.existence_status) or fac.existence_status != FactionData.STATUS_ACTIVE:
		return {"success": false, "reason": "Không thể tuyên chiến với thế lực không còn hoạt động (%s)" % fac.existence_status}
	if fac.is_at_war:
		return {"success": false, "reason": "Đã ở trong tình trạng chiến tranh"}
		
	fac.declare_war()
	war_declared.emit(fac.id)
	relation_changed.emit(fac.id, fac.opinion, fac.disposition)
	return {"success": true, "message": "Đã tuyên chiến với %s!" % fac.name}

func has_emerging_power() -> bool:
	for fac in _factions.values():
		if fac != null and fac.type == ASCENSION_NEW_TYPE:
			return true
	return false

func can_emerging_faction_ascend(day: int) -> bool:
	var tribe: FactionData = get_faction("neutral_tribe")
	if tribe == null or tribe.type != "neutral_tribe":
		return false
	if tribe.existence_status != FactionData.STATUS_ACTIVE:
		return false
	if has_emerging_power():
		return false
	if tribe.population < ASCENSION_MIN_POPULATION:
		return false
	if day < ASCENSION_MIN_DAY:
		return false
	if tribe.stability < ASCENSION_MIN_STABILITY:
		return false
	var wood: int = int(tribe.resources.get(EconomyConfig.RES_WOOD, 0))
	if wood < ASCENSION_MIN_WOOD:
		return false
	var herbs: int = int(tribe.resources.get(EconomyConfig.RES_HERBS, 0))
	if herbs < ASCENSION_MIN_HERBS:
		return false
	return true

## Simulation tick: checks periodic faction evolution (GDD 10.3), evaluates strategic intents (GDD 10.1, Package 1R),
## and executes bounded daily strategic actions (Package 1S).
func update_daily_simulation(day: int) -> void:
	var tribe_grew_today: bool = false
	var tribe_ascended_today: bool = false

	# 1. Check emerging faction ascent for neutral tribe (guarded against same-day replay)
	var tribe: FactionData = get_faction("neutral_tribe")
	if tribe != null and tribe.type == "neutral_tribe" and tribe.existence_status == FactionData.STATUS_ACTIVE:
		if day >= 1 and _last_tribe_growth_day < day:
			tribe.population += 1
			_last_tribe_growth_day = day
			tribe_grew_today = true
		if can_emerging_faction_ascend(day):
			tribe.type = ASCENSION_NEW_TYPE
			tribe.name = ASCENSION_NEW_NAME
			tribe.military_power = ASCENSION_NEW_MILITARY_POWER
			tribe.stability = ASCENSION_NEW_STABILITY
			tribe.strategic_goal = ASCENSION_NEW_STRATEGIC_GOAL
			tribe_ascended_today = true
			emerging_faction_ascended.emit(tribe.id, tribe.name)

	# 2. Evaluate and execute autonomous diplomatic decisions in stable deterministic order (Package 1T)
	# Executed BEFORE daily strategic economic actions so a faction declaring war today cannot also complete peacetime trade_expansion.
	var sorted_ids: Array = _factions.keys()
	sorted_ids.sort()
	for fid in sorted_ids:
		var fac_dip: FactionData = _factions[fid]
		if fac_dip == null:
			continue
		execute_faction_diplomatic_action(fid, day)

	# 3. Evaluate and execute daily strategic intents for active factions in stable deterministic order
	for fid in sorted_ids:
		var fac: FactionData = _factions[fid]
		if fac == null:
			continue
		var decision: Dictionary = FactionStrategyPlanner.evaluate_faction_intent(fac)
		if decision.get("eligible", false):
			strategic_intent_evaluated.emit(fid, decision)
			var exec_ctx: Dictionary = {}
			if fid == "neutral_tribe":
				if tribe_ascended_today:
					exec_ctx["ascended_today"] = true
				elif tribe_grew_today and fac.type == "neutral_tribe":
					exec_ctx["pre_ascension_growth_handled"] = true
					exec_ctx["population_delta"] = 1
			var exec_res: Dictionary = _strategy_executor.execute_intent(fac, decision, day, exec_ctx)
			strategic_intent_executed.emit(fid, exec_res)
