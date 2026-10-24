class_name AutomationManager
extends RefCounted
## Priority Automation System & Functional Automation Graph MVP for KINGDOMS UNBOUND.
## Conforms to HTML Stage 11 reference and Package 1V specification.
## Manages preset rule-based priority shifts and visual node graph programs.
## Enforces a strict execution budget to prevent infinite loops and performance death spirals.

const MAX_RULE_CHECKS_PER_TICK: int = 10
const MAX_STEPS_PER_RUN: int = 60
const MAX_LOGS: int = 60

# Preset rules configuration
var food_emergency_threshold: int = 30
var winter_prep_food_threshold: int = 80
var buffer_congestion_ratio: float = 0.8

var execution_budget_used: int = 0
var total_evaluations: int = 0

# Graph Programs and Diagnostic Logs
var programs: Array[AutomationProgram] = []
var execution_logs: Array[String] = []
var _next_program_counter: int = 1

# -----------------------------------------------------------------------------
# Program Lifecycle & Management
# -----------------------------------------------------------------------------

func create_program(name: String = "Chương trình Mới", priority: int = 5) -> AutomationProgram:
	var prog_id: String = "prog_%d" % _next_program_counter
	_next_program_counter += 1
	var prog := AutomationProgram.new(prog_id, name, priority)
	prog.nodes = [
		{
			"id": "n_start",
			"type": "Trigger",
			"subtype": "OnTick",
			"title": "⚡ Trigger",
			"x": 25.0,
			"y": 90.0,
			"params": {}
		}
	]
	prog.edges = []
	programs.append(prog)
	return prog

func duplicate_program(prog_id: String) -> AutomationProgram:
	var orig := get_program(prog_id)
	if orig == null:
		return null
	var data := orig.serialize()
	var new_prog := AutomationProgram.deserialize(data)
	new_prog.id = "prog_%d" % _next_program_counter
	_next_program_counter += 1
	new_prog.name = "%s (Bản sao)" % orig.name
	new_prog.enabled = false
	new_prog.last_run_time = -999.0
	programs.append(new_prog)
	return new_prog

func delete_program(prog_id: String) -> bool:
	for i in range(programs.size()):
		if programs[i].id == prog_id:
			programs.remove_at(i)
			return true
	return false

func get_program(prog_id: String) -> AutomationProgram:
	for p in programs:
		if p.id == prog_id:
			return p
	return null

func get_all_programs() -> Array[AutomationProgram]:
	return programs

func add_node(prog: AutomationProgram, type: String, subtype: String = "", x: float = 160.0, y: float = 90.0, params: Dictionary = {}) -> Dictionary:
	if prog == null:
		return {}
	var node_id: String = "node_%d" % (prog.nodes.size() + 1)
	var title: String = type
	match type:
		"Trigger":
			title = "⚡ Trigger"
		"Condition":
			title = "❓ Điều kiện (%s)" % (subtype if not subtype.is_empty() else "ResourceCompare")
		"LogicGate":
			title = "🔗 Cổng %s" % (subtype if not subtype.is_empty() else "AND")
		"IfElse":
			title = "🔀 IF / ELSE"
		"Action":
			title = "🎯 %s" % (subtype if not subtype.is_empty() else "Action")
		"End":
			title = "🛑 End"

	var node: Dictionary = {
		"id": node_id,
		"type": type,
		"subtype": subtype if not subtype.is_empty() else ("Default" if type == "Condition" else ("EmitLog" if type == "Action" else "")),
		"title": title,
		"x": x,
		"y": y,
		"params": params.duplicate(true)
	}
	prog.nodes.append(node)
	return node

