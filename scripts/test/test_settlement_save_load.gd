extends SceneTree

const SettlementDataScript = preload("res://scripts/world/settlement_data.gd")
const SettlementGeneratorScript = preload("res://scripts/world/settlement_generator.gd")
const SiegeObjectiveActorScript = preload("res://scripts/combat/siege_objective_actor.gd")
const EnemyMilitaryManagerScript = preload("res://scripts/military/enemy_military_manager.gd")
const FieldSiegeManagerScript = preload("res://scripts/combat/field_siege_manager.gd")
const WorldViewScene = preload("res://scenes/world/world_view.tscn")

class FailOnceEnemyMgr extends EnemyMilitaryManagerScript:
	var fail_once: bool = true
	var calls_seen: int = 0
	func deserialize(data: Dictionary) -> bool:
		calls_seen += 1
		if fail_once:
			fail_once = false
			return false
		return super.deserialize(data)

class CorruptOnceSiegeMgr extends FieldSiegeManagerScript:
	var corrupt_once: bool = true
	var calls_seen: int = 0
	func deserialize(data: Dictionary) -> bool:
		calls_seen += 1
		var ok: bool = super.deserialize(data)
		if ok and corrupt_once:
			corrupt_once = false
			for obj in get_all_objectives():
				if obj != null:
					obj.linked_settlement_id = ""
		return ok

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
	print("  TEST SUITE: C1.10 M4 Settlement Save/Load Persistence")
	print("========================================================")

	await _test_round_trip_fidelity_and_no_alias()
	await _test_per_faction_truth_table()
	await _test_terrain_occupancy_reservations_and_idempotency()
	await _test_option_b_props_and_resources_determinism()
	await _test_player_building_isolation_and_m4_conflicts()
	await _test_pre_m4_v8_migration_cases()
	await _test_objective_reconciliation_and_option_c()
	await _test_fow_minimap_and_cross_size_bounds()
	await _test_rollback_failure_injection()
	await _test_rollback_after_step_3d_3e_and_step_19_boundaries()

	print("--------------------------------------------------------")
	print("  Results: %d passed, %d failed" % [_passed, _failed])
	print("========================================================")
	quit(1 if _failed > 0 else 0)

func _test_round_trip_fidelity_and_no_alias() -> void:
	print("\n[1] M4+ Schema, Round-Trip Fidelity & Snapshot No-Alias")
	var wv := WorldViewScene.instantiate()
	wv.world_seed = 12345
	root.add_child(wv)
	await process_frame

	var wd = wv.world_data
	var fsm = wv.field_siege_mgr
	_assert(wd.settlements.size() == 3, "V8 generates 3 settlements")

	# Mutate settlement ownership/status independently from objective capture state
	var stl0 = wd.settlements[0]
	stl0.owner_faction_id = "player"
	stl0.status = SettlementDataScript.STATUS_CAPTURED
	var obj0 = fsm.get_objective(stl0.linked_objective_id)
	obj0.health = 140.0
	obj0.is_under_active_siege = true

	var snap: Dictionary = SaveManager.serialize_world_state(wv)
	_assert(snap.has("settlements"), "serialize_world_state() includes 'settlements' for V8")
	var stl_sec: Dictionary = snap["settlements"]
	_assert(int(stl_sec.get("schema_version", -1)) == 1, "settlements.schema_version == 1")
	_assert(stl_sec.get("items", []).size() == 3, "settlements.items has 3 entries")

	# Deep-copy / no-alias check: mutate live SettlementData & skip_reasons after serialize
	stl0.owner_faction_id = "mutated_faction"
	stl0.roads.append(Vector2i(1, 1))
	wd.settlement_skip_reasons["rival_military"] = "map_constraints"
	_assert(stl_sec["items"][0]["owner_faction_id"] == "player", "Snapshot owner_faction_id is isolated from live mutation")
	_assert(not stl_sec["skip_reasons"].has("rival_military"), "Snapshot skip_reasons is isolated from live mutation")

	# Restore from snapshot into fresh WorldView
	var wv2 := WorldViewScene.instantiate()
	wv2.world_seed = 9999 # Force needs_terrain_rebuild == true
	root.add_child(wv2)
	await process_frame
	var load_res: Dictionary = SaveManager.apply_loaded_state_to_world(wv2, snap)
	_assert(bool(load_res.get("success", false)), "M4+ snapshot loads cleanly into different-seed WorldView")

	var wd2 = wv2.world_data
	_assert(wd2.settlements.size() == 3, "Restored world has 3 settlements")
	var r_stl0 = wd2.settlements[0]
	_assert(r_stl0.settlement_id == "stl_rival_military_1", "settlement_id preserved")
	_assert(r_stl0.origin_faction_id == "rival_military", "origin_faction_id preserved")
	_assert(r_stl0.owner_faction_id == "player", "Independent owner_faction_id preserved")
	_assert(r_stl0.status == SettlementDataScript.STATUS_CAPTURED, "Independent status preserved")
	_assert(r_stl0.roads.size() == stl_sec["items"][0]["roads"].size(), "Roads round-trip without live alias")
	var r_obj0 = wv2.field_siege_mgr.get_objective(r_stl0.linked_objective_id)
	_assert(r_obj0 != null and is_equal_approx(r_obj0.health, 140.0) and r_obj0.is_under_active_siege, "Objective combat state preserved independently")
	_assert(r_obj0.owning_faction_id == "rival_military", "Objective owning_faction_id remains independent of SettlementData.owner_faction_id")

	# Unknown schema version rejected
	var bad_ver := snap.duplicate(true)
	bad_ver["settlements"]["schema_version"] = 99
	_assert(not bool(SaveManager.validate_save_data(bad_ver).get("valid", true)), "Unsupported settlements.schema_version is rejected")

	wv.queue_free()
	wv2.queue_free()
	await process_frame

