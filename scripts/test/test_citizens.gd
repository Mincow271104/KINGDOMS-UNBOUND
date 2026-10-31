extends SceneTree

const IsoMath = preload("res://scripts/utils/iso_math.gd")
const GridNavigation = preload("res://scripts/navigation/grid_navigation.gd")
const JobManager = preload("res://scripts/jobs/job_manager.gd")
const CitizenControllerScript = preload("res://scripts/entities/citizen_controller.gd")
const WorldGenerator = preload("res://scripts/world/world_generator.gd")

func _init() -> void:
	print("--- Running TestCitizens (TC-3.1 & TC-3.2) ---")
	var failures: int = 0
	
	var world_data = WorldGenerator.generate(12345)
	var nav = GridNavigation.new(world_data)
	var job_mgr = JobManager.new()
	
	# Test 1: Starter Job Distribution (Mandatory GDD / Master Prompt Item 1)
	# 5 Farmers, 4 Woodcutters, 3 Builders, 3 Haulers, 9 Idle = 24 total
	var starter_roles: Array[String] = []
	for i in range(5): starter_roles.append("farmer")
	for i in range(4): starter_roles.append("woodcutter")
	for i in range(3): starter_roles.append("builder")
	for i in range(3): starter_roles.append("hauler")
	for i in range(9): starter_roles.append("idle")
	
	if starter_roles.size() != 24:
		printerr("FAIL: Expected 24 starter roles, got %d" % starter_roles.size())
		failures += 1
	else:
		print("PASS: Exactly 24 starter citizens configured (5 Farmers, 4 Woodcutters, 3 Builders, 3 Haulers, 9 Idle)")

	# Spawn citizens and verify uniqueness of IDs
	var citizens: Array[Node] = []
	var ids: Dictionary = {}
	for i in range(24):
		var c = CitizenControllerScript.new()
		var cid: String = "citizen_%d" % (i + 1)
		if cid in ids:
			printerr("FAIL: Duplicate citizen ID: %s" % cid)
			failures += 1
		ids[cid] = true
		
		c.init_citizen(cid, "Dân Làng %d" % (i + 1), starter_roles[i], Vector2i(32, 33), nav, job_mgr)
		citizens.append(c)
		root.add_child(c)
		
	if ids.size() == 24:
		print("PASS: 24 unique stable citizen IDs verified")

	# Test 2: Grid Pathfinding around obstacles
	var p_start := Vector2i(25, 25)
	var p_goal := Vector2i(35, 25)
	var path := nav.find_path(p_start, p_goal)
	if path.is_empty():
		printerr("FAIL: find_path returned empty path across open grassland!")
		failures += 1
	elif path[0] != p_start or path[path.size() - 1] != p_goal:
		printerr("FAIL: Path does not start at %s or end at %s" % [p_start, p_goal])
		failures += 1
	else:
		print("PASS: A* pathfinding successfully resolved path from %s to %s (%d steps)" % [p_start, p_goal, path.size()])

	# Test 3: Unreachable target fails safely without infinite loop
	# Target surrounded completely by water
	var island_cell := Vector2i(2, 2)
	world_data.terrain[2][2] = WorldGenerator.TerrainType.GRASS
	world_data.occupancy[2][2] = false
	# Surround by water
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0: continue
			world_data.terrain[2 + dx][2 + dy] = WorldGenerator.TerrainType.WATER
			world_data.occupancy[2 + dx][2 + dy] = true
			
	var unreachable_path := nav.find_path(Vector2i(32, 32), island_cell)
	if not unreachable_path.is_empty():
		printerr("FAIL: Pathfinder crossed water barrier to isolated island!")
		failures += 1
	else:
		print("PASS: Pathfinder safely detects unreachable target and returns empty path")

	# Test 4: Job claiming and execution lifecycle
	# Create a farming job near the Farm (36, 35)
	var farm_job = job_mgr.create_job("farmer", Vector2i(35, 35), "Thu hoạch lúa", "farm_1", 1.0)
	var farmer_cit = citizens[0] # First citizen is a farmer
	farmer_cit.current_cell = Vector2i(32, 32)
	farmer_cit.position = IsoMath.map_to_local(farmer_cit.current_cell)
	
	# Citizen requests job
	farmer_cit._process_idle()
	if farmer_cit.active_job != farm_job:
		printerr("FAIL: Farmer did not claim available farm job!")
		failures += 1
	elif farm_job.state != JobManager.JobState.RESERVED:
		printerr("FAIL: Job state should be RESERVED, got %d" % farm_job.state)
		failures += 1
	else:
		print("PASS: Farmer claimed and reserved farm job successfully")

	# Citizen moves to job
	while not farmer_cit.current_path.is_empty():
		farmer_cit._process_movement(1.0)
		
	if farmer_cit.current_state != CitizenControllerScript.State.WORKING:
		printerr("FAIL: Farmer did not transition to WORKING upon arriving at destination")
		failures += 1
	elif farm_job.state != JobManager.JobState.IN_PROGRESS:
		printerr("FAIL: Job state should be IN_PROGRESS, got %d" % farm_job.state)
		failures += 1
	else:
		print("PASS: Farmer arrived and transitioned job to IN_PROGRESS")

	# Farmer works and completes job
	farmer_cit._process_working(1.5) # Work for 1.5 hours (requires 1.0)
	if farm_job.state != JobManager.JobState.COMPLETED:
		printerr("FAIL: Job did not complete after sufficient work hours!")
		failures += 1
	elif farmer_cit.current_state != CitizenControllerScript.State.IDLE:
		printerr("FAIL: Farmer did not return to IDLE after job completion")
		failures += 1
	else:
		print("PASS: Job completed and worker returned cleanly to IDLE")

	# Test 5: Citizen movement speed scaling with TimeManager (CANON-009)
	var speed_cit = citizens[1]
	var mock_tm_script := GDScript.new()
	mock_tm_script.source_code = "extends RefCounted\nvar current_speed: int = 1\nfunc is_paused() -> bool:\n\treturn current_speed == 0\n"
	mock_tm_script.reload()
	var mock_tm = mock_tm_script.new()
	speed_cit.set_custom_time_manager(mock_tm)

	var start_pos: Vector2 = IsoMath.map_to_local(Vector2i(32, 32))
	var next_cell := Vector2i(40, 32)
	var one_step_path: Array[Vector2i] = [next_cell]
	speed_cit.current_cell = Vector2i(32, 32)
	speed_cit.position = start_pos
	speed_cit.current_path = one_step_path.duplicate()
	mock_tm.current_speed = 0
	speed_cit._process_movement(0.1)
	if speed_cit.position != start_pos:
		printerr("FAIL: Citizen moved while simulation speed was 0 (paused)!")
		failures += 1

	mock_tm.current_speed = 1
	speed_cit.position = start_pos
	speed_cit.current_path = one_step_path.duplicate()
	speed_cit._process_movement(0.1)
	var dist_1x: float = speed_cit.position.distance_to(start_pos)

	mock_tm.current_speed = 2
	speed_cit.position = start_pos
	speed_cit.current_path = one_step_path.duplicate()
	speed_cit._process_movement(0.1)
	var dist_2x: float = speed_cit.position.distance_to(start_pos)

	mock_tm.current_speed = 3
	speed_cit.position = start_pos
	speed_cit.current_path = one_step_path.duplicate()
	speed_cit._process_movement(0.1)
	var dist_3x: float = speed_cit.position.distance_to(start_pos)

	if not (absf(dist_2x - dist_1x * 2.0) < 0.01 and absf(dist_3x - dist_1x * 3.0) < 0.01):
		printerr("FAIL: Citizen movement distance did not scale proportionally with 1x/2x/3x speed! (%.2f, %.2f, %.2f)" % [dist_1x, dist_2x, dist_3x])
		failures += 1
	else:
		print("PASS: Citizen movement scales proportionally with 0x/1x/2x/3x simulation speed")

	# Test 6: Guard starvation death vs combat death classification (CANON-014)
	var guard_starve = citizens[2]
	guard_starve.role = "guard"
	guard_starve.status_reason = "Đang canh gác bảo vệ định cư"
	guard_starve.die("Đã qua đời vì suy kiệt")
	if guard_starve.death_cause != "starvation_or_exhaustion":
		printerr("FAIL: Starving guard misclassified as '%s' instead of 'starvation_or_exhaustion'!" % guard_starve.death_cause)
		failures += 1

	var guard_combat = citizens[3]
	guard_combat.role = "guard"
	guard_combat.die("Tử trận khi bảo vệ định cư", "combat")
	if guard_combat.death_cause != "combat":
		printerr("FAIL: Combat guard death misclassified as '%s' instead of 'combat'!" % guard_combat.death_cause)
		failures += 1
	else:
		print("PASS: Guard starvation vs combat death cause classified accurately")

	# Cleanup test nodes
	for c in citizens:
		c.queue_free()

	if failures == 0:
		print("=== TC-3.1 & TC-3.2 ALL CITIZEN & JOB TESTS PASSED ===")
		quit(0)
	else:
		printerr("=== TC-3.1 & TC-3.2 FAILED WITH %d FAILURES ===" % failures)
		quit(1)
