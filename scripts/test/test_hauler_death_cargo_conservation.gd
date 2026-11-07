extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — BUG-001: Hauler Cargo Conservation on Citizen Death
## Authoritative Coverage: TC-CARGO.1 through TC-CARGO.12 with Fail-Closed Assertions

const CitizenControllerScript = preload("res://scripts/entities/citizen_controller.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")
const JobManagerScript = preload("res://scripts/jobs/job_manager.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")

class MockCappedResourceManager extends Node:
	var stock: Dictionary = {}
	var capacities: Dictionary = {}

	func _init() -> void:
		for r in EconomyConfigScript.ALL_RESOURCES:
			stock[r] = 100
			capacities[r] = 500
		capacities[EconomyConfigScript.RES_GOLD] = 999999

	func get_available_stock(res_id: String) -> int:
		return stock.get(res_id, 0)

	func get_total_stock(res_id: String) -> int:
		return stock.get(res_id, 0)

	func get_storage_capacity(res_id: String) -> int:
		return capacities.get(res_id, 500)

	func add_resource(res_id: String, amount: int) -> int:
		if amount <= 0:
			return 0
		var cur: int = stock.get(res_id, 0)
		var cap: int = capacities.get(res_id, 500)
		var space: int = maxi(0, cap - cur)
		var to_add: int = mini(amount, space)
		stock[res_id] = cur + to_add
		return to_add

var frame_count: int = 0
var world_instance: Node = null
var all_passed: bool = true
var test_results: Array[Dictionary] = []

func _init() -> void:
	print("\n========================================================")
	print("  STARTING BUG-001 HAULER CARGO CONSERVATION TEST SUITE")
	print("========================================================\n")
	var world_scene = load("res://scenes/world/world_view.tscn")
	world_instance = world_scene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count == 3:
		_run_all_tests()
	return false

func _record(test_id: String, passed: bool, message: String) -> void:
	test_results.append({"id": test_id, "passed": passed, "message": message})
	if passed:
		print("  [PASS] %s: %s" % [test_id, message])
	else:
		printerr("  [FAIL] %s: %s" % [test_id, message])
		all_passed = false

func _run_all_tests() -> void:
	var rm: Object = world_instance.call("_get_resource_mgr")
	if rm == null:
		printerr("FATAL: ResourceManager is null in WorldView instance")
		quit(1)
		return

	_test_tc_cargo_1_food_recovery(rm)
	_test_tc_cargo_1b_normal_capacity_pickup_path(rm)
	_test_tc_cargo_2_wood_recovery(rm)
	_test_tc_cargo_3_exact_quantity_once(rm)
	_test_tc_cargo_4_repeated_callbacks_idempotency(rm)
	_test_tc_cargo_5_zero_cargo_normal_death(rm)
	_test_tc_cargo_6_non_hauler_guard_death(rm)
	_test_tc_cargo_7_workplace_demolished_prior_to_death(rm)
	_test_tc_cargo_8_storage_capacity_capped()
	_test_tc_cargo_9_state_cleanup_consistency(rm)
	_test_tc_cargo_10_demolition_conservation_unaffected(rm)
	_test_tc_cargo_11_pending_cargo_full_lifecycle_recovery(rm)
	_test_tc_cargo_12_save_manager_disk_roundtrip(rm)

	print("\n--------------------------------------------------------")
	var passed_count: int = 0
	for res in test_results:
		if res.get("passed", false):
			passed_count += 1
	print("  BUG-001 RESULTS: %d / %d Tests Passed" % [passed_count, test_results.size()])
	if all_passed and passed_count == test_results.size():
		print("  ALL %d BUG-001 HAULER CARGO CONSERVATION TESTS PASSED! (Exit Code 0)" % test_results.size())
		print("--------------------------------------------------------\n")
		quit(0)
	else:
		print("  BUG-001 TESTS FAILED! (Exit Code 1)")
		print("--------------------------------------------------------\n")
		quit(1)

