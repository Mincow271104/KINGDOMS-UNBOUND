extends SceneTree

const WorldViewScene = preload("res://scenes/world/world_view.tscn")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const FogOfWarScript = preload("res://scripts/world/fog_of_war.gd")
const SettlementDataScript = preload("res://scripts/world/settlement_data.gd")
const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementVillagerContextScript = preload("res://scripts/world/settlement_villager_context.gd")
const SettlementSimulationManagerScript = preload("res://scripts/world/settlement_simulation_manager.gd")
const RivalPresentationControllerScript = preload("res://scripts/world/rival_presentation_controller.gd")
const RivalInspectionQueryScript = preload("res://scripts/world/rival_inspection_query.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")

var _passed: int = 0
var _failed: int = 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] %s" % msg)
	else:
		_failed += 1
		printerr("  [FAIL] %s" % msg)

func _make_test_world_and_manager() -> Dictionary:
	var wd = WorldGeneratorScript.generate(12345, WorldGeneratorScript.LATEST_GENERATOR_VERSION, 128, 128)
	var mgr := SettlementSimulationManagerScript.new()
	mgr.register_settlements_from_world_data(wd)
	mgr.seed_initial_populations()
	var fog := FogOfWarScript.new(128, 128)
	return {"world_data": wd, "mgr": mgr, "fog": fog}

