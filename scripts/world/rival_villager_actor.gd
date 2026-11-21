class_name RivalVillagerActor
extends Node2D
## Phase 6 Presentation-Only Visual Actor for a Rival Settlement Villager.
## Never owns canonical NPC state, jobs, needs, or economy, and never writes back to SettlementVillagerData.

const CITIZEN_TEXTURE_PATH: String = "res://assets/entities/citizen.png"
const BASE_SPRITE_OFFSET: Vector2 = EntityVisualRegistry.VILLAGER_SPRITE_OFFSET
const BASE_SHEET_HFRAMES: int = 6
const BASE_SHEET_VFRAMES: int = 6
const IDLE_ROW: int = 0
const WALK_ROW: int = 1
const BACK_IDLE_ROW: int = 2
const BACK_WALK_ROW: int = 3
const WORK_ROW: int = 4
const BACK_WORK_ROW: int = 5
const CARRY_IDLE_ROW: int = 6
const BACK_CARRY_IDLE_ROW: int = 7
const SCREEN_DIR_NW: int = 5
const SCREEN_DIR_N: int = 6
const SCREEN_DIR_NE: int = 7
const IDLE_FPS: float = 2.2
const FARMER_WORK_FPS: float = 5.5
const WOODCUTTER_WORK_FPS: float = 6.0
const HUNTER_AIM_FPS: float = 4.0
const GUARD_WATCH_FPS: float = 2.0
const AMBIENT_WALK_SPEED_PX: float = 19.9
const AMBIENT_WALK_FPS: float = 5.0
const MIN_WALK_FPS: float = 4.0
const MAX_WALK_FPS: float = 14.0
const WORKER_STATE_NONE: int = 0
const WORKER_STATE_APPROACHING: int = 1
const WORKER_STATE_WORKING_AT_TARGET: int = 2
const WORKER_STATE_WAITING: int = 3
const WORKER_STATE_TRANSPORT_EMPTY: int = 4
const WORKER_STATE_TRANSPORT_LOADED: int = 5
const WORKER_STATE_GUARDING: int = 6
const WORKER_STATE_RETURNING_HOME: int = 7
const WORKER_STATE_RESTING: int = 8
const WORKER_STATE_INVALID_TARGET: int = 9
const WORK_CADENCE_SPEED: float = 3.5
const WORK_CADENCE_AMPLITUDE_PX: float = 1.0

static var _cached_citizen_tex: Texture2D = null
static var _textures_loaded: bool = false

# Preserved for backward API compatibility; body rendering uses Color.WHITE + 7x7 marker
const FACTION_TINTS: Dictionary = {
	"rival_military": Color(224.0 / 255.0, 56.0 / 255.0, 56.0 / 255.0, 1.0),
	"rival_merchant": Color(242.0 / 255.0, 194.0 / 255.0, 46.0 / 255.0, 1.0),
	"neutral_tribe": Color(62.0 / 255.0, 198.0 / 255.0, 96.0 / 255.0, 1.0),
	"emerging_power": Color(162.0 / 255.0, 92.0 / 255.0, 232.0 / 255.0, 1.0),
}

var bound_villager_id: String = ""
var bound_settlement_id: String = ""
var bound_faction_id: String = ""
var presentation_role: String = ""
var facing_dir: int = 0
var is_moving_visually: bool = false
var walk_anim_time: float = 0.0
var work_anim_time: float = 0.0
var work_phase_offset: float = 0.0
var active_anim_name: String = ""
var active_sheet_id: String = ""
var is_back_facing: bool = false
var _eff_anim_name: String = ""
var _eff_row: int = 0
var _eff_frame_count: int = 4
var _eff_fps: float = 2.2
var _is_role_sheet_active: bool = false
var anim_clock_sec: float = 0.0
var idle_phase_offset: float = 0.0
var use_base_sheet: bool = true
var use_role_sheets: bool = true
var faction_tint: Color = Color.WHITE
var faction_marker_color: Color = Color(0.0, 0.0, 0.0, 0.0)
var sprite: Sprite2D = null
var worker_presentation_state: int = 0
var worker_has_valid_focus: bool = false
var worker_focus_cell: Vector2i = Vector2i(-1, -1)
var worker_transport_loaded: bool = false
var worker_cargo_resource: String = ""

