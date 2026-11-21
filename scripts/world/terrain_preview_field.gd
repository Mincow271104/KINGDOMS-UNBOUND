class_name TerrainPreviewField
extends RefCounted
## Derived visual terrain-preview SDF & envelope texture generator (C1.9.2).
##
## Strictly visual presentation data: never mutates FogOfWar and never
## grants gameplay discovery or entity visibility.

enum SourceCategory {
	TOWN_HALL = 0,
	HUNTER_SCOUT = 1,
	SOLDIER = 2,
}

const PREVIEW_SMOOTH_K: float = 135.0
const CORE_SMOOTH_K: float = 95.0
const PREVIEW_SD_CLAMP: float = 300.0
const PREVIEW_SD_RANGE: float = 600.0
const CORE_SD_CLAMP: float = 200.0
const CORE_SD_RANGE: float = 400.0
const DEFAULT_OVAL_X: float = 1.18

const DEFAULT_TOWN_HALL_PREVIEW_RADIUS: float = 310.0
const DEFAULT_TOWN_HALL_CORE_RADIUS: float = 165.0
const DEFAULT_HUNTER_PREVIEW_RADIUS: float = 185.0
const DEFAULT_HUNTER_CORE_RADIUS: float = 0.0
const DEFAULT_SOLDIER_PREVIEW_RADIUS: float = 165.0
const DEFAULT_SOLDIER_CORE_RADIUS: float = 95.0

const LOBE_MAX_BASE: float = 1.08
const LOBE_MAX_DIRECTIONAL: float = 1.19

var map_width: int = 128
var map_height: int = 128
var resolution_scale: int = 1
var tex_width: int = 128
var tex_height: int = 128
var world_seed: int = 0

var _fog_of_war: FogOfWar = null
var _sources: Dictionary = {} # id: String -> Dictionary
var _ordered_ids: Array[String] = [] # deterministic iteration order
var _committed_sources: Dictionary = {} # snapshot as of last buffer build/flush
var _dirty_all: bool = true
var _gpu_dirty: bool = true

var _phase_a: float = 0.4
var _phase_b: float = -0.9
var _cos_a: float = 0.0
var _sin_a: float = 0.0
var _cos_b: float = 0.0
var _sin_b: float = 0.0

var _buffer: PackedByteArray = PackedByteArray()
var _image: Image = null
var _texture: ImageTexture = null
var _last_profile_stats: Dictionary = {}


func configure(width: int, height: int, seed_value: int, res_scale: int = 1, fog_of_war: FogOfWar = null) -> void:
	map_width = maxi(1, width)
	map_height = maxi(1, height)
	resolution_scale = clampi(res_scale, 1, 4)
	tex_width = map_width * resolution_scale
	tex_height = map_height * resolution_scale
	world_seed = seed_value
	_fog_of_war = fog_of_war

	# Deterministic bounded phase variation from world_seed
	var h1: float = float((world_seed * 1103515245 + 12345) & 0xFFFF) / 65535.0
	var h2: float = float(((world_seed >> 8) * 1664525 + 1013904223) & 0xFFFF) / 65535.0
	_phase_a = 0.4 + (h1 - 0.5) * 0.6
	_phase_b = -0.9 + (h2 - 0.5) * 0.6
	_cos_a = cos(_phase_a)
	_sin_a = sin(_phase_a)
	_cos_b = cos(_phase_b)
	_sin_b = sin(_phase_b)

	_buffer.resize(tex_width * tex_height * 4)
	_buffer.fill(255)
	_image = Image.create_from_data(tex_width, tex_height, false, Image.FORMAT_RGBA8, _buffer)
	_texture = ImageTexture.create_from_image(_image)
	_committed_sources.clear()
	_dirty_all = true
	_gpu_dirty = true


func set_fog_of_war(fog_of_war: FogOfWar) -> void:
	_fog_of_war = fog_of_war


func clear_sources() -> void:
	if not _sources.is_empty():
		_gpu_dirty = true
	_sources.clear()
	_ordered_ids.clear()
	_dirty_all = true


