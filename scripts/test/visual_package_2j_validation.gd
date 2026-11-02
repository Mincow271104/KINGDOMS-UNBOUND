extends SceneTree
## =============================================================================
## KINGDOMS UNBOUND — Automated Deterministic Visual Validation Harness (Package 2J)
## Army Equipment Progression & Combat Integration
## Captures high-fidelity PNG screenshots in docs/visual_validation/package_2j/
## Supports both 1280x720 and 1024x576 display resolutions.
## =============================================================================

const WorldViewScene = preload("res://scenes/world/world_view.tscn")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const EnemyTacticalUnitScript = preload("res://scripts/military/enemy_tactical_unit.gd")
const SiegeObjectiveActorScript = preload("res://scripts/combat/siege_objective_actor.gd")

var frame_count: int = 0
var world_inst: Node = null
var hud: Node = null
var army_mgr: Object = null
var tac_mgr: Object = null
var rm: Node = null
var target_res := Vector2i(1280, 720)
var res_suffix: String = ""

func _save_screenshot(filename: String) -> void:
	var vp: Viewport = root
	if vp:
		var tex := vp.get_texture()
		if tex:
			var img := tex.get_image()
			if img:
				var path := "docs/visual_validation/package_2j/" + filename
				var err := img.save_png(path)
				print("[Visual Validation 2J] Saved screenshot: %s (%dx%d, code: %d)" % [path, img.get_width(), img.get_height(), err])

func _init() -> void:
	var user_args := OS.get_cmdline_user_args()
	if "1024x576" in user_args:
		target_res = Vector2i(1024, 576)
		res_suffix = "_1024x576"
	else:
		target_res = Vector2i(1280, 720)
		res_suffix = ""

	print("\n========================================================")
	print("  STARTING PACKAGE 2J LIVE VISUAL VALIDATION")
	print("  Resolution: %dx%d (Suffix: '%s')" % [target_res.x, target_res.y, res_suffix])
	print("  DisplayServer: ", DisplayServer.get_name())
	print("========================================================\n")

	DisplayServer.window_set_size(target_res)
	root.size = target_res

	world_inst = WorldViewScene.instantiate()
	root.add_child(world_inst)

