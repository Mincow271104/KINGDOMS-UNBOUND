extends SceneTree

var _passed: int = 0
var _failed: int = 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] %s" % msg)
	else:
		_failed += 1
		push_error("  [FAIL] %s" % msg)

func _init() -> void:
	print("\n========================================================")
	print("  TEST SUITE: C1.10 M2 Rival Settlement Rendering & Hover")
	print("========================================================")

	var world_scene := load("res://scenes/world/world_view.tscn") as PackedScene
	_assert(world_scene != null, "world_view.tscn loads cleanly")
	if world_scene == null:
		quit(1)
		return

	var wv := world_scene.instantiate()
	wv.set("world_seed", 12345)
	root.add_child(wv)
	await process_frame

	_test_rendering_structure_and_hierarchy(wv)
	_test_data_isolation(wv)
	_test_visibility_and_fog_safety(wv)
	_test_hover_and_click_isolation(wv)
	await _test_idempotent_rebuild_and_compact(wv)

	wv.queue_free()
	await process_frame

	print("--------------------------------------------------------")
	print("  Results: %d passed, %d failed" % [_passed, _failed])
	print("========================================================")
	quit(1 if _failed > 0 else 0)

func _test_rendering_structure_and_hierarchy(wv: Node) -> void:
	print("\n[1] Rendering Structure, HQ Positioning & Hierarchy")
	var entities: Node = wv.get("entity_container")
	var rsc: Node2D = wv.get("rival_settlements_container")
	_assert(entities != null and rsc != null, "RivalSettlements container exists")
	_assert(rsc.get_parent() == entities, "RivalSettlements is child of World/Entities")
	_assert(rsc.y_sort_enabled, "RivalSettlements has y_sort_enabled = true")
	_assert(rsc.get_child_count() == 3, "RivalSettlements has 3 faction settlement groups (got %d)" % rsc.get_child_count())

	var wd = wv.get("world_data")
	_assert(wd != null and wd.settlements.size() == 3, "WorldData has 3 settlements")

	for stl in wd.settlements:
		var sid: String = str(stl.get("settlement_id"))
		var group: Node = rsc.get_node_or_null(sid)
		_assert(group != null, "Group node exists for %s" % sid)

		var expected_nodes: int = 0
		var hq_desc: Dictionary = {}
		for b in stl.buildings:
			expected_nodes += 1
			if str(b.get("role", "")) == "hq":
				hq_desc = b
		for d in stl.decorations:
			if str(d.get("type", "")) in ["faction_banner", "campfire"]:
				expected_nodes += 1
		_assert(group.get_child_count() == expected_nodes, "%s has %d visual nodes (got %d)" % [sid, expected_nodes, group.get_child_count()])

		_assert(not hq_desc.is_empty(), "%s has HQ descriptor" % sid)
		var hq_node := group.get_node_or_null("RivalBld_%s_%s" % [sid, str(hq_desc.get("id", ""))])
		_assert(hq_node != null, "%s HQ visual node exists" % sid)
		if hq_node != null:
			var hq_origin: Vector2i = hq_desc["cell"]
			var hq_size: Vector2i = hq_desc["size"]
			var expected_pos: Vector2 = IsoMath.map_to_local(hq_origin + hq_size - Vector2i.ONE)
			var plaza_pos: Vector2 = IsoMath.map_to_local(stl.anchor_cell)
			_assert(hq_node.position.is_equal_approx(expected_pos), "%s HQ positioned at building base_vertex, not anchor_cell" % sid)
			_assert(not hq_node.position.is_equal_approx(plaza_pos), "%s HQ position differs from plaza anchor_cell" % sid)

func _test_data_isolation(wv: Node) -> void:
	print("\n[2] Player Data & System Isolation")
	var wd = wv.get("world_data")
	var b_by_cell: Dictionary = wv.get("buildings_by_cell")
	var rb_by_cell: Dictionary = wv.get("rival_buildings_by_cell")

	_assert(wd.buildings.size() == 8, "world_data.buildings remains strictly 8 player starter buildings")
	_assert(not rb_by_cell.is_empty(), "rival_buildings_by_cell is populated (%d cells)" % rb_by_cell.size())

	var overlap_count: int = 0
	for rc in rb_by_cell.keys():
		if b_by_cell.has(rc):
			overlap_count += 1
	_assert(overlap_count == 0, "Zero overlap between buildings_by_cell and rival_buildings_by_cell")

	var housing_cap: int = BuildingSystem.get_total_housing_capacity(wd)
	_assert(housing_cap == 24, "Player housing capacity unaffected by rival houses (got %d)" % housing_cap)

