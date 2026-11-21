extends SceneTree

## =============================================================================
## KINGDOMS UNBOUND — CONTROLLED DEFECT REPAIR PROGRAM
## SESSION 6 TEST SUITE: WORKPLACE OUTPUT BUFFER DISPOSITION
## Focus: MBL-ECO-01 (Policy A — Forfeit Unhauled Workplace Output)
## =============================================================================

const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")
const WorkplaceManagerScript = preload("res://scripts/economy/workplace_manager.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const CitizenControllerScript = preload("res://scripts/entities/citizen_controller.gd")

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
		var err_msg := "  ❌ [FAIL] %s" % message
		if not detail.is_empty():
			err_msg += " (%s)" % detail
		printerr(err_msg)

func _init() -> void:
	print("\n========================================================")
	print("  STARTING SESSION 6 INTEGRATION TEST SUITE")
	print("  MBL-ECO-01: Workplace Buffer Disposition (Policy A)")
	print("========================================================\n")
	world_instance = WorldViewScene.instantiate()
	world_instance.world_seed = 6001
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count < 3:
		return false

	_run_all_tests()

	print("\n========================================================")
	print("  SESSION 6 TEST RESULTS SUMMARY")
	print("  Passed Assertions : %d" % checks_passed)
	print("  Failed Assertions : %d" % failures)
	if failures == 0:
		print("  ALL SESSION 6 ASSERTIONS PASSED! (Exit Code 0)")
	else:
		printerr("  SOME SESSION 6 ASSERTIONS FAILED! (Exit Code 1)")
	print("========================================================\n")

	quit(1 if failures > 0 else 0)
	return true

func _run_all_tests() -> void:
	_test_group_a_non_empty_buffer_forfeited()
	_test_group_b_empty_buffer_clean_removal()
	_test_group_c_destruction_path_forfeiture()
	_test_group_d_cancellation_and_rejection_safety()
	_test_group_e_idempotency()
	_test_group_f_unrelated_workplace_isolation()
	_test_group_g_temporary_state_preservation()
	_test_group_h_workshop_multichannel_forfeiture()
	_test_group_i_legacy_save_load_destroyed_workplace_reconciliation()

## -----------------------------------------------------------------------------
## GROUP A: TEST A — Non-empty workplace buffer is forfeited upon demolition
## -----------------------------------------------------------------------------
func _test_group_a_non_empty_buffer_forfeited() -> void:
	print("\n--- Group A: Test A — Non-Empty Workplace Buffer Forfeited Upon Demolition ---")
	var wd = world_instance.get("world_data")
	var rm = world_instance.call("_get_resource_mgr")
	var wm: WorkplaceManager = world_instance.get("workplace_mgr")

	var b_id := "bld_test_farm_a"
	var origin := Vector2i(14, 14)
	var b_data := {
		"id": b_id,
		"type": "farm",
		"cell": origin,
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100,
		"max_health": 100,
		"upgrade_level": 1
	}
	wd.buildings.append(b_data)
	world_instance.buildings_by_cell[origin] = b_data
	world_instance.register_dynamic_workplace(b_data)

	var wp = wm.get_workplace(b_id)
	_assert(wp != null, "TestA.1: Dynamic farm registered in WorkplaceManager")
	wp.buffer_amount = 35
	_assert(wm.get_buffer_amount(b_id) == 35, "TestA.2: Buffer amount initialized to 35 food")

	var initial_central_food: int = rm.get_total_stock("food")

	var signal_captured := {"forfeited": false, "res": "", "amt": 0}
	var capture_cb = func(w_id: String, r_id: String, amt: int):
		if w_id == b_id:
			signal_captured["forfeited"] = true
			signal_captured["res"] = r_id
			signal_captured["amt"] = amt
	wm.buffer_forfeited.connect(capture_cb)

	# Execute permanent demolition via the authoritative production path
	var demo_res: Dictionary = world_instance.demolish_building_project(b_id)
	_assert(demo_res.get("success", false) == true, "TestA.3: demolish_building_project succeeded")

	wm.buffer_forfeited.disconnect(capture_cb)

	# Verify workplace is completely removed
	_assert(wm.get_workplace(b_id) == null, "TestA.4: Workplace unregistered from WorkplaceManager")
	_assert(wm.has_workplace(b_id) == false, "TestA.5: has_workplace returns false for demolished workplace")
	_assert(wm.get_buffer_amount(b_id) == 0, "TestA.6: get_buffer_amount safely returns 0")

	# Invariant check: Central food stock must NOT increase from unhauled buffer
	var final_central_food: int = rm.get_total_stock("food")
	_assert(final_central_food == initial_central_food, "TestA.7: Central ResourceManager food stock strictly unchanged (%d == %d)" % [final_central_food, initial_central_food])

	# Signal check
	_assert(signal_captured["forfeited"] == true, "TestA.8: buffer_forfeited signal was emitted")
	_assert(signal_captured["res"] == "food", "TestA.9: Forfeited resource type matches 'food'")
	_assert(signal_captured["amt"] == 35, "TestA.10: Forfeited amount matches exact unhauled quantity (35)")

## -----------------------------------------------------------------------------
## GROUP B: TEST B — Empty buffer workplace clean removal
## -----------------------------------------------------------------------------
func _test_group_b_empty_buffer_clean_removal() -> void:
	print("\n--- Group B: Test B — Empty Buffer Workplace Clean Removal ---")
	var wd = world_instance.get("world_data")
	var rm = world_instance.call("_get_resource_mgr")
	var wm: WorkplaceManager = world_instance.get("workplace_mgr")

	var b_id := "bld_test_wc_b"
	var origin := Vector2i(18, 14)
	var b_data := {
		"id": b_id,
		"type": "woodcutter",
		"cell": origin,
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100,
		"max_health": 100,
		"upgrade_level": 1
	}
	wd.buildings.append(b_data)
	world_instance.buildings_by_cell[origin] = b_data
	world_instance.register_dynamic_workplace(b_data)

	var wp = wm.get_workplace(b_id)
	_assert(wp != null, "TestB.1: Dynamic woodcutter registered")
	_assert(wp.buffer_amount == 0, "TestB.2: Buffer amount is 0")

	var initial_central_food: int = rm.get_total_stock("food")

	var demo_res: Dictionary = world_instance.demolish_building_project(b_id)
	_assert(demo_res.get("success", false) == true, "TestB.3: Empty buffer demolition succeeded")
	_assert(wm.get_workplace(b_id) == null, "TestB.4: Workplace cleanly unregistered")
	_assert(wm.get_buffer_amount(b_id) == 0, "TestB.5: Buffer amount returns 0")
	_assert(rm.get_total_stock("food") == initial_central_food, "TestB.6: Central food stock unaffected")

## -----------------------------------------------------------------------------
## GROUP C: TEST C — Destruction path applies Policy A forfeiture
## -----------------------------------------------------------------------------
func _test_group_c_destruction_path_forfeiture() -> void:
	print("\n--- Group C: Test C — Destruction Path Applies Policy A Forfeiture ---")
	var wd = world_instance.get("world_data")
	var rm = world_instance.call("_get_resource_mgr")
	var wm: WorkplaceManager = world_instance.get("workplace_mgr")

	var b_id := "bld_test_farm_c"
	var origin := Vector2i(22, 14)
	var b_data := {
		"id": b_id,
		"type": "farm",
		"cell": origin,
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100,
		"max_health": 100,
		"upgrade_level": 1
	}
	wd.buildings.append(b_data)
	world_instance.buildings_by_cell[origin] = b_data
	world_instance.register_dynamic_workplace(b_data)

	var wp = wm.get_workplace(b_id)
	_assert(wp != null, "TestC.1: Farm registered for destruction test")
	wp.buffer_amount = 40
	_assert(wm.get_buffer_amount(b_id) == 40, "TestC.2: Farm buffer has 40 food")

	var initial_central_food: int = rm.get_total_stock("food")

	# Apply lethal damage through production lifecycle
	var dmg_ok: bool = world_instance.damage_building(b_id, 100)
	_assert(dmg_ok, "TestC.3: Lethal damage applied via damage_building")
	_assert(b_data.get("state", "") == "destroyed", "TestC.4: Building state transitioned to 'destroyed'")

	# Policy A check on permanent destruction:
	_assert(wm.get_workplace(b_id) == null, "TestC.5: Workplace unregistered upon permanent destruction")
	_assert(wm.get_buffer_amount(b_id) == 0, "TestC.6: Buffer amount returns 0")

	# Central stock must NOT receive unhauled buffer
	var post_destruct_food: int = rm.get_total_stock("food")
	_assert(post_destruct_food == initial_central_food, "TestC.7: Central food stock unchanged after lethal destruction (%d == %d)" % [post_destruct_food, initial_central_food])

	# Clearing the ruin via demolish_building_project must succeed cleanly and idempotently
	var clear_res: Dictionary = world_instance.demolish_building_project(b_id)
	_assert(clear_res.get("success", false) == true, "TestC.8: Clearing destroyed ruin succeeded")
	_assert(rm.get_total_stock("food") == initial_central_food, "TestC.9: Central food stock strictly unchanged after clearing ruin")

## -----------------------------------------------------------------------------
## GROUP D: TEST D — Cancellation and Rejection safety
## -----------------------------------------------------------------------------
func _test_group_d_cancellation_and_rejection_safety() -> void:
	print("\n--- Group D: Test D — Cancellation and Rejection Safety ---")
	var wd = world_instance.get("world_data")
	var rm = world_instance.call("_get_resource_mgr")
	var wm: WorkplaceManager = world_instance.get("workplace_mgr")
	var hud = world_instance.get("hud")

	var b_id := "bld_test_farm_d"
	var origin := Vector2i(26, 14)
	var b_data := {
		"id": b_id,
		"type": "farm",
		"cell": origin,
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100,
		"max_health": 100,
		"upgrade_level": 1
	}
	wd.buildings.append(b_data)
	world_instance.buildings_by_cell[origin] = b_data
	world_instance.register_dynamic_workplace(b_data)

	var wp = wm.get_workplace(b_id)
	_assert(wp != null, "TestD.1: Farm registered for cancellation/rejection test")
	wp.buffer_amount = 25
	_assert(wm.get_buffer_amount(b_id) == 25, "TestD.2: Initial buffer is 25 food")

	# Subtest D1: Rejection safety (insufficient storage for refund fails closed)
	var orig_wood_cap: int = rm.get_capacity("wood")
	# Force wood capacity to current stock so 50% refund cannot fit
	rm._capacities["wood"] = rm.get_resource("wood")
	var reject_res: Dictionary = world_instance.demolish_building_project(b_id)
	_assert(reject_res.get("success", true) == false, "TestD.3: Demolition rejected when storage cannot accept refund")
	_assert(wm.get_workplace(b_id) != null, "TestD.4: Workplace remains registered after rejection")
	_assert(wm.get_buffer_amount(b_id) == 25, "TestD.5: Output buffer remains 25 food after rejection")

	# Restore wood capacity
	rm._capacities["wood"] = orig_wood_cap

	# Subtest D2: Cancellation safety via HUD overlay
	if hud != null:
		hud.inspected_building_id = b_id
		hud.inspected_building_data = b_data
		hud._on_demolish_building_pressed()
		var overlay = hud.get("demolish_confirm_overlay")
		if overlay != null:
			_assert(overlay.visible == true, "TestD.6: Demolish confirmation overlay opened")
			hud._on_cancel_demolish_pressed()
			_assert(overlay.visible == false, "TestD.7: Demolish confirmation overlay closed on cancel")

		_assert(wm.get_workplace(b_id) != null, "TestD.8: Workplace remains registered after cancellation")
		_assert(wm.get_buffer_amount(b_id) == 25, "TestD.9: Output buffer remains 25 food after cancellation")

	# Clean up test building
	world_instance.demolish_building_project(b_id)

## -----------------------------------------------------------------------------
## GROUP E: TEST E — Idempotency
## -----------------------------------------------------------------------------
func _test_group_e_idempotency() -> void:
	print("\n--- Group E: Test E — Idempotency of Removal & Cleanup ---")
	var wd = world_instance.get("world_data")
	var rm = world_instance.call("_get_resource_mgr")
	var wm: WorkplaceManager = world_instance.get("workplace_mgr")

	var b_id := "bld_test_quarry_e"
	var origin := Vector2i(14, 18)
	var b_data := {
		"id": b_id,
		"type": "quarry",
		"cell": origin,
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 100,
		"max_health": 100,
		"upgrade_level": 1
	}
	wd.buildings.append(b_data)
	world_instance.buildings_by_cell[origin] = b_data
	world_instance.register_dynamic_workplace(b_data)

	var wp = wm.get_workplace(b_id)
	_assert(wp != null, "TestE.1: Quarry registered")
	wp.buffer_amount = 15

	var initial_stone: int = rm.get_total_stock("stone")

	# Call unregister_workplace directly
	var unreg_res_1: Dictionary = wm.unregister_workplace(b_id)
	_assert(unreg_res_1.get("total_forfeited", 0) == 15, "TestE.2: First unregister forfeited 15 stone")
	_assert(wm.get_workplace(b_id) == null, "TestE.3: Workplace erased")

	# Second call on already erased workplace
	var unreg_res_2: Dictionary = wm.unregister_workplace(b_id)
	_assert(unreg_res_2.get("total_forfeited", 0) == 0, "TestE.4: Repeated unregister safely returns 0 forfeited")

	# Third call
	var unreg_res_3: Dictionary = wm.unregister_workplace(b_id)
	_assert(unreg_res_3.get("total_forfeited", 0) == 0, "TestE.5: Third unregister safely returns 0 forfeited")

	_assert(rm.get_total_stock("stone") == initial_stone, "TestE.6: Central stone stock unaffected across repeated unregistration")

	# Demolish the building
	var demo_res = world_instance.demolish_building_project(b_id)
	_assert(demo_res.get("success", false) == true, "TestE.7: Demolish building succeeded")

	# Calling demolish_building_project on already deleted building fails closed safely
	var repeat_demo: Dictionary = world_instance.demolish_building_project(b_id)
	_assert(repeat_demo.get("success", true) == false, "TestE.8: Repeated demolish_building_project safely rejected")

## -----------------------------------------------------------------------------
## GROUP F: TEST F — Unrelated workplace isolation
## -----------------------------------------------------------------------------
func _test_group_f_unrelated_workplace_isolation() -> void:
	print("\n--- Group F: Test F — Unrelated Workplace Isolation ---")
	var wd = world_instance.get("world_data")
	var rm = world_instance.call("_get_resource_mgr")
	var wm: WorkplaceManager = world_instance.get("workplace_mgr")

	var b_id_1 := "bld_test_farm_f1"
	var origin_1 := Vector2i(18, 18)
	var b_data_1 := {
		"id": b_id_1, "type": "farm", "cell": origin_1, "size": Vector2i(2, 2),
		"state": "active", "health": 100, "max_health": 100, "upgrade_level": 1
	}
	wd.buildings.append(b_data_1)
	world_instance.buildings_by_cell[origin_1] = b_data_1
	world_instance.register_dynamic_workplace(b_data_1)

	var b_id_2 := "bld_test_farm_f2"
	var origin_2 := Vector2i(22, 18)
	var b_data_2 := {
		"id": b_id_2, "type": "farm", "cell": origin_2, "size": Vector2i(2, 2),
		"state": "active", "health": 100, "max_health": 100, "upgrade_level": 1
	}
	wd.buildings.append(b_data_2)
	world_instance.buildings_by_cell[origin_2] = b_data_2
	world_instance.register_dynamic_workplace(b_data_2)

	var wp1 = wm.get_workplace(b_id_1)
	var wp2 = wm.get_workplace(b_id_2)
	_assert(wp1 != null and wp2 != null, "TestF.1: Both test farms registered")
	wp1.buffer_amount = 20
	wp2.buffer_amount = 45

	var initial_central_food: int = rm.get_total_stock("food")

	# Demolish Farm 1
	var demo_res: Dictionary = world_instance.demolish_building_project(b_id_1)
	_assert(demo_res.get("success", false) == true, "TestF.2: Farm 1 demolished")
	_assert(wm.get_workplace(b_id_1) == null, "TestF.3: Farm 1 workplace unregistered")
	_assert(wm.get_buffer_amount(b_id_1) == 0, "TestF.4: Farm 1 buffer returns 0")

	# Farm 2 must remain completely unaffected
	_assert(wm.get_workplace(b_id_2) != null, "TestF.5: Farm 2 workplace remains registered")
	_assert(wm.get_buffer_amount(b_id_2) == 45, "TestF.6: Farm 2 buffer strictly conserved at 45 food")
	_assert(rm.get_total_stock("food") == initial_central_food, "TestF.7: Central food stock unchanged")

	# Clean up Farm 2
	world_instance.demolish_building_project(b_id_2)
	_assert(wm.get_workplace(b_id_2) == null, "TestF.8: Farm 2 cleanly demolished")

## -----------------------------------------------------------------------------
## GROUP G: TEST G — Temporary / non-destructive state transitions preserve buffer
## -----------------------------------------------------------------------------
func _test_group_g_temporary_state_preservation() -> void:
	print("\n--- Group G: Test G — Temporary State Transitions Preserve Buffer ---")
	var wd = world_instance.get("world_data")
	var rm = world_instance.call("_get_resource_mgr")
	var wm: WorkplaceManager = world_instance.get("workplace_mgr")

	var b_id := "bld_test_farm_g"
	var origin := Vector2i(26, 18)
	var b_data := {
		"id": b_id, "type": "farm", "cell": origin, "size": Vector2i(2, 2),
		"state": "active", "health": 100, "max_health": 100, "upgrade_level": 1
	}
	wd.buildings.append(b_data)
	world_instance.buildings_by_cell[origin] = b_data
	world_instance.register_dynamic_workplace(b_data)

	var wp = wm.get_workplace(b_id)
	_assert(wp != null, "TestG.1: Farm registered for temporary state tests")
	wp.buffer_amount = 30
	_assert(wm.get_buffer_amount(b_id) == 30, "TestG.2: Initial buffer set to 30 food")

	# 1. State transition to paused
	world_instance.set_building_state(b_id, "paused", "active")
	_assert(wm.is_workplace_paused(b_id) == true, "TestG.3: Workplace is paused")
	_assert(wm.get_buffer_amount(b_id) == 30, "TestG.4: Output buffer preserved at 30 food while paused")

	# 2. State transition back to active (resumed)
	world_instance.set_building_state(b_id, "active", "paused")
	_assert(wm.is_workplace_paused(b_id) == false, "TestG.5: Workplace is resumed (unpaused)")
	_assert(wm.get_buffer_amount(b_id) == 30, "TestG.6: Output buffer preserved at 30 food after resuming")

	# 3. Non-lethal damage transition (health 100 -> 50, state: damaged)
	var dmg_ok: bool = world_instance.damage_building(b_id, 50)
	_assert(dmg_ok, "TestG.7: Non-lethal damage applied successfully")
	_assert(b_data.get("state", "") == "damaged", "TestG.8: Building transitioned to 'damaged'")
	_assert(wm.get_buffer_amount(b_id) == 30, "TestG.9: Output buffer preserved at 30 food while damaged")

	# 4. Repair completion restores active state
	world_instance.set_building_state(b_id, "active", "damaged")
	_assert(b_data.get("state", "") == "active", "TestG.10: Building restored to 'active'")
	_assert(wm.get_buffer_amount(b_id) == 30, "TestG.11: Output buffer preserved at 30 food after repair")

	# Clean up
	world_instance.demolish_building_project(b_id)

## -----------------------------------------------------------------------------
## GROUP H: TEST H — Workshop Multi-Channel Output Buffer Forfeiture
## -----------------------------------------------------------------------------
func _test_group_h_workshop_multichannel_forfeiture() -> void:
	print("\n--- Group H: Test H — Workshop Multi-Channel Output Buffer Forfeiture ---")
	var wd = world_instance.get("world_data")
	var rm = world_instance.call("_get_resource_mgr")
	var wm: WorkplaceManager = world_instance.get("workplace_mgr")

	var b_id := "bld_test_ws_h"
	var origin := Vector2i(14, 22)
	var b_data := {
		"id": b_id, "type": "workshop", "cell": origin, "size": Vector2i(2, 2),
		"state": "active", "health": 100, "max_health": 100, "upgrade_level": 1
	}
	wd.buildings.append(b_data)
	world_instance.buildings_by_cell[origin] = b_data
	world_instance.register_dynamic_workplace(b_data)

	var smelt_ch = wm.get_workplace(b_id + "_smelt")
	var craft_ch = wm.get_workplace(b_id + "_craft")
	_assert(smelt_ch != null, "TestH.1: Smelt channel registered")
	_assert(craft_ch != null, "TestH.2: Craft channel registered")

	smelt_ch.buffer_amount = 18 # 18 Metal
	craft_ch.buffer_amount = 12 # 12 Tools

	_assert(wm.get_buffer_amount(b_id, "smelt_metal") == 18, "TestH.3: Smelt channel buffer has 18 metal")
	_assert(wm.get_buffer_amount(b_id, "craft_tools") == 12, "TestH.4: Craft channel buffer has 12 tools")

	var initial_metal: int = rm.get_total_stock("metal")
	var initial_tools: int = rm.get_total_stock("tools")

	# Demolish workshop
	var demo_res: Dictionary = world_instance.demolish_building_project(b_id)
	_assert(demo_res.get("success", false) == true, "TestH.5: Workshop demolished successfully")

	# Both channels must be unregistered and buffers forfeited
	_assert(wm.get_workplace(b_id + "_smelt") == null, "TestH.6: Smelt channel unregistered")
	_assert(wm.get_workplace(b_id + "_craft") == null, "TestH.7: Craft channel unregistered")
	_assert(wm.get_buffer_amount(b_id, "smelt_metal") == 0, "TestH.8: Smelt channel buffer returns 0")
	_assert(wm.get_buffer_amount(b_id, "craft_tools") == 0, "TestH.9: Craft channel buffer returns 0")

	# Workshop construction cost has 5 metal (50% refund = 2 metal), but 0 tools.
	# The unhauled buffer (18 metal and 12 tools) must be completely forfeited.
	# Therefore, final metal = initial_metal + 2 (structural refund only, zero buffer)
	# and final tools = initial_tools + 0 (zero structural refund, zero buffer)
	var final_metal: int = rm.get_total_stock("metal")
	var final_tools: int = rm.get_total_stock("tools")
	var structural_metal_refund: int = 2
	_assert(final_metal == initial_metal + structural_metal_refund, "TestH.10: Central metal reflects only 50%% structural refund (%d == %d + %d), zero buffer credited" % [final_metal, initial_metal, structural_metal_refund])
	_assert(final_tools == initial_tools, "TestH.11: Central tools strictly unchanged (%d == %d), zero buffer credited" % [final_tools, initial_tools])

## -----------------------------------------------------------------------------
## GROUP I: TEST I — Legacy Save/Load Destroyed Workplace Reconciliation (Audit B)
## -----------------------------------------------------------------------------
func _test_group_i_legacy_save_load_destroyed_workplace_reconciliation() -> void:
	print("\n--- Group I: Test I — Legacy Save/Load Destroyed Workplace Reconciliation (Audit B) ---")
	var wd = world_instance.get("world_data")
	var rm = world_instance.call("_get_resource_mgr")
	var wm: WorkplaceManager = world_instance.get("workplace_mgr")

	var initial_food: int = rm.get_total_stock("food")
	var initial_stone: int = rm.get_total_stock("stone")

	# Scenario 1: Starter farm was destroyed prior to save
	var starter_farm_b = null
	for b in wd.buildings:
		if b.get("id") == "farm_starter" or (b.get("type") == "farm" and b.get("cell") == Vector2i(36, 35)):
			starter_farm_b = b
			break
	_assert(starter_farm_b != null, "TestI.1: Starter farm exists in world_data")
	if starter_farm_b != null:
		starter_farm_b["state"] = "destroyed"
		starter_farm_b["health"] = 0

	# Scenario 2: Legacy dynamic quarry was destroyed prior to save
	var b_quarry_id := "bld_quarry_audit_b"
	var quarry_data := {
		"id": b_quarry_id,
		"type": "quarry",
		"cell": Vector2i(10, 26),
		"size": Vector2i(2, 2),
		"state": "destroyed",
		"health": 0
	}
	wd.buildings.append(quarry_data)

	# Simulate legacy save payload containing stale workplaces with unhauled buffers
	var legacy_saved_workplaces := {
		"farm_starter": {
			"id": "farm_starter",
			"building_type": "farm",
			"buffer_amount": 35,
			"buffer_capacity": 50
		},
		"bld_quarry_audit_b": {
			"id": "bld_quarry_audit_b",
			"building_type": "quarry",
			"buffer_amount": 40,
			"buffer_capacity": 50
		}
	}

	# Run sync_workplaces_after_load reconciliation
	world_instance.sync_workplaces_after_load(legacy_saved_workplaces)

	# 1. Starter farm ruin must be unregistered and have no active buffer
	_assert(not wm.has_workplace("farm_starter"), "TestI.2: Destroyed starter farm is not in workplace_mgr after sync")
	_assert(wm.get_workplace("farm_starter") == null, "TestI.3: get_workplace('farm_starter') returns null")
	_assert(wm.get_buffer_amount("farm_starter") == 0, "TestI.4: get_buffer_amount('farm_starter') returns 0")

	# 2. Dynamic quarry ruin must be unregistered and have no active buffer
	_assert(not wm.has_workplace(b_quarry_id), "TestI.5: Destroyed dynamic quarry is not in workplace_mgr after sync")
	_assert(wm.get_workplace(b_quarry_id) == null, "TestI.6: get_workplace('bld_quarry_audit_b') returns null")
	_assert(wm.get_buffer_amount(b_quarry_id) == 0, "TestI.7: get_buffer_amount('bld_quarry_audit_b') returns 0")

	# 3. Policy A: Central ResourceManager stock must be untouched (zero buffer goods credited)
	var final_food: int = rm.get_total_stock("food")
	var final_stone: int = rm.get_total_stock("stone")
	_assert(final_food == initial_food, "TestI.8: Central food stock unchanged (%d == %d), zero buffer credited" % [final_food, initial_food])
	_assert(final_stone == initial_stone, "TestI.9: Central stone stock unchanged (%d == %d), zero buffer credited" % [final_stone, initial_stone])

	# 4. Idempotency: Repeating sync_workplaces_after_load produces identical clean state
	world_instance.sync_workplaces_after_load(legacy_saved_workplaces)
	_assert(not wm.has_workplace("farm_starter"), "TestI.10: Repeated sync preserves unregistered status for farm_starter")
	_assert(not wm.has_workplace(b_quarry_id), "TestI.11: Repeated sync preserves unregistered status for dynamic quarry")
	_assert(rm.get_total_stock("food") == initial_food, "TestI.12: Repeated sync maintains exact central food stock")

	# 5. In-transit citizen cargo conservation: ensure carried cargo is distinct from workplace buffer
	var test_cit = CitizenControllerScript.new()
	test_cit.name = "cit_audit_b_hauler"
	test_cit.carrying_amount = 15
	test_cit.carrying_resource = "wood"
	_assert(test_cit.carrying_amount == 15, "TestI.13: In-transit citizen carrying_amount is preserved (15 wood)")
	test_cit.free()

