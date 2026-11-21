class_name FogCloudLayer
extends Node2D
## Isolated pixel-art cloud overlay for UNEXPLORED Fog of War regions.
## Uses deterministic chunked placement and dirty-region updates without
## modifying FogOfWar state, reveal_circle(), or A2 FogTileMapLayer.

enum DensityPreset {
	DENSE = 0,
	BALANCED = 1,
	LOOSE = 2
}

enum CloudKind {
	TOWERING_CUMULUS = 0,     # main_cloud_01_towering_cumulus.png (144x92)
	SWEEPING_BANK = 1,        # main_cloud_02_sweeping_bank.png (160x84)
	ASYMMETRICAL_CLUSTER = 2  # main_cloud_03_asymmetrical_cluster.png (136x88)
}

const CHUNK_SIZE: int = 8
const FOOTPRINT_MARGIN: int = 6

const CLOUD_TEXTURE_PATHS: Array[String] = [
	"res://assets/fog/main_cloud_01_towering_cumulus.png",
	"res://assets/fog/main_cloud_02_sweeping_bank.png",
	"res://assets/fog/main_cloud_03_asymmetrical_cluster.png",
]

var _textures: Array[Texture2D] = []
var _fog_of_war: FogOfWar = null
var _world_seed: int = 1337
var _density_preset: int = DensityPreset.BALANCED
var _chunk_nodes: Dictionary = {} # Vector2i(cx, cy) -> Array[Sprite2D]
var _chunk_candidates: Dictionary = {} # Vector2i(cx, cy) -> Array[Dictionary]
var _enabled: bool = true
var _fog_mask_img: Image = null
var _fog_mask_tex: ImageTexture = null
var _active_layout_key: String = ""
static var _mask_lut: PackedByteArray = PackedByteArray()
static var _opaque_pts_cache: Array = []
static var _opaque_uv_bounds_cache: Array[Vector4] = []
static var _layout_cache: Dictionary = {} # layout_key -> Dictionary(chunk_coord -> Array[Dictionary])
static var _layout_cache_order: Array[String] = []
const MAX_LAYOUT_CACHE_ENTRIES: int = 8
static var _fg_cloud_material: ShaderMaterial = null

func _init() -> void:
	name = "FogCloudLayer"
	z_index = 7 # Directly above CloudSeaBase (z=6) and FogTileMapLayer (z=5), below CursorHighlight (z=10)
	y_sort_enabled = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load_textures()

func _load_textures() -> void:
	_textures.clear()
	for path in CLOUD_TEXTURE_PATHS:
		var tex: Texture2D = load(path) as Texture2D
		_textures.append(tex)
	if _opaque_pts_cache.size() != _textures.size() or _opaque_uv_bounds_cache.size() != _textures.size():
		_opaque_pts_cache.clear()
		_opaque_uv_bounds_cache.clear()
		for tex in _textures:
			if tex != null:
				var img: Image = tex.get_image()
				if img != null:
					var pts := _extract_opaque_sample_points(img, 1)
					_opaque_pts_cache.append(pts)
					var umin: float = 1e9
					var umax: float = -1e9
					var vmin: float = 1e9
					var vmax: float = -1e9
					for off in pts:
						var u: float = (off.x / IsoMath.TILE_WIDTH) + (off.y / IsoMath.TILE_HEIGHT)
						var v: float = (off.y / IsoMath.TILE_HEIGHT) - (off.x / IsoMath.TILE_WIDTH)
						if u < umin: umin = u
						if u > umax: umax = u
						if v < vmin: vmin = v
						if v > vmax: vmax = v
					_opaque_uv_bounds_cache.append(Vector4(umin, umax, vmin, vmax))
					continue
			_opaque_pts_cache.append(PackedVector2Array())
			_opaque_uv_bounds_cache.append(Vector4.ZERO)

