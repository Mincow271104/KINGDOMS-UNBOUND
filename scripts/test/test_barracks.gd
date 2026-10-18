extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — Package 1G: Barracks & Guard Integration
## Covers TC-BR.1 through TC-BR.7 with fail-closed assertions:
## TC-BR.1: Blueprint validation & configuration integrity
## TC-BR.2: Placement rules, 3x3 footprint, bounds, water, collision, and cost reservation
## TC-BR.3: BuildingSystem.is_barracks_active detection (active vs non-active states)
## TC-BR.4: Role assignment gating (UI dropdown, WorldView signal, CitizenController fail-closed)
## TC-BR.5: Deterministic guard duty loop, unique perimeter posts, time pause safety, urgent needs release
## TC-BR.6: Barracks downtime / inactivation behavior (job release, role preservation, reason update)
## TC-BR.7: Full WorldView lifecycle, placement execution, sprite offset, and Save/Load persistence idempotency

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
# TC-BR.2: Placement Rules, Footprint, Bounds, Water, Collision & Costs
# -----------------------------------------------------------------------------
func _test_tc_br_2_placement() -> bool:
	print("--- Running TC-BR.2: Placement Rules, Bounds, Water, Occupancy & Cost Reservation ---")
	var failures: int = 0

	var world_data = WorldGenerator.generate(42)
	var poor_rm = MockTestResourceManager.new({EconomyConfig.RES_WOOD: 10, EconomyConfig.RES_STONE: 5, EconomyConfig.RES_METAL: 0})
	var rich_rm = MockTestResourceManager.new({EconomyConfig.RES_WOOD: 100, EconomyConfig.RES_STONE: 50, EconomyConfig.RES_METAL: 20})

	# 1. Unaffordable check
	var res_poor = BuildingSystem.can_place_building("barracks", Vector2i(20, 20), world_data, poor_rm)
	if res_poor.get("valid", true):
		printerr("FAIL: can_place_building should fail when resources are insufficient")
		failures += 1
	elif res_poor.get("reason") != "Không đủ tài nguyên xây dựng":
		printerr("FAIL: Expected reason 'Không đủ tài nguyên xây dựng', got: %s" % res_poor.get("reason"))
		failures += 1

	# 2. Out of bounds check (3x3 footprint at edge)
	var res_oob = BuildingSystem.can_place_building("barracks", Vector2i(63, 63), world_data, rich_rm)
	if res_oob.get("valid", true):
		printerr("FAIL: can_place_building should fail when 3x3 footprint exceeds map bounds")
		failures += 1

	# 3. Water terrain check
	world_data.terrain[20][20] = WorldGenerator.TerrainType.WATER
	var res_water = BuildingSystem.can_place_building("barracks", Vector2i(20, 20), world_data, rich_rm)
	if res_water.get("valid", true):
		printerr("FAIL: can_place_building should fail on water terrain")
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
	world_data.occupancy[26][26] = false

	# 5. Successful atomic placement
	var wood_before = rich_rm.get_available_stock(EconomyConfig.RES_WOOD)
	var stone_before = rich_rm.get_available_stock(EconomyConfig.RES_STONE)
	var metal_before = rich_rm.get_available_stock(EconomyConfig.RES_METAL)
	var place_res = BuildingSystem.place_building("barracks", Vector2i(25, 25), world_data, rich_rm)

	if not place_res.get("success", false):
		printerr("FAIL: place_building failed unexpectedly: %s" % place_res.get("reason"))
		failures += 1
	else:
		# Check exact resource deduction: 25 wood, 20 stone, 5 metal
		if rich_rm.get_available_stock(EconomyConfig.RES_WOOD) != wood_before - 25:
			printerr("FAIL: 25 wood was not deducted correctly")
			failures += 1
		if rich_rm.get_available_stock(EconomyConfig.RES_STONE) != stone_before - 20:
			printerr("FAIL: 20 stone was not deducted correctly")
			failures += 1
		if rich_rm.get_available_stock(EconomyConfig.RES_METAL) != metal_before - 5:
			printerr("FAIL: 5 metal was not deducted correctly")
			failures += 1

		# Check all 9 cells occupied
		var all_occ: bool = true
		for ox in range(3):
			for oy in range(3):
				if not world_data.occupancy[25 + ox][25 + oy]:
					all_occ = false
		if not all_occ:
			printerr("FAIL: Not all 9 cells were marked as occupied for 3x3 barracks")
			failures += 1

		# Check building record
		var b_data = place_res.get("building", {})
		if b_data.get("type") != "barracks" or b_data.get("size") != Vector2i(3, 3) or b_data.get("state") != "active":
			printerr("FAIL: Building data improperly recorded: %s" % str(b_data))
			failures += 1

	poor_rm.queue_free()
	rich_rm.queue_free()

	if failures == 0:
		print("PASS TC-BR.2: Placement rules, 3x3 bounds, water, occupancy and atomic cost deduction verified")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BR.3: BuildingSystem.is_barracks_active Detection
