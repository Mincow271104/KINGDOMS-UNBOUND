extends SceneTree
## =============================================================================
## KINGDOMS UNBOUND — TEST SUITE: PACKAGE 3B FOG OF WAR & RECONNAISSANCE
## Tests Outpost Vision (Radius 6), Army Passive Reconnaissance, Observer Lifecycle,
## Overlapping Visibility Degradation, POI Discovery, and Save/Load Persistence.
## =============================================================================

const WorldViewScene = preload("res://scenes/world/world_view.tscn")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const FogOfWarScript = preload("res://scripts/world/fog_of_war.gd")
const TacticalUnitScript = preload("res://scripts/military/tactical_unit.gd")
const IsoMathScript = preload("res://scripts/utils/iso_math.gd")
const POIManagerScript = preload("res://scripts/world/poi_manager.gd")
const CitizenControllerScript = preload("res://scripts/entities/citizen_controller.gd")

var frame_count: int = 0
var tests_executed: bool = false
var failures: int = 0
var passed_count: int = 0
var world_instance: Node = null

func _assert(condition: bool, test_name: String, details: String = "") -> void:
	if condition:
		passed_count += 1
		print("  [PASS] %s" % test_name)
	else:
		failures += 1
		printerr("  [FAIL] %s - %s" % [test_name, details])

func _init() -> void:
	print("\n========================================================")
	print("  STARTING PACKAGE 3B FOG OF WAR RECONNAISSANCE TEST SUITE")
	print("========================================================\n")

	world_instance = WorldViewScene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count >= 3 and not tests_executed:
		tests_executed = true
		_run_all_tests()
		_print_summary()
		quit(0 if failures == 0 else 1)
		return true
	return false

func _print_summary() -> void:
	print("\n--------------------------------------------------------")
	print("  PACKAGE 3B TEST RESULTS SUMMARY")
	print("  Passed: %d | Failed: %d" % [passed_count, failures])
	print("--------------------------------------------------------")

func _run_all_tests() -> void:
	_test_tc_fow_01_outpost_manhattan_radius_6()
	_test_tc_fow_02_outpost_excludes_outside_radius_6()
	_test_tc_fow_03_outpost_ownership_transfer()
	_test_tc_fow_04_destroyed_or_removed_outpost()
	_test_tc_fow_05_army_movement_reconnaissance()
	_test_tc_fow_06_no_duplicate_observers()
	_test_tc_fow_07_observer_leaves_cells_explored()
	_test_tc_fow_08_overlapping_observers_preserve_visible()
	_test_tc_fow_09_civilian_explore_unaffected()
	_test_tc_fow_10_save_load_preserves_explored_coordinates()
	_test_tc_fow_11_save_load_rebuilds_visibility_from_observers()
	_test_tc_fow_12_legacy_save_compatibility()
	_test_tc_fow_13_reinforcements_transitions_vision_safety()
	_test_tc_fow_14_enemy_outpost_zero_player_vision()
	_test_tc_fow_15_left_click_unexplored_leak_prevention()
	_test_tc_fow_16_right_click_hostile_targeting_fog_safety()
	_test_tc_fow_17_malformed_save_payload_safety()

# -----------------------------------------------------------------------------
# 1. TC-FOW.01: Outpost reveals cells within Manhattan radius 6
# -----------------------------------------------------------------------------
func _test_tc_fow_01_outpost_manhattan_radius_6() -> void:
	print("\n--- TC-FOW.01: Outpost Manhattan Radius 6 ---")
	var fsm = world_instance.get("field_siege_mgr")
	var fow = world_instance.get("fog_of_war")

	var outpost_center := Vector2i(15, 15)
	var obj = fsm.register_objective("outpost_fow_01", outpost_center, "player", 250.0, 3)
	world_instance.refresh_world_vision()

	_assert(obj != null, "TC-FOW.01.1: Registered player outpost outpost_fow_01")
	_assert(obj.vision_radius == 6, "TC-FOW.01.2: Outpost vision_radius defaults to 6")
	_assert(fow.is_visible(outpost_center), "TC-FOW.01.3: Outpost center is VISIBLE")

	# Cardinal extremities at exact Manhattan distance 6
	_assert(fow.is_visible(Vector2i(15 + 6, 15)), "TC-FOW.01.4: Cardinal East (21, 15) at dist 6 is VISIBLE")
	_assert(fow.is_visible(Vector2i(15 - 6, 15)), "TC-FOW.01.5: Cardinal West (9, 15) at dist 6 is VISIBLE")
	_assert(fow.is_visible(Vector2i(15, 15 + 6)), "TC-FOW.01.6: Cardinal South (15, 21) at dist 6 is VISIBLE")
	_assert(fow.is_visible(Vector2i(15, 15 - 6)), "TC-FOW.01.7: Cardinal North (15, 9) at dist 6 is VISIBLE")

	# Diagonal perimeter points at Manhattan distance 6 (|dx| + |dy| == 6)
	_assert(fow.is_visible(Vector2i(18, 18)), "TC-FOW.01.8: Diagonal (18, 18) [3+3=6] is VISIBLE")
	_assert(fow.is_visible(Vector2i(13, 19)), "TC-FOW.01.9: Diagonal (13, 19) [2+4=6] is VISIBLE")
	_assert(fow.is_visible(Vector2i(19, 13)), "TC-FOW.01.10: Diagonal (19, 13) [4+2=6] is VISIBLE")

