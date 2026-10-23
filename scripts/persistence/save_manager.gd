class_name SaveManager
extends RefCounted
## Robust Save/Load & Persistence Subsystem for KINGDOMS UNBOUND.
## Features versioned JSON serialization, atomic disk writes (.tmp -> .json),
## automatic .bak backup preservation, corruption validation, and duplicate-free entity reconstruction.

const SAVE_SCHEMA_VERSION: int = 1
const DEFAULT_SAVE_PATH: String = "user://saves/world_save.json"
const BACKUP_SAVE_PATH: String = "user://saves/world_save.json.bak"
const TEMP_SAVE_PATH: String = "user://saves/world_save.json.tmp"


static func ensure_save_directory() -> void:
	var dir := DirAccess.open("user://")
	if dir:
		if not dir.dir_exists("saves"):
			dir.make_dir("saves")

static func serialize_world_state(world_view: Node) -> Dictionary:
	var data: Dictionary = {
		"schema_version": SAVE_SCHEMA_VERSION,
		"timestamp": Time.get_datetime_string_from_system(false, true),
		"metadata": {},
		"game_clock": {},
		"resources": {},
		"buildings": [],
		"citizens": [],
		"workplaces": {},
		"research": {},
		"factions": {},
		"pois": [],
		"victory": {},
		"fog_of_war": []
	}
	
	if world_view == null:
		return data
		
	# 1. Metadata
	data["metadata"] = {
		"world_seed": world_view.get("world_seed"),
		"difficulty": "normal"
	}
	
	# 2. Game Clock
	if Engine.has_singleton("TimeManager") or world_view.has_node("/root/TimeManager"):
		var tm: Node = world_view.get_node("/root/TimeManager")
		var spd: int = tm.get("current_speed")
		if spd == 0 and tm.get("previous_speed") != null and tm.get("previous_speed") != 0:
			spd = tm.get("previous_speed")
		elif spd == 0:
			spd = 1
		data["game_clock"] = {
			# BUG-01 fix: serialize only fields that exist on TimeManager.
			# Removed non-existent: total_elapsed_seconds, current_minute, current_season, is_paused.
			# Added season_index (the real backing field in TimeManager for the calendar season).
			"current_day": tm.get("current_day"),
			"current_hour": tm.get("current_hour"),
			"season_index": tm.get("season_index"),
			"current_year": tm.get("current_year"),
			"current_speed": spd
		}
		
	# 3. Resources
	if Engine.has_singleton("ResourceManager") or world_view.has_node("/root/ResourceManager"):
		var rm: Node = world_view.get_node("/root/ResourceManager")
		var stock_copy: Dictionary = {}
		var cap_copy: Dictionary = {}
		for res_id in rm.get("_current_stock"):
			stock_copy[res_id] = rm.call("get_available_stock", res_id)
		for res_id in rm.get("_capacities"):
			cap_copy[res_id] = rm.get("_capacities")[res_id]
			
		data["resources"] = {
			"stock": stock_copy,
			"capacities": cap_copy,
			"active_population": rm.get("active_population"),
			"is_starving": rm.call("is_starving") if rm.has_method("is_starving") else false
		}
		
	# 4. Buildings
	var world_data = world_view.get("world_data")
	if world_data != null and world_data.get("buildings") != null:
		var b_list: Array = []
		for b in world_data.buildings:
			var b_state: String = b.get("state", "active")
			var b_type: String = b.get("type", "")
			var bp: Dictionary = EconomyConfig.BLUEPRINTS.get(b_type, {})
			var default_hours: float = float(bp.get("construction_hours", 12.0))
			var b_hours: float = float(b.get("construction_hours", default_hours))
			var b_prog: float = float(b.get("construction_progress", b_hours if b_state == "active" else 0.0))
			b_list.append({
				"id": b.get("id", ""),
				"type": b_type,
				"cell_x": b.get("cell", Vector2i.ZERO).x,
				"cell_y": b.get("cell", Vector2i.ZERO).y,
				"size_x": b.get("size", Vector2i.ONE).x,
				"size_y": b.get("size", Vector2i.ONE).y,
				"state": b_state,
				"health": b.get("health", 100),
				"construction_progress": b_prog,
				"construction_hours": b_hours
			})
		data["buildings"] = b_list

	# 5. Citizens
	var cit_list: Array = world_view.get("citizen_list")
	if cit_list != null:
		var c_data_list: Array = []
		for cit in cit_list:
			if is_instance_valid(cit) and cit.call("is_alive"):
				c_data_list.append({
					"id": cit.get("citizen_id"),
					"name": cit.get("citizen_name"),
					"role": cit.get("role"),
					"cell_x": cit.get("current_cell").x,
					"cell_y": cit.get("current_cell").y,
					"hunger": cit.get("hunger"),
					"fatigue": cit.get("fatigue"),
					"health": cit.get("health"),
					"morale": cit.get("morale"),
					"carrying_resource": cit.get("carrying_resource"),
					"carrying_amount": cit.get("carrying_amount")
				})
		data["citizens"] = c_data_list

	# 6. Research
	var res_mgr = world_view.get("research_mgr")
	if res_mgr != null:
		data["research"] = {
			"active_tech_id": res_mgr.get("active_tech_id"),
			"active_progress_hours": res_mgr.get("active_progress_hours"),
			"active_required_hours": res_mgr.get("active_required_hours"),
			"unlocked_techs": res_mgr.call("get_unlocked_tech_ids")
		}

	# 7. Factions
	var fac_mgr = world_view.get("faction_mgr")
	if fac_mgr != null:
		var fac_dict: Dictionary = {}
		var all_factions = fac_mgr.call("get_all_factions")
		for f in all_factions:
			fac_dict[f.id] = {
				"id": f.id,
				"name": f.name,
				"type": f.type,
				"disposition": f.disposition,
				"opinion": f.opinion,
				"stability": f.stability,
				"military_power": f.military_power,
				"has_nap": f.has_nap,
				"has_alliance": f.has_alliance,
				"is_at_war": f.is_at_war,
				"population": f.population,
				"resources": f.resources.duplicate(),
				"strategic_goal": f.get("strategic_goal"),
				"existence_status": f.get("existence_status")
			}
		data["factions"] = {
			"factions": fac_dict
		}

	# 8. POIs
	var poi_mgr = world_view.get("poi_mgr")
	if poi_mgr != null:
		var p_list: Array = []
		for p in poi_mgr.call("get_all_pois"):
			p_list.append({
				"id": p.id,
				"name": p.name,
				"cell_x": p.cell.x,
				"cell_y": p.cell.y,
				"state": p.state,
				"reward": p.rewards
			})
		data["pois"] = p_list

	# 9. Victory & Crisis
	var vic_mgr = world_view.get("victory_mgr")
	if vic_mgr != null:
		data["victory"] = {
			"hold_hours_elapsed": vic_mgr.get("hold_hours_elapsed"),
			"is_victory_achieved": vic_mgr.get("is_victory_achieved"),
			"is_collapse_triggered": vic_mgr.get("is_collapse_triggered"),
			"peak_population": vic_mgr.get("peak_population"),
			"total_simulation_hours": vic_mgr.get("total_simulation_hours"),
			"legacy_points_earned": vic_mgr.get("legacy_points_earned"),
			"is_legacy_claimed": vic_mgr.get("is_legacy_claimed"),
			"major_events": vic_mgr.get("major_events")
		}

	# 10. Fog of War
	var fow = world_view.get("fog_of_war")
	if fow != null:
		var revealed: Array = []
		for x in range(fow.map_size):
			for y in range(fow.map_size):
				if fow.is_explored(Vector2i(x, y)):
					revealed.append([x, y])
		data["fog_of_war"] = revealed

	# 11. Workplaces (Logistics Buffers)
	var wp_mgr = world_view.get("workplace_mgr")
	if wp_mgr != null:
		var wp_dict: Dictionary = {}
		for wp in wp_mgr.call("get_all_workplaces"):
			wp_dict[wp.id] = {
				"id": wp.id,
				"building_type": wp.building_type,
				"buffer_amount": wp.buffer_amount,
				"buffer_capacity": wp.buffer_capacity
			}
		data["workplaces"] = wp_dict

	# 12. Battle Campaign
	var campaign_mgr = world_view.get("battle_campaign_mgr")
	if campaign_mgr != null and campaign_mgr.has_method("serialize"):
		data["battle_campaign"] = campaign_mgr.call("serialize")

	# 13. Player Army
	var army_mgr = world_view.get("player_army_mgr")
	if army_mgr != null and army_mgr.has_method("serialize"):
		data["player_army"] = army_mgr.call("serialize")

	# 14. Immigration Manager (DEBT-03: preserve next_citizen_index to avoid ID collisions)
	var imm_mgr = world_view.get("immigration_mgr")
	if imm_mgr != null and imm_mgr.has_method("serialize"):
		data["immigration"] = imm_mgr.call("serialize")

	return data

