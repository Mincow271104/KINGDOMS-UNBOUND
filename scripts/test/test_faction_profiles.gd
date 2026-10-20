extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — Package 1Q: Faction Strategic Profiles & Existence Status
## Validates authoritative data fields for factions per GDD §10.1 & §10.5:
## - TC-FPROF.1: Initialization (default mappings for initial factions)
## - TC-FPROF.2: Stable IDs & Vietnamese label mappings
## - TC-FPROF.3: Ascension integration (neutral tribe evolving to emerging_power mutates goal to consolidate_power)
## - TC-FPROF.4: Save serialization contains strategic_goal and existence_status
## - TC-FPROF.5: Save/Load roundtrip preserves exact profiles
## - TC-FPROF.6: Legacy save compatibility (missing fields load with documented fallbacks)
## - TC-FPROF.7: Invalid data safety (fail-closed validation and mutation prevention)
## - TC-FPROF.8: HUD rendering & refresh (Vietnamese labels displayed, refreshed upon profile changes)
## - TC-FPROF.9: Load idempotency (repeated loads do not duplicate factions, drift opinions, or re-emit signals)

const FactionManagerScript = preload("res://scripts/factions/faction_manager.gd")
const FactionDataScript = preload("res://scripts/factions/faction_data.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")
const HUDScene: PackedScene = preload("res://scenes/ui/hud.tscn")

var frame_count: int = 0
var world_instance: Node = null
var failures: int = 0

func _init() -> void:
	print("\n========================================================")
	print("  STARTING PACKAGE 1Q FACTION STRATEGIC PROFILES TESTS")
	print("========================================================\n")
	world_instance = WorldViewScene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count == 3:
		_run_all_tests()
		print("\n--------------------------------------------------------")
		if failures == 0:
			print("  ALL PACKAGE 1Q FACTION PROFILE TESTS PASSED! (Exit Code 0)")
			print("--------------------------------------------------------\n")
			quit(0)
			return true
		else:
			printerr("  PACKAGE 1Q FACTION PROFILE TESTS FAILED WITH %d FAILURES! (Exit Code 1)" % failures)
			print("--------------------------------------------------------\n")
			quit(1)
			return true
	return false

func _assert_true(cond: bool, test_name: String, msg: String = "") -> void:
	if not cond:
		failures += 1
		printerr("  ❌ FAIL [%s]: Expected true. %s" % [test_name, msg])
	else:
		print("  ✅ PASS [%s]%s" % [test_name, (" - " + msg) if msg != "" else ""])

func _assert_false(cond: bool, test_name: String, msg: String = "") -> void:
	if cond:
		failures += 1
		printerr("  ❌ FAIL [%s]: Expected false. %s" % [test_name, msg])
	else:
		print("  ✅ PASS [%s]%s" % [test_name, (" - " + msg) if msg != "" else ""])

func _assert_eq(actual: Variant, expected: Variant, test_name: String, msg: String = "") -> void:
	if actual != expected:
		failures += 1
		printerr("  ❌ FAIL [%s]: Expected %s, got %s. %s" % [test_name, str(expected), str(actual), msg])
	else:
		print("  ✅ PASS [%s]: %s == %s%s" % [test_name, str(actual), str(expected), (" - " + msg) if msg != "" else ""])

func _assert_approx(actual: float, expected: float, test_name: String, tol: float = 0.001) -> void:
	if abs(actual - expected) > tol:
		failures += 1
		printerr("  ❌ FAIL [%s]: Expected approx %f, got %f (tol %f)" % [test_name, expected, actual, tol])
	else:
		print("  ✅ PASS [%s]: Approx %f == %f" % [test_name, actual, expected])

func _run_all_tests() -> void:
	test_tc_fprof_1_initialization()
	test_tc_fprof_2_stable_ids_and_labels()
	test_tc_fprof_3_ascension_integration()
	test_tc_fprof_4_save_serialization()
	test_tc_fprof_5_save_load_roundtrip()
	test_tc_fprof_6_legacy_save_compatibility()
	test_tc_fprof_7_invalid_data_safety()
	test_tc_fprof_8_hud_rendering()
	test_tc_fprof_9_load_idempotency()