func _test_per_faction_truth_table() -> void:
	print("\n[2] Per-Faction Settlement/Skip/Objective Truth Table")
	var wv := WorldViewScene.instantiate()
	wv.world_seed = 12345
	root.add_child(wv)
	await process_frame
	var base_save: Dictionary = SaveManager.serialize_world_state(wv)
	wv.queue_free()
	await process_frame

	# Valid 1: 3 settlements
	_assert(bool(SaveManager.validate_save_data(base_save).get("valid", false)), "Truth table: 3 valid settlements passes")

	# Valid 2: 2 items + 1 map_constraints skip (0 objective)
	var mc_save: Dictionary = base_save.duplicate(true)
	mc_save["settlements"]["items"].remove_at(2) # neutral_tribe
	mc_save["settlements"]["skip_reasons"]["neutral_tribe"] = "map_constraints"
	var objs_mc: Array = mc_save["field_siege"]["objectives"]
	for i in range(objs_mc.size() - 1, -1, -1):
		if objs_mc[i]["objective_id"] == "outpost_neutral_tribe":
			objs_mc.remove_at(i)
	_assert(bool(SaveManager.validate_save_data(mc_save).get("valid", false)), "Truth table: 2 items + 1 map_constraints (0 obj) passes")

	# Invalid: map_constraints with matching objective
	var mc_with_obj: Dictionary = base_save.duplicate(true)
	mc_with_obj["settlements"]["items"].remove_at(2)
	mc_with_obj["settlements"]["skip_reasons"]["neutral_tribe"] = "map_constraints"
	_assert(not bool(SaveManager.validate_save_data(mc_with_obj).get("valid", true)), "Truth table: map_constraints with matching objective rejected")

	# Valid 3: 2 items + 1 legacy_player_building_conflict with 1 unlinked objective
	var lc_1_obj: Dictionary = base_save.duplicate(true)
	lc_1_obj["settlements"]["items"].remove_at(2)
	lc_1_obj["settlements"]["skip_reasons"]["neutral_tribe"] = "legacy_player_building_conflict"
	for o in lc_1_obj["field_siege"]["objectives"]:
		if o["objective_id"] == "outpost_neutral_tribe":
			o["linked_settlement_id"] = ""
	_assert(bool(SaveManager.validate_save_data(lc_1_obj).get("valid", false)), "Truth table: legacy_player_building_conflict + 1 unlinked obj passes")

	# Valid 4: 2 items + 1 legacy_player_building_conflict with 0 objectives
	var lc_0_obj: Dictionary = mc_save.duplicate(true)
	lc_0_obj["settlements"]["skip_reasons"]["neutral_tribe"] = "legacy_player_building_conflict"
	_assert(bool(SaveManager.validate_save_data(lc_0_obj).get("valid", false)), "Truth table: legacy_player_building_conflict + 0 obj passes")

	# Invalid: legacy_player_building_conflict with non-empty linked_settlement_id
	var lc_linked: Dictionary = base_save.duplicate(true)
	lc_linked["settlements"]["items"].remove_at(2)
	lc_linked["settlements"]["skip_reasons"]["neutral_tribe"] = "legacy_player_building_conflict"
	_assert(not bool(SaveManager.validate_save_data(lc_linked).get("valid", true)), "Truth table: legacy_player_building_conflict with linked objective rejected")

	# Valid 5: 0 items + 3 valid skip reasons
	var all_skips: Dictionary = base_save.duplicate(true)
	all_skips["settlements"]["items"].clear()
	all_skips["settlements"]["skip_reasons"] = {
		"rival_military": "map_constraints",
		"rival_merchant": "map_constraints",
		"neutral_tribe": "legacy_player_building_conflict"
	}
	all_skips["field_siege"]["objectives"] = []
	all_skips["field_siege"]["active_sieges"] = {}
	_assert(bool(SaveManager.validate_save_data(all_skips).get("valid", false)), "Truth table: 0 items + 3 valid skip reasons passes")

	# Invalid: missing faction representation
	var missing_fac: Dictionary = base_save.duplicate(true)
	missing_fac["settlements"]["items"].remove_at(2)
	_assert(not bool(SaveManager.validate_save_data(missing_fac).get("valid", true)), "Truth table: missing faction rejected")

	# Invalid: item + skip collision
	var both_fac: Dictionary = base_save.duplicate(true)
	both_fac["settlements"]["skip_reasons"]["neutral_tribe"] = "map_constraints"
	_assert(not bool(SaveManager.validate_save_data(both_fac).get("valid", true)), "Truth table: item + skip collision rejected")

	# Invalid: unknown faction / unknown skip reason / duplicate IDs
	var unk_reason: Dictionary = mc_save.duplicate(true)
	unk_reason["settlements"]["skip_reasons"]["neutral_tribe"] = "bogus_reason"
	_assert(not bool(SaveManager.validate_save_data(unk_reason).get("valid", true)), "Truth table: unknown skip reason rejected")

	var unk_fac: Dictionary = mc_save.duplicate(true)
	unk_fac["settlements"]["skip_reasons"]["alien_faction"] = "map_constraints"
	_assert(not bool(SaveManager.validate_save_data(unk_fac).get("valid", true)), "Truth table: unknown faction in skip_reasons rejected")

	var dup_sid: Dictionary = base_save.duplicate(true)
	dup_sid["settlements"]["items"][1]["settlement_id"] = dup_sid["settlements"]["items"][0]["settlement_id"]
	_assert(not bool(SaveManager.validate_save_data(dup_sid).get("valid", true)), "Truth table: duplicate settlement_id rejected")

	var dup_oid: Dictionary = base_save.duplicate(true)
	dup_oid["settlements"]["items"][1]["linked_objective_id"] = dup_oid["settlements"]["items"][0]["linked_objective_id"]
	_assert(not bool(SaveManager.validate_save_data(dup_oid).get("valid", true)), "Truth table: duplicate linked_objective_id rejected")

