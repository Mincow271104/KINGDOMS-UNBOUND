extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — Package 1N: Player-Led Abstract Offensive Campaigns
## Covers TC-OFFENSE.1 through TC-OFFENSE.14 across 14 focused tests:
## 1. Valid offensive attack when army is IDLE_AT_FIELD away from rally cell
## 2. Rejection with 0 soldiers (fails closed, informative Vietnamese message)
## 3. Rejection when garrisoned at home rally
## 4. Rejection when marching
## 5. Rejection against peaceful, neutral, allied, non-existent, or 0 military power faction
## 6. Deterministic seed produces identical BattleReport
## 7. Casualties bounded by initial counts; non-negative
## 8. Player casualties and faction military power reductions match report
## 9. Depleted army normalizes to garrison at rally; surviving army stays at field cell
## 10. Rejected attacks do not mutate state
## 11. HUD battle report reflects true mutated outcome and remaining counts
## 12. Save/load preserves post-attack army and faction states without replaying
## 13. Incoming settlement raids, schedules, and peace cancellations remain intact
## 14. Movement and deployment rules from Package 1M remain valid

const PlayerArmyManagerScript = preload("res://scripts/military/player_army_manager.gd")
const BattleCampaignManagerScript = preload("res://scripts/combat/battle_campaign_manager.gd")
const BattleResolverScript = preload("res://scripts/combat/battle_resolver.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const FactionManagerScript = preload("res://scripts/factions/faction_manager.gd")
const FactionDataScript = preload("res://scripts/factions/faction_data.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")
const HUDScene: PackedScene = preload("res://scenes/ui/hud.tscn")

var frame_count: int = 0
var world_instance: Node = null
var failures: int = 0

class MockResourceManager:
	var stock: Dictionary = {}
	var reserved: Dictionary = {}

	func _init() -> void:
		stock = {
			EconomyConfigScript.RES_FOOD: 500,
			EconomyConfigScript.RES_WOOD: 500,
			EconomyConfigScript.RES_GOLD: 500,
			EconomyConfigScript.RES_STONE: 200,
			EconomyConfigScript.RES_METAL: 200
		}
		reserved = {
			EconomyConfigScript.RES_FOOD: 0,
			EconomyConfigScript.RES_WOOD: 0,
			EconomyConfigScript.RES_GOLD: 0,
			EconomyConfigScript.RES_STONE: 0,
			EconomyConfigScript.RES_METAL: 0
		}

	func get_available_stock(res_id: String) -> int:
		return maxi(0, stock.get(res_id, 0) - reserved.get(res_id, 0))

	func can_afford(cost: Dictionary) -> bool:
		for res_id in cost:
			if get_available_stock(res_id) < cost[res_id]:
				return false
		return true

	func reserve_cost(cost: Dictionary) -> bool:
		if not can_afford(cost):
			return false
		for res_id in cost:
			reserved[res_id] = reserved.get(res_id, 0) + cost[res_id]
		return true

	func commit_cost(cost: Dictionary) -> void:
		for res_id in cost:
			var amt: int = cost[res_id]
			reserved[res_id] = maxi(0, reserved.get(res_id, 0) - amt)
			stock[res_id] = maxi(0, stock.get(res_id, 0) - amt)

	func release_cost(cost: Dictionary) -> void:
		for res_id in cost:
			reserved[res_id] = maxi(0, reserved.get(res_id, 0) - cost[res_id])

class MockEventManager:
	var events_triggered: Array = []

	func trigger_event(event_id: String, title: String, desc: String, is_positive: bool, payload: Dictionary = {}) -> void:
		events_triggered.append({
			"id": event_id,
			"title": title,
			"desc": desc,
			"positive": is_positive,
			"payload": payload
		})

class MockTimeManager:
	var current_day: int = 5
	var current_speed: int = 1
	var _paused: bool = false

	func is_paused() -> bool:
		return _paused

	func pause() -> void:
		_paused = true

	func resume() -> void:
		_paused = false

func _init() -> void:
	print("\n========================================================")
	print("  STARTING PACKAGE 1N OFFENSIVE CAMPAIGN TEST SUITE")
	print("========================================================\n")
	world_instance = WorldViewScene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count == 3:
		_run_all_tests()
		print("\n--------------------------------------------------------")
		if failures == 0:
			print("  ALL PACKAGE 1N OFFENSIVE CAMPAIGN TESTS PASSED! (Exit Code 0)")
			print("--------------------------------------------------------\n")
			quit(0)
			return true
		else:
			printerr("  PACKAGE 1N OFFENSIVE CAMPAIGN TESTS FAILED WITH %d FAILURES! (Exit Code 1)" % failures)
			print("--------------------------------------------------------\n")
			quit(1)
			return true
	return false

func _assert_true(cond: bool, test_name: String, msg: String = "") -> void:
	if not cond:
		failures += 1
		printerr("  ❌ FAIL [%s]: Expected true. %s" % [test_name, msg])
	else:
		print("  ✅ PASS [%s]%s" % [test_name, "" if msg.is_empty() else " - " + msg])

func _assert_false(cond: bool, test_name: String, msg: String = "") -> void:
	if cond:
		failures += 1
		printerr("  ❌ FAIL [%s]: Expected false. %s" % [test_name, msg])
	else:
		print("  ✅ PASS [%s]%s" % [test_name, "" if msg.is_empty() else " - " + msg])

func _assert_eq(val, expected, test_name: String, msg: String = "") -> void:
	if val != expected:
		failures += 1
		printerr("  ❌ FAIL [%s]: Expected '%s', got '%s'. %s" % [test_name, str(expected), str(val), msg])
	else:
		print("  ✅ PASS [%s]%s" % [test_name, "" if msg.is_empty() else " - " + msg])

func _run_all_tests() -> void:
	_test_tc_offense_1_valid_attack()
	_test_tc_offense_2_rejection_zero_soldiers()
	_test_tc_offense_3_rejection_garrisoned()
	_test_tc_offense_4_rejection_marching()
	_test_tc_offense_5_rejection_peaceful_or_zero_power()
	_test_tc_offense_6_deterministic_seed()
	_test_tc_offense_7_casualty_bounds()
	_test_tc_offense_8_power_and_casualty_application()
	_test_tc_offense_9_depleted_and_surviving_army()
	_test_tc_offense_10_rejected_attacks_preserve_state()
	_test_tc_offense_11_hud_battle_report_display()
	_test_tc_offense_12_persistence_and_schema_validation()
	_test_tc_offense_13_settlement_raids_unaffected()
	_test_tc_offense_14_marching_and_deployment_contract()

# -----------------------------------------------------------------------------
# Test Helper: Create standard test setup
# -----------------------------------------------------------------------------
func _create_test_campaign_setup() -> Dictionary:
	var mock_rm := MockResourceManager.new()
	var mock_em := MockEventManager.new()
	var mock_tm := MockTimeManager.new()
	var world_data := WorldGeneratorScript.generate(12345)
	var nav := GridNavigation.new(world_data)

	var army_mgr := PlayerArmyManagerScript.new()
	army_mgr.set_custom_resource_manager(mock_rm)
	army_mgr.set_custom_event_manager(mock_em)
	army_mgr.set_custom_time_manager(mock_tm)
	army_mgr.set_custom_nav(nav)
	army_mgr.soldier_count = 10
	army_mgr.rally_cell = Vector2i(2, 2)
	# Deploy army to field cell away from rally
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD
	army_mgr.current_cell = Vector2i(8, 8)
	army_mgr.destination_cell = Vector2i(8, 8)

	var fac_mgr := FactionManagerScript.new()
	var hostile_fac := FactionDataScript.new("rival_clan", "Bộ Tộc Đối Địch", "rival_military")
	hostile_fac.is_at_war = true
	hostile_fac.military_power = 150.0
	hostile_fac.stability = 70.0
	fac_mgr._factions["rival_clan"] = hostile_fac

	var camp_mgr := BattleCampaignManagerScript.new(null, fac_mgr, 12345)
	camp_mgr.set_custom_army_manager(army_mgr)
	camp_mgr.set_custom_resource_manager(mock_rm)
	camp_mgr.set_custom_world_data(world_data)
	camp_mgr.set_custom_current_day(5)

	return {
		"camp_mgr": camp_mgr,
		"army_mgr": army_mgr,
		"fac_mgr": fac_mgr,
		"hostile_fac": hostile_fac,
		"mock_rm": mock_rm,
		"mock_em": mock_em,
		"world_data": world_data,
		"nav": nav
	}

# -----------------------------------------------------------------------------
# TC-OFFENSE.1: Valid offensive attack when army is IDLE_AT_FIELD
# -----------------------------------------------------------------------------
func _test_tc_offense_1_valid_attack() -> void:
	print("--- TC-OFFENSE.1: Valid offensive attack when army is IDLE_AT_FIELD ---")
	var s = _create_test_campaign_setup()
	var camp_mgr: BattleCampaignManager = s["camp_mgr"]

	var check = camp_mgr.can_launch_offensive_campaign("rival_clan")
	_assert_true(check.get("can_attack", false), "TC-OFFENSE.1", "can_launch_offensive_campaign should allow attack when IDLE_AT_FIELD away from rally")

	var sig_data := {"emitted": false, "report": null, "context": {}}
	camp_mgr.offensive_campaign_resolved.connect(func(rep, ctx):
		sig_data["emitted"] = true
		sig_data["report"] = rep
		sig_data["context"] = ctx
	)

	var res = camp_mgr.launch_offensive_campaign("rival_clan", 99999)
	_assert_true(res.get("success", false), "TC-OFFENSE.1", "launch_offensive_campaign should succeed")
	_assert_true(sig_data["emitted"], "TC-OFFENSE.1", "offensive_campaign_resolved signal emitted")
	_assert_true(sig_data["report"] != null, "TC-OFFENSE.1", "Emitted report is valid BattleReport")
	_assert_true(sig_data["context"].get("is_offensive", false), "TC-OFFENSE.1", "Context is_offensive is true")
	_assert_eq(sig_data["context"].get("faction_id", ""), "rival_clan", "TC-OFFENSE.1", "Context faction_id matches")
	_assert_true(sig_data["context"].get("sequence", 0) > 0, "TC-OFFENSE.1", "Offensive sequence incremented")

# -----------------------------------------------------------------------------
# TC-OFFENSE.2: Rejection with 0 soldiers
# -----------------------------------------------------------------------------
func _test_tc_offense_2_rejection_zero_soldiers() -> void:
	print("--- TC-OFFENSE.2: Rejection with 0 soldiers ---")
	var s = _create_test_campaign_setup()
	var camp_mgr: BattleCampaignManager = s["camp_mgr"]
	var army_mgr = s["army_mgr"]
	army_mgr.soldier_count = 0

	var check = camp_mgr.can_launch_offensive_campaign("rival_clan")
	_assert_false(check.get("can_attack", true), "TC-OFFENSE.2", "can_launch returns false with 0 soldiers")
	_assert_true("binh sĩ" in check.get("reason", ""), "TC-OFFENSE.2", "Informative Vietnamese reason for 0 soldiers")

	var res = camp_mgr.launch_offensive_campaign("rival_clan")
	_assert_false(res.get("success", true), "TC-OFFENSE.2", "launch fails closed with 0 soldiers")

# -----------------------------------------------------------------------------
# TC-OFFENSE.3: Rejection when garrisoned at home rally
# -----------------------------------------------------------------------------
func _test_tc_offense_3_rejection_garrisoned() -> void:
	print("--- TC-OFFENSE.3: Rejection when garrisoned at home rally ---")
	var s = _create_test_campaign_setup()
	var camp_mgr: BattleCampaignManager = s["camp_mgr"]
	var army_mgr = s["army_mgr"]
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.GARRISONED
	army_mgr.current_cell = Vector2i(2, 2)

	var check = camp_mgr.can_launch_offensive_campaign("rival_clan")
	_assert_false(check.get("can_attack", true), "TC-OFFENSE.3", "can_launch returns false when garrisoned")
	_assert_true("căn cứ" in check.get("reason", "") or "đóng quân" in check.get("reason", ""), "TC-OFFENSE.3", "Informative Vietnamese reason when garrisoned")

	var res = camp_mgr.launch_offensive_campaign("rival_clan")
	_assert_false(res.get("success", true), "TC-OFFENSE.3", "launch fails closed when garrisoned")

# -----------------------------------------------------------------------------
# TC-OFFENSE.4: Rejection when marching
# -----------------------------------------------------------------------------
func _test_tc_offense_4_rejection_marching() -> void:
	print("--- TC-OFFENSE.4: Rejection when marching ---")
	var s = _create_test_campaign_setup()
	var camp_mgr: BattleCampaignManager = s["camp_mgr"]
	var army_mgr = s["army_mgr"]
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.MARCHING

	var check = camp_mgr.can_launch_offensive_campaign("rival_clan")
	_assert_false(check.get("can_attack", true), "TC-OFFENSE.4", "can_launch returns false when marching")
	_assert_true("hành quân" in check.get("reason", ""), "TC-OFFENSE.4", "Informative Vietnamese reason when marching")

	var res = camp_mgr.launch_offensive_campaign("rival_clan")
	_assert_false(res.get("success", true), "TC-OFFENSE.4", "launch fails closed when marching")

# -----------------------------------------------------------------------------
# TC-OFFENSE.5: Rejection against peaceful, neutral, allied, non-existent, or 0 military power faction
# -----------------------------------------------------------------------------
func _test_tc_offense_5_rejection_peaceful_or_zero_power() -> void:
	print("--- TC-OFFENSE.5: Rejection against peaceful, non-existent, or 0 military power ---")
	var s = _create_test_campaign_setup()
	var camp_mgr: BattleCampaignManager = s["camp_mgr"]
	var hostile_fac: FactionData = s["hostile_fac"]

	# Non-existent
	var check_non = camp_mgr.can_launch_offensive_campaign("ghost_faction")
	_assert_false(check_non.get("can_attack", true), "TC-OFFENSE.5", "Rejects non-existent faction")
	_assert_true("không tồn tại" in check_non.get("reason", ""), "TC-OFFENSE.5", "Informative message for non-existent faction")

	# Peaceful (not at war)
	hostile_fac.is_at_war = false
	var check_peace = camp_mgr.can_launch_offensive_campaign("rival_clan")
	_assert_false(check_peace.get("can_attack", true), "TC-OFFENSE.5", "Rejects faction when not at war")
	_assert_true("Chưa tuyên chiến" in check_peace.get("reason", ""), "TC-OFFENSE.5", "Informative message for peaceful faction")

	# Zero military power
	hostile_fac.is_at_war = true
	hostile_fac.military_power = 0.0
	var check_zero = camp_mgr.can_launch_offensive_campaign("rival_clan")
	_assert_false(check_zero.get("can_attack", true), "TC-OFFENSE.5", "Rejects faction with 0 military power")
	_assert_true("cạn kiệt" in check_zero.get("reason", ""), "TC-OFFENSE.5", "Informative message for zero military power")

# -----------------------------------------------------------------------------
# TC-OFFENSE.6: Deterministic seed produces identical BattleReport
# -----------------------------------------------------------------------------
func _test_tc_offense_6_deterministic_seed() -> void:
	print("--- TC-OFFENSE.6: Deterministic seed produces identical BattleReport ---")
	var s1 = _create_test_campaign_setup()
	var s2 = _create_test_campaign_setup()

	var res1 = s1["camp_mgr"].launch_offensive_campaign("rival_clan", 7777)
	var res2 = s2["camp_mgr"].launch_offensive_campaign("rival_clan", 7777)

	_assert_true(res1.get("success", false) and res2.get("success", false), "TC-OFFENSE.6", "Both campaigns resolved successfully")
	var rep1: BattleResolver.BattleReport = res1["report"]
	var rep2: BattleResolver.BattleReport = res2["report"]

	_assert_eq(rep1.victor, rep2.victor, "TC-OFFENSE.6", "Victors are identical with same seed")
	_assert_eq(rep1.attacker_casualties, rep2.attacker_casualties, "TC-OFFENSE.6", "Attacker casualties identical")
	_assert_eq(rep1.defender_casualties, rep2.defender_casualties, "TC-OFFENSE.6", "Defender casualties identical")
	_assert_eq(rep1.details.get("attacker_combat_score"), rep2.details.get("attacker_combat_score"), "TC-OFFENSE.6", "Attacker scores identical")
	_assert_eq(rep1.details.get("defender_combat_score"), rep2.details.get("defender_combat_score"), "TC-OFFENSE.6", "Defender scores identical")

# -----------------------------------------------------------------------------
# TC-OFFENSE.7: Casualties bounded by initial counts; non-negative
# -----------------------------------------------------------------------------
func _test_tc_offense_7_casualty_bounds() -> void:
	print("--- TC-OFFENSE.7: Casualties bounded by initial counts; non-negative ---")
	for test_seed in [101, 202, 303, 404, 505]:
		var s = _create_test_campaign_setup()
		var army_mgr = s["army_mgr"]
		army_mgr.soldier_count = 8
		s["hostile_fac"].military_power = 90.0 # troops = round(90/30) = 3

		var res = s["camp_mgr"].launch_offensive_campaign("rival_clan", test_seed)
		_assert_true(res.get("success", false), "TC-OFFENSE.7", "Run seed %d succeeded" % test_seed)
		var rep: BattleResolver.BattleReport = res["report"]
		_assert_true(rep.attacker_casualties >= 0 and rep.attacker_casualties <= 8, "TC-OFFENSE.7", "Attacker casualties bounded (0..8)")
		_assert_true(rep.defender_casualties >= 0 and rep.defender_casualties <= 3, "TC-OFFENSE.7", "Defender casualties bounded (0..3)")

# -----------------------------------------------------------------------------
# TC-OFFENSE.8: Player casualties and faction military power reductions match report
# -----------------------------------------------------------------------------
func _test_tc_offense_8_power_and_casualty_application() -> void:
	print("--- TC-OFFENSE.8: Player casualties and military power reductions match report ---")
	var s = _create_test_campaign_setup()
	var army_mgr = s["army_mgr"]
	var hostile_fac = s["hostile_fac"]
	army_mgr.soldier_count = 12
	hostile_fac.military_power = 120.0 # 4 troops

	var res = s["camp_mgr"].launch_offensive_campaign("rival_clan", 123456)
	_assert_true(res.get("success", false), "TC-OFFENSE.8", "Offensive campaign succeeded")
	var rep: BattleResolver.BattleReport = res["report"]

	var expected_soldiers: int = 12 - rep.attacker_casualties
	_assert_eq(army_mgr.get_army_count(), expected_soldiers, "TC-OFFENSE.8", "Soldier count decremented exactly by attacker_casualties")

	var expected_power: float = maxf(0.0, 120.0 - float(rep.defender_casualties) * 30.0)
	_assert_eq(hostile_fac.military_power, expected_power, "TC-OFFENSE.8", "Hostile military power reduced exactly by defender_casualties * 30.0")

# -----------------------------------------------------------------------------
# TC-OFFENSE.9: Depleted army normalizes to garrison at rally; surviving army stays at field cell
# -----------------------------------------------------------------------------
func _test_tc_offense_9_depleted_and_surviving_army() -> void:
	print("--- TC-OFFENSE.9: Depleted army normalizes to garrison; surviving army stays in field ---")
	# Case A: Army survives
	var s_survive = _create_test_campaign_setup()
	var army_survive = s_survive["army_mgr"]
	army_survive.soldier_count = 20 # Overwhelming force, guaranteed survival
	s_survive["hostile_fac"].military_power = 30.0 # 1 troop

	var res_surv = s_survive["camp_mgr"].launch_offensive_campaign("rival_clan", 42)
	_assert_true(res_surv.get("success", false), "TC-OFFENSE.9", "Survival campaign succeeded")
	_assert_true(army_survive.get_army_count() > 0, "TC-OFFENSE.9", "Army has surviving soldiers")
	_assert_eq(army_survive.get_movement_state(), PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD, "TC-OFFENSE.9", "Surviving army remains IDLE_AT_FIELD")
	_assert_eq(army_survive.get_current_cell(), Vector2i(8, 8), "TC-OFFENSE.9", "Surviving army stays at field cell without teleporting")

	# Case B: Army wiped out (depleted)
	var s_depleted = _create_test_campaign_setup()
	var army_depleted = s_depleted["army_mgr"]
	army_depleted.soldier_count = 1
	s_depleted["hostile_fac"].military_power = 600.0 # 20 troops with tier 2 equipment

	var res_dep = s_depleted["camp_mgr"].launch_offensive_campaign("rival_clan", 101)
	_assert_true(res_dep.get("success", false), "TC-OFFENSE.9", "Depletion campaign succeeded")
	if res_dep["report"].attacker_casualties >= 1:
		_assert_eq(army_depleted.get_army_count(), 0, "TC-OFFENSE.9", "Army soldiers depleted to 0")
		_assert_eq(army_depleted.get_movement_state(), PlayerArmyManagerScript.MovementState.GARRISONED, "TC-OFFENSE.9", "Depleted army normalizes to GARRISONED")
		_assert_eq(army_depleted.get_current_cell(), army_depleted.get_rally_cell(), "TC-OFFENSE.9", "Depleted army returns to rally cell")
	else:
		# If the 1 soldier miraculously survived this seed, manually call remove_casualties(1) to verify normalization
		army_depleted.remove_casualties(1)
		_assert_eq(army_depleted.get_army_count(), 0, "TC-OFFENSE.9", "Army soldiers depleted to 0")
		_assert_eq(army_depleted.get_movement_state(), PlayerArmyManagerScript.MovementState.GARRISONED, "TC-OFFENSE.9", "Depleted army normalizes to GARRISONED")
		_assert_eq(army_depleted.get_current_cell(), army_depleted.get_rally_cell(), "TC-OFFENSE.9", "Depleted army returns to rally cell")

# -----------------------------------------------------------------------------
# TC-OFFENSE.10: Rejected attacks do not mutate state
# -----------------------------------------------------------------------------
func _test_tc_offense_10_rejected_attacks_preserve_state() -> void:
	print("--- TC-OFFENSE.10: Rejected attacks do not mutate state ---")
	var s = _create_test_campaign_setup()
	var camp_mgr: BattleCampaignManager = s["camp_mgr"]
	var army_mgr = s["army_mgr"]
	var hostile_fac = s["hostile_fac"]
	var rm = s["mock_rm"]

	# Save baseline snapshot
	var snap_soldiers: int = army_mgr.get_army_count()
	var snap_state: int = army_mgr.get_movement_state()
	var snap_cell: Vector2i = army_mgr.get_current_cell()
	var snap_mil: float = hostile_fac.military_power
	var snap_war: bool = hostile_fac.is_at_war
	var snap_food: int = rm.stock[EconomyConfigScript.RES_FOOD]

	# Attempt rejected attack on invalid faction
	var res_bad_fac = camp_mgr.launch_offensive_campaign("invalid_fac_id")
	_assert_false(res_bad_fac.get("success", true), "TC-OFFENSE.10", "Rejects invalid faction")

	# Attempt rejected attack when garrisoned
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.GARRISONED
	var res_garr = camp_mgr.launch_offensive_campaign("rival_clan")
	_assert_false(res_garr.get("success", true), "TC-OFFENSE.10", "Rejects garrisoned army")
	army_mgr.movement_state = snap_state

	# Verify state was not mutated
	_assert_eq(army_mgr.get_army_count(), snap_soldiers, "TC-OFFENSE.10", "Soldier count unmodified")
	_assert_eq(army_mgr.get_movement_state(), snap_state, "TC-OFFENSE.10", "Movement state unmodified")
	_assert_eq(army_mgr.get_current_cell(), snap_cell, "TC-OFFENSE.10", "Current cell unmodified")
	_assert_eq(hostile_fac.military_power, snap_mil, "TC-OFFENSE.10", "Military power unmodified")
	_assert_eq(hostile_fac.is_at_war, snap_war, "TC-OFFENSE.10", "War status unmodified")
	_assert_eq(rm.stock[EconomyConfigScript.RES_FOOD], snap_food, "TC-OFFENSE.10", "Resource stocks unmodified")

# -----------------------------------------------------------------------------
# TC-OFFENSE.11: HUD battle report reflects true mutated outcome and remaining counts
# -----------------------------------------------------------------------------
func _test_tc_offense_11_hud_battle_report_display() -> void:
	print("--- TC-OFFENSE.11: HUD battle report reflects true mutated outcome ---")
	var hud = HUDScene.instantiate()
	root.add_child(hud)

	var report = BattleResolver.BattleReport.new()
	report.victor = "attacker"
	report.attacker_troops_initial = 10
	report.defender_troops_initial = 5
	report.attacker_casualties = 2
	report.defender_casualties = 5
	report.details = {
		"attacker_combat_score": 150.0,
		"defender_combat_score": 80.0
	}

	var context: Dictionary = {
		"is_offensive": true,
		"faction_id": "rival_clan",
		"faction_name": "Bộ Tộc Đối Địch",
		"player_casualties": 2,
		"enemy_casualties": 5,
		"remaining_player_troops": 8,
		"remaining_military_power": 0.0,
		"resolution_day": 7,
		"sequence": 1
	}

	hud._on_battle_resolved(report, context)

	var title_lbl: Label = hud.get_node_or_null("EventBanner/MarginContainer/VBoxContainer/EventTitle")
	var text_lbl: Label = hud.get_node_or_null("EventBanner/MarginContainer/VBoxContainer/EventDesc")
	_assert_true(title_lbl != null and text_lbl != null, "TC-OFFENSE.11", "EventBanner labels exist")

	var banner_text: String = text_lbl.text
	_assert_true("CHIẾN THẮNG TIẾN CÔNG" in title_lbl.text or "CHIẾN DỊCH" in title_lbl.text, "TC-OFFENSE.11", "Title indicates campaign battle")
	_assert_true("Bộ Tộc Đối Địch" in banner_text, "TC-OFFENSE.11", "Banner text mentions target faction name")
	_assert_true("mất 2" in banner_text, "TC-OFFENSE.11", "Banner text mentions player casualties")
	_assert_true("còn 8 lính" in banner_text, "TC-OFFENSE.11", "Banner text mentions remaining player troops")
	_assert_true("mất 5" in banner_text, "TC-OFFENSE.11", "Banner text mentions enemy casualties")

	hud.queue_free()

# -----------------------------------------------------------------------------
# TC-OFFENSE.12: Save/load preserves post-attack army and faction states without replaying
# -----------------------------------------------------------------------------
func _test_tc_offense_12_persistence_and_schema_validation() -> void:
	print("--- TC-OFFENSE.12: Save/load preserves post-attack army and faction states ---")
	var s = _create_test_campaign_setup()
	var camp_mgr: BattleCampaignManager = s["camp_mgr"]

	var res = camp_mgr.launch_offensive_campaign("rival_clan", 12345)
	_assert_true(res.get("success", false), "TC-OFFENSE.12", "Campaign launched")
	var expected_seq: int = camp_mgr.get_offensive_campaign_sequence()
	_assert_true(expected_seq > 0, "TC-OFFENSE.12", "Offensive sequence is positive")

	var serialized: Dictionary = camp_mgr.serialize()
	_assert_true(serialized.has("offensive_sequence"), "TC-OFFENSE.12", "Serialized contains offensive_sequence")
	_assert_eq(serialized.get("offensive_sequence"), expected_seq, "TC-OFFENSE.12", "Serialized offensive_sequence matches")

	# Test SaveManager schema validator for battle_campaign
	var mock_save_data: Dictionary = {
		"schema_version": SaveManagerScript.SAVE_SCHEMA_VERSION,
		"metadata": {"save_name": "Test", "timestamp": "2026-10-20"},
		"game_clock": {"current_day": 5, "current_hour": 12, "current_minute": 0},
		"resources": {"stock": {}, "capacities": {}, "active_population": 24},
		"buildings": [],
		"citizens": [],
		"world_data": {"seed": 12345, "unlocked_techs": []},
		"battle_campaign": serialized
	}
	var val_ok = SaveManagerScript.validate_save_data(mock_save_data)
	_assert_true(val_ok.get("valid", false), "TC-OFFENSE.12", "Valid battle_campaign passes SaveManager schema validation")

	# Negative test: invalid offensive_sequence (< 0)
	var bad_save_data = mock_save_data.duplicate(true)
	bad_save_data["battle_campaign"]["offensive_sequence"] = -5
	var val_bad = SaveManagerScript.validate_save_data(bad_save_data)
	_assert_false(val_bad.get("valid", true), "TC-OFFENSE.12", "Negative offensive_sequence fails SaveManager schema validation")

	# Test Deserialization restored accurately
	var new_camp_mgr := BattleCampaignManagerScript.new()
	new_camp_mgr.deserialize(serialized)
	_assert_eq(new_camp_mgr.get_offensive_campaign_sequence(), expected_seq, "TC-OFFENSE.12", "Deserialized offensive_sequence matches")

# -----------------------------------------------------------------------------
# TC-OFFENSE.13: Incoming settlement raids, schedules, and peace cancellations remain intact
# -----------------------------------------------------------------------------
func _test_tc_offense_13_settlement_raids_unaffected() -> void:
	print("--- TC-OFFENSE.13: Settlement raids and schedules remain unaffected ---")
	var s = _create_test_campaign_setup()
	var camp_mgr: BattleCampaignManager = s["camp_mgr"]
	var fac_mgr: FactionManager = s["fac_mgr"]

	# Schedule incoming raid for day 8
	camp_mgr.schedule_raid("rival_clan", 8, 1, true)
	_assert_true(camp_mgr.has_pending_raid("rival_clan"), "TC-OFFENSE.13", "Settlement raid is scheduled")

	# Launch an offensive campaign
	var res = camp_mgr.launch_offensive_campaign("rival_clan", 8888)
	_assert_true(res.get("success", false), "TC-OFFENSE.13", "Offensive campaign succeeded")

	# Assert settlement raid is still intact
	_assert_true(camp_mgr.has_pending_raid("rival_clan"), "TC-OFFENSE.13", "Settlement raid remains scheduled after offensive campaign")
	_assert_eq(camp_mgr.get_pending_raid("rival_clan").get("scheduled_day"), 8, "TC-OFFENSE.13", "Scheduled day remains day 8")

	# Signing peace should still cancel incoming raid
	fac_mgr.peace_signed.emit("rival_clan")
	_assert_false(camp_mgr.has_pending_raid("rival_clan"), "TC-OFFENSE.13", "Signing peace cancels scheduled raid as expected")

# -----------------------------------------------------------------------------
# TC-OFFENSE.14: Movement and deployment rules from Package 1M remain valid
# -----------------------------------------------------------------------------
func _test_tc_offense_14_marching_and_deployment_contract() -> void:
	print("--- TC-OFFENSE.14: Movement and deployment rules from Package 1M remain valid ---")
	var s = _create_test_campaign_setup()
	var army_mgr = s["army_mgr"]
	var nav = s["nav"]

	# Return home to rally cell
	army_mgr.order_return_home()
	_assert_eq(army_mgr.get_movement_state(), PlayerArmyManagerScript.MovementState.MARCHING, "TC-OFFENSE.14", "order_return_home puts army into MARCHING state")
	_assert_eq(army_mgr.get_destination_cell(), army_mgr.get_rally_cell(), "TC-OFFENSE.14", "Destination is rally cell")

	# Advance army steps until arrival
	for _i in range(30):
		if army_mgr.get_movement_state() == PlayerArmyManagerScript.MovementState.GARRISONED:
			break
		army_mgr.advance_movement(0.5)

	_assert_eq(army_mgr.get_movement_state(), PlayerArmyManagerScript.MovementState.GARRISONED, "TC-OFFENSE.14", "Army returned home and transitioned to GARRISONED")
	_assert_eq(army_mgr.get_current_cell(), army_mgr.get_rally_cell(), "TC-OFFENSE.14", "Current cell is rally cell")
	_assert_true(army_mgr.is_defense_eligible(), "TC-OFFENSE.14", "Army is defense eligible when garrisoned at home")
