extends SceneTree
## Headless Test Suite for Phase 7: Population Growth, Victory, Collapse & Summaries.
## Validates TC-7.1 (Immigration), TC-7.2 (5-day Prosperity Hold), and TC-7.3 (Collapse Triggers).

const ImmigrationManager = preload("res://scripts/economy/immigration_manager.gd")
const VictoryManager = preload("res://scripts/core/victory_manager.gd")
const BuildingSystem = preload("res://scripts/economy/building_system.gd")
const EconomyConfig = preload("res://scripts/economy/economy_config.gd")

func _init() -> void:
	print("\n========================================================")
	print("  TEST SUITE: Phase 7 — Population, Victory & Collapse")
	print("========================================================\n")
	
	var pass_tc1: bool = _test_tc7_1_immigration()
	var pass_tc2: bool = _test_tc7_2_prosperity_victory_hold()
	var pass_tc3: bool = _test_tc7_3_collapse_triggers()
	
	print("\n--------------------------------------------------------")
	if pass_tc1 and pass_tc2 and pass_tc3:
		print("  ALL PHASE 7 TESTS PASSED SUCCESSFULLY! (Exit Code 0)")
		print("--------------------------------------------------------\n")
		quit(0)
	else:
		print("  PHASE 7 TESTS FAILED!")
		print("--------------------------------------------------------\n")
		quit(1)

func _test_tc7_1_immigration() -> bool:
	print("--- Running TC-7.1: Immigration Pacing & Condition Gating ---")
	var imm := ImmigrationManager.new(99999)
	
	# Case 1: Housing Full (24/24) -> Must be rejected
	var res1: Dictionary = imm.evaluate_immigration(24, 24, 150, 80.0, 75.0, 3)
	if res1["allowed"]:
		print("  [FAIL] Immigration allowed when housing is completely full!")
		return false
	if not res1["reason"].contains("Thiếu chỗ ở"):
		print("  [FAIL] Reason did not explain housing shortage: %s" % res1["reason"])
		return false
	print("  [PASS] Housing full correctly rejected: %s" % res1["reason"])

	# Case 2: Housing available (30 cap, 24 pop), but Food < 30 -> Must be rejected
	var res2: Dictionary = imm.evaluate_immigration(30, 24, 20, 80.0, 75.0, 3)
	if res2["allowed"]:
		print("  [FAIL] Immigration allowed when food is insufficient (<30)!")
		return false
	if not res2["reason"].contains("Thiếu lương thực"):
		print("  [FAIL] Reason did not explain food shortage: %s" % res2["reason"])
		return false
	print("  [PASS] Food deficit correctly rejected: %s" % res2["reason"])

	# Case 3: Housing available, food adequate, but Stability < 50% -> Must be rejected
	var res3: Dictionary = imm.evaluate_immigration(30, 24, 150, 40.0, 75.0, 3)
	if res3["allowed"]:
		print("  [FAIL] Immigration allowed when stability is below threshold (<50%)!")
		return false
	if not res3["reason"].contains("ổn định"):
		print("  [FAIL] Reason did not explain low stability: %s" % res3["reason"])
		return false
	print("  [PASS] Low stability correctly rejected: %s" % res3["reason"])

	# Case 4: Housing available, food adequate, stability adequate, but Morale < 60% -> Must be rejected
	var res4: Dictionary = imm.evaluate_immigration(30, 24, 150, 80.0, 50.0, 3)
	if res4["allowed"]:
		print("  [FAIL] Immigration allowed when morale is below threshold (<60%)!")
		return false
	if not res4["reason"].contains("Sĩ khí"):
		print("  [FAIL] Reason did not explain low morale: %s" % res4["reason"])
		return false
	print("  [PASS] Low morale correctly rejected: %s" % res4["reason"])

	# Case 5: All conditions met (30 cap, 24 pop, 150 food, 80% stability, 75% morale) -> Must succeed
	var res5: Dictionary = imm.evaluate_immigration(30, 24, 150, 80.0, 75.0, 3)
	if not res5["allowed"]:
		print("  [FAIL] Immigration rejected under optimal conditions: %s" % res5["reason"])
		return false
	if res5["count"] <= 0 or res5["immigrants"].is_empty():
		print("  [FAIL] No immigrants generated in allowed wave!")
		return false
	
	var first_imm: Dictionary = res5["immigrants"][0]
	if first_imm["id"] != "citizen_25":
		print("  [FAIL] Immigrant ID expected citizen_25, got %s" % first_imm["id"])
		return false
	if first_imm["name"].strip_edges().is_empty():
		print("  [FAIL] Immigrant name is empty!")
		return false
		
	print("  [PASS] Immigration wave admitted (%d citizens): %s" % [res5["count"], first_imm["name"]])
	print("  [PASS] TC-7.1 PASSED.\n")
	return true

