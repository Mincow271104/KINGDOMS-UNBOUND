class_name GridNavigation
extends RefCounted
## Grid A* Navigation System for KINGDOMS UNBOUND.
## Computes discrete paths across the 64x64 logical simulation grid.

enum NearestSearchStatus {
	FOUND = 0,
	UNREACHABLE = 1,
	BUDGET_EXHAUSTED = 2,
	INVALID_INPUT = 3,
	IN_PROGRESS = 4,
	INVALIDATED = 5,
}

class IncrementalNearestSearch extends RefCounted:
	var start: Vector2i = Vector2i(-1, -1)
	var target_predicate: Callable = Callable()
	var max_iterations: int = 4096
	var world_revision: int = 0
	var heap: Array = []
	var came_from: Dictionary = {}
	var g_score: Dictionary = {}
	var closed: Dictionary = {}
	var iterations: int = 0
	var status: int = NearestSearchStatus.IN_PROGRESS
	var path: Array[Vector2i] = []

class IncrementalAStarSearch extends RefCounted:
	var start: Vector2i = Vector2i(-1, -1)
	var goal: Vector2i = Vector2i(-1, -1)
	var actual_goal: Vector2i = Vector2i(-1, -1)
	var allowed_cell_predicate: Callable = Callable()
	var max_iterations: int = 2048
	var nav_revision: int = 0
	var heap: Array = [] # [f_score, g_score, Vector2i]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {}
	var f_score: Dictionary = {}
	var closed: Dictionary = {}
	var iterations: int = 0
	var status: int = NearestSearchStatus.IN_PROGRESS
	var path: Array[Vector2i] = []

var world_data: WorldGenerator.WorldData

func _init(p_world_data: WorldGenerator.WorldData = null) -> void:
	world_data = p_world_data

## Returns true if the cell is within bounds, non-water (and non-mountain for V2), and not occupied by solid obstacles.
func is_cell_walkable(cell: Vector2i) -> bool:
	if not IsoMath.is_in_bounds(cell):
		return false
	if world_data == null:
		return true
	var t_type: int = world_data.terrain[cell.x][cell.y]
	if t_type == WorldGenerator.TerrainType.WATER:
		return world_data.bridge_walkable_cells.has(cell)
	if world_data.generator_version == WorldGenerator.BATCH03_GENERATOR_VERSION and t_type == WorldGenerator.TerrainType.MOUNTAINS:
		return false
	if world_data.occupancy[cell.x][cell.y]:
		return false
	return true

func get_movement_cost(cell: Vector2i) -> int:
	if world_data == null or not IsoMath.is_in_bounds(cell):
		return 1
	var t_type: int = world_data.terrain[cell.x][cell.y]
	if t_type == WorldGenerator.TerrainType.MOUNTAINS:
		return 3
	if t_type == WorldGenerator.TerrainType.HILLS:
		return 2
	return 1

func is_walkable(cell: Vector2i) -> bool:
	return is_cell_walkable(cell)

## Finds the closest walkable neighbor adjacent to an occupied/unwalkable target (e.g. building).
func find_closest_walkable_adjacent(target: Vector2i, from: Vector2i) -> Vector2i:
	if is_cell_walkable(target):
		return target
		
	var best_cell := Vector2i(-1, -1)
	var best_dist := 999999
	
	var neighbors := IsoMath.get_cardinal_neighbors(target)
	for n in neighbors:
		if is_cell_walkable(n):
			var d := IsoMath.grid_distance(from, n)
			if d < best_dist:
				best_dist = d
				best_cell = n
	return best_cell

## Discrete A* Pathfinding from start to goal.
## Returns Array of Vector2i representing consecutive steps.
## If goal is unreachable, returns empty array safely without infinite looping.
func find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	return find_path_with_predicate(start, goal, Callable())

