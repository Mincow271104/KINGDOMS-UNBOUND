extends SceneTree

const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")

func _init() -> void:
	print("--- Running TestWorldGen (TC-1.2) ---")
	var failures: int = 0
	
	var seed_a: int = 12345
	var data_a1 = WorldGeneratorScript.generate(seed_a)
	var data_a2 = WorldGeneratorScript.generate(seed_a)
	var seed_b: int = 99999
	var data_b = WorldGeneratorScript.generate(seed_b)
	
	# Check map size
	if data_a1.terrain.size() != 64 or data_a1.terrain[0].size() != 64:
		printerr("FAIL: Terrain dimensions not 64x64")
		failures += 1
	else:
		print("PASS: Terrain dimensions strictly 64x64")

	# Check starter buildings count
	if data_a1.buildings.size() != 8:
		printerr("FAIL: Expected 8 starter buildings, got %d" % data_a1.buildings.size())
		failures += 1
	else:
		print("PASS: Exactly 8 starter buildings placed (Town Hall, 4 Houses, Farm, Storehouse, Woodcutter)")

	# Check building footprints and non-overlapping
	var occupied_cells: Dictionary = {}
	for bld in data_a1.buildings:
		var origin: Vector2i = bld["cell"]
		var size: Vector2i = bld["size"]
		for ox in range(size.x):
			for oy in range(size.y):
				var cell: Vector2i = origin + Vector2i(ox, oy)
				if cell in occupied_cells:
					printerr("FAIL: Overlapping building cell at %s (Building %s overlaps %s)" % [cell, bld["type"], occupied_cells[cell]])
					failures += 1
				occupied_cells[cell] = bld["type"]
	if failures == 0:
		print("PASS: Zero building footprint collisions detected")

	# Check seed reproducibility: data_a1 vs data_a2 must be 100% identical
	var terrain_diffs: int = 0
	for x in range(64):
		for y in range(64):
			if data_a1.terrain[x][y] != data_a2.terrain[x][y]:
				terrain_diffs += 1
	if terrain_diffs > 0:
		printerr("FAIL: Seed reproducibility failed! %d terrain differences for identical seed" % terrain_diffs)
		failures += 1
	else:
		print("PASS: Identical seed produced 100% identical 64x64 terrain grid")

	if data_a1.props.size() != data_a2.props.size():
		printerr("FAIL: Prop count difference for identical seed (%d vs %d)" % [data_a1.props.size(), data_a2.props.size()])
		failures += 1
	else:
		print("PASS: Identical seed produced identical prop count (%d props)" % data_a1.props.size())

	# Check seed divergence: seed_a vs seed_b must differ
	var divergent_cells: int = 0
	for x in range(64):
		for y in range(64):
			if data_a1.terrain[x][y] != data_b.terrain[x][y]:
				divergent_cells += 1
	if divergent_cells == 0:
		printerr("FAIL: Different seeds produced identical terrain!")
		failures += 1
	else:
		print("PASS: Different seeds produced distinct maps (%d divergent cells)" % divergent_cells)

	if failures == 0:
		print("=== TC-1.2 ALL WORLD GEN & SEED TESTS PASSED ===")
		quit(0)
	else:
		printerr("=== TC-1.2 FAILED WITH %d FAILURES ===" % failures)
		quit(1)
