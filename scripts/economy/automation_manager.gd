class_name AutomationManager
extends RefCounted
## Priority Automation System & Functional Automation Graph MVP for KINGDOMS UNBOUND.
## Conforms to HTML Stage 11 reference and Package 1V specification.
## Manages preset rule-based priority shifts and visual node graph programs.
## Enforces a strict execution budget to prevent infinite loops and performance death spirals.

const MAX_RULE_CHECKS_PER_TICK: int = 10
const MAX_STEPS_PER_RUN: int = 60
const MAX_LOGS: int = 60
const MAX_GLOBAL_PENDING_CONTINUATIONS: int = 50
const MAX_PROGRAM_PENDING_CONTINUATIONS: int = 10

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

# Pending Delayed Continuations (Package 1Y)
var pending_continuations: Array[Dictionary] = []
var _next_continuation_counter: int = 1

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
	clear_pending_continuations_for_program(prog_id)
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

func get_execution_logs() -> Array[String]:
	return execution_logs.duplicate()

func clear_execution_logs() -> void:
	execution_logs.clear()

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
		"Delay":
			title = "⏳ Trì hoãn"
		"Repeat":
			title = "🔁 Lặp lại"

	var final_params := params.duplicate(true)
	if final_params.is_empty():
		if type == "Delay":
			final_params["duration_hours"] = 1
		elif type == "Repeat":
			final_params["count"] = 3

	var node: Dictionary = {
		"id": node_id,
		"type": type,
		"subtype": subtype if not subtype.is_empty() else ("Default" if type in ["Condition", "Delay", "Repeat"] else ("EmitLog" if type == "Action" else "")),
		"title": title,
		"x": x,
		"y": y,
		"params": final_params
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
	var is_flow_out: bool = (from_port in ["out", "true", "false", "body", "completed"])

	if is_bool_out:
		if tgt_type in ["Action", "End", "Delay", "Repeat", "Trigger"] or (tgt_type == "IfElse" and to_port != "cond"):
			return {"ok": false, "reason": "Sai kiểu cổng: Cổng boolean (%s) không nối được vào cổng luồng (%s)" % [from_port, to_port]}
		if not (to_port in ["cond", "inA", "inB", "in"]):
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
# Delayed Continuation Queue Management & Data Validation (Package 1Y)
# -----------------------------------------------------------------------------

static func validate_automation_data(auto_dict: Variant) -> Dictionary:
	if not (auto_dict is Dictionary):
		return {"valid": false, "error": "Mục 'automation' phải là từ điển (Dictionary)."}

	var progs_val = auto_dict.get("programs", null)
	if progs_val != null:
		if not (progs_val is Array):
			return {"valid": false, "error": "Mục 'programs' trong automation phải là danh sách (Array)."}
		var seen_pids: Dictionary = {}
		for p_entry in progs_val:
			if not (p_entry is Dictionary):
				return {"valid": false, "error": "Bản ghi chương trình automation không đúng định dạng Dictionary."}
			var pid = str(p_entry.get("id", "")).strip_edges()
			if pid.is_empty():
				return {"valid": false, "error": "Chương trình automation thiếu ID hợp lệ."}
			if seen_pids.has(pid):
				return {"valid": false, "error": "Trùng lặp ID chương trình automation: '%s'." % pid}
			seen_pids[pid] = true

			var val_prog := AutomationGraphValidator.validate_program(p_entry)
			if not val_prog.get("valid", false):
				var err_list: Array = val_prog.get("errors", ["Lỗi đồ thị không xác định"])
				return {"valid": false, "error": "Chương trình automation '%s' không hợp lệ: %s." % [pid, "; ".join(err_list)]}

	if auto_dict.has("execution_logs"):
		var logs_val = auto_dict.get("execution_logs")
		if not (logs_val is Array):
			return {"valid": false, "error": "Mục 'execution_logs' trong automation phải là danh sách (Array)."}

	if auto_dict.has("pending_continuations"):
		var val_conts = validate_pending_continuations(auto_dict.get("pending_continuations"), auto_dict.get("programs", []))
		if not val_conts.get("valid", false):
			return val_conts

	return {"valid": true}

static func find_enclosing_repeat_node(prog_data: Variant, target_delay_id: String) -> String:
	if target_delay_id.is_empty():
		return ""

	var raw_nodes = []
	var raw_edges = []
	if prog_data is Dictionary:
		raw_nodes = prog_data.get("nodes", [])
		raw_edges = prog_data.get("edges", [])
	elif prog_data is AutomationProgram:
		raw_nodes = prog_data.nodes
		raw_edges = prog_data.edges
	else:
		return ""

	if not (raw_nodes is Array) or not (raw_edges is Array):
		return ""

	var repeat_node_ids: Array[String] = []
	for nd in raw_nodes:
		if nd is Dictionary and str(nd.get("type", "")) == "Repeat":
			var r_id = str(nd.get("id", "")).strip_edges()
			if not r_id.is_empty():
				repeat_node_ids.append(r_id)

	for rep_id in repeat_node_ids:
		var body_start_nodes: Array[String] = []
		for e in raw_edges:
			if not (e is Dictionary):
				continue
			var fn = str(e.get("from_node", e.get("fromNode", ""))).strip_edges()
			var fp = str(e.get("from_port", e.get("fromPort", ""))).strip_edges()
			var tn = str(e.get("to_node", e.get("toNode", ""))).strip_edges()
			if fn == rep_id and (fp in ["body", "out"] or fp.is_empty()):
				if not tn.is_empty():
					body_start_nodes.append(tn)

		var visited: Dictionary = {rep_id: true}
		var queue: Array[String] = body_start_nodes.duplicate()
		while not queue.is_empty():
			var curr = queue.pop_front()
			if visited.has(curr):
				continue
			visited[curr] = true
			if curr == target_delay_id:
				return rep_id

			for e in raw_edges:
				if not (e is Dictionary):
					continue
				var fn = str(e.get("from_node", e.get("fromNode", ""))).strip_edges()
				var fp = str(e.get("from_port", e.get("fromPort", ""))).strip_edges()
				var tn = str(e.get("to_node", e.get("toNode", ""))).strip_edges()
				if fn == curr and not tn.is_empty():
					if fp in ["out", "true", "false", "body", ""]:
						queue.append(tn)

	return ""

static func validate_pending_continuations(conts_val: Variant, programs_val: Variant) -> Dictionary:
	if not (conts_val is Array):
		return {"valid": false, "error": "Mục 'pending_continuations' phải là danh sách (Array)."}

	if conts_val.size() > MAX_GLOBAL_PENDING_CONTINUATIONS:
		return {"valid": false, "error": "Số lượng pending_continuations (%d) vượt quá giới hạn tối đa toàn cục (%d)." % [conts_val.size(), MAX_GLOBAL_PENDING_CONTINUATIONS]}

	var prog_map: Dictionary = {}
	if programs_val is Array:
		for p in programs_val:
			if p is Dictionary and p.has("id"):
				var pid = str(p["id"]).strip_edges()
				var node_dict: Dictionary = {}
				var raw_nodes = p.get("nodes", [])
				if raw_nodes is Array:
					for nd in raw_nodes:
						if nd is Dictionary and nd.has("id"):
							node_dict[str(nd["id"]).strip_edges()] = nd
				var raw_edges = p.get("edges", [])
				prog_map[pid] = {
					"nodes": node_dict,
					"edges": raw_edges if (raw_edges is Array) else [],
					"program": p
				}
			elif p is AutomationProgram:
				var pid = p.id.strip_edges()
				var node_dict: Dictionary = {}
				for nd in p.nodes:
					if nd is Dictionary and nd.has("id"):
						node_dict[str(nd["id"]).strip_edges()] = nd
				prog_map[pid] = {
					"nodes": node_dict,
					"edges": p.edges,
					"program": p
				}

	var seen_cids: Dictionary = {}
	var prog_counts: Dictionary = {}

	for c_entry in conts_val:
		if not (c_entry is Dictionary):
			return {"valid": false, "error": "Bản ghi pending_continuation không đúng định dạng Dictionary."}

		if not c_entry.has("id"):
			return {"valid": false, "error": "pending_continuation thiếu trường 'id'."}
		var cid = str(c_entry.get("id", "")).strip_edges()
		if cid.is_empty():
			return {"valid": false, "error": "pending_continuation có ID rỗng."}
		if seen_cids.has(cid):
			return {"valid": false, "error": "Trùng lặp ID pending_continuation: '%s'." % cid}
		seen_cids[cid] = true

		if not c_entry.has("program_id"):
			return {"valid": false, "error": "pending_continuation '%s' thiếu trường 'program_id'." % cid}
		var pid = str(c_entry.get("program_id", "")).strip_edges()
		if pid.is_empty():
			return {"valid": false, "error": "pending_continuation '%s' có program_id rỗng." % cid}
		if not prog_map.has(pid):
			return {"valid": false, "error": "pending_continuation '%s' trỏ tới chương trình không tồn tại: '%s'." % [cid, pid]}

		prog_counts[pid] = prog_counts.get(pid, 0) + 1
		if prog_counts[pid] > MAX_PROGRAM_PENDING_CONTINUATIONS:
			return {"valid": false, "error": "Số lượng pending_continuations của chương trình '%s' vượt quá giới hạn tối đa (%d)." % [pid, MAX_PROGRAM_PENDING_CONTINUATIONS]}

		var prog_nodes: Dictionary = prog_map[pid]["nodes"]

		if not c_entry.has("delay_node_id"):
			return {"valid": false, "error": "pending_continuation '%s' thiếu trường 'delay_node_id'." % cid}
		var d_nid = str(c_entry.get("delay_node_id", "")).strip_edges()
		if d_nid.is_empty():
			return {"valid": false, "error": "pending_continuation '%s' có delay_node_id rỗng." % cid}
		if not prog_nodes.has(d_nid):
			return {"valid": false, "error": "pending_continuation '%s' có delay_node_id '%s' không tồn tại trong chương trình '%s'." % [cid, d_nid, pid]}
		if str(prog_nodes[d_nid].get("type", "")) != "Delay":
			return {"valid": false, "error": "pending_continuation '%s' có delay_node_id '%s' không phải loại node 'Delay'." % [cid, d_nid]}

		if not c_entry.has("resume_node_id"):
			return {"valid": false, "error": "pending_continuation '%s' thiếu trường 'resume_node_id'." % cid}
		var r_nid = str(c_entry.get("resume_node_id", "")).strip_edges()
		if r_nid.is_empty():
			return {"valid": false, "error": "pending_continuation '%s' có resume_node_id rỗng." % cid}
		if not prog_nodes.has(r_nid):
			return {"valid": false, "error": "pending_continuation '%s' có resume_node_id '%s' không tồn tại trong chương trình '%s'." % [cid, r_nid, pid]}

		# Verify resume_node_id is a valid downstream target of delay_node_id
		var prog_edges: Array = prog_map[pid].get("edges", [])
		var is_downstream: bool = false
		for e in prog_edges:
			if not (e is Dictionary):
				continue
			var fn = str(e.get("from_node", e.get("fromNode", ""))).strip_edges()
			var fp = str(e.get("from_port", e.get("fromPort", ""))).strip_edges()
			var tn = str(e.get("to_node", e.get("toNode", ""))).strip_edges()
			if fn == d_nid and tn == r_nid and (fp == "out" or fp.is_empty()):
				is_downstream = true
				break
		if not is_downstream:
			return {"valid": false, "error": "pending_continuation '%s' có resume_node_id '%s' không phải đích đến hợp lệ từ node Delay '%s'." % [cid, r_nid, d_nid]}

		if not c_entry.has("duration_hours"):
			return {"valid": false, "error": "pending_continuation '%s' thiếu trường 'duration_hours'." % cid}
		var dur = c_entry.get("duration_hours")
		if not (dur is int or (dur is float and not is_nan(float(dur)) and not is_inf(float(dur)) and floor(float(dur)) == float(dur))):
			return {"valid": false, "error": "pending_continuation '%s' duration_hours không phải số nguyên." % cid}
		var dur_int: int = int(dur)
		if dur_int < 1 or dur_int > 720:
			return {"valid": false, "error": "pending_continuation '%s' duration_hours (%d) nằm ngoài khoảng [1, 720]." % [cid, dur_int]}

		for h_key in ["due_day", "due_hour", "due_total_hours"]:
			if not c_entry.has(h_key):
				return {"valid": false, "error": "pending_continuation '%s' thiếu trường thời gian '%s'." % [cid, h_key]}
			var h_val = c_entry.get(h_key)
			if not (h_val is int or (h_val is float and not is_nan(float(h_val)) and not is_inf(float(h_val)) and floor(float(h_val)) == float(h_val))):
				return {"valid": false, "error": "pending_continuation '%s' trường '%s' không phải số nguyên." % [cid, h_key]}

		var due_d = int(c_entry["due_day"])
		var due_h = int(c_entry["due_hour"])
		var due_tot = int(c_entry["due_total_hours"])

		if due_d < 1:
			return {"valid": false, "error": "pending_continuation '%s' due_day (%d) phải >= 1." % [cid, due_d]}
		if due_h < 0 or due_h > 23:
			return {"valid": false, "error": "pending_continuation '%s' due_hour (%d) phải nằm trong khoảng [0, 23]." % [cid, due_h]}
		if due_tot < 0:
			return {"valid": false, "error": "pending_continuation '%s' due_total_hours (%d) phải >= 0." % [cid, due_tot]}

		var expected_total: int = (due_d - 1) * 24 + due_h
		if due_tot != expected_total:
			return {"valid": false, "error": "pending_continuation '%s' due_total_hours (%d) không khớp công thức với due_day (%d) và due_hour (%d) (Kỳ vọng: %d)." % [cid, due_tot, due_d, due_h, expected_total]}

		var enclosing_rep_id: String = find_enclosing_repeat_node(prog_map[pid]["program"], d_nid)

		var has_rep_id: bool = c_entry.has("repeat_node_id")
		var has_rep_iter: bool = c_entry.has("repeat_iteration")
		var has_rep_count: bool = c_entry.has("repeat_count")

		var is_repeat_continuation: bool = (not enclosing_rep_id.is_empty()) or has_rep_id or has_rep_iter or has_rep_count

		if is_repeat_continuation:
			if not has_rep_id:
				if not enclosing_rep_id.is_empty():
					return {"valid": false, "error": "pending_continuation '%s' thuộc nhánh lặp của node Repeat '%s' nhưng thiếu trường 'repeat_node_id'." % [cid, enclosing_rep_id]}
				else:
					return {"valid": false, "error": "pending_continuation '%s' chứa thông tin lặp không đầy đủ (thiếu 'repeat_node_id')." % cid}

			var raw_rep_id = c_entry.get("repeat_node_id")
			if not (raw_rep_id is String):
				return {"valid": false, "error": "pending_continuation '%s' repeat_node_id phải là chuỗi (String)." % cid}
			var rep_id: String = str(raw_rep_id).strip_edges()
			if rep_id.is_empty():
				return {"valid": false, "error": "pending_continuation '%s' có repeat_node_id rỗng." % cid}
			if not prog_nodes.has(rep_id):
				return {"valid": false, "error": "pending_continuation '%s' có repeat_node_id '%s' không tồn tại trong chương trình '%s'." % [cid, rep_id, pid]}

			var rep_node = prog_nodes[rep_id]
			if str(rep_node.get("type", "")) != "Repeat":
				return {"valid": false, "error": "pending_continuation '%s' có repeat_node_id '%s' không phải loại node 'Repeat'." % [cid, rep_id]}

			if enclosing_rep_id.is_empty():
				return {"valid": false, "error": "pending_continuation '%s' có repeat_node_id '%s' nhưng node Delay '%s' không nằm trong nhánh lặp của node Repeat này." % [cid, rep_id, d_nid]}

			if rep_id != enclosing_rep_id:
				return {"valid": false, "error": "pending_continuation '%s' có repeat_node_id '%s' không khớp với node Repeat bao đóng '%s'." % [cid, rep_id, enclosing_rep_id]}

			if not has_rep_count:
				return {"valid": false, "error": "pending_continuation '%s' thiếu trường 'repeat_count'." % cid}
			var rc = c_entry.get("repeat_count")
			if not (rc is int or (rc is float and not is_nan(float(rc)) and not is_inf(float(rc)) and floor(float(rc)) == float(rc))):
				return {"valid": false, "error": "pending_continuation '%s' repeat_count không phải số nguyên." % cid}
			var rc_int: int = int(rc)
			if rc_int < 1 or rc_int > 20:
				return {"valid": false, "error": "pending_continuation '%s' repeat_count (%d) nằm ngoài khoảng [1, 20]." % [cid, rc_int]}

			var node_rc: int = int(rep_node.get("params", {}).get("count", rep_node.get("params", {}).get("iterations", 1)))
			if rc_int != node_rc:
				return {"valid": false, "error": "pending_continuation '%s' repeat_count (%d) không khớp giá trị cấu hình (%d) của node Repeat '%s'." % [cid, rc_int, node_rc, rep_id]}

			if not has_rep_iter:
				return {"valid": false, "error": "pending_continuation '%s' thiếu trường 'repeat_iteration'." % cid}
			var ri = c_entry.get("repeat_iteration")
			if not (ri is int or (ri is float and not is_nan(float(ri)) and not is_inf(float(ri)) and floor(float(ri)) == float(ri))):
				return {"valid": false, "error": "pending_continuation '%s' repeat_iteration không phải số nguyên." % cid}
			var ri_int: int = int(ri)
			if ri_int < 1 or ri_int > rc_int:
				return {"valid": false, "error": "pending_continuation '%s' repeat_iteration (%d) nằm ngoài khoảng [1, %d]." % [cid, ri_int, rc_int]}

			if not c_entry.has("steps_used"):
				return {"valid": false, "error": "pending_continuation '%s' thuộc vòng lặp Repeat nhưng thiếu trường 'steps_used'." % cid}
			var su = c_entry.get("steps_used")
			if not (su is int or (su is float and not is_nan(float(su)) and not is_inf(float(su)) and floor(float(su)) == float(su))):
				return {"valid": false, "error": "pending_continuation '%s' steps_used không phải số nguyên." % cid}
			var su_int: int = int(su)
			if su_int < 0 or su_int > MAX_STEPS_PER_RUN:
				return {"valid": false, "error": "pending_continuation '%s' steps_used (%d) nằm ngoài khoảng [0, %d]." % [cid, su_int, MAX_STEPS_PER_RUN]}
		else:
			if c_entry.has("steps_used"):
				var su = c_entry.get("steps_used")
				if not (su is int or (su is float and not is_nan(float(su)) and not is_inf(float(su)) and floor(float(su)) == float(su))):
					return {"valid": false, "error": "pending_continuation '%s' steps_used không phải số nguyên." % cid}
				var su_int: int = int(su)
				if su_int < 0 or su_int > MAX_STEPS_PER_RUN:
					return {"valid": false, "error": "pending_continuation '%s' steps_used (%d) nằm ngoài khoảng [0, %d]." % [cid, su_int, MAX_STEPS_PER_RUN]}

	return {"valid": true}

func get_pending_continuations() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for c in pending_continuations:
		result.append(c.duplicate(true))
	return result

func get_pending_continuations_for_program(prog_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for c in pending_continuations:
		if str(c.get("program_id", "")) == prog_id:
			result.append(c.duplicate(true))
	return result

func cancel_continuation(cont_id: String) -> bool:
	for i in range(pending_continuations.size()):
		if str(pending_continuations[i].get("id", "")) == cont_id:
			pending_continuations.remove_at(i)
			return true
	return false

func clear_pending_continuations_for_program(prog_id: String) -> int:
	var count: int = 0
	var kept: Array[Dictionary] = []
	for c in pending_continuations:
		if str(c.get("program_id", "")) == prog_id:
			count += 1
		else:
			kept.append(c)
	pending_continuations = kept
	return count

func schedule_continuation(
	prog_id: String,
	delay_node_id: String,
	resume_node_id: String,
	duration_hours: int,
	current_day: int,
	current_hour: int,
	extra_meta: Dictionary = {}
) -> Dictionary:
	if pending_continuations.size() >= MAX_GLOBAL_PENDING_CONTINUATIONS:
		var msg := "Hàng đợi trì hoãn toàn cục đã đầy (Tối đa %d)" % MAX_GLOBAL_PENDING_CONTINUATIONS
		log_trace(prog_id, msg, false, [], current_day)
		return {"ok": false, "reason": msg, "code": "LIMIT_GLOBAL"}

	var prog_count: int = 0
	for c in pending_continuations:
		if str(c.get("program_id", "")) == prog_id:
			prog_count += 1
	if prog_count >= MAX_PROGRAM_PENDING_CONTINUATIONS:
		var msg := "Hàng đợi trì hoãn của chương trình '%s' đã đầy (Tối đa %d)" % [prog_id, MAX_PROGRAM_PENDING_CONTINUATIONS]
		log_trace(prog_id, msg, false, [], current_day)
		return {"ok": false, "reason": msg, "code": "LIMIT_PROGRAM"}

	var cur_total: int = (current_day - 1) * 24 + current_hour
	var due_total: int = cur_total + duration_hours
	var due_day: int = 1 + int(due_total / 24)
	var due_hour: int = due_total % 24
	var cont_id: String = "cont_%d" % _next_continuation_counter
	_next_continuation_counter += 1

	var entry: Dictionary = {
		"id": cont_id,
		"program_id": prog_id,
		"delay_node_id": delay_node_id,
		"resume_node_id": resume_node_id,
		"duration_hours": duration_hours,
		"scheduled_day": current_day,
		"scheduled_hour": current_hour,
		"due_day": due_day,
		"due_hour": due_hour,
		"due_total_hours": due_total
	}
	for k in extra_meta:
		entry[k] = extra_meta[k]

	pending_continuations.append(entry)
	return {"ok": true, "continuation": entry}

func process_due_continuations(context: Dictionary) -> Array[Dictionary]:
	if bool(context.get("is_paused", false)):
		return []

	var cur_day: int = int(context.get("current_day", 1))
	var cur_hour: int = int(context.get("current_hour", 0))
	var cur_total: int = (cur_day - 1) * 24 + cur_hour

	var due: Array[Dictionary] = []
	var remaining: Array[Dictionary] = []
	for c in pending_continuations:
		if int(c.get("due_total_hours", 0)) <= cur_total:
			due.append(c)
		else:
			remaining.append(c)
	pending_continuations = remaining

	if due.is_empty():
		return []

	due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta = int(a.get("due_total_hours", 0))
		var tb = int(b.get("due_total_hours", 0))
		if ta != tb:
			return ta < tb
		var prog_a := get_program(str(a.get("program_id", "")))
		var prog_b := get_program(str(b.get("program_id", "")))
		var pa = prog_a.priority if prog_a != null else 0
		var pb = prog_b.priority if prog_b != null else 0
		if pa != pb:
			return pa > pb
		return str(a.get("id", "")) < str(b.get("id", ""))
	)

	var executed_results: Array[Dictionary] = []
	var shared_action_locks: Dictionary = context.get("shared_action_locks", {})

	for c in due:
		var cid: String = str(c.get("id", ""))
		var prog_id: String = str(c.get("program_id", ""))
		var resume_id: String = str(c.get("resume_node_id", ""))

		var prog := get_program(prog_id)
		if prog == null:
			log_trace(prog_id, "Hủy continuation '%s': Chương trình không tồn tại" % cid, false, [], cur_day)
			continue
		if not prog.enabled:
			log_trace(prog_id, "Bỏ qua continuation '%s': Chương trình '%s' đang bị tắt" % [cid, prog_id], false, [], cur_day)
			continue

		var has_resume_node: bool = false
		for n in prog.nodes:
			if str(n.get("id", "")) == resume_id:
				has_resume_node = true
				break
		if not has_resume_node:
			log_trace(prog_id, "Hủy continuation '%s': Node tiếp tục '%s' không còn tồn tại" % [cid, resume_id], false, [], cur_day)
			continue

		log_trace(prog_id, "Kích hoạt continuation '%s' (tiếp tục tại node '%s')" % [cid, resume_id], false, [], cur_day)
		var run_opts: Dictionary = {
			"dry_run": false,
			"start_node_id": resume_id,
			"continuation_id": cid,
			"shared_action_locks": shared_action_locks
		}
		if c.has("repeat_node_id") and not str(c.get("repeat_node_id", "")).is_empty():
			run_opts["repeat_node_id"] = str(c.get("repeat_node_id", ""))
			run_opts["repeat_iteration"] = int(c.get("repeat_iteration", 1))
			run_opts["repeat_count"] = int(c.get("repeat_count", 1))
		if c.has("steps_used"):
			run_opts["steps_used"] = int(c.get("steps_used", 0))

		var res := run_program(prog_id, context, run_opts)
		executed_results.append({
			"continuation": c,
			"result": res
		})

	return executed_results

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

func _execute_repeat_node(
	rep_node: Dictionary,
	prog: AutomationProgram,
	context: Dictionary,
	is_dry_run: bool,
	trace: Array,
	action_locks: Dictionary,
	actions_executed: Array[Dictionary],
	cur_day: int,
	cur_hour: int,
	start_iter: int = 1,
	start_body_node_id: String = "",
	count: int = -1,
	in_steps: int = 0
) -> Dictionary:
	var cid: String = str(rep_node.get("id", ""))
	if count < 0:
		var p_dict: Dictionary = rep_node.get("params", {}) if (rep_node.get("params") is Dictionary) else {}
		var c_val = p_dict.get("count", p_dict.get("iterations", p_dict.get("repeat_count", 1)))
		count = clampi(int(c_val), 1, 20)

	var steps: int = in_steps
	var body_node_ids: Array[String] = []
	var completed_node_ids: Array[String] = []

	for e in prog.edges:
		var fn = str(e.get("from_node", e.get("fromNode", "")))
		var fp = str(e.get("from_port", e.get("fromPort", "")))
		var tn = str(e.get("to_node", e.get("toNode", "")))
		if fn == cid:
			if fp in ["body", "out"]:
				body_node_ids.append(tn)
			elif fp == "completed":
				completed_node_ids.append(tn)

	if start_iter == 1 and start_body_node_id.is_empty():
		log_trace(prog.id, "Bắt đầu vòng lặp Repeat (%s) với %d lần lặp" % [cid, count], is_dry_run, trace, cur_day)
	else:
		log_trace(prog.id, "Tiếp tục vòng lặp Repeat (%s) tại lần lặp %d/%d (node '%s')" % [cid, start_iter, count, start_body_node_id], is_dry_run, trace, cur_day)

	var suspended: bool = false

	for iter_idx in range(start_iter, count + 1):
		log_trace(prog.id, "Repeat %s: Vòng lặp %d/%d" % [cid, iter_idx, count], is_dry_run, trace, cur_day)
		var iter_memo_bool: Dictionary = {}
		var body_queue: Array[Dictionary] = []

		if iter_idx == start_iter and not start_body_node_id.is_empty():
			for n in prog.nodes:
				if str(n.get("id", "")) == start_body_node_id:
					body_queue.append(n)
					break
		else:
			for bn_id in body_node_ids:
				for n in prog.nodes:
					if str(n.get("id", "")) == bn_id:
						body_queue.append(n)
						break

		while not body_queue.is_empty():
			steps += 1
			if steps > MAX_STEPS_PER_RUN:
				var budget_msg := "Dừng khẩn cấp: Vượt ngân sách thực thi (%d bước/tick)" % MAX_STEPS_PER_RUN
				log_trace(prog.id, budget_msg, is_dry_run, trace, cur_day)
				return {
					"ok": false,
					"reason": budget_msg,
					"trace": trace,
					"actions_executed": actions_executed,
					"steps": steps,
					"suspended": false
				}

			var b_cur: Dictionary = body_queue.pop_front()
			var b_cid: String = str(b_cur.get("id", ""))
			var b_ctype: String = str(b_cur.get("type", ""))
			var b_ctitle: String = str(b_cur.get("title", b_ctype))

			match b_ctype:
				"Action":
					var act_res := execute_action_node(b_cur, prog, context, is_dry_run, trace, action_locks)
					actions_executed.append({
						"node_id": b_cid,
						"subtype": b_cur.get("subtype", ""),
						"ok": act_res.get("ok", false),
						"detail": act_res.get("delta", act_res.get("reason", ""))
					})
					for e in prog.edges:
						var fn = str(e.get("from_node", e.get("fromNode", "")))
						if fn == b_cid:
							var tn = str(e.get("to_node", e.get("toNode", "")))
							for n in prog.nodes:
								if str(n.get("id", "")) == tn:
									body_queue.append(n)
									break

				"Condition", "LogicGate":
					var val := evaluate_condition_node(b_cur, prog, context, iter_memo_bool)
					log_trace(prog.id, "Đánh giá %s = %s" % [b_ctitle, "TRUE" if val else "FALSE"], is_dry_run, trace, cur_day)
					for e in prog.edges:
						var fn = str(e.get("from_node", e.get("fromNode", "")))
						if fn == b_cid:
							var tn = str(e.get("to_node", e.get("toNode", "")))
							for n in prog.nodes:
								if str(n.get("id", "")) == tn:
									var nt: String = str(n.get("type", ""))
									if nt in ["IfElse", "LogicGate"]:
										body_queue.append(n)
									elif val:
										body_queue.append(n)
									break

				"IfElse":
					var cond_node: Dictionary = {}
					for e in prog.edges:
						var tn = str(e.get("to_node", e.get("toNode", "")))
						var tp = str(e.get("to_port", e.get("toPort", "")))
						if tn == b_cid and tp == "cond":
							var fn = str(e.get("from_node", e.get("fromNode", "")))
							for n in prog.nodes:
								if str(n.get("id", "")) == fn:
									cond_node = n
									break
							if not cond_node.is_empty():
								break

					if cond_node.is_empty():
						for e in prog.edges:
							var tn = str(e.get("to_node", e.get("toNode", "")))
							if tn == b_cid:
								var fn = str(e.get("from_node", e.get("fromNode", "")))
								for n in prog.nodes:
									if str(n.get("id", "")) == fn and str(n.get("type", "")) in ["Condition", "LogicGate"]:
										cond_node = n
										break
								if not cond_node.is_empty():
									break

					var cond_val: bool = false
					if not cond_node.is_empty():
						cond_val = evaluate_condition_node(cond_node, prog, context, iter_memo_bool)

					var branch_port: String = "true" if cond_val else "false"
					log_trace(prog.id, "Nhánh IF/ELSE chọn cổng [%s]" % branch_port.to_upper(), is_dry_run, trace, cur_day)

					for e in prog.edges:
						var fn = str(e.get("from_node", e.get("fromNode", "")))
						var fp = str(e.get("from_port", e.get("fromPort", "")))
						if fn == b_cid and fp == branch_port:
							var tn = str(e.get("to_node", e.get("toNode", "")))
							for n in prog.nodes:
								if str(n.get("id", "")) == tn:
									body_queue.append(n)
									break

				"End":
					log_trace(prog.id, "Kết thúc vòng lặp tại Node End (%s)" % b_cid, is_dry_run, trace, cur_day)
					body_queue.clear()

				"Delay":
					var d_p: Dictionary = b_cur.get("params", {}) if (b_cur.get("params") is Dictionary) else {}
					var d_val = d_p.get("duration_hours", d_p.get("duration", d_p.get("durationHours", 1)))
					var duration: int = clampi(int(d_val), 1, 720)
					var cur_total_h: int = (cur_day - 1) * 24 + cur_hour
					var due_total_h: int = cur_total_h + duration
					var due_d: int = 1 + int(due_total_h / 24)
					var due_h: int = due_total_h % 24

					var d_out_nodes: Array[String] = []
					for e in prog.edges:
						var fn = str(e.get("from_node", e.get("fromNode", "")))
						var fp = str(e.get("from_port", e.get("fromPort", "")))
						if fn == b_cid and fp == "out":
							d_out_nodes.append(str(e.get("to_node", e.get("toNode", ""))))

					if is_dry_run:
						var sim_msg := "Trì hoãn %d giờ trong vòng lặp (vòng %d): Dự kiến Ngày %d, %02d:00" % [
							duration, iter_idx, due_d, due_h
						]
						log_trace(prog.id, sim_msg, is_dry_run, trace, cur_day)
					else:
						if d_out_nodes.is_empty():
							log_trace(prog.id, "Node Delay (%s) trong vòng lặp không có nhánh 'out'" % b_cid, is_dry_run, trace, cur_day)
						else:
							for dn_id in d_out_nodes:
								var sched_res := schedule_continuation(prog.id, b_cid, dn_id, duration, cur_day, cur_hour, {
									"repeat_node_id": cid,
									"repeat_iteration": iter_idx,
									"repeat_count": count,
									"steps_used": steps
								})
								if sched_res.get("ok", false):
									var c_info: Dictionary = sched_res.get("continuation", {})
									var sched_msg := "Đã lập lịch trì hoãn %s trong vòng lặp: %d giờ → '%s' (vòng %d/%d, Ngày %d, %02d:00)" % [
										str(c_info.get("id")), duration, dn_id, iter_idx, count, due_d, due_h
									]
									log_trace(prog.id, sched_msg, is_dry_run, trace, cur_day)
								else:
									var err_msg := "Lỗi lập lịch trì hoãn trong vòng lặp tại node '%s': %s" % [b_cid, sched_res.get("reason", "")]
									log_trace(prog.id, err_msg, is_dry_run, trace, cur_day)

					suspended = true
					break

		if suspended:
			break

	if suspended:
		return {
			"ok": true,
			"suspended": true,
			"steps": steps,
			"completed_node_ids": []
		}

	log_trace(prog.id, "Repeat %s hoàn thành tất cả %d lần lặp" % [cid, count], is_dry_run, trace, cur_day)
	return {
		"ok": true,
		"suspended": false,
		"steps": steps,
		"completed_node_ids": completed_node_ids
	}

func run_program(prog_id: String, context: Dictionary, options: Dictionary = {}) -> Dictionary:
	var prog := get_program(prog_id)
	if prog == null:
		return {"ok": false, "reason": "Không tìm thấy chương trình '%s'" % prog_id, "trace": []}

	var is_dry_run: bool = bool(options.get("dry_run", false))
	var cur_day: int = int(context.get("current_day", 1))
	var cur_hour: int = int(context.get("current_hour", 0))
	var trace: Array = []

	var validation := AutomationGraphValidator.validate_program(prog)
	if not validation.get("valid", false):
		var err_str: String = "; ".join(validation.get("errors", ["Lỗi không xác định"]))
		log_trace(prog.id, "Từ chối chạy do lỗi đồ thị: %s" % err_str, is_dry_run, trace, cur_day)
		return {"ok": false, "reason": err_str, "errors": validation.get("errors", []), "trace": trace}

	var action_locks: Dictionary = options.get("shared_action_locks", {})
	var memo_bool: Dictionary = {}
	var steps: int = int(options.get("steps_used", 0))
	var actions_executed: Array[Dictionary] = []

	var queue: Array[Dictionary] = []

	var repeat_node_id: String = str(options.get("repeat_node_id", ""))
	if not repeat_node_id.is_empty():
		var rep_node: Dictionary = {}
		for n in prog.nodes:
			if str(n.get("id", "")) == repeat_node_id:
				rep_node = n
				break
		if rep_node.is_empty():
			var err_rep := "Không tìm thấy Repeat node '%s' để tiếp tục" % repeat_node_id
			log_trace(prog.id, err_rep, is_dry_run, trace, cur_day)
			return {"ok": false, "reason": err_rep, "trace": trace, "actions_executed": actions_executed}

		var rep_iter: int = int(options.get("repeat_iteration", 1))
		var rep_cnt: int = int(options.get("repeat_count", 1))
		var resume_nid: String = str(options.get("start_node_id", ""))

		var rep_res := _execute_repeat_node(
			rep_node, prog, context, is_dry_run, trace, action_locks, actions_executed,
			cur_day, cur_hour, rep_iter, resume_nid, rep_cnt, steps
		)
		steps = int(rep_res.get("steps", steps))
		if not rep_res.get("ok", false):
			return rep_res

		if not rep_res.get("suspended", false):
			for cn_id in rep_res.get("completed_node_ids", []):
				for n in prog.nodes:
					if str(n.get("id", "")) == cn_id:
						queue.append(n)
						break
	else:
		var start_node_id: String = str(options.get("start_node_id", ""))
		if not start_node_id.is_empty():
			for n in prog.nodes:
				if str(n.get("id", "")) == start_node_id:
					queue.append(n)
					break
		else:
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

			"Delay":
				var d_p: Dictionary = cur.get("params", {}) if (cur.get("params") is Dictionary) else {}
				var d_val = d_p.get("duration_hours", d_p.get("duration", d_p.get("durationHours", 1)))
				var duration: int = clampi(int(d_val), 1, 720)
				var cur_day_val: int = cur_day
				var cur_hour_val: int = cur_hour
				var cur_total_h: int = (cur_day_val - 1) * 24 + cur_hour_val
				var due_total_h: int = cur_total_h + duration
				var due_d: int = 1 + int(due_total_h / 24)
				var due_h: int = due_total_h % 24

				var out_nodes: Array[String] = []
				for e in prog.edges:
					var fn = str(e.get("from_node", e.get("fromNode", "")))
					var fp = str(e.get("from_port", e.get("fromPort", "")))
					if fn == cid and fp == "out":
						var tn = str(e.get("to_node", e.get("toNode", "")))
						out_nodes.append(tn)

				if is_dry_run:
					var sim_msg := "Trì hoãn %d giờ: Dự kiến kích hoạt vào Ngày %d, %02d:00 (Nối %d node)" % [
						duration, due_d, due_h, out_nodes.size()
					]
					log_trace(prog.id, sim_msg, is_dry_run, trace, cur_day_val)
				else:
					if out_nodes.is_empty():
						log_trace(prog.id, "Node Delay (%s) không có nhánh ra 'out'" % cid, is_dry_run, trace, cur_day_val)
					else:
						for target_nid in out_nodes:
							var sched_res := schedule_continuation(prog.id, cid, target_nid, duration, cur_day_val, cur_hour_val, {
								"steps_used": steps
							})
							if sched_res.get("ok", false):
								var c_info: Dictionary = sched_res.get("continuation", {})
								var sched_msg := "Đã lập lịch trì hoãn %s: %d giờ → tiếp tục tại '%s' (Đến hạn: Ngày %d, %02d:00)" % [
									str(c_info.get("id")), duration, target_nid, due_d, due_h
								]
								log_trace(prog.id, sched_msg, is_dry_run, trace, cur_day_val)
							else:
								var err_msg := "Lỗi lập lịch trì hoãn tại node '%s': %s" % [cid, sched_res.get("reason", "")]
								log_trace(prog.id, err_msg, is_dry_run, trace, cur_day_val)
				# Suspend current execution path: do not append out_nodes to queue

			"Repeat":
				var rep_res := _execute_repeat_node(
					cur, prog, context, is_dry_run, trace, action_locks, actions_executed,
					cur_day, cur_hour, 1, "", -1, steps
				)
				steps = int(rep_res.get("steps", steps))
				if not rep_res.get("ok", false):
					return rep_res

				if not rep_res.get("suspended", false):
					for cn_id in rep_res.get("completed_node_ids", []):
						for n in prog.nodes:
							if str(n.get("id", "")) == cn_id:
								queue.append(n)
								break

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

	# Ensure authoritative current_day and current_hour in context
	if not context.has("current_day") or int(context.get("current_day", 1)) < 1:
		context["current_day"] = 1
	if not context.has("current_hour") or int(context.get("current_hour", 0)) < 0:
		context["current_hour"] = 0

	var shared_action_locks: Dictionary = {}
	context["shared_action_locks"] = shared_action_locks
	var executed_programs: Array[String] = []

	# First, process due continuations (Package 1Y)
	var cont_results := process_due_continuations(context)
	for cr in cont_results:
		var c_dict: Dictionary = cr.get("continuation", {})
		var pid: String = str(c_dict.get("program_id", ""))
		var c_res: Dictionary = cr.get("result", {})
		if not pid.is_empty() and not executed_programs.has(pid):
			var acts: Array = c_res.get("actions_executed", [])
			if not acts.is_empty():
				executed_programs.append(pid)

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

	for prog in enabled_progs:
		var res := run_program(prog.id, context, {
			"dry_run": false,
			"shared_action_locks": shared_action_locks
		})
		if res.get("ok", false):
			var acts: Array = res.get("actions_executed", [])
			if not acts.is_empty() and not executed_programs.has(prog.id):
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
	is_paused: bool = false,
	current_day: int = -1,
	current_hour: int = -1
) -> Array[String]:
	var actions_taken: Array[String] = []
	execution_budget_used = 0
	total_evaluations += 1

	var eff_day: int = current_day
	var eff_hour: int = current_hour
	if eff_day < 1 or eff_hour < 0:
		var tm = Engine.get_main_loop().root.get_node_or_null("/root/TimeManager") if (Engine.get_main_loop() and Engine.get_main_loop().has_method("get_root") and Engine.get_main_loop().root) else null
		if tm != null:
			if eff_day < 1:
				eff_day = int(tm.get("current_day")) if tm.get("current_day") != null else 1
			if eff_hour < 0:
				eff_hour = int(tm.get("current_hour")) if tm.get("current_hour") != null else 0
		else:
			if eff_day < 1:
				eff_day = 1
			if eff_hour < 0:
				eff_hour = 0

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
		"current_day": eff_day,
		"current_hour": eff_hour
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
	var serialized_conts: Array = []
	for c in pending_continuations:
		serialized_conts.append(c.duplicate(true))
	return {
		"programs": serialized_progs,
		"execution_logs": execution_logs.duplicate(),
		"pending_continuations": serialized_conts,
		"next_continuation_counter": _next_continuation_counter
	}