func _init() -> void:
	y_sort_enabled = true
	visible = false
	_ensure_sprite()

func _ready() -> void:
	_ensure_sprite()

static func _ensure_cached_textures() -> void:
	if _textures_loaded:
		return
	_textures_loaded = true
	if ResourceLoader.exists(CITIZEN_TEXTURE_PATH):
		_cached_citizen_tex = load(CITIZEN_TEXTURE_PATH) as Texture2D

func _resolve_target_anim(p_is_moving: bool) -> String:
	if worker_presentation_state == WORKER_STATE_RESTING:
		return "idle"
	var norm_role: String = EntityVisualRegistry.normalize_villager_role(presentation_role)
	if norm_role == "hauler" and worker_transport_loaded:
		return "carry_walk" if p_is_moving else "carry_idle"
	if p_is_moving:
		return "walk"
	if worker_presentation_state == WORKER_STATE_WORKING_AT_TARGET:
		match norm_role:
			"farmer": return "farmer_work"
			"woodcutter": return "woodcutter_work"
			"hunter": return "hunter_aim"
			"builder": return "builder_work"
			"miner": return "miner_work"
			"quarryman": return "quarryman_work"
			"smith": return "smith_work"
			"soldier": return "soldier_attack"
	elif worker_presentation_state == WORKER_STATE_GUARDING and (norm_role == "guard" or norm_role == "soldier"):
		return "guard_watch" if norm_role == "guard" else "soldier_attack"
	return "idle"

static func is_back_facing_dir(p_facing_dir: int) -> bool:
	return p_facing_dir == SCREEN_DIR_NW or p_facing_dir == SCREEN_DIR_N or p_facing_dir == SCREEN_DIR_NE

func _apply_texture_for_anim(target_anim: String, p_back: bool = false) -> bool:
	_ensure_cached_textures()
	var norm_role: String = EntityVisualRegistry.normalize_villager_role(presentation_role) if use_role_sheets else "idle"
	var layout: Dictionary = EntityVisualRegistry.get_villager_sheet_layout(norm_role)
	var tex: Texture2D = EntityVisualRegistry.get_villager_sheet_texture(norm_role) if use_base_sheet else null
	var vframes_count: int = int(layout.get("vframes", BASE_SHEET_VFRAMES))
	var hframes_count: int = int(layout.get("hframes", BASE_SHEET_HFRAMES))
	var row: int = BACK_IDLE_ROW if p_back else IDLE_ROW
	var fcount: int = int(layout.get("idle_frames", 4))
	var fps: float = float(layout.get("idle_fps", IDLE_FPS))
	var eff_anim: String = target_anim
	var sheet_id: String = norm_role
	var is_role_sheet: bool = (norm_role != "idle")

	if tex != null and use_base_sheet:
		if target_anim == "walk":
			row = BACK_WALK_ROW if p_back else WALK_ROW
			fcount = int(layout.get("walk_frames", 6))
			fps = AMBIENT_WALK_FPS
		elif target_anim == "carry_walk" and norm_role == "hauler":
			row = BACK_WORK_ROW if p_back else WORK_ROW
			fcount = int(layout.get("work_frames", 6))
			fps = AMBIENT_WALK_FPS
			sheet_id = "hauler_carry"
		elif target_anim == "carry_idle" and norm_role == "hauler":
			row = BACK_CARRY_IDLE_ROW if p_back else CARRY_IDLE_ROW
			fcount = int(layout.get("idle_frames", 4))
			fps = float(layout.get("idle_fps", IDLE_FPS))
			sheet_id = "hauler_carry"
		elif target_anim != "idle" and use_role_sheets:
			row = BACK_WORK_ROW if p_back else WORK_ROW
			fcount = int(layout.get("work_frames", 6))
			fps = float(layout.get("work_fps", 5.5))
		else:
			eff_anim = "idle"
			row = BACK_IDLE_ROW if p_back else IDLE_ROW
			fcount = int(layout.get("idle_frames", 4))
			fps = float(layout.get("idle_fps", IDLE_FPS))

	if sprite != null and is_instance_valid(sprite):
		if tex != null:
			if sprite.texture != tex:
				sprite.texture = tex
			if sprite.hframes != hframes_count:
				sprite.hframes = hframes_count
			if sprite.vframes != vframes_count:
				sprite.vframes = vframes_count
			active_sheet_id = sheet_id
			_eff_anim_name = eff_anim
			_eff_row = row
			_eff_frame_count = maxi(1, fcount)
			_eff_fps = fps
			_is_role_sheet_active = is_role_sheet
			return true
		if sprite.texture != _cached_citizen_tex:
			sprite.texture = _cached_citizen_tex
		if sprite.hframes != 1:
			sprite.hframes = 1
		if sprite.vframes != 1:
			sprite.vframes = 1
		sprite.frame_coords = Vector2i.ZERO
	active_sheet_id = "citizen"
	_eff_anim_name = "citizen"
	_eff_row = 0
	_eff_frame_count = 1
	_eff_fps = IDLE_FPS
	_is_role_sheet_active = false
	return false