func _test_terrain_occupancy_reservations_and_idempotency() -> void:
	print("\n[3] Terrain, TileMapLayer, Occupancy, Reservations & Idempotency")
	var wv := WorldViewScene.instantiate()
	wv.world_seed = 12345
	root.add_child(wv)
	await process_frame

	var save_data: Dictionary = SaveManager.serialize_world_state(wv)
	var load_res: Dictionary = SaveManager.apply_loaded_state_to_world(wv, save_data)
	_assert(bool(load_res.get("success", false)), "Same-seed M4+ reload succeeds")

	var wd = wv.world_data
	var tml := wv.terrain_layer.get_node("TerrainTileMapLayer") as TileMapLayer
	var stl0 = wd.settlements[0]
	var hq_cell: Vector2i = stl0.buildings[0]["cell"]
	_assert(wd.occupancy[hq_cell.x][hq_cell.y], "Solid settlement building cell is occupied after load")
	_assert(not wd.occupancy[stl0.anchor_cell.x][stl0.anchor_cell.y], "Settlement plaza anchor_cell remains walkable after load")
	_assert(wd.terrain[stl0.anchor_cell.x][stl0.anchor_cell.y] == WorldGenerator.TerrainType.DIRT, "Settlement road/plaza cell is TERRAIN_DIRT after load")
	_assert(tml.get_cell_source_id(stl0.anchor_cell) == WorldGenerator.TerrainType.DIRT, "TerrainTileMapLayer matches TERRAIN_DIRT at road cell")
	_assert(wd.settlement_reserved_cells.has(stl0.anchor_cell), "settlement_reserved_cells rebuilt for road/anchor")
	_assert(wv.rival_buildings_by_cell.has(hq_cell), "rival_buildings_by_cell rebuilt")
	_assert(not wv.buildings_by_cell.has(hq_cell), "buildings_by_cell remains player-only")

	var count_before: int = wv.rival_settlements_container.get_child_count()
	SaveManager.apply_loaded_state_to_world(wv, save_data)
	_assert(wv.rival_settlements_container.get_child_count() == count_before, "Repeated load does not duplicate RivalSettlements nodes")

	wv.queue_free()
	await process_frame

func _test_option_b_props_and_resources_determinism() -> void:
	print("\n[4] Option B Stage E Props/Resources Determinism")
	var wv := WorldViewScene.instantiate()
	wv.world_seed = 12345
	root.add_child(wv)
	await process_frame

	var orig_props: Array = wv.world_data.props.duplicate(true)
	var cleared_cell := Vector2i(-1, -1)
	var nr_id := ""
	var nr_cell := Vector2i(-1, -1)
	for p in orig_props:
		var pt := str(p.get("type", ""))
		if pt == "tree" and cleared_cell.x < 0:
			cleared_cell = p["cell"]
		elif EconomyConfig.is_natural_resource_type(pt) and nr_id.is_empty():
			nr_id = str(p.get("id", ""))
			nr_cell = p["cell"]
		if cleared_cell.x >= 0 and not nr_id.is_empty():
			break

	var snap: Dictionary = SaveManager.serialize_world_state(wv)
	# Verify full props equality with Option B when no props are cleared/depleted
	var wv_clean := WorldViewScene.instantiate()
	wv_clean.world_seed = 777
	root.add_child(wv_clean)
	await process_frame
	var res_clean := SaveManager.apply_loaded_state_to_world(wv_clean, snap)
	_assert(bool(res_clean.get("success", false)), "Option B clean load succeeds")
	_assert(wv_clean.world_data.props.size() == orig_props.size(), "Option B preserves exact prop count (%d == %d)" % [wv_clean.world_data.props.size(), orig_props.size()])
	var all_props_match: bool = (wv_clean.world_data.props.size() == orig_props.size())
	if all_props_match:
		for i in range(orig_props.size()):
			if orig_props[i].get("type") != wv_clean.world_data.props[i].get("type") or orig_props[i].get("cell") != wv_clean.world_data.props[i].get("cell"):
				all_props_match = false
				break
	_assert(all_props_match, "Option B preserves exact deterministic prop positions & types")
	wv_clean.queue_free()

	if cleared_cell.x >= 0:
		var pid: String = wv.land_clearing_mgr.make_prop_id(12345, 8, "tree", cleared_cell)
		wv.land_clearing_mgr.cleared_prop_ids[pid] = true

	var wv2 := WorldViewScene.instantiate()
	wv2.world_seed = 777 # Force rebuild_world_terrain_for_load with Option B
	root.add_child(wv2)
	await process_frame
	if not nr_id.is_empty():
		wv.natural_resource_mgr.depleted_deltas[nr_id] = true
		wv.natural_resource_mgr.modified_deltas.erase(nr_id)
	var snap_deltas: Dictionary = SaveManager.serialize_world_state(wv)
	var res := SaveManager.apply_loaded_state_to_world(wv2, snap_deltas)
	_assert(bool(res.get("success", false)), "Option B load with cleared & depleted deltas succeeds")
	_assert(wv2.land_clearing_mgr.cleared_prop_ids.size() == wv.land_clearing_mgr.cleared_prop_ids.size(), "cleared_prop_ids preserved")
	if not nr_id.is_empty():
		_assert(wv2.natural_resource_mgr.depleted_deltas.has(nr_id), "Natural resource depleted_ids preserved via deterministic ID")
		_assert(not wv2.natural_resource_mgr.nodes_by_cell.has(nr_cell), "Depleted natural resource absent from nodes_by_cell")

	# Restore modified_qty test
	if not nr_id.is_empty():
		wv.natural_resource_mgr.depleted_deltas.erase(nr_id)
		wv.natural_resource_mgr.modified_deltas[nr_id] = 42
		var snap_mod: Dictionary = SaveManager.serialize_world_state(wv)
		SaveManager.apply_loaded_state_to_world(wv2, snap_mod)
		_assert(int(wv2.natural_resource_mgr.modified_deltas.get(nr_id, -1)) == 42, "Natural resource modified_qty preserved via deterministic ID")

	# M4+ snapshot prop conflict check in Step 3d rejects & preserves prop
	var stl0_solid_cell: Vector2i = wv.world_data.settlements[0].buildings[0]["cell"]
	var err_prop_conf := SaveManager._validate_m4_settlements_against_world(wv.world_data, wv.world_data.settlements, {}, {stl0_solid_cell: true})
	_assert(not err_prop_conf.is_empty(), "M4+ snapshot overlapping non-cleared prop is rejected by Step 3d conflict validator")

	wv.queue_free()
	wv2.queue_free()
	await process_frame