static func _extract_opaque_sample_points(img: Image, stride: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var w := img.get_width()
	var h := img.get_height()
	var hw := float(w) * 0.5
	var hh := float(h) * 0.5
	for y in range(0, h, stride):
		for x in range(0, w, stride):
			if img.get_pixel(x, y).a > 0.1:
				pts.append(Vector2(float(x) - hw, float(y) - hh))
	return pts

static func _get_foreground_cloud_material() -> ShaderMaterial:
	if _fg_cloud_material != null:
		return _fg_cloud_material
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;

uniform vec3 tint_rgb = vec3(1.04, 1.08, 1.14);
uniform float mid_lift = 0.22;
uniform float highlight_gain = 1.18;
uniform float alpha_mult = 0.97;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a < 0.01) {
		discard;
	}
	float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	float lift_mask = smoothstep(0.08, 0.55, lum);
	vec3 lifted = tex.rgb * mix(1.04, highlight_gain, lift_mask) + vec3(0.015, 0.022, 0.036) * mid_lift * lift_mask;
	vec3 final_rgb = clamp(lifted * tint_rgb, vec3(0.0), vec3(0.88));
	COLOR = vec4(final_rgb, tex.a * alpha_mult);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_fg_cloud_material = mat
	return _fg_cloud_material

func get_loaded_textures() -> Array[Texture2D]:
	return _textures

func configure(fog: FogOfWar, seed_val: int, preset: int = DensityPreset.BALANCED) -> void:
	_fog_of_war = fog
	_world_seed = seed_val
	_density_preset = clampi(preset, DensityPreset.DENSE, DensityPreset.LOOSE)
	sync_full()

func set_density_preset(preset: int) -> void:
	var clamped: int = clampi(preset, DensityPreset.DENSE, DensityPreset.LOOSE)
	if clamped != _density_preset:
		_density_preset = clamped
		sync_full()

func get_density_preset() -> int:
	return _density_preset

func set_cloud_enabled(enabled: bool) -> void:
	_enabled = enabled
	visible = _enabled

func is_cloud_enabled() -> bool:
	return _enabled

func get_active_cloud_count() -> int:
	var total: int = 0
	for sprites in _chunk_nodes.values():
		total += (sprites as Array).size()
	return total

func get_active_cloud_positions() -> Array[Vector2]:
	var pts: Array[Vector2] = []
	for sprites in _chunk_nodes.values():
		for sp in (sprites as Array):
			if is_instance_valid(sp):
				pts.append((sp as Node2D).position)
	return pts

func clear_all() -> void:
	for sprites in _chunk_nodes.values():
		for sp in (sprites as Array):
			if is_instance_valid(sp):
				var node := sp as Node
				if node.get_parent() == self:
					remove_child(node)
				node.queue_free()
	_chunk_nodes.clear()

func get_fog_mask_image() -> Image:
	return _fog_mask_img

func get_fog_mask_texture() -> ImageTexture:
	return _fog_mask_tex

static func _ensure_mask_lut() -> PackedByteArray:
	if _mask_lut.is_empty():
		var tmp_enc := Image.create(2, 1, false, Image.FORMAT_RGBA8)
		tmp_enc.set_pixel(0, 0, Color(0.42, 0.42, 0.42, 1.0))
		tmp_enc.set_pixel(1, 0, Color(0.78, 0.78, 0.78, 1.0))
		var bytes := tmp_enc.get_data()
		_mask_lut = PackedByteArray([0, 0, int(bytes[0]), int(bytes[4]), 255])
	return _mask_lut

func _compute_cell_mask_value_ref(cx: int, cy: int) -> float:
	if _fog_of_war == null or not _fog_of_war.is_unexplored(Vector2i(cx, cy)):
		return 0.0
	var min_d := 4
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var d := absi(dx) + absi(dy)
			if d >= min_d or d > 3:
				continue
			var nb := Vector2i(cx + dx, cy + dy)
			if IsoMath.is_in_bounds(nb, _get_fog_width(), _get_fog_height()):
				if not _fog_of_war.is_unexplored(nb):
					min_d = d
	if min_d <= 1:
		return 0.0
	elif min_d == 2:
		return 0.42
	elif min_d == 3:
		return 0.78
	return 1.0

