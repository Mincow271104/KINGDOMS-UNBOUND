extends SceneTree

const WorldViewScene = preload("res://scenes/world/world_view.tscn")
const PlayerArmyManagerScript = preload("res://scripts/military/player_army_manager.gd")
const TacticalMilitaryManagerScript = preload("res://scripts/military/tactical_military_manager.gd")
const TacticalUnitScript = preload("res://scripts/military/tactical_unit.gd")
const FieldSiegeManagerScript = preload("res://scripts/combat/field_siege_manager.gd")
const SiegeObjectiveActorScript = preload("res://scripts/combat/siege_objective_actor.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")

var passed_count: int = 0
var failed_count: int = 0

var world_instance: Node = null
var pam: Object = null
var tmm: Object = null
var fsm: Object = null

func _init() -> void:
	print("\n========================================================")
	print("  STARTING SESSION 1.3.2 TRANSACTION INTEGRITY SUITE")
	print("========================================================\n")
	call_deferred("_run_all_tests")

func _assert(condition: bool, message: String) -> void:
	if condition:
		passed_count += 1
		print("  [PASS] %s" % message)
	else:
		failed_count += 1
		printerr("  [FAIL] %s" % message)

func _setup_world() -> void:
	var root := get_root()
	if is_instance_valid(world_instance):
		world_instance.queue_free()
		world_instance = null

	world_instance = WorldViewScene.instantiate()
	root.add_child(world_instance)

	pam = world_instance.get("player_army_mgr")
	tmm = world_instance.get("tactical_military_mgr")
	fsm = world_instance.get("field_siege_mgr")

	pam.soldier_count = 10
	pam.equipment_tier = 1
	pam.garrisons = {}
	pam.active_reinforcements.clear()
	tmm.clear_all_units()
	tmm.sync_with_player_army()

func _create_active_watchtower(b_id: String, cell: Vector2i) -> Dictionary:
	var wd = world_instance.world_data
	var b_data := {
		"id": b_id,
		"type": "watchtower",
		"cell": cell,
		"size": Vector2i(1, 1),
		"state": "active",
		"health": 100,
		"max_health": 100
	}
	wd.buildings.append(b_data)
	world_instance.buildings_by_cell[cell] = "watchtower"
	world_instance._instantiate_building_node("watchtower", cell, Vector2i(1, 1), "active")
	var actor = fsm.register_objective(b_id, cell, "player", 250.0, 3)
	actor.is_alive = true
	actor.is_captured = false
	actor.owning_faction_id = "player"
	return b_data

func _run_all_tests() -> void:
	_test_group_a_null_dependencies()
	_test_group_b_generic_sync_non_destructive()
	_test_group_c_ownership_rollback_exact_state()
	_test_group_d_spawn_failure_factory_boundary()
	_print_summary()

