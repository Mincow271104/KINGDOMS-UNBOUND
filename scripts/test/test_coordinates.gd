extends SceneTree

const IsoMath = preload("res://scripts/utils/iso_math.gd")

func _init() -> void:
	print("--- Running TestCoordinates (TC-1.1) ---")
	var failures: int = 0
	
	# Test 1: Center mapping
	var test_centers: Array[Dictionary] = [
		{"grid": Vector2i(0, 0), "expected_local": Vector2(0, 0)},
		{"grid": Vector2i(1, 0), "expected_local": Vector2(16, 8)},
		{"grid": Vector2i(0, 1), "expected_local": Vector2(-16, 8)},
		{"grid": Vector2i(1, 1), "expected_local": Vector2(0, 16)},
		{"grid": Vector2i(63, 63), "expected_local": Vector2(0, 1008)}
	]
	
	for tc in test_centers:
		var grid: Vector2i = tc["grid"]
		var expected_local: Vector2 = tc["expected_local"]
		var local: Vector2 = IsoMath.map_to_local(grid)
		if local != expected_local:
			printerr("FAIL: map_to_local(%s) = %s, expected %s" % [grid, local, expected_local])
			failures += 1
		else:
			print("PASS: map_to_local(%s) = %s" % [grid, local])
			
		var roundtrip: Vector2i = IsoMath.local_to_map(local)
		if roundtrip != grid:
			printerr("FAIL: local_to_map(%s) = %s, expected %s" % [local, roundtrip, grid])
			failures += 1
		else:
			print("PASS: local_to_map(%s) = %s" % [local, roundtrip])

	# Test 2: Interior points of cell (0, 0)
	var interior_points: Array[Vector2] = [
		Vector2(-8, 0),
		Vector2(0, -4),
		Vector2(8, 0),
		Vector2(0, 4)
	]
	for pt in interior_points:
		var res: Vector2i = IsoMath.local_to_map(pt)
		if res != Vector2i(0, 0):
			printerr("FAIL: Interior point %s mapped to %s, expected (0, 0)" % [pt, res])
			failures += 1
		else:
			print("PASS: Interior point %s -> (0, 0)" % [pt])

	# Test 3: Top vertex of cell (0, 0)
	var top_vertex: Vector2 = Vector2(0, -8)
	var top_res: Vector2i = IsoMath.local_to_map(top_vertex)
	if top_res != Vector2i(0, 0):
		printerr("FAIL: Top vertex %s mapped to %s, expected (0, 0)" % [top_vertex, top_res])
		failures += 1
	else:
		print("PASS: Top vertex %s -> (0, 0)" % [top_vertex])

	# Test 4: Boundary validation (Out of bounds)
	var oob_points: Array[Dictionary] = [
		{"local": Vector2(0, -8.1), "expected_grid": Vector2i(-1, -1)},
		{"local": Vector2(-32, 0), "expected_grid": Vector2i(-1, 1)},
		{"local": Vector2(0, 1024), "expected_grid": Vector2i(64, 64)}
	]
	for oob in oob_points:
		var local_pt: Vector2 = oob["local"]
		var expected: Vector2i = oob["expected_grid"]
		var res: Vector2i = IsoMath.local_to_map(local_pt)
		if res != expected:
			printerr("FAIL: OOB point %s mapped to %s, expected %s" % [local_pt, res, expected])
			failures += 1
		elif IsoMath.is_in_bounds(res):
			printerr("FAIL: OOB point %s (%s) considered in bounds!" % [local_pt, res])
			failures += 1
		else:
			print("PASS: OOB point %s -> %s (correctly detected out of bounds)" % [local_pt, res])

	if failures == 0:
		print("=== TC-1.1 ALL 13 COORDINATE CASES PASSED ===")
		quit(0)
	else:
		printerr("=== TC-1.1 FAILED WITH %d FAILURES ===" % failures)
		quit(1)