# -----------------------------------------------------------------------------
# TC-FPROF.1: Initialization & Default Profile Mapping
# -----------------------------------------------------------------------------
func test_tc_fprof_1_initialization() -> void:
	print("\n--- TC-FPROF.1: Initialization ---")
	var fm = FactionManagerScript.new()

	var rival_mil: FactionData = fm.get_faction("rival_military")
	var rival_merch: FactionData = fm.get_faction("rival_merchant")
	var neutral_tribe: FactionData = fm.get_faction("neutral_tribe")

	_assert_true(rival_mil != null, "TC-FPROF.1-MIL-EXISTS", "rival_military exists")
	_assert_eq(rival_mil.strategic_goal, FactionDataScript.GOAL_MILITARY_EXPANSION, "TC-FPROF.1-MIL-GOAL", "rival_military has military_expansion goal")
	_assert_eq(rival_mil.existence_status, FactionDataScript.STATUS_ACTIVE, "TC-FPROF.1-MIL-STATUS", "rival_military is active")

	_assert_true(rival_merch != null, "TC-FPROF.1-MERCH-EXISTS", "rival_merchant exists")
	_assert_eq(rival_merch.strategic_goal, FactionDataScript.GOAL_TRADE_DOMINANCE, "TC-FPROF.1-MERCH-GOAL", "rival_merchant has trade_dominance goal")
	_assert_eq(rival_merch.existence_status, FactionDataScript.STATUS_ACTIVE, "TC-FPROF.1-MERCH-STATUS", "rival_merchant is active")

	_assert_true(neutral_tribe != null, "TC-FPROF.1-TRIBE-EXISTS", "neutral_tribe exists")
	_assert_eq(neutral_tribe.strategic_goal, FactionDataScript.GOAL_COMMUNITY_GROWTH, "TC-FPROF.1-TRIBE-GOAL", "neutral_tribe has community_growth goal")
	_assert_eq(neutral_tribe.existence_status, FactionDataScript.STATUS_ACTIVE, "TC-FPROF.1-TRIBE-STATUS", "neutral_tribe is active")

# -----------------------------------------------------------------------------
# TC-FPROF.2: Stable IDs & Vietnamese Localized Labels
# -----------------------------------------------------------------------------
func test_tc_fprof_2_stable_ids_and_labels() -> void:
	print("\n--- TC-FPROF.2: Stable IDs & Localized Labels ---")
	# Stable ID checks
	_assert_eq(FactionDataScript.GOAL_MILITARY_EXPANSION, "military_expansion", "TC-FPROF.2-ID-MIL", "Stable military_expansion ID")
	_assert_eq(FactionDataScript.GOAL_TRADE_DOMINANCE, "trade_dominance", "TC-FPROF.2-ID-TRADE", "Stable trade_dominance ID")
	_assert_eq(FactionDataScript.GOAL_COMMUNITY_GROWTH, "community_growth", "TC-FPROF.2-ID-GROWTH", "Stable community_growth ID")
	_assert_eq(FactionDataScript.GOAL_CONSOLIDATE_POWER, "consolidate_power", "TC-FPROF.2-ID-CONSOLIDATE", "Stable consolidate_power ID")

	_assert_eq(FactionDataScript.STATUS_ACTIVE, "active", "TC-FPROF.2-ID-ACTIVE", "Stable active status ID")
	_assert_eq(FactionDataScript.STATUS_IN_EXILE, "in_exile", "TC-FPROF.2-ID-EXILE", "Stable in_exile status ID")
	_assert_eq(FactionDataScript.STATUS_ELIMINATED, "eliminated", "TC-FPROF.2-ID-ELIM", "Stable eliminated status ID")

	# Vietnamese label mappings
	_assert_eq(FactionDataScript.get_strategic_goal_label(FactionDataScript.GOAL_MILITARY_EXPANSION), "Mở rộng quân sự", "TC-FPROF.2-LABEL-MIL", "Label for military_expansion")
	_assert_eq(FactionDataScript.get_strategic_goal_label(FactionDataScript.GOAL_TRADE_DOMINANCE), "Phát triển thương mại", "TC-FPROF.2-LABEL-TRADE", "Label for trade_dominance")
	_assert_eq(FactionDataScript.get_strategic_goal_label(FactionDataScript.GOAL_COMMUNITY_GROWTH), "Phát triển cộng đồng", "TC-FPROF.2-LABEL-GROWTH", "Label for community_growth")
	_assert_eq(FactionDataScript.get_strategic_goal_label(FactionDataScript.GOAL_CONSOLIDATE_POWER), "Củng cố thế lực", "TC-FPROF.2-LABEL-CONSOLIDATE", "Label for consolidate_power")
	_assert_eq(FactionDataScript.get_strategic_goal_label("unknown_goal"), "Không xác định", "TC-FPROF.2-LABEL-UNKNOWN-GOAL", "Fallback for unknown goal")

	_assert_eq(FactionDataScript.get_existence_status_label(FactionDataScript.STATUS_ACTIVE), "Hoạt động", "TC-FPROF.2-LABEL-ACTIVE", "Label for active status")
	_assert_eq(FactionDataScript.get_existence_status_label(FactionDataScript.STATUS_IN_EXILE), "Lưu vong", "TC-FPROF.2-LABEL-EXILE", "Label for in_exile status")
	_assert_eq(FactionDataScript.get_existence_status_label(FactionDataScript.STATUS_ELIMINATED), "Bị loại bỏ", "TC-FPROF.2-LABEL-ELIM", "Label for eliminated status")
	_assert_eq(FactionDataScript.get_existence_status_label("unknown_status"), "Không xác định", "TC-FPROF.2-LABEL-UNKNOWN-STATUS", "Fallback for unknown status")

	# Instance helper verification
	var custom_fac := FactionDataScript.new("test_fac", "Thế Lực Thử Nghiệm", "neutral_tribe")
	_assert_eq(custom_fac.get_strategic_goal_name(), "Phát triển cộng đồng", "TC-FPROF.2-INST-GOAL", "Instance helper gets goal label")
	_assert_eq(custom_fac.get_existence_status_name(), "Hoạt động", "TC-FPROF.2-INST-STATUS", "Instance helper gets status label")