func _get_fog_width() -> int:
	if _fog_of_war == null:
		return 0
	var w = _fog_of_war.get("map_width")
	return int(w) if w != null else int(_fog_of_war.map_size)

func _get_fog_height() -> int:
	if _fog_of_war == null:
		return 0
	var h = _fog_of_war.get("map_height")
	return int(h) if h != null else int(_fog_of_war.map_size)

func _sync_full_fog_mask_ref() -> Image:
	if _fog_of_war == null:
		return null
	var mw := _get_fog_width()
	var mh := _get_fog_height()
	var img := Image.create(mw, mh, false, Image.FORMAT_RGBA8)
	for y in range(mh):
		for x in range(mw):
			var v := _compute_cell_mask_value_ref(x, y)
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	return img

func _sync_full_fog_mask_fast() -> Image:
	if _fog_of_war == null:
		return null
	var mw := _get_fog_width()
	var mh := _get_fog_height()
	var n := mw * mh
	var dist := PackedByteArray()
	dist.resize(n)

	var grid: Array = _fog_of_war._grid
	for x in range(mw):
		var col: Array = grid[x]
		for y in range(mh):
			dist[y * mw + x] = 4 if int(col[y]) == FogOfWar.State.UNEXPLORED else 0

	# Pass 1: Top-Left to Bottom-Right (exact L1 Manhattan distance)
	for y in range(mh):
		var row := y * mw
		for x in range(mw):
			var idx := row + x
			var d: int = dist[idx]
			if d == 0:
				continue
			if x > 0:
				var dl: int = dist[idx - 1] + 1
				if dl < d:
					d = dl
			if y > 0:
				var du: int = dist[idx - mw] + 1
				if du < d:
					d = du
			dist[idx] = d

	# Pass 2: Bottom-Right to Top-Left
	for y in range(mh - 1, -1, -1):
		var row := y * mw
		for x in range(mw - 1, -1, -1):
			var idx := row + x
			var d: int = dist[idx]
			if d <= 1:
				continue
			if x + 1 < mw:
				var dr: int = dist[idx + 1] + 1
				if dr < d:
					d = dr
			if y + 1 < mh:
				var dd: int = dist[idx + mw] + 1
				if dd < d:
					d = dd
			dist[idx] = d

	var lut := _ensure_mask_lut()
	var rgba := PackedByteArray()
	rgba.resize(n * 4)
	for i in range(n):
		var d: int = dist[i]
		var val: int = lut[4 if d >= 4 else d]
		var p := i * 4
		rgba[p] = val
		rgba[p + 1] = val
		rgba[p + 2] = val
		rgba[p + 3] = 255

	return Image.create_from_data(mw, mh, false, Image.FORMAT_RGBA8, rgba)