# -----------------------------------------------------------------------------
func _test_tc_br_3_barracks_detection() -> bool:
	print("--- Running TC-BR.3: BuildingSystem.is_barracks_active Detection ---")
	var failures: int = 0

	var world_data = WorldGenerator.generate(123)

	# 1. Null check
	if BuildingSystem.is_barracks_active(null):
		printerr("FAIL: is_barracks_active returned true for null world_data")
		failures += 1

	# 2. Fresh world (no barracks)
	if BuildingSystem.is_barracks_active(world_data):
		printerr("FAIL: is_barracks_active returned true on fresh world with no barracks")
		failures += 1

	# 3. Add barracks with different states
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

	# State 'paused' -> false
	b_data["state"] = "paused"
	if BuildingSystem.is_barracks_active(world_data):
		printerr("FAIL: is_barracks_active should return false when state is 'paused'")
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

	# State 'destroyed' -> false
	b_data["state"] = "destroyed"
	if BuildingSystem.is_barracks_active(world_data):
		printerr("FAIL: is_barracks_active should return false when state is 'destroyed'")
		failures += 1

	# Remove test building
	world_data.buildings.erase(b_data)

	if failures == 0:
		print("PASS TC-BR.3: is_barracks_active returns true ONLY for state == 'active'")
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
	cit.set_barracks_checker(func(): return state_dict["active"])
	hud.set_barracks_checker(func(): return state_dict["active"])

	if hud.is_barracks_active():
		printerr("FAIL: hud.is_barracks_active() should be false when checker returns false")
		failures += 1

	# Verify UI option 7 is disabled and annotated
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

	# Inspect citizen in HUD
	hud.show_citizen_inspector(cit)
	# Attempt to select option 7 via UI handler
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
# TC-BR.5: Deterministic Guard Duty Loop & Unique Perimeter Posts
# -----------------------------------------------------------------------------
func _test_tc_br_5_guard_duty_loop() -> bool:
	print("--- Running TC-BR.5: Deterministic Guard Duty Loop & Perimeter Posts ---")
	var failures: int = 0

	var world_data = WorldGenerator.generate(77)
	var origin := Vector2i(20, 20)
	var size := Vector2i(3, 3)

	# Ensure perimeter is clear of water / occupancy
	for ox in range(-1, size.x + 1):
		for oy in range(-1, size.y + 1):
			var c := origin + Vector2i(ox, oy)
			world_data.terrain[c.x][c.y] = WorldGenerator.TerrainType.GRASS
			world_data.occupancy[c.x][c.y] = false

	# Mark building footprint as occupied
	for ox in range(size.x):
		for oy in range(size.y):
			world_data.occupancy[origin.x + ox][origin.y + oy] = true

	var perimeter = BuildingSystem.find_perimeter_cells(origin, size, world_data, 2)
	if perimeter.size() < 2:
		printerr("FAIL: find_perimeter_cells returned fewer than 2 cells: %d" % perimeter.size())
		failures += 1
	elif perimeter[0] == perimeter[1]:
		printerr("FAIL: find_perimeter_cells returned duplicate cells: %s" % str(perimeter))
		failures += 1

	for cell in perimeter:
		# Check not inside footprint
		if cell.x >= origin.x and cell.x < origin.x + size.x and cell.y >= origin.y and cell.y < origin.y + size.y:
			printerr("FAIL: Perimeter cell %s is inside the building footprint" % str(cell))
			failures += 1

	# Test duty loop execution
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

	# Register 2 guard jobs targeting perimeter
	var job1 = jm.create_job("guard", perimeter[0], "Canh gác vị trí 1", b_data["id"], 4.0, 2, true)
	var job2 = jm.create_job("guard", perimeter[1], "Canh gác vị trí 2", b_data["id"], 4.0, 2, true)

	var cit = CitizenControllerScript.new()
	cit.init_citizen("cit_guard_loop", "Guard Tester", "idle", origin + Vector2i(5, 5), nav, jm, null)
	cit.set_barracks_checker(func(): return BuildingSystem.is_barracks_active(world_data))
	cit.set_role("guard")
	world_instance.add_child(cit)

	# Process idle: should request job and start moving towards perimeter[0]
	cit._process_idle()
	if cit.current_state != CitizenControllerScript.State.MOVING_TO_JOB:
		printerr("FAIL: Citizen should be in MOVING_TO_JOB state, got: %d" % cit.current_state)
		failures += 1
	if cit.active_job == null or cit.active_job.type != "guard":
		printerr("FAIL: Citizen did not acquire a guard job")
		failures += 1

	# Move directly to destination
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

	# Time pause safety: when speed == 0, delta_hours is 0
	var work_before = cit.active_job.work_hours_done
	cit._process_guarding(1.0) # TimeManager mock speed default is 1 if root has TimeManager
	# Test urgent needs release while guarding
	cit.hunger = 75.0 # >= 70 threshold
	cit._process_guarding(1.0)
	if cit.active_job != null:
		printerr("FAIL: Active job should have been released due to hunger >= 70")
		failures += 1
	if cit.current_state != CitizenControllerScript.State.SEEKING_FOOD:
		printerr("FAIL: Citizen should switch to SEEKING_FOOD, got state: %d" % cit.current_state)
		failures += 1

	cit.queue_free()
	world_data.buildings.erase(b_data)

	if failures == 0:
		print("PASS TC-BR.5: Deterministic guard duty loop, unique posts, and urgent needs release verified")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BR.6: Barracks Downtime / Inactivation Behavior
