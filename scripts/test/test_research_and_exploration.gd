extends SceneTree

const EconomyConfig = preload("res://scripts/economy/economy_config.gd")
const TechTree = preload("res://scripts/research/tech_tree.gd")
const ResearchManager = preload("res://scripts/research/research_manager.gd")
const FogOfWar = preload("res://scripts/world/fog_of_war.gd")
const POIManager = preload("res://scripts/world/poi_manager.gd")
const WorldEventSystem = preload("res://scripts/core/world_event_system.gd")

func _init() -> void:
	print("\n--- Running TestResearchAndExploration (TC-5.1, TC-5.2 & TC-5.3) ---")
	test_research_system_and_bonuses()
	test_fog_of_war_and_poi_discovery()
	test_world_events()
	print("=== TC-5.1, TC-5.2 & TC-5.3 ALL RESEARCH & EXPLORATION TESTS PASSED ===\n")
	quit(0)

func test_research_system_and_bonuses() -> void:
	var res_mgr := MockResourceManager.new(100, 100, 100)
	var research := ResearchManager.new()
	
	# 1. Prerequisite verification: Cannot start food_preservation without crop_rotation
	var check_prereq := research.can_research("food_preservation", res_mgr)
	assert(not check_prereq["valid"], "Cannot research food_preservation before crop_rotation is unlocked")
	print("PASS: Technology prerequisites strictly enforced")
	
	# 2. Start crop_rotation (costs 20 wood, 10 food)
	var start_ok := research.start_research("crop_rotation", res_mgr)
	assert(start_ok, "crop_rotation should successfully start")
	assert(res_mgr.wood_stock == 80, "20 wood must be deducted atomically on research start")
	assert(res_mgr.food_stock == 90, "10 food must be deducted atomically on research start")
	assert(research.active_tech_id == "crop_rotation", "Active tech ID must be crop_rotation")
	print("PASS: Atomic resource deduction on research start verified")
	
	# 3. Only one active project at a time
	var check_concurrent := research.can_research("advanced_tools", res_mgr)
	assert(not check_concurrent["valid"], "Cannot research two technologies simultaneously")
	print("PASS: Single active research project constraint enforced")
	
	# 4. Progress research
	var completed := research.progress_research(6.0, res_mgr) # Halfway (12h needed)
	assert(not completed, "Research must not complete prematurely")
	assert(research.active_progress_hours == 6.0, "Progress must match elapsed hours")
	
	completed = research.progress_research(6.0, res_mgr) # Completed
	assert(completed, "Research must complete after full duration")
	assert(research.is_unlocked("crop_rotation"), "crop_rotation must now be unlocked")
	assert(research.active_tech_id == "", "Active tech must clear after completion")
	print("PASS: Technology completion and state transition verified")
	
	# 5. Food preservation is now eligible
	var check_unlocked_prereq := research.can_research("food_preservation", res_mgr)
	assert(check_unlocked_prereq["valid"], "food_preservation should now be valid to research")
	print("PASS: Dependent technology unlocks upon prerequisite completion")

func test_fog_of_war_and_poi_discovery() -> void:
	var fog := FogOfWar.new(64)
	
	# Initial state: everything is UNEXPLORED
	assert(fog.get_state(Vector2i(10, 10)) == FogOfWar.State.UNEXPLORED, "All cells start UNEXPLORED")
	assert(fog.get_state(Vector2i(32, 32)) == FogOfWar.State.UNEXPLORED, "Center starts UNEXPLORED")
	print("PASS: Initial Fog of War grid initialized to UNEXPLORED")
	
	# Observers update vision around (32, 32) with radius 4
	fog.update_observers([Vector2i(32, 32)], 4)
	assert(fog.get_state(Vector2i(32, 32)) == FogOfWar.State.VISIBLE, "Center must be VISIBLE")
	assert(fog.get_state(Vector2i(34, 32)) == FogOfWar.State.VISIBLE, "Nearby cell must be VISIBLE")
	assert(fog.get_state(Vector2i(45, 45)) == FogOfWar.State.UNEXPLORED, "Distant cell remains UNEXPLORED")
	print("PASS: Active sight radius marks cells as VISIBLE")
	
	# Move observer to (45, 45): old center should degrade to EXPLORED
	fog.update_observers([Vector2i(45, 45)], 4)
	assert(fog.get_state(Vector2i(32, 32)) == FogOfWar.State.EXPLORED, "Previous cell must degrade to EXPLORED")
	assert(fog.get_state(Vector2i(45, 45)) == FogOfWar.State.VISIBLE, "New cell must be VISIBLE")
	print("PASS: 3-state degradation (VISIBLE -> EXPLORED) verified")
	
	# POI Placement and Exploration
	var poi_mgr := POIManager.new()
	var walkable_cells: Array[Vector2i] = []
	for x in range(20, 50):
		for y in range(20, 50):
			walkable_cells.append(Vector2i(x, y))
			
	poi_mgr.generate_pois(12345, walkable_cells, 3)
	var all_pois := poi_mgr.get_all_pois()
	assert(all_pois.size() == 3, "Exactly 3 POIs generated")
	
	var test_poi: POIManager.POIData = all_pois[0]
	assert(test_poi.state == POIManager.POIState.UNDISCOVERED, "POI starts UNDISCOVERED")
	
	# Reveal POI cell in fog
	fog.reveal_circle(test_poi.cell, 2)
	var discovered := poi_mgr.update_discovery(fog)
	assert(discovered.has(test_poi), "POI must be discovered once cell is revealed")
	assert(test_poi.state == POIManager.POIState.DISCOVERED, "POI state transitions to DISCOVERED")
	print("PASS: Fog of War exploration reveals Points of Interest")
	
	# Claim POI reward
	var res_mgr := MockResourceManager.new(0, 0, 0)
	var claim_result := poi_mgr.claim_poi_reward(test_poi.id, res_mgr)
	assert(claim_result["success"], "First claim must succeed")
	assert(test_poi.state == POIManager.POIState.CLAIMED, "POI transitions to CLAIMED")
	assert(res_mgr.total_received > 0, "Rewards must be credited to resource ledger")
	print("PASS: POI reward claimed and credited to storage")
	
	# Re-claim attempt must be rejected
	var second_claim := poi_mgr.claim_poi_reward(test_poi.id, res_mgr)
	assert(not second_claim["success"], "Double-claiming must be strictly rejected")
	print("PASS: Single-claim rule strictly enforced; double-spending rejected")

