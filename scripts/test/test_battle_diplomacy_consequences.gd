extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — Package 1O: Post-Battle Diplomatic Consequences
## Validates authoritative diplomatic consequences for offensive campaigns and settlement raids:
## - TC-DIPLO.1: Successful offensive campaign applies exactly the configured opinion penalty (-8.0)
## - TC-DIPLO.2: Successful settlement raid applies exactly the configured opinion penalty (-10.0)
## - TC-DIPLO.3: Diplomatic penalties clamp at valid opinion boundaries (-100.0 to 100.0)
## - TC-DIPLO.4: Exactly one relation_changed event is emitted per successful battle consequence
## - TC-DIPLO.5: A rejected offensive campaign causes no opinion/disposition mutation and emits no signal
## - TC-DIPLO.6: A raid that is not due or is already processed cannot apply the penalty
## - TC-DIPLO.7: Existing hostile disposition semantics during war remain correct
## - TC-DIPLO.8: After peace is signed, disposition reflects restored non-war state and post-battle opinion
## - TC-DIPLO.9: Real SaveManager integration restores opinion/disposition correctly and double-load does not reapply
## - TC-DIPLO.10: Existing resource, military-power, casualty, raid-schedule, and campaign-sequence behavior unchanged
## - TC-DIPLO.11: Existing gift, treaty, war declaration, peace, and Package 1N behavior regression verification

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

	func has_resource(res_id: String, amount: int) -> bool:
		return get_available_stock(res_id) >= amount

	func consume_resource(res_id: String, amount: int) -> bool:
		if not has_resource(res_id, amount):
			return false
		stock[res_id] = maxi(0, stock.get(res_id, 0) - amount)
		return true

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
	print("  STARTING PACKAGE 1O BATTLE DIPLOMACY TEST SUITE")
	print("========================================================\n")
	world_instance = WorldViewScene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count == 3:
		_run_all_tests()
		print("\n--------------------------------------------------------")
		if failures == 0:
			print("  ALL PACKAGE 1O BATTLE DIPLOMACY TESTS PASSED! (Exit Code 0)")
			print("--------------------------------------------------------\n")
			quit(0)
			return true
		else:
			printerr("  PACKAGE 1O BATTLE DIPLOMACY TESTS FAILED WITH %d FAILURES! (Exit Code 1)" % failures)
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

func _assert_approx(val: float, expected: float, test_name: String, msg: String = "", tolerance: float = 0.001) -> void:
	if absf(val - expected) > tolerance:
		failures += 1
		printerr("  ❌ FAIL [%s]: Expected approx '%f', got '%f'. %s" % [test_name, expected, val, msg])
	else:
		print("  ✅ PASS [%s]%s" % [test_name, "" if msg.is_empty() else " - " + msg])

func _run_all_tests() -> void:
	_test_tc_diplo_1_offensive_campaign_penalty()
	_test_tc_diplo_2_settlement_raid_penalty()
	_test_tc_diplo_3_clamping_boundaries()
	_test_tc_diplo_4_signal_emission_exactly_once()
	_test_tc_diplo_5_rejected_attack_immutability()
	_test_tc_diplo_6_not_due_or_processed_raid_immutability()
	_test_tc_diplo_7_hostile_disposition_during_war()
	_test_tc_diplo_8_post_peace_disposition_recalculation()
	_test_tc_diplo_9_save_load_persistence_and_idempotency()
	_test_tc_diplo_10_combat_mechanics_unaltered()
	_test_tc_diplo_11_diplomacy_regression()

# -----------------------------------------------------------------------------
# Test Helper: Create standard campaign test setup
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
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD
	army_mgr.current_cell = Vector2i(8, 8)
	army_mgr.destination_cell = Vector2i(8, 8)

	var fac_mgr := FactionManagerScript.new()
	var hostile_fac := FactionDataScript.new("rival_clan", "Bộ Tộc Đối Địch", "rival_military")
	hostile_fac.is_at_war = true
	hostile_fac.military_power = 150.0
	hostile_fac.stability = 70.0
	hostile_fac.opinion = 20.0
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
# TC-DIPLO.1: Successful offensive campaign applies exactly configured penalty (-8.0)
# -----------------------------------------------------------------------------
func _test_tc_diplo_1_offensive_campaign_penalty() -> void:
	print("--- TC-DIPLO.1: Offensive campaign opinion penalty (-8.0) ---")
	var s = _create_test_campaign_setup()
	var camp_mgr: BattleCampaignManager = s["camp_mgr"]
	var hostile_fac: FactionData = s["hostile_fac"]
	hostile_fac.opinion = 20.0

	var res: Dictionary = camp_mgr.launch_offensive_campaign("rival_clan", 12345)
	_assert_true(res.get("success", false), "TC-DIPLO.1", "Offensive campaign launched successfully")
	_assert_approx(hostile_fac.opinion, 20.0 - FactionManagerScript.OPINION_PENALTY_OFFENSIVE_CAMPAIGN, "TC-DIPLO.1", "Opinion reduced by exactly 8.0 (20.0 -> 12.0)")
	_assert_approx(float(res.get("context", {}).get("diplomatic_opinion_penalty", 0.0)), FactionManagerScript.OPINION_PENALTY_OFFENSIVE_CAMPAIGN, "TC-DIPLO.1", "Context reflects canonical 8.0 penalty")
	_assert_approx(float(res.get("context", {}).get("new_opinion", 0.0)), 12.0, "TC-DIPLO.1", "Context reflects new opinion 12.0")

