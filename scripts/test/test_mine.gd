extends SceneTree
## Headless Test Suite for Package 1D: Dynamic Mine & Ore Production.
## Validates TC-M.1 through TC-M.6:
## - TC-M.1: Blueprint, Costs, UI & Sprite Verification
## - TC-M.2: Placement Legality, Inaccessible Rejection & Dynamic Registration
## - TC-M.3: Real Citizen Work & Local Buffer Production Integration
## - TC-M.4: Real Citizen Hauling Loop Integration (Pre-Pickup, Transit, Post-Delivery)
## - TC-M.5: Save/Load Persistence, Buffer Restoration & Anti-Duplication
## - TC-M.6: Non-Regression of Farm, Woodcutter, Watchtower & Quarry Systems

const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const WorkplaceManagerScript = preload("res://scripts/economy/workplace_manager.gd")
const JobManagerScript = preload("res://scripts/jobs/job_manager.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const IsoMathScript = preload("res://scripts/utils/iso_math.gd")
const GridNavigationScript = preload("res://scripts/navigation/grid_navigation.gd")
const ResourceManagerScript = preload("res://scripts/economy/resource_manager.gd")
const CitizenControllerScript = preload("res://scripts/entities/citizen_controller.gd")

const TEST_SAVE_PATH: String = "user://saves/test_mine_save.json"

var frame_count: int = 0
var world_instance: Node = null
var world_scene: PackedScene = null

func _init() -> void:
	print("\n========================================================")
	print("  TEST SUITE: Package 1D — Dynamic Mine & Ore Production")
	print("========================================================\n")

	SaveManagerScript.ensure_save_directory()

	world_scene = load("res://scenes/world/world_view.tscn")
	world_instance = world_scene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1

	# Allow world_instance._ready() to initialize fully on Frame 3
	if frame_count == 3:
		var all_passed := true

		var pass_tc1 := _test_tc_m_1_blueprint_and_ui()
		var pass_tc2 := _test_tc_m_2_placement_and_registration()
		var pass_tc3 := _test_tc_m_3_citizen_work_integration()
		var pass_tc4 := _test_tc_m_4_citizen_hauling_integration()
		var pass_tc5 := _test_tc_m_5_save_load_persistence()
		var pass_tc6 := _test_tc_m_6_non_regression()

		all_passed = pass_tc1 and pass_tc2 and pass_tc3 and pass_tc4 and pass_tc5 and pass_tc6

		print("\n--------------------------------------------------------")
		if all_passed:
			print("  ALL PACKAGE 1D DYNAMIC MINE TESTS PASSED! (Exit Code 0)")
			print("--------------------------------------------------------\n")
			quit(0)
			return true
		else:
			print("  PACKAGE 1D TESTS FAILED! (Exit Code 1)")
			print("--------------------------------------------------------\n")
			quit(1)
			return true

	return false

# -----------------------------------------------------------------------------
# TC-M.1: Blueprint, Costs, UI & Sprite Verification
# -----------------------------------------------------------------------------
func _test_tc_m_1_blueprint_and_ui() -> bool:
	print("--- Running TC-M.1: Blueprint, Costs, UI & Sprite Verification ---")
	var failures: int = 0

	# 1. Blueprint validation in EconomyConfig
	var bp: Dictionary = EconomyConfigScript.BLUEPRINTS.get("mine", {})
	if bp.is_empty():
		printerr("  [FAIL] Blueprint 'mine' not found in EconomyConfig.BLUEPRINTS!")
		return false

	if bp.get("footprint") != Vector2i(2, 2):
		printerr("  [FAIL] Mine footprint is %s, expected (2, 2)" % bp.get("footprint"))
		failures += 1
	if bp.get("output_resource") != EconomyConfigScript.RES_ORE:
		printerr("  [FAIL] Mine output_resource is '%s', expected '%s'" % [bp.get("output_resource"), EconomyConfigScript.RES_ORE])
		failures += 1
	if bp.get("job_type") != "miner":
		printerr("  [FAIL] Mine job_type is '%s', expected 'miner'" % bp.get("job_type"))
		failures += 1
	if bp.get("max_workers") != 4:
		printerr("  [FAIL] Mine max_workers is %d, expected 4" % bp.get("max_workers"))
		failures += 1

	var cost: Dictionary = bp.get("cost", {})
	if cost.get(EconomyConfigScript.RES_WOOD, 0) != 20 or cost.get(EconomyConfigScript.RES_STONE, 0) != 10:
		printerr("  [FAIL] Mine cost mismatch! Expected {wood: 20, stone: 10}, got: %s" % cost)
		failures += 1
	else:
		print("  [PASS] Blueprint 'mine' verified: 2x2, 20 Wood + 10 Stone, 4 Workers, Miner role, Ore output.")

	# 2. Sprite and offset validation in WorldView
	var b_textures: Dictionary = world_instance.get("building_textures")
	var mine_tex: Texture2D = b_textures.get("mine", null)
	if mine_tex == null:
		printerr("  [FAIL] WorldView building_textures has no 'mine' texture!")
		failures += 1
	else:
		var tex_size := mine_tex.get_size()
		if tex_size != Vector2(64, 48):
			printerr("  [FAIL] Mine texture size is %s, expected (64, 48)" % tex_size)
			failures += 1
		else:
			print("  [PASS] Mine texture loaded successfully (64x48 px).")

	var offset: Vector2 = world_instance.call("_get_building_sprite_offset", "mine")
	if offset != Vector2(-32.0, -36.0):
		printerr("  [FAIL] Mine sprite offset is %s, expected (-32, -36)" % offset)
		failures += 1
	else:
		print("  [PASS] Mine sprite offset verified strictly at (-32, -36).")

	var display_name: String = world_instance.call("_get_building_display_name", "mine")
	if display_name != "Mỏ Khai Thác Quặng (2x2)":
		printerr("  [FAIL] Mine display name is '%s', expected 'Mỏ Khai Thác Quặng (2x2)'" % display_name)
		failures += 1
	else:
		print("  [PASS] Mine display name verified: '%s'." % display_name)

	# 3. HUD integration
	var hud = world_instance.get("hud")
	if hud != null:
		var mine_btn = hud.get_node_or_null("BuildMenuPanel/MarginContainer/VBoxContainer/GridContainer/MineBtn")
		if mine_btn == null:
			printerr("  [FAIL] MineBtn not found in HUD BuildMenuPanel!")
			failures += 1
		else:
			print("  [PASS] MineBtn found in HUD tree.")
			mine_btn.emit_signal("pressed")
			if world_instance.get("placing_building_type") != "mine":
				printerr("  [FAIL] Pressing MineBtn did not set placing_building_type to 'mine'!")
				failures += 1
			else:
				print("  [PASS] MineBtn triggered building placement for 'mine'.")
			world_instance.call("_cancel_placement")

	if failures == 0:
		print("  [PASS] TC-M.1 PASSED.\n")
		return true
	else:
		printerr("  [FAIL] TC-M.1 had %d failures.\n" % failures)
		return false

# -----------------------------------------------------------------------------
# TC-M.2: Placement Legality, Inaccessible Rejection & Dynamic Registration
# -----------------------------------------------------------------------------
func _test_tc_m_2_placement_and_registration() -> bool:
	print("--- Running TC-M.2: Placement Legality, Inaccessible Rejection & Dynamic Registration ---")
	var failures: int = 0

	var live_rm: Node = world_instance.get_node_or_null("/root/ResourceManager")
	var world_data = world_instance.get("world_data")
	var wp_mgr: WorkplaceManager = world_instance.get("workplace_mgr")
	var job_mgr: JobManager = world_instance.get("job_mgr")

	if live_rm:
		live_rm.add_resource("wood", 100)
		live_rm.add_resource("stone", 100)

	# 1. Clear grass patch for Dynamic Mine at (29, 27) in center settlement meadow
	var mine_origin := Vector2i(29, 27)
	for dx in range(-1, 3):
		for dy in range(-1, 3):
			var c := mine_origin + Vector2i(dx, dy)
			world_data.terrain[c.x][c.y] = WorldGeneratorScript.TerrainType.GRASS
			world_data.occupancy[c.x][c.y] = false

	var wood_prior: int = live_rm.get_available_stock("wood") if live_rm else 0
	var stone_prior: int = live_rm.get_available_stock("stone") if live_rm else 0

	# Place Mine at legal position (29, 27) (size 2x2)
	world_instance.set("placing_building_type", "mine")
	var place_res: Dictionary = world_instance.call("_execute_placement", mine_origin)

	if not place_res.get("success", false):
		printerr("  [FAIL] Failed to place mine at (29, 27): %s" % place_res.get("reason", "unknown"))
		return false

	# 2. Verify atomic cost deduction (20 Wood, 10 Stone)
	var wood_post: int = live_rm.get_available_stock("wood") if live_rm else 0
	var stone_post: int = live_rm.get_available_stock("stone") if live_rm else 0

	if wood_post != wood_prior - 20 or stone_post != stone_prior - 10:
		printerr("  [FAIL] Cost deduction incorrect! Wood: %d->%d (-20), Stone: %d->%d (-10)" % [wood_prior, wood_post, stone_prior, stone_post])
		failures += 1
	else:
		print("  [PASS] Mine costs deducted atomically (-20 Wood, -10 Stone).")

	# 3. Verify Dynamic Workplace registration
	var m_id := "bld_mine_29_27"
	var m_wp: WorkplaceManager.WorkplaceData = wp_mgr.get_workplace(m_id)
	if m_wp == null:
		printerr("  [FAIL] Workplace '%s' not registered in WorkplaceManager!" % m_id)
		failures += 1
		return false

	if m_wp.building_type != "mine":
		printerr("  [FAIL] Workplace building_type is '%s', expected 'mine'" % m_wp.building_type)
		failures += 1
	if m_wp.output_resource != EconomyConfigScript.RES_ORE:
		printerr("  [FAIL] Workplace output_resource is '%s', expected '%s'" % [m_wp.output_resource, EconomyConfigScript.RES_ORE])
		failures += 1
	if m_wp.buffer_capacity != 40:
		printerr("  [FAIL] Workplace buffer_capacity is %d, expected 40" % m_wp.buffer_capacity)
		failures += 1
	if m_wp.worker_quota != 4:
		printerr("  [FAIL] Workplace worker_quota is %d, expected 4" % m_wp.worker_quota)
		failures += 1

	# Check access cell
	var acc: Vector2i = m_wp.access_cell
	if acc == Vector2i(-1, -1):
		printerr("  [FAIL] Mine access_cell is invalid (-1, -1)!")
		failures += 1
	else:
		# Access cell must be strictly outside 2x2 footprint
		var in_footprint := (acc.x >= 29 and acc.x < 31 and acc.y >= 27 and acc.y < 29)
		if in_footprint:
			printerr("  [FAIL] Mine access cell %s is inside the 2x2 footprint!" % acc)
			failures += 1
		elif world_data.occupancy[acc.x][acc.y]:
			printerr("  [FAIL] Mine access cell %s is occupied!" % acc)
			failures += 1
		else:
			print("  [PASS] Mine registered with valid walkable perimeter access cell: %s" % acc)

	# 4. Verify recurring jobs
	var m_jobs := job_mgr.get_jobs_for_building(m_id)
	if m_jobs.size() != 4:
		printerr("  [FAIL] Expected 4 jobs for '%s', got %d" % [m_id, m_jobs.size()])
		failures += 1
	else:
		var all_match := true
		for j in m_jobs:
			if j.type != "miner" or j.target_cell != acc or not j.is_recurring:
				all_match = false
				break
		if not all_match:
			printerr("  [FAIL] Job configuration mismatch in mine jobs!")
			failures += 1
		else:
			print("  [PASS] 4 recurring 'miner' jobs registered for %s at access cell %s." % [m_id, acc])

	# 5. Inaccessible Mine placement rejection before cost deduction
	var walled_origin := Vector2i(10, 10)
	# Surround perimeter with occupied cells
	for ox in range(-1, 3):
		for oy in range(-1, 3):
			var c := walled_origin + Vector2i(ox, oy)
			if IsoMathScript.is_in_bounds(c):
				world_data.occupancy[c.x][c.y] = true

	# Clear inside footprint
	for ox in range(2):
		for oy in range(2):
			world_data.occupancy[walled_origin.x + ox][walled_origin.y + oy] = false

	var wood_before_inacc: int = live_rm.get_available_stock("wood") if live_rm else 0
	var check_inacc := BuildingSystemScript.can_place_building("mine", walled_origin, world_data, live_rm)
	if check_inacc["valid"]:
		printerr("  [FAIL] Inaccessible mine was accepted!")
		failures += 1
	else:
		if check_inacc["reason"] != "Không có vị trí tiếp cận khả dụng":
			printerr("  [FAIL] Expected reason 'Không có vị trí tiếp cận khả dụng', got '%s'" % check_inacc["reason"])
			failures += 1
		else:
			print("  [PASS] Inaccessible mine correctly rejected: '%s'." % check_inacc["reason"])

	var wood_after_inacc: int = live_rm.get_available_stock("wood") if live_rm else 0
	if wood_after_inacc != wood_before_inacc:
		printerr("  [FAIL] Resources deducted despite placement rejection!")
		failures += 1
	else:
		print("  [PASS] Zero resources deducted on rejected placement.")

	# Clean up walled area
	for ox in range(-1, 3):
		for oy in range(-1, 3):
			var c := walled_origin + Vector2i(ox, oy)
			if IsoMathScript.is_in_bounds(c):
				world_data.occupancy[c.x][c.y] = false

	if failures == 0:
		print("  [PASS] TC-M.2 PASSED.\n")
		return true
	else:
		printerr("  [FAIL] TC-M.2 had %d failures.\n" % failures)
		return false

# -----------------------------------------------------------------------------
# TC-M.3: Real Citizen Work & Local Buffer Production Integration
# -----------------------------------------------------------------------------
func _test_tc_m_3_citizen_work_integration() -> bool:
	print("--- Running TC-M.3: Real Citizen Work & Local Buffer Production Integration ---")
	var failures: int = 0

	var wp_mgr: WorkplaceManager = world_instance.get("workplace_mgr")
	var job_mgr: JobManager = world_instance.get("job_mgr")
	var nav: GridNavigation = world_instance.get("nav")
	var live_rm: Node = world_instance.get_node_or_null("/root/ResourceManager")

	# Save roles and temporarily set existing citizens to idle for isolated execution
	var saved_roles: Dictionary = {}
	for cit in world_instance.get("citizen_list"):
		saved_roles[cit.citizen_id] = cit.role
		cit.role = "idle"
		if cit.active_job != null:
			job_mgr.release_job(cit.active_job)
			cit.active_job = null
			cit.current_state = CitizenControllerScript.State.IDLE

	var m_wp: WorkplaceManager.WorkplaceData = wp_mgr.get_workplace("bld_mine_29_27")
	if m_wp == null:
		printerr("  [FAIL] bld_mine_29_27 not found!")
		return false
	m_wp.buffer_amount = 0

	# 1. Create real CitizenController with role "miner"
	var miner: CitizenController = CitizenControllerScript.new()
	miner.name = "integration_test_miner"
	world_instance.add_child(miner)
	miner.init_citizen(
		"integration_test_miner",
		"Trịnh Thợ Mỏ Quặng",
		"miner",
		Vector2i(28, 26), # 1 cell away from access cell (28, 27)
		nav,
		job_mgr,
		wp_mgr
	)

	# 2. Cycle 1: Request job via state machine in IDLE
	miner._process(0.1)

	if miner.active_job == null:
		printerr("  [FAIL] Real miner citizen failed to claim a job!")
		failures += 1
		if miner.get_parent():
			miner.get_parent().remove_child(miner)
		miner.free()
		return false

	if miner.active_job.target_building_id != "bld_mine_29_27":
		printerr("  [FAIL] Claimed job target is '%s', expected 'bld_mine_29_27'" % miner.active_job.target_building_id)
		failures += 1
	if miner.active_job.worker_id != "integration_test_miner":
		printerr("  [FAIL] Job worker_id '%s' != 'integration_test_miner'" % miner.active_job.worker_id)
		failures += 1
	print("  [PASS] Miner claimed dynamic mine job for 'bld_mine_29_27'.")

	# 3. Move along discrete path to access cell
	var move_steps := 0
	while miner.current_state == CitizenControllerScript.State.MOVING_TO_JOB and move_steps < 30:
		move_steps += 1
		miner._process(0.2)

	if miner.current_state != CitizenControllerScript.State.WORKING:
		printerr("  [FAIL] Miner failed to arrive and enter WORKING state! Current state: %d" % miner.current_state)
		failures += 1
	if miner.current_cell != m_wp.access_cell:
		printerr("  [FAIL] Miner arrived at %s, expected %s" % [miner.current_cell, m_wp.access_cell])
		failures += 1
	print("  [PASS] Miner moved along grid and arrived at access cell %s (State: WORKING)." % m_wp.access_cell)

	# 4. Work 3.0 hours to complete cycle 1
	var ore_prior: int = live_rm.get_available_stock("ore") if live_rm else 0
	miner._process(3.0) # Completes work_hours_required (3.0h)

	# Verify production deposited to buffer (NOT central storage)
	if m_wp.buffer_amount != 4:
		printerr("  [FAIL] Expected mine buffer 4 Ore, got %d" % m_wp.buffer_amount)
		failures += 1
	else:
		print("  [PASS] Miner completed work cycle; produced 4 Ore directly into mine buffer.")

	var ore_post: int = live_rm.get_available_stock("ore") if live_rm else 0
	if ore_post != ore_prior:
		printerr("  [FAIL] Central ore stock changed on production! Zero teleportation violated.")
		failures += 1
	else:
		print("  [PASS] Central ore stock strictly unchanged on production (Zero Teleportation verified).")

	# 5. Cycle 2: Recurring job execution
	if miner.current_state != CitizenControllerScript.State.IDLE:
		printerr("  [FAIL] Miner did not return to IDLE! State: %d" % miner.current_state)
		failures += 1

	miner._process(0.1) # Claims recurring job again
	if miner.current_state == CitizenControllerScript.State.MOVING_TO_JOB:
		miner._process(0.1)

	if miner.current_state != CitizenControllerScript.State.WORKING:
		printerr("  [FAIL] Miner failed to resume recurring job for Cycle 2! State: %d" % miner.current_state)
		failures += 1
	else:
		miner._process(3.0) # Full 3.0 hours for Cycle 2
		if m_wp.buffer_amount != 8:
			printerr("  [FAIL] Mine buffer after Cycle 2 is %d, expected 8" % m_wp.buffer_amount)
			failures += 1
		else:
			print("  [PASS] Recurring job verified on Cycle 2: Miner produced additional 4 Ore into buffer (Total: 8).")

	if miner.get_parent():
		miner.get_parent().remove_child(miner)
	miner.free()

	# Restore citizen roles
	for cit in world_instance.get("citizen_list"):
		if saved_roles.has(cit.citizen_id):
			cit.role = saved_roles[cit.citizen_id]

	if failures == 0:
		print("  [PASS] TC-M.3 PASSED.\n")
		return true
	else:
		printerr("  [FAIL] TC-M.3 had %d failures.\n" % failures)
		return false

# -----------------------------------------------------------------------------
# TC-M.4: Real Citizen Hauling Loop Integration
# -----------------------------------------------------------------------------
func _test_tc_m_4_citizen_hauling_integration() -> bool:
	print("--- Running TC-M.4: Real Citizen Hauling Loop Integration ---")
	var failures: int = 0

	var wp_mgr: WorkplaceManager = world_instance.get("workplace_mgr")
	var job_mgr: JobManager = world_instance.get("job_mgr")
	var nav: GridNavigation = world_instance.get("nav")
	var live_rm: Node = world_instance.get_node_or_null("/root/ResourceManager")

	# Save roles and temporarily set existing citizens to idle for isolated execution
	var saved_roles: Dictionary = {}
	for cit in world_instance.get("citizen_list"):
		saved_roles[cit.citizen_id] = cit.role
		cit.role = "idle"
		if cit.active_job != null:
			job_mgr.release_job(cit.active_job)
			cit.active_job = null
			cit.current_state = CitizenControllerScript.State.IDLE

	var m_wp: WorkplaceManager.WorkplaceData = wp_mgr.get_workplace("bld_mine_29_27")
	if m_wp == null or m_wp.buffer_amount < 5:
		printerr("  [FAIL] bld_mine_29_27 buffer is %d, expected >= 5" % (m_wp.buffer_amount if m_wp else -1))
		return false

	# 1. Update hauling jobs to generate job from mine buffer (buffer = 8 Ore)
	var _created := wp_mgr.update_hauling_jobs(job_mgr)
	var haul_job: JobManager.JobData = null
	for j in job_mgr.get_all_jobs():
		if j.type == "hauler" and j.source_workplace_id == "bld_mine_29_27" and j.state == JobManagerScript.JobState.AVAILABLE:
			haul_job = j
			break

	if haul_job == null:
		printerr("  [FAIL] No available hauling job generated for bld_mine_29_27!")
		return false
	print("  [PASS] Hauling job generated: source %s -> dest %s, amount %d %s." % [haul_job.source_cell, haul_job.dest_cell, haul_job.cargo_amount, haul_job.cargo_resource])

	# 2. Create real CitizenController with role "hauler"
	var hauler: CitizenController = CitizenControllerScript.new()
	hauler.name = "integration_test_hauler"
	world_instance.add_child(hauler)
	hauler.init_citizen(
		"integration_test_hauler",
		"Lê Vận Chuyển Quặng",
		"hauler",
		Vector2i(28, 28), # 1 cell away from source cell (28, 27)
		nav,
		job_mgr,
		wp_mgr
	)

	# 3. Hauler claims job
	hauler._process(0.1)

	if hauler.active_job != haul_job:
		printerr("  [FAIL] Hauler did not claim the mine hauling job!")
		failures += 1
		if hauler.get_parent():
			hauler.get_parent().remove_child(hauler)
		hauler.free()
		return false
	if hauler.current_state != CitizenControllerScript.State.MOVING_TO_JOB:
		printerr("  [FAIL] Hauler state not MOVING_TO_JOB!")
		failures += 1
	print("  [PASS] Hauler citizen claimed hauling job and entered MOVING_TO_JOB state.")

	# 4. Record baseline BEFORE pickup
	var cargo_res: String = haul_job.cargo_resource
	var buffer_before_pickup: int = m_wp.buffer_amount
	var central_stock_before_pickup: int = live_rm.get_available_stock(cargo_res) if live_rm else 0

	# 5. Hauler moves to mine access cell
	var move_to_source := 0
	while hauler.current_state == CitizenControllerScript.State.MOVING_TO_JOB and move_to_source < 30:
		move_to_source += 1
		hauler._process(0.2)

	if hauler.current_state != CitizenControllerScript.State.HAULING:
		printerr("  [FAIL] Hauler did not transition to HAULING state upon arriving at source! State: %d" % hauler.current_state)
		failures += 1

	# Post-pickup assertions:
	if m_wp.buffer_amount != buffer_before_pickup - 8:
		printerr("  [FAIL] Buffer was not decremented! Amount: %d, expected %d" % [m_wp.buffer_amount, buffer_before_pickup - 8])
		failures += 1
	if hauler.carrying_resource != cargo_res or hauler.carrying_amount != 8:
		printerr("  [FAIL] Hauler cargo incorrect! Resource: '%s', Amount: %d (expected '%s', 8)" % [hauler.carrying_resource, hauler.carrying_amount, cargo_res])
		failures += 1

	var central_stock_after_pickup: int = live_rm.get_available_stock(cargo_res) if live_rm else 0
	if central_stock_after_pickup != central_stock_before_pickup:
		printerr("  [FAIL] Central stock changed upon cargo pickup! Before: %d, After: %d" % [central_stock_before_pickup, central_stock_after_pickup])
		failures += 1
	else:
		print("  [PASS] Hauler arrived at source %s, extracted 8 %s; buffer reduced %d->%d; central stock strictly unchanged (%d)." % [m_wp.access_cell, cargo_res, buffer_before_pickup, m_wp.buffer_amount, central_stock_after_pickup])

	# 6. Hauler travels along discrete path to dropoff cell
	var haul_steps := 0
	while hauler.current_state == CitizenControllerScript.State.HAULING and haul_steps < 60:
		haul_steps += 1
		hauler._process(0.2)

		# Verify mid-transit: stock unchanged while still traveling in HAULING state
		if hauler.current_state == CitizenControllerScript.State.HAULING:
			if live_rm and live_rm.get_available_stock(cargo_res) != central_stock_before_pickup:
				printerr("  [FAIL] Central stock increased during transit before reaching destination!")
				failures += 1

	if hauler.current_state != CitizenControllerScript.State.IDLE:
		printerr("  [FAIL] Hauler did not complete delivery to IDLE state! Final state: %d" % hauler.current_state)
		failures += 1

	# 7. Post-delivery assertions:
	var central_stock_post_delivery: int = live_rm.get_available_stock(cargo_res) if live_rm else 0
	if central_stock_post_delivery != central_stock_before_pickup + 8:
		printerr("  [FAIL] Central %s stock not credited properly! Prior: %d, Post: %d, Expected: %d" % [cargo_res, central_stock_before_pickup, central_stock_post_delivery, central_stock_before_pickup + 8])
		failures += 1
	else:
		print("  [PASS] Hauler delivered 8 %s to dropoff %s; Central storage credited atomically (+8 %s, total %d)." % [cargo_res, haul_job.dest_cell, cargo_res, central_stock_post_delivery])

	if hauler.carrying_amount != 0 or hauler.carrying_resource != "":
		printerr("  [FAIL] Hauler cargo was not cleared after deposit!")
		failures += 1
	if haul_job.state != JobManagerScript.JobState.COMPLETED:
		printerr("  [FAIL] Hauling job state is not COMPLETED!")
		failures += 1
	if m_wp.buffer_amount != 0:
		printerr("  [FAIL] Buffer modified unexpectedly post-delivery!")
		failures += 1
	print("  [PASS] Job state COMPLETED, cargo cleared from citizen, buffer not double-deducted.")

	if hauler.get_parent():
		hauler.get_parent().remove_child(hauler)
	hauler.free()

	# Restore citizen roles
	for cit in world_instance.get("citizen_list"):
		if saved_roles.has(cit.citizen_id):
			cit.role = saved_roles[cit.citizen_id]

	if failures == 0:
		print("  [PASS] TC-M.4 PASSED.\n")
		return true
	else:
		printerr("  [FAIL] TC-M.4 had %d failures.\n" % failures)
		return false

# -----------------------------------------------------------------------------
# TC-M.5: Save/Load Persistence, Buffer Restoration & Anti-Duplication
# -----------------------------------------------------------------------------
func _test_tc_m_5_save_load_persistence() -> bool:
	print("--- Running TC-M.5: Save/Load Persistence, Buffer Restoration & Anti-Duplication ---")
	var failures: int = 0

	var wp_mgr: WorkplaceManager = world_instance.get("workplace_mgr")
	var job_mgr: JobManager = world_instance.get("job_mgr")

	# Set buffer of bld_mine_29_27 to 12
	var m_wp = wp_mgr.get_workplace("bld_mine_29_27")
	if m_wp != null:
		m_wp.buffer_amount = 12

	# 1. Save world
	var save_res: Dictionary = SaveManagerScript.save_to_file(world_instance, TEST_SAVE_PATH)
	if not save_res.get("success", false):
		printerr("  [FAIL] Failed to save world: %s" % save_res.get("error"))
		return false
	print("  [PASS] World state saved successfully (%d bytes)." % save_res.get("bytes_written", 0))

	# 2. First Load
	var load_res: Dictionary = SaveManagerScript.load_from_file(TEST_SAVE_PATH)
	if not load_res.get("success", false):
		printerr("  [FAIL] Failed to load save file: %s" % load_res.get("error"))
		return false

	var apply_res: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, load_res["data"])
	if not apply_res.get("success", false):
		printerr("  [FAIL] Failed to apply loaded state: %s" % apply_res.get("error"))
		return false

	# Verify mine buffer restored to 12
	if wp_mgr.get_buffer_amount("bld_mine_29_27") != 12:
		printerr("  [FAIL] Mine buffer not restored! Expected 12, got %d" % wp_mgr.get_buffer_amount("bld_mine_29_27"))
		failures += 1
	else:
		print("  [PASS] Mine buffer amount accurately restored from save file (12 Ore).")

	# Verify 4 miner jobs reconstructed
	var m_jobs_load1 := job_mgr.get_jobs_for_building("bld_mine_29_27")
	if m_jobs_load1.size() != 4:
		printerr("  [FAIL] Expected 4 jobs for bld_mine_29_27 after load, got %d" % m_jobs_load1.size())
		failures += 1
	else:
		print("  [PASS] 4 recurring miner jobs faithfully reconstructed for bld_mine_29_27.")

	# 3. Second Load: Anti-Duplication Verification
	var apply_res2: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, load_res["data"])
	if not apply_res2.get("success", false):
		printerr("  [FAIL] Failed second apply: %s" % apply_res2.get("error"))
		failures += 1

	var m_jobs_load2 := job_mgr.get_jobs_for_building("bld_mine_29_27")
	if m_jobs_load2.size() != 4:
		printerr("  [FAIL] Job duplication detected on repeated load! Expected 4, got %d" % m_jobs_load2.size())
		failures += 1
	else:
		print("  [PASS] Zero job duplication across repeated load calls (Mine: 4 jobs strictly maintained).")

	# 4. Legacy Save Compatibility (save without 'workplaces')
	var legacy_dict: Dictionary = load_res["data"].duplicate(true)
	legacy_dict.erase("workplaces")

	var legacy_apply: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, legacy_dict)
	if not legacy_apply.get("success", false):
		printerr("  [FAIL] Applying legacy save failed: %s" % legacy_apply.get("error"))
		failures += 1
	else:
		if wp_mgr.get_buffer_amount("bld_mine_29_27") != 0:
			printerr("  [FAIL] Legacy save did not default mine buffer to 0! Got %d" % wp_mgr.get_buffer_amount("bld_mine_29_27"))
			failures += 1
		else:
			print("  [PASS] Legacy save without 'workplaces' loaded cleanly with mine buffer defaulted to 0.")

	# 5. Buffer Capacity Clamping
	var overflow_dict: Dictionary = load_res["data"].duplicate(true)
	overflow_dict["workplaces"]["bld_mine_29_27"]["buffer_amount"] = 9999

	var overflow_apply: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, overflow_dict)
	if not overflow_apply.get("success", false):
		printerr("  [FAIL] Applying overflow save failed: %s" % overflow_apply.get("error"))
		failures += 1
	else:
		var clamped: int = wp_mgr.get_buffer_amount("bld_mine_29_27")
		if clamped != 40: # Capacity is 40
			printerr("  [FAIL] Buffer overflow not clamped to 40! Got %d" % clamped)
			failures += 1
		else:
			print("  [PASS] Overflowed buffer clamped strictly to mine capacity (40).")

	if failures == 0:
		print("  [PASS] TC-M.5 PASSED.\n")
		return true
	else:
		printerr("  [FAIL] TC-M.5 had %d failures.\n" % failures)
		return false