func connect_nodes(prog: AutomationProgram, from_node: String, from_port: String, to_node: String, to_port: String) -> Dictionary:
	if prog == null:
		return {"ok": false, "reason": "Chương trình null"}
	if from_node == to_node:
		return {"ok": false, "reason": "Không thể tự nối Node vào chính nó"}

	var n_from: Dictionary = {}
	var n_to: Dictionary = {}
	for n in prog.nodes:
		if n.get("id") == from_node:
			n_from = n
		elif n.get("id") == to_node:
			n_to = n

	if n_from.is_empty() or n_to.is_empty():
		return {"ok": false, "reason": "Không tìm thấy Node nguồn hoặc đích"}

	var src_type: String = str(n_from.get("type", ""))
	var tgt_type: String = str(n_to.get("type", ""))

	# Port compatibility check
	var is_bool_out: bool = (src_type in ["Condition", "LogicGate"] and from_port == "bool")
	var is_flow_out: bool = (from_port in ["out", "true", "false"])

	if is_bool_out and not (to_port in ["cond", "inA", "inB", "in"]):
		return {"ok": false, "reason": "Sai kiểu cổng: Cổng boolean (%s) không nối được vào (%s)" % [from_port, to_port]}
	if is_flow_out and (to_port in ["inA", "inB", "cond"] or tgt_type == "LogicGate"):
		return {"ok": false, "reason": "Sai kiểu cổng: Cổng luồng (%s) không nối được vào cổng boolean (%s)" % [from_port, to_port]}

	# Remove duplicate edge if already present
	var filtered_edges: Array[Dictionary] = []
	for e in prog.edges:
		var fn = str(e.get("from_node", e.get("fromNode", "")))
		var fp = str(e.get("from_port", e.get("fromPort", "")))
		var tn = str(e.get("to_node", e.get("toNode", "")))
		var tp = str(e.get("to_port", e.get("toPort", "")))
		if not (fn == from_node and fp == from_port and tn == to_node and tp == to_port):
			filtered_edges.append(e)
	prog.edges = filtered_edges

	var edge_dict: Dictionary = {
		"id": "edge_%d" % (prog.edges.size() + 1),
		"from_node": from_node,
		"from_port": from_port,
		"to_node": to_node,
		"to_port": to_port
	}
	prog.edges.append(edge_dict)
	return {"ok": true, "edge": edge_dict}

func disconnect_nodes(prog: AutomationProgram, from_node: String, from_port: String, to_node: String, to_port: String) -> bool:
	if prog == null:
		return false
	var initial_size: int = prog.edges.size()
	var filtered: Array[Dictionary] = []
	for e in prog.edges:
		var fn = str(e.get("from_node", e.get("fromNode", "")))
		var fp = str(e.get("from_port", e.get("fromPort", "")))
		var tn = str(e.get("to_node", e.get("toNode", "")))
		var tp = str(e.get("to_port", e.get("toPort", "")))
		if not (fn == from_node and fp == from_port and tn == to_node and tp == to_port):
			filtered.append(e)
	prog.edges = filtered
	return prog.edges.size() < initial_size

func log_trace(prog_id: String, msg: String, is_dry_run: bool = false, target_trace: Array = [], current_day: int = 1) -> void:
	var entry: String = "[N%d|%s][%s] %s" % [current_day, "SIM" if is_dry_run else "EXEC", prog_id, msg]
	if target_trace != null:
		target_trace.append(entry)
	if not is_dry_run:
		execution_logs.push_front(entry)
		if execution_logs.size() > MAX_LOGS:
			execution_logs.pop_back()

# -----------------------------------------------------------------------------
# Graph Node Evaluation & Action Execution
# -----------------------------------------------------------------------------

func _get_resource_stock(resource_mgr: Variant, res_id: String, fallback_dict: Dictionary = {}) -> int:
	if resource_mgr != null:
		if resource_mgr is Object and resource_mgr.has_method("get_available_stock"):
			return int(resource_mgr.call("get_available_stock", res_id))
		elif resource_mgr is Dictionary:
			if resource_mgr.has("get_available_stock") and resource_mgr["get_available_stock"] is Callable:
				return int(resource_mgr["get_available_stock"].call(res_id))
			elif resource_mgr.has(res_id):
				return int(resource_mgr[res_id])
	if fallback_dict.has(res_id):
		return int(fallback_dict[res_id])
	return 0

