extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — RISK-008: Truthful Offensive Campaign Outcome Feedback
## Authoritative Coverage: TC-FEEDBACK.1 through TC-FEEDBACK.8 with Fail-Closed Assertions

const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")

class MockCampaignManagerDouble extends Node:
	var next_result: Dictionary = {}
	var last_targeted_faction: String = ""

	func launch_offensive_campaign(faction_id: String) -> Dictionary:
		last_targeted_faction = faction_id
		return next_result

class MockBattleReportObject:
	var victor: String = ""
	var attacker_casualties: int = 0
	var defender_casualties: int = 0

	func _init(v: String = "") -> void:
		victor = v

var frame_count: int = 0
var world_instance: Node = null
var hud: Node = null
var mock_campaign_mgr: MockCampaignManagerDouble = null
var all_passed: bool = true
var test_results: Array[Dictionary] = []

func _init() -> void:
	print("\n========================================================")
	print("  STARTING RISK-008 CAMPAIGN RESULT FEEDBACK TEST SUITE")
	print("========================================================\n")
	world_instance = WorldViewScene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count == 3:
		_run_all_tests()
	return false

func _record(test_id: String, passed: bool, message: String) -> void:
	test_results.append({"id": test_id, "passed": passed, "message": message})
	if passed:
		print("  [PASS] %s: %s" % [test_id, message])
	else:
		printerr("  [FAIL] %s: %s" % [test_id, message])
		all_passed = false

func _run_all_tests() -> void:
	hud = world_instance.hud
	if hud == null:
		printerr("FATAL: HUD node is null in WorldView instance")
		quit(1)
		return

	mock_campaign_mgr = MockCampaignManagerDouble.new()
	world_instance.add_child(mock_campaign_mgr)

	_test_tc_feedback_1_attacker_victory()
	_test_tc_feedback_2_defender_victory_player_defeat()
	_test_tc_feedback_3_stalemate_draw()
	_test_tc_feedback_4_launch_failure()
	_test_tc_feedback_5_unknown_or_missing_report()
	_test_tc_feedback_6_campaign_manager_null()
	_test_tc_feedback_7_battle_report_object_duck_typing()
	_test_tc_feedback_8_end_to_end_banner_visibility()

	print("\n--------------------------------------------------------")
	var passed_count: int = 0
	for res in test_results:
		if res.get("passed", false):
			passed_count += 1
	print("  RISK-008 RESULTS: %d / %d Tests Passed" % [passed_count, test_results.size()])
	if all_passed and passed_count == 8:
		print("  ALL 8 RISK-008 CAMPAIGN RESULT FEEDBACK TESTS PASSED! (Exit Code 0)")
		print("--------------------------------------------------------\n")
		quit(0)
	else:
		print("  RISK-008 TESTS FAILED! (Exit Code 1)")
		print("--------------------------------------------------------\n")
		quit(1)

# -----------------------------------------------------------------------------
# TC-FEEDBACK.1: Victor is "attacker" -> Positive Victory Banner & Feedback
# -----------------------------------------------------------------------------
func _test_tc_feedback_1_attacker_victory() -> void:
	hud.battle_campaign_mgr = mock_campaign_mgr
	mock_campaign_mgr.next_result = {
		"success": true,
		"report": {
			"victor": "attacker",
			"attacker_casualties": 1,
			"defender_casualties": 8
		}
	}

	var res: Dictionary = hud.attack_faction("target_faction_1")

	var banner_title: Label = hud.event_title
	var banner_desc: Label = hud.event_desc
	var fb_msg: String = hud._diplomacy_feedback_message
	var fb_err: bool = hud._diplomacy_feedback_is_error

	var ok: bool = (
		res.get("success", false) == true
		and banner_title.text == "Chiến Thắng!"
		and banner_title.modulate == Color(0.2, 1.0, 0.4)
		and fb_msg.contains("Thắng trận")
		and not fb_err
	)
	_record("TC-FEEDBACK.1", ok, "Attacker victory displays green 'Chiến Thắng!' banner and success feedback")

# -----------------------------------------------------------------------------
# TC-FEEDBACK.2: Victor is "defender" -> Negative Defeat Banner & Error Feedback
# -----------------------------------------------------------------------------
func _test_tc_feedback_2_defender_victory_player_defeat() -> void:
	hud.battle_campaign_mgr = mock_campaign_mgr
	mock_campaign_mgr.next_result = {
		"success": true,
		"report": {
			"victor": "defender",
			"attacker_casualties": 10,
			"defender_casualties": 2
		}
	}

	var res: Dictionary = hud.attack_faction("target_faction_2")

	var banner_title: Label = hud.event_title
	var banner_desc: Label = hud.event_desc
	var fb_msg: String = hud._diplomacy_feedback_message
	var fb_err: bool = hud._diplomacy_feedback_is_error

	var ok: bool = (
		res.get("success", false) == true
		and banner_title.text == "Thất Bại Chiến Dịch!"
		and banner_title.modulate == Color(1.0, 0.3, 0.3)
		and fb_msg.contains("Bại trận")
		and fb_err == true
	)
	_record("TC-FEEDBACK.2", ok, "Defender victory (player defeat) truthfully displays red 'Thất Bại Chiến Dịch!' banner and error feedback")