func _setup_test_citizen(cid: String, cname: String, crole: String, rm: Object) -> Node:
	var cit = CitizenControllerScript.new()
	cit.citizen_id = cid
	cit.citizen_name = cname
	cit.role = crole
	cit.world_view = world_instance
	cit.set_custom_resource_manager(rm)
	cit.citizen_died.connect(func(did: String): world_instance.call("_on_citizen_died", did))
	world_instance.citizens_container.add_child(cit)
	world_instance.citizen_list.append(cit)
	world_instance.citizens_by_id[cid] = cit
	return cit

# -----------------------------------------------------------------------------
# TC-CARGO.1: Hauler carrying Food dies -> food deposited to central stock
# (Boundary test: 15 Food demonstrates lack of artificial lower clamping)
# -----------------------------------------------------------------------------
func _test_tc_cargo_1_food_recovery(rm: Object) -> void:
	var cid := "test_cit_cargo_1"
	var cit = _setup_test_citizen(cid, "Hauler Food", "hauler", rm)
	cit.carrying_resource = EconomyConfigScript.RES_FOOD
	cit.carrying_amount = 15

	var stock_before: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_FOOD))
	cit.call("die", "Chết đói trên đường vận chuyển", "starvation_or_exhaustion")
	var stock_after: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_FOOD))

	var ok: bool = (stock_after == stock_before + 15) and (cit.carrying_amount == 0) and cit.carrying_resource.is_empty()
	_record("TC-CARGO.1", ok, "Hauler carrying 15 Food (boundary fixture) dies -> 15 Food deposited to central stock (%d -> %d)" % [stock_before, stock_after])

# -----------------------------------------------------------------------------
# TC-CARGO.1B: Standard 10-unit production carrying capacity pickup and death recovery
# -----------------------------------------------------------------------------
func _test_tc_cargo_1b_normal_capacity_pickup_path(rm: Object) -> void:
	var cid := "test_cit_cargo_1b"
	var cit = _setup_test_citizen(cid, "Hauler Standard 10", "hauler", rm)
	# Normal gameplay carry_capacity is 10 (EconomyConfig / CitizenController carry_capacity)
	var standard_cap: int = cit.carry_capacity
	cit.carrying_resource = EconomyConfigScript.RES_FOOD
	cit.carrying_amount = standard_cap # exactly 10

	var stock_before: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_FOOD))
	cit.call("die", "Tử nạn trên đường", "starvation_or_exhaustion")
	var stock_after: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_FOOD))

	var ok: bool = (standard_cap == 10) and (stock_after == stock_before + 10) and (cit.carrying_amount == 0) and cit.carrying_resource.is_empty()
	_record("TC-CARGO.1B", ok, "Standard hauler (carry_capacity=10) dies -> exactly 10 Food deposited to stock (%d -> %d)" % [stock_before, stock_after])

# -----------------------------------------------------------------------------
# TC-CARGO.2: Hauler carrying Wood dies -> wood deposited to central stock
# (Boundary test: 20 Wood demonstrates lack of artificial lower clamping)
# -----------------------------------------------------------------------------
func _test_tc_cargo_2_wood_recovery(rm: Object) -> void:
	var cid := "test_cit_cargo_2"
	var cit = _setup_test_citizen(cid, "Hauler Wood", "hauler", rm)
	cit.carrying_resource = EconomyConfigScript.RES_WOOD
	cit.carrying_amount = 20

	var stock_before: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_WOOD))
	cit.call("die", "Chết kiệt sức", "starvation_or_exhaustion")
	var stock_after: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_WOOD))

	var ok: bool = (stock_after == stock_before + 20) and (cit.carrying_amount == 0) and cit.carrying_resource.is_empty()
	_record("TC-CARGO.2", ok, "Hauler carrying 20 Wood (boundary fixture) dies -> 20 Wood deposited to central stock (%d -> %d)" % [stock_before, stock_after])