# -----------------------------------------------------------------------------
# 2. TC-FOW.02: Outpost does not reveal cells outside radius 6
# -----------------------------------------------------------------------------
func _test_tc_fow_02_outpost_excludes_outside_radius_6() -> void:
	print("\n--- TC-FOW.02: Outpost Excludes Outside Radius 6 ---")
	var fow = world_instance.get("fog_of_war")

	# Cardinal extremities at Manhattan distance 7 (|dx| + |dy| == 7)
	_assert(fow.is_unexplored(Vector2i(15 + 7, 15)), "TC-FOW.02.1: Cardinal East (22, 15) at dist 7 is UNEXPLORED")
	_assert(fow.is_unexplored(Vector2i(15 - 7, 15)), "TC-FOW.02.2: Cardinal West (8, 15) at dist 7 is UNEXPLORED")
	_assert(fow.is_unexplored(Vector2i(15, 15 + 7)), "TC-FOW.02.3: Cardinal South (15, 22) at dist 7 is UNEXPLORED")
	_assert(fow.is_unexplored(Vector2i(15, 15 - 7)), "TC-FOW.02.4: Cardinal North (15, 8) at dist 7 is UNEXPLORED")

	# Diagonal point at Manhattan distance 7 (|4| + |3| == 7)
	_assert(fow.is_unexplored(Vector2i(19, 18)), "TC-FOW.02.5: Diagonal (19, 18) [4+3=7] is UNEXPLORED")
	# Far point at Manhattan distance 10
	_assert(fow.is_unexplored(Vector2i(25, 15)), "TC-FOW.02.6: Far East (25, 15) [dist 10] is UNEXPLORED")

# -----------------------------------------------------------------------------
# 3. TC-FOW.03: Outpost vision updated after ownership transfer
# -----------------------------------------------------------------------------
func _test_tc_fow_03_outpost_ownership_transfer() -> void:
	print("\n--- TC-FOW.03: Outpost Ownership Transfer ---")
	var fsm = world_instance.get("field_siege_mgr")
	var fow = world_instance.get("fog_of_war")

	var outpost_center := Vector2i(15, 15)
	_assert(fow.is_visible(outpost_center), "TC-FOW.03.1: Pre-transfer outpost center is VISIBLE")

	# Transfer to rival_military
	var xfer_res = fsm.transfer_outpost_ownership("outpost_fow_01", "rival_military", "tx_fow_03_loss")
	_assert(xfer_res.get("success", false) == true, "TC-FOW.03.2: Transferred ownership to rival_military")

	# Cells in outpost radius must degrade to EXPLORED (not VISIBLE, and not reverting to UNEXPLORED)
	_assert(fow.get_state(outpost_center) == FogOfWar.State.EXPLORED, "TC-FOW.03.3: Lost outpost center degraded to EXPLORED")
	_assert(not fow.is_visible(outpost_center), "TC-FOW.03.4: Lost outpost center is no longer VISIBLE")
	_assert(fow.is_explored(outpost_center), "TC-FOW.03.5: Lost outpost center remains EXPLORED (not wiped)")
	_assert(fow.get_state(Vector2i(21, 15)) == FogOfWar.State.EXPLORED, "TC-FOW.03.6: Perimeter cell (21, 15) degraded to EXPLORED")

	# Transfer back to player
	var recapture_res = fsm.transfer_outpost_ownership("outpost_fow_01", "player", "tx_fow_03_recapture")
	_assert(recapture_res.get("success", false) == true, "TC-FOW.03.7: Recaptured outpost for player")
	_assert(fow.is_visible(outpost_center), "TC-FOW.03.8: Recaptured outpost center re-elevated to VISIBLE")
	_assert(fow.is_visible(Vector2i(21, 15)), "TC-FOW.03.9: Perimeter cell (21, 15) re-elevated to VISIBLE")

# -----------------------------------------------------------------------------
# 4. TC-FOW.04: Destroyed or removed outposts no longer contribute vision
# -----------------------------------------------------------------------------
func _test_tc_fow_04_destroyed_or_removed_outpost() -> void:
	print("\n--- TC-FOW.04: Destroyed or Removed Outposts ---")
	var fsm = world_instance.get("field_siege_mgr")
	var fow = world_instance.get("fog_of_war")

	var dest_center := Vector2i(45, 15)
	var dest_obj = fsm.register_objective("outpost_fow_dest", dest_center, "player", 250.0, 3)
	world_instance.refresh_world_vision()
	_assert(fow.is_visible(dest_center), "TC-FOW.04.1: Newly registered player outpost is VISIBLE")

	# Destroy the outpost
	dest_obj.is_alive = false
	dest_obj.health = 0.0
	fsm._on_objective_destroyed("outpost_fow_dest", "enemy_attacker")

	_assert(fow.get_state(dest_center) == FogOfWar.State.EXPLORED, "TC-FOW.04.2: Destroyed outpost center degraded to EXPLORED")
	_assert(not fow.is_visible(dest_center), "TC-FOW.04.3: Destroyed outpost center is NOT VISIBLE")

	# Test explicit unregister / removal
	var rem_center := Vector2i(45, 45)
	fsm.register_objective("outpost_fow_rem", rem_center, "player", 250.0, 3)
	world_instance.refresh_world_vision()
	_assert(fow.is_visible(rem_center), "TC-FOW.04.4: Removable outpost is VISIBLE before removal")

	var unreg_res = fsm.unregister_objective("outpost_fow_rem")
	_assert(unreg_res == true, "TC-FOW.04.5: Outpost unregister_objective succeeded")
	_assert(fow.get_state(rem_center) == FogOfWar.State.EXPLORED, "TC-FOW.04.6: Unregistered outpost center degraded to EXPLORED")
	_assert(not fow.is_visible(rem_center), "TC-FOW.04.7: Unregistered outpost center is NOT VISIBLE")