func _get_resource_capacity(resource_mgr: Variant, res_id: String) -> int:
	if resource_mgr != null:
		if resource_mgr is Object and resource_mgr.has_method("get_capacity"):
			return int(resource_mgr.call("get_capacity", res_id))
		elif resource_mgr is Dictionary:
			if resource_mgr.has("get_capacity") and resource_mgr["get_capacity"] is Callable:
				return int(resource_mgr["get_capacity"].call(res_id))
			elif resource_mgr.has(res_id):
				return int(resource_mgr[res_id])
	return 500

func _get_resource_total_stock(resource_mgr: Variant, res_id: String) -> int:
	if resource_mgr != null:
		if resource_mgr is Object and resource_mgr.has_method("get_total_stock"):
			return int(resource_mgr.call("get_total_stock", res_id))
		elif resource_mgr is Dictionary:
			if resource_mgr.has("get_total_stock") and resource_mgr["get_total_stock"] is Callable:
				return int(resource_mgr["get_total_stock"].call(res_id))
			elif resource_mgr.has(res_id):
				return int(resource_mgr[res_id])
	return _get_resource_stock(resource_mgr, res_id)

func evaluate_condition_node(node: Dictionary, prog: AutomationProgram, context: Dictionary, memo_bool: Dictionary) -> bool:
	var node_id: String = str(node.get("id", ""))
	if memo_bool.has(node_id):
		return bool(memo_bool[node_id])

	var result: bool = false
	var ntype: String = str(node.get("type", ""))
	var subtype: String = str(node.get("subtype", ""))
	var params: Dictionary = node.get("params", {}) if (node.get("params") is Dictionary) else {}
	var resource_mgr = context.get("resource_mgr")

	if ntype == "Condition":
		if subtype.is_empty() or subtype == "Default":
			subtype = "ResourceCompare"

		if subtype == "ResourceCompare":
			var res_key: String = str(params.get("resource", "Food")).to_lower()
			if res_key in ["treasury", "gold"]:
				res_key = EconomyConfig.RES_GOLD
			var fallback: Dictionary = context.get("resources", {}) if (context.get("resources") is Dictionary) else {}
			var cur_val: float = float(_get_resource_stock(resource_mgr, res_key, fallback))
			var target_val: float = float(params.get("value", 60.0))
			var op: String = str(params.get("op", "<"))
			match op:
				"<":
					result = cur_val < target_val
				"<=":
					result = cur_val <= target_val
				">":
					result = cur_val > target_val
				">=":
					result = cur_val >= target_val
				"==":
					result = absf(cur_val - target_val) < 0.001
				_:
					result = cur_val < target_val

		elif subtype == "CitizenFatigue":
			var thresh: float = float(params.get("value", 80.0))
			var citizens: Array = context.get("citizens", [])
			for c in citizens:
				if c == null:
					continue
				var f_val = c.get("fatigue")
				var is_dead = c.get("is_dead")
				if is_dead is bool and is_dead:
					continue
				if f_val != null and float(f_val) > thresh:
					result = true
					break

		elif subtype == "StorageFull":
			if resource_mgr != null:
				for res_id in EconomyConfig.ALL_RESOURCES:
					var stock: int = _get_resource_total_stock(resource_mgr, res_id)
					var cap: int = _get_resource_capacity(resource_mgr, res_id)
					if cap > 0 and stock >= cap:
						result = true
						break

	elif ntype == "LogicGate":
		# Find incoming edges into this node
		var in_vals: Array[bool] = []
		for e in prog.edges:
			var tn = str(e.get("to_node", e.get("toNode", "")))
			if tn == node_id:
				var fn = str(e.get("from_node", e.get("fromNode", "")))
				for src_node in prog.nodes:
					if str(src_node.get("id")) == fn:
						in_vals.append(evaluate_condition_node(src_node, prog, context, memo_bool))
						break

		match subtype:
			"AND":
				result = not in_vals.is_empty() and in_vals.all(func(v: bool) -> bool: return v)
			"OR":
				result = in_vals.any(func(v: bool) -> bool: return v)
			"NOT":
				result = not in_vals[0] if not in_vals.is_empty() else false
			_:
				result = false

	memo_bool[node_id] = result
	return result

