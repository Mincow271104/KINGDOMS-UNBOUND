extends SceneTree

## =============================================================================
## KINGDOMS UNBOUND — CONTROLLED DEFECT REPAIR PROGRAM
## SESSION 5 TEST SUITE: LEGACY MODIFIERS, TRADE INTEGRATION & VICTORY SETTLEMENT
## Focus: MBL-LEG-01 ('restless_bandits' live caravan route risk integration)
##        MBL-LEG-02 (Victory treasury settlement live kingdom stability gate)
##        MBL-LEG-03 (Settlement multi-file crash consistency verification - ca61815)
## =============================================================================

const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")
const TradeRouteCalculatorScript = preload("res://scripts/trade/trade_route_calculator.gd")
const VictoryManagerScript = preload("res://scripts/core/victory_manager.gd")
const LegacyProfileManagerScript = preload("res://scripts/legacy/legacy_profile_manager.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")

const TEST_PROFILE_PATH := "user://test_session5_legacy_profile.json"
const TEST_SAVE_PATH := "user://test_session5_save.json"

var frame_count: int = 0
var world_instance: Node = null
var failures: int = 0
var checks_passed: int = 0

func _assert(condition: bool, message: String, detail: String = "") -> void:
	if condition:
		checks_passed += 1
		print("  [PASS] %s" % message)
	else:
		failures += 1
		var err_msg := "  ❌ [FAIL] %s" % message
		if not detail.is_empty():
			err_msg += " (%s)" % detail
		printerr(err_msg)

func _cleanup_test_files() -> void:
	var dir := DirAccess.open("user://")
	if dir:
		for p in [TEST_PROFILE_PATH, TEST_PROFILE_PATH + ".bak", TEST_SAVE_PATH, TEST_SAVE_PATH + ".bak"]:
			if FileAccess.file_exists(p):
				dir.remove(p)

func _init() -> void:
	print("\n========================================================")
	print("  STARTING SESSION 5 INTEGRATION TEST SUITE")
	print("========================================================\n")
	_cleanup_test_files()
	world_instance = WorldViewScene.instantiate()
	world_instance.world_seed = 5001
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count < 3:
		return false

	_run_all_tests()

	print("\n========================================================")
	print("  SESSION 5 TEST RESULTS SUMMARY")
	print("  Passed Assertions : %d" % checks_passed)
	print("  Failed Assertions : %d" % failures)
	if failures == 0:
		print("  ALL SESSION 5 ASSERTIONS PASSED! (Exit Code 0)")
		print("========================================================\n")
		_cleanup_test_files()
		if is_instance_valid(world_instance):
			world_instance.queue_free()
		quit(0)
	else:
		printerr("  SESSION 5 TESTS ENCOUNTERED FAILURES! (Exit Code 1)")
		print("========================================================\n")
		_cleanup_test_files()
		if is_instance_valid(world_instance):
			world_instance.queue_free()
		quit(1)
	return true

func _run_all_tests() -> void:
	_test_mbl_leg_01_restless_bandits_route_risk()
	_test_mbl_leg_02_victory_live_stability_gate()
	_test_mbl_leg_03_settlement_crash_consistency()

