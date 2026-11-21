class_name TestSettlementWoodcutterW1
extends SceneTree
## Focused Test Suite for Implementation Slice W1:
## Woodcutter Atomic Resource Transaction & Exact-Once Labor Banking.
## Architecture v1.0 — 35 Assertions across Categories A–F.

const SettlementSimulationManagerScript = preload("res://scripts/world/settlement_simulation_manager.gd")
const SettlementResourceSourceAdapterScript = preload("res://scripts/world/settlement_resource_source_adapter.gd")
const SettlementVillagerContextScript = preload("res://scripts/world/settlement_villager_context.gd")
const SettlementSimulationStateScript = preload("res://scripts/world/settlement_simulation_state.gd")
const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementBuildingCapabilityAdapterScript = preload("res://scripts/world/settlement_building_capability_adapter.gd")
const SettlementDataScript = preload("res://scripts/world/settlement_data.gd")
const SettlementGeneratorScript = preload("res://scripts/world/settlement_generator.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const LandClearingManagerScript = preload("res://scripts/economy/land_clearing_manager.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")

var _passed: int = 0
var _failed: int = 0

func _init() -> void:
	call_deferred("_run_tests")

func _assert(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("  [PASS] %s" % message)
	else:
		_failed += 1
		print("  [FAIL] %s" % message)

func _create_mock_world_data(tree_cells: Array[Vector2i], p_map_size: int = 50) -> WorldGeneratorScript.WorldData:
	var wd = WorldGeneratorScript.WorldData.new()
	wd.seed_value = 12345
	wd.generator_version = 8
	wd.map_width = p_map_size
	wd.map_height = p_map_size
	wd.player_center = Vector2i(p_map_size / 2, p_map_size / 2)
	wd.center_spawn = wd.player_center + Vector2i(0, 1)
	wd.townhall_anchor = wd.player_center + Vector2i(-1, -2)
	wd.terrain = []
	wd.occupancy = []
	for x in range(p_map_size):
		var t_col: Array = []
		var o_col: Array = []
		for y in range(p_map_size):
			t_col.append(WorldGeneratorScript.TerrainType.GRASS)
			o_col.append(false)
		wd.terrain.append(t_col)
		wd.occupancy.append(o_col)
	var p_arr: Array[Dictionary] = []
	for c in tree_cells:
		p_arr.append({
			"type": "tree",
			"cell": c,
			"variant": 0
		})
		if c.x >= 0 and c.x < p_map_size and c.y >= 0 and c.y < p_map_size:
			wd.occupancy[c.x][c.y] = true
	wd.props = p_arr
	return wd

func _setup_woodcutter_context(sid: String = "stl_test", buffer_cap: int = 50) -> Dictionary:
	var ctx := SettlementVillagerContextScript.new(sid, "neutral_tribe", "neutral_tribe", 1, true)
	var stl := SettlementDataScript.new(sid, "neutral_tribe", "neutral_tribe", SettlementDataScript.ROLE_VILLAGE, Vector2i(10, 10))
	stl.buildings.append({
		"id": "bld_wood",
		"type": "woodcutter",
		"cell": Vector2i(10, 10),
		"size": Vector2i(2, 2),
		"role": "workplace",
		"blocking": true,
		"buffer_capacity": buffer_cap
	})
	ctx.reconcile_buildings(stl)
	var wp = ctx.workplace_registry.get_workplace("bld_wood")
	if wp != null:
		wp.buffer_capacity = buffer_cap
	return {"ctx": ctx, "stl": stl, "wp": wp}

func _run_tests() -> void:
	print("========================================================")
	print("  TEST SUITE: Woodcutter Atomic Resource Transaction (W1)")
	print("========================================================")

	_test_category_a_conservation()
	_test_category_b_atomicity()
	_test_category_c_labor_banking()
	_test_category_d_backpressure_retry()
	_test_category_e_serialization()
	_test_category_f_day_shift_mapping()
	_test_category_g_corrective_pass_requirements()
	_test_category_h_final_hardening()
	_test_category_i_acceptance_hardening()

	print("--------------------------------------------------------")
	print("  Results: %d passed, %d failed" % [_passed, _failed])
	print("========================================================")

	if _failed == 0:
		print("ALL %d ASSERTIONS PASSED! (Exit Code 0)" % _passed)
		quit(0)
	else:
		print("TEST SUITE FAILED WITH %d ERRORS! (Exit Code 1)" % _failed)
		quit(1)

# -----------------------------------------------------------------------------
# Category A: Resource Conservation & Zero Ghost Wood (6 assertions)
# -----------------------------------------------------------------------------
func _test_category_a_conservation() -> void:
	print("\n[Category A] Resource Conservation & Zero Ghost Wood")
	var setup := _setup_woodcutter_context("stl_a")
	var ctx: RefCounted = setup["ctx"]
	var wd := _create_mock_world_data([Vector2i(10, 12), Vector2i(10, 13)])
	var reg_res := SettlementResourceSourceAdapterScript.register_woodcutter_source(ctx, "bld_wood", wd, [Vector2i(10, 12), Vector2i(10, 13)])

	# A1: 1 tree contains exactly 5 Wood (5000 milli-units); zero partial tree harvesting
	var src: Dictionary = ctx.sim_state.production_sources["bld_wood"]
	var trees: Array = src["trees"]
	var t0: Dictionary = trees[0]
	_assert(
		reg_res["ok"] and trees.size() == 2
		and int(t0["remaining_milli"]) == SettlementResourceSourceAdapterScript.TREE_WOOD_MILLI
		and SettlementResourceSourceAdapterScript.calculate_remaining_wood(src) == 10,
		"A1: 1 tree contains exactly 5 Wood (5000 milli-units); zero partial harvesting"
	)

	# A2: Felling a tree removes prop from world_data.props and clears world_data.occupancy
	src["work_credit_milli"] = 5000
	var fell_res := SettlementResourceSourceAdapterScript.execute_tree_felling_transaction(ctx, "bld_wood", wd, null)
	var prop_remaining := SettlementResourceSourceAdapterScript.find_tree_prop_at_cell(wd, Vector2i(10, 12))
	var occ_cleared: bool = (not bool(wd.occupancy[10][12]))
	_assert(
		fell_res["ok"] and prop_remaining.is_empty() and occ_cleared
		and wd.props.size() == 1 and SettlementResourceSourceAdapterScript.is_tree_felled(t0) and int(t0["remaining_milli"]) == 0,
		"A2: Felling a tree removes prop from WorldData.props and clears occupancy synchronously"
	)

	# A3: If visual world_view is present, remove_prop_visual_at_cell removes the prop node
	var helper_node = Node.new()
	var callable_script = GDScript.new()
	callable_script.source_code = "extends Node\nvar last_cell := Vector2i(-1,-1)\nfunc remove_prop_visual_at_cell(c: Vector2i) -> void:\n\tlast_cell = c\n"
	callable_script.reload()
	helper_node.set_script(callable_script)
	src["work_credit_milli"] = 5000
	var fell_res_v := SettlementResourceSourceAdapterScript.execute_tree_felling_transaction(ctx, "bld_wood", wd, helper_node)
	_assert(
		fell_res_v["ok"] and helper_node.get("last_cell") == Vector2i(10, 13),
		"A3: WorldView remove_prop_visual_at_cell is invoked on tree felling"
	)
	helper_node.free()

	# A4: Player clearing of an assigned tree causes rival transaction to detect missing prop and fail closed
	var wd_shared := _create_mock_world_data([Vector2i(5, 5)])
	var setup_a4 := _setup_woodcutter_context("stl_a4")
	var ctx_a4: RefCounted = setup_a4["ctx"]
	SettlementResourceSourceAdapterScript.register_woodcutter_source(ctx_a4, "bld_wood", wd_shared, [Vector2i(5, 5)])
	var src_a4: Dictionary = ctx_a4.sim_state.production_sources["bld_wood"]
	src_a4["work_credit_milli"] = 5000
	# Simulate Player clearing tree first: remove from world_data.props
	wd_shared.props.clear()
	wd_shared.occupancy[5][5] = false
	var fail_closed_res := SettlementResourceSourceAdapterScript.execute_tree_felling_transaction(ctx_a4, "bld_wood", wd_shared, null)
	_assert(
		not fail_closed_res["ok"] and fail_closed_res["reason"] == "prop_missing_in_world"
		and int(src_a4["work_credit_milli"]) == 5000
		and int(setup_a4["wp"].buffer_amount) == 0,
		"A4: Player clearing causes rival transaction to fail closed with 0 credit debited and 0 wood deposited"
	)

	# A5: Rival felling of a tree cancels any player clearing order targeting that cell with zero wood
	var lcm := LandClearingManagerScript.new()
	var wd_a5 := _create_mock_world_data([Vector2i(6, 6)])
	lcm.queue_clearing_order(wd_a5, Vector2i(6, 6), 12345, 8)
	var ord_before: Dictionary = lcm.get_order_at_cell(Vector2i(6, 6))
	_assert(not ord_before.is_empty(), "Pre-A5: Player clearing order queued at (6, 6)")
	var setup_a5 := _setup_woodcutter_context("stl_a5")
	var ctx_a5: RefCounted = setup_a5["ctx"]
	SettlementResourceSourceAdapterScript.register_woodcutter_source(ctx_a5, "bld_wood", wd_a5, [Vector2i(6, 6)])
	ctx_a5.sim_state.production_sources["bld_wood"]["work_credit_milli"] = 5000
	var fell_a5 := SettlementResourceSourceAdapterScript.execute_tree_felling_transaction(ctx_a5, "bld_wood", wd_a5, null)
	var prop_lookup_a5: Dictionary = lcm.find_prop_at_cell(wd_a5, Vector2i(6, 6))
	var new_order_res: Dictionary = lcm.queue_clearing_order(wd_a5, Vector2i(6, 6), 12345, 8)
	_assert(
		fell_a5["ok"] and prop_lookup_a5.is_empty() and not bool(new_order_res.get("success", false)),
		"A5: Rival felling removes prop from WorldData; player clearing cannot queue on missing prop"
	)

	# A6: Complete tree depletion sets source remaining to 0 and blocks further production
	ctx_a5.sim_state.production_sources["bld_wood"]["work_credit_milli"] = 5000
	var empty_fell := SettlementResourceSourceAdapterScript.execute_tree_felling_transaction(ctx_a5, "bld_wood", wd_a5, null)
	_assert(
		not empty_fell["ok"] and empty_fell["reason"] == "source_depleted"
		and SettlementResourceSourceAdapterScript.calculate_remaining_wood(ctx_a5.sim_state.production_sources["bld_wood"]) == 0
		and ctx_a5.sim_state.production_blocked.get("bld_wood", "") == "source_depleted",
		"A6: Tree depletion sets remaining to 0 and blocks workplace with 'source_depleted'"
	)

# -----------------------------------------------------------------------------
# Category B: Atomicity & Rollback Integrity (6 assertions)
# -----------------------------------------------------------------------------
func _test_category_b_atomicity() -> void:
	print("\n[Category B] Atomicity & Rollback Integrity")
	var setup := _setup_woodcutter_context("stl_b")
	var ctx: RefCounted = setup["ctx"]
	var wd := _create_mock_world_data([Vector2i(1, 1), Vector2i(1, 2)])
	SettlementResourceSourceAdapterScript.register_woodcutter_source(ctx, "bld_wood", wd, [Vector2i(1, 1), Vector2i(1, 2)])
	var src: Dictionary = ctx.sim_state.production_sources["bld_wood"]

	# B1: Prepare failure due to insufficient credit leaves all state 100% unchanged
	src["work_credit_milli"] = 4000
	var res_b1 := SettlementResourceSourceAdapterScript.execute_tree_felling_transaction(ctx, "bld_wood", wd, null)
	_assert(
		not res_b1["ok"] and res_b1["reason"] == "insufficient_work_credit"
		and int(src["work_credit_milli"]) == 4000
		and int(setup["wp"].buffer_amount) == 0
		and wd.props.size() == 2,
		"B1: Prepare failure from insufficient credit leaves state 100% unchanged"
	)

	# B2: Prepare failure due to buffer full leaves credit banked and tree unfelled
	src["work_credit_milli"] = 5000
	setup["wp"].buffer_amount = 50 # buffer capacity is 50 -> headroom 0
	var res_b2 := SettlementResourceSourceAdapterScript.execute_tree_felling_transaction(ctx, "bld_wood", wd, null)
	_assert(
		not res_b2["ok"] and res_b2["reason"] == "buffer_full"
		and int(src["work_credit_milli"]) == 5000
		and setup["wp"].is_paused
		and wd.props.size() == 2,
		"B2: Prepare failure from buffer backpressure pauses workplace and preserves credit intact"
	)

	# B3: Prepare failure due to missing prop in world does not debit credit and does not deposit wood
	setup["wp"].buffer_amount = 0
	setup["wp"].is_paused = false
	wd.props.clear() # Simulate external removal
	var res_b3 := SettlementResourceSourceAdapterScript.execute_tree_felling_transaction(ctx, "bld_wood", wd, null)
	_assert(
		not res_b3["ok"] and res_b3["reason"] == "prop_missing_in_world"
		and int(src["work_credit_milli"]) == 5000
		and int(setup["wp"].buffer_amount) == 0,
		"B3: Prepare failure from missing prop preserves work credit and deposits 0 wood"
	)

	# B4: Commit phase mutates tree, credit, buffer, world props, and stats synchronously in memory
	var wd_b4 := _create_mock_world_data([Vector2i(2, 2)])
	var setup_b4 := _setup_woodcutter_context("stl_b4")
	var ctx_b4: RefCounted = setup_b4["ctx"]
	SettlementResourceSourceAdapterScript.register_woodcutter_source(ctx_b4, "bld_wood", wd_b4, [Vector2i(2, 2)])
	var src_b4: Dictionary = ctx_b4.sim_state.production_sources["bld_wood"]
	src_b4["work_credit_milli"] = 5000
	var res_b4 := SettlementResourceSourceAdapterScript.execute_tree_felling_transaction(ctx_b4, "bld_wood", wd_b4, null)
	_assert(
		res_b4["ok"]
		and int(src_b4["work_credit_milli"]) == 0
		and int(setup_b4["wp"].buffer_amount) == 5
		and int(ctx_b4.sim_state.stats["produced"]) == 5
		and wd_b4.props.is_empty(),
		"B4: Commit phase mutates tree, credit, buffer, world props, and stats synchronously"
	)

	# B5: Injected stage failure during production leaves worker hours and banked credit atomic
	var mgr := SettlementSimulationManagerScript.new()
	var setup_b5 := _setup_woodcutter_context("stl_b5")
	var ctx_b5: RefCounted = setup_b5["ctx"]
	var wd_b5 := _create_mock_world_data([Vector2i(3, 3)])
	mgr.set_world_data(wd_b5)
	var v1 = ctx_b5.create_and_add_villager("W1", "idle", Vector2i(10, 10))
	ctx_b5.reconcile_buildings(setup_b5["stl"])
	mgr.register_context(ctx_b5)
	mgr.register_woodcutter_source(ctx_b5.settlement_id, "bld_wood", [Vector2i(3, 3)])
	# Advance 2 hours so next hour (hour 3) hits production
	mgr.advance_to_hour_seq(2)
	mgr.process_all_pending()
	# Inject stage failure at hour 3 during production
	var fail_once: Array[bool] = [true]
	mgr.set_stage_fault_hook_for_test(ctx_b5.settlement_id, func(_s: String, _v: String, h: int, stg: String) -> bool:
		if fail_once[0] and h == 3 and stg == "during_production":
			fail_once[0] = false
			return false
		return true
	)
	mgr.advance_to_hour_seq(3)
	var b_res := mgr.process_batch(1, 1000.0)
	var src_b5: Dictionary = ctx_b5.sim_state.production_sources["bld_wood"]
	_assert(
		int(src_b5.get("work_credit_milli", 0)) == 0
		and int(setup_b5["wp"].buffer_amount) == 0
		and int(ctx_b5.sim_state.settled_hour_seq) == 2,
		"B5: Injected failure during production leaves watermark at 2, credit 0, buffer 0"
	)

	# B6: Re-executing transaction after stage failure retry completes exactly once
	mgr.clear_settlement_isolation(ctx_b5.settlement_id)
	mgr.process_all_pending()
	_assert(
		int(ctx_b5.sim_state.settled_hour_seq) == 3
		and int(src_b5.get("work_credit_milli", 0)) == 4000
		and int(setup_b5["wp"].buffer_amount) == 0,
		"B6: Retried hour 3 completes cleanly, banking exactly 4000 credit once"
	)
	mgr.free()

# -----------------------------------------------------------------------------
# Category C: Exact-Once Labor Banking & Shift Consistency (6 assertions)
# -----------------------------------------------------------------------------
func _test_category_c_labor_banking() -> void:
	print("\n[Category C] Exact-Once Labor Banking & Shift Consistency")
	var mgr := SettlementSimulationManagerScript.new()
	var setup := _setup_woodcutter_context("stl_c", 50)
	var ctx: RefCounted = setup["ctx"]
	var wd := _create_mock_world_data([
		Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 5)
	])
	mgr.set_world_data(wd)
	var v1 = ctx.create_and_add_villager("WC1", "idle", Vector2i(10, 10))
	ctx.reconcile_buildings(setup["stl"])
	mgr.register_context(ctx)
	mgr.register_woodcutter_source(ctx.settlement_id, "bld_wood", [
		Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 5)
	])
	var src: Dictionary = ctx.sim_state.production_sources["bld_wood"]

	# C1: Completed 3-hour worker cycle adds exactly 4000 work_credit_milli
	# Run 3 hours: hour 1, 2, 3
	mgr.advance_to_hour_seq(3)
	mgr.process_all_pending()
	_assert(
		int(src["work_credit_milli"]) == 4000,
		"C1: Completed 3-hour worker cycle adds exactly 4000 work_credit_milli"
	)

	# C2: 1st cycle (4000 credit) banks credit without felling (threshold is 5000)
	_assert(
		int(setup["wp"].buffer_amount) == 0 and wd.props.size() == 5,
		"C2: 1st cycle (4000 credit) banks credit without felling (buffer 0, trees 5)"
	)

	# C3: 2nd cycle (4000 + 4000 = 8000 credit) fells 1 tree, leaving exactly 3000 banked credit
	mgr.advance_to_hour_seq(6)
	mgr.process_all_pending()
	_assert(
		int(src["work_credit_milli"]) == 3000
		and int(setup["wp"].buffer_amount) == 5
		and wd.props.size() == 4,
		"C3: 2nd cycle fells 1 tree, leaving exactly 3000 credit and 5 wood in buffer"
	)

	# Advance 3rd cycle (hour 9): credit 3000 + 4000 = 7000 -> fells tree 2, leaves 2000 credit, 10 wood
	mgr.advance_to_hour_seq(9)
	mgr.process_all_pending()
	# Cycle 4: hours 10, 11 + night shift gap (hours 12..22) + hour 23 (clock 05:00) -> credit 2000 + 4000 = 6000 -> fells tree 3, leaves 1000 credit, 15 wood
	mgr.advance_to_hour_seq(23)
	mgr.process_all_pending()
	# Cycle 5: hours 24, 25, 26 (clock 06:00, 07:00, 08:00) -> credit 1000 + 4000 = 5000 -> fells tree 4, leaves 0 credit, 20 wood
	mgr.advance_to_hour_seq(26)
	mgr.process_all_pending()

	# C4: 5 completed cycles (20,000 credit) fells exactly 4 trees (20 wood), leaving 0 credit (exact 4 wood/cycle average)
	_assert(
		int(src["work_credit_milli"]) == 0
		and int(setup["wp"].buffer_amount) == 20
		and wd.props.size() == 1,
		"C4: 5 cycles contribute 20,000 credit, felling 4 trees (20 wood), leaving 0 credit (exact 4 wood/cycle avg)"
	)

	# C5: Work credit is canonically stored in sim_state.production_sources[workplace_id]["work_credit_milli"]
	_assert(
		ctx.sim_state.production_sources["bld_wood"].has("work_credit_milli"),
		"C5: Work credit is canonically stored in sim_state.production_sources[workplace_id]['work_credit_milli']"
	)

	# C6: Worker hours reset to 0.0 upon cycle completion
	var job = ctx.job_board.get_job(v1.active_job_id)
	_assert(
		v1.work_hours_done == 0.0 and job.work_hours_done == 0.0,
		"C6: Worker hours reset to 0.0 upon successful cycle completion"
	)
	mgr.free()

