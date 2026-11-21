extends SceneTree
## Test Suite: Package 1J — Settlement Battle & Fortification Integration
## Validates TC-BF.1 through TC-BF.12:
## Authoritative fortification derivation, boundary thresholds, deduplication,
## state filtering, fail-closed handling, caller dictionary immutability,
## deterministic outcomes, score multiplier reporting, and backward compatibility.

const BattleResolverScript = preload("res://scripts/combat/battle_resolver.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")

var failures: int = 0

func _init() -> void:
	print("\n========================================================")
	print("  TEST SUITE: Package 1J — Settlement Battle & Fortification")
	print("========================================================\n")

	test_tc_bf_1_zero_palisades()
	test_tc_bf_2_single_palisade()
	test_tc_bf_3_threshold_boundaries()
	test_tc_bf_4_duplicate_cells_deduplication()
	test_tc_bf_5_non_active_palisades_filtering()
	test_tc_bf_6_caller_fortification_override()
	test_tc_bf_7_attacker_score_independence()
	test_tc_bf_8_caller_dictionary_immutability()
	test_tc_bf_9_determinism()
	test_tc_bf_10_combat_score_formula_verification()
	test_tc_bf_11_fail_closed_invalid_world_data()
	test_tc_bf_12_backward_compatibility_resolve_battle()

	print("\n--------------------------------------------------------")
	if failures == 0:
		print("  ALL PACKAGE 1J BATTLE FORTIFICATION TESTS PASSED! (Exit Code 0)")
		print("--------------------------------------------------------\n")
		quit(0)
	else:
		printerr("  PACKAGE 1J BATTLE FORTIFICATION TESTS FAILED with %d failures! (Exit Code 1)" % failures)
		print("--------------------------------------------------------\n")
		quit(1)

# -----------------------------------------------------------------------------
# TC-BF.1: Settlement with 0 palisades resolves at fortification level 0
# (bonus 1.0, has_settlement_context true)
# -----------------------------------------------------------------------------
func test_tc_bf_1_zero_palisades() -> void:
	print("--- Running TC-BF.1: Zero Palisades Resolution ---")
	var world_data := WorldGeneratorScript.generate(1001)
	world_data.buildings.clear()

	var atk := {"troops": 20, "equipment_tier": 1, "morale": 70.0}
	var def := {"troops": 20, "equipment_tier": 1, "morale": 70.0}

	var report := BattleResolverScript.resolve_settlement_battle(atk, def, world_data, 12345)

	if not report.details.get("has_settlement_context", false):
		printerr("  [FAIL] TC-BF.1: has_settlement_context expected true, got false")
		failures += 1
	elif report.details.get("fortification_level", -1) != 0:
		printerr("  [FAIL] TC-BF.1: fortification_level expected 0, got %d" % report.details.get("fortification_level", -1))
		failures += 1
	elif not is_equal_approx(report.details.get("fortification_bonus", 0.0), 1.0):
		printerr("  [FAIL] TC-BF.1: fortification_bonus expected 1.0, got %f" % report.details.get("fortification_bonus", 0.0))
		failures += 1
	else:
		print("  [PASS] TC-BF.1: Zero palisades resolved at level 0, bonus 1.0, has_settlement_context true.")

# -----------------------------------------------------------------------------
# TC-BF.2: 1 active palisade produces level 1 (bonus 1.30)
# -----------------------------------------------------------------------------
func test_tc_bf_2_single_palisade() -> void:
	print("\n--- Running TC-BF.2: Single Active Palisade ---")
	var world_data := WorldGeneratorScript.generate(1002)
	world_data.buildings.clear()
	world_data.buildings.append({
		"id": "bld_palisade_1",
		"type": "palisade",
		"cell": Vector2i(10, 10),
		"state": "active"
	})

	var atk := {"troops": 20, "equipment_tier": 1, "morale": 70.0}
	var def := {"troops": 20, "equipment_tier": 1, "morale": 70.0}

	var report := BattleResolverScript.resolve_settlement_battle(atk, def, world_data, 12345)

	if not report.details.get("has_settlement_context", false):
		printerr("  [FAIL] TC-BF.2: has_settlement_context expected true")
		failures += 1
	elif report.details.get("fortification_level", -1) != 1:
		printerr("  [FAIL] TC-BF.2: fortification_level expected 1, got %d" % report.details.get("fortification_level", -1))
		failures += 1
	elif not is_equal_approx(report.details.get("fortification_bonus", 0.0), 1.30):
		printerr("  [FAIL] TC-BF.2: fortification_bonus expected 1.30, got %f" % report.details.get("fortification_bonus", 0.0))
		failures += 1
	else:
		print("  [PASS] TC-BF.2: 1 active palisade resolved at level 1, bonus 1.30.")

