extends SceneTree
## Session 1 Batch 1 Automated Verification Suite
## Focus: ID Uniqueness across Save/Load, Atomic Fail-Closed Recall, and Tactical Spawn Allocation

const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")

class MockCongestedTMM extends RefCounted:
	func can_allocate_spawns(_count: int, _rally: Vector2i = Vector2i(-1, -1)) -> bool:
		return false
	func sync_with_player_army() -> void:
		pass
	func get_all_units() -> Array:
		return []

var frame_count: int = 0
var tests_executed: bool = false
var failures: int = 0
var passed_count: int = 0
var world_instance: Node = null

const TEST_SAVE_PATH: String = "user://saves/test_session1_batch1_save.json"

func _assert(condition: bool, test_name: String, details: String = "") -> void:
	if condition:
		passed_count += 1
		print("  [PASS] %s" % test_name)
	else:
		failures += 1
		printerr("  [FAIL] %s - %s" % [test_name, details])

func _init() -> void:
	print("\n========================================================")
	print("  STARTING SESSION 1 BATCH 1 TEST SUITE: IDS & RECALL")
	print("========================================================\n")
	world_instance = WorldViewScene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count >= 3 and not tests_executed:
		tests_executed = true
		_run_all_tests()
	return false

func _run_all_tests() -> void:
	var pam = world_instance.player_army_mgr
	var tmm = world_instance.tactical_military_mgr
	var fsm = world_instance.field_siege_mgr

	print("--- TEST 1: Station Soldier ID Generation & Integrity ---")
	# Setup test barracks to have capacity
	pam.soldier_count = 10
	tmm.sync_with_player_army()
	_assert(pam.soldier_count == 10, "Initial soldier count is 10")
	_assert(tmm.units.size() == 10, "Tactical units synced to 10")

	# Register an outpost in FSM
	var outpost_id := "outpost_test_batch1"
	fsm.register_objective(outpost_id, Vector2i(20, 20), "player", 100.0, 5)

	# Station 2 soldiers
	var res_stat1 = pam.station_soldier(outpost_id, 2)
	_assert(res_stat1.get("success", false), "Station 2 soldiers succeeded")
	_assert(pam.soldier_count == 8, "Reserve decremented to 8")
	_assert(tmm.units.size() == 8, "Tactical units synced to 8")
	var g1 = pam.get_garrison(outpost_id)
	var s_list1: Array = g1.get("soldiers", [])
	_assert(s_list1.size() == 2, "Garrison has 2 soldiers")
	var id1_0: String = s_list1[0].get("soldier_id", "")
	var id1_1: String = s_list1[1].get("soldier_id", "")
	_assert(id1_0 != id1_1, "Stationed soldier IDs are distinct", "%s vs %s" % [id1_0, id1_1])
	print("  Stationed IDs: %s, %s" % [id1_0, id1_1])

	print("\n--- TEST 2: Save, Reload & Recompute Max IDs Past Existing ---")
	# Save world to file
	var save_dict := SaveManagerScript.serialize_world_state(world_instance)
	var save_ok: bool = SaveManagerScript.save_dict_to_file(save_dict, TEST_SAVE_PATH)
	_assert(save_ok, "World saved successfully")

	# Station another soldier on loaded world to test ID uniqueness
	var load_res := SaveManagerScript.load_from_file(TEST_SAVE_PATH)
	_assert(load_res.get("success", false), "World loaded successfully from file")

	# Create fresh world to apply state
	root.remove_child(world_instance)
	world_instance.queue_free()
	var fresh_world = WorldViewScene.instantiate()
	root.add_child(fresh_world)
	SaveManagerScript.apply_loaded_state_to_world(fresh_world, load_res.get("data", {}))

	var fresh_pam = fresh_world.player_army_mgr
	var fresh_tmm = fresh_world.tactical_military_mgr
	_assert(fresh_pam.soldier_count == 8, "Post-load soldier_count is 8")
	_assert(fresh_tmm.units.size() == 8, "Post-load tactical units is 8")

	# Station 1 more soldier on loaded world
	var res_stat2 = fresh_pam.station_soldier(outpost_id, 1)
	_assert(res_stat2.get("success", false), "Station 3rd soldier succeeded post-load")
	var g2 = fresh_pam.get_garrison(outpost_id)
	var s_list2: Array = g2.get("soldiers", [])
	_assert(s_list2.size() == 3, "Garrison now has 3 soldiers")
	var id2_2: String = s_list2[2].get("soldier_id", "")
	_assert(id2_2 != id1_0 and id2_2 != id1_1, "Post-load soldier ID is strictly unique from pre-load IDs", "Got %s vs (%s, %s)" % [id2_2, id1_0, id1_1])
	print("  New Stationed ID: %s" % id2_2)

	print("\n--- TEST 3: Reinforcement Dispatch ID Uniqueness Across Save/Load ---")
	var res_disp1 = fresh_pam.dispatch_reinforcements(outpost_id, 1, 5.0)
	_assert(res_disp1.get("success", false), "Dispatch reinforcement succeeded")
	var reinf_list1: Array = fresh_pam.active_reinforcements
	_assert(reinf_list1.size() == 1, "1 active reinforcement en route")
	var disp_id1: String = reinf_list1[0].get("dispatch_id", "")
	var reinf_soldier_id1: String = reinf_list1[0].get("soldiers", [])[0].get("soldier_id", "")
	print("  Dispatched ID: %s, Soldier: %s" % [disp_id1, reinf_soldier_id1])

	# Save again
	var save_dict2 := SaveManagerScript.serialize_world_state(fresh_world)
	var save_ok2: bool = SaveManagerScript.save_dict_to_file(save_dict2, TEST_SAVE_PATH)
	_assert(save_ok2, "Second world save succeeded")

	# Reload into fresh world
	root.remove_child(fresh_world)
	fresh_world.queue_free()
	var fresh_world2 = WorldViewScene.instantiate()
	root.add_child(fresh_world2)
	var load_res2 := SaveManagerScript.load_from_file(TEST_SAVE_PATH)
	SaveManagerScript.apply_loaded_state_to_world(fresh_world2, load_res2.get("data", {}))

	var pam3 = fresh_world2.player_army_mgr
	# Dispatch another reinforcement
	var res_disp2 = pam3.dispatch_reinforcements(outpost_id, 1, 5.0)
	_assert(res_disp2.get("success", false), "Second dispatch post-load succeeded")
	var reinf_list2: Array = pam3.active_reinforcements
	_assert(reinf_list2.size() == 2, "2 active reinforcements en route")
	var disp_id2: String = reinf_list2[1].get("dispatch_id", "")
	var reinf_soldier_id2: String = reinf_list2[1].get("soldiers", [])[0].get("soldier_id", "")
	_assert(disp_id2 != disp_id1, "Dispatch IDs are strictly unique across save/load", "%s vs %s" % [disp_id2, disp_id1])
	_assert(reinf_soldier_id2 != reinf_soldier_id1 and reinf_soldier_id2 != id1_0 and reinf_soldier_id2 != id2_2, "Reinforcement soldier IDs strictly unique", "%s" % reinf_soldier_id2)
	print("  Second Dispatch ID: %s, Soldier: %s" % [disp_id2, reinf_soldier_id2])

	print("\n--- TEST 4: Atomic Fail-Closed Voluntary Recall on Spawn Congestion ---")
	# Create a mock failing navigation or occupied scenario where can_allocate_spawns returns false
	var mock_blocking_tmm = fresh_world2.tactical_military_mgr
	# Verify normal recall works when cells available
	var cur_res_before = pam3.soldier_count
	var cur_gar_before = pam3.get_garrison_count(outpost_id)
	
	# Mock can_allocate_spawns to return false
	pam3.set_tactical_military_manager(MockCongestedTMM.new())
	var recall_fail = pam3.recall_soldier(outpost_id, 1)
	_assert(recall_fail.get("success", true) == false, "Recall failed closed when base is congested")
	_assert(pam3.soldier_count == cur_res_before, "Soldier count strictly untouched on failed recall", "Expected %d got %d" % [cur_res_before, pam3.soldier_count])
	_assert(pam3.get_garrison_count(outpost_id) == cur_gar_before, "Garrison count strictly untouched on failed recall", "Expected %d got %d" % [cur_gar_before, pam3.get_garrison_count(outpost_id)])

	# Restore real TMM and verify successful recall
	pam3.set_tactical_military_manager(mock_blocking_tmm)
	var recall_ok = pam3.recall_soldier(outpost_id, 1)
	_assert(recall_ok.get("success", false) == true, "Recall succeeded when base cells available")
	_assert(pam3.soldier_count == cur_res_before + 1, "Soldier count incremented by exactly 1")
	_assert(pam3.get_garrison_count(outpost_id) == cur_gar_before - 1, "Garrison count decremented by exactly 1")
	_assert(mock_blocking_tmm.units.size() == pam3.soldier_count, "Tactical units equal soldier_count after successful recall")

	# Clean up test save file
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(TEST_SAVE_PATH)
	if FileAccess.file_exists(TEST_SAVE_PATH + ".bak"):
		DirAccess.remove_absolute(TEST_SAVE_PATH + ".bak")

	print("\n--------------------------------------------------------")
	print("  SESSION 1 BATCH 1 RESULTS: %d Passed, %d Failed" % [passed_count, failures])
	print("--------------------------------------------------------\n")
	quit(0 if failures == 0 else 1)