# -----------------------------------------------------------------------------
# 5. TC-FOW.05: Army movement reveals cells through FogOfWar
# -----------------------------------------------------------------------------
func _test_tc_fow_05_army_movement_reconnaissance() -> void:
	print("\n--- TC-FOW.05: Army Movement Reconnaissance ---")
	var tac_mgr = world_instance.get("tactical_military_mgr")
	var fow = world_instance.get("fog_of_war")

	var step_start := Vector2i(20, 40)
	var step_mid := Vector2i(20, 41)
	var step_end := Vector2i(20, 42)

	# Ensure target cells are unexplored initially
	fow.set_state(step_start, FogOfWar.State.UNEXPLORED)
	fow.set_state(step_mid, FogOfWar.State.UNEXPLORED)
	fow.set_state(step_end, FogOfWar.State.UNEXPLORED)
	fow.set_state(Vector2i(20, 46), FogOfWar.State.UNEXPLORED)

	# Create a tactical unit at step_start
	var u = tac_mgr._create_unit_instance("tac_recon_1", step_start)
	tac_mgr.units["tac_recon_1"] = u
	tac_mgr.unit_spawned.emit("tac_recon_1", step_start)

	_assert(fow.is_visible(step_start), "TC-FOW.05.1: Unit spawn cell is VISIBLE")
	_assert(fow.is_visible(Vector2i(20, 44)), "TC-FOW.05.2: Cell at dist 4 (20, 44) is VISIBLE")
	_assert(fow.is_unexplored(Vector2i(20, 46)), "TC-FOW.05.3: Cell at dist 6 (20, 46) is UNEXPLORED")

	# Move unit to step_end via unit_cell_changed
	u.current_cell = step_end
	u.unit_cell_changed.emit("tac_recon_1", step_end)

	_assert(fow.is_visible(step_end), "TC-FOW.05.4: New unit position is VISIBLE")
	_assert(fow.is_visible(Vector2i(20, 46)), "TC-FOW.05.5: Cell (20, 46) [now dist 4 from end] is now VISIBLE")

	# Clean up unit
	tac_mgr._remove_unit("tac_recon_1")

# -----------------------------------------------------------------------------
# 6. TC-FOW.06: Army movement does not create duplicate observers
# -----------------------------------------------------------------------------
func _test_tc_fow_06_no_duplicate_observers() -> void:
	print("\n--- TC-FOW.06: No Duplicate Observers ---")
	var tac_mgr = world_instance.get("tactical_military_mgr")

	var initial_unit_count: int = tac_mgr.get_unit_count()
	var u = tac_mgr._create_unit_instance("tac_dupe_test", Vector2i(25, 25))
	tac_mgr.units["tac_dupe_test"] = u

	# Simulate 10 movement steps
	for i in range(1, 11):
		var next_c := Vector2i(25 + i, 25)
		u.current_cell = next_c
		u.unit_cell_changed.emit("tac_dupe_test", next_c)

	_assert(tac_mgr.get_unit_count() == initial_unit_count + 1, "TC-FOW.06.1: Unit count strictly conserved at +1 after 10 steps")
	_assert(tac_mgr.units.has("tac_dupe_test"), "TC-FOW.06.2: Exactly 1 registered instance for tac_dupe_test")

	tac_mgr._remove_unit("tac_dupe_test")
	_assert(tac_mgr.get_unit_count() == initial_unit_count, "TC-FOW.06.3: Unit count returned to initial after removal")

# -----------------------------------------------------------------------------
# 7. TC-FOW.07: Previously explored cells remain EXPLORED after observer leaves
# -----------------------------------------------------------------------------
func _test_tc_fow_07_observer_leaves_cells_explored() -> void:
	print("\n--- TC-FOW.07: Explored Cells Remain Explored ---")
	var tac_mgr = world_instance.get("tactical_military_mgr")
	var fow = world_instance.get("fog_of_war")

	var cell_a := Vector2i(10, 45)
	var cell_b := Vector2i(10, 60) # 15 tiles away

	var u = tac_mgr._create_unit_instance("tac_leave_test", cell_a)
	tac_mgr.units["tac_leave_test"] = u
	tac_mgr.unit_spawned.emit("tac_leave_test", cell_a)

	_assert(fow.is_visible(cell_a), "TC-FOW.07.1: Cell A is VISIBLE when observer is present")

	# Move observer far away to cell B
	u.current_cell = cell_b
	u.unit_cell_changed.emit("tac_leave_test", cell_b)

	_assert(fow.get_state(cell_a) == FogOfWar.State.EXPLORED, "TC-FOW.07.2: Cell A degraded to EXPLORED")
	_assert(fow.is_explored(cell_a) == true, "TC-FOW.07.3: is_explored(cell_a) is true")
	_assert(fow.is_visible(cell_a) == false, "TC-FOW.07.4: is_visible(cell_a) is false")
	_assert(fow.is_unexplored(cell_a) == false, "TC-FOW.07.5: is_unexplored(cell_a) is false (never reverted)")

	tac_mgr._remove_unit("tac_leave_test")

# -----------------------------------------------------------------------------
# 8. TC-FOW.08: Overlapping observers preserve VISIBLE state
# -----------------------------------------------------------------------------
func _test_tc_fow_08_overlapping_observers_preserve_visible() -> void:
	print("\n--- TC-FOW.08: Overlapping Observers Preserve VISIBLE ---")
	var fsm = world_instance.get("field_siege_mgr")
	var tac_mgr = world_instance.get("tactical_military_mgr")
	var fow = world_instance.get("fog_of_war")

	# Outpost at (30, 20), radius 6 covers up to (34, 20)
	var outpost = fsm.register_objective("outpost_overlap_test", Vector2i(30, 20), "player", 250.0, 3)
	# Tactical unit at (36, 20), radius 4 covers down to (34, 20)
	var u = tac_mgr._create_unit_instance("tac_overlap_test", Vector2i(36, 20))
	tac_mgr.units["tac_overlap_test"] = u

	world_instance.refresh_world_vision()

	var shared_cell := Vector2i(34, 20)
	_assert(fow.is_visible(shared_cell), "TC-FOW.08.1: Shared cell is VISIBLE under dual observers")

	# Move tactical unit far away
	u.current_cell = Vector2i(55, 55)
	u.unit_cell_changed.emit("tac_overlap_test", Vector2i(55, 55))

	_assert(fow.is_visible(shared_cell), "TC-FOW.08.2: Shared cell REMAINS VISIBLE because outpost still observes it")

	# Now transfer outpost away
	fsm.transfer_outpost_ownership("outpost_overlap_test", "rival_merchant", "tx_overlap_loss")

	_assert(fow.get_state(shared_cell) == FogOfWar.State.EXPLORED, "TC-FOW.08.3: Shared cell ONLY degrades to EXPLORED once final observer leaves")
	_assert(not fow.is_visible(shared_cell), "TC-FOW.08.4: Shared cell is no longer VISIBLE")

	tac_mgr._remove_unit("tac_overlap_test")
	fsm.unregister_objective("outpost_overlap_test")

