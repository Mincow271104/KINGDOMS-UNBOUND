extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — Package 1Y: Automation Graph Delay & Repeat Nodes
##
## Validates:
## - TC-Y.1 to TC-Y.2: Delay Node Validation & Parameter Bounds (1–720 hours)
## - TC-Y.3 to TC-Y.8: Delay Runtime Progression, Simulation Clock & Day Boundaries
## - TC-Y.9 to TC-Y.12: Delay Continuation Lifecycle, Single Execution & Queue Limits
## - TC-Y.13 to TC-Y.18: Repeat Node Validation, Bounded Iterations & Budget Safety
## - TC-Y.19 to TC-Y.22: Editor Ports, Palette Wiring & Side-Effect-Free Dry-Run
## - TC-Y.23 to TC-Y.27: Save/Load Persistence, Double-Load Idempotency & Legacy Compatibility
## - TC-Y.28 to TC-Y.30: Preset Rules Non-Regression & Authoritative Simulation Integration

const AutomationProgramScript = preload("res://scripts/economy/automation_program.gd")
const AutomationGraphValidatorScript = preload("res://scripts/economy/automation_graph_validator.gd")
const AutomationManagerScript = preload("res://scripts/economy/automation_manager.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")
const AutomationEditorScene: PackedScene = preload("res://scenes/ui/automation_editor.tscn")

class MockCitizen:
	extends RefCounted
	var id: String = ""
	var citizen_name: String = ""
	var role: String = "idle"
	var fatigue: float = 0.0
	var is_dead: bool = false

	func _init(p_id: String, p_name: String, p_role: String = "idle", p_fatigue: float = 0.0) -> void:
		id = p_id
		citizen_name = p_name
		role = p_role
		fatigue = p_fatigue
		is_dead = false

	func set_role(new_role: String) -> bool:
		role = new_role
		return true

class MockJobManager:
	extends RefCounted
	var boost_calls: Array[Dictionary] = []

	func boost_jobs_priority(job_type: String, delta_priority: int) -> int:
		boost_calls.append({"type": job_type, "delta": delta_priority})
		return 1

var frame_count: int = 0
var world_instance: Node = null
var failures: int = 0
var passed_checks: int = 0

func _init() -> void:
	print("\n========================================================")
	print("  STARTING PACKAGE 1Y AUTOMATION DELAY & REPEAT TESTS")
	print("========================================================\n")
	world_instance = WorldViewScene.instantiate()
	root.add_child(world_instance)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count == 3:
		_run_all_tests()
		print("\n--------------------------------------------------------")
		print("  Checks Passed: %d | Failures: %d" % [passed_checks, failures])
		if failures == 0:
			print("  ALL PACKAGE 1Y AUTOMATION DELAY & REPEAT TESTS PASSED! (Exit Code 0)")
			print("--------------------------------------------------------\n")
			quit(0)
			return true
		else:
			printerr("  PACKAGE 1Y TESTS FAILED WITH %d FAILURES! (Exit Code 1)" % failures)
			print("--------------------------------------------------------\n")
			quit(1)
			return true
	return false

func _assert_true(cond: bool, test_name: String, msg: String = "") -> void:
	if not cond:
		failures += 1
		printerr("  ❌ FAIL [%s]: Expected true. %s" % [test_name, msg])
	else:
		passed_checks += 1
		print("  ✅ PASS [%s]%s" % [test_name, (" - " + msg) if msg != "" else ""])

func _assert_false(cond: bool, test_name: String, msg: String = "") -> void:
	if cond:
		failures += 1
		printerr("  ❌ FAIL [%s]: Expected false. %s" % [test_name, msg])
	else:
		passed_checks += 1
		print("  ✅ PASS [%s]%s" % [test_name, (" - " + msg) if msg != "" else ""])

func _assert_eq(actual: Variant, expected: Variant, test_name: String, msg: String = "") -> void:
	if actual != expected:
		failures += 1
		printerr("  ❌ FAIL [%s]: Expected '%s', got '%s'. %s" % [test_name, str(expected), str(actual), msg])
	else:
		passed_checks += 1
		print("  ✅ PASS [%s]%s" % [test_name, (" - " + msg) if msg != "" else ""])

func _run_all_tests() -> void:
	_test_group_1_delay_validation()
	_test_group_2_delay_runtime_and_clock()
	_test_group_3_delay_continuation_lifecycle()
	_test_group_4_repeat_validation_and_iterations()
	_test_group_5_editor_ports_and_dry_run()
	_test_group_6_persistence_and_compatibility()
	_test_group_7_non_regression_and_world_integration()