func _run_categories_a_to_d() -> void:
	print("\n[Categories A-D] Fog of War, Data Accuracy, Read-Only Isolation & Selection")
	var env := _make_test_world_and_manager()
	var wd = env["world_data"]
	var mgr: Node = env["mgr"]
	var fog: RefCounted = env["fog"]
	var stl = wd.settlements[2] # stl_neutral_tribe_1 (full, 7 residents)
	var sid: String = stl.settlement_id
	var ctx = mgr.get_context(sid)
	var query := RivalInspectionQueryScript.new(mgr, wd, fog, null, false)

	# --- Category A: Fog of War ---
	var vm_unexp: Dictionary = query.build_settlement_view_model(sid)
	_assert(not bool(vm_unexp.get("allowed", true)) and vm_unexp.get("fog_state") == "unexplored", "A1: UNEXPLORED blocks settlement inspection")

	var first_v = ctx.get_all_villagers()[0]
	var v_unexp: Dictionary = query.build_villager_view_model(sid, first_v.villager_id)
	_assert(not bool(v_unexp.get("allowed", true)), "A2: UNEXPLORED blocks villager inspection")

	# Explore ONLY the first building footprint, then degrade to EXPLORED (not VISIBLE)
	var b0: Dictionary = stl.buildings[0]
	var b0_cell: Vector2i = b0.get("cell", stl.anchor_cell)
	fog.set_state(b0_cell, FogOfWarScript.State.EXPLORED)
	var vm_exp: Dictionary = query.build_settlement_view_model(sid)
	_assert(bool(vm_exp.get("allowed", false)) and vm_exp.get("fog_state") == "explored" and not bool(vm_exp.get("is_live_visible", true)), "A3: EXPLORED returns static settlement view only")
	_assert(int(vm_exp.get("explored_building_count", 0)) == 1 and stl.buildings.size() > 1, "A4: Hidden buildings are not counted/revealed in EXPLORED static results (1 of %d)" % stl.buildings.size())
	_assert(
		not vm_exp.has("living_count")
		and not vm_exp.has("gold")
		and not vm_exp.has("resources")
		and not vm_exp.has("visible_residents")
		and not vm_exp.has("role_counts"),
		"A5: EXPLORED never exposes live stock, Gold, population, or resident roster"
	)

	# Make ONE building cell VISIBLE -> approved full overview
	fog.set_state(b0_cell, FogOfWarScript.State.VISIBLE)
	var vm_vis: Dictionary = query.build_settlement_view_model(sid)
	_assert(bool(vm_vis.get("allowed", false)) and vm_vis.get("fog_state") == "visible" and bool(vm_vis.get("is_live_visible", false)), "A6: One visible settlement building footprint enables full overview")

	# Villager at a non-visible cell is STILL blocked even when settlement overview is visible
	var v_nonvis: Dictionary = query.build_villager_view_model(sid, first_v.villager_id)
	_assert(not bool(v_nonvis.get("allowed", true)), "A7: Villager still requires individual VISIBLE cell")

	# Make first_v cell VISIBLE (and ensure outdoor)
	first_v.rest_phase = SettlementVillagerDataScript.REST_NONE
	fog.set_state(first_v.cell, FogOfWarScript.State.VISIBLE)
	var v_vis: Dictionary = query.build_villager_view_model(sid, first_v.villager_id)
	_assert(bool(v_vis.get("allowed", false)) and v_vis.get("villager_id") == first_v.villager_id, "A7b: Individually VISIBLE outdoor villager is inspectable")

	# --- Category B: Data Accuracy ---
	# Add a removed resident and raw_meat to verify exclusion & separation
	var rem_v = ctx.create_and_add_villager("removed_test", SettlementVillagerDataScript.ROLE_IDLE, stl.anchor_cell)
	rem_v.life_state = SettlementVillagerDataScript.LIFE_REMOVED
	ctx.economy.deposit_hauled_resource(EconomyConfigScript.RES_RAW_MEAT, 15, "test_hunt", "test", 1)
	var vm_b: Dictionary = query.build_settlement_view_model(sid)
	_assert(int(vm_b.get("living_count", 0)) == 7 and int(vm_b.get("total_count", 0)) == 7, "B1/B2: Physical population derives from canonical residents and excludes REMOVED")
	var rc: Dictionary = vm_b.get("role_counts", {})
	_assert(int(rc.get("hunter", 0)) == 1 and int(rc.get("farmer", 0)) == 2 and int(rc.get("woodcutter", 0)) == 2 and int(rc.get("hauler", 0)) == 1 and int(rc.get("idle", 0)) == 1, "B3: Role breakdown matches canonical residents")
	_assert(int(vm_b.get("housing_capacity", 0)) == ctx.get_housing_capacity() and int(vm_b.get("housing_available", 0)) == ctx.get_available_housing_slots(), "B4/B5: Housing capacity & available slots match canonical context")
	var found_food: int = -1
	var found_meat: int = -1
	for r_item in vm_b.get("resources", []):
		if r_item["id"] == EconomyConfigScript.RES_FOOD:
			found_food = int(r_item["amount"])
		elif r_item["id"] == EconomyConfigScript.RES_RAW_MEAT:
			found_meat = int(r_item["amount"])
	_assert(found_food == ctx.economy.get_resource(EconomyConfigScript.RES_FOOD) and found_meat == 15 and found_food != found_meat, "B7/B8: Economy stocks match SettlementEconomy and raw_meat remains separate from food")
	_assert(int(vm_b.get("gold", -1)) == ctx.economy.get_gold(), "B9: Gold matches local economy")
	var first_b: Dictionary = vm_b.get("buildings", [])[0]
	_assert(not first_b.has("health") and not first_b.has("max_health") and not first_b.has("upgrade_level"), "B10: Absent building fields are not fabricated")

	# --- Category C: Read-Only Isolation & Deep Copy ---
	var food_before: int = ctx.economy.get_resource(EconomyConfigScript.RES_FOOD)
	var gold_before: int = ctx.economy.get_gold()
	var ledger_before: int = ctx.economy.get_ledger_snapshot().size()
	var role_before: String = first_v.role
	var hseq_before: int = ctx.sim_state.settled_hour_seq
	# Mutate returned view-model dicts
	vm_b["role_counts"]["hunter"] = 999
	vm_b["resources"][0]["amount"] = 99999
	var vm_after: Dictionary = query.build_settlement_view_model(sid)
	_assert(int(vm_after["role_counts"]["hunter"]) == 1 and ctx.economy.get_resource(EconomyConfigScript.RES_FOOD) == food_before and ctx.economy.get_gold() == gold_before and ctx.economy.get_ledger_snapshot().size() == ledger_before and first_v.role == role_before and ctx.sim_state.settled_hour_seq == hseq_before, "C1/C2: View-models are detached deep copies and querying never mutates canonical state")

	# --- Category D: Selection & Identity ---
	var unexp_stl = wd.settlements[0]
	var unexp_cell: Vector2i = unexp_stl.buildings[0]["cell"]
	_assert(query.find_rival_target_at_cell(unexp_cell).is_empty(), "D3: Unexplored Rival building cannot be selected")

	fog.set_state(unexp_cell, FogOfWarScript.State.EXPLORED)
	var hit_exp: Dictionary = query.find_rival_target_at_cell(unexp_cell)
	_assert(hit_exp.get("kind") == "settlement" and hit_exp.get("settlement_id") == unexp_stl.settlement_id, "D2: Explored Rival building selects settlement for static inspection")

	# Mid/Far LOD selection without Actor when individually VISIBLE
	var hit_mid_v: Dictionary = query.find_rival_target_at_cell(first_v.cell)
	_assert(hit_mid_v.get("kind") == "villager" and hit_mid_v.get("settlement_id") == sid and hit_mid_v.get("villager_id") == first_v.villager_id, "D5: Mid/Far visible villager can be selected without an active Actor")

	# Deterministic tie-breaker for overlapping villagers at same cell
	var v_other = ctx.get_all_villagers()[1]
	v_other.rest_phase = SettlementVillagerDataScript.REST_NONE
	v_other.cell = first_v.cell
	var hit_tie: Dictionary = query.find_rival_target_at_cell(first_v.cell)
	var expected_first_id: String = first_v.villager_id if first_v.villager_id < v_other.villager_id else v_other.villager_id
	_assert(hit_tie.get("kind") == "villager" and hit_tie.get("villager_id") == expected_first_id, "D10: Overlapping villager candidates resolve deterministically")