# -----------------------------------------------------------------------------
# TC-CARGO.3: Cargo deposited exactly once (exact quantity, no inflation)
# -----------------------------------------------------------------------------
func _test_tc_cargo_3_exact_quantity_once(rm: Object) -> void:
	var cit = CitizenControllerScript.new()
	cit.citizen_id = "test_cit_cargo_3"
	cit.set_custom_resource_manager(rm)
	cit.carrying_resource = EconomyConfigScript.RES_STONE
	cit.carrying_amount = 8

	var stock_before: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_STONE))
	var res1: Dictionary = cit.call("recover_cargo", rm)
	var stock_after_1: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_STONE))

	var res2: Dictionary = cit.call("recover_cargo", rm)
	var stock_after_2: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_STONE))

	var ok: bool = (
		stock_after_1 == stock_before + 8
		and res1.get("status") == "success"
		and res1.get("recovered") == 8
		and res1.get("remaining") == 0
		and stock_after_2 == stock_after_1
		and res2.get("status") == "no_cargo"
		and res2.get("recovered") == 0
	)
	cit.free()
	_record("TC-CARGO.3", ok, "Cargo deposited exactly once (8 Stone recovered, second recovery returns no_cargo with zero change)")

# -----------------------------------------------------------------------------
# TC-CARGO.4: Repeated death signal/callback does not duplicate resources (idempotency)
# -----------------------------------------------------------------------------
func _test_tc_cargo_4_repeated_callbacks_idempotency(rm: Object) -> void:
	var cid := "test_cit_cargo_4"
	var cit = _setup_test_citizen(cid, "Hauler Ore", "hauler", rm)
	cit.carrying_resource = EconomyConfigScript.RES_ORE
	cit.carrying_amount = 12

	var stock_before: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_ORE))
	# First death invocation
	cit.call("die", "Tử nạn", "starvation_or_exhaustion")
	var stock_after_1: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_ORE))

	# Re-trigger world_view handler directly
	world_instance.call("_on_citizen_died", cid)
	var stock_after_2: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_ORE))

	# Third invocation with unknown ID
	world_instance.call("_on_citizen_died", cid)
	var stock_after_3: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_ORE))

	var ok: bool = (stock_after_1 == stock_before + 12) and (stock_after_2 == stock_after_1) and (stock_after_3 == stock_after_1)
	_record("TC-CARGO.4", ok, "Repeated death callbacks are strictly idempotent (12 Ore deposited once, ignored on duplicate calls)")

# -----------------------------------------------------------------------------
# TC-CARGO.5: Citizen with 0 cargo dies normally without changes to resources
# -----------------------------------------------------------------------------
func _test_tc_cargo_5_zero_cargo_normal_death(rm: Object) -> void:
	var cid := "test_cit_cargo_5"
	var cit = _setup_test_citizen(cid, "Zero Cargo Citizen", "farmer", rm)
	cit.carrying_resource = ""
	cit.carrying_amount = 0

	var stocks_before: Dictionary = {}
	for r in EconomyConfigScript.ALL_RESOURCES:
		stocks_before[r] = int(rm.call("get_available_stock", r))

	cit.call("die", "Qua đời vì tuổi già", "natural")

	var stocks_match: bool = true
	for r in EconomyConfigScript.ALL_RESOURCES:
		if int(rm.call("get_available_stock", r)) != stocks_before[r]:
			stocks_match = false
			break

	var ok: bool = stocks_match and not cit.call("is_alive")
	_record("TC-CARGO.5", ok, "Citizen with 0 cargo dies normally with zero alteration to all resource stocks")

