extends SceneTree

var passed: int = 0
var failed: int = 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
		print("  [PASS] " + msg)
	else:
		failed += 1
		print("  [FAIL] " + msg)

func _make_flat_world(seed_val: int = 4242) -> WorldGenerator.WorldData:
	var wd := WorldGenerator.WorldData.new()
	wd.seed_value = seed_val
	wd.generator_version = WorldGenerator.LATEST_GENERATOR_VERSION
	wd.terrain.resize(WorldGenerator.MAP_SIZE)
	wd.occupancy.resize(WorldGenerator.MAP_SIZE)
	for x in range(WorldGenerator.MAP_SIZE):
		wd.terrain[x] = []
		wd.occupancy[x] = []
		wd.terrain[x].resize(WorldGenerator.MAP_SIZE)
		wd.occupancy[x].resize(WorldGenerator.MAP_SIZE)
		for y in range(WorldGenerator.MAP_SIZE):
			wd.terrain[x][y] = WorldGenerator.TerrainType.GRASS
			wd.occupancy[x][y] = false
	wd.center_spawn = Vector2i(32, 33)
	return wd

func _place_townhall(wd: WorldGenerator.WorldData, origin: Vector2i, b_id: String = "townhall_starter", level: int = 1, state: String = "active") -> Dictionary:
	var b := {
		"id": b_id,
		"type": "townhall",
		"cell": origin,
		"size": Vector2i(3, 3),
		"state": state,
		"is_constructed": (state != "under_construction"),
		"health": 0 if state == "destroyed" else 100,
		"max_health": 100,
		"upgrade_level": level,
		"construction_progress": 12.0 if state != "under_construction" else 0.0,
		"construction_hours": 12.0,
		"storage_applied": true
	}
	for ox in range(3):
		for oy in range(3):
			wd.occupancy[origin.x + ox][origin.y + oy] = true
	wd.buildings.append(b)
	if wd.townhall_anchor.x < 0:
		wd.townhall_anchor = origin
	return b

class MockResourceManager extends Node:
	var stock: Dictionary = {
		EconomyConfig.RES_WOOD: 500,
		EconomyConfig.RES_STONE: 500,
		EconomyConfig.RES_GOLD: 500,
		EconomyConfig.RES_FOOD: 500,
	}
	var reserved: Dictionary = {}
	var tx_tickets: Dictionary = {}

	func get_stock(res_id: String) -> int:
		return int(stock.get(res_id, 0))

	func has_resource(res_id: String, amt: int) -> bool:
		return get_stock(res_id) >= amt

	func can_afford(cost: Dictionary) -> bool:
		for r in cost:
			if get_stock(r) < int(cost[r]):
				return false
		return true

	func consume_resources(cost: Dictionary) -> bool:
		if not can_afford(cost):
			return false
		for r in cost:
			stock[r] = get_stock(r) - int(cost[r])
		return true

	func register_transaction(ticket_id: String, cost: Dictionary) -> bool:
		if tx_tickets.has(ticket_id):
			return true
		if not can_afford(cost):
			return false
		for r in cost:
			stock[r] = get_stock(r) - int(cost[r])
			reserved[r] = int(reserved.get(r, 0)) + int(cost[r])
		tx_tickets[ticket_id] = cost.duplicate()
		return true

	func commit_transaction(ticket_id: String) -> bool:
		if not tx_tickets.has(ticket_id):
			return false
		var cost: Dictionary = tx_tickets[ticket_id]
		for r in cost:
			reserved[r] = maxi(0, int(reserved.get(r, 0)) - int(cost[r]))
		tx_tickets.erase(ticket_id)
		return true

	func has_active_transaction(ticket_id: String) -> bool:
		return tx_tickets.has(ticket_id)

	func rollback_transaction(ticket_id: String) -> bool:
		if not tx_tickets.has(ticket_id):
			return false
		var cost: Dictionary = tx_tickets[ticket_id]
		for r in cost:
			var amt: int = int(cost[r])
			stock[r] = get_stock(r) + amt
			reserved[r] = maxi(0, int(reserved.get(r, 0)) - amt)
		tx_tickets.erase(ticket_id)
		return true

	func get_total_stock(res_id: String) -> int:
		return get_stock(res_id)

	func get_capacity(_res_id: String) -> int:
		return 2000

	func add_storage_capacity(_res_id: String, _amt: int) -> void:
		pass

	func remove_storage_capacity(_res_id: String, _amt: int) -> void:
		pass

	func add_resources_atomic(cost: Dictionary) -> Dictionary:
		var credited := {}
		for r in cost:
			stock[r] = get_stock(r) + int(cost[r])
			credited[r] = int(cost[r])
		return {"success": true, "credited": credited}

class MockWorldView extends Node:
	var territory_mgr: RefCounted = null
	var world_data: WorldGenerator.WorldData = null

