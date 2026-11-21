class_name EntityInspectionQuery
extends RefCounted
## Pure Read-Only Entity Inspection Query & View-Model Builder (M6-1).
## Supports: Wildlife, Monsters, Caves / Monster Nests, POIs,
## Individual Player/Enemy Military Units, Natural Resource Nodes, and Hover Tooltips.
## Never mutates gameplay, reservations, FogOfWar, AI timers, orders, or save state.

const MonsterConfigScript = preload("res://scripts/world/monster_config.gd")

var world_view: Node = null
var _icon_cache: Dictionary = {} # key -> ImageTexture (28x28)

func setup(wv: Node) -> void:
	world_view = wv

func _get_fow() -> FogOfWar:
	return world_view.get("fog_of_war") as FogOfWar if world_view != null else null

func _is_debug_fog() -> bool:
	return bool(world_view.get("debug_fog_disabled")) if world_view != null else false

func _get_world_data() -> WorldGenerator.WorldData:
	return world_view.get("world_data") as WorldGenerator.WorldData if world_view != null else null

func _get_nav() -> GridNavigation:
	return world_view.get("nav") as GridNavigation if world_view != null else null

func _is_cell_explored(cell: Vector2i) -> bool:
	if _is_debug_fog():
		return true
	var fow := _get_fow()
	return fow != null and fow.is_explored(cell)

func _is_cell_visible(cell: Vector2i) -> bool:
	if _is_debug_fog():
		return true
	var fow := _get_fow()
	return fow != null and fow.is_visible(cell)

func _is_real_fow_visible(cell: Vector2i) -> bool:
	var fow := _get_fow()
	return fow != null and fow.is_visible(cell)

# ==============================================================================
# LOCALIZATION HELPERS
# ==============================================================================

static func biome_name_vi(biome_id: int) -> String:
	match biome_id:
		WorldGenerator.BiomeType.GRASSLAND:
			return "Đồng Cỏ"
		WorldGenerator.BiomeType.TEMPERATE_FOREST:
			return "Rừng Ôn Đới"
		WorldGenerator.BiomeType.PINE_FOREST:
			return "Rừng Thông"
		WorldGenerator.BiomeType.HIGHLANDS:
			return "Cao Nguyên"
		WorldGenerator.BiomeType.WETLANDS:
			return "Đầm Lầy"
	return "Vùng Đất Hoang"

static func wildlife_species_name_vi(species_id: String) -> String:
	match species_id:
		"bird": return "Chim Nhỏ"
		"frog": return "Ếch Đầm Lầy"
		"rabbit": return "Thỏ Rừng"
		"deer": return "Hươu Rừng"
		"wild_boar": return "Lợn Rừng"
		"mountain_goat": return "Dê Núi"
	var spec := WildlifeConfig.get_species_def(species_id)
	return str(spec.get("display_name", species_id.capitalize()))

static func wildlife_category_vi(cat: int) -> String:
	match cat:
		WildlifeConfig.Category.AMBIENT:
			return "Sinh vật cảnh quan"
		WildlifeConfig.Category.PASSIVE_HUNTABLE:
			return "Thú hiền — Có thể săn"
		WildlifeConfig.Category.DEFENSIVE:
			return "Thú phòng vệ"
	return "Động vật hoang dã"

static func wildlife_state_vi(st: int) -> String:
	match st:
		WildlifeConfig.BehaviorState.IDLE:
			return "Đang nghỉ ngơi"
		WildlifeConfig.BehaviorState.WANDERING:
			return "Đang đi kiếm ăn"
		WildlifeConfig.BehaviorState.FLEEING:
			return "Đang bỏ chạy"
		WildlifeConfig.BehaviorState.ALERT:
			return "Cảnh giác cao"
		WildlifeConfig.BehaviorState.DEFENSIVE_DISPLAY:
			return "Tư thế phòng vệ"
		WildlifeConfig.BehaviorState.BEING_HUNTED:
			return "Đang bị săn đuổi"
	return "Không xác định"

static func monster_ai_state_vi(st: int) -> String:
	match st:
		MonsterConfigScript.MonsterAIState.IDLE:
			return "Canh gác / Nghỉ ngơi"
		MonsterConfigScript.MonsterAIState.GUARDING, MonsterConfigScript.MonsterAIState.ALERT:
			return "Cảnh giới quanh ổ"
		MonsterConfigScript.MonsterAIState.ROAMING:
			return "Tuần tra lãnh địa"
		MonsterConfigScript.MonsterAIState.CHASING:
			return "Đang truy đuổi mục tiêu"
		MonsterConfigScript.MonsterAIState.ATTACKING:
			return "Đang giao chiến"
		MonsterConfigScript.MonsterAIState.RETURNING:
			return "Đang rút về ổ"
		MonsterConfigScript.MonsterAIState.DEAD:
			return "Đã bị tiêu diệt"
	return "Không rõ"

static func poi_type_label_vi(poi_type: String) -> String:
	match poi_type:
		"abandoned_camp":
			return "Trại Bỏ Hoang"
		"ancient_ruins":
			return "Phế Tích Cổ Đại"
		"forgotten_cache":
			return "Kho Tàng Lãng Quên"
		"ruins":
			return "Di Tích Cổ (Di sản)"
		"shrine":
			return "Đền Thờ Cổ (Di sản)"
	return "Địa Danh Khám Phá"

static func poi_display_name_vi(poi: Object) -> String:
	if poi == null:
		return "Địa Danh"
	var p_type: String = str(poi.get("type"))
	match p_type:
		"abandoned_camp":
			return "Trại Bỏ Hoang"
		"ancient_ruins":
			return "Phế Tích Cổ Đại"
		"forgotten_cache":
			return "Kho Tàng Lãng Quên"
		_:
			var raw_name: String = str(poi.get("name"))
			return raw_name if not raw_name.is_empty() else poi_type_label_vi(p_type)

static func poi_state_vi(poi_state: int, is_guarded: bool) -> String:
	if poi_state == POIManager.POIState.CLAIMED:
		return "Đã thu thập"
	if is_guarded or poi_state == POIManager.POIState.GUARDED:
		return "Đang bị quái canh giữ"
	if poi_state == POIManager.POIState.CLEARED:
		return "An toàn — Sẵn sàng thu thập"
	if poi_state == POIManager.POIState.DISCOVERED:
		return "Đã phát hiện"
	return "Chưa khám phá"

static func resource_role_vi(role_id: String) -> String:
	match role_id:
		"miner": return "Thợ Mỏ"
		"farmer": return "Nông Dân"
		"woodcutter": return "Tiều Phu"
	return role_id.capitalize()

static func player_order_state_vi(order_state: int) -> String:
	match order_state:
		TacticalUnit.OrderState.IDLE:
			return "Sẵn sàng nhận lệnh"
		TacticalUnit.OrderState.MOVING:
			return "Đang hành quân"
		TacticalUnit.OrderState.HOLDING:
			return "Giữ vững vị trí"
		TacticalUnit.OrderState.ATTACKING:
			return "Đang giao chiến"
	return "Sẵn sàng"

static func enemy_ai_state_vi(ai_state: int) -> String:
	match ai_state:
		EnemyTacticalUnit.AIState.HOLD:
			return "Trấn giữ vị trí"
		EnemyTacticalUnit.AIState.PATROL:
			return "Tuần tra khu vực"
		EnemyTacticalUnit.AIState.ACQUIRE_TARGET:
			return "Cảnh giới / Tìm mục tiêu"
		EnemyTacticalUnit.AIState.PURSUE:
			return "Đang truy kích"
		EnemyTacticalUnit.AIState.ATTACK:
			return "Đang tấn công"
		EnemyTacticalUnit.AIState.RECOVER_RETREAT:
			return "Đang rút lui chỉnh đốn"
	return "Cảnh giới"

func _lookup_citizen_name(cit_id: String) -> String:
	if cit_id.is_empty() or world_view == null:
		return ""
	var c_dict = world_view.get("citizens_by_id")
	if c_dict is Dictionary and c_dict.has(cit_id):
		var c_node = c_dict[cit_id]
		if c_node != null and is_instance_valid(c_node):
			var c_name = c_node.get("citizen_name")
			if c_name != null and str(c_name) != "":
				return str(c_name)
	return "Dân làng"

func _lookup_faction_name(faction_id: String) -> String:
	if faction_id.is_empty():
		return "Vương Quốc Đối Địch"
	if world_view != null:
		var fm = world_view.get("faction_manager")
		if fm != null and fm.has_method("get_faction"):
			var f = fm.call("get_faction", faction_id)
			if f != null:
				var f_name = f.get("faction_name") if f is Object else f.get("faction_name", "")
				if f_name != null and str(f_name) != "":
					return str(f_name)
	return "Thế Lực Đối Địch"