# -----------------------------------------------------------------------------
# 9. TC-FOW.09: Civilian Explore behavior remains unchanged
# -----------------------------------------------------------------------------
func _test_tc_fow_09_civilian_explore_unaffected() -> void:
	print("\n--- TC-FOW.09: Civilian Explore Unaffected ---")
	var poi_mgr = world_instance.get("poi_mgr")
	var fow = world_instance.get("fog_of_war")
	var cit_list = world_instance.get("citizen_list")

	_assert(not cit_list.is_empty(), "TC-FOW.09.1: Living citizens exist in world")
	var cit = cit_list[0]

	var all_pois = poi_mgr.get_all_pois()
	_assert(not all_pois.is_empty(), "TC-FOW.09.2: POIs exist in world")

	var test_poi = all_pois[0]
	var cmd_res = cit.issue_manual_command("explore", test_poi.cell, test_poi.id)
	_assert(cmd_res.get("success", false) == true or cmd_res.get("reason", "") != "Loại lệnh không hợp lệ: explore", "TC-FOW.09.3: CitizenController accepts explore command")

	fow.reveal_circle(test_poi.cell, 2)
	var newly_disc = poi_mgr.update_discovery(fow)

	_assert(test_poi.state == POIManagerScript.POIState.DISCOVERED, "TC-FOW.09.4: POI discovered cleanly via FogOfWar update")

# -----------------------------------------------------------------------------
# 10. TC-FOW.10: Save/Load preserves explored coordinates
# -----------------------------------------------------------------------------
func _test_tc_fow_10_save_load_preserves_explored_coordinates() -> void:
	print("\n--- TC-FOW.10: Save/Load Preserves Explored Coordinates ---")
	var test_slot := "user://saves/test_fow_persistence.json"
	var fow = world_instance.get("fog_of_war")

	# Mark a distinct coordinate as explored
	var probe_cell := Vector2i(2, 2)
	fow.set_state(probe_cell, FogOfWar.State.EXPLORED)

	var save_res = SaveManagerScript.save_to_file(world_instance, test_slot)
	_assert(save_res.get("success", false) == true, "TC-FOW.10.1: SaveManager saved world state")

	var load_res = SaveManagerScript.load_from_file(test_slot)
	_assert(load_res.get("success", false) == true, "TC-FOW.10.2: SaveManager loaded world state")
	var loaded_data: Dictionary = load_res.get("data", {})

	var saved_fow: Array = loaded_data.get("fog_of_war", [])
	var found_probe := false
	for pt in saved_fow:
		if pt is Array and pt.size() >= 2 and int(pt[0]) == probe_cell.x and int(pt[1]) == probe_cell.y:
			found_probe = true
			break
	_assert(found_probe == true, "TC-FOW.10.3: Saved fog_of_war array contains probe cell [2, 2]")

	# Apply loaded state back to world
	var apply_res = SaveManagerScript.apply_loaded_state_to_world(world_instance, loaded_data)
	_assert(apply_res.get("success", false) == true, "TC-FOW.10.4: apply_loaded_state_to_world returned success")
	_assert(fow.is_explored(probe_cell) == true, "TC-FOW.10.5: Restored fog_of_war preserves explored probe cell")

	if FileAccess.file_exists(test_slot):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_slot))

# -----------------------------------------------------------------------------
# 11. TC-FOW.11: Save/Load rebuilds current visibility from valid observers
# -----------------------------------------------------------------------------
func _test_tc_fow_11_save_load_rebuilds_visibility_from_observers() -> void:
	print("\n--- TC-FOW.11: Save/Load Rebuilds Visibility From Observers ---")
	var fsm = world_instance.get("field_siege_mgr")
	var fow = world_instance.get("fog_of_war")
	var test_slot := "user://saves/test_fow_rebuild_vis.json"

	var out_c := Vector2i(18, 18)
	fsm.register_objective("outpost_persist_vis", out_c, "player", 250.0, 3)
	world_instance.refresh_world_vision()

	var save_res = SaveManagerScript.save_to_file(world_instance, test_slot)
	_assert(save_res.get("success", false) == true, "TC-FOW.11.1: Saved world with active outpost")

	var load_res = SaveManagerScript.load_from_file(test_slot)
	var apply_res = SaveManagerScript.apply_loaded_state_to_world(world_instance, load_res.get("data", {}))
	_assert(apply_res.get("success", false) == true, "TC-FOW.11.2: Restored world from save")

	var th_center: Vector2i = world_instance.world_data.center_spawn if world_instance.world_data != null else Vector2i(32, 32)
	_assert(fow.is_visible(th_center) == true, "TC-FOW.11.3: Town Hall center restored as VISIBLE")
	_assert(fow.is_visible(out_c) == true, "TC-FOW.11.4: Restored player outpost is VISIBLE")
	_assert(fow.is_visible(Vector2i(out_c.x + 6, out_c.y)) == true, "TC-FOW.11.5: Outpost perimeter (dist 6) restored as VISIBLE")

	fsm.unregister_objective("outpost_persist_vis")
	if FileAccess.file_exists(test_slot):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_slot))