# -----------------------------------------------------------------------------
# TC-CARGO.6: Non-hauler citizen (farmer/guard) dies without resource changes
# -----------------------------------------------------------------------------
func _test_tc_cargo_6_non_hauler_guard_death(rm: Object) -> void:
	var cid := "test_cit_cargo_6"
	var cit = _setup_test_citizen(cid, "Brave Guard", "guard", rm)
	cit.carrying_resource = ""
	cit.carrying_amount = 0

	var gold_before: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_GOLD))
	var food_before: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_FOOD))

	cit.call("die", "Tử trận khi chiến đấu", "combat")

	var gold_after: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_GOLD))
	var food_after: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_FOOD))

	var ok: bool = (gold_after == gold_before) and (food_after == food_before) and (cit.death_cause == "combat")
	_record("TC-CARGO.6", ok, "Non-hauler guard combat death records death_cause='combat' with zero resource changes")

# -----------------------------------------------------------------------------
# TC-CARGO.7: Source workplace demolished prior to death -> cargo still conserved
# -----------------------------------------------------------------------------
func _test_tc_cargo_7_workplace_demolished_prior_to_death(rm: Object) -> void:
	var cid := "test_cit_cargo_7"
	var cit = _setup_test_citizen(cid, "Orphaned Hauler", "hauler", rm)
	cit.carrying_resource = EconomyConfigScript.RES_TOOLS
	cit.carrying_amount = 5
	cit.carrying_source_workplace_id = "demolished_workshop_999"

	var stock_before: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_TOOLS))
	cit.call("die", "Qua đời khi công trình nguồn đã biến mất", "starvation_or_exhaustion")
	var stock_after: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_TOOLS))

	var ok: bool = (stock_after == stock_before + 5) and (cit.carrying_amount == 0) and (cit.carrying_source_workplace_id.is_empty())
	_record("TC-CARGO.7", ok, "Hauler cargo conserved on death even if source workplace was previously demolished (+5 Tools)")

# -----------------------------------------------------------------------------
# TC-CARGO.8: Resource storage already at/above nominal capacity -> stock does not overflow capacity, remaining cargo tracked
# -----------------------------------------------------------------------------
func _test_tc_cargo_8_storage_capacity_capped() -> void:
	var mock_rm := MockCappedResourceManager.new()
	# Set metal capacity to 500, current stock to 495 (space = 5)
	mock_rm.stock[EconomyConfigScript.RES_METAL] = 495
	mock_rm.capacities[EconomyConfigScript.RES_METAL] = 500

	var cit := CitizenControllerScript.new()
	cit.citizen_id = "test_cit_cargo_8"
	cit.set_custom_resource_manager(mock_rm)
	cit.carrying_resource = EconomyConfigScript.RES_METAL
	cit.carrying_amount = 12

	var res: Dictionary = cit.call("recover_cargo", mock_rm)

	var stock_final: int = mock_rm.get_available_stock(EconomyConfigScript.RES_METAL)
	var ok: bool = (
		stock_final == 500
		and res.get("recovered") == 5
		and res.get("remaining") == 7
		and res.get("status") == "partial_capacity"
		and cit.carrying_amount == 7
		and cit.carrying_resource == EconomyConfigScript.RES_METAL
	)
	cit.free()
	mock_rm.free()
	_record("TC-CARGO.8", ok, "Storage capacity cap prevents overflow (5 Metal stored, 7 remaining tracked, status='partial_capacity')")

# -----------------------------------------------------------------------------
# TC-CARGO.9: Cargo and citizen state cleaned up consistently
# -----------------------------------------------------------------------------
func _test_tc_cargo_9_state_cleanup_consistency(rm: Object) -> void:
	var cit := CitizenControllerScript.new()
	cit.citizen_id = "test_cit_cargo_9"
	cit.set_custom_resource_manager(rm)
	cit.carrying_resource = EconomyConfigScript.RES_CRYSTAL
	cit.carrying_amount = 14
	cit.carrying_source_workplace_id = "mine_test_1"

	var res: Dictionary = cit.call("recover_cargo", rm)

	var ok: bool = (
		res.get("status") == "success"
		and res.get("recovered") == 14
		and res.get("remaining") == 0
		and cit.carrying_amount == 0
		and cit.carrying_resource.is_empty()
		and cit.carrying_source_workplace_id.is_empty()
	)
	cit.free()
	_record("TC-CARGO.9", ok, "Post-recovery citizen state strictly cleaned up (amount=0, resource='', source_id='')")