# -----------------------------------------------------------------------------
# TC-FEEDBACK.3: Victor is "draw" / "stalemate" -> Stalemate Feedback
# -----------------------------------------------------------------------------
func _test_tc_feedback_3_stalemate_draw() -> void:
	hud.battle_campaign_mgr = mock_campaign_mgr
	mock_campaign_mgr.next_result = {
		"success": true,
		"report": {
			"victor": "draw",
			"attacker_casualties": 5,
			"defender_casualties": 5
		}
	}

	var res: Dictionary = hud.attack_faction("target_faction_3")

	var banner_title: Label = hud.event_title
	var fb_msg: String = hud._diplomacy_feedback_message
	var fb_err: bool = hud._diplomacy_feedback_is_error

	var ok: bool = (
		banner_title.text == "Bất Phân Thắng Bại"
		and fb_msg.contains("Hòa")
		and not fb_err
	)
	_record("TC-FEEDBACK.3", ok, "Stalemate outcome displays 'Bất Phân Thắng Bại' banner and neutral feedback")

# -----------------------------------------------------------------------------
# TC-FEEDBACK.4: Campaign Launch Fails -> Red Error Banner & Reason Feedback
# -----------------------------------------------------------------------------
func _test_tc_feedback_4_launch_failure() -> void:
	hud.battle_campaign_mgr = mock_campaign_mgr
	mock_campaign_mgr.next_result = {
		"success": false,
		"reason": "Không đủ quân sĩ viễn chinh (yêu cầu tối thiểu 5 lính)."
	}

	var res: Dictionary = hud.attack_faction("target_faction_4")

	var banner_title: Label = hud.event_title
	var banner_desc: Label = hud.event_desc
	var fb_msg: String = hud._diplomacy_feedback_message
	var fb_err: bool = hud._diplomacy_feedback_is_error

	var ok: bool = (
		res.get("success", false) == false
		and banner_title.text == "Không Thể Tấn Công"
		and banner_title.modulate == Color(1.0, 0.3, 0.3)
		and banner_desc.text.contains("Không đủ quân sĩ")
		and fb_msg.contains("Không đủ quân sĩ")
		and fb_err == true
	)
	_record("TC-FEEDBACK.4", ok, "Launch failure displays red 'Không Thể Tấn Công' banner with reason text")

# -----------------------------------------------------------------------------
# TC-FEEDBACK.5: Unknown or Missing Report -> Fail-Closed Neutral (Never Claims Victory)
# -----------------------------------------------------------------------------
func _test_tc_feedback_5_unknown_or_missing_report() -> void:
	hud.battle_campaign_mgr = mock_campaign_mgr
	mock_campaign_mgr.next_result = {
		"success": true,
		"report": {}
	}

	var res: Dictionary = hud.attack_faction("target_faction_5")

	var fb_msg: String = hud._diplomacy_feedback_message
	var banner_title: Label = hud.event_title

	var ok: bool = (
		fb_msg.contains("kết quả chưa xác định")
		and banner_title.text != "Chiến Thắng!"
	)
	_record("TC-FEEDBACK.5", ok, "Missing or unknown victor outcome fails closed to neutral and never falsely claims victory")

# -----------------------------------------------------------------------------
# TC-FEEDBACK.6: battle_campaign_mgr is null -> System Unready Error
# -----------------------------------------------------------------------------
func _test_tc_feedback_6_campaign_manager_null() -> void:
	hud.battle_campaign_mgr = null

	var res: Dictionary = hud.attack_faction("target_faction_6")

	var banner_title: Label = hud.event_title
	var fb_msg: String = hud._diplomacy_feedback_message
	var fb_err: bool = hud._diplomacy_feedback_is_error

	var ok: bool = (
		res.get("success", false) == false
		and banner_title.text == "Không Thể Tấn Công"
		and fb_msg.contains("Hệ thống chiến dịch chưa sẵn sàng")
		and fb_err == true
	)
	_record("TC-FEEDBACK.6", ok, "Null campaign manager gracefully rejects attack with unready error feedback")

# -----------------------------------------------------------------------------
# TC-FEEDBACK.7: BattleReport Object Duck-Typing Support
# -----------------------------------------------------------------------------
func _test_tc_feedback_7_battle_report_object_duck_typing() -> void:
	hud.battle_campaign_mgr = mock_campaign_mgr

	# Test object with victor = "defender"
	var def_report_obj = MockBattleReportObject.new("defender")
	mock_campaign_mgr.next_result = {
		"success": true,
		"report": def_report_obj
	}
	hud.attack_faction("target_faction_7a")
	var ok_def: bool = (hud.event_title.text == "Thất Bại Chiến Dịch!" and hud._diplomacy_feedback_is_error == true)

	# Test object with victor = "attacker"
	var atk_report_obj = MockBattleReportObject.new("attacker")
	mock_campaign_mgr.next_result = {
		"success": true,
		"report": atk_report_obj
	}
	hud.attack_faction("target_faction_7b")
	var ok_atk: bool = (hud.event_title.text == "Chiến Thắng!" and hud._diplomacy_feedback_is_error == false)

	_record("TC-FEEDBACK.7", ok_def and ok_atk, "Object-based BattleReport instances correctly parsed for both victory and defeat")

# -----------------------------------------------------------------------------
# TC-FEEDBACK.8: End-to-End Banner Visibility Verification
# -----------------------------------------------------------------------------
func _test_tc_feedback_8_end_to_end_banner_visibility() -> void:
	hud.battle_campaign_mgr = mock_campaign_mgr
	mock_campaign_mgr.next_result = {
		"success": true,
		"report": {
			"victor": "attacker"
		}
	}
	hud.attack_faction("target_faction_8")

	var banner_visible: bool = hud.event_banner != null and hud.event_banner.visible == true
	_record("TC-FEEDBACK.8", banner_visible, "Event banner control is rendered visible on attack resolution")
