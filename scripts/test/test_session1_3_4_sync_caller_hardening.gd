extends SceneTree

const WorldViewScene = preload("res://scenes/world/world_view.tscn")
const PlayerArmyManagerScript = preload("res://scripts/military/player_army_manager.gd")
const TacticalMilitaryManagerScript = preload("res://scripts/military/tactical_military_manager.gd")
const TacticalUnitScript = preload("res://scripts/military/tactical_unit.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")

var passed_count: int = 0
var failed_count: int = 0

var world_instance: Node = null
var pam: Object = null
var tmm: Object = null

func _init() -> void:
	print("\n========================================================")
	print("  STARTING SESSION 1.3.4 SYNC CALLER HARDENING SUITE")
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

	pam.soldier_count = 0
	pam.equipment_tier = 1
	pam.garrisons = {}
	pam.active_reinforcements.clear()
	tmm.clear_all_units()

func _create_active_watchtower(b_id: String, cell: Vector2i) -> Dictionary:
	var wd = world_instance.world_data
	var b_data := {
		"id": b_id,
		"type": "watchtower",
		"cell": cell,
		"size": Vector2i(1, 1),
		"state": "active",
		"health": 100,
		"max_health": 100,
		"construction_progress": 100.0,
		"construction_hours": 0.0,
		"upgrade_level": 1
	}
	wd["buildings"].append(b_data)
	world_instance.buildings_by_cell[cell] = b_data

	var b_node := Node2D.new()
	b_node.name = "Building_watchtower_%d_%d" % [cell.x, cell.y]
	world_instance.buildings_container.add_child(b_node)

	pam.register_outpost_for_testing(b_id, 3, cell)
	return b_data

func _run_all_tests() -> void:
	_test_group_a_manager_binding_sync_failure()
	_test_group_b_tactical_orders_fail_closed_on_desync()
	_test_group_c_perk_genesis_rollback_on_congestion()
	_test_group_d_save_and_legacy_load_hardening()
	_test_group_e_demolition_rollback_side_effects()
	_test_group_f_session1_3_5_synchronization_invariants()

	print("\n========================================================")
	print("  SESSION 1.3.4 TEST RESULTS SUMMARY")
	print("========================================================")
	print("  Passed Assertions : %d" % passed_count)
	print("  Failed Assertions : %d" % failed_count)
	if failed_count == 0:
		print("  ALL SESSION 1.3.4 ASSERTIONS PASSED! (Exit Code 0)")
		print("========================================================\n")
		quit(0)
	else:
		printerr("  SOME ASSERTIONS FAILED! (Exit Code 1)")
		print("========================================================\n")
		quit(1)

# =============================================================================
# GROUP A: MANAGER BINDING SYNCHRONIZATION FAILURE PROPAGATION
# =============================================================================
func _test_group_a_manager_binding_sync_failure() -> void:
	print("\n--- TEST GROUP A: MANAGER BINDING SYNC FAILURE ---")
	_setup_world()

	# Subtest A1: PAM set_tactical_military_manager with non-empty army when spawn is blocked
	var test_pam = PlayerArmyManagerScript.new()
	var test_tmm = TacticalMilitaryManagerScript.new()
	test_pam.soldier_count = 5
	test_tmm._test_spawn_capacity_override = 0 # Block all spawns

	var bind_res = test_pam.set_tactical_military_manager(test_tmm)
	_assert(bind_res is Dictionary, "TC-A1.1: set_tactical_military_manager returns Dictionary")
	_assert(bind_res.get("success", true) == false, "TC-A1.2: set_tactical_military_manager reports failure on spawn block")
	_assert(test_pam.soldier_count == 5, "TC-A1.3: Canonical soldier_count preserved (never decremented)")
	_assert(test_tmm.units.is_empty(), "TC-A1.4: No orphaned tactical units left over")

	# Subtest A2: TMM set_player_army_manager with non-empty army when factory fails
	var test_pam2 = PlayerArmyManagerScript.new()
	var test_tmm2 = TacticalMilitaryManagerScript.new()
	test_pam2.soldier_count = 3
	test_tmm2._test_simulate_spawn_instantiation_failure = true

	var bind_res2 = test_tmm2.set_player_army_manager(test_pam2)
	_assert(bind_res2 is Dictionary, "TC-A2.1: set_player_army_manager returns Dictionary")
	_assert(bind_res2.get("success", true) == false, "TC-A2.2: set_player_army_manager reports failure on factory error")
	_assert(test_pam2.soldier_count == 3, "TC-A2.3: Canonical soldier_count strictly intact at 3")
	_assert(test_tmm2.units.is_empty(), "TC-A2.4: Tactical units count is 0 after factory error")

