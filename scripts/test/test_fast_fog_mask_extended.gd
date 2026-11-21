extends SceneTree

var _failures: Array[String] = []
var _assertions: int = 0

func _assert(cond: bool, msg: String) -> void:
	_assertions += 1
	if not cond:
		_failures.append(msg)
		printerr("[FAIL] ", msg)

func _init() -> void:
	call_deferred("_run")

func _stats_from_samples(samples: Array[float]) -> Dictionary:
	var s := samples.duplicate()
	s.sort()
	var total := 0.0
	for v in s:
		total += v
	var n := s.size()
	var median: float = s[n / 2] if (n % 2 == 1) else (s[n / 2 - 1] + s[n / 2]) * 0.5
	var p95_idx := clampi(int(ceil(float(n) * 0.95)) - 1, 0, n - 1)
	return {
		"avg": snappedf(total / float(maxi(1, n)), 0.001),
		"median": snappedf(median, 0.001),
		"p95": snappedf(s[p95_idx], 0.001),
		"worst": snappedf(s[n - 1], 0.001),
	}

func _check_zero_leaks(fog: FogOfWar, img: Image, label: String) -> void:
	var data := img.get_data()
	var mw := fog.map_width
	var mh := fog.map_height
	var explored_leaks := 0
	var visible_leaks := 0
	for y in range(mh):
		for x in range(mw):
			var st := fog.get_state(Vector2i(x, y))
			var r_byte := int(data[(y * mw + x) * 4])
			if st == FogOfWar.State.EXPLORED and r_byte != 0:
				explored_leaks += 1
			elif st == FogOfWar.State.VISIBLE and r_byte != 0:
				visible_leaks += 1
	_assert(explored_leaks == 0, "%s: zero explored-tile leaks (got %d)" % [label, explored_leaks])
	_assert(visible_leaks == 0, "%s: zero visible-tile leaks (got %d)" % [label, visible_leaks])

func _verify_layer_state(layer: FogCloudLayer, fog: FogOfWar, label: String) -> void:
	var ref_img: Image = layer._sync_full_fog_mask_ref()
	var fast_img: Image = layer._sync_full_fog_mask_fast()
	_assert(ref_img != null and fast_img != null, "%s: non-null mask images" % label)
	if ref_img != null and fast_img != null:
		_assert(ref_img.get_data() == fast_img.get_data(), "%s: exact byte equivalence failed" % label)
		_check_zero_leaks(fog, fast_img, label)