func _apply_active_texture() -> bool:
	return _apply_texture_for_anim("idle")

func _ensure_sprite() -> void:
	if sprite != null and is_instance_valid(sprite):
		return
	sprite = get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = "Sprite2D"
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.offset = BASE_SPRITE_OFFSET
		add_child(sprite)
	_apply_active_texture()

func _draw() -> void:
	if visible and not bound_faction_id.is_empty() and bound_faction_id != "player":
		EntityVisualRegistry.draw_faction_marker_7x7(self, bound_faction_id, EntityVisualRegistry.FACTION_MARKER_OFFSET)

static func resolve_faction_tint(p_faction_id: String) -> Color:
	return Color.WHITE

func is_bound() -> bool:
	return not bound_villager_id.is_empty() and not bound_settlement_id.is_empty()

func bind_villager(p_settlement_id: String, p_villager_id: String, p_faction_id: String = "", p_role: String = "") -> void:
	_ensure_sprite()
	bound_settlement_id = p_settlement_id
	bound_villager_id = p_villager_id
	bound_faction_id = p_faction_id
	presentation_role = p_role
	faction_tint = Color.WHITE
	faction_marker_color = EntityVisualRegistry.get_faction_marker_color(p_faction_id)
	walk_anim_time = 0.0
	work_anim_time = 0.0
	work_phase_offset = float(abs(hash(p_villager_id)) % 628) * 0.01
	active_anim_name = ""
	active_sheet_id = ""
	is_back_facing = false
	_eff_anim_name = ""
	_eff_row = 0
	_is_role_sheet_active = false
	anim_clock_sec = 0.0
	idle_phase_offset = float(abs(hash(p_villager_id)) % 400) * 0.01
	is_moving_visually = false
	facing_dir = 0
	worker_presentation_state = 0
	worker_has_valid_focus = false
	worker_focus_cell = Vector2i(-1, -1)
	worker_transport_loaded = false
	worker_cargo_resource = ""
	rotation = 0.0
	scale = Vector2.ONE
	_apply_active_texture()
	if sprite != null:
		sprite.modulate = Color.WHITE
		sprite.flip_h = false
		sprite.offset = BASE_SPRITE_OFFSET
		sprite.frame_coords = Vector2i.ZERO
	queue_redraw()
	name = "RivalActor_%s_%s" % [p_settlement_id, p_villager_id]