func execute_action_node(
	node: Dictionary,
	prog: AutomationProgram,
	context: Dictionary,
	is_dry_run: bool,
	trace: Array,
	action_locks: Dictionary
) -> Dictionary:
	var subtype: String = str(node.get("subtype", "EmitLog"))
	var params: Dictionary = node.get("params", {}) if (node.get("params") is Dictionary) else {}
	var cur_day: int = int(context.get("current_day", 1))

	if subtype == "AssignRole":
		var from_role: String = str(params.get("from_role", params.get("fromRole", "idle"))).to_lower()
		var to_role: String = str(params.get("to_role", params.get("toRole", "farmer"))).to_lower()
		var citizens: Array = context.get("citizens", [])

		var candidate: Object = null
		for c in citizens:
			if c == null:
				continue
			var is_dead = c.get("is_dead")
			if is_dead is bool and is_dead:
				continue
			var c_role = str(c.get("role")).to_lower()
			if c_role != from_role:
				continue
			var cid: String = str(c.get("id")) if c.get("id") != null else str(c.name)
			if action_locks.has("cit_%s" % cid):
				continue
			candidate = c
			break

		if candidate == null:
			var reason := "Không có công dân %s khả dụng để chuyển sang %s" % [from_role, to_role]
			log_trace(prog.id, reason, is_dry_run, trace, cur_day)
			return {"ok": false, "reason": reason}

		var cand_id: String = str(candidate.get("id")) if candidate.get("id") != null else str(candidate.name)
		var cand_name: String = str(candidate.get("citizen_name")) if candidate.get("citizen_name") != null else cand_id

		# Check Barracks requirement if to_role is guard
		if to_role == "guard":
			var world_data = context.get("world_data")
			if world_data != null and not BuildingSystem.is_barracks_active(world_data):
				var reason := "Cần Doanh Trại đang hoạt động để phân công lính gác"
				log_trace(prog.id, reason, is_dry_run, trace, cur_day)
				return {"ok": false, "reason": reason}

		action_locks["cit_%s" % cand_id] = true
		if not is_dry_run:
			var role_changed := true
			if candidate.has_method("set_role"):
				role_changed = bool(candidate.call("set_role", to_role))
			else:
				candidate.set("role", to_role)
			if not role_changed:
				var reason := "Từ chối chuyển vai trò sang %s cho công dân %s" % [to_role, cand_name]
				log_trace(prog.id, reason, is_dry_run, trace, cur_day)
				return {"ok": false, "reason": reason}

			var world_view = context.get("world_view")
			if world_view != null and world_view.has_method("_on_citizen_role_changed"):
				world_view.call("_on_citizen_role_changed", cand_id, to_role)

		var msg := "Action AssignRole: Chuyển %s (%s) từ %s → %s" % [cand_name, cand_id, from_role, to_role]
		log_trace(prog.id, msg, is_dry_run, trace, cur_day)
		return {"ok": true, "delta": msg}

	elif subtype == "BoostJobPriority":
		var job_type: String = str(params.get("job_type", "farmer")).to_lower()
		var delta_p: int = int(params.get("delta_priority", 1))
		var job_mgr = context.get("job_mgr")
		if job_mgr == null:
			var reason := "Bỏ qua BoostJobPriority: Thiếu JobManager trong ngữ cảnh"
			log_trace(prog.id, reason, is_dry_run, trace, cur_day)
			return {"ok": false, "reason": reason}

		var boosted: int = 0
		if not is_dry_run:
			if job_mgr is Object and job_mgr.has_method("boost_jobs_priority"):
				boosted = int(job_mgr.call("boost_jobs_priority", job_type, delta_p))
			elif job_mgr is Dictionary and job_mgr.has("boost_jobs_priority") and job_mgr["boost_jobs_priority"] is Callable:
				boosted = int(job_mgr["boost_jobs_priority"].call(job_type, delta_p))

		var msg := "Action BoostJobPriority: Tăng ưu tiên %s thêm %+d" % [job_type, delta_p]
		log_trace(prog.id, msg, is_dry_run, trace, cur_day)
		return {"ok": true, "delta": msg, "count": boosted}

	elif subtype == "EmitLog":
		var log_msg: String = str(params.get("message", "Log từ đồ thị"))
		log_trace(prog.id, "Action EmitLog: " + log_msg, is_dry_run, trace, cur_day)
		return {"ok": true, "delta": log_msg}

	var unknown_msg := "Action không xác định: %s" % subtype
	log_trace(prog.id, unknown_msg, is_dry_run, trace, cur_day)
	return {"ok": false, "reason": unknown_msg}

