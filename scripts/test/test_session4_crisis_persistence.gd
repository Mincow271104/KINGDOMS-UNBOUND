extends SceneTree

## =============================================================================
## KINGDOMS UNBOUND — CONTROLLED DEFECT REPAIR PROGRAM
## SESSION 4 TEST SUITE: CRISIS MECHANICS & PERSISTENCE INTEGRITY
## Focus: MBL-CRS-01 (Drought Working-Citizen Fatigue Enum)
##        MBL-CRS-02 (Remote Army Interception Immunity & Defense Eligibility)
##        MBL-SAV-01 (CrisisManager Malformed Payload Type & Schema Validation)
##        MBL-SAV-02 (Legacy Crisis Payload & World Modifiers Persistence)
## =============================================================================

const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")
const CrisisManagerScript = preload("res://scripts/core/crisis_manager.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const CitizenControllerScript = preload("res://scripts/entities/citizen_controller.gd")
const PlayerArmyManagerScript = preload("res://scripts/military/player_army_manager.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")

var frame_count: int = 0
var world_instance: Node = null
var failures: int = 0
var checks_passed: int = 0

func _assert(condition: bool, message: String, detail: String = "") -> void:
	if condition:
		checks_passed += 1
		print("  [PASS] %s" % message)
	else:
		failures += 1
		var err_msg := "  [FAIL] %s" % message
		if not detail.is_empty():
			err_msg += " (%s)" % detail
		printerr(err_msg)

func _init() -> void:
	print("\n========================================================")
	print("  STARTING SESSION 4 CRISIS & PERSISTENCE TEST SUITE")
	print("========================================================\n")
	world_instance = WorldViewScene.instantiate()
	world_instance.world_seed = 12345
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count < 3:
		return false

	_run_all_tests()

	print("\n========================================================")
	print("  SESSION 4 TEST RESULTS SUMMARY")
	print("  Passed Assertions : %d" % checks_passed)
	print("  Failed Assertions : %d" % failures)
	if failures == 0:
		print("  ALL SESSION 4 ASSERTIONS PASSED! (Exit Code 0)")
		print("========================================================\n")
		if is_instance_valid(world_instance):
			world_instance.queue_free()
		quit(0)
	else:
		printerr("  SESSION 4 TEST SUITE FAILED WITH %d FAILURES (Exit Code 1)" % failures)
		print("========================================================\n")
		if is_instance_valid(world_instance):
			world_instance.queue_free()
		quit(1)
	return true

func _run_all_tests() -> void:
	_test_mbl_crs_01_drought_fatigue_enum()
	_test_mbl_crs_02_remote_army_interception_eligibility()
	_test_mbl_sav_01_payload_type_and_schema_validation()
	_test_mbl_sav_02_world_modifiers_persistence_and_isolation()

## -----------------------------------------------------------------------------
## GROUP 1: MBL-CRS-01 Drought Fatigue Enum Verification
## -----------------------------------------------------------------------------
func _test_mbl_crs_01_drought_fatigue_enum() -> void:
	print("--- Running Group 1: MBL-CRS-01 Drought Fatigue Enum ---")
	var cm := CrisisManagerScript.new(1111)
	cm.trigger_crisis(CrisisManagerScript.CRISIS_DROUGHT, true, 72.0)
	_assert(cm.is_crisis_active(), "CRS-01.1: Drought crisis active")

	# Test with real CitizenController instances
	var cit_working := CitizenControllerScript.new()
	cit_working.citizen_id = "cit_test_working"
	cit_working.fatigue = 20.0
	cit_working.health = 100.0
	cit_working.current_state = CitizenControllerScript.State.WORKING

	var cit_moving := CitizenControllerScript.new()
	cit_moving.citizen_id = "cit_test_moving"
	cit_moving.fatigue = 20.0
	cit_moving.health = 100.0
	cit_moving.current_state = CitizenControllerScript.State.MOVING_TO_JOB

	var cit_idle := CitizenControllerScript.new()
	cit_idle.citizen_id = "cit_test_idle"
	cit_idle.fatigue = 20.0
	cit_idle.health = 100.0
	cit_idle.current_state = CitizenControllerScript.State.IDLE

	var cit_resting := CitizenControllerScript.new()
	cit_resting.citizen_id = "cit_test_resting"
	cit_resting.fatigue = 20.0
	cit_resting.health = 100.0
	cit_resting.current_state = CitizenControllerScript.State.RESTING

	var cit_hauling := CitizenControllerScript.new()
	cit_hauling.citizen_id = "cit_test_hauling"
	cit_hauling.fatigue = 20.0
	cit_hauling.health = 100.0
	cit_hauling.current_state = CitizenControllerScript.State.HAULING

	var cit_guarding := CitizenControllerScript.new()
	cit_guarding.citizen_id = "cit_test_guarding"
	cit_guarding.fatigue = 20.0
	cit_guarding.health = 100.0
	cit_guarding.current_state = CitizenControllerScript.State.GUARDING

	var cit_seeking := CitizenControllerScript.new()
	cit_seeking.citizen_id = "cit_test_seeking"
	cit_seeking.fatigue = 20.0
	cit_seeking.health = 100.0
	cit_seeking.current_state = CitizenControllerScript.State.SEEKING_FOOD

	var citizen_list: Array = [
		cit_working, cit_moving, cit_idle, cit_resting, cit_hauling, cit_guarding, cit_seeking
	]

	# Execute 1 drought hour
	cm.tick_hourly(10, 1, "summer", null, null, citizen_list)

	# 1. Real CitizenController in State.WORKING receives exactly +0.5 fatigue
	_assert(is_equal_approx(cit_working.fatigue, 20.5), "CRS-01.2: WORKING citizen fatigue increased by exactly 0.5 (observed: %.2f)" % cit_working.fatigue)

	# 2. MOVING_TO_JOB (state 1) strictly does NOT receive drought working fatigue
	_assert(is_equal_approx(cit_moving.fatigue, 20.0), "CRS-01.3: MOVING_TO_JOB citizen fatigue untouched at 20.0 (observed: %.2f)" % cit_moving.fatigue)

	# 3. IDLE (state 0) strictly untouched
	_assert(is_equal_approx(cit_idle.fatigue, 20.0), "CRS-01.4: IDLE citizen fatigue untouched at 20.0 (observed: %.2f)" % cit_idle.fatigue)

	# 4. RESTING (state 4) strictly untouched
	_assert(is_equal_approx(cit_resting.fatigue, 20.0), "CRS-01.5: RESTING citizen fatigue untouched at 20.0 (observed: %.2f)" % cit_resting.fatigue)

	# 5. HAULING (state 5) strictly untouched
	_assert(is_equal_approx(cit_hauling.fatigue, 20.0), "CRS-01.6: HAULING citizen fatigue untouched at 20.0 (observed: %.2f)" % cit_hauling.fatigue)

	# 6. GUARDING (state 6) strictly untouched
	_assert(is_equal_approx(cit_guarding.fatigue, 20.0), "CRS-01.7: GUARDING citizen fatigue untouched at 20.0 (observed: %.2f)" % cit_guarding.fatigue)

	# 7. SEEKING_FOOD (state 3) strictly untouched
	_assert(is_equal_approx(cit_seeking.fatigue, 20.0), "CRS-01.8: SEEKING_FOOD citizen fatigue untouched at 20.0 (observed: %.2f)" % cit_seeking.fatigue)

	# 8. Fatigue cap at 100.0 enforced
	cit_working.fatigue = 99.8
	cm.tick_hourly(11, 1, "summer", null, null, [cit_working])
	_assert(is_equal_approx(cit_working.fatigue, 100.0), "CRS-01.9: WORKING citizen fatigue capped at exactly 100.0 (observed: %.2f)" % cit_working.fatigue)

	# Clean up citizen instances
	for c in citizen_list:
		if is_instance_valid(c):
			c.free()

func _clear_test_army(pam: Variant, tmm: Variant) -> void:
	if pam != null:
		pam.soldier_count = 0
		pam.garrisons.clear()
		pam.active_reinforcements.clear()
		pam.set("movement_state", PlayerArmyManagerScript.MovementState.GARRISONED)
		var rally: Vector2i = pam.call("get_rally_cell") if pam.has_method("get_rally_cell") else Vector2i(32, 33)
		pam.set("current_cell", rally)
		pam.set("destination_cell", rally)
		pam.current_path.clear()
	if tmm != null and tmm.has_method("clear_all_units"):
		tmm.call("clear_all_units")

func _setup_test_army(pam: Variant, tmm: Variant, count: int) -> void:
	_clear_test_army(pam, tmm)
	if pam != null:
		pam.soldier_count = count
		pam.set("movement_state", PlayerArmyManagerScript.MovementState.GARRISONED)
		var rally: Vector2i = pam.call("get_rally_cell") if pam.has_method("get_rally_cell") else Vector2i(32, 33)
		pam.set("current_cell", rally)
		pam.set("destination_cell", rally)
		pam.current_path.clear()
	if tmm != null and tmm.has_method("sync_with_player_army"):
		tmm.call("sync_with_player_army")

## -----------------------------------------------------------------------------
## GROUP 2: MBL-CRS-02 Remote Army Interception & Defense Eligibility
## -----------------------------------------------------------------------------
func _test_mbl_crs_02_remote_army_interception_eligibility() -> void:
	print("\n--- Running Group 2: MBL-CRS-02 Settlement Defense Eligibility ---")
	var pam: Variant = world_instance.get("player_army_mgr")
	var tmm: Variant = world_instance.get("tactical_military_mgr")
	var fsm: Variant = world_instance.get("field_siege_mgr")
	var rm: Variant = world_instance.call("_get_resource_mgr")
	var wd = world_instance.get("world_data")
	var cm := CrisisManagerScript.new(5555)

	_assert(pam != null, "CRS-02.P1: PlayerArmyManager exists")
	_assert(tmm != null, "CRS-02.P2: TacticalMilitaryManager exists")

	# Reset economy and army state
	_clear_test_army(pam, tmm)
	rm.reset_economy()
	rm.add_resource("gold", 500)
	rm.add_resource("metal", 100)
	rm.add_resource("food", 500)

	# Test A: Army at base (GARRISONED at rally_cell)
	_setup_test_army(pam, tmm, 4)
	_assert(pam.soldier_count == 4, "CRS-02.A1: Central reserve is 4")
	_assert(pam.get_defending_soldier_count() == 4, "CRS-02.A2: Defending count at base is exactly 4")

	# Trigger raid with threat = 10
	var raid_a := cm.resolve_bandit_raid(wd, rm, [], pam, fsm)
	_assert(raid_a.field_intercepted > 0, "CRS-02.A3: Settlement army intercepted bandits (intercepted: %d)" % raid_a.field_intercepted)
	_assert(raid_a.field_casualties > 0, "CRS-02.A4: Army suffered casualties from defense (casualties: %d)" % raid_a.field_casualties)
	_assert(pam.soldier_count == 4 - raid_a.field_casualties, "CRS-02.A5: Soldier count correctly decremented by casualties (remaining: %d)" % pam.soldier_count)
	_assert(pam.soldier_count >= 0, "CRS-02.A6: Soldier count has not underflowed")

	# Test B: Army marched away to remote field point (IDLE_AT_FIELD away from rally_cell)
	_setup_test_army(pam, tmm, 4)
	var rally_c: Vector2i = pam.get_rally_cell()
	var remote_c := Vector2i(50, 50) # Far from base rally_cell

	# Dispatch army to field
	pam.set("movement_state", PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD)
	pam.set("current_cell", remote_c)
	pam.set("destination_cell", remote_c)
	# Also update tactical units to remote cells
	for u in tmm.get_all_units():
		if is_instance_valid(u):
			u.current_cell = remote_c

	_assert(pam.soldier_count == 4, "CRS-02.B1: Remote army still has 4 soldiers strategically")
	_assert(pam.get_defending_soldier_count() == 0, "CRS-02.B2: Defending soldier count is strictly 0 when remote")

	# Trigger raid: remote army must NOT intercept and must NOT take casualties
	var initial_remote_soldiers: int = pam.soldier_count
	var raid_b := cm.resolve_bandit_raid(wd, rm, [], pam, fsm)
	_assert(raid_b.field_intercepted == 0, "CRS-02.B3: Remote army intercepted ZERO bandits (observed: %d)" % raid_b.field_intercepted)
	_assert(raid_b.field_casualties == 0, "CRS-02.B4: Remote army suffered ZERO casualties (observed: %d)" % raid_b.field_casualties)
	_assert(pam.soldier_count == initial_remote_soldiers, "CRS-02.B5: Remote army soldier count conserved at %d (no free kills or phantom deaths)" % pam.soldier_count)
	_assert(raid_b.breached_bandits == raid_b.threat_strength, "CRS-02.B6: Full bandit threat breached undefended settlement")

	# Test C: Mixed state (Outpost garrison vs Settlement defense vs Remote army)
	_setup_test_army(pam, tmm, 6)
	# Station 2 soldiers at an outpost
	var dummy_outpost_id := "outpost_test_c"
	pam.garrisons[dummy_outpost_id] = {
		"outpost_id": dummy_outpost_id,
		"cell": Vector2i(10, 10),
		"soldiers": [{"id": "sol_g1", "tier": 1}, {"id": "sol_g2", "tier": 1}]
	}
	pam.soldier_count -= 2 # 4 remaining in central reserve
	tmm.call("sync_with_player_army")

	# Outpost has 2 soldiers, settlement base has 4 defenders
	_assert(pam.get_garrison_count(dummy_outpost_id) == 2, "CRS-02.C1: Outpost garrison has 2 soldiers")
	_assert(pam.get_defending_soldier_count() == 4, "CRS-02.C2: Settlement base has 4 defending soldiers")
	_assert(pam.get_total_soldier_count() == 6, "CRS-02.C3: Total realm headcount strictly conserved at 6")

	var raid_c := cm.resolve_bandit_raid(wd, rm, [], pam, fsm)
	_assert(raid_c.garrison_intercepted > 0, "CRS-02.C4: Outpost garrison engaged in Phase 1 (intercepted: %d)" % raid_c.garrison_intercepted)
	_assert(pam.get_total_soldier_count() == 6 - (raid_c.garrison_casualties + raid_c.field_casualties), "CRS-02.C5: Total army strictly conserved across both defense phases")

	# Test D: In-transit reinforcements do NOT defend settlement
	_setup_test_army(pam, tmm, 3)
	pam.active_reinforcements.append({
		"outpost_id": "outpost_transit_test",
		"soldier_count": 2,
		"soldiers": [{"id": "sol_t1", "tier": 1}, {"id": "sol_t2", "tier": 1}],
		"duration": 5.0,
		"elapsed": 1.0,
		"dispatched_day": 1
	})
	pam.soldier_count -= 2 # 1 remaining at base
	tmm.call("sync_with_player_army")

	_assert(pam.get_in_transit_count("outpost_transit_test") == 2, "CRS-02.D1: 2 soldiers are in-transit")
	_assert(pam.get_defending_soldier_count() == 1, "CRS-02.D2: Only 1 soldier defending settlement base (in-transit excluded)")

	# Clean up test army
	_clear_test_army(pam, tmm)

## -----------------------------------------------------------------------------
## GROUP 3: MBL-SAV-01 Crisis Payload Type and Schema Validation
## -----------------------------------------------------------------------------
func _test_mbl_sav_01_payload_type_and_schema_validation() -> void:
	print("\n--- Running Group 3: MBL-SAV-01 Payload Type & Schema Validation ---")
	var valid_base_save: Dictionary = SaveManagerScript.serialize_world_state(world_instance)

	# 1. crisis_manager is integer 123
	var bad_int_save: Dictionary = valid_base_save.duplicate(true)
	bad_int_save["crisis_manager"] = 123
	var val_int = SaveManagerScript.validate_save_data(bad_int_save)
	_assert(not val_int.valid, "SAV-01.1: Integer crisis_manager rejected fail-closed")
	_assert("Dictionary" in val_int.error, "SAV-01.2: Error identifies Dictionary requirement")

	# 2. crisis_manager is boolean
	var bad_bool_save: Dictionary = valid_base_save.duplicate(true)
	bad_bool_save["crisis_manager"] = true
	var val_bool = SaveManagerScript.validate_save_data(bad_bool_save)
	_assert(not val_bool.valid, "SAV-01.3: Boolean crisis_manager rejected fail-closed")

	# 3. crisis_manager is string
	var bad_str_save: Dictionary = valid_base_save.duplicate(true)
	bad_str_save["crisis_manager"] = "invalid_payload"
	var val_str = SaveManagerScript.validate_save_data(bad_str_save)
	_assert(not val_str.valid, "SAV-01.4: String crisis_manager rejected fail-closed")

	# 4. crisis_manager is array
	var bad_arr_save: Dictionary = valid_base_save.duplicate(true)
	bad_arr_save["crisis_manager"] = ["not", "a", "dictionary"]
	var val_arr = SaveManagerScript.validate_save_data(bad_arr_save)
	_assert(not val_arr.valid, "SAV-01.5: Array crisis_manager rejected fail-closed")

	# 5. crisis_manager is null
	var bad_null_save: Dictionary = valid_base_save.duplicate(true)
	bad_null_save["crisis_manager"] = null
	var val_null = SaveManagerScript.validate_save_data(bad_null_save)
	_assert(not val_null.valid, "SAV-01.6: Null crisis_manager rejected fail-closed")

	# 6. active_crisis_data is integer
	var bad_acd_save: Dictionary = valid_base_save.duplicate(true)
	bad_acd_save["crisis_manager"] = {"active_crisis_data": 999}
	var val_acd = SaveManagerScript.validate_save_data(bad_acd_save)
	_assert(not val_acd.valid, "SAV-01.7: Non-dictionary active_crisis_data rejected fail-closed")
	_assert("active_crisis_data" in val_acd.error, "SAV-01.8: Error identifies active_crisis_data field")

	# 7. current_stage is unknown string
	var bad_stage_save: Dictionary = valid_base_save.duplicate(true)
	bad_stage_save["crisis_manager"] = {"current_stage": "cataclysm_phase_9"}
	var val_stage = SaveManagerScript.validate_save_data(bad_stage_save)
	_assert(not val_stage.valid, "SAV-01.9: Unknown current_stage rejected fail-closed")
	_assert("current_stage" in val_stage.error, "SAV-01.10: Error identifies current_stage field")

	# 8. current_crisis_type is unknown string
	var bad_type_save: Dictionary = valid_base_save.duplicate(true)
	bad_type_save["crisis_manager"] = {"current_crisis_type": "alien_invasion"}
	var val_type = SaveManagerScript.validate_save_data(bad_type_save)
	_assert(not val_type.valid, "SAV-01.11: Unknown current_crisis_type rejected fail-closed")
	_assert("current_crisis_type" in val_type.error, "SAV-01.12: Error identifies current_crisis_type field")

	# 9. world_modifiers in crisis_manager is non-array
	var bad_wm_save: Dictionary = valid_base_save.duplicate(true)
	bad_wm_save["crisis_manager"] = {"world_modifiers": "restless_bandits"}
	var val_wm = SaveManagerScript.validate_save_data(bad_wm_save)
	_assert(not val_wm.valid, "SAV-01.13: Non-array world_modifiers rejected fail-closed")

	# 10. world_modifiers contains non-string
	var bad_wme_save: Dictionary = valid_base_save.duplicate(true)
	bad_wme_save["crisis_manager"] = {"world_modifiers": [12345]}
	var val_wme = SaveManagerScript.validate_save_data(bad_wme_save)
	_assert(not val_wme.valid, "SAV-01.14: Array containing non-string modifier rejected fail-closed")

	# 11. Defensive direct CrisisManager.deserialize tests
	var cm := CrisisManagerScript.new(999)
	cm.deserialize(null)
	_assert(cm.current_stage == CrisisManagerScript.STAGE_INACTIVE, "SAV-01.15: Direct deserialize(null) safe fallback")
	cm.deserialize(123)
	_assert(cm.current_stage == CrisisManagerScript.STAGE_INACTIVE, "SAV-01.16: Direct deserialize(int) safe fallback")
	cm.deserialize("corrupted")
	_assert(cm.current_stage == CrisisManagerScript.STAGE_INACTIVE, "SAV-01.17: Direct deserialize(string) safe fallback")
	cm.deserialize({"current_stage": "invalid_stage", "current_crisis_type": "invalid_type", "active_crisis_data": 555})
	_assert(cm.current_stage == CrisisManagerScript.STAGE_INACTIVE, "SAV-01.18: Unknown stage normalized to STAGE_INACTIVE")
	_assert(cm.current_crisis_type == CrisisManagerScript.CRISIS_NONE, "SAV-01.19: Unknown type normalized to CRISIS_NONE")
	_assert(cm.active_crisis_data.is_empty(), "SAV-01.20: Malformed active_crisis_data safely defaulted to empty dict")

## -----------------------------------------------------------------------------
## GROUP 4: MBL-SAV-02 World Modifiers Persistence & Legacy Migration
## -----------------------------------------------------------------------------
func _test_mbl_sav_02_world_modifiers_persistence_and_isolation() -> void:
	print("\n--- Running Group 4: MBL-SAV-02 World Modifiers Persistence & Isolation ---")
	var base_save: Dictionary = SaveManagerScript.serialize_world_state(world_instance)

	# Integration Test A: Metadata has ["restless_bandits"], crisis_manager is {}
	var legacy_save: Dictionary = base_save.duplicate(true)
	legacy_save["metadata"]["world_modifiers"] = ["restless_bandits"]
	legacy_save["crisis_manager"] = {} # Empty legacy crisis payload

	var res_a = SaveManagerScript.apply_loaded_state_to_world(world_instance, legacy_save)
	_assert(res_a.get("success", false), "SAV-02.A1: apply_loaded_state_to_world succeeded on legacy crisis payload")

	var cr_mgr: Variant = world_instance.get("crisis_mgr")
	var ev_sys: Variant = world_instance.get("event_system")
	var world_mods: Array = world_instance.get("world_modifiers")
	var cr_mods: Array = cr_mgr.get("world_modifiers")
	var ev_mods: Array = ev_sys.get("world_modifiers")

	_assert(world_mods.has("restless_bandits"), "SAV-02.A2: WorldView has 'restless_bandits' from metadata")
	_assert(cr_mods.has("restless_bandits"), "SAV-02.A3: CrisisManager PRESERVED 'restless_bandits' (NOT wiped by empty crisis_manager payload!)")
	_assert(ev_mods.has("restless_bandits"), "SAV-02.A4: WorldEventSystem has 'restless_bandits'")

	# Integration Test B: Explicit world_modifiers in crisis_manager matches/synchronizes
	var explicit_save: Dictionary = base_save.duplicate(true)
	explicit_save["metadata"]["world_modifiers"] = ["pioneer_spirit"]
	explicit_save["crisis_manager"] = {
		"current_crisis_type": "none",
		"current_stage": "inactive",
		"world_modifiers": ["pioneer_spirit"]
	}
	var res_b = SaveManagerScript.apply_loaded_state_to_world(world_instance, explicit_save)
	_assert(res_b.get("success", false), "SAV-02.B1: apply_loaded_state_to_world succeeded with explicit crisis world_modifiers")
	_assert(world_instance.get("world_modifiers").has("pioneer_spirit"), "SAV-02.B2: WorldView has 'pioneer_spirit'")
	_assert(cr_mgr.get("world_modifiers").has("pioneer_spirit"), "SAV-02.B3: CrisisManager has 'pioneer_spirit'")

	# Integration Test C: Legacy save completely omitting 'crisis_manager' key
	var no_crisis_save: Dictionary = base_save.duplicate(true)
	no_crisis_save.erase("crisis_manager")
	no_crisis_save["metadata"]["world_modifiers"] = ["hardened_outposts"]
	var res_c = SaveManagerScript.apply_loaded_state_to_world(world_instance, no_crisis_save)
	_assert(res_c.get("success", false), "SAV-02.C1: apply_loaded_state_to_world succeeded with omitted crisis_manager key")
	_assert(world_instance.get("world_modifiers").has("hardened_outposts"), "SAV-02.C2: WorldView has 'hardened_outposts'")
	_assert(cr_mgr.get("world_modifiers").has("hardened_outposts"), "SAV-02.C3: CrisisManager preserved 'hardened_outposts' across omitted crisis section")

	# Integration Test D: Sequential load isolation (modifiers from Save 1 do NOT leak into Save 2)
	# Step 1: Load Save 1 with ["restless_bandits"]
	var save_with_mods: Dictionary = base_save.duplicate(true)
	save_with_mods["metadata"]["world_modifiers"] = ["restless_bandits"]
	save_with_mods["crisis_manager"] = {"world_modifiers": ["restless_bandits"]}
	SaveManagerScript.apply_loaded_state_to_world(world_instance, save_with_mods)
	_assert(cr_mgr.get("world_modifiers").has("restless_bandits"), "SAV-02.D1: Precondition: Save 1 loaded with 'restless_bandits'")

	# Step 2: Load Save 2 with [] (empty modifiers) in the SAME running process
	var save_empty_mods: Dictionary = base_save.duplicate(true)
	save_empty_mods["metadata"]["world_modifiers"] = []
	save_empty_mods["crisis_manager"] = {}
	var res_d = SaveManagerScript.apply_loaded_state_to_world(world_instance, save_empty_mods)
	_assert(res_d.get("success", false), "SAV-02.D2: Save 2 loaded successfully")
	_assert(world_instance.get("world_modifiers").is_empty(), "SAV-02.D3: WorldView modifiers strictly empty (no leak from Save 1)")
	_assert(cr_mgr.get("world_modifiers").is_empty(), "SAV-02.D4: CrisisManager modifiers strictly empty (no leak from Save 1)")
	_assert(ev_sys.get("world_modifiers").is_empty(), "SAV-02.D5: WorldEventSystem modifiers strictly empty (no leak from Save 1)")

	# Integration Test E: Malformed world_modifiers in metadata rejected before mutation
	var bad_meta_mods: Dictionary = base_save.duplicate(true)
	bad_meta_mods["metadata"]["world_modifiers"] = "corrupted_string"
	var val_meta = SaveManagerScript.validate_save_data(bad_meta_mods)
	_assert(not val_meta.valid, "SAV-02.E1: Malformed metadata world_modifiers rejected by validate_save_data")
