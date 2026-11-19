extends SceneTree

const WorldViewScene := preload("res://scenes/world/world_view.tscn")
const MonsterConfigScript := preload("res://scripts/world/monster_config.gd")
const EntityInspectionQueryScript := preload("res://scripts/ui/entity_inspection_query.gd")

var _passed: int = 0
var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures.append(msg)
		push_error("FAIL: " + msg)

func _tex_hash(tex: Texture2D) -> String:
	if tex == null:
		return "null"
	var img: Image = tex.get_image()
	if img == null:
		return "no_img"
	return str(img.get_data().hex_encode().hash())

func _vm_has_text(vm: Dictionary, needle: String) -> bool:
	var n := needle.to_lower()
	if str(vm.get("title", "")).to_lower().contains(n):
		return true
	if str(vm.get("subtitle", "")).to_lower().contains(n):
		return true
	if str(vm.get("status_text", "")).to_lower().contains(n):
		return true
	if str(vm.get("coords_text", "")).to_lower().contains(n):
		return true
	if str(vm.get("bar_text", "")).to_lower().contains(n):
		return true
	for r in vm.get("rows", []):
		if r is Dictionary:
			if str(r.get("label", "")).to_lower().contains(n) or str(r.get("value", "")).to_lower().contains(n):
				return true
	return false