func register_source(
	id: String,
	category: int,
	cell: Vector2i,
	preview_radius_px: float = -1.0,
	core_radius_px: float = -1.0,
	dir: Vector2 = Vector2.ZERO,
	oval_x: float = DEFAULT_OVAL_X
) -> bool:
	if id.is_empty() or _sources.has(id):
		return false
	upsert_source(id, category, cell, preview_radius_px, core_radius_px, dir, oval_x)
	return true


func upsert_source(
	id: String,
	category: int,
	cell: Vector2i,
	preview_radius_px: float = -1.0,
	core_radius_px: float = -1.0,
	dir: Vector2 = Vector2.ZERO,
	oval_x: float = DEFAULT_OVAL_X
) -> void:
	if id.is_empty():
		return
	var clamped_cell := _clamp_cell(cell)
	var p_rad: float = preview_radius_px if preview_radius_px >= 0.0 else _default_preview_radius(category)
	var c_rad: float = core_radius_px if core_radius_px >= 0.0 else _default_core_radius(category)
	var norm_dir := dir.normalized() if dir.length_squared() > 0.0001 else Vector2.ZERO
	# Subtle directional bias only for Hunter/Scout
	if category != SourceCategory.HUNTER_SCOUT:
		norm_dir = Vector2.ZERO

	if not _sources.has(id):
		_ordered_ids.append(id)

	var ox := maxf(0.5, oval_x)
	var has_dir := norm_dir.length_squared() > 0.0001
	var lobe_max := LOBE_MAX_DIRECTIONAL if has_dir else LOBE_MAX_BASE
	var p_reach := maxf(0.0, p_rad) * lobe_max + PREVIEW_SD_CLAMP + PREVIEW_SMOOTH_K * 1.5
	var c_reach := maxf(0.0, c_rad) * lobe_max + CORE_SD_CLAMP + CORE_SMOOTH_K * 1.5
	var reach_y := maxf(p_reach, c_reach) if (p_rad > 0.0 or c_rad > 0.0) else 0.0

	var new_src := {
		"id": id,
		"category": category,
		"cell": clamped_cell,
		"center_iso": IsoMath.map_to_local(clamped_cell),
		"preview_radius_px": maxf(0.0, p_rad),
		"core_radius_px": maxf(0.0, c_rad),
		"dir": norm_dir,
		"has_dir": has_dir,
		"oval_x": ox,
		"inv_oval_x": 1.0 / ox,
		"reach_y": reach_y,
		"reach_sq": reach_y * reach_y,
	}
	if not _sources.has(id) or not _sources_equal(_sources[id], new_src):
		_gpu_dirty = true
	_sources[id] = new_src


func update_source(
	id: String,
	cell: Vector2i,
	preview_radius_px: float = -1.0,
	core_radius_px: float = -1.0,
	dir: Vector2 = Vector2.ZERO,
	oval_x: float = -1.0
) -> bool:
	if not _sources.has(id):
		return false
	var existing: Dictionary = _sources[id]
	var cat: int = int(existing["category"])
	var p_rad: float = preview_radius_px if preview_radius_px >= 0.0 else float(existing["preview_radius_px"])
	var c_rad: float = core_radius_px if core_radius_px >= 0.0 else float(existing["core_radius_px"])
	var ox: float = oval_x if oval_x > 0.0 else float(existing["oval_x"])
	upsert_source(id, cat, cell, p_rad, c_rad, dir, ox)
	return true


func remove_source(id: String) -> bool:
	if not _sources.has(id):
		return false
	_sources.erase(id)
	_ordered_ids.erase(id)
	_gpu_dirty = true
	return true


func has_source(id: String) -> bool:
	return _sources.has(id)


func get_source(id: String) -> Dictionary:
	if not _sources.has(id):
		return {}
	return (_sources[id] as Dictionary).duplicate()


func get_source_ids() -> Array[String]:
	return _ordered_ids.duplicate()


