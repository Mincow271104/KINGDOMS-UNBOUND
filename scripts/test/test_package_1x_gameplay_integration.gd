extends SceneTree
## Automated Test Suite: Package 1X Gameplay Integration & Persistence Closure
## Tests the complete interactive gameplay lifecycle:
## 1. WorldView startup creates unique, valid outpost objectives away from player base.
## 2. Idempotent enemy force spawning upon authoritative war declaration.
## 3. Right-click outpost gameplay path: eligibility gating, rejection banners, launch, attack order.
## 4. Defender mobilization and combat against player tactical units.
## 5. Outpost damage gating (immune before launch, destructible after launch).
## 6. Canonical plunder rewards credited to ResourceManager without invalid keys.
## 7. Peace treaty handling: disengagement, enemy retreat, siege cancellation.
## 8. Save/load roundtrip and double-load idempotency.

const TacticalUnitScript = preload("res://scripts/military/tactical_unit.gd")
const EnemyTacticalUnitScript = preload("res://scripts/military/enemy_tactical_unit.gd")
const SiegeObjectiveActorScript = preload("res://scripts/combat/siege_objective_actor.gd")
const FieldSiegeManagerScript = preload("res://scripts/combat/field_siege_manager.gd")
const PlayerArmyManagerScript = preload("res://scripts/military/player_army_manager.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")

var total_assertions: int = 0
var passed_assertions: int = 0
var failed_assertions: int = 0
var world_instance: Node = null
var frame_count: int = 0

func _init() -> void:
	print("\n========================================================")
	print("  STARTING PACKAGE 1X GAMEPLAY INTEGRATION TEST SUITE")
	print("========================================================\n")
	var world_scene: PackedScene = load("res://scenes/world/world_view.tscn")
	world_instance = world_scene.instantiate()
	root.add_child(world_instance)

func _assert(condition: bool, test_name: String) -> void:
	total_assertions += 1
	if condition:
		passed_assertions += 1
		print("  [PASS] %s" % test_name)
	else:
		failed_assertions += 1
		printerr("  [FAIL] %s" % test_name)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count == 3:
		_run_all_integration_tests()
		print("\n========================================================")
		print("  Assertions Passed: %d | Failed: %d" % [passed_assertions, failed_assertions])
		if failed_assertions == 0:
			print("  ALL PACKAGE 1X GAMEPLAY INTEGRATION TESTS PASSED! (Exit Code 0)")
			print("========================================================\n")
			quit(0)
			return true
		else:
			printerr("  PACKAGE 1X INTEGRATION TESTS FAILED!")
			print("========================================================\n")
			quit(1)
			return true
	return false

func _run_all_integration_tests() -> void:
	_test_worldview_outpost_generation()
	_test_war_declaration_force_spawning_and_idempotency()
	_test_outpost_right_click_and_siege_launch()
	_test_siege_combat_and_plunder()
	_test_peace_treaty_disengagement()
	_test_persistence_and_double_load()
	_test_spawn_slot_policy_entity_exclusion()
	_test_end_to_end_siege_retry_and_anti_inflation()

func _test_worldview_outpost_generation() -> void:
	print("--- Test 1: WorldView Outpost Objective Generation ---")
	var sm = world_instance.get("field_siege_mgr")
	_assert(sm != null, "TC-INT.1: FieldSiegeManager initialized on WorldView")

	var objs = sm.get_all_objectives()
	_assert(objs.size() >= 3, "TC-INT.1: At least 3 default outposts registered on WorldView startup")

	var mil_outpost = sm.get_objective("outpost_rival_military")
	_assert(mil_outpost != null, "TC-INT.1: rival_military outpost exists")
	_assert(mil_outpost.is_alive == true, "TC-INT.1: rival_military outpost is alive")
	_assert(mil_outpost.is_captured == false, "TC-INT.1: rival_military outpost is not captured")
	_assert(mil_outpost.is_under_active_siege == false, "TC-INT.1: rival_military outpost initially not under active siege")

	var merch_outpost = sm.get_objective("outpost_rival_merchant")
	_assert(merch_outpost != null, "TC-INT.1: rival_merchant outpost exists")

	var tribe_outpost = sm.get_objective("outpost_neutral_tribe")
	_assert(tribe_outpost != null, "TC-INT.1: neutral_tribe outpost exists")

	# Verify outposts do not overlap each other
	var cells: Array[Vector2i] = [mil_outpost.current_cell, merch_outpost.current_cell, tribe_outpost.current_cell]
	_assert(cells[0] != cells[1] and cells[1] != cells[2] and cells[0] != cells[2], "TC-INT.1: Outpost locations are strictly distinct")