# =============================================================================
# GROUP 1: MBL-LEG-01 — Restless Bandits Caravan Route Risk Integration
# =============================================================================
func _test_mbl_leg_01_restless_bandits_route_risk() -> void:
	print("\n--- Group 1: MBL-LEG-01 Restless Bandits Caravan Route Risk ---")
	var wv: WorldView = world_instance
	var fog = wv.fog_of_war
	var fsm = wv.field_siege_mgr
	var wdata = wv.world_data

	var start_pos := Vector2i(10, 10)
	var end_pos := Vector2i(15, 10)

	# 1. Direct evaluate_route_risk without modifiers
	var risk_no_mod = TradeRouteCalculatorScript.evaluate_route_risk_between(
		start_pos, end_pos, fog, fsm, wdata, false, []
	)
	_assert(risk_no_mod.has("net_risk"), "MBL-LEG-01.1: Calculator returns net_risk")
	_assert(risk_no_mod.has("reasons"), "MBL-LEG-01.2: Calculator returns reasons list")
	_assert(not risk_no_mod.reasons.has("restless_bandits"), "MBL-LEG-01.3: Baseline does not include restless_bandits")

	# 2. Direct evaluate_route_risk with restless_bandits
	var risk_with_bandits = TradeRouteCalculatorScript.evaluate_route_risk_between(
		start_pos, end_pos, fog, fsm, wdata, false, ["restless_bandits"]
	)
	var diff_raw: float = float(risk_with_bandits.raw_risk) - float(risk_no_mod.raw_risk)
	_assert(is_equal_approx(diff_raw, 0.10), "MBL-LEG-01.4: restless_bandits adds exactly +0.10 (+10%) raw risk", "diff=%.4f" % diff_raw)
	_assert(risk_with_bandits.reasons.has("restless_bandits"), "MBL-LEG-01.5: reasons includes 'restless_bandits'")
	_assert(risk_with_bandits.has("world_modifiers"), "MBL-LEG-01.6: Result preserves world_modifiers")
	_assert(risk_with_bandits.world_modifiers.has("restless_bandits"), "MBL-LEG-01.7: world_modifiers contains 'restless_bandits'")

	# Also test neutral route (fow=null) where net_risk diff is identically 0.10 without hitting clamp
	var neutral_base = TradeRouteCalculatorScript.evaluate_route_risk_between(start_pos, end_pos, null, null, null, false, [])
	var neutral_mod = TradeRouteCalculatorScript.evaluate_route_risk_between(start_pos, end_pos, null, null, null, false, ["restless_bandits"])
	var diff_net: float = float(neutral_mod.net_risk) - float(neutral_base.net_risk)
	_assert(is_equal_approx(diff_net, 0.10), "MBL-LEG-01.7b: Neutral net_risk diff is exactly +0.10", "diff=%.4f" % diff_net)

	# 3. Dynamic WorldView modifier lifecycle
	const TradeCaravanScript = preload("res://scripts/trade/trade_caravan.gd")
	wv.active_caravan = TradeCaravanScript.generate_caravan(wv.world_seed, 3, "rival_merchant", false)
	wv.set_world_modifiers([])
	_assert(wv.get_world_modifiers().size() == 0, "MBL-LEG-01.8: WorldView modifiers initialized empty")

	wv.add_world_modifier("restless_bandits")
	_assert(wv.get_world_modifiers().has("restless_bandits"), "MBL-LEG-01.9: add_world_modifier registers restless_bandits")

	# Verify active caravan reflects restless_bandits surcharge
	wv.refresh_caravan_route_risk()
	var cv_risk: float = float(wv.active_caravan.route_risk)
	var cv_summary: Dictionary = wv.active_caravan.route_summary
	_assert(cv_summary.get("reasons", []).has("restless_bandits"), "MBL-LEG-01.10: Caravan route summary contains restless_bandits")
	_assert(cv_risk >= 0.10, "MBL-LEG-01.11: Caravan route risk reflects restless_bandits surcharge (>= 0.10)")

	# Dynamic removal
	wv.remove_world_modifier("restless_bandits")
	_assert(not wv.get_world_modifiers().has("restless_bandits"), "MBL-LEG-01.12: remove_world_modifier clears restless_bandits")
	wv.refresh_caravan_route_risk()
	var cv_summary_after: Dictionary = wv.active_caravan.route_summary
	_assert(not cv_summary_after.get("reasons", []).has("restless_bandits"), "MBL-LEG-01.13: Caravan route summary cleared of restless_bandits")

	# 4. Persistence roundtrip with world_modifiers
	wv.add_world_modifier("restless_bandits")
	wv.active_caravan = TradeCaravanScript.generate_caravan(wv.world_seed, 3, "rival_merchant", false)
	SaveManagerScript.save_to_file(wv, TEST_SAVE_PATH)
	_assert(FileAccess.file_exists(TEST_SAVE_PATH), "MBL-LEG-01.14: Campaign saved with restless_bandits modifier")

	var wv_reloaded = WorldViewScene.instantiate()
	wv_reloaded.world_seed = 5001
	root.add_child(wv_reloaded)
	var load_data = SaveManagerScript.load_from_file(TEST_SAVE_PATH)
	SaveManagerScript.apply_loaded_state_to_world(wv_reloaded, load_data.get("data", {}))

	_assert(wv_reloaded.get_world_modifiers().has("restless_bandits"), "MBL-LEG-01.15: Reloaded WorldView restored restless_bandits modifier")
	if wv_reloaded.active_caravan != null:
		var rel_summary: Dictionary = wv_reloaded.active_caravan.route_summary
		_assert(rel_summary.get("reasons", []).has("restless_bandits"), "MBL-LEG-01.16: Reloaded caravan incorporates restless_bandits into route risk")

	root.remove_child(wv_reloaded)
	wv_reloaded.queue_free()