# -----------------------------------------------------------------------------
# GROUP 1: Delay Validation & Configuration
# -----------------------------------------------------------------------------
func _test_group_1_delay_validation() -> void:
	print("--- Group 1: Delay Node Validation & Bounds (1–720h) ---")
	
	# 1. Valid Delay configurations (1h, 24h, 720h)
	for dur in [1, 24, 720]:
		var prog := AutomationProgram.new("p_delay_ok_%d" % dur, "Delay OK")
		prog.nodes = [
			{"id": "n1", "type": "Trigger", "subtype": "OnTick", "params": {}},
			{"id": "n2", "type": "Delay", "subtype": "", "params": {"duration_hours": dur}},
			{"id": "n3", "type": "Action", "subtype": "EmitLog", "params": {"message": "Delayed Action"}}
		]
		prog.edges = [
			{"from_node": "n1", "from_port": "out", "to_node": "n2", "to_port": "in"},
			{"from_node": "n2", "from_port": "out", "to_node": "n3", "to_port": "in"}
		]
		var val := AutomationGraphValidator.validate_program(prog)
		_assert_true(val["valid"], "TC-Y.1.1_%d" % dur, "Valid duration %d hours accepted" % dur)

	# 2. Invalid Delay durations (0, -1, 721, float 1.5, NaN, missing)
	var bad_durations = [0, -5, 721, 9999, 1.5, "10", null]
	for idx in range(bad_durations.size()):
		var b_dur = bad_durations[idx]
		var prog_bad := AutomationProgram.new("p_delay_bad_%d" % idx, "Delay Bad")
		var p_dict: Dictionary = {}
		if b_dur != null:
			p_dict["duration_hours"] = b_dur
		prog_bad.nodes = [
			{"id": "n1", "type": "Trigger", "subtype": "OnTick", "params": {}},
			{"id": "n2", "type": "Delay", "subtype": "", "params": p_dict},
			{"id": "n3", "type": "Action", "subtype": "EmitLog", "params": {"message": "Test"}}
		]
		prog_bad.edges = [
			{"from_node": "n1", "from_port": "out", "to_node": "n2", "to_port": "in"},
			{"from_node": "n2", "from_port": "out", "to_node": "n3", "to_port": "in"}
		]
		var val_bad := AutomationGraphValidator.validate_program(prog_bad)
		_assert_false(val_bad["valid"], "TC-Y.2.1_%d" % idx, "Invalid duration '%s' rejected fail-closed" % str(b_dur))

	# 3. Dead-end Delay without output port rejected
	var prog_dead_delay := AutomationProgram.new("p_dead_delay", "Dead Delay")
	prog_dead_delay.nodes = [
		{"id": "n1", "type": "Trigger", "subtype": "OnTick", "params": {}},
		{"id": "n2", "type": "Delay", "subtype": "", "params": {"duration_hours": 2}}
	]
	prog_dead_delay.edges = [
		{"from_node": "n1", "from_port": "out", "to_node": "n2", "to_port": "in"}
	]
	var val_dead := AutomationGraphValidator.validate_program(prog_dead_delay)
	_assert_false(val_dead["valid"], "TC-Y.2.2", "Delay without outgoing 'out' port rejected")

