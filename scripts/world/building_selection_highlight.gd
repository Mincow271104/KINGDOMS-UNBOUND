class_name BuildingSelectionHighlight
extends Node2D
## Isometric Diamond Selection Highlight for KINGDOMS UNBOUND (Package 2F).
## Renders a precise 2:1 dimetric ground footprint highlight (1x1, 2x2, 3x3)
## conforming to diamond tile geometry and world coordinates.

var origin_cell: Vector2i = Vector2i(-1, -1)
var footprint_size: Vector2i = Vector2i(1, 1)
var is_active: bool = false

var border_color: Color = Color(1.0, 0.85, 0.25, 0.95) # Royal gold
var fill_color: Color = Color(1.0, 0.85, 0.25, 0.22)   # Translucent gold
var border_width: float = 2.0

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
		# Draw filled translucent diamond polygon
		var colors := PackedColorArray([fill_color, fill_color, fill_color, fill_color])
		draw_polygon(pts, colors)

		# Draw crisp closed diamond border outline
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, border_color, border_width, true)

		# Draw subtle corner accent dots at the 4 diamond vertices
		for p in pts:
			draw_circle(p, 2.5, border_color)

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