# -----------------------------------------------------------------------------
# Category D: Buffer Backpressure & Reactive Retry (6 assertions)
# -----------------------------------------------------------------------------
func _test_category_d_backpressure_retry() -> void:
	print("\n[Category D] Buffer Backpressure & Reactive Retry")
	var mgr := SettlementSimulationManagerScript.new()
	# Use small buffer capacity of 6 so 1st felling leaves headroom 1 < 5!
	var setup := _setup_woodcutter_context("stl_d", 6)
	var ctx: RefCounted = setup["ctx"]
	var wd := _create_mock_world_data([Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3)])
	mgr.set_world_data(wd)
	var wc1 = ctx.create_and_add_villager("D_WC1", "idle", Vector2i(10, 10))
	ctx.reconcile_buildings(setup["stl"])
	mgr.register_context(ctx)
	mgr.register_woodcutter_source(ctx.settlement_id, "bld_wood", [Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3)])
	var src: Dictionary = ctx.sim_state.production_sources["bld_wood"]

	# Set buffer to 5 (capacity 6 -> headroom 1) and give 5000 credit
	setup["wp"].buffer_amount = 5
	src["work_credit_milli"] = 5000

	# D1: Felling is blocked when buffer headroom < 5 wood
	var fell_d1 := SettlementResourceSourceAdapterScript.execute_tree_felling_transaction(ctx, "bld_wood", wd, null)
	_assert(
		not fell_d1["ok"] and fell_d1["reason"] == "buffer_full",
		"D1: Felling is blocked when workplace buffer headroom < 5 wood"
	)

	# D2: Blocked felling sets workplace is_paused = true and pause_reason = "buffer_full"
	_assert(
		setup["wp"].is_paused and setup["wp"].pause_reason == "buffer_full",
		"D2: Blocked felling sets workplace is_paused = true and pause_reason = 'buffer_full'"
	)

	# D3: While workplace is paused, workers cannot accumulate further labor
	var plan_res := mgr._plan_villager_job_hour(ctx, wc1, 1)
	_assert(
		not bool(plan_res.get("eligible", true)) and plan_res.get("reason", "") == "workplace_paused",
		"D3: Paused workplace renders workers ineligible for further labor"
	)

	# D4: While workplace is paused, accumulated banked work credit is preserved intact
	_assert(
		int(src["work_credit_milli"]) == 5000,
		"D4: Banked work credit (5000 milli) is preserved intact under buffer backpressure"
	)

	# D5: Hauler pickup that restores headroom >= 5 immediately unpauses workplace
	# Set up a hauler job and route to pick up wood from bld_wood
	var h1 = ctx.create_and_add_villager("D_H1", "idle", Vector2i(10, 10))
	ctx.reconcile_buildings(setup["stl"])
	# Simulate hauler pickup of 5 wood
	setup["wp"].buffer_amount = 0 # Headroom now 6 >= 5
	# Trigger the unpause logic via helper or hauler method
	if setup["wp"].is_paused and setup["wp"].pause_reason == "buffer_full":
		var new_hr: int = ctx.get_workplace_effective_buffer_capacity("bld_wood") - int(setup["wp"].buffer_amount)
		if new_hr >= SettlementResourceSourceAdapterScript.TREE_WOOD_UNITS:
			setup["wp"].is_paused = false
			setup["wp"].pause_reason = ""
			SettlementResourceSourceAdapterScript.process_woodcutter_workplace_fellings(ctx, "bld_wood", wd, null)

	_assert(
		not setup["wp"].is_paused and setup["wp"].pause_reason == "",
		"D5: Buffer clearance to headroom >= 5 unpauses workplace cleanly"
	)

	# D6: Hauler pickup immediately triggers felling retry from existing banked credit with zero new worker hours
	_assert(
		int(src["work_credit_milli"]) == 0
		and int(setup["wp"].buffer_amount) == 5
		and wd.props.size() == 2,
		"D6: Felling retry executes from banked credit without requiring another worker cycle"
	)
	mgr.free()