# -----------------------------------------------------------------------------
# TC-DIPLO.2: Successful settlement raid applies exactly configured penalty (-10.0)
# -----------------------------------------------------------------------------
func _test_tc_diplo_2_settlement_raid_penalty() -> void:
	print("--- TC-DIPLO.2: Settlement raid opinion penalty (-10.0) ---")
	var s = _create_test_campaign_setup()
	var camp_mgr: BattleCampaignManager = s["camp_mgr"]
	var hostile_fac: FactionData = s["hostile_fac"]
	hostile_fac.opinion = -10.0

	# Schedule raid due on day 5
	var sched_ok: bool = camp_mgr.schedule_raid("rival_clan", 5, 1, true)
	_assert_true(sched_ok, "TC-DIPLO.2", "Raid scheduled for day 5")

	var res: Dictionary = camp_mgr.resolve_and_apply_raid("rival_clan", 5)
	_assert_true(res.get("success", false), "TC-DIPLO.2", "Raid resolved successfully")
	_assert_approx(hostile_fac.opinion, -10.0 - FactionManagerScript.OPINION_PENALTY_SETTLEMENT_RAID, "TC-DIPLO.2", "Opinion reduced by exactly 10.0 (-10.0 -> -20.0)")
	_assert_approx(float(res.get("context", {}).get("diplomatic_opinion_penalty", 0.0)), FactionManagerScript.OPINION_PENALTY_SETTLEMENT_RAID, "TC-DIPLO.2", "Context reflects canonical 10.0 penalty")
	_assert_approx(float(res.get("context", {}).get("new_opinion", 0.0)), -20.0, "TC-DIPLO.2", "Context reflects new opinion -20.0")