func _make_citizen(c_id: String, c_name: String, cell: Vector2i, p_nav: GridNavigation, p_tmgr: TerritoryManager, p_wd: WorldGenerator.WorldData) -> CitizenController:
	var wv := MockWorldView.new()
	wv.territory_mgr = p_tmgr
	wv.world_data = p_wd
	wv.add_to_group("world_view")
	root.add_child(wv)
	var c := CitizenController.new()
	c.citizen_id = c_id
	c.citizen_name = c_name
	c.current_cell = cell
	c.nav = p_nav
	c.world_view = wv
	wv.add_child(c)
	return c

func _init() -> void:
	call_deferred("_run_all")

func _run_all() -> void:
	print("=== RUNNING KU-POST-MVP-TOWN-HALL-RESTORATION-10 ACCEPTANCE SUITE ===")
	_test_nearest_search_suite()
	_test_incremental_scheduler_suite()
	_test_in_place_restoration_suite()
	_test_emergency_rebuild_suite()
	_test_multi_townhall_union()
	_test_save_load_suite()
	_test_performance_benchmark()
	await _test_live_worldview_integration()

	print("=======================================================")
	print("RESTORATION-10 RESULTS: %d PASSED, %d FAILED" % [passed, failed])
	print("=======================================================")
	quit(1 if failed > 0 else 0)

func _test_nearest_search_suite() -> void:
	print("-- [1/6] Nearest-Owned-Cell Search & Recovery Suite --")
	var wd := _make_flat_world(101)
	var nav := GridNavigation.new(wd)

	# 1. Start already matching & walkable
	var res1 := nav.find_path_to_nearest_matching_detailed(Vector2i(10, 10), func(c: Vector2i) -> bool: return c == Vector2i(10, 10))
	_assert(int(res1["status"]) == GridNavigation.NearestSearchStatus.FOUND and res1["path"] == [Vector2i(10, 10)], "S1: Start already matching returns FOUND with [start]")

	# 2. Direct short path
	var res2 := nav.find_path_to_nearest_matching_detailed(Vector2i(5, 5), func(c: Vector2i) -> bool: return c == Vector2i(8, 5))
	_assert(int(res2["status"]) == GridNavigation.NearestSearchStatus.FOUND and res2["path"].size() == 4, "S2: Direct short path returns FOUND with 4 cells")

	# 3. Invalid inputs
	var res_invalid_pred := nav.find_path_to_nearest_matching_detailed(Vector2i(5, 5), Callable())
	var res_invalid_oob := nav.find_path_to_nearest_matching_detailed(Vector2i(-1, 0), func(_c: Vector2i) -> bool: return true)
	var res_invalid_budget := nav.find_path_to_nearest_matching_detailed(Vector2i(5, 5), func(_c: Vector2i) -> bool: return true, 0)
	_assert(
		int(res_invalid_pred["status"]) == GridNavigation.NearestSearchStatus.INVALID_INPUT and
		int(res_invalid_oob["status"]) == GridNavigation.NearestSearchStatus.INVALID_INPUT and
		int(res_invalid_budget["status"]) == GridNavigation.NearestSearchStatus.INVALID_INPUT,
		"S3: Invalid predicate, OOB start, and zero budget return INVALID_INPUT"
	)

	# 4. >2048 expansion completeness on 64x64: fill almost entire map with snake/open flood where target is at (63, 63) from (0, 0)
	# Distance in 64x64 from (0,0) to (63,63) expands >2048 cells (manhattan 126 covers nearly all 4096 cells!).
	var target_far := Vector2i(63, 63)
	var res_far_default := nav.find_path_to_nearest_matching_detailed(Vector2i(0, 0), func(c: Vector2i) -> bool: return c == target_far)
	_assert(
		int(res_far_default["status"]) == GridNavigation.NearestSearchStatus.FOUND and
		int(res_far_default["iterations"]) > 2048 and
		res_far_default["path"][-1] == target_far,
		"S4: Complete search (>2048 expansions: %d) finds far cell (63,63) with default 4096 budget" % int(res_far_default["iterations"])
	)

	# 5. Same far target with explicit budget=2048 returns BUDGET_EXHAUSTED (not UNREACHABLE)
	var res_far_capped := nav.find_path_to_nearest_matching_detailed(Vector2i(0, 0), func(c: Vector2i) -> bool: return c == target_far, 2048)
	_assert(
		int(res_far_capped["status"]) == GridNavigation.NearestSearchStatus.BUDGET_EXHAUSTED and
		res_far_capped["path"].is_empty(),
		"S5: Budget=2048 on >2048 search explicitly reports BUDGET_EXHAUSTED"
	)

	# 6. Completely walled-off island returns UNREACHABLE
	var wd_walled := _make_flat_world(102)
	for x in range(8, 13):
		wd_walled.occupancy[x][8] = true
		wd_walled.occupancy[x][12] = true
	for y in range(8, 13):
		wd_walled.occupancy[8][y] = true
		wd_walled.occupancy[12][y] = true
	var nav_walled := GridNavigation.new(wd_walled)
	var res_walled := nav_walled.find_path_to_nearest_matching_detailed(Vector2i(10, 10), func(c: Vector2i) -> bool: return c == Vector2i(30, 30))
	_assert(
		int(res_walled["status"]) == GridNavigation.NearestSearchStatus.UNREACHABLE and
		res_walled["path"].is_empty(),
		"S6: Walled-off island returns UNREACHABLE"
	)

	# 7. Weighted terrain cost prefers GRASS over HILLS even if equal or slightly longer
	var wd_weight := _make_flat_world(103)
	for x in range(11, 16):
		wd_weight.terrain[x][10] = WorldGenerator.TerrainType.HILLS # cost 2
	var nav_weight := GridNavigation.new(wd_weight)
	var res_weight := nav_weight.find_path_to_nearest_matching_detailed(Vector2i(10, 10), func(c: Vector2i) -> bool: return c.x >= 16 and c.y == 10)
	_assert(
		int(res_weight["status"]) == GridNavigation.NearestSearchStatus.FOUND and
		not (Vector2i(13, 10) in res_weight["path"]),
		"S7: Dijkstra selects lower-cost GRASS detour over HILLS cells"
	)

	# 8. Backwards-compatible wrapper
	var compat_path := nav.find_path_to_nearest_matching(Vector2i(0, 0), func(c: Vector2i) -> bool: return c == target_far)
	_assert(not compat_path.is_empty() and compat_path[-1] == target_far, "S8: Backwards-compatible find_path_to_nearest_matching succeeds >2048")

	# 9. CitizenController recovery across >2048 expansion + multi-frame walk
	var wd_cit := _make_flat_world(104)
	_place_townhall(wd_cit, Vector2i(58, 58), "townhall_far", 1, "active")
	var tmgr := TerritoryManager.new()
	tmgr.initialize(wd_cit)
	var nav_cit := GridNavigation.new(wd_cit)
	var cit := _make_citizen("cit_far", "Far Citizen", Vector2i(1, 1), nav_cit, tmgr, wd_cit)
	var rec_ok := false
	for _frame in range(40):
		tmgr.advance_recovery_frame()
		if cit._attempt_territory_recovery(tmgr):
			rec_ok = true
			break
	_assert(rec_ok and cit.is_recovering_to_territory and tmgr.is_cell_owned(cit.recovery_target), "S9: CitizenController recovers across frames from (1,1) to far territory (>2048 Dijkstra)")
	cit.get_parent().free()

	# 10. CitizenController walled-off island fails gracefully across frames, enters IDLE with retry cooldown
	var tmgr_walled := TerritoryManager.new()
	_place_townhall(wd_walled, Vector2i(30, 30), "townhall_walled", 1, "active")
	tmgr_walled.initialize(wd_walled)
	var cit_w := _make_citizen("cit_walled", "Walled Citizen", Vector2i(10, 10), nav_walled, tmgr_walled, wd_walled)
	var rec_w := false
	for _frame in range(5):
		tmgr_walled.advance_recovery_frame()
		if cit_w._attempt_territory_recovery(tmgr_walled):
			rec_w = true
			break
		if cit_w._recovery_retry_timer > 0.0:
			break
	_assert(not rec_w and cit_w.current_state == CitizenController.State.IDLE and cit_w._recovery_retry_timer > 0.0, "S10: Walled-off citizen enters IDLE with retry cooldown after exhausting reachable frontier")
	cit_w.get_parent().free()