func _is_faction_at_war(faction_id: String) -> bool:
	if faction_id.is_empty() or world_view == null:
		return true
	var fm = world_view.get("faction_manager")
	if fm != null and fm.has_method("get_faction"):
		var f = fm.call("get_faction", faction_id)
		if f != null:
			var w = f.get("is_at_war") if f is Object else f.get("is_at_war", true)
			return bool(w)
	return true

# ==============================================================================
# VIEW-MODEL BUILDERS (STRICTLY READ-ONLY)
# ==============================================================================

func build_view_model(category: String, entity_id: String) -> Dictionary:
	if world_view == null or entity_id.is_empty():
		return {"valid": false}
	match category:
		"wildlife":
			return _build_wildlife_vm(entity_id)
		"monster":
			return _build_monster_vm(entity_id)
		"monster_nest":
			return _build_nest_vm(entity_id)
		"poi":
			return _build_poi_vm(entity_id)
		"military_unit":
			return _build_military_vm(entity_id)
		"natural_resource":
			return _build_resource_vm(entity_id)
	return {"valid": false}

func _build_wildlife_vm(entity_id: String) -> Dictionary:
	var wl_mgr = world_view.get("wildlife_mgr")
	if wl_mgr == null:
		return {"valid": false}
	var rec: Dictionary = wl_mgr.call("get_animal_by_id", entity_id)
	if rec.is_empty():
		return {"valid": false}
	var cell: Vector2i = rec.get("cell", Vector2i(-1, -1))
	if not _is_cell_visible(cell):
		return {"valid": false}

	var sp: String = str(rec.get("species_id", ""))
	var cat: int = int(rec.get("category", 0))
	var st: int = int(rec.get("state", 0))
	var wd := _get_world_data()
	var biome_str: String = biome_name_vi(wd.get_biome(cell)) if wd != null else "Không rõ"
	var spec: Dictionary = WildlifeConfig.get_species_def(sp)
	var huntable: bool = WildlifeConfig.is_huntable_species(sp)
	var meat_yield: int = int(rec.get("raw_meat_yield", spec.get("raw_meat_yield", 0)))
	var hunt_hours: float = float(rec.get("hunt_duration_hours", spec.get("hunt_duration_hours", 0.0)))
	var reserved_hunter_id: String = str(wl_mgr.call("get_reserved_hunter", entity_id))
	var is_reserved: bool = bool(wl_mgr.call("is_animal_reserved", entity_id)) and not reserved_hunter_id.is_empty()

	var status_color := Color(0.55, 0.90, 0.65, 1.0)
	if cat == WildlifeConfig.Category.DEFENSIVE:
		status_color = Color(0.95, 0.72, 0.30, 1.0)
	elif st == WildlifeConfig.BehaviorState.FLEEING or st == WildlifeConfig.BehaviorState.BEING_HUNTED:
		status_color = Color(0.98, 0.52, 0.32, 1.0)

	var rows: Array[Dictionary] = [
		{"section": "SINH THÁI & VỊ TRÍ"},
		{"label": "Phân loại", "value": wildlife_category_vi(cat), "color": status_color},
		{"label": "Quần xã", "value": biome_str},
		{"label": "Hành vi hiện tại", "value": wildlife_state_vi(st)},
		{"section": "KHẢ NĂNG SĂN BẮT"},
	]
	if huntable:
		rows.append({"label": "Săn bắt", "value": "Có thể săn (+%d Thịt sống / %.1f giờ)" % [meat_yield, hunt_hours], "color": Color(0.65, 0.92, 0.62, 1.0)})
	else:
		rows.append({"label": "Săn bắt", "value": "Không săn bắt (Bảo vệ tự nhiên / Cảnh quan)", "color": Color(0.75, 0.80, 0.86, 1.0)})

	if is_reserved:
		var hunter_name: String = _lookup_citizen_name(reserved_hunter_id)
		rows.append({"label": "Theo dõi săn", "value": "Đang bị %s truy tìm" % hunter_name, "color": Color(0.95, 0.78, 0.38, 1.0)})
	else:
		rows.append({"label": "Theo dõi săn", "value": "Tự do (Chưa có thợ săn nhắm tới)"})

	return {
		"valid": true,
		"category": "wildlife",
		"entity_id": entity_id,
		"icon_key": "wildlife_%s" % sp,
		"title": wildlife_species_name_vi(sp),
		"subtitle": wildlife_category_vi(cat),
		"coords_text": "Tọa độ: (%d, %d) | Quần xã: %s" % [cell.x, cell.y, biome_str],
		"cell": cell,
		"status_text": wildlife_state_vi(st),
		"status_color": status_color,
		"show_bar": false,
		"rows": rows,
		"footer_note": "Quan sát tự nhiên (Chỉ xem).",
		"action": {},
	}

func _build_monster_vm(entity_id: String) -> Dictionary:
	var m_mgr = world_view.get("monster_mgr")
	if m_mgr == null:
		return {"valid": false}
	var m: Dictionary = m_mgr.call("get_monster_record", entity_id)
	if m.is_empty():
		return {"valid": false}
	var st: int = int(m.get("state", MonsterConfigScript.MonsterAIState.DEAD))
	var hp: float = float(m.get("health", 0.0))
	if st == MonsterConfigScript.MonsterAIState.DEAD or hp <= 0.0:
		return {"valid": false}
	var cell: Vector2i = m.get("cell", Vector2i(-1, -1))
	if not _is_cell_visible(cell):
		return {"valid": false}

	var sp: String = str(m.get("species_id", ""))
	var spec: Dictionary = MonsterConfigScript.get_species_def(sp)
	var max_hp: float = maxf(1.0, float(m.get("max_health", spec.get("max_health", 75.0))))
	var wd := _get_world_data()
	var biome_str: String = biome_name_vi(wd.get_biome(cell)) if wd != null else "Không rõ"
	var atk_dmg: int = int(m.get("attack_damage", spec.get("attack_damage", 14.0)))
	var armor_val: float = float(m.get("armor", spec.get("armor", 0.0)))
	var atk_cd: float = float(m.get("attack_cooldown", spec.get("attack_cooldown", 1.0)))
	var atk_range: int = int(m.get("attack_range", spec.get("attack_range", 1)))
	var det_rad: int = int(spec.get("detection_radius", MonsterConfigScript.DETECTION_RADIUS_PATH_CELLS))
	var max_pursuit: int = int(spec.get("max_pursuit_distance", MonsterConfigScript.MAX_PURSUIT_PATH_CELLS))
	var is_displaced: bool = bool(m.get("is_displaced", false))

	var nest_id: String = str(m.get("home_nest_id", ""))
	var nest_status := "Không xác định"
	if is_displaced:
		nest_status = "Mất ổ (Phạm vi tuần tra thu hẹp)"
	elif not nest_id.is_empty() and m_mgr.has_method("get_nest_record"):
		var nd: Dictionary = m_mgr.call("get_nest_record", nest_id)
		if nd.is_empty() or bool(nd.get("is_destroyed", false)):
			nest_status = "Ổ đã bị phá hủy"
		else:
			var n_cell: Vector2i = nd.get("cell", Vector2i(-1, -1))
			nest_status = "%s (%d, %d)" % [str(nd.get("name", spec.get("nest_name", "Ổ Quái"))), n_cell.x, n_cell.y]

	var t_mgr = world_view.get("tactical_military_mgr")
	var selected_units: int = int(t_mgr.call("get_selected_count")) if (t_mgr != null and t_mgr.has_method("get_selected_count")) else 0
	var action_dict: Dictionary = {}
	if selected_units > 0:
		action_dict = {
			"action_id": "attack_monster",
			"target_id": entity_id,
			"label": "Tấn Công Quái Vật (%d lính)" % selected_units,
			"enabled": true,
			"hint": "",
		}

	var rows: Array[Dictionary] = [
		{"section": "CHỈ SỐ CHIẾN ĐẤU"},
		{"label": "Sát thương", "value": "%d (Hồi chiêu: %.1fs | Tầm: %d ô)" % [atk_dmg, atk_cd, atk_range]},
		{"label": "Giáp phòng ngự", "value": "%.0f" % armor_val},
		{"label": "Phát hiện / Truy đuổi", "value": "%d ô / tối đa %d ô" % [det_rad, max_pursuit]},
		{"section": "HÀNH VI & LÃNH ĐỊA"},
		{"label": "Trạng thái AI", "value": monster_ai_state_vi(st), "color": Color(0.95, 0.45, 0.35, 1.0)},
		{"label": "Ổ xuất phát", "value": nest_status},
	]

	return {
		"valid": true,
		"category": "monster",
		"entity_id": entity_id,
		"icon_key": "monster_%s" % sp,
		"title": str(spec.get("display_name_vi", sp.capitalize())),
		"subtitle": "Quái Vật Hoang Dã — Thù địch",
		"coords_text": "Tọa độ: (%d, %d) | Quần xã: %s" % [cell.x, cell.y, biome_str],
		"cell": cell,
		"status_text": monster_ai_state_vi(st),
		"status_color": Color(0.96, 0.36, 0.32, 1.0),
		"show_bar": true,
		"bar_value": hp,
		"bar_max": max_hp,
		"bar_text": "Sinh lực: %d / %d HP" % [int(ceil(hp)), int(round(max_hp))],
		"bar_color": Color(0.88, 0.25, 0.25, 1.0),
		"rows": rows,
		"footer_note": "Chọn quân đội để mở lệnh tấn công hoặc nhấp phải vào quái." if selected_units == 0 else "",
		"action": action_dict,
	}

