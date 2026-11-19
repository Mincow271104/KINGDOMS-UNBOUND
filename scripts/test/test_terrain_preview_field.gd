extends SceneTree

var _passed: int = 0
var _failed: int = 0


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] ", msg)
	else:
		_failed += 1
		printerr("  [FAIL] ", msg)


func _init() -> void:
	call_deferred("_run")


func _make_ref_copy(src_field: TerrainPreviewField, fow: FogOfWar = null) -> TerrainPreviewField:
	var ref := TerrainPreviewField.new()
	ref.configure(src_field.map_width, src_field.map_height, src_field.world_seed, src_field.resolution_scale, fow)
	for id in src_field.get_source_ids():
		var s: Dictionary = src_field.get_source(id)
		ref.upsert_source(
			id,
			int(s["category"]),
			s["cell"],
			float(s["preview_radius_px"]),
			float(s["core_radius_px"]),
			s["dir"],
			float(s["oval_x"])
		)
	ref.rebuild_full()
	return ref


func _measure_usec(fn: Callable) -> float:
	var t0 := Time.get_ticks_usec()
	fn.call()
	return float(Time.get_ticks_usec() - t0) / 1000.0


func _run() -> void:
	print("=== TEST SUITE: TerrainPreviewField (C1.9.2 M1) ===")

	# 1. Source lifecycle, duplicate ID, clamping, and FogOfWar non-mutation
	var fow := FogOfWar.new(128, 128)
	var center := Vector2i(64, 64)
	fow.reveal_circle(center, FogOfWar.TOWN_HALL_VISION_RADIUS)
	var fow_snap := PackedByteArray()
	for x in range(128):
		for y in range(128):
			fow_snap.append(fow.get_state(Vector2i(x, y)))

	var field := TerrainPreviewField.new()
	field.configure(128, 128, 12345, 2, fow)
	_assert(field.tex_width == 256 and field.tex_height == 256, "2x resolution configures 256x256 texture for 128x128 map")
	_assert(field.register_source("town_hall", TerrainPreviewField.SourceCategory.TOWN_HALL, center), "register_source('town_hall') succeeds")
	_assert(not field.register_source("town_hall", TerrainPreviewField.SourceCategory.TOWN_HALL, center), "Duplicate register_source('town_hall') returns false")
	_assert(field.get_source_count() == 1, "Source count is 1 after duplicate registration attempt")

	# Edge clamping
	_assert(field.register_source("edge_test", TerrainPreviewField.SourceCategory.SOLDIER, Vector2i(-10, 200)), "Edge out-of-bounds source registers safely")
	var edge_src := field.get_source("edge_test")
	_assert(edge_src["cell"] == Vector2i(0, 127), "Out-of-bounds cell (-10, 200) clamps to (0, 127)")
	_assert(field.remove_source("edge_test"), "remove_source('edge_test') succeeds")
	_assert(not field.remove_source("nonexistent"), "remove_source('nonexistent') returns false")

	field.rebuild_full()

	# 2. Soldier movement: old position stops contributing (zero trail)
	var s_start := Vector2i(30, 30)
	var s_end := Vector2i(95, 95)
	field.register_source("soldier_1", TerrainPreviewField.SourceCategory.SOLDIER, s_start)
	field.apply_incremental_updates()
	_assert(field.is_cell_in_preview(s_start), "Soldier start cell (30,30) is inside preview before move")

	field.update_source("soldier_1", s_end)
	field.apply_incremental_updates()
	_assert(not field.is_cell_in_preview(s_start), "Old soldier position (30,30) stops contributing after move (no trail)")
	_assert(field.is_cell_in_preview(s_end), "New soldier position (95,95) is inside preview after move")
	field.remove_source("soldier_1")
	field.apply_incremental_updates()

	# 3. Overlapping source removal preserves remaining source
	var ov_a := Vector2i(40, 80)
	var ov_b := Vector2i(44, 80)
	field.register_source("ov_a", TerrainPreviewField.SourceCategory.SOLDIER, ov_a)
	field.register_source("ov_b", TerrainPreviewField.SourceCategory.SOLDIER, ov_b)
	field.apply_incremental_updates()
	_assert(field.is_cell_in_preview(ov_a) and field.is_cell_in_preview(ov_b), "Both overlapping sources are in preview")
	field.remove_source("ov_a")
	field.apply_incremental_updates()
	_assert(field.is_cell_in_preview(ov_b), "Removing ov_a preserves ov_b contribution")
	field.remove_source("ov_b")
	field.apply_incremental_updates()

	# 4. Smooth merging of nearby sources & separation of distant sources
	var near_a := Vector2i(64, 64)
	var near_b := Vector2i(74, 60)
	field.register_source("near_b", TerrainPreviewField.SourceCategory.SOLDIER, near_b)
	var far_c := Vector2i(20, 20)
	field.register_source("far_c", TerrainPreviewField.SourceCategory.SOLDIER, far_c)
	field.apply_incremental_updates()
	var mid_far := Vector2i(42, 42)
	_assert(not field.is_cell_in_preview(mid_far), "Distant source far_c remains separated from Town Hall (midpoint outside preview)")
	_assert(field.is_cell_in_preview(far_c), "Distant source far_c forms its own preview island")

	# Hunter directional bias check (subtle, rounded, no spike)
	var hunter_pos := Vector2i(80, 40)
	field.register_source("hunter_1", TerrainPreviewField.SourceCategory.HUNTER_SCOUT, hunter_pos, 185.0, 0.0, Vector2(1.0, 0.0))
	field.apply_incremental_updates()
	var h_iso := IsoMath.map_to_local(hunter_pos)
	var sd_fwd := field.evaluate_preview_sd_at_iso(h_iso + Vector2(190.0, 0.0))
	var sd_back := field.evaluate_preview_sd_at_iso(h_iso - Vector2(190.0, 0.0))
	_assert(sd_fwd < sd_back, "Hunter directional preview extends subtly farther along forward direction")

	# 5. Incremental vs Full Rebuild Equivalence (2x) — including repeated move, coalesced multi-soldier, and map-edge
	field.update_source("near_b", Vector2i(76, 60))
	field.update_source("near_b", Vector2i(78, 61))
	field.update_source("near_b", Vector2i(80, 62))
	field.apply_incremental_updates()
	field.register_source("edge_corner", TerrainPreviewField.SourceCategory.SOLDIER, Vector2i(2, 125))
	field.apply_incremental_updates()
	field.update_source("edge_corner", Vector2i(125, 2))
	field.apply_incremental_updates()
	field.remove_source("edge_corner")
	field.apply_incremental_updates()
	# Coalesced multi-soldier movement in one tick
	field.register_source("coal_1", TerrainPreviewField.SourceCategory.SOLDIER, Vector2i(40, 40))
	field.register_source("coal_2", TerrainPreviewField.SourceCategory.SOLDIER, Vector2i(88, 88))
	field.apply_incremental_updates()
	field.update_source("coal_1", Vector2i(42, 41))
	field.update_source("coal_1", Vector2i(44, 43))
	field.update_source("coal_2", Vector2i(86, 87))
	field.update_source("coal_2", Vector2i(84, 85))
	field.apply_incremental_updates()

	var ref_2x := _make_ref_copy(field, fow)
	_assert(field.get_envelope_image().get_data() == ref_2x.get_envelope_image().get_data(), "2x incremental updates (incl. repeated/coalesced/edge) match full rebuild byte-for-byte")

	# 6. Incremental vs Full Rebuild Equivalence (1x)
	var field_1x := TerrainPreviewField.new()
	field_1x.configure(128, 128, 12345, 1, fow)
	field_1x.register_source("town_hall", TerrainPreviewField.SourceCategory.TOWN_HALL, center)
	field_1x.rebuild_full()
	field_1x.register_source("soldier_x", TerrainPreviewField.SourceCategory.SOLDIER, Vector2i(28, 28))
	field_1x.apply_incremental_updates()
	field_1x.update_source("soldier_x", Vector2i(36, 32))
	field_1x.apply_incremental_updates()
	field_1x.upsert_source("town_hall", TerrainPreviewField.SourceCategory.TOWN_HALL, center, 390.0, 210.0)
	field_1x.apply_incremental_updates()
	var ref_1x := _make_ref_copy(field_1x, fow)
	_assert(field_1x.get_envelope_image().get_data() == ref_1x.get_envelope_image().get_data(), "1x incremental updates match full rebuild byte-for-byte")

	# 7. No rectangular boundary leak at map corners (with Town Hall at center)
	var corner_field := TerrainPreviewField.new()
	corner_field.configure(128, 128, 12345, 2, fow)
	corner_field.register_source("town_hall", TerrainPreviewField.SourceCategory.TOWN_HALL, center)
	corner_field.rebuild_full()
	var img_2x := corner_field.get_envelope_image()
	var c0 := img_2x.get_pixel(0, 0)
	var c1 := img_2x.get_pixel(255, 0)
	var c2 := img_2x.get_pixel(0, 255)
	var c3 := img_2x.get_pixel(255, 255)
	_assert(c0.r > 0.99 and c1.r > 0.99 and c2.r > 0.99 and c3.r > 0.99, "All 4 map corners remain outside preview (R=1.0, no rectangular leak)")

	# 8. Determinism across identical configurations
	var det_a := _make_ref_copy(field, fow)
	var det_b := _make_ref_copy(field, fow)
	_assert(det_a.get_envelope_image().get_data() == det_b.get_envelope_image().get_data(), "Identical seed + sources produce byte-for-byte deterministic envelope")

	# 9. Verify FogOfWar was NEVER mutated
	var fow_unchanged := true
	var idx := 0
	for x in range(128):
		for y in range(128):
			if fow.get_state(Vector2i(x, y)) != fow_snap[idx]:
				fow_unchanged = false
				break
			idx += 1
		if not fow_unchanged:
			break
	_assert(fow_unchanged, "FogOfWar remains byte-for-byte untouched by TerrainPreviewField")

	# 10. Performance Benchmarks (warm-up + 5 iterations, median & worst, 1x vs 2x, 128x128 & 256x256)
	print("--- PERFORMANCE BENCHMARKS (5 iters, warm-up excluded) ---")
	var bench_stats := func(fn: Callable) -> Dictionary:
		fn.call() # warm-up
		var times: Array[float] = []
		for _i in range(5):
			times.append(_measure_usec(fn))
		times.sort()
		return {"median": times[2], "worst": times[4]}

	for res in [1, 2]:
		var bf := TerrainPreviewField.new()
		bf.configure(128, 128, 12345, res, fow)
		bf.register_source("town_hall", TerrainPreviewField.SourceCategory.TOWN_HALL, center)

		var st_f1: Dictionary = bench_stats.call(func(): bf.rebuild_full())

		var st_inc3: Dictionary = {}
		var prof_inc3: Dictionary = {}
		var inc3_fn := func():
			bf.remove_source("s1")
			bf.remove_source("s2")
			bf.rebuild_full()
			bf.register_source("s1", TerrainPreviewField.SourceCategory.SOLDIER, center + Vector2i(8, -3))
			bf.register_source("s2", TerrainPreviewField.SourceCategory.SOLDIER, center + Vector2i(-6, 7))
			bf.apply_incremental_updates()
		# Measure only apply_incremental_updates after setup
		inc3_fn.call() # warm-up
		var inc3_times: Array[float] = []
		for _i in range(5):
			bf.remove_source("s1")
			bf.remove_source("s2")
			bf.rebuild_full()
			bf.register_source("s1", TerrainPreviewField.SourceCategory.SOLDIER, center + Vector2i(8, -3))
			bf.register_source("s2", TerrainPreviewField.SourceCategory.SOLDIER, center + Vector2i(-6, 7))
			inc3_times.append(_measure_usec(func(): bf.apply_incremental_updates()))
			prof_inc3 = bf.get_last_profile_stats()
		inc3_times.sort()
		st_inc3 = {"median": inc3_times[2], "worst": inc3_times[4]}

		var st_f3: Dictionary = bench_stats.call(func(): bf.rebuild_full())

		for k in range(5):
			bf.register_source("ov_%d" % k, TerrainPreviewField.SourceCategory.SOLDIER, center + Vector2i(k * 2 - 4, k - 2))
		var st_f8: Dictionary = bench_stats.call(func(): bf.rebuild_full())

		# 6 separated sources + single soldier move + coalesced 4-soldier move
		bf.clear_sources()
		for k in range(6):
			bf.register_source("sep_%d" % k, TerrainPreviewField.SourceCategory.SOLDIER, Vector2i(18 + k * 18, 18 + ((k * 23) % 90)))
		var st_f6sep: Dictionary = bench_stats.call(func(): bf.rebuild_full())

		var move_times: Array[float] = []
		var prof_move: Dictionary = {}
		for iter in range(6):
			var p_from := Vector2i(54, 64) if iter % 2 == 0 else Vector2i(56, 62)
			var p_to := Vector2i(56, 62) if iter % 2 == 0 else Vector2i(54, 64)
			bf.update_source("sep_2", p_from)
			bf.apply_incremental_updates()
			bf.update_source("sep_2", p_to)
			var dt := _measure_usec(func(): bf.apply_incremental_updates())
			if iter > 0:
				move_times.append(dt)
				prof_move = bf.get_last_profile_stats()
		move_times.sort()
		var st_move := {"median": move_times[2], "worst": move_times[4]}

		# Coalesced 4-soldier multi-step movement in one tick
		var coal_times: Array[float] = []
		var prof_coal: Dictionary = {}
		for iter in range(6):
			var off := 2 if iter % 2 == 0 else -2
			for s_idx in range(4):
				var base_p := Vector2i(18 + s_idx * 18, 18 + ((s_idx * 23) % 90))
				bf.update_source("sep_%d" % s_idx, base_p + Vector2i(off / 2, 0))
				bf.update_source("sep_%d" % s_idx, base_p + Vector2i(off, off))
			var dt := _measure_usec(func(): bf.apply_incremental_updates())
			if iter > 0:
				coal_times.append(dt)
				prof_coal = bf.get_last_profile_stats()
		coal_times.sort()
		var st_coal := {"median": coal_times[2], "worst": coal_times[4]}

		print("BENCH 128x128 res=%dx (%dx%d) mem=%dKB:" % [res, bf.tex_width, bf.tex_height, bf.get_memory_bytes() / 1024])
		print("  full_1src:  med=%.2fms worst=%.2fms" % [st_f1["median"], st_f1["worst"]])
		print("  full_3src:  med=%.2fms worst=%.2fms" % [st_f3["median"], st_f3["worst"]])
		print("  inc_3src:   med=%.2fms worst=%.2fms | texels=%d (%.1f%%) sd_evals=%d" % [st_inc3["median"], st_inc3["worst"], prof_inc3["dirty_texels"], prof_inc3["dirty_pct"], prof_inc3["sd_evaluations"]])
		print("  full_8ov:   med=%.2fms worst=%.2fms" % [st_f8["median"], st_f8["worst"]])
		print("  full_6sep:  med=%.2fms worst=%.2fms" % [st_f6sep["median"], st_f6sep["worst"]])
		print("  move_1sol:  med=%.2fms worst=%.2fms | texels=%d (%.1f%%) sd_evals=%d" % [st_move["median"], st_move["worst"], prof_move["dirty_texels"], prof_move["dirty_pct"], prof_move["sd_evaluations"]])
		print("  coal_4sol:  med=%.2fms worst=%.2fms | texels=%d (%.1f%%) sd_evals=%d" % [st_coal["median"], st_coal["worst"], prof_coal["dirty_texels"], prof_coal["dirty_pct"], prof_coal["sd_evaluations"]])

	# Max map 256x256 at 1x and 2x
	for res in [1, 2]:
		var mf := TerrainPreviewField.new()
		mf.configure(256, 256, 12345, res, null)
		mf.register_source("town_hall", TerrainPreviewField.SourceCategory.TOWN_HALL, Vector2i(128, 128))
		var st_mf: Dictionary = bench_stats.call(func(): mf.rebuild_full())
		var mi_times: Array[float] = []
		var prof_mi: Dictionary = {}
		for iter in range(6):
			var p := Vector2i(140, 132) if iter % 2 == 0 else Vector2i(142, 134)
			mf.upsert_source("s1", TerrainPreviewField.SourceCategory.SOLDIER, p)
			var dt := _measure_usec(func(): mf.apply_incremental_updates())
			if iter > 0:
				mi_times.append(dt)
				prof_mi = mf.get_last_profile_stats()
		mi_times.sort()
		print("BENCH 256x256 res=%dx (%dx%d) mem=%dKB | full_1: med=%.2fms worst=%.2fms | inc_move: med=%.2fms worst=%.2fms texels=%d (%.1f%%)" % [
			res, mf.tex_width, mf.tex_height, mf.get_memory_bytes() / 1024,
			st_mf["median"], st_mf["worst"], mi_times[2], mi_times[4], prof_mi["dirty_texels"], prof_mi["dirty_pct"]
		])

	if _failed == 0:
		print("PASS: test_terrain_preview_field.gd (%d assertions passed, 0 failed)" % _passed)
		quit(0)
	else:
		printerr("FAIL: test_terrain_preview_field.gd (%d/%d assertions failed)" % [_failed, _passed + _failed])
		quit(1)