# =============================================================================
# GROUP B: TACTICAL ORDERS ABORT CLOSED ON DESYNC
# =============================================================================
func _test_group_b_tactical_orders_fail_closed_on_desync() -> void:
	print("\n--- TEST GROUP B: TACTICAL ORDERS FAIL CLOSED ON DESYNC ---")
	_setup_world()

	pam.soldier_count = 5
	tmm.sync_with_player_army()
	_assert(tmm.units.size() == 5, "TC-B1.1: Initial tactical units match reserve at 5")

	# Artificially desynchronize: pam has 8 soldiers, but spawn capacity is blocked
	pam.soldier_count = 8
	tmm._test_spawn_capacity_override = 0

	var move_order_res = tmm.order_move_all(Vector2i(35, 35))
	_assert(move_order_res is Dictionary, "TC-B2.1: order_move_all returns Dictionary")
	_assert(move_order_res.get("success", true) == false, "TC-B2.2: order_move_all fails closed when sync fails")
	_assert(pam.soldier_count == 8, "TC-B2.3: Soldier count preserved at 8 on move order abort")
	_assert(tmm.units.size() == 5, "TC-B2.4: Pre-existing unit count untouched at 5")

	var return_order_res = tmm.order_return_all_to_rally()
	_assert(return_order_res is Dictionary, "TC-B3.1: order_return_all_to_rally returns Dictionary")
	_assert(return_order_res.get("success", true) == false, "TC-B3.2: order_return_all_to_rally fails closed when sync fails")
	_assert(pam.soldier_count == 8, "TC-B3.3: Soldier count preserved at 8 on return order abort")

	tmm._test_spawn_capacity_override = -1

# =============================================================================
# GROUP C: STARTING PERK GENESIS ROLLBACK ON CONGESTION
# =============================================================================
func _test_group_c_perk_genesis_rollback_on_congestion() -> void:
	print("\n--- TEST GROUP C: STARTING PERK GENESIS ROLLBACK ON CONGESTION ---")
	_setup_world()

	world_instance.active_perks = ["hardened_outposts"]
	tmm._test_spawn_capacity_override = 0 # Simulate congestion at genesis

	var initial_s: int = pam.soldier_count
	world_instance._apply_starting_perks_and_modifiers()

	_assert(pam.soldier_count == initial_s, "TC-C1.1: soldier_count rolled back to initial value (0) on perk sync failure")
	_assert(tmm.units.size() == pam.soldier_count, "TC-C1.2: Invariant holds: units.size() == soldier_count == 0")

	tmm._test_spawn_capacity_override = -1

# =============================================================================
# GROUP D: SAVEMANAGER SAVE AND LEGACY LOAD HARDENING
# =============================================================================
func _test_group_d_save_and_legacy_load_hardening() -> void:
	print("\n--- TEST GROUP D: SAVEMANAGER SAVE AND LEGACY LOAD HARDENING ---")
	_setup_world()

	# Subtest D1: save_to_file aborts if sync fails
	pam.soldier_count = 4
	tmm.clear_all_units()
	tmm._test_simulate_spawn_instantiation_failure = true

	var test_save_path := "user://saves/test_sync_fail_save.json"
	var save_res = SaveManagerScript.save_to_file(world_instance, test_save_path)
	_assert(save_res.get("success", true) == false, "TC-D1.1: save_to_file fails closed when pre-save sync fails")
	_assert(not FileAccess.file_exists(test_save_path), "TC-D1.2: No save file written to disk on sync failure")

	tmm._test_simulate_spawn_instantiation_failure = false

	# Subtest D2: apply_loaded_state_to_world rolls back legacy save if spawn slots insufficient
	pam.soldier_count = 2
	tmm.sync_with_player_army()

	var legacy_save := {
		"schema_version": SaveManagerScript.SAVE_SCHEMA_VERSION,
		"timestamp": "2026-01-01T00:00:00",
		"metadata": {"world_id": "leg_world_01", "difficulty": "normal"},
		"game_clock": {"current_day": 1, "current_hour": 12, "season_index": 0, "current_year": 1, "current_speed": 1},
		"resources": {"stock": {"food": 100}, "total_stock": {"food": 100}, "capacities": {}, "active_population": 10, "is_starving": false},
		"buildings": [],
		"citizens": [],
		"player_army": {
			"soldier_count": 8,
			"movement_state": 0,
			"current_cell_x": 32,
			"current_cell_y": 33,
			"rally_cell_x": 32,
			"rally_cell_y": 33
		}
		# Note: NO "tactical_military" key -> triggers deserialize_legacy
	}

	tmm._test_spawn_capacity_override = 2 # only 2 slots available for 8 soldiers!
	var load_res = SaveManagerScript.apply_loaded_state_to_world(world_instance, legacy_save)
	_assert(load_res.get("success", true) == false, "TC-D2.1: apply_loaded_state_to_world fails closed when legacy deserialize fails")
	_assert(pam.soldier_count == 2, "TC-D2.2: Pre-load soldier_count restored via rollback")
	_assert(tmm.units.size() == 2, "TC-D2.3: Pre-load tactical units restored via rollback")

	tmm._test_spawn_capacity_override = -1

