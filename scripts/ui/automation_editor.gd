class_name AutomationEditor
extends Control
## Functional Visual Automation Graph Editor for KINGDOMS UNBOUND.
## Conforms to HTML Stage 11 reference and Package 1V specification.
## Features GraphEdit canvas, node wiring, parameter inspector, validation, and dry-run simulation.

signal editor_closed()

const PORT_TYPE_FLOW: int = 0
const PORT_TYPE_BOOL: int = 1

const COLOR_FLOW: Color = Color(0.3, 0.9, 0.4)
const COLOR_BOOL: Color = Color(0.3, 0.7, 1.0)

var automation_mgr: AutomationManager = null
var current_program: AutomationProgram = null
var selected_node_id: String = ""
var context_provider: Callable

# UI Node References
@onready var program_select: OptionButton = $Panel/MarginContainer/VBoxContainer/TopBar/ProgramSelect
@onready var btn_new_prog: Button = $Panel/MarginContainer/VBoxContainer/TopBar/NewProgBtn
@onready var btn_dup_prog: Button = $Panel/MarginContainer/VBoxContainer/TopBar/DupProgBtn
@onready var btn_del_prog: Button = $Panel/MarginContainer/VBoxContainer/TopBar/DelProgBtn
@onready var check_enabled: CheckBox = $Panel/MarginContainer/VBoxContainer/TopBar/EnableCheck
@onready var spin_priority: SpinBox = $Panel/MarginContainer/VBoxContainer/TopBar/PrioritySpin
@onready var btn_close: Button = $Panel/MarginContainer/VBoxContainer/TopBar/CloseBtn

@onready var graph_edit: GraphEdit = $Panel/MarginContainer/VBoxContainer/HSplit/LeftBox/GraphEdit
@onready var btn_del_node: Button = $Panel/MarginContainer/VBoxContainer/HSplit/LeftBox/Palette/DelNodeBtn

# Inspector Controls
@onready var inspector_node_title: Label = $Panel/MarginContainer/VBoxContainer/HSplit/RightBox/InspectorTitle
@onready var inspector_params_box: VBoxContainer = $Panel/MarginContainer/VBoxContainer/HSplit/RightBox/ParamsBox

# Validation & Simulation Controls
@onready var btn_validate: Button = $Panel/MarginContainer/VBoxContainer/HSplit/RightBox/ButtonsHBox/ValidateBtn
@onready var btn_dry_run: Button = $Panel/MarginContainer/VBoxContainer/HSplit/RightBox/ButtonsHBox/DryRunBtn
@onready var label_status: Label = $Panel/MarginContainer/VBoxContainer/HSplit/RightBox/StatusBadge
@onready var text_trace: TextEdit = $Panel/MarginContainer/VBoxContainer/HSplit/RightBox/TraceText

var _inspector_controls: Dictionary = {}

func _ready() -> void:
	_connect_ui_signals()
	_setup_palette_buttons()

func setup(p_auto_mgr: AutomationManager, p_context_provider: Callable = Callable()) -> void:
	automation_mgr = p_auto_mgr
	context_provider = p_context_provider
	refresh_programs_list()

func _connect_ui_signals() -> void:
	if btn_close:
		btn_close.pressed.connect(_on_close_pressed)
	if program_select:
		program_select.item_selected.connect(_on_program_selected)
	if btn_new_prog:
		btn_new_prog.pressed.connect(_on_new_program_pressed)
	if btn_dup_prog:
		btn_dup_prog.pressed.connect(_on_duplicate_program_pressed)
	if btn_del_prog:
		btn_del_prog.pressed.connect(_on_delete_program_pressed)
	if check_enabled:
		check_enabled.toggled.connect(_on_enabled_toggled)
	if spin_priority:
		spin_priority.value_changed.connect(_on_priority_changed)

	if graph_edit:
		graph_edit.connection_request.connect(_on_connection_request)
		graph_edit.disconnection_request.connect(_on_disconnection_request)
		graph_edit.delete_nodes_request.connect(_on_delete_nodes_request)
		graph_edit.node_selected.connect(_on_graph_node_selected)
		graph_edit.node_deselected.connect(_on_graph_node_deselected)

	if btn_del_node:
		btn_del_node.pressed.connect(_on_delete_selected_node_pressed)
	if btn_validate:
		btn_validate.pressed.connect(_on_validate_pressed)
	if btn_dry_run:
		btn_dry_run.pressed.connect(_on_dry_run_pressed)