# -----------------------------------------------------------------------------
# TC-DIPLO.3: Diplomatic penalties clamp at valid boundaries (-100.0 to 100.0)
# -----------------------------------------------------------------------------
func _test_tc_diplo_3_clamping_boundaries() -> void:
	print("--- TC-DIPLO.3: Opinion clamping at boundaries (-100.0 and +100.0) ---")
	var s = _create_test_campaign_setup()
	var camp_mgr: BattleCampaignManager = s["camp_mgr"]
	var hostile_fac: FactionData = s["hostile_fac"]

	# Subcase A: Offensive campaign clamps at -100.0
	hostile_fac.opinion = -95.0
	var res1: Dictionary = camp_mgr.launch_offensive_campaign("rival_clan", 11111)
	_assert_true(res1.get("success", false), "TC-DIPLO.3A", "Offensive campaign launched")
	_assert_approx(hostile_fac.opinion, -100.0, "TC-DIPLO.3A", "Opinion -95.0 - 8.0 clamped to -100.0")

	# Subcase B: Settlement raid clamps at -100.0
	hostile_fac.opinion = -96.0
	camp_mgr.schedule_raid("rival_clan", 5, 2, false)
	var res2: Dictionary = camp_mgr.resolve_and_apply_raid("rival_clan", 5)
	_assert_true(res2.get("success", false), "TC-DIPLO.3B", "Settlement raid resolved")
	_assert_approx(hostile_fac.opinion, -100.0, "TC-DIPLO.3B", "Opinion -96.0 - 10.0 clamped to -100.0")

	# Subcase C: Further attacks while at -100.0 remain strictly -100.0
	var res3: Dictionary = camp_mgr.launch_offensive_campaign("rival_clan", 22222)
	_assert_true(res3.get("success", false), "TC-DIPLO.3C", "Offensive campaign launched while at -100.0")
	_assert_approx(hostile_fac.opinion, -100.0, "TC-DIPLO.3C", "Opinion stays clamped at -100.0")

	# Subcase D & E: Authoritative upper boundary (+100.0) clamping via FactionManager.modify_opinion
	# Uses an isolated FactionManager instance and non-war faction to avoid test contamination
	var bound_fm := FactionManagerScript.new()
	var test_fac: FactionData = bound_fm.get_faction("neutral_tribe")
	_assert_true(test_fac != null and not test_fac.is_at_war, "TC-DIPLO.3D", "Non-war faction available for boundary testing")

	var bound_emissions: Array = []
	var on_bound_relation_changed = func(fid: String, op: float, disp: int):
		bound_emissions.append({"id": fid, "opinion": op, "disposition": disp})
	bound_fm.relation_changed.connect(on_bound_relation_changed)

	# 1. Set non-war faction opinion to 95.0; apply positive delta exceeding 100.0; assert resulting opinion is exactly 100.0
	test_fac.opinion = 95.0
	test_fac.recalculate_disposition()
	bound_emissions.clear()
	var res_upper1: Dictionary = bound_fm.modify_opinion(test_fac.id, 20.0)
	_assert_true(res_upper1.get("success", false), "TC-DIPLO.3D", "Positive modify_opinion succeeded")
	_assert_approx(test_fac.opinion, 100.0, "TC-DIPLO.3D", "Opinion 95.0 + 20.0 clamped to exactly 100.0")
	_assert_approx(float(res_upper1.get("new_opinion", 0.0)), 100.0, "TC-DIPLO.3D", "Returned new_opinion is 100.0")
	_assert_eq(bound_emissions.size(), 1, "TC-DIPLO.3D", "Exactly 1 signal emitted on upper boundary clamp")
	if bound_emissions.size() > 0:
		_assert_eq(bound_emissions[0]["id"], test_fac.id, "TC-DIPLO.3D", "Signal faction_id matches")
		_assert_approx(bound_emissions[0]["opinion"], 100.0, "TC-DIPLO.3D", "Signal opinion matches clamped 100.0")
		_assert_eq(bound_emissions[0]["disposition"], FactionDataScript.Disposition.ALLIED, "TC-DIPLO.3D", "Signal disposition is ALLIED (>= 75.0)")

	# 2. Apply another positive delta while already at 100.0; assert it remains exactly 100.0
	bound_emissions.clear()
	var res_upper2: Dictionary = bound_fm.modify_opinion(test_fac.id, 15.0)
	_assert_true(res_upper2.get("success", false), "TC-DIPLO.3E", "Positive modify_opinion while at 100.0 succeeded")
	_assert_approx(test_fac.opinion, 100.0, "TC-DIPLO.3E", "Opinion remains strictly clamped at 100.0")
	_assert_approx(float(res_upper2.get("new_opinion", 0.0)), 100.0, "TC-DIPLO.3E", "Returned new_opinion remains 100.0")
	_assert_eq(bound_emissions.size(), 1, "TC-DIPLO.3E", "Exactly 1 signal emitted when already at upper bound")
	if bound_emissions.size() > 0:
		_assert_approx(bound_emissions[0]["opinion"], 100.0, "TC-DIPLO.3E", "Signal opinion payload matches 100.0")
		_assert_eq(bound_emissions[0]["disposition"], FactionDataScript.Disposition.ALLIED, "TC-DIPLO.3E", "Signal disposition remains ALLIED")

	# Subcase F & G: Authoritative lower boundary (-100.0) clamping via FactionManager.modify_opinion
	# 3. Set non-war faction opinion to -95.0; apply negative delta crossing -100.0; assert resulting opinion is exactly -100.0
	test_fac.opinion = -95.0
	test_fac.recalculate_disposition()
	bound_emissions.clear()
	var res_lower1: Dictionary = bound_fm.modify_opinion(test_fac.id, -20.0)
	_assert_true(res_lower1.get("success", false), "TC-DIPLO.3F", "Negative modify_opinion succeeded")
	_assert_approx(test_fac.opinion, -100.0, "TC-DIPLO.3F", "Opinion -95.0 - 20.0 clamped to exactly -100.0")
	_assert_approx(float(res_lower1.get("new_opinion", 0.0)), -100.0, "TC-DIPLO.3F", "Returned new_opinion is -100.0")
	_assert_eq(bound_emissions.size(), 1, "TC-DIPLO.3F", "Exactly 1 signal emitted on lower boundary clamp")
	if bound_emissions.size() > 0:
		_assert_eq(bound_emissions[0]["id"], test_fac.id, "TC-DIPLO.3F", "Signal faction_id matches")
		_assert_approx(bound_emissions[0]["opinion"], -100.0, "TC-DIPLO.3F", "Signal opinion matches clamped -100.0")
		_assert_eq(bound_emissions[0]["disposition"], FactionDataScript.Disposition.HOSTILE, "TC-DIPLO.3F", "Signal disposition is HOSTILE (<= -40.0)")

	# 4. Apply another negative delta while already at -100.0; assert it remains exactly -100.0
	bound_emissions.clear()
	var res_lower2: Dictionary = bound_fm.modify_opinion(test_fac.id, -15.0)
	_assert_true(res_lower2.get("success", false), "TC-DIPLO.3G", "Negative modify_opinion while at -100.0 succeeded")
	_assert_approx(test_fac.opinion, -100.0, "TC-DIPLO.3G", "Opinion remains strictly clamped at -100.0")
	_assert_approx(float(res_lower2.get("new_opinion", 0.0)), -100.0, "TC-DIPLO.3G", "Returned new_opinion remains -100.0")
	_assert_eq(bound_emissions.size(), 1, "TC-DIPLO.3G", "Exactly 1 signal emitted when already at lower bound")
	if bound_emissions.size() > 0:
		_assert_approx(bound_emissions[0]["opinion"], -100.0, "TC-DIPLO.3G", "Signal opinion payload matches -100.0")
		_assert_eq(bound_emissions[0]["disposition"], FactionDataScript.Disposition.HOSTILE, "TC-DIPLO.3G", "Signal disposition remains HOSTILE")

	bound_fm.relation_changed.disconnect(on_bound_relation_changed)

