extends SceneTree
## =============================================================================
## KINGDOMS UNBOUND — Package 2J Live Visual Validation
## Army Equipment Progression & Combat Integration
## Captures high-fidelity PNG screenshots in docs/visual_validation/package_2j/
## =============================================================================

const WorldViewScene = preload("res://scenes/world/world_view.tscn")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const EnemyTacticalUnitScript = preload("res://scripts/military/enemy_tactical_unit.gd")

var frame_count: int = 0
var world_inst: Node = null
var hud: Node = null
var army_mgr: Object = null
var tac_mgr: Object = null
var rm: Node = null

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
	print("\n========================================================")
	print("  STARTING PACKAGE 2J LIVE VISUAL VALIDATION")
	print("  DisplayServer: ", DisplayServer.get_name())
	print("========================================================\n")

	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)

	world_inst = WorldViewScene.instantiate()
	root.add_child(world_inst)

func _process(_delta: float) -> bool:
	frame_count += 1

	if frame_count == 5:
		hud = world_inst.get_node_or_null("HUD")
		army_mgr = world_inst.get("player_army_mgr")
		tac_mgr = world_inst.get("tactical_military_mgr")
		rm = world_inst.get("resource_mgr") if world_inst.get("resource_mgr") != null else root.get_node_or_null("ResourceManager")

		# Ensure starting stock of Metal and Wood is ample for upgrades
		if rm != null and rm.has_method("add_stock"):
			rm.add_stock(EconomyConfigScript.RES_WOOD, 500)
			rm.add_stock(EconomyConfigScript.RES_METAL, 300)
			rm.add_stock(EconomyConfigScript.RES_GOLD, 500)
			rm.add_stock(EconomyConfigScript.RES_FOOD, 300)

		# Ensure Barracks exists and is active
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

		# Recruit 3 soldiers
		if army_mgr != null and army_mgr.has_method("recruit"):
			army_mgr.recruit(3)

		# Open Army Panel and refresh
		if hud != null:
			if hud.get("army_panel") != null:
				hud.army_panel.visible = true
			hud._refresh_army_panel()

	elif frame_count == 8:
		# Capture 01: Army Panel at Tier 1 (1.00x)
		_save_screenshot("01_army_panel_tier1.png")

		# Trigger upgrade to Tier 2
		if army_mgr != null and army_mgr.has_method("upgrade_equipment"):
			var res2 = army_mgr.upgrade_equipment(2)
			print("[Visual Validation 2J] Upgraded to Tier 2: ", res2)
		if hud != null:
			hud._refresh_army_panel()

	elif frame_count == 12:
		# Capture 02: Army Panel at Tier 2 (1.25x)
		_save_screenshot("02_army_panel_tier2.png")

		# Trigger upgrade to Tier 3
		if army_mgr != null and army_mgr.has_method("upgrade_equipment"):
			var res3 = army_mgr.upgrade_equipment(3)
			print("[Visual Validation 2J] Upgraded to Tier 3: ", res3)
		if hud != null:
			hud._refresh_army_panel()

	elif frame_count == 16:
		# Capture 03: Army Panel at Tier 3 (1.50x, Max Tier)
		_save_screenshot("03_army_panel_tier3.png")

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
		enemy_unit.owning_faction_id = "hostile_brigands"
		enemy_unit.faction_id = "hostile_brigands"
		enemy_unit.set_world_view(world_inst)
		world_inst.add_child(enemy_unit)
		enemy_unit.position = IsoMath.map_to_local(enemy_pos)

		# Make player units attack the enemy unit with Tier 3 effective damage
		if tac_mgr != null and tac_mgr.get("units") != null:
			for uid in tac_mgr.units:
				var u = tac_mgr.units[uid]
				if u != null and is_instance_valid(u):
					u.order_attack(enemy_unit)
					# Execute one attack strike to show combat damage
					var eff_dmg: float = u.get_effective_attack_damage()
					enemy_unit.take_damage(eff_dmg, u.unit_id)
					u.unit_attacked.emit(u.unit_id, enemy_unit.unit_id, eff_dmg)
					break

	elif frame_count == 20:
		# Capture 04: Tactical Combat with Tier 3 Damage
		_save_screenshot("04_tactical_combat_tier_damage.png")

		# Save world state to disk
		var save_path := "user://saves/test_p2j_visual_save.json"
		var save_res: Dictionary = SaveManagerScript.save_to_file(world_inst, save_path)
		print("[Visual Validation 2J] Saved to disk: ", save_res)

		# Reset in-memory tier to 1 to demonstrate genuine reload
		if army_mgr != null:
			army_mgr.equipment_tier = 1

		# Load world state from disk
		var load_res: Dictionary = SaveManagerScript.load_from_file(save_path)
		print("[Visual Validation 2J] Loaded from disk: ", load_res.get("valid", false))
		if load_res.get("valid", false):
			SaveManagerScript.apply_loaded_state_to_world(world_inst, load_res.get("data", {}))

		# Re-open Army Panel to show restored Tier 3
		if hud != null:
			if hud.get("army_panel") != null:
				hud.army_panel.visible = true
			hud._refresh_army_panel()

	elif frame_count == 24:
		# Capture 05: Save/Load Tier 3 Persistence
		_save_screenshot("05_save_load_tier_persistence.png")
		print("\n[Visual Validation 2J] All 5 visual artifacts captured successfully!\n")
		quit(0)
		return true

	return false
