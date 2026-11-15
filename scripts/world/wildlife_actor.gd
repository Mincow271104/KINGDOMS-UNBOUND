extends Node2D
## Lightweight visual actor for a Phase 6 wildlife entity.
## Uses cached procedural pixel textures per species; owns no global or save state.

const WildlifeConfigScript = preload("res://scripts/world/wildlife_config.gd")

static var _texture_cache: Dictionary = {}

var animal_id: String = ""
var species_id: String = ""
var _sprite: Sprite2D = null
var _state_badge: ColorRect = null

func setup(p_id: String, p_species_id: String, cell: Vector2i) -> void:
	animal_id = p_id
	species_id = p_species_id
	name = "Wildlife_%s" % p_id
	position = IsoMath.map_to_local(cell)
	y_sort_enabled = true

	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_sprite.centered = true
		_sprite.offset = Vector2(0, -5)
		add_child(_sprite)
	_sprite.texture = _get_species_texture(species_id)

	if _state_badge == null:
		_state_badge = ColorRect.new()
		_state_badge.size = Vector2(4, 4)
		_state_badge.position = Vector2(-2, -16)
		_state_badge.visible = false
		_state_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_state_badge)

func sync_visual(world_pos: Vector2, state: int, flip_h: bool, move_t: float = 0.0, is_moving: bool = false, anim_time: float = 0.0, turn_blend: float = 1.0) -> void:
	position = world_pos
	if _sprite != null:
		_sprite.flip_h = flip_h
		var spec: Dictionary = WildlifeConfigScript.get_species_def(species_id)
		var gait: int = int(spec.get("gait_type", WildlifeConfigScript.GaitType.WALK))
		var hop_h: float = float(spec.get("hop_height", 1.5))
		var bob_amp: float = float(spec.get("idle_bob_amp", 0.5))
		var bob_freq: float = float(spec.get("idle_bob_freq", 2.0))

		var y_off: float = -5.0
		var sy: float = 1.0
		if is_moving:
			var t := clampf(move_t, 0.0, 1.0)
			if gait == WildlifeConfigScript.GaitType.FLUTTER:
				y_off -= sin(t * PI) * hop_h + absf(sin(t * PI * 3.0)) * 1.2
			elif gait == WildlifeConfigScript.GaitType.HOP:
				var arc := sin(t * PI)
				y_off -= arc * hop_h
				sy = 1.0 + arc * 0.12
			else:
				y_off -= absf(sin(t * PI * 2.0)) * hop_h
		elif state == WildlifeConfigScript.BehaviorState.IDLE:
			y_off += sin(anim_time * bob_freq) * bob_amp

		_sprite.offset = Vector2(0.0, y_off)
		var sx: float = lerpf(0.35, 1.0, clampf(turn_blend, 0.0, 1.0))
		_sprite.scale = Vector2(sx, sy)

		if state == WildlifeConfigScript.BehaviorState.DEFENSIVE_DISPLAY:
			_sprite.modulate = Color(1.0, 0.85, 0.72, 1.0)
		else:
			_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
	if _state_badge != null:
		if state == WildlifeConfigScript.BehaviorState.DEFENSIVE_DISPLAY or state == WildlifeConfigScript.BehaviorState.ALERT:
			_state_badge.color = Color(0.95, 0.55, 0.15, 0.95)
			_state_badge.visible = true
		elif state == WildlifeConfigScript.BehaviorState.FLEEING:
			_state_badge.color = Color(0.95, 0.90, 0.35, 0.85)
			_state_badge.visible = true
		else:
			_state_badge.visible = false