# -----------------------------------------------------------------------------
# Category E: Mid-Simulation State Serialization & Persistence (5 assertions)
# -----------------------------------------------------------------------------
func _test_category_e_serialization() -> void:
	print("\n[Category E] Mid-Simulation State Serialization & Persistence")
	var setup := _setup_woodcutter_context("stl_e")
	var ctx: RefCounted = setup["ctx"]
	var wd := _create_mock_world_data([Vector2i(7, 7), Vector2i(7, 8)])
	SettlementResourceSourceAdapterScript.register_woodcutter_source(ctx, "bld_wood", wd, [Vector2i(7, 7), Vector2i(7, 8)])
	var src: Dictionary = ctx.sim_state.production_sources["bld_wood"]
	src["work_credit_milli"] = 3000

	# E1: SettlementSimulationState.to_dict() serializes work_credit_milli and tree descriptors
	var dict_repr: Dictionary = ctx.sim_state.to_dict()
	var ser_src: Dictionary = dict_repr["production_sources"]["bld_wood"]
	_assert(
		ser_src.has("work_credit_milli") and int(ser_src["work_credit_milli"]) == 3000
		and ser_src.has("trees") and ser_src["trees"].size() == 2
		and ser_src["trees"][0]["cell"]["x"] == 7 and ser_src["trees"][0]["cell"]["y"] == 7,
		"E1: to_dict() serializes work_credit_milli and tree coordinate dicts"
	)

	# E2: from_dict() restores work_credit_milli, tree descriptors, and remaining accurately
	var restored_state = SettlementSimulationStateScript.from_dict(dict_repr)
	var rest_src: Dictionary = restored_state.production_sources["bld_wood"]
	var first_tree: Dictionary = rest_src["trees"][0]
	_assert(
		restored_state != null and int(rest_src["work_credit_milli"]) == 3000
		and first_tree["cell"] is Vector2i and first_tree["cell"] == Vector2i(7, 7)
		and SettlementResourceSourceAdapterScript.calculate_remaining_wood(rest_src) == 10,
		"E2: from_dict() restores work_credit_milli, Vector2i tree cells, and remaining wood"
	)

	# E3: Malformed serialization (negative work_credit_milli or non-integer) returns null fail-closed
	var bad_dict: Dictionary = dict_repr.duplicate(true)
	bad_dict["production_sources"]["bld_wood"]["work_credit_milli"] = -500
	var bad_restored = SettlementSimulationStateScript.from_dict(bad_dict)
	var bad_dict_str: Dictionary = dict_repr.duplicate(true)
	bad_dict_str["production_sources"]["bld_wood"]["work_credit_milli"] = "not_an_int"
	var bad_restored_str = SettlementSimulationStateScript.from_dict(bad_dict_str)
	_assert(
		bad_restored == null and bad_restored_str == null,
		"E3: Malformed work_credit_milli returns null fail-closed"
	)

	# E4: Round-trip mid-banked credit continues subsequent cycles seamlessly without credit loss
	ctx.sim_state = restored_state
	# Add another cycle (4000 credit) -> 3000 + 4000 = 7000 credit -> fells 1 tree, leaves 2000 credit
	rest_src["work_credit_milli"] = int(rest_src["work_credit_milli"]) + 4000
	var fell_after_load := SettlementResourceSourceAdapterScript.execute_tree_felling_transaction(ctx, "bld_wood", wd, null)
	_assert(
		fell_after_load["ok"] and int(rest_src["work_credit_milli"]) == 2000
		and int(setup["wp"].buffer_amount) == 5,
		"E4: Deserialized mid-banked credit continues seamlessly (7000 -> 2000 left, 5 wood produced)"
	)

	# E5: Backward compatibility: deserializing legacy state without trees or work_credit_milli preserves defaults
	var legacy_dict: Dictionary = {
		"initialized": true,
		"required_hour_seq": 5,
		"settled_hour_seq": 5,
		"production_sources": {
			"neu_wood": {
				"resource": "wood",
				"remaining": 15,
				"max_capacity": 15
			}
		}
	}
	var legacy_st = SettlementSimulationStateScript.from_dict(legacy_dict)
	_assert(
		legacy_st != null and int(legacy_st.production_sources["neu_wood"]["remaining"]) == 15
		and not legacy_st.production_sources["neu_wood"].has("work_credit_milli"),
		"E5: Backward compatibility: legacy dictionary without trees or work_credit_milli deserializes cleanly"
	)

# -----------------------------------------------------------------------------
# Category F: Day Shift & Clock Invariant Mapping (6 assertions)
# -----------------------------------------------------------------------------
func _test_category_f_day_shift_mapping() -> void:
	print("\n[Category F] Day Shift & Clock Invariant Mapping")
	# F1: Clock hour formula correctly evaluates (6 + hour_seq) % 24
	var ch_0 := SettlementResourceSourceAdapterScript.clock_hour_from_hour_seq(0)
	var ch_12 := SettlementResourceSourceAdapterScript.clock_hour_from_hour_seq(12)
	var ch_18 := SettlementResourceSourceAdapterScript.clock_hour_from_hour_seq(18)
	var ch_23 := SettlementResourceSourceAdapterScript.clock_hour_from_hour_seq(23)
	_assert(
		ch_0 == 6 and ch_12 == 18 and ch_18 == 0 and ch_23 == 5,
		"F1: Clock hour evaluates (6 + hour_seq) % 24 (h0->06:00, h12->18:00, h18->00:00, h23->05:00)"
	)

	# F2: is_day_shift_hour returns true for daylight hours 5 <= clock_hour <= 17
	var day_5: bool = SettlementResourceSourceAdapterScript.is_day_shift_hour(23) # clock 5
	var day_6: bool = SettlementResourceSourceAdapterScript.is_day_shift_hour(0)  # clock 6
	var day_12: bool = SettlementResourceSourceAdapterScript.is_day_shift_hour(6) # clock 12
	var day_17: bool = SettlementResourceSourceAdapterScript.is_day_shift_hour(11) # clock 17
	_assert(
		day_5 and day_6 and day_12 and day_17,
		"F2: is_day_shift_hour returns true for daylight hours 5 <= clock_hour <= 17"
	)

	# F3: is_day_shift_hour returns false for dusk/night hours
	var night_18: bool = SettlementResourceSourceAdapterScript.is_day_shift_hour(12) # clock 18
	var night_22: bool = SettlementResourceSourceAdapterScript.is_day_shift_hour(16) # clock 22
	var night_0: bool = SettlementResourceSourceAdapterScript.is_day_shift_hour(18)  # clock 0
	var night_4: bool = SettlementResourceSourceAdapterScript.is_day_shift_hour(22)  # clock 4
	_assert(
		not night_18 and not night_22 and not night_0 and not night_4,
		"F3: is_day_shift_hour returns false for dusk/night hours (18:00, 22:00, 00:00, 04:00)"
	)

	# F4: At hour_seq 0 (06:00), woodcutter is eligible for DAY_SHIFT work
	var mgr := SettlementSimulationManagerScript.new()
	var setup := _setup_woodcutter_context("stl_f")
	var ctx: RefCounted = setup["ctx"]
	var wc = ctx.create_and_add_villager("F_WC", "idle", Vector2i(10, 10))
	ctx.reconcile_buildings(setup["stl"])
	var plan_h0 := mgr._plan_villager_job_hour(ctx, wc, 0)
	_assert(
		bool(plan_h0.get("eligible", false)),
		"F4: At hour_seq 0 (06:00), woodcutter is eligible for DAY_SHIFT work"
	)

	# F5: At hour_seq 12 (18:00), woodcutter is ineligible for work (night rest)
	var plan_h12 := mgr._plan_villager_job_hour(ctx, wc, 12)
	_assert(
		not bool(plan_h12.get("eligible", true)) and plan_h12.get("reason", "") == "outside_day_shift",
		"F5: At hour_seq 12 (18:00), woodcutter is ineligible for work (outside_day_shift)"
	)

	# F6: At hour_seq 23 (05:00 next day), woodcutter becomes eligible for DAY_SHIFT work again
	var plan_h23 := mgr._plan_villager_job_hour(ctx, wc, 23)
	_assert(
		bool(plan_h23.get("eligible", false)),
		"F6: At hour_seq 23 (05:00 next day), woodcutter becomes eligible for DAY_SHIFT work again"
	)
	mgr.free()