# -----------------------------------------------------------------------------
# TC-BF.3: Threshold boundaries: 4 (lvl 1), 5 (lvl 2), 9 (lvl 2), 10 (lvl 3), 15 (clamped lvl 3)
# -----------------------------------------------------------------------------
func test_tc_bf_3_threshold_boundaries() -> void:
	print("\n--- Running TC-BF.3: Fortification Threshold Boundaries ---")
	var test_cases := [
		{"count": 4, "expected_lvl": 1, "expected_bonus": 1.30},
		{"count": 5, "expected_lvl": 2, "expected_bonus": 1.60},
		{"count": 9, "expected_lvl": 2, "expected_bonus": 1.60},
		{"count": 10, "expected_lvl": 3, "expected_bonus": 1.90},
		{"count": 15, "expected_lvl": 3, "expected_bonus": 1.90}
	]

	for tc in test_cases:
		var world_data := WorldGeneratorScript.generate(2000 + tc["count"])
		world_data.buildings.clear()
		for i in range(tc["count"]):
			world_data.buildings.append({
				"id": "bld_palisade_%d" % i,
				"type": "palisade",
				"cell": Vector2i(10 + i, 10),
				"state": "active"
			})

		var atk := {"troops": 20, "equipment_tier": 1, "morale": 70.0}
		var def := {"troops": 20, "equipment_tier": 1, "morale": 70.0}

		var report := BattleResolverScript.resolve_settlement_battle(atk, def, world_data, 12345)
		var actual_lvl = report.details.get("fortification_level", -1)
		var actual_bonus = report.details.get("fortification_bonus", 0.0)

		if actual_lvl != tc["expected_lvl"]:
			printerr("  [FAIL] TC-BF.3: Count %d expected level %d, got %d" % [tc["count"], tc["expected_lvl"], actual_lvl])
			failures += 1
		elif not is_equal_approx(actual_bonus, tc["expected_bonus"]):
			printerr("  [FAIL] TC-BF.3: Count %d expected bonus %f, got %f" % [tc["count"], tc["expected_bonus"], actual_bonus])
			failures += 1
		else:
			print("  [PASS] TC-BF.3: %d palisades -> level %d (bonus %.2f)" % [tc["count"], actual_lvl, actual_bonus])

# -----------------------------------------------------------------------------
# TC-BF.4: Duplicate records at identical cell do not inflate fortification count
# -----------------------------------------------------------------------------
func test_tc_bf_4_duplicate_cells_deduplication() -> void:
	print("\n--- Running TC-BF.4: Duplicate Cell Deduplication ---")
	var world_data := WorldGeneratorScript.generate(1004)
	world_data.buildings.clear()

	# Add 6 records all sharing Vector2i(15, 15)
	for i in range(6):
		world_data.buildings.append({
			"id": "bld_palisade_dup_%d" % i,
			"type": "palisade",
			"cell": Vector2i(15, 15),
			"state": "active"
		})

	var atk := {"troops": 20, "equipment_tier": 1, "morale": 70.0}
	var def := {"troops": 20, "equipment_tier": 1, "morale": 70.0}

	var report := BattleResolverScript.resolve_settlement_battle(atk, def, world_data, 12345)
	var lvl = report.details.get("fortification_level", -1)

	if lvl != 1:
		printerr("  [FAIL] TC-BF.4: 6 duplicate records at same cell should yield level 1, got %d" % lvl)
		failures += 1
	else:
		print("  [PASS] TC-BF.4: 6 duplicate records correctly deduplicated to 1 unique cell (level 1).")