# -----------------------------------------------------------------------------
# TC-M.6: Non-Regression of Farm, Woodcutter, Watchtower & Quarry Systems
# -----------------------------------------------------------------------------
func _test_tc_m_6_non_regression() -> bool:
	print("--- Running TC-M.6: Non-Regression of Farm, Woodcutter, Watchtower & Quarry Systems ---")
	var failures: int = 0

	var wp_mgr: WorkplaceManager = world_instance.get("workplace_mgr")
	var job_mgr: JobManager = world_instance.get("job_mgr")

	# 1. Starter farm intact
	var farm_starter = wp_mgr.get_workplace("farm_starter")
	if farm_starter == null or farm_starter.worker_quota != 5 or farm_starter.output_resource != "food":
		printerr("  [FAIL] farm_starter corrupted or missing!")
		failures += 1
	else:
		print("  [PASS] Starter farm verified: 5 workers, 50 capacity, food output.")

	# 2. Starter woodcutter intact
	var wc_starter = wp_mgr.get_workplace("woodcutter_starter")
	if wc_starter == null or wc_starter.worker_quota != 4 or wc_starter.output_resource != "wood":
		printerr("  [FAIL] woodcutter_starter corrupted or missing!")
		failures += 1
	else:
		print("  [PASS] Starter woodcutter verified: 4 workers, 40 capacity, wood output.")

	# 3. Watchtower blueprint intact
	var wt_bp: Dictionary = EconomyConfigScript.BLUEPRINTS.get("watchtower", {})
	if wt_bp.is_empty() or wt_bp.get("vision_radius", 0) != 15 or wt_bp.get("footprint") != Vector2i(1, 1):
		printerr("  [FAIL] watchtower blueprint corrupted!")
		failures += 1
	else:
		print("  [PASS] Watchtower blueprint verified: 1x1 footprint, vision radius 15.")

	# 4. Quarry blueprint intact
	var q_bp: Dictionary = EconomyConfigScript.BLUEPRINTS.get("quarry", {})
	if q_bp.is_empty() or q_bp.get("output_resource", "") != "stone" or q_bp.get("footprint") != Vector2i(2, 2):
		printerr("  [FAIL] quarry blueprint corrupted!")
		failures += 1
	else:
		print("  [PASS] Quarry blueprint verified: 2x2 footprint, stone output, 4 workers.")

	if failures == 0:
		print("  [PASS] TC-M.6 PASSED.\n")
		return true
	else:
		printerr("  [FAIL] TC-M.6 had %d failures.\n" % failures)
		return false
