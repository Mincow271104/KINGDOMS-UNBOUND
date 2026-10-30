extends SceneTree
## Headless Test Suite for Package 1Z: Legacy Fund & Meta-Progression Foundation.
## Validates profile persistence, fail-closed validation, exactly-once claims, multi-world victory,
## older save exploit prevention, achievement unlock, deferred treasury conversion, and UI reflection.

const LegacyProfileManager = preload("res://scripts/legacy/legacy_profile_manager.gd")
const VictoryManager = preload("res://scripts/core/victory_manager.gd")

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
	
	_cleanup_test_files()
	LegacyProfileManager.reset_instance()
	
	print("\n--------------------------------------------------------")
	if (pass_tc1 and pass_tc2 and pass_tc3 and pass_tc4 and pass_tc5 and
		pass_tc6 and pass_tc7 and pass_tc8 and pass_tc9 and pass_tc10 and
		pass_tc11 and pass_tc12 and pass_tc13 and pass_tc14 and pass_tc15):
		print("  ALL 15 PACKAGE 1Z TESTS PASSED SUCCESSFULLY! (Exit Code 0)")
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
		"legacy_balance": 500, # Tampered! earned (100) - spent (0) = 100 != 500
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
			# Sum = 100, but earned = 200
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
	if mgr2.legacy_balance != 100: # The backup had 100 balance before second claim
		print("  [FAIL] Recovered balance expected 100, got: %d" % mgr2.legacy_balance)
		return false
	
	# Corrupt both primary and backup
	var corrupt_bak := FileAccess.open(TEST_PROFILE_BAK, FileAccess.WRITE)
	corrupt_bak.store_string("CORRUPTED_BACKUP_DATA")
	corrupt_bak.close()
	
	var mgr3 := LegacyProfileManager.new(TEST_PROFILE_PATH)
	mgr3.legacy_balance = 75 # Set live state
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
	vic1.world_id = "world_alpha"
	vic1.is_victory_achieved = true
	vic1.legacy_points_earned = 100
	
	var pts1 := vic1.claim_legacy_reward()
	if pts1 != 100 or mgr.legacy_balance != 100:
		print("  [FAIL] World 1 victory claim failed: pts=%d bal=%d" % [pts1, mgr.legacy_balance])
		return false
		
	# World 2 victory
	var vic2 := VictoryManager.new()
	vic2.profile_mgr = mgr
	vic2.world_id = "world_beta"
	vic2.is_victory_achieved = true
	vic2.legacy_points_earned = 100
	
	var pts2 := vic2.claim_legacy_reward()
	if pts2 != 100 or mgr.legacy_balance != 200:
		print("  [FAIL] World 2 victory claim failed: pts=%d bal=%d" % [pts2, mgr.legacy_balance])
		return false
		
	# World 1 duplicate attempt from new manager instance
	var vic1_dup := VictoryManager.new()
	vic1_dup.profile_mgr = mgr
	vic1_dup.world_id = "world_alpha"
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
	vic.world_id = "world_gamma"
	vic.is_victory_achieved = true
	vic.legacy_points_earned = 100
	var first_pts := vic.claim_legacy_reward()
	if first_pts != 100:
		print("  [FAIL] Initial claim failed: %d" % first_pts)
		return false
		
	# Now simulate loading an older save file from world_gamma where is_legacy_claimed was FALSE
	var loaded_vic := VictoryManager.new()
	loaded_vic.profile_mgr = mgr
	loaded_vic.world_id = "world_gamma"
	loaded_vic.is_victory_achieved = true
	loaded_vic.is_legacy_claimed = false # Save file says false!
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
	
	# First unlock
	var ach_res := mgr.unlock_achievement("prosperity_victory", "world_omega")
	if not ach_res.get("success", false):
		print("  [FAIL] First achievement unlock failed: %s" % str(ach_res))
		return false
	if mgr.legacy_balance != 100:
		print("  [FAIL] Achievement points not credited to balance: %d" % mgr.legacy_balance)
		return false
	if not mgr.is_achievement_unlocked("prosperity_victory"):
		print("  [FAIL] is_achievement_unlocked returned false after unlocking.")
		return false
		
	# Second unlock attempt (e.g. from different world)
	var dup_ach := mgr.unlock_achievement("prosperity_victory", "world_psi")
	if dup_ach.get("success", true):
		print("  [FAIL] Second achievement unlock should be rejected, got: %s" % str(dup_ach))
		return false
	if dup_ach.get("reason", "") != "already_unlocked":
		print("  [FAIL] Unexpected reason for duplicate achievement: %s" % dup_ach.get("reason", ""))
		return false
	if mgr.legacy_balance != 100:
		print("  [FAIL] Balance increased on duplicate achievement: %d" % mgr.legacy_balance)
		return false
		
	# Unknown achievement
	var unk_res := mgr.unlock_achievement("undocumented_fake_achievement")
	if unk_res.get("success", true) or unk_res.get("reason") != "unknown_achievement":
		print("  [FAIL] Unknown achievement was not rejected fail-closed: %s" % str(unk_res))
		return false
		
	print("  [PASS] Achievement registry awards points once and rejects duplicate/unknown achievements.")
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
	vic.world_id = "world_ui_test"
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