# -----------------------------------------------------------------------------
# TC-BF.5: Non-active palisades (under_construction, damaged, paused, destroyed)
# do not contribute to fortification level
# -----------------------------------------------------------------------------
func test_tc_bf_5_non_active_palisades_filtering() -> void:
	print("\n--- Running TC-BF.5: Non-Active Palisades Filtering ---")
	var world_data := WorldGeneratorScript.generate(1005)
	world_data.buildings.clear()

	# 1 active palisade
	world_data.buildings.append({
		"id": "pal_active",
		"type": "palisade",
		"cell": Vector2i(10, 10),
		"state": "active"
	})
	# Inactive / incomplete palisades
	world_data.buildings.append({
		"id": "pal_under_const",
		"type": "palisade",
		"cell": Vector2i(11, 10),
		"state": "under_construction"
	})
	world_data.buildings.append({
		"id": "pal_damaged",
		"type": "palisade",
		"cell": Vector2i(12, 10),
		"state": "damaged"
	})
	world_data.buildings.append({
		"id": "pal_paused",
		"type": "palisade",
		"cell": Vector2i(13, 10),
		"state": "paused"
	})
	world_data.buildings.append({
		"id": "pal_destroyed",
		"type": "palisade",
		"cell": Vector2i(14, 10),
		"state": "destroyed"
	})

	var atk := {"troops": 20, "equipment_tier": 1, "morale": 70.0}
	var def := {"troops": 20, "equipment_tier": 1, "morale": 70.0}

	var report := BattleResolverScript.resolve_settlement_battle(atk, def, world_data, 12345)
	var lvl = report.details.get("fortification_level", -1)

	if lvl != 1:
		printerr("  [FAIL] TC-BF.5: Non-active states should not count; expected level 1, got %d" % lvl)
		failures += 1
	else:
		print("  [PASS] TC-BF.5: Only active palisades counted; 4 non-active states ignored (level 1).")

# -----------------------------------------------------------------------------
# TC-BF.6: Pre-existing or omitted fortification_level in defender_force is overridden
# by authoritative calculation from defender_world_data
# -----------------------------------------------------------------------------
func test_tc_bf_6_caller_fortification_override() -> void:
	print("\n--- Running TC-BF.6: Authoritative Fortification Override ---")
	var world_data := WorldGeneratorScript.generate(1006)
	world_data.buildings.clear()

	var atk := {"troops": 20, "equipment_tier": 1, "morale": 70.0}

	# Scenario A: Caller passes fortification_level = 3, but settlement has 0 palisades
	var def_lying := {"troops": 20, "equipment_tier": 1, "morale": 70.0, "fortification_level": 3}
	var report_a := BattleResolverScript.resolve_settlement_battle(atk, def_lying, world_data, 12345)
	if report_a.details.get("fortification_level", -1) != 0:
		printerr("  [FAIL] TC-BF.6A: Unearned fortification_level=3 was NOT overridden to 0!")
		failures += 1
	else:
		print("  [PASS] TC-BF.6A: Fabricated fortification_level=3 overridden to 0 by WorldData.")

	# Scenario B: Caller omits fortification_level, but settlement has 10 active palisades
	for i in range(10):
		world_data.buildings.append({
			"id": "pal_%d" % i,
			"type": "palisade",
			"cell": Vector2i(20 + i, 20),
			"state": "active"
		})
	var def_omitted := {"troops": 20, "equipment_tier": 1, "morale": 70.0}
	var report_b := BattleResolverScript.resolve_settlement_battle(atk, def_omitted, world_data, 12345)
	if report_b.details.get("fortification_level", -1) != 3:
		printerr("  [FAIL] TC-BF.6B: Omitted fortification_level was NOT populated to level 3!")
		failures += 1
	else:
		print("  [PASS] TC-BF.6B: Omitted fortification_level correctly populated to level 3.")