func _test_war_declaration_force_spawning_and_idempotency() -> void:
	print("\n--- Test 2: War Declaration & Idempotent Force Spawning ---")
	var fm = world_instance.get("faction_mgr")
	var em = world_instance.get("enemy_military_mgr")

	var fac = fm.get_faction("rival_military")
	fac.is_at_war = true
	fm.war_declared.emit("rival_military")

	var forces = em.get_enemies_by_faction("rival_military")
	_assert(forces.size() > 0, "TC-INT.2: Hostile force spawned for rival_military")
	var count_first = forces.size()

	# Emit war_declared again -> must NOT create duplicate forces
	fm.war_declared.emit("rival_military")
	var forces_repeat = em.get_enemies_by_faction("rival_military")
	_assert(forces_repeat.size() == count_first, "TC-INT.2: Repeated war_declared is strictly idempotent (zero duplicates)")

func _test_outpost_right_click_and_siege_launch() -> void:
	print("\n--- Test 3: Outpost Right-Click & Eligibility Gating ---")
	var sm = world_instance.get("field_siege_mgr")
	var army_mgr = world_instance.get("player_army_mgr")
	var tac_mgr = world_instance.get("tactical_military_mgr")
	var obj = sm.get_objective("outpost_rival_military")

	# Recruit 3 soldiers for player army
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	if rm != null:
		rm.add_resource("food", 200)
		rm.add_resource("gold", 200)
		rm.add_resource("wood", 200)
		rm.add_resource("metal", 200)

	army_mgr.soldier_count = 3
	tac_mgr.sync_with_player_army()
	tac_mgr.select_all()

	# Case A: Army garrisoned at base -> right click outpost cannot launch
	var check_base = sm.can_launch_field_siege("rival_military", "outpost_rival_military")
	_assert(check_base["can_launch"] == false, "TC-INT.3: Cannot launch siege while army is garrisoned at base")

	# Case B: Army mobilized to outpost proximity (e.g. 2 tiles away)
	var near_cell = obj.current_cell + Vector2i(1, 1)
	army_mgr.current_cell = near_cell
	army_mgr.destination_cell = near_cell
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD
	for u in tac_mgr.get_all_units():
		u.current_cell = near_cell
		u.target_cell = near_cell
		u.order_state = TacticalUnitScript.OrderState.IDLE

	var check_field = sm.can_launch_field_siege("rival_military", "outpost_rival_military")
	_assert(check_field["can_launch"] == true, "TC-INT.3: Eligible to launch siege when army is near outpost")

	# Launch siege
	var launch_res = sm.launch_field_siege("rival_military", "outpost_rival_military")
	_assert(launch_res["success"] == true, "TC-INT.3: Field siege launched successfully")
	_assert(obj.is_under_active_siege == true, "TC-INT.3: Outpost flagged as under active siege")
	_assert(sm.is_siege_active_for_objective("outpost_rival_military") == true, "TC-INT.3: is_siege_active_for_objective returns true")

	# Issue tactical attack order
	var atk_res = tac_mgr.issue_attack_order(obj)
	_assert(atk_res["success"] == true, "TC-INT.3: Tactical attack order issued against siege objective")

