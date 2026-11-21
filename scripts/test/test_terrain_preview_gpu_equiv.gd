extends SceneTree

const TerrainPreviewRendererScript = preload("res://scripts/world/terrain_preview_renderer.gd")

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


static func _compare_rg_images(cpu_img: Image, gpu_img: Image) -> Dictionary:
	var w := cpu_img.get_width()
	var h := cpu_img.get_height()
	var max_r := 0
	var max_g := 0
	var sum_r := 0
	var sum_g := 0
	for y in range(h):
		for x in range(w):
			var c := cpu_img.get_pixel(x, y)
			var g := gpu_img.get_pixel(x, y)
			var dr := absi(int(roundf(c.r * 255.0)) - int(roundf(g.r * 255.0)))
			var dg := absi(int(roundf(c.g * 255.0)) - int(roundf(g.g * 255.0)))
			max_r = maxi(max_r, dr)
			max_g = maxi(max_g, dg)
			sum_r += dr
			sum_g += dg
	var n := float(w * h)
	return {
		"max_r": max_r,
		"max_g": max_g,
		"mean_r": snappedf(float(sum_r) / n, 0.001),
		"mean_g": snappedf(float(sum_g) / n, 0.001),
	}


static func _median_worst(vals: Array[float]) -> Dictionary:
	var s := vals.duplicate()
	s.sort()
	return {
		"med": snappedf(s[s.size() / 2], 0.001),
		"worst": snappedf(s[s.size() - 1], 0.001),
	}