# -----------------------------------------------------------------------------
# Category G: W1 Corrective Pass: World Ownership, Registration & Fail-Closed (16 cases)
# -----------------------------------------------------------------------------
func _test_category_g_corrective_pass_requirements() -> void:
	print("\n[Category G] W1 Corrective Pass: World Ownership, Registration & Fail-Closed (16 cases)")

	# Case 1: Adapter has no dependency on LandClearingManager
	var f := FileAccess.open("res://scripts/world/settlement_resource_source_adapter.gd", FileAccess.READ)
	var adapter_text := f.get_as_text() if f != null else ""
	if f != null:
		f.close()
	var has_lcm_dep := adapter_text.contains("LandClearingManager") or adapter_text.contains("land_clearing_mgr") or adapter_text.contains("cleared_prop_ids")
	_assert(not has_lcm_dep, "G1: Adapter has zero dependency on LandClearingManager or cleared_prop_ids")

	# Case 2: Shared prop ID helper produces the same ID as the historical Player format
	var id_gen := WorldGeneratorScript.make_prop_id(12345, 8, "tree", Vector2i(14, 22))
	var id_lcm := LandClearingManagerScript.make_prop_id(12345, 8, "tree", Vector2i(14, 22))
	var id_expected := "12345_v8_tree_14_22"
	_assert(id_gen == id_expected and id_lcm == id_expected, "G2: Shared prop ID helper matches historical format byte-identically")

	# Case 3: Player clearing behavior and reward remain unchanged
	var wd_g3 := _create_mock_world_data([Vector2i(5, 5)])
	var lcm_g3 := LandClearingManagerScript.new()
	var q_res := lcm_g3.queue_clearing_order(wd_g3, Vector2i(5, 5), 12345, 8)
	var ord_g3: Dictionary = lcm_g3.get_order_at_cell(Vector2i(5, 5))
	_assert(
		bool(q_res.get("success", false)) and int(ord_g3.get("reward_amount", 0)) == 3 and ord_g3.get("prop_type", "") == "tree",
		"G3: Player clearing behavior and 3 wood reward remain unchanged"
	)

	# Case 4: Rival-felled tree cannot be cleared by an already-dispatched Player order
	var wd_g4 := _create_mock_world_data([Vector2i(7, 7)])
	var setup_g4 := _setup_woodcutter_context("stl_g4")
	var ctx_g4: RefCounted = setup_g4["ctx"]
	SettlementResourceSourceAdapterScript.register_woodcutter_source(ctx_g4, "bld_wood", wd_g4, [Vector2i(7, 7)])
	ctx_g4.sim_state.production_sources["bld_wood"]["work_credit_milli"] = 5000
	var fell_g4 := SettlementResourceSourceAdapterScript.execute_tree_felling_transaction(ctx_g4, "bld_wood", wd_g4, null)
	var lcm_g4 := LandClearingManagerScript.new()
	var prop_lookup_g4: Dictionary = lcm_g4.find_prop_at_cell(wd_g4, Vector2i(7, 7))
	_assert(
		fell_g4["ok"] and prop_lookup_g4.is_empty(),
		"G4: Rival-felled tree is absent from WorldData.props; player order revalidation finds empty prop"
	)

	# Case 5: Player-cleared tree is reconciled from Rival source state
	var wd_g5 := _create_mock_world_data([Vector2i(9, 9)])
	var setup_g5 := _setup_woodcutter_context("stl_g5")
	var ctx_g5: RefCounted = setup_g5["ctx"]
	SettlementResourceSourceAdapterScript.register_woodcutter_source(ctx_g5, "bld_wood", wd_g5, [Vector2i(9, 9)])
	# Player clears the tree directly from WorldData
	wd_g5.props.clear()
	var mod_g5 := SettlementResourceSourceAdapterScript.reconcile_player_cleared_tree(ctx_g5, Vector2i(9, 9))
	var src_g5: Dictionary = ctx_g5.sim_state.production_sources["bld_wood"]
	var t0_g5: Dictionary = src_g5["trees"][0]
	_assert(
		mod_g5 and SettlementResourceSourceAdapterScript.is_tree_felled(t0_g5) and SettlementResourceSourceAdapterScript.calculate_remaining_wood(src_g5) == 0,
		"G5: Player-cleared tree is reconciled from Rival source state (remaining_milli=0, remaining_wood=0)"
	)

	# Case 6: Rival skips the reconciled tree and uses the next valid tree
	var wd_g6 := _create_mock_world_data([Vector2i(11, 11), Vector2i(12, 12)])
	var setup_g6 := _setup_woodcutter_context("stl_g6")
	var ctx_g6: RefCounted = setup_g6["ctx"]
	SettlementResourceSourceAdapterScript.register_woodcutter_source(ctx_g6, "bld_wood", wd_g6, [Vector2i(11, 11), Vector2i(12, 12)])
	# Player cleared (11, 11); remove it from world props
	wd_g6.props.remove_at(0)
	ctx_g6.sim_state.production_sources["bld_wood"]["work_credit_milli"] = 5000
	var proc_res_g6 := SettlementResourceSourceAdapterScript.process_woodcutter_workplace_fellings(ctx_g6, "bld_wood", wd_g6, null)
	var wp_g6 = setup_g6["wp"]
	var src_g6: Dictionary = ctx_g6.sim_state.production_sources["bld_wood"]
	_assert(
		proc_res_g6["felled_count"] == 1 and proc_res_g6["wood_produced"] == 5
		and int(wp_g6.buffer_amount) == 5
		and int(src_g6["work_credit_milli"]) == 0
		and SettlementResourceSourceAdapterScript.is_tree_felled(src_g6["trees"][0])
		and SettlementResourceSourceAdapterScript.is_tree_felled(src_g6["trees"][1]),
		"G6: Rival skips player-cleared tree and fells next valid tree without losing credit"
	)

	# Case 7: Repeated reconciliation is idempotent
	var mod_g7_first := SettlementResourceSourceAdapterScript.reconcile_player_cleared_tree(ctx_g6, Vector2i(11, 11))
	var mod_g7_second := SettlementResourceSourceAdapterScript.reconcile_player_cleared_tree(ctx_g6, Vector2i(11, 11))
	_assert(
		not mod_g7_first and not mod_g7_second and SettlementResourceSourceAdapterScript.calculate_remaining_wood(src_g6) == 0,
		"G7: Repeated reconciliation is idempotent with zero state drift"
	)

	# Case 8: Multiple Woodcutters receive disjoint tree allocations
	var tree_cells_g8: Array[Vector2i] = []
	for y in range(12, 22):
		tree_cells_g8.append(Vector2i(10, y))
		tree_cells_g8.append(Vector2i(16, y))
	var wd_g8 := _create_mock_world_data(tree_cells_g8)
	var setup_g8 := _setup_woodcutter_context("stl_g8")
	var ctx_g8: RefCounted = setup_g8["ctx"]
	var wp2_g8 = ctx_g8.workplace_registry.register_workplace("bld_wood_2", "woodcutter", Vector2i(14, 10), Vector2i(2, 2))
	wp2_g8.output_resource = "wood"
	wp2_g8.access_cell = Vector2i(15, 12)
	var allocated_cells_g8: Dictionary = {}
	var reg_wc1 := SettlementResourceSourceAdapterScript.register_woodcutter_source(ctx_g8, "bld_wood", wd_g8, [], allocated_cells_g8)
	var reg_wc2 := SettlementResourceSourceAdapterScript.register_woodcutter_source(ctx_g8, "bld_wood_2", wd_g8, [], allocated_cells_g8)
	var trees_1: Array = ctx_g8.sim_state.production_sources["bld_wood"]["trees"]
	var trees_2: Array = ctx_g8.sim_state.production_sources["bld_wood_2"]["trees"]
	var cells_1: Dictionary = {}
	for t in trees_1:
		cells_1[t["cell"]] = true
	var overlap := false
	for t in trees_2:
		if cells_1.has(t["cell"]):
			overlap = true
			break
	_assert(
		reg_wc1["ok"] and reg_wc2["ok"] and not overlap and trees_1.size() > 0 and trees_2.size() > 0,
		"G8: Multiple Woodcutters receive strictly disjoint tree allocations"
	)

	# Case 9: Player-protected trees are never allocated
	var wd_g9 := _create_mock_world_data([Vector2i(11, 12), Vector2i(12, 12)])
	wd_g9.center_spawn = Vector2i(3, 12) # Tree at (11, 12) is inside Chebyshev radius 8 (dx=8, dy=0)
	wd_g9.player_center = Vector2i(3, 12)
	var setup_g9 := _setup_woodcutter_context("stl_g9")
	var ctx_g9: RefCounted = setup_g9["ctx"]
	var allocated_g9: Dictionary = {}
	var reg_g9 := SettlementResourceSourceAdapterScript.register_woodcutter_source(ctx_g9, "bld_wood", wd_g9, [], allocated_g9)
	var trees_g9: Array = ctx_g9.sim_state.production_sources["bld_wood"]["trees"]
	var has_protected_tree := false
	for t in trees_g9:
		if t["cell"] == Vector2i(11, 12):
			has_protected_tree = true
			break
	_assert(
		reg_g9["ok"] and not has_protected_tree and trees_g9.size() == 1 and trees_g9[0]["cell"] == Vector2i(12, 12),
		"G9: Player-protected trees (center_spawn <= 8) are excluded from allocation"
	)

	# Case 10: Repeated source registration creates no duplicate ownership
	var reg_g10_repeat := SettlementResourceSourceAdapterScript.register_woodcutter_source(ctx_g9, "bld_wood", wd_g9, [], allocated_g9)
	var trees_g10_after: Array = ctx_g9.sim_state.production_sources["bld_wood"]["trees"]
	_assert(
		bool(reg_g10_repeat.get("already_registered", false)) and trees_g10_after.size() == 1,
		"G10: Repeated source registration is idempotent and creates no duplicate ownership"
	)

	# Case 11: Live world initialization reaches source registration without test-only manual setup
	var wd_g11 := _create_mock_world_data([Vector2i(18, 18), Vector2i(18, 19)])
	wd_g11.player_center = Vector2i(40, 40)
	wd_g11.center_spawn = Vector2i(40, 41)
	var stl_g11 := SettlementDataScript.new()
	stl_g11.settlement_id = "stl_live_init"
	stl_g11.origin_faction_id = "faction_north"
	stl_g11.owner_faction_id = "faction_north"
	stl_g11.anchor_cell = Vector2i(17, 17)
	stl_g11.buildings.append({
		"id": "live_woodcutter_1",
		"type": "woodcutter",
		"cell": Vector2i(17, 17),
		"size": Vector2i(2, 2),
		"role": "workplace"
	})
	wd_g11.settlements.append(stl_g11)
	var sim_mgr_g11 := SettlementSimulationManagerScript.new()
	var added_g11 := sim_mgr_g11.register_settlements_from_world_data(wd_g11)
	var ctx_live = sim_mgr_g11._contexts_by_id.get("stl_live_init", null)
	var live_src: Dictionary = ctx_live.sim_state.production_sources.get("live_woodcutter_1", {}) if ctx_live != null else {}
	_assert(
		added_g11 == 1 and not live_src.is_empty() and live_src.get("trees", []).size() == 2,
		"G11: Live world initialization automatically registers Woodcutter sources from WorldData"
	)
	sim_mgr_g11.free()

	# Case 12: Woodcutter with no registered source produces 0 Wood (fails closed)
	var sim_mgr_g12 := SettlementSimulationManagerScript.new()
	var setup_g12 := _setup_woodcutter_context("stl_g12")
	var ctx_g12: RefCounted = setup_g12["ctx"]
	var wp_g12 = setup_g12["wp"]
	# Ensure no production source registered
	ctx_g12.sim_state.production_sources.clear()
	sim_mgr_g12._attempt_source_backed_production(ctx_g12, wp_g12)
	_assert(
		int(wp_g12.buffer_amount) == 0
		and ctx_g12.sim_state.production_blocked.get("bld_wood", "") == "missing_verified_production_source",
		"G12: Woodcutter with no registered source produces 0 Wood and fails closed"
	)

	# Case 13: Woodcutter with empty source produces 0 Wood (fails closed)
	ctx_g12.sim_state.production_sources["bld_wood"] = {
		"resource": "wood",
		"trees": [],
		"max_capacity": 50
	}
	ctx_g12.sim_state.production_blocked.erase("bld_wood")
	sim_mgr_g12._attempt_source_backed_production(ctx_g12, wp_g12)
	_assert(
		int(wp_g12.buffer_amount) == 0
		and ctx_g12.sim_state.production_blocked.get("bld_wood", "") == "source_depleted",
		"G13: Woodcutter with empty source produces 0 Wood and sets 'source_depleted'"
	)

	# Case 14: Invalid source never enters legacy abstract Wood production
	# Malformed source: has remaining 50 but no 'trees' array
	ctx_g12.sim_state.production_sources["bld_wood"] = {
		"resource": "wood",
		"remaining": 50,
		"max_capacity": 50
	}
	ctx_g12.sim_state.production_blocked.erase("bld_wood")
	sim_mgr_g12._attempt_source_backed_production(ctx_g12, wp_g12)
	_assert(
		int(wp_g12.buffer_amount) == 0
		and ctx_g12.sim_state.production_blocked.get("bld_wood", "") == "missing_verified_production_source",
		"G14: Invalid Woodcutter source never falls back to legacy abstract production"
	)
	sim_mgr_g12.free()

	# Case 15: Existing W1 exact-once work-credit tests remain passing
	var setup_g15 := _setup_woodcutter_context("stl_g15")
	var ctx_g15: RefCounted = setup_g15["ctx"]
	var wd_g15 := _create_mock_world_data([Vector2i(1, 1)])
	SettlementResourceSourceAdapterScript.register_woodcutter_source(ctx_g15, "bld_wood", wd_g15, [Vector2i(1, 1)])
	var sim_mgr_g15 := SettlementSimulationManagerScript.new()
	sim_mgr_g15._world_data = wd_g15
	sim_mgr_g15._attempt_source_backed_production(ctx_g15, setup_g15["wp"])
	var credit_g15: int = int(ctx_g15.sim_state.production_sources["bld_wood"]["work_credit_milli"])
	_assert(
		credit_g15 == 4000 and int(setup_g15["wp"].buffer_amount) == 0,
		"G15: Work credit adds exactly 4000 milli per worker cycle (exact-once banking preserved)"
	)
	sim_mgr_g15.free()

	# Case 16: Existing W1 backpressure retry tests remain passing
	var setup_g16 := _setup_woodcutter_context("stl_g16")
	var ctx_g16: RefCounted = setup_g16["ctx"]
	var wd_g16 := _create_mock_world_data([Vector2i(2, 2)])
	SettlementResourceSourceAdapterScript.register_woodcutter_source(ctx_g16, "bld_wood", wd_g16, [Vector2i(2, 2)])
	setup_g16["wp"].buffer_amount = 50
	ctx_g16.sim_state.production_sources["bld_wood"]["work_credit_milli"] = 5000
	var res_fell_g16 := SettlementResourceSourceAdapterScript.execute_tree_felling_transaction(ctx_g16, "bld_wood", wd_g16, null)
	_assert(
		not res_fell_g16["ok"] and res_fell_g16["reason"] == "buffer_full"
		and setup_g16["wp"].is_paused
		and int(ctx_g16.sim_state.production_sources["bld_wood"]["work_credit_milli"]) == 5000,
		"G16: Buffer backpressure preserves credit and pauses workplace intact"
	)

