extends SceneTree

const SettlementDataScript = preload("res://scripts/world/settlement_data.gd")
const FieldSiegeManagerScript = preload("res://scripts/combat/field_siege_manager.gd")
const SiegeObjectiveActorScript = preload("res://scripts/combat/siege_objective_actor.gd")

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
	print("  TEST SUITE: C1.10 M3 Settlement-Siege Integration")
	print("========================================================")

	await _test_v8_worldview_linking_and_hierarchy()
	_test_one_to_one_relationship_validation()
	await _test_hq_anchor_skip_and_v7_fallback()
	await _test_debug_fog_worldview_and_minimap()
	_test_serialization_backward_compatibility()

	print("--------------------------------------------------------")
	print("  Results: %d passed, %d failed" % [_passed, _failed])
	print("========================================================")
	quit(1 if _failed > 0 else 0)

func _test_v8_worldview_linking_and_hierarchy() -> void:
	print("\n[1] V8 Linking, Hierarchy, Coordinates & Repeated Setup")
	var world_scene := load("res://scenes/world/world_view.tscn") as PackedScene
	var wv := world_scene.instantiate()
	wv.set("world_seed", 12345)
	root.add_child(wv)
	await process_frame

	var fsm = wv.get("field_siege_mgr")
	var wd = wv.get("world_data")
	var entities: Node = wv.get("entity_container")
	var siege_cont: Node = entities.get_node_or_null("SiegeObjectives") if entities != null else null

	_assert(siege_cont != null and siege_cont is Node2D, "World/Entities/SiegeObjectives container exists")
	_assert(siege_cont != null and siege_cont.y_sort_enabled, "SiegeObjectives has y_sort_enabled = true")
	_assert(fsm.get_all_objectives().size() == 3, "V8 WorldView registers 3 linked objectives")

	var expected := {
		"rival_military": "outpost_rival_military",
		"rival_merchant": "outpost_rival_merchant",
		"neutral_tribe": "outpost_neutral_tribe"
	}
	for stl in wd.settlements:
		var oid: String = expected[stl.origin_faction_id]
		var obj = fsm.get_objective(oid)
		_assert(obj != null, "Objective %s exists" % oid)
		if obj != null:
			_assert(obj.get_parent() == siege_cont, "%s parented under World/Entities/SiegeObjectives" % oid)
			_assert(obj.current_cell == stl.anchor_cell, "%s current_cell == settlement.anchor_cell (%s)" % [oid, str(stl.anchor_cell)])
			_assert(obj.position.is_equal_approx(IsoMath.map_to_local(stl.anchor_cell)), "%s position matches IsoMath.map_to_local(anchor_cell)" % oid)
			_assert(obj.linked_settlement_id == stl.settlement_id, "%s linked_settlement_id == %s" % [oid, stl.settlement_id])

	# Repeated setup idempotency
	wv.call("_setup_default_siege_objectives")
	_assert(fsm.get_all_objectives().size() == 3, "Repeated _setup_default_siege_objectives produces 0 duplicates")
	_assert(siege_cont.get_child_count() == 3, "SiegeObjectives container keeps exact 3 children")

	wv.queue_free()
	await process_frame

func _test_one_to_one_relationship_validation() -> void:
	print("\n[2] 1:1 Relationship Validation (FieldSiegeManager)")
	var fsm := FieldSiegeManagerScript.new()
	var o1 = fsm.register_objective("outpost_rival_military", Vector2i(20, 20), "rival_military", 300.0, 4, "stl_rival_military_1")
	_assert(o1 != null, "Initial linked objective registration succeeds")

	# Idempotent when consistent
	var o1_dup = fsm.register_objective("outpost_rival_military", Vector2i(20, 20), "rival_military", 300.0, 4, "stl_rival_military_1")
	_assert(o1_dup == o1, "Consistent duplicate registration returns existing objective")

	# Conflicting existing objective ID (different settlement)
	var o1_conflict_stl = fsm.register_objective("outpost_rival_military", Vector2i(20, 20), "rival_military", 300.0, 4, "stl_other")
	_assert(o1_conflict_stl == null, "Conflicting linked_settlement_id for existing objective ID is rejected")

	# Conflicting existing objective ID (different faction)
	var o1_conflict_fid = fsm.register_objective("outpost_rival_military", Vector2i(20, 20), "rival_merchant", 300.0, 4, "stl_rival_military_1")
	_assert(o1_conflict_fid == null, "Conflicting faction_id for existing objective ID is rejected")

	# Duplicate settlement linking (different objective ID, same settlement)
	var o2_dup_stl = fsm.register_objective("outpost_other", Vector2i(25, 25), "rival_merchant", 250.0, 3, "stl_rival_military_1")
	_assert(o2_dup_stl == null, "Second objective linking to already-linked settlement is rejected")
	_assert(fsm.get_all_objectives().size() == 1, "Only 1 valid objective remains registered")