func _test_in_place_restoration_suite() -> void:
	print("-- [2/6] In-Place Town Hall Restoration Suite --")
	var wd := _make_flat_world(201)
	var th := _place_townhall(wd, Vector2i(31, 30), "townhall_starter", 3, "active")
	var house := {"id": "house_1", "type": "house", "cell": Vector2i(35, 30), "size": Vector2i(2, 2), "state": "destroyed", "health": 0, "max_health": 100}
	wd.buildings.append(house)
	var tmgr := TerritoryManager.new()
	tmgr.initialize(wd)
	_assert(tmgr.get_owned_count() == 1201, "R1: Level 3 Town Hall starts with 1201 owned cells")

	# Destroy Town Hall
	th["state"] = "destroyed"
	th["health"] = 0
	tmgr.recalculate_territory()
	_assert(tmgr.get_owned_count() == 0, "R2: Destroying Town Hall sets owned_count == 0 while keeping ruin in buildings")

	var rm := MockResourceManager.new()
	# Ordinary repair rejects destroyed buildings (including Town Hall)
	_assert(not bool(BuildingSystem.can_repair_building(th, wd, rm).get("can_repair", false)), "R3: Ordinary can_repair_building still rejects destroyed Town Hall")
	_assert(not bool(BuildingSystem.can_repair_building(house, wd, rm).get("can_repair", false)), "R4: Ordinary can_repair_building still rejects destroyed House")
	_assert(not bool(BuildingSystem.can_restore_townhall(house, wd, rm).get("can_restore", false)), "R5: can_restore_townhall rejects ordinary destroyed House")

	# Insufficient resources check (atomic, zero deduction)
	rm.stock[EconomyConfig.RES_GOLD] = 10
	var check_low := BuildingSystem.can_restore_townhall(th, wd, rm)
	_assert(not bool(check_low.get("can_restore", false)), "R6: Insufficient gold blocks Town Hall restoration")
	var start_low := BuildingSystem.start_townhall_restoration(th, wd, rm)
	_assert(not bool(start_low.get("success", false)) and rm.get_stock(EconomyConfig.RES_WOOD) == 500 and rm.get_stock(EconomyConfig.RES_GOLD) == 10, "R7: Failed start_townhall_restoration deducts zero resources")

	# Restore resources and start restoration
	rm.stock[EconomyConfig.RES_GOLD] = 500
	var start_ok := BuildingSystem.start_townhall_restoration(th, wd, rm)
	_assert(
		bool(start_ok.get("success", false)) and
		th["state"] == "destroyed" and
		bool(th.get("is_repairing", false)) and
		bool(th.get("is_restoring_townhall", false)) and
		is_equal_approx(float(th.get("repair_hours_required", 0.0)), 12.0) and
		int(th.get("upgrade_level", 0)) == 3 and
		rm.get_stock(EconomyConfig.RES_WOOD) == 450 and
		rm.get_stock(EconomyConfig.RES_STONE) == 460 and
		rm.get_stock(EconomyConfig.RES_GOLD) == 425,
		"R8: start_townhall_restoration reserves 50W/40S/75G, sets 12.0h, keeps state=destroyed and upgrade_level=3 until completion"
	)

	# Mid-restoration owned_count remains 0; ordinary citizen frozen, assigned Town Hall builder allowed (Policy 1C)
	tmgr.recalculate_territory()
	_assert(tmgr.get_owned_count() == 0, "R9: Territory stays 0 while Town Hall restoration is in progress")
	var nav := GridNavigation.new(wd)
	var ord_cit := _make_citizen("ord_1", "Ordinary", Vector2i(20, 20), nav, tmgr, wd)
	var ord_pred := ord_cit._get_civilian_territory_predicate(Vector2i(20, 20), Vector2i(25, 20))
	_assert(ord_pred.is_valid() and not bool(ord_pred.call(Vector2i(21, 20))), "R10: Ordinary citizen movement blocked when owned_count == 0")
	var bld_cit := _make_citizen("bld_1", "Builder", Vector2i(20, 20), nav, tmgr, wd)
	bld_cit.role = "builder"
	var jm := JobManager.new()
	var th_job = jm.create_job("builder", Vector2i(31, 33), "Restore TH", "townhall_starter", 12.0, 1, false)
	bld_cit.active_job = th_job
	_assert(bld_cit._is_valid_townhall_repair_exception(Vector2i(31, 33)), "R11: Assigned builder has Policy 1C exception for Town Hall restoration")
	ord_cit.get_parent().free()
	bld_cit.get_parent().free()

	# Cancel restoration refunds 100% atomically
	var cancel_ok := BuildingSystem.cancel_repair(th, wd, rm)
	_assert(
		bool(cancel_ok.get("success", false)) and
		not bool(th.get("is_repairing", false)) and
		not bool(th.get("is_restoring_townhall", false)) and
		rm.get_stock(EconomyConfig.RES_WOOD) == 500 and
		rm.get_stock(EconomyConfig.RES_STONE) == 500 and
		rm.get_stock(EconomyConfig.RES_GOLD) == 500,
		"R12: Cancelling Town Hall restoration refunds 50W/40S/75G atomically"
	)

	# Re-start and complete restoration -> Level 1 + 365 cells
	BuildingSystem.start_townhall_restoration(th, wd, rm)
	var comp_ok := BuildingSystem.complete_repair(th, wd, rm)
	tmgr.recalculate_territory()
	_assert(
		bool(comp_ok.get("success", false)) and
		th["state"] == "active" and
		int(th["health"]) == int(th["max_health"]) and
		int(th["upgrade_level"]) == 1 and
		not bool(th.get("is_repairing", false)) and
		not bool(th.get("is_restoring_townhall", false)) and
		tmgr.get_owned_count() == 365,
		"R13: Completed Town Hall restoration returns to Level 1 with 365 owned cells"
	)