func _run_dim_suite(dim: int) -> Dictionary:
	var tag := "%dx%d" % [dim, dim]
	var fog := FogOfWar.new(dim, dim)
	var layer := FogCloudLayer.new()
	get_root().add_child(layer)
	layer.configure(fog, 12345, FogCloudLayer.DensityPreset.BALANCED)

	# 1. Empty exploration
	_verify_layer_state(layer, fog, tag + " empty")

	# 2. Boundary-adjacent reveals (corners + edge strips)
	fog.reveal_circle(Vector2i(0, 0), 3)
	fog.reveal_circle(Vector2i(dim - 1, 0), 2)
	fog.reveal_circle(Vector2i(0, dim - 1), 2)
	fog.reveal_circle(Vector2i(dim - 1, dim - 1), 3)
	fog.reveal_circle(Vector2i(dim / 2, 0), 2)
	_verify_layer_state(layer, fog, tag + " boundary")

	# 3. Multiple disconnected explored regions + observer degradation + overlapping scout pockets
	fog.reveal_circle(Vector2i(dim / 4, dim / 4), 5)
	fog.reveal_circle(Vector2i(3 * dim / 4, dim / 3), 4)
	fog.reveal_circle(Vector2i(dim / 2, 3 * dim / 4), 6)
	fog.update_observers([], 0)
	fog.reveal_circle(Vector2i(dim / 2, dim / 2), 6)
	fog.reveal_circle(Vector2i(dim / 2 + 3, dim / 2 + 2), 4)
	_verify_layer_state(layer, fog, tag + " disconnected+degraded+overlapping")

	# 4. Repeated reveals
	fog.reveal_circle(Vector2i(dim / 2, dim / 2), 6)
	fog.reveal_circle(Vector2i(dim / 2 + 2, dim / 2 - 1), 4)
	_verify_layer_state(layer, fog, tag + " repeated")

	# 5. Incremental dirty-rect update vs full sync
	layer.sync_full()
	var dirty: Array[Vector2i] = []
	var pocket_center := Vector2i(mini(dim - 5, dim / 2 + 12), mini(dim - 5, dim / 2 + 8))
	for dx in range(-4, 5):
		for dy in range(-4, 5):
			if absi(dx) + absi(dy) <= 4:
				var c := pocket_center + Vector2i(dx, dy)
				if IsoMath.is_in_bounds(c, dim, dim) and fog.is_unexplored(c):
					fog.set_state(c, FogOfWar.State.VISIBLE)
					dirty.append(c)
	var t_inc0 := Time.get_ticks_usec()
	layer.update_dirty_cells(dirty)
	var inc_ms := float(Time.get_ticks_usec() - t_inc0) / 1000.0
	var inc_bytes := layer.get_fog_mask_image().get_data()

	var full_img_after: Image = layer._sync_full_fog_mask_fast()
	var inc_matches_full := (inc_bytes == full_img_after.get_data())
	_assert(inc_matches_full, tag + " inc_matches_full")
	_assert(layer.get_fog_mask_texture() != null and layer.get_fog_mask_texture().get_width() == dim and layer.get_fog_mask_texture().get_height() == dim, tag + " mask texture size")

	# 6. Simulated Save/Load rebuild
	var saved: Array[Vector2i] = []
	for x in range(dim):
		for y in range(dim):
			if fog.is_explored(Vector2i(x, y)):
				saved.append(Vector2i(x, y))
	var fog_loaded := FogOfWar.new(dim, dim)
	for c in saved:
		fog_loaded._grid[c.x][c.y] = FogOfWar.State.EXPLORED
	fog_loaded.recompute_vision([], [{"cell": Vector2i(dim / 2, dim / 2), "radius": 6}])
	layer.configure(fog_loaded, 12345, FogCloudLayer.DensityPreset.BALANCED)
	_verify_layer_state(layer, fog_loaded, tag + " save_load_rebuild")

	# 7. Fully explored map
	for x in range(dim):
		for y in range(dim):
			fog_loaded._grid[x][y] = FogOfWar.State.EXPLORED
	_verify_layer_state(layer, fog_loaded, tag + " fully_explored")

	# 8. Timing benchmark on fog (1 ref sample, 10 fast samples)
	layer.configure(fog, 12345, FogCloudLayer.DensityPreset.BALANCED)
	var t0 := Time.get_ticks_usec()
	layer._sync_full_fog_mask_ref()
	var ref_ms := float(Time.get_ticks_usec() - t0) / 1000.0

	var fast_samples: Array[float] = []
	for _i in range(10):
		var tf0 := Time.get_ticks_usec()
		layer._sync_full_fog_mask_fast()
		fast_samples.append(float(Time.get_ticks_usec() - tf0) / 1000.0)

	layer.queue_free()
	return {
		"dim": tag,
		"ref_ms": snappedf(ref_ms, 0.001),
		"fast_stats": _stats_from_samples(fast_samples),
		"inc_ms": snappedf(inc_ms, 0.001),
		"inc_matches_full": inc_matches_full,
	}

func _run() -> void:
	print("=== Test: Extended Fast Fog Mask (C1.6.1) ===")
	for dim in [64, 128, 256]:
		var res := _run_dim_suite(dim)
		print("RESULT ", JSON.stringify(res))
	await process_frame

	if _failures.is_empty():
		print("PASS: test_fast_fog_mask_extended.gd (%d assertions passed, 0 failed)" % _assertions)
		quit(0)
	else:
		printerr("FAIL: test_fast_fog_mask_extended.gd (%d/%d assertions failed)" % [_failures.size(), _assertions])
		quit(1)