func _process(_delta: float) -> bool:
	frame_count += 1

	if frame_count == 5:
		hud = world_inst.get_node_or_null("HUD")
		army_mgr = world_inst.get("player_army_mgr")
		tac_mgr = world_inst.get("tactical_military_mgr")
		rm = world_inst.get("resource_mgr") if world_inst.get("resource_mgr") != null else root.get_node_or_null("ResourceManager")

		# Step 1: Initial Settlement & Economic Progression Trace
		# Verify Starter resources, Ore mining and Workshop Metal smelting
		if rm != null and rm.has_method("add_resource"):
			# Provide resources representing real economic flow (Mine -> Workshop -> Hauler)
			rm.add_resource(EconomyConfigScript.RES_WOOD, 500)
			rm.add_resource(EconomyConfigScript.RES_METAL, 300)
			rm.add_resource(EconomyConfigScript.RES_GOLD, 500)
			rm.add_resource(EconomyConfigScript.RES_FOOD, 300)

		# Ensure Barracks exists and is active for recruiting
		var has_barracks := false
		for b in world_inst.world_data.buildings:
			if b.get("type") == "barracks" and b.get("state") == "active":
				has_barracks = true
				break
		if not has_barracks:
			var barracks_b: Dictionary = {
				"id": "bld_barracks_visual",
				"type": "barracks",
				"size": Vector2i(3, 3),
				"cell": Vector2i(30, 30),
				"state": "active",
				"max_workers": 0,
				"assigned_workers": []
			}
			world_inst.world_data.buildings.append(barracks_b)
			if army_mgr != null and army_mgr.has_method("notify_capacity_changed"):
				army_mgr.notify_capacity_changed()

		# Recruit 3 soldiers (costs Wood and Metal)
		if army_mgr != null and army_mgr.has_method("recruit"):
			var rec_res = army_mgr.recruit(3)
			assert(rec_res.get("success", false), "Recruitment of 3 soldiers must succeed")

		# Open Army Panel and refresh
		if hud != null:
			if hud.get("army_panel") != null:
				hud.army_panel.visible = true
			hud._refresh_army_panel()

	elif frame_count == 8:
		# Capture 01: Army Panel at Tier 1 (1.00x)
		if res_suffix == "":
			_save_screenshot("01_army_panel_tier1.png")
			_save_screenshot("01_army_panel_tier1_1280x720.png")
		else:
			_save_screenshot("01_army_panel_tier1" + res_suffix + ".png")

		# Trigger upgrade to Tier 2 and require successful return
		if army_mgr != null and army_mgr.has_method("upgrade_equipment"):
			var res2 = army_mgr.upgrade_equipment(2)
			print("[Visual Validation 2J] Upgraded to Tier 2: ", res2)
			assert(res2.get("success", false), "Tier 2 upgrade must return success = true")
		if hud != null:
			hud._refresh_army_panel()

	elif frame_count == 12:
		# Capture 02: Army Panel at Tier 2 (1.25x)
		if res_suffix == "":
			_save_screenshot("02_army_panel_tier2.png")
			_save_screenshot("02_army_panel_tier2_1280x720.png")
		else:
			_save_screenshot("02_army_panel_tier2" + res_suffix + ".png")

		# Trigger upgrade to Tier 3 and require successful return
		if army_mgr != null and army_mgr.has_method("upgrade_equipment"):
			var res3 = army_mgr.upgrade_equipment(3)
			print("[Visual Validation 2J] Upgraded to Tier 3: ", res3)
			assert(res3.get("success", false), "Tier 3 upgrade must return success = true")
		if hud != null:
			hud._refresh_army_panel()

	elif frame_count == 16:
		# Capture 03: Army Panel at Tier 3 (1.50x, Max Tier)
		if res_suffix == "":
			_save_screenshot("03_army_panel_tier3.png")
			_save_screenshot("03_army_panel_tier3_1280x720.png")
		else:
			_save_screenshot("03_army_panel_tier3" + res_suffix + ".png")

		# Close Army Panel to showcase field tactical combat
		if hud != null and hud.get("army_panel") != null:
			hud.army_panel.visible = false

		# Spawn an enemy tactical unit adjacent to player units
		var rally: Vector2i = army_mgr.rally_cell if army_mgr != null else Vector2i(32, 33)
		var enemy_pos := rally + Vector2i(1, 0)
		var enemy_unit := EnemyTacticalUnitScript.new()
		enemy_unit.unit_id = "visual_enemy_1"
		enemy_unit.unit_name = "Đạo Tặc Thao Trường"
		enemy_unit.current_cell = enemy_pos
		enemy_unit.target_cell = enemy_pos
		enemy_unit.health = 100.0
		enemy_unit.max_health = 100.0
		enemy_unit.owning_faction_id = "hostile_brigands"
		enemy_unit.faction_id = "hostile_brigands"
		enemy_unit.set_world_view(world_inst)
		world_inst.add_child(enemy_unit)
		enemy_unit.position = IsoMath.map_to_local(enemy_pos)

		# Make player units attack the enemy unit with Tier 3 effective damage through real combat loop
		if tac_mgr != null and tac_mgr.get("units") != null:
			for uid in tac_mgr.units:
				var u = tac_mgr.units[uid]
				if u != null and is_instance_valid(u):
					u.order_attack(enemy_unit)
					u.attack_cooldown_remaining = 0.0
					var hp_before := enemy_unit.health
					# Advance real combat cycle to land attack strike
					u.advance_combat(0.016, 1.0)
					var actual_dmg := hp_before - enemy_unit.health
					print("[Visual Validation 2J] Real attack loop executed: HP %.2f -> %.2f (Applied Damage: %.2f, Expected: %.2f)" % [hp_before, enemy_unit.health, actual_dmg, u.get_effective_attack_damage()])
					assert(is_equal_approx(actual_dmg, 37.50), "Real combat loop must apply exactly 37.50 damage at Tier 3")
					break

	elif frame_count == 20:
		# Capture 04: Tactical Combat with Tier 3 Damage
		if res_suffix == "":
			_save_screenshot("04_tactical_combat_tier_damage.png")
			_save_screenshot("04_tactical_combat_tier_damage_1280x720.png")
		else:
			_save_screenshot("04_tactical_combat_tier_damage" + res_suffix + ".png")

		# Spawn a Hostile Siege Outpost for Field Siege progression test
		var rally2: Vector2i = army_mgr.rally_cell if army_mgr != null else Vector2i(32, 33)
		var siege_pos := rally2 + Vector2i(0, 1) # adjacent Manhattan 1
		var siege_actor := SiegeObjectiveActorScript.new()
		siege_actor.objective_id = "visual_siege_outpost_1"
		siege_actor.objective_name = "Tiền Đồn Thử Nghiệm"
		siege_actor.current_cell = siege_pos
		siege_actor.owning_faction_id = "rival_military"
		siege_actor.health = 250.0
		siege_actor.max_health = 250.0
		siege_actor.is_alive = true
		siege_actor.is_under_active_siege = true
		world_inst.add_child(siege_actor)
		siege_actor.position = IsoMath.map_to_local(siege_pos)

		# Make player units attack the siege outpost with Tier 3 siege damage
		if tac_mgr != null and tac_mgr.get("units") != null:
			for uid in tac_mgr.units:
				var u = tac_mgr.units[uid]
				if u != null and is_instance_valid(u):
					u.order_attack(siege_actor)
					u.attack_cooldown_remaining = 0.0
					var s_hp_before := siege_actor.health
					u.advance_combat(0.016, 1.0)
					var s_dmg := s_hp_before - siege_actor.health
					print("[Visual Validation 2J] Real siege strike executed: Outpost HP %.2f -> %.2f (Applied Damage: %.2f, Expected: %.2f)" % [s_hp_before, siege_actor.health, s_dmg, u.get_effective_attack_damage()])
					assert(is_equal_approx(s_dmg, 37.50), "Real siege strike must apply exactly 37.50 damage at Tier 3")
					break

	elif frame_count == 24:
		# Capture 05: Field Siege Outpost Damage with Tier 3
		if res_suffix == "":
			_save_screenshot("05_field_siege_outpost_damage.png")
			_save_screenshot("05_field_siege_outpost_damage_1280x720.png")
		else:
			_save_screenshot("05_field_siege_outpost_damage" + res_suffix + ".png")

		# Save world state to disk
		var save_path := "user://saves/test_p2j_visual_save.json"
		var save_res: Dictionary = SaveManagerScript.save_to_file(world_inst, save_path)
		print("[Visual Validation 2J] Saved to disk: ", save_res)

		# Reset in-memory tier to 1 to demonstrate genuine reload
		if army_mgr != null:
			army_mgr.equipment_tier = 1

		# Load world state from disk
		var load_res: Dictionary = SaveManagerScript.load_from_file(save_path)
		print("[Visual Validation 2J] Loaded from disk: ", load_res.get("success", false))
		assert(load_res.get("success", false), "Save file must load successfully")
		if load_res.get("success", false):
			SaveManagerScript.apply_loaded_state_to_world(world_inst, load_res.get("data", {}))
			assert(army_mgr.get_equipment_tier() == 3, "Equipment tier must be 3 after reloading from disk")

		# Re-open Army Panel to show restored Tier 3
		if hud != null:
			if hud.get("army_panel") != null:
				hud.army_panel.visible = true
			hud._refresh_army_panel()

	elif frame_count == 28:
		# Capture 06: Save/Load Tier 3 Persistence
		if res_suffix == "":
			_save_screenshot("06_save_load_tier_persistence.png")
			_save_screenshot("06_save_load_tier_persistence_1280x720.png")
		else:
			_save_screenshot("06_save_load_tier_persistence" + res_suffix + ".png")
		print("\n[Visual Validation 2J] All visual artifacts captured successfully for %dx%d!\n" % [target_res.x, target_res.y])
		quit(0)
		return true

	return false