func _setup_palette_buttons() -> void:
	var left_box = $Panel/MarginContainer/VBoxContainer/HSplit/LeftBox/Palette
	if not left_box:
		return
	var add_trigger: Button = left_box.get_node_or_null("AddTriggerBtn")
	if add_trigger:
		add_trigger.pressed.connect(func(): add_node_to_current("Trigger", "OnTick"))
	var add_cond_res: Button = left_box.get_node_or_null("AddCondResBtn")
	if add_cond_res:
		add_cond_res.pressed.connect(func(): add_node_to_current("Condition", "ResourceCompare", {"resource": "Food", "op": "<", "value": 60}))
	var add_cond_fat: Button = left_box.get_node_or_null("AddCondFatBtn")
	if add_cond_fat:
		add_cond_fat.pressed.connect(func(): add_node_to_current("Condition", "CitizenFatigue", {"value": 80}))
	var add_cond_store: Button = left_box.get_node_or_null("AddCondStoreBtn")
	if add_cond_store:
		add_cond_store.pressed.connect(func(): add_node_to_current("Condition", "StorageFull", {}))
	var add_logic_and: Button = left_box.get_node_or_null("AddLogicAndBtn")
	if add_logic_and:
		add_logic_and.pressed.connect(func(): add_node_to_current("LogicGate", "AND"))
	var add_logic_or: Button = left_box.get_node_or_null("AddLogicOrBtn")
	if add_logic_or:
		add_logic_or.pressed.connect(func(): add_node_to_current("LogicGate", "OR"))
	var add_logic_not: Button = left_box.get_node_or_null("AddLogicNotBtn")
	if add_logic_not:
		add_logic_not.pressed.connect(func(): add_node_to_current("LogicGate", "NOT"))
	var add_ifelse: Button = left_box.get_node_or_null("AddIfElseBtn")
	if add_ifelse:
		add_ifelse.pressed.connect(func(): add_node_to_current("IfElse", "Branch"))
	var add_act_role: Button = left_box.get_node_or_null("AddActRoleBtn")
	if add_act_role:
		add_act_role.pressed.connect(func(): add_node_to_current("Action", "AssignRole", {"from_role": "idle", "to_role": "farmer"}))
	var add_act_boost: Button = left_box.get_node_or_null("AddActBoostBtn")
	if add_act_boost:
		add_act_boost.pressed.connect(func(): add_node_to_current("Action", "BoostJobPriority", {"job_type": "farmer", "delta_priority": 1}))
	var add_act_log: Button = left_box.get_node_or_null("AddActLogBtn")
	if add_act_log:
		add_act_log.pressed.connect(func(): add_node_to_current("Action", "EmitLog", {"message": "Nhật ký tự động"}))
	var add_end: Button = left_box.get_node_or_null("AddEndBtn")
	if add_end:
		add_end.pressed.connect(func(): add_node_to_current("End", "Default"))

# -----------------------------------------------------------------------------
# Program List & Selection
# -----------------------------------------------------------------------------