func _run() -> void:
	print("=== TEST SUITE: TerrainPreviewRenderer GPU Equivalence & Lifecycle (M2-B) ===")

	var is_headless := DisplayServer.get_name() == "headless"
	var map_w := 128
	var map_h := 128
	var center := Vector2i(64, 64)

	var field := TerrainPreviewField.new()
	field.configure(map_w, map_h, 12345, 1, null)

	var renderer := TerrainPreviewRendererScript.new()
	get_root().add_child(renderer)
	renderer.configure(field, 1)

	# 1. Lifecycle, no duplicate SubViewport, coalescing, and UPDATE_DISABLED when idle
	_assert(renderer.get_child_count() == 1, "Renderer owns exactly 1 SubViewport child after configure()")
	renderer.configure(field, 1)
	_assert(renderer.get_child_count() == 1, "Repeated configure() does not create duplicate SubViewport")
	_assert(renderer.get_envelope_texture() != null, "get_envelope_texture() returns valid ViewportTexture")

	var sub_vp: SubViewport = renderer.get_subviewport()
	_assert(sub_vp.disable_3d, "SubViewport has disable_3d = true")
	await process_frame
	await process_frame
	_assert(sub_vp.render_target_update_mode == SubViewport.UPDATE_DISABLED, "SubViewport returns to UPDATE_DISABLED when idle")

	var passes_before: int = renderer.get_gpu_pass_count()
	for step in range(5):
		field.upsert_source("coal_s", TerrainPreviewField.SourceCategory.SOLDIER, Vector2i(40 + step, 40 + step))
	_assert(renderer.is_update_pending(), "is_update_pending() is true after source updates")
	var did_sync: bool = renderer.sync_if_needed()
	_assert(did_sync and renderer.get_gpu_pass_count() == passes_before + 1, "5 updates coalesce into exactly 1 GPU pass")
	_assert(not renderer.is_update_pending(), "is_update_pending() clears after sync_if_needed()")
	_assert(not renderer.sync_if_needed(), "Idle sync_if_needed() returns false and skips GPU pass")
	await process_frame
	await process_frame
	_assert(sub_vp.render_target_update_mode == SubViewport.UPDATE_DISABLED, "SubViewport returns to UPDATE_DISABLED after coalesced pass")
	var idle_passes_start: int = renderer.get_gpu_pass_count()
	await process_frame
	await process_frame
	await process_frame
	_assert(
		sub_vp.render_target_update_mode == SubViewport.UPDATE_DISABLED and renderer.get_gpu_pass_count() == idle_passes_start and not renderer.is_update_pending(),
		"Idle frames keep UPDATE_DISABLED, schedule no UPDATE_ONCE, and keep gpu_pass_count unchanged"
	)

	# 1b. Focused GPU Dirty-State & Soldier Movement Refresh Regression
	field.clear_sources()
	renderer.sync_if_needed()
	await process_frame
	var p_dirty := renderer.get_gpu_pass_count()
	_assert(field.register_source("s_move", TerrainPreviewField.SourceCategory.SOLDIER, Vector2i(24, 24)), "register_source() succeeds for new Soldier")
	_assert(field.is_gpu_dirty() and renderer.sync_if_needed() and renderer.get_gpu_pass_count() == p_dirty + 1, "register_source() marks GPU dirty and sync_if_needed(false) runs 1 pass")
	await process_frame
	await process_frame
	if not is_headless:
		var img_before: Image = renderer.get_envelope_texture().get_image()
		var old_cell_before := img_before.get_pixel(24, 24)
		var new_cell_before := img_before.get_pixel(96, 96)
		_assert(old_cell_before.r8 < 128 and new_cell_before.r8 == 255, "Before Soldier move: (24,24) revealed and (96,96) fogged")

	# Failed mutations must not mark GPU dirty
	_assert(not field.register_source("s_move", TerrainPreviewField.SourceCategory.SOLDIER, Vector2i(30, 30)), "Duplicate register_source() returns false")
	_assert(not field.update_source("missing_id", Vector2i(30, 30)), "Missing update_source() returns false")
	_assert(not field.remove_source("missing_id"), "Missing remove_source() returns false")
	_assert(not field.is_gpu_dirty() and not renderer.sync_if_needed(), "Failed mutations do not mark GPU dirty or trigger pass")

	# Soldier movement via update_source() with sync_if_needed(false)
	p_dirty = renderer.get_gpu_pass_count()
	_assert(field.update_source("s_move", Vector2i(96, 96)), "update_source() moves Soldier to (96, 96)")
	_assert(field.is_gpu_dirty() and renderer.sync_if_needed() and renderer.get_gpu_pass_count() == p_dirty + 1, "update_source() move triggers sync_if_needed(false) GPU pass")
	await process_frame
	await process_frame
	if not is_headless:
		var img_after: Image = renderer.get_envelope_texture().get_image()
		var old_cell_after := img_after.get_pixel(24, 24)
		var new_cell_after := img_after.get_pixel(96, 96)
		_assert(new_cell_after.r8 < 128 and old_cell_after.r8 == 255 and old_cell_after.g8 == 255, "After Soldier move: (96,96) revealed and old (24,24) no longer retained")

	# Parameter-only updates without cell change (Hunter dir, preview radius, core radius, oval_x)
	field.register_source("h_param", TerrainPreviewField.SourceCategory.HUNTER_SCOUT, Vector2i(64, 64), 180.0, 40.0, Vector2(1.0, 0.0), 1.08)
	renderer.sync_if_needed()
	await process_frame
	p_dirty = renderer.get_gpu_pass_count()
	field.update_source("h_param", Vector2i(64, 64), 180.0, 40.0, Vector2(0.0, 1.0), 1.08)
	_assert(field.is_gpu_dirty() and renderer.sync_if_needed() and renderer.get_gpu_pass_count() == p_dirty + 1, "Parameter-only dir update marks GPU dirty")
	p_dirty = renderer.get_gpu_pass_count()
	field.update_source("h_param", Vector2i(64, 64), 200.0, 40.0, Vector2(0.0, 1.0), 1.08)
	_assert(field.is_gpu_dirty() and renderer.sync_if_needed() and renderer.get_gpu_pass_count() == p_dirty + 1, "Parameter-only preview_radius update marks GPU dirty")
	p_dirty = renderer.get_gpu_pass_count()
	field.update_source("h_param", Vector2i(64, 64), 200.0, 52.0, Vector2(0.0, 1.0), 1.08)
	_assert(field.is_gpu_dirty() and renderer.sync_if_needed() and renderer.get_gpu_pass_count() == p_dirty + 1, "Parameter-only core_radius update marks GPU dirty")
	p_dirty = renderer.get_gpu_pass_count()
	field.update_source("h_param", Vector2i(64, 64), 200.0, 52.0, Vector2(0.0, 1.0), 1.25)
	_assert(field.is_gpu_dirty() and renderer.sync_if_needed() and renderer.get_gpu_pass_count() == p_dirty + 1, "Parameter-only oval_x update marks GPU dirty")

	# Removing one source while overlapping sources remain
	field.register_source("ov_keep", TerrainPreviewField.SourceCategory.SOLDIER, Vector2i(65, 64))
	renderer.sync_if_needed()
	p_dirty = renderer.get_gpu_pass_count()
	_assert(field.remove_source("h_param") and field.is_gpu_dirty() and renderer.sync_if_needed() and renderer.get_gpu_pass_count() == p_dirty + 1, "remove_source() with overlapping source remaining marks GPU dirty")

	# 2. Overflow & Deterministic Priority (128 slots max, 130 sources)
	field.clear_sources()
	for i in range(128):
		field.register_source("s_%03d" % i, TerrainPreviewField.SourceCategory.SOLDIER, Vector2i(10 + (i % 100), 10 + (i / 100) * 10))
	field.register_source("th_priority", TerrainPreviewField.SourceCategory.TOWN_HALL, center)
	field.register_source("hunter_priority", TerrainPreviewField.SourceCategory.HUNTER_SCOUT, center + Vector2i(10, -4), 185.0, 0.0, Vector2(1.0, 0.0))
	renderer.sync_if_needed()
	var st_ov: Dictionary = renderer.get_last_stats()
	_assert(int(st_ov["source_count"]) == 128 and int(st_ov["overflow_count"]) == 2, "130 sources pack into 128 slots with overflow_count=2")
	var packed_img: Image = renderer.get_source_data_texture().get_image()
	var slot0 := packed_img.get_pixel(0, 0)
	var slot1 := packed_img.get_pixel(1, 0)
	_assert(is_equal_approx(slot0.b, TerrainPreviewField.DEFAULT_TOWN_HALL_PREVIEW_RADIUS), "Overflow prioritizes TOWN_HALL into slot 0")
	_assert(is_equal_approx(slot1.b, TerrainPreviewField.DEFAULT_HUNTER_PREVIEW_RADIUS), "Overflow prioritizes HUNTER_SCOUT into slot 1")

	# 3. CPU vs GPU Equivalence across all 10 scenarios at 1x and 2x (real renderer only)
	if is_headless:
		print("  [INFO] Headless dummy renderer detected; skipping GPU pixel readback assertions (run without --headless for D3D12 verification).")
	else:
		var case_names := [
			"01_empty",
			"02_one_town_hall",
			"03_three_nearby",
			"04_separated",
			"05_eight_overlapping",
			"06_hunter_directional",
			"07_soldier_move",
			"08_multi_simultaneous",
			"09_remove_overlapping",
			"10_map_edge",
		]
		for res in [1, 2]:
			var tol := 4 if res == 1 else 2
			field.configure(map_w, map_h, 12345, res, null)
			renderer.configure(field, res)
			for ci in range(case_names.size()):
				var cname: String = case_names[ci]
				match ci:
					0:
						field.clear_sources()
					1:
						field.register_source("th", TerrainPreviewField.SourceCategory.TOWN_HALL, center)
					2:
						field.register_source("n1", TerrainPreviewField.SourceCategory.SOLDIER, center + Vector2i(7, -3))
						field.register_source("n2", TerrainPreviewField.SourceCategory.SOLDIER, center + Vector2i(-5, 6))
					3:
						field.register_source("sep", TerrainPreviewField.SourceCategory.SOLDIER, Vector2i(20, 20))
					4:
						for k in range(4):
							field.register_source("ov_%d" % k, TerrainPreviewField.SourceCategory.SOLDIER, center + Vector2i(k * 2 - 3, k - 1))
					5:
						field.register_source("h1", TerrainPreviewField.SourceCategory.HUNTER_SCOUT, center + Vector2i(14, -4), 185.0, 0.0, Vector2(1.0, -0.3))
					6:
						field.update_source("n1", Vector2i(92, 92))
					7:
						field.update_source("n2", Vector2i(82, 76))
						field.update_source("sep", Vector2i(28, 24))
						field.update_source("h1", center + Vector2i(16, -2), 185.0, 0.0, Vector2(0.8, 0.6))
					8:
						field.remove_source("ov_0")
						field.remove_source("ov_1")
					9:
						field.register_source("edge", TerrainPreviewField.SourceCategory.SOLDIER, Vector2i(2, 125))

				field.rebuild_full()
				renderer.sync_if_needed(true)
				await process_frame
				await process_frame
				var gpu_img: Image = renderer.get_envelope_texture().get_image()
				var diff := _compare_rg_images(field.get_envelope_image(), gpu_img)
				_assert(diff["max_r"] <= tol and diff["max_g"] <= tol, "res=%dx %-22s CPU/GPU within %d/255 (max_R=%d, max_G=%d, mean_R=%.3f, mean_G=%.3f)" % [
					res, cname, tol, diff["max_r"], diff["max_g"], diff["mean_r"], diff["mean_g"]
				])

		# 4. Performance Benchmarks (1, 8, 32, 64, 128 sources at 1x and 2x)
		print("--- PERFORMANCE BENCHMARKS (D3D12 Forward+) ---")
		var sub_rid: RID = renderer.get_subviewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(sub_rid, true)

		for res in [1, 2]:
			field.configure(map_w, map_h, 12345, res, null)
			renderer.configure(field, res)
			for n_src in [1, 8, 32, 64, 128]:
				field.clear_sources()
				field.register_source("th", TerrainPreviewField.SourceCategory.TOWN_HALL, center)
				for i in range(1, n_src):
					field.register_source("s_%03d" % i, TerrainPreviewField.SourceCategory.SOLDIER, Vector2i(14 + (i * 13) % 100, 14 + (i * 19) % 100))

				# Warm-up
				renderer.sync_if_needed(true)
				await process_frame

				var pack_times: Array[float] = []
				var up_times: Array[float] = []
				var gpu_times: Array[float] = []
				for it in range(6):
					field.update_source("th", center + Vector2i(it % 2, 0))
					renderer.sync_if_needed()
					var st: Dictionary = renderer.get_last_stats()
					await process_frame
					if it > 0:
						pack_times.append(float(st["pack_ms"]))
						up_times.append(float(st["tex_upload_ms"]))
						gpu_times.append(RenderingServer.viewport_get_measured_render_time_gpu(sub_rid))

				# Idle verification (retained GPU timestamp is not fresh idle GPU work)
				var passes_before_idle: int = renderer.get_gpu_pass_count()
				await process_frame
				await process_frame
				_assert(
					sub_vp.render_target_update_mode == SubViewport.UPDATE_DISABLED and renderer.get_gpu_pass_count() == passes_before_idle and not renderer.is_update_pending(),
					"BENCH res=%dx src=%3d idle frames keep UPDATE_DISABLED and +0 GPU passes" % [res, n_src]
				)
				var sp := _median_worst(pack_times)
				var su := _median_worst(up_times)
				var sg := _median_worst(gpu_times)
				print("  BENCH res=%dx src=%3d mem=%dKB | pack=%.3f/%.3fms upload=%.3f/%.3fms subGPU=%.3f/%.3fms idle=UPDATE_DISABLED/+0passes (gpu=unavailable)" % [
					res, n_src, renderer.get_memory_bytes() / 1024,
					sp["med"], sp["worst"], su["med"], su["worst"], sg["med"], sg["worst"]
				])

	# 5. Cleanup & teardown verification
	renderer.cleanup()
	_assert(renderer.get_subviewport() == null and renderer.get_envelope_texture() == null, "cleanup() frees SubViewport and clears ViewportTexture reference")
	renderer.queue_free()
	await process_frame

	if _failed == 0:
		print("PASS: test_terrain_preview_gpu_equiv.gd (%d assertions passed, 0 failed)" % _passed)
		quit(0)
	else:
		printerr("FAIL: test_terrain_preview_gpu_equiv.gd (%d/%d assertions failed)" % [_failed, _passed + _failed])
		quit(1)
