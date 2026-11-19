extends SceneTree

const WorldViewScene := preload("res://scenes/world/world_view.tscn")

var _failures: Array[String] = []
var _passed: int = 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures.append(msg)
		printerr("[FAIL] ", msg)

func _init() -> void:
	call_deferred("_run_all")

func _run_all() -> void:
	var wv := WorldViewScene.instantiate()
	wv.set("skip_intro_for_test", true)
	root.add_child(wv)
	await create_timer(0.15).timeout

	var fow: FogOfWar = wv.get("fog_of_war")
	var wd = wv.get("world_data")
	var nrm = wv.get("natural_resource_mgr")
	var pm = wv.get("poi_mgr")
	var hud = wv.get("hud")
	var minimap = hud.get("minimap_panel") if hud != null else null
	var territory_mgr = wv.get("territory_mgr")

	# 1. Default Fog ON
	_assert(not wv.is_debug_fog_disabled(), "Case 1: Fog ON is default on new world")

	# Find an UNEXPLORED natural resource node, an UNEXPLORED tree/rock prop, and an UNEXPLORED POI
	var unexp_res = null
	if nrm != null:
		for n in nrm.nodes_by_cell.values():
			if fow != null and not fow.is_explored(n.cell):
				unexp_res = n
				break
	_assert(unexp_res != null, "Fixture: found unexplored natural resource node")

	var unexp_prop_cell := Vector2i(-1, -1)
	if wd != null:
		for p in wd.props:
			var c: Vector2i = p.get("cell", Vector2i(-1, -1))
			var pt: String = str(p.get("type", ""))
			if c.x >= 0 and fow != null and not fow.is_explored(c) and (nrm == null or nrm.get_node_at_cell(c).is_empty()):
				if pt == "tree" or pt == "rock":
					unexp_prop_cell = c
					break
	_assert(unexp_prop_cell.x >= 0, "Fixture: found unexplored tree/rock prop")

	var unexp_poi = null
	if pm != null:
		for poi in pm.get_all_pois():
			if poi.state == POIManager.POIState.UNDISCOVERED and (fow == null or not fow.is_explored(poi.cell)):
				unexp_poi = poi
				break
	_assert(unexp_poi != null, "Fixture: found unexplored POI")

	# Fog ON fail-closed check on unexplored resource
	if unexp_res != null:
		wv._handle_left_click(unexp_res.cell)
		_assert(wv.get("selected_building_id") == "", "Fog ON: clicking unexplored cell does not select anything")

	# 2-5. Toggle Fog OFF -> reveals fog layer, resources, props, POIs
	var is_fog_vis: Callable = func() -> bool:
		if bool(wv.get("use_cloud_sea_composite")):
			return wv.cloud_sea_composite != null and wv.cloud_sea_composite.visible
		return wv.fog_tile_layer != null and wv.fog_tile_layer.visible

	wv.set_debug_fog_disabled(true)
	_assert(wv.is_debug_fog_disabled(), "Case 2: Fog OFF enabled")
	_assert(not is_fog_vis.call(), "Case 2b: active fog layer hidden when Fog OFF")

	if unexp_res != null:
		var r_prop = wv.prop_nodes_by_cell.get(unexp_res.cell)
		_assert(r_prop != null and r_prop.visible, "Case 3: unexplored natural resource prop visible when Fog OFF")
	if unexp_prop_cell.x >= 0:
		var p_node = wv.prop_nodes_by_cell.get(unexp_prop_cell)
		_assert(p_node != null and p_node.visible, "Case 4: unexplored tree/rock prop visible when Fog OFF")
	if unexp_poi != null:
		var poi_node = wv.poi_nodes_by_id.get(unexp_poi.id)
		_assert(poi_node != null and poi_node.visible, "Case 5: unexplored POI node visible when Fog OFF")

	# 6. Click/inspect unexplored natural resource node
	if unexp_res != null:
		var qty_before: int = unexp_res.remaining_qty
		wv._handle_left_click(unexp_res.cell)
		var insp_data: Dictionary = hud.get("inspected_building_data")
		_assert(bool(insp_data.get("is_debug_inspect", false)), "Case 6a: inspected_building_data marked is_debug_inspect")
		_assert(insp_data.get("type") == unexp_res.type, "Case 6b: inspected type matches resource node")
		_assert(int(insp_data.get("remaining_qty", -1)) == unexp_res.remaining_qty, "Case 6c: remaining_qty matches")
		_assert(int(insp_data.get("max_qty", -1)) == unexp_res.max_qty, "Case 6d: max_qty matches")
		_assert(hud.building_inspect_panel != null and hud.building_inspect_panel.visible, "Case 6e: BuildingInspectPanel visible")
		# 9. Zero gameplay side effects
		_assert(not nrm.is_node_reserved(unexp_res.id), "Case 9a: resource node not reserved by inspection")
		_assert(unexp_res.remaining_qty == qty_before, "Case 9b: resource qty unchanged by inspection")
		_assert(territory_mgr == null or not territory_mgr.is_cell_owned(unexp_res.cell), "Case 9c: territory not claimed")

	# 7. Click/inspect unexplored tree/rock
	if unexp_prop_cell.x >= 0:
		wv._handle_left_click(unexp_prop_cell)
		var prop_insp: Dictionary = hud.get("inspected_building_data")
		_assert(prop_insp.get("category") == "prop" and prop_insp.get("cell") == unexp_prop_cell, "Case 7: unexplored prop inspected")

	# 8. Click/inspect unexplored POI without discovering/claiming
	if unexp_poi != null:
		wv._handle_left_click(unexp_poi.cell)
		var poi_insp: Dictionary = hud.get("inspected_building_data")
		_assert(poi_insp.get("category") == "poi" and unexp_poi.state == POIManager.POIState.UNDISCOVERED, "Case 8: POI inspected without altering UNDISCOVERED state")

	# 10. Enemy military stays hidden in world & minimap
	var emm = wv.get("enemy_military_mgr")
	if emm != null and emm.has_method("get_all_enemies"):
		var hidden_enemy = null
		for e in emm.get_all_enemies():
			if e != null and is_instance_valid(e) and fow != null and not fow.is_visible(e.get("current_cell")):
				hidden_enemy = e
				break
		if hidden_enemy != null:
			_assert(not hidden_enemy.visible, "Case 10a: non-visible enemy military stays hidden in Fog OFF")
	if minimap != null:
		var snap_off: Dictionary = minimap.get_visible_markers_snapshot()
		for ec in snap_off.get("enemy_units", []):
			_assert(fow != null and fow.is_visible(ec), "Case 10b: minimap enemy_units strictly filtered by real fow.is_visible")
		# 11. Minimap natural_resources + pois populated in Fog OFF
		_assert(snap_off.get("natural_resources", []).size() > 0, "Case 11a: minimap shows natural_resources in Fog OFF")
		_assert(snap_off.get("pois", []).size() >= (pm.get_all_pois().size() if pm != null else 0), "Case 11b: minimap shows all POIs in Fog OFF")

	# 12. Future wildlife/monster extension point
	_assert(wv.should_debug_reveal_category("wildlife"), "Case 12a: wildlife category allowed in Fog OFF")
	_assert(not wv.should_debug_reveal_category("enemy_military"), "Case 12b: enemy_military category always denied")
	var mock_cell := Vector2i(100, 100)
	wv.register_debug_inspect_provider(func(c: Vector2i) -> Dictionary:
		if c == mock_cell:
			return {"category": "wildlife", "type": "deer", "label": "Deer", "cell": c, "title": "Deer [Debug]"}
		return {}
	)
	var mock_insp: Dictionary = wv.inspect_cell_in_debug_mode(mock_cell)
	_assert(mock_insp.get("category") == "wildlife" and mock_insp.get("type") == "deer", "Case 12c: extensible debug inspect provider works for future wildlife")

	# 13 & 14. Toggle Fog ON restores visibility, closes debug inspection, FogOfWar unchanged
	if unexp_res != null:
		wv._handle_left_click(unexp_res.cell)
	wv.set_debug_fog_disabled(false)
	_assert(not wv.is_debug_fog_disabled(), "Case 13a: Fog ON restored")
	_assert(is_fog_vis.call(), "Case 13b: active fog layer visible again when Fog ON")
	_assert(hud.building_inspect_panel == null or not hud.building_inspect_panel.visible, "Case 13c: debug inspection panel closed on Fog ON")
	_assert(wv.get("selected_building_id") == "", "Case 13d: selected_building_id cleared on Fog ON")
	if unexp_res != null:
		var r_prop2 = wv.prop_nodes_by_cell.get(unexp_res.cell)
		_assert(r_prop2 != null and not r_prop2.visible, "Case 13e: unexplored resource prop hidden again")
		_assert(fow.get_state(unexp_res.cell) == FogOfWar.State.UNEXPLORED, "Case 14: FogOfWar grid state remained UNEXPLORED")
	if unexp_poi != null:
		var poi_node2 = wv.poi_nodes_by_id.get(unexp_poi.id)
		_assert(poi_node2 != null and not poi_node2.visible, "Case 13f: unexplored POI hidden again")
	if minimap != null:
		var snap_on: Dictionary = minimap.get_visible_markers_snapshot()
		_assert(snap_on.get("natural_resources", []).is_empty(), "Case 11c: minimap natural_resources cleared on Fog ON")

	# 15. Save/Load does not persist Fog OFF
	wv.set_debug_fog_disabled(true)
	var save_path := "user://fog_debug_insp_test.json"
	var s_res: Dictionary = SaveManager.save_to_file(wv, save_path)
	_assert(bool(s_res.get("success", false)), "Case 15a: SaveManager.save_to_file succeeded")
	var wv2 := WorldViewScene.instantiate()
	wv2.set("skip_intro_for_test", true)
	root.add_child(wv2)
	await create_timer(0.15).timeout
	var l_res: Dictionary = SaveManager.load_from_file(save_path)
	var ok_load: bool = bool(l_res.get("success", false)) and SaveManager.apply_loaded_state_to_world(wv2, l_res["data"])
	_assert(ok_load, "Case 15b: SaveManager load & apply succeeded")
	_assert(not wv2.is_debug_fog_disabled(), "Case 15c: loaded world defaults to Fog ON")
	var hud2 = wv2.get("hud")
	if hud2 != null and hud2.get("fog_debug_btn") != null:
		_assert(hud2.fog_debug_btn.text == "Fog: ON", "Case 15d: FogDebugBtn text reset to Fog: ON after load")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	wv.queue_free()
	wv2.queue_free()

	print("[test_fog_debug_inspection] Passed: %d | Failed: %d" % [_passed, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