func _test_hq_anchor_skip_and_v7_fallback() -> void:
	print("\n[3] HQ/Anchor Validation, Skip Reasons, No Phantom V8 & V7 Fallback")
	var world_scene := load("res://scenes/world/world_view.tscn") as PackedScene
	var wv := world_scene.instantiate()
	wv.set("world_seed", 12345)
	root.add_child(wv)
	await process_frame

	var fsm = wv.get("field_siege_mgr")
	var wd = wv.get("world_data")

	# Test A: Intentional map_constraints skip -> omit without phantom legacy fallback
	fsm.clear_all_objectives()
	wd.settlements.clear()
	wd.settlement_skip_reasons.clear()
	wd.settlement_skip_reasons["rival_military"] = "map_constraints"
	# Test B: Unexpected missing rival_merchant (not in skip_reasons) -> omit without phantom
	# Test C: Missing HQ on neutral_tribe -> omit
	var bad_hq_stl := SettlementDataScript.new("stl_neutral_tribe_1", "neutral_tribe", "neutral_tribe", SettlementDataScript.ROLE_VILLAGE, Vector2i(80, 80), "outpost_neutral_tribe")
	bad_hq_stl.buildings.append({"id": "h1", "type": "house", "cell": Vector2i(78, 82), "size": Vector2i(2, 2), "role": "residential", "blocking": true})
	wd.settlements.append(bad_hq_stl)
	wv.call("_setup_default_siege_objectives")
	_assert(fsm.get_all_objectives().is_empty(), "V8 omits intentional skip, unexpected missing, and missing-HQ settlements with 0 phantom objectives")

	# Test D: Invalid HQ type & invalid anchor (WATER) & faction mismatch & duplicate canonical mapping
	fsm.clear_all_objectives()
	wd.settlements.clear()
	wd.settlement_skip_reasons.clear()
	var inv_type_stl := SettlementDataScript.new("stl_rival_military_1", "rival_military", "rival_military", SettlementDataScript.ROLE_CAPITAL, Vector2i(20, 20), "outpost_rival_military")
	inv_type_stl.buildings.append({"id": "hq", "type": "nonexistent_hq_type", "cell": Vector2i(19, 16), "size": Vector2i(3, 3), "role": "hq", "blocking": true})
	wd.settlements.append(inv_type_stl)

	var water_anchor := Vector2i(40, 40)
	wd.terrain[water_anchor.x][water_anchor.y] = WorldGenerator.TerrainType.WATER
	var inv_anchor_stl := SettlementDataScript.new("stl_rival_merchant_1", "rival_merchant", "rival_merchant", SettlementDataScript.ROLE_CAPITAL, water_anchor, "outpost_rival_merchant")
	inv_anchor_stl.buildings.append({"id": "hq", "type": "market", "cell": Vector2i(39, 36), "size": Vector2i(3, 3), "role": "hq", "blocking": true})
	wd.settlements.append(inv_anchor_stl)

	var mismatch_stl := SettlementDataScript.new("stl_neutral_tribe_1", "neutral_tribe", "neutral_tribe", SettlementDataScript.ROLE_VILLAGE, Vector2i(80, 80), "outpost_rival_military")
	mismatch_stl.buildings.append({"id": "hq", "type": "townhall", "cell": Vector2i(79, 76), "size": Vector2i(3, 3), "role": "hq", "blocking": true})
	wd.settlements.append(mismatch_stl)

	wv.call("_setup_default_siege_objectives")
	_assert(fsm.get_all_objectives().is_empty(), "Invalid HQ type, WATER anchor, and mismatched canonical objective ID are all rejected")

	# Test E: Duplicate canonical linked_objective_id across two settlements
	fsm.clear_all_objectives()
	wd.settlements.clear()
	var dup_a := SettlementDataScript.new("stl_rival_military_1", "rival_military", "rival_military", SettlementDataScript.ROLE_CAPITAL, Vector2i(20, 20), "outpost_rival_military")
	dup_a.buildings.append({"id": "hq", "type": "barracks", "cell": Vector2i(19, 16), "size": Vector2i(3, 3), "role": "hq", "blocking": true})
	var dup_b := SettlementDataScript.new("stl_rival_merchant_1", "rival_merchant", "rival_merchant", SettlementDataScript.ROLE_CAPITAL, Vector2i(50, 50), "outpost_rival_military")
	dup_b.buildings.append({"id": "hq", "type": "market", "cell": Vector2i(49, 46), "size": Vector2i(3, 3), "role": "hq", "blocking": true})
	wd.settlements.append(dup_a)
	wd.settlements.append(dup_b)
	wd.terrain[20][20] = WorldGenerator.TerrainType.GRASS
	wd.occupancy[20][20] = false
	wv.call("_setup_default_siege_objectives")
	_assert(fsm.get_objective("outpost_rival_merchant") == null, "Duplicate canonical objective mapping does not register second settlement")

	wv.queue_free()
	await process_frame

	# Test F: V7 Legacy fallback
	var wv7 := world_scene.instantiate()
	wv7.set("world_seed", 12345)
	wv7.set("world_generator_version", WorldGenerator.NATURAL_RESOURCES_GENERATOR_VERSION)
	root.add_child(wv7)
	await process_frame
	var fsm7 = wv7.get("field_siege_mgr")
	_assert(fsm7.get_all_objectives().size() == 3, "V7 WorldView registers 3 legacy objectives")
	for o in fsm7.get_all_objectives():
		_assert(o.linked_settlement_id == "", "V7 legacy objective %s has linked_settlement_id == ''" % o.objective_id)
	wv7.queue_free()
	await process_frame

