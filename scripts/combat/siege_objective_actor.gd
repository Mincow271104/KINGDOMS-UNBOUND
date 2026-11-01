class_name SiegeObjectiveActor
extends Node2D
## Field Siege Objective Actor (Package 1X & Package 2G)
## Represents a fortified hostile outpost or stronghold on the isometric world map.
## Features durability health pool, garrison defense coordination, dimetric rendering,
## health bar display, damage reception, capture state transitions, and persistent territorial control.

@export var objective_id: String = ""
@export var objective_name: String = "Tiền Đồn Địch"
@export var owning_faction_id: String = ""
@export var original_owner_id: String = ""
@export var previous_owner_id: String = ""
@export var capture_revision: int = 0
@export var last_capture_tx_id: String = ""
@export var current_cell: Vector2i = Vector2i(0, 0)
@export var health: float = 250.0
@export var max_health: float = 250.0
@export var is_alive: bool = true
@export var is_captured: bool = false
@export var is_under_active_siege: bool = false
@export var garrison_count: int = 3
@export var defending_unit_ids: Array[String] = []

signal objective_damaged(obj_id: String, amount: float, current_hp: float, max_hp: float)
signal objective_destroyed(obj_id: String, killer_id: String)
signal objective_captured(obj_id: String, new_owner_id: String)
signal objective_ownership_changed(obj_id: String, prev_owner: String, new_owner: String, tx_id: String)

var damage_flash_timer: float = 0.0
var faction_manager: Object = null

func _get_faction_manager() -> Object:
	if faction_manager != null:
		return faction_manager
	var p = get_parent()
	while p != null:
		if p.get("faction_mgr") != null:
			return p.get("faction_mgr")
		if p.get("faction_manager") != null:
			return p.get("faction_manager")
		p = p.get_parent()
	return null

func is_valid_owner_id(owner_id: String) -> bool:
	if owner_id.strip_edges().is_empty():
		return false
	if owner_id == "player":
		return true
	var fm = _get_faction_manager()
	if fm != null:
		if fm.has_method("get_faction"):
			return fm.get_faction(owner_id) != null
		elif fm.has_method("has_faction"):
			return fm.has_faction(owner_id)
		return false
	return false

func _ready() -> void:
	y_sort_enabled = true
	position = IsoMath.map_to_local(current_cell)
	if original_owner_id.is_empty() and not owning_faction_id.is_empty():
		original_owner_id = owning_faction_id

func take_damage(amount: float, attacker_id: String = "") -> void:
	# Package 2G: is_captured does not prevent taking damage if outpost is alive under active siege
	if not is_alive or amount <= 0.0 or not is_under_active_siege:
		return

	health = clampf(health - amount, 0.0, max_health)
	damage_flash_timer = 0.25
	objective_damaged.emit(objective_id, amount, health, max_health)

	if health <= 0.0:
		health = 0.0
		is_alive = false
		is_captured = true
		objective_destroyed.emit(objective_id, attacker_id)
		objective_captured.emit(objective_id, "player")

	queue_redraw()