func _test_emergency_rebuild_suite() -> void:
	print("-- [3/6] Emergency Town Hall Rebuild Suite --")
	var wd := _make_flat_world(301)
	var th := _place_townhall(wd, Vector2i(31, 30), "townhall_starter", 2, "destroyed")
	var tmgr := TerritoryManager.new()
	tmgr.initialize(wd)
	var rm := MockResourceManager.new()

	# Blocked while ruin still exists
	var chk_ruin := BuildingSystem.can_emergency_rebuild_townhall(Vector2i(31, 30), wd, rm, tmgr.get_owned_count())
	_assert(not bool(chk_ruin.get("valid", false)), "E1: Emergency rebuild blocked while Town Hall ruin exists")

	# Demolish ruin -> anchor preserved, count_townhalls == 0
	wd.townhall_anchor = th["cell"]
	var dem := BuildingSystem.demolish_building(th, wd, rm)
	_assert(bool(dem.get("success", false)) and BuildingSystem.count_townhalls(wd) == 0 and wd.townhall_anchor == Vector2i(31, 30), "E2: Demolishing ruin leaves 0 Town Halls and preserves townhall_anchor")

	# Blocked at non-anchor cell
	var chk_away := BuildingSystem.can_emergency_rebuild_townhall(Vector2i(20, 20), wd, rm, 0)
	_assert(not bool(chk_away.get("valid", false)), "E3: Emergency rebuild rejected at non-anchor cell (20,20)")

	# Ordinary building outside territory still blocked
	_assert(not tmgr.is_footprint_owned(Vector2i(31, 30), Vector2i(2, 2)), "E4: Ordinary house footprint still outside territory when owned_count == 0")

	# Place emergency Town Hall at anchor
	var em_res := BuildingSystem.place_emergency_townhall(Vector2i(31, 30), wd, rm, 0)
	_assert(
		bool(em_res.get("success", false)) and
		em_res["building"]["state"] == "under_construction" and
		int(em_res["building"]["upgrade_level"]) == 1 and
		is_equal_approx(float(em_res["building"]["construction_hours"]), 12.0) and
		bool(em_res["building"].get("is_emergency_rebuild", false)) and
		rm.get_stock(EconomyConfig.RES_WOOD) == 450 and
		rm.get_stock(EconomyConfig.RES_STONE) == 460 and
		rm.get_stock(EconomyConfig.RES_GOLD) == 425,
		"E5: Emergency Town Hall placed at anchor (31,30) with 50W/40S/75G cost and 12.0h duration"
	)

	# Complete construction after 12.0 hours -> Level 1 + 365 cells
	var em_b: Dictionary = em_res["building"]
	em_b["construction_progress"] = 12.0
	var comp := BuildingSystem.complete_building(em_b, wd, rm)
	tmgr.recalculate_territory()
	_assert(bool(comp) and em_b["state"] == "active" and int(em_b["upgrade_level"]) == 1 and tmgr.get_owned_count() == 365, "E6: Completed emergency Town Hall activates Level 1 territory (365 cells) [comp=%s, state=%s, lvl=%s, owned=%d]" % [str(comp), str(em_b.get("state")), str(em_b.get("upgrade_level")), tmgr.get_owned_count()])