# -----------------------------------------------------------------------------
# 12. TC-FOW.12: Legacy saves without Package 3B fields remain compatible
# -----------------------------------------------------------------------------
func _test_tc_fow_12_legacy_save_compatibility() -> void:
	print("\n--- TC-FOW.12: Legacy Save Compatibility ---")
	var fsm = world_instance.get("field_siege_mgr")
	var fow = world_instance.get("fog_of_war")

	# Construct a synthetic legacy save slice where objective lacks vision_radius
	var legacy_obj_data: Dictionary = {
		"objective_id": "outpost_legacy_no_vr",
		"objective_name": "Tiền Đồn Cũ",
		"owning_faction_id": "player",
		"current_cell": [22, 22],
		"health": 250.0,
		"max_health": 250.0,
		"is_alive": true
		# Omitted: vision_radius
	}

	var actor = fsm.register_objective("outpost_legacy_no_vr", Vector2i(22, 22), "player", 250.0, 3)
	var des_ok = actor.deserialize(legacy_obj_data)
	_assert(des_ok == true, "TC-FOW.12.1: Legacy objective deserialized successfully")
	_assert(actor.vision_radius == 6, "TC-FOW.12.2: Missing vision_radius defaulted to 6")

	world_instance.refresh_world_vision()
	_assert(fow.is_visible(Vector2i(22, 22)) == true, "TC-FOW.12.3: Legacy objective center is VISIBLE")
	_assert(fow.is_visible(Vector2i(28, 22)) == true, "TC-FOW.12.4: Legacy objective dist 6 perimeter is VISIBLE")

	fsm.unregister_objective("outpost_legacy_no_vr")

# -----------------------------------------------------------------------------
# 13. TC-FOW.13: Reinforcement transitions do not leak or duplicate vision
# -----------------------------------------------------------------------------
func _test_tc_fow_13_reinforcements_transitions_vision_safety() -> void:
	print("\n--- TC-FOW.13: Reinforcement Transitions Vision Safety ---")
	var pam = world_instance.get("player_army_mgr")
	var fsm = world_instance.get("field_siege_mgr")
	var fow = world_instance.get("fog_of_war")

	var out_c := Vector2i(14, 30)
	fsm.register_objective("outpost_reinf_vis", out_c, "player", 250.0, 3)
	pam.soldier_count = 10

	# Station 1 soldier
	var stat_res = pam.station_soldier("outpost_reinf_vis", 1)
	_assert(stat_res.get("success", false) == true, "TC-FOW.13.1: Stationed 1 soldier")
	world_instance.refresh_world_vision()
	_assert(fow.is_visible(out_c) == true, "TC-FOW.13.2: Outpost vision holds at center")
	_assert(fow.is_unexplored(Vector2i(out_c.x + 8, out_c.y)) == true, "TC-FOW.13.3: No phantom vision leaked beyond radius 6")

	# Dispatch reinforcements (travel_hours: 3.0)
	var disp_res = pam.dispatch_reinforcements("outpost_reinf_vis", 1, 3.0)
	_assert(disp_res.get("success", false) == true, "TC-FOW.13.4: Reinforcements dispatched")
	world_instance.refresh_world_vision()
	# Cell halfway across map between base and outpost (21, 30) is dist 7 from outpost and dist 13 from Town Hall
	_assert(fow.is_unexplored(Vector2i(21, 30)) == true, "TC-FOW.13.5: In-transit soldiers do NOT leak vision across map")

	# Advance arrival
	pam.advance_reinforcements(3.5)
	_assert(pam.get_in_transit_count("outpost_reinf_vis") == 0, "TC-FOW.13.6: Reinforcements arrived")
	world_instance.refresh_world_vision()
	_assert(fow.is_visible(out_c) == true, "TC-FOW.13.7: Outpost remains VISIBLE after arrival")

	# Recall soldiers
	var rec_res = pam.recall_soldier("outpost_reinf_vis", 1)
	_assert(rec_res.get("success", false) == true, "TC-FOW.13.8: Recalled soldier to base")
	world_instance.refresh_world_vision()
	_assert(fow.is_visible(out_c) == true, "TC-FOW.13.9: Outpost remains VISIBLE (outpost structure provides vision)")

	fsm.unregister_objective("outpost_reinf_vis")

# -----------------------------------------------------------------------------
# 14. TC-FOW.14: Enemy outpost grants zero player vision
# -----------------------------------------------------------------------------
func _test_tc_fow_14_enemy_outpost_zero_player_vision() -> void:
	print("\n--- TC-FOW.14: Enemy Outpost Zero Player Vision ---")
	var fsm = world_instance.get("field_siege_mgr")
	var fow = world_instance.get("fog_of_war")

	var enemy_c := Vector2i(5, 55)
	fow.set_state(enemy_c, FogOfWar.State.UNEXPLORED)
	fow.set_state(Vector2i(5, 56), FogOfWar.State.UNEXPLORED)
	fow.set_state(Vector2i(5, 54), FogOfWar.State.UNEXPLORED)

	var enemy_obj = fsm.register_objective("outpost_enemy_test", enemy_c, "rival_military", 300.0, 4)
	world_instance.refresh_world_vision()

	_assert(enemy_obj != null, "TC-FOW.14.1: Registered enemy outpost")
	_assert(enemy_obj.owning_faction_id == "rival_military", "TC-FOW.14.2: Owner is rival_military")
	_assert(fow.is_unexplored(enemy_c) == true, "TC-FOW.14.3: Enemy outpost center remains strictly UNEXPLORED")
	_assert(fow.is_unexplored(Vector2i(5, 56)) == true, "TC-FOW.14.4: Enemy outpost adjacent cell remains UNEXPLORED")
	_assert(not fow.is_visible(enemy_c), "TC-FOW.14.5: Enemy outpost grants ZERO player vision")

	fsm.unregister_objective("outpost_enemy_test")

# -----------------------------------------------------------------------------
# Test Double for Tactical Military Input Order Spying
# -----------------------------------------------------------------------------
class TacticalSpyDouble extends TacticalMilitaryManager:
	var issue_attack_order_calls: int = 0
	var issue_move_order_calls: int = 0
	var last_attack_target: Node = null
	var last_move_cell: Vector2i = Vector2i(-1, -1)

	func issue_attack_order(target: Node, nav: GridNavigation = null) -> Dictionary:
		issue_attack_order_calls += 1
		last_attack_target = target
		return {"success": true}

	func issue_move_order(target_cell: Vector2i, nav: GridNavigation = null) -> Dictionary:
		issue_move_order_calls += 1
		last_move_cell = target_cell
		return {"success": true}

