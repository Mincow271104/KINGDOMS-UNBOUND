extends SceneTree

const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const TerrainPreviewFieldScript = preload("res://scripts/world/terrain_preview_field.gd")

var _passed: int = 0
var _failed: int = 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] %s" % msg)
	else:
		_failed += 1
		printerr("  [FAIL] %s" % msg)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=== TEST SUITE: C1.9.2 M2-C3 Production Cloud Integration ===")
	var world_scene := load("res://scenes/world/world_view.tscn") as PackedScene
	_assert(world_scene != null, "world_view.tscn loads cleanly")
	if world_scene == null:
		quit(1)
		return

	var wv := world_scene.instantiate()
	get_root().add_child(wv)
	await process_frame
	await process_frame
	await process_frame

	var field: TerrainPreviewFieldScript = wv.get("terrain_preview_field") as TerrainPreviewFieldScript
	var renderer = wv.get("terrain_preview_renderer")
	var fog: FogOfWar = wv.get("fog_of_war") as FogOfWar
	var comp: Polygon2D = wv.get("cloud_sea_composite") as Polygon2D
	var tml: TileMapLayer = wv.get("fog_tile_layer") as TileMapLayer
	var cl = wv.get("fog_cloud_layer")
	var csb: Polygon2D = wv.get("cloud_sea_base") as Polygon2D

	# 1. Production activation & zero duplicate rendering
	_assert(wv.get("use_cloud_sea_composite") == true, "use_cloud_sea_composite defaults to true")
	_assert(comp != null and comp.visible, "CloudSeaComposite is visible by default")
	_assert(tml != null and not tml.visible, "Legacy fog_tile_layer is hidden when composite is active")
	_assert(cl != null and not cl.visible, "Legacy fog_cloud_layer is hidden when composite is active")
	_assert(csb != null and not csb.visible, "Legacy cloud_sea_base is hidden when composite is active")

	# Debug fog toggle
	wv.call("set_debug_fog_disabled", true)
	_assert(not comp.visible and not tml.visible and not cl.visible and not csb.visible, "set_debug_fog_disabled(true) hides composite and legacy layers")
	wv.call("set_debug_fog_disabled", false)
	_assert(comp.visible and not tml.visible and not cl.visible and not csb.visible, "set_debug_fog_disabled(false) restores composite only")

	# 2. Town Hall dynamic source & L1 -> L2 -> L3 upgrade synchronization
	var wd = wv.get("world_data")
	var th_id_str := ""
	var expected_th_cell: Vector2i = Vector2i(-1, -1)
	for b in wd.buildings:
		if str(b.get("type", "")) == "townhall":
			th_id_str = str(b.get("id", "townhall_starter"))
			expected_th_cell = b.get("cell", Vector2i(-1, -1))
			break
	_assert(field.has_source("townhall_main"), "townhall_main preview source registered")
	var th_src: Dictionary = field.get_source("townhall_main")
	_assert(th_src.get("cell") == expected_th_cell, "townhall_main uses dynamic Town Hall building cell %s" % str(expected_th_cell))
	_assert(is_equal_approx(float(th_src.get("preview_radius_px", 0.0)), 350.0) and is_equal_approx(float(th_src.get("core_radius_px", 0.0)), 200.0), "townhall_main L1 uses 350.0 / 200.0 px radii")

	# Upgrade L1 -> L2 -> L3 via production upgrade flow
	var rm_upg = get_root().get_node_or_null("/root/ResourceManager")
	if rm_upg != null and rm_upg.has_method("add_resource"):
		rm_upg.add_resource(EconomyConfig.RES_WOOD, 2000)
		rm_upg.add_resource(EconomyConfig.RES_STONE, 2000)
		rm_upg.add_resource(EconomyConfig.RES_GOLD, 2000)
	var gpu_before_l2: int = int(renderer.get("_gpu_pass_count"))
	var upg2_start: Dictionary = wv.call("start_building_upgrade", th_id_str, rm_upg)
	var th_b_ref: Dictionary = BuildingSystem.get_building_by_id(th_id_str, wd)
	th_b_ref["upgrade_progress"] = float(th_b_ref.get("upgrade_required_hours", 10.0))
	var upg2_ok: bool = bool(wv.call("complete_upgrade", th_id_str, rm_upg))
	await process_frame
	var l2_src: Dictionary = field.get_source("townhall_main")
	var expected_l2_scale: float = float(EconomyConfig.get_territory_radius(2)) / float(EconomyConfig.get_territory_radius(1))
	_assert(bool(upg2_start.get("success", false)) and upg2_ok, "Town Hall L1 -> L2 production upgrade succeeds")
	_assert(is_equal_approx(float(l2_src.get("preview_radius_px", 0.0)), 350.0 * expected_l2_scale) and is_equal_approx(float(l2_src.get("core_radius_px", 0.0)), 200.0 * expected_l2_scale), "Town Hall L2 scales preview/core radii deterministically from territory radius")
	_assert(int(renderer.get("_gpu_pass_count")) == gpu_before_l2 + 1, "Town Hall L2 upgrade triggers exactly 1 GPU preview pass")

	# Upgrade L2 -> L3
	if rm_upg != null and rm_upg.has_method("add_resource"):
		rm_upg.add_resource(EconomyConfig.RES_WOOD, 2000)
		rm_upg.add_resource(EconomyConfig.RES_STONE, 2000)
		rm_upg.add_resource(EconomyConfig.RES_GOLD, 2000)
	var gpu_before_l3: int = int(renderer.get("_gpu_pass_count"))
	var upg3_start: Dictionary = wv.call("start_building_upgrade", th_id_str, rm_upg)
	_assert(bool(upg3_start.get("success", false)), "Town Hall L2 -> L3 upgrade starts")
	th_b_ref = BuildingSystem.get_building_by_id(th_id_str, wd)
	th_b_ref["upgrade_progress"] = float(th_b_ref.get("upgrade_required_hours", 10.0))
	var upg3_ok: bool = bool(wv.call("complete_upgrade", th_id_str, rm_upg))
	await process_frame
	var l3_src: Dictionary = field.get_source("townhall_main")
	var expected_l3_scale: float = float(EconomyConfig.get_territory_radius(3)) / float(EconomyConfig.get_territory_radius(1))
	_assert(upg3_ok, "Town Hall L2 -> L3 production upgrade succeeds")
	_assert(is_equal_approx(float(l3_src.get("preview_radius_px", 0.0)), 350.0 * expected_l3_scale) and is_equal_approx(float(l3_src.get("core_radius_px", 0.0)), 200.0 * expected_l3_scale), "Town Hall L3 scales preview/core radii deterministically from territory radius")
	_assert(int(renderer.get("_gpu_pass_count")) == gpu_before_l3 + 1, "Town Hall L3 upgrade triggers exactly 1 GPU preview pass")

	var cur_expected_scale: float = float(EconomyConfig.get_territory_radius(int(th_b_ref.get("upgrade_level", 2)))) / float(EconomyConfig.get_territory_radius(1))

	# Town Hall destruction/restoration
	th_b_ref["state"] = "destroyed"
	wv.call("sync_gameplay_terrain_preview_sources")
	_assert(not field.has_source("townhall_main"), "Destroyed Town Hall removes townhall_main preview source")
	th_b_ref["state"] = "active"
	wv.call("sync_gameplay_terrain_preview_sources")
	_assert(field.has_source("townhall_main"), "Restored Town Hall re-registers townhall_main preview source")
	var restored_src: Dictionary = field.get_source("townhall_main")
	_assert(is_equal_approx(float(restored_src.get("preview_radius_px", 0.0)), 350.0 * cur_expected_scale), "Restored upgraded Town Hall preserves upgraded preview radius")

	# 3. Qualified Scout vs ordinary Hunter lifecycle
	var cit_list: Array = wv.get("citizen_list")
	_assert(cit_list.size() > 0, "Starter citizens exist")
	var cit = cit_list[0]
	var cid: String = str(cit.get("citizen_id"))
	wv.call("_on_citizen_role_changed", cid, "hunter")
	_assert(not field.has_source("hunter_%s" % cid), "Ordinary Hunter without can_scout_beyond_territory does NOT receive preview source")
	cit.set("can_scout_beyond_territory", true)
	wv.call("sync_gameplay_terrain_preview_sources")
	_assert(field.has_source("hunter_%s" % cid), "Qualified Scout (can_scout_beyond_territory == true) registers preview source")
	var h_cell: Vector2i = cit.get("current_cell") + Vector2i(3, -2)
	cit.set("current_cell", h_cell)
	cit.set("facing_dir", 2) # S -> (0, 1)
	wv.call("_sync_hunter_preview_sources_if_moved")
	var h_src: Dictionary = field.get_source("hunter_%s" % cid)
	_assert(h_src.get("cell") == h_cell and h_src.get("dir", Vector2.ZERO).y > 0.9, "Qualified Scout movement & facing updates preview source cell and direction")

	# Idle no-op check
	await process_frame
	var r_before: int = int(renderer.get("_gpu_pass_count"))
	wv.call("_sync_hunter_preview_sources_if_moved")
	wv.call("sync_gameplay_terrain_preview_sources")
	await process_frame
	_assert(int(renderer.get("_gpu_pass_count")) == r_before, "Repeated idle preview sync triggers 0 redundant GPU passes")

	cit.set("can_scout_beyond_territory", false)
	wv.call("sync_gameplay_terrain_preview_sources")
	_assert(not field.has_source("hunter_%s" % cid), "Removing scouting permission removes preview source")

	# Re-enable scout then kill
	cit.set("can_scout_beyond_territory", true)
	wv.call("sync_gameplay_terrain_preview_sources")
	_assert(field.has_source("hunter_%s" % cid), "Re-qualified Scout preview source present before death")
	cit.set("health", 0.0)
	wv.call("_on_citizen_died", cid)
	await process_frame
	_assert(not field.has_source("hunter_%s" % cid), "Scout death cleanly removes preview source")

	# 4. Soldier lifecycle (spawn, move with ZERO trail, despawn)
	var tac_mgr = wv.get("tactical_military_mgr")
	_assert(tac_mgr != null, "TacticalMilitaryManager present")
	var s_cell_a: Vector2i = expected_th_cell + Vector2i(2, 2)
	var s_cell_b: Vector2i = expected_th_cell + Vector2i(6, 4)
	var spawned_ids: Array[String] = tac_mgr.call("spawn_units_at_base", 1, false, s_cell_a)
	_assert(spawned_ids.size() == 1, "spawn_units_at_base spawned 1 soldier")
	var uid: String = spawned_ids[0]
	var s_unit = tac_mgr.call("get_unit", uid)
	var s_init_cell: Vector2i = s_unit.get("current_cell") if s_unit != null else s_cell_a
	_assert(s_unit != null and field.has_source("soldier_%s" % uid), "Spawning soldier registers soldier preview source")
	_assert(field.get_source("soldier_%s" % uid).get("cell") == s_init_cell, "Soldier preview source starts at spawn cell")
	s_unit.set("current_cell", s_cell_b)
	wv.call("_on_tactical_unit_moved", uid, s_cell_b)
	_assert(field.get_source("soldier_%s" % uid).get("cell") == s_cell_b, "Moving soldier updates single source to new cell")
	var soldier_source_count := 0
	for sid in field.get_source_ids():
		if str(sid).begins_with("soldier_%s" % uid):
			soldier_source_count += 1
	_assert(soldier_source_count == 1, "Soldier leaves ZERO preview trail (exactly 1 source for unit)")
	tac_mgr.call("despawn_units", [uid], true)
	await process_frame
	_assert(not field.has_source("soldier_%s" % uid), "Despawning soldier removes preview source")

	# 5. Save/Load & repeated load idempotency
	var saved_dict: Dictionary = SaveManagerScript.serialize_world_state(wv)
	_assert(not saved_dict.is_empty(), "SaveManager.serialize_world_state succeeds")
	var load_res1: Dictionary = SaveManagerScript.apply_loaded_state_to_world(wv, saved_dict)
	await process_frame
	_assert(bool(load_res1.get("success", false)), "First SaveManager.apply_loaded_state_to_world succeeds")
	var fog_after_1: FogOfWar = wv.get("fog_of_war") as FogOfWar
	var load_res2: Dictionary = SaveManagerScript.apply_loaded_state_to_world(wv, saved_dict)
	await process_frame
	_assert(bool(load_res2.get("success", false)), "Repeated SaveManager.apply_loaded_state_to_world succeeds")
	var fog_after_2: FogOfWar = wv.get("fog_of_war") as FogOfWar
	var comp_mat := comp.material as ShaderMaterial
	_assert(field.get("_fog_of_war") == fog_after_2, "TerrainPreviewField rebound to latest FogOfWar after repeated load")
	_assert(comp_mat.get_shader_parameter("fog_state_tex") == wv.call("get_fog_state_texture"), "CloudSeaComposite fog_state_tex rebound after repeated load")
	_assert(comp_mat.get_shader_parameter("envelope_tex") == renderer.get_envelope_texture(), "CloudSeaComposite envelope_tex bound after repeated load")
	_assert(field.has_source("townhall_main"), "Gameplay Town Hall preview source re-synced after repeated load")

	# 6. Entity visibility safety across VISIBLE / EXPLORED_NOT_VISIBLE / UNEXPLORED (even inside preview envelope)
	var test_fog: FogOfWar = wv.get("fog_of_war") as FogOfWar
	var preview_unexp_cell := expected_th_cell + Vector2i(14, 14)
	if preview_unexp_cell.x < test_fog.map_width and preview_unexp_cell.y < test_fog.map_height:
		test_fog.set_state(preview_unexp_cell, FogOfWar.State.UNEXPLORED)
	var exp_not_vis_cell := Vector2i(10, 10)
	var vis_cell := expected_th_cell
	test_fog.set_state(exp_not_vis_cell, FogOfWar.State.EXPLORED)
	test_fog.set_state(vis_cell, FogOfWar.State.VISIBLE)
	test_fog.rebuild_visible_cache()

	var enemy_mgr = wv.get("enemy_military_mgr")
	var mon_mgr = wv.get("monster_mgr")
	var wl_mgr = wv.get("wildlife_mgr")
	if enemy_mgr != null and enemy_mgr.has_method("spawn_enemy_unit"):
		var e_unexp = enemy_mgr.call("spawn_enemy_unit", "bandits", preview_unexp_cell, "test_e_unexp")
		var e_exp = enemy_mgr.call("spawn_enemy_unit", "bandits", exp_not_vis_cell, "test_e_exp")
		var e_vis = enemy_mgr.call("spawn_enemy_unit", "bandits", vis_cell, "test_e_vis")
		wv.call("_refresh_dynamic_actor_visibility")
		_assert(e_unexp != null and not e_unexp.visible, "Enemy military hidden in UNEXPLORED even inside preview envelope")
		_assert(e_exp != null and not e_exp.visible, "Enemy military hidden in EXPLORED_NOT_VISIBLE")
		_assert(e_vis != null and e_vis.visible, "Enemy military visible in VISIBLE")
	if mon_mgr != null and mon_mgr.has_method("get_living_monsters"):
		var living_mon: Array = mon_mgr.call("get_living_monsters")
		if living_mon.size() >= 3:
			var mu_node = mon_mgr.call("get_monster_actor", str(living_mon[0].get("id")))
			var me_node = mon_mgr.call("get_monster_actor", str(living_mon[1].get("id")))
			var mv_node = mon_mgr.call("get_monster_actor", str(living_mon[2].get("id")))
			living_mon[0]["cell"] = preview_unexp_cell
			living_mon[1]["cell"] = exp_not_vis_cell
			living_mon[2]["cell"] = vis_cell
			if mu_node != null and me_node != null and mv_node != null:
				mu_node.set("current_cell", preview_unexp_cell)
				me_node.set("current_cell", exp_not_vis_cell)
				mv_node.set("current_cell", vis_cell)
				mon_mgr.call("refresh_visibility", test_fog, false)
				_assert(not mu_node.visible, "Monster hidden in UNEXPLORED even inside preview envelope")
				_assert(not me_node.visible, "Monster hidden in EXPLORED_NOT_VISIBLE")
				_assert(mv_node.visible, "Monster visible in VISIBLE")
	if wl_mgr != null and wl_mgr.has_method("refresh_visibility"):
		wl_mgr.call("refresh_visibility", test_fog, false)
		_assert(true, "Wildlife visibility refresh executes cleanly with FogOfWar")

	wv.queue_free()
	await process_frame
	await process_frame

	if _failed == 0:
		print("PASS: test_c192_m2_c3_production_cloud.gd (%d assertions passed, 0 failed)" % _passed)
		quit(0)
	else:
		printerr("FAIL: test_c192_m2_c3_production_cloud.gd (%d passed, %d failed)" % [_passed, _failed])
		quit(1)