func get_source_count() -> int:
	return _sources.size()


func is_gpu_dirty() -> bool:
	return _gpu_dirty


func mark_gpu_synced() -> void:
	_gpu_dirty = false


func get_phase_offsets() -> Vector2:
	return Vector2(_phase_a, _phase_b)


func pack_sources_into_rgba32f(img: Image, max_slots: int = 128) -> Dictionary:
	var cap := maxi(1, max_slots)
	if img == null or img.get_width() != cap or img.get_height() != 2 or img.get_format() != Image.FORMAT_RGBAF:
		push_error("[TerrainPreviewField] pack_sources_into_rgba32f requires %dx2 FORMAT_RGBAF Image." % cap)
		return {"count": 0, "overflow_count": 0, "total_sources": _ordered_ids.size()}

	var total := _ordered_ids.size()
	var selected_ids: Array[String] = []
	var overflow_count := 0
	if total <= cap:
		selected_ids = _ordered_ids.duplicate()
	else:
		overflow_count = total - cap
		push_warning("[TerrainPreviewField] Source count (%d) exceeds GPU slot capacity (%d); prioritizing TOWN_HALL -> HUNTER_SCOUT -> SOLDIER." % [total, cap])
		for cat in [SourceCategory.TOWN_HALL, SourceCategory.HUNTER_SCOUT, SourceCategory.SOLDIER]:
			for id in _ordered_ids:
				if selected_ids.size() >= cap:
					break
				if int(_sources[id]["category"]) == cat:
					selected_ids.append(id)
			if selected_ids.size() >= cap:
				break

	var count := selected_ids.size()
	for i in range(count):
		var s: Dictionary = _sources[selected_ids[i]]
		var c: Vector2 = s["center_iso"]
		var d: Vector2 = s["dir"]
		var has_d := 1.0 if bool(s["has_dir"]) else 0.0
		img.set_pixel(i, 0, Color(c.x, c.y, float(s["preview_radius_px"]), float(s["core_radius_px"])))
		img.set_pixel(i, 1, Color(d.x, d.y, float(s["oval_x"]), has_d))

	for i in range(count, cap):
		img.set_pixel(i, 0, Color(0.0, 0.0, 0.0, 0.0))
		img.set_pixel(i, 1, Color(0.0, 0.0, 1.18, 0.0))

	return {
		"count": count,
		"overflow_count": overflow_count,
		"total_sources": total,
	}


func has_pending_dirty_rect() -> bool:
	if _dirty_all:
		return true
	return not _collect_changed_sources().is_empty()


func get_pending_dirty_rect() -> Rect2i:
	if _dirty_all:
		return Rect2i(0, 0, tex_width, tex_height)
	var changed := _collect_changed_sources()
	if changed.is_empty():
		return Rect2i()
	var merged := Rect2i()
	var has_r := false
	for src in changed:
		var r := _compute_source_texel_rect(src)
		if r.size.x > 0 and r.size.y > 0:
			merged = r if not has_r else merged.merge(r)
			has_r = true
	return merged


func get_last_profile_stats() -> Dictionary:
	return _last_profile_stats.duplicate()