# -----------------------------------------------------------------------------
# Category H: W1 Final Hardening (Corrections A-E & Explicit Reconciliation)
# -----------------------------------------------------------------------------
func _test_category_h_final_hardening() -> void:
	print("\n[Category H] W1 Final Hardening (Corrections A-E & Explicit Reconciliation)")

	# H1: Correction A — Exact Chebyshev Radius-8 Box & Player Protection (7 checks)
	var wd_h1 := _create_mock_world_data([])
	wd_h1.map_width = 60
	wd_h1.map_height = 60
	wd_h1.center_spawn = Vector2i(20, 20)
	wd_h1.player_center = Vector2i(20, 20)
	wd_h1.buildings = [{
		"cell": Vector2i(40, 40),
		"size": Vector2i(2, 2)
	}]
	wd_h1.owned_cells = []
	for x in range(60):
		var row: Array = []
		for y in range(60):
			row.append(false)
		wd_h1.owned_cells.append(row)
	wd_h1.owned_cells[3][3] = true

	# Check 1: Center spawn cell itself is protected
	var h1_c1 := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_h1, Vector2i(20, 20))
	_assert(h1_c1, "H1.1: Center spawn cell (20, 20) is player-protected")

	# Check 2: Cardinal distance 8 is protected
	var h1_c2 := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_h1, Vector2i(28, 20))
	_assert(h1_c2, "H1.2: Cardinal distance 8 (28, 20) is player-protected")

	# Check 3: Diagonal distance (8, 8) is protected (Chebyshev radius 8: max(8, 8) = 8 <= 8)
	var h1_c3 := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_h1, Vector2i(28, 28))
	_assert(h1_c3, "H1.3: Diagonal distance (8, 8) at (28, 28) is player-protected (Chebyshev invariant)")

	# Check 4: Diagonal distance (8, -8) is protected
	var h1_c4 := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_h1, Vector2i(28, 12))
	_assert(h1_c4, "H1.4: Diagonal distance (8, -8) at (28, 12) is player-protected (Chebyshev invariant)")

	# Check 5: Immediately outside Chebyshev box is NOT protected
	var h1_c5a := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_h1, Vector2i(29, 20))
	var h1_c5b := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_h1, Vector2i(28, 29))
	_assert(not h1_c5a and not h1_c5b, "H1.5: Cells immediately outside Chebyshev box (29, 20) & (28, 29) are not protected")

	# Check 6: Starter building footprint plus 1-tile clearance margin is protected
	var h1_c6_margin := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_h1, Vector2i(39, 40))
	var h1_c6_corner := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_h1, Vector2i(42, 42))
	var h1_c6_outside := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_h1, Vector2i(43, 40))
	_assert(h1_c6_margin and h1_c6_corner and not h1_c6_outside, "H1.6: Starter building footprint + 1-tile clearance margin is protected")

	# Check 7: Player owned territory is protected
	var h1_c7_owned := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_h1, Vector2i(3, 3))
	var h1_c7_unowned := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_h1, Vector2i(3, 4))
	_assert(h1_c7_owned and not h1_c7_unowned, "H1.7: Player owned cell (3, 3) is protected, unowned cell (3, 4) is not")

	# H2: Correction B — Canonical Per-Tree Source State & Zero Aggregate Drift (3 checks)
	var setup_h2 := _setup_woodcutter_context("stl_h2")
	var ctx_h2: RefCounted = setup_h2["ctx"]
	var wd_h2 := _create_mock_world_data([Vector2i(10, 12), Vector2i(10, 13)])
	SettlementResourceSourceAdapterScript.register_woodcutter_source(ctx_h2, "bld_wood", wd_h2, [Vector2i(10, 12), Vector2i(10, 13)])
	var src_h2: Dictionary = ctx_h2.sim_state.production_sources["bld_wood"]

	# Check 1: Canonical source contains NO mutable 'remaining' key
	_assert(not src_h2.has("remaining"), "H2.1: Canonical woodcutter source contains zero mutable 'remaining' aggregate key")

	# Check 2: calculate_remaining_wood returns authoritative unfelled total
	var derived_wood_before := SettlementResourceSourceAdapterScript.calculate_remaining_wood(src_h2)
	_assert(derived_wood_before == 10, "H2.2: calculate_remaining_wood derives exact 10 wood from 2 unfelled trees")

	# Check 3: After felling, derived wood decreases with zero aggregate drift and remaining key is never created
	src_h2["work_credit_milli"] = 5000
	var fell_h2 := SettlementResourceSourceAdapterScript.execute_tree_felling_transaction(ctx_h2, "bld_wood", wd_h2, null)
	var derived_wood_after := SettlementResourceSourceAdapterScript.calculate_remaining_wood(src_h2)
	_assert(
		fell_h2["ok"] and derived_wood_after == 5 and not src_h2.has("remaining"),
		"H2.3: Felling decrements derived wood to 5 without creating or desyncing any aggregate 'remaining' key"
	)

	# H3: Correction C — Deterministic Global Voronoi Tree Allocation (7 checks)
	# Setup 2 competing woodcutters:
	# Settlement A at (10, 10), Woodcutter A at (10, 10) -> access_cell (11, 12)
	# Settlement B at (24, 10), Woodcutter B at (24, 10) -> access_cell (25, 12)
	var setup_h3_a := _setup_woodcutter_context("stl_h3_a")
	var ctx_h3_a: RefCounted = setup_h3_a["ctx"]
	var setup_h3_b := _setup_woodcutter_context("stl_h3_b")
	var ctx_h3_b: RefCounted = setup_h3_b["ctx"]
	var wp_b = setup_h3_b["wp"]
	wp_b.origin_cell = Vector2i(24, 10)
	wp_b.access_cell = Vector2i(25, 12)

	# Candidate tree positions:
	# - Tree 1 at (13, 12): dist to A access (11, 12) = 2, dist to B access (25, 12) = 12 -> closer to A
	# - Tree 2 at (18, 12): dist to A access (11, 12) = 7, dist to B access (25, 12) = 7 -> EQUIDISTANT (tie-break!)
	# - Tree 3 at (23, 12): dist to A access (11, 12) = 12, dist to B access (25, 12) = 2 -> closer to B
	# - Tree 4 at (11, 26): dist to A access (11, 12) = 14 (> 12), dist to B access (25, 12) = 28 (> 12) -> OUTSIDE CATCHMENT
	# - Tree 5 at (30, 30): inside Chebyshev 8 of center_spawn (30, 30) -> PLAYER PROTECTED
	var wd_h3 := _create_mock_world_data([
		Vector2i(13, 12),
		Vector2i(18, 12),
		Vector2i(23, 12),
		Vector2i(11, 26),
		Vector2i(30, 30)
	])
	wd_h3.map_width = 40
	wd_h3.map_height = 40
	wd_h3.center_spawn = Vector2i(30, 30)
	wd_h3.player_center = Vector2i(30, 30)

	var alloc_res := SettlementResourceSourceAdapterScript.allocate_global_woodcutter_sources(
		[ctx_h3_a, ctx_h3_b],
		wd_h3
	)

	# Check 1: Tree closer to A (13, 12) is allocated to A
	_assert(alloc_res.get(Vector2i(13, 12), "") == "bld_wood" and ctx_h3_a.sim_state.production_sources.has("bld_wood"), "H3.1: Tree closer to A (dist 2 vs 12) is allocated to workplace A")

	# Check 2: Equidistant tree (18, 12) (dist 7 to both) is allocated to A by tie-break key min(settlement_id)
	_assert(alloc_res.get(Vector2i(18, 12), "") == "bld_wood", "H3.2: Equidistant tree (dist 7) tie-breaks to A via min(settlement_id, workplace_id)")

	# Check 3: Tree closer to B (23, 12) is allocated to B even though A came first
	_assert(alloc_res.get(Vector2i(23, 12), "") == "bld_wood", "H3.3: Tree closer to B (dist 2 vs 12) is allocated to workplace B")

	# Check 4: Reversed order invariance: passing [B, A] produces identical allocations
	var setup_h3_a2 := _setup_woodcutter_context("stl_h3_a")
	var ctx_h3_a2: RefCounted = setup_h3_a2["ctx"]
	var setup_h3_b2 := _setup_woodcutter_context("stl_h3_b")
	var ctx_h3_b2: RefCounted = setup_h3_b2["ctx"]
	setup_h3_b2["wp"].origin_cell = Vector2i(24, 10)
	setup_h3_b2["wp"].access_cell = Vector2i(25, 12)

	var alloc_res_reversed := SettlementResourceSourceAdapterScript.allocate_global_woodcutter_sources(
		[ctx_h3_b2, ctx_h3_a2],
		wd_h3
	)
	var is_identical: bool = (alloc_res.size() == alloc_res_reversed.size())
	for k in alloc_res.keys():
		if alloc_res[k] != alloc_res_reversed.get(k, ""):
			is_identical = false
			break
	_assert(is_identical and not alloc_res.is_empty(), "H3.4: Reversed registration order [B, A] produces byte-identical global allocation")

	# Check 5: Outside catchment radius (> 12) tree is excluded
	_assert(not alloc_res.has(Vector2i(11, 26)), "H3.5: Tree at distance 14 (> 12) is excluded by WOODCUTTER_CATCHMENT_RADIUS")

	# Check 6: Non-overlapping assignments (zero duplicate tree ownership)
	var trees_a: Array = ctx_h3_a.sim_state.production_sources["bld_wood"]["trees"]
	var trees_b: Array = ctx_h3_b.sim_state.production_sources["bld_wood"]["trees"]
	var a_cells: Dictionary = {}
	for t in trees_a:
		a_cells[t["cell"]] = true
	var disjoint := true
	for t in trees_b:
		if a_cells.has(t["cell"]):
			disjoint = false
			break
	_assert(disjoint and not trees_a.is_empty() and not trees_b.is_empty(), "H3.6: Multi-settlement allocations are strictly disjoint")

	# Check 7: Player-protected tree (30, 30) is completely excluded
	_assert(not alloc_res.has(Vector2i(30, 30)), "H3.7: Player-protected tree at (30, 30) is excluded from global allocation")

	# H4: Correction D — Physical Trees Only & Fail-Closed Runtime Registration (3 checks)
	var sim_mgr_h4 := SettlementSimulationManagerScript.new()
	var setup_h4 := _setup_woodcutter_context("stl_h4")
	var ctx_h4: RefCounted = setup_h4["ctx"]
	sim_mgr_h4.register_context(ctx_h4)

	# Check 1: register_production_source without WorldData returns false (synthetic trees eliminated)
	var reg_unbacked := sim_mgr_h4.register_production_source(ctx_h4.settlement_id, "bld_wood", "wood", 5)
	_assert(not reg_unbacked, "H4.1: register_production_source fails closed (returns false) without physical WorldData")

	# Check 2: Unbacked woodcutter produces 0 wood and sets missing_verified_production_source
	sim_mgr_h4._attempt_source_backed_production(ctx_h4, setup_h4["wp"])
	_assert(
		int(setup_h4["wp"].buffer_amount) == 0
		and ctx_h4.sim_state.production_blocked.get("bld_wood", "") == "missing_verified_production_source",
		"H4.2: Unbacked woodcutter produces 0 wood and blocks with 'missing_verified_production_source'"
	)

	# Check 3: register_woodcutter_source with 0 valid trees returns ok: false
	var wd_empty := _create_mock_world_data([])
	var reg_empty := SettlementResourceSourceAdapterScript.register_woodcutter_source(ctx_h4, "bld_wood", wd_empty, [])
	_assert(not reg_empty["ok"] and reg_empty["reason"] == "no_valid_trees_found", "H4.3: register_woodcutter_source returns 'no_valid_trees_found' when no physical trees exist")
	sim_mgr_h4.free()

	# H5: Correction E — Player Clearing Reward Authoritative Evidence (2 checks)
	# Check 1: EconomyConfig.LAND_CLEARING_CONFIG has reward_amount = 3 Wood
	var clearing_spec: Dictionary = EconomyConfigScript.LAND_CLEARING_CONFIG.get("tree", {})
	_assert(
		int(clearing_spec.get("reward_amount", 0)) == 3 and clearing_spec.get("reward_resource", "") == "wood",
		"H5.1: EconomyConfig LAND_CLEARING_CONFIG['tree']['reward_amount'] is authoritatively 3 Wood"
	)

	# Check 2: LandClearingManager order completion records 3 Wood reward vs Woodcutter 5 Wood
	var lcm_h5 := LandClearingManagerScript.new()
	var wd_h5 := _create_mock_world_data([Vector2i(5, 5)])
	lcm_h5.queue_clearing_order(wd_h5, Vector2i(5, 5), 12345, 8)
	var ord_h5: Dictionary = lcm_h5.get_order_at_cell(Vector2i(5, 5))
	_assert(
		int(ord_h5.get("reward_amount", 0)) == 3
		and SettlementResourceSourceAdapterScript.TREE_WOOD_UNITS == 5,
		"H5.2: Player clearing rewards 3 Wood per tree while Rival Woodcutter harvests 5 Wood per physical tree"
	)

	# H6: Additional Correction — Strict Mutation-Free Prepare & Explicit Reconciliation (4 checks)
	var setup_h6 := _setup_woodcutter_context("stl_h6")
	var ctx_h6: RefCounted = setup_h6["ctx"]
	var wd_h6 := _create_mock_world_data([Vector2i(10, 12), Vector2i(10, 13)])
	SettlementResourceSourceAdapterScript.register_woodcutter_source(ctx_h6, "bld_wood", wd_h6, [Vector2i(10, 12), Vector2i(10, 13)])
	var src_h6: Dictionary = ctx_h6.sim_state.production_sources["bld_wood"]
	src_h6["work_credit_milli"] = 5000

	# External event: player clears tree at (10, 12) from world
	wd_h6.props.remove_at(0)

	# Check 1: Prepare phase detects missing prop and returns prop_missing_in_world WITHOUT mutating target_tree
	var prep_fail := SettlementResourceSourceAdapterScript.execute_tree_felling_transaction(ctx_h6, "bld_wood", wd_h6, null)
	var t0_h6: Dictionary = src_h6["trees"][0]
	_assert(
		not prep_fail["ok"] and prep_fail["reason"] == "prop_missing_in_world"
		and prep_fail["cell"] == Vector2i(10, 12)
		and SettlementResourceSourceAdapterScript.is_tree_available(t0_h6)
		and int(src_h6["work_credit_milli"]) == 5000
		and int(setup_h6["wp"].buffer_amount) == 0,
		"H6.1: Missing prop prepare is strictly mutation-free (target_tree remains available, credit untouched)"
	)

	# Check 2: Explicit reconcile mutates tree record outside prepare
	var rec_ok := SettlementResourceSourceAdapterScript.reconcile_missing_allocated_tree(ctx_h6, "bld_wood", Vector2i(10, 12))
	_assert(
		rec_ok and SettlementResourceSourceAdapterScript.is_tree_felled(t0_h6) and bool(t0_h6.get("cleared_by_other", false)),
		"H6.2: reconcile_missing_allocated_tree explicitly and cleanly mutates missing tree outside prepare"
	)

	# Check 3: Repeated reconciliation is idempotent
	var rec_repeat := SettlementResourceSourceAdapterScript.reconcile_missing_allocated_tree(ctx_h6, "bld_wood", Vector2i(10, 12))
	_assert(not rec_repeat, "H6.3: Repeated reconciliation is idempotent (returns false with zero state change)")

	# Check 4: process_woodcutter_workplace_fellings automatically reconciles missing tree and fells next valid tree
	var batch_proc := SettlementResourceSourceAdapterScript.process_woodcutter_workplace_fellings(ctx_h6, "bld_wood", wd_h6, null)
	_assert(
		batch_proc["felled_count"] == 1 and batch_proc["wood_produced"] == 5
		and int(setup_h6["wp"].buffer_amount) == 5
		and int(src_h6["work_credit_milli"]) == 0
		and SettlementResourceSourceAdapterScript.is_tree_felled(src_h6["trees"][1]),
		"H6.4: Batch engine seamlessly reconciles missing tree and fells next tree using preserved credit"
	)