func _sync_dirty_fog_mask_fast(dirty_cells: Array[Vector2i]) -> void:
	if _fog_of_war == null or dirty_cells.is_empty():
		return
	var mw := _get_fog_width()
	var mh := _get_fog_height()
	if _fog_mask_img == null or _fog_mask_img.get_width() != mw or _fog_mask_img.get_height() != mh:
		_fog_mask_img = _sync_full_fog_mask_fast()
		_upload_fog_mask()
		return

	var min_x := mw - 1
	var max_x := 0
	var min_y := mh - 1
	var max_y := 0
	for c in dirty_cells:
		var cx := clampi(c.x, 0, mw - 1)
		var cy := clampi(c.y, 0, mh - 1)
		if cx < min_x: min_x = cx
		if cx > max_x: max_x = cx
		if cy < min_y: min_y = cy
		if cy > max_y: max_y = cy

	# Write region padded by 3 around dirty cells; read region padded by +3 more for exact L1 boundary distances.
	var write_x0 := maxi(0, min_x - 3)
	var write_y0 := maxi(0, min_y - 3)
	var write_x1 := mini(mw - 1, max_x + 3)
	var write_y1 := mini(mh - 1, max_y + 3)

	var pad_x0 := maxi(0, write_x0 - 3)
	var pad_y0 := maxi(0, write_y0 - 3)
	var pad_x1 := mini(mw - 1, write_x1 + 3)
	var pad_y1 := mini(mh - 1, write_y1 + 3)

	var rw := pad_x1 - pad_x0 + 1
	var rh := pad_y1 - pad_y0 + 1
	var dist := PackedByteArray()
	dist.resize(rw * rh)

	var grid: Array = _fog_of_war._grid
	for lx in range(rw):
		var gx := pad_x0 + lx
		var col: Array = grid[gx]
		for ly in range(rh):
			var gy := pad_y0 + ly
			dist[ly * rw + lx] = 4 if int(col[gy]) == FogOfWar.State.UNEXPLORED else 0

	for ly in range(rh):
		var row := ly * rw
		for lx in range(rw):
			var idx := row + lx
			var d: int = dist[idx]
			if d == 0:
				continue
			if lx > 0:
				var dl: int = dist[idx - 1] + 1
				if dl < d:
					d = dl
			if ly > 0:
				var du: int = dist[idx - rw] + 1
				if du < d:
					d = du
			dist[idx] = d

	for ly in range(rh - 1, -1, -1):
		var row := ly * rw
		for lx in range(rw - 1, -1, -1):
			var idx := row + lx
			var d: int = dist[idx]
			if d <= 1:
				continue
			if lx + 1 < rw:
				var dr: int = dist[idx + 1] + 1
				if dr < d:
					d = dr
			if ly + 1 < rh:
				var dd: int = dist[idx + rw] + 1
				if dd < d:
					d = dd
			dist[idx] = d

	var lut := _ensure_mask_lut()
	for gy in range(write_y0, write_y1 + 1):
		var ly := gy - pad_y0
		for gx in range(write_x0, write_x1 + 1):
			var lx := gx - pad_x0
			var d: int = dist[ly * rw + lx]
			var val: int = lut[4 if d >= 4 else d]
			var f := float(val) / 255.0
			_fog_mask_img.set_pixel(gx, gy, Color(f, f, f, 1.0))

func _upload_fog_mask() -> void:
	if _fog_mask_img == null:
		return
	if _fog_mask_tex == null or _fog_mask_tex.get_width() != _fog_mask_img.get_width() or _fog_mask_tex.get_height() != _fog_mask_img.get_height():
		_fog_mask_tex = ImageTexture.create_from_image(_fog_mask_img)
	else:
		_fog_mask_tex.update(_fog_mask_img)

func _get_layout_key() -> String:
	if _fog_of_war == null:
		return ""
	return "%d:%d:%d:%d" % [_world_seed, _get_fog_width(), _get_fog_height(), _density_preset]

func sync_full() -> void:
	clear_all()
	if _fog_of_war == null:
		_chunk_candidates.clear()
		_active_layout_key = ""
		return
	_fog_mask_img = _sync_full_fog_mask_fast()
	_upload_fog_mask()
	var key := _get_layout_key()
	if key != _active_layout_key or _chunk_candidates.is_empty():
		if _layout_cache.has(key):
			_chunk_candidates = _layout_cache[key]
		else:
			_generate_world_chunk_candidates()
			_layout_cache[key] = _chunk_candidates.duplicate(false)
			_layout_cache_order.append(key)
			if _layout_cache_order.size() > MAX_LAYOUT_CACHE_ENTRIES:
				var oldest: String = _layout_cache_order[0]
				_layout_cache_order.remove_at(0)
				_layout_cache.erase(oldest)
		_active_layout_key = key
	for chunk_coord in _chunk_candidates.keys():
		_rebuild_chunk(chunk_coord)