## Discrete A* Pathfinding with optional allowed_cell_predicate(cell: Vector2i) -> bool.
## Kept separate from find_path() so subclasses overriding find_path(start, goal) remain 100% compatible.
func find_path_with_predicate(start: Vector2i, goal: Vector2i, allowed_cell_predicate: Callable = Callable()) -> Array[Vector2i]:
	var has_pred := allowed_cell_predicate.is_valid()
	if has_pred and not bool(allowed_cell_predicate.call(goal)):
		return []
	if start == goal:
		return [start]
		
	# If goal is unwalkable (e.g. inside a building footprint), find adjacent accessible cell
	var actual_goal := goal
	if not is_cell_walkable(goal):
		actual_goal = find_closest_walkable_adjacent(goal, start)
		if actual_goal == Vector2i(-1, -1):
			return [] # No adjacent walkable tile
		if has_pred and not bool(allowed_cell_predicate.call(actual_goal)):
			return []
			
	if start == actual_goal:
		return [start]

	var open_set: Array[Vector2i] = [start]
	var came_from: Dictionary = {}
	
	var g_score: Dictionary = {}
	g_score[start] = 0
	
	var f_score: Dictionary = {}
	f_score[start] = IsoMath.grid_distance(start, actual_goal)
	
	var max_iterations := 2048 # Safety budget
	var iterations := 0
	
	while not open_set.is_empty():
		iterations += 1
		if iterations > max_iterations:
			return [] # Search budget exhausted, fails safely
			
		# Find node in open_set with lowest f_score
		var current := open_set[0]
		var lowest_f: int = f_score.get(current, 999999)
		var current_idx := 0
		
		for i in range(1, open_set.size()):
			var node := open_set[i]
			var f_val: int = f_score.get(node, 999999)
			if f_val < lowest_f:
				lowest_f = f_val
				current = node
				current_idx = i
				
		if current == actual_goal:
			# Reconstruct path
			var total_path: Array[Vector2i] = [current]
			while current in came_from:
				current = came_from[current]
				total_path.push_front(current)
			return total_path
			
		open_set.remove_at(current_idx)
		
		var neighbors := IsoMath.get_cardinal_neighbors(current)
		for neighbor in neighbors:
			if not is_cell_walkable(neighbor) and neighbor != actual_goal:
				continue
			if has_pred and neighbor != start and not bool(allowed_cell_predicate.call(neighbor)):
				continue
				
			var tentative_g: int = g_score[current] + get_movement_cost(neighbor)
			if tentative_g < g_score.get(neighbor, 999999):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + IsoMath.grid_distance(neighbor, actual_goal)
				
				if neighbor not in open_set:
					open_set.append(neighbor)
					
	return [] # Unreachable

## Creates a resumable incremental Dijkstra search state for `find_path_to_nearest_matching_detailed` and multi-frame schedulers.
func create_incremental_nearest_search(start: Vector2i, target_predicate: Callable, max_iterations: int = -1, world_revision: int = 0) -> IncrementalNearestSearch:
	var state := IncrementalNearestSearch.new()
	state.start = start
	state.target_predicate = target_predicate
	state.world_revision = world_revision
	if world_data == null or not target_predicate.is_valid() or not IsoMath.is_in_bounds(start):
		state.status = NearestSearchStatus.INVALID_INPUT
		return state
	if max_iterations == 0 or max_iterations < -1:
		state.status = NearestSearchStatus.INVALID_INPUT
		return state

	var default_budget: int = (world_data.map_width * world_data.map_height) if world_data != null else (WorldGenerator.MAP_SIZE * WorldGenerator.MAP_SIZE)
	state.max_iterations = default_budget if max_iterations < 0 else max_iterations

	if bool(target_predicate.call(start)) and is_cell_walkable(start):
		state.status = NearestSearchStatus.FOUND
		state.path = ([start] as Array[Vector2i])
		return state

	_heap_push(state.heap, [0, start])
	state.g_score[start] = 0
	state.status = NearestSearchStatus.IN_PROGRESS
	return state