func _build_nest_vm(entity_id: String) -> Dictionary:
	var m_mgr = world_view.get("monster_mgr")
	if m_mgr == null or not m_mgr.has_method("get_nest_record"):
		return {"valid": false}
	var nd: Dictionary = m_mgr.call("get_nest_record", entity_id)
	if nd.is_empty():
		return {"valid": false}
	var cell: Vector2i = nd.get("cell", Vector2i(-1, -1))
	var explored_or_discovered: bool = _is_cell_explored(cell) or bool(nd.get("discovered", false))
	if not explored_or_discovered:
		return {"valid": false}

	var is_live: bool = _is_cell_visible(cell)
	var sp: String = str(nd.get("species_id", ""))
	var spec: Dictionary = MonsterConfigScript.get_species_def(sp)
	var species_vi: String = str(spec.get("display_name_vi", sp.capitalize()))
	var wd := _get_world_data()
	var biome_str: String = biome_name_vi(wd.get_biome(cell)) if wd != null else "Không rõ"
	var destroyed: bool = bool(nd.get("is_destroyed", false))
	var nest_name: String = str(nd.get("name", spec.get("nest_name", "Ổ Quái Vật")))

	var rows: Array[Dictionary] = [
		{"section": "THÔNG TIN HANG / Ổ QUÁI"},
		{"label": "Loài cư trú", "value": species_vi},
		{"label": "Quần xã", "value": biome_str},
	]

	var status_txt := ""
	var status_col := Color(0.95, 0.45, 0.25, 1.0)
	var show_bar := false
	var bar_val := 0.0
	var bar_max := float(nd.get("max_health", MonsterConfigScript.NEST_MAX_HEALTH))
	var bar_txt := ""
	var action_dict: Dictionary = {}
	var footer_note := ""

	if not is_live:
		if destroyed:
			status_txt = "Đã bị phá hủy"
			status_col = Color(0.65, 0.65, 0.68, 1.0)
			rows.append({"label": "Tình trạng", "value": "Đã sụp đổ — Không còn sản sinh quái"})
		else:
			status_txt = "Ngoài tầm nhìn trực tiếp"
			status_col = Color(0.85, 0.75, 0.45, 1.0)
			rows.append({"label": "Trạng thái trực tiếp", "value": "Chưa có tầm nhìn tới hang ổ để đếm quái hoặc độ bền hiện tại."})
		footer_note = "Đưa dân hoặc quân đội lại gần để cập nhật thông tin trực tiếp."
	else:
		var hp: float = float(nd.get("health", 0.0))
		bar_max = maxf(1.0, float(nd.get("max_health", MonsterConfigScript.NEST_MAX_HEALTH)))
		show_bar = true
		bar_val = hp
		bar_txt = "Độ bền ổ quái: %d / %d HP" % [int(ceil(hp)), int(round(bar_max))]

		var territory_mgr = world_view.get("territory_mgr")
		var suppressed: bool = territory_mgr != null and territory_mgr.is_cell_owned(cell)
		var living_count: int = int(m_mgr.call("get_living_count_for_nest", entity_id))
		var cap: int = MonsterConfigScript.LOCAL_MONSTER_CAP_PER_NEST
		var rem_h: float = maxf(0.0, MonsterConfigScript.RESPAWN_INTERVAL_HOURS - float(nd.get("spawn_timer_hours", 0.0)))

		if destroyed:
			status_txt = "Đã bị phá hủy"
			status_col = Color(0.65, 0.65, 0.68, 1.0)
			rows.append({"section": "TRẠNG THÁI HOẠT ĐỘNG"})
			rows.append({"label": "Tình trạng", "value": "Đã bị tiêu diệt hoàn toàn"})
		else:
			status_txt = "Bị áp chế bởi lãnh thổ" if suppressed else "Đang hoạt động"
			status_col = Color(0.95, 0.78, 0.35, 1.0) if suppressed else Color(0.95, 0.42, 0.25, 1.0)
			rows.append({"section": "TRẠNG THÁI HOẠT ĐỘNG"})
			rows.append({"label": "Quái bảo vệ quanh ổ", "value": "%d / %d con" % [living_count, cap]})
			if suppressed:
				rows.append({"label": "Sản sinh quái", "value": "Tạm ngưng (Nằm trong lãnh thổ vương quốc)", "color": Color(0.62, 0.90, 0.65, 1.0)})
			elif living_count >= cap:
				rows.append({"label": "Sản sinh quái", "value": "Đã đạt giới hạn ổ (%d/%d)" % [living_count, cap]})
			else:
				rows.append({"label": "Tái sinh kế tiếp", "value": "Còn %.1f giờ" % rem_h})

			var t_mgr = world_view.get("tactical_military_mgr")
			var selected_units: int = int(t_mgr.call("get_selected_count")) if (t_mgr != null and t_mgr.has_method("get_selected_count")) else 0
			action_dict = {
				"action_id": "attack_nest",
				"target_id": entity_id,
				"label": "Tấn Công Ổ Quái" if selected_units > 0 else "Tấn Công Ổ Quái (Chưa chọn quân)",
				"enabled": selected_units > 0,
				"hint": "" if selected_units > 0 else "Hãy chọn ít nhất 1 đơn vị quân trước khi ra lệnh tấn công.",
			}

	return {
		"valid": true,
		"category": "monster_nest",
		"entity_id": entity_id,
		"icon_key": "nest_%s%s" % [sp, "_destroyed" if destroyed else ""],
		"title": nest_name,
		"subtitle": "Hang Động / Ổ Quái Vật",
		"coords_text": "Tọa độ: (%d, %d) | Quần xã: %s" % [cell.x, cell.y, biome_str],
		"cell": cell,
		"status_text": status_txt,
		"status_color": status_col,
		"show_bar": show_bar,
		"bar_value": bar_val,
		"bar_max": bar_max,
		"bar_text": bar_txt,
		"bar_color": Color(0.90, 0.42, 0.22, 1.0),
		"rows": rows,
		"footer_note": footer_note,
		"action": action_dict,
	}