func _test_player_building_isolation_and_m4_conflicts() -> void:
	print("\n[5] Player Building Isolation & M4+ Snapshot Conflict Rejection")
	var wv := WorldViewScene.instantiate()
	wv.world_seed = 12345
	root.add_child(wv)
	await process_frame

	var snap: Dictionary = SaveManager.serialize_world_state(wv)
	var bld_count_before: int = wv.world_data.buildings.size()
	var stl0_cell: Dictionary = snap["settlements"]["items"][0]["buildings"][0]["cell"]
	var bad_snap: Dictionary = snap.duplicate(true)
	# Inject player building overlapping settlement HQ
	var th_copy: Dictionary = bad_snap["buildings"][0].duplicate(true)
	th_copy["id"] = "house_conflict_1"
	th_copy["type"] = "house"
	th_copy["cell_x"] = int(stl0_cell["x"])
	th_copy["cell_y"] = int(stl0_cell["y"])
	th_copy["size_x"] = 2
	th_copy["size_y"] = 2
	bad_snap["buildings"].append(th_copy)

	var res := SaveManager.apply_loaded_state_to_world(wv, bad_snap)
	_assert(not bool(res.get("success", true)), "M4+ snapshot overlapping player building is rejected & rolled back")
	_assert(wv.world_data.buildings.size() == bld_count_before, "Player buildings untouched after M4+ conflict rollback")

	wv.queue_free()
	await process_frame

func _test_pre_m4_v8_migration_cases() -> void:
	print("\n[6] Pre-M4 V8 Migration Cases & Repeated M4+ Save/Load")
	var wv := WorldViewScene.instantiate()
	wv.world_seed = 12345
	root.add_child(wv)
	await process_frame

	var pre_m4_save: Dictionary = SaveManager.serialize_world_state(wv)
	pre_m4_save.erase("settlements")
	# Simulate legacy pre-M4 V8 objective with empty linked_settlement_id
	for o in pre_m4_save["field_siege"]["objectives"]:
		o["linked_settlement_id"] = ""

	# Case 1: needs_terrain_rebuild == true
	var wv_diff := WorldViewScene.instantiate()
	wv_diff.world_seed = 54321
	root.add_child(wv_diff)
	await process_frame
	var r1 := SaveManager.apply_loaded_state_to_world(wv_diff, pre_m4_save)
	_assert(bool(r1.get("success", false)), "Pre-M4 V8 migration (needs_terrain_rebuild=true) succeeds")
	_assert(wv_diff.world_data.settlements.size() == 3, "Migrated 3 V8 settlements")
	_assert(wv_diff.field_siege_mgr.get_objective("outpost_rival_military").linked_settlement_id == "stl_rival_military_1", "Empty reverse link bound on unique match")

	# Case 2 & 3: needs_terrain_rebuild == false (mutated in-memory vs empty in-memory)
	wv.world_data.settlements[0].owner_faction_id = "mutated_before_mig"
	var r2 := SaveManager.apply_loaded_state_to_world(wv, pre_m4_save)
	_assert(bool(r2.get("success", false)) and wv.world_data.settlements[0].owner_faction_id == "rival_military", "Pre-M4 V8 (needs_terrain_rebuild=false) ignores stale in-memory owner")

	wv.world_data.settlements.clear()
	var r3 := SaveManager.apply_loaded_state_to_world(wv, pre_m4_save)
	_assert(bool(r3.get("success", false)) and wv.world_data.settlements.size() == 3, "Pre-M4 V8 (needs_terrain_rebuild=false, empty settlements) reconstructs in staging")

	# Case 4: Pre-M4 V8 player-building conflict -> atomic omission + legacy_player_building_conflict + repeated M4+ save/load
	var stl0_hq: Vector2i = wv.world_data.settlements[0].buildings[0]["cell"]
	var conflict_save: Dictionary = pre_m4_save.duplicate(true)
	var b_over: Dictionary = conflict_save["buildings"][0].duplicate(true)
	b_over["id"] = "house_legacy_overlap"
	b_over["type"] = "house"
	b_over["cell_x"] = stl0_hq.x
	b_over["cell_y"] = stl0_hq.y
	b_over["size_x"] = 2
	b_over["size_y"] = 2
	conflict_save["buildings"].append(b_over)

	var r_conf := SaveManager.apply_loaded_state_to_world(wv, conflict_save)
	_assert(bool(r_conf.get("success", false)), "Pre-M4 V8 player conflict omits settlement instead of failing")
	_assert(wv.world_data.settlement_skip_reasons.get("rival_military", "") == "legacy_player_building_conflict", "Records legacy_player_building_conflict")
	_assert(wv.world_data.settlements.size() == 2, "Remaining 2 settlements survive")
	var ret_obj = wv.field_siege_mgr.get_objective("outpost_rival_military")
	_assert(ret_obj != null and ret_obj.linked_settlement_id == "", "Retained legacy objective stays unlinked")

	var m4_after_mig: Dictionary = SaveManager.serialize_world_state(wv)
	var r_next := SaveManager.apply_loaded_state_to_world(wv_diff, m4_after_mig)
	_assert(bool(r_next.get("success", false)) and wv_diff.world_data.settlements.size() == 2, "Subsequent M4+ load preserves legacy_player_building_conflict without regenerating omitted settlement")

	# Case 5: Pre-M4 V8 without field_siege section + player conflict -> 2 default objectives, 0 fabricated for omitted faction, reloads cleanly
	var no_siege_save: Dictionary = conflict_save.duplicate(true)
	no_siege_save.erase("field_siege")
	var r_nosiege := SaveManager.apply_loaded_state_to_world(wv, no_siege_save)
	_assert(bool(r_nosiege.get("success", false)), "Pre-M4 V8 without field_siege + player conflict migrates cleanly")
	_assert(wv.world_data.settlement_skip_reasons.get("rival_military", "") == "legacy_player_building_conflict", "No-field_siege migration records legacy_player_building_conflict")
	_assert(wv.field_siege_mgr.get_objective("outpost_rival_military") == null, "No-field_siege migration does not fabricate objective for omitted settlement")
	_assert(wv.field_siege_mgr.get_all_objectives().size() == 2, "No-field_siege migration initializes defaults for 2 surviving settlements")
	var m4_nosiege := SaveManager.serialize_world_state(wv)
	var r_nosiege_reload := SaveManager.apply_loaded_state_to_world(wv_diff, m4_nosiege)
	_assert(bool(r_nosiege_reload.get("success", false)) and wv_diff.world_data.settlements.size() == 2 and wv_diff.field_siege_mgr.get_all_objectives().size() == 2, "M4+ save from no-field_siege migration reloads cleanly")

	wv.queue_free()
	wv_diff.queue_free()
	await process_frame