# -----------------------------------------------------------------------------
# Program Execution Engine (Supports Dry-Run Simulation)
# -----------------------------------------------------------------------------

func run_program(prog_id: String, context: Dictionary, options: Dictionary = {}) -> Dictionary:
	var prog := get_program(prog_id)
	if prog == null:
		return {"ok": false, "reason": "Không tìm thấy chương trình '%s'" % prog_id, "trace": []}

	var is_dry_run: bool = bool(options.get("dry_run", false))
	var cur_day: int = int(context.get("current_day", 1))
	var trace: Array = []

	var validation := AutomationGraphValidator.validate_program(prog)
	if not validation.get("valid", false):
		var err_str: String = "; ".join(validation.get("errors", ["Lỗi không xác định"]))
		log_trace(prog.id, "Từ chối chạy do lỗi đồ thị: %s" % err_str, is_dry_run, trace, cur_day)
		return {"ok": false, "reason": err_str, "errors": validation.get("errors", []), "trace": trace}

	var action_locks: Dictionary = options.get("shared_action_locks", {})
	var memo_bool: Dictionary = {}
	var steps: int = 0
	var actions_executed: Array[Dictionary] = []

	var queue: Array[Dictionary] = []
	for n in prog.nodes:
		if str(n.get("type", "")) == "Trigger":
			queue.append(n)

	while not queue.is_empty():
		steps += 1
		if steps > MAX_STEPS_PER_RUN:
			var budget_msg := "Dừng khẩn cấp: Vượt ngân sách thực thi (%d bước/tick)" % MAX_STEPS_PER_RUN
			log_trace(prog.id, budget_msg, is_dry_run, trace, cur_day)
			return {"ok": false, "reason": budget_msg, "trace": trace, "actions_executed": actions_executed}

		var cur: Dictionary = queue.pop_front()
		var cid: String = str(cur.get("id", ""))
		var ctype: String = str(cur.get("type", ""))
		var ctitle: String = str(cur.get("title", ctype))

		match ctype:
			"Trigger":
				log_trace(prog.id, "Trigger kích hoạt: %s" % ctitle, is_dry_run, trace, cur_day)
				for e in prog.edges:
					var fn = str(e.get("from_node", e.get("fromNode", "")))
					if fn == cid:
						var tn = str(e.get("to_node", e.get("toNode", "")))
						for n in prog.nodes:
							if str(n.get("id")) == tn:
								queue.append(n)
								break

			"Condition", "LogicGate":
				var val := evaluate_condition_node(cur, prog, context, memo_bool)
				log_trace(prog.id, "Đánh giá %s = %s" % [ctitle, "TRUE" if val else "FALSE"], is_dry_run, trace, cur_day)
				for e in prog.edges:
					var fn = str(e.get("from_node", e.get("fromNode", "")))
					if fn == cid:
						var tn = str(e.get("to_node", e.get("toNode", "")))
						for n in prog.nodes:
							if str(n.get("id")) == tn:
								var nt: String = str(n.get("type", ""))
								if nt in ["IfElse", "LogicGate"]:
									queue.append(n)
								elif val:
									queue.append(n)
								break

			"IfElse":
				# Find condition input edge
				var cond_node: Dictionary = {}
				for e in prog.edges:
					var tn = str(e.get("to_node", e.get("toNode", "")))
					var tp = str(e.get("to_port", e.get("toPort", "")))
					if tn == cid and tp == "cond":
						var fn = str(e.get("from_node", e.get("fromNode", "")))
						for n in prog.nodes:
							if str(n.get("id")) == fn:
								cond_node = n
								break
						if not cond_node.is_empty():
							break

				if cond_node.is_empty():
					for e in prog.edges:
						var tn = str(e.get("to_node", e.get("toNode", "")))
						if tn == cid:
							var fn = str(e.get("from_node", e.get("fromNode", "")))
							for n in prog.nodes:
								if str(n.get("id")) == fn and str(n.get("type")) in ["Condition", "LogicGate"]:
									cond_node = n
									break
							if not cond_node.is_empty():
								break

				var cond_val: bool = false
				if not cond_node.is_empty():
					cond_val = evaluate_condition_node(cond_node, prog, context, memo_bool)

				var branch_port: String = "true" if cond_val else "false"
				log_trace(prog.id, "Nhánh IF/ELSE chọn cổng [%s]" % branch_port.to_upper(), is_dry_run, trace, cur_day)

				for e in prog.edges:
					var fn = str(e.get("from_node", e.get("fromNode", "")))
					var fp = str(e.get("from_port", e.get("fromPort", "")))
					if fn == cid and fp == branch_port:
						var tn = str(e.get("to_node", e.get("toNode", "")))
						for n in prog.nodes:
							if str(n.get("id")) == tn:
								queue.append(n)
								break

			"Action":
				var act_res := execute_action_node(cur, prog, context, is_dry_run, trace, action_locks)
				actions_executed.append({
					"node_id": cid,
					"subtype": cur.get("subtype", ""),
					"ok": act_res.get("ok", false),
					"detail": act_res.get("delta", act_res.get("reason", ""))
				})
				for e in prog.edges:
					var fn = str(e.get("from_node", e.get("fromNode", "")))
					if fn == cid:
						var tn = str(e.get("to_node", e.get("toNode", "")))
						for n in prog.nodes:
							if str(n.get("id")) == tn:
								queue.append(n)
								break

			"End":
				log_trace(prog.id, "Kết thúc luồng tại Node End (%s)" % cid, is_dry_run, trace, cur_day)

	return {
		"ok": true,
		"dry_run": is_dry_run,
		"steps": steps,
		"actions_executed": actions_executed,
		"trace": trace
	}

