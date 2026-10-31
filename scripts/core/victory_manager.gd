class_name VictoryManager
extends RefCounted
## Authoritative Victory, Crisis, and Collapse Manager for KINGDOMS UNBOUND.
## Enforces continuous 5-day prosperity hold, deterministic collapse triggers, and summary reporting.

signal victory_progress_updated(hold_hours: float, target_hours: float)
signal victory_hold_reset(reason: String)
signal victory_achieved(summary_report: Dictionary)
signal crisis_warning_issued(warning_data: Dictionary)
signal collapse_triggered(summary_report: Dictionary)

const TARGET_VICTORY_HOLD_HOURS: float = 120.0 # 5 game days * 24 hours
const MAX_TOWNHALL_RUIN_HOURS: float = 72.0    # 3 game days * 24 hours
const MAX_ANARCHY_HOURS: float = 72.0          # 3 game days * 24 hours

const PROTECTED_GOLD_RESERVE: int = 1000
const GOLD_PER_LEGACY_POINT: int = 100
const MIN_CONVERSION_STABILITY: float = 80.0

# Victory condition thresholds (GDD 12.3 & GAME_RULES 7.1)
var min_population: int = 30
var min_food: int = 500
var min_treasury: int = 1000
var min_stability: float = 80.0
var min_morale: float = 75.0
var min_technologies: int = 3

# State tracking
var hold_hours_elapsed: float = 0.0
var is_victory_achieved: bool = false
var is_collapse_triggered: bool = false
var has_continued_after_victory: bool = false

var townhall_ruin_hours: float = 0.0
var anarchy_hours: float = 0.0

var peak_population: int = 24
var total_simulation_hours: float = 0.0
var primary_collapse_reason: String = ""
var major_events: Array[String] = []

# Legacy claiming protection (Master Prompt Phase 7 exit gate & Package 1Z)
var legacy_points_earned: int = 0
var is_legacy_claimed: bool = false
var is_treasury_converted: bool = false
var treasury_conversion_record: Dictionary = {}
var profile_mgr: RefCounted = null
var world_id: String = ""
var is_world_id_persisted: bool = false
var resource_mgr: Node = null

func calculate_stability(food_stock: int, treasury_stock: int, pop: int, housing_cap: int, avg_morale: float, town_hall_alive: bool) -> float:
	var stability: float = 0.0
	
	# 1. Town Hall governance factor
	if town_hall_alive:
		stability += 20.0
	else:
		stability -= 40.0
		
	# 2. Morale factor (0..40%)
	stability += clampf(avg_morale * 0.4, 0.0, 40.0)
	
	# 3. Food security factor (-25..+20%)
	if food_stock >= 100:
		stability += 20.0
	elif food_stock >= 30:
		stability += 10.0
	elif food_stock > 0:
		stability += 0.0
	else:
		stability -= 25.0 # Starvation chaos
		
	# 4. Housing security factor (-20..+20%)
	if housing_cap >= pop and pop > 0:
		stability += 20.0
	else:
		stability -= 20.0 # Homelessness / overcrowding
		
	# 5. Treasury solvency factor (-15..+20%)
	if treasury_stock >= 500:
		stability += 20.0
	elif treasury_stock >= 100:
		stability += 10.0
	elif treasury_stock > 0:
		stability += 0.0
	else:
		stability -= 15.0 # Empty treasury
		
	return clampf(stability, 0.0, 100.0)

func evaluate_prosperity_conditions(pop: int, food: int, treasury: int, stability: float, morale: float, techs_unlocked: int) -> Dictionary:
	var conditions: Dictionary = {
		"population": {"met": pop >= min_population, "current": pop, "target": min_population, "name": "Dân số (>= 30)"},
		"food": {"met": food >= min_food, "current": food, "target": min_food, "name": "Lương thực (>= 500)"},
		"treasury": {"met": treasury >= min_treasury, "current": treasury, "target": min_treasury, "name": "Ngân khố (>= 1000)"},
		"stability": {"met": stability >= min_stability, "current": stability, "target": min_stability, "name": "Độ ổn định (>= 80%)"},
		"morale": {"met": morale >= min_morale, "current": morale, "target": min_morale, "name": "Sĩ khí trung bình (>= 75%)"},
		"technologies": {"met": techs_unlocked >= min_technologies, "current": techs_unlocked, "target": min_technologies, "name": "Công nghệ (>= 3)"}
	}
	
	var all_met: bool = true
	var failed_conditions: Array[String] = []
	for k in conditions:
		if not conditions[k]["met"]:
			all_met = false
			failed_conditions.append(conditions[k]["name"])
			
	return {
		"all_met": all_met,
		"conditions": conditions,
		"failed": failed_conditions
	}

