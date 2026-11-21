class_name ContinuousPathFollower
extends RefCounted
## Shared Continuous Isometric Path Follower, Safe Corridor Smoother,
## and 8-Direction Screen-Space Facing Classifier.
## Keeps GridNavigation discrete A* intact while providing smooth locomotion.

enum ScreenDir {
	E = 0,
	SE = 1,
	S = 2,
	SW = 3,
	W = 4,
	NW = 5,
	N = 6,
	NE = 7
}

const DIR_NAMES: Array[String] = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
const VEL_DEADZONE_SQ: float = 0.04
const HYSTERESIS_RAD: float = 0.08726646 # ~5 degrees

var smoothed_cells: Array[Vector2i] = []
var waypoints: Array[Vector2] = []
var waypoint_index: int = 0
var last_screen_dir: int = ScreenDir.E
var last_flip_h: bool = false

func clear() -> void:
	smoothed_cells.clear()
	waypoints.clear()
	waypoint_index = 0

func is_finished() -> bool:
	return waypoint_index >= waypoints.size()

func get_remaining_waypoints() -> Array[Vector2]:
	if is_finished():
		return []
	return waypoints.slice(waypoint_index)

## Sets a discrete grid path, applies conservative corridor smoothing,
## and prepares continuous screen-space waypoints.
func set_path(cell_path: Array[Vector2i], nav: GridNavigation = null, current_pos: Vector2 = Vector2.INF, allowed_cell_predicate: Callable = Callable()) -> void:
	clear()
	if cell_path.is_empty():
		return
	smoothed_cells = smooth_cell_path(cell_path, nav, allowed_cell_predicate)
	for c in smoothed_cells:
		waypoints.append(IsoMath.map_to_local(c))
	waypoint_index = 0
	if current_pos != Vector2.INF and waypoints.size() >= 2:
		if current_pos.distance_squared_to(waypoints[0]) <= 1.0:
			waypoint_index = 1

## Advances continuously along waypoints, consuming travel_dist across multiple
## waypoints if needed without pausing or resetting at intermediate cells.
func advance(current_pos: Vector2, travel_dist: float) -> Dictionary:
	if is_finished() or travel_dist <= 0.0:
		return {
			"position": current_pos,
			"cell": IsoMath.local_to_map(current_pos),
			"velocity": Vector2.ZERO,
			"arrived": is_finished(),
			"moved_dist": 0.0
		}

	var pos := current_pos
	var remaining := travel_dist
	var total_moved := 0.0
	var last_dir_vec := Vector2.ZERO

	while remaining > 0.0001 and waypoint_index < waypoints.size():
		var target := waypoints[waypoint_index]
		var diff := target - pos
		var dist := diff.length()
		if dist <= 0.0001:
			pos = target
			waypoint_index += 1
			continue

		last_dir_vec = diff / dist
		if dist <= remaining:
			pos = target
			remaining -= dist
			total_moved += dist
			waypoint_index += 1
		else:
			pos += last_dir_vec * remaining
			total_moved += remaining
			remaining = 0.0

	var arrived := waypoint_index >= waypoints.size()
	var vel := pos - current_pos
	if vel.length_squared() < VEL_DEADZONE_SQ and last_dir_vec != Vector2.ZERO and total_moved > 0.0:
		vel = last_dir_vec * total_moved

	return {
		"position": pos,
		"cell": IsoMath.local_to_map(pos),
		"velocity": vel,
		"arrived": arrived,
		"moved_dist": total_moved
	}

## Conservative string-pulling path smoother that preserves obstacles, corner clearance,
## terrain movement cost parity, and exact final destination.
static func smooth_cell_path(cell_path: Array[Vector2i], nav: GridNavigation, allowed_cell_predicate: Callable = Callable()) -> Array[Vector2i]:
	if cell_path.size() <= 2 or nav == null:
		return cell_path.duplicate()

	var result: Array[Vector2i] = [cell_path[0]]
	var anchor_idx := 0
	var n := cell_path.size()

	while anchor_idx < n - 1:
		var chosen := anchor_idx + 1
		var probe := n - 1
		while probe > anchor_idx + 1:
			if has_safe_corridor(cell_path[anchor_idx], cell_path[probe], nav, allowed_cell_predicate):
				chosen = probe
				break
			probe -= 1
		result.append(cell_path[chosen])
		anchor_idx = chosen

	return result