func _test_tc7_2_prosperity_victory_hold() -> bool:
	print("--- Running TC-7.2: Continuous 5-Day Prosperity Victory Hold & Reset ---")
	var vm := VictoryManager.new()
	
	# Initial conditions meeting all victory thresholds
	# pop: 30, food: 600, treasury: 1200, stability: 85.0, morale: 80.0, techs: 3, town_hall: true
	var pop: int = 30
	var food: int = 600
	var treasury: int = 1200
	var stability: float = 85.0
	var morale: float = 80.0
	var techs: int = 3
	var town_hall: bool = true
	
	# Simulate 100 hours of continuous prosperity
	for h in range(100):
		var tick = vm.tick_hourly(pop, food, treasury, stability, morale, techs, town_hall, 10)
		if tick["status"] == "victory":
			print("  [FAIL] Victory triggered prematurely at hour %d (< 120 hours)!" % (h + 1))
			return false
			
	if not is_equal_approx(vm.hold_hours_elapsed, 100.0):
		print("  [FAIL] Expected 100 hold hours, got %f" % vm.hold_hours_elapsed)
		return false
	print("  [PASS] 100 hours held without premature victory trigger.")

	# On hour 101, food drops below 500 (e.g. 450) -> Hold duration MUST reset to 0!
	var reset_tick = vm.tick_hourly(pop, 450, treasury, stability, morale, techs, town_hall, 10)
	if vm.hold_hours_elapsed != 0.0:
		print("  [FAIL] Hold hours failed to reset to 0 on food deficit! (hold_hours = %f)" % vm.hold_hours_elapsed)
		return false
	print("  [PASS] Prosperity hold correctly reset to 0 on metric lapse.")

	# Re-satisfy all conditions and hold for full 120 hours (5 days)
	for h in range(119):
		var tick = vm.tick_hourly(pop, food, treasury, stability, morale, techs, town_hall, 10)
		if tick["status"] == "victory":
			print("  [FAIL] Victory triggered early at hold hour %d (< 120)!" % (h + 1))
			return false
			
	# Hour 120: Victory must trigger!
	var final_tick = vm.tick_hourly(pop, food, treasury, stability, morale, techs, town_hall, 10)
	if final_tick["status"] != "victory" or not vm.is_victory_achieved:
		print("  [FAIL] Victory failed to trigger at hour 120! Status: %s" % final_tick["status"])
		return false
		
	var report: Dictionary = final_tick["report"]
	if report["outcome"] != "VICTORY":
		print("  [FAIL] Summary report outcome expected VICTORY, got %s" % report["outcome"])
		return false
	if report["legacy_points"] != 100:
		print("  [FAIL] Expected 100 legacy points, got %d" % report["legacy_points"])
		return false
		
	# Verify duplicate legacy claim protection
	var claimed_1: int = vm.claim_legacy_reward()
	if claimed_1 != 100:
		print("  [FAIL] First legacy claim failed: %d" % claimed_1)
		return false
	var claimed_2: int = vm.claim_legacy_reward()
	if claimed_2 != 0:
		print("  [FAIL] Duplicate legacy claim permitted! Received %d" % claimed_2)
		return false
	print("  [PASS] Double-spend legacy protection verified.")
	print("  [PASS] TC-7.2 PASSED.\n")
	return true