func refresh_programs_list() -> void:
	if automation_mgr == null:
		return
	program_select.clear()
	var all_progs := automation_mgr.get_all_programs()
	if all_progs.is_empty():
		# Create an initial sample program if none exist
		var initial_prog := automation_mgr.create_program("Quản lý Lương thực", 10)
		var n_cond = automation_mgr.add_node(initial_prog, "Condition", "ResourceCompare", 180, 80, {"resource": "Food", "op": "<", "value": 60})
		var n_if = automation_mgr.add_node(initial_prog, "IfElse", "Branch", 360, 80, {})
		var n_act_t = automation_mgr.add_node(initial_prog, "Action", "AssignRole", 540, 40, {"from_role": "idle", "to_role": "farmer"})
		var n_act_f = automation_mgr.add_node(initial_prog, "Action", "EmitLog", 540, 150, {"message": "Kho lương thực ổn định"})
		automation_mgr.connect_nodes(initial_prog, "n_start", "out", n_cond["id"], "in")
		automation_mgr.connect_nodes(initial_prog, n_cond["id"], "bool", n_if["id"], "cond")
		automation_mgr.connect_nodes(initial_prog, n_if["id"], "true", n_act_t["id"], "in")
		automation_mgr.connect_nodes(initial_prog, n_if["id"], "false", n_act_f["id"], "in")
		all_progs = automation_mgr.get_all_programs()

	for i in range(all_progs.size()):
		var p = all_progs[i]
		var label := "[%s] %s (Prio %d)" % ["BẬT" if p.enabled else "TẮT", p.name, p.priority]
		program_select.add_item(label, i)

	if not all_progs.is_empty():
		select_program(all_progs[0].id)

func select_program(prog_id: String) -> void:
	if automation_mgr == null:
		return
	current_program = automation_mgr.get_program(prog_id)
	if current_program == null:
		return

	# Update TopBar controls
	for i in range(program_select.item_count):
		var p = automation_mgr.get_all_programs()[i]
		if p.id == prog_id:
			program_select.selected = i
			break

	check_enabled.set_pressed_no_signal(current_program.enabled)
	spin_priority.set_value_no_signal(current_program.priority)
	selected_node_id = ""
	_clear_inspector()
	_rebuild_graph_view()

func _on_program_selected(index: int) -> void:
	var all_progs := automation_mgr.get_all_programs()
	if index >= 0 and index < all_progs.size():
		select_program(all_progs[index].id)

func _on_new_program_pressed() -> void:
	if automation_mgr == null:
		return
	var prog := automation_mgr.create_program("Chương trình Mới", 5)
	refresh_programs_list()
	select_program(prog.id)

func _on_duplicate_program_pressed() -> void:
	if automation_mgr == null or current_program == null:
		return
	var dup := automation_mgr.duplicate_program(current_program.id)
	refresh_programs_list()
	if dup:
		select_program(dup.id)

func _on_delete_program_pressed() -> void:
	if automation_mgr == null or current_program == null:
		return
	var target_id := current_program.id
	automation_mgr.delete_program(target_id)
	current_program = null
	refresh_programs_list()

func _on_enabled_toggled(button_pressed: bool) -> void:
	if current_program:
		current_program.enabled = button_pressed
		_update_current_program_select_label()

func _on_priority_changed(value: float) -> void:
	if current_program:
		current_program.priority = int(value)
		_update_current_program_select_label()

func _update_current_program_select_label() -> void:
	if current_program and program_select.selected >= 0:
		var label := "[%s] %s (Prio %d)" % ["BẬT" if current_program.enabled else "TẮT", current_program.name, current_program.priority]
		program_select.set_item_text(program_select.selected, label)

# -----------------------------------------------------------------------------
# GraphEdit Visual Building & Node Wiring
# -----------------------------------------------------------------------------

func _rebuild_graph_view() -> void:
	if graph_edit == null or current_program == null:
		return

	graph_edit.clear_connections()
	for child in graph_edit.get_children():
		if child is GraphNode:
			child.queue_free()

	# Re-create GraphNode elements
	for n_data in current_program.nodes:
		_create_graph_node_ui(n_data)

	# Wait a frame or reconnect after nodes are added
	call_deferred("_reconnect_all_edges")