static func save_to_file(world_view: Node, filepath: String = DEFAULT_SAVE_PATH) -> Dictionary:
	ensure_save_directory()
	var state_dict := serialize_world_state(world_view)
	var json_string := JSON.stringify(state_dict, "\t")
	
	# Atomic write pattern: write to .tmp first
	var tmp_path := filepath + ".tmp"
	var bak_path := filepath + ".bak"
	
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		var err_msg := "Không thể mở tệp tạm để ghi: %s (Mã lỗi: %d)" % [tmp_path, FileAccess.get_open_error()]
		return {"success": false, "error": err_msg}
		
	file.store_string(json_string)
	file.flush()
	file.close()
	
	# If main save exists, backup to .bak
	if FileAccess.file_exists(filepath):
		var dir := DirAccess.open("user://")
		if dir != null:
			if FileAccess.file_exists(bak_path):
				dir.remove(bak_path)
			dir.copy(filepath, bak_path)
			dir.remove(filepath)
			
	# Move .tmp to target filepath
	var rename_dir := DirAccess.open("user://")
	if rename_dir != null:
		var rename_err := rename_dir.rename(tmp_path, filepath)
		if rename_err != OK:
			return {"success": false, "error": "Không thể hoàn tất tệp lưu trữ (Lỗi đổi tên: %d)" % rename_err}
			
	return {"success": true, "path": filepath, "bytes": json_string.length()}

static func _is_valid_integer_val(val: Variant) -> bool:
	if val is int:
		return true
	if val is float:
		return not is_nan(val) and not is_inf(val) and floor(val) == val
	return false

static func _is_valid_coord_arr(arr: Variant) -> bool:
	if not (arr is Array):
		return false
	if arr.size() != 2:
		return false
	if not _is_valid_integer_val(arr[0]) or not _is_valid_integer_val(arr[1]):
		return false
	var x := int(arr[0])
	var y := int(arr[1])
	return IsoMath.is_in_bounds(Vector2i(x, y))

