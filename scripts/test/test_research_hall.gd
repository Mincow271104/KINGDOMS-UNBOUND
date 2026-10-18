extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — Package 1F: Research Hall Integration
## Covers TC-RH.1 through TC-RH.7 with fail-closed assertions:
## TC-RH.1: Blueprint validation & configuration integrity
## TC-RH.2: Placement rules, 3x3 footprint, bounds, water, collision, and cost reservation
## TC-RH.3: BuildingSystem.is_research_hall_active detection (active vs destroyed)
## TC-RH.4: Research gating (can_research and start_research fail closed without active hall)
## TC-RH.5: Downtime pause safety (progress frozen without reset during hall downtime, resumes on rebuild)
## TC-RH.6: HUD integration (ResearchHallBtn, build request, UI warning banner, tech button locking)
## TC-RH.7: Full WorldView lifecycle, placement execution, sprite setup, and Save/Load persistence

const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")
const ResearchManagerScript = preload("res://scripts/research/research_manager.gd")
const TechTreeScript = preload("res://scripts/research/tech_tree.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const IsoMathScript = preload("res://scripts/utils/iso_math.gd")

# Mock Resource Manager for isolated unit testing
class MockTestResourceManager extends Node:
	var stock: Dictionary = {}
	var capacities: Dictionary = {}
	var reserve_calls: int = 0
	var commit_calls: int = 0

	func _init(initial: Dictionary = {}) -> void:
		for r in EconomyConfig.ALL_RESOURCES:
			stock[r] = initial.get(r, 0)
			capacities[r] = 500

	func get_available_stock(res_id: String) -> int:
		return stock.get(res_id, 0)

	func can_afford(cost: Dictionary) -> bool:
		for r in cost:
			if get_available_stock(r) < cost[r]:
				return false
		return true

	func reserve_cost(cost: Dictionary) -> bool:
		reserve_calls += 1
		return can_afford(cost)

	func commit_cost(cost: Dictionary) -> void:
		commit_calls += 1
		for r in cost:
			stock[r] = get_available_stock(r) - cost[r]

	func consume_resource(res_id: String, amount: int) -> bool:
		if get_available_stock(res_id) >= amount:
			stock[res_id] = get_available_stock(res_id) - amount
			return true
		return false

	func add_resource(res_id: String, amount: int) -> int:
		var cur = get_available_stock(res_id)
		var added = mini(amount, capacities.get(res_id, 500) - cur)
		stock[res_id] = cur + added
		return added

	func add_storage_capacity(res_id: String, amount: int) -> void:
		capacities[res_id] = capacities.get(res_id, 500) + amount

var frame_count: int = 0
var world_instance: Node = null
var all_passed: bool = true

func _init() -> void:
	print("\n========================================================")
	print("  STARTING PACKAGE 1F RESEARCH HALL TEST SUITE")
	print("========================================================\n")

	var world_scene = load("res://scenes/world/world_view.tscn")
	world_instance = world_scene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1

	if frame_count == 3:
		var pass_tc1 := _test_tc_rh_1_blueprint()
		var pass_tc2 := _test_tc_rh_2_placement()
		var pass_tc3 := _test_tc_rh_3_hall_detection()
		var pass_tc4 := _test_tc_rh_4_research_gating()
		var pass_tc5 := _test_tc_rh_5_downtime_pause_safety()
		var pass_tc6 := _test_tc_rh_6_hud_integration()
		var pass_tc7 := _test_tc_rh_7_worldview_and_save_load()

		all_passed = pass_tc1 and pass_tc2 and pass_tc3 and pass_tc4 and pass_tc5 and pass_tc6 and pass_tc7

		print("\n--------------------------------------------------------")
		if all_passed:
			print("  ALL PACKAGE 1F RESEARCH HALL TESTS PASSED! (Exit Code 0)")
			print("--------------------------------------------------------\n")
			quit(0)
			return true
		else:
			print("  PACKAGE 1F RESEARCH HALL TESTS FAILED! (Exit Code 1)")
			print("--------------------------------------------------------\n")
			quit(1)
			return true

	return false

# -----------------------------------------------------------------------------
# TC-RH.1: Blueprint Validation & Integrity (Fail Closed)
# -----------------------------------------------------------------------------
func _test_tc_rh_1_blueprint() -> bool:
	print("--- Running TC-RH.1: Blueprint Validation & Integrity ---")
	var failures: int = 0

	if not EconomyConfig.BLUEPRINTS.has("research_hall"):
		printerr("FAIL: EconomyConfig.BLUEPRINTS missing 'research_hall' entry")
		failures += 1
		return false

	var bp: Dictionary = EconomyConfig.BLUEPRINTS["research_hall"]
	if bp.get("id") != "research_hall":
		printerr("FAIL: Expected id 'research_hall', got: %s" % bp.get("id"))
		failures += 1

	if bp.get("name_vi") != "Viện Nghiên Cứu Hoàng Gia":
		printerr("FAIL: Expected name_vi 'Viện Nghiên Cứu Hoàng Gia', got: %s" % bp.get("name_vi"))
		failures += 1

	if bp.get("footprint") != Vector2i(3, 3):
		printerr("FAIL: Expected footprint Vector2i(3, 3), got: %s" % str(bp.get("footprint")))
		failures += 1

	var cost: Dictionary = bp.get("cost", {})
	if cost.get(EconomyConfig.RES_WOOD) != 25 or cost.get(EconomyConfig.RES_STONE) != 10:
		printerr("FAIL: Expected cost {wood: 25, stone: 10}, got: %s" % str(cost))
		failures += 1

	if bp.get("construction_hours") != 12.0:
		printerr("FAIL: Expected construction_hours 12.0, got: %s" % str(bp.get("construction_hours")))
		failures += 1

	if bp.get("housing_capacity", -1) != 0:
		printerr("FAIL: Expected housing_capacity 0, got: %s" % str(bp.get("housing_capacity")))
		failures += 1

	if not bp.get("storage_bonus", {1: 1}).is_empty():
		printerr("FAIL: Expected empty storage_bonus, got: %s" % str(bp.get("storage_bonus")))
		failures += 1

	if bp.get("max_workers", -1) != 0:
		printerr("FAIL: Expected max_workers 0, got: %s" % str(bp.get("max_workers")))
		failures += 1

	if bp.get("job_type", "invalid") != "":
		printerr("FAIL: Expected empty job_type, got: %s" % str(bp.get("job_type")))
		failures += 1

	if failures == 0:
		print("PASS TC-RH.1: Blueprint validation fully conformant to authoritative spec")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-RH.2: Placement Rules, Footprint, Bounds, Water, Collision & Costs
# -----------------------------------------------------------------------------
func _test_tc_rh_2_placement() -> bool:
	print("--- Running TC-RH.2: Placement Rules, Bounds, Water, Occupancy & Cost Reservation ---")
	var failures: int = 0

	var world_data = WorldGenerator.generate(42)
	var poor_rm = MockTestResourceManager.new({EconomyConfig.RES_WOOD: 10, EconomyConfig.RES_STONE: 5})
	var rich_rm = MockTestResourceManager.new({EconomyConfig.RES_WOOD: 100, EconomyConfig.RES_STONE: 50})

	# 1. Unaffordable check
	var res_poor = BuildingSystem.can_place_building("research_hall", Vector2i(20, 20), world_data, poor_rm)
	if res_poor.get("valid", true):
		printerr("FAIL: can_place_building should fail when resources are insufficient")
		failures += 1
	elif res_poor.get("reason") != "Không đủ tài nguyên xây dựng":
		printerr("FAIL: Expected reason 'Không đủ tài nguyên xây dựng', got: %s" % res_poor.get("reason"))
		failures += 1

	# 2. Out of bounds check (3x3 footprint at edge)
	var res_oob = BuildingSystem.can_place_building("research_hall", Vector2i(63, 63), world_data, rich_rm)
	if res_oob.get("valid", true):
		printerr("FAIL: can_place_building should fail when 3x3 footprint exceeds map bounds")
		failures += 1

	# 3. Water terrain check
	world_data.terrain[20][20] = WorldGenerator.TerrainType.WATER
	var res_water = BuildingSystem.can_place_building("research_hall", Vector2i(20, 20), world_data, rich_rm)
	if res_water.get("valid", true):
		printerr("FAIL: can_place_building should fail on water terrain")
		failures += 1
	world_data.terrain[20][20] = WorldGenerator.TerrainType.GRASS

	# 4. Occupancy collision on any of the 9 cells
	for ox in range(3):
		for oy in range(3):
			world_data.occupancy[25 + ox][25 + oy] = false
	world_data.occupancy[26][26] = true # Block center cell of 3x3
	var res_occ = BuildingSystem.can_place_building("research_hall", Vector2i(25, 25), world_data, rich_rm)
	if res_occ.get("valid", true):
		printerr("FAIL: can_place_building should fail when any of the 9 cells is occupied")
		failures += 1
	world_data.occupancy[26][26] = false

	# 5. Successful atomic placement
	var wood_before = rich_rm.get_available_stock(EconomyConfig.RES_WOOD)
	var stone_before = rich_rm.get_available_stock(EconomyConfig.RES_STONE)
	var place_res = BuildingSystem.place_building("research_hall", Vector2i(25, 25), world_data, rich_rm)

	if not place_res.get("success", false):
		printerr("FAIL: place_building failed unexpectedly: %s" % place_res.get("reason"))
		failures += 1
	else:
		# Check exact resource deduction
		if rich_rm.get_available_stock(EconomyConfig.RES_WOOD) != wood_before - 25:
			printerr("FAIL: 25 wood was not deducted correctly")
			failures += 1
		if rich_rm.get_available_stock(EconomyConfig.RES_STONE) != stone_before - 10:
			printerr("FAIL: 10 stone was not deducted correctly")
			failures += 1

		# Check all 9 cells occupied
		var all_occ: bool = true
		for ox in range(3):
			for oy in range(3):
				if not world_data.occupancy[25 + ox][25 + oy]:
					all_occ = false
		if not all_occ:
			printerr("FAIL: Not all 9 cells were marked as occupied for 3x3 research_hall")
			failures += 1

		# Check building record
		var b_data = place_res.get("building", {})
		if b_data.get("type") != "research_hall" or b_data.get("size") != Vector2i(3, 3) or (b_data.get("state") != "active" and b_data.get("state") != "under_construction"):
			printerr("FAIL: Building data improperly recorded: %s" % str(b_data))
			failures += 1

	poor_rm.queue_free()
	rich_rm.queue_free()

	if failures == 0:
		print("PASS TC-RH.2: Placement rules, 3x3 bounds, water, occupancy and atomic cost deduction verified")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-RH.3: BuildingSystem.is_research_hall_active Detection
# -----------------------------------------------------------------------------
func _test_tc_rh_3_hall_detection() -> bool:
	print("--- Running TC-RH.3: BuildingSystem.is_research_hall_active Detection ---")
	var failures: int = 0

	var world_data = WorldGenerator.generate(123)

	# Initially no research hall
	if BuildingSystem.is_research_hall_active(world_data):
		printerr("FAIL: is_research_hall_active returned true on fresh world with no hall")
		failures += 1

	# Place active hall
	for ox in range(3):
		for oy in range(3):
			world_data.occupancy[15 + ox][15 + oy] = false
			world_data.terrain[15 + ox][15 + oy] = WorldGenerator.TerrainType.GRASS
	var rm = MockTestResourceManager.new({EconomyConfig.RES_WOOD: 100, EconomyConfig.RES_STONE: 100})
	var place_res = BuildingSystem.place_building("research_hall", Vector2i(15, 15), world_data, rm)
	if not place_res.get("success", false):
		printerr("FAIL: Failed to place research hall in TC-RH.3: %s" % place_res.get("reason"))
		failures += 1
		rm.queue_free()
		return false

	var b_data = place_res.get("building")

	# 1. State 'active' -> true
	b_data["state"] = "active"
	if not BuildingSystem.is_research_hall_active(world_data):
		printerr("FAIL: is_research_hall_active should return true when state is 'active'")
		failures += 1

	# 2. State 'paused' -> false
	b_data["state"] = "paused"
	if BuildingSystem.is_research_hall_active(world_data):
		printerr("FAIL: is_research_hall_active should return false when state is 'paused'")
		failures += 1

	# 3. State 'damaged' -> false
	b_data["state"] = "damaged"
	if BuildingSystem.is_research_hall_active(world_data):
		printerr("FAIL: is_research_hall_active should return false when state is 'damaged'")
		failures += 1

	# 4. State 'under_construction' -> false
	b_data["state"] = "under_construction"
	if BuildingSystem.is_research_hall_active(world_data):
		printerr("FAIL: is_research_hall_active should return false when state is 'under_construction'")
		failures += 1

	# 5. State 'planned' -> false
	b_data["state"] = "planned"
	if BuildingSystem.is_research_hall_active(world_data):
		printerr("FAIL: is_research_hall_active should return false when state is 'planned'")
		failures += 1

	# 6. State 'destroyed' -> false
	b_data["state"] = "destroyed"
	if BuildingSystem.is_research_hall_active(world_data):
		printerr("FAIL: is_research_hall_active should return false when state is 'destroyed'")
		failures += 1

	# 7. Missing state field -> defaults to 'active' -> true
	b_data.erase("state")
	if not BuildingSystem.is_research_hall_active(world_data):
		printerr("FAIL: is_research_hall_active should return true when state field is omitted (defaulting to active)")
		failures += 1

	# 8. No research hall in world -> false
	world_data.buildings.clear()
	if BuildingSystem.is_research_hall_active(world_data):
		printerr("FAIL: is_research_hall_active should return false when no research hall exists in buildings")
		failures += 1

	# 9. Null world_data safety -> false
	if BuildingSystem.is_research_hall_active(null):
		printerr("FAIL: is_research_hall_active should return false for null world_data")
		failures += 1

	rm.queue_free()

	if failures == 0:
		print("PASS TC-RH.3: is_research_hall_active accurately reflects hall existence and state")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-RH.4: Research Gating System (can_research & start_research Fail Closed)
# -----------------------------------------------------------------------------
func _test_tc_rh_4_research_gating() -> bool:
	print("--- Running TC-RH.4: Research Gating System ---")
	var failures: int = 0

	var research_mgr = ResearchManager.new()
	var rm = MockTestResourceManager.new({EconomyConfig.RES_WOOD: 100, EconomyConfig.RES_FOOD: 100})

	# Test 1: No hall checker configured -> has_active_hall() is false
	if research_mgr.has_active_hall():
		printerr("FAIL: has_active_hall should be false by default without a valid checker")
		failures += 1

	var check_no_hall = research_mgr.can_research("crop_rotation", rm)
	if check_no_hall.get("valid", true):
		printerr("FAIL: can_research should return valid: false when no research hall exists")
		failures += 1
	elif check_no_hall.get("reason") != "Cần có Viện Nghiên Cứu Hoàng Gia đang hoạt động":
		printerr("FAIL: Expected reason 'Cần có Viện Nghiên Cứu Hoàng Gia đang hoạt động', got: %s" % check_no_hall.get("reason"))
		failures += 1

	var start_no_hall = research_mgr.start_research("crop_rotation", rm)
	if start_no_hall:
		printerr("FAIL: start_research must return false when no research hall exists")
		failures += 1
	if research_mgr.active_tech_id != "":
		printerr("FAIL: active_tech_id must remain empty when start_research fails")
		failures += 1
	if rm.get_available_stock(EconomyConfig.RES_WOOD) != 100 or rm.get_available_stock(EconomyConfig.RES_FOOD) != 100:
		printerr("FAIL: No resources should be consumed when start_research is rejected (no hall)")
		failures += 1
	if rm.reserve_calls != 0 or rm.commit_calls != 0:
		printerr("FAIL: reserve_calls and commit_calls must be 0 when no hall exists. Got reserve=%d, commit=%d" % [rm.reserve_calls, rm.commit_calls])
		failures += 1

	# Test 2: Hall present but inactive (checker returns false)
	var hall_dict := {"active": false}
	research_mgr.set_hall_checker(func(): return hall_dict["active"])

	if research_mgr.has_active_hall():
		printerr("FAIL: has_active_hall should be false when checker returns false")
		failures += 1

	var check_inactive = research_mgr.can_research("crop_rotation", rm)
	if check_inactive.get("valid", true):
		printerr("FAIL: can_research should return valid: false when hall is inactive")
		failures += 1

	var start_inactive = research_mgr.start_research("crop_rotation", rm)
	if start_inactive:
		printerr("FAIL: start_research must return false when hall is inactive")
		failures += 1
	if research_mgr.active_tech_id != "":
		printerr("FAIL: active_tech_id must remain empty when hall is inactive")
		failures += 1
	if rm.get_available_stock(EconomyConfig.RES_WOOD) != 100 or rm.get_available_stock(EconomyConfig.RES_FOOD) != 100:
		printerr("FAIL: Resources altered when hall is inactive")
		failures += 1
	if rm.reserve_calls != 0 or rm.commit_calls != 0:
		printerr("FAIL: reserve_calls and commit_calls must be 0 when hall is inactive. Got reserve=%d, commit=%d" % [rm.reserve_calls, rm.commit_calls])
		failures += 1

	# Test 3: Hall is active, but partial resource deficiency (20 Wood, 5 Food; crop_rotation requires 20 Wood, 10 Food)
	hall_dict["active"] = true
	var rm_partial = MockTestResourceManager.new({EconomyConfig.RES_WOOD: 20, EconomyConfig.RES_FOOD: 5})

	var start_partial = research_mgr.start_research("crop_rotation", rm_partial)
	if start_partial:
		printerr("FAIL: start_research should fail on partial resource deficiency")
		failures += 1
	if research_mgr.active_tech_id != "":
		printerr("FAIL: active_tech_id should remain empty when reserve fails")
		failures += 1
	if rm_partial.reserve_calls != 1:
		printerr("FAIL: reserve_calls should be 1 on attempted reservation. Got: %d" % rm_partial.reserve_calls)
		failures += 1
	if rm_partial.commit_calls != 0:
		printerr("FAIL: commit_calls must be 0 when reserve fails. Got: %d" % rm_partial.commit_calls)
		failures += 1
	if rm_partial.get_available_stock(EconomyConfig.RES_WOOD) != 20 or rm_partial.get_available_stock(EconomyConfig.RES_FOOD) != 5:
		printerr("FAIL: Resources partially deducted on reserve failure. Wood=%d, Food=%d" % [rm_partial.get_available_stock(EconomyConfig.RES_WOOD), rm_partial.get_available_stock(EconomyConfig.RES_FOOD)])
		failures += 1
	rm_partial.queue_free()

	# Test 4: Missing atomic API (resource_mgr lacking reserve_cost/commit_cost methods)
	var dummy_rm = RefCounted.new()
	var start_no_api = research_mgr.start_research("crop_rotation", dummy_rm)
	if start_no_api:
		printerr("FAIL: start_research should fail closed when resource_mgr lacks reserve_cost/commit_cost")
		failures += 1
	if research_mgr.active_tech_id != "":
		printerr("FAIL: active_tech_id should remain empty when resource_mgr lacks atomic API")
		failures += 1

	# Test 4b: Null resource_mgr with non-empty cost technology must fail closed
	var signal_emitted := false
	var signal_callback = func(_t_id): signal_emitted = true
	research_mgr.tech_started.connect(signal_callback)

	var prev_progress: float = research_mgr.active_progress_hours
	var prev_required: float = research_mgr.active_required_hours
	var prev_wood: int = rm.get_available_stock(EconomyConfig.RES_WOOD)
	var prev_food: int = rm.get_available_stock(EconomyConfig.RES_FOOD)

	var start_null_mgr = research_mgr.start_research("crop_rotation", null)
	if start_null_mgr:
		printerr("FAIL: start_research must return false when resource_mgr is null and cost is non-empty")
		failures += 1
	if research_mgr.active_tech_id != "":
		printerr("FAIL: active_tech_id must remain empty when start_research fails with null resource_mgr")
		failures += 1
	if research_mgr.active_progress_hours != prev_progress:
		printerr("FAIL: active_progress_hours changed when start_research failed with null resource_mgr")
		failures += 1
	if research_mgr.active_required_hours != prev_required:
		printerr("FAIL: active_required_hours changed when start_research failed with null resource_mgr")
		failures += 1
	if signal_emitted:
		printerr("FAIL: tech_started signal was emitted when start_research failed with null resource_mgr")
		failures += 1
	if rm.get_available_stock(EconomyConfig.RES_WOOD) != prev_wood or rm.get_available_stock(EconomyConfig.RES_FOOD) != prev_food:
		printerr("FAIL: Resources deducted when start_research failed with null resource_mgr")
		failures += 1

	research_mgr.tech_started.disconnect(signal_callback)

	# Test 5: Hall checker returns true, sufficient resources, atomic reserve & commit succeeds
	if not research_mgr.has_active_hall():
		printerr("FAIL: has_active_hall should return true when checker returns true")
		failures += 1

	var check_with_hall = research_mgr.can_research("crop_rotation", rm)
	if not check_with_hall.get("valid", false):
		printerr("FAIL: can_research should return valid: true with active hall: %s" % check_with_hall.get("reason"))
		failures += 1

	rm.reserve_calls = 0
	rm.commit_calls = 0
	var start_with_hall = research_mgr.start_research("crop_rotation", rm)
	if not start_with_hall:
		printerr("FAIL: start_research should succeed with active hall and sufficient resources")
		failures += 1
	if research_mgr.active_tech_id != "crop_rotation":
		printerr("FAIL: Expected active_tech_id 'crop_rotation', got: %s" % research_mgr.active_tech_id)
		failures += 1
	if rm.reserve_calls != 1 or rm.commit_calls != 1:
		printerr("FAIL: reserve_calls and commit_calls must each be 1 on success. Got reserve=%d, commit=%d" % [rm.reserve_calls, rm.commit_calls])
		failures += 1
	if rm.get_available_stock(EconomyConfig.RES_WOOD) != 80: # 20 wood deducted
		printerr("FAIL: 20 wood should be deducted upon research start")
		failures += 1
	if rm.get_available_stock(EconomyConfig.RES_FOOD) != 90: # 10 food deducted
		printerr("FAIL: 10 food should be deducted upon research start")
		failures += 1

	rm.queue_free()

	if failures == 0:
		print("PASS TC-RH.4: Research gating strictly prevents starting research without active hall and enforces atomic reservation/commit")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-RH.5: Downtime Pause Safety & Progress Retention
# -----------------------------------------------------------------------------
func _test_tc_rh_5_downtime_pause_safety() -> bool:
	print("--- Running TC-RH.5: Downtime Pause Safety & Progress Retention ---")
	var failures: int = 0

	var research_mgr = ResearchManager.new()
	var rm = MockTestResourceManager.new({EconomyConfig.RES_WOOD: 100, EconomyConfig.RES_FOOD: 100})

	var hall_dict := {"active": true}
	research_mgr.set_hall_checker(func(): return hall_dict["active"])

	var ok = research_mgr.start_research("crop_rotation", rm)
	if not ok:
		printerr("FAIL: Failed to start research in TC-RH.5")
		rm.queue_free()
		return false

	# Advance 4 hours of progress
	research_mgr.progress_research(4.0, rm)
	if research_mgr.active_progress_hours != 4.0:
		printerr("FAIL: Expected 4.0 progress hours, got: %f" % research_mgr.active_progress_hours)
		failures += 1

	# Hall goes down (destroyed / downtime)
	hall_dict["active"] = false

	# Attempt to progress 2 hours while hall is down
	var progressed = research_mgr.progress_research(2.0, rm)
	if progressed:
		printerr("FAIL: progress_research must not return true during downtime")
		failures += 1
	if research_mgr.active_progress_hours != 4.0:
		printerr("FAIL: Progress must freeze during downtime without losing prior progress. Expected 4.0, got: %f" % research_mgr.active_progress_hours)
		failures += 1

	# Hall restored
	hall_dict["active"] = true

	# Progress resumes seamlessly (8 more hours to finish 12h project)
	var completed = research_mgr.progress_research(8.0, rm)
	if not completed:
		printerr("FAIL: Research should complete once remaining hours are fulfilled after hall restoration")
		failures += 1
	if not research_mgr.is_unlocked("crop_rotation"):
		printerr("FAIL: crop_rotation should be unlocked upon completion")
		failures += 1
	if research_mgr.active_tech_id != "":
		printerr("FAIL: active_tech_id should be cleared upon completion")
		failures += 1

	rm.queue_free()

	if failures == 0:
		print("PASS TC-RH.5: Downtime pause safety verified: progress freezes without data loss and resumes seamlessly")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-RH.6: HUD Integration & UI Fail-Closed Assertions
# -----------------------------------------------------------------------------
func _test_tc_rh_6_hud_integration() -> bool:
	print("--- Running TC-RH.6: HUD Integration & UI Assertions ---")
	var failures: int = 0

	var hud = world_instance.get_node_or_null("HUD")
	if hud == null:
		printerr("FAIL: HUD node not found in WorldView scene")
		return false

	var grid = hud.get_node_or_null("BuildMenuPanel/MarginContainer/VBoxContainer/GridContainer")
	if grid == null:
		printerr("FAIL: BuildMenuPanel GridContainer not found")
		return false

	var btn_hall: Button = grid.get_node_or_null("ResearchHallBtn")
	if btn_hall == null:
		printerr("FAIL: ResearchHallBtn missing in BuildMenuPanel GridContainer")
		failures += 1
	else:
		if not "Viện Nghiên Cứu" in btn_hall.text:
			printerr("FAIL: ResearchHallBtn text missing 'Viện Nghiên Cứu': %s" % btn_hall.text)
			failures += 1
		if not "25 Gỗ" in btn_hall.text or not "10 Đá" in btn_hall.text:
			printerr("FAIL: ResearchHallBtn text missing cost specification: %s" % btn_hall.text)
			failures += 1

		# Test button press activates research_hall placement in WorldView
		btn_hall.pressed.emit()
		if world_instance.get("placing_building_type") != "research_hall":
			printerr("FAIL: ResearchHallBtn did not activate 'research_hall' placement! Current: %s" % str(world_instance.get("placing_building_type")))
			failures += 1
		world_instance.call("_cancel_placement")

	# Test HUD Research UI when no hall is present
	var test_rm = ResearchManager.new()
	test_rm.set_hall_checker(func(): return false)
	hud.set_research_manager(test_rm)
	hud._refresh_research_ui()

	var status_lbl: Label = hud.get_node_or_null("ResearchMenuPanel/MarginContainer/VBoxContainer/TechStatusLabel")
	if status_lbl == null:
		printerr("FAIL: TechStatusLabel not found in ResearchMenuPanel")
		failures += 1
	else:
		if not "Cần xây dựng Viện Nghiên Cứu Hoàng Gia" in status_lbl.text:
			printerr("FAIL: TechStatusLabel did not warn about missing research hall: %s" % status_lbl.text)
			failures += 1

	# Verify tech buttons are locked closed
	var tech_vbox: VBoxContainer = hud.get_node_or_null("ResearchMenuPanel/MarginContainer/VBoxContainer/ScrollContainer/TechListVBox")
	if tech_vbox != null:
		var all_locked := true
		for child in tech_vbox.get_children():
			if child is Button and not child.disabled:
				all_locked = false
		if not all_locked:
			printerr("FAIL: Not all tech buttons were disabled when research hall is missing")
			failures += 1

	# Restore world_instance research_mgr on HUD
	if world_instance.get("research_mgr") != null:
		hud.set_research_manager(world_instance.research_mgr)

	if failures == 0:
		print("PASS TC-RH.6: HUD build button, signal emission, and research UI warning conform strictly")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-RH.7: WorldView Lifecycle, Placement Execution & Save/Load Persistence
# -----------------------------------------------------------------------------
func _test_tc_rh_7_worldview_and_save_load() -> bool:
	print("--- Running TC-RH.7: WorldView Lifecycle & Save/Load Persistence ---")
	var failures: int = 0

	if world_instance == null:
		printerr("FAIL: world_instance is null")
		return false

	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	if rm != null:
		rm.add_resource(EconomyConfig.RES_WOOD, 200)
		rm.add_resource(EconomyConfig.RES_STONE, 100)

	# Verify initial research hall state in WorldView
	if BuildingSystem.is_research_hall_active(world_instance.world_data):
		printerr("FAIL: WorldView started with active research hall unexpectedly")
		failures += 1
	if world_instance.research_mgr.has_active_hall():
		printerr("FAIL: WorldView research_mgr has_active_hall should initially be false")
		failures += 1

	# Find valid 3x3 location
	var target_cell := Vector2i(10, 10)
	var found_cell := false
	for x in range(8, 24):
		for y in range(8, 24):
			var c := Vector2i(x, y)
			var check = BuildingSystem.can_place_building("research_hall", c, world_instance.world_data, rm)
			if check.get("valid", false):
				target_cell = c
				found_cell = true
				break
		if found_cell:
			break

	if not found_cell:
		printerr("FAIL: Could not find valid 3x3 location for research_hall in world_instance")
		failures += 1
		return false

	# Execute placement via WorldView
	world_instance.placing_building_type = "research_hall"
	var place_res = world_instance._execute_placement(target_cell)
	if not place_res.get("success", false):
		printerr("FAIL: WorldView._execute_placement failed: %s" % place_res.get("reason"))
		failures += 1
		return false

	var b_data_placed = place_res.get("building", {})
	var b_id: String = b_data_placed.get("id", "")

	# Demonstrate premature complete_construction at 0% is rejected
	var premature_ok: bool = world_instance.complete_construction(b_id)
	if premature_ok:
		printerr("FAIL: Premature complete_construction at 0% should be rejected!")
		failures += 1

	# Advance progress through the intended construction path to completion
	var bp_rh: Dictionary = EconomyConfig.BLUEPRINTS.get("research_hall", {})
	var rh_hours: float = float(bp_rh.get("construction_hours", 12.0))
	var adv_res: Dictionary = world_instance.advance_construction_work(b_id, rh_hours)
	if not adv_res.get("completed", false):
		printerr("FAIL: Construction advancement failed for research_hall!")
		failures += 1

	# Verify exact count of research_hall records and visual nodes after placement
	var count_placed_records: int = 0
	for b in world_instance.world_data.buildings:
		if b.get("type") == "research_hall":
			count_placed_records += 1
	if count_placed_records != 1:
		printerr("FAIL: Expected exactly 1 research_hall record in world_data.buildings after placement, got: %d" % count_placed_records)
		failures += 1

	var count_placed_nodes: int = 0
	for child in world_instance.buildings_container.get_children():
		if "research_hall" in child.name:
			count_placed_nodes += 1
	if count_placed_nodes != 1:
		printerr("FAIL: Expected exactly 1 visual research_hall node in buildings_container after placement, got: %d" % count_placed_nodes)
		failures += 1

	# Verify research hall is now active and recognized by research_mgr
	if not BuildingSystem.is_research_hall_active(world_instance.world_data):
		printerr("FAIL: is_research_hall_active should return true after WorldView placement")
		failures += 1
	if not world_instance.research_mgr.has_active_hall():
		printerr("FAIL: world_instance.research_mgr.has_active_hall() should return true after placement")
		failures += 1

	# Start research and advance progress
	var start_ok = world_instance.research_mgr.start_research("crop_rotation", rm)
	if not start_ok:
		printerr("FAIL: Failed to start crop_rotation in WorldView with active hall")
		failures += 1
	world_instance.research_mgr.progress_research(5.0, rm)
	if world_instance.research_mgr.active_progress_hours != 5.0:
		printerr("FAIL: Progress mismatch in WorldView. Expected 5.0, got: %f" % world_instance.research_mgr.active_progress_hours)
		failures += 1

	# Test Save & Load Persistence
	var save_path := "user://test_package_1f_research_hall.json"
	var save_res = SaveManagerScript.save_to_file(world_instance, save_path)
	if not save_res.get("success", false):
		printerr("FAIL: SaveManager.save_to_file failed: %s" % save_res.get("error"))
		failures += 1
		return false

	var load_res = SaveManagerScript.load_from_file(save_path)
	if not load_res.get("success", false):
		printerr("FAIL: SaveManager.load_from_file failed: %s" % load_res.get("error"))
		failures += 1
		return false

	# Verify saved JSON data contains research_hall
	var buildings_saved = load_res["data"].get("buildings", [])
	var hall_found := false
	for b in buildings_saved:
		if b.get("type") == "research_hall" and b.get("cell_x") == target_cell.x and b.get("cell_y") == target_cell.y:
			hall_found = true
			if b.get("size_x") != 3 or b.get("size_y") != 3:
				printerr("FAIL: Saved research_hall has incorrect size: %s" % str(b))
				failures += 1
	if not hall_found:
		printerr("FAIL: research_hall not found in saved buildings data")
		failures += 1

	# Apply loaded state to world_instance
	var apply_res = SaveManagerScript.apply_loaded_state_to_world(world_instance, load_res["data"])
	if not apply_res.get("success", false):
		printerr("FAIL: SaveManager.apply_loaded_state_to_world failed: %s" % apply_res.get("error"))
		failures += 1
		return false

	# Verify exact count of research_hall records and visual nodes after first load
	var count_loaded_records: int = 0
	for b in world_instance.world_data.buildings:
		if b.get("type") == "research_hall":
			count_loaded_records += 1
	if count_loaded_records != 1:
		printerr("FAIL: Expected exactly 1 research_hall record in world_data.buildings after load, got: %d" % count_loaded_records)
		failures += 1

	var count_loaded_nodes: int = 0
	for child in world_instance.buildings_container.get_children():
		if "research_hall" in child.name:
			count_loaded_nodes += 1
	if count_loaded_nodes != 1:
		printerr("FAIL: Expected exactly 1 visual research_hall node in buildings_container after load, got: %d" % count_loaded_nodes)
		failures += 1

	# Re-apply loaded state a second time to verify anti-duplication / idempotency
	var reapply_res = SaveManagerScript.apply_loaded_state_to_world(world_instance, load_res["data"])
	if not reapply_res.get("success", false):
		printerr("FAIL: SaveManager second apply_loaded_state_to_world failed: %s" % reapply_res.get("error"))
		failures += 1
		return false

	var count_reapplied_records: int = 0
	for b in world_instance.world_data.buildings:
		if b.get("type") == "research_hall":
			count_reapplied_records += 1
	if count_reapplied_records != 1:
		printerr("FAIL: Anti-duplication failed: Expected exactly 1 research_hall record in world_data.buildings after re-applying load, got: %d" % count_reapplied_records)
		failures += 1

	var count_reapplied_nodes: int = 0
	for child in world_instance.buildings_container.get_children():
		if "research_hall" in child.name:
			count_reapplied_nodes += 1
	if count_reapplied_nodes != 1:
		printerr("FAIL: Anti-duplication failed: Expected exactly 1 visual research_hall node in buildings_container after re-applying load, got: %d" % count_reapplied_nodes)
		failures += 1

	# Verify post-load state
	if not BuildingSystem.is_research_hall_active(world_instance.world_data):
		printerr("FAIL: Post-load is_research_hall_active should be true")
		failures += 1
	if not world_instance.research_mgr.has_active_hall():
		printerr("FAIL: Post-load research_mgr.has_active_hall() should be true")
		failures += 1
	if world_instance.research_mgr.active_tech_id != "crop_rotation":
		printerr("FAIL: Post-load active_tech_id should be crop_rotation, got: %s" % world_instance.research_mgr.active_tech_id)
		failures += 1
	if world_instance.research_mgr.active_progress_hours != 5.0:
		printerr("FAIL: Post-load active_progress_hours should be 5.0, got: %f" % world_instance.research_mgr.active_progress_hours)
		failures += 1

	# Clean up test save file
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)

	if failures == 0:
		print("PASS TC-RH.7: WorldView placement, hall activation, research progression and save/load persistence fully verified")
		return true
	return false