# -----------------------------------------------------------------------------
# TC-DIPLO.4: Exactly one relation_changed event emitted per successful battle
# -----------------------------------------------------------------------------
func _test_tc_diplo_4_signal_emission_exactly_once() -> void:
	print("--- TC-DIPLO.4: Exactly one relation_changed emission per battle ---")
	var s = _create_test_campaign_setup()
	var camp_mgr: BattleCampaignManager = s["camp_mgr"]
	var fac_mgr: FactionManager = s["fac_mgr"]
	var hostile_fac: FactionData = s["hostile_fac"]
	hostile_fac.opinion = 0.0

	var emissions: Array = []
	var on_relation_changed = func(id, op, disp):
		emissions.append({"id": id, "opinion": op, "disposition": disp})
	fac_mgr.relation_changed.connect(on_relation_changed)

	# Part A: Offensive Campaign
	emissions.clear()
	var res_off: Dictionary = camp_mgr.launch_offensive_campaign("rival_clan", 33333)
	_assert_true(res_off.get("success", false), "TC-DIPLO.4A", "Offensive campaign succeeded")
	_assert_eq(emissions.size(), 1, "TC-DIPLO.4A", "Exactly 1 relation_changed emitted for offensive campaign")
	if emissions.size() > 0:
		_assert_eq(emissions[0]["id"], "rival_clan", "TC-DIPLO.4A", "Signal faction_id matches")
		_assert_approx(emissions[0]["opinion"], -8.0, "TC-DIPLO.4A", "Signal opinion matches (-8.0)")
		_assert_eq(emissions[0]["disposition"], FactionData.Disposition.HOSTILE, "TC-DIPLO.4A", "Signal disposition is HOSTILE during war")

	# Part B: Settlement Raid
	emissions.clear()
	camp_mgr.schedule_raid("rival_clan", 5, 1, true)
	var res_raid: Dictionary = camp_mgr.resolve_and_apply_raid("rival_clan", 5)
	_assert_true(res_raid.get("success", false), "TC-DIPLO.4B", "Raid resolved successfully")
	_assert_eq(emissions.size(), 1, "TC-DIPLO.4B", "Exactly 1 relation_changed emitted for settlement raid")
	if emissions.size() > 0:
		_assert_eq(emissions[0]["id"], "rival_clan", "TC-DIPLO.4B", "Signal faction_id matches")
		_assert_approx(emissions[0]["opinion"], -18.0, "TC-DIPLO.4B", "Signal opinion matches (-18.0)")
		_assert_eq(emissions[0]["disposition"], FactionData.Disposition.HOSTILE, "TC-DIPLO.4B", "Signal disposition is HOSTILE during war")

	fac_mgr.relation_changed.disconnect(on_relation_changed)

# -----------------------------------------------------------------------------
# TC-DIPLO.5: Rejected offensive campaign causes no opinion mutation and 0 signals
# -----------------------------------------------------------------------------
func _test_tc_diplo_5_rejected_attack_immutability() -> void:
	print("--- TC-DIPLO.5: Rejected offensive campaign causes zero diplomatic mutation ---")
	var s = _create_test_campaign_setup()
	var camp_mgr: BattleCampaignManager = s["camp_mgr"]
	var fac_mgr: FactionManager = s["fac_mgr"]
	var army_mgr = s["army_mgr"]
	var hostile_fac: FactionData = s["hostile_fac"]
	hostile_fac.opinion = 15.0

	var emissions: Array = []
	var on_relation_changed = func(id, op, disp):
		emissions.append({"id": id, "opinion": op, "disposition": disp})
	fac_mgr.relation_changed.connect(on_relation_changed)

	# 1. Reject: 0 soldiers
	army_mgr.soldier_count = 0
	emissions.clear()
	var r1 = camp_mgr.launch_offensive_campaign("rival_clan")
	_assert_false(r1.get("success", true), "TC-DIPLO.5", "Rejected with 0 soldiers")
	_assert_approx(hostile_fac.opinion, 15.0, "TC-DIPLO.5", "Opinion unchanged with 0 soldiers")
	_assert_eq(emissions.size(), 0, "TC-DIPLO.5", "0 signals emitted with 0 soldiers")
	army_mgr.soldier_count = 10

	# 2. Reject: garrisoned at home rally
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.GARRISONED
	army_mgr.current_cell = Vector2i(2, 2)
	emissions.clear()
	var r2 = camp_mgr.launch_offensive_campaign("rival_clan")
	_assert_false(r2.get("success", true), "TC-DIPLO.5", "Rejected when garrisoned at base")
	_assert_approx(hostile_fac.opinion, 15.0, "TC-DIPLO.5", "Opinion unchanged when garrisoned")
	_assert_eq(emissions.size(), 0, "TC-DIPLO.5", "0 signals emitted when garrisoned")
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD
	army_mgr.current_cell = Vector2i(8, 8)

	# 3. Reject: marching
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.MARCHING
	emissions.clear()
	var r3 = camp_mgr.launch_offensive_campaign("rival_clan")
	_assert_false(r3.get("success", true), "TC-DIPLO.5", "Rejected when marching")
	_assert_approx(hostile_fac.opinion, 15.0, "TC-DIPLO.5", "Opinion unchanged when marching")
	_assert_eq(emissions.size(), 0, "TC-DIPLO.5", "0 signals emitted when marching")
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD

	# 4. Reject: faction not at war
	hostile_fac.is_at_war = false
	emissions.clear()
	var r4 = camp_mgr.launch_offensive_campaign("rival_clan")
	_assert_false(r4.get("success", true), "TC-DIPLO.5", "Rejected against non-war faction")
	_assert_approx(hostile_fac.opinion, 15.0, "TC-DIPLO.5", "Opinion unchanged when not at war")
	_assert_eq(emissions.size(), 0, "TC-DIPLO.5", "0 signals emitted when not at war")
	hostile_fac.is_at_war = true

	# 5. Reject: faction with 0 military power
	hostile_fac.military_power = 0.0
	emissions.clear()
	var r5 = camp_mgr.launch_offensive_campaign("rival_clan")
	_assert_false(r5.get("success", true), "TC-DIPLO.5", "Rejected against 0 military power faction")
	_assert_approx(hostile_fac.opinion, 15.0, "TC-DIPLO.5", "Opinion unchanged with 0 power")
	_assert_eq(emissions.size(), 0, "TC-DIPLO.5", "0 signals emitted with 0 power")

	fac_mgr.relation_changed.disconnect(on_relation_changed)