func update_dirty_cells(dirty_cells: Array[Vector2i]) -> void:
	if _fog_of_war == null or dirty_cells.is_empty():
		return
	_sync_dirty_fog_mask_fast(dirty_cells)
	_upload_fog_mask()
	var chunks_x: int = ceili(float(_get_fog_width()) / float(CHUNK_SIZE))
	var chunks_y: int = ceili(float(_get_fog_height()) / float(CHUNK_SIZE))
	var dirty_chunks: Dictionary = {}
	for cell in dirty_cells:
		var min_cx: int = clampi(floori(float(cell.x - FOOTPRINT_MARGIN) / float(CHUNK_SIZE)), 0, chunks_x - 1)
		var max_cx: int = clampi(floori(float(cell.x + FOOTPRINT_MARGIN) / float(CHUNK_SIZE)), 0, chunks_x - 1)
		var min_cy: int = clampi(floori(float(cell.y - FOOTPRINT_MARGIN) / float(CHUNK_SIZE)), 0, chunks_y - 1)
		var max_cy: int = clampi(floori(float(cell.y + FOOTPRINT_MARGIN) / float(CHUNK_SIZE)), 0, chunks_y - 1)
		for cx in range(min_cx, max_cx + 1):
			for cy in range(min_cy, max_cy + 1):
				dirty_chunks[Vector2i(cx, cy)] = true
	for chunk_coord in dirty_chunks.keys():
		_rebuild_chunk(chunk_coord)

func apply_day_night_tint(continuous_hour: float) -> void:
	var h: float = fposmod(continuous_hour, 24.0)
	var day_tint := Color(1.0, 1.0, 1.0, 0.94)
	var dawn_tint := Color(0.95, 0.96, 1.04, 0.93)
	var dusk_tint := Color(0.84, 0.80, 1.08, 0.94)
	var night_tint := Color(0.68, 0.74, 0.98, 0.96)

	if h < 5.0:
		modulate = night_tint
	elif h < 7.0:
		modulate = night_tint.lerp(dawn_tint, (h - 5.0) / 2.0)
	elif h < 8.0:
		modulate = dawn_tint.lerp(day_tint, h - 7.0)
	elif h < 17.5:
		modulate = day_tint
	elif h < 19.0:
		modulate = day_tint.lerp(dusk_tint, (h - 17.5) / 1.5)
	elif h < 20.5:
		modulate = dusk_tint.lerp(night_tint, (h - 19.0) / 1.5)
	else:
		modulate = night_tint

func _chunk_seed(chunk_coord: Vector2i) -> int:
	var h: int = _world_seed * 73856093
	h = h ^ (chunk_coord.x * 19349663)
	h = h ^ (chunk_coord.y * 83492791)
	h = h ^ (_density_preset * 2654435761)
	return h

func _rebuild_chunk(chunk_coord: Vector2i) -> void:
	if _chunk_nodes.has(chunk_coord):
		var old_sprites: Array = _chunk_nodes[chunk_coord]
		for sp in old_sprites:
			if is_instance_valid(sp):
				var node := sp as Node
				if node.get_parent() == self:
					remove_child(node)
				node.queue_free()
		_chunk_nodes.erase(chunk_coord)

	if _fog_of_war == null or _textures.size() < 3:
		return

	var candidates: Array = _chunk_candidates.get(chunk_coord, [])
	if candidates.is_empty():
		return

	var fg_mat: ShaderMaterial = _get_foreground_cloud_material()
	var spawned: Array[Sprite2D] = []
	for cand in candidates:
		var pos: Vector2 = cand["pos"]
		var kind: int = cand["kind"]
		var sc: float = cand["scale"]
		if not _is_opaque_footprint_unexplored(pos, kind, sc):
			continue
		var tex: Texture2D = _textures[kind]
		if tex == null:
			continue
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sp.material = fg_mat
		sp.position = pos
		sp.scale = Vector2(sc, sc)
		add_child(sp)
		spawned.append(sp)

	if not spawned.is_empty():
		_chunk_nodes[chunk_coord] = spawned