# =============================================================================
# GROUP 2: MBL-LEG-02 — Victory Treasury Settlement Live Kingdom Stability Gate
# =============================================================================
func _test_mbl_leg_02_victory_live_stability_gate() -> void:
	print("\n--- Group 2: MBL-LEG-02 Victory Treasury Settlement Live Kingdom Stability Gate ---")
	var prof := LegacyProfileManagerScript.new(TEST_PROFILE_PATH)
	prof.reset_profile()
	LegacyProfileManagerScript.set_instance(prof)

	var wv: WorldView = world_instance
	var rm: Node = root.get_node_or_null("ResourceManager")
	var vm: VictoryManager = wv.victory_mgr

	# Setup VictoryManager state
	vm.world_id = "world_sess5_test_wid_001"
	vm.is_world_id_persisted = true
	vm.is_victory_achieved = true
	vm.legacy_points_earned = 100
	vm.is_collapse_triggered = false
	vm.profile_mgr = prof
	vm.set("world_view", wv)

	# Setup resources: 3,000 gold (surplus 2,000 gold -> 20 LP at 80% stability)
	if rm != null:
		rm.call("reset_economy")
		rm.call("add_resource", "gold", 2800) # Total 3000 gold

	# 1. Authoritative live stability query
	var live_stab: float = wv.get_live_stability()
	_assert(live_stab >= 0.0 and live_stab <= 100.0, "MBL-LEG-02.1: get_live_stability() returns valid percentage (%.2f%%)" % live_stab)

	# 2. Ineligible stability rejection (< 80.0%, e.g. 75.0%)
	# Must reject fail-closed BEFORE any mutations (claim_legacy_reward or convert_surplus_treasury)
	var low_stab_res: Dictionary = vm.finalize_victory_settlement(rm, 75.0)
	_assert(low_stab_res.get("success", true) == false, "MBL-LEG-02.2: Settlement rejected when stability < 80.0%")
	_assert(low_stab_res.get("reason") == "stability_too_low", "MBL-LEG-02.3: Reason is 'stability_too_low'")
	_assert(vm.is_legacy_claimed == false, "MBL-LEG-02.4: Base victory reward NOT claimed on rejection")
	_assert(vm.is_treasury_converted == false, "MBL-LEG-02.5: Treasury conversion NOT executed on rejection")
	_assert(rm.call("get_available_stock", "gold") == 3000, "MBL-LEG-02.6: Gold conserved at 3000 (zero deduction)")
	_assert(prof.legacy_balance == 0, "MBL-LEG-02.7: Profile balance unchanged at 0")
	_assert(not prof.has_treasury_conversion(vm.world_id), "MBL-LEG-02.8: Profile has NO lockout record written on rejection")

	# 3. Borderline stability rejection (79.9%)
	var borderline_res: Dictionary = vm.finalize_victory_settlement(rm, 79.9)
	_assert(borderline_res.get("success", true) == false, "MBL-LEG-02.9: 79.9% stability strictly rejected (< 80.0%)")
	_assert(borderline_res.get("reason") == "stability_too_low", "MBL-LEG-02.10: Reason is 'stability_too_low'")
	_assert(vm.is_legacy_claimed == false, "MBL-LEG-02.11: Legacy remains unclaimed")
	_assert(prof.legacy_balance == 0, "MBL-LEG-02.12: Profile balance strictly 0")

	# 3b. UI low-stability state check: button disabled and labeled "Chưa đủ điều kiện"
	var hud_early = wv.get_node_or_null("HUD")
	if hud_early != null:
		var early_claim_btn: Button = hud_early.get_node_or_null("VictoryPanel/MarginContainer/VBoxContainer/HBoxContainer/ClaimVictoryBtn")
		var early_stat_lbl: Label = hud_early.get_node_or_null("VictoryPanel/MarginContainer/VBoxContainer/LegacyStatusLabel")
		if early_claim_btn != null and early_stat_lbl != null:
			hud_early.call("_refresh_victory_claim_state", {"stability": 75.0})
			_assert(early_claim_btn.disabled == true, "MBL-LEG-02.12b: HUD Claim button disabled when stability < 80.0%")
			_assert(early_claim_btn.text == "Chưa đủ điều kiện", "MBL-LEG-02.12c: HUD Claim button text is truthfully 'Chưa đủ điều kiện'")
			_assert(early_stat_lbl.text.contains("chưa đạt mức tối thiểu 80.0%"), "MBL-LEG-02.12d: HUD LegacyStatusLabel displays low stability warning")

	# 4. Fail-closed handling when live stability is unavailable or invalid
	var unavail_vm := VictoryManagerScript.new()
	unavail_vm.world_id = "world_sess5_test_unavail"
	unavail_vm.is_world_id_persisted = true
	unavail_vm.is_victory_achieved = true
	unavail_vm.profile_mgr = prof
	unavail_vm.world_view = null # detached, no parent
	var unavail_res: Dictionary = unavail_vm.finalize_victory_settlement(null, -1.0)
	_assert(unavail_res.get("success", true) == false, "MBL-LEG-02.13: Missing stability fails closed")
	_assert(unavail_res.get("reason") == "stability_unavailable", "MBL-LEG-02.14: Reason is 'stability_unavailable'")

	var nan_res: Dictionary = unavail_vm.finalize_victory_settlement(null, NAN)
	_assert(nan_res.get("success", true) == false, "MBL-LEG-02.15: NaN stability fails closed")
	_assert(nan_res.get("reason") == "stability_unavailable", "MBL-LEG-02.16: Reason is 'stability_unavailable'")

	var inf_res: Dictionary = unavail_vm.finalize_victory_settlement(null, INF)
	_assert(inf_res.get("success", true) == false, "MBL-LEG-02.17: INF stability fails closed")
	_assert(inf_res.get("reason") == "stability_unavailable", "MBL-LEG-02.18: Reason is 'stability_unavailable'")

	# 5. Recovery & Successful settlement when stability >= 80.0% (e.g. 85.0%)
	# Since previous attempts were rejected without mutating profile or writing lockout records,
	# the kingdom can now settle cleanly!
	var success_res: Dictionary = vm.finalize_victory_settlement(rm, 85.0)
	_assert(success_res.get("success", false) == true, "MBL-LEG-02.19: Settlement succeeds at 85.0% stability")
	_assert(success_res.get("victory_claimed") == true, "MBL-LEG-02.20: Victory reward claimed")
	_assert(success_res.get("victory_points_awarded") == 100, "MBL-LEG-02.21: 100 base victory LP awarded")
	_assert(success_res.get("treasury_converted") == true, "MBL-LEG-02.22: Treasury conversion succeeded")
	_assert(success_res.get("treasury_points_awarded") == 20, "MBL-LEG-02.23: 20 treasury LP awarded (2000 surplus / 100)")
	_assert(success_res.get("total_legacy_awarded") == 120, "MBL-LEG-02.24: Total 120 LP awarded")
	_assert(success_res.get("gold_deducted") == 2000, "MBL-LEG-02.25: 2000 gold deducted from treasury")
	_assert(rm.call("get_available_stock", "gold") == 1000, "MBL-LEG-02.26: 1000 gold reserve strictly protected in treasury")
	_assert(prof.legacy_balance == 120, "MBL-LEG-02.27: Profile balance accurately credited with 120 LP")
	_assert(vm.is_legacy_claimed == true, "MBL-LEG-02.28: VictoryManager is_legacy_claimed is true")
	_assert(vm.is_treasury_converted == true, "MBL-LEG-02.29: VictoryManager is_treasury_converted is true")

	# 6. Idempotency after complete settlement
	var retry_res: Dictionary = vm.finalize_victory_settlement(rm, 85.0)
	_assert(retry_res.get("success", true) == false, "MBL-LEG-02.30: Repeated settlement call rejected")
	_assert(retry_res.get("reason") == "already_settled", "MBL-LEG-02.31: Retry reason is 'already_settled'")
	_assert(retry_res.get("total_legacy_awarded", -1) == 0, "MBL-LEG-02.32: Zero duplicate points awarded on retry")
	_assert(prof.legacy_balance == 120, "MBL-LEG-02.33: Profile balance conserved at 120 (no double-crediting)")

	# 7. UI HUD integration check
	var hud = wv.get_node_or_null("HUD")
	if hud != null:
		var claim_btn: Button = hud.get_node_or_null("VictoryPanel/MarginContainer/VBoxContainer/HBoxContainer/ClaimVictoryBtn")
		var stat_lbl: Label = hud.get_node_or_null("VictoryPanel/MarginContainer/VBoxContainer/LegacyStatusLabel")
		_assert(claim_btn != null, "MBL-LEG-02.34: HUD ClaimVictoryBtn exists")
		_assert(stat_lbl != null, "MBL-LEG-02.35: HUD LegacyStatusLabel exists")

		# In settled state, claim button is disabled and reflects completed settlement
		hud.call("_refresh_victory_claim_state", {})
		_assert(claim_btn.disabled == true, "MBL-LEG-02.36: Claim button disabled after complete settlement")
		_assert(claim_btn.text == "Đã Nhận Di Sản", "MBL-LEG-02.37: Claim button text is 'Đã Nhận Di Sản'")