func _create_graph_node_ui(n_data: Dictionary) -> GraphNode:
	var gn := GraphNode.new()
	var nid: String = str(n_data.get("id", ""))
	gn.name = nid
	gn.title = str(n_data.get("title", n_data.get("type", "")))
	gn.position_offset = Vector2(float(n_data.get("x", 100.0)), float(n_data.get("y", 100.0)))
	gn.resizable = false

	# Position drag persistence
	gn.dragged.connect(func(_from_pos: Vector2, to_pos: Vector2):
		n_data["x"] = to_pos.x
		n_data["y"] = to_pos.y
	)

	var ntype: String = str(n_data.get("type", ""))
	var subtype: String = str(n_data.get("subtype", ""))

	match ntype:
		"Trigger":
			var l0 := Label.new()
			l0.text = "⚡ Kích hoạt mỗi Tick"
			gn.add_child(l0)
			gn.set_slot(0, false, 0, Color.WHITE, true, PORT_TYPE_FLOW, COLOR_FLOW)

		"Condition":
			var l0 := Label.new()
			l0.text = _format_condition_label(n_data)
			gn.add_child(l0)
			gn.set_slot(0, true, PORT_TYPE_FLOW, COLOR_FLOW, true, PORT_TYPE_BOOL, COLOR_BOOL)

		"LogicGate":
			if subtype == "NOT":
				var l0 := Label.new()
				l0.text = "NOT Đảo bit [in → bool]"
				gn.add_child(l0)
				gn.set_slot(0, true, PORT_TYPE_BOOL, COLOR_BOOL, true, PORT_TYPE_BOOL, COLOR_BOOL)
			else:
				var l0 := Label.new()
				l0.text = "%s Đầu vào A" % subtype
				gn.add_child(l0)
				gn.set_slot(0, true, PORT_TYPE_BOOL, COLOR_BOOL, true, PORT_TYPE_BOOL, COLOR_BOOL)

				var l1 := Label.new()
				l1.text = "%s Đầu vào B" % subtype
				gn.add_child(l1)
				gn.set_slot(1, true, PORT_TYPE_BOOL, COLOR_BOOL, false, 0, Color.WHITE)

		"IfElse":
			var l0 := Label.new()
			l0.text = "Luồng vào → [TRUE]"
			gn.add_child(l0)
			gn.set_slot(0, true, PORT_TYPE_FLOW, COLOR_FLOW, true, PORT_TYPE_FLOW, COLOR_FLOW)

			var l1 := Label.new()
			l1.text = "Điều kiện (cond) → [FALSE]"
			gn.add_child(l1)
			gn.set_slot(1, true, PORT_TYPE_BOOL, COLOR_BOOL, true, PORT_TYPE_FLOW, COLOR_FLOW)

		"Action":
			var l0 := Label.new()
			l0.text = _format_action_label(n_data)
			gn.add_child(l0)
			gn.set_slot(0, true, PORT_TYPE_FLOW, COLOR_FLOW, true, PORT_TYPE_FLOW, COLOR_FLOW)

		"End":
			var l0 := Label.new()
			l0.text = "🛑 Dừng luồng"
			gn.add_child(l0)
			gn.set_slot(0, true, PORT_TYPE_FLOW, COLOR_FLOW, false, 0, Color.WHITE)

	graph_edit.add_child(gn)
	return gn

func _format_condition_label(n_data: Dictionary) -> String:
	var sub = str(n_data.get("subtype", "ResourceCompare"))
	var p = n_data.get("params", {}) if (n_data.get("params") is Dictionary) else {}
	match sub:
		"ResourceCompare":
			return "❓ %s %s %s" % [str(p.get("resource", "Food")), str(p.get("op", "<")), str(p.get("value", 60))]
		"CitizenFatigue":
			return "❓ Mệt mỏi > %s" % str(p.get("value", 80))
		"StorageFull":
			return "❓ Kho đã đầy"
	return "❓ Điều kiện"

