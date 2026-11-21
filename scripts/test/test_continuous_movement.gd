extends SceneTree

const WorldViewScene = preload("res://scenes/world/world_view.tscn")
const TacticalUnitScript = preload("res://scripts/military/tactical_unit.gd")
const EnemyTacticalUnitScript = preload("res://scripts/military/enemy_tactical_unit.gd")
const CitizenControllerScript = preload("res://scripts/entities/citizen_controller.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")

var _passed: int = 0
var _failed: int = 0

func _check(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] %s" % msg)
	else:
		_failed += 1
		printerr("  [FAIL] %s" % msg)

class MockTimeMgr extends RefCounted:
	var current_speed: int = 1
	var paused: bool = false
	func is_paused() -> bool:
		return paused or current_speed <= 0

func _init() -> void:
	call_deferred("_run_all")

func _run_all() -> void:
	print("=== KU-POST-MVP-NPC-MOVEMENT-01 TEST SUITE ===")
	var wd := WorldGenerator.generate(12345, WorldGenerator.BATCH03_GENERATOR_VERSION)
	var nav := GridNavigation.new(wd)

	_test_a_path_following(nav)
	_test_b_isometric_direction()
	_test_c_path_safety(wd, nav)
	_test_d_civilian_integration(wd, nav)
	_test_e_military_integration(wd, nav)
	await _test_f_save_load()
	_test_g_performance(nav)

	print("=== CONTINUOUS MOVEMENT SUMMARY: %d PASSED, %d FAILED ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _test_a_path_following(nav: GridNavigation) -> void:
	print("[A] Path Following")
	var pf := ContinuousPathFollower.new()
	var p0 := Vector2i(30, 30)
	var p1 := Vector2i(31, 30)
	var p2 := Vector2i(32, 30)
	var p3 := Vector2i(33, 30)
	pf.set_path([p0, p1, p2, p3], null, IsoMath.map_to_local(p0))

	# 1. Continuous movement between consecutive waypoints
	var start_pos := IsoMath.map_to_local(p0)
	var r1 := pf.advance(start_pos, 9.0)
	_check(not bool(r1["arrived"]) and r1["position"].distance_to(start_pos) > 8.9, "Moves continuously between waypoints without snapping")

	# 2-3. Multiple short waypoints consumed in one update without stopping at intermediate centers
	var r2 := pf.advance(r1["position"], 30.0)
	_check(is_equal_approx(float(r2["moved_dist"]), 30.0), "Consumes full 30px across intermediate waypoints in one frame")

	# 4. Does not overshoot final target
	var end_pos := IsoMath.map_to_local(p3)
	var r3 := pf.advance(r2["position"], 500.0)
	_check(bool(r3["arrived"]) and r3["position"].distance_to(end_pos) < 0.01, "Arrives cleanly without overshooting final target")

	# 5-8. TacticalUnit arrival signal fires once, zero speed & pause freeze, speed mult applied once
	var u := TacticalUnitScript.new()
	var tm := MockTimeMgr.new()
	u.set_custom_time_manager(tm)
	u.current_cell = Vector2i(30, 30)
	u.position = IsoMath.map_to_local(Vector2i(30, 30))
	var arrivals := [0]
	u.unit_reached_destination.connect(func(_id, _c): arrivals[0] += 1)
	u.order_move([Vector2i(31, 30), Vector2i(32, 30)], Vector2i(32, 30))

	var pos_before_zero := u.position
	u.advance_movement(0.5, 0.0, nav)
	_check(u.position == pos_before_zero, "Zero speed_mult does not move actor")

	tm.paused = true
	u.advance_movement(0.5, 1.0, nav)
	_check(u.position == pos_before_zero, "Paused TimeManager freezes movement")
	tm.paused = false

	u.advance_movement(0.2, 1.0, null)
	var d_1x := u.position.distance_to(pos_before_zero)
	u.current_cell = Vector2i(30, 30)
	u.position = pos_before_zero
	u.order_stop()
	u.order_move([Vector2i(31, 30), Vector2i(32, 30)], Vector2i(32, 30))
	u.advance_movement(0.2, 3.0, null)
	var d_3x := u.position.distance_to(pos_before_zero)
	_check(is_equal_approx(d_3x, d_1x * 3.0), "3x speed multiplier scales movement cleanly (1x=%.2f 3x=%.2f)" % [d_1x, d_3x])

	for _i in range(20):
		u.advance_movement(0.2, 1.0, null)
	_check(arrivals[0] == 1, "Arrival signal fires exactly once (count=%d)" % arrivals[0])
	u.free()

func _test_b_isometric_direction() -> void:
	print("[B] Isometric Screen-Space Direction")
	var pf := ContinuousPathFollower.new()
	var dirs := {
		"E": Vector2(10, 0),
		"SE": Vector2(10, 10),
		"S": Vector2(0, 10),
		"SW": Vector2(-10, 10),
		"W": Vector2(-10, 0),
		"NW": Vector2(-10, -10),
		"N": Vector2(0, -10),
		"NE": Vector2(10, -10)
	}
	var all_ok := true
	for k in dirs:
		var d := ContinuousPathFollower.classify_screen_direction(dirs[k], -1)
		if ContinuousPathFollower.dir_to_name(d) != k:
			all_ok = false
	_check(all_ok, "All 8 screen-space directional sectors classify accurately")

	# Logical grid North (0, -1) -> screen (+16, -8) = NE (not N!)
	var grid_n_screen := IsoMath.map_to_local(Vector2i(10, 9)) - IsoMath.map_to_local(Vector2i(10, 10))
	var grid_n_dir := ContinuousPathFollower.dir_to_name(ContinuousPathFollower.classify_screen_direction(grid_n_screen, -1))
	_check(grid_n_dir == "NE", "Logical grid North (0,-1) maps to screen NE (got %s)" % grid_n_dir)

	# Deadzone & idle preservation
	pf.update_facing_from_velocity(Vector2(-12, 0))
	var saved_dir := pf.last_screen_dir
	var saved_flip := pf.last_flip_h
	pf.update_facing_from_velocity(Vector2(0.05, 0.02)) # tiny jitter
	_check(pf.last_screen_dir == saved_dir and pf.last_flip_h == saved_flip, "Dead-zone preserves last facing direction during tiny jitter or idle")

func _test_c_path_safety(wd: WorldGenerator.WorldData, nav: GridNavigation) -> void:
	print("[C] Path Safety & Smoothing")
	# Find an open 6x6 patch on grass and place a single obstacle in the middle
	var origin := Vector2i(30, 30)
	for x in range(28, 36):
		for y in range(28, 36):
			wd.terrain[x][y] = WorldGenerator.TerrainType.GRASS
			wd.occupancy[x][y] = false
	wd.occupancy[32][32] = true # blocked cell
	var raw_path := nav.find_path(Vector2i(30, 32), Vector2i(34, 32))
	var smoothed := ContinuousPathFollower.smooth_cell_path(raw_path, nav)
	_check(smoothed.size() >= 2 and smoothed[-1] == Vector2i(34, 32), "Smoothed path preserves exact destination")

	var hits_blocked := false
	for i in range(smoothed.size() - 1):
		if not ContinuousPathFollower.has_safe_corridor(smoothed[i], smoothed[i + 1], nav):
			hits_blocked = true
	_check(not hits_blocked, "Smoothed corridor never crosses or corner-cuts blocked cell (32,32)")

	# Clear obstacle -> now straight corridor is safe
	wd.occupancy[32][32] = false
	var raw_open := nav.find_path(Vector2i(30, 32), Vector2i(34, 32))
	var smooth_open := ContinuousPathFollower.smooth_cell_path(raw_open, nav)
	_check(smooth_open.size() == 2, "Cleared obstacle allows straight 2-point smoothed corridor")

	# Terrain cost parity: high-cost hill in middle prevents shortcutting across hill
	wd.terrain[32][32] = WorldGenerator.TerrainType.HILLS
	_check(not ContinuousPathFollower.has_safe_corridor(Vector2i(30, 32), Vector2i(34, 32), nav), "Corridor smoothing respects higher-cost terrain")
	wd.terrain[32][32] = WorldGenerator.TerrainType.GRASS

	# Water remains impassable
	wd.terrain[32][32] = WorldGenerator.TerrainType.WATER
	_check(not ContinuousPathFollower.has_safe_corridor(Vector2i(30, 32), Vector2i(34, 32), nav), "Corridor smoothing never crosses water")
	wd.terrain[32][32] = WorldGenerator.TerrainType.GRASS

func _test_d_civilian_integration(wd: WorldGenerator.WorldData, nav: GridNavigation) -> void:
	print("[D] Civilian Integration")
	var cit := CitizenControllerScript.new()
	var tm := MockTimeMgr.new()
	var spr := Sprite2D.new()
	spr.name = "Sprite2D"
	spr.offset = Vector2(-12, -30)
	cit.add_child(spr)
	cit.set("_custom_time_mgr", tm)
	cit.init_citizen("cit_test", "Test", "idle", Vector2i(30, 30), nav, null, null)
	cit.world_data = wd

	var cmd_res: Dictionary = cit.issue_manual_command("move", Vector2i(34, 32))
	_check(bool(cmd_res.get("success", false)), "Manual continuous move command accepted")

	var moved_positions: Array[Vector2] = []
	for _i in range(10):
		cit._process(0.1)
		moved_positions.append(cit.position)
	_check(cit.is_moving_visually and spr.offset.y < -30.0, "Walk visual stride active while citizen translates")

	# Pause stops movement & resets walk stride while preserving facing
	var saved_flip := spr.flip_h
	tm.paused = true
	var pos_paused := cit.position
	cit._process(0.5)
	_check(cit.position == pos_paused and not cit.is_moving_visually and is_equal_approx(spr.offset.y, -30.0) and spr.flip_h == saved_flip, "Pause halts citizen, stops walk stride, preserves facing")
	tm.paused = false

	# Finish route
	for _i in range(60):
		cit._process(0.1)
		if cit.current_state == CitizenControllerScript.State.IDLE:
			break
	_check(cit.current_cell == Vector2i(34, 32) and cit.current_state == CitizenControllerScript.State.IDLE, "Citizen arrives at exact destination and returns to IDLE")
	cit.free()

func _test_e_military_integration(wd: WorldGenerator.WorldData, nav: GridNavigation) -> void:
	print("[E] Military Integration")
	# Player TacticalUnit continuous marching & dynamic reroute
	var u := TacticalUnitScript.new()
	var tm := MockTimeMgr.new()
	u.set_custom_time_manager(tm)
	u._setup_visuals()
	u.current_cell = Vector2i(29, 32)
	u.position = IsoMath.map_to_local(u.current_cell)
	var path := nav.find_path(Vector2i(29, 32), Vector2i(34, 32))
	u.order_move(path, Vector2i(34, 32))

	var prev_pos := u.position
	var no_stalls := true
	for _i in range(5):
		u.advance_movement(0.05, 1.0, nav)
		if u.position.distance_to(prev_pos) < 1.0:
			no_stalls = false
		prev_pos = u.position
	_check(no_stalls and u.is_moving_visually, "Player soldier marches continuously every 50ms without 0.5s tile stalls")

	# Dynamic obstacle placed ahead on (32, 32)
	wd.occupancy[32][32] = true
	for _i in range(60):
		u.advance_movement(0.1, 1.0, nav)
		if u.order_state == TacticalUnitScript.OrderState.IDLE:
			break
	_check(u.current_cell == Vector2i(34, 32), "Player soldier reroutes around dynamic obstacle to destination")
	wd.occupancy[32][32] = false
	u.free()

	# EnemyTacticalUnit continuous movement
	var eu := EnemyTacticalUnitScript.new()
	eu.set_custom_time_manager(tm)
	eu._setup_visuals()
	eu.current_cell = Vector2i(29, 30)
	eu.position = IsoMath.map_to_local(eu.current_cell)
	eu.order_move(nav.find_path(Vector2i(29, 30), Vector2i(33, 30)), Vector2i(33, 30))
	var e_p0 := eu.position
	eu.advance_movement(0.05, 1.0, nav)
	_check(eu.position.distance_to(e_p0) > 1.0, "Enemy soldier moves continuously on 50ms frame")
	eu.free()

func _test_f_save_load() -> void:
	print("[F] Save/Load Mid-Route & Legacy Compatibility")
	var wv := WorldViewScene.instantiate()
	root.add_child(wv)
	await process_frame

	var cit = wv.citizen_list[0]
	var nav_wv: GridNavigation = wv.nav
	var dest: Vector2i = cit.current_cell + Vector2i(3, 0)
	if not nav_wv.is_cell_walkable(dest):
		dest = cit.current_cell
	var moved_mid := false
	if dest != cit.current_cell:
		cit.issue_manual_command("move", dest)
		cit._process(0.15)
		cit._process(0.15)
		moved_mid = cit.position.distance_to(IsoMath.map_to_local(cit.current_cell)) > 0.5
	var saved_pos: Vector2 = cit.position
	var saved_dir: int = int(cit.get("facing_dir"))

	var slot_path := "user://saves/test_continuous_mov_slot.json"
	SaveManagerScript.save_to_file(wv, slot_path)
	var loaded := SaveManagerScript.load_from_file(slot_path)
	var apply_res: Dictionary = SaveManagerScript.apply_loaded_state_to_world(wv, loaded.get("data", loaded))
	_check(bool(apply_res.get("success", false)), "Mid-route save/load applies cleanly")
	var loaded_cit = wv.citizens_by_id.get(cit.citizen_id, null)
	_check(loaded_cit != null and loaded_cit.position.distance_to(saved_pos) < 0.1 and int(loaded_cit.get("facing_dir")) == saved_dir, "Citizen continuous position and facing_dir preserved across save/load (mid=%s)" % str(moved_mid))

	# TacticalUnit serialize/deserialize roundtrip & legacy fallback
	var tu := TacticalUnitScript.new()
	tu.unit_id = "tu_sav"
	tu.current_cell = Vector2i(30, 30)
	tu.target_cell = Vector2i(33, 30)
	tu.order_state = TacticalUnitScript.OrderState.MOVING
	tu.current_path = [Vector2i(31, 30), Vector2i(32, 30), Vector2i(33, 30)]
	tu.position = IsoMath.map_to_local(Vector2i(30, 30)) + Vector2(7.5, 3.75)
	tu.facing_dir = ContinuousPathFollower.ScreenDir.SE
	var tu_dict := tu.serialize()
	var tu2 := TacticalUnitScript.new()
	_check(tu2.deserialize(tu_dict) and tu2.position.distance_to(tu.position) < 0.01 and tu2.facing_dir == tu.facing_dir, "TacticalUnit mid-route continuous position preserved on deserialize")
	tu_dict.erase("pos_x")
	tu_dict.erase("pos_y")
	tu_dict.erase("facing_dir")
	var tu3 := TacticalUnitScript.new()
	_check(tu3.deserialize(tu_dict) and tu3.position.distance_to(IsoMath.map_to_local(Vector2i(30, 30))) < 0.01, "Legacy TacticalUnit save without pos_x/pos_y loads safely")
	tu.free()
	tu2.free()
	tu3.free()

	if FileAccess.file_exists(slot_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path))
	wv.queue_free()
	await process_frame

func _test_g_performance(nav: GridNavigation) -> void:
	print("[G] Performance (100 Continuous Followers)")
	var followers: Array[ContinuousPathFollower] = []
	var positions: Array[Vector2] = []
	var raw := nav.find_path(Vector2i(28, 28), Vector2i(35, 35))
	for _i in range(100):
		var f := ContinuousPathFollower.new()
		f.set_path(raw, nav, IsoMath.map_to_local(Vector2i(28, 28)))
		followers.append(f)
		positions.append(IsoMath.map_to_local(Vector2i(28, 28)))
	var t0 := Time.get_ticks_usec()
	for i in range(100):
		var r := followers[i].advance(positions[i], 2.0)
		positions[i] = r["position"]
		followers[i].update_facing_from_velocity(r["velocity"])
	var elapsed_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	_check(elapsed_ms < 5.0, "100 continuous followers tick in %.3f ms (< 5.0 ms)" % elapsed_ms)
