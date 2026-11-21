extends SceneTree
## =============================================================================
## KINGDOMS UNBOUND — Package 2E Live Visual Validation
## Autonomous Faction Conflict & Inter-Faction Warfare UI
## Captures high-fidelity PNG screenshots at 1280x720
## =============================================================================

const WorldViewScene = preload("res://scenes/world/world_view.tscn")

var frame_count: int = 0
var world_inst: Node = null
var hud: Node = null

func _save_screenshot(filename: String) -> void:
	var vp: Viewport = root
	if vp:
		var tex := vp.get_texture()
		if tex:
			var img := tex.get_image()
			if img:
				var path := "docs/visual_validation/" + filename
				var err := img.save_png(path)
				print("[Visual Validation] Saved screenshot: %s (%dx%d, code: %d)" % [path, img.get_width(), img.get_height(), err])

func _init() -> void:
	print("\n========================================================")
	print("  STARTING PACKAGE 2E LIVE VISUAL VALIDATION (1280x720)")
	print("  DisplayServer: ", DisplayServer.get_name())
	print("========================================================\n")

	world_inst = WorldViewScene.instantiate()
	root.add_child(world_inst)

func _process(_delta: float) -> bool:
	frame_count += 1

	if frame_count == 5:
		hud = world_inst.get_node_or_null("HUD")
		var fm = world_inst.get("faction_mgr")
		var bcm = world_inst.get("battle_campaign_mgr")
		if fm != null and bcm != null:
			# Setup real active war and campaign between military and merchant
			fm.declare_war_between_factions("rival_military", "rival_merchant", "Tranh chấp lãnh thổ và bành trướng quân sự", 4)
			bcm.schedule_inter_faction_campaign("rival_military", "rival_merchant", 6, 1)

			# Also setup truce between merchant and neutral tribe
			var rel_tribe = fm.get_pairwise_relation_between("neutral_tribe", "rival_merchant")
			if rel_tribe:
				rel_tribe.truce_until_day = 12

			# Open diplomacy menu
			hud._toggle_diplomacy_menu()

	elif frame_count == 10:
		_save_screenshot("p2e_01_inter_faction_warfare_diplomacy_panel.png")
		# Close diplomacy menu and trigger war banner
		if hud != null:
			var diplo_panel = hud.get_node_or_null("DiplomacyPanel")
			if diplo_panel:
				diplo_panel.visible = false
			hud.show_event_banner("Tin Chiến Sự Thế Giới!", "⚔️ Cổ Thành Thiết Giáp đã chính thức tuyên chiến với Thương Hội Vân Đồn!", false, 10.0)

	elif frame_count == 15:
		_save_screenshot("p2e_02_inter_faction_war_banner.png")
		# Trigger battle result banner
		if hud != null:
			hud.show_event_banner("KẾT QUẢ CHIẾN SỰ: CỔ THÀNH THIẾT GIÁP CHIẾN THẮNG!", "Cổ Thành Thiết Giáp vs Thương Hội Vân Đồn\nQuân đội Cổ Thành Thiết Giáp đã đánh bại đối phương tại cứ điểm tiền tiêu!\n[Thương vong: Phe công mất 2 lính | Phe thủ mất 6 lính | Cướp phá: {'gold': 45}]", false, 10.0)

	elif frame_count == 20:
		_save_screenshot("p2e_03_inter_faction_battle_result_banner.png")
		print("\n[Visual Validation] All Package 2E visual validation captures completed successfully!\n")
		quit(0)
		return true

	return false