func _test_objective_reconciliation_and_option_c() -> void:
	print("\n[7] Objective Reconciliation & Option C Overlap Lifecycle")
	var wv := WorldViewScene.instantiate()
	wv.world_seed = 12345
	root.add_child(wv)
	await process_frame

	# Create an unlinked legacy objective at (60, 60) and test Option C build/demolish/click/load
	var unlinked: Node2D = wv.field_siege_mgr.register_objective("outpost_test_unlinked", Vector2i(60, 60), "rival_military", 250.0, 3, "")
	_assert(not unlinked.is_player_building_overlapping, "Initially no player building overlap")

	# Build player house overlapping 2x2 hitbox cell (61, 61)
	wv.world_data.terrain[61][61] = WorldGenerator.TerrainType.GRASS
	wv.world_data.terrain[62][61] = WorldGenerator.TerrainType.GRASS
	wv.world_data.terrain[61][62] = WorldGenerator.TerrainType.GRASS
	wv.world_data.terrain[62][62] = WorldGenerator.TerrainType.GRASS
	wv.world_data.occupancy[61][61] = false
	wv.world_data.occupancy[62][61] = false
	wv.world_data.occupancy[61][62] = false
	wv.world_data.occupancy[62][62] = false
	var hb := {"id": "house_61_61", "type": "house", "cell": Vector2i(61, 61), "size": Vector2i(2, 2), "state": "active", "health": 100, "max_health": 100}
	wv.world_data.buildings.append(hb)
	wv._instantiate_building_node("house", Vector2i(61, 61), Vector2i(2, 2), "active")
	_assert(unlinked.is_player_building_overlapping, "Option C sets is_player_building_overlapping when 2x2 hitbox overlaps player building")

	# Left-click precedence: (61, 61) selects player building; (60, 60) selects objective
	wv.fog_of_war.reveal_circle(Vector2i(60, 60), 4)
	wv._handle_left_click(Vector2i(61, 61))
	_assert(wv.selected_building_id == "house_61_61", "Left-click on overlapping player cell selects player building")
	wv._handle_left_click(Vector2i(60, 60))
	_assert(wv.selected_building_id == "outpost_test_unlinked", "Left-click on unoccupied hitbox cell selects objective")

	# Right-click objective lookup & siege eligibility remain unchanged when overlapped
	_assert(wv._find_siege_objective_at_cell(Vector2i(61, 61)) == unlinked, "Right-click objective lookup still resolves overlapped objective")

	# complete_upgrade() refreshes overlap state idempotently
	hb["is_upgrading"] = true
	hb["upgrade_target_level"] = 2
	hb["upgrade_progress"] = 2.0
	hb["upgrade_required_hours"] = 2.0
	wv.complete_upgrade("house_61_61")
	hb.erase("is_upgrading")
	_assert(unlinked.is_player_building_overlapping, "complete_upgrade() preserves overlap flag idempotently")

	# Save/Load recomputes Option C overlap flag
	var optc_snap := SaveManager.serialize_world_state(wv)
	SaveManager.apply_loaded_state_to_world(wv, optc_snap)
	var restored_unlinked = wv.field_siege_mgr.get_objective("outpost_test_unlinked")
	_assert(restored_unlinked != null and restored_unlinked.is_player_building_overlapping, "Save/Load recomputes Option C overlap flag")

	# Demolish clears overlap flag
	var demo_res: Dictionary = wv.demolish_building_project("house_61_61")
	_assert(bool(demo_res.get("success", false)) and not restored_unlinked.is_player_building_overlapping, "Demolish clears is_player_building_overlapping")

	wv.queue_free()
	await process_frame

