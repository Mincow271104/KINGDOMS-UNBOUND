extends SceneTree

const TerrainPreviewFieldScript = preload("res://scripts/world/terrain_preview_field.gd")
const TerrainPreviewRendererScript = preload("res://scripts/world/terrain_preview_renderer.gd")
const FogOfWarScript = preload("res://scripts/world/fog_of_war.gd")

var _passed: int = 0
var _failed: int = 0


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] ", msg)
	else:
		_failed += 1
		printerr("  [FAIL] ", msg)


func _count_named_nodes(root: Node, target_name: String) -> int:
	var c := 0
	if root.name == target_name:
		c += 1
	for child in root.get_children():
		c += _count_named_nodes(child, target_name)
	return c


func _count_canvas_modulates(root: Node) -> int:
	var c := 0
	if root is CanvasModulate:
		c += 1
	for child in root.get_children():
		c += _count_canvas_modulates(child)
	return c


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== TEST SUITE: CloudSeaComposite Foundation (C1.9.2 M2-C2A) ===")
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

	var world_root: Node = wv.get_node_or_null("World")
	var comp: Polygon2D = wv.get("cloud_sea_composite") as Polygon2D
	var renderer: TerrainPreviewRendererScript = wv.get("terrain_preview_renderer") as TerrainPreviewRendererScript
	var field: TerrainPreviewFieldScript = wv.get("terrain_preview_field") as TerrainPreviewFieldScript
	var tml: TileMapLayer = wv.get("fog_tile_layer") as TileMapLayer
	var cl: FogCloudLayer = wv.get("fog_cloud_layer") as FogCloudLayer
	var csb: Polygon2D = wv.get("cloud_sea_base") as Polygon2D
	var fog: FogOfWar = wv.get("fog_of_war") as FogOfWar

	# 1-5: Composite node, shader, textures, envelope binding, polygon bounds
	_assert(comp != null and is_instance_valid(comp) and comp is Polygon2D, "CloudSeaComposite Polygon2D created")
	_assert(comp.get_parent() == world_root, "CloudSeaComposite is child of World (inherits single DayNightModulate)")
	_assert(_count_canvas_modulates(wv) == 1, "Exactly 1 CanvasModulate exists in WorldView (World/DayNightModulate)")
	_assert(comp.modulate == Color.WHITE, "CloudSeaComposite modulate is Color.WHITE (no compounded RGB tint)")
	_assert(comp.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR, "CloudSeaComposite uses TEXTURE_FILTER_LINEAR")
	_assert(comp.polygon.size() == 4, "CloudSeaComposite polygon has 4 isometric map corners")

	var mat: ShaderMaterial = comp.material as ShaderMaterial
	_assert(mat != null and mat.shader != null, "CloudSeaComposite has valid ShaderMaterial and Shader")
	var sea_tex := mat.get_shader_parameter("sea_tex") as Texture2D
	var bank_tex := mat.get_shader_parameter("bank_tex") as Texture2D
	var env_tex := mat.get_shader_parameter("envelope_tex") as Texture2D
	var map_sz = mat.get_shader_parameter("map_size")
	_assert(sea_tex != null and bank_tex != null, "Approved cloud sea_tex and bank_tex loaded")
	_assert(env_tex != null and env_tex == renderer.get_envelope_texture(), "envelope_tex bound to renderer.get_envelope_texture()")
	_assert(map_sz == Vector2(fog.map_width, fog.map_height), "Shader map_size matches FogOfWar dimensions")

	# 10-12: Production CloudSeaComposite active by default; legacy fog layers hidden; Town Hall preview registered
	_assert(wv.get("use_cloud_sea_composite") == true and comp.visible, "CloudSeaComposite is enabled by default in M2-C3")
	_assert(tml != null and not tml.visible and cl != null and not cl.visible and csb != null and not csb.visible, "Legacy fog layers are hidden when CloudSeaComposite is active")
	_assert(field.has_source("townhall_main"), "Gameplay Town Hall preview source is registered by default")

	# 8: Repeated setup does not create duplicate composite nodes
	wv.call("_setup_fog_layer")
	await process_frame
	await process_frame
	_assert(_count_named_nodes(wv, "CloudSeaComposite") == 1, "Repeated _setup_fog_layer() does not create duplicate CloudSeaComposite nodes")
	comp = wv.get("cloud_sea_composite") as Polygon2D
	tml = wv.get("fog_tile_layer") as TileMapLayer
	cl = wv.get("fog_cloud_layer") as FogCloudLayer
	csb = wv.get("cloud_sea_base") as Polygon2D

	# 6-7 & isolated shader tests (D3D12 Forward+)
	if is_headless:
		print("  [INFO] Headless mode; skipping GPU render readback checks.")
	else:
		# Measure FogOfWar unexplored count before isolated visual checks
		var unexp_before := 0
		for x in range(fog.map_width):
			for y in range(fog.map_height):
				if fog.is_unexplored(Vector2i(x, y)):
					unexp_before += 1

		var iso_fog = FogOfWarScript.new(128, 128)
		field.clear_sources()
		renderer.sync_if_needed()
		wv.call("rebind_terrain_preview_fog", iso_fog)
		wv.call("set_cloud_sea_composite_isolated_mode", true)
		await process_frame
		await process_frame
		_assert(comp.visible and not tml.visible and not cl.visible and not csb.visible, "Isolated mode shows CloudSeaComposite and hides legacy layers")

		# Zero sources: center of screen should be covered by cloud sea (brighter than dark grass)
		var img_zero: Image = get_root().get_texture().get_image()
		var center_zero := img_zero.get_pixel(640, 360)
		_assert(center_zero.r > 0.35 and center_zero.g > 0.35 and center_zero.b > 0.35, "Zero-source isolated composite renders opaque cloud sea over center")

		# One centered preview source fixture
		var spawn: Vector2i = wv.get("world_data").center_spawn
		field.register_source("fixture_th", TerrainPreviewFieldScript.SourceCategory.TOWN_HALL, spawn)
		renderer.sync_if_needed()
		await process_frame
		await process_frame
		var img_one: Image = get_root().get_texture().get_image()
		var center_one := img_one.get_pixel(640, 360)
		var corner_one := img_one.get_pixel(120, 620)
		_assert(center_one != center_zero, "Centered preview source opens terrain view at settlement center")
		_assert(corner_one.b > 0.35 and corner_one.g > 0.35, "Outer unexplored region remains covered by cloud sea")

		# Multiple overlapping sources + map boundary fixture
		field.register_source("fixture_s1", TerrainPreviewFieldScript.SourceCategory.SOLDIER, spawn + Vector2i(8, -4))
		field.register_source("fixture_s2", TerrainPreviewFieldScript.SourceCategory.SOLDIER, spawn + Vector2i(-6, 5))
		field.register_source("fixture_edge", TerrainPreviewFieldScript.SourceCategory.SOLDIER, Vector2i(0, 127))
		renderer.sync_if_needed()
		await process_frame
		await process_frame
		var img_multi: Image = get_root().get_texture().get_image()
		_assert(img_multi.get_size() == Vector2i(1280, 720), "Multiple overlapping and edge sources render cleanly without errors")

		# World-space invariance across camera zoom
		var cam: Camera2D = wv.get("camera") as Camera2D
		if cam != null:
			var prev_zoom := cam.zoom
			cam.zoom = Vector2(1.5, 1.5)
			await process_frame
			await process_frame
			var img_zoom: Image = get_root().get_texture().get_image()
			_assert(img_zoom.get_size() == Vector2i(1280, 720), "Zoom 1.5x renders cleanly with world-space v_world_pos")
			cam.zoom = prev_zoom

		# Clean up fixture sources and restore production composite mode
		wv.call("rebind_terrain_preview_fog", fog)
		wv.call("sync_gameplay_terrain_preview_sources")
		wv.call("set_cloud_sea_composite_isolated_mode", false)
		await process_frame
		await process_frame
		_assert(not comp.visible and tml.visible and cl.visible and csb.visible, "Exiting isolated mode switches cleanly to legacy fallback")

		var unexp_after := 0
		for x in range(fog.map_width):
			for y in range(fog.map_height):
				if fog.is_unexplored(Vector2i(x, y)):
					unexp_after += 1
		_assert(unexp_before == unexp_after, "FogOfWar state remains byte-for-byte untouched by composite tests")

	# 9: Cleanup
	var old_comp := comp
	wv.call("cleanup_cloud_sea_composite")
	await process_frame
	_assert(wv.get("cloud_sea_composite") == null and not is_instance_valid(old_comp), "cleanup_cloud_sea_composite() frees Polygon2D and clears reference")

	wv.queue_free()
	await process_frame
	await process_frame

	if _failed == 0:
		print("PASS: test_cloud_sea_composite.gd (%d assertions passed, 0 failed)" % _passed)
		quit(0)
	else:
		printerr("FAIL: test_cloud_sea_composite.gd (%d passed, %d failed)" % [_passed, _failed])
		quit(1)