# =============================================================================
# GROUP E: DEMOLITION ROLLBACK SIDE-EFFECT VERIFICATION
# =============================================================================
func _test_group_e_demolition_rollback_side_effects() -> void:
	print("\n--- TEST GROUP E: DEMOLITION ROLLBACK SIDE-EFFECT VERIFICATION ---")
	_setup_world()

	pam.soldier_count = 6
	tmm.sync_with_player_army()
	_assert(tmm.units.size() == 6, "TC-E1.1: Initial reserve and tactical units is 6")

	var wt_id := "wt_demo_test"
	_create_active_watchtower(wt_id, Vector2i(22, 22))

	var stat_res = pam.station_soldier(wt_id, 2)
	_assert(stat_res.get("success", false) == true, "TC-E1.2: Stationed 2 in watchtower")
	_assert(pam.soldier_count == 4, "TC-E1.3: Reserve decremented to 4")
	_assert(tmm.units.size() == 4, "TC-E1.4: Tactical units is 4")

	var disp_res = pam.dispatch_reinforcements(wt_id, 1, 10.0)
	_assert(disp_res.get("success", false) == true, "TC-E1.5: Dispatched 1 reinforcement en route")
	_assert(pam.soldier_count == 3, "TC-E1.6: Reserve decremented to 3")
	_assert(tmm.units.size() == 3, "TC-E1.7: Tactical units is 3")

	# Track garrison_changed signal emissions
	var garrison_signal_emissions: Array = []
	pam.garrison_changed.connect(func(outpost_id: String, count: int, cap: int):
		garrison_signal_emissions.append({"id": outpost_id, "count": count, "cap": cap})
	)

	# Simulate failure inside BuildingSystem.demolish_building
	BuildingSystemScript._test_force_demolish_failure = true

	var demo_res = world_instance.demolish_building_project(wt_id)
	_assert(demo_res.get("success", true) == false, "TC-E2.1: Demolish returns failure when BuildingSystem fails")

	# Verify complete rollback of military state
	_assert(pam.get_garrison_count(wt_id) == 2, "TC-E2.2: Garrison restored to 2")
	_assert(pam.get_in_transit_count(wt_id) == 1, "TC-E2.3: In-transit reinforcements restored to 1")
	_assert(pam.soldier_count == 3, "TC-E2.4: Central reserve restored to 3")
	_assert(tmm.units.size() == 3, "TC-E2.5: Tactical units on map restored to 3 (zero spawned units leaked)")

	# Verify building was NOT removed or cleared
	_assert(world_instance.buildings_by_cell.has(Vector2i(22, 22)), "TC-E2.6: Building remains in buildings_by_cell")
	var b_node = world_instance.buildings_container.get_node_or_null("Building_watchtower_22_22")
	_assert(b_node != null and is_instance_valid(b_node), "TC-E2.7: Building scene node preserved in tree")

	# Verify final garrison signal state informed UI of restored garrison
	_assert(garrison_signal_emissions.size() >= 2, "TC-E2.8: Garrison changed emitted on eviction and restored on rollback")
	var last_signal = garrison_signal_emissions.back()
	_assert(last_signal.get("count") == 2, "TC-E2.9: Final garrison signal accurately reported restored count of 2")

	BuildingSystemScript._test_force_demolish_failure = false

