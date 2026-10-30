extends SceneTree
## Headless Test Suite for Package 1Z: Legacy Fund & Meta-Progression Foundation.
## Validates profile persistence, fail-closed validation, exactly-once claims, multi-world victory,
## older save exploit prevention, achievement unlock, deferred treasury conversion, and UI reflection,
## plus all post-implementation critical hardening fixes (FIX-1Z-A through FIX-1Z-D).

const LegacyProfileManager = preload("res://scripts/legacy/legacy_profile_manager.gd")
const VictoryManager = preload("res://scripts/core/victory_manager.gd")
const SaveManager = preload("res://scripts/persistence/save_manager.gd")

const TEST_PROFILE_PATH: String = "user://test_legacy_profile.json"
const TEST_PROFILE_BAK: String = "user://test_legacy_profile.json.bak"
const TEST_PROFILE_TMP: String = "user://test_legacy_profile.json.tmp"

func _cleanup_test_files() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		if FileAccess.file_exists(TEST_PROFILE_PATH):
			dir.remove(TEST_PROFILE_PATH)
		if FileAccess.file_exists(TEST_PROFILE_BAK):
			dir.remove(TEST_PROFILE_BAK)
		if FileAccess.file_exists(TEST_PROFILE_TMP):
			dir.remove(TEST_PROFILE_TMP)

func _init() -> void:
	print("\n========================================================")
	print("  TEST SUITE: Package 1Z — Legacy Fund & Meta-Progression")
	print("========================================================\n")

	_cleanup_test_files()

	var pass_tc1: bool = _test_profile_initialization()
	var pass_tc2: bool = _test_schema_validation_valid()
	var pass_tc3: bool = _test_schema_validation_negative_numbers()
	var pass_tc4: bool = _test_schema_validation_math_invariant()
	var pass_tc5: bool = _test_schema_validation_claimed_sum_mismatch()
	var pass_tc6: bool = _test_schema_validation_invalid_source()
	var pass_tc7: bool = _test_schema_validation_invalid_reward_amount()
	var pass_tc8: bool = _test_atomic_persistence_and_backup_recovery()
	var pass_tc9: bool = _test_exactly_once_reward_claim()
	var pass_tc10: bool = _test_double_claim_exploit_prevention()
	var pass_tc11: bool = _test_multi_world_victory_claim()
	var pass_tc12: bool = _test_older_save_reload_exploit_prevention()
	var pass_tc13: bool = _test_achievement_foundation()
	var pass_tc14: bool = _test_deferred_surplus_treasury_conversion()
	var pass_tc15: bool = _test_ui_and_victory_claim_reflection()

	# Expanded post-audit hardening coverage
	var pass_exp1: bool = _test_double_reward_elimination()
	var pass_exp2: bool = _test_achievement_persistence_failure_rollback()
	var pass_exp3: bool = _test_profile_initialization_failure_unavailable()
	var pass_exp4: bool = _test_claims_rejected_while_unavailable()
	var pass_exp5: bool = _test_identical_seeds_have_distinct_world_ids()
	var pass_exp6: bool = _test_world_id_persistence_save_load()
	var pass_exp7: bool = _test_failed_migration_prevents_unsafe_claims()
	var pass_exp8: bool = _test_atomic_write_failure_and_rollback()
	var pass_exp9: bool = _test_float_nan_invalid_amount_rejection()
	var pass_exp10: bool = _test_failed_operations_leave_state_unchanged()

	# Second hardening audit coverage (FIX-1Z-E through FIX-1Z-J)
	var pass_exp11: bool = _test_canonical_reward_id_enforcement_and_custom_id_bypass_rejection()
	var pass_exp12: bool = _test_safe_backup_recovery_and_corrupt_primary_protection()
	var pass_exp13: bool = _test_save_manager_atomic_backup_hardening()
	var pass_exp14: bool = _test_hud_reward_status_classification()
	var pass_exp15: bool = _test_integer_overflow_rejection()

	# Third hardening audit coverage (FIX-1Z-K through FIX-1Z-N)
	var pass_exp16: bool = _test_fix_1z_k_fail_closed_rewards()
	var pass_exp17: bool = _test_fix_1z_l_world_id_persistence_lifecycle()
	var pass_exp18: bool = _test_fix_1z_m_save_manager_backup_rotation_10_cases()
	var pass_exp19: bool = _test_fix_1z_n_float_64bit_boundary_precision()

	_cleanup_test_files()
	LegacyProfileManager.reset_instance()

	print("\n--------------------------------------------------------")
	if (pass_tc1 and pass_tc2 and pass_tc3 and pass_tc4 and pass_tc5 and
		pass_tc6 and pass_tc7 and pass_tc8 and pass_tc9 and pass_tc10 and
		pass_tc11 and pass_tc12 and pass_tc13 and pass_tc14 and pass_tc15 and
		pass_exp1 and pass_exp2 and pass_exp3 and pass_exp4 and pass_exp5 and
		pass_exp6 and pass_exp7 and pass_exp8 and pass_exp9 and pass_exp10 and
		pass_exp11 and pass_exp12 and pass_exp13 and pass_exp14 and pass_exp15 and
		pass_exp16 and pass_exp17 and pass_exp18 and pass_exp19):
		print("  ALL 34 PACKAGE 1Z TESTS PASSED SUCCESSFULLY! (Exit Code 0)")
		print("--------------------------------------------------------\n")
		quit(0)
	else:
		print("  PACKAGE 1Z TESTS FAILED! (Exit Code 1)")
		print("--------------------------------------------------------\n")
		quit(1)

