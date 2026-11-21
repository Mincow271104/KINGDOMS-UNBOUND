class_name MonsterActor
extends Node2D

const MonsterConfigScript := preload("res://scripts/world/monster_config.gd")
## Host-compatible animated pixel-art actor representing an active Phase 9 hostile monster.
## Strictly presentation-only: derives Sprite2D sheet/clip/frame from canonical MonsterManager state.
## Compatible with TacticalMilitaryManager.issue_attack_order and TacticalUnit.advance_combat.

@export var unit_id: String = ""
@export var monster_id: String = ""
@export var species_id: String = "forest_stalker"
@export var display_name: String = "Forest Stalker"
@export var faction_id: String = MonsterConfigScript.FACTION_ID
@export var home_nest_id: String = ""
@export var current_cell: Vector2i = Vector2i.ZERO
@export var health: float = 75.0
@export var max_health: float = 75.0
@export var armor: float = 0.0
@export var is_alive: bool = true
@export var ai_state: int = MonsterConfigScript.MonsterAIState.IDLE

var body_color: Color = Color(0.72, 0.24, 0.22, 1.0)
var accent_color: Color = Color(0.95, 0.45, 0.25, 1.0)
var damage_flash_timer: float = 0.0
var is_selected: bool = false

# Presentation-only ecological movement & animation state (never authoritative)
var prev_cell: Vector2i = Vector2i.ZERO
var move_progress: float = 1.0
var facing_left: bool = false
var alert_visual_timer: float = 0.0
var anim_time: float = 0.0
var active_anim_clip: String = "idle"
var active_anim_row: int = 0
var active_frame_col: int = 0

var _sprite: Sprite2D = null
var _bound_species_id: String = ""
var _bound_monster_id: String = ""
var _prev_ai_state: int = -1
var _state_enter_anim_time: float = 0.0
var _attack_period_sec: float = 1.0
var _hp_bar_y: float = -25.0
var _alert_y: float = -28.0
var _visual_offset: Vector2 = Vector2.ZERO

signal monster_damaged(m_id: String, amount: float, current_hp: float, max_hp: float, attacker_id: String)
signal monster_died(m_id: String, killer_id: String)

func _ready() -> void:
	_ensure_sprite()
	_bind_species_visuals()
	_sync_sprite_visual()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible and _sprite != null and is_instance_valid(_sprite):
		_sync_sprite_visual()

func _ensure_sprite() -> void:
	if _sprite != null and is_instance_valid(_sprite):
		return
	var existing := get_node_or_null("Sprite2D")
	if existing is Sprite2D:
		_sprite = existing as Sprite2D
	else:
		_sprite = Sprite2D.new()
		_sprite.name = "Sprite2D"
		add_child(_sprite)
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _bind_species_visuals() -> void:
	_ensure_sprite()
	var lay: Dictionary = EntityVisualRegistry.get_monster_sheet_layout(species_id)
	var tex: Texture2D = EntityVisualRegistry.get_monster_sheet_texture(species_id)
	_sprite.texture = tex
	_sprite.hframes = int(lay.get("hframes", 6))
	_sprite.vframes = int(lay.get("vframes", 4))
	_sprite.offset = lay.get("anchor_offset", Vector2(-16.0, -28.0))
	_hp_bar_y = float(lay.get("hp_bar_y", -25.0))
	_alert_y = float(lay.get("alert_y", -28.0))
	var spec := MonsterConfigScript.get_species_def(species_id)
	_attack_period_sec = maxf(0.4, float(spec.get("attack_cooldown", 1.0)))
	_bound_species_id = species_id

func configure(p_id: String, p_species: String, p_cell: Vector2i, p_home_nest_id: String, p_hp: float, p_max_hp: float, p_armor: float, p_state: int) -> void:
	var rebinding := (p_id != _bound_monster_id) or (p_species != _bound_species_id)
	unit_id = p_id
	monster_id = p_id
	species_id = p_species
	current_cell = p_cell
	prev_cell = p_cell
	move_progress = 1.0
	home_nest_id = p_home_nest_id
	health = p_hp
	max_health = p_max_hp
	armor = p_armor
	is_alive = health > 0.0 and p_state != MonsterConfigScript.MonsterAIState.DEAD
	ai_state = p_state
	var spec := MonsterConfigScript.get_species_def(p_species)
	display_name = str(spec.get("display_name", p_species))
	body_color = spec.get("color", Color(0.72, 0.24, 0.22, 1.0))
	accent_color = spec.get("accent_color", Color(0.95, 0.45, 0.25, 1.0))
	position = IsoMath.map_to_local(current_cell)
	z_index = IsoMath.world_y_to_z_index(position.y)

	if rebinding:
		_bound_monster_id = p_id
		damage_flash_timer = 0.0
		alert_visual_timer = 0.0
		anim_time = 0.0
		facing_left = false
		_state_enter_anim_time = 0.0
		_prev_ai_state = p_state
		active_frame_col = 0
		_visual_offset = Vector2.ZERO
		_bind_species_visuals()
	elif _prev_ai_state != p_state:
		_prev_ai_state = p_state
		_state_enter_anim_time = anim_time

	_sync_sprite_visual()
	queue_redraw()

