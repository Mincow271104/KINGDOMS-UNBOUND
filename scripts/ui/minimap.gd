class_name MinimapPanel
extends PanelContainer
## Compact HUD Minimap for KINGDOMS UNBOUND (Phase 3).
## Renders dynamic 64x64 or 128x128 world terrain, 3-state Fog of War, territory tint,
## and filtered entity/structure markers using a single Image + ImageTexture.

const DISPLAY_SIZE := Vector2(160.0, 160.0)
const UNEXPLORED_COLOR := Color8(13, 15, 20, 255)

var _world_view: Node = null
var _map_width: int = 128
var _map_height: int = 128
var _img: Image = null
var _tex: ImageTexture = null
var _tex_rect: TextureRect = null
var _overlay: Control = null
var _title_label: Label = null
var debug_fog_disabled: bool = false

func set_debug_fog_disabled(disabled: bool) -> void:
	if debug_fog_disabled == disabled:
		return
	debug_fog_disabled = disabled
	rebuild_full_image()

func _init() -> void:
	name = "MinimapPanel"
	custom_minimum_size = Vector2(172, 192)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.14, 0.90)
	style.border_color = Color(0.36, 0.42, 0.52, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "🗺️ Bản Đồ"
	_title_label.add_theme_font_size_override("font_size", 11)
	_title_label.add_theme_color_override("font_color", Color(0.88, 0.85, 0.72, 1.0))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	var map_frame := Control.new()
	map_frame.custom_minimum_size = DISPLAY_SIZE
	map_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(map_frame)

	_tex_rect = TextureRect.new()
	_tex_rect.custom_minimum_size = DISPLAY_SIZE
	_tex_rect.size = DISPLAY_SIZE
	_tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	map_frame.add_child(_tex_rect)

	_overlay = _MinimapMarkerOverlay.new(self)
	_overlay.custom_minimum_size = DISPLAY_SIZE
	_overlay.size = DISPLAY_SIZE
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_frame.add_child(_overlay)

func initialize_minimap(world_view: Node) -> void:
	_world_view = world_view
	if _world_view == null:
		return
	var wd = _world_view.get("world_data")
	if wd == null:
		return
	_map_width = maxi(1, int(wd.map_width))
	_map_height = maxi(1, int(wd.map_height))
	_img = Image.create(_map_width, _map_height, false, Image.FORMAT_RGBA8)
	_tex = null
	rebuild_full_image()
	_tex = ImageTexture.create_from_image(_img)
	_tex_rect.texture = _tex
	refresh_markers()

func rebuild_full_image() -> void:
	if _img == null or _world_view == null:
		return
	var wd = _world_view.get("world_data")
	if wd == null:
		return
	if int(wd.map_width) != _map_width or int(wd.map_height) != _map_height:
		initialize_minimap(_world_view)
		return
	for x in range(_map_width):
		for y in range(_map_height):
			_img.set_pixel(x, y, _compute_cell_color(Vector2i(x, y)))
	if _tex != null:
		_tex.update(_img)
	refresh_markers()

func update_dirty_cells(cells: Array[Vector2i]) -> void:
	if _img == null or _tex == null or _world_view == null:
		return
	var wd = _world_view.get("world_data")
	if wd == null:
		return
	if int(wd.map_width) != _map_width or int(wd.map_height) != _map_height:
		initialize_minimap(_world_view)
		return
	if cells.is_empty():
		return
	for c in cells:
		if c.x >= 0 and c.x < _map_width and c.y >= 0 and c.y < _map_height:
			_img.set_pixel(c.x, c.y, _compute_cell_color(c))
	_tex.update(_img)
	refresh_markers()

func refresh_markers() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_redraw()

func get_pixel_color(cell: Vector2i) -> Color:
	if _img == null or cell.x < 0 or cell.x >= _map_width or cell.y < 0 or cell.y >= _map_height:
		return UNEXPLORED_COLOR
	return _img.get_pixel(cell.x, cell.y)

func _compute_cell_color(cell: Vector2i) -> Color:
	var fow = _world_view.get("fog_of_war")
	var state: int = fow.get_state(cell) if fow != null else FogOfWar.State.UNEXPLORED
	if not debug_fog_disabled and state == FogOfWar.State.UNEXPLORED:
		return UNEXPLORED_COLOR

	var wd = _world_view.get("world_data")
	var t_type: int = wd.terrain[cell.x][cell.y]
	var b_id: int = wd.get_biome(cell) if wd.has_method("get_biome") else 0
	var col := _get_base_terrain_color(t_type, b_id)

	var tmgr = _world_view.get("territory_mgr")
	if state == FogOfWar.State.VISIBLE and tmgr != null and tmgr.has_method("is_owned") and tmgr.is_owned(cell):
		col = col.lerp(Color(0.55, 0.85, 0.45), 0.18)

	if not debug_fog_disabled and state == FogOfWar.State.EXPLORED:
		var lum := col.r * 0.299 + col.g * 0.587 + col.b * 0.114
		col = col.lerp(Color(lum, lum, lum), 0.35).darkened(0.50)

	return col

func _get_base_terrain_color(t_type: int, b_id: int) -> Color:
	match t_type:
		WorldGenerator.TerrainType.WATER:
			return Color(0.16, 0.42, 0.58) if b_id == WorldGenerator.BiomeType.WETLANDS else Color(0.18, 0.44, 0.72)
		WorldGenerator.TerrainType.SAND:
			return Color(0.78, 0.70, 0.46)
		WorldGenerator.TerrainType.DIRT:
			return Color(0.46, 0.36, 0.24)
		WorldGenerator.TerrainType.HILLS:
			return Color(0.54, 0.48, 0.36)
		WorldGenerator.TerrainType.MOUNTAINS:
			return Color(0.40, 0.40, 0.46)
		_:
			match b_id:
				WorldGenerator.BiomeType.TEMPERATE_FOREST:
					return Color(0.24, 0.52, 0.24)
				WorldGenerator.BiomeType.PINE_FOREST:
					return Color(0.20, 0.46, 0.42)
				WorldGenerator.BiomeType.HIGHLANDS:
					return Color(0.46, 0.56, 0.30)
				WorldGenerator.BiomeType.WETLANDS:
					return Color(0.22, 0.44, 0.28)
				_:
					return Color(0.32, 0.62, 0.28)

func get_visible_markers_snapshot() -> Dictionary:
	var result := {
		"town_hall": [],
		"watchtowers": [],
		"outposts": [],
		"player_units": [],
		"pois": [],
		"natural_resources": [],
		"enemy_units": [],
		"monster_nests": [],
		"monsters": [],
	}
	if _world_view == null:
		return result
	var fow = _world_view.get("fog_of_war")
	var wd = _world_view.get("world_data")
	if wd != null and wd.get("buildings") != null:
		for b in wd.buildings:
			var b_type: String = str(b.get("type", ""))
			var b_cell: Vector2i = b.get("cell", Vector2i.ZERO)
			var b_state: String = str(b.get("state", "active"))
			if b_type == "townhall" and b_state != "destroyed":
				result["town_hall"].append(b_cell)
			elif b_type == "watchtower" and b_state == "active":
				result["watchtowers"].append(b_cell)
	var fsm = _world_view.get("field_siege_mgr")
	if fsm != null and fsm.has_method("get_all_objectives"):
		for obj in fsm.get_all_objectives():
			if obj != null and is_instance_valid(obj) and bool(obj.get("is_alive")):
				var o_cell: Vector2i = obj.get("current_cell")
				if str(obj.get("owning_faction_id")) == "player":
					result["outposts"].append(o_cell)
				elif debug_fog_disabled or (fow != null and fow.is_explored(o_cell)):
					result["pois"].append(o_cell)
	var tmm = _world_view.get("tactical_military_mgr")
	if tmm != null and tmm.has_method("get_all_units"):
		for u in tmm.get_all_units():
			if u != null and is_instance_valid(u) and bool(u.get("is_alive")):
				result["player_units"].append(u.get("current_cell"))
	var pm = _world_view.get("poi_mgr")
	if pm != null and pm.has_method("get_all_pois"):
		for poi in pm.get_all_pois():
			if debug_fog_disabled or poi.state != POIManager.POIState.UNDISCOVERED:
				result["pois"].append(poi.cell)
	if debug_fog_disabled:
		var nrm = _world_view.get("natural_resource_mgr")
		if nrm != null and nrm.get("nodes_by_cell") != null:
			for n_cell in nrm.nodes_by_cell.keys():
				var r_node = nrm.nodes_by_cell[n_cell]
				if r_node != null and not bool(r_node.get("depleted")):
					result["natural_resources"].append(n_cell)
	var emm = _world_view.get("enemy_military_mgr")
	if emm != null and emm.has_method("get_all_enemies"):
		for e in emm.get_all_enemies():
			if e != null and is_instance_valid(e) and bool(e.get("is_alive")):
				var e_cell: Vector2i = e.get("current_cell")
				if fow != null and fow.is_visible(e_cell):
					result["enemy_units"].append(e_cell)
	var mm = _world_view.get("monster_mgr")
	if mm != null:
		if mm.has_method("get_all_nests"):
			for nd in mm.get_all_nests():
				var nc: Vector2i = nd.get("cell", Vector2i(-1, -1))
				if debug_fog_disabled or bool(nd.get("discovered", false)) or (fow != null and fow.is_explored(nc)):
					result["monster_nests"].append(nc)
		if mm.has_method("get_living_monsters"):
			for m in mm.get_living_monsters():
				var mc: Vector2i = m.get("cell", Vector2i(-1, -1))
				if debug_fog_disabled or (fow != null and fow.is_visible(mc)):
					result["monsters"].append(mc)
	return result

class _MinimapMarkerOverlay extends Control:
	var _owner_panel: MinimapPanel
	func _init(owner_panel: MinimapPanel) -> void:
		_owner_panel = owner_panel
	func _draw() -> void:
		if _owner_panel == null or _owner_panel._world_view == null:
			return
		var sx: float = size.x / float(maxi(1, _owner_panel._map_width))
		var sy: float = size.y / float(maxi(1, _owner_panel._map_height))
		var m := _owner_panel.get_visible_markers_snapshot()
		for c in m.get("natural_resources", []):
			draw_rect(Rect2(c.x * sx - 1.0, c.y * sy - 1.0, 2.0, 2.0), Color(0.25, 0.90, 0.85, 0.90))
		for c in m["pois"]:
			draw_rect(Rect2(c.x * sx - 1.5, c.y * sy - 1.5, 3.0, 3.0), Color(0.95, 0.72, 0.22, 0.95))
		for c in m.get("monster_nests", []):
			draw_rect(Rect2(c.x * sx - 1.5, c.y * sy - 1.5, 3.0, 3.0), Color(0.88, 0.28, 0.18, 0.95))
		for c in m.get("monsters", []):
			draw_circle(Vector2(c.x * sx, c.y * sy), 1.8, Color(0.90, 0.25, 0.65, 0.95))
		for c in m["outposts"]:
			draw_rect(Rect2(c.x * sx - 1.5, c.y * sy - 1.5, 3.5, 3.5), Color(0.30, 0.75, 1.0, 1.0))
		for c in m["watchtowers"]:
			draw_rect(Rect2(c.x * sx - 1.5, c.y * sy - 1.5, 3.5, 3.5), Color(0.35, 0.95, 0.95, 1.0))
		for c in m["town_hall"]:
			draw_rect(Rect2(c.x * sx - 2.5, c.y * sy - 2.5, 5.0, 5.0), Color(1.0, 0.85, 0.20, 1.0))
		for c in m["player_units"]:
			draw_circle(Vector2(c.x * sx, c.y * sy), 2.0, Color(0.25, 1.0, 0.35, 1.0))
		for c in m["enemy_units"]:
			draw_circle(Vector2(c.x * sx, c.y * sy), 2.0, Color(1.0, 0.25, 0.25, 1.0))
		var cam = _owner_panel._world_view.get("camera")
		if cam != null and is_instance_valid(cam):
			var center_cell := IsoMath.local_to_map(cam.position)
			var half_span: float = clampf(16.0 / maxf(0.4, cam.zoom.x), 4.0, float(_owner_panel._map_width) * 0.45)
			var rx: float = clampf((center_cell.x - half_span) * sx, 0.0, size.x - 4.0)
			var ry: float = clampf((center_cell.y - half_span) * sy, 0.0, size.y - 4.0)
			var rw: float = clampf(half_span * 2.0 * sx, 4.0, size.x - rx)
			var rh: float = clampf(half_span * 2.0 * sy, 4.0, size.y - ry)
			draw_rect(Rect2(rx, ry, rw, rh), Color(1.0, 1.0, 1.0, 0.65), false, 1.0)