# -----------------------------------------------------------------------------
# 15. TC-FOW.15: AUD-3B-01 Left-Click Unexplored Fog Information Leak Prevention
# -----------------------------------------------------------------------------
func _test_tc_fow_15_left_click_unexplored_leak_prevention() -> void:
	print("\n--- TC-FOW.15: Left-Click Unexplored Fog Information Leak Prevention (AUD-3B-01) ---")
	var fsm = world_instance.get("field_siege_mgr")
	var fow = world_instance.get("fog_of_war")
	var hud = world_instance.get("hud")

	var inspect_cell := Vector2i(44, 44)
	fow.set_state(inspect_cell, FogOfWar.State.UNEXPLORED)
	fow.set_state(inspect_cell + Vector2i(1, 0), FogOfWar.State.UNEXPLORED)
	fow.set_state(inspect_cell + Vector2i(0, 1), FogOfWar.State.UNEXPLORED)
	fow.set_state(inspect_cell + Vector2i(1, 1), FogOfWar.State.UNEXPLORED)

	# Register a hidden building at inspect_cell
	var b_data := {
		"id": "bld_leak_test_mine",
		"type": "mine",
		"cell": inspect_cell,
		"size": Vector2i(2, 2),
		"state": "active"
	}
	world_instance.world_data.buildings.append(b_data)

	# Register a hidden hostile outpost at inspect_cell
	var leak_obj = fsm.register_objective("outpost_leak_obj", inspect_cell, "rival_military", 250.0, 3)
	world_instance.refresh_world_vision()

	_assert(fow.is_unexplored(inspect_cell) == true, "TC-FOW.15.1: Target cell is UNEXPLORED")

	# Subcase 1: Direct _handle_left_click on UNEXPLORED cell must fail closed
	world_instance.clear_building_selection()
	world_instance._handle_left_click(inspect_cell)
	_assert(world_instance.selected_building_id == "", "TC-FOW.15.2: Left-click on UNEXPLORED cell does not select hidden building or outpost")
	_assert(hud == null or not hud.has_method("get_inspected_citizen") or hud.get_inspected_citizen() == null, "TC-FOW.15.3: Left-click on UNEXPLORED cell does not inspect citizen")

	# Subcase 2: Synthetic InputEventMouseButton left-click on UNEXPLORED cell must fail closed
	var mb_down := InputEventMouseButton.new()
	mb_down.button_index = MOUSE_BUTTON_LEFT
	mb_down.pressed = true
	mb_down.set_meta("target_cell", inspect_cell)
	world_instance._unhandled_input(mb_down)
	var mb_up := InputEventMouseButton.new()
	mb_up.button_index = MOUSE_BUTTON_LEFT
	mb_up.pressed = false
	mb_up.set_meta("target_cell", inspect_cell)
	world_instance._unhandled_input(mb_up)
	_assert(world_instance.selected_building_id == "", "TC-FOW.15.4: Synthetic left-click event on UNEXPLORED cell leaks zero selection")

	# Subcase 3: Explored cell legitimately selects the entity
	fow.set_state(inspect_cell, FogOfWar.State.EXPLORED)
	world_instance._handle_left_click(inspect_cell)
	_assert(world_instance.selected_building_id != "", "TC-FOW.15.5: Left-click on EXPLORED cell legitimately selects entity")
	_assert(world_instance.selected_building_id == "outpost_leak_obj" or world_instance.selected_building_id == "bld_leak_test_mine", "TC-FOW.15.6: Selected entity matches expected target ID")

	# Subcase 4: Fail closed when fog_of_war is null
	world_instance.fog_of_war = null
	world_instance.selected_building_id = "stale_bld_id"
	world_instance._handle_left_click(inspect_cell)
	_assert(world_instance.selected_building_id == "", "TC-FOW.15.7: Left-click with null fog_of_war fails closed and clears selection")
	world_instance.fog_of_war = fow

	# Subcase 5: Safe unrelated UI clicks on empty cell
	var empty_cell := Vector2i(1, 1)
	fow.set_state(empty_cell, FogOfWar.State.EXPLORED)
	world_instance.selected_building_id = "stale_bld_id"
	world_instance._handle_left_click(empty_cell)
	_assert(world_instance.selected_building_id == "", "TC-FOW.15.8: Left-click on empty cell deselects cleanly without error")

	# Teardown
	fsm.unregister_objective("outpost_leak_obj")
	world_instance.world_data.buildings.erase(b_data)
	world_instance.clear_building_selection()