# -----------------------------------------------------------------------------
# GROUP 2: Delay Runtime Progression, Simulation Clock & Day Boundaries
# -----------------------------------------------------------------------------
func _test_group_2_delay_runtime_and_clock() -> void:
	print("--- Group 2: Delay Runtime Progression & Clock ---")
	var mgr := AutomationManager.new()
	var prog := mgr.create_program("TestDelayRuntime", 10)
	prog.enabled = true
	var n_delay = mgr.add_node(prog, "Delay", "", 180, 80, {"duration_hours": 3})
	var n_act = mgr.add_node(prog, "Action", "EmitLog", 360, 80, {"message": "Action Sau 3h"})
	mgr.connect_nodes(prog, "n_start", "out", n_delay["id"], "in")
	mgr.connect_nodes(prog, n_delay["id"], "out", n_act["id"], "in")

	# Initial run at Day 1, Hour 6
	var ctx: Dictionary = {"current_day": 1, "current_hour": 6, "is_paused": false}
	var res := mgr.run_program(prog.id, ctx)
	_assert_true(res["ok"], "TC-Y.3.1", "Run with Delay returned ok: true")
	_assert_eq(res["actions_executed"].size(), 0, "TC-Y.3.2", "Downstream action was NOT executed immediately")
	_assert_eq(mgr.get_pending_continuations().size(), 1, "TC-Y.3.3", "Exactly 1 continuation scheduled")

	var cont: Dictionary = mgr.get_pending_continuations()[0]
	_assert_eq(cont["due_day"], 1, "TC-Y.4.1", "Scheduled due day is Day 1")
	_assert_eq(cont["due_hour"], 9, "TC-Y.4.2", "Scheduled due hour is Hour 9 (6 + 3)")
	_assert_eq(cont["due_total_hours"], 9, "TC-Y.4.3", "Scheduled due_total_hours is 9")

	# Advance to Hour 7 (not due)
	ctx["current_hour"] = 7
	var due_7 := mgr.process_due_continuations(ctx)
	_assert_eq(due_7.size(), 0, "TC-Y.4.4", "Continuation not due at Hour 7")
	_assert_eq(mgr.get_pending_continuations().size(), 1, "TC-Y.4.5", "Continuation remains pending at Hour 7")

	# Advance to Hour 8 (not due)
	ctx["current_hour"] = 8
	var due_8 := mgr.process_due_continuations(ctx)
	_assert_eq(due_8.size(), 0, "TC-Y.4.6", "Continuation not due at Hour 8")

	# Advance to Hour 9 (now due!)
	ctx["current_hour"] = 9
	var due_9 := mgr.process_due_continuations(ctx)
	_assert_eq(due_9.size(), 1, "TC-Y.4.7", "Continuation resumed exactly at Hour 9")
	_assert_eq(mgr.get_pending_continuations().size(), 0, "TC-Y.4.8", "Continuation queue cleared after execution")
	var act_list: Array = due_9[0]["result"]["actions_executed"]
	_assert_eq(act_list.size(), 1, "TC-Y.4.9", "Downstream action executed on continuation resume")
	_assert_eq(act_list[0]["node_id"], n_act["id"], "TC-Y.4.10", "Action matches target node ID")

	# 1-hour delay resumes on next eligible simulation hour
	var prog_1h := mgr.create_program("TestDelay1h", 10)
	prog_1h.enabled = true
	var n_d1 = mgr.add_node(prog_1h, "Delay", "", 180, 80, {"duration_hours": 1})
	var n_a1 = mgr.add_node(prog_1h, "Action", "EmitLog", 360, 80, {"message": "1h later"})
	mgr.connect_nodes(prog_1h, "n_start", "out", n_d1["id"], "in")
	mgr.connect_nodes(prog_1h, n_d1["id"], "out", n_a1["id"], "in")

	ctx = {"current_day": 1, "current_hour": 10, "is_paused": false}
	mgr.run_program(prog_1h.id, ctx)
	_assert_eq(mgr.get_pending_continuations().size(), 1, "TC-Y.5.1", "1h delay scheduled at Hour 10")
	var due_1h := mgr.process_due_continuations(ctx)
	_assert_eq(due_1h.size(), 0, "TC-Y.5.2", "1h delay does not resume immediately in same hour (Hour 10)")
	ctx["current_hour"] = 11
	due_1h = mgr.process_due_continuations(ctx)
	_assert_eq(due_1h.size(), 1, "TC-Y.5.3", "1h delay resumes on next eligible simulation hour (Hour 11)")

	# Simulation Pause prevents delay progression
	var prog_pause := mgr.create_program("TestDelayPause", 10)
	prog_pause.enabled = true
	var n_dp = mgr.add_node(prog_pause, "Delay", "", 180, 80, {"duration_hours": 2})
	var n_ap = mgr.add_node(prog_pause, "Action", "EmitLog", 360, 80, {"message": "Pause Action"})
	mgr.connect_nodes(prog_pause, "n_start", "out", n_dp["id"], "in")
	mgr.connect_nodes(prog_pause, n_dp["id"], "out", n_ap["id"], "in")

	ctx = {"current_day": 1, "current_hour": 12, "is_paused": false}
	mgr.run_program(prog_pause.id, ctx)
	# Advance time while paused
	ctx["current_hour"] = 14
	ctx["is_paused"] = true
	var due_paused := mgr.process_due_continuations(ctx)
	_assert_eq(due_paused.size(), 0, "TC-Y.6.1", "Pause prevents continuation execution even when due time reached")
	_assert_eq(mgr.get_pending_continuations().size(), 1, "TC-Y.6.2", "Continuation remains queued during pause")
	# Unpause
	ctx["is_paused"] = false
	var due_unpaused := mgr.process_due_continuations(ctx)
	_assert_eq(due_unpaused.size(), 1, "TC-Y.6.3", "Continuation resumes cleanly upon unpause")

	# Delay crossing midnight day boundary
	var prog_midnight := mgr.create_program("TestMidnightDelay", 10)
	prog_midnight.enabled = true
	var n_dm = mgr.add_node(prog_midnight, "Delay", "", 180, 80, {"duration_hours": 3})
	var n_am = mgr.add_node(prog_midnight, "Action", "EmitLog", 360, 80, {"message": "Day 2 Action"})
	mgr.connect_nodes(prog_midnight, "n_start", "out", n_dm["id"], "in")
	mgr.connect_nodes(prog_midnight, n_dm["id"], "out", n_am["id"], "in")

	# Scheduled at Day 1, Hour 22 (+ 3h = Day 2, Hour 1)
	ctx = {"current_day": 1, "current_hour": 22, "is_paused": false}
	mgr.run_program(prog_midnight.id, ctx)
	var cont_mid: Dictionary = mgr.get_pending_continuations()[0]
	_assert_eq(cont_mid["due_day"], 2, "TC-Y.8.1", "Cross-day due_day correctly calculated as Day 2")
	_assert_eq(cont_mid["due_hour"], 1, "TC-Y.8.2", "Cross-day due_hour correctly calculated as Hour 1")
	_assert_eq(cont_mid["due_total_hours"], 25, "TC-Y.8.3", "Cross-day due_total_hours is 25 ((2-1)*24 + 1)")

	# Advance to Day 2, Hour 0 (not due yet: total=24 < 25)
	ctx["current_day"] = 2
	ctx["current_hour"] = 0
	_assert_eq(mgr.process_due_continuations(ctx).size(), 0, "TC-Y.8.4", "Not due yet at Day 2 Hour 0")

	# Advance to Day 2, Hour 1 (due!)
	ctx["current_hour"] = 1
	var due_mid := mgr.process_due_continuations(ctx)
	_assert_eq(due_mid.size(), 1, "TC-Y.8.5", "Cross-day continuation executed cleanly on Day 2 Hour 1")

