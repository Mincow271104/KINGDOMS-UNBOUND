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
var _grid: Array = [] # 2D array [x][y] storing State

func _init(size: int = 64) -> void:
	map_size = size
	reset_fog()

func reset_fog() -> void:
	_grid.clear()
	for x in range(map_size):
		var col: Array[int] = []
		for y in range(map_size):
			col.append(State.UNEXPLORED)
		_grid.append(col)

func get_state(cell: Vector2i) -> int:
	if not IsoMath.is_in_bounds(cell):
		return State.UNEXPLORED
	return _grid[cell.x][cell.y]

func set_state(cell: Vector2i, new_state: int) -> void:
	if IsoMath.is_in_bounds(cell):
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
				if IsoMath.is_in_bounds(cell):
					if _grid[cell.x][cell.y] == State.UNEXPLORED:
						newly_revealed += 1
					_grid[cell.x][cell.y] = State.VISIBLE
	return newly_revealed

## Updates vision from an array of observer positions (citizens, buildings, units, outposts).
## Supports Vector2i, objects with current_cell, or Dictionary {"cell": Vector2i, "radius": int}.
## Previously visible cells degrade to EXPLORED; cells in active range become VISIBLE.
func update_observers(observer_cells: Array, sight_radius: int = 4) -> int:
	# Step 1: Degrade current VISIBLE to EXPLORED
	for x in range(map_size):
		for y in range(map_size):
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
		
	return total_visible

func get_explored_ratio() -> float:
	var explored_count := 0
	var total_cells := map_size * map_size
	for x in range(map_size):
		for y in range(map_size):
			if _grid[x][y] != State.UNEXPLORED:
				explored_count += 1
	return float(explored_count) / float(total_cells)
