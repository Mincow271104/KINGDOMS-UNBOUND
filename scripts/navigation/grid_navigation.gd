class_name GridNavigation
extends RefCounted
## Grid A* Navigation System for KINGDOMS UNBOUND.
## Computes discrete paths across the 64x64 logical simulation grid.

var world_data: WorldGenerator.WorldData

func _init(p_world_data: WorldGenerator.WorldData = null) -> void:
	world_data = p_world_data

## Returns true if the cell is within bounds, non-water, and not occupied by solid obstacles.
func is_cell_walkable(cell: Vector2i) -> bool:
	if not IsoMath.is_in_bounds(cell):
		return false
	if world_data == null:
		return true
	if world_data.terrain[cell.x][cell.y] == WorldGenerator.TerrainType.WATER:
		return false
	if world_data.occupancy[cell.x][cell.y]:
		return false
	return true

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
	if start == goal:
		return [start]
		
	# If goal is unwalkable (e.g. inside a building footprint), find adjacent accessible cell
	var actual_goal := goal
	if not is_cell_walkable(goal):
		actual_goal = find_closest_walkable_adjacent(goal, start)
		if actual_goal == Vector2i(-1, -1):
			return [] # No adjacent walkable tile
			
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
				
			var tentative_g: int = g_score[current] + 1
			if tentative_g < g_score.get(neighbor, 999999):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + IsoMath.grid_distance(neighbor, actual_goal)
				
				if neighbor not in open_set:
					open_set.append(neighbor)
					
	return [] # Unreachable
