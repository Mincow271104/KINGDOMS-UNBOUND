class_name BattleCampaignManager
extends RefCounted
## Battle Campaign & Settlement Defense Raid Loop Manager for KINGDOMS UNBOUND.
## Manages raid scheduling, authoritative force construction, settlement defense battle
## execution via BattleResolver.resolve_settlement_battle(), and idempotent world state updates.

const BattleResolverScript = preload("res://scripts/combat/battle_resolver.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const FactionManagerScript = preload("res://scripts/factions/faction_manager.gd")

const INITIAL_RAID_DELAY_DAYS: int = 3
const SUBSEQUENT_RAID_INTERVAL_DAYS: int = 5
const MILITARY_POWER_PER_TROOP: float = 30.0
const MIN_ABSTRACT_TROOPS: int = 1
const MAX_ABSTRACT_TROOPS: int = 20

signal raid_scheduled(faction_id: String, scheduled_day: int, is_first: bool)
signal raid_cancelled(faction_id: String, reason: String)
signal battle_resolved(report: BattleResolver.BattleReport, raid_context: Dictionary)
signal offensive_campaign_resolved(report: BattleResolver.BattleReport, context: Dictionary)

var world_view: Node = null
var faction_mgr: FactionManager = null
var world_seed: int = 12345

# Dependency injection for headless / standalone unit testing
var _custom_world_data: WorldGenerator.WorldData = null
var _custom_citizen_list: Array = []
var _custom_resource_mgr: Object = null
var _custom_job_mgr: JobManager = null
var _custom_army_mgr: Object = null
var _custom_current_day: int = -1

# Persistent State:
# _pending_raids: faction_id -> {"scheduled_day": int, "raid_sequence": int}
var _pending_raids: Dictionary = {}
# _processed_raids: raid_id (String) -> true
var _processed_raids: Dictionary = {}
# In-flight guard to prevent re-entrant duplicate resolution
var _in_flight_raids: Dictionary = {}
var _in_flight_offensive: Dictionary = {}
var _offensive_campaign_sequence: int = 0

func _init(p_world_view: Node = null, p_faction_mgr: FactionManager = null, p_seed: int = 12345) -> void:
	world_view = p_world_view
	faction_mgr = p_faction_mgr
	world_seed = p_seed

	if faction_mgr != null:
		_connect_faction_signals()

func set_world_view(wv: Node) -> void:
	world_view = wv

func set_faction_manager(fm: FactionManager) -> void:
	if faction_mgr != null:
		_disconnect_faction_signals()
	faction_mgr = fm
	if faction_mgr != null:
		_connect_faction_signals()

func get_faction_manager() -> FactionManager:
	if faction_mgr != null:
		return faction_mgr
	if is_instance_valid(world_view) and world_view.get("faction_mgr") != null:
		return world_view.get("faction_mgr")
	return null

func set_custom_world_data(wd: WorldGenerator.WorldData) -> void:
	_custom_world_data = wd

func set_custom_citizen_list(cits: Array) -> void:
	_custom_citizen_list = cits

func set_custom_resource_manager(rm: Object) -> void:
	_custom_resource_mgr = rm

func set_custom_job_manager(jm: JobManager) -> void:
	_custom_job_mgr = jm

func set_custom_current_day(day: int) -> void:
	_custom_current_day = day

func _connect_faction_signals() -> void:
	if not faction_mgr.war_declared.is_connected(_on_faction_war_declared):
		faction_mgr.war_declared.connect(_on_faction_war_declared)
	if not faction_mgr.peace_signed.is_connected(_on_faction_peace_signed):
		faction_mgr.peace_signed.connect(_on_faction_peace_signed)

func _disconnect_faction_signals() -> void:
	if faction_mgr.war_declared.is_connected(_on_faction_war_declared):
		faction_mgr.war_declared.disconnect(_on_faction_war_declared)
	if faction_mgr.peace_signed.is_connected(_on_faction_peace_signed):
		faction_mgr.peace_signed.disconnect(_on_faction_peace_signed)

func _on_faction_war_declared(faction_id: String) -> void:
	var cur_day: int = get_current_day()
	schedule_raid(faction_id, cur_day + INITIAL_RAID_DELAY_DAYS, 1, true)

func _on_faction_peace_signed(faction_id: String) -> void:
	cancel_raid(faction_id, "Ký kết hòa bình")

func get_current_day() -> int:
	if _custom_current_day >= 0:
		return _custom_current_day
	if Engine.has_singleton("TimeManager"):
		var tm = Engine.get_singleton("TimeManager")
		return tm.get("current_day")
	if is_instance_valid(world_view) and world_view.is_inside_tree():
		var tm = world_view.get_node_or_null("/root/TimeManager")
		if tm != null:
			return tm.get("current_day")
	return 1

func get_world_data() -> WorldGenerator.WorldData:
	if _custom_world_data != null:
		return _custom_world_data
	if is_instance_valid(world_view):
		return world_view.get("world_data")
	return null

func get_citizen_list() -> Array:
	if not _custom_citizen_list.is_empty():
		return _custom_citizen_list
	if is_instance_valid(world_view):
		var cl = world_view.get("citizen_list")
		if cl != null:
			return cl
	return []

func get_job_manager() -> JobManager:
	if _custom_job_mgr != null:
		return _custom_job_mgr
	if is_instance_valid(world_view):
		return world_view.get("job_mgr")
	return null

func get_resource_manager() -> Object:
	if _custom_resource_mgr != null:
		return _custom_resource_mgr
	if Engine.has_singleton("ResourceManager"):
		return Engine.get_singleton("ResourceManager")
	if is_instance_valid(world_view) and world_view.is_inside_tree():
		return world_view.get_node_or_null("/root/ResourceManager")
	return null

func get_player_army_manager() -> Object:
	if _custom_army_mgr != null:
		return _custom_army_mgr
	if is_instance_valid(world_view):
		return world_view.get("player_army_mgr")
	return null

func set_custom_army_manager(mgr: Object) -> void:
	_custom_army_mgr = mgr

# -----------------------------------------------------------------------------
# B1. Raid Scheduling & Queries
# -----------------------------------------------------------------------------

func is_faction_eligible_to_raid(faction_id: String) -> bool:
	var fm: FactionManager = get_faction_manager()
	if fm == null:
		return false
	var fac: FactionData = fm.get_faction(faction_id)
	if fac == null:
		return false
	return fac.is_at_war and fac.military_power > 0.0

func has_pending_raid(faction_id: String) -> bool:
	return _pending_raids.has(faction_id)

func get_pending_raid(faction_id: String) -> Dictionary:
	return _pending_raids.get(faction_id, {}).duplicate()

func schedule_raid(faction_id: String, target_day: int, seq: int = 1, is_first: bool = false) -> bool:
	if not is_faction_eligible_to_raid(faction_id):
		return false

	_pending_raids[faction_id] = {
		"scheduled_day": target_day,
		"raid_sequence": seq
	}
	raid_scheduled.emit(faction_id, target_day, is_first)
	return true

func cancel_raid(faction_id: String, reason: String = "Cancelled") -> bool:
	if _pending_raids.has(faction_id):
		_pending_raids.erase(faction_id)
		raid_cancelled.emit(faction_id, reason)
		return true
	return false

# -----------------------------------------------------------------------------
# B2 & B3. Force Construction
# -----------------------------------------------------------------------------

func construct_attacking_force(fac: FactionData) -> Dictionary:
	if fac == null:
		return {"troops": 0, "equipment_tier": 1, "morale": 50.0, "terrain_multiplier": 1.0}

	var troops: int = 0
	if fac.military_power > 0.0:
		troops = clampi(int(round(fac.military_power / MILITARY_POWER_PER_TROOP)), MIN_ABSTRACT_TROOPS, MAX_ABSTRACT_TROOPS)

	var equip_tier: int = 2 if fac.type == "rival_military" else 1
	var morale: float = clampf(fac.stability, 20.0, 100.0)

	return {
		"troops": troops,
		"equipment_tier": equip_tier,
		"morale": morale,
		"terrain_multiplier": 1.0
	}

func get_eligible_guards() -> Array:
	var result: Array = []
	var wd = get_world_data()
	# Require active Barracks
	if not BuildingSystemScript.is_barracks_active(wd):
		return result

	var all_citizens = get_citizen_list()
	for cit in all_citizens:
		if is_instance_valid(cit):
			var is_alive: bool = cit.call("is_alive") if cit.has_method("is_alive") else (cit.get("health") > 0.0)
			if is_alive and cit.get("role") == "guard":
				result.append(cit)
	return result

func construct_defending_force() -> Dictionary:
	var army_mgr = get_player_army_manager()
	var army_soldiers: int = 0
	var army_morale: float = EconomyConfigScript.ARMY_MORALE_SUPPLIED
	var is_eligible: bool = true
	if army_mgr != null:
		if army_mgr.has_method("is_defense_eligible"):
			is_eligible = bool(army_mgr.call("is_defense_eligible"))
		elif army_mgr.has_method("is_garrisoned"):
			is_eligible = bool(army_mgr.call("is_garrisoned"))

	if is_eligible and army_mgr != null and army_mgr.has_method("get_army_count"):
		army_soldiers = maxi(0, int(army_mgr.call("get_army_count")))
		if army_mgr.has_method("get_combat_morale"):
			army_morale = float(army_mgr.call("get_combat_morale"))

	var guards: Array = get_eligible_guards()
	var guard_count: int = guards.size()
	var total_troops: int = army_soldiers + guard_count

	var avg_morale: float = 70.0
	if total_troops > 0:
		var total_morale_sum: float = 0.0
		if army_soldiers > 0:
			total_morale_sum += army_morale * float(army_soldiers)
		if guard_count > 0:
			for g in guards:
				total_morale_sum += float(g.get("morale"))
		avg_morale = clampf(total_morale_sum / float(total_troops), 20.0, 100.0)

	var def_resources: Dictionary = {}
	var rm = get_resource_manager()
	if rm != null and rm.has_method("get_available_stock"):
		for res_id in EconomyConfigScript.ALL_RESOURCES:
			var avail: int = rm.get_available_stock(res_id)
			if avail > 0:
				def_resources[res_id] = avail

	return {
		"troops": total_troops,
		"army_soldiers": army_soldiers,
		"guard_count": guard_count,
		"equipment_tier": 1,
		"morale": avg_morale,
		"terrain_multiplier": 1.0,
		"resources": def_resources
	}

# -----------------------------------------------------------------------------
# B4, C1..C4. Battle Execution and Idempotent World Mutation
# -----------------------------------------------------------------------------

func resolve_and_apply_raid(faction_id: String, current_day: int = -1) -> Dictionary:
	if current_day < 0:
		current_day = get_current_day()

	if not is_faction_eligible_to_raid(faction_id):
		cancel_raid(faction_id, "Thế lực không đủ điều kiện tấn công")
		return {"success": false, "reason": "Faction not eligible to raid"}

	var pending: Dictionary = _pending_raids.get(faction_id, {})
	if pending.is_empty():
		return {"success": false, "reason": "No pending raid for faction"}

	var sched_day: int = pending.get("scheduled_day", -1)
	if current_day < sched_day:
		return {"success": false, "reason": "Raid already processed or not due yet", "already_processed": true, "not_due": true}

	var seq: int = pending.get("raid_sequence", 1)
	var raid_id: String = "%s_day_%d_seq_%d" % [faction_id, sched_day, seq]

	# Guard against re-entrant duplicate execution or replay
	if _in_flight_raids.has(raid_id):
		return {"success": false, "reason": "Raid resolution already in-flight", "in_flight": true}

	if _processed_raids.has(raid_id):
		return {"success": false, "reason": "Raid already processed", "already_processed": true}

	var fm: FactionManager = get_faction_manager()
	var fac: FactionData = fm.get_faction(faction_id) if fm != null else null
	if fac == null:
		return {"success": false, "reason": "Faction data not found"}

	# Set in-flight guard before any operations begin
	_in_flight_raids[raid_id] = true

	var atk_force: Dictionary = construct_attacking_force(fac)
	var def_force: Dictionary = construct_defending_force()
	var wd = get_world_data()

	# Deterministic seed derivation using the effective resolution day
	var raid_seed: int = (world_seed * 31 + current_day * 101 + hash(faction_id) + seq * 17) & 0x7FFFFFFF

	# Call Package 1J authoritative resolver
	var report: BattleResolver.BattleReport = BattleResolverScript.resolve_settlement_battle(
		atk_force,
		def_force,
		wd,
		raid_seed
	)

	# Pre-validate plunder plan from actual available stock before mutations
	var plunder_plan: Dictionary = {}
	var rm = get_resource_manager()
	if report.victor == "attacker" and rm != null and not report.plunder_spoils.is_empty():
		for r_id in report.plunder_spoils:
			var requested_amt: int = int(report.plunder_spoils[r_id])
			if requested_amt > 0:
				var avail: int = 0
				if rm.has_method("get_available_stock"):
					avail = rm.call("get_available_stock", r_id)
				var to_deduct: int = mini(requested_amt, avail)
				if to_deduct > 0:
					plunder_plan[r_id] = to_deduct

	# Pre-validate defender casualties
	var total_def_casualties: int = maxi(0, report.defender_casualties)
	var army_casualties: int = 0
	var army_mgr = get_player_army_manager()
	var army_can_defend: bool = true
	if army_mgr != null:
		if army_mgr.has_method("is_defense_eligible"):
			army_can_defend = bool(army_mgr.call("is_defense_eligible"))
		elif army_mgr.has_method("is_garrisoned"):
			army_can_defend = bool(army_mgr.call("is_garrisoned"))

	if army_can_defend and army_mgr != null and army_mgr.has_method("get_army_count"):
		var cur_army: int = maxi(0, int(army_mgr.call("get_army_count")))
		army_casualties = mini(total_def_casualties, cur_army)
		if army_casualties > 0 and army_mgr.has_method("remove_casualties"):
			army_mgr.call("remove_casualties", army_casualties)

	var remaining_casualties: int = total_def_casualties - army_casualties
	var eligible_guards: Array = get_eligible_guards()
	eligible_guards.sort_custom(func(a, b): return String(a.get("citizen_id")) < String(b.get("citizen_id")))
	var casualties_to_take: int = mini(remaining_casualties, eligible_guards.size())
	var jm = get_job_manager()

	# C1. Apply Guard Casualties
	var guards_killed: Array[String] = []
	for i in range(casualties_to_take):
		var cit = eligible_guards[i]
		var c_id: String = cit.get("citizen_id")
		guards_killed.append(c_id)

		# Release active job safely and trigger citizen death lifecycle
		if cit.has_method("die"):
			cit.die("Tử trận khi bảo vệ định cư")
		else:
			if cit.get("active_job") != null and jm != null:
				jm.release_job(cit.active_job)
				cit.active_job = null

			# Update citizen status and mark deceased with combat reason
			cit.health = 0.0
			cit.status_reason = "Tử trận khi bảo vệ định cư"
			cit.current_state = 0 # State.IDLE
			if cit.get("current_path") != null:
				cit.current_path.clear()

			cit.citizen_died.emit(c_id)

		# Standalone test safety: ensure removal from custom citizen list if world_view signal not active
		if not _custom_citizen_list.is_empty():
			_custom_citizen_list.erase(cit)

	# C2. Apply Attacking Faction Losses
	var enemy_casualties: int = report.attacker_casualties
	var mil_loss: float = float(enemy_casualties) * MILITARY_POWER_PER_TROOP
	fac.military_power = maxf(0.0, fac.military_power - mil_loss)

	# C3. Apply Resource Plunder Transactionally
	var plundered_applied: Dictionary = {}
	if not plunder_plan.is_empty() and rm != null:
		if rm.has_method("reserve_cost") and rm.has_method("commit_cost"):
			var reserved: bool = rm.call("reserve_cost", plunder_plan)
			if reserved:
				rm.call("commit_cost", plunder_plan)
				plundered_applied = plunder_plan.duplicate()
			else:
				# Reservation failed (e.g. stock reserved by other orders or insufficient): fail closed
				plundered_applied = {}
		else:
			# ResourceManager does not provide full transaction API: fail closed
			plundered_applied = {}

	# C4. Schedule next raid or terminate campaign
	var next_scheduled_day: int = -1
	if fac.is_at_war and fac.military_power > 0.0:
		next_scheduled_day = current_day + SUBSEQUENT_RAID_INTERVAL_DAYS
		_pending_raids[faction_id] = {
			"scheduled_day": next_scheduled_day,
			"raid_sequence": seq + 1
		}
		raid_scheduled.emit(faction_id, next_scheduled_day, false)
	else:
		_pending_raids.erase(faction_id)
		if fac.military_power <= 0.0:
			raid_cancelled.emit(faction_id, "Quân lực đối phương đã bị tiêu diệt hoàn toàn")

	# C5. Apply Diplomatic Consequences (Package 1O)
	if fm != null:
		fm.modify_opinion(faction_id, -FactionManagerScript.OPINION_PENALTY_SETTLEMENT_RAID)
	elif fac != null:
		fac.change_opinion(-FactionManagerScript.OPINION_PENALTY_SETTLEMENT_RAID)

	var raid_context := {
		"raid_id": raid_id,
		"faction_id": faction_id,
		"faction_name": fac.name,
		"day": current_day,
		"scheduled_day": sched_day,
		"sequence": seq,
		"army_casualties": army_casualties,
		"guards_killed": guards_killed,
		"defender_casualties": army_casualties + guards_killed.size(),
		"enemy_casualties": enemy_casualties,
		"remaining_military_power": fac.military_power,
		"plundered_resources": plundered_applied,
		"next_raid_day": next_scheduled_day,
		"diplomatic_opinion_penalty": FactionManagerScript.OPINION_PENALTY_SETTLEMENT_RAID,
		"new_opinion": fac.opinion,
		"disposition": fac.disposition
	}

	# Mark processed, clear in-flight guard, and emit resolution signal
	_processed_raids[raid_id] = true
	_in_flight_raids.erase(raid_id)

	battle_resolved.emit(report, raid_context)

	return {
		"success": true,
		"raid_id": raid_id,
		"report": report,
		"context": raid_context
	}

## Called daily by WorldView on simulation day passed.
func process_daily_raids(current_day: int) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var factions_with_raids := _pending_raids.keys()
	factions_with_raids.sort()

	for fac_id in factions_with_raids:
		var pending: Dictionary = _pending_raids.get(fac_id, {})
		if pending.is_empty():
			continue
		var sched_day: int = pending.get("scheduled_day", -1)

		if sched_day <= current_day:
			if is_faction_eligible_to_raid(fac_id):
				var res = resolve_and_apply_raid(fac_id, current_day)
				results.append(res)
			else:
				cancel_raid(fac_id, "Thế lực không còn đủ điều kiện đột kích")

	return results

# -----------------------------------------------------------------------------
# Stage E. Persistence (Save / Load)
# -----------------------------------------------------------------------------

func serialize() -> Dictionary:
	return {
		"pending_raids": _pending_raids.duplicate(true),
		"processed_raids": _processed_raids.duplicate(true),
		"offensive_sequence": _offensive_campaign_sequence
	}

func deserialize(data: Dictionary) -> void:
	_pending_raids.clear()
	_processed_raids.clear()
	_in_flight_raids.clear()
	_in_flight_offensive.clear()
	_offensive_campaign_sequence = maxi(0, int(data.get("offensive_sequence", 0)))

	var raw_processed: Dictionary = data.get("processed_raids", {})
	for k in raw_processed:
		_processed_raids[String(k)] = bool(raw_processed[k])

	var raw_pending: Dictionary = data.get("pending_raids", {})
	for fac_id in raw_pending:
		var p_info: Dictionary = raw_pending[fac_id]
		# Sanitize against current faction status
		if is_faction_eligible_to_raid(fac_id):
			_pending_raids[fac_id] = {
				"scheduled_day": int(p_info.get("scheduled_day", 1)),
				"raid_sequence": int(p_info.get("raid_sequence", 1))
			}

# -----------------------------------------------------------------------------
# Stage F. Player-Led Abstract Offensive Campaigns (Package 1N)
# -----------------------------------------------------------------------------

func get_offensive_campaign_sequence() -> int:
	return _offensive_campaign_sequence

func set_offensive_campaign_sequence(seq: int) -> void:
	_offensive_campaign_sequence = maxi(0, seq)

func can_launch_offensive_campaign(target_faction_id: String) -> Dictionary:
	var fm = get_faction_manager()
	if fm == null:
		return {"can_attack": false, "reason": "Hệ thống thế lực chưa khởi tạo."}

	var fac: FactionData = fm.get_faction(target_faction_id)
	if fac == null:
		return {"can_attack": false, "reason": "Thế lực chỉ định không tồn tại."}

	if not fac.is_at_war:
		return {"can_attack": false, "reason": "Chưa tuyên chiến với %s. Chỉ có thể tấn công thế lực đang có chiến tranh." % fac.name}

	if fac.military_power <= 0.0:
		return {"can_attack": false, "reason": "Thế lực %s đã cạn kiệt quân lực, không còn lực lượng phòng thủ để giao chiến." % fac.name}

	var army_mgr = get_player_army_manager()
	if army_mgr == null:
		return {"can_attack": false, "reason": "Hệ thống quân đội hoàng gia chưa khởi tạo."}

	var soldier_count: int = int(army_mgr.call("get_army_count")) if army_mgr.has_method("get_army_count") else int(army_mgr.get("soldier_count"))
	if soldier_count <= 0:
		return {"can_attack": false, "reason": "Quân đội không có binh sĩ để tiến hành tấn công."}

	var m_state: int = int(army_mgr.call("get_movement_state")) if army_mgr.has_method("get_movement_state") else int(army_mgr.get("movement_state"))
	# MovementState: GARRISONED = 0, MARCHING = 1, IDLE_AT_FIELD = 2
	if m_state == 0: # GARRISONED
		return {"can_attack": false, "reason": "Quân đội đang đóng quân tại căn cứ. Cần hành quân dã chiến ra ngoài thành để tấn công."}
	elif m_state == 1: # MARCHING
		return {"can_attack": false, "reason": "Quân đội đang trong quá trình hành quân. Cần chờ đến nơi đóng trại dã chiến trước khi mở chiến dịch."}
	elif m_state != 2: # not IDLE_AT_FIELD
		return {"can_attack": false, "reason": "Trạng thái quân đội không hợp lệ để mở chiến dịch."}

	var cur_cell: Vector2i = army_mgr.call("get_current_cell") if army_mgr.has_method("get_current_cell") else Vector2i(-1, -1)
	var rally_cell: Vector2i = army_mgr.call("get_rally_cell") if army_mgr.has_method("get_rally_cell") else Vector2i(-1, -1)
	if cur_cell == rally_cell:
		return {"can_attack": false, "reason": "Quân đội đang ở tại vị trí căn cứ, không thể mở chiến dịch tấn công từ căn cứ."}

	return {"can_attack": true, "reason": "Quân đội sẵn sàng mở chiến dịch tấn công."}

func launch_offensive_campaign(target_faction_id: String, custom_seed: int = -1) -> Dictionary:
	var check: Dictionary = can_launch_offensive_campaign(target_faction_id)
	if not check.get("can_attack", false):
		return {"success": false, "reason": check.get("reason", "Không đủ điều kiện tấn công.")}

	# Guard against re-entrant duplicate execution
	if _in_flight_offensive.get(target_faction_id, false):
		return {"success": false, "reason": "Chiến dịch tấn công đang được xử lý.", "in_flight": true}

	_in_flight_offensive[target_faction_id] = true

	var fm = get_faction_manager()
	var fac: FactionData = fm.get_faction(target_faction_id) if fm != null else null
	var army_mgr = get_player_army_manager()

	# 1. Attacker Force (Player Army)
	var atk_troops: int = int(army_mgr.call("get_army_count")) if army_mgr.has_method("get_army_count") else int(army_mgr.get("soldier_count"))
	var atk_morale: float = float(army_mgr.call("get_combat_morale")) if army_mgr.has_method("get_combat_morale") else 70.0
	var atk_force: Dictionary = {
		"troops": atk_troops,
		"equipment_tier": 1,
		"morale": atk_morale,
		"terrain_multiplier": 1.0
	}

	# 2. Defender Force (Target Faction)
	var def_troops: int = clampi(int(round(fac.military_power / MILITARY_POWER_PER_TROOP)), MIN_ABSTRACT_TROOPS, MAX_ABSTRACT_TROOPS)
	var def_equip: int = 2 if fac.type == "rival_military" else 1
	var def_morale: float = clampf(fac.stability, 20.0, 100.0)
	var def_force: Dictionary = {
		"troops": def_troops,
		"equipment_tier": def_equip,
		"morale": def_morale,
		"fortification_level": 0,
		"terrain_multiplier": 1.0,
		"resources": {}
	}

	# 3. Deterministic Seed
	_offensive_campaign_sequence += 1
	var campaign_seed: int = custom_seed
	if campaign_seed < 0:
		var cur_day: int = get_current_day()
		campaign_seed = (world_seed * 37 + cur_day * 103 + hash(target_faction_id) + _offensive_campaign_sequence * 19) & 0x7FFFFFFF

	# 4. Resolve Battle without mutating caller force dictionaries
	var report: BattleResolver.BattleReport = BattleResolverScript.resolve_battle(
		atk_force.duplicate(true),
		def_force.duplicate(true),
		campaign_seed
	)

	# 5. Apply battle outcomes safely
	# 5a. Apply player casualties
	var player_lost: int = clampi(report.attacker_casualties, 0, atk_troops)
	if player_lost > 0 and army_mgr.has_method("remove_casualties"):
		army_mgr.call("remove_casualties", player_lost)

	# 5b. Apply enemy military power reduction
	var enemy_lost: int = clampi(report.defender_casualties, 0, def_troops)
	var mil_loss: float = float(enemy_lost) * MILITARY_POWER_PER_TROOP
	var prev_mil: float = fac.military_power
	fac.military_power = maxf(0.0, fac.military_power - mil_loss)

	# 5c. Apply Diplomatic Consequences (Package 1O)
	if fm != null:
		fm.modify_opinion(target_faction_id, -FactionManagerScript.OPINION_PENALTY_OFFENSIVE_CAMPAIGN)
	elif fac != null:
		fac.change_opinion(-FactionManagerScript.OPINION_PENALTY_OFFENSIVE_CAMPAIGN)

	_in_flight_offensive.erase(target_faction_id)

	# 6. Build context and emit signals
	var res_day: int = get_current_day()
	var context: Dictionary = {
		"is_offensive": true,
		"faction_id": target_faction_id,
		"faction_name": fac.name,
		"player_casualties": player_lost,
		"enemy_casualties": enemy_lost,
		"remaining_player_troops": int(army_mgr.call("get_army_count")) if army_mgr.has_method("get_army_count") else int(army_mgr.get("soldier_count")),
		"remaining_military_power": fac.military_power,
		"previous_military_power": prev_mil,
		"resolution_day": res_day,
		"sequence": _offensive_campaign_sequence,
		"seed": campaign_seed,
		"diplomatic_opinion_penalty": FactionManagerScript.OPINION_PENALTY_OFFENSIVE_CAMPAIGN,
		"new_opinion": fac.opinion,
		"disposition": fac.disposition
	}

	battle_resolved.emit(report, context)
	offensive_campaign_resolved.emit(report, context)

	return {
		"success": true,
		"report": report,
		"context": context
	}