# -----------------------------------------------------------------------------
# TC-BF.7: Attacker force never receives defender's fortification bonus
# (attacker score strictly independent of fortification)
# -----------------------------------------------------------------------------
func test_tc_bf_7_attacker_score_independence() -> void:
	print("\n--- Running TC-BF.7: Attacker Score Independence ---")
	var world_data_lvl0 := WorldGeneratorScript.generate(1007)
	world_data_lvl0.buildings.clear()

	var world_data_lvl3 := WorldGeneratorScript.generate(1008)
	world_data_lvl3.buildings.clear()
	for i in range(10):
		world_data_lvl3.buildings.append({
			"id": "pal_%d" % i,
			"type": "palisade",
			"cell": Vector2i(5 + i, 5),
			"state": "active"
		})

	var atk := {"troops": 30, "equipment_tier": 2, "morale": 80.0}
	var def := {"troops": 20, "equipment_tier": 1, "morale": 70.0}

	var report_lvl0 := BattleResolverScript.resolve_settlement_battle(atk, def, world_data_lvl0, 54321)
	var report_lvl3 := BattleResolverScript.resolve_settlement_battle(atk, def, world_data_lvl3, 54321)

	var atk_score_0 = report_lvl0.details.get("attacker_combat_score", 0.0)
	var atk_score_3 = report_lvl3.details.get("attacker_combat_score", 0.0)
	var def_score_0 = report_lvl0.details.get("defender_combat_score", 0.0)
	var def_score_3 = report_lvl3.details.get("defender_combat_score", 0.0)

	if not is_equal_approx(atk_score_0, atk_score_3):
		printerr("  [FAIL] TC-BF.7: Attacker score changed with fortification! lvl0: %f, lvl3: %f" % [atk_score_0, atk_score_3])
		failures += 1
	elif not (def_score_3 > def_score_0):
		printerr("  [FAIL] TC-BF.7: Defender score did not increase with level 3 fortification! lvl0: %f, lvl3: %f" % [def_score_0, def_score_3])
		failures += 1
	else:
		print("  [PASS] TC-BF.7: Attacker score strictly identical (%.2f == %.2f) across fortification levels." % [atk_score_0, atk_score_3])

# -----------------------------------------------------------------------------
# TC-BF.8: Caller dictionaries attacker_force and defender_force are not mutated
# -----------------------------------------------------------------------------
func test_tc_bf_8_caller_dictionary_immutability() -> void:
	print("\n--- Running TC-BF.8: Caller Dictionary Immutability ---")
	var world_data := WorldGeneratorScript.generate(1009)
	world_data.buildings.clear()
	world_data.buildings.append({
		"id": "pal_1",
		"type": "palisade",
		"cell": Vector2i(10, 10),
		"state": "active"
	})

	var atk_original: Dictionary = {
		"troops": 50,
		"equipment_tier": 3,
		"morale": 90.0,
		"custom_meta": "untouched"
	}
	var def_original: Dictionary = {
		"troops": 10,
		"equipment_tier": 1,
		"morale": 50.0,
		"fortification_level": 99,
		"resources": {"gold": 500, "food": 250}
	}

	var atk_copy: Dictionary = atk_original.duplicate(true)
	var def_copy: Dictionary = def_original.duplicate(true)

	var report := BattleResolverScript.resolve_settlement_battle(atk_copy, def_copy, world_data, 999)

	# Verify attacker plundered spoils to ensure plunder code path triggered
	if report.plunder_spoils.is_empty():
		printerr("  [FAIL] TC-BF.8: Attacker victory did not trigger plunder; test premise invalidated")
		failures += 1

	if atk_copy != atk_original:
		printerr("  [FAIL] TC-BF.8: Caller attacker_force was mutated! Original: %s, Current: %s" % [str(atk_original), str(atk_copy)])
		failures += 1
	elif def_copy != def_original:
		printerr("  [FAIL] TC-BF.8: Caller defender_force was mutated! Original: %s, Current: %s" % [str(def_original), str(def_copy)])
		failures += 1
	else:
		print("  [PASS] TC-BF.8: Zero mutation on caller dictionaries (including nested resources).")