func _build_poi_vm(entity_id: String) -> Dictionary:
	var poi_mgr = world_view.get("poi_mgr")
	if poi_mgr == null:
		return {"valid": false}
	var poi = poi_mgr.call("get_poi", entity_id)
	if poi == null:
		return {"valid": false}
	var cell: Vector2i = poi.cell
	if not _is_cell_explored(cell) or poi.state == POIManager.POIState.UNDISCOVERED:
		return {"valid": false}

	var p_type: String = str(poi.type)
	var m_mgr = world_view.get("monster_mgr")
	var nav := _get_nav()
	var is_live: bool = _is_cell_visible(cell)
	var guarded: bool = bool(poi_mgr.call("is_poi_guarded", poi, m_mgr, nav))
	var nearby_mil: bool = bool(poi_mgr.call("has_nearby_military_unit", poi, world_view.get("tactical_military_mgr"), nav))
	var can_claim: bool = (poi.state == POIManager.POIState.CLEARED or (poi.state == POIManager.POIState.DISCOVERED and not guarded)) and not guarded and nearby_mil and poi.state != POIManager.POIState.CLAIMED

	var reward_parts: Array[String] = []
	for r_id in poi.rewards.keys():
		var r_name: String = str(EconomyConfig.RESOURCE_NAMES_VI.get(str(r_id), str(r_id)))
		reward_parts.append("+%d %s" % [int(poi.rewards[r_id]), r_name])

	var pending_parts: Array[String] = []
	for r_id in poi.pending_rewards.keys():
		var r_name: String = str(EconomyConfig.RESOURCE_NAMES_VI.get(str(r_id), str(r_id)))
		pending_parts.append("+%d %s" % [int(poi.pending_rewards[r_id]), r_name])

	var wd := _get_world_data()
	var biome_str: String = biome_name_vi(wd.get_biome(cell)) if wd != null else "Không rõ"
	var status_txt := poi_state_vi(poi.state, guarded)
	var status_col := Color(0.95, 0.72, 0.24, 1.0)
	if poi.state == POIManager.POIState.CLAIMED:
		status_col = Color(0.65, 0.68, 0.72, 1.0)
	elif guarded:
		status_col = Color(0.95, 0.38, 0.32, 1.0)
	elif can_claim:
		status_col = Color(0.45, 0.92, 0.58, 1.0)

	var rows: Array[Dictionary] = [
		{"section": "THÔNG TIN ĐỊA DANH"},
		{"label": "Loại địa điểm", "value": poi_type_label_vi(p_type)},
	]
	if not str(poi.description).is_empty():
		rows.append({"label": "Mô tả", "value": str(poi.description)})

	rows.append({"section": "PHẦN THƯỞNG & ĐIỀU KIỆN"})
	rows.append({"label": "Chiến lợi phẩm", "value": ", ".join(reward_parts) if not reward_parts.is_empty() else "Không có"})
	if not pending_parts.is_empty():
		rows.append({"label": "Chờ kho còn chỗ", "value": ", ".join(pending_parts), "color": Color(0.95, 0.80, 0.35, 1.0)})

	var condition_txt := ""
	if poi.state == POIManager.POIState.CLAIMED:
		condition_txt = "Địa điểm đã được khám phá và thu thập hết tài nguyên."
	elif guarded:
		condition_txt = "Cần tiêu diệt toàn bộ quái vật canh giữ quanh đây (<= %d ô)." % MonsterConfigScript.POI_GUARD_RADIUS_PATH_CELLS
	elif not nearby_mil:
		condition_txt = "Điều động đơn vị quân đội áp sát (<= %d ô) để thu thập." % MonsterConfigScript.POI_CLAIM_PROXIMITY_PATH_CELLS
	elif not is_live:
		condition_txt = "Quân đội đang ở gần — sẵn sàng thu thập."
	else:
		condition_txt = "Đủ điều kiện! Có thể thu thập chiến lợi phẩm ngay."
	rows.append({"label": "Điều kiện", "value": condition_txt})

	var action_dict: Dictionary = {}
	if poi.state != POIManager.POIState.CLAIMED:
		action_dict = {
			"action_id": "claim_poi",
			"target_id": entity_id,
			"label": "Khám Phá / Thu Thập",
			"enabled": can_claim,
			"hint": "" if can_claim else condition_txt,
		}

	var poi_claimed: bool = (int(poi.state) == POIManager.POIState.CLAIMED)
	return {
		"valid": true,
		"category": "poi",
		"entity_id": entity_id,
		"icon_key": "poi_%s%s" % [p_type, "_claimed" if poi_claimed else ""],
		"title": poi_display_name_vi(poi),
		"subtitle": "Địa Danh (%s)" % poi_type_label_vi(p_type),
		"coords_text": "Tọa độ: (%d, %d) | Quần xã: %s" % [cell.x, cell.y, biome_str],
		"cell": cell,
		"status_text": status_txt,
		"status_color": status_col,
		"show_bar": false,
		"rows": rows,
		"footer_note": "",
		"action": action_dict,
	}

func _build_military_vm(entity_id: String) -> Dictionary:
	# entity_id format: "player:<unit_id>" or "enemy:<unit_id>"
	var is_player := true
	var raw_uid := entity_id
	if entity_id.begins_with("enemy:"):
		is_player = false
		raw_uid = entity_id.substr(6)
	elif entity_id.begins_with("player:"):
		is_player = true
		raw_uid = entity_id.substr(7)

	var unit_node: Node = null
	if is_player:
		var t_mgr = world_view.get("tactical_military_mgr")
		if t_mgr != null and t_mgr.has_method("get_unit"):
			unit_node = t_mgr.call("get_unit", raw_uid)
	else:
		var e_mgr = world_view.get("enemy_military_mgr")
		if e_mgr != null and e_mgr.has_method("get_all_enemies"):
			for e in e_mgr.call("get_all_enemies"):
				if e != null and is_instance_valid(e) and str(e.get("unit_id")) == raw_uid:
					unit_node = e
					break

	if unit_node == null or not is_instance_valid(unit_node) or not bool(unit_node.get("is_alive")):
		return {"valid": false}
	var cell: Vector2i = unit_node.get("current_cell")
	if not is_player and not _is_real_fow_visible(cell):
		return {"valid": false}

	var hp: float = float(unit_node.get("health"))
	var max_hp: float = maxf(1.0, float(unit_node.get("max_health")))
	var atk_dmg: float = float(unit_node.get("attack_damage"))
	var atk_range: int = int(unit_node.get("attack_range"))
	var atk_cd: float = float(unit_node.get("attack_cooldown"))
	var step_cells_per_sec: float = 1.0 / TacticalUnit.CELL_STEP_DURATION
	var u_name: String = str(unit_node.get("unit_name"))
	var u_type: String = str(unit_node.get("unit_type"))
	var u_type_vi := "Kiếm Sĩ"
	if u_type == "hostile_swordsman":
		u_type_vi = "Kiếm Sĩ Địch"
	elif u_type != "swordsman" and not u_type.is_empty():
		u_type_vi = u_type.replace("_", " ").capitalize()
	if u_name.is_empty():
		u_name = u_type_vi if is_player else "Binh Sĩ Địch"

	var wd := _get_world_data()
	var biome_str: String = biome_name_vi(wd.get_biome(cell)) if wd != null else "Không rõ"

	var faction_label := "Vương Quốc Người Chơi (Đồng minh)"
	var status_txt := ""
	var status_col := Color(0.42, 0.85, 0.98, 1.0)
	var rows: Array[Dictionary] = [
		{"section": "THÔNG TIN ĐƠN VỊ"},
		{"label": "Binh chủng", "value": u_type_vi},
	]

	if is_player:
		rows.append({"label": "Thuộc phe", "value": faction_label, "color": Color(0.45, 0.86, 0.98, 1.0)})
		var ost: int = int(unit_node.get("order_state"))
		status_txt = player_order_state_vi(ost)
		rows.append({"label": "Trạng thái lệnh", "value": status_txt})
		var grp_id: int = int(unit_node.get("control_group_id"))
		var fmt_str: String = str(unit_node.get("formation"))
		rows.append({"label": "Đội hình / Nhóm", "value": "%s%s" % [fmt_str, " | Nhóm Ctrl+%d" % grp_id if grp_id > 0 else ""]})
		var tgt_cell: Vector2i = unit_node.get("target_cell")
		var tgt_actor = unit_node.get("target_actor")
		if ost == TacticalUnit.OrderState.ATTACKING and tgt_actor != null and is_instance_valid(tgt_actor):
			var tgt_lbl := _describe_combat_target(tgt_actor)
			rows.append({"label": "Mục tiêu", "value": tgt_lbl, "color": Color(0.95, 0.58, 0.35, 1.0)})
		elif ost == TacticalUnit.OrderState.MOVING:
			rows.append({"label": "Đích hành quân", "value": "(%d, %d)" % [tgt_cell.x, tgt_cell.y]})
	else:
		var fac_id: String = str(unit_node.get("owning_faction_id"))
		var at_war := _is_faction_at_war(fac_id)
		var f_name := _lookup_faction_name(fac_id)
		faction_label = "%s (%s)" % [f_name, "Đang chiến tranh" if at_war else "Hòa bình"]
		status_col = Color(0.96, 0.36, 0.32, 1.0) if at_war else Color(0.92, 0.78, 0.42, 1.0)
		rows.append({"label": "Thuộc phe", "value": faction_label, "color": status_col})
		var ai_st: int = int(unit_node.get("ai_state"))
		status_txt = enemy_ai_state_vi(ai_st)
		rows.append({"label": "Trạng thái AI", "value": status_txt})
		if bool(unit_node.get("is_garrison_defender")):
			rows.append({"label": "Nhiệm vụ", "value": "Đồn trú bảo vệ tiền đồn"})

	rows.append({"section": "CHỈ SỐ CHIẾN ĐẤU"})
	rows.append({"label": "Sát thương", "value": "%d (Tốc độ đánh: %.1fs | Tầm: %d ô)" % [int(round(atk_dmg)), atk_cd, atk_range]})
	rows.append({"label": "Tốc độ hành quân", "value": "%.1f ô/giây" % step_cells_per_sec})

	return {
		"valid": true,
		"category": "military_unit",
		"entity_id": entity_id,
		"icon_key": "military_player" if is_player else "military_enemy",
		"title": u_name,
		"subtitle": "Quân Đội Người Chơi" if is_player else "Quân Đội Đối Địch",
		"coords_text": "Tọa độ: (%d, %d) | Quần xã: %s" % [cell.x, cell.y, biome_str],
		"cell": cell,
		"status_text": status_txt,
		"status_color": status_col,
		"show_bar": true,
		"bar_value": hp,
		"bar_max": max_hp,
		"bar_text": "Sinh lực: %d / %d HP" % [int(ceil(hp)), int(round(max_hp))],
		"bar_color": Color(0.28, 0.75, 0.92, 1.0) if is_player else Color(0.90, 0.28, 0.28, 1.0),
		"rows": rows,
		"footer_note": "Nhấp phải lên bản đồ để điều động quân đang chọn." if is_player else "Đơn vị đối địch (Chỉ xem thông tin).",
		"action": {},
	}

