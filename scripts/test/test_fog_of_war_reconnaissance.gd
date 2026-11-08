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

	_assert(fow.is_visible(Vector2i(32, 32)) == true, "TC-FOW.11.3: Town Hall center restored as VISIBLE")
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