# -----------------------------------------------------------------------------
# TC-BF.9: Identical input and seed produce 100% deterministic reports
# -----------------------------------------------------------------------------
func test_tc_bf_9_determinism() -> void:
	print("\n--- Running TC-BF.9: Resolution Determinism ---")
	var world_data := WorldGeneratorScript.generate(1010)
	world_data.buildings.clear()
	for i in range(5):
		world_data.buildings.append({
			"id": "pal_%d" % i,
			"type": "palisade",
			"cell": Vector2i(12 + i, 12),
			"state": "active"
		})

	var atk := {"troops": 25, "equipment_tier": 2, "morale": 75.0}
	var def := {"troops": 20, "equipment_tier": 2, "morale": 75.0}

	var report_a := BattleResolverScript.resolve_settlement_battle(atk, def, world_data, 77777)
	var report_b := BattleResolverScript.resolve_settlement_battle(atk, def, world_data, 77777)

	if report_a.victor != report_b.victor:
		printerr("  [FAIL] TC-BF.9: Victors diverge: %s vs %s" % [report_a.victor, report_b.victor])
		failures += 1
	elif report_a.attacker_casualties != report_b.attacker_casualties or report_a.defender_casualties != report_b.defender_casualties:
		printerr("  [FAIL] TC-BF.9: Casualties diverge!")
		failures += 1
	elif not is_equal_approx(report_a.details["attacker_combat_score"], report_b.details["attacker_combat_score"]):
		printerr("  [FAIL] TC-BF.9: Attacker combat score diverges!")
		failures += 1
	elif not is_equal_approx(report_a.details["defender_combat_score"], report_b.details["defender_combat_score"]):
		printerr("  [FAIL] TC-BF.9: Defender combat score diverges!")
		failures += 1
	elif report_a.details != report_b.details:
		printerr("  [FAIL] TC-BF.9: Details dictionaries diverge!")
		failures += 1
	else:
		print("  [PASS] TC-BF.9: Deterministic execution verified across duplicate runs.")

# -----------------------------------------------------------------------------
# TC-BF.10: Combat score details report the exact fortification multiplier actually used
# -----------------------------------------------------------------------------
func test_tc_bf_10_combat_score_formula_verification() -> void:
	print("\n--- Running TC-BF.10: Combat Score Formula Verification ---")
	var world_data := WorldGeneratorScript.generate(1011)
	world_data.buildings.clear()
	# 5 palisades -> level 2 -> def_fort_bonus = 1.0 + 2 * 0.30 = 1.60
	for i in range(5):
		world_data.buildings.append({
			"id": "pal_%d" % i,
			"type": "palisade",
			"cell": Vector2i(2 + i, 2),
			"state": "active"
		})

	var def_troops := 30
	var def_equip := 2
	var def_morale := 80.0
	var def_terrain := 1.20

	var atk := {"troops": 20, "equipment_tier": 1, "morale": 70.0}
	var def := {
		"troops": def_troops,
		"equipment_tier": def_equip,
		"morale": def_morale,
		"terrain_multiplier": def_terrain
	}

	var report := BattleResolverScript.resolve_settlement_battle(atk, def, world_data, 12345)

	var def_equip_bonus := 1.0 + float(def_equip - 1) * 0.25 # 1.25
	var def_morale_factor := clampf(def_morale / 100.0, 0.4, 1.2) # 0.80
	var expected_fort_bonus := 1.0 + 2.0 * 0.30 # 1.60
	var expected_def_score := float(def_troops) * def_equip_bonus * def_morale_factor * expected_fort_bonus * def_terrain

	var actual_fort_bonus = report.details.get("fortification_bonus", 0.0)
	var actual_def_score = report.details.get("defender_combat_score", 0.0)

	if not is_equal_approx(actual_fort_bonus, expected_fort_bonus):
		printerr("  [FAIL] TC-BF.10: fortification_bonus expected %f, got %f" % [expected_fort_bonus, actual_fort_bonus])
		failures += 1
	elif not is_equal_approx(actual_def_score, expected_def_score):
		printerr("  [FAIL] TC-BF.10: defender_combat_score expected %f, got %f" % [expected_def_score, actual_def_score])
		failures += 1
	else:
		print("  [PASS] TC-BF.10: Exact score formula matches report (Score: %.3f, Bonus: %.2f)." % [actual_def_score, actual_fort_bonus])