func _describe_combat_target(tgt: Node) -> String:
	if tgt == null or not is_instance_valid(tgt):
		return "Mục tiêu"
	if tgt.get("species_id") != null:
		var sp := str(tgt.get("species_id"))
		var spec := MonsterConfigScript.get_species_def(sp)
		if tgt.get("home_nest_id") != null:
			return str(spec.get("display_name_vi", "Quái Vật"))
		return str(spec.get("nest_name", "Ổ Quái Vật"))
	if tgt.get("objective_name") != null:
		return str(tgt.get("objective_name"))
	if tgt.get("unit_name") != null and str(tgt.get("unit_name")) != "":
		return str(tgt.get("unit_name"))
	return "Đơn vị đối địch"

func _build_resource_vm(entity_id: String) -> Dictionary:
	var nrm = world_view.get("natural_resource_mgr")
	if nrm == null:
		return {"valid": false}
	var node: Dictionary = nrm.call("get_node_by_id", entity_id)
	if node.is_empty():
		return {"valid": false}
	var cell: Vector2i = node.get("cell", Vector2i(-1, -1))
	if not _is_cell_explored(cell):
		return {"valid": false}

	var r_type: String = str(node.get("type", ""))
	var spec: Dictionary = EconomyConfig.get_natural_resource_spec(r_type)
	var r_res: String = str(node.get("resource", spec.get("resource", "")))
	var res_name_vi: String = str(EconomyConfig.RESOURCE_NAMES_VI.get(r_res, r_res.capitalize()))
	var label_vi: String = str(spec.get("label", r_type.capitalize()))
	var req_role: String = resource_role_vi(str(spec.get("required_role", "miner")))
	var yield_cycle: int = int(spec.get("yield_per_cycle", 2))
	var work_h: float = float(spec.get("work_hours", 2.0))
	var wd := _get_world_data()
	var biome_str: String = biome_name_vi(wd.get_biome(cell)) if wd != null else "Không rõ"

	var is_live: bool = _is_cell_visible(cell)
	var rows: Array[Dictionary] = [
		{"section": "THÔNG TIN TÀI NGUYÊN"},
		{"label": "Sản vật thu hoạch", "value": res_name_vi},
		{"label": "Nghề khai thác", "value": req_role},
		{"label": "Hiệu suất chuẩn", "value": "+%d %s / %.1f giờ" % [yield_cycle, res_name_vi, work_h]},
	]

	var status_txt := "Đã khám phá (Ngoài tầm nhìn)"
	var status_col := Color(0.85, 0.78, 0.45, 1.0)
	var show_bar := false
	var bar_val := 0.0
	var bar_max := 1.0
	var bar_txt := ""
	var footer_note := ""

	if not is_live:
		rows.append({"section": "TRẠNG THÁI TẦM NHÌN"})
		rows.append({"label": "Trữ lượng hiện tại", "value": "Ẩn trong sương mù — Đưa người tới gần để kiểm tra trữ lượng thực tế."})
		footer_note = "Thông tin trữ lượng chỉ cập nhật khi mỏ nằm trong tầm nhìn trực tiếp."
	else:
		var r_rem: int = int(node.get("remaining_qty", 0))
		var r_max: int = maxi(1, int(node.get("max_qty", spec.get("max_qty", 20))))
		var is_dep: bool = bool(node.get("depleted", false)) or r_rem <= 0
		var is_res: bool = bool(nrm.call("is_node_reserved", entity_id))
		var res_worker_id: String = str(nrm.reserved_by.get(entity_id, "")) if (nrm.get("reserved_by") is Dictionary) else ""

		show_bar = true
		bar_val = float(r_rem)
		bar_max = float(r_max)
		bar_txt = "Trữ lượng còn lại: %d / %d %s" % [r_rem, r_max, res_name_vi]

		rows.append({"section": "TRẠNG THÁI KHAI THÁC"})
		if is_dep:
			status_txt = "Đã cạn kiệt"
			status_col = Color(0.85, 0.35, 0.35, 1.0)
			rows.append({"label": "Tình trạng", "value": "Mỏ đã cạn kiệt hoàn toàn"})
		elif is_res and not res_worker_id.is_empty():
			status_txt = "Đang có người khai thác"
			status_col = Color(0.45, 0.90, 0.65, 1.0)
			rows.append({"label": "Phân công", "value": "%s đang khai thác" % _lookup_citizen_name(res_worker_id)})
		else:
			status_txt = "Sẵn sàng khai thác"
			status_col = Color(0.45, 0.86, 0.96, 1.0)
			rows.append({"label": "Phân công", "value": "Trống (Tự động khai thác nếu thuộc lãnh thổ)"})

	return {
		"valid": true,
		"category": "natural_resource",
		"entity_id": entity_id,
		"icon_key": "resource_%s" % r_type,
		"title": label_vi,
		"subtitle": "Tài Nguyên Thiên Nhiên — %s" % res_name_vi,
		"coords_text": "Tọa độ: (%d, %d) | Quần xã: %s" % [cell.x, cell.y, biome_str],
		"cell": cell,
		"status_text": status_txt,
		"status_color": status_col,
		"show_bar": show_bar,
		"bar_value": bar_val,
		"bar_max": bar_max,
		"bar_text": bar_txt,
		"bar_color": Color(0.32, 0.82, 0.62, 1.0),
		"rows": rows,
		"footer_note": footer_note,
		"action": {},
	}

# ==============================================================================
# CLICK TARGET RESOLUTION & HOVER SUMMARY (NO FULL-WORLD PER-FRAME SCAN)
# ==============================================================================