# -----------------------------------------------------------------------------
# TC-FPROF.3: Ascension Integration & Strategic Goal Transition
# -----------------------------------------------------------------------------
func test_tc_fprof_3_ascension_integration() -> void:
	print("\n--- TC-FPROF.3: Ascension Integration ---")
	var fm = FactionManagerScript.new()
	var tribe: FactionData = fm.get_faction("neutral_tribe")

	# Setup prerequisites for ascension
	tribe.population = 44 # Will become 45 on daily tick
	tribe.resources = {EconomyConfigScript.RES_WOOD: 80, EconomyConfigScript.RES_HERBS: 40}
	tribe.stability = 65.0

	_assert_eq(tribe.strategic_goal, FactionDataScript.GOAL_COMMUNITY_GROWTH, "TC-FPROF.3-PRE-GOAL", "Pre-ascension goal is community_growth")
	_assert_eq(tribe.existence_status, FactionDataScript.STATUS_ACTIVE, "TC-FPROF.3-PRE-STATUS", "Pre-ascension status is active")

	var emissions: Array = []
	var on_ascended := func(fac_id: String, new_name: String):
		emissions.append({"id": fac_id, "name": new_name})
	fm.emerging_faction_ascended.connect(on_ascended)

	# Trigger ascension on Day 10
	fm.update_daily_simulation(10)

	_assert_eq(emissions.size(), 1, "TC-FPROF.3-SIG-ONCE", "Ascension signal emitted exactly once")
	_assert_eq(tribe.type, FactionManagerScript.ASCENSION_NEW_TYPE, "TC-FPROF.3-TYPE", "Type changed to emerging_power")
	_assert_eq(tribe.name, FactionManagerScript.ASCENSION_NEW_NAME, "TC-FPROF.3-NAME", "Name changed to Liên Minh Rừng Thiêng")
	_assert_eq(tribe.strategic_goal, FactionDataScript.GOAL_CONSOLIDATE_POWER, "TC-FPROF.3-POST-GOAL", "Strategic goal changed to consolidate_power")
	_assert_eq(tribe.existence_status, FactionDataScript.STATUS_ACTIVE, "TC-FPROF.3-POST-STATUS", "Existence status remains active")

	# Subsequent simulation tick: goal remains consolidate_power and signal is not re-emitted
	fm.update_daily_simulation(11)
	_assert_eq(emissions.size(), 1, "TC-FPROF.3-NO-REEMIT", "Signal never re-emitted on subsequent day")
	_assert_eq(tribe.strategic_goal, FactionDataScript.GOAL_CONSOLIDATE_POWER, "TC-FPROF.3-GOAL-STABLE", "Goal remains consolidate_power")

	if fm.emerging_faction_ascended.is_connected(on_ascended):
		fm.emerging_faction_ascended.disconnect(on_ascended)