func _generate_world_chunk_candidates() -> void:
	_chunk_candidates.clear()
	if _fog_of_war == null:
		return

	var mw: int = _get_fog_width()
	var mh: int = _get_fog_height()
	var area_scale: float = float(mw * mh) / (128.0 * 128.0)
	var preset_mult: float = 1.0
	if _density_preset == DensityPreset.DENSE:
		preset_mult = 1.35
	elif _density_preset == DensityPreset.LOOSE:
		preset_mult = 0.65

	var target_banks: int = maxi(1, roundi(82.0 * area_scale * preset_mult))
	var target_bridges: int = maxi(1, roundi(68.0 * area_scale * preset_mult))

	var rng := RandomNumberGenerator.new()
	rng.seed = _world_seed * 31337 + 13 + _density_preset * 7919

	var min_x: float = -float(mh) * IsoMath.HALF_WIDTH + 60.0
	var max_x: float = float(mw) * IsoMath.HALF_WIDTH - 60.0
	var min_y: float = 60.0
	var max_y: float = float(mw + mh) * IsoMath.HALF_HEIGHT - 60.0
	if max_x <= min_x:
		min_x = -float(mh) * IsoMath.HALF_WIDTH * 0.5
		max_x = float(mw) * IsoMath.HALF_WIDTH * 0.5
	if max_y <= min_y:
		min_y = 16.0
		max_y = float(mw + mh) * IsoMath.HALF_HEIGHT - 16.0

	var bank_centers: Array[Dictionary] = []
	for _attempt in range(target_banks * 16):
		if bank_centers.size() >= target_banks:
			break
		var bpos := Vector2(rng.randf_range(min_x, max_x), rng.randf_range(min_y, max_y))
		if not IsoMath.is_in_bounds(IsoMath.local_to_map(bpos), mw, mh):
			continue
		var min_sep: float = rng.randf_range(152.0, 236.0)
		var ok: bool = true
		for prev in bank_centers:
			if bpos.distance_to(prev["pos"]) < min_sep:
				ok = false
				break
		if not ok:
			continue
		bank_centers.append({
			"pos": bpos,
			"radius": rng.randf_range(120.0, 200.0),
			"angle": rng.randf_range(-0.30, 0.30),
			"supports": rng.randi_range(3, 6),
		})

	var placed: Array[Dictionary] = []
	var weights: Array[float] = [0.34, 0.36, 0.30]
	for bank in bank_centers:
		var cpos: Vector2 = bank["pos"]
		var radius: float = bank["radius"]
		var angle: float = bank["angle"]
		var target_s: int = bank["supports"]
		var anchor_pos: Vector2 = (cpos + Vector2(rng.randf_range(-16.0, 16.0), rng.randf_range(-8.0, 8.0))).round()
		if not IsoMath.is_in_bounds(IsoMath.local_to_map(anchor_pos), mw, mh):
			anchor_pos = cpos
		_try_record_candidate(placed, anchor_pos, _pick_weighted_diverse_kind(rng, placed, anchor_pos, 130.0, weights, false), snappedf(rng.randf_range(1.04, 1.18), 0.01), 38.0)
		var sup_placed: int = 0
		for _m in range(target_s * 6):
			if sup_placed >= target_s:
				break
			var r_frac: float = rng.randf_range(0.30, 1.0)
			var theta: float = rng.randf_range(0.0, TAU)
			var m_pos: Vector2 = (cpos + Vector2(cos(theta) * radius * r_frac * 1.18, sin(theta) * radius * r_frac * 0.54).rotated(angle)).round()
			if not IsoMath.is_in_bounds(IsoMath.local_to_map(m_pos), mw, mh):
				continue
			if _try_record_candidate(placed, m_pos, _pick_weighted_diverse_kind(rng, placed, m_pos, 125.0, weights, false), _pick_varied_scale(rng, placed, m_pos, 0.88, 1.10), rng.randf_range(50.0, 74.0)):
				sup_placed += 1

	var bridge_count: int = 0
	for _b in range(target_bridges * 14):
		if bridge_count >= target_bridges or placed.is_empty():
			break
		var host: Dictionary = placed[rng.randi_range(0, placed.size() - 1)]
		var dist_h: float = rng.randf_range(64.0, 178.0)
		var ang: float = rng.randf_range(-0.45, 0.45) + (0.0 if rng.randf() < 0.5 else PI)
		var bpos: Vector2 = ((host["pos"] as Vector2) + Vector2(cos(ang) * dist_h, sin(ang) * dist_h * 0.58)).round()
		if not IsoMath.is_in_bounds(IsoMath.local_to_map(bpos), mw, mh):
			continue
		if _try_record_candidate(placed, bpos, _pick_weighted_diverse_kind(rng, placed, bpos, 130.0, weights, true), _pick_varied_scale(rng, placed, bpos, 0.82, 0.98), 68.0):
			bridge_count += 1

	var chunks_x: int = ceili(float(mw) / float(CHUNK_SIZE))
	var chunks_y: int = ceili(float(mh) / float(CHUNK_SIZE))
	for cand in placed:
		var cell: Vector2i = IsoMath.local_to_map(cand["pos"])
		var cx: int = clampi(floori(float(cell.x) / float(CHUNK_SIZE)), 0, chunks_x - 1)
		var cy: int = clampi(floori(float(cell.y) / float(CHUNK_SIZE)), 0, chunks_y - 1)
		var chunk_coord := Vector2i(cx, cy)
		if not _chunk_candidates.has(chunk_coord):
			_chunk_candidates[chunk_coord] = []
		(_chunk_candidates[chunk_coord] as Array).append(cand)

