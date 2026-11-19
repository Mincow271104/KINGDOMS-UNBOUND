class_name NaturalResourceManager
extends RefCounted
## Canonical Manager for Phase 5 Harvestable Natural Resource Nodes.
## Single source of truth referencing WorldData.props entries directly.

signal node_harvested(node_id: String, resource: String, amount: int, remaining_qty: int)
signal node_depleted(node_id: String, prop_type: String, cell: Vector2i)

var nodes_by_id: Dictionary = {}       # String -> Dictionary (ref to WorldData.props entry)
var nodes_by_cell: Dictionary = {}     # Vector2i -> Dictionary
var reserved_by: Dictionary = {}       # node_id (String) -> worker_id (String)
var depleted_deltas: Dictionary = {}   # node_id (String) -> true
var modified_deltas: Dictionary = {}   # node_id (String) -> int (remaining_qty)

func clear_all() -> void:
	nodes_by_id.clear()
	nodes_by_cell.clear()
	reserved_by.clear()
	depleted_deltas.clear()
	modified_deltas.clear()

func sync_from_world_data(world_data: WorldGenerator.WorldData) -> void:
	nodes_by_id.clear()
	nodes_by_cell.clear()
	reserved_by.clear()
	if world_data == null or world_data.props == null:
		return
	for p in world_data.props:
		if not (p is Dictionary):
			continue
		var p_type: String = str(p.get("type", ""))
		if not EconomyConfig.is_natural_resource_type(p_type):
			continue
		var cell: Vector2i = p.get("cell", Vector2i(-1, -1))
		var nid: String = str(p.get("id", ""))
		if nid == "":
			nid = WorldGenerator.make_resource_node_id(world_data.seed_value, world_data.generator_version, p_type, cell)
			p["id"] = nid
		if not p.has("max_qty"):
			var spec := EconomyConfig.get_natural_resource_spec(p_type)
			p["max_qty"] = int(spec.get("max_qty", 20))
			p["remaining_qty"] = int(p.get("remaining_qty", p["max_qty"]))
			p["resource"] = str(spec.get("resource", ""))
			p["depleted"] = false
		if bool(p.get("depleted", false)) or int(p.get("remaining_qty", 0)) <= 0:
			continue
		nodes_by_id[nid] = p
		nodes_by_cell[cell] = p

func get_node_by_id(node_id: String) -> Dictionary:
	return nodes_by_id.get(node_id, {})

func get_node_at_cell(cell: Vector2i) -> Dictionary:
	return nodes_by_cell.get(cell, {})

func is_node_reserved(node_id: String) -> bool:
	return reserved_by.has(node_id)

func reserve_node(node_id: String, worker_id: String) -> bool:
	if node_id == "" or worker_id == "":
		return false
	var node: Dictionary = nodes_by_id.get(node_id, {})
	if node.is_empty() or bool(node.get("depleted", false)) or int(node.get("remaining_qty", 0)) <= 0:
		return false
	if reserved_by.has(node_id) and str(reserved_by[node_id]) != worker_id:
		return false
	reserved_by[node_id] = worker_id
	return true

func release_node(node_id: String, worker_id: String = "") -> void:
	if not reserved_by.has(node_id):
		return
	if worker_id == "" or str(reserved_by[node_id]) == worker_id:
		reserved_by.erase(node_id)

func release_all_for_worker(worker_id: String) -> void:
	if worker_id == "":
		return
	var to_erase: Array[String] = []
	for nid in reserved_by:
		if str(reserved_by[nid]) == worker_id:
			to_erase.append(nid)
	for nid in to_erase:
		reserved_by.erase(nid)

func find_work_cell(node_cell: Vector2i, from_cell: Vector2i, world_data: WorldGenerator.WorldData, territory_mgr: Object, nav: GridNavigation) -> Vector2i:
	if world_data == null or nav == null:
		return Vector2i(-1, -1)
	var best_cell := Vector2i(-1, -1)
	var best_dist: int = 999999
	for offset in [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)
	]:
		var cand: Vector2i = node_cell + offset
		if not world_data.is_in_bounds(cand):
			continue
		if not nav.is_cell_walkable(cand):
			continue
		if territory_mgr != null and territory_mgr.has_method("is_cell_owned") and not bool(territory_mgr.call("is_cell_owned", cand)):
			continue
		var d: int = IsoMath.grid_distance(from_cell, cand)
		if d < best_dist:
			best_dist = d
			best_cell = cand
	return best_cell