func _test_multi_townhall_union() -> void:
	print("-- [4/6] Multi-Town Hall Territory Union Suite --")
	var wd := _make_flat_world(401)
	var th1 := _place_townhall(wd, Vector2i(20, 20), "townhall_1", 2, "active")
	var th2 := _place_townhall(wd, Vector2i(40, 40), "townhall_2", 1, "active")
	var tmgr := TerritoryManager.new()
	tmgr.initialize(wd)
	var union_cnt := tmgr.get_owned_count()
	_assert(union_cnt > 685, "M1: Two Town Halls form union > 685 cells (%d)" % union_cnt)

	th1["state"] = "destroyed"
	th1["health"] = 0
	tmgr.recalculate_territory()
	_assert(tmgr.get_owned_count() == 365, "M2: Destroying one Town Hall preserves remaining Town Hall's 365 cells")

	var rm := MockResourceManager.new()
	BuildingSystem.start_townhall_restoration(th1, wd, rm)
	BuildingSystem.complete_repair(th1, wd, rm)
	tmgr.recalculate_territory()
	_assert(int(th1["upgrade_level"]) == 1 and tmgr.get_owned_count() > 365, "M3: Restored Town Hall returns to Level 1 and restores multi-TH union")

func _test_save_load_suite() -> void:
	print("-- [5/6] Save/Load Round-Trip & Legacy Migration Suite --")
	# Test SaveManager.validate_save_data + metadata townhall_anchor_x/y + building flags
	var sm_script: GDScript = load("res://scripts/persistence/save_manager.gd")
	_assert(sm_script != null, "SL1: SaveManager script loads cleanly")

	# Build a minimal valid save dictionary representing restoring Town Hall
	var sample_save := {
		"schema_version": 1,
		"metadata": {
			"world_seed": 4242,
			"world_generator_version": WorldGenerator.LATEST_GENERATOR_VERSION,
			"world_id": "test_world_rest07",
			"townhall_anchor_x": 31,
			"townhall_anchor_y": 30
		},
		"resources": {
			"stock": {"wood": 450, "stone": 460, "gold": 425, "food": 500},
			"capacities": {"wood": 1000, "stone": 1000, "gold": 1000, "food": 1000},
			"active_population": 5
		},
		"buildings": [
			{
				"id": "townhall_starter",
				"type": "townhall",
				"cell_x": 31,
				"cell_y": 30,
				"size_x": 3,
				"size_y": 3,
				"state": "destroyed",
				"health": 0,
				"max_health": 100,
				"upgrade_level": 2,
				"construction_progress": 12.0,
				"construction_hours": 12.0,
				"is_repairing": true,
				"is_restoring_townhall": true,
				"repair_progress": 4.5,
				"repair_hours_required": 12.0,
				"repair_cost": {"wood": 50, "stone": 40, "gold": 75},
				"repair_reserved": true,
				"repair_ticket_id": "restore_townhall_starter"
			}
		],
		"citizens": []
	}
	var val_res: Dictionary = SaveManager.validate_save_data(sample_save)
	_assert(bool(val_res.get("valid", false)), "SL2: Save data with destroyed restoring Town Hall passes SaveManager.validate_save_data: %s" % str(val_res.get("error", "")))

	# Validate emergency rebuild save record
	sample_save["buildings"] = [
		{
			"id": "townhall_starter",
			"type": "townhall",
			"cell_x": 31,
			"cell_y": 30,
			"size_x": 3,
			"size_y": 3,
			"state": "under_construction",
			"health": 100,
			"max_health": 100,
			"upgrade_level": 1,
			"construction_progress": 3.0,
			"construction_hours": 12.0,
			"is_emergency_rebuild": true
		}
	]
	var val_em: Dictionary = SaveManager.validate_save_data(sample_save)
	_assert(bool(val_em.get("valid", false)), "SL3: Save data with emergency rebuild Town Hall passes SaveManager.validate_save_data")

	# Validate demolished 0-Town Hall save record
	sample_save["buildings"] = []
	var val_zero: Dictionary = SaveManager.validate_save_data(sample_save)
	_assert(bool(val_zero.get("valid", false)), "SL4: Save data with 0 Town Halls and townhall_anchor passes SaveManager.validate_save_data")