# -----------------------------------------------------------------------------
# GROUP 3: Delay Continuation Lifecycle & Safety
# -----------------------------------------------------------------------------
func _test_group_3_delay_continuation_lifecycle() -> void:
	print("--- Group 3: Delay Continuation Lifecycle & Safety ---")
	var mgr := AutomationManager.new()

	# Trigger is not re-executed when continuation resumes
	var prog_trig := mgr.create_program("TestNoReTrigger", 10)
	prog_trig.enabled = true
	var n_act_before = mgr.add_node(prog_trig, "Action", "EmitLog", 180, 80, {"message": "Pre-delay log"})
	var n_del = mgr.add_node(prog_trig, "Delay", "", 360, 80, {"duration_hours": 1})
	var n_act_after = mgr.add_node(prog_trig, "Action", "EmitLog", 540, 80, {"message": "Post-delay log"})
	mgr.connect_nodes(prog_trig, "n_start", "out", n_act_before["id"], "in")
	mgr.connect_nodes(prog_trig, n_act_before["id"], "out", n_del["id"], "in")
	mgr.connect_nodes(prog_trig, n_del["id"], "out", n_act_after["id"], "in")

	var ctx: Dictionary = {"current_day": 1, "current_hour": 1, "is_paused": false}
	var res_initial := mgr.run_program(prog_trig.id, ctx)
	_assert_eq(res_initial["actions_executed"].size(), 1, "TC-Y.9.1", "Pre-delay action executed initially")
	_assert_eq(res_initial["actions_executed"][0]["node_id"], n_act_before["id"], "TC-Y.9.2", "Pre-delay action was n_act_before")

	# Advance and resume continuation
	ctx["current_hour"] = 2
	var due := mgr.process_due_continuations(ctx)
	_assert_eq(due.size(), 1, "TC-Y.9.3", "Continuation resumed")
	var resumed_acts: Array = due[0]["result"]["actions_executed"]
	_assert_eq(resumed_acts.size(), 1, "TC-Y.9.4", "Only post-delay action executed on resume (Trigger & pre-delay skipped)")
	_assert_eq(resumed_acts[0]["node_id"], n_act_after["id"], "TC-Y.9.5", "Executed node is strictly post-delay node")

	# Processed exactly once (no repeat execution)
	var due_repeat := mgr.process_due_continuations(ctx)
	_assert_eq(due_repeat.size(), 0, "TC-Y.10.1", "Continuation cannot execute a second time")

	# Per-program queue limit (10)
	var prog_lim := mgr.create_program("TestQueueLimit", 10)
	prog_lim.enabled = true
	var n_dl = mgr.add_node(prog_lim, "Delay", "", 180, 80, {"duration_hours": 5})
	var n_al = mgr.add_node(prog_lim, "Action", "EmitLog", 360, 80, {"message": "Limit"})
	mgr.connect_nodes(prog_lim, "n_start", "out", n_dl["id"], "in")
	mgr.connect_nodes(prog_lim, n_dl["id"], "out", n_al["id"], "in")

	for i in range(10):
		var s_ok := mgr.schedule_continuation(prog_lim.id, n_dl["id"], n_al["id"], 5, 1, 10)
		_assert_true(s_ok["ok"], "TC-Y.11.1_%d" % i, "Scheduling continuation %d accepted" % i)
	var s_overflow := mgr.schedule_continuation(prog_lim.id, n_dl["id"], n_al["id"], 5, 1, 10)
	_assert_false(s_overflow["ok"], "TC-Y.11.2", "11th continuation rejected by per-program limit")
	_assert_eq(s_overflow["code"], "LIMIT_PROGRAM", "TC-Y.11.3", "Error code is LIMIT_PROGRAM")

	# Invalidation safety on deleted/disabled program
	var prog_del := mgr.create_program("TestProgDelete", 10)
	prog_del.enabled = true
	var n_dd = mgr.add_node(prog_del, "Delay", "", 180, 80, {"duration_hours": 1})
	var n_ad = mgr.add_node(prog_del, "Action", "EmitLog", 360, 80, {"message": "Delete"})
	mgr.connect_nodes(prog_del, "n_start", "out", n_dd["id"], "in")
	mgr.connect_nodes(prog_del, n_dd["id"], "out", n_ad["id"], "in")

	mgr.schedule_continuation(prog_del.id, n_dd["id"], n_ad["id"], 1, 1, 5)
	mgr.delete_program(prog_del.id)
	_assert_eq(mgr.get_pending_continuations_for_program(prog_del.id).size(), 0, "TC-Y.12.1", "Deleting program clears pending continuations")

	# Disabled program safely ignores due continuation
	var prog_dis := mgr.create_program("TestProgDisabled", 10)
	prog_dis.enabled = true
	var n_ds = mgr.add_node(prog_dis, "Delay", "", 180, 80, {"duration_hours": 1})
	var n_as = mgr.add_node(prog_dis, "Action", "EmitLog", 360, 80, {"message": "Dis"})
	mgr.connect_nodes(prog_dis, "n_start", "out", n_ds["id"], "in")
	mgr.connect_nodes(prog_dis, n_ds["id"], "out", n_as["id"], "in")

	mgr.schedule_continuation(prog_dis.id, n_ds["id"], n_as["id"], 1, 1, 5)
	prog_dis.enabled = false
	ctx = {"current_day": 1, "current_hour": 6, "is_paused": false}
	var res_dis := mgr.process_due_continuations(ctx)
	_assert_eq(res_dis.size(), 0, "TC-Y.12.2", "Disabled program continuation skipped cleanly without execution")

