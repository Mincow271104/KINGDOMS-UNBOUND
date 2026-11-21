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

func _frame_is_nonempty(tex: Texture2D, col: int, row: int, fw: int, fh: int) -> bool:
	if tex == null:
		return false
	var img: Image = tex.get_image()
	if img == null:
		return false
	var x0 := col * fw
	var y0 := row * fh
	for y in range(y0, y0 + fh):
		for x in range(x0, x0 + fw):
			if img.get_pixel(x, y).a > 0.1:
				return true
	return false

func _run() -> void:
	print("[test_monster_visual_animation] Starting M6-3 Monster Visual & Animation Suite...")

	# =========================================================================
	# 1. SPRITE SHEET LOADING, DIMENSIONS, FRAME CONTENT & MISSING FALLBACK
	# =========================================================================
	var expected_sheets := {
		"forest_stalker": Vector2i(32, 32),
		"marsh_crawler": Vector2i(32, 28),
		"stone_brute": Vector2i(36, 40),
	}
	var species_hashes := {}
	for sp in expected_sheets.keys():
		var fsz: Vector2i = expected_sheets[sp]
		var path := EntityVisualRegistryScript.get_monster_sheet_path(sp)
		_assert(ResourceLoader.exists(path), "1. Monster sheet asset exists: %s" % path)
		var tex: Texture2D = EntityVisualRegistryScript.get_monster_sheet_texture(sp)
		_assert(tex != null and tex.get_width() == fsz.x * 6 and tex.get_height() == fsz.y * 4, "1. Monster sheet %s exact size %dx%d (6x4 grid of %dx%d)" % [sp, fsz.x * 6, fsz.y * 4, fsz.x, fsz.y])
		_assert(EntityVisualRegistryScript.get_monster_sheet_texture(sp) == tex, "1. Registry returns cached Texture2D instance for %s" % sp)
		species_hashes[sp] = tex.get_image().get_data().hex_encode().hash()

		var lay := EntityVisualRegistryScript.get_monster_sheet_layout(sp)
		for col in range(int(lay["idle_frames"])):
			_assert(_frame_is_nonempty(tex, col, 0, fsz.x, fsz.y), "1. %s idle frame %d non-empty" % [sp, col])
		for col in range(int(lay["roam_frames"])):
			_assert(_frame_is_nonempty(tex, col, 1, fsz.x, fsz.y), "1. %s roam frame %d non-empty" % [sp, col])
		for col in range(int(lay["chase_frames"])):
			_assert(_frame_is_nonempty(tex, col, 2, fsz.x, fsz.y), "1. %s chase frame %d non-empty" % [sp, col])
		for col in range(int(lay["attack_frames"])):
			_assert(_frame_is_nonempty(tex, col, 3, fsz.x, fsz.y), "1. %s attack frame %d non-empty" % [sp, col])

		var portrait: Texture2D = EntityVisualRegistryScript.get_monster_portrait_texture(sp)
		_assert(portrait != null and portrait.get_width() == fsz.x and portrait.get_height() == fsz.y, "1. Portrait AtlasTexture matches frame size %dx%d for %s" % [fsz.x, fsz.y, sp])

	_assert(species_hashes["forest_stalker"] != species_hashes["marsh_crawler"] and species_hashes["marsh_crawler"] != species_hashes["stone_brute"] and species_hashes["forest_stalker"] != species_hashes["stone_brute"], "1. All 3 species sprite sheets are distinct artwork")

	# 2. Missing texture fallback
	var fb_tex: Texture2D = EntityVisualRegistryScript.load_texture_cached("res://assets/entities/monsters/missing_m63_test.png", "monster_sheet:stone_brute")
	_assert(fb_tex != null and fb_tex is ImageTexture, "2. Missing monster sheet falls back cleanly to non-null ImageTexture")
	_assert(EntityVisualRegistryScript.load_texture_cached("res://assets/entities/monsters/missing_m63_test.png", "monster_sheet:stone_brute") == fb_tex, "2. Missing monster fallback texture is cached cleanly")

	# =========================================================================
	# 2. WORLDVIEW LIVE SIMULATION + STATE-DRIVEN ANIMATION CHECKS (3..23)
	# =========================================================================
	var wv := WorldViewScene.instantiate()
	wv.set("skip_intro_for_test", true)
	root.add_child(wv)
	await create_timer(0.25).timeout

	var fow: FogOfWar = wv.get("fog_of_war")
	var wd = wv.get("world_data")
	var nav: GridNavigation = wv.get("nav")
	var m_mgr = wv.get("monster_mgr")
	var poi_mgr = wv.get("poi_mgr")
	var tm_mgr = wv.get("tactical_military_mgr")
	var pa_mgr = wv.get("player_army_mgr")
	var territory_mgr = wv.get("territory_mgr")
	var hud = wv.get("hud")

	_assert(MonsterConfigScript.GLOBAL_MONSTER_CAP == 24, "20. Global monster cap remains strictly 24")
	_assert(MonsterConfigScript.MAX_NON_COMBAT_ASTAR_PER_FRAME == 2, "21. Non-combat A* budget remains strictly 2 per frame")

	# Ensure at least 1 monster of each species exists on walkable visible terrain
	var stage_center: Vector2i = wd.center_spawn + Vector2i(0, 12)
	var by_sp := {}
	for m in m_mgr.monsters:
		by_sp[str(m["species_id"])] = m
	var idx := 0
	for sp in ["forest_stalker", "marsh_crawler", "stone_brute"]:
		if not by_sp.has(sp):
			var c_inj := stage_center + Vector2i(idx * 4, 0)
			if IsoMath.is_in_bounds(c_inj):
				var inj: Dictionary = m_mgr._create_monster_record(sp, c_inj, "", c_inj)
				by_sp[sp] = inj
		idx += 1
	m_mgr._sync_all_actors()

	# Spawn tactical unit first (before manual Fog reveals, since roster sync recomputes observers)
	pa_mgr.set("soldier_count", 1)
	tm_mgr.sync_with_player_army()
	var u0 = tm_mgr.get_all_units()[0]

	# Reveal generous radius around test monsters so roaming steps stay visible unless intentionally tested under Fog
	for sp in ["forest_stalker", "marsh_crawler", "stone_brute"]:
		var m_rec: Dictionary = by_sp[sp]
		fow.reveal_circle(m_rec["cell"], 4)
	m_mgr.refresh_visibility(fow, false)

	var fs_rec: Dictionary = by_sp["forest_stalker"]
	var fs_id := str(fs_rec["id"])
	var fs_actor: MonsterActor = m_mgr.get_monster_actor(fs_id)
	var fs_spr: Sprite2D = fs_actor.get_node_or_null("Sprite2D") as Sprite2D
	_assert(fs_actor != null and fs_spr != null, "Setup: Forest Stalker actor has persistent Sprite2D")
	_assert(fs_spr.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "16. Sprite2D uses TEXTURE_FILTER_NEAREST")
	_assert(not fs_spr.centered and fs_spr.position == Vector2.ZERO, "17. Sprite2D centered=false and local position=(0,0)")

	# 3-7: Canonical AI state -> clip & row mapping + state transitions
	fs_rec["state"] = MonsterConfigScript.MonsterAIState.IDLE
	fs_rec["cached_path"] = [] as Array[Vector2i]
	fs_rec["state_timer"] = 5.0
	m_mgr.update_simulation(0.1, 1.0, wd, nav, null, territory_mgr, fow, false)
	_assert(fs_actor.active_anim_clip == "idle" and fs_actor.active_anim_row == 0 and fs_spr.frame < 4, "3. IDLE selects idle clip (row 0, col < 4)")

	fs_rec["state"] = MonsterConfigScript.MonsterAIState.ROAMING
	fs_rec["step_accumulator"] = 0.0
	var p_roam: Array[Vector2i] = [fs_rec["cell"], fs_rec["cell"]]
	fs_rec["cached_path"] = p_roam
	m_mgr.update_simulation(0.1, 1.0, wd, nav, null, territory_mgr, fow, false)
	_assert(fs_actor.active_anim_clip == "roam" and fs_actor.active_anim_row == 1, "4. ROAMING selects walk/roam clip (row 1) [state=%s clip=%s vis=%s path=%s]" % [str(fs_rec["state"]), fs_actor.active_anim_clip, str(fs_actor.visible), str(fs_rec["cached_path"])])

	fs_rec["state"] = MonsterConfigScript.MonsterAIState.RETURNING
	fs_rec["step_accumulator"] = 0.0
	var p_ret: Array[Vector2i] = [fs_rec["cell"], fs_rec["cell"]]
	fs_rec["cached_path"] = p_ret
	m_mgr.update_simulation(0.1, 1.0, wd, nav, null, territory_mgr, fow, false)
	_assert(fs_actor.active_anim_clip == "return" and fs_actor.active_anim_row == 1, "7. RETURNING selects movement clip (row 1) [state=%s clip=%s vis=%s]" % [str(fs_rec["state"]), fs_actor.active_anim_clip, str(fs_actor.visible)])

	# 5 + anti-false-attack: CHASING target 2 cells away with positive cooldown MUST play chase (NOT attack!)
	var fs_cell_c: Vector2i = fs_rec["cell"]
	u0.current_cell = fs_cell_c + Vector2i(2, 0)
	fow.reveal_circle(u0.current_cell, 3)
	m_mgr.refresh_visibility(fow, false)
	fs_rec["target_unit_id"] = u0.unit_id
	fs_rec["state"] = MonsterConfigScript.MonsterAIState.CHASING
	fs_rec["attack_cooldown_remaining"] = 0.85
	fs_rec["cached_path"] = [fs_cell_c]
	m_mgr.update_simulation(0.1, 1.0, wd, nav, tm_mgr, territory_mgr, fow, false)
	_assert(fs_actor.active_anim_clip == "chase" and fs_actor.active_anim_row == 2, "5. CHASING selects chase clip (row 2) even when attack_cooldown_remaining > 0")

	# 6 & 13: Actual MonsterManager ATTACKING transition with adjacent TacticalUnit + read-only safety
	var fs_cell: Vector2i = fs_rec["cell"]
	var u0_cell := fs_cell + Vector2i(1, 0)
	u0.current_cell = u0_cell
	fow.reveal_circle(fs_cell, 3)
	m_mgr.refresh_visibility(fow, false)
	fs_rec["target_unit_id"] = u0.unit_id
	fs_rec["attack_cooldown_remaining"] = 0.0
	fs_rec["state"] = MonsterConfigScript.MonsterAIState.CHASING
	var hp_u0_before := float(u0.health)

	# Calling actor sync_visual directly for ATTACKING must NEVER deal damage to unit
	fs_actor.sync_visual(fs_cell, fs_cell, 1.0, MonsterConfigScript.MonsterAIState.ATTACKING, false, 0.0, 0.5)
	_assert(fs_actor.active_anim_clip == "attack" and fs_actor.active_anim_row == 3, "6. ATTACKING selects attack clip (row 3)")
	_assert(is_equal_approx(float(u0.health), hp_u0_before), "13. Attack animation never mutates or creates canonical damage")

	# Reset actor to IDLE before real MonsterManager combat tick enters ATTACKING
	fs_actor.sync_visual(fs_cell, fs_cell, 1.0, MonsterConfigScript.MonsterAIState.IDLE, false, 0.0, m_mgr._anim_time)
	fs_rec["state"] = MonsterConfigScript.MonsterAIState.CHASING
	fs_rec["attack_cooldown_remaining"] = 0.0
	m_mgr.update_simulation(0.05, 1.0, wd, nav, tm_mgr, territory_mgr, fow, false)
	_assert(int(fs_rec["state"]) == MonsterConfigScript.MonsterAIState.ATTACKING, "6. Canonical MonsterManager transitioned to ATTACKING")
	_assert(fs_actor.active_anim_clip == "attack" and fs_actor.active_anim_row == 3 and fs_actor.active_frame_col == 0, "9. State transition into ATTACKING resets to frame col 0")
	_assert(float(u0.health) < hp_u0_before, "Canonical simulation dealt damage on attack tick")

	# Step animation within ATTACKING clip without adding extra cooldown blows
	var u0_hp_after_hit := float(u0.health)
	m_mgr.update_simulation(0.45, 1.0, wd, nav, tm_mgr, territory_mgr, fow, false)
	_assert(fs_actor.active_anim_clip == "attack" and fs_actor.active_frame_col >= 1, "9. ATTACKING animation advances through lunge/strike frames")
	_assert(is_equal_approx(float(u0.health), u0_hp_after_hit), "13. Advancing attack clip does not create extra damage before cooldown expires")

	# Clean up combat target before timing checks
	fs_rec["target_unit_id"] = ""
	u0.current_cell = wd.center_spawn
	fs_rec["state"] = MonsterConfigScript.MonsterAIState.ROAMING
	fs_rec["cached_path"] = [] as Array[Vector2i]

	# 10 & 11: Pause freezes animation, 2x/3x speed scales animation rate proportionally
	var anim_before_pause := float(m_mgr._anim_time)
	var col_before_pause := fs_actor.active_frame_col
	m_mgr.update_simulation(0.5, 0.0, wd, nav, null, territory_mgr, fow, false)
	_assert(is_equal_approx(float(m_mgr._anim_time), anim_before_pause) and fs_actor.active_frame_col == col_before_pause, "10. Pause (speed_mult=0) freezes animation time & frame")

	var t_1x_start := float(m_mgr._anim_time)
	m_mgr.update_simulation(0.1, 1.0, wd, nav, null, territory_mgr, fow, false)
	var d1 := float(m_mgr._anim_time) - t_1x_start

	var t_2x_start := float(m_mgr._anim_time)
	m_mgr.update_simulation(0.1, 2.0, wd, nav, null, territory_mgr, fow, false)
	var d2 := float(m_mgr._anim_time) - t_2x_start

	var t_3x_start := float(m_mgr._anim_time)
	m_mgr.update_simulation(0.1, 3.0, wd, nav, null, territory_mgr, fow, false)
	var d3 := float(m_mgr._anim_time) - t_3x_start

	_assert(is_equal_approx(d2, d1 * 2.0) and is_equal_approx(d3, d1 * 3.0), "11. Animation time advances 2x and 3x faster under speed_mult=2/3")

	# 12: Movement speed cadence comparison across states & species
	var fs_lay := EntityVisualRegistryScript.get_monster_sheet_layout("forest_stalker")
	var mc_lay := EntityVisualRegistryScript.get_monster_sheet_layout("marsh_crawler")
	var sb_lay := EntityVisualRegistryScript.get_monster_sheet_layout("stone_brute")
	_assert(float(fs_lay["chase_fps"]) > float(fs_lay["roam_fps"]), "12. Forest Stalker CHASING cadence exceeds ROAMING cadence")
	_assert(float(fs_lay["chase_fps"]) > float(mc_lay["chase_fps"]) and float(mc_lay["roam_fps"]) >= float(sb_lay["roam_fps"]), "12. Cadence reflects lighter vs heavier monster species")

	# Verify CHASING visibly advances frames more rapidly than ROAMING over same elapsed time
	var sb_rec: Dictionary = by_sp["stone_brute"]
	var sb_actor: MonsterActor = m_mgr.get_monster_actor(str(sb_rec["id"]))
	fow.reveal_circle(sb_rec["cell"], 3)
	m_mgr.refresh_visibility(fow, false)
	sb_actor.sync_visual(sb_rec["cell"], sb_rec["cell"], 1.0, MonsterConfigScript.MonsterAIState.ROAMING, false, 0.0, 0.50)
	var col_roam := sb_actor.active_frame_col
	sb_actor.sync_visual(sb_rec["cell"], sb_rec["cell"], 1.0, MonsterConfigScript.MonsterAIState.CHASING, true, 0.0, 0.50)
	var sb_spr: Sprite2D = sb_actor.get_node("Sprite2D") as Sprite2D
	_assert(sb_actor.active_anim_clip == "chase" and sb_spr.flip_h and sb_actor.active_frame_col > col_roam, "12 & facing_left: CHASING + flip_h applied cleanly without altering cell")

	# 16 & 17: Foot anchor stability & exact world position interpolation
	var cell_a: Vector2i = sb_rec["cell"]
	var cell_b: Vector2i = cell_a + Vector2i(1, 0)
	sb_actor.sync_visual(cell_a, cell_b, 0.5, MonsterConfigScript.MonsterAIState.ROAMING, false, 0.0, 0.4)
	var expected_pos: Vector2 = IsoMath.map_to_local(cell_a).lerp(IsoMath.map_to_local(cell_b), 0.5)
	_assert(sb_actor.position.distance_to(expected_pos) < 0.01 and sb_actor.current_cell == cell_b, "17. Actor interpolates world position identically while preserving canonical cell")
	_assert(sb_spr.offset == sb_lay["anchor_offset"] and sb_actor.z_index == IsoMath.world_y_to_z_index(sb_actor.position.y), "16. Ground anchor offset & Y-sort z_index locked")

	# 14 & 15: Damage flash + HP bar compatibility
	var sb_hp_before := sb_actor.health
	sb_actor.take_damage(20.0, "test_knight") # 20 - 3 armor = 17 dmg
	_assert(is_equal_approx(sb_actor.health, sb_hp_before - 17.0), "15. Armor-mitigated HP reduction preserved cleanly")
	_assert(sb_actor.damage_flash_timer > 0.0 and sb_spr.modulate != Color.WHITE, "14. Damage flash modulates Sprite2D cleanly")
	sb_actor._process(0.30)
	_assert(sb_actor.damage_flash_timer == 0.0 and sb_spr.modulate == Color.WHITE, "14. Damage flash clears back to Color.WHITE cleanly")

	# 18: Actor reuse/rebinding resets stale texture, clip, frame, flash & alert timers
	var reuse_actor := MonsterActor.new()
	reuse_actor.configure("temp_sb", "stone_brute", Vector2i(15, 15), "", 160.0, 160.0, 3.0, MonsterConfigScript.MonsterAIState.IDLE)
	reuse_actor.sync_visual(Vector2i(15, 15), Vector2i(15, 15), 1.0, MonsterConfigScript.MonsterAIState.ATTACKING, true, 0.35, 0.9)
	reuse_actor.take_damage(10.0, "test")
	var reuse_spr: Sprite2D = reuse_actor.get_node("Sprite2D") as Sprite2D
	_assert(reuse_spr.texture == EntityVisualRegistryScript.get_monster_sheet_texture("stone_brute"), "18. Pre-reuse bound to Stone Brute sheet")
	reuse_actor.configure("temp_fs", "forest_stalker", Vector2i(18, 18), "", 75.0, 75.0, 0.0, MonsterConfigScript.MonsterAIState.IDLE)
	_assert(reuse_spr.texture == EntityVisualRegistryScript.get_monster_sheet_texture("forest_stalker"), "18. Reuse switches texture cleanly to Forest Stalker")
	_assert(reuse_spr.frame == 0 and reuse_actor.active_anim_clip == "idle" and reuse_actor.damage_flash_timer == 0.0 and reuse_actor.alert_visual_timer == 0.0 and not reuse_spr.flip_h and reuse_spr.modulate == Color.WHITE, "18. Reuse clears previous frame, timers, flip_h, and modulate cleanly")
	reuse_actor.free()

	# 19: Fog-hidden monsters stay invisible & skip frame updates, catching up on reveal
	var mc_rec: Dictionary = by_sp["marsh_crawler"]
	var mc_actor: MonsterActor = m_mgr.get_monster_actor(str(mc_rec["id"]))
	var mc_spr: Sprite2D = mc_actor.get_node("Sprite2D") as Sprite2D
	mc_actor.sync_visual(mc_rec["cell"], mc_rec["cell"], 1.0, MonsterConfigScript.MonsterAIState.IDLE, false, 0.0, 0.0)
	var hidden_start_frame := mc_spr.frame
	fow.set_state(mc_rec["cell"], FogOfWar.State.UNEXPLORED)
	m_mgr.refresh_visibility(fow, false)
	_assert(not mc_actor.visible, "19. Fog-gated monster actor is strictly invisible in UNEXPLORED Fog")
	mc_actor.sync_visual(mc_rec["cell"], mc_rec["cell"], 1.0, MonsterConfigScript.MonsterAIState.CHASING, false, 0.0, 0.35)
	_assert(mc_spr.frame == hidden_start_frame, "19. Hidden monster skips unnecessary per-frame Sprite2D updates")
	fow.set_state(mc_rec["cell"], FogOfWar.State.VISIBLE)
	m_mgr.refresh_visibility(fow, false)
	_assert(mc_actor.visible and mc_actor.active_anim_clip == "chase" and mc_spr.frame >= 12, "19. Revealing Fog immediately snaps Sprite2D to live chase frame")

	# 22: Presentation query read-only invariant & EntityInspectPanel portrait match
	var mc_state_before := int(mc_rec["state"])
	var mc_hp_before := float(mc_rec["health"])
	var mc_cell_before: Vector2i = mc_rec["cell"]
	hud.call("show_entity_inspector", "monster", str(mc_rec["id"]))
	var ep = hud.get("entity_inspect_panel")
	var ep_icon: TextureRect = ep.get("_icon_rect")
	_assert(ep.visible and ep_icon.texture == EntityVisualRegistryScript.get_monster_portrait_texture("marsh_crawler"), "EntityInspectPanel displays matching Marsh Crawler M6-3 portrait")
	_assert(int(mc_rec["state"]) == mc_state_before and is_equal_approx(float(mc_rec["health"]), mc_hp_before) and mc_rec["cell"] == mc_cell_before, "22. Presentation & inspection never mutate canonical MonsterManager state")

	# 8: DEAD lifecycle safely clears actor & sprite without lingering phantom
	var mc_id := str(mc_rec["id"])
	mc_actor.take_damage(999.0, "test_knight")
	_assert(not mc_actor.is_alive and not mc_spr.visible and mc_actor.active_anim_clip == "dead", "8. Killed MonsterActor hides sprite cleanly in DEAD state")
	_assert(m_mgr.get_monster_record(mc_id).is_empty() and m_mgr.get_monster_actor(mc_id) == null, "8. MonsterManager frees dead actor record & map entry cleanly")

	# 23: M6-2 nest & POI textures intact alongside M6-3
	for n_sp in ["stone_brute", "forest_stalker", "marsh_crawler"]:
		_assert(EntityVisualRegistryScript.get_nest_texture(n_sp, false).get_width() == 48, "23. M6-2 nest texture preserved (%s)" % n_sp)
	_assert(EntityVisualRegistryScript.get_poi_texture("ancient_ruins", false).get_width() == 40, "23. M6-2 POI texture preserved")

	wv.queue_free()
	await process_frame
	await process_frame

	print("[test_monster_visual_animation] Passed: %d | Failed: %d" % [_passed, _failures.size()])
	for f in _failures:
		printerr("  FAIL -> " + f)
	quit(0 if _failures.is_empty() else 1)