# =============================================================================
# GROUP A: ELIMINATE FAIL-OPEN NULL DEPENDENCIES
# =============================================================================
func _test_group_a_null_dependencies() -> void:
	print("\n--- TEST GROUP A: ELIMINATE FAIL-OPEN NULL DEPENDENCIES ---")
	_setup_world()

	# Scenario 1: Standalone PAM with no WorldView, no TMM, no Nav
	var standalone_pam = PlayerArmyManagerScript.new()
	standalone_pam.soldier_count = 5
	standalone_pam.register_outpost_for_testing("stand_outpost", 3, Vector2i(10, 10), "player")
	standalone_pam.station_soldier("stand_outpost", 2)
	_assert(standalone_pam.get_garrison_count("stand_outpost") == 2, "TC-A1.1: Standalone PAM stationed 2 soldiers")

	# Capacity must be strictly 0 on standalone PAM
	_assert(standalone_pam._get_available_spawn_slots(2) == 0, "TC-A1.2: Standalone PAM spawn slots is strictly 0")

	# Voluntary recall must fail closed
	var rec_res := standalone_pam.recall_soldier("stand_outpost", 1)
	_assert(rec_res.get("success", true) == false, "TC-A1.3: Standalone PAM voluntary recall fails closed")
	_assert(standalone_pam.get_garrison_count("stand_outpost") == 2, "TC-A1.4: Standalone PAM garrison preserved")
	_assert(standalone_pam.soldier_count == 3, "TC-A1.5: Standalone PAM reserve unchanged")

	# Voluntary demolition must fail closed
	var vol_evict := standalone_pam.evict_and_cancel_outpost("stand_outpost", true, false)
	_assert(vol_evict.get("success", true) == false, "TC-A1.6: Standalone PAM voluntary eviction fails closed")
	_assert(standalone_pam.get_garrison_count("stand_outpost") == 2, "TC-A1.7: Standalone PAM garrison preserved after eviction failure")

	# Forced eviction on standalone PAM: 0 capacity -> 100% casualties, records erased, 0 ghost increment
	var forced_evict := standalone_pam.evict_and_cancel_outpost("stand_outpost", true, true)
	_assert(forced_evict.get("success", false) == true, "TC-A1.8: Standalone PAM forced eviction succeeds with casualty accounting")
	_assert(forced_evict.get("evacuated_count", -1) == 0, "TC-A1.9: Standalone PAM 0 evacuated on missing dependencies")
	_assert(forced_evict.get("casualties_count", -1) == 2, "TC-A1.10: Standalone PAM all 2 soldiers accounted as casualties")
	_assert(standalone_pam.get_garrison_count("stand_outpost") == 0, "TC-A1.11: Standalone PAM garrison record cleared")
	_assert(standalone_pam.soldier_count == 3, "TC-A1.12: Standalone PAM reserve remains 3, zero ghost increment")

	# Scenario 2: WorldView present, but TMM is null
	_setup_world()
	var b_id_a2 := "wt_null_tmm"
	_create_active_watchtower(b_id_a2, Vector2i(20, 20))
	pam.station_soldier(b_id_a2, 2)
	_assert(pam.get_garrison_count(b_id_a2) == 2, "TC-A2.1: Stationed 2 in watchtower")

	pam.tactical_military_mgr = null
	world_instance.tactical_military_mgr = null
	_assert(pam._get_available_spawn_slots(2) == 0, "TC-A2.2: Available spawn slots is 0 when TMM is null")

	var rec_null_tmm: Dictionary = pam.recall_soldier(b_id_a2, 1)
	_assert(rec_null_tmm.get("success", true) == false, "TC-A2.3: Voluntary recall fails closed when TMM is null")
	_assert(pam.get_garrison_count(b_id_a2) == 2, "TC-A2.4: Garrison preserved on null TMM recall")

	var demo_null_tmm: Dictionary = world_instance.demolish_building_project(b_id_a2)
	_assert(demo_null_tmm.get("success", true) == false, "TC-A2.5: Voluntary demolition fails closed when TMM is null")
	_assert(pam.get_garrison_count(b_id_a2) == 2, "TC-A2.6: Garrison preserved on null TMM demolition")

	# Scenario 3: WorldView and TMM present, but Navigation is null
	_setup_world()
	var b_id_a3 := "wt_null_nav"
	_create_active_watchtower(b_id_a3, Vector2i(21, 21))
	pam.station_soldier(b_id_a3, 2)
	_assert(pam.get_garrison_count(b_id_a3) == 2, "TC-A3.1: Stationed 2 in watchtower")

	pam._test_simulate_null_nav = true
	tmm._test_simulate_null_nav = true
	_assert(pam._get_available_spawn_slots(2) == 0, "TC-A3.2: Available spawn slots is 0 when Nav is null")

	var rec_null_nav: Dictionary = pam.recall_soldier(b_id_a3, 1)
	_assert(rec_null_nav.get("success", true) == false, "TC-A3.3: Voluntary recall fails closed when Nav is null")
	_assert(pam.get_garrison_count(b_id_a3) == 2, "TC-A3.4: Garrison preserved on null Nav recall")

	var demo_null_nav: Dictionary = world_instance.demolish_building_project(b_id_a3)
	_assert(demo_null_nav.get("success", true) == false, "TC-A3.5: Voluntary demolition fails closed when Nav is null")
	_assert(pam.get_garrison_count(b_id_a3) == 2, "TC-A3.6: Garrison preserved on null Nav demolition")

	pam._test_simulate_null_nav = false
	tmm._test_simulate_null_nav = false

	# Scenario 4: Positive baseline with valid dependencies
	_assert(pam._get_available_spawn_slots(2) >= 2, "TC-A4.1: Available spawn slots >= 2 when dependencies are healthy")
	var rec_ok: Dictionary = pam.recall_soldier(b_id_a3, 1)
	_assert(rec_ok.get("success", false) == true, "TC-A4.2: Voluntary recall succeeds when dependencies are healthy")
	_assert(pam.get_garrison_count(b_id_a3) == 1, "TC-A4.3: Garrison decremented to 1")
	_assert(pam.soldier_count == 9, "TC-A4.4: Reserve incremented to 9")

	# Scenario 5: Freed / invalid reference detection
	var dead_pam = PlayerArmyManagerScript.new()
	var dead_mgr = Node2D.new()
	dead_pam.tactical_military_mgr = dead_mgr
	dead_mgr.free()
	var dead_slots: int = dead_pam._get_available_spawn_slots(1)
	_assert(dead_slots == 0, "TC-A5.1: Spawn slots is 0 when manager reference is freed")

	# Scenario 6: Reinforcement arrival with null dependencies evaluates to 0 capacity
	_setup_world()
	var b_id_a6 := "wt_reinf_null_nav"
	_create_active_watchtower(b_id_a6, Vector2i(22, 22))
	pam.dispatch_reinforcements(b_id_a6, 2, 2.0)
	_assert(pam.get_in_transit_count(b_id_a6) == 2, "TC-A6.1: 2 soldiers in transit")
	_assert(pam.soldier_count == 8, "TC-A6.2: Reserve decremented to 8")

	# Destroy outpost before arrival
	world_instance.world_data.buildings = world_instance.world_data.buildings.filter(func(b): return b.id != b_id_a6)
	var obj_a6 = fsm.get_objective(b_id_a6)
	if obj_a6:
		obj_a6.is_alive = false
		obj_a6.owning_faction_id = "destroyed"

	# Simulate null Nav upon arrival
	pam._test_simulate_null_nav = true
	tmm._test_simulate_null_nav = true
	pam.advance_reinforcements(3.0)

	_assert(pam.get_in_transit_count(b_id_a6) == 0, "TC-A6.3: In-transit record erased on dead outpost arrival with null Nav")
	_assert(pam.soldier_count == 8, "TC-A6.4: Reserve remains 8 (100% casualties, 0 ghost increment)")
	pam._test_simulate_null_nav = false
	tmm._test_simulate_null_nav = false