# -----------------------------------------------------------------------------
# TC-CARGO.10: Existing demolition cargo conservation remains unaffected
# -----------------------------------------------------------------------------
func _test_tc_cargo_10_demolition_conservation_unaffected(rm: Object) -> void:
	var b_data := {
		"id": "test_farm_demolish",
		"type": "farm",
		"cell": Vector2i(10, 10),
		"size": Vector2i(2, 2),
		"status": "active"
	}
	var carried_cargo := {
		EconomyConfigScript.RES_FOOD: 25
	}

	var can_demolish_res: Dictionary = BuildingSystemScript.can_demolish_building(
		b_data,
		world_instance.world_data,
		rm,
		0.5,
		carried_cargo
	)

	var ok: bool = can_demolish_res.get("can_demolish", false) == true
	_record("TC-CARGO.10", ok, "BuildingSystem demolition cargo preflight remains fully operational and unregressed")

# -----------------------------------------------------------------------------
# TC-CARGO.11: Full-capacity pending recovery lifecycle (Section 2.2)
# -----------------------------------------------------------------------------
func _test_tc_cargo_11_pending_cargo_full_lifecycle_recovery(rm: Object) -> void:
	# 1. Setup: Fill stone stock to capacity (500/500)
	var cap: int = int(rm.call("get_storage_capacity", EconomyConfigScript.RES_STONE))
	var initial_stone: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_STONE))
	rm.call("add_resource", EconomyConfigScript.RES_STONE, cap - initial_stone)
	var stone_full: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_STONE))

	# 2. Citizen carrying 10 stone dies while storage is completely full
	var cid := "test_cit_cargo_full_11"
	var cit = _setup_test_citizen(cid, "Hauler Full Storage", "hauler", rm)
	cit.carrying_resource = EconomyConfigScript.RES_STONE
	cit.carrying_amount = 10

	cit.call("die", "Chết đói khi kho đá đầy", "starvation_or_exhaustion")

	# Check: Storage remains capped, citizen fields cleared, remainder stored in pending_death_cargo
	var stone_after_death: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_STONE))
	var pending_amt: int = int(world_instance.call("get_pending_death_cargo", EconomyConfigScript.RES_STONE))

	# Check: Repeated death callback does not duplicate pending cargo
	world_instance.call("_on_citizen_died", cid)
	var pending_amt_dup: int = int(world_instance.call("get_pending_death_cargo", EconomyConfigScript.RES_STONE))

	# 3. Capacity becomes available: consume 20 stone
	rm.call("consume_resource", EconomyConfigScript.RES_STONE, 20)
	var stone_after_consume: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_STONE))

	# 4. Flush pending death cargo: recovers the 10 stone into available space
	var flush_res: Dictionary = world_instance.call("flush_pending_death_cargo")
	var stone_after_flush: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_STONE))
	var pending_after_flush: int = int(world_instance.call("get_pending_death_cargo", EconomyConfigScript.RES_STONE))

	# 5. Subsequent flush does nothing (exact once)
	var second_flush_res: Dictionary = world_instance.call("flush_pending_death_cargo")
	var stone_after_second_flush: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_STONE))

	var ok: bool = (
		stone_full == cap
		and stone_after_death == cap
		and pending_amt == 10
		and pending_amt_dup == 10
		and stone_after_consume == cap - 20
		and flush_res.get("recovered", {}).get(EconomyConfigScript.RES_STONE, 0) == 10
		and stone_after_flush == cap - 10
		and pending_after_flush == 0
		and second_flush_res.get("recovered", {}).is_empty()
		and stone_after_second_flush == stone_after_flush
	)

	_record("TC-CARGO.11", ok, "Full lifecycle pending death cargo: durably held when full, recovered exact once when space opens, zero duplication")

