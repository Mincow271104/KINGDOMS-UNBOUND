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
			"total_elapsed_seconds": tm.get("total_elapsed_seconds"),
			"current_day": tm.get("current_day"),
			"current_hour": tm.get("current_hour"),
			"current_minute": tm.get("current_minute"),
			"current_season": tm.get("current_season"),
			"current_year": tm.get("current_year"),
			"current_speed": spd,
			"is_paused": tm.get("is_paused")
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
			b_list.append({
				"id": b.get("id", ""),
				"type": b.get("type", ""),
				"cell_x": b.get("cell", Vector2i.ZERO).x,
				"cell_y": b.get("cell", Vector2i.ZERO).y,
				"size_x": b.get("size", Vector2i.ONE).x,
				"size_y": b.get("size", Vector2i.ONE).y,
				"state": b.get("state", "active"),
				"health": b.get("health", 100)
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
				"population": f.population
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

	var CitizenControllerScript = preload("res://scripts/entities/citizen_controller.gd")
	var citizen_tex = load("res://assets/entities/citizen.png")

	# 1. Restore Game Clock
	var clock_data: Dictionary = loaded_data.get("game_clock", {})
	if not clock_data.is_empty() and (Engine.has_singleton("TimeManager") or world_view.has_node("/root/TimeManager")):
		var tm: Node = world_view.get_node("/root/TimeManager")
		tm.set("total_elapsed_seconds", clock_data.get("total_elapsed_seconds", 0.0))
		tm.set("current_day", clock_data.get("current_day", 1))
		tm.set("current_hour", clock_data.get("current_hour", 6))
		tm.set("current_minute", clock_data.get("current_minute", 0))
		tm.set("current_season", clock_data.get("current_season", 0))
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
			var b_origin := Vector2i(b["cell_x"], b["cell_y"])
			var b_size := Vector2i(b["size_x"], b["size_y"])
			var b_type: String = b["type"]
			var b_id: String = b["id"]
			
			var b_dict := {
				"id": b_id,
				"type": b_type,
				"cell": b_origin,
				"size": b_size,
				"state": b.get("state", "active"),
				"health": b.get("health", 100)
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
						
			world_view.call("_instantiate_building_node", b_type, b_origin, b_size)

	# 3b. Sync Workplaces & Logistics Buffers
	if world_view.has_method("sync_workplaces_after_load"):
		var saved_wp_dict: Dictionary = loaded_data.get("workplaces", {})
		world_view.call("sync_workplaces_after_load", saved_wp_dict)

	# 4. Clean and Reconstruct Citizens (Zero Node Duplication)
	var citizens_container = world_view.get("citizens_container")
	if citizens_container:
		for child in citizens_container.get_children():
			child.queue_free()
	world_view.get("citizens_by_id").clear()
	world_view.get("citizen_list").clear()

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
				f_obj.disposition = int(f_saved.get("disposition", 1))
				f_obj.opinion = float(f_saved.get("opinion", 0.0))
				f_obj.stability = float(f_saved.get("stability", 70.0))
				f_obj.military_power = float(f_saved.get("military_power", 50.0))
				f_obj.has_nap = bool(f_saved.get("has_nap", false))
				f_obj.has_alliance = bool(f_saved.get("has_alliance", false))
				f_obj.is_at_war = bool(f_saved.get("is_at_war", false))
				f_obj.population = int(f_saved.get("population", 40))

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

	print("[SaveManager] Loaded world state restored successfully (%d citizens, %d buildings)" % [world_view.get("citizen_list").size(), world_data.buildings.size()])
	return {"success": true}