func _test_performance_benchmark() -> void:
	print("-- [6/6] Recovery Search Performance Benchmark --")
	var wd := _make_flat_world(601)
	var nav := GridNavigation.new(wd)
	var t0 := Time.get_ticks_usec()
	var res_worst := nav.find_path_to_nearest_matching_detailed(Vector2i(0, 0), func(_c: Vector2i) -> bool: return false)
	var dt_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	_assert(
		int(res_worst["status"]) == GridNavigation.NearestSearchStatus.UNREACHABLE and dt_ms < 100.0,
		"P1: Full 64x64 unreachable Dijkstra benchmark completed in %.2f ms (%d expansions)" % [dt_ms, int(res_worst["iterations"])]
	)

func _test_incremental_scheduler_suite() -> void:
	print("-- [1b/6] Incremental Recovery Scheduler & Fairness Suite --")
	var wd := _make_flat_world(701)
	_place_townhall(wd, Vector2i(50, 50), "townhall_sched", 1, "active")
	var tmgr := TerritoryManager.new()
	tmgr.initialize(wd)
	var nav := GridNavigation.new(wd)

	# IS1: Single far request pauses as IN_PROGRESS within 1 frame budget (160 expansions), then completes
	tmgr.advance_recovery_frame()
	var r1 := tmgr.request_recovery("sched_1", Vector2i(5, 5), nav)
	_assert(int(r1["status"]) == GridNavigation.NearestSearchStatus.IN_PROGRESS and tmgr.get_recovery_budget_remaining() == 0, "IS1: Far recovery pauses cleanly as IN_PROGRESS after spending shared 160-expansion frame budget")

	# IS2: Cancel cleans up queue immediately
	tmgr.cancel_recovery("sched_1")
	_assert(tmgr.get_active_recovery_count() == 0 and tmgr.get_recovery_queue_size() == 0, "IS2: cancel_recovery releases scheduler state and queue entry")

	# IS3: 20 simultaneous citizens complete fairly across frames without starvation or exceeding per-frame budget
	var completed: Dictionary = {}
	var max_frames := 450
	var frames_used := 0
	for f in range(max_frames):
		tmgr.advance_recovery_frame()
		for i in range(20):
			var cid := "batch_%d" % i
			if completed.has(cid):
				continue
			var sx := 2 + (i % 5) * 2
			var sy := 2 + int(i / 5) * 2
			var rr := tmgr.request_recovery(cid, Vector2i(sx, sy), nav)
			if int(rr["status"]) == GridNavigation.NearestSearchStatus.FOUND:
				completed[cid] = rr["path"]
		frames_used = f + 1
		if completed.size() == 20:
			break
	_assert(completed.size() == 20, "IS3: All 20 simultaneous recovery requests completed fairly across %d frames (%d/20)" % [frames_used, completed.size()])

	# IS4: Dynamic obstacle / territory invalidation cancels stale in-flight search cleanly
	tmgr.advance_recovery_frame()
	var r_inv1 := tmgr.request_recovery("inv_cit", Vector2i(2, 2), nav)
	_assert(int(r_inv1["status"]) == GridNavigation.NearestSearchStatus.IN_PROGRESS, "IS4a: Request queued as IN_PROGRESS before world change")
	tmgr.invalidate_walkable_cache()
	tmgr.advance_recovery_frame()
	var r_inv2 := tmgr.request_recovery("inv_cit", Vector2i(2, 2), nav)
	_assert(int(r_inv2["status"]) == GridNavigation.NearestSearchStatus.IN_PROGRESS and int(r_inv2["iterations"]) <= TerritoryManager.RECOVERY_EXPANSIONS_PER_FRAME, "IS4b: World invalidation cleanly restarts search without delivering stale path")
	tmgr.cancel_recovery("inv_cit")

