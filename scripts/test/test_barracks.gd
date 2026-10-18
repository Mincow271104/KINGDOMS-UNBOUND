extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — Package 1G: Barracks & Guard Integration
## Covers TC-BR.1 through TC-BR.7 with comprehensive fail-closed assertions:
## TC-BR.1: Blueprint validation & configuration integrity
## TC-BR.2: Placement rules, 3x3 footprint, bounds, water, occupancy, access, and rejection resource preservation
## TC-BR.3: BuildingSystem.is_barracks_active detection (active, paused, damaged, under_construction, planned, destroyed, legacy, specific ID)
## TC-BR.4: Role assignment gating (UI dropdown, WorldView signal, CitizenController fail-closed)
## TC-BR.5: Deterministic guard duty loop, genuine pause test, need decay, urgent needs release, constrained layouts & overlapping perimeter posts
## TC-BR.6: Multi-Barracks regression & downtime behavior (individual building tracking, duty release, role retention, reactivation)
## TC-BR.7: WorldView lifecycle, Save/Load idempotency (double-load verification, inactive barracks, legacy compatibility, zero resource deduction on load)

const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")
const CitizenControllerScript = preload("res://scripts/entities/citizen_controller.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const IsoMathScript = preload("res://scripts/utils/iso_math.gd")
const JobManagerScript = preload("res://scripts/jobs/job_manager.gd")
const GridNavigationScript = preload("res://scripts/navigation/grid_navigation.gd")

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
	print("  STARTING PACKAGE 1G BARRACKS & GUARD TEST SUITE")
	print("========================================================\n")

	var world_scene = load("res://scenes/world/world_view.tscn")
	world_instance = world_scene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1

	if frame_count == 3:
		var pass_tc1 := _test_tc_br_1_blueprint()
		var pass_tc2 := _test_tc_br_2_placement()
		var pass_tc3 := _test_tc_br_3_barracks_detection()
		var pass_tc4 := _test_tc_br_4_role_gating()
		var pass_tc5 := _test_tc_br_5_guard_duty_loop()
		var pass_tc6 := _test_tc_br_6_barracks_downtime_inactivation()
		var pass_tc7 := _test_tc_br_7_worldview_and_save_load()

		all_passed = pass_tc1 and pass_tc2 and pass_tc3 and pass_tc4 and pass_tc5 and pass_tc6 and pass_tc7

		print("\n--------------------------------------------------------")
		if all_passed:
			print("  ALL PACKAGE 1G BARRACKS TESTS PASSED! (Exit Code 0)")
			print("--------------------------------------------------------\n")
			quit(0)
			return true
		else:
			print("  PACKAGE 1G BARRACKS TESTS FAILED! (Exit Code 1)")
			print("--------------------------------------------------------\n")
			quit(1)
			return true

	return false

# -----------------------------------------------------------------------------
# TC-BR.1: Blueprint Validation & Integrity (Fail Closed)
# -----------------------------------------------------------------------------
func _test_tc_br_1_blueprint() -> bool:
	print("--- Running TC-BR.1: Blueprint Validation & Integrity ---")
	var failures: int = 0

	if not EconomyConfig.BLUEPRINTS.has("barracks"):
		printerr("FAIL: EconomyConfig.BLUEPRINTS missing 'barracks' entry")
		failures += 1
		return false

	var bp: Dictionary = EconomyConfig.BLUEPRINTS["barracks"]
	if bp.get("id") != "barracks":
		printerr("FAIL: Expected id 'barracks', got: %s" % bp.get("id"))
		failures += 1

	if bp.get("name_vi") != "Doanh Trại":
		printerr("FAIL: Expected name_vi 'Doanh Trại', got: %s" % bp.get("name_vi"))
		failures += 1

	if bp.get("footprint") != Vector2i(3, 3):
		printerr("FAIL: Expected footprint Vector2i(3, 3), got: %s" % str(bp.get("footprint")))
		failures += 1

	var cost: Dictionary = bp.get("cost", {})
	if cost.get(EconomyConfig.RES_WOOD) != 25 or cost.get(EconomyConfig.RES_STONE) != 20 or cost.get(EconomyConfig.RES_METAL) != 5:
		printerr("FAIL: Expected cost {wood: 25, stone: 20, metal: 5}, got: %s" % str(cost))
		failures += 1

	if bp.get("construction_hours") != 12.0:
		printerr("FAIL: Expected construction_hours 12.0, got: %s" % str(bp.get("construction_hours")))
		failures += 1

	if bp.get("housing_capacity", -1) != 0:
		printerr("FAIL: Expected housing_capacity 0, got: %s" % str(bp.get("housing_capacity")))
		failures += 1

	if bp.get("guard_capacity", -1) != 2:
		printerr("FAIL: Expected guard_capacity 2, got: %s" % str(bp.get("guard_capacity")))
		failures += 1

	if bp.get("max_workers", -1) != 2:
		printerr("FAIL: Expected max_workers 2, got: %s" % str(bp.get("max_workers")))
		failures += 1

	if bp.get("job_type") != "guard":
		printerr("FAIL: Expected job_type 'guard', got: %s" % str(bp.get("job_type")))
		failures += 1

	if not bp.get("storage_bonus", {1: 1}).is_empty():
		printerr("FAIL: Expected empty storage_bonus, got: %s" % str(bp.get("storage_bonus")))
		failures += 1

	if failures == 0:
		print("PASS TC-BR.1: Blueprint validation fully conformant to authoritative spec")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BR.2: Placement Rules, Rejection Coverage & Cost Reservation
# -----------------------------------------------------------------------------
func _test_tc_br_2_placement() -> bool:
	print("--- Running TC-BR.2: Placement Rules, Rejection Coverage & Deductions ---")
	var failures: int = 0

	var world_data = WorldGenerator.generate(42)
	var poor_rm = MockTestResourceManager.new({EconomyConfig.RES_WOOD: 10, EconomyConfig.RES_STONE: 5, EconomyConfig.RES_METAL: 0})
	var rich_rm = MockTestResourceManager.new({EconomyConfig.RES_WOOD: 100, EconomyConfig.RES_STONE: 50, EconomyConfig.RES_METAL: 20})

	# 1. Unaffordable check (can_place_building AND place_building rejection + resource unchanged)
	var wood_before = poor_rm.get_available_stock(EconomyConfig.RES_WOOD)
	var stone_before = poor_rm.get_available_stock(EconomyConfig.RES_STONE)
	var metal_before = poor_rm.get_available_stock(EconomyConfig.RES_METAL)

	var res_poor = BuildingSystem.can_place_building("barracks", Vector2i(20, 20), world_data, poor_rm)
	if res_poor.get("valid", true):
		printerr("FAIL: can_place_building should fail when resources are insufficient")
		failures += 1
	var place_poor = BuildingSystem.place_building("barracks", Vector2i(20, 20), world_data, poor_rm)
	if place_poor.get("success", true):
		printerr("FAIL: place_building should fail when resources are insufficient")
		failures += 1
	if poor_rm.get_available_stock(EconomyConfig.RES_WOOD) != wood_before or poor_rm.get_available_stock(EconomyConfig.RES_STONE) != stone_before or poor_rm.get_available_stock(EconomyConfig.RES_METAL) != metal_before:
		printerr("FAIL: Resources were modified despite rejected placement due to insufficient funds")
		failures += 1

	# 2. Out of bounds check (3x3 footprint at edge)
	wood_before = rich_rm.get_available_stock(EconomyConfig.RES_WOOD)
	var res_oob = BuildingSystem.can_place_building("barracks", Vector2i(63, 63), world_data, rich_rm)
	if res_oob.get("valid", true):
		printerr("FAIL: can_place_building should fail when 3x3 footprint exceeds map bounds")
		failures += 1
	var place_oob = BuildingSystem.place_building("barracks", Vector2i(63, 63), world_data, rich_rm)
	if place_oob.get("success", true):
		printerr("FAIL: place_building should fail when out of bounds")
		failures += 1
	if rich_rm.get_available_stock(EconomyConfig.RES_WOOD) != wood_before:
		printerr("FAIL: Resources modified on out-of-bounds rejection")
		failures += 1

	# 3. Water terrain check
	world_data.terrain[20][20] = WorldGenerator.TerrainType.WATER
	var res_water = BuildingSystem.can_place_building("barracks", Vector2i(20, 20), world_data, rich_rm)
	if res_water.get("valid", true):
		printerr("FAIL: can_place_building should fail on water terrain")
		failures += 1
	var place_water = BuildingSystem.place_building("barracks", Vector2i(20, 20), world_data, rich_rm)
	if place_water.get("success", true):
		printerr("FAIL: place_building should fail on water terrain")
		failures += 1
	if rich_rm.get_available_stock(EconomyConfig.RES_WOOD) != wood_before:
		printerr("FAIL: Resources modified on water terrain rejection")
		failures += 1
	world_data.terrain[20][20] = WorldGenerator.TerrainType.GRASS

	# 4. Occupancy collision on any of the 9 cells
	for ox in range(3):
		for oy in range(3):
			world_data.occupancy[25 + ox][25 + oy] = false
	world_data.occupancy[26][26] = true # Block center cell of 3x3
	var res_occ = BuildingSystem.can_place_building("barracks", Vector2i(25, 25), world_data, rich_rm)
	if res_occ.get("valid", true):
		printerr("FAIL: can_place_building should fail when any of the 9 cells is occupied")
		failures += 1
	var place_occ = BuildingSystem.place_building("barracks", Vector2i(25, 25), world_data, rich_rm)
	if place_occ.get("success", true):
		printerr("FAIL: place_building should fail when occupied")
		failures += 1
	if rich_rm.get_available_stock(EconomyConfig.RES_WOOD) != wood_before:
		printerr("FAIL: Resources modified on occupancy collision rejection")
		failures += 1
	world_data.occupancy[26][26] = false

	# 5. Unavailable access check (all perimeter cells blocked)
	var access_test_origin := Vector2i(10, 10)
	for ox in range(-1, 4):
		for oy in range(-1, 4):
			world_data.occupancy[access_test_origin.x + ox][access_test_origin.y + oy] = true
	# Clear building footprint cells themselves
	for ox in range(3):
		for oy in range(3):
			world_data.occupancy[access_test_origin.x + ox][access_test_origin.y + oy] = false
			world_data.terrain[access_test_origin.x + ox][access_test_origin.y + oy] = WorldGenerator.TerrainType.GRASS

	var res_no_access = BuildingSystem.can_place_building("barracks", access_test_origin, world_data, rich_rm)
	if res_no_access.get("valid", true):
		printerr("FAIL: can_place_building should fail when no perimeter access cell is available")
		failures += 1
	elif res_no_access.get("reason") != "Không có vị trí tiếp cận khả dụng":
		printerr("FAIL: Expected reason 'Không có vị trí tiếp cận khả dụng', got: %s" % res_no_access.get("reason"))
		failures += 1

	var place_no_access = BuildingSystem.place_building("barracks", access_test_origin, world_data, rich_rm)
	if place_no_access.get("success", true):
		printerr("FAIL: place_building should fail when no access cell is available")
		failures += 1
	if rich_rm.get_available_stock(EconomyConfig.RES_WOOD) != wood_before:
		printerr("FAIL: Resources modified on access cell rejection")
		failures += 1

	# Clear access test cells
	for ox in range(-1, 4):
		for oy in range(-1, 4):
			world_data.occupancy[access_test_origin.x + ox][access_test_origin.y + oy] = false

	# 6. Successful atomic placement
	wood_before = rich_rm.get_available_stock(EconomyConfig.RES_WOOD)
	stone_before = rich_rm.get_available_stock(EconomyConfig.RES_STONE)
	metal_before = rich_rm.get_available_stock(EconomyConfig.RES_METAL)
	var place_res = BuildingSystem.place_building("barracks", Vector2i(25, 25), world_data, rich_rm)

	if not place_res.get("success", false):
		printerr("FAIL: place_building failed unexpectedly: %s" % place_res.get("reason"))
		failures += 1
	else:
		if rich_rm.get_available_stock(EconomyConfig.RES_WOOD) != wood_before - 25:
			printerr("FAIL: 25 wood was not deducted correctly")
			failures += 1
		if rich_rm.get_available_stock(EconomyConfig.RES_STONE) != stone_before - 20:
			printerr("FAIL: 20 stone was not deducted correctly")
			failures += 1
		if rich_rm.get_available_stock(EconomyConfig.RES_METAL) != metal_before - 5:
			printerr("FAIL: 5 metal was not deducted correctly")
			failures += 1

		var all_occ: bool = true
		for ox in range(3):
			for oy in range(3):
				if not world_data.occupancy[25 + ox][25 + oy]:
					all_occ = false
		if not all_occ:
			printerr("FAIL: Not all 9 cells were marked as occupied for 3x3 barracks")
			failures += 1

		var b_data = place_res.get("building", {})
		if b_data.get("type") != "barracks" or b_data.get("size") != Vector2i(3, 3) or (b_data.get("state") != "active" and b_data.get("state") != "under_construction"):
			printerr("FAIL: Building data improperly recorded: %s" % str(b_data))
			failures += 1

	poor_rm.queue_free()
	rich_rm.queue_free()

	if failures == 0:
		print("PASS TC-BR.2: Placement rules, bounds, water, occupancy, access and rejection coverage verified")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BR.3: BuildingSystem.is_barracks_active Detection & State Transitions
# -----------------------------------------------------------------------------
func _test_tc_br_3_barracks_detection() -> bool:
	print("--- Running TC-BR.3: BuildingSystem.is_barracks_active Comprehensive State Coverage ---")
	var failures: int = 0

	var world_data = WorldGenerator.generate(123)

	# 1. Null check
	if BuildingSystem.is_barracks_active(null):
		printerr("FAIL: is_barracks_active returned true for null world_data (global)")
		failures += 1
	if BuildingSystem.is_barracks_active(null, "some_id"):
		printerr("FAIL: is_barracks_active returned true for null world_data with id")
		failures += 1

	# 2. Fresh world (no barracks)
	if BuildingSystem.is_barracks_active(world_data):
		printerr("FAIL: is_barracks_active returned true on fresh world with no barracks (global)")
		failures += 1
	if BuildingSystem.is_barracks_active(world_data, "non_existent"):
		printerr("FAIL: is_barracks_active returned true on fresh world with specific id")
		failures += 1

	# 3. Add single barracks across all states:
	var b_data = {
		"id": "bld_barracks_test",
		"type": "barracks",
		"cell": Vector2i(15, 15),
		"size": Vector2i(3, 3),
		"state": "active",
		"health": 100
	}
	world_data.buildings.append(b_data)

	# State 'active' -> true
	if not BuildingSystem.is_barracks_active(world_data):
		printerr("FAIL: is_barracks_active should return true when state is 'active'")
		failures += 1
	if not BuildingSystem.is_barracks_active(world_data, "bld_barracks_test"):
		printerr("FAIL: is_barracks_active should return true for matching active id")
		failures += 1

	# State 'paused' -> false
	b_data["state"] = "paused"
	if BuildingSystem.is_barracks_active(world_data):
		printerr("FAIL: is_barracks_active should return false when state is 'paused'")
		failures += 1
	if BuildingSystem.is_barracks_active(world_data, "bld_barracks_test"):
		printerr("FAIL: is_barracks_active(id) should return false when state is 'paused'")
		failures += 1

	# State 'damaged' -> false
	b_data["state"] = "damaged"
	if BuildingSystem.is_barracks_active(world_data):
		printerr("FAIL: is_barracks_active should return false when state is 'damaged'")
		failures += 1

	# State 'under_construction' -> false
	b_data["state"] = "under_construction"
	if BuildingSystem.is_barracks_active(world_data):
		printerr("FAIL: is_barracks_active should return false when state is 'under_construction'")
		failures += 1

	# State 'planned' -> false
	b_data["state"] = "planned"
	if BuildingSystem.is_barracks_active(world_data):
		printerr("FAIL: is_barracks_active should return false when state is 'planned'")
		failures += 1

	# State 'destroyed' -> false
	b_data["state"] = "destroyed"
	if BuildingSystem.is_barracks_active(world_data):
		printerr("FAIL: is_barracks_active should return false when state is 'destroyed'")
		failures += 1

	# Legacy record without 'state' property -> true (documented default is active)
	b_data.erase("state")
	if not BuildingSystem.is_barracks_active(world_data):
		printerr("FAIL: is_barracks_active should return true for legacy building without state property")
		failures += 1
	if not BuildingSystem.is_barracks_active(world_data, "bld_barracks_test"):
		printerr("FAIL: is_barracks_active(id) should return true for legacy building without state property")
		failures += 1

	# 4. Specific Building ID filtering across multiple Barracks:
	b_data["state"] = "active"
	var b_data_2 = {
		"id": "bld_barracks_2",
		"type": "barracks",
		"cell": Vector2i(25, 25),
		"size": Vector2i(3, 3),
		"state": "paused",
		"health": 100
	}
	world_data.buildings.append(b_data_2)

	# Global active: true because b_data is active
	if not BuildingSystem.is_barracks_active(world_data):
		printerr("FAIL: Global is_barracks_active should be true when one of multiple barracks is active")
		failures += 1
	# Specific active: true for b_data, false for b_data_2
	if not BuildingSystem.is_barracks_active(world_data, "bld_barracks_test"):
		printerr("FAIL: is_barracks_active(bld_barracks_test) should be true")
		failures += 1
	if BuildingSystem.is_barracks_active(world_data, "bld_barracks_2"):
		printerr("FAIL: is_barracks_active(bld_barracks_2) should be false because it is paused")
		failures += 1
	if BuildingSystem.is_barracks_active(world_data, "non_existent_id"):
		printerr("FAIL: is_barracks_active(non_existent_id) should be false")
		failures += 1

	# Clean up test buildings
	world_data.buildings.erase(b_data)
	world_data.buildings.erase(b_data_2)

	if failures == 0:
		print("PASS TC-BR.3: is_barracks_active comprehensive state coverage and building-ID filtering verified")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BR.4: Role Assignment Gating (UI and Controller)
# -----------------------------------------------------------------------------
func _test_tc_br_4_role_gating() -> bool:
	print("--- Running TC-BR.4: Role Assignment Gating (UI and CitizenController) ---")
	var failures: int = 0

	var hud = world_instance.get("hud")
	if hud == null:
		printerr("FAIL: HUD not found in world_instance")
		return false

	var cit = CitizenControllerScript.new()
	var nav = GridNavigationScript.new(world_instance.world_data)
	var jm = JobManagerScript.new()
	cit.init_citizen("cit_test_gate", "Test Citizen", "idle", Vector2i(30, 30), nav, jm, null)
	world_instance.add_child(cit)

	# 1. Without active barracks:
	var state_dict := {"active": false}
	cit.set_barracks_checker(func(_b_id: String = ""): return state_dict["active"])
	hud.set_barracks_checker(func(_b_id: String = ""): return state_dict["active"])

	if hud.is_barracks_active():
		printerr("FAIL: hud.is_barracks_active() should be false when checker returns false")
		failures += 1

	var role_btn: OptionButton = hud.get_node_or_null("CitizenInspectPanel/MarginContainer/VBoxContainer/RoleHBox/RoleOptionBtn")
	if role_btn == null:
		printerr("FAIL: RoleOptionBtn not found in HUD")
		failures += 1
	else:
		if not role_btn.is_item_disabled(7):
			printerr("FAIL: RoleOptionBtn item 7 should be disabled when barracks is not active")
			failures += 1
		if not "Cần Doanh Trại" in role_btn.get_item_text(7):
			printerr("FAIL: RoleOptionBtn item 7 should indicate 'Cần Doanh Trại', got: %s" % role_btn.get_item_text(7))
			failures += 1

	# CitizenController fail closed:
	var set_res: bool = cit.set_role("guard")
	if set_res:
		printerr("FAIL: cit.set_role('guard') should return false when barracks is inactive")
		failures += 1
	if cit.role != "idle":
		printerr("FAIL: Citizen role changed to '%s' despite inactive barracks" % cit.role)
		failures += 1
	if cit.status_reason != "Cần Doanh Trại đang hoạt động":
		printerr("FAIL: Expected status_reason 'Cần Doanh Trại đang hoạt động', got: %s" % cit.status_reason)
		failures += 1

	# Inspect citizen in HUD and attempt selection via UI
	hud.show_citizen_inspector(cit)
	hud._on_role_option_selected(7)
	if cit.role != "idle":
		printerr("FAIL: Citizen role changed via UI selection despite inactive barracks")
		failures += 1

	# 2. With active barracks:
	state_dict["active"] = true
	hud._refresh_role_options()

	if not hud.is_barracks_active():
		printerr("FAIL: hud.is_barracks_active() should be true when checker returns true")
		failures += 1

	if role_btn != null:
		if role_btn.is_item_disabled(7):
			printerr("FAIL: RoleOptionBtn item 7 should be enabled when barracks is active")
			failures += 1
		if not "Vệ Binh (Guard)" in role_btn.get_item_text(7):
			printerr("FAIL: RoleOptionBtn item 7 text should be 'Vệ Binh (Guard)', got: %s" % role_btn.get_item_text(7))
			failures += 1

	var set_ok: bool = cit.set_role("guard")
	if not set_ok:
		printerr("FAIL: cit.set_role('guard') should return true when barracks is active")
		failures += 1
	if cit.role != "guard":
		printerr("FAIL: Citizen role expected 'guard', got: %s" % cit.role)
		failures += 1

	cit.queue_free()

	if failures == 0:
		print("PASS TC-BR.4: Role gating fail-closed at both UI and controller layers")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BR.5: Deterministic Guard Duty Loop, Genuine Pause Test & Need Decay
# -----------------------------------------------------------------------------
func _test_tc_br_5_guard_duty_loop() -> bool:
	print("--- Running TC-BR.5: Guard Duty Loop, Genuine Pause, Needs & Constrained Positions ---")
	var failures: int = 0

	var world_data = WorldGenerator.generate(77)
	var origin := Vector2i(20, 20)
	var size := Vector2i(3, 3)

	for ox in range(-1, size.x + 1):
		for oy in range(-1, size.y + 1):
			var c := origin + Vector2i(ox, oy)
			world_data.terrain[c.x][c.y] = WorldGenerator.TerrainType.GRASS
			world_data.occupancy[c.x][c.y] = false

	for ox in range(size.x):
		for oy in range(size.y):
			world_data.occupancy[origin.x + ox][origin.y + oy] = true

	var nav = GridNavigationScript.new(world_data)
	var jm = JobManagerScript.new()

	var b_data := {
		"id": "bld_barracks_duty_test",
		"type": "barracks",
		"cell": origin,
		"size": size,
		"state": "active"
	}
	world_data.buildings.append(b_data)

	var perimeter = BuildingSystem.find_perimeter_cells(origin, size, world_data, 2)
	var job1 = jm.create_job("guard", perimeter[0], "Canh gác vị trí 1", b_data["id"], 4.0, 2, true)
	var job2 = jm.create_job("guard", perimeter[1], "Canh gác vị trí 2", b_data["id"], 4.0, 2, true)

	var cit = CitizenControllerScript.new()
	cit.init_citizen("cit_guard_loop", "Guard Tester", "idle", origin + Vector2i(5, 5), nav, jm, null)
	cit.set_barracks_checker(func(b_id: String = ""): return BuildingSystem.is_barracks_active(world_data, b_id))
	cit.set_role("guard")
	world_instance.add_child(cit)

	# 1. Process idle: citizen claims job and starts moving
	cit._process_idle()
	if cit.current_state != CitizenControllerScript.State.MOVING_TO_JOB:
		printerr("FAIL: Citizen should be in MOVING_TO_JOB state, got: %d" % cit.current_state)
		failures += 1
	if cit.active_job == null or cit.active_job.type != "guard":
		printerr("FAIL: Citizen did not acquire a guard job")
		failures += 1

	# 2. Arrive at destination: switches to State.GUARDING
	cit.position = IsoMathScript.map_to_local(cit.active_job.target_cell)
	cit.current_cell = cit.active_job.target_cell
	cit.current_path.clear()
	cit._arrive_at_destination()

	if cit.current_state != CitizenControllerScript.State.GUARDING:
		printerr("FAIL: Citizen did not switch to State.GUARDING upon arrival, state: %d" % cit.current_state)
		failures += 1
	if cit.active_job.state != JobManagerScript.JobState.IN_PROGRESS:
		printerr("FAIL: Job state was not set to IN_PROGRESS upon arrival")
		failures += 1
	if cit.status_reason != "Đang canh gác tại Doanh Trại":
		printerr("FAIL: Expected status reason 'Đang canh gác tại Doanh Trại', got: %s" % cit.status_reason)
		failures += 1

	# 3. Fix D: Genuine TimeManager Pause Test
	var tm = world_instance.get_node_or_null("/root/TimeManager")
	var saved_speed: int = tm.current_speed if tm != null else 1
	if tm != null:
		tm.pause()
		if not tm.is_paused():
			printerr("FAIL: TimeManager.is_paused() should be true after pause()")
			failures += 1

	var work_before: float = cit.active_job.work_hours_done
	var pos_before: Vector2 = cit.position

	# Exercise actual citizen processing paths while paused
	cit._process(1.0)
	cit._process_guarding(1.0)

	# Assert job progress and position do not change during pause
	if cit.active_job.work_hours_done != work_before:
		printerr("FAIL: Guard job progressed while paused! Before: %f, After: %f" % [work_before, cit.active_job.work_hours_done])
		failures += 1
	if cit.position != pos_before:
		printerr("FAIL: Citizen moved while paused! Before: %s, After: %s" % [str(pos_before), str(cit.position)])
		failures += 1

	# Restore previous game speed reliably
	if tm != null:
		tm.set_speed(saved_speed)

	# 4. Duty progress while unpaused
	cit._process_guarding(1.0)
	if cit.active_job.work_hours_done != work_before + 1.0:
		printerr("FAIL: Guard job did not advance by 1.0 hr when unpaused. Got: %f" % cit.active_job.work_hours_done)
		failures += 1

	# Complete shift (remaining 3.0 hrs)
	cit._process_guarding(3.0)
	if cit.active_job != null:
		printerr("FAIL: Citizen active_job should be cleared upon shift completion")
		failures += 1
	if cit.current_state != CitizenControllerScript.State.IDLE:
		printerr("FAIL: Citizen should return to IDLE upon shift completion, got: %d" % cit.current_state)
		failures += 1
	if cit.status_reason != "Hoàn thành ca gác, sẵn sàng nhiệm vụ mới":
		printerr("FAIL: Status reason mismatch post-shift: %s" % cit.status_reason)
		failures += 1

	# 5. Fix C: Work-related Need Decay during Guard Duty
	cit.position = IsoMathScript.map_to_local(job1.target_cell)
	cit.current_cell = job1.target_cell
	cit.active_job = job1
	job1.state = JobManagerScript.JobState.IN_PROGRESS
	cit.current_state = CitizenControllerScript.State.GUARDING
	cit.hunger = 20.0
	cit.fatigue = 20.0

	# Call _on_hour_passed
	cit._on_hour_passed(1, 1)
	if is_equal_approx(cit.hunger, 20.0):
		printerr("FAIL: Guarding state did not increase hunger during _on_hour_passed")
		failures += 1
	elif not is_equal_approx(cit.hunger, 24.167):
		printerr("FAIL: Expected hunger ~24.167, got: %f" % cit.hunger)
		failures += 1

	if is_equal_approx(cit.fatigue, 20.0):
		printerr("FAIL: Guarding state did not increase fatigue during _on_hour_passed")
		failures += 1
	elif not is_equal_approx(cit.fatigue, 24.0):
		printerr("FAIL: Expected fatigue ~24.0, got: %f" % cit.fatigue)
		failures += 1

	# 6. Urgent Needs Interruption while Guarding
	cit.hunger = 72.0 # Threshold >= 70
	cit._process_guarding(1.0)
	if cit.active_job != null:
		printerr("FAIL: Active guard job should be released when hunger >= 70")
		failures += 1
	if cit.current_state != CitizenControllerScript.State.SEEKING_FOOD:
		printerr("FAIL: Citizen should switch to SEEKING_FOOD, got: %d" % cit.current_state)
		failures += 1
	if cit.role != "guard":
		printerr("FAIL: Citizen role must remain 'guard' when seeking food, got: %s" % cit.role)
		failures += 1

	# 7. Constrained layout: only 1 valid perimeter post available
	var constr_origin := Vector2i(40, 40)
	for ox in range(-1, 4):
		for oy in range(-1, 4):
			world_data.terrain[constr_origin.x + ox][constr_origin.y + oy] = WorldGenerator.TerrainType.WATER
	# Make footprint and exactly 1 perimeter post walkable
	for ox in range(3):
		for oy in range(3):
			world_data.terrain[constr_origin.x + ox][constr_origin.y + oy] = WorldGenerator.TerrainType.GRASS
			world_data.occupancy[constr_origin.x + ox][constr_origin.y + oy] = true
	var single_valid_post := constr_origin + Vector2i(0, 3)
	world_data.terrain[single_valid_post.x][single_valid_post.y] = WorldGenerator.TerrainType.GRASS
	world_data.occupancy[single_valid_post.x][single_valid_post.y] = false

	var constr_b_data := {
		"id": "bld_barracks_constr",
		"type": "barracks",
		"cell": constr_origin,
		"size": Vector2i(3, 3),
		"state": "active"
	}
	world_data.buildings.append(constr_b_data)

	var constr_jobs = world_instance.register_barracks_jobs(constr_b_data, world_data)
	if constr_jobs.size() != 1:
		printerr("FAIL: Expected exactly 1 guard job for constrained barracks with 1 post, got: %d" % constr_jobs.size())
		failures += 1
	elif constr_jobs[0].target_cell != single_valid_post:
		printerr("FAIL: Constrained job target mismatch. Expected %s, got: %s" % [str(single_valid_post), str(constr_jobs[0].target_cell)])
		failures += 1

	# 8. Overlapping Barracks Perimeter Posts Test
	var bld_near_1 := {
		"id": "bld_barracks_near_1",
		"type": "barracks",
		"cell": Vector2i(4, 4),
		"size": Vector2i(3, 3),
		"state": "active"
	}
	var bld_near_2 := {
		"id": "bld_barracks_near_2",
		"type": "barracks",
		"cell": Vector2i(8, 4), # Separated by 1 cell (x=7 is shared perimeter boundary)
		"size": Vector2i(3, 3),
		"state": "active"
	}
	for ox in range(2, 13):
		for oy in range(2, 9):
			world_data.terrain[ox][oy] = WorldGenerator.TerrainType.GRASS
			world_data.occupancy[ox][oy] = false

	for ox in range(3):
		for oy in range(3):
			world_data.occupancy[4 + ox][4 + oy] = true
			world_data.occupancy[8 + ox][4 + oy] = true

	world_data.buildings.append(bld_near_1)
	world_data.buildings.append(bld_near_2)

	var near_jobs_1 = world_instance.register_barracks_jobs(bld_near_1, world_data)
	var near_jobs_2 = world_instance.register_barracks_jobs(bld_near_2, world_data)

	if near_jobs_1.size() > 2 or near_jobs_2.size() > 2:
		printerr("FAIL: Guard jobs exceeded configured capacity (2)")
		failures += 1

	var all_near_cells: Array[Vector2i] = []
	for j in near_jobs_1:
		all_near_cells.append(j.target_cell)
	for j in near_jobs_2:
		if all_near_cells.has(j.target_cell):
			printerr("FAIL: Conflicting overlapping guard post detected between barracks: %s" % str(j.target_cell))
			failures += 1
		all_near_cells.append(j.target_cell)

	# 9. Guard Post Becomes Occupied
	cit.position = IsoMathScript.map_to_local(job2.target_cell)
	cit.current_cell = job2.target_cell
	cit.active_job = job2
	job2.state = JobManagerScript.JobState.IN_PROGRESS
	cit.current_state = CitizenControllerScript.State.GUARDING
	cit.hunger = 10.0
	cit.fatigue = 10.0

	# Mark the post occupied
	world_data.occupancy[job2.target_cell.x][job2.target_cell.y] = true
	cit._process_guarding(1.0)
	if cit.active_job != null:
		printerr("FAIL: Guard duty should be released when guard post becomes occupied")
		failures += 1
	if cit.status_reason != "Không thể tiếp cận nơi làm việc (bị chặn đường)":
		printerr("FAIL: Status reason mismatch on occupied post: %s" % cit.status_reason)
		failures += 1

	cit.queue_free()
	world_instance.job_mgr.remove_jobs_for_building("bld_barracks_constr")
	world_instance.job_mgr.remove_jobs_for_building("bld_barracks_near_1")
	world_instance.job_mgr.remove_jobs_for_building("bld_barracks_near_2")
	world_data.buildings.erase(b_data)
	world_data.buildings.erase(constr_b_data)
	world_data.buildings.erase(bld_near_1)
	world_data.buildings.erase(bld_near_2)

	if failures == 0:
		print("PASS TC-BR.5: Guard duty loop, genuine pause test, need decay, urgent needs & unique posts verified")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BR.6: Multi-Barracks Regression & Downtime Behavior (Fix E)
# -----------------------------------------------------------------------------
func _test_tc_br_6_barracks_downtime_inactivation() -> bool:
	print("--- Running TC-BR.6: Multi-Barracks Regression & Downtime Behavior ---")
	var failures: int = 0

	var world_data = WorldGenerator.generate(88)
	var nav = GridNavigationScript.new(world_data)
	var jm = JobManagerScript.new()

	# Create two Barracks records with distinct IDs
	var b_active := {
		"id": "bld_barracks_active",
		"type": "barracks",
		"cell": Vector2i(20, 20),
		"size": Vector2i(3, 3),
		"state": "active"
	}
	var b_paused := {
		"id": "bld_barracks_paused",
		"type": "barracks",
		"cell": Vector2i(30, 20),
		"size": Vector2i(3, 3),
		"state": "paused"
	}
	world_data.buildings.append(b_active)
	world_data.buildings.append(b_paused)

	# Global Guard eligibility is true when active barracks exists
	if not BuildingSystem.is_barracks_active(world_data):
		printerr("FAIL: Global is_barracks_active should be true with one active barracks")
		failures += 1

	# Clear surrounding cells
	for ox in range(-1, 4):
		for oy in range(-1, 4):
			world_data.terrain[20 + ox][20 + oy] = WorldGenerator.TerrainType.GRASS
			world_data.occupancy[20 + ox][20 + oy] = false
			world_data.terrain[30 + ox][20 + oy] = WorldGenerator.TerrainType.GRASS
			world_data.occupancy[30 + ox][20 + oy] = false

	# Register jobs for both buildings
	var job_active = jm.create_job("guard", Vector2i(19, 20), "Canh gác Active", b_active["id"], 4.0, 2, true)
	var job_paused = jm.create_job("guard", Vector2i(29, 20), "Canh gác Paused", b_paused["id"], 4.0, 2, true)

	jm.set_barracks_checker(func(b_id: String = ""): return BuildingSystem.is_barracks_active(world_data, b_id))

	var cit = CitizenControllerScript.new()
	cit.init_citizen("cit_multi_barracks", "Multi-Barracks Guard", "idle", Vector2i(25, 20), nav, jm, null)
	cit.set_barracks_checker(func(b_id: String = ""): return BuildingSystem.is_barracks_active(world_data, b_id))
	cit.set_role("guard")
	world_instance.add_child(cit)

	# 1. Job selection excludes paused barracks job
	# Verify directly that job_paused is not executable
	if jm._is_job_executable(job_paused, null, null, Callable(), nav):
		printerr("FAIL: job_paused should not be executable while its barracks is paused")
		failures += 1

	if not jm._is_job_executable(job_active, null, null, Callable(), nav):
		printerr("FAIL: job_active should be executable while its barracks is active")
		failures += 1

	# Fail-Closed Guard Job Validation (Final Hardening)
	var jm_raw = JobManagerScript.new()
	var job_no_bld_id = jm_raw.create_job("guard", Vector2i(19, 20), "No Building ID", "", 4.0, 2, true)
	var job_with_bld_id = jm_raw.create_job("guard", Vector2i(19, 20), "With Building ID", b_active["id"], 4.0, 2, true)
	var job_nonexistent_bld = jm_raw.create_job("guard", Vector2i(19, 20), "Nonexistent Barracks", "bld_barracks_does_not_exist", 4.0, 2, true)
	var id_aware_cb := func(b_id: String) -> bool: return BuildingSystem.is_barracks_active(world_data, b_id)
	var global_only_cb := func() -> bool: return true

	# 1a. A guard job with no target_building_id is rejected under all circumstances
	if jm_raw._is_job_executable(job_no_bld_id, null, null, Callable(), nav):
		printerr("FAIL: Guard job with empty target_building_id should be rejected (no callbacks)")
		failures += 1
	if jm_raw._is_job_executable(job_no_bld_id, null, null, id_aware_cb, nav):
		printerr("FAIL: Guard job with empty target_building_id should be rejected even with ID-aware filter")
		failures += 1
	jm_raw.set_barracks_checker(id_aware_cb)
	if jm_raw._is_job_executable(job_no_bld_id, null, null, Callable(), nav):
		printerr("FAIL: Guard job with empty target_building_id should be rejected even with ID-aware barracks_checker")
		failures += 1

	# 1b. A guard job with neither manager checker nor custom filter is rejected
	jm_raw.set_barracks_checker(Callable())
	if jm_raw._is_job_executable(job_with_bld_id, null, null, Callable(), nav):
		printerr("FAIL: Guard job with neither checker nor custom_filter should be rejected")
		failures += 1

	# 1c. A checker that only reports global eligibility (0 args), without accepting a building ID, cannot validate an individual guard job
	if jm_raw._is_job_executable(job_with_bld_id, null, null, global_only_cb, nav):
		printerr("FAIL: 0-argument custom_filter should not be able to validate an individual guard job")
		failures += 1
	jm_raw.set_barracks_checker(global_only_cb)
	if jm_raw._is_job_executable(job_with_bld_id, null, null, Callable(), nav):
		printerr("FAIL: 0-argument barracks_checker on manager should not be able to validate an individual guard job")
		failures += 1

	# 1d. A job tied to an inactive or nonexistent Barracks is rejected even while another Barracks is active
	jm_raw.set_barracks_checker(id_aware_cb)
	if jm_raw._is_job_executable(job_paused, null, null, Callable(), nav):
		printerr("FAIL: Guard job for paused barracks should be rejected even when another barracks is active")
		failures += 1
	if jm_raw._is_job_executable(job_nonexistent_bld, null, null, Callable(), nav):
		printerr("FAIL: Guard job for nonexistent barracks should be rejected even when another barracks is active")
		failures += 1

	# 1e. A job tied to a specific active Barracks remains executable and claimable through the correct ID-aware checker
	if not jm_raw._is_job_executable(job_with_bld_id, null, null, Callable(), nav):
		printerr("FAIL: Guard job for active barracks should be executable with ID-aware barracks_checker")
		failures += 1
	if not jm_raw._is_job_executable(job_with_bld_id, null, null, id_aware_cb, nav):
		printerr("FAIL: Guard job for active barracks should be executable with ID-aware custom_filter")
		failures += 1

	# 1f. Verify request_job() behavior with fail-closed checks
	var cit_test_req = CitizenControllerScript.new()
	cit_test_req.init_citizen("cit_req_test", "Request Tester", "idle", Vector2i(21, 20), nav, jm_raw, null)
	cit_test_req.set_role("guard")

	# With no checker, request_job returns null
	jm_raw.set_barracks_checker(Callable())
	var req_no_checker = jm_raw.request_job(cit_test_req.citizen_id, "guard", cit_test_req.current_cell, nav)
	if req_no_checker != null:
		printerr("FAIL: request_job should return null when no checker is available")
		failures += 1

	# With global-only filter (0-argument), request_job returns null
	var req_global_filter = jm_raw.request_job(cit_test_req.citizen_id, "guard", cit_test_req.current_cell, nav, null, null, global_only_cb)
	if req_global_filter != null:
		printerr("FAIL: request_job should return null when filter cannot accept building ID")
		failures += 1

	# With ID-aware checker, request_job claims the active barracks job
	jm_raw.set_barracks_checker(id_aware_cb)
	var req_active = jm_raw.request_job(cit_test_req.citizen_id, "guard", cit_test_req.current_cell, nav)
	if req_active == null or req_active.id != job_with_bld_id.id:
		printerr("FAIL: request_job failed to claim active guard job with ID-aware checker")
		failures += 1
	cit_test_req.queue_free()

	# When requesting work, citizen must claim job_active, NOT job_paused
	cit._process_idle()
	if cit.active_job == null or cit.active_job.id != job_active.id:
		printerr("FAIL: Citizen claimed wrong job. Expected %s, got: %s" % [job_active.id, "null" if cit.active_job == null else cit.active_job.id])
		failures += 1

	# Arrive at duty post
	cit.position = IsoMathScript.map_to_local(job_active.target_cell)
	cit.current_cell = job_active.target_cell
	cit.current_path.clear()
	cit._arrive_at_destination()

	if cit.current_state != CitizenControllerScript.State.GUARDING:
		printerr("FAIL: Citizen should be in GUARDING state")
		failures += 1

	# 2. Deactivating the specific Barracks tied to this job releases duty even when another Barracks is active!
	b_active["state"] = "paused"
	b_paused["state"] = "active" # Swap: another barracks is active, but b_active is paused!

	# Global active is still true!
	if not BuildingSystem.is_barracks_active(world_data):
		printerr("FAIL: Global is_barracks_active should still be true")
		failures += 1

	cit._process_guarding(0.5)

	if cit.active_job != null:
		printerr("FAIL: Active job should have been released because ITS specific barracks was paused")
		failures += 1
	if cit.current_state != CitizenControllerScript.State.IDLE:
		printerr("FAIL: Citizen should return to IDLE upon specific barracks pause")
		failures += 1
	if cit.role != "guard":
		printerr("FAIL: Citizen role must remain 'guard', got: %s" % cit.role)
		failures += 1
	if cit.status_reason != "Cần Doanh Trại đang hoạt động":
		printerr("FAIL: Expected status reason 'Cần Doanh Trại đang hoạt động', got: %s" % cit.status_reason)
		failures += 1

	# 3. Citizen can now claim the other active barracks job
	cit._process_idle()
	if cit.active_job == null or cit.active_job.id != job_paused.id:
		printerr("FAIL: Citizen should now claim job for the currently active barracks")
		failures += 1

	# 4. Reactivation of b_active restores eligibility without duplicate jobs
	b_active["state"] = "active"
	var initial_jobs = world_instance.register_barracks_jobs(b_active, world_data)
	var count_after_first = world_instance.job_mgr.get_jobs_for_building(b_active["id"]).size()
	var reactivated_jobs = world_instance.register_barracks_jobs(b_active, world_data)
	if world_instance.job_mgr.get_jobs_for_building(b_active["id"]).size() != count_after_first:
		printerr("FAIL: Duplicate jobs created on barracks reactivation")
		failures += 1

	cit.queue_free()
	world_instance.job_mgr.remove_jobs_for_building(b_active["id"])
	world_data.buildings.erase(b_active)
	world_data.buildings.erase(b_paused)

	if failures == 0:
		print("PASS TC-BR.6: Multi-barracks tracking, individual duty release and role retention verified")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BR.7: WorldView Lifecycle, Idempotency & Save/Load Persistence (Fix F)
# -----------------------------------------------------------------------------
func _test_tc_br_7_worldview_and_save_load() -> bool:
	print("--- Running TC-BR.7: WorldView Placement, Double-Load Idempotency & Legacy Compatibility ---")
	var failures: int = 0

	if world_instance == null:
		printerr("FAIL: world_instance is null")
		return false

	# 1. Texture and display name checks
	var offset: Vector2 = world_instance._get_building_sprite_offset("barracks")
	if offset != Vector2(-48.0, -56.0):
		printerr("FAIL: Expected offset Vector2(-48.0, -56.0), got: %s" % str(offset))
		failures += 1

	var disp_name: String = world_instance._get_building_display_name("barracks")
	if disp_name != "Doanh Trại (3x3)":
		printerr("FAIL: Expected display name 'Doanh Trại (3x3)', got: %s" % disp_name)
		failures += 1

	# 2. Build menu button in HUD
	var hud = world_instance.get("hud")
	var btn_barracks = hud.get_node_or_null("BuildMenuPanel/MarginContainer/VBoxContainer/GridContainer/BarracksBtn")
	if btn_barracks == null:
		printerr("FAIL: BarracksBtn not found in BuildMenuPanel")
		failures += 1

	# 3. Placement via WorldView._execute_placement
	var rm = world_instance.get_node_or_null("/root/ResourceManager")
	if rm != null:
		rm.add_resource(EconomyConfig.RES_WOOD, 200)
		rm.add_resource(EconomyConfig.RES_STONE, 200)
		rm.add_resource(EconomyConfig.RES_METAL, 50)

	var target_cell := Vector2i(10, 10)
	var found_cell := false
	for x in range(8, 24):
		for y in range(8, 24):
			var c := Vector2i(x, y)
			var check = BuildingSystem.can_place_building("barracks", c, world_instance.world_data, rm)
			if check.get("valid", false):
				target_cell = c
				found_cell = true
				break
		if found_cell:
			break

	if not found_cell:
		printerr("FAIL: Could not find valid 3x3 location for barracks in world_instance")
		failures += 1
		return false

	world_instance.placing_building_type = "barracks"
	var place_res = world_instance._execute_placement(target_cell)
	if not place_res.get("success", false):
		printerr("FAIL: WorldView._execute_placement failed: %s" % place_res.get("reason"))
		failures += 1
		return false

	var b_data = place_res.get("building")
	var b_id: String = b_data.get("id")

	# Demonstrate premature complete_construction at 0% is rejected
	var premature_ok: bool = world_instance.complete_construction(b_id)
	if premature_ok:
		printerr("FAIL: Premature complete_construction at 0% should be rejected!")
		failures += 1

	# Advance progress through the intended construction path to completion
	var bp_br: Dictionary = EconomyConfig.BLUEPRINTS.get("barracks", {})
	var br_hours: float = float(bp_br.get("construction_hours", 12.0))
	var adv_res: Dictionary = world_instance.advance_construction_work(b_id, br_hours)
	if not adv_res.get("completed", false):
		printerr("FAIL: Construction advancement failed for barracks!")
		failures += 1

	var guard_jobs = world_instance.job_mgr.get_jobs_for_building(b_id)
	if guard_jobs.size() != 2:
		printerr("FAIL: Expected exactly 2 guard jobs for barracks, got: %d" % guard_jobs.size())
		failures += 1

	# Assign citizen 1 to Guard role
	var test_cit = world_instance.citizen_list[0]
	test_cit.set_role("guard")
	if test_cit.role != "guard":
		printerr("FAIL: Failed to assign citizen to guard role")
		failures += 1

	# Record resources before save
	var wood_before_save: int = rm.get_available_stock(EconomyConfig.RES_WOOD)
	var stone_before_save: int = rm.get_available_stock(EconomyConfig.RES_STONE)
	var metal_before_save: int = rm.get_available_stock(EconomyConfig.RES_METAL)

	# 4. Save to file
	var save_path := "user://test_package_1g_barracks.json"
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

	# 5. First Load Application
	var apply_res_1 = SaveManagerScript.apply_loaded_state_to_world(world_instance, load_res["data"])
	if not apply_res_1.get("success", false):
		printerr("FAIL: First apply_loaded_state_to_world failed: %s" % apply_res_1.get("error"))
		failures += 1
		return false

	# Assert building record, node count, guard role and jobs
	var count_placed_nodes: int = 0
	for child in world_instance.buildings_container.get_children():
		if "barracks" in child.name:
			count_placed_nodes += 1
	if count_placed_nodes != 1:
		printerr("FAIL: Expected exactly 1 visual barracks node after 1st load, got: %d" % count_placed_nodes)
		failures += 1

	var jobs_load_1 = world_instance.job_mgr.get_jobs_for_building(b_id)
	if jobs_load_1.size() != 2:
		printerr("FAIL: Expected exactly 2 guard jobs after 1st load, got: %d" % jobs_load_1.size())
		failures += 1

	var cit_restored = world_instance.citizens_by_id.get(test_cit.citizen_id)
	if cit_restored == null or cit_restored.role != "guard":
		printerr("FAIL: Citizen guard role was not preserved after 1st load")
		failures += 1

	# Fix F (Requirement 9): Verify load never deducts construction resources again
	if rm.get_available_stock(EconomyConfig.RES_WOOD) != wood_before_save or rm.get_available_stock(EconomyConfig.RES_STONE) != stone_before_save or rm.get_available_stock(EconomyConfig.RES_METAL) != metal_before_save:
		printerr("FAIL: Resources were deducted during load!")
		failures += 1

	# 6. Fix F (Requirements 6 & 7): Double-Load Idempotency Test
	var apply_res_2 = SaveManagerScript.apply_loaded_state_to_world(world_instance, load_res["data"])
	if not apply_res_2.get("success", false):
		printerr("FAIL: Second apply_loaded_state_to_world failed: %s" % apply_res_2.get("error"))
		failures += 1
		return false

	var count_nodes_2: int = 0
	for child in world_instance.buildings_container.get_children():
		if "barracks" in child.name:
			count_nodes_2 += 1
	if count_nodes_2 != 1:
		printerr("FAIL: Node duplication detected after 2nd load! Expected 1, got: %d" % count_nodes_2)
		failures += 1

	var jobs_load_2 = world_instance.job_mgr.get_jobs_for_building(b_id)
	if jobs_load_2.size() != 2:
		printerr("FAIL: Job duplication detected after 2nd load! Expected 2, got: %d" % jobs_load_2.size())
		failures += 1

	if jobs_load_2.size() == 2 and jobs_load_2[0].target_cell == jobs_load_2[1].target_cell:
		printerr("FAIL: Target cell duplicated on 2nd load: %s" % str(jobs_load_2[0].target_cell))
		failures += 1

	if rm.get_available_stock(EconomyConfig.RES_WOOD) != wood_before_save:
		printerr("FAIL: Resources changed on 2nd load application")
		failures += 1

	# 7. Fix F (Requirement 8): Inactive Barracks Save/Load test
	# Modify building record in loaded_data to paused state
	var inactive_save_data = load_res["data"].duplicate(true)
	for b in inactive_save_data["buildings"]:
		if b.get("type") == "barracks":
			b["state"] = "paused"

	var apply_res_inactive = SaveManagerScript.apply_loaded_state_to_world(world_instance, inactive_save_data)
	if not apply_res_inactive.get("success", false):
		printerr("FAIL: Inactive save apply failed")
		failures += 1

	# Inactive barracks must remain paused and must NOT receive executable guard jobs
	if BuildingSystem.is_barracks_active(world_instance.world_data, b_id):
		printerr("FAIL: Inactive barracks became active after load!")
		failures += 1

	var inactive_jobs = world_instance.job_mgr.get_jobs_for_building(b_id)
	if not inactive_jobs.is_empty():
		printerr("FAIL: Inactive barracks received guard jobs on load: %d" % inactive_jobs.size())
		failures += 1

	# 8. Fix F (Requirement 8): Legacy save without Barracks compatibility
	var legacy_save_data = load_res["data"].duplicate(true)
	var legacy_buildings: Array = []
	for b in legacy_save_data["buildings"]:
		if b.get("type") != "barracks":
			legacy_buildings.append(b)
	legacy_save_data["buildings"] = legacy_buildings

	var apply_res_legacy = SaveManagerScript.apply_loaded_state_to_world(world_instance, legacy_save_data)
	if not apply_res_legacy.get("success", false):
		printerr("FAIL: Legacy save without barracks failed to apply: %s" % apply_res_legacy.get("error"))
		failures += 1
	if BuildingSystem.is_barracks_active(world_instance.world_data):
		printerr("FAIL: is_barracks_active should be false on legacy save without barracks")
		failures += 1

	# Clean up save file
	var dir := DirAccess.open("user://")
	if dir and dir.file_exists(save_path):
		dir.remove(save_path)
	if dir and dir.file_exists(save_path + ".bak"):
		dir.remove(save_path + ".bak")

	if failures == 0:
		print("PASS TC-BR.7: WorldView placement, double-load idempotency & legacy compatibility verified")
		return true
	return false
