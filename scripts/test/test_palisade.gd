extends SceneTree
## Test Suite: Package 1I — Palisade & Fortification System
## Verifies Blueprint data, 1x1 placement legality, atomic cost deduction,
## construction lifecycle, worker capacity & progress scaling, cancellation & refund,
## GridNavigation obstacle occupancy, Save/Load persistence, fortification helper,
## and HUD / visual node wiring.

const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const ResourceManagerScript = preload("res://scripts/economy/resource_manager.gd")
const BuildingSystemScript = preload("res://scripts/economy/building_system.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const IsoMathScript = preload("res://scripts/utils/iso_math.gd")
const WorldViewScene = preload("res://scenes/world/world_view.tscn")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const BattleResolverScript = preload("res://scripts/combat/battle_resolver.gd")
const JobManagerScript = preload("res://scripts/jobs/job_manager.gd")
const CitizenControllerScript = preload("res://scripts/entities/citizen_controller.gd")

var frame_count: int = 0
var world_instance: Node = null
var failures: int = 0
var old_palisade_ref_for_next_frame: WeakRef = null

func _init() -> void:
	print("\n========================================================")
	print("  TEST SUITE: Package 1I — Palisade & Fortification System")
	print("========================================================\n")

	_run_unit_checks()

	# Instantiate WorldView to allow _ready() initialization across frames
	world_instance = WorldViewScene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1

	if frame_count == 3:
		_run_world_integration_checks()

	if frame_count == 4:
		print("\n--- Verifying Deferred Node Deletion Lifecycle (Frame 4) ---")
		if old_palisade_ref_for_next_frame != null:
			if old_palisade_ref_for_next_frame.get_ref() != null:
				printerr("  [FAIL] Old palisade node was NOT freed by engine after frame step!")
				failures += 1
			else:
				print("  [PASS] Old palisade node completely freed from memory by engine on next frame.")

		print("\n--------------------------------------------------------")
		if failures == 0:
			print("  ALL PACKAGE 1I PALISADE TESTS PASSED! (Exit Code 0)")
			print("--------------------------------------------------------\n")
			quit(0)
			return true
		else:
			printerr("  PACKAGE 1I PALISADE TESTS FAILED with %d failures! (Exit Code 1)" % failures)
			print("--------------------------------------------------------\n")
			quit(1)
			return true

	return false

# -----------------------------------------------------------------------------
# Unit Checks: Blueprint, Placement, Navigation, Fortification
# -----------------------------------------------------------------------------
func _run_unit_checks() -> void:
	# -------------------------------------------------------------------------
	# TC-PA.1: Blueprint & Placement Legality
	# -------------------------------------------------------------------------
	print("--- Running TC-PA.1: Blueprint & Placement Legality ---")
	var bp: Dictionary = EconomyConfigScript.BLUEPRINTS.get("palisade", {})
	if bp.is_empty():
		printerr("  [FAIL] 'palisade' blueprint missing from EconomyConfig.BLUEPRINTS!")
		failures += 1
	else:
		if bp.get("id") != "palisade":
			printerr("  [FAIL] Blueprint ID is '%s', expected 'palisade'" % bp.get("id"))
			failures += 1
		if bp.get("name_vi") != "Tường Rào Phòng Ngự":
			printerr("  [FAIL] Display name is '%s', expected 'Tường Rào Phòng Ngự'" % bp.get("name_vi"))
			failures += 1
		if bp.get("footprint") != Vector2i(1, 1):
			printerr("  [FAIL] Footprint is %s, expected Vector2i(1, 1)" % str(bp.get("footprint")))
			failures += 1
		var cost: Dictionary = bp.get("cost", {})
		if cost.get(EconomyConfigScript.RES_WOOD) != 4 or cost.get(EconomyConfigScript.RES_STONE) != 2:
			printerr("  [FAIL] Cost mismatch! Expected 4 Wood, 2 Stone. Got: %s" % str(cost))
			failures += 1
		if bp.get("construction_hours", 0.0) != 3.0:
			printerr("  [FAIL] Construction hours is %f, expected 3.0" % bp.get("construction_hours"))
			failures += 1
		if bp.get("housing_capacity", -1) != 0:
			printerr("  [FAIL] housing_capacity should be 0, got %d" % bp.get("housing_capacity"))
			failures += 1
		if not bp.get("storage_bonus", {}).is_empty():
			printerr("  [FAIL] storage_bonus should be empty, got %s" % str(bp.get("storage_bonus")))
			failures += 1
		if bp.get("max_workers", -1) != 0:
			printerr("  [FAIL] max_workers should be 0, got %d" % bp.get("max_workers"))
			failures += 1
		if bp.get("job_type", "none") != "":
			printerr("  [FAIL] job_type should be empty, got '%s'" % bp.get("job_type"))
			failures += 1
		print("  [PASS] Blueprint 'palisade' verified: 1x1, 4 Wood + 2 Stone, 3.0h, 0 workers, defensive structure.")

	# Placement legality checks
	var world_data = WorldGeneratorScript.generate(55555)
	var rm = ResourceManagerScript.new()
	rm.reset_economy()
	# Set baseline resources
	rm._current_stock[EconomyConfigScript.RES_WOOD] = 20
	rm._current_stock[EconomyConfigScript.RES_STONE] = 10

	var test_cell := Vector2i(20, 20)
	world_data.terrain[test_cell.x][test_cell.y] = WorldGeneratorScript.TerrainType.GRASS
	world_data.occupancy[test_cell.x][test_cell.y] = false

	# 1. Null ResourceManager check (fail closed)
	var null_rm_res = BuildingSystemScript.can_place_building("palisade", test_cell, world_data, null)
	if null_rm_res.get("valid", true):
		printerr("  [FAIL] can_place_building should fail closed when resource_mgr is null!")
		failures += 1
	var null_rm_place = BuildingSystemScript.place_building("palisade", test_cell, world_data, null)
	if null_rm_place.get("success", true):
		printerr("  [FAIL] place_building should fail closed when resource_mgr is null!")
		failures += 1

	# 2. Insufficient resources check (fail closed without deductions)
	rm._current_stock[EconomyConfigScript.RES_WOOD] = 3 # needs 4
	rm._current_stock[EconomyConfigScript.RES_STONE] = 1 # needs 2
	var poor_res = BuildingSystemScript.can_place_building("palisade", test_cell, world_data, rm)
	if poor_res.get("valid", true):
		printerr("  [FAIL] can_place_building should reject when unaffordable!")
		failures += 1
	var poor_place = BuildingSystemScript.place_building("palisade", test_cell, world_data, rm)
	if poor_place.get("success", true):
		printerr("  [FAIL] place_building should reject when unaffordable!")
		failures += 1
	if rm.get_available_stock(EconomyConfigScript.RES_WOOD) != 3 or rm.get_available_stock(EconomyConfigScript.RES_STONE) != 1:
		printerr("  [FAIL] Resource leakage on failed placement!")
		failures += 1

	# 3. Water terrain rejection
	rm._current_stock[EconomyConfigScript.RES_WOOD] = 20
	rm._current_stock[EconomyConfigScript.RES_STONE] = 10
	world_data.terrain[test_cell.x][test_cell.y] = WorldGeneratorScript.TerrainType.WATER
	var water_res = BuildingSystemScript.place_building("palisade", test_cell, world_data, rm)
	if water_res.get("success", true):
		printerr("  [FAIL] Palisade placement on water was erroneously accepted!")
		failures += 1
	world_data.terrain[test_cell.x][test_cell.y] = WorldGeneratorScript.TerrainType.GRASS

	# 4. Out of bounds rejection
	var oob_cell := Vector2i(-1, 20)
	var oob_res = BuildingSystemScript.place_building("palisade", oob_cell, world_data, rm)
	if oob_res.get("success", true):
		printerr("  [FAIL] Out of bounds placement was erroneously accepted!")
		failures += 1

	# 5. Occupied cell rejection
	world_data.occupancy[test_cell.x][test_cell.y] = true
	var occ_res = BuildingSystemScript.place_building("palisade", test_cell, world_data, rm)
	if occ_res.get("success", true):
		printerr("  [FAIL] Placement on occupied cell was erroneously accepted!")
		failures += 1
	world_data.occupancy[test_cell.x][test_cell.y] = false

	# 6. Legal placement: cost deducted atomically & occupancy marked
	var wood_before := rm.get_available_stock(EconomyConfigScript.RES_WOOD)
	var stone_before := rm.get_available_stock(EconomyConfigScript.RES_STONE)
	var place_res = BuildingSystemScript.place_building("palisade", test_cell, world_data, rm)
	if not place_res.get("success", false):
		printerr("  [FAIL] Legal palisade placement failed: %s" % place_res.get("reason", "unknown"))
		failures += 1
	else:
		var b: Dictionary = place_res.get("building", {})
		if b.get("state") != "under_construction":
			printerr("  [FAIL] Placed palisade state should be 'under_construction', got '%s'" % b.get("state"))
			failures += 1
		if b.get("construction_progress") != 0.0:
			printerr("  [FAIL] Initial construction_progress should be 0.0, got %f" % b.get("construction_progress"))
			failures += 1
		if b.get("construction_hours") != 3.0:
			printerr("  [FAIL] Initial construction_hours should be 3.0, got %f" % b.get("construction_hours"))
			failures += 1
		if rm.get_available_stock(EconomyConfigScript.RES_WOOD) != wood_before - 4 or rm.get_available_stock(EconomyConfigScript.RES_STONE) != stone_before - 2:
			printerr("  [FAIL] Atomic cost deduction failed! Wood: %d->%d, Stone: %d->%d" % [wood_before, rm.get_available_stock(EconomyConfigScript.RES_WOOD), stone_before, rm.get_available_stock(EconomyConfigScript.RES_STONE)])
			failures += 1
		if not world_data.occupancy[test_cell.x][test_cell.y]:
			printerr("  [FAIL] 1x1 footprint cell was not marked occupied!")
			failures += 1
		print("  [PASS] Legal palisade placement accepted: state='under_construction', 4W+2S deducted, 1x1 cell occupied.")

	# -------------------------------------------------------------------------
	# TC-PA.4: Navigation & Obstacle Occupancy
	# -------------------------------------------------------------------------
	print("\n--- Running TC-PA.4: Navigation and Occupancy ---")
	var nav := GridNavigation.new(world_data)
	# The placed palisade cell must be unwalkable
	if nav.is_cell_walkable(test_cell):
		printerr("  [FAIL] Palisade cell %s is walkable in GridNavigation!" % str(test_cell))
		failures += 1
	else:
		print("  [PASS] Palisade cell is strictly unwalkable in GridNavigation.")

	# A* pathfinding routes around the palisade obstacle
	var start_cell := Vector2i(19, 20)
	var end_cell := Vector2i(21, 20)
	for cx in range(18, 23):
		for cy in range(18, 23):
			world_data.terrain[cx][cy] = WorldGeneratorScript.TerrainType.GRASS
			world_data.occupancy[cx][cy] = false
	# Keep palisade obstacle cell occupied
	world_data.occupancy[test_cell.x][test_cell.y] = true

	var path := nav.find_path(start_cell, end_cell)
	if path.is_empty():
		printerr("  [FAIL] Pathfinding failed to find bypass around single palisade!")
		failures += 1
	else:
		var traversed_palisade := false
		for step in path:
			if step == test_cell:
				traversed_palisade = true
		if traversed_palisade:
			printerr("  [FAIL] Path traversed directly through solid palisade obstacle!")
			failures += 1
		else:
			print("  [PASS] Pathfinding successfully routed around palisade obstacle (%d steps)." % path.size())

	# -------------------------------------------------------------------------
	# TC-PA.6: Defensive Fortification Integration
	# -------------------------------------------------------------------------
	print("\n--- Running TC-PA.6: Defensive Fortification Integration ---")
	var fort_world_data := WorldGeneratorScript.generate(99999)
	fort_world_data.buildings.clear()

	# 0 palisades -> level 0
	var f_lvl_0 = BuildingSystemScript.calculate_fortification_level(fort_world_data)
	if f_lvl_0 != 0:
		printerr("  [FAIL] 0 palisades should yield level 0, got %d" % f_lvl_0)
		failures += 1
	var br_lvl_0 = BattleResolverScript.calculate_settlement_fortification_level(fort_world_data)
	if br_lvl_0 != 0:
		printerr("  [FAIL] BattleResolver helper mismatch for 0 palisades, got %d" % br_lvl_0)
		failures += 1

	# Add 1 active palisade -> level 1
	fort_world_data.buildings.append({
		"id": "bld_palisade_10_10",
		"type": "palisade",
		"cell": Vector2i(10, 10),
		"size": Vector2i(1, 1),
		"state": "active"
	})
	var f_lvl_1 = BuildingSystemScript.calculate_fortification_level(fort_world_data)
	if f_lvl_1 != 1:
		printerr("  [FAIL] 1 active palisade should yield level 1, got %d" % f_lvl_1)
		failures += 1

	# Add 3 under_construction palisades -> must NOT increase fortification level
	for i in range(3):
		fort_world_data.buildings.append({
			"id": "bld_palisade_1%d_11" % i,
			"type": "palisade",
			"cell": Vector2i(10 + i, 11),
			"size": Vector2i(1, 1),
			"state": "under_construction"
		})
	if BuildingSystemScript.calculate_fortification_level(fort_world_data) != 1:
		printerr("  [FAIL] Under-construction palisades improperly counted toward fortification level!")
		failures += 1
	else:
		print("  [PASS] Under-construction palisades strictly ignored in fortification calculation.")

	# Add duplicate building record at same cell (10, 10) -> must NOT inflate
	fort_world_data.buildings.append({
		"id": "bld_palisade_10_10_dup",
		"type": "palisade",
		"cell": Vector2i(10, 10),
		"size": Vector2i(1, 1),
		"state": "active"
	})
	if BuildingSystemScript.calculate_fortification_level(fort_world_data) != 1:
		printerr("  [FAIL] Duplicate building record at same cell inflated fortification level!")
		failures += 1
	else:
		print("  [PASS] Duplicate records at identical coordinates safely deduplicated.")

	# Add active palisades up to 5 total distinct cells -> level 2
	for i in range(1, 5):
		fort_world_data.buildings.append({
			"id": "bld_palisade_10_%d" % (10 + i),
			"type": "palisade",
			"cell": Vector2i(10, 10 + i),
			"size": Vector2i(1, 1),
			"state": "active"
		})
	var f_lvl_2 = BuildingSystemScript.calculate_fortification_level(fort_world_data)
	if f_lvl_2 != 2:
		printerr("  [FAIL] 5 active palisades should yield level 2, got %d" % f_lvl_2)
		failures += 1
	else:
		print("  [PASS] 5 active palisades scaled to level 2.")

	# Add active palisades up to 12 total distinct cells -> level 3 (clamped)
	for i in range(5, 12):
		fort_world_data.buildings.append({
			"id": "bld_palisade_10_%d" % (10 + i),
			"type": "palisade",
			"cell": Vector2i(10, 10 + i),
			"size": Vector2i(1, 1),
			"state": "active"
		})
	var f_lvl_3 = BuildingSystemScript.calculate_fortification_level(fort_world_data)
	if f_lvl_3 != 3:
		printerr("  [FAIL] 12 active palisades should yield level 3, got %d" % f_lvl_3)
		failures += 1
	else:
		print("  [PASS] 12 active palisades scaled and clamped strictly to maximum level 3.")

	# Verify BattleResolver with calculated fortification bonus
	var def_force := {
		"troops": 20,
		"equipment_tier": 1,
		"morale": 70.0,
		"fortification_level": f_lvl_3,
		"terrain_multiplier": 1.0
	}
	var atk_force := {
		"troops": 20,
		"equipment_tier": 1,
		"morale": 70.0
	}
	var battle_rep = BattleResolverScript.resolve_battle(atk_force, def_force, 12345)
	if battle_rep.details.get("fortification_bonus", 1.0) != 1.90:
		printerr("  [FAIL] BattleResolver did not apply level 3 fortification bonus (1.90), got %f" % battle_rep.details.get("fortification_bonus", 1.0))
		failures += 1
	else:
		print("  [PASS] BattleResolver applied correct fortification bonus (+90%%) for calculated level 3.")

	# Null world_data safely returns 0
	if BuildingSystemScript.calculate_fortification_level(null) != 0:
		printerr("  [FAIL] Null world_data should yield level 0!")
		failures += 1

	print("  [PASS] TC-PA.6 PASSED.")

# -----------------------------------------------------------------------------
# World Integration Checks: Lifecycle, Cancellation, Save/Load, HUD
# -----------------------------------------------------------------------------
func _run_world_integration_checks() -> void:
	print("\n========================================================")
	print("  RUNNING WORLD INTEGRATION & LIFECYCLE CHECKS")
	print("========================================================\n")

	var world_data = world_instance.get("world_data")
	var rm: Node = world_instance.get_node_or_null("/root/ResourceManager")
	var tm: Node = world_instance.get_node_or_null("/root/TimeManager")
	var hud = world_instance.get_node_or_null("HUD")
	var jm = world_instance.get("job_mgr")
	var nav = world_instance.get("nav")

	if world_data == null or rm == null or tm == null or hud == null or jm == null:
		printerr("  [FAIL] Missing vital world dependencies!")
		failures += 1
		return

	# -------------------------------------------------------------------------
	# TC-PA.7: HUD and Scene Wiring
	# -------------------------------------------------------------------------
	print("--- Running TC-PA.7: HUD and Scene Wiring ---")
	var palisade_btn: Button = hud.get_node_or_null("BuildMenuPanel/MarginContainer/VBoxContainer/GridContainer/PalisadeBtn")
	if palisade_btn == null:
		printerr("  [FAIL] PalisadeBtn not found in HUD BuildMenuPanel/MarginContainer/VBoxContainer/GridContainer!")
		failures += 1
	else:
		print("  [PASS] PalisadeBtn found in HUD tree.")
		palisade_btn.pressed.emit()
		if world_instance.get("placing_building_type") != "palisade":
			printerr("  [FAIL] Pressing PalisadeBtn did not set placing_building_type to 'palisade'!")
			failures += 1
		else:
			print("  [PASS] PalisadeBtn correctly initiated placement mode for 'palisade'.")

		var ghost_node: Node2D = world_instance.get("ghost_building_node")
		var ghost_sprite: Sprite2D = world_instance.get("ghost_building_sprite")
		if ghost_node == null or not ghost_node.visible:
			printerr("  [FAIL] Ghost building preview node not visible after PalisadeBtn press!")
			failures += 1
		if ghost_sprite == null or ghost_sprite.texture == null:
			printerr("  [FAIL] Ghost building preview sprite texture is null!")
			failures += 1
		elif ghost_sprite.offset != Vector2(-16.0, -28.0):
			printerr("  [FAIL] Ghost sprite offset mismatch: %s, expected Vector2(-16.0, -28.0)" % str(ghost_sprite.offset))
			failures += 1
		else:
			print("  [PASS] Ghost preview visible with correct texture and offset Vector2(-16.0, -28.0).")

		world_instance.call("_cancel_placement")
		if ghost_node.visible:
			printerr("  [FAIL] Canceling placement did not hide ghost preview!")
			failures += 1
		else:
			print("  [PASS] Placement canceled cleanly and ghost preview hidden.")

	# WorldView texture and display name checks
	if not world_instance.get("building_textures").has("palisade"):
		printerr("  [FAIL] WorldView building_textures missing 'palisade' entry!")
		failures += 1
	var disp_name: String = world_instance.call("_get_building_display_name", "palisade")
	if disp_name != "Tường Rào Phòng Ngự (1x1)":
		printerr("  [FAIL] _get_building_display_name('palisade') is '%s', expected 'Tường Rào Phòng Ngự (1x1)'" % disp_name)
		failures += 1
	else:
		print("  [PASS] WorldView display name for 'palisade' verified: '%s'" % disp_name)

	# -------------------------------------------------------------------------
	# TC-PA.2: Construction Lifecycle
	# -------------------------------------------------------------------------
	print("\n--- Running TC-PA.2: Construction Lifecycle ---")
	# 1. Capacity check: 1x1 palisade worker capacity must be 2
	var cap_worker := BuildingSystemScript.get_construction_worker_capacity("palisade")
	if cap_worker != 2:
		printerr("  [FAIL] Worker capacity for 1x1 palisade should be 2, got %d" % cap_worker)
		failures += 1
	else:
		print("  [PASS] Construction worker capacity for palisade (1x1) is strictly 2.")

	# Clear site for placement
	var pal_cell := Vector2i(25, 25)
	world_data.terrain[pal_cell.x][pal_cell.y] = WorldGeneratorScript.TerrainType.GRASS
	world_data.occupancy[pal_cell.x][pal_cell.y] = false
	# Clear perimeter cells
	for n in IsoMathScript.get_cardinal_neighbors(pal_cell):
		world_data.terrain[n.x][n.y] = WorldGeneratorScript.TerrainType.GRASS
		world_data.occupancy[n.x][n.y] = false

	rm._current_stock[EconomyConfigScript.RES_WOOD] = 50
	rm._current_stock[EconomyConfigScript.RES_STONE] = 50

	world_instance.set("placing_building_type", "palisade")
	var place_res = world_instance.call("_execute_placement", pal_cell)
	if not place_res.get("success", false):
		printerr("  [FAIL] _execute_placement for palisade failed: %s" % place_res.get("reason", ""))
		failures += 1
		return

	var b_pal: Dictionary = place_res.get("building", {})
	var b_id: String = b_pal.get("id", "")

	# Verify visual node created with amber modulate
	var b_node_name := "Building_palisade_%d_%d" % [pal_cell.x, pal_cell.y]
	var b_node = world_instance.get("buildings_container").get_node_or_null(b_node_name)
	if b_node == null:
		printerr("  [FAIL] Visual building node '%s' not found under buildings_container!" % b_node_name)
		failures += 1
	else:
		var spr: Sprite2D = b_node.get_node_or_null("Sprite2D")
		if spr == null or spr.modulate != Color(0.8, 0.7, 0.5, 0.7):
			printerr("  [FAIL] Under-construction palisade does not have amber scaffolding modulate!")
			failures += 1
		else:
			print("  [PASS] Visual node instantiated with amber scaffolding modulate.")

	# Verify builder jobs generated: capacity is 2, bounded by walkable perimeter
	var pal_jobs = jm.get_jobs_for_building(b_id)
	if pal_jobs.size() != 2:
		printerr("  [FAIL] Expected 2 builder jobs for palisade, got %d" % pal_jobs.size())
		failures += 1
	else:
		for j in pal_jobs:
			if j.type != "builder" or j.target_building_id != b_id:
				printerr("  [FAIL] Invalid builder job: type=%s, target=%s" % [j.type, j.target_building_id])
				failures += 1
		print("  [PASS] Exactly 2 valid builder jobs registered for palisade site.")

	# Verify executability in JobManager
	var job0 = pal_jobs[0]
	jm.set_construction_checker(func(bid: String): return BuildingSystemScript.is_building_under_construction(world_data, bid))
	if not jm._is_job_executable(job0, null, null, Callable(), nav):
		printerr("  [FAIL] Builder job should be executable while palisade is under_construction!")
		failures += 1

	# Progress accumulation: premature completion rejected
	var prem_res: bool = bool(world_instance.call("complete_construction", b_id))
	if prem_res:
		printerr("  [FAIL] Premature complete_construction succeeded at 0%% progress!")
		failures += 1
	else:
		print("  [PASS] Premature completion rejected at 0% progress.")

	# Advance progress partially (1.5 / 3.0 h)
	var adv_part := BuildingSystemScript.advance_construction(b_pal, 1.5, world_data)
	if adv_part.get("completed", false) or b_pal.get("construction_progress") != 1.5:
		printerr("  [FAIL] Partial advancement error: %s" % str(adv_part))
		failures += 1
	var prem_part: bool = bool(world_instance.call("complete_construction", b_id))
	if prem_part:
		printerr("  [FAIL] Premature complete_construction succeeded at 50%% progress!")
		failures += 1
	else:
		print("  [PASS] Premature completion rejected at 50% progress.")

	# Negative delta rejected
	var neg_adv := BuildingSystemScript.advance_construction(b_pal, -1.0, world_data)
	if neg_adv.get("success", true) or b_pal.get("construction_progress") != 1.5:
		printerr("  [FAIL] Negative delta was not rejected fail-closed!")
		failures += 1
	else:
		print("  [PASS] Negative progress delta safely rejected without decreasing progress.")

	# Advance to completion (add 1.5 h -> 3.0 h)
	var adv_full := BuildingSystemScript.advance_construction(b_pal, 1.5, world_data)
	if not adv_full.get("completed", false):
		printerr("  [FAIL] Construction did not register completed at 3.0 / 3.0 hours!")
		failures += 1

	# Complete construction legitimately
	var comp_res: bool = bool(world_instance.call("complete_construction", b_id))
	if not comp_res:
		printerr("  [FAIL] Legitimate complete_construction failed after full progress achieved!")
		failures += 1
	else:
		if b_pal.get("state") != "active":
			printerr("  [FAIL] Completed palisade state should be 'active', got '%s'" % b_pal.get("state"))
			failures += 1
		# Modulate cleared to normal Color(1, 1, 1, 1)
		var spr: Sprite2D = b_node.get_node_or_null("Sprite2D")
		if spr != null and spr.modulate != Color(1.0, 1.0, 1.0, 1.0):
			printerr("  [FAIL] Completed palisade modulate was not reset to normal!")
			failures += 1
		# Builder jobs cleaned up
		var remaining_jobs = jm.get_jobs_for_building(b_id)
		if not remaining_jobs.is_empty():
			printerr("  [FAIL] Builder jobs were not cleaned up upon construction completion! Remaining: %d" % remaining_jobs.size())
			failures += 1
		else:
			print("  [PASS] Construction completed legitimately: state='active', modulate reset, builder jobs cleaned up.")

	# Repeated completion call is idempotent
	var rep_comp: bool = bool(world_instance.call("complete_construction", b_id))
	if rep_comp:
		printerr("  [FAIL] Repeated complete_construction call returned true on already active building!")
		failures += 1
	else:
		print("  [PASS] Repeated completion call returned false idempotently.")

	# -------------------------------------------------------------------------
	# TC-PA.3: Cancellation and Cleanup
	# -------------------------------------------------------------------------
	print("\n--- Running TC-PA.3: Cancellation and Cleanup ---")
	var cancel_cell := Vector2i(28, 25)
	world_data.terrain[cancel_cell.x][cancel_cell.y] = WorldGeneratorScript.TerrainType.GRASS
	world_data.occupancy[cancel_cell.x][cancel_cell.y] = false
	for n in IsoMathScript.get_cardinal_neighbors(cancel_cell):
		world_data.terrain[n.x][n.y] = WorldGeneratorScript.TerrainType.GRASS
		world_data.occupancy[n.x][n.y] = false

	# Place under-construction palisade
	world_instance.set("placing_building_type", "palisade")
	var cancel_place = world_instance.call("_execute_placement", cancel_cell)
	var b_cancel: Dictionary = cancel_place.get("building", {})
	var cancel_id: String = b_cancel.get("id", "")

	# Create a neighboring building with overlapping textual prefix: bld_palisade_28_250
	var b_prefix_overlap := {
		"id": "bld_palisade_28_250",
		"type": "palisade",
		"cell": Vector2i(32, 25),
		"size": Vector2i(1, 1),
		"state": "under_construction",
		"construction_progress": 0.0,
		"construction_hours": 3.0
	}
	world_data.buildings.append(b_prefix_overlap)
	world_data.occupancy[32][25] = true
	var overlap_job = jm.create_job("builder", Vector2i(32, 26), "Overlap neighbor job", "bld_palisade_28_250", 3.0, 2, false)

	# 1. Missing ResourceManager fails closed
	var cancel_no_rm = BuildingSystemScript.cancel_construction(b_cancel, world_data, null, jm)
	if cancel_no_rm.get("success", true):
		printerr("  [FAIL] Cancellation succeeded when ResourceManager was null!")
		failures += 1
	if not world_data.occupancy[cancel_cell.x][cancel_cell.y]:
		printerr("  [FAIL] Missing RM cancellation modified occupancy!")
		failures += 1

	# 2. Insufficient storage capacity rejects cancellation safely
	# Force capacity lower than refund amount (refund: 2 Wood, 1 Stone)
	var old_wood_cap = rm._capacities["wood"]
	rm._capacities["wood"] = 10
	rm._current_stock["wood"] = 10 # 0 space
	var cancel_no_space = BuildingSystemScript.cancel_construction(b_cancel, world_data, rm, jm)
	if cancel_no_space.get("success", true):
		printerr("  [FAIL] Cancellation succeeded when storage was completely full!")
		failures += 1
	if not world_data.occupancy[cancel_cell.x][cancel_cell.y]:
		printerr("  [FAIL] Full storage cancellation modified occupancy!")
		failures += 1
	rm._capacities["wood"] = old_wood_cap
	rm._current_stock["wood"] = 10 # space available again

	# 3. Successful cancellation
	var wood_prior_cancel: int = int(rm.get_available_stock(EconomyConfigScript.RES_WOOD))
	var stone_prior_cancel: int = int(rm.get_available_stock(EconomyConfigScript.RES_STONE))
	var cancel_res: Dictionary = world_instance.call("cancel_construction_project", cancel_id)
	if not cancel_res.get("success", false):
		printerr("  [FAIL] Valid cancel_construction failed: %s" % cancel_res.get("reason", ""))
		failures += 1
	else:
		# Exact 50% refund: 4 Wood -> 2 Wood, 2 Stone -> 1 Stone
		var wood_now: int = int(rm.get_available_stock(EconomyConfigScript.RES_WOOD))
		var stone_now: int = int(rm.get_available_stock(EconomyConfigScript.RES_STONE))
		if wood_now != wood_prior_cancel + 2 or stone_now != stone_prior_cancel + 1:
			printerr("  [FAIL] Refund mismatch! Wood: %d->%d (+2), Stone: %d->%d (+1)" % [wood_prior_cancel, wood_now, stone_prior_cancel, stone_now])
			failures += 1
		else:
			print("  [PASS] Exact 50% refund credited atomically (+2 Wood, +1 Stone).")

		# Footprint occupancy cleared
		if world_data.occupancy[cancel_cell.x][cancel_cell.y]:
			printerr("  [FAIL] Footprint occupancy was not cleared upon palisade cancellation!")
			failures += 1
		else:
			print("  [PASS] Footprint occupancy cleared upon cancellation.")

		# Jobs removed
		if not jm.get_jobs_for_building(cancel_id).is_empty():
			printerr("  [FAIL] Builder jobs for canceled palisade were not removed!")
			failures += 1

		# Visual node freed
		var cancel_node_name := "Building_palisade_%d_%d" % [cancel_cell.x, cancel_cell.y]
		var c_node = world_instance.get("buildings_container").get_node_or_null(cancel_node_name)
		if c_node != null and not c_node.is_queued_for_deletion():
			printerr("  [FAIL] Visual building node was not queued for deletion upon cancellation!")
			failures += 1
		else:
			print("  [PASS] Visual node queued for deletion upon cancellation.")

		# Overlapping prefix building preserved
		if jm.get_jobs_for_building("bld_palisade_28_250").size() != 1:
			printerr("  [FAIL] Overlapping prefix neighbor jobs were corrupted by cancellation!")
			failures += 1
		else:
			print("  [PASS] Overlapping prefix building and jobs strictly preserved during cancellation.")

	# Cleanup overlap test building
	world_data.buildings.erase(b_prefix_overlap)
	world_data.occupancy[32][25] = false
	jm.remove_jobs_for_building("bld_palisade_28_250")

	# Re-cancellation safely rejected
	var re_cancel = world_instance.call("cancel_construction_project", cancel_id)
	if re_cancel.get("success", false):
		printerr("  [FAIL] Re-cancellation of already canceled palisade succeeded!")
		failures += 1
	else:
		print("  [PASS] Re-cancellation safely rejected without side effects.")

	# -------------------------------------------------------------------------
	# TC-PA.5: Save/Load Persistence
	# -------------------------------------------------------------------------
	print("\n--- Running TC-PA.5: Save/Load Persistence ---")
	# Place one active palisade and one under-construction palisade
	var save_active_cell := Vector2i(15, 15)
	var save_constr_cell := Vector2i(16, 15)
	for x in range(13, 19):
		for y in range(13, 19):
			world_data.terrain[x][y] = WorldGeneratorScript.TerrainType.GRASS
			world_data.occupancy[x][y] = false
			for i in range(world_data.props.size() - 1, -1, -1):
				if world_data.props[i]["cell"] == Vector2i(x, y):
					world_data.props.remove_at(i)

	var b_save_active = {
		"id": "bld_palisade_15_15",
		"type": "palisade",
		"cell": save_active_cell,
		"size": Vector2i(1, 1),
		"state": "active",
		"health": 100,
		"construction_progress": 3.0,
		"construction_hours": 3.0
	}
	var b_save_constr = {
		"id": "bld_palisade_16_15",
		"type": "palisade",
		"cell": save_constr_cell,
		"size": Vector2i(1, 1),
		"state": "under_construction",
		"health": 100,
		"construction_progress": 1.2,
		"construction_hours": 3.0
	}
	world_data.buildings.append(b_save_active)
	world_data.buildings.append(b_save_constr)
	world_data.occupancy[15][15] = true
	world_data.occupancy[16][15] = true
	world_instance.call("_instantiate_building_node", "palisade", save_active_cell, Vector2i(1, 1), "active")
	world_instance.call("_instantiate_building_node", "palisade", save_constr_cell, Vector2i(1, 1), "under_construction")

	# Save world to file
	var test_save_path := "user://test_palisade_save.json"
	var save_res := SaveManagerScript.save_to_file(world_instance, test_save_path)
	if not save_res.get("success", false):
		printerr("  [FAIL] SaveManager.save_to_file failed: %s" % save_res.get("error", ""))
		failures += 1
	else:
		print("  [PASS] World state saved successfully with active and under-construction palisades.")

	# Track active node before reload
	var tracked_node_name := "Building_palisade_15_15"
	var pre_load_node = world_instance.get("buildings_container").get_node_or_null(tracked_node_name)
	if pre_load_node != null:
		old_palisade_ref_for_next_frame = weakref(pre_load_node)

	# Reload from file
	var wood_prior_load: int = int(rm.get_available_stock(EconomyConfigScript.RES_WOOD))
	var stone_prior_load: int = int(rm.get_available_stock(EconomyConfigScript.RES_STONE))
	var load_res: Dictionary = SaveManagerScript.load_from_file(test_save_path)
	if not load_res.get("success", false):
		printerr("  [FAIL] SaveManager.load_from_file failed: %s" % load_res.get("error", ""))
		failures += 1
	else:
		var apply_res: Dictionary = SaveManagerScript.apply_loaded_state_to_world(world_instance, load_res["data"])
		if not apply_res.get("success", false):
			printerr("  [FAIL] SaveManager.apply_loaded_state_to_world failed: %s" % apply_res.get("error", ""))
			failures += 1
		# Verify zero cost deductions on load
		if rm.get_available_stock(EconomyConfigScript.RES_WOOD) != wood_prior_load or rm.get_available_stock(EconomyConfigScript.RES_STONE) != stone_prior_load:
			printerr("  [FAIL] Loading save improperly deducted building costs a second time!")
			failures += 1
		else:
			print("  [PASS] Zero resource deduction on load verified.")

		# Verify restored buildings in world_data
		var reloaded_active = BuildingSystemScript.get_building_by_id("bld_palisade_15_15", world_instance.get("world_data"))
		var reloaded_constr = BuildingSystemScript.get_building_by_id("bld_palisade_16_15", world_instance.get("world_data"))
		if reloaded_active.is_empty() or reloaded_active.get("state") != "active":
			printerr("  [FAIL] Active palisade state not preserved after load!")
			failures += 1
		if reloaded_constr.is_empty() or reloaded_constr.get("state") != "under_construction":
			printerr("  [FAIL] Under-construction palisade state not preserved after load!")
			failures += 1
		elif reloaded_constr.get("construction_progress") != 1.2 or reloaded_constr.get("construction_hours") != 3.0:
			printerr("  [FAIL] Construction progress/hours mismatch after load: prog=%f, hours=%f" % [reloaded_constr.get("construction_progress"), reloaded_constr.get("construction_hours")])
			failures += 1
		else:
			print("  [PASS] Construction progress and hours perfectly restored after load.")

		# Verify visual nodes: zero duplicates
		var b_container = world_instance.get("buildings_container")
		var matching_active_nodes := 0
		var matching_constr_nodes := 0
		for child in b_container.get_children():
			if child.name == "Building_palisade_15_15":
				matching_active_nodes += 1
			elif child.name == "Building_palisade_16_15":
				matching_constr_nodes += 1

		if matching_active_nodes != 1:
			printerr("  [FAIL] Expected exactly 1 active palisade node, found %d (duplicate node bug)!" % matching_active_nodes)
			failures += 1
		elif matching_constr_nodes != 1:
			printerr("  [FAIL] Expected exactly 1 under-construction palisade node, found %d!" % matching_constr_nodes)
			failures += 1
		else:
			print("  [PASS] Zero visual node duplication on reload verified.")

		# Verify builder jobs reconstructed for under_construction palisade
		var reloaded_jobs = world_instance.get("job_mgr").get_jobs_for_building("bld_palisade_16_15")
		if reloaded_jobs.is_empty():
			printerr("  [FAIL] Builder jobs were not reconstructed after load for under-construction palisade!")
			failures += 1
		else:
			print("  [PASS] Builder jobs reconstructed cleanly after reload.")

	# Cleanup test save file
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("test_palisade_save.json"):
		dir.remove("test_palisade_save.json")
	if dir != null and dir.file_exists("test_palisade_save.json.bak"):
		dir.remove("test_palisade_save.json.bak")
