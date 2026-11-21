extends SceneTree

const WorldViewScene := preload("res://scenes/world/world_view.tscn")
const WildlifeConfigScript := preload("res://scripts/world/wildlife_config.gd")
const WildlifeActorScript := preload("res://scripts/world/wildlife_actor.gd")
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
	for y in range(row * fh, (row + 1) * fh):
		for x in range(col * fw, (col + 1) * fw):
			if img.get_pixel(x, y).a > 0.1:
				return true
	return false

func _run() -> void:
	print("[test_wildlife_visual_animation] Starting M6-4 Wildlife Visual & Animation Suite...")

	# =========================================================================
	# 1. ALL 6 SPECIES SHEETS, DIMENSIONS, FRAMES, PORTRAITS & FALLBACK
	# =========================================================================
	var expected_specs := {
		"bird": Vector3i(20, 20, 2),
		"frog": Vector3i(20, 20, 2),
		"rabbit": Vector3i(20, 22, 3),
		"deer": Vector3i(28, 28, 3),
		"wild_boar": Vector3i(26, 24, 4),
		"mountain_goat": Vector3i(26, 26, 4),
	}
	var sp_hashes := {}
	for sp in WildlifeConfigScript.SPECIES_ORDER:
		var spec_v: Vector3i = expected_specs[sp]
		var fw := spec_v.x
		var fh := spec_v.y
		var rows := spec_v.z
		var path := EntityVisualRegistryScript.get_wildlife_sheet_path(sp)
		_assert(ResourceLoader.exists(path), "1. Wildlife sheet exists: %s" % path)
		var tex: Texture2D = EntityVisualRegistryScript.get_wildlife_sheet_texture(sp)
		_assert(tex != null and tex.get_width() == fw * 6 and tex.get_height() == fh * rows, "1. %s sheet dimensions == %dx%d (%dx%d frames, %d rows)" % [sp, fw * 6, fh * rows, fw, fh, rows])
		_assert(EntityVisualRegistryScript.get_wildlife_sheet_texture(sp) == tex, "1. Cached sheet identity reused for %s" % sp)
		sp_hashes[sp] = tex.get_image().get_data().hex_encode().hash()

		var lay := EntityVisualRegistryScript.get_wildlife_sheet_layout(sp)
		for c in range(int(lay["idle_frames"])):
			_assert(_frame_is_nonempty(tex, c, 0, fw, fh), "1. %s idle frame %d non-empty" % [sp, c])
		for c in range(int(lay["move_frames"])):
			_assert(_frame_is_nonempty(tex, c, 1, fw, fh), "1. %s move frame %d non-empty" % [sp, c])
		if rows >= 3:
			for c in range(int(lay["flee_frames"])):
				_assert(_frame_is_nonempty(tex, c, 2, fw, fh), "1. %s flee frame %d non-empty" % [sp, c])
		if rows >= 4:
			for c in range(int(lay["defensive_frames"])):
				_assert(_frame_is_nonempty(tex, c, 3, fw, fh), "1. %s defensive frame %d non-empty" % [sp, c])

		var portrait: Texture2D = EntityVisualRegistryScript.get_wildlife_portrait_texture(sp)
		_assert(portrait != null and portrait.get_width() == fw and portrait.get_height() == fh, "1. %s portrait AtlasTexture == %dx%d" % [sp, fw, fh])
		_assert(EntityVisualRegistryScript.get_wildlife_portrait_texture(sp) == portrait, "1. %s portrait AtlasTexture cached" % sp)

	# All 6 species are visually distinct
	var unique_hashes := {}
	for h in sp_hashes.values():
		unique_hashes[h] = true
	_assert(unique_hashes.size() == 6, "1. All 6 wildlife species have unique pixel-art sheets (%d)" % unique_hashes.size())

	# Missing fallback check
	var fb_tex: Texture2D = EntityVisualRegistryScript.load_texture_cached("res://assets/entities/wildlife/missing_m64_test.png", "wildlife_sheet:deer")
	_assert(fb_tex != null and fb_tex is ImageTexture, "Fallback: missing wildlife path yields ImageTexture safely")
	_assert(EntityVisualRegistryScript.load_texture_cached("res://assets/entities/wildlife/missing_m64_test.png", "wildlife_sheet:deer") == fb_tex, "Fallback: cached identically on repeated miss")

	# =========================================================================
	# 2. LIVE WORLD_VIEW SCENE INTEGRATION, ANIMATIONS, TIMING & FOG
	# =========================================================================
	var wv := WorldViewScene.instantiate()
	wv.set("skip_intro_for_test", true)
	root.add_child(wv)
	await create_timer(0.25).timeout

	var fow: FogOfWar = wv.get("fog_of_war")
	var wd = wv.get("world_data")
	var nav: GridNavigation = wv.get("nav")
	var wl_mgr = wv.get("wildlife_mgr")
	var hud = wv.get("hud")
	var ep = hud.get("entity_inspect_panel")
	var tip = hud.get("entity_hover_tooltip")
	var ep_icon: TextureRect = ep.get("_icon_rect")
	var tip_icon: TextureRect = tip.get("_icon_rect")

	_assert(wl_mgr != null and wl_mgr.animals.size() <= WildlifeConfigScript.MAX_TOTAL_POPULATION, "Cap: wildlife population <= 70")

	# Collect/ensure one representative per species in world_view
	var by_sp := {}
	for rec in wl_mgr.animals:
		by_sp[str(rec["species_id"])] = rec
	for i in range(WildlifeConfigScript.SPECIES_ORDER.size()):
		var sp: String = WildlifeConfigScript.SPECIES_ORDER[i]
		if not by_sp.has(sp):
			var c_inj: Vector2i = wd.center_spawn + Vector2i(2 + i * 2, 6)
			var spec_i := WildlifeConfigScript.get_species_def(sp)
			var rec_inj: Dictionary = wl_mgr._make_animal_record("test_wl_%s" % sp, sp, int(spec_i["category"]), c_inj)
			wl_mgr.animals.append(rec_inj)
			wl_mgr.animals_by_id[rec_inj["id"]] = rec_inj
			wl_mgr._spawn_actor_for_record(rec_inj)
			by_sp[sp] = rec_inj

	# Reveal all 6 species cleanly
	for sp in WildlifeConfigScript.SPECIES_ORDER:
		var rec: Dictionary = by_sp[sp]
		fow.reveal_circle(rec["cell"], 3)
	wl_mgr.refresh_visibility(fow, false)

	# Verify live WildlifeActor nodes bind real M6-4 sheets & match UI portraits
	for sp in WildlifeConfigScript.SPECIES_ORDER:
		var rec: Dictionary = by_sp[sp]
		var aid := str(rec["id"])
		var actor = wl_mgr.actors_by_id.get(aid)
		_assert(actor != null and is_instance_valid(actor), "Live scene has actor for %s" % sp)
		var spr: Sprite2D = actor.get("_sprite")
		_assert(spr != null and spr.texture == EntityVisualRegistryScript.get_wildlife_sheet_texture(sp), "Live actor for %s binds production Sprite2D sheet" % sp)
		_assert(spr.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and spr.centered, "Actor %s uses nearest filtering + centered=true" % sp)
		_assert(actor.z_index == IsoMath.world_y_to_z_index(actor.position.y), "Actor %s Y-sort z_index matches IsoMath" % sp)

		hud.call("show_entity_inspector", "wildlife", aid)
		_assert(ep.visible and ep_icon.texture == EntityVisualRegistryScript.get_wildlife_portrait_texture(sp), "EntityInspectPanel shows matching M6-4 portrait for %s" % sp)
		hud.call("update_world_hover", rec["cell"], Vector2(360, 360), false)
		if tip.visible and str(tip.call("get_current_entity_key")) == "wildlife:%s" % aid:
			_assert(tip_icon.texture == EntityVisualRegistryScript.get_wildlife_portrait_texture(sp), "EntityHoverTooltip shows matching portrait for %s" % sp)

	# Tailored FPS progression check across species & states
	var bird_lay := EntityVisualRegistryScript.get_wildlife_sheet_layout("bird")
	var deer_lay := EntityVisualRegistryScript.get_wildlife_sheet_layout("deer")
	var rab_lay := EntityVisualRegistryScript.get_wildlife_sheet_layout("rabbit")
	_assert(float(bird_lay["move_fps"]) > float(deer_lay["move_fps"]), "FPS: Bird flutter move_fps exceeds Deer walk move_fps")
	_assert(float(rab_lay["flee_fps"]) > float(rab_lay["move_fps"]) and float(rab_lay["move_fps"]) > float(rab_lay["idle_fps"]), "FPS: Rabbit flee_fps > move_fps > idle_fps")

	# Real State -> Clip Mapping checks
	var bird_a = wl_mgr.actors_by_id[str(by_sp["bird"]["id"])]
	var bird_p := IsoMath.map_to_local(by_sp["bird"]["cell"])
	bird_a.sync_visual(bird_p, WildlifeConfigScript.BehaviorState.IDLE, false, 0.0, false, 0.25, 1.0)
	_assert(bird_a.active_anim_clip == "idle" and bird_a.active_anim_row == 0 and bird_a._sprite.frame < 4, "Ambient Bird IDLE selects row 0")
	bird_a.sync_visual(bird_p, WildlifeConfigScript.BehaviorState.WANDERING, false, 0.5, true, 0.35, 1.0)
	_assert(bird_a.active_anim_clip == "move" and bird_a.active_anim_row == 1 and bird_a._sprite.offset.y < -5.0, "Ambient Bird FLUTTER selects row 1 + aerial lift")

	var rab_a = wl_mgr.actors_by_id[str(by_sp["rabbit"]["id"])]
	var rab_p := IsoMath.map_to_local(by_sp["rabbit"]["cell"])
	rab_a.sync_visual(rab_p, WildlifeConfigScript.BehaviorState.FLEEING, true, 0.5, true, 0.20, 1.0)
	_assert(rab_a.active_anim_clip == "flee" and rab_a.active_anim_row == 2 and rab_a._sprite.flip_h and rab_a._state_badge.visible, "Passive Huntable Rabbit FLEEING selects row 2 + flip_h + badge")
	rab_a.sync_visual(rab_p, WildlifeConfigScript.BehaviorState.BEING_HUNTED, false, 0.0, false, 1.0, 1.0)
	_assert(rab_a.active_anim_clip == "being_hunted" and rab_a.active_anim_row == 0 and rab_a.active_frame_col == 0 and is_equal_approx(rab_a._sprite.offset.y, -5.0), "Passive Huntable BEING_HUNTED freezes at row 0 col 0 with -5.0 ground anchor")

	var boar_a = wl_mgr.actors_by_id[str(by_sp["wild_boar"]["id"])]
	var boar_p := IsoMath.map_to_local(by_sp["wild_boar"]["cell"])
	boar_a.sync_visual(boar_p, WildlifeConfigScript.BehaviorState.DEFENSIVE_DISPLAY, false, 0.0, false, 0.30, 1.0)
	_assert(boar_a.active_anim_clip == "defensive" and boar_a.active_anim_row == 3 and boar_a._state_badge.visible and boar_a._sprite.modulate != Color.WHITE, "Defensive Wild Boar DEFENSIVE_DISPLAY selects row 3 + badge + warn tint")

	var goat_a = wl_mgr.actors_by_id[str(by_sp["mountain_goat"]["id"])]
	var goat_p := IsoMath.map_to_local(by_sp["mountain_goat"]["cell"])
	goat_a.sync_visual(goat_p, WildlifeConfigScript.BehaviorState.DEFENSIVE_DISPLAY, false, 0.0, false, 0.30, 1.0)
	_assert(goat_a.active_anim_clip == "defensive" and goat_a.active_anim_row == 3 and goat_a._state_badge.visible, "Defensive Mountain Goat DEFENSIVE_DISPLAY selects row 3 + badge")

	# Advance frame progression across time within defensive & flee clips
	goat_a.sync_visual(goat_p, WildlifeConfigScript.BehaviorState.DEFENSIVE_DISPLAY, false, 0.0, false, 0.65, 1.0)
	_assert(goat_a.active_frame_col >= 1 and goat_a._sprite.frame >= 18, "DEFENSIVE_DISPLAY advances through frame cols cleanly")

	# Pause & 2x/3x speed scaling in canonical WildlifeManager
	var anim_t_before_pause := float(wl_mgr._anim_time)
	wl_mgr.advance_simulation(0.4, 0.0, wd, nav, [], [])
	_assert(is_equal_approx(float(wl_mgr._anim_time), anim_t_before_pause), "Pause (speed_mult=0) freezes WildlifeManager._anim_time cleanly")

	var t0_1x := float(wl_mgr._anim_time)
	wl_mgr.advance_simulation(0.03, 1.0, wd, nav, [], [])
	var dt_1x := float(wl_mgr._anim_time) - t0_1x

	var t0_2x := float(wl_mgr._anim_time)
	wl_mgr.advance_simulation(0.03, 2.0, wd, nav, [], [])
	var dt_2x := float(wl_mgr._anim_time) - t0_2x

	var t0_3x := float(wl_mgr._anim_time)
	wl_mgr.advance_simulation(0.03, 3.0, wd, nav, [], [])
	var dt_3x := float(wl_mgr._anim_time) - t0_3x

	_assert(is_equal_approx(dt_2x, dt_1x * 2.0) and is_equal_approx(dt_3x, dt_1x * 3.0), "2x/3x simulation speed scales wildlife _anim_time proportionally")

	# Fog-hidden gating & immediate reveal catch-up
	var deer_rec: Dictionary = by_sp["deer"]
	var deer_id := str(deer_rec["id"])
	var deer_a = wl_mgr.actors_by_id[deer_id]
	var deer_p := IsoMath.map_to_local(deer_rec["cell"])
	deer_a.sync_visual(deer_p, WildlifeConfigScript.BehaviorState.IDLE, false, 0.0, false, 0.0, 1.0)
	var hidden_start_frame: int = deer_a._sprite.frame
	fow.set_state(deer_rec["cell"], FogOfWar.State.UNEXPLORED)
	wl_mgr.refresh_visibility(fow, false)
	_assert(not deer_a.visible, "Fog: wildlife hidden in UNEXPLORED")
	deer_a.sync_visual(deer_p, WildlifeConfigScript.BehaviorState.FLEEING, true, 0.4, true, 0.35, 1.0)
	_assert(deer_a._sprite.frame == hidden_start_frame, "Fog-hidden wildlife skips sprite frame updates")
	fow.set_state(deer_rec["cell"], FogOfWar.State.VISIBLE)
	wl_mgr.refresh_visibility(fow, false)
	_assert(deer_a.visible and deer_a.active_anim_clip == "flee" and deer_a._sprite.flip_h and deer_a._sprite.frame >= 12, "Fog reveal immediately catches up to live flee frame")

	# Actor reuse / reset safety check
	var reuse_a := WildlifeActorScript.new()
	reuse_a.setup("reuse_boar", "wild_boar", Vector2i(20, 20))
	reuse_a.sync_visual(IsoMath.map_to_local(Vector2i(20, 20)), WildlifeConfigScript.BehaviorState.DEFENSIVE_DISPLAY, true, 0.5, false, 0.4, 0.5)
	_assert(reuse_a._state_badge.visible and reuse_a._sprite.modulate != Color.WHITE and reuse_a._sprite.flip_h, "Pre-reuse defensive boar has badge, tint, flip_h")
	reuse_a.setup("reuse_bird", "bird", Vector2i(22, 22))
	_assert(reuse_a._sprite.texture == EntityVisualRegistryScript.get_wildlife_sheet_texture("bird"), "Reuse binds new bird sheet texture")
	_assert(reuse_a._sprite.frame == 0 and not reuse_a._sprite.flip_h and reuse_a._sprite.modulate == Color.WHITE and not reuse_a._state_badge.visible and reuse_a._sprite.scale == Vector2.ONE, "Reuse resets stale frame, flip_h, tint, scale & badge")
	reuse_a.free()

	# Read-only invariant: visual calls & inspector query never mutate WildlifeManager
	var boar_rec: Dictionary = by_sp["wild_boar"]
	var boar_st_before := int(boar_rec["state"])
	var boar_cell_before: Vector2i = boar_rec["cell"]
	hud.call("show_entity_inspector", "wildlife", str(boar_rec["id"]))
	_assert(int(boar_rec["state"]) == boar_st_before and boar_rec["cell"] == boar_cell_before and wl_mgr.animals.size() <= WildlifeConfigScript.MAX_TOTAL_POPULATION, "Read-only: inspection & visual presentation never mutate WildlifeManager state")

	wv.queue_free()
	await process_frame
	await process_frame

	print("[test_wildlife_visual_animation] Passed: %d | Failed: %d" % [_passed, _failures.size()])
	for f in _failures:
		printerr("  FAIL -> " + f)
	quit(0 if _failures.is_empty() else 1)