# -----------------------------------------------------------------------------
# TC-FPROF.4: Save Serialization of Strategic Profiles
# -----------------------------------------------------------------------------
func test_tc_fprof_4_save_serialization() -> void:
	print("\n--- TC-FPROF.4: Save Serialization ---")
	var state: Dictionary = SaveManagerScript.serialize_world_state(world_instance)

	_assert_true(state.has("factions"), "TC-FPROF.4-HAS-FACTIONS", "Serialized state contains factions section")
	var facs_dict: Dictionary = state.get("factions", {}).get("factions", {})
	_assert_true(not facs_dict.is_empty(), "TC-FPROF.4-FACTIONS-NOT-EMPTY", "factions dictionary not empty")

	var fm: FactionManager = world_instance.get("faction_mgr")
	for fid in ["rival_military", "rival_merchant", "neutral_tribe"]:
		_assert_true(facs_dict.has(fid), "TC-FPROF.4-HAS-" + fid.to_upper(), "Serialized state has " + fid)
		var f_data: Dictionary = facs_dict[fid]
		var live_fac: FactionData = fm.get_faction(fid)
		_assert_true(f_data.has("strategic_goal"), "TC-FPROF.4-" + fid.to_upper() + "-HAS-GOAL", fid + " serialized with strategic_goal")
		_assert_true(f_data.has("existence_status"), "TC-FPROF.4-" + fid.to_upper() + "-HAS-STATUS", fid + " serialized with existence_status")
		_assert_eq(f_data.get("strategic_goal"), live_fac.strategic_goal, "TC-FPROF.4-" + fid.to_upper() + "-GOAL-MATCH", fid + " goal matches live object")
		_assert_eq(f_data.get("existence_status"), live_fac.existence_status, "TC-FPROF.4-" + fid.to_upper() + "-STATUS-MATCH", fid + " status matches live object")

# -----------------------------------------------------------------------------
# TC-FPROF.5: Save/Load Roundtrip Preserves Exact Profiles
# -----------------------------------------------------------------------------
func test_tc_fprof_5_save_load_roundtrip() -> void:
	print("\n--- TC-FPROF.5: Save/Load Roundtrip ---")
	var fm: FactionManager = world_instance.get("faction_mgr")

	# Set custom profile values on live factions
	var tribe: FactionData = fm.get_faction("neutral_tribe")
	tribe.type = FactionManagerScript.ASCENSION_NEW_TYPE
	tribe.name = FactionManagerScript.ASCENSION_NEW_NAME
	tribe.strategic_goal = FactionDataScript.GOAL_CONSOLIDATE_POWER
	tribe.existence_status = FactionDataScript.STATUS_ACTIVE

	var rival_mil: FactionData = fm.get_faction("rival_military")
	rival_mil.existence_status = FactionDataScript.STATUS_IN_EXILE

	# Save world state
	var saved_data: Dictionary = SaveManagerScript.serialize_world_state(world_instance)

	# Mutate live world state to confirm restoration
	tribe.strategic_goal = FactionDataScript.GOAL_COMMUNITY_GROWTH
	rival_mil.existence_status = FactionDataScript.STATUS_ACTIVE

	# Apply loaded state to world
	var apply_res: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, saved_data)
	_assert_true(apply_res.get("success", false), "TC-FPROF.5-APPLY-SUCCESS", "apply_loaded_state_to_world succeeded")

	# Verify restored profiles
	var restored_tribe: FactionData = fm.get_faction("neutral_tribe")
	_assert_eq(restored_tribe.strategic_goal, FactionDataScript.GOAL_CONSOLIDATE_POWER, "TC-FPROF.5-REST-TRIBE-GOAL", "Restored tribe retains consolidate_power")
	_assert_eq(restored_tribe.existence_status, FactionDataScript.STATUS_ACTIVE, "TC-FPROF.5-REST-TRIBE-STATUS", "Restored tribe retains active status")

	var restored_mil: FactionData = fm.get_faction("rival_military")
	_assert_eq(restored_mil.strategic_goal, FactionDataScript.GOAL_MILITARY_EXPANSION, "TC-FPROF.5-REST-MIL-GOAL", "Restored military retains military_expansion")
	_assert_eq(restored_mil.existence_status, FactionDataScript.STATUS_IN_EXILE, "TC-FPROF.5-REST-MIL-STATUS", "Restored military retains in_exile status")

	# Reset exile state for subsequent tests
	restored_mil.existence_status = FactionDataScript.STATUS_ACTIVE