func _format_action_label(n_data: Dictionary) -> String:
	var sub = str(n_data.get("subtype", "EmitLog"))
	var p = n_data.get("params", {}) if (n_data.get("params") is Dictionary) else {}
	match sub:
		"AssignRole":
			return "🎯 %s → %s" % [str(p.get("from_role", "idle")).capitalize(), str(p.get("to_role", "farmer")).capitalize()]
		"BoostJobPriority":
			return "🎯 Boost %s %+d" % [str(p.get("job_type", "farmer")), int(p.get("delta_priority", 1))]
		"EmitLog":
			return "📝 Log: %s" % str(p.get("message", "Nhật ký"))
	return "🎯 Hành động"

func _reconnect_all_edges() -> void:
	if current_program == null or graph_edit == null:
		return
	graph_edit.clear_connections()
	for ed in current_program.edges:
		var fn: String = str(ed.get("from_node", ed.get("fromNode", "")))
		var fp: String = str(ed.get("from_port", ed.get("fromPort", "")))
		var tn: String = str(ed.get("to_node", ed.get("toNode", "")))
		var tp: String = str(ed.get("to_port", ed.get("toPort", "")))

		var n_from := _find_node_data(fn)
		var n_to := _find_node_data(tn)
		if n_from.is_empty() or n_to.is_empty():
			continue

		var from_idx := _port_name_to_index(n_from, false, fp)
		var to_idx := _port_name_to_index(n_to, true, tp)
		graph_edit.connect_node(StringName(fn), from_idx, StringName(tn), to_idx)

func _find_node_data(nid: String) -> Dictionary:
	if current_program == null:
		return {}
	for n in current_program.nodes:
		if str(n.get("id")) == nid:
			return n
	return {}

func _port_name_to_index(n_data: Dictionary, is_left: bool, port_name: String) -> int:
	var ntype: String = str(n_data.get("type", ""))
	if ntype == "LogicGate":
		if is_left and port_name == "inB":
			return 1
		return 0
	elif ntype == "IfElse":
		if is_left and port_name in ["cond"]:
			return 1
		if not is_left and port_name in ["false"]:
			return 1
		return 0
	return 0

func _index_to_port_name(n_data: Dictionary, is_left: bool, port_idx: int) -> String:
	var ntype: String = str(n_data.get("type", ""))
	var subtype: String = str(n_data.get("subtype", ""))
	match ntype:
		"Trigger":
			return "out" if not is_left else ""
		"Condition":
			return "in" if is_left else "bool"
		"LogicGate":
			if subtype == "NOT":
				return "in" if is_left else "bool"
			else:
				if is_left:
					return "inB" if port_idx == 1 else "inA"
				else:
					return "bool"
		"IfElse":
			if is_left:
				return "cond" if port_idx == 1 else "in"
			else:
				return "false" if port_idx == 1 else "true"
		"Action":
			return "in" if is_left else "out"
		"End":
			return "in" if is_left else ""
	return "in" if is_left else "out"

func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	if current_program == null or automation_mgr == null:
		return
	var n_from := _find_node_data(String(from_node))
	var n_to := _find_node_data(String(to_node))
	if n_from.is_empty() or n_to.is_empty():
		return

	var fp_name := _index_to_port_name(n_from, false, from_port)
	var tp_name := _index_to_port_name(n_to, true, to_port)

	var res := automation_mgr.connect_nodes(current_program, String(from_node), fp_name, String(to_node), tp_name)
	if res.get("ok", false):
		graph_edit.connect_node(from_node, from_port, to_node, to_port)
		label_status.text = "Đã nối: %s:%s → %s:%s" % [from_node, fp_name, to_node, tp_name]
		label_status.modulate = Color(0.4, 0.9, 0.4)
	else:
		label_status.text = "Lỗi nối: %s" % res.get("reason", "")
		label_status.modulate = Color(1.0, 0.4, 0.4)

