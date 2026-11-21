class_name BridgeVisualNode
extends Node2D
## Procedural Isometric Bridge Renderer (Phase 4).
## Renders a variable-length, variable-width (1-3) straight bridge as a single Node2D.

var bridge_id: String = ""
var origin: Vector2i = Vector2i.ZERO
var size: Vector2i = Vector2i.ONE
var axis: String = "x"
var length: int = 1
var width: int = 1
var bridge_state: String = "active"

func setup(b_data: Dictionary) -> void:
	bridge_id = str(b_data.get("id", ""))
	origin = b_data.get("cell", Vector2i.ZERO)
	size = b_data.get("size", Vector2i.ONE)
	axis = str(b_data.get("axis", "x"))
	length = maxi(1, int(b_data.get("length", size.x if axis == "x" else size.y)))
	width = clampi(int(b_data.get("width", size.y if axis == "x" else size.x)), 1, 3)
	bridge_state = str(b_data.get("state", "active"))
	name = "Building_bridge_%d_%d" % [origin.x, origin.y]
	# Y-sort anchor at +1: draws after TerrainLayer (y=0) and before units on deck (y>=8)
	position = Vector2(0, 1)
	queue_redraw()

func set_bridge_state(new_state: String) -> void:
	if bridge_state != new_state:
		bridge_state = new_state
		queue_redraw()

func _iso_diamond(cell: Vector2i) -> PackedVector2Array:
	var c := IsoMath.map_to_local(cell) - position
	return PackedVector2Array([
		c + Vector2(0, -IsoMath.HALF_HEIGHT),
		c + Vector2(IsoMath.HALF_WIDTH, 0),
		c + Vector2(0, IsoMath.HALF_HEIGHT),
		c + Vector2(-IsoMath.HALF_WIDTH, 0)
	])

func _draw() -> void:
	if size.x <= 0 or size.y <= 0:
		return

	var is_uc: bool = (bridge_state == "under_construction")
	var is_damaged: bool = (bridge_state == "damaged")
	var is_destroyed: bool = (bridge_state == "destroyed")

	var alpha: float = 0.62 if is_uc else (0.55 if is_destroyed else 1.0)
	var plank_col := Color(0.56, 0.39, 0.22, alpha)
	var plank_alt := Color(0.50, 0.34, 0.19, alpha)
	var seam_col := Color(0.28, 0.18, 0.09, alpha * 0.9)
	var rail_col := Color(0.38, 0.24, 0.12, alpha)
	var post_col := Color(0.26, 0.16, 0.08, alpha)
	var piling_col := Color(0.18, 0.12, 0.07, alpha * 0.85)

	if is_uc:
		plank_col = Color(0.68, 0.56, 0.34, alpha)
		plank_alt = Color(0.60, 0.48, 0.28, alpha)
	elif is_damaged:
		plank_col = Color(0.55, 0.30, 0.22, alpha)
		plank_alt = Color(0.45, 0.24, 0.18, alpha)
	elif is_destroyed:
		plank_col = Color(0.28, 0.22, 0.18, alpha)
		plank_alt = Color(0.22, 0.17, 0.14, alpha)

	# Draw deck cells in back-to-front isometric order (ascending x + y)
	var cells: Array[Vector2i] = []
	for ox in range(size.x):
		for oy in range(size.y):
			cells.append(origin + Vector2i(ox, oy))
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a.x + a.y) < (b.x + b.y)
	)

	for cell in cells:
		var poly := _iso_diamond(cell)
		# Water piling / underside shadow drop
		var shadow_poly := PackedVector2Array([
			poly[3], poly[2], poly[1],
			poly[1] + Vector2(0, 4),
			poly[2] + Vector2(0, 4),
			poly[3] + Vector2(0, 4)
		])
		draw_colored_polygon(shadow_poly, piling_col)

		# Deck surface
		var col := plank_col if ((cell.x + cell.y) % 2 == 0) else plank_alt
		draw_colored_polygon(poly, col)

		# Cross-planks perpendicular to bridge travel axis
		if axis == "x":
			for i in range(1, 4):
				var t: float = float(i) / 4.0
				var p0 := poly[0].lerp(poly[1], t)
				var p1 := poly[3].lerp(poly[2], t)
				draw_line(p0, p1, seam_col, 1.0)
		else:
			for i in range(1, 4):
				var t: float = float(i) / 4.0
				var p0 := poly[0].lerp(poly[3], t)
				var p1 := poly[1].lerp(poly[2], t)
				draw_line(p0, p1, seam_col, 1.0)

		if is_uc:
			# Construction scaffolding X-brace
			draw_line(poly[0], poly[2], post_col, 1.0)
			draw_line(poly[1], poly[3], post_col, 1.0)

		# Outer side railings only on outer lanes of the bridge
		if axis == "x":
			if cell.y == origin.y:
				# Top-right outer edge (poly[0] -> poly[1])
				draw_line(poly[0] + Vector2(0, -4), poly[1] + Vector2(0, -4), rail_col, 1.5)
				draw_line(poly[0], poly[0] + Vector2(0, -5), post_col, 1.5)
				draw_line(poly[1], poly[1] + Vector2(0, -5), post_col, 1.5)
			if cell.y == origin.y + size.y - 1:
				# Bottom-left outer edge (poly[3] -> poly[2])
				draw_line(poly[3] + Vector2(0, -4), poly[2] + Vector2(0, -4), rail_col, 1.5)
				draw_line(poly[3], poly[3] + Vector2(0, -5), post_col, 1.5)
				draw_line(poly[2], poly[2] + Vector2(0, -5), post_col, 1.5)
		else:
			if cell.x == origin.x:
				# Top-left outer edge (poly[0] -> poly[3])
				draw_line(poly[0] + Vector2(0, -4), poly[3] + Vector2(0, -4), rail_col, 1.5)
				draw_line(poly[0], poly[0] + Vector2(0, -5), post_col, 1.5)
				draw_line(poly[3], poly[3] + Vector2(0, -5), post_col, 1.5)
			if cell.x == origin.x + size.x - 1:
				# Bottom-right outer edge (poly[1] -> poly[2])
				draw_line(poly[1] + Vector2(0, -4), poly[2] + Vector2(0, -4), rail_col, 1.5)
				draw_line(poly[1], poly[1] + Vector2(0, -5), post_col, 1.5)
				draw_line(poly[2], poly[2] + Vector2(0, -5), post_col, 1.5)
