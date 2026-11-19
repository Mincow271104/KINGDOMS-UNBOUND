extends SceneTree

const TerrainPreviewFieldScript = preload("res://scripts/world/terrain_preview_field.gd")
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


func _sample_shader_at_cell(probe_vp: SubViewport, probe_cam: Camera2D, cell: Vector2i) -> Color:
	probe_cam.position = IsoMath.map_to_local(cell)
	probe_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await process_frame
	await process_frame
	var img: Image = probe_vp.get_texture().get_image()
	return img.get_pixel(64, 64)


func _run() -> void:
	print("=== TEST SUITE: CloudSeaComposite Fog-State Composition (C1.9.2 M2-C2B) ===")
	var is_headless: bool = DisplayServer.get_name() == "headless"
	var scene: PackedScene = load("res://scenes/world/world_view.tscn") as PackedScene
	_assert(scene != null, "world_view.tscn loads cleanly")
	if scene == null:
		quit(1)
		return

	var wv: Node = scene.instantiate()
	wv.set("world_seed", 12345)
	get_root().add_child(wv)
	await process_frame
	await process_frame

	var field: TerrainPreviewFieldScript = wv.get("terrain_preview_field") as TerrainPreviewFieldScript
	var renderer: TerrainPreviewRendererScript = wv.get("terrain_preview_renderer") as TerrainPreviewRendererScript
	var fog: FogOfWar = wv.get("fog_of_war") as FogOfWar
	var comp: Polygon2D = wv.get("cloud_sea_composite") as Polygon2D

	# 18. Gameplay Town Hall source registered; CloudSeaComposite is production default
	_assert(field.has_source("townhall_main"), "Gameplay Town Hall preview source registered by default")
	_assert(wv.get("use_cloud_sea_composite") == true and comp.visible, "CloudSeaComposite is production default (use_cloud_sea_composite == true)")

	# Fog-state texture format & initial stats
	var fst: ImageTexture = wv.call("get_fog_state_texture") as ImageTexture
	_assert(fst != null and fst.get_width() == fog.map_width and fst.get_height() == fog.map_height, "fog_state_tex created with map dimensions (%dx%d)" % [fog.map_width, fog.map_height])
	var fst_img: Image = fst.get_image()
	_assert(fst_img.get_format() == Image.FORMAT_R8, "fog_state_tex uses compact FORMAT_R8")
	var st_init: Dictionary = wv.call("get_fog_state_last_stats")
	print("  PERF initial_full_gen=%.3fms upload=%.3fms mem=%dKB" % [
		float(st_init.get("gen_ms", 0.0)), float(st_init.get("upload_ms", 0.0)), int(st_init.get("mem_bytes", 0)) / 1024
	])

	# 12. Repeated identical update produces no unnecessary upload
	var up_before: int = int(wv.call("get_fog_state_upload_count"))
	var did_full: bool = bool(wv.call("sync_fog_state_texture_full", false))
	_assert(not did_full and int(wv.call("get_fog_state_upload_count")) == up_before, "Repeated identical sync_fog_state_texture_full(false) performs 0 uploads")

	# 11. Multi-cell reveal update batches into 1 upload
	var batch_cells: Array[Vector2i] = []
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var c := Vector2i(100 + dx, 100 + dy)
			fog.set_state(c, FogOfWar.State.EXPLORED)
			batch_cells.append(c)
	up_before = int(wv.call("get_fog_state_upload_count"))
	var did_inc: bool = bool(wv.call("update_fog_state_texture_dirty_cells", batch_cells))
	var st_inc: Dictionary = wv.call("get_fog_state_last_stats")
	_assert(did_inc and int(wv.call("get_fog_state_upload_count")) == up_before + 1, "Multi-cell reveal batches 25 cells into exactly 1 upload")
	print("  PERF inc_25cells=%.3fms upload=%.3fms" % [float(st_inc.get("inc_ms", 0.0)), float(st_inc.get("upload_ms", 0.0))])
	_assert(not bool(wv.call("update_fog_state_texture_dirty_cells", batch_cells)), "Repeating same dirty_cells without state change performs 0 uploads")

	# 15. Rebinding to a different FogOfWar instance
	var alt_fog := FogOfWar.new(fog.map_width, fog.map_height)
	alt_fog.set_state(Vector2i(10, 10), FogOfWar.State.VISIBLE)
	alt_fog.set_state(Vector2i(12, 12), FogOfWar.State.EXPLORED)
	wv.call("rebind_terrain_preview_fog", alt_fog)
	var alt_img: Image = (wv.call("get_fog_state_texture") as ImageTexture).get_image()
	_assert(alt_img.get_pixel(10, 10).r8 == 255 and alt_img.get_pixel(12, 12).r8 == 128 and alt_img.get_pixel(20, 20).r8 == 0, "Rebinding FogOfWar encodes VISIBLE=255, EXPLORED=128, UNEXPLORED=0")

	if is_headless:
		print("  [INFO] Headless mode; skipping GPU shader readback assertions.")
	else:
		# Build transparent SubViewport probe sharing CloudSeaComposite material to read exact shader RGBA
		var probe_vp := SubViewport.new()
		probe_vp.size = Vector2i(128, 128)
		probe_vp.transparent_bg = true
		probe_vp.disable_3d = true
		probe_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var probe_cam := Camera2D.new()
		probe_cam.enabled = true
		probe_vp.add_child(probe_cam)
		var probe_poly := Polygon2D.new()
		probe_poly.polygon = comp.polygon
		probe_poly.material = comp.material
		probe_vp.add_child(probe_poly)
		get_root().add_child(probe_vp)

		# 1. Entire map UNEXPLORED + zero-source envelope
		alt_fog.reset_fog()
		field.clear_sources()
		renderer.sync_if_needed()
		wv.call("sync_fog_state_texture_full", false)
		var col_unexp := await _sample_shader_at_cell(probe_vp, probe_cam, Vector2i(64, 64))
		_assert(col_unexp.a > 0.95 and col_unexp.r > 0.75, "1/13: Entire map UNEXPLORED + 0 sources outputs opaque luminous cloud sea (a=%.2f)" % col_unexp.a)

		# 2. VISIBLE patch (5x5 so interior is clear of boundary feather)
		var patch_64: Array[Vector2i] = []
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var c := Vector2i(64 + dx, 64 + dy)
				alt_fog.set_state(c, FogOfWar.State.VISIBLE)
				patch_64.append(c)
		wv.call("update_fog_state_texture_dirty_cells", patch_64)
		await process_frame
		var col_vis := await _sample_shader_at_cell(probe_vp, probe_cam, Vector2i(64, 64))
		var col_adj := await _sample_shader_at_cell(probe_vp, probe_cam, Vector2i(68, 68))
		_assert(col_vis.a < 0.02 and col_adj.a > 0.95, "2: VISIBLE patch clears cloud (a=%.2f) while UNEXPLORED neighbor stays opaque (a=%.2f)" % [col_vis.a, col_adj.a])

		# 3 & 8. VISIBLE -> EXPLORED_NOT_VISIBLE transition
		for c in patch_64:
			alt_fog.set_state(c, FogOfWar.State.EXPLORED)
		wv.call("update_fog_state_texture_dirty_cells", patch_64)
		await process_frame
		var col_exp := await _sample_shader_at_cell(probe_vp, probe_cam, Vector2i(64, 64))
		_assert(col_exp.a < 0.02, "3/8: VISIBLE -> EXPLORED_NOT_VISIBLE outputs zero dark overlay (rgba=%.2f,%.2f,%.2f,%.2f)" % [col_exp.r, col_exp.g, col_exp.b, col_exp.a])

		# 9. EXPLORED_NOT_VISIBLE -> VISIBLE transition
		for c in patch_64:
			alt_fog.set_state(c, FogOfWar.State.VISIBLE)
		wv.call("update_fog_state_texture_dirty_cells", patch_64)
		await process_frame
		var col_revis := await _sample_shader_at_cell(probe_vp, probe_cam, Vector2i(64, 64))
		_assert(col_revis.a < 0.02, "9: EXPLORED_NOT_VISIBLE -> VISIBLE restores full clear terrain (a=%.2f)" % col_revis.a)

		# 10. UNEXPLORED -> EXPLORED transition
		var patch_80: Array[Vector2i] = []
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var c := Vector2i(80 + dx, 80 + dy)
				alt_fog.set_state(c, FogOfWar.State.EXPLORED)
				patch_80.append(c)
		wv.call("update_fog_state_texture_dirty_cells", patch_80)
		await process_frame
		var col_u2e := await _sample_shader_at_cell(probe_vp, probe_cam, Vector2i(80, 80))
		_assert(col_u2e.a < 0.02, "10: UNEXPLORED -> EXPLORED transitions cleanly with zero dark overlay (a=%.2f)" % col_u2e.a)

		# 4, 5, 6, 7. UNEXPLORED inside vs outside preview envelope, overlapping sources, map edges
		alt_fog.reset_fog()
		wv.call("sync_fog_state_texture_full", false)
		await process_frame
		field.register_source("p_th", TerrainPreviewFieldScript.SourceCategory.TOWN_HALL, Vector2i(64, 64))
		field.register_source("p_s1", TerrainPreviewFieldScript.SourceCategory.SOLDIER, Vector2i(72, 60))
		field.register_source("p_edge", TerrainPreviewFieldScript.SourceCategory.SOLDIER, Vector2i(0, 127))
		renderer.sync_if_needed()
		var col_in_prev := await _sample_shader_at_cell(probe_vp, probe_cam, Vector2i(64, 64))
		var col_out_prev := await _sample_shader_at_cell(probe_vp, probe_cam, Vector2i(10, 10))
		var col_edge_prev := await _sample_shader_at_cell(probe_vp, probe_cam, Vector2i(0, 127))
		_assert(col_in_prev.a < 0.15, "4/7: UNEXPLORED inside preview core opens clear terrain preview (a=%.2f)" % col_in_prev.a)
		_assert(col_out_prev.a > 0.95, "5: UNEXPLORED outside preview stays 100%% opaque cloud sea (a=%.2f)" % col_out_prev.a)
		_assert(col_edge_prev.a < 0.15, "6: Preview boundary at map edge (0,127) opens cleanly (a=%.2f)" % col_edge_prev.a)

		# 16 & 17. Preview state does not modify FogOfWar or reveal hidden entities
		_assert(alt_fog.is_unexplored(Vector2i(64, 64)), "16/17: Previewed cell (64,64) remains strictly UNEXPLORED in FogOfWar")

		# Measure GPU composite pass time
		var p_rid := probe_vp.get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(p_rid, true)
		probe_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await process_frame
		await process_frame
		print("  PERF composite_probe_gpu=%.3fms" % RenderingServer.viewport_get_measured_render_time_gpu(p_rid))

		probe_vp.queue_free()

	# 14. Simulated Save/Load fog texture reconstruction
	wv.call("rebind_terrain_preview_fog", fog)
	fog.set_state(Vector2i(5, 5), FogOfWar.State.EXPLORED)
	wv.call("_sync_full_fog_and_minimap")
	var recon_img: Image = (wv.call("get_fog_state_texture") as ImageTexture).get_image()
	_assert(recon_img.get_pixel(5, 5).r8 == 128, "14: _sync_full_fog_and_minimap() reconstructs fog_state_tex after simulated load")

	field.clear_sources()
	renderer.sync_if_needed()
	wv.queue_free()
	await process_frame
	await process_frame

	if _failed == 0:
		print("PASS: test_cloud_sea_fog_state_composition.gd (%d assertions passed, 0 failed)" % _passed)
		quit(0)
	else:
		printerr("FAIL: test_cloud_sea_fog_state_composition.gd (%d passed, %d failed)" % [_passed, _failed])
		quit(1)