func _run() -> void:
	print("[test_entity_inspection_ui] Starting M6-1 comprehensive suite...")
	var wv := WorldViewScene.instantiate()
	wv.set("skip_intro_for_test", true)
	root.add_child(wv)
	await create_timer(0.25).timeout

	var hud = wv.get("hud")
	var fow: FogOfWar = wv.get("fog_of_war")
	var wd = wv.get("world_data")
	var wl_mgr = wv.get("wildlife_mgr")
	var m_mgr = wv.get("monster_mgr")
	var poi_mgr = wv.get("poi_mgr")
	var nrm = wv.get("natural_resource_mgr")
	var tm_mgr = wv.get("tactical_military_mgr")
	var em_mgr = wv.get("enemy_military_mgr")
	var territory_mgr = wv.get("territory_mgr")

	_assert(hud != null and hud.has_method("show_entity_inspector"), "Setup: HUD exposes show_entity_inspector")
	var ep = hud.get("entity_inspect_panel")
	var tip = hud.get("entity_hover_tooltip")
	_assert(ep != null and tip != null, "Setup: EntityInspectPanel & EntityHoverTooltip instantiated")
	var query = hud.call("_get_entity_inspection_query")
	_assert(query != null, "Setup: EntityInspectionQuery initialized")

	# =========================================================================
	# 1. WILDLIFE INSPECTION (ALL 6 SPECIES + FOG + NO SIDE EFFECTS)
	# =========================================================================
	var species_seen: Dictionary = {}
	for rec in wl_mgr.get_all_animals():
		var sp := str(rec["species_id"])
		if not species_seen.has(sp):
			species_seen[sp] = rec
	for req_sp in WildlifeConfig.SPECIES_ORDER:
		if not species_seen.has(req_sp):
			var c_test := Vector2i(20 + WildlifeConfig.SPECIES_ORDER.find(req_sp), 20)
			var injected: Dictionary = wl_mgr._make_animal_record("test_wl_%s" % req_sp, req_sp, WildlifeConfig.get_species_def(req_sp)["category"], c_test)
			wl_mgr.animals.append(injected)
			wl_mgr.animals_by_id[injected["id"]] = injected
			species_seen[req_sp] = injected

	for sp_id in WildlifeConfig.SPECIES_ORDER:
		var rec: Dictionary = species_seen[sp_id]
		var wc: Vector2i = rec["cell"]
		var orig_fow: int = fow.get_state(wc)
		# Fog gate check: UNEXPLORED and EXPLORED (non-visible) must not inspect wildlife
		fow.set_state(wc, FogOfWar.State.UNEXPLORED)
		_assert(not bool(query.call("build_view_model", "wildlife", str(rec["id"])).get("valid", false)), "Wildlife Fog: %s hidden in UNEXPLORED" % sp_id)
		fow.set_state(wc, FogOfWar.State.EXPLORED)
		_assert(not bool(query.call("build_view_model", "wildlife", str(rec["id"])).get("valid", false)), "Wildlife Fog: %s hidden in EXPLORED-only" % sp_id)

		# Visible check
		fow.set_state(wc, FogOfWar.State.VISIBLE)
		var state_before: int = int(rec["state"])
		var res_before: bool = wl_mgr.is_animal_reserved(str(rec["id"]))
		wv._handle_left_click(wc)
		_assert(ep.visible, "Wildlife UI: clicking %s opens EntityInspectPanel" % sp_id)
		_assert(not hud.building_inspect_panel.visible, "Wildlife UI: BuildingInspectPanel remains closed")
		var vm: Dictionary = query.call("build_view_model", "wildlife", str(rec["id"]))
		_assert(bool(vm.get("valid", false)), "Wildlife VM valid for %s" % sp_id)
		_assert(not _vm_has_text(vm, "ID:"), "Wildlife UI: no raw ID debug prefix for %s" % sp_id)
		_assert(not _vm_has_text(vm, "(Read-only)"), "Wildlife UI: no raw debug suffix for %s" % sp_id)
		if WildlifeConfig.is_huntable_species(sp_id):
			_assert(_vm_has_text(vm, "Thịt sống"), "Wildlife UI: huntable %s displays yield info" % sp_id)
		else:
			_assert(_vm_has_text(vm, "Không săn bắt"), "Wildlife UI: non-huntable %s shows clear policy" % sp_id)
		_assert(int(rec["state"]) == state_before and wl_mgr.is_animal_reserved(str(rec["id"])) == res_before, "Wildlife Read-only: zero state/reservation mutation for %s" % sp_id)
		fow.set_state(wc, orig_fow)

	# Reservation display check on deer
	var deer_rec: Dictionary = species_seen["deer"]
	fow.set_state(deer_rec["cell"], FogOfWar.State.VISIBLE)
	var prev_cit: String = str(wv.citizen_list[0].get("citizen_id")) if not wv.citizen_list.is_empty() else "cit_1"
	wl_mgr.reserve_animal(str(deer_rec["id"]), prev_cit)
	var deer_vm: Dictionary = query.call("build_view_model", "wildlife", str(deer_rec["id"]))
	_assert(_vm_has_text(deer_vm, "truy tìm"), "Wildlife Reservation: displays active hunter tracking")
	wl_mgr.release_reservation(str(deer_rec["id"]), prev_cit)

	# =========================================================================
	# 2. MONSTER & CAVE / NEST INSPECTION (3 SPECIES + BIOME STRING + FOG + TERRITORY)
	# =========================================================================
	var nests_arr: Array = m_mgr.get_all_nests()
	var sp_monsters := {}
	for m_rec in m_mgr.monsters:
		sp_monsters[str(m_rec["species_id"])] = m_rec
	var test_nest_id := str(nests_arr[0]["id"]) if not nests_arr.is_empty() else ""
	for req_m_sp in ["forest_stalker", "marsh_crawler", "stone_brute"]:
		if not sp_monsters.has(req_m_sp):
			var mc_inj := Vector2i(35 + ["forest_stalker", "marsh_crawler", "stone_brute"].find(req_m_sp), 35)
			var inj_m: Dictionary = m_mgr._create_monster_record(req_m_sp, mc_inj, test_nest_id, mc_inj)
			sp_monsters[req_m_sp] = inj_m
	m_mgr._sync_all_actors()

	for m_sp in ["forest_stalker", "marsh_crawler", "stone_brute"]:
		var m_rec: Dictionary = sp_monsters[m_sp]
		var mc: Vector2i = m_rec["cell"]
		fow.set_state(mc, FogOfWar.State.UNEXPLORED)
		_assert(not bool(query.call("build_view_model", "monster", str(m_rec["id"])).get("valid", false)), "Monster Fog: %s hidden in UNEXPLORED" % m_sp)
		fow.set_state(mc, FogOfWar.State.VISIBLE)
		var m_hp_before: float = float(m_rec["health"])
		wv._handle_left_click(mc)
		_assert(ep.visible and hud.get("inspected_entity_category") == "monster", "Monster UI: clicking %s opens EntityInspectPanel" % m_sp)
		var m_vm: Dictionary = query.call("build_view_model", "monster", str(m_rec["id"]))
		var coords_str: String = str(m_vm.get("coords_text", ""))
		_assert(not coords_str.contains("Biome: 0") and not coords_str.contains("Biome: 1") and not coords_str.contains("Biome: 2") and not coords_str.contains("Biome: 3") and not coords_str.contains("Biome: 4"), "Monster UI: human-readable biome name instead of raw enum int (%s)" % coords_str)
		_assert(_vm_has_text(m_vm, "Giáp phòng ngự") and _vm_has_text(m_vm, "Phát hiện / Truy đuổi"), "Monster UI: armor & detection/pursuit ranges shown for %s" % m_sp)
		_assert(float(m_rec["health"]) == m_hp_before, "Monster Read-only: HP unchanged")

	# Target Monster action visibility vs military selection
	var p_units_spawn: Array = tm_mgr.get_all_units()
	if p_units_spawn.size() < 2:
		var anchor_th: Vector2i = wd.buildings[0]["cell"] if not wd.buildings.is_empty() else Vector2i(32, 33)
		tm_mgr.spawn_units_at_base(2 - p_units_spawn.size(), false, anchor_th + Vector2i(4, 0))
		p_units_spawn = tm_mgr.get_all_units()
	_assert(not p_units_spawn.is_empty(), "Setup: player tactical soldier available")
	var s0 = p_units_spawn[0]

	var fs_rec: Dictionary = sp_monsters["forest_stalker"]
	fow.set_state(fs_rec["cell"], FogOfWar.State.VISIBLE)
	tm_mgr.clear_selection()
	var fs_vm_unsel: Dictionary = query.call("build_view_model", "monster", str(fs_rec["id"]))
	_assert(bool(fs_vm_unsel.get("valid", false)) and fs_vm_unsel.get("action", {}).is_empty(), "Monster UI: Target Monster hidden when 0 soldiers selected")
	tm_mgr.select_unit(s0.unit_id, false)
	var fs_vm_sel: Dictionary = query.call("build_view_model", "monster", str(fs_rec["id"]))
	_assert(bool(fs_vm_sel.get("valid", false)) and str(fs_vm_sel.get("action", {}).get("action_id", "")) == "attack_monster" and bool(fs_vm_sel.get("action", {}).get("enabled", false)), "Monster UI: Target Monster enabled when soldier selected")
	tm_mgr.clear_selection()

	# Cave / Nest Fog gating + Territory Suppression
	if not nests_arr.is_empty():
		var nd: Dictionary = nests_arr[0]
		var nid: String = str(nd["id"])
		var nc: Vector2i = nd["cell"]
		nd["discovered"] = false
		fow.set_state(nc, FogOfWar.State.UNEXPLORED)
		_assert(not bool(query.call("build_view_model", "monster_nest", nid).get("valid", false)), "Nest Fog: unexplored nest rejected")
		fow.set_state(nc, FogOfWar.State.EXPLORED)
		var nest_exp_vm: Dictionary = query.call("build_view_model", "monster_nest", nid)
		_assert(bool(nest_exp_vm.get("valid", false)) and not bool(nest_exp_vm.get("show_bar", false)), "Nest Fog: explored-not-visible hides live HP bar & timer")
		fow.set_state(nc, FogOfWar.State.VISIBLE)
		var nest_vis_vm: Dictionary = query.call("build_view_model", "monster_nest", nid)
		_assert(bool(nest_vis_vm.get("show_bar", false)) and _vm_has_text(nest_vis_vm, "Quái bảo vệ"), "Nest Fog: visible nest shows HP bar & defender count")
		if territory_mgr != null and wd != null and wd.owned_cells.size() == wd.map_width:
			var was_owned: bool = territory_mgr.is_cell_owned(nc)
			if not was_owned:
				wd.owned_cells[nc.x][nc.y] = true
				var nest_sup_vm: Dictionary = query.call("build_view_model", "monster_nest", nid)
				_assert(_vm_has_text(nest_sup_vm, "áp chế"), "Nest UI: territory-suppressed spawn status shown")
				wd.owned_cells[nc.x][nc.y] = false

	# =========================================================================
	# 3. POI INSPECTION & DISTINCT PLACEHOLDER VISUALS
	# =========================================================================
	var poi_types_found := {}
	for poi in poi_mgr.get_all_pois():
		if not poi_types_found.has(poi.type):
			poi_types_found[poi.type] = poi
	for p_type_req in ["abandoned_camp", "ancient_ruins", "forgotten_cache"]:
		_assert(poi_types_found.has(p_type_req), "POI generation includes %s" % p_type_req)
	var icon_camp_h := _tex_hash(query.call("get_placeholder_icon", "poi_abandoned_camp"))
	var icon_ruins_h := _tex_hash(query.call("get_placeholder_icon", "poi_ancient_ruins"))
	var icon_cache_h := _tex_hash(query.call("get_placeholder_icon", "poi_forgotten_cache"))
	_assert(icon_camp_h != icon_ruins_h and icon_cache_h != icon_ruins_h and icon_camp_h != icon_cache_h, "POI UI icons: camp, ruins, cache are visually distinct")
	var camp_node = wv.poi_nodes_by_id.get(poi_types_found["abandoned_camp"].id)
	var cache_node = wv.poi_nodes_by_id.get(poi_types_found["forgotten_cache"].id)
	var ruins_tex = wv.prop_textures.get("poi_ruins")
	if camp_node != null and cache_node != null:
		_assert(camp_node.get_node("Sprite2D").texture != ruins_tex, "POI Map Visual: abandoned_camp does not reuse crystal ruins texture")
		_assert(cache_node.get_node("Sprite2D").texture != ruins_tex, "POI Map Visual: forgotten_cache does not reuse crystal ruins texture")

	var test_poi = poi_types_found["abandoned_camp"]
	fow.set_state(test_poi.cell, FogOfWar.State.UNEXPLORED)
	test_poi.state = POIManager.POIState.UNDISCOVERED
	_assert(not bool(query.call("build_view_model", "poi", test_poi.id).get("valid", false)), "POI Fog: UNDISCOVERED POI blocked")
	fow.set_state(test_poi.cell, FogOfWar.State.EXPLORED)
	poi_mgr.update_discovery(fow, m_mgr, wv.nav)
	wv._handle_left_click(test_poi.cell)
	_assert(ep.visible and hud.get("inspected_entity_category") == "poi", "POI UI: clicking discovered POI opens EntityInspectPanel")
	_assert(test_poi.state != POIManager.POIState.CLAIMED, "POI Read-only: clicking/inspecting never claims rewards")

	# =========================================================================
	# 4. MILITARY UNIT INSPECTION (PLAYER + ENEMY + NON-CONFLICTING COMMANDS)
	# =========================================================================
	var order_before: int = s0.order_state
	var tgt_before: Vector2i = s0.target_cell
	var ev_click_p := InputEventMouseButton.new()
	ev_click_p.button_index = MOUSE_BUTTON_LEFT
	ev_click_p.pressed = false
	ev_click_p.set_meta("target_cell", s0.current_cell)
	wv._unhandled_input(ev_click_p)
	_assert(ep.visible and hud.get("inspected_entity_category") == "military_unit", "Military UI: single click on Player soldier opens EntityInspectPanel")
	_assert(s0.order_state == order_before and s0.target_cell == tgt_before, "Military Read-only: inspecting soldier never issues movement/attack order")
	if p_units_spawn.size() >= 2:
		var s1 = p_units_spawn[1]
		var ev_shift_p := InputEventMouseButton.new()
		ev_shift_p.button_index = MOUSE_BUTTON_LEFT
		ev_shift_p.pressed = false
		ev_shift_p.shift_pressed = true
		ev_shift_p.set_meta("target_cell", s1.current_cell)
		wv._unhandled_input(ev_shift_p)
		_assert(not ep.visible and tm_mgr.get_selected_count() >= 2, "Military UI: Shift-selecting 2nd soldier keeps squad selection and closes single-unit EntityInspectPanel")
		tm_mgr.select_unit(s0.unit_id, false)
	var mil_vm: Dictionary = query.call("build_view_model", "military_unit", "player:%s" % s0.unit_id)
	_assert(_vm_has_text(mil_vm, "Vương Quốc Người Chơi") and _vm_has_text(mil_vm, "Kiếm Sĩ"), "Military UI: player unit displays faction & unit type")
	var soldier_tex: Texture2D = query.call("get_placeholder_icon", "military_player")
	var citizen_img: Image = load("res://assets/entities/citizen.png").get_image()
	_assert(_tex_hash(soldier_tex) != str(citizen_img.get_data().hex_encode().hash()), "Military UI: uses soldier silhouette placeholder instead of citizen.png")

	# Right-click tactical Move still works seamlessly while inspected
	var move_dest: Vector2i = s0.current_cell + Vector2i(1, 0)
	if not wv.nav.is_walkable(move_dest):
		move_dest = s0.current_cell + Vector2i(0, 1)
	var ev_rc := InputEventMouseButton.new()
	ev_rc.button_index = MOUSE_BUTTON_RIGHT
	ev_rc.pressed = true
	ev_rc.set_meta("target_cell", move_dest)
	wv._unhandled_input(ev_rc)
	_assert(s0.order_state == TacticalUnit.OrderState.MOVING, "Military Control: right-click tactical Move works without conflict")
	tm_mgr.clear_all_units()
	if wv.get("player_army_mgr") != null:
		wv.player_army_mgr.sync_with_tactical_units() if wv.player_army_mgr.has_method("sync_with_tactical_units") else null

	# Enemy unit inspection & strict real-Fog enforcement (even under debug_fog_disabled)
	var enemy_list: Array = em_mgr.get_all_enemies() if em_mgr != null else []
	if not enemy_list.is_empty():
		var e0 = enemy_list[0]
		var ec: Vector2i = e0.current_cell
		fow.set_state(ec, FogOfWar.State.UNEXPLORED)
		wv.set_debug_fog_disabled(true)
		_assert(not bool(query.call("build_view_model", "military_unit", "enemy:%s" % e0.unit_id).get("valid", false)), "Enemy Military Fog: hidden under real UNEXPLORED even when Fog OFF debug enabled")
		wv.set_debug_fog_disabled(false)
		fow.set_state(ec, FogOfWar.State.VISIBLE)
		wv._handle_left_click(ec)
		_assert(ep.visible and hud.get("inspected_entity_id") == "enemy:%s" % e0.unit_id, "Enemy Military UI: clicking visible enemy opens EntityInspectPanel")

	# =========================================================================
	# 5. NATURAL RESOURCE NODE INSPECTION IN NORMAL FOG ON GAMEPLAY
	# =========================================================================
	var res_nodes_vals: Array = nrm.nodes_by_id.values()
	_assert(not res_nodes_vals.is_empty(), "Setup: natural resource nodes exist")
	var rn: Dictionary = res_nodes_vals[0]
	var rc: Vector2i = rn["cell"]
	var r_qty_before: int = int(rn["remaining_qty"])
	fow.set_state(rc, FogOfWar.State.UNEXPLORED)
	_assert(not bool(query.call("build_view_model", "natural_resource", str(rn["id"])).get("valid", false)), "Resource Fog: unexplored blocked in normal gameplay")
	fow.set_state(rc, FogOfWar.State.EXPLORED)
	wv._handle_left_click(rc)
	_assert(ep.visible and hud.get("inspected_entity_category") == "natural_resource", "Resource UI: explored node inspectable in normal Fog ON gameplay without debug_fog_disabled")
	var rn_exp_vm: Dictionary = query.call("build_view_model", "natural_resource", str(rn["id"]))
	_assert(not bool(rn_exp_vm.get("show_bar", false)), "Resource Fog: explored-not-visible hides exact live quantity")
	fow.set_state(rc, FogOfWar.State.VISIBLE)
	var rn_vis_vm: Dictionary = query.call("build_view_model", "natural_resource", str(rn["id"]))
	_assert(bool(rn_vis_vm.get("show_bar", false)) and _vm_has_text(rn_vis_vm, str(r_qty_before)), "Resource Fog: visible node shows live quantity")
	_assert(int(rn["remaining_qty"]) == r_qty_before, "Resource Read-only: quantity unchanged")

	# =========================================================================
	# 6. UNIFIED HOVER TOOLTIP & ANTI-FLICKER / HIDING
	# =========================================================================
	var b0: Dictionary = wd.buildings[0]
	var b0_cell: Vector2i = b0["cell"]
	fow.set_state(b0_cell, FogOfWar.State.VISIBLE)
	hud.call("update_world_hover", b0_cell, Vector2(400, 300), false)
	_assert(tip.visible, "Hover Tooltip: visible over explored/visible building")
	var k1: String = tip.call("get_current_entity_key")
	hud.call("update_world_hover", b0_cell + Vector2i(1, 0), Vector2(412, 306), false)
	_assert(tip.visible and tip.call("get_current_entity_key") == k1, "Hover Tooltip: stable entity_key across adjacent building footprint cells (no flicker)")
	fow.set_state(Vector2i(120, 120), FogOfWar.State.UNEXPLORED)
	hud.call("update_world_hover", Vector2i(120, 120), Vector2(500, 320), false)
	_assert(not tip.visible, "Hover Tooltip: hides immediately over unexplored Fog")
	hud.call("update_world_hover", Vector2i(-1, -1), Vector2(500, 320), false)
	_assert(not tip.visible, "Hover Tooltip: hides immediately out of bounds")

	# =========================================================================
	# 7. MUTUAL EXCLUSION, ESCAPE, STALE INVALIDATION & SAVE/LOAD CLEANUP
	# =========================================================================
	wv._handle_left_click(rc)
	_assert(ep.visible, "Isolation: EntityInspectPanel active before switching")
	wv._handle_left_click(b0_cell)
	_assert(not ep.visible and hud.building_inspect_panel.visible, "Isolation: selecting Building closes EntityInspectPanel")

	wv._handle_left_click(rc)
	_assert(ep.visible, "Escape Test: EntityInspectPanel open")
	var esc_ev := InputEventKey.new()
	esc_ev.keycode = KEY_ESCAPE
	esc_ev.pressed = true
	hud._unhandled_input(esc_ev)
	_assert(not ep.visible and not hud.pause_menu_dialog.visible, "Escape Test: Escape closes EntityInspectPanel without opening PauseMenu")

	# Stale/dead entity invalidation closes panel cleanly
	fow.set_state(fs_rec["cell"], FogOfWar.State.VISIBLE)
	hud.call("show_entity_inspector", "monster", str(fs_rec["id"]))
	_assert(ep.visible, "Stale Test: open on living monster")
	fs_rec["state"] = MonsterConfigScript.MonsterAIState.DEAD
	fs_rec["health"] = 0.0
	hud.call("refresh_entity_inspector")
	_assert(not ep.visible and hud.get("inspected_entity_id") == "", "Stale Test: dead monster auto-closes EntityInspectPanel cleanly")

	# Save/Load closes EntityInspectPanel without dangling state
	wv._handle_left_click(rc)
	_assert(ep.visible, "Save/Load Test: panel open before save")
	var save_path := "user://test_m61_inspect_ui.json"
	var s_res := SaveManager.save_to_file(wv, save_path)
	_assert(bool(s_res.get("success", false)), "Save/Load Test: save succeeded")
	var l_res := SaveManager.load_from_file(save_path)
	if bool(s_res.get("success", false)) and bool(l_res.get("success", false)):
		var a_res := SaveManager.apply_loaded_state_to_world(wv, l_res["data"])
		_assert(bool(a_res.get("success", false)) and not ep.visible and not tip.visible, "Save/Load Test: apply_loaded_state closes inspectors & tooltip cleanly")
	else:
		_assert(false, "Save/Load Test: load skipped because save failed")
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	wv.queue_free()
	await process_frame
	await process_frame

	print("[test_entity_inspection_ui] Passed: %d | Failed: %d" % [_passed, _failures.size()])
	for f in _failures:
		printerr("  FAIL -> " + f)
	quit(0 if _failures.is_empty() else 1)