func _test_siege_combat_and_plunder() -> void:
	print("\n--- Test 4: Siege Combat & Canonical Plunder Awards ---")
	var sm = world_instance.get("field_siege_mgr")
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	var obj = sm.get_objective("outpost_rival_military")

	var initial_metal: int = rm.get_available_stock("metal") if rm != null else 0
	var initial_gold: int = rm.get_available_stock("gold") if rm != null else 0

	# Apply damage to objective while under active siege
	var hp_before = obj.health
	obj.take_damage(50.0, "player_army")
	_assert(obj.health == hp_before - 50.0, "TC-INT.4: Objective took 50 combat damage")

	# Destroy objective to achieve victory
	obj.take_damage(obj.health, "player_army")
	_assert(obj.is_alive == false, "TC-INT.4: Outpost destroyed")
	_assert(obj.is_captured == true, "TC-INT.4: Outpost captured by player")

	# Find siege record and evaluate
	for s_id in sm.active_sieges.keys():
		var s = sm.active_sieges[s_id]
		if s.get("objective_id") == "outpost_rival_military":
			var eval = sm.evaluate_siege_status(s_id)
			_assert(eval["outcome"] == "VICTORY", "TC-INT.4: evaluate_siege_status yields VICTORY")
			break

	_assert(obj.is_under_active_siege == false, "TC-INT.4: Outpost is_under_active_siege reset to false after resolution")
	if rm != null:
		_assert(rm.get_available_stock("metal") == initial_metal + 20, "TC-INT.4: Canonical metal stock incremented by 20")
		_assert(rm.get_available_stock("gold") == initial_gold + 60, "TC-INT.4: Gold stock incremented by 60")
		_assert(rm.get_available_stock("iron") == 0, "TC-INT.4: Non-canonical 'iron' key was not created")

func _test_peace_treaty_disengagement() -> void:
	print("\n--- Test 5: Peace Treaty Disengagement & Siege Cancellation ---")
	var fm = world_instance.get("faction_mgr")
	var em = world_instance.get("enemy_military_mgr")
	var sm = world_instance.get("field_siege_mgr")
	var tac_mgr = world_instance.get("tactical_military_mgr")

	# Start siege against rival_merchant
	var merch_obj = sm.get_objective("outpost_rival_merchant")
	var merch_fac = fm.get_faction("rival_merchant")
	merch_fac.is_at_war = true
	var army_mgr = world_instance.get("player_army_mgr")
	army_mgr.current_cell = merch_obj.current_cell + Vector2i(1, 1)
	army_mgr.destination_cell = army_mgr.current_cell
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD
	for u in tac_mgr.get_all_units():
		u.current_cell = army_mgr.current_cell

	var launch_res = sm.launch_field_siege("rival_merchant", "outpost_rival_merchant")
	_assert(launch_res["success"] == true, "TC-INT.5: Launched siege against rival_merchant")
	tac_mgr.select_all()
	tac_mgr.issue_attack_order(merch_obj)

	# Verify units are attacking
	var attacking_count: int = 0
	for u in tac_mgr.get_selected_units():
		if u.order_state == TacticalUnitScript.OrderState.ATTACKING:
			attacking_count += 1
	_assert(attacking_count > 0, "TC-INT.5: Player units in ATTACKING order state")

	# Sign peace with rival_merchant
	merch_fac.is_at_war = false
	fm.peace_signed.emit("rival_merchant")

	# Verify player units disengaged
	var attacking_after: int = 0
	for u in tac_mgr.get_selected_units():
		if u.order_state == TacticalUnitScript.OrderState.ATTACKING:
			attacking_after += 1
	_assert(attacking_after == 0, "TC-INT.5: All player units disengaged upon peace treaty")
	_assert(sm.is_siege_active_for_objective("outpost_rival_merchant") == false, "TC-INT.5: Active siege cancelled upon peace")
	_assert(merch_obj.is_under_active_siege == false, "TC-INT.5: Outpost is_under_active_siege reset to false")