func tick_hourly(pop: int, food: int, treasury: int, stability: float, morale: float, techs_unlocked: int, town_hall_alive: bool, buildings_count: int = 0) -> Dictionary:
	if is_collapse_triggered:
		return {"status": "collapsed"}
		
	total_simulation_hours += 1.0
	if pop > peak_population:
		peak_population = pop

	# 1. Evaluate Terminal Collapse Triggers
	# Condition A: Extinction (pop <= 0)
	if pop <= 0:
		is_collapse_triggered = true
		primary_collapse_reason = "Tuyệt chủng: Toàn bộ cư dân đã qua đời vì nạn đói hoặc kiệt sức."
		var report := generate_summary_report("COLLAPSE", pop, food, treasury, stability, morale, techs_unlocked, buildings_count)
		collapse_triggered.emit(report)
		return {"status": "collapse", "reason": primary_collapse_reason, "report": report}

	# Condition B: Town Hall Ruin (> 72 hours destroyed)
	if not town_hall_alive:
		townhall_ruin_hours += 1.0
		if townhall_ruin_hours >= MAX_TOWNHALL_RUIN_HOURS:
			is_collapse_triggered = true
			primary_collapse_reason = "Mất thủ đô: Tòa Thị Chính đã bị phá hủy quá 3 ngày (72 giờ) mà không được tái thiết."
			var report := generate_summary_report("COLLAPSE", pop, food, treasury, stability, morale, techs_unlocked, buildings_count)
			collapse_triggered.emit(report)
			return {"status": "collapse", "reason": primary_collapse_reason, "report": report}
	else:
		townhall_ruin_hours = 0.0

	# Condition C: Prolonged Anarchy (stability == 0% for > 72 hours)
	if stability <= 0.0:
		anarchy_hours += 1.0
		if anarchy_hours >= MAX_ANARCHY_HOURS:
			is_collapse_triggered = true
			primary_collapse_reason = "Vô chính phủ kéo dài: Mức độ ổn định duy trì ở mức 0% liên tục trong 3 ngày (72 giờ)."
			var report := generate_summary_report("COLLAPSE", pop, food, treasury, stability, morale, techs_unlocked, buildings_count)
			collapse_triggered.emit(report)
			return {"status": "collapse", "reason": primary_collapse_reason, "report": report}
	else:
		anarchy_hours = 0.0

	# 2. Check Crisis / Decline warnings
	_evaluate_crises(food, treasury, morale, stability, town_hall_alive)

	# 3. Evaluate Prosperity Victory Continuous Hold
	var victory_eval := evaluate_prosperity_conditions(pop, food, treasury, stability, morale, techs_unlocked)
	if victory_eval["all_met"]:
		hold_hours_elapsed += 1.0
		victory_progress_updated.emit(hold_hours_elapsed, TARGET_VICTORY_HOLD_HOURS)
		if hold_hours_elapsed >= TARGET_VICTORY_HOLD_HOURS and not is_victory_achieved:
			is_victory_achieved = true
			legacy_points_earned = 100
			if profile_mgr != null and profile_mgr.has_method("unlock_achievement"):
				profile_mgr.unlock_achievement("prosperity_victory", world_id)
			var report := generate_summary_report("VICTORY", pop, food, treasury, stability, morale, techs_unlocked, buildings_count)
			victory_achieved.emit(report)
			return {"status": "victory", "report": report}
	else:
		if hold_hours_elapsed > 0.0:
			var reason_str: String = "Điều kiện không còn thỏa mãn: " + ", ".join(victory_eval["failed"])
			hold_hours_elapsed = 0.0
			victory_hold_reset.emit(reason_str)

	return {
		"status": "ongoing",
		"hold_hours": hold_hours_elapsed,
		"hold_days": hold_hours_elapsed / 24.0,
		"victory_eval": victory_eval
	}