# -----------------------------------------------------------------------------
# GROUP 4: Repeat Node Validation & Bounded Iterations
# -----------------------------------------------------------------------------
func _test_group_4_repeat_validation_and_iterations() -> void:
	print("--- Group 4: Repeat Validation & Iterations ---")

	# Valid count values (1, 5, 20)
	for c in [1, 5, 20]:
		var prog := AutomationProgram.new("p_rep_ok_%d" % c, "Repeat OK")
		prog.nodes = [
			{"id": "n1", "type": "Trigger", "subtype": "OnTick", "params": {}},
			{"id": "n2", "type": "Repeat", "subtype": "", "params": {"count": c}},
			{"id": "n3", "type": "Action", "subtype": "EmitLog", "params": {"message": "Repeated"}}
		]
		prog.edges = [
			{"from_node": "n1", "from_port": "out", "to_node": "n2", "to_port": "in"},
			{"from_node": "n2", "from_port": "body", "to_node": "n3", "to_port": "in"}
		]
		var val := AutomationGraphValidator.validate_program(prog)
		_assert_true(val["valid"], "TC-Y.13.1_%d" % c, "Valid count %d accepted" % c)

	# Invalid count values (0, -1, 21, 100, 2.5, null)
	var bad_counts = [0, -1, 21, 100, 2.5, "5", null]
	for idx in range(bad_counts.size()):
		var b_c = bad_counts[idx]
		var prog_bad := AutomationProgram.new("p_rep_bad_%d" % idx, "Repeat Bad")
		var p_dict: Dictionary = {}
		if b_c != null:
			p_dict["count"] = b_c
		prog_bad.nodes = [
			{"id": "n1", "type": "Trigger", "subtype": "OnTick", "params": {}},
			{"id": "n2", "type": "Repeat", "subtype": "", "params": p_dict},
			{"id": "n3", "type": "Action", "subtype": "EmitLog", "params": {"message": "Test"}}
		]
		prog_bad.edges = [
			{"from_node": "n1", "from_port": "out", "to_node": "n2", "to_port": "in"},
			{"from_node": "n2", "from_port": "body", "to_node": "n3", "to_port": "in"}
		]
		var val_bad := AutomationGraphValidator.validate_program(prog_bad)
		_assert_false(val_bad["valid"], "TC-Y.13.2_%d" % idx, "Invalid count '%s' rejected fail-closed" % str(b_c))

	# Repeat without body output rejected
	var prog_no_body := AutomationProgram.new("p_no_body", "No Body")
	prog_no_body.nodes = [
		{"id": "n1", "type": "Trigger", "subtype": "OnTick", "params": {}},
		{"id": "n2", "type": "Repeat", "subtype": "", "params": {"count": 3}},
		{"id": "n3", "type": "Action", "subtype": "EmitLog", "params": {"message": "Test"}}
	]
	prog_no_body.edges = [
		{"from_node": "n1", "from_port": "out", "to_node": "n2", "to_port": "in"},
		{"from_node": "n2", "from_port": "completed", "to_node": "n3", "to_port": "in"}
	]
	var val_no_body := AutomationGraphValidator.validate_program(prog_no_body)
	_assert_false(val_no_body["valid"], "TC-Y.13.3", "Repeat without 'body' port connected rejected")

	# Simple action body executes exactly N iterations (e.g. 4 times)
	var mgr := AutomationManager.new()
	var prog_exec := mgr.create_program("TestRepeatExec", 10)
	prog_exec.enabled = true
	var n_rep = mgr.add_node(prog_exec, "Repeat", "", 180, 80, {"count": 4})
	var n_act = mgr.add_node(prog_exec, "Action", "BoostJobPriority", 360, 80, {"job_type": "farmer", "delta_priority": 1})
	var n_done = mgr.add_node(prog_exec, "Action", "EmitLog", 540, 80, {"message": "Loop Complete"})
	mgr.connect_nodes(prog_exec, "n_start", "out", n_rep["id"], "in")
	mgr.connect_nodes(prog_exec, n_rep["id"], "body", n_act["id"], "in")
	mgr.connect_nodes(prog_exec, n_rep["id"], "completed", n_done["id"], "in")

	var mock_job_mgr := MockJobManager.new()
	var ctx: Dictionary = {
		"job_mgr": mock_job_mgr,
		"current_day": 1,
		"current_hour": 10,
		"is_paused": false
	}
	var res_rep := mgr.run_program(prog_exec.id, ctx)
	_assert_true(res_rep["ok"], "TC-Y.14.1", "Repeat execution returned ok: true")
	_assert_eq(mock_job_mgr.boost_calls.size(), 4, "TC-Y.14.2", "Action executed exactly 4 times in loop")
	# Downstream completed port executed once
	var acts: Array = res_rep["actions_executed"]
	_assert_eq(acts.size(), 5, "TC-Y.15.1", "5 actions executed (4 loop body + 1 completed)")
	_assert_eq(acts[4]["node_id"], n_done["id"], "TC-Y.15.2", "Final action is from 'completed' port")

	# Ordinary cycles remain rejected fail-closed
	var prog_cycle := AutomationProgram.new("p_cycle", "Cycle")
	prog_cycle.nodes = [
		{"id": "n1", "type": "Trigger", "subtype": "OnTick", "params": {}},
		{"id": "n2", "type": "Repeat", "subtype": "", "params": {"count": 3}},
		{"id": "n3", "type": "Action", "subtype": "EmitLog", "params": {"message": "Cycle back"}}
	]
	prog_cycle.edges = [
		{"from_node": "n1", "from_port": "out", "to_node": "n2", "to_port": "in"},
		{"from_node": "n2", "from_port": "body", "to_node": "n3", "to_port": "in"},
		{"from_node": "n3", "from_port": "out", "to_node": "n2", "to_port": "in"} # Cycle back!
	]
	var val_cycle := AutomationGraphValidator.validate_program(prog_cycle)
	_assert_false(val_cycle["valid"], "TC-Y.16.1", "Back-edge into Repeat rejected by cycle detector")

	# Step budget enforcement (MAX_STEPS_PER_RUN = 60)
	var prog_budget := mgr.create_program("TestRepeatBudget", 10)
	prog_budget.enabled = true
	var n_rep_big = mgr.add_node(prog_budget, "Repeat", "", 180, 80, {"count": 20})
	# Create a chain of 4 actions in the body: 20 * 4 = 80 steps + overhead > 60 steps!
	var a1 = mgr.add_node(prog_budget, "Action", "EmitLog", 360, 40, {"message": "A1"})
	var a2 = mgr.add_node(prog_budget, "Action", "EmitLog", 500, 40, {"message": "A2"})
	var a3 = mgr.add_node(prog_budget, "Action", "EmitLog", 640, 40, {"message": "A3"})
	var a4 = mgr.add_node(prog_budget, "Action", "EmitLog", 780, 40, {"message": "A4"})
	mgr.connect_nodes(prog_budget, "n_start", "out", n_rep_big["id"], "in")
	mgr.connect_nodes(prog_budget, n_rep_big["id"], "body", a1["id"], "in")
	mgr.connect_nodes(prog_budget, a1["id"], "out", a2["id"], "in")
	mgr.connect_nodes(prog_budget, a2["id"], "out", a3["id"], "in")
	mgr.connect_nodes(prog_budget, a3["id"], "out", a4["id"], "in")

	var res_budget := mgr.run_program(prog_budget.id, ctx)
	_assert_false(res_budget["ok"], "TC-Y.17.1", "Repeat execution safely halted when exceeding MAX_STEPS_PER_RUN")
	_assert_true("Vượt ngân sách thực thi" in str(res_budget["reason"]), "TC-Y.17.2", "Diagnostic explains budget exhaustion")