# -----------------------------------------------------------------------------
# TC-FPROF.6: Legacy Save Compatibility (Missing Fields Default Safely)
# -----------------------------------------------------------------------------
func test_tc_fprof_6_legacy_save_compatibility() -> void:
	print("\n--- TC-FPROF.6: Legacy Save Compatibility ---")
	var fm: FactionManager = world_instance.get("faction_mgr")
	var saved_data: Dictionary = SaveManagerScript.serialize_world_state(world_instance)

	# Strip strategic_goal and existence_status from all factions in saved data (mimicking pre-1Q save)
	var facs_map: Dictionary = saved_data.get("factions", {}).get("factions", {})
	for fid in facs_map:
		var f_dict: Dictionary = facs_map[fid]
		f_dict.erase("strategic_goal")
		f_dict.erase("existence_status")

	# Mark neutral_tribe as ascended emerging_power in legacy save
	facs_map["neutral_tribe"]["type"] = "emerging_power"

	# Schema validator must pass on legacy save
	var val_res: Dictionary = SaveManagerScript.validate_save_data(saved_data)
	_assert_true(val_res.get("valid", false), "TC-FPROF.6-SCHEMA-VALID", "Legacy save passes schema validation")

	# Apply legacy save
	var apply_res: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, saved_data)
	_assert_true(apply_res.get("success", false), "TC-FPROF.6-APPLY-SUCCESS", "Legacy save restores successfully")

	# Verify fallback profiles
	var mil: FactionData = fm.get_faction("rival_military")
	_assert_eq(mil.strategic_goal, FactionDataScript.GOAL_MILITARY_EXPANSION, "TC-FPROF.6-MIL-DEFAULT-GOAL", "Legacy rival_military defaulted to military_expansion")
	_assert_eq(mil.existence_status, FactionDataScript.STATUS_ACTIVE, "TC-FPROF.6-MIL-DEFAULT-STATUS", "Legacy rival_military defaulted to active")

	var merch: FactionData = fm.get_faction("rival_merchant")
	_assert_eq(merch.strategic_goal, FactionDataScript.GOAL_TRADE_DOMINANCE, "TC-FPROF.6-MERCH-DEFAULT-GOAL", "Legacy rival_merchant defaulted to trade_dominance")
	_assert_eq(merch.existence_status, FactionDataScript.STATUS_ACTIVE, "TC-FPROF.6-MERCH-DEFAULT-STATUS", "Legacy rival_merchant defaulted to active")

	var tribe: FactionData = fm.get_faction("neutral_tribe")
	_assert_eq(tribe.strategic_goal, FactionDataScript.GOAL_CONSOLIDATE_POWER, "TC-FPROF.6-ASCENDED-DEFAULT-GOAL", "Legacy emerging_power defaulted to consolidate_power")
	_assert_eq(tribe.existence_status, FactionDataScript.STATUS_ACTIVE, "TC-FPROF.6-ASCENDED-DEFAULT-STATUS", "Legacy emerging_power defaulted to active")