func _test_tc7_3_collapse_triggers() -> bool:
	print("--- Running TC-7.3: Deterministic Collapse Triggers & Summaries ---")
	
	# Test 1: Extinction (Pop = 0)
	var vm_extinction := VictoryManager.new()
	var ext_tick = vm_extinction.tick_hourly(0, 100, 200, 50.0, 50.0, 1, true, 5)
	if ext_tick["status"] != "collapse":
		print("  [FAIL] Extinction did not trigger collapse when pop <= 0!")
		return false
	if not ext_tick["reason"].contains("Tuyệt chủng"):
		print("  [FAIL] Extinction reason incorrect: %s" % ext_tick["reason"])
		return false
	print("  [PASS] Extinction collapse triggered immediately: %s" % ext_tick["reason"])

	# Test 2: Town Hall Ruin (> 72 hours destroyed)
	var vm_townhall := VictoryManager.new()
	# 71 hours destroyed: must NOT trigger collapse yet
	for h in range(71):
		var tick = vm_townhall.tick_hourly(24, 100, 200, 50.0, 50.0, 1, false, 5)
		if tick["status"] == "collapse":
			print("  [FAIL] Town hall collapse triggered prematurely at hour %d!" % (h + 1))
			return false
	# At hour 72: must trigger collapse
	var th_collapse = vm_townhall.tick_hourly(24, 100, 200, 50.0, 50.0, 1, false, 5)
	if th_collapse["status"] != "collapse":
		print("  [FAIL] Town hall collapse failed to trigger at hour 72!")
		return false
	if not th_collapse["reason"].contains("Mất thủ đô"):
		print("  [FAIL] Town hall ruin reason incorrect: %s" % th_collapse["reason"])
		return false
	print("  [PASS] Town Hall ruin collapse triggered at 72 hours: %s" % th_collapse["reason"])

	# Test 3: Prolonged Anarchy (Stability = 0% for > 72 hours)
	var vm_anarchy := VictoryManager.new()
	# 71 hours at 0% stability: must NOT trigger collapse yet
	for h in range(71):
		var tick = vm_anarchy.tick_hourly(24, 0, 0, 0.0, 10.0, 1, true, 5)
		if tick["status"] == "collapse":
			print("  [FAIL] Anarchy collapse triggered prematurely at hour %d!" % (h + 1))
			return false
	# At hour 72: must trigger collapse
	var anarchy_collapse = vm_anarchy.tick_hourly(24, 0, 0, 0.0, 10.0, 1, true, 5)
	if anarchy_collapse["status"] != "collapse":
		print("  [FAIL] Anarchy collapse failed to trigger at hour 72!")
		return false
	if not anarchy_collapse["reason"].contains("Vô chính phủ"):
		print("  [FAIL] Anarchy collapse reason incorrect: %s" % anarchy_collapse["reason"])
		return false
	print("  [PASS] Prolonged Anarchy collapse triggered at 72 hours: %s" % anarchy_collapse["reason"])
	
	# Verify collapse summary report contains required metrics
	var collapse_rep: Dictionary = anarchy_collapse["report"]
	if collapse_rep["outcome"] != "COLLAPSE":
		print("  [FAIL] Expected outcome COLLAPSE, got %s" % collapse_rep["outcome"])
		return false
	if collapse_rep["primary_cause"] != vm_anarchy.primary_collapse_reason:
		print("  [FAIL] Primary cause mismatch!")
		return false
	print("  [PASS] Collapse summary report validated.")
	print("  [PASS] TC-7.3 PASSED.\n")
	return true