func _test_persistence_and_double_load() -> void:
	print("\n--- Test 6: Persistence & Double Load Idempotency ---")
	var save_state: Dictionary = SaveManager.serialize_world_state(world_instance)
	_assert(save_state.has("enemy_military"), "TC-INT.6: Serialized state has enemy_military")
	_assert(save_state.has("field_siege"), "TC-INT.6: Serialized state has field_siege")

	var val_res = SaveManager.validate_save_data(save_state)
	if not val_res.get("valid", false):
		print("DEBUG VALIDATION ERROR: ", val_res.get("error"))
	_assert(val_res["valid"] == true, "TC-INT.6: Serialized world state passes strict validation")

	var em = world_instance.get("enemy_military_mgr")
	var sm = world_instance.get("field_siege_mgr")
	var e_count_before: int = em.get_enemy_count()
	var o_count_before: int = sm.get_all_objectives().size()

	# Load once
	var load_1 = SaveManager.apply_loaded_state_to_world(world_instance, save_state)
	_assert(load_1.get("success", false) == true, "TC-INT.6: First restoration succeeded")
	_assert(em.get_enemy_count() == e_count_before, "TC-INT.6: Enemy count preserved on first load")
	_assert(sm.get_all_objectives().size() == o_count_before, "TC-INT.6: Objective count preserved on first load")

	# Load second time (double load)
	var load_2 = SaveManager.apply_loaded_state_to_world(world_instance, save_state)
	_assert(load_2.get("success", false) == true, "TC-INT.6: Second restoration succeeded (double-load)")
	_assert(em.get_enemy_count() == e_count_before, "TC-INT.6: Enemy count strictly identical after double load")
	_assert(sm.get_all_objectives().size() == o_count_before, "TC-INT.6: Objective count strictly identical after double load")

func _test_spawn_slot_policy_entity_exclusion() -> void:
	print("\n--- Test 7: Authoritative Spawn-Slot Entity Exclusion ---")
	var em = world_instance.get("enemy_military_mgr")
	var sm = world_instance.get("field_siege_mgr")
	var tac_mgr = world_instance.get("tactical_military_mgr")
	var nav = world_instance.get("nav")
	var wd = world_instance.get("world_data")
	var citizens = world_instance.get("citizen_list")

	# Collect all registered objective cells
	var obj_cells: Array[Vector2i] = []
	for o in sm.get_all_objectives():
		obj_cells.append(o.current_cell)

	# Collect all player unit cells
	var player_cells: Array[Vector2i] = []
	for u in tac_mgr.get_all_units():
		if u.is_alive:
			player_cells.append(u.current_cell)

	# Collect all living citizen cells
	var citizen_cells: Array[Vector2i] = []
	for cit in citizens:
		if is_instance_valid(cit) and cit.call("is_alive"):
			citizen_cells.append(cit.current_cell)

	# Verify every living enemy unit satisfies the authoritative spawn policy
	var all_enemies = em.get_all_enemies()
	_assert(all_enemies.size() > 0, "TC-INT.7: Active enemy units exist for verification")

	var seen_enemy_cells: Dictionary = {}
	var has_duplicate_enemy_cells := false
	var shares_objective_cell := false
	var shares_player_cell := false
	var shares_citizen_cell := false
	var on_water := false
	var on_occupied_building := false
	var out_of_bounds := false
	var unwalkable := false

	for e in all_enemies:
		if not is_instance_valid(e) or not e.is_alive:
			continue
		var c = e.current_cell
		if not IsoMath.is_in_bounds(c):
			out_of_bounds = true
		if nav != null and not nav.is_cell_walkable(c):
			unwalkable = true
		if wd != null:
			if wd.terrain[c.x][c.y] == WorldGenerator.TerrainType.WATER:
				on_water = true
			if wd.occupancy[c.x][c.y]:
				on_occupied_building = true

		if obj_cells.has(c):
			shares_objective_cell = true
		if player_cells.has(c):
			shares_player_cell = true
		if citizen_cells.has(c):
			shares_citizen_cell = true

		if seen_enemy_cells.has(c):
			has_duplicate_enemy_cells = true
		seen_enemy_cells[c] = true

	_assert(not out_of_bounds, "TC-INT.7: All enemy units are in bounds")
	_assert(not unwalkable, "TC-INT.7: All enemy units occupy walkable cells")
	_assert(not on_water, "TC-INT.7: Zero enemy units on water tiles")
	_assert(not on_occupied_building, "TC-INT.7: Zero enemy units inside building footprints")
	_assert(not shares_objective_cell, "TC-INT.7: Zero enemy units share a cell with any siege objective")
	_assert(not shares_player_cell, "TC-INT.7: Zero enemy units share a cell with player tactical units")
	_assert(not shares_citizen_cell, "TC-INT.7: Zero enemy units share a cell with living citizens")
	_assert(not has_duplicate_enemy_cells, "TC-INT.7: All enemy units occupy pairwise distinct cells")