## Advances an incremental Dijkstra search by up to `step_budget` finalized cell expansions.
## Preserves exact weighted shortest-path optimality across frames.
func step_incremental_nearest_search(state: IncrementalNearestSearch, step_budget: int) -> Dictionary:
	var empty_path: Array[Vector2i] = []
	if state == null:
		return {"status": NearestSearchStatus.INVALID_INPUT, "path": empty_path, "iterations": 0, "step_expansions": 0}
	if state.status != NearestSearchStatus.IN_PROGRESS:
		return {"status": state.status, "path": state.path, "iterations": state.iterations, "step_expansions": 0}
	if world_data == null or not state.target_predicate.is_valid():
		state.status = NearestSearchStatus.INVALID_INPUT
		return {"status": state.status, "path": empty_path, "iterations": state.iterations, "step_expansions": 0}
	if step_budget <= 0:
		return {"status": NearestSearchStatus.IN_PROGRESS, "path": empty_path, "iterations": state.iterations, "step_expansions": 0}

	var step_expansions := 0
	while not state.heap.is_empty():
		if step_expansions >= step_budget:
			return {"status": NearestSearchStatus.IN_PROGRESS, "path": empty_path, "iterations": state.iterations, "step_expansions": step_expansions}

		var top: Array = _heap_pop(state.heap)
		var cur_g: int = int(top[0])
		var current: Vector2i = top[1]
		if state.closed.has(current):
			continue
		if cur_g > int(state.g_score.get(current, 999999999)):
			continue

		if state.iterations >= state.max_iterations:
			state.status = NearestSearchStatus.BUDGET_EXHAUSTED
			return {"status": state.status, "path": empty_path, "iterations": state.iterations, "step_expansions": step_expansions}

		state.iterations += 1
		step_expansions += 1
		state.closed[current] = true

		if current != state.start and bool(state.target_predicate.call(current)) and is_cell_walkable(current):
			var total_path: Array[Vector2i] = [current]
			while state.came_from.has(current):
				current = state.came_from[current]
				total_path.push_front(current)
			state.status = NearestSearchStatus.FOUND
			state.path = total_path
			return {"status": state.status, "path": state.path, "iterations": state.iterations, "step_expansions": step_expansions}

		var neighbors := IsoMath.get_cardinal_neighbors(current)
		for neighbor in neighbors:
			if state.closed.has(neighbor) or not is_cell_walkable(neighbor):
				continue
			var tentative_g: int = cur_g + get_movement_cost(neighbor)
			if tentative_g < int(state.g_score.get(neighbor, 999999999)):
				state.came_from[neighbor] = current
				state.g_score[neighbor] = tentative_g
				_heap_push(state.heap, [tentative_g, neighbor])

	state.status = NearestSearchStatus.UNREACHABLE
	return {"status": state.status, "path": empty_path, "iterations": state.iterations, "step_expansions": step_expansions}

## Creates a resumable incremental point-to-point A* search state for bounded schedulers.
func create_incremental_astar_search(
	start: Vector2i,
	goal: Vector2i,
	allowed_cell_predicate: Callable = Callable(),
	max_iterations: int = 2048,
	nav_revision: int = 0
) -> IncrementalAStarSearch:
	var state := IncrementalAStarSearch.new()
	state.start = start
	state.goal = goal
	state.allowed_cell_predicate = allowed_cell_predicate
	state.nav_revision = nav_revision
	state.max_iterations = maxi(1, max_iterations)

	if not IsoMath.is_in_bounds(start) or not IsoMath.is_in_bounds(goal):
		state.status = NearestSearchStatus.INVALID_INPUT
		return state

	var has_pred := allowed_cell_predicate.is_valid()
	var actual_goal := goal
	if not is_cell_walkable(goal) or (has_pred and not bool(allowed_cell_predicate.call(goal))):
		actual_goal = find_closest_walkable_adjacent(goal, start)
		if actual_goal == Vector2i(-1, -1):
			state.status = NearestSearchStatus.UNREACHABLE
			return state
		if has_pred and not bool(allowed_cell_predicate.call(actual_goal)):
			state.status = NearestSearchStatus.UNREACHABLE
			return state

	state.actual_goal = actual_goal
	if start == actual_goal:
		state.status = NearestSearchStatus.FOUND
		state.path = ([start] as Array[Vector2i])
		return state

	var h0: int = IsoMath.grid_distance(start, actual_goal)
	state.g_score[start] = 0
	state.f_score[start] = h0
	_heap_push(state.heap, [h0, 0, start])
	state.status = NearestSearchStatus.IN_PROGRESS
	return state