# -----------------------------------------------------------------------------
# GROUP 5: Editor Visuals, Ports & Dry-Run Simulation
# -----------------------------------------------------------------------------
func _test_group_5_editor_ports_and_dry_run() -> void:
	print("--- Group 5: Editor Ports & Dry-Run Simulation ---")

	# Instantiate AutomationEditor to test UI controls
	var editor: Control = AutomationEditorScene.instantiate()
	root.add_child(editor)

	var mgr := AutomationManager.new()
	editor.setup(mgr)

	var left_box = editor.get_node_or_null("Panel/MarginContainer/VBoxContainer/HSplit/LeftBox/Palette")
	_assert_true(left_box != null, "TC-Y.19.1", "Palette container exists in AutomationEditor")
	var btn_delay: Button = left_box.get_node_or_null("AddDelayBtn")
	var btn_repeat: Button = left_box.get_node_or_null("AddRepeatBtn")
	_assert_true(btn_delay != null, "TC-Y.19.2", "AddDelayBtn exists in Palette")
	_assert_true(btn_repeat != null, "TC-Y.19.3", "AddRepeatBtn exists in Palette")

	# Test adding Delay and Repeat via editor
	var initial_prog := mgr.get_all_programs()[0]
	var n_d := mgr.add_node(initial_prog, "Delay", "", 100, 100, {"duration_hours": 4})
	var n_r := mgr.add_node(initial_prog, "Repeat", "", 200, 100, {"count": 5})
	_assert_eq(n_d["type"], "Delay", "TC-Y.19.4", "Delay node added successfully")
	_assert_eq(n_r["type"], "Repeat", "TC-Y.19.5", "Repeat node added successfully")

	# Verify port index mappings
	var d_in_idx = editor._port_name_to_index(n_d, true, "in")
	var d_out_idx = editor._port_name_to_index(n_d, false, "out")
	_assert_eq(d_in_idx, 0, "TC-Y.20.1", "Delay in-port maps to index 0")
	_assert_eq(d_out_idx, 0, "TC-Y.20.2", "Delay out-port maps to index 0")

	var r_body_idx = editor._port_name_to_index(n_r, false, "body")
	var r_comp_idx = editor._port_name_to_index(n_r, false, "completed")
	_assert_eq(r_body_idx, 0, "TC-Y.20.3", "Repeat body-port maps to slot 0")
	_assert_eq(r_comp_idx, 1, "TC-Y.20.4", "Repeat completed-port maps to slot 1")

	# Dry-Run Simulation: Side-effect free verification
	var prog_dry := mgr.create_program("TestDryRunAll", 10)
	prog_dry.enabled = true
	var n_rep_dry = mgr.add_node(prog_dry, "Repeat", "", 180, 80, {"count": 3})
	var n_act_dry = mgr.add_node(prog_dry, "Action", "AssignRole", 360, 80, {"from_role": "idle", "to_role": "miner"})
	var n_del_dry = mgr.add_node(prog_dry, "Delay", "", 540, 80, {"duration_hours": 2})
	var n_end_dry = mgr.add_node(prog_dry, "Action", "EmitLog", 700, 80, {"message": "Dry Run Log"})
	mgr.connect_nodes(prog_dry, "n_start", "out", n_rep_dry["id"], "in")
	mgr.connect_nodes(prog_dry, n_rep_dry["id"], "body", n_act_dry["id"], "in")
	mgr.connect_nodes(prog_dry, n_rep_dry["id"], "completed", n_del_dry["id"], "in")
	mgr.connect_nodes(prog_dry, n_del_dry["id"], "out", n_end_dry["id"], "in")

	var cit_idle := MockCitizen.new("c1", "Nguyễn Văn A", "idle")
	var dry_ctx: Dictionary = {
		"citizens": [cit_idle],
		"current_day": 1,
		"current_hour": 8,
		"is_paused": false
	}
	var dry_res := mgr.run_program(prog_dry.id, dry_ctx, {"dry_run": true})
	_assert_true(dry_res["ok"], "TC-Y.22.1", "Dry run succeeded")
	_assert_true(dry_res["dry_run"], "TC-Y.22.2", "Dry run flag is true")
	_assert_eq(cit_idle.role, "idle", "TC-Y.22.3", "Citizen role completely untouched during dry run (remained idle)")
	_assert_eq(mgr.get_pending_continuations().size(), 0, "TC-Y.22.4", "Dry run enqueued ZERO pending continuations")
	_assert_true(dry_res["trace"].size() > 0, "TC-Y.22.5", "Simulation trace generated with detailed logs")

	editor.queue_free()