func apply_incremental_updates() -> Rect2i:
	if _dirty_all:
		rebuild_full()
		return Rect2i(0, 0, tex_width, tex_height)

	var t_build0 := Time.get_ticks_usec()
	var changed := _collect_changed_sources()
	if changed.is_empty():
		var build_ms_empty := float(Time.get_ticks_usec() - t_build0) / 1000.0
		_last_profile_stats = {
			"dirty_rect": Rect2i(),
			"dirty_texels": 0,
			"total_texels": tex_width * tex_height,
			"dirty_pct": 0.0,
			"candidate_sources": 0,
			"sd_evaluations": 0,
			"dirty_build_ms": build_ms_empty,
			"eval_ms": 0.0,
			"upload_ms": 0.0,
		}
		return Rect2i()

	var merged_rect := Rect2i()
	var has_rect := false
	var ellipse_cx := PackedFloat32Array()
	var ellipse_cy := PackedFloat32Array()
	var ellipse_inv_ox := PackedFloat32Array()
	var ellipse_reach_sq := PackedFloat32Array()

	for src in changed:
		var r := _compute_source_texel_rect(src)
		if r.size.x > 0 and r.size.y > 0:
			merged_rect = r if not has_rect else merged_rect.merge(r)
			has_rect = true
			var c_iso: Vector2 = src["center_iso"]
			ellipse_cx.append(c_iso.x)
			ellipse_cy.append(c_iso.y)
			ellipse_inv_ox.append(float(src["inv_oval_x"]))
			ellipse_reach_sq.append(float(src["reach_sq"]))

	var dirty_build_ms := float(Time.get_ticks_usec() - t_build0) / 1000.0
	if not has_rect:
		_sync_committed_sources()
		return Rect2i()

	var x0 := merged_rect.position.x
	var y0 := merged_rect.position.y
	var x1 := x0 + merged_rect.size.x - 1
	var y1 := y0 + merged_rect.size.y - 1

	var t_eval0 := Time.get_ticks_usec()
	var eval_stats := _evaluate_rect_filtered(x0, y0, x1, y1, ellipse_cx, ellipse_cy, ellipse_inv_ox, ellipse_reach_sq)
	var eval_ms := float(Time.get_ticks_usec() - t_eval0) / 1000.0

	var t_up0 := Time.get_ticks_usec()
	_image.set_data(tex_width, tex_height, false, Image.FORMAT_RGBA8, _buffer)
	if _texture != null:
		_texture.update(_image)
	else:
		_texture = ImageTexture.create_from_image(_image)
	var upload_ms := float(Time.get_ticks_usec() - t_up0) / 1000.0

	_sync_committed_sources()

	var dirty_texels: int = int(eval_stats["evaluated_texels"])
	var total_texels := tex_width * tex_height
	_last_profile_stats = {
		"dirty_rect": merged_rect,
		"dirty_texels": dirty_texels,
		"total_texels": total_texels,
		"dirty_pct": (float(dirty_texels) / float(maxi(1, total_texels))) * 100.0,
		"candidate_sources": int(eval_stats["candidate_sources"]),
		"sd_evaluations": int(eval_stats["sd_evaluations"]),
		"dirty_build_ms": dirty_build_ms,
		"eval_ms": eval_ms,
		"upload_ms": upload_ms,
	}
	return merged_rect


func update_dirty_rect(texel_rect: Rect2i) -> void:
	if tex_width <= 0 or tex_height <= 0 or _buffer.is_empty():
		return
	var x0 := clampi(texel_rect.position.x, 0, tex_width - 1)
	var y0 := clampi(texel_rect.position.y, 0, tex_height - 1)
	var x1 := clampi(texel_rect.position.x + texel_rect.size.x - 1, 0, tex_width - 1)
	var y1 := clampi(texel_rect.position.y + texel_rect.size.y - 1, 0, tex_height - 1)
	if x1 < x0 or y1 < y0:
		return

	var empty_f := PackedFloat32Array()
	var t_eval0 := Time.get_ticks_usec()
	var eval_stats := _evaluate_rect_filtered(x0, y0, x1, y1, empty_f, empty_f, empty_f, empty_f)
	var eval_ms := float(Time.get_ticks_usec() - t_eval0) / 1000.0

	var t_up0 := Time.get_ticks_usec()
	_image.set_data(tex_width, tex_height, false, Image.FORMAT_RGBA8, _buffer)
	if _texture != null:
		_texture.update(_image)
	else:
		_texture = ImageTexture.create_from_image(_image)
	var upload_ms := float(Time.get_ticks_usec() - t_up0) / 1000.0

	var dw := x1 - x0 + 1
	var dh := y1 - y0 + 1
	var dirty_texels := dw * dh
	var total_texels := tex_width * tex_height
	_last_profile_stats = {
		"dirty_rect": Rect2i(x0, y0, dw, dh),
		"dirty_texels": dirty_texels,
		"total_texels": total_texels,
		"dirty_pct": (float(dirty_texels) / float(maxi(1, total_texels))) * 100.0,
		"candidate_sources": int(eval_stats["candidate_sources"]),
		"sd_evaluations": int(eval_stats["sd_evaluations"]),
		"dirty_build_ms": 0.0,
		"eval_ms": eval_ms,
		"upload_ms": upload_ms,
	}