# =============================================================================
# GROUP 3: MBL-LEG-03 — Multi-File Settlement Interruption Verification (ca61815)
# =============================================================================
func _test_mbl_leg_03_settlement_crash_consistency() -> void:
	print("\n--- Group 3: MBL-LEG-03 Multi-File Settlement Interruption Protection (ca61815) ---")
	var prof := LegacyProfileManagerScript.new(TEST_PROFILE_PATH)
	prof.reset_profile()
	prof.claim_reward("test_init_fund_100", "victory", 100, "world_test_init")
	LegacyProfileManagerScript.set_instance(prof)

	# Create a fresh campaign
	var wv_crash = WorldViewScene.instantiate()
	wv_crash.world_seed = 5003
	root.add_child(wv_crash)

	var rm_crash: Node = root.get_node_or_null("ResourceManager")
	if rm_crash != null:
		rm_crash.call("reset_economy")
		rm_crash.call("add_resource", "gold", 2800) # 3000 gold

	var vm_crash: VictoryManager = wv_crash.victory_mgr
	vm_crash.is_victory_achieved = true
	vm_crash.legacy_points_earned = 100
	vm_crash.profile_mgr = prof
	vm_crash.set("world_view", wv_crash)

	# Save campaign before settlement (simulates pre-settlement save file on disk with victory achieved but unsettled)
	SaveManagerScript.save_to_file(wv_crash, TEST_SAVE_PATH)
	var crash_wid: String = wv_crash.world_id

	# Simulate Profile committing transaction (100 base + 20 treasury LP = 120 LP awarded)
	# But SIMULATE CRASH: process terminates / closes BEFORE SaveManager.save_to_file() updates the world save!
	var set_res = vm_crash.finalize_victory_settlement(rm_crash, 85.0)
	_assert(set_res.get("success", false) == true, "MBL-LEG-03.1: Profile settlement transaction committed")
	_assert(prof.legacy_balance == 220, "MBL-LEG-03.2: Profile balance updated to 220 (100 + 120)")

	# Destroy the world instance without saving it to disk (simulates interruption window)
	root.remove_child(wv_crash)
	wv_crash.queue_free()

	# Reopen campaign from disk into a fresh WorldView
	var wv_recovered = WorldViewScene.instantiate()
	wv_recovered.world_seed = 5003
	root.add_child(wv_recovered)

	var load_res = SaveManagerScript.load_from_file(TEST_SAVE_PATH)
	# Trigger commit ca61815 crash recovery in SaveManager:
	SaveManagerScript.apply_loaded_state_to_world(wv_recovered, load_res.get("data", {}))

	var vm_rec: VictoryManager = wv_recovered.victory_mgr
	var rm_rec: Node = root.get_node_or_null("ResourceManager")

	# Verify commit ca61815 reconciled state:
	_assert(vm_rec.is_legacy_claimed == true, "MBL-LEG-03.3: Crash recovery reconciled is_legacy_claimed == true from profile")
	_assert(vm_rec.is_treasury_converted == true, "MBL-LEG-03.4: Crash recovery reconciled is_treasury_converted == true from profile")
	_assert(rm_rec.call("get_available_stock", "gold") == 1000, "MBL-LEG-03.5: Crash recovery retroactively deducted 2000 gold (3000 -> 1000)")

	# Retrying settlement on recovered world safely rejects without double-crediting
	var retry_crash = vm_rec.finalize_victory_settlement(rm_rec, 85.0)
	_assert(retry_crash.get("success", true) == false, "MBL-LEG-03.6: Settlement retry safely rejected on recovered world")
	_assert(retry_crash.get("reason") == "already_settled", "MBL-LEG-03.7: Rejection reason is 'already_settled'")
	_assert(retry_crash.get("total_legacy_awarded", -1) == 0, "MBL-LEG-03.8: Zero duplicate points awarded on recovered save")
	_assert(prof.legacy_balance == 220, "MBL-LEG-03.9: Profile balance invariant holds at 220")

	root.remove_child(wv_recovered)
	wv_recovered.queue_free()