# -----------------------------------------------------------------------------
# TC-DIPLO.6: Raid not due or already processed cannot apply penalty
# -----------------------------------------------------------------------------
func _test_tc_diplo_6_not_due_or_processed_raid_immutability() -> void:
	print("--- TC-DIPLO.6: Ineligible or already-processed raids cause zero opinion mutation ---")
	var s = _create_test_campaign_setup()
	var camp_mgr: BattleCampaignManager = s["camp_mgr"]
	var fac_mgr: FactionManager = s["fac_mgr"]
	var hostile_fac: FactionData = s["hostile_fac"]
	hostile_fac.opinion = -5.0

	var emissions: Array = []
	var on_relation_changed = func(id, op, disp):
		emissions.append({"id": id, "opinion": op, "disposition": disp})
	fac_mgr.relation_changed.connect(on_relation_changed)

	# Subcase A: Raid scheduled for day 8, attempted resolution on day 5 (not due)
	camp_mgr.schedule_raid("rival_clan", 8, 1, true)
	emissions.clear()
	var r_early = camp_mgr.resolve_and_apply_raid("rival_clan", 5)
	_assert_false(r_early.get("success", true), "TC-DIPLO.6A", "Early raid resolution rejected")
	_assert_approx(hostile_fac.opinion, -5.0, "TC-DIPLO.6A", "Opinion unchanged on early raid attempt")
	_assert_eq(emissions.size(), 0, "TC-DIPLO.6A", "0 signals emitted on early raid attempt")

	# Subcase B: Advance to day 8, resolve raid successfully (1 penalty, 1 emission)
	camp_mgr.set_custom_current_day(8)
	emissions.clear()
	var r_due = camp_mgr.resolve_and_apply_raid("rival_clan", 8)
	_assert_true(r_due.get("success", false), "TC-DIPLO.6B", "Due raid resolved successfully on Day 8")
	_assert_approx(hostile_fac.opinion, -15.0, "TC-DIPLO.6B", "Opinion updated on genuine resolution (-5.0 -> -15.0)")
	_assert_eq(emissions.size(), 1, "TC-DIPLO.6B", "1 signal emitted on genuine resolution")

	# Subcase C: Repeat attempt of identical raid (already processed)
	emissions.clear()
	var r_repeat = camp_mgr.resolve_and_apply_raid("rival_clan", 8)
	_assert_false(r_repeat.get("success", true), "TC-DIPLO.6C", "Repeat raid rejected as already processed")
	_assert_approx(hostile_fac.opinion, -15.0, "TC-DIPLO.6C", "Opinion unchanged on repeat raid attempt")
	_assert_eq(emissions.size(), 0, "TC-DIPLO.6C", "0 signals emitted on repeat raid attempt")

	# Subcase D: Attempt on faction with no pending raid
	emissions.clear()
	var r_none = camp_mgr.resolve_and_apply_raid("non_existent_faction", 8)
	_assert_false(r_none.get("success", true), "TC-DIPLO.6D", "Raid rejected for faction with no pending raid")
	_assert_eq(emissions.size(), 0, "TC-DIPLO.6D", "0 signals emitted for non-existent raid")

	fac_mgr.relation_changed.disconnect(on_relation_changed)

# -----------------------------------------------------------------------------
# TC-DIPLO.7: Existing hostile disposition semantics during war remain correct
# -----------------------------------------------------------------------------
func _test_tc_diplo_7_hostile_disposition_during_war() -> void:
	print("--- TC-DIPLO.7: Hostile disposition semantics during war remain strictly enforced ---")
	var fac := FactionDataScript.new("test_war_fac", "Thế Lực Thử Nghiệm", "rival_military")
	fac.is_at_war = true

	# Test various opinions while at war: disposition MUST always be HOSTILE
	var test_opinions: Array[float] = [-80.0, -40.0, -10.0, 0.0, 25.0, 50.0, 80.0]
	for op in test_opinions:
		fac.opinion = op
		fac.recalculate_disposition()
		_assert_eq(fac.disposition, FactionData.Disposition.HOSTILE, "TC-DIPLO.7", "Disposition is HOSTILE at opinion %f while at war" % op)
		_assert_true("Hostile" in fac.get_disposition_name() or "Chiến Tranh" in fac.get_disposition_name(), "TC-DIPLO.7", "Disposition name reflects Hostile/War at opinion %f" % op)