func rebuild_full() -> void:
	if tex_width <= 0 or tex_height <= 0:
		return
	if _buffer.size() != tex_width * tex_height * 4:
		_buffer.resize(tex_width * tex_height * 4)

	var empty_f := PackedFloat32Array()
	var t_eval0 := Time.get_ticks_usec()
	var eval_stats := _evaluate_rect_filtered(0, 0, tex_width - 1, tex_height - 1, empty_f, empty_f, empty_f, empty_f)
	var eval_ms := float(Time.get_ticks_usec() - t_eval0) / 1000.0

	var t_up0 := Time.get_ticks_usec()
	_image.set_data(tex_width, tex_height, false, Image.FORMAT_RGBA8, _buffer)
	if _texture != null:
		_texture.update(_image)
	else:
		_texture = ImageTexture.create_from_image(_image)
	var upload_ms := float(Time.get_ticks_usec() - t_up0) / 1000.0

	_sync_committed_sources()
	_dirty_all = false

	var total_texels := tex_width * tex_height
	_last_profile_stats = {
		"dirty_rect": Rect2i(0, 0, tex_width, tex_height),
		"dirty_texels": total_texels,
		"total_texels": total_texels,
		"dirty_pct": 100.0,
		"candidate_sources": int(eval_stats["candidate_sources"]),
		"sd_evaluations": int(eval_stats["sd_evaluations"]),
		"dirty_build_ms": 0.0,
		"eval_ms": eval_ms,
		"upload_ms": upload_ms,
	}


func get_envelope_image() -> Image:
	return _image


func get_envelope_texture() -> ImageTexture:
	return _texture


func get_memory_bytes() -> int:
	return _buffer.size() * 2 # buffer + backing Image RGBA8


func evaluate_preview_sd_at_iso(p_iso: Vector2) -> float:
	var p_sd := 9999.0
	for id in _ordered_ids:
		var src: Dictionary = _sources[id]
		var r_px: float = float(src["preview_radius_px"])
		if r_px <= 0.0:
			continue
		var d := _eval_source_sd(p_iso, src["center_iso"], r_px, float(src["oval_x"]), src["dir"])
		p_sd = d if p_sd > 9000.0 else _smin(p_sd, d, PREVIEW_SMOOTH_K)
	return p_sd


func evaluate_core_sd_at_iso(p_iso: Vector2) -> float:
	var c_sd := 9999.0
	for id in _ordered_ids:
		var src: Dictionary = _sources[id]
		var r_px: float = float(src["core_radius_px"])
		if r_px <= 0.0:
			continue
		var d := _eval_source_sd(p_iso, src["center_iso"], r_px, float(src["oval_x"]), src["dir"])
		c_sd = d if c_sd > 9000.0 else _smin(c_sd, d, CORE_SMOOTH_K)
	return c_sd


func is_cell_in_preview(cell: Vector2i) -> bool:
	return evaluate_preview_sd_at_iso(IsoMath.map_to_local(cell)) <= 0.0


func _clamp_cell(cell: Vector2i) -> Vector2i:
	return Vector2i(clampi(cell.x, 0, map_width - 1), clampi(cell.y, 0, map_height - 1))


static func _default_preview_radius(category: int) -> float:
	match category:
		SourceCategory.TOWN_HALL:
			return DEFAULT_TOWN_HALL_PREVIEW_RADIUS
		SourceCategory.HUNTER_SCOUT:
			return DEFAULT_HUNTER_PREVIEW_RADIUS
		SourceCategory.SOLDIER:
			return DEFAULT_SOLDIER_PREVIEW_RADIUS
	return DEFAULT_SOLDIER_PREVIEW_RADIUS