func _test_debug_fog_worldview_and_minimap() -> void:
	print("\n[4] Debug Fog Consistency (WorldView + Minimap, Enemy Military Stays Hidden)")
	var world_scene := load("res://scenes/world/world_view.tscn") as PackedScene
	var wv := world_scene.instantiate()
	wv.set("world_seed", 12345)
	root.add_child(wv)
	await process_frame

	var fsm = wv.get("field_siege_mgr")
	var emm = wv.get("enemy_military_mgr")
	var hud = wv.get("hud")
	var minimap = hud.get("minimap_panel") if hud != null else null
	var obj = fsm.get_objective("outpost_rival_military")
	var enemy_cell: Vector2i = obj.current_cell + Vector2i(1, 0)
	var enemy_unit = emm.spawn_enemy_unit("rival_military", enemy_cell)

	_assert(not obj.visible, "Unexplored linked objective is hidden")
	if minimap != null:
		var snap_off: Dictionary = minimap.get_visible_markers_snapshot()
		_assert(not snap_off["pois"].has(obj.current_cell), "Minimap hides unexplored NPC objective")

	wv.call("set_debug_fog_disabled", true)
	_assert(obj.visible, "WorldView reveals objective when debug_fog_disabled = true")
	_assert(enemy_unit == null or not enemy_unit.visible, "Enemy military remains hidden even when debug_fog_disabled = true")
	if minimap != null:
		var snap_on: Dictionary = minimap.get_visible_markers_snapshot()
		_assert(snap_on["pois"].has(obj.current_cell), "Minimap reveals objective when debug_fog_disabled = true")
		_assert(not snap_on["enemy_units"].has(enemy_cell), "Minimap keeps enemy military hidden when debug_fog_disabled = true")

	wv.call("set_debug_fog_disabled", false)
	_assert(not obj.visible, "WorldView re-hides unexplored objective when debug_fog_disabled = false")

	wv.queue_free()
	await process_frame

func _test_serialization_backward_compatibility() -> void:
	print("\n[5] SiegeObjectiveActor Serialization Backward Compatibility")
	var actor := SiegeObjectiveActorScript.new()
	actor.objective_id = "outpost_rival_military"
	actor.owning_faction_id = "rival_military"
	actor.current_cell = Vector2i(30, 30)
	actor.linked_settlement_id = "stl_rival_military_1"

	var ser: Dictionary = actor.serialize()
	_assert(ser.get("linked_settlement_id") == "stl_rival_military_1", "serialize() preserves linked_settlement_id")

	var restored := SiegeObjectiveActorScript.new()
	_assert(restored.deserialize(ser), "deserialize() succeeds with linked_settlement_id")
	_assert(restored.linked_settlement_id == "stl_rival_military_1", "deserialize() restores linked_settlement_id")

	# Legacy payload without linked_settlement_id
	ser.erase("linked_settlement_id")
	var legacy := SiegeObjectiveActorScript.new()
	_assert(legacy.deserialize(ser), "deserialize() succeeds on legacy payload missing linked_settlement_id")
	_assert(legacy.linked_settlement_id == "", "Legacy payload defaults linked_settlement_id to ''")

	actor.free()
	restored.free()
	legacy.free()
