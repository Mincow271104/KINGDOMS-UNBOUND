extends SceneTree

const WorldViewScene = preload("res://scenes/world/world_view.tscn")

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
	print("=== TEST SUITE: Hybrid Visual Boundary System ===")
	_run_tests()

func _run_tests() -> void:
	var wv: Node = WorldViewScene.instantiate()
	wv.world_seed = 12345
	root.add_child(wv)
	await process_frame
	await process_frame

	# 1. BuildingSelectionHighlight approved parameters & 1x1, 2x2, 3x3 geometry
	var hl: BuildingSelectionHighlight = wv.building_highlight
	_assert(hl != null, "BuildingSelectionHighlight exists on WorldView")
	var arm_ratio = hl.get("bracket_arm_ratio") if hl != null else null
	var b_width = hl.get("bracket_width") if hl != null else null
	var inner_w = hl.get("inner_border_width") if hl != null else null
	var inner_c = hl.get("inner_border_color") if hl != null else null
	_assert(arm_ratio != null and is_equal_approx(float(arm_ratio), 0.22), "Corner bracket arm ratio is 0.22")
	_assert(b_width != null and is_equal_approx(float(b_width), 3.0), "Corner bracket width is 3.0px")
	_assert(inner_w != null and is_equal_approx(float(inner_w), 1.5), "Inner diamond width is 1.5px")
	_assert(hl != null and is_equal_approx(hl.fill_color.a, 0.14), "Subtle fill alpha is 0.14")
	_assert(inner_c is Color and is_equal_approx((inner_c as Color).a, 0.55), "Inner line alpha is 0.55")
	_assert(hl != null and hl.border_color.is_equal_approx(Color(1.0, 0.85, 0.25, 0.95)), "Gold corner color matches approved prototype")

	for sz in [Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 3)]:
		hl.set_footprint(Vector2i(63, 62), sz)
		var pts := BuildingSelectionHighlight.compute_diamond_vertices(Vector2i(63, 62), sz)
		_assert(hl.is_active and hl.visible and pts.size() == 4, "Selection active for footprint %dx%d" % [sz.x, sz.y])
	hl.clear_highlight()
	_assert(not hl.is_active and not hl.visible, "clear_highlight() deactivates and hides selection")

	# 2. Fog of War A2 16-mask atlas + incremental vs full sync equivalence
	var fow: FogOfWar = wv.fog_of_war
	var tml: TileMapLayer = wv.fog_tile_layer
	var src: TileSetAtlasSource = tml.tile_set.get_source(0) as TileSetAtlasSource
	var all_masks_present := true
	for mask in range(16):
		if not src.has_tile(Vector2i(mask, 0)):
			all_masks_present = false
			break
	_assert(all_masks_present, "Fog TileSet atlas contains all 16 cardinal bitmask tiles (0..15)")
	_assert(src.has_alternative_tile(Vector2i(0, 0), 1), "Fog TileSet atlas preserves EXPLORED alt=1 on (0,0)")

	# Switch explicitly to legacy FogTileMapLayer mode to test legacy incremental vs full sync
	if wv.has_method("set_cloud_sea_composite_isolated_mode"):
		wv.set_cloud_sea_composite_isolated_mode(false)
	_assert(not wv.use_cloud_sea_composite and tml.visible, "Legacy mode enabled (use_cloud_sea_composite == false, FogTileMapLayer visible)")

	# Incremental reveal via military unit spawn & move
	var probe_center := Vector2i(20, 20)
	if wv.tactical_military_mgr != null and wv.tactical_military_mgr.has_method("spawn_units_at_base"):
		var u_ids: Array[String] = wv.tactical_military_mgr.spawn_units_at_base(1, false, probe_center)
		var u: Node2D = wv.tactical_military_mgr.get_unit(u_ids[0])
		probe_center = u.current_cell
		var edge_unexplored := probe_center + Vector2i(0, -5)
		wv._on_tactical_unit_moved(u.unit_id, probe_center)

		# Neighbor just outside radius 4: (0, -5) has explored neighbor (0, -4) at (0, 1) -> bit 4
		_assert(fow.is_unexplored(edge_unexplored), "Edge neighbor %s is UNEXPLORED" % [edge_unexplored])
		_assert(tml.get_cell_atlas_coords(edge_unexplored).x > 0, "Incremental update assigns non-zero bitmask to UNEXPLORED frontier neighbor")

		# Degrade to EXPLORED by despawning unit
		wv.tactical_military_mgr.despawn_units([u.unit_id])
		_assert(fow.get_state(probe_center) == FogOfWar.State.EXPLORED, "Vacated center degrades to EXPLORED")
		_assert(tml.get_cell_atlas_coords(probe_center) == Vector2i(0, 0) and tml.get_cell_alternative_tile(probe_center) == 1, "Degraded EXPLORED cell uses (0,0) alt=1")
	else:
		_assert(false, "Edge neighbor is UNEXPLORED (spawn_units_at_base unavailable)")
		_assert(false, "Incremental update assigns non-zero bitmask to UNEXPLORED frontier neighbor (spawn_units_at_base unavailable)")
		_assert(false, "Vacated center degrades to EXPLORED (spawn_units_at_base unavailable)")
		_assert(false, "Degraded EXPLORED cell uses (0,0) alt=1 (spawn_units_at_base unavailable)")

	# Compare incremental TileMapLayer state vs full _sync_full_fog_layer() across entire grid
	var fow_w: int = int(fow.get("map_width")) if fow.get("map_width") != null else fow.map_size
	var fow_h: int = int(fow.get("map_height")) if fow.get("map_height") != null else fow.map_size
	var inc_snapshot: Array = []
	for x in range(fow_w):
		for y in range(fow_h):
			var c := Vector2i(x, y)
			inc_snapshot.append([tml.get_cell_source_id(c), tml.get_cell_atlas_coords(c), tml.get_cell_alternative_tile(c)])

	wv._sync_full_fog_layer()
	var mismatch_count: int = 0
	var idx: int = 0
	for x in range(fow_w):
		for y in range(fow_h):
			var c := Vector2i(x, y)
			var cur := [tml.get_cell_source_id(c), tml.get_cell_atlas_coords(c), tml.get_cell_alternative_tile(c)]
			if cur != inc_snapshot[idx]:
				mismatch_count += 1
			idx += 1
	_assert(mismatch_count == 0, "Incremental fog sync and full fog sync produce identical TileMapLayer state (mismatches=%d)" % mismatch_count)

	# Switch back to composite mode and verify visibility toggles cleanly
	if wv.has_method("set_cloud_sea_composite_isolated_mode"):
		wv.set_cloud_sea_composite_isolated_mode(true)
	_assert(wv.use_cloud_sea_composite and not tml.visible and wv.cloud_sea_composite != null and wv.cloud_sea_composite.visible, "Composite mode restored (use_cloud_sea_composite == true, CloudSeaComposite visible, FogTileMapLayer hidden)")

	print("=== HYBRID BOUNDARY VISUALS RESULTS: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
