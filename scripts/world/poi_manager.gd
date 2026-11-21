class_name POIManager
extends RefCounted
## Points of Interest (POI) Management System for KINGDOMS UNBOUND.
## Manages deterministic world exploration sites, Phase 9 Guarded/Cleared/Looted lifecycle,
## capacity-aware pending rewards, and single-claim persistent discovery rewards.

const MonsterConfigScript := preload("res://scripts/world/monster_config.gd")

enum POIState {
	UNDISCOVERED = 0,
	DISCOVERED = 1,
	CLAIMED = 2,
	GUARDED = 3,
	CLEARED = 4
}

const LOOTED: int = POIState.CLAIMED

class POIData:
	var id: String
	var type: String
	var name: String
	var cell: Vector2i
	var state: int = POIState.UNDISCOVERED
	var rewards: Dictionary = {}
	var pending_rewards: Dictionary = {}
	var reward_claim_initiated: bool = false
	var description: String = ""

var _pois: Dictionary = {} # id -> POIData

signal poi_revealed(poi: POIData)
signal poi_reward_claimed(poi: POIData, rewards: Dictionary)
signal poi_state_changed(poi: POIData)

func generate_pois(seed_val: int, walkable_cells: Array, count: int = 4, use_phase9_defs: bool = false, excluded_cells: Dictionary = {}, settlement_center: Vector2i = Vector2i(-1, -1)) -> void:
	_pois.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 7777

	var poi_types: Array[Dictionary] = []
	if use_phase9_defs:
		poi_types = MonsterConfigScript.get_phase9_poi_defs()
	else:
		poi_types = [
			{
				"type": "ancient_ruins",
				"name": "Phế Tích Cổ Đại",
				"rewards": {
					EconomyConfig.RES_GOLD: 50,
					EconomyConfig.RES_CRYSTAL: 10,
					EconomyConfig.RES_STONE: 20
				},
				"desc": "Di tích của đế chế đã lụi tàn, chứa vàng bạc và pha lê huyền bí."
			},
			{
				"type": "abandoned_mine",
				"name": "Mỏ Quặng Bỏ Hoang",
				"rewards": {
					EconomyConfig.RES_STONE: 40,
					EconomyConfig.RES_METAL: 20,
					EconomyConfig.RES_TOOLS: 10
				},
				"desc": "Khu mỏ bị lãng quên từ thời chiến tranh, còn lưu trữ công cụ và kim loại giá trị."
			},
			{
				"type": "sacred_grove",
				"name": "Khu Rừng Thiêng",
				"rewards": {
					EconomyConfig.RES_WOOD: 40,
					EconomyConfig.RES_HERBS: 30
				},
				"desc": "Khu rừng rậm rạp được thiên nhiên bao bọc, cung cấp thảo dược thượng hạng và gỗ quý."
			},
			{
				"type": "ancient_shrine",
				"name": "Đền Thờ Cổ",
				"rewards": {
					EconomyConfig.RES_GOLD: 40,
					EconomyConfig.RES_HERBS: 20,
					EconomyConfig.RES_CRYSTAL: 5
				},
				"desc": "Đền thờ cổ kính mang lại phước lành và báu vật cho người tìm thấy."
			}
		]

	var target_count: int = count
	if use_phase9_defs and count < 0:
		target_count = rng.randi_range(MonsterConfigScript.POI_MIN_INITIAL_COUNT, MonsterConfigScript.POI_MAX_INITIAL_COUNT)

	# Select cells that are sufficiently far from central settlement plaza
	var candidate_cells: Array[Vector2i] = []
	var map_w: int = IsoMath.get_active_map_width()
	var map_h: int = IsoMath.get_active_map_height()
	var center: Vector2i = settlement_center if settlement_center != Vector2i(-1, -1) else Vector2i(map_w / 2, map_h / 2)
	var min_dist: int = 14 if use_phase9_defs else 12
	var max_dist: int = maxi(28, mini(map_w, map_h) / 2 - 4)
	for c in walkable_cells:
		if excluded_cells.has(c):
			continue
		var dist := IsoMath.grid_distance(c, center)
		if dist >= min_dist and dist <= max_dist:
			candidate_cells.append(c)

	if candidate_cells.is_empty() and not use_phase9_defs:
		candidate_cells = walkable_cells.duplicate()

	# Shuffle candidate cells deterministically
	for i in range(candidate_cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var temp = candidate_cells[i]
		candidate_cells[i] = candidate_cells[j]
		candidate_cells[j] = temp

	var placed_cells: Array[Vector2i] = []
	var type_schedule: Array[int] = []
	if use_phase9_defs:
		# Suggested composition: 3-4 Abandoned Camps (0), 2-3 Ancient Ruins (1), 1-3 Forgotten Caches (2)
		type_schedule = [0, 0, 0, 1, 1, 2, 0, 1, 2, 2]

	var idx := 0
	for c in candidate_cells:
		if placed_cells.size() >= target_count:
			break
		if use_phase9_defs:
			var too_close := false
			for pc in placed_cells:
				if IsoMath.grid_distance(c, pc) < MonsterConfigScript.POI_MIN_SPACING:
					too_close = true
					break
			if too_close:
				continue

		var t_idx: int = type_schedule[idx % type_schedule.size()] if use_phase9_defs else (idx % poi_types.size())
		var p_info: Dictionary = poi_types[t_idx]
		idx += 1

		var poi := POIData.new()
		poi.id = "poi_%d" % idx
		poi.type = p_info["type"]
		poi.name = p_info["name"]
		poi.cell = c
		poi.rewards = p_info["rewards"].duplicate()
		poi.pending_rewards = {}
		poi.reward_claim_initiated = false
		poi.description = p_info["desc"]
		poi.state = POIState.UNDISCOVERED

		_pois[poi.id] = poi
		placed_cells.append(c)

func get_all_pois() -> Array:
	return _pois.values()

func get_poi(id: String) -> POIData:
	return _pois.get(id, null)

func get_poi_at(cell: Vector2i) -> POIData:
	for poi in _pois.values():
		if poi != null and poi.cell == cell:
			return poi
	return null

## Checks if any POIs should transition from UNDISCOVERED to DISCOVERED (using real FogOfWar only)
func update_discovery(fog: FogOfWar, monster_mgr: Object = null, nav: GridNavigation = null) -> Array[POIData]:
	var newly_discovered: Array[POIData] = []
	if fog == null:
		return newly_discovered

	for poi in _pois.values():
		if poi.state == POIState.UNDISCOVERED and fog.is_explored(poi.cell):
			poi.state = POIState.DISCOVERED
			if monster_mgr != null:
				poi.state = POIState.GUARDED if is_poi_guarded(poi, monster_mgr, nav) else POIState.CLEARED
			newly_discovered.append(poi)
			poi_revealed.emit(poi)
			var em = _get_event_manager()
			if em != null:
				em.notify_poi_discovered(poi.id, poi.name, poi.cell)

	return newly_discovered

func is_poi_guarded(poi: POIData, monster_mgr: Object, nav: GridNavigation = null) -> bool:
	if poi == null or monster_mgr == null:
		return false
	if not monster_mgr.has_method("get_living_monsters"):
		return false
	for m in monster_mgr.get_living_monsters():
		var mc: Vector2i = m.get("cell", Vector2i(-1, -1))
		if IsoMath.grid_distance(poi.cell, mc) > MonsterConfigScript.POI_GUARD_RADIUS_PATH_CELLS:
			continue
		if nav == null:
			return true
		if poi.cell == mc:
			return true
		var p: Array[Vector2i] = nav.find_path(poi.cell, mc)
		if not p.is_empty() and (p.size() - 1) <= MonsterConfigScript.POI_GUARD_RADIUS_PATH_CELLS:
			return true
	return false

func refresh_guard_states(monster_mgr: Object, nav: GridNavigation = null) -> void:
	for poi in _pois.values():
		if poi == null:
			continue
		if poi.state == POIState.UNDISCOVERED or poi.state == POIState.CLAIMED:
			continue
		var guarded: bool = is_poi_guarded(poi, monster_mgr, nav)
		var target_st: int = POIState.GUARDED if guarded else POIState.CLEARED
		if poi.state != target_st:
			poi.state = target_st
			poi_state_changed.emit(poi)

func has_nearby_military_unit(poi: POIData, tactical_mgr: Object, nav: GridNavigation = null) -> bool:
	if poi == null or tactical_mgr == null or not tactical_mgr.has_method("get_all_units"):
		return false
	for u in tactical_mgr.get_all_units():
		if u == null or not is_instance_valid(u) or not bool(u.get("is_alive")):
			continue
		var uc: Vector2i = u.get("current_cell")
		if IsoMath.grid_distance(poi.cell, uc) > MonsterConfigScript.POI_CLAIM_PROXIMITY_PATH_CELLS:
			continue
		if nav == null or poi.cell == uc:
			return true
		var p: Array[Vector2i] = nav.find_path(uc, poi.cell)
		if not p.is_empty() and (p.size() - 1) <= MonsterConfigScript.POI_CLAIM_PROXIMITY_PATH_CELLS:
			return true
	return false

## Claim one-time reward from POI. Supports legacy 2-arg callers and Phase 9 guard/proximity/capacity rules.
func claim_poi_reward(poi_id: String, resource_mgr: Object, tactical_mgr: Object = null, monster_mgr: Object = null, nav: GridNavigation = null, require_phase9_rules: bool = false) -> Dictionary:
	var poi: POIData = get_poi(poi_id)
	if poi == null:
		return {"success": false, "reason": "Địa điểm khám phá không tồn tại"}

	if poi.state == POIState.CLAIMED:
		return {"success": false, "reason": "Phần thưởng đã được thu thập trước đó (chỉ nhận một lần)"}

	if require_phase9_rules:
		if poi.state == POIState.UNDISCOVERED:
			return {"success": false, "reason": "Địa điểm chưa được khám phá"}
		if monster_mgr != null and is_poi_guarded(poi, monster_mgr, nav):
			poi.state = POIState.GUARDED
			return {"success": false, "reason": "Địa điểm vẫn còn quái vật canh giữ"}
		if tactical_mgr != null and not has_nearby_military_unit(poi, tactical_mgr, nav):
			return {"success": false, "reason": "Cần đơn vị quân đội đứng cạnh (<= 1 ô) để thu thập"}

	var source_dict: Dictionary = poi.pending_rewards.duplicate() if poi.reward_claim_initiated else poi.rewards.duplicate()
	poi.reward_claim_initiated = true
	var credited: Dictionary = {}
	var remaining: Dictionary = {}

	if resource_mgr != null:
		for res_id in source_dict.keys():
			var amt: int = int(source_dict[res_id])
			if amt <= 0:
				continue
			var added: int = resource_mgr.add_resource(res_id, amt)
			if added > 0:
				credited[res_id] = added
			if added < amt:
				remaining[res_id] = amt - added

	poi.pending_rewards = remaining
	if remaining.is_empty():
		poi.state = POIState.CLAIMED
		poi_reward_claimed.emit(poi, credited if not credited.is_empty() else poi.rewards)
		return {
			"success": true,
			"partial": false,
			"rewards": credited if not credited.is_empty() else poi.rewards.duplicate(),
			"pending_rewards": {},
			"poi": poi
		}
	else:
		poi.state = POIState.CLEARED
		poi_state_changed.emit(poi)
		return {
			"success": not credited.is_empty(),
			"partial": true,
			"reason": "Kho đầy, phần thưởng còn lại được giữ tại địa điểm",
			"rewards": credited,
			"pending_rewards": remaining.duplicate(),
			"poi": poi
		}

func get_state_label(state: int) -> String:
	match state:
		POIState.UNDISCOVERED: return "Chưa khám phá"
		POIState.DISCOVERED: return "Đã khám phá"
		POIState.GUARDED: return "Đang bị canh giữ"
		POIState.CLEARED: return "Đã dọn sạch (Có thể thu thập)"
		POIState.CLAIMED: return "Đã thu thập (Trống)"
	return "Không xác định"

func _get_event_manager() -> Object:
	var ml = Engine.get_main_loop()
	if ml is SceneTree:
		return ml.root.get_node_or_null("EventManager")
	return null