func _test_visibility_and_fog_safety(wv: Node) -> void:
	print("\n[3] Fog of War & Visibility Safety")
	var wd = wv.get("world_data")
	var fow: FogOfWar = wv.get("fog_of_war")
	var rsc: Node2D = wv.get("rival_settlements_container")
	_assert(fow != null, "FogOfWar exists")

	var test_stl = wd.settlements[0]
	var hq: Dictionary = {}
	for b in test_stl.buildings:
		if str(b.get("role", "")) == "hq":
			hq = b
			break
	var hq_origin: Vector2i = hq["cell"]
	var hq_size: Vector2i = hq["size"]
	var vis_cell: Vector2i = hq_origin + Vector2i(hq_size.x / 2, hq_size.y / 2)
	var hq_node := rsc.get_node_or_null("%s/RivalBld_%s_%s" % [test_stl.settlement_id, test_stl.settlement_id, str(hq["id"])])

	_assert(fow.is_unexplored(vis_cell), "HQ vis_cell starts unexplored")
	_assert(hq_node != null and not hq_node.visible, "Unexplored rival HQ node is hidden")
	_assert(wv.call("get_rival_hover_label", hq_origin) == "", "Unexplored rival cell hover returns empty string")

	# Debug fog bypass
	wv.call("set_debug_fog_disabled", true)
	_assert(hq_node.visible, "Debug fog reveal shows static rival HQ")
	wv.call("set_debug_fog_disabled", false)
	_assert(not hq_node.visible, "Restoring fog re-hides unexplored rival HQ")

	# Exploring vis_cell (radius 2 covers 3x3 HQ footprint) reveals the building
	fow.reveal_circle(vis_cell, 2)
	wv.call("_refresh_rival_settlement_visibility")
	_assert(hq_node.visible, "Exploring vis_cell reveals rival HQ node")

func _test_hover_and_click_isolation(wv: Node) -> void:
	print("\n[4] Hover & Click Isolation")
	var wd = wv.get("world_data")
	var test_stl = wd.settlements[0]
	var hq: Dictionary = {}
	for b in test_stl.buildings:
		if str(b.get("role", "")) == "hq":
			hq = b
			break
	var hq_origin: Vector2i = hq["cell"]
	var hq_corner: Vector2i = hq_origin + Vector2i(2, 2)

	var label_origin: String = str(wv.call("get_rival_hover_label", hq_origin))
	var label_corner: String = str(wv.call("get_rival_hover_label", hq_corner))
	_assert(not label_origin.is_empty(), "Explored rival HQ hover returns label: %s" % label_origin)
	_assert(label_origin == label_corner, "Multi-cell rival building hover consistent across footprint")
	_assert(not label_origin.contains("Dân") and not label_origin.contains("Vàng"), "Hover does not expose population or economy")

	# Clicking rival HQ must NOT select a player building
	wv.call("clear_building_selection")
	wv.call("_handle_left_click", hq_origin)
	_assert(str(wv.get("selected_building_id")) == "", "Clicking rival building does not open player building selection")

	# Clicking player Town Hall preserves existing selection
	wv.call("_handle_left_click", wd.townhall_anchor)
	_assert(str(wv.get("selected_building_id")) != "", "Clicking player Town Hall still selects player building")
	wv.call("clear_building_selection")

func _test_idempotent_rebuild_and_compact(wv: Node) -> void:
	print("\n[5] Idempotent Rebuild & Graceful Missing Asset")
	var rsc: Node2D = wv.get("rival_settlements_container")
	var rb_before: int = wv.get("rival_buildings_by_cell").size()
	wv.call("sync_rival_settlements_visuals")
	await process_frame
	_assert(rsc.get_child_count() == 3, "Repeated sync keeps exact 3 settlement groups (got %d)" % rsc.get_child_count())
	_assert(wv.get("rival_buildings_by_cell").size() == rb_before, "Repeated sync keeps exact lookup cell count")

	# Missing asset fails gracefully
	var missing_node = wv.call("_create_building_sprite_node", "nonexistent_building_type", Vector2i(10, 10), Vector2i(2, 2), "MissingTest", "active")
	_assert(missing_node == null, "Missing building texture returns null gracefully without crashing")