func _evaluate_crises(food: int, treasury: int, morale: float, stability: float, town_hall_alive: bool) -> void:
	if not town_hall_alive:
		crisis_warning_issued.emit({
			"severity": "emergency",
			"title": "TÒA THỊ CHÍNH BỊ PHÁ HỦY!",
			"message": "Trung tâm quản trị đã sụp đổ! Thời gian tái thiết còn lại: %.1f giờ trước khi vương quốc tan rã." % (MAX_TOWNHALL_RUIN_HOURS - townhall_ruin_hours),
			"recommended_action": "Xây dựng lại Tòa Thị Chính ngay lập tức!"
		})
	elif stability <= 0.0:
		# MISS-02 fix: Evaluate critical 72h anarchy collapse countdown BEFORE starvation warning so collapse risk is never masked when food <= 0 also drives stability to 0.
		crisis_warning_issued.emit({
			"severity": "critical",
			"title": "BẤT ỔN NGHIÊM TRỌNG (0%)",
			"message": "Xã hội rơi vào hỗn loạn. Còn %.1f giờ trước khi sụp đổ hoàn toàn." % (MAX_ANARCHY_HOURS - anarchy_hours),
			"recommended_action": "Cung cấp đầy đủ nhà ở, lương thực và nâng cao tinh thần người dân."
		})
	elif food <= 0:
		crisis_warning_issued.emit({
			"severity": "critical",
			"title": "NẠN ĐÓI TOÀN DIỆN!",
			"message": "Kho lương thực đã cạn sạch! Sức khỏe cư dân đang suy giảm 5%/ngày.",
			"recommended_action": "Khẩn cấp bổ sung thêm nông dân hoặc mua lương thực từ thương nhân!"
		})
	elif food < 30:
		crisis_warning_issued.emit({
			"severity": "medium",
			"title": "LƯƠNG THỰC BÁO ĐỘNG",
			"message": "Kho lương thực chỉ còn %d đơn vị, nguy cơ cạn kiệt trong thời gian ngắn." % food,
			"recommended_action": "Mở rộng nông trại và đảm bảo người vận chuyển hoạt động hiệu quả."
		})
	elif treasury <= 0:
		crisis_warning_issued.emit({
			"severity": "medium",
			"title": "NGÂN KHỐ CẠN KIỆT",
			"message": "Ngân khố quốc gia không còn tiền vàng để chi trả hoặc giao thương.",
			"recommended_action": "Khai thác vàng hoặc bán tài nguyên thừa cho thương đoàn."
		})
	elif morale < 20.0:
		crisis_warning_issued.emit({
			"severity": "medium",
			"title": "TINH THẦN SUY SỤP",
			"message": "Tinh thần người dân đang ở mức rất thấp (%.1f%%)." % morale,
			"recommended_action": "Cung cấp đủ lương thực và nâng cấp chỗ ở để cải thiện tinh thần."
		})

func record_event(event_description: String) -> void:
	major_events.append(event_description)

static func is_valid_world_id(wid: String) -> bool:
	var clean := wid.strip_edges()
	if clean.is_empty():
		return false
	var parts := clean.split("_")
	# Legacy seed-only format: "world_<integer>"
	if parts.size() == 2 and parts[0] == "world" and parts[1].is_valid_int():
		return false
	return true

func get_canonical_victory_reward_id() -> String:
	var clean_id := world_id.strip_edges()
	if clean_id.is_empty():
		return ""
	return "victory_" + clean_id