func deserialize(data: Dictionary) -> bool:
	if not data.is_empty():
		var val_res := validate_automation_data(data)
		if not val_res.get("valid", false):
			push_error("AutomationManager.deserialize failed validation: " + val_res.get("error", ""))
			return false

	var new_programs: Array[AutomationProgram] = []
	var new_logs: Array[String] = []
	var new_continuations: Array[Dictionary] = []
	var new_prog_counter: int = _next_program_counter
	var new_cont_counter: int = _next_continuation_counter

	var raw_progs = data.get("programs", [])
	if raw_progs is Array:
		for p_data in raw_progs:
			if p_data is Dictionary:
				var prog := AutomationProgram.deserialize(p_data)
				new_programs.append(prog)
				# Update counter to avoid colliding IDs
				var pid_str := prog.id
				if pid_str.begins_with("prog_"):
					var num_part := pid_str.trim_prefix("prog_").to_int()
					if num_part >= new_prog_counter:
						new_prog_counter = num_part + 1

	var raw_logs = data.get("execution_logs", [])
	if raw_logs is Array:
		for l in raw_logs:
			new_logs.append(str(l))

	var raw_conts = data.get("pending_continuations", [])
	if raw_conts is Array:
		for c_data in raw_conts:
			if c_data is Dictionary:
				new_continuations.append(c_data.duplicate(true))
				var cid_str: String = str(c_data.get("id", ""))
				if cid_str.begins_with("cont_"):
					var num_part := cid_str.trim_prefix("cont_").to_int()
					if num_part >= new_cont_counter:
						new_cont_counter = num_part + 1

	if data.has("next_continuation_counter"):
		var ncc = int(data.get("next_continuation_counter", 1))
		if ncc > new_cont_counter:
			new_cont_counter = ncc

	programs = new_programs
	execution_logs = new_logs
	pending_continuations = new_continuations
	_next_program_counter = new_prog_counter
	_next_continuation_counter = new_cont_counter
	return true
