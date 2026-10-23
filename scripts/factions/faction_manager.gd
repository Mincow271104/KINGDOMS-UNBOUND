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

signal relation_changed(faction_id: String, new_opinion: float, disposition: int)
signal treaty_signed(faction_id: String, treaty_type: String)
signal war_declared(faction_id: String)
signal peace_signed(faction_id: String)
signal emerging_faction_ascended(faction_id: String, new_name: String)
signal strategic_intent_evaluated(faction_id: String, intent_data: Dictionary)
signal strategic_intent_executed(faction_id: String, execution_result: Dictionary)

var _factions: Dictionary = {} # id -> FactionData
var _strategy_executor: FactionStrategyExecutor = FactionStrategyExecutor.new()
var _last_tribe_growth_day: int = -1

func _init() -> void:
	_initialize_factions()

func _initialize_factions() -> void:
	_factions.clear()
	if _strategy_executor != null:
		_strategy_executor.reset_state()
	_last_tribe_growth_day = -1
	
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
	return out

func deserialize_executor_state(data: Dictionary, current_day: int = -1) -> void:
	if _strategy_executor == null:
		_strategy_executor = FactionStrategyExecutor.new()
	_strategy_executor.deserialize(data, current_day)
	if data.is_empty():
		_last_tribe_growth_day = -1
		return
	var raw_growth = data.get("last_tribe_growth_day", -1)
	if raw_growth is int or (raw_growth is float and not is_nan(raw_growth) and not is_inf(raw_growth) and floor(raw_growth) == raw_growth):
		var g_day: int = int(raw_growth)
		if g_day >= 1 and g_day <= 36500:
			_last_tribe_growth_day = g_day
		else:
			_last_tribe_growth_day = -1
	else:
		_last_tribe_growth_day = -1

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

	# 2. Evaluate and execute daily strategic intents for active factions in stable deterministic order
	var sorted_ids: Array = _factions.keys()
	sorted_ids.sort()
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
