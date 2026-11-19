extends SceneTree

## =============================================================================
## KINGDOMS UNBOUND — WorldView Field Siege Input & Failure-Path Test Suite
## =============================================================================
## File: scripts/test/test_world_view_siege_input.gd
## Purpose: Regression verification of field-siege launch and tactical attack-order
##          failure handling in scripts/world/world_view.gd.
## Verifies:
##   1. Valid Field Siege launch with ready field forces.
##   2. Tactical attack-order failure handling.
##   3. Correct red failure banner and exact failure reason displayed on HUD.
##   4. Rejection of false success feedback.
##   5. Consistent active siege state retention in FieldSiegeManager.
##   6. Retry handling without duplicate siege record creation.
##   7. Withdrawal/resolution cleanup of active siege state.
## =============================================================================

const TacticalMilitaryManagerScript = preload("res://scripts/military/tactical_military_manager.gd")
const IsoMathScript = preload("res://scripts/utils/iso_math.gd")

var frame_count: int = 0
var world_instance: Node = null
var failures: int = 0
var checks_passed: int = 0

func _assert(condition: bool, message: String) -> void:
	if condition:
		checks_passed += 1
		print("  [PASS] %s" % message)
	else:
		failures += 1
		printerr("  [FAIL] %s" % message)

func _init() -> void:
	print("\n========================================================")
	print("  STARTING WORLD_VIEW SIEGE INPUT FAILURE-PATH TESTS")
	print("========================================================\n")
	var world_scene: PackedScene = load("res://scenes/world/world_view.tscn")
	world_instance = world_scene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count < 3:
		# Wait 2 frames for WorldView _ready and child managers initialization
		return false

	_run_verification()
	print("\n--------------------------------------------------------")
	print("  Checks Passed: %d | Failures: %d" % [checks_passed, failures])
	if is_instance_valid(world_instance):
		world_instance.queue_free()
	if failures == 0:
		print("  WORLD_VIEW SIEGE INPUT FAILURE-PATH TESTS PASSED (Exit Code 0)")
		print("--------------------------------------------------------\n")
		quit(0)
	else:
		printerr("  WORLD_VIEW SIEGE INPUT FAILURE-PATH TESTS FAILED (Exit Code 1)")
		print("--------------------------------------------------------\n")
		quit(1)
	return true

# Controlled test double subclassing TacticalMilitaryManager to isolate issue_attack_order failure
class TacticalManagerDouble extends TacticalMilitaryManager:
	var force_failure: bool = true
	var failure_reason: String = "Đường đi tới mục tiêu công thành bị chặn hoàn toàn"
	var issue_attack_order_calls: int = 0
	var last_attack_target: Node = null

	func issue_attack_order(target: Node, nav: GridNavigation = null) -> Dictionary:
		issue_attack_order_calls += 1
		last_attack_target = target
		if force_failure:
			return {
				"success": false,
				"reason": failure_reason
			}
		return super.issue_attack_order(target, nav)

