class_name TestLegacyMetaProgression
extends SceneTree

## Dedicated Automated Test Suite for Package 4B — Legacy Meta-Unlocks & World Modifiers.
## Validates persistent profile perks, world modifiers, transaction atomicity,
## new campaign initialization, save/load persistence, and cross-campaign isolation.

const LegacyProfileManagerScript = preload("res://scripts/legacy/legacy_profile_manager.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const CrisisManagerScript = preload("res://scripts/core/crisis_manager.gd")
const WorldEventSystemScript = preload("res://scripts/core/world_event_system.gd")
const TradeRouteCalculatorScript = preload("res://scripts/trade/trade_route_calculator.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")

const TEST_PROFILE_PATH: String = "user://test_meta_progression_profile.json"
const TEST_SAVE_A: String = "user://saves/test_meta_campaign_a.json"
const TEST_SAVE_B: String = "user://saves/test_meta_campaign_b.json"

class MockCappedResourceManager extends Node:
	var stock: Dictionary = {}
	var capacities: Dictionary = {}

	func _init() -> void:
		reset_economy()

	func reset_economy() -> void:
		stock = {
			"food": 150,
			"wood": 120,
			"stone": 60,
			"metal": 20,
			"tools": 15,
			"gold": 200,
			"ore": 0,
			"herbs": 10,
			"crystal": 5
		}
		for r in stock:
			capacities[r] = 1500
		capacities["gold"] = 999999

	func get_available_stock(res_id: String) -> int:
		return int(stock.get(res_id, 0))

	func get_total_stock(res_id: String) -> int:
		return int(stock.get(res_id, 0))

	func add_resource(res_id: String, amount: int) -> int:
		if amount <= 0:
			return 0
		var cur: int = int(stock.get(res_id, 0))
		var cap: int = int(capacities.get(res_id, 1500))
		var space: int = maxi(0, cap - cur)
		var to_add: int = mini(amount, space)
		stock[res_id] = cur + to_add
		return to_add

	func consume_resource(res_id: String, amount: int) -> bool:
		if get_available_stock(res_id) < amount:
			return false
		stock[res_id] = int(stock.get(res_id, 0)) - amount
		return true

var passed_count: int = 0
var failed_count: int = 0
var frame_count: int = 0
var tests_executed: bool = false

func _init() -> void:
	print("\n========================================================")
	print("  TEST SUITE: Package 4B — Legacy Meta-Unlocks & World Modifiers")
	print("========================================================\n")

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count == 2 and not tests_executed:
		tests_executed = true
		_run_all_tests()
	return false

func _run_all_tests() -> void:
	_cleanup_test_files()

	var all_ok: bool = true
	all_ok = _test_perk_and_modifier_definitions() and all_ok
	all_ok = _test_perk_purchase_insufficient_balance() and all_ok
	all_ok = _test_perk_purchase_unmet_prerequisite() and all_ok
	all_ok = _test_perk_purchase_successful_and_duplicate_prevention() and all_ok
	all_ok = _test_perk_purchase_save_failure_rollback() and all_ok
	all_ok = _test_new_campaign_starter_grain_application() and all_ok
	all_ok = _test_new_campaign_master_carpenter_application() and all_ok
	all_ok = _test_new_campaign_hardened_outposts_application() and all_ok
	all_ok = _test_new_campaign_pioneer_spirit_application() and all_ok
	all_ok = _test_world_modifier_arid_realm_integration() and all_ok
	all_ok = _test_world_modifier_harsh_winters_integration() and all_ok
	all_ok = _test_world_modifier_restless_bandits_integration() and all_ok
	all_ok = _test_combined_perk_and_modifier_predictable_interaction() and all_ok
	all_ok = _test_campaign_save_load_roundtrip_no_reapplication() and all_ok
	all_ok = _test_separate_campaigns_isolation() and all_ok
	all_ok = _test_legacy_save_compatibility_without_perks() and all_ok
	all_ok = _test_main_menu_ui_wiring_and_selection() and all_ok
	all_ok = _test_victory_reward_calculation_and_settlement() and all_ok
	all_ok = _test_collapse_zero_reward_policy() and all_ok
	all_ok = _test_reward_idempotency_and_reopened_save() and all_ok
	all_ok = _test_cross_campaign_multi_reward_and_perk_progression() and all_ok
	all_ok = _test_profile_atomic_backup_recovery_and_fail_closed() and all_ok

	_cleanup_test_files()

	print("\n========================================================")
	print("  PACKAGE 4B TEST RESULTS")
	print("  Passed: %d | Failed: %d" % [passed_count, failed_count])
	print("========================================================\n")

	if failed_count == 0:
		print("ALL PACKAGE 4B TESTS PASSED SUCCESSFULLY! (Exit Code 0)\n")
		quit(0)
	else:
		printerr("PACKAGE 4B TESTS ENCOUNTERED FAILURES! (Exit Code 1)\n")
		quit(1)

func _assert_check(condition: bool, msg: String) -> bool:
	if condition:
		passed_count += 1
		print("  [PASS] %s" % msg)
		return true
	else:
		failed_count += 1
		printerr("  [FAIL] %s" % msg)
		return false

func _cleanup_test_files() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		var to_remove: Array[String] = [
			TEST_PROFILE_PATH,
			TEST_PROFILE_PATH + ".bak",
			TEST_PROFILE_PATH + ".tmp",
			TEST_PROFILE_PATH + ".bak.old",
			TEST_SAVE_A,
			TEST_SAVE_A + ".bak",
			TEST_SAVE_B,
			TEST_SAVE_B + ".bak"
		]
		for p in to_remove:
			if FileAccess.file_exists(p):
				dir.remove(p)

func _setup_test_profile(balance: int = 0) -> RefCounted:
	_cleanup_test_files()
	var prof = LegacyProfileManagerScript.new(TEST_PROFILE_PATH)
	prof.reset_profile()
	if balance > 0:
		prof.claim_reward("test_grant_%d" % balance, "victory", balance, "world_test_init")
	return prof

# -----------------------------------------------------------------------------
# Scenario 1: Perk & Modifier Definitions
# -----------------------------------------------------------------------------
func _test_perk_and_modifier_definitions() -> bool:
	print("--- Scenario 1: Perk & Modifier Catalog Definitions ---")
	var prof := _setup_test_profile(0)
	var perks: Dictionary = prof.get_perk_definitions()
	var mods: Dictionary = prof.get_world_modifier_definitions()

	var ok: bool = true
	ok = _assert_check(perks.has("starter_grain"), "Perk 'starter_grain' defined") and ok
	ok = _assert_check(perks.has("master_carpenter"), "Perk 'master_carpenter' defined") and ok
	ok = _assert_check(perks.has("hardened_outposts"), "Perk 'hardened_outposts' defined") and ok
	ok = _assert_check(perks.has("pioneer_spirit"), "Perk 'pioneer_spirit' defined") and ok

	ok = _assert_check(perks["starter_grain"]["cost"] == 50, "starter_grain costs exactly 50 LP") and ok
	ok = _assert_check(perks["master_carpenter"]["cost"] == 75, "master_carpenter costs exactly 75 LP") and ok
	ok = _assert_check(perks["hardened_outposts"]["cost"] == 100, "hardened_outposts costs exactly 100 LP") and ok
	ok = _assert_check(perks["pioneer_spirit"]["cost"] == 120, "pioneer_spirit costs exactly 120 LP") and ok

	ok = _assert_check(perks["hardened_outposts"]["prerequisites"] == ["master_carpenter"], "hardened_outposts requires master_carpenter") and ok
	ok = _assert_check(perks["pioneer_spirit"]["prerequisites"] == ["starter_grain"], "pioneer_spirit requires starter_grain") and ok

	ok = _assert_check(mods.has("arid_realm"), "Modifier 'arid_realm' defined") and ok
	ok = _assert_check(mods.has("harsh_winters"), "Modifier 'harsh_winters' defined") and ok
	ok = _assert_check(mods.has("restless_bandits"), "Modifier 'restless_bandits' defined") and ok
	return ok

# -----------------------------------------------------------------------------
# Scenario 2: Insufficient Balance Rejection
# -----------------------------------------------------------------------------
func _test_perk_purchase_insufficient_balance() -> bool:
	print("\n--- Scenario 2: Insufficient Balance Rejection ---")
	var prof := _setup_test_profile(30)
	var ok: bool = true

	var check_res: Dictionary = prof.can_purchase_perk("starter_grain")
	ok = _assert_check(not check_res.get("can_purchase", true), "can_purchase_perk returns false on low balance") and ok
	ok = _assert_check(check_res.get("reason") == "insufficient_balance", "Reason is insufficient_balance") and ok

	var buy_res: Dictionary = prof.purchase_perk("starter_grain")
	ok = _assert_check(not buy_res.get("success", true), "purchase_perk fails on low balance") and ok
	ok = _assert_check(prof.legacy_balance == 30, "Legacy balance conserved at 30") and ok
	ok = _assert_check(prof.lifetime_legacy_spent == 0, "Lifetime spent conserved at 0") and ok
	ok = _assert_check(not prof.is_perk_unlocked("starter_grain"), "Perk remains locked") and ok
	return ok

# -----------------------------------------------------------------------------
# Scenario 3: Unmet Prerequisites Rejection
# -----------------------------------------------------------------------------
func _test_perk_purchase_unmet_prerequisite() -> bool:
	print("\n--- Scenario 3: Unmet Prerequisite Rejection ---")
	var prof := _setup_test_profile(200)
	var ok: bool = true

	var check_res: Dictionary = prof.can_purchase_perk("hardened_outposts")
	ok = _assert_check(not check_res.get("can_purchase", true), "hardened_outposts blocked when master_carpenter is locked") and ok
	ok = _assert_check(check_res.get("reason") == "unmet_prerequisites", "Reason is unmet_prerequisites") and ok
	ok = _assert_check(check_res.get("missing_prerequisite") == "master_carpenter", "Identifies missing prerequisite master_carpenter") and ok

	var buy_res: Dictionary = prof.purchase_perk("hardened_outposts")
	ok = _assert_check(not buy_res.get("success", true), "purchase_perk fails when prereqs missing") and ok
	ok = _assert_check(prof.legacy_balance == 200, "Balance conserved at 200") and ok
	return ok

# -----------------------------------------------------------------------------
# Scenario 4: Successful Purchase & Duplicate Prevention
# -----------------------------------------------------------------------------
func _test_perk_purchase_successful_and_duplicate_prevention() -> bool:
	print("\n--- Scenario 4: Successful Perk Purchase & Duplicate Prevention ---")
	var prof := _setup_test_profile(200)
	var ok: bool = true

	var buy1: Dictionary = prof.purchase_perk("master_carpenter")
	ok = _assert_check(buy1.get("success", false), "master_carpenter purchased successfully") and ok
	ok = _assert_check(prof.legacy_balance == 125, "Balance deducted to 125 (200 - 75)") and ok
	ok = _assert_check(prof.lifetime_legacy_spent == 75, "Lifetime spent increased to 75") and ok
	ok = _assert_check(prof.is_perk_unlocked("master_carpenter"), "master_carpenter is unlocked in profile") and ok

	var dup_res: Dictionary = prof.purchase_perk("master_carpenter")
	ok = _assert_check(not dup_res.get("success", true), "Duplicate purchase properly rejected") and ok
	ok = _assert_check(dup_res.get("reason") == "already_unlocked", "Reason is already_unlocked") and ok
	ok = _assert_check(prof.legacy_balance == 125, "Balance remains 125 (no double deduction)") and ok

	var buy2: Dictionary = prof.purchase_perk("hardened_outposts")
	ok = _assert_check(buy2.get("success", false), "hardened_outposts purchased successfully after prerequisite met") and ok
	ok = _assert_check(prof.legacy_balance == 25, "Balance deducted to 25 (125 - 100)") and ok
	ok = _assert_check(prof.lifetime_legacy_spent == 175, "Lifetime spent updated to 175") and ok
	ok = _assert_check(prof.is_perk_unlocked("hardened_outposts"), "hardened_outposts unlocked in profile") and ok

	var reloaded := LegacyProfileManagerScript.new(TEST_PROFILE_PATH)
	ok = _assert_check(reloaded.legacy_balance == 25, "Reloaded profile preserves balance of 25") and ok
	ok = _assert_check(reloaded.lifetime_legacy_spent == 175, "Reloaded profile preserves spent of 175") and ok
	ok = _assert_check(reloaded.is_perk_unlocked("master_carpenter"), "Reloaded profile preserves master_carpenter") and ok
	ok = _assert_check(reloaded.is_perk_unlocked("hardened_outposts"), "Reloaded profile preserves hardened_outposts") and ok
	return ok

# -----------------------------------------------------------------------------
# Scenario 5: Save Failure Rollback
# -----------------------------------------------------------------------------
func _test_perk_purchase_save_failure_rollback() -> bool:
	print("\n--- Scenario 5: Purchase Atomic Rollback on Disk Write Failure ---")
	var prof := _setup_test_profile(100)
	var ok: bool = true

	LegacyProfileManagerScript._test_inject_fail_write = true
	var res: Dictionary = prof.purchase_perk("starter_grain")
	LegacyProfileManagerScript.reset_test_injection()

	ok = _assert_check(not res.get("success", true), "Purchase rejected on disk failure") and ok
	ok = _assert_check(res.get("reason") == "save_failed", "Reason is save_failed") and ok
	ok = _assert_check(prof.legacy_balance == 100, "Balance rolled back to 100") and ok
	ok = _assert_check(prof.lifetime_legacy_spent == 0, "Lifetime spent rolled back to 0") and ok
	ok = _assert_check(not prof.is_perk_unlocked("starter_grain"), "Perk state rolled back") and ok
	return ok

# -----------------------------------------------------------------------------
# Scenario 6: New Campaign starter_grain Application
# -----------------------------------------------------------------------------
func _test_new_campaign_starter_grain_application() -> bool:
	print("\n--- Scenario 6: New Campaign starter_grain (+50 Food) Application ---")
	var scene_res = load("res://scenes/world/world_view.tscn")
	var wv: WorldView = scene_res.instantiate()
	wv.world_seed = 1001
	wv.active_perks = ["starter_grain"]
	var mock_rm := MockCappedResourceManager.new()
	wv.set_resource_mgr_for_testing(mock_rm)

	root.add_child(wv)
	var food_stock: int = mock_rm.get_available_stock("food")

	var ok: bool = true
	ok = _assert_check(food_stock == 200, "starter_grain adds +50 Food to starting stockpile (150 -> %d)" % food_stock) and ok

	root.remove_child(wv)
	wv.queue_free()
	mock_rm.queue_free()
	return ok

# -----------------------------------------------------------------------------
# Scenario 7: New Campaign master_carpenter Application
# -----------------------------------------------------------------------------
func _test_new_campaign_master_carpenter_application() -> bool:
	print("\n--- Scenario 7: New Campaign master_carpenter (+40 Wood, +10 Tools) Application ---")
	var scene_res = load("res://scenes/world/world_view.tscn")
	var wv: WorldView = scene_res.instantiate()
	wv.world_seed = 1002
	wv.active_perks = ["master_carpenter"]
	var mock_rm := MockCappedResourceManager.new()
	wv.set_resource_mgr_for_testing(mock_rm)

	root.add_child(wv)
	var wood_stock: int = mock_rm.get_available_stock("wood")
	var tool_stock: int = mock_rm.get_available_stock("tools")

	var ok: bool = true
	ok = _assert_check(wood_stock == 160, "master_carpenter adds +40 Wood (120 -> %d)" % wood_stock) and ok
	ok = _assert_check(tool_stock == 25, "master_carpenter adds +10 Tools (15 -> %d)" % tool_stock) and ok

	root.remove_child(wv)
	wv.queue_free()
	mock_rm.queue_free()
	return ok

# -----------------------------------------------------------------------------
# Scenario 8: New Campaign hardened_outposts Application
# -----------------------------------------------------------------------------
func _test_new_campaign_hardened_outposts_application() -> bool:
	print("\n--- Scenario 8: New Campaign hardened_outposts (+20 Metal, +2 Soldiers) Application ---")
	var scene_res = load("res://scenes/world/world_view.tscn")
	var wv: WorldView = scene_res.instantiate()
	wv.world_seed = 1003
	wv.active_perks = ["hardened_outposts"]
	var mock_rm := MockCappedResourceManager.new()
	wv.set_resource_mgr_for_testing(mock_rm)

	root.add_child(wv)
	var metal_stock: int = mock_rm.get_available_stock("metal")
	var soldiers: int = int(wv.player_army_mgr.get("soldier_count")) if wv.player_army_mgr != null else 0

	var ok: bool = true
	ok = _assert_check(metal_stock == 40, "hardened_outposts adds +20 Metal (20 -> %d)" % metal_stock) and ok
	ok = _assert_check(soldiers == 2, "hardened_outposts adds +2 starter soldiers (0 -> %d)" % soldiers) and ok

	root.remove_child(wv)
	wv.queue_free()
	mock_rm.queue_free()
	return ok

# -----------------------------------------------------------------------------
# Scenario 9: New Campaign pioneer_spirit Application
# -----------------------------------------------------------------------------
func _test_new_campaign_pioneer_spirit_application() -> bool:
	print("\n--- Scenario 9: New Campaign pioneer_spirit (+10 Morale) Application ---")
	var scene_res = load("res://scenes/world/world_view.tscn")
	var wv: WorldView = scene_res.instantiate()
	wv.world_seed = 1004
	wv.active_perks = ["pioneer_spirit"]
	var mock_rm := MockCappedResourceManager.new()
	wv.set_resource_mgr_for_testing(mock_rm)

	root.add_child(wv)
	var ok: bool = true

	var total_morale: float = 0.0
	var cit_count: int = wv.citizen_list.size()
	for cit in wv.citizen_list:
		total_morale += float(cit.get("morale"))
	var avg_morale: float = total_morale / float(maxi(1, cit_count))

	ok = _assert_check(is_equal_approx(avg_morale, 80.0), "pioneer_spirit increases initial average morale from 70 to 80 (observed: %.1f)" % avg_morale) and ok

	root.remove_child(wv)
	wv.queue_free()
	mock_rm.queue_free()
	return ok

# -----------------------------------------------------------------------------
# Scenario 10: World Modifier arid_realm Integration
# -----------------------------------------------------------------------------
func _test_world_modifier_arid_realm_integration() -> bool:
	print("\n--- Scenario 10: World Modifier arid_realm (-20 Wood, -15%% Summer Farm) ---")
	var scene_res = load("res://scenes/world/world_view.tscn")
	var wv: WorldView = scene_res.instantiate()
	wv.world_seed = 1005
	wv.world_modifiers = ["arid_realm"]
	var mock_rm := MockCappedResourceManager.new()
	wv.set_resource_mgr_for_testing(mock_rm)

	root.add_child(wv)
	var wood_stock: int = mock_rm.get_available_stock("wood")

	var ok: bool = true
	ok = _assert_check(wood_stock == 100, "arid_realm consumes 20 starting Wood (120 -> %d)" % wood_stock) and ok

	var summer_mult: float = wv.event_system.get_farm_production_multiplier(1.20)
	ok = _assert_check(is_equal_approx(summer_mult, 1.02), "arid_realm reduces summer farm multiplier by 15%% (1.20 -> %.2f)" % summer_mult) and ok

	var spring_mult: float = wv.event_system.get_farm_production_multiplier(1.00)
	ok = _assert_check(is_equal_approx(spring_mult, 1.00), "arid_realm preserves normal spring multiplier (1.00 -> %.2f)" % spring_mult) and ok

	root.remove_child(wv)
	wv.queue_free()
	mock_rm.queue_free()
	return ok

# -----------------------------------------------------------------------------
# Scenario 11: World Modifier harsh_winters Integration
# -----------------------------------------------------------------------------
func _test_world_modifier_harsh_winters_integration() -> bool:
	print("\n--- Scenario 11: World Modifier harsh_winters (3 Wood/hr, +25%% Extra Fatigue) ---")
	var cm := CrisisManagerScript.new(12345)
	var ok: bool = true

	cm.set_world_modifiers([])
	cm.trigger_crisis(CrisisManagerScript.CRISIS_BLIZZARD, true, 48.0, true)
	var base_fatigue: float = cm.get_citizen_fatigue_multiplier()
	ok = _assert_check(is_equal_approx(base_fatigue, 1.50), "Baseline blizzard fatigue is 1.50") and ok

	cm.set_world_modifiers(["harsh_winters"])
	var harsh_fatigue: float = cm.get_citizen_fatigue_multiplier()
	ok = _assert_check(is_equal_approx(harsh_fatigue, 1.75), "harsh_winters increases blizzard fatigue to 1.75 (+25%% extra)") and ok

	var mock_rm := MockCappedResourceManager.new()
	mock_rm.stock["wood"] = 10
	cm._process_blizzard_hour(mock_rm, [], null, 1)
	ok = _assert_check(mock_rm.stock["wood"] == 7, "harsh_winters consumes 3 Wood/hour instead of 2 (10 -> %d)" % mock_rm.stock["wood"]) and ok

	mock_rm.queue_free()
	return ok

# -----------------------------------------------------------------------------
# Scenario 12: World Modifier restless_bandits Integration
# -----------------------------------------------------------------------------
func _test_world_modifier_restless_bandits_integration() -> bool:
	print("\n--- Scenario 12: World Modifier restless_bandits (+3 Raid Threat, +10%% Route Risk) ---")
	var cm := CrisisManagerScript.new(12345)
	cm.set_world_modifiers(["restless_bandits"])
	var ok: bool = true

	var raid_res: Dictionary = cm.resolve_bandit_raid(null, null, [], null, null)
	var threat: int = int(raid_res.get("threat_strength", 0))
	ok = _assert_check(threat >= 11 and threat <= 17, "restless_bandits increases base raid threat by +3 (range 11..17, observed: %d)" % threat) and ok

	var route_risk: Dictionary = TradeRouteCalculatorScript.evaluate_route_risk(
		[], null, null, null, false, ["restless_bandits"]
	)
	var net_r: float = float(route_risk.get("net_risk", 0.0))
	ok = _assert_check(is_equal_approx(net_r, 0.10), "restless_bandits adds +0.10 (+10%%) danger to trade route risk (observed: %.2f)" % net_r) and ok

	return ok

# -----------------------------------------------------------------------------
# Scenario 13: Combined Perk and Modifier Predictable Interaction
# -----------------------------------------------------------------------------
func _test_combined_perk_and_modifier_predictable_interaction() -> bool:
	print("\n--- Scenario 13: Combined Perk and Modifier Predictable Interaction ---")
	var scene_res = load("res://scenes/world/world_view.tscn")
	var wv: WorldView = scene_res.instantiate()
	wv.world_seed = 1006
	wv.active_perks = ["master_carpenter"]
	wv.world_modifiers = ["arid_realm"]
	var mock_rm := MockCappedResourceManager.new()
	wv.set_resource_mgr_for_testing(mock_rm)

	root.add_child(wv)
	var wood_stock: int = mock_rm.get_available_stock("wood")

	var ok: bool = true
	# Base 120 + 40 (perk) - 20 (modifier) = 140
	ok = _assert_check(wood_stock == 140, "master_carpenter (+40) and arid_realm (-20) combine additively to 140 Wood (observed: %d)" % wood_stock) and ok

	root.remove_child(wv)
	wv.queue_free()
	mock_rm.queue_free()
	return ok

# -----------------------------------------------------------------------------
# Scenario 14: Save/Load Roundtrip & Zero Re-application
# -----------------------------------------------------------------------------
func _test_campaign_save_load_roundtrip_no_reapplication() -> bool:
	print("\n--- Scenario 14: Save/Load Roundtrip & Zero Re-application ---")
	var rm: Node = root.get_node_or_null("ResourceManager")
	if rm != null:
		rm.call("reset_economy")

	var scene_res = load("res://scenes/world/world_view.tscn")
	var wv: WorldView = scene_res.instantiate()
	wv.world_seed = 1007
	wv.active_perks = ["starter_grain", "master_carpenter"]
	wv.world_modifiers = ["harsh_winters"]

	root.add_child(wv)
	var initial_food: int = rm.get_available_stock("food") if rm != null else 200
	var initial_wood: int = rm.get_available_stock("wood") if rm != null else 160

	var save_res: Dictionary = SaveManagerScript.save_to_file(wv, TEST_SAVE_A)
	var ok: bool = true
	ok = _assert_check(save_res.get("success", false), "Campaign saved to disk successfully") and ok

	if rm != null:
		rm.consume_resource("food", 30)
		var progressed_food: int = rm.get_available_stock("food")
		ok = _assert_check(progressed_food == initial_food - 30, "Live food stock progressed") and ok

	var load_res: Dictionary = SaveManagerScript.load_from_file(TEST_SAVE_A)
	ok = _assert_check(load_res.get("success", false), "Save file loaded successfully") and ok
	var apply_res: Dictionary = SaveManagerScript.apply_loaded_state_to_world(wv, load_res.get("data", {}))
	ok = _assert_check(apply_res.get("success", false), "Loaded state applied successfully") and ok

	ok = _assert_check(wv.active_perks.has("starter_grain") and wv.active_perks.has("master_carpenter"), "Active perks preserved across Save/Load") and ok
	ok = _assert_check(wv.world_modifiers.has("harsh_winters"), "World modifiers preserved across Save/Load") and ok
	ok = _assert_check(wv.crisis_mgr.get_world_modifiers().has("harsh_winters"), "CrisisManager world modifiers restored") and ok

	# Food and Wood restored to exact saved state without double-dipping perk bonus!
	var restored_food: int = rm.get_available_stock("food") if rm != null else 200
	var restored_wood: int = rm.get_available_stock("wood") if rm != null else 160
	ok = _assert_check(restored_food == initial_food, "Food restored to saved state (%d), zero double-application" % restored_food) and ok
	ok = _assert_check(restored_wood == initial_wood, "Wood restored to saved state (%d), zero double-application" % restored_wood) and ok

	root.remove_child(wv)
	wv.queue_free()
	return ok

# -----------------------------------------------------------------------------
# Scenario 15: Separate Campaign Isolation
# -----------------------------------------------------------------------------
func _test_separate_campaigns_isolation() -> bool:
	print("\n--- Scenario 15: Cross-Campaign Isolation (No Modifier Contamination) ---")
	var scene_res = load("res://scenes/world/world_view.tscn")

	# World A with harsh_winters
	var wv_a: WorldView = scene_res.instantiate()
	wv_a.world_seed = 2001
	wv_a.world_modifiers = ["harsh_winters"]
	var mock_a := MockCappedResourceManager.new()
	wv_a.set_resource_mgr_for_testing(mock_a)
	root.add_child(wv_a)
	SaveManagerScript.save_to_file(wv_a, TEST_SAVE_A)
	root.remove_child(wv_a)
	wv_a.queue_free()
	mock_a.queue_free()

	# World B with arid_realm
	var wv_b: WorldView = scene_res.instantiate()
	wv_b.world_seed = 2002
	wv_b.world_modifiers = ["arid_realm"]
	var mock_b := MockCappedResourceManager.new()
	wv_b.set_resource_mgr_for_testing(mock_b)
	root.add_child(wv_b)
	SaveManagerScript.save_to_file(wv_b, TEST_SAVE_B)

	# Reload World A into wv_b
	var load_a: Dictionary = SaveManagerScript.load_from_file(TEST_SAVE_A)
	SaveManagerScript.apply_loaded_state_to_world(wv_b, load_a.get("data", {}))

	var ok: bool = true
	ok = _assert_check(wv_b.world_modifiers == ["harsh_winters"], "Reloaded World A has ONLY harsh_winters") and ok
	ok = _assert_check(not wv_b.world_modifiers.has("arid_realm"), "Zero leakage of arid_realm from World B into World A") and ok

	root.remove_child(wv_b)
	wv_b.queue_free()
	mock_b.queue_free()
	return ok

# -----------------------------------------------------------------------------
# Scenario 16: Legacy Save Compatibility Without Perks/Modifiers
# -----------------------------------------------------------------------------
func _test_legacy_save_compatibility_without_perks() -> bool:
	print("\n--- Scenario 16: Legacy Save Compatibility (Missing Perks/Modifiers) ---")
	var scene_res = load("res://scenes/world/world_view.tscn")
	var wv: WorldView = scene_res.instantiate()
	wv.world_seed = 3001
	var mock_rm := MockCappedResourceManager.new()
	wv.set_resource_mgr_for_testing(mock_rm)
	root.add_child(wv)

	var state := SaveManagerScript.serialize_world_state(wv)
	state["metadata"].erase("active_perks")
	state["metadata"].erase("world_modifiers")

	var val_res := SaveManagerScript.validate_save_data(state)
	var ok: bool = true
	ok = _assert_check(val_res.get("valid", false), "Legacy save without perks passes validate_save_data") and ok

	var apply_res := SaveManagerScript.apply_loaded_state_to_world(wv, state)
	ok = _assert_check(apply_res.get("success", false), "Legacy save loads and applies cleanly") and ok
	ok = _assert_check(wv.active_perks.is_empty(), "Active perks default to empty array") and ok
	ok = _assert_check(wv.world_modifiers.is_empty(), "World modifiers default to empty array") and ok

	root.remove_child(wv)
	wv.queue_free()
	mock_rm.queue_free()
	return ok

# -----------------------------------------------------------------------------
# Scenario 17: Main Menu UI Wiring & Selection
# -----------------------------------------------------------------------------
func _test_main_menu_ui_wiring_and_selection() -> bool:
	print("\n--- Scenario 17: Main Menu UI Wiring & Selection ---")
	var prof := _setup_test_profile(200)
	LegacyProfileManagerScript.set_instance(prof)

	var menu_scene = load("res://scenes/ui/main_menu.tscn")
	var menu: MainMenu = menu_scene.instantiate()
	root.add_child(menu)

	var ok: bool = true
	var fund_label: Label = menu.get_node_or_null("CenterContainer/MainPanel/MarginContainer/VBoxContainer/TitleBox/LegacyFundLabel")
	ok = _assert_check(fund_label != null and fund_label.text.contains("200"), "MainMenu displays Quỹ Di Sản: 200 điểm") and ok

	ok = _assert_check(menu.perk_checkboxes.has("starter_grain"), "Perk checkbox for starter_grain exists") and ok
	ok = _assert_check(menu.perk_buttons.has("starter_grain"), "Unlock button for starter_grain exists") and ok

	menu._on_unlock_perk_pressed("starter_grain")
	ok = _assert_check(prof.is_perk_unlocked("starter_grain"), "starter_grain unlocked in profile via UI") and ok
	ok = _assert_check(prof.legacy_balance == 150, "Balance updated to 150 (200 - 50)") and ok
	ok = _assert_check(fund_label.text.contains("150"), "MainMenu label refreshed to 150 điểm") and ok

	menu.set_modifier_selected("harsh_winters", true)
	var selected_mods := menu.get_selected_modifiers()
	ok = _assert_check(selected_mods.has("harsh_winters"), "harsh_winters selected in UI") and ok

	menu.set_perk_selected("starter_grain", true)
	var selected_perks := menu.get_selected_perks()
	ok = _assert_check(selected_perks.has("starter_grain"), "starter_grain selected in UI") and ok

	root.remove_child(menu)
	menu.queue_free()
	LegacyProfileManagerScript.reset_instance()
	return ok

# -----------------------------------------------------------------------------
# Scenario 18: Victory Reward Calculation & Settlement Integration
# -----------------------------------------------------------------------------
func _test_victory_reward_calculation_and_settlement() -> bool:
	print("\n--- Scenario 18: Victory Reward Calculation & Settlement Integration ---")
	var prof := _setup_test_profile(0)
	LegacyProfileManagerScript.set_instance(prof)

	var scene_res = load("res://scenes/world/world_view.tscn")
	var wv: WorldView = scene_res.instantiate()
	wv.world_seed = 6001
	root.add_child(wv)

	var rm: Node = root.get_node_or_null("ResourceManager")
	if rm != null:
		rm.call("reset_economy")
		rm.call("add_resource", "gold", 3300) # Total 3500 gold (200 initial + 3300)

	# Save world to establish valid persisted world_id
	SaveManagerScript.save_to_file(wv, TEST_SAVE_A)
	var wid: String = wv.world_id

	var vic_mgr: VictoryManager = wv.victory_mgr
	vic_mgr.is_victory_achieved = true
	vic_mgr.legacy_points_earned = 100

	# Preview conversion: 3500 gold, 85% stability -> 1000 protected, 2500 surplus -> 25 legacy points, 2500 gold deducted
	var preview: Dictionary = vic_mgr.preview_treasury_conversion(3500, 85.0)
	var ok: bool = true
	ok = _assert_check(preview.get("eligible", false) == true, "Treasury conversion is eligible") and ok
	ok = _assert_check(preview.get("legacy_awarded", 0) == 25, "Preview awards exactly +25 Legacy Points") and ok
	ok = _assert_check(preview.get("gold_deducted", 0) == 2500, "Preview deducts exactly 2500 Gold") and ok
	ok = _assert_check(preview.get("remaining_gold", 0) == 1000, "Remaining Gold is 1000 (protected reserve)") and ok

	# Finalize victory settlement
	var res: Dictionary = vic_mgr.finalize_victory_settlement(rm, 85.0)
	ok = _assert_check(res.get("success", false) == true, "Settlement finalized successfully") and ok
	ok = _assert_check(res.get("victory_points_awarded", 0) == 100, "Victory awards 100 LP") and ok
	ok = _assert_check(res.get("treasury_points_awarded", 0) == 25, "Treasury awards 25 LP") and ok
	ok = _assert_check(res.get("total_legacy_awarded", 0) == 125, "Total settlement awards 125 LP (100 + 25)") and ok
	ok = _assert_check(prof.legacy_balance == 125, "Legacy balance updated to 125") and ok
	ok = _assert_check(prof.lifetime_legacy_earned == 125, "Lifetime earned updated to 125") and ok
	ok = _assert_check(prof.lifetime_legacy_spent == 0, "Lifetime spent is 0") and ok
	ok = _assert_check(prof.is_reward_claimed("victory_" + wid), "Base victory reward recorded in claimed_rewards") and ok
	ok = _assert_check(prof.is_reward_claimed("treasury_conv_" + wid), "Treasury conversion recorded in claimed_rewards") and ok
	ok = _assert_check(rm.call("get_available_stock", "gold") == 1000, "Remaining Gold stock is exactly 1000") and ok

	root.remove_child(wv)
	wv.queue_free()
	return ok

# -----------------------------------------------------------------------------
# Scenario 19: Collapse Zero-Reward Policy & Summary Report
# -----------------------------------------------------------------------------
func _test_collapse_zero_reward_policy() -> bool:
	print("\n--- Scenario 19: Collapse Zero-Reward Policy & Summary Report ---")
	var prof := _setup_test_profile(125)
	LegacyProfileManagerScript.set_instance(prof)

	var scene_res = load("res://scenes/world/world_view.tscn")
	var wv: WorldView = scene_res.instantiate()
	wv.world_seed = 6002
	root.add_child(wv)

	var rm: Node = root.get_node_or_null("ResourceManager")
	if rm != null:
		rm.call("reset_economy")
		rm.call("add_resource", "gold", 3800) # Total 4000 gold

	SaveManagerScript.save_to_file(wv, TEST_SAVE_B)

	var vic_mgr: VictoryManager = wv.victory_mgr
	vic_mgr.is_victory_achieved = true
	vic_mgr.is_collapse_triggered = true
	vic_mgr.primary_collapse_reason = "Tuyệt chủng: Toàn bộ cư dân đã qua đời vì nạn đói hoặc kiệt sức."

	var preview: Dictionary = vic_mgr.preview_treasury_conversion(4000, 0.0)
	var ok: bool = true
	ok = _assert_check(preview.get("eligible", true) == false, "Treasury conversion rejected on collapse") and ok
	ok = _assert_check(preview.get("status") == "collapsed", "Status is 'collapsed'") and ok
	ok = _assert_check(preview.get("legacy_awarded", -1) == 0, "Zero legacy awarded on collapse") and ok

	var report: Dictionary = vic_mgr.generate_summary_report("COLLAPSE", 0, 0, 4000, 0.0, 0.0, 2, 5)
	ok = _assert_check(report.get("outcome") == "COLLAPSE", "Summary outcome is COLLAPSE") and ok
	ok = _assert_check(report.get("legacy_points", -1) == 0, "Summary legacy points earned is 0") and ok

	var res: Dictionary = vic_mgr.finalize_victory_settlement(rm, 0.0)
	ok = _assert_check(res.get("success", true) == false, "Finalize settlement rejected on collapse") and ok
	ok = _assert_check(res.get("reason") == "collapse_triggered", "Reason is collapse_triggered") and ok
	ok = _assert_check(rm.call("get_available_stock", "gold") == 4000, "Gold conserved at 4000 (no deduction)") and ok
	ok = _assert_check(prof.legacy_balance == 125, "Profile balance conserved at 125 (zero gain/loss)") and ok

	root.remove_child(wv)
	wv.queue_free()
	return ok

# -----------------------------------------------------------------------------
# Scenario 20: Reward Idempotency, Repeated Settlement & Reopened Save
# -----------------------------------------------------------------------------
func _test_reward_idempotency_and_reopened_save() -> bool:
	print("\n--- Scenario 20: Reward Idempotency, Repeated Settlement & Reopened Save ---")
	var prof := _setup_test_profile(0)
	LegacyProfileManagerScript.set_instance(prof)

	var scene_res = load("res://scenes/world/world_view.tscn")
	var wv: WorldView = scene_res.instantiate()
	wv.world_seed = 6003
	root.add_child(wv)

	var rm: Node = root.get_node_or_null("ResourceManager")
	if rm != null:
		rm.call("reset_economy")
		rm.call("add_resource", "gold", 1800) # Total 2000 gold

	SaveManagerScript.save_to_file(wv, TEST_SAVE_A)
	var wid: String = wv.world_id

	var vic_mgr: VictoryManager = wv.victory_mgr
	vic_mgr.is_victory_achieved = true
	vic_mgr.legacy_points_earned = 100

	# 1st Settlement: Earn 100 (victory) + 10 (surplus: 1000 / 100) = 110 LP
	var res1: Dictionary = vic_mgr.finalize_victory_settlement(rm, 85.0)
	var ok: bool = true
	ok = _assert_check(res1.get("success", false) == true, "1st settlement succeeded") and ok
	ok = _assert_check(res1.get("total_legacy_awarded", 0) == 110, "1st settlement awarded 110 LP") and ok
	ok = _assert_check(prof.legacy_balance == 110, "Balance is 110") and ok

	# 2nd Immediate Settlement Attempt on same live instance
	var res2: Dictionary = vic_mgr.finalize_victory_settlement(rm, 85.0)
	ok = _assert_check(res2.get("success", true) == false, "2nd settlement call rejected") and ok
	ok = _assert_check(res2.get("total_legacy_awarded", -1) == 0, "2nd call awards 0 LP") and ok
	ok = _assert_check(prof.legacy_balance == 110, "Balance invariant holds at 110 (no double-crediting)") and ok

	# Save world in settled state
	SaveManagerScript.save_to_file(wv, TEST_SAVE_A)
	root.remove_child(wv)
	wv.queue_free()

	# Reload completed campaign from disk into fresh WorldView
	var wv_reloaded: WorldView = scene_res.instantiate()
	wv_reloaded.world_seed = 6003
	root.add_child(wv_reloaded)
	var load_res: Dictionary = SaveManagerScript.load_from_file(TEST_SAVE_A)
	SaveManagerScript.apply_loaded_state_to_world(wv_reloaded, load_res.get("data", {}))

	var reloaded_vic: VictoryManager = wv_reloaded.victory_mgr
	ok = _assert_check(reloaded_vic.is_legacy_claimed == true, "Restored world preserves is_legacy_claimed == true") and ok
	ok = _assert_check(reloaded_vic.is_treasury_converted == true, "Restored world preserves is_treasury_converted == true") and ok

	# 3rd Settlement Attempt on reloaded completed save
	var res3: Dictionary = reloaded_vic.finalize_victory_settlement(rm, 85.0)
	ok = _assert_check(res3.get("success", true) == false, "3rd settlement on reloaded save rejected") and ok
	ok = _assert_check(res3.get("total_legacy_awarded", -1) == 0, "Zero points awarded on reloaded save") and ok
	ok = _assert_check(prof.legacy_balance == 110, "Balance conserved at 110 across reloads") and ok

	# Direct backend API duplicate claim rejection
	var direct_claim: Dictionary = prof.claim_reward("victory_" + wid, "victory", 100, wid)
	ok = _assert_check(direct_claim.get("success", true) == false, "Direct backend claim rejected duplicate reward") and ok
	ok = _assert_check(direct_claim.get("reason") == "already_claimed", "Direct backend reason is already_claimed") and ok

	root.remove_child(wv_reloaded)
	wv_reloaded.queue_free()
	return ok

# -----------------------------------------------------------------------------
# Scenario 21: Cross-Campaign Multi-Reward & Perk Progression Flow
# -----------------------------------------------------------------------------
func _test_cross_campaign_multi_reward_and_perk_progression() -> bool:
	print("\n--- Scenario 21: Cross-Campaign Multi-Reward & Perk Progression Flow ---")
	var prof := _setup_test_profile(0)
	LegacyProfileManagerScript.set_instance(prof)

	var scene_res = load("res://scenes/world/world_view.tscn")
	var rm: Node = root.get_node_or_null("ResourceManager")

	# --- Campaign A Genesis & Victory ---
	var wv_a: WorldView = scene_res.instantiate()
	wv_a.world_seed = 7001
	root.add_child(wv_a)
	if rm != null:
		rm.call("reset_economy")
	SaveManagerScript.save_to_file(wv_a, TEST_SAVE_A)
	var wid_a: String = wv_a.world_id

	var vic_a: VictoryManager = wv_a.victory_mgr
	vic_a.is_victory_achieved = true
	vic_a.legacy_points_earned = 100
	var res_a: Dictionary = vic_a.finalize_victory_settlement(rm, 85.0)

	var ok: bool = true
	ok = _assert_check(res_a.get("success", false) == true, "Campaign A settled successfully") and ok
	ok = _assert_check(prof.legacy_balance == 100, "Campaign A awarded 100 LP (balance: 100)") and ok
	root.remove_child(wv_a)
	wv_a.queue_free()

	# --- Main Menu: Purchase master_carpenter (75 LP) ---
	var pur1: Dictionary = prof.purchase_perk("master_carpenter")
	ok = _assert_check(pur1.get("success", false) == true, "master_carpenter purchased for 75 LP") and ok
	ok = _assert_check(prof.legacy_balance == 25, "Balance deducted to 25 (100 - 75)") and ok
	ok = _assert_check(prof.is_perk_unlocked("master_carpenter"), "master_carpenter unlocked in profile") and ok

	# --- Campaign B Genesis with master_carpenter active ---
	if rm != null:
		rm.call("reset_economy")
	var wv_b: WorldView = scene_res.instantiate()
	wv_b.world_seed = 7002
	wv_b.active_perks = ["master_carpenter"]
	root.add_child(wv_b)
	if rm != null:
		ok = _assert_check(rm.call("get_available_stock", "wood") == 160, "Campaign B starts with 160 Wood from master_carpenter") and ok
		rm.call("add_resource", "gold", 1800) # Total 2000 gold

	SaveManagerScript.save_to_file(wv_b, TEST_SAVE_B)
	var wid_b: String = wv_b.world_id

	var vic_b: VictoryManager = wv_b.victory_mgr
	vic_b.is_victory_achieved = true
	vic_b.legacy_points_earned = 100
	var res_b: Dictionary = vic_b.finalize_victory_settlement(rm, 85.0)

	ok = _assert_check(res_b.get("success", false) == true, "Campaign B settled successfully") and ok
	ok = _assert_check(res_b.get("total_legacy_awarded", 0) == 110, "Campaign B awarded 110 LP (100 victory + 10 surplus)") and ok
	ok = _assert_check(prof.legacy_balance == 135, "Balance updated to 135 (25 + 110)") and ok
	ok = _assert_check(prof.lifetime_legacy_earned == 210, "Lifetime earned is 210 (100 + 110)") and ok
	ok = _assert_check(prof.lifetime_legacy_spent == 75, "Lifetime spent is 75") and ok
	ok = _assert_check(prof.legacy_balance == prof.lifetime_legacy_earned - prof.lifetime_legacy_spent, "Balance invariant holds: 135 == 210 - 75") and ok

	root.remove_child(wv_b)
	wv_b.queue_free()

	# --- Unlock hardened_outposts (100 LP, requires master_carpenter) ---
	var pur2: Dictionary = prof.purchase_perk("hardened_outposts")
	ok = _assert_check(pur2.get("success", false) == true, "hardened_outposts unlocked successfully") and ok
	ok = _assert_check(prof.legacy_balance == 35, "Balance updated to 35 (135 - 100)") and ok
	ok = _assert_check(prof.lifetime_legacy_spent == 175, "Lifetime spent updated to 175 (75 + 100)") and ok
	ok = _assert_check(prof.legacy_balance == prof.lifetime_legacy_earned - prof.lifetime_legacy_spent, "Balance invariant holds: 35 == 210 - 175") and ok

	# --- Simulate Application Restart ---
	LegacyProfileManagerScript.reset_instance()
	var reloaded_prof = LegacyProfileManagerScript.new(TEST_PROFILE_PATH)
	LegacyProfileManagerScript.set_instance(reloaded_prof)

	ok = _assert_check(reloaded_prof.legacy_balance == 35, "Restarted profile balance is 35") and ok
	ok = _assert_check(reloaded_prof.lifetime_legacy_earned == 210, "Restarted profile lifetime earned is 210") and ok
	ok = _assert_check(reloaded_prof.lifetime_legacy_spent == 175, "Restarted profile lifetime spent is 175") and ok
	ok = _assert_check(reloaded_prof.is_perk_unlocked("master_carpenter") == true, "master_carpenter persists across restart") and ok
	ok = _assert_check(reloaded_prof.is_perk_unlocked("hardened_outposts") == true, "hardened_outposts persists across restart") and ok
	ok = _assert_check(reloaded_prof.is_reward_claimed("victory_" + wid_a) == true, "Campaign A reward claim persisted") and ok
	ok = _assert_check(reloaded_prof.is_reward_claimed("victory_" + wid_b) == true, "Campaign B reward claim persisted") and ok
	ok = _assert_check(reloaded_prof.is_reward_claimed("treasury_conv_" + wid_b) == true, "Campaign B treasury claim persisted") and ok

	return ok

# -----------------------------------------------------------------------------
# Scenario 22: Profile Atomic Backup Recovery & Corrupt File Handling
# -----------------------------------------------------------------------------
func _test_profile_atomic_backup_recovery_and_fail_closed() -> bool:
	print("\n--- Scenario 22: Profile Atomic Backup Recovery & Corrupt File Handling ---")
	var prof := _setup_test_profile(50)
	prof.save_profile()

	var ok: bool = true
	ok = _assert_check(FileAccess.file_exists(TEST_PROFILE_PATH), "Primary profile exists on disk") and ok
	ok = _assert_check(FileAccess.file_exists(TEST_PROFILE_PATH + ".bak"), "Backup profile .bak exists on disk") and ok

	# 1. Corrupt primary profile with malformed JSON
	var f := FileAccess.open(TEST_PROFILE_PATH, FileAccess.WRITE)
	f.store_string("<<<INVALID JSON SYNTAX DUMP>>>")
	f.close()

	# Instantiate fresh manager to test automatic recovery
	var recov_mgr = LegacyProfileManagerScript.new(TEST_PROFILE_PATH)
	ok = _assert_check(recov_mgr.is_available() == true, "Recovered profile is available") and ok
	ok = _assert_check(recov_mgr.legacy_balance == 50, "Recovered profile restored balance 50 from .bak") and ok

	# 2. Corrupt BOTH primary and .bak
	var f1 := FileAccess.open(TEST_PROFILE_PATH, FileAccess.WRITE)
	f1.store_string("<<<CORRUPT PRIMARY>>>")
	f1.close()
	var f2 := FileAccess.open(TEST_PROFILE_PATH + ".bak", FileAccess.WRITE)
	f2.store_string("<<<CORRUPT BAK>>>")
	f2.close()

	var fail_mgr = LegacyProfileManagerScript.new(TEST_PROFILE_PATH)
	ok = _assert_check(fail_mgr.is_available() == false, "Manager fails closed when all copies corrupt") and ok

	var reject_claim: Dictionary = fail_mgr.claim_reward("test_fail", "victory", 100, "world_fail")
	ok = _assert_check(reject_claim.get("success", true) == false, "Claim rejected on unavailable profile") and ok
	ok = _assert_check(reject_claim.get("reason") == "profile_unavailable", "Reason is profile_unavailable") and ok

	var reject_buy: Dictionary = fail_mgr.purchase_perk("starter_grain")
	ok = _assert_check(reject_buy.get("success", true) == false, "Purchase rejected on unavailable profile") and ok
	ok = _assert_check(reject_buy.get("reason") == "profile_unavailable", "Reason is profile_unavailable") and ok

	return ok