static func _is_cardinal_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return abs(a.x - b.x) + abs(a.y - b.y) == 1

static func validate_save_data(json_dict: Variant) -> Dictionary:
	if not (json_dict is Dictionary):
		return {"valid": false, "error": "Dữ liệu JSON không đúng định dạng Dictionary gốc."}
		
	var schema_ver: int = json_dict.get("schema_version", -1)
	if schema_ver != SAVE_SCHEMA_VERSION:
		return {"valid": false, "error": "Phiên bản bản lưu không tương thích (Đọc được %d, yêu cầu %d)." % [schema_ver, SAVE_SCHEMA_VERSION]}
		
	var required_sections: Array[String] = ["metadata", "resources", "buildings", "citizens"]
	for sec in required_sections:
		if not json_dict.has(sec):
			return {"valid": false, "error": "Bản lưu bị thiếu mục cấu trúc cốt lõi: '%s'." % sec}

	# Validate buildings array and construction data
	var buildings_sec = json_dict.get("buildings")
	if not (buildings_sec is Array):
		return {"valid": false, "error": "Mục 'buildings' phải là một danh sách (Array)."}

	for b in buildings_sec:
		if not (b is Dictionary):
			return {"valid": false, "error": "Bản ghi công trình không đúng định dạng Dictionary."}

		var b_type: Variant = b.get("type", "")
		if not (b_type is String) or b_type == "" or not EconomyConfig.BLUEPRINTS.has(b_type):
			return {"valid": false, "error": "Loại công trình không hợp lệ: '%s'." % str(b_type)}

		var bp: Dictionary = EconomyConfig.BLUEPRINTS[b_type]
		var expected_size: Vector2i = bp.get("footprint", Vector2i(1, 1))

		var cell_x = b.get("cell_x")
		var cell_y = b.get("cell_y")
		if cell_x == null or cell_y == null:
			return {"valid": false, "error": "Tọa độ công trình '%s' thiếu cell_x hoặc cell_y." % b_type}
		if not _is_valid_integer_val(cell_x) or not _is_valid_integer_val(cell_y):
			return {"valid": false, "error": "Tọa độ công trình '%s' phải là số nguyên hợp lệ: (%s, %s)." % [b_type, str(cell_x), str(cell_y)]}

		var size_x = b.get("size_x")
		var size_y = b.get("size_y")
		var resolved_size_x: int = expected_size.x
		var resolved_size_y: int = expected_size.y

		if size_x != null:
			if not _is_valid_integer_val(size_x):
				return {"valid": false, "error": "Kích thước size_x của công trình '%s' phải là số nguyên hợp lệ: %s." % [b_type, str(size_x)]}
			if int(size_x) != expected_size.x:
				return {"valid": false, "error": "Kích thước size_x của công trình '%s' (%d) không khớp blueprint (%d)." % [b_type, int(size_x), expected_size.x]}
			resolved_size_x = int(size_x)

		if size_y != null:
			if not _is_valid_integer_val(size_y):
				return {"valid": false, "error": "Kích thước size_y của công trình '%s' phải là số nguyên hợp lệ: %s." % [b_type, str(size_y)]}
			if int(size_y) != expected_size.y:
				return {"valid": false, "error": "Kích thước size_y của công trình '%s' (%d) không khớp blueprint (%d)." % [b_type, int(size_y), expected_size.y]}
			resolved_size_y = int(size_y)

		var origin := Vector2i(int(cell_x), int(cell_y))
		var size := Vector2i(resolved_size_x, resolved_size_y)
		if not IsoMath.is_in_bounds(origin) or not IsoMath.is_in_bounds(origin + size - Vector2i(1, 1)):
			return {"valid": false, "error": "Vị trí hoặc kích thước công trình '%s' vượt quá giới hạn bản đồ: %s (%s)." % [b_type, origin, size]}

		var b_state: Variant = b.get("state", "active")
		if not (b_state is String):
			return {"valid": false, "error": "Trạng thái công trình không hợp lệ."}
		const VALID_STATES: Array[String] = ["active", "under_construction", "paused", "damaged", "destroyed", "planned"]
		if not (b_state in VALID_STATES):
			return {"valid": false, "error": "Trạng thái công trình không được nhận diện: '%s'." % b_state}

		var default_hours: float = float(bp.get("construction_hours", 12.0))
		var hours_val = b.get("construction_hours", default_hours)
		if not (hours_val is int or hours_val is float):
			return {"valid": false, "error": "Thời gian thi công không hợp lệ."}
		var b_hours: float = float(hours_val)
		if is_nan(b_hours) or is_inf(b_hours) or b_hours <= 0.0:
			return {"valid": false, "error": "Thời gian thi công của '%s' phải là số dương hữu hạn: %f." % [b_type, b_hours]}

		var prog_val = b.get("construction_progress", b_hours if b_state == "active" else 0.0)
		if not (prog_val is int or prog_val is float):
			return {"valid": false, "error": "Tiến độ thi công không hợp lệ."}
		var b_prog: float = float(prog_val)
		if is_nan(b_prog) or is_inf(b_prog):
			return {"valid": false, "error": "Tiến độ thi công không phải số hữu hạn."}
		const PROG_TOLERANCE: float = 0.001
		if b_prog < 0.0 or b_prog > (b_hours + PROG_TOLERANCE):
			return {"valid": false, "error": "Tiến độ thi công của '%s' nằm ngoài phạm vi hợp lệ [0, %f]: %f." % [b_type, b_hours, b_prog]}

	# Validate optional game_clock section
	if json_dict.has("game_clock"):
		var clock_val = json_dict.get("game_clock")
		if not (clock_val is Dictionary):
			return {"valid": false, "error": "Mục 'game_clock' phải là Dictionary."}
		if clock_val.has("current_day"):
			var c_day = clock_val.get("current_day")
			if not _is_valid_integer_val(c_day) or int(c_day) < 1:
				return {"valid": false, "error": "current_day trong game_clock phải là số nguyên hợp lệ >= 1: %s." % str(c_day)}

	# Validate optional Player Army section (Package 1L)
	if json_dict.has("player_army"):
		var army_val = json_dict.get("player_army")
		if not (army_val is Dictionary):
			return {"valid": false, "error": "Dữ liệu quân đội 'player_army' phải là Dictionary."}
		if army_val.has("soldier_count"):
			var s_count = army_val.get("soldier_count")
			if not _is_valid_integer_val(s_count):
				return {"valid": false, "error": "Quân số soldier_count phải là số nguyên hợp lệ: %s." % str(s_count)}
			if int(s_count) < 0 or int(s_count) > 1000:
				return {"valid": false, "error": "Quân số soldier_count nằm ngoài phạm vi cho phép [0, 1000]: %s." % str(s_count)}
		if army_val.has("last_upkeep_day"):
			var last_upkeep = army_val.get("last_upkeep_day")
			if not _is_valid_integer_val(last_upkeep):
				return {"valid": false, "error": "last_upkeep_day phải là số nguyên hợp lệ: %s." % str(last_upkeep)}
			if int(last_upkeep) < -1:
				return {"valid": false, "error": "last_upkeep_day không được nhỏ hơn -1: %s." % str(last_upkeep)}
			if json_dict.has("game_clock"):
				if not (json_dict["game_clock"] is Dictionary):
					return {"valid": false, "error": "Mục 'game_clock' phải là Dictionary."}
				if json_dict["game_clock"].has("current_day"):
					var clock_day = json_dict["game_clock"].get("current_day")
					if not _is_valid_integer_val(clock_day) or int(clock_day) < 1:
						return {"valid": false, "error": "current_day trong game_clock phải là số nguyên hợp lệ >= 1: %s." % str(clock_day)}
					if int(last_upkeep) > int(clock_day):
						return {"valid": false, "error": "last_upkeep_day (%d) không được lớn hơn ngày hiện tại trong game_clock (%d)." % [int(last_upkeep), int(clock_day)]}
		if army_val.has("is_supplied") and not (army_val.get("is_supplied") is bool):
			return {"valid": false, "error": "Trạng thái tiếp tế is_supplied phải là boolean."}

		# Cross-field and route continuity validation (Package 1M)
		var has_move_state: bool = army_val.has("movement_state")
		var has_current: bool = army_val.has("current_cell")
		var has_rally: bool = army_val.has("rally_cell")
		var has_dest: bool = army_val.has("destination_cell")
		var has_path: bool = army_val.has("current_path")

		if has_move_state or has_current or has_rally or has_dest or has_path:
			if not (has_move_state and has_current and has_rally and has_dest and has_path):
				return {"valid": false, "error": "Bản lưu player_army thiếu các trường di chuyển đồng bộ."}

			if not _is_valid_coord_arr(army_val.get("current_cell")):
				return {"valid": false, "error": "Tọa độ current_cell của player_army không hợp lệ hoặc nằm ngoài bản đồ: %s." % str(army_val.get("current_cell"))}
			if not _is_valid_coord_arr(army_val.get("rally_cell")):
				return {"valid": false, "error": "Tọa độ rally_cell của player_army không hợp lệ hoặc nằm ngoài bản đồ: %s." % str(army_val.get("rally_cell"))}
			if not _is_valid_coord_arr(army_val.get("destination_cell")):
				return {"valid": false, "error": "Tọa độ destination_cell của player_army không hợp lệ hoặc nằm ngoài bản đồ: %s." % str(army_val.get("destination_cell"))}

			var m_state_raw = army_val.get("movement_state")
			if not (m_state_raw is String) or not (m_state_raw in ["garrisoned", "marching", "idle_at_field"]):
				return {"valid": false, "error": "Trạng thái di chuyển movement_state của player_army không hợp lệ: %s." % str(m_state_raw)}

			var path_val = army_val.get("current_path")
			if not (path_val is Array):
				return {"valid": false, "error": "current_path của player_army phải là danh sách (Array)."}

			var cur_arr = army_val.get("current_cell")
			var ral_arr = army_val.get("rally_cell")
			var dst_arr = army_val.get("destination_cell")
			var m_state: String = String(m_state_raw)

			var cur_cell := Vector2i(int(cur_arr[0]), int(cur_arr[1]))
			var ral_cell := Vector2i(int(ral_arr[0]), int(ral_arr[1]))
			var dst_cell := Vector2i(int(dst_arr[0]), int(dst_arr[1]))

			var path_points: Array[Vector2i] = []
			for step in path_val:
				if not _is_valid_coord_arr(step):
					return {"valid": false, "error": "Điểm nút trong current_path của player_army không hợp lệ: %s." % str(step)}
				path_points.append(Vector2i(int(step[0]), int(step[1])))

			if m_state == "garrisoned":
				if not path_points.is_empty():
					return {"valid": false, "error": "Quân đội ở trạng thái garrisoned nhưng current_path không rỗng."}
				if cur_cell != ral_cell:
					return {"valid": false, "error": "Quân đội ở trạng thái garrisoned nhưng current_cell (%s) khác rally_cell (%s)." % [str(cur_cell), str(ral_cell)]}
				if dst_cell != ral_cell:
					return {"valid": false, "error": "Quân đội ở trạng thái garrisoned nhưng destination_cell (%s) khác rally_cell (%s)." % [str(dst_cell), str(ral_cell)]}
			elif m_state == "idle_at_field":
				if not path_points.is_empty():
					return {"valid": false, "error": "Quân đội ở trạng thái idle_at_field nhưng current_path không rỗng."}
				if dst_cell != cur_cell:
					return {"valid": false, "error": "Quân đội ở trạng thái idle_at_field nhưng destination_cell (%s) khác current_cell (%s)." % [str(dst_cell), str(cur_cell)]}
				if cur_cell == ral_cell:
					return {"valid": false, "error": "Quân đội ở trạng thái idle_at_field nhưng current_cell lại trùng với rally_cell (%s)." % str(cur_cell)}
			elif m_state == "marching":
				if path_points.is_empty():
					return {"valid": false, "error": "Quân đội ở trạng thái marching nhưng current_path lại rỗng."}
				if dst_cell == cur_cell:
					return {"valid": false, "error": "Quân đội ở trạng thái marching nhưng destination_cell lại trùng với current_cell (%s)." % str(cur_cell)}
				if not _is_cardinal_adjacent(cur_cell, path_points[0]):
					return {"valid": false, "error": "Điểm đầu tiên trong current_path (%s) không kề cạnh trực tiếp (cardinally adjacent) với current_cell (%s)." % [str(path_points[0]), str(cur_cell)]}
				for i in range(path_points.size() - 1):
					if not _is_cardinal_adjacent(path_points[i], path_points[i + 1]):
						return {"valid": false, "error": "Các điểm liên tiếp trong current_path (%s -> %s) không kề cạnh trực tiếp (cardinally adjacent)." % [str(path_points[i]), str(path_points[i + 1])]}
				if path_points[-1] != dst_cell:
					return {"valid": false, "error": "Điểm cuối cùng trong current_path (%s) không khớp với destination_cell (%s)." % [str(path_points[-1]), str(dst_cell)]}

	# Optional battle_campaign validation (Package 1K / 1N)
	if json_dict.has("battle_campaign"):
		var camp_val = json_dict.get("battle_campaign")
		if not (camp_val is Dictionary):
			return {"valid": false, "error": "battle_campaign phải là từ điển (Dictionary)."}
		# BUG-05 fix: serialize() uses key "offensive_sequence", not "campaign_sequence".
		# Removed dead validation block for "campaign_sequence" that never matched serialized data.
		if camp_val.has("offensive_sequence"):
			var off_seq = camp_val.get("offensive_sequence")
			if not ((off_seq is int) or (off_seq is float and off_seq == floor(off_seq))) or int(off_seq) < 0:
				return {"valid": false, "error": "offensive_sequence của battle_campaign phải là số nguyên >= 0."}
		if camp_val.has("pending_raids"):
			var p_raids = camp_val.get("pending_raids")
			if not (p_raids is Dictionary):
				return {"valid": false, "error": "pending_raids của battle_campaign phải là từ điển (Dictionary)."}
		if camp_val.has("processed_raids"):
			var pr_raids = camp_val.get("processed_raids")
			if not (pr_raids is Dictionary):
				return {"valid": false, "error": "processed_raids của battle_campaign phải là từ điển (Dictionary)."}
		if camp_val.has("scheduled_raids"):
			var raids_val = camp_val.get("scheduled_raids")
			if not (raids_val is Array):
				return {"valid": false, "error": "scheduled_raids của battle_campaign phải là danh sách (Array)."}
			for raid in raids_val:
				if not (raid is Dictionary):
					return {"valid": false, "error": "Mỗi đợt raid trong scheduled_raids phải là từ điển."}
				if raid.has("target_cell") and not _is_valid_coord_arr(raid.get("target_cell")):
					return {"valid": false, "error": "Tọa độ target_cell trong scheduled_raids không hợp lệ: %s." % str(raid.get("target_cell"))}

	# Validate optional factions section (Package 1Q)
	if json_dict.has("factions"):
		var fac_root = json_dict.get("factions")
		if not (fac_root is Dictionary):
			return {"valid": false, "error": "Mục 'factions' phải là từ điển (Dictionary)."}
		if fac_root.has("factions"):
			var facs_map = fac_root.get("factions")
			if not (facs_map is Dictionary):
				return {"valid": false, "error": "Danh sách factions trong mục 'factions' phải là từ điển (Dictionary)."}
			for fid in facs_map:
				var f_entry = facs_map[fid]
				if not (f_entry is Dictionary):
					return {"valid": false, "error": "Bản ghi thế lực '%s' phải là từ điển (Dictionary)." % str(fid)}
				if f_entry.has("strategic_goal"):
					var s_goal = f_entry.get("strategic_goal")
					if not (s_goal is String) or not FactionData.VALID_STRATEGIC_GOALS.has(s_goal):
						return {"valid": false, "error": "Mục tiêu chiến lược strategic_goal của thế lực '%s' không hợp lệ: %s." % [str(fid), str(s_goal)]}
				if f_entry.has("existence_status"):
					var e_status = f_entry.get("existence_status")
					if not (e_status is String) or not FactionData.VALID_EXISTENCE_STATUSES.has(e_status):
						return {"valid": false, "error": "Trạng thái tồn tại existence_status của thế lực '%s' không hợp lệ: %s." % [str(fid), str(e_status)]}

	return {"valid": true, "error": ""}