func is_reward_claimable() -> bool:
	if is_legacy_claimed:
		return false
	if not is_victory_achieved:
		return false
	if legacy_points_earned <= 0:
		return false
	if not is_world_id_persisted:
		return false
	if profile_mgr == null:
		return false
	if not profile_mgr.has_method("is_available") or not profile_mgr.has_method("is_reward_claimed") or not profile_mgr.has_method("claim_reward"):
		return false
	if not profile_mgr.is_available():
		return false
	if not is_valid_world_id(world_id):
		return false
	var canonical_id := get_canonical_victory_reward_id()
	if canonical_id.is_empty():
		return false
	if profile_mgr.is_reward_claimed(canonical_id):
		is_legacy_claimed = true
		return false
	return not is_legacy_claimed

func claim_legacy_reward(_deprecated_custom_reward_id: String = "") -> int:
	if is_legacy_claimed:
		return 0
	if not is_victory_achieved:
		return 0
	if legacy_points_earned <= 0:
		return 0
	if not is_world_id_persisted:
		return 0
	if profile_mgr == null:
		return 0
	if not profile_mgr.has_method("is_available") or not profile_mgr.has_method("is_reward_claimed") or not profile_mgr.has_method("claim_reward"):
		return 0
	if not profile_mgr.is_available():
		return 0
	if not is_valid_world_id(world_id):
		return 0
	var canonical_id := get_canonical_victory_reward_id()
	if canonical_id.is_empty():
		return 0
	if profile_mgr.is_reward_claimed(canonical_id):
		is_legacy_claimed = true
		return 0
	var res: Dictionary = profile_mgr.claim_reward(canonical_id, "victory", legacy_points_earned, world_id.strip_edges())
	if res.get("success", false):
		is_legacy_claimed = true
		return int(res.get("points_awarded", 0))
	else:
		if res.get("reason", "") == "already_claimed":
			is_legacy_claimed = true
		return 0

# -----------------------------------------------------------------------------
# Package 2C — Surplus Treasury Conversion & Victory Settlement Integration
# -----------------------------------------------------------------------------

static func calculate_treasury_conversion(treasury_gold: int, stability: float) -> Dictionary:
	if stability < MIN_CONVERSION_STABILITY:
		return {
			"eligible": false,
			"reason": "stability_too_low",
			"explanation": "Độ ổn định khi quyết toán chưa đạt mức tối thiểu (%.2f%% < %.1f%%)." % [stability, MIN_CONVERSION_STABILITY],
			"original_gold": treasury_gold,
			"protected_reserve": PROTECTED_GOLD_RESERVE,
			"surplus_gold": 0,
			"legacy_awarded": 0,
			"gold_deducted": 0,
			"remaining_gold": treasury_gold,
			"status": "ineligible_stability"
		}

	var surplus_gold: int = maxi(0, treasury_gold - PROTECTED_GOLD_RESERVE)
	var legacy_awarded: int = surplus_gold / GOLD_PER_LEGACY_POINT
	var gold_deducted: int = legacy_awarded * GOLD_PER_LEGACY_POINT
	var remaining_gold: int = treasury_gold - gold_deducted

	var is_eligible: bool = true
	var reason: String = "ok"
	var explanation: String = ""
	var status: String = "ready"

	if surplus_gold <= 0:
		is_eligible = false
		reason = "no_surplus"
		explanation = "Ngân khố không vượt quá mức dự trữ an toàn (1.000 Vàng)."
		status = "zero_surplus"
	elif legacy_awarded <= 0:
		is_eligible = false
		reason = "surplus_below_conversion_threshold"
		explanation = "Vàng thặng dư (%d) chưa đủ mức quy đổi tối thiểu (100 Vàng)." % surplus_gold
		status = "zero_surplus"
	else:
		explanation = "Quy đổi %d Vàng thặng dư thành +%d điểm Di Sản (Tỷ lệ 100:1)." % [gold_deducted, legacy_awarded]

	return {
		"eligible": is_eligible,
		"reason": reason,
		"explanation": explanation,
		"original_gold": treasury_gold,
		"protected_reserve": PROTECTED_GOLD_RESERVE,
		"surplus_gold": surplus_gold,
		"legacy_awarded": legacy_awarded,
		"gold_deducted": gold_deducted,
		"remaining_gold": remaining_gold,
		"status": status
	}

