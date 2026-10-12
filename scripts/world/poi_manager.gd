class_name POIManager
extends RefCounted
## Points of Interest (POI) Management System for KINGDOMS UNBOUND.
## Manages deterministic world exploration sites (Ancient Ruins, Abandoned Mines, Sacred Groves).
## Enforces single-claim persistent discovery rewards per GDD Section 9.4.



enum POIState {
	UNDISCOVERED = 0,
	DISCOVERED = 1,
	CLAIMED = 2
}

class POIData:
	var id: String
	var type: String
	var name: String
	var cell: Vector2i
	var state: int = POIState.UNDISCOVERED
	var rewards: Dictionary = {}
	var description: String = ""

var _pois: Dictionary = {} # id -> POIData

signal poi_revealed(poi: POIData)
signal poi_reward_claimed(poi: POIData, rewards: Dictionary)

func generate_pois(seed_val: int, walkable_cells: Array, count: int = 4) -> void:
	_pois.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 7777
	
	var poi_types: Array[Dictionary] = [
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
	
	# Select cells that are sufficiently far from central settlement plaza (distance >= 12)
	var candidate_cells: Array[Vector2i] = []
	var center := Vector2i(32, 32)
	for c in walkable_cells:
		var dist := IsoMath.grid_distance(c, center)
		if dist >= 12 and dist <= 28:
			candidate_cells.append(c)
			
	if candidate_cells.is_empty():
		candidate_cells = walkable_cells.duplicate()
		
	# Shuffle candidate cells deterministically
	for i in range(candidate_cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var temp = candidate_cells[i]
		candidate_cells[i] = candidate_cells[j]
		candidate_cells[j] = temp
		
	for i in range(mini(count, candidate_cells.size())):
		var t_idx := i % poi_types.size()
		var p_info: Dictionary = poi_types[t_idx]
		
		var poi := POIData.new()
		poi.id = "poi_%d" % (i + 1)
		poi.type = p_info["type"]
		poi.name = p_info["name"]
		poi.cell = candidate_cells[i]
		poi.rewards = p_info["rewards"].duplicate()
		poi.description = p_info["desc"]
		poi.state = POIState.UNDISCOVERED
		
		_pois[poi.id] = poi

func get_all_pois() -> Array:
	return _pois.values()

func get_poi(id: String) -> POIData:
	return _pois.get(id, null)

## Checks if any POIs should transition from UNDISCOVERED to DISCOVERED
func update_discovery(fog: FogOfWar) -> Array[POIData]:
	var newly_discovered: Array[POIData] = []
	if fog == null:
		return newly_discovered
		
	for poi in _pois.values():
		if poi.state == POIState.UNDISCOVERED and fog.is_explored(poi.cell):
			poi.state = POIState.DISCOVERED
			newly_discovered.append(poi)
			poi_revealed.emit(poi)
			var em = _get_event_manager()
			if em != null:
				em.notify_poi_discovered(poi.id, poi.name, poi.cell)
				
	return newly_discovered

## Claim one-time reward from POI. Rejects double-claiming.
func claim_poi_reward(poi_id: String, resource_mgr: Object) -> Dictionary:
	var poi: POIData = get_poi(poi_id)
	if poi == null:
		return {"success": false, "reason": "Địa điểm khám phá không tồn tại"}
		
	if poi.state == POIState.CLAIMED:
		return {"success": false, "reason": "Phần thưởng đã được thu thập trước đó (chỉ nhận một lần)"}
		
	poi.state = POIState.CLAIMED
	
	# Atomically credit rewards to central storage
	if resource_mgr != null:
		for res_id in poi.rewards:
			var amt: int = poi.rewards[res_id]
			resource_mgr.call("add_resource", res_id, amt)
			
	poi_reward_claimed.emit(poi, poi.rewards)
	var em = _get_event_manager()
	if em != null:
		em.notify_poi_claimed(poi.id, poi.name, poi.rewards)
		
	return {"success": true, "rewards": poi.rewards, "poi": poi}

func _get_event_manager() -> Object:
	if Engine.has_singleton("EventManager"):
		return Engine.get_singleton("EventManager")
	var loop = Engine.get_main_loop()
	if loop is SceneTree and loop.root.has_node("EventManager"):
		return loop.root.get_node("EventManager")
	return null
