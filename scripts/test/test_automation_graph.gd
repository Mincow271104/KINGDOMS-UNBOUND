extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — Package 1V: Functional Automation Graph MVP
## Validates:
## - TC-AGRAPH.1: Data model & Serialization of AutomationProgram
## - TC-AGRAPH.2: Validator rejects empty graphs, missing triggers, duplicate IDs
## - TC-AGRAPH.3: Validator detects orphan & unreachable nodes
## - TC-AGRAPH.4: Validator enforces port/socket compatibility (Flow vs Boolean)
## - TC-AGRAPH.5: Validator detects cycles & infinite loop risks fail-closed
## - TC-AGRAPH.6: Validator enforces IfElse condition input and branch requirements
## - TC-AGRAPH.7: Condition node evaluation (ResourceCompare, CitizenFatigue, StorageFull)
## - TC-AGRAPH.8: LogicGate evaluation (AND, OR, NOT combinational gates)
## - TC-AGRAPH.9: IfElse runtime branching (takes True branch on true, False branch on false)
## - TC-AGRAPH.10: Action AssignRole execution, action locking & Barracks requirement for guards
## - TC-AGRAPH.11: Action BoostJobPriority and EmitLog execution
## - TC-AGRAPH.12: Strict execution budget enforcement (MAX_STEPS_PER_RUN = 60)
## - TC-AGRAPH.13: Dry Run simulation guarantee (100% side-effect-free immutability)
## - TC-AGRAPH.14: Priority-ordered execution & pause respect
## - TC-AGRAPH.15: SaveManager persistence, fail-closed validation & legacy save compatibility
## - TC-AGRAPH.16: Non-regression of existing preset automation rules

