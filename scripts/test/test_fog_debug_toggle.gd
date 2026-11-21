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
		print("  [FAIL] ", msg)

func _init() -> void:
	_run()

func _run() -> void:
	print("=== TEST SUITE: Phase 5 Debug Fog of War Toggle ===")
	var wv := WorldViewScene.instantiate()
	wv.world_seed = 12345
	root.add_child(wv)
	await process_frame
	await process_frame

	var hud: InGameHUD = wv.hud
	var minimap: MinimapPanel = hud.get_minimap()
	var fow: FogOfWar = wv.fog_of_war

	# 1. Default state is ON, debug button present in debug build
	var is_fog_vis := func() -> bool:
		if bool(wv.get("use_cloud_sea_composite")):
			return wv.cloud_sea_composite != null and wv.cloud_sea_composite.visible
		return wv.fog_tile_layer != null and wv.fog_tile_layer.visible
	_assert(not wv.is_debug_fog_disabled(), "Default debug_fog_disabled is false (Fog: ON)")
	_assert(is_fog_vis.call(), "Active fog layer is visible by default")
	if OS.is_debug_build():
		var fb := hud.get_node_or_null("FogDebugBtn") as Button
		_assert(fb != null and fb.text == "Fog: ON", "Debug Fog button exists in debug build with text 'Fog: ON'")

	# Snapshot real FogOfWar state across entire 128x128 grid
	var unexp_cell := Vector2i(5, 5)
	for x in range(128):
		for y in range(128):
			if fow.get_state(Vector2i(x, y)) == FogOfWar.State.UNEXPLORED:
				unexp_cell = Vector2i(x, y)
				break
		if fow.get_state(unexp_cell) == FogOfWar.State.UNEXPLORED:
			break

	var fog_snapshot: PackedByteArray = PackedByteArray()
	for x in range(128):
		for y in range(128):
			fog_snapshot.append(fow.get_state(Vector2i(x, y)))

	_assert(minimap.get_pixel_color(unexp_cell) == MinimapPanel.UNEXPLORED_COLOR, "Minimap shows UNEXPLORED_COLOR before toggle OFF")

	# 2. Place hidden enemy unit on UNEXPLORED cell to verify info-safety
	var fake_enemy = wv.enemy_military_mgr.spawn_enemy_unit("iron_citadel", unexp_cell, "test_hidden_enemy")
	_assert(fake_enemy != null, "Spawned test enemy unit on UNEXPLORED cell")

	# 3. Toggle Fog OFF
	wv.set_debug_fog_disabled(true)
	_assert(wv.is_debug_fog_disabled(), "set_debug_fog_disabled(true) updates state")
	_assert(not is_fog_vis.call() and not wv.fog_tile_layer.visible, "Active fog layer is hidden when Fog is OFF")
	_assert(minimap.debug_fog_disabled, "Minimap debug_fog_disabled is true when Fog is OFF")
	_assert(minimap.get_pixel_color(unexp_cell) != MinimapPanel.UNEXPLORED_COLOR, "Minimap reveals underlying terrain/biome pixel when Fog is OFF")

	# 4. Underlying FogOfWar grid is byte-for-byte unchanged
	var grid_unchanged := true
	var idx := 0
	for x in range(128):
		for y in range(128):
			if fow.get_state(Vector2i(x, y)) != fog_snapshot[idx]:
				grid_unchanged = false
				break
			idx += 1
		if not grid_unchanged:
			break
	_assert(grid_unchanged, "Underlying FogOfWar grid remains byte-for-byte unchanged when Fog is OFF")

	# 5. Enemy markers remain filtered by real FogOfWar state
	var snap_off := minimap.get_visible_markers_snapshot()
	_assert(not snap_off["enemy_units"].has(unexp_cell), "Hidden enemy unit on UNEXPLORED cell remains hidden on minimap even when Fog is OFF")

	# 6. Toggle Fog ON restores exact appearance
	wv.set_debug_fog_disabled(false)
	_assert(is_fog_vis.call(), "Active fog layer immediately visible when Fog toggled back ON")
	_assert(minimap.get_pixel_color(unexp_cell) == MinimapPanel.UNEXPLORED_COLOR, "Minimap immediately restores UNEXPLORED_COLOR when Fog toggled back ON")

	# 7. Save/Load does NOT persist OFF state
	wv.set_debug_fog_disabled(true)
	var save_path := "user://test_p5_fog_toggle.json"
	SaveManager.save_to_file(wv, save_path)
	var l_res := SaveManager.load_from_file(save_path)
	_assert(not l_res["data"].has("debug_fog_disabled"), "Save payload does not serialize debug_fog_disabled")
	SaveManager.apply_loaded_state_to_world(wv, l_res["data"])
	_assert(not wv.is_debug_fog_disabled() and is_fog_vis.call(), "Loading save resets Fog debug toggle to ON")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	wv.queue_free()
	await process_frame

	print("========================================================")
	print("PHASE 5 FOG DEBUG TOGGLE RESULTS: %d passed, %d failed" % [_passed, _failed])
	print("========================================================")
	quit(0 if _failed == 0 else 1)
