extends SceneTree
## =============================================================================
## KINGDOMS UNBOUND — Package 2C Regression Test Suite
## Surplus Treasury Conversion & Victory Settlement Integration
## =============================================================================
## File: scripts/test/test_surplus_treasury_conversion.gd
## Validates all 14 authoritative requirements for Package 2C.
## =============================================================================

const LegacyProfileManager = preload("res://scripts/legacy/legacy_profile_manager.gd")
const VictoryManager = preload("res://scripts/core/victory_manager.gd")
const SaveManager = preload("res://scripts/persistence/save_manager.gd")
const WorldViewScene = preload("res://scenes/world/world_view.tscn")
const HudScene = preload("res://scenes/ui/hud.tscn")

const TEST_PROFILE_PATH: String = "user://test_p2c_profile.json"
const TEST_PROFILE_BAK: String = "user://test_p2c_profile.json.bak"
const TEST_PROFILE_TMP: String = "user://test_p2c_profile.json.tmp"
const TEST_SAVE_PATH: String = "user://saves/test_p2c_save.json"

var total_tests: int = 0
var passed_tests: int = 0
var world_instance: Node = null
var frame_count: int = 0

func _cleanup_test_files() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		for p in [TEST_PROFILE_PATH, TEST_PROFILE_BAK, TEST_PROFILE_TMP, TEST_SAVE_PATH, TEST_SAVE_PATH + ".bak", TEST_SAVE_PATH + ".tmp"]:
			if FileAccess.file_exists(p):
				dir.remove(p)

func _assert(cond: bool, test_name: String, msg: String = "") -> bool:
	total_tests += 1
	if cond:
		passed_tests += 1
		print("  [PASS] %s" % test_name)
		return true
	else:
		printerr("  ❌ [FAIL] %s: %s" % [test_name, msg])
		return false

func _init() -> void:
	print("\n========================================================")
	print("  TEST SUITE: Package 2C — Surplus Treasury Conversion")
	print("========================================================\n")

	_cleanup_test_files()
	SaveManager.set_test_default_save_path(TEST_SAVE_PATH)

	world_instance = WorldViewScene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count == 3:
		_run_all_tests()
		return true
	return false

func _run_all_tests() -> void:
	test_1_5000_gold_85_stability()
	test_2_5050_gold_85_stability()
	test_3_1100_gold_85_stability()
	test_4_treasury_at_or_below_1000()
	test_5_stability_below_80_percent()
	test_6_collapsed_defeated_kingdom()
	test_7_invalid_or_missing_world_id()
	test_8_repeated_conversion_same_world_id()
	test_9_reopen_summary_and_reload_save()
	test_10_interrupted_transaction_and_recovery()
	test_11_legacy_profile_migration_old_files()
	test_12_existing_victory_achievement_intact()
	test_13_conversion_failure_does_not_deduct_gold()
	test_14_ui_world_summary_display()
	test_15_cross_file_crash_recovery(world_instance)

	_cleanup_test_files()

	print("\n--------------------------------------------------------")
	print("  PACKAGE 2C RESULTS: %d/%d TESTS PASSED" % [passed_tests, total_tests])
	print("--------------------------------------------------------\n")

	if passed_tests == total_tests:
		print("  ALL 15 PACKAGE 2C REQUIREMENTS VERIFIED! (Exit Code 0)\n")
		quit(0)
	else:
		printerr("  SOME TESTS FAILED! (Exit Code 1)\n")
		quit(1)

