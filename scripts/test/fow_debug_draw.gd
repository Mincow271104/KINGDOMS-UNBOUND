extends Node2D
## Visual debug overlay for Package 3B live gameplay acceptance.
## Renders isometric Fog of War status and observer boundaries.

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var world_node := get_parent()
	if world_node == null:
		return
	var world_view := world_node.get_parent()
	if world_view == null:
		return
	var fow = world_view.get("fog_of_war")
	if fow == null:
		return

	var cam: Camera2D = world_view.get_node_or_null("Camera2D")
	var cam_cell: Vector2i = Vector2i(32, 32)
	if cam != null:
		cam_cell = IsoMath.local_to_map(cam.position)

	# Bounding box of cells around camera to draw
	var min_x := clampi(cam_cell.x - 16, 0, 63)
	var max_x := clampi(cam_cell.x + 16, 0, 63)
	var min_y := clampi(cam_cell.y - 16, 0, 63)
	var max_y := clampi(cam_cell.y + 16, 0, 63)

	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			var cell := Vector2i(x, y)
			var state: int = fow.get_state(cell)
			var fill_color := Color.TRANSPARENT
			var line_color := Color.TRANSPARENT

			if state == 2: # VISIBLE
				fill_color = Color(0.15, 0.85, 0.25, 0.22)
				line_color = Color(0.2, 0.9, 0.3, 0.45)
			elif state == 1: # EXPLORED
				fill_color = Color(0.25, 0.45, 0.75, 0.20)
				line_color = Color(0.35, 0.55, 0.85, 0.35)
			elif state == 0: # UNEXPLORED
				fill_color = Color(0.04, 0.05, 0.08, 0.70)
				line_color = Color(0.1, 0.12, 0.18, 0.4)

			var lp := IsoMath.map_to_local(cell)
			var top := lp + Vector2(0, -8)
			var right := lp + Vector2(16, 0)
			var bottom := lp + Vector2(0, 8)
			var left := lp + Vector2(-16, 0)

			draw_colored_polygon(PackedVector2Array([top, right, bottom, left]), fill_color)
			draw_polyline(PackedVector2Array([top, right, bottom, left, top]), line_color, 1.0)

	# Draw observer boundaries
	var fsm = world_view.get("field_siege_mgr")
	if fsm != null and fsm.has_method("get_all_objectives"):
		for obj in fsm.get_all_objectives():
			if obj != null and is_instance_valid(obj):
				var o_cell: Vector2i = obj.current_cell
				var is_player: bool = (str(obj.get("owning_faction_id")) == "player")
				var rad: int = int(obj.get("vision_radius")) if obj.get("vision_radius") != null else 6
				var b_color := Color(1.0, 0.85, 0.1, 0.95) if is_player else Color(0.9, 0.2, 0.2, 0.85)

				if is_player:
					_draw_diamond_boundary(o_cell, rad, b_color, 2.5)
				else:
					_draw_diamond_boundary(o_cell, 1, b_color, 2.0)

	var tac_mgr = world_view.get("tactical_military_mgr")
	if tac_mgr != null and tac_mgr.has_method("get_all_units"):
		for u in tac_mgr.get_all_units():
			if u != null and is_instance_valid(u) and bool(u.get("is_alive")):
				var u_cell: Vector2i = u.get("current_cell")
				_draw_diamond_boundary(u_cell, 4, Color(0.1, 0.9, 0.9, 0.95), 2.0)

	var pam = world_view.get("player_army_mgr")
	if pam != null and pam.get("current_cell") != null:
		var s_count: int = int(pam.get("soldier_count")) if pam.get("soldier_count") != null else 0
		if s_count > 0:
			var a_cell: Vector2i = pam.current_cell
			_draw_diamond_boundary(a_cell, 4, Color(0.95, 0.8, 0.2, 0.9), 2.0)

func _draw_diamond_boundary(center: Vector2i, radius: int, color: Color, width: float) -> void:
	var top := IsoMath.map_to_local(center + Vector2i(0, -radius)) + Vector2(0, -8)
	var right := IsoMath.map_to_local(center + Vector2i(radius, 0)) + Vector2(16, 0)
	var bottom := IsoMath.map_to_local(center + Vector2i(0, radius)) + Vector2(0, 8)
	var left := IsoMath.map_to_local(center + Vector2i(-radius, 0)) + Vector2(-16, 0)
	draw_polyline(PackedVector2Array([top, right, bottom, left, top]), color, width)