# -----------------------------------------------------------------------------
# TC-BF.11: Invalid or null defender_world_data fails closed
# (has_settlement_context == false, level 0, bonus 1.0)
# -----------------------------------------------------------------------------
func test_tc_bf_11_fail_closed_invalid_world_data() -> void:
	print("\n--- Running TC-BF.11: Fail-Closed Invalid WorldData ---")
	var atk := {"troops": 20, "equipment_tier": 1, "morale": 70.0}
	var def := {"troops": 20, "equipment_tier": 1, "morale": 70.0, "fortification_level": 3}

	# Case A: null defender_world_data
	var report_null := BattleResolverScript.resolve_settlement_battle(atk, def, null, 12345)
	if report_null.details.get("has_settlement_context", true):
		printerr("  [FAIL] TC-BF.11A: has_settlement_context expected false for null world_data")
		failures += 1
	elif report_null.details.get("fortification_level", -1) != 0:
		printerr("  [FAIL] TC-BF.11A: fortification_level expected 0 for null world_data, got %d" % report_null.details.get("fortification_level", -1))
		failures += 1
	elif not is_equal_approx(report_null.details.get("fortification_bonus", 0.0), 1.0):
		printerr("  [FAIL] TC-BF.11A: fortification_bonus expected 1.0 for null world_data")
		failures += 1
	else:
		print("  [PASS] TC-BF.11A: null world_data failed closed (lvl 0, bonus 1.0, has_context false).")

	# Case B: world_data with malformed / out-of-bounds palisade cells
	var malformed_data := WorldGeneratorScript.WorldData.new()
	malformed_data.buildings.append({
		"id": "pal_oob",
		"type": "palisade",
		"cell": Vector2i(-999, -999),
		"state": "active"
	})
	malformed_data.buildings.append({
		"id": "pal_missing_cell",
		"type": "palisade",
		"state": "active"
	})
	var report_malformed := BattleResolverScript.resolve_settlement_battle(atk, def, malformed_data, 12345)
	if not report_malformed.details.get("has_settlement_context", false):
		printerr("  [FAIL] TC-BF.11B: has_settlement_context expected true for valid world_data instance")
		failures += 1
	elif report_malformed.details.get("fortification_level", -1) != 0:
		printerr("  [FAIL] TC-BF.11B: fortification_level expected 0 for malformed/OOB palisades, got %d" % report_malformed.details.get("fortification_level", -1))
		failures += 1
	elif not is_equal_approx(report_malformed.details.get("fortification_bonus", 0.0), 1.0):
		printerr("  [FAIL] TC-BF.11B: fortification_bonus expected 1.0 for malformed/OOB palisades")
		failures += 1
	else:
		print("  [PASS] TC-BF.11B: malformed/OOB palisade entries rejected (lvl 0, bonus 1.0).")

# -----------------------------------------------------------------------------
# TC-BF.12: Existing direct resolve_battle() abstract calls remain fully compatible
# -----------------------------------------------------------------------------
func test_tc_bf_12_backward_compatibility_resolve_battle() -> void:
	print("\n--- Running TC-BF.12: Backward Compatibility resolve_battle() ---")
	var atk := {"troops": 30, "equipment_tier": 2, "morale": 80.0}
	var def := {"troops": 20, "equipment_tier": 1, "morale": 70.0, "fortification_level": 2}

	var report := BattleResolverScript.resolve_battle(atk, def, 12345)

	if report.details.get("has_settlement_context", true) != false:
		printerr("  [FAIL] TC-BF.12: direct resolve_battle() should have has_settlement_context=false")
		failures += 1
	elif report.details.get("fortification_level", -1) != 2:
		printerr("  [FAIL] TC-BF.12: direct resolve_battle() should preserve explicit fortification_level=2, got %d" % report.details.get("fortification_level", -1))
		failures += 1
	elif not is_equal_approx(report.details.get("fortification_bonus", 0.0), 1.60):
		printerr("  [FAIL] TC-BF.12: direct resolve_battle() fortification_bonus expected 1.60, got %f" % report.details.get("fortification_bonus", 0.0))
		failures += 1
	else:
		print("  [PASS] TC-BF.12: Direct resolve_battle() fully backward-compatible (preserves caller fort level 2, bonus 1.60, has_settlement_context false).")