# -----------------------------------------------------------------------------
# Test 1: 5,000 Gold at 85% Stability -> 40 Legacy, 4,000 Gold deducted
# -----------------------------------------------------------------------------
func test_1_5000_gold_85_stability() -> void:
	print("--- Test 1: 5,000 Gold at 85% Stability ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)
	var res := mgr.convert_surplus_treasury(5000, 85.0, "world_test_tc1_unique_1")

	_assert(res.get("converted") == true, "TC-1.1", "Conversion succeeded")
	_assert(res.get("legacy_awarded") == 40, "TC-1.2", "Awarded exactly 40 Legacy")
	_assert(res.get("gold_deducted") == 4000, "TC-1.3", "Deducted exactly 4,000 Gold")
	_assert(res.get("remaining_gold") == 1000, "TC-1.4", "Remaining Gold is 1,000")
	_assert(mgr.legacy_balance == 40, "TC-1.5", "Profile balance is 40")
	_assert(mgr.has_treasury_conversion("world_test_tc1_unique_1"), "TC-1.6", "Transaction record exists")

# -----------------------------------------------------------------------------
# Test 2: 5,050 Gold at 85% Stability -> 40 Legacy, 4,000 deducted, 1,050 remains
# -----------------------------------------------------------------------------
func test_2_5050_gold_85_stability() -> void:
	print("--- Test 2: 5,050 Gold at 85% Stability ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)
	var res := mgr.convert_surplus_treasury(5050, 85.0, "world_test_tc2_unique_1")

	_assert(res.get("converted") == true, "TC-2.1", "Conversion succeeded")
	_assert(res.get("legacy_awarded") == 40, "TC-2.2", "Awarded exactly 40 Legacy")
	_assert(res.get("gold_deducted") == 4000, "TC-2.3", "Deducted exactly 4,000 Gold")
	_assert(res.get("remaining_gold") == 1050, "TC-2.4", "Remaining Gold is 1,050 (preserved remainder)")

# -----------------------------------------------------------------------------
# Test 3: 1,100 Gold -> 1 Legacy, 100 deducted, 1,000 remains
# -----------------------------------------------------------------------------
func test_3_1100_gold_85_stability() -> void:
	print("--- Test 3: 1,100 Gold at 85% Stability ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)
	var res := mgr.convert_surplus_treasury(1100, 85.0, "world_test_tc3_unique_1")

	_assert(res.get("converted") == true, "TC-3.1", "Conversion succeeded")
	_assert(res.get("legacy_awarded") == 1, "TC-3.2", "Awarded exactly 1 Legacy")
	_assert(res.get("gold_deducted") == 100, "TC-3.3", "Deducted exactly 100 Gold")
	_assert(res.get("remaining_gold") == 1000, "TC-3.4", "Remaining Gold is 1,000")

# -----------------------------------------------------------------------------
# Test 4: Treasury at or below 1,000 Gold -> zero conversion
# -----------------------------------------------------------------------------
func test_4_treasury_at_or_below_1000() -> void:
	print("--- Test 4: Treasury at or below 1,000 Gold ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)

	# Case A: Exactly 1,000 Gold
	var res_1000 := mgr.convert_surplus_treasury(1000, 85.0, "world_test_tc4_a")
	_assert(res_1000.get("converted") == false, "TC-4.1", "1,000 Gold not converted")
	_assert(res_1000.get("legacy_awarded") == 0, "TC-4.2", "1,000 Gold awarded 0 Legacy")
	_assert(res_1000.get("gold_deducted") == 0, "TC-4.3", "1,000 Gold deducted 0")
	_assert(res_1000.get("remaining_gold") == 1000, "TC-4.4", "1,000 Gold remains 1,000")

	# Case B: 900 Gold (below reserve)
	var res_900 := mgr.convert_surplus_treasury(900, 85.0, "world_test_tc4_b")
	_assert(res_900.get("converted") == false, "TC-4.5", "900 Gold not converted")
	_assert(res_900.get("legacy_awarded") == 0, "TC-4.6", "900 Gold awarded 0 Legacy")
	_assert(res_900.get("gold_deducted") == 0, "TC-4.7", "900 Gold deducted 0")
	_assert(res_900.get("remaining_gold") == 900, "TC-4.8", "900 Gold remains 900")

# -----------------------------------------------------------------------------
# Test 5: Stability below 80% -> zero conversion and no deduction
# -----------------------------------------------------------------------------
func test_5_stability_below_80_percent() -> void:
	print("--- Test 5: Stability below 80% ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)

	# Case A: 79.99% Stability with 5,000 Gold
	var res_79 := mgr.convert_surplus_treasury(5000, 79.99, "world_test_tc5_a")
	_assert(res_79.get("converted") == false, "TC-5.1", "79.99% Stability rejected conversion")
	_assert(res_79.get("legacy_awarded") == 0, "TC-5.2", "Awarded 0 Legacy")
	_assert(res_79.get("gold_deducted") == 0, "TC-5.3", "Deducted 0 Gold")
	_assert(res_79.get("remaining_gold") == 5000, "TC-5.4", "Remaining Gold is 5,000")
	_assert(res_79.get("reason") == "stability_too_low", "TC-5.5", "Reason is stability_too_low")

	# Case B: 50.0% Stability
	var res_50 := mgr.convert_surplus_treasury(5000, 50.0, "world_test_tc5_b")
	_assert(res_50.get("converted") == false, "TC-5.6", "50% Stability rejected conversion")
	_assert(res_50.get("legacy_awarded") == 0, "TC-5.7", "Awarded 0 Legacy")
	_assert(res_50.get("gold_deducted") == 0, "TC-5.8", "Deducted 0 Gold")

# -----------------------------------------------------------------------------
# Test 6: Collapsed or defeated kingdom -> zero conversion
# -----------------------------------------------------------------------------
func test_6_collapsed_defeated_kingdom() -> void:
	print("--- Test 6: Collapsed or defeated kingdom ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)

	# Calling convert_surplus_treasury with is_prosperity_victory = false
	var res := mgr.convert_surplus_treasury(5000, 85.0, "world_test_tc6_unique", false)
	_assert(res.get("converted") == false, "TC-6.1", "Defeated kingdom rejected conversion")
	_assert(res.get("legacy_awarded") == 0, "TC-6.2", "Awarded 0 Legacy")
	_assert(res.get("gold_deducted") == 0, "TC-6.3", "Deducted 0 Gold")
	_assert(res.get("reason") == "not_prosperity_victory", "TC-6.4", "Reason is not_prosperity_victory")

	# VictoryManager settlement with collapse triggered
	var vm := VictoryManager.new()
	vm.world_id = "world_test_tc6_vm"
	vm.is_world_id_persisted = true
	vm.is_victory_achieved = false
	vm.is_collapse_triggered = true
	vm.profile_mgr = mgr
	var vm_res := vm.finalize_victory_settlement()
	_assert(vm_res.get("success") == false, "TC-6.5", "VictoryManager rejected collapse settlement")
	_assert(vm_res.get("total_legacy_awarded") == 0, "TC-6.6", "Zero legacy awarded on collapse")

# -----------------------------------------------------------------------------
# Test 7: Invalid or missing World ID -> fail closed
# -----------------------------------------------------------------------------
func test_7_invalid_or_missing_world_id() -> void:
	print("--- Test 7: Invalid or missing World ID ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)

	# Empty ID
	var res_empty := mgr.convert_surplus_treasury(5000, 85.0, "")
	_assert(res_empty.get("converted") == false, "TC-7.1", "Empty World ID rejected")
	_assert(res_empty.get("reason") == "empty_world_id", "TC-7.2", "Reason is empty_world_id")

	# Whitespace ID
	var res_space := mgr.convert_surplus_treasury(5000, 85.0, "   ")
	_assert(res_space.get("converted") == false, "TC-7.3", "Whitespace World ID rejected")

	# Invalid legacy format ("world_<number>")
	var res_legacy := mgr.convert_surplus_treasury(5000, 85.0, "world_12345")
	_assert(res_legacy.get("converted") == false, "TC-7.4", "Unseeded legacy World ID format rejected")
	_assert(res_legacy.get("reason") == "invalid_world_id", "TC-7.5", "Reason is invalid_world_id")

# -----------------------------------------------------------------------------
# Test 8: Repeated conversion with the same World ID -> no duplicate award
# -----------------------------------------------------------------------------
func test_8_repeated_conversion_same_world_id() -> void:
	print("--- Test 8: Repeated conversion with same World ID ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)
	var wid := "world_test_tc8_unique_123"

	# First conversion
	var res1 := mgr.convert_surplus_treasury(5000, 85.0, wid)
	_assert(res1.get("converted") == true, "TC-8.1", "First conversion succeeded")
	_assert(res1.get("legacy_awarded") == 40, "TC-8.2", "Awarded 40 Legacy")
	_assert(mgr.legacy_balance == 40, "TC-8.3", "Balance is 40")

	# Second conversion attempt
	var res2 := mgr.convert_surplus_treasury(5000, 85.0, wid)
	_assert(res2.get("converted") == false, "TC-8.4", "Duplicate conversion rejected")
	_assert(res2.get("reason") == "already_converted", "TC-8.5", "Reason is already_converted")
	_assert(res2.get("legacy_awarded") == 0, "TC-8.6", "Awarded 0 duplicate Legacy")
	_assert(res2.get("gold_deducted") == 0, "TC-8.7", "Deducted 0 duplicate Gold")
	_assert(mgr.legacy_balance == 40, "TC-8.8", "Profile balance remains exactly 40")

# -----------------------------------------------------------------------------
# Test 9: Reopening summary and reloading a previously settled world
# -----------------------------------------------------------------------------
func test_9_reopen_summary_and_reload_save() -> void:
	print("--- Test 9: Reopening summary and reloading a previously settled world ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)
	LegacyProfileManager.set_instance(mgr)

	var vm := VictoryManager.new()
	var wid := "world_test_tc9_persisted_save"
	vm.world_id = wid
	vm.is_world_id_persisted = true
	vm.is_victory_achieved = true
	vm.legacy_points_earned = 100
	vm.profile_mgr = mgr

	# Mock economy resource manager node
	var rm = load("res://scripts/economy/resource_manager.gd").new()
	rm.reset_economy()
	# Set gold to 5,000
	var cur_gold = rm.get_available_stock("gold")
	rm.add_resource("gold", 5000 - cur_gold)
	_assert(rm.get_available_stock("gold") == 5000, "TC-9.1", "Initial stock is 5,000 Gold")

	# Execute final settlement
	var s_res := vm.finalize_victory_settlement(rm, 85.0)
	_assert(s_res.get("success") == true, "TC-9.2", "Settlement completed successfully")
	_assert(s_res.get("victory_points_awarded") == 100, "TC-9.3", "Victory awarded 100 LP")
	_assert(s_res.get("treasury_points_awarded") == 40, "TC-9.4", "Treasury awarded 40 LP")
	_assert(s_res.get("total_legacy_awarded") == 140, "TC-9.5", "Total awarded is 140 LP")
	_assert(rm.get_available_stock("gold") == 1000, "TC-9.6", "Treasury Gold deducted to 1,000")
	_assert(mgr.legacy_balance == 140, "TC-9.7", "Profile balance is 140")

	# Re-open / call settlement a second time on the same instance
	var s_res2 := vm.finalize_victory_settlement(rm, 85.0)
	_assert(s_res2.get("total_legacy_awarded") == 0, "TC-9.8", "Re-settlement awarded 0 duplicate Legacy")
	_assert(s_res2.get("gold_deducted") == 0, "TC-9.9", "Re-settlement deducted 0 Gold")
	_assert(rm.get_available_stock("gold") == 1000, "TC-9.10", "Gold remains 1,000")
	_assert(mgr.legacy_balance == 140, "TC-9.11", "Balance remains 140")

	# Simulate reloading the world: a new VictoryManager instance loading this world_id
	var reloaded_vm := VictoryManager.new()
	reloaded_vm.world_id = wid
	reloaded_vm.is_world_id_persisted = true
	reloaded_vm.is_victory_achieved = true
	reloaded_vm.profile_mgr = mgr
	_assert(reloaded_vm.is_treasury_converted_or_settled() == true, "TC-9.12", "Reloaded instance recognizes prior conversion")

	var reload_settle := reloaded_vm.finalize_victory_settlement(rm, 85.0)
	_assert(reload_settle.get("total_legacy_awarded") == 0, "TC-9.13", "Reloaded settle awarded 0 duplicate Legacy")
	_assert(mgr.legacy_balance == 140, "TC-9.14", "Profile balance remains 140 after reload attempt")

	rm.free()

# -----------------------------------------------------------------------------
# Test 10: Interrupted transaction and recovery behavior
# -----------------------------------------------------------------------------
func test_10_interrupted_transaction_and_recovery() -> void:
	print("--- Test 10: Interrupted transaction and recovery behavior ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)

	# 1. Normal successful conversion
	var res1 := mgr.convert_surplus_treasury(5000, 85.0, "world_test_tc10_valid")
	_assert(res1.get("converted") == true, "TC-10.1", "Initial conversion committed")
	_assert(mgr.legacy_balance == 40, "TC-10.2", "Balance is 40")

	# 2. Simulate disk write failure during second conversion attempt
	LegacyProfileManager._test_inject_fail_write = true
	var res_fail := mgr.convert_surplus_treasury(3000, 85.0, "world_test_tc10_interrupted")
	LegacyProfileManager.reset_test_injection()

	_assert(res_fail.get("converted") == false, "TC-10.3", "Interrupted write returned failure")
	_assert(res_fail.get("reason") == "save_failed", "TC-10.4", "Reason is save_failed")
	_assert(mgr.legacy_balance == 40, "TC-10.5", "In-memory state rolled back cleanly to 40")
	_assert(not mgr.has_treasury_conversion("world_test_tc10_interrupted"), "TC-10.6", "Interrupted record rolled back")

	# 3. Reload profile from disk to confirm disk consistency
	var reloaded_mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)
	_assert(reloaded_mgr.legacy_balance == 40, "TC-10.7", "Disk profile preserved previous valid balance 40")
	_assert(reloaded_mgr.has_treasury_conversion("world_test_tc10_valid"), "TC-10.8", "Prior valid transaction intact")
	_assert(not reloaded_mgr.has_treasury_conversion("world_test_tc10_interrupted"), "TC-10.9", "Failed transaction not in disk profile")

# -----------------------------------------------------------------------------
# Test 11: Legacy profile migration from old files without conversion fields
# -----------------------------------------------------------------------------
func test_11_legacy_profile_migration_old_files() -> void:
	print("--- Test 11: Legacy profile migration from old files ---")
	_cleanup_test_files()

	# Create an old profile schema file lacking "treasury_conversions"
	var old_profile_data: Dictionary = {
		"schema_version": 1,
		"profile_id": "legacy_profile_default",
		"legacy_balance": 100,
		"lifetime_legacy_earned": 100,
		"lifetime_legacy_spent": 0,
		"claimed_rewards": {
			"victory_world_old_save": {
				"reward_id": "victory_world_old_save",
				"source": "victory",
				"amount": 100,
				"world_id": "world_old_save",
				"claimed_at_unix": 1700000000
			}
		},
		"unlocked_achievements": {}
	}

	var file := FileAccess.open(TEST_PROFILE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(old_profile_data, "  "))
	file.close()

	# Load old profile
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)
	_assert(mgr.is_available() == true, "TC-11.1", "Old profile loaded successfully")
	_assert(mgr.legacy_balance == 100, "TC-11.2", "Preserved 100 balance")
	_assert(mgr.has_treasury_conversion("world_old_save") == false, "TC-11.3", "treasury_conversions initialized to empty")

	# Perform conversion on migrated profile
	var conv_res := mgr.convert_surplus_treasury(5000, 85.0, "world_migrated_new_tc11")
	_assert(conv_res.get("converted") == true, "TC-11.4", "Conversion succeeds on migrated profile")
	_assert(mgr.legacy_balance == 140, "TC-11.5", "Balance updated to 140 (100 + 40)")

# -----------------------------------------------------------------------------
# Test 12: Existing victory achievement exactly-once behavior remains intact
# -----------------------------------------------------------------------------
func test_12_existing_victory_achievement_intact() -> void:
	print("--- Test 12: Existing victory achievement exactly-once behavior ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)

	# Unlock achievement
	var ach_res := mgr.unlock_achievement("prosperity_victory", "world_test_tc12")
	_assert(ach_res.get("success") == true, "TC-12.1", "Achievement unlocked successfully")
	_assert(mgr.is_achievement_unlocked("prosperity_victory") == true, "TC-12.2", "is_achievement_unlocked returns true")

	# Claim victory reward
	var rew_res := mgr.claim_reward("victory_world_test_tc12", "victory", 100, "world_test_tc12")
	_assert(rew_res.get("success") == true, "TC-12.3", "Victory reward claimed")
	_assert(mgr.legacy_balance == 100, "TC-12.4", "Balance is 100")

	# Duplicate victory claim rejected
	var dup_rew := mgr.claim_reward("victory_world_test_tc12", "victory", 100, "world_test_tc12")
	_assert(dup_rew.get("success") == false, "TC-12.5", "Duplicate victory claim rejected")
	_assert(dup_rew.get("reason") == "already_claimed", "TC-12.6", "Reason is already_claimed")
	_assert(mgr.legacy_balance == 100, "TC-12.7", "Balance unchanged at 100")

# -----------------------------------------------------------------------------
# Test 13: Conversion failure must not silently deduct Gold without crediting Legacy
# -----------------------------------------------------------------------------
func test_13_conversion_failure_does_not_deduct_gold() -> void:
	print("--- Test 13: Conversion failure does not deduct Gold ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)

	var rm = load("res://scripts/economy/resource_manager.gd").new()
	rm.reset_economy()
	rm.add_resource("gold", 5000 - rm.get_available_stock("gold"))
	_assert(rm.get_available_stock("gold") == 5000, "TC-13.1", "Initial stock is 5,000 Gold")

	var vm := VictoryManager.new()
	vm.world_id = "world_test_tc13_fail"
	vm.is_world_id_persisted = true
	vm.is_victory_achieved = true
	vm.legacy_points_earned = 100
	vm.profile_mgr = mgr

	# Inject profile failure
	LegacyProfileManager._test_inject_fail_write = true
	var settle_fail := vm.finalize_victory_settlement(rm, 85.0)
	LegacyProfileManager.reset_test_injection()

	_assert(settle_fail.get("treasury_converted") == false, "TC-13.2", "Treasury conversion failed")
	_assert(rm.get_available_stock("gold") == 5000, "TC-13.3", "Gold NOT deducted on failure (remains 5,000)")
	_assert(mgr.legacy_balance == 0, "TC-13.4", "Profile balance remains 0")

	rm.free()

# -----------------------------------------------------------------------------
# Test 14: UI accurately displays successful, zero-surplus, and ineligible outcomes
# -----------------------------------------------------------------------------
func test_14_ui_world_summary_display() -> void:
	print("--- Test 14: UI World Summary Display ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)
	LegacyProfileManager.set_instance(mgr)

	var hud = HudScene.instantiate()
	root.add_child(hud)

	# Case A: Successful Preview (5,000 Gold, 85% Stability)
	var report_a := {
		"days_survived": 10,
		"peak_population": 35,
		"food_reserve": 800,
		"treasury": 5000,
		"stability": 85.0,
		"technologies_unlocked": 4,
		"legacy_points": 100,
		"world_id": "world_test_ui_a",
		"legacy_claimed": false,
		"is_treasury_converted": false,
		"treasury_conversion": VictoryManager.calculate_treasury_conversion(5000, 85.0)
	}
	hud.show_victory_panel(report_a)
	var tc_label: Label = hud.get_node_or_null("VictoryPanel/MarginContainer/VBoxContainer/TreasuryConversionLabel")
	var claim_btn: Button = hud.get_node_or_null("VictoryPanel/MarginContainer/VBoxContainer/HBoxContainer/ClaimVictoryBtn")

	_assert(tc_label != null, "TC-14.1", "TreasuryConversionLabel exists in VictoryPanel")
	_assert(tc_label.text.contains("5000 Vàng"), "TC-14.2", "Displays 5,000 Vàng before conversion")
	_assert(tc_label.text.contains("4000 Vàng"), "TC-14.3", "Displays 4,000 Vàng converted")
	_assert(tc_label.text.contains("+40 điểm"), "TC-14.4", "Displays +40 điểm Legacy")
	_assert(tc_label.text.contains("100 Vàng = 1 Legacy"), "TC-14.5", "Displays 100:1 conversion rate")
	_assert(claim_btn.text.contains("+140"), "TC-14.6", "Button displays total +140 Legacy (100 + 40)")

	# Case B: Zero-Surplus Preview (900 Gold)
	var report_b := {
		"days_survived": 10,
		"peak_population": 35,
		"food_reserve": 800,
		"treasury": 900,
		"stability": 85.0,
		"technologies_unlocked": 4,
		"legacy_points": 100,
		"world_id": "world_test_ui_b",
		"legacy_claimed": false,
		"is_treasury_converted": false,
		"treasury_conversion": VictoryManager.calculate_treasury_conversion(900, 85.0)
	}
	hud.show_victory_panel(report_b)
	_assert(tc_label.text.contains("Không có thặng dư") or tc_label.text.contains("1.000 Vàng"), "TC-14.7", "Displays zero surplus explanation")
	_assert(claim_btn.text.contains("+100"), "TC-14.8", "Button displays only base +100 Legacy")

	# Case C: Ineligible Preview (75% Stability)
	var report_c := {
		"days_survived": 10,
		"peak_population": 35,
		"food_reserve": 800,
		"treasury": 5000,
		"stability": 75.0,
		"technologies_unlocked": 4,
		"legacy_points": 100,
		"world_id": "world_test_ui_c",
		"legacy_claimed": false,
		"is_treasury_converted": false,
		"treasury_conversion": VictoryManager.calculate_treasury_conversion(5000, 75.0)
	}
	hud.show_victory_panel(report_c)
	_assert(tc_label.text.contains("Không đủ điều kiện") or tc_label.text.contains("80.0%"), "TC-14.9", "Displays stability ineligible explanation")

	root.remove_child(hud)
	hud.free()

# -----------------------------------------------------------------------------
# Test 15: Cross-File Crash Recovery & Interruption Window
# -----------------------------------------------------------------------------
func test_15_cross_file_crash_recovery(world_inst: Node) -> void:
	print("--- Test 15: Cross-File Crash Recovery & Interruption Window ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)
	LegacyProfileManager.set_instance(mgr)

	var wid := "world_crash_rec_wid_1234"

	# 1. Generate an initial valid world save to disk via SaveManager
	var save_initial: Dictionary = SaveManager.save_to_file(world_inst, TEST_SAVE_PATH)
	_assert(save_initial.get("success", false) == true, "TC-15.1", "Initial save file written cleanly")

	# 2. Modify save data on disk to reflect pre-settlement state with 5,000 Gold and victory achieved
	var read_raw: Dictionary = SaveManager.load_from_file(TEST_SAVE_PATH)
	_assert(read_raw.get("success", false) == true, "TC-15.2", "Save file read for crash fixture setup")
	var save_data: Dictionary = read_raw.get("data", {})

	save_data["metadata"]["world_id"] = wid
	save_data["resources"]["stock"]["gold"] = 5000
	save_data["victory"]["is_victory_achieved"] = true
	save_data["victory"]["is_treasury_converted"] = false
	save_data["victory"]["treasury_conversion_record"] = {}
	save_data["victory"]["is_legacy_claimed"] = false

	var write_fixture: bool = SaveManager.save_dict_to_file(save_data, TEST_SAVE_PATH)
	_assert(write_fixture == true, "TC-15.3", "Crash fixture persisted to disk (5,000 Gold, is_treasury_converted=false)")

	# 3. Simulate Complete Settlement Profile Commit BEFORE Crash
	# Legacy profile commits base victory (+100 LP) and surplus conversion (+40 LP, 4000 Gold deducted)
	var rew_res: Dictionary = mgr.claim_reward("victory_" + wid, "victory", 100, wid)
	_assert(rew_res.get("success", false) == true, "TC-15.3b", "Profile committed base victory reward (+100 LP)")
	var conv_res: Dictionary = mgr.convert_surplus_treasury(5000, 85.0, wid, true)
	_assert(conv_res.get("converted") == true, "TC-15.4", "Profile committed surplus conversion (+40 LP, 4000 Gold deducted)")
	_assert(mgr.legacy_balance == 140, "TC-15.5", "Profile balance is 140 (100 base + 40 surplus)")
	_assert(mgr.has_treasury_conversion(wid) == true, "TC-15.6", "Transaction ledger has recorded conversion for world")

	# EXACT CRASH POINT SIMULATED:
	# Profile on disk has committed full transaction (140 Legacy).
	# World save on disk is OLD and has NOT recorded the deduction or settlement!

	# 4. Player reboots game and reloads the un-updated world save
	var crash_load: Dictionary = SaveManager.load_from_file(TEST_SAVE_PATH)
	_assert(crash_load.get("success", false) == true, "TC-15.7", "Loaded un-updated save from disk")

	SaveManager.apply_loaded_state_to_world(world_inst, crash_load.get("data", {}))

	# 5. Assertions on Post-Crash Recovery Invariants:
	var rm = world_inst.get_node_or_null("/root/ResourceManager")
	var vm = world_inst.get("victory_mgr")

	# Gold MUST be deducted according to profile ledger (5,000 - 4,000 = 1,000)
	_assert(rm.get_available_stock("gold") == 1000, "TC-15.8", "Recovery deducted 4,000 Gold from transaction ledger (now 1,000)")
	# Settlement MUST be marked completed
	_assert(vm.is_treasury_converted == true, "TC-15.9", "Settlement marked completed on restored victory manager")
	_assert(vm.get_active_treasury_conversion_record().get("status") == "completed", "TC-15.10", "Conversion record populated with status completed")
	_assert(mgr.legacy_balance == 140, "TC-15.11", "Zero duplicate Legacy points awarded during recovery (remains 140)")

	# 6. Verify Settlement Cannot Be Repeated in Recovered State
	var re_settle: Dictionary = vm.finalize_victory_settlement(rm, 85.0)
	_assert(re_settle.get("total_legacy_awarded") == 0, "TC-15.12", "Re-settlement after recovery awards 0 duplicate Legacy")
	_assert(re_settle.get("gold_deducted") == 0, "TC-15.13", "Re-settlement after recovery deducts 0 duplicate Gold")
	_assert(rm.get_available_stock("gold") == 1000, "TC-15.14", "Gold remains strictly 1,000")
	_assert(mgr.legacy_balance == 140, "TC-15.15", "Profile balance remains strictly 140")

	# 7. Verify UI Victory Panel Reflects Reconciled State
	var hud = HudScene.instantiate()
	root.add_child(hud)
	hud.world_view_ref = world_inst
	hud.show_victory_panel(vm.generate_summary_report("VICTORY", 24, 800, rm.get_available_stock("gold"), 85.0, 75.0, 4, 8))
	var claim_btn: Button = hud.get_node_or_null("VictoryPanel/MarginContainer/VBoxContainer/HBoxContainer/ClaimVictoryBtn")
	var tc_label: Label = hud.get_node_or_null("VictoryPanel/MarginContainer/VBoxContainer/TreasuryConversionLabel")
	_assert(claim_btn != null and claim_btn.disabled == true, "TC-15.16", "HUD claim button is disabled")
	_assert(claim_btn != null and claim_btn.text == "Đã Nhận Di Sản", "TC-15.17", "HUD claim button displays 'Đã Nhận Di Sản'")
	_assert(tc_label != null and tc_label.text.contains("Đã quyết toán thành công"), "TC-15.18", "HUD label confirms transaction was completed")
	root.remove_child(hud)
	hud.free()

	# 8. Save the Recovered World State Safely
	var save_recovered: Dictionary = SaveManager.save_to_file(world_inst, TEST_SAVE_PATH)
	_assert(save_recovered.get("success", false) == true, "TC-15.19", "Recovered world state saved safely to disk")

	# 9. Reload the Newly-Saved State -> Anti-Double-Deduction Check!
	var reload_new: Dictionary = SaveManager.load_from_file(TEST_SAVE_PATH)
	SaveManager.apply_loaded_state_to_world(world_inst, reload_new.get("data", {}))
	_assert(rm.get_available_stock("gold") == 1000, "TC-15.20", "Reloading reconciled save does NOT deduct Gold twice (remains 1,000)")
	_assert(vm.is_treasury_converted == true, "TC-15.21", "is_treasury_converted remains true on normal load")

	# 10. Scenario 2: World Save Disk Write Failure Simulation After Profile Commit
	var wid_fail := "world_crash_write_fail_wid_9999"
	rm.reset_economy()
	rm.add_resource("gold", 5000)
	var conv_res2: Dictionary = mgr.convert_surplus_treasury(5000, 85.0, wid_fail, true)
	_assert(conv_res2.get("converted") == true, "TC-15.22", "Second world conversion committed to profile (+40 LP, total 180)")
	_assert(mgr.legacy_balance == 180, "TC-15.23", "Profile balance updated to 180 (140 + 40)")

	# Simulate disk write failure on world save
	var fake_bad_path := "invalid_drive://impossible_dir/save.json"
	var fail_write: bool = SaveManager.save_dict_to_file({}, fake_bad_path)
	_assert(fail_write == false, "TC-15.24", "World save write failure rejected cleanly")

	# Verify profile on disk is unaffected
	var disk_mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)
	_assert(disk_mgr.legacy_balance == 180, "TC-15.25", "Disk profile preserved balance 180 despite world save failure")
	_assert(disk_mgr.has_treasury_conversion(wid_fail), "TC-15.26", "Disk profile preserved completed transaction record")