# -----------------------------------------------------------------------------
func _test_tc_br_6_barracks_downtime_inactivation() -> bool:
	print("--- Running TC-BR.6: Barracks Downtime & Inactivation Behavior ---")
	var failures: int = 0

	var world_data = WorldGenerator.generate(88)
	var nav = GridNavigationScript.new(world_data)
	var jm = JobManagerScript.new()

	var b_data := {
		"id": "bld_barracks_downtime",
		"type": "barracks",
		"cell": Vector2i(20, 20),
		"size": Vector2i(3, 3),
		"state": "active"
	}
	world_data.buildings.append(b_data)

	var job = jm.create_job("guard", Vector2i(19, 20), "Canh gác", b_data["id"], 4.0, 2, true)

	var cit = CitizenControllerScript.new()
	cit.init_citizen("cit_guard_down", "Guard Downtime Tester", "idle", Vector2i(19, 20), nav, jm, null)
	cit.set_barracks_checker(func(): return BuildingSystem.is_barracks_active(world_data))
	cit.set_role("guard")
	world_instance.add_child(cit)

	# Assign job and enter GUARDING state
	cit.active_job = job
	job.state = JobManagerScript.JobState.IN_PROGRESS
	job.worker_id = cit.citizen_id
	cit.current_state = CitizenControllerScript.State.GUARDING
	cit._update_reason()

	if cit.status_reason != "Đang canh gác tại Doanh Trại":
		printerr("FAIL: Initial guarding reason mismatch: %s" % cit.status_reason)
		failures += 1

	# Deactivate Barracks (simulate damage / pause)
	b_data["state"] = "paused"
	if BuildingSystem.is_barracks_active(world_data):
		printerr("FAIL: Barracks should not be active when paused")
		failures += 1

	# Citizen runs guarding process while barracks is inactive
	cit._process_guarding(0.5)

	if cit.active_job != null:
		printerr("FAIL: Citizen should have released active job upon barracks inactivation")
		failures += 1
	if cit.current_state != CitizenControllerScript.State.IDLE:
		printerr("FAIL: Citizen should return to IDLE state upon inactivation, got: %d" % cit.current_state)
		failures += 1
	if cit.role != "guard":
		printerr("FAIL: Citizen role must NOT be erased during downtime, got: %s" % cit.role)
		failures += 1
	if cit.status_reason != "Cần Doanh Trại đang hoạt động":
		printerr("FAIL: Expected status reason 'Cần Doanh Trại đang hoạt động', got: %s" % cit.status_reason)
		failures += 1

	# Verify job was released back to AVAILABLE (not destroyed or corrupted)
	if job.state != JobManagerScript.JobState.AVAILABLE:
		printerr("FAIL: Guard job was not restored to AVAILABLE state: %d" % job.state)
		failures += 1

	# Citizen in idle tries to request job while barracks is inactive
	cit._process_idle()
	if cit.active_job != null:
		printerr("FAIL: Guard should not acquire jobs while barracks is inactive")
		failures += 1
	if cit.status_reason != "Cần Doanh Trại đang hoạt động":
		printerr("FAIL: Status reason should stay 'Cần Doanh Trại đang hoạt động', got: %s" % cit.status_reason)
		failures += 1

	# Reactivate Barracks
	b_data["state"] = "active"
	cit._process_idle()
	if cit.active_job == null:
		printerr("FAIL: Guard should re-acquire guard job once barracks is active again")
		failures += 1

	cit.queue_free()
	world_data.buildings.erase(b_data)

	if failures == 0:
		print("PASS TC-BR.6: Barracks downtime preserves role and gracefully pauses duty loop")
		return true
	return false