func find_and_reserve_nearest_node(
	role: String,
	from_cell: Vector2i,
	world_data: WorldGenerator.WorldData,
	territory_mgr: Object,
	nav: GridNavigation,
	worker_id: String,
	path_cb: Callable = Callable()
) -> Dictionary:
	if world_data == null or nav == null or worker_id == "":
		return {}
	var candidates: Array[Dictionary] = []
	for nid in nodes_by_id:
		var node: Dictionary = nodes_by_id[nid]
		if bool(node.get("depleted", false)) or int(node.get("remaining_qty", 0)) <= 0:
			continue
		if reserved_by.has(nid) and str(reserved_by[nid]) != worker_id:
			continue
		var p_type: String = str(node.get("type", ""))
		var spec := EconomyConfig.get_natural_resource_spec(p_type)
		if spec.is_empty() or str(spec.get("required_role", "")) != role:
			continue
		var cell: Vector2i = node.get("cell", Vector2i(-1, -1))
		if territory_mgr != null and territory_mgr.has_method("is_cell_owned") and not bool(territory_mgr.call("is_cell_owned", cell)):
			continue
		var dist: int = IsoMath.grid_distance(from_cell, cell)
		candidates.append({"node": node, "dist": dist})

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["dist"]) < int(b["dist"])
	)

	for cand in candidates:
		var node: Dictionary = cand["node"]
		var cell: Vector2i = node["cell"]
		var work_cell := find_work_cell(cell, from_cell, world_data, territory_mgr, nav)
		if work_cell == Vector2i(-1, -1):
			continue
		var path: Array[Vector2i] = []
		if path_cb.is_valid():
			path = path_cb.call(from_cell, work_cell)
		else:
			path = nav.find_path(from_cell, work_cell)
		if path.is_empty():
			continue
		if reserve_node(str(node["id"]), worker_id):
			return {"node": node, "work_cell": work_cell, "path": path}
	return {}

func harvest_node(node_id: String, worker_id: String, max_amount: int, world_data: WorldGenerator.WorldData) -> Dictionary:
	var node: Dictionary = nodes_by_id.get(node_id, {})
	if node.is_empty():
		return {"harvested": 0, "resource": "", "depleted": true}
	if reserved_by.has(node_id) and str(reserved_by[node_id]) != worker_id:
		return {"harvested": 0, "resource": "", "depleted": false}
	var rem: int = int(node.get("remaining_qty", 0))
	if rem <= 0 or bool(node.get("depleted", false)):
		return {"harvested": 0, "resource": str(node.get("resource", "")), "depleted": true}

	var p_type: String = str(node.get("type", ""))
	var spec := EconomyConfig.get_natural_resource_spec(p_type)
	var yield_amt: int = int(spec.get("yield_per_cycle", 2))
	var take: int = mini(mini(yield_amt, maxi(0, max_amount)), rem)
	if take <= 0:
		return {"harvested": 0, "resource": str(node.get("resource", "")), "depleted": false}

	rem -= take
	node["remaining_qty"] = maxi(0, rem)
	modified_deltas[node_id] = int(node["remaining_qty"])
	var res_id: String = str(node.get("resource", ""))
	var is_depleted: bool = (int(node["remaining_qty"]) <= 0)

	if is_depleted:
		node["depleted"] = true
		depleted_deltas[node_id] = true
		modified_deltas.erase(node_id)
		reserved_by.erase(node_id)
		var cell: Vector2i = node.get("cell", Vector2i(-1, -1))
		nodes_by_id.erase(node_id)
		nodes_by_cell.erase(cell)
		if world_data != null:
			if world_data.is_in_bounds(cell):
				world_data.occupancy[cell.x][cell.y] = false
			for i in range(world_data.props.size() - 1, -1, -1):
				if str(world_data.props[i].get("id", "")) == node_id:
					world_data.props.remove_at(i)
					break
		node_depleted.emit(node_id, p_type, cell)

	node_harvested.emit(node_id, res_id, take, int(node.get("remaining_qty", 0)))
	return {"harvested": take, "resource": res_id, "depleted": is_depleted}

func serialize() -> Dictionary:
	var dep_list: Array[String] = []
	for nid in depleted_deltas:
		dep_list.append(str(nid))
	dep_list.sort()
	var mod_dict: Dictionary = {}
	for nid in modified_deltas:
		mod_dict[str(nid)] = int(modified_deltas[nid])
	return {
		"depleted_ids": dep_list,
		"modified_qty": mod_dict
	}

func apply_deltas_to_world_data(world_data: WorldGenerator.WorldData, data: Dictionary) -> void:
	clear_all()
	if data is Dictionary:
		var dep_arr: Variant = data.get("depleted_ids", [])
		if dep_arr is Array:
			for nid in dep_arr:
				depleted_deltas[str(nid)] = true
		var mod_raw: Variant = data.get("modified_qty", {})
		if mod_raw is Dictionary:
			for nid in mod_raw:
				modified_deltas[str(nid)] = maxi(0, int(mod_raw[nid]))

	if world_data != null and world_data.props != null:
		for i in range(world_data.props.size() - 1, -1, -1):
			var p: Dictionary = world_data.props[i]
			var p_type: String = str(p.get("type", ""))
			if not EconomyConfig.is_natural_resource_type(p_type):
				continue
			var cell: Vector2i = p.get("cell", Vector2i(-1, -1))
			var nid: String = str(p.get("id", WorldGenerator.make_resource_node_id(world_data.seed_value, world_data.generator_version, p_type, cell)))
			p["id"] = nid
			if depleted_deltas.has(nid):
				if world_data.is_in_bounds(cell):
					world_data.occupancy[cell.x][cell.y] = false
				world_data.props.remove_at(i)
			elif modified_deltas.has(nid):
				var qty: int = int(modified_deltas[nid])
				p["remaining_qty"] = qty
				if qty <= 0:
					depleted_deltas[nid] = true
					modified_deltas.erase(nid)
					if world_data.is_in_bounds(cell):
						world_data.occupancy[cell.x][cell.y] = false
					world_data.props.remove_at(i)

	sync_from_world_data(world_data)