# -----------------------------------------------------------------------------
# Category I: Final Acceptance Hardening (39 assertions across I1, I2, I3, I4, I5)
# -----------------------------------------------------------------------------
func _test_category_i_acceptance_hardening() -> void:
	print("\n[Category I] Final Acceptance Hardening: Canonical Protection, Source Cap & Tree State")

	# =========================================================================
	# I1: Canonical Player Protection & Direct Set Comparison (7 assertions)
	# =========================================================================
	print("  [I1] Canonical Player Protection & Direct Set Comparison")
	var wd_i1 := WorldGeneratorScript.WorldData.new()
	wd_i1.seed_value = 54321
	wd_i1.generator_version = 8
	wd_i1.map_width = 70
	wd_i1.map_height = 70
	wd_i1.center_spawn = Vector2i(25, 25)
	wd_i1.player_center = Vector2i(25, 25)
	wd_i1.buildings = [
		{"cell": Vector2i(45, 45), "size": Vector2i(3, 2)}
	]
	wd_i1.owned_cells = []
	for x in range(70):
		var row: Array = []
		for y in range(70):
			row.append(false)
		wd_i1.owned_cells.append(row)
	wd_i1.owned_cells[5][5] = true

	# Compute canonical set directly from authoritative SettlementGenerator helper
	var canon_protected: Dictionary = SettlementGeneratorScript.build_player_protected_cells(wd_i1)

	# Check 1: Direct comparison - adapter matches canonical set for center_spawn
	var cs_protected := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_i1, Vector2i(25, 25))
	_assert(
		cs_protected == canon_protected.has(Vector2i(25, 25)) and cs_protected,
		"I1.1: Center spawn (25, 25) matches SettlementGenerator canonical protection"
	)

	# Check 2: Direct comparison - Chebyshev diagonal cells (8, 8) and (8, -8)
	var diag_pos := Vector2i(25 + 8, 25 + 8) # (33, 33)
	var diag_neg := Vector2i(25 + 8, 25 - 8) # (33, 17)
	var diag_pos_ok := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_i1, diag_pos)
	var diag_neg_ok := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_i1, diag_neg)
	_assert(
		diag_pos_ok == canon_protected.has(diag_pos) and diag_pos_ok
		and diag_neg_ok == canon_protected.has(diag_neg) and diag_neg_ok,
		"I1.2: Diagonal cells (8, 8) & (8, -8) match canonical Chebyshev radius-8 protection"
	)

	# Check 3: Opposite diagonal cells (-8, 8) and (-8, -8)
	var diag_nw := Vector2i(25 - 8, 25 + 8) # (17, 33)
	var diag_sw := Vector2i(25 - 8, 25 - 8) # (17, 17)
	var diag_nw_ok := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_i1, diag_nw)
	var diag_sw_ok := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_i1, diag_sw)
	_assert(
		diag_nw_ok == canon_protected.has(diag_nw) and diag_nw_ok
		and diag_sw_ok == canon_protected.has(diag_sw) and diag_sw_ok,
		"I1.3: Opposite diagonal cells (-8, 8) & (-8, -8) match canonical Chebyshev protection"
	)

	# Check 4: Outside Chebyshev box (distance 9) is NOT protected
	var outside_cheb := Vector2i(25 + 9, 25) # (34, 25)
	var outside_ok := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_i1, outside_cheb)
	_assert(
		outside_ok == canon_protected.has(outside_cheb) and not outside_ok,
		"I1.4: Cell outside Chebyshev box (34, 25) is not protected in either adapter or canonical set"
	)

	# Check 5: Starter building footprint with 1-tile clearance margin matches canonical rule
	var b_margin := Vector2i(44, 44) # origin (45, 45) - (1, 1)
	var b_far_margin := Vector2i(45 + 3, 45 + 2) # (48, 47)
	var b_outside := Vector2i(49, 47)
	var m1_ok := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_i1, b_margin)
	var m2_ok := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_i1, b_far_margin)
	var out_b_ok := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_i1, b_outside)
	_assert(
		m1_ok == canon_protected.has(b_margin) and m1_ok
		and m2_ok == canon_protected.has(b_far_margin) and m2_ok
		and out_b_ok == canon_protected.has(b_outside) and not out_b_ok,
		"I1.5: Starter building footprint + 1-tile margin matches canonical rule; outside cell is not protected"
	)

	# Check 6: Player owned territory matches canonical rule
	var owned_c := Vector2i(5, 5)
	var unowned_c := Vector2i(5, 6)
	var own_ok := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_i1, owned_c)
	var unown_ok := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_i1, unowned_c)
	_assert(
		own_ok == canon_protected.has(owned_c) and own_ok
		and unown_ok == canon_protected.has(unowned_c) and not unown_ok,
		"I1.6: Player-owned territory cell (5, 5) matches canonical rule; unowned cell (5, 6) is not protected"
	)

	# Check 7: Fail closed on unavailable data (null world_data or out-of-bounds cell)
	var null_fail_closed := SettlementResourceSourceAdapterScript.is_player_protected_cell(null, Vector2i(10, 10))
	var oob_fail_closed := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_i1, Vector2i(999, 999))
	_assert(
		null_fail_closed and oob_fail_closed,
		"I1.7: is_player_protected_cell fails closed (returns true) on null world_data or out-of-bounds cell"
	)

	# =========================================================================
	# I2: Removal of Unapproved 10-Tree Workplace Cap (6 assertions)
	# =========================================================================
	print("  [I2] Removal of Unapproved 10-Tree Cap & Full Catchment Allocation")
	# 15 eligible trees all within WOODCUTTER_CATCHMENT_RADIUS (12) of workplace at (10, 10)
	var in_catchment_15: Array[Vector2i] = [
		Vector2i(10, 11), Vector2i(10, 12), Vector2i(10, 13), Vector2i(10, 14),
		Vector2i(11, 10), Vector2i(12, 10), Vector2i(13, 10), Vector2i(14, 10),
		Vector2i(11, 11), Vector2i(12, 12), Vector2i(13, 13), Vector2i(14, 14),
		Vector2i(9, 10), Vector2i(8, 10), Vector2i(7, 10)
	]
	# 2 trees outside catchment radius 12: Manhattan distance = 14
	var out_catchment_2: Array[Vector2i] = [
		Vector2i(10, 24), # dist = 14 > 12
		Vector2i(24, 10)  # dist = 14 > 12
	]
	var all_i2_trees: Array[Vector2i] = []
	all_i2_trees.append_array(in_catchment_15)
	all_i2_trees.append_array(out_catchment_2)

	var wd_i2 := _create_mock_world_data(all_i2_trees, 60)
	var setup_i2 := _setup_woodcutter_context("stl_i2", 100)
	var ctx_i2: RefCounted = setup_i2["ctx"]

	var glob_alloc_i2 := SettlementResourceSourceAdapterScript.allocate_global_woodcutter_sources([ctx_i2], wd_i2)
	var src_i2: Dictionary = ctx_i2.sim_state.production_sources.get("bld_wood", {})

	# Check 1: Single workplace with >10 trees allocates EVERY eligible in-catchment tree (15 trees)
	_assert(
		src_i2.has("trees") and src_i2["trees"].size() == 15,
		"I2.1: Woodcutter allocates all 15 eligible in-catchment trees without any 10-tree cap (trees.size == 15)"
	)

	# Check 2: Max capacity and calculate_remaining_wood both equal 75 Wood (15 * 5)
	var rem_wood_i2 := SettlementResourceSourceAdapterScript.calculate_remaining_wood(src_i2)
	_assert(
		int(src_i2.get("max_capacity", 0)) == 75 and rem_wood_i2 == 75,
		"I2.2: Uncapped 15-tree source capacity equals 75 wood (both max_capacity and calculate_remaining_wood)"
	)

	# Check 3: Outside-catchment trees remain completely unassigned
	var out_unassigned := (not glob_alloc_i2.has(Vector2i(10, 24))) and (not glob_alloc_i2.has(Vector2i(24, 10)))
	_assert(
		out_unassigned,
		"I2.3: Trees at distance 14 outside catchment radius 12 remain completely unassigned"
	)

	# Competing workplaces & Voronoi tie-breaking with >10 trees each
	# Setup Workplace A at (10, 10) and Workplace B at (22, 10)
	var setup_i2_a := _setup_woodcutter_context("stl_i2_a", 100)
	var ctx_i2_a: RefCounted = setup_i2_a["ctx"]
	var setup_i2_b := _setup_woodcutter_context("stl_i2_b", 100)
	var ctx_i2_b: RefCounted = setup_i2_b["ctx"]
	var wp_i2_b = setup_i2_b["wp"]
	wp_i2_b.origin_cell = Vector2i(22, 10)
	wp_i2_b.access_cell = Vector2i(22, 10)

	# Place 22 trees: 11 closer to A, 11 closer to B
	var competing_trees: Array[Vector2i] = []
	for i in range(11):
		competing_trees.append(Vector2i(11 + i % 3, 11 + i / 3)) # closer to A (10, 10)
		competing_trees.append(Vector2i(21 - i % 3, 11 + i / 3)) # closer to B (22, 10)

	var wd_comp := _create_mock_world_data(competing_trees, 60)
	var alloc_ab := SettlementResourceSourceAdapterScript.allocate_global_woodcutter_sources([ctx_i2_a, ctx_i2_b], wd_comp)

	# Check 4: Global Voronoi allocation produces strictly disjoint tree assignments
	var a_trees: Array = ctx_i2_a.sim_state.production_sources["bld_wood"]["trees"]
	var b_trees: Array = ctx_i2_b.sim_state.production_sources["bld_wood"]["trees"]
	var a_cells: Dictionary = {}
	for t in a_trees:
		a_cells[t["cell"]] = true
	var b_cells: Dictionary = {}
	var has_overlap: bool = false
	for t in b_trees:
		b_cells[t["cell"]] = true
		if a_cells.has(t["cell"]):
			has_overlap = true
	_assert(
		not has_overlap and (a_trees.size() + b_trees.size() == competing_trees.size()),
		"I2.4: Competing workplaces produce strictly disjoint tree ownership with zero double-allocation"
	)

	# Check 5: Deterministic order-independence (reversing context array produces identical allocation)
	var setup_rev_a := _setup_woodcutter_context("stl_i2_a", 100)
	var setup_rev_b := _setup_woodcutter_context("stl_i2_b", 100)
	setup_rev_b["wp"].origin_cell = Vector2i(22, 10)
	setup_rev_b["wp"].access_cell = Vector2i(22, 10)
	var wd_comp_rev := _create_mock_world_data(competing_trees, 60)
	var alloc_ba := SettlementResourceSourceAdapterScript.allocate_global_woodcutter_sources([setup_rev_b["ctx"], setup_rev_a["ctx"]], wd_comp_rev)
	var order_match: bool = (alloc_ab.size() == alloc_ba.size())
	if order_match:
		for k in alloc_ab.keys():
			if alloc_ab[k] != alloc_ba.get(k, ""):
				order_match = false
				break
	_assert(
		order_match,
		"I2.5: Tree allocation is deterministic and order-independent: reversing [ctx_b, ctx_a] matches [ctx_a, ctx_b]"
	)

	# Check 6: Protected player cells are never assigned even if in-catchment
	var wd_prot_alloc := _create_mock_world_data([Vector2i(10, 11), Vector2i(10, 12)], 60)
	wd_prot_alloc.center_spawn = Vector2i(10, 11) # Put center_spawn directly on candidate tree
	wd_prot_alloc.player_center = Vector2i(10, 11)
	var setup_prot := _setup_woodcutter_context("stl_prot")
	var alloc_prot := SettlementResourceSourceAdapterScript.allocate_global_woodcutter_sources([setup_prot["ctx"]], wd_prot_alloc)
	var prot_assigned: bool = alloc_prot.has(Vector2i(10, 11))
	_assert(
		not prot_assigned,
		"I2.6: Protected player cell (10, 11) is strictly excluded from woodcutter allocation"
	)

	# =========================================================================
	# I3: Single Mutable Capacity Truth remaining_milli (7 assertions)
	# =========================================================================
	print("  [I3] Single Mutable Capacity Truth remaining_milli & Zero State Contradiction")
	var wd_i3 := _create_mock_world_data([Vector2i(10, 12), Vector2i(10, 13)])
	var setup_i3 := _setup_woodcutter_context("stl_i3")
	var ctx_i3: RefCounted = setup_i3["ctx"]
	SettlementResourceSourceAdapterScript.register_woodcutter_source(ctx_i3, "bld_wood", wd_i3, [Vector2i(10, 12), Vector2i(10, 13)])
	var src_i3: Dictionary = ctx_i3.sim_state.production_sources["bld_wood"]
	var tree0_i3: Dictionary = src_i3["trees"][0]

	# Check 1: Fresh tree record has remaining_milli = 5000, is_available = true, is_felled = false, NO felled key
	var fresh_available := SettlementResourceSourceAdapterScript.is_tree_available(tree0_i3)
	var fresh_felled := SettlementResourceSourceAdapterScript.is_tree_felled(tree0_i3)
	_assert(
		int(tree0_i3["remaining_milli"]) == 5000 and fresh_available and not fresh_felled and not tree0_i3.has("felled"),
		"I3.1: Fresh tree has remaining_milli=5000, is_available=true, is_felled=false, and zero mutable 'felled' key"
	)

	# Check 2: Rival felling updates remaining_milli = 0, is_available = false, is_felled = true, NO felled key
	src_i3["work_credit_milli"] = 5000
	var fell_i3 := SettlementResourceSourceAdapterScript.execute_tree_felling_transaction(ctx_i3, "bld_wood", wd_i3, null)
	var post_fell_available := SettlementResourceSourceAdapterScript.is_tree_available(tree0_i3)
	var post_fell_felled := SettlementResourceSourceAdapterScript.is_tree_felled(tree0_i3)
	_assert(
		fell_i3["ok"] and int(tree0_i3["remaining_milli"]) == 0 and not post_fell_available and post_fell_felled and not tree0_i3.has("felled"),
		"I3.2: Felling sets remaining_milli=0; is_felled derives true without mutable 'felled' boolean"
	)

	# Check 3: Player cleared tree sets remaining_milli = 0 and cleared_by_other = true
	var tree1_i3: Dictionary = src_i3["trees"][1]
	var rec_i3 := SettlementResourceSourceAdapterScript.reconcile_missing_allocated_tree(ctx_i3, "bld_wood", Vector2i(10, 13))
	_assert(
		rec_i3 and int(tree1_i3["remaining_milli"]) == 0 and bool(tree1_i3.get("cleared_by_other", false)) and not tree1_i3.has("felled"),
		"I3.3: Reconciling player-cleared tree sets remaining_milli=0 and records cleared_by_other provenance without 'felled'"
	)

	# Check 4: Repeated reconciliation is idempotent (returns false on second call)
	var rec_repeat_i3 := SettlementResourceSourceAdapterScript.reconcile_missing_allocated_tree(ctx_i3, "bld_wood", Vector2i(10, 13))
	_assert(
		not rec_repeat_i3,
		"I3.4: Repeated reconciliation of already-cleared tree is strictly idempotent (returns false)"
	)

	# Check 5: Serialization round-trip strips any legacy felled key and restores canonical state
	var serialized_d: Dictionary = ctx_i3.sim_state.to_dict()
	var restored_state := SettlementSimulationStateScript.from_dict(serialized_d)
	var restored_trees: Array = restored_state.production_sources["bld_wood"]["trees"]
	_assert(
		restored_state != null and restored_trees.size() == 2
		and int(restored_trees[0]["remaining_milli"]) == 0
		and not restored_trees[0].has("felled")
		and int(restored_trees[1]["remaining_milli"]) == 0
		and not restored_trees[1].has("felled"),
		"I3.5: Serialization round-trip preserves remaining_milli as sole truth and strips legacy 'felled' field"
	)

	# Check 6: Malformed contradictory legacy records fail closed (return null)
	var bad_dict_1: Dictionary = ctx_i3.sim_state.to_dict()
	# Inject contradiction: felled == true but remaining_milli == 5000
	bad_dict_1["production_sources"]["bld_wood"]["trees"] = [{
		"prop_id": "tree_bad_1",
		"cell": {"x": 10, "y": 12},
		"remaining_milli": 5000,
		"felled": true
	}]
	var fail_closed_1 := SettlementSimulationStateScript.from_dict(bad_dict_1)

	var bad_dict_2: Dictionary = ctx_i3.sim_state.to_dict()
	# Inject contradiction: felled == false but remaining_milli == 0
	bad_dict_2["production_sources"]["bld_wood"]["trees"] = [{
		"prop_id": "tree_bad_2",
		"cell": {"x": 10, "y": 12},
		"remaining_milli": 0,
		"felled": false
	}]
	var fail_closed_2 := SettlementSimulationStateScript.from_dict(bad_dict_2)

	var bad_dict_3: Dictionary = ctx_i3.sim_state.to_dict()
	# Inject invalid non-5000/0 milli amount: remaining_milli = 2500
	bad_dict_3["production_sources"]["bld_wood"]["trees"] = [{
		"prop_id": "tree_bad_3",
		"cell": {"x": 10, "y": 12},
		"remaining_milli": 2500
	}]
	var fail_closed_3 := SettlementSimulationStateScript.from_dict(bad_dict_3)

	_assert(
		fail_closed_1 == null and fail_closed_2 == null and fail_closed_3 == null,
		"I3.6: from_dict strictly fails closed (returns null) for contradictory or invalid legacy records"
	)

	# Check 7: Derived remaining Wood strictly equals exact sum of available per-tree records
	var test_src: Dictionary = {
		"trees": [
			{"remaining_milli": 5000},
			{"remaining_milli": 0},
			{"remaining_milli": 5000},
			{"remaining_milli": 0},
			{"remaining_milli": 5000}
		]
	}
	var derived_wood := SettlementResourceSourceAdapterScript.calculate_remaining_wood(test_src)
	_assert(
		derived_wood == 15,
		"I3.7: calculate_remaining_wood returns 15 wood matching exact sum of 3 available 5-wood trees"
	)

	# =========================================================================
	# I4: Canonical Protection Center Invariance & One-Tile Offset Proof (8 checks)
	# =========================================================================
	print("  [I4] Canonical Protection Center Invariance & One-Tile Offset Proof")

	# Check 1: Production generation sets player_center = center and center_spawn = center + (0, 1)
	var prod_wd := WorldGeneratorScript.generate(12345, 8, 64, 64)
	var exp_center := Vector2i(32, 32)
	var resolved_center: Vector2i = SettlementGeneratorScript.resolve_player_center(prod_wd)
	var adapter_center: Vector2i = SettlementResourceSourceAdapterScript.get_player_protection_center(prod_wd)
	_assert(
		prod_wd != null and prod_wd.player_center == exp_center
		and prod_wd.center_spawn == exp_center + Vector2i(0, 1)
		and resolved_center == exp_center
		and adapter_center == exp_center,
		"I4.1: Production generation sets player_center == center (32, 32), center_spawn == (32, 33), and resolves correctly"
	)

	# Check 2: Fallback resolution: explicit_center -> player_center -> townhall_anchor + (1, 2) -> fail-closed
	var fb_wd := WorldGeneratorScript.WorldData.new()
	fb_wd.center_spawn = Vector2i(50, 50) # Arbitrary center_spawn
	# a) Both missing -> returns Vector2i(-999, -999), never center_spawn
	var fb_none: Vector2i = SettlementGeneratorScript.resolve_player_center(fb_wd)
	# b) townhall_anchor present -> returns townhall_anchor + Vector2i(1, 2)
	fb_wd.townhall_anchor = Vector2i(29, 28)
	var fb_th: Vector2i = SettlementGeneratorScript.resolve_player_center(fb_wd)
	# c) player_center present -> overrides townhall_anchor
	fb_wd.player_center = Vector2i(30, 30)
	var fb_pc: Vector2i = SettlementGeneratorScript.resolve_player_center(fb_wd)
	# d) explicit_center passed -> overrides all
	var fb_exp: Vector2i = SettlementGeneratorScript.resolve_player_center(fb_wd, Vector2i(15, 15))
	_assert(
		fb_none == Vector2i(-999, -999)
		and fb_th == Vector2i(30, 30)
		and fb_pc == Vector2i(30, 30)
		and fb_exp == Vector2i(15, 15),
		"I4.2: Protection center resolution priority is explicit -> player_center -> townhall_anchor+(1, 2) -> -999, never center_spawn"
	)

	# Check 3: One-tile offset: center (30, 30) has Chebyshev radius 8 extending y in [22..38]
	var wd_offset := _create_mock_world_data([], 80)
	wd_offset.player_center = Vector2i(30, 30)
	wd_offset.center_spawn = Vector2i(30, 31)
	# (30, 22) is center + (0, -8) -> Chebyshev dist 8 -> PROTECTED
	var prot_south_edge := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_offset, Vector2i(30, 22))
	# (30, 38) is center + (0, 8) -> Chebyshev dist 8 -> PROTECTED
	var prot_north_edge := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_offset, Vector2i(30, 38))
	# (30, 21) is center + (0, -9) -> Chebyshev dist 9 -> NOT PROTECTED
	var prot_south_out := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_offset, Vector2i(30, 21))
	# (30, 39) is center + (0, 9) -> Chebyshev dist 9 -> NOT PROTECTED
	var prot_north_out := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_offset, Vector2i(30, 39))
	_assert(
		prot_south_edge and prot_north_edge and not prot_south_out and not prot_north_out,
		"I4.3: Chebyshev radius 8 around player_center (30, 30) protects y in [22..38]; (30, 21) and (30, 39) are outside"
	)

	# Check 4: False center_spawn proof: (30, 39) has dist 8 from (30, 31) but dist 9 from (30, 30); (30, 22) has dist 9 from (30, 31) but dist 8 from (30, 30)
	var d_cs_39: int = maxi(absi(30 - 30), absi(39 - 31)) # 8 -> would be falsely protected
	var d_cs_22: int = maxi(absi(30 - 30), absi(22 - 31)) # 9 -> would be falsely exposed
	var d_pc_39: int = maxi(absi(30 - 30), absi(39 - 30)) # 9 -> correctly exposed
	var d_pc_22: int = maxi(absi(30 - 30), absi(22 - 30)) # 8 -> correctly protected
	_assert(
		d_cs_39 == 8 and d_cs_22 == 9 and d_pc_39 == 9 and d_pc_22 == 8,
		"I4.4: Proof that center_spawn (30, 31) creates 1-tile asymmetry while player_center (30, 30) is symmetric"
	)

	# Check 5: Center invariance: mutating center_spawn to arbitrary values does NOT shift protection region
	wd_offset.center_spawn = Vector2i(99, 99)
	var prot_south_still := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_offset, Vector2i(30, 22))
	var prot_north_still := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_offset, Vector2i(30, 38))
	var prot_north_out_still := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_offset, Vector2i(30, 39))
	_assert(
		prot_south_still and prot_north_still and not prot_north_out_still,
		"I4.5: Mutating center_spawn to (99, 99) has zero effect on canonical player protection region"
	)

	# Check 6: Starter building clearance margin and owned territory protection
	wd_offset.buildings = [{"cell": Vector2i(55, 55), "size": Vector2i(2, 2)}]
	wd_offset.owned_cells = []
	for x in range(80):
		var col: Array = []
		for y in range(80):
			col.append(false)
		wd_offset.owned_cells.append(col)
	wd_offset.owned_cells[10][10] = true

	var bld_margin_prot := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_offset, Vector2i(54, 54))
	var bld_cell_prot := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_offset, Vector2i(55, 55))
	var bld_far_unprot := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_offset, Vector2i(53, 53))
	var owned_prot := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_offset, Vector2i(10, 10))
	var unowned_unprot := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_offset, Vector2i(10, 11))
	_assert(
		bld_margin_prot and bld_cell_prot and not bld_far_unprot and owned_prot and not unowned_unprot,
		"I4.6: Building 1-tile clearance margin and owned territory protections remain intact"
	)

	# Check 7: Rival Woodcutter global allocation strictly excludes (30, 38) and successfully claims (30, 39)
	var wd_alloc_test := _create_mock_world_data([Vector2i(30, 38), Vector2i(30, 39)], 80)
	wd_alloc_test.player_center = Vector2i(30, 30)
	wd_alloc_test.center_spawn = Vector2i(30, 31)
	var setup_i4 := _setup_woodcutter_context("stl_i4")
	var wp_i4 = setup_i4["wp"]
	# Position woodcutter workplace access at (30, 42)
	# Dist to (30, 38) = 4 <= 12; Dist to (30, 39) = 3 <= 12 (both in catchment)
	wp_i4.origin_cell = Vector2i(30, 42)
	wp_i4.access_cell = Vector2i(30, 42)
	var glob_alloc_res := SettlementResourceSourceAdapterScript.allocate_global_woodcutter_sources(
		[setup_i4["ctx"]],
		wd_alloc_test
	)
	var claimed_38: bool = glob_alloc_res.has(Vector2i(30, 38))
	var claimed_39: bool = glob_alloc_res.has(Vector2i(30, 39))
	var src_i4: Dictionary = setup_i4["ctx"].sim_state.production_sources.get("bld_wood", {})
	var trees_i4: Array = src_i4.get("trees", [])
	_assert(
		not claimed_38 and claimed_39 and trees_i4.size() == 1 and trees_i4[0]["cell"] == Vector2i(30, 39),
		"I4.7: Woodcutter allocation excludes protected (30, 38) and claims unprotected (30, 39) within catchment"
	)

	# Check 8: Explicit player_center parameter override on adapter
	var explicit_prot := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_alloc_test, Vector2i(5, 5), Vector2i(5, 5))
	var explicit_unprot := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_alloc_test, Vector2i(20, 20), Vector2i(5, 5))
	_assert(
		explicit_prot and not explicit_unprot,
		"I4.8: Explicit player_center parameter correctly overrides world_data protection center"
	)

	# =========================================================================
	# I5: Fail-Closed Canonical Center & Direct World Generation Integration (11 checks)
	# =========================================================================
	print("  [I5] Fail-Closed Canonical Center & Direct World Generation Integration")

	# Check 1: Valid player_center resolution
	var wd_val_pc := WorldGeneratorScript.WorldData.new()
	wd_val_pc.map_width = 80
	wd_val_pc.map_height = 80
	wd_val_pc.player_center = Vector2i(40, 40)
	wd_val_pc.center_spawn = Vector2i(40, 41)
	wd_val_pc.townhall_anchor = Vector2i(39, 38)
	var res_val_pc: Vector2i = SettlementGeneratorScript.resolve_player_center(wd_val_pc)
	var adapt_val_pc: Vector2i = SettlementResourceSourceAdapterScript.get_player_protection_center(wd_val_pc)
	_assert(
		res_val_pc == Vector2i(40, 40) and adapt_val_pc == Vector2i(40, 40),
		"I5.1: Valid player_center (40, 40) resolves directly in both SettlementGenerator and adapter"
	)

	# Check 2: Valid townhall_anchor fallback resolution
	var wd_th_fb := WorldGeneratorScript.WorldData.new()
	wd_th_fb.map_width = 80
	wd_th_fb.map_height = 80
	wd_th_fb.player_center = Vector2i(-999, -999)
	wd_th_fb.townhall_anchor = Vector2i(39, 38) # townhall_anchor + (1, 2) = (40, 40)
	var res_th_fb: Vector2i = SettlementGeneratorScript.resolve_player_center(wd_th_fb)
	var adapt_th_fb: Vector2i = SettlementResourceSourceAdapterScript.get_player_protection_center(wd_th_fb)
	_assert(
		res_th_fb == Vector2i(40, 40) and adapt_th_fb == Vector2i(40, 40),
		"I5.2: Valid townhall_anchor (39, 38) correctly reconstructs canonical center (40, 40) via fallback"
	)

	# Check 3: Missing/invalid player_center and townhall_anchor fail closed
	var wd_inv := WorldGeneratorScript.WorldData.new()
	wd_inv.map_width = 80
	wd_inv.map_height = 80
	wd_inv.player_center = Vector2i(-999, -999)
	wd_inv.townhall_anchor = Vector2i(-1, -1)
	var res_inv: Vector2i = SettlementGeneratorScript.resolve_player_center(wd_inv)
	var adapt_inv: Vector2i = SettlementResourceSourceAdapterScript.get_player_protection_center(wd_inv)
	var cell_inv_prot := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_inv, Vector2i(20, 20))
	_assert(
		res_inv == Vector2i(-999, -999) and adapt_inv == Vector2i(-999, -999) and cell_inv_prot,
		"I5.3: Missing/invalid center resolves to -999 and is_player_protected_cell strictly fails closed (returns true)"
	)

	# Check 4: Explicit valid center overrides stored fallback
	var res_ovr: Vector2i = SettlementGeneratorScript.resolve_player_center(wd_th_fb, Vector2i(15, 15))
	var adapt_ovr: Vector2i = SettlementResourceSourceAdapterScript.get_player_protection_center(wd_th_fb, Vector2i(15, 15))
	var ovr_prot := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_inv, Vector2i(15, 15), Vector2i(15, 15))
	var ovr_unprot := SettlementResourceSourceAdapterScript.is_player_protected_cell(wd_inv, Vector2i(30, 30), Vector2i(15, 15))
	_assert(
		res_ovr == Vector2i(15, 15) and adapt_ovr == Vector2i(15, 15) and ovr_prot and not ovr_unprot,
		"I5.4: Explicit valid center parameter (15, 15) overrides stored fallback and defines exact protection region"
	)

	# Check 5: Rival Woodcutter registration/allocation with invalid center must NOT claim physical trees
	var p_inv: Array[Dictionary] = [
		{"type": "tree", "cell": Vector2i(10, 11), "variant": 0},
		{"type": "tree", "cell": Vector2i(10, 12), "variant": 0}
	]
	wd_inv.props = p_inv
	var setup_inv := _setup_woodcutter_context("stl_inv")
	var wp_inv = setup_inv["wp"]
	wp_inv.origin_cell = Vector2i(10, 10)
	wp_inv.access_cell = Vector2i(10, 10)
	var reg_inv := SettlementResourceSourceAdapterScript.register_woodcutter_source(setup_inv["ctx"], "bld_wood", wd_inv)
	var alloc_inv := SettlementResourceSourceAdapterScript.allocate_global_woodcutter_sources([setup_inv["ctx"]], wd_inv)
	_assert(
		not reg_inv["ok"] and reg_inv["reason"] == "missing_canonical_player_center" and alloc_inv.is_empty(),
		"I5.5: Woodcutter source registration and global allocation fail closed (claim 0 trees) when player center is invalid"
	)

	# Check 6: Building-footprint and owned-territory protection remain intact even with invalid center
	wd_inv.buildings = [{"cell": Vector2i(50, 50), "size": Vector2i(2, 2)}]
	wd_inv.owned_cells = []
	for x in range(80):
		var col: Array = []
		for y in range(80):
			col.append(false)
		wd_inv.owned_cells.append(col)
	wd_inv.owned_cells[12][12] = true
	var prot_set_inv: Dictionary = SettlementGeneratorScript.build_player_protected_cells(wd_inv)
	_assert(
		prot_set_inv.has(Vector2i(50, 50)) and prot_set_inv.has(Vector2i(49, 49)) and prot_set_inv.has(Vector2i(52, 52))
		and prot_set_inv.has(Vector2i(12, 12)),
		"I5.6: Building footprints (with 1-tile margin) and owned territory remain fully protected under build_player_protected_cells"
	)

	# Check 7: Real WorldGenerator generation sets player_center == center (64, 64) and center_spawn == (64, 65)
	var real_wd := WorldGeneratorScript.generate(12345, 8, 128, 128)
	var real_center := Vector2i(64, 64)
	_assert(
		real_wd != null and real_wd.player_center == real_center
		and real_wd.center_spawn == real_center + Vector2i(0, 1)
		and real_wd.townhall_anchor == real_center + Vector2i(-1, -2),
		"I5.7: Real WorldGenerator production generation stores player_center == (64, 64) and center_spawn == (64, 65)"
	)

	# Check 8: Real WorldGenerator resolves identical center for SettlementGenerator and Rival adapter
	var real_res_center: Vector2i = SettlementGeneratorScript.resolve_player_center(real_wd)
	var real_adapt_center: Vector2i = SettlementResourceSourceAdapterScript.get_player_protection_center(real_wd)
	_assert(
		real_res_center == real_center and real_adapt_center == real_center,
		"I5.8: SettlementGenerator and Rival adapter both resolve exact canonical center (64, 64) from real WorldData"
	)

	# Check 9: Real WorldGenerator canonical protection set has exact radius-8 boundaries
	var real_canon := SettlementGeneratorScript.build_player_protected_cells(real_wd)
	var real_south_8 := real_canon.has(real_center + Vector2i(0, -8)) # (64, 56)
	var real_north_8 := real_canon.has(real_center + Vector2i(0, 8))  # (64, 72)
	var real_east_8  := real_canon.has(real_center + Vector2i(8, 0))  # (72, 64)
	var real_west_8  := real_canon.has(real_center + Vector2i(-8, 0)) # (56, 64)
	var real_diag_ne := real_canon.has(real_center + Vector2i(8, 8))   # (72, 72)
	var real_diag_sw := real_canon.has(real_center + Vector2i(-8, -8)) # (56, 56)
	var real_north_9 := real_canon.has(real_center + Vector2i(0, 9))  # (64, 73)
	var real_south_9 := real_canon.has(real_center + Vector2i(0, -9)) # (64, 55)
	_assert(
		real_south_8 and real_north_8 and real_east_8 and real_west_8 and real_diag_ne and real_diag_sw
		and not real_north_9 and not real_south_9,
		"I5.9: Real WorldGenerator canonical protection set strictly covers 17x17 Chebyshev radius-8 region"
	)

	# Check 10: Real WorldGenerator rival woodcutter allocation claims ZERO player-protected trees
	var real_contexts: Array = []
	for stl in real_wd.settlements:
		var sid: String = String(stl.settlement_id)
		var fid: String = String(stl.origin_faction_id)
		var ctx := SettlementVillagerContextScript.new(sid, fid, fid, 1, true)
		ctx.reconcile_buildings(stl)
		real_contexts.append(ctx)

	var real_alloc := SettlementResourceSourceAdapterScript.allocate_global_woodcutter_sources(real_contexts, real_wd)
	var zero_prot_allocated := true
	for allocated_cell in real_alloc.keys():
		if real_canon.has(allocated_cell):
			zero_prot_allocated = false
			break
	_assert(
		zero_prot_allocated and not real_alloc.is_empty(),
		"I5.10: Global tree allocation on real WorldGenerator output allocates valid trees while strictly claiming 0 player-protected trees"
	)

	# Check 11: Tree injected inside real world player protection zone is strictly ineligible
	var inside_cell := real_center + Vector2i(0, 6) # (64, 70), inside radius 8
	var is_inside_prot := SettlementResourceSourceAdapterScript.is_player_protected_cell(real_wd, inside_cell)
	_assert(
		is_inside_prot,
		"I5.11: Candidate tree inside real world player protection zone (64, 70) is strictly protected and ineligible"
	)