func sync_presentation(
	world_pos: Vector2,
	p_flip_h: bool,
	p_facing_dir: int,
	p_is_moving: bool,
	p_visible: bool,
	anim_delta: float = 0.0,
	move_speed_px: float = -1.0
) -> void:
	_ensure_sprite()
	position = world_pos
	z_index = IsoMath.world_y_to_z_index(world_pos.y)
	facing_dir = p_facing_dir
	is_moving_visually = p_is_moving
	visible = p_visible
	if not p_visible:
		return

	is_back_facing = is_back_facing_dir(p_facing_dir)
	var target_anim: String = _resolve_target_anim(p_is_moving)
	var sheet_active: bool = _apply_texture_for_anim(target_anim, is_back_facing)
	var is_m31_working: bool = (
		not p_is_moving
		and (presentation_role == "farmer" or presentation_role == "woodcutter")
		and worker_presentation_state == WORKER_STATE_WORKING_AT_TARGET
	)

	var next_anim: String = _eff_anim_name
	if next_anim != active_anim_name:
		active_anim_name = next_anim
		anim_clock_sec = 0.0
	elif anim_delta > 0.0:
		anim_clock_sec += anim_delta

	if p_is_moving and anim_delta > 0.0:
		walk_anim_time += anim_delta * 10.0
		work_anim_time = 0.0
	elif is_m31_working and anim_delta > 0.0:
		walk_anim_time = 0.0
		work_anim_time += anim_delta * WORK_CADENCE_SPEED
	elif not p_is_moving:
		walk_anim_time = 0.0
		if not is_m31_working:
			work_anim_time = 0.0

	if sprite != null:
		sprite.flip_h = p_flip_h
		sprite.modulate = Color.WHITE
		var bob_y: float = 0.0
		if sheet_active:
			var target_row: int = _eff_row
			var fps: float = _eff_fps
			var use_idle_offset: bool = (next_anim == "idle" or next_anim == "carry_idle")
			if next_anim == "walk" or next_anim == "carry_walk":
				var eff_speed: float = move_speed_px if move_speed_px > 0.0 else AMBIENT_WALK_SPEED_PX
				fps = clampf(AMBIENT_WALK_FPS * (eff_speed / AMBIENT_WALK_SPEED_PX), MIN_WALK_FPS, MAX_WALK_FPS)
			var eff_t: float = (anim_clock_sec + idle_phase_offset) if use_idle_offset else anim_clock_sec
			var frame_idx: int = int(floor(eff_t * fps)) % maxi(1, _eff_frame_count)
			sprite.frame_coords = Vector2i(frame_idx, target_row)
		else:
			if p_is_moving:
				bob_y = -absf(sin(walk_anim_time)) * 1.5
			elif is_m31_working:
				bob_y = -clampf(sin(work_anim_time + work_phase_offset), 0.0, 1.0) * WORK_CADENCE_AMPLITUDE_PX
		sprite.offset = BASE_SPRITE_OFFSET + Vector2(0.0, bob_y)

func set_worker_presentation_metadata(pres_res: RefCounted) -> void:
	if pres_res == null:
		worker_presentation_state = 0
		worker_has_valid_focus = false
		worker_focus_cell = Vector2i(-1, -1)
		worker_transport_loaded = false
		worker_cargo_resource = ""
		return
	worker_presentation_state = int(pres_res.presentation_state)
	worker_has_valid_focus = bool(pres_res.has_valid_focus)
	worker_focus_cell = pres_res.focus_cell
	worker_transport_loaded = bool(pres_res.transport_loaded)
	worker_cargo_resource = String(pres_res.cargo_resource)

func release_binding() -> void:
	bound_villager_id = ""
	bound_settlement_id = ""
	bound_faction_id = ""
	presentation_role = ""
	facing_dir = 0
	is_moving_visually = false
	walk_anim_time = 0.0
	work_anim_time = 0.0
	work_phase_offset = 0.0
	active_anim_name = ""
	active_sheet_id = ""
	is_back_facing = false
	_eff_anim_name = ""
	_eff_row = 0
	_is_role_sheet_active = false
	anim_clock_sec = 0.0
	idle_phase_offset = 0.0
	worker_presentation_state = 0
	worker_has_valid_focus = false
	worker_focus_cell = Vector2i(-1, -1)
	worker_transport_loaded = false
	worker_cargo_resource = ""
	faction_tint = Color.WHITE
	faction_marker_color = Color(0.0, 0.0, 0.0, 0.0)
	visible = false
	queue_redraw()
	position = Vector2.ZERO
	z_index = 0
	rotation = 0.0
	scale = Vector2.ONE
	modulate = Color.WHITE
	name = "RivalActor_Pooled"
	if sprite != null and is_instance_valid(sprite):
		sprite.flip_h = false
		sprite.modulate = Color.WHITE
		sprite.offset = BASE_SPRITE_OFFSET
		sprite.frame_coords = Vector2i.ZERO
		sprite.rotation = 0.0
		sprite.scale = Vector2.ONE
	# Disconnect any script-defined signal listeners without touching Godot internal C++ signals
	var script_obj: Script = get_script()
	if script_obj != null:
		for sig_info in script_obj.get_script_signal_list():
			var sig_name: StringName = sig_info["name"]
			for conn in get_signal_connection_list(sig_name):
				var c_callable: Callable = conn["callable"]
				if c_callable.is_valid():
					disconnect(sig_name, c_callable)