# -----------------------------------------------------------------------------
# TC-CARGO.12: SaveManager Real Disk Save/Load Roundtrip of Pending Death Cargo
# -----------------------------------------------------------------------------
func _test_tc_cargo_12_save_manager_disk_roundtrip(rm: Object) -> void:
	# 1. Setup: Fill stone stock to capacity
	var cap: int = int(rm.call("get_storage_capacity", EconomyConfigScript.RES_STONE))
	var initial_stone: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_STONE))
	rm.call("add_resource", EconomyConfigScript.RES_STONE, cap - initial_stone)

	# 2. Citizen carrying 10 stone dies while storage is completely full
	var cid := "test_cit_save_roundtrip_12"
	var cit = _setup_test_citizen(cid, "Hauler Save Roundtrip", "hauler", rm)
	cit.carrying_resource = EconomyConfigScript.RES_STONE
	cit.carrying_amount = 10

	cit.call("die", "Tử nạn khi kho đầy trước khi lưu game", "combat")

	# Pending death cargo now contains 10 stone in world_instance
	var pending_before_save: int = int(world_instance.call("get_pending_death_cargo", EconomyConfigScript.RES_STONE))

	# 3. Save to disk via real SaveManager.save_to_file
	var test_save_path := "user://test_death_cargo_roundtrip.json"
	var save_res: Dictionary = SaveManagerScript.save_to_file(world_instance, test_save_path)
	var save_ok: bool = bool(save_res.get("success", false))

	# 4. Clear/mutate pending_death_cargo in world_instance to prove restoration
	world_instance.set("pending_death_cargo", {})
	var pending_cleared: int = int(world_instance.call("get_pending_death_cargo", EconomyConfigScript.RES_STONE))

	# 5. Load from disk via real SaveManager.load_from_file and apply to world
	var load_res: Dictionary = SaveManagerScript.load_from_file(test_save_path)
	var load_ok: bool = bool(load_res.get("success", false))
	var apply_ok: bool = false
	if load_ok:
		var apply_res: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, load_res.get("data", {}))
		apply_ok = bool(apply_res.get("success", false))

	var pending_restored: int = int(world_instance.call("get_pending_death_cargo", EconomyConfigScript.RES_STONE))

	# 6. Free capacity: consume 20 stone
	rm.call("consume_resource", EconomyConfigScript.RES_STONE, 20)
	var stone_after_consume: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_STONE))

	# 7. Flush pending death cargo: recovers the 10 stone into available space
	var flush_res: Dictionary = world_instance.call("flush_pending_death_cargo")
	var stone_after_flush: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_STONE))
	var pending_after_flush: int = int(world_instance.call("get_pending_death_cargo", EconomyConfigScript.RES_STONE))

	# 8. Subsequent flush does nothing (idempotent, exact-once)
	var second_flush_res: Dictionary = world_instance.call("flush_pending_death_cargo")
	var stone_after_second_flush: int = int(rm.call("get_available_stock", EconomyConfigScript.RES_STONE))

	# 9. Clean up temporary save file
	if FileAccess.file_exists(test_save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save_path))

	var ok: bool = (
		pending_before_save == 10
		and save_ok
		and pending_cleared == 0
		and load_ok
		and apply_ok
		and pending_restored == 10
		and stone_after_consume == cap - 20
		and flush_res.get("recovered", {}).get(EconomyConfigScript.RES_STONE, 0) == 10
		and stone_after_flush == cap - 10
		and pending_after_flush == 0
		and second_flush_res.get("recovered", {}).is_empty()
		and stone_after_second_flush == stone_after_flush
	)

	_record("TC-CARGO.12", ok, "SaveManager disk roundtrip of pending death cargo: persisted to disk, restored faithfully, flushed exact-once when space opens, zero duplicate credit")