func _test_fow_minimap_and_cross_size_bounds() -> void:
	print("\n[8] FOW, Minimap, Cross-Size & Strict Bounds")
	# Direct 64x64 deserialize rejects (70, 18)
	IsoMath.set_active_map_dimensions(64, 64)
	var actor := SiegeObjectiveActorScript.new()
	var ok_64 := actor.deserialize({"objective_id": "outpost_rival_military", "owning_faction_id": "rival_military", "current_cell": [70, 18]})
	_assert(not ok_64, "Strict SiegeObjectiveActor.deserialize() rejects (70, 18) when active map is 64x64")
	actor.free()

	# 128x128 <-> 64x64 round trip via SaveManager
	var wv128 := WorldViewScene.instantiate()
	wv128.world_seed = 12345
	root.add_child(wv128)
	await process_frame
	var save128: Dictionary = SaveManager.serialize_world_state(wv128)

	var wv64 := WorldViewScene.instantiate()
	wv64.world_seed = 12345
	wv64.world_generator_version = 3
	root.add_child(wv64)
	await process_frame
	var save64: Dictionary = SaveManager.serialize_world_state(wv64)

	_assert(bool(SaveManager.apply_loaded_state_to_world(wv128, save64).get("success", false)), "128x128 -> 64x64 load succeeds")
	_assert(wv128.world_data.settlements.is_empty(), "V3 64x64 load has 0 procedural settlements")
	_assert(bool(SaveManager.apply_loaded_state_to_world(wv128, save128).get("success", false)), "64x64 -> 128x128 reload succeeds with preflight bounds scoping")
	_assert(wv128.world_data.settlements.size() == 3, "128x128 reload restores 3 settlements")

	wv128.queue_free()
	wv64.queue_free()
	await process_frame

func _test_rollback_failure_injection() -> void:
	print("\n[9] Rollback Failure Injection (Post-Step-3d/3e)")
	var wv := WorldViewScene.instantiate()
	wv.world_seed = 12345
	root.add_child(wv)
	await process_frame

	var pre_snap: Dictionary = SaveManager.serialize_world_state(wv)
	var pre_wid: String = str(wv.world_id)
	var pre_stl_count: int = wv.world_data.settlements.size()
	var pre_hq_cell: Vector2i = wv.world_data.settlements[0].buildings[0]["cell"]
	var pre_road_cell: Vector2i = wv.world_data.settlements[0].anchor_cell
	var pre_biome: int = wv.world_data.get_biome(pre_road_cell)
	var pre_props_count: int = wv.world_data.props.size()
	var pre_bld_count: int = wv.world_data.buildings.size()
	var pre_res_count: int = wv.world_data.settlement_reserved_cells.size()
	var pre_rival_cnt: int = wv.rival_buildings_by_cell.size()
	var pre_fow_explored: bool = wv.fog_of_war.is_explored(wv.world_data.center_spawn)
	var mm = wv.hud.get_minimap() if wv.hud != null else null
	var pre_mm_pois: int = mm.get_visible_markers_snapshot()["pois"].size() if mm != null else -1

	var wv_other := WorldViewScene.instantiate()
	wv_other.world_seed = 54321
	root.add_child(wv_other)
	await process_frame
	var fail_save: Dictionary = SaveManager.serialize_world_state(wv_other)
	wv_other.queue_free()
	await process_frame

	# Put a player building overlapping wv_other's settlement HQ -> passes validate_save_data & preflight, rebuilds terrain to seed 54321, then FAILS in Step 3d!
	var other_hq: Dictionary = fail_save["settlements"]["items"][0]["buildings"][0]["cell"]
	var b_conf: Dictionary = fail_save["buildings"][0].duplicate(true)
	b_conf["id"] = "house_rollback_trig"
	b_conf["type"] = "house"
	b_conf["cell_x"] = int(other_hq["x"])
	b_conf["cell_y"] = int(other_hq["y"])
	b_conf["size_x"] = 2
	b_conf["size_y"] = 2
	fail_save["buildings"].append(b_conf)

	var fail_res := SaveManager.apply_loaded_state_to_world(wv, fail_save)
	_assert(not bool(fail_res.get("success", true)), "Mid-load Step 3d conflict fails & triggers Strategy A rollback")
	_assert(wv.world_id == pre_wid and wv.world_seed == 12345 and wv.world_data.generator_version == 8, "Rollback restored world_id, seed, and generator_version")
	_assert(wv.world_data.map_width == 128 and wv.world_data.map_height == 128, "Rollback restored 128x128 dimensions")
	_assert(wv.world_data.get_biome(pre_road_cell) == pre_biome, "Rollback restored biome_grid")
	_assert(wv.world_data.props.size() == pre_props_count, "Rollback restored props count")
	_assert(wv.world_data.buildings.size() == pre_bld_count, "Rollback restored player buildings count")
	_assert(wv.world_data.settlements.size() == pre_stl_count and wv.world_data.settlement_skip_reasons.is_empty(), "Rollback restored 3 settlements & skip_reasons")
	_assert(wv.world_data.settlement_reserved_cells.size() == pre_res_count, "Rollback restored settlement_reserved_cells")
	_assert(wv.world_data.occupancy[pre_hq_cell.x][pre_hq_cell.y], "Rollback restored prior settlement solid occupancy")
	_assert(wv.world_data.terrain[pre_road_cell.x][pre_road_cell.y] == WorldGenerator.TerrainType.DIRT, "Rollback restored prior road TERRAIN_DIRT")
	var tml := wv.terrain_layer.get_node("TerrainTileMapLayer") as TileMapLayer
	_assert(tml.get_cell_source_id(pre_road_cell) == WorldGenerator.TerrainType.DIRT, "Rollback restored TerrainTileMapLayer")
	_assert(wv.rival_buildings_by_cell.size() == pre_rival_cnt and wv.rival_settlements_container.get_child_count() == 3, "Rollback restored rival_buildings_by_cell & RivalSettlements")
	_assert(wv.field_siege_mgr.get_all_objectives().size() == 3, "Rollback restored 3 objectives")
	_assert(wv.fog_of_war.is_explored(wv.world_data.center_spawn) == pre_fow_explored, "Rollback restored FOW explored state")
	if mm != null:
		_assert(mm.get_visible_markers_snapshot()["pois"].size() == pre_mm_pois, "Rollback restored Minimap markers")

	# Direct _is_rollback == true terminal failure guard (no infinite recursion)
	var bad_rb := pre_snap.duplicate(true)
	bad_rb["schema_version"] = 999
	var rb_fail := SaveManager.apply_loaded_state_to_world(wv, bad_rb, true)
	_assert(not bool(rb_fail.get("success", true)), "Terminal rollback failure returns success=false without infinite recursion")

	wv.queue_free()
	await process_frame

