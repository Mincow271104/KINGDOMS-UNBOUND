class_name AutomationGraphValidator
extends RefCounted
## Strict fail-closed validator for Automation Graph Programs in KINGDOMS UNBOUND.
## Conforms to HTML Stage 11 reference and Package 1V specification.

const MAX_STEPS_PER_RUN: int = 60

const VALID_NODE_TYPES: Array[String] = [
	"Trigger",
	"Condition",
	"LogicGate",
	"IfElse",
	"Action",
	"End",
	"Delay",
	"Repeat"
]

const VALID_ACTION_SUBTYPES: Array[String] = [
	"AssignRole",
	"BoostJobPriority",
	"EmitLog"
]

const VALID_CONDITION_SUBTYPES: Array[String] = [
	"ResourceCompare",
	"StorageFull",
	"CitizenFatigue"
]

const VALID_LOGIC_SUBTYPES: Array[String] = [
	"AND",
	"OR",
	"NOT"
]

const VALID_ROLES: Array[String] = [
	"idle",
	"farmer",
	"woodcutter",
	"builder",
	"hauler",
	"miner",
	"smith",
	"guard"
]

const VALID_COMPARE_OPS: Array[String] = [
	"<",
	"<=",
	">",
	">=",
	"=="
]

static func validate_program(prog: Variant) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	if prog == null:
		return {"valid": false, "errors": ["Chương trình không tồn tại (null)"], "warnings": warnings}

	var p_id: String = ""
	var p_name: String = ""
	var p_enabled: bool = false
	var p_prio: int = 5
	var raw_nodes: Variant = null
	var raw_edges: Variant = null

	if prog is AutomationProgram:
		p_id = prog.id
		p_name = prog.name
		p_enabled = prog.enabled
		p_prio = prog.priority
		raw_nodes = prog.nodes
		raw_edges = prog.edges
	elif prog is Dictionary:
		p_id = str(prog.get("id", ""))
		p_name = str(prog.get("name", ""))
		p_enabled = bool(prog.get("enabled", false))
		var raw_prio = prog.get("priority", 5)
		if not (raw_prio is int or (raw_prio is float and not is_nan(raw_prio) and not is_inf(raw_prio) and floor(raw_prio) == raw_prio)):
			errors.push_back("priority của chương trình phải là số nguyên hợp lệ")
		else:
			p_prio = int(raw_prio)
		raw_nodes = prog.get("nodes", null)
		raw_edges = prog.get("edges", null)
	else:
		return {"valid": false, "errors": ["Định dạng chương trình không hợp lệ (cần AutomationProgram hoặc Dictionary)"], "warnings": warnings}

	if p_id.strip_edges().is_empty():
		errors.push_back("ID chương trình không được rỗng")

	if not (raw_nodes is Array) or raw_nodes.is_empty():
		return {"valid": false, "errors": ["Đồ thị trống (Không có Node nào)"], "warnings": warnings}

	if not (raw_edges is Array):
		return {"valid": false, "errors": ["Danh sách liên kết (edges) phải là danh sách hợp lệ"], "warnings": warnings}

	var node_ids: Dictionary = {} # id -> node Dictionary
	var triggers: Array[Dictionary] = []

	for i in range(raw_nodes.size()):
		var n = raw_nodes[i]
		if not (n is Dictionary):
			errors.push_back("Node tại vị trí %d không phải Dictionary" % i)
			continue
		var nid: String = str(n.get("id", "")).strip_edges()
		if nid.is_empty():
			errors.push_back("Node tại vị trí %d thiếu ID hợp lệ" % i)
			continue
		if node_ids.has(nid):
			errors.push_back("Trùng lặp ID node: '%s'" % nid)
			continue
		node_ids[nid] = n

		var ntype: String = str(n.get("type", ""))
		if not VALID_NODE_TYPES.has(ntype):
			errors.push_back("Loại node không hợp lệ: '%s' tại node '%s'" % [ntype, nid])
			continue

		if ntype == "Trigger":
			triggers.append(n)

		# Validate node coordinates
		for coord_key in ["x", "y"]:
			if n.has(coord_key):
				var c_val = n[coord_key]
				if not (c_val is int or c_val is float) or is_nan(float(c_val)) or is_inf(float(c_val)):
					errors.push_back("Tọa độ '%s' của node '%s' không phải số hữu hạn hợp lệ" % [coord_key, nid])

		# Validate params per node type
		var params: Dictionary = n.get("params", {}) if (n.get("params") is Dictionary) else {}
		var subtype: String = str(n.get("subtype", ""))

		match ntype:
			"Condition":
				if subtype.is_empty():
					subtype = "ResourceCompare"
				if not VALID_CONDITION_SUBTYPES.has(subtype):
					errors.push_back("Phân loại Condition không hợp lệ: '%s' tại node '%s'" % [subtype, nid])
				elif subtype == "ResourceCompare":
					var res_key: String = str(params.get("resource", "Food")).to_lower()
					if res_key == "treasury":
						res_key = EconomyConfig.RES_GOLD
					if not EconomyConfig.ALL_RESOURCES.has(res_key):
						errors.push_back("Tài nguyên kiểm tra không hợp lệ: '%s' tại node '%s'" % [str(params.get("resource", "")), nid])
					var op: String = str(params.get("op", "<"))
					if not VALID_COMPARE_OPS.has(op):
						errors.push_back("Toán tử so sánh không hợp lệ: '%s' tại node '%s'" % [op, nid])
					var val = params.get("value", 0)
					if not (val is int or val is float) or is_nan(float(val)) or is_inf(float(val)):
						errors.push_back("Giá trị ngưỡng so sánh phải là số hữu hạn tại node '%s'" % nid)
				elif subtype == "CitizenFatigue":
					var f_val = params.get("value", 80)
					if not (f_val is int or f_val is float) or is_nan(float(f_val)) or is_inf(float(f_val)):
						errors.push_back("Ngưỡng mệt mỏi phải là số hữu hạn tại node '%s'" % nid)

			"LogicGate":
				if not VALID_LOGIC_SUBTYPES.has(subtype):
					errors.push_back("Phân loại LogicGate không hợp lệ: '%s' tại node '%s'" % [subtype, nid])

			"Action":
				if subtype.is_empty():
					subtype = "EmitLog"
				if not VALID_ACTION_SUBTYPES.has(subtype):
					errors.push_back("Phân loại Action không hợp lệ: '%s' tại node '%s'" % [subtype, nid])
				elif subtype == "AssignRole":
					var from_r: String = str(params.get("from_role", params.get("fromRole", "idle"))).to_lower()
					var to_r: String = str(params.get("to_role", params.get("toRole", "farmer"))).to_lower()
					if not VALID_ROLES.has(from_r):
						errors.push_back("from_role không hợp lệ: '%s' tại node '%s'" % [from_r, nid])
					if not VALID_ROLES.has(to_r):
						errors.push_back("to_role không hợp lệ: '%s' tại node '%s'" % [to_r, nid])
					if from_r == to_r and not from_r.is_empty():
						warnings.push_back("from_role và to_role giống nhau ('%s') tại node '%s'" % [from_r, nid])
				elif subtype == "BoostJobPriority":
					var job_t: String = str(params.get("job_type", "farmer")).to_lower()
					if not VALID_ROLES.has(job_t) or job_t == "idle":
						errors.push_back("job_type cần boost không hợp lệ: '%s' tại node '%s'" % [job_t, nid])
					var delta_p = params.get("delta_priority", 1)
					if not (delta_p is int or delta_p is float) or is_nan(float(delta_p)) or is_inf(float(delta_p)) or int(delta_p) == 0:
						errors.push_back("delta_priority phải là số nguyên khác 0 tại node '%s'" % nid)

			"Delay":
				var d_val = params.get("duration_hours", params.get("duration", params.get("durationHours", null)))
				if d_val == null:
					errors.push_back("Node Delay '%s' thiếu tham số 'duration_hours'" % nid)
				elif not (d_val is int or (d_val is float and not is_nan(float(d_val)) and not is_inf(float(d_val)) and floor(float(d_val)) == float(d_val))):
					errors.push_back("duration_hours của node Delay '%s' phải là số nguyên hợp lệ" % nid)
				else:
					var d_int: int = int(d_val)
					if d_int < 1 or d_int > 720:
						errors.push_back("duration_hours của node Delay '%s' (%d) phải nằm trong khoảng 1–720 giờ" % [nid, d_int])

			"Repeat":
				var c_val = params.get("count", params.get("iterations", params.get("repeat_count", null)))
				if c_val == null:
					errors.push_back("Node Repeat '%s' thiếu tham số 'count'" % nid)
				elif not (c_val is int or (c_val is float and not is_nan(float(c_val)) and not is_inf(float(c_val)) and floor(float(c_val)) == float(c_val))):
					errors.push_back("count của node Repeat '%s' phải là số nguyên hợp lệ" % nid)
				else:
					var c_int: int = int(c_val)
					if c_int < 1 or c_int > 20:
						errors.push_back("count của node Repeat '%s' (%d) phải nằm trong khoảng 1–20 lần" % [nid, c_int])

	if triggers.is_empty():
		errors.push_back("Thiếu Node khởi đầu (Trigger)")

	# Validate edges
	var valid_edges: Array[Dictionary] = []
	for i in range(raw_edges.size()):
		var e = raw_edges[i]
		if not (e is Dictionary):
			errors.push_back("Edge tại vị trí %d không phải Dictionary" % i)
			continue
		var fn: String = str(e.get("from_node", e.get("fromNode", "")))
		var fp: String = str(e.get("from_port", e.get("fromPort", "")))
		var tn: String = str(e.get("to_node", e.get("toNode", "")))
		var tp: String = str(e.get("to_port", e.get("toPort", "")))

		if not node_ids.has(fn):
			errors.push_back("Edge trỏ từ node không tồn tại: '%s'" % fn)
			continue
		if not node_ids.has(tn):
			errors.push_back("Edge trỏ tới node không tồn tại: '%s'" % tn)
			continue
		if fn == tn:
			errors.push_back("Không được tự nối node '%s' vào chính nó" % fn)
			continue

		var src_type: String = str(node_ids[fn].get("type", ""))
		var tgt_type: String = str(node_ids[tn].get("type", ""))

		# Port compatibility checks
		var is_bool_out: bool = (src_type in ["Condition", "LogicGate"] and fp == "bool")
		var is_flow_out: bool = (fp in ["out", "true", "false", "body", "completed"])

		if is_bool_out:
			if tgt_type in ["Action", "End", "Delay", "Repeat", "Trigger"] or (tgt_type == "IfElse" and tp != "cond"):
				errors.push_back("Sai kiểu cổng: Cổng boolean (%s:%s) không nối được vào cổng luồng (%s:%s)" % [fn, fp, tn, tp])
				continue
			if not (tp in ["cond", "inA", "inB", "in"]):
				errors.push_back("Sai kiểu cổng: Cổng boolean (%s:%s) không nối được vào (%s:%s)" % [fn, fp, tn, tp])
				continue
		if is_flow_out and (tp in ["inA", "inB", "cond"] or tgt_type == "LogicGate"):
			errors.push_back("Sai kiểu cổng: Cổng luồng (%s:%s) không nối được vào cổng boolean (%s:%s)" % [fn, fp, tn, tp])
			continue

		valid_edges.append({
			"from_node": fn,
			"from_port": fp,
			"to_node": tn,
			"to_port": tp
		})

	# Reachability from Triggers via BFS + backward data dependencies
	var reachable: Dictionary = {}
	var queue: Array[String] = []
	for t in triggers:
		var tid: String = str(t.get("id"))
		queue.append(tid)

	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if reachable.has(cur):
			continue
		reachable[cur] = true
		for ed in valid_edges:
			if ed["from_node"] == cur:
				if not reachable.has(ed["to_node"]):
					queue.append(ed["to_node"])

	var changed: bool = true
	while changed:
		changed = false
		for ed in valid_edges:
			if reachable.has(ed["to_node"]):
				var src_id: String = ed["from_node"]
				if not reachable.has(src_id):
					reachable[src_id] = true
					changed = true

	for nid in node_ids:
		if not reachable.has(nid):
			var n_title: String = str(node_ids[nid].get("title", node_ids[nid].get("type", "")))
			errors.push_back("Node rời (Orphan/Unreachable): '%s' (%s)" % [n_title, nid])

		# Specific structural constraints
		var ntype: String = str(node_ids[nid].get("type", ""))
		if ntype == "IfElse":
			var has_cond: bool = false
			var has_true: bool = false
			var has_false: bool = false
			for ed in valid_edges:
				if ed["to_node"] == nid and ed["to_port"] == "cond":
					has_cond = true
				if ed["from_node"] == nid and ed["from_port"] == "true":
					has_true = true
				if ed["from_node"] == nid and ed["from_port"] == "false":
					has_false = true
			if not has_cond:
				errors.push_back("Node IF/ELSE (%s) thiếu đầu vào điều kiện" % nid)
			if not has_true and not has_false:
				errors.push_back("Node IF/ELSE (%s) chưa nối nhánh đầu ra True hoặc False" % nid)
		elif ntype == "Repeat":
			var has_body: bool = false
			for ed in valid_edges:
				if ed["from_node"] == nid and ed["from_port"] in ["body", "out"]:
					has_body = true
					break
			if not has_body:
				errors.push_back("Node Repeat (%s) chưa nối nhánh lặp 'body'" % nid)
		elif ntype == "Delay":
			var has_out: bool = false
			for ed in valid_edges:
				if ed["from_node"] == nid and ed["from_port"] == "out":
					has_out = true
					break
			if not has_out:
				errors.push_back("Node Delay (%s) chưa nối nhánh tiếp tục 'out'" % nid)

	# Cycle detection (Iterative DFS with visiting stack)
	var visiting: Dictionary = {}
	var visited: Dictionary = {}
	var has_cycle: bool = false

	for t in triggers:
		var start_id: String = str(t.get("id"))
		if visited.has(start_id):
			continue
		var stack: Array = [[start_id, 0]]
		visiting[start_id] = true
		while not stack.is_empty():
			var top: Array = stack.back()
			var cur_node: String = top[0]
			var edge_idx: int = top[1]

			var out_edges: Array[String] = []
			for ed in valid_edges:
				if ed["from_node"] == cur_node:
					out_edges.append(ed["to_node"])

			if edge_idx < out_edges.size():
				top[1] = edge_idx + 1
				var next_id: String = out_edges[edge_idx]
				if visiting.has(next_id):
					has_cycle = true
					break
				elif not visited.has(next_id):
					visiting[next_id] = true
					stack.append([next_id, 0])
			else:
				visiting.erase(cur_node)
				visited[cur_node] = true
				stack.pop_back()
		if has_cycle:
			break

	if has_cycle:
		errors.push_back("Phát hiện chu trình lặp không an toàn (Cycle/Infinite loop risk)")

	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings
	}
