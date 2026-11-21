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


func _count_subviewports(root: Node) -> int:
	var count := 0
	if root is SubViewport:
		count += 1
	for child in root.get_children():
		count += _count_subviewports(child)
	return count


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== TEST SUITE: WorldView TerrainPreview Lifecycle (C1.9.2 M2-C1) ===")
	var is_headless: bool = DisplayServer.get_name() == "headless"
	var scene: PackedScene = load("res://scenes/world/world_view.tscn") as PackedScene
	_assert(scene != null, "world_view.tscn loads cleanly")
	if scene == null:
		quit(1)
		return

	var t_init0 := Time.get_ticks_usec()
	var wv: Node = scene.instantiate()
	wv.set("world_seed", 12345)
	get_root().add_child(wv)
	await process_frame
	await process_frame
	var init_ms := float(Time.get_ticks_usec() - t_init0) / 1000.0

	var field: TerrainPreviewFieldScript = wv.get("terrain_preview_field") as TerrainPreviewFieldScript
	var renderer: TerrainPreviewRendererScript = wv.get("terrain_preview_renderer") as TerrainPreviewRendererScript
	var fog: FogOfWar = wv.get("fog_of_war") as FogOfWar

	# 1-5: Ownership, dimensions, empty registry, valid envelope texture
	_assert(field != null, "WorldView owns one TerrainPreviewField")
	_assert(renderer != null and is_instance_valid(renderer), "WorldView owns one TerrainPreviewRenderer")
	_assert(fog != null and renderer.map_width == fog.map_width and renderer.map_height == fog.map_height, "Renderer configured with FogOfWar map dimensions (%dx%d)" % [fog.map_width, fog.map_height])
	var sub_vp: SubViewport = renderer.get_subviewport()
	_assert(sub_vp != null and sub_vp.size == Vector2i(fog.map_width, fog.map_height), "SubViewport size matches map dimensions")
	_assert(field.has_source("townhall_main"), "Gameplay Town Hall preview source registered")
	_assert(renderer.get_envelope_texture() != null and renderer.get_gpu_pass_count() >= 1, "Renderer initialized with valid envelope ViewportTexture")

	# 11: Production CloudSeaComposite active and legacy fog layers hidden
	var comp: Polygon2D = wv.get("cloud_sea_composite") as Polygon2D
	var tml: TileMapLayer = wv.get("fog_tile_layer") as TileMapLayer
	var cl: FogCloudLayer = wv.get("fog_cloud_layer") as FogCloudLayer
	var csb: Polygon2D = wv.get("cloud_sea_base") as Polygon2D
	_assert(comp != null and comp.visible and tml != null and not tml.visible and cl != null and not cl.visible and csb != null and not csb.visible, "Production CloudSeaComposite active and legacy fog layers hidden")

	# 6: Repeated setup does not create duplicate SubViewports
	var vp_count_before := _count_subviewports(wv)
	wv.call("_setup_fog_layer")
	await process_frame
	await process_frame
	var vp_count_after := _count_subviewports(wv)
	var renderer_after_setup: TerrainPreviewRendererScript = wv.get("terrain_preview_renderer") as TerrainPreviewRendererScript
	_assert(vp_count_before >= 1 and vp_count_after == vp_count_before and renderer_after_setup == renderer, "Repeated _setup_fog_layer() does not create duplicate SubViewports or renderers")

	# 10: Idle synchronization creates zero additional GPU passes and stays UPDATE_DISABLED
	var passes_idle_before := renderer.get_gpu_pass_count()
	var did_idle_sync := renderer.sync_if_needed()
	await process_frame
	await process_frame
	_assert(not did_idle_sync and renderer.get_gpu_pass_count() == passes_idle_before, "Idle sync_if_needed() creates 0 additional GPU passes")
	_assert(renderer.get_subviewport().render_target_update_mode == SubViewport.UPDATE_DISABLED, "SubViewport remains UPDATE_DISABLED when idle")

	# Future Save/Load rebind API check (without modifying SaveManager)
	var replacement_fog := FogOfWar.new(fog.map_width, fog.map_height)
	wv.call("rebind_terrain_preview_fog", replacement_fog)
	_assert(wv.get("terrain_preview_field")._fog_of_war == replacement_fog, "rebind_terrain_preview_fog() safely updates field FogOfWar reference")
	wv.call("rebind_terrain_preview_fog", fog)

	# 7-8: Cleanup and reinitialization
	var old_sub := renderer.get_subviewport()
	wv.call("cleanup_terrain_preview_renderer")
	await process_frame
	_assert(wv.get("terrain_preview_renderer") == null and wv.get("terrain_preview_field") == null and not is_instance_valid(old_sub), "cleanup_terrain_preview_renderer() frees SubViewport and clears references")
	wv.call("_setup_terrain_preview_renderer")
	await process_frame
	await process_frame
	var reinit_renderer: TerrainPreviewRendererScript = wv.get("terrain_preview_renderer") as TerrainPreviewRendererScript
	var reinit_field: TerrainPreviewFieldScript = wv.get("terrain_preview_field") as TerrainPreviewFieldScript
	_assert(reinit_renderer != null and is_instance_valid(reinit_renderer) and reinit_renderer.get_envelope_texture() != null and reinit_field.get_source_count() == 0, "Reinitialization succeeds with valid ViewportTexture and 0 sources")

	# 9 & 12: Independent WorldView instances do not share mutable field state
	var wv2: Node = scene.instantiate()
	wv2.set("world_seed", 67890)
	get_root().add_child(wv2)
	await process_frame
	await process_frame
	var f1: TerrainPreviewFieldScript = wv.get("terrain_preview_field") as TerrainPreviewFieldScript
	var f2: TerrainPreviewFieldScript = wv2.get("terrain_preview_field") as TerrainPreviewFieldScript
	var r2: TerrainPreviewRendererScript = wv2.get("terrain_preview_renderer") as TerrainPreviewRendererScript
	_assert(f1 != f2 and reinit_renderer != r2, "Independent WorldView instances own distinct field and renderer instances")
	f1.register_source("iso_test", TerrainPreviewFieldScript.SourceCategory.SOLDIER, Vector2i(10, 10))
	_assert(f1.has_source("iso_test") and not f2.has_source("iso_test"), "Mutating WorldView 1 field does not leak to WorldView 2")
	f1.clear_sources()
	reinit_renderer.sync_if_needed()
	await process_frame

	# Performance & memory summary
	var st: Dictionary = reinit_renderer.get_last_stats()
	var mem_kb: int = reinit_renderer.get_memory_bytes() / 1024
	var sub_gpu_ms := -1.0
	if not is_headless:
		var rid := reinit_renderer.get_subviewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(rid, true)
		reinit_renderer.sync_if_needed(true)
		await process_frame
		await process_frame
		sub_gpu_ms = RenderingServer.viewport_get_measured_render_time_gpu(rid)
		st = reinit_renderer.get_last_stats()
	print("  PERF init_ms=%.2fms pack_0src=%.3fms upload=%.3fms subGPU=%s mem=%dKB vp_before=%d vp_after=%d" % [
		init_ms,
		float(st.get("pack_ms", 0.0)),
		float(st.get("tex_upload_ms", 0.0)),
		("%.3fms" % sub_gpu_ms) if sub_gpu_ms >= 0.0 else "headless_unavailable",
		mem_kb,
		vp_count_before,
		vp_count_after,
	])

	wv.queue_free()
	wv2.queue_free()
	await process_frame
	await process_frame

	if _failed == 0:
		print("PASS: test_world_view_preview_lifecycle.gd (%d assertions passed, 0 failed)" % _passed)
		quit(0)
	else:
		printerr("FAIL: test_world_view_preview_lifecycle.gd (%d passed, %d failed)" % [_passed, _failed])
		quit(1)