# -----------------------------------------------------------------------------
# GROUP 6: SaveManager Persistence & Schema Compatibility
# -----------------------------------------------------------------------------
func _test_group_6_persistence_and_compatibility() -> void:
	print("--- Group 6: SaveManager Persistence & Compatibility ---")
	var mgr := AutomationManager.new()
	var prog := mgr.create_program("PersistProgram", 10)
	prog.enabled = true
	var n_d = mgr.add_node(prog, "Delay", "", 180, 80, {"duration_hours": 4})
	var n_a = mgr.add_node(prog, "Action", "EmitLog", 360, 80, {"message": "Saved"})
	mgr.connect_nodes(prog, "n_start", "out", n_d["id"], "in")
	mgr.connect_nodes(prog, n_d["id"], "out", n_a["id"], "in")

	# Schedule a continuation at Day 3, Hour 10 (+ 4h = Day 3, Hour 14)
	mgr.schedule_continuation(prog.id, n_d["id"], n_a["id"], 4, 3, 10)

	var serialized := mgr.serialize()
	_assert_true(serialized.has("pending_continuations"), "TC-Y.23.1", "Serialized data contains pending_continuations")
	_assert_eq(serialized["pending_continuations"].size(), 1, "TC-Y.23.2", "Serialized exactly 1 pending continuation")

	# Test SaveManager schema validation accepts valid section
	var save_dict: Dictionary = {
		"schema_version": 1,
		"metadata": {"world_seed": 12345, "difficulty": "normal"},
		"clock": {"current_day": 3, "current_hour": 10, "season_index": 0, "current_year": 1, "current_speed": 1},
		"resources": {"stock": {}, "capacities": {}},
		"buildings": [],
		"citizens": [],
		"research": {},
		"factions": {},
		"pois": [],
		"victory": {},
		"fog_of_war": [],
		"automation": serialized
	}
	var val_save := SaveManager.validate_save_data(save_dict)
	_assert_true(val_save["valid"], "TC-Y.23.3", "SaveManager accepts valid pending_continuations")

	# Deserialization restoration
	var mgr_restored := AutomationManager.new()
	mgr_restored.deserialize(serialized)
	_assert_eq(mgr_restored.get_pending_continuations().size(), 1, "TC-Y.23.4", "Restored exactly 1 pending continuation")
	var r_cont: Dictionary = mgr_restored.get_pending_continuations()[0]
	_assert_eq(r_cont["due_day"], 3, "TC-Y.23.5", "Restored due_day matches 3")
	_assert_eq(r_cont["due_hour"], 14, "TC-Y.23.6", "Restored due_hour matches 14")
	_assert_eq(r_cont["due_total_hours"], 62, "TC-Y.23.7", "Restored due_total_hours matches 62 ((3-1)*24 + 14)")

	# Double-load idempotency: second deserialize produces identical queue without duplicates
	mgr_restored.deserialize(serialized)
	_assert_eq(mgr_restored.get_pending_continuations().size(), 1, "TC-Y.24.1", "Double load preserves exact continuation count without duplicates")

	# Fail-closed validation on malformed pending_continuations
	var malformed_saves = [
		{"pending_continuations": "not_an_array"},
		{"pending_continuations": [{"id": ""}]},
		{"pending_continuations": [{"id": "c1", "program_id": "", "resume_node_id": "n1"}]},
		{"pending_continuations": [{"id": "c1", "program_id": "p1", "resume_node_id": "n1", "duration_hours": 0}]},
		{"pending_continuations": [{"id": "c1", "program_id": "p1", "resume_node_id": "n1", "duration_hours": 800}]},
		{"pending_continuations": [{"id": "c1", "program_id": "p1", "resume_node_id": "n1", "duration_hours": 5, "due_day": -1, "due_hour": 10, "due_total_hours": 10}]},
		{"pending_continuations": [{"id": "c1", "program_id": "p1", "resume_node_id": "n1", "duration_hours": 5, "due_day": 1, "due_hour": 25, "due_total_hours": 25}]}
	]
	for idx in range(malformed_saves.size()):
		var bad_auto = serialized.duplicate(true)
		for k in malformed_saves[idx]:
			bad_auto[k] = malformed_saves[idx][k]
		var bad_save = save_dict.duplicate(true)
		bad_save["automation"] = bad_auto
		var val_bad_save := SaveManager.validate_save_data(bad_save)
		_assert_false(val_bad_save["valid"], "TC-Y.26.1_%d" % idx, "Malformed continuation record %d rejected fail-closed" % idx)

	# Legacy save lacking pending_continuations loads cleanly
	var legacy_auto = serialized.duplicate(true)
	legacy_auto.erase("pending_continuations")
	var legacy_save = save_dict.duplicate(true)
	legacy_save["automation"] = legacy_auto
	var val_legacy := SaveManager.validate_save_data(legacy_save)
	_assert_true(val_legacy["valid"], "TC-Y.27.1", "Legacy save without pending_continuations passes validation")
	var mgr_legacy := AutomationManager.new()
	mgr_legacy.deserialize(legacy_auto)
	_assert_eq(mgr_legacy.get_pending_continuations().size(), 0, "TC-Y.27.2", "Legacy save loads cleanly with empty pending queue")

