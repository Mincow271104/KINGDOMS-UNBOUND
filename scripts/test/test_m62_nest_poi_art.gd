extends SceneTree

const WorldViewScene := preload("res://scenes/world/world_view.tscn")
const MonsterConfigScript := preload("res://scripts/world/monster_config.gd")
const EntityVisualRegistryScript := preload("res://scripts/world/entity_visual_registry.gd")

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

func _run() -> void:
	print("[test_m62_nest_poi_art] Starting M6-2 Nest & POI Pixel-Art Suite...")

	# =========================================================================
	# 1. TEXTURE REGISTRY, ASSETS, DIMENSIONS, CACHING & FALLBACK
	# =========================================================================
	var nest_species := ["stone_brute", "forest_stalker", "marsh_crawler"]
	var nest_active_hashes := {}
	var nest_destroyed_hashes := {}
	for sp in nest_species:
		var a_path := EntityVisualRegistryScript.get_nest_texture_path(sp, false)
		var d_path := EntityVisualRegistryScript.get_nest_texture_path(sp, true)
		_assert(ResourceLoader.exists(a_path), "Asset exists: %s" % a_path)
		_assert(ResourceLoader.exists(d_path), "Asset exists: %s" % d_path)
		var a_tex: Texture2D = EntityVisualRegistryScript.get_nest_texture(sp, false)
		var d_tex: Texture2D = EntityVisualRegistryScript.get_nest_texture(sp, true)
		_assert(a_tex != null and a_tex.get_width() == 48 and a_tex.get_height() == 40, "Nest active %s size == 48x40" % sp)
		_assert(d_tex != null and d_tex.get_width() == 48 and d_tex.get_height() == 40, "Nest destroyed %s size == 48x40" % sp)
		_assert(a_tex != d_tex, "Nest %s active != destroyed texture" % sp)
		_assert(_tex_hash(a_tex) != _tex_hash(d_tex), "Nest %s active pixels != destroyed pixels" % sp)
		# Caching check: second lookup returns identical instance
		_assert(EntityVisualRegistryScript.get_nest_texture(sp, false) == a_tex, "Registry cache returns identical Texture2D for active %s" % sp)
		_assert(EntityVisualRegistryScript.get_nest_texture(sp, true) == d_tex, "Registry cache returns identical Texture2D for destroyed %s" % sp)
		nest_active_hashes[sp] = _tex_hash(a_tex)
		nest_destroyed_hashes[sp] = _tex_hash(d_tex)

	_assert(nest_active_hashes["stone_brute"] != nest_active_hashes["forest_stalker"] and nest_active_hashes["forest_stalker"] != nest_active_hashes["marsh_crawler"] and nest_active_hashes["stone_brute"] != nest_active_hashes["marsh_crawler"], "All 3 nest active visuals have distinct silhouettes/pixels")

	var old_ruins_tex: Texture2D = load("res://assets/props/prop_poi_ruins.png")
	var old_ruins_hash := _tex_hash(old_ruins_tex)
	var poi_types := ["abandoned_camp", "ancient_ruins", "forgotten_cache"]
	var expected_sizes := {
		"abandoned_camp": Vector2i(40, 36),
		"ancient_ruins": Vector2i(40, 36),
		"forgotten_cache": Vector2i(32, 32),
	}
	var poi_hashes := {}
	for pt in poi_types:
		var p_path := EntityVisualRegistryScript.get_poi_texture_path(pt, false)
		var c_path := EntityVisualRegistryScript.get_poi_texture_path(pt, true)
		_assert(ResourceLoader.exists(p_path), "Asset exists: %s" % p_path)
		_assert(ResourceLoader.exists(c_path), "Asset exists: %s" % c_path)
		var p_tex: Texture2D = EntityVisualRegistryScript.get_poi_texture(pt, false)
		var c_tex: Texture2D = EntityVisualRegistryScript.get_poi_texture(pt, true)
		var sz: Vector2i = expected_sizes[pt]
		_assert(p_tex != null and p_tex.get_width() == sz.x and p_tex.get_height() == sz.y, "POI intact %s size == %dx%d" % [pt, sz.x, sz.y])
		_assert(c_tex != null and c_tex.get_width() == sz.x and c_tex.get_height() == sz.y, "POI claimed %s size == %dx%d" % [pt, sz.x, sz.y])
		_assert(_tex_hash(p_tex) != _tex_hash(c_tex), "POI %s intact pixels != claimed pixels" % pt)
		_assert(_tex_hash(p_tex) != old_ruins_hash, "POI %s replaces legacy prop_poi_ruins.png" % pt)
		_assert(EntityVisualRegistryScript.get_poi_texture(pt, false) == p_tex, "Registry cache returns identical Texture2D for intact %s" % pt)
		poi_hashes[pt] = _tex_hash(p_tex)

	_assert(poi_hashes["abandoned_camp"] != poi_hashes["ancient_ruins"] and poi_hashes["ancient_ruins"] != poi_hashes["forgotten_cache"] and poi_hashes["abandoned_camp"] != poi_hashes["forgotten_cache"], "All 3 POI intact visuals are pixel-distinct")

	var fb_tex: Texture2D = EntityVisualRegistryScript.load_texture_cached("res://assets/entities/nonexistent_m62_test.png", "fallback_stone_brute")
	_assert(fb_tex != null and fb_tex is ImageTexture, "Missing texture path gracefully yields cached ImageTexture fallback")
	_assert(EntityVisualRegistryScript.load_texture_cached("res://assets/entities/nonexistent_m62_test.png", "fallback_stone_brute") == fb_tex, "Fallback texture is cached identically")

	# =========================================================================
	# 2. WORLDVIEW LIVE INTEGRATION: NESTS, POIS, UI PORTRAITS & TOOLTIPS
	# =========================================================================
	var wv := WorldViewScene.instantiate()
	wv.set("skip_intro_for_test", true)
	root.add_child(wv)
	await create_timer(0.25).timeout

	var hud = wv.get("hud")
	var fow: FogOfWar = wv.get("fog_of_war")
	var m_mgr = wv.get("monster_mgr")
	var poi_mgr = wv.get("poi_mgr")
	var ep = hud.get("entity_inspect_panel")
	var tip = hud.get("entity_hover_tooltip")
	var query = hud.call("_get_entity_inspection_query")

	var ep_icon: TextureRect = ep.get("_icon_rect")
	var tip_icon: TextureRect = tip.get("_icon_rect")
	_assert(ep_icon != null and ep_icon.expand_mode == TextureRect.EXPAND_IGNORE_SIZE and ep_icon.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "EntityInspectPanel icon preserves aspect without distortion")
	_assert(ep_icon != null and ep_icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "EntityInspectPanel icon uses nearest-neighbor filter")
	_assert(tip_icon != null and tip_icon.expand_mode == TextureRect.EXPAND_IGNORE_SIZE and tip_icon.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "EntityHoverTooltip icon preserves aspect without distortion")
	_assert(tip_icon != null and tip_icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "EntityHoverTooltip icon uses nearest-neighbor filter")

	# Ensure at least one nest per species exists in world
	var nests_by_species: Dictionary = {}
	for nid in m_mgr.nests.keys():
		var nd: Dictionary = m_mgr.nests[nid]
		var sp := str(nd.get("species_id", ""))
		if not nests_by_species.has(sp):
			nests_by_species[sp] = nd

	for idx in range(nest_species.size()):
		var sp: String = nest_species[idx]
		if not nests_by_species.has(sp):
			var c_inj := Vector2i(22 + idx * 4, 22)
			var inj_id := "test_nest_%s" % sp
			var n_rec := {
				"id": inj_id,
				"species_id": sp,
				"name": str(MonsterConfigScript.get_species_def(sp).get("nest_name", sp)),
				"cell": c_inj,
				"shared_anchor_cell": c_inj,
				"needs_shared_anchor_init": false,
				"health": MonsterConfigScript.NEST_MAX_HEALTH,
				"max_health": MonsterConfigScript.NEST_MAX_HEALTH,
				"is_destroyed": false,
				"spawn_timer_hours": 0.0,
				"discovered": true,
			}
			m_mgr.nests[inj_id] = n_rec
			m_mgr._sync_all_actors()
			nests_by_species[sp] = n_rec

	# Test each nest actor: Sprite2D, filter, offset, z_index, active state, UI match, damage flash, destruction transition
	for sp in nest_species:
		var nd: Dictionary = nests_by_species[sp]
		var nid := str(nd["id"])
		var actor: MonsterNestActor = m_mgr.nest_actors.get(nid) as MonsterNestActor
		_assert(actor != null and is_instance_valid(actor), "Nest %s has live MonsterNestActor" % sp)
		var spr: Sprite2D = actor.get_node_or_null("Sprite2D") as Sprite2D
		_assert(spr != null, "Nest %s uses persistent Sprite2D child" % sp)
		_assert(spr.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Nest %s Sprite2D uses TEXTURE_FILTER_NEAREST" % sp)
		_assert(actor.z_index == IsoMath.world_y_to_z_index(actor.position.y), "Nest %s z_index synced with IsoMath Y-sort" % sp)
		var expected_active := EntityVisualRegistryScript.get_nest_texture(sp, false)
		var expected_destroyed := EntityVisualRegistryScript.get_nest_texture(sp, true)
		_assert(spr.texture == expected_active, "Active nest %s renders active texture (not destroyed)" % sp)
		_assert(spr.texture != expected_destroyed, "Active nest %s never shows destroyed artwork" % sp)
		_assert(spr.offset == EntityVisualRegistryScript.get_nest_sprite_offset(expected_active), "Active nest %s offset aligned" % sp)

		# Fog gate check: UNEXPLORED fails closed in inspector & hover tooltip
		var nc: Vector2i = nd["cell"]
		fow.set_state(nc, FogOfWar.State.UNEXPLORED)
		_assert(not bool(query.call("build_view_model", "monster_nest", nid).get("valid", false)), "Nest %s hidden from inspector in UNEXPLORED Fog" % sp)
		hud.call("update_world_hover", nc, Vector2(300, 300), false)
		_assert(not tip.visible, "Nest %s hover tooltip hidden in UNEXPLORED Fog" % sp)

		# Visible inspection & hover portrait match world sprite
		fow.set_state(nc, FogOfWar.State.VISIBLE)
		hud.call("show_entity_inspector", "monster_nest", nid)
		_assert(ep.visible and ep_icon.texture == spr.texture, "Nest %s active EntityInspectPanel portrait matches Sprite2D" % sp)
		hud.call("update_world_hover", nc, Vector2(300, 300), false)
		_assert(tip.visible and tip_icon.texture == spr.texture, "Nest %s active EntityHoverTooltip icon matches Sprite2D" % sp)

		# Non-lethal hit triggers damage flash while keeping active sprite & HP intact
		var hp_before := actor.health
		actor.take_damage(15.0, "test_knight")
		_assert(is_equal_approx(actor.health, hp_before - 15.0), "Nest %s take_damage updates HP properly" % sp)
		_assert(actor.damage_flash_timer > 0.0 and spr.modulate != Color.WHITE, "Nest %s shows red/white damage flash modulate" % sp)
		_assert(actor.is_alive and spr.texture == expected_active, "Nest %s retains active texture while alive" % sp)

	# Destroy Stone Brute nest via gameplay kill and verify ruined sprite + inspector portrait switch
	var target_nd: Dictionary = nests_by_species["stone_brute"]
	var target_nid := str(target_nd["id"])
	var target_actor: MonsterNestActor = m_mgr.nest_actors.get(target_nid) as MonsterNestActor
	target_actor.take_damage(target_actor.health + 50.0, "test_knight")
	_assert(not target_actor.is_alive and bool(target_nd.get("is_destroyed", false)), "Destroyed Stone Brute nest updates simulation flags")
	var target_spr: Sprite2D = target_actor.get_node("Sprite2D") as Sprite2D
	_assert(target_spr.texture == EntityVisualRegistryScript.get_nest_texture("stone_brute", true), "Destroyed Stone Brute nest switches Sprite2D to destroyed asset")
	hud.call("show_entity_inspector", "monster_nest", target_nid)
	_assert(ep.visible and ep_icon.texture == target_spr.texture, "Destroyed nest EntityInspectPanel displays destroyed artwork")
	hud.call("update_world_hover", target_nd["cell"], Vector2(320, 320), false)
	_assert(tip.visible and tip_icon.texture == target_spr.texture, "Destroyed nest EntityHoverTooltip displays destroyed artwork")

	# Ensure all 3 POI types exist, check UNDISCOVERED visibility, DISCOVERED/CLEARED intact sprite, CLAIMED transition
	var pois_by_type: Dictionary = {}
	for poi in poi_mgr.get_all_pois():
		if not pois_by_type.has(poi.type):
			pois_by_type[poi.type] = poi
	for idx in range(poi_types.size()):
		var pt: String = poi_types[idx]
		if not pois_by_type.has(pt):
			var pc := Vector2i(30 + idx * 4, 30)
			var p_new := POIManager.POIData.new()
			p_new.id = "test_poi_%s" % pt
			p_new.type = pt
			p_new.name = "Test %s" % pt
			p_new.cell = pc
			p_new.rewards = {"gold": 50}
			poi_mgr._pois[p_new.id] = p_new
			wv.call("_spawn_single_poi_node", p_new)
			pois_by_type[pt] = p_new

	var pa_mgr = wv.get("player_army_mgr")
	var tact = wv.get("tactical_military_mgr")
	if pa_mgr != null and tact != null:
		pa_mgr.set("soldier_count", 2)
		tact.sync_with_player_army()
	var units: Array = tact.get_all_units() if tact != null else []
	var claim_unit: Node2D = units[0] if not units.is_empty() else null

	for pt in poi_types:
		var poi: POIManager.POIData = pois_by_type[pt]
		var p_node: Node2D = wv.get("poi_nodes_by_id").get(poi.id) as Node2D
		_assert(p_node != null and is_instance_valid(p_node), "POI %s has live world Node2D" % pt)
		var p_spr: Sprite2D = p_node.get_node_or_null("Sprite2D") as Sprite2D
		_assert(p_spr != null and p_spr.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "POI %s Sprite2D uses TEXTURE_FILTER_NEAREST" % pt)
		_assert(p_node.z_index == IsoMath.world_y_to_z_index(p_node.position.y), "POI %s z_index synced with IsoMath Y-sort" % pt)

		# Fog/discovery hidden state check
		poi.state = POIManager.POIState.UNDISCOVERED
		wv.call("refresh_poi_visibility")
		_assert(not p_node.visible, "POI %s is hidden in world while UNDISCOVERED" % pt)
		fow.set_state(poi.cell, FogOfWar.State.UNEXPLORED)
		_assert(not bool(query.call("build_view_model", "poi", poi.id).get("valid", false)), "POI %s hidden from inspector while UNDISCOVERED" % pt)

		# Discovered / Cleared (unguarded intact) -> intact sprite
		fow.set_state(poi.cell, FogOfWar.State.VISIBLE)
		poi.state = POIManager.POIState.DISCOVERED
		poi_mgr.poi_revealed.emit(poi)
		var intact_tex := EntityVisualRegistryScript.get_poi_texture(pt, false)
		var claimed_tex := EntityVisualRegistryScript.get_poi_texture(pt, true)
		_assert(p_node.visible and p_spr.texture == intact_tex, "POI %s DISCOVERED shows intact asset" % pt)
		poi.state = POIManager.POIState.CLEARED
		poi_mgr.poi_state_changed.emit(poi)
		_assert(p_spr.texture == intact_tex, "POI %s CLEARED (unlooted) keeps intact asset" % pt)

		hud.call("show_entity_inspector", "poi", poi.id)
		_assert(ep.visible and ep_icon.texture == intact_tex, "POI %s intact inspector portrait matches world Sprite2D" % pt)
		hud.call("update_world_hover", poi.cell, Vector2(360, 360), false)
		_assert(tip.visible and tip_icon.texture == intact_tex, "POI %s intact hover tooltip matches world Sprite2D" % pt)

		# Clear any guard monsters within guard radius & place player military unit next to POI to claim cleanly
		if claim_unit != null:
			claim_unit.set("current_cell", poi.cell)
		for m in m_mgr.monsters:
			if IsoMath.grid_distance(m["cell"], poi.cell) <= 8:
				m["state"] = MonsterConfigScript.MonsterAIState.DEAD
				m["health"] = 0.0
		poi.rewards = {"gold": 25}
		poi.pending_rewards.clear()
		poi.reward_claim_initiated = false
		var gold_before := int(wv.call("_get_resource_mgr").get_resource("gold"))
		var claim_res: Dictionary = wv.call("claim_poi_with_military", poi.id)
		if claim_unit != null:
			claim_unit.set("current_cell", wv.get("world_data").center_spawn)
		_assert(bool(claim_res.get("success", false)), "POI %s claim_poi_with_military succeeded" % pt)
		_assert(poi.state == POIManager.POIState.CLAIMED, "POI %s transitioned to POIState.CLAIMED" % pt)
		_assert(int(wv.call("_get_resource_mgr").get_resource("gold")) == gold_before + 25, "POI %s reward behavior preserved (+25 gold)" % pt)
		_assert(p_spr.texture == claimed_tex and p_spr.texture != intact_tex, "POI %s CLAIMED switches world Sprite2D to claimed asset" % pt)
		hud.call("show_entity_inspector", "poi", poi.id)
		_assert(ep.visible and ep_icon.texture == claimed_tex, "POI %s claimed inspector portrait matches claimed Sprite2D" % pt)
		hud.set("_hover_refresh_timer", 0.35)
		hud.call("update_world_hover", poi.cell, Vector2(360, 360), false)
		_assert(tip.visible and tip_icon.texture == claimed_tex, "POI %s claimed hover tooltip matches claimed Sprite2D" % pt)

	# Verify UI query is strictly read-only on inspected/hovered entities
	var test_camp: POIManager.POIData = pois_by_type["abandoned_camp"]
	var camp_state_before := test_camp.state
	query.call("build_view_model", "poi", test_camp.id)
	query.call("find_hover_entity_summary", test_camp.cell)
	_assert(test_camp.state == camp_state_before, "Inspect/Hover query does not mutate POI state")

	# =========================================================================
	# 3. SAVE / LOAD CONSISTENCY (NEST DESTROYED & POI CLAIMED PRESERVED)
	# =========================================================================
	var claimed_poi: POIManager.POIData = pois_by_type["abandoned_camp"]
	var claimed_poi_id := claimed_poi.id
	var save_path := "user://test_m62_art_save.json"
	var s_res := SaveManager.save_to_file(wv, save_path)
	_assert(bool(s_res.get("success", false)), "SaveManager.save_to_file succeeded without schema break")
	var l_res := SaveManager.load_from_file(save_path)
	_assert(bool(l_res.get("success", false)), "SaveManager.load_from_file succeeded")
	if bool(s_res.get("success", false)) and bool(l_res.get("success", false)):
		# Flip visuals temporarily before restore to prove load actually re-syncs from canonical state
		target_actor.is_alive = true
		target_actor._sync_sprite_visual()
		claimed_poi.state = POIManager.POIState.DISCOVERED
		wv.call("_update_poi_node_visual", claimed_poi)

		var a_res := SaveManager.apply_loaded_state_to_world(wv, l_res["data"])
		_assert(bool(a_res.get("success", false)), "SaveManager.apply_loaded_state_to_world succeeded")
		var restored_actor: MonsterNestActor = m_mgr.nest_actors.get(target_nid) as MonsterNestActor
		_assert(restored_actor != null and not restored_actor.is_alive, "Save/Load restored destroyed nest state")
		_assert(restored_actor != null and restored_actor.get_node("Sprite2D").texture == EntityVisualRegistryScript.get_nest_texture("stone_brute", true), "Save/Load restored destroyed nest Sprite2D asset")
		var restored_poi: POIManager.POIData = poi_mgr.get_poi(claimed_poi_id)
		var restored_pnode: Node2D = wv.get("poi_nodes_by_id").get(claimed_poi_id) as Node2D
		_assert(restored_poi != null and restored_poi.state == POIManager.POIState.CLAIMED, "Save/Load restored claimed POI state")
		_assert(restored_pnode != null and restored_pnode.get_node("Sprite2D").texture == EntityVisualRegistryScript.get_poi_texture("abandoned_camp", true), "Save/Load restored claimed POI Sprite2D asset")

	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	wv.queue_free()
	await process_frame
	await process_frame

	print("[test_m62_nest_poi_art] Passed: %d | Failed: %d" % [_passed, _failures.size()])
	for f in _failures:
		printerr("  FAIL -> " + f)
	quit(0 if _failures.is_empty() else 1)
