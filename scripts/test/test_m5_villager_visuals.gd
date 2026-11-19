extends SceneTree

const RivalVillagerActorScript = preload("res://scripts/world/rival_villager_actor.gd")
const CitizenControllerScript = preload("res://scripts/entities/citizen_controller.gd")
const TacticalUnitScript = preload("res://scripts/military/tactical_unit.gd")
const EnemyTacticalUnitScript = preload("res://scripts/military/enemy_tactical_unit.gd")
const WorkerPresResolverScript = preload("res://scripts/world/worker_presentation_resolver.gd")

var _passed: int = 0
var _failed: int = 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("  [FAIL] ", msg)

func _run_tests() -> void:
	print("[test_m5_villager_visuals] Starting M5 Villager Production & Integration Suite...")

	var all_roles := [
		"idle", "farmer", "woodcutter", "hunter", "hauler",
		"guard", "soldier", "builder", "miner", "quarryman", "smith"
	]

	# 1. All 11 sprite sheets & layout metadata
	for r in all_roles:
		var tex := EntityVisualRegistry.get_villager_sheet_texture(r)
		var lay := EntityVisualRegistry.get_villager_sheet_layout(r)
		var port := EntityVisualRegistry.get_villager_portrait_texture(r)
		var expected_h := 288 if r == "hauler" else 216
		_assert(tex != null and tex.resource_path.begins_with("res://assets/entities/villagers/"), "Sheet loaded from production villagers dir: " + r)
		_assert(tex != null and tex.get_width() == 192 and tex.get_height() == expected_h, "Sheet exact dimensions (192x%d): %s" % [expected_h, r])
		_assert(int(lay.get("hframes", 0)) == 6, "6-column layout for " + r)
		_assert(port is AtlasTexture and (port as AtlasTexture).region == Rect2(0, 0, 32, 36), "Portrait region is 32x36 frame 0 for " + r)

	# 2. Faction marker color rules
	_assert(EntityVisualRegistry.get_faction_marker_color("player").a == 0.0, "Player has NO faction marker")
	_assert(EntityVisualRegistry.get_faction_marker_color("").a == 0.0, "Empty faction has NO faction marker")
	_assert(EntityVisualRegistry.get_faction_marker_color("rival_military").a == 1.0, "Rival Military has opaque 7x7 marker")
	_assert(EntityVisualRegistry.get_faction_marker_color("rival_merchant").a == 1.0, "Rival Merchant has opaque 7x7 marker")
	_assert(EntityVisualRegistry.get_faction_marker_color("neutral_tribe").a == 1.0, "Neutral Tribe has opaque 7x7 marker")
	_assert(EntityVisualRegistry.get_faction_marker_color("emerging_power").a == 1.0, "Emerging Power has opaque 7x7 marker")

	# 3. RivalVillagerActor integration across all 11 roles, zero body tint, animation, pause, pool reuse
	var actor := RivalVillagerActorScript.new()
	root.add_child(actor)
	var pres_res := WorkerPresResolverScript.PresentationResult.new()
	for r in all_roles:
		actor.bind_villager("stl_m5", "npc_" + r, "rival_merchant", r)
		pres_res.reset()
		pres_res.presentation_state = WorkerPresResolverScript.State.GUARDING if r == "guard" else WorkerPresResolverScript.State.WORKING_AT_TARGET
		pres_res.has_valid_focus = true
		if r == "hauler":
			pres_res.presentation_state = WorkerPresResolverScript.State.TRANSPORT_LOADED
			pres_res.transport_loaded = true
		actor.set_worker_presentation_metadata(pres_res)
		actor.sync_presentation(Vector2(100, 100), false, 1, false, true, 0.0, 48.0)
		_assert(actor.sprite.modulate == Color.WHITE, "RivalVillagerActor zero whole-body tint for " + r)
		_assert(actor.sprite.offset == Vector2(-16.0, -33.0), "RivalVillagerActor foot anchor (-16,-33) for " + r)
		_assert(actor.sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Nearest filter on RivalVillagerActor for " + r)
		_assert(actor.faction_marker_color.a == 1.0, "RivalVillagerActor tracks 7x7 marker color for " + r)
		var work_row_expected := 0 if r == "idle" else (6 if r == "hauler" else 4)
		_assert(actor.sprite.frame_coords.y == work_row_expected, "RivalVillagerActor work/carry row %d for %s" % [work_row_expected, r])

	# Pause & speed scaling
	actor.bind_villager("stl_m5", "npc_spd", "neutral_tribe", "builder")
	pres_res.reset()
	pres_res.presentation_state = WorkerPresResolverScript.State.WORKING_AT_TARGET
	actor.set_worker_presentation_metadata(pres_res)
	actor.sync_presentation(Vector2(100, 100), false, 1, false, true, 0.0, 48.0)
	var f0 := actor.sprite.frame_coords
	actor.sync_presentation(Vector2(100, 100), false, 1, false, true, 0.0, 48.0)
	_assert(actor.sprite.frame_coords == f0, "Pause freezes RivalVillagerActor work frame")
	actor.sync_presentation(Vector2(100, 100), false, 1, false, true, 0.2, 48.0)
	_assert(actor.sprite.frame_coords.x > 0, "Builder work advances across 6-frame arc")
	actor.release_binding()
	_assert(actor.bound_faction_id == "" and actor.faction_marker_color.a == 0.0 and actor.sprite.modulate == Color.WHITE and actor.sprite.frame_coords == Vector2i.ZERO, "Pool release clears marker, tint, and frame cleanly")
	actor.queue_free()

	# 4. Player CitizenController integration (real Citizen.tscn / CitizenController)
	var cit_scene := load("res://scenes/entities/citizen.tscn") as PackedScene
	_assert(cit_scene != null, "citizen.tscn loads cleanly")
	if cit_scene != null:
		for r in all_roles:
			var cit: CitizenController = cit_scene.instantiate() as CitizenController
			cit.citizen_id = "cit_m5_" + r
			cit.role = r
			root.add_child(cit)
			_assert(cit.sprite != null and cit.sprite.texture == EntityVisualRegistry.get_villager_sheet_texture(r), "CitizenController loads M5 sheet for " + r)
			_assert(cit.sprite.offset == Vector2(-16.0, -33.0) and not cit.sprite.centered, "CitizenController foot anchor (-16,-33) for " + r)
			_assert(is_equal_approx(cit.sprite.modulate.r, 1.0) and is_equal_approx(cit.sprite.modulate.g, 1.0) and is_equal_approx(cit.sprite.modulate.b, 1.0), "CitizenController preserves Color.WHITE RGB for " + r)
			_assert(cit.sprite.hframes == 6, "CitizenController uses 6-frame sheet for " + r)
			cit.current_state = CitizenController.State.WORKING
			cit._sync_citizen_visuals(0.2)
			var exp_row := 6 if r == "hauler" else 4
			if r == "hauler":
				cit.current_state = CitizenController.State.HAULING
				cit._sync_citizen_visuals(0.2)
			_assert(cit.sprite.frame_coords.y == exp_row, "CitizenController maps WORKING/HAULING row %d for %s" % [exp_row, r])
			cit.queue_free()

	# 5. Player TacticalUnit & EnemyTacticalUnit integration
	var pu := TacticalUnitScript.new()
	pu.unit_id = "p_u1"
	pu.faction_id = "player"
	root.add_child(pu)
	_assert(pu.sprite != null and pu.sprite.texture == EntityVisualRegistry.get_villager_sheet_texture("soldier"), "Player TacticalUnit uses M5 soldier sheet")
	_assert(pu.sprite.modulate == Color.WHITE, "Player TacticalUnit removes old yellow whole-body tint")
	_assert(pu.sprite.offset == Vector2(-16.0, -33.0) and pu.sprite.hframes == 6, "Player TacticalUnit uses 32x36 6-frame anchor")
	pu.order_state = TacticalUnitScript.OrderState.ATTACKING
	pu._sync_unit_visuals(0.0)
	pu._sync_unit_visuals(0.2)
	_assert(pu.sprite.frame_coords.y == 4 and pu.sprite.frame_coords.x > 0, "Player TacticalUnit maps ATTACKING to Row 4 combat swing")
	pu.queue_free()

	var eu := EnemyTacticalUnitScript.new()
	eu.unit_id = "e_u1"
	eu.owning_faction_id = "rival_military"
	root.add_child(eu)
	_assert(eu.sprite != null and eu.sprite.texture == EntityVisualRegistry.get_villager_sheet_texture("soldier"), "EnemyTacticalUnit uses M5 soldier sheet")
	_assert(eu.sprite.modulate == Color.WHITE, "EnemyTacticalUnit removes old crimson whole-body wash")
	_assert(eu.faction_id == "rival_military" and EntityVisualRegistry.get_faction_marker_color(eu.faction_id).a == 1.0, "EnemyTacticalUnit uses 7x7 faction marker instead of body tint")
	eu.queue_free()

	# 6. Cache stability (zero growth across repeated lookups)
	var cache_before: int = EntityVisualRegistry._texture_cache.size()
	for r in all_roles:
		EntityVisualRegistry.get_villager_sheet_texture(r)
	_assert(EntityVisualRegistry._texture_cache.size() == cache_before, "Shared static texture cache has zero growth on repeated lookups")

	await process_frame
	print("[test_m5_villager_visuals] Passed: %d | Failed: %d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _initialize() -> void:
	call_deferred("_run_tests")