static func _pick_weighted_diverse_kind(rng: RandomNumberGenerator, placed: Array[Dictionary], pos: Vector2, radius: float, weights: Array[float], prefer_bridge: bool) -> int:
	if prefer_bridge and rng.randf() < 0.58:
		return CloudKind.ASYMMETRICAL_CLUSTER
	var blocked: Dictionary = {}
	var nearest_kind: int = -1
	var nearest_d: float = 1e9
	for p in placed:
		var d: float = pos.distance_to(p["pos"])
		if d < radius:
			blocked[p["kind"]] = true
		if d < nearest_d:
			nearest_d = d
			nearest_kind = p["kind"]
	var avail: Array[int] = []
	var w_sum: float = 0.0
	for k in range(3):
		if not blocked.has(k):
			avail.append(k)
			w_sum += float(weights[k])
	if not avail.is_empty():
		var r: float = rng.randf() * w_sum
		var acc: float = 0.0
		for k in avail:
			acc += float(weights[k])
			if r <= acc:
				return k
		return avail[avail.size() - 1]
	return (nearest_kind + rng.randi_range(1, 2)) % 3 if nearest_kind >= 0 else rng.randi_range(0, 2)

static func _pick_varied_scale(rng: RandomNumberGenerator, placed: Array[Dictionary], pos: Vector2, s_min: float, s_max: float) -> float:
	var nearest_scale: float = -1.0
	var nearest_d: float = 1e9
	for p in placed:
		var d: float = pos.distance_to(p["pos"])
		if d < 115.0 and d < nearest_d:
			nearest_d = d
			nearest_scale = p["scale"]
	for _try in range(6):
		var s: float = snappedf(rng.randf_range(s_min, s_max), 0.01)
		if nearest_scale < 0.0 or absf(s - nearest_scale) >= 0.07:
			return s
	return snappedf(rng.randf_range(s_min, s_max), 0.01)