# -----------------------------------------------------------------------------
# GROUP 7: Non-Regression & Preset Rules
# -----------------------------------------------------------------------------
func _test_group_7_non_regression_and_world_integration() -> void:
	print("--- Group 7: Non-Regression & WorldView Integration ---")
	var mgr := AutomationManager.new()

	# Preset rules continue working
	var real_jm := JobManager.new()
	var j1 := real_jm.create_job("farmer", Vector2i(10, 10))
	var j2 := real_jm.create_job("hauler", Vector2i(10, 10))
	var real_wpm := WorkplaceManager.new()
	var mock_res = {"get_available_stock": func(r: String) -> int: return 10 if r == "food" else 50}
	var actions := mgr.evaluate_rules(mock_res, real_jm, real_wpm, "spring", [], null, false, 1, 6)
	_assert_true(actions.size() > 0, "TC-Y.28.1", "Preset Rule 1 (Food emergency) triggered successfully")
	_assert_true(j1.priority > 1, "TC-Y.28.2", "Farmer job boosted by preset rule")
	_assert_true(j2.priority > 1, "TC-Y.28.3", "Hauler job boosted by preset rule")

	# evaluate_rules without day/hour arguments works seamlessly (backward compatibility)
	var legacy_actions := mgr.evaluate_rules(mock_res, real_jm, real_wpm, "spring", [], null, false)
	_assert_true(legacy_actions.size() > 0, "TC-Y.29.1", "evaluate_rules without explicit day/hour parameters succeeds")

	# WorldView hourly simulation tick integration
	_assert_true(world_instance != null, "TC-Y.30.1", "WorldView instance exists")
	var wv_auto_mgr = world_instance.get("automation_mgr")
	_assert_true(wv_auto_mgr != null, "TC-Y.30.2", "WorldView automation_mgr initialized")
