extends Node2D
## Animated pixel-art visual actor for a Phase 6 wildlife entity.
## Strictly presentation-only: derives Sprite2D clip/frame from canonical WildlifeManager state.
## Owns no simulation, reservation, or save state; uses EntityVisualRegistry shared texture cache.

const WildlifeConfigScript = preload("res://scripts/world/wildlife_config.gd")

var animal_id: String = ""
var species_id: String = ""
var active_anim_clip: String = "idle"
var active_anim_row: int = 0
var active_frame_col: int = 0

var _sprite: Sprite2D = null
var _state_badge: ColorRect = null
var _bound_species_id: String = ""
var _last_state: int = -1
var _state_enter_anim_time: float = 0.0
var _last_flip_h: bool = false
var _last_move_t: float = 0.0
var _last_is_moving: bool = false
var _last_anim_time: float = 0.0
var _last_turn_blend: float = 1.0
var _badge_y: float = -16.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible and _sprite != null and is_instance_valid(_sprite):
		_sync_sprite_visual()

func _ensure_visual_nodes() -> void:
	if _sprite == null or not is_instance_valid(_sprite):
		_sprite = Sprite2D.new()
		_sprite.name = "Sprite2D"
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_sprite.centered = true
		_sprite.offset = Vector2(0.0, -5.0)
		add_child(_sprite)

	if _state_badge == null or not is_instance_valid(_state_badge):
		_state_badge = ColorRect.new()
		_state_badge.name = "StateBadge"
		_state_badge.size = Vector2(4, 4)
		_state_badge.position = Vector2(-2.0, _badge_y)
		_state_badge.visible = false
		_state_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_state_badge)

func _bind_species_visuals() -> void:
	_ensure_visual_nodes()
	var lay: Dictionary = EntityVisualRegistry.get_wildlife_sheet_layout(species_id)
	var tex: Texture2D = EntityVisualRegistry.get_wildlife_sheet_texture(species_id)
	_sprite.texture = tex
	_sprite.hframes = int(lay.get("hframes", 6))
	_sprite.vframes = int(lay.get("vframes", 2))
	_sprite.centered = true
	_sprite.offset = Vector2(0.0, -5.0)
	_sprite.frame = 0
	_badge_y = float(lay.get("badge_y", -16.0))
	_state_badge.position = Vector2(-2.0, _badge_y)
	_bound_species_id = species_id

func setup(p_id: String, p_species_id: String, cell: Vector2i) -> void:
	animal_id = p_id
	species_id = p_species_id
	name = "Wildlife_%s" % p_id
	position = IsoMath.map_to_local(cell)
	z_index = IsoMath.world_y_to_z_index(position.y)
	y_sort_enabled = true

	_ensure_visual_nodes()
	_bind_species_visuals()

	# Clean reset on setup/reuse (never leak prior animal animation phase/timers/transforms)
	_last_state = WildlifeConfigScript.BehaviorState.IDLE
	_state_enter_anim_time = 0.0
	_last_flip_h = false
	_last_move_t = 0.0
	_last_is_moving = false
	_last_anim_time = 0.0
	_last_turn_blend = 1.0
	active_anim_clip = "idle"
	active_anim_row = 0
	active_frame_col = 0
	_sprite.flip_h = false
	_sprite.scale = Vector2.ONE
	_sprite.modulate = Color.WHITE
	_sprite.frame = 0
	_state_badge.visible = false

func sync_visual(world_pos: Vector2, state: int, flip_h: bool, move_t: float = 0.0, is_moving: bool = false, anim_time: float = 0.0, turn_blend: float = 1.0) -> void:
	position = world_pos
	z_index = IsoMath.world_y_to_z_index(world_pos.y)

	if _last_state != state:
		_last_state = state
		_state_enter_anim_time = anim_time
	_last_flip_h = flip_h
	_last_move_t = move_t
	_last_is_moving = is_moving
	_last_anim_time = anim_time
	_last_turn_blend = turn_blend

	# Fog-hidden wildlife skip per-frame sprite math until revealed
	if not visible:
		return
	_sync_sprite_visual()

