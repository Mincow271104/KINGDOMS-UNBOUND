class_name BuildingSelectionHighlight
extends Node2D
## Isometric Bracketed Diamond Selection Highlight for KINGDOMS UNBOUND.
## Renders a precise 2:1 dimetric ground footprint highlight (1x1, 2x2, 3x3)
## with a subtle translucent fill, soft inner perimeter, and royal-gold corner brackets.

var origin_cell: Vector2i = Vector2i(-1, -1)
var footprint_size: Vector2i = Vector2i(1, 1)
var is_active: bool = false

var border_color: Color = Color(1.0, 0.85, 0.25, 0.95)       # Royal gold corner brackets
var inner_border_color: Color = Color(1.0, 0.85, 0.25, 0.55) # Soft inner diamond line
var fill_color: Color = Color(1.0, 0.85, 0.25, 0.14)         # Subtle translucent gold fill
var bracket_width: float = 3.0
var inner_border_width: float = 1.5
var bracket_arm_ratio: float = 0.22

func set_footprint(origin: Vector2i, size: Vector2i) -> void:
	origin_cell = origin
	footprint_size = size
	is_active = true
	visible = true
	queue_redraw()

func clear_highlight() -> void:
	is_active = false
	visible = false
	origin_cell = Vector2i(-1, -1)
	queue_redraw()

func _draw() -> void:
	if not is_active or origin_cell.x < 0 or origin_cell.y < 0:
		return

	var pts := compute_diamond_vertices(origin_cell, footprint_size)
	if pts.size() == 4:
		# Draw subtle translucent diamond fill
		var colors := PackedColorArray([fill_color, fill_color, fill_color, fill_color])
		draw_polygon(pts, colors)

		# Draw soft closed inner diamond outline
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, inner_border_color, inner_border_width, true)

		# Draw royal-gold corner brackets (constant-time across 1x1, 2x2, 3x3)
		for i in range(4):
			var prev := pts[(i + 3) % 4]
			var curr := pts[i]
			var next := pts[(i + 1) % 4]
			var p1 := curr.lerp(prev, bracket_arm_ratio)
			var p2 := curr.lerp(next, bracket_arm_ratio)
			draw_polyline(PackedVector2Array([p1, curr, p2]), border_color, bracket_width, true)

## Computes the 4 outer ground vertices of a multi-tile isometric footprint (w x h).
## - Top vertex: top vertex of cell (origin.x, origin.y)
## - Right vertex: right vertex of cell (origin.x + w - 1, origin.y)
## - Bottom vertex: bottom vertex of cell (origin.x + w - 1, origin.y + h - 1)
## - Left vertex: left vertex of cell (origin.x, origin.y + h - 1)
static func compute_diamond_vertices(origin: Vector2i, size: Vector2i) -> PackedVector2Array:
	var w: int = maxi(1, size.x)
	var h: int = maxi(1, size.y)

	# In IsoMath.map_to_local(cell): returns bottom-center vertex (0, 0)
	# Cell diamond: Top (0, -16), Right (16, -8), Bottom (0, 0), Left (-16, -8)
	var top := IsoMath.map_to_local(origin) + Vector2(0.0, -16.0)
	var right := IsoMath.map_to_local(Vector2i(origin.x + w - 1, origin.y)) + Vector2(16.0, -8.0)
	var bottom := IsoMath.map_to_local(Vector2i(origin.x + w - 1, origin.y + h - 1)) + Vector2(0.0, 0.0)
	var left := IsoMath.map_to_local(Vector2i(origin.x, origin.y + h - 1)) + Vector2(-16.0, -8.0)

	return PackedVector2Array([top, right, bottom, left])
