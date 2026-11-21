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
	print("=== TEST SUITE: Phase 3 Visual Fog of War & Dynamic Vision ===")
	_run_tests()

func _run_tests() -> void:
	var wv: Node = WorldViewScene.instantiate()
	wv.world_seed = 12345
	root.add_child(wv)
	await process_frame
	await process_frame

	var wd: WorldGenerator.WorldData = wv.world_data
	var fow: FogOfWar = wv.fog_of_war
	var fog_tml: TileMapLayer = wv.fog_tile_layer
	var comp: Polygon2D = wv.get("cloud_sea_composite") as Polygon2D
	_assert(fog_tml != null and is_instance_valid(fog_tml), "FogTileMapLayer node exists in WorldView")
	_assert(comp != null and comp.visible and not fog_tml.visible, "Composite mode active by default and legacy FogTileMapLayer hidden (no duplicate fog)")
	_assert(fog_tml.tile_set != null and fog_tml.tile_set.tile_size == Vector2i(32, 16), "FogTileMapLayer uses 32x16 isometric TileSet")
	_assert(fog_tml.position == Vector2(-16.0, -8.0), "FogTileMapLayer aligned with TerrainTileMapLayer (-16, -8)")

	# Switch to Legacy mode to validate FogTileMapLayer presentation
	wv.set_cloud_sea_composite_isolated_mode(false)
	wv._sync_full_fog_layer()
	_assert(comp != null and not comp.visible and fog_tml != null and fog_tml.visible, "Legacy mode shows FogTileMapLayer and hides CloudSeaComposite")

	# 1. Town Hall owned territory is 100% VISIBLE & FogTileMapLayer erased there
	var tmgr = wv.get("territory_mgr")
	var all_owned_visible := tmgr != null
	var all_owned_clear_in_tml := tmgr != null
	if tmgr != null:
		for oc in tmgr.get_owned_cells():
			if not fow.is_visible(oc):
				all_owned_visible = false
				break
			if fog_tml.get_cell_source_id(oc) != -1:
				all_owned_clear_in_tml = false
				break
	_assert(all_owned_visible, "100% of Town Hall owned_cells are VISIBLE")
	_assert(all_owned_clear_in_tml, "FogTileMapLayer erases fog on all owned VISIBLE cells")

	# 2. Unexplored cell far from center is UNEXPLORED and alt=0 in FogTileMapLayer
	var far_cell := Vector2i(5, 5)
	_assert(fow.is_unexplored(far_cell), "Far cell (5, 5) starts UNEXPLORED")
	_assert(fog_tml.get_cell_source_id(far_cell) == 0 and fog_tml.get_cell_alternative_tile(far_cell) == 0, "FogTileMapLayer renders UNEXPLORED cell with opaque alt=0")

	# 3. Ordinary citizen placed outside owned territory does NOT reveal unexplored cell
	var scout_test_cell := Vector2i(10, 10)
	if not wv.citizen_list.is_empty():
		var cit = wv.citizen_list[0]
		var orig_c: Vector2i = cit.get("current_cell")
		cit.set("current_cell", scout_test_cell)
		wv.refresh_world_vision()
		_assert(fow.is_unexplored(scout_test_cell), "Ordinary citizen outside territory does NOT reveal UNEXPLORED cells")
		# Extensible specialized scout hook
		cit.set_meta("_orig_cell", orig_c)
		cit.set("current_cell", orig_c)
		wv.refresh_world_vision()

	# 4. Military unit scouting, movement, overlap, and leaving -> EXPLORED
	var scout_a := Vector2i(18, 18)
	var scout_b := Vector2i(22, 18)
	var shared_cell := Vector2i(20, 18)
	var has_spawn: bool = wv.tactical_military_mgr != null and wv.tactical_military_mgr.has_method("spawn_units_at_base")
	if has_spawn:
		var u1_ids: Array[String] = wv.tactical_military_mgr.spawn_units_at_base(1, false, scout_a)
		var u1: Node2D = wv.tactical_military_mgr.get_unit(u1_ids[0])
		u1.current_cell = scout_a
		wv._on_tactical_unit_moved(u1.unit_id, scout_a)
		_assert(fow.is_visible(scout_a) and fow.is_visible(shared_cell), "Player military unit reveals radius 4 immediately on spawn")
		_assert(fog_tml.get_cell_source_id(shared_cell) == -1, "FogTileMapLayer clears newly VISIBLE cell")
		var u2_ids: Array[String] = wv.tactical_military_mgr.spawn_units_at_base(1, false, scout_b)
		var u2: Node2D = wv.tactical_military_mgr.get_unit(u2_ids[0])
		u2.current_cell = scout_b
		wv._on_tactical_unit_moved(u2.unit_id, scout_b)
		_assert(fow.is_visible(shared_cell), "Overlapping units keep shared cell VISIBLE")
		u1.current_cell = Vector2i(12, 12)
		wv._on_tactical_unit_moved(u1.unit_id, u1.current_cell)
		_assert(fow.is_visible(shared_cell), "Removing/moving first unit preserves shared VISIBLE via second unit")
		_assert(fow.get_state(Vector2i(18, 14)) == FogOfWar.State.EXPLORED, "Vacated cell transitions from VISIBLE to EXPLORED")
		_assert(fog_tml.get_cell_source_id(Vector2i(18, 14)) == 0 and fog_tml.get_cell_alternative_tile(Vector2i(18, 14)) == 1, "FogTileMapLayer renders EXPLORED cell with mist alt=1")
		wv.tactical_military_mgr.despawn_units([u1.unit_id, u2.unit_id])
		_assert(fow.get_state(shared_cell) == FogOfWar.State.EXPLORED and not fow.is_visible(shared_cell), "Removing final observer degrades cell to EXPLORED (never UNEXPLORED)")
	else:
		_assert(false, "Player military unit reveals radius 4 immediately on spawn (spawn_units_at_base unavailable)")
		_assert(false, "FogTileMapLayer clears newly VISIBLE cell (spawn_units_at_base unavailable)")
		_assert(false, "Overlapping units keep shared cell VISIBLE (spawn_units_at_base unavailable)")
		_assert(false, "Removing/moving first unit preserves shared VISIBLE via second unit (spawn_units_at_base unavailable)")
		_assert(false, "Vacated cell transitions from VISIBLE to EXPLORED (spawn_units_at_base unavailable)")
		_assert(false, "FogTileMapLayer renders EXPLORED cell with mist alt=1 (spawn_units_at_base unavailable)")
		_assert(false, "Removing final observer degrades cell to EXPLORED (spawn_units_at_base unavailable)")

	# 5. Dynamic enemy unit visibility filtering under UNEXPLORED and EXPLORED
	var enemy_cell := shared_cell # currently EXPLORED, NOT VISIBLE
	var has_enemy_spawn: bool = wv.enemy_military_mgr != null and wv.enemy_military_mgr.has_method("spawn_enemy_force")
	if has_spawn and has_enemy_spawn:
		var enemies = wv.enemy_military_mgr.spawn_enemy_force("rival_military", enemy_cell, 1, wv.nav, false, false, "")
		wv._refresh_dynamic_actor_visibility()
		_assert(enemies.size() >= 1 and not enemies[0].visible, "Live enemy unit in EXPLORED-only cell is hidden (visible == false)")
		var u3_ids: Array[String] = wv.tactical_military_mgr.spawn_units_at_base(1, false, enemy_cell + Vector2i(1, 0))
		var u3: Node2D = wv.tactical_military_mgr.get_unit(u3_ids[0])
		u3.current_cell = enemy_cell + Vector2i(1, 0)
		wv._on_tactical_unit_moved(u3.unit_id, u3.current_cell)
		_assert(enemies[0].visible, "Live enemy unit becomes visible when cell enters active VISIBLE sight")
		wv.tactical_military_mgr.despawn_units([u3.unit_id])
		_assert(not enemies[0].visible, "Live enemy unit hides again when observer leaves")
	else:
		_assert(false, "Live enemy unit in EXPLORED-only cell is hidden (integration API unavailable)")
		_assert(false, "Live enemy unit becomes visible when cell enters active VISIBLE sight (integration API unavailable)")
		_assert(false, "Live enemy unit hides again when observer leaves (integration API unavailable)")

	# 6. Town Hall upgrade immediately reveals newly owned territory
	if tmgr != null:
		var pre_owned: int = tmgr.get_owned_cells().size()
		for b in wd.buildings:
			if b.get("type") == "townhall":
				b["upgrade_level"] = 2
				break
		tmgr.recalculate_territory()
		var post_owned: int = tmgr.get_owned_cells().size()
		var new_owned_all_vis := true
		for oc in tmgr.get_owned_cells():
			if not fow.is_visible(oc):
				new_owned_all_vis = false
				break
		_assert(post_owned > pre_owned and new_owned_all_vis, "Town Hall upgrade expands owned territory and immediately reveals all newly owned cells")
	else:
		_assert(false, "Town Hall upgrade expands owned territory and immediately reveals all newly owned cells (territory_mgr unavailable)")

	# 7. Save/Load V6 and legacy V3 (64x64) FogTileMapLayer resize
	var save_res := SaveManager.save_to_file(wv, "user://test_p3_fog_v6.json")
	_assert(bool(save_res.get("success", false)), "Save V6 with explored fog succeeds")
	var wv3: Node = WorldViewScene.instantiate()
	wv3.world_seed = 12345
	if "world_generator_version" in wv3:
		wv3.set("world_generator_version", 3)
	root.add_child(wv3)
	await process_frame
	var v3_data := SaveManager.serialize_world_state(wv3)
	wv3.queue_free()
	await process_frame
	var load3 := SaveManager.apply_loaded_state_to_world(wv, v3_data)
	_assert(bool(load3.get("success", false)) and wv.fog_of_war.get("map_width") == 64, "Loading V3 save resizes FogOfWar to 64x64")
	_assert(wv.fog_tile_layer.get_cell_source_id(Vector2i(5, 5)) == 0, "FogTileMapLayer renders on 64x64 legacy world")

	var loaded_v6 := SaveManager.load_from_file("user://test_p3_fog_v6.json")
	var load6 := SaveManager.apply_loaded_state_to_world(wv, loaded_v6.get("data", {}))
	_assert(bool(load6.get("success", false)) and wv.fog_of_war.get("map_width") == 128, "Reloading V6 save restores 128x128 FogOfWar")
	_assert(wv.fog_of_war.is_explored(shared_cell) and not wv.fog_of_war.is_visible(shared_cell), "Reloaded V6 preserves EXPLORED cell without stale VISIBLE observer")

	wv.queue_free()
	await process_frame
	print("========================================================")
	print("PHASE 3 FOG RENDERING RESULTS: %d passed, %d failed" % [_passed, _failed])
	print("========================================================")
	quit(0 if _failed == 0 else 1)