# -----------------------------------------------------------------------------
# 16. TC-FOW.16: AUD-3B-01 Right-Click Hostile Targeting Fog Safety
# -----------------------------------------------------------------------------
func _test_tc_fow_16_right_click_hostile_targeting_fog_safety() -> void:
	print("\n--- TC-FOW.16: Right-Click Hostile Targeting Fog Safety (AUD-3B-01) ---")
	var pam = world_instance.get("player_army_mgr")
	var real_tac = world_instance.get("tactical_military_mgr")
	var fsm = world_instance.get("field_siege_mgr")
	var fow = world_instance.get("fog_of_war")
	var emm = world_instance.get("enemy_military_mgr")

	var spy_tac := TacticalSpyDouble.new(world_instance, pam)
	spy_tac.set_world_view(world_instance)
	spy_tac.set_player_army_manager(pam)
	world_instance.set("tactical_military_mgr", spy_tac)
	pam.set_tactical_military_manager(spy_tac)

	pam.soldier_count = 3
	spy_tac.sync_with_player_army()
	spy_tac.select_all()
	_assert(spy_tac.get_selected_count() > 0, "TC-FOW.16.1: Tactical units selected for order tests")

	var hostile_cell := Vector2i(48, 48)
	var enemy_u = emm.spawn_enemy_unit("rival_military", hostile_cell, "enemy_fow_test_unit")
	_assert(enemy_u != null, "TC-FOW.16.2: Spawned enemy unit at hostile_cell")

	var outpost_cell := Vector2i(46, 46)
	var enemy_obj = fsm.register_objective("enemy_outpost_fow_test", outpost_cell, "rival_military", 250.0, 3)
	_assert(enemy_obj != null, "TC-FOW.16.3: Registered enemy siege objective at outpost_cell")
	# Register active siege so right clicking on visible outpost directly dispatches attack order
	fsm.active_sieges["test_siege_fow"] = {
		"siege_id": "test_siege_fow",
		"objective_id": "enemy_outpost_fow_test",
		"attacker_faction_id": "player",
		"defender_faction_id": "rival_military",
		"status": "active"
	}

	# --- Part A: Enemy Tactical Unit ---
	# Subcase 1: Target unit cell is UNEXPLORED
	fow.set_state(hostile_cell, FogOfWar.State.UNEXPLORED)
	spy_tac.issue_attack_order_calls = 0
	spy_tac.issue_move_order_calls = 0
	var mb_unit := InputEventMouseButton.new()
	mb_unit.button_index = MOUSE_BUTTON_RIGHT
	mb_unit.pressed = true
	mb_unit.set_meta("target_cell", hostile_cell)
	world_instance._unhandled_input(mb_unit)
	_assert(spy_tac.issue_attack_order_calls == 0, "TC-FOW.16.4: In UNEXPLORED fog, attack order is NOT dispatched to hidden enemy unit")
	_assert(spy_tac.issue_move_order_calls == 1, "TC-FOW.16.5: In UNEXPLORED fog, safe move order is issued instead")
	_assert(spy_tac.last_move_cell == hostile_cell, "TC-FOW.16.6: Safe move order targets the clicked cell")

	# Subcase 2: Target unit cell is EXPLORED but not VISIBLE
	fow.set_state(hostile_cell, FogOfWar.State.EXPLORED)
	_assert(not fow.is_visible(hostile_cell), "TC-FOW.16.7: Unit cell is EXPLORED but NOT VISIBLE")
	spy_tac.issue_attack_order_calls = 0
	spy_tac.issue_move_order_calls = 0
	world_instance._unhandled_input(mb_unit)
	_assert(spy_tac.issue_attack_order_calls == 0, "TC-FOW.16.8: In EXPLORED-only fog, attack order is NOT dispatched to non-visible enemy unit")
	_assert(spy_tac.issue_move_order_calls == 1, "TC-FOW.16.9: In EXPLORED-only fog, safe move order is issued instead")

	# Subcase 3: Target unit cell is VISIBLE
	fow.set_state(hostile_cell, FogOfWar.State.VISIBLE)
	_assert(fow.is_visible(hostile_cell), "TC-FOW.16.10: Unit cell is actively VISIBLE")
	spy_tac.issue_attack_order_calls = 0
	spy_tac.issue_move_order_calls = 0
	world_instance._unhandled_input(mb_unit)
	_assert(spy_tac.issue_attack_order_calls == 1, "TC-FOW.16.11: When unit cell is VISIBLE, attack order IS dispatched to enemy unit")
	_assert(spy_tac.last_attack_target == enemy_u, "TC-FOW.16.12: Attack target matches visible enemy unit")

	# Subcase 4: Target unit cell with null fog_of_war (fail-closed)
	world_instance.fog_of_war = null
	spy_tac.issue_attack_order_calls = 0
	spy_tac.issue_move_order_calls = 0
	world_instance._unhandled_input(mb_unit)
	_assert(spy_tac.issue_attack_order_calls == 0, "TC-FOW.16.13: With null fog_of_war, attack order is NOT dispatched against unit")
	_assert(spy_tac.issue_move_order_calls == 1, "TC-FOW.16.14: With null fog_of_war, falls through to safe move order")
	world_instance.fog_of_war = fow

	# --- Part B: Enemy Siege Objective Outpost ---
	var mb_obj := InputEventMouseButton.new()
	mb_obj.button_index = MOUSE_BUTTON_RIGHT
	mb_obj.pressed = true
	mb_obj.set_meta("target_cell", outpost_cell)

	# Subcase 5: Target outpost cell is UNEXPLORED
	fow.set_state(outpost_cell, FogOfWar.State.UNEXPLORED)
	spy_tac.issue_attack_order_calls = 0
	spy_tac.issue_move_order_calls = 0
	world_instance._unhandled_input(mb_obj)
	_assert(spy_tac.issue_attack_order_calls == 0, "TC-FOW.16.15: In UNEXPLORED fog, attack order is NOT dispatched to hidden outpost")
	_assert(spy_tac.issue_move_order_calls == 1, "TC-FOW.16.16: In UNEXPLORED fog, safe move order is issued instead of siege attack")

	# Subcase 6: Target outpost cell is EXPLORED but not VISIBLE
	fow.set_state(outpost_cell, FogOfWar.State.EXPLORED)
	_assert(not fow.is_visible(outpost_cell), "TC-FOW.16.17: Outpost cell is EXPLORED but NOT VISIBLE")
	spy_tac.issue_attack_order_calls = 0
	spy_tac.issue_move_order_calls = 0
	world_instance._unhandled_input(mb_obj)
	_assert(spy_tac.issue_attack_order_calls == 0, "TC-FOW.16.18: In EXPLORED-only fog, attack order is NOT dispatched to non-visible outpost")
	_assert(spy_tac.issue_move_order_calls == 1, "TC-FOW.16.19: In EXPLORED-only fog, safe move order is issued instead")

	# Subcase 7: Target outpost cell is VISIBLE
	fow.set_state(outpost_cell, FogOfWar.State.VISIBLE)
	_assert(fow.is_visible(outpost_cell), "TC-FOW.16.20: Outpost cell is actively VISIBLE")
	spy_tac.issue_attack_order_calls = 0
	spy_tac.issue_move_order_calls = 0
	world_instance._unhandled_input(mb_obj)
	_assert(spy_tac.issue_attack_order_calls == 1, "TC-FOW.16.21: When outpost cell is VISIBLE, attack order IS dispatched to siege objective")
	_assert(spy_tac.last_attack_target == enemy_obj, "TC-FOW.16.22: Attack target matches visible siege objective")

	# Subcase 8: Target outpost cell with null fog_of_war (fail-closed)
	world_instance.fog_of_war = null
	spy_tac.issue_attack_order_calls = 0
	spy_tac.issue_move_order_calls = 0
	world_instance._unhandled_input(mb_obj)
	_assert(spy_tac.issue_attack_order_calls == 0, "TC-FOW.16.23: With null fog_of_war, siege attack fails closed")
	_assert(spy_tac.issue_move_order_calls == 1, "TC-FOW.16.24: With null fog_of_war, falls through to safe move order")
	world_instance.fog_of_war = fow

	# Teardown
	fsm.active_sieges.erase("test_siege_fow")
	fsm.unregister_objective("enemy_outpost_fow_test")
	emm.remove_enemy("enemy_fow_test_unit")
	world_instance.set("tactical_military_mgr", real_tac)
	pam.set_tactical_military_manager(real_tac)