# =============================================================================
# GROUP B: GENERIC SYNC MUST NOT SILENTLY DELETE SOLDIERS
# =============================================================================
func _test_group_b_generic_sync_non_destructive() -> void:
	print("\n--- TEST GROUP B: GENERIC SYNC NON-DESTRUCTIVE VERIFICATION ---")
	_setup_world()

	# Baseline: 10 soldiers in reserve, 10 tactical units on map
	_assert(pam.soldier_count == 10, "TC-B1.1: Initial reserve is 10")
	_assert(tmm.units.size() == 10, "TC-B1.2: Initial tactical units is 10")

	# Subtest 1: Normal sync when reserve > units by 2 succeeds
	pam.soldier_count = 12
	var sync_res_1: Dictionary = tmm.sync_with_player_army()
	_assert(sync_res_1.get("success", false) == true, "TC-B1.3: sync_with_player_army returns success when room available")
	_assert(sync_res_1.get("spawned", 0) == 2, "TC-B1.4: Exactly 2 units spawned")
	_assert(sync_res_1.get("needed", 0) == 2, "TC-B1.5: Exactly 2 needed")
	_assert(tmm.units.size() == 12, "TC-B1.6: Tactical units increased to 12")
	_assert(pam.soldier_count == 12, "TC-B1.7: Canonical soldier count preserved at 12")

	# Subtest 2: Partial spawn failure during generic sync (e.g. only 1 of 2 can spawn)
	pam.soldier_count = 14 # 2 more needed
	tmm._test_max_successful_spawns = 1 # allow only 1 spawn

	var sync_res_2: Dictionary = tmm.sync_with_player_army()
	_assert(sync_res_2.get("success", true) == false, "TC-B2.1: sync_with_player_army returns false on incomplete spawn")
	_assert(sync_res_2.get("spawned", 0) == 0, "TC-B2.2: sync reported spawned = 0 (partial units rolled back)")
	_assert(sync_res_2.get("needed", 0) == 2, "TC-B2.3: sync reported needed = 2")
	_assert(tmm.units.size() == 12, "TC-B2.4: Tactical units remains 12 (zero partial units leaked)")
	# CRITICAL INVARIANT: pam.soldier_count must NOT be silently decremented to 12!
	_assert(pam.soldier_count == 14, "TC-B2.5: Canonical soldier_count NOT silently decremented (remains 14)")

	tmm._test_max_successful_spawns = -1

	# Subtest 3: Zero spawns succeed during generic sync (e.g. maxed capacity)
	pam.soldier_count = 16 # 4 more needed
	tmm._test_spawn_capacity_override = 0

	var sync_res_3: Dictionary = tmm.sync_with_player_army()
	_assert(sync_res_3.get("success", true) == false, "TC-B3.1: sync_with_player_army returns false when 0 spawns available")
	_assert(sync_res_3.get("spawned", -1) == 0, "TC-B3.2: sync reported spawned = 0")
	_assert(sync_res_3.get("needed", 0) == 4, "TC-B3.3: sync reported needed = 4")
	# CRITICAL INVARIANT: pam.soldier_count preserved at 16, units remain 12
	_assert(pam.soldier_count == 16, "TC-B3.4: Canonical soldier_count strictly preserved at 16 (never deleted)")
	_assert(tmm.units.size() == 12, "TC-B3.5: Tactical units remain 12")

	tmm._test_spawn_capacity_override = -1

	# Subtest 4: Pre-existing tactical units are untouched by failed generic sync
	var existing_ids: Array = tmm.units.keys()
	existing_ids.sort()
	var pre_positions: Dictionary = {}
	for uid in existing_ids:
		pre_positions[uid] = tmm.units[uid].current_cell

	tmm._test_simulate_spawn_instantiation_failure = true
	var sync_res_4: Dictionary = tmm.sync_with_player_army()
	_assert(sync_res_4.get("success", true) == false, "TC-B4.1: Sync failed under simulated instantiation failure")
	_assert(pam.soldier_count == 16, "TC-B4.2: soldier_count unchanged at 16")
	_assert(tmm.units.size() == 12, "TC-B4.3: Unit count unchanged at 12")

	var all_preserved: bool = true
	for uid in existing_ids:
		if not tmm.units.has(uid) or tmm.units[uid].current_cell != pre_positions[uid]:
			all_preserved = false
			break
	_assert(all_preserved, "TC-B4.4: Every pre-existing tactical unit preserved with exact ID and position")

	tmm._test_simulate_spawn_instantiation_failure = false

