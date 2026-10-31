class_name IsoMath
extends RefCounted
## Mathematical conversion utility for 2D dimetric (2:1 isometric) projection.
## Strictly decouples 64x64 discrete grid cells from local pixel coordinates.

const TILE_WIDTH: float = 32.0
const TILE_HEIGHT: float = 16.0
const HALF_WIDTH: float = 16.0
const HALF_HEIGHT: float = 8.0
const MAP_SIZE: int = 64

## Converts a discrete integer grid coordinate (gx, gy) to continuous map-local pixel space.
## The resulting Vector2 represents the bottom-center ground contact vertex of the cell diamond.
static func map_to_local(grid_pos: Vector2i) -> Vector2:
	var lx: float = (float(grid_pos.x) - float(grid_pos.y)) * HALF_WIDTH
	var ly: float = (float(grid_pos.x) + float(grid_pos.y)) * HALF_HEIGHT
	return Vector2(lx, ly)

## Alias for map_to_local conforming to standard world projection nomenclature.
static func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return map_to_local(grid_pos)

## Converts continuous map-local pixel space (lx, ly) to discrete integer grid coordinate (gx, gy).
## Uses exact half-tile continuous axis transformation:
## u = lx/32.0 + ly/16.0; v = ly/16.0 - lx/32.0; gx = floor(u + 0.5); gy = floor(v + 0.5).
static func local_to_map(local_pos: Vector2) -> Vector2i:
	var u: float = (local_pos.x / TILE_WIDTH) + (local_pos.y / TILE_HEIGHT)
	var v: float = (local_pos.y / TILE_HEIGHT) - (local_pos.x / TILE_WIDTH)
	var gx: int = int(floor(u + 0.5))
	var gy: int = int(floor(v + 0.5))
	return Vector2i(gx, gy)

## Checks whether a grid coordinate is within the valid 64x64 simulation boundaries.
static func is_in_bounds(grid_pos: Vector2i) -> bool:
	return grid_pos.x >= 0 and grid_pos.x < MAP_SIZE and grid_pos.y >= 0 and grid_pos.y < MAP_SIZE

## Clamps a grid coordinate to the valid 64x64 boundaries.
static func clamp_grid(grid_pos: Vector2i) -> Vector2i:
	return Vector2i(
		clampi(grid_pos.x, 0, MAP_SIZE - 1),
		clampi(grid_pos.y, 0, MAP_SIZE - 1)
	)

## Returns the 4 cardinal neighbors (North, East, South, West) on the isometric diamond grid.
static func get_cardinal_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	var deltas: Array[Vector2i] = [
		Vector2i(0, -1), # North
		Vector2i(1, 0),  # East
		Vector2i(0, 1),  # South
		Vector2i(-1, 0)  # West
	]
	for d in deltas:
		var n: Vector2i = cell + d
		if is_in_bounds(n):
			neighbors.append(n)
	return neighbors

## Returns all 8 surrounding neighbors (cardinals + diagonals).
static func get_all_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var n: Vector2i = cell + Vector2i(dx, dy)
			if is_in_bounds(n):
				neighbors.append(n)
	return neighbors

## Computes Manhattan distance on the discrete grid.
static func grid_distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

## Computes the local screen bounding box center for a multi-tile footprint (e.g. 2x2 or 3x3).
## Origin (0,0) of the building footprint occupies cell (origin_cell.x, origin_cell.y).
static func get_footprint_local_center(origin_cell: Vector2i, width: int, height: int) -> Vector2:
	var top_left: Vector2 = map_to_local(origin_cell)
	var bottom_right: Vector2 = map_to_local(origin_cell + Vector2i(width - 1, height - 1))
	return (top_left + bottom_right) * 0.5
