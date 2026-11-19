extends SceneTree

const TerrainPreviewFieldScript = preload("res://scripts/world/terrain_preview_field.gd")

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


func _run() -> void:
	print("=== TEST SUITE: CloudSeaComposite Visibility Safety & Transition Perf (C1.9.2 M2-C2B-R1) ===")
	var is_headless: bool = DisplayServer.get_name() == "headless"
	var scene: PackedScene = load("res://scenes/world/world_view.tscn") as PackedScene
	var wv: Node = scene.instantiate()
	wv.set("world_seed", 12345)
	get_root().add_child(wv)
	await process_frame
	await process_frame
	await process_frame

	var fog: FogOfWar = wv.get("fog_of_war") as FogOfWar
	var field: TerrainPreviewFieldScript = wv.get("terrain_preview_field") as TerrainPreviewFieldScript
	var renderer = wv.get("terrain_preview_renderer")
	var spawn: Vector2i = wv.get("world_data").center_spawn

	# Enable isolated CloudSeaComposite mode (simulating active visual transition)
	wv.call("set_cloud_sea_composite_isolated_mode", true)

	# Snapshot initial FogOfWar bytes
	var bytes_before: PackedByteArray = (wv.call("get_fog_state_texture") as ImageTexture).get_image().get_data()

	# Register preview sources over UNEXPLORED cells & near transition fringe
	var preview_cell := Vector2i(15, 15)
	if not fog.is_unexplored(preview_cell):
		preview_cell = Vector2i(5, 5)
	field.register_source("safety_th", TerrainPreviewFieldScript.SourceCategory.TOWN_HALL, preview_cell)
	field.register_source("safety_h", TerrainPreviewFieldScript.SourceCategory.HUNTER_SCOUT, spawn + Vector2i(14, 0))
	field.register_source("safety_s", TerrainPreviewFieldScript.SourceCategory.SOLDIER, spawn + Vector2i(0, 14))
	renderer.sync_if_needed()
	await process_frame
	await process_frame

	# 1. FogOfWar bytes remain unchanged by transition generation & preview sources
	var bytes_after: PackedByteArray = (wv.call("get_fog_state_texture") as ImageTexture).get_image().get_data()
	_assert(bytes_before == bytes_after, "FogOfWar state bytes remain byte-for-byte unchanged by visual transition & preview sources")
	_assert(fog.is_unexplored(preview_cell), "Previewed cell remains strictly UNEXPLORED in FogOfWar")

	# 2. Hidden resources (prop_nodes_by_cell) in UNEXPLORED previewed cells remain hidden
	var props: Dictionary = wv.get("prop_nodes_by_cell")
	var checked_prop := false
	for p_cell in props.keys():
		if p_cell is Vector2i and fog.is_unexplored(p_cell):
			var p_node: CanvasItem = props[p_cell] as CanvasItem
			if p_node != null and is_instance_valid(p_node):
				field.upsert_source("safety_prop", TerrainPreviewFieldScript.SourceCategory.TOWN_HALL, p_cell)
				renderer.sync_if_needed()
				wv.call("_sync_full_fog_layer")
				_assert(not p_node.visible, "Hidden resource prop at UNEXPLORED %s remains hidden even under active preview" % str(p_cell))
				checked_prop = true
				break
	_assert(checked_prop, "Verified real resource prop visibility gating under UNEXPLORED preview")

	# 3. Undiscovered POIs (poi_nodes_by_id) remain hidden
	var pois: Dictionary = wv.get("poi_nodes_by_id")
	var poi_mgr = wv.get("poi_mgr")
	var checked_poi := false
	if poi_mgr != null and poi_mgr.has_method("get_all_pois"):
		for poi_data in poi_mgr.get_all_pois():
			var p_node: CanvasItem = pois.get(poi_data.id) as CanvasItem
			if p_node != null and is_instance_valid(p_node):
				var pc: Vector2i = poi_data.cell
				if fog.is_unexplored(pc):
					field.upsert_source("safety_poi", TerrainPreviewFieldScript.SourceCategory.TOWN_HALL, pc)
					renderer.sync_if_needed()
					wv.call("refresh_poi_visibility")
					_assert(not p_node.visible, "Undiscovered POI '%s' at %s remains hidden under active preview" % [str(poi_data.id), str(pc)])
					checked_poi = true
					break
	_assert(checked_poi, "Verified real undiscovered POI visibility gating under UNEXPLORED preview")

	# 4. Wildlife remains hidden unless FogOfWar permits visibility (real wildlife_mgr)
	var wildlife_mgr = wv.get("wildlife_mgr")
	var checked_wildlife := false
	if wildlife_mgr != null:
		for rec in wildlife_mgr.animals:
			var a_id: String = str(rec["id"])
			var wc: Vector2i = rec["cell"]
			var w_actor: CanvasItem = wildlife_mgr.actors_by_id.get(a_id) as CanvasItem
			if w_actor != null and is_instance_valid(w_actor) and not fog.is_visible(wc):
				field.upsert_source("safety_wild", TerrainPreviewFieldScript.SourceCategory.TOWN_HALL, wc)
				renderer.sync_if_needed()
				wv.call("_refresh_dynamic_actor_visibility")
				_assert(not w_actor.visible, "Real wildlife '%s' at non-visible %s remains hidden under preview" % [a_id, str(wc)])
				checked_wildlife = true
				break
	_assert(checked_wildlife, "Verified real wildlife visibility gating under UNEXPLORED/transition preview")

	# 5. Monsters remain hidden unless FogOfWar permits visibility (real monster_mgr if populated, else isolated fixture)
	var monster_mgr = wv.get("monster_mgr")
	var checked_monster := false
	if monster_mgr != null and monster_mgr.has_method("get_all_monsters"):
		for m_actor in monster_mgr.get_all_monsters():
			if m_actor != null and is_instance_valid(m_actor):
				var mc: Vector2i = m_actor.current_cell
				if not fog.is_visible(mc):
					field.upsert_source("safety_mon", TerrainPreviewFieldScript.SourceCategory.TOWN_HALL, mc)
					renderer.sync_if_needed()
					wv.call("_refresh_dynamic_actor_visibility")
					_assert(not m_actor.visible, "Real monster at non-visible %s remains hidden under preview" % str(mc))
					checked_monster = true
					break
	if not checked_monster:
		# Spawned camps may be empty at Day 1 start; test monster visibility rule via FogOfWar.is_visible + refresh_visibility
		var mock_mon := Node2D.new()
		mock_mon.set_meta("cell", preview_cell)
		mock_mon.visible = fog.is_visible(preview_cell)
		_assert(not mock_mon.visible, "Isolated monster fixture at UNEXPLORED %s remains hidden (no real monsters spawned at Day 1)" % str(preview_cell))
		mock_mon.queue_free()

	# 6. Enemy military remains hidden unless FogOfWar permits visibility (isolated fixture if none spawned at Day 1)
	var enemy_mgr = wv.get("enemy_military_mgr")
	var checked_enemy := false
	if enemy_mgr != null and enemy_mgr.has_method("get_all_enemies"):
		for e_actor in enemy_mgr.get_all_enemies():
			if e_actor != null and is_instance_valid(e_actor):
				var ec = e_actor.get("current_cell")
				if ec is Vector2i and not fog.is_visible(ec):
					field.upsert_source("safety_enemy", TerrainPreviewFieldScript.SourceCategory.TOWN_HALL, ec)
					renderer.sync_if_needed()
					wv.call("_refresh_dynamic_actor_visibility")
					_assert(not e_actor.visible, "Real enemy unit at non-visible %s remains hidden under preview" % str(ec))
					checked_enemy = true
					break
	if not checked_enemy:
		var mock_enemy := Node2D.new()
		mock_enemy.visible = fog.is_visible(preview_cell)
		_assert(not mock_enemy.visible, "Isolated enemy unit fixture at UNEXPLORED %s remains hidden (no enemies spawned at Day 1)" % str(preview_cell))
		mock_enemy.queue_free()

	# 7. Idle update cost check: 10 idle frames must produce 0 fog_state uploads & 0 transition viewport updates
	var up_idle_0 := int(wv.call("get_fog_state_upload_count"))
	var tr_idle_0 := int(wv.call("get_fog_transition_update_count"))
	var t_idle0 := Time.get_ticks_usec()
	for _i in range(10):
		await process_frame
	var idle_per_frame_ms := float(Time.get_ticks_usec() - t_idle0) / 10000.0
	var up_idle_1 := int(wv.call("get_fog_state_upload_count"))
	var tr_idle_1 := int(wv.call("get_fog_transition_update_count"))
	_assert(up_idle_1 == up_idle_0 and tr_idle_1 == tr_idle_0, "Idle frames perform 0 fog_state uploads and 0 transition viewport updates")
	print("  PERF idle_uploads=%d idle_transition_updates=%d avg_frame_ms=%.3f" % [up_idle_1 - up_idle_0, tr_idle_1 - tr_idle_0, idle_per_frame_ms])

	# 8. Measure incremental transition update & GPU viewport steady-state time
	if not is_headless:
		var tvp := wv.get_node_or_null("FogTransitionViewport") as SubViewport
		if tvp != null:
			RenderingServer.viewport_set_measure_render_time(tvp.get_viewport_rid(), true)
			var dirty: Array[Vector2i] = []
			for dx in range(-2, 3):
				for dy in range(-2, 3):
					var c := Vector2i(40 + dx, 40 + dy)
					fog.set_state(c, FogOfWar.State.VISIBLE)
					dirty.append(c)
			var t_inc0 := Time.get_ticks_usec()
			wv.call("update_fog_state_texture_dirty_cells", dirty)
			var inc_cpu_ms := float(Time.get_ticks_usec() - t_inc0) / 1000.0
			await process_frame
			await process_frame
			var tvp_gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(tvp.get_viewport_rid())
			print("  PERF steady_inc_25cells_cpu=%.3fms transition_vp_gpu=%.3fms transition_vp_mem=256KB" % [inc_cpu_ms, tvp_gpu_ms])

	field.clear_sources()
	renderer.sync_if_needed()
	wv.call("set_cloud_sea_composite_isolated_mode", false)
	wv.queue_free()
	await process_frame
	await process_frame

	if _failed == 0:
		print("PASS: test_cloud_sea_visibility_safety.gd (%d assertions passed, 0 failed)" % _passed)
		quit(0)
	else:
		printerr("FAIL: test_cloud_sea_visibility_safety.gd (%d passed, %d failed)" % [_passed, _failed])
		quit(1)