static func _default_core_radius(category: int) -> float:
	match category:
		SourceCategory.TOWN_HALL:
			return DEFAULT_TOWN_HALL_CORE_RADIUS
		SourceCategory.HUNTER_SCOUT:
			return DEFAULT_HUNTER_CORE_RADIUS
		SourceCategory.SOLDIER:
			return DEFAULT_SOLDIER_CORE_RADIUS
	return 0.0


static func _smin(a: float, b: float, k: float) -> float:
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)


func _eval_source_sd(p_iso: Vector2, c_iso: Vector2, r_px: float, oval_x: float, dir: Vector2) -> float:
	var dx := (p_iso.x - c_iso.x) / oval_x
	var dy := p_iso.y - c_iso.y
	var dist := sqrt(dx * dx + dy * dy)
	var ang := atan2(dy, dx)
	# Bounded low-frequency irregularity (max +/- 8%, zero narrow tails)
	var lobe := 1.0 + 0.045 * sin(ang * 2.0 + _phase_a) + 0.035 * cos(ang * 3.0 + _phase_b)
	if dir.length_squared() > 0.0001 and dist > 1.0:
		var align := maxf(0.0, (dx * dir.x + dy * dir.y) / dist)
		lobe += 0.11 * align
	return dist - r_px * lobe


func _sync_committed_sources() -> void:
	_committed_sources.clear()
	for id in _ordered_ids:
		_committed_sources[id] = _sources[id]


func _sources_equal(a: Dictionary, b: Dictionary) -> bool:
	return (
		a["cell"] == b["cell"]
		and is_equal_approx(float(a["preview_radius_px"]), float(b["preview_radius_px"]))
		and is_equal_approx(float(a["core_radius_px"]), float(b["core_radius_px"]))
		and a["dir"] == b["dir"]
		and is_equal_approx(float(a["oval_x"]), float(b["oval_x"]))
	)


func _collect_changed_sources() -> Array[Dictionary]:
	var changed: Array[Dictionary] = []
	for id in _sources.keys():
		var cur: Dictionary = _sources[id]
		if not _committed_sources.has(id):
			changed.append(cur)
		else:
			var prev: Dictionary = _committed_sources[id]
			if not _sources_equal(cur, prev):
				changed.append(prev)
				changed.append(cur)
	for id in _committed_sources.keys():
		if not _sources.has(id):
			changed.append(_committed_sources[id])
	return changed


func _compute_source_texel_rect(src: Dictionary) -> Rect2i:
	var reach_y: float = float(src["reach_y"])
	if reach_y <= 0.0:
		return Rect2i()
	var ox: float = float(src["oval_x"])
	var c_iso: Vector2 = src["center_iso"]
	# Exact elliptical projection onto rotated isometric (u_grid, v_grid) axes:
	# max(a * cos(t) + b * sin(t)) = sqrt(a^2 + b^2)
	var a_u := (reach_y * ox) / IsoMath.TILE_WIDTH
	var b_u := reach_y / IsoMath.TILE_HEIGHT
	var half_uv := sqrt(a_u * a_u + b_u * b_u)

	var cu := (c_iso.x / IsoMath.TILE_WIDTH) + (c_iso.y / IsoMath.TILE_HEIGHT)
	var cv := (c_iso.y / IsoMath.TILE_HEIGHT) - (c_iso.x / IsoMath.TILE_WIDTH)

	var scale_f := float(resolution_scale)
	var min_tx := clampi(int(floor((cu - half_uv + 0.5) * scale_f - 0.5)) - 1, 0, tex_width - 1)
	var max_tx := clampi(int(ceil((cu + half_uv + 0.5) * scale_f - 0.5)) + 1, 0, tex_width - 1)
	var min_ty := clampi(int(floor((cv - half_uv + 0.5) * scale_f - 0.5)) - 1, 0, tex_height - 1)
	var max_ty := clampi(int(ceil((cv + half_uv + 0.5) * scale_f - 0.5)) + 1, 0, tex_height - 1)
	if max_tx < min_tx or max_ty < min_ty:
		return Rect2i()
	return Rect2i(min_tx, min_ty, max_tx - min_tx + 1, max_ty - min_ty + 1)