func _assert_full_world_state_matches(
	wv: Node,
	pre_snap: Dictionary,
	pre_props: Array,
	pre_reserved: Dictionary,
	pre_rival_cells: Dictionary,
	pre_blds_by_cell: Dictionary,
	pre_mm_snap: Dictionary,
	label: String
) -> void:
	var wd = wv.world_data
	var meta: Dictionary = pre_snap["metadata"]
	_assert(wv.world_id == str(meta["world_id"]) and wv.world_seed == int(meta["world_seed"]) and wd.generator_version == int(meta["world_generator_version"]), "%s: world identity/seed/version restored" % label)
	_assert(wd.map_width == int(meta["map_width"]) and wd.map_height == int(meta["map_height"]), "%s: map dimensions restored" % label)

	var pre_stl0: Dictionary = pre_snap["settlements"]["items"][0]
	var road_c := Vector2i(int(pre_stl0["anchor_cell"]["x"]), int(pre_stl0["anchor_cell"]["y"]))
	var hq_c := Vector2i(int(pre_stl0["buildings"][0]["cell"]["x"]), int(pre_stl0["buildings"][0]["cell"]["y"]))
	var tml := wv.terrain_layer.get_node("TerrainTileMapLayer") as TileMapLayer
	_assert(wd.terrain[road_c.x][road_c.y] == WorldGenerator.TerrainType.DIRT and tml.get_cell_source_id(road_c) == WorldGenerator.TerrainType.DIRT, "%s: terrain & TileMapLayer restored" % label)
	_assert(wd.occupancy[hq_c.x][hq_c.y] and not wd.occupancy[road_c.x][road_c.y], "%s: settlement solid occupancy & walkable plaza restored" % label)

	var props_ok: bool = (wd.props.size() == pre_props.size())
	if props_ok:
		for i in range(pre_props.size()):
			if wd.props[i].get("type") != pre_props[i].get("type") or wd.props[i].get("cell") != pre_props[i].get("cell"):
				props_ok = false
				break
	_assert(props_ok, "%s: exact props array (types & positions) restored" % label)
	_assert(wv.land_clearing_mgr.cleared_prop_ids.size() == pre_snap.get("land_clearing", {}).get("cleared_prop_ids", []).size(), "%s: land_clearing deltas restored" % label)
	_assert(wv.natural_resource_mgr.modified_deltas == pre_snap.get("natural_resources", {}).get("modified_qty", {}), "%s: natural_resources modified_qty restored" % label)

	_assert(wd.buildings.size() == pre_snap["buildings"].size() and wv.buildings_by_cell == pre_blds_by_cell, "%s: player buildings & buildings_by_cell exact equality" % label)
	_assert(wd.settlements.size() == pre_snap["settlements"]["items"].size(), "%s: settlement count restored" % label)
	_assert(wd.settlements[0].owner_faction_id == pre_stl0["owner_faction_id"] and wd.settlements[0].status == pre_stl0["status"], "%s: settlement owner & status restored" % label)
	_assert(wd.settlement_skip_reasons == pre_snap["settlements"]["skip_reasons"], "%s: settlement_skip_reasons restored" % label)
	_assert(wd.settlement_reserved_cells == pre_reserved, "%s: settlement_reserved_cells exact equality" % label)
	_assert(wv.rival_buildings_by_cell == pre_rival_cells and wv.rival_settlements_container.get_child_count() == pre_snap["settlements"]["items"].size(), "%s: rival_buildings_by_cell & RivalSettlements restored" % label)

	var pre_objs: Array = pre_snap["field_siege"]["objectives"]
	_assert(wv.field_siege_mgr.get_all_objectives().size() == pre_objs.size(), "%s: objective count restored" % label)
	var obj0 = wv.field_siege_mgr.get_objective("outpost_rival_military")
	var pre_o0: Dictionary = pre_objs[0]
	for po in pre_objs:
		if po["objective_id"] == "outpost_rival_military":
			pre_o0 = po
			break
	_assert(obj0 != null and is_equal_approx(obj0.health, float(pre_o0["health"])) and obj0.is_captured == bool(pre_o0["is_captured"]) and obj0.linked_settlement_id == str(pre_o0["linked_settlement_id"]) and not obj0.is_player_building_overlapping, "%s: objective state, relationship & overlap flag restored" % label)

	var pre_fow_coords: Array = pre_snap["fog_of_war"]
	var fow_ok: bool = true
	for c in pre_fow_coords:
		if not wv.fog_of_war.is_explored(Vector2i(int(c[0]), int(c[1]))):
			fow_ok = false
			break
	_assert(fow_ok, "%s: FOW explored state restored" % label)
	var mm = wv.hud.get_minimap() if wv.hud != null else null
	if mm != null:
		_assert(mm.get_visible_markers_snapshot() == pre_mm_snap, "%s: Minimap markers exact equality" % label)