## Verifies that the straight continuous isometric segment between grid cells a and b
## stays within walkable cells, avoids diagonal corner-cutting, and does not shortcut
## across higher-cost terrain.
static func has_safe_corridor(a: Vector2i, b: Vector2i, nav: GridNavigation, allowed_cell_predicate: Callable = Callable()) -> bool:
	if nav == null:
		return true
	if a == b:
		return true

	var has_pred := allowed_cell_predicate.is_valid()
	var pa := IsoMath.map_to_local(a)
	var pb := IsoMath.map_to_local(b)
	var grid_span := absi(b.x - a.x) + absi(b.y - a.y)
	var steps := maxi(4, grid_span * 4)
	var has_cost_fn: bool = nav.has_method("get_movement_cost")
	var max_cost: int = maxi(int(nav.call("get_movement_cost", a)), int(nav.call("get_movement_cost", b))) if has_cost_fn else 1

	for i in range(1, steps):
		var t := float(i) / float(steps)
		var p := pa.lerp(pb, t)
		var cell := IsoMath.local_to_map(p)
		if cell != a and cell != b:
			if not nav.is_cell_walkable(cell):
				return false
			if has_pred and not bool(allowed_cell_predicate.call(cell)):
				return false
			if has_cost_fn and int(nav.call("get_movement_cost", cell)) > max_cost:
				return false

		# Continuous grid coordinates for corner-clearance check
		var u := (p.x / IsoMath.TILE_WIDTH) + (p.y / IsoMath.TILE_HEIGHT)
		var v := (p.y / IsoMath.TILE_HEIGHT) - (p.x / IsoMath.TILE_WIDTH)
		var fu := floorf(u)
		var fv := floorf(v)
		if absf(u - fu - 0.5) < 0.35 and absf(v - fv - 0.5) < 0.35:
			var corners := [
				Vector2i(int(fu), int(fv)),
				Vector2i(int(ceilf(u)), int(fv)),
				Vector2i(int(fu), int(ceilf(v))),
				Vector2i(int(ceilf(u)), int(ceilf(v)))
			]
			for cc in corners:
				if cc != a and cc != b:
					if not nav.is_cell_walkable(cc):
						return false
					if has_pred and not bool(allowed_cell_predicate.call(cc)):
						return false

	return true

## Classifies screen-space velocity into one of 8 isometric screen directions
## with dead-zone and angular hysteresis to prevent flicker.
func update_facing_from_velocity(vel: Vector2) -> int:
	last_screen_dir = classify_screen_direction(vel, last_screen_dir)
	last_flip_h = should_flip_h(last_screen_dir, last_flip_h)
	return last_screen_dir

static func classify_screen_direction(vel: Vector2, prev_dir: int = ScreenDir.E) -> int:
	if vel.length_squared() < VEL_DEADZONE_SQ:
		return prev_dir

	var ang := atan2(vel.y, vel.x) # [-PI, PI], 0 is Screen East (+X)
	if ang < 0.0:
		ang += TAU
	var sector := int(round(ang / (PI / 4.0))) % 8

	if prev_dir >= 0 and prev_dir < 8 and sector != prev_dir:
		var prev_center := float(prev_dir) * (PI / 4.0)
		var diff := absf(wrapf(ang - prev_center, -PI, PI))
		if diff <= (PI / 8.0) + HYSTERESIS_RAD:
			return prev_dir

	return sector

static func dir_to_name(dir: int) -> String:
	if dir >= 0 and dir < DIR_NAMES.size():
		return DIR_NAMES[dir]
	return "E"

static func should_flip_h(dir: int, prev_flip: bool = false) -> bool:
	match dir:
		ScreenDir.W, ScreenDir.NW, ScreenDir.SW:
			return true
		ScreenDir.E, ScreenDir.NE, ScreenDir.SE:
			return false
		_:
			return prev_flip

## Lightweight local separation nudge for nearby moving actors.
static func compute_separation_nudge(self_pos: Vector2, other_positions: Array, radius: float = 10.0, max_push: float = 0.6) -> Vector2:
	var push := Vector2.ZERO
	var r_sq := radius * radius
	for op in other_positions:
		if not (op is Vector2):
			continue
		var op_vec: Vector2 = op
		var d: Vector2 = self_pos - op_vec
		var d_sq: float = d.length_squared()
		if d_sq > 0.001 and d_sq < r_sq:
			var dist := sqrt(d_sq)
			push += (d / dist) * ((radius - dist) / radius)
	if push.length() > max_push:
		push = push.normalized() * max_push
	return push
