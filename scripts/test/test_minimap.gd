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
	print("=== TEST SUITE: Phase 3 HUD Minimap ===")
	_run_tests()

func _run_tests() -> void:
	var wv: Node = WorldViewScene.instantiate()
	wv.world_seed = 12345
	root.add_child(wv)
	await process_frame
	await process_frame

	var mm = wv.hud.get_minimap()
	_assert(mm != null and is_instance_valid(mm), "MinimapPanel exists on HUD")
	_assert(mm._map_width == 128 and mm._map_height == 128, "Minimap dimensions match 128x128 V6 world")
	_assert(mm._img != null and mm._img.get_width() == 128 and mm._img.get_height() == 128, "Minimap uses single 128x128 Image")

	# 1. UNEXPLORED cell has uniform dark pixel (no terrain/biome leak)
	var unexp_cell := Vector2i(6, 6)
	_assert(wv.fog_of_war.is_unexplored(unexp_cell), "Probe cell (6, 6) is UNEXPLORED")
	_assert(mm.get_pixel_color(unexp_cell).is_equal_approx(mm.UNEXPLORED_COLOR), "Minimap UNEXPLORED pixel hides terrain/biome")

	# 2. VISIBLE cell near starter has non-unexplored color
	var vis_cell: Vector2i = wv.world_data.center_spawn
	var vis_col: Color = mm.get_pixel_color(vis_cell)
	_assert(not vis_col.is_equal_approx(mm.UNEXPLORED_COLOR), "Minimap VISIBLE cell shows terrain color")

	# 3. Army movement updates minimap pixel to VISIBLE, then leaving dims to EXPLORED
	var scout_cell := Vector2i(20, 20)
	var u_ids: Array[String] = wv.tactical_military_mgr.spawn_units_at_base(1, false, scout_cell)
	var u: Node2D = wv.tactical_military_mgr.get_unit(u_ids[0])
	u.current_cell = scout_cell
	wv._on_tactical_unit_moved(u.unit_id, scout_cell)
	var scout_vis_col: Color = mm.get_pixel_color(scout_cell)
	_assert(not scout_vis_col.is_equal_approx(mm.UNEXPLORED_COLOR), "Minimap updates immediately when military unit scouts cell")
	wv.tactical_military_mgr.despawn_units([u.unit_id])
	var scout_exp_col: Color = mm.get_pixel_color(scout_cell)
	_assert(not scout_exp_col.is_equal_approx(mm.UNEXPLORED_COLOR) and scout_exp_col.get_luminance() < scout_vis_col.get_luminance(), "Minimap EXPLORED pixel is darker/muted than VISIBLE pixel")

	# 4. Enemy marker security: hidden in EXPLORED, shown only in VISIBLE
	var enemies = wv.enemy_military_mgr.spawn_enemy_force("rival_military", scout_cell, 1, wv.nav, false, false, "")
	var snap_hidden: Dictionary = mm.get_visible_markers_snapshot()
	_assert(snap_hidden["enemy_units"].is_empty(), "Minimap does NOT leak enemy marker in EXPLORED cell")
	var u2_ids: Array[String] = wv.tactical_military_mgr.spawn_units_at_base(1, false, scout_cell + Vector2i(1, 0))
	var u2: Node2D = wv.tactical_military_mgr.get_unit(u2_ids[0])
	u2.current_cell = scout_cell + Vector2i(1, 0)
	wv._on_tactical_unit_moved(u2.unit_id, u2.current_cell)
	var snap_vis: Dictionary = mm.get_visible_markers_snapshot()
	_assert(snap_vis["enemy_units"].size() >= 1, "Minimap shows enemy marker when cell is VISIBLE")
	_assert(snap_vis["town_hall"].size() == 1 and snap_vis["player_units"].size() >= 1, "Minimap markers include Town Hall and player military unit")
	wv.tactical_military_mgr.despawn_units([u2.unit_id])

	# 5. Legacy 64x64 V3 save resizes Minimap to 64x64, and V6 reload restores 128x128
	var v6_save := SaveManager.serialize_world_state(wv)
	var wv3: Node = WorldViewScene.instantiate()
	wv3.world_seed = 12345
	wv3.world_generator_version = 3
	root.add_child(wv3)
	await process_frame
	var v3_save := SaveManager.serialize_world_state(wv3)
	wv3.queue_free()
	await process_frame

	SaveManager.apply_loaded_state_to_world(wv, v3_save)
	_assert(mm._map_width == 64 and mm._img.get_width() == 64, "Minimap resizes cleanly to 64x64 on V3 load")
	SaveManager.apply_loaded_state_to_world(wv, v6_save)
	_assert(mm._map_width == 128 and mm._img.get_width() == 128, "Minimap restores 128x128 on V6 reload")
	_assert(not mm.get_pixel_color(scout_cell).is_equal_approx(mm.UNEXPLORED_COLOR), "Minimap preserves remembered EXPLORED pixel after save/load")

	wv.queue_free()
	await process_frame
	print("========================================================")
	print("PHASE 3 MINIMAP RESULTS: %d passed, %d failed" % [_passed, _failed])
	print("========================================================")
	quit(0 if _failed == 0 else 1)