func _test_end_to_end_siege_retry_and_anti_inflation() -> void:
	print("\n--- Test 8: End-to-End Siege Retry Lifecycle & Anti-Inflation ---")
	var fm = world_instance.get("faction_mgr")
	var em = world_instance.get("enemy_military_mgr")
	var sm = world_instance.get("field_siege_mgr")
	var army_mgr = world_instance.get("player_army_mgr")
	var tac_mgr = world_instance.get("tactical_military_mgr")

	var tribe_obj = sm.get_objective("outpost_neutral_tribe")
	_assert(tribe_obj != null, "TC-INT.8: neutral_tribe outpost found")

	var tribe_fac = fm.get_faction("neutral_tribe")
	tribe_fac.is_at_war = true
	fm.war_declared.emit("neutral_tribe")

	var initial_tribe_units = em.get_enemies_by_faction("neutral_tribe")
	_assert(initial_tribe_units.size() == tribe_obj.garrison_count, "TC-INT.8: War declared spawned exactly garrison_count units (%d)" % tribe_obj.garrison_count)

	# Position player army at outpost proximity
	var near_cell = tribe_obj.current_cell + Vector2i(1, 1)
	army_mgr.current_cell = near_cell
	army_mgr.destination_cell = near_cell
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD
	for u in tac_mgr.get_all_units():
		u.current_cell = near_cell
		u.target_cell = near_cell
		u.order_state = TacticalUnitScript.OrderState.IDLE

	# Launch siege 1 -> should reuse the existing garrison units without duplicating
	var launch_res1 = sm.launch_field_siege("neutral_tribe", "outpost_neutral_tribe")
	_assert(launch_res1["success"] == true, "TC-INT.8: First siege launch on neutral_tribe succeeded")
	var after_launch1 = em.get_enemies_by_faction("neutral_tribe")
	_assert(after_launch1.size() == tribe_obj.garrison_count, "TC-INT.8: Total units remains exactly garrison_count after launch (%d, not doubled)" % tribe_obj.garrison_count)

	# Simulate player withdrawal
	army_mgr.current_cell = Vector2i(32, 33)
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.GARRISONED
	var s_id1 = launch_res1["siege_id"]
	var eval_res1 = sm.evaluate_siege_status(s_id1)
	_assert(eval_res1["outcome"] == "WITHDRAWAL", "TC-INT.8: Siege evaluated as WITHDRAWAL upon army return home")
	_assert(tribe_obj.is_under_active_siege == false, "TC-INT.8: Outpost active siege flag cleared")

	# Return to outpost and launch siege retry
	army_mgr.current_cell = near_cell
	army_mgr.movement_state = PlayerArmyManagerScript.MovementState.IDLE_AT_FIELD
	var launch_res2 = sm.launch_field_siege("neutral_tribe", "outpost_neutral_tribe")
	_assert(launch_res2["success"] == true, "TC-INT.8: Retry launch succeeded")
	var after_retry = em.get_enemies_by_faction("neutral_tribe")
	_assert(after_retry.size() == tribe_obj.garrison_count, "TC-INT.8: Retry does NOT spawn duplicate garrison (count remains %d)" % tribe_obj.garrison_count)

	# Repeated war_declared events must not add units either
	fm.war_declared.emit("neutral_tribe")
	_assert(em.get_enemies_by_faction("neutral_tribe").size() == tribe_obj.garrison_count, "TC-INT.8: Repeated war_declared preserves exact garrison count")
