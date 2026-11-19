extends SceneTree

## =============================================================================
## KINGDOMS UNBOUND — CONTROLLED DEFECT REPAIR PROGRAM
## SESSION 2 TEST SUITE: MILITARY UI & OUTPOST INTERACTION CORRECTION
## Focus: MBL-UI-01 (Outpost Footprint & Reinforcement Dispatch)
##        MBL-UI-02 (ArmyPanel Total Realm Headcount & Upkeep)
## =============================================================================

const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")
const SiegeObjectiveActorScript = preload("res://scripts/combat/siege_objective_actor.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const IsoMathScript = preload("res://scripts/utils/iso_math.gd")

var frame_count: int = 0
var world_instance: Node = null
var failures: int = 0
var checks_passed: int = 0

func _assert(condition: bool, message: String) -> void:
	if condition:
		checks_passed += 1
		print("  [PASS] %s" % message)
	else:
		failures += 1
		printerr("  [FAIL] %s" % message)

func _init() -> void:
	print("\n========================================================")
	print("  STARTING SESSION 2 MILITARY UI TEST SUITE")
	print("========================================================\n")
	world_instance = WorldViewScene.instantiate()
	world_instance.world_seed = 12345
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count < 3:
		# Wait for WorldView and child systems _ready()
		return false

	_run_session2_tests()

	print("\n========================================================")
	print("  SESSION 2 TEST RESULTS SUMMARY")
	print("  Passed Assertions : %d" % checks_passed)
	print("  Failed Assertions : %d" % failures)
	if failures == 0:
		print("  ALL SESSION 2 ASSERTIONS PASSED! (Exit Code 0)")
		print("========================================================\n")
		if is_instance_valid(world_instance):
			world_instance.queue_free()
		quit(0)
	else:
		printerr("  SOME SESSION 2 ASSERTIONS FAILED! (Exit Code 1)")
		print("========================================================\n")
		if is_instance_valid(world_instance):
			world_instance.queue_free()
		quit(1)
	return true

func _run_session2_tests() -> void:
	var pam = world_instance.get("player_army_mgr")
	var fsm = world_instance.get("field_siege_mgr")
	var tmm = world_instance.get("tactical_military_mgr")
	var hud = world_instance.get("hud")

	_assert(pam != null, "Precondition: PlayerArmyManager exists")
	_assert(fsm != null, "Precondition: FieldSiegeManager exists")
	_assert(tmm != null, "Precondition: TacticalMilitaryManager exists")
	_assert(hud != null, "Precondition: HUD exists")

	_test_group_a1_outpost_footprint(fsm, hud)
	_test_group_a2_reinforcement_dispatch(pam, fsm, hud)
	_test_group_b_armypanel_total_headcount(pam, hud)

func _send_click(cell: Vector2i, button: int = MOUSE_BUTTON_LEFT, shift: bool = false) -> void:
	if button == MOUSE_BUTTON_LEFT:
		var mb_down := InputEventMouseButton.new()
		mb_down.button_index = MOUSE_BUTTON_LEFT
		mb_down.pressed = true
		mb_down.shift_pressed = shift
		mb_down.set_meta("target_cell", cell)
		world_instance._unhandled_input(mb_down)

		var mb_up := InputEventMouseButton.new()
		mb_up.button_index = MOUSE_BUTTON_LEFT
		mb_up.pressed = false
		mb_up.shift_pressed = shift
		mb_up.set_meta("target_cell", cell)
		world_instance._unhandled_input(mb_up)
	else:
		var mb := InputEventMouseButton.new()
		mb.button_index = button
		mb.pressed = true
		mb.shift_pressed = shift
		mb.set_meta("target_cell", cell)
		world_instance._unhandled_input(mb)

# =============================================================================
# TEST GROUP A1: MBL-UI-01 Outpost 2x2 Footprint Hit-Testing
# =============================================================================
func _test_group_a1_outpost_footprint(fsm: Object, hud: Object) -> void:
	print("\n--- Running Test Group A1: SiegeObjectiveActor 2x2 Click Footprint ---")
	
	# Spawn a test siege objective at (20, 20) with 2x2 footprint
	var obj := SiegeObjectiveActorScript.new()
	obj.objective_id = "test_outpost_footprint_2x2"
	obj.objective_name = "Tiền Đồn Thử Nghiệm 2x2"
	obj.owning_faction_id = "rival_military"
	obj.current_cell = Vector2i(20, 20)
	obj.health = 250.0
	obj.max_health = 250.0
	obj.is_alive = true
	fsm.objectives[obj.objective_id] = obj
	world_instance.add_child(obj)

	var origin: Vector2i = obj.current_cell

	# AUD-3B-01: Explicitly mark outpost footprint and adjacent test cells EXPLORED in Fog of War
	var fow = world_instance.get("fog_of_war")
	if fow != null:
		for dx in range(-1, 3):
			for dy in range(-1, 3):
				fow.set_state(origin + Vector2i(dx, dy), FogOfWar.State.EXPLORED)

	# 1. Verify all 4 cells of the 2x2 footprint select the objective
	# Cell 0: Origin (20, 20)
	world_instance.clear_building_selection()
	_send_click(origin)
	_assert(world_instance.selected_building_id == obj.objective_id,
		"TC-A1.1: Click at origin (20, 20) selects outpost")
	_assert(hud.building_inspect_panel != null and hud.building_inspect_panel.visible,
		"TC-A1.2: HUD building inspector opened for origin click")

	# Cell 1: (21, 20) = origin + (1, 0)
	world_instance.clear_building_selection()
	_send_click(origin + Vector2i(1, 0))
	_assert(world_instance.selected_building_id == obj.objective_id,
		"TC-A1.3: Click at origin + (1, 0) (21, 20) selects outpost")

	# Cell 2: (20, 21) = origin + (0, 1)
	world_instance.clear_building_selection()
	_send_click(origin + Vector2i(0, 1))
	_assert(world_instance.selected_building_id == obj.objective_id,
		"TC-A1.4: Click at origin + (0, 1) (20, 21) selects outpost")

	# Cell 3: (21, 21) = origin + (1, 1)
	world_instance.clear_building_selection()
	_send_click(origin + Vector2i(1, 1))
	_assert(world_instance.selected_building_id == obj.objective_id,
		"TC-A1.5: Click at origin + (1, 1) (21, 21) selects outpost")

	# 2. Verify cells immediately outside footprint DO NOT select the objective
	# North: (20, 19)
	world_instance.clear_building_selection()
	_send_click(origin + Vector2i(0, -1))
	_assert(world_instance.selected_building_id != obj.objective_id,
		"TC-A1.6: Click North (20, 19) does NOT select outpost")

	# West: (19, 20)
	world_instance.clear_building_selection()
	_send_click(origin + Vector2i(-1, 0))
	_assert(world_instance.selected_building_id != obj.objective_id,
		"TC-A1.7: Click West (19, 20) does NOT select outpost")

	# East: (22, 20) [half-open boundary: origin.x + size.x = 22]
	world_instance.clear_building_selection()
	_send_click(origin + Vector2i(2, 0))
	_assert(world_instance.selected_building_id != obj.objective_id,
		"TC-A1.8: Click East (22, 20) does NOT select outpost (half-open boundary)")

	# South: (20, 22) [half-open boundary: origin.y + size.y = 22]
	world_instance.clear_building_selection()
	_send_click(origin + Vector2i(0, 2))
	_assert(world_instance.selected_building_id != obj.objective_id,
		"TC-A1.9: Click South (20, 22) does NOT select outpost (half-open boundary)")

	# Southeast corner outside: (22, 22)
	world_instance.clear_building_selection()
	_send_click(origin + Vector2i(2, 2))
	_assert(world_instance.selected_building_id != obj.objective_id,
		"TC-A1.10: Click Southeast (22, 22) does NOT select outpost")

	# 3. Input priority & precedence: citizen on outpost cell takes Priority 2 over outpost Priority 2.5
	var cit_list: Array = world_instance.get("citizen_list")
	if not cit_list.is_empty():
		var test_cit = cit_list[0]
		var orig_cit_cell: Vector2i = test_cit.get("current_cell")
		# Temporarily position citizen on one of the outpost cells: (21, 20)
		test_cit.current_cell = origin + Vector2i(1, 0)
		world_instance.clear_building_selection()

		_send_click(origin + Vector2i(1, 0))
		_assert(hud.citizen_panel != null and hud.citizen_panel.visible,
			"TC-A1.11: Priority 2: Citizen at (21, 20) takes precedence over outpost Priority 2.5")
		_assert(world_instance.selected_building_id != obj.objective_id,
			"TC-A1.12: Outpost was NOT selected when clicking citizen on outpost cell")

		# Restore citizen position
		test_cit.current_cell = orig_cit_cell
		if hud.citizen_panel != null:
			hud.citizen_panel.visible = false

	world_instance.clear_building_selection()

# =============================================================================
# TEST GROUP A2: MBL-UI-01 Reinforcement Dispatch via HUD
# =============================================================================
func _test_group_a2_reinforcement_dispatch(pam: Object, fsm: Object, hud: Object) -> void:
	print("\n--- Running Test Group A2: Reinforcement Dispatch via HUD Button ---")

	# Register a player-controlled outpost in PlayerArmyManager
	var outpost_id := "outpost_player_ui_test"
	pam.register_outpost_for_testing(outpost_id, 3, Vector2i(45, 45), "player")
	var obj := SiegeObjectiveActorScript.new()
	obj.objective_id = outpost_id
	obj.objective_name = "Tiền Đồn Của Ta"
	obj.owning_faction_id = "player"
	obj.current_cell = Vector2i(45, 45)
	obj.health = 250.0
	obj.max_health = 250.0
	obj.is_alive = true
	fsm.objectives[outpost_id] = obj
	world_instance.add_child(obj)

	# Set central reserve soldiers
	pam.soldier_count = 6
	pam.active_reinforcements.clear()
	var initial_total: int = pam.get_total_soldier_count()
	_assert(initial_total == 6, "TC-A2.1: Initial total realm headcount is 6")
	_assert(pam.get_garrison_count(outpost_id) == 0, "TC-A2.2: Initial garrison is 0")
	_assert(pam.get_in_transit_count(outpost_id) == 0, "TC-A2.3: Initial in-transit is 0")

	# Inspect outpost in HUD
	var outpost_data := {
		"id": outpost_id,
		"type": "outpost",
		"name": obj.objective_name,
		"cell": obj.current_cell,
		"size": Vector2i(2, 2),
		"state": "active",
		"health": 250,
		"max_health": 250,
		"owner": "player",
		"is_outpost": true,
		"is_under_siege": false
	}
	world_instance.select_building(outpost_data)

	_assert(hud.reinforce_btn != null and not hud.reinforce_btn.disabled,
		"TC-A2.4: Reinforce button is enabled when reserve > 0 and garrison has capacity")

	# Click Reinforce Button via HUD handler
	hud._on_reinforce_outpost_pressed()

	# Verify dispatch contract:
	# 1. Central reserve decrements immediately
	_assert(pam.soldier_count == 5,
		"TC-A2.5: Central reserve decremented atomically to 5 (was 6)")
	# 2. Outpost garrison DOES NOT increase immediately
	_assert(pam.get_garrison_count(outpost_id) == 0,
		"TC-A2.6: Outpost garrison did NOT increase immediately (stays at 0)")
	# 3. Active in-transit record created
	_assert(pam.get_in_transit_count(outpost_id) == 1,
		"TC-A2.7: In-transit reinforcement count is exactly 1")
	# 4. Total realm headcount strictly conserved
	_assert(pam.get_total_soldier_count() == 6,
		"TC-A2.8: Total realm headcount strictly conserved at 6 during transit")
	# 5. HUD event banner indicates dispatch success with travel hours
	_assert(hud.event_title != null and hud.event_title.text == "Điều Binh Tiếp Viện",
		"TC-A2.9: HUD displays 'Điều Binh Tiếp Viện' success banner")
	# 6. HUD garrison transit label is visible
	_assert(hud.garrison_transit_label != null and hud.garrison_transit_label.visible,
		"TC-A2.10: HUD garrison transit label is visible with in-transit info")

	# Advance travel time until arrival
	var reinf = pam.active_reinforcements[0]
	var travel_h: float = float(reinf.get("travel_hours", 1.0))
	pam.advance_reinforcements(travel_h + 0.1)

	# Verify arrival contract:
	_assert(pam.get_garrison_count(outpost_id) == 1,
		"TC-A2.11: Garrison increased to 1 upon arrival")
	_assert(pam.get_in_transit_count(outpost_id) == 0,
		"TC-A2.12: In-transit record cleared upon arrival")
	_assert(pam.get_total_soldier_count() == 6,
		"TC-A2.13: Total realm headcount strictly conserved at 6 post-arrival")
	_assert(hud.garrison_transit_label != null and not hud.garrison_transit_label.visible,
		"TC-A2.14: HUD garrison transit label hidden after arrival")

	# Edge Case: Dispatch failure on invalid outpost
	hud.inspected_building_id = "non_existent_outpost_999"
	hud._on_reinforce_outpost_pressed()
	_assert(hud.event_title != null and hud.event_title.text == "Điều Binh Thất Bại",
		"TC-A2.15: Dispatch failure on invalid outpost displays failure banner")
	_assert(pam.soldier_count == 5,
		"TC-A2.16: Central reserve preserved on failed dispatch")

	# Edge Case: Dispatch failure when reserve is 0
	pam.soldier_count = 0
	hud.inspected_building_id = outpost_id
	hud.refresh_building_inspector()
	_assert(hud.reinforce_btn.disabled,
		"TC-A2.17: Reinforce button disabled when central reserve is 0")

	hud._on_reinforce_outpost_pressed()
	_assert(hud.event_title != null and hud.event_title.text == "Điều Binh Thất Bại",
		"TC-A2.18: Calling dispatch with 0 reserve displays failure banner")
	_assert(pam.soldier_count == 0,
		"TC-A2.19: Reserve remains 0 on rejected dispatch")
	_assert(pam.get_garrison_count(outpost_id) == 1,
		"TC-A2.20: Garrison untouched on rejected dispatch")

	world_instance.clear_building_selection()

# =============================================================================
# TEST GROUP B: MBL-UI-02 ArmyPanel Total Headcount & Upkeep
# =============================================================================
func _test_group_b_armypanel_total_headcount(pam: Object, hud: Object) -> void:
	print("\n--- Running Test Group B: ArmyPanel Total Headcount & Upkeep across 7 States ---")

	# Clean slate setup
	pam.soldier_count = 5
	pam.garrisons.clear()
	pam.active_reinforcements.clear()

	var op_a := "outpost_realm_a"
	var op_b := "outpost_realm_b"
	pam.register_outpost_for_testing(op_a, 4, Vector2i(10, 10), "player")
	pam.register_outpost_for_testing(op_b, 4, Vector2i(30, 30), "player")

	var cap: int = pam.get_army_capacity()

	# Open ArmyPanel in HUD
	hud.army_panel.visible = true

	# -------------------------------------------------------------------------
	# State 1: All soldiers in central reserve
	# -------------------------------------------------------------------------
	pam.soldier_count = 5
	hud._refresh_army_panel()
	var total_s1: int = pam.get_total_soldier_count()
	_assert(total_s1 == 5, "TC-B.1.1: State 1 total headcount == 5 (5 reserve, 0 gar, 0 transit)")
	_assert(hud.army_count_label.text.find("5 / %d" % cap) != -1,
		"TC-B.1.2: ArmyPanel displays total headcount '5 / %d'" % cap)
	_assert(hud.upkeep_label.text.find("%d Lương thực" % (5 * EconomyConfigScript.ARMY_DAILY_FOOD_UPKEEP)) != -1,
		"TC-B.1.3: ArmyPanel displays upkeep for 5 soldiers")

	# -------------------------------------------------------------------------
	# State 2: Soldiers split between central reserve and outpost garrisons
	# -------------------------------------------------------------------------
	var st_res = pam.station_soldier(op_a, 2)
	_assert(bool(st_res.get("success", false)), "TC-B.2.1: Stationed 2 soldiers at outpost A")
	_assert(pam.soldier_count == 3, "TC-B.2.2: Central reserve reduced to 3")
	_assert(pam.get_garrison_count(op_a) == 2, "TC-B.2.3: Outpost A garrison is 2")

	hud._refresh_army_panel()
	var total_s2: int = pam.get_total_soldier_count()
	_assert(total_s2 == 5, "TC-B.2.4: State 2 total headcount strictly conserved at 5 (3 reserve + 2 gar)")
	_assert(hud.army_count_label.text.find("5 / %d" % cap) != -1,
		"TC-B.2.5: ArmyPanel displays total headcount '5 / %d' (NOT central reserve 3!)" % cap)
	_assert(hud.upkeep_label.text.find("%d Lương thực" % (5 * EconomyConfigScript.ARMY_DAILY_FOOD_UPKEEP)) != -1,
		"TC-B.2.6: ArmyPanel displays upkeep based on total headcount (5), NOT reserve (3)")

	# -------------------------------------------------------------------------
	# State 3: Soldiers travelling as reinforcements
	# -------------------------------------------------------------------------
	var disp_res = pam.dispatch_reinforcements(op_b, 1, 2.0)
	_assert(bool(disp_res.get("success", false)), "TC-B.3.1: Dispatched 1 reinforcement to outpost B")
	_assert(pam.soldier_count == 2, "TC-B.3.2: Central reserve reduced to 2")
	_assert(pam.get_in_transit_count(op_b) == 1, "TC-B.3.3: In-transit count to B is 1")
	_assert(pam.get_garrison_count(op_b) == 0, "TC-B.3.4: Outpost B garrison is still 0")

	hud._refresh_army_panel()
	var total_s3: int = pam.get_total_soldier_count()
	_assert(total_s3 == 5, "TC-B.3.5: State 3 total headcount strictly conserved at 5 (2 res + 2 gar + 1 transit)")
	_assert(hud.army_count_label.text.find("5 / %d" % cap) != -1,
		"TC-B.3.6: ArmyPanel displays total headcount '5 / %d' during transit (NOT reserve 2!)" % cap)
	_assert(hud.upkeep_label.text.find("%d Lương thực" % (5 * EconomyConfigScript.ARMY_DAILY_FOOD_UPKEEP)) != -1,
		"TC-B.3.7: ArmyPanel displays upkeep based on total headcount (5)")

	# -------------------------------------------------------------------------
	# State 4: Reinforcement arrival
	# -------------------------------------------------------------------------
	pam.advance_reinforcements(2.5)
	_assert(pam.get_in_transit_count(op_b) == 0, "TC-B.4.1: In-transit record cleared on arrival")
	_assert(pam.get_garrison_count(op_b) == 1, "TC-B.4.2: Outpost B garrison is now 1")
	_assert(pam.soldier_count == 2, "TC-B.4.3: Central reserve unchanged at 2")

	hud._refresh_army_panel()
	var total_s4: int = pam.get_total_soldier_count()
	_assert(total_s4 == 5, "TC-B.4.4: State 4 total headcount strictly conserved at 5 (2 res + 3 gar)")
	_assert(hud.army_count_label.text.find("5 / %d" % cap) != -1,
		"TC-B.4.5: ArmyPanel displays total headcount '5 / %d' post-arrival" % cap)
	_assert(hud.upkeep_label.text.find("%d Lương thực" % (5 * EconomyConfigScript.ARMY_DAILY_FOOD_UPKEEP)) != -1,
		"TC-B.4.6: ArmyPanel upkeep conserved post-arrival")

	# -------------------------------------------------------------------------
	# State 5: Reinforcement cancellation
	# -------------------------------------------------------------------------
	var disp_res2 = pam.dispatch_reinforcements(op_b, 1, 3.0)
	_assert(bool(disp_res2.get("success", false)), "TC-B.5.1: Dispatched second reinforcement to B")
	_assert(pam.soldier_count == 1, "TC-B.5.2: Reserve decremented to 1")

	var cancel_res: int = pam.cancel_outpost_reinforcements(op_b)
	_assert(cancel_res > 0, "TC-B.5.3: Cancelled reinforcement to B (returned %d refunded soldiers)" % cancel_res)
	_assert(pam.soldier_count == 2, "TC-B.5.4: Soldier refunded to central reserve (now 2)")
	_assert(pam.get_in_transit_count(op_b) == 0, "TC-B.5.5: In-transit count to B is 0")

	hud._refresh_army_panel()
	var total_s5: int = pam.get_total_soldier_count()
	_assert(total_s5 == 5, "TC-B.5.6: State 5 total headcount conserved at 5 after cancellation")
	_assert(hud.army_count_label.text.find("5 / %d" % cap) != -1,
		"TC-B.5.7: ArmyPanel displays '5 / %d' after cancellation" % cap)

	# -------------------------------------------------------------------------
	# State 6: Soldier recall
	# -------------------------------------------------------------------------
	var recall_res = pam.recall_soldier(op_a, 1)
	_assert(bool(recall_res.get("success", false)), "TC-B.6.1: Recalled 1 soldier from outpost A")
	_assert(pam.get_garrison_count(op_a) == 1, "TC-B.6.2: Outpost A garrison reduced to 1")
	_assert(pam.soldier_count == 3, "TC-B.6.3: Central reserve increased to 3")

	hud._refresh_army_panel()
	var total_s6: int = pam.get_total_soldier_count()
	_assert(total_s6 == 5, "TC-B.6.4: State 6 total headcount conserved at 5 after recall")
	_assert(hud.army_count_label.text.find("5 / %d" % cap) != -1,
		"TC-B.6.5: ArmyPanel displays '5 / %d' after recall" % cap)

	# -------------------------------------------------------------------------
	# State 7: Outpost evacuation after destruction (Session 1 behavior)
	# -------------------------------------------------------------------------
	var evict_res: Array = pam.evict_outpost_garrison(op_a, true)
	_assert(not evict_res.is_empty(), "TC-B.7.1: Evicted garrison from outpost A (%d soldiers returned to central)" % evict_res.size())
	_assert(pam.get_garrison_count(op_a) == 0, "TC-B.7.2: Outpost A garrison is 0")
	_assert(pam.soldier_count == 4, "TC-B.7.3: Central reserve increased to 4 (4 reserve + 1 gar at B)")

	hud._refresh_army_panel()
	var total_s7: int = pam.get_total_soldier_count()
	_assert(total_s7 == 5, "TC-B.7.4: State 7 total headcount strictly conserved at 5 after eviction")
	_assert(hud.army_count_label.text.find("5 / %d" % cap) != -1,
		"TC-B.7.5: ArmyPanel displays '5 / %d' after eviction" % cap)
	_assert(hud.upkeep_label.text.find("%d Lương thực" % (5 * EconomyConfigScript.ARMY_DAILY_FOOD_UPKEEP)) != -1,
		"TC-B.7.6: ArmyPanel upkeep strictly matches total headcount (5)")

	# Verify simulation food upkeep matches ArmyPanel
	var upkeep_dict = pam.process_daily_upkeep(10)
	var expected_upkeep_food: int = 5 * EconomyConfigScript.ARMY_DAILY_FOOD_UPKEEP
	_assert(int(upkeep_dict.get("cost", 0)) == expected_upkeep_food,
		"TC-B.7.7: Simulation process_daily_upkeep cost (%d) matches ArmyPanel upkeep (%d)" %
		[int(upkeep_dict.get("cost", 0)), expected_upkeep_food])