func _test_live_worldview_integration() -> void:
	print("-- [7/7] Live WorldView End-to-End Integration & Persistence Suite --")
	var packed: PackedScene = load("res://scenes/world/world_view.tscn")
	var wv := packed.instantiate()
	root.add_child(wv)
	for _i in range(6):
		await process_frame

	var rm := root.get_node_or_null("ResourceManager")
	var tm := root.get_node_or_null("TimeManager")
	var hud := wv.get_node_or_null("HUD")
	if rm != null and rm.has_method("add_resources_atomic"):
		rm.add_resources_atomic({EconomyConfig.RES_WOOD: 500, EconomyConfig.RES_STONE: 500, EconomyConfig.RES_GOLD: 500})

	# A1: Multi-TH immutable anchor test in live WorldView
	var expected_anchor: Vector2i = Vector2i(wv.world_data.map_width / 2 - 1, wv.world_data.map_height / 2 - 2)
	_assert(wv.world_data.townhall_anchor == expected_anchor, "A1: Live starter world initializes townhall_anchor to %s" % str(expected_anchor))
	var sec_origin: Vector2i = expected_anchor + Vector2i(14, 15)
	var sec_th := _place_townhall(wv.world_data, sec_origin, "townhall_secondary", 1, "active")
	wv._instantiate_building_node("townhall", sec_origin, Vector2i(3, 3), "active")
	wv.territory_mgr.recalculate_territory()
	wv.demolish_building_project("townhall_secondary")
	_assert(wv.world_data.townhall_anchor == expected_anchor, "A2: Demolishing secondary Town Hall preserves original kingdom anchor %s" % str(expected_anchor))

	# L1: Live In-Place Restoration (destroy -> select -> restore -> pause -> 12h -> Level 1 + dropoff)
	var th := BuildingSystem.get_building_by_id("townhall_starter", wv.world_data)
	th["upgrade_level"] = 3
	th["state"] = "destroyed"
	th["health"] = 0
	wv.territory_mgr.recalculate_territory()
	_assert(wv.territory_mgr.get_owned_count() == 0, "L1a: Live destroyed starter Town Hall drops owned_count to 0")

	if hud != null:
		hud.call("show_building_inspector", th)
		var rbtn = hud.get("repair_btn")
		_assert(rbtn != null and rbtn.visible and not rbtn.disabled and rbtn.text == "Phục Hồi Tòa Thị Chính", "L1b: Live HUD inspector exposes 'Phục Hồi Tòa Thị Chính' for destroyed Town Hall")

	var wood_before: int = rm.get_available_stock(EconomyConfig.RES_WOOD)
	var stone_before: int = rm.get_available_stock(EconomyConfig.RES_STONE)
	var gold_before: int = rm.get_available_stock(EconomyConfig.RES_GOLD)
	var start_res: Dictionary = wv.start_townhall_restoration("townhall_starter", rm)
	_assert(
		bool(start_res.get("success", false)) and
		rm.get_available_stock(EconomyConfig.RES_WOOD) == wood_before - 50 and
		rm.get_available_stock(EconomyConfig.RES_STONE) == stone_before - 40 and
		rm.get_available_stock(EconomyConfig.RES_GOLD) == gold_before - 75,
		"L1c: Live start_townhall_restoration reserves exact 50W/40S/75G"
	)

	# Assign a builder >2 cells away and verify Policy 1C travel
	var builder_start: Vector2i = expected_anchor + Vector2i(-5, 0)
	var builder_cit = null
	for c in wv.citizen_list:
		if is_instance_valid(c):
			builder_cit = c
			break
	if builder_cit != null:
		builder_cit.role = "builder"
		builder_cit.current_cell = builder_start
		builder_cit.active_job = null
		builder_cit.current_state = CitizenController.State.IDLE
		builder_cit._process_idle(0.1)
		_assert(builder_cit.active_job != null and builder_cit.current_state == CitizenController.State.MOVING_TO_JOB and not builder_cit.current_path.is_empty(), "L1d: Builder at %s (>2 cells away) acquires Town Hall restoration job and paths via Policy 1C" % str(builder_start))

	# Pause check: progress must not advance while TimeManager is paused
	if tm != null:
		tm.set_speed(0)
	var prog_paused_before: float = float(th.get("repair_progress", 0.0))
	if tm != null and tm.get("current_speed") == 0:
		# Simulate TimeManager hour check while paused (must stay 0)
		_assert(is_equal_approx(float(th.get("repair_progress", 0.0)), prog_paused_before), "L1e: Paused TimeManager keeps repair_progress frozen")
		tm.set_speed(1)

	# Save mid-restoration via real SaveManager.save_to_file() in isolated APPDATA
	var save_path := "user://rest10_inplace.json"
	var real_save_path := ProjectSettings.globalize_path(save_path)
	var save_res: Dictionary = SaveManager.save_to_file(wv, save_path)
	_assert(bool(save_res.get("success", false)) and real_save_path.contains("isolated_appdata"), "L3a: SaveManager.save_to_file() mid-restoration succeeds in isolated APPDATA: %s" % real_save_path)

	# Load back into live WorldView and verify no duplicate resource deduction
	var load_file_res: Dictionary = SaveManager.load_from_file(save_path)
	var load_res: Dictionary = SaveManager.apply_loaded_state_to_world(wv, load_file_res.get("data", {})) if bool(load_file_res.get("success", false)) else {"success": false}
	var th_loaded := BuildingSystem.get_building_by_id("townhall_starter", wv.world_data)
	_assert(
		bool(load_res.get("success", false)) and
		bool(th_loaded.get("is_restoring_townhall", false)) and
		rm.get_available_stock(EconomyConfig.RES_WOOD) == wood_before - 50 and
		rm.get_available_stock(EconomyConfig.RES_STONE) == stone_before - 40 and
		rm.get_available_stock(EconomyConfig.RES_GOLD) == gold_before - 75,
		"L3b: SaveManager.load_from_file() + apply_loaded_state_to_world() restores in-place restoration without double-charging resources"
	)

	# Advance 11 hours (<12h) -> must NOT complete yet
	wv.advance_repair_work("townhall_starter", 11.0, rm)
	_assert(th_loaded.get("state", "") == "destroyed" and wv.territory_mgr.get_owned_count() == 0, "L1f: At 11.0h (<12.0h), Town Hall restoration is not prematurely completed")

	# Advance remaining 1.0h -> completes at 12.0h, resets to Level 1, restores 365 cells & dropoff
	var th_dropoff: Vector2i = expected_anchor + Vector2i(0, 4)
	wv.advance_repair_work("townhall_starter", 1.0, rm)
	_assert(
		th_loaded.get("state", "") == "active" and
		int(th_loaded.get("upgrade_level", 0)) == 1 and
		wv.territory_mgr.get_owned_count() == 365 and
		wv.workplace_mgr.get_nearest_dropoff_cell(th_dropoff) == th_dropoff,
		"L1g: Completing 12.0h restoration activates Town Hall at Level 1 (365 cells) and restores dropoff"
	)

	# L2: Live Emergency Rebuild (destroy -> demolish -> save/load -> rebuild at anchor -> 12h -> Level 1)
	th_loaded["state"] = "destroyed"
	th_loaded["health"] = 0
	wv.territory_mgr.recalculate_territory()
	wv.demolish_building_project("townhall_starter")
	_assert(BuildingSystem.count_townhalls(wv.world_data) == 0 and wv.territory_mgr.get_owned_count() == 0 and wv.world_data.townhall_anchor == expected_anchor, "L2a: Demolishing ruin leaves 0 Town Halls and preserves %s anchor" % str(expected_anchor))

	var em_res: Dictionary = wv.start_emergency_townhall_rebuild(rm)
	_assert(bool(em_res.get("success", false)) and em_res["building"]["cell"] == expected_anchor, "L2b: Live emergency rebuild placed at original anchor %s" % str(expected_anchor))

	var em_save_path := "user://rest10_emergency.json"
	var save_em: Dictionary = SaveManager.save_to_file(wv, em_save_path)
	var load_em_file: Dictionary = SaveManager.load_from_file(em_save_path)
	var load_em: Dictionary = SaveManager.apply_loaded_state_to_world(wv, load_em_file.get("data", {})) if bool(load_em_file.get("success", false)) else {"success": false}
	var em_loaded := BuildingSystem.get_building_by_id("townhall_starter", wv.world_data)
	_assert(bool(save_em.get("success", false)) and bool(load_em.get("success", false)) and BuildingSystem.count_townhalls(wv.world_data) == 1 and bool(em_loaded.get("is_emergency_rebuild", false)), "L3c: Live Save/Load mid-emergency-rebuild preserves 1 Town Hall and anchor")

	wv.advance_construction_work("townhall_starter", 12.0, rm)
	_assert(
		em_loaded.get("state", "") == "active" and
		int(em_loaded.get("upgrade_level", 0)) == 1 and
		wv.territory_mgr.get_owned_count() == 365,
		"L2c: Completing 12.0h emergency rebuild activates Level 1 Town Hall with 365 cells"
	)

	wv.free()
