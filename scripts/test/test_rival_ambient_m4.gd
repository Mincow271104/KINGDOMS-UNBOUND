extends SceneTree

const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const SettlementDataScript = preload("res://scripts/world/settlement_data.gd")
const SettlementVillagerDataScript = preload("res://scripts/world/settlement_villager_data.gd")
const SettlementSimulationManagerScript = preload("res://scripts/world/settlement_simulation_manager.gd")
const RivalVillagerActorScript = preload("res://scripts/world/rival_villager_actor.gd")
const RivalPresentationControllerScript = preload("res://scripts/world/rival_presentation_controller.gd")
const GridNavigationScript = preload("res://scripts/navigation/grid_navigation.gd")
const FogOfWarScript = preload("res://scripts/world/fog_of_war.gd")
const WorkerPresentationResolverScript = preload("res://scripts/world/worker_presentation_resolver.gd")
const SettlementNavigationContextScript = preload("res://scripts/world/settlement_navigation_context.gd")

var _passed: int = 0
var _failed: int = 0

func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] %s" % label)
	else:
		_failed += 1
		printerr("  [FAIL] %s" % label)

func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		_passed += 1
		print("  [PASS] %s" % label)
	else:
		_failed += 1
		printerr("  [FAIL] %s (got=%s exp=%s)" % [label, str(actual), str(expected)])

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("\n====================================================================")
	print("  TEST SUITE: M4-1 Base Locomotion Sprite Sheet & Frame Stepper")
	print("====================================================================")

	# 1. Sprite sheet & dimensions + foot anchor/offset preservation
	var actor := RivalVillagerActorScript.new()
	actor.bind_villager("stl_m4", "npc_stl_m4_1", "neutral_tribe", "farmer")
	_assert_true(actor.sprite != null and actor.sprite.hframes == 6 and actor.sprite.vframes == 6, "M4-1 Sheet: Sprite2D uses 6x6 hframes/vframes (M5 Variant A)")
	_assert_true(actor.sprite.texture != null and actor.sprite.texture.get_size() == Vector2(192, 216), "M4-1 Sheet: Texture size is 192x216 (32x36 frames)")
	_assert_eq(actor.sprite.offset, RivalVillagerActorScript.BASE_SPRITE_OFFSET, "M4-1 Offset: BASE_SPRITE_OFFSET (-16,-33) preserved")

	# 2. Idle row selection & deterministic phase offset
	actor.sync_presentation(Vector2(100, 100), false, 0, false, true, 0.0, 19.9)
	_assert_true(actor.active_anim_name == "idle" and actor.sprite.frame_coords.y == 0, "M4-1 Idle: stationary selects Row 0 (idle)")

	var actor_b := RivalVillagerActorScript.new()
	actor_b.bind_villager("stl_m4", "npc_stl_m4_2", "neutral_tribe", "farmer")
	var actor_a2 := RivalVillagerActorScript.new()
	actor_a2.bind_villager("stl_m4", "npc_stl_m4_1", "neutral_tribe", "farmer")
	_assert_true(is_equal_approx(actor.idle_phase_offset, actor_a2.idle_phase_offset) and actor.idle_phase_offset != actor_b.idle_phase_offset, "M4-1 Idle Phase: deterministic per villager ID & differs across villagers")

	# 3. Walk row selection, frame indexing, seamless wrap, and disabled walk bob
	actor.sync_presentation(Vector2(100, 100), false, 0, true, true, 0.0, 19.9)
	_assert_true(actor.active_anim_name == "walk" and actor.sprite.frame_coords == Vector2i(0, 1) and actor.sprite.offset == RivalVillagerActorScript.BASE_SPRITE_OFFSET, "M4-1 Walk: moving starts at Row 1 Frame 0 with bob_y == 0.0")
	actor.sync_presentation(Vector2(102, 100), false, 0, true, true, 0.2, 19.9) # 5 FPS -> 0.2s = frame 1
	_assert_eq(actor.sprite.frame_coords, Vector2i(1, 1), "M4-1 Walk Indexing: 0.2s at 5 FPS -> Frame 1")
	actor.sync_presentation(Vector2(104, 100), false, 0, true, true, 0.4, 19.9) # total 0.6s -> frame 3
	_assert_eq(actor.sprite.frame_coords, Vector2i(3, 1), "M4-1 Walk Indexing: 0.6s at 5 FPS -> Frame 3")
	actor.sync_presentation(Vector2(106, 100), false, 0, true, true, 0.6, 19.9) # total 1.2s (6f @ 5 FPS) -> wraps to frame 0
	_assert_eq(actor.sprite.frame_coords, Vector2i(0, 1), "M4-1 Walk Wrap: 1.2s wraps seamlessly back to Frame 0")

	# 4. Pause freezes animation (anim_delta == 0.0)
	actor.sync_presentation(Vector2(107, 100), false, 0, true, true, 0.2, 19.9) # frame 1
	var paused_fc: Vector2i = actor.sprite.frame_coords
	actor.sync_presentation(Vector2(107, 100), false, 0, true, true, 0.0, 19.9)
	_assert_eq(actor.sprite.frame_coords, paused_fc, "M4-1 Pause: anim_delta == 0.0 freezes current frame")

	# 5. 2x / 3x speed scaling & Ambient (19.9 px/s -> 5 FPS) vs Worker (48 px/s -> ~12 FPS) cadence
	var actor_w := RivalVillagerActorScript.new()
	actor_w.bind_villager("stl_m4", "npc_stl_m4_w", "neutral_tribe", "woodcutter")
	actor_w.sync_presentation(Vector2(100, 100), true, 4, true, true, 0.0, 48.0)
	_assert_true(actor_w.sprite.flip_h == true, "M4-1 Flip: flip_h=true applied cleanly")
	actor_w.sync_presentation(Vector2(104, 100), true, 4, true, true, 0.1, 48.0) # ~12.06 FPS -> 0.1s = frame 1
	_assert_eq(actor_w.sprite.frame_coords, Vector2i(1, 1), "M4-1 Speed Cadence: Worker at 48 px/s (~12 FPS) advances faster than Ambient at 19.9 px/s")

	# 6. Stop moving returns to Idle & resets anim_clock_sec
	actor_w.sync_presentation(Vector2(104, 100), true, 4, false, true, 0.0, 48.0)
	_assert_true(actor_w.active_anim_name == "idle" and actor_w.anim_clock_sec == 0.0 and actor_w.sprite.frame_coords.y == 0, "M4-1 State Reset: stopping resets anim_clock_sec=0.0 & returns to Idle Row 0")

	# 7. Actor pool release/rebind resets frame & animation state
	actor.release_binding()
	_assert_true(actor.active_anim_name == "" and actor.anim_clock_sec == 0.0 and actor.sprite.frame_coords == Vector2i.ZERO and not actor.sprite.flip_h, "M4-1 Pool Release: resets anim name, clock, frame_coords, and flip_h")
	actor.bind_villager("stl_m4", "npc_stl_m4_99", "rival_military", "guard")
	_assert_true(actor.active_anim_name == "" and actor.sprite.frame_coords == Vector2i.ZERO, "M4-1 Pool Rebind: starts cleanly without previous villager frame")

	# 8. Missing sprite sheet fallback to citizen.png (1x1 + procedural bob restored)
	actor.use_base_sheet = false
	actor.sync_presentation(Vector2(100, 100), false, 0, true, true, 0.15, 19.9)
	_assert_true(actor.sprite.hframes == 1 and actor.sprite.vframes == 1 and actor.sprite.offset != RivalVillagerActorScript.BASE_SPRITE_OFFSET, "M4-1 Fallback: missing sheet falls back to 1x1 citizen.png & procedural bob")

	# 9. Controller integration: Fog gating, 48-Actor cap, Near/Mid/Far, zero canonical mutation
	var wd = WorldGeneratorScript.generate(12345, WorldGeneratorScript.LATEST_GENERATOR_VERSION, 128, 128)
	var mgr = SettlementSimulationManagerScript.new()
	mgr.register_settlements_from_world_data(wd)
	mgr.seed_initial_populations()
	var sid: String = mgr.get_registered_settlement_ids()[0]
	var ctx = mgr.get_context(sid)
	var snaps_before := []
	for vv in ctx.get_all_villagers_cached_view():
		snaps_before.append(vv.to_dict())

	var gnav := GridNavigationScript.new(wd)
	var cam := Camera2D.new()
	cam.position = IsoMath.map_to_local(wd.settlements[0].anchor_cell)
	cam.zoom = Vector2(2.0, 2.0)
	root.add_child(cam)
	var pool_cont := Node2D.new()
	root.add_child(pool_cont)
	var fog := FogOfWarScript.new(128, 128)
	var pres := RivalPresentationControllerScript.new()
	pres.setup(mgr, wd, gnav, cam, fog, pool_cont)
	pres.debug_fog_disabled = false
	pres.update_presentation(0.05, 1.0)
	_assert_eq(pres.get_actor_pool().get_active_count(), 0, "M4-1 Fog: Unexplored cells keep active_actors == 0")

	pres.debug_fog_disabled = true
	for _i in range(5):
		mgr.step_ambient_locomotion(0.1)
		pres.update_presentation(0.05, 2.0)
	_assert_true(pres.get_actor_pool().get_active_count() > 0 and pres.get_actor_pool().get_active_count() <= 48, "M4-1 Pool Cap: active_actors in 1..48 (%d)" % pres.get_actor_pool().get_active_count())

	var snaps_after := []
	for vv in ctx.get_all_villagers_cached_view():
		snaps_after.append(vv.to_dict())
	_assert_true(snaps_before.size() == snaps_after.size(), "M4-1 Isolation: villager count unchanged")

	actor.free()
	actor_b.free()
	actor_a2.free()
	actor_w.free()

	print("\n====================================================================")
	print("  TEST SUITE: M4-2 Role-Specific Work & Cargo Animations")
	print("====================================================================")

	var resolver = WorkerPresentationResolverScript.new()
	var pres_res = WorkerPresentationResolverScript.PresentationResult.new()

	# Helper actor for role mapping tests
	var r_actor := RivalVillagerActorScript.new()

	# 1. Farmer WORKING_AT_TARGET -> Farmer Work
	r_actor.bind_villager("stl_m4", "npc_f1", "neutral_tribe", "farmer")
	pres_res.reset()
	pres_res.presentation_state = WorkerPresentationResolverScript.State.WORKING_AT_TARGET
	pres_res.has_valid_focus = true
	pres_res.focus_cell = Vector2i(10, 10)
	r_actor.set_worker_presentation_metadata(pres_res)
	r_actor.sync_presentation(Vector2(100, 100), false, 0, false, true, 0.0, 48.0)
	_assert_true(r_actor.active_anim_name == "farmer_work" and r_actor.active_sheet_id == "farmer" and r_actor.sprite.texture.get_size() == Vector2(192, 216) and r_actor.sprite.hframes == 6 and r_actor.sprite.vframes == 6 and r_actor.sprite.offset == RivalVillagerActorScript.BASE_SPRITE_OFFSET, "M4-2 Test 1: Farmer WORKING_AT_TARGET selects Farmer Work (192x216, no stacked bob)")

	# 2. Farmer WAITING -> Idle
	pres_res.presentation_state = WorkerPresentationResolverScript.State.WAITING
	r_actor.set_worker_presentation_metadata(pres_res)
	r_actor.sync_presentation(Vector2(100, 100), false, 0, false, true, 0.0, 48.0)
	_assert_true(r_actor.active_anim_name == "idle" and r_actor.active_sheet_id == "farmer" and r_actor.sprite.frame_coords.y == 0, "M4-2 Test 2: Farmer WAITING selects Farmer Idle")

	# 3. Woodcutter WORKING_AT_TARGET -> Woodcutter Work
	r_actor.bind_villager("stl_m4", "npc_w1", "rival_military", "woodcutter")
	pres_res.reset()
	pres_res.presentation_state = WorkerPresentationResolverScript.State.WORKING_AT_TARGET
	pres_res.has_valid_focus = true
	r_actor.set_worker_presentation_metadata(pres_res)
	r_actor.sync_presentation(Vector2(100, 100), false, 0, false, true, 0.0, 48.0)
	_assert_true(r_actor.active_anim_name == "woodcutter_work" and r_actor.active_sheet_id == "woodcutter" and r_actor.sprite.texture.get_size() == Vector2(192, 216) and r_actor.sprite.offset == RivalVillagerActorScript.BASE_SPRITE_OFFSET, "M4-2 Test 3: Woodcutter WORKING_AT_TARGET selects Woodcutter Work (192x216, no stacked bob)")

	# 4. Woodcutter INVALID_TARGET -> Idle
	pres_res.presentation_state = WorkerPresentationResolverScript.State.INVALID_TARGET
	pres_res.has_valid_focus = false
	r_actor.set_worker_presentation_metadata(pres_res)
	r_actor.sync_presentation(Vector2(100, 100), false, 0, false, true, 0.0, 48.0)
	_assert_true(r_actor.active_anim_name == "idle" and r_actor.active_sheet_id == "woodcutter", "M4-2 Test 4: Woodcutter INVALID_TARGET selects Woodcutter Idle")

	# 5. Hunter WORKING_AT_TARGET -> Hunter Aim
	r_actor.bind_villager("stl_m4", "npc_h1", "neutral_tribe", "hunter")
	pres_res.reset()
	pres_res.presentation_state = WorkerPresentationResolverScript.State.WORKING_AT_TARGET
	pres_res.has_valid_focus = true
	r_actor.set_worker_presentation_metadata(pres_res)
	r_actor.sync_presentation(Vector2(100, 100), false, 0, false, true, 0.0, 48.0)
	_assert_true(r_actor.active_anim_name == "hunter_aim" and r_actor.active_sheet_id == "hunter" and r_actor.sprite.texture.get_size() == Vector2(192, 216), "M4-2 Test 5: Hunter WORKING_AT_TARGET selects Hunter Aim (192x216)")

	# 6. Hunter INVALID_TARGET -> Idle
	pres_res.presentation_state = WorkerPresentationResolverScript.State.INVALID_TARGET
	r_actor.set_worker_presentation_metadata(pres_res)
	r_actor.sync_presentation(Vector2(100, 100), false, 0, false, true, 0.0, 48.0)
	_assert_true(r_actor.active_anim_name == "idle" and r_actor.active_sheet_id == "hunter", "M4-2 Test 6: Hunter INVALID_TARGET selects Hunter Idle")

	# 7. Guard GUARDING -> Guard Watch
	r_actor.bind_villager("stl_m4", "npc_g1", "rival_military", "guard")
	pres_res.reset()
	pres_res.presentation_state = WorkerPresentationResolverScript.State.GUARDING
	pres_res.has_valid_focus = true
	r_actor.set_worker_presentation_metadata(pres_res)
	r_actor.sync_presentation(Vector2(100, 100), false, 0, false, true, 0.0, 48.0)
	_assert_true(r_actor.active_anim_name == "guard_watch" and r_actor.active_sheet_id == "guard" and r_actor.sprite.texture.get_size() == Vector2(192, 216), "M4-2 Test 7: Guard GUARDING selects Guard Watch (192x216)")

	# 8. Guard WAITING -> Idle
	pres_res.presentation_state = WorkerPresentationResolverScript.State.WAITING
	r_actor.set_worker_presentation_metadata(pres_res)
	r_actor.sync_presentation(Vector2(100, 100), false, 0, false, true, 0.0, 48.0)
	_assert_true(r_actor.active_anim_name == "idle" and r_actor.active_sheet_id == "guard", "M4-2 Test 8: Guard WAITING selects Guard Idle")

	# 9-13. Hauler canonical metadata via real WorkerPresentationResolver
	var hauler_v = null
	var hauler_job = null
	for vv in ctx.get_all_villagers_cached_view():
		if String(vv.role) == SettlementVillagerDataScript.ROLE_HAULER:
			hauler_v = vv
			break
	if hauler_v == null and ctx.get_all_villagers_cached_view().size() > 0:
		hauler_v = ctx.get_all_villagers_cached_view()[0]
	var orig_h_role := String(hauler_v.role)
	var orig_h_task := String(hauler_v.task_state)
	var orig_h_job := String(hauler_v.active_job_id)
	var orig_h_cargo: Dictionary = Dictionary(hauler_v.cargo)
	# Find or reuse an active job/workplace for resolver test
	for j in ctx.job_board.get_all_jobs():
		if ctx.workplace_registry.get_workplace(String(j.workplace_id)) != null:
			hauler_job = j
			break
	var orig_j_dest: Vector2i = hauler_job.dest_cell
	var orig_j_src: Vector2i = hauler_job.source_cell
	var orig_j_tgt: Vector2i = hauler_job.target_cell

	hauler_v.role = SettlementVillagerDataScript.ROLE_HAULER
	hauler_v.task_state = SettlementVillagerDataScript.TASK_HAULING
	hauler_v.active_job_id = String(hauler_job.job_id)
	var h_loc = SettlementNavigationContextScript.LocomotionState.new()
	h_loc.has_valid_focus = false

	# 9. Hauler empty moving -> Base Walk
	hauler_v.clear_cargo()
	h_loc.is_moving = true
	resolver.resolve_into(ctx, hauler_v, h_loc, wd, null, pres_res)
	r_actor.bind_villager(sid, String(hauler_v.villager_id), "rival_merchant", "hauler")
	r_actor.set_worker_presentation_metadata(pres_res)
	r_actor.sync_presentation(Vector2(100, 100), false, 0, pres_res.is_moving, true, 0.0, 48.0)
	_assert_true(pres_res.presentation_state == WorkerPresentationResolverScript.State.TRANSPORT_EMPTY and not pres_res.transport_loaded and r_actor.active_anim_name == "walk" and r_actor.active_sheet_id == "hauler" and r_actor.sprite.frame_coords.y == 1, "M4-2 Test 9: Hauler empty moving selects Hauler Walk")

	# 10. Hauler empty stationary -> Hauler Idle
	h_loc.is_moving = false
	resolver.resolve_into(ctx, hauler_v, h_loc, wd, null, pres_res)
	r_actor.set_worker_presentation_metadata(pres_res)
	r_actor.sync_presentation(Vector2(100, 100), false, 0, pres_res.is_moving, true, 0.0, 48.0)
	_assert_true(r_actor.active_anim_name == "idle" and r_actor.active_sheet_id == "hauler" and r_actor.sprite.frame_coords.y == 0, "M4-2 Test 10: Hauler empty stationary selects Hauler Idle")

	# 11. Hauler loaded moving -> Carry Walk
	hauler_v.set_cargo("wood", 5)
	h_loc.is_moving = true
	resolver.resolve_into(ctx, hauler_v, h_loc, wd, null, pres_res)
	r_actor.set_worker_presentation_metadata(pres_res)
	r_actor.sync_presentation(Vector2(100, 100), false, 0, pres_res.is_moving, true, 0.0, 48.0)
	_assert_true(pres_res.presentation_state == WorkerPresentationResolverScript.State.TRANSPORT_LOADED and pres_res.transport_loaded and r_actor.active_anim_name == "carry_walk" and r_actor.active_sheet_id == "hauler_carry" and r_actor.sprite.frame_coords.y == 4 and r_actor.sprite.texture.get_size() == Vector2(192, 288), "M4-2 Test 11: Hauler loaded moving selects Carry Walk (Row 4, 192x288)")

	# 12. Hauler loaded stationary -> Carry Idle
	h_loc.is_moving = false
	resolver.resolve_into(ctx, hauler_v, h_loc, wd, null, pres_res)
	r_actor.set_worker_presentation_metadata(pres_res)
	r_actor.sync_presentation(Vector2(100, 100), false, 0, pres_res.is_moving, true, 0.0, 48.0)
	_assert_true(r_actor.active_anim_name == "carry_idle" and r_actor.active_sheet_id == "hauler_carry" and r_actor.sprite.frame_coords.y == 6, "M4-2 Test 12: Hauler loaded stationary selects Carry Idle (Row 6)")

	# 13. Hauler loaded + invalid destination -> Carry Idle
	hauler_job.dest_cell = Vector2i(-1, -1)
	hauler_job.target_cell = Vector2i(-1, -1)
	resolver.resolve_into(ctx, hauler_v, h_loc, wd, null, pres_res)
	r_actor.set_worker_presentation_metadata(pres_res)
	r_actor.sync_presentation(Vector2(100, 100), false, 0, pres_res.is_moving, true, 0.0, 48.0)
	_assert_true(pres_res.presentation_state == WorkerPresentationResolverScript.State.INVALID_TARGET and pres_res.transport_loaded and r_actor.active_anim_name == "carry_idle" and r_actor.active_sheet_id == "hauler_carry", "M4-2 Test 13: Hauler loaded + INVALID_TARGET still selects Carry Idle")

	# 14. Cargo state changes update the active sheet immediately
	hauler_v.clear_cargo()
	hauler_job.dest_cell = orig_j_dest
	hauler_job.target_cell = orig_j_tgt
	resolver.resolve_into(ctx, hauler_v, h_loc, wd, null, pres_res)
	r_actor.set_worker_presentation_metadata(pres_res)
	r_actor.sync_presentation(Vector2(100, 100), false, 0, pres_res.is_moving, true, 0.0, 48.0)
	_assert_true(r_actor.active_sheet_id == "hauler" and r_actor.active_anim_name == "idle", "M4-2 Test 14: Cargo cleared immediately switches active state back to Hauler idle")

	# Restore hauler_v & job
	hauler_v.role = orig_h_role
	hauler_v.task_state = orig_h_task
	hauler_v.active_job_id = orig_h_job
	hauler_v.cargo = orig_h_cargo
	hauler_job.dest_cell = orig_j_dest
	hauler_job.source_cell = orig_j_src
	hauler_job.target_cell = orig_j_tgt

	# 15. Rebinding Farmer Actor to Woodcutter clears prior work frames
	r_actor.bind_villager("stl_m4", "npc_f2", "neutral_tribe", "farmer")
	pres_res.reset()
	pres_res.presentation_state = WorkerPresentationResolverScript.State.WORKING_AT_TARGET
	r_actor.set_worker_presentation_metadata(pres_res)
	r_actor.sync_presentation(Vector2(100, 100), false, 0, false, true, 0.5, 48.0) # advance frame
	r_actor.release_binding()
	var released_clean: bool = (r_actor.active_anim_name == "" and r_actor.active_sheet_id == "" and r_actor.anim_clock_sec == 0.0 and r_actor.sprite.frame_coords == Vector2i.ZERO)
	r_actor.bind_villager("stl_m4", "npc_w2", "neutral_tribe", "woodcutter")
	_assert_true(released_clean and r_actor.active_anim_name == "" and r_actor.active_sheet_id == "woodcutter" and r_actor.anim_clock_sec == 0.0 and r_actor.sprite.frame_coords == Vector2i.ZERO, "M4-2 Test 15: Rebinding Farmer -> Woodcutter clears prior work frames and clock")

	# 16. Rebinding loaded Hauler Actor to empty Guard clears cargo visuals
	r_actor.bind_villager("stl_m4", "npc_hl2", "rival_merchant", "hauler")
	pres_res.reset()
	pres_res.presentation_state = WorkerPresentationResolverScript.State.TRANSPORT_LOADED
	pres_res.transport_loaded = true
	pres_res.cargo_resource = "wood"
	r_actor.set_worker_presentation_metadata(pres_res)
	r_actor.sync_presentation(Vector2(100, 100), false, 0, false, true, 0.0, 48.0)
	r_actor.release_binding()
	r_actor.bind_villager("stl_m4", "npc_gd2", "rival_military", "guard")
	r_actor.sync_presentation(Vector2(100, 100), false, 0, false, true, 0.0, 48.0)
	_assert_true(not r_actor.worker_transport_loaded and r_actor.worker_cargo_resource.is_empty() and r_actor.active_sheet_id == "guard", "M4-2 Test 16: Rebinding loaded Hauler -> Guard clears cargo visuals")

	# 17. Missing role sheet falls back to idle sheet
	r_actor.bind_villager("stl_m4", "npc_fb1", "neutral_tribe", "farmer")
	r_actor.use_role_sheets = false
	pres_res.reset()
	pres_res.presentation_state = WorkerPresentationResolverScript.State.WORKING_AT_TARGET
	r_actor.set_worker_presentation_metadata(pres_res)
	r_actor.sync_presentation(Vector2(100, 100), false, 0, false, true, 0.0, 48.0)
	_assert_true(r_actor.active_sheet_id == "idle" and r_actor.active_anim_name == "idle" and r_actor.sprite.hframes == 6 and r_actor.sprite.vframes == 6, "M4-2 Test 17: Missing role sheet falls back to idle sheet")
	r_actor.use_role_sheets = true

	# 18. Missing base sheet falls back to citizen.png
	r_actor.use_base_sheet = false
	r_actor.sync_presentation(Vector2(100, 100), false, 0, false, true, 0.2, 48.0)
	_assert_true(r_actor.active_sheet_id == "citizen" and r_actor.sprite.hframes == 1 and r_actor.sprite.vframes == 1, "M4-2 Test 18: Missing base sheet falls back to citizen.png")
	r_actor.use_base_sheet = true

	# 19. Pause freezes all role animations
	r_actor.bind_villager("stl_m4", "npc_p1", "neutral_tribe", "woodcutter")
	pres_res.reset()
	pres_res.presentation_state = WorkerPresentationResolverScript.State.WORKING_AT_TARGET
	r_actor.set_worker_presentation_metadata(pres_res)
	r_actor.sync_presentation(Vector2(100, 100), false, 0, false, true, 0.0, 48.0)
	r_actor.sync_presentation(Vector2(100, 100), false, 0, false, true, 0.25, 48.0) # frame 1 at 4.5 FPS
	var frozen_fc := r_actor.sprite.frame_coords
	r_actor.sync_presentation(Vector2(100, 100), false, 0, false, true, 0.0, 48.0)
	_assert_true(r_actor.sprite.frame_coords == frozen_fc and frozen_fc.x > 0, "M4-2 Test 19: Pause (anim_delta == 0.0) freezes role animation")

	# 20. 2x/3x speed scales role animations correctly
	r_actor.bind_villager("stl_m4", "npc_spd", "neutral_tribe", "farmer")
	r_actor.set_worker_presentation_metadata(pres_res)
	r_actor.sync_presentation(Vector2(100, 100), false, 0, false, true, 0.0, 48.0) # Frame 0 (4 FPS)
	r_actor.sync_presentation(Vector2(100, 100), false, 0, false, true, 0.125 * 2.0, 48.0) # 2x speed: 0.25s -> Frame 1
	var fc_2x := r_actor.sprite.frame_coords.x
	r_actor.sync_presentation(Vector2(100, 100), false, 0, false, true, 0.084 * 3.0, 48.0) # +0.252s -> total 0.502s -> Frame 2
	var fc_3x := r_actor.sprite.frame_coords.x
	_assert_true(fc_2x == 1 and fc_3x == 2, "M4-2 Test 20: 2x/3x speed scales Farmer Work animation (2x->f%d, 3x->f%d)" % [fc_2x, fc_3x])

	# 21-24. Controller verification: no canonical mutation, Fog gating, Actor cap <= 48, Near/Mid/Far LOD
	var snaps_m42_before := []
	for vv in ctx.get_all_villagers_cached_view():
		snaps_m42_before.append(vv.to_dict())
	pres.debug_fog_disabled = false
	pres.update_presentation(0.05, 2.0)
	var fog_actors: int = pres.get_actor_pool().get_active_count()
	pres.debug_fog_disabled = true
	pres.update_presentation(0.05, 3.0)
	var active_actors_3x: int = pres.get_actor_pool().get_active_count()
	var snaps_m42_after := []
	for vv in ctx.get_all_villagers_cached_view():
		snaps_m42_after.append(vv.to_dict())
	var same_canonical := (snaps_m42_before.size() == snaps_m42_after.size())
	if same_canonical:
		for i in range(snaps_m42_before.size()):
			if snaps_m42_before[i] != snaps_m42_after[i]:
				same_canonical = false
				break
	_assert_true(same_canonical, "M4-2 Test 21: Zero canonical simulation or economy mutation")
	_assert_eq(fog_actors, 0, "M4-2 Test 22: Fog gating keeps active_actors == 0")
	_assert_true(active_actors_3x > 0 and active_actors_3x <= 48, "M4-2 Test 23: Actor cap remains <= 48 (%d)" % active_actors_3x)
	var b_metrics: Dictionary = pres.get_benchmark_metrics()
	_assert_true(b_metrics.get("active_actors", 0) <= 48 and b_metrics.has("near_count") and b_metrics.has("mid_count"), "M4-2 Test 24: Near/Mid/Far LOD metrics preserved")

	print("\n====================================================================")
	print("  TEST SUITE: M4-3 Directional Facing, Grounding & Final Integration")
	print("====================================================================")

	# 1. Base Front vs Back orientation rows (E/SE/S/SW/W -> Front Row 0/1, NW/N/NE -> Back Row 2/3)
	r_actor.bind_villager("stl_m4", "npc_dir_1", "neutral_tribe", "farmer")
	pres_res.reset()
	r_actor.set_worker_presentation_metadata(pres_res)
	r_actor.sync_presentation(Vector2(100, 100), false, 1, false, true, 0.0, 48.0) # SE -> Front Idle Row 0
	_assert_true(not r_actor.is_back_facing and r_actor.sprite.frame_coords.y == 0 and not r_actor.sprite.flip_h, "M4-3 Dir: SE stationary -> Front Idle Row 0, flip_h=false")
	r_actor.sync_presentation(Vector2(102, 100), true, 3, true, true, 0.1, 48.0) # SW -> Front Walk Row 1, flip_h=true
	_assert_true(not r_actor.is_back_facing and r_actor.sprite.frame_coords.y == 1 and r_actor.sprite.flip_h, "M4-3 Dir: SW moving -> Front Walk Row 1, flip_h=true")
	r_actor.sync_presentation(Vector2(102, 98), false, 7, false, true, 0.0, 48.0) # NE -> Back Idle Row 2, flip_h=false
	_assert_true(r_actor.is_back_facing and r_actor.sprite.frame_coords.y == 2 and not r_actor.sprite.flip_h, "M4-3 Dir: NE stationary -> Back Idle Row 2, flip_h=false")
	r_actor.sync_presentation(Vector2(100, 96), true, 5, true, true, 0.1, 48.0) # NW -> Back Walk Row 3, flip_h=true
	_assert_true(r_actor.is_back_facing and r_actor.sprite.frame_coords.y == 3 and r_actor.sprite.flip_h, "M4-3 Dir: NW moving -> Back Walk Row 3, flip_h=true")
	r_actor.sync_presentation(Vector2(100, 94), true, 6, true, true, 0.1, 48.0) # N -> preserves Back Walk Row 3 & flip_h=true
	_assert_true(r_actor.is_back_facing and r_actor.sprite.frame_coords.y == 3 and r_actor.sprite.flip_h, "M4-3 Dir: N moving -> preserves Back Walk Row 3 & flip_h")

	# 2. Role work Front (Row 4) vs Back (Row 5) + offset/anchor stability
	for role_name in ["farmer", "woodcutter", "hunter", "guard"]:
		var st_val: int = WorkerPresentationResolverScript.State.GUARDING if role_name == "guard" else WorkerPresentationResolverScript.State.WORKING_AT_TARGET
		r_actor.bind_villager("stl_m4", "npc_role_%s" % role_name, "rival_military", role_name)
		pres_res.reset()
		pres_res.presentation_state = st_val
		pres_res.has_valid_focus = true
		r_actor.set_worker_presentation_metadata(pres_res)
		r_actor.sync_presentation(Vector2(120, 120), false, 1, false, true, 0.0, 48.0)
		var front_ok: bool = (not r_actor.is_back_facing and r_actor.sprite.frame_coords.y == 4 and r_actor.sprite.offset == RivalVillagerActorScript.BASE_SPRITE_OFFSET)
		r_actor.sync_presentation(Vector2(120, 120), true, 5, false, true, 0.0, 48.0)
		var back_ok: bool = (r_actor.is_back_facing and r_actor.sprite.frame_coords.y == 5 and r_actor.sprite.flip_h and r_actor.sprite.offset == RivalVillagerActorScript.BASE_SPRITE_OFFSET)
		_assert_true(front_ok and back_ok, "M4-3 Role %s: Front Row 4 / Back Row 5 + anchor (-16,-33) preserved" % role_name)

	# 3. Hauler carry Front (Row 6/4) vs Back (Row 7/5) including INVALID_TARGET
	r_actor.bind_villager("stl_m4", "npc_haul_dir", "rival_merchant", "hauler")
	pres_res.reset()
	pres_res.presentation_state = WorkerPresentationResolverScript.State.TRANSPORT_LOADED
	pres_res.transport_loaded = true
	r_actor.set_worker_presentation_metadata(pres_res)
	r_actor.sync_presentation(Vector2(140, 140), false, 7, false, true, 0.0, 48.0)
	_assert_true(r_actor.active_anim_name == "carry_idle" and r_actor.sprite.frame_coords.y == 7, "M4-3 Hauler: Back loaded stationary -> Row 7 (Back Carry Idle)")
	r_actor.sync_presentation(Vector2(140, 138), true, 5, true, true, 0.1, 48.0)
	_assert_true(r_actor.active_anim_name == "carry_walk" and r_actor.sprite.frame_coords.y == 5 and r_actor.sprite.flip_h, "M4-3 Hauler: Back loaded moving NW -> Row 5 (Back Carry Walk, flip_h=true)")
	pres_res.presentation_state = WorkerPresentationResolverScript.State.INVALID_TARGET
	r_actor.set_worker_presentation_metadata(pres_res)
	r_actor.sync_presentation(Vector2(140, 138), false, 7, false, true, 0.0, 48.0)
	_assert_true(r_actor.active_anim_name == "carry_idle" and r_actor.sprite.frame_coords.y == 7, "M4-3 Hauler: Back loaded + INVALID_TARGET -> Row 7 (Back Carry Idle)")

	# 4. Pool rebind resets is_back_facing
	r_actor.release_binding()
	_assert_true(not r_actor.is_back_facing and r_actor.sprite.frame_coords == Vector2i.ZERO, "M4-3 Pool Release: resets is_back_facing=false")

	r_actor.free()
	pres.queue_free()
	pool_cont.queue_free()
	cam.queue_free()
	await process_frame

	print("\n--------------------------------------------------------------------")
	print("  Results: %d passed, %d failed" % [_passed, _failed])
	print("====================================================================")
	quit(0 if _failed == 0 else 1)
