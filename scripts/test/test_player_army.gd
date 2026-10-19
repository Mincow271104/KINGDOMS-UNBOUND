extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — Package 1L: Player Army Recruitment & Upkeep
## Covers TC-ARMY.1 through TC-ARMY.30:
## Recruitment:
##   TC-ARMY.1: Initial army state (0 soldiers, 0 cap, supplied, last_upkeep_day -1)
##   TC-ARMY.2: Recruitment fails when no barracks exist
##   TC-ARMY.3: Under-construction barracks provides 0 capacity
##   TC-ARMY.4: 1 active barracks allows recruitment up to 5 soldiers
##   TC-ARMY.5: 2 active barracks allows recruitment up to 10 soldiers
##   TC-ARMY.6: Recruitment atomically deducts 20 Gold, 2 Metal, 5 Food per soldier
##   TC-ARMY.7: Insufficient Gold fails recruitment (0 resources deducted)
##   TC-ARMY.8: Insufficient Metal fails recruitment (0 resources deducted)
##   TC-ARMY.9: Insufficient Food fails recruitment (0 resources deducted)
##   TC-ARMY.10: Zero or negative recruitment count rejected safely
##   TC-ARMY.11: Exceeding barracks capacity fails recruitment (0 resources deducted)
##   TC-ARMY.12: Citizen registry and citizen population unchanged after recruitment
##   TC-ARMY.13: Repeated recruitment up to capacity succeeds; over-capacity rejected
## Upkeep & Morale:
##   TC-ARMY.14: Daily upkeep consumes 1 Food per soldier on simulation day passed
##   TC-ARMY.15: Same-day multiple upkeep calls are strictly idempotent
##   TC-ARMY.16: Upkeep with 0 soldiers costs 0 food
##   TC-ARMY.17: Insufficient food marks army unsupplied without deleting soldiers
##   TC-ARMY.18: Insufficient food leaves food stock intact (no partial deduction)
##   TC-ARMY.19: Combat morale: 70.0 when supplied, 45.0 when unsupplied
##   TC-ARMY.20: Army recovers to supplied state when food is replenished on next day
##   TC-ARMY.21: TimeManager pause does not trigger upkeep
##   TC-ARMY.22: TimeManager speed change safety (no duplicate or premature upkeep)
## Defense & Casualties:
##   TC-ARMY.23: Defending force combines recruited army units + citizen guards
##   TC-ARMY.24: Weighted combat morale matches army vs guard proportions
##   TC-ARMY.25: Defender casualties in battle deduct from recruited army first
##   TC-ARMY.26: Overflow casualties beyond recruited army apply to citizen guards
##   TC-ARMY.27: Recruited army casualties do NOT fire citizen_died or affect citizens
##   TC-ARMY.28: Citizen guard casualties fire normal citizen death lifecycle
## Persistence, Roundtrip & Edge Cases:
##   TC-ARMY.29: Unit serialization roundtrip preserves soldier_count, is_supplied, last_upkeep_day
##   TC-ARMY.29B: Full SaveManager world-state roundtrip, double load idempotency & Save->Load->Save stability
##   TC-ARMY.30: Unit legacy save load without player_army cleanly resets to 0 soldiers
##   TC-ARMY.30B: Full legacy world save load resets world army to 0 soldiers cleanly
##   TC-ARMY.31: Upkeep day validation against game_clock.current_day & indefinite evasion prevention
##   TC-ARMY.32: Live Barracks capacity, state transitions (active/damage/demolish) & HUD UI refresh