func is_treasury_converted_or_settled() -> bool:
	if is_treasury_converted:
		return true
	var mgr = profile_mgr
	if mgr == null:
		var LegacyProfileManagerScript = load("res://scripts/legacy/legacy_profile_manager.gd")
		if LegacyProfileManagerScript != null and LegacyProfileManagerScript.has_method("get_instance"):
			mgr = LegacyProfileManagerScript.get_instance()
	if mgr != null and mgr.has_method("has_treasury_conversion"):
		if mgr.has_treasury_conversion(world_id):
			is_treasury_converted = true
			if treasury_conversion_record.is_empty() and mgr.has_method("get_treasury_conversion"):
				treasury_conversion_record = mgr.get_treasury_conversion(world_id)
			return true
	return false

func get_active_treasury_conversion_record() -> Dictionary:
	if not treasury_conversion_record.is_empty():
		return treasury_conversion_record.duplicate(true)
	var mgr = profile_mgr
	if mgr == null:
		var LegacyProfileManagerScript = load("res://scripts/legacy/legacy_profile_manager.gd")
		if LegacyProfileManagerScript != null and LegacyProfileManagerScript.has_method("get_instance"):
			mgr = LegacyProfileManagerScript.get_instance()
	if mgr != null and mgr.has_method("get_treasury_conversion"):
		var rec: Dictionary = mgr.get_treasury_conversion(world_id)
		if not rec.is_empty():
			treasury_conversion_record = rec
			return rec.duplicate(true)
	return {}

func preview_treasury_conversion(treasury_gold: int, stability: float) -> Dictionary:
	if is_treasury_converted_or_settled():
		var rec := get_active_treasury_conversion_record()
		rec["already_converted"] = true
		return rec

	if not is_victory_achieved:
		return {
			"eligible": false,
			"reason": "victory_not_achieved",
			"explanation": "Chưa đạt Chiến Thắng Thịnh Vượng.",
			"original_gold": treasury_gold,
			"protected_reserve": PROTECTED_GOLD_RESERVE,
			"surplus_gold": 0,
			"legacy_awarded": 0,
			"gold_deducted": 0,
			"remaining_gold": treasury_gold,
			"status": "victory_not_achieved"
		}

	if is_collapse_triggered:
		return {
			"eligible": false,
			"reason": "collapsed",
			"explanation": "Vương quốc đã sụp đổ, không áp dụng quy đổi ngân khố.",
			"original_gold": treasury_gold,
			"protected_reserve": PROTECTED_GOLD_RESERVE,
			"surplus_gold": 0,
			"legacy_awarded": 0,
			"gold_deducted": 0,
			"remaining_gold": treasury_gold,
			"status": "collapsed"
		}

	return calculate_treasury_conversion(treasury_gold, stability)