func _test_rollback_after_step_3d_3e_and_step_19_boundaries() -> void:
	print("\n[10] Mandatory Rollback Boundaries: Post-Step-3d/3e & Post-Step-19/19a")
	var wv := WorldViewScene.instantiate()
	wv.world_seed = 12345
	root.add_child(wv)
	await process_frame

	# Mutate pre-load world so it is non-trivial (settlement owner/status, objective HP, cleared prop, resource qty, FOW)
	wv.world_data.settlements[0].owner_faction_id = "player"
	wv.world_data.settlements[0].status = SettlementDataScript.STATUS_CAPTURED
	wv.apply_settlement_overlays_from_world_data()
	var obj0 = wv.field_siege_mgr.get_objective("outpost_rival_military")
	obj0.health = 175.0
	for i in range(wv.world_data.props.size()):
		var p: Dictionary = wv.world_data.props[i]
		if str(p.get("type", "")) == "tree":
			var pid: String = wv.land_clearing_mgr.make_prop_id(12345, 8, "tree", p["cell"])
			wv.land_clearing_mgr.cleared_prop_ids[pid] = true
			wv.world_data.props.remove_at(i)
			break
	for nid in wv.natural_resource_mgr.nodes_by_cell.values():
		var rid := str(nid.get("id", ""))
		if not rid.is_empty():
			wv.natural_resource_mgr.modified_deltas[rid] = 33
			break
	wv.fog_of_war.reveal_circle(wv.world_data.settlements[0].anchor_cell, 3)
	wv.refresh_world_vision()

	var pre_snap: Dictionary = SaveManager.serialize_world_state(wv)
	var pre_props: Array = wv.world_data.props.duplicate(true)
	var pre_reserved: Dictionary = wv.world_data.settlement_reserved_cells.duplicate(true)
	var pre_rival_cells: Dictionary = wv.rival_buildings_by_cell.duplicate(true)
	var pre_blds_by_cell: Dictionary = wv.buildings_by_cell.duplicate(true)
	var mm = wv.hud.get_minimap()
	var pre_mm_snap: Dictionary = mm.get_visible_markers_snapshot()

	# Valid different-seed target save (passes validate_save_data & preflight)
	var wv_target := WorldViewScene.instantiate()
	wv_target.world_seed = 54321
	root.add_child(wv_target)
	await process_frame
	var target_save: Dictionary = SaveManager.serialize_world_state(wv_target)
	wv_target.queue_free()
	await process_frame

	# Test A: Failure injected AFTER Step 3d/3e commit (via Step 18 FailOnceEnemyMgr)
	var orig_em = wv.enemy_military_mgr
	var fail_em := FailOnceEnemyMgr.new(wv, wv.faction_mgr)
	fail_em.set_field_siege_manager(wv.field_siege_mgr)
	fail_em.set_tactical_military_manager(wv.tactical_military_mgr)
	fail_em.fail_once = false
	fail_em.deserialize(pre_snap.get("enemy_military", {}))
	fail_em.calls_seen = 0
	fail_em.fail_once = true
	wv.enemy_military_mgr = fail_em
	var res_a := SaveManager.apply_loaded_state_to_world(wv, target_save)
	_assert(not bool(res_a.get("success", true)) and fail_em.calls_seen == 2, "Test A: Step 3d/3e committed, Step 18 failed & Strategy A rollback ran")
	_assert_full_world_state_matches(wv, pre_snap, pre_props, pre_reserved, pre_rival_cells, pre_blds_by_cell, pre_mm_snap, "Test A")
	wv.enemy_military_mgr = orig_em

	# Test B: Failure injected AFTER Step 19 FieldSiegeManager.deserialize() inside Step 19a reconciliation
	var orig_fsm = wv.field_siege_mgr
	var corrupt_fsm := CorruptOnceSiegeMgr.new(wv, wv.faction_mgr, wv.player_army_mgr, wv.enemy_military_mgr)
	corrupt_fsm.set_objectives_container(orig_fsm.objectives_container)
	corrupt_fsm.corrupt_once = false
	corrupt_fsm.deserialize(pre_snap.get("field_siege", {}))
	corrupt_fsm.calls_seen = 0
	corrupt_fsm.corrupt_once = true
	wv.field_siege_mgr = corrupt_fsm
	var res_b := SaveManager.apply_loaded_state_to_world(wv, target_save)
	_assert(not bool(res_b.get("success", true)) and corrupt_fsm.calls_seen == 2, "Test B: Step 19 completed, Step 19a reconciliation failed & Strategy A rollback ran")
	_assert_full_world_state_matches(wv, pre_snap, pre_props, pre_reserved, pre_rival_cells, pre_blds_by_cell, pre_mm_snap, "Test B")
	wv.field_siege_mgr = orig_fsm

	wv.queue_free()
	await process_frame