func evaluate_all_graphs(context: Dictionary, _dt: float = 0.0) -> Dictionary:
	if bool(context.get("is_paused", false)):
		return {"executed_programs": []}

	var enabled_progs: Array[AutomationProgram] = []
	for p in programs:
		if p.enabled:
			enabled_progs.append(p)

	# Sort by priority descending, then by id ascending
	enabled_progs.sort_custom(func(a: AutomationProgram, b: AutomationProgram) -> bool:
		if a.priority != b.priority:
			return a.priority > b.priority
		return a.id < b.id
	)

	var shared_action_locks: Dictionary = {}
	var executed_programs: Array[String] = []

	for prog in enabled_progs:
		var res := run_program(prog.id, context, {
			"dry_run": false,
			"shared_action_locks": shared_action_locks
		})
		if res.get("ok", false):
			var acts: Array = res.get("actions_executed", [])
			if not acts.is_empty():
				executed_programs.append(prog.id)

	return {"executed_programs": executed_programs}

# -----------------------------------------------------------------------------
# Preset Rules Evaluation (Preserved for backward compatibility)
# -----------------------------------------------------------------------------

func evaluate_rules(
	resource_mgr: Variant,
	job_mgr: JobManager,
	workplace_mgr: WorkplaceManager,
	current_season: String = "spring",
	citizens: Array = [],
	world_data = null,
	is_paused: bool = false
) -> Array[String]:
	var actions_taken: Array[String] = []
	execution_budget_used = 0
	total_evaluations += 1

	if resource_mgr != null and job_mgr != null:
		# --- Rule 1: Food Emergency Priority Boost ---
		if execution_budget_used < MAX_RULE_CHECKS_PER_TICK:
			execution_budget_used += 1
			var food_avail: int = _get_resource_stock(resource_mgr, EconomyConfig.RES_FOOD)
			if food_avail < food_emergency_threshold:
				var farm_boosted := job_mgr.boost_jobs_priority("farmer", 2)
				var haul_boosted := job_mgr.boost_jobs_priority("hauler", 3)
				if farm_boosted > 0 or haul_boosted > 0:
					actions_taken.append(
						"Cảnh báo lương thực thấp (%d < %d): Tăng độ ưu tiên cho %d việc nông dân và %d việc vận chuyển" % [
							food_avail, food_emergency_threshold, farm_boosted, haul_boosted
						]
					)

		# --- Rule 2: Workplace Buffer Congestion Protection ---
		if workplace_mgr != null and execution_budget_used < MAX_RULE_CHECKS_PER_TICK:
			for wp in workplace_mgr.get_all_workplaces():
				if execution_budget_used >= MAX_RULE_CHECKS_PER_TICK:
					break
				execution_budget_used += 1

				if wp.buffer_capacity > 0:
					var fill_ratio: float = float(wp.buffer_amount) / float(wp.buffer_capacity)
					if fill_ratio >= buffer_congestion_ratio:
						for job in job_mgr.get_all_jobs():
							if job.type == "hauler" and job.source_workplace_id == wp.id:
								job.priority += 2
								actions_taken.append(
									"Kho tạm %s đầy (%.0f%%): Tăng ưu tiên vận chuyển hàng về kho trung tâm" % [
										wp.id, fill_ratio * 100.0
									]
								)
								break

		# --- Rule 3: Autumn Winter Preparation ---
		if execution_budget_used < MAX_RULE_CHECKS_PER_TICK:
			execution_budget_used += 1
			if current_season == "autumn":
				var food_avail: int = _get_resource_stock(resource_mgr, EconomyConfig.RES_FOOD)
				if food_avail < winter_prep_food_threshold:
					var boosted := job_mgr.boost_jobs_priority("farmer", 1)
					if boosted > 0:
						actions_taken.append(
							"Mùa Thu chuẩn bị Mùa Đông: Tăng sản xuất lương thực dự trữ (kho hiện tại: %d)" % food_avail
						)

	# --- Evaluate Enabled Graph Programs ---
	var graph_context: Dictionary = {
		"resource_mgr": resource_mgr,
		"job_mgr": job_mgr,
		"workplace_mgr": workplace_mgr,
		"citizens": citizens,
		"world_data": world_data,
		"is_paused": is_paused,
		"current_day": 1
	}
	var graph_res := evaluate_all_graphs(graph_context)
	var exec_progs: Array = graph_res.get("executed_programs", [])
	for pid in exec_progs:
		actions_taken.append("Thực thi đồ thị tự động hóa: %s" % pid)

	return actions_taken

# -----------------------------------------------------------------------------
# Persistence Integration
# -----------------------------------------------------------------------------

func serialize() -> Dictionary:
	var serialized_progs: Array = []
	for p in programs:
		serialized_progs.append(p.serialize())
	return {
		"programs": serialized_progs,
		"execution_logs": execution_logs.duplicate()
	}

func deserialize(data: Dictionary) -> void:
	programs.clear()
	execution_logs.clear()

	var raw_progs = data.get("programs", [])
	if raw_progs is Array:
		for p_data in raw_progs:
			if p_data is Dictionary:
				var prog := AutomationProgram.deserialize(p_data)
				programs.append(prog)
				# Update counter to avoid colliding IDs
				var pid_str := prog.id
				if pid_str.begins_with("prog_"):
					var num_part := pid_str.trim_prefix("prog_").to_int()
					if num_part >= _next_program_counter:
						_next_program_counter = num_part + 1

	var raw_logs = data.get("execution_logs", [])
	if raw_logs is Array:
		for l in raw_logs:
			execution_logs.append(str(l))