func finalize_victory_settlement(resource_mgr_override = null, stability_override: float = -1.0) -> Dictionary:
	var rm = resource_mgr_override if resource_mgr_override != null else resource_mgr
	if rm == null and Engine.get_main_loop() != null:
		var root_node = Engine.get_main_loop().root
		if root_node != null:
			rm = root_node.get_node_or_null("ResourceManager")

	var res_dict: Dictionary = {
		"success": false,
		"victory_claimed": is_legacy_claimed,
		"victory_points_awarded": 0,
		"treasury_converted": is_treasury_converted_or_settled(),
		"treasury_points_awarded": 0,
		"total_legacy_awarded": 0,
		"gold_deducted": 0,
		"treasury_conversion": {},
		"reason": ""
	}

	if not is_victory_achieved:
		res_dict["reason"] = "victory_not_achieved"
		return res_dict

	if is_collapse_triggered:
		res_dict["reason"] = "collapse_triggered"
		return res_dict

	if not is_world_id_persisted:
		res_dict["reason"] = "world_not_persisted"
		return res_dict

	if not is_valid_world_id(world_id):
		res_dict["reason"] = "invalid_world_id"
		return res_dict

	if profile_mgr == null or not profile_mgr.has_method("is_available") or not profile_mgr.is_available():
		res_dict["reason"] = "profile_unavailable"
		return res_dict

	# 1. Claim base victory reward (100 LP) if not already claimed
	var vic_pts: int = 0
	if not is_legacy_claimed:
		vic_pts = claim_legacy_reward()
		res_dict["victory_points_awarded"] = vic_pts
		res_dict["victory_claimed"] = is_legacy_claimed

	# 2. Process Surplus Treasury Conversion
	if is_treasury_converted_or_settled():
		res_dict["treasury_converted"] = true
		res_dict["treasury_conversion"] = get_active_treasury_conversion_record()
		res_dict["success"] = (vic_pts > 0)
		res_dict["total_legacy_awarded"] = vic_pts
		if vic_pts == 0:
			res_dict["reason"] = "already_settled"
		return res_dict

	# Determine treasury gold and stability
	var treasury_gold: int = 0
	if rm != null and rm.has_method("get_available_stock"):
		treasury_gold = rm.get_available_stock("gold")
	elif rm != null and rm.get("available_resources") is Dictionary:
		treasury_gold = rm.available_resources.get("gold", 0)

	var current_stab: float = 85.0
	if stability_override >= 0.0:
		current_stab = stability_override

	var conv_res: Dictionary = profile_mgr.convert_surplus_treasury(
		treasury_gold,
		current_stab,
		world_id.strip_edges(),
		is_victory_achieved
	)

	res_dict["treasury_conversion"] = conv_res

	if conv_res.get("converted", false) == true:
		var gold_to_deduct: int = int(conv_res.get("gold_deducted", 0))
		var pts_awarded: int = int(conv_res.get("legacy_awarded", 0))
		res_dict["treasury_points_awarded"] = pts_awarded
		res_dict["gold_deducted"] = gold_to_deduct
		res_dict["treasury_converted"] = true
		is_treasury_converted = true
		treasury_conversion_record = conv_res.get("record", {})

		# Deduct gold actually converted
		if gold_to_deduct > 0 and rm != null and rm.has_method("consume_resource"):
			rm.consume_resource("gold", gold_to_deduct)

		res_dict["success"] = true
		res_dict["total_legacy_awarded"] = vic_pts + pts_awarded
	else:
		if conv_res.get("success", false) == true:
			# Clean zero-surplus transaction recorded in profile
			is_treasury_converted = true
			treasury_conversion_record = conv_res.get("record", {})
			res_dict["treasury_converted"] = true
			res_dict["success"] = true
			res_dict["total_legacy_awarded"] = vic_pts
		else:
			res_dict["success"] = (vic_pts > 0)
			res_dict["total_legacy_awarded"] = vic_pts
			res_dict["reason"] = conv_res.get("reason", "conversion_failed")

	return res_dict

func generate_summary_report(outcome: String, pop: int, food: int, treasury: int, stability: float, morale: float, techs_unlocked: int, buildings_count: int) -> Dictionary:
	var days: int = int(total_simulation_hours / 24.0)
	var hours: int = int(total_simulation_hours) % 24

	var claimed = is_legacy_claimed
	var canonical_id = get_canonical_victory_reward_id()
	if not canonical_id.is_empty() and profile_mgr != null and profile_mgr.has_method("is_reward_claimed"):
		if profile_mgr.is_reward_claimed(canonical_id):
			claimed = true
			is_legacy_claimed = true

	var tc_preview = preview_treasury_conversion(treasury, stability)
	var tc_done = is_treasury_converted_or_settled()
	
	return {
		"outcome": outcome,
		"days_survived": days,
		"hours_survived": hours,
		"peak_population": peak_population,
		"final_population": pop,
		"food_reserve": food,
		"treasury": treasury,
		"stability": stability,
		"morale": morale,
		"technologies_unlocked": techs_unlocked,
		"buildings_count": buildings_count,
		"primary_cause": primary_collapse_reason if outcome == "COLLAPSE" else "Duy trì thịnh vượng xuất sắc trong 5 ngày liên tục",
		"major_events": major_events.duplicate(),
		"legacy_points": legacy_points_earned,
		"legacy_claimed": claimed,
		"world_id": world_id,
		"is_treasury_converted": tc_done,
		"treasury_conversion": tc_preview
	}