func _test_profile_initialization() -> bool:
	print("--- Scenario 1: Authoritative Profile Initialization ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)
	var load_res := mgr.load_profile()
	if not load_res.get("success", false) or load_res.get("status") != "new_profile":
		print("  [FAIL] Expected new_profile status on empty file, got: %s" % str(load_res))
		return false
	if mgr.legacy_balance != 0 or mgr.lifetime_legacy_earned != 0 or mgr.lifetime_legacy_spent != 0:
		print("  [FAIL] Initial balances non-zero: bal=%d earned=%d spent=%d" % [mgr.legacy_balance, mgr.lifetime_legacy_earned, mgr.lifetime_legacy_spent])
		return false
	if not mgr.claimed_rewards.is_empty():
		print("  [FAIL] Claimed rewards not empty initially.")
		return false
	print("  [PASS] Clean profile initialized with 0 balance and empty records.")
	return true

func _test_schema_validation_valid() -> bool:
	print("--- Scenario 2: Schema Validation (Valid Data) ---")
	var valid_dict = {
		"schema_version": 1,
		"profile_id": "player_profile_test",
		"legacy_balance": 100,
		"lifetime_legacy_earned": 150,
		"lifetime_legacy_spent": 50,
		"claimed_rewards": {
			"reward_1": {
				"reward_id": "reward_1",
				"source": "victory",
				"amount": 100,
				"world_id": "world_1",
				"claimed_at_unix": 1000
			},
			"reward_2": {
				"reward_id": "reward_2",
				"source": "achievement",
				"amount": 50,
				"world_id": "world_1",
				"claimed_at_unix": 1005
			}
		},
		"unlocked_achievements": {}
	}
	var res = LegacyProfileManager.validate_profile_data(valid_dict)
	if not res.get("valid", false):
		print("  [FAIL] Valid dictionary failed validation: %s" % res.get("error", ""))
		return false
	print("  [PASS] Valid profile passed validation.")
	return true

func _test_schema_validation_negative_numbers() -> bool:
	print("--- Scenario 3: Fail-Closed on Negative Balances ---")
	var bad_dict = {
		"schema_version": 1,
		"profile_id": "player_profile_test",
		"legacy_balance": -10,
		"lifetime_legacy_earned": 0,
		"lifetime_legacy_spent": 10,
		"claimed_rewards": {}
	}
	var res = LegacyProfileManager.validate_profile_data(bad_dict)
	if res.get("valid", true):
		print("  [FAIL] Negative balance was improperly accepted!")
		return false
	print("  [PASS] Negative balance rejected: %s" % res.get("error", ""))
	return true

func _test_schema_validation_math_invariant() -> bool:
	print("--- Scenario 4: Fail-Closed on Balance Invariant (balance != earned - spent) ---")
	var bad_dict = {
		"schema_version": 1,
		"profile_id": "player_profile_test",
		"legacy_balance": 500,
		"lifetime_legacy_earned": 100,
		"lifetime_legacy_spent": 0,
		"claimed_rewards": {
			"r1": {"reward_id": "r1", "source": "victory", "amount": 100}
		}
	}
	var res = LegacyProfileManager.validate_profile_data(bad_dict)
	if res.get("valid", true):
		print("  [FAIL] Tampered balance passed validation!")
		return false
	print("  [PASS] Math invariant violation rejected: %s" % res.get("error", ""))
	return true

func _test_schema_validation_claimed_sum_mismatch() -> bool:
	print("--- Scenario 5: Fail-Closed on Claimed Rewards Sum Mismatch ---")
	var bad_dict = {
		"schema_version": 1,
		"profile_id": "player_profile_test",
		"legacy_balance": 200,
		"lifetime_legacy_earned": 200,
		"lifetime_legacy_spent": 0,
		"claimed_rewards": {
			"r1": {"reward_id": "r1", "source": "victory", "amount": 100}
		}
	}
	var res = LegacyProfileManager.validate_profile_data(bad_dict)
	if res.get("valid", true):
		print("  [FAIL] Claimed rewards sum mismatch was improperly accepted!")
		return false
	print("  [PASS] Claimed rewards sum mismatch rejected: %s" % res.get("error", ""))
	return true

func _test_schema_validation_invalid_source() -> bool:
	print("--- Scenario 6: Fail-Closed on Invalid Reward Source ---")
	var bad_dict = {
		"schema_version": 1,
		"profile_id": "player_profile_test",
		"legacy_balance": 100,
		"lifetime_legacy_earned": 100,
		"lifetime_legacy_spent": 0,
		"claimed_rewards": {
			"r1": {"reward_id": "r1", "source": "unauthorized_cheat_injection", "amount": 100}
		}
	}
	var res = LegacyProfileManager.validate_profile_data(bad_dict)
	if res.get("valid", true):
		print("  [FAIL] Unsupported reward source was improperly accepted!")
		return false
	print("  [PASS] Unsupported reward source rejected: %s" % res.get("error", ""))
	return true

func _test_schema_validation_invalid_reward_amount() -> bool:
	print("--- Scenario 7: Fail-Closed on Non-Integer / Negative Reward Amount ---")
	var bad_dict = {
		"schema_version": 1,
		"profile_id": "player_profile_test",
		"legacy_balance": 0,
		"lifetime_legacy_earned": 0,
		"lifetime_legacy_spent": 0,
		"claimed_rewards": {
			"r1": {"reward_id": "r1", "source": "victory", "amount": -50}
		}
	}
	var res = LegacyProfileManager.validate_profile_data(bad_dict)
	if res.get("valid", true):
		print("  [FAIL] Negative reward amount was improperly accepted!")
		return false
	print("  [PASS] Negative reward amount rejected: %s" % res.get("error", ""))
	return true

func _test_atomic_persistence_and_backup_recovery() -> bool:
	print("--- Scenario 8: Atomic Persistence & Backup Recovery ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)
	mgr.claim_reward("first_reward", "victory", 100, "world_test")

	if not FileAccess.file_exists(TEST_PROFILE_PATH):
		print("  [FAIL] Profile file was not created on disk.")
		return false

	# Perform a second save to produce .bak rotation
	mgr.claim_reward("second_reward", "victory", 50, "world_test")
	if not FileAccess.file_exists(TEST_PROFILE_BAK):
		print("  [FAIL] Backup profile (.bak) was not created on rotation.")
		return false

	# Corrupt the primary file
	var corrupt_file := FileAccess.open(TEST_PROFILE_PATH, FileAccess.WRITE)
	corrupt_file.store_string("CORRUPTED_GARBAGE_DATA_{{{")
	corrupt_file.close()

	# Reload into fresh manager instance: should cleanly recover from .bak
	var mgr2 := LegacyProfileManager.new(TEST_PROFILE_PATH)
	var load_res := mgr2.load_profile()
	if not load_res.get("success", false) or load_res.get("status") != "recovered_from_backup":
		print("  [FAIL] Recovery from backup failed: %s" % str(load_res))
		return false
	if mgr2.legacy_balance != 100:
		print("  [FAIL] Recovered balance expected 100, got: %d" % mgr2.legacy_balance)
		return false

	# Corrupt both primary and backup
	var corrupt_bak := FileAccess.open(TEST_PROFILE_BAK, FileAccess.WRITE)
	corrupt_bak.store_string("CORRUPTED_BACKUP_DATA")
	corrupt_bak.close()

	var mgr3 := LegacyProfileManager.new(TEST_PROFILE_PATH)
	mgr3.legacy_balance = 75
	var load_res_both_corrupt := mgr3.load_profile()
	if load_res_both_corrupt.get("success", true):
		print("  [FAIL] Load should fail closed when both main and backup are corrupted!")
		return false
	if mgr3.legacy_balance != 75:
		print("  [FAIL] Fail-closed corrupted load should preserve live state, got: %d" % mgr3.legacy_balance)
		return false

	print("  [PASS] Atomic persistence and .bak recovery verified.")
	return true

func _test_exactly_once_reward_claim() -> bool:
	print("--- Scenario 9: Exactly-Once Reward Claim API ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)
	var res := mgr.claim_reward("vic_world_1", "victory", 100, "world_1", {"details": "win"})
	if not res.get("success", false) or res.get("points_awarded", 0) != 100:
		print("  [FAIL] First claim failed: %s" % str(res))
		return false
	if mgr.legacy_balance != 100 or mgr.lifetime_legacy_earned != 100:
		print("  [FAIL] Balance not updated: bal=%d earned=%d" % [mgr.legacy_balance, mgr.lifetime_legacy_earned])
		return false
	if not mgr.is_reward_claimed("vic_world_1"):
		print("  [FAIL] is_reward_claimed returned false for claimed reward.")
		return false
	print("  [PASS] Exactly-once reward claim succeeded and recorded.")
	return true

func _test_double_claim_exploit_prevention() -> bool:
	print("--- Scenario 10: Double-Claim Exploit Prevention ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)
	mgr.claim_reward("vic_world_1", "victory", 100, "world_1")

	# Attempt duplicate claim with exact same reward_id
	var dup_res := mgr.claim_reward("vic_world_1", "victory", 100, "world_1")
	if dup_res.get("success", true) or dup_res.get("points_awarded", -1) != 0:
		print("  [FAIL] Duplicate claim succeeded or awarded points: %s" % str(dup_res))
		return false
	if dup_res.get("reason", "") != "already_claimed":
		print("  [FAIL] Unexpected reason for duplicate claim: %s" % dup_res.get("reason", ""))
		return false
	if mgr.legacy_balance != 100:
		print("  [FAIL] Balance changed on duplicate claim: %d" % mgr.legacy_balance)
		return false
	print("  [PASS] Duplicate claim correctly rejected with 0 points awarded.")
	return true

func _test_multi_world_victory_claim() -> bool:
	print("--- Scenario 11: Multi-World Victory Claim ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)

	# World 1 victory
	var vic1 := VictoryManager.new()
	vic1.profile_mgr = mgr
	vic1.world_id = "world_alpha_unique_1"
	vic1.is_world_id_persisted = true
	vic1.is_victory_achieved = true
	vic1.legacy_points_earned = 100

	var pts1 := vic1.claim_legacy_reward()
	if pts1 != 100 or mgr.legacy_balance != 100:
		print("  [FAIL] World 1 victory claim failed: pts=%d bal=%d" % [pts1, mgr.legacy_balance])
		return false

	# World 2 victory
	var vic2 := VictoryManager.new()
	vic2.profile_mgr = mgr
	vic2.world_id = "world_beta_unique_2"
	vic2.is_world_id_persisted = true
	vic2.is_victory_achieved = true
	vic2.legacy_points_earned = 100

	var pts2 := vic2.claim_legacy_reward()
	if pts2 != 100 or mgr.legacy_balance != 200:
		print("  [FAIL] World 2 victory claim failed: pts=%d bal=%d" % [pts2, mgr.legacy_balance])
		return false

	# World 1 duplicate attempt from new manager instance
	var vic1_dup := VictoryManager.new()
	vic1_dup.profile_mgr = mgr
	vic1_dup.world_id = "world_alpha_unique_1"
	vic1_dup.is_world_id_persisted = true
	vic1_dup.is_victory_achieved = true
	vic1_dup.legacy_points_earned = 100

	var pts1_dup := vic1_dup.claim_legacy_reward()
	if pts1_dup != 0 or mgr.legacy_balance != 200:
		print("  [FAIL] Duplicate world 1 claim was awarded points: pts=%d bal=%d" % [pts1_dup, mgr.legacy_balance])
		return false

	print("  [PASS] Multi-world victory claims allowed across distinct worlds; duplicate rejected.")
	return true

func _test_older_save_reload_exploit_prevention() -> bool:
	print("--- Scenario 12: Older Save Reload Exploit Prevention ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)

	# World achieved victory and claimed reward in profile
	var vic := VictoryManager.new()
	vic.profile_mgr = mgr
	vic.world_id = "world_gamma_unique_3"
	vic.is_world_id_persisted = true
	vic.is_victory_achieved = true
	vic.legacy_points_earned = 100
	var first_pts := vic.claim_legacy_reward()
	if first_pts != 100:
		print("  [FAIL] Initial claim failed: %d" % first_pts)
		return false

	# Now simulate loading an older save file from world_gamma where is_legacy_claimed was FALSE
	var loaded_vic := VictoryManager.new()
	loaded_vic.profile_mgr = mgr
	loaded_vic.world_id = "world_gamma_unique_3"
	loaded_vic.is_world_id_persisted = true
	loaded_vic.is_victory_achieved = true
	loaded_vic.is_legacy_claimed = false
	loaded_vic.legacy_points_earned = 100

	# Verify VictoryManager recognizes profile already claimed this reward
	if loaded_vic.is_reward_claimable():
		print("  [FAIL] is_reward_claimable returned true despite profile already having recorded victory_world_gamma!")
		return false

	var re_pts := loaded_vic.claim_legacy_reward()
	if re_pts != 0:
		print("  [FAIL] Reloaded older save awarded duplicate legacy points: %d" % re_pts)
		return false
	if mgr.legacy_balance != 100:
		print("  [FAIL] Legacy balance modified by older save reload: %d" % mgr.legacy_balance)
		return false

	var report := loaded_vic.generate_summary_report("VICTORY", 30, 500, 1000, 80.0, 75.0, 3, 5)
	if not report.get("legacy_claimed", false):
		print("  [FAIL] Summary report did not reflect legacy_claimed == true from profile.")
		return false

	print("  [PASS] Older save reload exploit prevented by authoritative profile check.")
	return true

func _test_achievement_foundation() -> bool:
	print("--- Scenario 13: Achievement Foundation & Single-Award Invariant ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)

	# First unlock of prosperity_victory: reward is deferred to victory claim per FIX-1Z-A
	var ach_res := mgr.unlock_achievement("prosperity_victory", "world_omega_unique_4")
	if not ach_res.get("success", false):
		print("  [FAIL] First achievement unlock failed: %s" % str(ach_res))
		return false
	if mgr.legacy_balance != 0:
		print("  [FAIL] Achievement points unexpectedly credited to balance (should be deferred): %d" % mgr.legacy_balance)
		return false
	if not mgr.is_achievement_unlocked("prosperity_victory"):
		print("  [FAIL] is_achievement_unlocked returned false after unlocking.")
		return false

	# Second unlock attempt (e.g. from different world)
	var dup_ach := mgr.unlock_achievement("prosperity_victory", "world_psi_unique_5")
	if dup_ach.get("success", true):
		print("  [FAIL] Second achievement unlock should be rejected, got: %s" % str(dup_ach))
		return false
	if dup_ach.get("reason", "") != "already_unlocked":
		print("  [FAIL] Unexpected reason for duplicate achievement: %s" % dup_ach.get("reason", ""))
		return false
	if mgr.legacy_balance != 0:
		print("  [FAIL] Balance increased on duplicate achievement: %d" % mgr.legacy_balance)
		return false

	# Unknown achievement
	var unk_res := mgr.unlock_achievement("undocumented_fake_achievement")
	if unk_res.get("success", true) or unk_res.get("reason") != "unknown_achievement":
		print("  [FAIL] Unknown achievement was not rejected fail-closed: %s" % str(unk_res))
		return false

	print("  [PASS] Achievement registry correctly handles deferred victory reward and rejects duplicates/unknowns.")
	return true

func _test_deferred_surplus_treasury_conversion() -> bool:
	print("--- Scenario 14: Deferred Surplus Treasury Conversion Extension Point ---")
	var mgr := LegacyProfileManager.new()
	var conv_res := mgr.convert_surplus_treasury(5000, 95.0, "world_test")
	if conv_res.get("status") != "deferred" or conv_res.get("converted") != false:
		print("  [FAIL] Treasury conversion status unexpected: %s" % str(conv_res))
		return false
	if conv_res.get("legacy_awarded", -1) != 0 or conv_res.get("gold_deducted", -1) != 0:
		print("  [FAIL] Treasury conversion awarded or deducted values: %s" % str(conv_res))
		return false
	print("  [PASS] Surplus treasury conversion correctly documented and deferred.")
	return true

func _test_ui_and_victory_claim_reflection() -> bool:
	print("--- Scenario 15: UI & Victory Claim Reflection ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)
	LegacyProfileManager.set_instance(mgr)

	var vic := VictoryManager.new()
	vic.profile_mgr = mgr
	vic.world_id = "world_ui_test_unique_6"
	vic.is_world_id_persisted = true
	vic.is_victory_achieved = true
	vic.legacy_points_earned = 100

	# Before claim: is_reward_claimable is true
	if not vic.is_reward_claimable():
		print("  [FAIL] Victory reward should be claimable before claim.")
		return false

	# Claim victory
	var pts := vic.claim_legacy_reward()
	if pts != 100:
		print("  [FAIL] Claim failed in UI test: %d" % pts)
		return false

	# After claim: is_reward_claimable is false
	if vic.is_reward_claimable():
		print("  [FAIL] Victory reward should NOT be claimable after claim.")
		return false

	# Verify profile balance matches
	if mgr.legacy_balance != 100:
		print("  [FAIL] Legacy balance mismatch: %d" % mgr.legacy_balance)
		return false

	print("  [PASS] VictoryManager and profile state reflect seamlessly for UI presentation.")
	return true

# -----------------------------------------------------------------------------
# Post-Audit Hardening Expanded Tests (FIX-1Z-A through FIX-1Z-D)
# -----------------------------------------------------------------------------

func _test_double_reward_elimination() -> bool:
	print("--- Expanded Test 1: Double Reward Elimination (FIX-1Z-A) ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)
	LegacyProfileManager.set_instance(mgr)

	var vic := VictoryManager.new()
	vic.profile_mgr = mgr
	vic.world_id = "world_double_elim_unique_7"
	vic.is_world_id_persisted = true
	vic.is_victory_achieved = true
	vic.legacy_points_earned = 100

	# Unlock prosperity_victory achievement
	var ach_res := mgr.unlock_achievement("prosperity_victory", vic.world_id)
	if not ach_res.get("success", false):
		print("  [FAIL] Failed to unlock prosperity_victory: %s" % str(ach_res))
		return false
	if mgr.legacy_balance != 0:
		print("  [FAIL] Achievement should not grant direct points: bal=%d" % mgr.legacy_balance)
		return false

	# Claim victory reward
	var pts := vic.claim_legacy_reward()
	if pts != 100:
		print("  [FAIL] Claiming victory did not award 100 points: %d" % pts)
		return false
	if mgr.legacy_balance != 100:
		print("  [FAIL] Total legacy balance after victory claim is not 100: %d" % mgr.legacy_balance)
		return false

	# Verify duplicate claim is blocked
	var re_pts := vic.claim_legacy_reward()
	if re_pts != 0:
		print("  [FAIL] Duplicate claim awarded extra points: %d" % re_pts)
		return false
	if mgr.legacy_balance != 100:
		print("  [FAIL] Legacy balance modified by duplicate claim: %d" % mgr.legacy_balance)
		return false

	print("  [PASS] Complete prosperity victory grants exactly 100 Legacy Fund total (no double reward).")
	return true

func _test_achievement_persistence_failure_rollback() -> bool:
	print("--- Expanded Test 2: Achievement Persistence Failure Rollback (FIX-1Z-B) ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)
	mgr.legacy_balance = 50
	mgr.lifetime_legacy_earned = 50
	# Temporarily set active_filepath to an invalid unwritable path
	mgr.active_filepath = "user://nonexistent_invalid_dir/profile.json"

	# Temporarily add a test achievement definition with positive points
	LegacyProfileManager.ACHIEVEMENTS["test_unlock_rollback"] = {
		"id": "test_unlock_rollback",
		"title": "Test Rollback",
		"description": "Test",
		"reward_legacy": 30,
		"reward_source": "achievement"
	}

	var res := mgr.unlock_achievement("test_unlock_rollback", "world_rollback")
	if res.get("success", true):
		print("  [FAIL] unlock_achievement should fail when save_profile fails!")
		LegacyProfileManager.ACHIEVEMENTS.erase("test_unlock_rollback")
		return false
	if res.get("reason", "") != "save_failed":
		print("  [FAIL] Unexpected reason for save failure: %s" % res.get("reason", ""))
		LegacyProfileManager.ACHIEVEMENTS.erase("test_unlock_rollback")
		return false

	# Verify complete memory rollback
	if mgr.is_achievement_unlocked("test_unlock_rollback"):
		print("  [FAIL] Achievement remained unlocked in memory after save failure!")
		LegacyProfileManager.ACHIEVEMENTS.erase("test_unlock_rollback")
		return false
	if mgr.is_reward_claimed("ach_test_unlock_rollback"):
		print("  [FAIL] Claim record remained in memory after save failure!")
		LegacyProfileManager.ACHIEVEMENTS.erase("test_unlock_rollback")
		return false
	if mgr.legacy_balance != 50 or mgr.lifetime_legacy_earned != 50:
		print("  [FAIL] Legacy balances changed despite rollback: bal=%d earned=%d" % [mgr.legacy_balance, mgr.lifetime_legacy_earned])
		LegacyProfileManager.ACHIEVEMENTS.erase("test_unlock_rollback")
		return false

	LegacyProfileManager.ACHIEVEMENTS.erase("test_unlock_rollback")
	print("  [PASS] In-memory achievement state completely rolled back on save failure.")
	return true

func _test_profile_initialization_failure_unavailable() -> bool:
	print("--- Expanded Test 3: Profile Initialization Failure Unavailable (FIX-1Z-D) ---")
	_cleanup_test_files()
	var f1 := FileAccess.open(TEST_PROFILE_PATH, FileAccess.WRITE)
	f1.store_string("CORRUPTED_JSON_PRIMARY_DATA_!@#$%")
	f1.close()
	var f2 := FileAccess.open(TEST_PROFILE_BAK, FileAccess.WRITE)
	f2.store_string("CORRUPTED_JSON_BACKUP_DATA_!@#$%")
	f2.close()

	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)
	if mgr.is_available():
		print("  [FAIL] Corrupted profile reported as available!")
		return false
	if mgr.get_status() != LegacyProfileManager.STATUS_UNAVAILABLE:
		print("  [FAIL] Expected STATUS_UNAVAILABLE, got: %s" % mgr.get_status())
		return false
	if mgr.get_initialization_error().is_empty():
		print("  [FAIL] Initialization error string is empty!")
		return false

	# Verify corrupted files were NOT deleted or wiped to 0 bytes
	var f1_chk := FileAccess.open(TEST_PROFILE_PATH, FileAccess.READ)
	if f1_chk == null or f1_chk.get_length() == 0:
		print("  [FAIL] Primary corrupt file was deleted or wiped to 0 bytes!")
		return false
	f1_chk.close()

	print("  [PASS] Corrupted profile leaves profile unavailable and preserves corrupted files.")
	return true

func _test_claims_rejected_while_unavailable() -> bool:
	print("--- Expanded Test 4: Claims Rejected While Profile Unavailable (FIX-1Z-D) ---")
	_cleanup_test_files()
	var f1 := FileAccess.open(TEST_PROFILE_PATH, FileAccess.WRITE)
	f1.store_string("{ INVALID JSON }")
	f1.close()
	var f2 := FileAccess.open(TEST_PROFILE_BAK, FileAccess.WRITE)
	f2.store_string("{ INVALID JSON }")
	f2.close()

	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)
	var claim_res := mgr.claim_reward("test_unavail", "victory", 100, "world_test")
	if claim_res.get("success", true) or claim_res.get("reason") != "profile_unavailable":
		print("  [FAIL] claim_reward should fail with profile_unavailable, got: %s" % str(claim_res))
		return false

	var ach_res := mgr.unlock_achievement("prosperity_victory", "world_test")
	if ach_res.get("success", true) or ach_res.get("reason") != "profile_unavailable":
		print("  [FAIL] unlock_achievement should fail with profile_unavailable, got: %s" % str(ach_res))
		return false

	if mgr.legacy_balance != 0:
		print("  [FAIL] Legacy balance modified while unavailable: %d" % mgr.legacy_balance)
		return false

	print("  [PASS] Reward claims and achievement unlocks cleanly rejected while profile is unavailable.")
	return true

func _test_identical_seeds_have_distinct_world_ids() -> bool:
	print("--- Expanded Test 5: Identical Seeds Have Distinct World IDs (FIX-1Z-C) ---")
	var WorldViewScript = load("res://scripts/world/world_view.gd")
	var VictoryManagerScript = load("res://scripts/core/victory_manager.gd")
	var seed_val: int = 77777
	var generated_ids: Dictionary = {}
	for i in range(20):
		var wid: String = WorldViewScript.generate_unique_world_id(seed_val)
		if generated_ids.has(wid):
			print("  [FAIL] Duplicate world ID generated for seed %d: %s" % [seed_val, wid])
			return false
		generated_ids[wid] = true
		if wid == "world_%d" % seed_val:
			print("  [FAIL] World ID used legacy seed-only format: %s" % wid)
			return false
		if not VictoryManagerScript.is_valid_world_id(wid):
			print("  [FAIL] Generated world ID failed is_valid_world_id check: %s" % wid)
			return false

	print("  [PASS] Successive world ID generations for identical seed produced 20 distinct valid IDs.")
	return true

func _test_world_id_persistence_save_load() -> bool:
	print("--- Expanded Test 6: World ID Persistence on Save / Load (FIX-1Z-C) ---")
	var test_save_path := "user://test_world_id_persistence.json"
	var test_legacy_path := "user://test_legacy_migration.json"
	var dir := DirAccess.open("user://")
	if dir:
		for p in [test_save_path, test_save_path + ".bak", test_save_path + ".tmp",
				  test_legacy_path, test_legacy_path + ".bak", test_legacy_path + ".tmp"]:
			if FileAccess.file_exists(p): dir.remove(p)

	var WorldViewScript = load("res://scripts/world/world_view.gd")
	var SaveManagerScript = load("res://scripts/persistence/save_manager.gd")
	var VictoryManagerScript = load("res://scripts/core/victory_manager.gd")
	var unique_wid: String = WorldViewScript.generate_unique_world_id(45678)

	# 1. Test saving and loading a canonical save with unique world_id
	var save_data = {
		"schema_version": 1,
		"metadata": {
			"world_seed": 45678,
			"world_id": unique_wid,
			"difficulty": "normal"
		},
		"resources": {"food": 100, "wood": 100, "stone": 50, "gold": 200, "tools": 10, "is_starving": false},
		"buildings": [],
		"citizens": [],
		"tactical_military": {"units": []},
		"enemy_military": {"units": []},
		"field_siege": {"active_sieges": {}}
	}
	var save_ok: bool = SaveManagerScript.save_dict_to_file(save_data, test_save_path)
	if not save_ok:
		print("  [FAIL] save_dict_to_file failed!")
		return false

	var load_res: Dictionary = SaveManagerScript.load_from_file(test_save_path)
	if not load_res.get("success", false):
		print("  [FAIL] load_from_file failed: %s" % str(load_res))
		return false
	var loaded_meta: Dictionary = load_res.get("data", {}).get("metadata", {})
	if loaded_meta.get("world_id") != unique_wid:
		print("  [FAIL] Loaded metadata world_id mismatch: %s != %s" % [str(loaded_meta.get("world_id")), unique_wid])
		return false

	# 2. Test legacy migration for save without world_id
	var legacy_save_data = {
		"schema_version": 1,
		"metadata": {
			"world_seed": 12345,
			"difficulty": "normal"
			# Missing world_id entirely!
		},
		"resources": {"food": 100, "wood": 100, "stone": 50, "gold": 200, "tools": 10, "is_starving": false},
		"buildings": [],
		"citizens": [],
		"tactical_military": {"units": []},
		"enemy_military": {"units": []},
		"field_siege": {"active_sieges": {}}
	}
	SaveManagerScript.save_dict_to_file(legacy_save_data, test_legacy_path)

	var mig_res: Dictionary = SaveManagerScript.load_from_file(test_legacy_path)
	if not mig_res.get("success", false):
		print("  [FAIL] Legacy save load failed: %s" % str(mig_res))
		return false
	var mig_meta: Dictionary = mig_res.get("data", {}).get("metadata", {})
	var migrated_id: String = str(mig_meta.get("world_id", ""))
	if migrated_id.is_empty():
		print("  [FAIL] Legacy save did not generate a migrated world_id!")
		return false
	if migrated_id == "world_12345":
		print("  [FAIL] Migrated world_id used legacy seed-only format: %s" % migrated_id)
		return false
	if not VictoryManagerScript.is_valid_world_id(migrated_id):
		print("  [FAIL] Migrated world_id failed is_valid_world_id check: %s" % migrated_id)
		return false

	# Verify migrated world_id was persisted to disk immediately
	var disk_res: Dictionary = SaveManagerScript.load_from_file(test_legacy_path)
	var disk_wid = disk_res.get("data", {}).get("metadata", {}).get("world_id")
	if disk_wid != migrated_id:
		print("  [FAIL] Migrated world_id was not persisted to disk: %s != %s" % [str(disk_wid), migrated_id])
		return false

	# 3. Test apply_loaded_state_to_world sets world_id and is_world_id_persisted
	var dummy_wv = Node2D.new()
	dummy_wv.set_script(WorldViewScript)
	var dummy_vic = VictoryManagerScript.new()
	dummy_wv.set("victory_mgr", dummy_vic)
	SaveManagerScript.apply_loaded_state_to_world(dummy_wv, load_res.get("data", {}))
	if dummy_wv.get("world_id") != unique_wid:
		print("  [FAIL] dummy_wv world_id not set: %s" % str(dummy_wv.get("world_id")))
		dummy_wv.free()
		return false
	if not dummy_wv.get("is_world_id_persisted"):
		print("  [FAIL] dummy_wv is_world_id_persisted not set to true!")
		dummy_wv.free()
		return false
	if dummy_vic.world_id != unique_wid or not dummy_vic.is_world_id_persisted:
		print("  [FAIL] dummy_vic metadata not set: wid=%s persisted=%s" % [dummy_vic.world_id, str(dummy_vic.is_world_id_persisted)])
		dummy_wv.free()
		return false
	dummy_wv.free()

	if dir:
		for p in [test_save_path, test_save_path + ".bak", test_save_path + ".tmp",
				  test_legacy_path, test_legacy_path + ".bak", test_legacy_path + ".tmp"]:
			if FileAccess.file_exists(p): dir.remove(p)

	print("  [PASS] World ID correctly persisted and restored across save/load lifecycle.")
	return true

func _test_failed_migration_prevents_unsafe_claims() -> bool:
	print("--- Expanded Test 7: Failed Migration Prevents Unsafe Claims (FIX-1Z-C) ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)
	LegacyProfileManager.set_instance(mgr)

	var vic := VictoryManager.new()
	vic.profile_mgr = mgr
	vic.world_id = "world_migrated_unique_8"
	vic.is_victory_achieved = true
	vic.legacy_points_earned = 100

	# Mark world ID as NOT persisted (migration save failed)
	vic.is_world_id_persisted = false

	if vic.is_reward_claimable():
		print("  [FAIL] is_reward_claimable returned true when is_world_id_persisted is false!")
		return false

	var pts := vic.claim_legacy_reward()
	if pts != 0:
		print("  [FAIL] claim_legacy_reward awarded points on unpersisted world ID: %d" % pts)
		return false
	if mgr.legacy_balance != 0:
		print("  [FAIL] Profile balance changed on unpersisted claim attempt: %d" % mgr.legacy_balance)
		return false

	# Now simulate world achieving successful persistence
	vic.is_world_id_persisted = true
	if not vic.is_reward_claimable():
		print("  [FAIL] is_reward_claimable returned false once is_world_id_persisted became true!")
		return false
	var valid_pts := vic.claim_legacy_reward()
	if valid_pts != 100:
		print("  [FAIL] Claim failed after persistence: %d" % valid_pts)
		return false

	print("  [PASS] Unpersisted world ID migration gates claims fail-closed until disk persistence.")
	return true

func _test_atomic_write_failure_and_rollback() -> bool:
	print("--- Expanded Test 8: Atomic Write Failure and Rollback ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)
	# Set active_filepath to unwritable path
	mgr.active_filepath = "user://invalid_dir_no_exist/test.json"

	var res := mgr.claim_reward("test_atomic_fail", "victory", 100, "world_fail_unique_9")
	if res.get("success", true):
		print("  [FAIL] claim_reward should fail when file cannot be written!")
		return false
	if res.get("reason", "") != "save_failed":
		print("  [FAIL] Expected reason save_failed, got: %s" % res.get("reason", ""))
		return false
	if mgr.is_reward_claimed("test_atomic_fail"):
		print("  [FAIL] Reward was not rolled back from claimed_rewards dictionary!")
		return false
	if mgr.legacy_balance != 0 or mgr.lifetime_legacy_earned != 0:
		print("  [FAIL] Balances were not rolled back: bal=%d earned=%d" % [mgr.legacy_balance, mgr.lifetime_legacy_earned])
		return false

	print("  [PASS] Disk save failure triggers complete atomic in-memory rollback.")
	return true

func _test_float_nan_invalid_amount_rejection() -> bool:
	print("--- Expanded Test 9: Float / NaN / Inf Rejection Fail-Closed ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)

	# NaN amount
	var r_nan := mgr.claim_reward("r_nan", "victory", NAN, "world_test")
	if r_nan.get("success", true) or r_nan.get("reason") != "invalid_amount":
		print("  [FAIL] NaN amount not rejected fail-closed: %s" % str(r_nan))
		return false

	# Inf amount
	var r_inf := mgr.claim_reward("r_inf", "victory", INF, "world_test")
	if r_inf.get("success", true) or r_inf.get("reason") != "invalid_amount":
		print("  [FAIL] INF amount not rejected fail-closed: %s" % str(r_inf))
		return false

	# Non-integer float amount (12.5)
	var r_float := mgr.claim_reward("r_float", "victory", 12.5, "world_test")
	if r_float.get("success", true) or r_float.get("reason") != "invalid_amount":
		print("  [FAIL] Non-integer float amount not rejected: %s" % str(r_float))
		return false

	# Negative float (-10.0)
	var r_neg := mgr.claim_reward("r_neg", "victory", -10.0, "world_test")
	if r_neg.get("success", true) or r_neg.get("reason") != "invalid_amount":
		print("  [FAIL] Negative amount not rejected: %s" % str(r_neg))
		return false

	# Validate profile schema data rejects NaN / float
	var bad_data = {
		"schema_version": 1,
		"profile_id": "test",
		"legacy_balance": NAN,
		"lifetime_legacy_earned": 0,
		"lifetime_legacy_spent": 0,
		"claimed_rewards": {}
	}
	var val_nan = LegacyProfileManager.validate_profile_data(bad_data)
	if val_nan.get("valid", true):
		print("  [FAIL] validate_profile_data accepted NaN balance!")
		return false

	bad_data["legacy_balance"] = 55.5
	var val_float = LegacyProfileManager.validate_profile_data(bad_data)
	if val_float.get("valid", true):
		print("  [FAIL] validate_profile_data accepted non-integer float balance!")
		return false

	print("  [PASS] Float, NaN, Inf, and non-integer amounts strictly rejected fail-closed.")
	return true

func _test_failed_operations_leave_state_unchanged() -> bool:
	print("--- Expanded Test 10: Failed Operations Leave State Unchanged ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)
	mgr.claim_reward("initial_valid", "victory", 50, "world_valid")

	var initial_balance: int = mgr.legacy_balance
	var initial_earned: int = mgr.lifetime_legacy_earned
	var initial_spent: int = mgr.lifetime_legacy_spent
	var initial_records_count: int = mgr.claimed_rewards.size()

	# Attempt 1: Duplicate claim
	mgr.claim_reward("initial_valid", "victory", 50, "world_valid")
	# Attempt 2: Empty reward ID
	mgr.claim_reward("", "victory", 100, "world_valid")
	# Attempt 3: Negative amount
	mgr.claim_reward("neg_id", "victory", -20, "world_valid")
	# Attempt 4: Unsupported source
	mgr.claim_reward("cheat_id", "invalid_source", 50, "world_valid")
	# Attempt 5: NaN amount
	mgr.claim_reward("nan_id", "victory", NAN, "world_valid")

	if mgr.legacy_balance != initial_balance:
		print("  [FAIL] Balance changed: %d != %d" % [mgr.legacy_balance, initial_balance])
		return false
	if mgr.lifetime_legacy_earned != initial_earned:
		print("  [FAIL] Lifetime earned changed: %d != %d" % [mgr.lifetime_legacy_earned, initial_earned])
		return false
	if mgr.lifetime_legacy_spent != initial_spent:
		print("  [FAIL] Lifetime spent changed: %d != %d" % [mgr.lifetime_legacy_spent, initial_spent])
		return false
	if mgr.claimed_rewards.size() != initial_records_count:
		print("  [FAIL] Claimed rewards count changed: %d != %d" % [mgr.claimed_rewards.size(), initial_records_count])
		return false

	print("  [PASS] Profile state strictly invariant across all rejected operations.")
	return true

func _test_canonical_reward_id_enforcement_and_custom_id_bypass_rejection() -> bool:
	print("--- FIX-1Z-E: Canonical Reward ID Enforcement & Custom ID Rejection ---")
	_cleanup_test_files()
	var profile := LegacyProfileManager.new(TEST_PROFILE_PATH)
	var vic_mgr := VictoryManager.new()
	vic_mgr.profile_mgr = profile
	vic_mgr.world_id = "world_sec_alpha_1"
	vic_mgr.is_world_id_persisted = true
	vic_mgr.is_victory_achieved = true
	vic_mgr.legacy_points_earned = 100

	# Ensure canonical id helper
	var canon_id := vic_mgr.get_canonical_victory_reward_id()
	if canon_id != "victory_world_sec_alpha_1":
		print("  [FAIL] Expected canonical ID 'victory_world_sec_alpha_1', got: '%s'" % canon_id)
		return false

	# Attempt to bypass using custom reward ID
	var awarded := vic_mgr.claim_legacy_reward("custom_exploit_id_999")
	if awarded != 100:
		print("  [FAIL] Expected 100 points awarded, got: %d" % awarded)
		return false

	# Verify that the canonical ID was claimed in profile, NOT the custom exploit ID
	if profile.is_reward_claimed("custom_exploit_id_999"):
		print("  [FAIL] Custom exploit ID was accepted and registered in profile!")
		return false
	if not profile.is_reward_claimed("victory_world_sec_alpha_1"):
		print("  [FAIL] Canonical ID was not registered in profile!")
		return false

	# Verify duplicate claim with different custom ID is rejected
	var duplicate_awarded := vic_mgr.claim_legacy_reward("different_custom_exploit_id")
	if duplicate_awarded != 0:
		print("  [FAIL] Duplicate claim with different custom ID awarded points: %d" % duplicate_awarded)
		return false

	if profile.legacy_balance != 100:
		print("  [FAIL] Profile balance unexpected: %d (expected 100)" % profile.legacy_balance)
		return false

	# Simulate reload from an older save before claim was recorded in victory_mgr
	vic_mgr.is_legacy_claimed = false
	if vic_mgr.is_reward_claimable():
		print("  [FAIL] is_reward_claimable returned true after older save reload!")
		return false
	var reloaded_claim := vic_mgr.claim_legacy_reward()
	if reloaded_claim != 0:
		print("  [FAIL] Reloaded older save was able to claim again!")
		return false
	if not vic_mgr.is_legacy_claimed:
		print("  [FAIL] is_legacy_claimed was not synchronized to true!")
		return false

	print("  [PASS] Canonical reward ID strictly enforced; arbitrary custom IDs rejected.")
	return true

func _test_safe_backup_recovery_and_corrupt_primary_protection() -> bool:
	print("--- FIX-1Z-F & FIX-1Z-H: Safe Backup Recovery & Corrupt Target Protection ---")
	_cleanup_test_files()
	# Step 1: Create a valid profile and save it to produce valid primary and backup
	var profile := LegacyProfileManager.new(TEST_PROFILE_PATH)
	var claim_res := profile.claim_reward("rew_safe_backup", "victory", 100, "world_safe")
	if not claim_res.get("success", false):
		print("  [FAIL] Initial claim failed: %s" % str(claim_res))
		return false

	# Second save creates the backup
	profile.save_profile()
	if not FileAccess.file_exists(TEST_PROFILE_BAK):
		print("  [FAIL] Backup profile file does not exist after second save.")
		return false

	# Step 2: Corrupt the primary file
	var corrupt_file := FileAccess.open(TEST_PROFILE_PATH, FileAccess.WRITE)
	corrupt_file.store_string("{\n  \"schema_version\": 1,\n  \"broken_json\": [")
	corrupt_file.close()

	# Step 3: Load profile - should recover from valid backup
	var recovery_profile := LegacyProfileManager.new(TEST_PROFILE_PATH)
	if recovery_profile.get_status() != LegacyProfileManager.STATUS_RECOVERED_FROM_BACKUP:
		print("  [FAIL] Expected status 'recovered_from_backup', got: '%s'" % recovery_profile.get_status())
		return false
	if recovery_profile.legacy_balance != 100:
		print("  [FAIL] Recovered balance mismatch: %d != 100" % recovery_profile.legacy_balance)
		return false

	# Step 4: Now save_profile() after recovery.
	# The on-disk primary file is STILL corrupt.
	# FIX-1Z-H guarantees that the corrupt primary is NOT copied over the valid backup!
	var save_res := recovery_profile.save_profile()
	if not save_res:
		print("  [FAIL] save_profile failed after backup recovery!")
		return false

	# Check that backup file is still valid JSON and not corrupted!
	var bak_val := recovery_profile._read_and_validate_json_file(TEST_PROFILE_BAK)
	if not bak_val.get("valid", false):
		print("  [FAIL] Backup was overwritten with corrupt primary file! Error: %s" % bak_val.get("error", ""))
		return false

	# Check that primary file is now valid JSON
	var primary_val := recovery_profile._read_and_validate_json_file(TEST_PROFILE_PATH)
	if not primary_val.get("valid", false):
		print("  [FAIL] Primary file is not valid after save: %s" % primary_val.get("error", ""))
		return false

	print("  [PASS] Backup recovery succeeded and corrupt primary was never rotated over valid backup.")
	return true

func _test_save_manager_atomic_backup_hardening() -> bool:
	print("--- FIX-1Z-G: SaveManager Atomic Writes and Backup Safety ---")
	_cleanup_test_files()
	var test_save_path := "user://test_save_atomic.json"
	var test_bak_path := test_save_path + ".bak"
	var test_tmp_path := test_save_path + ".tmp"

	var dir := DirAccess.open("user://")
	if dir != null:
		if FileAccess.file_exists(test_save_path): dir.remove(test_save_path)
		if FileAccess.file_exists(test_bak_path): dir.remove(test_bak_path)
		if FileAccess.file_exists(test_tmp_path): dir.remove(test_tmp_path)

	var dummy_data := {"world": 1, "score": 999}
	var save_ok1 := SaveManager.save_dict_to_file(dummy_data, test_save_path)
	if not save_ok1:
		print("  [FAIL] Initial save_dict_to_file failed.")
		return false
	if not FileAccess.file_exists(test_save_path):
		print("  [FAIL] Target save file missing after write.")
		return false
	if FileAccess.file_exists(test_tmp_path):
		print("  [FAIL] Lingering .tmp file found after save.")
		return false

	# Second save creates backup
	dummy_data["score"] = 1000
	var save_ok2 := SaveManager.save_dict_to_file(dummy_data, test_save_path)
	if not save_ok2:
		print("  [FAIL] Second save_dict_to_file failed.")
		return false
	if not FileAccess.file_exists(test_bak_path):
		print("  [FAIL] Backup file missing after second save.")
		return false

	# Read back backup to ensure it contains previous score (999)
	var bak_file := FileAccess.open(test_bak_path, FileAccess.READ)
	var bak_json = JSON.parse_string(bak_file.get_as_text())
	bak_file.close()
	if int(bak_json.get("score", 0)) != 999:
		print("  [FAIL] Backup file does not contain previous state.")
		return false

	# Clean up
	if dir != null:
		if FileAccess.file_exists(test_save_path): dir.remove(test_save_path)
		if FileAccess.file_exists(test_bak_path): dir.remove(test_bak_path)
		if FileAccess.file_exists(test_tmp_path): dir.remove(test_tmp_path)

	print("  [PASS] SaveManager writes atomically and rotates backups reliably.")
	return true

func _test_hud_reward_status_classification() -> bool:
	print("--- FIX-1Z-I: HUD Reward Status Classification ---")
	_cleanup_test_files()
	var HUDScript = load("res://scripts/ui/hud.gd")
	var hud = HUDScript.new()
	var test_btn = Button.new()
	var test_lbl = Label.new()
	hud.claim_victory_btn = test_btn
	hud.legacy_status_label = test_lbl

	var profile := LegacyProfileManager.new(TEST_PROFILE_PATH)
	LegacyProfileManager.set_instance(profile)

	var vic_mgr = VictoryManager.new()
	var mock_script = GDScript.new()
	mock_script.source_code = "extends Node\nvar victory_mgr = null\n"
	mock_script.reload()
	var mock_world_view = Node.new()
	mock_world_view.set_script(mock_script)
	mock_world_view.victory_mgr = vic_mgr
	hud.world_view_ref = mock_world_view

	vic_mgr.profile_mgr = profile
	vic_mgr.world_id = "world_hud_test_1"
	vic_mgr.is_victory_achieved = true
	vic_mgr.legacy_points_earned = 100

	# Case 1: Unpersisted world ID -> must show "Chưa Lưu Thế Giới", NOT "Đã Nhận Di Sản"
	vic_mgr.is_world_id_persisted = false
	vic_mgr.is_legacy_claimed = false
	hud._refresh_victory_claim_state()
	if not test_btn.disabled or test_btn.text != "Chưa Lưu Thế Giới":
		print("  [FAIL] Case 1 (Unpersisted): Expected 'Chưa Lưu Thế Giới' (disabled), got: '%s' (disabled=%s)" % [test_btn.text, str(test_btn.disabled)])
		mock_world_view.free()
		hud.free()
		return false

	# Case 2: Invalid world ID -> must show "ID Thế Giới Không Hợp Lệ"
	vic_mgr.is_world_id_persisted = true
	vic_mgr.world_id = "world_1234" # seed-only invalid
	hud._refresh_victory_claim_state()
	if not test_btn.disabled or test_btn.text != "ID Thế Giới Không Hợp Lệ":
		print("  [FAIL] Case 2 (Invalid ID): Expected 'ID Thế Giới Không Hợp Lệ' (disabled), got: '%s'" % test_btn.text)
		mock_world_view.free()
		hud.free()
		return false

	# Case 3: Claimable -> button enabled, "Nhận Di Sản (+100)"
	vic_mgr.world_id = "world_hud_test_valid_1"
	hud._refresh_victory_claim_state()
	if test_btn.disabled or test_btn.text != "Nhận Di Sản (+100)":
		print("  [FAIL] Case 3 (Claimable): Expected enabled 'Nhận Di Sản (+100)', got disabled=%s text='%s'" % [str(test_btn.disabled), test_btn.text])
		mock_world_view.free()
		hud.free()
		return false

	# Case 4: Profile unavailable -> "Hồ Sơ Lỗi (Không Thể Nhận)"
	profile.profile_status = LegacyProfileManager.STATUS_UNAVAILABLE
	hud._refresh_victory_claim_state()
	if not test_btn.disabled or test_btn.text != "Hồ Sơ Lỗi (Không Thể Nhận)":
		print("  [FAIL] Case 4 (Unavailable): Expected 'Hồ Sơ Lỗi (Không Thể Nhận)', got: '%s'" % test_btn.text)
		mock_world_view.free()
		hud.free()
		return false
	profile.profile_status = LegacyProfileManager.STATUS_LOADED

	# Case 5: Genuinely claimed -> "Đã Nhận Di Sản"
	vic_mgr.is_legacy_claimed = true
	hud._refresh_victory_claim_state()
	if not test_btn.disabled or test_btn.text != "Đã Nhận Di Sản":
		print("  [FAIL] Case 5 (Claimed): Expected 'Đã Nhận Di Sản' (disabled), got: '%s'" % test_btn.text)
		mock_world_view.free()
		hud.free()
		return false

	# Case 6: Victory not yet achieved -> "Chưa Đạt Điều Kiện"
	vic_mgr.is_victory_achieved = false
	vic_mgr.is_legacy_claimed = false
	hud._refresh_victory_claim_state()
	if not test_btn.disabled or test_btn.text != "Chưa Đạt Điều Kiện":
		print("  [FAIL] Case 6 (Unachieved): Expected 'Chưa Đạt Điều Kiện' (disabled), got: '%s'" % test_btn.text)
		mock_world_view.free()
		hud.free()
		return false

	test_btn.free()
	test_lbl.free()
	mock_world_view.free()
	hud.free()
	print("  [PASS] HUD accurately distinguishes all gating and claim states.")
	return true

func _test_integer_overflow_rejection() -> bool:
	print("--- FIX-1Z-J: Numeric Overflow Protection Fail-Closed ---")
	_cleanup_test_files()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)

	# Valid initial claim
	var r1 := mgr.claim_reward("r_norm", "victory", 100, "world_overflow_1")
	if not r1.get("success", false):
		print("  [FAIL] Valid initial claim failed: %s" % str(r1))
		return false

	# Claim exceeding MAX_SAFE_INT directly
	var r_huge := mgr.claim_reward("r_huge", "victory", mgr.MAX_SAFE_INT, "world_overflow_1")
	if r_huge.get("success", true) or r_huge.get("reason") != "overflow":
		print("  [FAIL] Overflow claim was not rejected with reason 'overflow': %s" % str(r_huge))
		return false

	# Balance must remain unchanged at 100
	if mgr.legacy_balance != 100:
		print("  [FAIL] Balance changed after rejected overflow claim: %d" % mgr.legacy_balance)
		return false

	# Profile schema validation rejects overflow values
	var bad_dict = {
		"schema_version": 1,
		"profile_id": "player_profile_test",
		"legacy_balance": 9223372036854775807,
		"lifetime_legacy_earned": 9223372036854775807,
		"lifetime_legacy_spent": 0,
		"claimed_rewards": {
			"r1": {
				"reward_id": "r1",
				"source": "victory",
				"amount": 9223372036854775800,
				"world_id": "w1"
			},
			"r2": {
				"reward_id": "r2",
				"source": "victory",
				"amount": 100,
				"world_id": "w1"
			}
		}
	}
	# r1 amount + r2 amount overflows MAX_SAFE_INT!
	var val_res = LegacyProfileManager.validate_profile_data(bad_dict)
	if val_res.get("valid", true):
		print("  [FAIL] validate_profile_data accepted sum that overflows 64-bit int!")
		return false

	print("  [PASS] 64-bit integer overflow bounds strictly enforced fail-closed.")
	return true

func _test_fix_1z_k_fail_closed_rewards() -> bool:
	print("--- FIX-1Z-K: Fail-Closed Rewards (No Null-Profile Fallback) ---")
	_cleanup_test_files()
	var vic := VictoryManager.new()
	vic.world_id = "world_k_test_12345"
	vic.is_world_id_persisted = true
	vic.is_victory_achieved = true
	vic.legacy_points_earned = 100

	# 1. Null profile: claims must be rejected, return 0, is_legacy_claimed must remain false
	vic.profile_mgr = null
	if vic.is_reward_claimable():
		print("  [FAIL] is_reward_claimable returned true with profile_mgr == null")
		return false
	var pts_null := vic.claim_legacy_reward()
	if pts_null != 0:
		print("  [FAIL] claim_legacy_reward awarded points (%d) with profile_mgr == null" % pts_null)
		return false
	if vic.is_legacy_claimed:
		print("  [FAIL] is_legacy_claimed was set to true on failed null-profile claim")
		return false

	# 2. Mock profile with missing methods
	var mock_incomplete = RefCounted.new()
	vic.profile_mgr = mock_incomplete
	if vic.is_reward_claimable():
		print("  [FAIL] is_reward_claimable returned true with incomplete profile object")
		return false
	var pts_incomplete := vic.claim_legacy_reward()
	if pts_incomplete != 0 or vic.is_legacy_claimed:
		print("  [FAIL] claim_legacy_reward succeeded with incomplete profile object")
		return false

	# 3. Profile manager unavailable
	var profile := LegacyProfileManager.new(TEST_PROFILE_PATH)
	profile.profile_status = LegacyProfileManager.STATUS_UNAVAILABLE
	vic.profile_mgr = profile
	if vic.is_reward_claimable():
		print("  [FAIL] is_reward_claimable returned true with unavailable profile")
		return false
	var pts_unavail := vic.claim_legacy_reward()
	if pts_unavail != 0 or vic.is_legacy_claimed:
		print("  [FAIL] claim_legacy_reward succeeded with unavailable profile")
		return false

	# 4. Valid profile: normal claim succeeds
	profile.profile_status = LegacyProfileManager.STATUS_LOADED
	if not vic.is_reward_claimable():
		print("  [FAIL] is_reward_claimable returned false with valid available profile")
		return false
	var pts_valid := vic.claim_legacy_reward()
	if pts_valid != 100:
		print("  [FAIL] Expected 100 points, got: %d" % pts_valid)
		return false
	if not vic.is_legacy_claimed:
		print("  [FAIL] is_legacy_claimed was not set to true after successful claim")
		return false
	if profile.legacy_balance != 100:
		print("  [FAIL] Profile legacy balance not updated: %d" % profile.legacy_balance)
		return false

	# 5. Duplicate claim rejected
	if vic.is_reward_claimable():
		print("  [FAIL] is_reward_claimable returned true after claim")
		return false
	var pts_dup := vic.claim_legacy_reward()
	if pts_dup != 0:
		print("  [FAIL] Duplicate claim awarded points: %d" % pts_dup)
		return false

	print("  [PASS] Non-persistent fallback eliminated; claims fail closed when profile is missing or unavailable.")
	return true

func _test_fix_1z_l_world_id_persistence_lifecycle() -> bool:
	print("--- FIX-1Z-L: World ID Persistence Lifecycle & Gating ---")
	_cleanup_test_files()
	var test_save_path := "user://test_lifecycle_save.json"
	var dir := DirAccess.open("user://")
	if dir != null:
		if FileAccess.file_exists(test_save_path): dir.remove(test_save_path)
		if FileAccess.file_exists(test_save_path + ".bak"): dir.remove(test_save_path + ".bak")
		if FileAccess.file_exists(test_save_path + ".tmp"): dir.remove(test_save_path + ".tmp")

	# 1. New world starts unpersisted
	var WorldViewScript = load("res://scripts/world/world_view.gd")
	var generated_id: String = WorldViewScript.generate_unique_world_id(12345)

	var vic := VictoryManager.new()
	var profile := LegacyProfileManager.new(TEST_PROFILE_PATH)
	vic.profile_mgr = profile
	vic.world_id = generated_id
	# Initial state must be false
	if vic.is_world_id_persisted:
		print("  [FAIL] VictoryManager.is_world_id_persisted did not default to false!")
		return false

	vic.is_victory_achieved = true
	vic.legacy_points_earned = 100

	# 2. Victory claims blocked while unpersisted
	if vic.is_reward_claimable():
		print("  [FAIL] is_reward_claimable returned true on unpersisted world ID!")
		return false
	var pts_unpersisted := vic.claim_legacy_reward()
	if pts_unpersisted != 0 or vic.is_legacy_claimed:
		print("  [FAIL] claim_legacy_reward granted points before world save!")
		return false

	# Create mock world view
	var mock_script = GDScript.new()
	mock_script.source_code = "extends Node\nvar world_id = \"\"\nvar world_seed = 12345\nvar is_world_id_persisted = false\nvar victory_mgr = null\n"
	mock_script.reload()
	var world_node = Node.new()
	world_node.set_script(mock_script)
	world_node.world_id = generated_id
	world_node.is_world_id_persisted = false
	world_node.victory_mgr = vic

	# 3. Failed first save keeps is_world_id_persisted == false
	SaveManager.reset_test_injection()
	SaveManager._test_inject_fail_tmp_write = true
	var fail_save_res := SaveManager.save_to_file(world_node, test_save_path)
	SaveManager.reset_test_injection()
	if fail_save_res.get("success", true):
		print("  [FAIL] Injected save failure reported success!")
		world_node.free()
		return false
	if world_node.is_world_id_persisted or vic.is_world_id_persisted:
		print("  [FAIL] Failed save incorrectly marked world ID as persisted!")
		world_node.free()
		return false
	if vic.claim_legacy_reward() != 0:
		print("  [FAIL] Claim succeeded after failed save attempt!")
		world_node.free()
		return false

	# 4. Successful save sets is_world_id_persisted = true
	var ok_save_res := SaveManager.save_to_file(world_node, test_save_path)
	if not ok_save_res.get("success", false):
		print("  [FAIL] SaveManager.save_to_file failed: %s" % ok_save_res.get("error", ""))
		world_node.free()
		return false
	if not world_node.is_world_id_persisted or not vic.is_world_id_persisted:
		print("  [FAIL] Successful save failed to set is_world_id_persisted = true!")
		world_node.free()
		return false

	# 5. Claims now allowed
	if not vic.is_reward_claimable():
		print("  [FAIL] Reward not claimable after successful save!")
		world_node.free()
		return false
	var pts_ok := vic.claim_legacy_reward()
	if pts_ok != 100:
		print("  [FAIL] Claim failed after successful save: %d" % pts_ok)
		world_node.free()
		return false

	# 6. Load preserves world ID and persisted status
	var load_res := SaveManager.load_from_file(test_save_path)
	if not load_res.get("success", false):
		print("  [FAIL] SaveManager.load_from_file failed: %s" % load_res.get("error", ""))
		world_node.free()
		return false

	var reloaded_world = Node.new()
	reloaded_world.set_script(mock_script)
	var reloaded_vic = VictoryManager.new()
	reloaded_world.victory_mgr = reloaded_vic

	var apply_res := SaveManager.apply_loaded_state_to_world(reloaded_world, load_res["data"])
	if not apply_res.get("success", false):
		print("  [FAIL] apply_loaded_state_to_world failed: %s" % apply_res.get("error", ""))
		reloaded_world.free()
		world_node.free()
		return false
	if reloaded_world.world_id != generated_id:
		print("  [FAIL] Reloaded world ID mismatch: %s != %s" % [reloaded_world.world_id, generated_id])
		reloaded_world.free()
		world_node.free()
		return false
	if not reloaded_world.is_world_id_persisted or not reloaded_vic.is_world_id_persisted:
		print("  [FAIL] Reloaded world ID not marked as persisted!")
		reloaded_world.free()
		world_node.free()
		return false

	# 7. Unrelated subsequent write failure does NOT reset is_world_id_persisted on an already-persisted world
	SaveManager._test_inject_fail_tmp_write = true
	var fail_second_save := SaveManager.save_to_file(reloaded_world, test_save_path)
	SaveManager.reset_test_injection()
	if fail_second_save.get("success", true):
		print("  [FAIL] Second save injection unexpectedly reported success!")
		reloaded_world.free()
		world_node.free()
		return false
	if not reloaded_world.is_world_id_persisted or not reloaded_vic.is_world_id_persisted:
		print("  [FAIL] Unrelated write failure reset already-persisted identity status!")
		reloaded_world.free()
		world_node.free()
		return false

	reloaded_world.free()
	world_node.free()
	if dir != null:
		if FileAccess.file_exists(test_save_path): dir.remove(test_save_path)
		if FileAccess.file_exists(test_save_path + ".bak"): dir.remove(test_save_path + ".bak")
		if FileAccess.file_exists(test_save_path + ".tmp"): dir.remove(test_save_path + ".tmp")

	print("  [PASS] World ID persistence lifecycle and gating verified across creation, save, load, and errors.")
	return true

func _test_fix_1z_m_save_manager_backup_rotation_10_cases() -> bool:
	print("--- FIX-1Z-M: SaveManager 10 Failure Injection & Backup Rotation Cases ---")
	_cleanup_test_files()
	var test_path := "user://test_m_hardening.json"
	var test_bak := test_path + ".bak"
	var test_tmp := test_path + ".tmp"
	var test_bak_tmp := test_path + ".bak.tmp"
	var dir := DirAccess.open("user://")

	var cleanup_m = func():
		SaveManager.reset_test_injection()
		LegacyProfileManager.reset_test_injection()
		if dir != null:
			if FileAccess.file_exists(test_path): dir.remove(test_path)
			if FileAccess.file_exists(test_bak): dir.remove(test_bak)
			if FileAccess.file_exists(test_tmp): dir.remove(test_tmp)
			if FileAccess.file_exists(test_bak_tmp): dir.remove(test_bak_tmp)

	var make_data = func(score: int) -> Dictionary:
		return {
			"schema_version": 1,
			"timestamp": "2026-10-31",
			"metadata": {"world_id": "world_m_hard_1", "world_seed": 100},
			"resources": {"score": score},
			"buildings": [],
			"citizens": []
		}

	cleanup_m.call()

	# Establish initial valid save
	SaveManager.save_dict_to_file(make_data.call(10), test_path)
	SaveManager.save_dict_to_file(make_data.call(20), test_path)
	# Now primary has 20, backup has 10

	# Case 1: Primary write interrupted (tmp write fail) -> original primary and backup untouched
	SaveManager._test_inject_fail_tmp_write = true
	var res1 = SaveManager.save_dict_to_file(make_data.call(30), test_path)
	SaveManager.reset_test_injection()
	if res1:
		print("  [FAIL] Case 1: Expected save_dict_to_file to fail with tmp write failure")
		cleanup_m.call()
		return false
	var read1 = SaveManager.load_from_file(test_path)
	if int(read1.get("data", {}).get("resources", {}).get("score", 0)) != 20:
		print("  [FAIL] Case 1: Primary file modified despite tmp write failure!")
		cleanup_m.call()
		return false

	# Case 2: Staged backup creation fail -> primary and existing backup untouched
	SaveManager._test_inject_fail_backup_create = true
	var res2 = SaveManager.save_dict_to_file(make_data.call(30), test_path)
	SaveManager.reset_test_injection()
	if res2:
		print("  [FAIL] Case 2: Expected failure on staged backup creation failure")
		cleanup_m.call()
		return false
	var read2_bak = SaveManager.load_from_file(test_bak)
	if int(read2_bak.get("data", {}).get("resources", {}).get("score", 0)) != 10:
		print("  [FAIL] Case 2: Existing backup damaged on staged backup create failure!")
		cleanup_m.call()
		return false

	# Case 3: Staged backup replace fail -> primary and existing backup untouched
	SaveManager._test_inject_fail_backup_replace = true
	var res3 = SaveManager.save_dict_to_file(make_data.call(30), test_path)
	SaveManager.reset_test_injection()
	if res3:
		print("  [FAIL] Case 3: Expected failure on backup replace failure")
		cleanup_m.call()
		return false
	var read3_bak = SaveManager.load_from_file(test_bak)
	if int(read3_bak.get("data", {}).get("resources", {}).get("score", 0)) != 10:
		print("  [FAIL] Case 3: Existing backup damaged on replace failure!")
		cleanup_m.call()
		return false

	# Case 4: Target removal fail -> tmp cleaned, backup untouched
	SaveManager._test_inject_fail_target_remove = true
	var res4 = SaveManager.save_dict_to_file(make_data.call(30), test_path)
	SaveManager.reset_test_injection()
	if res4:
		print("  [FAIL] Case 4: Expected failure on target removal failure")
		cleanup_m.call()
		return false
	if FileAccess.file_exists(test_tmp):
		print("  [FAIL] Case 4: tmp file lingering after removal failure")
		cleanup_m.call()
		return false

	# Case 5: Target rename fail -> restored from backup, tmp cleaned
	SaveManager._test_inject_fail_target_rename = true
	var res5 = SaveManager.save_dict_to_file(make_data.call(30), test_path)
	SaveManager.reset_test_injection()
	if res5:
		print("  [FAIL] Case 5: Expected failure on target rename failure")
		cleanup_m.call()
		return false
	if not FileAccess.file_exists(test_path):
		print("  [FAIL] Case 5: Target file missing after rename failure rollback!")
		cleanup_m.call()
		return false

	# Case 6: Target rename fail with restore fail -> reported error gracefully
	SaveManager._test_inject_fail_target_rename = true
	SaveManager._test_inject_fail_backup_restore = true
	var res6 = SaveManager.save_dict_to_file(make_data.call(30), test_path)
	SaveManager.reset_test_injection()
	if res6:
		print("  [FAIL] Case 6: Expected failure on rename & restore failure")
		cleanup_m.call()
		return false

	# Case 7: Corrupt primary on save -> backup NOT overwritten by bad primary
	cleanup_m.call()
	SaveManager.save_dict_to_file(make_data.call(100), test_path)
	SaveManager.save_dict_to_file(make_data.call(200), test_path) # Now backup has 100
	# Corrupt the primary
	var corrupt_f := FileAccess.open(test_path, FileAccess.WRITE)
	corrupt_f.store_string("{ corrupt json: [")
	corrupt_f.close()
	# Save new data (300)
	var res7 = SaveManager.save_dict_to_file(make_data.call(300), test_path)
	if not res7:
		print("  [FAIL] Case 7: save_dict_to_file failed when overwriting corrupt primary")
		cleanup_m.call()
		return false
	# Verify backup still has 100 and was NOT overwritten by corrupt primary
	var read7_bak = SaveManager.load_from_file(test_bak)
	if int(read7_bak.get("data", {}).get("resources", {}).get("score", 0)) != 100:
		print("  [FAIL] Case 7: Backup was overwritten by corrupt primary!")
		cleanup_m.call()
		return false

	# Case 8: Corrupt primary on load -> recovers from good backup
	var corrupt_f2 := FileAccess.open(test_path, FileAccess.WRITE)
	corrupt_f2.store_string("{ corrupt json again: [")
	corrupt_f2.close()
	var res8 = SaveManager.load_from_file(test_path)
	if not res8.get("success", false) or not res8.get("recovered_from_backup", false):
		print("  [FAIL] Case 8: Did not recover from backup when primary corrupt: %s" % str(res8))
		cleanup_m.call()
		return false
	if int(res8.get("data", {}).get("resources", {}).get("score", 0)) != 100:
		print("  [FAIL] Case 8: Recovered data score mismatch!")
		cleanup_m.call()
		return false

	# Case 9: Missing primary on load -> recovers from good backup
	dir.remove(test_path)
	var res9 = SaveManager.load_from_file(test_path)
	if not res9.get("success", false) or not res9.get("recovered_from_backup", false):
		print("  [FAIL] Case 9: Did not recover from backup when primary missing: %s" % str(res9))
		cleanup_m.call()
		return false

	# Case 10: Unopenable / empty primary on load -> recovers from good backup
	var empty_f := FileAccess.open(test_path, FileAccess.WRITE)
	empty_f.store_string("")
	empty_f.close()
	var res10 = SaveManager.load_from_file(test_path)
	if not res10.get("success", false) or not res10.get("recovered_from_backup", false):
		print("  [FAIL] Case 10: Did not recover from backup when primary empty: %s" % str(res10))
		cleanup_m.call()
		return false

	# ProfileManager failure injection test
	var prof := LegacyProfileManager.new(TEST_PROFILE_PATH)
	LegacyProfileManager._test_inject_fail_write = true
	var r_p1 = prof.claim_reward("prof_inj_1", "victory", 100, "w1")
	LegacyProfileManager.reset_test_injection()
	if r_p1.get("success", true) or r_p1.get("reason") != "save_failed":
		print("  [FAIL] LegacyProfileManager._test_inject_fail_write was not rejected")
		cleanup_m.call()
		return false
	if prof.is_reward_claimed("prof_inj_1") or prof.legacy_balance != 0:
		print("  [FAIL] LegacyProfileManager failed write did not roll back state")
		cleanup_m.call()
		return false

	LegacyProfileManager._test_inject_fail_rename = true
	var r_p2 = prof.claim_reward("prof_inj_2", "victory", 100, "w1")
	LegacyProfileManager.reset_test_injection()
	if r_p2.get("success", true) or r_p2.get("reason") != "save_failed":
		print("  [FAIL] LegacyProfileManager._test_inject_fail_rename was not rejected")
		cleanup_m.call()
		return false

	cleanup_m.call()
	print("  [PASS] All 10 failure injection scenarios for SaveManager backup rotation and recovery passed.")
	return true

func _test_fix_1z_n_float_64bit_boundary_precision() -> bool:
	print("--- FIX-1Z-N: 64-Bit Float Boundary Precision Validation ---")
	_cleanup_test_files()

	# 1. Test boundaries in LegacyProfileManager._is_valid_integer_val
	var max_int: int = 9223372036854775807
	if not LegacyProfileManager._is_valid_integer_val(max_int):
		print("  [FAIL] MAX_SAFE_INT rejected by LegacyProfileManager._is_valid_integer_val")
		return false

	var float_upper: float = LegacyProfileManager.FLOAT_INT64_EXCLUSIVE_UPPER # 9223372036854775808.0 (2^63)
	if LegacyProfileManager._is_valid_integer_val(float_upper):
		print("  [FAIL] FLOAT_INT64_EXCLUSIVE_UPPER (2^63) was accepted as valid int!")
		return false

	var largest_safe_float: float = 9223372036854774784.0 # largest float < 2^63
	if not LegacyProfileManager._is_valid_integer_val(largest_safe_float):
		print("  [FAIL] largest float < 2^63 rejected by LegacyProfileManager._is_valid_integer_val")
		return false

	var float_lower: float = LegacyProfileManager.FLOAT_INT64_INCLUSIVE_LOWER # -9223372036854775808.0 (-2^63)
	if not LegacyProfileManager._is_valid_integer_val(float_lower):
		print("  [FAIL] FLOAT_INT64_INCLUSIVE_LOWER rejected by LegacyProfileManager._is_valid_integer_val")
		return false

	# 2. Test boundaries in SaveManager._is_valid_integer_val
	if not SaveManager._is_valid_integer_val(max_int):
		print("  [FAIL] MAX_SAFE_INT rejected by SaveManager._is_valid_integer_val")
		return false
	if SaveManager._is_valid_integer_val(float_upper):
		print("  [FAIL] FLOAT_INT64_EXCLUSIVE_UPPER accepted by SaveManager._is_valid_integer_val")
		return false
	if not SaveManager._is_valid_integer_val(largest_safe_float):
		print("  [FAIL] largest float < 2^63 rejected by SaveManager._is_valid_integer_val")
		return false

	# 3. Test in claim_reward()
	var mgr := LegacyProfileManager.new(TEST_PROFILE_PATH)
	var r_overflow := mgr.claim_reward("r_bound_ovf", "victory", float_upper, "world_b1")
	if r_overflow.get("success", true) or r_overflow.get("reason") != "invalid_amount":
		print("  [FAIL] claim_reward accepted float 2^63 as amount: %s" % str(r_overflow))
		return false

	var r_neg_bound := mgr.claim_reward("r_bound_neg", "victory", float_lower, "world_b1")
	if r_neg_bound.get("success", true) or r_neg_bound.get("reason") != "invalid_amount":
		print("  [FAIL] claim_reward accepted negative float lower bound: %s" % str(r_neg_bound))
		return false

	var r_valid_float := mgr.claim_reward("r_bound_valid", "victory", 100.0, "world_b1")
	if not r_valid_float.get("success", false) or r_valid_float.get("points_awarded") != 100:
		print("  [FAIL] claim_reward failed for valid whole float 100.0: %s" % str(r_valid_float))
		return false

	# 4. Test in validate_profile_data()
	var bad_dict_float_bound = {
		"schema_version": 1,
		"profile_id": "test_profile",
		"legacy_balance": float_upper,
		"lifetime_legacy_earned": float_upper,
		"lifetime_legacy_spent": 0,
		"claimed_rewards": {}
	}
	var val_upper = LegacyProfileManager.validate_profile_data(bad_dict_float_bound)
	if val_upper.get("valid", true):
		print("  [FAIL] validate_profile_data accepted float_upper for legacy_balance!")
		return false

	print("  [PASS] 64-bit float boundary precision strictly enforced across all components.")
	return true