func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	if current_program == null or automation_mgr == null:
		return
	var n_from := _find_node_data(String(from_node))
	var n_to := _find_node_data(String(to_node))
	var fp_name := _index_to_port_name(n_from, false, from_port)
	var tp_name := _index_to_port_name(n_to, true, to_port)

	automation_mgr.disconnect_nodes(current_program, String(from_node), fp_name, String(to_node), tp_name)
	graph_edit.disconnect_node(from_node, from_port, to_node, to_port)
	label_status.text = "Đã ngắt dây: %s → %s" % [from_node, to_node]
	label_status.modulate = Color(0.8, 0.8, 0.8)

func _on_delete_nodes_request(node_names: Array[StringName]) -> void:
	for n_name in node_names:
		delete_node_by_id(String(n_name))

func add_node_to_current(type: String, subtype: String = "", params: Dictionary = {}) -> void:
	if current_program == null or automation_mgr == null:
		return
	var center_offset := graph_edit.scroll_offset + Vector2(200, 150)
	var n_data := automation_mgr.add_node(current_program, type, subtype, center_offset.x, center_offset.y, params)
	_create_graph_node_ui(n_data)
	select_node(str(n_data.get("id")))

func delete_node_by_id(nid: String) -> void:
	if current_program == null:
		return
	# Remove edges attached to this node
	var kept_edges: Array[Dictionary] = []
	for ed in current_program.edges:
		var fn = str(ed.get("from_node", ed.get("fromNode", "")))
		var tn = str(ed.get("to_node", ed.get("toNode", "")))
		if fn != nid and tn != nid:
			kept_edges.append(ed)
	current_program.edges = kept_edges

	# Remove node
	for i in range(current_program.nodes.size()):
		if str(current_program.nodes[i].get("id")) == nid:
			current_program.nodes.remove_at(i)
			break

	var gn = graph_edit.get_node_or_null(nid)
	if gn:
		gn.queue_free()

	if selected_node_id == nid:
		selected_node_id = ""
		_clear_inspector()

	call_deferred("_reconnect_all_edges")

func _on_delete_selected_node_pressed() -> void:
	if not selected_node_id.is_empty():
		delete_node_by_id(selected_node_id)

# -----------------------------------------------------------------------------
# Node Selection & Parameter Inspector
# -----------------------------------------------------------------------------

func _on_graph_node_selected(node: Node) -> void:
	if node is GraphNode:
		select_node(node.name)

func _on_graph_node_deselected(node: Node) -> void:
	if node is GraphNode and selected_node_id == node.name:
		selected_node_id = ""
		_clear_inspector()

func select_node(nid: String) -> void:
	selected_node_id = nid
	var n_data := _find_node_data(nid)
	if n_data.is_empty():
		_clear_inspector()
		return
	_build_inspector_for_node(n_data)

func _clear_inspector() -> void:
	inspector_node_title.text = "Chưa chọn Node"
	for child in inspector_params_box.get_children():
		child.queue_free()
	_inspector_controls.clear()