func find_hover_entity_summary(cell: Vector2i) -> Dictionary:
	if world_view == null or not IsoMath.is_in_bounds(cell):
		return {"valid": false}
	if not _is_cell_explored(cell):
		return {"valid": false}

	var is_live := _is_cell_visible(cell)

	# 1. Player Tactical Unit (exact or adjacent 1 tile, matches left-click)
	if world_view.has_method("_find_tactical_unit_at_cell"):
		var pu: Node2D = world_view.call("_find_tactical_unit_at_cell", cell)
		if pu != null and is_instance_valid(pu) and bool(pu.get("is_alive")):
			var uid: String = str(pu.get("unit_id"))
			var uname: String = str(pu.get("unit_name"))
			if uname.is_empty():
				uname = "Kiếm Sĩ"
			return {
				"valid": true,
				"entity_key": "military_player:%s" % uid,
				"category": "military_unit",
				"icon_key": "military_player",
				"title": uname,
				"category_label": "Quân Đội Đồng Minh",
				"status_text": "HP %d/%d • %s" % [int(ceil(float(pu.get("health")))), int(round(float(pu.get("max_health")))), player_order_state_vi(int(pu.get("order_state")))],
				"accent_color": Color(0.42, 0.86, 0.98, 1.0),
			}

	# 2. Player Citizen (visible, non-indoor)
	var cit_list = world_view.get("citizen_list")
	if cit_list is Array:
		for cit in cit_list:
			if cit != null and is_instance_valid(cit) and cit.visible and cit.get("current_cell") == cell:
				var c_name: String = str(cit.get("citizen_name")) if cit.get("citizen_name") != null else "Dân Làng"
				var role_str: String = str(cit.get("role")) if cit.get("role") != null else ""
				return {
					"valid": true,
					"entity_key": "citizen:%s" % str(cit.get("citizen_id")),
					"category": "citizen",
					"icon_key": "military_player",
					"title": c_name,
					"category_label": "Dân Làng",
					"status_text": "Nghề: %s" % role_str.capitalize(),
					"accent_color": Color(0.55, 0.85, 1.0, 1.0),
				}

	# 3. Siege Objective Outpost (cell inside footprint)
	if world_view.has_method("_find_siege_objective_at_cell"):
		var obj = world_view.call("_find_siege_objective_at_cell", cell)
		if obj != null and is_instance_valid(obj):
			return {
				"valid": true,
				"entity_key": "outpost:%s" % str(obj.get("objective_id")),
				"category": "outpost",
				"icon_key": "military_enemy",
				"title": str(obj.get("objective_name")),
				"category_label": "Tiền Đồn Đối Địch",
				"status_text": "HP %d/%d" % [int(obj.get("health")), int(obj.get("max_health"))] if is_live else "Ngoài tầm nhìn",
				"accent_color": Color(0.95, 0.55, 0.30, 1.0),
			}

	# 4. Player Building (exact footprint match via buildings_by_cell)
	if world_view.has_method("_get_building_at_cell"):
		var b_data: Dictionary = world_view.call("_get_building_at_cell", cell)
		if not b_data.is_empty():
			var b_id: String = str(b_data.get("id", ""))
			var b_type: String = str(b_data.get("type", ""))
			var bp: Dictionary = EconomyConfig.BLUEPRINTS.get(b_type, {})
			var b_title: String = str(bp.get("name_vi", b_type.capitalize()))
			var hp_str := "HP %d/100" % int(b_data.get("health", 100))
			if str(b_data.get("state", "")) == "under_construction":
				var tot: float = maxf(1.0, float(b_data.get("construction_hours", 12.0)))
				var pct: int = int((float(b_data.get("construction_progress", 0.0)) / tot) * 100.0)
				hp_str = "Đang thi công %d%%" % pct
			return {
				"valid": true,
				"entity_key": "building:%s" % b_id,
				"category": "building",
				"icon_key": "settlement_building",
				"title": b_title,
				"category_label": "Công Trình Vương Quốc",
				"status_text": hp_str,
				"accent_color": Color(0.92, 0.78, 0.35, 1.0),
			}

	# 5. Enemy Military Unit (strictly requires real FogOfWar visibility even in Fog OFF debug)
	if _is_real_fow_visible(cell) and world_view.has_method("_find_enemy_unit_at_cell"):
		var eu: Node2D = world_view.call("_find_enemy_unit_at_cell", cell)
		if eu != null and is_instance_valid(eu) and bool(eu.get("is_alive")):
			var e_uid: String = str(eu.get("unit_id"))
			var f_name := _lookup_faction_name(str(eu.get("owning_faction_id")))
			return {
				"valid": true,
				"entity_key": "military_enemy:%s" % e_uid,
				"category": "military_unit",
				"icon_key": "military_enemy",
				"title": "Binh Sĩ (%s)" % f_name,
				"category_label": "Quân Đội Đối Địch",
				"status_text": "HP %d/%d • %s" % [int(ceil(float(eu.get("health")))), int(round(float(eu.get("max_health")))), enemy_ai_state_vi(int(eu.get("ai_state")))],
				"accent_color": Color(0.96, 0.36, 0.32, 1.0),
			}

	# 6. Monsters & Caves / Monster Nests
	var m_mgr = world_view.get("monster_mgr")
	if m_mgr != null:
		if is_live and m_mgr.get("monsters") is Array:
			for m in m_mgr.monsters:
				if int(m.get("state", MonsterConfigScript.MonsterAIState.DEAD)) == MonsterConfigScript.MonsterAIState.DEAD:
					continue
				if m.get("cell") == cell:
					var sp := str(m.get("species_id", ""))
					var spec := MonsterConfigScript.get_species_def(sp)
					return {
						"valid": true,
						"entity_key": "monster:%s" % str(m["id"]),
						"category": "monster",
						"icon_key": "monster_%s" % sp,
						"title": str(spec.get("display_name_vi", sp.capitalize())),
						"category_label": "Quái Vật Thù Địch",
						"status_text": "HP %d/%d • %s" % [int(ceil(float(m["health"]))), int(round(float(m["max_health"]))), monster_ai_state_vi(int(m["state"]))],
						"accent_color": Color(0.95, 0.38, 0.32, 1.0),
					}
		if m_mgr.get("nests") is Dictionary:
			for nid in m_mgr.nests.keys():
				var nd: Dictionary = m_mgr.nests[nid]
				if nd.get("cell") == cell:
					var destroyed := bool(nd.get("is_destroyed", false))
					var sp_n := str(nd.get("species_id", ""))
					var n_status := "Đã phá hủy" if destroyed else ("HP %d/%d" % [int(ceil(float(nd["health"]))), int(round(float(nd["max_health"])))] if is_live else "Đã khám phá (Ngoài tầm nhìn)")
					return {
						"valid": true,
						"entity_key": "nest:%s" % str(nid),
						"category": "monster_nest",
						"icon_key": "nest_%s%s" % [sp_n, "_destroyed" if destroyed else ""],
						"title": str(nd.get("name", "Ổ Quái Vật")),
						"category_label": "Hang Động / Ổ Quái",
						"status_text": n_status,
						"accent_color": Color(0.65, 0.65, 0.68, 1.0) if destroyed else Color(0.95, 0.50, 0.28, 1.0),
					}

	# 7. Discovered POI
	var poi_mgr = world_view.get("poi_mgr")
	if poi_mgr != null and poi_mgr.has_method("get_poi_at"):
		var poi = poi_mgr.call("get_poi_at", cell)
		if poi != null and poi.state != POIManager.POIState.UNDISCOVERED:
			var guarded := bool(poi_mgr.call("is_poi_guarded", poi, m_mgr, _get_nav()))
			var poi_claimed: bool = (int(poi.state) == POIManager.POIState.CLAIMED)
			return {
				"valid": true,
				"entity_key": "poi:%s" % str(poi.id),
				"category": "poi",
				"icon_key": "poi_%s%s" % [str(poi.type), "_claimed" if poi_claimed else ""],
				"title": poi_display_name_vi(poi),
				"category_label": "Địa Danh (%s)" % poi_type_label_vi(str(poi.type)),
				"status_text": poi_state_vi(poi.state, guarded),
				"accent_color": Color(0.95, 0.72, 0.24, 1.0),
			}

	# 8. Visible Wildlife
	if is_live:
		var wl_mgr = world_view.get("wildlife_mgr")
		if wl_mgr != null and wl_mgr.has_method("get_all_animals"):
			for rec in wl_mgr.call("get_all_animals"):
				if rec.get("cell") == cell:
					var sp_w := str(rec.get("species_id", ""))
					return {
						"valid": true,
						"entity_key": "wildlife:%s" % str(rec["id"]),
						"category": "wildlife",
						"icon_key": "wildlife_%s" % sp_w,
						"title": wildlife_species_name_vi(sp_w),
						"category_label": wildlife_category_vi(int(rec.get("category", 0))),
						"status_text": wildlife_state_vi(int(rec.get("state", 0))),
						"accent_color": Color(0.55, 0.90, 0.65, 1.0),
					}

	# 8.5. Rival Villager / Rival Building (explored/visible via Phase 7 query)
	if world_view.has_method("get_rival_inspection_query"):
		var r_query = world_view.call("get_rival_inspection_query")
		if r_query != null:
			var r_hit: Dictionary = r_query.call("find_rival_target_at_cell", cell, Vector2.INF)
			if not r_hit.is_empty():
				var r_kind: String = str(r_hit.get("kind", ""))
				var sid: String = str(r_hit.get("settlement_id", ""))
				if r_kind == "villager":
					var vid: String = str(r_hit.get("villager_id", ""))
					var v_vm: Dictionary = r_query.call("build_villager_view_model", sid, vid)
					if bool(v_vm.get("allowed", false)):
						return {
							"valid": true,
							"entity_key": "rival_villager:%s:%s" % [sid, vid],
							"category": "rival_villager",
							"icon_key": "military_enemy",
							"title": str(v_vm.get("display_name", "Cư Dân Láng Giềng")),
							"category_label": "Cư Dân %s" % str(v_vm.get("settlement_name", "Làng Láng Giềng")),
							"status_text": str(v_vm.get("role_label", "")),
							"accent_color": Color(0.86, 0.72, 0.96, 1.0),
						}
				elif r_kind == "settlement":
					var s_vm: Dictionary = r_query.call("build_settlement_view_model", sid)
					if bool(s_vm.get("allowed", false)):
						return {
							"valid": true,
							"entity_key": "rival_settlement:%s" % sid,
							"category": "rival_settlement",
							"icon_key": "settlement_building",
							"title": str(s_vm.get("display_name", "Khu Định Cư")),
							"category_label": str(s_vm.get("faction_label", "Thế Lực Láng Giềng")),
							"status_text": "Trong tầm nhìn" if bool(s_vm.get("is_live_visible", false)) else "Ngoài tầm nhìn trực tiếp",
							"accent_color": Color(0.86, 0.72, 0.96, 1.0),
						}

	# 9. Natural Resource Node (O(1) cell lookup, respects Fog)
	var nrm = world_view.get("natural_resource_mgr")
	if nrm != null and nrm.has_method("get_node_at_cell"):
		var r_node: Dictionary = nrm.call("get_node_at_cell", cell)
		if not r_node.is_empty():
			var nid := str(r_node.get("id", ""))
			var r_type := str(r_node.get("type", ""))
			var spec := EconomyConfig.get_natural_resource_spec(r_type)
			var r_res := str(r_node.get("resource", spec.get("resource", "")))
			var res_vi := str(EconomyConfig.RESOURCE_NAMES_VI.get(r_res, r_res))
			var status_txt := "Ngoài tầm nhìn trực tiếp"
			if is_live:
				status_txt = "Còn %d/%d %s" % [int(r_node.get("remaining_qty", 0)), int(r_node.get("max_qty", 0)), res_vi]
			return {
				"valid": true,
				"entity_key": "resource:%s" % nid,
				"category": "natural_resource",
				"icon_key": "resource_%s" % r_type,
				"title": str(spec.get("label", r_type.capitalize())),
				"category_label": "Tài Nguyên Tự Nhiên",
				"status_text": status_txt,
				"accent_color": Color(0.38, 0.85, 0.65, 1.0),
			}

	return {"valid": false}