func _run_verification() -> void:
	print("--- Step 1: Setting up World & Prerequisites ---")
	var fm = world_instance.get("faction_mgr")
	var fsm = world_instance.get("field_siege_mgr")
	var pam = world_instance.get("player_army_mgr")
	var real_tac = world_instance.get("tactical_military_mgr")
	var hud = world_instance.get("hud")

	_assert(fm != null, "FactionManager is present")
	_assert(fsm != null, "FieldSiegeManager is present")
	_assert(pam != null, "PlayerArmyManager is present")
	_assert(real_tac != null, "TacticalMilitaryManager is present")
	_assert(hud != null, "HUD is present")

	# Declare war with rival_military so field siege is allowed
	var war_res = fm.declare_war("rival_military")
	_assert(bool(war_res.get("success", false)), "War declared with rival_military")

	# Find rival_military objective
	var obj_id := "outpost_rival_military"
	var obj = fsm.get_objective(obj_id)
	_assert(obj != null, "Siege objective %s exists" % obj_id)
	_assert(obj.is_alive, "Siege objective is alive")
	_assert(not obj.is_under_active_siege, "Objective initially not under siege")

	# Instantiate TacticalManagerDouble and attach to WorldView and PlayerArmyManager
	var tac_double := TacticalManagerDouble.new(world_instance, pam)
	tac_double.set_world_view(world_instance)
	tac_double.set_player_army_manager(pam)
	world_instance.set("tactical_military_mgr", tac_double)
	pam.set_tactical_military_manager(tac_double)

	# Synchronize tactical units with army first
	pam.soldier_count = 5
	tac_double.sync_with_player_army()
	var all_u = tac_double.get_all_units()
	_assert(all_u.size() > 0, "Tactical units synchronized (count = %d)" % all_u.size())

	# Position player army and tactical units in the field near the objective (dist = 2 <= SIEGE_RADIUS = 12)
	var target_field_cell: Vector2i = obj.current_cell + Vector2i(2, 2)
	for u in all_u:
		if is_instance_valid(u):
			u.current_cell = target_field_cell
			u.target_cell = target_field_cell
			u.order_state = 0 # OrderState.IDLE

	pam.current_cell = target_field_cell
	pam.destination_cell = target_field_cell
	pam.movement_state = 2 # MovementState.IDLE_AT_FIELD
	pam.sync_state_from_tactical()

	# Refresh world vision so the positioned field units observe the target objective in FogOfWar
	if world_instance.has_method("refresh_world_vision"):
		world_instance.refresh_world_vision()

	tac_double.select_all()
	_assert(tac_double.get_selected_count() > 0, "Tactical units selected (selected = %d)" % tac_double.get_selected_count())
	_assert(pam.get_field_unit_count() > 0, "PlayerArmyManager has ready field troops (%d)" % pam.get_field_unit_count())

	# Verify can_launch_field_siege is valid
	var can_launch = fsm.can_launch_field_siege(obj.owning_faction_id, obj.objective_id)
	_assert(bool(can_launch.get("can_launch", false)), "can_launch_field_siege succeeds with field troops ready")

	# Configure double to FAIL on attack order
	tac_double.force_failure = true
	tac_double.failure_reason = "Đường đi tới mục tiêu công thành bị chặn hoàn toàn"

	print("\n--- Step 2: Triggering Right-Click on Objective (Failure Path) ---")
	# Create synthetic right-click InputEventMouseButton directed at objective cell
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_RIGHT
	mb.pressed = true
	mb.set_meta("target_cell", obj.current_cell)

	# Execute _unhandled_input
	world_instance._unhandled_input(mb)

	# Verification of Step 2:
	_assert(tac_double.issue_attack_order_calls == 1, "issue_attack_order was called exactly once")
	_assert(tac_double.last_attack_target == obj, "issue_attack_order target is the objective")

	# Verify HUD banner state directly via HUD properties
	_assert(hud.event_banner != null and hud.event_banner.visible, "EventBanner is visible on HUD")
	_assert(hud.event_title != null and hud.event_title.text == "Lệnh Tấn Công Thất Bại", "HUD title indicates failure: '%s'" % (hud.event_title.text if hud.event_title else ""))
	_assert(hud.event_desc != null and hud.event_desc.text == tac_double.failure_reason, "HUD description matches exact failure reason: '%s'" % (hud.event_desc.text if hud.event_desc else ""))
	_assert(hud.event_title != null and is_equal_approx(hud.event_title.modulate.r, 1.0) and is_equal_approx(hud.event_title.modulate.g, 0.3), "HUD banner modulate is red (is_positive = false)")
	_assert(hud.event_title != null and hud.event_title.text != "Phát Động Công Thành!", "Success banner was NOT displayed")

	# Verify FieldSiegeManager state after failure
	_assert(fsm.is_siege_active_for_objective(obj_id), "Siege record was created and remains active in FieldSiegeManager")
	_assert(fsm.active_sieges.size() == 1, "Exactly 1 active siege exists")
	_assert(obj.is_under_active_siege, "Objective marked is_under_active_siege = true")

	print("\n--- Step 3: Triggering Second Right-Click (Retry Mechanism) ---")
	# Now change the double to SUCCEED on retry
	tac_double.force_failure = false

	# Send second right click on the same objective
	world_instance._unhandled_input(mb)

	# Verification of Step 3:
	_assert(tac_double.issue_attack_order_calls == 2, "issue_attack_order was called a second time (retry)")
	_assert(fsm.active_sieges.size() == 1, "Active sieges count remains strictly 1 (NO duplicate siege created)")
	_assert(fsm.is_siege_active_for_objective(obj_id), "Siege is still active for objective")

	print("\n--- Step 4: Resolving Siege via Withdrawal Lifecycle ---")
	# When army withdraws or cancels active sieges:
	fsm.cancel_active_sieges_for_faction("rival_military", "WITHDRAWAL")
	_assert(not fsm.is_siege_active_for_objective(obj_id), "Siege is no longer active after withdrawal")
	_assert(not obj.is_under_active_siege, "Objective is_under_active_siege cleared to false")
	var evaluated = fsm.evaluate_siege_status("siege_1")
	_assert(evaluated.get("status") == "resolved", "Siege record evaluated cleanly as resolved")
	_assert(evaluated.get("outcome") == "WITHDRAWAL", "Siege outcome is WITHDRAWAL")

	# Restore real manager before teardown
	world_instance.set("tactical_military_mgr", real_tac)
	pam.set_tactical_military_manager(real_tac)