static func load_from_file(filepath: String = DEFAULT_SAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(filepath):
		# Check if backup exists
		var bak_path := filepath + ".bak"
		if FileAccess.file_exists(bak_path):
			print("[SaveManager] Main save not found, attempting recovery from backup: %s" % bak_path)
			filepath = bak_path
		else:
			return {"success": false, "error": "Không tìm thấy tệp bản lưu: %s" % filepath}

	var file := FileAccess.open(filepath, FileAccess.READ)
	if file == null:
		return {"success": false, "error": "Không thể đọc tệp bản lưu: %s" % filepath}

	var content := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_err := json.parse(content)
	if parse_err != OK:
		return {"success": false, "error": "Lỗi phân tích cú pháp JSON (Dòng %d: %s)" % [json.get_error_line(), json.get_error_message()]}

	var data = json.get_data()
	var val_res := validate_save_data(data)
	if not val_res["valid"]:
		return {"success": false, "error": val_res["error"]}

	return {"success": true, "data": data, "path": filepath}

static func apply_loaded_state_to_world(world_view: Node, loaded_data: Dictionary) -> Dictionary:
	if world_view == null or loaded_data.is_empty():
		return {"success": false, "error": "WorldView hoặc dữ liệu bản lưu rỗng"}

	# Validate loaded data safely before destructive world modifications begin
	var val_res := validate_save_data(loaded_data)
	if not val_res.get("valid", false):
		return {"success": false, "error": val_res.get("error", "Dữ liệu bản lưu không hợp lệ")}

	var CitizenControllerScript = preload("res://scripts/entities/citizen_controller.gd")
	var citizen_tex = load("res://assets/entities/citizen.png")

	# 1. Restore Game Clock
	var clock_data: Dictionary = loaded_data.get("game_clock", {})
	if not clock_data.is_empty() and (Engine.has_singleton("TimeManager") or world_view.has_node("/root/TimeManager")):
		var tm: Node = world_view.get_node("/root/TimeManager")
		# BUG-01 fix: restore only real TimeManager fields.
		# season_index replaces the non-existent "current_season" field.
		# Removed: total_elapsed_seconds, current_minute, is_paused (don't exist on TimeManager).
		# _hour_accumulator is intentionally not restored (resets to 0.0 = lose < 1 game-hour, acceptable).
		tm.set("current_day", clock_data.get("current_day", 1))
		tm.set("current_hour", clock_data.get("current_hour", 6))
		tm.set("season_index", clock_data.get("season_index", 0))
		tm.set("current_year", clock_data.get("current_year", 1))
		tm.set_speed(clock_data.get("current_speed", 1))

	# 2. Restore Resources
	var res_data: Dictionary = loaded_data.get("resources", {})
	if not res_data.is_empty() and (Engine.has_singleton("ResourceManager") or world_view.has_node("/root/ResourceManager")):
		var rm: Node = world_view.get_node("/root/ResourceManager")
		rm.call("reset_economy")
		var stocks: Dictionary = res_data.get("stock", {})
		for r_id in stocks:
			rm.get("_current_stock")[r_id] = stocks[r_id]
		var caps: Dictionary = res_data.get("capacities", {})
		for r_id in caps:
			rm.get("_capacities")[r_id] = caps[r_id]
		rm.set("active_population", res_data.get("active_population", 24))

	# 3. Clean and Reconstruct Buildings
	var world_data = world_view.get("world_data")
	var buildings_container = world_view.get("buildings_container")
	if buildings_container:
		for child in buildings_container.get_children():
			buildings_container.remove_child(child)
			child.queue_free()
	world_view.get("buildings_by_cell").clear()
	
	if world_data != null:
		world_data.buildings.clear()
		# Reset occupancy grid to false, then fill from loaded buildings & props
		for x in range(IsoMath.MAP_SIZE):
			for y in range(IsoMath.MAP_SIZE):
				world_data.occupancy[x][y] = false
				
		for p in world_data.props:
			world_data.occupancy[p["cell"].x][p["cell"].y] = true

		var saved_buildings: Array = loaded_data.get("buildings", [])
		for b in saved_buildings:
			var b_type: String = b["type"]
			var bp: Dictionary = EconomyConfig.BLUEPRINTS.get(b_type, {})
			var default_size: Vector2i = bp.get("footprint", Vector2i(1, 1))
			var b_origin := Vector2i(int(b["cell_x"]), int(b["cell_y"]))
			var b_size := Vector2i(int(b.get("size_x", default_size.x)), int(b.get("size_y", default_size.y)))
			var b_id: String = b["id"]
			var b_state: String = b.get("state", "active")
			var default_hours: float = float(bp.get("construction_hours", 12.0))
			var b_hours: float = float(b.get("construction_hours", default_hours))
			var b_prog: float = float(b.get("construction_progress", b_hours if b_state == "active" else 0.0))
			
			var b_dict := {
				"id": b_id,
				"type": b_type,
				"cell": b_origin,
				"size": b_size,
				"state": b_state,
				"health": b.get("health", 100),
				"construction_progress": b_prog,
				"construction_hours": b_hours
			}
			world_data.buildings.append(b_dict)
			
			# Occupancy
			for ox in range(b_size.x):
				for oy in range(b_size.y):
					var cx: int = b_origin.x + ox
					var cy: int = b_origin.y + oy
					if cx >= 0 and cx < IsoMath.MAP_SIZE and cy >= 0 and cy < IsoMath.MAP_SIZE:
						world_data.occupancy[cx][cy] = true
						world_view.get("buildings_by_cell")[Vector2i(cx, cy)] = b_type
						
			world_view.call("_instantiate_building_node", b_type, b_origin, b_size, b_state)

	# 3b. Sync Workplaces & Logistics Buffers
	if world_view.has_method("sync_workplaces_after_load"):
		var saved_wp_dict: Dictionary = loaded_data.get("workplaces", {})
		world_view.call("sync_workplaces_after_load", saved_wp_dict)

	# 4. Clean and Reconstruct Citizens (Zero Node Duplication)
	var citizens_container = world_view.get("citizens_container")
	if citizens_container:
		for child in citizens_container.get_children():
			if child.name == "ArmyMarker":
				continue
			child.queue_free()
	world_view.get("citizens_by_id").clear()
	world_view.get("citizen_list").clear()
	if world_view.get("deceased_citizen_ids") != null:
		world_view.get("deceased_citizen_ids").clear()

	var nav = world_view.get("nav")
	var job_mgr = world_view.get("job_mgr")
	var workplace_mgr = world_view.get("workplace_mgr")
	var saved_citizens: Array = loaded_data.get("citizens", [])

	for c in saved_citizens:
		var cid: String = c["id"]
		var cname: String = c["name"]
		var crole: String = c["role"]
		var c_cell := Vector2i(c["cell_x"], c["cell_y"])

		var cit = CitizenControllerScript.new()
		cit.name = cid

		var spr := Sprite2D.new()
		spr.name = "Sprite2D"
		spr.texture = citizen_tex
		spr.centered = false
		spr.offset = Vector2(-12.0, -30.0)
		cit.add_child(spr)

		cit.init_citizen(cid, cname, crole, c_cell, nav, job_mgr, workplace_mgr)
		if world_data != null and cit.has_method("set_barracks_checker"):
			cit.call("set_barracks_checker", func(b_id: String = ""): return BuildingSystem.is_barracks_active(world_data, b_id))
		if world_data != null and cit.has_method("set_construction_checker"):
			cit.call("set_construction_checker", func(b_id: String = ""): return BuildingSystem.is_building_under_construction(world_data, b_id))
		if cit.has_method("set_world_view"):
			cit.call("set_world_view", world_view)
		cit.set("hunger", c.get("hunger", 10.0))
		cit.set("fatigue", c.get("fatigue", 10.0))
		cit.set("health", c.get("health", 100.0))
		cit.set("morale", c.get("morale", 70.0))
		cit.set("carrying_resource", c.get("carrying_resource", ""))
		cit.set("carrying_amount", c.get("carrying_amount", 0))

		citizens_container.add_child(cit)
		world_view.get("citizens_by_id")[cid] = cit
		world_view.get("citizen_list").append(cit)
		cit.citizen_died.connect(func(died_id: String): world_view.call("_on_citizen_died", died_id))

	# 4b. Restore Immigration Manager state & ensure next_citizen_index never collides (DEBT-03)
	var imm_mgr = world_view.get("immigration_mgr")
	if imm_mgr != null and imm_mgr.has_method("deserialize"):
		var imm_data = loaded_data.get("immigration", {})
		if not (imm_data is Dictionary):
			imm_data = {}
		imm_mgr.call("deserialize", imm_data, saved_citizens)

	# 5. Restore Research
	var res_data_dict: Dictionary = loaded_data.get("research", {})
	var res_mgr = world_view.get("research_mgr")
	if res_mgr != null and not res_data_dict.is_empty():
		res_mgr.set("active_tech_id", res_data_dict.get("active_tech_id", ""))
		res_mgr.set("active_progress_hours", res_data_dict.get("active_progress_hours", 0.0))
		res_mgr.set("active_required_hours", res_data_dict.get("active_required_hours", 0.0))
		var unlocked_arr = res_data_dict.get("unlocked_techs", [])
		if unlocked_arr is Array:
			var d: Dictionary = res_mgr.get("_unlocked_techs")
			d.clear()
			for tid in unlocked_arr:
				d[tid] = true

	# 6. Restore Victory & Crisis State
	var vic_data: Dictionary = loaded_data.get("victory", {})
	var vic_mgr = world_view.get("victory_mgr")
	if vic_mgr != null and not vic_data.is_empty():
		vic_mgr.set("hold_hours_elapsed", vic_data.get("hold_hours_elapsed", 0.0))
		vic_mgr.set("is_victory_achieved", vic_data.get("is_victory_achieved", false))
		vic_mgr.set("is_collapse_triggered", vic_data.get("is_collapse_triggered", false))
		vic_mgr.set("peak_population", vic_data.get("peak_population", 24))
		vic_mgr.set("total_simulation_hours", vic_data.get("total_simulation_hours", 0.0))
		vic_mgr.set("legacy_points_earned", vic_data.get("legacy_points_earned", 0))
		vic_mgr.set("is_legacy_claimed", vic_data.get("is_legacy_claimed", false))

	# 7. Restore Factions
	var fac_mgr = world_view.get("faction_mgr")
	var fac_data_dict: Dictionary = loaded_data.get("factions", {}).get("factions", {})
	if fac_mgr != null and not fac_data_dict.is_empty():
		for fid in fac_data_dict:
			var f_saved = fac_data_dict[fid]
			var f_obj = fac_mgr.call("get_faction", fid)
			if f_obj != null:
				if f_saved.has("name"):
					f_obj.name = str(f_saved["name"])
				if f_saved.has("type"):
					f_obj.type = str(f_saved["type"])
				f_obj.disposition = int(f_saved.get("disposition", 1))
				f_obj.opinion = float(f_saved.get("opinion", 0.0))
				f_obj.stability = float(f_saved.get("stability", 70.0))
				f_obj.military_power = float(f_saved.get("military_power", 50.0))
				f_obj.has_nap = bool(f_saved.get("has_nap", false))
				f_obj.has_alliance = bool(f_saved.get("has_alliance", false))
				f_obj.is_at_war = bool(f_saved.get("is_at_war", false))
				f_obj.population = int(f_saved.get("population", 40))
				if f_saved.has("resources") and f_saved["resources"] is Dictionary:
					f_obj.resources = f_saved["resources"].duplicate()
				# Strategic Goal & Existence Status (Package 1Q)
				if f_saved.has("strategic_goal"):
					var s_goal = str(f_saved["strategic_goal"])
					if FactionData.VALID_STRATEGIC_GOALS.has(s_goal):
						f_obj.strategic_goal = s_goal
					else:
						f_obj.strategic_goal = FactionData.get_default_strategic_goal(f_obj.id, f_obj.type)
				else:
					f_obj.strategic_goal = FactionData.get_default_strategic_goal(f_obj.id, f_obj.type)

				if f_saved.has("existence_status"):
					var e_status = str(f_saved["existence_status"])
					if FactionData.VALID_EXISTENCE_STATUSES.has(e_status):
						f_obj.existence_status = e_status
					else:
						f_obj.existence_status = FactionData.STATUS_ACTIVE
				else:
					f_obj.existence_status = FactionData.STATUS_ACTIVE

	# 8. Restore POIs
	var poi_mgr = world_view.get("poi_mgr")
	var saved_pois: Array = loaded_data.get("pois", [])
	if poi_mgr != null and not saved_pois.is_empty():
		var saved_poi_ids := {}
		for p_data in saved_pois:
			saved_poi_ids[p_data["id"]] = true
			var p_obj = poi_mgr.call("get_poi", p_data["id"])
			if p_obj == null:
				p_obj = POIManager.POIData.new()
				p_obj.id = p_data["id"]
				p_obj.name = p_data.get("name", "")
				p_obj.cell = Vector2i(p_data.get("cell_x", 0), p_data.get("cell_y", 0))
				p_obj.rewards = p_data.get("reward", {}).duplicate()
				poi_mgr._pois[p_obj.id] = p_obj
			p_obj.state = int(p_data.get("state", 0))
		for poi in poi_mgr.call("get_all_pois"):
			if not saved_poi_ids.has(poi.id):
				poi.state = 0 # POIState.UNDISCOVERED

	# 9. Restore Fog of War
	var fow = world_view.get("fog_of_war")
	var saved_fow: Array = loaded_data.get("fog_of_war", [])
	if fow != null:
		fow.reset_fog()
		for coord in saved_fow:
			if coord is Array and coord.size() >= 2:
				var cx: int = int(coord[0])
				var cy: int = int(coord[1])
				if IsoMath.is_in_bounds(Vector2i(cx, cy)):
					fow._grid[cx][cy] = 2 # VISIBLE

	# Refresh POI visibility based on restored discovery states
	if world_view.has_method("refresh_poi_visibility"):
		world_view.call("refresh_poi_visibility")

	# Refresh HUD
	var hud = world_view.get("hud")
	if hud:
		var housing_cap: int = BuildingSystem.get_total_housing_capacity(world_data)
		hud.call("update_population_display", world_view.get("citizen_list").size(), housing_cap)
		hud.call("_refresh_all_resources")

	# 12. Restore Battle Campaign
	var campaign_mgr = world_view.get("battle_campaign_mgr")
	if campaign_mgr != null and campaign_mgr.has_method("deserialize"):
		var campaign_data = loaded_data.get("battle_campaign", {})
		if campaign_data is Dictionary and not campaign_data.is_empty():
			campaign_mgr.call("deserialize", campaign_data)
		else:
			# Legacy save or empty battle_campaign: reset campaign manager to clean default state
			campaign_mgr.call("deserialize", {})

	# 13. Restore Player Army
	var army_mgr = world_view.get("player_army_mgr")
	if army_mgr != null and army_mgr.has_method("deserialize"):
		var army_data = loaded_data.get("player_army", {})
		if army_data is Dictionary and not army_data.is_empty():
			army_mgr.call("deserialize", army_data)
		else:
			# Legacy save or empty player_army: reset to clean default state (0 soldiers)
			army_mgr.call("deserialize", {})

	if world_view.has_method("_setup_army_marker"):
		world_view.call("_setup_army_marker")

	if hud and hud.has_method("_refresh_army_panel"):
		hud.call("_refresh_army_panel")

	print("[SaveManager] Loaded world state restored successfully (%d citizens, %d buildings)" % [world_view.get("citizen_list").size(), world_data.buildings.size()])
	return {"success": true}