func transfer_ownership(new_owner_id: String, tx_id: String = "") -> Dictionary:
	if tx_id.strip_edges().is_empty():
		return {
			"success": false,
			"already_applied": false,
			"reason": "Mã giao dịch (tx_id) không được rỗng hoặc chỉ chứa khoảng trắng"
		}

	if not is_valid_owner_id(new_owner_id):
		return {
			"success": false,
			"already_applied": false,
			"reason": "Chủ sở hữu mới không hợp lệ hoặc chưa được xác thực: %s" % new_owner_id
		}

	# Idempotency check: duplicate transaction ID
	if last_capture_tx_id == tx_id:
		return {
			"success": true,
			"already_applied": true,
			"reason": "Giao dịch %s đã được áp dụng trước đó" % tx_id,
			"objective_id": objective_id,
			"current_owner": owning_faction_id
		}

	# Idempotency check: already owned by new owner
	if owning_faction_id == new_owner_id:
		return {
			"success": true,
			"already_applied": true,
			"reason": "Tiền đồn %s đã thuộc về %s" % [objective_id, new_owner_id],
			"objective_id": objective_id,
			"current_owner": owning_faction_id
		}

	var prev_owner := owning_faction_id
	if original_owner_id.is_empty():
		original_owner_id = prev_owner
	previous_owner_id = prev_owner
	owning_faction_id = new_owner_id
	capture_revision += 1
	last_capture_tx_id = tx_id

	# Package 2G Post-Capture Contract: 35% health recovery, alive, not permanently dead
	is_captured = true
	is_alive = true
	is_under_active_siege = false
	health = clampf(round(max_health * 0.35), 1.0, max_health)

	if new_owner_id == "player":
		objective_name = "Tiền Đồn Vương Quốc"
	else:
		objective_name = "Tiền Đồn %s" % new_owner_id.capitalize()

	defending_unit_ids.clear()
	damage_flash_timer = 0.0
	queue_redraw()

	objective_captured.emit(objective_id, new_owner_id)
	objective_ownership_changed.emit(objective_id, prev_owner, new_owner_id, tx_id)

	return {
		"success": true,
		"already_applied": false,
		"reason": "Chuyển giao quyền kiểm soát thành công",
		"objective_id": objective_id,
		"prev_owner": prev_owner,
		"new_owner": new_owner_id,
		"capture_revision": capture_revision,
		"tx_id": tx_id
	}

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

	# Package 2G: Dynamic Faction banner distinguishing owner
	var banner_color: Color
	match owning_faction_id:
		"player":
			banner_color = Color(0.2, 0.45, 0.95, 0.95) # Royal Blue
		"rival_military":
			banner_color = Color(0.85, 0.2, 0.2, 0.95) # Crimson Red
		"rival_merchant":
			banner_color = Color(0.92, 0.72, 0.15, 0.95) # Amber Gold
		"neutral_tribe":
			banner_color = Color(0.2, 0.75, 0.35, 0.95) # Forest Green
		_:
			banner_color = Color(0.65, 0.65, 0.65, 0.95)

	var banner_pts := PackedVector2Array([
		Vector2(0, -40),
		Vector2(0, -54),
		Vector2(12, -48),
		Vector2(0, -42)
	])
	draw_colored_polygon(banner_pts, banner_color)
	var pole_color := Color(0.85, 0.7, 0.2) if owning_faction_id == "player" else Color(0.1, 0.1, 0.1)
	draw_line(Vector2(0, -40), Vector2(0, -56), pole_color, 1.5)

	# Package 2G: Visual distinction for captured outposts (conquest finial crest)
	if is_captured:
		draw_circle(Vector2(0, -56), 2.2, Color(1.0, 0.85, 0.2, 1.0))

	# Health bar on top
	if is_alive:
		var bar_w := 36.0
		var bar_h := 4.5
		var bar_pos := Vector2(-bar_w / 2.0, -62.0)
		var ratio := clampf(health / max_health, 0.0, 1.0)
		var hp_fill_color := Color(0.25, 0.85, 0.45, 0.95) if owning_faction_id == "player" else Color(0.9, 0.25, 0.25, 0.95)
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.1, 0.1, 0.1, 0.85), true)
		draw_rect(Rect2(bar_pos, Vector2(bar_w * ratio, bar_h)), hp_fill_color, true)
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.0, 0.0, 0.0, 0.8), false, 1.0)

	# Impact flash
	if damage_flash_timer > 0.0:
		draw_polyline(tower_pts, Color(1.0, 0.9, 0.9, 0.7), 2.5, true)

func serialize() -> Dictionary:
	return {
		"objective_id": objective_id,
		"objective_name": objective_name,
		"owning_faction_id": owning_faction_id,
		"original_owner_id": original_owner_id,
		"previous_owner_id": previous_owner_id,
		"capture_revision": capture_revision,
		"last_capture_tx_id": last_capture_tx_id,
		"current_cell": [current_cell.x, current_cell.y],
		"health": health,
		"max_health": max_health,
		"is_alive": is_alive,
		"is_captured": is_captured,
		"is_under_active_siege": is_under_active_siege,
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
	original_owner_id = String(data.get("original_owner_id", ""))
	if original_owner_id.is_empty():
		original_owner_id = owning_faction_id
	previous_owner_id = String(data.get("previous_owner_id", ""))
	capture_revision = maxi(0, int(data.get("capture_revision", 0)))
	last_capture_tx_id = String(data.get("last_capture_tx_id", ""))

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
	is_captured = bool(data.get("is_captured", false))
	is_under_active_siege = bool(data.get("is_under_active_siege", false))
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
