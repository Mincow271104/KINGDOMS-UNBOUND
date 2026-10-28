class_name SiegeObjectiveActor
extends Node2D
## Field Siege Objective Actor (Package 1X)
## Represents a fortified hostile outpost or stronghold on the isometric world map.
## Features durability health pool, garrison defense coordination, dimetric rendering,
## health bar display, damage reception, and capture state transitions.

@export var objective_id: String = ""
@export var objective_name: String = "Tiền Đồn Địch"
@export var owning_faction_id: String = ""
@export var current_cell: Vector2i = Vector2i(0, 0)
@export var health: float = 250.0
@export var max_health: float = 250.0
@export var is_alive: bool = true
@export var is_captured: bool = false
@export var garrison_count: int = 3
@export var defending_unit_ids: Array[String] = []

signal objective_damaged(obj_id: String, amount: float, current_hp: float, max_hp: float)
signal objective_destroyed(obj_id: String, killer_id: String)
signal objective_captured(obj_id: String, new_owner_id: String)

var damage_flash_timer: float = 0.0

func _ready() -> void:
	y_sort_enabled = true
	position = IsoMath.map_to_local(current_cell)

func take_damage(amount: float, attacker_id: String = "") -> void:
	if not is_alive or amount <= 0.0:
		return

	health = clampf(health - amount, 0.0, max_health)
	damage_flash_timer = 0.25
	objective_damaged.emit(objective_id, amount, health, max_health)

	if health <= 0.0:
		is_alive = false
		is_captured = true
		objective_destroyed.emit(objective_id, attacker_id)
		objective_captured.emit(objective_id, "player")

	queue_redraw()

func _process(delta: float) -> void:
	if damage_flash_timer > 0.0:
		damage_flash_timer = maxf(0.0, damage_flash_timer - delta)
		if damage_flash_timer == 0.0:
			queue_redraw()

func _draw() -> void:
	# Draw isometric base footprint (2:1 slope diamond)
	var hw := 28.0
	var hh := 14.0
	var diamond := PackedVector2Array([
		Vector2(0, -hh),
		Vector2(hw, 0),
		Vector2(0, hh),
		Vector2(-hw, 0)
	])
	draw_colored_polygon(diamond, Color(0.2, 0.18, 0.15, 0.7))
	draw_polyline(diamond, Color(0.4, 0.35, 0.3, 0.9), 1.5, true)

	# Outpost tower body
	var tower_pts := PackedVector2Array([
		Vector2(-16, 0),
		Vector2(-16, -32),
		Vector2(0, -40),
		Vector2(16, -32),
		Vector2(16, 0),
		Vector2(0, 8)
	])
	var body_color := Color(0.55, 0.45, 0.4, 0.95) if is_alive else Color(0.3, 0.28, 0.28, 0.7)
	draw_colored_polygon(tower_pts, body_color)
	draw_polyline(tower_pts, Color(0.2, 0.15, 0.12, 0.95), 1.5, true)

	# Faction banner
	var banner_color := Color(0.85, 0.2, 0.2, 0.95) if not is_captured else Color(0.2, 0.8, 0.3, 0.95)
	var banner_pts := PackedVector2Array([
		Vector2(0, -40),
		Vector2(0, -54),
		Vector2(12, -48),
		Vector2(0, -42)
	])
	draw_colored_polygon(banner_pts, banner_color)
	draw_line(Vector2(0, -40), Vector2(0, -56), Color(0.1, 0.1, 0.1), 1.5)

	# Health bar on top
	if is_alive:
		var bar_w := 36.0
		var bar_h := 4.5
		var bar_pos := Vector2(-bar_w / 2.0, -62.0)
		var ratio := clampf(health / max_health, 0.0, 1.0)
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.1, 0.1, 0.1, 0.85), true)
		draw_rect(Rect2(bar_pos, Vector2(bar_w * ratio, bar_h)), Color(0.9, 0.25, 0.25, 0.95), true)
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.0, 0.0, 0.0, 0.8), false, 1.0)

	# Impact flash
	if damage_flash_timer > 0.0:
		draw_polyline(tower_pts, Color(1.0, 0.9, 0.9, 0.7), 2.5, true)

func serialize() -> Dictionary:
	return {
		"objective_id": objective_id,
		"objective_name": objective_name,
		"owning_faction_id": owning_faction_id,
		"current_cell": [current_cell.x, current_cell.y],
		"health": health,
		"max_health": max_health,
		"is_alive": is_alive,
		"is_captured": is_captured,
		"garrison_count": garrison_count,
		"defending_unit_ids": defending_unit_ids.duplicate()
	}

func deserialize(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	objective_id = String(data.get("objective_id", ""))
	if objective_id.is_empty():
		return false
	objective_name = String(data.get("objective_name", "Tiền Đồn Địch"))
	owning_faction_id = String(data.get("owning_faction_id", ""))
	var raw_c = data.get("current_cell")
	if raw_c is Array and raw_c.size() >= 2:
		current_cell = Vector2i(int(raw_c[0]), int(raw_c[1]))
	elif raw_c is Vector2i:
		current_cell = raw_c
	else:
		return false
	if not IsoMath.is_in_bounds(current_cell):
		return false

	max_health = maxf(1.0, float(data.get("max_health", 250.0)))
	health = clampf(float(data.get("health", 250.0)), 0.0, max_health)
	is_alive = bool(data.get("is_alive", health > 0.0))
	is_captured = bool(data.get("is_captured", not is_alive))
	garrison_count = maxi(0, int(data.get("garrison_count", 3)))
	defending_unit_ids.clear()
	var raw_def = data.get("defending_unit_ids")
	if raw_def is Array:
		for d in raw_def:
			defending_unit_ids.append(str(d))
	position = IsoMath.map_to_local(current_cell)
	damage_flash_timer = 0.0
	queue_redraw()
	return true