## Advances an incremental A* search by up to `step_budget` node expansions.
## Preserves frontier state across frames and never exceeds `step_budget`.
func step_incremental_astar_search(state: IncrementalAStarSearch, step_budget: int) -> Dictionary:
	var empty_path: Array[Vector2i] = []
	if state == null:
		return {"status": NearestSearchStatus.INVALID_INPUT, "path": empty_path, "iterations": 0, "step_expansions": 0}
	if state.status != NearestSearchStatus.IN_PROGRESS:
		return {"status": state.status, "path": state.path, "iterations": state.iterations, "step_expansions": 0}
	if step_budget <= 0:
		return {"status": NearestSearchStatus.IN_PROGRESS, "path": empty_path, "iterations": state.iterations, "step_expansions": 0}

	var has_pred := state.allowed_cell_predicate.is_valid()
	var step_expansions := 0
	while not state.heap.is_empty():
		if step_expansions >= step_budget:
			return {"status": NearestSearchStatus.IN_PROGRESS, "path": empty_path, "iterations": state.iterations, "step_expansions": step_expansions}

		var top: Array = _heap_pop(state.heap)
		var current: Vector2i = top[2]
		if state.closed.has(current):
			continue
		if int(top[1]) > int(state.g_score.get(current, 999999999)):
			continue

		if state.iterations >= state.max_iterations:
			state.status = NearestSearchStatus.BUDGET_EXHAUSTED
			return {"status": state.status, "path": empty_path, "iterations": state.iterations, "step_expansions": step_expansions}

		state.iterations += 1
		step_expansions += 1
		state.closed[current] = true

		if current == state.actual_goal:
			var total_path: Array[Vector2i] = [current]
			while state.came_from.has(current):
				current = state.came_from[current]
				total_path.push_front(current)
			state.status = NearestSearchStatus.FOUND
			state.path = total_path
			return {"status": state.status, "path": state.path, "iterations": state.iterations, "step_expansions": step_expansions}

		var cur_g: int = int(state.g_score.get(current, 0))
		var neighbors := IsoMath.get_cardinal_neighbors(current)
		for neighbor in neighbors:
			if state.closed.has(neighbor):
				continue
			if not is_cell_walkable(neighbor) and neighbor != state.actual_goal:
				continue
			if has_pred and neighbor != state.start and not bool(state.allowed_cell_predicate.call(neighbor)):
				continue

			var tentative_g: int = cur_g + get_movement_cost(neighbor)
			if tentative_g < int(state.g_score.get(neighbor, 999999999)):
				state.came_from[neighbor] = current
				state.g_score[neighbor] = tentative_g
				var f_val: int = tentative_g + IsoMath.grid_distance(neighbor, state.actual_goal)
				state.f_score[neighbor] = f_val
				_heap_push(state.heap, [f_val, tentative_g, neighbor])

	state.status = NearestSearchStatus.UNREACHABLE
	return {"status": state.status, "path": empty_path, "iterations": state.iterations, "step_expansions": step_expansions}

## Dijkstra shortest-cost path from `start` to the nearest walkable cell satisfying `target_predicate(cell) -> bool`.
## Returns `{"status": NearestSearchStatus, "path": Array[Vector2i], "iterations": int}`.
## Default `max_iterations = -1` expands up to `WorldGenerator.MAP_SIZE * WorldGenerator.MAP_SIZE` (4096) cells.
func find_path_to_nearest_matching_detailed(start: Vector2i, target_predicate: Callable, max_iterations: int = -1) -> Dictionary:
	var state := create_incremental_nearest_search(start, target_predicate, max_iterations)
	if state.status != NearestSearchStatus.IN_PROGRESS:
		return {"status": state.status, "path": state.path, "iterations": state.iterations}
	var res := step_incremental_nearest_search(state, state.max_iterations + 1)
	return {"status": int(res.get("status", NearestSearchStatus.UNREACHABLE)), "path": res.get("path", []), "iterations": int(res.get("iterations", 0))}

## Backwards-compatible wrapper returning the path array or `[]` if not found.
func find_path_to_nearest_matching(start: Vector2i, target_predicate: Callable, max_iterations: int = -1) -> Array[Vector2i]:
	var res := find_path_to_nearest_matching_detailed(start, target_predicate, max_iterations)
	if int(res.get("status", NearestSearchStatus.UNREACHABLE)) == NearestSearchStatus.FOUND:
		return res.get("path", [])
	return []

func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var idx := heap.size() - 1
	while idx > 0:
		var parent := (idx - 1) >> 1
		if int(heap[idx][0]) < int(heap[parent][0]):
			var tmp = heap[parent]
			heap[parent] = heap[idx]
			heap[idx] = tmp
			idx = parent
		else:
			break

func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var n := heap.size()
		var idx := 0
		while true:
			var left := (idx << 1) + 1
			if left >= n:
				break
			var right := left + 1
			var smallest := left
			if right < n and int(heap[right][0]) < int(heap[left][0]):
				smallest = right
			if int(heap[smallest][0]) < int(heap[idx][0]):
				var tmp = heap[idx]
				heap[idx] = heap[smallest]
				heap[smallest] = tmp
				idx = smallest
			else:
				break
	return top