# =============================================================================
# GROUP C: OWNERSHIP TRANSFER ROLLBACK RESTORES EXACT STATE
# =============================================================================
func _test_group_c_ownership_rollback_exact_state() -> void:
	print("\n--- TEST GROUP C: OWNERSHIP TRANSFER ROLLBACK EXACT STATE ---")
	_setup_world()

	var obj_c := "wt_rollback_exact"
	_create_active_watchtower(obj_c, Vector2i(25, 25))
	var obj_actor = fsm.get_objective(obj_c)
	_assert(obj_actor != null, "TC-C1.1: Watchtower objective registered")

	# Station 2 soldiers and dispatch 1 reinforcement
	pam.station_soldier(obj_c, 2)
	pam.dispatch_reinforcements(obj_c, 1, 5.0)

	_assert(pam.get_garrison_count(obj_c) == 2, "TC-C1.2: Garrison has 2 soldiers")
	_assert(pam.get_in_transit_count(obj_c) == 1, "TC-C1.3: In-transit has 1 soldier")
	_assert(pam.soldier_count == 7, "TC-C1.4: Reserve is 7 (10 - 2 - 1)")
	_assert(tmm.units.size() == 7, "TC-C1.5: Tactical units on map is 7")

	var orig_unit_ids: Array = tmm.units.keys()
	orig_unit_ids.sort()
	var orig_unit_positions: Dictionary = {}
	var orig_unit_states: Dictionary = {}
	for uid in orig_unit_ids:
		var u = tmm.units[uid]
		orig_unit_positions[uid] = u.current_cell
		orig_unit_states[uid] = u.order_state

	var orig_next_soldier_id: int = pam.next_soldier_id
	var orig_next_reinforce_id: int = pam.next_reinforce_id

	# Configure actor to fail ownership commit via test hook
	obj_actor._test_simulate_transfer_failure = true

	# Attempt ownership transfer
	var tx_res: Dictionary = fsm.transfer_outpost_ownership(obj_c, "rival_military", "tx_c_rollback_01")
	_assert(tx_res.get("success", true) == false, "TC-C2.1: Transfer ownership returns failure")

	# VERIFY ROLLBACK RESTORATION:
	# 1. Newly spawned tactical units must be deleted
	_assert(tmm.units.size() == 7, "TC-C2.2: Tactical unit count restored exactly to 7 (no leaked units)")

	# 2. Pre-existing tactical units must be EXACTLY preserved
	var post_unit_ids: Array = tmm.units.keys()
	post_unit_ids.sort()
	_assert(post_unit_ids == orig_unit_ids, "TC-C2.3: Pre-existing unit IDs match exactly")

	var states_preserved: bool = true
	for uid in orig_unit_ids:
		var u = tmm.units[uid]
		if u.current_cell != orig_unit_positions[uid] or u.order_state != orig_unit_states[uid]:
			states_preserved = false
			break
	_assert(states_preserved, "TC-C2.4: Pre-existing unit positions and states match exactly")

	# 3. Garrison records restored
	_assert(pam.get_garrison_count(obj_c) == 2, "TC-C2.5: Garrison restored to 2")

	# 4. In-transit reinforcements restored
	_assert(pam.get_in_transit_count(obj_c) == 1, "TC-C2.6: In-transit restored to 1")

	# 5. Reserve soldier_count restored
	_assert(pam.soldier_count == 7, "TC-C2.7: Reserve soldier_count restored to 7")

	# 6. ID counters restored
	_assert(pam.next_soldier_id == orig_next_soldier_id, "TC-C2.8: next_soldier_id restored")
	_assert(pam.next_reinforce_id == orig_next_reinforce_id, "TC-C2.9: next_reinforce_id restored")

	# 7. Actor ownership untouched
	_assert(obj_actor.owning_faction_id == "player", "TC-C2.10: Objective owner remains player")

	obj_actor._test_simulate_transfer_failure = false

	# Subtest 2: Successful commit after failure hook disabled
	var tx_res_ok: Dictionary = fsm.transfer_outpost_ownership(obj_c, "rival_military", "tx_c_commit_02")
	_assert(tx_res_ok.get("success", false) == true, "TC-C3.1: Ownership transfer succeeds when hook disabled")
	_assert(obj_actor.owning_faction_id == "rival_military", "TC-C3.2: Objective owner updated to rival_military")
	_assert(pam.get_garrison_count(obj_c) == 0, "TC-C3.3: Garrison cleared on capture")
	_assert(pam.get_in_transit_count(obj_c) == 0, "TC-C3.4: In-transit cleared on capture")
	_assert(pam.soldier_count == 10, "TC-C3.5: Evacuated 3 soldiers to reserve (7 + 3 = 10)")
	_assert(tmm.units.size() == 10, "TC-C3.6: Tactical units spawned on map (10 == 10)")