func sync_visual(p_prev_cell: Vector2i, p_current_cell: Vector2i, p_move_progress: float, p_state: int, p_facing_left: bool, p_alert_timer: float, p_anim_time: float) -> void:
	var prev_state := _prev_ai_state
	var prev_alert := alert_visual_timer
	prev_cell = p_prev_cell
	current_cell = p_current_cell
	move_progress = clampf(p_move_progress, 0.0, 1.0)
	ai_state = p_state
	facing_left = p_facing_left
	alert_visual_timer = maxf(0.0, p_alert_timer)
	anim_time = p_anim_time

	if prev_state != ai_state:
		_prev_ai_state = ai_state
		_state_enter_anim_time = anim_time

	var p0: Vector2 = IsoMath.map_to_local(prev_cell)
	var p1: Vector2 = IsoMath.map_to_local(current_cell)
	position = p0.lerp(p1, move_progress)
	z_index = IsoMath.world_y_to_z_index(position.y)
	_visual_offset = Vector2.ZERO

	# Fog-hidden monsters skip sprite frame updates until revealed (Section 8 optimization)
	if visible:
		_sync_sprite_visual()
		if (prev_alert > 0.0) != (alert_visual_timer > 0.0) or alert_visual_timer > 0.0:
			queue_redraw()

func _sync_sprite_visual() -> void:
	if _sprite == null or not is_instance_valid(_sprite):
		_ensure_sprite()
	if _bound_species_id != species_id or _sprite.texture == null:
		_bind_species_visuals()

	if not is_alive or ai_state == MonsterConfigScript.MonsterAIState.DEAD:
		active_anim_clip = "dead"
		_sprite.visible = false
		return

	_sprite.visible = true
	_sprite.flip_h = facing_left
	_sprite.modulate = Color(1.45, 0.72, 0.72, 1.0) if damage_flash_timer > 0.0 else Color.WHITE

	var lay: Dictionary = EntityVisualRegistry.get_monster_sheet_layout(species_id)
	var row := 0
	var col := 0
	var hframes := int(lay.get("hframes", 6))

	match ai_state:
		MonsterConfigScript.MonsterAIState.ATTACKING:
			active_anim_clip = "attack"
			row = 3
			var cnt := maxi(1, int(lay.get("attack_frames", 5)))
			var elapsed := maxf(0.0, anim_time - _state_enter_anim_time)
			var phase := fposmod(elapsed, _attack_period_sec) / _attack_period_sec
			col = mini(cnt - 1, int(floor(phase * float(cnt))))
		MonsterConfigScript.MonsterAIState.CHASING:
			active_anim_clip = "chase"
			row = 2
			var cnt := maxi(1, int(lay.get("chase_frames", 6)))
			var fps := float(lay.get("chase_fps", 10.0))
			col = int(floor(maxf(0.0, anim_time) * fps)) % cnt
		MonsterConfigScript.MonsterAIState.ROAMING:
			active_anim_clip = "roam"
			row = 1
			var cnt := maxi(1, int(lay.get("roam_frames", 6)))
			var fps := float(lay.get("roam_fps", 7.0))
			col = int(floor(maxf(0.0, anim_time) * fps)) % cnt
		MonsterConfigScript.MonsterAIState.RETURNING:
			active_anim_clip = "return"
			row = 1
			var cnt := maxi(1, int(lay.get("roam_frames", 6)))
			var fps := float(lay.get("roam_fps", 7.0)) * 1.15
			col = int(floor(maxf(0.0, anim_time) * fps)) % cnt
		_:
			active_anim_clip = "idle"
			row = 0
			var cnt := maxi(1, int(lay.get("idle_frames", 4)))
			var fps := float(lay.get("idle_fps", 2.5))
			col = int(floor(maxf(0.0, anim_time) * fps)) % cnt

	active_anim_row = row
	active_frame_col = col
	var frame_idx := clampi(row * hframes + col, 0, maxi(0, hframes * int(lay.get("vframes", 4)) - 1))
	if _sprite.frame != frame_idx:
		_sprite.frame = frame_idx

func take_damage(amount: float, attacker_id: String = "") -> void:
	if not is_alive or amount <= 0.0:
		return
	var mitigated: float = maxf(1.0, amount - armor)
	health = clampf(health - mitigated, 0.0, max_health)
	damage_flash_timer = 0.22
	monster_damaged.emit(monster_id, mitigated, health, max_health, attacker_id)
	if health <= 0.0:
		health = 0.0
		is_alive = false
		ai_state = MonsterConfigScript.MonsterAIState.DEAD
		monster_died.emit(monster_id, attacker_id)
	_sync_sprite_visual()
	queue_redraw()

func _process(delta: float) -> void:
	if damage_flash_timer > 0.0:
		damage_flash_timer = maxf(0.0, damage_flash_timer - delta)
		if damage_flash_timer == 0.0:
			_sync_sprite_visual()
			queue_redraw()

func _draw() -> void:
	if not is_alive:
		return
	# Gameplay indicators only (body & contact shadow are authored cleanly in the Sprite2D sheet)
	if alert_visual_timer > 0.0:
		var alert_pos := Vector2(0.0, _alert_y)
		var alert_pts := PackedVector2Array([
			alert_pos + Vector2(0, -5),
			alert_pos + Vector2(3.5, 0),
			alert_pos + Vector2(0, 3.5),
			alert_pos + Vector2(-3.5, 0),
		])
		draw_colored_polygon(alert_pts, Color(1.0, 0.42, 0.12, 0.95))

	# Compact HP bar when injured, flashing, or selected
	if is_selected or health < max_health or damage_flash_timer > 0.0:
		var bar_w := 24.0 if species_id == "stone_brute" else 22.0
		var bar_h := 3.0
		var bar_pos := Vector2(-bar_w * 0.5, _hp_bar_y)
		draw_rect(Rect2(bar_pos - Vector2(1, 1), Vector2(bar_w + 2, bar_h + 2)), Color(0.08, 0.08, 0.08, 0.85), true)
		var ratio := clampf(health / maxf(1.0, max_health), 0.0, 1.0)
		draw_rect(Rect2(bar_pos, Vector2(bar_w * ratio, bar_h)), Color(0.92, 0.22, 0.22, 1.0), true)
