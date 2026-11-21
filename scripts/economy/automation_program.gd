class_name AutomationProgram
extends RefCounted
## Data Model for Automation Graph Programs in KINGDOMS UNBOUND.
## Conforms to HTML Stage 11 reference and Package 1V specification.

var id: String = ""
var name: String = "Chương trình Mới"
var enabled: bool = false
var priority: int = 5
var cooldown_sec: float = 1.0
var last_run_time: float = -999.0
var nodes: Array[Dictionary] = []
var edges: Array[Dictionary] = []

func _init(p_id: String = "", p_name: String = "Chương trình Mới", p_prio: int = 5) -> void:
	id = p_id
	name = p_name
	priority = p_prio
	enabled = false
	cooldown_sec = 1.0
	last_run_time = -999.0
	nodes = []
	edges = []

func serialize() -> Dictionary:
	var nodes_copy: Array = []
	for n in nodes:
		nodes_copy.append(n.duplicate(true))
	var edges_copy: Array = []
	for e in edges:
		edges_copy.append(e.duplicate(true))
	return {
		"id": id,
		"name": name,
		"enabled": enabled,
		"priority": priority,
		"cooldown_sec": cooldown_sec,
		"last_run_time": last_run_time,
		"nodes": nodes_copy,
		"edges": edges_copy
	}

static func deserialize(data: Dictionary) -> AutomationProgram:
	var prog := AutomationProgram.new()
	prog.id = str(data.get("id", ""))
	prog.name = str(data.get("name", "Chương trình Mới"))
	prog.enabled = bool(data.get("enabled", false))
	prog.priority = int(data.get("priority", 5))
	prog.cooldown_sec = float(data.get("cooldown_sec", 1.0))
	prog.last_run_time = float(data.get("last_run_time", -999.0))
	
	var raw_nodes = data.get("nodes", [])
	if raw_nodes is Array:
		for n in raw_nodes:
			if n is Dictionary:
				prog.nodes.append(n.duplicate(true))
				
	var raw_edges = data.get("edges", [])
	if raw_edges is Array:
		for e in raw_edges:
			if e is Dictionary:
				prog.edges.append(e.duplicate(true))
	return prog