func _run_category_e_ui_and_lifecycle() -> void:
	print("\n[Category E] Live WorldView + HUD Integration, Fog Loss & Escape Lifecycle")
	var wv: Node = WorldViewScene.instantiate()
	wv.set("world_seed", 12345)
	root.add_child(wv)
	await process_frame

	var hud: Node = wv.get("hud")
	var sim_mgr: Node = wv.get("settlement_simulation_manager")
	var fog: RefCounted = wv.get("fog_of_war")
	var pres_ctrl: Node = wv.get("rival_presentation_controller")
	var sids: Array[String] = sim_mgr.get_registered_settlement_ids()
	var sid0: String = sids[0]
	var ctx0 = sim_mgr.get_context(sid0)
	var stl0 = null
	for s in wv.world_data.settlements:
		if s.settlement_id == sid0:
			stl0 = s
			break

	# Reveal settlement building cell as VISIBLE and click it via _handle_left_click
	var b0_cell: Vector2i = stl0.buildings[0]["cell"]
	fog.set_state(b0_cell, FogOfWarScript.State.VISIBLE)
	wv.call("_handle_left_click", b0_cell)
	var r_stl_panel: Control = hud.get("rival_settlement_panel")
	var r_vil_panel: Control = hud.get("rival_villager_panel")
	_assert(r_stl_panel != null and r_stl_panel.visible and hud.get("inspected_rival_settlement_id") == sid0, "E1/D1: Clicking visible Rival building opens RivalSettlementInspectPanel")
	_assert(r_stl_panel.mouse_filter == Control.MOUSE_FILTER_STOP and r_vil_panel.mouse_filter == Control.MOUSE_FILTER_STOP, "E6: Both Rival inspector panels use MOUSE_FILTER_STOP")

	# Drill-down to visible villager from Settlement Inspector
	var v0 = ctx0.get_all_villagers()[0]
	v0.rest_phase = SettlementVillagerDataScript.REST_NONE
	fog.set_state(v0.cell, FogOfWarScript.State.VISIBLE)
	hud.call("show_rival_villager_inspector", sid0, v0.villager_id, true)
	_assert(r_vil_panel.visible and not r_stl_panel.visible and hud.get("inspected_rival_villager_id") == v0.villager_id, "E2/E3: Settlement-to-Villager drill-down opens RivalVillagerInspectPanel")

	# Back button returns to Settlement Inspector
	hud.call("_on_back_to_rival_settlement_pressed")
	_assert(r_stl_panel.visible and not r_vil_panel.visible, "E4: Back button returns to RivalSettlementInspectPanel")

	# Fog loss on open settlement drops to EXPLORED static view
	for b in stl0.buildings:
		for ox in range(int(b.get("size", Vector2i.ONE).x)):
			for oy in range(int(b.get("size", Vector2i.ONE).y)):
				var c: Vector2i = b["cell"] + Vector2i(ox, oy)
				if fog.is_visible(c):
					fog.set_state(c, FogOfWarScript.State.EXPLORED)
	if fog.is_visible(stl0.anchor_cell):
		fog.set_state(stl0.anchor_cell, FogOfWarScript.State.EXPLORED)
	hud.call("refresh_rival_inspector")
	var notice_lbl: Label = hud.get("rival_settlement_notice_label")
	_assert(r_stl_panel.visible and notice_lbl != null and notice_lbl.visible, "A8a: Visibility loss immediately restricts open Settlement Inspector to EXPLORED static view")

	# Villager visibility loss closes Villager Inspector immediately on refresh
	fog.set_state(v0.cell, FogOfWarScript.State.VISIBLE)
	hud.call("show_rival_villager_inspector", sid0, v0.villager_id, false)
	_assert(r_vil_panel.visible, "E2b: Open Villager Inspector visible while villager cell is VISIBLE")
	fog.set_state(v0.cell, FogOfWarScript.State.EXPLORED)
	hud.call("refresh_rival_inspector")
	_assert(not r_vil_panel.visible and hud.get("inspected_rival_villager_id") == "", "A8b: Villager visibility loss immediately closes Villager Inspector")

	# Pool release & Actor rebind safety while villager remains VISIBLE
	fog.set_state(v0.cell, FogOfWarScript.State.VISIBLE)
	wv.camera.focus_on_cell(v0.cell)
	wv.camera.force_update_scroll()
	await process_frame
	pres_ctrl.update_presentation(0.016, 1.0)
	hud.call("show_rival_villager_inspector", sid0, v0.villager_id, false)
	pres_ctrl.get_actor_pool().release(sid0, v0.villager_id)
	hud.call("refresh_rival_inspector")
	_assert(r_vil_panel.visible and hud.get("inspected_rival_villager_id") == v0.villager_id, "D6/D7: Pool release does not invalidate stable (sid, vid) villager selection")

	# Mutual exclusion with Player Building & Citizen Inspectors
	var player_bld: Dictionary = wv.world_data.buildings[0]
	wv.call("_handle_left_click", player_bld["cell"])
	_assert(not r_vil_panel.visible and not r_stl_panel.visible and hud.get("building_inspect_panel").visible, "E5/E7: Selecting Player building closes Rival inspectors and opens Player BuildingInspectPanel")

	# Escape closes Rival panels cleanly without opening Pause Menu
	hud.call("show_rival_villager_inspector", sid0, v0.villager_id, true)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	hud.call("_unhandled_input", esc)
	_assert(not r_vil_panel.visible and r_stl_panel.visible, "E8a: Escape on drilled-down Villager Inspector returns to Settlement Inspector")
	hud.call("_unhandled_input", esc)
	_assert(not r_stl_panel.visible and not hud.get("pause_menu_dialog").visible, "E8b: Second Escape closes Settlement Inspector without triggering Pause Menu")

	# Villager removal & Settlement removal clear selection
	hud.call("show_rival_villager_inspector", sid0, v0.villager_id, false)
	v0.life_state = SettlementVillagerDataScript.LIFE_REMOVED
	hud.call("refresh_rival_inspector")
	_assert(not r_vil_panel.visible and hud.get("inspected_rival_villager_id") == "", "D8: Removed resident clears Villager Inspector selection")

	fog.set_state(b0_cell, FogOfWarScript.State.VISIBLE)
	hud.call("show_rival_settlement_inspector", sid0)
	sim_mgr.unregister_context(sid0)
	wv.world_data.settlements = wv.world_data.settlements.filter(func(s): return s.settlement_id != sid0)
	hud.call("refresh_rival_inspector")
	_assert(not r_stl_panel.visible and hud.get("inspected_rival_settlement_id") == "", "D9: Removed settlement clears Settlement Inspector selection")

	wv.queue_free()
	await process_frame

func _init() -> void:
	print("====================================================================")
	print("  TEST SUITE: Phase 7 Rival Settlement & Villager HUD Inspection")
	print("====================================================================")
	call_deferred("_run_all")

func _run_all() -> void:
	_run_categories_a_to_d()
	await _run_category_e_ui_and_lifecycle()

	print("\n--------------------------------------------------------------------")
	print("  Results: %d passed, %d failed" % [_passed, _failed])
	print("====================================================================")
	if _failed == 0:
		print("ALL %d ASSERTIONS PASSED! (Exit Code 0)" % _passed)
		quit(0)
	else:
		print("FAILED WITH %d FAILURES! (Exit Code 1)" % _failed)
		quit(1)