func test_world_events() -> void:
	var event_system := WorldEventSystem.new(12345)
	var res_mgr := MockResourceManager.new(50, 50, 50)
	var event_mgr := MockEventManager.new()
	
	# Trigger event on day 5 (interval >= 4)
	var ev1 := event_system.check_and_trigger_event(5, res_mgr, event_mgr)
	assert(not ev1.is_empty(), "World event must trigger on day 5")
	assert(event_mgr.dispatched_events.size() == 1, "Event must be dispatched to EventManager")
	print("PASS: Scheduled world event triggered and dispatched successfully")
	
	# Immediate subsequent day (day 6) must NOT trigger due to cooldown
	var ev2 := event_system.check_and_trigger_event(6, res_mgr, event_mgr)
	assert(ev2.is_empty(), "Event cooldown must prevent immediate subsequent triggering")
	print("PASS: Event cooldown interval enforced")

class MockResourceManager extends RefCounted:
	var food_stock: int = 100
	var wood_stock: int = 100
	var stone_stock: int = 100
	var gold_stock: int = 200
	var crystal_stock: int = 20
	var herbs_stock: int = 20
	var metal_stock: int = 20
	var tools_stock: int = 20
	var total_received: int = 0
	
	func _init(f: int, w: int, s: int) -> void:
		food_stock = f
		wood_stock = w
		stone_stock = s
		
	func can_afford(cost: Dictionary) -> bool:
		for res in cost:
			if get_available_stock(res) < cost[res]:
				return false
		return true
		
	func get_available_stock(res: String) -> int:
		match res:
			EconomyConfig.RES_FOOD: return food_stock
			EconomyConfig.RES_WOOD: return wood_stock
			EconomyConfig.RES_STONE: return stone_stock
			EconomyConfig.RES_GOLD: return gold_stock
			EconomyConfig.RES_CRYSTAL: return crystal_stock
			EconomyConfig.RES_HERBS: return herbs_stock
			_: return 50
			
	func consume_resource(res: String, amount: int) -> bool:
		match res:
			EconomyConfig.RES_FOOD: food_stock -= amount
			EconomyConfig.RES_WOOD: wood_stock -= amount
			EconomyConfig.RES_STONE: stone_stock -= amount
			EconomyConfig.RES_GOLD: gold_stock -= amount
			EconomyConfig.RES_CRYSTAL: crystal_stock -= amount
			EconomyConfig.RES_HERBS: herbs_stock -= amount
		return true
		
	func add_resource(_res: String, amount: int) -> int:
		total_received += amount
		return amount
		
	func add_storage_capacity(_res: String, _bonus: int) -> void:
		pass

class MockEventManager extends RefCounted:
	var dispatched_events: Array = []
	func trigger_event(id: String, title: String, desc: String, is_positive: bool, payload: Dictionary) -> void:
		dispatched_events.append({"id": id, "title": title, "desc": desc, "pos": is_positive, "payload": payload})
	func notify_poi_discovered(_id: String, _name: String, _cell: Vector2i) -> void:
		pass
	func notify_poi_claimed(_id: String, _name: String, _rewards: Dictionary) -> void:
		pass
	func notify_tech_unlocked(_id: String, _name: String) -> void:
		pass
