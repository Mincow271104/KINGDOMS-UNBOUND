class_name MonsterNestActor
extends Node2D

const MonsterConfigScript := preload("res://scripts/world/monster_config.gd")
## Destructible Monster Nest actor compatible with TacticalMilitaryManager.issue_attack_order
## and TacticalUnit.advance_combat without triggering faction Field Siege checks.

@export var objective_id: String = ""
@export var nest_id: String = ""
@export var species_id: String = "forest_stalker"
@export var nest_name: String = "Monster Nest"
@export var faction_id: String = MonsterConfigScript.FACTION_ID
@export var current_cell: Vector2i = Vector2i.ZERO
@export var health: float = MonsterConfigScript.NEST_MAX_HEALTH
@export var max_health: float = MonsterConfigScript.NEST_MAX_HEALTH
@export var is_alive: bool = true

var damage_flash_timer: float = 0.0
var is_discovered: bool = false
var _sprite: Sprite2D = null

signal nest_damaged(n_id: String, amount: float, current_hp: float, max_hp: float, attacker_id: String)
signal nest_destroyed(n_id: String, killer_id: String)

func _ready() -> void:
	_ensure_sprite()
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

func _sync_sprite_visual() -> void:
	_ensure_sprite()
	var tex := EntityVisualRegistry.get_nest_texture(species_id, not is_alive)
	if _sprite.texture != tex:
		_sprite.texture = tex
	_sprite.offset = EntityVisualRegistry.get_nest_sprite_offset(tex)
	_sprite.modulate = Color(1.35, 0.78, 0.78, 1.0) if (is_alive and damage_flash_timer > 0.0) else Color.WHITE

func configure(p_id: String, p_species: String, p_cell: Vector2i, p_hp: float, p_max_hp: float, p_destroyed: bool) -> void:
	objective_id = p_id
	nest_id = p_id
	species_id = p_species
	current_cell = p_cell
	health = p_hp
	max_health = p_max_hp
	is_alive = not p_destroyed and health > 0.0
	var spec := MonsterConfigScript.get_species_def(p_species)
	nest_name = str(spec.get("nest_name", "Ổ Quái Vật"))
	position = IsoMath.map_to_local(current_cell)
	z_index = IsoMath.world_y_to_z_index(position.y)
	_sync_sprite_visual()
	queue_redraw()

func take_damage(amount: float, attacker_id: String = "") -> void:
	if not is_alive or amount <= 0.0:
		return
	health = clampf(health - amount, 0.0, max_health)
	damage_flash_timer = 0.22
	nest_damaged.emit(nest_id, amount, health, max_health, attacker_id)
	if health <= 0.0:
		health = 0.0
		is_alive = false
		nest_destroyed.emit(nest_id, attacker_id)
	_sync_sprite_visual()
	queue_redraw()

func _process(delta: float) -> void:
	if damage_flash_timer > 0.0:
		damage_flash_timer = maxf(0.0, damage_flash_timer - delta)
		if damage_flash_timer == 0.0:
			_sync_sprite_visual()
			queue_redraw()

func _draw() -> void:
	if is_alive and (health < max_health or damage_flash_timer > 0.0):
		var bar_w := 26.0
		var bar_h := 3.5
		var bar_pos := Vector2(-bar_w * 0.5, -28.0)
		draw_rect(Rect2(bar_pos - Vector2(1, 1), Vector2(bar_w + 2, bar_h + 2)), Color(0.08, 0.08, 0.08, 0.85), true)
		var ratio := clampf(health / maxf(1.0, max_health), 0.0, 1.0)
		draw_rect(Rect2(bar_pos, Vector2(bar_w * ratio, bar_h)), Color(0.95, 0.40, 0.15, 1.0), true)
