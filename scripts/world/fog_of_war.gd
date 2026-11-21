class_name FogOfWar
extends RefCounted
## 3-State Fog of War Simulation Grid for KINGDOMS UNBOUND.
## Conforms to GDD Section 3.4:
## 0: Unexplored (Chưa khám phá)
## 1: Explored (Đã khám phá nhưng hiện không quan sát)
## 2: Visible (Đang được quan sát trực tiếp)

enum State {
	UNEXPLORED = 0,
	EXPLORED = 1,
	VISIBLE = 2
}

# Standardized vision radii across entities & structures (GDD §3.4, Package 3B)
const OUTPOST_VISION_RADIUS: int = 6
const ARMY_UNIT_VISION_RADIUS: int = 4
const CITIZEN_VISION_RADIUS: int = 4
const WATCHTOWER_VISION_RADIUS: int = 15
const TOWN_HALL_VISION_RADIUS: int = 10

var map_size: int = 64
var map_width: int = 64
var map_height: int = 64
var _grid: Array = [] # 2D array [x][y] storing State
var _prev_visible_cells: Array[Vector2i] = []

func _init(width: int = 64, height: int = -1) -> void:
	map_width = maxi(1, width)
	map_height = map_width if height <= 0 else maxi(1, height)
	map_size = maxi(map_width, map_height)
	reset_fog()

func reset_fog() -> void:
	_grid.clear()
	_prev_visible_cells.clear()
	for x in range(map_width):
		var col: Array[int] = []
		for y in range(map_height):
			col.append(State.UNEXPLORED)
		_grid.append(col)

func get_state(cell: Vector2i) -> int:
	if not IsoMath.is_in_bounds(cell, map_width, map_height):
		return State.UNEXPLORED
	return _grid[cell.x][cell.y]

func set_state(cell: Vector2i, new_state: int) -> void:
	if IsoMath.is_in_bounds(cell, map_width, map_height):
		if new_state == State.VISIBLE and _grid[cell.x][cell.y] != State.VISIBLE:
			_prev_visible_cells.append(cell)
		_grid[cell.x][cell.y] = new_state

func is_unexplored(cell: Vector2i) -> bool:
	return get_state(cell) == State.UNEXPLORED

func is_explored(cell: Vector2i) -> bool:
	var s: int = get_state(cell)
	return s == State.EXPLORED or s == State.VISIBLE

func is_visible(cell: Vector2i) -> bool:
	return get_state(cell) == State.VISIBLE

## Reveals a circular diamond area around a center point
func reveal_circle(center: Vector2i, radius: int) -> int:
	var newly_revealed := 0
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var dist := absi(dx) + absi(dy)
			if dist <= radius:
				var cell := center + Vector2i(dx, dy)
				if IsoMath.is_in_bounds(cell, map_width, map_height):
					if _grid[cell.x][cell.y] == State.UNEXPLORED:
						newly_revealed += 1
					if _grid[cell.x][cell.y] != State.VISIBLE:
						_prev_visible_cells.append(cell)
					_grid[cell.x][cell.y] = State.VISIBLE
	return newly_revealed

## Updates vision from an array of observer positions (citizens, buildings, units, outposts).
## Supports Vector2i, objects with current_cell, or Dictionary {"cell": Vector2i, "radius": int}.
## Previously visible cells degrade to EXPLORED; cells in active range become VISIBLE.
func update_observers(observer_cells: Array, sight_radius: int = 4) -> int:
	# Step 1: Degrade current VISIBLE to EXPLORED
	for x in range(map_width):
		for y in range(map_height):
			if _grid[x][y] == State.VISIBLE:
				_grid[x][y] = State.EXPLORED
				
	# Step 2: Mark cells within sight radius of any active observer as VISIBLE
	var total_visible := 0
	for obs in observer_cells:
		var c: Vector2i = Vector2i.ZERO
		var r: int = sight_radius
		if obs is Vector2i:
			c = obs
		elif obs is Dictionary:
			if obs.has("cell") and obs["cell"] is Vector2i:
				c = obs["cell"]
			elif obs.has("current_cell") and obs["current_cell"] is Vector2i:
				c = obs["current_cell"]
			r = int(obs.get("radius", obs.get("vision_radius", sight_radius)))
		elif obs is Object and is_instance_valid(obs):
			var obj_c = obs.get("current_cell")
			if obj_c is Vector2i:
				c = obj_c
			if obs.get("vision_radius") != null:
				r = int(obs.get("vision_radius"))
		total_visible += reveal_circle(c, r)
	rebuild_visible_cache()
	return total_visible

## Recomputes the union of owned_cells and active observer_specs in O(visible + newly_revealed)
## and returns only the cells whose FogOfWar.State changed since the previous pass.
func recompute_vision(owned_cells: Array[Vector2i], observer_specs: Array) -> Array[Vector2i]:
	var old_states: Dictionary = {}
	for prev_c in _prev_visible_cells:
		if IsoMath.is_in_bounds(prev_c, map_width, map_height):
			old_states[prev_c] = _grid[prev_c.x][prev_c.y]
			if _grid[prev_c.x][prev_c.y] == State.VISIBLE:
				_grid[prev_c.x][prev_c.y] = State.EXPLORED

	var new_visible_set: Dictionary = {}
	var new_visible_list: Array[Vector2i] = []

	for oc in owned_cells:
		if IsoMath.is_in_bounds(oc, map_width, map_height):
			if not old_states.has(oc):
				old_states[oc] = _grid[oc.x][oc.y]
			_grid[oc.x][oc.y] = State.VISIBLE
			if not new_visible_set.has(oc):
				new_visible_set[oc] = true
				new_visible_list.append(oc)

	for obs in observer_specs:
		var center: Vector2i = Vector2i.ZERO
		var rad: int = 4
		if obs is Dictionary:
			center = obs.get("cell", Vector2i.ZERO)
			rad = int(obs.get("radius", 4))
		elif obs is Vector2i:
			center = obs
		for dx in range(-rad, rad + 1):
			for dy in range(-rad, rad + 1):
				if absi(dx) + absi(dy) > rad:
					continue
				var cell := center + Vector2i(dx, dy)
				if IsoMath.is_in_bounds(cell, map_width, map_height):
					if not old_states.has(cell):
						old_states[cell] = _grid[cell.x][cell.y]
					_grid[cell.x][cell.y] = State.VISIBLE
					if not new_visible_set.has(cell):
						new_visible_set[cell] = true
						new_visible_list.append(cell)

	_prev_visible_cells = new_visible_list
	var dirty_cells: Array[Vector2i] = []
	for cell in old_states.keys():
		if _grid[cell.x][cell.y] != int(old_states[cell]):
			dirty_cells.append(cell)
	return dirty_cells

func rebuild_visible_cache() -> void:
	_prev_visible_cells.clear()
	for x in range(map_width):
		for y in range(map_height):
			if _grid[x][y] == State.VISIBLE:
				_prev_visible_cells.append(Vector2i(x, y))

func get_explored_ratio() -> float:
	var explored_count := 0
	var total_cells := maxi(1, map_width * map_height)
	for x in range(map_width):
		for y in range(map_height):
			if _grid[x][y] != State.UNEXPLORED:
				explored_count += 1
	return float(explored_count) / float(total_cells)