# =============================================================================
# GROUP D: ACTUAL SPAWN FAILURE AT INSTANTIATION BOUNDARY
# =============================================================================
func _test_group_d_spawn_failure_factory_boundary() -> void:
	print("\n--- TEST GROUP D: SPAWN FAILURE AT FACTORY/INSTANTIATION BOUNDARY ---")
	_setup_world()

	var obj_d := "wt_spawn_factory_fail"
	_create_active_watchtower(obj_d, Vector2i(28, 28))
	pam.station_soldier(obj_d, 2)
	_assert(pam.soldier_count == 8, "TC-D1.1: Reserve at 8")
	_assert(tmm.units.size() == 8, "TC-D1.2: Tactical units at 8")

	# Subtest 1: Factory returns null during voluntary eviction -> fails closed, 0 partial units leaked
	tmm._test_simulate_spawn_instantiation_failure = true
	var demo_res: Dictionary = world_instance.demolish_building_project(obj_d)
	_assert(demo_res.get("success", true) == false, "TC-D1.3: Demolition fails closed when instantiation fails")
	_assert(pam.get_garrison_count(obj_d) == 2, "TC-D1.4: Garrison preserved on instantiation failure")
	_assert(pam.soldier_count == 8, "TC-D1.5: Reserve unchanged at 8")
	_assert(tmm.units.size() == 8, "TC-D1.6: Tactical units unchanged at 8 (zero ghost units)")

	tmm._test_simulate_spawn_instantiation_failure = false

	# Subtest 2: Partial factory failure during voluntary eviction -> rollback removes partial spawns
	tmm._test_max_successful_spawns = 1 # allow only 1 spawn out of 2 needed
	var demo_res_partial: Dictionary = world_instance.demolish_building_project(obj_d)
	_assert(demo_res_partial.get("success", true) == false, "TC-D2.1: Demolition fails closed on partial spawn")
	_assert(pam.get_garrison_count(obj_d) == 2, "TC-D2.2: Garrison preserved on partial spawn")
	_assert(pam.soldier_count == 8, "TC-D2.3: Reserve unchanged at 8")
	_assert(tmm.units.size() == 8, "TC-D2.4: Tactical units unchanged at 8 (partial spawn rolled back)")

	tmm._test_max_successful_spawns = -1

	# Subtest 3: Forced eviction with partial factory failure -> evacuates successful, records rest as casualties
	tmm._test_max_successful_spawns = 1 # allow only 1 spawn out of 2 needed
	var forced_res: Dictionary = pam.evict_and_cancel_outpost(obj_d, true, true)
	_assert(forced_res.get("success", false) == true, "TC-D3.1: Forced eviction succeeds with partial casualty accounting")
	_assert(forced_res.get("evacuated_count", -1) == 1, "TC-D3.2: Exactly 1 evacuated")
	_assert(forced_res.get("casualties_count", -1) == 1, "TC-D3.3: Exactly 1 recorded as casualty")
	_assert(pam.get_garrison_count(obj_d) == 0, "TC-D3.4: Garrison cleared")
	_assert(pam.soldier_count == 9, "TC-D3.5: Reserve incremented by 1 (8 + 1 = 9)")
	_assert(tmm.units.size() == 9, "TC-D3.6: Tactical units is 9 (8 + 1 = 9)")

	tmm._test_max_successful_spawns = -1

	# Verify final system invariant: Invariant B (units == reserve)
	_assert(tmm.units.size() == pam.soldier_count, "TC-D4.1: Final Invariant B strictly holds: units (%d) == reserve (%d)" % [tmm.units.size(), pam.soldier_count])

func _print_summary() -> void:
	print("\n========================================================")
	print("  SESSION 1.3.2 TEST RESULTS SUMMARY")
	print("========================================================")
	print("  Passed Assertions : %d" % passed_count)
	print("  Failed Assertions : %d" % failed_count)
	if failed_count == 0:
		print("  ALL SESSION 1.3.2 ASSERTIONS PASSED! (Exit Code 0)")
		print("========================================================\n")
		quit(0)
	else:
		printerr("  SOME SESSION 1.3.2 ASSERTIONS FAILED!")
		print("========================================================\n")
		quit(1)