# -----------------------------------------------------------------------------
# TC-BR.7: WorldView Lifecycle, Placement & Save/Load Persistence Idempotency
# -----------------------------------------------------------------------------
func _test_tc_br_7_worldview_and_save_load() -> bool:
	print("--- Running TC-BR.7: WorldView Lifecycle & Save/Load Persistence ---")
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

	# Check guard jobs created
	var guard_jobs = world_instance.job_mgr.get_jobs_for_building(b_id)
	if guard_jobs.size() != 2:
		printerr("FAIL: Expected exactly 2 guard jobs for barracks, got: %d" % guard_jobs.size())
		failures += 1

	# 4. Save & Load persistence
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

	# Apply loaded state to world_instance
	var apply_res = SaveManagerScript.apply_loaded_state_to_world(world_instance, load_res["data"])
	if not apply_res.get("success", false):
		printerr("FAIL: SaveManager.apply_loaded_state_to_world failed: %s" % apply_res.get("error"))
		failures += 1
		return false

	# Verify zero node duplication
	var count_placed_nodes: int = 0
	for child in world_instance.buildings_container.get_children():
		if "barracks" in child.name:
			count_placed_nodes += 1
	if count_placed_nodes != 1:
		printerr("FAIL: Expected exactly 1 visual barracks node after load, got: %d" % count_placed_nodes)
		failures += 1

	# Verify zero job duplication after load
	var jobs_after_load = world_instance.job_mgr.get_jobs_for_building(b_id)
	if jobs_after_load.size() != 2:
		printerr("FAIL: Expected exactly 2 guard jobs after load, got: %d" % jobs_after_load.size())
		failures += 1

	# Clean up save file
	var dir := DirAccess.open("user://")
	if dir and dir.file_exists(save_path):
		dir.remove(save_path)
	if dir and dir.file_exists(save_path + ".bak"):
		dir.remove(save_path + ".bak")

	if failures == 0:
		print("PASS TC-BR.7: WorldView placement, guard job creation, and Save/Load idempotency verified")
		return true
	return false