# -----------------------------------------------------------------------------
# TC-DIPLO.8: After peace is signed, disposition reflects non-war state and post-battle opinion
# -----------------------------------------------------------------------------
func _test_tc_diplo_8_post_peace_disposition_recalculation() -> void:
	print("--- TC-DIPLO.8: Post-peace disposition recalculation from post-battle opinion ---")
	var fm := FactionManagerScript.new()

	# Subcase A: Post-battle opinion remains <= -40.0 after peace boost (+20.0) -> HOSTILE
	var fac_a: FactionData = fm.get_faction("rival_military")
	fac_a.is_at_war = true
	fac_a.opinion = -70.0 # e.g. after war declaration and multiple battles
	var p_res_a = fm.propose_treaty("rival_military", "peace")
	_assert_true(p_res_a.get("success", false), "TC-DIPLO.8A", "Peace signed for rival_military")
	_assert_approx(fac_a.opinion, -50.0, "TC-DIPLO.8A", "Opinion boosted by +20.0 (-70.0 -> -50.0)")
	_assert_false(fac_a.is_at_war, "TC-DIPLO.8A", "War state ended")
	_assert_eq(fac_a.disposition, FactionData.Disposition.HOSTILE, "TC-DIPLO.8A", "Disposition remains HOSTILE (opinion <= -40.0)")

	# Subcase B: Post-battle opinion ends between -40.0 and 25.0 after peace boost -> NEUTRAL
	var fac_b := FactionDataScript.new("rival_neutral_after_peace", "Thế Lực Trung Lập", "rival_merchant")
	fac_b.is_at_war = true
	fac_b.opinion = -30.0 # e.g. after one battle
	fm._factions[fac_b.id] = fac_b
	var p_res_b = fm.propose_treaty(fac_b.id, "peace")
	_assert_true(p_res_b.get("success", false), "TC-DIPLO.8B", "Peace signed")
	_assert_approx(fac_b.opinion, -10.0, "TC-DIPLO.8B", "Opinion boosted by +20.0 (-30.0 -> -10.0)")
	_assert_eq(fac_b.disposition, FactionData.Disposition.NEUTRAL, "TC-DIPLO.8B", "Disposition is NEUTRAL (-40.0 < opinion < 25.0)")

	# Subcase C: Post-battle opinion ends between 25.0 and 75.0 after peace boost -> FRIENDLY
	var fac_c := FactionDataScript.new("rival_friendly_after_peace", "Thế Lực Thân Thiện", "neutral_tribe")
	fac_c.is_at_war = true
	fac_c.opinion = 15.0 # started very friendly, had brief war and quick peace
	fm._factions[fac_c.id] = fac_c
	var p_res_c = fm.propose_treaty(fac_c.id, "peace")
	_assert_true(p_res_c.get("success", false), "TC-DIPLO.8C", "Peace signed")
	_assert_approx(fac_c.opinion, 35.0, "TC-DIPLO.8C", "Opinion boosted by +20.0 (15.0 -> 35.0)")
	_assert_eq(fac_c.disposition, FactionData.Disposition.FRIENDLY, "TC-DIPLO.8C", "Disposition is FRIENDLY (25.0 <= opinion < 75.0)")