# -----------------------------------------------------------------------------
# TC-FPROF.7: Invalid Data Safety (Fail-Closed)
# -----------------------------------------------------------------------------
func test_tc_fprof_7_invalid_data_safety() -> void:
	print("\n--- TC-FPROF.7: Invalid Data Safety ---")
	var fm: FactionManager = world_instance.get("faction_mgr")

	# 1. Invalid strategic_goal in save data
	var invalid_goal_save: Dictionary = SaveManagerScript.serialize_world_state(world_instance)
	invalid_goal_save["factions"]["factions"]["rival_military"]["strategic_goal"] = "invade_the_galaxy"

	var val_goal: Dictionary = SaveManagerScript.validate_save_data(invalid_goal_save)
	_assert_false(val_goal.get("valid", true), "TC-FPROF.7-INVALID-GOAL-REJECTED", "Invalid strategic_goal rejected by schema validator")
	_assert_true(val_goal.get("error", "").contains("strategic_goal"), "TC-FPROF.7-GOAL-ERR-MSG", "Error message identifies strategic_goal issue")

	var apply_goal_res: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, invalid_goal_save)
	_assert_false(apply_goal_res.get("success", true), "TC-FPROF.7-APPLY-REJECTED-GOAL", "apply_loaded_state_to_world fails-closed on invalid goal")

	# 2. Invalid existence_status in save data
	var invalid_status_save: Dictionary = SaveManagerScript.serialize_world_state(world_instance)
	invalid_status_save["factions"]["factions"]["rival_merchant"]["existence_status"] = "ghost_realm"

	var val_status: Dictionary = SaveManagerScript.validate_save_data(invalid_status_save)
	_assert_false(val_status.get("valid", true), "TC-FPROF.7-INVALID-STATUS-REJECTED", "Invalid existence_status rejected by schema validator")
	_assert_true(val_status.get("error", "").contains("existence_status"), "TC-FPROF.7-STATUS-ERR-MSG", "Error message identifies existence_status issue")

	var apply_status_res: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, invalid_status_save)
	_assert_false(apply_status_res.get("success", true), "TC-FPROF.7-APPLY-REJECTED-STATUS", "apply_loaded_state_to_world fails-closed on invalid status")

	# 3. Code-level setter safety
	var test_fac := FactionDataScript.new("test_guard", "Bảo Vệ", "neutral_tribe")
	var initial_goal: String = test_fac.strategic_goal
	var set_goal_ok: bool = test_fac.set_strategic_goal("completely_invalid_goal")
	_assert_false(set_goal_ok, "TC-FPROF.7-SET-GOAL-FALSE", "set_strategic_goal returns false on invalid value")
	_assert_eq(test_fac.strategic_goal, initial_goal, "TC-FPROF.7-SET-GOAL-UNCHANGED", "strategic_goal untouched after invalid set")

	var initial_status: String = test_fac.existence_status
	var set_status_ok: bool = test_fac.set_existence_status("completely_invalid_status")
	_assert_false(set_status_ok, "TC-FPROF.7-SET-STATUS-FALSE", "set_existence_status returns false on invalid value")
	_assert_eq(test_fac.existence_status, initial_status, "TC-FPROF.7-SET-STATUS-UNCHANGED", "existence_status untouched after invalid set")

# -----------------------------------------------------------------------------
# TC-FPROF.8: HUD Rendering & Dynamic Refresh
# -----------------------------------------------------------------------------
func _find_card_text(factions_vbox: VBoxContainer, expected_text: String) -> bool:
	if factions_vbox == null:
		return false
	for child in factions_vbox.get_children():
		if child.is_queued_for_deletion():
			continue
		for sub in child.get_children():
			if sub is VBoxContainer:
				for elem in sub.get_children():
					if elem is Label and elem.text.contains(expected_text):
						return true
	return false