static func _get_species_texture(p_species_id: String) -> ImageTexture:
	if _texture_cache.has(p_species_id):
		return _texture_cache[p_species_id]
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	match p_species_id:
		"bird":
			_draw_pixels(img, [
				Vector2i(6, 7), Vector2i(7, 7), Vector2i(8, 7), Vector2i(9, 7),
				Vector2i(7, 6), Vector2i(8, 6), Vector2i(9, 6),
				Vector2i(5, 8), Vector2i(6, 8), Vector2i(7, 8), Vector2i(8, 8),
				Vector2i(7, 9), Vector2i(8, 9),
			], Color(0.32, 0.62, 0.88, 1.0))
			_draw_pixels(img, [Vector2i(10, 6), Vector2i(7, 10)], Color(0.95, 0.78, 0.25, 1.0))
		"frog":
			_draw_pixels(img, [
				Vector2i(6, 9), Vector2i(7, 9), Vector2i(8, 9), Vector2i(9, 9),
				Vector2i(5, 10), Vector2i(6, 10), Vector2i(7, 10), Vector2i(8, 10), Vector2i(9, 10), Vector2i(10, 10),
				Vector2i(5, 11), Vector2i(10, 11),
			], Color(0.28, 0.78, 0.34, 1.0))
			_draw_pixels(img, [Vector2i(6, 8), Vector2i(9, 8)], Color(0.85, 0.95, 0.45, 1.0))
		"rabbit":
			_draw_pixels(img, [
				Vector2i(6, 5), Vector2i(6, 6), Vector2i(8, 5), Vector2i(8, 6),
				Vector2i(6, 7), Vector2i(7, 7), Vector2i(8, 7),
				Vector2i(6, 8), Vector2i(7, 8), Vector2i(8, 8), Vector2i(9, 8),
				Vector2i(5, 9), Vector2i(6, 9), Vector2i(7, 9), Vector2i(8, 9), Vector2i(9, 9),
				Vector2i(6, 10), Vector2i(9, 10),
			], Color(0.86, 0.80, 0.72, 1.0))
			_draw_pixels(img, [Vector2i(4, 9)], Color(0.98, 0.98, 0.98, 1.0))
		"deer":
			_draw_pixels(img, [
				Vector2i(4, 7), Vector2i(5, 7), Vector2i(6, 7), Vector2i(7, 7), Vector2i(8, 7), Vector2i(9, 7),
				Vector2i(4, 8), Vector2i(5, 8), Vector2i(6, 8), Vector2i(7, 8), Vector2i(8, 8), Vector2i(9, 8),
				Vector2i(9, 5), Vector2i(9, 6), Vector2i(10, 5),
				Vector2i(5, 9), Vector2i(5, 10), Vector2i(5, 11),
				Vector2i(8, 9), Vector2i(8, 10), Vector2i(8, 11),
			], Color(0.74, 0.50, 0.28, 1.0))
			_draw_pixels(img, [Vector2i(9, 3), Vector2i(10, 4), Vector2i(8, 4)], Color(0.88, 0.78, 0.60, 1.0))
		"wild_boar":
			_draw_pixels(img, [
				Vector2i(4, 7), Vector2i(5, 7), Vector2i(6, 7), Vector2i(7, 7), Vector2i(8, 7), Vector2i(9, 7),
				Vector2i(4, 8), Vector2i(5, 8), Vector2i(6, 8), Vector2i(7, 8), Vector2i(8, 8), Vector2i(9, 8), Vector2i(10, 8),
				Vector2i(5, 9), Vector2i(6, 9), Vector2i(7, 9), Vector2i(8, 9), Vector2i(9, 9),
				Vector2i(5, 10), Vector2i(9, 10),
			], Color(0.42, 0.30, 0.24, 1.0))
			_draw_pixels(img, [Vector2i(11, 8), Vector2i(11, 7)], Color(0.95, 0.92, 0.82, 1.0))
		"mountain_goat":
			_draw_pixels(img, [
				Vector2i(5, 7), Vector2i(6, 7), Vector2i(7, 7), Vector2i(8, 7), Vector2i(9, 7),
				Vector2i(5, 8), Vector2i(6, 8), Vector2i(7, 8), Vector2i(8, 8), Vector2i(9, 8),
				Vector2i(9, 5), Vector2i(9, 6), Vector2i(10, 5),
				Vector2i(5, 9), Vector2i(5, 10), Vector2i(8, 9), Vector2i(8, 10),
			], Color(0.90, 0.88, 0.82, 1.0))
			_draw_pixels(img, [Vector2i(8, 4), Vector2i(9, 4)], Color(0.45, 0.42, 0.38, 1.0))
	var tex := ImageTexture.create_from_image(img)
	_texture_cache[p_species_id] = tex
	return tex

static func _draw_pixels(img: Image, pts: Array, col: Color) -> void:
	for p in pts:
		if p.x >= 0 and p.x < 16 and p.y >= 0 and p.y < 16:
			img.set_pixel(p.x, p.y, col)