func _sync_sprite_visual() -> void:
	if _sprite == null or not is_instance_valid(_sprite):
		_ensure_visual_nodes()
	if _bound_species_id != species_id or _sprite.texture == null:
		_bind_species_visuals()

	var lay: Dictionary = EntityVisualRegistry.get_wildlife_sheet_layout(species_id)
	var spec: Dictionary = WildlifeConfigScript.get_species_def(species_id)
	var hframes := maxi(1, int(lay.get("hframes", 6)))
	var vframes := maxi(1, int(lay.get("vframes", 2)))
	var gait: int = int(spec.get("gait_type", WildlifeConfigScript.GaitType.WALK))
	var hop_h: float = float(spec.get("hop_height", 1.5))
	var bob_freq: float = float(spec.get("idle_bob_freq", 2.0))

	_sprite.flip_h = _last_flip_h

	# Determine row, col, clip, and subtle gait vertical offset (maintaining -5.0 ground-anchor base)
	var row := 0
	var col := 0
	var y_off := -5.0
	var sy := 1.0
	var st := _last_state

	if st == WildlifeConfigScript.BehaviorState.BEING_HUNTED:
		active_anim_clip = "being_hunted"
		row = 0
		col = 0
		y_off = -5.0
	elif st == WildlifeConfigScript.BehaviorState.DEFENSIVE_DISPLAY or st == WildlifeConfigScript.BehaviorState.ALERT:
		var def_cnt := int(lay.get("defensive_frames", 0))
		if vframes >= 4 and def_cnt > 0:
			active_anim_clip = "defensive"
			row = 3
			var d_fps := float(lay.get("defensive_fps", 6.5))
			var elapsed := maxf(0.0, _last_anim_time - _state_enter_anim_time)
			col = int(floor(elapsed * d_fps)) % def_cnt
		else:
			active_anim_clip = "idle"
			row = 0
			col = 0
		y_off = -5.0
	elif st == WildlifeConfigScript.BehaviorState.FLEEING:
		if vframes >= 3:
			active_anim_clip = "flee"
			row = 2
			var f_cnt := maxi(1, int(lay.get("flee_frames", 6)))
			var f_fps := float(lay.get("flee_fps", 12.0))
			col = int(floor(maxf(0.0, _last_anim_time) * f_fps)) % f_cnt
		else:
			active_anim_clip = "move"
			row = mini(1, vframes - 1)
			var m_cnt_f := maxi(1, int(lay.get("move_frames", 6)))
			var m_fps_f := float(lay.get("move_fps", 9.0)) * 1.25
			col = int(floor(maxf(0.0, _last_anim_time) * m_fps_f)) % m_cnt_f
		if _last_is_moving:
			var t_f := clampf(_last_move_t, 0.0, 1.0)
			if gait == WildlifeConfigScript.GaitType.FLUTTER:
				y_off -= sin(t_f * PI) * hop_h + absf(sin(t_f * PI * 3.0)) * 1.2
			elif gait == WildlifeConfigScript.GaitType.HOP:
				var arc_f := sin(t_f * PI)
				y_off -= arc_f * hop_h
				sy = 1.0 + arc_f * 0.08
			else:
				y_off -= absf(sin(t_f * PI * 2.0)) * 0.5
	elif _last_is_moving or st == WildlifeConfigScript.BehaviorState.WANDERING:
		active_anim_clip = "move"
		row = mini(1, vframes - 1)
		var m_cnt := maxi(1, int(lay.get("move_frames", 6)))
		var m_fps := float(lay.get("move_fps", 8.0))
		col = int(floor(maxf(0.0, _last_anim_time) * m_fps)) % m_cnt
		if _last_is_moving:
			var t_m := clampf(_last_move_t, 0.0, 1.0)
			if gait == WildlifeConfigScript.GaitType.FLUTTER:
				y_off -= sin(t_m * PI) * hop_h + absf(sin(t_m * PI * 3.0)) * 1.2
			elif gait == WildlifeConfigScript.GaitType.HOP:
				var arc_m := sin(t_m * PI)
				y_off -= arc_m * hop_h
				sy = 1.0 + arc_m * 0.08
			else:
				y_off -= absf(sin(t_m * PI * 2.0)) * 0.4
	else:
		active_anim_clip = "idle"
		row = 0
		var i_cnt := maxi(1, int(lay.get("idle_frames", 4)))
		var i_fps := float(lay.get("idle_fps", 2.5))
		col = int(floor(maxf(0.0, _last_anim_time) * i_fps)) % i_cnt
		if st == WildlifeConfigScript.BehaviorState.IDLE:
			y_off += sin(_last_anim_time * bob_freq) * 0.25

	active_anim_row = row
	active_frame_col = col
	_sprite.offset = Vector2(0.0, y_off)
	var sx: float = lerpf(0.35, 1.0, clampf(_last_turn_blend, 0.0, 1.0))
	_sprite.scale = Vector2(sx, sy)

	var frame_idx := clampi(row * hframes + col, 0, maxi(0, hframes * vframes - 1))
	if _sprite.frame != frame_idx:
		_sprite.frame = frame_idx

	if st == WildlifeConfigScript.BehaviorState.DEFENSIVE_DISPLAY:
		_sprite.modulate = Color(1.0, 0.88, 0.74, 1.0)
	else:
		_sprite.modulate = Color.WHITE

	if _state_badge != null:
		if st == WildlifeConfigScript.BehaviorState.DEFENSIVE_DISPLAY or st == WildlifeConfigScript.BehaviorState.ALERT:
			_state_badge.color = Color(0.95, 0.55, 0.15, 0.95)
			_state_badge.visible = true
		elif st == WildlifeConfigScript.BehaviorState.FLEEING:
			_state_badge.color = Color(0.95, 0.90, 0.35, 0.85)
			_state_badge.visible = true
		else:
			_state_badge.visible = false