# -----------------------------------------------------------------------------
# 17. TC-FOW.17: AUD-3B-02 Malformed Save Payload Validation and Safety
# -----------------------------------------------------------------------------
func _test_tc_fow_17_malformed_save_payload_safety() -> void:
	print("\n--- TC-FOW.17: Malformed Save Payload Validation and Safety (AUD-3B-02) ---")
	var test_slot := "user://saves/test_fow_malformed_suite.json"
	var save_res = SaveManagerScript.save_to_file(world_instance, test_slot)
	_assert(save_res.get("success", false) == true, "TC-FOW.17.0a: Generated baseline valid save file")
	var load_res = SaveManagerScript.load_from_file(test_slot)
	_assert(load_res.get("success", false) == true, "TC-FOW.17.0b: Loaded baseline valid save file")
	var base_dict: Dictionary = load_res.get("data", {}).duplicate(true)

	# Case 1: Missing fog_of_war key (legacy save compatibility)
	var c1 = base_dict.duplicate(true)
	c1.erase("fog_of_war")
	var val_c1 = SaveManagerScript.validate_save_data(c1)
	_assert(val_c1.get("valid", false) == true, "TC-FOW.17.1: Missing 'fog_of_war' key is accepted as valid legacy save")

	# Case 2: Valid non-empty Array
	var c2 = base_dict.duplicate(true)
	c2["fog_of_war"] = [[10, 10], [12, 12]]
	var val_c2 = SaveManagerScript.validate_save_data(c2)
	_assert(val_c2.get("valid", false) == true, "TC-FOW.17.2: Valid non-empty coordinates array is accepted")

	# Case 3: Valid empty Array
	var c3 = base_dict.duplicate(true)
	c3["fog_of_war"] = []
	var val_c3 = SaveManagerScript.validate_save_data(c3)
	_assert(val_c3.get("valid", false) == true, "TC-FOW.17.3: Valid empty array is accepted")

	# Case 4: Malformed Array elements
	var c4 = base_dict.duplicate(true)
	c4["fog_of_war"] = ["bad_coordinate", [999, 999]]
	var val_c4 = SaveManagerScript.validate_save_data(c4)
	_assert(val_c4.get("valid", true) == false, "TC-FOW.17.4: Malformed array elements rejected by validate_save_data")

	# Case 5: Integer payload
	var c5 = base_dict.duplicate(true)
	c5["fog_of_war"] = 42
	var val_c5 = SaveManagerScript.validate_save_data(c5)
	_assert(val_c5.get("valid", true) == false, "TC-FOW.17.5: Integer payload rejected by validate_save_data")

	# Case 6: Dictionary payload
	var c6 = base_dict.duplicate(true)
	c6["fog_of_war"] = {"coords": []}
	var val_c6 = SaveManagerScript.validate_save_data(c6)
	_assert(val_c6.get("valid", true) == false, "TC-FOW.17.6: Dictionary payload rejected by validate_save_data")

	# Case 7: Null payload
	var c7 = base_dict.duplicate(true)
	c7["fog_of_war"] = null
	var val_c7 = SaveManagerScript.validate_save_data(c7)
	_assert(val_c7.get("valid", true) == false, "TC-FOW.17.7: Null payload rejected by validate_save_data")

	# Case 8: Atomic load rejection (malformed file load does not mutate live world state)
	var malformed_slot := "user://saves/test_fow_malformed_reject.json"
	var f := FileAccess.open(malformed_slot, FileAccess.WRITE)
	f.store_string(JSON.stringify(c5, "\t"))
	f.close()

	var pre_cit_count: int = world_instance.citizen_list.size()
	var pre_mods: Array = world_instance.world_modifiers.duplicate()
	var load_reject = SaveManagerScript.load_from_file(malformed_slot)
	_assert(load_reject.get("success", true) == false, "TC-FOW.17.8: load_from_file atomically rejected malformed save")
	_assert(world_instance.citizen_list.size() == pre_cit_count, "TC-FOW.17.9: Live citizens count unmutated after rejection")
	_assert(world_instance.world_modifiers == pre_mods, "TC-FOW.17.10: Live world modifiers unmutated after rejection")

	# Case 9: Direct apply_loaded_state_to_world with non-array payload safely rejected without crash
	var direct_app = SaveManagerScript.apply_loaded_state_to_world(world_instance, c5)
	_assert(direct_app.get("success", true) == false, "TC-FOW.17.11: Direct apply_loaded_state_to_world with integer payload safely rejected")
	_assert(world_instance.world_modifiers == pre_mods, "TC-FOW.17.12: Live world modifiers preserved through direct rejection")

	# Cleanup temporary files
	if FileAccess.file_exists(test_slot):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_slot))
	if FileAccess.file_exists(malformed_slot):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(malformed_slot))