# -----------------------------------------------------------------------------
# TC-DIPLO.9: Real SaveManager integration restores opinion/disposition correctly & double-load
# -----------------------------------------------------------------------------
func _test_tc_diplo_9_save_load_persistence_and_idempotency() -> void:
	print("--- TC-DIPLO.9: SaveManager persistence and double-load idempotency ---")
	_assert_true(world_instance != null, "TC-DIPLO.9", "Live world_instance fixture is available")
	var live_army_mgr: PlayerArmyManager = world_instance.get("player_army_mgr")
	var live_fac_mgr: FactionManager = world_instance.get("faction_mgr")
	var live_camp_mgr: BattleCampaignManager = world_instance.get("battle_campaign_mgr")
	var live_world_data: WorldGenerator.WorldData = world_instance.get("world_data")
	var live_nav: GridNavigation = world_instance.get("nav")

	# Ensure barracks exists for sufficient capacity
	var has_barracks := false
	for b in live_world_data.buildings:
		if b.get("type") == "barracks" and b.get("state") == "active":
			has_barracks = true
			break
	if not has_barracks:
		live_world_data.buildings.append({
			"id": "bld_barracks_diplo_persist",
			"type": "barracks",
			"cell": Vector2i(26, 26),
			"size": Vector2i(3, 3),
			"state": "active",
			"construction_progress": 18.0,
			"construction_hours": 18.0
		})
	live_army_mgr.notify_capacity_changed()

	# Deploy army with positive troops to field
	live_army_mgr.soldier_count = 20
	live_army_mgr.is_supplied = true
	live_army_mgr.refresh_rally_cell()
	var live_rally: Vector2i = live_army_mgr.get_rally_cell()
	var field_target := Vector2i(live_rally.x + 4, live_rally.y)
	if not IsoMath.is_in_bounds(field_target) or not live_nav.is_cell_walkable(field_target):
		field_target = Vector2i(live_rally.x, live_rally.y + 4)

	var move_res = live_army_mgr.order_move(field_target)
	_assert_true(move_res.get("success", false), "TC-DIPLO.9", "Army ordered to field")
	for _i in range(50):
		if live_army_mgr.get_movement_state() == PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD:
			break
		live_army_mgr.advance_movement(0.5)

	# Setup target faction
	var target_fac: FactionData = live_fac_mgr.get_faction("rival_military")
	_assert_true(target_fac != null, "TC-DIPLO.9", "rival_military exists in live faction_mgr")
	target_fac.is_at_war = true
	target_fac.military_power = 150.0
	target_fac.opinion = 10.0

	# 1. Resolve offensive campaign: opinion drops 10.0 -> 2.0 (-8)
	var off_res = live_camp_mgr.launch_offensive_campaign("rival_military", 55555)
	_assert_true(off_res.get("success", false), "TC-DIPLO.9", "Offensive campaign launched on live world")
	_assert_approx(target_fac.opinion, 2.0, "TC-DIPLO.9", "Live opinion updated post-campaign (10.0 -> 2.0)")

	# Capture post-battle live state
	var post_opinion: float = target_fac.opinion
	var post_disposition: int = target_fac.disposition
	var post_soldiers: int = live_army_mgr.get_army_count()
	var post_seq: int = live_camp_mgr.get_offensive_campaign_sequence()
	var post_power: float = target_fac.military_power

	# 2. Serialize world state via SaveManager
	var saved_world: Dictionary = SaveManagerScript.serialize_world_state(world_instance)
	var val_res = SaveManagerScript.validate_save_data(saved_world)
	_assert_true(val_res.get("valid", false), "TC-DIPLO.9", "Serialized world state passes SaveManager validation")

	# Verify serialized faction data
	var saved_facs: Dictionary = saved_world.get("factions", {}).get("factions", {})
	_assert_true(saved_facs.has("rival_military"), "TC-DIPLO.9", "Save data contains rival_military")
	var saved_fac_data: Dictionary = saved_facs.get("rival_military", {})
	_assert_approx(float(saved_fac_data.get("opinion", 0.0)), post_opinion, "TC-DIPLO.9", "Serialized opinion matches post-battle opinion")
	_assert_eq(int(saved_fac_data.get("disposition", -1)), post_disposition, "TC-DIPLO.9", "Serialized disposition matches post-battle disposition")

	# 3. Perturb live in-memory values to guarantee real restoration
	target_fac.opinion = 88.0
	target_fac.disposition = FactionData.Disposition.ALLIED
	target_fac.military_power = 999.0
	live_army_mgr.soldier_count = 1

	var emissions: Array = []
	var on_relation_changed = func(id, op, disp):
		emissions.append({"id": id, "opinion": op, "disposition": disp})
	live_fac_mgr.relation_changed.connect(on_relation_changed)

	# 4. First Apply Loaded State
	emissions.clear()
	var apply_1: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, saved_world)
	_assert_true(apply_1.get("success", false), "TC-DIPLO.9 (Load 1)", "First apply_loaded_state_to_world succeeds")
	_assert_approx(target_fac.opinion, post_opinion, "TC-DIPLO.9 (Load 1)", "Restored opinion matches post-battle opinion")
	_assert_eq(target_fac.disposition, post_disposition, "TC-DIPLO.9 (Load 1)", "Restored disposition matches post-battle disposition")
	_assert_eq(live_army_mgr.get_army_count(), post_soldiers, "TC-DIPLO.9 (Load 1)", "Restored army count matches")
	_assert_eq(live_camp_mgr.get_offensive_campaign_sequence(), post_seq, "TC-DIPLO.9 (Load 1)", "Restored campaign sequence matches")
	_assert_approx(target_fac.military_power, post_power, "TC-DIPLO.9 (Load 1)", "Restored military power matches")
	_assert_eq(emissions.size(), 0, "TC-DIPLO.9 (Load 1)", "Zero relation_changed signals emitted during world loading")

	# 5. Second Apply Loaded State (Double-Load Idempotency)
	emissions.clear()
	var apply_2: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, saved_world)
	_assert_true(apply_2.get("success", false), "TC-DIPLO.9 (Load 2)", "Second apply_loaded_state_to_world succeeds")
	_assert_approx(target_fac.opinion, post_opinion, "TC-DIPLO.9 (Load 2)", "Opinion strictly unchanged on second load (no double penalty)")
	_assert_eq(target_fac.disposition, post_disposition, "TC-DIPLO.9 (Load 2)", "Disposition strictly unchanged on second load")
	_assert_eq(live_army_mgr.get_army_count(), post_soldiers, "TC-DIPLO.9 (Load 2)", "Army count strictly unchanged on second load")
	_assert_eq(emissions.size(), 0, "TC-DIPLO.9 (Load 2)", "Zero relation_changed signals emitted during second load")

	# Marker check
	var marker_count := 0
	var cit_cont = world_instance.get("citizens_container")
	if cit_cont != null:
		for child in cit_cont.get_children():
			if child.name == "ArmyMarker":
				marker_count += 1
	_assert_true(marker_count <= 1, "TC-DIPLO.9 (Load 2)", "ArmyMarker not duplicated (count = %d)" % marker_count)

	live_fac_mgr.relation_changed.disconnect(on_relation_changed)