# ==============================================================================
# PROCEDURAL 28x28 PLACEHOLDER UI ICONS (NO FINAL ARTWORK ASSETS)
# ==============================================================================

func get_placeholder_icon(icon_key: String) -> Texture2D:
	if icon_key.begins_with("wildlife_"):
		var w_sp := icon_key.trim_prefix("wildlife_")
		return EntityVisualRegistry.get_wildlife_portrait_texture(w_sp)
	if icon_key.begins_with("monster_"):
		var m_sp := icon_key.trim_prefix("monster_")
		return EntityVisualRegistry.get_monster_portrait_texture(m_sp)
	if icon_key.begins_with("nest_"):
		var is_destroyed := icon_key.ends_with("_destroyed")
		var sp := icon_key.trim_prefix("nest_")
		if is_destroyed:
			sp = sp.trim_suffix("_destroyed")
		return EntityVisualRegistry.get_nest_texture(sp, is_destroyed)
	if icon_key.begins_with("poi_"):
		var is_claimed := icon_key.ends_with("_claimed")
		var p_type := icon_key.trim_prefix("poi_")
		if is_claimed:
			p_type = p_type.trim_suffix("_claimed")
		return EntityVisualRegistry.get_poi_texture(p_type, is_claimed)
	if _icon_cache.has(icon_key):
		return _icon_cache[icon_key]
	var tex := _generate_placeholder_icon(icon_key)
	_icon_cache[icon_key] = tex
	return tex

func _generate_placeholder_icon(icon_key: String) -> ImageTexture:
	var img := Image.create(28, 28, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))

	# Distinct rounded dark frame
	_fill_rect(img, 1, 1, 26, 26, Color(0.11, 0.13, 0.17, 0.92))
	_stroke_rect(img, 1, 1, 26, 26, _border_color_for_key(icon_key))

	if icon_key.begins_with("wildlife_"):
		_draw_wildlife_icon(img, icon_key.substr(9))
	elif icon_key.begins_with("monster_"):
		_draw_monster_icon(img, icon_key.substr(8))
	elif icon_key.begins_with("nest_"):
		_draw_nest_icon(img, icon_key.substr(5))
	elif icon_key.begins_with("poi_"):
		_draw_poi_icon(img, icon_key.substr(4))
	elif icon_key == "military_player":
		_draw_soldier_icon(img, Color(0.35, 0.72, 0.96, 1.0), Color(0.75, 0.88, 0.98, 1.0))
	elif icon_key == "military_enemy":
		_draw_soldier_icon(img, Color(0.88, 0.28, 0.28, 1.0), Color(0.98, 0.72, 0.72, 1.0))
	elif icon_key.begins_with("resource_"):
		_draw_resource_icon(img, icon_key.substr(9))
	elif icon_key == "settlement_building":
		_draw_poi_icon(img, "abandoned_camp")
	else:
		_fill_rect(img, 9, 9, 10, 10, Color(0.70, 0.75, 0.85, 1.0))

	return ImageTexture.create_from_image(img)

func _border_color_for_key(icon_key: String) -> Color:
	if icon_key.begins_with("wildlife_"): return Color(0.45, 0.78, 0.55, 1.0)
	if icon_key.begins_with("monster_"): return Color(0.88, 0.32, 0.28, 1.0)
	if icon_key.begins_with("nest_"): return Color(0.82, 0.45, 0.24, 1.0)
	if icon_key.begins_with("poi_"): return Color(0.90, 0.72, 0.28, 1.0)
	if icon_key == "settlement_building": return Color(0.90, 0.72, 0.28, 1.0)
	if icon_key == "military_player": return Color(0.38, 0.78, 0.96, 1.0)
	if icon_key == "military_enemy": return Color(0.90, 0.30, 0.30, 1.0)
	if icon_key.begins_with("resource_"): return Color(0.35, 0.78, 0.62, 1.0)
	return Color(0.55, 0.58, 0.66, 1.0)

func _draw_wildlife_icon(img: Image, sp: String) -> void:
	match sp:
		"bird":
			_fill_rect(img, 9, 13, 9, 5, Color(0.45, 0.72, 0.94, 1.0))
			_fill_rect(img, 15, 10, 4, 4, Color(0.55, 0.80, 0.98, 1.0))
			_fill_rect(img, 19, 11, 3, 2, Color(0.95, 0.78, 0.25, 1.0)) # beak
			_fill_rect(img, 7, 11, 5, 3, Color(0.32, 0.56, 0.80, 1.0))  # wing
		"frog":
			_fill_rect(img, 8, 15, 12, 6, Color(0.36, 0.78, 0.36, 1.0))
			_fill_rect(img, 10, 11, 3, 3, Color(0.90, 0.92, 0.35, 1.0))
			_fill_rect(img, 15, 11, 3, 3, Color(0.90, 0.92, 0.35, 1.0))
		"rabbit":
			_fill_rect(img, 9, 14, 10, 7, Color(0.86, 0.82, 0.76, 1.0))
			_fill_rect(img, 11, 7, 2, 7, Color(0.86, 0.82, 0.76, 1.0))
			_fill_rect(img, 15, 7, 2, 7, Color(0.86, 0.82, 0.76, 1.0))
			_fill_rect(img, 14, 15, 2, 2, Color(0.95, 0.55, 0.60, 1.0))
		"deer":
			_fill_rect(img, 9, 14, 10, 6, Color(0.76, 0.52, 0.30, 1.0))
			_fill_rect(img, 10, 20, 2, 4, Color(0.62, 0.42, 0.24, 1.0))
			_fill_rect(img, 16, 20, 2, 4, Color(0.62, 0.42, 0.24, 1.0))
			_fill_rect(img, 16, 9, 4, 5, Color(0.76, 0.52, 0.30, 1.0))
			_fill_rect(img, 15, 5, 2, 4, Color(0.88, 0.78, 0.58, 1.0)) # antlers
			_fill_rect(img, 19, 5, 2, 4, Color(0.88, 0.78, 0.58, 1.0))
		"wild_boar":
			_fill_rect(img, 7, 13, 13, 8, Color(0.45, 0.30, 0.24, 1.0))
			_fill_rect(img, 19, 15, 3, 4, Color(0.60, 0.42, 0.34, 1.0))
			_fill_rect(img, 20, 18, 2, 3, Color(0.96, 0.94, 0.86, 1.0)) # tusk
		"mountain_goat":
			_fill_rect(img, 8, 14, 11, 6, Color(0.88, 0.88, 0.86, 1.0))
			_fill_rect(img, 16, 10, 4, 5, Color(0.88, 0.88, 0.86, 1.0))
			_fill_rect(img, 15, 6, 4, 3, Color(0.48, 0.42, 0.38, 1.0)) # horns
			_fill_rect(img, 10, 20, 2, 4, Color(0.65, 0.65, 0.65, 1.0))
			_fill_rect(img, 15, 20, 2, 4, Color(0.65, 0.65, 0.65, 1.0))