func test_tc_fprof_8_hud_rendering() -> void:
	print("\n--- TC-FPROF.8: HUD Rendering & Refresh ---")
	var hud = HUDScene.instantiate()
	root.add_child(hud)

	var fm = FactionManagerScript.new()
	hud.set_faction_manager(fm, world_instance)
	hud.call("_refresh_diplomacy_ui")

	# Assert that Vietnamese labels for goals and statuses are present on cards
	_assert_true(_find_card_text(hud.factions_list_vbox, "Mở rộng quân sự"), "TC-FPROF.8-RENDER-MIL-GOAL", "HUD card displays 'Mở rộng quân sự'")
	_assert_true(_find_card_text(hud.factions_list_vbox, "Phát triển thương mại"), "TC-FPROF.8-RENDER-MERCH-GOAL", "HUD card displays 'Phát triển thương mại'")
	_assert_true(_find_card_text(hud.factions_list_vbox, "Phát triển cộng đồng"), "TC-FPROF.8-RENDER-TRIBE-GOAL", "HUD card displays 'Phát triển cộng đồng'")
	_assert_true(_find_card_text(hud.factions_list_vbox, "Hoạt động"), "TC-FPROF.8-RENDER-STATUS", "HUD cards display 'Hoạt động'")

	# Confirm raw internal IDs are NOT rendered
	_assert_false(_find_card_text(hud.factions_list_vbox, "military_expansion"), "TC-FPROF.8-NO-RAW-MIL", "No raw 'military_expansion' in HUD")
	_assert_false(_find_card_text(hud.factions_list_vbox, "trade_dominance"), "TC-FPROF.8-NO-RAW-TRADE", "No raw 'trade_dominance' in HUD")
	_assert_false(_find_card_text(hud.factions_list_vbox, "community_growth"), "TC-FPROF.8-NO-RAW-GROWTH", "No raw 'community_growth' in HUD")

	# Trigger ascension of neutral tribe
	var tribe: FactionData = fm.get_faction("neutral_tribe")
	tribe.population = 44
	tribe.resources = {EconomyConfigScript.RES_WOOD: 100, EconomyConfigScript.RES_HERBS: 50}
	tribe.stability = 70.0
	fm.update_daily_simulation(10)

	# Assert that refreshed card now displays 'Củng cố thế lực'
	_assert_true(_find_card_text(hud.factions_list_vbox, "Củng cố thế lực"), "TC-FPROF.8-RENDER-ASCENDED-GOAL", "HUD card displays 'Củng cố thế lực' after ascension")
	_assert_false(_find_card_text(hud.factions_list_vbox, "consolidate_power"), "TC-FPROF.8-NO-RAW-CONSOLIDATE", "No raw 'consolidate_power' in HUD")

	hud.queue_free()

# -----------------------------------------------------------------------------
# TC-FPROF.9: Load Idempotency & Repeat Application
# -----------------------------------------------------------------------------
func test_tc_fprof_9_load_idempotency() -> void:
	print("\n--- TC-FPROF.9: Load Idempotency ---")
	var fm: FactionManager = world_instance.get("faction_mgr")
	var saved_data: Dictionary = SaveManagerScript.serialize_world_state(world_instance)

	var emissions: Array = []
	var on_ascended := func(fac_id: String, new_name: String):
		emissions.append({"id": fac_id, "name": new_name})
	fm.emerging_faction_ascended.connect(on_ascended)

	# First load
	var res1: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, saved_data)
	_assert_true(res1.get("success", false), "TC-FPROF.9-LOAD1-SUCCESS", "First load application succeeded")
	_assert_eq(emissions.size(), 0, "TC-FPROF.9-LOAD1-NO-SIGNAL", "Zero ascension signals emitted on first load")
	_assert_eq(fm.get_all_factions().size(), 3, "TC-FPROF.9-LOAD1-FAC-COUNT", "Faction count remains exactly 3")

	# Simulation tick on loaded world
	fm.update_daily_simulation(11)
	_assert_eq(emissions.size(), 0, "TC-FPROF.9-TICK-NO-SIGNAL", "Zero signals emitted on subsequent simulation tick")

	# Second load (double-load idempotency)
	var res2: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, saved_data)
	_assert_true(res2.get("success", false), "TC-FPROF.9-LOAD2-SUCCESS", "Second load application succeeded")
	_assert_eq(emissions.size(), 0, "TC-FPROF.9-LOAD2-NO-SIGNAL", "Zero ascension signals emitted on second load")
	_assert_eq(fm.get_all_factions().size(), 3, "TC-FPROF.9-LOAD2-FAC-COUNT", "Faction count remains exactly 3 after double load")

	# Verify faction attributes preserved identically
	var mil: FactionData = fm.get_faction("rival_military")
	_assert_eq(mil.strategic_goal, FactionDataScript.GOAL_MILITARY_EXPANSION, "TC-FPROF.9-MIL-GOAL", "Military goal intact after double-load")
	_assert_eq(mil.existence_status, FactionDataScript.STATUS_ACTIVE, "TC-FPROF.9-MIL-STATUS", "Military status intact after double-load")

	if fm.emerging_faction_ascended.is_connected(on_ascended):
		fm.emerging_faction_ascended.disconnect(on_ascended)