# -----------------------------------------------------------------------------
# TC-DIPLO.10: Existing resource, military power, casualties & schedules unchanged
# -----------------------------------------------------------------------------
func _test_tc_diplo_10_combat_mechanics_unaltered() -> void:
	print("--- TC-DIPLO.10: Combat mechanics and state mutations remain unaltered ---")
	var s = _create_test_campaign_setup()
	var camp_mgr: BattleCampaignManager = s["camp_mgr"]
	var army_mgr = s["army_mgr"]
	var hostile_fac: FactionData = s["hostile_fac"]
	var mock_rm: MockResourceManager = s["mock_rm"]
	hostile_fac.opinion = 0.0
	hostile_fac.military_power = 150.0
	army_mgr.soldier_count = 15

	var prev_power: float = hostile_fac.military_power
	var prev_seq: int = camp_mgr.get_offensive_campaign_sequence()

	var res: Dictionary = camp_mgr.launch_offensive_campaign("rival_clan", 77777)
	_assert_true(res.get("success", false), "TC-DIPLO.10", "Campaign launched")

	var report: BattleResolver.BattleReport = res.get("report")
	var context: Dictionary = res.get("context", {})

	# Assert casualties and military power reduction math
	var expected_player_lost: int = report.attacker_casualties
	var expected_enemy_lost: int = report.defender_casualties
	var expected_power_loss: float = float(expected_enemy_lost) * BattleCampaignManager.MILITARY_POWER_PER_TROOP

	_assert_eq(context.get("player_casualties"), expected_player_lost, "TC-DIPLO.10", "Player casualties match report")
	_assert_eq(context.get("enemy_casualties"), expected_enemy_lost, "TC-DIPLO.10", "Enemy casualties match report")
	_assert_approx(hostile_fac.military_power, maxf(0.0, prev_power - expected_power_loss), "TC-DIPLO.10", "Military power reduced accurately")
	_assert_eq(camp_mgr.get_offensive_campaign_sequence(), prev_seq + 1, "TC-DIPLO.10", "Sequence incremented by exactly 1")
	_assert_approx(hostile_fac.opinion, -8.0, "TC-DIPLO.10", "Opinion penalty applied alongside combat mutations")

# -----------------------------------------------------------------------------
# TC-DIPLO.11: Existing gift, treaty, war declaration, peace still pass regression
# -----------------------------------------------------------------------------
func _test_tc_diplo_11_diplomacy_regression() -> void:
	print("--- TC-DIPLO.11: Existing diplomacy mechanics regression verification ---")
	var fm := FactionManagerScript.new()
	var rival_mil: FactionData = fm.get_faction("rival_military")
	var neutral: FactionData = fm.get_faction("neutral_tribe")
	var mock_rm := MockResourceManager.new()

	# 1. NAP rejected when opinion is negative (-10)
	var nap_rej = fm.propose_treaty("rival_military", "nap")
	_assert_false(nap_rej.get("success", true), "TC-DIPLO.11", "NAP rejected when opinion is negative")

	# 2. NAP accepted for neutral tribe with positive opinion (30)
	var nap_acc = fm.propose_treaty("neutral_tribe", "nap")
	_assert_true(nap_acc.get("success", false), "TC-DIPLO.11", "NAP accepted for neutral tribe")
	_assert_true(neutral.has_nap, "TC-DIPLO.11", "Neutral tribe has NAP")

	# 3. Send gift boosts opinion
	var pre_op: float = rival_mil.opinion
	var gift_res = fm.send_gift("rival_military", EconomyConfigScript.RES_GOLD, 50, mock_rm)
	_assert_true(gift_res.get("success", false), "TC-DIPLO.11", "Gift sent successfully")
	_assert_true(rival_mil.opinion > pre_op, "TC-DIPLO.11", "Opinion boosted by gift")

	# 4. Declare war breaks NAP, sets war, decreases opinion (-50)
	var pre_war_op: float = neutral.opinion
	var war_res = fm.declare_war("neutral_tribe")
	_assert_true(war_res.get("success", false), "TC-DIPLO.11", "War declared successfully")
	_assert_true(neutral.is_at_war, "TC-DIPLO.11", "Neutral tribe is now at war")
	_assert_false(neutral.has_nap, "TC-DIPLO.11", "War broke NAP")
	_assert_approx(neutral.opinion, clampf(pre_war_op - 50.0, -100.0, 100.0), "TC-DIPLO.11", "War declaration deducted 50 opinion")
	_assert_eq(neutral.disposition, FactionData.Disposition.HOSTILE, "TC-DIPLO.11", "Disposition is HOSTILE during war")

	# 5. Propose peace ends war, boosts opinion (+20), recalculates disposition
	var pre_peace_op: float = neutral.opinion
	var peace_res = fm.propose_treaty("neutral_tribe", "peace")
	_assert_true(peace_res.get("success", false), "TC-DIPLO.11", "Peace proposed successfully")
	_assert_false(neutral.is_at_war, "TC-DIPLO.11", "War ended")
	_assert_approx(neutral.opinion, clampf(pre_peace_op + 20.0, -100.0, 100.0), "TC-DIPLO.11", "Peace boosted opinion by +20.0")