func _draw_monster_icon(img: Image, sp: String) -> void:
	var body_c := Color(0.72, 0.24, 0.22, 1.0)
	var eye_c := Color(1.0, 0.85, 0.25, 1.0)
	if sp == "marsh_crawler":
		body_c = Color(0.32, 0.58, 0.34, 1.0)
		eye_c = Color(0.75, 1.0, 0.35, 1.0)
	elif sp == "stone_brute":
		body_c = Color(0.52, 0.50, 0.56, 1.0)
		eye_c = Color(0.98, 0.55, 0.20, 1.0)
	_fill_rect(img, 7, 10, 14, 11, body_c)
	_fill_rect(img, 6, 7, 4, 4, body_c.lightened(0.18))
	_fill_rect(img, 18, 7, 4, 4, body_c.lightened(0.18))
	_fill_rect(img, 9, 13, 3, 2, eye_c)
	_fill_rect(img, 16, 13, 3, 2, eye_c)
	_fill_rect(img, 10, 18, 8, 2, Color(0.92, 0.92, 0.90, 1.0)) # fangs

func _draw_nest_icon(img: Image, sp: String) -> void:
	var stone := Color(0.42, 0.39, 0.42, 1.0)
	var accent := Color(0.95, 0.45, 0.25, 1.0)
	if sp == "marsh_crawler":
		stone = Color(0.30, 0.42, 0.32, 1.0)
		accent = Color(0.62, 0.88, 0.42, 1.0)
	elif sp == "stone_brute":
		stone = Color(0.48, 0.46, 0.52, 1.0)
		accent = Color(0.94, 0.58, 0.22, 1.0)
	_fill_rect(img, 5, 10, 18, 12, stone)
	_fill_rect(img, 8, 7, 12, 4, stone.lightened(0.12))
	_fill_rect(img, 9, 13, 10, 9, Color(0.06, 0.06, 0.09, 1.0)) # cavern void
	_fill_rect(img, 11, 16, 2, 2, accent) # glowing cave eyes
	_fill_rect(img, 15, 16, 2, 2, accent)

func _draw_poi_icon(img: Image, poi_type: String) -> void:
	match poi_type:
		"abandoned_camp":
			# Pitched canvas tent + dying campfire embers
			_fill_rect(img, 6, 11, 11, 10, Color(0.74, 0.62, 0.44, 1.0))
			_fill_rect(img, 9, 8, 5, 3, Color(0.62, 0.50, 0.34, 1.0))
			_fill_rect(img, 9, 14, 5, 7, Color(0.22, 0.16, 0.12, 1.0))
			_fill_rect(img, 18, 17, 5, 4, Color(0.45, 0.28, 0.16, 1.0)) # firewood
			_fill_rect(img, 19, 14, 3, 3, Color(0.98, 0.58, 0.18, 1.0)) # ember
		"ancient_ruins":
			# Stone pillars + faint cyan crystal glyph
			_fill_rect(img, 6, 8, 4, 14, Color(0.55, 0.58, 0.64, 1.0))
			_fill_rect(img, 18, 10, 4, 12, Color(0.55, 0.58, 0.64, 1.0))
			_fill_rect(img, 5, 20, 18, 3, Color(0.40, 0.43, 0.48, 1.0))
			_fill_rect(img, 12, 10, 4, 8, Color(0.32, 0.88, 0.95, 1.0)) # crystal glyph
		"forgotten_cache":
			# Mossy iron-bound treasure/supply chest
			_fill_rect(img, 6, 12, 16, 10, Color(0.58, 0.38, 0.20, 1.0))
			_fill_rect(img, 6, 11, 16, 3, Color(0.72, 0.50, 0.26, 1.0))
			_fill_rect(img, 6, 15, 16, 2, Color(0.84, 0.72, 0.30, 1.0)) # brass band
			_fill_rect(img, 12, 14, 4, 4, Color(0.95, 0.82, 0.32, 1.0)) # clasp
			_fill_rect(img, 7, 10, 5, 2, Color(0.35, 0.62, 0.32, 1.0))  # moss
		_:
			# Legacy ruins/shrine neutral pillar
			_fill_rect(img, 8, 8, 12, 14, Color(0.62, 0.62, 0.68, 1.0))
			_fill_rect(img, 11, 11, 6, 8, Color(0.85, 0.72, 0.35, 1.0))

func _draw_soldier_icon(img: Image, crest_col: Color, steel_col: Color) -> void:
	# Neutral Soldier Silhouette: Visored helm + shield + sword blade
	_fill_rect(img, 10, 6, 8, 7, steel_col)         # helm dome
	_fill_rect(img, 12, 4, 4, 3, crest_col)         # helm crest
	_fill_rect(img, 11, 9, 6, 2, Color(0.12, 0.14, 0.18, 1.0)) # visor slit
	_fill_rect(img, 8, 13, 12, 8, crest_col)        # surcoat torso
	_fill_rect(img, 6, 14, 5, 7, steel_col.darkened(0.15)) # kite shield
	_fill_rect(img, 20, 8, 2, 11, Color(0.86, 0.90, 0.95, 1.0)) # blade
	_fill_rect(img, 19, 18, 4, 2, Color(0.78, 0.65, 0.28, 1.0)) # hilt

func _draw_resource_icon(img: Image, r_type: String) -> void:
	match r_type:
		"ore_deposit":
			_fill_rect(img, 6, 12, 16, 10, Color(0.45, 0.44, 0.46, 1.0))
			_fill_rect(img, 9, 14, 4, 4, Color(0.82, 0.56, 0.32, 1.0))
			_fill_rect(img, 16, 15, 4, 4, Color(0.88, 0.65, 0.36, 1.0))
		"crystal_vein":
			_fill_rect(img, 7, 16, 14, 6, Color(0.38, 0.40, 0.46, 1.0))
			_fill_rect(img, 10, 8, 4, 10, Color(0.35, 0.85, 0.96, 1.0))
			_fill_rect(img, 15, 10, 4, 8, Color(0.55, 0.92, 1.0, 1.0))
		"herb_patch":
			_fill_rect(img, 7, 14, 14, 7, Color(0.24, 0.56, 0.28, 1.0))
			_fill_rect(img, 9, 10, 4, 5, Color(0.42, 0.82, 0.42, 1.0))
			_fill_rect(img, 15, 11, 4, 4, Color(0.68, 0.92, 0.45, 1.0))
		"berry_bush":
			_fill_rect(img, 6, 11, 16, 10, Color(0.22, 0.52, 0.24, 1.0))
			_fill_rect(img, 9, 13, 3, 3, Color(0.88, 0.24, 0.32, 1.0))
			_fill_rect(img, 15, 15, 3, 3, Color(0.92, 0.28, 0.36, 1.0))
			_fill_rect(img, 13, 11, 3, 3, Color(0.88, 0.24, 0.32, 1.0))
		_:
			_fill_rect(img, 8, 10, 12, 12, Color(0.55, 0.72, 0.55, 1.0))

static func _fill_rect(img: Image, x: int, y: int, w: int, h: int, col: Color) -> void:
	for py in range(maxi(0, y), mini(img.get_height(), y + h)):
		for px in range(maxi(0, x), mini(img.get_width(), x + w)):
			img.set_pixel(px, py, col)

static func _stroke_rect(img: Image, x: int, y: int, w: int, h: int, col: Color) -> void:
	for px in range(maxi(0, x), mini(img.get_width(), x + w)):
		if y >= 0 and y < img.get_height(): img.set_pixel(px, y, col)
		if y + h - 1 >= 0 and y + h - 1 < img.get_height(): img.set_pixel(px, y + h - 1, col)
	for py in range(maxi(0, y), mini(img.get_height(), y + h)):
		if x >= 0 and x < img.get_width(): img.set_pixel(x, py, col)
		if x + w - 1 >= 0 and x + w - 1 < img.get_width(): img.set_pixel(x + w - 1, py, col)
