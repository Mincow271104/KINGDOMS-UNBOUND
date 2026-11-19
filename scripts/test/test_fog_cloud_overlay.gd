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

func _run() -> void:
	print("=== Test: Fog Cloud Overlay (C1) ===")

	# 1. All 3 Version A Main Cloud textures load & preserve transparency
	var layer := FogCloudLayer.new()
	var textures: Array[Texture2D] = layer.get_loaded_textures()
	var expected_sizes: Array[Vector2i] = [Vector2i(144, 92), Vector2i(160, 84), Vector2i(136, 88)]
	_assert(textures.size() == 3, "Expected 3 Version A cloud textures loaded, got %d" % textures.size())
	for i in range(textures.size()):
		var tex: Texture2D = textures[i]
		_assert(tex != null, "Cloud texture %d failed to load" % i)
		if tex != null:
			var img: Image = tex.get_image()
			_assert(img != null and img.get_size() == expected_sizes[i], "Cloud texture %d must match expected Version A size %s" % [i, str(expected_sizes[i])])
			if img != null:
				var has_alpha_zero := false
				var has_opaque := false
				for y in range(img.get_height()):
					for x in range(img.get_width()):
						var a: float = img.get_pixel(x, y).a
						if a < 0.01:
							has_alpha_zero = true
						elif a > 0.99:
							has_opaque = true
				_assert(has_alpha_zero and has_opaque, "Cloud texture %d must preserve alpha transparency" % i)

	# 2. Nearest-neighbor rendering confirmed
	_assert(layer.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "FogCloudLayer must use TEXTURE_FILTER_NEAREST")

	# 3. Deterministic composition confirmed
	var fog_a := FogOfWar.new(64, 64)
	fog_a.reveal_circle(Vector2i(32, 32), 10)
	var fog_b := FogOfWar.new(64, 64)
	fog_b.reveal_circle(Vector2i(32, 32), 10)

	var layer_a := FogCloudLayer.new()
	var layer_b := FogCloudLayer.new()
	get_root().add_child(layer_a)
	get_root().add_child(layer_b)
	layer_a.configure(fog_a, 424242, FogCloudLayer.DensityPreset.BALANCED)
	layer_b.configure(fog_b, 424242, FogCloudLayer.DensityPreset.BALANCED)
	await process_frame

	var pos_a: Array[Vector2] = layer_a.get_active_cloud_positions()
	var pos_b: Array[Vector2] = layer_b.get_active_cloud_positions()
	pos_a.sort()
	pos_b.sort()
	_assert(pos_a.size() > 0, "Expected non-zero clouds in unexplored regions")
	_assert(pos_a == pos_b, "Deterministic placement failed for identical seed & fog state")

	# Verify spawned Sprite2D nearest-neighbor filter, Version A usage, distribution, bounds & no cloud over VISIBLE/EXPLORED
	var all_sprites_nearest := true
	var any_over_explored_or_visible := false
	var any_out_of_bounds := false
	var any_legacy_48 := false
	var kind_counts := {0: 0, 1: 0, 2: 0}
	for chunk_arr in layer_a._chunk_nodes.values():
		for sp in (chunk_arr as Array):
			if sp is Sprite2D:
				var sprite := sp as Sprite2D
				if sprite.texture_filter != CanvasItem.TEXTURE_FILTER_NEAREST:
					all_sprites_nearest = false
				if sprite.texture == null or sprite.texture.get_size() == Vector2(48, 48):
					any_legacy_48 = true
				for k in range(textures.size()):
					if sprite.texture == textures[k]:
						kind_counts[k] = int(kind_counts[k]) + 1
				var cell: Vector2i = IsoMath.local_to_map(sprite.position)
				if not IsoMath.is_in_bounds(cell, fog_a.map_width, fog_a.map_height):
					any_out_of_bounds = true
				elif not fog_a.is_unexplored(cell):
					any_over_explored_or_visible = true
	_assert(all_sprites_nearest, "Every cloud Sprite2D must use TEXTURE_FILTER_NEAREST")
	_assert(not any_legacy_48, "Foreground must use Version A textures rather than legacy 48x48")
	_assert(not any_out_of_bounds, "All cloud Sprite2D centers must be within map bounds")
	_assert(not any_over_explored_or_visible, "No cloud may appear over VISIBLE or EXPLORED terrain")
	_assert(int(kind_counts[0]) > 0 and int(kind_counts[1]) > 0 and int(kind_counts[2]) > 0, "All 3 Version A morphologies must appear in foreground distribution")

	# Different seed produces varied placement
	var layer_diff := FogCloudLayer.new()
	get_root().add_child(layer_diff)
	layer_diff.configure(fog_a, 987654, FogCloudLayer.DensityPreset.BALANCED)
	await process_frame
	var pos_diff: Array[Vector2] = layer_diff.get_active_cloud_positions()
	pos_diff.sort()
	_assert(pos_diff.size() > 0 and pos_diff != pos_a, "Different seeds must produce valid, varied placements")
	layer_diff.queue_free()

	# Repeated sync_full produces no duplicate child nodes
	layer_a.sync_full()
	await process_frame
	_assert(layer_a.get_child_count() == layer_a.get_active_cloud_count(), "Repeated sync_full must not leave duplicate child nodes")

	# 4. Incremental update removes clouds when region becomes visible & matches full sync
	var dirty: Array[Vector2i] = []
	for dx in range(-5, 6):
		for dy in range(-5, 6):
			if absi(dx) + absi(dy) <= 5:
				var c := Vector2i(14 + dx, 14 + dy)
				if fog_a.is_unexplored(c):
					fog_a.set_state(c, FogOfWar.State.VISIBLE)
					dirty.append(c)
	layer_a.update_dirty_cells(dirty)
	await process_frame

	# Check no cloud remains over newly visible pocket
	var cloud_in_new_visible := false
	for p in layer_a.get_active_cloud_positions():
		var c: Vector2i = IsoMath.local_to_map(p)
		if not fog_a.is_unexplored(c):
			cloud_in_new_visible = true
	_assert(not cloud_in_new_visible, "Incremental update must remove clouds from newly visible cells")

	# Compare incremental sync against fresh full sync
	layer_b.configure(fog_a, 424242, FogCloudLayer.DensityPreset.BALANCED)
	await process_frame
	var inc_pos: Array[Vector2] = layer_a.get_active_cloud_positions()
	var full_pos: Array[Vector2] = layer_b.get_active_cloud_positions()
	inc_pos.sort()
	full_pos.sort()
	_assert(inc_pos == full_pos, "Incremental update_dirty_cells() must match full sync_full()")

	# 5. Day / Dusk / Night palette tinting non-destructive
	layer_a.apply_day_night_tint(12.0)
	var c_day: Color = layer_a.modulate
	layer_a.apply_day_night_tint(18.75)
	var c_dusk: Color = layer_a.modulate
	layer_a.apply_day_night_tint(22.0)
	var c_night: Color = layer_a.modulate
	_assert(c_day != c_dusk and c_dusk != c_night and c_day != c_night, "Day/Dusk/Night cloud tints must be distinct")

	# 6. WorldView integration: A2 FogTileMapLayer + CloudSeaBase + FogCloudLayer z-ordering, shader & lifecycle
	var wv_scene: PackedScene = load("res://scenes/world/world_view.tscn") as PackedScene
	var wv: Node2D = wv_scene.instantiate() as Node2D
	get_root().add_child(wv)
	await process_frame
	await process_frame

	var tml: TileMapLayer = wv.get("fog_tile_layer") as TileMapLayer
	var csb: Polygon2D = wv.get("cloud_sea_base") as Polygon2D
	var cl: FogCloudLayer = wv.get("fog_cloud_layer") as FogCloudLayer
	var comp: Polygon2D = wv.get("cloud_sea_composite") as Polygon2D
	var cursor_hl: Node2D = wv.get_node_or_null("World/CursorHighlight") as Node2D
	var hud_node: CanvasLayer = wv.get_node_or_null("HUD") as CanvasLayer
	_assert(tml != null and is_instance_valid(tml), "A2 FogTileMapLayer must remain intact in WorldView")
	_assert(csb != null and is_instance_valid(csb) and csb is Polygon2D, "CloudSeaBase Polygon2D must exist in WorldView")
	_assert(cl != null and is_instance_valid(cl), "FogCloudLayer must be present in WorldView")
	_assert(comp != null and comp.visible and not csb.visible and not cl.visible and not tml.visible, "Composite mode active by default; legacy fog layers hidden (no duplicate fog)")
	wv.call("set_debug_fog_disabled", true)
	_assert(not comp.visible and not csb.visible and not cl.visible and not tml.visible, "Composite mode: set_debug_fog_disabled(true) hides all fog layers")
	wv.call("set_debug_fog_disabled", false)
	_assert(comp.visible and not csb.visible and not cl.visible and not tml.visible, "Composite mode: set_debug_fog_disabled(false) restores CloudSeaComposite only")
	# Switch to Legacy mode to validate legacy cloud overlay behavior
	wv.call("set_cloud_sea_composite_isolated_mode", false)
	wv.call("_sync_full_fog_layer")
	_assert(not comp.visible and csb.visible and cl.visible and tml.visible, "Legacy mode enables CloudSeaBase, FogCloudLayer, and FogTileMapLayer")
	_assert(cursor_hl != null and cursor_hl.z_index == 10, "CursorHighlight must remain at z=10")
	_assert(hud_node != null, "HUD CanvasLayer must remain intact")
	if tml != null and csb != null and cl != null:
		_assert(cl.get_density_preset() == FogCloudLayer.DensityPreset.BALANCED, "WorldView FogCloudLayer must use A_Medium (BALANCED) preset")
		_assert(tml.z_index == 5 and csb.z_index == 6 and cl.z_index == 7, "Rendering order must be FogTileMapLayer (z=5) < CloudSeaBase (z=6) < FogCloudLayer (z=7)")
		_assert(csb.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "CloudSeaBase must use TEXTURE_FILTER_NEAREST")
		var mat := csb.material as ShaderMaterial
		_assert(mat != null and mat.shader != null, "CloudSeaBase must have ShaderMaterial and Shader")
		if mat != null:
			var base_tex := mat.get_shader_parameter("base_tex") as Texture2D
			var wisp_tex := mat.get_shader_parameter("wisp_tex") as Texture2D
			_assert(base_tex != null and base_tex.resource_path.ends_with("cloud_sea_base_v4_512.png"), "CloudSeaBase base_tex must use cloud_sea_base_v4_512.png")
			_assert(wisp_tex != null and wisp_tex.resource_path.ends_with("cloud_sea_base_v5_wisps_512.png"), "CloudSeaBase wisp_tex must use cloud_sea_base_v5_wisps_512.png")
			_assert(mat.get_shader_parameter("fog_mask") == cl.get_fog_mask_texture(), "CloudSeaBase fog_mask must bind to FogCloudLayer.get_fog_mask_texture()")
			_assert(is_equal_approx(float(mat.get_shader_parameter("tex_scale")), 512.0), "CloudSeaBase tex_scale must be 512.0")
			_assert(is_equal_approx(float(mat.get_shader_parameter("wisp_scale")), 640.0), "CloudSeaBase wisp_scale must be 640.0")
			_assert(is_equal_approx(float(mat.get_shader_parameter("use_wisp")), 1.0), "CloudSeaBase use_wisp must be 1.0")
			_assert(is_equal_approx(float(mat.get_shader_parameter("base_alpha")), 0.96), "CloudSeaBase base_alpha must be 0.96")
			var fow: FogOfWar = wv.get("fog_of_war") as FogOfWar
			_assert(mat.get_shader_parameter("map_size") == Vector2(float(fow.map_width), float(fow.map_height)), "CloudSeaBase map_size must match FogOfWar dimensions")

			# Initial mask coverage: unexplored vs visible
			var mask_img := cl.get_fog_mask_image()
			_assert(mask_img != null and mask_img.get_pixel(5, 5).r > 0.99, "Initial fog mask must cover far unexplored cell (5,5)")
			_assert(mask_img.get_pixel(fow.map_width / 2, fow.map_height / 2).r < 0.01, "Initial fog mask must clear visible center cell")

			# Incremental update via WorldView._update_fog_visuals
			var inc_dirty: Array[Vector2i] = []
			for dx in range(-3, 4):
				for dy in range(-3, 4):
					if absi(dx) + absi(dy) <= 3:
						var c := Vector2i(10 + dx, 10 + dy)
						if fow.is_unexplored(c):
							fow.set_state(c, FogOfWar.State.EXPLORED)
							inc_dirty.append(c)
			wv.call("_update_fog_visuals", inc_dirty)
			_assert(cl.get_fog_mask_image().get_pixel(10, 10).r < 0.01, "Incremental update must clear newly explored cell in fog_mask")
			_assert(mat.get_shader_parameter("fog_mask") == cl.get_fog_mask_texture(), "CloudSeaBase fog_mask remains connected after incremental update")

	# Lifecycle: overlay toggle, debug_fog_disabled & repeated _setup_fog_layer produces no duplicate CloudSeaBase
	wv.call("set_cloud_overlay_enabled", false)
	_assert(not csb.visible and not cl.visible, "set_cloud_overlay_enabled(false) hides both CloudSeaBase and FogCloudLayer")
	wv.call("set_cloud_overlay_enabled", true)
	_assert(csb.visible and cl.visible, "set_cloud_overlay_enabled(true) shows both CloudSeaBase and FogCloudLayer")
	wv.call("set_debug_fog_disabled", true)
	_assert(not csb.visible and not cl.visible and not tml.visible, "set_debug_fog_disabled(true) hides CloudSeaBase, FogCloudLayer, and FogTileMapLayer")
	wv.call("set_debug_fog_disabled", false)
	_assert(csb.visible and cl.visible and tml.visible, "Legacy mode: set_debug_fog_disabled(false) restores CloudSeaBase, FogCloudLayer, and FogTileMapLayer")
	wv.call("set_cloud_sea_composite_isolated_mode", true)
	_assert(comp.visible and not csb.visible and not cl.visible and not tml.visible, "Switching back to Composite mode hides legacy layers cleanly")

	wv.call("_setup_fog_layer")
	await process_frame
	var world_node := wv.get_node("World")
	var csb_count := 0
	for child in world_node.get_children():
		if child is Polygon2D and child.name.begins_with("CloudSeaBase"):
			csb_count += 1
	_assert(csb_count == 1, "Repeated _setup_fog_layer must not leave duplicate CloudSeaBase nodes (got %d)" % csb_count)

	# 13. C1.6.3-R1: Candidate Layout Cache reuse, invalidation, and dynamic FogOfWar re-evaluation
	var r1_fow := FogOfWar.new(64, 64)
	var r1_layer := FogCloudLayer.new()
	root.add_child(r1_layer)
	r1_layer.configure(r1_fow, 77777, FogCloudLayer.DensityPreset.BALANCED)
	var key_base: String = r1_layer.call("_get_layout_key")
	var cands_first: Dictionary = r1_layer._chunk_candidates
	var count_initial := r1_layer.get_active_cloud_count()
	_assert(r1_layer._layout_cache.has(key_base), "Layout cache must store key after initial configure/sync_full()")
	_assert(count_initial > 0, "Initial 64x64 unexplored map must spawn clouds")

	# Same key -> cache hit (reuses exact candidate dictionary reference)
	r1_layer.sync_full()
	var cands_second: Dictionary = r1_layer._chunk_candidates
	_assert(cands_second == cands_first and cands_second.size() == cands_first.size(), "Repeated sync_full() with same key must reuse cached candidate dictionary")

	# Dynamic FogOfWar re-evaluation on cache hit: reveal a 12x12 region and sync_full()
	for rx in range(24, 36):
		for ry in range(24, 36):
			r1_fow.set_state(Vector2i(rx, ry), FogOfWar.State.EXPLORED)
	r1_layer.sync_full()
	var count_after_reveal := r1_layer.get_active_cloud_count()
	_assert(count_after_reveal < count_initial, "sync_full() after FogOfWar reveal must re-evaluate visibility even on layout cache hit (%d < %d)" % [count_after_reveal, count_initial])
	var any_stale_revealed := false
	var r1_texs := r1_layer.get_loaded_textures()
	for ch in r1_layer.get_children():
		if ch is Sprite2D:
			var sc_f: float = ch.scale.x
			var k_idx: int = r1_texs.find(ch.texture)
			if k_idx < 0:
				k_idx = 0
			if not r1_layer._is_opaque_footprint_unexplored(ch.position, k_idx, sc_f):
				any_stale_revealed = true
				break
	_assert(not any_stale_revealed, "Zero stale clouds may remain over revealed region after cached sync_full()")

	# Seed change invalidates cache key
	r1_layer.configure(r1_fow, 88888, FogCloudLayer.DensityPreset.BALANCED)
	var key_seed2: String = r1_layer.call("_get_layout_key")
	_assert(key_seed2 != key_base, "Changing world seed must produce a distinct layout cache key")
	_assert(r1_layer._layout_cache.has(key_seed2), "Layout cache must store new seed key")

	# Map dimension change invalidates cache key
	var r1_fow_small := FogOfWar.new(32, 32)
	r1_layer.configure(r1_fow_small, 77777, FogCloudLayer.DensityPreset.BALANCED)
	var key_dim2: String = r1_layer.call("_get_layout_key")
	_assert(key_dim2 != key_base, "Changing map dimensions must produce a distinct layout cache key")
	_assert(r1_layer._layout_cache.has(key_dim2), "Layout cache must store new dimension key")

	# Density preset change invalidates cache key
	r1_layer.configure(r1_fow, 77777, FogCloudLayer.DensityPreset.DENSE)
	var key_dense: String = r1_layer.call("_get_layout_key")
	_assert(key_dense != key_base, "Changing DensityPreset must produce a distinct layout cache key")
	_assert(r1_layer._layout_cache.has(key_dense), "Layout cache must store new DensityPreset key")

	# 14. C1.6.3-R1: Exhaustive stride=1 equivalence across assets, scales, pockets, strips, and boundaries
	var eq_fow := FogOfWar.new(32, 32)
	# Pattern 1: 1-cell explored pocket
	eq_fow.set_state(Vector2i(8, 8), FogOfWar.State.EXPLORED)
	# Pattern 2: narrow horizontal strip (1 cell tall)
	for hx in range(12, 22):
		eq_fow.set_state(Vector2i(hx, 6), FogOfWar.State.EXPLORED)
	# Pattern 3: narrow vertical strip (1 cell wide)
	for vy in range(10, 20):
		eq_fow.set_state(Vector2i(20, vy), FogOfWar.State.EXPLORED)
	# Pattern 4: diagonal strip
	for d in range(10, 20):
		eq_fow.set_state(Vector2i(d, d + 4), FogOfWar.State.EXPLORED)
	# Pattern 5: boundary edge explored cells
	eq_fow.set_state(Vector2i(0, 0), FogOfWar.State.EXPLORED)
	eq_fow.set_state(Vector2i(31, 0), FogOfWar.State.EXPLORED)
	eq_fow.set_state(Vector2i(0, 31), FogOfWar.State.EXPLORED)
	eq_fow.set_state(Vector2i(31, 31), FogOfWar.State.EXPLORED)

	var eq_layer := FogCloudLayer.new()
	root.add_child(eq_layer)
	eq_layer.configure(eq_fow, 12345, FogCloudLayer.DensityPreset.BALANCED)

	var test_centers := [
		FogCloudLayer._continuous_map_to_local(8.0, 8.0),
		FogCloudLayer._continuous_map_to_local(16.0, 6.0),
		FogCloudLayer._continuous_map_to_local(20.0, 14.0),
		FogCloudLayer._continuous_map_to_local(15.0, 19.0),
		FogCloudLayer._continuous_map_to_local(0.0, 0.0),
		FogCloudLayer._continuous_map_to_local(31.0, 31.0),
		FogCloudLayer._continuous_map_to_local(4.0, 4.0),
		FogCloudLayer._continuous_map_to_local(26.0, 26.0),
	]
	var test_scales := [0.82, 1.00, 1.18, 1.50]
	var eq_mismatches := 0
	var eq_cases := 0
	for c_pos in test_centers:
		for k_idx in range(3):
			var pts: PackedVector2Array = eq_layer._opaque_pts_cache[k_idx]
			for sc_val in test_scales:
				eq_cases += 1
				var actual_res: bool = eq_layer._is_opaque_footprint_unexplored(c_pos, k_idx, sc_val)
				# Brute-force stride=1 reference
				var ref_res := true
				var has_in := false
				for off in pts:
					var p: Vector2 = c_pos + off * sc_val
					var gp := Vector2i(
						int(floor((p.x / IsoMath.TILE_WIDTH) + (p.y / IsoMath.TILE_HEIGHT) + 0.5)),
						int(floor((p.y / IsoMath.TILE_HEIGHT) - (p.x / IsoMath.TILE_WIDTH) + 0.5))
					)
					if gp.x >= 0 and gp.x < eq_fow.map_width and gp.y >= 0 and gp.y < eq_fow.map_height:
						has_in = true
						if not eq_fow.is_unexplored(gp):
							ref_res = false
							break
				if not has_in:
					ref_res = false
				if actual_res != ref_res:
					eq_mismatches += 1
	_assert(eq_mismatches == 0, "Optimized exact footprint check must match brute-force stride=1 on all %d edge cases (mismatches=%d)" % [eq_cases, eq_mismatches])

	r1_layer.queue_free()
	eq_layer.queue_free()
	layer.queue_free()
	layer_a.queue_free()
	layer_b.queue_free()
	wv.queue_free()
	await process_frame

	if _failures.is_empty():
		print("PASS: test_fog_cloud_overlay.gd (%d assertions passed, 0 failed)" % _assertions)
		quit(0)
	else:
		printerr("FAIL: test_fog_cloud_overlay.gd (%d/%d assertions failed)" % [_failures.size(), _assertions])
		quit(1)
