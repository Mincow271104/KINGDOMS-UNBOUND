class_name SettlementData
extends RefCounted
## Pure data model for a physical rival/neutral settlement in KINGDOMS UNBOUND (C1.10).
## Kept strictly separate from player-owned `WorldData.buildings` and `buildings_by_cell`.

const LAYOUT_VERSION: int = 1

const ROLE_CAPITAL: String = "capital"
const ROLE_VILLAGE: String = "village"
const ROLE_OUTPOST: String = "outpost"

const STATUS_ACTIVE: String = "active"
const STATUS_CAPTURED: String = "captured"
const STATUS_ABANDONED: String = "abandoned"
const STATUS_DESTROYED: String = "destroyed"

var settlement_id: String = ""
var origin_faction_id: String = ""
var owner_faction_id: String = ""
var role: String = ROLE_CAPITAL
var status: String = STATUS_ACTIVE
var anchor_cell: Vector2i = Vector2i(-1, -1)
var layout_version: int = LAYOUT_VERSION
var layout_tier: String = "full" # "full" | "compact"
var buildings: Array[Dictionary] = [] # [{id, type, cell, size, role, blocking}]
var roads: Array[Vector2i] = []
var decorations: Array[Dictionary] = [] # [{type, cell, variant, faction_id}]
var linked_objective_id: String = ""

func _init(
	p_id: String = "",
	p_origin_faction_id: String = "",
	p_owner_faction_id: String = "",
	p_role: String = ROLE_CAPITAL,
	p_anchor: Vector2i = Vector2i(-1, -1),
	p_linked_objective_id: String = ""
) -> void:
	settlement_id = p_id
	origin_faction_id = p_origin_faction_id
	owner_faction_id = p_owner_faction_id if not p_owner_faction_id.is_empty() else p_origin_faction_id
	role = p_role
	anchor_cell = p_anchor
	linked_objective_id = p_linked_objective_id

func get_building_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for b in buildings:
		var origin: Vector2i = b.get("cell", Vector2i.ZERO)
		var b_size: Vector2i = b.get("size", Vector2i.ONE)
		for ox in range(b_size.x):
			for oy in range(b_size.y):
				cells.append(origin + Vector2i(ox, oy))
	return cells

func get_bounds() -> Rect2i:
	var has_any := false
	var min_x: int = 999999
	var min_y: int = 999999
	var max_x: int = -999999
	var max_y: int = -999999
	for c in get_building_cells():
		has_any = true
		min_x = mini(min_x, c.x)
		min_y = mini(min_y, c.y)
		max_x = maxi(max_x, c.x)
		max_y = maxi(max_y, c.y)
	for r in roads:
		has_any = true
		min_x = mini(min_x, r.x)
		min_y = mini(min_y, r.y)
		max_x = maxi(max_x, r.x)
		max_y = maxi(max_y, r.y)
	if not has_any:
		if anchor_cell.x >= 0 and anchor_cell.y >= 0:
			return Rect2i(anchor_cell, Vector2i.ONE)
		return Rect2i()
	return Rect2i(Vector2i(min_x, min_y), Vector2i(max_x - min_x + 1, max_y - min_y + 1))

func serialize() -> Dictionary:
	var b_arr: Array[Dictionary] = []
	for b in buildings:
		var bc: Vector2i = b.get("cell", Vector2i.ZERO)
		var bs: Vector2i = b.get("size", Vector2i.ONE)
		b_arr.append({
			"id": str(b.get("id", "")),
			"type": str(b.get("type", "")),
			"cell": {"x": bc.x, "y": bc.y},
			"size": {"x": bs.x, "y": bs.y},
			"role": str(b.get("role", "")),
			"blocking": bool(b.get("blocking", true))
		})

	var r_arr: Array[Dictionary] = []
	for r in roads:
		r_arr.append({"x": r.x, "y": r.y})

	var d_arr: Array[Dictionary] = []
	for dec in decorations:
		var dc: Vector2i = dec.get("cell", Vector2i.ZERO)
		d_arr.append({
			"type": str(dec.get("type", "")),
			"cell": {"x": dc.x, "y": dc.y},
			"variant": str(dec.get("variant", "")),
			"faction_id": str(dec.get("faction_id", ""))
		})

	return {
		"settlement_id": settlement_id,
		"origin_faction_id": origin_faction_id,
		"owner_faction_id": owner_faction_id,
		"role": role,
		"status": status,
		"anchor_cell": {"x": anchor_cell.x, "y": anchor_cell.y},
		"layout_version": layout_version,
		"layout_tier": layout_tier,
		"buildings": b_arr,
		"roads": r_arr,
		"decorations": d_arr,
		"linked_objective_id": linked_objective_id
	}

static func _parse_vec2i(val: Variant, fallback: Vector2i = Vector2i.ZERO) -> Vector2i:
	if val is Vector2i:
		return val
	if val is Dictionary:
		return Vector2i(int(val.get("x", fallback.x)), int(val.get("y", fallback.y)))
	if val is Array and val.size() >= 2:
		return Vector2i(int(val[0]), int(val[1]))
	return fallback

static func deserialize(data: Dictionary) -> RefCounted:
	if data.is_empty():
		return null
	var sid: String = str(data.get("settlement_id", ""))
	var origin_fid: String = str(data.get("origin_faction_id", ""))
	if sid.is_empty() or origin_fid.is_empty():
		return null

	var owner_fid: String = str(data.get("owner_faction_id", origin_fid))
	if owner_fid.is_empty():
		owner_fid = origin_fid

	var stl = new(
		sid,
		origin_fid,
		owner_fid,
		str(data.get("role", ROLE_CAPITAL)),
		_parse_vec2i(data.get("anchor_cell", null), Vector2i(-1, -1)),
		str(data.get("linked_objective_id", ""))
	)
	stl.status = str(data.get("status", STATUS_ACTIVE))
	stl.layout_version = int(data.get("layout_version", LAYOUT_VERSION))
	stl.layout_tier = str(data.get("layout_tier", "full"))

	var raw_buildings = data.get("buildings", [])
	if raw_buildings is Array:
		for b in raw_buildings:
			if not (b is Dictionary):
				continue
			stl.buildings.append({
				"id": str(b.get("id", "")),
				"type": str(b.get("type", "")),
				"cell": _parse_vec2i(b.get("cell", null), Vector2i.ZERO),
				"size": _parse_vec2i(b.get("size", null), Vector2i.ONE),
				"role": str(b.get("role", "")),
				"blocking": bool(b.get("blocking", true))
			})

	var raw_roads = data.get("roads", [])
	if raw_roads is Array:
		for r in raw_roads:
			stl.roads.append(_parse_vec2i(r, Vector2i.ZERO))

	var raw_decs = data.get("decorations", [])
	if raw_decs is Array:
		for dec in raw_decs:
			if not (dec is Dictionary):
				continue
			stl.decorations.append({
				"type": str(dec.get("type", "")),
				"cell": _parse_vec2i(dec.get("cell", null), Vector2i.ZERO),
				"variant": str(dec.get("variant", "")),
				"faction_id": str(dec.get("faction_id", ""))
			})

	return stl