func _evaluate_rect_filtered(
	x0: int,
	y0: int,
	x1: int,
	y1: int,
	filter_cx: PackedFloat32Array,
	filter_cy: PackedFloat32Array,
	filter_inv_ox: PackedFloat32Array,
	filter_reach_sq: PackedFloat32Array
) -> Dictionary:
	var scale_f := float(resolution_scale)
	var inv_scale := 1.0 / scale_f
	var stride := tex_width * 4

	var rect_corners := [
		_texel_to_iso(x0, y0, inv_scale),
		_texel_to_iso(x1, y0, inv_scale),
		_texel_to_iso(x1, y1, inv_scale),
		_texel_to_iso(x0, y1, inv_scale),
	]
	var iso_min_x := INF
	var iso_min_y := INF
	var iso_max_x := -INF
	var iso_max_y := -INF
	for cp in rect_corners:
		iso_min_x = minf(iso_min_x, cp.x)
		iso_min_y = minf(iso_min_y, cp.y)
		iso_max_x = maxf(iso_max_x, cp.x)
		iso_max_y = maxf(iso_max_y, cp.y)

	var s_cx := PackedFloat32Array()
	var s_cy := PackedFloat32Array()
	var s_prad := PackedFloat32Array()
	var s_crad := PackedFloat32Array()
	var s_inv_ox := PackedFloat32Array()
	var s_dx := PackedFloat32Array()
	var s_dy := PackedFloat32Array()
	var s_has_dir := PackedByteArray()
	var s_reach_sq := PackedFloat32Array()

	for id in _ordered_ids:
		var src: Dictionary = _sources[id]
		var reach_y: float = float(src["reach_y"])
		if reach_y <= 0.0:
			continue
		var c_iso: Vector2 = src["center_iso"]
		var ox: float = float(src["oval_x"])
		var reach_x := reach_y * ox
		if c_iso.x + reach_x >= iso_min_x and c_iso.x - reach_x <= iso_max_x and c_iso.y + reach_y >= iso_min_y and c_iso.y - reach_y <= iso_max_y:
			var dir: Vector2 = src["dir"]
			s_cx.append(c_iso.x)
			s_cy.append(c_iso.y)
			s_prad.append(float(src["preview_radius_px"]))
			s_crad.append(float(src["core_radius_px"]))
			s_inv_ox.append(float(src["inv_oval_x"]))
			s_dx.append(dir.x)
			s_dy.append(dir.y)
			s_has_dir.append(1 if bool(src["has_dir"]) else 0)
			s_reach_sq.append(float(src["reach_sq"]))

	var s_count := s_cx.size()
	var filter_count := filter_cx.size()
	var has_filter := filter_count > 0
	var has_fow := _fog_of_war != null
	const INV_PREVIEW_RANGE := 1.0 / PREVIEW_SD_RANGE
	const INV_CORE_RANGE := 1.0 / CORE_SD_RANGE

	var evaluated_texels := 0
	var sd_evaluations := 0
	var iso_step_x := IsoMath.HALF_WIDTH * inv_scale
	var iso_step_y := IsoMath.HALF_HEIGHT * inv_scale

	for ty in range(y0, y1 + 1):
		var v_grid: float = (float(ty) + 0.5) * inv_scale - 0.5
		var cell_y := clampi(int(floor(v_grid + 0.5)), 0, map_height - 1)
		var row_base := ty * stride
		var u_start: float = (float(x0) + 0.5) * inv_scale - 0.5
		var iso_x: float = (u_start - v_grid) * IsoMath.HALF_WIDTH - iso_step_x
		var iso_y: float = (u_start + v_grid) * IsoMath.HALF_HEIGHT - iso_step_y
		var u_grid: float = u_start - inv_scale
		for tx in range(x0, x1 + 1):
			iso_x += iso_step_x
			iso_y += iso_step_y
			u_grid += inv_scale

			if has_filter:
				var in_changed_ellipse := false
				for f in range(filter_count):
					var fdx := (iso_x - filter_cx[f]) * filter_inv_ox[f]
					var fdy := iso_y - filter_cy[f]
					if fdx * fdx + fdy * fdy <= filter_reach_sq[f]:
						in_changed_ellipse = true
						break
				if not in_changed_ellipse:
					continue

			evaluated_texels += 1
			var p_sd := 9999.0
			var c_sd := 9999.0
			var has_p := false
			var has_c := false

			for i in range(s_count):
				var dx := (iso_x - s_cx[i]) * s_inv_ox[i]
				var dy := iso_y - s_cy[i]
				var d2 := dx * dx + dy * dy
				if d2 > s_reach_sq[i]:
					continue

				sd_evaluations += 1
				var dist := sqrt(d2)
				var lobe := 1.0
				if dist > 0.0001:
					var inv_d := 1.0 / dist
					var ux := dx * inv_d
					var uy := dy * inv_d
					var sin2 := 2.0 * ux * uy
					var cos2 := ux * ux - uy * uy
					var cos3 := (4.0 * ux * ux - 3.0) * ux
					var sin3 := (3.0 - 4.0 * uy * uy) * uy
					lobe += 0.045 * (sin2 * _cos_a + cos2 * _sin_a) + 0.035 * (cos3 * _cos_b - sin3 * _sin_b)
					if s_has_dir[i] != 0 and dist > 1.0:
						var align := maxf(0.0, ux * s_dx[i] + uy * s_dy[i])
						lobe += 0.11 * align
				else:
					lobe += 0.045 * _sin_a + 0.035 * _cos_b

				var pr := s_prad[i]
				if pr > 0.0:
					var dp := dist - pr * lobe
					if not has_p:
						p_sd = dp
						has_p = true
					else:
						var hp := clampf(0.5 + 0.5 * (dp - p_sd) / PREVIEW_SMOOTH_K, 0.0, 1.0)
						p_sd = lerpf(dp, p_sd, hp) - PREVIEW_SMOOTH_K * hp * (1.0 - hp)

				var cr := s_crad[i]
				if cr > 0.0:
					var dc := dist - cr * lobe
					if not has_c:
						c_sd = dc
						has_c = true
					else:
						var hc := clampf(0.5 + 0.5 * (dc - c_sd) / CORE_SMOOTH_K, 0.0, 1.0)
						c_sd = lerpf(dc, c_sd, hc) - CORE_SMOOTH_K * hc * (1.0 - hc)

			var r_f := clampf(0.5 + p_sd * INV_PREVIEW_RANGE, 0.0, 1.0)
			var g_f := clampf(0.5 + c_sd * INV_CORE_RANGE, 0.0, 1.0)
			var b_byte := 0
			if has_fow:
				var cell_x := clampi(int(floor(u_grid + 0.5)), 0, map_width - 1)
				if _fog_of_war.is_explored(Vector2i(cell_x, cell_y)):
					b_byte = 255

			var idx := row_base + tx * 4
			_buffer[idx] = int(roundf(r_f * 255.0))
			_buffer[idx + 1] = int(roundf(g_f * 255.0))
			_buffer[idx + 2] = b_byte
			_buffer[idx + 3] = 255

	return {
		"candidate_sources": s_count,
		"evaluated_texels": evaluated_texels,
		"sd_evaluations": sd_evaluations,
	}


static func _texel_to_iso(tx: int, ty: int, inv_scale: float) -> Vector2:
	var u_grid := (float(tx) + 0.5) * inv_scale - 0.5
	var v_grid := (float(ty) + 0.5) * inv_scale - 0.5
	return Vector2((u_grid - v_grid) * IsoMath.HALF_WIDTH, (u_grid + v_grid) * IsoMath.HALF_HEIGHT)