func _build_inspector_for_node(n_data: Dictionary) -> void:
	_clear_inspector()
	var nid: String = str(n_data.get("id", ""))
	var ntype: String = str(n_data.get("type", ""))
	var subtype: String = str(n_data.get("subtype", ""))
	var params: Dictionary = n_data.get("params", {}) if (n_data.get("params") is Dictionary) else {}

	inspector_node_title.text = "%s [%s] (%s)" % [n_data.get("title", ntype), subtype, nid]

	match ntype:
		"Condition":
			if subtype == "ResourceCompare":
				# Resource dropdown
				var lbl_r := Label.new()
				lbl_r.text = "Tài nguyên so sánh:"
				inspector_params_box.add_child(lbl_r)

				var opt_r := OptionButton.new()
				var resources := ["Food", "Wood", "Stone", "Ore", "Metal", "Tools", "Gold"]
				for i in range(resources.size()):
					opt_r.add_item(resources[i], i)
					if resources[i].to_lower() == str(params.get("resource", "Food")).to_lower():
						opt_r.selected = i
				opt_r.item_selected.connect(func(idx: int):
					params["resource"] = resources[idx]
					_refresh_node_label_in_graph(nid)
				)
				inspector_params_box.add_child(opt_r)

				# Operator dropdown
				var lbl_op := Label.new()
				lbl_op.text = "Toán tử so sánh:"
				inspector_params_box.add_child(lbl_op)

				var opt_op := OptionButton.new()
				var ops := ["<", "<=", ">", ">=", "=="]
				for i in range(ops.size()):
					opt_op.add_item(ops[i], i)
					if ops[i] == str(params.get("op", "<")):
						opt_op.selected = i
				opt_op.item_selected.connect(func(idx: int):
					params["op"] = ops[idx]
					_refresh_node_label_in_graph(nid)
				)
				inspector_params_box.add_child(opt_op)

				# Threshold value
				var lbl_v := Label.new()
				lbl_v.text = "Giá trị ngưỡng:"
				inspector_params_box.add_child(lbl_v)

				var spin_v := SpinBox.new()
				spin_v.min_value = 0
				spin_v.max_value = 999999
				spin_v.value = float(params.get("value", 60.0))
				spin_v.value_changed.connect(func(val: float):
					params["value"] = val
					_refresh_node_label_in_graph(nid)
				)
				inspector_params_box.add_child(spin_v)

			elif subtype == "CitizenFatigue":
				var lbl_f := Label.new()
				lbl_f.text = "Ngưỡng mệt mỏi (%):"
				inspector_params_box.add_child(lbl_f)

				var spin_f := SpinBox.new()
				spin_f.min_value = 0
				spin_f.max_value = 100
				spin_f.value = float(params.get("value", 80.0))
				spin_f.value_changed.connect(func(val: float):
					params["value"] = val
					_refresh_node_label_in_graph(nid)
				)
				inspector_params_box.add_child(spin_f)

		"Action":
			if subtype == "AssignRole":
				var roles := ["idle", "farmer", "woodcutter", "builder", "hauler", "miner", "smith", "guard"]
				# From Role
				var lbl_fr := Label.new()
				lbl_fr.text = "Từ nghề (From Role):"
				inspector_params_box.add_child(lbl_fr)

				var opt_fr := OptionButton.new()
				for i in range(roles.size()):
					opt_fr.add_item(roles[i].capitalize(), i)
					if roles[i] == str(params.get("from_role", "idle")).to_lower():
						opt_fr.selected = i
				opt_fr.item_selected.connect(func(idx: int):
					params["from_role"] = roles[idx]
					_refresh_node_label_in_graph(nid)
				)
				inspector_params_box.add_child(opt_fr)

				# To Role
				var lbl_tr := Label.new()
				lbl_tr.text = "Sang nghề (To Role):"
				inspector_params_box.add_child(lbl_tr)

				var opt_tr := OptionButton.new()
				for i in range(roles.size()):
					opt_tr.add_item(roles[i].capitalize(), i)
					if roles[i] == str(params.get("to_role", "farmer")).to_lower():
						opt_tr.selected = i
				opt_tr.item_selected.connect(func(idx: int):
					params["to_role"] = roles[idx]
					_refresh_node_label_in_graph(nid)
				)
				inspector_params_box.add_child(opt_tr)

			elif subtype == "BoostJobPriority":
				var job_types := ["farmer", "woodcutter", "builder", "hauler", "miner", "smith", "guard"]
				var lbl_jt := Label.new()
				lbl_jt.text = "Loại công việc cần tăng ưu tiên:"
				inspector_params_box.add_child(lbl_jt)

				var opt_jt := OptionButton.new()
				for i in range(job_types.size()):
					opt_jt.add_item(job_types[i].capitalize(), i)
					if job_types[i] == str(params.get("job_type", "farmer")).to_lower():
						opt_jt.selected = i
				opt_jt.item_selected.connect(func(idx: int):
					params["job_type"] = job_types[idx]
					_refresh_node_label_in_graph(nid)
				)
				inspector_params_box.add_child(opt_jt)

				var lbl_dp := Label.new()
				lbl_dp.text = "Mức thay đổi (+/-):"
				inspector_params_box.add_child(lbl_dp)

				var spin_dp := SpinBox.new()
				spin_dp.min_value = -10
				spin_dp.max_value = 10
				spin_dp.value = float(params.get("delta_priority", 1))
				spin_dp.value_changed.connect(func(val: float):
					params["delta_priority"] = int(val)
					_refresh_node_label_in_graph(nid)
				)
				inspector_params_box.add_child(spin_dp)

			elif subtype == "EmitLog":
				var lbl_m := Label.new()
				lbl_m.text = "Nội dung thông báo (Message):"
				inspector_params_box.add_child(lbl_m)

				var line_m := LineEdit.new()
				line_m.text = str(params.get("message", "Nhật ký tự động"))
				line_m.text_changed.connect(func(new_text: String):
					params["message"] = new_text
					_refresh_node_label_in_graph(nid)
				)
				inspector_params_box.add_child(line_m)

		_:
			var lbl_info := Label.new()
			lbl_info.text = "Node này không có tham số mở rộng."
			inspector_params_box.add_child(lbl_info)