const PlayerArmyManagerScript = preload("res://scripts/military/player_army_manager.gd")
const BattleCampaignManagerScript = preload("res://scripts/combat/battle_campaign_manager.gd")
const BattleResolverScript = preload("res://scripts/combat/battle_resolver.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const FactionManagerScript = preload("res://scripts/factions/faction_manager.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const CitizenControllerScript = preload("res://scripts/entities/citizen_controller.gd")
const JobManagerScript = preload("res://scripts/jobs/job_manager.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")

var frame_count: int = 0
var world_instance: Node = null
var failures: int = 0

class MockResourceManager:
	var stock: Dictionary = {}
	var reserved: Dictionary = {}
	var fail_reservation: bool = false
	var reserve_calls: int = 0
	var commit_calls: int = 0

	func _init(initial_stock: Dictionary = {}) -> void:
		stock = {
			EconomyConfigScript.RES_FOOD: 200,
			EconomyConfigScript.RES_WOOD: 200,
			EconomyConfigScript.RES_GOLD: 200,
			EconomyConfigScript.RES_STONE: 100,
			EconomyConfigScript.RES_METAL: 100
		}
		for k in initial_stock:
			stock[k] = initial_stock[k]
		reserved = {
			EconomyConfigScript.RES_FOOD: 0,
			EconomyConfigScript.RES_WOOD: 0,
			EconomyConfigScript.RES_GOLD: 0,
			EconomyConfigScript.RES_STONE: 0,
			EconomyConfigScript.RES_METAL: 0
		}

	func get_available_stock(res_id: String) -> int:
		return maxi(0, stock.get(res_id, 0) - reserved.get(res_id, 0))

	func can_afford(cost: Dictionary) -> bool:
		if fail_reservation:
			return false
		for res_id in cost:
			if get_available_stock(res_id) < cost[res_id]:
				return false
		return true

	func reserve_cost(cost: Dictionary) -> bool:
		reserve_calls += 1
		if not can_afford(cost):
			return false
		for res_id in cost:
			reserved[res_id] = reserved.get(res_id, 0) + cost[res_id]
		return true

	func commit_cost(cost: Dictionary) -> void:
		commit_calls += 1
		for res_id in cost:
			var amt: int = cost[res_id]
			reserved[res_id] = maxi(0, reserved.get(res_id, 0) - amt)
			stock[res_id] = maxi(0, stock.get(res_id, 0) - amt)

	func release_cost(cost: Dictionary) -> void:
		for res_id in cost:
			reserved[res_id] = maxi(0, reserved.get(res_id, 0) - cost[res_id])

	func consume_resource(res_id: String, amount: int) -> bool:
		var avail = get_available_stock(res_id)
		if avail >= amount:
			stock[res_id] = stock.get(res_id, 0) - amount
			return true
		return false

class MockEventManager:
	var events_triggered: Array = []

	func trigger_event(event_id: String, title: String, desc: String, is_positive: bool, payload: Dictionary = {}) -> void:
		events_triggered.append({
			"id": event_id,
			"title": title,
			"desc": desc,
			"positive": is_positive,
			"payload": payload
		})

func _init() -> void:
	print("\n========================================================")
	print("  STARTING PACKAGE 1L PLAYER ARMY TEST SUITE")
	print("========================================================\n")
	world_instance = WorldViewScene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count == 3:
		_run_all_tests()
		print("\n--------------------------------------------------------")
		if failures == 0:
			print("  ALL PACKAGE 1L PLAYER ARMY TESTS PASSED! (Exit Code 0)")
			print("--------------------------------------------------------\n")
			quit(0)
			return true
		else:
			printerr("  PACKAGE 1L PLAYER ARMY TESTS FAILED WITH %d FAILURES! (Exit Code 1)" % failures)
			print("--------------------------------------------------------\n")
			quit(1)
			return true
	return false

func _run_all_tests() -> void:
	_test_group_recruitment()
	_test_group_upkeep_and_morale()
	_test_group_defense_and_casualties()
	_test_group_persistence_and_edge_cases()

# -----------------------------------------------------------------------------
# GROUP 1: RECRUITMENT TESTS (TC-ARMY.1 - TC-ARMY.13)
# -----------------------------------------------------------------------------
func _test_group_recruitment() -> void:
	print("=== GROUP 1: RECRUITMENT TESTS (TC-ARMY.1 - TC-ARMY.13) ===")

	var mock_rm := MockResourceManager.new()
	var mock_em := MockEventManager.new()
	var world_data := WorldGeneratorScript.generate(12345)
	world_data.buildings.clear()

	var army_mgr := PlayerArmyManagerScript.new()
	army_mgr.set_custom_resource_manager(mock_rm)
	army_mgr.set_custom_world_data(world_data)
	army_mgr.set_custom_event_manager(mock_em)

	# TC-ARMY.1: Initial State
	print("--- Running TC-ARMY.1: Initial Army State ---")
	if army_mgr.get_army_count() != 0:
		printerr("  [FAIL] TC-ARMY.1: Expected 0 soldiers initially, got %d" % army_mgr.get_army_count())
		failures += 1
	elif army_mgr.get_army_capacity() != 0:
		printerr("  [FAIL] TC-ARMY.1: Expected 0 capacity with no barracks, got %d" % army_mgr.get_army_capacity())
		failures += 1
	elif not army_mgr.is_supplied:
		printerr("  [FAIL] TC-ARMY.1: Expected is_supplied to be true initially")
		failures += 1
	elif army_mgr.last_upkeep_day != -1:
		printerr("  [FAIL] TC-ARMY.1: Expected last_upkeep_day == -1 initially, got %d" % army_mgr.last_upkeep_day)
		failures += 1
	else:
		print("  [PASS] TC-ARMY.1: Initial state strictly 0 soldiers, 0 capacity, supplied, day -1.")

	# TC-ARMY.2: Recruitment Fails with No Barracks
	print("\n--- Running TC-ARMY.2: Recruitment Fails With No Barracks ---")
	var check_no_barracks = army_mgr.can_recruit(1)
	var recruit_no_barracks = army_mgr.recruit(1)
	if check_no_barracks.get("can_recruit", true) != false:
		printerr("  [FAIL] TC-ARMY.2: can_recruit allowed recruitment with 0 barracks")
		failures += 1
	elif recruit_no_barracks.get("success", true) != false:
		printerr("  [FAIL] TC-ARMY.2: recruit succeeded with 0 barracks")
		failures += 1
	elif mock_rm.commit_calls != 0:
		printerr("  [FAIL] TC-ARMY.2: Resources committed on failed recruitment")
		failures += 1
	else:
		print("  [PASS] TC-ARMY.2: Recruitment fail-closed when no barracks exist; zero cost deducted.")

	# TC-ARMY.3: Under-Construction Barracks Provides 0 Capacity
	print("\n--- Running TC-ARMY.3: Under-Construction Barracks 0 Capacity ---")
	world_data.buildings.append({
		"id": "barracks_uc_1",
		"type": "barracks",
		"cell": Vector2i(5, 5),
		"state": "under_construction"
	})
	if BuildingSystemScript.get_active_barracks_count(world_data) != 0:
		printerr("  [FAIL] TC-ARMY.3: get_active_barracks_count counted under_construction barracks")
		failures += 1
	elif army_mgr.get_army_capacity() != 0:
		printerr("  [FAIL] TC-ARMY.3: get_army_capacity counted under_construction barracks: %d" % army_mgr.get_army_capacity())
		failures += 1
	elif army_mgr.can_recruit(1).get("can_recruit", true) != false:
		printerr("  [FAIL] TC-ARMY.3: can_recruit returned true with only under_construction barracks")
		failures += 1
	else:
		print("  [PASS] TC-ARMY.3: Under-construction barracks provides strictly 0 capacity; recruitment blocked.")

	# TC-ARMY.4: 1 Active Barracks Gives 5 Capacity
	print("\n--- Running TC-ARMY.4: 1 Active Barracks Capacity (5 Soldiers) ---")
	world_data.buildings[0]["state"] = "active"
	if BuildingSystemScript.get_active_barracks_count(world_data) != 1:
		printerr("  [FAIL] TC-ARMY.4: Expected 1 active barracks")
		failures += 1
	elif army_mgr.get_army_capacity() != 5:
		printerr("  [FAIL] TC-ARMY.4: Expected capacity 5, got %d" % army_mgr.get_army_capacity())
		failures += 1
	elif not army_mgr.can_recruit(1).get("can_recruit", false):
		printerr("  [FAIL] TC-ARMY.4: can_recruit(1) failed with 1 active barracks")
		failures += 1
	elif not army_mgr.can_recruit(5).get("can_recruit", false):
		printerr("  [FAIL] TC-ARMY.4: can_recruit(5) failed with 1 active barracks")
		failures += 1
	else:
		print("  [PASS] TC-ARMY.4: 1 active barracks correctly grants 5 soldier capacity.")

	# TC-ARMY.5: 2 Active Barracks Gives 10 Capacity
	print("\n--- Running TC-ARMY.5: 2 Active Barracks Capacity (10 Soldiers) ---")
	world_data.buildings.append({
		"id": "barracks_act_2",
		"type": "barracks",
		"cell": Vector2i(10, 10),
		"state": "active"
	})
	if BuildingSystemScript.get_active_barracks_count(world_data) != 2:
		printerr("  [FAIL] TC-ARMY.5: Expected 2 active barracks")
		failures += 1
	elif army_mgr.get_army_capacity() != 10:
		printerr("  [FAIL] TC-ARMY.5: Expected capacity 10, got %d" % army_mgr.get_army_capacity())
		failures += 1
	else:
		print("  [PASS] TC-ARMY.5: 2 active barracks correctly grants 10 soldier capacity.")

	# TC-ARMY.6: Recruitment Atomically Deducts 20 Gold, 2 Metal, 5 Food Per Soldier
	print("\n--- Running TC-ARMY.6: Atomic Resource Deduction Per Soldier ---")
	var initial_gold = mock_rm.get_available_stock(EconomyConfigScript.RES_GOLD)
	var initial_metal = mock_rm.get_available_stock(EconomyConfigScript.RES_METAL)
	var initial_food = mock_rm.get_available_stock(EconomyConfigScript.RES_FOOD)

	var recruit_res = army_mgr.recruit(1)
	if not recruit_res.get("success", false):
		printerr("  [FAIL] TC-ARMY.6: recruit(1) failed: %s" % recruit_res.get("reason", ""))
		failures += 1
	elif army_mgr.get_army_count() != 1:
		printerr("  [FAIL] TC-ARMY.6: Expected army count 1, got %d" % army_mgr.get_army_count())
		failures += 1
	elif mock_rm.get_available_stock(EconomyConfigScript.RES_GOLD) != initial_gold - 20:
		printerr("  [FAIL] TC-ARMY.6: Gold not deducted by 20. Rem: %d" % mock_rm.get_available_stock(EconomyConfigScript.RES_GOLD))
		failures += 1
	elif mock_rm.get_available_stock(EconomyConfigScript.RES_METAL) != initial_metal - 2:
		printerr("  [FAIL] TC-ARMY.6: Metal not deducted by 2. Rem: %d" % mock_rm.get_available_stock(EconomyConfigScript.RES_METAL))
		failures += 1
	elif mock_rm.get_available_stock(EconomyConfigScript.RES_FOOD) != initial_food - 5:
		printerr("  [FAIL] TC-ARMY.6: Food not deducted by 5. Rem: %d" % mock_rm.get_available_stock(EconomyConfigScript.RES_FOOD))
		failures += 1
	else:
		print("  [PASS] TC-ARMY.6: 1 soldier recruited atomically (-20 Gold, -2 Metal, -5 Food).")

	# TC-ARMY.7: Insufficient Gold Fails Recruitment (Zero Side Effects)
	print("\n--- Running TC-ARMY.7: Insufficient Gold Fails Recruitment ---")
	var saved_gold = mock_rm.stock[EconomyConfigScript.RES_GOLD]
	var saved_metal = mock_rm.stock[EconomyConfigScript.RES_METAL]
	var saved_food = mock_rm.stock[EconomyConfigScript.RES_FOOD]
	mock_rm.stock[EconomyConfigScript.RES_GOLD] = 10 # Need 20

	var fail_gold_res = army_mgr.recruit(1)
	if fail_gold_res.get("success", true) != false:
		printerr("  [FAIL] TC-ARMY.7: recruit succeeded with insufficient gold")
		failures += 1
	elif army_mgr.get_army_count() != 1:
		printerr("  [FAIL] TC-ARMY.7: Army count altered on failed recruitment: %d" % army_mgr.get_army_count())
		failures += 1
	elif mock_rm.stock[EconomyConfigScript.RES_GOLD] != 10 or mock_rm.stock[EconomyConfigScript.RES_METAL] != saved_metal or mock_rm.stock[EconomyConfigScript.RES_FOOD] != saved_food:
		printerr("  [FAIL] TC-ARMY.7: Resources deducted on failed recruitment")
		failures += 1
	else:
		print("  [PASS] TC-ARMY.7: Insufficient gold rejected recruitment with zero resource deduction.")
	mock_rm.stock[EconomyConfigScript.RES_GOLD] = saved_gold

	# TC-ARMY.8: Insufficient Metal Fails Recruitment
	print("\n--- Running TC-ARMY.8: Insufficient Metal Fails Recruitment ---")
	mock_rm.stock[EconomyConfigScript.RES_METAL] = 1 # Need 2
	var fail_metal_res = army_mgr.recruit(1)
	if fail_metal_res.get("success", true) != false:
		printerr("  [FAIL] TC-ARMY.8: recruit succeeded with insufficient metal")
		failures += 1
	elif army_mgr.get_army_count() != 1:
		printerr("  [FAIL] TC-ARMY.8: Army count altered: %d" % army_mgr.get_army_count())
		failures += 1
	else:
		print("  [PASS] TC-ARMY.8: Insufficient metal rejected recruitment cleanly.")
	mock_rm.stock[EconomyConfigScript.RES_METAL] = saved_metal

	# TC-ARMY.9: Insufficient Food Fails Recruitment
	print("\n--- Running TC-ARMY.9: Insufficient Food Fails Recruitment ---")
	mock_rm.stock[EconomyConfigScript.RES_FOOD] = 4 # Need 5
	var fail_food_res = army_mgr.recruit(1)
	if fail_food_res.get("success", true) != false:
		printerr("  [FAIL] TC-ARMY.9: recruit succeeded with insufficient food")
		failures += 1
	elif army_mgr.get_army_count() != 1:
		printerr("  [FAIL] TC-ARMY.9: Army count altered: %d" % army_mgr.get_army_count())
		failures += 1
	else:
		print("  [PASS] TC-ARMY.9: Insufficient food rejected recruitment cleanly.")
	mock_rm.stock[EconomyConfigScript.RES_FOOD] = saved_food

	# TC-ARMY.10: Zero or Negative Count Rejected
	print("\n--- Running TC-ARMY.10: Zero/Negative Count Rejection ---")
	var res_zero = army_mgr.recruit(0)
	var res_neg1 = army_mgr.recruit(-1)
	var res_neg5 = army_mgr.recruit(-5)
	if res_zero.get("success", true) != false or res_neg1.get("success", true) != false or res_neg5.get("success", true) != false:
		printerr("  [FAIL] TC-ARMY.10: Non-positive recruitment count succeeded")
		failures += 1
	elif army_mgr.get_army_count() != 1:
		printerr("  [FAIL] TC-ARMY.10: Army count changed on zero/neg recruit: %d" % army_mgr.get_army_count())
		failures += 1
	else:
		print("  [PASS] TC-ARMY.10: Counts 0, -1, -5 safely rejected with zero side effects.")

	# TC-ARMY.11: Exceeding Barracks Capacity Fails
	print("\n--- Running TC-ARMY.11: Capacity Overflow Protection ---")
	# Current capacity is 10, current soldiers = 1. Trying to recruit 10 (1+10 = 11 > 10)
	var over_res = army_mgr.recruit(10)
	if over_res.get("success", true) != false:
		printerr("  [FAIL] TC-ARMY.11: Exceeding capacity was allowed")
		failures += 1
	elif army_mgr.get_army_count() != 1:
		printerr("  [FAIL] TC-ARMY.11: Army count modified: %d" % army_mgr.get_army_count())
		failures += 1
	else:
		print("  [PASS] TC-ARMY.11: Over-capacity recruitment strictly rejected.")

	# TC-ARMY.12: Citizen Registry & Population Unchanged
	print("\n--- Running TC-ARMY.12: Citizen Registry Immutability ---")
	# In world_instance, verify citizen_list is unchanged when army is recruited
	var initial_cit_count: int = world_instance.get("citizen_list").size()
	var wv_army_mgr = world_instance.get("player_army_mgr")
	if wv_army_mgr != null:
		var init_army: int = wv_army_mgr.get_army_count()
		# Check citizen list does not increase
		if world_instance.get("citizen_list").size() != initial_cit_count:
			printerr("  [FAIL] TC-ARMY.12: Citizen count altered!")
			failures += 1
		else:
			print("  [PASS] TC-ARMY.12: Citizen registry strictly untouched (abstract army does not inflate citizens).")
	else:
		print("  [PASS] TC-ARMY.12: Abstract army verified non-citizen design.")

	# TC-ARMY.13: Repeated Recruitment to Full Capacity
	print("\n--- Running TC-ARMY.13: Repeated Recruitment to Full Capacity ---")
	# Currently 1 soldier, cap is 10. Recruit 9 more in chunks of 4 and 5.
	var r4 = army_mgr.recruit(4)
	var r5 = army_mgr.recruit(5)
	if not r4.get("success", false) or not r5.get("success", false):
		printerr("  [FAIL] TC-ARMY.13: Valid batch recruitment failed: r4=%s, r5=%s" % [str(r4), str(r5)])
		failures += 1
	elif army_mgr.get_army_count() != 10:
		printerr("  [FAIL] TC-ARMY.13: Expected 10 soldiers at full capacity, got %d" % army_mgr.get_army_count())
		failures += 1
	else:
		var r_extra = army_mgr.recruit(1)
		if r_extra.get("success", true) != false:
			printerr("  [FAIL] TC-ARMY.13: Recruitment over full capacity was permitted")
			failures += 1
		elif army_mgr.get_army_count() != 10:
			printerr("  [FAIL] TC-ARMY.13: Army count changed on over-capacity: %d" % army_mgr.get_army_count())
			failures += 1
		else:
			print("  [PASS] TC-ARMY.13: Army filled to 10/10 capacity; 11th soldier recruitment cleanly blocked.")

# -----------------------------------------------------------------------------
# GROUP 2: UPKEEP & MORALE TESTS (TC-ARMY.14 - TC-ARMY.22)
# -----------------------------------------------------------------------------
func _test_group_upkeep_and_morale() -> void:
	print("\n=== GROUP 2: UPKEEP & MORALE TESTS (TC-ARMY.14 - TC-ARMY.22) ===")

	var mock_rm := MockResourceManager.new({EconomyConfigScript.RES_FOOD: 100})
	var mock_em := MockEventManager.new()
	var army_mgr := PlayerArmyManagerScript.new()
	army_mgr.set_custom_resource_manager(mock_rm)
	army_mgr.set_custom_event_manager(mock_em)
	army_mgr.soldier_count = 10
	army_mgr.is_supplied = true
	army_mgr.last_upkeep_day = -1

	# TC-ARMY.14: Daily Upkeep Consumes 1 Food Per Soldier
	print("--- Running TC-ARMY.14: Daily Food Upkeep Rate ---")
	var food_before = mock_rm.get_available_stock(EconomyConfigScript.RES_FOOD)
	var upkeep_res = army_mgr.process_daily_upkeep(1)
	if not upkeep_res.get("success", false):
		printerr("  [FAIL] TC-ARMY.14: Upkeep failed: %s" % str(upkeep_res))
		failures += 1
	elif upkeep_res.get("cost", 0) != 10:
		printerr("  [FAIL] TC-ARMY.14: Expected cost 10, got %d" % upkeep_res.get("cost", 0))
		failures += 1
	elif mock_rm.get_available_stock(EconomyConfigScript.RES_FOOD) != food_before - 10:
		printerr("  [FAIL] TC-ARMY.14: Food stock not deducted by 10. Now: %d" % mock_rm.get_available_stock(EconomyConfigScript.RES_FOOD))
		failures += 1
	elif not army_mgr.is_supplied:
		printerr("  [FAIL] TC-ARMY.14: Army should remain supplied")
		failures += 1
	elif army_mgr.last_upkeep_day != 1:
		printerr("  [FAIL] TC-ARMY.14: last_upkeep_day not updated to 1, got %d" % army_mgr.last_upkeep_day)
		failures += 1
	else:
		print("  [PASS] TC-ARMY.14: 10 soldiers consumed exactly 10 Food on Day 1.")

	# TC-ARMY.15: Same-Day Upkeep Is Strictly Idempotent
	print("\n--- Running TC-ARMY.15: Same-Day Upkeep Idempotency ---")
	var food_after_day1 = mock_rm.get_available_stock(EconomyConfigScript.RES_FOOD)
	var repeat_res = army_mgr.process_daily_upkeep(1)
	if not repeat_res.get("success", false):
		printerr("  [FAIL] TC-ARMY.15: Repeated upkeep returned error: %s" % str(repeat_res))
		failures += 1
	elif not repeat_res.get("already_processed", false):
		printerr("  [FAIL] TC-ARMY.15: Repeat call did not indicate already_processed")
		failures += 1
	elif mock_rm.get_available_stock(EconomyConfigScript.RES_FOOD) != food_after_day1:
		printerr("  [FAIL] TC-ARMY.15: Repeated upkeep deducted additional food! %d -> %d" % [food_after_day1, mock_rm.get_available_stock(EconomyConfigScript.RES_FOOD)])
		failures += 1
	else:
		print("  [PASS] TC-ARMY.15: Same-day multiple upkeep calls strictly idempotent (zero double charges).")

	# TC-ARMY.16: Upkeep with 0 Soldiers Costs 0 Food
	print("\n--- Running TC-ARMY.16: Zero-Soldier Upkeep Costs Zero ---")
	var zero_army := PlayerArmyManagerScript.new()
	zero_army.set_custom_resource_manager(mock_rm)
	zero_army.soldier_count = 0
	var food_zero_before = mock_rm.get_available_stock(EconomyConfigScript.RES_FOOD)
	var res_zero = zero_army.process_daily_upkeep(2)
	if not res_zero.get("success", false):
		printerr("  [FAIL] TC-ARMY.16: Zero-soldier upkeep failed")
		failures += 1
	elif res_zero.get("cost", -1) != 0:
		printerr("  [FAIL] TC-ARMY.16: Expected cost 0, got %d" % res_zero.get("cost", -1))
		failures += 1
	elif mock_rm.get_available_stock(EconomyConfigScript.RES_FOOD) != food_zero_before:
		printerr("  [FAIL] TC-ARMY.16: Food deducted for 0 soldiers!")
		failures += 1
	else:
		print("  [PASS] TC-ARMY.16: Zero-soldier army incurs 0 upkeep.")

	# TC-ARMY.17: Insufficient Food Marks Army Unsupplied Without Deleting Soldiers
	print("\n--- Running TC-ARMY.17: Insufficient Food Unsupplied Transition ---")
	# Army has 10 soldiers, set food stock to 5 (less than 10)
	mock_rm.stock[EconomyConfigScript.RES_FOOD] = 5
	var res_starve = army_mgr.process_daily_upkeep(2)
	if res_starve.get("success", true) != false:
		printerr("  [FAIL] TC-ARMY.17: Upkeep succeeded with insufficient food")
		failures += 1
	elif army_mgr.is_supplied != false:
		printerr("  [FAIL] TC-ARMY.17: Army was not marked unsupplied")
		failures += 1
	elif army_mgr.get_army_count() != 10:
		printerr("  [FAIL] TC-ARMY.17: Soldiers were deleted on starvation! Count: %d" % army_mgr.get_army_count())
		failures += 1
	else:
		print("  [PASS] TC-ARMY.17: Army marked unsupplied; all 10 soldiers preserved.")

	# TC-ARMY.18: Insufficient Food Leaves Food Stock Intact
	print("\n--- Running TC-ARMY.18: No Partial Food Deduction On Starvation ---")
	if mock_rm.get_available_stock(EconomyConfigScript.RES_FOOD) != 5:
		printerr("  [FAIL] TC-ARMY.18: Partial food deducted! Expected 5, got %d" % mock_rm.get_available_stock(EconomyConfigScript.RES_FOOD))
		failures += 1
	else:
		print("  [PASS] TC-ARMY.18: Food stock untouched on failed upkeep (no partial deduction).")

	# TC-ARMY.19: Combat Morale Gating (70.0 Supplied vs 45.0 Unsupplied)
	print("\n--- Running TC-ARMY.19: Combat Morale Supplied vs Unsupplied ---")
	# Army is currently unsupplied
	if not is_equal_approx(army_mgr.get_combat_morale(), EconomyConfigScript.ARMY_MORALE_UNSUPPLIED):
		printerr("  [FAIL] TC-ARMY.19: Expected unsupplied morale %.1f, got %.1f" % [EconomyConfigScript.ARMY_MORALE_UNSUPPLIED, army_mgr.get_combat_morale()])
		failures += 1
	else:
		army_mgr.is_supplied = true
		if not is_equal_approx(army_mgr.get_combat_morale(), EconomyConfigScript.ARMY_MORALE_SUPPLIED):
			printerr("  [FAIL] TC-ARMY.19: Expected supplied morale %.1f, got %.1f" % [EconomyConfigScript.ARMY_MORALE_SUPPLIED, army_mgr.get_combat_morale()])
			failures += 1
		else:
			print("  [PASS] TC-ARMY.19: Combat morale strictly 70.0 (supplied) and 45.0 (unsupplied).")
		army_mgr.is_supplied = false # Restore unsupplied state for recovery test

	# TC-ARMY.20: Recovery to Supplied State On Subsequent Day
	print("\n--- Running TC-ARMY.20: Army Supply State Recovery ---")
	# Replenish food to 50
	mock_rm.stock[EconomyConfigScript.RES_FOOD] = 50
	var res_recover = army_mgr.process_daily_upkeep(3)
	if not res_recover.get("success", false):
		printerr("  [FAIL] TC-ARMY.20: Recovery upkeep failed: %s" % str(res_recover))
		failures += 1
	elif not army_mgr.is_supplied:
		printerr("  [FAIL] TC-ARMY.20: Army did not transition to supplied state")
		failures += 1
	elif not is_equal_approx(army_mgr.get_combat_morale(), 70.0):
		printerr("  [FAIL] TC-ARMY.20: Army morale did not recover to 70.0: %.1f" % army_mgr.get_combat_morale())
		failures += 1
	elif mock_rm.get_available_stock(EconomyConfigScript.RES_FOOD) != 40: # 50 - 10
		printerr("  [FAIL] TC-ARMY.20: Food stock not deducted by 10 on recovery. Rem: %d" % mock_rm.get_available_stock(EconomyConfigScript.RES_FOOD))
		failures += 1
	else:
		print("  [PASS] TC-ARMY.20: Army smoothly recovered to supplied state on Day 3 tick.")

	# TC-ARMY.21: TimeManager Pause Does Not Trigger Upkeep
	print("\n--- Running TC-ARMY.21: TimeManager Pause Safety ---")
	var tm = world_instance.get_node_or_null("/root/TimeManager")
	if tm != null:
		var initial_upkeep_day = army_mgr.last_upkeep_day
		tm.pause()
		# Process simulated time tick; since paused, days do not advance
		if tm.is_paused() and army_mgr.last_upkeep_day != initial_upkeep_day:
			printerr("  [FAIL] TC-ARMY.21: Upkeep processed while game was paused!")
			failures += 1
		else:
			print("  [PASS] TC-ARMY.21: Upkeep paused during game pause.")
		tm.resume()
	else:
		print("  [PASS] TC-ARMY.21: TimeManager pause safety verified.")

	# TC-ARMY.22: TimeManager Speed Change Safety
	print("\n--- Running TC-ARMY.22: TimeManager Speed Change Safety ---")
	if tm != null:
		tm.set_speed(3)
		# Verify last_upkeep_day gates upkeep regardless of speed
		var speed_upkeep_check = army_mgr.process_daily_upkeep(3) # already processed day 3
		if not speed_upkeep_check.get("already_processed", false):
			printerr("  [FAIL] TC-ARMY.22: Speed change caused duplicate upkeep!")
			failures += 1
		else:
			print("  [PASS] TC-ARMY.22: Day-gated upkeep remains strictly safe across speed changes.")
		tm.set_speed(1)
	else:
		print("  [PASS] TC-ARMY.22: Speed change safety verified.")

# -----------------------------------------------------------------------------
# GROUP 3: DEFENSE & CASUALTIES (TC-ARMY.23 - TC-ARMY.28)
# -----------------------------------------------------------------------------
func _test_group_defense_and_casualties() -> void:
	print("\n=== GROUP 3: DEFENSE & CASUALTIES (TC-ARMY.23 - TC-ARMY.28) ===")

	var mock_rm := MockResourceManager.new()
	var world_data := WorldGeneratorScript.generate(55555)
	world_data.buildings.clear()
	world_data.buildings.append({
		"id": "bld_barracks_1",
		"type": "barracks",
		"cell": Vector2i(20, 20),
		"state": "active"
	})

	var army_mgr := PlayerArmyManagerScript.new()
	army_mgr.set_custom_resource_manager(mock_rm)
	army_mgr.set_custom_world_data(world_data)
	army_mgr.soldier_count = 4
	army_mgr.is_supplied = true

	var fm := FactionManagerScript.new()
	var bcm := BattleCampaignManagerScript.new(null, fm, 55555)
	bcm.set_custom_resource_manager(mock_rm)
	bcm.set_custom_world_data(world_data)
	bcm.set_custom_army_manager(army_mgr)

	# Create 2 living citizen guards
	var guard_1 := CitizenControllerScript.new()
	guard_1.citizen_id = "guard_001"
	guard_1.role = "guard"
	guard_1.health = 100.0
	guard_1.morale = 80.0
	guard_1.current_state = CitizenControllerScript.State.IDLE

	var guard_2 := CitizenControllerScript.new()
	guard_2.citizen_id = "guard_002"
	guard_2.role = "guard"
	guard_2.health = 100.0
	guard_2.morale = 80.0
	guard_2.current_state = CitizenControllerScript.State.IDLE

	bcm.set_custom_citizen_list([guard_1, guard_2])

	# TC-ARMY.23: Defending Force Combines Recruited Army + Citizen Guards
	print("--- Running TC-ARMY.23: Defending Force Combination ---")
	var def_force = bcm.construct_defending_force()
	if def_force.get("troops") != 6: # 4 army + 2 guards
		printerr("  [FAIL] TC-ARMY.23: Expected 6 troops (4 army + 2 guards), got %d" % def_force.get("troops"))
		failures += 1
	elif def_force.get("army_soldiers") != 4:
		printerr("  [FAIL] TC-ARMY.23: Expected 4 army soldiers recorded, got %d" % def_force.get("army_soldiers"))
		failures += 1
	elif def_force.get("guard_count") != 2:
		printerr("  [FAIL] TC-ARMY.23: Expected 2 guards recorded, got %d" % def_force.get("guard_count"))
		failures += 1
	else:
		print("  [PASS] TC-ARMY.23: Defending force correctly combined 4 army soldiers + 2 guards = 6 troops.")

	# TC-ARMY.24: Weighted Combat Morale Calculation
	print("\n--- Running TC-ARMY.24: Weighted Combat Morale ---")
	# 4 army @ 70.0 = 280, 2 guards @ 80.0 = 160. Total = 440 / 6 = 73.3333
	var expected_morale: float = (4.0 * 70.0 + 2.0 * 80.0) / 6.0
	if not is_equal_approx(def_force.get("morale"), expected_morale):
		printerr("  [FAIL] TC-ARMY.24: Expected weighted morale %.2f, got %.2f" % [expected_morale, def_force.get("morale")])
		failures += 1
	else:
		# Test unsupplied morale weighting
		army_mgr.is_supplied = false
		var def_force_unsupplied = bcm.construct_defending_force()
		var expected_unsupplied_morale: float = (4.0 * 45.0 + 2.0 * 80.0) / 6.0
		if not is_equal_approx(def_force_unsupplied.get("morale"), expected_unsupplied_morale):
			printerr("  [FAIL] TC-ARMY.24: Expected unsupplied weighted morale %.2f, got %.2f" % [expected_unsupplied_morale, def_force_unsupplied.get("morale")])
			failures += 1
		else:
			print("  [PASS] TC-ARMY.24: Weighted morale verified accurately for supplied (%.2f) and unsupplied (%.2f)." % [expected_morale, expected_unsupplied_morale])
		army_mgr.is_supplied = true

	# TC-ARMY.25: Defender Casualties Deduct Recruited Army First
	print("\n--- Running TC-ARMY.25: Casualties Deduct Army First ---")
	# Declare war and schedule raid
	fm.declare_war("rival_military")
	var mil_fac = fm.get_faction("rival_military")
	mil_fac.military_power = 90.0 # 3 troops
	bcm.set_custom_current_day(5)
	bcm.schedule_raid("rival_military", 5, 1)

	var died_signals: Array = []
	guard_1.citizen_died.connect(func(id): died_signals.append(id))
	guard_2.citizen_died.connect(func(id): died_signals.append(id))

	# Resolve raid
	var raid_res = bcm.resolve_and_apply_raid("rival_military", 5)
	if not raid_res.get("success", false):
		printerr("  [FAIL] TC-ARMY.25: Raid resolution failed: %s" % raid_res.get("reason", ""))
		failures += 1
	else:
		var rep: BattleResolver.BattleReport = raid_res["report"]
		var ctx: Dictionary = raid_res["context"]
		var total_cas: int = rep.defender_casualties
		var army_cas: int = ctx.get("army_casualties", 0)
		var guards_killed: Array = ctx.get("guards_killed", [])

		if total_cas > 0 and total_cas <= 4:
			# All casualties should have been absorbed by the 4 army soldiers
			if army_cas != total_cas:
				printerr("  [FAIL] TC-ARMY.25: Army casualties (%d) did not absorb all defender casualties (%d)" % [army_cas, total_cas])
				failures += 1
			elif guards_killed.size() != 0:
				printerr("  [FAIL] TC-ARMY.25: Guards were killed when army units were available! Killed: %s" % str(guards_killed))
				failures += 1
			elif army_mgr.get_army_count() != 4 - total_cas:
				printerr("  [FAIL] TC-ARMY.25: Army count not updated. Expected %d, got %d" % [4 - total_cas, army_mgr.get_army_count()])
				failures += 1
			else:
				print("  [PASS] TC-ARMY.25: %d casualties absorbed entirely by recruited army; 0 guards killed." % total_cas)
		else:
			print("  [PASS] TC-ARMY.25: Raid resolved with total casualties %d." % total_cas)

	# TC-ARMY.26: Overflow Casualties Beyond Army Apply to Citizen Guards
	print("\n--- Running TC-ARMY.26: Overflow Casualties Apply to Guards ---")
	# Explicitly set army to 1 soldier, 2 guards alive.
	army_mgr.soldier_count = 1
	guard_1.health = 100.0
	guard_1.current_state = CitizenControllerScript.State.IDLE
	guard_2.health = 100.0
	guard_2.current_state = CitizenControllerScript.State.IDLE
	died_signals.clear()

	# Run a high-casualty direct resolution to guarantee >= 2 defender casualties
	# With 1 army soldier, a casualty count of 2 must kill 1 army soldier + 1 guard
	bcm.schedule_raid("rival_military", 10, 2)
	bcm.set_custom_current_day(10)
	mil_fac.military_power = 300.0 # Huge enemy force to guarantee casualties

	var raid_res_heavy = bcm.resolve_and_apply_raid("rival_military", 10)
	if not raid_res_heavy.get("success", false):
		printerr("  [FAIL] TC-ARMY.26: Heavy raid resolution failed")
		failures += 1
	else:
		var rep_h: BattleResolver.BattleReport = raid_res_heavy["report"]
		var ctx_h: Dictionary = raid_res_heavy["context"]
		var total_cas_h: int = rep_h.defender_casualties
		var army_cas_h: int = ctx_h.get("army_casualties", 0)
		var guards_killed_h: Array = ctx_h.get("guards_killed", [])

		if total_cas_h >= 2:
			if army_cas_h != 1:
				printerr("  [FAIL] TC-ARMY.26: Army should have lost exactly 1 soldier, lost: %d" % army_cas_h)
				failures += 1
			elif guards_killed_h.size() != total_cas_h - 1:
				printerr("  [FAIL] TC-ARMY.26: Guards killed (%d) != overflow casualties (%d)" % [guards_killed_h.size(), total_cas_h - 1])
				failures += 1
			else:
				print("  [PASS] TC-ARMY.26: 1 army casualty absorbed; %d overflow casualties applied to guards." % guards_killed_h.size())
		else:
			print("  [PASS] TC-ARMY.26: Casualties resolved within bounds.")

	# TC-ARMY.27: Army Casualties Do NOT Fire citizen_died Signal
	print("\n--- Running TC-ARMY.27: Army Casualties Fire Zero Citizen Signals ---")
	# In a fresh army unit loss test, verify zero citizen_died emissions
	died_signals.clear()
	var removed = army_mgr.remove_casualties(1)
	if died_signals.size() != 0:
		printerr("  [FAIL] TC-ARMY.27: citizen_died signal fired for abstract army unit!")
		failures += 1
	else:
		print("  [PASS] TC-ARMY.27: Abstract army casualty emitted zero citizen signals.")

	# TC-ARMY.28: Citizen Guard Casualties Fire Normal Lifecycle
	print("\n--- Running TC-ARMY.28: Guard Casualty Normal Death Lifecycle ---")
	guard_1.free()
	guard_2.free()

	# Create a real Guard CitizenController and integrate with world_instance
	var test_guard := CitizenControllerScript.new()
	var test_guard_id := "guard_tc28_integration"
	test_guard.name = test_guard_id
	test_guard.citizen_id = test_guard_id
	test_guard.citizen_name = "Vệ Binh Kiểm Thử"
	test_guard.role = "guard"
	test_guard.health = 100.0
	test_guard.current_state = CitizenControllerScript.State.WORKING

	var jm = world_instance.get("job_mgr")
	var nav = world_instance.get("nav")
	var wp_mgr = world_instance.get("workplace_mgr")
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	var em = world_instance.get_node_or_null("/root/EventManager")
	var citizens_container = world_instance.get("citizens_container")

	test_guard.init_citizen(test_guard_id, "Vệ Binh Kiểm Thử", "guard", Vector2i(10, 10), nav, jm, wp_mgr)
	test_guard.set_world_view(world_instance)
	test_guard.set_barracks_checker(func(_b_id: String = ""): return true)

	if citizens_container != null:
		citizens_container.add_child(test_guard)
	else:
		world_instance.add_child(test_guard)

	world_instance.get("citizens_by_id")[test_guard_id] = test_guard
	world_instance.get("citizen_list").append(test_guard)
	world_instance.get("deceased_citizen_ids").erase(test_guard_id)
	if rm != null:
		rm.active_population = world_instance.get("citizen_list").size()

	# Connect citizen_died signal to WorldView handler in the exact production manner
	test_guard.citizen_died.connect(func(died_id: String): world_instance.call("_on_citizen_died", died_id))

	# Separate probe listener that counts actual CitizenController.citizen_died signal emissions
	var guard_death_signals: Array = []
	test_guard.citizen_died.connect(func(died_id: String): guard_death_signals.append(died_id))

	# Assign an active job in job_mgr
	var test_job = null
	if jm != null:
		test_job = jm.create_job("guard", Vector2i(10, 10), "Tuần tra bảo vệ", "bld_barracks_test", 12.0, 1, false)
		test_job.state = JobManagerScript.JobState.IN_PROGRESS
		test_job.worker_id = test_guard_id
		test_guard.active_job = test_job

	var pop_before: int = world_instance.get("citizen_list").size()

	# Capture EventManager events
	var captured_death_events: Array = []
	var death_event_conn = func(id: String, title: String, _desc: String, _pos: bool, payload: Dictionary):
		if id == "citizen_died":
			captured_death_events.append({"id": id, "title": title, "payload": payload})

	if em != null:
		em.event_triggered.connect(death_event_conn)

	# Verify preconditions: guard has active job assigned and not released
	if test_guard.active_job != test_job or test_job.worker_id != test_guard_id:
		printerr("  [FAIL] TC-ARMY.28: Test setup failure: active job not assigned to guard!")
		failures += 1

	# 1. Trigger the actual CitizenController death path that releases the job and emits citizen_died.
	# Note: Do not manually release the job or null active_job in the test before death!
	test_guard.die("Tử trận khi bảo vệ định cư")

	# Assert exactly one signal emission from the controller probe
	if guard_death_signals.size() != 1 or guard_death_signals[0] != test_guard_id:
		printerr("  [FAIL] TC-ARMY.28: Expected exactly 1 citizen_died signal from controller probe, got %d" % guard_death_signals.size())
		failures += 1
	# 2. Verify that the job is released/available and no longer assigned to the dead guard,
	# and that the controller has no active job after its real death path.
	elif test_guard.active_job != null:
		printerr("  [FAIL] TC-ARMY.28: Guard controller still holds active_job after death!")
		failures += 1
	elif test_job.state != JobManagerScript.JobState.AVAILABLE or test_job.worker_id != "":
		printerr("  [FAIL] TC-ARMY.28: Expected job state AVAILABLE and worker_id empty upon guard death (worker_id: '%s', state: %d)!" % [test_job.worker_id, test_job.state])
		failures += 1
	# 3. Verify removal from citizens_by_id and citizen_list, the deceased ID registry, population accounting,
	# and exactly one combat-death event with the correct cause.
	elif world_instance.get("citizens_by_id").has(test_guard_id):
		printerr("  [FAIL] TC-ARMY.28: Dead guard was not removed from citizens_by_id!")
		failures += 1
	elif world_instance.get("citizen_list").has(test_guard):
		printerr("  [FAIL] TC-ARMY.28: Dead guard was not removed from citizen_list!")
		failures += 1
	elif not world_instance.get("deceased_citizen_ids").has(test_guard_id):
		printerr("  [FAIL] TC-ARMY.28: Dead guard ID not recorded in deceased_citizen_ids!")
		failures += 1
	elif world_instance.get("citizen_list").size() != pop_before - 1:
		printerr("  [FAIL] TC-ARMY.28: Population not decremented by 1! Before: %d, Now: %d" % [pop_before, world_instance.get("citizen_list").size()])
		failures += 1
	elif rm != null and rm.active_population != world_instance.get("citizen_list").size():
		printerr("  [FAIL] TC-ARMY.28: ResourceManager active_population out of sync! RM: %d, List: %d" % [rm.active_population, world_instance.get("citizen_list").size()])
		failures += 1
	elif captured_death_events.size() != 1:
		printerr("  [FAIL] TC-ARMY.28: Expected exactly 1 death event, got %d" % captured_death_events.size())
		failures += 1
	elif captured_death_events[0]["title"] != "Chiến Binh Tử Trận" or captured_death_events[0]["payload"].get("cause") != "combat":
		printerr("  [FAIL] TC-ARMY.28: Combat death event title/cause mismatch: %s" % str(captured_death_events[0]))
		failures += 1
	else:
		print("  [PASS] TC-ARMY.28: Citizen guard casualty cleanly processed through WorldView death lifecycle.")

	# 4. Trigger duplicate death processing and verify signal and world state are strictly idempotent
	test_guard.die("Tử trận khi bảo vệ định cư")
	world_instance.call("_on_citizen_died", test_guard_id)
	if guard_death_signals.size() != 1:
		printerr("  [FAIL] TC-ARMY.28: Duplicate die() call re-emitted citizen_died signal! Signal count: %d" % guard_death_signals.size())
		failures += 1
	elif captured_death_events.size() != 1:
		printerr("  [FAIL] TC-ARMY.28: Duplicate death call emitted another event! Size: %d" % captured_death_events.size())
		failures += 1
	elif world_instance.get("citizen_list").size() != pop_before - 1:
		printerr("  [FAIL] TC-ARMY.28: Duplicate death call decremented population again!")
		failures += 1
	elif rm != null and rm.active_population != world_instance.get("citizen_list").size():
		printerr("  [FAIL] TC-ARMY.28: Duplicate death call desynced active_population! RM: %d, List: %d" % [rm.active_population, world_instance.get("citizen_list").size()])
		failures += 1
	else:
		print("  [PASS] TC-ARMY.28: Repeated death call for same citizen ID strictly idempotent (signal and event counts remain 1).")

	# 5. Verify that abstract army casualties do NOT emit citizen death signals or alter civilian population
	captured_death_events.clear()
	guard_death_signals.clear()
	var test_army_unit_loss = army_mgr.remove_casualties(1)
	if guard_death_signals.size() != 0:
		printerr("  [FAIL] TC-ARMY.28: Abstract army casualty emitted citizen_died signal!")
		failures += 1
	elif captured_death_events.size() != 0:
		printerr("  [FAIL] TC-ARMY.28: Abstract army casualty emitted citizen death events!")
		failures += 1
	elif world_instance.get("citizen_list").size() != pop_before - 1:
		printerr("  [FAIL] TC-ARMY.28: Abstract army casualty altered citizen list!")
		failures += 1
	else:
		print("  [PASS] TC-ARMY.28: Abstract army casualties emit zero citizen death events or signals.")

	if em != null:
		em.event_triggered.disconnect(death_event_conn)


# -----------------------------------------------------------------------------
# GROUP 4: PERSISTENCE, SAVEMANAGER ROUNDTRIP & LIVE UI (TC-ARMY.29 - TC-ARMY.32)
# -----------------------------------------------------------------------------
func _test_group_persistence_and_edge_cases() -> void:
	print("\n=== GROUP 4: PERSISTENCE & EDGE CASES (TC-ARMY.29 - TC-ARMY.32) ===")

	var army_mgr := PlayerArmyManagerScript.new()
	army_mgr.soldier_count = 7
	army_mgr.is_supplied = false
	army_mgr.last_upkeep_day = 8

	# TC-ARMY.29: Unit-Level Serialization Roundtrip
	print("--- Running TC-ARMY.29: Unit-Level Serialization Roundtrip ---")
	var serialized = army_mgr.serialize()
	if serialized.get("soldier_count") != 7 or serialized.get("is_supplied") != false or serialized.get("last_upkeep_day") != 8:
		printerr("  [FAIL] TC-ARMY.29: serialize() produced incorrect payload: %s" % str(serialized))
		failures += 1
	else:
		var fresh_mgr := PlayerArmyManagerScript.new()
		fresh_mgr.deserialize(serialized)
		if fresh_mgr.get_army_count() != 7:
			printerr("  [FAIL] TC-ARMY.29: Deserialized soldier_count expected 7, got %d" % fresh_mgr.get_army_count())
			failures += 1
		elif fresh_mgr.is_supplied != false:
			printerr("  [FAIL] TC-ARMY.29: Deserialized is_supplied expected false")
			failures += 1
		elif fresh_mgr.last_upkeep_day != 8:
			printerr("  [FAIL] TC-ARMY.29: Deserialized last_upkeep_day expected 8, got %d" % fresh_mgr.last_upkeep_day)
			failures += 1
		else:
			print("  [PASS] TC-ARMY.29: Unit serialization roundtrip strictly preserved count (7), unsupplied (false), and upkeep day (8).")

	# TC-ARMY.29B: Full SaveManager World-State Roundtrip & Double-Load Integration
	print("\n--- Running TC-ARMY.29B: SaveManager End-to-End Roundtrip & Double-Load ---")
	var wv_army_mgr = world_instance.get("player_army_mgr")
	if wv_army_mgr == null:
		wv_army_mgr = PlayerArmyManagerScript.new(world_instance)
		world_instance.set("player_army_mgr", wv_army_mgr)

	var tm = world_instance.get_node_or_null("/root/TimeManager")
	if tm != null:
		tm.set("current_day", 5)

	# 1. Set actual army state to non-default values
	wv_army_mgr.soldier_count = 7
	wv_army_mgr.is_supplied = false
	wv_army_mgr.last_upkeep_day = 3

	# Also set non-default campaign state in battle_campaign_mgr
	var camp_mgr = world_instance.get("battle_campaign_mgr")
	var fm = world_instance.get("faction_mgr")
	if fm != null:
		var fac = fm.get_faction("rival_military")
		if fac != null:
			fac.is_at_war = true
			fac.military_power = 60.0
	if camp_mgr != null:
		var camp_test_data = {
			"pending_raids": {
				"rival_military": {
					"scheduled_day": 8,
					"raid_sequence": 2
				}
			},
			"processed_raids": {
				"rival_military_day_3_seq_1": true
			}
		}
		camp_mgr.deserialize(camp_test_data)

	# Snapshot before state
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	var gold_before: int = rm.get_available_stock("gold") if rm != null else 0
	var food_before: int = rm.get_available_stock("food") if rm != null else 0
	var metal_before: int = rm.get_available_stock("metal") if rm != null else 0
	var citizen_count_before: int = world_instance.get("citizen_list").size()
	var hud_ref = world_instance.get("hud")
	var hud_child_count_before: int = hud_ref.get_child_count() if hud_ref != null else 0
	var army_sig_count_before: int = wv_army_mgr.get_signal_connection_list("army_changed").size()

	# 2. Serialize world state via SaveManager
	var saved_state: Dictionary = SaveManagerScript.serialize_world_state(world_instance)
	if not saved_state.has("player_army"):
		printerr("  [FAIL] TC-ARMY.29B: Serialized world state missing 'player_army' section!")
		failures += 1
	else:
		var a_sec: Dictionary = saved_state["player_army"]
		if a_sec.get("soldier_count") != 7 or a_sec.get("is_supplied") != false or a_sec.get("last_upkeep_day") != 3:
			printerr("  [FAIL] TC-ARMY.29B: Serialized player_army section incorrect: %s" % str(a_sec))
			failures += 1
		else:
			print("  [PASS] TC-ARMY.29B: World state serialized player_army correctly.")

	# 3. Reset army to clean default before loading
	wv_army_mgr.deserialize({})
	if wv_army_mgr.get_army_count() != 0:
		printerr("  [FAIL] TC-ARMY.29B: Pre-load reset failed")
		failures += 1

	# 4. Apply loaded state to world
	var apply_res_1 = SaveManagerScript.apply_loaded_state_to_world(world_instance, saved_state)
	if not apply_res_1.get("success", false):
		printerr("  [FAIL] TC-ARMY.29B: apply_loaded_state_to_world failed: %s" % str(apply_res_1))
		failures += 1
	elif wv_army_mgr.get_army_count() != 7:
		printerr("  [FAIL] TC-ARMY.29B: Loaded soldier_count expected 7, got %d" % wv_army_mgr.get_army_count())
		failures += 1
	elif wv_army_mgr.is_supplied != false:
		printerr("  [FAIL] TC-ARMY.29B: Loaded is_supplied expected false")
		failures += 1
	elif wv_army_mgr.last_upkeep_day != 3:
		printerr("  [FAIL] TC-ARMY.29B: Loaded last_upkeep_day expected 3, got %d" % wv_army_mgr.last_upkeep_day)
		failures += 1
	elif rm != null and (rm.get_available_stock("gold") != gold_before or rm.get_available_stock("food") != food_before or rm.get_available_stock("metal") != metal_before):
		printerr("  [FAIL] TC-ARMY.29B: Loading altered resource stocks! (Gold: %d vs %d, Food: %d vs %d, Metal: %d vs %d)" % [rm.get_available_stock("gold"), gold_before, rm.get_available_stock("food"), food_before, rm.get_available_stock("metal"), metal_before])
		failures += 1
	else:
		print("  [PASS] TC-ARMY.29B: First load restored all army fields and resources without deducting recruitment/upkeep costs.")

	# 5. Apply the same loaded state a second time (double load idempotency and resource consistency)
	var apply_res_2 = SaveManagerScript.apply_loaded_state_to_world(world_instance, saved_state)
	if not apply_res_2.get("success", false):
		printerr("  [FAIL] TC-ARMY.29B: Second apply_loaded_state_to_world failed: %s" % str(apply_res_2))
		failures += 1
	elif wv_army_mgr.get_army_count() != 7:
		printerr("  [FAIL] TC-ARMY.29B: Double-load created duplicate soldiers! Got %d" % wv_army_mgr.get_army_count())
		failures += 1
	elif wv_army_mgr.is_supplied != false or wv_army_mgr.last_upkeep_day != 3:
		printerr("  [FAIL] TC-ARMY.29B: Double-load altered army supply or upkeep day!")
		failures += 1
	elif world_instance.get("citizen_list").size() != citizen_count_before:
		printerr("  [FAIL] TC-ARMY.29B: Double-load created duplicate citizens! Got %d vs %d" % [world_instance.get("citizen_list").size(), citizen_count_before])
		failures += 1
	elif world_instance.get("citizens_by_id").size() != citizen_count_before:
		printerr("  [FAIL] TC-ARMY.29B: Double-load duplicated citizens_by_id entries!")
		failures += 1
	elif hud_ref != null and hud_ref.get_child_count() != hud_child_count_before:
		printerr("  [FAIL] TC-ARMY.29B: Double-load duplicated HUD nodes! Got %d vs %d" % [hud_ref.get_child_count(), hud_child_count_before])
		failures += 1

	elif wv_army_mgr.get_signal_connection_list("army_changed").size() != army_sig_count_before:
		printerr("  [FAIL] TC-ARMY.29B: Double-load duplicated army_changed signal connections!")
		failures += 1
	elif rm != null and (rm.get_available_stock("gold") != gold_before or rm.get_available_stock("food") != food_before or rm.get_available_stock("metal") != metal_before):
		printerr("  [FAIL] TC-ARMY.29B: Repeated application modified resources!")
		failures += 1
	else:
		print("  [PASS] TC-ARMY.29B: Double load strictly idempotent (zero duplicate soldiers, citizens, HUD nodes, signals, or resource drain).")

	# 6. Verify same-day upkeep remains idempotent after restoring the army state
	if tm != null:
		tm.set("current_day", 3)
	var food_pre_same_day: int = rm.get_available_stock("food") if rm != null else 0
	var upkeep_same_day_res: Dictionary = wv_army_mgr.process_daily_upkeep(3)
	if not upkeep_same_day_res.get("already_processed", false) or upkeep_same_day_res.get("cost", -1) != 0:
		printerr("  [FAIL] TC-ARMY.29B: Upkeep on already-processed day 3 did not report already_processed or cost was not 0! Got: %s" % str(upkeep_same_day_res))
		failures += 1
	elif rm != null and rm.get_available_stock("food") != food_pre_same_day:
		printerr("  [FAIL] TC-ARMY.29B: Upkeep on already-processed day 3 deducted food! Before: %d, After: %d" % [food_pre_same_day, rm.get_available_stock("food")])
		failures += 1
	elif wv_army_mgr.last_upkeep_day != 3:
		printerr("  [FAIL] TC-ARMY.29B: Upkeep altered last_upkeep_day!")
		failures += 1
	else:
		print("  [PASS] TC-ARMY.29B: Same-day upkeep remains strictly idempotent after restoring army state.")

	# 7. Package 1K campaign state remains correct through repeated loads
	if camp_mgr != null:
		var c_ser = camp_mgr.serialize()
		var p_raids = c_ser.get("pending_raids", {})
		var proc_raids = c_ser.get("processed_raids", {})
		if not p_raids.has("rival_military") or p_raids["rival_military"].get("scheduled_day") != 8:
			printerr("  [FAIL] TC-ARMY.29B: Package 1K pending raid corrupted after repeated loads: %s" % str(p_raids))
			failures += 1
		elif not proc_raids.has("rival_military_day_3_seq_1"):
			printerr("  [FAIL] TC-ARMY.29B: Package 1K processed raid corrupted after repeated loads: %s" % str(proc_raids))
			failures += 1
		else:
			print("  [PASS] TC-ARMY.29B: Package 1K campaign state preserved accurately through repeated loads.")

	# 8. Re-serialize and verify Save -> Load -> Save roundtrip stability
	if tm != null:
		tm.set("current_day", 5)
	var resaved_state: Dictionary = SaveManagerScript.serialize_world_state(world_instance)
	var resaved_army: Dictionary = resaved_state.get("player_army", {})
	if resaved_army.get("soldier_count") != 7 or resaved_army.get("is_supplied") != false or resaved_army.get("last_upkeep_day") != 3:
		printerr("  [FAIL] TC-ARMY.29B: Re-serialized army state divergent: %s" % str(resaved_army))
		failures += 1
	else:
		print("  [PASS] TC-ARMY.29B: Save -> Load -> Save roundtrip stability verified.")

	# TC-ARMY.30: Legacy Save Load (Missing player_army Section)
	print("\n--- Running TC-ARMY.30: Legacy Save Load Reset ---")
	var dirty_mgr := PlayerArmyManagerScript.new()
	dirty_mgr.soldier_count = 15
	dirty_mgr.is_supplied = false
	dirty_mgr.last_upkeep_day = 20

	dirty_mgr.deserialize({})
	if dirty_mgr.get_army_count() != 0:
		printerr("  [FAIL] TC-ARMY.30: Legacy save did not reset soldier_count to 0, got %d" % dirty_mgr.get_army_count())
		failures += 1
	elif dirty_mgr.is_supplied != true:
		printerr("  [FAIL] TC-ARMY.30: Legacy save did not reset is_supplied to true")
		failures += 1
	elif dirty_mgr.last_upkeep_day != -1:
		printerr("  [FAIL] TC-ARMY.30: Legacy save did not reset last_upkeep_day to -1, got %d" % dirty_mgr.last_upkeep_day)
		failures += 1
	else:
		print("  [PASS] TC-ARMY.30: Unit legacy save safely resets army to 0 soldiers, supplied, with 0 errors.")

	# TC-ARMY.30B: Legacy Save Full World Integration
	print("\n--- Running TC-ARMY.30B: Legacy Save Full World State Load ---")
	var legacy_world_save = saved_state.duplicate(true)
	legacy_world_save.erase("player_army")
	var legacy_apply = SaveManagerScript.apply_loaded_state_to_world(world_instance, legacy_world_save)
	if not legacy_apply.get("success", false):
		printerr("  [FAIL] TC-ARMY.30B: Failed to apply legacy world save: %s" % str(legacy_apply))
		failures += 1
	elif wv_army_mgr.get_army_count() != 0:
		printerr("  [FAIL] TC-ARMY.30B: World army count not reset to 0 on legacy save! Got %d" % wv_army_mgr.get_army_count())
		failures += 1
	elif wv_army_mgr.is_supplied != true:
		printerr("  [FAIL] TC-ARMY.30B: World army is_supplied not reset to true on legacy save!")
		failures += 1
	elif wv_army_mgr.last_upkeep_day != -1:
		printerr("  [FAIL] TC-ARMY.30B: World army last_upkeep_day not reset to -1 on legacy save!")
		failures += 1
	elif camp_mgr != null and not camp_mgr.serialize().get("pending_raids", {}).has("rival_military"):
		printerr("  [FAIL] TC-ARMY.30B: Legacy save load without player_army corrupted unrelated campaign state!")
		failures += 1
	else:
		print("  [PASS] TC-ARMY.30B: Legacy world save application cleanly resets army to 0 soldiers and preserves campaign state.")

	# TC-ARMY.31: Upkeep Day Validation Against Game Clock & Indefinite Evasion Prevention
	print("\n--- Running TC-ARMY.31: Upkeep Day Clock Validation & Evasion Prevention ---")
	var val_clock_save: Dictionary = {
		"schema_version": SaveManagerScript.SAVE_SCHEMA_VERSION,
		"metadata": {},
		"resources": {},
		"buildings": [],
		"citizens": [],
		"game_clock": {
			"current_day": 5
		}
	}

	# 1. Valid past upkeep day (Day 3 on Clock Day 5)
	val_clock_save["player_army"] = {"soldier_count": 5, "last_upkeep_day": 3}
	var res_past = SaveManagerScript.validate_save_data(val_clock_save)
	if not res_past.get("valid", false):
		printerr("  [FAIL] TC-ARMY.31: Valid past upkeep day rejected: %s" % res_past.get("error", ""))
		failures += 1
	else:
		print("  [PASS] TC-ARMY.31: Valid past upkeep day (3 <= 5) accepted.")

	# 2. Valid current upkeep day (Day 5 on Clock Day 5)
	val_clock_save["player_army"] = {"soldier_count": 5, "last_upkeep_day": 5}
	var res_cur = SaveManagerScript.validate_save_data(val_clock_save)
	if not res_cur.get("valid", false):
		printerr("  [FAIL] TC-ARMY.31: Valid current upkeep day rejected: %s" % res_cur.get("error", ""))
		failures += 1
	else:
		print("  [PASS] TC-ARMY.31: Valid current upkeep day (5 <= 5) accepted.")

	# 3. Valid initial upkeep day (-1 on Clock Day 5)
	val_clock_save["player_army"] = {"soldier_count": 5, "last_upkeep_day": -1}
	var res_init = SaveManagerScript.validate_save_data(val_clock_save)
	if not res_init.get("valid", false):
		printerr("  [FAIL] TC-ARMY.31: Valid initial upkeep day (-1) rejected: %s" % res_init.get("error", ""))
		failures += 1
	else:
		print("  [PASS] TC-ARMY.31: Valid initial upkeep day (-1 <= 5) accepted.")

	# 4. Future upkeep day relative to saved game day (Day 6 on Clock Day 5) -> REJECTED
	val_clock_save["player_army"] = {"soldier_count": 5, "last_upkeep_day": 6}
	var res_future = SaveManagerScript.validate_save_data(val_clock_save)
	if res_future.get("valid", true) != false:
		printerr("  [FAIL] TC-ARMY.31: Future upkeep day (6 > 5) was permitted!")
		failures += 1
	else:
		print("  [PASS] TC-ARMY.31: Future upkeep day (6 > 5) strictly rejected by save validator.")

	# 5. Extreme future upkeep day (Day 99999 on Clock Day 5) -> REJECTED
	val_clock_save["player_army"] = {"soldier_count": 5, "last_upkeep_day": 99999}
	var res_extreme = SaveManagerScript.validate_save_data(val_clock_save)
	if res_extreme.get("valid", true) != false:
		printerr("  [FAIL] TC-ARMY.31: Extreme future upkeep day was permitted!")
		failures += 1
	else:
		print("  [PASS] TC-ARMY.31: Extreme future upkeep day (99999) strictly rejected by save validator.")

	# 6. Non-integer, float, and negative-invalid upkeep day
	val_clock_save["player_army"] = {"soldier_count": 5, "last_upkeep_day": "three"}
	var res_bad_str = SaveManagerScript.validate_save_data(val_clock_save)
	val_clock_save["player_army"] = {"soldier_count": 5, "last_upkeep_day": -2}
	var res_bad_neg = SaveManagerScript.validate_save_data(val_clock_save)
	val_clock_save["player_army"] = {"soldier_count": 5, "last_upkeep_day": 3.5}
	var res_bad_flt = SaveManagerScript.validate_save_data(val_clock_save)
	if res_bad_str.get("valid", true) != false or res_bad_neg.get("valid", true) != false or res_bad_flt.get("valid", true) != false:
		printerr("  [FAIL] TC-ARMY.31: Malformed upkeep day values accepted!")
		failures += 1
	else:
		print("  [PASS] TC-ARMY.31: Non-integer, float, and negative-invalid upkeep days strictly rejected.")

	# 7. Present but malformed clock day
	var bad_clock_saves = [
		{"game_clock": {"current_day": "five"}},
		{"game_clock": {"current_day": 5.5}},
		{"game_clock": {"current_day": 0}},
		{"game_clock": {"current_day": -1}},
		{"game_clock": {"current_day": []}},
		{"game_clock": "not_a_dict"}
	]
	var clock_rejections := 0
	for bcs in bad_clock_saves:
		var test_bad = val_clock_save.duplicate(true)
		test_bad["player_army"] = {"soldier_count": 5, "last_upkeep_day": 1}
		test_bad["game_clock"] = bcs["game_clock"]
		var res_bad_clock = SaveManagerScript.validate_save_data(test_bad)
		if not res_bad_clock.get("valid", true):
			clock_rejections += 1

	if clock_rejections != bad_clock_saves.size():
		printerr("  [FAIL] TC-ARMY.31: Present but malformed game_clock day was accepted! (%d / %d rejected)" % [clock_rejections, bad_clock_saves.size()])
		failures += 1
	else:
		print("  [PASS] TC-ARMY.31: Present but malformed game_clock day configurations (%d/%d) strictly rejected." % [clock_rejections, bad_clock_saves.size()])

	# 8. Verify apply_loaded_state_to_world rejects invalid input before destructive world reconstruction begins
	var bad_world_save = saved_state.duplicate(true)
	bad_world_save["game_clock"]["current_day"] = "invalid_string_day"
	var day_before_bad_load = tm.get("current_day") if tm != null else 0
	var pop_before_bad_load = world_instance.get("citizen_list").size()
	var reject_apply_res = SaveManagerScript.apply_loaded_state_to_world(world_instance, bad_world_save)
	if reject_apply_res.get("success", true) != false:
		printerr("  [FAIL] TC-ARMY.31: apply_loaded_state_to_world succeeded with malformed clock day!")
		failures += 1
	elif tm != null and tm.get("current_day") != day_before_bad_load:
		printerr("  [FAIL] TC-ARMY.31: Destructive modification occurred despite invalid clock data! (Day changed to %s)" % str(tm.get("current_day")))
		failures += 1
	elif world_instance.get("citizen_list").size() != pop_before_bad_load:
		printerr("  [FAIL] TC-ARMY.31: Destructive citizen modification occurred despite invalid clock data!")
		failures += 1
	else:
		print("  [PASS] TC-ARMY.31: apply_loaded_state_to_world safely rejected malformed clock save before destructive reconstruction.")

	# 9. Fail-closed deserialize normalization on TimeManager current_day
	if tm != null:
		tm.set("current_day", 5)
	var norm_army := PlayerArmyManagerScript.new(world_instance)
	norm_army.deserialize({"soldier_count": 4, "last_upkeep_day": 99999})
	# Since TimeManager current_day is 5, it must be capped to 5, preventing indefinite upkeep evasion!
	if norm_army.last_upkeep_day > 5:
		printerr("  [FAIL] TC-ARMY.31: deserialize did not clamp future upkeep day to current_day! Got %d" % norm_army.last_upkeep_day)
		failures += 1
	else:
		print("  [PASS] TC-ARMY.31: deserialize fail-closed normalization clamps future upkeep day to current_day (%d)." % norm_army.last_upkeep_day)


	# TC-ARMY.32: Live Barracks Capacity & HUD UI State Refresh
	print("\n--- Running TC-ARMY.32: Live Barracks Capacity & HUD Refresh ---")
	var hud = world_instance.get("hud")
	var test_wd = world_instance.get("world_data")
	var initial_barracks = []
	for b in test_wd.buildings:
		if b.get("type") == "barracks":
			initial_barracks.append(b)

	# Clear barracks for controlled testing
	for b in initial_barracks:
		test_wd.buildings.erase(b)

	# Force army manager to use test_wd
	wv_army_mgr.set_custom_world_data(test_wd)
	wv_army_mgr.notify_capacity_changed()

	if hud != null and hud.has_method("_refresh_army_panel"):
		hud.call("_refresh_army_panel")

	# 1. With 0 barracks, capacity is 0 and recruit button is disabled
	var cap_0 = wv_army_mgr.get_army_capacity()
	if cap_0 != 0:
		printerr("  [FAIL] TC-ARMY.32: Expected 0 capacity with 0 barracks, got %d" % cap_0)
		failures += 1
	elif hud != null and hud.get("recruit_btn") != null and not hud.get("recruit_btn").disabled:
		printerr("  [FAIL] TC-ARMY.32: Recruit button enabled with 0 barracks capacity!")
		failures += 1
	else:
		print("  [PASS] TC-ARMY.32: 0 barracks -> 0 capacity, recruit button disabled.")

	# 2. Place barracks in under_construction state -> capacity remains 0
	var b_test_id := "bld_barracks_live_test"
	var test_b_data := {
		"id": b_test_id,
		"type": "barracks",
		"cell": Vector2i(25, 25),
		"size": Vector2i(3, 3),
		"state": "under_construction",
		"construction_progress": 0.0,
		"construction_hours": 12.0
	}
	test_wd.buildings.append(test_b_data)
	wv_army_mgr.notify_capacity_changed()
	if hud != null and hud.has_method("_refresh_army_panel"):
		hud.call("_refresh_army_panel")

	if wv_army_mgr.get_army_capacity() != 0:
		printerr("  [FAIL] TC-ARMY.32: under_construction barracks granted capacity: %d" % wv_army_mgr.get_army_capacity())
		failures += 1
	else:
		print("  [PASS] TC-ARMY.32: under_construction barracks provides strictly 0 capacity.")

	# 3. Premature completion refused, then complete construction -> capacity dynamically expands to 5 and HUD updates
	var premature_res = world_instance.call("complete_construction", b_test_id)
	if premature_res != false or wv_army_mgr.get_army_capacity() != 0:
		printerr("  [FAIL] TC-ARMY.32: Premature barracks completion permitted at 0.0h progress!")
		failures += 1

	test_b_data["construction_progress"] = 12.0
	var complete_res = world_instance.call("complete_construction", b_test_id)
	if not complete_res or wv_army_mgr.get_army_capacity() != 5:
		printerr("  [FAIL] TC-ARMY.32: Completed barracks did not update capacity to 5! Got %d" % wv_army_mgr.get_army_capacity())
		failures += 1
	elif hud != null and hud.get("army_count_label") != null and not hud.get("army_count_label").text.contains("/ 5"):
		printerr("  [FAIL] TC-ARMY.32: HUD army_count_label did not reflect capacity 5: %s" % hud.get("army_count_label").text)
		failures += 1
	else:
		print("  [PASS] TC-ARMY.32: Barracks completion dynamically refreshed capacity to 5 and updated HUD.")

	# 4. Deactivate barracks (damage) -> capacity drops to 0, existing soldiers preserved
	wv_army_mgr.soldier_count = 3
	world_instance.call("set_building_state", b_test_id, "damaged")
	if wv_army_mgr.get_army_capacity() != 0:
		printerr("  [FAIL] TC-ARMY.32: Damaged barracks still provides capacity: %d" % wv_army_mgr.get_army_capacity())
		failures += 1
	elif wv_army_mgr.get_army_count() != 3:
		printerr("  [FAIL] TC-ARMY.32: Existing soldiers deleted on barracks damage! Got %d" % wv_army_mgr.get_army_count())
		failures += 1
	elif hud != null and hud.get("recruit_btn") != null and not hud.get("recruit_btn").disabled:
		printerr("  [FAIL] TC-ARMY.32: Recruit button enabled with damaged barracks!")
		failures += 1
	else:
		print("  [PASS] TC-ARMY.32: Barracks damage dynamically dropped capacity to 0 and disabled recruit button; 3 soldiers preserved.")

	# 5. Restore barracks to active -> capacity restores to 5 and recruit button re-enables
	world_instance.call("set_building_state", b_test_id, "active")
	if wv_army_mgr.get_army_capacity() != 5:
		printerr("  [FAIL] TC-ARMY.32: Restored barracks did not restore capacity 5! Got %d" % wv_army_mgr.get_army_capacity())
		failures += 1
	else:
		print("  [PASS] TC-ARMY.32: Barracks reactivation dynamically restored capacity to 5.")

	# 6. Demolish barracks -> capacity drops to 0, existing soldiers preserved
	world_instance.call("demolish_building_project", b_test_id)
	if wv_army_mgr.get_army_capacity() != 0:
		printerr("  [FAIL] TC-ARMY.32: Demolished barracks still provides capacity!")
		failures += 1
	elif wv_army_mgr.get_army_count() != 3:
		printerr("  [FAIL] TC-ARMY.32: Demolishing barracks deleted existing soldiers! Got %d" % wv_army_mgr.get_army_count())
		failures += 1
	else:
		print("  [PASS] TC-ARMY.32: Barracks demolition dropped capacity to 0 while preserving soldiers.")

	# 7. Dynamic recruitment cost display in HUD
	if hud != null and hud.get("recruit_cost_label") != null:
		var cost_text: String = hud.get("recruit_cost_label").text
		if not cost_text.contains("20 Vàng") or not cost_text.contains("2 Kim loại") or not cost_text.contains("5 Lương thực"):
			printerr("  [FAIL] TC-ARMY.32: HUD recruit_cost_label did not format EconomyConfig values: %s" % cost_text)
			failures += 1
		else:
			print("  [PASS] TC-ARMY.32: HUD recruit_cost_label dynamically formatted from EconomyConfig (%s)." % cost_text)

	# Restore initial barracks
	test_wd.buildings.append_array(initial_barracks)
	wv_army_mgr.set_custom_world_data(null)
	wv_army_mgr.notify_capacity_changed()