const AutomationProgramScript = preload("res://scripts/economy/automation_program.gd")
const AutomationGraphValidatorScript = preload("res://scripts/economy/automation_graph_validator.gd")
const AutomationManagerScript = preload("res://scripts/economy/automation_manager.gd")
const SaveManagerScript = preload("res://scripts/persistence/save_manager.gd")
const EconomyConfigScript = preload("res://scripts/economy/economy_config.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const WorldViewScene: PackedScene = preload("res://scenes/world/world_view.tscn")

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

var frame_count: int = 0
var world_instance: Node = null
var failures: int = 0
var passed_checks: int = 0

func _init() -> void:
	print("\n========================================================")
	print("  STARTING PACKAGE 1V AUTOMATION GRAPH MVP TESTS")
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
			print("  ALL PACKAGE 1V AUTOMATION GRAPH TESTS PASSED! (Exit Code 0)")
			print("--------------------------------------------------------\n")
			quit(0)
			return true
		else:
			printerr("  PACKAGE 1V AUTOMATION GRAPH TESTS FAILED WITH %d FAILURES! (Exit Code 1)" % failures)
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
	_test_tc_agraph_1_model_and_serialization()
	_test_tc_agraph_2_validator_structure_and_ids()
	_test_tc_agraph_3_validator_orphans_and_reachability()
	_test_tc_agraph_4_validator_port_types()
	_test_tc_agraph_5_validator_cycle_detection()
	_test_tc_agraph_6_validator_ifelse_constraints()
	_test_tc_agraph_7_condition_evaluation()
	_test_tc_agraph_8_logic_gates()
	_test_tc_agraph_9_ifelse_branching_runtime()
	_test_tc_agraph_10_action_assign_role()
	_test_tc_agraph_11_action_boost_job_and_emit_log()
	_test_tc_agraph_12_step_budget_exhaustion()
	_test_tc_agraph_13_dry_run_immutability()
	_test_tc_agraph_14_priority_execution_order()
	_test_tc_agraph_15_persistence_and_legacy_compatibility()
	_test_tc_agraph_16_preset_rules_non_regression()

# -----------------------------------------------------------------------------
# TC-AGRAPH.1: Data model & Serialization of AutomationProgram
# -----------------------------------------------------------------------------
func _test_tc_agraph_1_model_and_serialization() -> void:
	var prog := AutomationProgram.new("prog_test_1", "Test Program", 15)
	prog.enabled = true
	prog.nodes = [
		{"id": "n1", "type": "Trigger", "subtype": "OnTick", "x": 10.0, "y": 20.0, "params": {}},
		{"id": "n2", "type": "Action", "subtype": "EmitLog", "x": 100.0, "y": 20.0, "params": {"message": "Hello"}}
	]
	prog.edges = [
		{"id": "e1", "from_node": "n1", "from_port": "out", "to_node": "n2", "to_port": "in"}
	]

	var serialized := prog.serialize()
	_assert_eq(serialized["id"], "prog_test_1", "TC-AGRAPH.1.1", "ID serialized correctly")
	_assert_eq(serialized["name"], "Test Program", "TC-AGRAPH.1.2", "Name serialized correctly")
	_assert_eq(serialized["priority"], 15, "TC-AGRAPH.1.3", "Priority serialized correctly")
	_assert_true(serialized["enabled"], "TC-AGRAPH.1.4", "Enabled flag serialized correctly")
	_assert_eq(serialized["nodes"].size(), 2, "TC-AGRAPH.1.5", "Nodes serialized correctly")
	_assert_eq(serialized["edges"].size(), 1, "TC-AGRAPH.1.6", "Edges serialized correctly")

	var deserialized := AutomationProgram.deserialize(serialized)
	_assert_eq(deserialized.id, "prog_test_1", "TC-AGRAPH.1.7", "Deserialized ID matches")
	_assert_eq(deserialized.name, "Test Program", "TC-AGRAPH.1.8", "Deserialized Name matches")
	_assert_eq(deserialized.priority, 15, "TC-AGRAPH.1.9", "Deserialized Priority matches")
	_assert_true(deserialized.enabled, "TC-AGRAPH.1.10", "Deserialized Enabled matches")
	_assert_eq(deserialized.nodes.size(), 2, "TC-AGRAPH.1.11", "Deserialized Nodes match")
	_assert_eq(deserialized.edges.size(), 1, "TC-AGRAPH.1.12", "Deserialized Edges match")

# -----------------------------------------------------------------------------
# TC-AGRAPH.2: Validator rejects empty graphs, missing triggers, duplicate IDs
# -----------------------------------------------------------------------------
func _test_tc_agraph_2_validator_structure_and_ids() -> void:
	# Null program
	var r_null := AutomationGraphValidator.validate_program(null)
	_assert_false(r_null["valid"], "TC-AGRAPH.2.1", "Null program rejected")

	# Empty nodes array
	var prog_empty := AutomationProgram.new("p_empty", "Empty")
	prog_empty.nodes = []
	var r_empty := AutomationGraphValidator.validate_program(prog_empty)
	_assert_false(r_empty["valid"], "TC-AGRAPH.2.2", "Empty nodes array rejected")

	# Missing Trigger
	var prog_no_trig := AutomationProgram.new("p_no_trig", "No Trigger")
	prog_no_trig.nodes = [{"id": "n1", "type": "Action", "subtype": "EmitLog", "params": {}}]
	var r_no_trig := AutomationGraphValidator.validate_program(prog_no_trig)
	_assert_false(r_no_trig["valid"], "TC-AGRAPH.2.3", "Missing trigger rejected")

	# Duplicate node IDs
	var prog_dup := AutomationProgram.new("p_dup", "Duplicate ID")
	prog_dup.nodes = [
		{"id": "n_trig", "type": "Trigger", "subtype": "OnTick", "params": {}},
		{"id": "n_trig", "type": "Action", "subtype": "EmitLog", "params": {}}
	]
	var r_dup := AutomationGraphValidator.validate_program(prog_dup)
	_assert_false(r_dup["valid"], "TC-AGRAPH.2.4", "Duplicate node ID rejected")

	# Invalid node type
	var prog_bad_type := AutomationProgram.new("p_bad_type", "Bad Type")
	prog_bad_type.nodes = [
		{"id": "n_trig", "type": "Trigger", "subtype": "OnTick", "params": {}},
		{"id": "n_bad", "type": "InvalidTypeFoo", "params": {}}
	]
	var r_bad_type := AutomationGraphValidator.validate_program(prog_bad_type)
	_assert_false(r_bad_type["valid"], "TC-AGRAPH.2.5", "Invalid node type rejected")

# -----------------------------------------------------------------------------
# TC-AGRAPH.3: Validator detects orphan & unreachable nodes
# -----------------------------------------------------------------------------
func _test_tc_agraph_3_validator_orphans_and_reachability() -> void:
	# Graph with orphan action node
	var prog_orphan := AutomationProgram.new("p_orphan", "Orphan")
	prog_orphan.nodes = [
		{"id": "n_trig", "type": "Trigger", "subtype": "OnTick", "params": {}},
		{"id": "n_act1", "type": "Action", "subtype": "EmitLog", "params": {}},
		{"id": "n_orphan", "type": "Action", "subtype": "EmitLog", "params": {}}
	]
	prog_orphan.edges = [
		{"from_node": "n_trig", "from_port": "out", "to_node": "n_act1", "to_port": "in"}
	]
	var r_orphan := AutomationGraphValidator.validate_program(prog_orphan)
	_assert_false(r_orphan["valid"], "TC-AGRAPH.3.1", "Orphan node rejected")
	_assert_true(r_orphan["errors"].any(func(e: String) -> bool: return e.contains("Orphan")), "TC-AGRAPH.3.2", "Error mentions orphan")

	# Valid connected graph without orphans
	var prog_valid := AutomationProgram.new("p_valid", "Valid Reachable")
	prog_valid.nodes = [
		{"id": "n_trig", "type": "Trigger", "subtype": "OnTick", "params": {}},
		{"id": "n_act1", "type": "Action", "subtype": "EmitLog", "params": {}}
	]
	prog_valid.edges = [
		{"from_node": "n_trig", "from_port": "out", "to_node": "n_act1", "to_port": "in"}
	]
	var r_valid := AutomationGraphValidator.validate_program(prog_valid)
	_assert_true(r_valid["valid"], "TC-AGRAPH.3.3", "Fully connected graph validated")

# -----------------------------------------------------------------------------
# TC-AGRAPH.4: Validator enforces port/socket compatibility (Flow vs Boolean)
# -----------------------------------------------------------------------------
func _test_tc_agraph_4_validator_port_types() -> void:
	var prog := AutomationProgram.new("p_ports", "Port Check")
	prog.nodes = [
		{"id": "n_trig", "type": "Trigger", "subtype": "OnTick", "params": {}},
		{"id": "n_logic", "type": "LogicGate", "subtype": "AND", "params": {}},
		{"id": "n_act", "type": "Action", "subtype": "EmitLog", "params": {}}
	]
	# Flow out into boolean inA on LogicGate
	prog.edges = [
		{"from_node": "n_trig", "from_port": "out", "to_node": "n_logic", "to_port": "inA"},
		{"from_node": "n_logic", "from_port": "bool", "to_node": "n_act", "to_port": "in"}
	]
	var res := AutomationGraphValidator.validate_program(prog)
	_assert_false(res["valid"], "TC-AGRAPH.4.1", "Flow out connecting to boolean port inA rejected")

	# Self connection
	var prog_self := AutomationProgram.new("p_self", "Self Connect")
	prog_self.nodes = [{"id": "n_trig", "type": "Trigger", "subtype": "OnTick", "params": {}}]
	prog_self.edges = [{"from_node": "n_trig", "from_port": "out", "to_node": "n_trig", "to_port": "in"}]
	var res_self := AutomationGraphValidator.validate_program(prog_self)
	_assert_false(res_self["valid"], "TC-AGRAPH.4.2", "Self-connection rejected")

# -----------------------------------------------------------------------------
# TC-AGRAPH.5: Validator detects cycles & infinite loop risks fail-closed
# -----------------------------------------------------------------------------
func _test_tc_agraph_5_validator_cycle_detection() -> void:
	var prog := AutomationProgram.new("p_cycle", "Cycle Loop")
	prog.nodes = [
		{"id": "n_trig", "type": "Trigger", "subtype": "OnTick", "params": {}},
		{"id": "n_a", "type": "Action", "subtype": "EmitLog", "params": {}},
		{"id": "n_b", "type": "Action", "subtype": "EmitLog", "params": {}}
	]
	# n_trig -> n_a -> n_b -> n_a (cycle between a and b)
	prog.edges = [
		{"from_node": "n_trig", "from_port": "out", "to_node": "n_a", "to_port": "in"},
		{"from_node": "n_a", "from_port": "out", "to_node": "n_b", "to_port": "in"},
		{"from_node": "n_b", "from_port": "out", "to_node": "n_a", "to_port": "in"}
	]
	var res := AutomationGraphValidator.validate_program(prog)
	_assert_false(res["valid"], "TC-AGRAPH.5.1", "Cycle detected and rejected")
	_assert_true(res["errors"].any(func(e: String) -> bool: return e.contains("chu trình lặp")), "TC-AGRAPH.5.2", "Error specifies cycle risk")

# -----------------------------------------------------------------------------
# TC-AGRAPH.6: Validator enforces IfElse condition input and branch requirements
# -----------------------------------------------------------------------------
func _test_tc_agraph_6_validator_ifelse_constraints() -> void:
	# IfElse missing condition input
	var p_no_cond := AutomationProgram.new("p_if_no_cond", "If No Cond")
	p_no_cond.nodes = [
		{"id": "n_trig", "type": "Trigger", "subtype": "OnTick", "params": {}},
		{"id": "n_if", "type": "IfElse", "subtype": "Branch", "params": {}},
		{"id": "n_act", "type": "Action", "subtype": "EmitLog", "params": {}}
	]
	p_no_cond.edges = [
		{"from_node": "n_trig", "from_port": "out", "to_node": "n_if", "to_port": "in"},
		{"from_node": "n_if", "from_port": "true", "to_node": "n_act", "to_port": "in"}
	]
	var r_no_cond := AutomationGraphValidator.validate_program(p_no_cond)
	_assert_false(r_no_cond["valid"], "TC-AGRAPH.6.1", "IfElse without condition input rejected")

	# IfElse missing both True and False outputs
	var p_no_out := AutomationProgram.new("p_if_no_out", "If No Output")
	p_no_out.nodes = [
		{"id": "n_trig", "type": "Trigger", "subtype": "OnTick", "params": {}},
		{"id": "n_cond", "type": "Condition", "subtype": "ResourceCompare", "params": {"resource": "Food", "op": "<", "value": 50}},
		{"id": "n_if", "type": "IfElse", "subtype": "Branch", "params": {}}
	]
	p_no_out.edges = [
		{"from_node": "n_trig", "from_port": "out", "to_node": "n_cond", "to_port": "in"},
		{"from_node": "n_cond", "from_port": "bool", "to_node": "n_if", "to_port": "cond"}
	]
	var r_no_out := AutomationGraphValidator.validate_program(p_no_out)
	_assert_false(r_no_out["valid"], "TC-AGRAPH.6.2", "IfElse without True or False outputs rejected")

# -----------------------------------------------------------------------------
# TC-AGRAPH.7: Condition node evaluation (ResourceCompare, CitizenFatigue, StorageFull)
# -----------------------------------------------------------------------------
func _test_tc_agraph_7_condition_evaluation() -> void:
	var auto_mgr := AutomationManagerScript.new()
	var mock_rm := {}
	var stocks := {"food": 40, "gold": 120, "wood": 100}
	var caps := {"food": 100, "wood": 100, "stone": 100, "ore": 100, "metal": 100, "tools": 100, "gold": 500}
	mock_rm["get_available_stock"] = func(r: String) -> int: return stocks.get(r, 0)
	mock_rm["get_total_stock"] = func(r: String) -> int: return stocks.get(r, 0)
	mock_rm["get_capacity"] = func(r: String) -> int: return caps.get(r, 500)

	var c1 := MockCitizen.new("c1", "Alice", "farmer", 90.0)
	var c2 := MockCitizen.new("c2", "Bob", "idle", 30.0)
	var ctx := {
		"resource_mgr": mock_rm,
		"citizens": [c1, c2],
		"current_day": 1
	}

	var prog := AutomationProgram.new("p_eval", "Eval")
	# ResourceCompare: Food < 50 (should be TRUE since 40 < 50)
	var n_food_lt := {"id": "c_food_lt", "type": "Condition", "subtype": "ResourceCompare", "params": {"resource": "Food", "op": "<", "value": 50}}
	var memo := {}
	var res_lt := auto_mgr.evaluate_condition_node(n_food_lt, prog, ctx, memo)
	_assert_true(res_lt, "TC-AGRAPH.7.1", "ResourceCompare: Food 40 < 50 is TRUE")

	# ResourceCompare: Food > 50 (should be FALSE since 40 > 50 is false)
	var n_food_gt := {"id": "c_food_gt", "type": "Condition", "subtype": "ResourceCompare", "params": {"resource": "Food", "op": ">", "value": 50}}
	memo.clear()
	var res_gt := auto_mgr.evaluate_condition_node(n_food_gt, prog, ctx, memo)
	_assert_false(res_gt, "TC-AGRAPH.7.2", "ResourceCompare: Food 40 > 50 is FALSE")

	# ResourceCompare: Treasury/Gold == 120 (should be TRUE)
	var n_gold_eq := {"id": "c_gold_eq", "type": "Condition", "subtype": "ResourceCompare", "params": {"resource": "Gold", "op": "==", "value": 120}}
	memo.clear()
	var res_gold := auto_mgr.evaluate_condition_node(n_gold_eq, prog, ctx, memo)
	_assert_true(res_gold, "TC-AGRAPH.7.3", "ResourceCompare: Gold 120 == 120 is TRUE")

	# CitizenFatigue: Threshold 80 (c1 has 90 -> TRUE)
	var n_fat := {"id": "c_fat", "type": "Condition", "subtype": "CitizenFatigue", "params": {"value": 80}}
	memo.clear()
	var res_fat := auto_mgr.evaluate_condition_node(n_fat, prog, ctx, memo)
	_assert_true(res_fat, "TC-AGRAPH.7.4", "CitizenFatigue: Fatigue 90 > 80 is TRUE")

	# StorageFull: Wood is 100/100 -> TRUE
	var n_store := {"id": "c_store", "type": "Condition", "subtype": "StorageFull", "params": {}}
	memo.clear()
	var res_store := auto_mgr.evaluate_condition_node(n_store, prog, ctx, memo)
	_assert_true(res_store, "TC-AGRAPH.7.5", "StorageFull: Wood 100/100 triggers full storage")

# -----------------------------------------------------------------------------
# TC-AGRAPH.8: LogicGate evaluation (AND, OR, NOT combinational gates)
# -----------------------------------------------------------------------------
func _test_tc_agraph_8_logic_gates() -> void:
	var auto_mgr := AutomationManagerScript.new()
	var mock_rm = {
		"get_available_stock": func(r: String) -> int: return 40 if r == "food" else 10
	}
	var ctx := {"resource_mgr": mock_rm, "current_day": 1}

	var prog := AutomationProgram.new("p_logic", "Logic")
	var n_c1 := {"id": "c1", "type": "Condition", "subtype": "ResourceCompare", "params": {"resource": "Food", "op": "<", "value": 50}} # TRUE (40 < 50)
	var n_c2 := {"id": "c2", "type": "Condition", "subtype": "ResourceCompare", "params": {"resource": "Wood", "op": ">", "value": 50}} # FALSE (10 > 50)
	var n_and := {"id": "g_and", "type": "LogicGate", "subtype": "AND", "params": {}}
	var n_or := {"id": "g_or", "type": "LogicGate", "subtype": "OR", "params": {}}
	var n_not := {"id": "g_not", "type": "LogicGate", "subtype": "NOT", "params": {}}

	prog.nodes = [n_c1, n_c2, n_and, n_or, n_not]
	prog.edges = [
		{"from_node": "c1", "to_node": "g_and"},
		{"from_node": "c2", "to_node": "g_and"},
		{"from_node": "c1", "to_node": "g_or"},
		{"from_node": "c2", "to_node": "g_or"},
		{"from_node": "c1", "to_node": "g_not"}
	]

	var memo := {}
	var res_and := auto_mgr.evaluate_condition_node(n_and, prog, ctx, memo)
	_assert_false(res_and, "TC-AGRAPH.8.1", "LogicGate AND: True AND False is FALSE")

	var res_or := auto_mgr.evaluate_condition_node(n_or, prog, ctx, memo)
	_assert_true(res_or, "TC-AGRAPH.8.2", "LogicGate OR: True OR False is TRUE")

	var res_not := auto_mgr.evaluate_condition_node(n_not, prog, ctx, memo)
	_assert_false(res_not, "TC-AGRAPH.8.3", "LogicGate NOT: NOT True is FALSE")

# -----------------------------------------------------------------------------
# TC-AGRAPH.9: IfElse runtime branching (takes True branch on true, False branch on false)
# -----------------------------------------------------------------------------
func _test_tc_agraph_9_ifelse_branching_runtime() -> void:
	var auto_mgr := AutomationManagerScript.new()
	var prog := auto_mgr.create_program("IfElseBranchTest", 10)
	var n_cond := auto_mgr.add_node(prog, "Condition", "ResourceCompare", 160, 80, {"resource": "Food", "op": "<", "value": 50})
	var n_if := auto_mgr.add_node(prog, "IfElse", "Branch", 320, 80, {})
	var n_act_t := auto_mgr.add_node(prog, "Action", "EmitLog", 480, 40, {"message": "Branch TRUE ran"})
	var n_act_f := auto_mgr.add_node(prog, "Action", "EmitLog", 480, 140, {"message": "Branch FALSE ran"})

	auto_mgr.connect_nodes(prog, "n_start", "out", n_cond["id"], "in")
	auto_mgr.connect_nodes(prog, n_cond["id"], "bool", n_if["id"], "cond")
	auto_mgr.connect_nodes(prog, n_if["id"], "true", n_act_t["id"], "in")
	auto_mgr.connect_nodes(prog, n_if["id"], "false", n_act_f["id"], "in")

	# Test Case A: Food = 80 (Condition 80 < 50 is FALSE -> executes False branch)
	var mock_rm_false = {"get_available_stock": func(_r: String) -> int: return 80}
	var ctx_false := {"resource_mgr": mock_rm_false, "current_day": 1}
	var res_f := auto_mgr.run_program(prog.id, ctx_false, {"dry_run": false})
	_assert_true(res_f["ok"], "TC-AGRAPH.9.1", "Run with False condition succeeded")
	var acts_f: Array = res_f["actions_executed"]
	_assert_eq(acts_f.size(), 1, "TC-AGRAPH.9.2", "Exactly 1 action executed on False branch")
	_assert_eq(acts_f[0]["detail"], "Branch FALSE ran", "TC-AGRAPH.9.3", "False branch action executed")

	# Test Case B: Food = 30 (Condition 30 < 50 is TRUE -> executes True branch)
	var mock_rm_true = {"get_available_stock": func(_r: String) -> int: return 30}
	var ctx_true := {"resource_mgr": mock_rm_true, "current_day": 1}
	var res_t := auto_mgr.run_program(prog.id, ctx_true, {"dry_run": false})
	_assert_true(res_t["ok"], "TC-AGRAPH.9.4", "Run with True condition succeeded")
	var acts_t: Array = res_t["actions_executed"]
	_assert_eq(acts_t.size(), 1, "TC-AGRAPH.9.5", "Exactly 1 action executed on True branch")
	_assert_eq(acts_t[0]["detail"], "Branch TRUE ran", "TC-AGRAPH.9.6", "True branch action executed")

# -----------------------------------------------------------------------------
# TC-AGRAPH.10: Action AssignRole execution, action locking & Barracks requirement for guards
# -----------------------------------------------------------------------------
func _test_tc_agraph_10_action_assign_role() -> void:
	var auto_mgr := AutomationManagerScript.new()
	var prog := auto_mgr.create_program("AssignRoleTest", 10)
	var n_act := auto_mgr.add_node(prog, "Action", "AssignRole", 200, 80, {"from_role": "idle", "to_role": "woodcutter"})
	auto_mgr.connect_nodes(prog, "n_start", "out", n_act["id"], "in")

	var cit_1 := MockCitizen.new("cit_101", "Citizen One", "idle")
	var ctx := {
		"citizens": [cit_1],
		"current_day": 1
	}

	var res := auto_mgr.run_program(prog.id, ctx, {"dry_run": false})
	_assert_true(res["ok"], "TC-AGRAPH.10.1", "AssignRole executed successfully")
	_assert_eq(cit_1.role, "woodcutter", "TC-AGRAPH.10.2", "Citizen role changed to woodcutter")

	# Test Barracks requirement for Guard role
	var prog_guard := auto_mgr.create_program("AssignGuardTest", 10)
	var n_guard_act := auto_mgr.add_node(prog_guard, "Action", "AssignRole", 200, 80, {"from_role": "idle", "to_role": "guard"})
	auto_mgr.connect_nodes(prog_guard, "n_start", "out", n_guard_act["id"], "in")

	var cit_2 := MockCitizen.new("cit_102", "Citizen Two", "idle")
	var empty_world_data := WorldGenerator.WorldData.new() # Inactive/no barracks
	var ctx_guard := {
		"citizens": [cit_2],
		"world_data": empty_world_data,
		"current_day": 1
	}
	var res_guard := auto_mgr.run_program(prog_guard.id, ctx_guard, {"dry_run": false})
	_assert_true(res_guard["ok"], "TC-AGRAPH.10.3", "Run finished")
	_assert_eq(cit_2.role, "idle", "TC-AGRAPH.10.4", "Guard assignment blocked when Barracks is inactive")

# -----------------------------------------------------------------------------
# TC-AGRAPH.11: Action BoostJobPriority and EmitLog execution
# -----------------------------------------------------------------------------
func _test_tc_agraph_11_action_boost_job_and_emit_log() -> void:
	var auto_mgr := AutomationManagerScript.new()
	var prog := auto_mgr.create_program("BoostAndLogTest", 10)
	var n_boost := auto_mgr.add_node(prog, "Action", "BoostJobPriority", 200, 80, {"job_type": "farmer", "delta_priority": 3})
	var n_log := auto_mgr.add_node(prog, "Action", "EmitLog", 380, 80, {"message": "Priority boosted"})
	auto_mgr.connect_nodes(prog, "n_start", "out", n_boost["id"], "in")
	auto_mgr.connect_nodes(prog, n_boost["id"], "out", n_log["id"], "in")

	var job_boost_state := {"called": false}
	var mock_job_mgr := {
		"boost_jobs_priority": func(jtype: String, delta: int) -> int:
			if jtype == "farmer" and delta == 3:
				job_boost_state["called"] = true
			return 2
	}
	var ctx := {"job_mgr": mock_job_mgr, "current_day": 1}

	var res := auto_mgr.run_program(prog.id, ctx, {"dry_run": false})
	_assert_true(res["ok"], "TC-AGRAPH.11.1", "Boost & Log execution succeeded")
	_assert_true(job_boost_state["called"], "TC-AGRAPH.11.2", "JobManager.boost_jobs_priority called with correct arguments")
	_assert_true(auto_mgr.execution_logs.any(func(l: String) -> bool: return l.contains("Priority boosted")), "TC-AGRAPH.11.3", "EmitLog recorded in execution_logs")

# -----------------------------------------------------------------------------
# TC-AGRAPH.12: Strict execution budget enforcement (MAX_STEPS_PER_RUN = 60)
# -----------------------------------------------------------------------------
func _test_tc_agraph_12_step_budget_exhaustion() -> void:
	var auto_mgr := AutomationManagerScript.new()
	var prog := auto_mgr.create_program("BudgetExhaustionTest", 10)
	# Chain of 65 Action nodes in series
	var prev_id: String = "n_start"
	for i in range(65):
		var n := auto_mgr.add_node(prog, "Action", "EmitLog", 50.0 + i * 20.0, 50.0, {"message": "Step %d" % i})
		auto_mgr.connect_nodes(prog, prev_id, "out", n["id"], "in")
		prev_id = n["id"]

	var ctx := {"current_day": 1}
	var res := auto_mgr.run_program(prog.id, ctx, {"dry_run": false})
	_assert_false(res["ok"], "TC-AGRAPH.12.1", "Execution halted when step budget exceeded")
	_assert_true(str(res["reason"]).contains("ngân sách"), "TC-AGRAPH.12.2", "Reason explains budget exhaustion")

# -----------------------------------------------------------------------------
# TC-AGRAPH.13: Dry Run simulation guarantee (100% side-effect-free immutability)
# -----------------------------------------------------------------------------
func _test_tc_agraph_13_dry_run_immutability() -> void:
	var auto_mgr := AutomationManagerScript.new()
	var prog := auto_mgr.create_program("DryRunImmutabilityTest", 10)
	var n_act := auto_mgr.add_node(prog, "Action", "AssignRole", 200, 80, {"from_role": "idle", "to_role": "woodcutter"})
	auto_mgr.connect_nodes(prog, "n_start", "out", n_act["id"], "in")

	var cit_dry := MockCitizen.new("cit_dry_1", "Dry Citizen", "idle")
	var ctx := {"citizens": [cit_dry], "current_day": 1}
	var logs_count_before: int = auto_mgr.execution_logs.size()

	# Run with dry_run = true
	var res := auto_mgr.run_program(prog.id, ctx, {"dry_run": true})
	_assert_true(res["ok"], "TC-AGRAPH.13.1", "Dry run returned ok: true")
	_assert_true(res["dry_run"], "TC-AGRAPH.13.2", "Dry run flag set in result")
	_assert_eq(cit_dry.role, "idle", "TC-AGRAPH.13.3", "Citizen role completely unmodified during dry run")
	_assert_eq(auto_mgr.execution_logs.size(), logs_count_before, "TC-AGRAPH.13.4", "Persistent execution_logs untouched")
	_assert_true(res["trace"].size() > 0, "TC-AGRAPH.13.5", "Simulation trace generated in returned result")

# -----------------------------------------------------------------------------
# TC-AGRAPH.14: Priority-ordered execution & pause respect
# -----------------------------------------------------------------------------
func _test_tc_agraph_14_priority_execution_order() -> void:
	var auto_mgr := AutomationManagerScript.new()
	var prog_low := auto_mgr.create_program("LowPrioProg", 5)
	var n_low := auto_mgr.add_node(prog_low, "Action", "AssignRole", 200, 80, {"from_role": "idle", "to_role": "woodcutter"})
	auto_mgr.connect_nodes(prog_low, "n_start", "out", n_low["id"], "in")
	prog_low.enabled = true

	var prog_high := auto_mgr.create_program("HighPrioProg", 25)
	var n_high := auto_mgr.add_node(prog_high, "Action", "AssignRole", 200, 80, {"from_role": "idle", "to_role": "miner"})
	auto_mgr.connect_nodes(prog_high, "n_start", "out", n_high["id"], "in")
	prog_high.enabled = true

	# Single idle citizen available
	var cit := MockCitizen.new("cit_contest", "Contested", "idle")
	var ctx := {"citizens": [cit], "is_paused": false, "current_day": 1}

	var res := auto_mgr.evaluate_all_graphs(ctx)
	_assert_true(res["executed_programs"].has(prog_high.id), "TC-AGRAPH.14.1", "High priority program executed")
	_assert_eq(cit.role, "miner", "TC-AGRAPH.14.2", "High priority program claimed citizen (assigned miner, not woodcutter)")

	# Test paused simulation
	var ctx_paused := {"citizens": [cit], "is_paused": true, "current_day": 1}
	var res_paused := auto_mgr.evaluate_all_graphs(ctx_paused)
	_assert_true(res_paused["executed_programs"].is_empty(), "TC-AGRAPH.14.3", "Paused simulation halts all graph execution")

# -----------------------------------------------------------------------------
# TC-AGRAPH.15: SaveManager persistence, fail-closed validation & legacy save compatibility
# -----------------------------------------------------------------------------
func _test_tc_agraph_15_persistence_and_legacy_compatibility() -> void:
	var auto_mgr := AutomationManagerScript.new()
	var prog := auto_mgr.create_program("PersistProg", 15)
	var n_act := auto_mgr.add_node(prog, "Action", "EmitLog", 200, 80, {"message": "Saved message"})
	auto_mgr.connect_nodes(prog, "n_start", "out", n_act["id"], "in")
	prog.enabled = true
	auto_mgr.log_trace(prog.id, "Log line 1", false, [])

	var serialized_auto := auto_mgr.serialize()
	_assert_eq(serialized_auto["programs"].size(), 1, "TC-AGRAPH.15.1", "Serialized 1 program")
	_assert_true(serialized_auto["execution_logs"].size() > 0, "TC-AGRAPH.15.2", "Serialized execution logs")

	# Validation of save data with valid automation section
	var dummy_save := {
		"schema_version": SaveManagerScript.SAVE_SCHEMA_VERSION,
		"metadata": {},
		"game_clock": {"current_day": 1},
		"resources": {"is_starving": false},
		"buildings": [],
		"citizens": [],
		"automation": serialized_auto
	}
	var val_ok := SaveManagerScript.validate_save_data(dummy_save)
	_assert_true(val_ok["valid"], "TC-AGRAPH.15.3", "SaveManager accepts valid automation section")

	# Validation of save data with MALFORMED automation section (invalid graph with cycle)
	var bad_prog_dict := {
		"id": "p_bad",
		"name": "Bad",
		"priority": 5,
		"nodes": [
			{"id": "n1", "type": "Trigger", "subtype": "OnTick"},
			{"id": "n2", "type": "Action", "subtype": "EmitLog"}
		],
		"edges": [
			{"from_node": "n1", "to_node": "n2"},
			{"from_node": "n2", "to_node": "n1"} # Cycle
		]
	}
	var malformed_save := {
		"schema_version": SaveManagerScript.SAVE_SCHEMA_VERSION,
		"metadata": {},
		"game_clock": {"current_day": 1},
		"resources": {"is_starving": false},
		"buildings": [],
		"citizens": [],
		"automation": {
			"programs": [bad_prog_dict],
			"execution_logs": []
		}
	}
	var val_fail := SaveManagerScript.validate_save_data(malformed_save)
	_assert_false(val_fail["valid"], "TC-AGRAPH.15.4", "SaveManager rejects malformed automation program fail-closed")

	# Legacy save WITHOUT automation section (backward compatibility without version bump)
	var legacy_save := {
		"schema_version": SaveManagerScript.SAVE_SCHEMA_VERSION,
		"metadata": {},
		"game_clock": {"current_day": 1},
		"resources": {"is_starving": false},
		"buildings": [],
		"citizens": []
	}
	var val_legacy := SaveManagerScript.validate_save_data(legacy_save)
	_assert_true(val_legacy["valid"], "TC-AGRAPH.15.5", "SaveManager accepts legacy save lacking automation field")

	# Deserialization roundtrip
	var restored_mgr := AutomationManagerScript.new()
	restored_mgr.deserialize(serialized_auto)
	_assert_eq(restored_mgr.programs.size(), 1, "TC-AGRAPH.15.6", "Restored program count matches")
	_assert_eq(restored_mgr.programs[0].name, "PersistProg", "TC-AGRAPH.15.7", "Restored program name matches")
	_assert_eq(restored_mgr.programs[0].priority, 15, "TC-AGRAPH.15.8", "Restored program priority matches")
	_assert_true(restored_mgr.programs[0].enabled, "TC-AGRAPH.15.9", "Restored program enabled flag matches")

# -----------------------------------------------------------------------------
# TC-AGRAPH.16: Non-regression of existing preset automation rules
# -----------------------------------------------------------------------------
func _test_tc_agraph_16_preset_rules_non_regression() -> void:
	var auto_mgr := AutomationManagerScript.new()
	var mock_rm = {
		"get_available_stock": func(r: String) -> int: return 20 if r == "food" else 100
	}
	var mock_jm := JobManager.new()
	# Add jobs to boost
	var j1 := mock_jm.create_job("farmer", Vector2i(10, 10))
	var j2 := mock_jm.create_job("hauler", Vector2i(10, 10))

	var wp_mgr := WorkplaceManager.new()

	var actions := auto_mgr.evaluate_rules(mock_rm, mock_jm, wp_mgr, "spring")
	_assert_true(actions.size() > 0, "TC-AGRAPH.16.1", "Preset Rule 1 (Food emergency) triggered")
	_assert_true(j1.priority > 1, "TC-AGRAPH.16.2", "Farmer job priority boosted by preset rule")
	_assert_true(j2.priority > 1, "TC-AGRAPH.16.3", "Hauler job priority boosted by preset rule")
