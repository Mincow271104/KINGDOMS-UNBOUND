class_name TerrainPreviewRenderer
extends Node
## GPU SubViewport envelope texture generator (C1.9.2 Option B).
##
## Owns a dedicated SubViewport, ColorRect, ShaderMaterial, and 128x2 RGBAF
## source-data texture. Remains UPDATE_DISABLED when idle and triggers
## UPDATE_ONCE only when TerrainPreviewField reports pending GPU changes.

const MAX_SOURCE_SLOTS: int = 128
const ENVELOPE_SHADER_PATH: String = "res://shaders/fog/terrain_preview_envelope.gdshader"

var resolution_scale: int = 1
var map_width: int = 128
var map_height: int = 128

var _field: TerrainPreviewField = null
var _subviewport: SubViewport = null
var _color_rect: ColorRect = null
var _material: ShaderMaterial = null
var _shader: Shader = null

var _source_data_img: Image = null
var _source_data_tex: ImageTexture = null
var _update_pending: bool = false
var _awaiting_post_draw_disable: bool = false
var _gpu_pass_count: int = 0
var _last_stats: Dictionary = {}


func _ready() -> void:
	if not RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.connect(_on_frame_post_draw)


func _exit_tree() -> void:
	cleanup()


func configure(field: TerrainPreviewField, res_scale: int = 1) -> void:
	if field == null:
		push_error("[TerrainPreviewRenderer] configure() requires a valid TerrainPreviewField.")
		return

	_field = field
	resolution_scale = clampi(res_scale, 1, 2)
	map_width = maxi(1, field.map_width)
	map_height = maxi(1, field.map_height)

	_ensure_source_data_resources()
	_ensure_subviewport_resources()

	var target_size := Vector2i(map_width * resolution_scale, map_height * resolution_scale)
	if _subviewport.size != target_size:
		_subviewport.size = target_size
	if _color_rect.size != Vector2(target_size):
		_color_rect.size = Vector2(target_size)

	sync_if_needed(true)


func set_resolution_scale(res_scale: int) -> void:
	var clamped := clampi(res_scale, 1, 2)
	if clamped == resolution_scale and _subviewport != null:
		return
	resolution_scale = clamped
	if _subviewport != null and _field != null:
		var target_size := Vector2i(map_width * resolution_scale, map_height * resolution_scale)
		_subviewport.size = target_size
		_color_rect.size = Vector2(target_size)
		sync_if_needed(true)


func request_update() -> void:
	_update_pending = true


func sync_if_needed(force: bool = false) -> bool:
	if _field == null or _subviewport == null or _material == null:
		return false
	if not force and not _update_pending and not _field.is_gpu_dirty():
		return false

	var t_pack0 := Time.get_ticks_usec()
	var pack_info := _field.pack_sources_into_rgba32f(_source_data_img, MAX_SOURCE_SLOTS)
	var pack_ms := float(Time.get_ticks_usec() - t_pack0) / 1000.0

	var t_up0 := Time.get_ticks_usec()
	_source_data_tex.update(_source_data_img)
	var tex_upload_ms := float(Time.get_ticks_usec() - t_up0) / 1000.0

	var phases := _field.get_phase_offsets()
	_material.set_shader_parameter("source_data_tex", _source_data_tex)
	_material.set_shader_parameter("source_count", int(pack_info["count"]))
	_material.set_shader_parameter("map_size", Vector2(map_width, map_height))
	_material.set_shader_parameter("phase_a", phases.x)
	_material.set_shader_parameter("phase_b", phases.y)

	_subviewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_awaiting_post_draw_disable = true
	_field.mark_gpu_synced()
	_update_pending = false
	_gpu_pass_count += 1

	_last_stats = {
		"pack_ms": pack_ms,
		"tex_upload_ms": tex_upload_ms,
		"source_count": int(pack_info["count"]),
		"overflow_count": int(pack_info["overflow_count"]),
		"total_sources": int(pack_info["total_sources"]),
		"gpu_pass_count": _gpu_pass_count,
		"resolution_scale": resolution_scale,
		"envelope_size": _subviewport.size,
	}
	return true


func get_envelope_texture() -> ViewportTexture:
	if _subviewport == null or not is_instance_valid(_subviewport):
		return null
	return _subviewport.get_texture()


func get_subviewport() -> SubViewport:
	return _subviewport


func get_source_data_texture() -> ImageTexture:
	return _source_data_tex


func is_update_pending() -> bool:
	if _update_pending:
		return true
	return _field != null and _field.is_gpu_dirty()


func get_gpu_pass_count() -> int:
	return _gpu_pass_count


func get_last_stats() -> Dictionary:
	return _last_stats.duplicate()


func get_memory_bytes() -> int:
	# 128x2 RGBAF CPU Image + VRAM ImageTexture (4096 * 2) + SubViewport RGBA8 (w*h*4)
	var src_bytes := MAX_SOURCE_SLOTS * 2 * 16 * 2
	var vp_bytes := (map_width * resolution_scale) * (map_height * resolution_scale) * 4
	return src_bytes + vp_bytes


func _on_frame_post_draw() -> void:
	if not _awaiting_post_draw_disable:
		return
	_awaiting_post_draw_disable = false
	if _subviewport != null and is_instance_valid(_subviewport):
		_subviewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func cleanup() -> void:
	_update_pending = false
	_awaiting_post_draw_disable = false
	if RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)
	if _color_rect != null and is_instance_valid(_color_rect):
		_color_rect.material = null
		if _color_rect.get_parent() != null:
			_color_rect.get_parent().remove_child(_color_rect)
		_color_rect.queue_free()
	_color_rect = null

	if _subviewport != null and is_instance_valid(_subviewport):
		_subviewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if _subviewport.get_parent() == self:
			remove_child(_subviewport)
		_subviewport.queue_free()
	_subviewport = null

	_material = null
	_source_data_tex = null
	_source_data_img = null


func _ensure_source_data_resources() -> void:
	if _source_data_img == null:
		_source_data_img = Image.create(MAX_SOURCE_SLOTS, 2, false, Image.FORMAT_RGBAF)
		_source_data_img.fill(Color(0.0, 0.0, 0.0, 0.0))
	if _source_data_tex == null:
		_source_data_tex = ImageTexture.create_from_image(_source_data_img)


func _ensure_subviewport_resources() -> void:
	if _shader == null:
		_shader = load(ENVELOPE_SHADER_PATH) as Shader
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = _shader
		_material.set_shader_parameter("source_data_tex", _source_data_tex)

	if _subviewport == null or not is_instance_valid(_subviewport):
		_subviewport = SubViewport.new()
		_subviewport.name = "TerrainPreviewEnvelopeSubViewport"
		_subviewport.disable_3d = true
		_subviewport.transparent_bg = false
		_subviewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(_subviewport)

	if _color_rect == null or not is_instance_valid(_color_rect):
		_color_rect = ColorRect.new()
		_color_rect.name = "EnvelopeQuad"
		_color_rect.position = Vector2.ZERO
		_color_rect.material = _material
		_subviewport.add_child(_color_rect)