static func _try_record_candidate(placed: Array[Dictionary], pos: Vector2, kind: int, sc: float, min_dist: float) -> bool:
	for p in placed:
		if pos.distance_to(p["pos"]) < min_dist:
			return false
	placed.append({"pos": pos, "kind": kind, "scale": sc})
	return true

func _is_opaque_footprint_unexplored(center_px: Vector2, kind: int, sc: float) -> bool:
	if _fog_of_war == null:
		return false
	var pts: PackedVector2Array = _opaque_pts_cache[kind] if kind < _opaque_pts_cache.size() else PackedVector2Array()
	if pts.is_empty():
		var cell := IsoMath.local_to_map(center_px)
		return IsoMath.is_in_bounds(cell, _get_fog_width(), _get_fog_height()) and _fog_of_war.is_unexplored(cell)

	var uv_bounds: Vector4 = _opaque_uv_bounds_cache[kind]
	var cu: float = (center_px.x / IsoMath.TILE_WIDTH) + (center_px.y / IsoMath.TILE_HEIGHT)
	var cv: float = (center_px.y / IsoMath.TILE_HEIGHT) - (center_px.x / IsoMath.TILE_WIDTH)
	var u0: int = int(floor(cu + uv_bounds.x * sc + 0.5))
	var u1: int = int(floor(cu + uv_bounds.y * sc + 0.5))
	var v0: int = int(floor(cv + uv_bounds.z * sc + 0.5))
	var v1: int = int(floor(cv + uv_bounds.w * sc + 0.5))

	var mw: int = _get_fog_width()
	var mh: int = _get_fog_height()
	var gx0: int = maxi(0, u0)
	var gx1: int = mini(mw - 1, u1)
	var gy0: int = maxi(0, v0)
	var gy1: int = mini(mh - 1, v1)
	if gx0 > gx1 or gy0 > gy1:
		return false

	var grid: Array = _fog_of_war._grid
	var any_explored_in_bbox: bool = false
	for gx in range(gx0, gx1 + 1):
		var col: Array = grid[gx]
		for gy in range(gy0, gy1 + 1):
			if int(col[gy]) != FogOfWar.State.UNEXPLORED:
				any_explored_in_bbox = true
				break
		if any_explored_in_bbox:
			break

	if not any_explored_in_bbox:
		if u0 >= 0 and u1 < mw and v0 >= 0 and v1 < mh:
			return true
		for off in pts:
			var p: Vector2 = center_px + off * sc
			var u: float = (p.x / IsoMath.TILE_WIDTH) + (p.y / IsoMath.TILE_HEIGHT)
			var v: float = (p.y / IsoMath.TILE_HEIGHT) - (p.x / IsoMath.TILE_WIDTH)
			var gx: int = int(floor(u + 0.5))
			var gy: int = int(floor(v + 0.5))
			if gx >= 0 and gx < mw and gy >= 0 and gy < mh:
				return true
		return false

	var any_in_bounds: bool = false
	for off in pts:
		var p: Vector2 = center_px + off * sc
		var u: float = (p.x / IsoMath.TILE_WIDTH) + (p.y / IsoMath.TILE_HEIGHT)
		var v: float = (p.y / IsoMath.TILE_HEIGHT) - (p.x / IsoMath.TILE_WIDTH)
		var gx: int = int(floor(u + 0.5))
		var gy: int = int(floor(v + 0.5))
		if gx >= 0 and gx < mw and gy >= 0 and gy < mh:
			any_in_bounds = true
			if int(grid[gx][gy]) != FogOfWar.State.UNEXPLORED:
				return false
	return any_in_bounds

static func _continuous_map_to_local(fx: float, fy: float) -> Vector2:
	return Vector2(
		(fx - fy) * IsoMath.HALF_WIDTH,
		(fx + fy) * IsoMath.HALF_HEIGHT
	)