# =============================================================================
# GROUP F: SESSION 1.3.5 SYNCHRONIZATION INVARIANTS & REBINDING
# =============================================================================
func _test_group_f_session1_3_5_synchronization_invariants() -> void:
	print("\n--- TEST GROUP F: SESSION 1.3.5 SYNCHRONIZATION INVARIANTS ---")
	_setup_world()

	# 1. Full successful synchronization
	pam.soldier_count = 5
	var sync_f1 = tmm.sync_with_player_army()
	_assert(sync_f1.get("success", false) == true, "TC-F1.1: Full synchronization returns success")
	_assert(sync_f1.get("spawned", 0) == 5, "TC-F1.2: Exactly 5 units spawned")
	_assert(tmm.units.size() == 5, "TC-F1.3: Tactical units size matches 5")
	_assert(pam.soldier_count == 5, "TC-F1.4: soldier_count matches 5")

	# 2. Failure before any spawn (spawn capacity = 0)
	pam.soldier_count = 8 # 3 more needed
	tmm._test_spawn_capacity_override = 0
	var sync_f2 = tmm.sync_with_player_army()
	_assert(sync_f2.get("success", true) == false, "TC-F2.1: Sync fails when capacity is 0")
	_assert(sync_f2.get("spawned", -1) == 0, "TC-F2.2: 0 spawned reported")
	_assert(sync_f2.get("needed", 0) == 3, "TC-F2.3: 3 needed reported")
	_assert(tmm.units.size() == 5, "TC-F2.4: Pre-existing 5 units preserved")
	_assert(pam.soldier_count == 8, "TC-F2.5: Canonical soldier_count preserved at 8")

	tmm._test_spawn_capacity_override = -1

	# 3. Partial spawn followed by failure (Transactional Rollback)
	tmm._test_max_successful_spawns = 2 # only 2 out of 3 allowed
	var sync_f3 = tmm.sync_with_player_army()
	_assert(sync_f3.get("success", true) == false, "TC-F3.1: Sync fails on partial spawn")
	_assert(sync_f3.get("spawned", -1) == 0, "TC-F3.2: Spawned reported 0 due to transactional rollback")
	_assert(tmm.units.size() == 5, "TC-F3.3: Pre-existing units strictly preserved at 5 (zero leaked units)")
	_assert(pam.soldier_count == 8, "TC-F3.4: soldier_count untouched at 8")

	# 4. Retry after capacity becomes available
	tmm._test_max_successful_spawns = -1
	var sync_f4 = tmm.sync_with_player_army()
	_assert(sync_f4.get("success", false) == true, "TC-F4.1: Retry succeeds after capacity restored")
	_assert(sync_f4.get("spawned", 0) == 3, "TC-F4.2: Remaining 3 units spawned on retry")
	_assert(tmm.units.size() == 8, "TC-F4.3: Total units is 8")
	_assert(pam.soldier_count == 8, "TC-F4.4: soldier_count is 8")

	# 5. Manager rebinding after failure
	pam.soldier_count = 6
	pam.set_tactical_military_manager(null)
	var tmm_rebind = TacticalMilitaryManagerScript.new()
	tmm_rebind._test_spawn_capacity_override = 0 # Block spawns on first bind

	var rebind_fail = pam.set_tactical_military_manager(tmm_rebind)
	_assert(rebind_fail.get("success", true) == false, "TC-F5.1: Manager bind fails closed on spawn failure")
	_assert(pam.soldier_count == 6, "TC-F5.2: soldier_count preserved at 6 on bind failure")
	_assert(tmm_rebind.units.is_empty(), "TC-F5.3: No rogue units created in failing manager")

	# Now relieve congestion and rebind
	tmm_rebind._test_spawn_capacity_override = -1
	var rebind_ok = pam.set_tactical_military_manager(tmm_rebind)
	_assert(rebind_ok.get("success", false) == true, "TC-F5.4: Rebinding succeeds once capacity is available")
	_assert(tmm_rebind.units.size() == 6, "TC-F5.5: All 6 units created in rebound manager")
	_assert(pam.soldier_count == 6, "TC-F5.6: soldier_count preserved at 6")

	# 6. hardened_outposts genesis remains exactly 2 soldiers with 2 valid tactical units
	var wv_perk := WorldViewScene.instantiate()
	wv_perk.active_perks = ["hardened_outposts"]
	wv_perk.world_seed = 4242
	get_root().add_child(wv_perk)

	var p_pam = wv_perk.get("player_army_mgr")
	var p_tmm = wv_perk.get("tactical_military_mgr")
	_assert(p_pam.soldier_count == 2, "TC-F6.1: hardened_outposts genesis has exactly 2 soldiers")
	_assert(p_tmm.units.size() == 2, "TC-F6.2: hardened_outposts genesis has exactly 2 tactical units")
	_assert(p_pam.movement_state == PlayerArmyManagerScript.MovementState.GARRISONED, "TC-F6.3: State is GARRISONED")

	var save_dict = SaveManagerScript.serialize_world_state(wv_perk)
	var valid_res = SaveManagerScript.validate_save_data(save_dict)
	_assert(valid_res.get("valid", false) == true, "TC-F6.4: Genesis save passes validate_save_data cleanly")

	wv_perk.queue_free()