func _refresh_node_label_in_graph(nid: String) -> void:
	var n_data := _find_node_data(nid)
	if n_data.is_empty():
		return
	var gn = graph_edit.get_node_or_null(nid)
	if gn and gn.get_child_count() > 0:
		var first_child = gn.get_child(0)
		if first_child is Label:
			var ntype: String = str(n_data.get("type", ""))
			if ntype == "Condition":
				first_child.text = _format_condition_label(n_data)
			elif ntype == "Action":
				first_child.text = _format_action_label(n_data)

# -----------------------------------------------------------------------------
# Validation & Dry-Run Simulation
# -----------------------------------------------------------------------------

func _on_validate_pressed() -> void:
	if current_program == null:
		label_status.text = "Chưa chọn chương trình để kiểm tra"
		label_status.modulate = Color(1.0, 0.4, 0.4)
		return

	var res := AutomationGraphValidator.validate_program(current_program)
	if res.get("valid", false):
		label_status.text = "✅ Đồ thị hợp lệ! Không phát hiện lỗi cấu trúc."
		label_status.modulate = Color(0.3, 0.9, 0.4)
		text_trace.text = "Kiểm tra cấu trúc thành công:\n- Đầy đủ Trigger khởi đầu\n- Toàn bộ node đều có kết nối hợp lệ\n- Không có chu trình lặp vô hạn\n- Nhánh IF/ELSE hợp lệ"
	else:
		label_status.text = "❌ Đồ thị có lỗi! Vui lòng sửa các điểm bên dưới."
		label_status.modulate = Color(1.0, 0.3, 0.3)
		var err_lines := "\n".join(res.get("errors", []))
		text_trace.text = "DANH SÁCH LỖI PHÁT HIỆN:\n" + err_lines

func _on_dry_run_pressed() -> void:
	if current_program == null or automation_mgr == null:
		return

	var ctx: Dictionary = {}
	if context_provider.is_valid():
		ctx = context_provider.call()

	var res := automation_mgr.run_program(current_program.id, ctx, {"dry_run": true})
	var trace: Array = res.get("trace", [])
	text_trace.text = "=== KẾT QUẢ CHẠY THỬ DRY RUN (KHÔNG THAY ĐỔI DỮ LIỆU THỰC TẾ) ===\n" + "\n".join(trace)

	if res.get("ok", false):
		label_status.text = "✅ Chạy thử thành công (%d bước)" % int(res.get("steps", 0))
		label_status.modulate = Color(0.3, 0.9, 0.4)
	else:
		label_status.text = "❌ Chạy thử dừng với lỗi: %s" % res.get("reason", "")
		label_status.modulate = Color(1.0, 0.4, 0.4)

func _on_close_pressed() -> void:
	visible = false
	editor_closed.emit()
